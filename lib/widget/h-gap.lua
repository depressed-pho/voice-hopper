local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

local HGap = class("HGap", Widget)

function HGap:__init(width)
    assert(type(width) == "number", "HGap:new() expects the number of pixels")
    super()
    self._width = width
end

function HGap:materialise()
    return ui.manager:HGap(self._width)
end

return HGap
