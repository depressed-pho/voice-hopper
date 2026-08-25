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
local console     = require("console")
local fs          = require("fs")
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

-- @private
local Subtitle = class("Subtitle")
function Subtitle:__init(voice)
    assert(Voice:made(voice))

    self._audioEnt = voice.audio    -- DirEnt
    self._subEnt   = voice.subtitle -- DirEnt|nil
    self._text     = nil            -- string|nil
end
function Subtitle.__getter:text()
    if not self._text then
        if self._subEnt then
            -- The file is there. We just haven't read it yet.
            local ok, ret = pcall(fs.readFile, self._subEnt.path)
            if ok then
                self._text = ret
            else
                -- The file is gone now? This is not an error.
                console:warn("%s", ret)
            end
        end
    end
    return self._text
end
function Subtitle:update(voice)
    assert(Voice:made(voice))

    self._audioEnt = voice.audio
    if self._text then
        if voice.subtitle then
            -- We've read the file, and the file still exists. But does
            -- it still have the same text?
            if self._subEnt.lastModified == voice.subtitle.lastModified then
                -- It most likely is.
            else
                -- Probably not. Forget the text we previously read.
                self._text = nil
            end
        else
            -- There was a file but it no longer exists. Dunno why the
            -- user deleted it, but we should probably forget it now.
            self._text = nil
        end
    end
    self._subEnt = voice.subtitle
end

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
    for _i, name in ipairs(diff:toSeq()) do
        self._subs:delete(name)
    end
end

local ImportVoicesWindow = class("ImportVoicesWindow", Window)

function ImportVoicesWindow:__init(propWatchDir, propClassifier)
    assert(Property:made(propWatchDir))
    assert(Property:made(propClassifier))
    super()

    self._watchDir     = propWatchDir     -- Property<Path or nil>
    self._watcher      = nil              -- VoiceNotify or nil
    self._voicesBus    = Bus:new()        -- Bus<Voices> where Voices: Map<BaseName: string, Voice>
    self._voices       = self._voicesBus:toProperty() -- Property<Voices>
    self._classifier   = propClassifier   -- Property<Classifier>
    self._subtitles    = SubtitleDB:new() -- SubtitleDB

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
                    col.colour.fg = Colour:name("red")
                    return col
                end,
                Match = function (char)
                    return TreeColumn:new(char.portrait)
                end,
                Ambiguous = function (_chars)
                    local col = TreeColumn:new("Ambiguous")
                    col.colour.fg = Colour:name("red")
                    return col
                end
            }
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

                tab:clear() -- FIXME: Don't
                local elems = Array:of()
                for voice in voices:values() do
                    local item = TreeItem:new {
                        TreeColumn:new(voice.name),
                        mkTrackColumn(classifier, voice),
                        TreeColumn:new(voice.audioType or ""),
                        mkLabColumn(voice),
                        mkSubtitleColumn(voice)
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
    -- FIXME: react on modify event too
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
