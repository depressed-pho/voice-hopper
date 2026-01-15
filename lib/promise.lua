require("shim/table")
local Array   = require("collection/array")
local Symbol  = require("symbol")
local class   = require("class")
local console = require("console")
local fun     = require("function")

--
-- A promise represents a value from the future, similar to ECMAScript
-- Promise.
--
local Promise = class("Promise")

-- Promise states
local PENDING   = Symbol("pending")
local FULFILLED = Symbol("fulfilled")
local REJECTED  = Symbol("rejected")

-- Very dirty hack
local ALLOW_MISSING_EXECUTOR = false

local function _resolve(self, ...)
    -- It's a no-op to try to resolve an already settled promise. It's not
    -- even an error.
    if self._state == PENDING then
        -- THINKME: What should we do if the value is another Promise? We
        -- haven't decided yet, have we?
        self._value = Array:of(...)
        self._state = FULFILLED
        self:_settled()
    end
end

local function _reject(self, reason)
    -- It's a no-op to try to reject an already settled promise. It's not
    -- even an error.
    if self._state == PENDING then
        self._value = reason
        self._state = REJECTED
        self:_settled()
    end
end

--
-- Promise:withResolvers() returns 3 values: a promise, a resolve function,
-- and a reject function.
--
Promise:static("withResolvers")
function Promise:withResolvers()
    ALLOW_MISSING_EXECUTOR = true
    local p = Promise:new() -- This will never raise an error.
    ALLOW_MISSING_EXECUTOR = false
    return p, fun.pap(_resolve, p), fun.pap(_reject, p)
end

--
-- Promise:resolve(...) returns a promise which is already resolved with
-- the given arguments.
--
Promise:static("resolve")
function Promise:resolve(...)
    ALLOW_MISSING_EXECUTOR = true
    local p = Promise:new() -- This will never raise an error.
    ALLOW_MISSING_EXECUTOR = false
    p._value = Array:of(...)
    p._state = FULFILLED
    return p
end

--
-- Promise:reject(reason) returns an already rejected promise.
--
Promise:static("reject")
function Promise:reject(reason)
    ALLOW_MISSING_EXECUTOR = true
    local p = Promise:new() -- This will never raise an error.
    ALLOW_MISSING_EXECUTOR = false
    p._value = reason
    p._state = REJECTED
    return p
end

function Promise:__init(executor)
    self._conts = {}  -- Continuations of this promise: a list of coroutines.
    self._value = nil -- Fulfilled or rejected value, or another Promise in the fulfilled case.
    self._state = PENDING

    -- Executor is a regular function, not a coroutine, that we evaluate
    -- synchronously in this constructor. Two thunks "resolve" and "reject"
    -- are passed to the executor, which will be called asynchronously.
    --
    -- It's okay to be nil only when called via Promise:withResolvers().
    if executor == nil then
        if not ALLOW_MISSING_EXECUTOR then
            error("Promise:new() expects an executor function", 2)
        end
    else
        local ok, err = pcall(executor, fun.pap(_resolve, self), fun.pap(_reject, self))
        if not ok then
            self._value = err
            self._state = REJECTED
            self:_settled()
        end
    end
end

function Promise:__tostring()
    if self._state == PENDING then
        return "[Promise: pending]"
    elseif self._state == FULFILLED then
        assert(Array:made(self._value))
        return string.format("[Promise: fulfilled: %s]", self._value:join(", "))
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
        -- Promise:race() and we lost the race.
        if coroutine.status(coro) == "dead" then
            -- Don't do anything in that case.
        else
            local ok, err =
                coroutine.resume(coro, self) -- Promise:race() will need this "self".
            if not ok then
                -- This means we settled a promise and then someone
                -- awaiting it raised an error in response to
                -- it. Propagating the error here, i.e. the thread settled
                -- the promise is going to die, is probably not the right
                -- thing to do.
                console.warn(
                    "A thread that was awaiting a promise raised an error upon settling it." ..
                    " This is most likely due to an unhandled rejection: %s", err)
            end
        end
    end
end

-- Promise:await() suspends the calling coroutine until it is fulfilled or
-- rejected. If it's fulfilled it returns fulfilled values. It it's
-- rejected it raises an error with the reason for the rejection.
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
        assert(Array:made(self._value))
        return self._value:unpack()
    elseif self._state == REJECTED then
        error(self._value, 0) -- Do not rewrite the message.
    else
        error("Invalid promise state: " .. tostring(self._state))
    end
end

-- The Promise:race() static method takes a sequence of promises as input
-- and returns a single Promise. This returned promise settles with the
-- eventual state of the first promise that settles.
--
-- The returned promise remains pending forever if the sequence passed is
-- empty.
Promise:static("race")
function Promise:race(seq)
    assert(type(seq) == "table", "Promise:race() takes a sequence of promises")

    if #seq == 0 then
        -- Special case for optimisation: if there are no promises to race,
        -- we can efficiently create a forever-pending promise.
        ALLOW_MISSING_EXECUTOR = true
        local p = Promise:new() -- This will never raise an error.
        ALLOW_MISSING_EXECUTOR = false
        return p
    end

    local p, resolve, reject = Promise:withResolvers()

    -- We may need to suspend our own coroutine, which means we must do
    -- this asynchronously.
    local coro = coroutine.create(function()
        local coro = coroutine.running()
        for _i, p1 in ipairs(seq) do
            if p1._state == PENDING then
                table.insert(p._conts, coro)
            elseif p1._state == FULFILLED then
                assert(Array:made(p._value))
                resolve(p._value:unpack())
                return
            elseif p1._state == REJECTED then
                reject(p1._value)
                return
            else
                error("Invalid promise state: " .. tostring(p1._state))
            end
        end
        -- Being here means either the sequence is empty or none of the
        -- promises are settled. Suspend ourselves now. When any of the
        -- promises gets settled it will resume us.
        local settled = coroutine.yield()
        if settled._state == FULFILLED then
            assert(Array:made(settled._value))
            resolve(settled._value:unpack())
        elseif settled._state == REJECTED then
            reject(settled._value)
        else
            error("Invalid promise state: " .. tostring(p._state))
        end
    end)

    -- But we can synchronously start this coroutine. It may yield but
    -- that's fine because it will be resumed eventually.
    local ok, err = coroutine.resume(coro)
    if not ok then
        error(err, 0) -- Don't rewrite the error message.
    end

    return p
end

--
-- The Promise:try(func, arg1, arg2, ...) static method returns a Promise
-- that is:
--
-- * Already fulfilled, if `func` synchronously returns a value.
-- * Already rejected, if `func` synchronously throws an error.
-- * Asynchronously fulfilled or rejected, if `func` awaits a promise.
--
-- The function is started synchronously but runs in its own coroutine, so
-- it can freely await promises.
--
Promise:static("try")
function Promise:try(func, ...)
    assert(type(func) == "function", "Promise:try() expects a function")

    local p, resolve, reject = Promise:withResolvers()

    -- Obviously we must create a coroutine now because it may call
    -- :await()
    local coro = coroutine.create(function(...)
        local function settle(ok, ...)
            if ok then
                resolve(...)
            else
                reject(...)
            end
        end
        settle(pcall(func, ...))
    end)

    -- Start the coroutine. It may run till the end, or yield. If it yields
    -- we just hope someone else is going to resume it. When it eventually
    -- terminates we will call our settle() to resolve or reject our
    -- promise.
    local ok, err = coroutine.resume(coro, ...)
    if not ok then
        error("Our coroutine is not supposed to raise an error but it did it regardless: " .. tostring(err), 0)
    end

    return p
end

return Promise
