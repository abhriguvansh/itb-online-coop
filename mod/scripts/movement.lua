-- Bounded, manually triggered experiment. This is NOT a multiplayer input gate.
local movement = {}
local types = { [0] = 'PunchMech', [1] = 'TankMech', [2] = 'ArtiMech' }
local function need(condition, reason) if not condition then error(reason, 0) end end
local function xy(p) return { x = p.x, y = p.y } end
local function same(a, b) return a.x == b.x and a.y == b.y end
local function integer(n) return type(n) == 'number' and n == n and n % 1 == 0 end

function movement.new(env, emit, path)
    path = path or 'native'
    assert(path == 'native' or path == 'effect' or path == 'ui', 'Unknown movement experiment')
    local self = { armed = false, blocked = false, pending = nil, fault = false, usedPawns = {}, status = 'Move lab off' }
    self.label = path == 'ui' and 'UI move lab' or (path == 'effect' and 'effect lab' or 'move lab')
    function self:profileAllowed()
        local key = env.modApi:getCurrentProfile()
        return type(key) == 'string' and key ~= '' and type(env.Profile) == 'table'
            and env.Profile.visible_name == 'ITB_Coop_Probe'
    end
    local function context()
        need(self:profileAllowed(), 'wrong-profile')
        need(env.modApi:getGameVersion() == '1.2.93', 'wrong-game-version')
        need(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not self.blocked and not self.gateBlocked and not self.attackBlocked, 'not-tactical-ui')
        local mission = env.GetCurrentMission()
        need(mission and mission.ID == (self.supportedMission or 'Mission_Artillery'), 'unsupported-mission')
        need(env.Board and env.Game and env.Board:IsTipImage() == false, 'no-normal-board')
        need(env.modApi.deployment:isDeploymentPhase() == false
            and env.modApi.deployment:isLandingPhase() == false, 'deployment')
        need(env.Game:GetTeamTurn() == env.TEAM_PLAYER and env.Game:GetTurnCount() >= 1, 'wrong-phase')
        need(env.memedit and env.memedit:get(), 'memedit-unavailable')
        return mission
    end
    local function idle()
        need(env.Board:IsBusy() == false, 'board-busy')
        local ids = env.Board:GetPawns(env.TEAM_ANY)
        need(integer(ids:size()) and ids:size() <= 64, 'unexpected-pawn-count')
        for i = 1, ids:size() do
            need(env.Board:GetPawn(ids:index(i)):IsBusy() == false, 'pawn-busy')
        end
    end
    local function pawnState(pawn)
        local state = { position = xy(pawn:GetSpace()), health = pawn:GetHealth(), active = pawn:IsActive(),
            movementSpent = pawn:IsMovementSpent(), undoPossible = pawn:IsUndoPossible(), fire=pawn:IsFire() }
        if path ~= 'native' then state.undoPosition = xy(pawn:GetUndoLoc()) end
        return state
    end
    function self:lockInput(sessionMode)
        -- A separate diagnostic: no move, attack, reset or allowance write.
        need(self:profileAllowed(), 'wrong-profile')
        need(env.modApi:getGameVersion() == '1.2.93', 'wrong-game-version')
        need(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not self.blocked
            and not self.gateBlocked and not self.attackBlocked, 'not-tactical-ui')
        local mission = env.GetCurrentMission()
        need(mission and mission.ID and mission.ID ~= 'Mission_Test', 'no-normal-mission')
        need(env.Board and env.Game and env.Board:IsTipImage() == false, 'no-normal-board')
        need(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(), 'deployment')
        need(env.Game:GetTeamTurn() == env.TEAM_PLAYER, 'wrong-phase')
        need(not self.pending and self.bridge and not self.bridge.guardWatching and not self.bridge.sessionWatching, 'guard-busy')
        idle()
        if sessionMode then self.bridge:startSession(sessionMode=='timeout') else self.bridge:lock() end
    end
    local function safeTile(p, origin, transit)
        local b = env.Board
        local terrain = b:GetTerrain(p)
        -- UI submission also supports entering a clear forest through normal engine handling.
        need((terrain == env.TERRAIN_ROAD or ((origin or path == 'ui') and terrain == env.TERRAIN_FOREST))
            and b:GetItem(p) == '', 'unsupported-tile')
        for _, method in ipairs({ 'IsFire', 'IsAcid', 'IsSmoke', 'IsFrozen', 'IsSpawning',
                'IsPod', 'IsCracked', 'IsEnvironmentDanger', 'IsDangerous', 'IsDangerousItem' }) do
            local value=b[method](b,p)
            -- Normal-control proof: crossing a burning intermediate tile does not ignite
            -- these ground mechs. Origin/destination and every other hazard stay restricted.
            local fireTransit=path=='ui' and transit and method=='IsFire' and value==true
            -- Normal Tides control: leaving/crossing the next flooded row is legal.
            -- Never end there; retain every other hazard and native route check.
            local tideEscape=path=='ui' and self.supportedMission=='Mission_Tides'
                and (origin or transit) and method=='IsEnvironmentDanger' and value==true
            need(value==false or fireTransit or tideEscape,'unsafe-tile:'..method)
        end
    end
    local function validate(request, allowPending)
        need(self.armed and not self.fault, 'not-armed')
        need(allowPending or not self.pending, 'move-pending')
        local mission = context()
        need(type(request) == 'table' and integer(request.pawnId) and types[request.pawnId], 'invalid-pawn')
        need(path ~= 'ui' or allowPending or not self.usedPawns[request.pawnId], 'ui-one-call-per-pawn-lockout')
        need(request.mission == mission.ID and request.turn == env.Game:GetTurnCount(), 'stale-context')
        for _, p in ipairs({ request.from or {}, request.to or {} }) do
            need(integer(p.x) and integer(p.y), 'invalid-point')
            need(env.Board:IsValid(env.Point(p.x, p.y)) == true, 'out-of-bounds')
        end
        idle()
        local pawn = env.Board:GetPawn(request.pawnId)
        need(pawn and pawn:GetId() == request.pawnId and pawn:GetType() == types[request.pawnId], 'unsupported-pawn')
        need(pawn:GetTeam() == env.TEAM_PLAYER and pawn:IsPowered() == true, 'uncontrolled-pawn')
        need(pawn:IsActive() == true and pawn:IsDead() == false, 'inactive-pawn')
        need(pawn:IsMovementSpent() == false, 'movement-spent')
        for _, method in ipairs({ 'IsFrozen', 'IsGrappled', 'IsFlying', 'IsJumper', 'IsTeleporter',
                'IsFire', 'IsAcid' }) do
            need(pawn[method](pawn) == false, 'unsupported-status:' .. method)
        end
        need(env[pawn:GetType()] and env[pawn:GetType()].MoveSkill == nil, 'custom-move')
        need(pawn:IsAbility('Adjacent_Heal') == false and pawn:IsAbility('Web_Vek') == false, 'post-move-ability')
        local from, to = pawn:GetSpace(), env.Point(request.to.x, request.to.y)
        need(same(from, request.from), 'stale-origin')
        local distance=math.abs(from.x-to.x)+math.abs(from.y-to.y)
        need(path == 'ui' and distance>=1 or distance==1, 'one-tile-only')
        need(env.Board:IsPawnSpace(to) == false, 'occupied-target')
        safeTile(from, true); safeTile(to, false)
        local speed = pawn:GetMoveSpeed()
        need(integer(speed) and speed >= 1 and speed <= 8, 'unsupported-move-speed')
        local reachable = env.Board:GetReachable(from, speed, pawn:GetPathProf())
        need(reachable:size() <= 1024, 'unexpected-target-count')
        local found = false
        for i = 1, reachable:size() do if same(reachable:index(i), to) then found = true end end
        need(found, 'unreachable-target')
        if path == 'ui' then
            local route=env.Board:GetPath(from,to,pawn:GetPathProf())
            local count=route:size()
            need(integer(count) and count>=2 and count<=speed+1,'unsupported-path-length')
            need(same(route:index(1),from) and same(route:index(count),to),'path-endpoints-changed')
            local visited={}
            for i=1,count do
                local point=route:index(i)
                need(integer(point.x) and integer(point.y) and env.Board:IsValid(point)==true,'invalid-path-point')
                local key=point.x..':'..point.y
                need(not visited[key],'path-cycle');visited[key]=true
                safeTile(point,i==1,i>1 and i<count)
                if i>1 then
                    local previous=route:index(i-1)
                    need(math.abs(point.x-previous.x)+math.abs(point.y-previous.y)==1,'nonadjacent-path-step')
                    if env.Board:IsPawnSpace(point) then
                        -- Reachability and the route are engine-derived. Only a living
                        -- friendly may occupy an intermediate tile; never the destination.
                        local ally=env.Board:GetPawn(point)
                        need(i<count and ally and ally:GetId()~=pawn:GetId()
                            and ally:GetTeam()==env.TEAM_PLAYER and ally:IsDead()==false
                            and same(ally:GetSpace(),point),'occupied-path')
                    end
                end
            end
        end
        return pawnState(pawn)
    end
    function self:validate(request)
        local ok, result = pcall(validate, request)
        return ok, result
    end
    function self:arm()
        if self.pending or self.fault then return false end
        local ok, reason = pcall(function() context(); idle() end)
        self.armed = ok
        self.status = ok and 'Move lab armed' or tostring(reason)
        emit(ok and 'move_lab_armed' or 'move_lab_rejected', { reason = self.status })
        return ok
    end
    function self:reset(reason)
        if self.bridge then self.bridge:stop() end
        if self.bridge and self.bridge.unlock then self.bridge:unlock() end
        if self.pending then
            self.fault = true
            emit('move_failed', { reason = 'context-changed:' .. reason })
        end
        self.armed, self.pending = false, nil
        -- A fault needs a fresh game launch, never a menu/context reset.
        self.status = self.fault and 'Move lab fault: restart required' or 'Move lab off'
    end
    function self:preview(id)
        local ok, result = pcall(function()
            local m = context()
            local pawn = env.Board:GetPawn(id)
            need(pawn, 'missing-pawn')
            local from = xy(pawn:GetSpace())
            local lastReason = 'no-safe-neighbor'
            local destinations={}
            if path=='ui' then
                local reachable=env.Board:GetReachable(pawn:GetSpace(),pawn:GetMoveSpeed(),pawn:GetPathProf())
                need(integer(reachable:size()) and reachable:size()<=1024,'unexpected-target-count')
                for i=1,reachable:size() do destinations[#destinations+1]=xy(reachable:index(i)) end
                table.sort(destinations,function(a,b)
                    local da,db=math.abs(a.x-from.x)+math.abs(a.y-from.y),math.abs(b.x-from.x)+math.abs(b.y-from.y)
                    if da~=db then return da>db end
                    if a.y~=b.y then return a.y<b.y end
                    return a.x<b.x
                end)
            else
                for _,delta in ipairs({{0,-1},{-1,0},{1,0},{0,1}}) do
                    destinations[#destinations+1]={x=from.x+delta[1],y=from.y+delta[2]}
                end
            end
            for _, destination in ipairs(destinations) do
                local request = { pawnId = id, from = from,
                    to = destination,
                    mission = m.ID, turn = env.Game:GetTurnCount() }
                local valid, reason = self:validate(request)
                if valid then return request end
                lastReason = tostring(reason)
            end
            error(lastReason, 0)
        end)
        if ok then return result end
        return nil, tostring(result)
    end
    function self:request(request)
        local valid, before = self:validate(request)
        if not valid then
            self.status = tostring(before)
            emit('move_rejected', { reason = self.status, request = request })
            return false
        end
        -- Copy scalar request data; retain no pawn/board userdata across callbacks.
        local command = { pawnId = request.pawnId, from = xy(request.from), to = xy(request.to),
            mission = request.mission, turn = request.turn }
        self.pending = { command = command, before = before, since = env.modApi:elapsedTime(),
            samples = 0, nextSample = 0, startObserved = false, endObserved = false }
        emit('move_requested', { request = command, before = before, path = path, inputGateImplemented = false })
        local ok, result = pcall(function()
            if path == 'ui' then
                self.usedPawns[command.pawnId] = true
                need(self.bridge, 'ui-bridge-unavailable')
                self.bridge:start(command, function() return pcall(validate, command, true) end)
                return nil
            end
            if path == 'effect' then
                local pawn = env.Board:GetPawn(command.pawnId)
                local route = env.Board:GetPath(env.Point(command.from.x, command.from.y),
                    env.Point(command.to.x, command.to.y), pawn:GetPathProf())
                need(route:size() == 2 and same(route:index(1), command.from)
                    and same(route:index(2), command.to), 'unexpected-effect-path')
                -- Standard ground Move uses this effect primitive. No allowance/undo setters,
                -- global Pawn replacement, injected execution hooks, or forced save.
                local effect = env.SkillEffect()
                effect:AddMove(route, env.FULL_DELAY)
                env.Board:AddEffect(effect) -- documented void return; observe state separately
                return nil
            end
            return env.Board:GetPawn(command.pawnId):Move(env.Point(command.to.x, command.to.y))
        end)
        emit('move_engine_return', { callSucceeded = ok, returnedTrue = result == true,
            path = path, returnType = type(result),
            detail = not ok and tostring(result) or nil })
        if not ok or (path == 'native' and result ~= true) then
            if self.bridge then self.bridge:stop() end
            self.fault, self.armed, self.pending = true, false, nil
            self.status = 'Move failed: restart required'
            emit('move_failed', { reason = 'engine-call-failed-or-uncertain' })
            return false
        end
        self.status = 'Checking move outcome'
        return true
    end
    function self:skillEvent(kind, pawn, weapon)
        local pending = self.pending
        if pending and weapon == 'Move' and pawn and pawn:GetId() == pending.command.pawnId then
            if kind == 'onSkillStart' then pending.startObserved = true end
            if kind == 'onSkillEnd' then pending.endObserved = true end
        end
    end
    function self:update()
        local p = self.pending
        if not p then return end
        local now = env.modApi:elapsedTime()
        if now < p.nextSample then return end
        p.nextSample = now + 100
        if self.bridge then
            local bridgeOk,reason=pcall(function() self.bridge:update() end)
            if not bridgeOk then
                self.bridge:stop()
                self.pending,self.armed,self.fault=nil,false,true
                self.status='Move failed: restart required'
                emit('move_failed',{reason='bridge-validation-failed',detail=tostring(reason),request=p.command})
                return -- Never continue a partially submitted command after a guard failed.
            end
        end
        local ok, after = pcall(function()
            local mission = context()
            need(mission.ID == p.command.mission and env.Game:GetTurnCount() == p.command.turn, 'context-changed')
            idle()
            return pawnState(env.Board:GetPawn(p.command.pawnId))
        end)
        local matches = ok and same(after.position, p.command.to) and after.movementSpent == true
            and after.active == p.before.active and after.health == p.before.health and after.fire==p.before.fire
        if path ~= 'native' then
            matches = matches and after.undoPossible == true and same(after.undoPosition, p.command.from)
        end
        if path == 'ui' then matches = matches and p.startObserved and p.endObserved end
        p.samples = matches and (p.samples + 1) or 0
        if p.samples >= 3 then
            emit('move_postconditions_observed', { request = p.command, before = p.before, after = after,
                startObserved = p.startObserved, endObserved = p.endObserved,
                path = path, persistenceVerified = false,
                proofOfQuiescence = false, coverage = path=='ui' and 'validated-ground-path-lab-only' or 'one-tile-manual-lab-only' })
            if self.bridge then self.bridge:stop(true) end
            self.pending = nil
            self.status = 'Move outcome observed'
        elseif now - p.since > 5000 then
            emit('move_failed', { reason = 'postconditions-not-observed', request = p.command,
                path = path, startObserved = p.startObserved, endObserved = p.endObserved,
                after = ok and after or nil, detail = not ok and tostring(after) or nil })
            if self.bridge then self.bridge:stop() end
            self.pending, self.armed, self.fault = nil, false, true
            self.status = 'Move failed: restart required'
        end
    end
    return self
end
return movement
