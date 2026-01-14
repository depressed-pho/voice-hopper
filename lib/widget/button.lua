local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local Button = class("Button", Widget)

function Button:__init(label)
    assert(type(label) == "string", "Button:new() expects a string label as its 1st argument")
    super(Set:new {"ui:Clicked", "ui:Toggled", "ui:Pressed", "ui:Released"})
    self._label = label
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
    props.Text = self._label
    return ui.manager:Button(props)
end

return Button
