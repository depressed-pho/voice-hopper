local SemVer   = require("semver")
local class    = require("class")
local console  = require("console")
local fs       = require("fs")
local path     = require("path")
local readonly = require("readonly")
local types    = require("config/types")

local REGISTRY = {} -- {[path] = Config}

--
-- Private class "Config"
--
local Config = class("Config")

function Config:__init(args)
    self._path     = args.path
    self._absPath  = path.resolve("Config:/" .. args.path .. ".fu")
    self._absDir   = path.dirname(self._absPath)
    self._version  = (type(args.version) == "string" and SemVer:new(args.version)) or args.version
    self._root     = types.table(args.fields):create(self._path) -- FixedTableField
    self._upgrader = self:_compileUpgraders(args.upgraders or {})

    -- The root element of the configuration tree must always be a table,
    -- because we need to inject our own metadata (such as a version) into
    -- it.

    self:_load()
end

function Config.__getter:fields()
    return self._root:cook()
end

function Config:_compileUpgraders(upgraders)
    --
    -- The upgraders table is unsorted. First we need to sort them first.
    --
    local seq = {} -- {{ver, func}, ...}
    for key, func in pairs(upgraders) do
        -- The version has to be parsable.
        local ver = SemVer:new(key)
        -- And the function must really be a function, though we cannot
        -- evaluate it yet.
        if type(func) ~= "function" then
            error(string.format("Invalid upgrader function for version %s: %s", ver, func), 2)
        end
        table.insert(seq, {ver, func})
    end
    table.sort(seq, function(e1, e2)
        return e1[1] < e2[1]
    end)
    --
    -- Now create a function that runs the upgraders.
    --
    return function(fileVer, root)
        for _i, e in ipairs(seq) do
            local ver, func = e[1], e[2]

            if ver < fileVer then
                -- e.g. upgrader 1.2.0 for file 1.2.1. Unnecessary for this
                -- file. Skip it.
            elseif ver == fileVer or ver.major == fileVer.major then
                -- e.g. upgrader 1.2.1 for file 1.2.1, or upgrader 1.2.2
                -- for file 1.2.1. Use this. Upgraders are called with
                -- (fileVer, root) and are expected to return new SemVer
                -- (or a string) and a root table. They are allowed to
                -- mutate the given table.
                print(
                    string.format(
                        "INFO: Upgrading config %s version %s using upgrader for %s",
                        self._path, fileVer, ver))

                local newVer, newRoot = func(fileVer, root)
                if not SemVer:made(newVer) then
                    newVer = SemVer:new(newVer)
                end
                assert(type(newRoot) == "table",
                       "Upgraders are expected to return a version and a new root table", 2)

                if newVer <= fileVer then
                    error("The upgrader didn't actually upgrade the config." ..
                          " It returned version " .. tostring(newVer), 2)
                elseif newVer > self._version then
                    error("The upgrader did too much. It returned a version" ..
                          " even newer than the current schema: " .. tostring(newVer), 2)
                else
                    -- Ok, continue upgrading it.
                    fileVer, root = newVer, newRoot
                end
            else
                -- e.g. upgrader 2.0.0 for file 1.2.1. Clearly
                -- incompatible.
                break
            end
        end
        return fileVer, root
    end
end

function Config:_load()
    -- luacheck: read_globals bmd
    if bmd == nil then
        error("The global \"bmd\" is not defined. This function can only be called inside of Fusion", 2)
    end

    -- Try loading the file. Can we load it?
    local raw = bmd.readfile(self._absPath)
    if raw == nil then
        -- This is okay. We just fill fields with their default values.
        return
    end

    -- Okay, loaded the file. But what about its version? Is it compatible
    -- with our schema?
    local ok, fileVer = pcall(function()
        return SemVer:new(raw.version)
    end)
    if not ok then
        -- Fine. We couldn't even parse its version.
        console:warn("Failed to parse version of config %s: %s", self._path, fileVer)
        return
    end

    -- Delete the version now, or Field#setRaw() will complain.
    raw.version = nil

    if fileVer == self._version then
        -- The version is exactly the same as what we expect. Great.
        self._root:setRaw(raw)

    elseif fileVer > self._version then
        -- The file is from the future! Maybe we can still read it?
        console:warn(
            "Config file for %s is from the future: expected %s but got %s",
            self._path, self._version, fileVer)
        if fileVer.major == self._version.major then
            -- Seems like so.
            console:warn("Still trying to interpret it because major versions match")
            self._root:setRaw(raw)
        end
    else
        -- It's old. Maybe we can upgrade it?
        local newVer, newRaw = self._upgrader(fileVer, raw)
        if newVer == self._version then
            -- Now it's the exact same version. The upgrader worked
            -- perfectly. Load it and then save.
            self._root:setRaw(raw)
            self:save()
        else
            -- It's still old.
            assert(newVer < self._version)
            if newVer.major == self._version.major then
                -- This means the upgrader is probably fine with this
                -- version, or is it?
                console:warn(
                    "No upgraders for config %s upgraded config version %s to version %s",
                    self._path, newVer, self._version)
                self._root:setRaw(newRaw)
            else
                console:warn(
                    "No compatible upgraders for config %s are found for config version %s",
                    self._path, newVer)
                -- Can't load it in this case.
            end
        end
    end
end

function Config:save()
    -- luacheck: read_globals bmd
    if bmd == nil then
        error("The global \"bmd\" is not defined. This function can only be called inside of Fusion", 2)
    end

    -- bmd.writefile() will always fail if the parent directory does not
    -- exist.
    local ok = pcall(fs.mkdir, self._absDir, {recursive = true})
    if not ok then
        -- Not sure if this should raise an error. Probably not?
        console:warn("Failed to create a directory for a config file:", self._absPath)
    end

    local raw = self._root:getRaw()
    raw.version = tostring(self._version)

    local ok = bmd.writefile(self._absPath, raw)
    if not ok then
        -- Not sure if this should raise an error. Probably not?
        console:warn("Failed to write a config file:", self._absPath)
    end
end

--
-- Configuration manager
--
local cfg = {}

for name, fldType in pairs(types) do
    cfg[name] = fldType -- FieldFactory or function
end

function cfg.schema(args)
    assert(type(args) == "table", "cfg.schema() expects a table")
    assert(
        type(args.path) == "string" and not path.isAbsolute(args.path),
        "\"path\" must to be a relative file path")
    assert(
        type(args.version) == "string" or SemVer:made(args.version),
        "\"version\" must either be a string or a SemVer")
    assert(
        type(args.fields) == "table" and getmetatable(args.fields) == nil,
        "\"fields\" must be a table")
    assert(
        args.fields.version == nil,
        "A configuration schema must not have a field named \"version\" as it's reserved")
    assert(
        args.upgraders == nil or type(args.upgraders) == "table",
        "\"upgraders\" must be a table")

    if REGISTRY[args.path] == nil then
        local conf = Config:new(args)
        REGISTRY[args.path] = conf
        return conf
    else
        error(string.format("Schema for \"%s\" has already been defined", args.path), 2)
    end
end

-- Mistyping a type name with no default values will result in a cryptic
-- error because keys with nil values will vanish. We should therefore
-- disallow accessing non-existent keys in cfg.
return readonly(cfg, {errOnMissingKeys = true})
