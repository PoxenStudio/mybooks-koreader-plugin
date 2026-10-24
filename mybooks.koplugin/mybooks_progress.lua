local logger = require("logger")

local DeviceInfo = require("mybooks_device")
local State = require("mybooks_state")

local M = {}

local stats_available

local function stats_ok()
    if stats_available == nil then
        stats_available = require("mybooks_stats_reader").available()
    end
    return stats_available
end

function M.snapshot(ui)
    if not ui or not ui.document then
        return nil
    end
    local doc_settings = ui.doc_settings
    local xpointer = ui.rolling and ui.rolling.xpointer
    if (not xpointer or xpointer == "") and doc_settings then
        xpointer = doc_settings:readSetting("last_xpointer")
    end
    local percent
    local source = ui.paging or ui.rolling
    if source and type(source.getLastPercent) == "function" then
        local ok, value = pcall(source.getLastPercent, source)
        if ok then
            percent = tonumber(value)
        end
    end
    if not percent and doc_settings then
        percent = tonumber(doc_settings:readSetting("percent_finished"))
    end
    if percent and percent <= 1 then
        percent = math.floor(percent * 10000 + 0.5) / 100
    end
    local page, pages
    local page_ok, current = pcall(function()
        return ui.document:getCurrentPage()
    end)
    if page_ok then
        page = tonumber(current)
    end
    local count_ok, total = pcall(function()
        return ui.document:getPageCount()
    end)
    if count_ok then
        pages = tonumber(total)
    end
    logger.dbg("MyBooks: snapshot", tostring(xpointer), tostring(percent), tostring(page), tostring(pages))
    return { xpointer = xpointer, percent = percent, page = page, pages = pages }
end

function M.payload(link, snap)
    local payload = {
        book_id = link.book_id,
        format = link.format or "epub",
        client_updated_at = os.time() * 1000,
        skip_heartbeat = stats_ok(),
        device = { id = State.device_id(), name = DeviceInfo.model() },
    }
    if snap then
        if snap.xpointer and snap.xpointer ~= "" then
            payload.location = { xpointer = snap.xpointer }
        end
        if snap.percent then
            payload.percent = snap.percent
        end
        if snap.page and snap.pages and snap.pages > 0 then
            payload.progress = { snap.page, snap.pages }
        end
    end
    return payload
end

function M.push(api, link, payload)
    local rsp, err = api:post("/progress", payload)
    if err then
        logger.warn("MyBooks: progress push failed", err)
        return nil, err
    end
    if link and link.path then
        link.pushed_at = payload.client_updated_at
        State.set_link(link.path, link)
    end
    return rsp
end

function M.pull(api, link)
    local rsp, err = api:get("/progress/" .. tostring(link.book_id), { format = link.format or "epub" })
    if err then
        logger.warn("MyBooks: progress pull failed", err)
        return nil, err
    end
    return rsp
end

function M.apply(ui, position, percent)
    local view = ui and (ui.paging or ui.rolling)
    if not view then
        return false
    end
    local xpointer = position and position.xpointer
    if xpointer and xpointer ~= "" and type(view.onGotoXPointer) == "function" then
        local ok, done = pcall(view.onGotoXPointer, view, xpointer)
        if ok and done ~= false then
            logger.dbg("MyBooks: applied server xpointer", xpointer)
            return true
        end
        logger.warn("MyBooks: goto xpointer failed", xpointer)
    end
    percent = tonumber(percent)
    if percent and percent > 0 and type(view.onGotoPercent) == "function" then
        local ok = pcall(view.onGotoPercent, view, percent)
        if ok then
            logger.dbg("MyBooks: applied server percent", percent)
            return true
        end
    end
    return false
end

function M.open_sync(api, ui, link)
    local rsp, err = M.pull(api, link)
    if not rsp or err then
        local snap = M.snapshot(ui)
        return M.push(api, link, M.payload(link, snap)), err
    end
    local position = rsp.location or {}
    local server_ts = tonumber(position.client_updated_at) or 0
    local local_ts = tonumber(link.pushed_at) or 0
    if server_ts > local_ts and M.apply(ui, position, position.percent or rsp.progress_percent) then
        link.pushed_at = server_ts
        if link.path then
            State.set_link(link.path, link)
        end
        return rsp
    end
    local snap = M.snapshot(ui)
    return M.push(api, link, M.payload(link, snap))
end

return M
