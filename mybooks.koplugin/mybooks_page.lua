local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Metrics = require("mybooks_metrics")
local UI = require("mybooks_ui")
local Button = require("ui.button")

local Page = InputContainer:extend{
    title = "",
    items = {},
    show_back = true,
    mode = "list",
    header_buttons = {},
    footer_buttons = {},
    footer_button_rows = 1,
    pager = nil,
}

function Page:init()
    local w, h = Metrics.screen_size()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.header_h = Metrics.dp(48)
    self.footer_row_h = Metrics.dp(34)
    self.footer_h = self.footer_row_h * math.max(1, self.footer_button_rows or 1)
    self.pad = Metrics.dp(8)
    self.row_h = Metrics.row_height()
    self.list_h = h - self.header_h - self.footer_h
    self.offset = 0
    self.grid_top = 0
    self.hit_rows = {}
    self.hit_buttons = {}
    Page.open_pages = Page.open_pages or {}
    Page.open_pages[self] = true
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
        Hold = { GestureRange:new{ ges = "hold", range = self.dimen } },
        SwipeNorth = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "north" } },
        SwipeSouth = { GestureRange:new{ ges = "swipe", range = self.dimen, direction = "south" } },
    }
    self.key_events = {
        Back = { { "Back" } },
        Left = { { "Left" } },
        Right = { { "Right" } },
        Up = { { "Up" } },
        Down = { { "Down" } },
    }
end

function Page:set_items(items, reset)
    self.items = items or {}
    if reset or self.offset > self:content_height() then
        self.offset = 0
        self.grid_top = 0
    end
    self:refresh()
end

function Page:item_height(item)
    if item.kind == "header" then
        return Metrics.dp(30)
    end
    if item.kind == "section" then
        return Metrics.dp(50)
    end
    if item.kind == "space" then
        return item.h or self.pad
    end
    if item.kind == "text" then
        return (item.h or Metrics.dp(120)) + Metrics.dp(4)
    end
    return item.h or self.row_h
end

function Page:content_height()
    local total = 0
    for _, item in ipairs(self.items) do
        total = total + self:item_height(item)
    end
    return total
end

function Page:max_offset()
    return math.max(0, self:content_height() - self.list_h)
end

function Page:scroll_to_end()
    self.offset = self:max_offset()
    self:refresh()
end

function Page:refresh()
    UIManager:setDirty(self, "ui")
end

function Page:close()
    if self._closed then
        return
    end
    self._closed = true
    if Page.open_pages then
        Page.open_pages[self] = nil
    end
    UIManager:close(self)
    if self.on_close then
        self.on_close()
    end
end

function Page.close_all()
    local pages = {}
    for page in pairs(Page.open_pages or {}) do
        pages[#pages + 1] = page
    end
    for _, page in ipairs(pages) do
        page:close()
    end
    Page.open_pages = {}
end

function Page:onCloseWidget()
    if self._content_bb then
        self._content_bb:free()
        self._content_bb = nil
    end
    if self._closed then
        return
    end
    self._closed = true
    if Page.open_pages then
        Page.open_pages[self] = nil
    end
    if self.on_close then
        self.on_close()
    end
end

function Page:_draw_button(bb, btn, x, y, w, h, boxed)
    if boxed then
        Button.draw(bb, x, y, w, h, btn.text, { face = btn.face, icon = btn.icon })
    else
        local text = TextWidget:new{
            text = btn.text or "",
            face = btn.face or Metrics.body_face(),
            fgcolor = Metrics.color.text,
            padding = Metrics.dp(2),
        }
        local size = text:getSize()
        text:paintTo(bb, x + math.floor((w - size.w) / 2), y + math.floor((h - size.h) / 2))
        text:free()
    end
    if btn.hit then
        self.hit_buttons[#self.hit_buttons + 1] = UI.hit_rect(x, y, w, h, btn.hit)
    end
end

function Page:paintTo(bb, x, y)
    self.hit_rows = {}
    self.hit_buttons = {}
    local w = self.dimen.w
    bb:paintRect(x, y, w, self.dimen.h, Metrics.color.bg)

    if self.show_back then
        self:_draw_button(bb, { text = "‹", hit = function() self:close() end }, x, y, self.header_h, self.header_h)
    end
    local title_left = x + (self.show_back and self.header_h or self.pad)
    local buttons_w = #self.header_buttons * self.header_h
    local note = nil
    local note_w = 0
    if self.header_note and self.header_note ~= "" then
        note = UI.text(self.header_note, { face = Metrics.tiny_face(), color = Metrics.color.muted, padding = 0 })
        note_w = note:getSize().w + Metrics.dp(6)
    end
    local title = TextWidget:new{
        text = self.title or "",
        face = Metrics.title_face(),
        max_width = math.max(Metrics.dp(40), w - (title_left - x) - buttons_w - self.pad - note_w),
    }
    local title_size = title:getSize()
    local title_y = y + math.floor((self.header_h - title_size.h) / 2)
    title:paintTo(bb, title_left, title_y)
    title:free()
    if note then
        local note_size = note:getSize()
        note:paintTo(bb, title_left + title_size.w + Metrics.dp(6), title_y + title_size.h - note_size.h)
        note:free()
    end

    local bx = x + w - buttons_w
    for _, btn in ipairs(self.header_buttons) do
        self:_draw_button(bb, btn, bx, y, self.header_h, self.header_h)
        bx = bx + self.header_h
    end
    bb:paintRect(x, y + self.header_h - 1, w, 1, Metrics.color.line)

    local content_bb = self:_content_buffer(bb, w, self.list_h)
    content_bb:fill(Metrics.color.bg)
    self:paintContent(content_bb, 0, 0)
    bb:blitFrom(content_bb, x, y + self.header_h)
    local top_limit = y + self.header_h
    local bottom_limit = y + self.dimen.h - self.footer_h
    local kept = {}
    for _, rect in ipairs(self.hit_rows) do
        rect.x1 = rect.x1 + x
        rect.x2 = rect.x2 + x
        rect.y1 = math.max(top_limit, rect.y1 + top_limit)
        rect.y2 = math.min(bottom_limit, rect.y2 + top_limit)
        if rect.y2 > rect.y1 then
            kept[#kept + 1] = rect
        end
    end
    self.hit_rows = kept

    local footer_y = y + self.dimen.h - self.footer_h
    if #self.footer_buttons > 0 or self.pager then
        bb:paintRect(x, footer_y, w, 1, Metrics.color.line)
    end
    local cells = {}
    if self.pager then
        cells[#cells + 1] = { pager = true }
    end
    for _, btn in ipairs(self.footer_buttons) do
        cells[#cells + 1] = btn
    end
    local rows = math.max(1, self.footer_button_rows or 1)
    local row_h = math.floor(self.footer_h / rows)
    local per_row = math.ceil(#cells / rows)
    for row = 0, rows - 1 do
        local first = row * per_row + 1
        local last = math.min(#cells, first + per_row - 1)
        local count = last - first + 1
        if count > 0 then
            local cell_w = math.floor(w / count)
            local fx = x + math.floor((w - cell_w * count) / 2)
            local row_y = footer_y + row * row_h
            for index = first, last do
                local cell = cells[index]
                if cell.pager then
                    local label = string.format("%d/%d", self.pager.page or 1, self.pager.pages or 1)
                    local text = TextWidget:new{ text = label, face = Metrics.small_face(), fgcolor = Metrics.color.muted }
                    local size = text:getSize()
                    text:paintTo(bb, fx + math.floor((cell_w - size.w) / 2), row_y + math.floor((row_h - size.h) / 2))
                    text:free()
                else
                    self:_draw_button(bb, cell, fx, row_y, cell_w, row_h, true)
                end
                fx = fx + cell_w
            end
        end
    end
end

function Page:_content_buffer(bb, w, h)
    local buffer = self._content_bb
    if not buffer or buffer:getWidth() ~= w or buffer:getHeight() ~= h then
        if buffer then
            buffer:free()
        end
        buffer = Blitbuffer.new(w, h, bb:getType())
        self._content_bb = buffer
    end
    return buffer
end

function Page:paintContent(bb, x, y)
    if self.mode == "grid" then
        self:_paint_grid(bb, x, y)
    else
        self:_paint_list(bb, x, y)
    end
end

function Page:_paint_list(bb, x, y)
    self.offset = math.min(self.offset, self:max_offset())
    local bottom = y + self.list_h
    local row_y = y - self.offset
    for _, item in ipairs(self.items) do
        local height = self:item_height(item)
        local top = row_y
        row_y = row_y + height
        if row_y > y and top < bottom then
            if item.kind == "header" then
                local text = TextWidget:new{
                    text = item.title or "",
                    face = Metrics.small_face(),
                    max_width = self.dimen.w - self.pad * 2,
                    fgcolor = Metrics.color.muted,
                }
                text:paintTo(bb, x + self.pad, top + Metrics.dp(4))
                text:free()
            elseif item.kind == "section" then
                if item.divider then
                    bb:paintRect(x + self.pad, top + Metrics.dp(6), self.dimen.w - self.pad * 2, 1, Metrics.color.edge)
                end
                local text = TextWidget:new{
                    text = item.title or "",
                    face = Metrics.body_face(),
                    bold = true,
                    max_width = self.dimen.w - self.pad * 2,
                    fgcolor = Metrics.color.text,
                }
                text:paintTo(bb, x + self.pad, top + Metrics.dp(18))
                text:free()
            elseif item.kind == "space" then
                -- spacer only
            elseif item.kind == "text" then
                local box = TextBoxWidget:new{
                    text = item.text or "",
                    face = item.face or Metrics.body_face(),
                    width = self.dimen.w - self.pad * 2,
                    height = height - Metrics.dp(4),
                    fgcolor = item.color or Metrics.color.muted,
                }
                box:paintTo(bb, x + self.pad, top)
                box:free()
                self:_add_row_hit(x, top, self.dimen.w, height, item, y, bottom)
            else
                if top >= y - height and top <= bottom then
                    self:_paint_row(bb, item, x, top, self.dimen.w, height)
                end
                self:_add_row_hit(x, top, self.dimen.w, height, item, y, bottom)
                bb:paintRect(x + self.pad, top + height - 1, self.dimen.w - self.pad * 2, 1, Metrics.color.line)
            end
        end
        if row_y > bottom then
            break
        end
    end
end

function Page:_add_row_hit(x, top, w, h, item, y, bottom)
    local y1 = math.max(top, y)
    local y2 = math.min(top + h, bottom)
    if y2 <= y1 then
        return
    end
    local rect = UI.hit_rect(x, y1, w, y2 - y1, item.hit)
    rect.on_hold = item.on_hold
    self.hit_rows[#self.hit_rows + 1] = rect
end

function Page:_paint_row(bb, item, x, y, w, h)
    local pad = self.pad
    local left = x + pad
    if item.image then
        local cw = math.floor(h * 0.62)
        local ch = h - pad
        UI.paint_cover(bb, item.image, left, y + math.floor((h - ch) / 2), cw, ch)
        left = left + cw + pad
    elseif item.icon then
        local text = TextWidget:new{ text = item.icon, face = Metrics.body_face() }
        local size = text:getSize()
        text:paintTo(bb, left, y + math.floor((h - size.h) / 2))
        text:free()
        left = left + size.w + pad
    end

    local right_pad = Metrics.dp(104)
    local text_w = math.max(Metrics.dp(60), w - (left - x) - right_pad)
    local title = TextWidget:new{
        text = item.title or "",
        face = item.face or Metrics.body_face(),
        max_width = text_w,
        bold = item.bold,
    }
    local title_size = title:getSize()
    local ty = y + math.floor((h - title_size.h) / 2)
    if item.sub and item.sub ~= "" then
        ty = y + Metrics.dp(6)
    end
    title:paintTo(bb, left, ty)
    title:free()
    if item.sub and item.sub ~= "" then
        local sub = TextWidget:new{
            text = item.sub,
            face = item.sub_face or Metrics.small_face(),
            max_width = text_w,
            fgcolor = Metrics.color.muted,
        }
        sub:paintTo(bb, left, ty + title_size.h + Metrics.dp(2))
        sub:free()
    end

    local right = x + w - pad
    if item.percent then
        local label = TextWidget:new{
            text = Metrics.format_percent(item.percent),
            face = Metrics.small_face(),
            fgcolor = Metrics.color.muted,
        }
        local size = label:getSize()
        label:paintTo(bb, right - size.w, y + Metrics.dp(8))
        label:free()
        local bar = ProgressWidget:new{
            width = right_pad - Metrics.dp(20),
            height = Metrics.dp(6),
            percentage = math.min(1, math.max(0, (item.percent or 0) / 100)),
        }
        bar:paintTo(bb, right - bar:getSize().w, y + h - Metrics.dp(18))
        bar:free()
    elseif item.badge then
        local label = TextWidget:new{
            text = tostring(item.badge),
            face = Metrics.small_face(),
            fgcolor = Metrics.color.muted,
        }
        local size = label:getSize()
        label:paintTo(bb, right - size.w, y + math.floor((h - size.h) / 2))
        label:free()
    end
end

function Page:grid_metrics()
    local pad = self.pad
    local cell_w = math.floor((self.dimen.w - pad * 3) / 2)
    local rows = math.max(1, self.grid_rows or 1)
    local cell_h = math.floor(self.list_h / rows)
    local cover_h = math.max(Metrics.dp(40), cell_h - Metrics.dp(52))
    return cell_w, cover_h, cell_h
end

function Page:_paint_grid(bb, x, y)
    local pad = self.pad
    local cell_w, cover_h, cell_h = self:grid_metrics()
    local visible = math.max(1, math.floor(self.list_h / cell_h))
    local rows = math.ceil(#self.items / 2)
    local max_top = math.max(0, rows - visible)
    if self.grid_top > max_top then
        self.grid_top = max_top
    end
    local index = self.grid_top * 2 + 1
    local last = math.min(#self.items, index + visible * 2 - 1)
    local row = 0
    while index <= last do
        local cy = y + row * cell_h
        for col = 0, 1 do
            local item = self.items[index]
            if not item then
                break
            end
            local cx = x + pad + col * (cell_w + pad)
            UI.paint_cover(bb, item.image, cx, cy, cell_w, cover_h)
            local title = TextWidget:new{
                text = item.title or "",
                face = Metrics.small_face(),
                max_width = cell_w,
                padding = 0,
            }
            title:paintTo(bb, cx, cy + cover_h + Metrics.dp(3))
            title:free()
            if item.percent then
                local bar = ProgressWidget:new{
                    width = cell_w,
                    height = Metrics.dp(5),
                    percentage = math.min(1, math.max(0, (item.percent or 0) / 100)),
                }
                bar:paintTo(bb, cx, cy + cover_h + Metrics.dp(22))
                bar:free()
                local label = TextWidget:new{
                    text = Metrics.format_percent(item.percent),
                    face = Metrics.small_face(),
                    fgcolor = Metrics.color.muted,
                    padding = 0,
                }
                label:paintTo(bb, cx, cy + cover_h + Metrics.dp(29))
                label:free()
            elseif item.badge then
                local label = TextWidget:new{
                    text = tostring(item.badge),
                    face = Metrics.small_face(),
                    fgcolor = Metrics.color.muted,
                    padding = 0,
                }
                label:paintTo(bb, cx, cy + cover_h + Metrics.dp(29))
                label:free()
            end
            local y2 = math.min(cy + cell_h, y + self.list_h)
            if y2 > cy then
                self.hit_rows[#self.hit_rows + 1] = UI.hit_rect(cx, cy, cell_w, y2 - cy, item.hit)
            end
            index = index + 1
        end
        row = row + 1
    end
end

function Page:onBack()
    self:close()
    return true
end

function Page:onTap(_, ges)
    for _, btn in ipairs(self.hit_buttons) do
        if UI.contains(btn, ges.pos) then
            btn.hit()
            return true
        end
    end
    for _, row in ipairs(self.hit_rows) do
        if UI.contains(row, ges.pos) then
            if row.hit then
                row.hit()
            end
            return true
        end
    end
    return true
end

function Page:onHold(_, ges)
    for _, row in ipairs(self.hit_rows) do
        if UI.contains(row, ges.pos) then
            if row.on_hold then
                row.on_hold()
            elseif row.hit then
                row.hit()
            end
            return true
        end
    end
    return true
end

function Page:onSwipeNorth()
    self:scroll(1)
    return true
end

function Page:onSwipeSouth()
    self:scroll(-1)
    return true
end

function Page:onLeft()
    self:scroll(-1)
    return true
end

function Page:onRight()
    self:scroll(1)
    return true
end

function Page:onUp()
    self:scroll(-1)
    return true
end

function Page:onDown()
    self:scroll(1)
    return true
end

function Page:scroll(delta)
    if self.mode == "grid" then
        local _, _, cell_h = self:grid_metrics()
        local visible = math.max(1, math.floor(self.list_h / cell_h))
        local rows = math.ceil(#self.items / 2)
        local max_top = math.max(0, rows - visible)
        self.grid_top = math.min(max_top, math.max(0, self.grid_top + delta))
        logger.dbg("MyBooks: grid scroll", self.grid_top)
    else
        local step = math.floor(self.list_h * 0.75)
        self.offset = math.min(self:max_offset(), math.max(0, self.offset + delta * step))
        logger.dbg("MyBooks: list scroll", self.offset)
    end
    self:refresh()
end

return Page
