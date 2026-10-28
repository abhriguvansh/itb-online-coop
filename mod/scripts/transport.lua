-- One opt-in in-process connection for the existing isolated full-mission lab.
local M={}
function M.privateAddress(text)
    if type(text)~='string' or #text>15 then return false end
    local a,b,c,d=text:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    if not a then return false end
    local n={tonumber(a),tonumber(b),tonumber(c),tonumber(d)}
    if table.concat(n,'.')~=text then return false end
    for _,v in ipairs(n)do if v>255 then return false end end
    return n[1]==10 or n[1]==172 and n[2]>=16 and n[2]<=31 or n[1]==192 and n[2]==168
        or n[1]==100 and n[2]>=64 and n[2]<=127 or text=='127.0.0.1'
end
function M.install(env,path,json,emit,session)
    if env.os.getenv('ITB_COOP_NATIVE_TRANSPORT')~='1' then return nil end
    local self={out={},incoming={},bootstrap={},sent=0,received=0};local native,config,sid,peer,token,port,target,since,last
    env.ITBCoopTransport=self
    local root='C:/ITBCoopProbe/Wire'
    local function read(name)
        local f=env.io.open(root..'/'..name,'rb');if not f then return nil end
        local v=f:read(1025);f:close();assert(#v<=1024,'transport-config-size');return v
    end
    local function fail(why)
        if self.error or self.done then return end
        self.error=tostring(why);if native then pcall(native.close) end
        emit('native_transport_failed',{reason=self.error})
        local s=session();if s then s:stop('native-transport:'..self.error) end
    end
    function self:healthy()
        if self.error or self.done or not native then return false end
        local n=native.info();return n.abi=='itb-transport-v2' and n.target==target and n.state==2 and n.fault==0
    end
    function self:send(value)
        assert(not self.error and not self.done,'transport-stopped')
        assert(value.session==sid and value.peer==peer and type(value.type)=='string','transport-message-identity')
        assert(#self.out<32 and self.sent<4300,'transport-output-limit')
        local text=json.encode(value);assert(#text<=140000,'transport-output-size')
        self.out[#self.out+1]=text;self.sent=self.sent+1
        if value.type=='complete' then
            self.complete=true
            for i=#self.incoming,1,-1 do if self.incoming[i]:match('^PING|') then table.remove(self.incoming,i) end end
        end
    end
    function self:receive()
        assert(not self.error,'transport-stopped');return table.remove(self.incoming,1)
    end
    function self:bootstrapFile(name)
        if name=='bridge-failure.txt' then return self.error end
        return self.bootstrap[name]
    end
    local ok,why=pcall(function()
        assert(env.os.getenv('ITB_COOP_WIRE_DIR')==root,'transport-unsupported-mode')
        config=assert(read('native-connection.txt'),'transport-config-missing')
        local number
        sid,peer,target,number,token=config:match('^itb%-transport%-v2\n([a-f0-9%-]+)\n([a-z]+)\n([^\n]+)\n(%d+)\n([a-f0-9]+)\n$')
        port=tonumber(number)
        assert(sid and #sid==36 and (peer=='host' or peer=='guest') and M.privateAddress(target) and port and port>=1 and port<=65535
            and tostring(port)==number and #token==48,'transport-config-invalid')
        local sessionConfig=read('session.txt')
        assert(sessionConfig==sid..'\n'..peer..'\nfull-mission\n' and env.os.getenv('ITB_COOP_LIVE_BOOTSTRAP')=='1'
            or sessionConfig==sid..'\n'..peer..'\nxp-result-checkpoint\n' and env.os.getenv('ITB_COOP_XP_CHECKPOINT')=='1'
                and not env.os.getenv('ITB_COOP_LIVE_BOOTSTRAP') and not env.os.getenv('ITB_COOP_INITIAL_CHOICES')
            or sessionConfig==sid..'\n'..peer..'\nrepeated-turns\n' and env.os.getenv('ITB_COOP_REPAIR_CHECKPOINT')=='1'
                and not env.os.getenv('ITB_COOP_LIVE_BOOTSTRAP') and not env.os.getenv('ITB_COOP_INITIAL_CHOICES'),'transport-config-session')
        local open=assert(env.package.loadlib(path..'../itb_transport.dll','luaopen_itb_transport'))
        native=assert(open());assert(native.info().abi=='itb-transport-v2','transport-abi')
        local n=native.open(port,target);assert(n.target==target and n.fault==0 and (n.state==1 or n.state==2),'transport-connect-failed')
        since=env.modApi:elapsedTime();last=since
        env.modApi.events.onFrameDrawStart:subscribe(function()
            if self.error or self.done then return end
            local worked,reason=pcall(function()
                local now=env.modApi:elapsedTime()
                assert(now-since<3610000,'transport-experiment-deadline')
                assert(read('native-connection.txt')==config and read('session.txt')==sessionConfig,'transport-config-replaced')
                for _=1,4 do
                    local packet=native.poll();local n=native.info();assert(n.fault==0 and n.target==target,'transport-native-fault:'..tostring(n.fault))
                    if packet then
                        self.received=self.received+1;assert(self.received<=4096,'transport-input-limit');last=now
                        local kind,id,body=packet:match('^([A-Z]+)|([^|\n]+)\n(.*)$')
                        if kind=='BOOTSTRAPCHOICES' or kind=='BOOTSTRAPREADY' then
                            assert(id==sid and #body<=2048 and (kind~='BOOTSTRAPCHOICES' or peer=='guest'),'transport-bootstrap-identity')
                            local name=kind=='BOOTSTRAPCHOICES' and 'bootstrap-offer.txt' or 'bootstrap-agreed.txt'
                            assert(not self.bootstrap[name],'transport-duplicate-bootstrap');self.bootstrap[name]=sid..'\n'..body
                        else
                            local m=require(path..'phase_wire').decode(packet,sid)
                            if m.kind=='PING' then assert(native.send(json.encode({type='pong',session=sid})),'transport-pong-failed') end
                            assert(m.kind~='STOP','transport-coordinator-stopped')
                            if m.kind~='PING' or self.active and not self.complete then
                                assert(#self.incoming<32,'transport-incoming-queue');self.incoming[#self.incoming+1]=packet
                            end
                        end
                    end
                    if not packet then break end
                end
                local n=native.info()
                if n.state==3 then
                    assert(self.complete and #self.out==0 and n.pendingTx==0 and n.pendingRx==0 and #self.incoming==0,'transport-disconnected')
                    self.done=true;emit('native_transport_completed',{queued=self.sent,received=self.received});return
                end
                assert(now-last<10000,'transport-heartbeat-expired')
                if n.state==2 then
                    if not self.hello then
                        assert(native.send(json.encode({type='hello',session=sid,peer=peer,token=token})),'transport-hello-failed')
                        self.hello=true;emit('native_transport_connected',{peer=peer,abi=n.abi,target=n.target})
                    end
                    for _=1,4 do
                        local value=self.out[1];if not value then break end
                        assert(native.send(value),'transport-send-failed');table.remove(self.out,1)
                    end
                end
            end)
            if not worked then fail(reason) end
        end)
    end)
    if not ok then fail(why) end
    return self
end
return M
