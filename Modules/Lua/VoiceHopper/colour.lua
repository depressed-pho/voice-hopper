local class = require("VoiceHopper/class")

local Colour = class("Colour")

-- internal
function Colour:__init(r, g, b)
    assert(type(r) == "number" and r >= 0.0 and r <= 1.0, "must satisfy 0 <= r <= 1: " .. tostring(r))
    assert(type(g) == "number" and g >= 0.0 and g <= 1.0, "must satisfy 0 <= g <= 1: " .. tostring(g))
    assert(type(b) == "number" and b >= 0.0 and b <= 1.0, "must satisfy 0 <= b <= 1: " .. tostring(b))
    self._r = r
    self._g = g
    self._b = b
end

function Colour.rgb(r, g, b)
    return Colour:new(r, g, b)
end

function Colour.__getter:r()
    return self._r
end

function Colour.__getter:g()
    return self._g
end

function Colour.__getter:b()
    return self._b
end

function Colour:asCSS()
    return tostring(self)
end

function Colour:__tostring()
    return string.format(
        "rgb(%d, %d, %d)",
        math.floor(self._r * 255),
        math.floor(self._g * 255),
        math.floor(self._b * 255))
end

return Colour
