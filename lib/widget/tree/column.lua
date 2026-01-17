local class = require("class")

--
-- A column of a TreeItem. There is no corresponding class in the native UI
-- toolkit.
--
local TreeColumn = class("TreeColumn")

function TreeColumn:__init(text)
    assert(text == nil or type(text) == "string",
           "TreeColumn:new() expects an optional string text")
    self._text = text or ""
    self._item = nil -- TreeItem
    self._idx  = nil -- number
end

-- Private; only TreeItem can call this method.
function TreeColumn:populate(item, idx)
    if self._item then
        error("This TreeColumn object has already populated a TreeItem", 2)
    end

    self._item = item
    self._idx  = idx  -- 0-indexed

    self._item.raw.Text[self._idx] = self._text
    -- FIXME: populate other fields...
end

return TreeColumn
