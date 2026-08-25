local ProjectManager = require("resolve/project-manager")
local class          = require("class")
local ui             = require("ui")

local Resolve = class("Resolve")

-- @private
function Resolve:__init(raw)
    assert(raw, "Resolve:new() expects a raw Resolve object")
    self._raw = raw -- Resolve
end

function Resolve.__getter:projectManager()
    return ProjectManager:new(self._raw:GetProjectManager())
end

-- Resolve is a singleton object.
return Resolve:new(ui.fusion:GetResolve())
