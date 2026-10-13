-- Explicitly opted-in local four-command test. Peer intent is scripted, not network input.
local M={}
function M.install(env,mod,native,path)
    local json=require(path..'json')
    local function capture() return require(path..'snapshot').capture(env,env.GetCurrentMission(),json) end
    local function emit(k,p) mod.probe:record(k,p) end
    local self={status='Protected phase sequence',used=false}
    local function witness() local state=capture();assert(#state.unavailable==0,'incomplete-observation');return json.encode(state) end
    local function request(kind,id,actor,fx,fy,tx,ty)
        return {session='local-phase-proof',encounter='artillery-checkpoint',phase=self.session.phase,
            revision=self.session.revision,witness=witness(),id=id,kind=kind,actor=actor,
            fromX=fx,fromY=fy,toX=tx,toY=ty,confirmUnused=kind=='end-turn' and true or nil}
    end
    local function check(value,reason) assert(value,reason) end
    local function start()
        check(not self.used and not mod.movement.armed and not mod.movement.pending
            and not mod.attack.armed and not mod.attack.pending and not mod.inputGate.active,'other-diagnostic-active')
        check(mod.movement:profileAllowed() and env.Game:GetTurnCount()==2,'checkpoint-required')
        local state,idle=capture();check(idle and state.gridPower==4,'checkpoint-not-ready')
        for _,p in ipairs(state.pawns) do
            if p.localId==2 then check(p.position.x==0 and p.position.y==3 and p.health==2 and not p.movementSpent,'artillery-checkpoint-required') end
        end
        mod.movement:lockInput('protected')
        self.used=true;mod.movement.sessionOwned=true
        self.session=require(path..'command_session').new({env=env,session='local-phase-proof',encounter='artillery-checkpoint',
            phase='player2',players={'host','guest'},entities={combat={pawnId=0,owner='host',commandable=true},
                cannon={pawnId=1,owner='guest',commandable=true},artillery={pawnId=2,owner='guest',commandable=true},
                missionAlly={pawnId=100,owner='host',commandable=true}},movement=require(path..'movement'),
            attack=require(path..'attack'),endTurn=require(path..'end_turn'),native=native,bridge=mod.movement.bridge,
            gate=mod.inputGate,capture=capture,json=json,witness=witness,
            guardHealthy=function() local n=native.info();return n.sessionState==1 and n.guardActive and not n.releaseFailed end,
            stopProtection=function() native.sessionStop();native.finish() end,emit=emit})
        self.stage=0;self.status='Running protected phase sequence'
        emit('phase_lab_started',{scriptedPeers=true,networked=false,state=state})
    end
    local function advance()
        local s=self.session
        if s.stopped then self.status='Stopped: '..tostring(s.reason)..' - Esc exits';return end
        s:update()
        if s.stopped then return end
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
    env.modApi.events.onMissionUpdate:subscribe(function() if self.session then self.session:missionUpdate() end end)
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
                and env.GetCurrentMission() and env.GetCurrentMission().ID=='Mission_Artillery'
            self.button:caption(self.status)
            if self.startAt and env.modApi:elapsedTime()>=self.startAt then self.startAt=nil;start() end
            if self.session and not self.done then self.session:draw();advance() end
        end)
        if not ok then
            self.status='Sequence stopped - Esc exits';self.done=true
            if self.session then self.session:stop('phase-lab:'..tostring(err)) else native.sessionStop();native.finish() end
            emit('phase_lab_failed',{reason=tostring(err)})
        end
    end)
    for _,name in ipairs({'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawnAdded','onVekSpawnRemoved',
            'onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned'}) do
        local event=name
        env.modApi.events[event]:subscribe(function(mission)
            if not self.session or self.done then return end
            self.session:phaseEvent(event,mission)
            if self.ending and not self.session.stopped then
                local ok,err=pcall(function()
                    self.phaseProbe=(self.phaseProbe or 0)+1
                    local r=request('move','during-'..event..'-'..self.phaseProbe,'cannon',1,5,0,3)
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
    for _,name in ipairs({'onMissionChanged','onMissionEnd','onGameExited','onProfileChanged'}) do
        local event=name
        env.modApi.events[event]:subscribe(function() if self.session then self.session:stop('context:'..event) end end)
    end
    env.modApi.events.onWindowShown:subscribe(function() if self.session then self.session:setBlocked(true);self.session:stop('unexpected-window') end end)
    return self
end
return M
