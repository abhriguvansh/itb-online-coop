-- Opt-in checkpoint/deployment experiments with the ordered TCP mailbox.
local M={}
local unpack=unpack or table.unpack
-- Bounded observation only: preserve the native RNG results and call count.
function M.traceSpawns(env,active,emit,array,onError)
    local original=env.Mission.NextPawn
    env.Mission.NextPawn=function(mission,...)
        if not active() then return original(mission,...) end
        local random=env.random_int;local calls=array();local count=0
        env.random_int=function(limit)
            local value=random(limit);count=count+1
            if count<=128 then calls[#calls+1]={limit=limit,value=value} end
            return value
        end
        local function pack(...) return {n=select('#',...),...} end
        local result=pack(pcall(original,mission,...))
        env.random_int=random
        local recorded,why=pcall(emit,'spawn_random_observed',{calls=calls,count=count,complete=count<=128,success=result[1]})
        -- Logging must never suppress the native pawn return/spawn. Latch protection.
        if not recorded then onError(tostring(why)) end
        if not result[1] then error(result[2]) end
        return unpack(result,2,result.n)
    end
end
function M.install(env,mod,native,path)
    local json=require(path..'json')
    local wire
    local deploymentModule=require(path..'deployment')
    local function capture()
        local state,idle=require(path..'snapshot').capture(env,env.GetCurrentMission(),json)
        if wire and wire.deployment then
            deploymentModule.capture(env,state,json)
            state.initialChoices=mod.initialChoices and mod.initialChoices.choices
        end
        return state,idle
    end
    local function emit(k,p) mod.probe:record(k,p) end
    wire=require(path..'phase_wire').open(env,json,emit)
    local self={status=wire and 'Network phase proof' or 'Protected phase sequence',used=false,
        identity=wire and wire.session or 'local-phase-proof'}
    self.resultTrace=require(path..'mission_completion').observe(env,emit,json,native)
    if wire and wire.repeatedTurns then
        self.result=require(path..'mission_completion').runtime({env=env,native=native,json=json,wire=wire,
            session=function() return self.session end,capture=capture,emit=emit})
        wire.result=self.result
    end
    function self:context(event,mission,detail)
        if event=='onMissionChanged' or event=='onGameExited' or event=='onProfileChanged' then self.freshDeployment=false end
        if event=='onMissionEnd' and mod.movement:profileAllowed() then self.resultTrace:begin(mission,detail) end
        if not self.session then return false end
        local ok,handled=pcall(function()
            if self.result and event=='onMissionEnd' and self.session:beginTerminal(mission) then
                self.result:start(mission,detail);return true
            end
            if self.result and self.result:context(event,mission,detail) then return true end
            return false
        end)
        if ok and handled then return true end
        self.session:stop(ok and 'context:'..event or 'result-context:'..tostring(handled))
        return false
    end
    if wire and (wire.repeatedTurns or wire.deployment) then
        self.spawns=require(path..'spawn_sync').install({env=env,wire=wire,json=json,native=native,
            session=function() return self.session end,capture=capture,emit=emit,
            resultPreview=function(mission) return self.result and self.result:allowsPreview(mission) end})
    end
    local function witness() local state=capture();assert(#state.unavailable==0,'incomplete-observation');return json.encode(state) end
    local function request(kind,id,actor,fx,fy,tx,ty,rejectionProbe)
        return {session=self.identity,encounter='artillery-checkpoint',phase=self.session.phase,
            revision=self.session.revision,witness=rejectionProbe and 'unadmittable-phase-rejection-probe' or witness(),id=id,kind=kind,actor=actor,
            fromX=fx,fromY=fy,toX=tx,toY=ty,confirmUnused=kind=='end-turn' and true or nil,
            confirmDeployment=kind=='deployment-confirm' and true or nil}
    end
    local function planned()
        local n=self.session.revision
        if wire and wire.deployment then
            if self.session.phase=='deployment' and n==3 then return request('deployment-confirm','deployment-confirm-3'),'host' end
            if wire.fullMission and self.session.phase~='deployment' then return request('end-turn','end-turn-'..n),'host' end
            if self.session.phase=='player1' then local p=env.Board:GetPawn(1):GetSpace();return request('move','deployment-move-context','cannon',p.x,p.y,1,6),'guest' end
            return request('deploy','deployment-context','combat',-1,-1,1,4),'host'
        end
        if wire and wire.repeatedTurns then return request('end-turn','end-turn-'..n),'host' end
        if n==0 then return request('move','artillery','artillery',0,3,1,1),'guest'
        elseif n==1 then return request('lab-punch','punch','combat',3,3,2,3),'host'
        elseif n==2 then return request('end-turn','end-turn'),'host'
        elseif n==3 then return request('move','cannon-next','cannon',1,5,0,3),'guest'
        else return request('complete','complete'),'host' end
    end
    local function check(value,reason) assert(value,reason) end
    if wire and wire.interactive then
        if not wire.deployment or wire.fullMission then self.inspection=require(path..'inspection').new({env=env,native=native,wire=wire,capture=capture,json=json,emit=emit}) end
        self.intent=require(path..'move_intent').new({env=env,native=native,wire=wire,request=request,emit=emit,inspection=self.inspection})
        self.status=wire.phaseRun and 'Interactive co-op phase' or 'Interactive co-op moves'
    end
    local function start()
        check(not self.used and not mod.movement.armed and not mod.movement.pending
            and not mod.attack.armed and not mod.attack.pending and not mod.inputGate.active,'other-diagnostic-active')
        local finalCheckpoint=wire and wire.terminalCheckpoint
        local deploying=wire and wire.deployment
        check(mod.movement:profileAllowed() and env.Game:GetTurnCount()==(deploying and 0 or finalCheckpoint and 4 or 2),'checkpoint-required')
        local state,idle=capture();check(idle and state.gridPower==(deploying and 2 or finalCheckpoint and 1 or 4),'checkpoint-not-ready')
        if deploying then
            check(mod.initialChoices and mod.initialChoices.healthy and mod.initialChoices:healthy(),'initial-choice-bootstrap-incomplete')
            check(self.freshDeployment==true,'fresh-deployment-entry-required')
            check(env.GetCurrentMission().ID=='Mission_Tides' and env.Game:GetTeamTurn()==env.TEAM_ENEMY
                and state.deployment.inProgress and state.deployment.phase==0 and env.sdlext.isGame() and not env.sdlext.isConsoleOpen(),'deployment-checkpoint-required')
            for _,p in ipairs(state.deployment.mechs) do check(p.x==-1 and p.y==-1,'unplaced-squad-required') end
        elseif finalCheckpoint then
            local f=assert(env.io.open('C:/ITBCoopProbe/terminal-checkpoint.txt','rb'),'terminal-checkpoint-witness-missing')
            local expected=f:read(65537);f:close();check(#expected<=65536 and json.encode(state)==expected,'terminal-checkpoint-witness-mismatch')
        else
            for _,p in ipairs(state.pawns) do
                if p.localId==2 then check(p.position.x==0 and p.position.y==3 and p.health==2 and not p.movementSpent,'artillery-checkpoint-required') end
            end
        end
        if deploying then mod.movement.bridge:startSession() else mod.movement:lockInput('protected') end
        self.used=true;mod.movement.sessionOwned=true
        self.session=require(path..'command_session').new({env=env,session=self.identity,encounter='artillery-checkpoint',
            phase=deploying and 'deployment' or finalCheckpoint and 'player4' or 'player2',players={'host','guest'},entities={combat={pawnId=0,owner='host',commandable=true},
                cannon={pawnId=1,owner='guest',commandable=true},artillery={pawnId=2,owner='guest',commandable=true},
                missionAlly={pawnId=100,owner='host',commandable=true}},movement=require(path..'movement'),
            attack=require(path..(wire and wire.repeatedTurns and 'basic_attack' or 'attack')),undoMove=require(path..'undo_move'),endTurn=require(path..'end_turn'),native=native,bridge=mod.movement.bridge,
            gate=mod.inputGate,capture=capture,json=json,witness=witness,repeatedTurns=wire and wire.repeatedTurns,terminalCheckpoint=finalCheckpoint,
            deployment=deploying and deploymentModule or nil,fullMission=wire and wire.fullMission,
            phaseSettled=self.spawns and function(turn) return self.spawns:settled(turn) end or nil,
            guardHealthy=function() local n=native.info();return n.sessionState==1 and n.guardActive and not n.releaseFailed end,
            stopProtection=function() native.sessionStop();native.finish() end,emit=emit})
        self.stage=0;self.status='Running protected phase sequence'
        if wire then wire:arm(planned());self.status='Waiting for network peer' end
        emit('phase_lab_started',{scriptedPeers=not (wire and wire.interactive),networked=wire~=nil,state=state})
    end
    local function advance()
        local s=self.session
        if s.stopped then
            self.status='Stopped: '..tostring(s.reason)..' - Esc exits'
            if self.intent then self.intent:update(s,false) end
            if wire and not self.stopSent then self.stopSent=true;wire:send({type='stopped',reason=tostring(s.reason)}) end
            return
        end
        s:update()
        if s.stopped then return end
        if wire then
            self.status='Network phase proof: revision '..s.revision
            if wire:tick(s,planned,native) then
                emit('phase_lab_completed',{state=not s.terminal and capture() or nil,terminal=s.terminal~=nil,
                    revision=s.revision,native=native.info(),networked=true,fullStateProof=false})
                self.status='Network sequence passed - Esc exits';self.done=true
                native.sessionStop();native.finish()
            end
            if self.intent and not s.terminal then self.status=self.intent:update(s,self.done) end
            if s.terminal and not self.done then self.status=self.result:status() end
            return
        end
        if s.revision~=self.stage then return end
        local r,peer
        if self.stage==0 then r=request('move','artillery','artillery',0,3,1,1);peer='guest'
        elseif self.stage==1 then r=request('lab-punch','punch','combat',3,3,2,3);peer='host'
        elseif self.stage==2 then
            r=request('end-turn','end-turn');peer='host'
            check(s:submit('intruder',r).reason=='unknown-peer','unauthorized-dispatched')
            local unready=request('end-turn','unready')
            check(s:submit('host',unready).reason=='both-players-must-be-ready','unready-dispatched')
            check(s:setReady('host',r.phase,r.revision,r.witness,true),'host-not-ready')
            check(s:setReady('guest',r.phase,r.revision,r.witness,true),'guest-not-ready')
        elseif self.stage==3 then r=request('move','cannon-next','cannon',1,5,0,3);peer='guest'
        elseif self.stage==4 then
            emit('phase_lab_completed',{state=capture(),revision=s.revision,native=native.info(),networked=false})
            self.status='Phase sequence passed - Esc exits';self.done=true
            native.sessionStop();native.finish();return
        end
        check(s:submit(peer,r).status=='pending','command-not-admitted')
        check(s:submit(peer,r).status=='duplicate','duplicate-not-blocked')
        if r.kind=='end-turn' then
            local conflict={};for k,v in pairs(r) do conflict[k]=v end;conflict.witness='conflict'
            check(s:submit(peer,conflict).reason=='request-id-conflict','conflict-not-blocked')
            self.ending=true
        end
        self.stage=self.stage+1
    end
    env.modApi.events.onMissionUpdate:subscribe(function()
        if self.session then
            self.session:missionUpdate()
            if self.inspection and not self.done then
                local ok,why=pcall(function()self.inspection:mark(self.session)end)
                if not ok then self.session:stop('inspection-mark:'..tostring(why)) end
            end
        end
    end)
    env.modApi.events.onFrameDrawStart:subscribe(function()
        if not self.button then
            local root=env.sdlext.getUiRoot();if not root then return end
            self.button=env.Ui():pospx(8,828):widthpx(360):heightpx(36):caption(self.status)
                :decorate({env.DecoButton(),env.DecoAlign(0,2),env.DecoCaption()}):addTo(root)
            self.button.onclicked=function(_,b)
                if b==1 and not self.used then self.startAt=env.modApi:elapsedTime()+300 end
                return true
            end
        end
        local ok,err=pcall(function()
            self.button.visible=mod.movement:profileAllowed() and env.sdlext.isGame()
                and env.GetCurrentMission() and env.GetCurrentMission().ID==(wire and wire.deployment and 'Mission_Tides' or 'Mission_Artillery')
            self.button:caption(self.status)
            if self.startAt and env.modApi:elapsedTime()>=self.startAt then self.startAt=nil;start() end
            if mod.movement:profileAllowed() then self.resultTrace:draw() end
            if self.session and not self.done then self.session:draw();advance() end
            if self.intent then self.intent:draw(env.sdlext.getUiRoot(),self.session~=nil and self.button.visible) end
        end)
        if not ok then
            self.status='Sequence stopped - Esc exits';self.done=true
            if self.session then self.session:stop('phase-lab:'..tostring(err)) else native.sessionStop();native.finish() end
            emit('phase_lab_failed',{reason=tostring(err)})
            if wire then pcall(function() wire:send({type='stopped',reason=tostring(err)}) end) end
        end
    end)
    for _,name in ipairs({'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawnAdded','onVekSpawnRemoved',
            'onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned'}) do
        local event=name
        env.modApi.events[event]:subscribe(function(mission,spawn)
            if not self.session or self.done then return end
            if event=='onVekSpawnAdded' and spawn then
                emit('spawn_choice_observed',{type=spawn.type,id=spawn.id,turns=spawn.turns,
                    location=spawn.location and {x=spawn.location.x,y=spawn.location.y}})
            end
            self.session:phaseEvent(event,mission)
            if (self.ending or (wire and wire.ending)) and not self.session.stopped then
                local ok,err=pcall(function()
                    self.phaseProbe=(self.phaseProbe or 0)+1
                    -- This negative probe must reject at the pending-command gate,
                    -- before reading a witness from transitional spawn bookkeeping.
                    -- Its sentinel cannot authorize a real action if that gate regresses.
                    local r=request('move','during-'..event..'-'..self.phaseProbe,'cannon',1,5,0,3,true)
                    local result=self.session:submit('guest',r)
                    check(result.reason=='command-pending-renew-intent' or result.status=='duplicate','phase-admission-opened-early')
                    emit('phase_lab_early_command_rejected',{phaseEvent=event,result=result})
                end)
                if not ok then self.session:stop(tostring(err)) end
            end
        end)
    end
    for _,name in ipairs({'onSkillStart','onSkillEnd'}) do
        local event=name
        env.modapiext.events[event]:subscribe(function(_,pawn,weapon) if self.session then self.session:skillEvent(event,pawn,weapon) end end)
    end
    env.modapiext.events.onPawnUndoMove:subscribe(function(mission,pawn,previous)
        if self.session then self.session:undoEvent(mission,pawn,previous) end
    end)
    env.modapiext.events.onResetTurn:subscribe(function()
        if self.session then self.session:stop('unsupported-reset-turn') end
    end)
    env.modApi.events.onMissionDismissed:subscribe(function(mission) if self.result then self.result:dismissed(mission) end end)
    for _,name in ipairs({'onDeploymentPhaseStart','onPawnSelectedForDeployment','onPawnUnselectedForDeployment','onPawnDeployed','onPawnUndeployed','onLandingPhaseStart','onPawnLanding','onPawnLanded','onDeploymentPhaseEnd'}) do
        local event=name
        env.modApi.events[event]:subscribe(function(id)
            if event=='onDeploymentPhaseStart' then self.freshDeployment=true end
            if mod.movement:profileAllowed() and env.GetCurrentMission() and env.GetCurrentMission().ID=='Mission_Tides' then
                local ok,state=pcall(function()return deploymentModule.capture(env,capture(),json)end)
                emit('deployment_event',{name=event,id=id,state=ok and state or nil,error=not ok and tostring(state) or nil})
            end
            if self.session and not self.done and wire and wire.deployment then self.session:deploymentEvent(event,id) end
        end)
    end
    env.modApi.events.onWindowShown:subscribe(function()
        if self.session and not (self.result and self.result:windowAllowed()) then self.session:setBlocked(true);self.session:stop('unexpected-window') end
    end)
    return self
end
return M
