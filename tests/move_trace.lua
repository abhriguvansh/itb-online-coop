local trace = dofile('mod/scripts/move_trace.lua')
local json = dofile('mod/scripts/json.lua')
local passed=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); passed=passed+1 end
local function fixture()
    local e={clock=0,Profile={visible_name='ITB_Coop_Probe'},logs={}}
    local p={pos={x=0,y=3},spent=false,undo=false,active=true,busy=false}
    p.GetId=function() return 2 end
    p.GetSpace=function() return p.pos end
    p.IsMovementSpent=function() return p.spent end
    p.IsUndoPossible=function() return p.undo end
    p.GetUndoLoc=function() return {x=1,y=3} end
    p.IsActive=function() return p.active end
    p.GetHealth=function() return 2 end
    p.IsBusy=function() return p.busy end
    e.modApi={getCurrentProfile=function() return 'Alpha' end,getGameVersion=function() return '1.2.93' end,
        elapsedTime=function() return e.clock end}
    e.GetCurrentMission=function() return {ID='Mission_Artillery'} end
    e.Board={IsTipImage=function() return false end,IsBusy=function() return false end,GetPawn=function() return p end}
    e.Game={GetTurnCount=function() return 2 end,GetTeamTurn=function() return 1 end}
    local t=trace.new(e,function(kind,payload) e.logs[#e.logs+1]={kind=kind,payload=payload} end,json)
    return e,p,t
end
test('unchanged previews deduplicate without treating them as execution',function()
    local e,p,t=fixture()
    for i=1,200 do t:observe('build',p,'Move',p.pos,{x=0,y=i%8}) end
    assert(#e.logs==1 and e.logs[1].payload.stage=='build' and next(t.watched)==nil)
    assert(e.logs[1].payload.changesGameplay==false and e.logs[1].payload.proofOfCommitBoundary==false)
end)
test('execution captures latest preview and observed bookkeeping separately',function()
    local e,p,t=fixture(); t:observe('build',p,'Move',p.pos,{x=0,y=2})
    t:observe('build',p,'Move',p.pos,{x=0,y=1})
    assert(#e.logs==1) -- target changes alone do not create duplicate state records
    p.spent=true; p.undo=true; t:observe('onSkillStart',p,'Move',p.pos,{x=0,y=2})
    local data=e.logs[2].payload
    assert(data.state.movementSpent and not data.detail.lastBuild.state.movementSpent)
    assert(data.detail.lastBuild.target.to.y==1 and data.detail.target.to.y==2)
    p.pos.x=6; assert(data.state.position.x==0) -- retained values are copies
end)
test('after execution watches state changes then expires',function()
    local e,p,t=fixture(); t:observe('onSkillEnd',p,'Move'); t:update(); assert(#e.logs==1)
    p.spent=true; e.clock=100; t:update(); assert(#e.logs==2 and e.logs[2].payload.stage=='update')
    e.clock=2001; p.active=false; t:update(); assert(#e.logs==2 and next(t.watched)==nil)
end)
test('missing getters are explicit and do not stop tracing',function()
    local e,p,t=fixture(); p.GetUndoLoc=nil; p.IsMovementSpent=function() error('missing native read') end
    t:observe('build',p,'Move'); assert(#e.logs==1 and #e.logs[1].payload.state.unavailable==2)
    assert(e.logs[1].payload.state.movementSpent==nil)
end)
test('normal profiles and missing identity emit nothing',function()
    local e,p,t=fixture(); e.Profile.visible_name='normal'; t:observe('build',p,'Move'); t:update()
    e.Profile=nil; t:observe('onSkillStart',p,'Move'); assert(#e.logs==0)
end)
test('other missions versions weapons and pawns are ignored',function()
    local e,p,t=fixture(); t:observe('build',p,'Prime_Punchmech')
    p.GetId=function() return 100 end; t:observe('build',p,'Move')
    p.GetId=function() return 2 end; e.GetCurrentMission=function() return {ID='Mission_Test'} end
    t:observe('build',p,'Move'); e.GetCurrentMission=function() return {ID='Mission_Artillery'} end
    e.modApi.getGameVersion=function() return 'other' end; t:observe('build',p,'Move'); assert(#e.logs==0)
end)
test('output budget is bounded and resets with context',function()
    local e,p,t=fixture(); for i=1,500 do t:observe('onSkillStart',p,'Move') end
    assert(#e.logs==129 and e.logs[129].kind=='move_trace_limit')
    t:reset(); t:observe('build',p,'Move'); assert(#e.logs==130 and not t.limited)
end)
test('diagnostic errors are contained and reported once',function()
    local e,p,t=fixture(); p.GetId=function() error('bad pawn') end
    t:observe('build',p,'Move'); t:observe('build',p,'Move'); t:update()
    assert(#e.logs==1 and e.logs[1].kind=='move_trace_error')
end)
test('disappearing pawn closes its watch without retaining userdata',function()
    local e,p,t=fixture(); t:observe('onSkillEnd',p,'Move'); e.Board.GetPawn=function() return nil end
    t:update(); assert(e.logs[2].payload.stage=='pawn-missing' and next(t.watched)==nil)
end)
test('reset clears preview and watch across contexts',function()
    local e,p,t=fixture(); t:observe('build',p,'Move'); t:observe('onSkillStart',p,'Move'); t:reset()
    p.spent=true; t:update(); assert(#e.logs==2 and next(t.previews)==nil)
end)
print('Move trace contract tests: '..passed..' passed.')
