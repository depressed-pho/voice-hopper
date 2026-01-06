local Symbol = {}

-- A value is a symbol iff it's a table whose metatable has IS_SYMBOL as a
-- key.
local IS_SYMBOL = {}

--
-- Symbol is a callable object. Each call of Symbol() or Symbol("name")
-- creates a new symbol regardless of whether a name is given or not.
--
local function newSymbol(_ns, name)
    assert(name == nil or type(name) == "string", "Symbol() expects an optional name string")
    local sym = {}
    local function toStr(_sym)
        if name ~= nil then
            return "[symbol: " .. name .. "]"
        else
            return "[symbol]"
        end
    end
    return setmetatable(sym, {[IS_SYMBOL] = true, __tostring = toStr})
end

--
-- Symbol:of(name) always returns the same symbol for a given name.
--
local symTable = {} -- name => symbol
function Symbol:of(name)
    assert(type(name) == "string", "Symbol.of() expects a name string")
    local sym = symTable[name]
    if sym ~= nil then
        return sym
    else
        sym = Symbol(name)
        symTable[name] = sym
        return sym
    end
end

--
-- Symbol:made(val) returns true if the given value is a symbol, or
-- false otherwise.
--
function Symbol:made(val)
    return type(val) == "table" and getmetatable(val)[IS_SYMBOL]
end

--
-- No other properties of Symbol are accessible.
--
return setmetatable(
    {},
    {
        __call  = newSymbol,
        __index = function(_self, key)
            local val = Symbol[key]
            if val == nil then
                error("No such properties exists in Symbol: " .. key, 2)
            else
                return val
            end
        end,
        __newindex = function()
            error("Symbol is a read-only table")
        end
    })
