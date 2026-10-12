-- Read-only adapter. Keep engine userdata inside this immediate capture only.
local snapshot = {}

function snapshot.capture(env, mission, json)
    local board, game = env.Board, env.Game
    local missing = json.array()
    local function attempt(path, fn)
        local ok, value = pcall(fn)
        if not ok or value == nil then
            missing[#missing + 1] = path
            return nil
        end
        return value
    end
    local function point(value)
        assert(value ~= nil, 'missing point')
        return { x = value.x, y = value.y }
    end
    local result = {
        schema = 'itb-observation-v1',
        coverage = 'partial-observation-only',
        identity = 'local-pawn-ids-only',
        unavailable = missing,
        tiles = json.array(),
        pawns = json.array(),
        excluded = json.array({ 'rng-state', 'pending-engine-effects', 'pending-callbacks',
            'mission-script-state', 'spawn-plan', 'weapon-power-and-charges',
            'pilot-abilities', 'off-board-pawns', 'campaign-state' }),
    }
    result.mission = attempt('mission.ID', function() return mission.ID end)
    result.turn = attempt('game.turn', function() return game:GetTurnCount() end)
    result.team = attempt('game.team', function() return game:GetTeamTurn() end)
    result.gridPower = attempt('game.gridPower', function() return game:GetPower():GetValue() end)
    result.size = attempt('board.size', function() return point(board:GetSize()) end)
    if not result.size then return result, false end
    local width, height = result.size.x, result.size.y
    assert(type(width) == 'number' and type(height) == 'number'
        and width >= 1 and height >= 1 and width <= 32 and height <= 32
        and width % 1 == 0 and height % 1 == 0, 'unexpected board dimensions')
    local idle = attempt('board.idle', function()
        local busy = board:IsBusy()
        assert(type(busy) == 'boolean', 'unknown board busy flag')
        return not busy
    end) == true
    local tileMethods = {
        terrain = 'GetTerrain', health = 'GetHealth', fire = 'IsFire', acid = 'IsAcid',
        smoke = 'IsSmoke', frozen = 'IsFrozen', spawning = 'IsSpawning',
        pod = 'IsPod', building = 'IsBuilding', cracked = 'IsCracked',
        environmentDanger = 'IsEnvironmentDanger',
    }
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local loc = env.Point(x, y)
            local tile = { x = x, y = y }
            for field, method in pairs(tileMethods) do
                tile[field] = attempt('tile.' .. x .. '.' .. y .. '.' .. field, function()
                    return board[method](board, loc)
                end)
            end
            result.tiles[#result.tiles + 1] = tile
        end
    end
    local ids = attempt('board.pawns', function()
        local list = board:GetPawns(env.TEAM_ANY)
        local values = {}
        for i = 1, list:size() do values[#values + 1] = list:index(i) end
        table.sort(values)
        return values
    end)
    if not ids then idle = false end
    local pawnMethods = {
        type = 'GetType', team = 'GetTeam', health = 'GetHealth', active = 'IsActive',
        moveSpeed = 'GetMoveSpeed', pathing = 'GetPathProf', fire = 'IsFire', acid = 'IsAcid',
        frozen = 'IsFrozen', shield = 'IsShield', grappled = 'IsGrappled', dead = 'IsDead',
    }
    for _, id in ipairs(ids or {}) do
        local pawn = attempt('pawn.' .. id, function() return board:GetPawn(id) end)
        if pawn then
            local entry = { localId = id }
            for field, method in pairs(pawnMethods) do
                entry[field] = attempt('pawn.' .. id .. '.' .. field, function()
                    return pawn[method](pawn)
                end)
            end
            entry.position = attempt('pawn.' .. id .. '.position', function()
                return point(pawn:GetSpace())
            end)
            local pawnIdle = attempt('pawn.' .. id .. '.idle', function()
                local busy = pawn:IsBusy()
                assert(type(busy) == 'boolean', 'unknown pawn busy flag')
                return not busy
            end)
            if pawnIdle ~= true then idle = false end
            -- These getters are defined by the bundled memedit extension, if enabled.
            entry.movementSpent = attempt('pawn.' .. id .. '.movementSpent', function()
                return pawn:IsMovementSpent()
            end)
            entry.queuedTarget = attempt('pawn.' .. id .. '.queuedTarget', function()
                return point(pawn:GetQueuedTarget())
            end)
            result.pawns[#result.pawns + 1] = entry
        else
            idle = false
        end
    end
    table.sort(missing)
    return result, idle
end

return snapshot
