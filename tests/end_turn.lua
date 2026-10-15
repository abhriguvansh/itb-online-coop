local M=dofile('mod/scripts/end_turn.lua')
local passed=0
local function test(name,fn) local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function fixture()
    local e=dofile('tests/fixtures/movement.lua')('ui')
    e.TEAM_ENEMY=6;e.busy=0;e.ready=false;e.records={};e.clicks=0;e.frames=0
    e.screen={w=function()return 1920 end,h=function()return 1081 end};e.GetBoardScale=function()return 3 end
    e.Board.GetSelectedPawn=function()return nil end;e.Board.GetBusyState=function()return e.busy end
    e.sdlext.CurrentWindowRect={x=0,y=0,w=0,h=0}
    local n={sessionState=1,guardActive=true,releaseFailed=false,pressed=false}
    local native={info=function()return n end,begin=function()return true end,finish=function()end,
        sessionStop=function()n.sessionState=2 end,aim=function(x,y)n.mouseX=x-(e.offset or 0);n.mouseY=y-(e.offset or 0);n.cursorX=n.mouseX;n.cursorY=n.mouseY;return true end,
        click=function(x,y)e.clicks=e.clicks+1;e.lastClick={x=x,y=y};return not e.rejectClick end}
    local function capture()
        local pawns={};for _,id in ipairs({0,1,2,100})do pawns[#pawns+1]={localId=id,team=1,active=e.ready,movementSpent=false,dead=false,frozen=false} end
        return {pawns=pawns,unavailable=e.missing and {'field'} or {}}, e.busy==0
    end
    local lab=M.new(e,native,function(k,p)e.records[#e.records+1]={kind=k,payload=p}end,capture)
    local function tick() e.clock=e.clock+16;lab:draw();lab:missionUpdate();lab:update() end
    local function clickEnd()
        assert(lab:arm());lab:request();for i=1,8 do tick() end;assert(e.clicks==1)
    end
    local function phases()
        for i,name in ipairs({'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned','onNextTurn'}) do
            if i==3 then e.phase=6 end;if i==7 then e.phase=1;e.turn=3 end
            lab:phaseEvent(name,e.mission)
        end
    end
    return e,lab,tick,clickEnd,phases,n
end
test('native confirmation is retained and clicked only after recognized geometry',function()
    local e,l,t,start=fixture();start();assert(l.pending.stage=='wait-dialog')
    e.sdlext.CurrentWindowRect={x=803,y=683,w=315,h=60}
    for i=1,10 do t() end
    assert(e.clicks==2 and e.lastClick.x==890 and e.lastClick.y==565 and l.pending.stage=='wait-transition' and not l.fault)
end)
test('one-pixel native cursor rounding still permits the single click',function()
    local e,l,t,start=fixture();e.offset=1;start();assert(e.clicks==1 and not l.fault)
end)
test('four-unused-unit confirmation uses the separately observed native layout',function()
    local e,l,t,start=fixture();start();e.sdlext.CurrentWindowRect={x=779,y=683,w=362,h=60}
    for i=1,10 do t()end
    assert(e.clicks==2 and e.lastClick.x==890 and e.lastClick.y==565 and l.pending.stage=='wait-transition' and not l.fault)
end)
test('confirmed transition waits beyond UI deadline without retry or early completion',function()
    local e,l,t,start,phases,n=fixture();start()
    e.sdlext.CurrentWindowRect={x=803,y=683,w=315,h=60}
    for i=1,10 do t() end
    e.clock=5000;e.ready=true;t()
    assert(l.pending and not l.fault and n.sessionState==1 and e.clicks==2)
    phases();t();assert(not l.pending and not l.fault and e.clicks==2)
end)
test('confirmed transition with no hooks still times out protected without retry',function()
    local e,l,t,start,_,n=fixture();start()
    e.sdlext.CurrentWindowRect={x=803,y=683,w=315,h=60}
    for i=1,10 do t() end
    e.clock=61000;t();t()
    assert(l.fault and n.sessionState==2 and e.clicks==2)
end)
test('unknown modal is never clicked and timeout latches protection',function()
    local e,l,t,start,_,n=fixture();start();e.sdlext.CurrentWindowRect={x=765,y=385,w=390,h=219}
    t();assert(e.clicks==1);e.clock=5000;t();assert(l.fault and n.sessionState==2 and e.clicks==1)
end)
test('idle and restored allowances cannot complete without phase hooks',function()
    local e,l,t,start=fixture();start();e.ready=true
    for i=1,10 do t() end;assert(l.pending and not l.fault)
end)
test('player hook requires later update and restored allowances',function()
    local e,l,t,start,phases=fixture();start();phases();assert(not l.fault)
    l:update();assert(l.pending);e.ready=true;l:draw();l:update();assert(l.pending);e.ready=false;t();assert(l.pending)
    e.ready=true;t();assert(not l.pending and not l.fault)
end)
test('busy board still blocks after complete hook sequence',function()
    local e,l,t,start,phases=fixture();start();phases();e.ready=true;e.busy=6;t();assert(l.pending)
    e.busy=0;t();assert(not l.pending)
end)
test('queued loader callbacks still block admission',function()
    local e,l,t,start,phases=fixture();start();phases();e.ready=true;e.modApi.runLaterQueue={function()end};t();assert(l.pending)
    e.modApi.runLaterQueue={};t();assert(not l.pending)
end)
test('missing or reordered phase hook fails closed',function()
    local e,l,t,start,_,n=fixture();start();l:phaseEvent('onPostEnvironment',e.mission)
    assert(l.fault and n.sessionState==2);t();assert(e.clicks==1)
end)
test('wrong team or unexpected turn cannot become player completion',function()
    local e,l,_,start=fixture();start();l:phaseEvent('onPreEnvironment',e.mission);l:phaseEvent('onPostEnvironment',e.mission)
    l:phaseEvent('onNextTurn',e.mission);assert(l.fault)
end)
test('phase timeout does not retry End Turn',function()
    local e,l,t,start,_,n=fixture();start();l:phaseEvent('onPreEnvironment',e.mission);e.clock=61000;t()
    assert(l.fault and n.sessionState==2 and e.clicks==1)
end)
test('click uncertainty does not retry',function()
    local e,l,t,_,_,n=fixture();e.rejectClick=true;assert(l:arm());l:request();for i=1,20 do t()end
    assert(l.fault and n.sessionState==2 and e.clicks==1)
end)
test('missing observation field cannot admit next phase',function()
    local e,l,t,start,phases=fixture();start();phases();e.ready=true;e.missing=true;t();assert(l.fault)
end)
test('guard loss before End Turn refuses dispatch',function()
    local e,l,_,_,_,n=fixture();n.sessionState=2;assert(not l:arm() and e.clicks==0)
end)
test('repeat mode renews only after the complete observed phase boundary',function()
    local e,l,t,start,phases=fixture();l.repeatedTurns=true;start()
    assert(not l:arm());e.ready=true;phases();t();assert(not l.pending and l.completedTurn==3)
    assert(l:arm());l:request();assert(l.pending.turn==3 and l.completedTurn==nil)
    assert(not l:arm());for i=1,8 do t()end
    local events={'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned','onNextTurn'}
    for i,name in ipairs(events)do
        if i==3 then e.phase=6 end;if i==7 then e.phase=1;e.turn=4 end
        l:phaseEvent(name,e.mission)
    end
    t();assert(not l.fault and not l.pending and l.completedTurn==4 and e.clicks==2)
end)
test('repeat mode cannot jump turns or recover uncertain execution',function()
    local e,l,t,start,phases=fixture();l.repeatedTurns=true;start();e.ready=true;phases();t()
    e.turn=4;assert(not l:arm());e.turn=3;l.fault=true;assert(not l:arm())
end)
print('Protected End Turn contracts: '..passed..' passed (mocked engine/native input).')
