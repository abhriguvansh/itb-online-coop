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
local fixture = dofile('tests/fixtures/movement.lua')
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
local function longRoute()
    local e,l,r=fixture('ui');r.to=e.Point(1,0)
    local points={r.from,e.Point(1,2),e.Point(1,1),r.to}
    e.Board.GetReachable=function()return list({r.to})end
    e.Board.GetPath=function()return list(points)end
    assert(l:arm());return e,l,r,points
end
test('UI path accepts a reachable three-step clear ground path',function()
    local e,l,r=longRoute();assert(l:validate(r));assert(e.calls==0 and e.effectCalls==0)
end)
local function friendlyRoute()
    local e,l,r,points=longRoute()
    local ally={GetId=function()return 100 end,GetTeam=function()return e.TEAM_PLAYER end,
        IsDead=function()return false end,GetSpace=function()return points[2] end}
    e.Board.IsPawnSpace=function(_,p)return p.x==points[2].x and p.y==points[2].y end
    e.Board.GetPawn=function(_,id)return type(id)=='table' and ally or e.pawn end
    return e,l,r,points,ally
end
test('UI path permits engine-reachable friendly intermediate transit without dispatch',function()
    local e,l,r=friendlyRoute();assert(l:validate(r));assert(e.calls==0 and e.effectCalls==0 and not l.pending)
end)
for _,problem in ipairs({'enemy','dead','wrong-position','same-actor','missing','destination','unreachable','hazard'}) do
    test('friendly transit retains rejection for '..problem,function()
        local e,l,r,points,ally=friendlyRoute()
        if problem=='enemy' then ally.GetTeam=function()return 6 end
        elseif problem=='dead' then ally.IsDead=function()return true end
        elseif problem=='wrong-position' then ally.GetSpace=function()return r.to end
        elseif problem=='same-actor' then ally.GetId=function()return e.pawn:GetId()end
        elseif problem=='missing' then e.Board.GetPawn=function(_,id)if type(id)~='table' then return e.pawn end end
        elseif problem=='destination' then e.Board.IsPawnSpace=function()return true end
        elseif problem=='unreachable' then e.Board.GetReachable=function()return list({})end
        else e.Board.IsFire=function(_,p)return p.y==2 end end
        assert(not l:request(r) and e.calls==0 and e.effectCalls==0 and not l.usedPawns[2])
    end)
end
test('friendly route is rechecked if its occupant changes team before submission',function()
    local e,l,r,points,ally=friendlyRoute();assert(l:validate(r))
    ally.GetTeam=function()return 6 end
    assert(not l:request(r) and not l.pending and not l.usedPawns[2] and e.calls==0)
end)
for _,problem in ipairs({'hazard','occupancy','terrain','jump','cycle','end','length'}) do
    test('UI path rejects unsafe or malformed intermediate path: '..problem,function()
        local e,l,r,points=longRoute()
        if problem=='hazard' then e.Board.IsFire=function(_,p)return p.y==2 end
        elseif problem=='occupancy' then e.Board.IsPawnSpace=function(_,p)return p.y==2 end
        elseif problem=='terrain' then e.Board.GetTerrain=function(_,p)return p.y==2 and 3 or 0 end
        elseif problem=='jump' then points[2]=e.Point(2,2)
        elseif problem=='cycle' then points[3]=points[1]
        elseif problem=='end' then points[4]=e.Point(2,0)
        else points[5]=r.to end
        assert(not l:request(r) and e.calls==0 and e.effectCalls==0 and not l.usedPawns[2])
    end)
end
test('UI bridge validation failure stops immediately without a retry',function()
    local e,l,r=fixture('ui');local updates,stops=0,0
    l.bridge={start=function()end,update=function()updates=updates+1;error('preview-mismatch')end,
        stop=function()stops=stops+1 end}
    l:arm();assert(l:request(r));l:update();assert(l.fault and not l.pending and stops==1)
    e.clock=1000;l:update();assert(updates==1 and not l:arm())
end)
test('one successful pawn cannot repeat but another pawn can submit',function()
    local e,l,r=fixture('ui');local starts=0
    l.bridge={start=function()starts=starts+1 end,update=function()end,stop=function()end}
    l:arm();assert(l:request(r));e.pawn.position=r.to;e.pawn.spent=true
    l:skillEvent('onSkillStart',e.pawn,'Move');l:skillEvent('onSkillEnd',e.pawn,'Move')
    for i=1,3 do e.clock=i*100;l:update()end
    e.pawn.position=r.from;e.pawn.spent=false;assert(not l:request(r))
    e.pawn.GetId=function()return 1 end;e.pawn.GetType=function()return 'TankMech'end;e.TankMech={};r.pawnId=1
    assert(l:request(r) and starts==2 and l.usedPawns[1] and l.usedPawns[2])
end)
test('standalone guard needs no available move and submits no action',function()
    local e,l=fixture('ui');local locked=0
    l.bridge={lock=function()locked=locked+1 end};e.pawn.spent=true;e.mission.ID='Mission_Survive';e.turn=0
    l:lockInput();assert(locked==1 and e.calls==0 and e.effectCalls==0 and not l.armed and not l.pending)
end)
for _,case in ipairs({
    {'normal profile',function(e) e.Profile.visible_name='Aman' end},
    {'wrong version',function(e)e.modApi.getGameVersion=function()return 'other'end end},
    {'modal',function(e,l)l.blocked=true end},
    {'console',function(e)e.sdlext.isConsoleOpen=function()return true end end},
    {'non tactical',function(e)e.sdlext.isGame=function()return false end end},
    {'test mission',function(e)e.mission.ID='Mission_Test'end},
    {'deployment',function(e)e.modApi.deployment.isDeploymentPhase=function()return true end end},
    {'landing',function(e)e.modApi.deployment.isLandingPhase=function()return true end end},
    {'enemy phase',function(e)e.phase=6 end},
    {'pending move',function(e,l)l.pending={}end},
    {'active guard',function(e,l)l.bridge.guardWatching=true end},
    {'busy board',function(e)e.Board.IsBusy=function()return true end end},
    {'busy pawn',function(e)e.pawn.IsBusy=function()return true end end},
    {'attack lab',function(e,l)l.attackBlocked=true end},
    {'SDL gate',function(e,l)l.gateBlocked=true end},
}) do
    test('standalone guard rejects '..case[1],function()
        local e,l=fixture('ui');local locked=false;l.bridge={lock=function()locked=true end}
        case[2](e,l);assert(not pcall(function()l:lockInput()end) and not locked and e.calls==0)
    end)
end
print('Movement contract tests: '..passed..' passed.')
