-- Coordinate only the observed native shared-XP remainder choice for full missions.
local M={}
function M.new(env,path,json,emit)
    local open=assert(env.package.loadlib(path..'../itb_initial_choices.dll','luaopen_itb_initial_choices'))
    local native=assert(open());local self={}
    local function checked(v)
        assert(v.abi=='itb-shared-xp-v1' and v.fault==0 and type(v.count)=='number'
            and v.count>=0 and v.count<=128 and #v.entries==v.count,'shared-xp-native-fault')
        return v
    end
    function self:healthy()return checked(native.xpInfo())end
    function self:begin(session,r)
        assert(not self.context,'shared-xp-overlap')
        assert(env.Profile.visible_name=='ITB_Coop_Probe' and env.modApi:getCurrentProfile()~='','shared-xp-profile')
        local context=session..'/'..r.phase..'/'..r.revision..'/'..r.id
        local v=checked(native.xpBegin(context));assert(v.active and v.context==context and v.count==0,'shared-xp-not-armed')
        self.context=context;emit('shared_xp_command_started',{context=context})
    end
    function self:finish()
        assert(self.context,'shared-xp-not-started')
        local v=checked(native.xpFinish());assert(not v.active and v.context==self.context,'shared-xp-not-restored')
        local result={abi=v.abi,context=v.context,entries=json.array()}
        for i,e in ipairs(v.entries)do
            assert(e.limit>=1 and e.limit<=3 and e.limit%1==0 and e.applied>=0 and e.applied<=32767
                and e.applied%1==0,'shared-xp-invalid-draw')
            result.entries[i]={limit=e.limit,applied=e.applied}
        end
        v.entries=json.array(v.entries);emit('shared_xp_command_restored',{native=v})
        self.context=nil;return result
    end
    function self:stop()
        if native.xpInfo().active then native.xpFinish() end
        self.context=nil
    end
    self:healthy();return self
end
return M
