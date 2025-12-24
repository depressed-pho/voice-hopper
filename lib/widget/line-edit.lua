local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

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
        Events     = self.enabledEvents,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._initialText,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:LineEdit(props)
end

return LineEdit
