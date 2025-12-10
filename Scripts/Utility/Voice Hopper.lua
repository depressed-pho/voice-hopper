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
local Widget = class()

function Widget:__init()
    -- Generate a random ID
    local digits = {"id"}
    for i = 2, 21 do
        digits[i] = math.random(0, 9)
    end
    self._id  = table.concat(digits)
    self._raw = nil
end

function Widget:id()
    return self._id
end

function Widget:raw()
    if not self._raw then
        self._raw = self:materialise()
    end
    return self._raw
end

function Widget:materialise()
    error("Widgets are expected to override the method materialise()", 2)
end

-- ----------------------------------------------------------------------------
-- Label widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Label = class(Widget)

function Label:__init(text)
    assert(type(text) == "nil" or type(text) == "string", "Label:new() expects an optional string text as its 1st argument")
    super()
    self._text = text
end

function Label:materialise()
    local props = {
        ID   = self:id(),
        Text = self._text
    }
    return ui.manager:Label(props)
end

-- ----------------------------------------------------------------------------
-- Container widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Container = class(Widget)

function Container:__init(children)
    assert(
        type(children) == "nil" or type(children) == "table",
        "Layout:new() expects an optional list of child widgets")
    super()

    if children then
        self._children = children
    else
        self._children = {}
    end
end

function Container:children()
    return self._children
end

-- ----------------------------------------------------------------------------
-- VGroup widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local VGroup = class(Container)

function VGroup:materialise()
    local props = {
        ID = self:id()
    }

    local raws = {}
    for i, child in ipairs(self:children()) do
        raws[i] = child:raw()
    end

    return ui.manager:VGroup(props, raws)
end

-- ----------------------------------------------------------------------------
-- Window class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Window = class()

function Window:__init(id)
    assert(type(id) == "string", "Window:new() expects its argument to be a string ID")

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
    assert(Widget:made(widget), "Window#addChild() expects a Widget")
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

        --[[
        ui.manager:VGroup {
            ID = "root",
            ui.manager:Label {
                ID = "TestLabel",
                Text = "Hello, World!",
            },
        },
        ]]
        VGroup:new({
                Label:new("Test label")
        }):raw()
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
