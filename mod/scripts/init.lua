local mod = {
    id = 'aman_itb_coop_probe',
    name = 'ITB Co-op Capability Probe',
    version = '0.2.2',
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
    self.moveTrace = require(path .. 'move_trace').new(_G,
        function(kind, payload) self.probe:record(kind, payload) end, require(path .. 'json'))
    self.movement = require(path .. 'movement').new(_G, function(kind, payload) self.probe:record(kind, payload) end, 'effect')
    require(path .. 'movement_ui').install(_G, self.movement)
    modApi.events.onMissionUpdate:subscribe(function() self.movement:update(); self.moveTrace:update() end)
    for _, name in ipairs({ 'onMissionChanged', 'onMissionEnd', 'onGameExited', 'onProfileChanged' }) do
        local eventName = name
        modApi.events[eventName]:subscribe(function() self.movement:reset(eventName); self.moveTrace:reset() end)
    end
    for _, name in ipairs({ 'onSkillStart', 'onSkillEnd' }) do
        local eventName = name
        modapiext.events[eventName]:subscribe(function(_, pawn, weapon, from, to)
            self.movement:skillEvent(eventName, pawn, weapon)
            self.moveTrace:observe(eventName, pawn, weapon, from, to)
        end)
    end
    modapiext.events.onSkillBuild:subscribe(function(_, pawn, weapon, from, to)
        self.moveTrace:observe('build', pawn, weapon, from, to)
    end)
end

function mod:load()
    self.probe:load()
    self.movement:reset('mod-load')
    self.moveTrace:reset()
end

return mod
