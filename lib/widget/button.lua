local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local Button = class("Button", Widget)

function Button:__init(label)
    assert(type(label) == "string", "Button:new() expects a string label as its 1st argument")
    super(Set:new {"ui:Clicked", "ui:Toggled", "ui:Pressed", "ui:Released"})
    self._autoExclusive = false
    self._checkable     = false
    self._checked       = false
    self._flat          = false
    self._label         = label
end

--[[ FIXME: We should provide a way to apply CSS for non-rounded style:
QPushButton {
    border: 1px solid palette(light);
}
QPushButton:hover {
    border: 1px solid palette(bright-text);
}
QPushButton:checked {
    background-color: palette(highlight);
}
]]

function Button.__getter:autoExclusive()
    return self._autoExclusive
end
function Button.__setter:autoExclusive(bool)
    assert(type(bool) == "boolean", "Button#autoExclusive expects a boolean")
    self._autoExclusive = bool
    if self.materialised then
        self.raw.AutoExclusive = bool
    end
end

function Button.__getter:checkable()
    return self._checkable
end
function Button.__setter:checkable(bool)
    assert(type(bool) == "boolean", "Button#checkable expects a boolean")
    self._checkable = bool
    if self.materialised then
        self.raw.Checkable = bool
    end
end

function Button.__getter:checked()
    if self.materialised then
        return self.raw.Checked
    else
        return self._checked
    end
end
function Button.__setter:checked(bool)
    assert(type(bool) == "boolean", "Button#checked expects a boolean")
    self._checked = bool
    if self.materialised then
        self.raw.Checked = bool
    end
end

function Button.__getter:flat()
    return self._flat
end
function Button.__setter:flat(bool)
    assert(type(bool) == "boolean", "Button#flat expects a boolean")
    self._flat = bool
    if self.materialised then
        self.raw.Flat = bool
    end
end

function Button.__getter:label()
    return self._label
end
function Button.__setter:label(label)
    assert(type(label) == "string", "Button#label expects a string")
    self._label = label
    if self.materialised then
        self.raw.Text = label
    end
end

function Button:materialise()
    local props = self:commonProps()
    props.AutoExclusive = self._autoExclusive
    props.Checkable     = self._checkable
    props.Checked       = self._checked
    props.Flat          = self._flat
    props.Text          = self._label
    return ui.manager:Button(props)
end

return Button
