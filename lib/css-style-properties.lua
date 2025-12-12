local CSSStyleProperties = {}

local function camel2kebab(camel)
    local ret = {}

    local s, e = string.find(camel, "^%l*")
    table.insert(ret, string.sub(camel, s, e))

    local idx = e + 1
    while true do
        local s, e = string.find(camel, "^%u%l*", idx)
        if s == nil then
            assert(idx >= string.len(camel), "invalid camelCase: " .. camel)
            break
        else
            table.insert(ret, string.lower(string.sub(camel, s, e)))
            idx = e + 1
        end
    end

    return table.concat(ret, "-")
end

local meta = {}
function meta.__index(self, key)
    local kebab = camel2kebab(tostring(key))
    return self.__props[kebab]
end
function meta.__newindex(self, key, value)
    local kebab = camel2kebab(tostring(key))
    self.__props[kebab] = tostring(value)
end
function meta.__tostring(self)
    local ret = {}
    for key, val in pairs(self.__props) do
        table.insert(ret, string.format("%s: %s", key, val))
    end
    return table.concat(ret, "; ")
end

-- Objects of CSSStyleProperties behaves like a regular table but keys
-- in camelCase are mapped to kebab-case and values are coerced into
-- strings. tostring() will turn the object into "prop1: value1; prop2:
-- value2; ...".
function CSSStyleProperties:new()
    local self = {}
    self.__props = {} -- name in kebab-case => string value

    setmetatable(self, meta)
    return self
end

return CSSStyleProperties
