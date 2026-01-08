require("shim/table")
local Set    = require("collection/set")
local Symbol = require("symbol")
local class  = require("class")

local function isName(name)
    return type(name) == "string" or Symbol:made(name)
end

--
-- An event emitter is a mixin that allows callback functions to listen to
-- events. "base" is an optional base class that can be nil.
--
-- An event name is either a string or a symbol.
--
-- There are two special events: "newListener" and "removeListener". These
-- events are emitted before a listener subscribes to, or after a listener
-- unsubscribes from an event. They are called with the name of the event
-- and the listener function.
--
local function EventEmitter(base)
    local klass = class("EventEmitter", base)

    --
    -- allowedEvents is an optional list of event names. When it's present
    -- the event emitter becomes restricted, which disallows listeners to
    -- listen on events that aren't part of it.
    --
    function klass:__init(allowedEvents, ...)
        if base then
            super(...)
        end
        self._listenersOf   = {}  -- {[name] = non-empty sequence of {origFun, wrappedFun}}
        self._allowedEvents = nil -- Set of names, or nil if everything is allowed.

        if allowedEvents ~= nil then
            assert(
                Set:made(allowedEvents),
                "EventEmitter:new() expects an optional set of event names in its 1st argument")
            for name in allowedEvents:values() do
                assert(isName(name), "EventEmitter:new() expects an optional set of event names in its 1st argument")
            end

            -- Clone it so that the caller can't modify it afterwards.
            self._allowedEvents = Set:new(allowedEvents:values())

            -- There is nothing special about "newListener" and
            -- "removeListener". If the caller doesn't explicitly allow
            -- them, they can't be subscribed to.
        end
    end

    --
    -- The set of allowed events if it's restricted, or nil otherwise.
    --
    function klass.__getter:allowedEvents()
        if self._allowedEvents then
            -- Clone it so that the caller can't modify the original set
            -- afterwards.
            return Set:new(self._allowedEvents:values())
            -- THINKME: But shouldn't it be a read-only live set?
        else
            return nil
        end
    end

    --
    -- The set of event names for which the emitter has registered
    -- listeners.
    --
    function klass.__getter:listenedEvents()
        local ret = Set:new()
        for name, _listeners in pairs(self._listenersOf) do
            ret:add(name)
        end
        return ret
        -- THINKME: But shouldn't it be a read-only live set?
    end

    function klass:_emit(name, ...)
        local listeners = self._listenersOf[name]
        if listeners then
            for _i, ent in ipairs(listeners) do
                local wrapped = ent[2]
                local ok, err = pcall(wrapped, ...)
                if not ok then
                    -- It wouldn't be the right thing to abort the entire
                    -- event handling just because a single listener raised
                    -- an error.
                    print(err)
                end
            end
        end
        return self
    end

    function klass:_subscribe(name, orig, wrapped)
        if self._allowedEvents and not self._allowedEvents:has(name) then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        if not self._allowedEvents or self._allowedEvents:has("newListener") then
            self:_emit("newListener", name, orig)
        end

        local listeners = self._listenersOf[name]
        if listeners == nil then
            listeners = {}
            self._listenersOf[name] = listeners
        end
        table.insert(listeners, {orig, wrapped})

        return self
    end

    function klass:_unsubscribe(name, orig)
        if self._allowedEvents and not self._allowedEvents:has(name) then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        local listeners = self._listenersOf[name]
        if listeners ~= nil then
            local i = 1
            while i <= #listeners do
                if listeners[i][1] == orig then
                    table.remove(listeners, i)

                    if not self._allowedEvents or self._allowedEvents:has("removeListener") then
                        self:_emit("removeListener", name, orig)
                    end
                else
                    i = i + 1
                end
            end
            if #listeners == 0 then
                self._listenersOf[name] = nil
            end
        end

        return self
    end

    --
    -- Subscribe to an event with a given function.
    --
    function klass:on(name, func)
        assert(isName(name), "EventEmitter#on() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#on() expects a listener function as its 2nd argument")

        return self:_subscribe(name, func, func)
    end

    --
    -- Asynchronous variant of EventEmitter#on(). The function will be
    -- evaluated in an asynchronous context.
    --
    function klass:onAsync(name, func)
        assert(isName(name), "EventEmitter#onAsync() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#onAsync() expects a listener function as its 2nd argument")

        return self:_subscribe(name, func, function(...)
            -- Start the coroutine right now. We don't care if it runs till
            -- the termination or not. If it yields it's expected to be
            -- resumed by someone else, most likely a promise.
            coroutine.wrap(func)(...)
        end)
    end

    --
    -- Subscribe to an event with a given function. The function will be
    -- automatically unsubscribed on the first event it receives.
    --
    function klass:once(name, func)
        assert(isName(name), "EventEmitter#once() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#once() expects a listener function as its 2nd argument")

        return self:_subscribe(name, func, function(...)
            self:_unsubscribe(name, func)
            func(...)
        end)
    end

    --
    -- Asynchronous variant of EventEmitter#once(). The function will be
    -- evaluated in an asynchronous context.
    --
    function klass:onceAsync(name, func)
        assert(isName(name), "EventEmitter#onceAsync() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#onceAsync() expects a listener function as its 2nd argument")

        return self:_subscribe(name, func, function(...)
            self:_unsubscribe(name, func)
            coroutine.wrap(func)(...)
        end)
    end

    --
    -- Unsubscribe a listener from an event.
    --
    function klass:off(name, func)
        assert(isName(name), "EventEmitter#off() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#off() expects a listener function as its 2nd argument")

        return self:_unsubscribe(name, func)
    end

    --
    -- Emit an event. Extra arguments are redirected to listener functions.
    --
    function klass:emit(name, ...)
        assert(isName(name), "EventEmitter#emit() expects an event name as its 1st argument")

        if self._allowedEvents and not self._allowedEvents:has(name) then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        return self:_emit(name, ...)
    end

    --
    -- Count the number of listeners for a given event name. "func" is
    -- optional, and if it's provided it returns how many times that
    -- specific listener is found in the subscription list.
    --
    function klass:countListeners(name, func)
        assert(isName(name), "EventEmitter#countListeners() expects an event name as its 1st argument")
        assert(func == nil or type(func) == "function",
               "EventEmitter#countListeners() expects an optional function as its 2nd argument")

        local listeners = self._listenersOf[name]
        if listeners ~= nil then
            if func == nil then
                return #listeners
            else
                local n = 0
                for _i, ent in ipairs(listeners) do
                    if ent[1] == func then
                        n = n + 1
                    end
                end
                return n
            end
        else
            return 0
        end
    end

    return klass
end

return EventEmitter
