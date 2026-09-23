local Array       = require("collection/array")
local Bus         = require("reactive").Bus
local Button      = require("widget/button")
local Colour      = require("colour")
local ComboBox    = require("widget/combo-box")
local EventStream = require("reactive").EventStream
local HGap        = require("widget/h-gap")
local HGroup      = require("widget/container/h-group")
local KeySet      = require("collection/set/key-set")
local Label       = require("widget/label")
local LineEdit    = require("widget/line-edit")
local Map         = require("collection/map")
local Property    = require("reactive").Property
local Set         = require("collection/set")
local Spacer      = require("widget/spacer")
local String      = require("ustring")
local Subtitle    = require("entity/voice/subtitle")
local TextEdit    = require("widget/text-edit")
local Tree        = require("widget/tree")
local TreeColumn  = require("widget/tree/column")
local TreeItem    = require("widget/tree/item")
local UIEvent     = require("ui/event")
local VGap        = require("widget/v-gap")
local VGroup      = require("widget/container/v-group")
local Voice       = require("entity/voice")
local VoiceNotify = require("voice-notify")
local Window      = require("widget/window")
local class       = require("class")
local path        = require("path")

-- @private
local SubtitleDB = class("SubtitleDB")
function SubtitleDB:__init()
    self._subs = Map:new() -- Map<name, Subtitle>
end
function SubtitleDB:clear()
    self._subs:clear()
end
function SubtitleDB:get(voice)
    local sub = self._subs:get(voice.name)
    if sub then
        sub:update(voice)
    else
        sub = Subtitle:new(voice)
        self._subs:set(voice.name, sub)
    end
    return sub
end
function SubtitleDB:purgeExceptFor(names)
    local diff = KeySet:new(self._subs) - names
    -- :toSeq() because we're deleting elements from the very map we're
    -- iterating over.
    for _i, name in ipairs(diff:toSeq()) do
        self._subs:delete(name)
    end
end

local ImportVoicesWindow = class("ImportVoicesWindow", Window)

function ImportVoicesWindow:__init(propWatchDir, propClassifier)
    assert(Property:made(propWatchDir))
    assert(Property:made(propClassifier))
    super()

    self._watchDir       = propWatchDir     -- Property<Path or nil>
    self._watcher        = nil              -- VoiceNotify or nil
    self._voicesBus      = Bus:new()        -- Bus<Voices> where Voices: Map<BaseName: string, Voice>
    self._voices         = self._voicesBus:toProperty() -- Property<Voices>
    self._classifier     = propClassifier   -- Property<Classifier>
    self._subtitles      = SubtitleDB:new() -- SubtitleDB
    self._highlightedBus = Bus:new()        -- Bus<Voice|nil>
    self._highlighted    = self._highlightedBus:toProperty(nil) -- Property<Voice|nil>
    self._selectedBus    = Bus:new()        -- Bus<Voice[]>
    self._selected       = self._selectedBus:toProperty(Array:of()) -- Property<Voice[]>
    self._selectAll      = Bus:new()        -- Bus<void>
    self._deselectAll    = Bus:new()        -- Bus<void>

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
        cmbFilter:addItem("Voices Not in the MediaPool", "not-in-pool")
        cmbFilter:addItem("Voices Unused in Any Timelines", "unused-anywhere")
        cmbFilter:addItem("Voices Unused in the Current Timeline", "unused-in-current")
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
        tab.selectionMode = Tree.SelectionMode.Extended
        -- FIXME: Also refresh the table when the filter is changed.
        local function mkTrackColumn(classifier, voice)
            return classifier(voice.name):match {
                NoMatch = function ()
                    local col = TreeColumn:new("No Matches")
                    col.colour.fg = Colour:name("red")
                    col.toolTip   = "No characters have a pattern matching to this file."
                    return col
                end,
                Match = function (char)
                    return TreeColumn:new(char.portrait)
                end,
                Ambiguous = function (chars)
                    local names = Array:from(chars):map(
                        function (char)
                            return char.portrait
                        end)
                        :join(", ")
                    local col   = TreeColumn:new("Ambiguous: " .. names)
                    col.colour.fg = Colour:name("red")
                    col.toolTip   =
                        "More than a single character have a pattern matching to this file: "
                        .. names
                    return col
                end
            }
        end
        local function mkTypeColumn(voice)
            return TreeColumn:new(voice.audioType or "")
        end
        local function mkLabColumn(voice)
            if voice.lipSync then
                local col = TreeColumn:new("○") -- U+3007 IDEOGRAPHIC NUMBER ZERO
                col.colour.fg = Colour:name("green")
                return col
            else
                return TreeColumn:new("—") -- U+2014 EM DASH
            end
        end
        local function mkSubtitleColumn(voice)
            local sub = self._subtitles:get(voice)
            if sub.text then
                return TreeColumn:new(sub.text)
            else
                local col = TreeColumn:new("—") -- U+2014 EM DASH
                col.colour.fg = Colour:name("gold")
                return col
            end
        end
        Property:combineAsArray(self._classifier, self._voices):onValue(
            function (args)
                local classifier, voices = args:unpack()

                local seen = Set:new()
                local i    = 1
                while i <= tab.items.length do
                    local item  = tab.items[i]
                    local name  = item.columns[1].text
                    local voice = voices:get(name)
                    if voice then
                        item.columns[2]:assign(mkTrackColumn(classifier, voice))
                        item.columns[3]:assign(mkTypeColumn(voice))
                        item.columns[4]:assign(mkLabColumn(voice))
                        item.columns[5]:assign(mkSubtitleColumn(voice))
                        seen:add(name)
                        i = i + 1
                    else
                        -- This voice no longer exists.
                        tab:removeItemAt(i)
                    end
                end

                local missing = KeySet:new(voices) - seen
                for name in missing:values() do
                    local voice = voices:get(name)
                    local item  = TreeItem:new {
                        TreeColumn:new(voice.name),
                        mkTrackColumn(classifier, voice),
                        mkTypeColumn(voice),
                        mkLabColumn(voice),
                        mkSubtitleColumn(voice)
                    }
                    tab:addItem(item)
                end
            end)
        self._selectAll:onValue(
            function ()
                tab:suspend("ui:ItemSelectionChanged")
                for item in tab.items:values() do
                    item.selected = true
                end
                tab:resume("ui:ItemSelectionChanged")
                   :emit("ui:ItemSelectionChanged", UIEvent:new())
                   :await()
            end)
        self._deselectAll:onValue(
            function ()
                tab:suspend("ui:ItemSelectionChanged")
                for item in tab.items:values() do
                    item.selected = false
                end
                tab:resume("ui:ItemSelectionChanged")
                   :emit("ui:ItemSelectionChanged", UIEvent:new())
                   :await()
            end)
        self._highlightedBus:plug(
            self._voices
                :sampledBy(
                    EventStream:fromEvent(tab, "ui:CurrentItemChanged"))
                :map(
                    function (voices)
                        local item = tab.currentItem
                        if item then
                            local name = item.columns[1].text
                            return voices:get(name)
                        end
                    end))
        self._selectedBus:plug(
            self._voices
                :sampledBy(
                    EventStream:fromEvent(tab, "ui:ItemSelectionChanged"))
                :map(
                    function (voices)
                        local ret = Array:of()
                        for item in tab.selectedItems:values() do
                            local name  = item.columns[1].text
                            local voice = voices:get(name)
                            assert(Voice:made(voice))
                            ret:push(voice)
                        end
                        return ret
                    end))
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
        fldBasename.weight   = 0
        fldBasename.readOnly = true
        self._highlighted:onValue(
            function (voice)
                fldBasename.enabled = not not voice
                fldBasename.text    = (voice and voice.name) or ""
            end)
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
        fldTrack.weight   = 0
        fldTrack.readOnly = true
        Property:combineAsArray(self._classifier, self._highlighted):onValue(
            function (args)
                local classifier, voice = args:unpack()
                if voice then
                    fldTrack.enabled = true
                    classifier(voice.name):match {
                        NoMatch = function ()
                            fldTrack.text        = "No Matches"
                            fldTrack.style.color = Colour:name("red"):asCSS()
                            fldTrack.toolTip     = "No characters have a pattern matching to this file."
                        end,
                        Match = function (char)
                            fldTrack.text        = char.portrait
                            fldTrack.style.color = nil
                            fldTrack.toolTip     = nil
                        end,
                        Ambiguous = function (chars)
                            local names = Array:from(chars):map(
                                function (char)
                                    return char.portrait
                                end)
                                :join(", ")
                            fldTrack.text        = "Ambiguous: " .. names
                            fldTrack.style.color = Colour:name("red"):asCSS()
                            fldTrack.toolTip     =
                                "More than a single character have a pattern matching to this file: "
                                .. names
                        end,
                    }
                else
                    fldTrack.enabled = false
                    fldTrack.text    = ""
                end
            end)
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
        fldType.weight   = 0
        fldType.readOnly = true
        self._highlighted:onValue(
            function (voice)
                fldType.enabled = not not voice
                fldType.text    = (voice and voice.audioType) or ""
            end)
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
        fldLab.weight   = 0
        fldLab.readOnly = true
        self._highlighted:onValue(
            function (voice)
                if voice then
                    fldLab.enabled = true
                    if voice.lipSync then
                        fldLab.text = "Yes"
                        fldLab.style.color = Colour:name("lime"):asCSS()
                    else
                        fldLab.text = "No"
                        fldLab.style.color = nil
                    end
                else
                    fldLab.enabled     = false
                    fldLab.text        = ""
                    fldLab.style.color = nil
                end
            end)
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
        local function save(voice)
            assert(Voice:made(voice))
            local sub  = self._subtitles:get(voice)
            local text = tostring(String:new(txtSubtitle.text):trim())
            if (sub.text or "") ~= text then
                if text == "" then
                    sub:delete()
                else
                    sub:save(text)
                end
            end
        end
        self._highlighted
            :diff(
                nil,
                function (old, new)
                    return Array:of(old, new)
                end)
            :onValue(
                function (args)
                    local old, new = args:unpack()
                    if old then
                        -- Save the old subtitle before changing the
                        -- content of TextEdit.
                        save(old)
                    end
                    if new then
                        local sub = self._subtitles:get(new)
                        txtSubtitle.enabled = true
                        txtSubtitle.text    = sub.text or ""
                    else
                        txtSubtitle.enabled = false
                        txtSubtitle.text    = ""
                    end
                end)
        self._highlighted
            :sampledBy(
                EventStream
                    :fromEvent(txtSubtitle, "ui:TextChanged")
                    :debounce(0.8))
            :onValue(
                function (voice)
                    if voice then
                        save(voice)
                    end
                end)
        grp:addChild(txtSubtitle)
    end
    return grp
end

function ImportVoicesWindow:_mkSelectionGroup()
    local grp = HGroup:new()
    local gap = 2
    grp.weight = 0
    do
        local btnSelectAll = Button:new("Select All")
        btnSelectAll.weight = 0
        self._selectAll:plug(
            EventStream:fromEvent(btnSelectAll, "ui:Clicked"))
        grp:addChild(btnSelectAll)
        grp:addChild(HGap:new(gap))
    end
    do
        local btnDeselectAll = Button:new("Deselect All")
        btnDeselectAll.weight = 0
        self._deselectAll:plug(
            EventStream:fromEvent(btnDeselectAll, "ui:Clicked"))
        grp:addChild(btnDeselectAll)
    end
    do
        local labSelected = Label:new("*** voices selected")
        labSelected.weight  = 0
        labSelected.visible = false
        Property:combineWith(
            function (selected, _ev)
                return selected
            end,
            self._selected,
            -- Avoid updating the label until the window is
            -- shown. Otherwise the label will be resized prematurely.
            EventStream:fromEvent(self, "ui:Show")
        ):onValue(
            function (selected)
                if selected.length > 0 then
                    if selected.length == 1 then
                        labSelected.text = "1 voice selected"
                    else
                        labSelected.text = string.format("%d voices selected", selected.length)
                    end
                    labSelected.visible = true
                else
                    labSelected.visible = false
                end
            end)
        grp:addChild(labSelected)
    end
    grp:addChild(Spacer:new())
    grp:addChild(HGap:new(10))
    do
        local labImported = Label:new("***/*** voices imported")
        labImported.weight = 0
        grp:addChild(labImported)
        grp:addChild(HGap:new(gap))
    end
    do
        local btnImport = Button:new("Import")
        btnImport.weight = 0
        btnImport:on("ui:Clicked", function()
            -- FIXME
        end)
        grp:addChild(btnImport)
    end
    grp:addChild(HGap:new(10))
    return grp
end

function ImportVoicesWindow:_updateVoices()
    assert(self._watcher)

    local map = Map:new()
    for tab in self._watcher.voices:values() do
        local parsed = path.parse(tab.audio.name)
        map:set(parsed.name, Voice:new(parsed.name, tab.audio, tab.subtitle, tab.lipSync))
    end
    self._subtitles:purgeExceptFor(KeySet:new(map))
    self._voicesBus:push(map)
end

function ImportVoicesWindow:_startWatching(watchDir)
    assert(type(watchDir) == "string")

    -- SubtitleDB should be cleared whenever the watch directory
    -- changes. There's no problem forgetting user-set subtitle texts
    -- because they're saved on disk.
    self._subtitles:clear()

    self:_stopWatching()
    self._watcher = VoiceNotify:new(watchDir)
    self._watcher:on("create", function () self:_updateVoices() end)
    self._watcher:on("delete", function () self:_updateVoices() end)
    self._watcher:on("modify", function () self:_updateVoices() end)
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
