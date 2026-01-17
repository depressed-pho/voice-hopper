local Array      = require("collection/array")
local TreeColumn = require("widget/tree/column")
local class      = require("class")

--
-- TreeItem corresponds to UITreeItem, which does *not* derive Widget.
--
local TreeItem = class("TreeItem")

function TreeItem:__init(cols)
    assert(cols == nil or type(cols) == "table" or Array:has(cols),
           "TreeItem:new() expects an optional array or a sequence of TreeColumn")

    if Array:made(cols) then
        self._cols = cols
    else
        self._cols = Array:from(cols or {})
    end
    self._tree = nil -- Tree
    self._raw  = nil -- UITextItem

    for i, col in self._cols:entries() do
        assert(TreeColumn:made(col),
               string.format("The column #%d is not a TreeColumn: %s", i, col))
    end
end

--
-- TreeItem#cols is a sequence of columns of a TreeItem.
--
function TreeItem.__getter:cols()
    return self._cols
end

function TreeItem.__getter:raw()
    if not self._raw then
        error("This TreeItem object has not been materialised yet", 2)
    end
    return self._raw
end

-- Private; only Tree can call this method.
function TreeItem:materialise(tree)
    if self._raw then
        if self._tree == tree then
            -- Do nothing and return. It's the same tree.
            return
        else
            error("This TreeItem object has already been materialised", 2)
        end
    end

    self._tree = tree
    self._raw  = tree.raw:NewItem()
    for i, col in self._cols:entries() do
        col:populate(self, i - 1) -- 0-indexed
    end
    return self._raw
end

return TreeItem
