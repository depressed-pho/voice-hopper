local Symbol   = require("symbol")
local class    = require("class")
local path     = require("path")
local readonly = require("readonly")
assert(bmd, "Global \"bmd\" not defined")

--
-- Class DirEnt represents a directory entry.
--
local DirEnt = class("DirEnt")

local TYPE_FILE = Symbol("file")
local TYPE_DIR  = Symbol("dir")

-- private
function DirEnt:__init(props)
    self._props = props
    self._path  = nil   -- A cache of the absolute path of the entry.
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
-- DirEnt.path is the absolute path of the file this DirEnt object refers
-- to.
--
function DirEnt.__getter:path()
    if self._path == nil then
        self._path = path.join(self._props.parent, self._props.name)
    end
    return self._path
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
-- Accessing file system in a very limited way, limited to what "bmd" API
-- offers to us.
--
local fs = {}
fs.DirEnt = DirEnt

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
    assert(type(p) == "string", "fs.stat() expects a path to a directory")

    -- Turn p into absolute if it's relative. The base directory should be
    -- what bmd.getcurrentdir() returns. bmd.readdir("relative/path") never
    -- returns anything.
    if not path.isAbsolute(p) then
        error("FIXME: Relative paths are currently not supported: "..p)
    end

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
    assert(type(p) == "string", "fs.isFile() expects a path to a directory")

    -- Turn p into absolute if it's relative. The base directory should be
    -- what bmd.getcurrentdir() returns. bmd.readdir("relative/path") never
    -- returns anything.
    if not path.isAbsolute(p) then
        error("FIXME: Relative paths are currently not supported: "..p)
    end

    local ents = bmd.readdir(p)
    return ents[1] ~= nil and not ents[1].IsDir
end

--
-- fs.isDirectory(p) returns true iff "p" refers to a directory.
--
fs.isDirectory = bmd.direxists

--
-- fs.mkdir(p, opts) creates a directory. If "opts" is given and
-- "opts.recursive" is true, the entire directory tree will be created.
--
-- In non-recursive mode (default), fs.mkdir() raises an error if the
-- directory already exists. In recursive mode it doesn't.
--
function fs.mkdir(p, opts)
    assert(type(p) == "string", "fs.mkdir() expects a string path as its 1st argument")

    opts = opts or {}
    assert(type(opts) == "table", "fs.mkdir() expects an optional table as its 2nd argument")

    opts.recursive = opts.recursive or false
    assert(type(opts.recursive) == "boolean", "\"recursive\" is expected to be a boolean")

    if not opts.recursive then
        -- bmd.createdir() is always recursive. We must emulate a
        -- non-recursive mkdir in a racy way.
        if fs.isDirectory(path.dirname(p)) then
            -- ok
        else
            error("Parent directory does not exist: " .. p, 2)
        end
    end

    local ok = bmd.createdir(p)
    if not ok then
        if fs.isDirectory(p) then
            -- bmd.createdir() failed because it already exists. There can
            -- be a race here, but that's not our fault.
        else
            error("Failed to create a directory: " .. p, 2)
        end
    end
end

--
-- fs.readdir(dir) returns a sequence of DirEnt objects for each file in
-- the given directory path. If the directory does not exist, it raises an
-- error.
--
function fs.readdir(p)
    assert(type(p) == "string", "fs.readdir() expects a path to a directory")

    -- Turn p into absolute if it's relative. The base directory should be
    -- what bmd.getcurrentdir() returns. bmd.readdir("*") never returns
    -- anything.
    if not path.isAbsolute(p) then
        error("FIXME: Relative paths are currently not supported: "..p)
    end

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
