local Event        = require("event/base")
local EventEmitter = require("event/emitter")
local FSNotify     = require("fsnotify")
local Promise      = require("promise")
local Map          = require("collection/map")
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
local KIND_AUDIO    = Symbol("audio")
local KIND_SUBTITLE = Symbol("subtitle")
local KIND_LIPSYNC  = Symbol("lipSync")

-- The set of possible extensions of audio files.
local AUDIO_EXTS = Set:new {
    ".wav",
    ".aac",
    ".mp3",
}

-- The set of possible extensions of subtitle files.
local SUBTITLE_EXTS = Set:new {
    ".txt",
}

-- The set of possible extensions of lip sync files.
local LIPSYNC_EXTS = Set:new {
    ".lab",
}

local function fileKind(parsed)
    local ext = string.lower(parsed.ext)
    if AUDIO_EXTS:has(ext) then
        return KIND_AUDIO
    elseif SUBTITLE_EXTS:has(ext) then
        return KIND_SUBTITLE
    elseif LIPSYNC_EXTS:has(ext) then
        return KIND_LIPSYNC
    else
        return nil
    end
end

-- ----------------------------------------------------------------------------
-- CreatedEvent (public)
-- ----------------------------------------------------------------------------
local CreatedEvent = class("CreatedEvent", Event)

function CreatedEvent:__init(audioEnt, subEnt, labEnt)
    assert(fs.DirEnt:made(audioEnt))
    assert(subEnt == nil or fs.DirEnt:made(subEnt))
    assert(labEnt == nil or fs.DirEnt:made(labEnt))

    -- Public property "audio" is an instance of fs.DirEnt referring to an
    -- audio file of the voice. This property always exists.
    self.audio = audioEnt

    -- Public property "subtitle" is an instance of fs.DirEnt referring to
    -- a subtitle file of the voice. It's nil if the file doesn't exist.
    self.subtitle = subEnt

    -- Public property "lipSync" is an instance of fs.DirEnt referring to a
    -- lip-sync file of the voice. It's nil if the file doesn't exist
    -- (yet).
    self.lipSync = labEnt
end

-- ----------------------------------------------------------------------------
-- DeletedEvent (public)
-- ----------------------------------------------------------------------------
local DeletedEvent = class("DeletedEvent", Event)

function DeletedEvent:__init(audioEnt, subEnt, labEnt)
    assert(fs.DirEnt:made(audioEnt))
    assert(subEnt == nil or fs.DirEnt:made(subEnt))
    assert(labEnt == nil or fs.DirEnt:made(labEnt))

    -- Public property "audio" is an instance of fs.DirEnt referring to the
    -- deleted audio file of the voice. This property always exists.
    self.audio = audioEnt

    -- Public property "subtitle" is an instance of fs.DirEnt referring to
    -- the subtitle file of the voice, which might still exist. It's nil if
    -- we have never observed its existence.
    self.subtitle = subEnt

    -- Public property "lipSync" is an instance of fs.DirEnt referring to
    -- the lip-sync file of the voice, which might still exist. It's nil if
    -- we have never observed its existence.
    self.lipSync = labEnt
end

-- ----------------------------------------------------------------------------
-- KnownVoice (private)
-- ----------------------------------------------------------------------------
local KnownVoice = class("KnownVoice")

function KnownVoice:__init(timeToSettle, timeToGiveUpOnSubs)
    self._timeToSettle       = timeToSettle
    self._timeToGiveUpOnSubs = timeToGiveUpOnSubs
    self._audio              = nil -- {dirEnt: DirEnt, deleted: boolean, updatedAt: Instant}
    self._subtitle           = nil -- ditto
    self._lipSync            = nil -- ditto
    self._discovered         = false
    self._creationReported   = false
    self._deletionReported   = false
end

-- True if the voice has been discovered on our own but has not been
-- notified by FSNotify. Events should not be emitted for those voices.
function KnownVoice.__getter:discovered()
    return self._discovered
end

function KnownVoice:discovered(ent, kind)
    self:created(ent, kind)
    self._discovered = true
end

function KnownVoice:created(ent, kind)
    local file = {
        dirEnt    = ent,
        deleted   = false,
        updatedAt = clock.now()
    }
    if kind == KIND_AUDIO then
        self._audio = file
    elseif kind == KIND_SUBTITLE then
        self._subtitle = file
    elseif kind == KIND_LIPSYNC then
        self._lipSync = file
    else
        error("Unknown kind: "..tostring(kind), 2)
    end
    self._discovered = false
end

-- Deleting a file counts as a sort of modification. We wait indefinitely
-- when a file is deleted, because it may be that the file is going to be
-- recreated soon. We still emit a DeletedEvent when an audio file is
-- deleted after some delay.
function KnownVoice:deleted(ent, kind)
    local file = {
        dirEnt    = ent,
        deleted   = true,
        updatedAt = clock.now()
    }
    if kind == KIND_AUDIO then
        self._audio = file
    elseif kind == KIND_SUBTITLE then
        self._subtitle = file
    elseif kind == KIND_LIPSYNC then
        self._lipSync = file
    else
        error("Unknown kind: "..tostring(kind), 2)
    end
    self._discovered = false
end

function KnownVoice:toCreationReport()
    assert(not self._creationReported)
    assert(not self._discovered)
    assert(self._audio and not self._audio.deleted)

    local audioEnt = self._audio.dirEnt
    local subEnt
    if self._subtitle and not self._subtitle.deleted then
        subEnt = self._subtitle.dirEnt
    end
    local labEnt
    if self._lipSync and not self._lipSync.deleted then
        labEnt = self._lipSync.dirEnt
    end
    return CreatedEvent:new(audioEnt, subEnt, labEnt)
end

function KnownVoice:creationReported()
    self._creationReported = true
    self._deletionReported = false
end

function KnownVoice:toDeletionReport()
    assert(not self._deletionReported)
    assert(self._audio and self._audio.deleted)

    local audioEnt = self._audio.dirEnt
    local subEnt
    if self._subtitle then
        subEnt = self._subtitle.dirEnt
    end
    local labEnt
    if self._lipSync then
        labEnt = self._lipSync.dirEnt
    end
    return DeletedEvent:new(audioEnt, subEnt, labEnt)
end

function KnownVoice:deletionReported()
    self._creationReported = false
    self._deletionReported = true
end

-- We can't rely on our coarse polling to check if files are updated, so
-- recheck the filesystem. Of course the underlying OS caches inodes
-- doesn't it?
function KnownVoice:_update(now)
    local function update(file)
        local oldEnt = file.dirEnt
        local newEnt = fs.stat(oldEnt.path)

        if newEnt == nil or not newEnt.isFile then
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
    if self._audio then
        update(self._audio)
    end
    if self._subtitle then
        update(self._subtitle)
    end
    if self._lipSync then
        update(self._lipSync)
    end
end

-- Return nil if the voice is deleted or incomplete.
function KnownVoice:toTable()
    local now = clock.now()

    if self._deletionReported or self:_deletionDelay(now) == 0 then
        -- It's now gone.
        return nil
    end

    -- If it's a discovered one, consider it complete as long as it has an
    -- audio, because it's very likely that the file was created long
    -- before we discovered it.
    if (self._discovered and self._audio and not self._audio.deleted) or
        self._creationReported or
        (self:_creationDelay(now) == 0) then
        -- It exists and is complete.
        local ret = {
            audio = self._audio.dirEnt
        }
        if self._subtitle and not self._subtitle.deleted then
            ret.subtitle = self._subtitle.dirEnt
        end
        if self._lipSync and not self._lipSync.deleted then
            ret.lipSync = self._lipSync.dirEnt
        end
        return ret
    else
        return nil
    end
end

function KnownVoice:delay(now)
    local cDelay = self:_creationDelay(now)
    if cDelay == 0 then
        return 0, "create"
    end

    local dDelay = self:_deletionDelay(now)
    if dDelay == 0 then
        return 0, "delete"
    end

    return math.min(cDelay, dDelay)
end

-- If this method returns 0, it means the voice is ready to be notified of
-- creation.
function KnownVoice:_creationDelay(now)
    if self._discovered then
        -- We've been aware of this voice since we have discovered it. It's
        -- not that the voice appeared while we're watching the
        -- directory. No creation reports should be emitted in this case.
        return math.huge
    end

    if self._creationReported then
        -- We have already reported the creation of this voice. It
        -- shouldn't be reported again.
        return math.huge
    end

    if not self._audio or self._audio.deleted then
        -- We don't even have an audio. Wait forever.
        return math.huge
    end

    self:_update(now)

    local audioDelta = now - self._audio.updatedAt
    if audioDelta >= self._timeToSettle then
        -- The audio file is complete. How about the subtitle?
        if not self._subtitle or self._subtitle.deleted then
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

    -- Note that we don't wait for lab files to appear, because they are
    -- only needed when we apply lip sync.
end

-- If this method returns 0, it means the voice is ready to be notified of
-- deletion.
function KnownVoice:_deletionDelay(now)
    if self._deletionReported then
        -- We have already reported the deletion of this voice. It
        -- shouldn't be reported again.
        return math.huge
    end

    self:_update(now)

    if not self._audio or not self._audio.deleted then
        -- It's either that we have never observed ths existence of an
        -- audio file, nor its disappearance.
        return math.huge
    end

    local delta = now - self._audio.updatedAt
    if delta >= self._timeToSettle then
        -- The audio is gone and it's not coming back. Consider it really
        -- gone.
        return 0
    else
        -- Wait for it to reappear.
        return self._timeToSettle - delta
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
    opts.maxDepth           = opts.maxDepth           or 8
    opts.interval           = opts.interval           or 0.5
    opts.timeToSettle       = opts.timeToSettle       or 0.3
    opts.timeToGiveUpOnSubs = opts.timeToGiveUpOnSubs or 0.5
    assert(
        type(opts.maxDepth) == "number" and opts.maxDepth > 0,
        "VoiceNotify:new(): maxDepth is expected to be a positive integer")
    assert(
        type(opts.interval) == "number" and opts.interval >= 0,
        "VoiceNotify:new(): interval is expected to be a non-negative number")
    assert(
        type(opts.timeToSettle) == "number" and opts.timeToSettle >= 0,
        "VoiceNotify:new(): timeToSettle is expected to be a non-negative number")
    assert(
        type(opts.timeToGiveUpOnSubs) == "number" and opts.timeToGiveUpOnSubs >= 0,
        "VoiceNotify:new(): timeToGiveUpOnSubs is expected to be a non-negative number")

    local events = Set:new {
        "create", -- CreatedEvent
        "delete", -- DeletedEvent
    }
    super(events, "VoiceNotify")

    self._fsn = FSNotify:new(root, {
        maxDepth    = opts.maxDepth,
        interval    = opts.interval,
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

    self._timeToSettle       = opts.timeToSettle
    self._timeToGiveUpOnSubs = opts.timeToGiveUpOnSubs
    self._hasScannedAll      = false
    self._knownVoices        = Map:new() -- Map<BasePath, KnownVoice>
    -- BasePath is an absolute path without extension.
    self._interrupt          = Notify:new()
end

--
-- VoiceNotify#voices is a non-live Set of tables with the following keys:
--
-- audio:    fs.DirEnt referring to an audio file.
-- subtitle: fs.DirEnt referring to a subtitle file, or nil if no subtitles exist.
-- lipSync:  fs.DirEnt referring to a lab file, or nil if no subtitles exist.
--
function VoiceNotify.__getter:voices()
    if not self._hasScannedAll then
        local seenAny = false
        local function scan(dir, depth)
            for _i, ent in ipairs(fs.readdir(dir)) do
                if ent.isDirectory and depth <= self._fsn.maxDepth then
                    scan(ent.path, depth + 1)
                else
                    -- Is this a file we're interested in?
                    local parsed = path.parse(ent.path)
                    local kind   = fileKind(parsed)
                    if kind then
                        local voice = self:_seen(parsed)
                        voice:discovered(ent, kind)
                        seenAny = true
                    end
                end
            end
        end
        scan(self._fsn.root, 1)

        if seenAny then
            -- We have discovered at least one file we're interested in. Wake
            -- the thread up.
            self._interrupt:notifyOne()
        end
        self._hasScannedAll = true
    end

    local ret = Set:new()
    for voice in self._knownVoices:values() do
        local tab = voice:toTable()
        if tab then
            ret:add(tab)
        end
    end
    return ret
end

function VoiceNotify:_seen(parsed)
    -- Is its base path known to us?
    local basePath = path.join(parsed.dir, parsed.name)
    local voice    = self._knownVoices:get(basePath)
    if not voice then
        -- No we've never seen it.
        voice = KnownVoice:new(self._timeToSettle, self._timeToGiveUpOnSubs)
        self._knownVoices:set(basePath, voice)
    end
    return voice
end

function VoiceNotify:_onCreated(ent)
    local parsed = path.parse(path.join(ent.parentPath, ent.name))

    -- Is this a file we're interested in?
    local kind = fileKind(parsed)
    if not kind then
        return
    end

    local voice = self:_seen(parsed)
    voice:created(ent, kind)
    self._interrupt:notifyOne()
end

function VoiceNotify:_onDeleted(ent)
    -- Some voice-synthesisers such as "VoiSona Talk" deletes existing
    -- files and then recreates them when asked to export all voice clips
    -- in a project. We don't like it but it makes sense to ensure exported
    -- files are up to date. When that happens we must count it as a
    -- modification, not a combination of a deletion and a creation.
    local parsed = path.parse(path.join(ent.parentPath, ent.name))

    -- Is this a file we're interested in?
    local kind = fileKind(parsed)
    if not kind then
        return
    end

    local voice = self:_seen(parsed)
    voice:deleted(ent, kind)
    self._interrupt:notifyOne()
end

function VoiceNotify:_report(voice, what)
    assert(type(what) == "string")

    if what == "create" then
        return self:_reportCreation(voice)
    elseif what == "delete" then
        return self:_reportDeletion(voice)
    else
        error("Invalid value for the argument `what': " .. what)
    end
end

function VoiceNotify:_reportCreation(voice)
    local ev = voice:toCreationReport()

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
        voice:creationReported()
    end)
end

function VoiceNotify:_reportDeletion(voice)
    local ev = voice:toDeletionReport()
    self:emit("delete", ev)
    voice:deletionReported()
end

function VoiceNotify:run(cancelled)
    self._fsn:start()
    fun.finally(
        function()
            while true do
                local now      = clock.now()
                local minDelay = math.huge

                for voice in self._knownVoices:values() do
                    local d, what = voice:delay(now)
                    if d == 0 then
                        self:_report(voice, what)
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
