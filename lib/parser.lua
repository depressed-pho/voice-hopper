require("shim/table")
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
-- Applicative parsing: p1 * p2 is p1 *> p2.
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
-- Pure function: P.const is const a _ = a.
--
function P.const(val)
    return function(_arg)
        return val
    end
end

--
-- Constant parser: P.str(s) expects "s" and consumes "s" if it's found. It
-- returns "s".
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
-- Pattern matcher: P.pat(s) expects a string matching the given pattern
-- "s". It returns the matched string.
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
    local nArgs, parsers = select("#", ...), {...}
    return parser(function(src, pos)
        local args = {}
        for i = 1, nArgs do
            local ok, newPos, ret = parsers[i]._f(src, pos)
            if ok then
                args[i] = ret
                pos     = newPos
            else
                return false, newPos
            end
        end
        return true, pos, f(table.unpack(args, 1, nArgs))
    end)
end

--
-- The combinator P.many(p) parses 0 or more appearances of p. This parser
-- never fails.
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
