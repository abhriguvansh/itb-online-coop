local module=dofile('mod/scripts/undo_move.lua')
local fixture=dofile('tests/fixtures/movement.lua')
local json=dofile('mod/scripts/json.lua')
local passed=0
local function test(name,fn)local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function make()
    local e,lab=fixture('ui');e.pawn.position={x=1,y=2};e.pawn.spent=true;e.busy=0;e.submissions=0;e.released=true
    e.Board.GetBusyState=function()return e.busy end
    local function capture()return {unavailable=json.array(),position=e.pawn.position,health=e.pawn.health,spent=e.pawn.spent},e.busy==0 end
    local c={pawnId=2,from={x=1,y=2},to={x=1,y=3},turn=2,restoreWitness=json.encode({unavailable=json.array(),position={x=1,y=3},health=3,spent=false})}
    local b={phase='off',start=function(self,command,validate)
        assert(command.undo and validate());e.submissions=e.submissions+1;self.phase='submitted';return true
    end,update=function()end,submissionReleased=function()return e.released end,stop=function(self)self.phase='off'end}
    local u=module.new(e,lab,{active=false},function(k,p)e.logs[#e.logs+1]={kind=k,payload=p}end,capture,json);u.bridge=b
    local function hook()e.pawn.position={x=1,y=3};e.pawn.spent=false;u:event(e.mission,e.pawn,{x=1,y=2})end
    return e,u,c,hook
end
test('matching hook needs later draw, update, release and idle before restored observation',function()
    local e,u,c,hook=make();assert(u:arm(c));assert(u:request(c));hook();u:update();assert(u.pending)
    u:draw();u:update();assert(u.pending);u:missionUpdate();e.released=false;u:update();assert(u.pending)
    e.released=true;e.busy=1;u:update();assert(u.pending);e.busy=0;e.modApi.runLaterQueue={pending=true};u:update();assert(u.pending)
    e.modApi.runLaterQueue={};u:update();assert(not u.pending and not u.fault and e.submissions==1)
end)
test('unchanged idle samples without the Undo hook never complete or retry',function()
    local e,u,c=make();assert(u:arm(c));u:request(c)
    for i=1,4 do e.clock=i*100;u:draw();u:missionUpdate();u:update();assert(u.pending)end
    e.clock=15000;u:update();assert(u.fault and e.submissions==1)
end)
test('restored actor alone cannot hide a changed observed board',function()
    local e,u,c,hook=make();assert(u:arm(c));u:request(c);hook();e.pawn.health=2;u:draw();u:missionUpdate();u:update()
    assert(u.fault and u.pending and e.submissions==1)
end)
test('wrong, duplicate and unsolicited hooks cannot complete',function()
    local e,u,c,hook=make();assert(not pcall(function()u:event(e.mission,e.pawn,{x=1,y=2})end));assert(u:arm(c));u:request(c)
    assert(not pcall(function()u:event(e.mission,e.pawn,{x=7,y=7})end));hook();assert(not pcall(hook))
end)
test('wrong native undo origin and stale phase reject before input',function()
    local e,u,c=make();e.pawn.GetUndoLoc=function()return {x=0,y=0}end;assert(not u:arm(c) and e.submissions==0)
    e,u,c=make();e.turn=3;assert(not u:arm(c) and e.submissions==0)
    e,u,c=make();e.pawn.spent=false;assert(not u:arm(c) and e.submissions==0)
end)
test('failed submission and unexpected skill are uncertain and never repeated',function()
    local e,u,c=make();u.bridge.start=function()e.submissions=e.submissions+1;error('possibly submitted')end
    assert(u:arm(c));assert(not u:request(c));assert(u.fault);u:update();assert(e.submissions==1)
    e,u,c=make();assert(u:arm(c));u:request(c);assert(not pcall(function()u:skillEvent()end))
end)
print('Protected Undo outcome contracts: '..passed..' passed (engine/input doubles only).')
