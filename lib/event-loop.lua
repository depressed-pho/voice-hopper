local class = require("class")
local fun   = require("function")
local ui    = require("ui")

local EventLoop = class("EventLoop")

-- protected: Don't call this directly. Subclasses can override this but
-- don't forget to call super:run(). User code should call :start()
-- instead.
function EventLoop:run()
    ui.dispatcher:RunLoop()
end

function EventLoop:start()
    fun.onException(
        function()
            self:run()
        end,
        function()
            ui.dispatcher:ExitLoop()
        end)
end

return EventLoop
