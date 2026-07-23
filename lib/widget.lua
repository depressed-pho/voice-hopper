local AbstractImmutableSet = require("collection/set/immutable/base")
local CSSStyleProperties   = require("css-style-properties")
local EventEmitter         = require("event/emitter")
local Set                  = require("collection/set")
local UIEvent              = require("ui/event")
local class                = require("class")
local console              = require("console")

-- ----------------------------------------------------------------------------
-- Abstract widget class
-- ----------------------------------------------------------------------------
local Widget = class("Widget", EventEmitter())

function Widget:__init(possibleEvents)
    assert(possibleEvents == nil or AbstractImmutableSet:made(possibleEvents),
           "Widget:new() expects an optional set of possible events it can emit")

    -- Native UI events are in the namespace "ui".
    local events = Set:new {
        "newListener", "ui:MousePress", "ui:MouseRelease", "ui:MouseDoubleClick",
        "ui:MouseMove", "ui:Wheel", "ui:KeyPress", "ui:KeyRelease", "ui:ContextMenu",
        "ui:Move", "ui:FocusIn", "ui:FocusOut"
    }
    super(events .. (possibleEvents or Set:new()))

    -- Generate a random ID
    local digits = {"id"}
    for i = 2, 21 do
        digits[i] = math.random(0, 9)
    end
    self._id      = table.concat(digits)
    self._enabled = true
    self._minSize = nil -- {w, h}
    -- self._style may also be a string.
    self._style   = CSSStyleProperties:new(function() self:_styleUpdated() end)
    self._visible = true
    self._weight  = nil
    self._toolTip = nil
    self._raw     = nil

    self:on("newListener", function(name, _ev)
        if self._raw then
            -- This is unfortunate. Events has to be enabled via widget
            -- properties in order for them to be emitted, and it seems we
            -- cannot change them afterwards. We can do
            -- self._raw:Set("Events", {...}) yes, but it doesn't take
            -- effect (see app:GetHelp("UIItem")).
            console:warn(
                "It's too late to set an event handler for %s on the widget." ..
                " It must be done before the widget is materialised", name)
            console:trace()
        end
    end)
end

function Widget.__getter:id()
    return self._id
end

function Widget.__getter:enabled()
    return self._enabled
end
function Widget.__setter:enabled(enabled)
    assert(type(enabled) == "boolean", "Widget#enabled is expected to be a boolean")
    self._enabled = enabled
    if self._raw then
        self._raw.Enabled = enabled
    end
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
-- Widget#minimumSize is a live table with two fields "w" and "h", which
-- reflects the minimum width and height of the widget
-- respectively. Writing to these fields will affect the minimum size of
-- the widget.
--
function Widget.__getter:minimumSize()
    if self._minSizeCache == nil then
        self._minSizeCache = setmetatable(
            {},
            {
                __index = function(_tab, key)
                    if key == "w" then
                        return (self._minSize and self._minSize[1]) or 0
                    elseif key == "h" then
                        return (self._minSize and self._minSize[2]) or 0
                    else
                        error("No such key exists: "..tostring(key), 2)
                    end
                end,
                __newindex = function(_tab, key, val)
                    assert(type(val) == "number", tostring(key).." is expected to be a number")

                    if key == "w" then
                        self._minSize = self._minSize or {0, 0}
                        self._minSize[1] = val
                        if self._raw then
                            self._raw.MinimumSize[1] = val
                        end
                    elseif key == "h" then
                        self._minSize = self._minSize or {0, 0}
                        self._minSize[2] = val
                        if self._raw then
                            self._raw.MinimumSize[2] = val
                        end
                    else
                        error("No such key exists: "..tostring(key), 2)
                    end
                end
            })
    end
    return self._minSizeCache
end

--
-- Widget#size is a live table with two fields "w" and "h", which reflects
-- the current width and height of the widget respectively. Writing to these
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
function Widget.__setter:style(text)
    assert(type(text) == "string", "Widget#style is expected to be a string")
    self._style = text
    if self._raw then
        self._raw.StyleSheet = text
    end
end
function Widget:_styleUpdated()
    if self._raw then
        self._raw.StyleSheet = tostring(self.style)
    end
end

function Widget.__getter:visible()
    return self._visible
end
function Widget.__setter:visible(visible)
    assert(type(visible) == "boolean", "Widget#enabled is expected to be a boolean")
    self._visible = visible
    if self._raw then
        self._raw.Visible = visible
    end
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
    for name in self.listenedEvents:values() do
        -- Only enable native UI events.
        if string.find(name, "^ui:") then
            ret[string.sub(name, 4)] = true
        end
    end
    return ret
end

-- protected
function Widget:commonProps()
    local props = {
        ID          = self._id,
        Enabled     = self._enabled,
        Events      = self.enabledEvents,
        MinimumSize = self._minSize,
        StyleSheet  = tostring(self._style),
        ToolTip     = self._toolTip,
        Weight      = self._weight,
    }
    if not self._visible then
        -- Declaring "Visible = true" causes an inexplicably strange
        -- behaviour. Most likely a Resolve bug.
        props.Visible = false
    end
    return props
end

-- protected
Widget:abstract("materialise")

-- protected
function Widget:installEventHandlers(rawWin)
    for name in self.listenedEvents:values() do
        -- Only install handlers for native UI events.
        if string.find(name, "^ui:") then
            rawWin.On[self._id][string.sub(name, 4)] = function(ev)
                -- THINKME: We should subclass UIEvent based on the raw
                -- event type.
                self:emit(name, UIEvent:new(ev))
            end
        end
    end
end

return Widget
