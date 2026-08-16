local AbstractImmutableArray = require("collection/array/immutable/base")
local class                  = require("class")

--
-- An immutable array that reflects another array, possibly a mutable one.
--
local ReflectiveArray = class("ReflectiveArray", AbstractImmutableArray)

--
-- Construct a reflective array out of another array. The type of the base
-- array is irrelevant.
--
function ReflectiveArray:__init(base)
    assert(AbstractImmutableArray:made(base), "ReflectiveArray:new() expects an array")

    self._base = base
end

--
-- The maximum index of the array, regardless of whether it is sparse or
-- not.
--
function ReflectiveArray.__getter:length()
    return self._base.length
end

--
-- arr[idx] indexes an element, or nil if no such element exists.
--
function ReflectiveArray:__index(idx)
    return self._base[idx]
end

return ReflectiveArray
