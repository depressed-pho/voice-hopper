-- luacheck: read_globals utf8
require("shim/utf8")
local P   = require("parser")
local Set = require("collection/set")
local ast = require("re/ast")
local fun = require("function")

-- Quantifiers
local CODE_ASTERISK  = string.byte("*")
local CODE_PLUS      = string.byte("+")
local CODE_QUESTION  = string.byte("?")

-- Non-paren assertions
local CODE_DOLLAR    = string.byte("$")
local CODE_CARET     = string.byte("^")

-- Other meta characters
local CODE_BRACE_O   = string.byte("{")
local CODE_BRACE_C   = string.byte("}")
local CODE_BACKSLASH = string.byte("\\")
local CODE_PAREN_O   = string.byte("(")
local CODE_PAREN_C   = string.byte(")")
local CODE_SQB_O     = string.byte("[") -- SQuare Bracket
--local CODE_SQB_C     = string.byte("]")
local CODE_PIPE      = string.byte("|")
local CODE_PERIOD    = string.byte(".")
local CODE_COMMA     = string.byte(",")

-- These aren't meta-characters by any means
local CODE_0         = string.byte("0")
local CODE_9         = string.byte("9")
local CODE_LOWER_A   = string.byte("a")
local CODE_LOWER_F   = string.byte("f")
local CODE_LOWER_U   = string.byte("u")
local CODE_LOWER_X   = string.byte("x")
local CODE_UPPER_A   = string.byte("A")
local CODE_UPPER_F   = string.byte("F")

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

local pAssertion = P.choice {
    P.char(CODE_CARET ) * P.pure(ast.Caret ),
    P.char(CODE_DOLLAR) * P.pure(ast.Dollar),
}

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
            return P.fail("expected a literal character")
        end
    end)

local ESCAPED_SYMBOLS = {
    ["0"] = "\0",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
    v = "\v",
}
local function escapedSymbol(char)
    return ast.Literal:new(ESCAPED_SYMBOLS[char] or char)
end
local function escapedHexOctet(hex)
    local code = tonumber(hex, 16)
    return ast.Literal:new(string.char(code))
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
local function escapedHexCodepoint(hex)
    local code = tonumber(hex, 16)
    return ast.Literal:new(utf8.char(code))
end
local function newBackreference(digits)
    return ast.Backreference:new(tonumber(digits))
end
local pEscape = P.char(CODE_BACKSLASH) *
    P.choice {
        -- \n, \r, \^, \$, ...
        P.map(escapedSymbol, P.pat("[0fnrtv^$\\.*+?()%[%]{}|/]")),
        -- \xHH
        P.map(escapedHexOctet, P.char(CODE_LOWER_X) * P.pat("[0-9a-fA-F][0-9a-fA-F]")),
        -- \u{HH...} and \uHHHH
        P.map(escapedHexCodepoint,
              P.char(CODE_LOWER_U) *
              ( (P.char(CODE_BRACE_O) * (P.scan(0, scanHexCodepoints) / P.char(CODE_BRACE_C))):bind(
                      function(digits)
                          if #digits > 0 then
                              return P.pure(digits)
                          else
                              return P.fail("expected at least one hexadecimal digit")
                          end
                      end) +
                P.pat("[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]") )),
        -- Backreference
        P.map(newBackreference, P.pat("[1-9][0-9]*")),
    }

local pAtom = P.choice {
    pLiteral,
    pEscape,
    P.fail("FIXME")
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

local pNode = pAssertion + pMaybeQuantified

local pAlternative = P.map(
    function(nodes)
        return ast.Alternative:new(nodes)
    end,
    P.many(pNode))

-- Every regexp is implicitly contained in a group if it doesn't explicitly
-- begin with '(' and end with ')', but the implicit group does not capture
-- anything.
local pRegex = P.map(
    function(alts)
        if #alts == 1 and ast.Group:made(alts[1]) then
            return alts[1]
        else
            return ast.Group:new(alts, false)
        end
    end,
    P.sepBy(pAlternative, P.char(CODE_PIPE)))

return pRegex
