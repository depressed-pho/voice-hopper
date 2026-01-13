local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local SpinBox = class("SpinBox", Widget)

function SpinBox:__init(val, min, max, step)
    assert(val  == nil or type(val ) == "number", "SpinBox:new() expects the current numeric value as 1st argument")
    assert(min  == nil or type(min ) == "number", "SpinBox:new() expects the minimum numeric value as 2nd argument")
    assert(max  == nil or type(max ) == "number", "SpinBox:new() expects the maximum numeric value as 3rd argument")
    assert(step == nil or type(step) == "number", "SpinBox:new() expects the numeric step as 4th argument")
    assert(min == nil or max == nil or min <= max,
           "The minimum must be no greater than the maximum: " .. tostring(min) .. ", " .. tostring(max))
    assert(step == nil or step > 0, "The step must be greater than zero: " .. tostring(step))
    super(Set:new {"ui:ValueChanged", "ui:EditingFinished"})
    self._val      = val
    self._min      = min
    self._max      = max
    self._step     = step
    self._readOnly = false
end

function SpinBox.__getter:readOnly()
    return self._readOnly
end
function SpinBox.__setter:readOnly(bool)
    assert(type(bool) == "boolean", "SpinBox.readOnly expects a boolean")
    if self.materialised then
        self.raw.ReadOnly = bool
    else
        self._readOnly = bool
    end
end

function SpinBox.__getter:value()
    if self.materialised then
        return self.raw.Value
    else
        return self._val
    end
end
function SpinBox.__setter:value(val)
    assert(type(val) == "number", "SpinBox.value expects a number")
    if self.materialised then
        self.raw.Value = val
    else
        self._val = val
    end
end

function SpinBox:materialise()
    local props = {
        ID         = self.id,
        Events     = self.enabledEvents,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        -- SpinBox behaves strangely when its limits are inf or -inf (which
        -- comes from math.huge). We use some reasonably small or large
        -- values instead. The default limits are absurd: 0 for the min and
        -- 99 for the max.
        Value      = self._val  or       0,
        Minimum    = self._min  or -999999,
        Maximum    = self._max  or  999999,
        SingleStep = self._step or       1,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:SpinBox(props)
end

return SpinBox
