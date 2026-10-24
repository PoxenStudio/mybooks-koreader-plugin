local socketurl = require("socket.url")
local logger = require("logger")
local UIManager = require("ui/uimanager")

local I18N = require("mybooks_i18n")
local ListView = require("mybooks_list_view")
local MenuUI = require("mybooks_menu_ui")
local Metrics = require("mybooks_metrics")
local Page = require("mybooks_page")
local State = require("mybooks_state")
local TextEntry = require("mybooks_text_entry")
local Toast = require("mybooks_toast")

local M = {}

local BOOK_ENDPOINTS = {
    favorites = { path = "/api/favorites", title = "my_favorites" },
    wants = { path = "/api/wants", title = "my_wishlist" },
    read_done = { path = "/api/read-done", title = "my_read" },
    reading = { path = "/api/reading", title = "reading_now" },
    recent = { path = "/api/recent", title = "latest" },
}

local function merge_states(api, books)
    if #books == 0 then
        return
    end
    local ids = {}
    for _, book in ipairs(books) do
        ids[#ids + 1] = book.id
    end
    local data, err = api:get("/states", { ids = table.concat(ids, ",") })
    if err or not data or not data.states then
        logger.dbg("MyBooks: states merge skipped", err)
        return
    end
    for _, book in ipairs(books) do
        local state = data.states[tostring(book.id)]
        if state then
            book.progress_percent = state.progress_percent
            book.total_seconds = state.total_seconds
            book.read_state = state.read_state
            book.formats = state.formats
        end
    end
end

function M.fetch_books(api, kind, page_no, size, name)
    local start = (page_no - 1) * size
    local params = { start = start, size = size }
    local path
    if BOOK_ENDPOINTS[kind] then
        path = BOOK_ENDPOINTS[kind].path
    elseif kind == "tag" or kind == "author" then
        path = "/api/" .. kind .. "/" .. socketurl.escape(name or "")
        params.sort = "title"
    elseif kind == "category" then
        path = "/api/koreader/search"
        params.q = "#category:=\"" .. tostring(name or "") .. "\""
        params.order = "title"
    elseif kind == "search" then
        path = "/api/koreader/search"
        params.q = name or ""
        params.order = "title"
    else
        return {}, 0, "params"
    end
    local rsp, err = api:get_abs(path, params)
    if err then
        logger.warn("MyBooks: fetch books failed", kind, err)
        return nil, nil, err
    end
    local books = rsp.books or {}
    merge_states(api, books)
    return books, rsp.total or #books, nil
end

local function open_detail(api, book)
    require("mybooks_detail").show(api, book)
end

function M.show_books(api, kind, name, title, on_close)
    local mode = State.setting("view_mode", "list")
    local page
    local function open(book)
        open_detail(api, book)
    end
    page = ListView.show{
        api = api,
        title = title,
        mode = mode,
        on_close = on_close,
        fetch = function(page_no, size)
            return M.fetch_books(api, kind, page_no, size, name)
        end,
        on_book = open,
        on_hold = function(book)
            M.book_actions(api, book)
        end,
        header_buttons = {
            {
                text = "≡",
                hit = function()
                    local next_mode = State.setting("view_mode", "list") == "list" and "grid" or "list"
                    State.set_setting("view_mode", next_mode)
                    page:close()
                    M.show_books(api, kind, name, title, on_close)
                end,
            },
        },
    }
    return page
end

function M.show_meta(api, meta, on_close)
    local path, title_key
    if meta == "category" then
        path, title_key = "/api/categories", "categories"
    elseif meta == "tag" then
        path, title_key = "/api/tag", "tags"
    elseif meta == "author" then
        path, title_key = "/api/author", "authors"
    else
        return nil
    end
    Toast.loading(I18N.T("loading"))
    local rsp, err = api:get_abs(path)
    Toast.dismiss()
    if err then
        Toast.error(ListView.error_text(err))
        return nil
    end
    local items
    if meta == "category" then
        items = rsp.categories or {}
    else
        items = rsp.items or {}
    end
    logger.dbg("MyBooks: meta list", meta, #items)

    local page = Page:new{
        title = I18N.T(title_key),
        on_close = on_close,
    }
    local chunk = 200
    local next_index = 1
    local rows = {}
    local function build()
        if #rows > 0 and rows[#rows].is_load_more then
            rows[#rows] = nil
        end
        local last = math.min(#items, next_index + chunk - 1)
        for index = next_index, last do
            local item = items[index]
            rows[#rows + 1] = MenuUI.meta_row(item.name, item.count, {
                hit = function()
                    local name = tostring(item.name)
                    M.show_books(api, meta, name, name, on_close)
                end,
            })
        end
        next_index = last + 1
        if #rows == 0 then
            rows[#rows + 1] = MenuUI.header(I18N.T(meta == "category" and "no_categories" or (meta == "tag" and "no_tags" or "no_authors")))
        end
        if next_index <= #items then
            local more = MenuUI.icon_row(nil, I18N.T("load_more"), nil, {
                hit = function()
                    page:set_items(build(), false)
                    page:scroll_to_end()
                end,
            })
            more.is_load_more = true
            rows[#rows + 1] = more
        end
        return rows
    end
    page:set_items(build(), true)
    UIManager:show(page, "ui")
    return page
end

function M.book_actions(api, book)
    local Detail = require("mybooks_detail")
    local Download = require("mybooks_download")
    local Sync = require("mybooks_sync")
    local dialog
    local function current_state()
        local rsp, err = api:get("/states", { ids = tostring(book.id) })
        if rsp and not err and rsp.states then
            return rsp.states[tostring(book.id)] or {}
        end
        return {}
    end
    local function toggle(key, value)
        local changes = {}
        changes[key] = value
        local rsp = Sync.push_state(api, { book_id = book.id, format = "epub" }, changes)
        if not rsp then
            Toast.error(ListView.error_text("network"))
        end
    end
    local state = current_state()
    local buttons = {
        {
            {
                text = I18N.T("details"),
                callback = function()
                    UIManager:close(dialog)
                    Detail.show(api, book)
                end,
            },
        },
        {
            {
                text = I18N.T("download"),
                callback = function()
                    UIManager:close(dialog)
                    Download.start(api, book)
                end,
            },
        },
        {
            {
                text = I18N.T(state.favorite and "unfavorite" or "favorite"),
                callback = function()
                    UIManager:close(dialog)
                    toggle("favorite", not state.favorite)
                end,
            },
            {
                text = I18N.T(state.wants and "unwant" or "to_read"),
                callback = function()
                    UIManager:close(dialog)
                    toggle("wants", not state.wants)
                end,
            },
        },
        {
            {
                text = I18N.T(state.read_state == 2 and "mark_unread" or "mark_read"),
                callback = function()
                    UIManager:close(dialog)
                    toggle("read_state", state.read_state == 2 and 0 or 2)
                end,
            },
        },
    }
    local local_path = M.local_path(book)
    if local_path then
        buttons[#buttons + 1] = {
            {
                text = I18N.T("open"),
                callback = function()
                    UIManager:close(dialog)
                    Download.open_file(local_path)
                end,
            },
        }
    end
    dialog = require("ui/widget/buttondialog"):new{
        title = book.title,
        buttons = buttons,
        width = Metrics.dp(520),
    }
    UIManager:show(dialog)
    return dialog
end

function M.local_path(book)
    local Download = require("mybooks_download")
    return Download.local_path(book)
end

function M.search(api)
    TextEntry.input{
        title = I18N.T("search"),
        hint = I18N.T("search_hint"),
        on_save = function(keyword)
            keyword = tostring(keyword or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if keyword == "" then
                Toast.show(I18N.T("enter_keyword"))
                return
            end
            M.show_books(api, "search", keyword, I18N.T("search") .. ": " .. keyword)
        end,
    }
end

function M.show_tree(api, on_close)
    local home = State.home()
    local counts = {}
    if home and home.sections then
        for _, section in ipairs(home.sections) do
            counts[section.kind] = section.count
        end
    end
    local page
    local rows = {
        MenuUI.icon_row(nil, I18N.T("search"), nil, {
            hit = function()
                M.search(api)
            end,
        }),
        MenuUI.header(I18N.T("browse")),
        MenuUI.icon_row(nil, I18N.T("my_favorites"), counts.favorites, {
            hit = function() M.show_books(api, "favorites", nil, I18N.T("my_favorites")) end,
        }),
        MenuUI.icon_row(nil, I18N.T("my_wishlist"), counts.wants, {
            hit = function() M.show_books(api, "wants", nil, I18N.T("my_wishlist")) end,
        }),
        MenuUI.icon_row(nil, I18N.T("my_read"), counts.read_done, {
            hit = function() M.show_books(api, "read_done", nil, I18N.T("my_read")) end,
        }),
        MenuUI.icon_row(nil, I18N.T("categories"), counts.categories, {
            hit = function() M.show_meta(api, "category") end,
        }),
        MenuUI.icon_row(nil, I18N.T("tags"), counts.tags, {
            hit = function() M.show_meta(api, "tag") end,
        }),
        MenuUI.icon_row(nil, I18N.T("authors"), counts.authors, {
            hit = function() M.show_meta(api, "author") end,
        }),
        MenuUI.icon_row(nil, I18N.T("latest"), nil, {
            hit = function() M.show_books(api, "recent", nil, I18N.T("latest")) end,
        }),
    }
    page = Page:new{
        title = I18N.T("browse"),
        items = rows,
        on_close = on_close,
    }
    UIManager:show(page, "ui")
    return page
end

return M
