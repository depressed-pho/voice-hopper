local CharMap = require("entity/characters/char-map")
local Set     = require("collection/set")
local alc     = require("algebraic")
local class   = require("class")

local Result = alc.data {
    alc.name "Result",
    alc.ctor "NoMatch",
    alc.ctor("Match"    , "char" ), -- Character
    alc.ctor("Ambiguous", "chars")  -- Set<Character>
}

local Classifier = class("Classifier")

Classifier.Result = Result

function Classifier:__init(map)
    assert(CharMap:made(map), "Classifier:new() expects a CharMap")

    self._charMap = map
end

function Classifier:__call(basename)
    assert(type(basename) == "string", "Classifier expects a path basename")

    local matched = Set:new() -- Set<Character>

    for char in self._charMap:values() do
        assert(char.pattern, "Character without a pattern is found in the CharMap: " .. tostring(char))

        if char.pattern:test(basename) then
            matched:add(char)
        end
    end

    if matched.size == 0 then
        return Result.NoMatch:new()

    elseif matched.size == 1 then
        -- luacheck: ignore 512 (loop is executed at most once)
        for char in matched:values() do
            return Result.Match:new(char)
        end
        assert(false)

    else
        return Result.Ambiguous:new(matched)
    end
end

return Classifier
