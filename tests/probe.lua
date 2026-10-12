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
    local env = { TEAM_ANY = 2, clock = 0, logs = {}, selectedProfile = 'ITB_Coop_Probe' }
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
test('snapshot ordering survives pawn enumeration order', function()
    local env=environment()
    local ids={9,7}
    env.Board.GetPawns=function() return {size=function() return 2 end, index=function(_, i) return ids[i] end} end
    local a=snapshot.capture(env, {ID='fixture'}, json)
    ids={7,9}
    local b=snapshot.capture(env, {ID='fixture'}, json)
    eq(json.encode(a), json.encode(b))
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
    env.selectedProfile='normal'; env:tick(); env:tick(); env:tick()
    env.modapiext.events.onSkillStart:dispatch({},env.pawn,'Move',env.Point(0,0),env.Point(1,0))
    eq(env:count('onSkillStart'),0); eq(env:count('settled_candidate'),0)
    env.selectedProfile='ITB_Coop_Probe'; env.Board.IsTipImage=function() return true end
    env:tick(); env:tick(); env:tick(); eq(env:count('settled_candidate'),0)
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
test('capture failure is recorded once and never emits stability', function()
    local env=environment(); local broken={capture=function() error('fixture failure') end}
    local p=probe.new({version='test'},env,json,broken,settle); p:subscribe()
    env:tick(); env:tick(); env:tick()
    eq(env:count('capture_failed'),1); eq(env:count('settled_candidate'),0)
end)
print('Lua contract tests: ' .. passed .. ' passed.')
