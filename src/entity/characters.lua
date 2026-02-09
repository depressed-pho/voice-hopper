local TimelineItem = require("resolve/timeline/item")
local cfg          = require("config")

local chars = cfg.schema {
    path    = "VoiceHopper/Characters",
    version = "1.0.0",
    fields  = {
        position = {
            x = cfg.number,
            y = cfg.number,
        },
        size = {
            w = cfg.number(600),
            h = cfg.number(600),
        },
        characters = cfg.table(
            cfg.string,
            {
                pattern  = cfg.regexp,
                colour   = cfg.enum(TimelineItem.CLIP_COLOURS),
                subtitle = cfg.string, -- Path to *.setting
            },
            {}
        )
    }
}

return chars
