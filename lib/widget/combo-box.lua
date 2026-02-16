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

    self._items = Array:new() -- Array of ComboBoxItem
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
