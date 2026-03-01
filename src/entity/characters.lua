local RegExp       = require("re")
local Set          = require("collection/set")
local TimelineItem = require("resolve/timeline/item")
local cfg          = require("config")
local class        = require("class")
local path         = require("path")

local SET_OF_CLIP_COLOURS = Set:new(TimelineItem.CLIP_COLOURS)

local config = cfg.schema {
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
            cfg.string, -- track name
            {
                pattern   = cfg.regexp,
                colour    = cfg.enum(TimelineItem.CLIP_COLOURS),
                subtitles = cfg.string, -- Absolute path to *.setting, or preset setting ID.
            },
            {} -- FIXME: default characters
        ),
        lastChosenUserSubs = cfg.string, -- Absolute path to *.setting
    }
}

--
-- A character configuration. Not necessarily valid, as required properties
-- can be missing.
--
local Character = class("Character")

function Character:__init(props)
    assert(props == nil or (type(props) == "table" and getmetatable(props) == nil),
           "Character:new() expects an optional table of properties")
    props = props or {}

    assert(props.pattern == nil or RegExp:made(props.pattern),
           "pattern is expected to be an optional RegExp")
    self.pattern = props.pattern

    assert(props.portrait == nil or type(props.portrait) == "string",
           "portrait is expected to be an optional string")
    self.portrait = props.portrait

    assert(props.colour == nil or SET_OF_CLIP_COLOURS:has(props.colour),
           "colour is expected to be an optional known colour name")
    self.colour = props.colour

    assert(props.subtitles == nil or type(props.subtitles) == "string",
           "subtitles is expected to be an optional path string")
    self.subtitles = props.subtitles
end

function Character.__getter:usesPresetSubtitles()
    -- Not having a property for this also counts as using a preset.
    return (not self.subtitles) or (not path.isAbsolute(self.subtitles))
end

--
-- The collection of character configurations.
--
local Characters = class("Characters")

--
-- Public class: Character
--
Characters.Character = Character

function Characters.__getter:position()
    return config.fields.position
end

function Characters.__getter:size()
    return config.fields.size
end

function Characters.__getter:lastChosenUserSubs()
    return config.fields.lastChosenUserSubs
end
function Characters.__setter:lastChosenUserSubs(value)
    config.fields.lastChosenUserSubs = value
end

function Characters:save()
    config:save()
end

return Characters:new() -- This is a singleton class.
