local SYM_FAMILY = {}
local SYM_INDEX  = {}

--
-- Usage:
--
--   local enum = require("enum")
--
--   local Severity = enum {
--       "Debug", -- Values need not be strings. Any values will do.
--       "Log",
--       "Info",
--       "Warn",
--       "Error"
--   }
--
--   print(Severity.Debug)                -- prints "Debug"
--   print(Severity.Debug < Severity.Log) -- prints true
--   print(Severity:has(Severity.Log)     -- prints true
--   print(Severity:has("Log")            -- prints false
--
local function enum(names)
    assert(type(names) == "table", "enum() expects a sequence of value names")

    -- Distinguishing enum values from those from other enum groups
    local family = {}
    local function indexOf(v)
        if type(v) ~= "table" then
            error("Enum values can only be compared with other enum values: "..tostring(v), 2)
        end

        local meta = getmetatable(v)
        if not meta then
            error("Enum values can only be compared with other enum values: "..tostring(v), 2)
        elseif meta[SYM_FAMILY] ~= family then
            error("Enum values can only be compared with other enum values from the same enum group: "..tostring(v), 2)
        else
            return meta[SYM_INDEX]
        end
    end
    local function has(self, v)
        if type(v) ~= "table" then
            return false
        end

        local meta = getmetatable(v)
        return meta and meta[SYM_FAMILY] == family
    end

    -- Comparison functions
    local function __eq(v1, v2)
        return rawequal(v1, v2)
    end
    local function __lt(v1, v2)
        return indexOf(v1) < indexOf(v2)
    end
    local function __le(v1, v2)
        return indexOf(v1) <= indexOf(v2)
    end

    local symbolFor = {} -- {[name] = Symbol-like object}
    for i, name in ipairs(names) do
        if name == "has" then
            error("The name \"has\" is reserved and cannot be used as an enum value", 2)
        end
        symbolFor[name] = setmetatable(
            {},
            {
                [SYM_FAMILY] = family,
                [SYM_INDEX ] = i,
                __eq         = __eq,
                __lt         = __lt,
                __le         = __le,
                __tostring   = function()
                    return tostring(name)
                end
            })
    end

    return setmetatable(
        {},
        {
            __index = function(self, key)
                if key == "has" then
                    return has
                else
                    local sym = symbolFor[key]
                    if sym then
                        return sym
                    else
                        error("No such value exists in this enum group: "..tostring(key), 2)
                    end
                end
            end,
            __newindex = function()
                error("Enum tables are read-only", 2)
            end
        })
end

return enum
