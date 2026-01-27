-- luacheck: read_globals utf8
require("shim/utf8")
local P   = require("parser")
local Set = require("collection/set")
local ast = require("re/ast")
local fun = require("function")

-- Quantifiers
local CODE_ASTERISK     = string.byte "*"
local CODE_PLUS         = string.byte "+"
local CODE_QUESTION     = string.byte "?"

-- Non-paren assertions
local CODE_DOLLAR       = string.byte "$"
local CODE_CARET        = string.byte "^"

-- Other meta characters
local CODE_BRACE_O      = string.byte "{"
local CODE_BRACE_C      = string.byte "}"
local CODE_BACKSLASH    = string.byte "\\"
local CODE_PAREN_O      = string.byte "("
local CODE_PAREN_C      = string.byte ")"
local CODE_SQB_O        = string.byte "[" -- SQuare Bracket
local CODE_SQB_C        = string.byte "]"
local CODE_PIPE         = string.byte "|"
local CODE_PERIOD       = string.byte "."
local CODE_COMMA        = string.byte ","

-- These aren't meta-characters.
local CODE_0            = string.byte "0"
local CODE_9            = string.byte "9"
local CODE_LOWER_A      = string.byte "a"
local CODE_LOWER_B      = string.byte "b"
local CODE_LOWER_D      = string.byte "d"
local CODE_LOWER_F      = string.byte "f"
local CODE_LOWER_S      = string.byte "s"
local CODE_LOWER_U      = string.byte "u"
local CODE_LOWER_W      = string.byte "w"
local CODE_LOWER_X      = string.byte "x"
local CODE_LOWER_Z      = string.byte "z"
local CODE_UPPER_A      = string.byte "A"
local CODE_UPPER_B      = string.byte "B"
local CODE_UPPER_D      = string.byte "D"
local CODE_UPPER_F      = string.byte "F"
local CODE_UPPER_S      = string.byte "S"
local CODE_UPPER_W      = string.byte "W"
local CODE_UPPER_Z      = string.byte "Z"
local CODE_EXCLAMATION  = string.byte "!"
local CODE_COLON        = string.byte ":"
local CODE_HYPHEN       = string.byte "-"
local CODE_LESS_THAN    = string.byte "<"
local CODE_EQUAL        = string.byte "="
local CODE_GREATER_THAN = string.byte ">"
local CODE_UNDERSCORE   = string.byte "_"

-- These exclude '}', ']', and ',' because they are treated as literals if
-- unbalanced.
local NON_LITERAL_CODES = {
    QUANTIFIERS = Set:new {
        CODE_ASTERISK, CODE_PLUS, CODE_QUESTION, CODE_BRACE_O,
    },
    OTHERS = Set:new {
        -- Assertions
        CODE_DOLLAR, CODE_CARET,

        -- Anything else
        CODE_BACKSLASH, CODE_PAREN_O, CODE_PAREN_C, CODE_SQB_O,
        CODE_PIPE, CODE_PERIOD,
    },
}

local pAlternative = P.placeholder()
local pAlts        = P.sepBy(pAlternative, P.char(CODE_PIPE))

local pAssertion = P.choice {
    -- '^' and '$'
    P.char(CODE_CARET ) * P.pure(ast.Caret ),
    P.char(CODE_DOLLAR) * P.pure(ast.Dollar),
    -- Extended look-arounds
    P.str "(?" *
        P.choice {
            -- positive lookahead (?=...)
            P.char(CODE_EQUAL) * P.map(
                function(alts)
                    return ast.Lookaround:new(true, true, ast.NonCapturingGroup:new(alts))
                end,
                pAlts),
            -- negative lookahead (?!...)
            P.char(CODE_EXCLAMATION) * P.map(
                function(alts)
                    return ast.Lookaround:new(false, true, ast.NonCapturingGroup:new(alts))
                end,
                pAlts),
            -- lookbehinds
            P.char(CODE_LESS_THAN) * P.choice {
                -- positive lookbehind (?<=...)
                P.char(CODE_EQUAL) * P.map(
                    function(alts)
                        return ast.Lookaround:new(true, false, ast.NonCapturingGroup:new(alts))
                    end,
                    pAlts),
                -- negative lookbehind (?<!...)
                P.char(CODE_EXCLAMATION) * P.map(
                    function(alts)
                        return ast.Lookaround:new(false, false, ast.NonCapturingGroup:new(alts))
                    end,
                    pAlts),
            }
        } / P.char(CODE_PAREN_C),
    -- Word boundaries
    P.char(CODE_BACKSLASH) *
        P.choice {
            P.char(CODE_LOWER_B) * P.pure(ast.WordBoundary:new(true )),
            P.char(CODE_UPPER_B) * P.pure(ast.WordBoundary:new(false)),
        },
}

-- Modifier (?ims-ims), not to be confused with (?ims-ims:...).
local PAT_MODIFIER = "[ims]*"
local pMods = P.pat(PAT_MODIFIER):bind(
    function(enabled)
        return P.map(
            function(disabled)
                return ast.Mods:new(enabled, disabled)
            end,
            P.option("", P.char(CODE_HYPHEN) * P.pat(PAT_MODIFIER)))
    end)
local pModifier = P.str "(?" * pMods / P.char(CODE_PAREN_C)

-- Literal characters
local newLiteral = fun.pap(ast.Literal.new, ast.Literal)
local pLiteral = P.peekStr():bind(
    function(src)
        -- Consume as many non-meta characters as possible, as long as they
        -- aren't quantified. For example, when the input is "さよち*" we
        -- consume "さよ" and leave "ち*" behind. However, when there is
        -- only one non-meta character which is quantified like "ち*", we
        -- consume that single literal "ち" and leave "*" behind.
        local bytesConsumed = 0
        local broke         = false
        for idx, code in utf8.codes(src) do
            if NON_LITERAL_CODES.QUANTIFIERS:has(code) then
                broke = true
                if bytesConsumed == 0 then
                    bytesConsumed = idx - 1
                end
                break
            elseif NON_LITERAL_CODES.OTHERS:has(code) then
                -- This is a meta character but isn't a quantifier, which
                -- means we can consume the previous character (if any).
                bytesConsumed = idx - 1
                broke         = true
                break
            else
                -- This is a literal character. Continue consuming the
                -- input.
                bytesConsumed = idx - 1
            end
        end
        if not broke then
            -- We reached the end of the input, which means we can also
            -- consume the last character (if any).
            bytesConsumed = #src
        end
        if bytesConsumed > 0 then
            return P.map(newLiteral, P.take(bytesConsumed))
        else
            return P.fail "expected a literal character"
        end
    end)

local ESCAPED_SYMBOLS = {
    ["0"] = 0x0000,
    t = 0x0009,
    n = 0x000A,
    v = 0x000B,
    r = 0x000D,
    f = 0x000F,
}
local function escapedSymbol(char)
    return ESCAPED_SYMBOLS[char] or utf8.codepoint(char)
end
local function escapedHex(hex)
    return tonumber(hex, 16)
end
local function scanHexCodepoints(len, code)
    if len > 6 then
        return nil
    elseif (code >= CODE_0       and code <= CODE_9      ) or
           (code >= CODE_LOWER_A and code <= CODE_LOWER_F) or
           (code >= CODE_UPPER_A and code <= CODE_UPPER_F) then
        return len + 1
    else
        return nil
    end
end
local cDigit = {{CODE_0, CODE_9}}
local cWord = {
    {CODE_0      , CODE_9      },
    {CODE_UPPER_A, CODE_UPPER_Z},
    {CODE_LOWER_A, CODE_LOWER_Z},
    CODE_UNDERSCORE
}
local cSpace = {
    0x0009, -- \t
    0x000A, -- \n
    0x000B, -- \v
    0x000D, -- \r
    0x000F, -- \f
    0x0020, -- ' '
    0x00A0, -- No-break space
    0x2028, -- Line separator
    0x2029, -- Paragraph separator
    0xFEFF, -- Zero-width no-break space
    -- Other Unicode Space_Separator characters are very annoying to list
    -- here. Should we somehow embed Unicode data tables in our Lua
    -- scripts?
}
local pEscapedChar = P.char(CODE_BACKSLASH) *
    P.choice {
        -- \n, \r, \^, \$, ...
        P.map(escapedSymbol, P.pat "[0fnrtv^$\\.*+?()%[%]{}|/]"),
        -- \xHH
        P.map(escapedHex, P.char(CODE_LOWER_X) * P.pat "[0-9a-fA-F][0-9a-fA-F]"),
        -- \u{HH...} and \uHHHH
        P.map(escapedHex,
              P.char(CODE_LOWER_U) *
              P.choice {
                  (P.char(CODE_BRACE_O) * (P.scan(0, scanHexCodepoints) / P.char(CODE_BRACE_C))):bind(
                      function(digits)
                          if #digits > 0 then
                              return P.pure(digits)
                          else
                              return P.fail "expected at least one hexadecimal digit"
                          end
                      end),
                  P.pat "[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]"
              }),
    }
local pPredefinedClass = P.char(CODE_BACKSLASH) *
    P.choice {
        P.char(CODE_LOWER_D) * P.pure(ast.Class:new(false, cDigit)),
        P.char(CODE_UPPER_D) * P.pure(ast.Class:new(true , cDigit)),
        P.char(CODE_LOWER_W) * P.pure(ast.Class:new(false, cWord )),
        P.char(CODE_UPPER_W) * P.pure(ast.Class:new(true , cWord )),
        P.char(CODE_LOWER_S) * P.pure(ast.Class:new(false, cSpace)),
        P.char(CODE_UPPER_S) * P.pure(ast.Class:new(true , cSpace)),
        -- NOTE: Unicode property class is currently unsupported.
    }
local pEscapeSequence = P.choice {
    -- Escaped single character
    P.map(
        function(code)
            return ast.Literal:new(utf8.char(code))
        end,
        pEscapedChar),
    -- Backreference
    P.char(CODE_BACKSLASH) *
        P.choice {
            -- unnamed
            P.map(
                function(digits)
                    return ast.Backreference:new(tonumber(digits))
                end,
                P.pat "[1-9][0-9]*"),
            -- named
            P.map(
                function(name)
                    return ast.Backreference:new(name)
                end,
                P.str("k<") * P.pat "[^>]*" / P.char(CODE_GREATER_THAN))
        },
    -- Character classes such as \d
    pPredefinedClass,
}

local pGroup =
    P.char(CODE_PAREN_O) *
    P.choice {
        P.char(CODE_QUESTION) *
            P.choice {
                -- Non-capturing group with optional modifiers: (?:...), (?ims-ims:...)
                pMods:bind(
                    function(mods)
                        return P.map(
                            function(alts)
                                return ast.NonCapturingGroup:new(alts, mods)
                            end,
                            P.char(CODE_COLON) * pAlts)
                    end),
                -- Named capturing group: (?<name>...)
                P.char(CODE_LESS_THAN) *
                    P.pat "[^>]*":bind(
                        function(name)
                            return P.map(
                                function(alts)
                                    return ast.CapturingGroup:new(alts, name)
                                end,
                                P.char(CODE_GREATER_THAN) * pAlts)
                        end)
            },
        -- Unnamed capturing group: (...)
        P.map(
            function(alts)
                return ast.CapturingGroup:new(alts)
            end,
            pAlts)
    } /
    P.char(CODE_PAREN_C)

local pClassLiteral = P.satisfyU8(
    function(code)
        return code ~= CODE_SQB_C
    end)
local pClassElement = P.choice {
    -- Range
    (pEscapedChar + pClassLiteral):bind(
        function(from)
            return P.char(CODE_HYPHEN) * (pEscapedChar + pClassLiteral):bind(
                function(to)
                    if from < to then -- [a-b]
                        return P.pure {from, to}
                    elseif from == to then -- [a-a]
                        return P.pure(from)
                    else
                        -- [b-a]. This is an invalid range but the parser
                        -- must accept this. We must not backtrack, because
                        -- then it would be successfully parsed as
                        -- [b\-a]. The AST validator will later find this
                        -- error.
                        return P.pure {from, to}
                    end
                end)
        end),
    -- Escaped single character
    pEscapedChar,
    -- Character classes such as \d
    pPredefinedClass,
    -- Bare characters
    pClassLiteral,
}
local pClass =
    P.char(CODE_SQB_O) *
    P.option(false, P.char(CODE_CARET) * P.pure(true)):bind(
        function(negated)
            return P.map(
                function(elems)
                    return ast.Class:new(negated, Set:new(elems:values()))
                end,
                P.many(pClassElement))
        end) /
    P.char(CODE_SQB_C)

local pAtom = P.choice {
    pLiteral,
    pEscapeSequence,
    pGroup,
    pClass,
    P.char(CODE_PERIOD) * P.pure(ast.Wildcard)
}

local pZeroOrMore = function(atom)
    return P.char(CODE_ASTERISK) *
        (P.char(CODE_QUESTION) * P.pure(ast.Quantified:new(atom, 0, math.huge, false)) +
                                 P.pure(ast.Quantified:new(atom, 0, math.huge, true )))
end
local pOneOrMore = function(atom)
    return P.char(CODE_PLUS) *
        (P.char(CODE_QUESTION) * P.pure(ast.Quantified:new(atom, 1, math.huge, false)) +
                                 P.pure(ast.Quantified:new(atom, 1, math.huge, true )))
end
local pZeroOrOne = function(atom)
    return P.char(CODE_QUESTION) *
        (P.char(CODE_QUESTION) * P.pure(ast.Quantified:new(atom, 0, 1, false)) +
                                 P.pure(ast.Quantified:new(atom, 0, 1, true )))
end
local pGenericQuant = function(atom)
    return P.char(CODE_BRACE_O) *
        ( P.unsigned:bind(
              function(min)
                  -- The first number exists. It can be any of {num},
                  -- {min,} and {min,max}.
                  return P.map(
                      function(max)
                          return {min, max}
                      end,
                      P.char(CODE_COMMA) * P.option(math.huge, P.unsigned)) + -- {min,} or {min,max}
                      P.pure({min, min}) -- {num}
              end) +
          P.map(
              function(max)
                  return {0, max}
              end,
              P.char(CODE_COMMA) * P.option(math.huge, P.unsigned)) -- {,} or {,max}
        ):bind(function(minMax)
            return P.char(CODE_BRACE_C) *
                (P.char(CODE_QUESTION) * P.pure(ast.Quantified:new(atom, minMax[1], minMax[2], false)) +
                                         P.pure(ast.Quantified:new(atom, minMax[1], minMax[2], true )))
        end)
end
local pMaybeQuantified = pAtom:bind(
    function(atom)
        return P.choice {
            pZeroOrMore  (atom),
            pOneOrMore   (atom),
            pZeroOrOne   (atom),
            pGenericQuant(atom),
            P.pure(atom)
        }
    end)

local pNode = pAssertion + pModifier + pMaybeQuantified

pAlternative:set(
    P.map(
        function(nodes)
            return ast.Alternative:new(nodes)
        end,
        P.many(pNode)))

-- Every regexp is implicitly contained in a non-capturing group.
local pRegex = P.map(
    function(alts)
        return ast.RegExp:new(
            ast.NonCapturingGroup:new(alts))
    end,
    pAlts)

return pRegex
