--
-- Create a read-only alias of a table.
--
local function readonly(tab, opts)
    assert(type(tab) == "table", "readonly() expects a table as its 1st argument")

    opts = opts or {}
    assert(type(opts) == "table", "readonly() expects an optional table as its 2nd argument")

    opts.errOnMissingKeys = opts.errOnMissingKeys or false
    assert(type(opts.errOnMissingKeys) == "boolean", "errOnMissingKeys is expected to be a boolean")

    local meta = {}

    function meta.__newindex()
        error("Cannot modify a read-only table", 2)
    end

    if opts.errOnMissingKeys then
        function meta.__index(_self, key)
            local val = tab[key]
            if val == nil then
                error("No such key exists in the table: " .. key, 2)
            else
                return val
            end
        end
    else
        meta.__index = tab
    end

    return setmetatable({}, meta)
end

return readonly
