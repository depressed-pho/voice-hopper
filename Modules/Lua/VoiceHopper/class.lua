local Symbol = require("VoiceHopper/symbol")

local symClass   = Symbol("class")
local symBase    = Symbol("base")
local symIsClass = Symbol("isClass")

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

local function injectVar(func, name, value)
    if setfenv then
        local oldEnv = getfenv(func)
        local newEnv =
            setmetatable(
                {[name] = value},
                {__index = oldEnv, __newindex = oldEnv})
        setfenv(func, newEnv)
    elseif debug.getupvalue then
        local level = 1
        local unknown = falsea
        while true do
            local upname, upval = debug.getupvalue(func, level)
            if upname == "_ENV" then
                local newEnv =
                    setmetatable(
                        {[name] = value},
                        {__index = upval, __newindex = upval})
                debug.upvaluejoin(func, level, function() return newEnv end, 1)
                break
            elseif upname == "" then
                unknown = true
            elseif upname == nil then
                if unknown then
                    error("Failed to enumerate upvalues. Debug info missing?")
                else
                    -- This is fine. The function really has no upvalues,
                    -- which means it has no free variables.
                    break
                end
            else
                level = level + 1
            end
        end
    else
        error("Don't know how to inject a variable into the function environment", 1)
    end
end

local superOf
local function mkSuper(base, isCtor)
    local superMeta = {}

    if isCtor then
        -- We are creating a "super" object for a constructor, which means
        -- "super" should be callable and when called it should invoke the
        -- constructor of the base class.
        function superMeta.__call(_super, ...)
            local initBase = base.__init
            if initBase ~= nil then
                initBase(superOf, ...)
            end
        end
    end

    -- Regardless of whether it's for a ctor or not, super:foo(...) should
    -- behave as if it were base:foo(...).
    function superMeta.__index(_super, key)
        local method = base[key]
        -- FIXME: Check for errors.
        -- FIXME: What if this was a class method as opposed to an instance method?
        -- FIXME: What about accessors?
        return function(_super, ...)
            return method(superOf, ...)
        end
    end

    return setmetatable({}, superMeta)
end

local function class(name, base)
    if name == nil and base == nil then
        name = "(anonymous)"
    elseif type(name) == "table" and base == nil then
        base = name
        name = "(anonymous)"
    end

    if type(name) ~= "string" or
        ( base ~= nil and
          ( type(base) ~= "table" or not getmetatable(base)[symIsClass] )
        ) then
        error("class() must be called as class(), class(name), class(base), or class(name, base)", 2)
    end

    local klass = {}
    klass.name     = name
    klass.__getter = {}
    klass.__setter = {}

    if base then
        setmetatable(klass.__getter, {__index = base.__getter})
        setmetatable(klass.__setter, {__index = base.__setter})
    end

    local function obj2str(obj)
        local toStr = klass.__tostring
        if toStr ~= nil then
            return toStr(obj)
        else
            return "[" .. name .. "]"
        end
    end

    function klass:new(...)
        local obj = {}

        local objMeta = {}
        objMeta.__tostring = obj2str
        objMeta[symClass]  = klass
        if base then
            function objMeta.__index(_obj, key)
                -- The __index event for the instance object is triggered,
                -- which means the key doesn't exist in the object
                -- itself. This might be a method call or a getter call.
                superOf = obj
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
                            error("Property " .. key .. " of class " .. klass.name .. " is write-only", 2)
                        else
                            -- It really doesn't exist, which is fine.
                            return nil
                        end
                    end
                else
                    return method
                end
            end

            function objMeta.__newindex(_obj, key, val)
                -- The __newindex event for the instance object is
                -- triggered, which means the key doesn't exist in the
                -- object itself. It could be a setter call.
                superOf = obj
                local setter = klass.__setter[key]
                if setter ~= nil then
                    setter(obj, val)
                else
                    -- No it's not. Maybe it has a getter alone?
                    local getter = klass.__getter[key]
                    if getter ~= nil then
                        error("Property " .. key .. " of class " .. klass.name .. " is read-only", 1)
                    else
                        -- No. This is genuinely a new property.
                        rawset(obj, key, val)
                    end
                end
            end
        else
            objMeta.__index = klass
        end
        setmetatable(obj, objMeta)

        local initThis = klass.__init
        if initThis ~= nil then
            superOf = obj
            initThis(obj, ...)
        end

        return obj
    end

    function klass:made(obj)
        return isa(obj, klass)
    end

    local klassMeta = {}
    klassMeta[symIsClass] = true
    function klassMeta.__tostring(_klass)
        return "[class " .. name .. "]"
    end
    if base then
        klassMeta.__index  = base
        klassMeta[symBase] = base
        function klassMeta.__newindex(klass, key, value)
            if type(value) == "function" then
                -- This is a method definition. Inject "super" in the
                -- environment of the function if there is a base class.
                local isCtor = key == "__init"
                local super  = mkSuper(base, isCtor)
                -- Do we really need to create a separate "super" object
                -- for each method? Yes we do, because we will need to
                -- modify this "super" every time the method is called so
                -- that super:foo() can work.
                injectVar(value, "super", super)
            end
            rawset(klass, key, value)
        end
    end
    setmetatable(klass, klassMeta)

    return klass
end

return class
