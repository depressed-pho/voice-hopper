local class = require("class")
local ui    = require("ui")

local EventLoop = class("EventLoop")

function EventLoop:run()
    ui.dispatcher:RunLoop()
end

return EventLoop
