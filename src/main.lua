local EventLoop    = require("event-loop")
local HopperWindow = require("window/hopper")
--local VoiceNotify = require("voice-notify")
local class        = require("class")

local Main = class("Main", EventLoop)

function Main:__init()
    self._hopper = require("entity/hopper")
    self._win    = HopperWindow:new(self._hopper)

    self._win:onAsync("watchDirChosen", function(_absPath)
        self._win.isWatching = true
        -- FIXME: actually start watching it
    end)

    self._win:onAsync("startRequested", function()
        assert(self._hopper.fields.watchDir)
        self._win.isWatching = true
        -- FIXME
    end)

    self._win:onAsync("stopRequested", function()
        self._win.isWatching = false
        -- FIXME
    end)
end

function Main:run()
    self._win:show()
    super:run()
end

Main:new():run()
