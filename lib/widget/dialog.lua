local Container = require("widget/container")
local class     = require("class")
local ui        = require("ui")

--
-- Caveat: the dialog will have a native close button but pushing it does
-- nothing. Pressing the ESC key closes the dialog with no means to catch
-- the event.
--
local Dialog = class("Dialog", Container)

function Dialog:__init(children)
    -- The "official documentation" lists no events for UIDialog. The
    -- actual window to be shown will have a native close button, but
    -- clicking it does absolutely nothing. Not even "Close" event will be
    -- emitted.
    super(nil, children)
    self._title = nil
end

function Dialog.__getter:title()
    return self._title
end
function Dialog.__setter:title(title)
    assert(type(title) == "string", "Window:setTitle() expects a string title")
    self._title = title
    if self.materialised then
        self.raw.WindowTitle = title
    end
end

function Dialog:materialise()
    if #self.children == 0 then
        -- Attempting to create an empty window causes DaVinci Resolve to
        -- crash. Not tested, but it most likely affects dialogs too.
        error("The dialog has no children. Add something before showing it", 2)
    end

    -- Nothing is documented at all, but these properties are confirmed to
    -- work.
    local props = {
        ID             = self.id,
        WindowModality = "ApplicationModal",
        WindowFlags    = {
            Dialog = true,
        },
        WindowTitle    = self._title,
    }

    local rawChildren = {}
    for _i, child in pairs(self.children) do
        table.insert(rawChildren, child.raw)
    end

    local raw = ui.dispatcher:AddDialog(props, rawChildren)
    raw:RecalcLayout()

    self:installEventHandlers(raw)

    return raw
end

function Dialog:show()
    -- UIDialog:Exec() seems to be broken. It opens up a modal dialg (even
    -- when WindowModality is unspecified) but then no widget events will
    -- be emitted and there'll be no way to close it. I have absolutely no
    -- idea what is the intended way to use UIDialog because seriously,
    -- it's completely undocumented.
    self.raw:Show()

    -- Shrink the dialog as far as possible.
    self.raw:Resize({0, 0})
end

function Dialog:hide()
    -- UIDialog:Done() closes the dialog too, but what's the point of using
    -- it if there are no known ways to exit from UIDialog:Exec() aside
    -- from pressing the ESC key? This is seriously frustrating.
    self.raw:Hide()
end

return Dialog
