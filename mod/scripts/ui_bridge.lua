-- Bounded UI submission experiment, not multiplayer input authorization.
local bridge = {}
local function same(a,b) return a and b and a.x==b.x and a.y==b.y end
function bridge.new(env, native, emit)
    local self = { phase = 'off', releasesSeen = 0 }
    -- Timer submission is not SDL delivery. The game can draw after the native
    -- worker submits mouse-up but before SDL has processed that release.
    self.releaseHook=env.sdl.eventHook(function(event)
        if self.phase~='off' and event:type()==env.sdl.events.mousebuttonup and event:mousebutton()==1 then
            self.releasesSeen=self.releasesSeen+1
        end
        return false
    end)
    local function center(tile)
        local scale=env.GetBoardScale()
        -- Empirical lower-tile hit point from the disposable-profile positive control.
        -- Loader roundtrip alone did not establish the native game's clickable point.
        assert(type(scale)=='number' and scale>0 and scale<=8,'unsupported-board-scale')
        local origin,_,_,tw,th=env.getScreenRefs(scale)
        local p={x=math.floor(origin.x+tw*scale*(tile.x-tile.y)+0.5),
            y=math.floor(origin.y+th*scale*(tile.x+tile.y+1)+0.5)+34}
        assert(same(env.screenPointToTile(p,false),tile),'coordinate-roundtrip-failed')
        assert(p.x>=300 and p.x<=1580 and p.y>=150 and p.y<=975,'tile-overlaps-ui-or-edge')
        return p
    end
    local function aim(p,phase)
        -- The loader can consume the first motion while its old button hover is cached.
        -- Leave that button, allow a draw, then deliver a distinct motion over the tile.
        local approach={x=p.x+4,y=p.y}
        self.preview=nil
        local ok,detail=native.aim(approach.x,approach.y);assert(ok,detail)
        self.phase,self.aimedAt='prepare',env.modApi:elapsedTime()
        self.finalPoint,self.finalPhase=p,phase
        self.aimPoint,self.waitLogged=approach,false
    end
    function self:stop(completed)
        if native then
            if completed~=true and native.sessionStop then native.sessionStop() end
            if self.phase~='off' then emit('ui_bridge_guard_result',native.info()) end
            native.finish()
        end
        self.phase='off'
        self.preview=nil
        self.releaseExpected=nil
    end
    function self:startSession(timeoutTest)
        assert(self.phase=='off' and not self.guardWatching and not self.sessionWatching
            and native and native.info().abi=='itb-win32-click-v3','session-unavailable')
        local ok,reason=native.sessionBegin();assert(ok,reason)
        self.sessionWatching=true;self.sessionHeartbeat=not timeoutTest;self.lastSessionState=1
        emit('protected_session_start',native.info())
    end
    function self:pollSession()
        if not self.sessionWatching then return end
        -- Native code latches expiry before processing a pulse; late pulses cannot revive it.
        if self.sessionHeartbeat then native.sessionPulse() end
        local state=native.info()
        self.sessionStatus=state.sessionState==1 and 'Session protected - Esc exits'
            or 'SESSION STOPPED - Esc exits'
        if state.sessionState~=self.lastSessionState then
            emit('protected_session_changed',state);self.lastSessionState=state.sessionState
        end
        if state.sessionState==3 then
            self.sessionWatching=false;self.sessionStatus='Session ended - restart game'
        end
    end
    function self:lock()
        assert(self.phase=='off' and native and native.info().abi=='itb-win32-click-v3','guard-unavailable')
        local ok,reason=native.guardBegin();assert(ok,reason)
        self.guardWatching=true
        emit('ui_guard_start',native.info())
    end
    function self:unlock()
        if native and native.guardEnd then native.guardEnd() end
        self:pollGuard()
    end
    function self:pollGuard()
        if not self.guardWatching then return end
        local state=native.info()
        self.guardStatus='Native input blocked: '..math.ceil(state.guardRemainingMs/1000)..'s'
        if not state.guardActive then
            self.guardWatching=false;self.guardStatus=nil
            emit('ui_guard_end',state)
        end
    end
    function self:observePreview(pawn,weapon,from,to)
        if self.phase=='off' or self.phase=='submitted' or not self.command then return end
        if self.finalPhase~='aim-destination' or not pawn or weapon~='Move' then return end
        -- Copies only. This is a fresh native preview, not a claim of execution.
        self.preview={pawnId=pawn:GetId(),from={x=from.x,y=from.y},to={x=to.x,y=to.y}}
    end
    function self:start(command, validate)
        assert(self.phase=='off','bridge-already-active')
        assert(native and native.info().abi=='itb-win32-click-v3','native-bridge-unavailable')
        local valid,reason=validate();assert(valid,reason)
        local selected=env.Board:GetSelectedPawn()
        -- Pinned loader modapi/pawn.lua maps weapon index 0 to the Move skill.
        assert(not selected or selected:GetArmedWeaponId()==-1 or selected:GetArmedWeaponId()==0,'weapon-armed')
        self.command,self.validate=command,validate
        self.from,self.to=center(command.from),center(command.to)
        emit('ui_bridge_layout',{width=env.screen:w(),height=env.screen:h(),scale=env.GetBoardScale(),
            fromPixel=self.from,toPixel=self.to})
        -- Keep the tested projection/layout; native preview now verifies each destination.
        assert(env.screen:w()==1920 and env.screen:h()==1081 and env.GetBoardScale()==3,
            'uncalibrated-layout')
        self.width,self.height=env.screen:w(),env.screen:h()
        local ok,detail=native.begin();assert(ok,detail)
        emit('ui_bridge_started',{command=command,fromPixel=self.from,toPixel=self.to,
            native=native.info(),proofOfInputAuthorization=false})
        if not selected or selected:GetId()~=command.pawnId then
            aim(self.from,'aim-selection')
        else aim(self.to,'aim-destination') end
    end
    function self:update()
        if self.phase=='off' then return end
        local input=native.info()
        assert(not input.releaseFailed,'native-release-failed')
        if input.pressed then return end
        if self.releaseExpected then
            if self.releasesSeen<self.releaseExpected then return end
            self.releaseExpected=nil
            emit('ui_bridge_release_observed',{releases=self.releasesSeen})
        end
        if self.phase=='submitted' then return end
        assert(self.width==env.screen:w() and self.height==env.screen:h(),'screen-changed')
        assert(same(center(self.command.to),self.to),'board-geometry-changed')
        local valid,reason=self.validate();assert(valid,reason)
        local pawn=env.Board:GetSelectedPawn()
        if self.phase=='selecting' then
            if pawn and pawn:GetId()==self.command.pawnId then
                assert(pawn:GetArmedWeaponId()==0,'movement-not-armed-after-selection')
                emit('ui_bridge_actor_selected',{pawnId=pawn:GetId(),armedWeaponId=pawn:GetArmedWeaponId()})
                aim(self.to,'aim-destination')
            end
            return
        end
        -- Loader hover state refreshes on draw, not merely on queued motion.
        if env.modApi:elapsedTime()-self.aimedAt<100 then return end
        if type(input.mouseX)~='number' or type(input.mouseY)~='number'
            or math.abs(input.mouseX-self.aimPoint.x)>1 or math.abs(input.mouseY-self.aimPoint.y)>1
            or input.cursorX~=input.mouseX or input.cursorY~=input.mouseY then
            if not self.waitLogged then
                emit('ui_bridge_waiting_for_cursor',{expected=self.aimPoint,native=input})
                self.waitLogged=true
            end
            return -- Await delivery; no press has been sent, and the lab timeout remains active.
        end
        local aimedTile=self.phase=='aim-selection' and self.command.from or self.command.to
        if self.phase=='prepare' then
            local ok,detail=native.aim(self.finalPoint.x,self.finalPoint.y);assert(ok,detail)
            self.phase,self.aimedAt=self.finalPhase,env.modApi:elapsedTime()
            self.aimPoint,self.waitLogged=self.finalPoint,false
            return
        end
        assert(same(env.screenPointToTile({x=input.mouseX,y=input.mouseY},false),aimedTile),
            'delivered-cursor-wrong-tile')
        if self.phase=='aim-selection' then
            self.phase='selecting'
            self.releaseExpected=self.releasesSeen+1
            local sent,count=native.click(self.from.x,self.from.y)
            emit('ui_bridge_selection_queued',{accepted=sent,events=count,native=native.info()})
            assert(sent,'selection-queue-failed')
        elseif self.phase=='aim-destination' then
            assert(pawn and pawn:GetId()==self.command.pawnId,'selection-changed')
            assert(pawn:GetArmedWeaponId()==0,'movement-not-armed-after-selection')
            local preview=self.preview
            if not preview then return end -- Bounded outer timeout; no destination press.
            assert(preview.pawnId==self.command.pawnId and same(preview.from,self.command.from)
                and same(preview.to,self.command.to),'native-preview-mismatch')
            emit('ui_bridge_preview_verified',preview)
            self.phase='submitted'
            local sent,count=native.click(self.to.x,self.to.y)
            emit('ui_bridge_destination_queued',{accepted=sent,events=count,pawnId=pawn:GetId(),native=native.info()})
            assert(sent,'destination-queue-failed')
        end
    end
    return self
end
return bridge
