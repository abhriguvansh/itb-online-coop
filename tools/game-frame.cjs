// The existing game decoder's text format over a length-prefixed TCP stream.
const assert=require('node:assert/strict');
const kinds=['PING','STOP','PROPOSE','READY','CONSENT','EXEC','DONE','INPUT','PREPARE','SPAWNSELECT','SPAWNAPPLY','SPAWNRELEASE','RESULTCONTINUE','RESULTDONE'];
function gameFrame(f){
 assert(typeof f.session==='string'&&/^[a-f0-9-]{36}$/.test(f.session));
 assert(typeof f.witness==='string');
 if(['BOOTSTRAPCHOICES','BOOTSTRAPREADY'].includes(f.kind)){
  assert(f.witness.length<=2048);return `${f.kind}|${f.session}\n${f.witness}`;
 }
 assert(kinds.includes(f.kind)&&['host','guest','-'].includes(f.peer));
 assert(Number.isInteger(f.revision)&&f.revision>=0&&f.revision<=32);
 for(const key of ['phase','id'])assert(typeof f[key]==='string'&&/^[\w.:-]{1,96}$/.test(f[key]));
 const spawn=f.kind.startsWith('SPAWN');
 assert(f.witness.length<=65536&&!f.witness.includes('\r')&&(spawn||!f.witness.includes('\n')));
 const header=[f.kind,f.session,f.peer,f.revision,f.phase,f.id];
 if(f.move){
  const m=f.move;assert(['EXEC','PREPARE'].includes(f.kind)&&['combat','cannon','artillery'].includes(m.actor));
  assert(['move','lab-punch','basic-attack','deploy'].includes(m.kind));
  assert(m.kind!=='lab-punch'||m.actor==='combat');
  for(const key of ['fromX','fromY','toX','toY'])assert(Number.isInteger(m[key])&&
    (m.kind==='deploy'&&key.startsWith('from')?m[key]===-1:m[key]>=0&&m[key]<=7));
  const actor=m.kind==='deploy'?'deploy'+m.actor:m.kind==='lab-punch'?'punch':m.kind==='basic-attack'?'attack'+m.actor:m.actor;
  header.push(actor,m.fromX,m.fromY,m.toX,m.toY);
 }
 return header.join('|')+'\n'+f.witness;
}
function packet(frame){const body=Buffer.from(gameFrame(frame),'utf8');assert(body.length>0&&body.length<=70000);return Buffer.concat([Buffer.from(body.length+'\n'),body]);}
module.exports={gameFrame,packet};
