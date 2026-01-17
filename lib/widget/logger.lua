local Colour      = require("colour")
local ConsoleBase = require("console/base")
local TextEdit    = require("widget/text-edit")
local class       = require("class")

--
-- The Logger widget is a subclass of the TextEdit widget and provides the
-- Console API.
--
-- Why TextEdit? Wouldn't it be better to use Tree instead? Because
-- Tree#wordWrap, just, doesn't, work.
--
local Logger = class("Logger", ConsoleBase(TextEdit))

function Logger:__init()
    super()
    self.readOnly = true
end

local function sev2str(sev)
    if     sev == Logger.Severity.debug then return "🐞" -- U+1F41E LADY BEETLE
    elseif sev == Logger.Severity.log   then return ""
    elseif sev == Logger.Severity.info  then return "ⓘ" -- U+24D8 CIRCLED LATIN SMALL LETTER I
    elseif sev == Logger.Severity.warn  then return "⚠️" -- U+26A0 WARNING SIGN
    elseif sev == Logger.Severity.error then return "ERROR: "
    else
        error("Unknown severity: "..tostring(sev), 2)
    end
end

local C_WARN  = {Colour:rgb(0.25, 0.21, 0.13), Colour:rgb(0.97, 0.89, 0.66)} -- bg, fg
local C_ERROR = {Colour:rgb(0.27, 0.19, 0.21), Colour:rgb(0.95, 0.71, 0.82)}
local function sev2colour(sev)
    if     sev == Logger.Severity.warn  then return C_WARN
    elseif sev == Logger.Severity.error then return C_ERROR
    else
        return nil
    end
end

function Logger:logImpl(sev, ...)
    if self.materialised then
        local msg = sev2str(sev) .. self:format(...)
        local c   = sev2colour(sev)
        self.colour.bg = (c and c[1]) or nil
        self.colour.fg = (c and c[2]) or nil
        self:append(msg)
    else
        error("Logging before materialisation is currently unsupported", 2)
    end
end

function Logger:traceImpl(sev, trace, ...)
    if self.materialised then
        local msg = {}
        if select("#", ...) > 0 then
            table.insert(msg, sev2str(sev))
            table.insert(msg, self:format(...))
            table.insert(msg, "\n")
        end
        table.insert(msg, trace)

        local c = sev2colour(sev)
        self.colour.bg = (c and c[1]) or nil
        self.colour.fg = (c and c[2]) or nil
        self:append(table.concat(msg))
    else
        error("Logging before materialisation is currently unsupported", 2)
    end
end

return Logger
