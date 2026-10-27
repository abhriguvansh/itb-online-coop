-- One native Undo for the newest remaining authorized ordinary move.
-- The loader hook is inferred; completion also needs later runtime observations.
local M={}
local types={[0]='PunchMech',[1]='TankMech',[2]='ArtiMech'}
local function same(a,b)return a and b and a.x==b.x and a.y==b.y end
function M.new(env,lab,gate,emit,capture,json)
    local self={armed=false,fault=false,status='Undo unavailable',frame=0,updates=0}
    local function context(c)
        assert(lab:profileAllowed() and env.modApi:getGameVersion()=='1.2.93','unsupported-profile-version')
        assert(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not lab.blocked,'not-tactical')
        assert(not gate.active and not lab.pending and not lab.armed,'other-action-active')
        assert(env.GetCurrentMission().ID==(lab.supportedMission or 'Mission_Artillery'),'unsupported-mission')
        assert(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(),'deployment')
        assert(env.Game:GetTeamTurn()==env.TEAM_PLAYER and env.Game:GetTurnCount()==c.turn,'wrong-phase')
        assert(env.Board and not env.Board:IsTipImage(),'unsupported-board')
    end
    local function validate(c,executing)
        assert(c and not self.fault and (not self.pending or executing),'undo-unavailable');context(c)
        assert(type(c.restoreWitness)=='string' and #c.restoreWitness>0 and #c.restoreWitness<=65536,'missing-move-witness')
        local state,idle=capture();assert(idle and #state.unavailable==0,'incomplete-or-busy')
        local pawn=env.Board:GetPawn(c.pawnId)
        assert(pawn and types[c.pawnId]==pawn:GetType() and pawn:GetTeam()==env.TEAM_PLAYER,'unsupported-actor')
        assert(pawn:IsPowered() and pawn:IsActive() and not pawn:IsDead(),'inactive-actor')
        for _,method in ipairs({'IsFrozen','IsGrappled','IsFlying','IsJumper','IsTeleporter','IsFire','IsAcid'}) do
            assert(pawn[method](pawn)==false,'unsupported-status:'..method)
        end
        assert(not pawn:IsAbility('Adjacent_Heal') and not pawn:IsAbility('Web_Vek'),'unsupported-move-ability')
        assert(same(pawn:GetSpace(),c.from) and not same(c.from,c.to),'stale-undo-origin')
        assert(pawn:IsMovementSpent() and pawn:IsUndoPossible(),'native-undo-unavailable')
        assert(same(pawn:GetUndoLoc(),c.to),'native-undo-location-changed')
        assert(env.Board:IsValid(env.Point(c.to.x,c.to.y)) and not env.Board:IsPawnSpace(env.Point(c.to.x,c.to.y)),'undo-destination-unavailable')
        return state
    end
    function self:arm(c)
        local ok,result=pcall(validate,c);self.armed=ok;self.command=ok and c or nil
        self.status=ok and 'Undo ready' or tostring(result);return ok
    end
    function self:disarm()if self.pending then return false end;self.armed=false;self.command=nil;return true end
    function self:request(c)
        assert(self.armed and self.command==c,'not-armed');validate(c);self.armed=false
        self.pending={command=c,since=env.modApi:elapsedTime(),mission=env.GetCurrentMission()}
        emit('undo_move_requested',{actorId=c.pawnId,from=c.from,to=c.to})
        local ok,result=pcall(function()return self.bridge:start({pawnId=c.pawnId,from=c.from,to=c.to,undo=true},function()
            local valid,reason=pcall(validate,c,true);return valid,reason
        end)end)
        emit('undo_move_ui_submission',{callSucceeded=ok,returnedTrue=result==true})
        if not ok then self.fault=true end
        return ok -- A possibly committed action is never retried.
    end
    function self:event(mission,pawn,previous)
        local p=self.pending;assert(p and not self.fault,'unrequested-undo')
        context(p.command);assert(mission==p.mission and not p.hook,'unexpected-undo-hook')
        assert(self.bridge.phase=='submitted' and pawn and pawn:GetId()==p.command.pawnId,'undo-before-submission-or-wrong-actor')
        assert(same(previous,p.command.from) and same(pawn:GetSpace(),p.command.to),'undo-hook-position-mismatch')
        assert(pawn:IsActive() and not pawn:IsMovementSpent() and not pawn:IsUndoPossible(),'undo-hook-allowance-mismatch')
        p.hook=true;p.hookFrame=self.frame;p.hookUpdate=self.updates
        emit('undo_move_execution_hook',{actorId=p.command.pawnId,previous={x=previous.x,y=previous.y},
            position={x=pawn:GetSpace().x,y=pawn:GetSpace().y},inferredByLoader=true})
    end
    function self:skillEvent()assert(not self.pending,'unexpected-skill-during-undo')end
    function self:draw()self.frame=self.frame+1 end
    function self:missionUpdate()self.updates=self.updates+1 end
    function self:update()
        local p=self.pending;if not p or self.fault then return end
        local ok,reason=pcall(function()
            context(p.command);assert(env.GetCurrentMission()==p.mission,'mission-changed')
            assert(env.modApi:elapsedTime()-p.since<15000,'undo-outcome-timeout')
            self.bridge:update()
            if self.bridge.phase~='submitted' then assert(env.modApi:elapsedTime()-p.since<4500,'undo-ui-timeout') end
            if not p.hook or self.frame<=p.hookFrame or self.updates<=p.hookUpdate then return end
            if not self.bridge:submissionReleased() then return end
            local state,idle=capture();assert(#state.unavailable==0,'incomplete-observation')
            if not idle or env.Board:GetBusyState()~=0 or (env.modApi.runLaterQueue and next(env.modApi.runLaterQueue)) then return end
            local pawn=env.Board:GetPawn(p.command.pawnId)
            assert(pawn and same(pawn:GetSpace(),p.command.to) and pawn:IsActive()
                and not pawn:IsMovementSpent() and not pawn:IsUndoPossible(),'undo-outcome-mismatch')
            assert(json.encode(state)==p.command.restoreWitness,'undo-restored-observation-mismatch')
            emit('undo_move_postconditions_observed',{actorId=p.command.pawnId,state=state,matchingHook=true,
                laterDraw=true,laterMissionUpdate=true,releaseObserved=true,proofOfGeneralQuiescence=false})
            self.bridge:stop(true);self.pending=nil;self.command=nil;self.status='Undo observed'
        end)
        if not ok then self.fault=true;emit('undo_move_failed',{reason=tostring(reason)}) end
    end
    return self
end
return M
