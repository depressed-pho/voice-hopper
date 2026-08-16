local CharConfWindow     = require("window/characters")
local EventLoop          = require("event/loop")
local HopperWindow       = require("window/hopper")
local ImportVoicesWindow = require("window/import")
local VoiceNotify        = require("voice-notify")
local class              = require("class")

local Main = class("Main", EventLoop)

function Main:__init()
    self._hopper    = require("entity/hopper")
    self._chars     = require("entity/characters")
    self._winMain   = HopperWindow:new(self._hopper, self._isWatching)
    self._winChars  = CharConfWindow:new(self._chars)
    self._winImport = ImportVoicesWindow:new(self._winMain.watchDir)
    self._watcher   = nil -- VoiceNotify

    -- HopperWindow events
    self._winMain.startRequested:onValue(function (watchDir)
        self:startWatching(watchDir)
    end)
    self._winMain.stopRequested:onValue(function ()
        self:stopWatching()
    end)
    self._winMain.confCharacters:onValue(function ()
        self._winChars:show()
    end)
    self._winMain.importVoiceClips:onValue(function ()
        self._winImport:show()
    end)
end

function Main:startWatching(watchDir)
    assert(type(watchDir) == "string")

    self:stopWatching()

    self._winMain.isWatchingBus:push(true)
    self._watcher = VoiceNotify:new(watchDir)
    self._watcher.onUnhandledError = function(err)
        self._winMain.logger:warn(err)
        self._watcher = nil
        self._winMain.isWatchingBus:push(false)
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
    self._winMain.isWatchingBus:push(false)
end

function Main:run()
    self._winMain:show()
    super:run()
end

Main:new():start()
