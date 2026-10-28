// File identity for the restricted alpha; no Git installation is required by a guest.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function compatibility(root=path.resolve(__dirname,'..')){
  const files=['package.json'];
  for(const dir of ['tools','mod/scripts','native'])for(const name of fs.readdirSync(path.join(root,dir))){
    if(/\.(cjs|ps1|psm1|lua|c|h)$/.test(name))files.push(dir+'/'+name);
  }
  return {protocol:'itb-coop-launch-v1',probe:JSON.parse(fs.readFileSync(path.join(root,'package.json'),'utf8')).version,
    sourceSha256:sha(files.sort().map(file=>file+'\0'+sha(fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'))+'\n').join(''))};
}
module.exports={compatibility};
