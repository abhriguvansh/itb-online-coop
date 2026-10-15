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
  constructor(session,send,record,interactive=false,now=()=>performance.now(),phaseRun=false,repeatedTurns=false){this.repeatedTurns=repeatedTurns;this.turn=2;this.phaseRun=phaseRun;this.now=now;this.interactive=interactive;this.limit=interactive&&!phaseRun?2:4;this.used=new Set();this.session=session;this.send=send;this.record=record;this.stage=0;this.mode='arming';this.states={};this.receipts={};this.consents={};this.complete={};}
  require(ok,reason){if(!ok)throw Error(reason);}
  tick(){this.require(this.mode!=='preparing'||this.now()<this.prepareDeadline,'game-prepare-timeout');}
  context(m,revision){
    this.require(m.revision===revision && m.phase===(this.repeatedTurns?'player'+(this.turn+(revision===this.stage+1&&this.pendingKind==='end-turn'?1:0)):((this.interactive&&!this.phaseRun)||revision<3?'player2':'player3')),'wrong-phase-or-revision');
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
    if(!this.repeatedTurns&&this.stage===this.limit){this.mode='finishing';this.both(this.frame('DONE'));return;}
    this.require(this.stage<32,'experiment-command-limit');
    this.consents={};
    if(this.interactive){this.mode=!this.repeatedTurns&&this.phaseRun&&this.stage===2?'readiness':'proposal';this.both(this.frame(this.mode==='readiness'?'READY':'INPUT','-',this.mode==='readiness'?'end-turn':'-'));return;}
    if(this.stage===2){this.mode='readiness';this.both(this.frame('READY','-','end-turn'));return;}
    this.mode='proposal';this.send(owners[this.stage],this.frame('PROPOSE',owners[this.stage],ids[this.stage]));
  }
  receive(peer,m){
    this.tick();
    this.require((peer==='host'||peer==='guest') && m.session===this.session && m.peer===peer,'peer-binding');
    this.require(m.type!=='stopped','game-stopped:'+String(m.reason).slice(0,200));
    if(m.type==='armed'){
      this.require(this.mode==='arming' && !this.states[peer] && m.probe==='0.15.0' && m.interactive===this.interactive && (m.phaseRun===true)===this.phaseRun && (m.repeatedTurns===true)===this.repeatedTurns,'unexpected-arm');
      this.context(m,0);this.states[peer]={phase:m.phase,witness:m.witness};
      if(this.states.host && this.states.guest)this.advance();return;
    }
    if(m.type==='ready'){
      if(this.repeatedTurns&&this.mode==='proposal'){this.mode='readiness';this.both(this.frame('READY','-','end-turn-'+this.stage));}
      this.require(this.mode==='readiness' && !this.consents[peer] && m.confirmUnused===true,'unexpected-readiness');
      this.context(m,this.repeatedTurns?this.stage:2);this.require(m.witness===this.states[peer].witness,'stale-readiness');this.consents[peer]=true;
      if(this.consents.host && this.consents.guest){
        for(const origin of ['host','guest'])this.both(this.frame('CONSENT',origin,this.repeatedTurns?'end-turn-'+this.stage:'end-turn'));
        if(this.phaseRun){this.prepare('host',this.repeatedTurns?{session:this.session,encounter:'artillery-checkpoint',phase:this.states.host.phase,revision:this.stage,witness:this.states.host.witness,id:'end-turn-'+this.stage,kind:'end-turn',confirmUnused:true}:expected(this.session,2,this.states.host));}
        else {this.mode='proposal';this.send('host',this.frame('PROPOSE','host','end-turn'));}
      }return;
    }
    if(m.type==='proposal'){
      this.require(this.mode==='proposal' && (this.interactive || owners[this.stage]===peer),'unexpected-proposal');
      if(this.interactive){
        const r=m.request,entities={combat:{peer:'host',id:0},cannon:{peer:'guest',id:1},artillery:{peer:'guest',id:2}};
        this.require(r && Object.hasOwn(entities,r.actor) && entities[r.actor].peer===peer,'actor-not-owned');
        this.context(r,this.stage);
        if(this.phaseRun&&!this.repeatedTurns)this.require((this.stage===0&&r.kind==='move'&&r.actor==='artillery')||(this.stage===1&&r.kind==='lab-punch'&&r.actor==='combat'&&r.fromX===3&&r.fromY===3&&r.toX===2&&r.toY===3)||(this.stage===3&&r.kind==='move'&&r.actor==='cannon'),'unsupported-phase-action');
        this.require(r.kind==='move'||r.kind==='lab-punch'||(this.repeatedTurns&&r.kind==='basic-attack'),'unsupported-action');
        const state=this.states.host,shape={session:this.session,encounter:'artillery-checkpoint',phase:state.phase,revision:this.stage,witness:state.witness,id:r.id,kind:this.repeatedTurns?r.kind:this.phaseRun&&this.stage===1?'lab-punch':'move',actor:r.actor,fromX:r.fromX,fromY:r.fromY,toX:r.toX,toY:r.toY};
        this.require(typeof r.id==='string' && /^(move|attack)-(host|guest)-[1-9][0-9]{0,2}$/.test(r.id) && canonical(r)===canonical(shape),'invalid-move-envelope');
        this.require(!this.used.has(peer+'/'+r.id),'duplicate-request');
        this.require(['fromX','fromY','toX','toY'].every(k=>Number.isInteger(r[k])&&r[k]>=0&&r[k]<=7),'invalid-coordinate');
        const pawn=JSON.parse(state.witness).pawns.find(p=>p.localId===entities[r.actor].id);
        this.require(pawn && pawn.position.x===r.fromX && pawn.position.y===r.fromY && (r.kind==='move'?!pawn.movementSpent:pawn.active===true),'stale-actor');
        this.used.add(peer+'/'+r.id);
      }else this.require(canonical(m.request)===canonical(expected(this.session,this.stage,this.states.host)),'proposal-conflict');
      if(this.interactive){
        this.prepare(peer,m.request);return;
      }
      this.dispatch(peer,m.request);return;
    }
    if(m.type==='prepared'){
      this.require(this.interactive && this.mode==='preparing' && !this.prepared[peer],'unexpected-prepared');
      this.require(m.origin===this.proposal.peer && canonical(m.request)===canonical(this.proposal.request),'prepared-request-conflict');
      this.require(m.native?.guardActive===true && m.native?.sessionState===1 && m.native?.releaseFailed===false && m.native?.armed===false && m.native?.pressed===false,'prepared-protection-lost');
      this.prepared[peer]=true;
      if(this.prepared.host && this.prepared.guest)this.dispatch(this.proposal.peer,this.proposal.request);
      return;
    }
    if(m.type==='observed'){
      this.require(this.mode==='executing' && !this.receipts[peer] && m.id===this.pendingId,'unexpected-outcome');
      this.context(m,this.stage+1);
      this.require(m.native?.guardActive===true && m.native?.sessionState===1 && m.native?.releaseFailed===false,'protection-lost');
      this.receipts[peer]=m;
      if(this.receipts.host && this.receipts.guest){
        for(const p of ['host','guest'])this.states[p]={phase:this.receipts[p].phase,witness:this.receipts[p].witness};
        if(this.repeatedTurns&&this.pendingKind==='end-turn')this.turn++;
        this.stage++;this.advance();
      }return;
    }
    if(m.type==='complete'){
      this.require(this.mode==='finishing' && !this.complete[peer] && m.revision===this.limit && m.witness===this.states[peer].witness,'unexpected-completion');
      this.require(m.native?.guardActive===true && m.native?.sessionState===1 && m.native?.releaseFailed===false,'completion-protection-lost');
      this.complete[peer]=true;
      if(this.complete.host && this.complete.guest){this.mode='complete';this.record({type:'complete',revision:this.limit,fullStateProof:false});}
      return;
    }
    throw Error('unknown-message');
  }
  prepare(peer,request){
    this.mode='preparing';this.prepared={};this.prepareDeadline=this.now()+3000;this.proposal={peer,request};
    this.record({type:'prepare',origin:peer,request});
    this.both({...this.frame('PREPARE',peer,request.id),...(request.kind==='end-turn'?{}:{move:request})});
  }
  dispatch(peer,request){
    this.mode='executing';this.receipts={};this.record({type:'dispatch',origin:peer,request});
    this.pendingId=request.id;this.pendingKind=request.kind;
    this.both({...this.frame('EXEC',peer,request.id),...(this.interactive&&request.kind!=='end-turn'?{move:request}:{})});
  }
}
function main(root,interactive=false,phaseRun=false,repeatedTurns=false){
  if(!root)throw Error('Usage: node tools/phase-coordinator.cjs PRIVATE_NEW_SESSION_DIRECTORY');
  root=path.resolve(root);fs.mkdirSync(root,{recursive:false});
  const session=crypto.randomUUID(),tokens={host:crypto.randomBytes(24).toString('hex'),guest:crypto.randomBytes(24).toString('hex')};
  const peers={},sockets=new Set(),created=Date.now();let stopped=false,started=0;
  const record=value=>fs.appendFileSync(path.join(root,'events.jsonl'),JSON.stringify({at:new Date().toISOString(),...value})+'\n');
  const send=(peer,value)=>{if(!peers[peer] || peers[peer].destroyed)throw Error('peer-unavailable');peers[peer].write(JSON.stringify(value)+'\n');};
  const core=new PhaseCoordinator(session,send,record,interactive,undefined,phaseRun,repeatedTurns);
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
          if(++count>(repeatedTurns?2048:1024))throw Error('message-limit');
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
    try{core.tick();}catch(e){stop(e.message);return;}
    if(!started && Date.now()-created>600000){stop('startup-deadline');return;}
    if(started && Date.now()-started>(repeatedTurns?1500000:interactive?600000:180000)){stop('experiment-deadline');return;}
    for(const peer of Object.keys(peers))if(!peers[peer].destroyed)send(peer,{kind:'PING',session,peer:'-',revision:core.stage,phase:'-',id:'-',witness:''});
  },1000);
  server.on('error',e=>stop(e.message));
  server.listen(0,'127.0.0.1',()=>{
    for(const peer of ['host','guest'])fs.writeFileSync(path.join(root,peer+'.json'),JSON.stringify({session,peer,token:tokens[peer],host:'10.0.2.2',port:server.address().port,interactive,phaseRun,repeatedTurns},null,2));
    record({type:'listening',session,port:server.address().port});console.log('Private phase coordinator ready; games must be explicitly armed.');
  });
  process.on('SIGINT',()=>stop('operator-stop'));
}
module.exports={PhaseCoordinator,expected};
if(require.main===module){try{main(process.argv[2],['--interactive','--interactive-phase','--repeated-turns'].includes(process.argv[3]),['--interactive-phase','--repeated-turns'].includes(process.argv[3]),process.argv[3]==='--repeated-turns');}catch(e){console.error(e.message);process.exitCode=1;}}
