local AbstractImmutableSet = require("collection/set/immutable/base")
local class                = require("class")

--
-- An immutable set that reflects another set, possibly a mutable one.
--
local ReflectiveSet = class("ReflectiveSet", AbstractImmutableSet)

--
-- Construct a reflective set out of another set. The type of the base set
-- is irrelevant.
--
function ReflectiveSet:__init(base)
    assert(AbstractImmutableSet:made(base), "ReflectiveSet:new() expects a set")

    self._base = base
end

--
-- The number of elements in the set.
--
function ReflectiveSet.__getter:size()
    return self._base.size
end

--
-- :has(elem) returns true if "elem" is an element of the set, or false
-- otherwise.
--
function ReflectiveSet:has(elem)
    return self._base:has(elem)
end

--
-- :values() returns an iterator which iterates over its elements in an
-- unspecified order.
--
function ReflectiveSet:values()
    return self._base:values()
end

return ReflectiveSet
