local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")

local I18N = require("mybooks_i18n")
local Metrics = require("mybooks_metrics")

local M = {}

function M.actions(title, buttons)
    local dialog
    dialog = ButtonDialog:new{
        title = title,
        buttons = buttons,
        width = Metrics.dp(520),
    }
    UIManager:show(dialog)
    return dialog
end

function M.choose(title, options, on_pick)
    local dialog
    local buttons = {}
    for _, option in ipairs(options) do
        local value = option.value
        local row = {
            {
                text = option.text,
                callback = function()
                    UIManager:close(dialog)
                    if on_pick then
                        on_pick(value, option)
                    end
                end,
            },
        }
        buttons[#buttons + 1] = row
    end
    buttons[#buttons + 1] = {
        {
            text = I18N.T("cancel"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
    }
    dialog = ButtonDialog:new{
        title = title,
        buttons = buttons,
        width = Metrics.dp(480),
    }
    UIManager:show(dialog)
    return dialog
end

function M.confirm(text, on_confirm, on_cancel)
    local dialog
    dialog = ConfirmBox:new{
        text = text,
        ok_text = I18N.T("ok"),
        cancel_text = I18N.T("cancel"),
        ok_callback = function()
            if on_confirm then
                on_confirm()
            end
        end,
        cancel_callback = function()
            if on_cancel then
                on_cancel()
            end
        end,
    }
    UIManager:show(dialog)
    return dialog
end

function M.sheet(title, buttons)
    return M.actions(title, buttons)
end

return M
