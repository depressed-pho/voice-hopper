local Button       = require("widget/button")
local ComboBox     = require("widget/combo-box")
local HGap         = require("widget/h-gap")
local HGroup       = require("widget/container/h-group")
local Label        = require("widget/label")
local LineEdit     = require("widget/line-edit")
local Set          = require("collection/set")
local Spacer       = require("widget/spacer")
local Stack        = require("widget/container/stack")
local TabBar       = require("widget/tab-bar")
local TimelineItem = require("resolve/timeline/item")
local Tree         = require("widget/tree")
local TreeColumn   = require("widget/tree/column")
local TreeItem     = require("widget/tree/item")
local VGap         = require("widget/v-gap")
local VGroup       = require("widget/container/v-group")
local Window       = require("widget/window")
local class        = require("class")
--local event        = require("event")

local CharConfWindow = class("CharConfWindow", Window)

function CharConfWindow:__init(chars)
    local events = Set:new {
    }
    super(events)

    self._chars           = chars -- Config
    self._btnAdd          = nil   -- Button
    self._btnDelete       = nil   -- Button
    self._table           = nil   -- Tree
    self._fldPattern      = nil   -- LineEdit
    self._fldTrkPortrait  = nil   -- LineEdit
    self._fldTrkSubtitles = nil   -- LineEdit
    self._fldTrkVoices    = nil   -- LineEdit
    self._cmbColour       = nil   -- ComboBox
    self._tabSubtitles    = nil   -- TabBar
    self._stkSubtitles    = nil   -- Stack
    self._cmbPresetSubs   = nil   -- ComboBox
    self._fldUserSubs     = nil   -- LineEdit
    self._labErrors       = nil   -- Label
    self._btnDiscard      = nil   -- Button
    self._btnSave         = nil   -- Button

--[[
    self:on("ui:Move", event.debounce(
        function()
            self._chars.fields.position.x = self.position.x
            self._chars.fields.position.y = self.position.y
            --self._chars:save() -- FIXME
        end, 0.5)
    )
    self:on("ui:Resize", event.debounce(
        function()
            self._chars.fields.size.w = self.size.w
            self._chars.fields.size.h = self.size.h
            --self._chars:save() -- FIXME
        end, 0.5)
    )
]]
    self:on("ui:Show", function ()
        -- Workaround for a possible Resolve bug.
        self._stkSubtitles.currentIndex = 2
        self._stkSubtitles.currentIndex = 1
    end)

    self.title = "Characters"
    self.type  = "floating"
    self.style.padding = "10px"

    self.position.x = self._chars.fields.position.x or self.position.x
    self.position.y = self._chars.fields.position.y or self.position.y
    self.size.w     = self._chars.fields.size.w     or self.size.w
    self.size.h     = self._chars.fields.size.h     or self.size.h

    local root = HGroup:new()
    local gap  = 2
    do
        root:addChild(self:_mkTableGroup())
        root:addChild(HGap:new(gap))
    end
    do
        root:addChild(self:_mkFieldsGroup())
    end
    self:addChild(root)
end

function CharConfWindow:_mkTableGroup()
    local grp = VGroup:new()
    do
        local btns = HGroup:new()
        btns.weight = 0
        do
            self._btnAdd = Button:new("Add")
            self._btnAdd.weight = 0
            btns:addChild(self._btnAdd)
        end
        do
            self._btnDelete = Button:new("Delete...")
            self._btnDelete.weight = 0
            btns:addChild(self._btnDelete)
        end
        grp:addChild(btns)
    end
    do
        self._table = Tree:new(4)
        self._table.header = TreeItem:new {
            TreeColumn:new "Pattern",
            TreeColumn:new "Name",
            TreeColumn:new "Colour",
            TreeColumn:new "Subtitles"
        }
        grp:addChild(self._table)
    end
    return grp
end

function CharConfWindow:_mkFieldsGroup()
    local grp = VGroup:new()
    local gap = 2
    do
        local label = Label:new("Pattern of file name:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldPattern = LineEdit:new()
        self._fldPattern.weight = 0
        grp:addChild(self._fldPattern)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Track names:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        local cols = HGroup:new()
        cols.weight = 0
        do
            local col = VGroup:new()
            do
                self._fldTrkPortrait = LineEdit:new()
                col:addChild(self._fldTrkPortrait)
            end
            do
                self._fldTrkSubtitles = LineEdit:new()
                self._fldTrkSubtitles.readOnly = true
                col:addChild(self._fldTrkSubtitles)
            end
            do
                self._fldTrkVoices = LineEdit:new()
                self._fldTrkVoices.readOnly = true
                col:addChild(self._fldTrkVoices)
            end
            cols:addChild(col)
        end
        do
            local col = VGroup:new()
            col.weight = 0
            col:addChild(Label:new("for portrait"))
            col:addChild(Label:new("for subtitles"))
            col:addChild(Label:new("for voices"))
            cols:addChild(col)
        end
        grp:addChild(cols)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Clip colour:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._cmbColour = ComboBox:new()
        self._cmbColour.weight = 0
        self._cmbColour:addItem("None")
        for _i, colour in ipairs(TimelineItem.CLIP_COLOURS) do
            self._cmbColour:addItem(colour)
        end
        grp:addChild(self._cmbColour)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Setting file subtitles:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._tabSubtitles = TabBar:new {
            TabBar.Tab:new "Preset",
            TabBar.Tab:new "User-defined"
        }
        self._tabSubtitles.weight = 0
        self._tabSubtitles.drawBase = true
        self._tabSubtitles.expanding = true
        self._tabSubtitles:on("ui:CurrentChanged", function()
            self._stkSubtitles.currentIndex = self._tabSubtitles.currentIndex
        end)
        grp:addChild(self._tabSubtitles)
    end
    do
        self._stkSubtitles = Stack:new()
        self._stkSubtitles.weight = 0
        do
            self._cmbPresetSubs = ComboBox:new()
            -- FIXME: presets
            self._stkSubtitles:addChild(self._cmbPresetSubs)
        end
        do
            local row = HGroup:new()
            do
                self._fldUserSubs = LineEdit:new()
                self._fldUserSubs.readOnly = true
                row:addChild(self._fldUserSubs)
            end
            do
                local btnChoose = Button:new("...")
                btnChoose.weight = 0
                btnChoose.style.padding = "5px";
                row:addChild(btnChoose)
            end
            self._stkSubtitles:addChild(row)
        end
        grp:addChild(self._stkSubtitles)
        grp:addChild(VGap:new(gap))
    end
    do
        self._labErrors = Label:new("FIXME: errors here")
        self._labErrors.weight = 0
        self._labErrors.style.color = "red"
        grp:addChild(self._labErrors)
    end
    do
        local buttons = HGroup:new()
        buttons.weight = 0
        buttons:addChild(Spacer:new())
        do
            self._btnDiscard = Button:new("Discard...")
            self._btnDiscard.weight = 0
            buttons:addChild(self._btnDiscard)
        end
        do
            self._btnSave = Button:new("Save")
            self._btnSave.weight = 0
            buttons:addChild(self._btnSave)
        end
        grp:addChild(buttons)
    end
    return grp
end

return CharConfWindow
