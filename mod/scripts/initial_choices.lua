-- Live host capture or legacy recorded replay for the pinned Mission_Tides fixture.
-- This exact initialization shape is experimental, not a general joining protocol.
local M={}
function M.parse(text,json)
    assert(type(text)=='string' and #text<=2048 and text:sub(-1)=='\n','initial-choice-transcript-invalid')
    local rows=json.array();local consumed=0
    for line in text:gmatch('([^\n]+)\n') do
        local kind,limit,value=line:match('^([a-z%-]+)|(%d+)|(%d+)$')
        local n=#rows+1;local v,l=tonumber(value),tonumber(limit)
        assert(n<=20 and v and v>=0 and v<=32767 and tostring(v)==value and tostring(l)==limit,'initial-choice-transcript-shape')
        rows[n]={kind=kind,limit=l,value=v};consumed=consumed+#line+1
    end
    local count=#rows
    assert((count==19 or count==20) and consumed==#text,'initial-choice-transcript-count')
    for i,row in ipairs(rows)do
        local special=count==20 and i==19
        assert(row.kind==(i<18 and 'ai-constructor' or i==18 and 'pod-delivery' or special and 'pod-special' or 'pod-select')
            and row.limit==(i<18 and 32768 or i==18 and 3 or special and 100 or 9),'initial-choice-transcript-shape')
    end
    return rows
end
function M.install(env,path,emit)
    if env.os.getenv('ITB_COOP_LIVE_BOOTSTRAP')=='1' then return M.exchange(env,path,emit) end
    local self={enabled=false}
    local mode=env.os.getenv('ITB_COOP_INITIAL_CHOICES')
    if not mode then return self end
    self.enabled=true
    local json=require(path..'json');local native
    local function observe(boundary)
        local v=native.info();v.entries=json.array(v.entries)
        emit('initial_choice_trace',{boundary=boundary,native=v});self.last=v.count
        return v
    end
    local ok,why=pcall(function()
        assert(mode=='capture' or mode=='replay','initial-choice-mode-invalid')
        local open=assert(env.package.loadlib(path..'../itb_initial_choices.dll','luaopen_itb_initial_choices'))
        native=assert(open());assert(native.info().abi=='itb-initial-choices-v1','initial-choice-abi')
        if mode=='replay' then
            local f=assert(env.io.open('C:/ITBCoopProbe/initial-choices.txt','rb'),'initial-choice-transcript-missing')
            local text=f:read(2049);f:close();self.choices=M.parse(text,json)
        end
        emit('initial_choice_trace_install',native.install(self.choices))
        for _,name in ipairs({'onMissionStart','onDeploymentPhaseStart','onLandingPhaseStart','onDeploymentPhaseEnd','onNextTurn'}) do
            local event=name
            env.modApi.events[event]:subscribe(function()
                if mode=='replay' and event=='onDeploymentPhaseStart' then native.restore() end
                observe(event)
            end)
        end
        env.modApi.events.onMissionUpdate:subscribe(function()
            if native.info().count~=self.last then observe('onMissionUpdate') end
        end)
    end)
    self.error=not ok and tostring(why) or nil
    if not ok then emit('initial_choice_bootstrap_failed',{reason=self.error}) end
    function self:healthy()
        if self.error or not native or mode~='replay' then return false end
        local v=native.info()
        return v.abi=='itb-initial-choices-v1' and v.sealed and not v.installed
            and v.fault==0 and not v.overflow and self.choices and v.count==#self.choices and v.expectedCount==#self.choices
    end
    return self
end
-- Live host capture -> authenticated bridge -> guest pre-entry replay.
-- Only the two observed 19/20-choice Tides initialization shapes are accepted.
function M.exchange(env,path,emit)
    local self={enabled=true};local json=require(path..'json');local native
    local root='C:/ITBCoopProbe/Wire';local session,peer,mode,lastTick
    local function read(name)
        if env.ITBCoopTransport and name~='session.txt' then return env.ITBCoopTransport:bootstrapFile(name) end
        local f=env.io.open(root..'/'..name,'rb');if not f then return nil end
        local text=f:read(4097);f:close();assert(#text<=4096,'bootstrap-file-size');return text
    end
    local function write(name,value)
        assert(not read(name),'bootstrap-output-already-exists')
        value.session=session;value.peer=peer;value.probe='0.31.0';value.fixture='tides-fresh-v1'
        value.game='1.2.93';value.abi='itb-initial-choices-v1'
        if env.ITBCoopTransport then env.ITBCoopTransport:send(value);return end
        local target=root..'/'..name;local f=assert(env.io.open(target..'.tmp','wb'),'bootstrap-output-open')
        assert(f:write(json.encode(value)));assert(f:close());assert(env.os.rename(target..'.tmp',target),'bootstrap-output-commit')
    end
    local function checked(fn)
        if self.error then return end
        local ok,why=pcall(fn)
        if not ok then
            self.error=tostring(why)
            if native and native.info().installed then pcall(native.restore) end
            local detail={reason=self.error,live=true}
            if native then local readOk,v=pcall(native.info);if readOk then v.entries=json.array(v.entries);detail.native=v end end
            emit('initial_choice_bootstrap_failed',detail)
        end
    end
    local function info()
        local v=native.info();v.entries=json.array(v.entries)
        assert(v.abi=='itb-initial-choices-v1' and v.fault==0 and not v.overflow,'bootstrap-native-fault')
        return v
    end
    local function transcript(v)
        assert((v.count==19 or v.count==20) and #v.entries==v.count,'bootstrap-native-count')
        local rows={}
        for i,e in ipairs(v.entries)do
            assert(type(e.applied)=='number' and e.applied%1==0,'bootstrap-applied-value')
            if peer=='host' then assert(e.applied==e.value,'bootstrap-host-not-original') end
            rows[i]=e.kind..'|'..e.limit..'|'..e.applied..'\n'
        end
        local text=table.concat(rows);M.parse(text,json);return text
    end
    local function body(name)
        local text=read(name);if not text then return nil end
        local sid,value=text:match('^([%w-]+)\n(.*)$');assert(sid==session,'bootstrap-stale-delivery')
        M.parse(value,json);return value
    end
    checked(function()
        assert(env.os.getenv('ITB_COOP_WIRE_DIR')==root,'bootstrap-wire-directory')
        local config=assert(read('session.txt'),'bootstrap-config-missing')
        session,peer=config:match('^([%w-]+)\n(host)\nfull%-mission\n$')
        if not session then session,peer=config:match('^([%w-]+)\n(guest)\nfull%-mission\n$') end
        assert(session and #session==36 and peer,'bootstrap-config-invalid')
        mode=env.os.getenv('ITB_COOP_INITIAL_CHOICES');assert(mode==(peer=='host' and 'capture' or 'replay'),'bootstrap-role-mode')
        local open=assert(env.package.loadlib(path..'../itb_initial_choices.dll','luaopen_itb_initial_choices'))
        native=assert(open());info()
        if peer=='host' then native.install();info();assert(native.info().installed,'bootstrap-host-install-failed')
        else write('bootstrap-ready.json',{type='bootstrap_ready'}) end
        local since=env.modApi:elapsedTime()
        env.modApi.events.onFrameDrawStart:subscribe(function()
            if self.error or self.agreed then return end
            checked(function()
                local now=env.modApi:elapsedTime();if lastTick and now-lastTick<100 then return end;lastTick=now
                assert(now-since<600000,'bootstrap-exchange-timeout')
                assert(read('session.txt')==config,'bootstrap-session-replaced')
                assert(not read('bridge-failure.txt'),'bootstrap-bridge-stopped')
                if peer=='guest' and not self.installed then
                    local offered=body('bootstrap-offer.txt')
                    if offered then
                        assert(not env.sdlext.isGame() and not env.Board,'bootstrap-guest-entered-too-early')
                        self.choices=M.parse(offered,json);self.text=offered
                        native.install(self.choices);local v=info();assert(v.installed and v.expectedCount==#self.choices,'bootstrap-guest-install-failed')
                        self.installed=true;emit('initial_choice_live_installed',{peer=peer,count=#self.choices,native=v})
                    end
                end
                local agreed=body('bootstrap-agreed.txt')
                if agreed then
                    assert(self.sealed and agreed==self.text,'bootstrap-agreement-before-seal')
                    self.agreed=true;emit('initial_choice_live_agreed',{peer=peer,count=#self.choices})
                end
            end)
        end)
        env.modApi.events.onDeploymentPhaseStart:subscribe(function()
            checked(function()
                assert(not self.sealed and (peer=='host' or self.installed),'bootstrap-entry-not-ready')
                assert(env.Profile.visible_name=='ITB_Coop_Probe' and env.modApi:getCurrentProfile()~='','bootstrap-wrong-profile')
                assert(env.GetCurrentMission().ID=='Mission_Tides','bootstrap-wrong-mission')
                native.restore();local v=info();assert(not v.installed,'bootstrap-hooks-still-installed')
                local text=transcript(v)
                if peer=='host' then
                    self.text=text;self.choices=M.parse(text,json)
                    write('bootstrap-offer.json',{type='bootstrap_offer',witness=text})
                else assert(text==self.text and v.sealed,'bootstrap-replay-disagreement') end
                self.sealed=true
                write('bootstrap-sealed.json',{type='bootstrap_sealed',witness=text,native=v,
                    mission=env.GetCurrentMission().ID,profile=env.Profile.visible_name})
                emit('initial_choice_live_sealed',{peer=peer,count=#self.choices,native=v})
            end)
        end)
    end)
    function self:healthy()
        if self.error or not self.agreed or not self.sealed then return false end
        local v=native.info()
        return v.fault==0 and not v.overflow and not v.installed and self.choices and v.count==#self.choices
            and v.passThrough==(peer=='host') and (peer=='host' or v.sealed and v.expectedCount==#self.choices)
    end
    return self
end
return M
