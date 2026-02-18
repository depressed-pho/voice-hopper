local Label = require("widget/label")
local class = require("class")

--
-- A widget emulating QSpacerItem. Since it's not directly available in
-- Resolve API we emulate it with an empty UILabel.
--
local Spacer = class("Spacer", Label)
function Spacer:__init()
    super("")
end

return Spacer
