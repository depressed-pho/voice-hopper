local class = require("class")

--
-- The base class for immutable maps.
--
local AbstractImmutableMap = class("AbstractImmutableMap")

--
-- The string representation of the map.
--
function AbstractImmutableMap:__tostring()
    local ents = {}
    for k, v in self:entries() do
        local ent = {}
        if type(k) == "string" then
            if string.find(k, "^[%a_][%w_]*$") then
                -- This key is an identifier.
                table.insert(ent, k)
            else
                table.insert(ent, string.format("[%q]", k))
            end
        else
            table.insert(ent, "[")
            table.insert(ent, tostring(k))
            table.insert(ent, "]")
        end
        table.insert(ent, " = ")
        table.insert(ent, tostring(v))
        table.insert(ents, table.concat(ent))
    end
    return table.concat {
        class.nameOf(class.classOf(self)),
        " {",
        table.concat(ents, ", "),
        "}"
    }
end

--
-- The number of entries in the map.
--
AbstractImmutableMap:abstract("getter:size")

--
-- Get a value that corresponds to the given key, or nil if it's not found.
--
AbstractImmutableMap:abstract("get")

--
-- Return true if the map has a value corresponding to the given key, or
-- false otherwise.
--
function AbstractImmutableMap:has(k)
    return self:get(k) ~= nil
end

--
-- Map#keys() returns an iterator which iterates over its keys:
--
--   local m = Set:new {
--       foo = 10,
--       bar = 20
--   }
--   for key in m:keys() do
--       print(key)
--   end
--   -- Prints "foo" and "bar" but in an unspecified order.
--
AbstractImmutableMap:abstract("keys")

--
-- Map#entries() returns an iterator which iterates over its keys and
-- values, just like the built-in function pairs() for tables.
--
AbstractImmutableMap:abstract("entries")

--
-- Map#toTable() returns a shallow copy of the map represented as a Lua
-- table.
--
function AbstractImmutableMap:toTable()
    local tab = {}
    for k, v in self:entries() do
        tab[k] = v
    end
    return tab
end

return AbstractImmutableMap
