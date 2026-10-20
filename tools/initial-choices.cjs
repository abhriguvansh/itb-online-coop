// Extract data only from a completed pass-through normal-game reference.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
function extract(text){
  const observations=text.split(/\r?\n/).filter(line=>line.includes('ITBCOOP ')).map(line=>JSON.parse(line.slice(line.indexOf('ITBCOOP ')+8)))
    .filter(e=>e.event==='initial_choice_trace');
  assert(observations.some(e=>e.payload.boundary==='onNextTurn'),'normal initial phase reference missing');
  for(const e of observations){const v=e.payload.native;assert(v.passThrough===true&&v.fault===0&&v.overflow===false&&v.count===19&&v.entries.length===19,'incomplete or altered native reference');}
  assert(observations.length,'native reference missing');
  const rows=observations.at(-1).payload.native.entries.map((e,i)=>{
    assert(e.kind===(i<17?'ai-constructor':i===17?'pod-delivery':'pod-select')&&e.limit===(i<17?32768:i===17?3:9)&&Number.isInteger(e.value)&&e.value>=0&&e.value<=32767,'unsupported reference shape');
    assert(e.applied===undefined||e.applied===e.value,'reference changed a native draw');
    return `${e.kind}|${e.limit}|${e.value}\n`;
  });
  const result=rows.join('');
  for(const e of observations)assert(e.payload.native.entries.map(x=>`${x.kind}|${x.limit}|${x.value}\n`).join('')===result,'reference choice sequence changed');
  return result;
}
if(require.main===module){
  const [input,output]=process.argv.slice(2);assert(input&&output,'Usage: node tools/initial-choices.cjs PRIVATE_LOG PRIVATE_OUTPUT');
  const root=path.resolve('.local')+path.sep;
  for(const file of [input,output])assert(path.resolve(file).startsWith(root),'Keep raw references and transcripts under .local');
  fs.writeFileSync(output,extract(fs.readFileSync(input,'utf8')),{flag:'wx'});
  console.log('19 normal native choices extracted; private transcript created without overwriting.');
}
module.exports={extract};
