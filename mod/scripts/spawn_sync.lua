-- Restricted checkpoint experiment: coordinate native spawn choices inside End Turn.
-- No seed repair or post-state overwrites. Each intercepted call executes at most once.
local M={}
function M.install(o)
    local env,wire,json=o.env,o.wire,o.json
    local originalSpawn,originalPlan,originalBatch=env.Mission.SpawnPawn,env.Mission.PlanEnvironment,env.Mission.SpawnPawns
    local self={queue={},serial=0}
    local function session() return o.session() end
    local function protected()
        local s=session();local n=o.native.info()
        assert(s and not s.stopped and wire.pendingKind=='end-turn' and wire.pending,'spawn-outside-end-turn')
        assert(n.guardActive and n.sessionState==1 and not n.releaseFailed,'spawn-protection-lost')
        return s
    end
    local function spawner(m)
        local s=m:GetSpawner();local v={}
        for _,key in ipairs({'num_spawns','num_bosses','used_bosses','upgrade_streak','num_weak','num_upgrades','upgrade_max','spawn_island'}) do
            local n=s[key];assert(n==nil or type(n)=='number','unsupported-spawner-field');v[key]=n
        end
        v.pawn_counts={}
        for k,n in pairs(s.pawn_counts or {}) do
            assert(type(k)=='string' and type(n)=='number','invalid-spawner-count');v.pawn_counts[k]=n
        end
        for _,key in ipairs({'curr_weakRatio','curr_upgradeRatio'}) do
            if s[key] then v[key]=json.array({s[key][1],s[key][2]}) end
        end
        local choices=env.GAME:GetSpawnList(s.spawn_island)
        v.choices=json.array();for _,kind in ipairs(choices) do v.choices[#v.choices+1]=kind end
        return json.encode(v)
    end
    local function witness(m)
        local state=o.capture();assert(#state.unavailable==0,'spawn-incomplete-observation')
        return json.encode({board=state,spawner=spawner(m)})
    end
    local function send(kind,p,extra)
        local value=extra or {};value.type=kind;value.index=p.index;value.revision=p.revision;value.phase=p.phase
        wire:send(value)
    end
    local function perform(p,data)
        protected();assert(not p.committed,'spawn-already-committed')
        assert(witness(p.mission)==p.before,'spawn-precondition-changed')
        p.committed=true -- Errors after this point are uncertain; never retry.
        local random=env.random_int;local calls=json.array();local cursor=0
        env.random_int=function(limit)
            cursor=cursor+1;assert(cursor<=128,'spawn-random-limit')
            local nativeValue=random(limit) -- consume the ordinary native draw exactly once
            local value=nativeValue
            if data then
                local c=data.calls[cursor];assert(c and c.limit==limit,'spawn-random-shape-conflict');value=c.value
            end
            calls[#calls+1]={limit=limit,value=value}
            return value
        end
        local ok,pawn=pcall(function() return p.mission:NextPawn() end)
        env.random_int=random
        if not ok then error('spawn-selection-uncertain:'..tostring(pawn)) end
        assert(not data or cursor==#data.calls,'spawn-random-count-conflict')
        local kind,id=pawn:GetType(),pawn:GetId()
        if data then
            assert(kind==data.pawnType and id==data.pawnId,'spawn-pawn-conflict')
            assert(spawner(p.mission)==data.afterSpawner,'spawn-bookkeeping-conflict')
            local loc=env.Point(data.x,data.y)
            assert(not env.Board:IsSpawning(loc),'spawn-location-conflict')
            originalSpawn(p.mission,loc,pawn)
        else
            originalSpawn(p.mission,nil,pawn)
        end
        local q=p.mission.QueuedSpawns;local spawn=q and q[#q]
        assert(spawn and spawn.id==id and spawn.type==kind and spawn.location,'spawn-result-missing')
        if data then assert(spawn.location.x==data.x and spawn.location.y==data.y,'spawn-location-overridden') end
        local result={pawnType=kind,pawnId=id,x=spawn.location.x,y=spawn.location.y,calls=calls,
            afterSpawner=spawner(p.mission),witness=witness(p.mission),native=o.native.info()}
        o.emit('coordinated_spawn_executed',{peer=wire.peer,index=p.index,revision=p.revision,
            pawnType=kind,pawnId=id,x=result.x,y=result.y,calls=calls,afterSpawner=result.afterSpawner})
        p.after=result.witness;p.stage=wire.peer=='host' and 'selected' or 'applied'
        send(wire.peer=='host' and 'spawn_selected' or 'spawn_applied',p,result)
    end
    function self:receive(m)
        local s=protected();local p=self.pending
        assert(p and m.revision==p.revision and m.phase==p.phase and m.id=='spawn-'..p.index
            and s.revision==p.revision,'spawn-stale-context')
        if m.kind=='SPAWNSELECT' then
            assert(wire.peer=='host' and p.stage=='waiting' and m.witness==p.before,'spawn-select-conflict')
            perform(p)
        elseif m.kind=='SPAWNAPPLY' then
            assert(wire.peer=='guest' and p.stage=='waiting','spawn-apply-conflict')
            local head,after,before=m.witness:match('^([^\n]+)\n([^\n]+)\n([^\n]+)$')
            assert(head and before==p.before,'spawn-apply-precondition')
            local kind,id,x,y,raw=head:match('^([%w_]+)|(%d+)|([0-7])|([0-7])|(.*)$')
            assert(kind and #kind<=128,'spawn-apply-shape')
            local calls={};local encoded={}
            for limit,value in raw:gmatch('(%d+),(%d+);') do
                limit=tonumber(limit);value=tonumber(value)
                assert(limit>0 and value<limit and #calls<128,'spawn-apply-random')
                calls[#calls+1]={limit=limit,value=value};encoded[#encoded+1]=limit..','..value..';'
            end
            assert(table.concat(encoded)==raw,'spawn-apply-random-format')
            perform(p,{pawnType=kind,pawnId=tonumber(id),x=tonumber(x),y=tonumber(y),calls=calls,afterSpawner=after})
        elseif m.kind=='SPAWNRELEASE' then
            assert((p.stage=='selected' or p.stage=='applied') and m.witness==p.after,'spawn-release-conflict')
            o.emit('coordinated_spawn_released',{index=p.index,revision=p.revision})
            self.pending=nil
        else error('spawn-message-kind') end
    end
    function self:tick()
        if self.pending then assert(env.modApi:elapsedTime()-self.pending.at<20000,'spawn-peer-timeout') end
        if not self.pending and #self.queue>0 then
            local s=protected();local m=table.remove(self.queue,1)
            self.serial=self.serial+1;assert(self.serial<=32,'spawn-experiment-limit')
            local p={mission=m,index=self.serial,revision=s.revision,phase=s.phase,stage='waiting',at=env.modApi:elapsedTime()}
            p.before=witness(m);self.pending=p
            send('spawn_prepare',p,{witness=p.before,native=o.native.info()})
            o.emit('coordinated_spawn_waiting',{index=p.index,revision=p.revision,peer=wire.peer})
        end
    end
    function self:settled(turn)
        local b=self.batch
        return b and b.turn==turn and self.serial==b.start+b.count and not self.pending and #self.queue==0
    end
    -- The engine may switch teams before a slow peer replies. Keep its effect
    -- queue occupied until this native spawn batch has been acknowledged.
    env.ITBCoopSpawnWait=function()
        local s=session();local b=self.batch
        if not s or s.stopped or not b or self:settled(b.turn) then return end
        local ok,why=pcall(function()
            protected()
            assert(env.modApi:elapsedTime()-b.at<25000,'spawn-batch-timeout')
            local fx=env.SkillEffect();fx:AddDelay(0.2);fx:AddScript('ITBCoopSpawnWait()')
            env.Board:AddEffect(fx)
        end)
        if not ok then s:stop('spawn-wait:'..tostring(why)) end
    end
    env.Mission.SpawnPawns=function(m,count)
        if not session() or (o.resultPreview and o.resultPreview(m)) then return originalBatch(m,count) end
        local ok,why=pcall(function()
            protected()
            assert(type(count)=='number' and count%1==0 and count>=0 and count<=8,'unsupported-spawn-count')
            assert(not self.batch or self:settled(self.batch.turn),'spawn-batch-overlap')
            self.batch={turn=env.Game:GetTurnCount(),start=self.serial,count=count,at=env.modApi:elapsedTime()}
            o.emit('coordinated_spawn_batch',{turn=self.batch.turn,count=count})
            originalBatch(m,count)
            env.ITBCoopSpawnWait()
        end)
        if not ok then session():stop('spawn-batch:'..tostring(why)) end
    end
    env.Mission.SpawnPawn=function(m,location,pawnType)
        if not session() or (o.resultPreview and o.resultPreview(m)) then return originalSpawn(m,location,pawnType) end
        local ok,why=pcall(function()
            protected();assert(not location and not pawnType and m.ID=='Mission_Artillery','unsupported-spawn-call')
            assert(#self.queue<8,'spawn-queue-limit');self.queue[#self.queue+1]=m
        end)
        if not ok then session():stop('spawn-intercept:'..tostring(why)) end
    end
    env.Mission.PlanEnvironment=function(m,...)
        if o.resultPreview and o.resultPreview(m) then return originalPlan(m,...) end
        if session() and (session().stopped or self.pending or #self.queue>0) then return true end
        return originalPlan(m,...)
    end
    wire.spawn=self
    return self
end
return M
