local MediaPoolItem = require("resolve/media-pool/item")
local class         = require("class")

local Folder = class("Folder")

-- @private
function Folder:__init(raw)
    assert(raw, "Folder:new() expects a raw Folder object")

    self._raw = raw
end

function Folder:__tostring()
    return table.concat {"[Folder: ", self.name, "]"}
end

function Folder.__getter:name()
    return self._raw:GetName()
end

function Folder:clips()
    local seq = self._raw:GetClipList()
    return coroutine.wrap(
        function ()
            for _i, rawItem in ipairs(seq) do
                coroutine.yield(MediaPoolItem:new(rawItem))
            end
        end)
end

function Folder:dirs()
    local seq = self._raw:GetSubFolderList()
    return coroutine.wrap(
        function ()
            for _i, rawDir in ipairs(seq) do
                coroutine.yield(Folder:new(rawDir))
            end
        end)
end

function Folder:dir(name)
    assert(type(name) == "string", "Folder#dir() expects a folder name")

    local seq = self._raw:GetSubFolderList()
    for _i, rawDir in ipairs(seq) do
        if rawDir:GetName() == name then
            return Folder:new(rawDir)
        end
    end
end

return Folder
