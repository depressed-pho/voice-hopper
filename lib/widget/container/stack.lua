local Container = require("widget/container")
local class     = require("class")
local ui        = require("ui")

--
-- The undocumented UIStack which seemingly is based on QStackWidget. We
-- have UITabBar but no widgets corresponding to QTabWidget so this appears
-- to be the only way to implement tabbed panes.
--
-- There's a caveat though. When a window is shown, UIStack is incorrectly
-- rendered until its currentIndex changed. This is most likely a Resolve
-- bug.
--
local Stack = class("Stack", Container)

function Stack:__init(...)
    super(...)
    self._currentIndex = 1
end

function Stack.__getter:currentIndex()
    return self._currentIndex
end
function Stack.__setter:currentIndex(index)
    assert(type(index) == "number" and math.floor(index) == index, "Stack#currentIndex is expected to be an integer")

    if index < 1 or index > #self.children then
        error("Index out of bounds: " .. tostring(index), 2)
    end

    self._currentIndex = index

    if self.materialised then
        self.raw.CurrentIndex = index - 1 -- 0-origin
    end
end

function Stack:materialise()
    local props = self:commonProps()
    props.CurrentIndex = self._currentIndex - 1 -- 0-origin

    local raws = {}
    for i, child in ipairs(self.children) do
        raws[i] = child.raw
    end

    return ui.manager:Stack(props, raws)
end

return Stack
