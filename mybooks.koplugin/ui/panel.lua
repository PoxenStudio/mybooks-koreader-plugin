--[[
 Draw a panel with a title and badge.
 PoxenStudio@2026
]]

local Metrics = require("mybooks_metrics")
local UI = require("mybooks_ui")

local M = {}

function M.grid_width(width, pad, columns)
    columns = math.max(1, columns or 2)
    return math.floor((width - pad * (columns + 1)) / columns)
end

function M.height()
    return Metrics.dp(56)
end

function M.draw(bb, x, y, w, h, opts)
    opts = opts or {}
    UI.card(bb, x, y, w, h, {
        radius = Metrics.dp(6),
        border = Metrics.color.edge,
        shadow = false,
    })
    local inner = Metrics.dp(10)
    local icon_size = 0
    local icon_gap = 0
    if opts.icon and opts.icon ~= "" then
        icon_size = Metrics.dp(22)
        icon_gap = Metrics.dp(10)
        UI.paint_icon(bb, opts.icon, x + inner, y + math.floor((h - icon_size) / 2), icon_size)
    end
    local badge = nil
    local badge_w = 0
    if opts.badge ~= nil and opts.badge ~= "" then
        badge = UI.text(tostring(opts.badge), { face = Metrics.small_face(), color = Metrics.color.muted })
        badge_w = badge:getSize().w + Metrics.dp(6)
    end
    local title = UI.text(opts.title or "", {
        face = opts.face or Metrics.body_face(),
        color = opts.color,
        bold = opts.bold,
        width = math.max(Metrics.dp(20), w - inner * 2 - badge_w - icon_size - icon_gap),
    })
    local size = title:getSize()
    title:paintTo(bb, x + inner + icon_size + icon_gap, y + math.floor((h - size.h) / 2))
    title:free()
    if badge then
        local badge_size = badge:getSize()
        badge:paintTo(bb, x + w - inner - badge_size.w, y + math.floor((h - badge_size.h) / 2))
        badge:free()
    end
end

return M
