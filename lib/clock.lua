local class    = require("class")
local readonly = require("readonly")
local ui       = require("ui")

local Instant = class("Instant")

Instant._epoch = os.time()
Instant._timer = nil -- UITimer

function Instant:__init()
    -- Have we activated the global UITimer? If not, do it now.
    if Instant._timer == nil then
        -- This would emit a timeout event every second, but the thread
        -- scheduler won't care because this timer is unknown to it.
        Instant._timer = ui.manager:Timer {
            Interval   = 1000,
            SingleShot = false,
            -- See https://note.com/hitsugi_yukana/n/n20ac7b565be4
            TimerType  = "PreciseTimer"
        }
    end

    self._osTime = os.time()
    self._millis = 1000 - Instant._timer.RemainingTime
end

function Instant:_toNumber()
    return os.difftime(self._osTime, Instant._epoch) + self._millis / 1000
end

function Instant:__tostring()
    return string.format("[Instant: %.3f]", self._toNumber())
end

function Instant.__sub(t0, t1)
    assert(Instant:made(t0), "Expected an Instant: " .. tostring(t0))
    assert(Instant:made(t1), "Expected an Instant: " .. tostring(t1))
    local r0 = t0:_toNumber()
    local r1 = t1:_toNumber()
    return r1 - r0
end

function Instant.__eq(t0, t1)
    assert(Instant:made(t0), "Expected an Instant: " .. tostring(t0))
    assert(Instant:made(t1), "Expected an Instant: " .. tostring(t1))
    return t0._osTime == t1._osTime and t0._millis == t1._millis
end

function Instant.__lt(t0, t1)
    assert(Instant:made(t0), "Expected an Instant: " .. tostring(t0))
    assert(Instant:made(t1), "Expected an Instant: " .. tostring(t1))
    if t0._osTime < t1._osTime then
        return true
    elseif t0._osTime > t1._osTime then
        return false
    else
        return t0._millis < t1._millis
    end
end

function Instant.__le(t0, t1)
    assert(Instant:made(t0), "Expected an Instant: " .. tostring(t0))
    assert(Instant:made(t1), "Expected an Instant: " .. tostring(t1))
    if t0._osTime < t1._osTime then
        return true
    elseif t0._osTime > t1._osTime then
        return false
    else
        return t0._millis <= t1._millis
    end
end

--
-- High-precision clock
--
local clock = {}

--
-- clock.now() returns an opaque object representing the current
-- wallclock. The only way to make sense of the clock is to subtract them:
--
--   local t0 = clock.now()
--   ...
--   local t1 = clock.now()
--   print(t1 - t0) -- prints fractional seconds between t0 and t1
--
-- Or to compare them:
--
--   print(t1 >= t0) -- *supposed* to print true
--
-- Note that the clock is not guaranteed to be monotonic nor steady. In
-- fact it's most likely not.
--
function clock.now()
    return Instant:new()
end

return readonly(clock)
