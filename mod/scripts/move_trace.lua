-- Read-only timing evidence. No effect modification, setters, or action calls.
local trace = {}
function trace.new(env, emit, json)
    local self = {}
    function self:reset()
        self.count, self.limited, self.previews, self.watched = 0, false, {}, {}
    end
    self:reset()
    local function allowed()
        local key = env.modApi:getCurrentProfile()
        local mission = env.GetCurrentMission()
        return type(key) == 'string' and key ~= '' and env.Profile
            and env.Profile.visible_name == 'ITB_Coop_Probe'
            and env.modApi:getGameVersion() == '1.2.93'
            and mission and mission.ID == 'Mission_Artillery'
            and env.Board and not env.Board:IsTipImage()
    end
    local function point(p) return {x=p.x,y=p.y} end
    local function state(pawn)
        local result = {unavailable=json.array()}
        local function read(name, fn)
            local ok, value = pcall(fn)
            if ok and value ~= nil then result[name] = value
            else result.unavailable[#result.unavailable+1] = name end
        end
        read('position', function() return point(pawn:GetSpace()) end)
        read('movementSpent', function() return pawn:IsMovementSpent() end)
        read('undoPossible', function() return pawn:IsUndoPossible() end)
        read('undoPosition', function() return point(pawn:GetUndoLoc()) end)
        read('active', function() return pawn:IsActive() end)
        read('health', function() return pawn:GetHealth() end)
        read('pawnBusy', function() return pawn:IsBusy() end)
        read('boardBusy', function() return env.Board:IsBusy() end)
        read('turn', function() return env.Game:GetTurnCount() end)
        read('team', function() return env.Game:GetTeamTurn() end)
        return result
    end
    local function record(stage, id, observed, extra)
        if self.count >= 128 then
            if not self.limited then emit('move_trace_limit', {limit=128}); self.limited=true end
            return
        end
        self.count = self.count + 1
        emit('move_trace', {stage=stage, pawnId=id, elapsedMs=env.modApi:elapsedTime(),
            state=observed, detail=extra, changesGameplay=false, proofOfCommitBoundary=false})
    end
    function self:observe(stage, pawn, weapon, from, to)
        -- Never allow diagnostic failures to interrupt a native skill callback.
        local ok, reason = pcall(function()
            if not allowed() or self.limited or (weapon ~= 'Move' and weapon ~= 'Prime_Punchmech' and weapon ~= 'Brute_Tankmech' and weapon ~= 'Ranged_Artillerymech') or not pawn then return end
            local id = pawn:GetId()
            if id ~= 0 and id ~= 1 and id ~= 2 then return end
            local observed = state(pawn)
            local fingerprint = json.encode(observed)
            local target = {weapon=weapon,from=from and point(from), to=to and point(to)}
            if stage == 'build' then
                local old = self.previews[id]
                -- Keep the latest scalar preview even if its state did not change.
                self.previews[id] = {state=observed, fingerprint=fingerprint, target=target}
                if not old or old.fingerprint ~= fingerprint then record(stage,id,observed,target) end
            else
                record(stage,id,observed,{target=target, lastBuild=self.previews[id]})
                self.watched[id] = {fingerprint=fingerprint, untilMs=env.modApi:elapsedTime()+2000}
            end
        end)
        if not ok and not self.limited then
            self.limited = true
            emit('move_trace_error', {stage=stage, reason=tostring(reason)})
        end
    end
    function self:update()
        local ok, reason = pcall(function()
            if not allowed() or self.limited then return end
            for id, watch in pairs(self.watched) do
                if env.modApi:elapsedTime() > watch.untilMs then self.watched[id]=nil
                else
                    local pawn = env.Board:GetPawn(id)
                    if not pawn then
                        record('pawn-missing',id,{}); self.watched[id]=nil
                    else
                        local observed = state(pawn)
                        local fingerprint = json.encode(observed)
                        if fingerprint ~= watch.fingerprint then
                            record('update',id,observed); watch.fingerprint=fingerprint
                        end
                    end
                end
            end
        end)
        if not ok and not self.limited then
            self.limited=true; emit('move_trace_error', {stage='update',reason=tostring(reason)})
        end
    end
    return self
end
return trace
