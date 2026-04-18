local Array = require("collection/array")
local class = require("class")

local TimelineItem = class("TimelineItem")

TimelineItem.CLIP_COLOURS = Array:from {
    "Orange",
    "Apricot",
    "Yellow",
    "Lime",
    "Olive",
    "Green",
    "Teal",
    "Navy",
    "Blue",
    "Purple",
    "Violet",
    "Pink",
    "Tan",
    "Beige",
    "Brown",
    "Chocolate"
}

return TimelineItem
