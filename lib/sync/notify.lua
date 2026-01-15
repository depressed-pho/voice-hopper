local Promise = require("promise")
local Queue   = require("collection/queue")
local class   = require("class")

--
-- "Notify" provides a basic mechanism to notify a single thread of an
-- event. "Notify" itself does not carry any data. Instead, it is to be
-- used to signal another thread to perform an operation.
--
local Notify = class("Notify")

function Notify:__init()
    self._waiters   = Queue:new() -- Queue of resolve() functions.
    self._permitted = false
end

--
-- Wait for a notification.
--
-- Each Notify value holds a single permit. If a permit is available from
-- an earlier call to :notifyOne(), then :notified() will complete
-- immediately, consuming that permit. Otherwise, :notified() waits for a
-- permit to be made available by the next call to :notifyOne().
--
-- This function returns a promise. The caller will need to await() it.
--
function Notify:notified()
    if self._permitted then
        -- Return an already resolved promise.
        self._permitted = false
        return Promise:resolve()
    else
        -- Push an unfulfilled promise to the queue and return it.
        local p, resolve = Promise:withResolvers()
        self._waiters:push(resolve)
        return p
    end
end

--
-- Notify a waiting thread.
--
-- If a thread is currently waiting, that thread is notified. Otherwise, a
-- permit is stored in this "Notify" value and the next call to :notified()
-- will complete immediately consuming the permit made available by this
-- call to :notifyOne().
--
-- At most one permit may be stored by "Notify". Many sequential calls to
-- :notifyOne() will result in a single permit being stored. The next call
-- to :notified() will complete immediately, but the one after that will
-- wait.
--
function Notify:notifyOne()
    if self._waiters.length == 0 then
        -- No waiters exist. Store a permit.
        self._permitted = true
    else
        -- Awake one waiting thread.
        local resolve = self._waiters:shift()
        resolve()
    end
end

--
-- Notify all waiting threads.
--
-- If a thread is currently waiting, that thread is notified. Unlike with
-- :notifyOne(), no permit is stored to be used by the next call to
-- :notified(). The purpose of this method is to notify all already
-- registered waiters.
--
function Notify:notifyAll()
    for resolve in self._waiters:values() do
        resolve()
    end
    self._waiters:clear()
end

return Notify
