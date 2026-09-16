local Container = require("widget/container")
local HGap      = require("widget/h-gap")
local class     = require("class")
local ui        = require("ui")

local VGroup = class("VGroup", Container)

function VGroup:materialise()
    local props = self:commonProps()

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:VGroup(props, raws)
end

function VGroup:addChild(widget)
    if HGap:made(widget) then
        error("It's an error to add an HGap to a VGroup", 2)
    else
        return super:addChild(widget)
    end
end

return VGroup
