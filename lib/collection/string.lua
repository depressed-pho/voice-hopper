-- luacheck: read_globals utf8
require("shim/utf8")
local class = require("class")

--
-- String represents a sequence of Unicode codepoints as opposed to octets.
--
local String = class("String")

--
-- Construct a String object out of a UTF-8 encoded string.
--
function String:__init(str)
    assert(type(str) == "string", "String:new() expects a UTF-8 string")
    self._str = str
end

--
-- tostring() returns a UTF-8 encoded string.
--
function String:__tostring()
    return self._str
end

--
-- String#reverse() reverses Unicode codepoints in place, and returns the
-- reference to the same String.
--
function String:reverse()
    local str = self._str
    local tmp = {}
    local pos = #str + 1
    while pos > 1 do
        local prev = utf8.offset(str, -1, pos)
        table.insert(tmp, string.sub(str, prev, pos-1))
        pos = prev
    end
    return table.concat(tmp)
end

return String
