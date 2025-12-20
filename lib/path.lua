local readonly = require("readonly")

--
-- Manipulating file paths.
--
local path = {}

--
-- path.sep is a platform-specific path segment separator
--
assert(
    package.config ~= nil,
    "The path module requires package.config to be available. Maybe Lua is too old?")
path.sep = package.config:sub(1, 1)

--
-- The path.join() function joins all given path segments together using
-- the platform-specific separator as a delimiter.
--
-- Unlike Node.js path.join(), this function does not normalise the
-- resulting path string. All it does is to simply concatenate path
-- segments.
--
-- An error is raised if any of the path segments is not a string.
--
function path.join(...)
    -- First, check if all of the arguments are strings. We don't perform
    -- automatic tostring().
    local n = select("#", ...)
    for i=1, n do
        local arg = select(i, ...)
        if type(arg) ~= "string" then
            error(string.format("path.join(): %d-th argument is a non-string: %s", i, arg), 2)
        end
    end
    return table.concat({...}, path.sep)
end

return readonly(path)
