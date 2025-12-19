local CSSStyleProperties = require("css-style-properties")
local class              = require("class")

-- ----------------------------------------------------------------------------
-- Abstract widget class
-- ----------------------------------------------------------------------------
local Widget = class("Widget")

function Widget:__init()
    -- Generate a random ID
    local digits = {"id"}
    for i = 2, 21 do
        digits[i] = math.random(0, 9)
    end
    self._id       = table.concat(digits)
    self._style    = CSSStyleProperties:new()
    self._weight   = nil
    self._toolTip  = nil
    self._events   = {} -- name => function
    self._raw      = nil
end

function Widget.__getter:id()
    return self._id
end

function Widget.__getter:style()
    return self._style
end

function Widget.__getter:weight()
    return self._weight
end
function Widget.__setter:weight(weight)
    assert(weight == nil or type(weight) == "number", "Widget.weight expects an optional number")
    self._weight = weight
end

function Widget.__getter:toolTip()
    return self._toolTip
end
function Widget.__setter:toolTip(toolTip)
    assert(toolTip == nil or type(toolTip) == "string", "Widget.toolTip expects an optional string")
    self._toolTip = toolTip
end

function Widget.__getter:raw()
    if not self._raw then
        self._raw = self:materialise()
    end
    return self._raw
end

function Widget.__getter:materialised()
    return not not self._raw
end

-- protected
function Widget:materialise()
    error("Widgets are expected to override the method materialise()", 2)
end

function Widget:on(eventName, listener)
    assert(type(eventName) == "string", "Widget:on() expects an event name as its 1st argument")
    assert(type(listener) == "function", "Widget:on() expects a listener function as its 2nd argument")
    self._events[eventName] = listener
    return self
end

-- protected
function Widget:installEventHandlers(rawWin)
    for name, listener in pairs(self._events) do
        rawWin.On[self._id][name] = listener
    end
end

return Widget
