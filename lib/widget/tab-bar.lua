local Array  = require("collection/array")
local Set    = require("collection/set")
local Tab    = require("widget/tab-bar/tab")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local TabBar = class("TabBar", Widget)

TabBar.Tab = Tab

function TabBar:__init(tabs)
    assert(tabs == nil or Array:made(tabs) or (type(tabs) == "table" and getmetatable(tabs) == nil),
           "TabBar:new() expects an optional array or a sequence of Tab")

    local events = Set:new {
        "ui:CurrentChanged", "ui:CloseRequested", "ui:TabMoved",
        "ui:TabBarClicked", "ui:TabBarDoubleClicked"
    }
    super(events)

    if Array:made(tabs) then
        self._tabs = tabs
    else
        self._tabs = Array:from(tabs or {})
    end
    self._autoHide            = false
    self._changeCurrentOnDrag = false
    self._currentIndex        = 1
    self._documentMode        = false
    self._drawBase            = false
    self._expanding           = false
    self._movable             = false
    self._tabsClosable        = false
    self._useScrollButtons    = false

    for i, tab in self._tabs:entries() do
        assert(Tab:made(tab),
               string.format("The tab #%d is not an instance of Tab: %s", i, tab))
    end
end

function TabBar.__getter:autoHide()
    return self._autoHide
end
function TabBar.__setter:autoHide(bool)
    assert(type(bool) == "boolean", "TabBar#autoHide is expected to be a boolean")
    self._autoHide = bool
    if self.materialised then
        self.raw.AutoHide = bool
    end
end

function TabBar.__getter:changeCurrentOnDrag()
    return self._changeCurrentOnDrag
end
function TabBar.__setter:changeCurrentOnDrag(bool)
    assert(type(bool) == "boolean", "TabBar#changeCurrentOnDrag is expected to be a boolean")
    self._changeCurrentOnDrag = bool
    if self.materialised then
        self.raw.ChangeCurrentOnDrag = bool
    end
end

function TabBar.__getter:currentIndex()
    if self.materialised then
        return self.raw.CurrentIndex + 1
    else
        return self._currentIndex
    end
end
function TabBar.__setter:currentIndex(index)
    assert(type(index) == "number" and math.floor(index) == index, "TabBar#currentIndex is expected to be an integer")

    if index < 1 or index > #self.children then
        error("Index out of bounds: " .. tostring(index), 2)
    end

    self._currentIndex = index

    if self.materialised then
        self.raw.CurrentIndex = index - 1 -- 0-origin
    end
end

function TabBar.__getter:documentMode()
    return self._documentMode
end
function TabBar.__setter:documentMode(bool)
    assert(type(bool) == "boolean", "TabBar#documentMode is expected to be a boolean")
    self._documentMode = bool
    if self.materialised then
        self.raw.DocumentMode = bool
    end
end

function TabBar.__getter:drawBase()
    return self._drawBase
end
function TabBar.__setter:drawBase(bool)
    assert(type(bool) == "boolean", "TabBar#drawBase is expected to be a boolean")
    self._drawBase = bool
    if self.materialised then
        self.raw.DrawBase = bool
    end
end

function TabBar.__getter:expanding()
    return self._expanding
end
function TabBar.__setter:expanding(bool)
    assert(type(bool) == "boolean", "TabBar#expanding is expected to be a boolean")
    self._expanding = bool
    if self.materialised then
        self.raw.Expanding = bool
    end
end

function TabBar.__getter:movable()
    return self._movable
end
function TabBar.__setter:movable(bool)
    assert(type(bool) == "boolean", "TabBar#movable is expected to be a boolean")
    self._movable = bool
    if self.materialised then
        self.raw.Movable = bool
    end
end

function TabBar.__getter:tabsClosable()
    return self._tabsClosable
end
function TabBar.__setter:tabsClosable(bool)
    assert(type(bool) == "boolean", "TabBar#tabsClosable is expected to be a boolean")
    self._tabsClosable = bool
    if self.materialised then
        self.raw.TabsClosable = bool
    end
end

function TabBar.__getter:useScrollButtons()
    return self._useScrollButtons
end
function TabBar.__setter:useScrollButtons(bool)
    assert(type(bool) == "boolean", "TabBar#useScrollButtons is expected to be a boolean")
    self._useScrollButtons = bool
    if self.materialised then
        self.raw.UseScrollButtons = bool
    end
end

function TabBar:materialise()
    local props = self:commonProps()
    props.AutoHide            = self._autoHide
    props.ChangeCurrentOnDrag = self._changeCurrentOnDrag
    props.CurrentIndex        = self._currentIndex - 1 -- 0-origin
    props.DocumentMode        = self._documentMode
    props.DrawBase            = self._drawBase
    props.Expanding           = self._expanding
    props.Movable             = self._movable
    props.TabsClosable        = self._tabsClosable
    props.UseScrollButtons    = self._useScrollButtons

    local raw = ui.manager:TabBar(props)
    for i, tab in self._tabs:entries() do
        tab:populate(raw, i - 1) -- 0-origin
    end
    return raw
end

return TabBar
