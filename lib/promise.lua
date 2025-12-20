local class     = require("class")
local scheduler = require("thread/scheduler")

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
        -- The promise no longer needs to hold a reference of this
        -- coroutine. We won't resume it ever again.
        local coro = self._conts[i]
        self._conts[i] = nil

        -- The coroutine is possibly dead, that is, it might have done
        -- Promise.race() and we lost the race.
        if coroutine.status(coro) == "dead" then
            -- Don't do anything in that case.
        else
            local succeeded, err =
                coroutine.resume(coro, self) -- Promise.race() will need this "self".
            if not succeeded then
                -- This means we settled a promise and then someone
                -- awaiting it raised an error in response to
                -- it. Propagating the error here, i.e. the thread settled
                -- the promise is going to die, is probably not the right
                -- thing to do.
                print("WARNING: A thread that was awaiting a promise raised an error upon settling it: "..tostring(err))
            end
        end
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

-- The Promise.race() static method takes a sequence of promises as input
-- and returns a single Promise. This returned promise settles with the
-- eventual state of the first promise that settles.
--
-- The returned promise remains pending forever if the sequence passed is
-- empty.
function Promise.race(seq)
    assert(type(seq) == "table", "Promise.race() takes a sequence of promises")

    return Promise:new(function(resolve, reject)
        -- We are going to refer to our own coroutine, which means we must
        -- do this asynchronously.
        local coro = coroutine.create(function()
            local coro = coroutine.running()
            for _i, p in ipairs(seq) do
                if p._state == PENDING then
                    table.insert(p._conts, coro)
                elseif p._state == FULFILLED then
                    resolve(p._value)
                    return
                elseif p._state == REJECTED then
                    reject(p._value)
                    return
                else
                    error("Invalid promise state: " .. tostring(p._state))
                end
            end
            -- Being here means either the sequence is empty or none of the
            -- promises are settled. Suspend ourselves now. When any of the
            -- promises gets settled it will resume us.
            local settled = coroutine.yield()
            if settled._state == FULFILLED then
                resolve(settled._value)
            elseif settled._state == REJECTED then
                reject(settled._value)
            else
                error("Invalid promise state: " .. tostring(p._state))
            end
        end)

        scheduler.setTimeout(function()
            local succeeded, err = coroutine.resume(coro)
            if not succeeded then
                error(err, 0) -- Don't rewrite the error message.
            end
        end)
    end)
end

return Promise
