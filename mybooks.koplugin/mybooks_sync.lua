local UIManager = require("ui/uimanager")
local logger = require("logger")

local Annotations = require("mybooks_annotations")
local Progress = require("mybooks_progress")
local State = require("mybooks_state")
local StatsReader = require("mybooks_stats_reader")
local Toast = require("mybooks_toast")

local M = {}

local MAX_SECONDS_BATCH = 200
local SECONDS_FINALIZE_DELAY = 60
local STATS_LOOKBACK = 300

local function tz_offset()
    local sign, hours, minutes = tostring(os.date("%z")):match("([+-])(%d%d)(%d%d)")
    if not sign then
        return 0
    end
    local value = tonumber(hours) * 3600 + tonumber(minutes) * 60
    return sign == "-" and -value or value
end

function M.book_key(link)
    return tostring(link.book_id) .. ":" .. tostring(link.format or "epub")
end

local book_key = M.book_key

function M.link_for_ui(ui)
    if not ui or not ui.document or not ui.document.file then
        return nil
    end
    local link = State.link(ui.document.file)
    if not link then
        link = M.adopt_download(ui.document.file)
    end
    if not link or not link.book_id then
        logger.dbg("MyBooks: no link for", ui.document.file)
        return nil
    end
    return link
end

function M.adopt_download(file_path)
    for book_id, formats in pairs(State.load().downloads or {}) do
        for fmt, item in pairs(formats) do
            if type(item) == "table" and item.path == file_path then
                local book = State.book(book_id) or {}
                local info = {
                    book_id = tonumber(book_id),
                    format = fmt,
                    title = book.title,
                    author = book.author,
                    md5 = item.md5,
                    path = file_path,
                    pushed_at = 0,
                }
                State.set_link(file_path, info)
                logger.dbg("MyBooks: adopted download", file_path, book_id)
                return info
            end
        end
    end
    return nil
end

local function ensure_watermark(link)
    local marks = State.stats_watermarks()
    if link and link.md5 and not marks[link.md5] then
        local now = os.time() - STATS_LOOKBACK
        State.set_stats_watermarks({ [link.md5] = now })
        marks[link.md5] = now
        logger.dbg("MyBooks: stats watermark init", link.md5, now)
    end
    return marks
end

local function collect_pending()
    local remote = {}
    for _, key in ipairs(State.pending_seconds_keys()) do
        local bucket = State.pending_seconds(key)
        if type(bucket) == "table" and bucket.md5 then
            local linked = State.link_by_md5(bucket.md5)
            local seconds = tonumber(bucket.seconds) or 0
            if linked and seconds > 0 then
                remote[#remote + 1] = {
                    key = key,
                    book_id = linked.book_id,
                    format = linked.format or "epub",
                    date = bucket.date or os.date("%Y-%m-%d"),
                    seconds = math.floor(seconds),
                    seq = tonumber(bucket.total) or 0,
                }
            end
        end
    end
    return remote
end

function M.collect_seconds(link)
    if not State.setting("sync_reading_seconds", true) then
        return nil
    end
    local marks = ensure_watermark(link)
    local floor
    for _, timestamp in pairs(marks) do
        floor = floor and math.min(floor, timestamp) or timestamp
    end
    if floor then
        local entries, updates = StatsReader.entries(marks, floor, tz_offset(), os.time() - SECONDS_FINALIZE_DELAY)
        if updates then
            State.set_stats_watermarks(updates)
        end
        for _, entry in ipairs(entries or {}) do
            local key = entry.md5 .. "|" .. entry.date
            local bucket = State.pending_seconds(key) or { md5 = entry.md5, date = entry.date, seconds = 0, total = 0 }
            bucket.seconds = (bucket.seconds or 0) + entry.seconds
            bucket.total = (bucket.total or 0) + entry.seconds
            State.set_pending_seconds(key, bucket)
        end
    end

    local remote = collect_pending()
    if #remote == 0 then
        return nil
    end
    return remote
end

function M.push_seconds(api, entries)
    if not entries or #entries == 0 then
        return
    end
    local rsp
    local index = 1
    while index <= #entries do
        local batch = {}
        for offset = index, math.min(#entries, index + MAX_SECONDS_BATCH - 1) do
            batch[#batch + 1] = entries[offset]
        end
        local result, err = api:post("/reading-seconds", { client_updated_at = os.time() * 1000, entries = batch })
        if not result or err then
            logger.warn("MyBooks: reading-seconds push failed", err)
            return nil, err
        end
        for _, entry in ipairs(batch) do
            if entry.key then
                State.clear_pending_seconds(entry.key)
            end
        end
        rsp = result
        index = index + #batch
    end
    logger.dbg("MyBooks: reading-seconds pushed", rsp and rsp.applied, #entries)
    return rsp
end

function M.flush_seconds(api, link)
    M.push_seconds(api, M.collect_seconds(link))
end

function M.flush_pending(api)
    for _, key in ipairs(State.pending_keys()) do
        local payload = State.pending(key)
        if payload then
            local rsp, err = api:post("/progress", payload)
            if rsp and not err then
                State.clear_pending(key)
            else
                logger.warn("MyBooks: pending progress still failing", key)
                break
            end
        end
    end
end

function M.push_state(api, link, changes)
    if not link or not link.book_id then
        return nil
    end
    local payload = {
        book_id = link.book_id,
        client_updated_at = os.time() * 1000,
    }
    for key, value in pairs(changes or {}) do
        payload[key] = value
    end
    local key = book_key(link)
    local rsp, err = api:post("/state", payload)
    if not rsp or err then
        State.set_pending_state(key, payload)
        logger.warn("MyBooks: state push failed", key, err)
        return nil, err
    end
    State.clear_pending_state(key)
    return rsp
end

function M.flush_state(api)
    for key, payload in pairs(State.load().pending_state or {}) do
        local rsp, err = api:post("/state", payload)
        if rsp and not err then
            State.clear_pending_state(key)
        else
            logger.warn("MyBooks: pending state still failing", key)
        end
    end
end

function M.on_open_document(api, ui, notify)
    local link = M.link_for_ui(ui)
    if not link then
        return
    end
    ensure_watermark(link)
    M.flush_pending(api)
    M.flush_state(api)
    M.flush_seconds(api, link)
    if State.setting("sync_progress", true) then
        local rsp, err = Progress.open_sync(api, ui, link)
        if not rsp and notify then
            Toast.error(require("mybooks_list_view").error_text(err))
        end
    end
    if State.setting("sync_annotations", true) then
        Annotations.exchange(api, ui, link, book_key(link))
    end
    UIManager:setDirty(ui.view, "ui")
end

function M.on_suspend(api, ui)
    local link = M.link_for_ui(ui)
    if not link then
        return
    end
    local seconds = M.collect_seconds(link)
    if State.setting("sync_progress", true) then
        local payload = Progress.payload(link, Progress.snapshot(ui))
        if not Progress.push(api, link, payload) then
            State.set_pending(book_key(link), payload)
        end
    end
    if seconds then
        M.push_seconds(api, seconds)
    end
end

function M.on_close_document(api, ui)
    local link = M.link_for_ui(ui)
    if not link then
        return
    end
    M.on_suspend(api, ui)
    if State.setting("sync_annotations", true) then
        Annotations.exchange(api, ui, link, book_key(link))
    end
end

function M.on_page_update(api, ui)
    local link = M.link_for_ui(ui)
    if not link or not State.setting("sync_progress", true) then
        return
    end
    local now = os.time()
    if link.last_heartbeat and now - link.last_heartbeat < 60 then
        return
    end
    link.last_heartbeat = now
    State.set_link(ui.document.file, link)
    Progress.push(api, link, Progress.payload(link, Progress.snapshot(ui)))
end

function M.mark_opened(api, ui)
    local link = M.link_for_ui(ui)
    if not link then
        return
    end
    M.push_state(api, link, { read_state = 1, download = true })
end

return M
