local Array       = require("collection/array")
local Bus         = require("reactive").Bus
local Button      = require("widget/button")
local Colour      = require("colour")
local ComboBox    = require("widget/combo-box")
local EventStream = require("reactive").EventStream
local HGap        = require("widget/h-gap")
local HGroup      = require("widget/container/h-group")
local Label       = require("widget/label")
local LineEdit    = require("widget/line-edit")
local Map         = require("collection/map")
local Property    = require("reactive").Property
local Spacer      = require("widget/spacer")
local String      = require("ustring")
local TextEdit    = require("widget/text-edit")
local Tree        = require("widget/tree")
local TreeColumn  = require("widget/tree/column")
local TreeItem    = require("widget/tree/item")
local VGap        = require("widget/v-gap")
local VGroup      = require("widget/container/v-group")
local VoiceNotify = require("voice-notify")
local Window      = require("widget/window")
local class       = require("class")
local path        = require("path")

-- @private
local Voice = class("Voice")
function Voice:__init(name, audio, subtitle, lipSync)
    self.name     = name     -- string
    self.audio    = audio    -- DirEnt
    self.subtitle = subtitle -- DirEnt|nil
    self.lipSync  = lipSync  -- DirEnt|nil
end
function Voice.__getter:audioType()
    if not self._audioType then
        local parsed = path.parse(self.audio.name)
        if string.find(parsed.ext, "^%.") then
            return string.upper(string.sub(parsed.ext, 2))
        else
            return nil -- No extension
        end
    end
    return self._audioType
end

local ImportVoicesWindow = class("ImportVoicesWindow", Window)

function ImportVoicesWindow:__init(propWatchDir, propClassifier)
    assert(Property:made(propWatchDir))
    assert(Property:made(propClassifier))
    super()

    self._watchDir     = propWatchDir   -- Property<Path or nil>
    self._watcher      = nil            -- VoiceNotify or nil
    self._voicesBus    = Bus:new()      -- Bus<Voices> where Voices: Map<BaseName: string, Voice>
    self._voices       = self._voicesBus:toProperty() -- Property<Voices>
    self._classifier   = propClassifier -- Property<Classifier>

    -- An instance of VoiceNotify should be started when the window is
    -- opened, and it should be stopped when it is closed. VoiceNotify
    -- should be restarted when watchDir changes while the window is open.
    EventStream
        :mergeAll(
            self._watchDir:sampledBy(EventStream:fromEvent(self, "ui:Show")),
            self._watchDir:sampledBy(EventStream:fromEvent(self, "ui:Hide")),
            self._watchDir)
        :onValue(
            function (watchDir)
                self:_stopWatching()
                if self.isShown then
                    self:_startWatching(watchDir)
                end
            end)

    -- The watch directory should be shown on the window title.
    self._watchDir:onValue(function (dir)
        assert(type(dir) == "string")

        local MAX_LENGTH = 40
        local dirU = String:new(dir)
        if dirU.length > MAX_LENGTH then
            dirU = "…" .. dirU:slice(dirU.length - MAX_LENGTH + 1)
        end
        self.title = "Import from " .. tostring(dirU)
    end)

    self.type          = "floating"
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
        local cmbFilter = ComboBox:new()
        cmbFilter.weight = 0
        cmbFilter:addItem("Everything", "everything")
        cmbFilter:addItem("Voices Unused in the Current Timeline", "unused")
        cmbFilter:on("ui:CurrentIndexChanged", function()
            -- FIXME
        end)
        grp:addChild(cmbFilter)
    end
    return grp
end

function ImportVoicesWindow:_mkTableGroup()
    local grp = HGroup:new()
    local gap = 2
    do
        local tab = Tree:new(5)
        tab.weight = 3
        tab.header = TreeItem:new {
            TreeColumn:new "Name",
            TreeColumn:new "Track",
            TreeColumn:new "Type",
            TreeColumn:new "Lab",
            TreeColumn:new "Subtitle"
        }
        tab:sortByColumn(1, Tree.SortOrder.Ascending)
        tab.columnWidth[2] = 60
        tab.columnWidth[3] = 40
        tab.columnWidth[4] = 35
        -- FIXME: Set columnWidth
        -- FIXME: Also refresh the table when the filter is changed.
        local function mkTrackColumn(classifier, voice)
            return classifier(voice.name):match {
                NoMatch = function ()
                    local col = TreeColumn:new("No Match")
                    col.colour.fg = Colour:rgb(1, 0, 0)
                    return col
                end,
                Match = function (char)
                    return TreeColumn:new(char.portrait)
                end,
                Ambiguous = function (_chars)
                    local col = TreeColumn:new("Ambiguous")
                    col.colour.fg = Colour:rgb(1, 0, 0)
                    return col
                end
            }
        end
        local function mkLabColumn(voice)
            if voice.lipSync then
                local col = TreeColumn:new("○") -- U+3007 IDEOGRAPHIC NUMBER ZERO
                col.colour.fg = Colour:rgb(0, 1, 0)
                return col
            else
                return TreeColumn:new("—") -- U+2014 EM DASH
            end
        end
        Property:combineAsArray(self._classifier, self._voices):onValue(
            function (args)
                local classifier, voices = args:unpack()

                tab:clear() -- FIXME: Don't
                local elems = Array:of()
                for voice in voices:values() do
                    local item = TreeItem:new {
                        TreeColumn:new(voice.name),
                        mkTrackColumn(classifier, voice),
                        TreeColumn:new(voice.audioType or ""),
                        mkLabColumn(voice),
                        TreeColumn:new("FIXME"),
                    }
                    elems:push({item = item, key = voice.name})
                end
                for elem in elems:values() do
                    tab:addItem(elem.item)
                end
            end)
        grp:addChild(tab)
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
        local fldBasename = LineEdit:new()
        fldBasename.weight  = 0
        fldBasename.enabled = false
        grp:addChild(fldBasename)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Track name:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        local fldTrack = LineEdit:new()
        fldTrack.weight  = 0
        fldTrack.enabled = false
        grp:addChild(fldTrack)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Audio file type:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        local fldType = LineEdit:new()
        fldType.weight  = 0
        fldType.enabled = false
        grp:addChild(fldType)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Lab file available:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        local fldLab = LineEdit:new()
        fldLab.weight  = 0
        fldLab.enabled = false
        grp:addChild(fldLab)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Subtitle:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        local txtSubtitle = TextEdit:new()
        txtSubtitle.enabled = false
        grp:addChild(txtSubtitle)
    end
    return grp
end

function ImportVoicesWindow:_mkSelectionGroup()
    local grp = HGroup:new()
    local gap = 5
    grp.weight = 0
    do
        local btnDeselectAll = Button:new("Deselect All")
        btnDeselectAll.weight = 0
        btnDeselectAll:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(btnDeselectAll)
    end
    do
        local btnSelectAll = Button:new("Select All")
        btnSelectAll.weight = 0
        btnSelectAll:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(btnSelectAll)
        grp:addChild(HGap:new(gap))
    end
    do
        local labSelected = Label:new("n items selected") -- FIXME: should be empty initially
        labSelected.weight = 0
        grp:addChild(labSelected)
        grp:addChild(Spacer:new())
    end
    do
        local btnImport = Button:new("Import")
        btnImport.weight = 0
        btnImport:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(HGap:new(10))
        grp:addChild(btnImport)
        grp:addChild(HGap:new(10))
    end
    return grp
end

function ImportVoicesWindow:_updateVoices()
    assert(self._watcher)

    local map = Map:new()
    for tab in self._watcher.voices:values() do
        local parsed = path.parse(tab.audio.name)
        map:set(parsed.name, Voice:new(parsed.name, tab.audio, tab.subtitle, tab.lipSync))
    end
    self._voicesBus:push(map)
end

function ImportVoicesWindow:_startWatching(watchDir)
    assert(type(watchDir) == "string")

    self:_stopWatching()
    self._watcher = VoiceNotify:new(watchDir)
    self._watcher:on("create", function () self:_updateVoices() end)
    -- FIXME: react on delete and modify events too
    self._watcher:start()

    self:_updateVoices()
end

function ImportVoicesWindow:_stopWatching()
    if self._watcher then
        self._watcher:cancel():join():await()
        self._watcher = nil
    end
end

return ImportVoicesWindow
