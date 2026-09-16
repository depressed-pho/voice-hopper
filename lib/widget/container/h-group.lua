local Container = require("widget/container")
local VGap      = require("widget/v-gap")
local class     = require("class")
local ui        = require("ui")

local HGroup = class("HGroup", Container)

function HGroup:materialise()
    local props = self:commonProps()
    props.CurrentIndex = 0

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:HGroup(props, raws)
end

function HGroup:addChild(widget)
    if VGap:made(widget) then
        error("It's an error to add a VGap to an HGroup", 2)
    else
        return super:addChild(widget)
    end
end

return HGroup
