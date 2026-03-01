local SemVer = require("semver")
local class  = require("class")
local fs     = require("fs")

local TAG     = "tag:cielonegro.org,2026:voice-hopper:subtitles" -- RFC 4151: Tag URI
local VERSION = SemVer:new("1.0.0")

--
-- An instance of Subtitles represents a subtitles setting. It supports two
-- formats on disk: our native format and ResolveScript-compatible format.
--
-- Our native format has the following structure:
-- {
--     schema     = "tag:cielonegro.org,2026:voice-hopper:subtitles",
--     version    = "1.0.0",
--     properties = {
--         [Entries of TextPlus "Inputs" except for StyledText, Width, and Height]
--     }
-- }
--
-- On the other hand, ResolveScript writes whatever Operator:SaveSettings()
-- outputs to files:
-- {
--     Tools = ordered() {
--         ["Whatever"] = TextPlus {
--             ...
--         }
--     }
-- }
--
local Subtitles = class("Subtitles")

function Subtitles:__init(tab)
    assert(type(tab) == "table" and getmetatable(tab) == nil,
           "Subtitles:new() expects a plain table")

    if tab.schema == TAG then
        -- Looks like it's our format. But what about its version?
        local ver = SemVer:new(tab.version)
        if ver.major == VERSION.major then
            -- Okay, we can read this.
            self._props = tab.properties

        elseif ver.major < VERSION.major then
            -- It's too old and we don't even know how to interpret this.
            error("Subtitles version too old: " .. tostring(ver), 2)

        else
            error("Subtitles from the future: " .. tostring(ver), 2)
        end
    else
        if type(tab.Tools) ~= "table" then
            error("No table \"Tools\" at /: " .. tostring(tab.Tools), 2)
        end
        for key, val in pairs(tab.Tools) do
            if type(val) == "table" and val.__ctor == "TextPlus" then
                if type(val.Inputs) ~= "table" then
                    error(string.format("No table \"Inputs\" at /Tools/%s", key), 2)
                end
                -- Found a TextPlus. Hope it's what we are looking for.
                self._props = val.Inputs
                return
            end
        end
        error("No TextPlus in /Tools", 2)
    end
end

Subtitles:static("readFile")
function Subtitles:readFile(p)
    assert(type(p) == "string", "Subtitles:readFile() expects a string path")

    -- luacheck: read_globals bmd
    assert(bmd, "Global \"bmd\" not defined")

    local str = fs.readFile(p)
    local val = bmd.readstring(str)
    if not val then
        error("Cannot parse " .. p, 2)
    end

    local ok, res = pcall(function()
        return Subtitles:new(val)
    end)
    if ok then
        return res
    else
        error(string.format("Invalid subtitles setting: %s: %s", p, res), 2)
    end
end

return Subtitles
