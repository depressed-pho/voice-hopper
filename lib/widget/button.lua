local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local Button = class("Button", Widget)

function Button:__init(label)
    assert(type(label) == "string", "Button:new() expects a string label as its 1st argument")
    super()
    self._label = label
end

function Button:materialise()
    local props = {
        ID         = self.id,
        Events     = self.enabledEvents,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._label,
    }
    return ui.manager:Button(props)
end

return Button
