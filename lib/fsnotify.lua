local EventEmitter = require("event-emitter")
local Promise      = require("promise")
local Thread       = require("thread")
local class        = require("class")
local delay        = require("delay")
local fs           = require("fs")
local path         = require("path")

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
local FSNotify = class("FSNotify", EventEmitter(Thread))

-- root: Path to a directory to watch.
-- opts: An optional table of options.
--   "maxDepth": number
--     The maximum depth of recursive scan. Depth 1 means no recursion. (default: 1)
--   "interval": number
--     The interval of polling in seconds. Fractional numbers are allowed. (default: 1)
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

    super({"create", "delete", "modify"}, "FSNotify")
    self._root     = root
    self._maxDepth = opts.maxDepth or 1
    self._interval = opts.interval or 1
    self._snapshot = nil -- Snapshot
    -- Snapshot:
    --   {[name] = {DirEnt, Snapshot} if it's a directory and it's shallow enough,
    --             {DirEnt, nil     } otherwise.
    --   }
end

function FSNotify:_takeSnapshot(dir, depth)
    if depth > self._maxDepth then
        return nil
    end

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

function FSNotify:run(cancelled)
    self._snapshot = self:_takeSnapshot(self._root, 1)

    while true do
        Promise.race({
            cancelled,
            delay(self._interval * 1000)
        }):await()
        print("FSNotify tick")
    end
end

return FSNotify
