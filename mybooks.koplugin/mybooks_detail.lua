local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local I18N = require("mybooks_i18n")
local ListView = require("mybooks_list_view")
local MenuUI = require("mybooks_menu_ui")
local Metrics = require("mybooks_metrics")
local Page = require("mybooks_page")
local State = require("mybooks_state")
local Thumbnails = require("mybooks_thumbnails")
local Toast = require("mybooks_toast")
local UI = require("mybooks_ui")

local M = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

local function utf8_char(code)
    if code < 128 then
        return string.char(code)
    end
    if code < 2048 then
        return string.char(192 + math.floor(code / 64), 128 + code % 64)
    end
    if code < 65536 then
        return string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64)
    end
    return "?"
end

local function entity(name)
    local mapped = ENTITIES[name]
    if mapped then
        return mapped
    end
    local decimal = name:match("^#(%d+)$")
    if decimal then
        return utf8_char(tonumber(decimal))
    end
    local hex = name:match("^#[xX](%x+)$")
    if hex then
        return utf8_char(tonumber(hex, 16))
    end
    return "&" .. name .. ";"
end

local function plain_text(html)
    html = tostring(html or "")
    html = html:gsub("<[Bb][Rr]%s*/?>", "\n")
    html = html:gsub("</[Pp]>", "\n")
    html = html:gsub("<[^>]+>", "")
    html = html:gsub("&(#?%w+);", entity)
    html = html:gsub("[ \t]+", " ")
    html = html:gsub("\n\n+", "\n\n")
    return (html:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function as_text(value)
    if type(value) == "table" then
        local parts = {}
        for _, item in ipairs(value) do
            parts[#parts + 1] = tostring(item)
        end
        return table.concat(parts, " / ")
    end
    return value
end

function M.show(api, book)
    if not book or not book.id then
        return nil
    end
    Toast.loading(I18N.T("loading"))
    local rsp, err = api:get_abs("/api/book/" .. tostring(book.id), { track = "0" })
    Toast.dismiss()
    if err or not rsp or not rsp.book then
        Toast.error(ListView.error_text(err or "json"))
        return nil
    end
    local detail = rsp.book
    local files = detail.files or {}
    local formats = {}
    for _, file in ipairs(files) do
        formats[#formats + 1] = tostring(file.format or ""):upper()
    end
    State.set_book(detail.id, {
        title = detail.title,
        author = detail.author,
        img = detail.img,
        thumb = detail.thumb,
        formats = formats,
    })
    logger.dbg("MyBooks: detail loaded", detail.id, #files)

    local page
    local description = plain_text(detail.comments)

    local function build()
        local rows = {
            {
                kind = "row",
                title = detail.title,
                sub = detail.author,
                sub_face = Metrics.meta_face(),
                image = Thumbnails.get(detail) or Thumbnails.get(book),
                h = Metrics.dp(164),
            },
        }
        local stats = detail.reading_stats or {}
        local multi_format = #formats > 1
        if #stats > 0 then
            rows[#rows + 1] = MenuUI.header(I18N.T("reading_stats"))
            local lines = {}
            for _, item in ipairs(stats) do
                local finished = tonumber(item.state) == 1
                local percent = finished and 100 or tonumber(item.progress_percent)
                local parts = { Metrics.format_duration(item.total_seconds or 0) }
                local stamp = finished and item.finish_time or item.start_time
                if stamp and stamp ~= "" then
                    parts[#parts + 1] = I18N.T(finished and "finished_on" or "started_on", stamp:sub(1, 10))
                end
                if percent then
                    parts[#parts + 1] = Metrics.format_percent(percent)
                end
                local line = table.concat(parts, " · ")
                if multi_format then
                    line = TextBoxWidget.PTF_BOLD_START .. tostring(item.format or ""):upper()
                        .. TextBoxWidget.PTF_BOLD_END .. " : " .. line
                end
                lines[#lines + 1] = line
            end
            local text = TextBoxWidget.PTF_HEADER .. table.concat(lines, "\n")
            local width = Metrics.screen_size() - Metrics.dp(8) * 2
            rows[#rows + 1] = {
                kind = "text",
                text = text,
                face = Metrics.meta_face(),
                color = Metrics.color.text,
                h = UI.text_height(text, Metrics.meta_face(), width) + Metrics.dp(4),
            }
        end

        local state = detail.state or {}
        local status = {}
        if state.favorite == true or state.favorite == 1 then
            status[#status + 1] = I18N.T("favorite")
        end
        if state.wants == true or state.wants == 1 then
            status[#status + 1] = I18N.T("to_read")
        end
        if state.read_state == 1 then
            status[#status + 1] = I18N.T("reading")
        elseif state.read_state == 2 then
            status[#status + 1] = I18N.T("finished")
        end

        local meta = {}
        local function add_meta(label, value)
            if value == nil or value == "" then
                return
            end
            meta[#meta + 1] = TextBoxWidget.PTF_BOLD_START .. I18N.T(label) .. TextBoxWidget.PTF_BOLD_END
                .. " : " .. tostring(as_text(value))
        end
        if #status > 0 then
            add_meta("status", table.concat(status, " · "))
        end
        local series = detail.series
        if series and series ~= "" then
            if detail.series_index then
                series = string.format("%s #%s", series, detail.series_index)
            end
            add_meta("series", series)
        end
        if detail.rating and tonumber(detail.rating) and tonumber(detail.rating) > 0 then
            add_meta("rating", string.format("%d/10", tonumber(detail.rating)))
        end
        add_meta("tags", detail.tag)
        add_meta("publisher", detail.publisher)
        add_meta("published", detail.pubdate)
        add_meta("isbn", detail.isbn)
        add_meta("language", detail.languages)
        if multi_format and #stats == 0 then
            add_meta("formats", table.concat(formats, " / "))
        end

        if #meta > 0 then
            local text = TextBoxWidget.PTF_HEADER .. table.concat(meta, "\n")
            local screen_w = Metrics.screen_size()
            local width = screen_w - Metrics.dp(8) * 2
            rows[#rows + 1] = {
                kind = "text",
                text = text,
                face = Metrics.meta_face(),
                color = Metrics.color.text,
                h = UI.text_height(text, Metrics.meta_face(), width) + Metrics.dp(4),
            }
        end

        local desc_text = description ~= "" and description or I18N.T("description_empty")
        rows[#rows + 1] = {
            kind = "text",
            text = desc_text,
            h = UI.text_height(desc_text, Metrics.body_face(), Metrics.screen_size() - Metrics.dp(8) * 2),
        }
        return rows
    end

    page = Page:new{
        title = detail.title or "",
        items = build(),
        footer_button_rows = 2,
    }
    local function is_on(key)
        local value = (detail.state or {})[key]
        return value == true or value == 1
    end
    local function refresh_footer()
        local buttons = page.footer_buttons
        buttons[1].text = I18N.T(is_on("favorite") and "unfavorite" or "favorite")
        buttons[2].text = I18N.T(is_on("wants") and "unwant" or "to_read")
        buttons[3].text = I18N.T((detail.state or {}).read_state == 2 and "mark_unread" or "mark_read")
    end
    local function apply_state(changes)
        local Sync = require("mybooks_sync")
        local result = Sync.push_state(api, { book_id = detail.id, format = "epub" }, changes)
        if result and result.state then
            detail.state = result.state
            refresh_footer()
            page:set_items(build(), false)
        else
            Toast.error(I18N.T("err_network"))
        end
    end
    page.footer_buttons = {
        {
            text = I18N.T(is_on("favorite") and "unfavorite" or "favorite"),
            icon = "favorites",
            hit = function()
                apply_state({ favorite = not is_on("favorite") })
            end,
        },
        {
            text = I18N.T(is_on("wants") and "unwant" or "to_read"),
            icon = "wants",
            hit = function()
                apply_state({ wants = not is_on("wants") })
            end,
        },
        {
            text = I18N.T((detail.state or {}).read_state == 2 and "mark_unread" or "mark_read"),
            icon = "read_done",
            hit = function()
                local finished = (detail.state or {}).read_state == 2
                apply_state({ read_state = finished and 0 or 2 })
            end,
        },
        {
            text = I18N.T("download"),
            icon = "download",
            hit = function()
                require("mybooks_download").start(api, detail)
            end,
        },
        {
            text = I18N.T("read"),
            icon = "read",
            hit = function()
                local Download = require("mybooks_download")
                local path = Download.local_path(detail)
                if path then
                    Download.open_file(path)
                else
                    Toast.show(I18N.T("no_local_file"))
                end
            end,
        },
    }
    UIManager:show(page, "ui")
    return page
end

return M
