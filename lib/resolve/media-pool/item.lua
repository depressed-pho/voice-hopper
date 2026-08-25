local class = require("class")

local MediaPoolItem = class("MediaPoolItem")

-- @private
function MediaPoolItem:__init(raw)
    assert(raw, "MediaPoolItem:new() expects a raw MediaPoolItem object")

    self._raw = raw
end

function MediaPoolItem:__tostring()
    return table.concat {"[MediaPoolItem: ", self.name, "]"}
end

function MediaPoolItem.__getter:name()
    return self._raw:GetName()
end

function MediaPoolItem.__getter:filePath()
    return self._raw:GetClipProperty("File Path")
end

return MediaPoolItem
