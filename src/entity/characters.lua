local Character    = require("entity/characters/character")
local CharMap      = require("entity/characters/char-map")
local Classifier   = require("entity/characters/classifier")
local Set          = require("collection/set")
local TimelineItem = require("resolve/timeline/item")
local cfg          = require("config")
local class        = require("class")

local SET_OF_CLIP_COLOURS = Set:new(TimelineItem.CLIP_COLOURS:values())

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
            h = cfg.number(480),
        },
        characters = cfg.table(
            cfg.string, -- track name
            {
                pattern   = cfg.regexp,
                colour    = cfg.enum(SET_OF_CLIP_COLOURS),
                subtitles = cfg.string, -- Absolute path to *.setting, or preset setting ID.
            },
            {
                Metan = {
                    pattern   = [[^\d+_四国めたん.+]],
                    colour    = "Violet",
                    subtitles = "white-on-magenta"
                },
                Zundamon = {
                    pattern   = [[^\d+_ずんだもん.+]],
                    colour    = "Lime",
                    subtitles = "white-on-magenta" -- FIXME: change the default
                },
                -- FIXME: More default characters
            }
        ),
        lastChosenUserSubs = cfg.string, -- Absolute path to *.setting
    }
}

--
-- The collection of character configurations.
--
local Characters = class("Characters")

--
-- Public class: Character
--
Characters.Character = Character

function Characters:__init()
    self._charMap = CharMap:new(config)
end

function Characters.__getter:classifier()
    return Classifier:new(self._charMap)
end

function Characters.__getter:position()
    return config.fields.position
end

function Characters.__getter:size()
    return config.fields.size
end

-- Return a live object that implements the Map interface, mapping from
-- portrait track names (string) to instances of Character. The returned
-- object does not have the method :set(key, val) but instead has
-- :put(val).
function Characters.__getter:map()
    return self._charMap
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
