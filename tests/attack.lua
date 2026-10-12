local module=dofile('mod/scripts/attack.lua')
local json=dofile('mod/scripts/json.lua')
local passed=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..': '..tostring(err)); passed=passed+1 end
local function list(v) return {size=function() return #v end,index=function(_,i) return v[i] end} end
local function fixture()
    local e={TEAM_PLAYER=1,TERRAIN_ROAD=0,TERRAIN_FOREST=6,clock=0,calls=0,logs={},idle=true}
    local l={profileAllowed=function() return true end}; local g={active=false}
    e.Point=function(x,y) return {x=x,y=y} end
    local function pawn(id,kind,x,y,team)
        local p={id=id,kind=kind,pos={x=x,y=y},hp=3,active=true}
        p.GetId=function() return id end; p.GetType=function() return p.kind end
        p.GetSpace=function() return p.pos end; p.GetHealth=function() return p.hp end
        p.GetTeam=function() return team end; p.IsActive=function() return p.active end
        p.IsPowered=function() return true end
        p.GetPoweredWeapons=function() return {'Prime_Punchmech'} end
        for _,m in ipairs({'IsMovementSpent','IsUndoPossible','IsBoosted','IsDead','IsFrozen','IsAcid','IsFire','IsShield','IsArmor','IsGuarding'}) do p[m]=function() return false end end
        return p
    end
    e.actor=pawn(0,'PunchMech',3,3,1);e.target=pawn(101,'Hornet1',2,3,6)
    e.actor.FireWeapon=function(_,p,index) e.calls=e.calls+1;assert(p.x==2 and p.y==3 and index==1);return true end
    e.modApi={elapsedTime=function() return e.clock end,getGameVersion=function() return '1.2.93' end,
        deployment={isDeploymentPhase=function() return false end,isLandingPhase=function() return false end}}
    e.sdlext={isGame=function() return true end,isConsoleOpen=function() return false end}
    e.GetCurrentMission=function() return {ID='Mission_Artillery'} end
    e.Game={GetTeamTurn=function() return 1 end,GetTurnCount=function() return 2 end}
    e.memedit={get=function() return true end}
    e.Board={IsTipImage=function() return false end,GetPawn=function(_,id) return id==0 and e.actor or e.target end,
        IsValid=function() return true end,GetTerrain=function() return 0 end,GetItem=function() return '' end,IsPawnSpace=function() return false end}
    for _,m in ipairs({'IsFire','IsAcid','IsSmoke','IsFrozen','IsSpawning','IsPod','IsCracked','IsEnvironmentDanger','IsDangerous','IsDangerousItem'}) do e.Board[m]=function() return false end end
    e.Prime_Punchmech={Damage=2,GetTargetArea=function() return list({{x=2,y=3}}) end}
    local a=module.new(e,l,g,function(k,d)e.logs[#e.logs+1]={kind=k,payload=d}end,function()return {gridPower=4},e.idle end,json)
    return e,l,g,a
end
test('one validated request crosses native boundary once',function()
    local e,l,g,a=fixture();assert(not a:request());assert(a:arm());assert(l.attackBlocked);assert(a:request());assert(e.calls==1)
    assert(not a:request());a:reset('test');assert(not a:arm() and e.calls==1)
end)
test('damage push and consumption with execution hooks need three spaced samples',function()
    local e,l,g,a=fixture();a:arm();a:request();a:skillEvent('onSkillStart',e.actor,'Prime_Punchmech')
    e.actor.active=false;e.target.pos={x=1,y=3};e.target.hp=1
    a:skillEvent('onSkillEnd',e.actor,'Prime_Punchmech')
    for i=1,2 do e.clock=i*100;a:update();assert(a.pending) end
    e.clock=300;a:update();assert(not a.pending and not a.fault and not l.attackBlocked)
    assert(e.logs[#e.logs].kind=='attack_postconditions_observed')
end)
test('missing consumption faults instead of patching state',function()
    local e,l,g,a=fixture();a:arm();a:request();e.target.pos={x=1,y=3};e.target.hp=1;e.clock=5001;a:update()
    assert(a.fault and e.actor.active and e.calls==1 and not a:arm())
end)
test('matching visible result without hooks is insufficient',function()
    local e,l,g,a=fixture();a:arm();a:request();e.actor.active=false;e.target.pos={x=1,y=3};e.target.hp=1
    e.clock=5001;a:update();assert(a.fault)
end)
test('uncertain exception never retries',function()
    local e,l,g,a=fixture();e.actor.FireWeapon=function()e.calls=e.calls+1;error('uncertain')end
    a:arm();assert(not a:request());assert(a.fault and not a:arm() and e.calls==1)
end)
test('native false locks the lab',function()
    local e,l,g,a=fixture();e.actor.FireWeapon=function()e.calls=e.calls+1;return false end
    a:arm();assert(not a:request());assert(a.fault and a.used and not a:arm())
end)
test('context reset preserves one-call lockout',function()
    local e,l,g,a=fixture();a:arm();a:request();a:reset('mission-change');assert(a.fault and not a:arm())
end)
for _,case in ipairs({
    {'profile',function(e,l)l.profileAllowed=function()return false end end},
    {'gate overlap',function(e,l,g)g.active=true end},
    {'movement overlap',function(e,l)l.armed=true end},
    {'busy',function(e)e.idle=false end},
    {'spent actor',function(e)e.actor.active=false end},
    {'upgraded weapon',function(e)e.actor.GetPoweredWeapons=function()return {'Prime_Punchmech_A'}end end},
    {'shield target',function(e)e.target.IsShield=function()return true end end},
    {'blocked push',function(e)e.Board.IsPawnSpace=function()return true end end},
    {'hazard',function(e)e.Board.IsFire=function()return true end end},
    {'wrong phase',function(e)e.Game.GetTeamTurn=function()return 6 end end},
    {'illegal target',function(e)e.Prime_Punchmech.GetTargetArea=function()return list({})end end},
    {'different damage',function(e)e.Prime_Punchmech.Damage=4 end},
    {'stale position',function(e)e.actor.pos={x=4,y=3}end},
    {'limited weapon',function(e)e.Prime_Punchmech.Limited=1 end},
}) do test('reject '..case[1],function()local e,l,g,a=fixture();case[2](e,l,g);assert(not a:arm() and e.calls==0)end) end
test('revalidate after arming',function()
    local e,l,g,a=fixture();assert(a:arm());e.target.hp=2;assert(not a:request() and e.calls==0)
end)
print('Attack contracts: '..passed..' passed.')
