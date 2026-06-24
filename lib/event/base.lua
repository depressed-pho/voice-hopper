local Symbol = require("symbol")
local class  = require("class")

local isCanceled = Symbol("isCanceled")

--
-- The Event base class: root of all events.
--
local Event = class("Event")

function Event:__init()
    -- Avoid conflicts with subclass fields. Also avoid interaction with
    -- subclass __newindex.
    rawset(self, isCanceled, false)
end

--
-- True iff its :cancel() method has been called.
--
function Event.__getter:isCanceled()
    return rawget(self, isCanceled)
end

--
-- Cancel the event. When an event is cancelled, no event handlers will be
-- further invoked for this specific event. Its default action won't be
-- performed either.
--
function Event:cancel()
    rawset(self, isCanceled, true)
end

return Event
