local Array    = require("collection/array")
local Map      = require("collection/map")
local Symbol   = require("Symbol")
local class    = require("class")
local readonly = require("readonly")

local TypeName = class("TypeName")
function TypeName:__init(name)
    assert(type(name) == "string", "alc.name() expects a name string")
    self.name = name
end

local Constructor = class("Constructor")
function Constructor:__init(name, ...)
    assert(type(name) == "string", "alc.ctor() expects a name string as its 1st argument")

    self.name   = name
    self.fields = Array:of() -- Array<string|Symbol>

    for i=1, select("#", ...) do
        local field = select(i, ...)
        assert(type(field) == "string" or Symbol:made(field),
               "alc.ctor() expects field names after its 1st argument")
        self.fields:push(field)
    end
end

--
-- Algebraic data types.
--
-- Usage:
--
--   local alc = require("algebraic")
--   local Foo = alc.data {
--       alc.name "Foo", -- optional
--       alc.ctor "A",
--       alc.ctor("B", "fld0"),
--       alc.ctor("C", "fld0", "fld1")
--   }
--
-- This translates to the following code:
--
--   local class = require("class")
--   local Foo   = class("Foo")
--   Foo.A = class("A", Foo)
--   Foo.B = class("B", Foo)
--   function Foo.B.__init(fld0)
--       super()
--       self.fld0 = fld0
--   end
--   Foo.C = class("C", Foo)
--   function Foo.C.__init(fld0, fld1)
--       super()
--       self.fld0 = fld0
--       self.fld1 = fld1
--   end
--
-- The generated class has a method :match() that works like this:
--
--   local foo = Foo.A:new()
--   local ret = foo:match {
--       A = function () 1 end,
--       B = function (fld0) 2 end,
--       C = function (fld0, fld1) 3 end
--   } -- ret contains 3
--
local alc = {}

function alc.data(tab)
    assert(type(tab) == "table" and getmetatable(tab) == nil,
           "alc.data() expects a sequence")

    local typeName = nil       -- string|nil
    local ctors    = Map:new() -- Map<string, Constructor>
    for _k, v in pairs(tab) do
        assert(type(v) == "table" and getmetatable(tab) == nil,
               "Something wrong was given to alc.data(): " .. tostring(v))

        if TypeName:made(v) then
            typeName = v.name
        elseif Constructor:made(v) then
            ctors:set(v.name, v)
        else
            error("Something wrong was given to alc.data(): " .. tostring(v))
        end
    end

    local dataClass = class(typeName)
    function dataClass:match(funcs)
        assert(type(funcs) == "table", getmetatable(funcs) == nil,
               class.nameOf(dataClass) .. "#match() expects a table of functions")

        local ctorName = class.nameOf(class.classOf(self))
        local func     = funcs[ctorName]

        assert(func, class.nameOf(dataClass) .. "#match(): No branches for constructor " .. ctorName)
        assert(type(func) == "function",
               class.nameOf(dataClass) .. "#match() expects a table of functions")

        local ctor = ctors:get(ctorName)
        assert(ctor, "Unknown constructor of data type " .. tostring(class.nameOf(self)))

        local args = ctor.fields:map(
            function (field)
                return rawget(self, field)
            end)
        return func(args:unpack())
    end

    for ctor in ctors:values() do
        local ctorClass = class(ctor.name, dataClass)
        dataClass[ctor.name] = ctorClass

        function ctorClass:__init(...)
            super()
            for i, field in ctor.fields:entries() do
                rawset(self, field, select(i, ...))
            end
        end

        function ctorClass:__index(k)
            -- Reaching here either means k is not a valid field name, or
            -- the value of field k is nil.
            if ctor.fields:includes(k) then
                return nil
            else
                error(class.nameOf(dataClass) .. "." .. ctor.name .. " does not have a field named " .. tostring(k), 2)
            end
        end

        function ctorClass:__newindex(k, v)
            -- Reaching here either means k is not a valid field name, or
            -- the value of field k is nil.
            if ctor.fields:includes(k) then
                rawset(self, k, v)
            else
                error(class.nameOf(dataClass) .. "." .. ctor.name .. " does not have a field named " .. tostring(k), 2)
            end
        end

        function ctorClass:__tostring()
            local ret = Array:of()

            if typeName then
                ret:push(typeName, ".")
            end
            ret:push(ctor.name)

            if ctor.fields.length > 0 then
                ret:push " {"
                local props = Array:new()
                for field in ctor.fields:values() do
                    local prop = Array:new()
                    if type(field) == "string" then
                        if string.find(field, "^[%a_][%w_]*$") then
                            -- This field name is an identifier.
                            prop:push(field)
                        else
                            prop:push(string.format("[%q]", field))
                        end
                    else
                        prop:push("[", tostring(field), "]")
                    end
                    prop:push(" = ", tostring(rawget(self, field)))
                    props:push(prop:join "")
                end
                ret:push(props:join(", "))
                ret:push "}"
            end

            return ret:join("")
        end
    end

    return dataClass
end

function alc.name(name)
    return TypeName:new(name)
end

function alc.ctor(name, ...)
    return Constructor:new(name, ...)
end

return readonly(alc, {errOnMissingKeys = true})
