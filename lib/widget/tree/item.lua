local Array      = require("collection/array")
local TreeColumn = require("widget/tree/column")
local class      = require("class")

--
-- TreeItem corresponds to UITreeItem, which does *not* derive Widget.
--
local TreeItem = class("TreeItem")

function TreeItem:__init(cols)
    assert(cols == nil or Array:made(cols) or (type(cols) == "table" and getmetatable(cols) == nil),
           "TreeItem:new() expects an optional array or a sequence of TreeColumn")

    if Array:made(cols) then
        self._cols = cols
    else
        self._cols = Array:from(cols or {})
    end
    self._children = {}  -- {TreeItem, ...}
    self._tree     = nil -- UITree
    self._raw      = nil -- UITextItem
    self._selected = false

    for i, col in self._cols:entries() do
        assert(TreeColumn:made(col),
               string.format("The column #%d is not a TreeColumn: %s", i, col))
    end
end

--
-- TreeItem#cols is a non-live Array of columns of a TreeItem.
--
function TreeItem.__getter:cols()
    return self._cols:clone()
end

-- Private; only Tree can call this method.
function TreeItem.__getter:tree()
    if not self._tree then
        error("This TreeItem object has not been materialised yet", 2)
    end
    return self._tree
end

-- Private; only Tree can call this method.
function TreeItem.__getter:raw()
    if not self._raw then
        error("This TreeItem object has not been materialised yet", 2)
    end
    return self._raw
end

function TreeItem.__getter:selected()
    if self._raw then
        return self.raw.Selected
    else
        return self._selected
    end
end
function TreeItem.__setter:selected(b)
    assert(type(b) == "boolean", "TreeItem#selected is expected to be a boolean")
    self._selected = b
    if self._raw then
        self.raw.Selected = b
    end
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

    -- Setting self._raw.Selected here doesn't seem to have any effect.
    -- Tree#addItem() will have to do it after adding the item to the tree.

    return self._raw
end

return TreeItem
