local Colour      = require("colour")
local ConsoleBase = require("console/base")
local Tree        = require("widget/tree")
local TreeColumn  = require("widget/tree/column")
local TreeItem    = require("widget/tree/item")
local class       = require("class")

--
-- The Logger widget is a subclass of the Tree widget and provides the
-- Console API.
--
local Logger = class("Logger", ConsoleBase(Tree))

function Logger:__init()
    super(1)
    --self.indent = 0
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
        local col = TreeColumn:new(msg)
        local c   = sev2colour(sev)
        if c then
            col.colour.bg = c[1]
            col.colour.fg = c[2]
        end
        self:addItem(TreeItem:new {col})
    else
        error("Logging before materialisation is currently unsupported", 2)
    end
end

function Logger:traceImpl(sev, trace, ...)
    if self.materialised then
        local traceCol = TreeColumn:new(trace)
        local c        = sev2colour(sev)
        if c then
            traceCol.colour.bg = c[1]
            traceCol.colour.fg = c[2]
        end
        local traceItem = TreeItem:new {traceCol}

        if select("#", ...) > 0 then
            local msg    = sev2str(sev) .. self:format(...)
            local msgCol = TreeColumn:new(msg)
            if c then
                msgCol.colour.bg = c[1]
                msgCol.colour.fg = c[2]
            end
            local msgItem = TreeItem:new {msgCol}
            msgItem:addChild(traceItem)
            self:addItem(msgItem)
        else
            self:addItem(traceItem)
        end
    else
        error("Logging before materialisation is currently unsupported", 2)
    end
end

return Logger
