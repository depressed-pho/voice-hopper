local Promise   = require("promise")
local scheduler = require("thread/scheduler")

-- Create and return a promise that will be resolved with no values after
-- the given duration of time passes. The duration is in fractional
-- seconds.
local function delay(s)
    assert(type(s) == "number", "delay() expects a non-negative number")
    if s >= math.huge then
        return Promise:race({}) -- forever pending
    else
        local p, resolve = Promise:withResolvers()
        scheduler.setTimeout(resolve, s * 1000)
        return p
    end
end

return delay
