-- Restricted command lifecycle. Runtime entry is the trusted diagnostic harness.
-- The optional transport binds peer identity before this boundary.
local M = {}
local function id(v)
    return type(v) == 'string' and #v > 0 and #v <= 96 and v:match('^[%w_.:-]+$') ~= nil
end
local function integer(v) return type(v) == 'number' and v >= 0 and v <= 1000000 and v == math.floor(v) end
local function copy(t) local c = {}; for k,v in pairs(t) do c[k] = v end; return c end
local fields = {'id','session','encounter','phase','revision','witness','kind','actor','fromX','fromY','toX','toY','confirmUnused','confirmDeployment','confirmReset'}
local allowed = {}; for _,k in ipairs(fields) do allowed[k] = true end
local function envelope(r)
    if type(r) ~= 'table' or getmetatable(r) then return false end
    for k in pairs(r) do if not allowed[k] then return false end end
    for _,k in ipairs({'id','session','encounter','phase'}) do if not id(r[k]) then return false end end
    if not integer(r.revision) or type(r.witness) ~= 'string' or #r.witness == 0 or #r.witness > 65536 then return false end
    if r.kind=='reset-turn' then
        return r.confirmReset==true and r.confirmUnused==nil and r.confirmDeployment==nil and r.actor==nil
            and r.fromX==nil and r.fromY==nil and r.toX==nil and r.toY==nil
    end
    if r.confirmReset~=nil then return false end
    if r.kind=='deployment-confirm' then
        return r.confirmDeployment==true and r.confirmUnused==nil and r.actor==nil and r.fromX==nil and r.fromY==nil and r.toX==nil and r.toY==nil
    end
    if r.confirmDeployment~=nil then return false end
    if r.kind=='end-turn' then
        return r.confirmUnused==true and r.actor==nil and r.fromX==nil and r.fromY==nil and r.toX==nil and r.toY==nil
    end
    if r.kind=='deploy' then
        return id(r.actor) and r.confirmUnused==nil and r.fromX==-1 and r.fromY==-1
            and integer(r.toX) and r.toX<=7 and integer(r.toY) and r.toY<=7
    end
    if (r.kind ~= 'move' and r.kind ~= 'undo-move' and r.kind ~= 'lab-punch' and r.kind ~= 'basic-attack' and r.kind~='repair') or not id(r.actor) or r.confirmUnused~=nil then return false end
    for _,k in ipairs({'fromX','fromY','toX','toY'}) do if not integer(r[k]) or r[k] > 7 then return false end end
    return r.kind~='repair' or r.fromX==r.toX and r.fromY==r.toY
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
    local self = {revision=0, stopped=false,phase=o.phase,turn=o.env.Game:GetTurnCount()}
    local records, count, pending, observed = {}, 0, nil, false
    local primaryInstalled=not o.primarySetup
    local move, attack, ending, deployment, undo, reset
    local ready={}
    -- The observed native button undoes moves in reverse execution order,
    -- regardless of the selected pawn. Never skip another actor's latest move.
    local undoMoves={}
    local function protectStop() if o.stopProtection then pcall(o.stopProtection) end end
    local function emit(kind,data)
        local ok = pcall(o.emit,kind,data)
        if not ok then
            self.stopped=true; self.reason='evidence-write-failed'
            protectStop()
            if pending then pending.status='uncertain'; pending.reason=self.reason end
        end
    end
    function self:stop(reason)
        if not self.stopped then
            self.stopped=true; self.reason=reason
            protectStop()
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
            if pending and pending.request.kind=='reset-turn' and reset and reset:loading() then return end
            local pawns = o.env.Board:GetPawns(o.env.TEAM_PLAYER)
            assert(pawns:size() <= 64)
            for i=1,pawns:size() do assert(localIds[pawns:index(i)], 'unmapped-friendly') end
        end)
        if not inventoryOk then self:stop('friendly-inventory-changed'); return false end
        if move.fault or attack.fault or (reset and reset.fault) or (undo and undo.fault) or (ending and ending.fault) or (deployment and deployment.fault) then self:stop('diagnostic-fault'); return false end
        return not self.stopped
    end
    local function labEvent(kind,data)
        emit(kind,data)
        -- A lab's pre-dispatch evidence callback must not return normally after
        -- failed logging: the next line in that lab may cross the engine boundary.
        if self.stopped then error(self.reason) end
        if pending then
            local expected = pending.request.kind=='deployment-confirm' and 'deployment_launch_observed' or pending.request.kind=='deploy' and 'deployment_postconditions_observed' or pending.request.kind == 'move' and 'move_postconditions_observed'
                or pending.request.kind=='reset-turn' and 'reset_turn_postconditions_observed' or pending.request.kind=='undo-move' and 'undo_move_postconditions_observed' or pending.request.kind=='end-turn' and 'end_turn_postconditions_observed' or 'attack_postconditions_observed'
            if kind == expected then observed=true;if pending.request.kind=='reset-turn' then self.resetRemaining=data.remaining end end
            if kind == 'move_failed' or kind == 'reset_turn_failed' or kind == 'undo_move_failed' or kind == 'attack_failed' or kind == 'attack_outcome_timeout' or kind=='end_turn_failed' or kind=='deployment_failed' then
                self:stop(kind)
            end
        end
    end
    move = o.movement.new(o.env,labEvent,'ui')
    if o.deployment or o.fullMission then move.supportedMission='Mission_Tides' end
    move.bridge = o.bridge
    attack = o.attack.new(o.env,move,o.gate,labEvent,o.capture,o.json)
    attack.bridge=o.bridge
    if o.undoMove and o.repeatedTurns then undo=o.undoMove.new(o.env,move,o.gate,labEvent,o.capture,o.json);undo.bridge=o.bridge end
    if o.resetTurn and o.repeatedTurns then reset=o.resetTurn.new(o.env,o.native,labEvent,o.capture,o.json);reset.fullMission=o.fullMission end
    if o.endTurn then ending=o.endTurn.new(o.env,o.native,labEvent,o.capture,o.phaseSettled) end
    if o.deployment then deployment=o.deployment.new(o.env,o.native,labEvent,o.capture,o.json,o.phaseSettled) end
    if o.repeatedTurns and ending then ending.repeatedTurns=true end
    if o.fullMission and ending then ending.fullMission=true end
    if o.terminalCheckpoint and ending then ending.terminalCheckpoint=true end
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
    function self:installPrimaryOwners(owners,expected)
        assert(o.primarySetup and o.deployment and o.fullMission and not primaryInstalled and self.phase=='deployment' and self.revision==0
            and self.turn==0 and count==0 and not pending and not self.terminal and health(),'primary-install-context')
        assert(type(owners)=='table' and getmetatable(owners)==nil and witness()==expected,'primary-install-state')
        local keys={combat=0,cannon=1,artillery=2};local n,host=0,0
        for actor,owner in pairs(owners) do
            local e=registry[actor];assert(keys[actor]~=nil and e and e.pawnId==keys[actor] and e.owner==false
                and e.commandable==false and players[owner],'primary-install-map')
            n=n+1;if owner=='host' then host=host+1 end
        end
        assert(n==3 and host>=1 and host<=2 and not self.stopped,'primary-install-participants')
        for actor,owner in pairs(owners) do registry[actor].owner=owner;registry[actor].commandable=true end
        primaryInstalled=true;emit('primary_owners_installed',{owners=copy(owners),revision=0,immutable=true})
    end
    local function undoMatch(peer,r)
        local m=undoMoves[#undoMoves]
        return undo and m and m.peer==peer and m.actor==r.actor and m.revision<=self.revision
            and m.phase==self.phase and m.turn==self.turn and r.fromX==m.toX and r.fromY==m.toY
            and r.toX==m.fromX and r.toY==m.fromY
    end
    local function commandFor(r,entity)
        if r.kind=='deployment-confirm' then return {launch=true} end
        if r.kind=='reset-turn' then return {turn=self.turn,restoreWitness=self.resetBase and self.resetBase.restoreWitness,actionObserved=self.resetAction==true} end
        if not entity then return nil end
        return {pawnId=entity.pawnId,repair=r.kind=='repair' or nil,from={x=r.fromX,y=r.fromY},to={x=r.toX,y=r.toY},
            mission=(o.deployment or o.fullMission) and 'Mission_Tides' or 'Mission_Artillery',turn=self.turn,
            restoreWitness=r.kind=='undo-move' and undoMoves[#undoMoves] and undoMoves[#undoMoves].witness or nil}
    end
    function self:undoTarget(peer,actor)
        local m=undoMoves[#undoMoves]
        if not undo or pending or self.stopped then return nil,'Undo unavailable while a command is active or stopped' end
        if not m or m.phase~=self.phase or m.turn~=self.turn then return nil,'No recorded native move to undo; attacks clear Undo' end
        if m.peer~=peer or m.actor~=actor then return nil,'Native Undo reverses the newest move; that mech must undo first' end
        return {fromX=m.toX,fromY=m.toY,toX=m.fromX,toY=m.fromY}
    end
    function self:setReady(peer,phase,revision,value,confirmUnused,kind)
        if not primaryInstalled then return false end
        if self.terminal then return false end
        if not players[peer] then return false end
        ready[peer]=nil
        if not health() or pending or self.phase~=phase or self.revision~=revision or confirmUnused~=true
            or o.env.Game:GetTeamTurn()~=(self.phase=='deployment' and o.env.TEAM_ENEMY or o.env.TEAM_PLAYER) or o.env.Game:GetTurnCount()~=self.turn then return false end
        if value~=witness() or self.stopped then return false end
        kind=kind or (self.phase=='deployment' and 'deployment-confirm' or 'end-turn')
        if kind~='end-turn' and kind~='deployment-confirm' and not (kind=='reset-turn' and reset) then return false end
        ready[peer]={phase=phase,revision=revision,witness=value,kind=kind};return true
    end
    function self:clearResetReady()for peer,v in pairs(ready)do if v.kind=='reset-turn' then ready[peer]=nil end end end
    function self:canReset(peer,phase,revision,value)
        if not primaryInstalled then return false,'primary-setup-pending' end
        if not reset or not players[peer] or self.terminal or not health() or pending or self.phase=='deployment'
            or self.phase~=phase or self.revision~=revision or value~=witness() then return false,'reset-context-unavailable' end
        if not self.resetBase or self.resetBase.turn~=self.turn or self.resetBase.phase~=self.phase then return false,'fresh-turn-start-required' end
        if not self.resetAction then return false,'native-action-required-before-reset' end
        local ok,armed=pcall(function()return reset:arm({turn=self.turn,restoreWitness=self.resetBase.restoreWitness,actionObserved=true})end)
        reset.armed=false;reset.command=nil
        if not ok then self:stop('reset-validation-exception');return false,self.reason end
        return armed,reset.status
    end
    function self:submit(peer,r)
        if not players[peer] then return {status='rejected',reason='unknown-peer'} end
        if not envelope(r) then return {status='rejected',reason='invalid-envelope'} end
        if not primaryInstalled then return {status='rejected',reason='primary-setup-pending'} end
        local key=peer..'/'..r.id
        if records[key] then
            if not same(records[key].request,r) then return {status='rejected',reason='request-id-conflict'} end
            return {status='duplicate',originalStatus=records[key].status,reason=records[key].reason,revision=records[key].revision}
        end
        if count >= 128 then self:stop('experiment-record-limit'); return {status='stopped',reason=self.reason} end
        local rec={request=copy(r),status='rejected',revision=self.revision}; records[key]=rec; count=count+1
        local function reject(reason) rec.reason=reason; emit('command_rejected',{id=r.id,peer=peer,reason=reason}); return result(rec) end
        if self.terminal then return reject('mission-result-pending') end
        if not health() then return reject(self.reason) end
        if r.session ~= o.session or r.encounter ~= o.encounter or r.phase ~= self.phase then return reject('wrong-context') end
        if pending then return reject('command-pending-renew-intent') end
        if (self.phase=='deployment' and (not deployment or (r.kind~='deploy' and r.kind~='deployment-confirm') or o.env.Game:GetTeamTurn()~=o.env.TEAM_ENEMY))
            or (self.phase~='deployment' and (r.kind=='deploy' or r.kind=='deployment-confirm' or o.env.Game:GetTeamTurn()~=o.env.TEAM_PLAYER))
            or o.env.Game:GetTurnCount()~=self.turn then
            return reject('wrong-engine-phase')
        end
        if r.revision ~= self.revision then return reject('stale-revision-renew-intent') end
        local entity=registry[r.actor]
        if r.kind~='end-turn' and r.kind~='deployment-confirm' and r.kind~='reset-turn' and (not entity or not entity.commandable or entity.owner ~= peer) then return reject('actor-not-owned') end
        local current=witness()
        if self.stopped then return reject(self.reason) end
        if r.witness ~= current then return reject('stale-observation-renew-intent') end
        if r.kind=='undo-move' and not undoMatch(peer,r) then return reject('no-current-owned-move-to-undo') end
        if r.kind=='end-turn' or r.kind=='deployment-confirm' or r.kind=='reset-turn' then
            if r.kind=='end-turn' and not ending then return reject('end-turn-unavailable') end
            if r.kind=='reset-turn' and (not reset or not self.resetBase or self.resetBase.turn~=self.turn) then return reject('fresh-turn-start-required') end
            for player in pairs(players) do
                local consent=ready[player]
                if not consent or consent.kind~=r.kind or consent.phase~=r.phase or consent.revision~=r.revision or consent.witness~=r.witness then
                    return reject('both-players-must-be-ready')
                end
            end
        end
        if (r.kind=='basic-attack' or r.kind=='repair') and not o.repeatedTurns then return reject('basic-attack-unavailable') end
        -- Retain the exact fixed punch, including actor/target. This is not an arbitrary attack API.
        if r.kind == 'lab-punch' and (entity.pawnId ~= 0 or r.fromX ~= 3 or r.fromY ~= 3 or r.toX ~= 2 or r.toY ~= 3) then
            return reject('unsupported-punch-scenario')
        end
        local lab = (r.kind=='deploy' or r.kind=='deployment-confirm') and deployment or r.kind == 'move' and move or r.kind=='reset-turn' and reset or r.kind=='undo-move' and undo or r.kind=='end-turn' and ending or attack
        local command=commandFor(r,entity)
        local ok,armed = pcall(function() return lab:arm(command) end)
        if not ok then self:stop('validation-exception'); return reject(self.reason) end
        if not armed then return reject('diagnostic-validation:'..tostring(lab.status)) end
        if r.kind == 'move' then
            local valid,reason=move:validate(command)
            if not valid then move.armed=false; return reject('diagnostic-validation:'..tostring(reason)) end
        end
        -- Arm and validation can call engine getters. Recheck before reserving execution.
        if not health() or r.witness ~= witness() then
            if lab==deployment or lab==reset then lab.armed=false elseif r.kind == 'move' then move.armed=false elseif r.kind=='end-turn' then ending.armed=false else lab:disarm() end
            return reject(self.reason or 'stale-observation-renew-intent')
        end
        pending=rec; observed=false; rec.status='pending';rec.peer=peer;ready={}
        emit('command_admitted',{id=r.id,peer=peer,kind=r.kind,actor=r.actor,revision=self.revision})
        if self.stopped then rec.status='uncertain'; rec.reason=self.reason; return result(rec) end
        local called,accepted=pcall(function() return lab:request(command) end)
        -- Even a false return is not permission to retry a possibly submitted engine action.
        if not called or not accepted or self.stopped then self:stop('dispatch-rejected-or-uncertain') end
        return result(rec)
    end
    -- Read-only draft check; never reserves a command or crosses the input boundary.
    function self:previewMove(peer,r)
        if not primaryInstalled then return false,'primary-setup-pending' end
        if self.terminal then return false,'mission-result-pending' end
        if not players[peer] or not envelope(r) or r.kind~='move' then return false,'invalid-move-draft' end
        if not health() then return false,self.reason end
        if pending then return false,'command-pending-renew-intent' end
        if r.session~=o.session or r.encounter~=o.encounter or r.phase~=self.phase
            or r.revision~=self.revision or r.witness~=witness() then return false,'stale-draft-renew-intent' end
        local entity=registry[r.actor]
        if not entity or not entity.commandable or entity.owner~=peer then return false,'actor-not-owned' end
        if not move:arm() then return false,move.status end
        local ok,reason=move:validate({pawnId=entity.pawnId,from={x=r.fromX,y=r.fromY},to={x=r.toX,y=r.toY},
            mission=(o.deployment or o.fullMission) and 'Mission_Tides' or 'Mission_Artillery',turn=self.turn})
        move.armed=false
        return ok,ok and 'supported-move' or tostring(reason)
    end
    function self:previewAction(peer,r)
        if not primaryInstalled then return false,'primary-setup-pending' end
        if self.terminal then return false,'mission-result-pending' end
        if self.phase=='deployment' then
            if not deployment or not players[peer] or not envelope(r) or (r.kind~='deploy' and r.kind~='deployment-confirm') then return false,'invalid-deployment-draft' end
            if not health() then return false,self.reason end
            if pending then return false,'command-pending-renew-intent' end
            if r.session~=o.session or r.encounter~=o.encounter or r.phase~=self.phase or r.revision~=self.revision or r.witness~=witness() then return false,'stale-draft-renew-intent' end
            local e=registry[r.actor]
            if r.kind=='deployment-confirm' then
                for player in pairs(players) do local v=ready[player];if not v or v.phase~=r.phase or v.revision~=r.revision or v.witness~=r.witness then return false,'both-players-must-be-ready' end end
            elseif not e or not e.commandable or e.owner~=peer then return false,'actor-not-owned' end
            local ok=deployment:arm(r.kind=='deployment-confirm' and {launch=true} or {pawnId=e.pawnId,from={x=r.fromX,y=r.fromY},to={x=r.toX,y=r.toY}})
            deployment.armed=false
            if not health() or r.witness~=witness() then return false,self.reason or 'stale-draft-renew-intent' end
            return ok,deployment.status
        end
        if type(r)=='table' and r.kind=='move' then return self:previewMove(peer,r) end
        if not players[peer] or not envelope(r) then return false,'invalid-action-draft' end
        if not health() then return false,self.reason end
        if pending then return false,'command-pending-renew-intent' end
        if r.session~=o.session or r.encounter~=o.encounter or r.phase~=self.phase
            or r.revision~=self.revision or r.witness~=witness()
            or o.env.Game:GetTeamTurn()~=o.env.TEAM_PLAYER or o.env.Game:GetTurnCount()~=self.turn then
            return false,'stale-draft-renew-intent'
        end
        local lab
        if r.kind=='end-turn' or r.kind=='reset-turn' then
            if r.kind=='reset-turn' and (not reset or not self.resetBase or self.resetBase.turn~=self.turn) then return false,'fresh-turn-start-required' end
            if not ending then return false,'end-turn-unavailable' end
            for player in pairs(players) do
                local consent=ready[player]
                if not consent or consent.kind~=r.kind or consent.phase~=r.phase or consent.revision~=r.revision or consent.witness~=r.witness then
                    return false,'both-players-must-be-ready'
                end
            end
            lab=r.kind=='reset-turn' and reset or ending
        else
            local entity=registry[r.actor]
            if not entity or not entity.commandable or entity.owner~=peer then return false,'actor-not-owned' end
            if r.kind=='undo-move' then
                if not undoMatch(peer,r) then return false,'no-current-owned-move-to-undo' end
            elseif r.kind=='basic-attack' or r.kind=='repair' then
                if not o.repeatedTurns then return false,'basic-attack-unavailable' end
            elseif entity.pawnId~=0 or r.fromX~=3 or r.fromY~=3 or r.toX~=2 or r.toY~=3 then return false,'unsupported-punch-scenario' end
            lab=r.kind=='undo-move' and undo or attack
        end
        local entity=registry[r.actor]
        local command=commandFor(r,entity)
        local ok,armed=pcall(function()return lab:arm(command)end)
        local reason=lab.status
        if lab==attack or lab==undo then lab:disarm() else lab.armed=false end
        if not ok then self:stop('validation-exception');return false,self.reason end
        if not armed then return false,reason end
        if not health() or r.witness~=witness() then return false,self.reason or 'stale-draft-renew-intent' end
        return true,'supported-action'
    end
    function self:update()
        if self.terminal then
            local ok,healthy=pcall(o.guardHealthy)
            if not ok or not healthy then self:stop('protection-unavailable') end
            return
        end
        if not health() then return end
        local ok = pcall(function() move:update(); attack:update();if undo then undo:update() end;if reset then reset:update() end;if ending then ending:update() end;if deployment then deployment:update() end end)
        if not ok then self:stop('update-exception'); return end
        if not health() then return end
        if pending and observed and not move.pending and not attack.pending and not (reset and reset.pending) and not (undo and undo.pending) and not (ending and ending.pending) and not (deployment and deployment.pending) then
            if pending.request.kind=='deployment-confirm' then self.turn=1;self.phase='player1'
            elseif pending.request.kind=='end-turn' then
                self.turn=self.turn+1;self.phase='player'..self.turn
                -- Release only the successful previous turn's diagnostic reservation.
                -- Engine allowances, protection, hooks and session replay records still gate every action.
                if o.repeatedTurns then move.usedPawns={} end
            end
            if pending.request.kind=='end-turn' or pending.request.kind=='deployment-confirm' then
                local base=witness();if self.stopped then return end
                local restored=o.resetTurn and o.resetTurn.comparable and o.resetTurn.comparable(o.capture(),o.json) or base
                self.resetBase={turn=self.turn,phase=self.phase,witness=base,restoreWitness=restored};self.resetAction=false
            elseif pending.request.kind=='reset-turn' then move.usedPawns={};self.resetAction=false
            elseif pending.request.kind=='lab-punch' or pending.request.kind=='basic-attack' or pending.request.kind=='repair' then self.resetAction=true end
            self.revision=self.revision+1
            if pending.request.kind=='move' then
                local r=pending.request
                undoMoves[#undoMoves+1]={peer=pending.peer,actor=r.actor,revision=self.revision,phase=self.phase,turn=self.turn,
                    fromX=r.fromX,fromY=r.fromY,toX=r.toX,toY=r.toY,witness=r.witness}
            elseif pending.request.kind=='undo-move' then
                table.remove(undoMoves)
                move.usedPawns[registry[pending.request.actor].pawnId]=nil
            else
                -- Normal stock attacks/Repair commit preceding moves. Phase
                -- transitions and Reset also start a new native Undo history.
                undoMoves={}
            end
            pending.status='observed'; pending.revision=self.revision
            emit('command_observed',{id=pending.request.id,revision=self.revision,proofOfQuiescence=false,proofOfPeerAgreement=false})
            pending=nil; observed=false; move.armed=false
        elseif pending and not move.pending and not attack.pending and not (reset and reset.pending) and not (undo and undo.pending) and not (ending and ending.pending) and not (deployment and deployment.pending) then
            self:stop('missing-completion-evidence')
        end
    end
    function self:phaseEvent(name,mission)
        if self.stopped then return end
        if deployment and pending and pending.request.kind=='deployment-confirm' then
            local ok,why=pcall(function()deployment:phaseEvent(name,mission)end)
            if not ok then self:stop('deployment-phase:'..tostring(why)) end
            return
        end
        if not pending or pending.request.kind~='end-turn' then self:stop('unrequested-phase-transition');return end
        local ok=pcall(function() ending:phaseEvent(name,mission) end)
        if not ok then self:stop('phase-hook-exception') end
    end
    function self:beginTerminal(mission)
        if self.stopped or self.terminal or not o.repeatedTurns or not pending or pending.request.kind~='end-turn'
            or not ending or not ending.beginTerminal or not health() then return false end
        if not ending:beginTerminal(mission) then return false end
        self.terminal={id=pending.request.id,revision=self.revision,phase=self.phase}
        ready={};emit('command_terminal_pending',self.terminal);return not self.stopped
    end
    function self:finishTerminal()
        assert(not self.stopped and self.terminal and pending and pending.request.id==self.terminal.id,'terminal-command-missing')
        assert(o.guardHealthy(),'terminal-protection-lost')
        self.revision=self.revision+1;pending.status='observed';pending.revision=self.revision
        emit('command_observed',{id=pending.request.id,revision=self.revision,terminal=true,proofOfPeerAgreement=false})
        pending=nil;self.terminal.completed=true
    end
    function self:draw() if self.terminal then return end;if attack.draw then attack:draw() end;if reset then reset:draw() end;if undo then undo:draw() end;if ending then ending:draw() end;if deployment then deployment:draw() end end
    function self:missionUpdate() if self.terminal then return end;if attack.missionUpdate then attack:missionUpdate() end;if reset then reset:missionUpdate() end;if undo then undo:missionUpdate() end;if ending then ending:missionUpdate() end;if deployment then deployment:missionUpdate() end end
    function self:deploymentEvent(name,id)
        if not deployment or self.stopped then return end
        if not pending or (pending.request.kind~='deploy' and pending.request.kind~='deployment-confirm') then self:stop('unrequested-deployment-transition');return end
        local ok,why=pcall(function()deployment:event(name,id)end)
        if not ok then self:stop('deployment-hook:'..tostring(why)) end
    end
    function self:setBlocked(value) move.blocked=value;if reset then reset.blocked=value end;if ending then ending.blocked=value end end
    function self:skillEvent(kind,pawn,weapon)
        if self.stopped then return end
        local ok=pcall(function() move:skillEvent(kind,pawn,weapon); attack:skillEvent(kind,pawn,weapon);if undo then undo:skillEvent() end;if reset then reset:skillEvent() end end)
        if not ok then self:stop('hook-exception') end
    end
    function self:undoEvent(mission,pawn,previous)
        if self.stopped then return end
        local ok,why=pcall(function()
            assert(undo and pending and pending.request.kind=='undo-move','unrequested-undo')
            undo:event(mission,pawn,previous)
        end)
        if not ok then self:stop('undo-hook:'..tostring(why)) end
    end
    function self:resetModLoad()
        if self.stopped or not reset or not pending or pending.request.kind~='reset-turn' then return false end
        local ok,why=pcall(function()return reset:modLoad()end)
        if not ok then self:stop('reset-mod-load:'..tostring(why));return false end
        return true
    end
    function self:resetLoadEvent(stage)
        if not pending or pending.request.kind~='reset-turn' or self.stopped then return end
        local ok,why=pcall(function()reset:loadEvent(stage)end)
        if not ok then self:stop('reset-load-event:'..tostring(why)) end
    end
    function self:resetEvent(mission)
        if self.stopped then return end
        local ok,why=pcall(function()
            assert(reset and pending and pending.request.kind=='reset-turn','unrequested-reset')
            reset:event(mission)
        end)
        if not ok then self:stop('reset-hook:'..tostring(why)) end
    end
    function self:resetContext(event,mission,old)
        if not reset or not pending or pending.request.kind~='reset-turn' or self.stopped then return false end
        local ok,handled=pcall(function()return reset:context(event,mission,old)end)
        if not ok then self:stop('reset-context:'..tostring(handled));return false end
        return handled
    end
    -- Persistence boundary intentionally has no restore operation in this non-resumable experiment.
    function self:checkpoint() return nil,'unsupported-non-resumable-experiment' end
    return self
end
return M
