local Set      = require("collection/set")
local TreeItem = require("widget/tree/item")
local Widget   = require("widget")
local class    = require("class")
local ui       = require("ui")

--
-- The Tree widget is like a Container but only accepts TreeItem as its
-- children. It is a strange amalgamation of QTreeView
-- (https://doc.qt.io/qt-6/qtreeview.html) and QTreeWidget
-- (https://doc.qt.io/qt-6/qtreewidget.html).
--
local Tree = class("Tree", Widget)

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
    self._numCols = numCols
    self._header  = nil         -- TreeItem or nil
    self._items   = items or {} -- {TreeItem, ...}
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

function Tree:addItem(item)
    assert(TreeItem:made(item), "Tree#addItem() expects a TreeItem")

    table.insert(self._items, item)
    if self.materialised then
        self.raw:AddTopLevelItem(item:materialise(self))
    end
    return self
end

function Tree:materialise()
    local props = self:commonProps()
    props.ColumnCount = self._numCols

    local raw      = ui.manager:Tree(props)
    local rawItems = {}
    for i, item in ipairs(self._items) do
        rawItems[i] = item:materialise(self)
    end
    raw:AddTopLevelItems(rawItems)

    if self._header then
        raw:SetHeaderItem(self._header:materialise(self))
        raw.HeaderHidden = false
    else
        raw.HeaderHidden = true
    end

    return raw
end

return Tree
