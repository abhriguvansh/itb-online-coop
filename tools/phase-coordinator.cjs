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
  constructor(session,send,record,interactive=false,now=()=>performance.now(),phaseRun=false,repeatedTurns=false,terminalCheckpoint=false,deployment=false,fullMission=false){this.fullMission=fullMission;this.deployment=deployment;this.terminalCheckpoint=terminalCheckpoint;this.repeatedTurns=repeatedTurns;this.turn=deployment?0:terminalCheckpoint?4:2;this.phaseRun=phaseRun;this.now=now;this.interactive=interactive;this.limit=deployment?5:interactive&&!phaseRun?2:4;this.used=new Set();this.session=session;this.send=send;this.record=record;this.stage=0;this.mode='arming';this.states={};this.receipts={};this.consents={};this.complete={};}
  require(ok,reason){if(!ok)throw Error(reason);}
  tick(){this.require(this.mode!=='preparing'||this.now()<this.prepareDeadline,'game-prepare-timeout');this.require(!this.spawn||this.now()<this.spawn.deadline,'spawn-prepare-timeout');this.require(!this.result||this.mode==='complete'||this.now()<this.result.deadline,'mission-result-timeout');}
  resultReceive(peer,m){
    this.require(this.repeatedTurns&&this.pendingKind==='end-turn'&&this.turn===(this.fullMission?3:4)&&!this.spawn,'result-outside-final-end-turn');
    this.require(m.revision===this.stage&&m.phase===this.states.host.phase&&m.id===this.pendingId,'result-stale-context');
    this.require(m.native?.guardActive===true&&m.native?.sessionState===1&&m.native?.releaseFailed===false,'result-protection-lost');
    this.require(typeof m.witness==='string'&&Buffer.byteLength(m.witness)<=65536&&!/[\r\n]/.test(m.witness),'result-invalid-witness');
    const state=JSON.parse(m.witness);
    if(m.type==='result_prepared'){
      this.require(this.mode==='executing'||this.mode==='result-preparing','result-unexpected-preparation');
      if(!this.result){this.result={before:{},after:{},deadline:this.now()+90000};this.mode='result-preparing';}
      this.require(!this.result.before[peer],'result-duplicate-preparation');
      this.require(state.schema==='itb-observation-v1'&&state.unavailable?.length===0&&Array.isArray(state.pawns)&&state.pawns.every(p=>p.team!==6||p.dead),'result-retreat-incomplete');
      this.result.before[peer]=m.witness;
      if(this.result.before.host&&this.result.before.guest){
        this.require(this.result.before.host===this.result.before.guest,'result-precondition-divergence');
        this.mode='result-executing';this.result.deadline=this.now()+30000;
        this.record({type:'result_prepared_barrier',revision:this.stage,witness:m.witness,fullStateProof:false});
        this.both({...this.frame('RESULTCONTINUE','-',this.pendingId),witness:m.witness});
      }return;
    }
    this.require(m.type==='result_observed'&&this.mode==='result-executing'&&!this.result.after[peer],'result-unexpected-outcome');
    this.require(state.schema==='itb-mission-result-v1'&&state.coverage==='partial-result-only'&&state.region===(this.fullMission?1:2)&&state.regionState===2&&state.mission===''&&Number.isInteger(state.grid)&&state.grid>0&&Number.isInteger(state.reputation)&&state.reputation>=0,'result-uncommitted-state');
    this.require(Array.isArray(state.pilots)&&state.pilots.length===3&&state.pilots.every((p,i)=>p.slot===i&&typeof p.id==='string'&&Number.isInteger(p.experience)&&p.experience>=0&&Number.isInteger(p.level)&&p.level>=0),'result-incomplete-pilots');
    this.require(Array.isArray(state.objectives)&&state.objectives.length===2&&state.objectives.every((v,i)=>v.slot===i&&typeof v.text==='string'&&v.text.length>0&&Number.isInteger(v.value)&&v.value>=0&&Number.isInteger(v.potential)&&v.potential>=v.value)&&(this.fullMission||state.objectives.every(v=>v.value===1&&v.potential===1)&&state.objectives[0].text==='Mission_Artillery_Obj'&&state.objectives[1].text==='Bonus_Simple_Asset'),'result-incomplete-objectives');
    this.result.after[peer]=m.witness;
    if(this.result.after.host&&this.result.after.guest){
      this.require(this.result.after.host===this.result.after.guest,'result-outcome-divergence');this.mode='result-finishing';
      this.record({type:'result_committed_barrier',revision:this.stage+1,witness:m.witness,fullStateProof:false});
      this.both({...this.frame('RESULTDONE','-',this.pendingId),witness:m.witness});
    }
  }
  spawnReceive(peer,m){
    this.require(this.mode==='executing'&&((this.repeatedTurns&&this.pendingKind==='end-turn')||(this.deployment&&this.pendingKind==='deployment-confirm')),'spawn-outside-end-turn');
    this.require(m.revision===this.stage&&m.phase===this.states.host.phase&&Number.isInteger(m.index)&&m.index===(this.spawnIndex||0)+1&&m.index<=32,'spawn-stale-context');
    this.require(m.native?.guardActive===true&&m.native?.sessionState===1&&m.native?.releaseFailed===false,'spawn-protection-lost');
    this.require(typeof m.witness==='string'&&Buffer.byteLength(m.witness)<=65536&&!/[\r\n]/.test(m.witness),'spawn-invalid-witness');
    const state=JSON.parse(m.witness);
    this.require(state.board?.schema==='itb-observation-v1'&&state.board.unavailable?.length===0&&typeof state.spawner==='string','spawn-incomplete-state');
    const frame=(kind,witness)=>({...this.frame(kind,'host','spawn-'+m.index),witness});
    if(m.type==='spawn_prepare'){
      if(!this.spawn)this.spawn={mode:'prepare',before:{},deadline:this.now()+20000};
      const p=this.spawn;this.require(p.mode==='prepare'&&!p.before[peer],'spawn-duplicate-prepare');p.before[peer]=m.witness;
      if(p.before.host&&p.before.guest){
        this.require(p.before.host===p.before.guest,'spawn-precondition-divergence');p.mode='select';
        this.record({type:'spawn_prepared',index:m.index,revision:this.stage,witness:m.witness});
        this.send('host',frame('SPAWNSELECT',m.witness));
      }return;
    }
    const p=this.spawn;this.require(p,'spawn-not-prepared');
    if(m.type==='spawn_selected'){
      this.require(peer==='host'&&p.mode==='select','spawn-unauthorized-selection');
      this.require(typeof m.pawnType==='string'&&/^[A-Za-z0-9_]{1,128}$/.test(m.pawnType)&&Number.isInteger(m.pawnId)&&m.pawnId>=0&&m.pawnId<=2147483647,'spawn-invalid-pawn');
      this.require([m.x,m.y].every(n=>Number.isInteger(n)&&n>=0&&n<=7),'spawn-invalid-location');
      this.require(Array.isArray(m.calls)&&m.calls.length<=128&&m.calls.every(c=>Number.isInteger(c.limit)&&c.limit>0&&c.limit<=2147483647&&Number.isInteger(c.value)&&c.value>=0&&c.value<c.limit),'spawn-invalid-random');
      this.require(typeof m.afterSpawner==='string'&&!/[\r\n]/.test(m.afterSpawner)&&m.afterSpawner===state.spawner,'spawn-invalid-bookkeeping');
      p.after=m.witness;p.mode='apply';
      const transcript=m.calls.map(c=>c.limit+','+c.value+';').join('');
      const body=[`${m.pawnType}|${m.pawnId}|${m.x}|${m.y}|${transcript}`,m.afterSpawner,p.before.guest].join('\n');
      this.require(Buffer.byteLength(body)<=65536,'spawn-frame-size');
      this.record({type:'spawn_selected',index:m.index,revision:this.stage,pawnType:m.pawnType,pawnId:m.pawnId,x:m.x,y:m.y,calls:m.calls});
      this.send('guest',frame('SPAWNAPPLY',body));return;
    }
    this.require(m.type==='spawn_applied'&&peer==='guest'&&p.mode==='apply','spawn-unexpected-outcome');
    this.require(m.witness===p.after,'spawn-outcome-divergence');
    this.record({type:'spawn_barrier',index:m.index,revision:this.stage,witness:m.witness,fullStateProof:false});
    this.both(frame('SPAWNRELEASE',m.witness));this.spawnIndex=m.index;this.spawn=null;
  }
  context(m,revision){
    const next=revision===this.stage+1;
    const turn=next&&this.pendingKind==='deployment-confirm'?1:this.turn+(next&&this.pendingKind==='end-turn'?1:0);
    const phase=this.deployment&&revision<4?'deployment':this.fullMission||this.repeatedTurns?'player'+turn:this.deployment?'player1':((this.interactive&&!this.phaseRun)||revision<3?'player2':'player3');
    this.require(m.revision===revision && m.phase===phase,'wrong-phase-or-revision');
    this.require(typeof m.witness==='string' && m.witness.length>0 && Buffer.byteLength(m.witness)<=65536,'invalid-witness');
    const state=JSON.parse(m.witness);
    this.require(state.schema==='itb-observation-v1' && Array.isArray(state.unavailable) && state.unavailable.length===0,'incomplete-state');
    if(this.deployment){
      this.require(state.mission==='Mission_Tides'&&state.turn===(revision<4?0:this.fullMission?Number(m.phase.slice(6)):1)&&state.team===(revision>=4?1:6)&&state.deployment?.inProgress===(revision<4)&&state.deployment.phase===(revision>=4?2:0)&&state.deployment.mechs?.length===3,'incomplete-deployment-state');
      this.require(Array.isArray(state.initialChoices)&&state.initialChoices.length===19&&state.initialChoices.every((v,i)=>v.kind===(i<17?'ai-constructor':i===17?'pod-delivery':'pod-select')&&v.limit===(i<17?32768:i===17?3:9)&&Number.isInteger(v.value)&&v.value>=0&&v.value<=32767),'incomplete-initial-choices');
    }
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
    if(this.interactive){this.mode=!this.deployment&&!this.repeatedTurns&&this.phaseRun&&this.stage===2?'readiness':'proposal';this.both(this.frame(this.mode==='readiness'?'READY':'INPUT','-',this.mode==='readiness'?'end-turn':'-'));return;}
    if(this.stage===2){this.mode='readiness';this.both(this.frame('READY','-','end-turn'));return;}
    this.mode='proposal';this.send(owners[this.stage],this.frame('PROPOSE',owners[this.stage],ids[this.stage]));
  }
  receive(peer,m){
    this.tick();
    this.require((peer==='host'||peer==='guest') && m.session===this.session && m.peer===peer,'peer-binding');
    this.require(m.type!=='stopped','game-stopped:'+String(m.reason).slice(0,200));
    if(m.type==='result_prepared'||m.type==='result_observed'){this.resultReceive(peer,m);return;}
    if(['spawn_prepare','spawn_selected','spawn_applied'].includes(m.type)){this.spawnReceive(peer,m);return;}
    if(m.type==='armed'){
      this.require(this.mode==='arming' && !this.states[peer] && m.probe==='0.25.0' && m.interactive===this.interactive && (m.phaseRun===true)===this.phaseRun && (m.repeatedTurns===true)===this.repeatedTurns && (m.terminalCheckpoint===true)===this.terminalCheckpoint && (m.deployment===true)===this.deployment && (m.fullMission===true)===this.fullMission,'unexpected-arm');
      this.context(m,0);this.states[peer]={phase:m.phase,witness:m.witness};
      if(this.states.host && this.states.guest)this.advance();return;
    }
    if(m.type==='ready'){
      if(this.deployment&&this.stage<4){
        this.require(this.stage===3&&m.confirmDeployment===true&&m.confirmUnused===undefined,'unexpected-deployment-readiness');
        if(this.mode==='proposal'){this.mode='readiness';this.both(this.frame('READY','-','deployment-confirm-3'));}
        this.require(this.mode==='readiness'&&!this.consents[peer],'unexpected-readiness');this.context(m,3);
        this.require(m.witness===this.states[peer].witness,'stale-readiness');this.consents[peer]=true;
        if(this.consents.host&&this.consents.guest){
          for(const origin of ['host','guest'])this.both(this.frame('CONSENT',origin,'deployment-confirm-3'));
          this.prepare('host',{session:this.session,encounter:'artillery-checkpoint',phase:'deployment',revision:3,witness:this.states.host.witness,id:'deployment-confirm-3',kind:'deployment-confirm',confirmDeployment:true});
        }return;
      }
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
        if(this.deployment&&(!this.fullMission||this.stage<4))this.require(this.stage<3?r.kind==='deploy'&&r.actor===['combat','cannon','artillery'][this.stage]:this.stage===4&&r.kind==='move'&&r.actor==='cannon','unsupported-deployment-order');
        else if(!this.deployment&&this.phaseRun&&!this.repeatedTurns)this.require((this.stage===0&&r.kind==='move'&&r.actor==='artillery')||(this.stage===1&&r.kind==='lab-punch'&&r.actor==='combat'&&r.fromX===3&&r.fromY===3&&r.toX===2&&r.toY===3)||(this.stage===3&&r.kind==='move'&&r.actor==='cannon'),'unsupported-phase-action');
        this.require(this.deployment&&(!this.fullMission||this.stage<4)?(this.stage<3?r.kind==='deploy':r.kind==='move'):r.kind==='move'||r.kind==='lab-punch'||(this.repeatedTurns&&['basic-attack','repair'].includes(r.kind)),'unsupported-action');
        this.require(r.kind!=='repair'||r.fromX===r.toX&&r.fromY===r.toY,'repair-must-target-self');
        const state=this.states.host,shape={session:this.session,encounter:'artillery-checkpoint',phase:state.phase,revision:this.stage,witness:state.witness,id:r.id,kind:this.deployment&&(!this.fullMission||this.stage<4)?(this.stage<3?'deploy':'move'):this.repeatedTurns?r.kind:this.phaseRun&&this.stage===1?'lab-punch':'move',actor:r.actor,fromX:r.fromX,fromY:r.fromY,toX:r.toX,toY:r.toY};
        this.require(typeof r.id==='string' && /^(move|attack|repair)-(host|guest)-[1-9][0-9]{0,2}$/.test(r.id) && canonical(r)===canonical(shape),'invalid-move-envelope');
        this.require(!this.used.has(peer+'/'+r.id),'duplicate-request');
        this.require(['fromX','fromY','toX','toY'].every(k=>Number.isInteger(r[k])&&(this.deployment&&this.stage<3&&k.startsWith('from')?r[k]===-1:r[k]>=0&&r[k]<=7)),'invalid-coordinate');
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
      this.require(!this.spawn,'spawn-unfinished-at-phase-boundary');
      this.require(this.mode==='executing' && !this.receipts[peer] && m.id===this.pendingId,'unexpected-outcome');
      this.context(m,this.stage+1);
      this.require(m.native?.guardActive===true && m.native?.sessionState===1 && m.native?.releaseFailed===false,'protection-lost');
      this.receipts[peer]=m;
      if(this.receipts.host && this.receipts.guest){
        for(const p of ['host','guest'])this.states[p]={phase:this.receipts[p].phase,witness:this.receipts[p].witness};
        if(this.pendingKind==='deployment-confirm')this.turn=1;
        if(this.repeatedTurns&&this.pendingKind==='end-turn')this.turn++;
        this.stage++;this.advance();
      }return;
    }
    if(m.type==='complete'){
      if(this.mode==='result-finishing'){
        this.require(!this.complete[peer]&&m.revision===this.stage&&m.phase===this.states.host.phase&&m.id===this.pendingId&&m.witness===this.result.after[peer],'result-unexpected-completion');
        this.require(m.native?.guardActive===true&&m.native?.sessionState===1&&m.native?.releaseFailed===false,'result-completion-protection-lost');
        this.complete[peer]=true;
        if(this.complete.host&&this.complete.guest){this.mode='complete';this.record({type:'complete',revision:this.stage+1,terminal:true,fullStateProof:false});}return;
      }
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
    this.both({...this.frame('PREPARE',peer,request.id),...(['end-turn','deployment-confirm'].includes(request.kind)?{}:{move:request})});
  }
  dispatch(peer,request){
    this.mode='executing';this.receipts={};this.record({type:'dispatch',origin:peer,request});
    this.pendingId=request.id;this.pendingKind=request.kind;
    this.both({...this.frame('EXEC',peer,request.id),...(this.interactive&&!['end-turn','deployment-confirm'].includes(request.kind)?{move:request}:{})});
  }
}
function main(root,interactive=false,phaseRun=false,repeatedTurns=false,terminalCheckpoint=false,fixedCombatFixture=false,deployment=false,fullMission=false,liveBootstrap=false,nativeTransport=false){
  if(!root)throw Error('Usage: node tools/phase-coordinator.cjs PRIVATE_NEW_SESSION_DIRECTORY');
  root=path.resolve(root);fs.mkdirSync(root,{recursive:false});
  const session=crypto.randomUUID(),tokens={host:crypto.randomBytes(24).toString('hex'),guest:crypto.randomBytes(24).toString('hex')};
  const peers={},sockets=new Set(),created=Date.now();let stopped=false,started=0;
  const record=value=>fs.appendFileSync(path.join(root,'events.jsonl'),JSON.stringify({at:new Date().toISOString(),...value})+'\n');
  const encode=value=>nativeTransport?require('./game-frame.cjs').packet(value):JSON.stringify(value)+'\n';
  const send=(peer,value)=>{if(!peers[peer] || peers[peer].destroyed)throw Error('peer-unavailable');peers[peer].write(encode(value));};
  const core=new PhaseCoordinator(session,send,record,interactive,undefined,phaseRun,repeatedTurns,terminalCheckpoint,deployment,fullMission);
  const bootstrap=liveBootstrap?new (require('./bootstrap-exchange.cjs').BootstrapExchange)(session,send,record):null;
  if(fixedCombatFixture&&(!interactive||!phaseRun||!repeatedTurns||terminalCheckpoint))throw Error('fixture-requires-original-repeated-turn-checkpoint');
  const fixture=fixedCombatFixture?require('./fixed-combat-fixture.cjs').createFixedCombatFixture():null;
  function stop(reason,success=false){
    if(stopped)return;stopped=true;clearInterval(timer);record({type:success?'passed':'stopped',reason});
    if(!success)for(const socket of sockets)if(!socket.destroyed)socket.write(encode({kind:'STOP',session,peer:'-',revision:core.stage,phase:'-',id:'-',witness:''}));
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
          if(++count>(fullMission?4096:repeatedTurns?2048:1024))throw Error('message-limit');
          const m=JSON.parse(buffer.slice(0,cut));buffer=buffer.slice(cut+1);
          if(!peer){
            if(m.type!=='hello'||m.session!==session||!Object.hasOwn(tokens,m.peer)||m.token!==tokens[m.peer]||peers[m.peer])throw Error('authentication-failed');
            peer=m.peer;peers[peer]=socket;if(!started)started=Date.now();record({type:'connected',peer});continue;
          }
          if(m.type==='pong'){if(m.session!==session)throw Error('pong-session');continue;}
          record({type:'received',peer,message:m});
          if(bootstrap&&m.type.startsWith('bootstrap_')){bootstrap.receive(peer,m);continue;}
          if(bootstrap&&!bootstrap.complete)throw Error('bootstrap-agreement-required');
          core.receive(peer,m);
          if(core.mode==='complete')stop('both-real-game-outcomes-agree',true);
        }
      }catch(e){stop(e.message);}
    });
  });
  const timer=setInterval(()=>{
    try{core.tick();if(fixture)fixture(core,record);}catch(e){stop(e.message);return;}
    if(!started && Date.now()-created>600000){stop('startup-deadline');return;}
    if(started && Date.now()-started>(fullMission?3600000:repeatedTurns?1800000:interactive?600000:180000)){stop('experiment-deadline');return;}
    for(const peer of Object.keys(peers))if(!peers[peer].destroyed)send(peer,{kind:'PING',session,peer:'-',revision:core.stage,phase:'-',id:'-',witness:''});
  },1000);
  server.on('error',e=>stop(e.message));
  server.listen(0,'127.0.0.1',()=>{
    for(const peer of ['host','guest']){
      fs.writeFileSync(path.join(root,peer+'.json'),JSON.stringify({session,peer,token:tokens[peer],host:'10.0.2.2',port:server.address().port,interactive,phaseRun,repeatedTurns,terminalCheckpoint,deployment,fullMission,liveBootstrap,nativeTransport},null,2));
      if(nativeTransport)fs.writeFileSync(path.join(root,peer+'-native.txt'),['itb-transport-v1',session,peer,'10.0.2.2',server.address().port,tokens[peer],''].join('\n'));
    }
    record({type:'listening',session,port:server.address().port});console.log('Private phase coordinator ready; games must be explicitly armed.');
    if(fixture){record({type:'scripted_combat_fixture',humanSelectionProof:false,humanReadinessProof:false});console.log('Fixed combat fixture: both roles have scripted intent and End Turn consent. Result review remains manual.');}
  });
  process.on('SIGINT',()=>stop('operator-stop'));
}
module.exports={PhaseCoordinator,expected};
if(require.main===module){try{const raw=process.argv[3],repair=raw==='--native-repair',direct=repair||raw==='--native-transport',live=!repair&&(direct||raw==='--live-bootstrap'),mode=repair?'--repeated-turns':live?'--full-mission':raw,full=mode==='--full-mission';main(process.argv[2],['--full-mission','--interactive','--interactive-phase','--repeated-turns','--terminal-checkpoint','--fixed-combat-fixture','--deployment'].includes(mode),['--full-mission','--interactive-phase','--repeated-turns','--terminal-checkpoint','--fixed-combat-fixture','--deployment'].includes(mode),['--full-mission','--repeated-turns','--terminal-checkpoint','--fixed-combat-fixture'].includes(mode),mode==='--terminal-checkpoint',mode==='--fixed-combat-fixture',mode==='--deployment'||full,full,live,direct);}catch(e){console.error(e.message);process.exitCode=1;}}
