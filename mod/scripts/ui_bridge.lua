-- Bounded UI submission experiment, not multiplayer input authorization.
local bridge = {}
local function same(a,b) return a and b and a.x==b.x and a.y==b.y end
function bridge.new(env, native, emit)
    local self = { phase = 'off' }
    local function center(tile)
        local scale=env.GetBoardScale()
        assert(type(scale)=='number' and scale>0 and scale<=8, 'unsupported-board-scale')
        local origin,_,_,tw,th=env.getScreenRefs(scale)
        local p={x=math.floor(origin.x+tw*scale*(tile.x-tile.y)+0.5),
            y=math.floor(origin.y+th*scale*(tile.x+tile.y+1)+0.5)}
        assert(same(env.screenPointToTile(p,false),tile),'coordinate-roundtrip-failed')
        return p
    end
    local function aim(p,phase)
        local ok,detail=native.aim(p.x,p.y);assert(ok,detail)
        self.phase,self.aimedAt=phase,env.modApi:elapsedTime()
    end
    function self:stop()
        if native then native.finish() end
        self.phase='off'
    end
    function self:start(command, validate)
        assert(self.phase=='off','bridge-already-active')
        assert(native and native.info().abi=='itb-sdl-click-v1','native-bridge-unavailable')
        local valid,reason=validate();assert(valid,reason)
        local selected=env.Board:GetSelectedPawn()
        assert(not selected or selected:GetArmedWeaponId()==-1,'weapon-armed')
        self.command,self.validate=command,validate
        self.from,self.to=center(command.from),center(command.to)
        self.width,self.height=env.screen:w(),env.screen:h()
        local ok,detail=native.begin();assert(ok,detail)
        emit('ui_bridge_started',{command=command,fromPixel=self.from,toPixel=self.to,
            native=native.info(),proofOfInputAuthorization=false})
        if not selected or selected:GetId()~=command.pawnId then
            aim(self.from,'aim-selection')
        else aim(self.to,'aim-destination') end
    end
    function self:update()
        if self.phase=='off' or self.phase=='submitted' then return end
        assert(self.width==env.screen:w() and self.height==env.screen:h(),'screen-changed')
        assert(same(center(self.command.to),self.to),'board-geometry-changed')
        local valid,reason=self.validate();assert(valid,reason)
        local pawn=env.Board:GetSelectedPawn()
        if self.phase=='selecting' then
            if pawn and pawn:GetId()==self.command.pawnId then
                assert(pawn:GetArmedWeaponId()==-1,'weapon-armed-after-selection')
                aim(self.to,'aim-destination')
            end
            return
        end
        -- Loader hover state refreshes on draw, not merely on queued motion.
        if env.modApi:elapsedTime()-self.aimedAt<100 then return end
        if self.phase=='aim-selection' then
            self.phase='selecting'
            local sent,count=native.click(self.from.x,self.from.y)
            emit('ui_bridge_selection_queued',{accepted=sent,events=count})
            assert(sent,'selection-queue-failed')
        elseif self.phase=='aim-destination' then
            assert(pawn and pawn:GetId()==self.command.pawnId,'selection-changed')
            assert(pawn:GetArmedWeaponId()==-1,'weapon-armed-after-selection')
            self.phase='submitted'
            local sent,count=native.click(self.to.x,self.to.y)
            emit('ui_bridge_destination_queued',{accepted=sent,events=count,pawnId=pawn:GetId()})
            assert(sent,'destination-queue-failed')
        end
    end
    return self
end
return bridge
