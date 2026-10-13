-- Offline integration experiment. Not loaded or installed by the probe.
-- The caller is a trusted harness, not an authenticated network peer.
local M = {}
local function id(v)
    return type(v) == 'string' and #v > 0 and #v <= 96 and v:match('^[%w_.:-]+$') ~= nil
end
local function integer(v) return type(v) == 'number' and v >= 0 and v <= 1000000 and v == math.floor(v) end
local function copy(t) local c = {}; for k,v in pairs(t) do c[k] = v end; return c end
local fields = {'id','session','encounter','phase','revision','witness','kind','actor','fromX','fromY','toX','toY'}
local allowed = {}; for _,k in ipairs(fields) do allowed[k] = true end
local function envelope(r)
    if type(r) ~= 'table' or getmetatable(r) then return false end
    for k in pairs(r) do if not allowed[k] then return false end end
    for _,k in ipairs({'id','session','encounter','phase','actor'}) do if not id(r[k]) then return false end end
    if not integer(r.revision) or type(r.witness) ~= 'string' or #r.witness == 0 or #r.witness > 65536 then return false end
    if r.kind ~= 'move' and r.kind ~= 'lab-punch' then return false end
    for _,k in ipairs({'fromX','fromY','toX','toY'}) do if not integer(r[k]) or r[k] > 7 then return false end end
    return true
end
local function same(a,b) for _,k in ipairs(fields) do if a[k] ~= b[k] then return false end end; return true end

function M.new(o)
    assert(id(o.session) and id(o.encounter) and id(o.phase), 'invalid-session-identity')
    assert(#o.players == 2 and id(o.players[1]) and id(o.players[2]) and o.players[1] ~= o.players[2], 'two-distinct-players-required')
    local players = {[o.players[1]]=true,[o.players[2]]=true}
    local registry, localIds = {}, {}
    for key,e in pairs(o.entities) do
        assert(id(key) and integer(e.pawnId) and not localIds[e.pawnId], 'invalid-entity-mapping')
        assert(players[e.owner] or (e.owner == false and e.commandable == false), 'explicit-owner-required')
        assert(type(e.commandable) == 'boolean', 'classify-friendly-entity')
        registry[key],localIds[e.pawnId] = copy(e),true
    end
    local self = {revision=0, stopped=false}
    local records, count, pending, observed = {}, 0, nil, false
    local move, attack
    local function emit(kind,data)
        local ok = pcall(o.emit,kind,data)
        if not ok then
            self.stopped=true; self.reason='evidence-write-failed'
            if pending then pending.status='uncertain'; pending.reason=self.reason end
        end
    end
    function self:stop(reason)
        if not self.stopped then
            self.stopped=true; self.reason=reason
            if pending then pending.status='uncertain'; pending.reason=reason end
            emit('session_stopped',{reason=reason,revision=self.revision})
        end
        -- Keep this latch separate from diagnostic reset and native input teardown.
    end
    local function health()
        if o.gate.active then self:stop('diagnostic-gate-overlap'); return false end
        local ok,healthy = pcall(o.guardHealthy)
        if not ok or healthy ~= true then self:stop('protection-unavailable'); return false end
        local inventoryOk = pcall(function()
            local pawns = o.env.Board:GetPawns(o.env.TEAM_PLAYER)
            assert(pawns:size() <= 64)
            for i=1,pawns:size() do assert(localIds[pawns:index(i)], 'unmapped-friendly') end
        end)
        if not inventoryOk then self:stop('friendly-inventory-changed'); return false end
        if move.fault or attack.fault then self:stop('diagnostic-fault'); return false end
        return not self.stopped
    end
    local function labEvent(kind,data)
        emit(kind,data)
        -- A lab's pre-dispatch evidence callback must not return normally after
        -- failed logging: the next line in that lab may cross the engine boundary.
        if self.stopped then error(self.reason) end
        if pending then
            local expected = pending.request.kind == 'move' and 'move_postconditions_observed' or 'attack_postconditions_observed'
            if kind == expected then observed=true end
            if kind == 'move_failed' or kind == 'attack_failed' or kind == 'attack_outcome_timeout' then
                self:stop(kind)
            end
        end
    end
    move = o.movement.new(o.env,labEvent,'ui')
    move.bridge = o.bridge
    attack = o.attack.new(o.env,move,o.gate,labEvent,o.capture,o.json)
    local function result(record)
        return {status=record.status,reason=record.reason,revision=record.revision or self.revision}
    end
    local function witness()
        local ok,value = pcall(o.witness)
        if not ok or type(value) ~= 'string' or #value == 0 or #value > 65536 then
            self:stop('observation-unavailable'); return nil
        end
        return value
    end
    function self:submit(peer,r)
        if not players[peer] then return {status='rejected',reason='unknown-peer'} end
        if not envelope(r) then return {status='rejected',reason='invalid-envelope'} end
        local key=peer..'/'..r.id
        if records[key] then
            if not same(records[key].request,r) then return {status='rejected',reason='request-id-conflict'} end
            return {status='duplicate',originalStatus=records[key].status,reason=records[key].reason,revision=records[key].revision}
        end
        if count >= 128 then self:stop('experiment-record-limit'); return {status='stopped',reason=self.reason} end
        local rec={request=copy(r),status='rejected',revision=self.revision}; records[key]=rec; count=count+1
        local function reject(reason) rec.reason=reason; emit('command_rejected',{id=r.id,peer=peer,reason=reason}); return result(rec) end
        if not health() then return reject(self.reason) end
        if r.session ~= o.session or r.encounter ~= o.encounter or r.phase ~= o.phase then return reject('wrong-context') end
        if pending then return reject('command-pending-renew-intent') end
        if r.revision ~= self.revision then return reject('stale-revision-renew-intent') end
        local entity=registry[r.actor]
        if not entity or not entity.commandable or entity.owner ~= peer then return reject('actor-not-owned') end
        local current=witness()
        if self.stopped then return reject(self.reason) end
        if r.witness ~= current then return reject('stale-observation-renew-intent') end
        -- Retain the exact fixed punch, including actor/target. This is not an arbitrary attack API.
        if r.kind == 'lab-punch' and (entity.pawnId ~= 0 or r.fromX ~= 3 or r.fromY ~= 3 or r.toX ~= 2 or r.toY ~= 3) then
            return reject('unsupported-punch-scenario')
        end
        local lab = r.kind == 'move' and move or attack
        local command={pawnId=entity.pawnId,from={x=r.fromX,y=r.fromY},to={x=r.toX,y=r.toY},mission='Mission_Artillery',turn=2}
        local ok,armed = pcall(function() return lab:arm() end)
        if not ok then self:stop('validation-exception'); return reject(self.reason) end
        if not armed then return reject('diagnostic-validation:'..tostring(lab.status)) end
        if r.kind == 'move' then
            local valid,reason=move:validate(command)
            if not valid then move.armed=false; return reject('diagnostic-validation:'..tostring(reason)) end
        end
        -- Arm and validation can call engine getters. Recheck before reserving execution.
        if not health() or r.witness ~= witness() then
            if r.kind == 'move' then move.armed=false else attack:disarm() end
            return reject(self.reason or 'stale-observation-renew-intent')
        end
        pending=rec; observed=false; rec.status='pending'
        emit('command_admitted',{id=r.id,peer=peer,kind=r.kind,actor=r.actor,revision=self.revision})
        if self.stopped then rec.status='uncertain'; rec.reason=self.reason; return result(rec) end
        local called,accepted=pcall(function() return lab:request(command) end)
        -- Even a false return is not permission to retry a possibly submitted engine action.
        if not called or not accepted or self.stopped then self:stop('dispatch-rejected-or-uncertain') end
        return result(rec)
    end
    function self:update()
        if not health() then return end
        local ok = pcall(function() move:update(); attack:update() end)
        if not ok then self:stop('update-exception'); return end
        if not health() then return end
        if pending and observed and not move.pending and not attack.pending then
            self.revision=self.revision+1
            pending.status='observed'; pending.revision=self.revision
            emit('command_observed',{id=pending.request.id,revision=self.revision,proofOfQuiescence=false,proofOfPeerAgreement=false})
            pending=nil; observed=false; move.armed=false
        elseif pending and not move.pending and not attack.pending then
            self:stop('missing-completion-evidence')
        end
    end
    function self:skillEvent(kind,pawn,weapon)
        if self.stopped then return end
        local ok=pcall(function() move:skillEvent(kind,pawn,weapon); attack:skillEvent(kind,pawn,weapon) end)
        if not ok then self:stop('hook-exception') end
    end
    -- Persistence boundary intentionally has no restore operation in this non-resumable experiment.
    function self:checkpoint() return nil,'unsupported-non-resumable-experiment' end
    return self
end
return M
