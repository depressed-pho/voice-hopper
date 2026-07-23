local Event = require("event/base")
local class = require("class")

--
-- The root of UI events, mostly coming from widgets.
--
local UIEvent = class("UIEvent", Event)

-- @private
function UIEvent:__init(raw)
    super()
    self._raw = raw
end

return UIEvent
