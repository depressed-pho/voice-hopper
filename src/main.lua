local HopperWindow = require("window/hopper")
local ui           = require("ui")

local function Main()
    local win = HopperWindow:new()

    win:show()
    ui.dispatcher:RunLoop()
end
Main()
