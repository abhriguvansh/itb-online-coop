local M=dofile('mod/scripts/shared_xp.lua');local json=dofile('mod/scripts/json.lua')
local function fixture()
    local v={abi='itb-shared-xp-v1',fault=0,active=false,count=0,entries={}};local events={}
    local n={xpInfo=function()return v end,xpBegin=function(context)v.active=true;v.context=context;v.count=0;v.entries={};return v end,
        xpFinish=function()v.active=false;return v end}
    local e={package={loadlib=function()return function()return n end end},Profile={visible_name='ITB_Coop_Probe'},modApi={getCurrentProfile=function()return 'Alpha'end}}
    local s=M.new(e,'fixture/',json,function(k,p)events[#events+1]={k,p}end)
    return s,v,e,events
end
do
    local s,v,_,events=fixture();local r={phase='player2',revision=16,id='end-turn-16'}
    s:begin('session',r);assert(v.context=='session/player2/16/end-turn-16')
    assert(not pcall(function()s:begin('session',r)end),'overlap cannot install another hook')
    v.count=1;v.entries={{limit=3,applied=123,raw=456}}
    local out=s:finish();assert(not v.active and not s.context and out.entries[1].applied==123 and out.entries[1].raw==nil)
    assert(#events==2 and not pcall(function()s:finish()end))
end
do local s,v=fixture();s:begin('session',{phase='player1',revision=4,id='attack-host-1'});v.fault=3;assert(not pcall(function()s:healthy()end));s:stop();assert(not v.active) end
do local s,_,e=fixture();e.Profile.visible_name='Aman';assert(not pcall(function()s:begin('session',{phase='player1',revision=4,id='attack-host-1'})end)) end
do local s,v=fixture();s:begin('session',{phase='player1',revision=4,id='attack-host-1'});v.count=1;v.entries={{limit=4,applied=1}};assert(not pcall(function()s:finish()end)) end
print('Shared XP lifecycle: exact command context, overlap/profile/native-fault refusal, restored hook and applied-only comparison (native doubles).')
