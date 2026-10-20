-- Captured normal-choice replay for the pinned fresh-entry Mission_Tides fixture.
-- A private transcript is an experimental prerequisite, not a joining protocol.
local M={}
function M.parse(text,json)
    assert(type(text)=='string' and #text<=2048 and text:sub(-1)=='\n','initial-choice-transcript-invalid')
    local rows=json.array();local consumed=0
    for line in text:gmatch('([^\n]+)\n') do
        local kind,limit,value=line:match('^([a-z%-]+)|(%d+)|(%d+)$')
        local n=#rows+1;local v,l=tonumber(value),tonumber(limit)
        assert(n<=19 and kind==(n<18 and 'ai-constructor' or n==18 and 'pod-delivery' or 'pod-select')
            and l==(n<18 and 32768 or n==18 and 3 or 9) and v and v>=0 and v<=32767
            and tostring(v)==value and tostring(l)==limit,'initial-choice-transcript-shape')
        rows[n]={kind=kind,limit=l,value=v};consumed=consumed+#line+1
    end
    assert(#rows==19 and consumed==#text,'initial-choice-transcript-count')
    return rows
end
function M.install(env,path,emit)
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
            and v.fault==0 and not v.overflow and v.count==19 and v.expectedCount==19
    end
    return self
end
return M
