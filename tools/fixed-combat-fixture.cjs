// Fixed disposable-checkpoint test only. Both roles have scripted intent and readiness.
// Every request still passes the existing coordinator and both real runtime preparations.
function createFixedCombatFixture(){
let issued=new Set(),branch=null;
const plan=[
 ['combat','basic-attack',2,3],['cannon','basic-attack',1,3],['artillery','basic-attack',4,3],null,
 ['artillery','move',0,1],['artillery','basic-attack',4,1],['combat','basic-attack',2,4],['cannon','move',0,3],['cannon','basic-attack',2,3],null,
 ['cannon','move',0,5],['cannon','basic-attack',2,5],
 'artillery-move','artillery-attack','combat-move','combat-attack',null
];
return (core,record)=>{
 if(core.mode!=='proposal'||issued.has(core.stage))return;
 core.require(core.stage<plan.length,'fixture-command-limit');
 const state=JSON.parse(core.states.host.witness);let action=plan[core.stage];
 if(core.stage>=12&&!branch){
  const p=state.pawns.find(p=>p.localId===123&&!p.dead);
  if(p?.type==='Scorpion1'&&p.position.x===4&&p.position.y===4&&p.queuedTarget?.x===3&&p.queuedTarget?.y===4)branch='common';
  else if(p?.type==='Firefly1'&&p.position.x===6&&p.position.y===3&&p.queuedTarget.x===5&&p.queuedTarget.y===3)branch='common';
  else if(p?.type==='Firefly1'&&p.position.x===6&&p.position.y===1&&p.queuedTarget.x===5&&p.queuedTarget.y===1)branch='north';
  else if(p?.type==='Firefly1'&&p.position.x===5&&p.position.y===4&&p.queuedTarget.x===4&&p.queuedTarget.y===4)branch='south';
  else throw Error('fixture-unsupported-observed-spawn');
  record({type:'fixture_branch',branch,fullStateProof:false});
 }
 const later=branch==='south'?{
  'artillery-move':['artillery','move',0,3],'artillery-attack':['artillery','basic-attack',5,3],
  'combat-move':['combat','move',4,3],'combat-attack':['combat','basic-attack',4,2]
 }:branch==='north'?{
  'artillery-move':['artillery','move',0,2],'artillery-attack':['artillery','basic-attack',6,2],
  'combat-move':['combat','move',4,3],'combat-attack':['combat','basic-attack',4,2]
 }:{
  'artillery-move':['artillery','move',0,3],'artillery-attack':['artillery','basic-attack',4,3],
  'combat-move':['combat','move',4,2],'combat-attack':['combat','basic-attack',4,1]
 };
 if(typeof action==='string')action=later[action];
 issued.add(core.stage); // Never retry an issued or uncertain action.
 if(action===null){
  record({type:'scripted_fixture_end_readiness',revision:core.stage,roles:['host','guest'],humanReadinessProof:false});
  for(const peer of ['host','guest'])core.receive(peer,{type:'ready',session:core.session,peer,revision:core.stage,phase:core.states[peer].phase,witness:core.states[peer].witness,confirmUnused:true});
  return;
 }
 const [actor,kind,toX,toY]=action,peer=actor==='combat'?'host':'guest',pawn=state.pawns.find(p=>p.localId===({combat:0,cannon:1,artillery:2})[actor]);
 core.require(pawn&&!pawn.dead,'fixture-actor-unavailable');
 const request={session:core.session,encounter:'artillery-checkpoint',phase:core.states.host.phase,revision:core.stage,witness:core.states.host.witness,id:(kind==='move'?'move':'attack')+'-'+peer+'-'+(core.stage+1),kind,actor,fromX:pawn.position.x,fromY:pawn.position.y,toX,toY};
 record({type:'scripted_fixture_intent',revision:core.stage,actor,kind,toX,toY,humanSelectionProof:false});
 core.receive(peer,{type:'proposal',session:core.session,peer,request});
};

}
module.exports={createFixedCombatFixture};
