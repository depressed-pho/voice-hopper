local Promise   = require("promise")
local scheduler = require("thread/scheduler")

-- Create and return a promise that will be resolved with nil after the
-- given duration of time passes.
local function delay(ms)
    return Promise:new(function(resolve)
        scheduler.setTimeout(resolve, ms)
    end)
end

return delay
