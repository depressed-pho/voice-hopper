local class    = require("class")
local path     = require("path")
local readonly = require("readonly")
assert(bmd, "Global \"bmd\" not defined")

--
-- Accessing file system in a very limited way, limited to what "bmd" API
-- offers to us.
--
local fs = {}

local DirEnt = class("DirEnt")

local TYPE_FILE = 0
local TYPE_DIR  = 1

-- private
function DirEnt:__init(props)
    self._props = props
end

-- true iff the DirEnt object describes a directory.
function DirEnt.__getter:isDirectory()
    return self._props.type == TYPE_DIR
end

-- true iff the DirEnt object describes a non-directory (but not
-- necessarily a regular) file.
function DirEnt.__getter:isFile()
    return self._props.type == TYPE_FILE
end

-- The file name that this DirEnt object refers to.
function DirEnt.__getter:name()
    return self._props.name
end

-- The path to the parent directory of the file this DirEnt object refers
-- to.
function DirEnt.__getter:parentPath()
    return self._props.parent
end

-- The time at which the file was last modified. It is a number whose
-- meaning depends on the platform, the same as what os.time() returns.
function DirEnt.__getter:lastModified()
    return self._props.lastModified
end

-- The time at which the file was last accessed.
function DirEnt.__getter:lastAccessed()
    return self._props.lastAccessed
end

-- The time at which the file was created.
function DirEnt.__getter:created()
    return self._props.created
end

-- true iff the file is read-only.
function DirEnt.__getter:isReadOnly()
    return self._props.isReadOnly
end

--
-- fs.readdir(dir) returns a sequence of DirEnt objects for each file in
-- the given directory path. If the directory does not exist, it raises an
-- error.
--
function fs.readdir(p)
    assert(type(p) == "string", "fs.readdir() expects a path to a directory")

    if bmd.direxists(p) then
        -- OMG a race can happen OMG OMG but since bmd.readdir() returns an
        -- empty table on error there's nothing we can do about the race.
        local dir = bmd.readdir(path.join(p, "*"))
        local ret = {}
        for i, ent in ipairs(dir) do
            ret[i] = DirEnt:new {
                parent       = p,
                type         = (ent.IsDir and TYPE_DIR) or TYPE_FILE,
                size         = ent.Size,
                name         = ent.Name,
                lastModified = ent.WriteTime,
                lastAccessed = ent.AccessTime,
                created      = ent.CreateTime,
                isReadOnly   = ent.IsReadOnly,
            }
        end
        return ret
    else
        error("Directory " .. p .. " does not exist", 2)
    end
end

return readonly(fs)
