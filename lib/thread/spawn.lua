local Thread = require("thread")
local class  = require("class")

-- Usage:
--
--   local thr = spawn(func)
--   or
--   local thr = spawn(name, func)
--
-- where "func" is a function taking a cancellation promise. The function
-- returns an instance of Thread.
local function spawn(name, func)
    if type(func) and func == nil then
        func = name
        name = "(anonymous)"
    end
    assert(type(name) == "string", "spawn() expects either a thread name or a function as its 1st argument")
    assert(type(func) == "function", "spawn() expects a function as its 2nd argument if it's given a name")

    local T = class(Thread)
    function T:run(cancelled)
        func(cancelled)
    end
    return T:new(name):start()
end

return spawn
