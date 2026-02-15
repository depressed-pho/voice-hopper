local Set      = require("collection/set")
local TreeItem = require("widget/tree/item")
local Widget   = require("widget")
local class    = require("class")
local enum     = require("enum")
local ui       = require("ui")

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
-- The Tree widget is like a Container but only accepts TreeItem as its
-- children. It is a strange amalgamation of QTreeView
-- (https://doc.qt.io/qt-6/qtreeview.html) and QTreeWidget
-- (https://doc.qt.io/qt-6/qtreewidget.html).
--
local Tree = class("Tree", Widget)

Tree.SelectionBehaviour = SelectionBehaviour
Tree.SelectionMode      = SelectionMode

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
    }
    super(events)
    self._numCols  = numCols
    self._header   = nil         -- TreeItem or nil
    self._items    = items or {} -- {TreeItem, ...}
    self._selB     = SelectionBehaviour.Rows
    self._selM     = SelectionMode.Single
    self._indent   = nil         -- number or nil
    self._wordWrap = false       -- boolean
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

function Tree:addItem(item)
    assert(TreeItem:made(item), "Tree#addItem() expects a TreeItem")

    table.insert(self._items, item)
    if self.materialised then
        self.raw:AddTopLevelItem(item:materialise(self))
    end
    return self
end

function Tree:clear()
    self._items = {}
    if self.materialised then
        self.raw:Clear()
    end
    return self
end

function Tree:materialise()
    local props = self:commonProps()
    props.ColumnCount       = self._numCols
    props.SelectionBehavior = NATIVE_SB_FOR[self._selB]
    props.SelectionMode     = NATIVE_SM_FOR[self._selM]
    if self._indent then
        props.Indentation = self._indent
    end
    props.WordWrap = self._wordWrap

    local raw      = ui.manager:Tree(props)
    local rawItems = {}
    for i, item in ipairs(self._items) do
        rawItems[i] = item:materialise(raw)
    end
    raw:AddTopLevelItems(rawItems)

    if self._header then
        raw:SetHeaderItem(self._header:materialise(raw))
        raw.HeaderHidden = false
    else
        raw.HeaderHidden = true
    end

    return raw
end

return Tree
