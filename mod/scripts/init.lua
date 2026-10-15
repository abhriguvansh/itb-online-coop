local mod = {
    id = 'aman_itb_coop_probe',
    name = 'ITB Co-op Capability Probe',
    version = '0.17.0',
    modApiVersion = '2.9.6',
    gameVersion = '1.2.93',
    description = 'Research probe with an opt-in validated-path movement lab on ITB_Coop_Probe. No multiplayer yet.',
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
    self.movement = require(path .. 'movement').new(_G, function(kind, payload) self.probe:record(kind, payload) end, 'ui')
    local native
    local loaded, reason = pcall(function()
        local open, detail = package.loadlib(path .. '../itb_input.dll', 'luaopen_itb_input')
        assert(open, detail)
        native = open()
        assert(type(native)=='table' and native.info().abi=='itb-win32-click-v3','unsupported-native-bridge')
    end)
    self.probe:record('ui_bridge_loaded', {available=loaded, reason=not loaded and tostring(reason) or nil})
    self.movement.bridge = require(path .. 'ui_bridge').new(_G, loaded and native or nil,
        function(kind,payload)
            if kind=='ui_guard_start' or kind=='ui_guard_end' or kind=='protected_session_start' or kind=='protected_session_changed' then
                local ok,state=pcall(function()
                    assert(self.movement:profileAllowed(),'outside-disposable-profile')
                    return require(path..'snapshot').capture(_G,GetCurrentMission(),require(path..'json'))
                end)
                payload.state=ok and state or {unavailable=tostring(state)}
                local uiOk,uiState=pcall(function()
                    assert(self.movement:profileAllowed(),'outside-disposable-profile')
                    local pawn=Board:GetSelectedPawn()
                    return {selectedPawnId=pawn and pawn:GetId() or -1,
                        armedWeaponId=pawn and pawn:GetArmedWeaponId() or -1,
                        modalObserved=self.movement.blocked}
                end)
                payload.ui=uiOk and uiState or {unavailable=tostring(uiState)}
            end
            self.probe:record(kind,payload)
        end)
    self.inputGate = require(path .. 'input_gate').new(_G, self.movement,
        function(kind, payload) self.probe:record(kind, payload) end,
        function() return require(path .. 'snapshot').capture(_G, GetCurrentMission(), require(path .. 'json')) end)
    self.inputGate:install()
    local inputRecords=0
    self.deliveryTrace=sdl.eventHook(function(event)
        if self.movement.pending and inputRecords<24 then
            local t=event:type()
            if t==sdl.events.mousemotion or t==sdl.events.mousebuttondown or t==sdl.events.mousebuttonup then
                inputRecords=inputRecords+1
                self.probe:record('ui_bridge_event_after_loader',{type=t,x=sdl.mouse.x(),y=sdl.mouse.y(),
                    phase=self.movement.bridge.phase})
            end
        end
        return false
    end)
    self.attack = require(path .. 'attack').new(_G, self.movement, self.inputGate,
        function(kind, payload) self.probe:record(kind, payload) end,
        function() return require(path .. 'snapshot').capture(_G, GetCurrentMission(), require(path .. 'json')) end,
        require(path .. 'json'))
    require(path .. 'movement_ui').install(_G, self.movement, self.inputGate, self.attack)
    modApi.events.onMissionUpdate:subscribe(function() self.movement:update(); self.moveTrace:update(); self.attack:update() end)
    for _, name in ipairs({ 'onMissionChanged', 'onMissionEnd', 'onGameExited', 'onProfileChanged' }) do
        local eventName = name
        modApi.events[eventName]:subscribe(function(mission,detail)
            if self.phaseLab and self.phaseLab:context(eventName,mission,detail) then return end
            self.attack:reset(eventName); self.inputGate:stop(eventName, true); self.movement:reset(eventName); self.moveTrace:reset()
        end)
    end
    for _, name in ipairs({ 'onSkillStart', 'onSkillEnd' }) do
        local eventName = name
        modapiext.events[eventName]:subscribe(function(_, pawn, weapon, from, to)
            self.attack:skillEvent(eventName, pawn, weapon)
            self.movement:skillEvent(eventName, pawn, weapon)
            self.moveTrace:observe(eventName, pawn, weapon, from, to)
        end)
    end
    modapiext.events.onSkillBuild:subscribe(function(_, pawn, weapon, from, to)
        self.movement.bridge:observePreview(pawn, weapon, from, to)
        self.moveTrace:observe('build', pawn, weapon, from, to)
    end)
    if loaded then self.phaseLab=require(path..'phase_lab').install(_G,self,native,path) end
end

function mod:load()
    if self.phaseLab and self.phaseLab.session then self.phaseLab.session:stop('mod-load') end
    self.attack:reset('mod-load')
    self.inputGate:stop('mod-load', true)
    self.probe:load()
    self.movement:reset('mod-load')
    self.moveTrace:reset()
end

return mod
