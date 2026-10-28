const assert=require('node:assert/strict');
const {PhaseCoordinator,expected}=require('../tools/phase-coordinator.cjs');
const session='fixture-session';
testRepeatedTurns();
{
 const make=(frozen=false,building=false)=>{
  const c=new PhaseCoordinator(session,()=>{},()=>{},true,()=>0,true,true);
  c.stage=8;c.turn=1;c.mode='executing';c.executionDeadline=240000;c.pendingKind='reset-turn';c.pendingId='reset-turn-8';
  const state={schema:'itb-observation-v1',unavailable:[],tiles:[{terrain:3,building,frozen,health:4}],pawns:[]};
  c.resetBaseWitness=JSON.stringify(state);
  const message=(peer,health)=>({session,peer,type:'observed',id:c.pendingId,revision:9,phase:'player1',resetRemaining:0,native:{guardActive:true,sessionState:1,releaseFailed:false},witness:JSON.stringify({...state,tiles:[{...state.tiles[0],health}]})});
  return {c,message};
 };
 const good=make();for(const peer of ['host','guest'])good.c.receive(peer,good.message(peer,2));assert.equal(good.c.stage,9);
 for(const pair of [[true,false],[false,true]]){const bad=make(...pair);assert.throws(()=>bad.c.receive('host',bad.message('host',2)),/reset-outcome-or-allowance-mismatch/);}
 const unequal=make();unequal.c.receive('host',unequal.message('host',2));assert.throws(()=>unequal.c.receive('guest',unequal.message('guest',3)),/state-divergence/);
 console.log('Reset permits normal unfrozen-water rehydration only in baseline comparison; frozen/building HP and raw peer equality stay strict (fake peers).');
}

{
 const sent=[],events=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>0,true,true);
 const n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 const ctx=(revision,turn,x=0,spent=false)=>({revision,phase:'player'+turn,witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn,pawns:[{localId:2,position:{x,y:3},active:true,movementSpent:spent}]})});
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,phaseRun:true,repeatedTurns:true,...ctx(0,2)});
 const vote=(revision,turn,x=0)=>({type:'reset_ready',confirmReset:true,...ctx(revision,turn,x,x!==0)});
 assert.throws(()=>send('host',vote(0,2)),/reset-unavailable/);
 for(const peer of ['host','guest'])send(peer,{type:'ready',confirmUnused:true,...ctx(0,2)});
 const apply=(origin,r,next,extra={})=>{
  for(const peer of ['host','guest'])send(peer,{type:'prepared',origin,request:r,native:n});
  for(const peer of ['host','guest'])send(peer,{type:'observed',id:r.id,native:n,...next,...extra});
 };
 apply('host',c.proposal.request,ctx(1,3));
 const move=(id,revision,fromX,toX,spent=false)=>({session,encounter:'artillery-checkpoint',...ctx(revision,3,fromX,spent),id,kind:'move',actor:'artillery',fromX,fromY:3,toX,toY:3});
 let r=move('move-guest-1',1,0,1);send('guest',{type:'proposal',request:r});apply('guest',r,ctx(2,3,1,true));
 send('host',vote(2,3,1));assert.equal(c.mode,'reset-readiness');assert.equal(sent.filter(v=>v.frame.kind==='EXEC').length,4);
 assert.throws(()=>send('host',vote(2,3,1)),/duplicate-reset-readiness/);
 // Another action cancels the uncommitted request, requiring both fresh votes.
 r={...move('undo-guest-2',2,1,0,true),kind:'undo-move'};send('guest',{type:'proposal',request:r});apply('guest',r,ctx(3,3));
 assert(events.some(v=>v.type==='reset_cancelled'));
 r=move('move-guest-3',3,0,2);send('guest',{type:'proposal',request:r});apply('guest',r,ctx(4,3,2,true));
 assert.throws(()=>send('guest',vote(2,3,1)),/wrong-phase-or-revision/);
 send('guest',vote(4,3,2));send('host',vote(4,3,2));r=c.proposal.request;
 assert.equal(r.kind,'reset-turn');assert.equal(r.confirmReset,true);assert.equal(c.mode,'preparing');
 assert.equal(sent.filter(v=>v.frame.kind==='EXEC').length,8);
 for(const peer of ['host','guest'])send(peer,{type:'prepared',origin:'host',request:r,native:n});
 assert.throws(()=>send('host',{type:'observed',id:r.id,native:n,...ctx(5,3),resetRemaining:1}),/reset-outcome-or-allowance-mismatch/);
 for(const peer of ['host','guest'])send(peer,{type:'observed',id:r.id,native:n,...ctx(5,3),resetRemaining:0});
 assert.equal(c.stage,5);assert.equal(c.turn,3);assert(c.resetUsed);
 assert.throws(()=>send('guest',vote(5,3)),/reset-unavailable/);
 assert.throws(()=>send('guest',{type:'proposal',request:move('move-guest-1',5,0,1)}),/duplicate-request/);
 r=move('move-guest-4',5,0,1);send('guest',{type:'proposal',request:r});apply('guest',r,ctx(6,3,1,true));
 assert.equal(c.stage,6);
 console.log('Reset requires a fresh phase baseline, unanimous fresh consent, both preparations and native allowance decrement; cancellation and replay history survive (fake peers).');
}
{
 const sent=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true,true);
 const n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 const ctx=(revision,x,y,spent)=>({revision,phase:'player2',witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn:2,pawns:[{localId:2,position:{x,y},active:true,movementSpent:spent}]})});
 for(const peer of ['host','guest'])c.receive(peer,{type:'armed',session,peer,probe:'0.33.0',interactive:true,phaseRun:true,repeatedTurns:true,...ctx(0,0,3,false)});
 const proposal=(kind,id,revision,fromX,fromY,toX,toY,spent)=>({session,encounter:'artillery-checkpoint',...ctx(revision,fromX,fromY,spent),id,kind,actor:'artillery',fromX,fromY,toX,toY});
 const first=proposal('move','move-guest-1',0,0,3,0,2,false);
 const apply=(r,next)=>{
  c.receive('guest',{type:'proposal',session,peer:'guest',request:r});
  for(const peer of ['host','guest'])c.receive(peer,{type:'prepared',session,peer,origin:'guest',request:r,native:n});
  for(const peer of ['host','guest'])c.receive(peer,{type:'observed',session,peer,id:r.id,native:n,...next});
 };
 const noHistory=proposal('undo-move','undo-guest-1',0,0,3,0,2,false);
 assert.throws(()=>c.receive('guest',{type:'proposal',session,peer:'guest',request:noHistory}),/no-current-owned-move-to-undo/);
 apply(first,ctx(1,0,2,true));
 const undo=proposal('undo-move','undo-guest-2',1,0,2,0,3,true);
 assert.throws(()=>c.receive('guest',{type:'proposal',session,peer:'guest',request:{...undo,toX:1}}),/no-current-owned-move-to-undo/);
 apply(undo,ctx(2,0,3,false));assert.equal(c.undoMoves.length,0);
 apply(proposal('move','move-guest-3',2,0,3,1,3,false),ctx(3,1,3,true));
 assert.equal(c.stage,3);assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,6);
 console.log('Undo is tied to one completed owned move, both preparations and a fresh following move (fake peers).');
}
{
 const sent=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true,true);
 const n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 const state=(artillery,combat)=>JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn:2,pawns:[{localId:2,position:{x:0,y:artillery},active:true,movementSpent:artillery===2},{localId:0,position:{x:combat,y:3},active:true,movementSpent:combat===2}]});
 const ctx=(revision,artillery=3,combat=3)=>({revision,phase:'player2',witness:state(artillery,combat)});
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,phaseRun:true,repeatedTurns:true,...ctx(0)});
 const request=(peer,kind,actor,id,fromX,fromY,toX,toY)=>({session,encounter:'artillery-checkpoint',phase:'player2',revision:c.stage,witness:c.states.host.witness,id:kind==='move'?'move-'+peer+'-'+id:'undo-'+peer+'-'+id,kind,actor,fromX,fromY,toX,toY});
 const apply=(origin,r,next)=>{
  send(origin,{type:'proposal',request:r});
  for(const peer of ['host','guest'])send(peer,{type:'prepared',origin,request:r,native:n});
  for(const peer of ['host','guest'])send(peer,{type:'observed',id:r.id,native:n,...next});
 };
 apply('guest',request('guest','move','artillery',1,0,3,0,2),ctx(1,2));
 const stale=request('guest','undo-move','artillery',2,0,2,0,3);
 apply('host',request('host','move','combat',1,3,3,2,3),ctx(2,2,2));
 assert.throws(()=>send('guest',{type:'proposal',request:request('guest','undo-move','artillery',3,0,2,0,3)}),/no-current-owned-move-to-undo/);
 apply('host',request('host','undo-move','combat',2,2,3,3,3),ctx(3,2));
 assert.throws(()=>send('guest',{type:'proposal',request:stale}),/wrong-phase-or-revision/);
 apply('guest',request('guest','undo-move','artillery',4,0,2,0,3),ctx(4));
 assert.equal(c.stage,4);assert.equal(c.undoMoves.length,0);assert.equal(sent.filter(v=>v.frame.kind==='EXEC').length,8);
 console.log('Native reverse move order preserves older ownership after newer Undo, refuses skipping and stale requests (fake peers).');
}
{
 const make=()=>{
  const sent=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true,true);
  const witness=JSON.stringify({schema:'itb-observation-v1',unavailable:[],turn:2,pawns:[{localId:0,position:{x:3,y:3},active:true,movementSpent:false,health:2}]});
  for(const peer of ['host','guest'])c.receive(peer,{type:'armed',session,peer,probe:'0.33.0',interactive:true,phaseRun:true,repeatedTurns:true,revision:0,phase:'player2',witness});
  const request={session,encounter:'artillery-checkpoint',revision:0,phase:'player2',witness,id:'repair-host-1',kind:'repair',actor:'combat',fromX:3,fromY:3,toX:3,toY:3};
  return {c,sent,request};
 };
 const f=make();f.c.receive('host',{session,peer:'host',type:'proposal',request:f.request});
 assert.equal(f.c.mode,'preparing');assert.equal(f.sent.filter(v=>v.frame.kind==='EXEC').length,0);
 const n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 for(const peer of ['host','guest'])f.c.receive(peer,{type:'prepared',session,peer,origin:'host',request:f.request,native:n});
 assert.equal(f.sent.filter(v=>v.frame.kind==='EXEC').length,2);
 assert.throws(()=>f.c.receive('host',{session,peer:'host',type:'proposal',request:f.request}));
 const wrong=make();assert.throws(()=>wrong.c.receive('guest',{session,peer:'guest',type:'proposal',request:wrong.request}));
 const target=make();assert.throws(()=>target.c.receive('host',{session,peer:'host',type:'proposal',request:{...target.request,toX:4}}),/repair-must-target-self/);
 console.log('Repair proposals retain owner binding, self target, both preparations and duplicate refusal (fake peers).');
}
function testRepeatedTurns(){
 const sent=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true,true);
 const send=(peer,m)=>c.receive(peer,{session,peer,...m});
 const ctx=(revision,turn)=>({revision,phase:'player'+turn,witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],pawns:[{localId:2,position:{x:0,y:3},movementSpent:false,active:true}],turn})});
 const n={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,phaseRun:true,repeatedTurns:true,...ctx(0,2)});
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
 assert.equal(c.mode,'proposal');assert.equal(c.stage,5);assert.equal(c.turn,4);
 assert.equal(sent.filter(x=>x.frame.kind==='DONE').length,0);
 assert.throws(()=>send('host',{type:'complete',revision:5,witness:ctx(5,4).witness,native:n}),/unexpected-completion/);
 console.log('Repeated-turn coordinator continues beyond player4 without false completion (fake messages).');
}
const context=n=>({revision:n,phase:n<3?'player2':'player3',witness:JSON.stringify({schema:'itb-observation-v1',unavailable:[],testRevision:n})});
const guard={guardActive:true,sessionState:1,releaseFailed:false};
function spawnFixture(){
  const sent=[],events=[];let time=0;
  const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>time,true,true);
  c.mode='executing';c.executionDeadline=240000;c.pendingKind='end-turn';c.stage=3;c.states={host:{phase:'player2'},guest:{phase:'player2'}};
  const witness=JSON.stringify({board:{schema:'itb-observation-v1',unavailable:[]},spawner:'{}'});
  const message=(type,extra={})=>({type,session,revision:3,phase:'player2',index:1,witness,native:guard,...extra});
  const send=(peer,type,extra)=>c.receive(peer,{...message(type,extra),peer});
  return {c,sent,events,send,witness,elapse:ms=>time+=ms};
}
{
 const f=spawnFixture();f.send('guest','spawn_prepare');assert.equal(f.sent.length,0);
 f.send('host','spawn_prepare');assert.equal(f.sent[0].peer,'host');assert.equal(f.sent[0].frame.kind,'SPAWNSELECT');
 const choice={pawnType:'Scorpion1',pawnId:123,x:5,y:3,calls:[{limit:4,value:2}],afterSpawner:'{}'};
 assert.throws(()=>f.send('guest','spawn_selected',choice),/unauthorized-selection/);
 f.send('host','spawn_selected',choice);assert.equal(f.sent[1].frame.kind,'SPAWNAPPLY');
 assert.throws(()=>f.send('host','spawn_selected',choice),/unauthorized-selection/);
 f.send('guest','spawn_applied');assert.equal(f.c.spawnIndex,1);assert.equal(f.c.spawn,null);
 assert.deepEqual(f.sent.slice(2).map(x=>x.frame.kind),['SPAWNRELEASE','SPAWNRELEASE']);
 assert.throws(()=>f.send('guest','spawn_applied'),/stale-context/);
 const bad=spawnFixture();bad.send('host','spawn_prepare');
 assert.throws(()=>bad.send('guest','spawn_prepare',{witness:JSON.stringify({...JSON.parse(bad.witness),spawner:'{"different":true}'})}),/precondition-divergence/);
 const timeout=spawnFixture();timeout.send('guest','spawn_prepare');timeout.elapse(20000);assert.throws(()=>timeout.c.tick(),/spawn-prepare-timeout/);
 const unauthorized=spawnFixture();unauthorized.c.pendingKind='move';assert.throws(()=>unauthorized.send('host','spawn_prepare'),/outside-end-turn/);
 const outcome=spawnFixture();outcome.send('host','spawn_prepare');outcome.send('guest','spawn_prepare');outcome.send('host','spawn_selected',choice);
 assert.throws(()=>outcome.send('guest','spawn_applied',{witness:JSON.stringify({...JSON.parse(outcome.witness),spawner:'{"changed":true}'})}),/outcome-divergence/);
 assert.equal(outcome.sent.filter(x=>x.frame.kind==='SPAWNRELEASE').length,0);
 const malformed=spawnFixture();malformed.send('host','spawn_prepare');malformed.send('guest','spawn_prepare');
 assert.throws(()=>malformed.send('host','spawn_selected',{...choice,calls:[{limit:4,value:4}]}),/invalid-random/);
 console.log('Spawn exchange rejects missing, stale, duplicate, unauthorized and conflicting peer data (fake messages).');
}
function fixture(){
  const sent=[],events=[];const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e));
  const send=(peer,message)=>c.receive(peer,{session,peer,...message});
  for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:false,...context(0)});
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
  for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,...ctx});
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
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,phaseRun:true,...ctx});
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

test('repeated-turn basic weapon proposal still needs exact both-runtime preparation',()=>{
 const state={schema:'itb-observation-v1',unavailable:[],pawns:[{localId:1,position:{x:1,y:5},active:true}]},sent=[];
 const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),()=>{},true,()=>0,true,true);
 const ctx={revision:0,phase:'player2',witness:JSON.stringify(state)},send=(peer,m)=>c.receive(peer,{session,peer,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.33.0',interactive:true,phaseRun:true,repeatedTurns:true,...ctx});
 const request={session,encounter:'artillery-checkpoint',...ctx,id:'attack-guest-1',kind:'basic-attack',actor:'cannon',fromX:1,fromY:5,toX:1,toY:3};
 assert.throws(()=>send('host',{type:'proposal',request}),/actor-not-owned/);
 send('guest',{type:'proposal',request});assert.equal(c.mode,'preparing');
 send('host',{type:'prepared',origin:'guest',request,native:{...guard,armed:false,pressed:false}});
 assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,0);
 send('guest',{type:'prepared',origin:'guest',request,native:{...guard,armed:false,pressed:false}});
 assert.equal(sent.filter(x=>x.frame.kind==='EXEC').length,2);
});
{
 const make=()=>{
  const sent=[],events=[];let clock=0;
  const c=new PhaseCoordinator(session,(peer,frame)=>sent.push({peer,frame}),e=>events.push(e),true,()=>clock,true,true);
  c.stage=16;c.turn=4;c.mode='executing';c.executionDeadline=240000;c.pendingKind='end-turn';c.pendingId='end-turn-16';c.states={host:{phase:'player4'},guest:{phase:'player4'}};
  const witness=JSON.stringify({schema:'itb-observation-v1',unavailable:[],pawns:[]});
  const guard={guardActive:true,sessionState:1,releaseFailed:false};
  const msg=(peer,type,body=witness)=>({session,peer,type,id:'end-turn-16',revision:16,phase:'player4',witness:body,native:guard});
  return {c,sent,events,msg,witness,elapse:n=>clock+=n};
 };
 const {c,sent,msg,events}=make();c.receive('host',msg('host','result_prepared'));
 assert.equal(sent.length,0);assert.throws(()=>c.receive('host',msg('host','result_prepared')),/duplicate-preparation/);
 c.receive('guest',msg('guest','result_prepared'));assert.equal(sent.filter(s=>s.frame.kind==='RESULTCONTINUE').length,2);
 const result={schema:'itb-mission-result-v1',coverage:'partial-result-only',region:2,regionState:2,mission:'',grid:2,reputation:1,pilots:[0,1,2].map(slot=>({slot,id:'p'+slot,experience:slot,level:0,skill1:3,skill2:0})),objectives:[{slot:0,text:'Mission_Artillery_Obj',value:1,potential:1},{slot:1,text:'Bonus_Simple_Asset',value:1,potential:1}]};
 const after=JSON.stringify(result);
 c.receive('host',msg('host','result_observed',after));assert.equal(c.mode,'result-executing');
 c.receive('guest',msg('guest','result_observed',after));assert.equal(c.mode,'result-finishing');
 c.receive('host',msg('host','complete',after));assert.equal(c.mode,'result-finishing');
 c.receive('guest',msg('guest','complete',after));assert.equal(c.mode,'complete');assert(events.some(e=>e.terminal&&e.revision===17));
 const stale=make();assert.throws(()=>stale.c.receive('host',{...stale.msg('host','result_prepared'),revision:15}),/stale-context/);
 const early=make();early.c.turn=3;assert.throws(()=>early.c.receive('host',early.msg('host','result_prepared')),/outside-final/);
 const lost=make();assert.throws(()=>lost.c.receive('host',{...lost.msg('host','result_prepared'),native:{...guard,sessionState:2}}),/protection-lost/);
 const timed=make();timed.c.receive('host',timed.msg('host','result_prepared'));timed.elapse(90001);assert.throws(()=>timed.c.tick(),/result-timeout/);
 const mismatch=make();for(const peer of ['host','guest'])mismatch.c.receive(peer,mismatch.msg(peer,'result_prepared'));
 mismatch.c.receive('host',mismatch.msg('host','result_observed',after));
 assert.throws(()=>mismatch.c.receive('guest',mismatch.msg('guest','result_observed',JSON.stringify({...result,reputation:2}))),/outcome-divergence/);
 const missingSkill=make();for(const peer of ['host','guest'])missingSkill.c.receive(peer,missingSkill.msg(peer,'result_prepared'));
 const incomplete=structuredClone(result);delete incomplete.pilots[0].skill1;
 assert.throws(()=>missingSkill.c.receive('host',missingSkill.msg('host','result_observed',JSON.stringify(incomplete))),/incomplete-pilots/);
 const changedSkill=make();for(const peer of ['host','guest'])changedSkill.c.receive(peer,changedSkill.msg(peer,'result_prepared'));
 changedSkill.c.receive('host',changedSkill.msg('host','result_observed',after));
 const changedPilot=structuredClone(result);changedPilot.pilots[0].skill1=4;
 assert.throws(()=>changedSkill.c.receive('guest',changedSkill.msg('guest','result_observed',JSON.stringify(changedPilot))),/outcome-divergence/);
 console.log('Terminal coordinator requires both preparations, committed result equality and both acknowledgments (fake peers).');
 const fresh=make();fresh.c.fullMission=true;fresh.c.deployment=true;
 assert.throws(()=>fresh.c.receive('host',fresh.msg('host','result_prepared')),/outside-final/,'Tides does not use the Artillery turn-four boundary');
 fresh.c.turn=3;fresh.c.states={host:{phase:'player3'},guest:{phase:'player3'}};
 fresh.c.proposal={request:{phase:'player3'}};
 const xp={abi:'itb-shared-xp-v1',context:session+'/player3/16/end-turn-16',entries:[]};
 const freshMsg=(peer,type,body)=>({...fresh.msg(peer,type,body),phase:'player3',sharedXp:xp});
 for(const peer of ['host','guest'])fresh.c.receive(peer,freshMsg(peer,'result_prepared'));
 assert.throws(()=>fresh.c.receive('host',freshMsg('host','result_observed',after)),/uncommitted-state/,'old fixture region cannot finish a fresh mission');
 const freshResult={...result,region:1,objectives:[{slot:0,text:'Bonus_GridDamage',value:0,potential:1},{slot:1,text:'Bonus_Power',value:1,potential:1}]};
 const freshAfter=JSON.stringify(freshResult);
 for(const peer of ['host','guest'])fresh.c.receive(peer,freshMsg(peer,'result_observed',freshAfter));
 assert.equal(fresh.c.mode,'result-finishing');
 for(const peer of ['host','guest'])fresh.c.receive(peer,freshMsg(peer,'complete',freshAfter));
 assert.equal(fresh.c.mode,'complete','mission completion does not require every bonus objective to succeed');
 const podResult={...freshResult,objectives:[...freshResult.objectives,{slot:2,text:'Pod_Failed',category:3,param1:'',param2:'',value:0,potential:1}]};
 for(const variant of ['observed','unknown','wrong-category','changed-peer']){
  const p=make();p.c.fullMission=true;p.c.turn=3;p.c.states={host:{phase:'player3'},guest:{phase:'player3'}};
  p.c.proposal={request:{phase:'player3'}};
  const send=(peer,type,value)=>p.c.receive(peer,{...p.msg(peer,type,value),phase:'player3',sharedXp:xp});
  for(const peer of ['host','guest'])send(peer,'result_prepared');
  const value=structuredClone(podResult);
  if(variant==='unknown')value.objectives[2].text='Pod_Unobserved';
  if(variant==='wrong-category')value.objectives[2].category=2;
  if(variant==='unknown'||variant==='wrong-category')assert.throws(()=>send('host','result_observed',JSON.stringify(value)),/incomplete-objectives/);
  else{
   send('host','result_observed',JSON.stringify(value));
   if(variant==='changed-peer')assert.throws(()=>send('guest','result_observed',freshAfter),/outcome-divergence/);
   else{send('guest','result_observed',JSON.stringify(value));assert.equal(p.c.mode,'result-finishing');}
  }
 }
 console.log('Only the observed third Pod_Failed result is admitted; unknown variants and differing peer objectives refuse (fake peers).');
 for(const variant of ['missing','context','limit','different']){
  const p=make();p.c.fullMission=true;p.c.turn=3;p.c.states={host:{phase:'player3'},guest:{phase:'player3'}};p.c.proposal={request:{phase:'player3'}};
  const send=(peer,value)=>p.c.receive(peer,{...p.msg(peer,'result_prepared'),phase:'player3',sharedXp:value});
  const good={...xp,entries:[{limit:3,applied:123}]};
  if(variant==='different'){send('host',good);assert.throws(()=>send('guest',{...good,entries:[{limit:3,applied:124}]}),/shared-xp-divergence/);}
  else assert.throws(()=>send('host',variant==='missing'?undefined:variant==='context'?{...good,context:'stale'}:{...good,entries:[{limit:4,applied:123}]}),/shared-xp-/);
  assert.equal(p.sent.filter(v=>v.frame.kind==='RESULTCONTINUE').length,0,'unagreed XP cannot authorize result navigation');
 }
 console.log('Shared-XP proof requires exact command context, supported limits and equal applied draws before Continue (fake peers).');
}
