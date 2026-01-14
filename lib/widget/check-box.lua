local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local CheckBox = class("CheckBox", Widget)

function CheckBox:__init(initialState, label)
    assert(type(initialState) == "boolean", "CheckBox:new() expects a boolean initial state as its 1st argument")
    assert(type(label) == "string", "CheckBox:new() expects a string label as its 2nd argument")
    super(Set:new {"ui:Clicked", "ui:Toggled", "ui:Pressed", "ui:Released"})
    self._initialState = initialState
    self._label        = label
end

function CheckBox.__getter:checked()
    if self.materialised then
        return self.raw.Checked
    else
        return self._initialState
    end
end
function CheckBox.__setter:checked(bool)
    assert(type(bool) == "boolean", "CheckBox.checked expects a boolean")
    if self.materialised then
        self.raw.Checked = bool
    else
        self._initialState = bool
    end
end

function CheckBox:materialise()
    local props = self:commonProps()
    props.Text    = self._label
    props.Checked = self._initialState
    return ui.manager:CheckBox(props)
end

return CheckBox
