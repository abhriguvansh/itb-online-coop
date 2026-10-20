-- Restricted native placement for the observed stock Mission_Tides deployment.
-- No pawn relocation, save edits, allowances or deployment-state writes.
local M={}
local types={[0]='PunchMech',[1]='TankMech',[2]='ArtiMech'}
local function same(a,b)return a and b and a.x==b.x and a.y==b.y end
function M.capture(env,state,json)
    local m=assert(env.GetCurrentMission(),'deployment-mission-missing')
    local d=assert(m.deployment,'deployment-data-missing')
    local mechs=json.array()
    for id=0,2 do
        local p=assert(env.Board:GetPawn(id),'deployment-pawn-missing');local v=p:GetSpace()
        mechs[#mechs+1]={id=id,type=p:GetType(),x=v.x,y=v.y,state=assert(d[id]).state}
    end
    state.deployment={inProgress=d.in_progress==true,phase=d.phase,mechs=mechs}
    return state
end
function M.new(env,native,emit,capture,json,phaseSettled)
    local self={status='Deployment off',releases=0,draws=0,updates=0}
    self.releaseHook=env.sdl.eventHook(function(e)
        if self.pending and e:type()==env.sdl.events.mousebuttonup and e:mousebutton()==1 then self.releases=self.releases+1 end
        return false
    end)
    local function healthy()
        local n=native.info()
        assert(n.guardActive and n.sessionState==1 and not n.releaseFailed,'deployment-protection-lost')
        return n
    end
    local function context(transition)
        assert(env.Profile and env.Profile.visible_name=='ITB_Coop_Probe' and env.modApi:getCurrentProfile()~='','wrong-profile')
        assert(env.modApi:getGameVersion()=='1.2.93','wrong-game-version')
        assert(env.sdlext.isGame() and not env.sdlext.isConsoleOpen(),'not-deployment-ui')
        assert(env.GetCurrentMission().ID=='Mission_Tides','wrong-deployment-context')
        if not transition then
            assert(env.Game:GetTurnCount()==0 and env.Game:GetTeamTurn()==env.TEAM_ENEMY,'wrong-deployment-context')
            assert(env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(),'not-placement-phase')
        else assert(env.Game:GetTurnCount()<=1,'unexpected-initial-turn') end
        assert(env.screen:w()==1920 and env.screen:h()==1081 and env.GetBoardScale()==3,'uncalibrated-deployment-layout')
        local state,idle=capture();assert((transition or idle) and #state.unavailable==0,'deployment-board-not-idle')
        return state,idle
    end
    local function validate(c)
        healthy();local state=context()
        if c and c.launch==true then
            for id=0,2 do
                local p=env.Board:GetPawn(id)
                assert(p:GetType()==types[id] and env.Board:IsValid(p:GetSpace()) and not p:IsBusy()
                    and env.GetCurrentMission().deployment[id].state==2,'squad-not-placed')
            end
            assert(env.modApi.deployment:getSelected()==nil,'deployment-selection-active')
            return state
        end
        assert(type(c)=='table' and types[c.pawnId] and c.from.x==-1 and c.from.y==-1,'invalid-placement')
        local p=env.Board:GetPawn(c.pawnId)
        assert(p:GetType()==types[c.pawnId] and same(p:GetSpace(),c.from) and not p:IsDead() and not p:IsBusy(),'actor-not-unplaced')
        assert(env.modApi.deployment:getSelected()==c.pawnId,'native-deployment-selection-mismatch')
        for id=0,c.pawnId-1 do assert(env.GetCurrentMission().deployment[id].state==2,'placement-order') end
        local to=env.Point(c.to.x,c.to.y);assert(env.Board:IsValid(to),'invalid-tile')
        local zone=false
        for _,v in ipairs(env.modApi.deployment:getDeploymentZone()) do if same(v,to) then zone=true end end
        assert(zone,'outside-deployment-zone')
        local terrain=env.Board:GetTerrain(to)
        assert((terrain==env.TERRAIN_ROAD or terrain==env.TERRAIN_FOREST) and env.Board:GetItem(to)==''
            and not env.Board:GetPawn(to) and not env.Board:IsBlocked(to,p:GetPathProf()),'unsupported-deployment-tile')
        for _,method in ipairs({'IsFire','IsAcid','IsSmoke','IsFrozen','IsSpawning','IsPod','IsCracked','IsEnvironmentDanger','IsDangerous','IsDangerousItem'}) do
            assert(env.Board[method](env.Board,to)==false,'unsafe-deployment-tile:'..method)
        end
        return state
    end
    function self:arm(c)
        if self.fault or self.pending then return false end
        local ok,why=pcall(validate,c);self.armed=ok;self.status=ok and 'Placement ready' or tostring(why);return ok
    end
    local function center(to)
        local scale=env.GetBoardScale();local origin,_,_,tw,th=env.getScreenRefs(scale)
        local p={x=math.floor(origin.x+tw*scale*(to.x-to.y)+.5),y=math.floor(origin.y+th*scale*(to.x+to.y+1)+.5)+34}
        assert(same(env.screenPointToTile(p,false),to) and p.x>=350 and p.x<=1580 and p.y>=150 and p.y<=975,'placement-coordinate-refused')
        return p
    end
    function self:request(c)
        assert(self.armed and not self.pending,'placement-not-armed');self.armed=false
        local before=validate(c);local p=c.launch and {x=170,y=228} or center(c.to)
        self.pending={command=c,before=before,witness=json.encode(before),point=p,stage='approach',since=env.modApi:elapsedTime(),draw=self.draws,update=self.updates}
        self.eventSeen=false
        if c.launch then self.landing={started=false,landing={},landed={},ended=false,step=0,mission=env.GetCurrentMission()} end
        assert(native.begin(),'deployment-native-begin-failed')
        assert(native.aim(p.x+4,p.y),'deployment-approach-failed')
        emit('deployment_started',{command=c,before=before,pixel=p});return true
    end
    function self:event(name,id)
        if not self.pending then return end
        if self.pending.command.launch then
            local l=self.landing;assert(self.pending.stage=='committed','uncommitted-landing-transition')
            if name=='onLandingPhaseStart' then assert(not l.started,'duplicate-landing-start');l.started=true
            elseif name=='onPawnLanding' then assert(l.started and types[id] and not l.landing[id],'unexpected-landing');l.landing[id]=true
            elseif name=='onPawnLanded' then assert(l.landing[id] and not l.landed[id],'unexpected-landed');l.landed[id]=true
            elseif name=='onDeploymentPhaseEnd' then
                assert(l.started and not l.ended and l.landed[0] and l.landed[1] and l.landed[2],'landing-not-complete');l.ended=true
            else error('unexpected-launch-event:'..name) end
            emit('deployment_landing_event',{name=name,id=id,turn=env.Game:GetTurnCount(),team=env.Game:GetTeamTurn()});return
        end
        if name=='onPawnDeployed' then
            assert(id==self.pending.command.pawnId and not self.eventSeen,'unexpected-deployed-pawn')
            self.eventSeen=true;self.eventDraw=self.draws;self.eventUpdate=self.updates
            emit('deployment_placed_event',{id=id,state=capture()})
        elseif name=='onLandingPhaseStart' or name=='onDeploymentPhaseEnd' or name=='onPawnUndeployed' then
            error('unexpected-deployment-transition:'..name)
        end
    end
    function self:phaseEvent(name,mission)
        local p=self.pending;assert(p and p.command.launch and p.stage=='committed','unrequested-launch-phase')
        local l=self.landing;assert(l.ended and mission==l.mission,'phase-before-landing-completed')
        if name=='onVekSpawnAdded' or name=='onVekSpawnRemoved' then return end
        -- Normal initial entry emits NextTurn twice: before planning, then at
        -- player admission after the turn-zero future-spawn batch. Neither the
        -- first hook nor the end of environment planning is player completion.
        local order={'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned','onNextTurn'}
        assert(order[l.step+1]==name,'unexpected-initial-phase:'..name);l.step=l.step+1
        emit('deployment_initial_phase',{source=name,step=l.step,turn=env.Game:GetTurnCount(),team=env.Game:GetTeamTurn()})
        if l.step==7 then l.draw=self.draws;l.update=self.updates end
    end
    function self:draw()self.draws=self.draws+1 end
    function self:missionUpdate()self.updates=self.updates+1 end
    function self:update()
        local p=self.pending;if not p then return end
        local ok,why=pcall(function()
            local n=healthy();assert(env.modApi:elapsedTime()-p.since<(p.command.launch and 60000 or 15000),'deployment-timeout')
            if p.stage=='approach' or p.stage=='aim' then
                assert(json.encode(validate(p.command))==p.witness,'deployment-precondition-changed')
                if self.draws<=p.draw then return end
                if p.stage=='approach' then
                    assert(native.aim(p.point.x,p.point.y),'deployment-aim-failed');p.stage='aim';p.draw=self.draws;return
                end
                assert(n.mouseX==p.point.x and n.mouseY==p.point.y and not n.pressed,'deployment-cursor-moved')
                -- Reserve before the sole native click. A failure never authorizes a retry.
                p.stage='committed';p.release=self.releases
                emit('deployment_native_click',{command=p.command,pixel=p.point})
                assert(native.click(p.point.x,p.point.y),'deployment-click-uncertain');return
            end
            if p.command.launch then
                context(true);local l=self.landing
                if not l.ended or l.step~=7 or self.releases<=p.release or n.pressed or self.draws<=l.draw or self.updates<=l.update then return end
                if not phaseSettled or not phaseSettled(0) then return end
                local after,idle=context(true)
                if not idle or env.Board:GetBusyState()~=0 or (env.modApi.runLaterQueue and next(env.modApi.runLaterQueue)) then return end
                assert(env.Game:GetTurnCount()==1 and env.Game:GetTeamTurn()==env.TEAM_PLAYER,'initial-player-phase-missing')
                assert(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(),'landing-still-active')
                local count=0;for _,v in ipairs(after.pawns) do if v.team==env.TEAM_PLAYER then
                    assert(types[v.localId] and v.dead==false and v.frozen==false and v.active==true and v.movementSpent==false,'initial-allowance-not-ready');count=count+1
                end end
                assert(count==3,'initial-friendly-inventory')
                native.finish();self.pending=nil
                emit('deployment_launch_observed',{after=after,landingEvents=true,phaseHooks=7,spawnBatchAcknowledged=true,releaseObserved=true,laterUpdate=true,laterDraw=true,proofOfGeneralQuiescence=false});return
            end
            if not self.eventSeen or self.releases<=p.release or n.pressed or self.draws<=self.eventDraw or self.updates<=self.eventUpdate then return end
            local after=context();local c=p.command
            assert(same(env.Board:GetPawn(c.pawnId):GetSpace(),c.to) and env.GetCurrentMission().deployment[c.pawnId].state==2,'deployment-location-mismatch')
            for _,before in ipairs(p.before.pawns) do
                local found
                for _,v in ipairs(after.pawns) do if v.localId==before.localId then found=v;break end end
                assert(found,'deployment-pawn-missing-after')
                if before.localId~=c.pawnId then assert(json.encode(found)==json.encode(before),'deployment-other-pawn-changed')
                else
                    local expected={};for k,v in pairs(before) do expected[k]=v end;expected.position={x=c.to.x,y=c.to.y}
                    assert(json.encode(found)==json.encode(expected),'deployment-bookkeeping-changed')
                end
            end
            assert(after.gridPower==p.before.gridPower and json.encode(after.tiles)==json.encode(p.before.tiles),'deployment-board-changed')
            native.finish();self.pending=nil
            emit('deployment_postconditions_observed',{command=c,after=after,placementEvent=true,releaseObserved=true,laterDraw=true,laterUpdate=true})
        end)
        if not ok then self.fault=true;self.pending=nil;native.sessionStop();native.finish();emit('deployment_failed',{reason=tostring(why)}) end
    end
    return self
end
return M
