local Container = require("widget/container")
local class     = require("class")
local ui        = require("ui")

local Window = class("Window", Container)
Window._shown = setmetatable({}, {__mode = "k"}) -- Window => true

function Window:__init(children)
    super(children)
    self._title    = nil
    self._geometry = nil
    self._type     = "regular"

    -- Install a default Close handler as a safety measure. Without this
    -- the user won't be able to terminate the "fuscript" process
    -- gracefully.
    local function defaultOnClose()
        -- If this is the last visible window, we should tear down the
        -- entire event loop.
        local foundOther = false
        for win in pairs(Window._shown) do
            if win ~= self then
                foundOther = true
                break
            end
        end
        if foundOther then
            self.close()
        else
            ui.dispatcher:ExitLoop()
        end
    end
    self:on("Close", defaultOnClose)
end

function Window.__getter:title()
    return self._title
end
function Window.__setter:title(title)
    assert(type(title) == "string", "Window:setTitle() expects a string title")
    self._title = title
end

function Window.__getter:type()
    return self._type
end
function Window.__setter:type(typ)
    assert(typ == "regular" or typ == "floating")
    self._type = typ
    return self
end

function Window:setGeometry(x, y, width, height)
    assert(type(x     ) == "number", "Window:setGeometry() expects 4 numbers")
    assert(type(y     ) == "number", "Window:setGeometry() expects 4 numbers")
    assert(type(width ) == "number", "Window:setGeometry() expects 4 numbers")
    assert(type(height) == "number", "Window:setGeometry() expects 4 numbers")
    self._geometry = {x, y, width, height}
    return self
end

function Window:materialise()
    if #self.children == 0 then
        -- Attempting to create an empty window causes DaVinci Resolve
        -- to crash.
        error("The window has no children. Add something before showing it", 2)
    end

    local props = {
        ID = self.id
    }
    if self._title ~= nil then
        props.WindowTitle = self._title
    end
    if self._geometry then
        props.Geometry = self._geometry
    end

    if self._type == "regular" then
        props.WindowFlags = {
            Window = true,
            WindowStaysOnTopHint = false,
        }
    elseif self._type == "floating" then
        -- Giving no window flags seems to make it behave like the console
        -- window. Why? I don't know, because there's absolutely no
        -- documentation.
    else
        error("Unknown window type: " .. self._type)
    end

    local rawChildren = {}
    for _i, child in pairs(self.children) do
        table.insert(rawChildren, child.raw)
    end

    local raw = ui.dispatcher:AddWindow(props, rawChildren)
    if not self._geometry then
        raw:RecalcLayout()
    end

    self:installEventHandlers(raw)

    return raw
end

function Window:show()
    Window._shown[self] = true
    self.raw:Show()
    self.raw:Raise()
    return self
end

function Window:hide()
    if self.materialised then
        self.raw:Hide()
        Window._shown[self] = nil
    end
    return self
end

function Window:close()
    if self.materialised then
        self.raw:Close()
        Window._shown[self] = nil
    end
    return self
end

return Window
