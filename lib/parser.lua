-- luacheck: read_globals utf8
require("shim/utf8")
local Array    = require("collection/array")
local readonly = require("readonly")

--
-- Monadic parser combinators!
--
local P = {}

local meta = {}
meta.__index = {}

local function parser(f)
    return setmetatable({_f = f}, meta)
end

--
-- Monadic parsing: p1:bind(f) is p1 >>= f.
--
function meta.__index:bind(cont)
    return parser(function(src, pos)
        local ok, newPos, ret = self._f(src, pos)
        if ok then
            return cont(ret)._f(src, newPos)
        else
            return false, newPos -- newPos actually contains an error message
        end
    end)
end

--
-- Applicative parsing: p1 * p2 is p1 *> p2, i.e. apply p1 first and then
-- p2 next, then return the result of p2.
--
function meta.__mul(p1, p2)
    return parser(function(src, pos)
        local ok, newPos, _ret = p1._f(src, pos)
        if ok then
            return p2._f(src, newPos)
        else
            return false, newPos
        end
    end)
end

--
-- Applicative parsing: p1 / p2 is p1 <* p2, i.e. apply p1 first and then
-- p2 next, then return the result of p1.
--
function meta.__div(p1, p2)
    return parser(function(src, pos)
        local ok, newPos, ret = p1._f(src, pos)
        if ok then
            local ok2, newPos2, _ret2 = p2._f(src, newPos)
            if ok2 then
                return true, newPos2, ret
            else
                return false, newPos2 -- error
            end
        else
            return false, newPos -- error
        end
    end)
end

--
-- Alternative parsing: p1 + p2 is p1 <|> p2.
--
function meta.__add(p1, p2)
    return parser(function(src, pos)
        local ok, newPos, ret = p1._f(src, pos)
        if ok then
            return true, newPos, ret
        else
            return p2._f(src, pos)
        end
    end)
end

--
-- Applicative parsing: P.pure(v) is pure v.
--
function P.pure(val)
    return parser(function(_src, pos)
        return true, pos, val
    end)
end

--
-- Always-failing parser.
--
function P.fail(msg)
    return parser(function(_src, pos)
        return false, string.format("%s at position %d", msg, pos)
    end)
end

--
-- Pure function: P.const is const a _ = a.
--
function P.const(val)
    return function(_arg)
        return val
    end
end

--
-- P.choice(ps) tries a sequence of parsers "ps" in order, until one of
-- them succeeds.
--
function P.choice(ps)
    assert(#ps > 0, "P.choice() expects a non-empty sequence of parsers")
    return parser(function(src, pos)
        local lastErr
        for _i, p in ipairs(ps) do
            local ok, newPos, ret = p._f(src, pos)
            if ok then
                return ok, newPos, ret
            else
                lastErr = newPos -- newPos actually contains an error message
            end
        end
        return false, lastErr
    end)
end

--
-- Constant parser: P.str(s) consumes and returns "s" if it's found, or
-- fails otherwise.
--
function P.str(str)
    return parser(function(src, pos)
        local sub = string.sub(src, pos, pos + #str - 1)
        if sub == str then
            return true, pos + #str, str
        else
            return false, string.format("expected \"%s\" at position %d", str, pos)
        end
    end)
end

--
-- Constant parser: P.char(code) consumes and returns a single numeric
-- codepoint if it's found, or fails otherwise.
--
function P.char(code)
    assert(type(code) == "number" and code >= 0, "P.char() expects a numeric codepoint")
    if code <= 0x7F then
        -- The fast path: we can consume at most one octet.
        return parser(function(src, pos)
            if #src >= pos then
                local got = string.byte(src, pos)
                if got == code then
                    return true, pos + 1, code
                end
            end
            return false, string.format("expected '%s' at position %d", string.char(code), pos)
        end)
    else
        return parser(function(src, pos)
            if #src >= pos then
                local got = utf8.codepoint(src, pos)
                if got == code then
                    local newPos = utf8.offset(src, 1, pos)
                    return true, newPos or #src + 1, code
                end
            end
            return false, string.format("expected '%s' at position %d", utf8.char(code), pos)
        end)
    end
end

--
-- Lua pattern matcher: P.pat(s) expects a string matching the given
-- pattern "s". It returns the matched string.
--
function P.pat(pat)
    return parser(function(src, pos)
        local from, to = string.find(src, "^" .. pat, pos)
        if from == nil then
            return false, string.format("expected %s at position %d", pat, pos)
        else
            return true, to + 1, string.sub(src, from, to)
        end
    end)
end

--
-- Applicative parsing: P.map(f, p1, p2, ...pn) is f <$> p1 <*> p2 <*>
-- ...pn for any n.
--
function P.map(f, ...)
    local parsers = Array:of(...)
    return parser(function(src, pos)
        local args = Array:new()
        for i = 1, parsers.length do
            local ok, newPos, ret = parsers[i]._f(src, pos)
            if ok then
                args[i] = ret
                pos     = newPos
            else
                return false, newPos
            end
        end
        return true, pos, f(args:unpack())
    end)
end

--
-- P.peekStr() returns the rest of the input without consuming anything.
--
function P.peekStr()
    return parser(function(src, pos)
        return true, pos, string.sub(src, pos)
    end)
end

--
-- P.take(n) consumes and returns n octets from the input. It fails when
-- there are not enough octets left.
--
function P.take(n)
    return parser(function(src, pos)
        local newPos = pos + n
        if #src + 1 >= newPos then
            return true, newPos, string.sub(src, pos, newPos - 1)
        else
            return false, string.format("expected %d octets but the input is not enough", n)
        end
    end)
end

--
-- P.scan(state, f) is like P.scanU8() but works on octets and not on UTF-8
-- codepoints. It's faster than P.scanU8().
--
function P.scan(st0, f)
    return parser(function(src, pos)
        local st      = st0
        local lastIdx = nil

        for i = pos, #src do
            local code = string.byte(src, i)
            st = f(st, code)
            if st == nil then
                break
            else
                lastIdx = i
            end
        end

        if lastIdx then
            -- At least one octet was consumed.
            return true, lastIdx + 1, string.sub(src, pos, lastIdx)
        else
            return true, pos, ""
        end
    end)
end

--
-- P.scanU8(state, f) is a stateful scanner. It repeatedly calls f(state,
-- codepoint) for each next UTF-8 codepoint in the input until f returns
-- nil or the input ends. If f returns a non-nil value, the codepoint will
-- be consumed and the value will be used as the next state. The parser
-- returns a string containing consumed characters.
--
-- This parser does not fail. It returns an empty string if the predicate
-- returns nil on the first codepoint of input.
--
-- Note: Because this parser does not fail, do not use it with combinators
-- such as P.many(), because such parsers loop until a failure
-- occurs. Careless use will thus result in an infinite loop.
--
function P.scanU8(st0, f)
    return parser(function(src, pos)
        local st      = st0
        local lastIdx = nil

        for idx, code in utf8.codes(string.sub(src, pos)) do
            st = f(st, code)
            if st == nil then
                break
            else
                lastIdx = idx
            end
        end

        if lastIdx then
            -- At least one character was consumed. Find the byte position
            -- of the first unconsumed character.
            local newPos = utf8.offset(src, 1, pos - 1 + lastIdx) or #src + 1
            return true, newPos, string.sub(src, pos, newPos - 1)
        else
            return true, pos, ""
        end
    end)
end

--
-- The combinator P.many(p) parses 0 or more appearances of p, and returns
-- a sequence of results of p. This parser never fails.
--
function P.many(p)
    return parser(function(src, pos)
        local seq = {}
        while true do
            local ok, newPos, ret = p._f(src, pos)
            if ok then
                table.insert(seq, ret)
                pos = newPos
            else
                break
            end
        end
        return true, pos, seq
    end)
end

--
-- The combinator P.sepBy(p, sep) parses zero or more occurences of p,
-- separated by sep. It returns a sequence of results of p. This parser
-- never fails.
--
function P.sepBy(p, sep)
    return P.sepBy1(p, sep) + P.pure({})
end

--
-- The combinator P.sepBy1(p, sep) parses one or more occurences of p,
-- separated by sep. It returns a sequence of results of p. The sequence
-- will never be empty.
--
function P.sepBy1(p, sep)
    return parser(function(src, pos)
        local seq = {}
        while true do
            local ok, newPos, ret = p._f(src, pos)
            if ok then
                table.insert(seq, ret)
                pos = newPos

                local ok1, newPos1, _ret1 = sep._f(src, pos)
                if ok1 then
                    pos = newPos1
                else
                    -- seq is guaranteed to be non-empty at this point.
                    return true, pos, seq
                end
            elseif #seq > 0 then
                return true, pos, seq
            else
                -- newPos actually contains an error message
                return false, newPos
            end
        end
    end)
end

--
-- Optional parsing: P.option(default, p) tries p and if it fails returns
-- "default". This parser never fails.
--
function P.option(default, p)
    return parser(function(src, pos)
        local ok, newPos, ret = p._f(src, pos)
        if ok then
            return true, newPos, ret
        else
            return true, pos, default
        end
    end)
end

--
-- P.unsigned parses and returns a unsigned decimal integer.
--
P.unsigned = P.map(tonumber, P.pat("%d+"))

--
-- P.tillEnd(p) expects the end of string right after p, and returns what p
-- returns.
--
function P.tillEnd(p)
    return parser(function(src, pos)
        local ok, newPos, ret = p._f(src, pos)
        if ok then
            if newPos == #src + 1 then
                return true, newPos, ret
            else
                return false, string.format("expected EOF at position %d", newPos)
            end
        else
            return false, newPos
        end
    end)
end

--
-- Running a parser: P.parse(p, str) tries to parse str with p. When it
-- succeeds it returns the result of the parser and the
-- left-over. Otherwise it raises an error.
--
function P.parse(p, str)
    local ok, newPos, ret = p._f(str, 1)
    if ok then
        return ret, string.sub(str, newPos)
    else
        error(newPos .. ": " .. str, 2)
    end
end

return readonly(P)
