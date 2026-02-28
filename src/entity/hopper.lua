local cfg   = require("config")
local class = require("class")

local config = cfg.schema {
    path    = "VoiceHopper/Hopper",
    version = "1.0.0",
    fields  = {
        position = {
            x = cfg.number,
            y = cfg.number,
        },
        size = {
            w = cfg.number(330),
            h = cfg.number(550),
        },
        -- Invariant: "watching" is always false if "watchDir" is missing.
        watchDir     = cfg.string,
        watching     = cfg.boolean(false),
        gaps         = cfg.nonNegInteger(15),
        subExt       = cfg.nonNegInteger(15),
        useClipboard = cfg.boolean(true),
    }
}

local VoiceHopper = class("VoiceHopper")

function VoiceHopper.__getter:position()
    return config.fields.position
end

function VoiceHopper.__getter:size()
    return config.fields.size
end

function VoiceHopper.__getter:watchDir()
    return config.fields.watchDir
end
function VoiceHopper.__setter:watchDir(val)
    config.fields.watchDir = val
end

function VoiceHopper.__getter:watching()
    return config.fields.watching
end
function VoiceHopper.__setter:watching(val)
    assert((val and config.fields.watchDir) or not val,
           "Invariant: watching is always false if watchDir is missing")
    config.fields.watching = val
end

function VoiceHopper.__getter:gaps()
    return config.fields.gaps
end
function VoiceHopper.__setter:gaps(val)
    config.fields.gaps = val
end

function VoiceHopper.__getter:subExt()
    return config.fields.subExt
end
function VoiceHopper.__setter:subExt(val)
    config.fields.subExt = val
end

function VoiceHopper.__getter:useClipboard()
    return config.fields.useClipboard
end
function VoiceHopper.__setter:useClipboard(val)
    config.fields.useClipboard = val
end

function VoiceHopper:save()
    config:save()
end

return VoiceHopper:new() -- This is a singleton class.
