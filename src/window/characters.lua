local Array        = require("collection/array")
local Bus          = require("reactive").Bus
local Button       = require("widget/button")
local Colour       = require("colour")
local ComboBox     = require("widget/combo-box")
local EventStream  = require("reactive").EventStream
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
local alc          = require("algebraic")
local class        = require("class")
local console      = require("console")
local fun          = require("function")
local throttle     = require("event/throttle")
local modal        = require("modal")
local path         = require("path")
local subPresets   = require("assets/subtitles")
local ui           = require("ui")

-- THINKME: We should somehow react to Enter (or Return) pressing event and
-- treat that as the "Save" button being clicked.

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

local HowToRefresh = alc.data {
    alc.name "HowToRefresh",
    alc.ctor "LoadAll",
    alc.ctor("SelectChar", "char"),
    alc.ctor "SelectNone",
    alc.ctor("AddChar"   , "char"),
    alc.ctor("DeleteChar", "char"),
    alc.ctor("UpdateChar", "old", "new")
}

local CharConfWindow = class("CharConfWindow", Window)

function CharConfWindow:__init(chars)
    local events = Set:new {
    }
    super(events)

    self._chars             = chars -- Characters
    self._originalBus       = Bus:new() -- Bus<Character or nil>
    self._original          = -- Property<Character>
        self._originalBus:map(
            function (char)
                assert(char == nil or self._chars.Character:made(char))
                if char then
                    return char
                else
                    return self._chars.Character:new()
                end
            end):toProperty(self._chars.Character:new())
    self._refreshTable      = Bus:new() -- Bus<HowToRefresh>
    self._selectedCharBus   = Bus:new() -- Bus<Character or nil>
    self._selectedChar      = self._selectedCharBus:toProperty(nil) -- Property<Character or nil>
    self._selectedColourBus = Bus:new() -- Bus<Colour or nil>
    self._selectedColour    = self._selectedColourBus:toProperty(nil) -- Property<Colour or nil>
    self._fieldsEnabledBus  = Bus:new() -- Bus<boolean>
    self._fieldsEnabled     = self._fieldsEnabledBus:toProperty(false) -- Property<boolean>
    self._fieldChanged      = Bus:new() -- Bus<void>
    self._classifierUpdated = Bus:new() -- Bus<void>
    self._classifier        =           -- Property<Classifier>
        self._classifierUpdated
        :map(
            function ()
                return self._chars.classifier
            end)
        :toProperty(self._chars.classifier)

    self._fldPattern        = nil       -- LineEdit
    self._fldTrkPortrait    = nil       -- LineEdit
    self._cmbColour         = nil       -- ComboBox
    self._tabSubtitles      = nil       -- TabBar
    self._cmbPresetSubs     = nil       -- ComboBox
    self._fldUserSubs       = nil       -- LineEdit

    self:on("ui:Move", throttle.debounce(
        function()
            self._chars.position.x = self.position.x
            self._chars.position.y = self.position.y
            self._chars:save()
        end, 0.5)
    )
    self:on("ui:Resize", throttle.debounce(
        function()
            self._chars.size.w = self.size.w
            self._chars.size.h = self.size.h
            self._chars:save()
        end, 0.5)
    )
    self:on("ui:Show", function ()
        self._refreshTable:push(HowToRefresh.LoadAll:new()):await()
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
        root:addChild(self:_mkFieldsGroup())
    end
    self:addChild(root)

    -- Update the state of widgets.
    self._fieldChanged:push()
end

--
-- CharConfWindow#classifier is a Property<Classifier> representing the
-- current classifier.
--
function CharConfWindow.__getter:classifier()
    return self._classifier
end

function CharConfWindow:_mkTableGroup()
    local grp = VGroup:new()
    do
        local btns = HGroup:new()
        btns.weight = 0
        do
            local btnNew = Button:new("New")
            btnNew.weight = 0
            self._original
                :sampledBy(EventStream:fromEvent(btnNew, "ui:Clicked"))
                :onValue(
                    function (orig)
                        self:_newCharacter(orig)
                    end)
            btns:addChild(btnNew)
        end
        do
            local btnDelete = Button:new("Delete...")
            btnDelete.weight  = 0
            btnDelete.enabled = false
            self._original
                :sampledBy(EventStream:fromEvent(btnDelete, "ui:Clicked"))
                :onValue(
                    function (orig)
                        self:_deleteCharacter(orig)
                    end)
            self._selectedChar:onValue(
                function (char)
                    btnDelete.enabled = not not char
                end)
            btns:addChild(btnDelete)
        end
        grp:addChild(btns)
    end
    do
        local tab = Tree:new(4)
        tab.header = TreeItem:new {
            TreeColumn:new "Pattern",
            TreeColumn:new "Track",
            TreeColumn:new "Colour",
            TreeColumn:new "Subtitles"
        }
        tab:sortByColumn(2, Tree.SortOrder.Ascending)
        -- We really want to resize columns automatically but the UITree
        -- widget doesn't appear to support Qt's resizeColumnToContents():
        -- https://doc.qt.io/qt-6/qtreeview.html#resizeColumnToContents
        tab.columnWidth[1] = 110
        tab.columnWidth[2] = 50
        tab.columnWidth[3] = 10
        -- The width of the last column is intentionally left out so that
        -- it takes all the remaining space. We'd also like to save widths
        -- to config when columns are resized, but there seems to be no
        -- events that are triggered when that happens.
        local function mkItem(char)
            local colColour = TreeColumn:new("■")
            colColour.colour.fg = COLOUR_OF[char.colour]
            local colSubs = TreeColumn:new(
                (char.usesPresetSubtitles and subPresets[char.subtitles].label)
                or char.subtitles
            )
            return TreeItem:new {
                TreeColumn:new(char.pattern.source),
                TreeColumn:new(char.portrait),
                colColour,
                colSubs,
            }
        end
        self._refreshTable:onValue(
            function (how)
                assert(HowToRefresh:made(how))
                how:match {
                    LoadAll = function ()
                        tab.sortingEnabled = false
                        for char in self._chars.map:values() do
                            tab:addItem(mkItem(char))
                        end
                        tab.sortingEnabled = true
                    end,
                    SelectChar = function (char)
                        local toSelect = nil -- TreeItem
                        for item in tab.items:values() do
                            if item.columns[2].text == char.portrait then
                                -- Can't select it right now, otherwise we
                                -- might select two items at the same time.
                                toSelect = item
                            else
                                item.selected = false
                            end
                        end
                        assert(toSelect)
                        toSelect.selected = true
                    end,
                    SelectNone = function ()
                        for item in tab.items:values() do
                            item.selected = false
                        end
                    end,
                    AddChar = function(char)
                        for item in tab.items:values() do
                            item.selected = false
                        end
                        local item = mkItem(char)
                        item.selected = true
                        tab:addItem(item)
                    end,
                    DeleteChar = function(char)
                        for idx, item in tab.items:entries() do
                            if item.columns[2].text == char.portrait then
                                tab:removeItemAt(idx)
                                break
                            end
                        end
                    end,
                    UpdateChar = function(old, new)
                        for item in tab.items:values() do
                            if item.columns[2].text == old.portrait then
                                local item1 = mkItem(new)
                                for i, col in item.columns:entries() do
                                    col:assign(item1.columns[i])
                                end
                                break
                            end
                        end
                    end
                }
            end)
        self._selectedCharBus:plug(
            EventStream:fromEvent(tab, "ui:ItemSelectionChanged"):map(
                function (_ev)
                    local items = tab.selectedItems
                    assert(items.length <= 1)
                    if items.length > 0 then
                        local track = items[1].columns[2].text
                        local char  = self._chars.map:get(track)
                        assert(char, "A character whose track name is \""..track.."\" must exist")
                        return char
                    else
                        return nil
                    end
                end))
        self._selectedCharBus
            :withLatestFrom(
                self._original,
                function (char, orig)
                    return Array:of(char, orig)
                end)
            :onValue(
                function (args)
                    local char, orig = args:unpack()

                    if not char then
                        -- No characters are selected. This can actually
                        -- happen when the "New" button is clicked.
                        return
                    end

                    if char.portrait == orig.portrait then
                        -- This means we are reverting the selection
                        -- change. Don't do anything further.
                        return
                    end

                    local proceed = self:_confirmDiscard(orig):await()
                    if proceed then
                        Promise:all {
                            self._originalBus:push(char),
                            self._refreshTable:push(HowToRefresh.SelectChar:new(char)),
                            self._fieldsEnabledBus:push(true)
                        }:await()
                    else
                        -- Discarding canceled. Select the character we
                        -- were selecting before this change.
                        self._refreshTable:push(HowToRefresh.SelectChar:new(orig)):await()
                    end
                end)
        grp:addChild(tab)
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
        self._fieldChanged:plug(
            EventStream:fromEvent(self._fldPattern, "ui:TextChanged"):map(fun.const()))
        self._original:onValue(
            function (orig)
                self._fldPattern.text = (orig.pattern or RegExp:new("")).source
            end)
        self._fieldsEnabled:onValue(
            function (b)
                self._fldPattern.enabled = b
            end)
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
                self._fieldChanged:plug(
                    EventStream:fromEvent(self._fldTrkPortrait, "ui:TextChanged"):map(fun.const()))
                self._original:onValue(
                    function (orig)
                        self._fldTrkPortrait.text = orig.portrait or ""
                    end)
                self._fieldsEnabled:onValue(
                    function (b)
                        self._fldTrkPortrait.enabled = b
                    end)
                col:addChild(self._fldTrkPortrait)
            end
            do
                local fldTrkSubtitles = LineEdit:new()
                fldTrkSubtitles.enabled = false
                self._fldTrkPortrait:on("ui:TextChanged", function ()
                    local track = self._fldTrkPortrait.text
                    if track == "" then
                        fldTrkSubtitles.text = ""
                    else
                        fldTrkSubtitles.text = track .. "_t"
                    end
                end)
                col:addChild(fldTrkSubtitles)
            end
            do
                local fldTrkVoices = LineEdit:new()
                fldTrkVoices.enabled = false
                self._fldTrkPortrait:on("ui:TextChanged", function ()
                    local track = self._fldTrkPortrait.text
                    if track == "" then
                        fldTrkVoices.text = ""
                    else
                        fldTrkVoices.text = track .. "_a"
                    end
                end)
                col:addChild(fldTrkVoices)
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
            self._selectedColourBus:plug(
                EventStream:fromEvent(self._cmbColour, "ui:CurrentIndexChanged"):map(
                    function (_ev)
                        local name = self._cmbColour.current.data
                        if name == "None" then
                            return nil
                        else
                            local colour = COLOUR_OF[name]
                            if colour then
                                return colour
                            else
                                console:warn("Unknown colour:", name)
                                console:trace()
                                return nil
                            end
                        end
                    end))
            self._original:onValue(
                function (orig)
                    if orig.colour then
                        -- + 1 is to skip "None"
                        self._cmbColour.current.index =
                            TimelineItem.CLIP_COLOURS:indexOf(orig.colour) + 1
                    else
                        self._cmbColour.current.index = 1 -- "None"
                    end
                end)
            self._fieldsEnabled:onValue(
                function (b)
                    self._cmbColour.enabled = b
                end)
            row:addChild(self._cmbColour)
        end
        do
            local labColour = Label:new("■")
            labColour.weight = 0
            self._selectedColour:onValue(
                function (colour)
                    labColour.style.color = colour
                end)
            row:addChild(labColour)
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
        self._fieldChanged:plug(
            EventStream:fromEvent(self._tabSubtitles, "ui:CurrentChanged"):map(fun.const()))
        self._original:onValue(
            function (orig)
                if orig.usesPresetSubtitles then
                    self._tabSubtitles.currentIndex = 1
                else
                    self._tabSubtitles.currentIndex = 2
                end
            end)
        self._fieldsEnabled:onValue(
            function (b)
                self._tabSubtitles.enabled = b
            end)
        grp:addChild(self._tabSubtitles)
    end
    do
        local stkSubtitles = Stack:new()
        stkSubtitles.weight = 0
        do
            self._cmbPresetSubs = ComboBox:new()
            self._cmbPresetSubs.enabled = false
            -- Sort presets by their labels.
            local ents = Array:of()
            for id, tab in pairs(subPresets) do
                ents:push {id = id, label = tab.label}
            end
            ents:sort(
                function (a, b)
                    if     a.label < b.label then return -1
                    elseif a.label > b.label then return  1
                    else                          return  0
                    end
                end)
            for ent in ents:values() do
                self._cmbPresetSubs:addItem(ent.label, ent.id)
            end
            self._fieldChanged:plug(
                EventStream:fromEvent(self._cmbPresetSubs, "ui:CurrentIndexChanged"):map(fun.const()))
            self._original:onValue(
                function (orig)
                    if orig.usesPresetSubtitles and orig.subtitles then
                        for i=1, self._cmbPresetSubs.size do
                            if self._cmbPresetSubs:getItem(i).data == orig.subtitles then
                                self._cmbPresetSubs.current.index = i
                                break
                            end
                        end
                    else
                        self._cmbPresetSubs.current.index = 1
                    end
                end)
            self._fieldsEnabled:onValue(
                function (b)
                    self._cmbPresetSubs.enabled = b
                end)
            stkSubtitles:addChild(self._cmbPresetSubs)
        end
        do
            local row = HGroup:new()
            do
                self._fldUserSubs = LineEdit:new()
                self._fldUserSubs.enabled  = false
                self._fldUserSubs.readOnly = true
                self._original:onValue(
                    function (orig)
                        if orig.usesPresetSubtitles then
                            self._fldUserSubs.text = ""
                        else
                            self._fldUserSubs.text = orig.subtitles or ""
                        end
                    end)
                self._fieldsEnabled:onValue(
                    function (b)
                        self._fldUserSubs.enabled = b
                    end)
                row:addChild(self._fldUserSubs)
            end
            do
                local btnChooseUserSubs = Button:new("...")
                btnChooseUserSubs.weight = 0
                btnChooseUserSubs.enabled = false
                btnChooseUserSubs.style.padding = "5px";
                btnChooseUserSubs:on("ui:Clicked", function() self:_chooseUserSubs() end)
                self._fieldsEnabled:onValue(
                    function (b)
                        btnChooseUserSubs.enabled = b
                    end)
                row:addChild(btnChooseUserSubs)
            end
            stkSubtitles:addChild(row)
        end
        self._tabSubtitles:on("ui:CurrentChanged", function ()
            stkSubtitles.currentIndex = self._tabSubtitles.currentIndex
        end)
        -- Workaround for a possible Resolve bug. Widgets that are supposed
        -- to be hidden are still rendered, unless we change the current
        -- index of UIStack. THINKME: Remove this when it's fixed.
        self:on("ui:Show", function ()
            stkSubtitles.currentIndex = 2
            stkSubtitles.currentIndex = 1
        end, {oneShot = true})
        grp:addChild(stkSubtitles)
        grp:addChild(VGap:new(gap))
    end
    do
        local labErrors = Label:new("")
        labErrors.weight             = 0
        labErrors.alignment.vertical = "top"
        labErrors.style.color        = "red"
        labErrors.style.minHeight    = "5ex" -- approx. 2 lines
        labErrors.wordWrap           = true
        self._original:sampledBy(self._fieldChanged):onValue(
            function (orig)
                if self:_isDirty(orig) then
                    labErrors.text = self:_validate(orig) or ""
                else
                    labErrors.text = ""
                end
            end)
        grp:addChild(labErrors)
    end
    do
        local buttons = HGroup:new()
        buttons.weight = 0
        buttons:addChild(Spacer:new())
        do
            local btnDiscard = Button:new("Discard...")
            btnDiscard.weight = 0
            self._original
                :sampledBy(EventStream:fromEvent(btnDiscard, "ui:Clicked"))
                :onValue(
                    function (orig)
                        local proceed = self:_confirmDiscard(orig):await()
                        if proceed then
                            Promise:all {
                                self._originalBus:push(orig),
                                self._fieldsEnabledBus:push(not orig.isEmpty)
                            }:await()
                        end
                    end)
            self._original:sampledBy(self._fieldChanged):onValue(
                function (orig)
                    btnDiscard.enabled = self:_isDirty(orig)
                end)
            buttons:addChild(btnDiscard)
        end
        do
            local btnSave = Button:new("Save")
            btnSave.weight = 0
            self._original
                :sampledBy(EventStream:fromEvent(btnSave, "ui:Clicked"))
                :onValue(
                    function (orig)
                        self:_saveCharacter(orig)
                    end)
            self._original:sampledBy(self._fieldChanged):onValue(
                function (orig)
                    if self:_isDirty(orig) then
                        btnSave.enabled = not self:_validate(orig)
                    else
                        btnSave.enabled = false
                    end
                end)
            buttons:addChild(btnSave)
        end
        grp:addChild(buttons)
    end
    return grp
end

-- Return Promise<bool>: true if we can proceed, false otherwise. The
-- promise is supposed to be never rejected.
function CharConfWindow:_confirmDiscard(orig)
    assert(self._chars.Character:made(orig))

    local msg
    if self:_isDirty(orig) then
        if orig.isEmpty then
            msg = "The character being added has not been saved. Do you want to discard it?"
        else
            msg = "The character being edited has not been saved. Do you want to discard changes?"
        end
    end

    if msg then
        return modal.confirm(msg, {defaultButton = "Discard"})
            :then_(true, false)
    else
        return Promise:resolve(true)
    end
end

function CharConfWindow:_newCharacter(orig)
    assert(self._chars.Character:made(orig))

    local proceed = self:_confirmDiscard(orig):await()
    if proceed then
        Promise:all {
            self._originalBus:push(nil),
            self._refreshTable:push(HowToRefresh.SelectNone:new()),
            self._fieldsEnabledBus:push(true)
        }:await()
    end
end

function CharConfWindow:_deleteCharacter(orig)
    assert(self._chars.Character:made(orig))

    -- This string is only for displaying purpose.
    local portrait = self._fldTrkPortrait.text
    if portrait == "" then
        portrait = orig.portrait
    end

    local msg = string.format(
        "Are you sure you want to delete the character `%s'?", portrait)

    if self:_isDirty(orig) then
        msg = msg .. "\nIt's also being edited and has not been saved."
    end

    local proceed = modal.confirm(msg, {defaultButton = "Delete"})
        :then_(true, false)
        :await()

    if proceed then
        self._chars.map:delete(orig.portrait)
        self._chars:save()

        Promise:all {
            self._originalBus:push(nil),
            self._refreshTable:push(HowToRefresh.DeleteChar:new(orig)),
            self._fieldsEnabledBus:push(false),
            self._classifierUpdated:push()
        }:await()
    end
end

function CharConfWindow:_saveCharacter(orig)
    assert(self._chars.Character:made(orig))

    local subs
    if self._tabSubtitles.currentIndex == 1 then
        subs = self._cmbPresetSubs.current.data
    else
        subs = self._fldUserSubs.text
    end

    local colour = nil
    if self._cmbColour.current.data ~= "None" then
        colour = self._cmbColour.current.data
    end

    local char = self._chars.Character:new {
        pattern   = RegExp:new(self._fldPattern.text),
        portrait  = self._fldTrkPortrait.text,
        colour    = colour,
        subtitles = subs
    }
    if orig.portrait then
        -- Delete the entry first, because the track name might have been
        -- changed.
        self._chars.map:delete(orig.portrait)
    end
    self._chars.map:put(char)
    self._chars:save()

    local refreshP
    if orig.portrait then
        refreshP = self._refreshTable:push(HowToRefresh.UpdateChar:new(orig, char))
    else
        refreshP = self._refreshTable:push(HowToRefresh.AddChar:new(char))
    end
    Promise:all {
        self._originalBus:push(char),
        refreshP,
        self._fieldChanged:push(),
        self._classifierUpdated:push()
    }:await()
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
        self._fieldChanged:push():await()

        self._chars.lastChosenUserSubs = absPath
        self._chars:save()
    end
end

function CharConfWindow:_isDirty(orig)
    assert(self._chars.Character:made(orig))

    -- See if any of the fields have different values from the original
    -- state.
    if self._fldPattern.text ~= (orig.pattern or RegExp:new("")).source or
        self._fldTrkPortrait.text ~= (orig.portrait or "") or
        self._cmbColour.current.data ~= (orig.colour or "None") then
        return true
    end
    -- Subtitles setting is a tricky one...
    if orig.usesPresetSubtitles then
        if self._tabSubtitles.currentIndex ~= 1 then
            return true
        end

        if orig.subtitles then
            if self._cmbPresetSubs.current.data ~= orig.subtitles then
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

        assert(orig.subtitles,
               "It has to have a path to subtitles setting given that it uses a user-defined one")
        if self._fldUserSubs.text ~= orig.subtitles then
            return true
        end
    end
    return false
end

-- Return a message string if any of the fields have invalid values, or nil
-- otherwise.
function CharConfWindow:_validate(orig)
    assert(self._chars.Character:made(orig))

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
    local track = self._fldTrkPortrait.text
    if track == "" then
        return "Track name for portrait cannot be empty."
    elseif track ~= orig.portrait and self._chars.map:has(track) then
        return string.format("Track name `%s' is already in use.", track)
    end
    if self._tabSubtitles.currentIndex == 2 and self._fldUserSubs.text == "" then
        return "User-defined subtitles setting has not been chosen."
    end
end

return CharConfWindow
