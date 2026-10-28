const assert=require('node:assert/strict');
const {PhaseCoordinator}=require('../tools/phase-coordinator.cjs');
const {createIntegratedMissionFixture}=require('../tools/integrated-mission-fixture.cjs');
function fixture(){
 let time=0;const sent=[],records=[],session='integrated-test';
 const core=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),r=>records.push(r),true,()=>time,true,true,false,true,true);
 const state={schema:'itb-observation-v1',unavailable:[],mission:'Mission_Tides',turn:0,team:6,gridPower:2,size:{x:8,y:8},tiles:[],
  initialChoices:Array.from({length:19},(_,i)=>({kind:i<17?'ai-constructor':i===17?'pod-delivery':'pod-select',limit:i<17?32768:i===17?3:9,value:42})),
  deployment:{inProgress:true,phase:0,mechs:[0,1,2].map(id=>({id,state:id?1:0,x:-1,y:-1}))},
  pawns:['PunchMech','TankMech','ArtiMech'].map((type,localId)=>({type,localId,team:1,health:localId===2?2:3,active:true,movementSpent:false,position:{x:-1,y:-1}}))};
 const context=revision=>({revision,phase:revision<4?'deployment':'player'+state.turn,witness:JSON.stringify(state)});
 const send=(peer,m)=>core.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.31.0',interactive:true,phaseRun:true,repeatedTurns:true,deployment:true,fullMission:true,sharedXp:'itb-shared-xp-v1',...context(0)});
 const native={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 const prepared=peer=>send(peer,{type:'prepared',origin:core.proposal.peer,request:core.proposal.request,native});
 const observed=change=>{
  const r=core.proposal.request,stage=core.stage;
  if(change)change(state);
  else if(r.kind==='deploy'){
   const id={combat:0,cannon:1,artillery:2}[r.actor];state.pawns[id].position={x:r.toX,y:r.toY};Object.assign(state.deployment.mechs[id],{state:2,x:r.toX,y:r.toY});
  }else if(r.kind==='deployment-confirm'){
   state.turn=1;state.team=1;state.deployment.inProgress=false;state.deployment.phase=2;
   state.deployment.mechs.forEach(p=>{p.state=4});
  }else throw Error('test only models deployment observations');
  for(const peer of ['host','guest'])send(peer,{type:'observed',id:r.id,...context(stage+1),native,
   sharedXp:{abi:'itb-shared-xp-v1',context:session+'/'+r.phase+'/'+stage+'/'+r.id,entries:[]}});
 };
 const tick=createIntegratedMissionFixture(),run=()=>tick(core,r=>records.push(r));
 const deploy=()=>{for(let i=0;i<4;i++){run();prepared('host');prepared('guest');observed();}};
 return {core,state,sent,records,send,prepared,observed,run,deploy,elapse:()=>{time=3000}};
}
{
 const f=fixture();f.run();f.run();
 assert.equal(f.core.mode,'preparing');assert.equal(f.records.filter(r=>r.type==='prepare').length,1);
 assert.equal(f.records.filter(r=>r.type==='dispatch').length,0);
 assert.equal(f.core.proposal.peer,'host');assert.equal(f.core.proposal.request.kind,'deploy');
 assert.equal(f.core.proposal.request.id,'move-host-901');
 assert.equal(f.records.find(r=>r.type==='scripted_integrated_intent').humanSelectionProof,false);
 f.prepared('host');assert.equal(f.records.filter(r=>r.type==='dispatch').length,0);
 f.elapse();assert.throws(()=>f.core.tick(),/game-prepare-timeout/);
 assert.equal(f.records.filter(r=>r.type==='dispatch').length,0);
}
{
 const f=fixture();f.deploy();
 assert.equal(f.core.stage,4);assert.equal(f.core.turn,1);
 assert.deepEqual(f.records.filter(r=>r.type==='dispatch').map(r=>[r.origin,r.request.kind]),[['host','deploy'],['guest','deploy'],['guest','deploy'],['host','deployment-confirm']]);
 const ready=f.records.find(r=>r.type==='scripted_integrated_readiness');
 assert.equal(ready.kind,'deployment-confirm');assert.deepEqual(ready.roles,['host','guest']);assert.equal(ready.humanReadinessProof,false);
 // An unfamiliar but synchronized board retires only scripted intent; the
 // existing protected local proposal path remains open, without a guessed move.
 const before=f.sent.length;f.run();assert.equal(f.sent.length,before);assert.equal(f.core.mode,'proposal');
 assert.equal(f.records.filter(r=>r.type==='integrated_fixture_handoff').length,1);
 // Later familiar state must not revive a retired fixture.
 f.state.pawns.push({team:6,type:'Jelly_Health1',health:2,position:{x:4,y:4},queuedTarget:{x:-1,y:-1}},
  {team:6,type:'Hornet1',health:3,position:{x:3,y:3},queuedTarget:{x:3,y:4}},
  {team:6,type:'Hornet1',health:3,position:{x:5,y:4},queuedTarget:{x:5,y:5}});
 const witness=JSON.stringify(f.state);for(const peer of ['host','guest'])f.core.states[peer].witness=witness;
 f.run();assert.equal(f.sent.length,before);assert.equal(f.records.filter(r=>r.type==='integrated_fixture_handoff').length,1);
 const localMove={session:f.core.session,encounter:'artillery-checkpoint',phase:'player1',revision:4,witness,
  id:'move-host-1',kind:'move',actor:'combat',fromX:1,fromY:4,toX:1,toY:3};
 f.send('host',{type:'proposal',request:localMove});assert.equal(f.core.mode,'preparing','local UI first ID must not collide with fixture IDs');
 const dispatches=f.records.filter(r=>r.type==='dispatch').length;f.prepared('host');
 assert.equal(f.records.filter(r=>r.type==='dispatch').length,dispatches);
 f.prepared('guest');assert.equal(f.records.filter(r=>r.type==='dispatch').length,dispatches+1);
}
{
 const f=fixture(),receive=f.core.receive.bind(f.core);let attempts=0;
 f.core.receive=(peer,m)=>{attempts++;receive(peer,m);throw Error('delivery-uncertain')};
 assert.throws(f.run,/delivery-uncertain/);f.core.mode='proposal';f.run();
 assert.equal(attempts,1);assert.equal(f.records.filter(r=>r.type==='prepare').length,1);assert.equal(f.records.filter(r=>r.type==='dispatch').length,0);
}
for(const mutate of [
 f=>{f.core.fullMission=false},f=>{f.core.stage=4},f=>{f.core.states.guest.witness='different'},
 f=>{f.state.pawns[0].type='OtherMech'},f=>{f.state.gridPower=1},f=>{f.state.pawns[0].position.x=0}
]){
 const f=fixture();mutate(f);
 if(f.core.states.guest.witness!=='different'){const witness=JSON.stringify(f.state);for(const peer of ['host','guest'])f.core.states[peer].witness=witness;}
 assert.throws(f.run,/integrated-fixture/);assert.equal(f.sent.filter(r=>r.frame.kind==='PREPARE'||r.frame.kind==='EXEC').length,0);
}
{
 const f=fixture();f.deploy();
 f.state.pawns.push({team:6,type:'Jelly_Health1',health:2,position:{x:4,y:4},queuedTarget:{x:-1,y:-1}},
  {team:6,type:'Hornet1',health:3,position:{x:3,y:3},queuedTarget:{x:3,y:4}},
  {team:6,type:'Hornet1',health:3,position:{x:5,y:4},queuedTarget:{x:5,y:5}});
 for(const peer of ['host','guest'])f.core.states[peer].witness=JSON.stringify(f.state);
 // Supply separate outcome observations; this test does not simulate physics.
 for(const outcome of [
  s=>{s.pawns[1].position.y=6;s.pawns[1].movementSpent=true},
  s=>{s.pawns[1].position.y=5;s.pawns[1].movementSpent=false},
  s=>{s.pawns[1].active=false;s.pawns[2].position.x=3;s.pawns[2].health=1},
  s=>{s.pawns[2].active=false;s.pawns[2].health=2}
 ]){f.run();f.prepared('host');f.prepared('guest');f.observed(outcome);}
 assert.equal(f.core.stage,8);const count=f.records.filter(r=>r.type==='prepare').length;
 f.run();f.run();assert.equal(f.core.mode,'proposal');assert.equal(f.records.filter(r=>r.type==='prepare').length,count);
 const pause=f.records.find(r=>r.type==='integrated_fixture_local_reset_required');
 assert.equal(pause.scriptedReadiness,false);assert.deepEqual(pause.roles,['host','guest']);
 assert.equal(f.records.filter(r=>r.type==='reset_ready').length,0,'driver must never fabricate local Reset readiness');
 const ready={type:'reset_ready',revision:8,phase:'player1',witness:f.core.states.host.witness,confirmReset:true};
 f.send('host',ready);f.run();assert.equal(f.core.mode,'reset-readiness');
 assert.equal(f.records.filter(r=>r.type==='dispatch'&&r.request.kind==='reset-turn').length,0);
 f.send('guest',ready);assert.equal(f.core.mode,'preparing');f.prepared('host');
 assert.equal(f.records.filter(r=>r.type==='dispatch'&&r.request.kind==='reset-turn').length,0);
 f.prepared('guest');assert.equal(f.records.filter(r=>r.type==='dispatch'&&r.request.kind==='reset-turn').length,1);
}
console.log('Integrated diagnostic fixture: existing two-runtime preparation, timeout with zero dispatch, scripted consent labels, unknown-branch latch, sequence/ownership context and no retry after uncertainty (doubles only).');
