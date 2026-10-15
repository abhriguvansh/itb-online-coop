const assert=require('node:assert/strict');
const {createFixedCombatFixture}=require('../tools/fixed-combat-fixture.cjs');
function context(stage=0,spawn){
 const messages=[],records=[],state={pawns:[{localId:0,position:{x:3,y:3}},{localId:1,position:{x:1,y:5}},{localId:2,position:{x:0,y:3}}]};
 if(spawn)state.pawns.push(spawn);
 const witness=JSON.stringify(state),phase=stage<4?'player2':stage<10?'player3':'player4';
 const core={session:'fixed-fixture',stage,mode:'proposal',states:{host:{witness,phase},guest:{witness,phase}},require:(ok,why)=>assert.ok(ok,why),receive:(peer,message)=>messages.push({peer,message})};
 return {core,messages,records,record:r=>records.push(r)};
}
{
 const tick=createFixedCombatFixture(),x=context();tick(x.core,x.record);tick(x.core,x.record);
 assert.equal(x.messages.length,1);const r=x.messages[0].message.request;
 assert.equal(r.kind,'basic-attack');assert.equal(r.actor,'combat');assert.equal(r.witness,x.core.states.host.witness);
 assert.equal(x.records[0].humanSelectionProof,false);
 x.core.stage=6;tick(x.core,x.record);assert.equal(x.messages[1].message.request.kind,'basic-attack');
}
{
 const tick=createFixedCombatFixture(),x=context();let calls=0;
 x.core.receive=()=>{calls++;throw Error('uncertain-admission')};
 assert.throws(()=>tick(x.core,x.record),/uncertain-admission/);tick(x.core,x.record);assert.equal(calls,1);
}
{
 const tick=createFixedCombatFixture(),x=context(3);tick(x.core,x.record);tick(x.core,x.record);
 assert.deepEqual(x.messages.map(m=>m.peer),['host','guest']);assert.ok(x.messages.every(m=>m.message.type==='ready'&&m.message.confirmUnused===true));
 assert.equal(x.records[0].humanReadinessProof,false);
}
{
 const tick=createFixedCombatFixture(),x=context(12,{localId:123,type:'Scorpion1',position:{x:4,y:4},queuedTarget:{x:4,y:3}});
 assert.throws(()=>tick(x.core,x.record),/fixture-unsupported-observed-spawn/);assert.equal(x.messages.length,0);
 x.core.states.host.witness=JSON.stringify({pawns:[{localId:2,position:{x:0,y:1}},{localId:123,type:'Scorpion1',position:{x:4,y:4},queuedTarget:{x:3,y:4}}]});
 tick(x.core,x.record);assert.equal(x.messages[0].message.request.toY,3);
}
{
 const tick=createFixedCombatFixture(),x=context();x.core.mode='executing';tick(x.core,x.record);assert.equal(x.messages.length,0);
 x.core.mode='proposal';x.core.stage=17;assert.throws(()=>tick(x.core,x.record),/fixture-command-limit/);assert.equal(x.messages.length,0);
}
console.log('Fixed combat fixture: standard attacks, no retries, scripted consent labels, unsupported spawn and phase waits passed (engine doubles).');
{
 const tick=createFixedCombatFixture(),x=context(12,{localId:123,type:'Firefly1',position:{x:5,y:4},queuedTarget:{x:4,y:4}});
 tick(x.core,x.record);x.core.stage=13;tick(x.core,x.record);
 assert.deepEqual([x.messages[1].message.request.toX,x.messages[1].message.request.toY],[5,3]);
 x.core.stage=14;tick(x.core,x.record);assert.equal(x.messages[2].message.request.toY,3);
 x.core.stage=15;tick(x.core,x.record);assert.equal(x.messages[3].message.request.toY,2);
}
