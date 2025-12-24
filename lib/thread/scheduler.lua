require("shim/table")
local readonly = require("readonly")
local ui       = require("ui")

--
-- Provides scheduling primitives built on top of UITimer (see
-- app:GetHelp("UITimer")). User code is discouraged from using this
-- directly.
--
local scheduler = {}

-- The table of currently active timers: UITimer => [thunk, args, nArgs]
local TASK_OF = {}

local function setTimer(func, interval, singleShot, ...)
    local timer = ui.manager:Timer {
        Interval   = math.floor(interval) or 0,
        SingleShot = singleShot,
    }
    TASK_OF[timer] = {func, {...}, select("#", ...)}
    timer:Start()
    return timer
end

local function restartTimer(timer)
    timer:Start()
end

local function clearTimer(timer)
    timer:Stop()
    TASK_OF[timer] = nil
end

function ui.dispatcher.On.Timeout(ev)
    local timer = ev.sender
    local task  = TASK_OF[ev.sender]
    if task ~= nil then
        local succeeded, err = pcall(task[1], table.unpack(task[2], 1, task[3]))

        if not timer:GetIsActive() then
            -- The timer is no longer active. It was probably a
            -- single-shot. Remove it from our table.
            TASK_OF[timer] = nil
        end

        if not succeeded then
            error(err, 0) -- Don't rewrite the error message.
        end
    end
end

--
-- Call a function after some delay with the supplied arguments. The delay
-- is in milliseconds. If delay is omitted, it is defaulted to 0, which
-- means the function will be called on the next event cycle.
--
function scheduler.setTimeout(func, delay, ...)
    assert(type(func) == "function", "setTimeout() expects a function as its 1st argument")
    assert(
        delay == nil or
        (type(delay) == "number" and delay >= 0),
        "setTimeout() expects an optional non-negative delay as its 2nd argument")

    return setTimer(func, delay, true, ...)
end

--
-- Restart a timer created with setTimeout().
--
function scheduler.restartTimeout(timer)
    restartTimer(timer)
end

--
-- Cancel a timer created with setTimeout().
--
function scheduler.clearTimeout(timer)
    clearTimer(timer)
end

--
-- Call a function repeatedly in a given interval with the supplied
-- arguments. The interval is in milliseconds. If interval is omitted, it
-- is defaulted to 0, which means the function will be called on each
-- event cycle.
--
function scheduler.setInterval(func, interval, ...)
    assert(type(func) == "function", "setInterval() expects a function as its 1st argument")
    assert(
        interval == nil or
        (type(interval) == "number" and interval >= 0),
        "setInterval() expects an optional non-negative delay as its 2nd argument")

    return setTimer(func, interval, false, ...)
end

--
-- Restart a timer created with setInterval().
--
function scheduler.restartInterval(timer)
    restartTimer(timer)
end

--
-- Cancel a timer created with setInterval().
--
function scheduler.clearInterval(timer)
    clearTimer(timer)
end

return readonly(scheduler)
