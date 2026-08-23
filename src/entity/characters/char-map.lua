local AbstractMap  = require("collection/map/base")
local Character    = require("entity/characters/character")
local RegExp       = require("re")
local class        = require("class")

--
-- Private class that reflects the character map in the config object.
--
local CharMap = class("CharMap", AbstractMap)

function CharMap:__init(config)
    self._config = config
end

function CharMap.__getter:size()
    return self._config.fields.characters.size
end

function CharMap:get(key)
    assert(type(key) == "string", "CharMap#get() expects a string key that is a portrait track name")
    local tab = self._config.fields.characters:get(key)
    if tab then
        return Character:new {
            pattern   = RegExp:new(tab.pattern),
            portrait  = key,
            colour    = tab.colour,
            subtitles = tab.subtitles
        }
    end
end

function CharMap:has(key)
    assert(type(key) == "string", "CharMap#has() expects a string key that is a portrait track name")
    return self._config.fields.characters:has(key)
end

function CharMap:put(val)
    assert(Character:made(val), "CharMap#put() expects a Character object")
    self._config.fields.characters:set(
        val.portrait,
        {
            pattern   = val.pattern.source,
            colour    = val.colour,
            subtitles = val.subtitles
        })
end

function CharMap:set()
    error("CharMap does not implement a method :set(). Use :put() instead", 2)
end

function CharMap:clear()
    self._config.fields.characters:clear()
    return self
end

function CharMap:delete(key)
    assert(type(key) == "string", "CharMap#delete() expects a string key that is a portrait track name")
    return self._config.fields.characters:delete(key)
end

function CharMap:keys()
    return self._config.fields.characters:keys()
end

function CharMap:entries()
    return coroutine.wrap(
        function ()
            for key, tab in self._config.fields.characters:entries() do
                coroutine.yield(
                    key,
                    Character:new {
                        pattern   = RegExp:new(tab.pattern),
                        portrait  = key,
                        colour    = tab.colour,
                        subtitles = tab.subtitles
                    })
            end
        end)
end

return CharMap
