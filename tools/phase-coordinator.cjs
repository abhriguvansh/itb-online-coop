// Restricted, non-resumable two-guest experiment. No public listener or lobby.
const fs=require('node:fs'),net=require('node:net'),crypto=require('node:crypto'),path=require('node:path');
const {canonical}=require('./probe-report.cjs');
const owners=['guest','host','host','guest'];
const ids=['artillery','punch','end-turn','cannon-next'];
function expected(session,revision,state){
  const r={session,encounter:'artillery-checkpoint',phase:state.phase,revision,witness:state.witness,id:ids[revision]};
  if(revision===2)return {...r,kind:'end-turn',confirmUnused:true};
  const values=[['move','artillery',0,3,1,1],['lab-punch','combat',3,3,2,3],null,['move','cannon',1,5,0,3]][revision];
  return {...r,kind:values[0],actor:values[1],fromX:values[2],fromY:values[3],toX:values[4],toY:values[5]};
}
class PhaseCoordinator{
  constructor(session,send,record){this.session=session;this.send=send;this.record=record;this.stage=0;this.mode='arming';this.states={};this.receipts={};this.consents={};this.complete={};}
  require(ok,reason){if(!ok)throw Error(reason);}
  context(m,revision){
    this.require(m.revision===revision && m.phase===(revision<3?'player2':'player3'),'wrong-phase-or-revision');
    this.require(typeof m.witness==='string' && m.witness.length>0 && Buffer.byteLength(m.witness)<=65536,'invalid-witness');
    const state=JSON.parse(m.witness);
    this.require(state.schema==='itb-observation-v1' && Array.isArray(state.unavailable) && state.unavailable.length===0,'incomplete-state');
  }
  frame(kind,peer='-',id='-'){
    const state=this.states.host;
    return {kind,session:this.session,peer,revision:this.stage,phase:state.phase,id,witness:state.witness};
  }
  both(frame){for(const peer of ['host','guest'])this.send(peer,frame);}
  advance(){
    this.require(this.states.host.witness===this.states.guest.witness,'observed-state-divergence');
    this.record({type:'barrier',revision:this.stage,witness:this.states.host.witness,fullStateProof:false});
    if(this.stage===4){this.mode='finishing';this.both(this.frame('DONE'));return;}
    if(this.stage===2){this.mode='readiness';this.both(this.frame('READY','-','end-turn'));return;}
    this.mode='proposal';this.send(owners[this.stage],this.frame('PROPOSE',owners[this.stage],ids[this.stage]));
  }
  receive(peer,m){
    this.require((peer==='host'||peer==='guest') && m.session===this.session && m.peer===peer,'peer-binding');
    this.require(m.type!=='stopped','game-stopped:'+String(m.reason).slice(0,200));
    if(m.type==='armed'){
      this.require(this.mode==='arming' && !this.states[peer] && m.probe==='0.10.0','unexpected-arm');
      this.context(m,0);this.states[peer]={phase:m.phase,witness:m.witness};
      if(this.states.host && this.states.guest)this.advance();return;
    }
    if(m.type==='ready'){
      this.require(this.mode==='readiness' && !this.consents[peer] && m.confirmUnused===true,'unexpected-readiness');
      this.context(m,2);this.require(m.witness===this.states[peer].witness,'stale-readiness');this.consents[peer]=true;
      if(this.consents.host && this.consents.guest){
        for(const origin of ['host','guest'])this.both(this.frame('CONSENT',origin,'end-turn'));
        this.mode='proposal';this.send('host',this.frame('PROPOSE','host','end-turn'));
      }return;
    }
    if(m.type==='proposal'){
      this.require(this.mode==='proposal' && owners[this.stage]===peer,'unexpected-proposal');
      this.require(canonical(m.request)===canonical(expected(this.session,this.stage,this.states.host)),'proposal-conflict');
      this.mode='executing';this.receipts={};this.record({type:'dispatch',origin:peer,request:m.request});
      this.both(this.frame('EXEC',peer,ids[this.stage]));return;
    }
    if(m.type==='observed'){
      this.require(this.mode==='executing' && !this.receipts[peer] && m.id===ids[this.stage],'unexpected-outcome');
      this.context(m,this.stage+1);
      this.require(m.native?.guardActive===true && m.native?.sessionState===1 && m.native?.releaseFailed===false,'protection-lost');
      this.receipts[peer]=m;
      if(this.receipts.host && this.receipts.guest){
        for(const p of ['host','guest'])this.states[p]={phase:this.receipts[p].phase,witness:this.receipts[p].witness};
        this.stage++;this.advance();
      }return;
    }
    if(m.type==='complete'){
      this.require(this.mode==='finishing' && !this.complete[peer] && m.revision===4 && m.witness===this.states[peer].witness,'unexpected-completion');
      this.require(m.native?.guardActive===true && m.native?.sessionState===1 && m.native?.releaseFailed===false,'completion-protection-lost');
      this.complete[peer]=true;
      if(this.complete.host && this.complete.guest){this.mode='complete';this.record({type:'complete',revision:4,fullStateProof:false});}
      return;
    }
    throw Error('unknown-message');
  }
}
function main(root){
  if(!root)throw Error('Usage: node tools/phase-coordinator.cjs PRIVATE_NEW_SESSION_DIRECTORY');
  root=path.resolve(root);fs.mkdirSync(root,{recursive:false});
  const session=crypto.randomUUID(),tokens={host:crypto.randomBytes(24).toString('hex'),guest:crypto.randomBytes(24).toString('hex')};
  const peers={},sockets=new Set(),created=Date.now();let stopped=false,started=0;
  const record=value=>fs.appendFileSync(path.join(root,'events.jsonl'),JSON.stringify({at:new Date().toISOString(),...value})+'\n');
  const send=(peer,value)=>{if(!peers[peer] || peers[peer].destroyed)throw Error('peer-unavailable');peers[peer].write(JSON.stringify(value)+'\n');};
  const core=new PhaseCoordinator(session,send,record);
  function stop(reason,success=false){
    if(stopped)return;stopped=true;clearInterval(timer);record({type:success?'passed':'stopped',reason});
    if(!success)for(const socket of sockets)if(!socket.destroyed)socket.write(JSON.stringify({kind:'STOP',session,peer:'-',revision:core.stage,phase:'-',id:'-',witness:''})+'\n');
    server.close();setTimeout(()=>{for(const socket of sockets)socket.destroy();process.exitCode=success?0:1;},500);
  }
  const server=net.createServer(socket=>{
    sockets.add(socket);let peer=null,buffer='',count=0;socket.setEncoding('utf8');socket.setNoDelay(true);socket.setTimeout(15000);
    socket.on('timeout',()=>stop('connection-timeout'));
    socket.on('error',()=>stop('connection-error'));
    socket.on('close',()=>{sockets.delete(socket);if(!stopped)stop('connection-closed');});
    socket.on('data',chunk=>{
      try{
        buffer+=chunk;if(Buffer.byteLength(buffer)>140000)throw Error('oversized-frame');
        let cut;while((cut=buffer.indexOf('\n'))>=0){
          if(++count>1024)throw Error('message-limit');
          const m=JSON.parse(buffer.slice(0,cut));buffer=buffer.slice(cut+1);
          if(!peer){
            if(m.type!=='hello'||m.session!==session||!Object.hasOwn(tokens,m.peer)||m.token!==tokens[m.peer]||peers[m.peer])throw Error('authentication-failed');
            peer=m.peer;peers[peer]=socket;if(!started)started=Date.now();record({type:'connected',peer});continue;
          }
          if(m.type==='pong'){if(m.session!==session)throw Error('pong-session');continue;}
          record({type:'received',peer,message:m});core.receive(peer,m);
          if(core.mode==='complete')stop('both-real-game-outcomes-agree',true);
        }
      }catch(e){stop(e.message);}
    });
  });
  const timer=setInterval(()=>{
    if(!started && Date.now()-created>600000){stop('startup-deadline');return;}
    if(started && Date.now()-started>180000){stop('experiment-deadline');return;}
    for(const peer of Object.keys(peers))if(!peers[peer].destroyed)send(peer,{kind:'PING',session,peer:'-',revision:core.stage,phase:'-',id:'-',witness:''});
  },1000);
  server.on('error',e=>stop(e.message));
  server.listen(0,'127.0.0.1',()=>{
    for(const peer of ['host','guest'])fs.writeFileSync(path.join(root,peer+'.json'),JSON.stringify({session,peer,token:tokens[peer],host:'10.0.2.2',port:server.address().port},null,2));
    record({type:'listening',session,port:server.address().port});console.log('Private phase coordinator ready; games must be explicitly armed.');
  });
  process.on('SIGINT',()=>stop('operator-stop'));
}
module.exports={PhaseCoordinator,expected};
if(require.main===module){try{main(process.argv[2]);}catch(e){console.error(e.message);process.exitCode=1;}}
