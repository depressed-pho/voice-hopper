local class = require("class")

--
-- The base class for immutable, potentially sparse arrays.
--
local AbstractImmutableArray = class("AbstractImmutableArray")

--
-- The string representation of the array.
--
function AbstractImmutableArray:__tostring()
    local elems = {}
    for i, elem in self:entries() do
        if type(elem) == "string" then
            elems[i] = string.format("%q", elem)
        else
            elems[i] = tostring(elem)
        end
    end
    return table.concat {
        class.nameOf(class.classOf(self)),
        " {",
        table.concat(elems, ", "),
        "}"
    }
end

--
-- The maximum index of the array, regardless of whether it is sparse or
-- not.
--
AbstractImmutableArray:abstract("getter:length")

--
-- The ".." operator creates a new array that is a concatenation of two
-- arrays.
--
local ConcatenatedArray = class("ConcatenatedArray", AbstractImmutableArray)
function ConcatenatedArray:__init(a1, a2)
    self._a1 = a1
    self._a2 = a2
end
function ConcatenatedArray.__getter:length()
    return self._a1.length + self._a2.length
end
function ConcatenatedArray:__index(idx)
    assert(type(idx) == "number" and math.floor(idx) == idx,
           class.nameOf(class.classOf(self)) .. " doesn't have a property " .. tostring(idx))
    if idx <= self._a1.length then
        return self._a1[idx]
    else
        return self._a2[idx - self._a1.length]
    end
end
function AbstractImmutableArray.__concat(a1, a2)
    assert(AbstractImmutableArray:made(a1) and AbstractImmutableArray:made(a2),
           string.format("Arrays can only be concatenated with arrays: %s .. %s", a1, a2))

    return ConcatenatedArray:new(a1, a2)
end

--
-- arr[idx] indexes an element, or nil if no such element exists.
--
AbstractImmutableArray:abstract("__index")

--
-- :at(idx) is like the operator [] but also supports negative indices.
--
function AbstractImmutableArray:at(idx)
    assert(type(idx) == "number" and math.floor(idx) == idx,
           class.nameOf(class.classOf(self)) .. "#at() expects an integer index")
    if idx < 0 then
        idx = idx + self.length + 1
    end
    return self[idx]
end

--
-- :clone() returns a shallow copy of the array.
--
function AbstractImmutableArray:clone()
    return self -- because this is an immutable array.
end

--
-- :indexOf(elem[, from]) returns the first index (1-based) at which a
-- given element can be found in the array, or -1 if it's not present. If
-- the array is sparse, empty slots are skipped. The "from" index can be
-- negative and can be out of range.
--
function AbstractImmutableArray:indexOf(elem, from)
    assert(elem ~= nil,
           class.nameOf(class.classOf(self)) .. "#indexOf() expects a non-nil value as its 1st argument")
    assert(from == nil or (type(from) == "number" and math.floor(from) == from),
           class.nameOf(class.classOf(self)) .. "#indexOf() expects an optional integer as its 2nd argument")

    from = from or 1
    if from < 0 then
        from = from + self.length + 1
    end

    for i=from, self.length do
        if self[i] == elem then
            return i
        end
    end
    return -1
end

--
-- :join(sep) returns a string with all elements converted into strings and
-- joined with the given separator. If the array is sparse, missing
-- elements are stringified as empty strings.
--
function AbstractImmutableArray:join(sep)
    assert(type(sep) == "string",
           class.nameOf(class.classOf(self)) .. "#join() expects a string separator")
    local seq = {}
    for i, elem in self:entries() do
        if elem == nil then
            seq[i] = ""
        else
            seq[i] = tostring(elem)
        end
    end
    return table.concat(seq, sep)
end

--
-- :map(func) creates a new array with each element being the result of
-- applying "func" to the element. The function "func" is called with 3
-- arguments: the element, the index, and the array. If the array is
-- sparse, the function will not be called for missing elements.
--
local MappedArray = class("MappedArray", AbstractImmutableArray)
function MappedArray:__init(arr, func)
    self._arr  = arr
    self._func = func
end
function MappedArray.__getter:length()
    return self._arr.length
end
function MappedArray:__index(idx)
    assert(type(idx) == "number" and math.floor(idx) == idx,
           class.nameOf(class.classOf(self)) .. " doesn't have a property " .. tostring(idx))
    local elem = self.arr[idx]
    if elem == nil then
        return nil
    else
        return self._func(self._arr[idx], idx, self._arr)
    end
end
function AbstractImmutableArray:map(func)
    assert(type(func) == "function",
           class.nameOf(class.classOf(self)) .. "#map() expects a function")

    return MappedArray:new(self, func)
end

--
-- :slice(from, to) returns a shallow copy of the array. Unlike JavaScript
-- Array, the range is [from, to] but not [from, to). Indices are also
-- 1-origin. Both arguments are optional.
--
-- Calling :slice() with no arguments is equivalent to :clone().
--
local SlicedArray = class("SlicedArray", AbstractImmutableArray)
function SlicedArray:__init(arr, from, to)
    self._arr  = arr
    self._from = from
    self._to   = to
end
function SlicedArray.__getter:_clippedFrom()
    local from = self._from or 1
    if from < 0 then
        from = from + self._arr.length + 1
    end
    return math.max(1, from)
end
function SlicedArray.__getter:_clippedTo()
    local to = self._to or self._arr.length
    if to < 0 then
        to = to + self._arr.length + 1
    end
    return math.max(0, to)
end
function SlicedArray.__getter:length()
    return math.min(self._clippedTo, self._arr.length)
end
function SlicedArray:__index(idx)
    assert(type(idx) == "number" and math.floor(idx) == idx,
           class.nameOf(class.classOf(self)) .. " doesn't have a property " .. tostring(idx))
    if idx <= self.length then
        return self._arr[idx]
    else
        return nil
    end
end
function AbstractImmutableArray:slice(from, to)
    assert(from == nil or (type(from) == "number" and math.floor(from) == from),
           class.nameOf(class.classOf(self)) .. "#slice() expects an integer as its 1st argument")
    assert(to == nil or (type(to) == "number" and math.floor(to) == to),
           class.nameOf(class.classOf(self)) .. "#slice() expects an integer as its 2nd argument")

    return SlicedArray:new(self, from, to)
end

--
-- :toReversed() returns a shallow copy of the array, with all elements
-- reversed.
--
local ReversedArray = class("ReversedArray", AbstractImmutableArray)
function ReversedArray:__init(arr)
    self._arr = arr
end
function ReversedArray.__getter:length()
    return self._arr.length
end
function ReversedArray:__index(idx)
    assert(type(idx) == "number" and math.floor(idx) == idx,
           class.nameOf(class.classOf(self)) .. " doesn't have a property " .. tostring(idx))
    return self._arr[self._arr.length - idx + 1]
end
function AbstractImmutableArray:toReversed()
    return ReversedArray:new(self)
end

--
-- :entries() returns an iterator which iterates over its indices and
-- values. If the array is sparse, it iterates missing values as if they
-- were nil.
--
function AbstractImmutableArray:entries()
    return coroutine.wrap(
        function ()
            for i=1, self.length do
                coroutine.yield(i, self[i])
            end
        end)
end

--
-- :values() returns an iterator which iterates over its values. If the
-- array is sparse, it skips over missing elements. This inconsistency with
-- :entries() is unavoidable due to the language limitation.
--
function AbstractImmutableArray:values()
    return coroutine.wrap(
        function ()
            for i=1, self.length do
                local elem = self[i]
                if elem ~= nil then
                    coroutine.yield(elem)
                end
            end
        end)
end

--
-- :toSeq() converts an array into sequence. If the array is sparse, the
-- method raises an error because it's not representable as a sequence.
--
function AbstractImmutableArray:toSeq()
    local seq = {}
    for i, elem in self:entries() do
        if elem == nil then
            error(
                string.format(
                    "Cannot convert to sequence because the array has a hole at index %d: %s",
                    i, tostring(self)), 2)
        else
            seq[i] = elem
        end
    end
    return seq
end

--
-- :unpack() returns all elements in the array.
--
function AbstractImmutableArray:unpack()
    local seq = {}
    for i, elem in self:entries() do
        seq[i] = elem
    end
    -- luacheck: read_globals table.unpack
    return table.unpack(seq, 1, self.length)
end

return AbstractImmutableArray
