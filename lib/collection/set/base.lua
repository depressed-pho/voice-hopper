local AbstractImmutableSet = require("collection/set/immutable/base")
local class                = require("class")

--
-- The base class for mutable sets.
--
local AbstractSet = class("AbstractSet", AbstractImmutableSet)

--
-- Add an element to the set.
--
AbstractSet:abstract("add")

--
-- Delete all the elements in the set.
--
AbstractSet:abstract("clear")

--
-- Delete a specified element in the set. Return true if it's found, false
-- otherwise.
--
AbstractSet:abstract("delete")

--
-- Set#difference(other) returns a new set containing elements in this set
-- but not in "other".
--
function AbstractSet:difference(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#difference() expects another set")

    local ret = self:clone()
    for elem in other:values() do
        ret:delete(elem)
    end
    return ret
end

--
-- Set#intersection(other) returns a new set containing elements both in
-- this and "other" sets.
--
function AbstractSet:intersection(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#intersection() expects another set")

    local ret = self:clone()
    for elem in self:values() do
        if not other:has(elem) then
            ret:delete(elem)
        end
    end
    return ret
end

--
-- Set#symmetricDifference(other) returns a new set containing elements
-- which are either in this set or the other set, bot not in both.
--
function AbstractSet:symmetricDifference(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#symmetricDifference() expects another set")

    local ret = self:clone()
    for elem in self:values() do
        if other:has(elem) then
            ret:delete(elem)
        end
    end
    return ret
end

--
-- Set#union(other) returns a new set containing elements which are either
-- or both in this set and the other set.
--
function AbstractSet:union(other)
    assert(AbstractImmutableSet:made(other),
           class.nameOf(class.classOf(self)) .. "#union() expects another set")

    local ret = self:clone()
    for elem in other:values() do
        ret:add(elem)
    end
    return ret
end

return AbstractSet
