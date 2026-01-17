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

local function prettyPrint(val, seen, numSeen, level)
    -- This function MUST NOT call format(), or circular references will go
    -- undetected.
    seen    = seen    or {} -- {[table] = index}
    numSeen = numSeen or 0  -- the size of "seen"
    level   = level   or 0

    if type(val) == "table" then
        local circularIdx = seen[val]
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
        local keys = {}
        for k, _v in pairs(val) do
            table.insert(keys, k)
        end
        table.sort(keys)

        -- We dump regular tables and sequences differently. Sequences
        -- don't need their indices to be explicitly dumped.
        local lastIdx = 0
        local props   = {}
        for _i, k in ipairs(keys) do
            local v    = val[k]
            local prop = {string.rep("  ", level + 1)}

            if k == lastIdx + 1 then
                -- We can omit this key.
                lastIdx = lastIdx + 1
            else
                if type(k) == "string" then
                    if string.find(k, "^[%a_][%w_]*$") ~= nil then
                        -- This key is an identifier.
                        table.insert(prop, k)
                    else
                        table.insert(prop, string.format("[%q]", k))
                    end
                else
                    table.insert(prop, "[")
                    do
                        seen[val] = numSeen + 1
                        table.insert(prop, prettyPrint(k, seen, numSeen + 1))
                        seen[val] = nil
                    end
                    table.insert(prop, "]")
                end
                table.insert(prop, " = ")
            end
            do
                seen[val] = numSeen + 1
                table.insert(prop, prettyPrint(v, seen, numSeen + 1, level + 1))
                seen[val] = nil
            end
            table.insert(props, table.concat(prop))
        end

        if #props > 0 then
            local ret = {}
            table.insert(ret, "{\n")
            table.insert(ret, table.concat(props, ",\n"))
            table.insert(ret, "\n")
            table.insert(ret, string.rep("  ", level))
            table.insert(ret, "}")
            return table.concat(ret)
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
    assert(fst ~= nil, "Console output functions expect at least one non-nil value")

    local ret = {}
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
                        table.insert(ret, tostring(arg))
                        argIdx = argIdx + 1
                    else
                        table.insert(ret, string.sub(fst, from, i))
                    end
                elseif code == CODE_LOWER_O or code == CODE_UPPER_O then
                    -- %o or %O: pretty-print the next argument.
                    if argIdx <= nArgs then
                        local arg = select(argIdx, ...)
                        table.insert(ret, prettyPrint(arg))
                        argIdx = argIdx + 1
                    else
                        table.insert(ret, string.sub(fst, from, i))
                    end
                elseif code == CODE_LOWER_S then
                    -- %s: print the next argument as a string.
                    if argIdx <= nArgs then
                        local arg = select(argIdx, ...)
                        if type(arg) == "string" then
                            table.insert(ret, arg)
                        else
                            table.insert(ret, tostring(arg))
                        end
                        argIdx = argIdx + 1
                    else
                        table.insert(ret, string.sub(fst, from, i))
                    end
                elseif code == CODE_PERCENT then
                    -- %%: print "%"
                    table.insert(ret, "%")
                else
                    -- Unknown substitution: print it as-is.
                    table.insert(ret, string.sub(fst, from, i))
                end
                isPct = false
                from  = i + 1
            else
                if code == CODE_PERCENT then
                    if from < i then
                        table.insert(ret, string.sub(fst, from, i - 1))
                    end
                    isPct = true
                    from  = i
                end
            end
        end
        if from <= #fst then
            table.insert(ret, string.sub(fst, from))
        end
        -- Pretty-print all unconsumed arguments.
        for i = argIdx, nArgs do
            table.insert(ret, " ")
            table.insert(ret, prettyPrint((select(i, ...))))
        end
    else
        -- Pretty-print all arguments, including the first one.
        table.insert(ret, prettyPrint(fst))
        for i = 1, select("#", ...) do
            table.insert(ret, " ")
            table.insert(ret, prettyPrint((select(i, ...))))
        end
    end
    return table.concat(ret)
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

    function klass:logImpl()
        error("Subclasses must override :logImpl(sev, ...)", 2)
    end

    function klass:_log(sev, ...)
        if sev >= self._logLevel then
            self:logImpl(sev, ...)
        end
    end

    function klass:traceImpl()
        error("Subclasses must override :traceImpl(sev, trace, ...)", 2)
    end

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
