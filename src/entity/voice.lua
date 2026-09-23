local Array = require("collection/array")
local class = require("class")
local path  = require("path")

-- @private
local Voice = class("Voice")
function Voice:__init(name, audio, subtitle, lipSync)
    self.name     = name     -- string
    self.audio    = audio    -- DirEnt
    self.subtitle = subtitle -- DirEnt|nil
    self.lipSync  = lipSync  -- DirEnt|nil
end
function Voice:__tostring()
    local props = Array:of(
        "name = " .. self.name,
        "audio = " .. tostring(self.audio),
        "subtitle = " .. tostring(self.subtitle),
        "lipSync = " .. tostring(self.lipSync))
    return table.concat {
        "Voice {",
        props:join(", "),
        "}"
    }
end
function Voice.__getter:audioType()
    if not self._audioType then
        local parsed = path.parse(self.audio.name)
        if string.find(parsed.ext, "^%.") then
            return string.upper(string.sub(parsed.ext, 2))
        else
            return nil -- No extension
        end
    end
    return self._audioType
end

return Voice
