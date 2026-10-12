const assert = require('node:assert/strict');
const {canonical, diff, parse, summarize} = require('../tools/probe-report.cjs');
exports.runReportTests = () => {
  assert.equal(canonical({b:1,a:false}),canonical({a:false,b:1}));
  assert.notEqual(canonical({a:false}),canonical({}));
  assert.deepEqual(diff({pawn:{health:3}},{pawn:{health:2}}),[{field:'$.pawn.health',left:3,right:2}]);
  assert.deepEqual(diff({}, {x:null}), [{field:'$.x',left:null,right:null,leftMissing:true}]);
  assert.equal(parse('normal game log\n').length,0);
  assert.throws(()=>parse('ITBCOOP {truncated'),/Malformed/);
  assert.throws(()=>parse('ITBCOOP {"schema":"wrong"}'),/Invalid/);
  assert.throws(()=>parse('ITBCOOP '+ 'x'.repeat(1024*1024)),/Oversized/);
  const record = {schema:'itb-probe-log-v1',event:'settled_candidate',sequence:2,epoch:1,
    payload:{state:{schema:'itb-observation-v1',coverage:'partial',unavailable:['rng'],turn:1,team:0}}};
  const result = summarize(parse('LOG: ITBCOOP '+JSON.stringify(record)));
  assert.equal(result.counts.settled_candidate,1);
  assert.equal(result.boundaries[0].observationSha256.length,64);
  assert.deepEqual(result.boundaries[0].unavailableFields,['rng']);
  console.log('Log analysis assertions: 11 passed.');
};
