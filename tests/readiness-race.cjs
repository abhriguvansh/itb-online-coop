const assert=require('node:assert/strict'),{PhaseCoordinator}=require('../tools/phase-coordinator.cjs');
const session='readiness-fixture',native={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
function setup(){
 const sent=[],events=[],c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>0,true,true);
 const context=(revision,x=3)=>({revision,phase:'player2',witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn:2,pawns:[{localId:0,position:{x,y:3},active:true,movementSpent:x!==3}]})});
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.35.0',interactive:true,phaseRun:true,repeatedTurns:true,...context(0)});
 const move={session,encounter:'artillery-checkpoint',...context(0),id:'move-host-1',kind:'move',actor:'combat',fromX:3,fromY:3,toX:2,toY:3};
 const ready=revision=>({type:'ready',confirmUnused:true,...context(revision,revision?2:3)});
 const prepare=()=>{for(const peer of ['host','guest'])send(peer,{type:'prepared',origin:'host',request:move,native});};
 const outcome=peer=>send(peer,{type:'observed',id:move.id,native,...context(1,2)});
 return {c,sent,events,send,move,ready,prepare,outcome};
}
for(const timing of ['preparing','executing','one-outcome','next-input']){
 const f=setup();f.send('host',{type:'proposal',request:f.move});
 if(timing!=='preparing')f.prepare();
 if(['one-outcome','next-input'].includes(timing))f.outcome('host');
 if(timing==='next-input')f.outcome('guest');
 const mode=f.c.mode,command=f.c.proposal;
 f.send('guest',f.ready(0));assert.equal(f.c.mode,mode);assert.equal(f.c.proposal,command);assert.equal(f.sent.at(-1).frame.kind,'REJECT');assert.equal(f.c.consents.guest,undefined);
 assert.throws(()=>f.send('guest',f.ready(0)),/unexpected-readiness/);
 if(timing==='preparing')f.prepare();
 if(!['one-outcome','next-input'].includes(timing))f.outcome('host');
 if(timing!=='next-input')f.outcome('guest');
 f.send('host',f.ready(1));assert.equal(f.c.mode,'readiness');assert.equal(f.events.filter(e=>e.type==='prepare').length,1,'old guest vote cannot authorize End Turn');
 f.send('guest',f.ready(1));assert.equal(f.c.proposal.request.kind,'end-turn');assert.equal(f.events.filter(e=>e.type==='prepare').length,2);
}
{
 const f=setup();f.send('guest',f.ready(0));f.send('host',{type:'proposal',request:f.move});
 assert.equal(f.c.mode,'preparing');assert.equal(f.c.consents.guest,undefined);
 const cancellation=f.sent.findIndex(e=>e.frame.kind==='READYCANCEL'),preparation=f.sent.findIndex(e=>e.frame.kind==='PREPARE');assert(cancellation>=0&&cancellation<preparation);
 f.prepare();f.outcome('host');f.outcome('guest');f.send('host',f.ready(1));assert.equal(f.c.mode,'readiness');
 f.send('guest',f.ready(1));assert.equal(f.c.proposal.request.kind,'end-turn');
}
{
 const f=setup();for(const peer of ['host','guest'])f.send(peer,f.ready(0));const ending=f.c.proposal;
 f.send('host',{type:'proposal',request:f.move});assert.equal(f.c.proposal,ending);assert.equal(f.sent.at(-1).frame.kind,'REJECT');assert.equal(f.events.filter(e=>e.type==='prepare').length,1);
}
for(const mutation of [m=>m.witness='{}',m=>m.revision=1,m=>m.confirmUnused=false,m=>m.extra=true]){
 const f=setup();f.send('host',{type:'proposal',request:f.move});const r=f.ready(0);mutation(r);assert.throws(()=>f.send('guest',r));assert(!f.events.some(e=>e.type==='readiness_rejected'));
}
{
 const f=setup();f.c.resetBaseWitness='earlier-verified-baseline';f.send('guest',f.ready(0));
 const {type,confirmUnused,...context}=f.ready(0);f.send('host',{...context,type:'reset_ready',confirmReset:true});
 assert.equal(f.c.mode,'reset-readiness');assert.equal(f.c.consents.guest,undefined);
 assert.equal(f.sent.filter(e=>e.frame.kind==='READYCANCEL').length,2);assert.equal(f.sent.filter(e=>e.frame.kind==='RESETREADY').length,2);
 assert.equal(f.events.filter(e=>e.type==='prepare').length,0,'one Reset approval cannot execute a reset or reuse End Turn readiness');
}
console.log('Ready/action races preserve one admitted command, clear earlier votes, refuse stale readiness and require both fresh next-revision approvals (fake peers).');
