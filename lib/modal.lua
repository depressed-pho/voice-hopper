local Button   = require("widget/button")
local Dialog   = require("widget/dialog")
local Label    = require("widget/label")
local Promise  = require("promise")
local Spacer   = require("widget/spacer")
local HGroup   = require("widget/container/h-group")
local VGap     = require("widget/v-gap")
local VGroup   = require("widget/container/v-group")
local readonly = require("readonly")

--
-- Simple modal dialogs like JavaScript window.confirm().
--
local modal = {}

--
-- Show a confirmation dialog and return a Promise which will be resolved
-- (with no values) when its default button is clicked or rejected when its
-- non-default button is clicked. Supported options are:
--
--   * title: window title
--   * defaultButton: the label of the default button
--   * nonDefaultButton: the label of the non-default button
--
function modal.confirm(message, opts)
    assert(type(message) == "string", "modal.confirm() expects a string message as its 1st argument")

    opts = opts or {}
    assert(type(opts) == "table" and getmetatable(opts) == nil,
           "modal.confirm() expects an optional table as its 2nd argument")

    opts.title = opts.title or "Confirmation"
    assert(type(opts.title) == "string",
           "title is expected to be an optional string")

    opts.defaultButton = opts.defaultButton or "OK"
    assert(type(opts.defaultButton) == "string",
           "defaultButton is expected to be an optional string")

    opts.nonDefaultButton = opts.nonDefaultButton or "Cancel"
    assert(type(opts.nonDefaultButton) == "string",
           "nonDefaultButton is expected to be an optional string")

    local promise, resolve, reject = Promise:withResolvers()

    local dialog = Dialog:new()
    dialog.title = opts.title
    do
        local root = VGroup:new()
        local gap  = 5
        do
            local label = Label:new(message)
            label.weight = 0
            root:addChild(label)
            root:addChild(VGap:new(gap))
        end
        do
            local row = HGroup:new()
            row.weight = 0
            row:addChild(Spacer:new())
            do
                local button = Button:new(opts.nonDefaultButton)
                button.weight  = 0
                button.default = false
                button:on("ui:Clicked", function()
                    dialog.raw:Hide()
                    reject()
                end)
                row:addChild(button)
            end
            do
                local button = Button:new(opts.defaultButton)
                button.weight  = 0
                button.default = true
                button:on("ui:Clicked", function()
                    dialog.raw:Hide()
                    resolve()
                end)
                row:addChild(button)
            end
            root:addChild(row)
        end
        dialog:addChild(root)
    end

    dialog:show()
    return promise
end

return readonly(modal)
