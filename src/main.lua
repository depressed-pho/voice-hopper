local HopperWindow = require("window/hopper")
--local VoiceNotify = require("voice-notify")
local hopper       = require("entity/hopper")
local ui           = require("ui")

local function Main()
    local win = HopperWindow:new(hopper)

    win:onAsync("watchDirChosen", function(_absPath)
        win.isWatching = true
        -- FIXME: actually start watching it
    end)

    win:onAsync("startRequested", function()
        win.isWatching = true
        -- FIXME
    end)

    win:onAsync("stopRequested", function()
        win.isWatching = false
        -- FIXME
    end)

    win:show()
    ui.dispatcher:RunLoop()
end
Main()
