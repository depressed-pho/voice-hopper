local Array  = require("collection/array")
local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

-- private
local ComboBoxItem = class("ComboBoxItem")

-- private
local TextItem = class("TextItem", ComboBoxItem)
function TextItem:__init(label, data)
    self.label = label -- string
    self.data  = data  -- any (or nil)
end

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
                end
            })
    end
    return self._curCache
end

function ComboBox:addItem(label, data)
    assert(type(label) == "string", "ComboBox#addItem() expects a label string as its 1st argument")
    self._items:push(TextItem:new(label, data))
    if self.materialised then
        self.raw:AddItem(label)
    end
end

function ComboBox:materialise()
    local props = self:commonProps()
    props.CurrentIndex = self._currentIndex - 1 -- 0-origin

    local raw   = ui.manager:ComboBox(props)
    for item in self._items:values() do
        if TextItem:made(item) then
            raw:AddItem(item.label)
        else
            -- FIXME: separator
        end
    end
    return raw
end

return ComboBox
