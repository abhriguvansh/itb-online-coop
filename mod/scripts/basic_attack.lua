-- Restricted Rift Walker base weapons. Native execution owns damage and allowances.
local M={}
local types={[0]={'PunchMech','Prime_Punchmech'},[1]={'TankMech','Brute_Tankmech'},[2]={'ArtiMech','Ranged_Artillerymech'}}
function M.new(env,lab,gate,emit,capture,json)
    local self={armed=false,fault=false,status='Basic attack off',frame=0,updates=0}
    local function context(c)
        assert(lab:profileAllowed() and env.modApi:getGameVersion()=='1.2.93','unsupported-profile-version')
        assert(env.sdlext.isGame() and not env.sdlext.isConsoleOpen() and not lab.blocked,'not-tactical')
        assert(not gate.active and not lab.pending and not lab.armed,'other-action-active')
        assert(env.GetCurrentMission().ID==(lab.supportedMission or 'Mission_Artillery'),'unsupported-mission')
        assert(not env.modApi.deployment:isDeploymentPhase() and not env.modApi.deployment:isLandingPhase(),'deployment')
        assert(env.Game:GetTeamTurn()==env.TEAM_PLAYER and env.Game:GetTurnCount()==c.turn,'wrong-phase')
        assert(not env.Board:IsTipImage() and env.memedit and env.memedit:get(),'unsupported-board')
    end
    local function validate(c,executing)
        assert(c and (not self.pending or executing) and not self.fault,'attack-unavailable');context(c)
        local state,idle=capture();assert(idle and #state.unavailable==0,'incomplete-or-busy')
        local spec=types[c.pawnId];assert(spec,'unsupported-actor')
        local p=env.Board:GetPawn(c.pawnId)
        assert(p and p:GetType()==spec[1] and p:GetTeam()==env.TEAM_PLAYER,'wrong-actor')
        assert(p:IsPowered() and p:IsActive() and not p:IsDead() and not p:IsFrozen(),'inactive-actor')
        local pos=p:GetSpace();assert(pos.x==c.from.x and pos.y==c.from.y,'stale-origin')
        assert(not env.Board:IsSmoke(pos),'smoke-blocked')
        assert(not p:IsAbility('Double_Shot') and not p:IsAbility('Post_Move') and not p:IsAbility('Shifty'),'unsupported-pilot')
        assert(p:GetPoweredWeapons()[1]==spec[2],'unsupported-powered-weapon')
        local weapon=c.repair and 'Skill_Repair' or spec[2]
        local maximum
        if c.repair then
            maximum=p:GetMaxHealth()
            assert(maximum==(c.pawnId==2 and 2 or 3),'unsupported-repair-health')
            assert(c.to.x==pos.x and c.to.y==pos.y,'repair-must-target-self')
            assert(not p:IsAcid() and not env.Board:IsAcid(pos),'acid-repair-unverified')
            assert(p:GetHealth()<maximum or p:IsFire() or env.Board:IsFire(pos),'repair-has-no-effect')
        end
        local skill=env[weapon];assert(skill and not skill.TwoClick and (not skill.Limited or skill.Limited==0),'unsupported-skill')
        local targets=skill:GetTargetArea(pos);assert(targets:size()<=64,'target-list-size')
        local found=false
        for i=1,targets:size() do local t=targets:index(i);if t.x==c.to.x and t.y==c.to.y then found=true end end
        assert(found and env.Board:IsValid(env.Point(c.to.x,c.to.y)),'illegal-target')
        return {state=state,weapon=weapon,health=p:GetHealth(),maximum=maximum,repair=c.repair==true,from={x=pos.x,y=pos.y}}
    end
    function self:arm(c)
        local ok,result=pcall(validate,c);self.armed=ok;self.command=ok and c or nil
        self.status=ok and 'Basic weapon ready' or tostring(result);return ok
    end
    function self:disarm() if self.pending then return false end;self.armed=false;self.command=nil;return true end
    function self:request(c)
        assert(self.armed and self.command==c,'not-armed')
        local before=validate(c);self.armed=false
        self.pending={command=c,before=before,since=env.modApi:elapsedTime(),mission=env.GetCurrentMission()}
        emit('attack_requested',{actorId=c.pawnId,weapon=before.weapon,weaponIndex=c.repair and 50 or 1,target=c.to,before=before})
        local ok,result=pcall(function()
            return self.bridge:start({pawnId=c.pawnId,from=c.from,to=c.to,weapon=before.weapon,weaponIndex=c.repair and 50 or nil},function()
                local valid,reason=pcall(validate,c,true);return valid,reason
            end)
        end)
        emit('attack_ui_submission',{callSucceeded=ok,returnType=type(result),returnedTrue=result==true})
        if not ok then self.fault=true end
        return ok -- Never infer completion or retry from the native return value.
    end
    function self:skillEvent(kind,pawn,weapon)
        local p=self.pending;if not p then return end
        if pawn and pawn:GetId()==p.command.pawnId and weapon==p.before.weapon then
            assert(kind~='onSkillStart' or not p.started,'duplicate-attack-start')
            assert(kind~='onSkillEnd' or (p.started and not p.ended),'unexpected-attack-end')
            if kind=='onSkillStart' then p.started=true end
            if kind=='onSkillEnd' then p.ended=true;p.endFrame=self.frame;p.endUpdate=self.updates end
            emit('attack_execution_hook',{stage=kind,actorId=p.command.pawnId,weapon=weapon})
        end
    end
    function self:draw() self.frame=self.frame+1 end
    function self:missionUpdate() self.updates=self.updates+1 end
    function self:update()
        local p=self.pending;if not p or self.fault then return end
        local ok,reason=pcall(function()
            self.bridge:update()
            context(p.command);assert(env.GetCurrentMission()==p.mission,'mission-changed')
            assert(env.modApi:elapsedTime()-p.since<15000,'attack-outcome-timeout')
            if not p.ended or self.frame<=p.endFrame or self.updates<=p.endUpdate then return end
            local state,idle=capture();assert(#state.unavailable==0,'incomplete-observation')
            if not idle or env.Board:GetBusyState()~=0 or (env.modApi.runLaterQueue and next(env.modApi.runLaterQueue)) then return end
            local actor=env.Board:GetPawn(p.command.pawnId)
            assert(actor,'actor-unavailable')
            local allowance=tostring(actor:IsActive())..':'..tostring(actor:IsUndoPossible())
            if allowance~=p.lastAllowance then
                p.lastAllowance=allowance;emit('attack_allowance_observation',{actorId=p.command.pawnId,active=actor:IsActive(),undoPossible=actor:IsUndoPossible(),elapsed=env.modApi:elapsedTime()-p.since})
            end
            if actor:IsActive() or actor:IsUndoPossible() then return end
            local pos=actor:GetSpace();assert(pos.x==p.before.from.x and pos.y==p.before.from.y,'unexpected-actor-displacement')
            if p.before.repair then
                assert(actor:GetHealth()==math.min(p.before.health+1,p.before.maximum),'repair-health-mismatch')
                assert(not actor:IsFire() and not actor:IsAcid() and not env.Board:IsFire(pos),'repair-status-mismatch')
            end
            emit('attack_postconditions_observed',{actorId=p.command.pawnId,weapon=p.before.weapon,after=state,
                startObserved=p.started,endObserved=p.ended,laterDraw=true,laterMissionUpdate=true,proofOfGeneralQuiescence=false})
            self.bridge:stop(true);self.pending=nil;self.status='Basic attack observed'
        end)
        if not ok then self.fault=true;emit('attack_failed',{reason=tostring(reason)}) end
    end
    return self
end
return M
