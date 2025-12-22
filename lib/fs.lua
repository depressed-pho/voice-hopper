local class    = require("class")
local path     = require("path")
local readonly = require("readonly")
assert(bmd, "Global \"bmd\" not defined")

--
-- Accessing file system in a very limited way, limited to what "bmd" API
-- offers to us.
--
local fs = {}

--
-- fs.exists(p) returns true iff "p" refers to a file or a directory.
--
fs.exists = bmd.fileexists

--
-- fs.stat(p) returns an instance of DirEnt if "p" refers to a file or a
-- directory, or nil otherwise. As a special case it also returns nil for
-- the root directory (which is undesirable but is unavoidable because of
-- the way how the "bmd" API works).
--
function fs.stat(p)
    local ents = bmd.readdir(p)
    local ent  = ents[1]

    if ent == nil then
        return nil
    else
        return DirEnt:new {
            parent       = ents.Parent,
            type         = (ent.IsDir and TYPE_DIR) or TYPE_FILE,
            size         = ent.Size,
            name         = ent.Name,
            lastModified = ent.WriteTime,
            lastAccessed = ent.AccessTime,
            created      = ent.CreateTime,
            isReadOnly   = ent.IsReadOnly,
        }
    end
end

--
-- fs.isFile(p) returns true iff "p" refers to a non-directory (but not
-- necessarily a regular) file.
--
function fs.isFile(p)
    local ents = bmd.readdir(p)
    return ents[1] ~= nil and not ents[1].IsDir
end

--
-- fs.isDirectory(p) returns true iff "p" refers to a directory.
--
fs.isDirectory = bmd.direxists

--
-- Class DirEnt represents a directory entry.
--
local DirEnt = class("DirEnt")
fs.DirEnt = DirEnt

local TYPE_FILE = 0
local TYPE_DIR  = 1

-- private
function DirEnt:__init(props)
    self._props = props
end

function DirEnt:__tostring()
    return string.format(
        "[DirEnt: %s%s]",
        self._props.name,
        (self._props.type == TYPE_DIR and "/") or "")
end

--
-- DirEnt.isDirectory is true iff the DirEnt object describes a directory.
--
function DirEnt.__getter:isDirectory()
    return self._props.type == TYPE_DIR
end

--
-- DirEnt.isFile is true iff the DirEnt object describes a non-directory
-- (but not necessarily a regular) file.
--
function DirEnt.__getter:isFile()
    return self._props.type == TYPE_FILE
end

--
-- DirEnt.size is the size of the file this DirEnt object refers to. If
-- it's a directory the meaning of the size is platform-dependent and is
-- usually *not* the total size of the files in the directory. In other
-- words, it makes no sense.
--
function DirEnt.__getter:size()
    return self._props.size
end

--
-- DirEnt.name is the file name this DirEnt object refers to.
--
function DirEnt.__getter:name()
    return self._props.name
end

--
-- DirEnt.parentPath is the path to the parent directory of the file this
-- DirEnt object refers to.
--
function DirEnt.__getter:parentPath()
    return self._props.parent
end

--
-- DirEnt.lastModified is the time at which the file was last modified. It
-- is a number whose meaning depends on the platform, the same as what
-- os.time() returns.
--
function DirEnt.__getter:lastModified()
    return self._props.lastModified
end

--
-- DirEnt.lastAccessed is the time at which the file was last accessed.
--
function DirEnt.__getter:lastAccessed()
    return self._props.lastAccessed
end

--
-- DirEnt.created is the time at which the file was created.
--
function DirEnt.__getter:created()
    return self._props.created
end

--
-- DirEnt.isReadOnly is true iff the file is read-only.
--
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
