local Container = require("widget/container")
local class     = require("class")
local ui        = require("ui")

local HGroup = class("HGroup", Container)

function HGroup:materialise()
    local props = self:commonProps()

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:HGroup(props, raws)
end

return HGroup
