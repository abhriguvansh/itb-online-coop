local module=dofile('mod/scripts/ui_bridge.lua')
local passed=0
local function test(name,fn)local ok,err=pcall(fn);assert(ok,name..': '..tostring(err));passed=passed+1 end
local function fixture()
    local e={selected=nil,width=1920,height=1081,scale=3,valid=true,clock=0,roundtrip=true,logs={}}
    local n={calls={},begins=0,finishes=0}
    e.modApi={elapsedTime=function()return e.clock end}
    e.screen={w=function()return e.width end,h=function()return e.height end}
    e.GetBoardScale=function()return e.scale end
    e.getScreenRefs=function()return {x=e.width/2,y=e.height/2-168*e.scale+30-10*e.scale},nil,nil,28,21 end
    e.screenPointToTile=function(p)
        if not e.roundtrip then return nil end
        local o=e.getScreenRefs();local dx=(p.x-o.x)/(28*e.scale);local dy=(p.y-o.y)/(21*e.scale)
        return {x=math.floor((dy+dx)/2),y=math.floor((dy-dx)/2)}
    end
    e.Board={GetSelectedPawn=function()return e.selected end,GetPawn=function()return e.pawn end}
    e.sdl={events={mousebuttonup=1026},eventHook=function(fn)e.releaseHook=fn;return fn end}
    e.release=function(button)e.releaseHook({type=function()return 1026 end,mousebutton=function()return button or 1 end})end
    e.pawn={GetId=function()return 2 end,GetArmedWeaponId=function()return 0 end}
    n.aims={}
    n.aim=function(x,y)n.x,n.y=x,y;n.aims[#n.aims+1]={x=x,y=y};return true end
    n.info=function()return {abi='itb-win32-click-v3',mouseX=n.x,mouseY=n.y,cursorX=n.x,cursorY=n.y}end
    n.begin=function()n.begins=n.begins+1;return true end
    n.beginAttack=function()n.attackBegins=(n.attackBegins or 0)+1;return true end
    n.click=function(x,y)n.calls[#n.calls+1]={x=x,y=y};if not e.delayRelease then e.release() end;return true,2 end
    n.finish=function()n.finishes=n.finishes+1 end
    local b=module.new(e,n,function(k,v)e.logs[#e.logs+1]={kind=k,value=v}end)
    local c={pawnId=2,from={x=0,y=3},to={x=0,y=2}}
    e.preview=function()b:observePreview(e.pawn,'Move',c.from,c.to)end
    return e,n,b,c,function()return e.valid,'stale-command'end
end
test('selection must be observed before exactly one destination submission',function()
    local e,n,b,c,v=fixture();b:start(c,v);assert(#n.calls==0);b:update();assert(#n.calls==0);e.clock=100;b:update();assert(#n.calls==0)
    assert(#n.aims==2 and n.aims[1].x==712 and n.aims[2].x==708)
    e.clock=200;b:update();assert(#n.calls==1)
    e.selected=e.pawn;b:update();e.clock=300;b:update();assert(#n.calls==1)
    e.preview();e.clock=400;b:update();assert(#n.calls==2 and b.phase=='submitted' and #n.aims==4)
    b:update();assert(#n.calls==2);b:stop();assert(b.phase=='off' and n.finishes==1)
end)
test('submitted native release must reach SDL before destination aiming',function()
    local e,n,b,c,v=fixture();e.delayRelease=true;b:start(c,v)
    e.clock=100;b:update();e.clock=200;b:update();e.selected=e.pawn
    -- Native pressed=false is insufficient: SDL may still report held input.
    local aimed=#n.aims
    e.clock=300;b:update();e.clock=400;b:update()
    assert(#n.calls==1 and #n.aims==aimed)
    e.release(3);b:update();assert(#n.aims==aimed)
    e.release();b:update();assert(#n.aims==aimed+1 and #n.calls==1)
    e.clock=500;b:update();e.preview();e.clock=600;b:update()
    assert(#n.calls==2 and b.phase=='submitted')
end)
test('already selected actor needs only destination click',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn;b:start(c,v);assert(#n.calls==0);e.clock=100;b:update();assert(#n.calls==0);e.preview();e.clock=200;b:update();assert(#n.calls==1)
end)
test('Undo uses the global button without actor selection and waits for actual SDL release',function()
    local e,n,b,c,v=fixture();c.undo=true;e.pawn.IsUndoPossible=function()return true end
    e.selected={GetId=function()return 0 end,GetArmedWeaponId=function()return 0 end}
    b:start(c,v);e.clock=100;b:update();assert(#n.calls==0);e.delayRelease=true;e.clock=200;b:update()
    assert(#n.calls==1 and n.calls[1].x==347 and n.calls[1].y==180 and b.phase=='submitted')
    assert(not b:submissionReleased());e.release();b:update();assert(b:submissionReleased())
    b:update();assert(#n.calls==1)
end)
test('Undo rejects lost native availability before its one button click',function()
    local e,n,b,c,v=fixture();c.undo=true;e.selected=e.pawn;e.pawn.IsUndoPossible=function()return false end
    b:start(c,v);e.clock=100;b:update();e.clock=200;assert(not pcall(function()b:update()end) and #n.calls==0)
end)
for _,change in ipairs({'valid','roundtrip','width','scale','weapon'}) do
    test('reject changed '..change..' before destination',function()
        local e,n,b,c,v=fixture();b:start(c,v);e.clock=100;b:update();e.clock=200;b:update();e.selected=e.pawn;b:update();e.clock=300;b:update();e.clock=400
        if change=='valid' then e.valid=false elseif change=='roundtrip' then e.roundtrip=false
        elseif change=='width' then e.width=1280 elseif change=='scale' then e.scale=2
        else e.pawn.GetArmedWeaponId=function()return 1 end end
        assert(not pcall(function()b:update()end) and #n.calls==1)
    end)
end
test('partial queue acceptance is uncertain and never retried',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn;b:start(c,v)
    e.clock=100;b:update();e.preview();e.clock=200;n.click=function()n.calls[#n.calls+1]={};return false,1 end
    assert(not pcall(function()b:update()end));assert(b.phase=='submitted' and #n.calls==1)
    b:update();assert(#n.calls==1)
end)
test('UI-overlapping endpoints and uncalibrated layouts cannot arm native input',function()
    for _,change in ipairs({'route','width','height','scale'}) do
        local e,n,b,c,v=fixture()
        if change=='route' then c.to={x=0,y=0}
        elseif change=='width' then e.width=1280
        elseif change=='height' then e.height=720
        else e.scale=2 end
        assert(not pcall(function()b:start(c,v)end));assert(n.begins==0 and #n.calls==0)
    end
end)
test('one-pixel rounding is accepted only with agreeing cursor readings',function()
    local e,n,b,c,v=fixture();b:start(c,v);n.x,n.y=n.x-1,n.y-1;e.clock=100;b:update();assert(#n.calls==0)
    n.x,n.y=n.x-1,n.y-1;e.clock=200;b:update();assert(#n.calls==1)
end)
test('larger cursor error waits without submitting and can settle later',function()
    local e,n,b,c,v=fixture();b:start(c,v);local x,y=n.x,n.y;n.x=x-2;e.clock=100;b:update();assert(#n.calls==0)
    n.x,n.y=x,y;b:update();assert(#n.calls==0);e.clock=200;b:update();assert(#n.calls==1)
end)
test('disagreeing native and SDL readings cannot submit',function()
    local e,n,b,c,v=fixture();b:start(c,v)
    n.info=function()return {mouseX=n.x,mouseY=n.y,cursorX=n.x+1,cursorY=n.y}end
    e.clock=100;b:update();assert(#n.calls==0)
end)
test('attack and repair selections cannot arm native input',function()
    for _,weapon in ipairs({1,2,50,99}) do
        local e,n,b,c,v=fixture();e.selected=e.pawn;e.pawn.GetArmedWeaponId=function()return weapon end
        assert(not pcall(function()b:start(c,v)end) and n.begins==0 and #n.calls==0)
    end
end)

test('a selected actor without Move armed cannot receive a destination click',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn;e.pawn.GetArmedWeaponId=function()return -1 end
    b:start(c,v);e.clock=100;b:update();e.clock=200
    assert(not pcall(function()b:update()end) and #n.calls==0)
end)

test('failed release prevents every subsequent submission',function()
    local e,n,b,c,v=fixture();b:start(c,v)
    n.info=function()return {releaseFailed=true}end
    assert(not pcall(function()b:update()end) and #n.calls==0)
end)

test('missing native module cannot submit',function()
    local e,n,b,c,v=fixture();b=module.new(e,nil,function()end)
    assert(not pcall(function()b:start(c,v)end));b:stop();assert(#n.calls==0)
end)
test('destination is never clicked without a fresh native preview',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn
    b:observePreview(e.pawn,'Move',c.from,c.to) -- A stale pre-session preview is ignored.
    b:start(c,v);e.clock=100;b:update();e.clock=200;b:update()
    assert(#n.calls==0 and b.phase=='aim-destination')
    b:observePreview(e.pawn,'Prime_Punch',c.from,c.to);b:update();assert(#n.calls==0)
    e.preview();b:update();assert(#n.calls==1)
end)

for _,field in ipairs({'pawn','from','to'}) do
    test('mismatching native preview rejects '..field,function()
        local e,n,b,c,v=fixture();e.selected=e.pawn;b:start(c,v);e.clock=100;b:update()
        local pawn,from,to=e.pawn,c.from,c.to
        if field=='pawn' then pawn={GetId=function()return 1 end}
        elseif field=='from' then from={x=1,y=3} else to={x=1,y=2} end
        b:observePreview(pawn,'Move',from,to);e.clock=200
        assert(not pcall(function()b:update()end) and #n.calls==0)
    end)
end

test('a different actor and longer route require the same native preview guard',function()
    local e,n,b,c,v=fixture();c.pawnId=1;c.from={x=1,y=5};c.to={x=1,y=2}
    e.pawn.GetId=function()return 1 end;e.selected=e.pawn
    b:start(c,v);e.clock=100;b:update();e.clock=200;b:update();assert(#n.calls==0)
    e.preview();b:update();assert(#n.calls==1 and b.phase=='submitted')
end)

test('diagnostic guard records expiry and cannot silently stay watched',function()
    local e,n,b=fixture();local active=false
    n.info=function()return {abi='itb-win32-click-v3',guardActive=active,guardRemainingMs=active and 20000 or 0}end
    n.guardBegin=function()active=true;return true end
    n.guardEnd=function()active=false end
    b:lock();assert(b.guardWatching and e.logs[1].kind=='ui_guard_start')
    b:pollGuard();assert(b.guardStatus=='Native input blocked: 20s')
    b:stop();assert(active) -- Finishing a move does not end the diagnostic lease.
    b:unlock();assert(not b.guardWatching and not b.guardStatus and e.logs[2].kind=='ui_guard_end')
end)
test('failed native guard arming never starts a command',function()
    local e,n,b=fixture();n.guardBegin=function()return false,'held-input'end
    assert(not pcall(function()b:lock()end));assert(not b.guardWatching and #n.calls==0 and n.begins==0)
end)
test('guard cannot overlap an already active command',function()
    local e,n,b,c,v=fixture();b:start(c,v)
    n.guardBegin=function()error('must not reach native lock')end
    assert(not pcall(function()b:lock()end) and not b.guardWatching and #n.calls==0)
end)
test('session heartbeat is explicit and stopped state never auto-resumes',function()
    local e,n,b=fixture();local state=0;local pulses=0
    n.info=function()return {abi='itb-win32-click-v3',sessionState=state}end
    n.sessionBegin=function()state=1;return true end
    n.sessionPulse=function()pulses=pulses+1;return state==1 end
    b:startSession(false);b:pollSession();assert(pulses==1 and b.sessionWatching)
    state=2;b:pollSession();assert(b.sessionWatching and b.sessionStatus=='SESSION STOPPED - Esc exits')
    state=3;b:pollSession();assert(not b.sessionWatching and b.sessionStatus=='Session ended - restart game')
    assert(#e.logs==3 and #n.calls==0)
end)
test('timeout diagnostic withholds heartbeat rather than simulating a native failure',function()
    local e,n,b=fixture();n.sessionBegin=function()return true end
    n.sessionPulse=function()error('must withhold heartbeat')end
    n.info=function()return {abi='itb-win32-click-v3',sessionState=1}end
    b:startSession(true);b:pollSession();assert(b.sessionWatching and not b.sessionHeartbeat)
end)
test('failed command or context stops protected session but success keeps protection',function()
    local e,n,b=fixture();local stopped=0;n.sessionStop=function()stopped=stopped+1 end
    b:stop(true);assert(stopped==0 and n.finishes==1)
    b:stop();assert(stopped==1 and n.finishes==2)
end)
test('session cannot overlap a watched diagnostic guard',function()
    local e,n,b=fixture();b.guardWatching=true
    n.sessionBegin=function()error('overlap reached native')end
    assert(not pcall(function()b:startSession(false)end))
end)
test('basic weapon requires selection then armed slot and fresh weapon preview',function()
 local e,n,b,c,v=fixture();c.weapon='Ranged_Artillerymech';e.pawn.GetArmedWeaponId=function()return -1 end;e.pawn.IsUndoPossible=function()return false end
 b:start(c,v);e.clock=100;b:update();e.clock=200;b:update();assert(#n.calls==1)
 e.selected=e.pawn;b:update();e.clock=300;b:update();e.clock=400;b:update();assert(#n.calls==2)
 e.pawn.GetArmedWeaponId=function()return 1 end;b:update();e.clock=500;b:update();e.clock=600;b:update();assert(#n.calls==2)
 b:observePreview(e.pawn,c.weapon,c.from,c.to);b:update();assert(#n.calls==3 and b.phase=='submitted')
 b:update();assert(#n.calls==3)
end)
test('older native bridge cannot silently use movement allowance for an attack',function()
 local e,n,b,c,v=fixture();c.weapon='Prime_Punchmech';n.beginAttack=nil
 assert(not pcall(function()b:start(c,v)end) and n.begins==0 and #n.calls==0)
end)
print('UI bridge contracts: '..passed..' passed.')
do
 local e,n,b,c,v=fixture();c.weapon='Skill_Repair';c.weaponIndex=50;c.to=c.from;e.pawn.IsUndoPossible=function()return false end
 b:start(c,v);e.clock=100;b:update();e.clock=200;b:update();assert(#n.calls==1)
 e.selected=e.pawn;b:update();e.clock=300;b:update();e.clock=400;b:update();assert(n.calls[2].x==220 and n.calls[2].y==920)
 e.pawn.GetArmedWeaponId=function()return 50 end;b:update();e.clock=500;b:update();e.clock=600;b:update();assert(#n.calls==2)
 b:observePreview(e.pawn,'Skill_Repair',c.from,c.to);b:update();assert(#n.calls==3 and b.phase=='submitted');b:update();assert(#n.calls==3)
end
print('Repair uses native index 50, observed selection and a fresh self preview before one target click (UI doubles).')
