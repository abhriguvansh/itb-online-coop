local M=dofile('mod/scripts/transport.lua');local json=dofile('mod/scripts/json.lua')
assert(M.install({os={getenv=function()end}},'',{},function()error('disabled')end)==nil)
local function fixture(options)
    options=options or {};local sid='11111111-1111-1111-1111-111111111111';local peer='guest'
    local files={['session.txt']=sid..'\n'..peer..'\nfull-mission\n',
        ['native-connection.txt']='itb-transport-v1\n'..sid..'\n'..peer..'\n10.0.2.2\n12345\n'..string.rep('a',48)..'\n'}
    local clock,draw,stops=0,nil,0;local sent,packets,records={},{},{}
    local state={abi='itb-transport-v1',state=0,fault=0,pendingTx=0,pendingRx=0}
    local native={info=function()return state end,open=function(port)assert(port==12345);state.state=2;return state end,
        poll=function()return table.remove(packets,1)end,send=function(v)sent[#sent+1]=v;return true end,
        close=function()state.state=3 end}
    local flags={ITB_COOP_NATIVE_TRANSPORT='1',ITB_COOP_LIVE_BOOTSTRAP='1',ITB_COOP_WIRE_DIR='C:/ITBCoopProbe/Wire'}
    if options.checkpoint then flags.ITB_COOP_LIVE_BOOTSTRAP=nil;flags.ITB_COOP_REPAIR_CHECKPOINT='1';files['session.txt']=sid..'\n'..peer..'\nrepeated-turns\n' end
    local env={os={getenv=function(k)return flags[k]end},
        package={loadlib=function()return function()return native end end},
        io={open=function(p,mode)assert(mode=='rb','transport must not use per-message files');local v=files[p:match('/([^/]+)$')];
            if v then return {read=function()return v end,close=function()end} end end},
        modApi={elapsedTime=function()return clock end,events={onFrameDrawStart={subscribe=function(_,f)draw=f end}}}}
    if options.xp then flags.ITB_COOP_LIVE_BOOTSTRAP=nil;flags.ITB_COOP_XP_CHECKPOINT='1';files['session.txt']=sid..'\n'..peer..'\nxp-result-checkpoint\n' end
    if options.change then options.change(files)end
    local t=M.install(env,'mod/scripts/',json,function(k,p)records[#records+1]={kind=k,payload=p}end,function()return {stop=function()stops=stops+1 end}end)
    return {t=t,sid=sid,files=files,state=state,sent=sent,packets=packets,records=records,
        tick=function(n)clock=n or clock+100;draw()end,stops=function()return stops end}
end
do local f=fixture();assert(f.t:healthy());f.t:send({type='bootstrap_ready',session=f.sid,peer='guest'});f.tick()
    assert(#f.sent==2 and f.sent[1]:find('"type":"hello"') and f.sent[2]:find('bootstrap_ready'))
    for _=1,40 do f.packets[#f.packets+1]='PING|'..f.sid..'|-|0|-|-\n' end;for _=1,10 do f.tick()end
    assert(not f.t.error and #f.t.incoming==0 and #f.sent==42)
    f.packets[1]='BOOTSTRAPCHOICES|'..f.sid..'\nai-constructor|32768|42\n';f.tick()
    assert(f.t:bootstrapFile('bootstrap-offer.txt')==f.sid..'\nai-constructor|32768|42\n')
    f.packets[1]='BOOTSTRAPCHOICES|'..f.sid..'\nduplicate\n';f.tick();assert(f.t.error and f.stops()==1)
end
do local f=fixture();f.t.active=true;local packet='INPUT|'..f.sid..'|-|0|deployment|-\n{}';f.packets[1]=packet;f.tick();assert(f.t:receive()==packet and not f.t:receive())end
do local f=fixture();f.files['native-connection.txt']='replaced';f.tick();assert(f.t.error and f.stops()==1 and #f.sent==0)end
do local f=fixture();f.files['session.txt']='replaced';f.tick();assert(f.t.error and f.stops()==1)end
do local f=fixture();f.state.state=3;f.tick();assert(f.t.error and f.stops()==1)end
do local f=fixture();f.state.fault=6;f.tick();assert(f.t.error and f.stops()==1)end
do local f=fixture();f.tick(10000);assert(f.t.error and f.stops()==1)end
do local f=fixture();f.packets[1]='BOOTSTRAPREADY|stale\nbad';f.tick();assert(f.t.error and f.stops()==1)end
do local f=fixture();f.packets[1]='EXEC|bad';f.tick();assert(f.t.error and f.stops()==1)end
do local f=fixture();assert(not pcall(function()f.t:send({type='ready',session='stale',peer='guest'})end));assert(#f.sent==0)end
do local f=fixture();f.tick();f.t:send({type='complete',session=f.sid,peer='guest'});f.tick();f.state.state=3;f.tick();assert(f.t.done and not f.t.error and f.stops()==0)end
do local f=fixture({change=function(files)files['native-connection.txt']='malformed'end});assert(f.t.error and f.stops()==1)end
do local f=fixture({checkpoint=true});f.tick();assert(f.t:healthy() and not f.t.error)end
print('In-game transport: ordered hello/messages, bounded pre-arm heartbeats, data framing, replaced config, disconnect/fault/timeout stop and completion passed (socket/engine doubles).')

do local f=fixture({xp=true});assert(f.t:healthy()) end
