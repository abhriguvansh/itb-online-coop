const assert=require('node:assert/strict');
const {PhaseCoordinator,expected}=require('../tools/phase-coordinator.cjs');
const session='fixture-session';
testRepeatedTurns();
function testRepeatedTurns(){
 const sent=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true,true);
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});
 const ctx=(revision,turn)=>({revision,phase:'player'+turn,witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],pawns:[{localId:2,position:{x:0,y:3},movementSpent:false,active:true}],turn})});
 const n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.13.0',interactive:true,phaseRun:true,repeatedTurns:true,...ctx(0,2)});
 let rev=0,turn=2;
 for(const kind of ['move','end-turn','move','end-turn','move']){
  let r,origin;
  if(kind==='end-turn'){
   const ready={type:'ready',confirmUnused:true,...ctx(rev,turn)};
   send('guest',ready);assert.equal(c.mode,'readiness');
   assert.throws(()=>send('guest',ready),/unexpected-readiness/);
   assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,rev*2);
   send('host',ready);r=c.proposal.request;origin='host';assert.equal(r.id,'end-turn-'+rev);
  }else{
   r={session,encounter:'artillery-checkpoint',...ctx(rev,turn),id:'move-guest-'+(rev+1),kind,actor:'artillery',fromX:0,fromY:3,toX:1,toY:3};origin='guest';
   send(origin,{type:'proposal',request:r});
  }
  for(const peer of ['host','guest'])send(peer,{type:'prepared',origin,request:r,native:n});
  if(kind==='end-turn')turn++;
  for(const peer of ['host','guest'])send(peer,{type:'observed',id:r.id,...ctx(rev+1,turn),native:n});
  rev++;
 }
 assert.equal(c.mode,'finishing');assert.equal(c.stage,5);assert.equal(c.turn,4);
 for(const peer of ['host','guest'])send(peer,{type:'complete',revision:5,witness:ctx(5,4).witness,native:n});
 assert.equal(c.mode,'complete');console.log('Repeated-turn coordinator sequence passed (fake messages).');
}
const context=n=>({revision:n,phase:n<3?'player2':'player3',witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],testRevision:n})});
const guard={guardActive:true,sessionState:1,releaseFailed:false};
function fixture(){
  const sent=[],events=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e));
  const send=(peer,message)=>c.receive(peer,{session,peer,...message});
  for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.13.0',interactive:false,...context(0)});
  return {c,sent,events,send};
}
let count=0;
function test(name,fn){fn();count++;console.log('PASS '+name);}
test('four-command fixture waits for both observed outcomes and both End Turn consents',()=>{
  const {c,send,sent}=fixture();
  for(let n=0;n<4;n++){
    if(n===2){
      assert(sent.filter(x=>x.frame.kind==='READY').every(x=>x.frame.id==='end-turn'));
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

function interactiveFixture(){
  const state={schema:'itb-observation-v1',unavailable:[],pawns:[{localId:0,position:{x:3,y:3},movementSpent:false},{localId:2,position:{x:0,y:3},movementSpent:false}]};
  const ctx={revision:0,phase:'player2',witness:JSON.stringify(state)},sent=[];
  let time=0;const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>time);
  const send=(peer,message)=>c.receive(peer,{session,peer,...message});
  for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.13.0',interactive:true,...ctx});
  const r={session,encounter:'artillery-checkpoint',...ctx,id:'move-guest-1',kind:'move',actor:'artillery',fromX:0,fromY:3,toX:0,toY:2};
  const prepare=()=>{for(const peer of ['host','guest'])send(peer,{type:'prepared',origin:'guest',request:r,native:{...guard,armed:false,pressed:false}});};
  return {c,send,sent,r,ctx,prepare,elapse:ms=>{time+=ms;}};
}
test('interactive barrier waits for explicit proposal and transmits chosen destination',()=>{
  const {c,send,sent,r,ctx,prepare}=interactiveFixture();assert.equal(sent.filter(x=>x.frame.kind==='INPUT').length,2);
  assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,0);send('guest',{type:'proposal',request:r});
  assert.equal(sent.at(-1).frame.move.toY,2);assert.equal(c.mode,'preparing');
  assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,0);prepare();assert.equal(c.mode,'executing');
  for(const peer of ['host','guest'])send(peer,{type:'observed',id:r.id,...ctx,revision:1,native:guard});
  assert.equal(c.stage,1);assert.equal(c.mode,'proposal');
});
test('interactive peer cannot command teammate or stale witness',()=>{
  let f=interactiveFixture();assert.throws(()=>f.send('host',{type:'proposal',request:f.r}),/actor-not-owned/);
  f=interactiveFixture();assert.throws(()=>f.send('guest',{type:'proposal',request:{...f.r,witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[]})}}),/invalid-move-envelope/);
});
test('interactive duplicate during execution cannot submit a second move',()=>{
  const {send,r,sent,prepare}=interactiveFixture();send('guest',{type:'proposal',request:r});prepare();
  assert.throws(()=>send('guest',{type:'proposal',request:r}),/unexpected-proposal/);
  assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,2);
});
console.log('Interactive transport checks complete; fake messages only.');
test('missing runtime preparation times out without dispatch despite bridge traffic',()=>{
  const f=interactiveFixture();f.send('guest',{type:'proposal',request:f.r});
  f.send('guest',{type:'prepared',origin:'guest',request:f.r,native:{...guard,armed:false,pressed:false}});
  f.elapse(3000);assert.throws(()=>f.c.tick(),/game-prepare-timeout/);
  assert.throws(()=>f.send('host',{type:'prepared',origin:'guest',request:f.r,native:{...guard,armed:false,pressed:false}}),/game-prepare-timeout/);
  assert.equal(f.sent.filter(x=>x.frame.kind==='EXEC').length,0);
});
test('changed, duplicate or unprotected preparation never dispatches',()=>{
  for(const failure of ['changed','duplicate','guard']){
    const f=interactiveFixture();f.send('guest',{type:'proposal',request:f.r});
    const ack={type:'prepared',origin:'guest',request:f.r,native:{...guard,armed:false,pressed:false}};
    if(failure==='changed')ack.request={...f.r,toY:7};
    if(failure==='guard')ack.native.sessionState=2;
    if(failure==='duplicate')f.send('host',ack);
    assert.throws(()=>f.send('host',ack));assert.equal(f.sent.filter(x=>x.frame.kind==='EXEC').length,0);
  }
});
test('both owned moves need fresh preparation and both outcomes before completion',()=>{
  const f=interactiveFixture();let ctx=f.ctx;
  for(const [index,origin,actor,id,x,y,tx,ty] of [[0,'guest','artillery',2,0,3,0,2],[1,'host','combat',0,3,3,3,2]]){
    const r={...f.r,...ctx,id:`move-${origin}-1`,actor,fromX:x,fromY:y,toX:tx,toY:ty};
    f.send(origin,{type:'proposal',request:r});assert.equal(f.c.mode,'preparing');
    for(const peer of ['guest','host'])f.send(peer,{type:'prepared',origin,request:r,native:{...guard,armed:false,pressed:false}});
    const state=JSON.parse(ctx.witness);const pawn=state.pawns.find(p=>p.localId===id);pawn.position={x:tx,y:ty};pawn.movementSpent=true;
    ctx={revision:index+1,phase:'player2',witness:JSON.stringify(state)};
    for(const peer of ['host','guest'])f.send(peer,{type:'observed',id:r.id,...ctx,native:guard});
  }
  assert.equal(f.c.mode,'finishing');assert.equal(f.sent.filter(x=>x.frame.kind==='EXEC').length,4);
  for(const peer of ['host','guest'])f.send(peer,{type:'complete',revision:2,witness:ctx.witness,native:guard});
  assert.equal(f.c.mode,'complete');
});

test('selected phase requires two explicit ready messages and fresh preparation for all four actions',()=>{
 const sent=[],state={schema:'itb-observation-v1',unavailable:[],pawns:[{localId:0,position:{x:3,y:3},active:true},{localId:1,position:{x:1,y:5},movementSpent:false},{localId:2,position:{x:0,y:3},movementSpent:false}]};
 const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true);
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});let ctx={revision:0,phase:'player2',witness:JSON.stringify(state)};
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.13.0',interactive:true,phaseRun:true,...ctx});
 for(let n=0;n<4;n++){
  const origin=['guest','host','host','guest'][n],r=expected(session,n,ctx);
  if(n!==2)r.id=(n===1?'attack-':'move-')+origin+'-'+(n+1);
  if(n===2){
   assert.equal(c.mode,'readiness');assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,4);
   send('host',{type:'ready',confirmUnused:true,...ctx});assert.equal(c.mode,'readiness');
   assert.throws(()=>send('host',{type:'ready',confirmUnused:true,...ctx}),/unexpected-readiness/);
   assert.throws(()=>send('guest',{type:'ready',confirmUnused:true,...ctx,witness:context(2).witness}),/stale-readiness/);
   assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,4);
   send('guest',{type:'ready',confirmUnused:true,...ctx});
  }else send(origin,{type:'proposal',request:r});
  assert.equal(c.mode,'preparing');
  send('host',{type:'prepared',origin,request:r,native:{...guard,armed:false,pressed:false}});assert.equal(c.mode,'preparing');
  send('guest',{type:'prepared',origin,request:r,native:{...guard,armed:false,pressed:false}});assert.equal(c.mode,'executing');
  assert.throws(()=>send('guest',{type:'proposal',request:r}),/unexpected-proposal/);
  ctx={revision:n+1,phase:n<2?'player2':'player3',witness:JSON.stringify(state)};
  send('host',{type:'observed',id:r.id,...ctx,native:guard});assert.equal(c.mode,'executing');
  send('guest',{type:'observed',id:r.id,...ctx,native:guard});
 }
 assert.equal(c.mode,'finishing');assert.equal(sent.filter(x=>x.frame.kind==='PREPARE').length,8);
 assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,8);
 for(const peer of ['host','guest'])send(peer,{type:'complete',revision:4,witness:ctx.witness,native:guard});
 assert.equal(c.mode,'complete');
});
