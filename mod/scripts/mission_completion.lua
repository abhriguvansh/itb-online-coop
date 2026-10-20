-- Restricted mission-result observations. Never equate the mission-end hook with completion.
local M={}
local function integer(n) return type(n)=='number' and n>=0 and n%1==0 end
function M.saved(env,index,json)
    local data=env.ReadSaveData() -- pinned loader's read-only, isolated save-data reader
    assert(integer(index) and index<20,'unsupported-result-region')
    local region=assert(data.RegionData['region'..index],'result-region-missing')
    local game,squad=data.GameData,data.SquadData
    assert(integer(game.network) and integer(squad.money) and integer(region.state),'result-fields-missing')
    local result={schema='itb-mission-result-v1',coverage='partial-result-only',region=index,
        regionState=region.state,mission=region.mission,grid=game.network,reputation=squad.money,pilots=json.array(),objectives=json.array(),
        victory=region.player and region.player.victory or nil,
        excluded=json.array({'rng','full-campaign-state','civilian-population','cosmetic-dialogue','unobserved-reward-effects'})}
    assert(type(result.mission)=='string','result-mission-missing')
    for id=0,2 do
        local pilot=assert(game.current['pilot'..id],'result-pilot-missing')
        assert(type(pilot.id)=='string' and integer(pilot.exp) and integer(pilot.level),'result-pilot-fields')
        result.pilots[#result.pilots+1]={slot=id,id=pilot.id,experience=pilot.exp,level=pilot.level}
    end
    for i=0,7 do
        local v=region.objectives and region.objectives[tostring(i)]
        if v then
            assert(type(v.text)=='string' and type(v.param1)=='string' and type(v.param2)=='string'
                and integer(v.value) and integer(v.potential) and integer(v.category),'result-objective-fields')
            result.objectives[#result.objectives+1]={slot=i,text=v.text,param1=v.param1,param2=v.param2,
                value=v.value,potential=v.potential,category=v.category}
        end
    end
    return result
end
-- Narrow final-turn boundary for Artillery or opt-in Tides. No campaign admission.
function M.runtime(o)
    local env,native,json,wire=o.env,o.native,o.json,o.wire
    local self={frame=0}
    local function now() return env.modApi:elapsedTime() end
    local function healthy()
        local n=native.info()
        assert(n.guardActive and n.sessionState==1 and not n.releaseFailed,'result-protection-lost')
        assert(env.Profile.visible_name=='ITB_Coop_Probe' and env.modApi:getCurrentProfile()~='','result-profile-changed')
        assert(env.screen:w()==1920 and env.screen:h()==1081,'result-layout-changed')
        return n
    end
    local function send(kind,witness)
        local p=self.pending
        wire:send({type=kind,id=p.context.id,revision=p.context.revision,phase=p.context.phase,witness=witness,native=native.info()})
    end
    local function aim(x,y,stage)
        local p=self.pending;assert(native.aim(x,y),'result-aim-failed')
        p.x,p.y,p.stage,p.aimFrame=x,y,stage,self.frame
    end
    if env.sdl then self.inputHook=env.sdl.eventHook(function(event)
        local p=self.pending
        if p and event:type()==env.sdl.events.mousebuttonup and event:mousebutton()==1 then
            p.releasesSeen=(p.releasesSeen or 0)+1
        end
        if p and p.stage~='retreat' and (p.inputRecords or 0)<24 then
            local t=event:type()
            if t==env.sdl.events.mousemotion or t==env.sdl.events.mousebuttondown or t==env.sdl.events.mousebuttonup then
                p.inputRecords=(p.inputRecords or 0)+1
                local ok=pcall(o.emit,'mission_result_input_observed',{stage=p.stage,type=t,
                    x=env.sdl.mouse.x(),y=env.sdl.mouse.y(),native=native.info()})
                if not ok then o.session():stop('result-input-evidence-failed') end
            end
        end
        return false
    end) end
    env.ITBCoopProtectedMissionTail=function()
        local p=self.pending
        if not p or p.stage~='retreat' then if o.session() then o.session():stop('unexpected-result-tail') end;return end
        local ok,why=pcall(function()
            healthy();assert(env.GetCurrentMission()==p.mission,'result-tail-mission-changed')
            p.tailFrame=self.frame;p.stage='tail'
            o.emit('mission_result_effect_tail',{frame=self.frame,busy=env.Board:GetBusyState(),protected=true})
        end)
        if not ok then o.session():stop('result-tail:'..tostring(why)) end
    end
    function self:start(mission,fx)
        assert(not self.pending and wire.repeatedTurns,'result-overlap')
        healthy();assert(env.RegionData.iBattleRegion==(wire.fullMission and 1 or 2) and mission.ID==(wire.fullMission and 'Mission_Tides' or 'Mission_Artillery'),'unsupported-result-region')
        assert(type(fx.AddScript)=='function','result-effect-missing')
        self.pending={mission=mission,index=wire.fullMission and 1 or 2,context=o.session().terminal,at=now(),stage='retreat'}
        wire.inputReady=false;wire.readyInput=false
        o.emit('mission_result_hook_observed',{protected=true,revision=o.session().revision,proofOfFinalCompletion=false})
        fx:AddScript('ITBCoopProtectedMissionTail()')
    end
    function self:context(event,mission,old)
        local p=self.pending;if not p then return false end
        if event=='onMissionChanged' and mission==nil and old==p.mission and p.stage=='continue-sent' and not env.Board then
            p.changed=true;p.changedAt=now();o.emit('mission_result_dismissal_observed',{source=event});return true
        end
        if event=='onGameExited' and p.stage=='menu-sent' and not env.Board and not env.GetCurrentMission() then
            p.exited=true;o.emit('mission_result_menu_exit_observed',{});return true
        end
        return false
    end
    function self:dismissed(mission)
        local p=self.pending
        if p and p.stage=='continue-sent' and mission==p.mission and not env.Board then
            p.dismissed=true;o.emit('mission_result_dismissal_observed',{source='onMissionDismissed'})
        elseif p then o.session():stop('unexpected-result-dismissal') end
    end
    function self:windowAllowed() local p=self.pending;return p and (p.stage=='gear-sent' or p.stage=='menu-approach' or p.stage=='menu-click') end
    function self:allowsPreview(mission)
        local p=self.pending
        return p and mission~=p.mission and (p.stage=='continue-sent' or p.changed==true)
    end
    function self:receive(m)
        local p=assert(self.pending,'result-message-without-command');healthy()
        assert(m.peer=='-' and m.revision==p.context.revision and m.phase==p.context.phase and m.id==p.context.id,'result-stale-context')
        if m.kind=='RESULTCONTINUE' then
            assert(p.stage=='prepared' and m.witness==p.before and now()-p.preparedAt<90000,'result-continue-not-prepared')
            local state,idle=o.capture()
            assert(idle and #state.unavailable==0 and json.encode(state)==p.before,'result-precondition-changed')
            assert(native.begin(),'result-input-unavailable');aim(1329,803,'continue-approach')
        elseif m.kind=='RESULTDONE' then
            assert(p.stage=='observed' and m.witness==p.after,'result-done-conflict')
            o.session():finishTerminal();p.stage='complete';send('complete',p.after)
            o.emit('mission_result_completed',{revision=o.session().revision,result=p.result,coverage='partial-result-only'})
            return true
        else error('result-message-kind') end
    end
    function self:update()
        self.frame=self.frame+1;local p=self.pending;if not p or p.stage=='complete' then return end
        local n=healthy();assert(now()-p.at<120000,'result-timeout-no-retry')
        -- Worker submission precedes SDL delivery. Do not aim at the next
        -- control while the game's button state still belongs to the last click.
        if p.releaseExpected and (p.releasesSeen or 0)<p.releaseExpected then return end
        if p.stage=='retreat' or p.stage=='prepared' or p.stage=='observed' then return end
        if p.stage=='tail' then
            assert(env.GetCurrentMission()==p.mission and env.Board,'result-tail-context-lost')
            if self.frame<=p.tailFrame+1 or env.Board:GetBusyState()~=0 then return end
            if env.modApi.runLaterQueue and next(env.modApi.runLaterQueue) then return end
            local state,idle=o.capture();assert(#state.unavailable==0,'result-incomplete-observation')
            if not idle then return end
            for _,pawn in ipairs(state.pawns) do assert(pawn.team~=env.TEAM_ENEMY or pawn.dead,'result-enemy-not-retreated') end
            p.stage='await-confirm';p.serial=n.intentSerial
            o.emit('mission_result_retreat_settled',{revision=p.context.revision,state=state});return
        end
        if p.stage=='await-confirm' then
            if n.intentSerial==p.serial then return end
            local contiguous=n.intentSerial==p.serial+1;p.serial=n.intentSerial
            if not contiguous or n.armed or n.pressed or n.intentX<8 or n.intentX>368 or n.intentY<828 or n.intentY>864 then return end
            assert(env.Board and env.GetCurrentMission()==p.mission and env.Board:GetBusyState()==0,'result-confirmation-context-lost')
            local state,idle=o.capture();assert(idle and #state.unavailable==0,'result-confirmation-incomplete')
            p.before=json.encode(state);p.stage='prepared';p.preparedAt=now();send('result_prepared',p.before)
            o.emit('mission_result_prepared',{revision=p.context.revision,state=state,explicitLocalConfirmation=true});return
        end
        if p.stage=='continue-sent' then
            if not p.dismissed or not p.changed or env.Board or env.GetCurrentMission() then return end
            assert(env.modApi:getGameState()=='Island','result-not-on-island')
            if n.pressed then return end
            -- Give the native result transition its normal animation time. This delay
            -- is not completion proof: only the committed result below can finish.
            if now()-p.changedAt<2500 or (env.modApi.runLaterQueue and next(env.modApi.runLaterQueue)) then return end
            native.finish();assert(native.begin(),'result-menu-input-unavailable')
            aim(40,26,'gear-approach');return
        end
        if p.stage=='gear-sent' then
            if n.pressed then return end
            local r=env.sdlext.CurrentWindowRect
            if not r or r.x~=1005 or r.y~=290 or r.w~=275 or r.h~=500 then return end
            o.emit('mission_result_native_menu_observed',{x=r.x,y=r.y,w=r.w,h=r.h})
            aim(812,593,'menu-approach');return
        end
        if p.stage=='menu-sent' then
            if not p.exited or n.pressed or env.modApi:getGameState()~='Main_Menu' then return end
            local result=M.saved(env,p.index,json)
            if result.regionState~=2 or result.mission~='' or #result.objectives~=2 then
                if not p.staleReported then p.staleReported=true;o.emit('mission_result_save_pending',{result=result}) end
                return -- Read-only wait; never repeat Continue or menu actions.
            end
            native.finish();p.result=result;p.after=json.encode(result);p.stage='observed';send('result_observed',p.after)
            o.emit('mission_result_committed_observed',{result=result});return
        end
        if n.pressed or self.frame<=p.aimFrame+1 or n.mouseX~=p.x or n.mouseY~=p.y or n.cursorX~=n.mouseX or n.cursorY~=n.mouseY then return end
        if p.stage=='continue-approach' then aim(1325,803,'continue-click');return end
        if p.stage=='gear-approach' then aim(36,26,'gear-click');return end
        if p.stage=='menu-approach' then aim(808,593,'menu-click');return end
        local nextStage=({['continue-click']='continue-sent',['gear-click']='gear-sent',['menu-click']='menu-sent'})[p.stage]
        assert(nextStage,'result-unknown-stage')
        if p.stage=='menu-click' then
            local r=env.sdlext.CurrentWindowRect;assert(r and r.x==1005 and r.y==290 and r.w==275 and r.h==500,'result-menu-changed')
        end
        local action=p.stage;p.stage=nextStage
        if env.sdl then p.releaseExpected=(p.releasesSeen or 0)+1 end
        local accepted,detail=native.click(p.x,p.y)
        o.emit('mission_result_native_click',{action=action,accepted=accepted,detail=detail})
        assert(accepted,'result-click-uncertain-no-retry')
    end
    function self:status()
        return self.pending and self.pending.stage=='await-confirm' and 'Review results; click here to finish' or 'Protected mission completion; waiting for peer / game'
    end
    return self
end
function M.observe(env,emit,json,native)
    local self={frame=0}
    env.ITBCoopMissionTail=function()
        local p=self.pending;if not p then return end
        p.tail=true;p.tailFrame=self.frame
        emit('mission_result_effect_tail',{frame=self.frame,busy=env.Board and env.Board:GetBusyState()})
    end
    function self:begin(mission,fx)
        if env.os.getenv('ITB_COOP_TERMINAL_TRACE')~='1' then return end
        local index=assert(env.RegionData.iBattleRegion,'result-region-missing')
        self.pending={mission=mission,index=index,at=env.modApi:elapsedTime()}
        emit('mission_result_hook_observed',{region=index,mission=mission.ID,
            saved=M.saved(env,index,json),gameState=env.modApi:getGameState()})
        fx:AddScript('ITBCoopMissionTail()')
    end
    function self:draw()
        self.frame=self.frame+1;local p=self.pending
        if not p or env.modApi:elapsedTime()-p.at>900000 then return end
        local ok,saved=pcall(M.saved,env,p.index,json)
        local n=native.info();local r=env.sdlext.CurrentWindowRect
        local value={tail=p.tail==true,boardPresent=env.Board~=nil,
            missionPresent=env.GetCurrentMission()~=nil,gameState=env.modApi:getGameState(),saved=ok and saved or nil,
            saveUnavailable=not ok,saveReason=not ok and tostring(saved):sub(1,240) or nil,cursor={x=n.mouseX,y=n.mouseY},window=r and {x=r.x,y=r.y,w=r.w,h=r.h} or nil}
        local text=json.encode(value)
        if text~=p.last then p.last=text;emit('mission_result_boundary_observed',value) end
    end
    return self
end
return M
