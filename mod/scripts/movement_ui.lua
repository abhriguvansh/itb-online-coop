-- Mouse-triggered controls for separate opt-in diagnostics.
local ui = {}
function ui.install(env, lab, gate, attack)
    local controls, windows, lastRequests = {}, {}, {}
    local nextRefresh = 0
    local names = { [0] = 'Combat', [1] = 'Cannon', [2] = 'Artillery' }
    local function button(root, y, caption, callback)
        local b = env.Ui():pospx(8, y):widthpx(270):heightpx(36):caption(caption)
            :decorate({ env.DecoButton(), env.DecoAlign(0, 2), env.DecoCaption() }):addTo(root)
        b.onclicked = function(_, mouseButton)
            if mouseButton == 1 then callback() end
            return true -- The diagnostic click must never reach the native board.
        end
        return b
    end
    env.modApi.events.onWindowShown:subscribe(function(id) windows[id] = true; lab.blocked = true end)
    env.modApi.events.onWindowHidden:subscribe(function(id) windows[id] = nil; lab.blocked = next(windows) ~= nil end)
    env.modApi.events.onFrameDrawStart:subscribe(function()
        gate:update()
        if lab.bridge then lab.bridge:pollGuard() end
        local root = env.sdlext.getUiRoot()
        if not root then return end
        if not controls.toggle then
            controls.guarded = button(root, 654, 'Guarded move + lock 20s', function()
                if not lab.armed or lab.pending or lab.fault or not lab.bridge then return end
                for id=0,2 do
                    local request=lab:preview(id)
                    if request then
                        local ok,reason=pcall(function() lab.bridge:lock() end)
                        if ok then lab:request(request) else lab.status=tostring(reason) end
                        return
                    end
                end
                lab.status='No unused supported mech for guarded move'
            end)
            controls.attack = button(root, 556, 'Enable attack lab', function()
                if attack.armed then attack:disarm() else attack:arm() end
            end)
            controls.fire = button(root, 600, 'Punch Hornet at (2,3)', function() attack:request() end)
            controls.gate = button(root, 510, 'Block input 30s', function()
                if gate.active then gate:stop('manual-disarm', false) else gate:arm() end
            end)
            controls.toggle = button(root, 310, 'Enable move lab', function()
                if lab.armed then lab:reset('manual-disarm') else lab:arm() end
            end)
            for id = 0, 2 do
                local pawnId = id
                controls[id] = button(root, 354 + id * 42, names[id], function()
                    -- Keep the last displayed request for a deliberate repeat/rejection check.
                    if lastRequests[pawnId] then lab:request(lastRequests[pawnId]) end
                end)
            end
        end
        local ok, visible = pcall(function()
            local mission = env.GetCurrentMission()
            return lab:profileAllowed() and env.sdlext.isGame() and not lab.blocked
                and not env.sdlext.isConsoleOpen() and mission and mission.ID == 'Mission_Artillery'
        end)
        visible = ok and visible == true
        controls.guarded.visible=visible and lab.armed and not gate.active and not attack.armed
        controls.guarded:caption(lab.bridge.guardStatus or 'Guarded move + lock 20s')
        controls.guarded:settooltip('One validated move, then block window mouse/keyboard until the 20-second diagnostic expires.')
        controls.attack.visible = visible and not gate.active and not lab.armed
        controls.attack:caption(attack.armed and 'Disable attack lab' or 'Enable attack lab')
        controls.attack:settooltip(attack.status)
        controls.fire.visible = visible and attack.armed
        controls.fire:settooltip(attack.status)
        controls.gate.visible = visible and not attack.armed
        controls.gate:caption(gate.active and gate.status or 'Block input 30s')
        controls.gate:settooltip(gate.status)
        controls.toggle.visible = visible and not gate.active and not attack.armed
        controls.toggle:caption((lab.armed and 'Disable ' or 'Enable ') .. lab.label)
        controls.toggle:settooltip(lab.status)
        local refresh = env.modApi:elapsedTime() >= nextRefresh
        if refresh then nextRefresh = env.modApi:elapsedTime() + 100 end
        for id = 0, 2 do
            local b = controls[id]
            b.visible = visible and lab.armed and not gate.active
            if b.visible and refresh then
                local request, reason = lab:preview(id)
                if request then
                    lastRequests[id] = request
                    b:caption(names[id] .. ': move to (' .. request.to.x .. ',' .. request.to.y .. ')')
                else
                    b:caption(names[id] .. ': unavailable')
                end
                b:settooltip(request and 'Validated clear ground path. One move per mech per launch.' or reason)
            elseif not b.visible then
                lastRequests[id] = nil
            end
        end
    end)
end
return ui
