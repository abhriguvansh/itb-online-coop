-- Temporary diagnostic, not multiplayer authorization. No gameplay setters.
local gate = {}
function gate.new(env, lab, emit, capture)
    local self = { active = false, held = {}, status = 'Input lab off', count = 0 }
    local function log(kind, data) pcall(emit, kind, data) end
    local function now()
        local t = env.modApi:elapsedTime()
        assert(type(t) == 'number' and t == t and t >= 0 and t < math.huge, 'invalid clock')
        return t
    end
    local function context()
        assert(lab:profileAllowed(), 'wrong profile')
        assert(env.modApi:getGameVersion() == '1.2.93', 'wrong version')
        assert(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not lab.blocked, 'not tactical UI')
        local mission = env.GetCurrentMission()
        assert(mission and mission.ID == 'Mission_Artillery', 'wrong mission')
        assert(env.Board and not env.Board:IsTipImage(), 'no board')
        assert(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(), 'deployment')
        assert(env.Game:GetTeamTurn() == env.TEAM_PLAYER and env.Game:GetTurnCount() >= 1, 'wrong phase')
        assert(not lab.armed and not lab.pending, 'movement lab must be off')
        return mission
    end
    local function sample()
        local ok, data = pcall(function()
            assert(lab:profileAllowed(), 'outside disposable profile')
            return capture()
        end)
        return ok and data or { unavailable = tostring(data) }
    end
    function self:stop(reason, clearHeld)
        if self.active then
            self.active, lab.gateBlocked = false, false
            self.status = 'Input lab off: ' .. reason
            log('input_gate_end', { reason = reason, blockedEvents = self.count, state = sample(),
                proofOfCompleteGate = false })
        end
        if clearHeld then self.held = {} end
    end
    function self:arm()
        if self.active or next(self.held) then return false end
        local ok, result = pcall(function()
            context()
            assert(env.Board:IsBusy() == false, 'board busy')
            local data, idle = capture()
            assert(idle == true, 'snapshot not idle')
            return { state = data, start = now(), turn = env.Game:GetTurnCount() }
        end)
        if not ok then self.status = tostring(result); log('input_gate_rejected', { reason = self.status }); return false end
        self.started, self.deadline, self.turn = result.start, result.start + 30000, result.turn
        self.count, self.active, lab.gateBlocked = 0, true, true
        self.status = 'Input blocked for 30 seconds'
        log('input_gate_start', { durationMs = 30000, state = result.state, proofOfCompleteGate = false })
        return true
    end
    function self:update()
        if not self.active then return end
        local ok, reason = pcall(function()
            local t = now()
            if t < self.started then return 'clock-reset' end
            if t >= self.deadline then return 'timeout' end
            context()
            if env.Game:GetTurnCount() ~= self.turn then return 'turn-changed' end
            self.status = 'Input blocked: ' .. math.ceil((self.deadline - t) / 1000) .. 's'
        end)
        if not ok then self:stop('context-or-clock-error', true)
        elseif reason then self:stop(reason, reason ~= 'timeout') end
    end
    function self:handle(kind, code)
        self:update()
        local device = (kind == 'keydown' or kind == 'keyup') and 'key' or
            ((kind == 'mousedown' or kind == 'mouseup') and 'mouse' or nil)
        local id = device and device .. ':' .. tostring(code) or nil
        local down = kind == 'keydown' or kind == 'mousedown'
        local up = kind == 'keyup' or kind == 'mouseup'
        local recognized = device or kind == 'wheel' or kind == 'text'
        if not recognized then return false end -- Motion and quit deliberately pass.
        if not self.active and not (id and self.held[id]) then return false end
        if down then self.held[id] = true elseif up then self.held[id] = nil end
        self.count = self.count + 1
        if self.count <= 128 then
            log('input_gate_blocked', { kind = kind, code = code, active = self.active })
        elseif self.count == 129 then log('input_gate_log_limit', { limit = 128 }) end
        return true
    end
    function self:install()
        local function safe(fn)
            local wasActive = self.active
            local ok, value = pcall(fn)
            if ok then return value end
            self:stop('callback-error', true)
            log('input_gate_error', { reason = tostring(value) })
            return wasActive -- Contain the failing event; diagnostic then releases.
        end
        env.modApi.events.onKeyPressing:subscribe(function(code)
            return safe(function() return self:handle('keydown', code) end)
        end)
        env.modApi.events.onKeyReleasing:subscribe(function(code)
            return safe(function() return self:handle('keyup', code) end)
        end)
        -- Retain userdata. The loader UI's earlier hook still runs first.
        self.nativeHook = env.sdl.eventHook(function(event)
            return safe(function()
                local t, types = event:type(), env.sdl.events
                if t == types.mousebuttondown then return self:handle('mousedown', event:mousebutton()) end
                if t == types.mousebuttonup then return self:handle('mouseup', event:mousebutton()) end
                if t == types.mousewheel then return self:handle('wheel') end
                if t == types.textinput then return self:handle('text') end
                return false
            end)
        end)
    end
    return self
end
return gate
