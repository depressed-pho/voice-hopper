local AbstractSet = require("collection/set/base")
local class       = require("class")

--
-- A finite set, implemented on top of primitive table.
--
local Set = class("Set", AbstractSet)

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
-- The number of elements in the set.
--
function Set.__getter:size()
    return self._size
end

--
-- Create a shallow copy of the set.
--
function Set:clone()
    local ret = Set:new()

    for elem, _true in pairs(self._tab) do
        ret._tab[elem] = true
    end
    ret._size = self._size

    return ret
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
-- Set#has(elem) returns true if "elem" is an element of the set, or false
-- otherwise.
--
function Set:has(elem)
    assert(elem ~= nil, "Set#has() expects a non-nil value")

    return self._tab[elem] or false
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
    return coroutine.wrap(
        function ()
            for elem, _true in pairs(self._tab) do
                coroutine.yield(elem)
            end
        end)
end

return Set
