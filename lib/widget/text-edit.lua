local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

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

function TextEdit.__getter:text()
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
        Events     = self.enabledEvents,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Text       = self._initialText,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:TextEdit(props)
end

return TextEdit
