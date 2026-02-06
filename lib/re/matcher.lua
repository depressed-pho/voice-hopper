-- luacheck: read_globals utf8
require("shim/utf8")
local class = require("class")

local CODE_0          = string.byte "0"
local CODE_9          = string.byte "9"
local CODE_UPPER_A    = string.byte "A"
local CODE_UPPER_Z    = string.byte "Z"
local CODE_LOWER_A    = string.byte "a"
local CODE_LOWER_Z    = string.byte "z"
local CODE_UNDERSCORE = string.byte "_"
local function isWordChar(code)
    return (code >= CODE_0       and code <= CODE_9      ) or
           (code >= CODE_UPPER_A and code <= CODE_UPPER_Z) or
           (code >= CODE_LOWER_A and code <= CODE_LOWER_Z) or
            code == CODE_UNDERSCORE
end

local m = {}

--
-- An abstract string matcher.
--
m.Matcher = class("Matcher")
-- src: string
-- pos: integer
-- groups: Groups
-- returns integer, the number of consumed octets (not codepoints), or nil
--   when the match fails. When the matcher is reversed the result will be
--   negative.
m.Matcher:abstract("matches")

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
            local off = utf8.offset(src, -1, pos)
            assert(off, "There must always be a valid UTF-8 codepoint right before pos")
            local code = utf8.codepoint(src, off)
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
function m.LiteralMatcher:__init(str, ignoreCase, reverse)
    if ignoreCase then
        self._str = string.lower(str)
    else
        self._str = str
    end
    self._ignoreCase = ignoreCase
    self._reverse    = reverse
end
function m.LiteralMatcher:__tostring()
    return table.concat {
        "Lit",
        ((self._ignoreCase or self._reverse) and "/") or "",
        (self._ignoreCase and "i") or "",
        (self._reverse    and "R") or "",
        " ",
        string.format("%q", self._str)
    }
end
function m.LiteralMatcher:matches(src, pos)
    local sub, sign
    if self._reverse then
        if pos-1 < #self._str then
            return -- An obvious case of failure
        end
        sub  = string.sub(src, pos - #self._str, pos - 1)
        sign = -1
    else
        sub  = string.sub(src, pos, pos + #self._str - 1)
        sign = 1
    end

    if self._ignoreCase then
        -- NOTE: Non-ASCII codepoints are compared case-sensitively atm.
        if string.lower(sub) == self._str then
            return #self._str * sign
        end
    else
        if sub == self._str then
            return #self._str * sign
        end
    end
end

--
-- Backreference matcher
--
m.BackrefMatcher = class("BackrefMatcher", m.Matcher)
function m.BackrefMatcher:__init(ref, reverse)
    self._ref     = ref     -- integer or string
    self._reverse = reverse -- boolean
end
function m.BackrefMatcher:__tostring()
    local flags = (self._reverse and "/R") or ""
    if type(self._ref) == "number" then
        return string.format("Ref%s %d", flags, self._ref)
    else
        return string.format("Ref%s <%s>", flags, self._ref)
    end
end
function m.BackrefMatcher:matches(src, pos, groups)
    local captured = groups:substringFor(self._ref)
    if captured then
        local sub, sign
        if self._reverse then
            if pos-1 < #captured then
                return -- An obvious case of failure
            end
            sub  = string.sub(src, pos - #captured, pos - 1)
            sign = -1
        else
            sub  = string.sub(src, pos, pos + #captured - 1)
            sign = 1
        end
        if sub == captured then
            return #captured * sign
        end
    end
end

--
-- Class matcher
--
m.ClassMatcher = class("ClassMatcher", m.Matcher)
function m.ClassMatcher:__init(charClass, ignoreCase, reverse)
    if ignoreCase then
        self._class = charClass:caseIgnored()
    else
        self._class = charClass
    end
    self._ignoreCase = ignoreCase
    self._reverse    = reverse
end
function m.ClassMatcher:__tostring()
    return table.concat {
        ((self._ignoreCase or self._reverse) and "/") or "",
        (self._ignoreCase and "i") or "",
        (self._reverse    and "R") or "",
        ((self._ignoreCase or self._reverse) and " ") or "",
        tostring(self._class)
    }
end
function m.ClassMatcher:matches(src, pos)
    if self._reverse then
        if pos > 1 then
            local off = utf8.offset(src, -1, pos)
            assert(off, "There must always be a valid UTF-8 codepoint right before pos")
            local code = utf8.codepoint(src, off)

            if self._ignoreCase then
                -- Wrong, but...
                code = utf8.codepoint(string.lower(utf8.char(code)))
            end

            if self._class:contains(code) then
                return off - pos
            end
        end
    else
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
end

--
-- Wildcard matcher
--
m.WildcardMatcher = class("WildcardMatcher", m.Matcher)
function m.WildcardMatcher:__init(dotAll, reverse)
    self._dotAll  = dotAll
    self._reverse = reverse
end
function m.WildcardMatcher:__tostring()
    return table.concat {
        ".",
        ((self._dotAll or self._reverse) and "/") or "",
        (self._dotAll  and "s") or "",
        (self._reverse and "R") or "",
    }
end
function m.WildcardMatcher:matches(src, pos)
    if self._reverse then
        if pos > 1 then
            local off = utf8.offset(src, -1, pos)
            assert(off, "There must always be a valid UTF-8 codepoint right before pos")

            if not self._dotAll then
                local code = utf8.codepoint(src, off)
                if code == 0x000A or code == 0x000D or
                   code == 0x2028 or code == 0x2029 then
                    return
                end
            end

            return off - pos
        end
    else
        if pos <= #src then
            if not self._dotAll then
                local octet = string.byte(src, pos)
                if octet == 0x0A or octet == 0x0D then
                    -- Failure: this is a newline character and it's not in
                    -- the /s mode.
                    return
                end
                local code = utf8.codepoint(src, pos)
                if code == 0x2028 or code == 0x2029 then
                    -- Failure: it's either Line separator or Paragraph
                    -- separator.
                    return
                end
            end
            local off = utf8.offset(src, 2, pos)
            return (off or #src + 1) - pos
        end
    end
end

--
-- Lookaround matcher
--
m.LookaroundMatcher = class("LookaroundMatcher", m.Matcher)
function m.LookaroundMatcher:__init(positive, ahead, nfa)
    self._positive = positive
    self._ahead    = ahead
    self._nfa      = nfa
    assert(
        (ahead and not nfa.isReversed) or (not ahead and nfa.isReversed),
        "Reversed NFA for lookahead matching, or vice versa, is certainly a mistake")
end
function m.LookaroundMatcher:__tostring()
    return table.concat {
        (self._positive and "=") or "!",
        (self.ahead and "La: ") or "Lb: ",
        tostring(self._nfa)
    }
end
function m.LookaroundMatcher:matches(src, pos, groups)
    local matched = self._nfa:exec(src, pos, groups)
    if self._positive then
        if matched then
            return 0
        end
    else
        if not matched then
            return 0
        end
    end
end

--
-- Word boundary matcher
--
m.WordBoundaryMatcher = class("WordBoundaryMatcher", m.Matcher)
function m.WordBoundaryMatcher:__init(positive)
    self._positive = positive
end
function m.WordBoundaryMatcher:__tostring()
    if self._positive then
        return "=Word"
    else
        return "!Word"
    end
end
function m.WordBoundaryMatcher:matches(src, pos)
    if pos == 1 or pos >= #src then
        -- Obvious success
        return 0
    else
        -- No support of Unicode characters, which means we only need to
        -- check the current and the previous octets.
        local prev , cur  = string.byte(src, pos-1, pos)
        local wPrev, wCur = isWordChar(prev), isWordChar(cur)
        if self._positive then
            if (wPrev and not wCur) or (not wPrev and wCur) then
                return 0
            end
        else
            if (wPrev and wCur) or (not wPrev and not wCur) then
                return 0
            end
        end
    end
end

return m
