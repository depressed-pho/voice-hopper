local class = require("VoiceHopper/class")

-- Usage:
--   local val = delay(function ()
--       return 666
--   end)
--   force(val) -- Returns 666
--
local Delayed = class("Delayed")

function Delayed:__init(thunk)
    assert(type(thunk) == "function", "delay() expects its argument to be a thunk")
    self._thunk  = thunk
    self._forced = false
    self._value  = nil
end

function Delayed:__call()
    if not self._forced then
        self._value  = self._thunk()
        self._forced = true
    end
    return self._value
end

local function delay(thunk)
    return Delayed:new(thunk)
end

local function force(delayed)
    assert(isa(delayed, Delayed), "force() expects its argument to be a delayed computation")
    return delayed()
end

--
-- Usage:
--   local t = lazy {
--       foo = function ()
--           return 666
--       end,
--       bar = function (self)
--           return self.foo + 1
--       end,
--   }
--   t.bar -- Evaluates to 667
--
local function lazy(thunks)
    local meta = {}
    meta._forced = {} -- {key = true}

    function meta.__index(obj, key)
        if meta._forced[key] then
            -- Forced but __index() was called, which means the value was
            -- nil.
            return nil
        end

        local thunk = thunks[key]
        assert(thunk, "Field \"" .. key .. "\" not defined")
        assert(type(thunk) == "function", "Field \"" .. key .. "\" is expected to be a thunk: " .. tostring(thunk))

        local value = thunk(obj)
        obj[key] = value
        meta._forced[key] = true

        return value
    end

    local obj = {}
    setmetatable(obj, meta)
    return obj
end

return {
    delay = delay,
    force = force,
    lazy  = lazy
}
