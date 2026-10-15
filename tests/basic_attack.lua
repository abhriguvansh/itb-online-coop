local module=dofile('mod/scripts/basic_attack.lua')
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
        p.IsAbility=function()return false end;p.IsPowered=function() return true end
        p.GetPoweredWeapons=function() return {'Prime_Punchmech'} end
        for _,m in ipairs({'IsMovementSpent','IsUndoPossible','IsBoosted','IsDead','IsFrozen','IsAcid','IsFire','IsShield','IsArmor','IsGuarding'}) do p[m]=function() return false end end
        return p
    end
    e.actor=pawn(0,'PunchMech',3,3,1);e.target=pawn(101,'Hornet1',2,3,6)
    e.actor.FireWeapon=function(_,p,index) e.calls=e.calls+1;assert(p.x==2 and p.y==3 and index==1);return true end
    e.modApi={elapsedTime=function() return e.clock end,getGameVersion=function() return '1.2.93' end,
        deployment={isDeploymentPhase=function() return false end,isLandingPhase=function() return false end}}
    e.sdlext={isGame=function() return true end,isConsoleOpen=function() return false end}
    e.mission={ID='Mission_Artillery'};e.GetCurrentMission=function() return e.mission end
    e.Game={GetTeamTurn=function() return 1 end,GetTurnCount=function() return 2 end}
    e.memedit={get=function() return true end}
    e.Board={IsTipImage=function() return false end,GetPawn=function(_,id) return id==0 and e.actor or e.target end,
        IsValid=function() return true end,GetTerrain=function() return 0 end,GetItem=function() return '' end,IsPawnSpace=function() return false end}
    for _,m in ipairs({'IsFire','IsAcid','IsSmoke','IsFrozen','IsSpawning','IsPod','IsCracked','IsEnvironmentDanger','IsDangerous','IsDangerousItem'}) do e.Board[m]=function() return false end end
    e.Board.GetBusyState=function()return 0 end
    e.Prime_Punchmech={Damage=2,GetTargetArea=function() return list({{x=2,y=3}}) end}
    local a=module.new(e,l,g,function(k,d)e.logs[#e.logs+1]={kind=k,payload=d}end,function()return {gridPower=4,unavailable={}},e.idle end,json)
    a.bridge={start=function(_,c,v) assert(v());return e.actor:FireWeapon(c.to,1) end,update=function()end,stop=function()end}
    return e,l,g,a
end

local function command()return {pawnId=0,from={x=3,y=3},to={x=2,y=3},turn=2}end
local function finish(e,a)
 a:skillEvent('onSkillStart',e.actor,'Prime_Punchmech');e.actor.active=false
 a:skillEvent('onSkillEnd',e.actor,'Prime_Punchmech');a:draw();a:missionUpdate();a:update()
end
test('requires execution end plus later draw and mission update',function()
 local e,l,g,a=fixture();local c=command();assert(a:arm(c));assert(a:request(c));a:update();assert(a.pending)
 a:skillEvent('onSkillStart',e.actor,'Prime_Punchmech');e.actor.active=false;a:skillEvent('onSkillEnd',e.actor,'Prime_Punchmech')
 a:update();assert(a.pending);a:draw();a:update();assert(a.pending);a:missionUpdate();a:update();assert(not a.pending and not a.fault)
end)
test('rejects inactive upgraded smoked unsupported-pilot and illegal target',function()
 for _,bad in ipairs({'inactive','weapon','smoke','pilot','target'}) do
  local e,l,g,a=fixture();local c=command()
  if bad=='inactive' then e.actor.active=false elseif bad=='weapon' then e.actor.GetPoweredWeapons=function()return {'Prime_Punchmech_A'}end
  elseif bad=='smoke' then e.Board.IsSmoke=function()return true end elseif bad=='pilot' then e.actor.IsAbility=function()return true end else c.to.x=7 end
  assert(not a:arm(c) and e.calls==0)
 end
end)
test('unconsumed allowance or missing hooks stops without retry',function()
 local e,l,g,a=fixture();local c=command();assert(a:arm(c));a:request(c);e.clock=15001;a:update();assert(a.fault and e.calls==1 and not a:arm(c))
end)
test('next attack uses engine allowance rather than launch quota',function()
 local e,l,g,a=fixture();local c=command();assert(a:arm(c));a:request(c);finish(e,a);assert(not a:arm(c))
 e.actor.active=true;assert(a:arm(c));a:request(c);finish(e,a);assert(e.calls==2 and not a.fault)
end)
test('queued callback delays completion',function()
 local e,l,g,a=fixture();local c=command();a:arm(c);a:request(c);e.modApi.runLaterQueue={true};finish(e,a);assert(a.pending)
 e.modApi.runLaterQueue={};a:update();assert(not a.pending)
end)
test('uncertain native exception latches before any retry',function()
 local e,l,g,a=fixture();local c=command();e.actor.FireWeapon=function()e.calls=e.calls+1;error('unknown')end
 a:arm(c);assert(not a:request(c));assert(a.fault and a.pending and not a:arm(c) and e.calls==1)
end)
test('all three base weapons use exact powered first slot and target area',function()
 for id,spec in pairs({[0]={'PunchMech','Prime_Punchmech'},[1]={'TankMech','Brute_Tankmech'},[2]={'ArtiMech','Ranged_Artillerymech'}})do
  local e,l,g,a=fixture();local c=command();c.pawnId=id
  e.actor.GetId=function()return id end;e.actor.GetType=function()return spec[1]end
  e.actor.GetPoweredWeapons=function()return {spec[2]}end;e[spec[2]]=e.Prime_Punchmech
  e.Board.GetPawn=function(_,n)assert(n==id);return e.actor end
  assert(a:arm(c));assert(a:request(c));a:skillEvent('onSkillStart',e.actor,spec[2]);e.actor.active=false
  a:skillEvent('onSkillEnd',e.actor,spec[2]);a:draw();a:missionUpdate();a:update();assert(not a.pending and e.calls==1)
 end
end)
test('late allowance consumption waits without replaying native attack',function()
 local e,l,g,a=fixture();local c=command();a:arm(c);a:request(c)
 a:skillEvent('onSkillStart',e.actor,'Prime_Punchmech');a:skillEvent('onSkillEnd',e.actor,'Prime_Punchmech')
 a:draw();a:missionUpdate();a:update();assert(a.pending and not a.fault and e.calls==1)
 e.actor.active=false;a:update();assert(not a.pending and not a.fault and e.calls==1)
end)
print('Basic weapon contracts: '..passed..' passed (engine doubles only).')
