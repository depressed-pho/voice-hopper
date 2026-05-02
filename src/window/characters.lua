local Button       = require("widget/button")
local Colour       = require("colour")
local ComboBox     = require("widget/combo-box")
local HGap         = require("widget/h-gap")
local HGroup       = require("widget/container/h-group")
local Label        = require("widget/label")
local LineEdit     = require("widget/line-edit")
local Promise      = require("promise")
local RegExp       = require("re")
local Set          = require("collection/set")
local Spacer       = require("widget/spacer")
local Stack        = require("widget/container/stack")
local Subtitles    = require("entity/subtitles")
local TabBar       = require("widget/tab-bar")
local TimelineItem = require("resolve/timeline/item")
local Tree         = require("widget/tree")
local TreeColumn   = require("widget/tree/column")
local TreeItem     = require("widget/tree/item")
local VGap         = require("widget/v-gap")
local VGroup       = require("widget/container/v-group")
local Window       = require("widget/window")
local class        = require("class")
local console      = require("console")
local event        = require("event")
local modal        = require("modal")
local path         = require("path")
local subPresets   = require("assets/subtitles")
local ui           = require("ui")

local COLOUR_OF = {
    Orange    = Colour:rgb(1.00, 0.65, 0.00),
    Apricot   = Colour:rgb(1.00, 0.70, 0.50),
    Yellow    = Colour:rgb(1.00, 1.00, 0.00),
    Lime      = Colour:rgb(0.00, 1.00, 0.00),
    Olive     = Colour:rgb(0.50, 0.50, 0.00),
    Green     = Colour:rgb(0.00, 0.50, 0.00),
    Teal      = Colour:rgb(0.00, 0.50, 0.50),
    Navy      = Colour:rgb(0.00, 0.00, 0.50),
    Blue      = Colour:rgb(0.00, 0.00, 1.00),
    Purple    = Colour:rgb(0.50, 0.00, 0.50),
    Violet    = Colour:rgb(0.93, 0.51, 0.93),
    Pink      = Colour:rgb(1.00, 0.75, 0.80),
    Tan       = Colour:rgb(0.82, 0.71, 0.55),
    Beige     = Colour:rgb(0.96, 0.96, 0.86),
    Brown     = Colour:rgb(0.65, 0.16, 0.16),
    Chocolate = Colour:rgb(0.82, 0.41, 0.12),
}

local CharConfWindow = class("CharConfWindow", Window)

function CharConfWindow:__init(chars)
    local events = Set:new {
    }
    super(events)

    self._chars             = chars -- Characters
    self._original          = self._chars.Character:new() -- Character
    self._btnNew            = nil   -- Button
    self._btnDelete         = nil   -- Button
    self._table             = nil   -- Tree
    self._fldPattern        = nil   -- LineEdit
    self._fldTrkPortrait    = nil   -- LineEdit
    self._fldTrkSubtitles   = nil   -- LineEdit
    self._fldTrkVoices      = nil   -- LineEdit
    self._cmbColour         = nil   -- ComboBox
    self._labColour         = nil   -- Label
    self._tabSubtitles      = nil   -- TabBar
    self._stkSubtitles      = nil   -- Stack
    self._cmbPresetSubs     = nil   -- ComboBox
    self._fldUserSubs       = nil   -- LineEdit
    self._btnChooseUserSubs = nil   -- Button
    self._labErrors         = nil   -- Label
    self._btnDiscard        = nil   -- Button
    self._btnSave           = nil   -- Button

    self:on("ui:Move", event.debounce(
        function()
            self._chars.position.x = self.position.x
            self._chars.position.y = self.position.y
            self._chars:save()
        end, 0.5)
    )
    self:on("ui:Resize", event.debounce(
        function()
            self._chars.size.w = self.size.w
            self._chars.size.h = self.size.h
            self._chars:save()
        end, 0.5)
    )
    self:on("ui:Show", function ()
        -- Workaround for a possible Resolve bug. Widgets that are supposed
        -- to be hidden are still rendered, unless we change the current
        -- index of UIStack. THINKME: Remove this when it's fixed.
        if not self._shownOnce then
            self._stkSubtitles.currentIndex = 2
            self._stkSubtitles.currentIndex = 1
            self._shownOnce = true
        end
    end)

    self.title = "Characters"
    self.type  = "floating"
    self.style.padding = "10px"

    self.position.x = self._chars.position.x or self.position.x
    self.position.y = self._chars.position.y or self.position.y
    self.size.w     = self._chars.size.w     or self.size.w
    self.size.h     = self._chars.size.h     or self.size.h

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

    for portrait, char in self._chars.map:entries() do
        local colColour = TreeColumn:new("■")
        colColour.colour.fg = COLOUR_OF[char.colour]

        local colSubs = TreeColumn:new(
            (char.usesPresetSubtitles and subPresets[char.subtitles].label)
            or char.subtitles
        )

        local item = TreeItem:new {
            TreeColumn:new(char.pattern.source),
            TreeColumn:new(portrait),
            colColour,
            colSubs,
        }
        self._table:addItem(item)
    end
end

function CharConfWindow:_mkTableGroup()
    local grp = VGroup:new()
    do
        local btns = HGroup:new()
        btns.weight = 0
        do
            self._btnNew = Button:new("New")
            self._btnNew.weight = 0
            self._btnNew:onAsync("ui:Clicked", function()
                self:_newCharacter()
            end)
            btns:addChild(self._btnNew)
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
            TreeColumn:new "Track",
            TreeColumn:new "Colour",
            TreeColumn:new "Subtitles"
        }
        -- We really want to resize columns automatically but the UITree
        -- widget doesn't appear to support Qt's resizeColumnToContents():
        -- https://doc.qt.io/qt-6/qtreeview.html#resizeColumnToContents
        self._table.columnWidth[1] = 110
        self._table.columnWidth[2] = 50
        self._table.columnWidth[3] = 10
        -- The width of the last column is intentionally left out so that
        -- it takes all the remaining space. We'd also like to save widths
        -- to config when columns are resized, but there seems to be no
        -- events that are triggered when that happens.
        self._table:onAsync("ui:CurrentItemChanged", function()
            local item = self._table.currentItem
            if item then
                local track = item.cols[2].text
                local char  = self._chars.map:get(track)
                assert(char, "A character whose track name is \""..track.."\" must exist")
                self:_editCharacter(char)
            end
        end)
        grp:addChild(self._table)
    end
    return grp
end

function CharConfWindow:_mkFieldsGroup()
    local grp = VGroup:new()
    local gap = 2
    do
        local label = Label:new("Pattern of file names:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._fldPattern = LineEdit:new()
        self._fldPattern.weight  = 0
        self._fldPattern.enabled = false
        self._fldPattern:on("ui:TextChanged", function() self:fieldChanged() end)
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
                self._fldTrkPortrait.enabled = false
                self._fldTrkPortrait:on("ui:TextChanged", function() self:fieldChanged() end)
                col:addChild(self._fldTrkPortrait)
            end
            do
                self._fldTrkSubtitles = LineEdit:new()
                self._fldTrkSubtitles.enabled = false
                col:addChild(self._fldTrkSubtitles)
            end
            do
                self._fldTrkVoices = LineEdit:new()
                self._fldTrkVoices.enabled = false
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
        local row = HGroup:new()
        row.weight = 0
        do
            self._cmbColour = ComboBox:new()
            self._cmbColour.enabled = false
            self._cmbColour:addItem("None", "None")
            for colour in TimelineItem.CLIP_COLOURS:values() do
                self._cmbColour:addItem(colour, colour)
            end
            self._cmbColour:on("ui:CurrentIndexChanged", function()
                local name = self._cmbColour.current.data
                if name == "None" then
                    self._labColour.style.color = nil
                else
                    local colour = COLOUR_OF[name]
                    if colour then
                        self._labColour.style.color = colour
                    else
                        console:warn("Unknown colour:", name)
                        console:trace()
                    end
                end
                self:fieldChanged()
            end)
            row:addChild(self._cmbColour)
        end
        do
            self._labColour = Label:new("■")
            self._labColour.weight = 0
            row:addChild(self._labColour)
        end
        grp:addChild(row)
        grp:addChild(VGap:new(gap))
    end
    do
        local label = Label:new("Subtitles:")
        label.weight = 0
        grp:addChild(label)
    end
    do
        self._tabSubtitles = TabBar:new {
            TabBar.Tab:new "Preset",
            TabBar.Tab:new "User-defined"
        }
        self._tabSubtitles.weight    = 0
        self._tabSubtitles.enabled   = false
        self._tabSubtitles.drawBase  = true
        self._tabSubtitles.expanding = true
        self._tabSubtitles:on("ui:CurrentChanged", function()
            self._stkSubtitles.currentIndex = self._tabSubtitles.currentIndex
            self:fieldChanged()
        end)
        grp:addChild(self._tabSubtitles)
    end
    do
        self._stkSubtitles = Stack:new()
        self._stkSubtitles.weight = 0
        do
            self._cmbPresetSubs = ComboBox:new()
            self._cmbPresetSubs.enabled = false
            -- Sort presets by their labels.
            local tmp = {}
            for id, tab in pairs(subPresets) do
                table.insert(tmp, {id = id, label = tab.label})
            end
            table.sort(tmp, function(a, b) return a.label < b.label end)
            for _i, ent in ipairs(tmp) do
                self._cmbPresetSubs:addItem(ent.label, ent.id)
            end
            self._cmbPresetSubs:on("ui:CurrentIndexChanged", function() self:fieldChanged() end)
            self._stkSubtitles:addChild(self._cmbPresetSubs)
        end
        do
            local row = HGroup:new()
            do
                self._fldUserSubs = LineEdit:new()
                self._fldUserSubs.enabled  = false
                self._fldUserSubs.readOnly = true
                row:addChild(self._fldUserSubs)
            end
            do
                self._btnChooseUserSubs = Button:new("...")
                self._btnChooseUserSubs.weight = 0
                self._btnChooseUserSubs.enabled = false
                self._btnChooseUserSubs.style.padding = "5px";
                self._btnChooseUserSubs:on("ui:Clicked", function() self:_chooseUserSubs() end)
                row:addChild(self._btnChooseUserSubs)
            end
            self._stkSubtitles:addChild(row)
        end
        grp:addChild(self._stkSubtitles)
        grp:addChild(VGap:new(gap))
    end
    do
        self._labErrors = Label:new("")
        self._labErrors.weight             = 0
        self._labErrors.alignment.vertical = "top"
        self._labErrors.style.color        = "red"
        self._labErrors.style.minHeight    = "5ex" -- approx. 2 lines
        self._labErrors.wordWrap           = true
        grp:addChild(self._labErrors)
    end
    do
        local buttons = HGroup:new()
        buttons.weight = 0
        buttons:addChild(Spacer:new())
        do
            self._btnDiscard = Button:new("Discard...")
            self._btnDiscard.weight  = 0
            self._btnDiscard.enabled = false
            self._btnDiscard:onAsync("ui:Clicked", function() self:_revertCharacter() end)
            buttons:addChild(self._btnDiscard)
        end
        do
            self._btnSave = Button:new("Save")
            self._btnSave.weight  = 0
            self._btnSave.enabled = false
            buttons:addChild(self._btnSave)
        end
        grp:addChild(buttons)
    end
    return grp
end

-- Return Promise<bool>: true if we can proceed, false otherwise. The
-- promise is supposed to be never rejected.
function CharConfWindow:_confirmDiscard()
    if self.isDirty then
        local msg
        if self._original.isEmpty then
            msg = "The character being added has not been saved. Do you want to discard it?"
        else
            msg = "The character being edited has not been saved. Do you want to discard changes?"
        end
        return modal.confirm(msg, {defaultButton = "Discard"})
            :then_(true, false)
    else
        return Promise:resolve(true)
    end
end

function CharConfWindow:_editCharacter(char)
    self:_confirmDiscard():then_(function (proceed)
        if proceed then
            self:resetFields(char)
            self.fieldsEnabled = true
        end
    end)
end

function CharConfWindow:_revertCharacter()
    self:_confirmDiscard():then_(function (proceed)
        if proceed then
            self:resetFields(self._original)
            self.fieldsEnabled = not self._original.isEmpty
        end
    end)
end

function CharConfWindow:_newCharacter()
    self:_confirmDiscard():then_(function (proceed)
        if proceed then
            self:resetFields(nil)
            self.fieldsEnabled = true
            local item = self._table.currentItem
            if item then
                item.selected = false
            end
        end
    end)
end

function CharConfWindow:_chooseUserSubs()
    -- See https://note.com/hitsugi_yukana/n/n5d821fd71b3c
    local lastPath = self._chars.lastChosenUserSubs
    local absPath  = ui.fusion:RequestFile(
        lastPath and path.dirname(lastPath),
        lastPath and path.basename(lastPath),
        {
            FReqB_Saving = false,
            FReqS_Title  = "Choose a subtitles setting file",
            FReqS_Filter = "Subtitles setting (*.setting) | *.setting"
        })
    if absPath ~= nil then
        -- Check if it's really a valid subtitles setting.
        local ok, err = pcall(function() Subtitles:readFile(absPath) end)
        if not ok then
            console:error(err)
            modal.alert(
                "Failed to read the subtitles setting.",
                {title = "Error", details = err})
            return
        end

        self._fldUserSubs.text = absPath
        self:fieldChanged()

        self._chars.lastChosenUserSubs = absPath
        self._chars:save()
    end
end

function CharConfWindow.__getter:isDirty()
    -- See if any of the fields have different values from the original
    -- state.
    if self._fldPattern.text ~= (self._original.pattern or RegExp:new("")).source or
        self._fldTrkPortrait.text ~= (self._original.portrait or "") or
        self._cmbColour.current.data ~= (self._original.colour or "None") then
        return true
    end
    -- Subtitles setting is a tricky one...
    if self._original.usesPresetSubtitles then
        if self._tabSubtitles.currentIndex ~= 1 then
            return true
        end

        if self._original.subtitles then
            if self._cmbPresetSubs.current.data ~= self._original.subtitles then
                return true
            end
        else
            -- No subtitles set: the first preset is the default.
            if self._cmbPresetSubs.current.index ~= 1 then
                return true
            end
        end
    else
        if self._tabSubtitles.currentIndex ~= 2 then
            return true
        end

        assert(self._original.subtitles,
               "It has to have a path to subtitles setting given that it uses a user-defined one")
        if self._fldUserSubs.text ~= self._original.subtitles then
            return true
        end
    end
    return false
end

function CharConfWindow.__setter:original(char)
    assert(self._chars.Character:made(char),
           "CharConfWindow#original is expected to be a Character")
    self._original = char
    self:fieldChanged()
end

function CharConfWindow.__setter:fieldsEnabled(b)
    assert(type(b) == "boolean", "CharConfWindow#fieldsEnabled is expected to be a boolean")
    self._fldPattern.enabled = b
    self._fldTrkPortrait.enabled = b
    self._cmbColour.enabled = b
    self._tabSubtitles.enabled = b
    self._cmbPresetSubs.enabled = b
    self._fldUserSubs.enabled = b
    self._btnChooseUserSubs.enabled = b
end

function CharConfWindow:resetFields(char)
    assert(char == nil or self._chars.Character:made(char))
    char = char or self._chars.Character:new()

    if char.isEmpty then
        self._fldPattern.text             = ""
        self._fldTrkPortrait.text         = ""
        self._cmbColour.current.index     = 1
        self._tabSubtitles.currentIndex   = 1
        self._cmbPresetSubs.current.index = 1
        self._fldUserSubs.text = ""
    else
        self._fldPattern.text     = char.pattern.source
        self._fldTrkPortrait.text = char.portrait

        if char.colour then
            -- + 1 is to skip "None"
            self._cmbColour.current.index = TimelineItem.CLIP_COLOURS:indexOf(char.colour) + 1
        else
            self._cmbColour.current.index = 1 -- "None"
        end

        if char.usesPresetSubtitles then
            self._tabSubtitles.currentIndex = 1
            for i=1, self._cmbPresetSubs.size do
                if self._cmbPresetSubs:getItem(i).data == char.subtitles then
                    self._cmbPresetSubs.current.index = i
                    break
                end
            end
            self._fldUserSubs.text = ""
        else
            self._tabSubtitles.currentIndex = 2
            self._cmbPresetSubs.current.index = 1
            self._fldUserSubs.text            = char.subtitles
        end
    end

    -- Setting .original also validates the fields.
    self.original = char
end

-- Return a message string if any of the fields have invalid values, or nil
-- otherwise.
function CharConfWindow:validate()
    if self._fldPattern.text == "" then
        return "Pattern of file names cannot be empty."
    end
    do
        local ok = pcall(function()
            RegExp:new(self._fldPattern.text)
        end)
        if not ok then
            return "The pattern of file names is invalid as a regular expression."
        end
    end
    if self._fldTrkPortrait.text == "" then
        return "Track name for portrait cannot be empty."
    end
    if self._tabSubtitles.currentIndex == 2 and self._fldUserSubs.text == "" then
        return "User-defined subtitles setting has not been chosen."
    end
end

function CharConfWindow:fieldChanged()
    self._btnDiscard.enabled = self.isDirty

    if self.isDirty then
        local err = self:validate()
        if err then
            self._labErrors.text  = err
            self._btnSave.enabled = false
        else
            self._labErrors.text  = ""
            self._btnSave.enabled = self.isDirty
        end
    else
        self._labErrors.text  = ""
        self._btnSave.enabled = false
    end

    local track = self._fldTrkPortrait.text
    if track == "" then
        self._fldTrkSubtitles.text = ""
        self._fldTrkVoices.text    = ""
    else
        self._fldTrkSubtitles.text = track .. "_t"
        self._fldTrkVoices.text    = track .. "_a"
    end
end

return CharConfWindow
