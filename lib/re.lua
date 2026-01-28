local Array  = require("collection/array")
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
-- Instances of RegExp are immutable once they are created, but don't even
-- think of serialising them. They aren't guaranteed to survive
-- serialisation.
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

--
-- RegExp#exec(str, opts) executes a search with this regular expression
-- for a match in a specified string and returns a result array, or nil.
--
-- Supported options are:
--
--   * "start" (positive integer): The 1-based starting byte position of
--     the search. 1 by default. The RegExp object is stateless, unlike
--     ECMAScript, so if you want to iterate over multiple occurences of
--     matching substrings you need to give it a starting position
--     explicitly.
--
--   * "indices" (boolean): The resulting array will have an additional
--     property "indices" when this option is set to true.
--
-- If the match fails, the method returns nil. If it succeeds, it returns
-- an Array, whose first element is the matched text and then one element
-- for each capturing group (named or not) of the matched text. The array
-- also has the following additional properties:
--
--   * "groups" (table): A table of named capturing groups, whose keys are
--     the names, and values are captured substrings. This property is
--     absent if the regular expression doesn't have any named capturing
--     groups.
--
--   * "indices" (Array): This property is only present when the "indices"
--     option is set. It is an array where each entry represents the bounds
--     of a substring match. The first entry represents the entire match,
--     the second entry represents the first capturing group, and so
--     on. Each entry is a two-element sequence, where the first number
--     represents the match's start index, and the second number, its end
--     index. Both indices are inclusive and 1-based.
--
--     The indices array additionally has a "groups" property, which holds
--     a table of all named capturing groups. The keys are the names of the
--     capturing groups, and each value is a two-element sequence, with the
--     first number being the start index, and the second number being the
--     end index of the capturing group. If the regular expression doesn't
--     contain any named capturing groups, "groups" is absent.
--
function RegExp:exec(str, opts)
    assert(type(str) == "string", "RegExp#exec() expects a string as its 1st argument")
    assert(opts == nil or type(opts) == "table", "RegExp#exec() expects an optional table as its 2nd argument")

    opts         = opts         or {}
    opts.start   = opts.start   or 1
    opts.indices = opts.indices or false

    for pos = opts.start, #str do
        local from, to, groups = self._nfa:exec(str, pos)
        if from then
            -- Successful match
            local m = Array:of(string.sub(str, from, to))
            for i=1, self._ast.numCapGroups do
                local range = groups[i]
                if range[1][1] then
                    -- Successfully captured something.
                    m[i+1] = string.sub(str, range[1][1], range[2])
                end
            end
            if self._ast.namedCapGroups.size > 0 then
                local groups1 = {}
                for name, idx in self._ast.namedCapGroups:entries() do
                    groups1[name] = m[idx + 1]
                end
                rawset(m, "groups", groups1)
            end
            if opts.indices then
                local indices = Array:of({from, to})
                for i=1, self._ast.numCapGroups do
                    local range = groups[i]
                    if range[1][1] then
                        indices[i+1] = {range[1][1], range[2]}
                    end
                end
                if self._ast.namedCapGroups.size > 0 then
                    local groups1 = {}
                    for name, idx in self._ast.namedCapGroups:entries() do
                        groups1[name] = indices[idx + 1]
                    end
                    rawset(indices, "groups", groups1)
                end
                rawset(m, "indices", indices)
            end
            return m
        end
    end

    -- Failed match
    return
end

return RegExp
