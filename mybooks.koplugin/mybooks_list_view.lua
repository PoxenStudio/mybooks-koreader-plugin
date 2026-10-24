local UIManager = require("ui/uimanager")
local logger = require("logger")

local I18N = require("mybooks_i18n")
local MenuUI = require("mybooks_menu_ui")
local Metrics = require("mybooks_metrics")
local Page = require("mybooks_page")
local Thumbnails = require("mybooks_thumbnails")
local Toast = require("mybooks_toast")

local M = {}

local ERROR_ALIAS = {
    ["user.need_login"] = "err_auth",
    ["koreader.disabled"] = "err_disabled",
}

function M.error_text(err)
    err = tostring(err)
    local key = ERROR_ALIAS[err] or ("err_" .. err)
    local text = I18N.T(key)
    if text == key then
        return err
    end
    return text
end

function M.capacity()
    return 8
end

function M.show(opts)
    opts = opts or {}
    local api = opts.api
    local mode = opts.mode or "list"
    local page = Page:new{
        title = opts.title or "",
        mode = mode,
        on_close = opts.on_close,
    }
    page.list_h = page.dimen.h - page.header_h - page.footer_h
    local state = { page_no = opts.page or 1, total = 0, pages = 1, loading = false }
    local size = opts.size or M.capacity()
    if mode == "grid" then
        page.grid_rows = math.ceil(size / 2)
    else
        page.row_h = math.max(Metrics.dp(32), math.floor(page.list_h / size))
    end

    local function build_items(books)
        local items = {}
        for _, book in ipairs(books) do
            local image = Thumbnails.get(book)
            items[#items + 1] = MenuUI.book_row(book, {
                image = image,
                hit = function()
                    if opts.on_book then
                        opts.on_book(book)
                    end
                end,
                on_hold = function()
                    if opts.on_hold then
                        opts.on_hold(book)
                    end
                end,
            })
        end
        if #items == 0 then
            items[1] = MenuUI.space(Metrics.dp(24))
            items[2] = MenuUI.header(I18N.T(opts.empty_key or "no_books"))
        end
        return items
    end

    local load
    load = function(page_no)
        if state.loading then
            return false
        end
        state.loading = true
        logger.dbg("MyBooks: list load page", page_no, "size", size)
        Toast.loading(I18N.T("loading"))
        local books, total, err = opts.fetch(page_no, size)
        Toast.dismiss()
        state.loading = false
        if err then
            Toast.error(M.error_text(err))
            return false
        end
        state.total = total or #books
        state.pages = math.max(1, math.ceil(state.total / size))
        if page_no > state.pages then
            page_no = state.pages
        end
        state.page_no = page_no
        page.pager = { page = state.page_no, pages = state.pages }
        Thumbnails.prefetch(api, books, 8)
        page:set_items(build_items(books), true)
        UIManager:setDirty(page, "ui")
        UIManager:forceRePaint()
        return true
    end

    page.footer_buttons = {
        {
            text = "‹",
            face = Metrics.title_face(),
            hit = function()
                if state.page_no <= 1 then
                    Toast.show(I18N.T("first_page"))
                else
                    load(state.page_no - 1)
                end
            end,
        },
        {
            text = "↻",
            face = Metrics.title_face(),
            hit = function()
                load(state.page_no)
            end,
        },
        {
            text = "›",
            face = Metrics.title_face(),
            hit = function()
                if state.page_no >= state.pages then
                    Toast.show(I18N.T("last_page"))
                else
                    load(state.page_no + 1)
                end
            end,
        },
    }
    page.header_buttons = opts.header_buttons or {}

    UIManager:show(page, "ui")
    load(state.page_no)
    return page, load
end

return M
