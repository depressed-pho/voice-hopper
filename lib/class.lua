require("shim/fenv")
local Symbol = require("symbol")

-- Suppress some of runtime sanity checks in exchange for safety.
local NDEBUG = os.getenv("NDEBUG") ~= nil

local symClass   = Symbol("class")
local symBase    = Symbol("base")
local symIsClass = Symbol("isClass")
local symName    = Symbol("name")
local symStatic  = Symbol("static")

local IS_BINARY_OP = {
    __add    = true,
    __sub    = true,
    __mul    = true,
    __div    = true,
    __mod    = true,
    __pow    = true,
    __concat = true,
    __eq     = true,
    __lt     = true,
    __le     = true,
}

local function isClass(k)
    return type(k) == "table" and getmetatable(k)[symIsClass]
end

local function isBaseOf(k1, k2)
    if isClass(k1) and isClass(k2) then
        while true do
            k2 = getmetatable(k2)[symBase]
            if k2 == nil then
                break
            elseif k1 == k2 then
                return true
            end
        end
    end
    return false
end

local function classOf(obj)
    local objMeta = getmetatable(obj)
    if objMeta then
        return objMeta[symClass]
    else
        return nil
    end
end

local function nameOf(k)
    return getmetatable(k)[symName]
end

local function isa(obj, klass)
    local objMeta = getmetatable(obj)
    if objMeta == nil then
        return false
    end

    local objKlass = objMeta[symClass]
    if objKlass == nil then
        return false
    elseif objKlass == klass then
        return true
    end

    -- Maybe it's an instance of some class deriving "klass"?
    while true do
        objKlass = getmetatable(objKlass)[symBase]
        if objKlass == nil then
            return false
        elseif objKlass == klass then
            return true
        end
    end
end

local function injectToEnv(func, name, value)
    -- luacheck: read_globals getfenv setfenv
    local oldEnv = getfenv(func)
    local newEnv =
        setmetatable(
            {[name] = value},
            {__index = oldEnv, __newindex = oldEnv})
    setfenv(func, newEnv)
end

local function findLocal(frame, name)
    local idx = 1
    while true do
        local n, v = debug.getlocal(frame + 1, idx) -- +1 for the findLocal() frame
        if n == name then
            return v
        elseif n == nil then
            error("Local variable \"" .. name .. "\" not found. Debug info missing?", 2)
        else
            idx = idx + 1
        end
    end
end

local function mkSuper(base, isCtor)
    local superMeta = {}

    if isCtor then
        -- We are creating a "super" object for a constructor, which means
        -- "super" should be callable and when called it should invoke the
        -- constructor of the base class.
        function superMeta.__call(_super, ...)
            local initBase = base.__init
            if initBase ~= nil then
                -- Now we must do something hacky. We need to somehow
                -- obtain the "self" object from the call frame because
                -- it's a function parameter.
                local obj = findLocal(2, "self")
                initBase(obj, ...)
            end
        end
    end

    -- Regardless of whether it's for a ctor or not, super:foo(...) should
    -- behave as if it were base:foo(...).
    function superMeta.__index(_super, key)
        local obj    = findLocal(2, "self")
        local method = base[key]
        if method == nil then
            -- No such method exists. Possibly a getter?
            local getter = base.__getter[key]
            if getter ~= nil then
                return getter(obj)
            else
                -- No it's not. Maybe it has a setter alone?
                local setter = base.__getter[key]
                if setter ~= nil then
                    error("Property " .. key .. " of class " .. nameOf(base) .. " is write-only", 2)
                else
                    -- It really doesn't exist, which is fine.
                    return nil
                end
            end
        elseif type(method) == "function" then
            -- FIXME: What if this was a class method as opposed to an instance method?
            return function(_super, ...)
                return method(obj, ...)
            end
        else
            return method
        end
    end

    -- "super.foo = 1" should behave as if it were "self.foo = 1", except
    -- for the case of "foo" being a setter.
    function superMeta.__newindex(_super, key, val)
        local obj = findLocal(2, "self")
        local setter = base.__setter[key]
        if setter ~= nil then
            setter(obj, val)
        else
            -- It's not a setter. Maybe it has a getter alone?
            local getter = base.__getter[key]
            if getter ~= nil then
                error("Property " .. key .. " of class " .. nameOf(base) .. " is read-only", 1)
            else
                -- No. This is genuiely a new property.
                rawset(obj, key, val)
            end
        end
    end

    return setmetatable({}, superMeta)
end

local function mkClass(name, base)
    if name == nil and base == nil then
        name = "(anonymous)"
    elseif type(name) == "table" and base == nil then
        base = name
        name = "(anonymous)"
    end

    if type(name) ~= "string" or
        (base ~= nil and not isClass(base)) then

        error("class() must be called as class(), class(name), class(base), or class(name, base)", 2)
    end

    local klass = {}
    klass.__getter = {}
    klass.__setter = {}

    if base then
        setmetatable(klass.__getter, {__index = base.__getter})
        setmetatable(klass.__setter, {__index = base.__setter})
    end

    local objMeta = {}
    objMeta[symClass] = klass

    function objMeta.__tostring(obj)
        local toStr = klass.__tostring
        if toStr ~= nil then
            return toStr(obj)
        else
            -- Just showing something like "[Object]" is unhelpful because
            -- there can be many such objects in the entire
            -- process. However, there is no raw* function that bypasses
            -- __tostring. So we must do something dirty.
            local meta = debug.getmetatable(obj)
            debug.setmetatable(obj, nil)
            local addr = string.sub(tostring(obj), #"table: " + 1)
            debug.setmetatable(obj, meta)
            return "[" .. name .. " " .. addr .. "]"
        end
    end

    function objMeta.__index(obj, key)
        -- The __index event for the instance object is triggered, which
        -- means the key doesn't exist in the object itself. This might be
        -- a method call or a getter call.
        local method = klass[key]
        if method == nil then
            -- No such method exists. Possibly a getter?
            local getter = klass.__getter[key]
            if getter ~= nil then
                return getter(obj)
            else
                -- No it's not. Maybe it has a setter alone?
                local setter = klass.__setter[key]
                if setter ~= nil then
                    error("Property " .. key .. " of class " .. nameOf(klass) .. " is write-only", 2)
                else
                    -- Not it's not. Maybe __index is overridden?
                    local index = klass.__index
                    if index ~= nil then
                        return index(obj, key)
                    else
                        -- It really doesn't exist, which is fine.
                        return nil
                    end
                end
            end
        else
            return method
        end
    end

    function objMeta.__newindex(obj, key, val)
        -- The __newindex event for the instance object is
        -- triggered, which means the key doesn't exist in the
        -- object itself. It could be a setter call.
        local setter = klass.__setter[key]
        if setter ~= nil then
            setter(obj, val)
        else
            -- No it's not. Maybe it has a getter alone?
            local getter = klass.__getter[key]
            if getter ~= nil then
                error("Property " .. key .. " of class " .. nameOf(klass) .. " is read-only", 2)
            else
                -- No. Maybe __newindex is overridden?
                local newindex = klass.__newindex
                if newindex ~= nil then
                    newindex(obj, key, val)
                else
                    -- No. This is genuinely a new property.
                    rawset(obj, key, val)
                end
            end
        end
    end

    function objMeta.__call(obj, ...)
        local call = klass.__call
        if call ~= nil then
            return call(obj, ...)
        else
            error("An instance of " .. nameOf(klass) .. " is not callable", 2)
        end
    end

    --
    -- Note [Overriding binary operations]
    --
    -- Binary operations are hard to override correctly. When Lua evaluates
    -- an expression like "o1 < o2", Lua first tries to use o1's __lt, and
    -- if it doesn't exist it uses o2's __lt. The mere existence of a
    -- metamethod changes the behaviour. This means we cannot define binary
    -- ops unconditionally, but when a class is defined there are no
    -- methods defined yet. We don't know if the class is going to have the
    -- method. Also metamethods cannot be found via metatable's metatable
    -- because Lua uses rawget() to look up metamethods. So the only way to
    -- conditionally define them is to detect definition of binary ops in
    -- klassMeta's __newindex.
    --

    function klass:new(...)
        local obj = setmetatable({}, objMeta)

        local initThis = klass.__init
        if initThis ~= nil then
            initThis(obj, ...)
        end

        return obj
    end

    function klass:made(obj)
        return isa(obj, klass)
    end

    local klassMeta = {}
    klassMeta[symName   ] = name
    klassMeta[symIsClass] = true
    klassMeta[symStatic ] = {} -- {[name] = true}
    function klassMeta.__tostring(_klass)
        return "[class " .. name .. "]"
    end
    if base then
        klassMeta.__index  = base
        klassMeta[symBase] = base

        local ctorSuper = mkSuper(base, true)
        local methSuper = mkSuper(base, false)
        function klassMeta.__newindex(self, key, value)
            if IS_BINARY_OP[key] then
                -- See note [Overriding binary operations]. Use klass.__op
                -- for objMeta.__op
                objMeta[key] = value
            end

            if type(value) == "function" then
                -- This is a method definition. Inject "super" in the
                -- environment of the function if there is a base class.
                if key == "__init" then
                    injectToEnv(value, "super", ctorSuper)
                else
                    injectToEnv(value, "super", methSuper)
                end

                -- If it's a static method, inject an error check to make
                -- sure they are called as klass:method(), not
                -- klass.method(). It's a very common mistake and produces
                -- a very confusing result.
                if not NDEBUG and klassMeta[symStatic][key] then
                    local method = value
                    value = function(self, ...)
                        if klass ~= self and not isBaseOf(klass, self) then
                            error(
                                string.format(
                                    "Misuse of %s:%s(): It cannot be called as %s.%s()",
                                    name, key, name, key), 2)
                        end
                        return method(self, ...)
                    end
                end
            end

            rawset(klass, key, value)
        end
    else
        function klassMeta.__newindex(self, key, value)
            if IS_BINARY_OP[key] then
                -- See note [Overriding binary operations]. Use klass.__op
                -- for objMeta.__op
                objMeta[key] = value
            end

            if type(value) == "function" then
                if not NDEBUG and klassMeta[symStatic][key] then
                    local method = value
                    value = function(self, ...)
                        if klass ~= self and not isBaseOf(klass, self) then
                            error(
                                string.format(
                                    "Misuse of %s:%s(): It cannot be called as %s.%s()",
                                    name, key, name, key), 2)
                        end
                        return method(self, ...)
                    end
                end
            end

            rawset(klass, key, value)
        end
    end
    setmetatable(klass, klassMeta)

    --
    -- Declare that the method with the given name is a static method.
    --
    function klass:static(method)
        assert(type(method) == "string", name..":static() expects a method name")
        klassMeta[symStatic][method] = true
    end

    --
    -- Declare that the method with the given name is purely virtual and
    -- needs overriding. Method names can be prefixed with "getter:" or
    -- "setter:" to mean pure virtual accessors.
    --
    function klass:abstract(method)
        assert(type(method) == "string", name..":abstract() expects a method name")

        local function pv(self)
            error(
                string.format(
                    "%s:%s() is a purely virtual method and has to be overridden",
                    nameOf(classOf(self)), method),
                2)
        end

        if string.find(method, "^getter:") then
            klass.__getter[string.sub(method, 8)] = pv

        elseif string.find(method, "^setter:") then
            klass.__setter[string.sub(method, 8)] = pv
        else
            klass[method] = pv
        end
    end

    --
    -- Define a method ":clone()" that creates a shallow copy of the
    -- object. When a function "f" is given it is applied to the shallow
    -- copy before it's returned, which can be used for deep-copying.
    --
    function klass:cloneable(f)
        assert(f == nil or type(f) == "function", name..":cloneable() takes an optional function")
        function klass:clone()
            -- In Lua 5.4 we need to temporarily remove its metatable
            -- because its __pairs might be overloaded. Its __metatable
            -- might also be overloaded.
            local meta = debug.getmetatable(self)
            debug.setmetatable(self, nil)

            local ret = {}
            for k, v in pairs(self) do
                rawset(ret, k, v)
            end
            debug.setmetatable(ret, meta)
            debug.setmetatable(self, meta)

            if f then
                f(ret)
            end
            return ret
        end
    end

    return klass
end

-- "class" is a callable object which constructs a class.
local class = setmetatable(
    {},
    {
        __call = function(_class, ...)
            return mkClass(...)
        end,
    })

-- class.isClass(k) returns true iff k is a class.
class.isClass = isClass

return class
