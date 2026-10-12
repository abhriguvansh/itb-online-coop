local mod = {
    id = 'aman_itb_coop_probe',
    name = 'ITB Co-op Capability Probe',
    version = '0.1.0',
    modApiVersion = '2.9.6',
    gameVersion = '1.2.93',
    description = 'Observer-only research probe. Logs execution and partial state on ITB_Coop_Probe. No multiplayer yet.',
    dependencies = { modApiExt = '1.25' },
}

function mod:init()
    local path = self.scriptPath
    self.probe = require(path .. 'probe').new(self, _G, require(path .. 'json'),
        require(path .. 'snapshot'), require(path .. 'settle'))
    self.probe:subscribe()
end

function mod:load()
    self.probe:load()
end

return mod
