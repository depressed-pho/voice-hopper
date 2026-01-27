local NFA    = require("re/nfa")
local P      = require("parser")
local ast    = require("re/ast")
local class  = require("class")
local pRegex = require("re/parser")

--
-- A regular expression engine, implemented as NFA. Its syntax and
-- semantics is similar to that of ECMAScript and PCRE. It is left-biased,
-- and supports both greedy and non-greedy quantifiers.
--
-- The engine always works on UTF-8 codepoints in a string. There is
-- currently no switches for Unicode-unaware matching. Both patterns and
-- input strings are assumed to be valid UTF-8 strings.
--
local RegExp = class("RegExp")

--
-- RegExp:new(pattern, flags) constructs a RegExp object representing a
-- compiled regular expression from "pattern". The "flags" is an optional
-- string containing any combinations of the following letters:
--
--   * "i": Case-insensitive match. Note that only ASCII characters are
--          compared case-insensitively. Proper Unicode case folding is
--          currently unsupported.
--   * "m": Multiline match. In this mode '^' and '$' meta-characters also
--          matches the beginning and the end of lines.
--   * "s": Dot-all mode. The '.' meta-character also matches CR, LF,
--          U+2028 Line Separator, and U+2029 Paragraph Separator.
--
function RegExp:__init(pattern, flags)
    assert(type(pattern) == "string", "RegExp:new() expects a pattern string as its 1st argument")
    assert(flags == nil or type(flags) == "string", "RegExp:new() expects string flags as its 2nd argument")

    -- Save the pattern here, because recovering a regular expression back
    -- from an NFA is very hard although not impossible.
    self._pat  = pattern
    self._mods = ast.modsToSet(flags or "")

    self._ast  = P.parse(P.finishOff(pRegex), pattern)
    self._ast:optimise()
    self._ast:validate()

    self._nfa  = NFA:new(self._mods, self._ast.root)
    self._nfa:optimise()
end

function RegExp:__tostring()
    return string.format(
        "[RegExp /%s/%s]",
        string.gsub(self._pat, "/", "\\/"),
        ast.modsFromSet(self._mods))
end

--
-- Dump the internal representation of the compiled regular expression to
-- the standard output. The sole purpose of this method is for
-- debugging. Do not use it for anything else. Really, don't.
--
function RegExp:dump()
    local console = require("console")
    console:log(self)
    console:log("parsed as:", self._ast)
    console:log("compiled into:", self._nfa)
end

return RegExp
