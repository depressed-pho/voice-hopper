local HGap       = require("widget/h-gap")
local HGroup     = require("widget/container/h-group")
local Set        = require("collection/set")
local Tree       = require("widget/tree")
local TreeColumn = require("widget/tree/column")
local TreeItem   = require("widget/tree/item")
local VGroup     = require("widget/container/v-group")
local Window     = require("widget/window")
local class      = require("class")
--local event      = require("event")

local CharConfWindow = class("CharConfWindow", Window)

function CharConfWindow:__init(chars)
    local events = Set:new {
    }
    super(events)

    self._chars = chars -- Config
    self._table = nil   -- Tree

--[[
    self:on("ui:Move", event.debounce(
        function()
            self._chars.fields.position.x = self.position.x
            self._chars.fields.position.y = self.position.y
            --self._chars:save() -- FIXME
        end, 0.5)
    )
    self:on("ui:Resize", event.debounce(
        function()
            self._chars.fields.size.w = self.size.w
            self._chars.fields.size.h = self.size.h
            --self._chars:save() -- FIXME
        end, 0.5)
    )
]]

    self.title = "Characters"
    self.type  = "floating"
    self.style.padding = "10px"

    self.position.x = self._chars.fields.position.x or self.position.x
    self.position.y = self._chars.fields.position.y or self.position.y
    self.size.w     = self._chars.fields.size.w     or self.size.w
    self.size.h     = self._chars.fields.size.h     or self.size.h

    local root = HGroup:new()
    local gap  = 10
    do
        root:addChild(self:_mkTableGroup())
        root:addChild(HGap:new(gap))
    end
    do
        root:addChild(self:_mkFieldsGroup())
    end
    self:addChild(root)
end

function CharConfWindow:_mkTableGroup()
    local grp = HGroup:new()
    do
        self._table = Tree:new(4)
        self._table.header = TreeItem:new {
            TreeColumn:new "Name",
            TreeColumn:new "Pattern",
            TreeColumn:new "Colour",
            TreeColumn:new "Subtitle"
        }
        grp:addChild(self._table)
    end
    return grp
end

function CharConfWindow:_mkFieldsGroup()
    local grp = VGroup:new()
    return grp
end

return CharConfWindow
