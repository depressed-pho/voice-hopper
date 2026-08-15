local Description = require("reactive/description")
local End         = require("reactive/event").End
local Error       = require("reactive/event").Error
local Event       = require("reactive/event").Event
local EventStream = require("reactive/observable/event-stream")
local Promise     = require("promise")
local Reply       = require("reactive/reply")
local Set         = require("collection/set")
local Value       = require("reactive/event").Value
local class       = require("class")
local fun         = require("function")

-- @private
local Upstream = class("Upstream")
function Upstream:__init(src)
    assert(type(src) == "function")

    self._src   = src -- EventSink => Unsub (where EventSink: Event => Reply, Unsub: () => void)
    self._unsub = nil -- Unsub or nil
end
function Upstream:subscribe(sink)
    assert(type(sink) == "function")

    self._unsub = self._src(sink)
    assert(type(self._unsub) == "function",
           string.format(
               "The upstream %s was expected to return an unsubscriber function but it returned %s",
               self._src, self._unsub))
end
function Upstream:unsubscribe()
    if self._unsub then
        self._unsub()
        self._unsub = nil
    end
end

--
-- An EventStream that allows you to push values into the stream.
--
-- It also allows plugging other streams into the Bus, as inputs. The Bus
-- practically merges all plugged-in streams and the values pushed using
-- the :push() method.
--
local Bus = class("Bus", EventStream)

--
-- Construct a new Bus with no upstreams.
--
function Bus:__init()
    super(
        Description:new("Bus", "new"),
        function (sink)
            return self:_subscribeAll(sink)
        end)

    self._ups     = Set:new() -- Set<Upstream>
    self._sink    = nil       -- Event => Reply
    self._pushing = false     -- boolean
    self._closed  = false     -- boolean
end

function Bus:_subscribeAll(sink)
    assert(type(sink) == "function") -- Event => Reply

    if self._closed then
        -- A downstream appeared but the bus has already been closed.
        sink(End:new())
    else
        self._sink = sink
        for up in self._ups:values() do
            self:_subscribeInput(up)
        end
    end

    return fun.pap(self._unsubAll, self)
end

function Bus:_subscribeInput(up)
    assert(Upstream:made(up))

    up:subscribe(
        function (ev)
            if End:made(ev) then
                -- An upstream declared it reached its end. Remove it.
                up:unsubscribe()
                return Reply.noMore
            else
                assert(self._sink,
                       "We have no downstreams but we didn't unsubscribe from upstreams. " ..
                       "This is an internal logical error")
                return self._sink(ev)
            end
        end)
end

function Bus:_unsubAll()
    for up in self._ups:values() do
        up:unsubscribe()
    end
end

--
-- Push a new value to the stream, and return a Promise to be resolved when
-- the event handling finishes.
--
function Bus:push(val)
    return self:_push(Value:new(val))
end

--
-- End the stream. Send an End event to all subscribers. After this call,
-- there'll be no more events to the subscribers. Also, the :push(),
-- :error() and :plug() methods will have no effect. Return a Promise to be
-- resolved when the event handling finishes.
--
function Bus:close()
    return self:_push(End:new())
end

--
-- Push an error to this stream, and return a Promise to be resolved when
-- the event handling finishes.
--
function Bus:error(err)
    return self:_push(Error:new(err))
end

function Bus:_push(ev)
    assert(Event:made(ev))

    return Promise:try(
        function ()
            if not self._closed then
                if End:made(ev) then
                    self._closed = true
                end
                if self._sink then
                    -- We have downstreams. Send it to them. Discard the event
                    -- otherwise.
                    self._sink(ev)
                end
            end
        end)
end

--
-- Create an EventStream out of the Bus. Since Bus is already a Bus, this
-- method is mostly an identity except that the resulting EventStream is
-- pushing capability stripped off.
--
function Bus:toEventStream()
    return self:transform(
        function (sink, ev)
            return sink(ev)
        end,
        Description:new(self, "toEventStream"))
end

return Bus
