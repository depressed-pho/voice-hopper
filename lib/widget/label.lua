local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

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
        Events     = self.enabledEvents,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._text,
        Indent     = self._indent,
    }
    return ui.manager:Label(props)
end

return Label
