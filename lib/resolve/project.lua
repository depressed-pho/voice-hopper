local MediaPool = require("resolve/media-pool")
local class     = require("class")

local Project = class("Project")

-- @private
function Project:__init(raw)
    assert(raw, "Project:new() expects a raw Project object")

    self._raw = raw
end

function Project:__tostring()
    return table.concat {"[Project: ", self.name, "]"}
end

function Project.__getter:mediaPool()
    return MediaPool:new(self._raw:GetMediaPool())
end

function Project.__getter:name()
    return self._raw:GetName()
end

return Project
