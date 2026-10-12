-- Bounded, manually triggered experiment. This is NOT a multiplayer input gate.
local movement = {}
local types = { [0] = 'PunchMech', [1] = 'TankMech', [2] = 'ArtiMech' }
local function need(condition, reason) if not condition then error(reason, 0) end end
local function xy(p) return { x = p.x, y = p.y } end
local function same(a, b) return a.x == b.x and a.y == b.y end
local function integer(n) return type(n) == 'number' and n == n and n % 1 == 0 end

function movement.new(env, emit)
    local self = { armed = false, blocked = false, pending = nil, fault = false, status = 'Move lab off' }
    function self:profileAllowed()
        local key = env.modApi:getCurrentProfile()
        return type(key) == 'string' and key ~= '' and type(env.Profile) == 'table'
            and env.Profile.visible_name == 'ITB_Coop_Probe'
    end
    local function context()
        need(self:profileAllowed(), 'wrong-profile')
        need(env.modApi:getGameVersion() == '1.2.93', 'wrong-game-version')
        need(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not self.blocked, 'not-tactical-ui')
        local mission = env.GetCurrentMission()
        need(mission and mission.ID == 'Mission_Artillery', 'unsupported-mission')
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
        return { position = xy(pawn:GetSpace()), health = pawn:GetHealth(), active = pawn:IsActive(),
            movementSpent = pawn:IsMovementSpent(), undoPossible = pawn:IsUndoPossible() }
    end
    local function safeTile(p, origin)
        local b = env.Board
        local terrain = b:GetTerrain(p)
        -- Leaving an unburning forest is supported; destinations remain plain ground.
        need((terrain == env.TERRAIN_ROAD or (origin and terrain == env.TERRAIN_FOREST))
            and b:GetItem(p) == '', 'unsupported-tile')
        for _, method in ipairs({ 'IsFire', 'IsAcid', 'IsSmoke', 'IsFrozen', 'IsSpawning',
                'IsPod', 'IsCracked', 'IsEnvironmentDanger', 'IsDangerous', 'IsDangerousItem' }) do
            need(b[method](b, p) == false, 'unsafe-tile:' .. method)
        end
    end
    local function validate(request)
        need(self.armed and not self.fault, 'not-armed')
        need(not self.pending, 'move-pending')
        local mission = context()
        need(type(request) == 'table' and integer(request.pawnId) and types[request.pawnId], 'invalid-pawn')
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
        need(math.abs(from.x - to.x) + math.abs(from.y - to.y) == 1, 'one-tile-only')
        need(env.Board:IsPawnSpace(to) == false, 'occupied-target')
        safeTile(from, true); safeTile(to, false)
        local speed = pawn:GetMoveSpeed()
        need(integer(speed) and speed >= 1 and speed <= 8, 'unsupported-move-speed')
        local reachable = env.Board:GetReachable(from, speed, pawn:GetPathProf())
        need(reachable:size() <= 1024, 'unexpected-target-count')
        local found = false
        for i = 1, reachable:size() do if same(reachable:index(i), to) then found = true end end
        need(found, 'unreachable-target')
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
            for _, delta in ipairs({ {0,-1}, {-1,0}, {1,0}, {0,1} }) do
                local request = { pawnId = id, from = from,
                    to = { x = from.x + delta[1], y = from.y + delta[2] },
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
        emit('move_requested', { request = command, before = before, inputGateImplemented = false })
        local ok, result = pcall(function()
            return env.Board:GetPawn(command.pawnId):Move(env.Point(command.to.x, command.to.y))
        end)
        emit('move_engine_return', { callSucceeded = ok, returnedTrue = result == true,
            detail = not ok and tostring(result) or nil })
        if not ok or result ~= true then
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
        local ok, after = pcall(function()
            local mission = context()
            need(mission.ID == p.command.mission and env.Game:GetTurnCount() == p.command.turn, 'context-changed')
            idle()
            return pawnState(env.Board:GetPawn(p.command.pawnId))
        end)
        local matches = ok and same(after.position, p.command.to) and after.movementSpent == true
            and after.active == p.before.active and after.health == p.before.health
        p.samples = matches and (p.samples + 1) or 0
        if p.samples >= 3 then
            emit('move_postconditions_observed', { request = p.command, before = p.before, after = after,
                startObserved = p.startObserved, endObserved = p.endObserved,
                proofOfQuiescence = false, coverage = 'one-tile-manual-lab-only' })
            self.pending = nil
            self.status = 'Move outcome observed'
        elseif now - p.since > 5000 then
            emit('move_failed', { reason = 'postconditions-not-observed', request = p.command,
                after = ok and after or nil, detail = not ok and tostring(after) or nil })
            self.pending, self.armed, self.fault = nil, false, true
            self.status = 'Move failed: restart required'
        end
    end
    return self
end
return movement
