-- luacheck: read_globals utf8
require("shim/utf8")
local class = require("class")

local m = {}

--
-- An abstract string matcher.
--
m.Matcher = class("Matcher")
function m.Matcher:matches(_src, _pos, _groups)
    -- src: string
    -- pos: integer
    -- groups: Groups
    -- returns integer, the number of consumed octets (not codepoints), or
    --   nil when the match fails.
    error("Subclasses must override :matches(): " .. tostring(self))
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
function m.CaretMatcher:matches(src, pos)
    if pos == 1 then
        -- Obvious success
        return 0
    elseif self._multiline then
        -- Succeed if a newline character precedes the current position.
        local lastB = string.byte(src, pos - 1)
        if lastB == 0x0A or lastB == 0x0D then
            -- Success
            return 0
        else
            local pos1 = utf8.offset(src, -1, pos)
            assert(pos1, "There must always be a valid UTF-8 codepoint right before pos")
            local code = utf8.codepoint(src, pos1)
            if code == 0x2028 or code == 0x2029 then
                -- It's either Line separator or Paragraph
                -- separator. Succeed as well.
                return 0
            end
        end
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
function m.DollarMatcher:matches(src, pos)
    if pos == #src + 1 then
        -- Obvious success
        return 0
    elseif self._multiline then
        -- Succeed if a newline character is at the current position.
        local lastB = string.byte(src, pos)
        if lastB == 0x0A or lastB == 0x0D then
            -- Success
            return 0
        else
            local code = utf8.codepoint(src, pos)
            if code == 0x2028 or code == 0x2029 then
                -- It's either Line separator or Paragraph
                -- separator. Succeed as well.
                return 0
            end
        end
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
    local sub = string.sub(src, pos, pos + #self._str - 1)

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

--
-- Backreference matcher
--
m.BackrefMatcher = class("BackrefMatcher", m.Matcher)
function m.BackrefMatcher:__init(ref)
    self._ref = ref -- integer or string
end
function m.BackrefMatcher:__tostring()
    if type(self._ref) == "number" then
        return string.format("Ref %d", self._ref)
    else
        return string.format("Ref <%s>", self._ref)
    end
end
function m.BackrefMatcher:matches(src, pos, groups)
    local captured = groups:substringFor(self._ref)
    if captured then
        local found = string.sub(src, pos, pos + #captured - 1)
        if found == captured then
            return #captured
        end
    end
end

--
-- Class matcher
--
m.ClassMatcher = class("ClassMatcher", m.Matcher)
function m.ClassMatcher:__init(charClass, ignoreCase)
    if ignoreCase then
        self._class = charClass:caseIgnored()
    else
        self._class = charClass
    end
    self._ignoreCase = ignoreCase
end
function m.ClassMatcher:__tostring()
    if self._ignoreCase then
        return "/i " .. tostring(self._class)
    else
        return tostring(self._class)
    end
end
function m.ClassMatcher:matches(src, pos)
    if pos <= #src then
        local code = utf8.codepoint(src, pos)
        if self._ignoreCase then
            -- Wrong, but...
            code = utf8.codepoint(string.lower(utf8.char(code)))
        end

        if self._class:contains(code) then
            local off = utf8.offset(src, 2, pos)
            return (off or #src + 1) - pos
        end
    end
end

return m
