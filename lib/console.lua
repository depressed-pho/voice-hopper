local ConsoleBase = require("console/base")
local class       = require("class")

--
-- An implementation of the Console API that prints logs to the default output.
--
local Console = class("Console", ConsoleBase())

local function sev2str(sev)
    if     sev == Console.Severity.debug then return "DEBUG: "
    elseif sev == Console.Severity.log   then return ""
    elseif sev == Console.Severity.info  then return "INFO: "
    elseif sev == Console.Severity.warn  then return "WARNING: "
    elseif sev == Console.Severity.error then return "ERROR: "
    else
        error("Unknown severity: "..tostring(sev), 2)
    end
end

function Console:logImpl(sev, ...)
    print(sev2str(sev) .. self:format(...))
end

function Console:traceImpl(sev, trace, ...)
    if select("#", ...) > 0 then
        self:logImpl(sev, ...)
    end
    print(trace)
end

return Console:new()
