local Colour = require("colour")
local class  = require("class")

--
-- A column of a TreeItem. There is no corresponding class in the native UI
-- toolkit.
--
local TreeColumn = class("TreeColumn")

function TreeColumn:__init(text)
    assert(type(text) == "string", "TreeColumn:new() expects a string text")
    self._item     = nil  -- TreeItem
    self._idx      = nil  -- number
    self._text     = text -- string
    self._fgColour = nil  -- Colour or nil
    self._bgColour = nil  -- Colour or nil
end

function TreeColumn.__getter:text()
    return self._text
end
function TreeColumn.__setter:text(text)
    assert(type(text) == "string", "TreeColumn#text expects a string text")
    self._text = text
    if self._item then
        self._item.raw.Text[self._idx] = text
    end
end

--
-- TreeColumn#colour is a live object with two properties "fg" and
-- "bg". Both of the properties are of type Colour or nil, with nil being
-- the default colour.
--
function TreeColumn.__getter:colour()
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
                               "TreeColumn#colours.fg is expected to either be a Colour or nil")
                        self._fgColour = val
                        if self._item then
                            self._item.raw.TextColor[self._idx] = (val and val:asTable()) or nil
                        end
                    elseif key == "bg" then
                        assert(val == nil or Colour:made(val),
                               "TreeColumn#colours.bg is expected to either be a Colour or nil")
                        self._bgColour = val
                        if self._item then
                            self._item.raw.BackgroundColor[self._idx] = (val and val:asTable()) or nil
                        end
                    else
                        error("Unknown property: "..tostring(key), 2)
                    end
                end
            })
    end
    return self._colourCache
end

-- Private; only TreeItem can call this method.
function TreeColumn:populate(item, idx)
    if self._item then
        error("This TreeColumn object has already populated a TreeItem", 2)
    end

    self._item = item
    self._idx  = idx  -- 0-indexed

    self._item.raw.Text[self._idx] = self._text
    if self._fgColour then
        self._item.raw.TextColor[self._idx] = self._fgColour:asTable()
    end
    if self._bgColour then
        self._item.raw.BackgroundColor[self._idx] = self._bgColour:asTable()
    end
end

return TreeColumn
