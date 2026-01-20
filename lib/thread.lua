local Promise   = require("promise")
local class     = require("class")
local console   = require("console")
local scheduler = require("thread/scheduler")

-- private
local ThreadCancellationRequested = class("ThreadCancellationRequested")

--
-- An abstract cooperative (non-preemptive) thread class that runs on
-- UIDispatcher, scheduled with UITimer.
--
local Thread = class("Thread")

-- The ID of the next thread to be created.
Thread._nextTid = 0
function Thread._getNextTid()
    local self    = Thread
    local tid     = self._nextTid
    self._nextTid = self._nextTid + 1
    return tid
end

-- A weak map from coroutine to its corresponding Thread object. Only the
-- keys should be weak. That is, when a coroutine terminates its
-- corresponding Thread should be GC'ed if everyone has abandoned the
-- thread handle. But the thread handle should not be GC'ed as long as its
-- coroutine is alive, because it may still want to yield(). This means the
-- Thread object must not retain a reference to its own coroutine.
Thread._threadFor = setmetatable({}, {__mode = "k"})

function Thread:__init(name)
    assert(name == nil or type(name) == "string", "Thread:new() takes an optional name string")

    self._id               = Thread._getNextTid()
    self._name             = name or "(anonymous)"
    self._hasStarted       = false
    self._shouldStop       = false
    self._onUnhandledError = function(err)
        console:error("Thread #%d (%s) aborted: %s", self._id, self._name, err)
    end

    self._terminated, self._resolveTerminated, self._rejectTerminated =
        Promise:withResolvers()

    -- One of the two mechanisms to cancel a thread. The promise is passed
    -- to run() and will never be resolved. When a cancellation is
    -- requested, the promise will be rejected.
    local p, _resolve, reject = Promise:withResolvers()
    self._cancelled  = p
    self._cancel     = function()
        reject(ThreadCancellationRequested:new())
    end
end

-- An abstract method that will be invoked to run the task of the thread.
function Thread:run(_cancelled)
    error("Threads are expected to override the method run()", 2)
end

-- Start the thread. It doesn't start on its own just by constructing an
-- instance, because that means run() would be invoked even before
-- constructors of subclasses complete.
function Thread:start()
    if self._hasStarted then
        return self
    end

    -- Create a coroutine and schedule it to run on the next event cycle.
    local coro = coroutine.create(function()
        local function inspect(ok, ...)
            if ok then
                -- The thread exited normally.
                self._resolveTerminated(...)
            else
                local err = ...
                if ThreadCancellationRequested:made(err) then
                    -- The thread didn't catch the cancellation request,
                    -- which is perfectly fine. Threads aren't supposed to
                    -- catch these.
                    self._resolveTerminated()
                elseif self._onUnhandledError then
                    local function inspectAgain(ok, ...)
                        if ok then
                            self._resolveTerminated(...)
                        else
                            self._rejectTerminated(...)
                        end
                    end
                    inspectAgain(pcall(self._onUnhandledError, err))
                else
                    self._rejectTerminated(err)
                end
            end
        end
        inspect(pcall(self.run, self, self._cancelled))
    end)

    -- The coroutine has not started yet. Register it to our table before
    -- starting it so that it can call Thread:yield().
    Thread._threadFor[coro] = self

    -- Then schedule it.
    scheduler.setTimeout(function()
        local ok, err = coroutine.resume(coro)
        if not ok then
            error(err, 0) -- Don't rewrite the error message.
        end
    end)

    self._hasStarted = true
    return self
end

--
-- This is a function to be called when the thread is terminated due to an
-- unhandled error. When a handler is set and the thread dies from an
-- unhandled error, the handler will be called with the error to intercept
-- the regular flow regarding join(). The promise returned from join() will
-- be resolved with whatever values the handler returns, as opposed to
-- being rejected.
--
-- If the handler itself raises an error, the promise returned from join()
-- will be rejected with that error. The original error can be lost in this
-- case if the handler doesn't re-raise it.
--
-- The handler must not yield, or await any promises. Due to technical
-- reasons there is no protection against this mistake, and very confusing
-- errors will happen.
--
-- Threads have a default error handler by default. The default handler
-- prints the error to the console and returns normally. If you want to
-- handle it in your own way, you must remove the handler by setting it to
-- nil.
--
function Thread.__getter:onUnhandledError()
    return self._onUnhandledError
end
function Thread.__setter:onUnhandledError(handler)
    assert(handler == nil or type(handler) == "function",
           "Thread#onUncaughtError is expected to be an optional function")
    self._onUnhandledError = handler
end

-- Voluntarily suspend the calling thread until the next event cycle.
Thread:static("yield")
function Thread:yield()
    local coro = coroutine.running()
    if coro == nil then
        error("The main thread is not allowed to yield", 2)
    end

    local thr = Thread._threadFor[coro]
    if thr == nil then
        error("No thread objects found for the coroutine " .. tostring(coro))
    end

    -- Thread:yield() is the only place we can raise this error in response
    -- to a cancellation request. We cannot interrupt a thread when it's
    -- awaiting a promise. In that case the thread has to Promise:race()
    -- with the cancellation promise in order to respond to the request in
    -- a timely manner.
    if thr._shouldStop then
        error(ThreadCancellationRequested:new(), 2)
    end

    -- Schedule it to resume later.
    scheduler.setTimeout(function()
        local ok, err = coroutine.resume(coro)
        if not ok then
            error(err, 0) -- Don't rewrite the error message.
        end
    end)
end

--
-- Return a promise to be resolved with the result of :run() when the
-- thread exits normally, or be rejected when it dies with an
-- error. Getting a cancellation request and not catching it does not count
-- as an error, instead it will be treated as if the thread exited normally
-- with no return values. If the thread has already terminated, the
-- resulting promise will be an already settled one.
--
-- See the caveat on Thread#onUncaughtError. The promise will never be
-- rejected by default.
--
-- Unlike the POSIX threading API, it is legal to join a thread more than
-- once. Subsequent joins will just return the same settled promise.
--
function Thread:join()
    if not self._hasStarted then
        error("The thread has never been started", 2)
    end

    local coro = coroutine.running()
    if coro == nil then
        error("The main thread is not allowed to join a thread", 2)
    end

    if Thread._threadFor[coro] == self then
        error("Joining its own thread will deadlock", 2)
    end

    return self._terminated
end

-- Request a cancellation of a thread. The thread is expected to terminate
-- itself shortly, but there's no guarantee of that. This operation is
-- asynchronous, that is, cancel() may return before the thread actually
-- terminates. If you want to wait for its termination, call join() after
-- this.
function Thread:cancel()
    if not self._hasStarted then
        error("The thread has never been started", 2)
    end
    self._shouldStop = true
    self._cancel() -- Reject the cancellation promise.
    return self
end

return Thread
