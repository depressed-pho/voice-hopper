local class = require("class")

-- A promise represents a value from the future, similar to ECMAScript
-- Promise.
local Promise = class("Promise")

-- Promise states
local PENDING   = 0
local FULFILLED = 1
local REJECTED  = 2

function Promise:__init(executor)
    self._conts = {}  -- Continuations of this promise: a list of coroutines.
    self._value = nil -- Fulfilled or rejected value, or another Promise in the fulfilled case.
    self._state = PENDING

    -- Executor is a regular function, not a coroutine, that we evaluate
    -- synchronously in this constructor. Two thunks "resolve" and "reject"
    -- are passed to the executor, which will be called asynchronously.
    local function resolve(value)
        if self._state == PENDING then
            self._value = value
            self._state = FULFILLED
            self:_settled()
        else
            error("The promise has already been settled: " .. tostring(self), 2)
        end
    end
    local function reject(reason)
        if self._state == PENDING then
            self._value = reason
            self._state = REJECTED
            self:_settled()
        else
            error("The promise has already been rejected: " .. tostring(self), 2)
        end
    end
    local succeeded, err = pcall(executor, resolve, reject)
    if not succeeded then
        self._value = err
        self._state = REJECTED
        self:_settled()
    end
end

function Promise:__tostring()
    if self._state == PENDING then
        return "[Promise: pending]"
    elseif self._state == FULFILLED then
        return string.format("[Promise: fulfilled: %s]", self._value)
    elseif self._state == REJECTED then
        return string.format("[Promise: rejected: %s]", self._value)
    else
        return string.format("[Promise: invalid state: %s]", self._state)
    end
end

function Promise:_settled()
    local len = #self._conts
    for i=1, len do
        local succeeded, err =
            coroutine.resume(self._conts[i])
        if not succeeded then
            error("FIXME: The coroutine raised an error but we haven't decided what to do: " .. tostring(err))
        end
        -- The promise no longer needs to hold a reference of this
        -- coroutine. We won't resume it ever again.
        self._conts[i] = nil
    end
end

-- Promise:await() suspends the calling coroutine until it is fulfilled or
-- rejected. If it's fulfilled the result will be the fulfilled value. It
-- it's rejected it will raise an error with the reason for the rejection.
function Promise:await()
    if self._state == PENDING then
        local coro = coroutine.running()
        if coro == nil then
            error("The main thread is not allowed to await a Promise", 2)
        end
        table.insert(self._conts, coro)
        coroutine.yield()
    end
    -- Intentionally falling through the PENDING case.
    if self._state == FULFILLED then
        return self._value
    elseif self._state == REJECTED then
        error(self._value, 0) -- Do not rewrite the message.
    else
        error("Invalid promise state: " .. tostring(self._state))
    end
end

return Promise
