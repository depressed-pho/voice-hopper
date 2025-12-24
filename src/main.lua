local HopperWindow = require("window/hopper")
local ui           = require("ui")

-- FIXME: delete this
local spawn = require("thread/spawn")
local delay = require("delay")
local FSNotify = require("fsnotify")
spawn(function()
        local fsn = FSNotify:new("/Users/pho/bin")
        fsn:start()

        delay(3500):await()
        print("cancelling fsn")
        fsn:cancel()
        print("joining fsn")
        fsn:join():await()
        print("done")
end)

function Main()
    local win = HopperWindow:new()

    win:show()
    ui.dispatcher:RunLoop()
end
Main()
