const assert=require('node:assert/strict'),{PhaseCoordinator}=require('../tools/phase-coordinator.cjs');
function fixture(){
 const sent=[],events=[],s='deployment-session';let time=0;
 const c=new PhaseCoordinator(s,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>time,true,false,false,true);
 const state={schema:'itb-observation-v1',unavailable:[],mission:'Mission_Tides',turn:0,team:6,
  deployment:{inProgress:true,phase:0,mechs:[0,1,2].map(id=>({id,state:id?1:0,x:-1,y:-1}))},
  pawns:[0,1,2].map(localId=>({localId,position:{x:-1,y:-1},active:true}))};
 const ctx=revision=>({revision,phase:revision>=4?'player1':'deployment',witness:JSON.stringify(state)});
 const send=(peer,m)=>c.receive(peer,{session:s,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.20.0',interactive:true,phaseRun:true,deployment:true,...ctx(0)});
 const request=i=>({session:s,encounter:'artillery-checkpoint',...ctx(i),id:'move-'+(i?'guest':'host')+'-'+(i+1),kind:'deploy',actor:['combat','cannon','artillery'][i],fromX:-1,fromY:-1,toX:1,toY:4+i});
 return {c,send,sent,events,state,ctx,request,elapse:()=>{time=3000}};
}
{
 const f=fixture();assert.throws(()=>f.send('guest',{type:'proposal',request:f.request(0)}),/actor-not-owned/);
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
 for(const peer of ['host','guest'])f.send(peer,{type:'complete',...f.ctx(5),native:{guardActive:true,sessionState:1,releaseFailed:false}});
 assert.equal(f.c.mode,'complete');assert.equal(f.events.filter(e=>e.type==='dispatch').length,5);
}
{
 const f=fixture();f.send('host',{type:'proposal',request:f.request(0)});f.elapse();assert.throws(()=>f.c.tick(),/game-prepare-timeout/);
 assert.equal(f.events.filter(e=>e.type==='dispatch').length,0);
}
console.log('Deployment coordinator: three placements, both launch consents, next-turn move, ownership/order, preparations, duplicate refusal and stopped-peer timeout (fake peers).');
