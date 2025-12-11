local class = require("VoiceHopper/class")
local lazy  = require("VoiceHopper/lazy").lazy

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
-- Abstract widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Widget = class("Widget")

function Widget:__init()
    -- Generate a random ID
    local digits = {"id"}
    for i = 2, 21 do
        digits[i] = math.random(0, 9)
    end
    self._id     = table.concat(digits)
    self._events = {} -- name => function
    self._raw    = nil
end

function Widget.__getter:id()
    return self._id
end

function Widget.__getter:raw()
    if not self._raw then
        self._raw = self:materialise()
    end
    return self._raw
end

function Widget.__getter:materialised()
    return not not self._raw
end

-- protected
function Widget:materialise()
    error("Widgets are expected to override the method materialise()", 2)
end

function Widget:on(eventName, handler)
    self._events[eventName] = handler
    return self
end

-- protected
function Widget:installEventHandlers(rawWin)
    for name, handler in pairs(self._events) do
        rawWin.On[self._id][name] = handler
    end
end

-- ----------------------------------------------------------------------------
-- Label widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Label = class("Label", Widget)

function Label:__init(text)
    assert(text == nil or type(text) == "string", "Label:new() expects an optional string text as its 1st argument")
    super()
    self._text = text
end

function Label:materialise()
    local props = {
        ID   = self.id,
        Text = self._text
    }
    return ui.manager:Label(props)
end

-- ----------------------------------------------------------------------------
-- Container widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Container = class("Container", Widget)

function Container:__init(children)
    assert(
        children == nil or type(children) == "table",
        "Layout:new() expects an optional list of child widgets")
    super()
    self._children = children or {}
end

function Container.__getter:children()
    return self._children
end

function Container:addChild(widget)
    assert(Widget:made(widget), "Container:addChild() expects a Widget")
    table.insert(self._children, widget)
    return self
end

-- protected
function Container:installEventHandlers(rawWin)
    -- Invoke the super method to install handlers for the container
    -- itself.
    super:installEventHandlers(rawWin)

    -- Then do it for each child.
    for _i, child in ipairs(self._children) do
        child:installEventHandlers(rawWin)
    end
end

-- ----------------------------------------------------------------------------
-- VGroup widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local VGroup = class("VGroup", Container)

function VGroup:materialise()
    local props = {
        ID = self.id
    }

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:VGroup(props, raws)
end

-- ----------------------------------------------------------------------------
-- Window class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Window = class("Window", Container)
Window._shown = setmetatable({}, {__mode = "k"}) -- Window => true

function Window:__init(children)
    super(children)
    self._title    = nil
    self._geometry = nil
    self._type     = "regular"

    -- Install a default Close handler as a safety measure. Without this
    -- the user won't be able to terminate the "fuscript" process
    -- gracefully.
    local function defaultOnClose()
        -- If this is the last visible window, we should tear down the
        -- entire event loop.
        local foundOther = false
        for win in pairs(Window._shown) do
            if win ~= self then
                foundOther = true
                break
            end
        end
        if foundOther then
            self.hide()
        else
            ui.dispatcher:ExitLoop()
        end
    end
    self:on("Close", defaultOnClose)
end

function Window:setTitle(title)
    assert(type(title) == "string", "Window:setTitle() expects a string title")
    self._title = title
    return self
end

function Window:setGeometry(x, y, width, height)
    assert(type(x     ) == "number", "Window:setGeometry() expects 4 numbers")
    assert(type(y     ) == "number", "Window:setGeometry() expects 4 numbers")
    assert(type(width ) == "number", "Window:setGeometry() expects 4 numbers")
    assert(type(height) == "number", "Window:setGeometry() expects 4 numbers")
    self._geometry = {x, y, width, height}
    return self
end

function Window:setType(typ)
    assert(typ == "regular" or typ == "floating")
    self._type = typ
    return self
end

function Window:materialise()
    if #self.children == 0 then
        -- Attempting to create an empty window causes DaVinci Resolve
        -- to crash.
        error("The window has no children. Add something before showing it", 2)
    end

    local props = {
        ID = self.id
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
            Window = true,
            WindowStaysOnTopHint = true,
        }
    else
        error("Unknown window type: " .. self._type)
    end

    local rawChildren = {}
    for _i, child in pairs(self.children) do
        table.insert(rawChildren, child.raw)
    end

    local raw = ui.dispatcher:AddWindow(props, rawChildren)
    if not self._geometry then
        raw:RecalcLayout()
    end

    self:installEventHandlers(raw)

    return raw
end

function Window:show()
    Window._shown[self] = true
    self.raw:Show()
    return self
end

function Window:hide()
    if self.materialised then
        self.raw:Hide()
        Window._shown[self] = nil
    end
    return self
end

-- ----------------------------------------------------------------------------
-- Voice Hopper
-- ----------------------------------------------------------------------------

local HopperWindow = class("HopperWindow", Window)

function HopperWindow:__init()
    super {
        VGroup:new {
            Label:new("Test label")
        }
    }
    self:setTitle("Voice Hopper")
    self:setType("floating")
end

function Main()
    local win = HopperWindow:new()

    win:show()
    ui.dispatcher:RunLoop()
end

Main()
