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
local CODE_PERIOD    = string.byte(".")

-- Other meta characters
local CODE_BRACE_O   = string.byte("{")
local CODE_BRACE_C   = string.byte("}")
local CODE_BACKSLASH = string.byte("\\")
local CODE_PAREN_O   = string.byte("(")
local CODE_PAREN_C   = string.byte(")")
local CODE_SQB_O     = string.byte("[") -- SQuare Bracket
local CODE_SQB_C     = string.byte("]")
local CODE_PIPE      = string.byte("|")
local CODE_CARET     = string.byte("^")

-- These exclude '}' and ']' because they are treated as literals if
-- unbalanced.
local NON_LITERAL_CODES = {
    QUANTIFIERS = Set:new {
        CODE_ASTERISK, CODE_PLUS, CODE_QUESTION, CODE_BRACE_O,
    },
    OTHERS = Set:new {
        -- Assertions
        CODE_DOLLAR, CODE_PERIOD,

        -- Anything else
        CODE_BACKSLASH, CODE_PAREN_O, CODE_PAREN_C, CODE_SQB_O,
        CODE_PIPE, CODE_CARET,
    },
}

local pAssertion =
    P.char(CODE_CARET ) * P.pure(ast.Caret ) +
    P.char(CODE_DOLLAR) * P.pure(ast.Dollar)

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

local pAtom =
    pLiteral +
    P.fail("FIXME")

local pZeroOrMore = function(atom)
    return P.char(CODE_ASTERISK) *
        (P.char(CODE_QUESTION) * P.pure(ast.ZeroPlus:new(atom, true )) +
                                 P.pure(ast.ZeroPlus:new(atom, false)))
end
local pMaybeQuantified = pAtom:bind(
    function(atom)
        return
            pZeroOrMore(atom) +
            -- FIXME: more quantifiers
            P.pure(atom)
    end)

local pNode = pAssertion + pMaybeQuantified

local newAlt = fun.pap(ast.Alternative.new, ast.Alternative)
local pAlt = P.map(newAlt, P.many(pNode))

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
    P.sepBy(pAlt, P.char(CODE_PIPE)))

return pRegex
