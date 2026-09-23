local String  = require("ustring")
local Voice   = require("entity/voice")
local class   = require("class")
local console = require("console")
local fs      = require("fs")
local path    = require("path")

-- @private
local Subtitle = class("Subtitle")
function Subtitle:__init(voice)
    assert(Voice:made(voice))

    self._audioEnt = voice.audio    -- DirEnt
    self._subEnt   = voice.subtitle -- DirEnt|nil
    self._text     = nil            -- string|nil
end
function Subtitle.__getter:text()
    if not self._text then
        if self._subEnt then
            -- The file is there. We just haven't read it yet.
            local ok, ret = pcall(fs.readFile, self._subEnt.path)
            if ok then
                self._text = tostring(String:new(ret):trim())
            else
                -- The file is gone now? This is not an error.
                console:warn("%s", ret)
            end
        end
    end
    return self._text
end
function Subtitle:update(voice)
    assert(Voice:made(voice))

    self._audioEnt = voice.audio
    if self._text then
        if voice.subtitle then
            -- We've read the file, and the file still exists. But does
            -- it still have the same text?
            if self._subEnt.lastModified == voice.subtitle.lastModified then
                -- It most likely is.
            else
                -- Probably not. Forget the text we previously read.
                self._text = nil
            end
        else
            -- There was a file but it no longer exists. Dunno why the
            -- user deleted it, but we should probably forget it now.
            self._text = nil
        end
    end
    self._subEnt = voice.subtitle
end
function Subtitle:save(text)
    assert(type(text) == "string")

    -- If no subtitle files exist, infer its file name from the audio file.
    if not self._subEnt then
        local parsed = path.parse(self.audio.path)
        self._subEnt = path.join(parsed.dir, parsed.name .. ".txt")
    end

    self._text = text
    fs.writeFile(self._subEnt.path, self._text)
end
function Subtitle:delete()
    if self._subEnt then
        fs.rm(self._subEnt.path)
        self._subEnt = nil
        self._text   = nil
    end
end

return Subtitle
