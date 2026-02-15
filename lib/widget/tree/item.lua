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
    self._children = {}  -- {TreeItem, ...}
    self._tree     = nil -- UITree
    self._raw      = nil -- UITextItem

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

--
-- Add a child item to this item.
--
function TreeItem:addChild(child)
    assert(TreeItem:made(child), "TreeItem#addChild() expects a TreeItem")
    table.insert(self._children, child)
    if self._raw then
        self._raw:AddChild(child:materialise(self._tree))
    end
    return self
end

-- Private; only Tree can call this method.
function TreeItem:materialise(rawTree)
    if self._raw then
        if self._tree == rawTree then
            -- Do nothing and return. It's the same tree.
            return
        else
            error("This TreeItem object has already been materialised", 2)
        end
    end

    self._tree = rawTree
    self._raw  = rawTree:NewItem()
    for i, col in self._cols:entries() do
        col:populate(self._raw, i - 1) -- 0-indexed
    end

    for _i, child in ipairs(self._children) do
        self._raw:AddChild(child:materialise(self._tree))
    end

    return self._raw
end

return TreeItem
