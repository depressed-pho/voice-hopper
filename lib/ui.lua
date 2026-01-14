local lazy = require("lazy").lazy

local ui = lazy {
    fusion = function ()
        -- luacheck: read_globals fusion
        assert(fusion, "Global \"fusion\" not defined")
        return fusion
    end,
    manager = function (self)
        return self.fusion.UIManager
    end,
    dispatcher = function (self)
        -- luacheck: read_globals bmd
        assert(bmd, "Global \"bmd\" not defined")
        return bmd.UIDispatcher(self.manager)
    end,
    platform = function (self)
        --
        -- Guess the platform we are on. This is only a guess. NEVER DO
        -- ANYTHING UNSAFE WITH THIS INFORMATION.
        --
        local appPath = self.fusion:MapPath("Fusion:/")
        if string.find(appPath, "\\Program Files") then
            return "win32"
        elseif string.find(appPath, "\\PROGRA~1") then
            return "win32"
        elseif string.find(appPath, "^/Applications/") then
            return "darwin"
        else
            return "linux"
        end
    end
}

return ui
