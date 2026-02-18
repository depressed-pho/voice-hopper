local Colour = require("colour")
local class  = require("class")

--
-- A tab in a tab bar. There is no corresponding class in the native UI
-- toolkit.
--
local Tab = class("Tab")

function Tab:__init(text)
    assert(type(text) == "string", "Tab:new() expects a string text")
    self._tabBar     = nil  -- UITabBar
    self._index      = nil  -- integer
    self._text       = text -- string
    self._toolTip    = nil  -- string or nil
    self._whatsThis  = nil  -- string or nil
    self._textColour = nil  -- Colour or nil
end

function Tab.__getter:text()
    return self._text
end
function Tab.__setter:text(text)
    assert(type(text) == "string", "Tab#text is expected to be a string")
    self._text = text
    if self._tabBar then
        self._tabBar.TabText[self._index] = text
    end
end

function Tab.__getter:toolTip()
    return self._toolTip
end
function Tab.__setter:toolTip(text)
    assert(type(text) == "string", "Tab#toolTip is expected to be a string")
    self._toolTip = text
    if self._tabBar then
        self._tabBar.TabToolTip[self._index] = text
    end
end

function Tab.__getter:whatsThis()
    return self._whatsThis
end
function Tab.__setter:toolTip(text)
    assert(type(text) == "string", "Tab#whatsThis is expected to be a string")
    self._whatsThis = text
    if self._tabBar then
        self._tabBar.TabWhatsThis[self._index] = text
    end
end

function Tab.__getter:textColour()
    return self._textColour
end
function Tab.__setter:textColour(colour)
    assert(Colour:made(colour) or colour == nil, "Tab#textColour is expected to be a Colour or nil")
    self._textColour = colour
    if self._tabBar then
        self._tabBar.TabTextColor[self._index] = (colour and colour:asTable()) or nil
    end
end

-- Private; only TabBar can call this method.
function Tab:populate(tabBar, index)
    if self._tabBar then
        error("This Tab object has already populated a TabBar", 2)
    end

    self._tabBar = tabBar
    self._index  = index -- 0-origin

    self._tabBar:AddTab(self._text)
    self._tabBar.TabToolTip[self._index] = self._toolTip
    self._tabBar.TabWhatsThis[self._index] = self._whatsThis
    self._tabBar.TabTextColor[self._index] = (self._textColour and self._textColour:asTable()) or nil
end

return Tab
