local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local SpinBox = class("SpinBox", Widget)

function SpinBox:__init(val, min, max, step)
    assert(val  == nil or type(val ) == "number", "SpinBox:new() expects the current numeric value as 1st argument")
    assert(min  == nil or type(min ) == "number", "SpinBox:new() expects the minimum numeric value as 2nd argument")
    assert(max  == nil or type(max ) == "number", "SpinBox:new() expects the maximum numeric value as 3rd argument")
    assert(step == nil or type(step) == "number", "SpinBox:new() expects the numeric step as 4th argument")
    assert(min == nil or max == nil or min <= max, "The minimum must be no greater than the maximum: " .. tostring(min) .. ", " .. tostring(max))
    assert(step == nil or step > 0, "The step must be greater than zero: " .. tostring(step))
    super()
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
    self._readOnly = bool
end

function SpinBox:materialise()
    local props = {
        ID         = self.id,
        Weight     = self.weight,
        ToolTip    = self.toolTip,
        StyleSheet = tostring(self.style),
        Value      = self._val,
        Minimum    = self._min,
        Maximum    = self._max,
        SingleStep = self._step,
        ReadOnly   = self._readOnly,
    }
    return ui.manager:SpinBox(props)
end

return SpinBox
