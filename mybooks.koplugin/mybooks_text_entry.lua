local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")

local I18N = require("mybooks_i18n")

local M = {}

function M.input(opts)
    local dialog
    local buttons = {
        {
            {
                text = I18N.T("cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = I18N.T("ok"),
                is_enter_default = true,
                callback = function()
                    local value = dialog:getInputText()
                    UIManager:close(dialog)
                    if opts.on_save then
                        opts.on_save(value)
                    end
                end,
            },
        },
    }
    dialog = InputDialog:new{
        title = opts.title or "",
        input = opts.value or "",
        input_hint = opts.hint or "",
        description = opts.description,
        text_type = opts.password and "password" or nil,
        buttons = buttons,
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

return M
