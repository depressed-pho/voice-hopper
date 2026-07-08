local AbstractImmutableSet = require("collection/set/immutable/base")
local AbstractImmutableMap = require("collection/map/immutable/base")
local class                = require("class")

--
-- An immutable set that reflects keys of a map, possibly a mutable one.
--
local KeySet = class("KeySet", AbstractImmutableSet)

--
-- Construct a key set out of a map. The type of the map is irrelevant.
--
function KeySet:__init(map)
    assert(AbstractImmutableMap:made(map), "KeySet:new() expects a map")

    self._map = map
end

--
-- The number of elements in the set.
--
function KeySet.__getter:size()
    return self._map.size
end

--
-- :has(elem) returns true if "elem" is an element of the set, or false
-- otherwise.
--
function KeySet:has(elem)
    return self._map:has(elem)
end

--
-- :values() returns an iterator which iterates over its elements in an
-- unspecified order.
--
function KeySet:values()
    return self._map:keys()
end

return KeySet
