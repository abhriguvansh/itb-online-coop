-- One known scenario, one call per process. No flag repairs or automatic retries.
local attack = {}
local function need(value, reason) assert(value, reason) end
local function at(p, x, y) return p.x == x and p.y == y end
local function point(p) return { x = p.x, y = p.y } end
function attack.new(env, lab, gate, emit, capture, json)
    local self = { armed = false, used = false, fault = false, status = 'Attack lab off' }
    local function context()
        need(lab:profileAllowed(), 'wrong-profile')
        need(env.modApi:getGameVersion() == '1.2.93', 'wrong-version')
        need(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not lab.blocked, 'not-tactical')
        need(not gate.active and not lab.armed and not lab.pending, 'other-lab-active')
        local m = env.GetCurrentMission()
        need(m and m.ID == 'Mission_Artillery', 'wrong-mission')
        need(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(), 'deployment')
        need(env.Game:GetTeamTurn() == env.TEAM_PLAYER and env.Game:GetTurnCount() == 2, 'wrong-phase')
        need(env.Board:IsTipImage() == false and env.memedit and env.memedit:get(), 'unsupported-board')
    end
    local function safeTile(p)
        need(env.Board:IsValid(p), 'invalid-tile')
        local t = env.Board:GetTerrain(p)
        need(t == env.TERRAIN_ROAD or t == env.TERRAIN_FOREST, 'unsupported-terrain')
        need(env.Board:GetItem(p) == '', 'tile-item')
        for _, method in ipairs({'IsFire','IsAcid','IsSmoke','IsFrozen','IsSpawning','IsPod',
                'IsCracked','IsEnvironmentDanger','IsDangerous','IsDangerousItem'}) do
            need(env.Board[method](env.Board,p) == false, 'unsafe-tile:' .. method)
        end
    end
    local function state(p)
        return { position = point(p:GetSpace()), health = p:GetHealth(), active = p:IsActive(),
            movementSpent = p:IsMovementSpent(), undoPossible = p:IsUndoPossible() }
    end
    local function validate()
        need(not self.used and not self.fault and not self.pending, 'one-call-lockout')
        context()
        local observed, idle = capture()
        need(idle == true, 'not-idle')
        local actor, target = env.Board:GetPawn(0), env.Board:GetPawn(101)
        need(actor and actor:GetType() == 'PunchMech' and at(actor:GetSpace(),3,3), 'wrong-actor')
        need(actor:GetTeam() == env.TEAM_PLAYER and actor:IsPowered() and actor:IsActive(), 'inactive-actor')
        need(actor:GetHealth() == 3 and not actor:IsBoosted(), 'unsupported-actor-state')
        need(actor:GetPoweredWeapons()[1] == 'Prime_Punchmech', 'wrong-powered-weapon')
        need(target and target:GetType() == 'Hornet1' and at(target:GetSpace(),2,3)
            and target:GetTeam() ~= env.TEAM_PLAYER and target:GetHealth() == 3, 'wrong-target')
        for _, p in ipairs({actor,target}) do
            for _, method in ipairs({'IsDead','IsFrozen','IsAcid','IsFire','IsShield','IsArmor'}) do
                need(p[method](p) == false, 'unsupported-pawn-status:' .. method)
            end
        end
        need(not target:IsGuarding(), 'unpushable-target')
        local from, to, pushed = env.Point(3,3), env.Point(2,3), env.Point(1,3)
        safeTile(from); safeTile(to); safeTile(pushed)
        need(not env.Board:IsPawnSpace(pushed), 'push-destination-occupied')
        local skill = env.Prime_Punchmech
        need(skill.Damage == 2 and not skill.Dash and not skill.Flip and not skill.Shield
            and not skill.Projectile and not skill.PushBack and (not skill.Limited or skill.Limited == 0), 'unsupported-skill')
        local targets = skill:GetTargetArea(from)
        need(targets:size() <= 64, 'target-list-size')
        local found = false
        for i=1,targets:size() do if at(targets:index(i),2,3) then found = true end end
        need(found, 'illegal-target')
        return { actor = state(actor), target = state(target), observation = observed }
    end
    function self:arm()
        if self.pending then
            emit('attack_rejected', { reason = 'attack-in-progress' })
            return false -- Preserve the reservation until outcome or lifecycle reset.
        end
        local ok, value = pcall(validate)
        self.armed, lab.attackBlocked = ok, ok
        self.status = ok and 'Ready: punch Hornet (2,3)' or tostring(value)
        emit(ok and 'attack_lab_armed' or 'attack_rejected', { reason = self.status })
        return ok
    end
    function self:disarm()
        if self.pending then
            emit('attack_rejected', { reason = 'attack-in-progress' })
            return false
        end
        self:reset('manual-disarm')
        return true
    end
    function self:reset(reason)
        if self.pending then self.fault = true; emit('attack_failed', { reason = 'context:' .. reason }) end
        self.pending, self.armed, lab.attackBlocked = nil, false, false
        self.status = self.used and 'Attack used: restart required' or 'Attack lab off'
    end
    function self:request()
        if not self.armed then emit('attack_rejected', { reason = 'not-armed' }); return false end
        local ok, before = pcall(validate)
        if not ok then emit('attack_rejected', { reason = tostring(before) }); return false end
        self.used = true -- Set before crossing the native boundary, even on exception.
        self.pending = { before = before, since = env.modApi:elapsedTime(), samples = 0,
            nextSample = 0, startObserved = false, endObserved = false }
        emit('attack_requested', { actorId = 0, targetId = 101, weaponIndex = 1,
            target = {x=2,y=3}, before = before })
        local called, result = pcall(function() return env.Board:GetPawn(0):FireWeapon(env.Point(2,3),1) end)
        emit('attack_engine_return', { callSucceeded = called, returnedTrue = result == true,
            returnType = type(result), detail = not called and tostring(result) or nil })
        -- The installed engine executed an attack without returning true. Never
        -- discard observation or retry solely because the return is unexpected.
        self.pending.callSucceeded, self.pending.returnType = called, type(result)
        self.pending.returnedTrue = result == true
        if not called then self.fault = true end
        self.status = 'Checking attack outcome'
        return called -- Submission only; completion is measured independently.
    end
    function self:skillEvent(kind, pawn, weapon)
        if self.pending and pawn and pawn:GetId() == 0 and weapon == 'Prime_Punchmech' then
            if kind == 'onSkillStart' then self.pending.startObserved = true end
            if kind == 'onSkillEnd' then self.pending.endObserved = true end
            emit('attack_execution_hook', { stage = kind, actor = state(pawn) })
        end
    end
    function self:update()
        local p = self.pending
        if not p then return end
        local t = env.modApi:elapsedTime()
        if t < p.nextSample then return end
        p.nextSample = t + 100
        local ok, after = pcall(function()
            context()
            local observed, idle = capture()
            return { actor = state(env.Board:GetPawn(0)), target = state(env.Board:GetPawn(101)),
                observation = observed, idle = idle }
        end)
        local match = ok and after.idle and at(after.actor.position,3,3) and after.actor.health == 3
            and after.actor.active == false and after.actor.undoPossible == false
            and at(after.target.position,1,3) and after.target.health == 1
            and after.observation.gridPower == p.before.observation.gridPower
        local fingerprint = ok and json.encode(after) or nil
        if match and p.startObserved and p.endObserved then
            p.samples = fingerprint == p.last and p.samples + 1 or 1
        else p.samples = 0 end
        p.last = fingerprint
        if p.samples >= 3 then
            emit('attack_postconditions_observed', { after = after, startObserved = p.startObserved,
                endObserved = p.endObserved, callSucceeded = p.callSucceeded,
                returnType = p.returnType, returnedTrue = p.returnedTrue,
                proofOfQuiescence = false, persistenceVerified = false })
            self.pending = nil; self:reset('observed'); self.status = 'Attack outcome observed; lab locked'
        elseif t - p.since >= 5000 then
            emit('attack_outcome_timeout', { after = ok and after or nil, readError = not ok and tostring(after) or nil,
                startObserved = p.startObserved, endObserved = p.endObserved })
            self.fault = true; self:reset('outcome-timeout')
        end
    end
    return self
end
return attack
