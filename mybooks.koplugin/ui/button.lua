--[[
 Draw a button with text.
 PoxenStudio@2026
]]

local Metrics = require("mybooks_metrics")
local UI = require("mybooks_ui")

local M = {}

function M.draw(bb, x, y, w, h, text, opts)
    opts = opts or {}
    local inset = opts.inset or Metrics.dp(2)
    UI.card(bb, x + inset, y + inset, w - inset * 2, h - inset * 2, {
        radius = opts.radius or Metrics.dp(6),
        border = opts.border or Metrics.color.edge,
        shadow = false,
    })
    local icon_size = 0
    local icon_gap = 0
    if opts.icon and opts.icon ~= "" then
        icon_size = Metrics.dp(18)
        icon_gap = Metrics.dp(5)
    end
    local label = UI.text(text or "", {
        face = opts.face or Metrics.body_face(),
        color = opts.color,
        bold = opts.bold,
        padding = Metrics.dp(2),
        width = math.max(Metrics.dp(20), w - inset * 2 - Metrics.dp(8) - icon_size - icon_gap),
    })
    local size = label:getSize()
    local left = x + math.floor((w - icon_size - icon_gap - size.w) / 2)
    if icon_size > 0 then
        UI.paint_icon(bb, opts.icon, left, y + math.floor((h - icon_size) / 2), icon_size)
    end
    label:paintTo(bb, left + icon_size + icon_gap, y + math.floor((h - size.h) / 2))
    label:free()
end

return M
