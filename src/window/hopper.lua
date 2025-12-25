local Colour   = require("colour")
local Widget   = require("widget")
local Button   = require("widget/button")
local CheckBox = require("widget/check-box")
local HGroup   = require("widget/container/h-group")
local VGroup   = require("widget/container/v-group")
local Label    = require("widget/label")
local LineEdit = require("widget/line-edit")
local SpinBox  = require("widget/spin-box")
local TextEdit = require("widget/text-edit")
local VGap     = require("widget/v-gap")
local Window   = require("widget/window")
local class    = require("class")
local event    = require("event")
local ui       = require("ui")

local HopperWindow = class("HopperWindow", Window)

function HopperWindow:__init()
    super()
    self._fldWatchDir     = nil -- LineEdit
    self._labStatus       = nil -- Label
    self._fldGaps         = nil -- SpinBox
    self._fldSubExt       = nil -- SpinBox
    self._chkUseClipboard = nil -- CheckBox

    self._debouncedSaveConfig = event.debounce(
        function(ev)
            self:_saveConfig()
        end, 0.5)
    self:on("Move"  , self._debouncedSaveConfig)
    self:on("Resize", self._debouncedSaveConfig)

    self.title = "Voice Hopper"
    self.type  = "floating"
    self.style.padding = "10px"

    local root = VGroup:new()
    local gap  = 10
    do
        local title = Label:new("Folder to watch:")
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

function HopperWindow:_mkWatchGroup()
    local grp = VGroup:new()
    grp.weight = 0
    do
        local row = HGroup:new()
        do
            self._fldWatchDir = LineEdit:new()
            self._fldWatchDir.readOnly = true
            row:addChild(self._fldWatchDir)
        end
        do
            local btnChoose = Button:new("...")
            btnChoose.weight = 0
            btnChoose.style.padding = "5px"
            btnChoose:on("Clicked", function() self:_chooseDir() end)
            row:addChild(btnChoose)
        end
        grp:addChild(row)
    end
    do
        local row = HGroup:new()
        do
            local labStatus = Label:new("")
            labStatus.weight = 0
            labStatus.style.color           = Colour.rgb(1.0, 1.0, 1.0):asCSS()
            labStatus.style.backgroundColor = Colour.rgb(0  , 0.4, 0  ):asCSS()
            labStatus.style.padding         = "3px"
            labStatus.style.fontSize        = "14px"
            row:addChild(labStatus)
            self._labStatus = labStatus

            -- A dummy label to fill the gap
            row:addChild(Label:new(""))

            local btnStartStop = Button:new("")
            btnStartStop.weight = 0
            btnStartStop:on("Clicked", function() self:_startStop() end)
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
                local label = Label:new("Gaps (in frames)")
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
                self._fldGaps = SpinBox:new(15, 0, nil, 1)
                col:addChild(self._fldGaps)
            end
            do
                self._fldSubExt = SpinBox:new(15, 0, nil, 1)
                col:addChild(self._fldSubExt)
            end
            cols:addChild(col)
        end
        grp:addChild(cols)
    end
    do
        self._chkUseClipboard = CheckBox:new(false, "Use clipboard if voices lack .txt files")
        self._chkUseClipboard.toolTip = "Subtitles are usually created from .txt files corresponding to voices. With this option enabled, the clipboard will be used as a fallback."
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
    local log = TextEdit:new()
    log.readOnly = true
    return log
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

function HopperWindow:_chooseDir()
    local path = ui.fusion:RequestDir(
        ".",
        {
            FReqB_Saving = False,
            FReqS_Title  = "Choose folder to watch"
        })
    if path ~= nil then
        self._fldWatchDir.text = path
        self:_saveConfig()
        -- FIXME: watch this directory
    end
end

function HopperWindow:_startStop()
    error("FIXME: not impl")
end

function HopperWindow:_saveConfig()
    local cfg = {
        version = "1.0.0", -- Version of the config file.

        watchDir = self._fldPath.text,
    }
    print(bmd.writestring(cfg))
end

return HopperWindow
