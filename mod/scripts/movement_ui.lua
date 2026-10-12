-- A mouse-triggered diagnostic panel; no keyboard or whole-game input interception.
local ui = {}
function ui.install(env, lab)
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
        local root = env.sdlext.getUiRoot()
        if not root then return end
        if not controls.toggle then
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
        controls.toggle.visible = visible
        controls.toggle:caption((lab.armed and 'Disable ' or 'Enable ') .. lab.label)
        controls.toggle:settooltip(lab.status)
        local refresh = env.modApi:elapsedTime() >= nextRefresh
        if refresh then nextRefresh = env.modApi:elapsedTime() + 100 end
        for id = 0, 2 do
            local b = controls[id]
            b.visible = visible and lab.armed
            if b.visible and refresh then
                local request, reason = lab:preview(id)
                if request then
                    lastRequests[id] = request
                    b:caption(names[id] .. ': move to (' .. request.to.x .. ',' .. request.to.y .. ')')
                else
                    b:caption(names[id] .. ': unavailable')
                end
                b:settooltip(request and 'One adjacent clear ground tile. Click to execute the diagnostic move.' or reason)
            elseif not b.visible then
                lastRequests[id] = nil
            end
        end
    end)
end
return ui
