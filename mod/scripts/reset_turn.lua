-- Restricted native Reset: one normal shared allowance, fresh unanimous consent.
-- Session history remains in process memory while the engine reloads its turn save.
local M={}
-- Normal native Reset rehydrates non-damageable road HP differently. Keep raw
-- peer witnesses intact; only turn-restoration comparison excludes this field.
function M.comparable(state,json)
    local copy={};for k,v in pairs(state)do copy[k]=v end
    if state.tiles then
        copy.tiles=json.array()
        for _,tile in ipairs(state.tiles)do
            local t={};for k,v in pairs(tile)do t[k]=v end
            if t.terrain==0 and t.building==false then t.health=nil end
            copy.tiles[#copy.tiles+1]=t
        end
    end
    return json.encode(copy)
end
function M.saved(env,index,undo)
    local path
    if undo then
        local profile=env.modApi:getCurrentProfile();assert(profile:match('^[%w_-]+$'),'unsafe-reset-profile')
        path=env.GetSavedataLocation()..'profile_'..profile..'/undoSave.lua'
    end
    local data=env.ReadSaveData(path)
    if undo then assert(data.GameData and data.GameData.undosave==true,'native-turn-save-required') end
    local region=assert(data.RegionData and data.RegionData['region'..index],'reset-saved-region-missing')
    local p=assert(region.player,'reset-saved-player-missing')
    assert(type(p.iUndoTurn)=='number' and p.iUndoTurn%1==0 and p.iUndoTurn>=0 and p.iUndoTurn<=2,'reset-allowance-unavailable')
    assert(type(p.sMission)=='string' and p.sMission==region.mission,'reset-saved-mission-missing')
    if undo then assert(p.actions==0,'reset-target-not-turn-start') end
    return {region=index,mission=p.sMission,turn=p.iCurrentTurn,team=p.iTeamTurn,remaining=p.iUndoTurn}
end
function M.new(env,native,emit,capture,json)
    local self={armed=false,used=false,fault=false,status='Reset unavailable',frame=0,updates=0,releases=0}
    local function common()
        assert(env.Profile and env.Profile.visible_name=='ITB_Coop_Probe' and env.modApi:getCurrentProfile()~='','wrong-profile')
        assert(env.modApi:getGameVersion()=='1.2.93','wrong-game-version')
        assert(env.screen:w()==1920 and env.screen:h()==1081 and env.GetBoardScale()==3,'uncalibrated-layout')
        local n=native.info();assert(n.guardActive and n.sessionState==1 and not n.releaseFailed,'reset-protection-lost')
        return n
    end
    local function context(c)
        common();assert(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not self.blocked,'not-tactical')
        assert(env.Board and not env.Board:IsTipImage() and env.GetCurrentMission().ID==(self.fullMission and 'Mission_Tides' or 'Mission_Artillery'),'unsupported-reset-context')
        assert(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(),'deployment')
        assert(env.Game:GetTeamTurn()==env.TEAM_PLAYER and env.Game:GetTurnCount()==c.turn,'wrong-phase')
    end
    local function validate(c)
        assert(c and not self.used and not self.pending and not self.fault,'reset-used-or-pending');context(c)
        assert(c.actionObserved==true,'native-action-required-before-reset')
        assert(type(c.restoreWitness)=='string' and #c.restoreWitness>0 and #c.restoreWitness<=65536,'fresh-turn-start-required')
        local state,idle=capture();assert(idle and #state.unavailable==0,'incomplete-or-busy')
        assert(M.comparable(state,json)~=c.restoreWitness,'no-observed-action-to-reset')
        local index=self.fullMission and 1 or 2
        assert(env.RegionData.iBattleRegion==index,'reset-region-changed')
        -- A native attack invalidates saveData.lua. The engine's own undoSave.lua
        -- remains the normal Reset target; read it without forcing a save/effect.
        local saved=M.saved(env,index,true)
        assert(saved.turn==c.turn and saved.team==env.TEAM_PLAYER and saved.remaining==1,'reset-allowance-or-saved-phase-unavailable')
        local selected=env.Board:GetSelectedPawn();assert(not selected or selected:GetArmedWeaponId()<=0,'weapon-armed')
        return saved
    end
    function self:arm(c)
        local ok,why=pcall(validate,c);self.armed=ok;self.command=ok and c or nil
        self.status=ok and 'Reset ready' or tostring(why);return ok
    end
    local function aim(p,x,y,stage)
        assert(native.aim(x,y),'reset-aim-failed');p.x,p.y,p.stage,p.aimedFrame,p.aimedAt=x,y,stage,self.frame,env.modApi:elapsedTime()
    end
    function self:request(c)
        assert(self.armed and self.command==c,'not-armed');local saved=validate(c)
        self.used=true;self.armed=false
        local p={command=c,saved=saved,mission=env.GetCurrentMission(),since=env.modApi:elapsedTime(),startRelease=self.releases}
        self.pending=p;emit('reset_turn_requested',{turn=c.turn,remaining=saved.remaining,confirmation='normal-native-dialog'})
        local ok,why=native.begin();assert(ok,why);aim(p,578,119,'approach-reset');return true
    end
    function self:loading()return self.pending and self.pending.confirmSent==true end
    function self:modLoad()
        local p=self.pending;common();assert(p and p.confirmSent and not p.loadSeen,'unrequested-reset-load')
        p.loadSeen=true;emit('reset_turn_lifecycle',{stage='mod-load'});return true
    end
    function self:loadEvent(stage)
        local p=self.pending;common();assert(p and p.confirmSent and p.loadSeen,'unrequested-reset-load-event')
        if stage=='pre-load' then assert(not p.preSeen and not p.resetSeen,'duplicate-reset-pre-load');p.preSeen=true
        else assert(stage=='post-load' and p.preSeen and p.resetSeen and not p.postSeen,'unexpected-reset-post-load')
            p.postSeen=true;p.postFrame=self.frame;p.postUpdate=self.updates
        end
        emit('reset_turn_lifecycle',{stage=stage})
    end
    function self:event(mission)
        local p=self.pending;common()
        assert(p and p.confirmSent and p.preSeen and not p.resetSeen and mission==p.mission,'unrequested-reset-hook')
        p.resetSeen=true;emit('reset_turn_lifecycle',{stage='reset-hook'})
    end
    function self:context(event,mission,old)
        local p=self.pending
        if not p or not p.confirmSent then return false end
        common()
        assert(event=='onMissionChanged' and p.postSeen and not p.changed and old==p.mission
            and mission and mission~=old and mission.ID==p.mission.ID,'unexpected-reset-context')
        p.changed=true;p.newMission=mission
        emit('reset_turn_lifecycle',{stage='mission-changed'});return true
    end
    function self:skillEvent()assert(not self.pending,'unexpected-skill-during-reset')end
    function self:draw()self.frame=self.frame+1 end
    function self:missionUpdate()self.updates=self.updates+1 end
    if env.sdl then self.releaseHook=env.sdl.eventHook(function(event)
        if self.pending then
            local t=event:type()
            if t==env.sdl.events.mousebuttonup and event:mousebutton()==1 then self.releases=self.releases+1 end
            if t==env.sdl.events.mousebuttondown or t==env.sdl.events.mousebuttonup then
                emit('reset_turn_input_observed',{type=t,button=event:mousebutton(),stage=self.pending.stage,
                    releases=self.releases,elapsed=env.modApi:elapsedTime(),native=native.info()})
            end
        end
        return false
    end) end
    function self:update()
        local p=self.pending;if not p or self.fault then return end
        local ok,why=pcall(function()
            local n=common();assert(env.modApi:elapsedTime()-p.since<15000,'reset-outcome-timeout')
            if p.confirmSent then
                if not p.postSeen or not p.changed or self.frame<=p.postFrame or self.updates<=p.postUpdate then return end
                context(p.command);assert(env.GetCurrentMission()==p.newMission,'reset-mission-changed-again')
                if n.pressed or self.releases<p.startRelease+2 then return end
                local state,idle=capture();assert(#state.unavailable==0,'incomplete-reset-observation')
                if not idle or env.Board:GetBusyState()~=0 or (env.modApi.runLaterQueue and next(env.modApi.runLaterQueue)) then return end
                assert(M.comparable(state,json)==p.command.restoreWitness,'reset-restored-observation-mismatch')
                if env.modApi:elapsedTime()<(p.readAt or 0) then return end
                p.readAt=env.modApi:elapsedTime()+250
                local available,saved=pcall(M.saved,env,p.saved.region)
                if not available or saved.remaining==p.saved.remaining then return end
                assert(saved.mission==p.saved.mission and saved.turn==p.command.turn and saved.team==env.TEAM_PLAYER
                    and saved.remaining==p.saved.remaining-1,'reset-committed-allowance-mismatch')
                emit('reset_turn_postconditions_observed',{turn=p.command.turn,state=state,remaining=saved.remaining,
                    reloadHooks=4,missionChanged=true,laterDraw=true,laterMissionUpdate=true,releaseObserved=true,
                    savedAllowanceObserved=true,restorationExcludes='non-building-road-tile-health',proofOfGeneralQuiescence=false})
                native.finish();self.pending=nil;self.command=nil;self.status='Reset observed';return
            end
            context(p.command);assert(env.GetCurrentMission()==p.mission,'reset-context-changed-before-confirmation')
            assert(env.modApi:elapsedTime()-p.since<4500,'reset-ui-timeout')
            if n.pressed or (p.releaseExpected and self.releases<p.releaseExpected) then return end
            if p.stage=='wait-dialog' then
                local r=env.sdlext.CurrentWindowRect
                if r and r.x==765 and r.y==408 and r.w==390 and r.h==265 then
                    emit('reset_turn_confirmation_observed',{x=r.x,y=r.y,w=r.w,h=r.h});aim(p,894,630,'approach-confirm')
                end
                return
            end
            if self.frame<=p.aimedFrame+1 or env.modApi:elapsedTime()-p.aimedAt<150
                or n.mouseX~=p.x or n.mouseY~=p.y or n.cursorX~=n.mouseX or n.cursorY~=n.mouseY then return end
            if p.stage=='approach-reset' then aim(p,569,119,'click-reset');return end
            if p.stage=='approach-confirm' then aim(p,886,630,'click-confirm');return end
            local confirming=p.stage=='click-confirm'
            assert(confirming or p.stage=='click-reset','unknown-reset-ui-stage')
            if confirming then
                local r=env.sdlext.CurrentWindowRect
                assert(r and r.x==765 and r.y==408 and r.w==390 and r.h==265,'reset-confirmation-changed')
                p.confirmSent=true;p.stage='wait-reload'
            else p.stage='wait-dialog' end
            p.releaseExpected=self.releases+1
            local sent,count=native.click(p.x,p.y)
            emit('reset_turn_click',{action=confirming and 'confirm-reset' or 'open-reset',accepted=sent,events=count,native=native.info()})
            assert(sent,'reset-click-uncertain')
        end)
        if not ok then self.fault=true;emit('reset_turn_failed',{reason=tostring(why)}) end
    end
    return self
end
return M
