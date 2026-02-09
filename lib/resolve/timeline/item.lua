local class    = require("class")
local readonly = require("readonly")

local TimelineItem = class("TimelineItem")

TimelineItem.CLIP_COLOURS =
    readonly {
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
