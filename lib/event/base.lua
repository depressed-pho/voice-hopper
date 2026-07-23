local Symbol = require("symbol")
local class  = require("class")

local symIsCanceled = Symbol("Event::isCanceled")

--
-- The Event base class: root of all events.
--
local Event = class("Event")

function Event:__init()
    -- Avoid conflicts with subclass fields. Also avoid interaction with
    -- subclass __newindex.
    rawset(self, symIsCanceled, false)
end

--
-- True iff its :cancel() method has been called.
--
function Event.__getter:isCanceled()
    return self[symIsCanceled]
end

--
-- Cancel the event. When an event is cancelled, no event handlers will be
-- further invoked for this specific event. Its default action won't be
-- performed either.
--
function Event:cancel()
    self[symIsCanceled] = true
    return self
end

return Event
