local Description = require("reactive/description")
local Event       = require("reactive/event").Event
local Initial     = require("reactive/event").Initial
local Next        = require("reactive/event").Next
local Observable  = require("reactive/observable")
local Option      = require("collection/option")
local Reply       = require("reactive/reply")
local Symbol      = require("symbol")
local class       = require("class")
local fun         = require("function")

--
-- EventStream represents a stream of events. It is an Observable object,
-- meaning that you can listen to events in the stream using, for instance,
-- the onValue method with a callback.
--
local EventStream = class("EventStream", Observable)

--
-- If none of the other factory methods above apply, you may of course roll
-- your own EventStream by using :fromBinder().
--
-- The parameter "binder" is a function that accepts a sink which is a
-- function that your binder function can "push" events to.
--
-- For example:
--
--     local R      = require("reactive")
--     local stream = R.EventStream:fromBinder(function (sink)
--         sink(R.Next:new("first value"))
--         sink(R.Next:new("2nd"))
--         sink(R.Error:new("oops, an error"))
--         sink(R.End:new())
--         return function ()
--             -- unsub functionality here, this one's a no-op
--         end
--     end)
--     stream:log()
--
-- The binder function must return a function. Let's call that function
-- "unbind". The returned function can be used by subscribers (directly or
-- indirectly) to unsubscribe from the EventStream. It should release all
-- resources that the binder function reserved.
--
-- The sink function may return R.noMore (as well as nil or any other
-- value). If it returns R.noMore, no further events will be consumed by
-- subscribers. The binder function may choose to clean up all resources at
-- this point (e.g., by calling unbind). This is usually not necessary,
-- because further calls to sink are ignored, but doing so can increase
-- performance if the binder is going to synchronously push a lot of (or
-- infinite number of) events before the unbind function is returned.
--
-- The EventStream will wrap your binder function so that it will only be
-- called when the first stream listener is added, and the unbind function
-- is called only after the last listener has been removed. The bind-unbind
-- cycle may be repeated indefinitely, so prepare for multiple calls to the
-- binder function.
--
EventStream:static("fromBinder")
function EventStream:fromBinder(binder)
    assert(type(binder) == "function", "EventStream:fromBinder() expects a binder function")

    return EventStream:new(
        Description:new("EventStream", "fromBinder", binder),
        function (sink)
            local unbind = binder(
                function (ev)
                    assert(Event:made(ev), "sink expects an Event as its argument")
                    return sink(ev)
                end)
            assert(type(unbind) == "function", "binder is expected to return an unbind function")
            return unbind
        end)
end

--
-- Create an EventStream from EventEmitter events. You can also pass an
-- optional table to use when subscribing to events.
--
EventStream:static("fromEvent")
function EventStream:fromEvent(target, name, opts)
    -- Cant' assert EventEmitter:made(target) because it's a mix-in.
    assert(type(name) == "string" or Symbol:made(name),
           "EventStream:fromEvent() expects an event name as its 2nd argument")
    assert(opts == nil or (type(opts) == "table" and getmetatable(opts) == nil),
           "EventStream:fromEvent() expects an optional table as its 3rd argument")

    local desc = Description:new("EventStream", "fromEvent", target, name, opts)
    return EventStream:fromBinder(
        function (sink)
            local function onEvent(ev)
                sink(Next:new(ev))
            end
            return target:on(name, onEvent, opts)
        end)
        :withDesc(desc)
end

--
-- Create a Property based on the EventStream.
--
-- Without arguments, you'll get a Property without an initial value. The
-- Property will get its first actual value from the stream, and after that
-- it'll always have a current value.
--
-- You can also give an initial value that will be used as the current
-- value until the first value comes from the stream.
--
function EventStream:toProperty(...)
    local init = Option:new(...)

    -- Can't import this at the top-level, because that would form a mutual
    -- dependency.
    local Property = require("reactive/observable/property")
    local initSent = false

    return Property:new(
        Description:new(self, "toProperty", init:unpack()),
        function (sink)
            -- The upstream of this Property is self the EventStream, and
            -- the Property now has its own downstream. If we have an
            -- initial value, push it before anything from the
            -- EventStream. We only need to do this once, because Property
            -- will hold the latest value.
            if not initSent and init.hasValue then
                local reply = sink(Initial:new(init.value))
                initSent = true
                if reply == Reply.noMore then
                    -- But the property says it doesn't want any more
                    -- values, which means it doesn't need to subscribe to
                    -- the EventStream.
                    return fun.const()
                end
            end
            return self:subscribe(sink)
        end)
end

function EventStream:transform(...)
    return self:_transform(EventStream, ...)
end

return EventStream
