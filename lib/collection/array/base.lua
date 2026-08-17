local AbstractImmutableArray = require("collection/array/immutable/base")
local class                  = require("class")

-- Assume we are on LuaJIT and the BitOp-compatible API is available. At
-- least it must be externally installed. Bundlers would have to ignore
-- this.
local bit    = require("bit")
local lshift = bit.lshift
local rshift = bit.rshift

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
-- :sort([cmp]) sorts the elements of the array in-place. If a comparator
-- function ``cmp`` is provided, ``cmp(a, b)`` is expected to return a
-- negative number if ``a`` should come before ``b``, a positive number if
-- ``a`` should come after ``b``, or zero if ``a`` and ``b`` are considered
-- equal.
--
-- If ``cmp`` is omitted they are compared with comparison operators ``<``
-- and ``>`` which can possibly be overridden via metatables.
--
-- Empty slots are not compared against anything. They are always moved to
-- the end of the array.
--
-- Unlike Lua's ``table.sort()``, this method performs a stable in-place
-- sort.
--
local function defaultCmp(a, b)
    if     a == nil then return (b == nil and 0) or 1
    elseif b == nil then return -1
    elseif a <  b   then return -1
    elseif a >  b   then return 1
    else                 return 0
    end
end
local function wrapCmp(cmp)
    return function (a, b)
        if     a == nil then return (b == nil and 0) or 1
        elseif b == nil then return -1
        else                 return cmp(a, b)
        end
    end
end
local function extendRun(a, len, cmp, i)
    -- Return the index of the end of the run (exclusive), starting from i.
    if i == len-1 then
        return i+1
    end
    local j = i+1
    if cmp(a[i+1], a[j+1]) <= 0 then
        while j < len and cmp(a[j], a[j+1]) <= 0 do
            j = j+1
        end
    else
        while j < len and cmp(a[j], a[j+1]) > 0 do
            j = j+1
        end
        -- Reverse elements from i to j. This doesn't cause an instability
        -- because the span [i, j) is strictly decreasing, i.e. no elements
        -- compare equal to any other elements.
        local i1, j1 = i, j-1
        while i1 < j1 do
            local tmp = a[i1+1]
            a[i1+1] = a[j1+1]
            a[j1+1] = tmp
            i1 = i1 + 1
            j1 = j1 - 1
        end
    end
    return j
end
local function power(runA, startB, lenB, len)
    local startA, lenA = runA[1], runA[2]
    assert(startB == startA + lenA)

    local a = 2 * startA + lenA
    local b = a + lenA + lenB
    local p = 0
    while true do
        p = p+1
        if a >= len then
            assert(b >= a)
            a = a - len
            b = b - len
        elseif b >= len then
            return p
        end
        assert(a < b and b < len)
        a = lshift(a, 1)
        b = lshift(b, 1)
    end
end
local function mergePosA(a, cmp, startA, endA, val)
    while startA < endA do
        local mPos = startA + rshift(endA - startA, 1)
        local mVal = a[mPos+1]
        if cmp(mVal, val) > 0 then
            endA = mPos
        else
            startA = mPos + 1
        end
    end
    return endA
end
local function mergePosB(a, cmp, startB, endB, val)
    while startB < endB do
        local mPos = startB + rshift(endB - startB, 1)
        local mVal = a[mPos+1]
        if cmp(mVal, val) < 0 then
            startB = mPos + 1
        else
            endB = mPos
        end
    end
    return startB
end
local function mergeInplace(a, cmp, i, m, j)
    assert(i < m and m < j)
    -- The first run spans [i, m), and the second run spans [m, j). Find
    -- out the position where the smallest element of the second run would
    -- be inserted into the first run.
    local from = mergePosA(a, cmp, i, m, a[m+1])
    -- And find out the position where the largest element of the first run
    -- would be inserted into the second run.
    local to = mergePosB(a, cmp, m, j, a[m])
    -- So, elements in [i, from) and [to, j) are already in their final
    -- positions and the runs in which elements movements are required are
    -- [from, m) and [m, to).
    if m - from <= to - m then
        -- [from, m) is smaller (or the sizes are the same). Copy them to a
        -- temporary buffer and merge runs from left to right.
        local tmp = {}
        for k=from, m-1 do
            tmp[k-from+1] = a[k+1]
        end

        local posA = from
        local posB = m
        for k=from, to-1 do
            if posA < m and (posB >= to or cmp(tmp[posA-from+1], a[posB+1]) <= 0) then
                -- Take element from the left run.
                a[k+1] = tmp[posA-from+1]
                posA   = posA + 1
            else
                -- Take element from the right run.
                a[k+1] = a[posB+1]
                posB   = posB + 1
            end
        end
    else
        -- [m, to) is smaller. Copy them to a temporary buffer and merge
        -- runs from right to left.
        local tmp = {}
        for k=m, to-1 do
            tmp[k-m+1] = a[k+1]
        end

        local posA = m-1
        local posB = to-1
        for k=to-1, from, -1 do
            if posA >= from and (posB < m or cmp(a[posA+1], tmp[posB-m+1]) > 0) then
                -- Take element from the left run.
                a[k+1] = a[posA+1]
                posA   = posA - 1
            else
                -- Take element from the right run.
                a[k+1] = tmp[posB-m+1]
                posB   = posB - 1
            end
        end
    end
end
local function mergeTopmost2(a, cmp, runs)
    assert(#runs >= 2)
    local y = runs[#runs-1]
    local z = runs[#runs  ]
    assert(z[1] == y[1] + y[2])
    mergeInplace(a, cmp, y[1], z[1], z[1] + z[2])
    y[2] = y[2] + z[2]
    runs[#runs] = nil
end
function AbstractArray:sort(cmp)
    assert(cmp == nil or type(cmp) == "function",
           class.nameOf(class.classOf(self)) .. "#sort() expects an optional comparator function")
    cmp = (cmp and wrapCmp(cmp)) or defaultCmp

    -- This implementation is a simplified PowerSort. It doesn't do
    -- galloping or insertion sort: https://power-sort.github.io/

    -- 1-based indices SERIOUSLY suck. All programmers on the earth have
    -- brain with 0-indices hardwired, and I am no exception. We use
    -- 0-indices in this entire PowerSort thing.

    local len  = self.length
    local i    = 0
    local runs = {} -- sequence of {start, length, power}
    local j    = extendRun(self, len, cmp, i)
    runs[#runs+1] = {i, j-i, 0}
    i = j
    while i < len do
        j = extendRun(self, len, cmp, i)
        local p = power(runs[#runs], i, j-i, len)
        while p <= runs[#runs][3] do
            mergeTopmost2(self, cmp, runs)
        end
        runs[#runs+1] = {i, j-i, p}
        i = j
    end
    while #runs >= 2 do
        mergeTopmost2(self, cmp, runs)
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
