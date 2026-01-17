require("shim/table")
local class = require("class")

--
-- A potentially sparse array. Unlike the standard Lua sequence, indicies
-- of an array is not always contiguous. In other words, nil is a valid
-- element of an array (although it is considered a "hole" in the array.)
--
-- Array is 1-indexed, for the sake of consistency with other parts of Lua.
--
local Array = class("Array")

--
-- Array:new(length) constructs an array with the given length. All
-- elements in the array will have nil value. If "length" is omitted it
-- will be defaulted to zero.
--
function Array:__init(length)
    assert(
        length == nil or
        (type(length) == "number" and length >= 0 and math.floor(length) == length),
        "Array:new() expects an optional non-negative integer")

    -- Can't do self._tab = {} because we override __newindex.
    rawset(self, "_tab", {})
    rawset(self, "_len", length or 0)
end

--
-- Array:of(e1, e2, ...) constructs an array with given elements. The
-- length of the resulting array is the same of the number of elements
-- passed to the function, including nil values.
--
Array:static("of")
function Array:of(...)
    local ret = Array:new()
    ret._tab = {...}
    ret._len = select("#", ...)
    return ret
end

--
-- Array:from(iter) constructs an array with an iterator which generates
-- the initial contents of the array.
--
-- Array:from(seq) constructs an array with the given standard Lua sequence
-- (which cannot have nil values).
--
Array:static("from")
function Array:from(iter, ...)
    local ret = Array:new()

    if type(iter) == "table" then
        local len = 0
        for i, elem in ipairs(iter) do
            ret._tab[i] = elem
            len         = i
        end
        ret._len = len
    elseif type(iter) == "function" then
        for elem in iter, ... do
            ret:push(elem)
        end
    else
        error("Array:from() takes either a sequence or an iterable", 2)
    end

    return ret
end

--
-- The string representation of the array.
--
function Array:__tostring()
    local elems = {}
    for i = 1, self._len do
        local elem = self._tab[i]
        if type(elem) == "string" then
            elems[i] = string.format("%q", elem)
        else
            elems[i] = tostring(elem)
        end
    end
    return "Array {" .. table.concat(elems, ", ") .. "}"
end

--
-- The maximum index of the array, regardless of whether it is sparse or
-- not.
--
function Array.__getter:length()
    return self._len
end

--
-- The ".." operator creates a new array that is a concatenation of two
-- arrays.
--
function Array.__concat(a1, a2)
    assert(Array:made(a1) and Array:made(a2),
           string.format("Array can only be concatenated with another Array: %s .. %s", a1, a2))
    local ret = Array:new(a1._len + a2._len)
    for i = 1, a1._len do
        ret._tab[i] = a1._tab[i]
    end
    for i = 1, a2._len do
        ret._tab[a1._len + i] = a2._tab[i]
    end
    return ret
end

--
-- arr[idx] indexes an element, or nil if no such element exists.
--
function Array:__index(idx)
    assert(type(idx) == "number", "Array#[] expects an integer index: " .. tostring(idx))
    return self._tab[idx]
end
function Array:__newindex(idx, elem)
    assert(
        type(idx) == "number" and idx >= 1 and math.floor(idx) == idx,
        "Array#[] expects a positive integer index")
    self._len = math.max(self._len, idx)
    self._tab[idx] = elem
end

--
-- Array#join(sep) returns a string with all elements converted into
-- strings and joined with the given separator. If the array is sparse,
-- missing elements are stringified as "nil".
--
function Array:join(sep)
    assert(type(sep) == "string", "Array#join() expects a string separator")
    local seq = {}
    for i=1, self._len do
        seq[i] = tostring(self._tab[i])
    end
    return table.concat(seq, sep)
end

--
-- Array#map(func) creates a new array with each element being the result
-- of applying "func" to the element. The function "func" is called with 3
-- arguments: the element, the index, and the array. If the array is
-- sparse, the function will not be called for missing elements.
--
function Array:map(func)
    assert(type(func) == "function", "Array#map() expects a function")
    local ret = Array:new(self._len)
    for i=1, self._len do
        local elem = self._tab[i]
        if elem ~= nil then
            ret._tab[i] = func(elem, i, self)
        end
    end
    return ret
end

--
-- Array#push(elem) adds the element at the end of the array. "elem" can be
-- a nil value.
--
function Array:push(elem)
    self._len = self._len + 1
    self._tab[self._len] = elem
    return self
end

--
-- Array#entries() returns an iterator which iterates over its indices and
-- values. If the array is sparse, it iterates missing values as if they
-- were nil.
--
local function _entries(self, lastIdx)
    if lastIdx >= self._len then
        return
    else
        local i = lastIdx + 1
        return i, self._tab[i]
    end
end
function Array:entries()
    return _entries, self, 0
end

--
-- Array#values() returns an iterator which iterates over its values. If
-- the array is sparse, it skips over missing elements. This inconsistency
-- with Array#entries() is unavoidable due to the language limitation.
--
function Array:values()
    local lastIdx = 0
    return function()
        for i = lastIdx + 1, self._len do
            local elem = self._tab[i]
            lastIdx = i
            if elem ~= nil then
                return elem
            end
        end
        return
    end
end

--
-- Array#toSeq() converts an array into sequence. If the array is sparse,
-- the method raises an error because it's not representable as a sequence.
--
function Array:toSeq()
    local ret = {}
    for i = 1, self._len do
        if self._tab[i] ~= nil then
            ret[i] = self._tab[i]
        else
            error(
                string.format(
                    "Cannot convert to sequence because the array has a hole at index %d: %s",
                    i, tostring(self)), 2)
        end
    end
    return ret
end

--
-- Array#unpack() returns all elements in the array.
--
function Array:unpack()
    -- luacheck: read_globals table.unpack
    return table.unpack(self._tab, 1, self._len)
end

return Array
