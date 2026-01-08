local CSSStyleProperties = require("css-style-properties")
local class              = require("class")

-- ----------------------------------------------------------------------------
-- Abstract widget class
-- ----------------------------------------------------------------------------
local Widget = class("Widget")

function Widget:__init()
    -- Generate a random ID
    local digits = {"id"}
    for i = 2, 21 do
        digits[i] = math.random(0, 9)
    end
    self._id       = table.concat(digits)
    self._style    = CSSStyleProperties:new()
    self._weight   = nil
    self._toolTip  = nil
    self._events   = {} -- name => function
    self._raw      = nil
end

function Widget.__getter:id()
    return self._id
end

--
-- Widget#position is a live table with two fields "x" and "y", which
-- reflects the current X-Y position of the widget. Writing to these fields
-- will move the widget.
--
function Widget.__getter:position()
    if self._raw then
        if self._posCache == nil then
            self._posCache = setmetatable(
                {},
                {
                    __index = function(_tab, key)
                        if key == "x" then
                            -- See app:GetHelp("UIWidget")
                            return self._raw:X()
                        elseif key == "y" then
                            return self._raw:Y()
                        else
                            error("No such key exists: "..tostring(key), 2)
                        end
                    end,
                    __newindex = function(_tab, key, val)
                        assert(type(val) == "number", tostring(key).." is expected to be a number")

                        if key == "x" then
                            -- See app:GetHelp("UIWidget")
                            self._raw:Move({val, self._raw:Y()})
                        elseif key == "y" then
                            self._raw:Move({self._raw:X(), val})
                        else
                            error("No such key exists: "..tostring(key), 2)
                        end
                    end
                })
        end
        return self._posCache
    else
        error("Non-materialised widget does not have a position", 2)
    end
end

--
-- Widget#size is a live table with two fields "w" and "h", which reflects
-- the current width and height of the widget respectively. Writing to ehse
-- fields will resize the widget.
--
function Widget.__getter:size()
    if self._raw then
        if self._sizeCache == nil then
            self._sizeCache = setmetatable(
                {},
                {
                    __index = function(_tab, key)
                        if key == "w" then
                            -- See app:GetHelp("UIWidget")
                            return self._raw:Width()
                        elseif key == "h" then
                            return self._raw:Height()
                        else
                            error("No such key exists: "..tostring(key), 2)
                        end
                    end,
                    __newindex = function(_tab, key, val)
                        assert(type(val) == "number", tostring(key).." is expected to be a number")

                        if key == "w" then
                            -- See app:GetHelp("UIWidget")
                            self._raw:Resize({val, self._raw:Height()})
                        elseif key == "h" then
                            self._raw:Resize({self._raw:Width(), val})
                        else
                            error("No such key exists: "..tostring(key), 2)
                        end
                    end
                })
        end
        return self._sizeCache
    else
        error("Non-materialised widget does not have a size", 2)
    end
end

function Widget.__getter:style()
    return self._style
end

function Widget.__getter:weight()
    return self._weight
end
function Widget.__setter:weight(weight)
    assert(weight == nil or type(weight) == "number", "Widget.weight expects an optional number")
    self._weight = weight
end

function Widget.__getter:toolTip()
    return self._toolTip
end
function Widget.__setter:toolTip(toolTip)
    assert(toolTip == nil or type(toolTip) == "string", "Widget.toolTip expects an optional string")
    self._toolTip = toolTip
end

function Widget.__getter:raw()
    if not self._raw then
        self._raw = self:materialise()
    end
    return self._raw
end

function Widget.__getter:materialised()
    return not not self._raw
end

-- protected
function Widget.__getter:enabledEvents()
    local ret = {}
    for name, _listener in pairs(self._events) do
        ret[name] = true
    end
    return ret
end

-- protected
function Widget:materialise()
    error("Widgets are expected to override the method materialise()", 2)
end

function Widget:on(eventName, listener)
    assert(type(eventName) == "string", "Widget:on() expects an event name as its 1st argument")
    assert(type(listener) == "function", "Widget:on() expects a listener function as its 2nd argument")

    self._events[eventName] = listener

    if self.materialised then
        -- This is unfortunate. Events has to be enabled via widget
        -- properties in order for them to be emitted, and it seems we
        -- cannot change them afterwards. We can do self._raw:Set("Events",
        -- {...}) yes, but it doesn't take effect (see
        -- app:GetHelp("UIItem")).
        error("It's too late to set an event handler on the widget." ..
              " It must be done before the widget is materialised", 2);
    end
    return self
end

-- protected
function Widget:installEventHandlers(rawWin)
    for name, listener in pairs(self._events) do
        rawWin.On[self._id][name] = listener
    end
end

return Widget
