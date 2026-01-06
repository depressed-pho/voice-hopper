local hdrLvl = 0
local function mkHeader(label)
    return table.concat {
        string.rep("  ", hdrLvl),
        "- ",
        label
    }
end

function describe(label, thunk)
    io.stderr:write(mkHeader(label) .. "\n")
    hdrLvl = hdrLvl + 1
    thunk()
    hdrLvl = hdrLvl - 1
end

function it(label, thunk)
    local ok, err = pcall(thunk)
    if ok then
        io.stderr:write(mkHeader(label) .. " [PASSED]\n")
    else
        io.stderr:write(mkHeader(label) .. " [FAILED]\n")
        error(err, 0) -- Don't rewrite the message
    end
end

local function _dump(obj, level)
    local ret = {}

    if type(obj) == "table" then
        table.insert(ret, tostring(obj))
        table.insert(ret, " = {\n")
        for k, v in pairs(obj) do
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
            table.insert(ret, _dump(v, level + 1))
            table.insert(ret, ",\n")
        end
        table.insert(ret, string.rep("  ", level))
        table.insert(ret, "}")
    elseif type(obj) == "string" then
        table.insert(ret, string.format("%q", obj))
    else
        table.insert(ret, tostring(obj))
    end

    return table.concat(ret)
end
function dump(obj)
    print(_dump(obj, 0))
end

local function pushPath(path, key)
    local ret = {}
    for i, v in ipairs(path) do
        ret[i] = v
    end
    table.insert(ret, key)
    return ret
end
local function fmtPath(path)
    local ret = {"$"}
    for _i, seg in ipairs(path) do
        if type(seg) == "string" then
            if string.find(seg, "^[%a_][%w_]*$") ~= nil then
                -- This segment is an identifier.
                table.insert(ret, ".")
                table.insert(ret, seg)
            else
                table.insert(ret, string.format("[%q]", seg))
            end
        else
            table.insert(ret, "[")
            table.insert(ret, tostring(seg))
            table.insert(ret, "]")
        end
    end
    return table.concat(ret)
end
local PRIMITIVES = {
    ["nil"     ] = true,
    ["string"  ] = true,
    ["number"  ] = true,
    ["function"] = true,
}
local function deepEqual(value, expVal, path)
    path = path or {}

    if type(value) ~= type(expVal) then
        error(string.format("%s: Expected type %s but got %s: %s", fmtPath(path), type(expVal), type(value), value), 2)
    end

    if PRIMITIVES[type(value)] then
        if value ~= expVal then
            error(string.format("%s: Expected %s but got %s", fmtPath(path), expVal, value), 2)
        end
    elseif type(value) == "table" then
        for k, v in pairs(expVal) do
            deepEqual(value[k], v, pushPath(path, k))
        end
        for k, v in pairs(value) do
            if expVal[k] == nil then
                error(string.format("%s: Unexpected value exists: %s", fmtPath(pushPath(path, k)), v), 2)
            end
        end
    else
        error("Don't know how to compare values of " .. type(expVal))
    end
end

local IDENTITY = function(self)
    return self
end
local PROPS = {
    be   = IDENTITY,
    have = IDENTITY,
    that = IDENTITY,
    to   = IDENTITY,

    a = function(self)
        -- "a" is both an identity and a function at the same time.
        return setmetatable(
            {},
            {
                __index = self,
                __call = function(self, expType)
                    assert(type(expType) == "string", "a() expects a type name")

                    local typ = type(self._value)
                    if typ ~= expType then
                        error(string.format("Expected a %s but got %s: %s", expType, typ, self._value), 2)
                    end
                    return self
                end,
            })
    end,

    as = function(self)
        return function(typ)
            local castOf = {
                string = tostring,
                number = tonumber,
            }
            local cast = castOf[typ]
            if type(cast) == "function" then
                self._value = cast(self._value)
                return self
            else
                error("Unknown type name: "..typ)
            end
        end
    end,

    deep = function(self)
        self._deep = true
        return self
    end,

    equal = function(self)
        return function(expVal)
            if self._deep then
                deepEqual(self._value, expVal)
            else
                if self._value == expVal then
                    -- Passed
                else
                    error(string.format("Expected %s but got %s", expVal, self._value), 2)
                end
            end
        end
    end,

    above = function(self)
        return function(expVal)
            if self._value > expVal then
                -- Passed
            else
                error(string.format("Expected %s > %s but they aren't", self._value, expVal), 2)
            end
        end
    end,

    below = function(self)
        return function(expVal)
            if self._value < expVal then
                -- Passed
            else
                error(string.format("Expected %s < %s but they aren't", self._value, expVal), 2)
            end
        end
    end,

    lengthOf = function(self)
        return function(expLen)
            assert(type(expLen) == "number", "lengthOf() expects a number")

            if type(self._value) == "table" then
                local len = #self._value
                if len == expLen then
                    -- Passed
                else
                    error(string.format("%s does not have a length of %d: %d", self._value, expLen, len), 2)
                end
            else
                error(string.format("%s is not a table", self._value), 2)
            end
        end
    end,

    match = function(self)
        return function(pat)
            assert(type(pat) == "string", "match() expects a pattern string")

            if type(self._value) ~= "string" then
                error(string.format("Expected a string but got %s", self._value), 2)
            elseif string.find(self._value, pat) == nil then
                error(string.format("\"%s\" is expected to match %s", self._value, pat), 2)
            end
        end
    end,

    members = function(self)
        return function(seq)
            assert(type(seq) == "table", "members() expects a sequence")

            if type(self._value) ~= "table" then
                error(string.format("%s is not a table", self._value), 2)
            elseif #self._value ~= #seq then
                error(string.format("the sequence is expected to have %d elements but it actually has %d", #self._value), 2)
            else
                local set = {}
                for _i, got in ipairs(self._value) do
                    set[got] = true
                end
                for _i, exp in ipairs(seq) do
                    if not set[exp] then
                        error(string.format("the sequence is expected to contain %s but it doesn't", tostring(exp)), 2)
                    end
                end
            end
        end
    end,

    null = function(self)
        return function()
            if self._value == nil then
                -- Passed
            else
                error(string.format("Expected nil but got %s", self._value), 2)
            end
        end
    end,

    oneOf = function(self)
        return function(seq)
            assert(type(seq) == "table", "oneOf() expects a sequence")

            for _i, exp in ipairs(seq) do
                if self._value == exp then
                    -- Passed
                    return
                end
            end
            error(string.format("%s is equal to none of the given sequence", self._value), 2)
        end
    end,

    property = function(self)
        return function(name, expVal)
            if type(self._value) == "table" then
                local propVal = self._value[name]
                if expVal ~= nil then
                    if self._deep then
                        deepEqual(propVal, expVal)
                    elseif propVal ~= expVal then
                        error(string.format("%s does not have a property %s with %s: %s", self._value, name, expVal, propVal), 2)
                    end
                else
                    self._value = propVal
                    return self
                end
            else
                error(string.format("%s is not a table", self._value), 2)
            end
        end
    end,

    satisfy = function(self)
        return function(pred)
            assert(type(pred) == "function", "satisfy() expects a predicate function")
            if not pred(self._value) then
                error(string.format("%s does not satisfy the given predicate", self._value), 2)
            end
            return self
        end
    end,
}
PROPS.satisfies = PROPS.satisfy
local expMeta = {}
function expMeta:__index(key)
    if key == "_value" then
        -- This is necessary because self._value might be nil.
        return rawget(self, _value)
    end

    local prop = PROPS[key]
    if prop == nil then
        error("No such property in expect: "..tostring(key), 2)
    else
        return prop(self)
    end
end

function expect(value)
    local exp = {
        _value = value,
        _deep  = false,
    }
    return setmetatable(exp, expMeta)
end
