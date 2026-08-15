local class    = require("class")
local readonly = require("readonly")

--
-- Event: The base class for all events passed through an EventStream or a Property.
--
local Event = class("Event")
function Event.__getter:value()
    error(class.nameOf(class.classOf(self)) .. " carries no values", 2)
end
function Event.__getter:error()
    error(class.nameOf(class.classOf(self)) .. " carries no errors", 2)
end
Event:abstract("map")

--
-- Value: The base class for all events carrying a value.
--
local Value = class("Value", Event)
function Value:__init(value)
    super()
    self._value = value
end
function Value.__getter:value()
    return self._value
end

--
-- NoValue: The base class for all events not carrying a value.
--
local NoValue = class("NoValue", Event)

--
-- Initial: An event carrying the initial value of a Property.
--
local Initial = class("Initial", Value)
function Initial:map(f)
    assert(type(f) == "function", "Initial#map() expects a value-mapping function")
    return Initial:new(f(self.value))
end

--
-- Next: Indicate a new value in an EventStream or a Property.
--
local Next = class("Next", Value)
function Next:map(f)
    assert(type(f) == "function", "Next#map() expects a value-mapping function")
    return Next:new(f(self.value))
end

--
-- End: An event that indicates the end of an EventStream or a Property. No
-- more events can be emitted after this one.
--
local End = class("End", NoValue)
function End:map(_f)
    return self
end

--
-- Error: An event carrying an error.
--
local Error = class("Error", NoValue)
function Error:__init(err)
    super()
    self._error = err
end
function Error.__getter:error()
    return self._error
end
function Error:map(_f)
    return self
end

return readonly {
    Event   = Event,

    Value   = Value,
    NoValue = NoValue,

    Initial = Initial,
    Next    = Next,

    End     = End,
    Error   = Error,
}, true
