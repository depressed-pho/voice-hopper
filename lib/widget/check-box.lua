local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

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
        Events     = self.enabledEvents,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._label,
        Checked    = self._initialState,
    }
    return ui.manager:CheckBox(props)
end

return CheckBox
