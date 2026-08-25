local Project = require("resolve/project")
local class   = require("class")

local ProjectManager = class("ProjectManager")

-- @private
function ProjectManager:__init(raw)
    assert(raw, "ProjectManager:new() expects a raw ProjectManager object")

    self._raw = raw
end

function ProjectManager.__getter:current()
    local rawProj = self._raw:GetCurrentProject()
    return rawProj and Project:new(rawProj)
end

return ProjectManager
