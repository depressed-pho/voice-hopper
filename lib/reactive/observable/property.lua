local Array       = require("collection/array")
local Description = require("reactive/description")
local End         = require("reactive/event").End
local Error       = require("reactive/event").Error
local Event       = require("reactive/event").Event
local Initial     = require("reactive/event").Initial
local Next        = require("reactive/event").Next
local Observable  = require("reactive/observable")
local Option      = require("collection/option")
local Reply       = require("reactive/reply")
local Set         = require("collection/set")
local Value       = require("reactive/event").Value
local class       = require("class")
local fun         = require("function")

--
-- A reactive property. Has the concept of "current value". You can create
-- a Property from an EventStream by using either :toProperty() or :scan()
-- method. Note: depending on how a Property is created, it may or may not
-- have an initial value. The current value stays as its last value after
-- the stream has ended.
--
local Property = class("Property", Observable)

function Property:__init(desc, src)
    super(desc, src)

    self._current = Option:new()
end

function Property:_handleEvent(ev)
    --
    -- We must override Observable#_handleEvent() so that we can retain the
    -- latest value.
    --
    assert(Event:made(ev))

    if Value:made(ev) then
        self._current.value = ev.value
    end
    return super:_handleEvent(ev)
end

function Property:subscribe(sink)
    --
    -- We must override Observable#subscribe() because every time a new
    -- downstream appears we need to send the current value to it.
    --
    assert(type(sink) == "function", "Property#subscribe() expects a handler function")

    if self._current.hasValue and (self.ended or self.hasSubscribers) then
        -- In this case super:subscribe() will not send an Initial event to
        -- this downstream, so we must do it here.
        local reply = sink(Initial:new(self._current.value))
        if reply == Reply.noMore then
            -- And the downstream says it doesn't want anything more!
            return fun.const()
        end
    end
    return super:subscribe(sink)
end

--
-- Create a constant property with the given value.
--
Property:static("constant")
function Property:constant(k)
    return Property:new(
        Description:new(self, "constant", k),
        function (sink)
            sink(Initial:new(k))
            sink(End:new())
            return fun.const()
        end)
end

--
-- Combine Observable's so that the result Property will have an array of
-- the latest values from all sources as its value.
--
-- local p = Property:combineAsArray(
--     Property:constant(1),
--     EventStream:once(2)
-- ) -- "p" produces Array:of(1, 2)
--
Property:static("combineAsArray")
function Property:combineAsArray(...)
    local ss = Array:of(...)

    if ss.length == 0 then
        -- A special case with no sources.
        return Property:constant(Array:of())
    end

    for src in ss:values() do
        assert(Observable:made(src), "Property:combineAsArray() expects Observable's")
    end
    return Property:new(
        Description:new(self, "combineAsArray", ...),
        function (sink)
            local current = Array:new(ss.length)
            local unsubs  = Array:new()
            local alive   = Set:new(ss:values())
            local noData  = Set:new(ss:values())

            for i, src in ss:entries() do
                local unsub = src:subscribe(
                    function (ev)
                        if End:made(ev) then
                            -- One of the sources ended. If this is the
                            -- last source, end the combined stream too.
                            alive:delete(src)
                            if alive.size == 0 then
                                sink(ev)
                                return Reply.noMore
                            end

                        elseif Error:made(ev) then
                            -- Got an error from one of the
                            -- sources. Redirect it to the combined stream.
                            return sink(ev)

                        else
                            assert(Value:made(ev))
                            -- Got a value from one of the sources. Update
                            -- the slot of the current value that
                            -- corresponds to this source, and if all slots
                            -- have values emit the array.
                            current[i] = ev.value
                            noData:delete(src)
                            if noData.size == 0 then
                                return sink(Next:new(current:clone()))
                            end
                        end
                    end)
                unsubs:push(unsub)
            end

            return function ()
                for unsub in unsubs:values() do
                    unsub()
                end
            end
        end)
end

--
-- Combine given n Observable's using the given n-ary function f(v1, v2
-- ...).
--
-- To calculate the current sum of three numeric Properties, you can do
--
-- Property:combineWith(
--     function (x, y, z)
--         return x + y + z
--     end,
--     p1, p2, p3)
--
Property:static("combineWith")
function Property:combineWith(f, ...)
    assert(type(f) == "function", "Property:combineWith() expects a combining function as its 1st argument")

    local desc = Description:new(self, "combineWith", f, ...)
    return Property:combineAsArray(...):map(
        function (values)
            return f(values:unpack())
        end)
        :withDesc(desc)
end

--
-- Create an EventStream/Property by sampling this property value at each
-- event from the sampler stream. The result will contain the sampled value
-- at each event in the property. The result of this method is an
-- EventStream if the sampler is an EventStream, or Property if it's a
-- Property.
--
function Property:sampledBy(sampler)
    -- Can't import this at the top-level, because that would form a mutual
    -- dependency.
    local EventStream = require("reactive/observable/event-stream")

    if EventStream:made(sampler) then
        return self:_sampledBy(EventStream, sampler)

    elseif Property:made(sampler) then
        return self:_sampledBy(Property, sampler)

    else
        error("Property#sampledBy() expects either an EventStream or a Property as a sampler", 2)
    end
end
function Property:_sampledBy(klass, sampler)
    return klass:new(
        Description:new(self, "sampledBy", sampler),
        function (sink)
            local current      = Option:new()
            local unsubSamplee = self:subscribe(
                function (ev)
                    if End:made(ev) then
                        -- The samplee ended but that doesn't matter. As
                        -- long as the sampler goes on, the combined stream
                        -- should not end.

                    elseif Error:made(ev) then
                        -- Got an error from the samplee. Redirect it to
                        -- the combined stream.
                        return sink(ev)

                    else
                        assert(Value:made(ev))
                        -- Got a new value from the samplee. Save it but
                        -- don't send.
                        current.value = ev.value
                        -- We don't need to do anything special, even if
                        -- it's an Initial event and the sampler is a
                        -- Property. As soon as we sub to the sampler we'll
                        -- (probably) get an initial value from it, and we
                        -- can send this saved value in response.
                    end
                end)
            local unsubSampler = sampler:subscribe(
                function (ev)
                    if End:made(ev) then
                        -- The sampler ended. End the combined stream too.
                        sink(ev)
                        unsubSamplee()
                        return Reply.noMore

                    elseif Error:made(ev) then
                        -- Got an error from the sampler. Redirect it to
                        -- the combined stream.
                        return sink(ev)

                    else
                        assert(Value:made(ev))
                        -- Got a value from the sampler. Ignore it, and
                        -- send the current sampled value instead.
                        if current.hasValue then
                            return sink(Next:new(current.value))
                        end
                    end
                end)
            return function ()
                unsubSamplee()
                unsubSampler()
            end
        end)
end

function Property:transform(...)
    return self:_transform(Property, ...)
end

return Property
