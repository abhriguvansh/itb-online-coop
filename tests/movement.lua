local movement = dofile('mod/scripts/movement.lua')
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
    passed = passed + 1
end
local function list(values)
    return { size = function() return #values end, index = function(_, i) return values[i] end }
end
local function fixture(path)
    local env = { TEAM_PLAYER = 1, TEAM_ANY = 2, TERRAIN_ROAD = 0, TERRAIN_FOREST = 6, clock = 0,
        Profile = { visible_name = 'ITB_Coop_Probe' }, ArtiMech = {}, calls = 0,
        mission = { ID = 'Mission_Artillery' }, turn = 2, phase = 1, logs = {} }
    env.Point = function(x,y) return {x=x,y=y} end
    local pawn = { position = env.Point(1,3), spent = false, active = true, health = 3 }
    env.pawn = pawn
    pawn.GetId = function() return 2 end
    pawn.GetType = function() return 'ArtiMech' end
    pawn.GetTeam = function() return 1 end
    pawn.GetSpace = function() return pawn.position end
    pawn.GetHealth = function() return pawn.health end
    pawn.GetMoveSpeed = function() return 3 end
    pawn.GetPathProf = function() return 0 end
    pawn.IsActive = function() return pawn.active end
    pawn.IsMovementSpent = function() return pawn.spent end
    pawn.IsUndoPossible = function() return pawn.spent end
    pawn.GetUndoLoc = function() return env.Point(1,3) end
    pawn.IsPowered = function() return true end
    for _, key in ipairs({'IsBusy','IsDead','IsFrozen','IsGrappled','IsFlying','IsJumper',
            'IsTeleporter','IsFire','IsAcid','IsAbility'}) do pawn[key] = function() return false end end
    pawn.Move = function(_, p) env.calls = env.calls + 1; env.requested = p; return true end
    env.Board = { IsTipImage = function() return false end, IsBusy = function() return false end,
        GetPawns = function() return list({2}) end, GetPawn = function() return pawn end,
        IsValid = function(_,p) return p.x >= 0 and p.y >= 0 and p.x < 8 and p.y < 8 end,
        IsPawnSpace = function() return false end, GetTerrain = function() return 0 end,
        GetItem = function() return '' end,
        GetReachable = function() return list({env.Point(1,2),env.Point(0,3),env.Point(2,3),env.Point(1,4)}) end }
    for _, key in ipairs({'IsFire','IsAcid','IsSmoke','IsFrozen','IsSpawning','IsPod',
            'IsCracked','IsEnvironmentDanger','IsDangerous','IsDangerousItem'}) do
        env.Board[key] = function() return false end
    end
    env.modApi = { getCurrentProfile = function() return 'Alpha' end,
        getGameVersion = function() return '1.2.93' end, elapsedTime = function() return env.clock end,
        deployment = {isDeploymentPhase=function() return false end, isLandingPhase=function() return false end} }
    env.sdlext = {isGame=function() return true end, isConsoleOpen=function() return false end}
    env.memedit = {get=function() return {} end}
    env.Game = {GetTeamTurn=function() return env.phase end, GetTurnCount=function() return env.turn end}
    env.GetCurrentMission = function() return env.mission end
    env.FULL_DELAY = 1
    env.Board.GetPath = function(_,from,to) return list({from,to}) end
    env.SkillEffect = function() return {AddMove=function(_,route,delay) env.effectRoute=route; assert(delay==1) end} end
    env.effectCalls=0
    env.Board.AddEffect = function() env.effectCalls=env.effectCalls+1 end
    local lab = movement.new(env, function(kind,payload) env.logs[#env.logs+1]={kind=kind,payload=payload} end, path)
    local request = {pawnId=2,from=env.Point(1,3),to=env.Point(1,2),mission='Mission_Artillery',turn=2}
    return env, lab, request
end
test('default observer never moves, including previews and updates', function()
    local env,lab,request=fixture()
    assert(not lab:request(request)); lab:preview(2); lab:update(); assert(env.calls==0)
    assert(lab:arm()); assert(lab:preview(2)); lab:update(); assert(env.calls==0)
end)
local rejections = {
    {'wrong profile',function(e) e.Profile.visible_name='normal' end},
    {'missing profile',function(e) e.Profile=nil end},
    {'unsupported game',function(e) e.modApi.getGameVersion=function() return 'other' end end},
    {'menu open',function(e,l) l.blocked=true end},
    {'console open',function(e) e.sdlext.isConsoleOpen=function() return true end end},
    {'Test Mech excluded',function(e) e.mission.ID='Mission_Test' end},
    {'deployment',function(e) e.modApi.deployment.isDeploymentPhase=function() return true end end},
    {'enemy phase',function(e) e.phase=6 end},
    {'stale turn',function(e) e.turn=3 end},
    {'missing memedit',function(e) e.memedit=nil end},
    {'uncalibrated memedit',function(e) e.memedit.get=function() return nil end end},
    {'occupied destination',function(e) e.Board.IsPawnSpace=function() return true end end},
    {'unreachable destination',function(e) e.Board.GetReachable=function() return list({}) end end},
    {'off board',function(e,l,r) r.to.x=-1 end},
    {'nonadjacent destination',function(e,l,r) r.to.x=4 end},
    {'malformed coordinates',function(e,l,r) r.to.y=0/0 end},
    {'unknown pawn id',function(e,l,r) r.pawnId=99 end},
    {'stale origin',function(e) e.pawn.position=e.Point(2,3) end},
    {'spent movement',function(e) e.pawn.spent=true end},
    {'inactive pawn',function(e) e.pawn.active=false end},
    {'unpowered pawn',function(e) e.pawn.IsPowered=function() return false end end},
    {'webbed pawn',function(e) e.pawn.IsGrappled=function() return true end end},
    {'frozen pawn',function(e) e.pawn.IsFrozen=function() return true end end},
    {'custom movement',function(e) e.ArtiMech.MoveSkill='custom' end},
    {'post move ability',function(e) e.pawn.IsAbility=function() return true end end},
    {'hazard',function(e) e.Board.IsFire=function() return true end end},
    {'item',function(e) e.Board.GetItem=function() return 'Mine' end end},
    {'wrong terrain',function(e) e.Board.GetTerrain=function() return 3 end end},
    {'board busy',function(e) e.Board.IsBusy=function() return true end end},
    {'pawn busy',function(e) e.pawn.IsBusy=function() return true end end},
    {'unknown busy state',function(e) e.Board.IsBusy=function() return nil end end},
    {'missing getter',function(e) e.pawn.IsMovementSpent=nil end},
}
for _, entry in ipairs(rejections) do
    test('reject before native call: '..entry[1],function()
        local e,l,r=fixture(); assert(l:arm()); entry[2](e,l,r)
        assert(not l:request(r)); assert(e.calls==0); assert(e.logs[#e.logs].kind=='move_rejected')
    end)
end
test('revalidate preview against latest live state',function()
    local e,l=fixture(); l:arm(); local r=l:preview(2); e.pawn.spent=true
    assert(not l:request(r)); assert(e.calls==0)
end)
test('one engine call, pending lock, scalar request, and measured postconditions',function()
    local e,l,r=fixture(); l:arm(); assert(l:request(r)); assert(not l:request(r)); assert(e.calls==1)
    r.to.x=7 -- Caller mutation cannot change the in-flight command.
    l:skillEvent('onSkillStart',e.pawn,'Move'); l:skillEvent('onSkillEnd',e.pawn,'Move')
    e.pawn.position=e.Point(1,2); e.pawn.spent=true
    for i=1,3 do e.clock=i*100; l:update() end
    assert(not l.pending); local record=e.logs[#e.logs]
    assert(record.kind=='move_postconditions_observed' and record.payload.startObserved and record.payload.endObserved)
    assert(record.payload.proofOfQuiescence==false)
end)
test('true engine return without consumed allowance is a fault, not a pass',function()
    local e,l,r=fixture(); l:arm(); l:request(r); e.pawn.position=e.Point(1,2)
    e.clock=5100; l:update(); assert(l.fault and not l.pending); assert(e.logs[#e.logs].kind=='move_failed')
    assert(not l:arm()); assert(e.calls==1)
end)
test('engine exception latches uncertainty and prevents a retry',function()
    local e,l,r=fixture(); l:arm(); e.pawn.Move=function() e.calls=e.calls+1; error('fixture') end
    assert(not l:request(r)); assert(not l:request(r)); assert(e.calls==1 and l.fault)
end)
test('context change during movement faults and survives reset',function()
    local e,l,r=fixture(); l:arm(); l:request(r); l:reset('mission'); l:reset('menu')
    assert(l.fault and not l:arm() and not l.pending)
end)
test('successful move cannot be repeated after allowance is consumed',function()
    local e,l,r=fixture(); l:arm(); l:request(r); e.pawn.position=e.Point(1,2); e.pawn.spent=true
    for i=1,3 do e.clock=i*100; l:update() end
    assert(not l:request(r)); assert(e.calls==1 and e.logs[#e.logs].payload.reason=='movement-spent')
end)
test('clear forest origin is allowed but forest destination is excluded',function()
    local e,l,r=fixture(); l:arm()
    e.Board.GetTerrain=function(_,p) return p.y==3 and 6 or 0 end
    assert(l:validate(r)); assert(e.calls==0)
    e.Board.GetTerrain=function() return 6 end
    assert(not l:request(r)); assert(e.calls==0)
end)
test('burning forest origin is rejected before native call',function()
    local e,l,r=fixture(); l:arm()
    e.Board.GetTerrain=function(_,p) return p.y==3 and 6 or 0 end
    e.Board.IsFire=function(_,p) return p.y==3 end
    assert(not l:request(r)); assert(e.calls==0)
end)
test('effect path submits once with void return and never calls native Move',function()
    local e,l,r=fixture('effect'); l:arm(); assert(l:request(r)); assert(not l:request(r))
    assert(e.effectCalls==1 and e.calls==0 and l.pending and not l.fault)
end)
test('effect rejection checks run before building or submitting',function()
    local e,l,r=fixture('effect'); l:arm(); e.pawn.spent=true
    assert(not l:request(r) and e.effectCalls==0 and e.effectRoute==nil)
end)
test('unexpected engine path fails without submission and latches fault',function()
    local e,l,r=fixture('effect'); l:arm(); e.Board.GetPath=function() return list({r.to,r.from}) end
    assert(not l:request(r) and e.effectCalls==0 and l.fault and not l:arm())
end)
test('effect exception is not retried through native Move',function()
    local e,l,r=fixture('effect'); l:arm()
    e.Board.AddEffect=function() e.effectCalls=e.effectCalls+1; error('uncertain') end
    assert(not l:request(r)); assert(not l:request(r)); assert(e.effectCalls==1 and e.calls==0)
end)
test('spent movement without undo remains an effect failure',function()
    local e,l,r=fixture('effect'); l:arm(); l:request(r)
    e.pawn.position=r.to; e.pawn.spent=true; e.pawn.IsUndoPossible=function() return false end
    e.clock=5100; l:update(); assert(l.fault and e.logs[#e.logs].kind=='move_failed')
end)
test('wrong undo origin remains an effect failure',function()
    local e,l,r=fixture('effect'); l:arm(); l:request(r)
    e.pawn.position=r.to; e.pawn.spent=true; e.pawn.GetUndoLoc=function() return r.to end
    e.clock=5100; l:update(); assert(l.fault)
end)
test('effect postconditions explicitly leave persistence unverified',function()
    local e,l,r=fixture('effect'); l:arm(); l:request(r); e.pawn.position=r.to; e.pawn.spent=true
    for i=1,3 do e.clock=i*100; l:update() end
    local log=e.logs[#e.logs]; assert(log.kind=='move_postconditions_observed')
    assert(log.payload.path=='effect' and log.payload.persistenceVerified==false)
end)
test('input diagnostic blocks movement arming and requests',function()
    local e,l,r=fixture(); l.gateBlocked=true; assert(not l:arm())
    l.gateBlocked=false; assert(l:arm()); l.gateBlocked=true
    assert(not l:request(r) and e.calls==0)
end)
test('UI path permits clear forest but still rejects hazards',function()
    local e,l,r=fixture('ui');e.Board.GetTerrain=function()return 6 end
    assert(l:arm() and l:validate(r));e.Board.IsFire=function()return true end
    assert(not l:validate(r) and e.calls==0 and e.effectCalls==0)
end)
test('UI path requires hooks and undo then locks further submissions',function()
    local e,l,r=fixture('ui');local starts,stops=0,0
    l.bridge={start=function(_,c,validate)starts=starts+1;assert(validate())end,
        update=function()end,stop=function()stops=stops+1 end}
    l:arm();assert(l:request(r));e.pawn.position=r.to;e.pawn.spent=true
    for i=1,3 do e.clock=i*100;l:update()end
    assert(l.pending)
    l:skillEvent('onSkillStart',e.pawn,'Move');l:skillEvent('onSkillEnd',e.pawn,'Move')
    for i=4,6 do e.clock=i*100;l:update()end
    assert(not l.pending and starts==1 and stops==1 and e.calls==0 and e.effectCalls==0)
    e.pawn.position=r.from;e.pawn.spent=false
    assert(not l:request(r) and starts==1)
end)
test('UI bridge failure faults without a fallback relocation',function()
    local e,l,r=fixture('ui');local stops=0
    l.bridge={start=function()error('uncertain queue')end,stop=function()stops=stops+1 end}
    l:arm();assert(not l:request(r));assert(l.fault and stops==1 and e.calls==0 and e.effectCalls==0)
end)
print('Movement contract tests: '..passed..' passed.')
