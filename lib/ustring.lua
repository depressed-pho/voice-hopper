-- luacheck: read_globals utf8
require("shim/utf8")
local Set   = require("collection/set")
local class = require("class")

--
-- String wraps a string primitive, treating it as a UTF-8 octet
-- sequence. It provides an API to manipulate strings in terms of Unicode
-- codepoints instead of octets.
--
local String = class("String")

function String:__init(str)
    self._str = tostring(str)
    self._len = nil -- integer
end

--
-- tostring() returns the wrapped string primitive.
--
function String:__tostring()
    return self._str
end

--
-- The ".." operator concatenates two strings. String objects can be
-- directly concatenated with primitives, in which case the primitive is
-- expected to be a valid UTF-8 octet sequence.
--
function String.__concat(s1, s2)
    assert(type(s1) == "string" or String:made(s1), "Attempted to concatenate a String with non-string")
    assert(type(s2) == "string" or String:made(s2), "Attempted to concatenate a String with non-string")

    return String:new(tostring(s1) .. tostring(s2))
end

--
-- String#length is the number of codepoints in the string.
--
function String.__getter:length()
    if not self._len then
        self._len = utf8.len(self._str)
    end
    return self._len
end

--
-- String#slice() extracts a section of this string and returns it as a new
-- string, without modifying the original string. It extracts up to
-- including "to". "from" is mandatory but "to" is optional.
--
function String:slice(from, to)
    assert(type(from) == "number" and math.floor(from) == from,
           "String#slice() expects an integer as its 1st argument")
    assert(to == nil or (type(to) == "number" and math.floor(to) == to),
           "String#slice() expects an optional integer as its 2nd argument")

    if from < 0 then
        from = math.max(from + self.length + 1, 1)
    end

    local fromO = utf8.offset(self._str, from)
    if not fromO then
        -- Index out of bounds: this is not an error.
        return String:new ""
    end

    if to then
        if to < 0 then
            to = math.max(to + self.length + 1, 1)
        end
        if to < from then
            return String:new ""
        end

        -- We know where the from-th codepoint starts, and we want to know
        -- where the to-th codepoint ends.
        local toO = utf8.offset(self._str, to - from + 2, fromO)
        if toO then
            return String:new(string.sub(self._str, fromO, toO-1))
        end
    end

    return String:new(string.sub(self._str, fromO))
end

local SPACES = Set:new {
    0x0009, -- Character Tabulation
    0x000A, -- Line Feed
    0x000B, -- Line Tabulation
    0x000D, -- Carriage Return
    0x000C, -- Form Feed
    0x0020, -- Space
    0x00A0, -- No-break Space
    0x2028, -- Line Separator
    0x2029, -- Paragraph Separator
    0xFEFF, -- Zero-width No-break Space
    -- Other Unicode Space_Separator characters are very annoying to list
    -- here. Should we somehow embed Unicode data tables in our Lua
    -- scripts?
}

--
-- String#trimStart() removes whitespace from the beginning of this string
-- and returns a new string, without modifying the original string.
--
function String:trimStart()
    for idx, code in utf8.codes(self._str) do
        if not SPACES:has(code) then
            return String:new(string.sub(self._str, idx))
        end
    end
    return String:new ""
end

--
-- String#trimEnd() removes whitespace from the end of this string and
-- returns a new string, without modifying the original string.
--
function String:trimEnd()
    local lastSpaceFrom = nil
    for idx, code in utf8.codes(self._str) do
        if SPACES:has(code) then
            if not lastSpaceFrom then
                lastSpaceFrom = idx
            end
        else
            lastSpaceFrom = nil
        end
    end
    if lastSpaceFrom then
        if lastSpaceFrom > 1 then
            return String:new(string.sub(self._str, 1, lastSpaceFrom - 1))
        else
            return String:new ""
        end
    end
    return String:new(self._str)
end

--
-- String#trim() removes whitespace from both ends of this String and
-- returns a new String, without modifying the original String.
--
function String:trim()
    return self:trimStart():trimEnd()
end

return String
