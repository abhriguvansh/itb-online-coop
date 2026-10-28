const assert=require('node:assert/strict');
const {PhaseCoordinator}=require('../tools/phase-coordinator.cjs');
function fixture(){
 let time=0;const sent=[],records=[],session='outcome-test';
 const core=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),v=>records.push(v),true,()=>time);
 const native={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 const context=(revision,y=3)=>({revision,phase:'player2',witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn:2,pawns:[{localId:2,position:{x:0,y},active:true,movementSpent:y!==3}]})});
 const send=(peer,m)=>core.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,...context(0)});
 const request={session,encounter:'artillery-checkpoint',...context(0),id:'move-guest-1',kind:'move',actor:'artillery',fromX:0,fromY:3,toX:0,toY:2};
 send('guest',{type:'proposal',request});
 for(const peer of ['host','guest'])send(peer,{type:'prepared',origin:'guest',request,native});
 const observed=peer=>send(peer,{type:'observed',id:request.id,native,...context(1,2)});
 return {core,sent,records,observed,at:value=>{time=value}};
}
{
 const f=fixture();f.at(19000);f.observed('host');f.at(19999);f.core.tick();
 assert.equal(f.core.mode,'executing');assert.equal(f.core.stage,0);
 assert.equal(f.records.filter(v=>v.type==='barrier').length,1);
 f.at(20000);assert.throws(()=>f.core.tick(),/game-outcome-timeout/);
 assert.throws(()=>f.observed('guest'),/game-outcome-timeout/,'a late receipt cannot reopen admission');
 assert.equal(f.sent.filter(v=>v.frame.kind==='EXEC').length,2,'exactly one dispatch to each peer, no retry');
 assert.equal(f.sent.filter(v=>v.frame.kind==='INPUT').length,2,'no following input barrier');
}
{
 const f=fixture();f.at(19999);f.observed('host');f.observed('guest');f.at(240001);f.core.tick();
 assert.equal(f.core.stage,1);assert.equal(f.core.mode,'proposal','completed command deadline cannot expire user thinking time');
}
for(const kind of ['end-turn','deployment-confirm']){
 const f=fixture();f.core.dispatch('host',{...f.core.proposal.request,kind});
 f.at(239999);f.core.tick();f.at(240000);assert.throws(()=>f.core.tick(),/game-outcome-timeout/);
}
console.log('Outcome deadline: one-sided commit cannot renew the bounded wait or admit/retry another command; late receipt refused, completed barrier releases thinking time, phase review retains its longer bound (fake peers/clock).');
