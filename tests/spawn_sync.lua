local module=dofile('mod/scripts/spawn_sync.lua');local json=dofile('mod/scripts/json.lua')
local function fixture(peer)
    local f={sent={},draws=0,spawns=0,plans=0,time=0}
    local s={revision=3,phase='player2',stop=function(self,why) self.stopped=true;self.reason=why end}
    local env={Mission={},Point=function(x,y)return {x=x,y=y}end,
        GAME={GetSpawnList=function()return {'Scorpion','Hornet'}end},Board={IsSpawning=function()return false end},
        Game={GetTurnCount=function()return 2 end},modApi={elapsedTime=function()return f.time end}}
    local spawner={num_spawns=4,pawn_counts={}}
    env.random_int=function(n)f.draws=f.draws+1;return peer=='host' and 0 or n-1 end
    local random=env.random_int
    env.Mission.NextPawn=function()
        local k=env.random_int(2)==0 and 'Scorpion1' or 'Hornet1'
        spawner.num_spawns=spawner.num_spawns+1;spawner.pawn_counts[k]=1
        return setmetatable({GetType=function()return k end,GetId=function()return 123 end},
            {__tostring=function()error('native pawn has no string conversion')end})
    end
    env.Mission.SpawnPawn=function(m,loc,pawn)
        f.spawns=f.spawns+1;loc=loc or env.Point(5,3)
        m.QueuedSpawns={{type=pawn:GetType(),id=pawn:GetId(),location=loc,turns=0}}
    end
    env.Mission.PlanEnvironment=function()f.plans=f.plans+1;return false end
    env.SkillEffect=function()return {AddDelay=function(_,n)assert(n==0.2)end,AddScript=function(_,code)assert(code=='ITBCoopSpawnWait()')end}end
    env.Board.AddEffect=function()f.waits=(f.waits or 0)+1 end
    env.Mission.SpawnPawns=function(m,count)f.batchCount=count end -- scheduled calls arrive later
    local m=setmetatable({ID='Mission_Artillery',GetSpawner=function()return spawner end},{__index=env.Mission})
    local wire={peer=peer,pendingKind='end-turn',pending='end-turn-3',send=function(_,v)json.encode(v);f.sent[#f.sent+1]=v end}
    local native={info=function()return {guardActive=true,sessionState=1,releaseFailed=false}end}
    f.controller=module.install({env=env,wire=wire,json=json,native=native,session=function()return s end,
        capture=function()return {schema='itb-observation-v1',unavailable=json.array(),queued=m.QueuedSpawns and m.QueuedSpawns[1].type or nil}end,
        emit=function(_,v)json.encode(v)end,resultPreview=function(mission)return f.preview==mission end})
    f.env=env;f.m=m;f.s=s;f.native=native;f.random=random
    function f.begin()m:SpawnPawn();assert(f.spawns==0);assert(m:PlanEnvironment());f.controller:tick();return f.sent[1]end
    function f.frame(kind,witness)return {kind=kind,revision=3,phase='player2',id='spawn-1',witness=witness}end
    return f
end
local h,g=fixture('host'),fixture('guest');local hp,gp=h.begin(),g.begin();assert(hp.witness==gp.witness)
h.controller:receive(h.frame('SPAWNSELECT',hp.witness));local selected=h.sent[2]
assert(h.spawns==1 and h.draws==1 and h.env.random_int==h.random)
local head=selected.pawnType..'|'..selected.pawnId..'|'..selected.x..'|'..selected.y..'|2,0;'
local apply=g.frame('SPAWNAPPLY',head..'\n'..selected.afterSpawner..'\n'..gp.witness)
g.controller:receive(apply)
assert(g.spawns==1 and g.draws==1 and g.env.random_int==g.random and g.sent[2].witness==selected.witness)
assert(not pcall(function()g.controller:receive(apply)end) and g.spawns==1)
for _,f in ipairs({h,g})do f.controller:receive(f.frame('SPAWNRELEASE',selected.witness));assert(not f.m:PlanEnvironment() and f.plans==1)end
g=fixture('guest');gp=g.begin();apply=g.frame('SPAWNAPPLY',head..'\n'..selected.afterSpawner..'\n'..gp.witness)
apply.revision=2;assert(not pcall(function()g.controller:receive(apply)end) and g.spawns==0 and g.draws==0)
g=fixture('guest');gp=g.begin();g.time=20000;assert(not pcall(function()g.controller:tick()end) and g.spawns==0)
g=fixture('guest');gp=g.begin();apply=g.frame('SPAWNAPPLY',head:gsub('2,0;','3,0;')..'\n'..selected.afterSpawner..'\n'..gp.witness)
assert(not pcall(function()g.controller:receive(apply)end) and g.spawns==0 and g.env.random_int==g.random)
g=fixture('guest');gp=g.begin();apply=g.frame('SPAWNAPPLY',head..'\n{}\n'..gp.witness)
assert(not pcall(function()g.controller:receive(apply)end) and g.spawns==0)
g=fixture('guest');g.native.info=function()return {guardActive=false}end;g.m:SpawnPawn();assert(g.s.stopped and g.spawns==0)
assert(g.m:PlanEnvironment() and g.plans==0)
-- The native player-turn hook can precede a scheduled spawn or its peer release.
h=fixture('host');assert(not h.controller:settled(2));h.m:SpawnPawns(1)
assert(h.batchCount==1 and not h.controller:settled(2) and h.waits==1)
h.env.ITBCoopSpawnWait();assert(h.waits==2)
h.m:SpawnPawn();h.controller:tick();hp=h.sent[#h.sent]
h.controller:receive(h.frame('SPAWNSELECT',hp.witness));selected=h.sent[#h.sent]
assert(not h.controller:settled(2))
h.controller:receive(h.frame('SPAWNRELEASE',selected.witness));assert(h.controller:settled(2) and not h.controller:settled(3))
h.env.ITBCoopSpawnWait();assert(h.waits==2)
h.env.Game.GetTurnCount=function()return 3 end;h.m:SpawnPawns(0)
assert(h.controller:settled(3) and not h.controller:settled(2))
h.m:SpawnPawns(1);h.m:SpawnPawns(1);assert(h.s.stopped)
h=fixture('host');h.m:SpawnPawns(1);h.time=25000;h.env.ITBCoopSpawnWait()
assert(h.s.stopped and h.s.reason:find('spawn%-batch%-timeout') and h.waits==1)
h.env.ITBCoopSpawnWait();assert(h.waits==1 and h.draws==0 and h.spawns==0)
h=fixture('host')
local preview=setmetatable({ID='Mission_Train'},{__index=h.env.Mission});h.preview=preview
preview:SpawnPawn(h.env.Point(1,1),{GetType=function()return 'Firefly1' end,GetId=function()return 200 end})
preview:SpawnPawns(2);assert(not preview:PlanEnvironment())
assert(h.spawns==1 and h.batchCount==2 and h.plans==1 and not h.s.stopped and #h.sent==0)
h.m:SpawnPawn();assert(h.spawns==1 and #h.controller.queue==1,'active battle must still be intercepted')
print('Coordinated spawn contracts passed: real serializers, engine doubles only; authorized result previews retain native calls.')
