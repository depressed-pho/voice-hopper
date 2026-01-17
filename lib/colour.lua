local class = require("class")

local Colour = class("Colour")

-- internal
function Colour:__init(r, g, b, a)
    assert(type(r) == "number" and r >= 0.0 and r <= 1.0, "must satisfy 0 <= r <= 1: " .. tostring(r))
    assert(type(g) == "number" and g >= 0.0 and g <= 1.0, "must satisfy 0 <= g <= 1: " .. tostring(g))
    assert(type(b) == "number" and b >= 0.0 and b <= 1.0, "must satisfy 0 <= b <= 1: " .. tostring(b))
    a = a or 1.0
    assert(type(a) == "number" and a >= 0.0 and a <= 1.0, "must satisfy 0 <= a <= 1: " .. tostring(a))

    self._r = r
    self._g = g
    self._b = b
    self._a = a
end

Colour:static("rgb")
function Colour:rgb(r, g, b)
    return Colour:new(r, g, b)
end

Colour:static("rgba")
function Colour:rgba(r, g, b, a)
    return Colour:new(r, g, b, a)
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

function Colour.__getter:a()
    return self._a
end

--
-- Convert a colour into a css "rgba()" expression.
--
function Colour:asCSS()
    return tostring(self)
end

--
-- Convert a colour into a plain table that UIManager expects.
--
function Colour:asTable()
    return {
        R = self._r,
        G = self._g,
        B = self._b,
        A = self._a
    }
end

function Colour:__tostring()
    return string.format(
        "rgba(%d, %d, %d, %d)",
        math.floor(self._r * 255),
        math.floor(self._g * 255),
        math.floor(self._b * 255),
        math.floor(self._a * 255))
end

return Colour
