require("shim/table")
local Array           = require("collection/array")
local ReflectiveArray = require("collection/array/reflective")
local Map             = require("collection/map")
local Set             = require("collection/set")
local TreeItem        = require("widget/tree/item")
local Widget          = require("widget")
local class           = require("class")
local enum            = require("enum")
local ui              = require("ui")

--
-- Selection behaviour:
-- https://doc.qt.io/qt-6/qabstractitemview.html#SelectionBehavior-enum
--
local SelectionBehaviour = enum {
    "Cells",  -- Each cell can be selected individually.
    "Rows",   -- Only rows can be selected.
    "Columns" -- Only columns can be selected.
}
local NATIVE_SB_FOR = {
    [SelectionBehaviour.Cells  ] = "SelectItems",
    [SelectionBehaviour.Rows   ] = "SelectRows",
    [SelectionBehaviour.Columns] = "SelectColumns"
}

--
-- Selection mode:
-- https://doc.qt.io/qt-6/qabstractitemview.html#SelectionMode-enum
--
local SelectionMode = enum {
    "Single",
    "Contiguous",
    "Extended",
    "Multi",
    "None"
}
local NATIVE_SM_FOR = {
    [SelectionMode.Single    ] = "SingleSelection",
    [SelectionMode.Contiguous] = "ContiguousSelection",
    [SelectionMode.Extended  ] = "ExtendedSelection",
    [SelectionMode.Multi     ] = "MultiSelection",
    [SelectionMode.None      ] = "NoSelection"
}

--
-- Sort order:
-- https://doc.qt.io/qt-6/qt.html#SortOrder-enum
--
local SortOrder = enum {
    "Ascending",
    "Descending"
}
local NATIVE_SO_FOR = {
    [SortOrder.Ascending ] = "AscendingOrder",
    [SortOrder.Descending] = "DescendingOrder"
}

--
-- The Tree widget is like a Container but only accepts TreeItem as its
-- children. It is a strange amalgamation of QTreeView
-- (https://doc.qt.io/qt-6/qtreeview.html) and QTreeWidget
-- (https://doc.qt.io/qt-6/qtreewidget.html).
--
local Tree = class("Tree", Widget)

Tree.SelectionBehaviour = SelectionBehaviour
Tree.SelectionMode      = SelectionMode
Tree.SortOrder          = SortOrder

function Tree:__init(numCols, items)
    assert(type(numCols) == "number" and numCols == math.floor(numCols) and numCols >= 0,
           "Tree:new() expects the number of columns as its 1st argument")
    assert(items == nil or type(items) == "table",
           "Tree:new() expects an optional list of TreeItem")

    if items then
        for i, item in ipairs(items) do
            assert(TreeItem:made(item),
                   string.format("The item #%d is not a TreeItem: %s", i, item))
        end
    end

    local events = Set:new {
        "ui:CurrentItemChanged", "ui:ItemClicked", "ui:ItemPressed",
        "ui:ItemActivated", "ui:ItemDoubleClicked", "ui:ItemChanged",
        "ui:ItemEntered", "ui:ItemExpanded", "ui:ItemCollapsed",
        "ui:CurrentItemChanged", "ui:ItemSelectionChanged"
        -- THINKME: README.txt lists CurrentItemChanged twice. Maybe
        -- there's an unknown event?
    }
    super(events)
    self._numCols   = numCols
    self._header    = nil         -- TreeItem|nil
    self._items     = Array:from(items or {}) -- [TreeItem, ...]
    self._itemFor   = Map:new()   -- Map<UITreeItem, TreeItem>
    self._selB      = SelectionBehaviour.Rows
    self._selM      = SelectionMode.Single
    self._sort      = false       -- boolean
    self._sortBy    = nil         -- {integer, SortOrder}|nil
    self._indent    = 0           -- number|nil
    self._wordWrap  = false       -- boolean
    self._colWidths = Array:new() -- [number|nil, ...]
end

function Tree.__getter:header()
    return self._header
end
function Tree.__setter:header(item)
    assert(item == nil or TreeItem:made(item), "Tree#header expects a TreeItem")

    self._header = item
    if self.materialised then
        if item then
            self.raw:SetHeaderItem(item:materialise(self))
            self.raw.HeaderHidden = false
        else
            self.raw.HeaderHidden = true
        end
    end
end

function Tree.__getter:selectionBehaviour()
    return self._selB
end
function Tree.__setter:selectionBehaviour(sb)
    assert(SelectionBehaviour:has(sb), "Tree#selectionBehaviour expects a Tree.SelectionBehaviour")
    self._selB = sb
    if self.materialised then
        self.raw.SelectionBehavior = NATIVE_SB_FOR[sb]
    end
end

function Tree.__getter:selectionMode()
    return self._selM
end
function Tree.__setter:selectionMode(sm)
    assert(SelectionMode:has(sm), "Tree#selectionMode expects a Tree.SelectionMode")
    self._selM = sm
    if self.materialised then
        self.raw.SelectionMode = NATIVE_SM_FOR[sm]
    end
end

function Tree.__getter:sortingEnabled()
    return self._sort
end
function Tree.__setter:sortingEnabled(bool)
    assert(type(bool) == "boolean", "Tree#sortingEnabled expects a boolean")
    self._sort = bool
    if self.materialised then
        self.raw.SortingEnabled = bool
    end
end

function Tree.__getter:indent()
    return self._indent
end
function Tree.__setter:indent(indent)
    assert(indent == nil or type(indent) == "number", "Tree#indent expects an optional number")
    self._indent = indent
    if self.materialised then
        if indent then
            self.raw.Indentation = indent
        else
            self.raw:ResetIndentation()
        end
    end
end

--
-- But this does nothing. What the heck. It is a documented feature
-- (https://doc.qt.io/qt-6/qtreeview.html#wordWrap-prop) yet it does
-- nothing actually. StackOverflow has tons of guides of weird hacks (and
-- complaints ofc) involving delegation to circumvent this bug, which is
-- impossible for us to achieve within the capability of UIManager.
--
function Tree.__getter:wordWrap()
    return self._wordWrap
end
function Tree.__setter:wordWrap(enabled)
    assert(type(enabled) == "boolean", "Tree#wordWrap expects a boolean")
    self._wordWrap = enabled
    if self.materialised then
        self.raw.WordWrap = enabled
    end
end

--
-- This is a read-only live array of top-level TreeItem objects in the tree.
--
function Tree.__getter:items()
    return ReflectiveArray:new(self._items)
end

--
-- This is a non-live Array of TreeItem objects that are currently selected.
-- THINKME: Consider turning this into a live array.
--
function Tree.__getter:selectedItems()
    if self.materialised then
        local seq = self.raw:SelectedItems() -- sequence of UITreeItem
        local ret = Array:new()
        for _i, rawItem in ipairs(seq) do
            ret:push(self:_findItemForRaw(rawItem))
        end
        return ret
    else
        error("Tree#selectedItems can only be inspected after materialisation", 2)
    end
end
-- We need to find our TreeItem object that corresponds to this UITreeItem,
-- but it's not easy to do. It might be a top-level item, or might be a
-- child of some item.
function Tree:_findItemForRaw(rawItem)
    local rawParent = rawItem:Parent()
    if rawParent then
        local parent = self:_findItemForRaw(rawParent)
        return parent:findChildForRaw(rawItem)
    else
        local item = self._itemFor:get(rawItem)
        assert(item, "No TreeItem corresponds to "..tostring(rawItem))
        return item
    end
end

--
-- This is a live sequence that reflects widths of columns. Getting a width
-- may result in nil until the tree is materialised.
--
function Tree.__getter:columnWidth()
    if self._widthsCache == nil then
        self._widthsCache = setmetatable(
            {},
            {
                __index = function(_tab, key)
                    assert(
                        type(key) == "number" and math.floor(key) == key,
                        tostring(key).." is expected to be an integer")
                    assert(
                        key >= 1 and key <= self._numCols,
                        "index out of range: "..tostring(key))
                    if self.materialised then
                        return self.raw.ColumnWidth[key - 1] -- 0-origin
                    else
                        return self._colWidths[key]
                    end
                end,
                __newindex = function(_tab, key, val)
                    assert(
                        type(key) == "number" and math.floor(key) == key,
                        tostring(key).." is expected to be an integer")
                    assert(
                        key >= 1 and key <= self._numCols,
                        "index out of range: "..tostring(key))
                    assert(
                        type(val) == "number" and val >= 0,
                        tostring(val).." is expected to be a non-negative number")
                    if self.materialised then
                        self.raw.ColumnWidth[key - 1] = val -- 0-origin
                    else
                        self._colWidths[key] = val
                    end
                end
            })
    end
    return self._widthsCache
end

function Tree:addItem(item)
    assert(TreeItem:made(item), "Tree#addItem() expects a TreeItem")

    self._items:push(item)
    if self.materialised then
        -- UITreeItem#Selected will be cleared when it's added to a
        -- UITree. See a comment in TreeItem#materialise().
        local selected = item.selected
        local rawItem  = item:materialise(self.raw)

        self.raw:AddTopLevelItem(rawItem)
        self._itemFor:set(rawItem, item)

        if selected then
            item.selected = true
        end
    end
    return self
end

function Tree:removeItemAt(idx)
    assert(type(idx) == "number" and math.floor(idx) == idx and idx > 0,
           "Tree#removeItemAt() expects a positive index")

    local item = self._items:splice(idx, 1)[1]

    if self.materialised then
        local rawIdx = self.raw:IndexOfTopLevelItem(item.raw)
        assert(rawIdx)
        self.raw:TakeTopLevelItem(rawIdx)
    end
end

function Tree:clear()
    self._items.length = 0
    self._itemFor:clear()
    if self.materialised then
        self.raw:Clear()
    end
    return self
end

function Tree:scrollTo(item)
    assert(TreeItem:made(item),
           "Tree#scrollTo() expects an instance of TreeItem")

    if self.materialised then
        if item.tree ~= self.raw then
            error("This TreeItem does not belong to the tree: "..tostring(item), 2)
        end
        self.raw:ScrollToItem(item.raw)
    end
end

function Tree:sortByColumn(idx, order)
    assert(type(idx) == "number" and math.floor(idx) == idx and idx > 0,
           "Tree#sortByColumn() expects a positive column index as its 1st argument")
    assert(SortOrder:has(order),
           "Tree#sortByColumn() expects a Tree.SortOrder as its 2nd argument")

    if idx > self._numCols then
        error("Column index out of bounds: " .. tostring(idx), 2)
    end

    self._sort   = true
    self._sortBy = {idx, order}

    if self.materialised then
        self.raw.SortingEnabled = true
        self.raw:SortByColumn(idx - 1, NATIVE_SO_FOR[order]) -- 0-origin
    end
end

function Tree:materialise()
    local props = self:commonProps()
    props.ColumnCount       = self._numCols
    props.SelectionBehavior = NATIVE_SB_FOR[self._selB]
    props.SelectionMode     = NATIVE_SM_FOR[self._selM]
    props.SortingEnabled    = self._sort
    if self._indent then
        props.Indentation = self._indent
    end
    props.WordWrap = self._wordWrap

    local raw      = ui.manager:Tree(props)
    local rawItems = {}
    for i, item in self._items:entries() do
        rawItems[i] = item:materialise(raw)
        self._itemFor:set(rawItems[i], item)
    end
    raw:AddTopLevelItems(rawItems)

    if self._header then
        raw:SetHeaderItem(self._header:materialise(raw))
        raw.HeaderHidden = false
    else
        raw.HeaderHidden = true
    end

    for i, width in self._colWidths:entries() do
        raw.ColumnWidth[i - 1] = width -- 0-origin
    end

    if self._sortBy then
        -- There are no properties for this.
        -- luacheck: read_globals table.unpack
        local idx, order = table.unpack(self._sortBy)
        raw:SortByColumn(idx - 1, NATIVE_SO_FOR[order]) -- 0-origin
    end

    return raw
end

return Tree
