local EventEmitter = require("event-emitter")
local Set          = require("collection/set")
local class        = require("class")

local NATIVE_HORIZ_FOR = {
    left     = "AlignLeft",
    right    = "AlignRight",
    center   = "AlignHCenter",
    justify  = "AlignJustify",
}

local NATIVE_VERT_FOR = {
    top      = "AlignTop",
    bottom   = "AlignBottom",
    center   = "AlignVCenter",
    baseline = "AlignBaseline",
}

local Alignment = class("Alignment", EventEmitter())

function Alignment:__init(args)
    assert(type(args) == "table", "Alignment:new() expects a table")
    assert(NATIVE_HORIZ_FOR[args.horizontal],
           "\"horizontal\" is expected to be a valid horizontal alignment")
    assert(NATIVE_VERT_FOR[args.vertical],
           "\"vertical\" is expected to be a valid horizontal alignment")

    super(Set:new {"update"})
    self._horiz = args.horizontal
    self._vert  = args.vertical
end

--
-- Horizontal alignment: one of "left", "right", "center", and "justify".
--
function Alignment.__getter:horizontal()
    return self._horiz
end
function Alignment.__setter:horizontal(horiz)
    assert(NATIVE_HORIZ_FOR[horiz],
           "Alignment#horizontal is expected to be a valid horizontal alignment")
    self._horiz = horiz
    self:emit("update", "horizontal", horiz)
end

--
-- Vertical alignment: one of "top", "bottom", "center", and "baseline".
--
function Alignment.__getter:vertical()
    return self._vert
end
function Alignment.__setter:vertical(vert)
    assert(NATIVE_VERT_FOR[vert],
           "Alignment#vertical is expected to be a valid vertical alignment")
    self._vert = vert
    self:emit("update", "vertical", vert)
end

--
-- Convert an alignment into a plain table that UIManager expects.
--
function Alignment:asTable()
    return {
        [NATIVE_HORIZ_FOR[self._horiz]] = true,
        [NATIVE_VERT_FOR [self._vert ]] = true,
    }
end

return Alignment
