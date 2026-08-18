local Array = require("collection/array")
local Map   = require("collection/map")
local class = require("class")
local enum  = require("enum")

local Severity = enum {
    "debug", "log", "info", "warn", "error"
}

local CODE_PERCENT = string.byte("%")
local CODE_LOWER_D = string.byte("d")
local CODE_LOWER_F = string.byte("f")
local CODE_LOWER_I = string.byte("i")
local CODE_LOWER_O = string.byte("o")
local CODE_UPPER_O = string.byte("O")
local CODE_LOWER_S = string.byte("s")

-- The comparator ``compare(a, b)`` uses the standard comparison operators
-- by default, but allows types to be different. Values of different types
-- are compared in this order: nil, number, string, boolean, table,
-- function, thread, and then userdata. booleans are also comparable: false
-- is less than true.
local TYPE_ORDER = {
    ["nil"     ] = 1,
    ["number"  ] = 2,
    ["string"  ] = 3,
    ["boolean" ] = 4,
    ["table"   ] = 5,
    ["thread"  ] = 6,
    ["userdata"] = 7,
}
local function stdCmp(a, b)
    if     a < b then return -1
    elseif a > b then return  1
    else              return  0
    end
end
local function compare(a, b)
    -- If either a or b is a table or a userdata, there is a chance that
    -- they overload comparison operators, and there is a well-formed
    -- ordering between a and b.
    if type(a) == "table" or type(a) == "userdata" or
       type(b) == "table" or type(b) == "userdata" then
        local ok, ret = pcall(stdCmp, a, b)
        if ok then
            return ret
        end
        -- Ignore the exception, fall through.
    end

    local tA = TYPE_ORDER[type(a)]
    local tB = TYPE_ORDER[type(b)]
    assert(tA and tB)
    if     tA < tB then return -1
    elseif tA > tB then return  1
    else
        -- We now know that a and b have the same type, but this doesn't
        -- necessarily mean they are comparable.
        if a == nil then
            return 0 -- because b must also be nil.

        elseif type(a) == "number" then
            return a - b

        elseif type(a) == "string" then
            return stdCmp(a, b)

        elseif type(a) == "boolean" then
            if a then
                return (b and  0) or 1
            else
                return (b and -1) or 0
            end

        else
            -- This comparison really makes no sense...
            return (a == b and 0) or -1
        end
    end
end

local function prettyPrint(val, seen, level)
    -- This function MUST NOT call format(), or circular references will go
    -- undetected.
    seen    = seen  or Map:new() -- Map<any, Index> where Index is an integer
    level   = level or 0

    if type(val) == "table" then
        local circularIdx = seen:get(val)
        if circularIdx then
            -- This is a circular reference. Break the loop or we'll enter
            -- an infinite loop.
            return string.format("[Circular *%d]", circularIdx)
        end

        local meta       = getmetatable(val)
        local __tostring = (meta and meta.__tostring) or nil
        if __tostring then
            -- This table has tostring() overridden. Trust it, and don't
            -- bother to dump its internals.
            local ok, ret = pcall(__tostring, val)
            if ok then
                return ret
            else
                return string.format("<Inspection raised: %s>", ret)
            end
        end

        -- Sort keys in their natural order.
        local keys = Array:of()
        for k, _v in pairs(val) do
            keys:push(k)
        end
        keys:sort(compare)

        -- We dump regular tables and sequences differently. Sequences
        -- don't need their indices to be explicitly printed.
        local lastIdx = 0
        local props   = Array:of()
        for k in keys:values() do
            local v    = val[k]
            local prop = Array:of(string.rep("  ", level + 1))

            if k == lastIdx + 1 then
                -- We can omit this key.
                lastIdx = lastIdx + 1
            else
                if type(k) == "string" then
                    if string.find(k, "^[%a_][%w_]*$") ~= nil then
                        -- This key is an identifier.
                        prop:push(k)
                    else
                        prop:push(string.format("[%q]", k))
                    end
                else
                    prop:push "["
                    do
                        seen:set(val, seen.size + 1)
                        prop:push(prettyPrint(k, seen))
                        seen:delete(val)
                    end
                    prop:push "]"
                end
                prop:push " = "
            end
            do
                seen:set(val, seen.size + 1)
                prop:push(prettyPrint(v, seen, level + 1))
                seen:delete(val)
            end
            props:push(prop:join "")
        end

        if props.length > 0 then
            return table.concat {
                "{\n",
                props:join ",\n",
                "\n",
                string.rep("  ", level),
                "}"
            }
        else
            return "{}"
        end
    elseif type(val) == "string" then
        if level == 0 then
            return val
        else
            return string.format("%q", val)
        end
    else
        return tostring(val)
    end
end

local function format(fst, ...)
    local ret = Array:of()
    if type(fst) == "string" then
        local from   = 1
        local isPct  = false
        local argIdx = 1
        local nArgs  = select("#", ...)
        for i = 1, #fst do
            local code = string.byte(fst, i)
            if isPct then
                if code == CODE_LOWER_D or code == CODE_LOWER_I or code == CODE_LOWER_F then
                    -- %d, %i, or %f: print the next argument as a number.
                    if argIdx <= nArgs then
                        local arg = select(argIdx, ...)
                        ret:push(tostring(arg))
                        argIdx = argIdx + 1
                    else
                        ret:push(string.sub(fst, from, i))
                    end
                elseif code == CODE_LOWER_O or code == CODE_UPPER_O then
                    -- %o or %O: pretty-print the next argument.
                    if argIdx <= nArgs then
                        local arg = select(argIdx, ...)
                        ret:push(prettyPrint(arg))
                        argIdx = argIdx + 1
                    else
                        ret:push(string.sub(fst, from, i))
                    end
                elseif code == CODE_LOWER_S then
                    -- %s: print the next argument as a string.
                    if argIdx <= nArgs then
                        local arg = select(argIdx, ...)
                        if type(arg) == "string" then
                            ret:push(arg)
                        else
                            ret:push(tostring(arg))
                        end
                        argIdx = argIdx + 1
                    else
                        ret:push(string.sub(fst, from, i))
                    end
                elseif code == CODE_PERCENT then
                    -- %%: print "%"
                    ret:push "%"
                else
                    -- Unknown substitution: print it as-is.
                    ret:push(string.sub(fst, from, i))
                end
                isPct = false
                from  = i + 1
            else
                if code == CODE_PERCENT then
                    if from < i then
                        ret:push(string.sub(fst, from, i - 1))
                    end
                    isPct = true
                    from  = i
                end
            end
        end
        if from <= #fst then
            ret:push(string.sub(fst, from))
        end
        -- Pretty-print all unconsumed arguments.
        for i = argIdx, nArgs do
            ret:push " "
            ret:push(prettyPrint((select(i, ...))))
        end
    else
        -- Pretty-print all arguments, including the first one.
        ret:push(prettyPrint(fst))
        for i = 1, select("#", ...) do
            ret:push " "
            ret:push(prettyPrint((select(i, ...))))
        end
    end
    return ret:join("")
end

--
-- Abstract Console API mixin: Implementations must override :logImpl() and
-- :traceImpl().
--
local function ConsoleBase(base)
    local klass = class("ConsoleBase", base)

    klass.Severity = Severity

    function klass:__init(...)
        if base then
            super(...)
        end
        self._logLevel = Severity.log
    end

    function klass.__getter:logLevel()
        return self._logLevel
    end
    function klass.__setter:logLevel(severity)
        assert(Severity:has(severity), "ConsoleBase#logLevel expects a Severity")
        self._logLevel = severity
    end

    -- protected
    function klass:format(...)
        return format(...)
    end

    klass:abstract("logImpl")

    function klass:_log(sev, ...)
        if sev >= self._logLevel then
            self:logImpl(sev, ...)
        end
    end

    klass:abstract("traceImpl")

    function klass:_trace(sev, ...)
        if sev >= self._logLevel then
            -- LuaJIT seems to have a bug. When the first argument to
            -- debug.traceback() is nil, the result becomes also nil. But
            -- giving it an empty string prepends an unwanted empty line to
            -- the result, so we remove the first line of the trace.
            local trace = debug.traceback("", 2)
            local from  = string.find(trace, "[^\r\n]") -- first non-LF, non-CR character
            if from == nil then
                self:traceImpl(sev, trace, ...)
            else
                self:traceImpl(sev, string.sub(trace, from), ...)
            end
        end
    end

    --
    -- ConsoleBase#debug(...) prints a message in the "debug" level.
    --
    function klass:debug(...)
        self:_log(Severity.debug, ...)
    end

    --
    -- ConsoleBase#log(...) prints a message in the "log" level.
    --
    function klass:log(...)
        self:_log(Severity.log, ...)
    end

    --
    -- ConsoleBase#trace(...) prints a message in the "log" level with a
    -- stack trace.
    --
    function klass:trace(...)
        self:_trace(Severity.log, ...)
    end

    --
    -- ConsoleBase#info(...) prints a message in the "info" level.
    --
    function klass:info(...)
        self:_log(Severity.info, ...)
    end

    --
    -- ConsoleBase#warn(...) prints a message in the "warn" level.
    --
    function klass:warn(...)
        self:_log(Severity.warn, ...)
    end

    --
    -- ConsoleBase#error(...) prints a message in the "error" level with a
    -- stack trace.
    --
    function klass:error(...)
        self:_trace(Severity.error, ...)
    end

    return klass
end

return ConsoleBase
