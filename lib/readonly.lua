-- Create a read-only alias of a table.
local function readonly(tab)
    assert(type(tab) == "table", "readonly() expects a table")
    return setmetatable(
        {},
        {
            __index = tab,
            __newindex = function()
                error("Cannot modify a read-only table", 2)
            end
        })
end

return readonly
