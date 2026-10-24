local Metrics = require("mybooks_metrics")

local M = {}

function M.header(title)
    return { kind = "header", title = title }
end

function M.section(title, opts)
    opts = opts or {}
    return { kind = "section", title = title, divider = opts.divider }
end

function M.space(height)
    return { kind = "space", h = height or Metrics.dp(8) }
end

function M.book_row(book, opts)
    opts = opts or {}
    return {
        kind = "row",
        title = book.title,
        sub = (book.author and book.author ~= "") and book.author or nil,
        image = opts.image,
        percent = opts.percent or book.progress_percent,
        badge = opts.badge,
        hit = opts.hit,
        on_hold = opts.on_hold,
        book = book,
    }
end

function M.book_card(book, opts)
    opts = opts or {}
    return {
        kind = "card",
        title = book.title,
        image = opts.image,
        percent = opts.percent or book.progress_percent,
        badge = opts.badge,
        hit = opts.hit,
        on_hold = opts.on_hold,
        book = book,
    }
end

function M.meta_row(name, count, opts)
    opts = opts or {}
    return {
        kind = "row",
        icon = opts.icon,
        title = tostring(name or ""),
        badge = count and tostring(count) or nil,
        hit = opts.hit,
        on_hold = opts.on_hold,
        value = name,
    }
end

function M.icon_row(icon, title, count, opts)
    opts = opts or {}
    return {
        kind = "row",
        icon = icon,
        title = title,
        badge = count and tostring(count) or (opts.badge or nil),
        hit = opts.hit,
        on_hold = opts.on_hold,
    }
end

function M.segmented(options, active)
    return { options = options, active = active }
end

function M.pill(text)
    return "[ " .. tostring(text or "") .. " ]"
end

return M
