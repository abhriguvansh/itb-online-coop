-- Bounded UI submission experiment, not multiplayer input authorization.
local bridge = {}
local function same(a,b) return a and b and a.x==b.x and a.y==b.y end
function bridge.new(env, native, emit)
    local self = { phase = 'off' }
    local function center(tile)
        local scale=env.GetBoardScale()
        -- Empirical lower-tile hit point from the disposable-profile positive control.
        -- Loader roundtrip alone did not establish the native game's clickable point.
        assert(type(scale)=='number' and scale>0 and scale<=8,'unsupported-board-scale')
        local origin,_,_,tw,th=env.getScreenRefs(scale)
        local p={x=math.floor(origin.x+tw*scale*(tile.x-tile.y)+0.5),
            y=math.floor(origin.y+th*scale*(tile.x+tile.y+1)+0.5)+34}
        assert(same(env.screenPointToTile(p,false),tile),'coordinate-roundtrip-failed')
        return p
    end
    local function aim(p,phase)
        -- The loader can consume the first motion while its old button hover is cached.
        -- Leave that button, allow a draw, then deliver a distinct motion over the tile.
        local approach={x=p.x+4,y=p.y}
        local ok,detail=native.aim(approach.x,approach.y);assert(ok,detail)
        self.phase,self.aimedAt='prepare',env.modApi:elapsedTime()
        self.finalPoint,self.finalPhase=p,phase
        self.aimPoint,self.waitLogged=approach,false
    end
    function self:stop()
        if native then native.finish() end
        self.phase='off'
    end
    function self:start(command, validate)
        assert(self.phase=='off','bridge-already-active')
        assert(native and native.info().abi=='itb-win32-click-v1','native-bridge-unavailable')
        local valid,reason=validate();assert(valid,reason)
        local selected=env.Board:GetSelectedPawn()
        -- Pinned loader modapi/pawn.lua maps weapon index 0 to the Move skill.
        assert(not selected or selected:GetArmedWeaponId()==-1 or selected:GetArmedWeaponId()==0,'weapon-armed')
        self.command,self.validate=command,validate
        self.from,self.to=center(command.from),center(command.to)
        emit('ui_bridge_layout',{width=env.screen:w(),height=env.screen:h(),scale=env.GetBoardScale(),
            fromPixel=self.from,toPixel=self.to})
        -- Only these two pixel/tile pairs have an independent native-game positive control.
        assert(command.pawnId==2 and same(command.from,{x=0,y=3}) and same(command.to,{x=0,y=2})
            and same(self.from,{x=708,y=323}) and same(self.to,{x=792,y=260}),
            'uncalibrated-route-or-layout')
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
            local sent,count=native.click(self.from.x,self.from.y)
            emit('ui_bridge_selection_queued',{accepted=sent,events=count,native=native.info()})
            assert(sent,'selection-queue-failed')
        elseif self.phase=='aim-destination' then
            assert(pawn and pawn:GetId()==self.command.pawnId,'selection-changed')
            assert(pawn:GetArmedWeaponId()==0,'movement-not-armed-after-selection')
            self.phase='submitted'
            local sent,count=native.click(self.to.x,self.to.y)
            emit('ui_bridge_destination_queued',{accepted=sent,events=count,pawnId=pawn:GetId(),native=native.info()})
            assert(sent,'destination-queue-failed')
        end
    end
    return self
end
return bridge
