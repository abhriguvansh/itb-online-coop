local M=dofile('mod/scripts/mission_completion.lua')
local json=dofile('mod/scripts/json.lua')
local function fixture()
    local e={clock=0,Profile={visible_name='ITB_Coop_Probe'},RegionData={iBattleRegion=2},TEAM_ENEMY=6}
    local mission={ID='Mission_Artillery'};e.mission=mission;e.state='Mission'
    e.modApi={elapsedTime=function()return e.clock end,getCurrentProfile=function()return 'Alpha' end,getGameState=function()return e.state end,runLaterQueue={}}
    e.GetCurrentMission=function()return e.mission end
    e.Board={GetBusyState=function()return e.busy or 0 end};e.screen={w=function()return 1920 end,h=function()return 1081 end}
    e.sdlext={CurrentWindowRect={}}
    local n={guardActive=true,sessionState=1,releaseFailed=false,pressed=false,intentSerial=0,armed=false}
    local native={info=function()return n end,begin=function()return true end,finish=function()end}
    local clicks={};native.aim=function(x,y)n.mouseX=x;n.mouseY=y;n.cursorX=x;n.cursorY=y;return true end
    native.click=function(x,y)clicks[#clicks+1]={x=x,y=y};return true end
    local sent={};local wire={repeatedTurns=true,send=function(_,m)sent[#sent+1]=m end}
    local s={terminal={id='end-turn-16',revision=16,phase='player4'},revision=16}
    s.stop=function(_,reason)s.stopped=true;s.reason=reason end
    s.finishTerminal=function()s.revision=17 end
    local data={GameData={network=2,current={}},SquadData={money=1},RegionData={region2={state=2,mission='',objectives={}}}}
    for i=0,2 do data.GameData.current['pilot'..i]={id='pilot'..i,exp=i,level=0} end
    for i=0,1 do data.RegionData.region2.objectives[tostring(i)]={text=i==0 and 'Mission_Artillery_Obj' or 'Bonus_Simple_Asset',param1='',param2='',value=1,potential=1,category=i} end
    e.ReadSaveData=function()return data end
    local r=M.runtime({env=e,native=native,json=json,wire=wire,session=function()return s end,
        emit=function()end,capture=function()return {schema='itb-observation-v1',unavailable={},pawns={}},true end})
    local fx={AddScript=function(_,script)assert(script=='ITBCoopProtectedMissionTail()')end}
    local function frame(kind,witness)return {kind=kind,peer='-',id='end-turn-16',revision=16,phase='player4',witness=witness}end
    local function tick(count)for i=1,count or 1 do e.clock=e.clock+20;r:update()end end
    return e,r,s,n,sent,clicks,fx,frame,tick,mission
end
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
