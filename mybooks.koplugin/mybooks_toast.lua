local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local M = {}

local active

local function close_active()
    if active then
        pcall(UIManager.close, UIManager, active)
        active = nil
    end
end

function M.show(text, timeout)
    close_active()
    logger.dbg("MyBooks: toast", text)
    active = InfoMessage:new{
        text = text,
        timeout = timeout or 3,
    }
    UIManager:show(active)
    return active
end

function M.error(text)
    return M.show(text, 5)
end

function M.loading(text)
    close_active()
    active = InfoMessage:new{
        text = text,
        timeout = nil,
    }
    UIManager:show(active)
    UIManager:forceRePaint()
    return active
end

function M.dismiss()
    close_active()
end

return M
