require("shim/table")
local AbstractImmutableArray = require("collection/array/immutable/base")
local class                  = require("class")

--
-- A potentially sparse immutable array. Unlike the standard Lua sequence, indicies
-- of an array is not always contiguous. In other words, nil is a valid
-- element of an array (although it is considered a "hole" in the array.)
--
-- ImmutableArray is 1-indexed, for the sake of consistency with other
-- parts of Lua.
--
local ImmutableArray = class("ImmutableArray", AbstractImmutableArray)

-- @private
function ImmutableArray:__init(length)
    assert(
        length == nil or
        (type(length) == "number" and length >= 0 and math.floor(length) == length),
        "ImmutableArray:new() expects an optional non-negative integer")

    -- Can't do self._tab = {} because we override __newindex.
    rawset(self, "_tab", {})
    rawset(self, "_len", length or 0)
end

--
-- ImmutableArray:of(e1, e2, ...) constructs an array with given
-- elements. The length of the resulting array is the same of the number of
-- elements passed to the function, including nil values.
--
ImmutableArray:static("of")
function ImmutableArray:of(...)
    local ret = ImmutableArray:new()
    ret._tab = {...}
    ret._len = select("#", ...)
    return ret
end

--
-- ImmutableArray:from(iter) constructs an array with an iterator which
-- generates the initial contents of the array.
--
-- ImmutableArray:from(seq) constructs an array with the given standard Lua
-- sequence (which cannot have nil values).
--
ImmutableArray:static("from")
function ImmutableArray:from(iter, ...)
    local ret = ImmutableArray:new()

    if type(iter) == "table" then
        local len = 0
        for i, elem in ipairs(iter) do
            ret._tab[i] = elem
            len         = i
        end
        ret._len = len
    elseif type(iter) == "function" then
        for elem in iter, ... do
            ret._tab[ret._len + 1] = elem
            ret._len = ret._len + 1
        end
    else
        error("ImmutableArray:from() takes either a sequence or an iterable", 2)
    end

    return ret
end

--
-- The maximum index of the array, regardless of whether it is sparse or
-- not.
--
function ImmutableArray.__getter:length()
    return self._len
end

--
-- The ".." operator creates a new array that is a concatenation of two
-- arrays.
--
function ImmutableArray.__concat(a1, a2)
    assert(AbstractImmutableArray:made(a1) and AbstractImmutableArray(a2),
           string.format("Array can only be concatenated with another Array: %s .. %s", a1, a2))
    local ret = ImmutableArray:new(a1.length + a2.length)
    for i=1, a1.length do
        ret._tab[i] = a1[i]
    end
    for i=1, a2.length do
        ret._tab[a1.length + i] = a2[i]
    end
    return ret
end

--
-- arr[idx] indexes an element, or nil if no such element exists.
--
function ImmutableArray:__index(idx)
    assert(type(idx) == "number", "ImmutableArray doesn't have a property " .. tostring(idx))
    return self._tab[idx]
end
function ImmutableArray:__newindex()
    error("Attempted to mutate an immutable array", 2)
end

-- :map(func) creates a new array with each element being the result of
-- applying "func" to the element. The function "func" is called with 3
-- arguments: the element, the index, and the array. If the array is
-- sparse, the function will not be called for missing elements.
--
function ImmutableArray:map(func)
    assert(type(func) == "function", "ImmutableArray#map() expects a function")
    local ret = ImmutableArray:new(self._len)
    for i=1, self._len do
        local elem = self._tab[i]
        if elem ~= nil then
            ret._tab[i] = func(elem, i, self)
        end
    end
    return ret
end

--
-- :slice(from, to) returns a shallow copy of the array. Unlike JavaScript
-- Array, the range is [from, to] but not [from, to). Indices are also
-- 1-origin. Both arguments are optional.
--
-- Calling :slice() with no arguments is equivalent to :clone().
--
function ImmutableArray:slice(from, to)
    assert(from == nil or (type(from) == "number" and math.floor(from) == from),
            "ImmutableArray#slice() expects an integer as its 1st argument")
    assert(to == nil or (type(to) == "number" and math.floor(to) == to),
            "ImmutableArray#slice() expects an integer as its 2nd argument")

    from = from or 1
    to   = to   or self._len

    if from < 0 then
        from = from + self._len + 1
    end
    from = math.max(1, from)

    if to < 0 then
        to = to + self._len + 1
    end
    to = math.max(0, to)

    local ret = ImmutableArray:new()
    for i = from, to do
        ret._tab[ret._len + 1] = self._tab[i]
        ret._len = ret._len + 1
    end
    return ret
end

--
-- :toReversed() returns a shallow copy of the array, with all elements
-- reversed.
--
function ImmutableArray:toReversed()
    local ret = ImmutableArray:new(self._len)
    for i=1, self._len do
        ret._tab[self._len - i + 1] = self._tab[i]
    end
    return ret
end

--
-- :unpack() returns all elements in the array.
--
function ImmutableArray:unpack()
    -- luacheck: read_globals table.unpack
    return table.unpack(self._tab, 1, self._len)
end

return ImmutableArray
