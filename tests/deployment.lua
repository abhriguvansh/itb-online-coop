local M=dofile('mod/scripts/deployment.lua');local json=dofile('mod/scripts/json.lua')
local function fixture()
    local e={TEAM_ENEMY=6,TEAM_PLAYER=1,TERRAIN_ROAD=0,TERRAIN_FOREST=6,Profile={visible_name='ITB_Coop_Probe'},clock=0}
    local d={in_progress=true,phase=0,[0]={state=0},[1]={state=1},[2]={state=1}}
    local mission={ID='Mission_Tides',deployment=d};e.GetCurrentMission=function()return mission end
    e.Point=function(x,y)return {x=x,y=y}end
    e.Game={GetTurnCount=function()return e.turn or 0 end,GetTeamTurn=function()return e.team or 6 end}
    e.screen={w=function()return 1920 end,h=function()return 1081 end}
    e.GetBoardScale=function()return 3 end;e.getScreenRefs=function()return {x=960,y=100},nil,nil,28,21 end
    e.screenPointToTile=function()return {x=1,y=4}end
    e.sdlext={isGame=function()return true end,isConsoleOpen=function()return false end}
    e.modApi={getCurrentProfile=function()return 'Alpha'end,getGameVersion=function()return '1.2.93'end,elapsedTime=function()return e.clock end}
    e.modApi.deployment={isDeploymentPhase=function()return d.in_progress end,isLandingPhase=function()return d.phase==1 end,
        getSelected=function()if e.selected~=nil then return e.selected end;for id=0,2 do if d[id].state==0 then return id end end end,getDeploymentZone=function()return {{x=1,y=4}}end}
    local types={[0]='PunchMech',[1]='TankMech',[2]='ArtiMech'};local ps={}
    for id=0,2 do
        local p={pos={x=-1,y=-1}};ps[id]=p
        p.GetSpace=function()return p.pos end;p.GetType=function()return types[id]end;p.IsDead=function()return false end
        p.IsBusy=function()return false end;p.GetPathProf=function()return 18 end
    end
    e.Board={GetPawn=function(_,v)return type(v)=='number' and ps[v] or nil end,IsValid=function()return true end,
        GetTerrain=function()return 0 end,GetItem=function()return ''end,IsBlocked=function()return e.blocked or false end,GetBusyState=function()return 0 end}
    for _,m in ipairs({'IsFire','IsAcid','IsSmoke','IsFrozen','IsSpawning','IsPod','IsCracked','IsEnvironmentDanger','IsDangerous','IsDangerousItem'})do e.Board[m]=function()return false end end
    e.sdl={events={mousebuttonup=2},eventHook=function(fn)e.hook=fn;return fn end}
    local events={};local n={guardActive=true,sessionState=1,releaseFailed=false,pressed=false};local clicks=0
    local native={info=function()return n end,begin=function()n.armed=true;return true end,
        aim=function(x,y)n.mouseX=x;n.mouseY=y;return true end,
        click=function()clicks=clicks+1;return not e.clickFailure end,finish=function()n.armed=false end,sessionStop=function()n.sessionState=2 end}
    local function capture()
        local a=json.array();for id=0,2 do a[#a+1]={localId=id,position={x=ps[id].pos.x,y=ps[id].pos.y},health=3,team=1,active=true,movementSpent=false,dead=false,frozen=false}end
        return M.capture(e,{pawns=a,gridPower=e.grid or 2,tiles=json.array(),unavailable=json.array()},json),true
    end
    local lab=M.new(e,native,function(k,v)events[#events+1]={event=k,payload=v}end,capture,json,function(turn)assert(turn==0);return e.spawnReady==true end)
    local c={pawnId=0,from={x=-1,y=-1},to={x=1,y=4}}
    local function tick()e.clock=e.clock+100;lab:draw();lab:missionUpdate();lab:update()end
    local function release()e.hook({type=function()return 2 end,mousebutton=function()return 1 end})end
    return e,lab,c,tick,release,ps,d,events,function()return clicks end
end
do
 local e,l,c,tick,release,ps,d,events,clicks=fixture()
 e.blocked=true;assert(not l:arm(c));e.blocked=false;e.selected=1;assert(not l:arm(c));e.selected=0
 assert(l:arm(c));assert(l:request(c));tick();tick();assert(clicks()==1)
 for _=1,5 do tick()end;assert(l.pending,'idle snapshots cannot finish a placement')
 ps[0].pos={x=1,y=4};d[0].state=2;e.selected=1
 l:event('onPawnDeployed',0);tick();assert(l.pending,'worker submission cannot replace SDL release delivery')
 release();tick();assert(not l.pending and not l.fault and events[#events].event=='deployment_postconditions_observed')
 assert(clicks()==1 and not l:arm(c),'committed placement cannot be repeated')
end
do
 local e,l,c,tick,_,_,_,_,clicks=fixture();assert(l:arm(c));l:request(c);e.grid=1;tick()
 assert(l.fault and clicks()==0,'changed precondition must stop before input')
end
do
 local e,l,c,tick,_,_,_,_,clicks=fixture();assert(l:arm(c));l:request(c);e.clickFailure=true;tick();tick()
 assert(l.fault and clicks()==1);tick();assert(clicks()==1,'uncertain click cannot retry')
end
do
 local e,l,c,tick=fixture();assert(l:arm(c));l:request(c);tick();tick();e.clock=15000;tick();assert(l.fault,'missing placement event must time out')
end
print('Deployment contracts passed: native order/legality, event plus later update/draw and actual release, changed-state stop, bounded uncertainty and no retries (engine doubles).')
do
 local e,l,_,tick,release,ps,d,events,clicks=fixture()
 for id=0,2 do ps[id].pos={x=1,y=3+id};d[id].state=2 end
 local c={launch=true};assert(l:arm(c));l:request(c);tick();tick();assert(clicks()==1);release()
 l:event('onLandingPhaseStart');d.phase=1
 for id=2,0,-1 do l:event('onPawnLanding',id);d[id].state=4;l:event('onPawnLanded',id)end
 d.phase=2;d.in_progress=false;l:event('onDeploymentPhaseEnd');e.turn=1;e.team=1
 for _=1,5 do tick()end;assert(l.pending,'landed and idle is insufficient')
 for _,name in ipairs({'onPreEnvironment','onPostEnvironment','onNextTurn','onVekSpawningEnd','onPreEnvPlanned','onPostEnvPlanned'})do l:phaseEvent(name,e.GetCurrentMission())end
 e.spawnReady=true;tick();assert(l.pending,'planning plus acknowledged spawns cannot replace the player turn event')
 l:phaseEvent('onNextTurn',e.GetCurrentMission());e.spawnReady=false
 tick();assert(l.pending,'all initial spawn choices must be acknowledged')
 e.spawnReady=true;e.modApi.runLaterQueue={tail=true};tick();assert(l.pending,'pending loader work must finish')
 e.modApi.runLaterQueue={};tick();assert(not l.pending and not l.fault and events[#events].event=='deployment_launch_observed' and clicks()==1)
end
print('Deployment launch requires all landing events, ordered initial phase hooks, acknowledged spawn batch, empty callback queue and later observation (engine doubles).')
