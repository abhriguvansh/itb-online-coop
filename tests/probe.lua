local json = dofile('mod/scripts/json.lua')
local settle = dofile('mod/scripts/settle.lua')
local snapshot = dofile('mod/scripts/snapshot.lua')
local probe = dofile('mod/scripts/probe.lua')
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err))
    passed = passed + 1
end
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. ' ~= ' .. tostring(expected))
end
local function fails(fn) assert(not pcall(fn), 'expected failure') end

test('object ordering independent of insertion order', function()
    eq(json.encode({z = 2, a = 1}), '{"a":1,"z":2}')
end)
test('control characters, quotes and backslashes escaped', function()
    eq(json.encode('a\n"\\\0'), '"a\\u000a\\"\\\\\\u0000"')
end)
test('false, zero and empty array retain meaning', function()
    eq(json.encode({b = false, n = 0, a = json.array()}), '{"a":[],"b":false,"n":0}')
end)
test('cyclic and executable values rejected', function()
    local cycle = {}; cycle.x = cycle
    fails(function() json.encode(cycle) end)
    fails(function() json.encode(function() end) end)
end)
test('nonfinite numbers and sparse arrays rejected', function()
    fails(function() json.encode(0/0) end)
    fails(function() json.encode(math.huge) end)
    fails(function() json.encode(json.array({[2] = 'gap'})) end)
end)
test('stable samples require three observations', function()
    local s = settle.new(3)
    eq(s:sample(true, 'A'), false); eq(s:sample(true, 'A'), false)
    eq(s:sample(true, 'A'), true); eq(s:sample(true, 'A'), false)
end)
test('busy or unknown idle invalidates prior samples', function()
    local s = settle.new(3)
    s:sample(true, 'A'); s:sample(true, 'A'); s:sample(false, 'A')
    eq(s:sample(true, 'A'), false)
    s:sample(nil, 'A'); eq(s:sample(true, 'A'), false)
end)
test('state change and context reset restart stability', function()
    local s = settle.new(3)
    s:sample(true, 'A'); s:sample(true, 'A')
    eq(s:sample(true, 'B'), false)
    s:sample(true, 'B'); eq(s:sample(true, 'B'), true)
    s:reset(); eq(s:sample(true, 'B'), false)
end)

local function environment()
    local env = { TEAM_ANY = 2, clock = 0, logs = {}, selectedProfile = 'Alpha',
        Profile = { visible_name = 'ITB_Coop_Probe' } }
    env.Point = function(x,y) return {x=x,y=y} end
    local pawn = { IsBusy=function() return false end,
        GetSpace=function() return env.Point(0,0) end, GetId=function() return 7 end }
    local methods = { GetType='PunchMech', GetTeam=0, GetHealth=3, IsActive=true,
        GetMoveSpeed=3, GetPathProf=0, IsFire=false, IsAcid=false, IsFrozen=false,
        IsShield=false, IsGrappled=false, IsDead=false }
    for method, value in pairs(methods) do
        local v = value; pawn[method] = function() return v end
    end
    env.pawn = pawn
    env.Board = {
        GetSize=function() return env.Point(1,1) end,
        IsBusy=function() return false end,
        IsTipImage=function() return false end,
        GetPawns=function() return {size=function() return 1 end, index=function() return 7 end} end,
        GetPawn=function() return pawn end,
    }
    for _, name in ipairs({'GetTerrain','GetHealth','IsFire','IsAcid','IsSmoke','IsFrozen',
        'IsSpawning','IsPod','IsBuilding','IsCracked','IsEnvironmentDanger'}) do
        env.Board[name] = function() return 0 end
    end
    env.Game = {
        GetTurnCount=function() return 1 end, GetTeamTurn=function() return 0 end,
        GetPower=function() return { GetValue=function() return 5 end } end,
    }
    local function events()
        return setmetatable({}, {__index=function(t, k)
            local e = { listeners={} }
            function e:subscribe(fn) self.listeners[#self.listeners+1] = fn end
            function e:dispatch(...) for _, fn in ipairs(self.listeners) do fn(...) end end
            rawset(t, k, e); return e
        end})
    end
    env.modApi = { version='2.9.6', events=events(),
        getCurrentProfile=function() return env.selectedProfile end,
        getGameVersion=function() return '1.2.93' end,
        elapsedTime=function() return env.clock end }
    env.modapiext = { events=events() }
    env.LOG = function(message) env.logs[#env.logs+1]=message end
    function env:tick() self.clock=self.clock+100; self.modApi.events.onMissionUpdate:dispatch({ID='fixture'}) end
    function env:count(kind)
        local count=0
        for _, log in ipairs(self.logs) do
            if log:find('"event":"' .. kind .. '"', 1, true) then count=count+1 end
        end
        return count
    end
    return env
end

test('snapshot marks inaccessible state and preserves false values', function()
    local env=environment()
    local s, idle=snapshot.capture(env, {ID='fixture'}, json)
    eq(idle, true); eq(s.pawns[1].active, true); eq(s.pawns[1].fire, false)
    eq(s.gridPower, 5); eq(s.identity, 'local-pawn-ids-only')
    eq(#s.unavailable, 2)
    eq(s.unavailable[1], 'pawn.7.movementSpent')
end)
test('missing pawn or failed busy query cannot be idle', function()
    local env=environment(); env.Board.GetPawn=function() return nil end
    local _, idle=snapshot.capture(env, {}, json); eq(idle, false)
    env=environment(); env.Board.IsBusy=function() error('unavailable') end
    _, idle=snapshot.capture(env, {}, json); eq(idle, false)
    env=environment(); env.Board.IsBusy=function() return nil end
    _, idle=snapshot.capture(env, {}, json); eq(idle, false)
    env=environment(); env.pawn.IsBusy=function() return 0 end
    _, idle=snapshot.capture(env, {}, json); eq(idle, false)
end)

test('queued spawn type participates in the observation and inconsistent markers are unavailable',function()
    local env=environment();env.Board.IsSpawning=function() return true end
    local mission={ID='fixture',QueuedSpawns={{id=123,type='Firefly1',turns=1,location=env.Point(0,0)}}}
    local a=snapshot.capture(env,mission,json)
    eq(a.queuedSpawns[1].type,'Firefly1');eq(#a.unavailable,2)
    mission.QueuedSpawns[1].type='Scorpion1'
    local b=snapshot.capture(env,mission,json);assert(json.encode(a)~=json.encode(b))
    mission.QueuedSpawns={}
    local c=snapshot.capture(env,mission,json);eq(c.queuedSpawns,nil);eq(#c.unavailable,3)
    env.Board.IsSpawning=function() return false end
    mission.QueuedSpawns={{id=123,type='Firefly1',turns=1,location=env.Point(0,0)}}
    c=snapshot.capture(env,mission,json);eq(c.queuedSpawns,nil)
end)

test('spawn RNG trace preserves native calls returns and restoration after failure',function()
    local lab=dofile('mod/scripts/phase_lab.lua');local calls=0;local records={};local enabled=true
    local env={Mission={}};local rng=function(limit) calls=calls+1;return limit-1 end;env.random_int=rng
    env.Mission.NextPawn=function(_,limit) return env.random_int(limit),nil,'tail' end
    lab.traceSpawns(env,function() return enabled end,function(_,p) json.encode(p);records[#records+1]=p end,json.array,error)
    local a,b,c=env.Mission:NextPawn(4);eq(a,3);eq(b,nil);eq(c,'tail');eq(calls,1)
    eq(env.random_int,rng);eq(records[1].calls[1].value,3)
    enabled=false;env.Mission:NextPawn(8);eq(calls,2);eq(#records,1)
    local broken={Mission={NextPawn=function() error('native failure') end},random_int=rng}
    lab.traceSpawns(broken,function() return true end,function() end,json.array,error)
    fails(function() broken.Mission:NextPawn() end);eq(broken.random_int,rng)
    local stopped=false;local logFailure={Mission={NextPawn=function() return 'native-pawn' end},random_int=rng}
    lab.traceSpawns(logFailure,function() return true end,function()error('log failed')end,json.array,function()stopped=true end)
    eq(logFailure.Mission:NextPawn(),'native-pawn');eq(stopped,true);eq(logFailure.random_int,rng)
end)
test('snapshot ordering survives pawn enumeration order', function()
    local env=environment()
    local ids={9,7}
    env.Board.GetPawns=function() return {size=function() return 2 end, index=function(_, i) return ids[i] end} end
    local a=snapshot.capture(env, {ID='fixture'}, json)
    ids={7,9}
    local b=snapshot.capture(env, {ID='fixture'}, json)
    eq(json.encode(a), json.encode(b))
end)

test('phase rejection diagnostic never captures a transitional spawn witness',function()
    local names={'onMissionUpdate','onFrameDrawStart','onPreEnvironment','onPostEnvironment','onNextTurn',
        'onVekSpawnAdded','onVekSpawnRemoved','onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned',
        'onMissionDismissed','onDeploymentPhaseStart','onPawnSelectedForDeployment','onPawnUnselectedForDeployment',
        'onPawnDeployed','onPawnUndeployed','onLandingPhaseStart','onPawnLanding','onPawnLanded','onDeploymentPhaseEnd','onWindowShown'}
    local events={};for _,name in ipairs(names)do events[name]={subscribe=function(self,fn)self.listener=fn end}end
    local env={modApi={events=events},modapiext={events={onSkillStart={subscribe=function()end},onSkillEnd={subscribe=function()end}}}}
    local prefix='phase-rejection-fixture/'
    package.loaded[prefix..'json']=json
    package.loaded[prefix..'deployment']={}
    package.loaded[prefix..'phase_wire']={open=function()end}
    package.loaded[prefix..'mission_completion']={observe=function()return {}end}
    local captures=0;package.loaded[prefix..'snapshot']={capture=function()captures=captures+1;error('transitional queue')end}
    local emitted={};local mod={probe={record=function(_,name)emitted[#emitted+1]=name end}}
    local lab=dofile('mod/scripts/phase_lab.lua').install(env,mod,{},prefix)
    local submissions=0
    lab.session={phase='player2',revision=15,phaseEvent=function()end,
        submit=function(_,peer,r)
            submissions=submissions+1;eq(peer,'guest');eq(r.witness,'unadmittable-phase-rejection-probe')
            return {status='rejected',reason='command-pending-renew-intent'}
        end,stop=function()error('unexpected stop')end}
    lab.ending=true;events.onVekSpawningEnd.listener({})
    eq(submissions,1);eq(captures,0);eq(emitted[1],'phase_lab_early_command_rejected')
    lab.session.submit=function()return {status='rejected',reason='stale-observation-renew-intent'}end
    local stopped=false;lab.session.stop=function()stopped=true end
    events.onVekSpawningEnd.listener({});eq(stopped,true)
end)
test('unexpected board size fails instead of looping unboundedly', function()
    local env=environment(); env.Board.GetSize=function() return env.Point(9999,1) end
    fails(function() snapshot.capture(env, {}, json) end)
end)
test('duplicate subscribe and repeated loads do not multiply callbacks', function()
    local env=environment(); local p=probe.new({version='test'},env,json,snapshot,settle)
    p:subscribe(); p:subscribe(); p:load(); p:load()
    eq(#env.modApi.events.onMissionUpdate.listeners,1)
    eq(#env.modapiext.events.onSkillStart.listeners,1)
end)
test('normal profile and tip images do not produce tactical evidence', function()
    local env=environment(); local p=probe.new({version='test'},env,json,snapshot,settle); p:subscribe()
    env.selectedProfile='normal'; env.Profile.visible_name='normal'; env:tick(); env:tick(); env:tick()
    env.modapiext.events.onSkillStart:dispatch({},env.pawn,'Move',env.Point(0,0),env.Point(1,0))
    eq(env:count('onSkillStart'),0); eq(env:count('settled_candidate'),0)
    env.selectedProfile='Alpha'; env.Profile.visible_name='ITB_Coop_Probe'; env.Board.IsTipImage=function() return true end
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),0)
end)
test('profile display name is required even when its folder key matches', function()
    local env=environment(); local p=probe.new({version='test'},env,json,snapshot,settle); p:subscribe()
    env.selectedProfile='ITB_Coop_Probe'; env.Profile.visible_name='normal'
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),0)
    env.Profile=nil
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),0)
    env.Profile={visible_name='ITB_Coop_Probe'}; env.selectedProfile=''
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),0)
    env.selectedProfile='Alpha'
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),1)
end)
test('build events do not become execution events', function()
    local env=environment(); local p=probe.new({version='test'},env,json,snapshot,settle); p:subscribe()
    for i=1,10 do env.modapiext.events.onSkillBuild:dispatch() end
    eq(env:count('onSkillStart'),0)
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),1)
    assert(env.logs[#env.logs]:find('"buildCallsSincePreviousCandidate":10',1,true))
end)
test('execution logs scalars, then requires a fresh stability window', function()
    local env=environment(); local p=probe.new({version='test'},env,json,snapshot,settle); p:subscribe()
    env:tick(); env:tick(); env:tick()
    env.modapiext.events.onSkillEnd:dispatch({},nil,'Move',env.Point(0,0),env.Point(1,0))
    env:tick(); env:tick(); eq(env:count('settled_candidate'),1)
    env:tick(); eq(env:count('settled_candidate'),2)
    eq(env:count('onSkillEnd'),1)
end)
test('undo is reported as unblocked and invalidates observation', function()
    local env=environment(); local p=probe.new({version='test'},env,json,snapshot,settle); p:subscribe()
    env:tick(); env:tick(); env.modapiext.events.onPawnUndoMove:dispatch()
    env:tick(); eq(env:count('settled_candidate'),0)
    eq(env:count('unsupported_action_observed'),1)
end)
test('undo native hook copies observed fields without becoming completion or authorization',function()
    local env=environment();env.pawn.IsMovementSpent=function()return false end;env.pawn.IsUndoPossible=function()return false end
    local p=probe.new({version='test'},env,json,snapshot,settle);p:subscribe()
    env.modapiext.events.onPawnUndoMove:dispatch({ID='fixture'},env.pawn,env.Point(1,0))
    eq(env:count('native_undo_move_observed'),1)
    assert(env.logs[#env.logs]:find('"proofOfCompletion":false',1,true))
    assert(env.logs[#env.logs]:find('"previous":{"x":1,"y":0}',1,true))
    env.Profile.visible_name='normal';env.modapiext.events.onPawnUndoMove:dispatch({ID='fixture'},env.pawn,env.Point(1,0))
    eq(env:count('native_undo_move_observed'),1)
end)
test('undo observation getter failure cannot interrupt the existing invalidation hook',function()
    local env=environment();env.pawn.IsMovementSpent=function()error('unavailable getter')end
    local p=probe.new({version='test'},env,json,snapshot,settle);p:subscribe()
    env.modapiext.events.onPawnUndoMove:dispatch({ID='fixture'},env.pawn,env.Point(1,0))
    eq(env:count('unsupported_action_observed'),1)
    eq(env:count('undo_observation_unavailable'),1)
    eq(env:count('native_undo_move_observed'),0)
end)
test('capture failure is recorded once and never emits stability', function()
    local env=environment(); local broken={capture=function() error('fixture failure') end}
    local p=probe.new({version='test'},env,json,broken,settle); p:subscribe()
    env:tick(); env:tick(); env:tick()
    eq(env:count('capture_failed'),1); eq(env:count('settled_candidate'),0)
end)
print('Lua contract tests: ' .. passed .. ' passed.')
