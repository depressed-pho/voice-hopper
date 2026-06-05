local Button     = require("widget/button")
local ComboBox   = require("widget/combo-box")
local HGap       = require("widget/h-gap")
local HGroup     = require("widget/container/h-group")
local Label      = require("widget/label")
local LineEdit   = require("widget/line-edit")
local Spacer     = require("widget/spacer")
local TextEdit   = require("widget/text-edit")
local Tree       = require("widget/tree")
local TreeColumn = require("widget/tree/column")
local TreeItem   = require("widget/tree/item")
local VGap       = require("widget/v-gap")
local VGroup     = require("widget/container/v-group")
local Window     = require("widget/window")
local class      = require("class")

local ImportVoicesWindow = class("ImportVoicesWindow", Window)

function ImportVoicesWindow:__init(_hopper)
    super()

    self._cmbFilter      = nil -- ComboBox
    self._table          = nil -- Tree
    self._fldBasename    = nil -- LineEdit
    self._fldTrack       = nil -- LineEdit
    self._fldType        = nil -- LineEdit
    self._fldLab         = nil -- LineEdit
    self._txtSubtitle    = nil -- TextEdit
    self._btnDeselectAll = nil -- Button
    self._btnSelectAll   = nil -- Button
    self._labSelected    = nil -- Label
    self._btnImport      = nil -- Button

    self.title = "Import" -- FIXME
    self.type  = "floating"
    self.style.padding = "10px"

    local root = VGroup:new()
    do
        root:addChild(self:_mkFilterGroup())
        root:addChild(self:_mkTableGroup())
        root:addChild(self:_mkSelectionGroup())
    end
    self:addChild(root)
end

function ImportVoicesWindow:_mkFilterGroup()
    local grp = HGroup:new()
    grp.weight = 0
    do
        local label = Label:new("Show")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._cmbFilter = ComboBox:new()
        self._cmbFilter.weight = 0
        self._cmbFilter:addItem("Everything", "everything")
        self._cmbFilter:addItem("Voices Unused in the Current Timeline", "unused")
        self._cmbFilter:on("ui:CurrentIndexChanged", function()
            -- FIXME
        end)
        grp:addChild(self._cmbFilter)
    end
    return grp
end

function ImportVoicesWindow:_mkTableGroup()
    local grp = HGroup:new()
    local gap = 2
    do
        self._table = Tree:new(5)
        self._table.weight = 3
        self._table.header = TreeItem:new {
            TreeColumn:new "Name",
            TreeColumn:new "Track",
            TreeColumn:new "Type",
            TreeColumn:new "Lab",
            TreeColumn:new "Subtitle"
        }
        grp:addChild(self._table)
        grp:addChild(HGap:new(gap))
        grp:addChild(self:_mkFieldsGroup())
    end
    return grp
end

function ImportVoicesWindow:_mkFieldsGroup()
    local grp = VGroup:new()
    local gap = 1
    grp.weight = 2
    do
        local label = Label:new("File base name:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldBasename = LineEdit:new()
        self._fldBasename.weight  = 0
        self._fldBasename.enabled = false
        grp:addChild(self._fldBasename)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Track name:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldTrack = LineEdit:new()
        self._fldTrack.weight  = 0
        self._fldTrack.enabled = false
        grp:addChild(self._fldTrack)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Audio file type:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldType = LineEdit:new()
        self._fldType.weight  = 0
        self._fldType.enabled = false
        grp:addChild(self._fldType)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Lab file available:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldLab = LineEdit:new()
        self._fldLab.weight  = 0
        self._fldLab.enabled = false
        grp:addChild(self._fldLab)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Subtitle:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._txtSubtitle = TextEdit:new()
        self._txtSubtitle.enabled = false
        grp:addChild(self._txtSubtitle)
    end
    return grp
end

function ImportVoicesWindow:_mkSelectionGroup()
    local grp = HGroup:new()
    local gap = 5
    grp.weight = 0
    do
        self._btnDeselectAll = Button:new("Deselect All")
        self._btnDeselectAll.weight = 0
        self._btnDeselectAll:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(self._btnDeselectAll)
    end
    do
        self._btnSelectAll = Button:new("Select All")
        self._btnSelectAll.weight = 0
        self._btnSelectAll:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(self._btnSelectAll)
        grp:addChild(HGap:new(gap))
    end
    do
        self._labSelected = Label:new("n items selected") -- FIXME: should be empty initially
        self._labSelected.weight = 0
        grp:addChild(self._labSelected)
        grp:addChild(Spacer:new())
    end
    do
        self._btnImport = Button:new("Import")
        self._btnImport.weight = 0
        self._btnImport:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(HGap:new(10))
        grp:addChild(self._btnImport)
        grp:addChild(HGap:new(10))
    end
    return grp
end

return ImportVoicesWindow
