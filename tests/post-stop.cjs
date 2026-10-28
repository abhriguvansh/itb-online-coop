// Real loopback sockets; no game process or native executable.
const fs=require('node:fs'),path=require('node:path'),net=require('node:net'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
(async()=>{
 const root=path.resolve('.local','post-stop-test-'+Date.now()+'-'+process.pid,'session');fs.mkdirSync(path.dirname(root),{recursive:true});
 const child=spawn(process.execPath,['tools/phase-coordinator.cjs',root,'--interactive'],{stdio:['ignore','pipe','pipe'],windowsHide:true});
 let ended=false,output='',lateSent=false;const sockets=[],peers={};child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>output+=v);
 const exited=new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',code=>{ended=true;resolve(code);});});
 const timeout=setTimeout(()=>{for(const s of sockets)s.destroy();child.kill();},10000);
 try{
  const start=Date.now();while(!fs.existsSync(path.join(root,'guest.json'))){assert(!ended&&Date.now()-start<5000,'startup: '+output);await new Promise(r=>setTimeout(r,20));}
  const configs=Object.fromEntries(['host','guest'].map(p=>[p,JSON.parse(fs.readFileSync(path.join(root,p+'.json'),'utf8'))]));
  const witness=JSON.stringify({schema:'itb-observation-v1',unavailable:[],pawns:[{localId:2,position:{x:0,y:3},active:true,movementSpent:false}]});
  const ctx={revision:0,phase:'player2',witness};
  const connect=async()=>{const s=net.createConnection({host:'127.0.0.1',port:configs.host.port});sockets.push(s);s.on('error',()=>{});await new Promise((resolve,reject)=>{s.once('connect',resolve);s.once('error',reject)});return s;};
  const send=(p,m)=>peers[p].write(JSON.stringify({session:configs[p].session,peer:p,...m})+'\n');
  const inputs=new Set();let resolveInputs;const ready=new Promise(r=>resolveInputs=r);
  for(const p of ['host','guest']){const s=peers[p]=await connect();let pending='';s.setEncoding('utf8');s.on('data',chunk=>{pending+=chunk;let cut;while((cut=pending.indexOf('\n'))>=0){const m=JSON.parse(pending.slice(0,cut));pending=pending.slice(cut+1);if(m.kind==='INPUT'){inputs.add(p);if(inputs.size===2)resolveInputs();}if(m.kind==='PING')send(p,{type:'pong'});if(m.kind==='STOP'&&p==='guest'&&!lateSent){lateSent=true;send('guest',{type:'proposal',request:{session:configs.guest.session,encounter:'artillery-checkpoint',...ctx,id:'move-guest-1',kind:'move',actor:'artillery',fromX:0,fromY:3,toX:0,toY:2}});}}});
   send(p,{type:'hello',token:configs[p].token});send(p,{type:'armed',probe:'0.33.0',interactive:true,...ctx});}
  await Promise.race([ready,exited.then(()=>{throw Error('coordinator exited before both INPUT frames: '+output)})]);const invalid=await connect();invalid.write(JSON.stringify({type:'hello',session:configs.host.session,peer:'host',token:'invalid-test-token'})+'\n');
  assert.equal(await exited,1);assert(lateSent,'test must send the legal proposal after receiving STOP');
  const e=fs.readFileSync(path.join(root,'events.jsonl'),'utf8').trim().split(/\r?\n/).map(JSON.parse),i=e.findIndex(v=>v.type==='stopped');assert(i>=0);assert.equal(e[i].reason,'authentication-failed');
  assert.deepEqual(e.slice(i+1),[],'latched stop must consume no queued peer messages or prepare another action');
  assert.equal(e.filter(v=>v.type==='prepare'||v.type==='dispatch').length,0);
  console.log('Real loopback stopped coordinator ignores a legal proposal sent after STOP during its socket-drain window (fake game peers).');
 }finally{clearTimeout(timeout);for(const s of sockets)s.destroy();if(!ended)child.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
