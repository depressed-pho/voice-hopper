local Promise   = require("promise")
local class     = require("class")
local scheduler = require("thread/scheduler")

-- private
local ThreadCancellationRequested = class("ThreadCancellationRequested")

-- An absolute cooperative (non-preemptive) thread class that runs on
-- UIDispatcher, scheduled with UITimer.
local Thread = class("Thread")

-- The ID of the next thread to be created.
local nextTID = 0

function Thread:__init(name)
    assert(name == nil or type(name) == "string", "Thread:new() takes an optional name string")

    self._id = nextTID
    nextTID = nextTID + 1

    self._name       = name or "(anonymous)"
    self._shouldStop = false
    -- This will be clobbered when the thread starts running.
    self._cancel     = function() end
end

-- An abstract method that will be invoked to run the task of the thread.
function Thread:run(_cancelled)
    error("Threads are expected to override the method run()", 2)
end

-- Start the thread. It doesn't start on its own just by constructing an
-- instance, because that means run() would be invoked even before
-- constructors of subclasses complete.
function Thread:start()
    -- One of the two mechanisms to cancel a thread. The promise is passed
    -- to run() and will never be resolved. When a cancellation is
    -- requested, the promise will be rejected.
    local cancelled = Promise:new(function(_resolve, reject)
        self._cancel = reject
    end)

    -- Create a coroutine and schedule it to run on the next event cycle.
    local coro = coroutine.create(function()
        local succeeded, err = pcall(self.run, cancelled)
        if succeeded then
            -- The thread exited normally.
        elseif ThreadCancellationRequested:made(err) then
            -- The thread didn't catch the cancellation request, which is
            -- perfectly fine.
        else
            error(string.format("Thread #%d (%s) aborted: %s", self._id, self._name, err), 0)
        end
    end)
    scheduler.setTimeout(function()
        local succeeded, err = coroutine.resume(coro)
        if not succeeded then
            error(err, 0) -- Don't rewrite the error message.
        end
    end)

    return self
end

return Thread
