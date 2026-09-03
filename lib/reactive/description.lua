local ImmutableArray = require("collection/array/immutable")
local class          = require("class")

--
-- Description: A class that is a structured version of what tostring() returns.
--
local Description = class("Description")

function Description:__init(context, method, ...)
    if not context then
        require("console"):trace()
    end
    assert(context ~= nil, "Description:new() expects a non-nil context as its 1st argument")
    assert(type(method) == "string", "Description:new() expects a string method as its 2nd argument")

    self._context = context
    self._method  = method
    self._args    = ImmutableArray:of(...)
end

function Description:__tostring()
    return table.concat {
        tostring(self._context),
        ".",
        tostring(self._method),
        "(",
        self._args:map(tostring):join(", "),
        ")"
    }
end

return Description
