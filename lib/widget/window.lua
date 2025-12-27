local Container = require("widget/container")
local class     = require("class")
local ui        = require("ui")

local Window = class("Window", Container)
Window._shown = setmetatable({}, {__mode = "k"}) -- Window => true

function Window:__init(children)
    super(children)
    self._initialTitle = nil
    self._initialGeom  = {100, 100, 640, 480} -- {x, y, w, h}
    self._initialType  = "regular"

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
    if self.materialised then
        return self.raw.WindowTitle
    else
        return self._initialTitle
    end
end
function Window.__setter:title(title)
    assert(type(title) == "string", "Window:setTitle() expects a string title")
    if self.materialised then
        self.raw.WindowTitle = title
    else
        self._initialTitle = title
    end
end

function Window.__getter:type()
    return self._type
end
function Window.__setter:type(typ)
    assert(typ == "regular" or typ == "floating")
    self._type = typ
    if self.materialised then
        error("Changing window type after materialisation is currently not supported. Don't know if it's even possible")
    end
    return self
end

function Window.__getter:position()
    if self._posCache == nil then
        self._posCache = setmetatable(
            {},
            {
                __index = function(_tab, key)
                    if key == "x" then
                        if self.materialised then
                            return self.raw:X()
                        else
                            return self._initialGeom[1]
                        end
                    elseif key == "y" then
                        if self.materialised then
                            return self.raw:Y()
                        else
                            return self._initialGeom[2]
                        end
                    else
                        error("No such key exists: "..tostring(key), 2)
                    end
                end,
                __newindex = function(_tab, key, val)
                    assert(type(val) == "number", tostring(key).." is expected to be a number")

                    if key == "x" then
                        if self.materialised then
                            self.raw:Move({val, self.raw:Y()})
                        else
                            self._initialGeom[1] = val
                        end
                    elseif key == "y" then
                        if self.materialised then
                            self.raw.Move({self.raw:X(), val})
                        else
                            self._initialGeom[2] = val
                        end
                    else
                        error("No such key exists: "..tostring(key), 2)
                    end
                end
            })
    end
    return self._posCache
end

function Window.__getter:size()
    if self._sizeCache == nil then
        self._sizeCache = setmetatable(
            {},
            {
                __index = function(_tab, key)
                    if key == "w" then
                        if self.materialised then
                            return self.raw:Width()
                        else
                            return self._initialGeom[3]
                        end
                    elseif key == "h" then
                        if self.materialised then
                            return self.raw:Height()
                        else
                            return self._initialGeom[4]
                        end
                    else
                        error("No such key exists: "..tostring(key), 2)
                    end
                end,
                __newindex = function(_tab, key, val)
                    assert(type(val) == "number", tostring(key).." is expected to be a number")

                    if key == "w" then
                        if self.materialised then
                            self.raw:Resize({val, self.raw:Height()})
                        else
                            self._initialGeom[3] = val
                        end
                    elseif key == "h" then
                        if self.materialised then
                            self.raw.Resize({self.raw:Width(), val})
                        else
                            self._initialGeom[4] = val
                        end
                    else
                        error("No such key exists: "..tostring(key), 2)
                    end
                end
            })
    end
    return self._sizeCache
end

function Window:materialise()
    if #self.children == 0 then
        -- Attempting to create an empty window causes DaVinci Resolve
        -- to crash.
        error("The window has no children. Add something before showing it", 2)
    end

    local props = {
        ID       = self.id,
        Events   = self.enabledEvents,
        Geometry = self._initialGeom,
    }
    if self._title ~= nil then
        props.WindowTitle = self._title
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
    raw:RecalcLayout()

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
