const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const files = execFileSync('git',['ls-files','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const rejected = files.filter(file => /(^|\/)(\.local|node_modules|profile_[^/]*|\.env)(\/|$)/i.test(file)
  || /\.(dll|exe|dat|zip|log|sav)$/i.test(file)
  || /(^|\/)(settings|profile|saveData|undoSave)\.lua$/i.test(file)
  || (fs.existsSync(file) && fs.statSync(file).size > 1024*1024));
if (rejected.length) {
  console.error('Unexpected private, binary, or oversized tracked files:', rejected.join(', '));
  process.exitCode = 1;
} else console.log(`Tracked-file guard: ${files.length} files checked. Review content before publication.`);
