local CharConfWindow = require("window/characters")
local EventLoop      = require("event-loop")
local HopperWindow   = require("window/hopper")
local VoiceNotify    = require("voice-notify")
local class          = require("class")

local Main = class("Main", EventLoop)

function Main:__init()
    self._hopper   = require("entity/hopper")
    self._chars    = require("entity/characters")
    self._winMain  = HopperWindow:new(self._hopper)
    self._winChars = CharConfWindow:new(self._chars)
    self._watcher  = nil -- VoiceNotify

    self._winMain:onAsync("watchDirChosen", function(dirPath)
        self:startWatching(dirPath)
    end)
    self._winMain:onAsync("startRequested", function(dirPath)
        self:startWatching(dirPath)
    end)
    self._winMain:onAsync("stopRequested", function()
        self:stopWatching()
    end)
    self._winMain:on("confCharacters", function()
        self._winChars:show()
        self._winMain.isCharConfEnabled = false
    end)
    self._winChars:on("ui:Hide", function()
        self._winMain.isCharConfEnabled = true
    end)
end

function Main:startWatching(dirPath)
    assert(type(dirPath) == "string")

    self:stopWatching()

    self._winMain.isWatching = true
    self._watcher = VoiceNotify:new(dirPath)
    self._watcher.onUnhandledError = function(err)
        self._winMain.logger:warn(err)
        self._watcher = nil
        self._winMain.isWatching = false
    end
    self._watcher:on("create", function(ev)
        require("console"):log("voice appeared: %O", ev)
    end)
    self._watcher:start()
end

function Main:stopWatching()
    if self._watcher then
        self._watcher:cancel():join():await()
        self._watcher = nil
    end
    self._winMain.isWatching = false
end

function Main:run()
    self._winMain:show()
    super:run()
end

Main:new():start()
