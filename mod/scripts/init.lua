local mod = {
    id = 'aman_itb_coop_probe',
    name = 'ITB Co-op Capability Probe',
    version = '0.2.0',
    modApiVersion = '2.9.6',
    gameVersion = '1.2.93',
    description = 'Research probe with an opt-in one-tile movement lab on ITB_Coop_Probe. No multiplayer yet.',
    dependencies = { modApiExt = '1.25' },
    -- Enable this and modApiExt in Configure Mods, then restart the game.
    enabled = false,
}

function mod:init()
    local path = self.scriptPath
    self.probe = require(path .. 'probe').new(self, _G, require(path .. 'json'),
        require(path .. 'snapshot'), require(path .. 'settle'))
    self.probe:subscribe()
    self.movement = require(path .. 'movement').new(_G, function(kind, payload) self.probe:record(kind, payload) end)
    require(path .. 'movement_ui').install(_G, self.movement)
    modApi.events.onMissionUpdate:subscribe(function() self.movement:update() end)
    for _, name in ipairs({ 'onMissionChanged', 'onMissionEnd', 'onGameExited', 'onProfileChanged' }) do
        local eventName = name
        modApi.events[eventName]:subscribe(function() self.movement:reset(eventName) end)
    end
    for _, name in ipairs({ 'onSkillStart', 'onSkillEnd' }) do
        local eventName = name
        modapiext.events[eventName]:subscribe(function(_, pawn, weapon)
            self.movement:skillEvent(eventName, pawn, weapon)
        end)
    end
end

function mod:load()
    self.probe:load()
    self.movement:reset('mod-load')
end

return mod
