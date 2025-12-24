local Promise   = require("promise")
local scheduler = require("thread/scheduler")

-- Create and return a promise that will be resolved with nil after the
-- given duration of time passes. The duration is in fractional seconds.
local function delay(s)
    return Promise:new(function(resolve)
        scheduler.setTimeout(resolve, s * 1000)
    end)
end

return delay
