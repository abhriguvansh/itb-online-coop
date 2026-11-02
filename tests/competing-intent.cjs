const assert=require('node:assert/strict');
const {PhaseCoordinator}=require('../tools/phase-coordinator.cjs');
const session='competing-fixture',native={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
function setup(){
 const sent=[],events=[],c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>0,true,true);
 const witness=JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn:2,pawns:[{localId:0,position:{x:3,y:3},active:true,movementSpent:false},{localId:2,position:{x:0,y:3},active:true,movementSpent:false}]});
 const context={phase:'player2',revision:0,witness};
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.35.0',interactive:true,phaseRun:true,repeatedTurns:true,...context});
 const request=peer=>({session,encounter:'artillery-checkpoint',...context,id:'move-'+peer+'-1',kind:'move',actor:peer==='host'?'combat':'artillery',fromX:peer==='host'?3:0,fromY:3,toX:peer==='host'?2:0,toY:peer==='host'?3:2});
 return {c,sent,events,send,request,context};
}
for(const mode of ['preparing','executing','one-outcome','next-input']){
 const f=setup(),host=f.request('host'),guest=f.request('guest');
 f.send('host',{type:'proposal',request:host});
 if(mode!=='preparing')for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'host',request:host,native});
 const next={revision:1,phase:'player2',witness:JSON.stringify({...JSON.parse(f.context.witness),pawns:[{localId:0,position:{x:2,y:3},active:true,movementSpent:true},{localId:2,position:{x:0,y:3},active:true,movementSpent:false}]})};
 if(['one-outcome','next-input'].includes(mode))f.send('host',{type:'observed',id:host.id,native,...next});
 if(mode==='next-input')f.send('guest',{type:'observed',id:host.id,native,...next});
 const before={mode:f.c.mode,proposal:f.c.proposal,pendingId:f.c.pendingId,frames:f.sent.length};
 f.send('guest',{type:'proposal',request:guest});
 assert.equal(f.c.mode,before.mode);assert.equal(f.c.proposal,before.proposal);assert.equal(f.c.pendingId,before.pendingId);
 assert.equal(f.sent.length,before.frames+1);assert.equal(f.sent.at(-1).peer,'guest');assert.equal(f.sent.at(-1).frame.kind,'REJECT');
 assert.equal(f.sent.at(-1).frame.witness,mode==='next-input'?'stale-input':'action-in-progress');
 assert.throws(()=>f.send('guest',{type:'proposal',request:guest}),/duplicate-request/);
 if(mode==='preparing')for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'host',request:host,native});
 if(!['one-outcome','next-input'].includes(mode))f.send('host',{type:'observed',id:host.id,native,...next});
 if(mode!=='next-input')f.send('guest',{type:'observed',id:host.id,native,...next});
 const renewed={...guest,...next,id:'move-guest-2'};f.send('guest',{type:'proposal',request:renewed});assert.equal(f.c.mode,'preparing');
 assert.equal(f.events.filter(e=>e.type==='dispatch').length,1,'rejection never dispatches or retries the losing intent');
}
for(const mutation of [r=>r.actor='combat',r=>r.witness='{}',r=>r.revision=1,r=>r.id='move-host-2',r=>r.toX=8,r=>r.extra=true]){
 const f=setup();f.send('host',{type:'proposal',request:f.request('host')});const r=f.request('guest');mutation(r);
 assert.throws(()=>f.send('guest',{type:'proposal',request:r}));assert(!f.sent.some(e=>e.frame.kind==='REJECT'));
}
{
 const f=setup(),first=f.request('guest');f.send('guest',{type:'proposal',request:first});
 f.send('host',{type:'proposal',request:f.request('host')});
 assert.equal(f.sent.at(-1).peer,'host');assert.equal(f.sent.at(-1).frame.kind,'REJECT');
 assert.equal(f.c.proposal.peer,'guest','arrival order has no host privilege');
 for(const peer of ['host','guest'])f.send(peer,{type:'prepared',origin:'guest',request:first,native});
 assert.equal(f.events.filter(e=>e.type==='dispatch').length,1);assert.equal(f.events.at(-1).origin,'guest');
}
console.log('Competing genuine-context intents are refused without cancelling execution or granting INPUT; stale renewal and fatal authorization/duplicate guards pass (fake peers).');
