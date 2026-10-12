local module = dofile('mod/scripts/input_gate.lua')
local passed = 0
local function test(name, fn) local ok, err = pcall(fn); assert(ok, name .. ': ' .. tostring(err)); passed = passed + 1 end
local function fixture()
    local e = { clock = 0, TEAM_PLAYER = 1, logs = {}, turn = 2 }
    local lab = { profileAllowed = function() return true end }
    local function event() return { subscribe = function(self, fn) self.fn = fn end } end
    e.modApi = { elapsedTime = function() return e.clock end, getGameVersion = function() return '1.2.93' end,
        deployment = { isDeploymentPhase = function() return false end, isLandingPhase = function() return false end },
        events = { onKeyPressing = event(), onKeyReleasing = event() } }
    e.sdlext = { isGame = function() return true end, isConsoleOpen = function() return false end }
    e.GetCurrentMission = function() return { ID = 'Mission_Artillery' } end
    e.Board = { IsTipImage = function() return false end, IsBusy = function() return false end }
    e.Game = { GetTeamTurn = function() return 1 end, GetTurnCount = function() return e.turn end }
    e.sdl = { events = { mousebuttondown = 1, mousebuttonup = 2, mousewheel = 3, textinput = 4 },
        eventHook = function(fn) e.native = fn; return { retained = true } end }
    local g = module.new(e, lab, function(k, d) e.logs[#e.logs+1] = { kind = k, data = d } end,
        function() return { turn = e.turn }, not e.busy end)
    return e, lab, g
end
test('off passes supported inputs without logging', function()
    local e, l, g = fixture()
    for _, k in ipairs({'keydown','keyup','mousedown','mouseup','text','wheel'}) do assert(not g:handle(k,1)) end
    assert(#e.logs == 0)
end)
test('arm records state and blocks action presses and releases', function()
    local e, l, g = fixture(); assert(g:arm() and l.gateBlocked)
    assert(e.logs[1].data.state.turn == 2)
    for _, k in ipairs({'keydown','keyup','mousedown','mouseup','text','wheel'}) do assert(g:handle(k,1)) end
    assert(next(g.held) == nil and g.count == 6)
    assert(not g:handle('motion') and not g:handle('quit'))
end)
test('timeout releases new inputs at exactly 30 seconds', function()
    local e, l, g = fixture(); g:arm(); e.clock = 29999; assert(g:handle('wheel'))
    e.clock = 30000; assert(not g:handle('keydown',2)); assert(not l.gateBlocked and not g.active)
    assert(e.logs[#e.logs].data.reason == 'timeout')
end)
test('held key repeats and release remain suppressed across expiry', function()
    local e,l,g=fixture(); g:arm(); assert(g:handle('keydown',7)); e.clock=30001
    assert(g:handle('keydown',7)); assert(not g:arm()); assert(g:handle('keyup',7))
    assert(not g:handle('keydown',7)); assert(g:arm())
end)
test('mouse release is paired across manual disarm', function()
    local e,l,g=fixture(); g:arm(); g:handle('mousedown',1); g:stop('manual',false)
    assert(g:handle('mouseup',1)); assert(not g:handle('mousedown',1))
end)
test('context reset clears suppression for normal profiles', function()
    local e,l,g=fixture(); g:arm(); g:handle('keydown',7); l.profileAllowed=function() return false end
    g:update(); assert(not g.active and next(g.held)==nil and not l.gateBlocked)
    assert(not g:arm() and not g:handle('keyup',7))
end)
test('movement lab cannot overlap', function()
    local e,l,g=fixture(); l.armed=true; assert(not g:arm()); l.armed=false; l.pending={}; assert(not g:arm())
end)
test('busy capture and unsupported phase reject arming', function()
    local e,l,g=fixture(); e.busy=true; assert(not g:arm()); e.busy=false
    e.Game.GetTeamTurn=function() return 2 end; assert(not g:arm())
end)
test('invalid and rewound clock release diagnostic', function()
    local e,l,g=fixture(); e.clock=10; g:arm(); e.clock=9; g:update(); assert(not g.active)
    e.clock=10; g:arm(); e.clock=0/0; g:update(); assert(not g.active and not l.gateBlocked)
end)
test('turn change is observed and disarms', function()
    local e,l,g=fixture(); g:arm(); e.turn=3; g:update(); assert(not g.active)
    assert(e.logs[#e.logs].data.reason=='turn-changed' and e.logs[#e.logs].data.state.turn==3)
end)
test('logging is bounded while suppression continues', function()
    local e,l,g=fixture(); g:arm(); for i=1,500 do assert(g:handle('wheel')) end
    assert(#e.logs==130 and e.logs[130].kind=='input_gate_log_limit'); g:stop('manual',false)
    assert(e.logs[131].data.blockedEvents==500)
end)
test('installed keyboard and native mouse callbacks consume and retain hook', function()
    local e,l,g=fixture(); g:install(); assert(g.nativeHook.retained); g:arm()
    assert(e.modApi.events.onKeyPressing.fn(4)); assert(e.modApi.events.onKeyReleasing.fn(4))
    assert(e.native({type=function() return 1 end,mousebutton=function() return 1 end}))
    assert(e.native({type=function() return 2 end,mousebutton=function() return 1 end}))
    assert(not e.native({type=function() return 999 end}))
end)
test('callback exception is contained, current event consumed and lab released', function()
    local e,l,g=fixture(); g:install(); g:arm()
    assert(e.native({type=function() error('bad event') end})); assert(not g.active and not l.gateBlocked)
    assert(e.logs[#e.logs].kind=='input_gate_error')
end)
test('failed logger never throws into the native hook', function()
    local e,l=fixture(); local g=module.new(e,l,function() error('logger') end,function() return {},true end)
    g:install(); assert(g:arm()); assert(e.modApi.events.onKeyPressing.fn(2)); g:stop('manual',true)
end)
print('Input gate contracts: '..passed..' passed.')
