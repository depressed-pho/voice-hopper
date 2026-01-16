require("shim/table")
local SemVer   = require("semver")
local class    = require("class")
local console  = require("console")
local fs       = require("fs")
local path     = require("path")
local readonly = require("readonly")

local REGISTRY = {} -- {[path] = Config}

--
-- Private class "FieldType"
--
local FieldType = class("FieldType")

function FieldType:__init(args)
    assert(type(args) == "table")
    assert(type(args.name) == "string")
    assert(type(args.validate) == "function")

    self.name     = args.name
    self.validate = args.validate
    self.default  = args.default
end

function FieldType:__call(default)
    if self.default == nil then
        -- cfg.integer is itself an instance of FieldType, but it is also
        -- callable. When called it takes a default value and returns a new
        -- FieldType. The same goes for any other types.

        local succeeded, err = pcall(self.validate, default)
        if succeeded then
            return FieldType:new {
                name     = self.name,
                validate = self.validate,
                default  = default
            }
        else
            error("Invalid default value: " .. err, 2)
        end
    else
        error("FieldType with a default value is not callable", 2)
    end
end

--
-- Private class "Config"
--
local Config = class("Config")

function Config:__init(args)
    self._path     = args.path
    self._absPath  = path.resolve("Config:/" .. args.path .. ".fu")
    self._absDir   = path.dirname(self._absPath)
    self._version  = (type(args.version) == "string" and SemVer:new(args.version)) or args.version
    self._schema   = args.fields
    self._upgrader = self:_compileUpgraders(args.upgraders or {})
    self._raw      = nil
    self._cooked   = nil

    self:_load()
end

function Config.__getter:fields()
    return self._cooked
end

function Config:_compileUpgraders(tab)
    --
    -- The table is unsorted. First we need to sort them first.
    --
    local seq = {} -- {{ver, func}, ...}
    for key, func in pairs(tab) do
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
    return function(fileVer, tab)
        for _i, e in ipairs(tab) do
            local ver, func = e[1], e[2]

            if ver < fileVer then
                -- e.g. upgrader 1.2.0 for file 1.2.1. Unnecessary for this
                -- file. Skip it.
            elseif ver == fileVer or ver.major == fileVer.major then
                -- e.g. upgrader 1.2.1 for file 1.2.1, or upgrader 1.2.2
                -- for file 1.2.1. Use this. Upgraders are called with
                -- (fileVer, tab) and are expected to return new SemVer (or
                -- a string) and tab. They are allowed to mutate the given
                -- table.
                print(
                    string.format(
                        "INFO: Upgrading config %s version %s using upgrader for %s",
                        self._path, fileVer, ver))

                local newVer, newTab = func(fileVer, tab)
                if not SemVer:made(newVer) then
                    newVer = SemVer:new(newVer)
                end
                assert(type(newTab) == "table", "Upgraders are expected to return a version and a new table", 2)

                if newVer <= fileVer then
                    error("The upgrader didn't actually upgrade the config." ..
                          " It returned version " .. tostring(newVer), 2)
                elseif newVer > self._version then
                    error("The upgrader did too much. It returned a version" ..
                          " even newer than the current schema: " .. tostring(newVer), 2)
                else
                    -- Ok, continue upgrading it.
                    fileVer, tab = newVer, newTab
                end
            else
                -- e.g. upgrader 2.0.0 for file 1.2.1. Clearly
                -- incompatible.
                break
            end
        end
        return fileVer, tab
    end
end

local function pushPath(keyPath, key)
    local ret = {}
    for i, v in ipairs(keyPath) do
        ret[i] = v
    end
    table.insert(ret, key)
    return ret
end
local function fmtPath(keyPath)
    return "/" .. table.concat(keyPath, "/")
end

function Config:_cookTree(schema, keyPath)
    schema  = schema  or self._schema
    keyPath = keyPath or {}

    local raw, cooked = {}, {}
    for fldName, fldType in pairs(schema) do
        if type(fldName) ~= "string" then
            error(
                string.format(
                    "Invalid schema at %s: field names are expected to be a string but got %s",
                    fmtPath(keyPath), fldName), 2)
        end

        if FieldType:made(fldType) then
            -- Default values should not initially exist in raw. Skip this.
        elseif type(fldType) == "table" and getmetatable(fldType) == nil then
            -- This is a subtree.
            raw[fldName], cooked[fldName] = self:_cookTree(fldType, pushPath(keyPath, fldName))
        else
            error(
                string.format(
                    "Invalid schema at %s: field \"%s\" is neither a table nor a field type: %s",
                    fmtPath(keyPath), fldName, fldType), 2)
        end
    end

    -- conf.fields is a table whose unknown keys are not accessible. Writes
    -- are always validated, which means it must not have its own
    -- properties.
    local meta = {}

    function meta.__index(_self, key)
        local fldType = rawget(schema, key)
        if fldType == nil then
            error(
                string.format(
                    "No such key exists in config %s: %s",
                    self._path, fmtPath(pushPath(keyPath, key))), 2)
        elseif FieldType:made(fldType) then
            -- The value itself can be nil.
            local val = rawget(raw, key)
            if val ~= nil then
                return val
            else
                return fldType.default
            end
        else
            local subtree = rawget(cooked, key)
            assert(type(fldType) == "table" and getmetatable(fldType) == nil)
            assert(type(subtree) == "table")
            return subtree
        end
    end

    function meta.__newindex(_self, key, val)
        local fldType = rawget(schema, key)
        if fldType == nil then
            error(
                string.format(
                    "No such key exists in config %s: %s",
                    self._path, fmtPath(pushPath(keyPath, key))), 2)
        elseif FieldType:made(fldType) then
            -- If the value is nil, revert it back to the
            -- default. Otherwise validate it.
            if val == nil then
                rawset(raw, key, nil)
            else
                local succeeded = pcall(fldType.validate, val)
                if not succeeded then
                    error(
                        string.format(
                            "Invalid value for %s in config %s: %s",
                            fmtPath(pushPath(keyPath, key)), self._path, val), 2)
                end
                rawset(raw, key, val)
            end
        else
            assert(type(fldType) == "table" and getmetatable(fldType) == nil)
            error(
                string.format(
                    "%s is a subtree in config %s and cannot be replaced",
                    fmtPath(pushPath(keyPath, key)), self._path), 2)
        end
    end

    return raw, setmetatable({}, meta)
end

function Config:_fillWithRawTree(raw, cooked)
    cooked = cooked or self._cooked

    for fldName, fldVal in pairs(raw) do
        if type(fldVal) == "table" then
            local ok, err = pcall(function()
                self:_fillWithRawTree(fldVal, cooked[fldName])
            end)
            if not ok then
                -- No such subtree? This is fine.
                console:warn(err)
            end
        else
            local ok, err = pcall(function()
                cooked[fldName] = fldVal
            end)
            if not ok then
                -- Validation failed. This is fine. It should just revert
                -- to the default value.
                console:warn(err)
            end
        end
    end
end

function Config:_load()
    -- luacheck: read_globals bmd
    if bmd == nil then
        error("The global \"bmd\" is not defined. This function can only be called inside of Fusion", 2)
    end

    self._raw, self._cooked = self:_cookTree()

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

    -- Delete the version now, or self:_fillWithRawTree() will complain.
    raw.version = nil

    if fileVer == self._version then
        -- The version is exactly the same as what we expect. Great.
        self:_fillWithRawTree(raw)

    elseif fileVer > self._version then
        -- The file is from the future! Maybe we can still read it?
        console:warn(
            "Config file for %s is from the future: expected %s but got %s",
            self._path, self._version, fileVer)
        if fileVer.major == self._version.major then
            -- Seems like so.
            console:warn("Still trying to interpret it because major versions match")
            self:_fillWithRawTree(raw)
        end
    else
        -- It's old. Maybe we can upgrade it?
        local newVer, newRaw = self._upgrader(fileVer, raw)
        if newVer == self._version then
            -- Now it's the exact same version. The upgrader worked
            -- perfectly. Load it and then save.
            self:_fillWithRawTree(newRaw)
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
                self:_fillWithRawTree(newRaw)
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

    -- Create a shallow clone of the raw tree so that we can inject a
    -- version without affecting it.
    local raw = {}
    for key, val in pairs(self._raw) do
        raw[key] = val
    end
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

cfg.boolean = FieldType:new {
    name     = "boolean",
    validate = function(val)
        if type(val) ~= "boolean" then
            error("Expected a boolean but got " .. tostring(val), 0)
        end
    end
}
cfg.nonNegInteger = FieldType:new {
    name     = "nonNegInteger",
    validate = function(val)
        if type(val) ~= "number" or val ~= math.floor(val) or val < 0 then
            error("Expected a non-negative integer but got " .. tostring(val), 0)
        end
    end
}
cfg.number = FieldType:new {
    name     = "number",
    validate = function(val)
        if type(val) ~= "number" then
            error("Expected a number but got " .. tostring(val), 0)
        end
    end
}
cfg.string = FieldType:new {
    name     = "string",
    validate = function(val)
        if type(val) ~= "string" then
            error("Expected a string but got " .. tostring(val), 0)
        end
    end
}

function cfg.schema(args)
    assert(type(args) == "table", "cfg.schema() expects a table")
    assert(
        type(args.path) == "string" and not path.isAbsolute(args.path),
        "\"path\" must to be a relative file path")
    assert(
        type(args.version) == "string" or SemVer:made(args.version),
        "\"version\" must either be a string or a SemVer")
    assert(
        type(args.fields) == "table",
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
