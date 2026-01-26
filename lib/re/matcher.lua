local class = require("class")

local m = {}

--
-- An abstract string matcher.
--
m.Matcher = class("Matcher")
function m.Matcher:matches(_src, _pos, _captured)
    -- src: string
    -- pos: integer
    -- captured: {[idx: integer] = string}
    -- returns integer, the number of consumed octets (not codepoints), or
    --   nil when the match fails.
    error("Subclasses must override :matches()")
end

--
-- Literal matcher
--
m.LiteralMatcher = class("LiteralMatcher", m.Matcher)
function m.LiteralMatcher:__init(str)
    self._str = str
end
function m.LiteralMatcher:__tostring()
    return string.format("Lit %q", self._str)
end
function m.LiteralMatcher:matches(src, pos)
    if string.sub(src, pos, pos + #self._str) == self._str then
        return #self._str
    end
end

return m
