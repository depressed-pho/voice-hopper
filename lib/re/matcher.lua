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
-- Caret matcher
--
m.CaretMatcher = class("CaretMatcher", m.Matcher)
function m.CaretMatcher:__init(multiline)
    self._multiline = multiline
end
function m.CaretMatcher:__tostring()
    if self._multiline then
        return "^/m"
    else
        return "^"
    end
end

--
-- Dollar matcher
--
m.DollarMatcher = class("DollarMatcher", m.Matcher)
function m.DollarMatcher:__init(multiline)
    self._multiline = multiline
end
function m.DollarMatcher:__tostring()
    if self._multiline then
        return "$/m"
    else
        return "$"
    end
end

--
-- Literal matcher
--
m.LiteralMatcher = class("LiteralMatcher", m.Matcher)
function m.LiteralMatcher:__init(str, ignoreCase)
    if ignoreCase then
        self._str = string.lower(str)
    else
        self._str = str
    end
    self._ignoreCase = ignoreCase
end
function m.LiteralMatcher:__tostring()
    if self._ignoreCase then
        return string.format("Lit/i %q", self._str)
    else
        return string.format("Lit %q", self._str)
    end
end
function m.LiteralMatcher:matches(src, pos)
    local sub = string.sub(src, pos, pos + #self._str)

    if self._ignoreCase then
        -- NOTE: Non-ASCII codepoints are compared case-sensitively atm.
        if string.lower(sub) == self._str then
            return #self._str
        end
    else
        if sub == self._str then
            return #self._str
        end
    end
end

return m
