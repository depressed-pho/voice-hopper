require("shim/table")
local Array     = require("collection/array")
local readonly  = require("readonly")
local scheduler = require("thread/scheduler")

--
-- Event handling utilities
--
local event = {}

--
-- event.debounce(func, delay) returns a function which, when called, calls
-- the original function with all the arguments redirected but only does so
-- after the given "quiet period". The delay is in fractional seconds:
--
--     f:              asdf----asdf----
--     debounce(f, 2): -----f-------f--
--
function event.debounce(func, delay)
    assert(type(func ) == "function", "event.debounce() expects a function as its 1st argument")
    assert(type(delay) == "number" and delay >= 0.0,
           "event.debounce() expects a non-negative number as its 2nd argument")

    local args  = nil
    local timer = nil

    local function call()
        timer = nil
        func(args:unpack())
    end

    return function(...)
        args = Array:of(...)

        if timer == nil then
            timer = scheduler.setTimeout(call, delay * 1000)
        else
            scheduler.restartTimeout(timer)
        end
    end
end

return readonly(event)
