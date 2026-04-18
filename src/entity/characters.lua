local Array        = require("collection/array")
local RegExp       = require("re")
local Set          = require("collection/set")
local TimelineItem = require("resolve/timeline/item")
local cfg          = require("config")
local class        = require("class")
local path         = require("path")

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

function Character:__tostring()
    local ret = Array:new()
    ret:push("Character {")
    ret:push("pattern = "    , tostring(self.pattern), ", ")
    ret:push("portrait = \"" , self.portrait         , "\", ")
    ret:push("colour = \""   , self.colour           , "\", ")
    ret:push("subtitles = \"", self.subtitles)
    ret:push("}")
    return ret:join("")
end

function Character.__getter:isEmpty()
    return (not self.pattern) and
        (not self.portrait ) and
        (not self.colour   ) and
        (not self.subtitles)
end

function Character.__getter:usesPresetSubtitles()
    -- Not having a property for this also counts as using a preset.
    return (not self.subtitles) or (not path.isAbsolute(self.subtitles))
end

--
-- Private class that reflects the character map in the config object.
--
local CharMap = class("CharMap")

function CharMap:get(key)
    assert(type(key) == "string", "CharMap#get() expects a string key that is a portrait track name")
    local tab = config.fields.characters:get(key)
    if tab then
        return Character:new {
            pattern   = RegExp:new(tab.pattern),
            portrait  = key,
            colour    = tab.colour,
            subtitles = tab.subtitles
        }
    end
end

function CharMap:entries()
    local f, s0, key0 = config.fields.characters:entries()
    return function(s, key)
        local key1, valTab = f(s, key)
        if key1 == nil then
            return nil
        else
            local char = Character:new {
                pattern   = RegExp:new(valTab.pattern),
                portrait  = key1,
                colour    = valTab.colour,
                subtitles = valTab.subtitles
            }
            return key1, char
        end
    end, s0, key0
end

--
-- The collection of character configurations.
--
local Characters = class("Characters")

--
-- Public class: Character
--
Characters.Character = Character

function Characters:__init()
    self._charMap = CharMap:new()
end

function Characters.__getter:position()
    return config.fields.position
end

function Characters.__getter:size()
    return config.fields.size
end

-- Return a dynamic object that (partially) implements the Map interface,
-- mapping from portrait track names (string) to instances of Character.
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
