local module=dofile('mod/scripts/reset_turn.lua')
local json=dofile('mod/scripts/json.lua')
local passed=0
local function test(name,fn)local ok,why=pcall(fn);assert(ok,name..': '..tostring(why));passed=passed+1 end
local function make()
 local e={clock=0,turn=3,team=1,healthy=true,busy=0,saved=true,remaining=1,records={},mission={ID='Mission_Artillery'}}
 local base={unavailable=json.array(),turn=3,pawn={x=1,y=5},gridPower=2};e.state={unavailable=json.array(),turn=3,pawn={x=0,y=5},gridPower=2}
 e.Profile={visible_name='ITB_Coop_Probe'};e.TEAM_PLAYER=1;e.RegionData={iBattleRegion=2}
 e.modApi={getCurrentProfile=function()return 'Alpha'end,getGameVersion=function()return '1.2.93'end,elapsedTime=function()return e.clock end,
  deployment={isDeploymentPhase=function()return false end,isLandingPhase=function()return false end}}
 e.GetCurrentMission=function()return e.mission end;e.Game={GetTeamTurn=function()return e.team end,GetTurnCount=function()return e.turn end}
 e.sdlext={isGame=function()return true end,isConsoleOpen=function()return false end,CurrentWindowRect={x=0,y=0,w=0,h=0}}
 e.screen={w=function()return 1920 end,h=function()return 1081 end};e.GetBoardScale=function()return 3 end
 e.Board={IsTipImage=function()return false end,GetSelectedPawn=function()end,GetBusyState=function()return e.busy end}
 e.GetSavedataLocation=function()return 'C:/private/'end
 e.ReadSaveData=function(path)
  if path then assert(path=='C:/private/profile_Alpha/undoSave.lua' and not e.undoMissing,'native turn save unavailable')else assert(e.saved,'temporarily missing native save')end
  return {GameData={undosave=true},RegionData={region2={mission='Mission7',player={sMission='Mission7',iCurrentTurn=3,iTeamTurn=1,iUndoTurn=path and 1 or e.remaining,actions=0}}}}
 end
 e.sdl={events={mousebuttonup=2},eventHook=function(fn)e.releaseHook=fn;return fn end}
 e.release=function()e.releaseHook({type=function()return 2 end,mousebutton=function()return 1 end})end
 local n={clicks={},finishCount=0}
 n.info=function()return {guardActive=e.healthy,sessionState=e.healthy and 1 or 2,releaseFailed=false,pressed=false,mouseX=n.x,mouseY=n.y,cursorX=n.x,cursorY=n.y}end
 n.begin=function()return true end;n.aim=function(x,y)n.x,n.y=x,y;return true end;n.finish=function()n.finishCount=n.finishCount+1 end
 n.click=function(x,y)n.clicks[#n.clicks+1]={x,y};e.release();if #n.clicks==1 then e.sdlext.CurrentWindowRect={x=765,y=408,w=390,h=265}end;return true,2 end
 local u=module.new(e,n,function(k,p)e.records[#e.records+1]={kind=k,payload=p}end,function()return e.state,e.busy==0 end,json)
 local c={turn=3,restoreWitness=module.comparable(base,json),actionObserved=true}
 e.tick=function(ms)e.clock=e.clock+(ms or 100);u:draw();u:missionUpdate();u:update()end
 e.submit=function()assert(u:arm(c));assert(u:request(c));for i=1,12 do e.tick()end;assert(#n.clicks==2 and u:loading())end
 e.reload=function()
  local old=e.mission;e.turn=0;e.team=2;e.saved=false
  assert(u:modLoad());u:loadEvent('pre-load');u:event(old);u:loadEvent('post-load')
  e.mission={ID='Mission_Artillery'};e.turn=3;e.team=1;e.state=base
  assert(u:context('onMissionChanged',e.mission,old));e.remaining=0
 end
 return e,n,u,c
end
test('restoration excludes only non-building road health without mutating the observation',function()
 local function state(terrain,hp,building)return {tiles=json.array({{terrain=terrain,health=hp,building=building,x=2,y=4}})}end
 local a=state(0,4,false);assert(module.comparable(a,json)==module.comparable(state(0,2,false),json) and a.tiles[1].health==4)
 assert(module.comparable(state(1,2,true),json)~=module.comparable(state(1,1,true),json))
 assert(module.comparable(state(4,2,false),json)~=module.comparable(state(4,1,false),json))
 assert(module.comparable(state(0,2,true),json)~=module.comparable(state(0,1,true),json))
end)
test('normal flooded-water restoration excludes HP only while unfrozen and non-building',function()
 local function state(hp,frozen,building,terrain)return {tiles=json.array({{terrain=terrain or 3,health=hp,building=building,frozen=frozen,x=4,y=1}})}end
 local a=state(4,false,false)
 assert(module.comparable(a,json)==module.comparable(state(2,false,false),json) and a.tiles[1].health==4)
 for _,v in ipairs({{true,false},{false,true}})do
  assert(module.comparable(state(4,v[1],v[2]),json)~=module.comparable(state(2,v[1],v[2]),json))
 end
 assert(module.comparable(state(4,nil,false),json)~=module.comparable(state(2,nil,false),json),'unknown frozen state stays compared')
 assert(module.comparable(state(4,false,false),json)~=module.comparable(state(4,false,false,0),json),'terrain stays compared')
end)

test('normal dialog and ordered reload wait for later observations and consumed saved allowance',function()
 local e,n,u=make();e.submit();e.reload();u:update();assert(u.pending)
 e.tick();assert(u.pending and not u.fault);e.saved=true;e.modApi.runLaterQueue={pending=true};e.tick(300);assert(u.pending)
 e.modApi.runLaterQueue={};e.busy=1;e.tick();assert(u.pending);e.busy=0;e.tick(300)
 assert(not u.pending and not u.fault and n.finishCount==1 and #n.clicks==2)
 assert(not u:arm({turn=3,restoreWitness='anything'}),'shared allowance cannot reset with the board')
end)
test('matching idle snapshots without reset events never finish',function()
 local e,n,u=make();e.submit();e.state={unavailable=json.array(),turn=3,pawn={x=1,y=5},gridPower=2};e.remaining=0
 e.tick();assert(u.pending);e.tick(15000);assert(u.fault and #n.clicks==2)
end)
test('unchanged saved allowance waits then fails without another click',function()
 local e,n,u=make();e.submit();e.reload();e.saved=true;e.remaining=1;e.tick(300);assert(u.pending and not u.fault)
 e.tick(15000);assert(u.fault and #n.clicks==2)
end)
test('wrong restored observation stops despite consumed allowance',function()
 local e,n,u=make();e.submit();e.reload();e.saved=true;e.state.gridPower=1;e.tick(300);assert(u.fault and #n.clicks==2)
end)
test('unknown dialog stops before any confirmation',function()
 local e,n,u,c=make();assert(u:arm(c));u:request(c)
 for i=1,5 do e.tick()end;e.sdlext.CurrentWindowRect={x=765,y=408,w=389,h=265}
 e.tick(4500);assert(u.fault and #n.clicks==1)
end)
test('reload and hook order are not generic permission to load another context',function()
 local e,n,u=make();assert(not pcall(function()u:modLoad()end));e.submit()
 assert(not pcall(function()u:loadEvent('post-load')end));e.reload()
 assert(not pcall(function()u:event(e.mission)end));assert(not pcall(function()u:context('onProfileChanged')end))
end)
test('lost guard while board bindings reload remains a failure',function()
 local e,n,u=make();e.submit();e.turn=0;e.team=2;e.healthy=false;e.tick();assert(u.fault and #n.clicks==2)
end)
test('movement alone and missing native turn save refuse before input',function()
 local e,n,u,c=make();c.actionObserved=false;assert(not u:arm(c) and #n.clicks==0)
 c.actionObserved=true;e.saved=false;assert(u:arm(c),'native turn save survives invalidated current save')
 e.undoMissing=true;assert(not u:arm(c) and #n.clicks==0)
end)
print('Protected Reset boundary contracts: '..passed..' passed (engine/save/input doubles only).')
