local class = require("class")

--
-- An instance of Option is either empty or has one value. The value can be
-- anything including nil.
--
local Option = class("Option")

function Option:__init(...)
    assert(select("#", ...) <= 1, "Option:new() expects zero or one value")

    self._hasValue = select("#", ...) > 0
    self._value    = ...
end

--
-- Option#hasValue is true iff it holds a value, or false otherwise.
--
function Option.__getter:hasValue()
    return self._hasValue
end

--
-- Option#value is the value it holds, or raises an error if it's
-- empty. Assigning anything to #value makes it non-empty.
--
function Option.__getter:value()
    if self._hasValue then
        return self._value
    else
        error("Attempted to dereference an empty Option", 2)
    end
end
function Option.__setter:value(v)
    self._hasValue = true
    self._value    = v
end

--
-- :clear() makes the Option empty.
--
function Option:clear()
    self._hasValue = true
    self._value    = nil
end

--
-- :unpack() returns zero or one value in the Option.
--
function Option:unpack()
    if self._hasValue then
        return self._value
    else
        return
    end
end

return Option
