local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen

local M = {}

function M.dp(size)
    return Screen:scaleBySize(size or 1)
end

function M.screen_size()
    return Screen:getWidth(), Screen:getHeight()
end

function M.face(key, size)
    local face = Font:getFace(key or "cfont", size)
    return face
end

M.color = {
    text = Blitbuffer.COLOR_BLACK,
    muted = Blitbuffer.Color8(26),
    faint = Blitbuffer.COLOR_GRAY,
    line = Blitbuffer.COLOR_LIGHT_GRAY,
    bg = Blitbuffer.COLOR_WHITE,
    invert_text = Blitbuffer.COLOR_WHITE,
    accent = Blitbuffer.COLOR_BLACK,
    -- 3D / card helpers
    shadow = Blitbuffer.COLOR_GRAY_D,
    edge = Blitbuffer.COLOR_GRAY_B,
}

function M.title_face()
    return M.face("tfont")
end

function M.body_face()
    return M.face("cfont")
end

function M.small_face()
    return M.face("smallinfofont")
end

function M.tiny_face()
    return M.face("xx_smallinfofont")
end

function M.meta_face()
    return M.face("x_smallinfofont")
end

function M.row_height()
    local h = Screen:getHeight()
    return math.max(M.dp(56), math.floor(h * 0.11))
end

function M.format_duration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh%02dm", hours, minutes)
    end
    if minutes > 0 then
        return string.format("%dm", minutes)
    end
    return "0m"
end

function M.format_hours(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    return string.format("%.2f", seconds / 3600)
end

function M.format_percent(value)
    value = tonumber(value) or 0
    if value <= 0 then
        return "0%"
    end
    if value >= 100 then
        return "100%"
    end
    return string.format("%d%%", math.floor(value))
end

function M.format_size(bytes)
    bytes = tonumber(bytes) or 0
    if bytes >= 1024 * 1024 then
        return string.format("%.1f MB", bytes / 1024 / 1024)
    end
    if bytes >= 1024 then
        return string.format("%d KB", math.floor(bytes / 1024))
    end
    return string.format("%d B", bytes)
end

return M
