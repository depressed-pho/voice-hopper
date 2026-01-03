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

local CODE_PERIOD    = string.byte(".")
local CODE_SLASH     = string.byte("/")
local CODE_BACKSLASH = string.byte("\\")

--
-- path.sep is a platform-specific path segment separator
--
platforms.posix.sep   = "/"
platforms.windows.sep = "\\"

--
-- path.basename(p, suffix) extracts the file part of the path, optionally
-- stripping the suffix off.
--
function platforms.posix.basename(_ns, p, suffix)
    assert(type(p) == "string", "path.basename() expects a string path as its 1st argument")
    assert(suffix == nil or type(suffix) == "string", "path.basename() expects an optional string suffix as its 2nd argument")

    local baseStart  = 1
    local baseEnd    = nil
    for i = #p, 1, -1 do
        if string.byte(p, i) == CODE_SLASH then
            if baseEnd ~= nil then
                -- We've found at least one non-separator character, and
                -- now we found a separator. This is where we should split
                -- the path.
                baseStart = i + 1
                break
            end
        elseif baseEnd == nil then
            baseEnd = i
        end
    end

    if baseEnd == nil then
        -- "p" contains no non-separator characters.
        return ""
    end

    local base = string.sub(p, baseStart, baseEnd)
    if suffix ~= nil and #base >= #suffix then
        if base == suffix then
            -- Special case: don't strip the suffix if it's identical to
            -- the remaining path string.
            return base
        elseif string.sub(base, #base - #suffix + 1) == suffix then
            -- Suffix matches. Strip it off.
            return string.sub(base, 1, #base - #suffix)
        end
    end
    return base
end
function platforms.windows.basename(_ns, p, suffix)
    assert(type(p) == "string", "path.basename() expects a string path as its 1st argument")
    assert(suffix == nil or type(suffix) == "string", "path.basename() expects an optional string suffix as its 2nd argument")

    local baseStart = 1

    -- Check for a driver letter prefix so as not to mistake the following
    -- path separator as an extra separator at the end of the path that can
    -- be disregarded. In other words, driver letters must always be
    -- discarded.
    if string.find(p, "^[A-Za-z]:") ~= nil then
        baseStart = 3
    end

    local baseEnd = nil
    for i = #p, baseStart, -1 do
        local code = string.byte(p, i)
        if code == CODE_SLASH or code == CODE_BACKSLASH then
            if baseEnd ~= nil then
                -- We've found at least one non-separator character, and
                -- now we found a separator. This is where we should split
                -- the path.
                baseStart = i + 1
                break
            end
        elseif baseEnd == nil then
            baseEnd = i
        end
    end

    if baseEnd == nil then
        -- "p" contains no non-separator characters.
        return ""
    end

    local base = string.sub(p, baseStart, baseEnd)
    if suffix ~= nil and #base >= #suffix then
        if base == suffix then
            -- Special case: don't strip the suffix if it's identical to
            -- the remaining path string.
            return base
        elseif string.sub(base, #base - #suffix + 1) == suffix then
            -- Suffix matches. Strip it off.
            return string.sub(base, 1, #base - #suffix)
        end
    end
    return base
end

--
-- path.dirname(p) extracts the directory part of the path.
--
function platforms.posix.dirname(ns, p)
    assert(type(p) == "string", "path.dirname() expects a string path")

    local foundNonSep = false
    for i = #p, 2, -1 do
        if string.byte(p, i) == CODE_SLASH then
            if foundNonSep then
                -- We've found at least one non-separator character, and
                -- now we found a separator. We also know this separator
                -- isn't at the beginning of the path. This is where we
                -- should split it.
                return string.sub(p, 1, i-1)
            end
        else
            foundNonSep = true
        end
    end
    return (ns.isAbsolute(p) and "/") or "."
end
function platforms.windows.dirname(ns, p)
    assert(type(p) == "string", "path.dirname() expects a string path")

    -- Windows is abysmal. Just look at this code. This is how you
    -- implement dirname(), a supposedly simple path manipulation.
    local rootEnd = nil

    local code = string.byte(p, 1)
    if code == CODE_SLASH or code == CODE_BACKSLASH then
        -- The first character is a separator. Maybe it's UNC?
        local _from, to = string.find(p, "^[/\\][/\\]+[^/\\]+[/\\]+")
        if to == nil then
            rootEnd = 1 -- Only the separator at the beginning is root.
        else
            -- So far we matched "\\host\". Do we have any leftovers?
            local _from, to = string.find(p, "^[^/\\]+[/\\]", to + 1)
            if to == nil then
                -- No. The path contains a UNC root only.
                return p
            else
                -- Matched "\\host\root\". Treat this entirely as the root
                -- path. LOL
                rootEnd = to
            end
        end
    else
        -- Maybe it's a device root?
        local _from, to = string.find(p, "^[A-Za-z]:[/\\]?")
        if to ~= nil then
            -- Yes it is.
            rootEnd = to
        end
    end

    local offset      = rootEnd or 1
    local foundNonSep = false
    for i = #p, offset + 1, -1 do
        local code = string.byte(p, i)
        if code == CODE_SLASH or code == CODE_BACKSLASH then
            if foundNonSep then
                -- We've found at least one non-separator character, and
                -- now we found a separator. We also know this separator
                -- isn't at the beginning of the path. This is where we
                -- should split it.
                return string.sub(p, 1, i-1)
            end
        else
            foundNonSep = true
        end
    end

    if rootEnd == nil then
        return "."
    else
        return string.sub(p, 1, rootEnd)
    end
end

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
-- path.parse(p) splits the given path into its components. For example, on
-- POSIX:
--
--   path.parse("/home/user/dir/file.tar.gz")
--   => {
--        root = "/",
--        dir  = "/home/user/dir",
--        base = "file.tar.gz",
--        name = "file.tar",
--        ext  = ".gz"
--      }
--
-- On Windows:
--
--   path.parse("C:\\path\\dir\\file.txt")
--   => {
--        root = "C:\\",
--        dir  = "C:\\path\\dir",
--        base = "file.txt",
--        name = "file",
--        ext  = ".txt"
--      }
--
-- * "root" is an empty string if the path is relative.
-- * "dir" is an empty string if the path has no directory separators
--   (ignoring ones at the end of the path).
-- * "ext" is an empty string if the path has no extensions. It is the last
--   extension of the file.
--
function platforms.posix.parse(ns, p)
    assert(type(p) == "string", "path.extension() expects a string path")
    local ret = {
        root = "",
        dir  = "",
        base = "",
        name = "",
        ext  = ""
    }
    if #p == 0 then
        return ret
    end

    local offset
    if ns.isAbsolute(p) then
        ret.root = "/"
        offset = 2
    else
        offset = 1
    end

    local baseStart = offset
    local baseEnd   = nil
    local dirEnd    = nil
    local extStart  = nil
    for i = #p, offset, -1 do
        local code = string.byte(p, i)
        if code == CODE_SLASH then
            if baseEnd ~= nil then
                -- We've found at least one non-separator character, and
                -- now we found a separator. We also know this separator
                -- isn't at the beginning of the path. This is where the
                -- basename begins.
                baseStart = i + 1
                dirEnd    = i - 1
                break
            end
        else
            if baseEnd == nil then
                -- This is the last non-separator in the path. It's the end
                -- of the basename.
                baseEnd = i
            end
            if extStart == nil and code == CODE_PERIOD then
                -- This is the last period in the path.
                extStart = i
            end
        end
    end

    if baseEnd ~= nil then
        -- "p" contains at least one non-separator character, which means
        -- its basename isn't empty.
        local base = string.sub(p, baseStart, baseEnd)
        ret.base = base
        ret.name = base -- But we might overwrite this later.

        -- Basenames "." and ".." are special. They aren't extensions.
        if base ~= "." and base ~= ".." then
            if extStart ~= nil then
                if baseStart == extStart then
                    -- This means the only period in the basename is at the
                    -- beginning of it. It's a POSIX hidden file such as
                    -- ".foo" and we don't count it as an extension.
                else
                    -- There is something in the basename before the
                    -- period. There is definitely an extension.
                    ret.name = string.sub(p, baseStart, extStart-1)
                    ret.ext  = string.sub(p, extStart , baseEnd   )
                end
            end
        end
    end

    if dirEnd ~= nil then
        ret.dir = string.sub(p, 1, dirEnd)
    else
        ret.dir = ret.root
    end

    return ret
end
function platforms.windows.parse(_ns, p)
    assert(type(p) == "string", "path.extension() expects a string path")
    local ret = {
        root = "",
        dir  = "",
        base = "",
        name = "",
        ext  = ""
    }
    if #p == 0 then
        return ret
    end

    local rootEnd = nil

    local code = string.byte(p, 1)
    if code == CODE_SLASH or code == CODE_BACKSLASH then
        -- The first character is a separator. Maybe it's UNC?
        local _from, to = string.find(p, "^[/\\][/\\]+[^/\\]+[/\\]+")
        if to == nil then
            rootEnd = 1 -- Only the separator at the beginning is root.
        else
            rootEnd = to
            -- So far we matched "\\host\". Do we have any leftovers?
            local _from, to = string.find(p, "^[^/\\]+", to + 1)
            if to == nil then
                -- No. The path contains a UNC root only.
            else
                -- Matched "\\host\root". Treat this and the next separator
                -- as the root path. LOL
                rootEnd = to + 1
            end
        end
    else
        -- Maybe it's a device root?
        local _from, to = string.find(p, "^[A-Za-z]:[/\\]?")
        if to ~= nil then
            -- Yes it is.
            rootEnd = to
        end
    end

    local offset
    if rootEnd ~= nil then
        ret.root = string.sub(p, 1, rootEnd)
        offset = rootEnd + 1
    else
        offset = 1
    end

    local baseStart = offset
    local baseEnd   = nil
    local dirEnd    = nil
    local extStart  = nil
    for i = #p, offset, -1 do
        local code = string.byte(p, i)
        if code == CODE_SLASH or code == CODE_BACKSLASH then
            if baseEnd ~= nil then
                -- We've found at least one non-separator character, and
                -- now we found a separator. We also know this separator
                -- isn't at the beginning of the path. This is where the
                -- basename begins.
                baseStart = i + 1
                dirEnd    = i - 1
                break
            end
        else
            if baseEnd == nil then
                -- This is the last non-separator in the path. It's the end
                -- of the basename.
                baseEnd = i
            end
            if extStart == nil and code == CODE_PERIOD then
                -- This is the last period in the path.
                extStart = i
            end
        end
    end

    if baseEnd ~= nil then
        -- "p" contains at least one non-separator character after the
        -- root, which means its basename isn't empty.
        local base = string.sub(p, baseStart, baseEnd)
        ret.base = base
        ret.name = base -- But we might overwrite this later.

        -- Basenames "." and ".." are special. They aren't extensions.
        if base ~= "." and base ~= ".." then
            if extStart ~= nil then
                if baseStart == extStart then
                    -- This means the only period in the basename is at the
                    -- beginning of it. It's a POSIX hidden file such as
                    -- ".foo" and we don't count it as an extension.
                else
                    -- There is something in the basename before the
                    -- period. There is definitely an extension.
                    ret.name = string.sub(p, baseStart, extStart-1)
                    ret.ext  = string.sub(p, extStart , baseEnd   )
                end
            end
        end
    end

    -- If the directory is the root, use the entire root as the "dir"
    -- including the trailing slash if any (C:\abc -> C:\). Otherwise,
    -- strip out the trailing slash (C:\abc\def -> C:\abc).
    if dirEnd ~= nil then
        ret.dir = string.sub(p, 1, dirEnd)
    else
        ret.dir = ret.root
    end

    return ret
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

    return string.byte(p, 1) == CODE_SLASH
end
function platforms.windows.isAbsolute(_ns, p)
    assert(type(p) == "string", "path.isAbsolute() expects a string path")

    -- Did you know Windows accepted '/' as a directory separator as well?
    local code = string.byte(p)
    return code == CODE_SLASH     or
           code == CODE_BACKSLASH or
           string.find(p, "^[A-Za-z]:[/\\]") ~= nil
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
                                return val(self, ...)
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
