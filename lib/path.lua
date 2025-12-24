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

--
-- path.resolve() attempts to resolve a Fusion path mapping:
--
--   path.resolve("Config:/Foo.fu")
--
-- By default it raises an error when it fails to resolve the path. You can
-- change the behaviour by doing:
--
--   path.resolve(p, {relaxed = true})
--
-- In this case the function returns the given path unchanged, instead of
-- raising an error.
--
function path.resolve(p, opts)
    assert(type(p) == "string", "path.resolve() expects a string path as its 1st argument")

    opts = opts or {}
    assert(type(opts) == "table", "path.resolve() expects an optional table as its 2nd argument")

    opts.relaxed = opts.relaxed or false
    assert(type(opts.relaxed) == "boolean", "path.resolve(): option \"relaxed\" must be a boolean")

    if app == nil then
        error("The global \"app\" is not defined. This function can only be called inside of Fusion", 2)
    end

    local ret = app:MapPath(p)
    if ret == p and not opts.relaxed then
        error("Failed to resolve a path mapping: " .. p, 2)
    else
        return ret
    end
end

return readonly(path)
