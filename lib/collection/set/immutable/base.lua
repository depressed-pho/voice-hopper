local class = require("class")

--
-- The base class for immutable sets.
--
local AbstractImmutableSet = class("AbstractImmutableSet")

--
-- The string representation of the set.
--
function AbstractImmutableSet:__tostring()
    local elems = {}
    for elem in self:values() do
        if type(elem) == "string" then
            table.insert(elems, string.format("%q", elem))
        else
            table.insert(elems, tostring(elem))
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
-- The number of elements in the set.
--
AbstractImmutableSet:abstract("getter:size")

--
-- The ".." operator is an alias to :union().
--
function AbstractImmutableSet.__concat(s1, s2)
    assert(AbstractImmutableSet:made(s1) and AbstractImmutableSet:made(s2),
           string.format("Sets can only be concatenated with another set: %s .. %s", s1, s2))
    return s1:union(s2)
end

--
-- The "-" operator is an alias to :difference().
--
function AbstractImmutableSet.__sub(s1, s2)
    assert(AbstractImmutableSet:made(s1) and AbstractImmutableSet:made(s2),
           string.format("Sets can only be subtracted by another set: %s - %s", s1, s2))
    return s1:difference(s2)
end

--
-- Create a shallow copy of the set.
--
function AbstractImmutableSet:clone()
    return self -- because this is an immutable set.
end

--
-- :difference(other) returns a new set containing elements in this set
-- but not in "other".
--
local DifferenceSet = class("DifferenceSet", AbstractImmutableSet)
function DifferenceSet:__init(s1, s2)
    self._s1 = s1
    self._s2 = s2
end
function DifferenceSet.__getter:size()
    local ret = 0
    for elem in self._s1:values() do
        if not self._s2.has(elem) then
            ret = ret + 1
        end
    end
    return ret
end
function DifferenceSet:has(elem)
    return self._s1:has(elem) and not self._s2:has(elem)
end
function DifferenceSet:values()
    return coroutine.wrap(
        function ()
            for elem in self._s1:values() do
                if not self._s2:has(elem) then
                    coroutine.yield(elem)
                end
            end
        end)
end
function AbstractImmutableSet:difference(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#difference() expects another set")

    -- We'd like to define this class in a separate file, but then it'd
    -- form a circular dependency.
    return DifferenceSet:new(self, other)
end

--
-- :has(elem) returns true if "elem" is an element of the set, or false
-- otherwise.
--
AbstractImmutableSet:abstract("has")

--
-- :intersection(other) returns a new set containing elements both in this
-- and "other" sets.
--
local IntersectionSet = class("IntersectionSet", AbstractImmutableSet)
function IntersectionSet:__init(s1, s2)
    self._s1 = s1
    self._s2 = s2
end
function IntersectionSet.__getter:size()
    local ret = 0
    for elem in self._s1:values() do
        if self._s2:has(elem) then
            ret = ret + 1
        end
    end
    return ret
end
function IntersectionSet:has(elem)
    return self._s1:has(elem) and self._s2:has(elem)
end
function IntersectionSet:values()
    return coroutine.wrap(
        function ()
            for elem in self._s1:values() do
                if self._s2:has(elem) then
                    coroutine.yield(elem)
                end
            end
        end)
end
function AbstractImmutableSet:intersection(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#intersection() expects another set")

    return IntersectionSet:new(self, other)
end

--
-- :isDisjointFrom(other) returns true if this set has no elements in
-- common with the other set, or false otherwise.
--
function AbstractImmutableSet:isDisjointFrom(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#isDisjointFrom() expects another set")

    for elem in self:values() do
        if other:has(elem) then
            return false
        end
    end
    return true
end

--
-- :isSubsetOf(other) returns true if all elements of this set are also in
-- the other set.
--
function AbstractImmutableSet:isSubsetOf(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#isSubsetOf() expects another set")

    for elem in self:values() do
        if not other:has(elem) then
            return false
        end
    end
    return true
end

--
-- :isSupersetOf(other) returns true if all elements of the other set are
-- also in this set.
--
function AbstractImmutableSet:isSupersetOf(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#isSupersetOf() expects another set")

    for elem in other:values() do
        if not self:has(elem) then
            return false
        end
    end
    return true
end

--
-- :symmetricDifference(other) returns a new set containing elements which
-- are either in this set or the other set, bot not in both.
--
local SymmetricDifferenceSet = class("SymmetricDifferenceSet", AbstractImmutableSet)
function SymmetricDifferenceSet:__init(s1, s2)
    self._s1 = s1
    self._s2 = s2
end
function SymmetricDifferenceSet.__getter:size()
    local ret = 0
    for elem in self._s1:values() do
        if not self._s2.has(elem) then
            ret = ret + 1
        end
    end
    for elem in self._s2:values() do
        if not self._s1:has(elem) then
            ret = ret + 1
        end
    end
    return ret
end
function SymmetricDifferenceSet:has(elem)
    local h1 = self._s1:has(elem)
    local h2 = self._s2:has(elem)
    return h1 ~= h2
end
function SymmetricDifferenceSet:values()
    return coroutine.wrap(
        function ()
            for elem in self._s1:values() do
                if not self._s2:has(elem) then
                    coroutine.yield(elem)
                end
            end
            for elem in self._s2:values() do
                if not self._s1:has(elem) then
                    coroutine.yield(elem)
                end
            end
        end)
end
function AbstractImmutableSet:symmetricDifference(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#symmetricDifference() expects another set")

    return SymmetricDifferenceSet:new(self, other)
end

--
-- :union(other) returns a new set containing elements which are either or
-- both in this set and the other set.
--
local UnionSet = class("UnionSet", AbstractImmutableSet)
function UnionSet:__init(s1, s2)
    self._s1 = s1
    self._s2 = s2
end
function UnionSet:has(elem)
    return self._s1:has(elem) or self._s2:has(elem)
end
function UnionSet:values()
    return coroutine.wrap(
        function ()
            for elem in self._s1:values() do
                coroutine.yield(elem)
            end
            for elem in self._s2:values() do
                if not self._s1:has(elem) then
                    coroutine.yield(elem)
                end
            end
        end)
end
function AbstractImmutableSet:union(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#union() expects another set")

    return UnionSet:new(self, other)
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
AbstractImmutableSet:abstract("values")

--
-- Convert a set into a sequence with an unspecified order.
--
function AbstractImmutableSet:toSeq()
    local seq = {}
    for elem in self:values() do
        table.insert(seq, elem)
    end
    return seq
end

return AbstractImmutableSet
