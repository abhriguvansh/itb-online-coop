local M=dofile('mod/scripts/initial_choices.lua');local json=dofile('mod/scripts/json.lua')
local text=string.rep('ai-constructor|32768|42\n',17)..'pod-delivery|3|123\n'..'pod-select|9|123\n'
local rows=M.parse(text,json);assert(#rows==19 and rows[19].value==123)
assert(json.encode(rows):sub(1,1)=='[')
for _,bad in ipairs({text..'\n',text:sub(1,-2),text:gsub('pod%-select|9','pod-select|8'),
    text:gsub('|42','|32768'),text:gsub('|42','|-1'),text:gsub('|42','|042'),
    text:gsub('ai%-constructor','pod-select'),text..'pod-select|9|1\n',string.rep('x',2049)})do
    assert(not pcall(M.parse,bad,json))
end
local disabled=M.install({os={getenv=function()return nil end}},'',function()error('disabled mode touched runtime')end)
assert(not disabled.enabled)
local callbacks,records={},{};local state={abi='itb-initial-choices-v1',count=0,fault=0,entries={},installed=true}
local native={info=function()return state end,install=function(r)assert(#r==19);return state end,
    restore=function()state={abi='itb-initial-choices-v1',count=19,expectedCount=19,fault=0,entries={},installed=false,sealed=true}end}
local e={os={getenv=function()return 'replay'end},package={loadlib=function()return function()return native end end},
    io={open=function(p)assert(p=='C:/ITBCoopProbe/initial-choices.txt');return {read=function()return text end,close=function()end}end},modApi={events={}}}
for _,name in ipairs({'onMissionStart','onDeploymentPhaseStart','onLandingPhaseStart','onDeploymentPhaseEnd','onNextTurn','onMissionUpdate'})do
    local n=name;e.modApi.events[n]={subscribe=function(_,fn)callbacks[n]=fn end}
end
local realRequire=require;require=function(name)assert(name=='test/json');return json end
local s=M.install(e,'test/',function(k,p)records[#records+1]={kind=k,payload=p};json.encode(p)end)
require=realRequire
assert(s.enabled and not s.error and not s:healthy())
callbacks.onDeploymentPhaseStart();assert(s:healthy() and records[#records].payload.native.sealed)
state.fault=8;assert(not s:healthy());state.fault=0;state.installed=true;assert(not s:healthy())
state.installed=false;state.count=18;assert(not s:healthy());state.count=19;state.overflow=true;assert(not s:healthy())
print('Initial-choice transcript, disabled mode, seal/admission and fault contracts passed (Lua doubles).')

local function exchange(role,direct)
    local sid='11111111-1111-1111-1111-111111111111';local files={['session.txt']=sid..'\n'..role..'\nfull-mission\n'}
    local callbacks={};local clock,playing=0,false
    local value={abi='itb-initial-choices-v1',count=0,entries={},fault=0,overflow=false,installed=false,
        passThrough=role=='host',expectedCount=role=='host' and 0 or 19,sealed=false}
    local chosen
    local native={info=function()return value end,install=function(rows)
        assert(not value.installed);chosen=rows;value.installed=true;return value
    end,restore=function()value.installed=false;value.sealed=role=='guest';return value end}
    local env={os={getenv=function(key)
        if key=='ITB_COOP_LIVE_BOOTSTRAP' then return '1' end
        if key=='ITB_COOP_WIRE_DIR' then return 'C:/ITBCoopProbe/Wire' end
        if key=='ITB_COOP_INITIAL_CHOICES' then return role=='host' and 'capture' or 'replay' end
    end,rename=function(a,b)
        a=a:match('/([^/]+)$');b=b:match('/([^/]+)$');assert(not files[b]);files[b]=files[a];files[a]=nil;return true
    end},io={open=function(path,mode)
        local name=path:match('/([^/]+)$')
        assert(name~='initial-choices.txt','live path must never read historical transcript')
        if mode=='rb' then if not files[name] then return nil end;return {read=function()return files[name] end,close=function()return true end} end
        return {write=function(_,text)files[name]=text;return true end,close=function()return true end}
    end},package={loadlib=function()return function()return native end end},sdlext={isGame=function()return playing end},
    Profile={visible_name='ITB_Coop_Probe'},GetCurrentMission=function()return {ID='Mission_Tides'}end,
    modApi={elapsedTime=function()return clock end,getCurrentProfile=function()return 'Alpha' end,events={}}}
    for _,name in ipairs({'onFrameDrawStart','onDeploymentPhaseStart'})do
        local key=name;env.modApi.events[key]={subscribe=function(_,fn)callbacks[key]=fn end}
    end
    local transport
    if direct then
        transport={incoming={},out={}}
        function transport:bootstrapFile(name)return self.incoming[name]end
        function transport:send(value)self.out[#self.out+1]=value end
        env.ITBCoopTransport=transport
    end
    local old=require;require=function(name)assert(name=='test/json');return json end
    local s=M.install(env,'test/',function(_,p)json.encode(p)end);require=old
    local function tick(time)clock=time or clock+200;callbacks.onFrameDrawStart()end
    local function enter(count)
        playing=true;env.Board={};value.count=count or 19;value.entries={}
        for i=1,value.count do
            local kind=i<18 and 'ai-constructor' or i==18 and 'pod-delivery' or 'pod-select'
            value.entries[i]={kind=kind,limit=i<18 and 32768 or i==18 and 3 or 9,
                value=role=='host' and i+123 or i+456,applied=chosen and chosen[i].value or i+123}
        end
        callbacks.onDeploymentPhaseStart()
    end
    return {s=s,files=files,native=value,env=env,tick=tick,enter=enter,sid=sid,transport=transport}
end
do
    local h,g=exchange('host'),exchange('guest')
    assert(h.native.installed and not g.native.installed and g.files['bootstrap-ready.json'])
    assert(not h.s:healthy() and not g.s:healthy())
    h.enter();assert(not h.s.error and h.s.sealed and h.files['bootstrap-offer.json'] and not h.native.installed)
    g.files['bootstrap-offer.txt']=g.sid..'\n'..h.s.text;g.tick()
    assert(g.s.installed and g.native.installed and not g.s.error)
    g.enter();assert(g.s.text==h.s.text and g.native.sealed and not g.s:healthy())
    for _,f in ipairs({h,g})do f.files['bootstrap-agreed.txt']=f.sid..'\n'..h.s.text;f.tick();assert(f.s:healthy()) end
    g.native.fault=8;assert(not g.s:healthy())
end
do local g=exchange('guest');g.enter();assert(g.s.error and not g.s:healthy() and not g.files['bootstrap-sealed.json'])end
do local h=exchange('host');h.enter(18);assert(h.s.error and not h.files['bootstrap-offer.json'])end
do local g=exchange('guest');g.files['bootstrap-offer.txt']='stale\n'..text;g.tick();assert(g.s.error and not g.native.installed)end
do local g=exchange('guest');g.files['bootstrap-agreed.txt']=g.sid..'\n'..text;g.tick();assert(g.s.error and not g.s:healthy())end
do local g=exchange('guest');g.files['session.txt']='replaced';g.tick();assert(g.s.error)end
do local g=exchange('guest');g.tick(600000);assert(g.s.error and not g.native.installed)end
print('Live Lua bootstrap: fresh host capture, deferred guest install, restored-hook seal/agreement, no historical file read and fail-closed negatives passed (engine/filesystem doubles).')
do
    local h,g=exchange('host',true),exchange('guest',true)
    assert(g.transport.out[1].type=='bootstrap_ready' and not g.files['bootstrap-ready.json'])
    h.enter();assert(#h.transport.out==2 and h.transport.out[1].type=='bootstrap_offer' and not h.files['bootstrap-offer.json'])
    g.transport.incoming['bootstrap-offer.txt']=g.sid..'\n'..h.s.text;g.tick();g.enter()
    for _,f in ipairs({h,g})do f.transport.incoming['bootstrap-agreed.txt']=f.sid..'\n'..h.s.text;f.tick();assert(f.s:healthy())end
    assert(not h.files['bootstrap-sealed.json'] and not g.files['bootstrap-sealed.json'])
end
print('Live bootstrap also uses the in-game transport without message files (engine/transport doubles).')
