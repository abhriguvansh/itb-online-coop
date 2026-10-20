local M=dofile('mod/scripts/initial_choices.lua');local json=dofile('mod/scripts/json.lua')
local text=string.rep('ai-constructor|32768|42\n',17)..'pod-delivery|3|123\n'..'pod-select|9|123\n'
local rows=M.parse(text,json);assert(#rows==19 and rows[19].value==123)
assert(json.encode(rows):sub(1,1)=='[')
for _,bad in ipairs({text..'\n',text:sub(1,-2),text:gsub('pod%-select|9','pod-select|8'),
    text:gsub('|42','|32768'),text:gsub('|42','|-1'),text:gsub('|42','|042'),
    text:gsub('ai%-constructor','pod-select'),text..'pod-select|9|1\n',string.rep('x',2049)})do
    assert(not pcall(M.parse,bad,json))
end
local disabled=M.install({os={getenv=function()return nil end}},'',function()error('disabled mode touched runtime')end)
assert(not disabled.enabled)
local callbacks,records={},{};local state={abi='itb-initial-choices-v1',count=0,fault=0,entries={},installed=true}
local native={info=function()return state end,install=function(r)assert(#r==19);return state end,
    restore=function()state={abi='itb-initial-choices-v1',count=19,expectedCount=19,fault=0,entries={},installed=false,sealed=true}end}
local e={os={getenv=function()return 'replay'end},package={loadlib=function()return function()return native end end},
    io={open=function(p)assert(p=='C:/ITBCoopProbe/initial-choices.txt');return {read=function()return text end,close=function()end}end},modApi={events={}}}
for _,name in ipairs({'onMissionStart','onDeploymentPhaseStart','onLandingPhaseStart','onDeploymentPhaseEnd','onNextTurn','onMissionUpdate'})do
    local n=name;e.modApi.events[n]={subscribe=function(_,fn)callbacks[n]=fn end}
end
local realRequire=require;require=function(name)assert(name=='test/json');return json end
local s=M.install(e,'test/',function(k,p)records[#records+1]={kind=k,payload=p};json.encode(p)end)
require=realRequire
assert(s.enabled and not s.error and not s:healthy())
callbacks.onDeploymentPhaseStart();assert(s:healthy() and records[#records].payload.native.sealed)
state.fault=8;assert(not s:healthy());state.fault=0;state.installed=true;assert(not s:healthy())
state.installed=false;state.count=18;assert(not s:healthy());state.count=19;state.overflow=true;assert(not s:healthy())
print('Initial-choice transcript, disabled mode, seal/admission and fault contracts passed (Lua doubles).')
