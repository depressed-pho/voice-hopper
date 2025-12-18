-- Provides scheduling primitives built on top of UITimer. User code is
-- discouraged from using this directly.
local ui = require("ui")

-- The table of currently active timers: UITimer => thunk
local THUNK_OF = {}

-- private
local function setTimer(thunk, interval, singleShot)
    local timer = ui.manager:Timer {
        ID         = tid,
        Interval   = interval or 0,
        SingleShot = singleShot,
    }
    THUNK_OF[timer] = thunk
    timer:Start()
    return timer
end

-- private
local function clearTimer(timer)
    local thunk = THUNK_OF[timer]
    if thunk ~= nil then
        timer:Stop()
        THUNK_OF[timer] = nil
    end
end

-- private
function ui.dispatcher.On.Timeout(ev)
    local timer = ev.sender
    local thunk = THUNK_OF[ev.sender]
    if thunk ~= nil then
        local succeeded, err = pcall(thunk)

        if not timer:GetIsActive() then
            -- The timer is no longer active. It was probably a
            -- single-shot. Remove it from our table.
            THUNK_OF[timer] = nil
        end

        if not succeeded then
            error(err, 0) -- Don't rewrite the error message.
        end
    end
end

-- Invoke a thunk after some delay. The delay is in milliseconds. If delay
-- is omitted, it is defaulted to 0, which means the thunk will be
-- evaluated on the next event cycle.
local function setTimeout(thunk, delay)
    assert(type(thunk) == "function", "setTimeout() expects a thunk as its 1st argument")
    assert(
        delay == nil or
        (type(delay) == "number" and delay >= 0),
        "setTimeout() expects an optional non-negative delay as its 2nd argument")

    return setTimer(thunk, delay, true)
end

-- Cancel a timer created with setTimeout().
local function clearTimeout(tid)
    clearTimer(tid)
end

-- Invoke a thunk with a given interval. The interval is in
-- milliseconds. If interval is omitted, it is defaulted to 0, which means
-- the function will be evaluated on each event cycle.
local function setInterval(thunk, interval, ...)
    assert(type(thunk) == "function", "setInterval() expects a thunk as its 1st argument")
    assert(
        interval == nil or
        (type(interval) == "number" and interval >= 0),
        "setInterval() expects an optional non-negative delay as its 2nd argument")

    return setTimer(thunk, interval, false, ...)
end

-- Cancel a timer created with setInterval().
local function clearInterval(tid)
    clearTimer(tid)
end

return {
    setTimeout    = setTimeout,
    clearTimeout  = clearTimeout,
    setInterval   = setInterval,
    clearInterval = clearInterval,
}
