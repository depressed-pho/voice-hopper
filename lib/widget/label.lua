local Alignment = require("widget/alignment")
local Widget    = require("widget")
local class     = require("class")
local ui        = require("ui")

local Label = class("Label", Widget)

function Label:__init(text)
    assert(type(text) == "string", "Label:new() expects an string label as its 1st argument")

    super()
    self._align  = Alignment:new {
        horizontal = "left",
        vertical   = "center"
    }
    self._text   = text
    self._indent = nil

    self._align:on("update", function()
        if self.materialised then
            self._raw.Alignment = self._align:asTable()
        end
    end)
end

function Label.__getter:alignment()
    return self._align
end

function Label.__getter:text()
    return self._text
end
function Label.__setter:text(text)
    assert(type(text) == "string", "Label#text expects a string")
    self._text = text
    if self.materialised then
        self.raw.Text = text
    end
end

function Label.__getter:indent()
    return self._indent
end
function Label.__setter:indent(indent)
    assert(indent == nil or type(indent) == "number", "Label#indent expects an optional number")
    self._indent = indent
end

function Label:materialise()
    local props = self:commonProps()
    props.Alignment = self._align:asTable()
    props.Text      = self._text
    props.Indent    = self._indent
    return ui.manager:Label(props)
end

return Label
