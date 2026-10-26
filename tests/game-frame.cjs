const assert=require('node:assert/strict'),{gameFrame,packet}=require('../tools/game-frame.cjs');
const base={kind:'PING',session:'11111111-1111-1111-1111-111111111111',peer:'-',revision:0,phase:'-',id:'-',witness:''};
assert.equal(gameFrame(base),`PING|${base.session}|-|0|-|-\n`);
for(const actor of ['combat','cannon','artillery'])for(const kind of ['move','basic-attack','deploy']){
 const m={...base,kind:'EXEC',peer:'guest',move:{actor,kind,fromX:kind==='deploy'?-1:1,fromY:kind==='deploy'?-1:5,toX:2,toY:5}};
 const p=packet(m),cut=p.indexOf(10);assert.equal(Number(p.subarray(0,cut).toString()),p.length-cut-1);
 assert(p.toString().includes(kind==='deploy'?'deploy'+actor:kind==='basic-attack'?'attack'+actor:actor));
}
assert.equal(gameFrame({...base,kind:'BOOTSTRAPREADY',witness:'rows\n'}),`BOOTSTRAPREADY|${base.session}\nrows\n`);
for(const value of [{session:'stale'},{kind:'UNKNOWN'},{revision:33},{phase:'bad|phase'},{witness:'bad\nline'},
 {kind:'EXEC',move:{actor:'cannon',kind:'lab-punch',fromX:1,fromY:5,toX:2,toY:5}}])assert.throws(()=>packet({...base,...value}));
console.log('Native TCP frame encoder preserves existing game framing and refuses malformed bounds/actors (serializer only).');
