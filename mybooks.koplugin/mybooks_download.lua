local UIManager = require("ui/uimanager")
local logger = require("logger")

local DeviceInfo = require("mybooks_device")
local DialogUI = require("mybooks_dialog_ui")
local I18N = require("mybooks_i18n")
local ListView = require("mybooks_list_view")
local State = require("mybooks_state")
local Toast = require("mybooks_toast")

local M = {}

local function dedupe(formats)
    local seen = {}
    local list = {}
    for _, fmt in ipairs(formats) do
        fmt = tostring(fmt or ""):lower()
        if fmt ~= "" and not seen[fmt] then
            seen[fmt] = true
            list[#list + 1] = fmt
        end
    end
    return list
end

local function formats_of(book)
    local formats = {}
    for _, file in ipairs(book.files or {}) do
        formats[#formats + 1] = file.format
    end
    for _, fmt in ipairs(book.formats or {}) do
        formats[#formats + 1] = fmt
    end
    return dedupe(formats)
end

function M.local_path(book)
    if not book or not book.id then
        return nil
    end
    local saved = State.load().downloads[tostring(book.id)]
    if type(saved) ~= "table" then
        return nil
    end
    local preferred = tostring(State.setting("default_format", "epub")):lower()
    local first = saved[preferred]
    if type(first) == "table" and first.path and DeviceInfo.file_exists(first.path) then
        return first.path, preferred
    end
    local keys = {}
    for fmt in pairs(saved) do
        keys[#keys + 1] = fmt
    end
    table.sort(keys)
    for _, fmt in ipairs(keys) do
        local item = saved[fmt]
        if type(item) == "table" and item.path and DeviceInfo.file_exists(item.path) then
            return item.path, fmt
        end
    end
    return nil
end

function M.open_file(path)
    if not DeviceInfo.file_exists(path) then
        Toast.error(I18N.T("no_local_file"))
        return
    end
    logger.dbg("MyBooks: open file", path)
    require("mybooks_page").close_all()
    local ReaderUI = require("apps/reader/readerui")
    UIManager:nextTick(function()
        ReaderUI:showReader(path)
    end)
end

local function path_owner(path)
    local downloads = State.load().downloads
    for book_id, formats in pairs(downloads) do
        for _, item in pairs(formats) do
            if type(item) == "table" and item.path == path then
                return book_id
            end
        end
    end
    return nil
end

local function size_of(book, fmt)
    for _, file in ipairs(book.files or {}) do
        if tostring(file.format or ""):lower() == fmt then
            return tonumber(file.size)
        end
    end
    return nil
end

local function md5_of(path)
    local util = require("util")
    if type(util.partialMD5) ~= "function" then
        return nil
    end
    local ok, digest = pcall(util.partialMD5, path)
    if ok then
        return digest
    end
    return nil
end

local function remember(book, fmt, path)
    local md5 = md5_of(path)
    local existing = State.link(path)
    State.set_download(book.id, fmt, path, md5)
    State.set_book(book.id, {
        title = book.title,
        author = book.author,
        img = book.img,
        thumb = book.thumb,
        formats = formats_of(book),
    })
    State.set_link(path, {
        book_id = book.id,
        format = fmt,
        title = book.title,
        author = book.author,
        md5 = md5,
        path = path,
        pushed_at = existing and existing.pushed_at or 0,
    })
end

local function download(api, book, fmt, expected)
    local dir = DeviceInfo.download_dir()
    DeviceInfo.ensure_dir(dir)
    local title = book.title or ("book_" .. tostring(book.id))
    local path = dir .. "/" .. DeviceInfo.safe_filename(title) .. "." .. fmt
    local owner = path_owner(path)
    if owner and owner ~= tostring(book.id) then
        path = dir .. "/" .. DeviceInfo.safe_filename(title .. " (" .. tostring(book.id) .. ")") .. "." .. fmt
    end
    local part = path .. ".part"

    local function proceed()
        logger.dbg("MyBooks: start download", book.id, fmt, path)
        local last = -1
        local last_bytes = 0
        local function progress(received, total)
            if total and total > 0 then
                local percent = math.floor(received * 100 / total)
                if percent >= last + 5 then
                    last = percent
                    Toast.loading(I18N.T("download_progress", math.min(100, percent)))
                end
            elseif received >= last_bytes + 524288 then
                last_bytes = received
                Toast.loading(I18N.T("downloading", title))
            end
        end
        Toast.loading(I18N.T("downloading", title))
        local saved, err = api:download(book.id, fmt, path, part, progress, true, expected)
        Toast.dismiss()
        if err then
            logger.warn("MyBooks: download failed", book.id, fmt, err)
            Toast.error(I18N.T("download_failed", ListView.error_text(err)))
            return
        end
        remember(book, fmt, saved)
        Toast.show(I18N.T("download_done"))
        if State.setting("auto_open", true) then
            M.open_file(saved)
        end
    end

    if DeviceInfo.file_exists(path) then
        remember(book, fmt, path)
        M.open_file(path)
        return
    end
    proceed()
end

function M.start(api, book, preferred_fmt)
    if not book or not book.id then
        return
    end
    local formats = formats_of(book)
    if #formats == 0 then
        Toast.loading(I18N.T("loading"))
        local rsp, err = api:get_abs("/api/book/" .. tostring(book.id), { track = "0" })
        Toast.dismiss()
        if err or not rsp or not rsp.book then
            Toast.error(ListView.error_text(err or "json"))
            return
        end
        book = rsp.book
        formats = formats_of(book)
    end
    if #formats == 0 then
        Toast.show(I18N.T("no_format"))
        return
    end

    local default = tostring(State.setting("default_format", "epub")):lower()
    table.sort(formats, function(a, b)
        if a == b then
            return false
        end
        if a == default then
            return true
        end
        if b == default then
            return false
        end
        return a < b
    end)

    if preferred_fmt then
        local target = tostring(preferred_fmt):lower()
        for _, fmt in ipairs(formats) do
            if fmt == target then
                download(api, book, fmt, size_of(book, fmt))
                return
            end
        end
    end

    if #formats == 1 then
        download(api, book, formats[1], size_of(book, formats[1]))
        return
    end

    local options = {}
    for _, fmt in ipairs(formats) do
        options[#options + 1] = { text = fmt:upper(), value = fmt }
    end
    DialogUI.choose(I18N.T("choose_format"), options, function(fmt)
        download(api, book, fmt, size_of(book, fmt))
    end)
end

return M
