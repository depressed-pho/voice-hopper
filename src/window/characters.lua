local Button       = require("widget/button")
local ComboBox     = require("widget/combo-box")
local HGap         = require("widget/h-gap")
local HGroup       = require("widget/container/h-group")
local Label        = require("widget/label")
local LineEdit     = require("widget/line-edit")
local Set          = require("collection/set")
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

    self._chars        = chars -- Config
    self._btnAdd       = nil   -- Button
    self._btnDelete    = nil   -- Button
    self._table        = nil   -- Tree
    self._fldPattern   = nil   -- LineEdit
    self._fldTrackName = nil   -- LineEdit
    self._cmbColour    = nil   -- ComboBox

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
            TreeColumn:new "Subtitle"
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
        local label = Label:new("Track name:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldTrackName = LineEdit:new()
        self._fldTrackName.weight = 0
        grp:addChild(self._fldTrackName)
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
        for _i, colour in ipairs(TimelineItem.CLIP_COLOURS) do
            self._cmbColour:addItem(colour)
        end
        grp:addChild(self._cmbColour)
        grp:addChild(VGap:new(gap))
    end
    return grp
end

return CharConfWindow
