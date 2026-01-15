require("shim/table")
local Array    = require("collection/array")
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

    local resource = Array:of(pre())

    local ok, ret, err
    local function saveRet(ok0, ...)
        ok = ok0
        if ok0 then
            ret = Array:of(...)
        else
            err = ...
        end
    end
    saveRet(pcall(main, resource:unpack()))

    post(resource:unpack())

    if ok then
        return ret:unpack()
    else
        error(err, 0) -- Don't rewrite the error.
    end
end

--
-- fun.finally(main, fin) is a variant of fun.bracket(). It first evaluates
-- main(), then evaluates fin(). fin() is evaluated regardless of whether
-- main() runs till the end or raises an error.
--
function fun.finally(main, fin)
    assert(type(main) == "function", "fun.finally() expects a function as its 1st argument")
    assert(type(fin ) == "function", "fun.finally() expects a function as its 2nd argument")

    local ok, ret, err
    local function saveRet(ok0, ...)
        ok = ok0
        if ok0 then
            ret = Array:of(...)
        else
            err = ...
        end
    end
    saveRet(pcall(main))

    fin()

    if ok then
        return ret:unpack()
    else
        error(err, 0) -- Don't rewrite the error.
    end
end

--
-- fun.onException(main, fin) is a variant of fun.bracket(). It first
-- evaluates main(), and if it raises an error the function evaluates
-- fin(), then re-raises the error. Otherwise it won't evaluate fin().
--
function fun.onException(main, fin)
    assert(type(main) == "function", "fun.finally() expects a function as its 1st argument")
    assert(type(fin ) == "function", "fun.finally() expects a function as its 2nd argument")

    local ok, ret, err
    local function saveRet(ok0, ...)
        ok = ok0
        if ok0 then
            ret = Array:of(...)
        else
            err = ...
        end
    end
    saveRet(pcall(main))

    if ok then
        return ret:unpack()
    else
        fin()
        error(err, 0) -- Don't rewrite the error.
    end
end

--
-- fun.const(arg1, arg2, ...) is a constant function. It creates a function
-- which ignores its own arguments and returns arg1, arg2, ... instead.
--
function fun.const(...)
    local args = Array:of(...)
    return function()
        return args:unpack()
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

    local args = Array:of(...)
    return function(...)
        return f(args:unpack(), ...)
    end
end

return readonly(fun)
