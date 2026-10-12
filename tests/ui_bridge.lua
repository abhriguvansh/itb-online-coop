local module=dofile('mod/scripts/ui_bridge.lua')
local passed=0
local function test(name,fn)local ok,err=pcall(fn);assert(ok,name..': '..tostring(err));passed=passed+1 end
local function fixture()
    local e={selected=nil,width=1920,height=1080,scale=2,valid=true,clock=0,roundtrip=true,logs={}}
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
    e.pawn={GetId=function()return 2 end,GetArmedWeaponId=function()return -1 end}
    n.aim=function()return true end
    n.info=function()return {abi='itb-sdl-click-v1'}end
    n.begin=function()n.begins=n.begins+1;return true end
    n.click=function(x,y)n.calls[#n.calls+1]={x=x,y=y};return true,2 end
    n.finish=function()n.finishes=n.finishes+1 end
    local b=module.new(e,n,function(k,v)e.logs[#e.logs+1]={kind=k,value=v}end)
    local c={pawnId=2,from={x=0,y=3},to={x=0,y=2}}
    return e,n,b,c,function()return e.valid,'stale-command'end
end
test('selection must be observed before exactly one destination submission',function()
    local e,n,b,c,v=fixture();b:start(c,v);assert(#n.calls==0);b:update();assert(#n.calls==0);e.clock=100;b:update();assert(#n.calls==1)
    e.selected=e.pawn;b:update();e.clock=200;b:update();assert(#n.calls==2 and b.phase=='submitted')
    b:update();assert(#n.calls==2);b:stop();assert(b.phase=='off' and n.finishes==1)
end)
test('already selected actor needs only destination click',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn;b:start(c,v);assert(#n.calls==0);e.clock=100;b:update();assert(#n.calls==1)
end)
for _,change in ipairs({'valid','roundtrip','width','scale','weapon'}) do
    test('reject changed '..change..' before destination',function()
        local e,n,b,c,v=fixture();b:start(c,v);e.clock=100;b:update();e.selected=e.pawn;b:update();e.clock=200
        if change=='valid' then e.valid=false elseif change=='roundtrip' then e.roundtrip=false
        elseif change=='width' then e.width=1280 elseif change=='scale' then e.scale=3
        else e.pawn.GetArmedWeaponId=function()return 1 end end
        assert(not pcall(function()b:update()end) and #n.calls==1)
    end)
end
test('partial queue acceptance is uncertain and never retried',function()
    local e,n,b,c,v=fixture();e.selected=e.pawn;b:start(c,v)
    e.clock=100;n.click=function()n.calls[#n.calls+1]={};return false,1 end
    assert(not pcall(function()b:update()end));assert(b.phase=='submitted' and #n.calls==1)
    b:update();assert(#n.calls==1)
end)
test('all board corners roundtrip across supported screen layouts',function()
    for _,layout in ipairs({{1280,720,1},{1920,1080,2},{2560,1440,3}}) do
        for _,tile in ipairs({{0,0},{7,0},{0,7},{7,7}}) do
            local e,n,b,c,v=fixture();e.width,e.height,e.scale=layout[1],layout[2],layout[3]
            c.from={x=tile[1],y=tile[2]};c.to=c.from;b:start(c,v);e.clock=100;b:update();assert(#n.calls==1)
        end
    end
end)
test('missing native module cannot submit',function()
    local e,n,b,c,v=fixture();b=module.new(e,nil,function()end)
    assert(not pcall(function()b:start(c,v)end));b:stop();assert(#n.calls==0)
end)
print('UI bridge contracts: '..passed..' passed.')
