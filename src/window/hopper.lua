local Bus         = require("reactive").Bus
local Button      = require("widget/button")
local CheckBox    = require("widget/check-box")
local Colour      = require("colour")
local EventStream = require("reactive").EventStream
local HGroup      = require("widget/container/h-group")
local VGroup      = require("widget/container/v-group")
local Label       = require("widget/label")
local LineEdit    = require("widget/line-edit")
local Logger      = require("widget/logger")
local Property    = require("reactive").Property
local Spacer      = require("widget/spacer")
local SpinBox     = require("widget/spin-box")
local VGap        = require("widget/v-gap")
local Window      = require("widget/window")
local class       = require("class")
local fun         = require("function")
local throttle    = require("event/throttle")
local ui          = require("ui")

--
-- The HopperWindow class
--
local HopperWindow = class("HopperWindow", Window)

function HopperWindow:__init(hopper)
    super()

    self._hopper           = hopper    -- VoiceHopper
    self._watchDirBus      = Bus:new() -- Bus<Path>
    self._watchDir         = self._watchDirBus:toProperty(self._hopper.watchDir) -- Property<Path or nil>
    self._isWatchingBus    = Bus:new() -- Bus<boolean>
    self._isWatching       = self._isWatchingBus:toProperty(self._hopper.watching) -- Property<boolean>
    self._isImportingBus   = Bus:new() -- Bus<boolean>
    self._isImporting      = self._isImportingBus:toProperty(false) -- Property<boolean>
    self._startRequested   = Bus:new() -- Bus<void>
    self._stopRequested    = Bus:new() -- Bus<void>
    self._confCharacters   = nil       -- EventStream<void>
    self._importVoiceClips = nil       -- EventStream<void>
    self._logger           = nil       -- Logger

    -- FIXME: confirm on close when something's dirty
    -- FIXME: exit on boot when we're already running

    self:on("ui:Move", throttle.debounce(
        function()
            self._hopper.position.x = self.position.x
            self._hopper.position.y = self.position.y
            self._hopper:save()
        end, 0.5)
    )
    self:on("ui:Resize", throttle.debounce(
        function()
            self._hopper.size.w = self.size.w
            self._hopper.size.h = self.size.h
            self._hopper:save()
        end, 0.5)
    )

    self._watchDirBus:onValue(function (watchDir)
        self._hopper.watchDir = watchDir
        self._hopper:save()
    end)

    self._isWatchingBus:onValue(function (watching)
        self._hopper.watching = watching
        self._hopper:save()
    end)

    -- When the window is shown, and the watcher was previously running,
    -- start the watcher automatically.
    self:on("ui:Show", function ()
        if self._hopper.watching then
            self._startRequested:push():await()
        end
    end)

    self.title = "Voice Hopper"
    self.type  = "floating"
    self.style.padding = "10px"

    self.position.x = self._hopper.position.x or self.position.x
    self.position.y = self._hopper.position.y or self.position.y
    self.size.w     = self._hopper.size.w     or self.size.w
    self.size.h     = self._hopper.size.h     or self.size.h

    local root = VGroup:new()
    local gap  = 10
    do
        local title = Label:new(
            (ui.platform == "linux" and "Directory to watch:")
            or "Folder to watch:")
        title.weight = 0
        root:addChild(title)
        root:addChild(self:_mkWatchGroup())
        root:addChild(VGap:new(gap))
    end
    do
        local title = Label:new("Import settings:")
        title.weight = 0
        root:addChild(title)
        root:addChild(self:_mkSettingsGroup())
    end
    do
        local title = Label:new("Log:")
        title.weight = 0
        root:addChild(title)
        root:addChild(self:_mkLogGroup())
    end
    do
        root:addChild(self:_mkButtonsGroup())
    end
    self:addChild(root)
end

function HopperWindow.__getter:logger()
    return self._logger
end

--
-- HopperWindow#watchDir is a Property<Path or nil> representing the
-- directory to watch.
--
function HopperWindow.__getter:watchDir()
    return self._watchDir
end

--
-- HopperWindow#isWatchingBus is a Bus<boolean> to signal start/stop of the
-- watcher.
--
function HopperWindow.__getter:isWatchingBus()
    return self._isWatchingBus
end

--
-- HopperWindow#startRequested is an EventStream<Path> representing a start
-- request of the watcher.
--
function HopperWindow.__getter:startRequested()
    return self._watchDir:sampledBy(self._startRequested)
end

--
-- HopperWindow#stopRequested is an EventStream<void> representing a stop
-- request of the watcher.
--
function HopperWindow.__getter:stopRequested()
    return self._stopRequested:toEventStream()
end

--
-- HopperWindow#confCharacters is an EventStream<void> signaling that the
-- character configuration window should be opened and focused.
--
function HopperWindow.__getter:confCharacters()
    return self._confCharacters
end

--
-- HopperWindow#importVoiceClips is an EventStream<void> signaling that the
-- voice import window should be opened and focused.
--
function HopperWindow.__getter:importVoiceClips()
    return self._importVoiceClips
end

function HopperWindow:_mkWatchGroup()
    local grp = VGroup:new()
    grp.weight = 0
    do
        local row = HGroup:new()
        do
            local fldWatchDir = LineEdit:new()
            fldWatchDir.readOnly = true
            self._watchDir:onValue(function (watchDir)
                fldWatchDir.text = watchDir or ""
            end)
            row:addChild(fldWatchDir)
        end
        do
            local btnChoose = Button:new("...")
            btnChoose.weight = 0
            btnChoose.style.padding = "5px"
            self._watchDir
                :sampledBy(EventStream:fromEvent(btnChoose, "ui:Clicked"))
                :onValue(
                    function (watchDir)
                        self:_chooseDir(watchDir)
                    end)
            row:addChild(btnChoose)
        end
        grp:addChild(row)
    end
    do
        local row = HGroup:new()
        do
            -- The initial text of the label should be the longest one it
            -- can show, so that the widget need not be resized later.
            local labStatus = Label:new("Importing")
            labStatus.weight = 0
            labStatus.style.padding  = "3px"
            labStatus.alignment.horizontal = "center"
            Property:combineWith(
                function (isWatching, isImporting, _ev)
                    if isImporting then
                        return "importing"
                    elseif isWatching then
                        return "watching"
                    else
                        return "idle"
                    end
                end,
                self._isWatching, self._isImporting,
                -- Avoid updating the label until the window is
                -- shown. Otherwise the label will be resized prematurely.
                EventStream:fromEvent(self, "ui:Show"))
                :onValue(
                    function (status)
                        if status == "importing" then
                            labStatus.text                  = "Importing"
                            labStatus.style.color           = Colour:rgb(1.0, 1.0, 1.0):asCSS()
                            labStatus.style.backgroundColor = Colour:rgb(0.4, 0.0, 0.0):asCSS()
                        elseif status == "watching" then
                            labStatus.text                  = "Watching"
                            labStatus.style.color           = Colour:rgb(1.0, 1.0, 1.0):asCSS()
                            labStatus.style.backgroundColor = Colour:rgb(0.0, 0.4, 0.0):asCSS()
                        elseif status == "idle" then
                            labStatus.text                  = "Idle"
                            labStatus.style.color           = Colour:rgb(0.7, 0.7, 0.7):asCSS()
                            labStatus.style.backgroundColor = Colour:rgb(0.2, 0.2, 0.2):asCSS()
                        end
                    end)
            row:addChild(labStatus)

            row:addChild(Spacer:new())

            -- The initial text of the button should be the longest one it
            -- can show, so that the widget need not be resized later.
            local btnStartStop = Button:new("")
            btnStartStop.weight = 0
            btnStartStop:on("ui:Clicked", function()
                if self._hopper.watching then
                    self._stopRequested:push():await()
                else
                    self._startRequested:push():await()
                end
            end)
            self._watchDir:onValue(function (watchDir)
                btnStartStop.enabled = not not watchDir
            end)
            self._isWatching:onValue(function (isWatching)
                if isWatching then
                    btnStartStop.label = "Stop Watching"
                else
                    btnStartStop.label = "Start Watching"
                end
            end)
            row:addChild(btnStartStop)
        end
        grp:addChild(row)
    end
    return grp
end

function HopperWindow:_mkSettingsGroup()
    local indent = 10

    local grp = VGroup:new()
    grp.weight = 0
    do
        local cols = HGroup:new()
        cols.weight = 0
        do
            local col = VGroup:new()
            col.weight = 0
            do
                local label = Label:new("Gaps between clips (in frames)")
                label.indent  = indent
                col:addChild(label)
            end
            do
                local label = Label:new("Subtitle extension (in frames)")
                label.indent  = indent
                col:addChild(label)
            end
            cols:addChild(col)
        end
        do
            local col = VGroup:new()
            do
                local fldGaps = SpinBox:new(self._hopper.gaps, 0, 300, 1)
                fldGaps.toolTip = "Number of frames between consecutive voice clips"
                fldGaps.alignment.horizontal = "right"
                fldGaps:on("ui:ValueChanged", throttle.debounce(
                    function()
                        self._hopper.gaps = fldGaps.value
                        self._hopper:save()
                    end, 0.5))
                col:addChild(fldGaps)
            end
            do
                local fldSubExt = SpinBox:new(self._hopper.subExt, 0, 300, 1)
                fldSubExt.toolTip = "Number of frames to extend the subtitle at the end of a voice clip."
                fldSubExt.alignment.horizontal = "right"
                fldSubExt:on("ui:ValueChanged", throttle.debounce(
                    function()
                        self._hopper.subExt = fldSubExt.value
                        self._hopper:save()
                    end, 0.5))
                col:addChild(fldSubExt)
            end
            cols:addChild(col)
        end
        grp:addChild(cols)
    end
    do
        local chkUseClipboard =
            CheckBox:new(self._hopper.useClipboard, "Use clipboard if voices lack .txt files")
        chkUseClipboard.toolTip =
            "Subtitles are usually created from .txt files corresponding to voices.\n" ..
            "With this option enabled, the clipboard will be used as a fallback."
        chkUseClipboard:on("ui:Toggled", function()
            self._hopper.useClipboard = chkUseClipboard.checked
            self._hopper:save()
        end)
        grp:addChild(chkUseClipboard)
    end
    do
        local row = HGroup:new()
        do
            row:addChild(Spacer:new())

            local btnConfChars = Button:new("Configure Characters...")
            btnConfChars.weight = 0
            self._confCharacters =
                EventStream
                :fromEvent(btnConfChars, "ui:Clicked")
                :map(fun.const())
            row:addChild(btnConfChars)
        end
        grp:addChild(row)
    end
    return grp
end

function HopperWindow:_mkLogGroup()
    self._logger = Logger:new()
    return self._logger
end

function HopperWindow:_mkButtonsGroup()
    local row = HGroup:new()
    row.weight = 0
    do
        local btnImport = Button:new("Import voice clips...")
        btnImport.weight  = 0
        self._importVoiceClips =
            EventStream
            :fromEvent(btnImport, "ui:Clicked")
            :map(fun.const())
        self._watchDir:onValue(function (watchDir)
            btnImport.enabled = not not watchDir
        end)
        row:addChild(btnImport)
    end
    return row
end

function HopperWindow:_chooseDir(oldPath)
    assert(oldPath == nil or type(oldPath) == "string")

    -- See https://note.com/hitsugi_yukana/n/n5d821fd71b3c
    local newPath = ui.fusion:RequestDir(
        oldPath,
        {
            FReqB_Saving = false,
            FReqS_Title  =
                (ui.platform == "linux" and "Choose a directory to watch")
                or "Choose a folder to watch"
        })
    if newPath ~= nil then
        self._watchDirBus:push(newPath):await()
        self._startRequested:push():await()
    end
end

return HopperWindow
