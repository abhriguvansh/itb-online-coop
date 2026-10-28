local M=dofile('mod/scripts/mission_completion.lua')
local json=dofile('mod/scripts/json.lua')
local function fixture()
    local e={clock=0,Profile={visible_name='ITB_Coop_Probe'},RegionData={iBattleRegion=2},TEAM_ENEMY=6}
    local mission={ID='Mission_Artillery'};e.mission=mission;e.state='Mission'
    e.modApi={elapsedTime=function()return e.clock end,getCurrentProfile=function()return 'Alpha' end,getGameState=function()return e.state end,runLaterQueue={}}
    e.GetCurrentMission=function()return e.mission end
    e.Board={GetBusyState=function()return e.busy or 0 end};e.screen={w=function()return 1920 end,h=function()return 1081 end}
    e.sdlext={CurrentWindowRect={},getSurface=function()
        return setmetatable({wasDrawn=function()return e.Board and e.victory~=false or e.promotion==true end},{__index=function(_,key)
            if e.Board then return key=='x' and (e.victoryX or 959) or key=='y' and (e.victoryY or 653) or nil end
            return key=='x' and (e.portraitX or 810) or key=='y' and 471 or nil
        end})
    end}
    local releaseHook
    e.sdl={events={mousebuttonup=1,mousebuttondown=2,mousemotion=3},mouse={x=function()return 0 end,y=function()return 0 end},eventHook=function(fn)releaseHook=fn;return fn end}
    e.release=function()releaseHook({type=function()return 1 end,mousebutton=function()return 1 end})end
    local n={guardActive=true,sessionState=1,releaseFailed=false,pressed=false,intentSerial=0,armed=false}
    local native={info=function()return n end,begin=function()return true end,finish=function()end}
    local clicks={};e.aims=0;native.aim=function(x,y)e.aims=e.aims+1;n.mouseX=x;n.mouseY=y;n.cursorX=x;n.cursorY=y;return true end
    native.click=function(x,y)clicks[#clicks+1]={x=x,y=y};if not e.deferRelease then e.release() end;return true end
    local sent={};local wire={repeatedTurns=true,send=function(_,m)sent[#sent+1]=m end}
    local s={terminal={id='end-turn-16',revision=16,phase='player4'},revision=16}
    s.stop=function(_,reason)s.stopped=true;s.reason=reason end
    s.finishTerminal=function()s.revision=17 end
    local data={GameData={network=2,current={}},SquadData={money=1},RegionData={region2={state=2,mission='',objectives={}}}}
    for i=0,2 do data.GameData.current['pilot'..i]={id='pilot'..i,exp=i,level=0,skill1=3,skill2=0} end
    for i=0,1 do data.RegionData.region2.objectives[tostring(i)]={text=i==0 and 'Mission_Artillery_Obj' or 'Bonus_Simple_Asset',param1='',param2='',value=1,potential=1,category=i} end
    e.ReadSaveData=function()return data end
    local r=M.runtime({env=e,native=native,json=json,wire=wire,session=function()return s end,
        emit=function()end,capture=function()return {schema='itb-observation-v1',unavailable={},pawns={}},true end})
    local fx={AddScript=function(_,script)assert(script=='ITBCoopProtectedMissionTail()')end}
    local function frame(kind,witness)return {kind=kind,peer='-',id='end-turn-16',revision=16,phase='player4',witness=witness}end
    local function tick(count)for i=1,count or 1 do e.clock=e.clock+20;r:update()end end
    return e,r,s,n,sent,clicks,fx,frame,tick,mission
end
for _,case in ipairs({{653,803},{688,839}}) do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture();e.victoryY=case[1]
    r:start(m,fx);e.ITBCoopProtectedMissionTail();tick(2)
    n.intentSerial=1;n.intentX=100;n.intentY=840;tick()
    r:receive(frame('RESULTCONTINUE',sent[1].witness));tick(6)
    assert(#clicks==1 and clicks[1].x==1325 and clicks[1].y==case[2],'observed result layout determines sole Continue target')
end
for _,change in ipairs({'missing','changed','unknown'}) do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture()
    r:start(m,fx);e.ITBCoopProtectedMissionTail();tick(2)
    n.intentSerial=1;n.intentX=100;n.intentY=840;tick()
    if change=='unknown' then e.victoryY=700 end
    local ok=pcall(function()r:receive(frame('RESULTCONTINUE',sent[1].witness))end)
    if change~='unknown' then
        assert(ok);if change=='missing' then e.victory=false else e.victoryY=688 end
        ok=pcall(function()tick(6)end)
    end
    assert(not ok and #clicks==0,'missing, changed or unknown result layout cannot dispatch Continue')
end
print('Native result layout contracts: two observed portrait positions, exact target, changed/missing/unknown refusal (doubles only).')
local function continued(e,r,n,sent,fx,frame,tick,m)
    r:start(m,fx);e.ITBCoopProtectedMissionTail();tick(2)
    n.intentSerial=1;n.intentX=100;n.intentY=840;tick()
    r:receive(frame('RESULTCONTINUE',sent[1].witness));tick(6)
    e.Board=nil;e.mission=nil;e.state='Island';r:context('onMissionChanged',nil,m);r:dismissed(m)
    e.clock=e.clock+2500
end
do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture();continued(e,r,n,sent,fx,frame,tick,m)
    e.promotion=true;e.deferRelease=true;tick(6)
    assert(#clicks==2 and clicks[2].x==984 and clicks[2].y==672,'observed panel gets one native acknowledgment')
    tick(10);assert(#clicks==2,'visible panel cannot be retried or bypassed with gear')
    e.promotion=false;local aims=e.aims;tick(6)
    assert(e.aims==aims,'portrait disappearance cannot substitute for actual SDL release')
    e.deferRelease=false;e.release();tick(5);assert(#clicks==2)
    e.clock=e.clock+2500;tick(6);assert(#clicks==3 and clicks[3].x==36)
end
do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture();continued(e,r,n,sent,fx,frame,tick,m)
    e.promotion=true;e.portraitX=959
    assert(not pcall(tick) and #clicks==1,'result portrait at a different position cannot authorize a promotion click')
end
do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture();continued(e,r,n,sent,fx,frame,tick,m)
    e.promotion=true;tick(1);e.promotion=false
    assert(not pcall(function()tick(6)end) and #clicks==1,'disappearance before the click stops without an acknowledgment')
end
do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture();continued(e,r,n,sent,fx,frame,tick,m)
    e.promotion=true;tick(6);e.promotion=false;tick(5);e.promotion=true;e.clock=e.clock+2500
    assert(not pcall(tick) and #clicks==2,'another promotion is unsupported and cannot be clicked blindly')
end
do
    local e=fixture();local data=e.ReadSaveData();data.GameData.current.pilot0.skill1=nil
    assert(not pcall(function()M.saved(e,2,json)end),'missing pilot skills cannot produce a complete result witness')
end
print('Observed promotion contracts: exact native portrait cue, one acknowledgment, real release, later disappearance, changed/repeated dialog refusal and saved skills (doubles only).')
do
    local e,r,_,_,sent,clicks,fx,_,tick,m=fixture();r:start(m,fx);tick(8)
    assert(#sent==0 and #clicks==0,'idle alone must never establish retreat completion')
    e.clock=120001;assert(not pcall(function()r:update()end),'missing tail must time out')
end
do
    local e,r,s,n,sent,clicks,fx,frame,tick,m=fixture();r:start(m,fx)
    assert(not r:allowsPreview({}))
    e.ITBCoopProtectedMissionTail();e.busy=1;tick(4);assert(#sent==0)
    e.busy=0;tick();assert(#sent==0 and r:status():find('Review results'))
    n.intentSerial=1;n.intentX=100;n.intentY=840;tick();assert(sent[1].type=='result_prepared' and #clicks==0)
    local ready=frame('RESULTCONTINUE',sent[1].witness);ready.revision=15
    assert(not pcall(function()r:receive(ready)end));ready.revision=16
    assert(not r:context('onGameExited') and not r:context('onMissionChanged',nil,m))
    r:receive(ready);assert(not pcall(function()r:receive(ready)end),'duplicate continue')
    tick(6);assert(#clicks==1 and clicks[1].x==1325)
    assert(r:allowsPreview({}) and not r:allowsPreview(m))
    e.Board=nil;e.mission=nil;e.state='Island'
    assert(r:context('onMissionChanged',nil,m));r:dismissed(m);tick(6);assert(#clicks==1)
    e.clock=e.clock+2500;tick(6)
    assert(#clicks==2 and clicks[2].x==36)
    e.sdlext.CurrentWindowRect={x=1005,y=290,w=275,h=500};tick(6)
    assert(#clicks==3 and clicks[3].x==808)
    assert(r:context('onGameExited'));e.state='Main_Menu'
    local read=e.ReadSaveData;local data=read();data.RegionData.region2.state=1
    tick(3);assert(#sent==1 and #clicks==3,'stale save must wait without another click')
    data.RegionData.region2.state=2;tick()
    assert(sent[2].type=='result_observed' and s.revision==16)
    local done=frame('RESULTDONE',sent[2].witness);done.witness='changed'
    assert(not pcall(function()r:receive(done)end));done.witness=sent[2].witness
    assert(r:receive(done) and s.revision==17 and sent[3].type=='complete')
    assert(not pcall(function()r:receive(done)end));tick(3);assert(#clicks==3)
end
do
    local e,r,_,n,_,_,fx,_,tick,m=fixture();r:start(m,fx);n.sessionState=2
    assert(not pcall(tick),'guard loss cannot complete result')
end
print('Mission result contracts: tail, dismissal, native menu commit, exact peer messages and no retries (engine doubles only).')

for _,variant in ipairs({'observed','unknown','changed'}) do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture()
    -- Exercise the complete result path, including the runtime's saved-objective gate.
    -- The fixture uses Artillery context; only the explicit full-mission gate is changed.
    local data=e.ReadSaveData()
    r=M.runtime({env=e,native={info=function()return n end,begin=function()return true end,
        finish=function()end,aim=function(x,y)n.mouseX=x;n.mouseY=y;n.cursorX=x;n.cursorY=y;return true end,
        click=function(x,y)clicks[#clicks+1]={x=x,y=y};e.release();return true end},json=json,
        wire={repeatedTurns=true,fullMission=true,send=function(_,v)sent[#sent+1]=v end},
        session=function()return {terminal={id='end-turn-16',revision=16,phase='player4'}} end,
        emit=function()end,capture=function()return {unavailable={},pawns={}},true end})
    data.RegionData.region1=data.RegionData.region2;e.RegionData.iBattleRegion=1;m.ID='Mission_Tides'
    local function step(count)for i=1,count or 1 do e.clock=e.clock+20;r:update()end end
    data.RegionData.region1.objectives['2']={text=variant=='unknown' and 'Pod_Success' or 'Pod_Failed',category=3,param1='',param2='',value=0,potential=1}
    if variant=='changed' then data.RegionData.region1.objectives['2'].category=2 end
    r:start(m,fx);e.ITBCoopProtectedMissionTail();step(2);n.intentSerial=1;n.intentX=100;n.intentY=840;step()
    r:receive(frame('RESULTCONTINUE',sent[1].witness));step(6)
    e.Board=nil;e.mission=nil;e.state='Island';r:context('onMissionChanged',nil,m);r:dismissed(m)
    e.clock=e.clock+2500;step(6);e.sdlext.CurrentWindowRect={x=1005,y=290,w=275,h=500};step(6)
    r:context('onGameExited');e.state='Main_Menu';step(3)
    assert((#sent==2)==(variant=='observed'),'only measured failed-pod saved objective can complete full-mission result')
end
do
    local e,r,_,n,sent,clicks,fx,frame,tick,m=fixture();r:start(m,fx)
    e.ITBCoopProtectedMissionTail();tick(2);n.intentSerial=1;n.intentX=100;n.intentY=840;tick()
    r:receive(frame('RESULTCONTINUE',sent[1].witness));tick(6)
    e.Board=nil;e.mission=nil;e.state='Island';r:context('onMissionChanged',nil,m);r:dismissed(m)
    e.clock=e.clock+2500;e.deferRelease=true;tick(6);assert(#clicks==2)
    e.sdlext.CurrentWindowRect={x=1005,y=290,w=275,h=500}
    local aims=e.aims;tick(8);assert(e.aims==aims and #clicks==2,'worker release is not SDL release')
    e.deferRelease=false;e.release();tick(6);assert(#clicks==3,'SDL release admits the next one-shot menu click')
end
