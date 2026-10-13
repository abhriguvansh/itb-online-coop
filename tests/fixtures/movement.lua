local movement = dofile('mod/scripts/movement.lua')
local function list(values) return {size=function() return #values end,index=function(_,i) return values[i] end} end
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
return fixture
