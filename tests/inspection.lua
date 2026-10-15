local module=dofile('mod/scripts/inspection.lua');local json=dofile('mod/scripts/json.lua')
local function fixture()
    local e={TEAM_PLAYER=1,TEAM_ENEMY=6,TERRAIN_ROAD=0,math={random=function()return .5 end},random_int=function()return 0 end}
    local mt={__sub=function(a,b)return e.Point(a.x-b.x,a.y-b.y)end}
    e.Point=function(x,y)return setmetatable({x=x,y=y},mt)end
    e.GetDirection=function(p)return p.x<0 and 3 or p.x>0 and 1 or p.y<0 and 0 or 2 end
    local function list(a)return {size=function()return #a end,index=function(_,i)return a[i]end,empty=function()return #a==0 end}end
    local actor={GetType=function()return 'PunchMech'end,IsActive=function()return not e.spent end,IsPowered=function()return true end,IsFrozen=function()return false end,IsBoosted=function()return false end,
        GetSpace=function()return e.Point(3,3)end,GetPoweredWeapons=function()return {'Prime_Punchmech'}end,GetMechName=function()return 'Combat Mech'end}
    local enemy={GetMechName=function()return 'Hornet'end}
    local marks,events={},{};e.Board={GetPawn=function(_,id)return id==0 and actor or enemy end,GetSelectedPawn=function()return nil end,IsSmoke=function()return false end,
        IsValid=function(_,p)return p.x>=0 and p.x<8 and p.y>=0 and p.y<8 end,MarkSpaceDamage=function(_,d)marks[#marks+1]=d;if e.mutateMark then e.grid=3 end end}
    e.SpaceDamage=function(p,d,push)return {loc=p,iDamage=d,iPush=push}end
    local builds=0;e.Prime_Punchmech={Damage=2,GetTargetArea=function()return list({e.Point(2,3),e.Point(4,3)})end,
        GetSkillEffect=function(_,from,to)builds=builds+1;if e.consumeRandom then e.random_int(4)end
            return {q_effect=list({}),effect=list({{iDamage=0,sScript='never execute',loc=e.Point(-1,-1)},
                {iDamage=2,loc=to,iPush=e.GetDirection(to-from),sAnimation='not copied'}})}end}
    local state={unavailable=json.array(),size={x=8,y=8},gridPower=4,tiles=json.array(),pawns=json.array({{localId=101,position={x=2,y=3},type='Hornet1',team=6,health=3,moveSpeed=5,queuedTarget={x=2,y=4}}}),
        queuedSpawns=json.array({{type='HiddenFutureEnemy'}})}
    for y=0,7 do for x=0,7 do state.tiles[#state.tiles+1]={x=x,y=y,terrain=0} end end
    local capture=function()state.gridPower=e.grid or 4;return state,true end
    local n={guardActive=true,sessionState=1,armed=false,pressed=false,releaseFailed=false}
    local wire={inputReady=true,inspectionReady=true,peer='guest'};local s={revision=0}
    local ui=module.new({env=e,native={info=function()return n end},wire=wire,capture=capture,json=json,emit=function(k,v)events[#events+1]={event=k,payload=v}end})
    return e,ui,s,n,wire,marks,events,function()return builds end
end
do
    local e,ui,s,_,wire,marks,events,builds=fixture();ui:update(s);ui.enabled=true
    ui:inspect(s,{x=2,y=3});assert(ui.lines[3]=='Hornet' and ui.lines[7]=='Attack aimed at (2,4)')
    assert(not json.encode(ui.lines):find('HiddenFutureEnemy'))
    assert(ui:punch(s,{x=2,y=3}) and builds()==1,'guest may inspect teammate without owning it')
    ui:mark(s);assert(#marks==1 and marks[1].iDamage==2 and marks[1].iPush==3 and not marks[1].sScript and not marks[1].sAnimation)
    assert(wire.inputReady and events[#events].event=='inspection_mark_observed')
    s.revision=1;ui:update(s);assert(not ui.preview and #ui.lines==0);ui:mark(s);assert(#marks==1)
end
do
    local e,ui,s,n,wire,marks,_,builds=fixture();ui:update(s);ui.enabled=true
    assert(not ui:punch(s,{x=0,y=0}) and builds()==0)
    e.spent=true;assert(not ui:punch(s,{x=2,y=3}) and builds()==0);e.spent=false
    wire.inputReady=false;wire.inspectionReady=false;assert(not pcall(function()ui:punch(s,{x=2,y=3})end));assert(#marks==0)
    wire.inspectionReady=true;n.sessionState=2;assert(not pcall(function()ui:inspect(s,{x=2,y=3})end))
end
do
    local e,ui,s=fixture();local original=e.random_int;local random=e.math.random;e.consumeRandom=true
    assert(not pcall(function()ui:punch(s,{x=2,y=3})end));assert(e.random_int==original and e.math.random==random and not ui.preview)
end
do
    local e,ui,s=fixture();ui.enabled=true;ui:punch(s,{x=2,y=3});e.mutateMark=true
    assert(not pcall(function()ui:mark(s)end),'render mutation must stop rather than be repaired')
end
print('Inspection contracts: teammate preview without dispatch, hidden-spawn omission, safe damage copy, revision invalidation, stopped/busy refusal, RNG restoration and render-mutation rejection (engine doubles).')
do
    local _,ui,s,_,wire=fixture();wire.inputReady=false;wire.readyInput=true;ui.enabled=true
    ui:inspect(s,{x=2,y=3});assert(ui.lines[3]=='Hornet','readiness may retain independent inspection')
    wire.prepared={};assert(not pcall(function()ui:punch(s,{x=2,y=3})end))
    assert(ui:click(1610,350,s) and not ui.enabled,'local exit must remain possible while preparation disables inspection')
    assert(ui:click(1610,350,s) and not ui.enabled,'preparation cannot enable inspection')
end
