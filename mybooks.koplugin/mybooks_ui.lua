local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local lfs = require("libs/libkoreader-lfs")

local Metrics = require("mybooks_metrics")

local M = {}

local ICON_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)[/\\]") or "."

function M.text(text, opts)
    opts = opts or {}
    return TextWidget:new{
        text = tostring(text or ""),
        face = opts.face or Metrics.body_face(),
        max_width = opts.width,
        bold = opts.bold,
        fgcolor = opts.color or Metrics.color.text,
        padding = opts.padding or Metrics.dp(2),
    }
end

function M.text_height(text, face, width)
    local box = TextBoxWidget:new{
        text = tostring(text or ""),
        face = face,
        width = width,
    }
    local height = box:getSize().h
    box:free()
    return height
end

function M.cover(path, width, height)
    if not path then
        return nil
    end
    return ImageWidget:new{
        file = path,
        width = width,
        height = height,
        scale_factor = 0,
        alpha = true,
    }
end

function M.paint_cover(bb, path, x, y, w, h)
    local image = M.cover(path, w, h)
    if not image then
        bb:paintRect(x, y, w, h, Metrics.color.line)
        return
    end
    local size = image:getSize()
    image:paintTo(bb, x + math.floor((w - size.w) / 2), y + math.floor((h - size.h) / 2))
    image:free()
end

-- Clips an image to a rounded rectangle (or a circle when radius is half its
-- size) by painting the surrounding corners with the background color.
function M.paint_round_image(bb, path, x, y, w, h, radius, bg)
    M.paint_cover(bb, path, x, y, w, h)
    x, y = math.floor(x), math.floor(y)
    w, h = math.floor(w), math.floor(h)
    radius = math.min(math.max(0, math.floor(radius or 0)), math.floor(math.min(w, h) / 2))
    if radius <= 0 then
        return
    end
    local fill = bg or Metrics.color.bg
    for dy = 0, h - 1 do
        local inset = 0
        if dy < radius then
            local d = radius - dy - 0.5
            inset = radius - math.floor(math.sqrt(math.max(0, radius * radius - d * d)))
        elseif dy >= h - radius then
            local d = dy - (h - radius) + 0.5
            inset = radius - math.floor(math.sqrt(math.max(0, radius * radius - d * d)))
        end
        if inset > 0 then
            bb:paintRect(x, y + dy, inset, 1, fill)
            bb:paintRect(x + w - inset, y + dy, inset, 1, fill)
        end
    end
end

function M.icon_path(name)
    return ICON_DIR .. "/icons/" .. tostring(name or "") .. ".svg"
end

function M.paint_icon(bb, name, x, y, size)
    local path = M.icon_path(name)
    if lfs.attributes(path, "mode") ~= "file" then
        return
    end
    local icon = IconWidget:new{
        file = path,
        width = size,
        height = size,
        alpha = true,
    }
    icon:paintTo(bb, x, y)
    icon:free()
end

function M.circle(bb, cx, cy, radius, color)
    local r2 = radius * radius
    for dy = -radius, radius do
        local dx = math.floor(math.sqrt(math.max(0, r2 - dy * dy)))
        bb:paintRect(cx - dx, cy + dy, dx * 2, 1, color or Metrics.color.line)
    end
end

function M.hit_rect(x, y, w, h, hit)
    return { x1 = x, y1 = y, x2 = x + w, y2 = y + h, hit = hit }
end

function M.contains(rect, pos)
    return pos.x >= rect.x1 and pos.x <= rect.x2 and pos.y >= rect.y1 and pos.y <= rect.y2
end

-- Paints a filled rectangle with rounded corners, row by row, so it works on
-- every BlitBuffer type (including 8-bit grayscale e-ink screens).
function M.round_rect(bb, x, y, w, h, radius, color)
    x, y = math.floor(x), math.floor(y)
    w, h = math.floor(w), math.floor(h)
    if w <= 0 or h <= 0 then
        return
    end
    radius = math.max(0, math.floor(radius or 0))
    radius = math.min(radius, math.floor(math.min(w, h) / 2))
    if radius <= 0 then
        bb:paintRect(x, y, w, h, color)
        return
    end
    for dy = 0, h - 1 do
        local inset = 0
        if dy < radius then
            local d = radius - dy - 0.5
            inset = radius - math.floor(math.sqrt(math.max(0, radius * radius - d * d)))
        elseif dy >= h - radius then
            local d = dy - (h - radius) + 0.5
            inset = radius - math.floor(math.sqrt(math.max(0, radius * radius - d * d)))
        end
        if inset < 0 then
            inset = 0
        end
        bb:paintRect(x + inset, y + dy, w - inset * 2, 1, color)
    end
end

-- A small raised card: soft drop shadow + light border + white fill.
function M.card(bb, x, y, w, h, opts)
    opts = opts or {}
    local radius = opts.radius or Metrics.dp(5)
    local border = opts.border or Metrics.color.line
    local fill = opts.fill or Metrics.color.bg
    if opts.shadow ~= false then
        M.round_rect(bb, x + 2, y + 2, w, h, radius, Metrics.color.shadow)
    end
    M.round_rect(bb, x, y, w, h, radius, border)
    M.round_rect(bb, x + 1, y + 1, w - 2, h - 2, math.max(0, radius - 1), fill)
end

-- An embossed (3D) horizontal divider: a darker top edge fading into a light
-- ridge, so it reads as a raised separator on white and on e-ink alike.
function M.divider(bb, x, y, w)
    bb:paintRect(x, y, w, 1, Metrics.color.faint)
    bb:paintRect(x, y + 1, w, 1, Metrics.color.shadow)
    bb:paintRect(x, y + 2, w, 1, Metrics.color.edge)
    bb:paintRect(x, y + 3, w, 1, Metrics.color.bg)
end

return M
