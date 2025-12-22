local class = require("class")

-- An event emitter is a mixin that allows callback functions to listen to
-- events. "base" is an optional base class that can be nil.
local function EventEmitter(base)
    local klass = class("EventEmitter", base)

    -- allowedEvents is a list of event names that can be nil. When it's
    -- not nil the event emitter becomes restricted, which disallows
    -- listeners to listen on events that aren't included in it.
    function klass:__init(allowedEvents, ...)
        super(...)
        self._listenersOf = {} -- {[name] = {[fun] = boolean}}

        if allowedEvents == nil then
            self._allowedEvents = nil
        else
            assert(
                type(allowedEvents) == "table",
                "EventEmitter:new() expects an optional list of event names in its 1st argument")
            self._allowedEvents = {} -- {[name] = true}
            for _i, name in ipairs(allowedEvents) do
                assert(
                    type(name) == "string",
                    "EventEmitter:new() expects an optional list of event names in its 1st argument")
                self._allowedEvents[name] = true
            end
        end
    end

    function klass:on(name, fun)
        assert(type(name) == "string", "EventEmitter:on() expects an event name as its 1st argument")
        assert(type(fun) == "function", "EventEmitter:on() expects a listener function as its 2nd argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. name .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        if listenersOf == nil then
            listenersOf = {}
            self._listeners[name] = listenersOf
        end
        listenersOf[fun] = false -- not once

        return self
    end

    function klass:once(name, fun)
        assert(type(name) == "string", "EventEmitter:once() expects an event name as its 1st argument")
        assert(type(fun) == "function", "EventEmitter:once() expects a listener function as its 2nd argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. name .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        if listenersOf == nil then
            listenersOf = {}
            self._listeners[name] = listenersOf
        end
        listenersOf[fun] = true -- once

        return self
    end

    function klass:off(name, fun)
        assert(type(name) == "string", "EventEmitter:on() expects an event name as its 1st argument")
        assert(type(fun) == "function", "EventEmitter:on() expects a listener function as its 2nd argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. name .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        if listenersOf ~= nil then
            listenersOf[fun] = nil
        end

        return self
    end

    function klass:emit(name, ...)
        assert(type(name) == "string", "EventEmitter:emit() expects an event name as its 1st argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. name .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        for fun, once in pairs(listenersOf) do
            local succeeded, err = pcall(fun, ...)
            if not succeeded then
                -- It wouldn't be the right thing to abort the entire event
                -- handling just because a single listener raised an error.
                print(err)
            end
        end

        return self
    end

    return klass
end

return EventEmitter
