-- Deterministic diagnostic encoding; no decoder or executable payloads.
local json = {}
local arrayTag = {}

function json.array(value)
    return setmetatable(value or {}, arrayTag)
end

local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
        if char == '"' then return '\\"' end
        if char == '\\' then return '\\\\' end
        return string.format('\\u%04x', string.byte(char))
    end) .. '"'
end

local function encode(value, seen)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'string' then return quote(value) end
    if kind == 'number' then
        assert(value == value and value ~= math.huge and value ~= -math.huge, 'non-finite number')
        if value == 0 then return '0' end
        return string.format('%.17g', value)
    end
    assert(kind == 'table', 'unsupported diagnostic value: ' .. kind)
    assert(not seen[value], 'cyclic diagnostic table')
    seen[value] = true
    local parts = {}
    if getmetatable(value) == arrayTag then
        local count = 0
        for key in pairs(value) do
            assert(type(key) == 'number' and key >= 1 and key % 1 == 0, 'invalid array index')
            count = count + 1
        end
        for i = 1, count do
            assert(value[i] ~= nil, 'sparse array')
            parts[i] = encode(value[i], seen)
        end
        seen[value] = nil
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for key in pairs(value) do
        assert(type(key) == 'string', 'object keys must be strings')
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = quote(key) .. ':' .. encode(value[key], seen)
    end
    seen[value] = nil
    return '{' .. table.concat(parts, ',') .. '}'
end

function json.encode(value)
    return encode(value, {})
end

return json
