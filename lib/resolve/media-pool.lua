local Folder = require("resolve/media-pool/folder")
local class  = require("class")

local MediaPool = class("MediaPool")

-- @private
function MediaPool:__init(raw)
    assert(raw, "MediaPool:new() expects a raw MediaPool object")

    self._raw = raw
end

function MediaPool.__getter:root()
    return Folder:new(self._raw:GetRootFolder())
end

return MediaPool
