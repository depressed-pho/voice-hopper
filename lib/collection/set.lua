local class = require("class")

--
-- A finite set, implemented on top of primitive table.
--
local Set = class("Set")

--
-- Construct a set. It optionally takes an iterator which generates the
-- initial contents of the set, or a Lua sequence of elements.
--
function Set:__init(iter, ...)
    self._tab  = {} -- {[key] = true}
    self._size = 0

    if iter ~= nil then
        if type(iter) == "table" then
            for _i, elem in ipairs(iter) do
                self:add(elem)
            end
        elseif type(iter) == "function" then
            for elem in iter, ... do
                self:add(elem)
            end
        else
            error("Set:new() takes an optional iterator or a sequence of initial contents: "..tostring(iter), 2)
        end
    end
end

--
-- The string representation of the set.
--
function Set:__tostring()
    local elems = {}
    for elem, _true in pairs(self._tab) do
        if type(elem) == "string" then
            table.insert(elems, string.format("%q", elem))
        else
            table.insert(elems, tostring(elem))
        end
    end
    return "Set {" .. table.concat(elems, ", ") .. "}"
end

--
-- The number of elements in the set.
--
function Set.__getter:size()
    return self._size
end

--
-- Add an element to the set.
--
function Set:add(elem)
    assert(elem ~= nil, "Set:add() expects a non-nil value")

    if not self._tab[elem] then
        self._tab[elem] = true
        self._size      = self._size + 1
    end

    return self
end

--
-- Delete all the elements in the set.
--
function Set:clear()
    self._tab  = {}
    self._size = 0

    return self
end

--
-- Delete a specified element in the set. Return true if it's found, false
-- otherwise.
--
function Set:delete(elem)
    assert(elem ~= nil, "Set#delete() expects a non-nil value")

    if self._tab[elem] then
        self._tab[elem] = nil
        self._size      = self._size - 1
        return true
    else
        return false
    end
end

--
-- Set#difference(other) returns a new set containing elements in this set
-- but not in "other".
--
function Set:difference(other)
    assert(Set:made(other), "Set#difference() expects a Set")

    local ret = Set:new()
    for elem, _true in pairs(self._tab) do
        if not other._tab[elem] then
            ret._tab[elem] = true
            ret._size      = ret._size + 1
        end
    end
    return ret
end

--
-- Set#has(elem) returns true if "elem" is an element of the set, or false
-- otherwise.
--
function Set:has(elem)
    assert(elem ~= nil, "Set#has() expects a non-nil value")

    return self._tab[elem] or false
end

--
-- Set#intersection(other) returns a new set containing elements both in
-- this and "other" sets.
--
function Set:intersection(other)
    assert(Set:made(other), "Set#intersection() expects a Set")

    local ret = Set:new()
    for elem, _true in pairs(self._tab) do
        if other._tab[elem] then
            ret._tab[elem] = true
            ret._size      = ret._size + 1
        end
    end
    return ret
end

--
-- Set#isDisjointFrom(other) returns true if this set has no elements in
-- common with the other set, or false otherwise.
--
function Set:isDisjointFrom(other)
    assert(Set:made(other), "Set#isDisjointFrom() expects a Set")

    for elem, _true in pairs(self._tab) do
        if other._tab[elem] then
            return false
        end
    end
    return true
end

--
-- Set#isSubsetOf(other) returns true if all elements of this set are also
-- in the other set.
--
function Set:isSubsetOf(other)
    assert(Set:made(other), "Set#isSubsetOf() expects a Set")

    for elem, _true in pairs(self._tab) do
        if not other._tab[elem] then
            return false
        end
    end
    return true
end

--
-- Set#isSupersetOf(other) returns true if all elements of the other set
-- are also in this set.
--
function Set:isSupersetOf(other)
    assert(Set:made(other), "Set#isSupersetOf() expects a Set")

    for elem, _true in pairs(other._tab) do
        if not self._tab[elem] then
            return false
        end
    end
    return true
end

--
-- Set#symmetricDifference(other) returns a new set containing elements
-- which are either in this set or the other set, bot not in both.
--
function Set:symmetricDifference(other)
    assert(Set:made(other), "Set#isSupersetOf() expects a Set")

    local ret = Set:new()
    for elem, _true in pairs(self._tab) do
        if not other._tab[elem] then
            ret._tab[elem] = true
            ret._size      = ret._size + 1
        end
    end
    for elem, _true in pairs(other._tab) do
        if not self._tab[elem] then
            ret._tab[elem] = true
            ret._size      = ret._size + 1
        end
    end
    return ret
end

--
-- Set#union(other) returns a new set containing elements which are either
-- or both in this set and the other set.
--
function Set:union(other)
    assert(Set:made(other), "Set#union() expects a Set")

    local ret = Set:new()

    for elem, _true in pairs(self._tab) do
        ret._tab[elem] = true
    end
    ret._size = self._size

    for elem, _true in pairs(other._tab) do
        if not ret._tab[elem] then
            ret._tab[elem] = true
            ret._size      = ret._size + 1
        end
    end

    return ret
end

--
-- Set#values() returns an iterator which iterates over its elements in an
-- unspecified order:
--
--   local s = Set:new()
--   s:add(1)
--   s:add(2)
--   for elem in s:values() do
--       print(elem)
--   end
--   -- Prints "1" and "2" but in an unspecified order.
--
function Set:values()
    local f, s, elem = pairs(self._tab)
    return function()
        elem = f(s, elem)
        return elem
    end
end

--
-- Convert a set into a sequence with an unspecified order.
--
function Set:toSeq()
    local seq = {}
    for elem, _true in pairs(self._tab) do
        table.insert(seq, elem)
    end
    return seq
end

return Set
