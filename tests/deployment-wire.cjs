const assert=require('node:assert/strict'),{PhaseCoordinator}=require('../tools/phase-coordinator.cjs');
function fixture(full=false){
 const sent=[],events=[],s='deployment-session';let time=0;
 const c=new PhaseCoordinator(s,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>time,true,full,false,true,full);
 const state={schema:'itb-observation-v1',unavailable:[],mission:'Mission_Tides',turn:0,team:6,
  initialChoices:Array.from({length:19},(_,i)=>({kind:i<17?'ai-constructor':i===17?'pod-delivery':'pod-select',limit:i<17?32768:i===17?3:9,value:42})),
  deployment:{inProgress:true,phase:0,mechs:[0,1,2].map(id=>({id,state:id?1:0,x:-1,y:-1}))},
  pawns:[0,1,2].map(localId=>({localId,position:{x:-1,y:-1},active:true}))};
 const ctx=revision=>({revision,phase:revision>=4?'player'+state.turn:'deployment',witness:JSON.stringify(state)});
 const send=(peer,m)=>c.receive(peer,{session:s,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.29.0',interactive:true,phaseRun:true,deployment:true,...(full?{repeatedTurns:true,fullMission:true}:{}),...ctx(0)});
 const request=i=>({session:s,encounter:'artillery-checkpoint',...ctx(i),id:'move-'+(i?'guest':'host')+'-'+(i+1),kind:'deploy',actor:['combat','cannon','artillery'][i],fromX:-1,fromY:-1,toX:1,toY:4+i});
 return {c,send,sent,events,state,ctx,request,elapse:()=>{time=3000}};
}
{
 const f=fixture(true),n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 // Model the already covered placement/launch boundary, then test the newly connected path.
 f.c.stage=4;f.c.turn=1;f.state.turn=1;f.state.team=1;f.state.deployment.inProgress=false;f.state.deployment.phase=2;
 f.state.pawns.forEach((p,i)=>{p.position={x:1,y:4+i};p.movementSpent=false});
 f.c.states={host:f.ctx(4),guest:f.ctx(4)};f.c.advance();
 const r={session:f.c.session,encounter:'artillery-checkpoint',...f.ctx(4),id:'attack-guest-1',kind:'basic-attack',actor:'artillery',fromX:1,fromY:6,toX:1,toY:2};
 f.send('guest',{type:'proposal',request:r});
 for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'guest',request:r,native:n});
 for(const peer of ['host','guest'])f.send(peer,{type:'observed',id:r.id,...f.ctx(5),native:n});
 assert.equal(f.c.mode,'proposal','fresh mission must continue past former five-command stop');
 assert.throws(()=>f.send('host',{type:'ready',confirmDeployment:true,...f.ctx(5)}),/unexpected-readiness/);
 for(const peer of ['host','guest'])f.send(peer,{type:'ready',confirmUnused:true,...f.ctx(5)});
 const end=f.c.proposal.request;assert.equal(end.kind,'end-turn');assert.equal(end.phase,'player1');
 for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'host',request:end,native:n});
 assert.throws(()=>f.send('host',{type:'observed',id:end.id,...f.ctx(6),native:n}),/wrong-phase-or-revision/);
 f.state.turn=2;
 for(const peer of ['host','guest'])f.send(peer,{type:'observed',id:end.id,...f.ctx(6),native:n});
 assert.equal(f.c.turn,2);assert.equal(f.c.mode,'proposal');
 assert.throws(()=>f.send('guest',{type:'proposal',request:r}),/wrong-phase-or-revision/);
 console.log('Fresh mission connects attacks, joint End Turn and player-two admission without resetting the session (fake peers).');
}
for(const full of [false,true]){
 const f=fixture(full);assert.throws(()=>f.send('guest',{type:'proposal',request:f.request(0)}),/actor-not-owned/);
 assert.throws(()=>f.send('host',{type:'ready',confirmUnused:true,...f.ctx(0)}),/unexpected-deployment-readiness/);
 for(let i=0;i<3;i++){
  const peer=i?'guest':'host',r=f.request(i);f.send(peer,{type:'proposal',request:r});assert.equal(f.c.mode,'preparing');
  for(const p of ['host','guest'])f.send(p,{type:'prepared',origin:peer,request:r,native:{guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false}});
  assert.equal(f.c.mode,'executing');assert.throws(()=>f.send(peer,{type:'proposal',request:r}),/unexpected-proposal/);
  f.state.pawns[i].position={x:r.toX,y:r.toY};Object.assign(f.state.deployment.mechs[i],{state:2,x:r.toX,y:r.toY});
  for(const p of ['host','guest'])f.send(p,{type:'observed',id:r.id,...f.ctx(i+1),native:{guardActive:true,sessionState:1,releaseFailed:false}});
 }
 assert.equal(f.c.mode,'proposal');assert.deepEqual(f.events.filter(e=>e.type==='barrier').map(e=>e.revision),[0,1,2,3]);
 f.send('host',{type:'ready',confirmDeployment:true,...f.ctx(3)});assert.equal(f.events.filter(e=>e.type==='dispatch').length,3);
 f.send('guest',{type:'ready',confirmDeployment:true,...f.ctx(3)});
 const launch=f.events.at(-1).request;
 for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'host',request:launch,native:{guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false}});
 f.state.turn=1;f.state.team=1;f.state.deployment.inProgress=false;f.state.deployment.phase=2;for(const p of f.state.deployment.mechs)p.state=4;
 for(const peer of ['host','guest'])f.send(peer,{type:'observed',id:launch.id,...f.ctx(4),native:{guardActive:true,sessionState:1,releaseFailed:false}});
 const r={...f.request(4),kind:'move',actor:'cannon',fromX:1,fromY:5,toX:1,toY:6};f.send('guest',{type:'proposal',request:r});
 for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'guest',request:r,native:{guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false}});
 f.state.pawns[1].position={x:1,y:6};f.state.deployment.mechs[1].y=6;
 for(const peer of ['host','guest'])f.send(peer,{type:'observed',id:r.id,...f.ctx(5),native:{guardActive:true,sessionState:1,releaseFailed:false}});
 if(full){assert.equal(f.c.mode,'proposal');assert.equal(f.c.turn,1)}else{
  for(const peer of ['host','guest'])f.send(peer,{type:'complete',...f.ctx(5),native:{guardActive:true,sessionState:1,releaseFailed:false}});
  assert.equal(f.c.mode,'complete');
 }
 assert.equal(f.events.filter(e=>e.type==='dispatch').length,5);
}
{
 const f=fixture();f.send('host',{type:'proposal',request:f.request(0)});f.elapse();assert.throws(()=>f.c.tick(),/game-prepare-timeout/);
 assert.equal(f.events.filter(e=>e.type==='dispatch').length,0);
}
console.log('Deployment coordinator: three placements, both launch consents, next-turn move, ownership/order, preparations, duplicate refusal and stopped-peer timeout (fake peers).');
{
 const f=fixture();delete f.state.initialChoices;
 assert.throws(()=>f.c.context(f.ctx(0),0),/incomplete-initial-choices/);
 assert.equal(f.events.filter(e=>e.type==='dispatch').length,0);
}
