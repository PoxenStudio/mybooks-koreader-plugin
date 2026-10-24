local lfs = require("libs/libkoreader-lfs")

local DeviceInfo = require("mybooks_device")

local M = {}

local MAX_CACHE_FILES = 500

function M.path(book_id, fmt)
    return DeviceInfo.cache_dir() .. "/" .. tostring(book_id) .. "_" .. tostring(fmt or "jpg") .. ".jpg"
end

function M.get(book)
    if not book or not book.id then
        return nil
    end
    local path = M.path(book.id)
    if DeviceInfo.file_exists(path) then
        return path
    end
    return nil
end

function M.fetch(api, book)
    if not book or not book.id then
        return nil
    end
    local existing = M.get(book)
    if existing then
        return existing
    end
    local url = book.thumb or book.img
    if not url or url == "" then
        return nil
    end
    url = api:resolve(url)
    if not url then
        return nil
    end
    local path = M.path(book.id)
    local part = path .. ".part"
    local saved = api:fetch_file(url, part)
    if not saved then
        return nil
    end
    local renamed = os.rename(part, path)
    if not renamed then
        pcall(os.remove, part)
        return nil
    end
    M.prune()
    return path
end

function M.prefetch(api, books, limit)
    limit = limit or 8
    local count = 0
    for _, book in ipairs(books or {}) do
        if count >= limit then
            break
        end
        if book.id and not M.get(book) and (book.thumb or book.img) then
            M.fetch(api, book)
            count = count + 1
        end
    end
    return count
end

function M.prune(max_files)
    max_files = max_files or MAX_CACHE_FILES
    local dir = DeviceInfo.cache_dir()
    local entries = {}
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            local attr = lfs.attributes(dir .. "/" .. name)
            if attr and attr.mode == "file" then
                entries[#entries + 1] = { path = dir .. "/" .. name, ts = attr.modification or 0 }
            end
        end
    end
    if #entries <= max_files then
        return 0
    end
    table.sort(entries, function(a, b) return a.ts < b.ts end)
    local removed = 0
    for index = 1, #entries - max_files do
        pcall(os.remove, entries[index].path)
        removed = removed + 1
    end
    return removed
end

function M.clear()
    local dir = DeviceInfo.cache_dir()
    local removed = 0
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            pcall(os.remove, dir .. "/" .. name)
            removed = removed + 1
        end
    end
    return removed
end

return M
