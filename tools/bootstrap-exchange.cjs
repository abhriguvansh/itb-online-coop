// One bounded, live initialization batch for the existing fresh Tides experiment.
// No native thread waits on networking; the guest installs before mission entry.
const assert=require('node:assert/strict');
function validateTranscript(text){
  assert.equal(typeof text,'string');assert(text.length<=2048&&text.endsWith('\n'));
  const rows=text.slice(0,-1).split('\n');assert(rows.length===19||rows.length===20);
  rows.forEach((row,i)=>{
    const match=/^([a-z-]+)\|([0-9]+)\|([0-9]+)$/.exec(row);assert(match);
    assert.equal(match[1],i<17?'ai-constructor':i===17?'pod-delivery':rows.length===20&&i===18?'pod-special':'pod-select');
    assert.equal(match[2],String(i<17?32768:i===17?3:rows.length===20&&i===18?100:9));
    assert.equal(String(Number(match[3])),match[3]);assert(Number(match[3])<=32767);
  });return text;
}
class BootstrapExchange{
  constructor(session,send,record){this.session=session;this.send=send;this.record=record;this.seals={};}
  receive(peer,m){
    assert(!this.complete,'bootstrap-after-agreement');
    assert.equal(m.session,this.session,'bootstrap-session');assert.equal(m.peer,peer,'bootstrap-role');
    assert.equal(m.probe,'0.32.0','bootstrap-version');assert.equal(m.fixture,'tides-fresh-v1','bootstrap-fixture');
    assert.equal(m.game,'1.2.93','bootstrap-game');assert.equal(m.abi,'itb-initial-choices-v1','bootstrap-abi');
    if(m.type==='bootstrap_ready'){
      assert.equal(peer,'guest');assert(!this.guestReady,'duplicate-bootstrap-ready');this.guestReady=true;
    }else if(m.type==='bootstrap_offer'){
      assert.equal(peer,'host');assert(!this.offer,'duplicate-bootstrap-offer');
      this.offer=validateTranscript(m.witness);this.count=this.offer.trimEnd().split('\n').length;this.record({type:'bootstrap_host_choices',count:this.count});
    }else if(m.type==='bootstrap_sealed'){
      assert(this.offer&&!this.seals[peer],'bootstrap-seal-order');
      if(peer==='guest')assert(this.delivered&&this.guestReady,'bootstrap-guest-not-prepared');
      assert.equal(validateTranscript(m.witness),this.offer,'bootstrap-seal-disagreement');
      const n=m.native;assert(n&&n.installed===false&&n.fault===0&&n.overflow===false&&n.count===this.count,'bootstrap-hooks-not-restored');
      assert.equal(n.passThrough,peer==='host');assert.equal(n.expectedCount,peer==='host'?0:this.count);
      assert.equal(n.sealed,peer==='guest');assert.equal(m.mission,'Mission_Tides');
      assert.equal(m.profile,'ITB_Coop_Probe');this.seals[peer]=true;
      this.record({type:'bootstrap_sealed',peer,count:this.count});
    }else throw Error('unknown-bootstrap-message');
    if(this.offer&&this.guestReady&&!this.delivered){
      this.send('guest',{kind:'BOOTSTRAPCHOICES',session:this.session,witness:this.offer});this.delivered=true;
    }
    if(this.seals.host&&this.seals.guest){
      this.complete=true;
      for(const role of ['host','guest'])this.send(role,{kind:'BOOTSTRAPREADY',session:this.session,witness:this.offer});
      this.record({type:'bootstrap_agreed',count:this.count,capturedFileRequired:false});
    }
  }
}
module.exports={BootstrapExchange,validateTranscript};
