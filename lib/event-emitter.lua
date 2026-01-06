local Symbol = require("symbol")
local class  = require("class")

local function isName(name)
    return type(name) == "string" or Symbol.isSymbol(name)
end

--
-- An event emitter is a mixin that allows callback functions to listen to
-- events. "base" is an optional base class that can be nil.
--
-- An event name is either a string or a symbol.
--
local function EventEmitter(base)
    local klass = class("EventEmitter", base)

    --
    -- allowedEvents is an optional list of event names. When it's present
    -- the event emitter becomes restricted, which disallows listeners to
    -- listen on events that aren't part of it.
    --
    function klass:__init(allowedEvents, ...)
        super(...)
        self._listenersOf = {} -- {[name] = {[origFun] = wrappedFun}}

        if allowedEvents == nil then
            self._allowedEvents = nil
        else
            assert(
                type(allowedEvents) == "table",
                "EventEmitter:new() expects an optional list of event names in its 1st argument")
            self._allowedEvents = {} -- {[name] = true}
            for _i, name in ipairs(allowedEvents) do
                assert(isName(name), "EventEmitter:new() expects an optional list of event names in its 1st argument")
                self._allowedEvents[name] = true
            end
        end
    end

    function klass:on(name, func)
        assert(isName(name), "EventEmitter:on() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter:on() expects a listener function as its 2nd argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        if listenersOf == nil then
            listenersOf = {}
            self._listeners[name] = listenersOf
        end
        listenersOf[func] = func

        return self
    end

    function klass:once(name, func)
        assert(isName(name), "EventEmitter:once() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter:once() expects a listener function as its 2nd argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        if listenersOf == nil then
            listenersOf = {}
            self._listeners[name] = listenersOf
        end
        listenersOf[func] = function(...)
            local ok, err = pcall(func, ...)

            listenersOf[func] = nil

            if not ok then
                error(err, 0) -- Don't rewrite the error.
            end
        end

        return self
    end

    function klass:off(name, func)
        assert(isName(name), "EventEmitter:on() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter:on() expects a listener function as its 2nd argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        if listenersOf ~= nil then
            listenersOf[func] = nil
        end

        return self
    end

    function klass:emit(name, ...)
        assert(isName(name), "EventEmitter:emit() expects an event name as its 1st argument")

        if allowedEvents and not allowedEvents[name] then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        local listenersOf = self._listeners[name]
        for func, wrapped in pairs(listenersOf) do
            local ok, err = pcall(wrapped, ...)
            if not ok then
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
