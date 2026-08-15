local Symbol   = require("symbol")
local readonly = require("readonly")

--
-- Reply for "no more data, please". The opposite of noMore is nil.
--
local noMore = Symbol("noMore")

--
-- Return true iff the given value is a valid Reply.
--
local function isReply(v)
    return v == nil or v == noMore
end

return readonly {
    noMore  = noMore,
    isReply = isReply,
}, true
