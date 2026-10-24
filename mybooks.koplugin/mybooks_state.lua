local DataStorage = require("datastorage")
local dump = require("dump")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local M = {}

local state_path
local state

local function path()
    if not state_path then
        state_path = DataStorage:getSettingsDir() .. "/mybooks_state.lua"
    end
    return state_path
end

local function default_state()
    return {
        version = 1,
        device_id = nil,
        server_key = nil,
        session = nil,
        home = nil,
        home_ts = 0,
        books = {},
        downloads = {},
        links = {},
        pending_progress = {},
        pending_seconds = {},
        pending_state = {},
        annotation_ack = {},
        annotation_known = {},
        stats_since = {},
        ui = { view_mode = "list" },
    }
end

function M.load()
    if state then
        return state
    end
    state = default_state()
    local file = io.open(path(), "r")
    if file then
        local content = file:read("*a")
        file:close()
        local chunk = loadstring or load
        local fn = chunk(content, "mybooks_state")
        local loaded, data = false, nil
        if fn then
            loaded, data = pcall(fn)
        end
        if loaded and type(data) == "table" then
            for key, value in pairs(data) do
                state[key] = value
            end
            logger.dbg("MyBooks: state loaded from", path())
        else
            logger.warn("MyBooks: state file invalid, backing up")
            pcall(os.rename, path(), path() .. ".corrupt")
        end
    end
    if type(state.books) ~= "table" then state.books = {} end
    if type(state.downloads) ~= "table" then state.downloads = {} end
    if type(state.links) ~= "table" then state.links = {} end
    if type(state.pending_progress) ~= "table" then state.pending_progress = {} end
    if type(state.pending_seconds) ~= "table" then state.pending_seconds = {} end
    if type(state.pending_state) ~= "table" then state.pending_state = {} end
    if type(state.annotation_ack) ~= "table" then state.annotation_ack = {} end
    if type(state.annotation_known) ~= "table" then state.annotation_known = {} end
    if type(state.stats_since) ~= "table" then state.stats_since = {} end
    if type(state.ui) ~= "table" then state.ui = { view_mode = "list" } end
    return state
end

function M.save()
    local data = M.load()
    local ok, text = pcall(dump, data, nil, true)
    if not ok then
        logger.err("MyBooks: state dump failed", text)
        return false
    end
    local target = path()
    local tmp = target .. ".tmp"
    local file, err = io.open(tmp, "w")
    if not file then
        logger.err("MyBooks: cannot write state", err)
        return false
    end
    file:write("return ", text, "\n")
    if ffiUtil.fsyncOpenedFile then
        pcall(ffiUtil.fsyncOpenedFile, file)
    end
    file:close()
    if lfs.attributes(target, "mode") == "file" then
        pcall(os.remove, target .. ".old")
        pcall(os.rename, target, target .. ".old")
    end
    local renamed, rename_err = os.rename(tmp, target)
    if not renamed then
        os.remove(tmp)
        logger.err("MyBooks: state rename failed", rename_err)
        return false
    end
    if ffiUtil.fsyncDirectory then
        pcall(ffiUtil.fsyncDirectory, DataStorage:getSettingsDir())
    end
    return true
end

function M.session()
    return M.load().session
end

function M.set_session(data, server_key)
    local s = M.load()
    s.session = data
    s.server_key = server_key
    s.session_ts = os.time()
    M.save()
    logger.dbg("MyBooks: session cached for", server_key)
end

function M.clear_session()
    local s = M.load()
    s.session = nil
    s.server_key = nil
    M.save()
end

function M.home()
    return M.load().home
end

function M.set_home(data)
    local s = M.load()
    s.home = data
    s.home_ts = os.time()
    M.save()
end

function M.clear_home()
    local s = M.load()
    s.home = nil
    s.home_ts = 0
    M.save()
end

function M.book(book_id)
    local s = M.load()
    return s.books[tostring(book_id)]
end

function M.set_book(book_id, info)
    local s = M.load()
    s.books[tostring(book_id)] = info
    M.save()
end

function M.remove_book(book_id)
    local s = M.load()
    s.books[tostring(book_id)] = nil
    M.save()
end

function M.download(book_id, fmt)
    local s = M.load()
    local per_book = s.downloads[tostring(book_id)]
    if not per_book then
        return nil
    end
    return per_book[tostring(fmt):lower()]
end

function M.set_download(book_id, fmt, local_path, md5)
    local s = M.load()
    local key = tostring(book_id)
    s.downloads[key] = s.downloads[key] or {}
    s.downloads[key][tostring(fmt):lower()] = {
        path = local_path,
        md5 = md5,
        ts = os.time(),
    }
    M.save()
end

function M.setting(key, default)
    local s = M.load()
    local value = s.ui[key]
    if value == nil then
        return default
    end
    return value
end

function M.set_setting(key, value)
    local s = M.load()
    s.ui[key] = value
    M.save()
end

function M.link(file_path)
    if not file_path then
        return nil
    end
    return M.load().links[file_path]
end

function M.set_link(file_path, info)
    if not file_path then
        return
    end
    local s = M.load()
    s.links[file_path] = info
    M.save()
end

function M.remove_link(file_path)
    if not file_path then
        return
    end
    local s = M.load()
    s.links[file_path] = nil
    M.save()
end

function M.links_count()
    local count = 0
    for _ in pairs(M.load().links) do
        count = count + 1
    end
    return count
end

function M.link_by_md5(md5)
    if not md5 then
        return nil
    end
    for file_path, info in pairs(M.load().links) do
        if info.md5 == md5 then
            return info, file_path
        end
    end
    return nil
end

function M.pending(key)
    return M.load().pending_progress[key]
end

function M.set_pending(key, payload)
    local s = M.load()
    s.pending_progress[key] = payload
    M.save()
end

function M.clear_pending(key)
    local s = M.load()
    s.pending_progress[key] = nil
    M.save()
end

function M.pending_keys()
    local keys = {}
    for key in pairs(M.load().pending_progress) do
        keys[#keys + 1] = key
    end
    return keys
end

function M.pending_seconds(md5)
    if not md5 then
        return nil
    end
    return M.load().pending_seconds[md5]
end

function M.set_pending_seconds(md5, bucket)
    if not md5 then
        return
    end
    local s = M.load()
    s.pending_seconds[md5] = bucket
    M.save()
end

function M.clear_pending_seconds(md5)
    if not md5 then
        return
    end
    local s = M.load()
    local bucket = s.pending_seconds[md5]
    if bucket and bucket.date == os.date("%Y-%m-%d") then
        bucket.seconds = 0
    else
        s.pending_seconds[md5] = nil
    end
    M.save()
end

function M.pending_seconds_keys()
    local keys = {}
    for key in pairs(M.load().pending_seconds) do
        keys[#keys + 1] = key
    end
    return keys
end

function M.pending_state(key)
    return M.load().pending_state[key]
end

function M.set_pending_state(key, payload)
    local s = M.load()
    s.pending_state[key] = payload
    M.save()
end

function M.clear_pending_state(key)
    local s = M.load()
    s.pending_state[key] = nil
    M.save()
end

function M.annotation_known(book_key)
    return M.load().annotation_known[book_key] or {}
end

function M.set_annotation_known(book_key, known)
    local s = M.load()
    s.annotation_known[book_key] = known
    M.save()
end

function M.annotation_ack(key)
    return M.load().annotation_ack[key]
end

function M.set_annotation_ack(key, ack)
    local s = M.load()
    s.annotation_ack[key] = ack
    M.save()
end

function M.stats_watermarks()
    local marks = {}
    for md5, timestamp in pairs(M.load().stats_since) do
        marks[md5] = tonumber(timestamp) or 0
    end
    return marks
end

function M.set_stats_watermarks(marks)
    local s = M.load()
    for md5, timestamp in pairs(marks or {}) do
        s.stats_since[md5] = tonumber(timestamp) or 0
    end
    M.save()
end

function M.device_id()
    local s = M.load()
    if not s.device_id then
        local seed = tostring(os.time()) .. tostring(math.random(100000, 999999))
        s.device_id = string.format("%08x%s", os.time(), seed:sub(-6))
        M.save()
    end
    return s.device_id
end

function M.size()
    local attr = lfs.attributes(path())
    return attr and attr.size or 0
end

function M.credentials()
    local ok, saved = pcall(function()
        return G_reader_settings:readSetting("mybooks")
    end)
    if ok and type(saved) == "table" then
        return saved
    end
    return {}
end

function M.save_credentials(cred)
    local data = M.credentials()
    for key, value in pairs(cred or {}) do
        data[key] = value
    end
    G_reader_settings:saveSetting("mybooks", data)
    logger.dbg("MyBooks: credentials saved", data.server_url)
    return data
end

function M.clear_credentials()
    pcall(function() G_reader_settings:delSetting("mybooks") end)
end

function M.api()
    local Api = require("mybooks_api")
    local cred = M.credentials()
    if not cred.server_url or cred.server_url == "" then
        return nil
    end
    return Api.new{
        server_url = cred.server_url,
        username = cred.username or "",
        password = cred.password or "",
        device_id = M.device_id(),
    }
end

return M
