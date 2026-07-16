local AbstractImmutableArray = require("collection/array/immutable/base")
local class                  = require("class")

--
-- The base class for mutable, potentially sparse arrays.
--
local AbstractArray = class("AbstractArray", AbstractImmutableArray)

--
-- The maximum index of the array, regardless of whether it is sparse or
-- not. Setting it to a value smaller than the current length truncates the
-- array.
--
AbstractArray:abstract("setter:length")

--
-- arr[idx] indexes an element, or nil if no such element exists.
--
AbstractArray:abstract("__newindex")

--
-- :push(elem1, elem2, ...) inserts given elements at the end of the
-- array. They can be nil values.
--
function AbstractArray:push(...)
    for i=1, select("#", ...) do
        self[self.length + 1] = select(i, ...)
    end
    return self
end

--
-- :pop() removes and returns the last element of the array, or nothing if
-- it's empty.
--
function AbstractArray:pop()
    if self.length > 0 then
        local elem = self[self.length]
        self.length = self.length - 1
        return elem
    end
end

--
-- :unshift(elem1, elem2, ...) inserts given elements at the beginning of
-- the array. They can be nil values.
--
-- Note that this is a costly O(n) operation where n is the number of
-- existing elements in the array. If you want O(1) behaviour, use Queue
-- instead.
--
function AbstractArray:unshift(...)
    local nArgs = select("#", ...)
    for i = self.length, 1, -1 do
        self[i + nArgs] = self[i]
    end
    for i=1, nArgs do
        self[i] = select(i, ...)
    end
    return self
end

--
-- :shift() removes and returns the first element of the array, or nothing
-- if it's empty.
--
-- Note that this is a costly O(n) operation where n is the number of
-- existing elements in the array. If you want O(1) behaviour, use Queue
-- instead.
--
function AbstractArray:shift()
    if self.length > 0 then
        local elem = self[1]
        for i=1, self.length - 1 do
            self[i] = self[i + 1]
        end
        self.length = self.length - 1
        return elem
    end
end

--
-- :splice(start, deleteCount, item1, item2, ...) deletes given number of
-- elements starting from the given index, and inserts given elements at
-- the index. All arguments except for "start" are optional.
--
-- This function returns an array of deleted elements.
--
AbstractArray:abstract("splice")

--
-- :reverse() reverses the array in place, and returns the reference to the
-- same array.
--
function AbstractArray:reverse()
    local i = 1
    local j = self.length
    while i < j do
        local tmp = self[i]
        self[i] = self[j]
        self[j] = tmp
        i = i + 1
        j = j - 1
    end
    return self
end

return AbstractArray
