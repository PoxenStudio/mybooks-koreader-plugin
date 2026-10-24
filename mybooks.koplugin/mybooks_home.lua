local UIManager = require("ui/uimanager")
local logger = require("logger")

local DeviceInfo = require("mybooks_device")
local I18N = require("mybooks_i18n")
local Metrics = require("mybooks_metrics")
local Page = require("mybooks_page")
local Panel = require("ui.panel")
local State = require("mybooks_state")
local Thumbnails = require("mybooks_thumbnails")
local Toast = require("mybooks_toast")
local UI = require("mybooks_ui")

local M = {}

local SECTION_LABELS = {
    favorites = "my_favorites",
    wants = "my_wishlist",
    read_done = "my_read",
    categories = "categories",
    tags = "tags",
    authors = "authors",
    recent = "latest",
}

local META_KINDS = {
    categories = "category",
    tags = "tag",
    authors = "author",
}

local SECTION_ICONS = {
    search = "search",
    favorites = "favorites",
    wants = "wants",
    read_done = "read_done",
    categories = "categories",
    tags = "tags",
    authors = "authors",
    recent = "recent",
}

local HomePage = Page:extend{
    show_back = false,
}

local function first_char(text)
    text = tostring(text or "")
    local byte = text:byte(1)
    if not byte then
        return "?"
    end
    local length = 1
    if byte >= 240 then
        length = 4
    elseif byte >= 224 then
        length = 3
    elseif byte >= 192 then
        length = 2
    end
    return text:sub(1, length)
end

function HomePage:init()
    Page.init(self)
    self.title = State.setting("site_title", I18N.T("app_title"))
    self.header_note = State.setting("site_version", "")
    self.version = "Rev: " .. DeviceInfo.plugin_version()
    self.version_face = Metrics.face("cfont", 18)
    self.footer_h = 0
    self.list_h = self.dimen.h - self.header_h
    self.header_buttons = {
        {
            text = "⚙",
            hit = function()
                require("mybooks_settings_page").show(self.api)
            end,
        },
        {
            text = "≡",
            hit = function()
                require("mybooks_browse").show_tree(self.api)
            end,
        },
    }
    self.data = State.home()
end

function HomePage:load_site_info()
    local rsp = self.api:get_abs("/api/user/info")
    local sys = rsp and rsp.sys or {}
    if sys.title and sys.title ~= "" then
        self.title = tostring(sys.title)
        State.set_setting("site_title", self.title)
    end
    if sys.version then
        self.header_note = tostring(sys.version)
        State.set_setting("site_version", self.header_note)
    end
end

function HomePage:load_home()
    self:load_site_info()
    local rsp, err = self.api:get("/home")
    if err then
        logger.warn("MyBooks: home load failed", err)
        Toast.error(require("mybooks_list_view").error_text(err))
        return false
    end
    State.set_home(rsp)
    self.data = rsp
    local profile = rsp.profile or {}
    if profile.avatar and profile.avatar ~= "" then
        local cached = State.setting("avatar_url", "")
        local path = DeviceInfo.cache_dir() .. "/avatar.jpg"
        if cached ~= profile.avatar or not DeviceInfo.file_exists(path) then
            local part = path .. ".part"
            local saved = self.api:fetch_file(self.api:resolve(profile.avatar), part)
            if saved then
                os.rename(part, path)
                State.set_setting("avatar_url", profile.avatar)
            else
                pcall(os.remove, part)
            end
        end
    end
    self:refresh()
    Thumbnails.prefetch(self.api, rsp.reading_now, 3)
    self:refresh()
    return true
end

function HomePage:open_book(book)
    local Download = require("mybooks_download")
    local path = Download.local_path(book)
    if path then
        Download.open_file(path)
        return
    end
    Download.start(self.api, book)
end

function HomePage:open_section(kind, title)
    local Browse = require("mybooks_browse")
    local meta = META_KINDS[kind]
    if meta then
        Browse.show_meta(self.api, meta)
    else
        Browse.show_books(self.api, kind, nil, title)
    end
end

function HomePage:stat_card_h()
    if not self._stat_card_h then
        local label = UI.text("0.00", { face = Metrics.tiny_face(), padding = 0 })
        local value = UI.text("0.00", { face = Metrics.body_face(), bold = true, padding = 0 })
        self._stat_label_h = label:getSize().h
        self._stat_value_h = value:getSize().h
        label:free()
        value:free()
        self._stat_card_h = self._stat_label_h + self._stat_value_h + Metrics.dp(12)
    end
    return self._stat_card_h
end

function HomePage:stats_height()
    return math.floor(Metrics.dp(44)) + Metrics.dp(8) + self:stat_card_h() * 2 + Metrics.dp(6)
end

function HomePage:_paint_stat_card(bb, x, y, w, h, label, value, unit)
    UI.card(bb, x, y, w, h, { radius = Metrics.dp(5) })
    local inner = Metrics.dp(7)
    local label_text = UI.text(label, { face = Metrics.tiny_face(), color = Metrics.color.muted, padding = 0 })
    label_text:paintTo(bb, x + inner, y + Metrics.dp(5))
    label_text:free()

    local value_text = UI.text(value, { face = Metrics.body_face(), bold = true, padding = 0 })
    local value_size = value_text:getSize()
    local vy = y + h - value_size.h - Metrics.dp(5)
    value_text:paintTo(bb, x + inner, vy)
    value_text:free()

    if unit and unit ~= "" then
        local unit_text = UI.text(unit, { face = Metrics.small_face(), color = Metrics.color.muted, padding = 0 })
        local unit_size = unit_text:getSize()
        unit_text:paintTo(bb, x + inner + value_size.w + Metrics.dp(3), vy + value_size.h - unit_size.h - Metrics.dp(1))
        unit_text:free()
    end
end

function HomePage:_paint_stats(bb, x, y, w)
    local pad = self.pad
    local profile = self.data.profile or {}
    local stats = self.data.stats or {}
    local status = stats.book_status or {}
    local streak = stats.streak or {}

    local avatar = math.floor(Metrics.dp(44))
    local path = DeviceInfo.cache_dir() .. "/avatar.jpg"
    if DeviceInfo.file_exists(path) then
        UI.paint_round_image(bb, path, x + pad, y, avatar, avatar, math.floor(avatar / 2), Metrics.color.bg)
    else
        local cx = x + pad + math.floor(avatar / 2)
        UI.circle(bb, cx, y + math.floor(avatar / 2), math.floor(avatar / 2) - 1, Metrics.color.line)
        local text = UI.text(first_char(profile.nickname), { face = Metrics.title_face() })
        local size = text:getSize()
        text:paintTo(bb, cx - math.floor(size.w / 2), y + math.floor((avatar - size.h) / 2))
        text:free()
    end

    local left = x + pad + avatar + pad

    local name = UI.text(profile.nickname or I18N.T("not_logged_in"), {
        width = math.max(Metrics.dp(60), w - (left - x) - pad * 2),
        bold = true,
    })
    local name_size = name:getSize()
    name:paintTo(bb, left, y + math.floor((avatar - name_size.h) / 2))
    name:free()

    self.hit_rows[#self.hit_rows + 1] = UI.hit_rect(x, y, w, avatar, function()
        require("mybooks_settings_page").show(self.api)
    end)

    local card_w = math.floor((w - pad * 4) / 3)
    local card_h = self:stat_card_h()
    local row1 = y + avatar + Metrics.dp(8)

    local time_cards = {
        {
            label = I18N.T("reading_time"),
            value = Metrics.format_hours(stats.total_seconds or 0),
            unit = I18N.T("unit_hours"),
            hit = function()
                Toast.show(string.format(
                    "%s · %s",
                    I18N.T("today_reading", Metrics.format_duration(stats.today_seconds or 0)),
                    I18N.T("streak_days", streak.current or 0)
                ))
            end,
        },
        {
            label = I18N.T("today"),
            value = Metrics.format_hours(stats.today_seconds or 0),
            unit = I18N.T("unit_hours"),
        },
        {
            label = I18N.T("streak"),
            value = tostring(streak.current or 0),
            unit = I18N.T("unit_days"),
        },
    }
    for index, card in ipairs(time_cards) do
        local cx = x + pad + (index - 1) * (card_w + pad)
        self:_paint_stat_card(bb, cx, row1, card_w, card_h, card.label, card.value, card.unit)
        if card.hit then
            self.hit_rows[#self.hit_rows + 1] = UI.hit_rect(cx, row1, card_w, card_h, card.hit)
        end
    end

    local row2 = row1 + card_h + Metrics.dp(6)
    local status_cards = {
        { label = I18N.T("reading"), value = status.reading or 0, kind = "reading", title = I18N.T("reading_now") },
        { label = I18N.T("finished"), value = status.finished or 0, kind = "read_done", title = I18N.T("my_read") },
        { label = I18N.T("to_read"), value = status.to_read or 0, kind = "wants", title = I18N.T("my_wishlist") },
    }
    for index, card in ipairs(status_cards) do
        local cx = x + pad + (index - 1) * (card_w + pad)
        self:_paint_stat_card(bb, cx, row2, card_w, card_h, card.label, tostring(card.value or 0), nil)
        local kind, title = card.kind, card.title
        self.hit_rows[#self.hit_rows + 1] = UI.hit_rect(cx, row2, card_w, card_h, function()
            self:open_section(kind, title)
        end)
    end

    return self:stats_height()
end

function HomePage:divider_h()
    return Metrics.dp(20)
end

function HomePage:version_height()
    if not self._version_h then
        local text = UI.text(self.version, { face = self.version_face, padding = 0 })
        self._version_h = text:getSize().h
        text:free()
    end
    return self._version_h
end

function HomePage:_paint_divider(bb, x, y, w)
    UI.divider(bb, x + self.pad, y + Metrics.dp(8), w - self.pad * 2)
    return self:divider_h()
end

function HomePage:reading_metrics(w)
    local pad = self.pad
    local card_w = math.floor((w - pad * 4) / 3)
    local cover_h = math.min(math.floor(card_w * 4 / 3), Metrics.dp(220))
    return card_w, cover_h, cover_h + Metrics.dp(40)
end

function HomePage:_paint_reading(bb, x, y, w)
    local pad = self.pad
    local books = self.data.reading_now or {}
    local header_h = Metrics.dp(30)
    local title = UI.text(I18N.T("home_reading"), { bold = true })
    local title_size = title:getSize()
    title:paintTo(bb, x + pad, y + math.floor((header_h - title_size.h) / 2))
    title:free()
    local all = UI.text(I18N.T("view_all") .. " ›", { face = Metrics.small_face(), color = Metrics.color.muted })
    local all_size = all:getSize()
    all:paintTo(bb, x + w - pad - all_size.w, y + math.floor((header_h - all_size.h) / 2))
    all:free()
    self.hit_rows[#self.hit_rows + 1] = UI.hit_rect(x + w - pad - all_size.w - pad, y, all_size.w + pad * 2, header_h, function()
        require("mybooks_browse").show_books(self.api, "reading", nil, I18N.T("reading_now"))
    end)

    if #books == 0 then
        local empty = UI.text(I18N.T("no_reading_now"), { face = Metrics.small_face(), color = Metrics.color.muted })
        empty:paintTo(bb, x + pad, y + header_h)
        empty:free()
        return header_h + Metrics.dp(32)
    end

    local card_w, cover_h, card_h = self:reading_metrics(w)
    local count = math.min(3, #books)
    for index = 1, count do
        local book = books[index]
        local cx = x + pad + (index - 1) * (card_w + pad)
        local cy = y + header_h
        UI.card(bb, cx, cy, card_w, cover_h, { radius = Metrics.dp(3) })
        UI.paint_cover(bb, Thumbnails.get(book), cx, cy, card_w, cover_h)
        local label = UI.text(book.title, {
            face = Metrics.small_face(),
            width = card_w,
            padding = 0,
        })
        label:paintTo(bb, cx, cy + cover_h + Metrics.dp(4))
        label:free()
        local percent = UI.text(Metrics.format_percent(book.progress_percent or 0), {
            face = Metrics.small_face(),
            color = Metrics.color.muted,
            padding = 0,
        })
        percent:paintTo(bb, cx, cy + cover_h + Metrics.dp(22))
        percent:free()
        local rect = UI.hit_rect(cx, cy, card_w, card_h, function()
            self:open_book(book)
        end)
        rect.on_hold = function()
            require("mybooks_browse").book_actions(self.api, book)
        end
        self.hit_rows[#self.hit_rows + 1] = rect
    end
    return header_h + card_h
end

function HomePage:paintContent(bb, x, y)
    local pad = self.pad
    local w = self.dimen.w
    local data = self.data or {}
    self.data = data

    local rows_count = 8
    local cell_h = Panel.height()
    local grid_rows = math.ceil(rows_count / 2)
    local grid_h = grid_rows * cell_h + (grid_rows - 1) * pad
    local _, _, card_h = self:reading_metrics(w)
    local reading_h = Metrics.dp(30) + card_h
    local content_h = pad + self:stats_height() + self:divider_h() + reading_h
        + Metrics.dp(8) + self:divider_h() + Metrics.dp(30) + grid_h
        + self:divider_h() + Metrics.dp(4) + self:version_height() + pad
    self._content_h = content_h
    self.offset = math.min(self.offset, math.max(0, content_h - self.list_h))

    local top = y + pad - self.offset
    top = top + self:_paint_stats(bb, x, top, w)
    top = top + self:_paint_divider(bb, x, top, w)
    top = top + self:_paint_reading(bb, x, top, w)
    top = top + Metrics.dp(8)
    top = top + self:_paint_divider(bb, x, top, w)

    local header_h = Metrics.dp(30)
    local section = UI.text(I18N.T("browse_section"), { bold = true })
    local section_size = section:getSize()
    section:paintTo(bb, x + pad, top + math.floor((header_h - section_size.h) / 2))
    section:free()
    top = top + header_h

    local counts = {}
    for _, item in ipairs(data.sections or {}) do
        counts[item.kind] = item.count
    end

    local rows = {
        { title = I18N.T("search"), icon = SECTION_ICONS.search, action = function()
            require("mybooks_browse").search(self.api)
        end },
    }
    for _, kind in ipairs({ "favorites", "wants", "read_done", "categories", "tags", "authors", "recent" }) do
        local title = I18N.T(SECTION_LABELS[kind])
        rows[#rows + 1] = {
            title = title,
            icon = SECTION_ICONS[kind],
            badge = counts[kind],
            action = function()
                self:open_section(kind, title)
            end,
        }
    end

    local cell_w = Panel.grid_width(w, pad, 2)
    for index, row in ipairs(rows) do
        local column = (index - 1) % 2
        local line = math.floor((index - 1) / 2)
        local cx = x + pad + column * (cell_w + pad)
        local cy = top + line * (cell_h + pad)
        Panel.draw(bb, cx, cy, cell_w, cell_h, { title = row.title, icon = row.icon, badge = row.badge })
        self.hit_rows[#self.hit_rows + 1] = UI.hit_rect(cx, cy, cell_w, cell_h, row.action)
    end

    top = top + grid_h
    top = top + self:_paint_divider(bb, x, top, w)
    local version = UI.text(self.version, {
        face = self.version_face,
        color = Metrics.color.muted,
        padding = 0,
    })
    local version_size = version:getSize()
    version:paintTo(bb, x + math.floor((w - version_size.w) / 2), top + Metrics.dp(4))
    version:free()
end

function HomePage:scroll(delta)
    self.offset = math.min(
        math.max(0, (self._content_h or 0) - self.list_h),
        math.max(0, self.offset + delta * math.floor(self.list_h * 0.75))
    )
    logger.dbg("MyBooks: home scroll", self.offset)
    self:refresh()
end

function HomePage:onSwipeNorth()
    self:scroll(1)
    return true
end

function HomePage:onSwipeSouth()
    self:scroll(-1)
    return true
end

function HomePage:onLeft()
    self:scroll(-1)
    return true
end

function HomePage:onRight()
    self:scroll(1)
    return true
end

function HomePage:onUp()
    self:scroll(-1)
    return true
end

function HomePage:onDown()
    self:scroll(1)
    return true
end

function M.show(api, opts)
    opts = opts or {}
    local page = HomePage:new{
        api = api,
        on_close = opts.on_close,
    }
    UIManager:show(page, "ui")
    local cached = page.data ~= nil
    if not cached then
        Toast.loading(I18N.T("loading"))
    end
    local ok = page:load_home()
    if not cached and ok then
        Toast.dismiss()
    end
    return page
end

return M
