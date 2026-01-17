local Colour = require("colour")
local Set    = require("collection/set")
local Widget = require("widget")
local class  = require("class")
local ui     = require("ui")

-- We must define our own default colours because Qt provides no API to
-- read platform-default colours.
local DEFAULT_FG_COLOUR = Colour:rgba(1, 1, 1, 1)
local DEFAULT_BG_COLOUR = Colour:rgba(0, 0, 0, 0)

local TextEdit = class("TextEdit", Widget)

function TextEdit:__init(initialText)
    assert(initialText == nil or type(initialText) == "string", "TextEdit:new() expects an optional initial text")
    super(Set:new {"ui:TextChanged", "ui:SelectionChanged", "ui:CursorPositionChanged"})
    self._initialText = initialText or ""
    self._readOnly    = false -- boolean
    self._tabWidth    = 20    -- non-negative integer
    self._fgColour    = DEFAULT_FG_COLOUR
    self._bgColour    = DEFAULT_BG_COLOUR
end

function TextEdit.__getter:readOnly()
    return self._readOnly
end

function TextEdit.__setter:readOnly(bool)
    self._readOnly = bool
end

--
-- This is the pixel width of tabs. Not the number of spaces or anything
-- like that.
--
function TextEdit.__getter:tabWidth()
    return self._tabWidth
end
function TextEdit.__setter:tabWidth(width)
    assert(type(width) == "number" and math.floor(width) == width and width >= 0,
           "TextEdit#tabWidth is expected to be a non-negative integer")
    self._tabWidth = width
    if self.materialised then
        self.raw.TabStopWidth = width
    end
end

--
-- TextEdit#colour is a live object with two properties "fg" and "bg". Both
-- of the properties are of type Colour or nil, with nil being the default
-- colour.
--
-- This is the colour of the text formatting. It doesn't change the colour
-- of the current contents.
--
function TextEdit.__getter:colour()
    if self._colourCache == nil then
        self._colourCache = setmetatable(
            {},
            {
                __index = function(_colour, key)
                    if key == "fg" then
                        return self._fgColour
                    elseif key == "bg" then
                        return self._bgColour
                    else
                        error("Unknown property: "..tostring(key), 2)
                    end
                end,
                __newindex = function(_colour, key, val)
                    if key == "fg" then
                        assert(val == nil or Colour:made(val),
                               "TextEdit#colour.fg is expected to either be a Colour or nil")
                        self._fgColour = val or DEFAULT_FG_COLOUR
                        if self.materialised then
                            self.raw.TextColor = self._fgColour:asTable()
                        end
                    elseif key == "bg" then
                        assert(val == nil or Colour:made(val),
                               "TextEdit#colour.bg is expected to either be a Colour or nil")
                        self._bgColour = val or DEFAULT_BG_COLOUR
                        if self.materialised then
                            self.raw.TextBackgroundColor = self._bgColour:asTable()
                        end
                    else
                        error("Unknown property: "..tostring(key), 2)
                    end
                end
            })
    end
    return self._colourCache
end

--
-- The contents of the TextEdit in plain text.
--
function TextEdit.__getter:text()
    if self.materialised then
        return self.raw.Text
    else
        return self._initialText
    end
end
function TextEdit.__setter:text(text)
    assert(type(text) == "string", "TextEdit#text expects a string")
    if self.materialised then
        self.raw.Text = text
    else
        self._initialText = text
    end
end

--
-- Append a *paragraph* to the widget.
--
function TextEdit:append(para)
    assert(type(para) == "string", "TextEdit#append() expects a string paragraph")
    if self.materialised then
        self.raw:Append(para)
    else
        error("TextEdit#append() can only be used after materialisation at the moment", 2)
    end
end

function TextEdit:clear()
    if self.materialised then
        self.raw:Clear()
        -- Clear() resets the current format. Restore them back.
        self.raw.TextColor           = self._fgColour:asTable()
        self.raw.TextBackgroundColor = self._bgColour:asTable()
    else
        self._initialText = ""
    end
end

function TextEdit:materialise()
    local props = self:commonProps()
    props.Text                = self._initialText
    props.ReadOnly            = self._readOnly
    props.TabStopWidth        = self._tabWidth
    props.TextColor           = self._fgColour:asTable()
    props.TextBackgroundColor = self._bgColour:asTable()
    return ui.manager:TextEdit(props)
end

return TextEdit
