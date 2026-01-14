local readonly = require("readonly")

local CSSStyleProperties = {}

local function camel2kebab(camel)
    local ret = {}

    local s, e = string.find(camel, "^%l*")
    table.insert(ret, string.sub(camel, s, e))

    local idx = e + 1
    while true do
        local s1, e1 = string.find(camel, "^%u%l*", idx)
        if s1 == nil then
            assert(idx >= string.len(camel), "invalid camelCase: " .. camel)
            break
        else
            table.insert(ret, string.lower(string.sub(camel, s1, e1)))
            idx = e1 + 1
        end
    end

    return table.concat(ret, "-")
end

local meta = {}
function meta.__index(self, key)
    key = tostring(key)

    local kebab = camel2kebab(key)
    return self.__props[kebab]
end
function meta.__newindex(self, key, value)
    key = tostring(key)

    local kebab = camel2kebab(key)
    self.__props[kebab] = value
    if self.__cb then
        self.__cb(kebab, value, self)
    end
end
function meta.__tostring(self)
    local ret = {}
    for key, val in pairs(self.__props) do
        table.insert(ret, string.format("%s: %s", key, val))
    end
    return table.concat(ret, "; ")
end

--
-- Objects of CSSStyleProperties behaves like a regular table but keys
-- in camelCase are mapped to kebab-case and values are coerced into
-- strings. tostring() will turn the object into "prop1: value1; prop2:
-- value2; ...".
--
-- If a callback function "cb" is given, it will be called when any of the
-- properties are updated. Its arguments are (prop, value, self) where
-- "prop" is the property name in kebab-case, "value" is the value, and
-- "self" is the CSSStyleProperties itself.
--
function CSSStyleProperties:new(cb)
    assert(cb == nil or type(cb) == "function", "CSSStyleProperties:new() expects an optional callback function")

    local self = {}
    self.__cb    = cb
    self.__props = {} -- name in kebab-case => string value

    setmetatable(self, meta)
    return self
end

return readonly(CSSStyleProperties)
