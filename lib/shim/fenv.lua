--
-- Shim getfenv/setfenv that was removed from Lua 5.2, based on
-- https://github.com/davidm/lua-compat-env/blob/master/lua/compat_env.lua
--

if getfenv == nil or setfenv == nil then
    local function getFunc(caller, f)
        if type(f) == "function" then
            -- Do nothing
        elseif type(f) == "number" then
            assert(f ~= 0, "This should be handled in the caller")

            if f < 0 then
                error(
                    string.format(
                        "%s expects either a non-negative number or a function as its 1st argument: %s",
                        caller, f),
                    3)
            else
                -- Level 1 is the caller of getfenv(). It's also the caller
                -- of debug.getinfo() on Lua > 5.2 but 0 was the caller on
                -- Lua 5.1. The lack of getfenv() means we are on Lua >
                -- 5.2.
                f = debug.getinfo(f + 1, "f").func
            end
        else
            error(
                string.format(
                    "%s expects either a number or a function as its 1st argument: %s",
                    caller, f),
                3)
        end
    end

    local function getEnv(f)
        local idx     = 1
        local unknown = false
        while true do
            local upname, upval = debug.getupvalue(f, idx)
            if upname == "_ENV" then
                return upval, idx
            elseif upname == "" then
                unknown = true
            elseif upname == nil then
                if unknown then
                    error("Failed to enumerate upvalues. Debug info missing?", 3)
                else
                    -- This function really has no _ENV, which means it has
                    -- either no free variables or it's a C function.
                    return nil
                end
            else
                idx = idx + 1
            end
        end
    end

    function getfenv(f)
        if f == nil then
            -- Special case: return the environment of the caller of
            -- getfenv().
            f = 1
        elseif f == 0 then
            -- Special case: return the global environment.
            return _G
        end

        -- Translate "f" into a real function.
        f = getFunc("getfenv", f)

        return getEnv(f) or _G
    end

    function setfenv(f, env)
        if f == 0 then
            -- Special case: the caller tried to change the environment of
            -- the current coroutine. We could simulate them by installing
            -- a function call hook with debug.sethook() and replacing _ENV
            -- for each and every function called. But it's of course not a
            -- realistic solution. It's completely unacceptable to make
            -- everything so slow just for loading this shim.
            error("Thread environments unsupported in " .. _VERSION, 2)
        end

        -- Translate "f" into a real function.
        f = getFunc("setfenv", f)

        local _oldEnv, idx = getEnv(f)
        if idx ~= nil then
            -- Create a non-shared environment:
            -- http://lua-users.org/lists/lua-l/2010-06/msg00313.html
            debug.upvaluejoin(f, idx, function() return env end, 1)
        end

        return f
    end
end
