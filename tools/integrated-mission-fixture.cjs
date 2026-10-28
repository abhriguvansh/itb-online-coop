// Diagnostic intent only, for the observed fresh Tides branch. Games must be
// entered and armed locally; Reset consent and result review remain local.
// No engine calls here.
const actors={combat:{id:0,type:'PunchMech',owner:'host'},cannon:{id:1,type:'TankMech',owner:'guest'},artillery:{id:2,type:'ArtiMech',owner:'guest'}};
// actor, kind, expected origin, target. The last turn is a new live hypothesis;
// the first 21 commands were observed together in the 0.31 run-2 evidence.
const plan=[
 ['combat','deploy',-1,-1,1,4],['cannon','deploy',-1,-1,1,5],['artillery','deploy',-1,-1,2,5],'launch',
 ['cannon','move',1,5,1,6],['cannon','undo-move',1,6,1,5],
 ['cannon','basic-attack',1,5,2,5],['artillery','repair',3,5,3,5],'reset',
 ['cannon','move',1,5,4,5],['cannon','basic-attack',4,5,4,4],
 ['combat','move',1,4,2,3],['combat','basic-attack',2,3,3,3],
 ['artillery','move',2,5,1,4],['artillery','basic-attack',1,4,4,4],'end',
 ['combat','move',2,3,1,5],['combat','basic-attack',1,5,2,5],
 ['cannon','basic-attack',4,6,5,6],['artillery','basic-attack',1,4,4,4],'end',
 ['cannon','basic-attack',4,6,4,5],['combat','move',1,5,4,5],
 ['combat','basic-attack',4,5,4,4],['artillery','move',1,4,2,5],
 ['artillery','basic-attack',2,5,2,3],'end'
];
// No local-ID assumptions for enemies. Match the whole living enemy branch,
// including health and queued targets, before issuing its first tactical action.
const branches={
 4:[['Jelly_Health1',2,4,4,-1,-1],['Hornet1',3,3,3,3,4],['Hornet1',3,5,4,5,5]],
 9:[['Jelly_Health1',2,4,4,-1,-1],['Hornet1',3,3,3,3,4],['Hornet1',3,5,4,5,5]],
 16:[['Hornet1',2,4,4,3,4],['Hornet1',2,2,5,2,4],['Scorpion1',3,5,4,5,5],['Scorpion1',3,5,6,5,5]],
 21:[['Hornet1',1,2,3,2,4],['Scorpion1',2,5,6,4,6],['Scorpion1',2,4,5,4,6],['Scorpion1',3,4,4,3,4]]
};
const sorted=rows=>JSON.stringify(rows.map(r=>JSON.stringify(r)).sort());
function createIntegratedMissionFixture(){
 const issued=new Set();let failed=false,handedBack=false,nextStage=0;
 return (core,record)=>{
  if(failed||handedBack||core.mode!=='proposal'||issued.has(core.stage))return;
  try{
   core.require(core.interactive&&core.phaseRun&&core.repeatedTurns&&core.deployment&&core.fullMission&&!core.terminalCheckpoint,'integrated-fixture-mode');
   core.require(Number.isInteger(core.stage)&&core.stage>=0&&core.stage<plan.length,'integrated-fixture-command-limit');
   core.require(core.stage===nextStage,'integrated-fixture-sequence-changed');
   core.require(core.states.host.witness===core.states.guest.witness&&core.states.host.phase===core.states.guest.phase,'integrated-fixture-peer-disagreement');
   const s=JSON.parse(core.states.host.witness),stage=core.stage,turn=stage<4?0:stage<16?1:stage<21?2:3;
   core.require(s.schema==='itb-observation-v1'&&s.unavailable?.length===0&&s.mission==='Mission_Tides'&&s.turn===turn&&s.gridPower===(turn===3?1:2)&&s.team===(turn===0?6:1),'integrated-fixture-context');
   core.require(core.states.host.phase===(turn===0?'deployment':'player'+turn),'integrated-fixture-phase');
   core.require(Array.isArray(s.pawns)&&Array.isArray(s.tiles)&&s.size?.x===8&&s.size?.y===8,'integrated-fixture-incomplete-board');
   for(const a of Object.values(actors)){
    const ps=s.pawns.filter(p=>p.localId===a.id),p=ps[0];
    const health=a.id===2?(stage===7?1:2):3;
    core.require(ps.length===1&&p.type===a.type&&p.team===1&&!p.dead&&p.health===health&&!p.fire&&!p.frozen&&!p.acid&&!p.shield,'integrated-fixture-squad-changed');
   }
   if(branches[stage]){
    const enemies=s.pawns.filter(p=>p.team===6&&!p.dead);
    core.require(enemies.every(p=>!p.fire&&!p.frozen&&!p.acid&&!p.shield),'integrated-fixture-enemy-status-changed');
    const observed=enemies.map(p=>[p.type,p.health,p.position.x,p.position.y,p.queuedTarget?.x,p.queuedTarget?.y]);
    if(sorted(observed)!==sorted(branches[stage])){
     // Both games already agree at a normal INPUT barrier. This is unknown
     // strategy, not uncertain execution: retire the script before proposing
     // anything, leaving the existing owner-bound local controls available.
     handedBack=true;
     record({type:'integrated_fixture_handoff',revision:stage,turn,reason:'unfamiliar-enemy-branch',
      localOperatorIntentRequired:true,humanSelectionProof:false,fullStateProof:false});
     return;
    }
    record({type:'integrated_fixture_branch',revision:stage,turn,humanSelectionProof:false,fullStateProof:false});
   }
   if(stage===9)core.require(core.pendingKind==='reset-turn'&&core.resetUsed,'integrated-fixture-local-reset-required');
   let action=plan[stage];
   // Latch before the first send, including readiness sends. An exception after
   // one peer receives intent never causes a second attempt on another tick.
   issued.add(stage);nextStage++;
   if(action==='reset'){
    // Reset intentionally requires each runtime's own resetReady call before
    // coordinator consent. Never impersonate that local approval in the driver.
    record({type:'integrated_fixture_local_reset_required',revision:stage,roles:['host','guest'],scriptedReadiness:false,humanReadinessProof:false});
    return;
   }
   if(typeof action==='string'){
    const launch=action==='launch';
    record({type:'scripted_integrated_readiness',revision:stage,kind:launch?'deployment-confirm':'end-turn',roles:['host','guest'],humanReadinessProof:false});
    for(const peer of ['host','guest']){
     core.receive(peer,{type:'ready',session:core.session,peer,revision:stage,phase:core.states[peer].phase,witness:core.states[peer].witness,
      ...(launch?{confirmDeployment:true}:{confirmUnused:true})});
    }
    return;
   }
   const [actor,kind,fromX,fromY,toX,toY]=action,a=actors[actor],p=s.pawns.find(p=>p.localId===a.id);
   core.require(p.position.x===fromX&&p.position.y===fromY&&p.active===true,'integrated-fixture-actor-changed');
   if(kind==='move')core.require(!p.movementSpent&&!p.grappled,'integrated-fixture-move-unavailable');
   const peer=a.owner,prefix=kind==='basic-attack'?'attack':kind==='undo-move'?'undo':kind==='repair'?'repair':'move';
   // Keep this bounded fixture's IDs away from the local UI's initial counter,
   // which has not authored any requests while the script was driving.
   const request={session:core.session,encounter:'artillery-checkpoint',phase:core.states.host.phase,revision:stage,witness:core.states.host.witness,
    id:prefix+'-'+peer+'-'+(901+stage),kind,actor,fromX,fromY,toX,toY};
   record({type:'scripted_integrated_intent',revision:stage,actor,kind,fromX,fromY,toX,toY,humanSelectionProof:false});
   core.receive(peer,{type:'proposal',session:core.session,peer,request});
  }catch(error){failed=true;throw error;}
 };
}
module.exports={createIntegratedMissionFixture};
