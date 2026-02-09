local Array   = require("collection/array")
local Map     = require("collection/map")
local RegExp  = require("re")
local Set     = require("collection/set")
local class   = require("class")
local console = require("console")

--
-- KeyPath
--
local KeyPath = class("KeyPath")
function KeyPath:__init()
    self._path = Array:new()
end
KeyPath:cloneable(function(self)
    self._path = self._path:clone()
end)
function KeyPath:__tostring()
    return "/" .. self._path:join("/")
end
function KeyPath:snoc(key)
    assert(key ~= nil, "KeyPath#snoc() expects a non-nil key")

    local ret = self:clone()
    ret._path:push(key)
    return ret
end

--
-- Field
--
local Field = class("Field")
function Field:__init(cfgPath, keyPath)
    self._cfgPath = cfgPath
    self._keyPath = keyPath
end
function Field.__getter:cfgPath()
    return self._cfgPath
end
function Field.__getter:keyPath()
    return self._keyPath
end
function Field:validationError(reason)
    error(string.format("Invalid value at %s for config %s: %s",
                        self._keyPath, self._cfgPath, reason), 0)
end
Field:abstract("cook")
Field:abstract("getRaw")
Field:abstract("setRaw")

--
-- ScalarField
--
local ScalarField = class("ScalarField", Field)
function ScalarField:__init(cfgPath, keyPath, default)
    super(cfgPath, keyPath)
    self._default = default
    self._value   = nil

    if self._default ~= nil then
        self:validate(self._default)
    end
end
function ScalarField:cook()
    if self._value == nil then
        return self._default
    else
        return self._value
    end
end
function ScalarField:getRaw()
    return self._value
end
function ScalarField:setRaw(value, permissive)
    if value ~= nil then
        local ok, msg = pcall(self.validate, self, value)
        if not ok then
            if permissive then
                -- Validation failed but this is fine. We should just
                -- revert it to the default value.
                console:warn(msg)
            else
                error(msg, 0)
            end
        end
    end
    self._value = value
end
Field:abstract("validate")

--
-- FieldFactory
--
local FieldFactory = class("FieldFactory")
function FieldFactory:__init(fieldClass, defaultable, ...)
    self._class       = fieldClass
    self._default     = nil
    self._defaultable = defaultable -- boolean
    self._args        = Array:of(...)
end
FieldFactory:cloneable()
function FieldFactory:__call(default)
    local ret = self:clone()
    if ret._default == nil then
        if ret._defaultable then
            ret._default = default
        else
            error("This field cannot have a default value", 2)
        end
    else
        error("Field with a default value is not callable", 2)
    end
    return ret
end
function FieldFactory:create(cfgPath, keyPath)
    keyPath = keyPath or KeyPath:new()

    if self._defaultable then
        return self._class:new(cfgPath, keyPath, self._default, self._args:unpack())
    else
        return self._class:new(cfgPath, keyPath, self._args:unpack())
    end
end

--
-- Types
--
local types = {}

--
-- cfg.boolean
--
local BooleanField = class("BooleanField", ScalarField)
function BooleanField:validate(value)
    if type(value) ~= "boolean" then
        self:validationError("Expected a boolean but got " .. tostring(value))
    end
end
types.boolean = FieldFactory:new(BooleanField, true)

--
-- cfg.nonNegInteger
--
local NonNegIntegerField = class("NonNegIntegerField", ScalarField)
function NonNegIntegerField:validate(value)
    if type(value) ~= "number" or value ~= math.floor(value) or value < 0 then
        self:validationError("Expected a non-negative integer but got " .. tostring(value))
    end
end
types.nonNegInteger = FieldFactory:new(NonNegIntegerField, true)

--
-- cfg.number
--
local NumberField = class("NumberField", ScalarField)
function NumberField:validate(value)
    if type(value) ~= "number" then
        self:validationError("Expected a number but got " .. tostring(value))
    end
end
types.number = FieldFactory:new(NumberField, true)

--
-- cfg.string
--
local StringField = class("StringField", ScalarField)
function StringField:validate(value)
    if type(value) ~= "string" then
        self:validationError("Expected a string but got " .. tostring(value))
    end
end
types.string = FieldFactory:new(StringField, true)

--
-- cfg.regexp
--
local RegExpField = class("RegExpField", ScalarField)
function RegExpField:validate(value)
    local ok, err = pcall(RegExp.new, RegExp, value)
    if not ok then
        self:validationError(
            string.format(
                "Expected a valid regular expression but got %s: %s", value, err))
    end
end
types.regexp = FieldFactory:new(RegExpField, true)

--
-- cfg.enum(values[, default])
--
local EnumField = class("EnumField", ScalarField)
function EnumField:__init(cfgPath, keyPath, default, values)
    assert(type(values) == "table", "cfg.enum() expects a sequence of candidates")
    super(cfgPath, keyPath, default)
    self._values = Set:new(values)
end
function EnumField:validate(value)
    if not self._values:has(value) then
        self:validationError("Unexpected value: " .. tostring(value))
    end
end
types.enum = function(values, default)
    return FieldFactory:new(EnumField, true, values)(default)
end

--
-- cfg.table({[key] = value})
--
local FixedTableField = class("FixedTableField", Field)
function FixedTableField:__init(cfgPath, keyPath, schema)
    assert(type(schema) == "table" and getmetatable(schema) == nil,
           "cfg.table(tab) expects a table")
    super(cfgPath, keyPath)

    self._fields = {} -- {[key] = Field}
    for k, v in pairs(schema) do
        if FieldFactory:made(v) then
            self._fields[k] = v:create(cfgPath, keyPath:snoc(k))
        else
            assert(type(v) == "table" and getmetatable(v) == nil,
                   string.format(
                       "Invalid schema at %s: field \"%s\" is neither a table nor a field type: %s",
                       keyPath, k, v))
            self._fields[k] = FixedTableField:new(cfgPath, keyPath:snoc(k), v)
        end
    end

    self._cooked = setmetatable(
        {},
        {
            __index = function(_self, key)
                local field = self._fields[key]
                if field == nil then
                    self:nonexistentFieldError(key)
                else
                    return field:cook()
                end
            end,
            __newindex = function(_self, key, value)
                local field = self._fields[key]
                if field == nil then
                    self:nonexistentFieldError(key)
                else
                    field:setRaw(value)
                end
            end
        })
end
function FixedTableField:cook()
    return self._cooked
end
function FixedTableField:getRaw()
    local raw = Map:new()
    for key, field in pairs(self._fields) do
        local value = field:getRaw()
        if value ~= nil then
            raw:set(key, value)
        end
    end
    return (raw.size > 0 and raw:toTable()) or nil
end
function FixedTableField:setRaw(raw, permissive)
    if type(raw) == "table" and getmetatable(raw) == nil then
        for key, value in pairs(raw) do
            local field = self._fields[key]
            if field == nil then
                if permissive then
                    -- No such field? This is fine. Just ignore it.
                else
                    self:nonexistentFieldError(key)
                end
            else
                local ok, msg = pcall(function()
                    field:setRaw(value)
                end)
                if not ok then
                    if permissive then
                        -- Validation failed but this is fine. We should
                        -- just revert it to the default value.
                        console:warn(msg)
                        field:setRaw(nil)
                    else
                        error(msg, 0)
                    end
                end
            end
        end
    else
        self:validationError("Expected a table but got " .. tostring(raw))
    end
end
function FixedTableField:nonexistentFieldError(key)
    error(string.format("Nonexistent key %s for config %s",
                        self.keyPath:snoc(key), self.cfgPath), 0)
end

--
-- cfg.table(keys, values[, default])
--
local FreeTableField = class("FreeTableField", Field)
function FreeTableField:__init(cfgPath, keyPath, default, keys, values)
    assert(FieldFactory:made(keys), "cfg.table(keys, values): keys is expected to be a FieldFactory")
    assert(FieldFactory:made(values) or (type(values) == "table" and getmetatable(values) == nil),
           "cfg.table(keys, values): values is expected to either be a FieldFactory or a table")
    super(cfgPath, keyPath)

    self._keys    = keys
    self._values  = values
    self._default = default -- raw table or nil
    self._fields  = {}      -- {[key] = Field}

    if not FieldFactory:made(self._values) then
        self._values = FixedTableField:new(cfgPath, keyPath, self._values)
    end

    if self._default then
        for key, value in pairs(self._default) do
            -- Instantiate a ScalarField just to validate the key.
            local keyFld = self._keys:create(cfgPath, keyPath:snoc("{key}"))
            assert(ScalarField:made(keyFld),
                   "cfg.table(keys, values): keys must be of a scalar type")
            keyFld:setRaw(key)

            -- Instantiate a Field just to validate the value.
            local valFld = self._values:create(cfgPath, keyPath:snoc(key))
            valFld:setRaw(value)
        end
    end
end
function FreeTableField:cook()
    return self._fields
end
function FreeTableField:getRaw()
    local raw = Map:new()
    for key, field in pairs(self._fields) do
        local value = field:getRaw()
        if value ~= nil then
            raw:set(key, value)
        end
    end
    return (raw.size > 0 and raw:toTable()) or nil
end
function FreeTableField:setRaw(raw, permissive)
    if raw == nil then
        self._fields = {}
    elseif type(raw) == "table" and getmetatable(raw) == nil then
        self._fields = {}
        for key, value in pairs(raw) do
            -- Instantiate a ScalarField just to validate the key.
            local keyFld = self._keys:create(self.cfgPath, self.keyPath:snoc("{key}"))
            assert(ScalarField:made(keyFld),
                   "cfg.table(keys, values): keys must be of a scalar type")
            local ok, msg = pcall(keyFld.setRaw, keyFld, key)
            if not ok then
                if permissive then
                    -- Invalid key? This is fine. Just ignore it.
                    console:warn(msg)
                else
                    error(msg, 0)
                end
            else
                -- Instantiate a Field to hold the value.
                local valFld = self._values:create(self.cfgPath, self.keyPath:snoc(key))
                local ok1, msg1 = pcall(valFld.setRaw, valFld, value)
                if not ok1 then
                    if permissive then
                        -- Invalid value? This is fine. Just revert it to
                        -- the default value.
                        valFld:setRaw(nil)
                    else
                        error(msg1, 0)
                    end
                end
                -- Register the key/field pair to the table.
                self._fields[keyFld:getRaw()] = valFld
            end
        end
    else
        self:validationError("Expected a table but got " .. tostring(raw))
    end
end

types.table = function(...)
    if select("#", ...) == 1 then
        return FieldFactory:new(FixedTableField, false, ...)
    else
        local args    = Array:of(...)
        local default = args:pop()
        return FieldFactory:new(FreeTableField, true, args:unpack())(default)
    end
end

return types
