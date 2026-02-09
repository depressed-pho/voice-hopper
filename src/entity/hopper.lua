local cfg = require("config")

local hopper = cfg.schema {
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

return hopper
