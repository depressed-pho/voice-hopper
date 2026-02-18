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

    if self.materialised then
        error("UIWidget#AddChild() is incredibly broken. It either puts the widget at a wrong position or" ..
              " causes memory corruption and a crash. Don't try to insert a child dynamically." ..
              " Consider using Stack instead")
    end

    return self
end

function Container:removeChild(widget)
    assert(Widget:made(widget), "Container:removeChild() expects a Widget")

    local tmp = {}
    for _i, child in ipairs(self._children) do
        if widget ~= child then
            table.insert(tmp, child)
        end
    end
    self._children = tmp

    if self.materialised then
        self.raw:RemoveChild(widget.id)
    end

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
