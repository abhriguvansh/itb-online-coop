const fs = require('node:fs');
const crypto = require('node:crypto');
const MAX_BYTES = 64 * 1024 * 1024;
const MAX_LINE = 1024 * 1024;

function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  return '{' + Object.keys(value).sort().map(key => JSON.stringify(key)+':'+canonical(value[key])).join(',') + '}';
}
function diff(left, right, at = '$', output = []) {
  if (output.length >= 1000 || canonical(left) === canonical(right)) return output;
  if (left && right && typeof left === 'object' && typeof right === 'object'
      && Array.isArray(left) === Array.isArray(right)) {
    for (const key of [...new Set([...Object.keys(left),...Object.keys(right)])].sort()) {
      diff(left[key], right[key], `${at}.${key}`, output);
    }
  } else {
    const change = { field: at, left: left ?? null, right: right ?? null };
    if (left === undefined) change.leftMissing = true;
    if (right === undefined) change.rightMissing = true;
    output.push(change);
  }
  return output;
}
function parse(text) {
  if (Buffer.byteLength(text) > MAX_BYTES) throw new Error('Log exceeds 64 MiB.');
  const records = [];
  for (const [index,line] of text.split(/\r?\n/).entries()) {
    const offset = line.indexOf('ITBCOOP ');
    if (offset < 0) continue;
    if (Buffer.byteLength(line) > MAX_LINE) throw new Error(`Oversized record at line ${index+1}.`);
    let value;
    try { value = JSON.parse(line.slice(offset + 8)); }
    catch { throw new Error(`Malformed probe JSON at line ${index+1}.`); }
    if (value.schema !== 'itb-probe-log-v1' || typeof value.event !== 'string'
        || !Number.isSafeInteger(value.sequence) || value.sequence < 1
        || !Number.isSafeInteger(value.epoch) || !value.payload || typeof value.payload !== 'object') {
      throw new Error(`Invalid record shape at line ${index+1}.`);
    }
    if (value.event === 'settled_candidate' && (!value.payload.state
        || value.payload.state.schema !== 'itb-observation-v1')) {
      throw new Error(`Invalid state at line ${index+1}.`);
    }
    records.push(value);
  }
  return records;
}
function summarize(records) {
  const counts = Object.create(null);
  const boundaries = [];
  for (const record of records) {
    counts[record.event] = (counts[record.event] || 0) + 1;
    if (record.event === 'settled_candidate') {
      const state = record.payload.state;
      boundaries.push({ sequence: record.sequence, epoch: record.epoch,
        turn: state.turn, team: state.team,
        observationSha256: crypto.createHash('sha256').update(canonical(state)).digest('hex'),
        unavailableFields: state.unavailable, coverage: state.coverage });
    }
  }
  return { records: records.length, counts, boundaries,
    interpretation: 'Observed fields only. Hash equality does not prove synchronization, legality, or quiescence.' };
}
function readLog(file) {
  if (fs.statSync(file).size > MAX_BYTES) throw new Error('Log exceeds 64 MiB.');
  return parse(fs.readFileSync(file, 'utf8'));
}
function main(args) {
  if (args.length === 1) return summarize(readLog(args[0]));
  if (args.length !== 5 || args[0] !== '--diff') {
    throw new Error('Usage: npm run report -- LOG | --diff LEFT_LOG LEFT_SEQUENCE RIGHT_LOG RIGHT_SEQUENCE');
  }
  const select = (file, sequence) => {
    const matches = readLog(file).filter(r=>r.event==='settled_candidate' && r.sequence===Number(sequence));
    if(matches.length!==1) throw new Error('Select one unambiguous settled_candidate sequence from each log.');
    return matches[0].payload.state;
  };
  return { warning: 'Caller must verify equivalent scenario and action boundary; local pawn IDs are not mapped.',
    differences: diff(select(args[1],args[2]),select(args[3],args[4])), maxDifferences: 1000 };
}
module.exports = { canonical, diff, parse, summarize };
if (require.main === module) {
  try { console.log(JSON.stringify(main(process.argv.slice(2)),null,2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
