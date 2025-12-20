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
local ui       = require("ui")

-- FIXME: delete this
--[[
local spawn = require("thread/spawn")
local delay = require("delay")
spawn(function()
        print("Before delay")
        delay(1000):await()
        print("Called after 1 sec!")
end)
]]
local fs = require("fs")
dump(fs.readdir("/"))

-- ----------------------------------------------------------------------------
-- Voice Hopper
-- ----------------------------------------------------------------------------
local HopperWindow = class("HopperWindow", Window)

function HopperWindow:__init()
    super()
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
            local fldPath = LineEdit:new()
            fldPath.readOnly = true
            row:addChild(fldPath)
            self._fldPath = fldPath

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
                local spin = SpinBox:new(15, 0, nil, 1)
                col:addChild(spin)
            end
            do
                local spin = SpinBox:new(15, 0, nil, 1)
                col:addChild(spin)
            end
            cols:addChild(col)
        end
        grp:addChild(cols)
    end
    do
        local chk = CheckBox:new(false, "Use clipboard if voices lack .txt files")
        chk.toolTip = "Subtitles are usually created from .txt files corresponding to voices. With this option enabled, the clipboard will be used as a fallback."
        grp:addChild(chk)
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
        self._fldPath.text = path
    end
end

function HopperWindow:_startStop()
    error("FIXME: not impl")
end

--
function Main()
    local win = HopperWindow:new()

    win:show()
    ui.dispatcher:RunLoop()
end
Main()
