local Array       = require("collection/array")
local Queue       = require("collection/queue")
local Set         = require("collection/set")
local Description = require("reactive/description")
local End         = require("reactive/event").End
local Error       = require("reactive/event").Error
local Event       = require("reactive/event").Event
local Reply       = require("reactive/reply")
local Value       = require("reactive/event").Value
local class       = require("class")
local fun         = require("function")

-- @private
local Downstream = class("Downstream")
function Downstream:__init(sink)
    assert(type(sink) == "function")

    self._sink = sink -- Event => Reply
end
function Downstream:push(ev)
    return self._sink(ev)
end

--
-- Observable: the base class for EventStream and Property.
--
local Observable = class("Observable")

-- @private
function Observable:__init(desc, src)
    assert(Description:made(desc), "Observable:new() expects a Description as its 1st argument")
    assert(type(src) == "function", "Observable:new() expects a Source as its 2nd argument")

    self._desc      = desc        -- Description
    self._source    = src         -- EventSink => Unsub (where EventSink: Event => Reply, Unsub: () => void)

    self._name      = nil         -- string or nil
    self._unsubSrc  = nil         -- Unsub or nil
    self._downs     = Set:new()   -- Set<Downstream>
    self._pushing   = false       -- boolean
    self._ended     = false       -- boolean
    self._prevError = nil         -- Error or nil
    self._queue     = Queue:new() -- Queue<Event>
end

function Observable:__tostring()
    if self._name then
        return self._name
    else
        return tostring(self._desc)
    end
end

--
-- Observable#ended is true if the stream has ended, or false otherwise.
--
function Observable.__getter:ended()
    return self._ended
end

--
-- Observable#hasSubscribers is true if there is at least one subscriber to
-- it, or false otherwise.
--
function Observable.__getter:hasSubscribers()
    return self._downs.size > 0
end

-- @private
function Observable:withDesc(desc)
    assert(Description:made(desc), "Observable#withDesc() expects a Description")
    self._desc = desc
    return self
end

function Observable:_handleEvent(ev)
    -- Called when the upstream pushes an event to us.
    assert(Event:made(ev))

    if End:made(ev) then
        self._ended = true
    end

    if self._pushing then
        -- Passing the event to downstreams made the upstream emit new
        -- event. Queue it to prevent stack overflow.
        self._queue:push(ev)
    else
        if ev == self._prevError then
            return
        end
        if Error:made(ev) then
            self._prevError = ev
        end

        self._pushing = true
        local ok, err = pcall(self._pushToDownstreams, self, ev)
        self._pushing = false

        if ok then
            while true do
                local e = self._queue:shift()
                if e then
                    self:_handleEvent(e)
                else
                    break
                end
            end
            if not self.hasSubscribers then
                return Reply.noMore
            end
        else
            -- Ditch queue in case of exception to avoid unexpected behavior.
            self._queue:clear()
            error(err, 0)
        end
    end
end

function Observable:_pushToDownstreams(ev)
    local toRemove -- Set<Downstream> or nil
    for down in self._downs:values() do
        local reply = down:push(ev)
        assert(Reply.isReply(reply))
        if reply == Reply.noMore or End:made(ev) then
            if not toRemove then
                toRemove = Set:new()
            end
            toRemove:add(down)
        end
    end

    if toRemove then
        for down in toRemove:values() do
            self:_removeDownstream(down)
        end
    end
end

function Observable:_removeDownstream(down)
    self._downs:delete(down)
    if not self.hasSubscribers then
        -- It was our last subscriber. Now we should unsubscribe ourselves
        -- from the upstream.
        self._unsubSrc()
        self._unsubSrc = nil
    end
end

--
-- Subscribe a given handler function to Observable. The function will
-- receive Event objects for all new Value, End and Error events from the
-- observable. The subscribe() call returns a unsubscribe function that you
-- can call to unsubscribe. You can also unsubscribe by returning
-- Reactive.noMore from the handler function as a reply to an
-- Event. EventStream#subscribe() and Property#subscribe() behave
-- similarly, except that the latter also pushes the initial value of the
-- property, in case there is one.
--
-- The handler function MAY await a Promise, but it SHOULD NOT block
-- indefinitely. When a single handler blocks, all other handlers will need
-- to wait.
--
-- @param  sink: Event => Reply
-- @return () => void
--
function Observable:subscribe(sink)
    assert(type(sink) == "function", "Observable#subscribe() expects a handler function")

    if self._ended then
        -- The stream has already ended. No actual subscription should
        -- happen.
        sink(End:new())
        return fun.const()
    else
        local down = Downstream:new(sink)
        self._downs:add(down)
        if self._downs.size == 1 then
            -- This is our first downstream. Now we need to subscribe
            -- ourselves to the upstream.
            self._unsubSrc = self._source(fun.pap(self._handleEvent, self))
            assert(type(self._unsubSrc) == "function",
                   string.format(
                       "The upstream of %s was expected to return an unsubscriber function but it returned %s",
                       self, self._unsubSrc))
        end
        return function ()
            self:_removeDownstream(down)
        end
    end
end

--
-- Subscribe a function to stream end. The function will be called when the
-- stream ends. Just like :subscribe() this method returns a function for
-- unsubscribing.
--
-- @param  sink: () => Reply
-- @return () => void
--
function Observable:onEnd(sink)
    assert(type(sink) == "function", "Observable#onEnd() expects a handler function")

    return self:subscribe(
        function (ev)
            if End:made(ev) then
                return sink()
            end
        end)
end

--
-- Subscribe a handler to error events. The function will be called for
-- each error in the stream. Just like subscribe, this method returns a
-- function for unsubscribing.
--
-- @param  sink: any => Reply
-- @return () => void
--
function Observable:onError(sink)
    assert(type(sink) == "function", "Observable#onError() expects a handler function")

    return self:subscribe(
        function (ev)
            if Error:made(ev) then
                return sink(ev.error)
            end
        end)
end

--
-- Subscribe a given handler function to the Observable. The function will
-- be called for each new value. This is the simplest way to assign a
-- side-effect to an Observable. The difference to :subscribe() is that the
-- actual stream values are received, instead of Event objects. Just like
-- :subscribe(), this method returns a function for
-- unsubscribing. EventStream#onValue() and Property:onValue() behave
-- similarly, except that the latter also pushes the initial value of the
-- property, in case there is one.
--
-- @param  sink: any => Reply
-- @return () => void
--
function Observable:onValue(sink)
    assert(type(sink) == "function", "Observable#onValue() expects a handler function")

    return self:subscribe(
        function (ev)
            if Value:made(ev) then
                return sink(ev.value)
            end
        end)
end

--
-- Log each value of the Observable to the console. It optionally takes
-- arguments to pass to console:log() alongside each value. To assist with
-- chaining, it returns the original Observable. Note that as a
-- side-effect, the observable will have a constant listener and will not
-- be garbage-collected. So, use this for debugging only and remove from
-- production code.
--
function Observable:log(...)
    local args    = Array:of(...)
    local console = require("console")

    self:subscribe(
        function (ev)
            console:log((args .. Array:of(ev)):unpack())
        end)

    return self
end

--
-- Map values using given function, returning a new Observable with the
-- same type.
--
-- @param  f: any => any
-- @return Self
--
function Observable:map(f)
    assert(type(f) == "function", "Observable#map() expects a value-mapping function")

    return self:transform(
        function (sink, ev)
            return sink(ev:map(f))
        end,
        Description:new(self, "map", f))
end

--
-- Let you do more custom event handling: you get all events to your
-- function and you can output any number of events and end the stream if
-- you choose. For example, to send an error and end the stream in case a
-- value is below zero:
--
-- local t = o:transform(
--     function (sink, ev)
--         if Value:made(ev) and ev.value < 0 then
--             sink(Error:new("Value below zero"))
--             return sink(End:new())
--         else
--             return sink(ev)
--         end
--     end)
--
-- Note that it's important to return the value from sink so that the
-- connection to the underlying stream will be closed when no more events
-- are needed.
--
-- @param  tr:   (ev: Event, sink: (Event) => Reply) => Reply
-- @param  desc: Description | nil
-- @return Self
--
Observable:abstract("transform")

-- @private
function Observable:_transform(ctor, tr, desc)
    assert(class.isBaseOf(Observable, ctor))
    assert(type(tr) == "function",
           class.nameOf(ctor) .. "#transform() expects a transformer function as its 1st argument")
    assert(desc == nil or Description:made(desc),
           class.nameOf(ctor) .. "#transform() expects an optional Description as its 2nd argument")

    local ret = ctor:new(
        Description:new(self, "transform", tr),
        function (sink)
            return self:subscribe(
                function (ev)
                    return tr(sink, ev)
                end)
        end)
    if desc then
        return ret:withDesc(desc)
    else
        return ret
    end
end

return Observable
