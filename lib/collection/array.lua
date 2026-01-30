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
    assert(type(idx) == "number", "Array doesn't have a property " .. tostring(idx))
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
-- Array#at(idx) is like the operator [] but also supports negative
-- indices.
--
function Array:at(idx)
    assert(type(idx) == "number", "Array#at() expects an integer index")
    if idx < 0 then
        idx = idx + self._len + 1
    end
    return self._tab[idx]
end

--
-- Array#clone() returns a shallow copy of the array.
--
function Array:clone()
    local ret = Array:new()
    for i=1, self._len do
        ret._tab[i] = self._tab[i]
    end
    ret._len = self._len
    return ret
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
-- Array#push(elem1, elem2, ...) inserts given elements at the end of the
-- array. They can be nil values.
--
function Array:push(...)
    for i=1, select("#", ...) do
        self._tab[self._len + i] = select(i, ...)
    end
    self._len = self._len + select("#", ...)
    return self
end

--
-- Array#pop() removes and returns the last element of the array, or
-- nothing if it's empty.
--
function Array:pop()
    if self._len > 0 then
        local ret = self._tab[self._len]
        self._tab[self._len] = nil
        self._len = self._len - 1
        return ret
    end
end

--
-- Array#unshift(elem1, elem2, ...) inserts given elements at the beginning
-- of the array. They can be nil values.
--
-- Note that this is a costly O(n) operation where n is the number of
-- existing elements in the array. If you want O(1) behaviour, use Queue
-- instead of Array.
--
function Array:unshift(...)
    local nArgs = select("#", ...)
    for i = self._len, 1, -1 do
        self._tab[i + nArgs] = self._tab[i]
    end
    for i = 1, nArgs do
        self._tab[i] = select(i, ...)
    end
    self._len = self._len + nArgs
    return self
end

--
-- Array#shift() removes and returns the first element of the array, or
-- nothing if it's empty.
--
-- Note that this is a costly O(n) operation where n is the number of
-- existing elements in the array. If you want O(1) behaviour, use Queue
-- instead of Array.
--
function Array:shift()
    if self._len > 0 then
        local ret = self._tab[1]
        for i=1, self._len - 1 do
            self._tab[i] = self._tab[i + 1]
        end
        self._tab[self._len] = nil
        self._len = self._len - 1
        return ret
    end
end

--
-- Array#slice(from, to) returns a shallow copy of the array. Unlike
-- JavaScript Array, the range is [from, to] but not [from, to). Indices
-- are also 1-origin. Both arguments are optional.
--
-- Calling :slice() with no arguments is equivalent to :clone().
--
function Array:slice(from, to)
    assert(from == nil or (type(from) == "number" and math.floor(from) == from),
            "Array#slice() expects an integer as its 1st argument")
    assert(to == nil or (type(to) == "number" and math.floor(to) == to),
            "Array#slice() expects an integer as its 2nd argument")

    from = from or 1
    to   = to   or self._len

    if from < 0 then
        from = from + self._len + 1
    end
    if to < 0 then
        to = to + self._len + 1
    end
    assert(from >= 1 and to >= 1, "Array#slice(): indices out of bounds")

    local ret = Array:new()
    for i = from, to do
        ret:push(self._tab[i])
    end
    return ret
end

--
-- Array#splice(start, deleteCount, item1, item2, ...) deletes given number
-- of elements starting from the given index, and inserts given elements at
-- the index. All arguments except for "start" are optional.
--
-- This function returns an array of deleted elements.
--
function Array:splice(start, deleteCount, ...)
    assert(type(start) == "number" and math.floor(start) == start,
           "Array#splice() expects an integer as its 1st argument")
    assert(deleteCount == nil or
           (type(deleteCount) == "number" and deleteCount >= 0 and math.floor(deleteCount) == deleteCount),
           "Array#splice() expects an optional non-negative integer as its 2nd argument")

    if start < 0 then
        start = start + self._len + 1
    end
    assert(start >= 1, "Array#splice(): starting index out of bounds")

    deleteCount = deleteCount or math.huge
    deleteCount = math.min(deleteCount, math.max(0, self._len - start + 1))

    local ret  = self:slice(start, start + deleteCount - 1)
    local insertCount = select("#", ...)
    if deleteCount >= insertCount then
        -- The array is shrinking. Replace "insertCount" elements, then
        -- move the rest to the left.
        for i = 1, insertCount do
            self._tab[start + i - 1] = select(i, ...)
        end
        local gap = deleteCount - insertCount
        for i = start + insertCount, self._len - gap do
            self._tab[i] = self._tab[i + gap]
        end
        for i = self._len - gap + 1, self._len do
            self._tab[i] = nil
        end
        self._len = self._len - gap
    else
        -- The array is growing. Move elements to the right, then replace
        -- the rest.
        local gap = insertCount - deleteCount
        for i = self._len + gap, start + insertCount, -1 do
            self._tab[i] = self._tab[i - gap]
        end
        for i = 1, insertCount do
            self._tab[start + i - 1] = select(i, ...)
        end
        self._len = self._len + gap
    end
    return ret
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
