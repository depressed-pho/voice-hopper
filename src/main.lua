local EventLoop    = require("event-loop")
local HopperWindow = require("window/hopper")
local VoiceNotify = require("voice-notify")
local class        = require("class")

local Main = class("Main", EventLoop)

function Main:__init()
    self._hopper  = require("entity/hopper")
    self._win     = HopperWindow:new(self._hopper)
    self._watcher = nil -- VoiceNotify

    self._win:onAsync("watchDirChosen", function(dirPath)
        self:startWatching(dirPath)
    end)

    self._win:onAsync("startRequested", function(dirPath)
        self:startWatching(dirPath)
    end)

    self._win:onAsync("stopRequested", function()
        self:stopWatching()
    end)
end

function Main:startWatching(dirPath)
    assert(type(dirPath) == "string")

    self:stopWatching()

    self._win.isWatching = true
    self._watcher = VoiceNotify:new(dirPath)
    self._watcher:on("create", function(ev)
        require("console").log("voice appeared: %O", ev)
    end)
    self._watcher:start()
end

function Main:stopWatching()
    if self._watcher then
        self._watcher:cancel():join()
        self._watcher = nil
    end
    self._win.isWatching = false
end

function Main:run()
    self._win:show()
    super:run()
end

Main:new():start()
