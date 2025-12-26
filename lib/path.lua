--
-- Manipulating file paths.
--

-- Generic implementations.
local generic = {}

-- Platform-specific implementations.
local platforms = {
    posix   = {},
    windows = {},
}

local PLATFORM_OF = {
    ["/" ] = "posix",
    ["\\"] = "windows"
}
assert(
    package.config ~= nil,
    "The path module requires package.config to be available. Maybe Lua is too old?")
local platform
do
    local sep = package.config:sub(1, 1)
    platform = PLATFORM_OF[sep]
    if platform == nil then
        error(string.format("We don't know this platform as it uses \"%s\" as the path separator", sep), 2)
    end
end

--
-- path.sep is a platform-specific path segment separator
--
platforms.posix.sep   = "/"
platforms.windows.sep = "\\"

--
-- path.join(...) joins all given path segments together using the
-- platform-specific separator as a delimiter.
--
-- Unlike Node.js path.join(), this function does not normalise the
-- resulting path string. All it does is to simply concatenate path
-- segments.
--
-- An error is raised if any of the path segments is not a string
--
function generic.join(ns, ...)
    -- First, check if all of the arguments are strings. We don't perform
    -- automatic tostring().
    local n = select("#", ...)
    for i=1, n do
        local arg = select(i, ...)
        if type(arg) ~= "string" then
            error(string.format("path.join(): %d-th argument is a non-string: %s", i, arg), 2)
        end
    end
    return table.concat({...}, ns.sep)
end

--
-- path.resolve(p, opts) attempts to resolve a Fusion path mapping:
--
--   path.resolve("Config:/Foo.fu")
--
-- By default it raises an error when it fails to resolve the path. You can
-- change the behaviour by doing:
--
--   path.resolve(p, {error = false})
--
-- In this case the function returns the given path unchanged, instead of
-- raising an error.
--
function generic.resolve(_ns, p, opts)
    assert(type(p) == "string", "path.resolve() expects a string path as its 1st argument")

    opts = opts or {}
    assert(type(opts) == "table", "path.resolve() expects an optional table as its 2nd argument")

    opts.error = opts.error or true
    assert(type(opts.error) == "boolean", "path.resolve(): option \"error\" must be a boolean")

    if app == nil then
        error("The global \"app\" is not defined. This function can only be called inside of Fusion", 2)
    end

    local ret = app:MapPath(p)
    if ret == p and opts.error then
        error("Failed to resolve a path mapping: " .. p, 2)
    else
        return ret
    end
end

--
-- path.isAbsolute(p) returns true iff the given string is an absolute path
-- on the current platform.
--
function platforms.posix.isAbsolute(_ns, p)
    assert(type(p) == "string", "path.isAbsolute() expects a string path")

    return string.find(p, "^/") ~= nil
end
function platforms.windows.isAbsolute(_ns, p)
    assert(type(p) == "string", "path.isAbsolute() expects a string path")

    -- Did you know Windows accepted '/' as a directory separator as well?
    return string.find(p, "^[\\/]")     ~= nil or
           string.find(p, "^[A-Za-z]:") ~= nil
end

-- Construct and return the magic object "path".
do
    local platNSs = {}
    for name, ns in pairs(platforms) do
        platNSs[name] = setmetatable(
            {},
            {
                __index = function(self, key)
                    -- Generic members should also be accessible through
                    -- platform-specific namespaces "path.{platform}". In
                    -- this case references to "ns" in those functions
                    -- should refer to this platform.
                    local val = rawget(generic, key)
                    if val ~= nil then
                        if type(val) == "function" then
                            local function wrapper(...)
                                return val(self, ...)
                            end
                            rawset(self, key, wrapper)
                            return wrapper
                        else
                            rawset(self, key, val)
                            return val
                        end
                    end

                    -- The key was not found in the generic namespace. It
                    -- must be in this platform-specific one. In this case
                    -- references to "ns" should refer to this platform.
                    local val = rawget(ns, key)
                    if val ~= nil then
                        if type(val) == "function" then
                            local function wrapper(...)
                                return val(ns, ...)
                            end
                            rawset(self, key, wrapper)
                            return wrapper
                        else
                            rawset(self, key, val)
                            return val
                        end
                    end
                end,
                __newindex = function(_self, _key, _val)
                    error("Cannot modify a read-only table", 2)
                end
            })
    end

    local currentNS = platNSs[platform]
    assert(currentNS ~= nil)

    return setmetatable(
        {},
        {
            __index = function(self, key)
                -- "path.{platform}" is a platform-specific namespace.
                local platNS = rawget(platNSs, key)
                if platNS ~= nil then
                    -- The key is the name of a platform-specific
                    -- namespace such as "posix".
                    rawset(self, key, platNS)
                    return platNS
                end

                -- References to "ns" in generic functions should refer to
                -- "path.{platform}" where {platform} is the current
                -- platform.
                local val = rawget(generic, key)
                if val ~= nil then
                    if type(val) == "function" then
                        local function wrapper(...)
                            return val(currentNS, ...)
                        end
                        rawset(self, key, wrapper)
                        return wrapper
                    else
                        rawset(self, key, val)
                        return val
                    end
                end

                -- The key was not found in the generic namespace. It must
                -- be in the current platform-specific one.
                return currentNS[key]
            end
        })
end
