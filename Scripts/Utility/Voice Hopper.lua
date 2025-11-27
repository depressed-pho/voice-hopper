-- ----------------------------------------------------------------------------
-- OOP utility: this should be moved to a standalone Lua module
-- ----------------------------------------------------------------------------
local function class(base)
    -- The class object we are creating.
    local klass = {}

    if type(base) == 'table' then
        error("FIXME: Class inheritance not implemented yet", 2)
    end

    -- The class will be the metatable for all its instances. Redirect any
    -- missing method calls to the class itself.
    klass.__index = klass

    -- Expose a constructor which can be called by CLASS:new(ARGS...)
    function klass:new(...)
        local obj = {}
        setmetatable(obj, self)

        if self.__init then
            self.__init(obj, ...)
        end

        return obj
    end

    return klass
end

-- ----------------------------------------------------------------------------
-- Voice Hopper
-- ----------------------------------------------------------------------------

local HopperWindow = class()

function HopperWindow:__init(ui, disp)
    self._win = disp:AddWindow {
        ID = "VoiceHopper",
        TargetID = "VoiceHopper",
        WindowTitle = "Voice Hopper",
        Geometry = {0, 0, 500, 500},
        WindowFlags = {
            Window = true,
            WindowStaysOnTopHint = true,
        },
        ui:VGroup {
            ID = "root",
            ui:Label {
                ID = "TestLabel",
                Text = "Hello, World!",
            },
        },
    }
end

function Main()
    local ui = fusion.UIManager
    local disp = bmd.UIDispatcher(ui)

    local win = HopperWindow:new(ui, disp)

    win._win:Show()
    win._win.On.VoiceHopper.Close = function (ev)
        disp:ExitLoop()
    end
    disp:RunLoop()
end

Main()
