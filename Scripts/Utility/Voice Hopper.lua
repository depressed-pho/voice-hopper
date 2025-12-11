local Colour = require("VoiceHopper/colour")
local class  = require("VoiceHopper/class")
local lazy   = require("VoiceHopper/lazy").lazy

-- ----------------------------------------------------------------------------
-- UI Globals: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local ui = lazy {
    fusion = function ()
        assert(fusion, "Global \"fusion\" not defined")
        return fusion
    end,
    manager = function (self)
        return self.fusion.UIManager
    end,
    dispatcher = function (self)
        assert(bmd, "Global \"bmd\" not defined")
        return bmd.UIDispatcher(self.manager)
    end,
}

-- ----------------------------------------------------------------------------
-- CSSStyleProperties: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local CSSStyleProperties = {}

function camel2kebab(camel)
    local ret = {}

    local s, e = string.find(camel, "^%l*")
    table.insert(ret, string.sub(camel, s, e))

    local idx = e + 1
    while true do
        local s, e = string.find(camel, "^%u%l*", idx)
        if s == nil then
            assert(idx >= string.len(camel), "invalid camelCase: " .. camel)
            break
        else
            table.insert(ret, string.lower(string.sub(camel, s, e)))
            idx = e + 1
        end
    end

    return table.concat(ret, "-")
end

do
    local meta = {}
    function meta.__index(self, key)
        local kebab = camel2kebab(tostring(key))
        return self.__props[kebab]
    end
    function meta.__newindex(self, key, value)
        local kebab = camel2kebab(tostring(key))
        self.__props[kebab] = tostring(value)
    end
    function meta.__tostring(self)
        local ret = {}
        for key, val in pairs(self.__props) do
            table.insert(ret, string.format("%s: %s", key, val))
        end
        return table.concat(ret, "; ")
    end

    -- Objects of CSSStyleProperties behaves like a regular table but keys
    -- in camelCase are mapped to kebab-case and values are coerced into
    -- strings. tostring() will turn the object into "prop1: value1; prop2:
    -- value2; ...".
    function CSSStyleProperties:new()
        local self = {}
        self.__props = {} -- name in kebab-case => string value

        setmetatable(self, meta)
        return self
    end
end

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
    self._id       = table.concat(digits)
    self._style    = CSSStyleProperties:new()
    self._weight   = nil
    self._toolTip  = nil
    self._events   = {} -- name => function
    self._raw      = nil
end

function Widget.__getter:id()
    return self._id
end

function Widget.__getter:style()
    return self._style
end

function Widget.__getter:weight()
    return self._weight
end
function Widget.__setter:weight(weight)
    assert(weight == nil or type(weight) == "number", "Widget.weight expects an optional number")
    self._weight = weight
end

function Widget.__getter:toolTip()
    return self._toolTip
end
function Widget.__setter:toolTip(toolTip)
    assert(toolTip == nil or type(toolTip) == "string", "Widget.toolTip expects an optional string")
    self._toolTip = toolTip
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
-- Button widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Button = class("Button", Widget)

function Button:__init(label)
    assert(type(label) == "string", "Button:new() expects a string label as its 1st argument")
    super()
    self._label = label
end

function Button:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._label,
    }
    return ui.manager:Button(props)
end

-- ----------------------------------------------------------------------------
-- CheckBox widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local CheckBox = class("CheckBox", Widget)

function CheckBox:__init(initialState, label)
    assert(type(initialState) == "boolean", "CheckBox:new() expects a boolean initial state as its 1st argument")
    assert(type(label) == "string", "CheckBox:new() expects a string label as its 2nd argument")
    super()
    self._initialState = initialState
    self._label        = label
end

function CheckBox:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._label,
        Checked    = self._initialState,
    }
    return ui.manager:CheckBox(props)
end

-- ----------------------------------------------------------------------------
-- Label widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local Label = class("Label", Widget)

function Label:__init(text)
    assert(type(text) == "string", "Label:new() expects an string label as its 1st argument")
    super()
    self._text   = text
    self._indent = nil
end

function Label.__getter:indent()
    return self._indent
end
function Label.__setter:indent(indent)
    assert(indent == nil or type(indent) == "number", "Label.indent expects a number")
    self._indent = indent
end

function Label:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._text,
        Indent     = self._indent,
    }
    return ui.manager:Label(props)
end

-- ----------------------------------------------------------------------------
-- LineEdit widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local LineEdit = class("LineEdit", Widget)

function LineEdit:__init(initialText)
    assert(initialText == nil or type(initialText) == "string", "LineEdit:new() expects an optional initial text")
    super()
    self._initialText = initialText or ""
    self._readOnly    = false
end

function LineEdit.__getter:readOnly()
    return self._readOnly
end

function LineEdit.__setter:readOnly(bool)
    self._readOnly = bool
end

function LineEdit.__getter:text(text)
    if self.materialised then
        return self.raw.Text
    else
        return self._initialText
    end
end
function LineEdit.__setter:text(text)
    assert(type(text) == "string", "LineEdit.text expects a string")
    if self.materialised then
        self.raw.Text = text
    else
        self._initialText = text
    end
end

function LineEdit:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._initialText,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:LineEdit(props)
end

-- ----------------------------------------------------------------------------
-- TextEdit widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local TextEdit = class("TextEdit", Widget)

function TextEdit:__init(initialText)
    assert(initialText == nil or type(initialText) == "string", "TextEdit:new() expects an optional initial text")
    super()
    self._initialText = initialText or ""
    self._readOnly    = false
end

function TextEdit.__getter:readOnly()
    return self._readOnly
end

function TextEdit.__setter:readOnly(bool)
    self._readOnly = bool
end

function TextEdit.__getter:text(text)
    if self.materialised then
        return self.raw.Text
    else
        return self._initialText
    end
end
function TextEdit.__setter:text(text)
    assert(type(text) == "string", "TextEdit.text expects a string")
    if self.materialised then
        self.raw.Text = text
    else
        self._initialText = text
    end
end

function TextEdit:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._initialText,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:TextEdit(props)
end

-- ----------------------------------------------------------------------------
-- SpinBox widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local SpinBox = class("SpinBox", Widget)

function SpinBox:__init(val, min, max, step)
    assert(val  == nil or type(val ) == "number", "SpinBox:new() expects the current numeric value as 1st argument")
    assert(min  == nil or type(min ) == "number", "SpinBox:new() expects the minimum numeric value as 2nd argument")
    assert(max  == nil or type(max ) == "number", "SpinBox:new() expects the maximum numeric value as 3rd argument")
    assert(step == nil or type(step) == "number", "SpinBox:new() expects the numeric step as 4th argument")
    assert(min == nil or max == nil or min <= max, "The minimum must be no greater than the maximum: " .. tostring(min) .. ", " .. tostring(max))
    assert(step == nil or step > 0, "The step must be greater than zero: " .. tostring(step))
    super()
    self._val      = val
    self._min      = min
    self._max      = max
    self._step     = step
    self._readOnly = false
end

function SpinBox.__getter:readOnly()
    return self._readOnly
end

function SpinBox.__setter:readOnly(bool)
    self._readOnly = bool
end

function SpinBox:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Value      = self._val,
        Minimum    = self._min,
        Maximum    = self._max,
        SingleStep = self._step,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:SpinBox(props)
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
-- HGroup widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local HGroup = class("HGroup", Container)

function HGroup:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
    }

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:HGroup(props, raws)
end

-- ----------------------------------------------------------------------------
-- VGroup widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local VGroup = class("VGroup", Container)

function VGroup:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
    }

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:VGroup(props, raws)
end

-- ----------------------------------------------------------------------------
-- HGap widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local HGap = class("HGap", Widget)

function HGap:__init(width)
    assert(type(width) == "number", "HGap:new() expects the number of pixels")
    super()
    self._width = width
end

function HGap:materialise()
    return ui.manager:HGap(self._width)
end

-- ----------------------------------------------------------------------------
-- VGap widget class: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local VGap = class("VGap", Widget)

function VGap:__init(height)
    assert(type(height) == "number", "VGap:new() expects the number of pixels")
    super()
    self._height = height
end

function VGap:materialise()
    return ui.manager:VGap(self._height)
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
            self.close()
        else
            ui.dispatcher:ExitLoop()
        end
    end
    self:on("Close", defaultOnClose)
end

function Window.__getter:title()
    return self._title
end
function Window.__setter:title(title)
    assert(type(title) == "string", "Window:setTitle() expects a string title")
    self._title = title
end

function Window.__getter:type()
    return self._type
end
function Window.__setter:type(typ)
    assert(typ == "regular" or typ == "floating")
    self._type = typ
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
        -- Giving no window flags seems to make it behave like the console
        -- window. Why? I don't know, because there's absolutely no
        -- documentation.
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
    self.raw:Raise()
    return self
end

function Window:hide()
    if self.materialised then
        self.raw:Hide()
        Window._shown[self] = nil
    end
    return self
end

function Window:close()
    if self.materialised then
        self.raw:Close()
        Window._shown[self] = nil
    end
    return self
end

-- ----------------------------------------------------------------------------
-- Voice Hopper
-- ----------------------------------------------------------------------------

local HopperWindow = class("HopperWindow", Window)

function HopperWindow:__init()
    super()
    self.title = "Voice Hopper"
    self.type  = "floating"
    self.style.padding = "10px"

    local root = VGroup:new()
    local gap  = 10
    do
        local title = Label:new("Folder to watch:")
        title.weight = 0
        root:addChild(title)
        root:addChild(self:_mkWatchGroup())
        root:addChild(VGap:new(gap))
    end
    do
        local title = Label:new("Import settings:")
        title.weight = 0
        root:addChild(title)
        root:addChild(self:_mkSettingsGroup())
    end
    do
        local title = Label:new("Log:")
        title.weight = 0
        root:addChild(title)
        root:addChild(self:_mkLogGroup())
    end
    do
        root:addChild(self:_mkButtonsGroup())
    end
    self:addChild(root)
end

function HopperWindow:_mkWatchGroup()
    local grp = VGroup:new()
    grp.weight = 0
    do
        local row = HGroup:new()
        do
            local fldPath = LineEdit:new()
            fldPath.readOnly = true
            row:addChild(fldPath)
            self._fldPath = fldPath

            local btnChoose = Button:new("...")
            btnChoose.weight = 0
            btnChoose.style.padding = "5px"
            btnChoose:on("Clicked", function() self:_chooseDir() end)
            row:addChild(btnChoose)
        end
        grp:addChild(row)
    end
    do
        local row = HGroup:new()
        do
            local labStatus = Label:new("")
            labStatus.weight = 0
            labStatus.style.color           = Colour.rgb(1.0, 1.0, 1.0):asCSS()
            labStatus.style.backgroundColor = Colour.rgb(0  , 0.4, 0  ):asCSS()
            labStatus.style.padding         = "3px"
            labStatus.style.fontSize        = "14px"
            row:addChild(labStatus)
            self._labStatus = labStatus

            -- A dummy label to fill the gap
            row:addChild(Label:new(""))

            local btnStartStop = Button:new("")
            btnStartStop.weight = 0
            btnStartStop:on("Clicked", function() self:_startStop() end)
            row:addChild(btnStartStop)
        end
        grp:addChild(row)
    end
    return grp
end

function HopperWindow:_mkSettingsGroup()
    local indent = 10

    local grp = VGroup:new()
    grp.weight = 0
    do
        local cols = HGroup:new()
        cols.weight = 0
        do
            local col = VGroup:new()
            col.weight = 0
            do
                local label = Label:new("Gaps (in frames)")
                label.indent  = indent
                label.toolTip = "Number of frames between consecutive voice clips"
                col:addChild(label)
            end
            do
                local label = Label:new("Subtitle extension (in frames)")
                label.indent  = indent
                label.toolTip = "Number of frames to extend the subtitle at the end of a voice clip."
                col:addChild(label)
            end
            cols:addChild(col)
        end
        do
            local col = VGroup:new()
            do
                local spin = SpinBox:new(15, 0, nil, 1)
                col:addChild(spin)
            end
            do
                local spin = SpinBox:new(15, 0, nil, 1)
                col:addChild(spin)
            end
            cols:addChild(col)
        end
        grp:addChild(cols)
    end
    do
        local chk = CheckBox:new(false, "Use clipboard if voices lack .txt files")
        chk.toolTip = "Subtitles are usually created from .txt files corresponding to voices. With this option enabled, the clipboard will be used as a fallback."
        grp:addChild(chk)
    end
    do
        local row = HGroup:new()
        do
            -- A dummy label to fill the gap
            row:addChild(Label:new(""))

            local btn = Button:new("Configure Characters...")
            btn.weight = 0
            row:addChild(btn)
        end
        grp:addChild(row)
    end
    return grp
end

function HopperWindow:_mkLogGroup()
    local log = TextEdit:new()
    log.readOnly = true
    return log
end

function HopperWindow:_mkButtonsGroup()
    local row = HGroup:new()
    row.weight = 0
    do
        local btn = Button:new("Import voice clip...")
        btn.weight = 0
        row:addChild(btn)
    end
    return row
end

function HopperWindow:_chooseDir()
    local path = ui.fusion:RequestDir(
        ".",
        {
            FReqB_Saving = False,
            FReqS_Title  = "Choose folder to watch"
        })
    if path ~= nil then
        self._fldPath.text = path
    end
end

function HopperWindow:_startStop()
    error("FIXME: not impl")
end

--
function Main()
    local win = HopperWindow:new()

    win:show()
    ui.dispatcher:RunLoop()
end
Main()
