local Colour      = require("colour")
local Button      = require("widget/button")
local CheckBox    = require("widget/check-box")
local HGroup      = require("widget/container/h-group")
local VGroup      = require("widget/container/v-group")
local Label       = require("widget/label")
local LineEdit    = require("widget/line-edit")
local Logger      = require("widget/logger")
local Set         = require("collection/set")
local SpinBox     = require("widget/spin-box")
local VGap        = require("widget/v-gap")
local Window      = require("widget/window")
local class       = require("class")
local event       = require("event")
local ui          = require("ui")

local HopperWindow = class("HopperWindow", Window)

function HopperWindow:__init(hopper)
    local events = Set:new {
        "watchDirChosen", -- (dirPath: string)
        "startRequested", -- (dirPath: string)
        "stopRequested",  -- ()
    }
    super(events)

    self._hopper          = hopper -- Config
    self._isImporting     = false
    self._fldWatchDir     = nil    -- LineEdit
    self._labStatus       = nil    -- Label
    self._btnStartStop    = nil    -- Button
    self._fldGaps         = nil    -- SpinBox
    self._fldSubExt       = nil    -- SpinBox
    self._chkUseClipboard = nil    -- CheckBox
    self._logger          = nil    -- Logger

    self:on("ui:Move", event.debounce(
        function()
            self._hopper.fields.position.x = self.position.x
            self._hopper.fields.position.y = self.position.y
            self._hopper:save()
        end, 0.5)
    )
    self:on("ui:Resize", event.debounce(
        function()
            self._hopper.fields.size.w = self.size.w
            self._hopper.fields.size.h = self.size.h
            self._hopper:save()
        end, 0.5)
    )
    self:on("ui:Show", function()
        self:_updateStatus()
        if self.isWatching then
            local dirPath = self._hopper.fields.watchDir
            assert(dirPath)
            self:emit("startRequested", dirPath)
        end
    end)

    self.title = "Voice Hopper"
    self.type  = "floating"
    self.style.padding = "10px"

    self.position.x = self._hopper.fields.position.x or self.position.x
    self.position.y = self._hopper.fields.position.y or self.position.y
    self.size.w     = self._hopper.fields.size.w     or self.size.w
    self.size.h     = self._hopper.fields.size.h     or self.size.h

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

    -- This has to be done after setting up all the widgets.
    self.isWatching = self._hopper.fields.watching
end

function HopperWindow.__getter:logger()
    return self._logger
end

function HopperWindow:_mkWatchGroup()
    local grp = VGroup:new()
    grp.weight = 0
    do
        local row = HGroup:new()
        do
            self._fldWatchDir = LineEdit:new()
            self._fldWatchDir.readOnly = true
            self._fldWatchDir.text     = self._hopper.fields.watchDir or ""
            row:addChild(self._fldWatchDir)
        end
        do
            local btnChoose = Button:new("...")
            btnChoose.weight = 0
            btnChoose.style.padding = "5px"
            btnChoose:on("ui:Clicked", function() self:_chooseDir() end)
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
            row:addChild(labStatus)
            self._labStatus = labStatus

            -- A dummy label to fill the gap
            row:addChild(Label:new(""))

            -- The initial text of the button should be the longest one it
            -- can show, so that the widget need not be resized later.
            local btnStartStop = Button:new("Start Watching")
            btnStartStop.weight = 0
            btnStartStop.enabled = not not self._hopper.fields.watchDir
            btnStartStop:on("ui:Clicked", function() self:_startStop() end)
            row:addChild(btnStartStop)
            self._btnStartStop = btnStartStop
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
                label.toolTip = "Number of frames between consecutive voice clips"
                col:addChild(label)
            end
            do
                local label = Label:new("Subtitle extension (in frames)")
                label.indent  = indent
                label.toolTip = "Number of frames to extend the subtitle at the end of a voice clip."
                col:addChild(label)
            end
            cols:addChild(col)
        end
        do
            local col = VGroup:new()
            do
                self._fldGaps = SpinBox:new(self._hopper.fields.gaps, 0, 300, 1)
                self._fldGaps.alignment.horizontal = "right"
                self._fldGaps:on("ui:ValueChanged", event.debounce(
                    function()
                        self._hopper.fields.gaps = self._fldGaps.value
                        self._hopper:save()
                    end, 0.5))
                col:addChild(self._fldGaps)
            end
            do
                self._fldSubExt = SpinBox:new(self._hopper.fields.subExt, 0, 300, 1)
                self._fldSubExt.alignment.horizontal = "right"
                self._fldSubExt:on("ui:ValueChanged", event.debounce(
                    function()
                        self._hopper.fields.subExt = self._fldSubExt.value
                        self._hopper:save()
                    end, 0.5))
                col:addChild(self._fldSubExt)
            end
            cols:addChild(col)
        end
        grp:addChild(cols)
    end
    do
        self._chkUseClipboard =
            CheckBox:new(self._hopper.fields.useClipboard, "Use clipboard if voices lack .txt files")
        self._chkUseClipboard.toolTip =
            "Subtitles are usually created from .txt files corresponding to voices.\n" ..
            "With this option enabled, the clipboard will be used as a fallback."
        self._chkUseClipboard:on("ui:Toggled", function()
            self._hopper.fields.useClipboard = self._chkUseClipboard.checked
            self._hopper:save()
        end)
        grp:addChild(self._chkUseClipboard)
    end
    do
        local row = HGroup:new()
        do
            -- A dummy label to fill the gap
            row:addChild(Label:new(""))

            local btn = Button:new("Configure Characters...")
            btn.weight = 0
            row:addChild(btn)
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
        local btn = Button:new("Import voice clip...")
        btn.weight = 0
        row:addChild(btn)
    end
    return row
end

function HopperWindow.__getter:isWatching()
    return self._hopper.fields.watching
end
function HopperWindow.__setter:isWatching(watching)
    assert(type(watching) == "boolean", "HopperWindow#watching expects a boolean value")

    self._hopper.fields.watching = watching
    self._hopper:save()

    if self.materialised then
        self:_updateStatus()
    end
end

function HopperWindow:_updateStatus()
    if self._isImporting then
        self._status = "importing"
    elseif self.isWatching then
        self._status = "watching"
    else
        self._status = "idle"
    end

    if self._hopper.fields.watching then
        self._btnStartStop.label = "Stop Watching"
    else
        self._btnStartStop.label = "Start Watching"
    end
end

function HopperWindow.__setter:_status(status)
    assert(self.materialised, "This setter must be called only after the window is materialised")

    if status == "importing" then
        self._labStatus.text                  = "Importing"
        self._labStatus.style.color           = Colour:rgb(1.0, 1.0, 1.0):asCSS()
        self._labStatus.style.backgroundColor = Colour:rgb(0.4, 0.0, 0.0):asCSS()
    elseif status == "watching" then
        self._labStatus.text                  = "Watching"
        self._labStatus.style.color           = Colour:rgb(1.0, 1.0, 1.0):asCSS()
        self._labStatus.style.backgroundColor = Colour:rgb(0.0, 0.4, 0.0):asCSS()
    elseif status == "idle" then
        self._labStatus.text                  = "Idle"
        self._labStatus.style.color           = Colour:rgb(0.7, 0.7, 0.7):asCSS()
        self._labStatus.style.backgroundColor = Colour:rgb(0.2, 0.2, 0.2):asCSS()
    end
end

function HopperWindow:_chooseDir()
    -- See https://note.com/hitsugi_yukana/n/n5d821fd71b3c
    local absPath = ui.fusion:RequestDir(
        self._hopper.fields.watchDir or ".",
        {
            FReqB_Saving = false,
            FReqS_Title  =
                (ui.platform == "linux" and "Choose a directory to watch")
                or "Choose a folder to watch"
        })
    if absPath ~= nil then
        self._fldWatchDir.text     = absPath
        self._btnStartStop.enabled = true

        self._hopper.fields.watchDir = absPath
        self._hopper:save()

        self:emit("watchDirChosen", absPath)
    end
end

function HopperWindow:_startStop()
    if self._hopper.fields.watching then
        self:emit("stopRequested")
    else
        local dirPath = self._hopper.fields.watchDir
        assert(dirPath)
        self:emit("startRequested", dirPath)
    end
end

return HopperWindow
