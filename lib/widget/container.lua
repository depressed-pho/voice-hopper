local Widget = require("widget")
local class  = require("class")

local Container = class("Container", Widget)

function Container:__init(possibleEvents, children)
    assert(
        children == nil or type(children) == "table",
        "Layout:new() expects an optional list of child widgets")
    super(possibleEvents)
    self._children = children or {}
end

function Container.__getter:children()
    return self._children
end

function Container:addChild(widget)
    assert(Widget:made(widget), "Container:addChild() expects a Widget")
    table.insert(self._children, widget)
    return self
end

-- protected
function Container:installEventHandlers(rawWin)
    -- Invoke the super method to install handlers for the container
    -- itself.
    super:installEventHandlers(rawWin)

    -- Then do it for each child.
    for _i, child in ipairs(self._children) do
        child:installEventHandlers(rawWin)
    end
end

return Container
