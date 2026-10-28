const a=require('node:assert/strict'),{PhaseCoordinator}=require('../tools/phase-coordinator.cjs'),{PrimarySetup}=require('../tools/primary-setup.cjs');
const actors=['combat','cannon','artillery'],native={guardActive:true,sessionState:1,releaseFailed:false,armed:false,pressed:false};
function fixture(){
 const sent=[],events=[],c=new PhaseCoordinator('primary-test',(peer,frame)=>sent.push({peer,frame}),r=>events.push(r),true,()=>0,true,true,false,true,true);
 c.primarySetup=new PrimarySetup(c);
 const state={schema:'itb-observation-v1',unavailable:[],mission:'Mission_Tides',turn:0,team:6,
  initialChoices:Array.from({length:19},(_,i)=>({kind:i<17?'ai-constructor':i===17?'pod-delivery':'pod-select',limit:i<17?32768:i===17?3:9,value:42})),
  deployment:{inProgress:true,phase:0,mechs:[0,1,2].map(id=>({id,state:id?1:0,x:-1,y:-1}))},pawns:[0,1,2].map(localId=>({localId,position:{x:-1,y:-1},active:true}))};
 const ctx={revision:0,phase:'deployment',witness:JSON.stringify(state)};
 const send=(peer,m)=>c.receive(peer,{session:c.session,peer,...ctx,native,...m});
 for(const peer of ['host','guest'])send(peer,{type:'armed',probe:'0.32.0',interactive:true,phaseRun:true,repeatedTurns:true,deployment:true,fullMission:true,primarySetup:true,sharedXp:'itb-shared-xp-v1'});
 const choose=(peer,primary,sharedController='host')=>send(peer,{type:'primary_choice',primary,sharedController});
 const ready=peer=>send(peer,{type:'primary_ready',generation:c.primarySetup.generation,confirm:true});
 const applied=peer=>send(peer,{type:'primary_applied',generation:c.primarySetup.generation,owners:c.primarySetup.snapshot().owners});
 return {c,sent,events,send,choose,ready,applied,ctx};
}
for(const h of actors)for(const g of actors.filter(v=>v!==h))for(const shared of ['host','guest']){
 const f=fixture();a.equal(f.c.mode,'primary');a(!f.sent.some(x=>x.frame.kind==='INPUT'));
 f.choose('host',h,shared);f.choose('guest',g,shared);const owners=f.c.primarySetup.snapshot().owners;
 a.equal(owners[h],'host');a.equal(owners[g],'guest');a.equal(owners[actors.find(x=>x!==h&&x!==g)],shared);
 f.ready('host');a.equal(f.c.mode,'primary');f.ready('guest');a.equal(f.c.mode,'primary-applying');
 f.applied('host');a(!f.sent.some(x=>x.frame.kind==='INPUT'));f.applied('guest');a.equal(f.c.mode,'proposal');
 a.equal(f.events.filter(x=>x.type==='primary_assignments_locked').length,1);
 const owner=owners.combat,other=owner==='host'?'guest':'host';
 const r={session:f.c.session,encounter:'artillery-checkpoint',...f.ctx,id:'move-'+owner+'-1',kind:'deploy',actor:'combat',fromX:-1,fromY:-1,toX:1,toY:4};
 a.throws(()=>f.send(other,{type:'proposal',request:r}),/actor-not-owned/);
 f.send(owner,{type:'proposal',request:r});a.equal(f.c.mode,'preparing');
 f.send('host',{type:'prepared',origin:owner,request:r});a.equal(f.events.filter(x=>x.type==='dispatch').length,0);
 f.send('guest',{type:'prepared',origin:owner,request:r});a.equal(f.events.filter(x=>x.type==='dispatch').length,1);
 a.throws(()=>f.choose('host',h,shared),/primary-setup-closed/);
}
{
 const f=fixture();f.choose('host','combat');f.choose('guest','combat');a.equal(f.c.primarySetup.snapshot().owners,null);
 a.throws(()=>f.ready('host'),/primary-ready-conflict/);a(!f.sent.some(x=>x.frame.kind==='INPUT'));
 f.choose('guest','artillery','guest');a.equal(f.c.primarySetup.snapshot().owners,null);
 f.choose('guest','artillery');f.ready('host');const old=f.c.primarySetup.generation;
 f.choose('guest','cannon');a.deepEqual(f.c.primarySetup.ready,{});
 f.send('host',{type:'primary_ready',generation:old,confirm:true});a.deepEqual(f.c.primarySetup.ready,{});
 a.equal(f.events.filter(x=>x.type==='primary_ready_stale').length,1);
 f.ready('guest');a.equal(f.c.mode,'primary');f.ready('host');
 a.throws(()=>f.send('host',{type:'primary_applied',generation:f.c.primarySetup.generation,owners:{combat:'guest',cannon:'host',artillery:'host'}}),/primary-applied-mismatch/);
 a(!f.sent.some(x=>x.frame.kind==='INPUT'));
}
{
 const f=fixture();a.throws(()=>f.send('host',{type:'primary_choice',primary:'combat',sharedController:'host',native:{...native,guardActive:false}}),/primary-setup-protection/);
 a.throws(()=>f.send('host',{type:'primary_choice',primary:'combat',sharedController:'host',witness:'changed'}),/invalid|incomplete|Unexpected|stale/);
 a(!f.sent.some(x=>['INPUT','PREPARE','EXEC'].includes(x.frame.kind)));
}
console.log('Primary setup: all 12 distinct-primary/first-controller combinations, conflict and stale approval, immutable assignment, both applied acknowledgments and normal owner/two-preparation gates (fake game peers).');
