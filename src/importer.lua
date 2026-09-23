local AbstractImmutableArray = require("collection/array/immutable/base")
local Event                  = require("event/base")
local EventEmitter           = require("event/emitter")
local Set                    = require("collection/set")
local Thread                 = require("thread")
local Voice                  = require("entity/voice")
local class                  = require("class")

local StartedEvent = class("StartedEvent", Event)

local ProgressEvent = class("ProgressEvent", Event)
function ProgressEvent:__init(num_imported, total)
    assert(type(num_imported) == "number" and
           num_imported >= 0 and
           math.floor(num_imported) == num_imported)
    assert(type(total) == "number" and total >= 0 and math.floor(total) == total)
    assert(num_imported <= total)

    super()
    self.num_imported = num_imported -- non-negative integer
    self.total        = total        -- non-negative integer
end

local FinishedEvent = class("FinishedEvent", Event)

local VoiceImporter = class("VoiceImporter", EventEmitter(Thread))

function VoiceImporter:__init(voices, opts)
    assert(AbstractImmutableArray:made(voices),
           "VoiceImporter:new() expects an array of Voice as its 1st argument: " .. tostring(voices))
    for voice in voices:values() do
        assert(Voice:made(voice),
               "VoiceImporter:new() expects an array of Voice as its 1st argument: " .. tostring(voice))
    end

    opts = opts or {}
    assert(type(opts) == "table" and getmetatable(opts) == nil,
           "VoiceImporter:new() expects an optional table as its 2nd argument")

    opts.interactive = opts.interactive or false
    assert(type(opts.interactive) == "boolean",
           "The option `interactive' is expected to be a boolean")

    local events = Set:new {
        "start",    -- StartedEvent
        "progress", -- ProgressEvent
        "finish",   -- FinishedEvent
    }
    super(events, "VoiceImporter")

    self._voices      = voices           -- Voice[]
    self._interactive = opts.interactive -- boolean
end

function VoiceImporter:run()
    self:emit("start", StartedEvent:new()):await()

    local total = self._voices.length
    for i, voice in self._voices:entries() do
        self:emit("progress", ProgressEvent:new(i-1, total)):await()

        -- FIXME
        require("console"):log(voice)
        require("delay")(1.0):await()

        Thread:yield()
    end
    self:emit("progress", ProgressEvent:new(total, total)):await()
    self:emit("finish", FinishedEvent:new()):await()
end

return VoiceImporter
