local Array        = require("collection/array")
local RegExp       = require("re")
local Set          = require("collection/set")
local TimelineItem = require("resolve/timeline/item")
local class        = require("class")
local path         = require("path")

local SET_OF_CLIP_COLOURS = Set:new(TimelineItem.CLIP_COLOURS:values())

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
    -- FIXME: colour is nil when it's None, but this prints it as "nil". We
    -- should really implement a proper pretty-printer.
    ret:push("colour = \""   , self.colour           , "\", ")
    ret:push("subtitles = \"", self.subtitles        , "\"")
    ret:push("}")
    return ret:join ""
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

return Character
