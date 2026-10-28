const assert=require('node:assert/strict'),{BootstrapExchange,validateTranscript}=require('../tools/bootstrap-exchange.cjs');
const text='ai-constructor|32768|42\n'.repeat(17)+'pod-delivery|3|123\npod-select|9|234\n';
const base={session:'test',probe:'0.31.0',fixture:'tides-fresh-v1',game:'1.2.93',abi:'itb-initial-choices-v1'};
function fixture(witness=text){
 const count=witness.trimEnd().split('\n').length;
 const sent=[],records=[],b=new BootstrapExchange('test',(peer,m)=>sent.push({peer,...m}),r=>records.push(r));
 const send=(peer,type,extra={})=>b.receive(peer,{...base,peer,type,...extra});
 const offer=()=>send('host','bootstrap_offer',{witness});
 const ready=()=>send('guest','bootstrap_ready');
 const seal=(peer,extra={})=>send(peer,'bootstrap_sealed',{witness,profile:'ITB_Coop_Probe',mission:'Mission_Tides',
   native:{installed:false,fault:0,overflow:false,count,passThrough:peer==='host',expectedCount:peer==='host'?0:count,sealed:peer==='guest',...extra}});
 return {b,sent,records,send,offer,ready,seal};
}
assert.equal(validateTranscript(text),text);
for(const bad of [text+'\n',text.slice(0,-1),text.replace('|42','|042'),text.replace('|42','|32768'),text.replace('pod-select|9','pod-select|8')])assert.throws(()=>validateTranscript(bad));
for(const order of [0,1]){
 const f=fixture();if(order){f.ready();f.offer();}else{f.offer();assert.equal(f.sent.length,0);f.ready();}
 assert.equal(f.sent.length,1);assert.equal(f.sent[0].peer,'guest');assert.equal(f.sent[0].witness,text);
 f.seal('host');assert(!f.b.complete);f.seal('guest');assert(f.b.complete);
 assert.equal(f.sent.filter(m=>m.kind==='BOOTSTRAPREADY').length,2);
 assert.throws(()=>f.seal('guest'));
}
for(const [key,value] of [['session','stale'],['peer','guest'],['probe','old'],['game','different'],['fixture','different'],['abi','different']]){
 const f=fixture();assert.throws(()=>f.send('host','bootstrap_offer',{witness:text,[key]:value}));assert(!f.b.complete);
}
for(const native of [{installed:true},{fault:8},{overflow:true},{count:18},{passThrough:false},{expectedCount:19},{sealed:true}]){
 const f=fixture();f.offer();f.ready();assert.throws(()=>f.seal('host',native));assert(!f.b.complete);
}
{const f=fixture();f.offer();assert.throws(()=>f.seal('guest'));assert.throws(()=>f.offer());}
{const f=fixture();f.ready();assert.throws(()=>f.ready());assert.throws(()=>f.seal('host'));}
{const f=fixture();f.offer();f.ready();assert.throws(()=>f.send('guest','bootstrap_sealed',{witness:text.replace('|42','|43')}));}
console.log('Live bootstrap protocol: original host batch, guest readiness, exact restored-hook seals, stale/duplicate/mismatch refusal passed (fake peers).');

{
 const pod=text.replace('pod-select|9|234','pod-special|100|8055\npod-select|9|20506');
 assert.equal(validateTranscript(pod),pod);
 for(const bad of [pod.replace('pod-special|100','pod-special|99'),pod.replace('pod-special|100','pod-select|100'),pod+'pod-select|9|1\n'])assert.throws(()=>validateTranscript(bad));
 const f=fixture(pod);f.offer();f.ready();f.seal('host');assert(!f.b.complete);f.seal('guest');assert(f.b.complete);
 assert(f.records.filter(r=>r.type==='bootstrap_agreed').every(r=>r.count===20));
 const g=fixture(pod);g.offer();g.ready();assert.throws(()=>g.seal('guest',{count:19,expectedCount:19}));
}
console.log('Observed 20-choice pod-arrival transcript uses exact extra draw and seal counts; malformed/short replay refuses (fake peers).');
