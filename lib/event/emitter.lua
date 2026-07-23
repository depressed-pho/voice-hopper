local Array                = require("collection/array")
local AbstractImmutableSet = require("collection/set/immutable/base")
local Event                = require("event/base")
local KeySet               = require("collection/set/key-set")
local Map                  = require("collection/map")
local Promise              = require("promise")
local ReflectiveSet        = require("collection/set/reflective")
local Set                  = require("collection/set")
local Symbol               = require("symbol")
local class                = require("class")
local console              = require("console")

local function isName(name)
    return type(name) == "string" or Symbol:made(name)
end

--
-- A special event emitted when a listener appears or disappears.
--
local ListenerEvent = class("ListenerEvent", Event)
function ListenerEvent:__init(name, func, opts)
    super()
    self.name = name  -- The name of the event.
    self.func = func  -- The listener.
    self.opts = opts  -- The options.
end

--
-- Private
--
local Listener = class("Listener")
function Listener:__init(func, opts)
    self.func      = func
    self.isDefault = not not opts.default
    self.isOneShot = not not opts.oneShot
end
function Listener.__getter:opts()
    return {
        default = self.isDefault or nil,
        oneShot = self.isOneShot or nil,
    }
end
function Listener:__call(ev)
    return Promise:try(self.func, ev)
end

--
-- An event emitter is a mixin that allows callback functions to listen to
-- events. "base" is an optional base class that can be nil.
--
-- An event name is either a string or a symbol.
--
-- There are two special events: "newListener" and "removeListener". These
-- events are emitted before a listener subscribes to, or after a listener
-- unsubscribes from an event. They are called with a ListenerEvent object.
--
local symListenersOf   = Symbol("EventEmitter::listenersOf")
local symDefaultOf     = Symbol("EventEmitter::defaultOf")
local symAllowedEvents = Symbol("EventEmitter::allowedEvents")
local function EventEmitter(base)
    local klass = class("EventEmitter", base)

    --
    -- Public class ListenerEvent
    --
    klass.ListenerEvent = ListenerEvent

    --
    -- allowedEvents is an optional Set of event names. When it's present
    -- the event emitter becomes restricted, which disallows listeners to
    -- listen on events that aren't part of it.
    --
    function klass:__init(allowedEvents, ...)
        if base then
            super(...)
        end
        -- Invariant: there exists at most one Listener in the array such
        -- that Listener#isDefault is set to true.
        rawset(self, symListenersOf  , Map:new()) -- {name => non-empty Array of Listener}
        rawset(self, symDefaultOf    , Map:new()) -- {name => Listener}
        rawset(self, symAllowedEvents, nil      ) -- Set of names, or nil if everything is allowed.

        if allowedEvents ~= nil then
            assert(
                AbstractImmutableSet:made(allowedEvents),
                "EventEmitter:new() expects an optional set of event names in its 1st argument")
            for name in allowedEvents:values() do
                assert(isName(name), "EventEmitter:new() expects an optional set of event names in its 1st argument")
            end

            -- Clone it so that the caller can't modify it afterwards.
            rawset(self, symAllowedEvents, Set:new(allowedEvents:values()))

            -- There is nothing special about "newListener" and
            -- "removeListener". If the caller doesn't explicitly allow
            -- them, they can't be subscribed to.
        end
    end

    --
    -- The set of allowed events if it's restricted, or nil otherwise.
    --
    function klass.__getter:allowedEvents()
        if self[symAllowedEvents] then
            -- Create an immutable reflective set so that the caller can't
            -- mutate it.
            return ReflectiveSet:new(self[symAllowedEvents])
        else
            return nil
        end
    end

    --
    -- The set of event names for which the emitter has registered
    -- listeners.
    --
    function klass.__getter:listenedEvents()
        return KeySet:new(self[symListenersOf])
    end

    -- This function is asynchronous. Use with caution.
    function klass:_emit(name, ev)
        local listeners = self[symListenersOf]:get(name)
        if listeners then
            local i = 1
            while i <= listeners.length do
                local l = listeners[i]
                if l.isDefault then
                    i = i + 1
                else
                    l(ev):catch(
                        function (err)
                            -- It wouldn't be the right thing to abort the
                            -- entire event handling just because a single
                            -- listener raised an error.
                            console:error(err)
                        end)
                        :await()

                    if l.isOneShot then
                        listeners:splice(i, 1)
                        self:_emit("removeListener", ListenerEvent:new(name, l.func, l.opts))
                        if listeners.length == 0 then
                            self[symListenersOf]:delete(name)
                        end
                    else
                        i = i + 1
                    end

                    if ev.isCanceled then
                        return
                    end
                end
            end

            local def = self[symDefaultOf]:get(name)
            if def then
                def(ev):catch(
                    function (err)
                        console:error(err)
                    end)

                if def.isOneShot then
                    for j, l in listeners:entries() do
                        if l == def then
                            listeners:splice(j, 1)
                            self[symDefaultOf]:delete(name)
                            self:_emit("removeListener", ListenerEvent:new(name, l.func, l.opts))
                            if listeners.length == 0 then
                                self[symListenersOf]:delete(name)
                            end
                            break
                        end
                    end
                end

                -- Canceling the event from the default handler does
                -- nothing.
            end
        end
    end

    --
    -- Return true iff the event with the given name is allowed.
    --
    function klass:isAllowed(name)
        return not self[symAllowedEvents] or self[symAllowedEvents]:has(name)
    end

    --
    -- Subscribe to an event with a given function. "opts" is an optional
    -- table with the following keys, with all keys being optional:
    --
    --   default: boolean
    --     If this is true, this handler is registered as the default
    --     handler for this event. At most one handler can be registered as
    --     the default one.
    --
    --   oneShot: boolean
    --     If this is true, this handler will be automatically removed on
    --     the first event it receives.
    --
    -- The handler function can either be synchronous or asynchronous. When
    -- it awaits a promise, no other handlers will be invoked until the
    -- promise is settled. Return value of the function will be ignored.
    --
    -- This method returns a function that, when called, unregisters the
    -- handler.
    --
    function klass:on(name, func, opts)
        assert(isName(name), "EventEmitter#on() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#on() expects a listener function as its 2nd argument")
        assert(opts == nil or (type(opts) == "table" and getmetatable(opts) == nil),
               "EventEmitter#on() expects an optional table as its 3rd argument")

        opts = opts or {}

        if not self:isAllowed(name) then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        if self:isAllowed("newListener") then
            self:emit("newListener", ListenerEvent:new(name, func, opts))
        end

        local listeners = self[symListenersOf]:get(name)
        if not listeners then
            listeners = Array:of()
            self[symListenersOf]:set(name, listeners)

        elseif opts.default and self[symDefaultOf]:has(name) then
            error("There already exists a default handler for event " .. name, 2)
        end

        local l   = Listener:new(func, opts)
        local idx = listeners.length + 1
        listeners:push(l)

        if l.isDefault then
            self[symDefaultOf]:set(name, l)
        end

        return function()
            if listeners[idx] == l then
                listeners:splice(idx, 1)
                if listeners.length == 0 then
                    self[symListenersOf]:delete(name)
                end
                if l.isDefault then
                    self[symDefaultOf]:delete(name)
                end
                if self:isAllowed("removeListener") then
                    self:emit("removeListener", ListenerEvent:new(name, func, opts))
                end
            end
        end
    end

    --
    -- Unsubscribe a listener from an event. Use of this method is
    -- discouraged because it's less efficient than calling a function
    -- returned by :on().
    --
    function klass:off(name, func)
        assert(isName(name), "EventEmitter#off() expects an event name as its 1st argument")
        assert(type(func) == "function", "EventEmitter#off() expects a listener function as its 2nd argument")

        if not self:isAllowed(name) then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        local listeners = self[symListenersOf]:get(name)
        if listeners then
            local i = 1
            while i <= listeners.length do
                local l = listeners[i]
                if l.func == func then
                    listeners:splice(i, 1)
                    if l.isDefault then
                        self[symDefaultOf]:delete(name)
                    end
                    if self:isAllowed("removeListener") then
                        self:emit("removeListener", ListenerEvent:new(name, l.func, l.opts))
                    end
                else
                    i = i + 1
                end
            end
            if listeners.length == 0 then
                self[symListenersOf]:delete(name)
            end
        end

        return self
    end

    --
    -- Emit an event and returns a promise that will be resolved when the
    -- event handling finishes. The promise will never be rejected.
    --
    function klass:emit(name, ev)
        assert(isName(name), "EventEmitter#emit() expects an event name as its 1st argument")
        assert(Event:made(ev), "EventEmitter#emit() expects an instance of Event as its 2nd argument")

        if not self:isAllowed(name) then
            error("Event " .. tostring(name) .. " is not available on this EventEmitter", 2)
        end

        return Promise:try(self._emit, self, name, ev)
    end

    --
    -- Count the number of listeners for the given event name. "func" is
    -- optional, and if it's provided it returns how many times that
    -- specific listener is found in the subscription list.
    --
    function klass:countListeners(name, func)
        assert(isName(name), "EventEmitter#countListeners() expects an event name as its 1st argument")
        assert(func == nil or type(func) == "function",
               "EventEmitter#countListeners() expects an optional function as its 2nd argument")

        local listeners = self[symListenersOf]:get(name)
        if listeners ~= nil then
            if func == nil then
                return listeners.length
            else
                local n = 0
                for l in listeners:values() do
                    if l.func == func then
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
