-- One protected Mission_Artillery phase transition. Never infer completion from idle alone.
local M = {}
local order={'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawningEnd',
    'onPreEnvPlanned','onPostEnvPlanned','onNextTurn'}
function M.new(env,native,emit,capture)
    local self={armed=false,used=false,fault=false,status='End Turn off',frame=0,updates=0}
    local function context()
        assert(env.Profile and env.Profile.visible_name=='ITB_Coop_Probe'
            and type(env.modApi:getCurrentProfile())=='string' and env.modApi:getCurrentProfile()~='', 'wrong-profile')
        assert(env.modApi:getGameVersion()=='1.2.93' and env.GetCurrentMission().ID=='Mission_Artillery','unsupported-context')
        assert(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not self.blocked,'not-tactical')
        assert(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(),'deployment')
        assert(env.Board and not env.Board:IsTipImage(),'unsupported-board')
        assert(env.screen:w()==1920 and env.screen:h()==1081 and env.GetBoardScale()==3,'uncalibrated-layout')
        local n=native.info()
        assert(n.sessionState==1 and n.guardActive and not n.releaseFailed,'protection-unavailable')
    end
    local function fail(reason)
        self.fault=true;self.armed=false;self.status=reason
        native.sessionStop();native.finish()
        emit('end_turn_failed',{reason=reason,stage=self.pending and self.pending.stage})
    end
    function self:arm()
        local ok,reason=pcall(function()
            context();assert((not self.used or (self.repeatedTurns and self.completedTurn==env.Game:GetTurnCount())) and not self.pending and not self.fault,'one-call-lockout')
            assert(env.Game:GetTeamTurn()==env.TEAM_PLAYER and (env.Game:GetTurnCount()==2 or (self.repeatedTurns and self.completedTurn==env.Game:GetTurnCount())),'unsupported-start-phase')
            local _,idle=capture();assert(idle,'not-idle')
            local selected=env.Board:GetSelectedPawn()
            assert(not selected or selected:GetArmedWeaponId()<=0,'weapon-armed')
        end)
        self.armed=ok;self.status=ok and 'End Turn armed' or tostring(reason);return ok
    end
    local function aim(p,x,y,stage)
        local ok,why=native.aim(x,y);assert(ok,why)
        p.x,p.y,p.stage,p.aimedFrame=x,y,stage,self.frame
    end
    function self:request()
        assert(self.armed and (not self.used or (self.repeatedTurns and self.completedTurn==env.Game:GetTurnCount())) and not self.pending and not self.fault,'not-armed')
        context()
        self.used=true;self.completedTurn=nil
        local p={turn=env.Game:GetTurnCount(),mission=env.GetCurrentMission(),since=env.modApi:elapsedTime(),step=0,stage='starting'}
        self.pending=p
        emit('end_turn_requested',{turn=p.turn,confirmation='normal-native-dialog',native=native.info()})
        local ok,why=native.begin();assert(ok,why)
        aim(p,183,177,'approach-end')
        return true
    end
    function self:draw() self.frame=self.frame+1 end
    function self:missionUpdate() self.updates=self.updates+1 end
    function self:phaseEvent(name,mission)
        local p=self.pending;if not p or self.fault then return end
        local ok,why=pcall(function()
            context();assert(mission==p.mission,'mission-changed')
            if name=='onVekSpawnRemoved' or name=='onVekSpawnAdded' then return end
            assert(p.endSent and order[p.step+1]==name,'unexpected-phase-order:'..name)
            if name=='onNextTurn' then
                local expected=p.step==2 and env.TEAM_ENEMY or env.TEAM_PLAYER
                assert(env.Game:GetTeamTurn()==expected,'unexpected-team-transition')
                assert(env.Game:GetTurnCount()==p.turn+(p.step==6 and 1 or 0),'unexpected-turn-transition')
            end
            p.step=p.step+1
            emit('end_turn_phase',{source=name,step=p.step,turn=env.Game:GetTurnCount(),team=env.Game:GetTeamTurn(),busy=env.Board:GetBusyState()})
            if p.step==1 then native.finish();p.stage='transition' end
            if p.step==7 then p.playerUpdate=self.updates;p.playerFrame=self.frame end
        end)
        if not ok then fail(tostring(why)) end
    end
    function self:update()
        local p=self.pending;if not p or self.fault then return end
        local ok,why=pcall(function()
            context();assert(env.GetCurrentMission()==p.mission,'mission-changed')
            assert(env.modApi:elapsedTime()-p.since<60000,'phase-timeout')
            local n=native.info()
            if p.step==7 then
                assert(env.Game:GetTeamTurn()==env.TEAM_PLAYER and env.Game:GetTurnCount()==p.turn+1,'player-phase-lost')
                if self.updates<=p.playerUpdate or self.frame<=p.playerFrame then return end
                local state,idle=capture()
                assert(state.unavailable and #state.unavailable==0,'incomplete-phase-observation')
                if not idle or env.Board:GetBusyState()~=0 then return end
                -- This restricted checkpoint has exactly four surviving, unfrozen friendlies.
                local ready={};local count=0
                for _,pawn in ipairs(state.pawns) do
                    if pawn.team==env.TEAM_PLAYER then
                        if pawn.dead~=false or pawn.frozen~=false or pawn.active~=true or pawn.movementSpent~=false then return end
                        ready[pawn.localId]=true;count=count+1
                    end
                end
                assert(count==4 and ready[0] and ready[1] and ready[2] and ready[100],'unsupported-friendly-transition')
                if env.modApi.runLaterQueue and next(env.modApi.runLaterQueue) then return end
                emit('end_turn_postconditions_observed',{turn=p.turn+1,team=env.TEAM_PLAYER,phaseHooks=p.step,
                    busy=env.Board:GetBusyState(),state=state,proofOfGeneralQuiescence=false,proofOfPeerAgreement=false})
                self.completedTurn=p.turn+1;self.pending=nil;self.armed=false;self.status='Next player phase admitted';return
            end
            -- After Yes is submitted, only ordered phase evidence can complete the action.
            -- Slow rendering can delay the first hook past the UI deadline; retain the
            -- overall phase deadline and protection, without sending another click.
            if p.stage=='transition' or p.stage=='wait-transition' then return end
            assert(env.modApi:elapsedTime()-p.since<4500,'end-turn-ui-timeout')
            if n.pressed then return end
            if p.stage=='wait-dialog' then
                if not p.releasedFrame then p.releasedFrame=self.frame;return end
                if self.frame<=p.releasedFrame+2 then return end
                local r=env.sdlext.CurrentWindowRect
                local rect=r and {x=r.x,y=r.y,w=r.w,h=r.h} or {}
                local fingerprint=table.concat({rect.x or -1,rect.y or -1,rect.w or -1,rect.h or -1},':')
                if p.lastRect~=fingerprint then
                    p.lastRect=fingerprint;emit('end_turn_dialog_observation',rect)
                end
                -- Observed native Active Units subpanel for one, three or four unused units.
                -- The confirmation buttons retain the same position in these layouts.
                if r and r.y==683 and r.h==60 and ((r.x==850 and r.w==221) or (r.x==803 and r.w==315) or (r.x==779 and r.w==362)) then
                    p.dialog=rect;emit('end_turn_confirmation_observed',rect)
                    aim(p,894,565,'approach-confirm')
                end
                return
            end
            if self.frame<=p.aimedFrame+1 or type(n.mouseX)~='number' or type(n.mouseY)~='number'
                or math.abs(n.mouseX-p.x)>1 or math.abs(n.mouseY-p.y)>1
                or n.cursorX~=n.mouseX or n.cursorY~=n.mouseY then return end
            if p.stage=='approach-end' then aim(p,179,177,'click-end');return end
            if p.stage=='approach-confirm' then aim(p,890,565,'click-confirm');return end
            if p.stage=='click-confirm' then
                local r=env.sdlext.CurrentWindowRect
                assert(r and r.x==p.dialog.x and r.y==p.dialog.y and r.w==p.dialog.w and r.h==p.dialog.h,'confirmation-changed')
            end
            local action=p.stage=='click-end' and 'end-turn' or 'confirm-unused'
            assert(p.stage=='click-end' or p.stage=='click-confirm','unknown-ui-stage')
            p.endSent=true;p.stage=action=='end-turn' and 'wait-dialog' or 'wait-transition'
            local sent,detail=native.click(p.x,p.y)
            emit('end_turn_click',{action=action,accepted=sent,detail=detail,native=native.info()})
            assert(sent,'click-uncertain')
        end)
        if not ok then fail(tostring(why)) end
    end
    return self
end
return M
