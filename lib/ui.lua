local lazy = require("lazy").lazy

local ui = lazy {
    fusion = function ()
        assert(fusion, "Global \"fusion\" not defined")
        return fusion
    end,
    manager = function (self)
        return self.fusion.UIManager
    end,
    dispatcher = function (self)
        assert(bmd, "Global \"bmd\" not defined")
        return bmd.UIDispatcher(self.manager)
    end,
}

return ui
