local class = require("class")

--
-- A finite map, implemented on top of primitive table.
--
local Map = class("Map")

--
-- Construct a map. It optionally takes an iterator returning key, value
-- pairs which generates the initial contents of the map, or a Lua table of
-- elements.
--
function Map:__init(iter, ...)
    self._tab  = {} -- {[key] = value}
    self._size = 0

    if iter ~= nil then
        if type(iter) == "table" then
            for k, v in pairs(iter) do
                self:set(k, v)
            end
        elseif type(iter) == "function" then
            for k, v in iter, ... do
                self:set(k, v)
            end
        else
            error("Map:new() takes an optional iterator or a table of initial contents: "..tostring(iter), 2)
        end
    end
end

--
-- The string representation of the map.
--
function Map:__tostring()
    local ents = {}
    for k, v in pairs(self._tab) do
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
    return "Map {" .. table.concat(ents, ", ") .. "}"
end

--
-- The number of entries in the map.
--
function Map.__getter:size()
    return self._size
end

--
-- Get a value that corresponds to the given key, or nil if it's not found.
--
function Map:get(k)
    assert(k ~= nil, "Map#get() expects a non-nil key")

    return self._tab[k]
end

--
-- Return true if the map has a value corresponding to the given key, or
-- false otherwise.
--
function Map:has(k)
    assert(k ~= nil, "Map#has() expects a non-nil key")

    return not not self._tab[k]
end

--
-- Insert an entry to the map, or overwrite an existing value.
--
function Map:set(k, v)
    assert(k ~= nil, "Map#set() expects a non-nil key")
    assert(v ~= nil, "Map#set() expects a non-nil value")

    if self._tab[k] == nil then
        self._tab[k] = v
        self._size   = self._size + 1
    end

    return self
end

--
-- Delete all the entries in the map.
--
function Map:clear()
    self._tab  = {}
    self._size = 0

    return self
end

--
-- Delete a key in the map. Return true if it's found, false otherwise.
--
function Map:delete(k)
    assert(k ~= nil, "Map#delete() expects a non-nil key")

    if self._tab[k] == nil then
        return false
    else
        self._tab[k] = nil
        self._size   = self._size - 1
        return true
    end
end

return Map
