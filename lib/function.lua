require("shim/table")
local readonly = require("readonly")

--
-- Function utilities
--
local fun = {}

--
-- fun.bracket(pre, post, main) is a guarded evaluation. It first evaluates
-- pre(), then calls main(...) with the returned values of pre(), then
-- calls post(...) with the returned values of pre(), and returns what
-- main(...) returned.
--
-- The function post(...) is called regardless of whether main(...) raised
-- an error or not. If main(...) raises an error, it will be raised after
-- post(...) is called.
--
-- Errors raised in pre() or post(..) will not be caught even once.
--
function fun.bracket(pre, post, main)
    assert(type(pre ) == "function", "fun.bracket() expects a function as its 1st argument")
    assert(type(post) == "function", "fun.bracket() expects a function as its 2nd argument")
    assert(type(main) == "function", "fun.bracket() expects a function as its 3rd argument")

    local res, nRes
    local function saveRes(...)
        res, nRes = {...}, select("#", ...)
    end
    saveRes(pre())

    local ok, ret, nRet, err
    local function saveRet(ok0, ...)
        ok = ok0
        if ok0 then
            ret, nRet = {...}, select("#", ...)
        else
            err = ...
        end
    end
    saveRet(pcall(main, table.unpack(res, 1, nRes)))

    post(table.unpack(res, 1, nRes))

    if ok then
        return table.unpack(ret, 1, nRet)
    else
        error(err, 0) -- Don't rewrite the error.
    end
end

--
-- fun.const(arg1, arg2, ...) is a constant function. It creates a function
-- which ignores its own arguments and returns arg1, arg2, ... instead.
--
function fun.const(...)
    local args, nArgs = {...}, select("#", ...)
    return function()
        return table.unpack(args, 1, nArgs)
    end
end

--
-- fun.id(arg1, arg2, ...) is an identity function. It returns arg1, arg2,
-- ...
--
function fun.id(...)
    return ...
end

--
-- fun.pap(f, arg1, arg2, ...) is a partial application. It creates a
-- function that calls f with the supplied arguments prepended.
--
function fun.pap(f, ...)
    assert(type(f) == "function", "fun.pap() expects a function as its 1st argument")

    local args, nArgs = {...}, select("#", ...)
    return function(...)
        return f(table.unpack(args, 1, nArgs), ...)
    end
end

return readonly(fun)
