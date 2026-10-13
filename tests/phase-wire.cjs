const assert=require('node:assert/strict');
const {PhaseCoordinator,expected}=require('../tools/phase-coordinator.cjs');
const session='fixture-session';
const context=n=>({revision:n,phase:n<3?'player2':'player3',witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],testRevision:n})});
const guard={guardActive:true,sessionState:1,releaseFailed:false};
function fixture(){
  const sent=[],events=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e));
  const send=(peer,message)=>c.receive(peer,{session,peer,...message});
  for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.10.0',...context(0)});
  return {c,sent,events,send};
}
let count=0;
function test(name,fn){fn();count++;console.log('PASS '+name);}
test('four-command fixture waits for both observed outcomes and both End Turn consents',()=>{
  const {c,send,sent}=fixture();
  for(let n=0;n<4;n++){
    if(n===2){
      send('host',{type:'ready',confirmUnused:true,...context(2)});assert.equal(c.mode,'readiness');
      send('guest',{type:'ready',confirmUnused:true,...context(2)});assert.equal(c.mode,'proposal');
      assert.equal(sent.filter(x=>x.frame.kind==='CONSENT').length,4);
    }
    const r=expected(session,n,context(n));send(['guest','host','host','guest'][n],{type:'proposal',request:r});
    send('host',{type:'observed',id:r.id,...context(n+1),native:guard});assert.equal(c.stage,n);assert.equal(c.mode,'executing');
    send('guest',{type:'observed',id:r.id,...context(n+1),native:guard});assert.equal(c.stage,n+1);
  }
  send('host',{type:'complete',revision:4,witness:context(4).witness,native:guard});assert.equal(c.mode,'finishing');
  send('guest',{type:'complete',revision:4,witness:context(4).witness,native:guard});assert.equal(c.mode,'complete');
});
test('connection identity cannot submit the other peer proposal',()=>{
  const {send}=fixture();assert.throws(()=>send('host',{type:'proposal',request:expected(session,0,context(0))}),/unexpected-proposal/);
});
test('stale or altered proposal never dispatches',()=>{
  const {send,sent}=fixture();assert.throws(()=>send('guest',{type:'proposal',request:{...expected(session,0,context(0)),toX:2}}),/proposal-conflict/);
  assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,0);
});
test('duplicate proposal is not replayed',()=>{
  const {send,sent}=fixture(),m={type:'proposal',request:expected(session,0,context(0))};send('guest',m);
  assert.throws(()=>send('guest',m),/unexpected-proposal/);assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,2);
});
test('divergent observations prevent the next action',()=>{
  const {send,c}=fixture(),r=expected(session,0,context(0));send('guest',{type:'proposal',request:r});
  send('host',{type:'observed',id:r.id,...context(1),native:guard});
  assert.throws(()=>send('guest',{type:'observed',id:r.id,...context(1),witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],different:true}),native:guard}),/observed-state-divergence/);
  assert.notEqual(c.mode,'proposal');
});
test('lost guard cannot acknowledge a successful action',()=>{
  const {send}=fixture(),r=expected(session,0,context(0));send('guest',{type:'proposal',request:r});
  assert.throws(()=>send('host',{type:'observed',id:r.id,...context(1),native:{...guard,guardActive:false}}),/protection-lost/);
});
test('completion cannot skip the phase barrier',()=>{
  const {send}=fixture();assert.throws(()=>send('host',{type:'complete',revision:4,witness:context(4).witness,native:guard}),/unexpected-completion/);
});
console.log(count+' coordinator contracts passed; fake peer messages only.');
