-- ----------------------------------------------------------------------------
-- OOP utility: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local function isa(obj, klass)
    local meta = getmetatable(obj)
    return meta == klass -- FIXME: consider inheritance
end

local function class(base)
    -- The class object we are creating.
    local klass = {}
    local klassMeta = {}

    if type(base) == 'table' then
        function klassMeta.__index(obj, key)
            if key == "super" then
                local super = {}
                local superMeta = {}

                -- self.super is a special case. Its value is a table
                -- containing all the methods of the super class so that
                -- regular methods can do this:
                --
                --   function Foo:method()
                --       return self.super.method() + 1
                --       -- NOTE: This isn't a typo of self.super:method()!
                --   end
                --
                function superMeta.__index(_super, key)
                    -- Invariant: _super == super
                    -- Requirement: key refers to a method accessible from self.
                    local method = obj[key]
                    return function(...)
                        method(obj, ...)
                    end
                end

                -- But It's also callable which invokes the constructor of
                -- the super class. In fact any classes that inherit
                -- something MUST call self.super() before touching self by
                -- any other means:
                --
                --   function Foo:__init()
                --       self.super("foo")
                --       self.field = "bar"
                --   end
                function superMeta.__call(_super, ...)
                    if base.__init then
                        base.__init(obj, ...)
                    end
                end

                -- Now the "super" object is complete. Cache it in the
                -- instance so that we won't have to create it repeatedly.
                setmetatable(super, superMeta)
                obj.super = super

                return super
            end
        end

        -- Redirect method calls to the base class if they don't exist in
        -- this class.
        klassMeta.__index = base

        setmetatable(klass, klassMeta)
    end

    -- The class will be the metatable for all its instances. Redirect any
    -- missing method calls to the class itself.
    klass.__index = klass

    -- The instance is callable iff CLASS.__call(...) exists, but we can't
    -- check for its existence yet.
    function klass:__call(...)
        local call = rawget(self, "__call")
        if call then
            return call(self, ...)
        else
            error("Object not callable: " .. tostring(self))
        end
    end

    -- Expose a constructor which can be called by CLASS:new(...)
    function klass:new(...)
        -- Invariant: self == klass

        local obj = {}
        setmetatable(obj, self)

        if self.__init then
            self.__init(obj, ...)
        end

        return obj
    end

    -- Expose an instance predicate which can be called by OBJ:isa(CLASS)
    function klass:isa(cls)
        return isa(self, cls)
    end

    return klass
end

-- ----------------------------------------------------------------------------
-- Lazy evaluation: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
--
-- Usage:
--   local val = delay(function ()
--       return 666
--   end)
--   force(val) -- Returns 666
--
local Delayed = class()

function Delayed:__init(thunk)
    assert(type(thunk) == "function", "delay() expects its argument to be a thunk")
    self._thunk  = thunk
    self._forced = false
    self._value  = nil
end

function Delayed:__call()
    if not self._forced then
        self._value  = self._thunk()
        self._forced = true
    end
    return self._value
end

local function delay(thunk)
    return Delayed:new(thunk)
end

local function force(delayed)
    assert(isa(delayed, Delayed), "force() expects its argument to be a delayed computation")
    return delayed()
end

--
-- Usage:
--   local t = lazy {
--       foo = function ()
--           return 666
--       end,
--       bar = function (self)
--           return self.foo + 1
--       end,
--   }
--   t.bar -- Evaluates to 667
--
local function lazy(thunks)
    local meta = {}
    meta._forced = {} -- {key = true}

    function meta.__index(obj, key)
        if meta._forced[key] then
            -- Forced but __index() was called, which means the value was
            -- nil.
            return nil
        end

        local thunk = thunks[key]
        assert(thunk, "Field \"" .. key .. "\" not defined")
        assert(type(thunk) == "function", "Field \"" .. key .. "\" is expected to be a thunk: " .. tostring(thunk))

        local value = thunk(obj)
        obj[key] = value
        meta._forced[key] = true

        return value
    end

    local obj = {}
    setmetatable(obj, meta)
    return obj
end

-- ----------------------------------------------------------------------------
-- UI Globals: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local ui = lazy {
    manager = function ()
        assert(fusion, "Global \"fusion\" not defined")
        return fusion.UIManager
    end,
    dispatcher = function (self)
        assert(bmd, "Global \"bmd\" not defined")
        return bmd.UIDispatcher(self.manager)
    end,
}

-- ----------------------------------------------------------------------------
-- Window class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Window = class()

function Window:__init(id)
    assert(type(id) == "string", "Window:new() expects its 3rd argument to be a string ID")

    self._id       = id
    self._title    = nil
    self._geometry = nil
    self._type     = "regular"
    self._children = {}
    self._window   = nil
end

function Window:setTitle(title)
    assert(type(title) == "string", "Window#setTitle() expects a string title")
    self._title = title
    return self
end

function Window:setGeometry(x, y, width, height)
    assert(type(x     ) == "number", "Window#setGeometry() expects 4 numbers")
    assert(type(y     ) == "number", "Window#setGeometry() expects 4 numbers")
    assert(type(width ) == "number", "Window#setGeometry() expects 4 numbers")
    assert(type(height) == "number", "Window#setGeometry() expects 4 numbers")
    self._geometry = {x, y, width, height}
    return self
end

function Window:setType(typ)
    assert(typ == "regular" or typ == "floating")
    self._type = typ
    return self
end

function Window:addChild(widget)
    assert(isa(widget, Widget), "Window#addChild() expects a Widget")
    table.insert(self._children, widget)
    return self
end

function Window:_getWin()
    if not self._window then
        if #self._children == 0 then
            -- Attempting to create an empty window causes DaVinci Resolve
            -- to crash.
            error("The window has no children. Add something before showing it", 2)
        end

        local props = {
            ID = self._id
        }
        if self._title ~= nil then
            props.WindowTitle = self._title
        end
        if self._geometry then
            props.Geometry = self._geometry
        end

        if self._type == "regular" then
            props.WindowFlags = {
                Window = true,
                WindowStaysOnTopHint = false,
            }
        elseif self._type == "floating" then
            props.WindowFlags = {
                Window = false,
                WindowStaysOnTopHint = true
            }
        else
            error("Unknown window type: " .. self._type)
        end

        self._window = ui.dispatcher:AddWindow(props, self._children)
        if not self._geometry then
            self._window:RecalcLayout()
        end
    end
    return self._window
end

function Window:show()
    self:_getWin():Show()
    return self
end

function Window:hide()
    if self._window then
        self._window:Hide()
    end
    return self
end

-- ----------------------------------------------------------------------------
-- Voice Hopper
-- ----------------------------------------------------------------------------

local HopperWindow = class()

function HopperWindow:__init()
    self._win = ui.dispatcher:AddWindow {
        ID = "VoiceHopper",
        --TargetID = "VoiceHopper", -- unnecessary
        --WindowTitle = "Voice Hopper", -- empty if omitted
        -- Geometry = {0, 0, 500, 500},
        --[[WindowFlags = {
            Window = true,
            WindowStaysOnTopHint = true,
        },]]
        ui.manager:VGroup {
            ID = "root",
            ui.manager:Label {
                ID = "TestLabel",
                Text = "Hello, World!",
            },
        },
    }
end

function Main()
    local win = HopperWindow:new()

    win._win:Show()
    win._win.On.VoiceHopper.Close = function (ev)
        ui.dispatcher:ExitLoop()
    end
    ui.dispatcher:RunLoop()
end

Main()
