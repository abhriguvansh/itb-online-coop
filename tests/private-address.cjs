const a=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const {isPrivateAddress}=require('../tools/phase-coordinator.cjs');
for(const ip of ['10.0.2.2','172.16.0.1','172.31.255.254','192.168.1.10','100.64.0.1','100.127.255.254','127.0.0.1'])a.equal(isPrivateAddress(ip),true);
for(const ip of [null,42,'','localhost','0.0.0.0','8.8.8.8','172.15.1.1','172.32.0.1','100.63.0.1','100.128.0.1','127.0.0.2','010.0.2.2','10.0.2.02','10..2.2','10.0.2.256','10.0.2.2.','10.0.2.2\n','10.0.2.2:80','224.0.0.1','255.255.255.255'])a.equal(isPrivateAddress(ip),false);
for(const [mode,tail] of [['--native-primary-choice',['--private-address','8.8.8.8']],['--interactive',['--private-address','127.0.0.1']],['--native-primary-choice',['--private-address']],['--native-primary-choice',['--unknown','127.0.0.1']]]){
 const root=path.resolve('.local','refused-endpoint-'+Date.now()+'-'+Math.random().toString(36).slice(2));
 const r=spawnSync(process.execPath,['tools/phase-coordinator.cjs',root,mode,...tail],{encoding:'utf8',windowsHide:true});a.equal(r.status,1);a.equal(fs.existsSync(root),false,'invalid address/options must not create a session or listener');
}
console.log('Private endpoint policy: canonical RFC1918/CGNAT/exact loopback, public/DNS/wildcard/malformed and non-native mode refusal before a listener exists.');
