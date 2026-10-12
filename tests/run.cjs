const fs = require('node:fs');
const path = require('node:path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const luaparse = require('luaparse');
const { runReportTests } = require('./report.cjs');

process.chdir(path.resolve(__dirname, '..'));
const files = fs.readdirSync('mod/scripts').filter(name => name.endsWith('.lua'));
for (const file of files) {
  luaparse.parse(fs.readFileSync(`mod/scripts/${file}`, 'utf8'), { luaVersion: '5.1' });
}
console.log(`Lua 5.1 syntax: ${files.length} mod files passed.`);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
for (const suite of ['tests/probe.lua', 'tests/movement.lua', 'tests/move_trace.lua', 'tests/input_gate.lua']) {
  if (lauxlib.luaL_dofile(L, to_luastring(suite)) !== lua.LUA_OK) {
    console.error(lua.lua_tojsstring(L, -1));
    process.exitCode = 1;
    break;
  }
}
if (!process.exitCode) {
  runReportTests();
  console.log('Contract tests use Fengari (Lua 5.3) and engine doubles. No in-game result is implied.');
}
lua.lua_close(L);
