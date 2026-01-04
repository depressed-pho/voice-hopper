local EventEmitter = require("event-emitter")
local Promise      = require("promise")
local Queue        = require("container/queue")
local Thread       = require("thread")
local class        = require("class")
local delay        = require("delay")
local fs           = require("fs")
local path         = require("path")

--
-- FSEvent is the root of the event that FSNotify emits.
--
local FSEvent = class("FSEvent")

function FSEvent:__init(entry)
    assert(fs.DirEnt:made(entry), "FSEvent:new() expects an instance of fs.DirEnt")

    -- Public property "entry" is an instance of fs.DirEnt the event refers
    -- to.
    self.entry = entry
end

--
-- CreatedEvent is a subclass of FSEvent to be emitted when a file or a
-- directory is created or moved in.
--
local CreatedEvent = class("CreatedEvent", FSEvent)

--
-- DeletedEvent is a subclass of FSEvent to be emitted when a file or a
-- directory is deleted or moved away.
--
local DeletedEvent = class("DeletedEvent", FSEvent)

--
-- ModifiedEvent is a subclass of FSEvent to be emitted when a file or a
-- directory is modified. Creating or deleting entries in a directory also
-- counts as modifying the directory.
--
local ModifiedEvent = class("ModifiedEvent", FSEvent)

function ModifiedEvent:__init(oldEntry, newEntry)
    assert(fs.DirEnt:made(oldEntry), "ModifiedEvent:new() expects two instances of fs.DirEnt")
    assert(fs.DirEnt:made(newEntry), "ModifiedEvent:new() expects two instances of fs.DirEnt")

    super(newEntry)

    -- Public property "oldEntry" is an instance of fs.DirEnt representing
    -- the old state of the directory entry.
    self.oldEntry = oldEntry
end

--
-- FSNotify is a subclass of Thread and EventEmitter. Its purpose is to
-- watch a directory (and optionally its subdirectories) and emit events
-- when files under the directory are created, deleted, or modified.
--
-- Example:
--   local fsn = FSNotify:new("/foo/bar")
--   fsn:on("modify", function(ev) ... end)
--   fsn:start()
--   ...
--   fsn:cancel()
--
-- Supported events are:
-- * "create"  - emitted with CreatedEvent
-- * "delete"  - emitted with DeletedEvent
-- * "modify"  - emitted with ModifiedEvent
--
local FSNotify = class("FSNotify", EventEmitter(Thread))

--
-- root: Path to a directory to watch.
-- opts: An optional table of options.
--
--   "maxDepth": number
--     The maximum depth of recursive scan. Depth 1 means no recursion. (default: 1)
--
--   "interval": number
--     The interval of polling in seconds. Fractional numbers are allowed. (default: 0.5)
--
--   "reportFiles": boolean
--     Report creations, removals, and modifications of files. (default: true)
--
--   "reportDirs": boolean
--     Report creations, removals, and modifications of directories. (default: false)
--
function FSNotify:__init(root, opts)
    assert(type(root) == "string", "FSNotify:new() expects a path string as its 1st argument")
    assert(opts == nil or type(opts) == "table", "FSNotify:new() expects an optional table as its 2nd argument")

    if opts == nil then
        opts = {}
    end
    assert(
        opts.maxDepth == nil or
        (type(opts.maxDepth) == "number" and opts.maxDepth > 0),
        "FSNotify:new(): maxDepth is expected to be a positive integer")
    assert(
        opts.interval == nil or
        (type(opts.interval) == "number" and opts.interval >= 0),
        "FSNotify:new(): interval is expected to be a non-negative number")
    assert(
        opts.reportFiles == nil or type(opts.reportFiles) == "boolean",
        "FSNotify:new(): reportFiles is expected to be a boolean")
    assert(
        opts.reportDirs == nil or type(opts.reportDirs) == "boolean",
        "FSNotify:new(): reportDirs is expected to be a non-negative number")

    super({"create", "delete", "modify"}, "FSNotify")
    self._root        = root
    self._maxDepth    = opts.maxDepth    or 1
    self._interval    = opts.interval    or 0.5
    self._reportFiles = opts.reportFiles or true
    self._reportDirs  = opts.reportDirs  or false
    self._snapshot    = nil -- Snapshot
    -- Snapshot:
    --   {[name] = {DirEnt, Snapshot} if it's a directory and it's shallow enough,
    --             {DirEnt, nil     } otherwise.
    --   }
end

function FSNotify:_takeSnapshot(dir, depth)
    dir   = dir   or self._root
    depth = depth or 1

    local ret = {}
    for _i, ent in ipairs(fs.readdir(dir)) do
        local pair = {ent, nil}
        if ent.isDirectory and depth <= self._maxDepth then
            pair[2] = self:_takeSnapshot(
                path.join(dir, ent.name),
                depth + 1)
        end
        ret[ent.name] = pair
    end
    return ret
end

function FSNotify:_scanSnapshots(root0, root1)
    -- We compute the differences from ss0 to ss1 in a breadth-first
    -- order. We yield each time we complete a scan of a single directory
    -- so that we won't block the scheduler for too long.
    local dirQ = Queue:new() -- A queue of {snapshot0, snapshot1}
    dirQ:push({root0, root1})

    while dirQ.length > 0 do
        local qPair    = dirQ:shift()
        local ss0, ss1 = qPair[1], qPair[2]

        if ss0 == nil then
            -- Everything in ss1 is a new file or a directory.
            for name, newPair in pairs(ss1) do
                local newEnt, newTree = newPair[1], newPair[2]

                self:_created(newEnt)

                if newTree ~= nil then
                    dirQ:push({nil, newTree})
                end
            end
        elseif ss1 == nil then
            -- Everything in ss0 is a deleted file or a directory.
            for name, oldPair in pairs(ss0) do
                local oldEnt, oldTree = oldPair[1], oldPair[2]

                self:_deleted(oldEnt)

                if oldTree ~= nil then
                    dirQ:push({oldTree, nil})
                end
            end
        else
            for name, newPair in pairs(ss1) do
                local newEnt, newTree = newPair[1], newPair[2]

                -- We are iterating over the newer snapshot. If this DirEnt
                -- does not exist in the older one, it means the file has been
                -- newly created or moved in, which we cannot differentiate.

                local oldPair = ss0[name]
                if oldPair == nil then
                    -- This is either a new file or a new directory.
                    self:_created(newEnt)
                    if newTree ~= nil then
                        dirQ:push({nil, newTree})
                    end
                else
                    -- This entry exists both in the old and the new
                    -- tree. Has it been modified?
                    local oldEnt, oldTree = oldPair[1], oldPair[2]

                    if oldEnt.isDirectory and not newEnt.isDirectory then
                        -- It was once a directory but now isn't.
                        self:_replaced(oldEnt, newEnt)
                        if oldTree ~= nil then
                            dirQ:push({oldTree, nil})
                        end
                    elseif not oldEnt.isDirectory and newEnt.isDirectory then
                        -- It was once a non-directory but now it is.
                        self:_replaced(oldEnt, newEnt)
                        if newTree ~= nil then
                            dirQ:push({nil, newTree})
                        end
                    elseif oldEnt.created ~= newEnt.created then
                        -- These files are most likely different files. It
                        -- is possible to modify the creation time of an
                        -- existing file, but nobody really does that.
                        self:_replaced(oldEnt, newEnt)
                        if oldTree ~= nil then
                            -- newTree must also exist because we don't
                            -- change the maximum depths.
                            assert(newTree ~= nil)
                            dirQ:push({oldTree, newTree})
                        end
                    elseif oldEnt.size         ~= newEnt.size         or
                           oldEnt.lastModified ~= newEnt.lastModified then
                        self:_modified(oldEnt, newEnt)
                        if oldTree ~= nil then
                            -- newTree must also exist because we don't
                            -- change the maximum depths.
                            assert(newTree ~= nil)
                            dirQ:push({oldTree, newTree})
                        end
                    end
                    -- Or the entry has not been changed. There is a catch
                    -- though. Modifying a file without changing any of its
                    -- metadata will cause FSNotify to miss the change. It
                    -- is technically possible to do it because we are only
                    -- polling for changes, but in practice nobody would
                    -- ever be doing that. We could be scanning files and
                    -- computing hashes to detect this, but that would be
                    -- unacceptably slow.

                    -- It's perfectly fine to destroy the old snapshot. We
                    -- intentionally do it here to improve performance.
                    ss0[name] = nil
                end
            end

            -- Anything still in ss0 is a deleted file or a directory.
            for name, oldPair in pairs(ss0) do
                local oldEnt, oldTree = oldPair[1], oldPair[2]

                self:_deleted(oldEnt)

                if oldTree ~= nil then
                    dirQ:push({oldTree, nil})
                end
            end
        end

        if dirQ.length > 0 then
            Thread.yield()
        end
    end
end

function FSNotify:_created(dirEnt)
    if dirEnt.isFile then
        if self._reportFiles then
            self.emit("create", CreatedEvent:new(dirEnt))
        end
    elseif dirEnt.isDirectory then
        if self._reportDirs then
            self.emit("create", CreatedEvent:new(dirEnt))
        end
    end
end

function FSNotify:_deleted(dirEnt)
    if dirEnt.isFile then
        if self._reportFiles then
            self.emit("delete", DeletedEvent:new(dirEnt))
        end
    elseif dirEnt.isDirectory then
        if self._reportDirs then
            self.emit("delete", DeletedEvent:new(dirEnt))
        end
    end
end

function FSNotify:_modified(oldEnt, newEnt)
    if newEnt.isFile then
        assert(oldEnt.isFile)
        if self._reportFiles then
            self.emit("modify", ModifiedEvent:new(oldEnt, newEnt))
        end
    elseif newEnt.isDirectory then
        assert(oldEnt.isDirectory)
        if self._reportDirs then
            self.emit("modify", ModifiedEvent:new(oldEnt, newEnt))
        end
    end
end

function FSNotify:_replaced(oldEnt, newEnt)
    self:_deleted(oldEnt)
    self:_created(newEnt)
end

function FSNotify:run(cancelled)
    self._snapshot = self:_takeSnapshot()

    while true do
        Promise.race({
            cancelled,
            delay(self._interval * 1000)
        }):await()

        local ss1 = self:_takeSnapshot()
        self:_scanSnapshots(self._snapshot, ss1)
        self._snapshot = ss1
    end
end

return FSNotify
