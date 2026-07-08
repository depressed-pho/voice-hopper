local AbstractImmutableMap = require("collection/map/immutable/base")
local class                = require("class")

--
-- The base class for mutable maps.
--
local AbstractMap = class("AbstractMap", AbstractImmutableMap)

--
-- Insert an entry to the map, or replace an existing value.
--
AbstractMap:abstract("set")

--
-- Delete all the entries in the map.
--
AbstractMap:abstract("clear")

--
-- Delete a key in the map. Return true if it's found, false otherwise.
--
AbstractMap:abstract("delete")

return AbstractMap
