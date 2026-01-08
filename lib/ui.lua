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
}

return ui
