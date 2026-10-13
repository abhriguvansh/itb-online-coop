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
    e.Board={GetSelectedPawn=function()return e.selected end}
    e.pawn={GetId=function()return 2 end,GetArmedWeaponId=function()return 0 end}
    n.aims={}
    n.aim=function(x,y)n.x,n.y=x,y;n.aims[#n.aims+1]={x=x,y=y};return true end
    n.info=function()return {abi='itb-win32-click-v1',mouseX=n.x,mouseY=n.y,cursorX=n.x,cursorY=n.y}end
    n.begin=function()n.begins=n.begins+1;return true end
    n.click=function(x,y)n.calls[#n.calls+1]={x=x,y=y};return true,2 end
    n.finish=function()n.finishes=n.finishes+1 end
    local b=module.new(e,n,function(k,v)e.logs[#e.logs+1]={kind=k,value=v}end)
    local c={pawnId=2,from={x=0,y=3},to={x=0,y=2}}
    return e,n,b,c,function()return e.valid,'stale-command'end
end
test('selection must be observed before exactly one destination submission',function()
    local e,n,b,c,v=fixture();b:start(c,v);assert(#n.calls==0);b:update();assert(#n.calls==0);e.clock=100;b:update();assert(#n.calls==0)
    assert(#n.aims==2 and n.aims[1].x==712 and n.aims[2].x==708)
    e.clock=200;b:update();assert(#n.calls==1)
    e.selected=e.pawn;b:update();e.clock=300;b:update();assert(#n.calls==1)
    e.clock=400;b:update();assert(#n.calls==2 and b.phase=='submitted' and #n.aims==4)
    b:update();assert(#n.calls==2);b:stop();assert(b.phase=='off' and n.finishes==1)
end)
test('already selected actor needs only destination click',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn;b:start(c,v);assert(#n.calls==0);e.clock=100;b:update();assert(#n.calls==0);e.clock=200;b:update();assert(#n.calls==1)
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
    e.clock=100;b:update();e.clock=200;n.click=function()n.calls[#n.calls+1]={};return false,1 end
    assert(not pcall(function()b:update()end));assert(b.phase=='submitted' and #n.calls==1)
    b:update();assert(#n.calls==1)
end)
test('uncalibrated routes and layouts cannot arm native input',function()
    for _,change in ipairs({'route','width','height','scale'}) do
        local e,n,b,c,v=fixture()
        if change=='route' then c.to={x=1,y=3}
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
print('UI bridge contracts: '..passed..' passed.')
