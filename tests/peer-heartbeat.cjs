// Real loopback sockets, fake game peers: writes must not conceal a silent runtime.
const fs=require('node:fs'),path=require('node:path'),net=require('node:net'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
(async()=>{
 const root=path.resolve('.local','heartbeat-test-'+Date.now()+'-'+process.pid);
 const child=spawn(process.execPath,['tools/phase-coordinator.cjs',root,'--native-primary-choice','--private-address','127.0.0.1'],{stdio:['ignore','pipe','pipe'],windowsHide:true});
 let output='',ended=false;const sockets=[],counts={host:0,guest:0};
 child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>output+=v);
 const exited=new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',code=>{ended=true;resolve(code);});});
 const timeout=setTimeout(()=>{for(const s of sockets)s.destroy();child.kill();},25000);
 try{
  const start=Date.now();
  while(!fs.existsSync(path.join(root,'guest.json'))){assert(!ended&&Date.now()-start<5000,'coordinator startup failed: '+output);await new Promise(r=>setTimeout(r,25));}
  for(const peer of ['host','guest']){
   const c=JSON.parse(fs.readFileSync(path.join(root,peer+'.json'),'utf8'));
   assert.equal(c.host,'127.0.0.1');
   const native=fs.readFileSync(path.join(root,peer+'-native.txt'),'utf8').split('\n');assert.equal(native[0],'itb-transport-v2');assert.equal(native[3],c.host);
   const socket=net.createConnection({host:'127.0.0.1',port:c.port});sockets.push(socket);
   let pending=Buffer.alloc(0);
   socket.on('error',()=>{});
   socket.on('data',chunk=>{
    pending=Buffer.concat([pending,chunk]);
    for(;;){const cut=pending.indexOf(10);if(cut<0)return;const n=Number(pending.subarray(0,cut).toString());if(pending.length<cut+1+n)return;
     const frame=pending.subarray(cut+1,cut+1+n).toString();pending=pending.subarray(cut+1+n);
     if(frame.startsWith('PING|')){counts[peer]++;if(peer==='host')socket.write(JSON.stringify({type:'pong',session:c.session})+'\n');}
    }
   });
   await new Promise((resolve,reject)=>{socket.once('error',reject);socket.once('connect',resolve);});
   socket.write(JSON.stringify({type:'hello',session:c.session,peer,token:c.token})+'\n');
  }
  assert.equal(await exited,1,'silent peer must stop the experiment');
  const events=fs.readFileSync(path.join(root,'events.jsonl'),'utf8').trim().split(/\r?\n/).map(JSON.parse);
  assert.equal(events.at(-1).type,'stopped');assert.equal(events.at(-1).reason,'peer-heartbeat-timeout:guest');
  assert(counts.host>=10&&counts.guest>=10,'both sockets must keep receiving outbound heartbeats');
  assert.equal(events.filter(e=>e.type==='dispatch'||e.type==='barrier').length,0);
  console.log('Real loopback coordinator: outgoing PING cannot renew a silent peer; acknowledged host stays live, silent guest stops before gameplay (fake game peers).');
 }finally{clearTimeout(timeout);for(const s of sockets)s.destroy();if(!ended)child.kill();}
})().catch(error=>{console.error(error);process.exitCode=1;});
