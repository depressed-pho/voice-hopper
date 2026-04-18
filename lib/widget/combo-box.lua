local Array  = require("collection/array")
local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

-- private
local ComboBoxItem = class("ComboBoxItem")

function ComboBoxItem:__init()
    self._combo = nil -- UIComboBox
    self._index = nil -- 0-origin
end

function ComboBoxItem:assignRaw(combo, index)
    if self._combo then
        error("This ComboBoxItem object has already been assigned a raw UIComboBox", 2)
    end
    self._combo = combo
    self._index = index
end

-- private
local TextItem = class("TextItem", ComboBoxItem)

function TextItem:__init(label, data)
    self._label = label -- string
    self._data  = data  -- any (or nil)
end

function TextItem.__getter:label()
    return self._label
end
function TextItem.__setter:label(label)
    assert(type(label) == "string", "TextItem#label is expected to be a string")
    self._label = label
    if self._combo then
        self._combo.ItemText[self._index] = label
    end
end

function TextItem.__getter:data()
    return self._data
end
function TextItem.__setter:data(data)
    self._data = data
end

--
-- The ComboBox widget which corresponds to UIComboBox.
--
local ComboBox = class("ComboBox", Widget)

function ComboBox:__init()
    local events = Set:new {
        "ui:CurrentIndexChanged", "ui:CurrentTextChanged", "ui:TextEdited", "ui:EditTextChanged",
        "ui:EditingFinished", "ui:ReturnPressed", "ui:Activated"
    }
    super(events)

    -- FIXME: Editable combo boxes are currently unsupported.
    -- FIXME: Separators are currently unsupported.

    self._items        = Array:new() -- Array of ComboBoxItem
    self._currentIndex = 1
end

--
-- ComboBox#size is the number of items in the combo box.
--
function ComboBox.__getter:size()
    return self._items.length
end

--
-- ComboBox#current is a live table with the following entries:
--
--   * index: 1-origin index of the selected item.
--   * label: The label text of the selected item.
--   * data:  The associated data of the selected item, possibly nil.
--
-- All properties are nil if no items are selected. This can only happen
-- when the combo box has no items.
--
function ComboBox.__getter:current()
    if self._curCache == nil then
        local function getIndex()
            if self.materialised then
                return self.raw.CurrentIndex + 1 -- 0-origin
            else
                return self._currentIndex
            end
        end
        self._curCache = setmetatable(
            {},
            {
                __index = function(_self, key)
                    local idx  = getIndex()
                    local item = self._items[idx]

                    if key == "index" then
                        return (item and idx) or nil

                    elseif key == "label" then
                        return (item and item.label) or nil

                    elseif key == "data" then
                        return (item and item.data) or nil

                    else
                        error("No such key exists in ComboBox#current: " .. tostring(key), 2)
                    end
                end,
                __newindex = function(_self, key, value)
                    if key == "index" then
                        assert(type(value) == "number" and math.floor(value) == value and value > 0,
                               "ComboBox#current.value is expected to be a positive integer")
                        assert(value <= self._items.length,
                               "index out of range: " .. tostring(value))
                        if self.materialised then
                            self.raw.CurrentIndex = value - 1
                        else
                            self._currentIndex = value
                        end

                    elseif key == "label" then
                        assert(type(value) == "string",
                               "ComboBox#current.label is expected to be a string")
                        local idx  = getIndex()
                        local item = self._items[idx]

                        item.label = value

                    elseif key == "data" then
                        local idx  = getIndex()
                        local item = self._items[idx]

                        item.data = value

                    else
                        error("No such key exists in ComboBox#current: " .. tostring(key), 2)
                    end
                end
            })
    end
    return self._curCache
end

function ComboBox:addItem(label, data)
    assert(type(label) == "string", "ComboBox#addItem() expects a label string as its 1st argument")

    local item = TextItem:new(label, data)
    self._items:push(item)

    if self.materialised then
        item.assignRaw(self.raw, self._items.length - 1)
        self.raw:AddItem(label)
    end
end

function ComboBox:getItem(index)
    return self._items[index]
end

function ComboBox:materialise()
    local props = self:commonProps()
    props.CurrentIndex = self._currentIndex - 1 -- 0-origin

    local raw = ui.manager:ComboBox(props)
    for idx, item in self._items:entries() do
        item.assignRaw(raw, idx - 1)

        if TextItem:made(item) then
            raw:AddItem(item.label)
        else
            -- FIXME: separator
        end
    end
    return raw
end

return ComboBox
