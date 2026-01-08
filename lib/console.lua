local V_STRING_OF = {
    "debug", "log", "info", "warn", "error"
}
local V_NUMBER_OF = {}
for i, str in ipairs(V_STRING_OF) do
    V_NUMBER_OF[str] = i
end
local VERBOSITY = V_NUMBER_OF["log"]

local CODE_PERCENT = string.byte("%")
local CODE_LOWER_D = string.byte("d")
local CODE_LOWER_F = string.byte("f")
local CODE_LOWER_I = string.byte("i")
local CODE_LOWER_O = string.byte("o")
local CODE_UPPER_O = string.byte("O")
local CODE_LOWER_S = string.byte("s")

local function prettyPrint(val, level)
    level = level or 0

    if type(val) == "table" then
        local ret = {}
        table.insert(ret, tostring(val))
        table.insert(ret, " = {\n")
        for k, v in pairs(val) do
            if type(k) == "string" then
                if string.find(k, "^[%a_][%w_]*$") ~= nil then
                    -- This key is an identifier.
                    table.insert(ret, string.rep("  ", level + 1))
                    table.insert(ret, k)
                else
                    table.insert(ret, string.rep("  ", level + 1))
                    table.insert(ret, string.format("[%q]", k))
                end
            else
                table.insert(ret, string.rep("  ", level + 1))
                table.insert(ret, "[")
                table.insert(ret, tostring(k))
                table.insert(ret, "]")
            end
            table.insert(ret, " = ")
            table.insert(ret, prettyPrint(v, level + 1))
            table.insert(ret, ",\n")
        end
        table.insert(ret, string.rep("  ", level))
        table.insert(ret, "}")
        return table.concat(ret)
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
                    if argIdx < nArgs then
                        local arg = select(argIdx, ...)
                        table.insert(ret, tostring(arg))
                        argIdx = argIdx + 1
                    else
                        table.insert(ret, string.sub(fst, from, i))
                    end
                elseif code == CODE_LOWER_O or code == CODE_UPPER_O then
                    -- %o or %O: pretty-print the next argument.
                    if argIdx < nArgs then
                        local arg = select(argIdx, ...)
                        table.insert(ret, prettyPrint(arg))
                        argIdx = argIdx + 1
                    else
                        table.insert(ret, string.sub(fst, from, i))
                    end
                elseif code == CODE_LOWER_S then
                    -- %s: print the next argument as a string.
                    if argIdx < nArgs then
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
        -- Pretty-print all unconsumed arguments.
        for i = argIdx, nArgs do
            table.insert(ret, " ")
            table.insert(prettyPrint(select(i, ...)))
        end
    else
        -- Pretty-print all arguments, including the first one.
        table.insert(ret, prettyPrint(fst))
        for i = 1, select("#", ...) do
            table.insert(ret, " ")
            table.insert(prettyPrint(select(i, ...)))
        end
    end
    return table.concat(ret)
end

local function _log(level, header, ...)
    if level >= VERBOSITY then
        if header ~= nil then
            print(header .. ": " .. format(...))
        else
            print(format(...))
        end
    end
end

local function _trace(level, header, ...)
    if level >= VERBOSITY then
        if select("#", ...) > 0 then
            if header ~= nil then
                print(header .. ": " .. format(...))
            else
                print(format(...))
            end
        end
        -- LuaJIT seems to have a bug. When the first argument to
        -- debug.traceback() is nil, the result becomes also nil. But
        -- giving it an empty string prepends an unwanted empty line to the
        -- result, so we remove the first line of the trace.
        local trace = debug.traceback("", 2)
        local from  = string.find(trace, "[^\r\n]") -- first non-LF, non-CR character
        if from == nil then
            print(trace)
        else
            print(string.sub(trace, from))
        end
    end
end

--
-- JS-like Console API
--
local console = {}

--
-- console.verbosity is a read-write property and is one of the following
-- strings:
--
--   * "debug"
--   * "log" (default)
--   * "info"
--   * "warn"
--   * "error"
--
local function setVerbosity(v)
    local n = V_NUMBER_OF[v]
    if n then
        VERBOSITY = n
    else
        error("Invalid verbosity: " .. v, 2)
    end
end

--
-- console.debug(...) prints a message in the "debug" level.
--
function console.debug(...)
    _log(1, "DEBUG", ...)
end

--
-- console.log(...) prints a message in the "log" level.
--
function console.log(...)
    _log(2, nil, ...)
end

--
-- console.trace(...) prints a message in the "log" level with a stack trace.
--
function console.trace(...)
    _trace(2, nil, ...)
end

--
-- console.info(...) prints a message in the "info" level.
--
function console.info(...)
    _log(3, "INFO", ...)
end

--
-- console.warn(...) prints a message in the "warn" level.
--
function console.warn(...)
    _log(4, "WARNING", ...)
end

--
-- console.error(...) prints a message in the "error" level with a stack
-- trace.
--
function console.error(...)
    _trace(5, "ERROR", ...)
end

return setmetatable(
    {},
    {
        __index = function(self, key)
            local val = console[key]
            if val ~= nil then
                return val
            elseif key == "verbosity" then
                return VERBOSITY
            else
                error("No such property exists in console: " .. key, 2)
            end
        end,
        __newindex = function(self, key, val)
            if key == "verbosity" then
                setVerbosity(val)
            else
                if console[key] then
                    error("Cannot modify the read-only property " .. key, 2)
                else
                    error("Cannot modify the read-only table", 2)
                end
            end
        end
    })
