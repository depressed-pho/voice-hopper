local Container = require("widget/container")
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

return VGroup
