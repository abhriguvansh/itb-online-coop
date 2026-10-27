local probe = {}

function probe.new(mod, env, json, snapshot, settle)
    local self = {
        sequence = 0, epoch = 0, builds = 0, subscribed = false,
        observer = settle.new(3), nextSample = 0,
    }
    local function emit(kind, payload)
        self.sequence = self.sequence + 1
        env.LOG('ITBCOOP ' .. json.encode({ schema = 'itb-probe-log-v1',
            event = kind, sequence = self.sequence, epoch = self.epoch, payload = payload or {} }))
    end
    local function allowed()
        -- getCurrentProfile returns a folder key, which survives profile renames.
        -- The loader refreshes Profile on main-menu entry and profile changes.
        local key = env.modApi:getCurrentProfile()
        return type(key) == 'string' and key ~= '' and type(env.Profile) == 'table'
            and env.Profile.visible_name == 'ITB_Coop_Probe'
    end
    function self:record(kind, payload) emit(kind, payload) end
    function self:resetTrace(stage,mission)
        if not env.os or env.os.getenv('ITB_COOP_RESET_TRACE')~='1' or not allowed() then return end
        local ok,payload=pcall(function()
            local current=env.GetCurrentMission()
            local saved,data=pcall(env.ReadSaveData)
            local index=env.RegionData and env.RegionData.iBattleRegion
            local region=saved and index and data.RegionData['region'..index]
            local p=region and region.player
            local result={stage=stage,elapsed=env.modApi:elapsedTime(),boardPresent=env.Board~=nil,
                mission=current and current.ID,hookMission=mission and mission.ID,sameMission=mission==current,
                turn=env.Game and env.Game:GetTurnCount(),team=env.Game and env.Game:GetTeamTurn(),
                savedRegion=index,savedTurn=p and p.iCurrentTurn,savedTeam=p and p.iTeamTurn,savedUndoTurn=p and p.iUndoTurn,
                savedActions=p and p.actions,savedPresent=saved,savedUnavailable=not saved and tostring(data) or nil,
                coverage='reset-observation-only',proofOfCompletion=false}
            return result
        end)
        emit(ok and 'reset_lifecycle_observed' or 'reset_observation_unavailable',ok and payload or {stage=stage,reason=tostring(payload)})
        return ok and payload.savedPresent
    end
    local function clear()
        self.epoch = self.epoch + 1
        self.observer:reset()
        self.builds = 0
        self.nextSample = 0
    end
    local function observe(kind, pawn, weaponId, p1, p2)
        if not allowed() or not env.Board or env.Board:IsTipImage() then return end
        local payload = { weapon = weaponId }
        if pawn then payload.localPawnId = pawn:GetId() end
        if p1 then payload.from = { x = p1.x, y = p1.y } end
        if p2 then payload.to = { x = p2.x, y = p2.y } end
        emit(kind, payload)
        self.observer:reset()
    end
    function self:load()
        clear()
        emit('probe_loaded', { version = mod.version, loader = env.modApi.version,
            game = env.modApi:getGameVersion(), mode = 'observer-with-opt-in-movement-lab',
            testProfileSelected = allowed(), requiredProfile = 'ITB_Coop_Probe',
            runtimeVerified = false })
        self:resetTrace('mod-load')
    end
    function self:subscribe()
        if self.subscribed then return end
        self.subscribed = true
        local function subscribe(events, name, callback)
            local event = events and events[name]
            if not event or type(event.subscribe) ~= 'function' then
                emit('missing_hook', { name = name })
                return
            end
            event:subscribe(callback)
        end
        local extEvents = env.modapiext and env.modapiext.events
        for _, name in ipairs({ 'onSkillStart', 'onSkillEnd', 'onQueuedSkillStart', 'onQueuedSkillEnd' }) do
            local eventName = name
            subscribe(extEvents, eventName, function(mission, pawn, weaponId, p1, p2)
                observe(eventName, pawn, weaponId, p1, p2)
            end)
        end
        subscribe(extEvents, 'onSkillBuild', function()
            if allowed() and env.Board and not env.Board:IsTipImage() then
                self.builds = self.builds + 1
            end
        end)
        for _, name in ipairs({ 'onPawnUndoMove', 'onResetTurn' }) do
            local eventName = name
            subscribe(extEvents, eventName, function(mission,pawn,previous)
                clear()
                if allowed() then emit('unsupported_action_observed', { source = eventName, blocked = false }) end
                if eventName=='onResetTurn' then self:resetTrace('reset-hook',mission);self.resetLater=true;self.resetRetryUntil=env.modApi:elapsedTime()+10000;self.resetRetryAt=0 end
                if eventName=='onPawnUndoMove' and allowed() and pawn and env.Board and not env.Board:IsTipImage() then
                    local ok,payload=pcall(function()
                        local p=pawn:GetSpace()
                        return {localPawnId=pawn:GetId(),previous=previous and {x=previous.x,y=previous.y},
                            position={x=p.x,y=p.y},health=pawn:GetHealth(),active=pawn:IsActive(),
                            movementSpent=pawn:IsMovementSpent(),undoPossible=pawn:IsUndoPossible(),
                            fire=pawn:IsFire(),mission=mission and mission.ID,elapsed=env.modApi:elapsedTime(),
                            coverage='native-undo-hook-observation-only',proofOfCompletion=false}
                    end)
                    emit(ok and 'native_undo_move_observed' or 'undo_observation_unavailable',ok and payload or {reason=tostring(payload)})
                end
            end)
        end
        local events = env.modApi.events
        subscribe(events,'onFrameDrawStart',function()
            if not env.os or env.os.getenv('ITB_COOP_RESET_TRACE')~='1' or not allowed() then return end
            local r=env.sdlext.CurrentWindowRect
            local fingerprint=r and table.concat({r.x,r.y,r.w,r.h},':') or 'none'
            if fingerprint~=self.resetRect then
                self.resetRect=fingerprint
                emit('reset_window_observed',{elapsed=env.modApi:elapsedTime(),rect=r and {x=r.x,y=r.y,w=r.w,h=r.h}})
            end
        end)
        for _,name in ipairs({'onPreLoadGame','onPostLoadGame','onWindowShown','onWindowHidden'})do
            local stage=name
            subscribe(events,stage,function()self:resetTrace(stage,env.GetCurrentMission())end)
        end
        for _, name in ipairs({ 'onMissionStart', 'onNextTurn', 'onPreEnvironment', 'onPostEnvironment',
                'onPreEnvPlanned', 'onPostEnvPlanned', 'onVekSpawnAdded', 'onVekSpawnRemoved', 'onVekSpawningEnd' }) do
            local eventName = name
            subscribe(events, eventName, function()
                self.observer:reset()
                if allowed() then emit('phase_observed', { source = eventName }) end
            end)
        end
        for _, name in ipairs({ 'onMissionChanged', 'onMissionEnd', 'onTestMechEntered',
                'onTestMechExited', 'onGameExited', 'onProfileChanged' }) do
            local eventName = name
            subscribe(events, eventName, function()
                clear()
                emit('context_changed', { source = eventName, testProfileSelected = allowed() })
            end)
        end
        subscribe(events, 'onMissionUpdate', function(mission)
            if self.resetLater and env.modApi:elapsedTime()>=(self.resetRetryAt or 0) then
                local available=self:resetTrace('later-mission-update',mission)
                self.resetRetryAt=env.modApi:elapsedTime()+250
                if available or env.modApi:elapsedTime()>self.resetRetryUntil then self.resetLater=nil end
            end
            if not allowed() or not env.Board or env.Board:IsTipImage() then
                self.observer:reset()
                return
            end
            local now = env.modApi:elapsedTime()
            if now < self.nextSample then return end
            self.nextSample = now + 100
            local ok, state, idle = pcall(snapshot.capture, env, mission, json)
            if not ok then
                self.observer:reset()
                if not self.captureError then emit('capture_failed', { detail = tostring(state) }) end
                self.captureError = true
                return
            end
            self.captureError = false
            if self.observer:sample(idle, json.encode(state)) then
                emit('settled_candidate', { stableSamples = 3, sampleIntervalMs = 100,
                    proofOfQuiescence = false, buildCallsSincePreviousCandidate = self.builds,
                    state = state })
                self.builds = 0
            end
        end)
        emit('observer_registered', { changesGameplay = false, inputGateImplemented = false })
    end
    return self
end

return probe
