local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local VGap = class("VGap", Widget)

function VGap:__init(height)
    assert(type(height) == "number", "VGap:new() expects the number of pixels")
    super()
    self._height = height
end

function VGap:materialise()
    return ui.manager:VGap(self._height)
end

return VGap
