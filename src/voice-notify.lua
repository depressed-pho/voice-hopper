local EventEmitter = require("event-emitter")
local FSNotify     = require("fsnotify")
local Promise      = require("promise")
local Notify       = require("sync/notify")
local Set          = require("collection/set")
local Symbol       = require("symbol")
local Thread       = require("thread")
local class        = require("class")
local clock        = require("clock")
local delay        = require("delay")
local fs           = require("fs")
local fun          = require("function")
local path         = require("path")
local spawn        = require("thread/spawn")

-- ----------------------------------------------------------------------------
-- Constants (private)
-- ----------------------------------------------------------------------------
local KIND_AUDIO      = Symbol("audio")
local KIND_SUBTITLE   = Symbol("subtitle")

-- The set of possible extensions of audio files.
local AUDIO_EXTS = {
    [".wav"] = true,
    [".aac"] = true,
    [".mp3"] = true,
}

-- The set of possible extensions of subtitle files.
local SUBTITLE_EXTS = {
    [".txt"] = true,
}

-- NOTE: VoiceNotify ignores .lab files because they aren't needed until
-- lip sync is applied.

local function fileKind(parsed)
    local ext = string.lower(parsed.ext)

    local pref = AUDIO_EXTS[ext]
    if pref ~= nil then
        return KIND_AUDIO
    end

    local pref = SUBTITLE_EXTS[ext]
    if pref ~= nil then
        return KIND_SUBTITLE
    end

    return nil
end

-- ----------------------------------------------------------------------------
-- CreatedEvent (public)
-- ----------------------------------------------------------------------------
local CreatedEvent = class("CreatedEvent")

function CreatedEvent:__init(audioEnt, subEnt)
    assert(fs.DirEnt:made(audioEnt))
    assert(subEnt == nil or fs.DirEnt:made(subEnt))

    -- Public property "audio" is an instance of fs.DirEnt referring to an
    -- audio file of the voice. This property always exists.
    self.audio = audioEnt

    -- Public property "subtitle" is an instance of fs.DirEnt referring to
    -- a subtitle file of the voice. It's nil if the file doesn't exist.
    self.subtitle = subEnt
end

-- ----------------------------------------------------------------------------
-- KnownVoice (private)
-- ----------------------------------------------------------------------------
local KnownVoice = class("KnownVoice")

function KnownVoice:__init(timeToSettle, timeToGiveUpOnSubs)
    self._timeToSettle       = timeToSettle
    self._timeToGiveUpOnSubs = timeToGiveUpOnSubs
    self._audio              = nil
    self._subtitle           = nil
    self._reported           = false
end

function KnownVoice:created(ent, kind)
    if self._reported then
        return
    end

    if kind == KIND_AUDIO then
        self._audio = {
            dirEnt    = ent,
            deleted   = false,
            updatedAt = clock.now()
        }
    elseif kind == KIND_SUBTITLE then
        self._subtitle = {
            dirEnt    = ent,
            deleted   = false,
            updatedAt = clock.now()
        }
    else
        error("Unknown kind: "..tostring(kind), 2)
    end
end

-- Deleting a file counts as a sort of modification. We wait indefinitely
-- when a file is deleted, because it may be that the file is going to be
-- recreated soon.
function KnownVoice:deleted(ent, kind)
    if self._reported then
        return
    end

    if kind == KIND_AUDIO then
        self._audio = {
            dirEnt    = ent,
            deleted   = true,
            updatedAt = clock.now()
        }
    elseif kind == KIND_SUBTITLE then
        self._subtitle = {
            dirEnt    = ent,
            deleted   = true,
            updatedAt = clock.now()
        }
    else
        error("Unknown kind: "..tostring(kind), 2)
    end
end

function KnownVoice:toReport()
    assert(not self._reported)
    assert(self._audio ~= nil and not self._audio.deleted)

    local audioEnt = self._audio.dirEnt
    local subEnt
    if self._subtitle ~= nil and not self._subtitle.deleted then
        subEnt = self._subtitle.dirEnt
    end
    return CreatedEvent:new(audioEnt, subEnt)
end

function KnownVoice:reported()
    self._reported = true

    -- We don't need these data anymore. Free up the memory.
    self._audio    = nil
    self._subtitle = nil
end

-- We can't rely on our coarse polling to check if files are updated, so
-- recheck the filesystem. Of course the underlying OS caches inodes
-- doesn't it?
function KnownVoice:_update(now)
    assert(not self._reported)

    local function update(file)
        local oldEnt = file.dirEnt
        local newEnt = fs.stat(oldEnt.path)

        if newEnt == nil or not newEnt.isFile() then
            -- The file is no longer there!
            file.deleted   = true
            file.updatedAt = now
        elseif oldEnt.lastModified ~= newEnt.lastModified or
               oldEnt.size         ~= newEnt.size         then
            -- The file has been presumably updated. We purposely don't
            -- compare their creation time because it might have been
            -- recreated from scratch.
            file.dirEnt    = newEnt
            file.deleted   = false
            file.updatedAt = now
        end
    end
    if self._audio ~= nil then
        update(self._audio)
    end
    if self._subtitle ~= nil then
        update(self._subtitle)
    end
end

-- If this method returns 0, it means the voice is ready to be notified.
function KnownVoice:delay(now)
    if self._reported then
        -- We have already reported this voice. No additional work is
        -- required.
        return math.huge
    end

    if self._audio == nil or self._audio.deleted then
        -- We don't even have an audio. Wait forever.
        return math.huge
    end

    self._update(now)

    local audioDelta = now - self._audio.updatedAt
    if audioDelta >= self._timeToSettle then
        -- The audio file is complete. How about the subtitle?
        if self._subtitle == nil or self._subtitle.deleted then
            -- We don't have any.
            if audioDelta >= self._timeToGiveUpOnSubs then
                -- And we should give up now. We don't wait indefinitely
                -- even when it had previously shown up but then
                -- deleted. Because the producer of the file might have
                -- decided not to generate a subtitle.
                return 0
            else
                -- Wait for one to appear.
                return self._timeToGiveUpOnSubs - audioDelta
            end
        else
            -- We have a subtitle, but is it complete?
            local subDelta = now - self._subtitle.updatedAt
            if subDelta >= self._timeToSettle then
                -- It is.
                return 0
            else
                -- Wait for it to complete.
                return self._timeToSettle - subDelta
            end
        end
    else
        -- Wait for it to complete.
        return self._timeToSettle - audioDelta
    end
end

-- ----------------------------------------------------------------------------
-- VoiceNotify (public)
-- ----------------------------------------------------------------------------
--
-- VoiceNotify is a subclass of Thread and EventEmitter. It is a wrapper of
-- FSNotify that is specialised for watching voice clips.
--
-- "create" is the only event VoiceNotify emits. It is emitted with
-- CreatedEvent.
--
local VoiceNotify = class("VoiceNotify", EventEmitter(Thread))
VoiceNotify.CreatedEvent = CreatedEvent -- Export it.

--
-- root: Path to a directory to watch.
-- opts: An optional table of options.
--
--   "maxDepth": number
--     The maximum depth of recursive scan. Depth 1 means no recursion. (default: 8)
--
--   "interval": number
--     The interval of polling in seconds. Fractional numbers are allowed. (default: 0.5)
--
--   "timeToSettle": number
--     The number of seconds before a newly created file is considered
--     settled. Voice-synthesising software might create files by
--     repeatedly appending data to them, and VoiceNotify waits for this
--     duration before considering them complete. Fractional numbers are
--     allowed. (default: 0.3)
--
--   "timeToGiveUpOnSubs": number
--     The number of seconds before giving up on missing subtitle
--     files. Voice-synthesising software might create audio files without
--     their corresponding subtitle files, and we don't want to wait
--     forever. Fractional numbers are allowed. (default: 0.5)
--
function VoiceNotify:__init(root, opts)
    assert(type(root) == "string", "VoiceNotify:new() expects a path string as its 1st argument")
    assert(opts == nil or type(opts) == "table", "VoiceNotify:new() expects an optional table as its 2nd argument")

    if opts == nil then
        opts = {}
    end
    assert(
        opts.maxDepth == nil or
        (type(opts.maxDepth) == "number" and opts.maxDepth > 0),
        "VoiceNotify:new(): maxDepth is expected to be a positive integer")
    assert(
        opts.interval == nil or
        (type(opts.interval) == "number" and opts.interval >= 0),
        "VoiceNotify:new(): interval is expected to be a non-negative number")
    assert(
        opts.timeToSettle == nil or
        (type(opts.timeToSettle) == "number" and opts.timeToSettle >= 0),
        "VoiceNotify:new(): timeToSettle is expected to be a non-negative number")
    assert(
        opts.timeToGiveUpOnSubs == nil or
        (type(opts.timeToGiveUpOnSubs) == "number" and opts.timeToGiveUpOnSubs >= 0),
        "VoiceNotify:new(): timeToGiveUpOnSubs is expected to be a non-negative number")

    super(Set:new {"create"}, "VoiceNotify")

    self._fsn = FSNotify:new(root, {
        maxDepth    = opts.maxDepth or 8,
        interval    = opts.interval or 0.5,
        reportFiles = true,
        reportDirs  = false,
    })
    self._fsn:on("create", function(ev)
        self:_onCreated(ev.entry)
    end)
    self._fsn:on("delete", function(ev)
        self:_onDeleted(ev.entry)
    end)
    self._fsn:on("modify", function(ev)
        -- We can handle this identically to file creation.
        self:_onCreated(ev.entry)
    end)
    -- Disable the default error handler. We want to handle it in our own
    -- way.
    self._fsn.onUnhandledError = nil

    self._timeToSettle       = opts.timeToSettle       or 0.3
    self._timeToGiveUpOnSubs = opts.timeToGiveUpOnSubs or 0.5

    self._knownVoices = {} -- {[basePath] = KnownVoice}
    -- basePath is an absolute path without extension.

    self._interrupt = Notify:new()
end

function VoiceNotify:_seen(parsed)
    -- Is its base path known to us?
    local basePath = path.join(parsed.dir, parsed.name)
    local voice    = self._knownVoices[basePath]
    if voice == nil then
        -- No we've never seen it.
        voice = KnownVoice:new(self._timeToSettle, self._timeToGiveUpOnSubs)
        self._knownVoices[basePath] = voice
    end
    return voice
end

function VoiceNotify:_onCreated(ent)
    local parsed = path.parse(path.join(ent.parentPath, ent.name))

    -- Is this a file we're interested in?
    local kind = fileKind(parsed)
    if kind == nil then
        return
    end

    local voice = self:_seen(parsed)
    voice:created(ent, kind)
    self._interrupt:notifyOne()
end

function VoiceNotify:_onDeleted(ent)
    -- Some voice-synthesisers such as "VoiSona Talk" deletes existing
    -- files and then recreates them when asked to export all voice clips
    -- in a project. We don't like it but it makes sense to do it to ensure
    -- exported files are up to date. When that happens we must count it as
    -- a modification, not a combination of a deletion and a creation.
    local parsed = path.parse(path.join(ent.parentPath, ent.name))

    -- Is this a file we're interested in?
    local kind = fileKind(parsed)
    if kind == nil then
        return
    end

    local voice = self:_seen(parsed)
    voice:deleted(ent, kind)
    self._interrupt:notifyOne()
end

function VoiceNotify:_report(voice)
    local ev = voice:toReport()

    -- On Windows, when a process holds a writable handle to a file, the
    -- file is exclusively locked and no other processes can read it or
    -- even rename it. So we spawn a separate thread that waits until all
    -- files constituting the voice are unlocked. We only strictly need to
    -- do this on Windows but it's mostly harmless on any other OSes.
    local function waitUnlock(p)
        while true do
            local file = io.open(p, "rb")
            if file then
                return
            else
                delay(0.1):await()
            end
        end
    end
    spawn("wait unlock: " .. ev.audio.path, function()
        waitUnlock(ev.audio.path)
        if ev.subtitle ~= nil then
            waitUnlock(ev.subtitle.path)
        end
        -- Okay, files are unlocked.
        self:emit("create", ev)
        voice:reported()
    end)
end

function VoiceNotify:run(cancelled)
    self._fsn:start()
    fun.finally(
        function()
            while true do
                local now      = clock.now()
                local minDelay = math.huge

                for _basePath, voice in pairs(self._knownVoices) do
                    local d = voice:delay(now)
                    if d == 0 then
                        self:_report(voice)
                    else
                        minDelay = math.min(minDelay, d)
                    end
                end

                local ps = {
                    cancelled,                  -- Will reject when the thread is cancelled.
                    self._interrupt:notified(), -- Will resolve when a new event is arrived.
                    delay(minDelay),            -- Will resolve when a certain period of time is passed.
                    self._fsn:join(),           -- Will reject when FSNotify dies.
                }
                -- This will raise some special error object when
                -- "cancelled" is rejected, which is fine. We're also not
                -- interested in the fulfilled value.
                Promise:race(ps):await()
            end
        end,
        function()
            self._fsn:cancel():join():await()
        end)
end

return VoiceNotify
