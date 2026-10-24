local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local logger = require("logger")
local md5 = require("ffi/sha2").md5

local State = require("mybooks_state")

local M = {}

local STYLE_TO_DRAWER = {
    highlight = "lighten",
    underline = "underscore",
    squiggly = "strikeout",
}

local DRAWER_TO_STYLE = {
    lighten = "highlight",
    invert = "highlight",
    underscore = "underline",
    strikeout = "squiggly",
}

local KNOWN_COLORS = {
    ["#FF0000"] = "red",
    ["#FFFF00"] = "yellow",
    ["#00FF00"] = "green",
    ["#0000FF"] = "blue",
    ["#FFA500"] = "orange",
    ["#800080"] = "purple",
    ["#808080"] = "gray",
}

local COLORS = {}
for hex, name in pairs(KNOWN_COLORS) do
    COLORS[name] = hex
end

local function digest(text)
    local sum = md5()
    sum(tostring(text or ""))
    return sum()
end

local function ms(datetime)
    if not datetime or datetime == "" then
        return nil
    end
    local y, m, d, hh, mm, ss = tostring(datetime):match("(%d+)-(%d+)-(%d+)[ T](%d+):(%d+):(%d+)")
    if not y then
        return nil
    end
    return os.time({
        year = tonumber(y) or 0,
        month = tonumber(m) or 1,
        day = tonumber(d) or 1,
        hour = tonumber(hh) or 0,
        min = tonumber(mm) or 0,
        sec = tonumber(ss) or 0,
        isdst = false,
    }) * 1000
end

local function datetime(value)
    local seconds = math.floor((tonumber(value) or 0) / 1000)
    if seconds <= 0 then
        return nil
    end
    return os.date("%Y-%m-%d %H:%M:%S", seconds)
end

local function style_of(item)
    return DRAWER_TO_STYLE[item.drawer or ""] or "highlight"
end

local function color_of(item)
    local raw = tostring(item.color or ""):upper()
    if raw == "" then
        return "yellow"
    end
    return KNOWN_COLORS[raw] or raw
end

local function drawer_of(note)
    return STYLE_TO_DRAWER[note.style or ""] or "lighten"
end

local function color_hex(note)
    local name = tostring(note.color or ""):lower()
    return COLORS[name] or KNOWN_COLORS[tostring(note.color or ""):upper()] or "#FFFF00"
end

local function pos_key(value)
    if type(value) ~= "table" then
        return tostring(value or "")
    end
    return string.format("%s:%s:%s", tostring(value.page), tostring(value.x), tostring(value.y))
end

local function local_key(item)
    return pos_key(item.pos0 or item.page) .. "#" .. tostring(item.text or "") .. "#" .. tostring(item.datetime or "")
end

function M.collect(ui, book_key)
    local annotations = ui and ui.annotation and ui.annotation.annotations
    if not annotations then
        logger.dbg("MyBooks: annotations not ready")
        return nil
    end
    local known = State.annotation_known(book_key)
    local device_id = State.device_id()
    local current = {}
    local notes = {}
    for index, item in ipairs(annotations) do
        local xpointer0 = item.pos0
        if not xpointer0 and item.page then
            xpointer0 = tostring(item.page)
        end
        if xpointer0 then
            local key = local_key(item)
            local id = known[key]
            local created = ms(item.datetime) or os.time() * 1000
            if not id then
                id = string.format("ko-%s-%d-%s", device_id, created, digest(pos_key(xpointer0)):sub(1, 12))
            end
            current[key] = id
            notes[#notes + 1] = {
                id = id,
                type = (item.note and item.note ~= "") and "excerpt" or "annotation",
                xpointer0 = xpointer0,
                xpointer1 = item.pos1,
                text = item.text,
                note = item.note,
                style = style_of(item),
                color = color_of(item),
                chapter = item.chapter,
                createdAt = created,
                updatedAt = math.max(created, ms(item.datetime_updated) or created),
                index = index,
            }
        end
    end

    local now = os.time() * 1000
    for key, id in pairs(known) do
        if not current[key] then
            notes[#notes + 1] = { id = id, deletedAt = now, updatedAt = now }
        end
    end
    return notes, current
end

function M.find_local(ui, note, key)
    local annotations = ui.annotation and ui.annotation.annotations or {}
    for index, item in ipairs(annotations) do
        if key and local_key(item) == key then
            return index, item
        end
        if item.pos0 and pos_key(item.pos0) == pos_key(note.xpointer0) then
            return index, item
        end
        if not item.pos0 and note.xpointer0 and tostring(item.page) == tostring(note.xpointer0) and item.text == note.text then
            return index, item
        end
    end
    return nil
end

function M.apply_server(ui, book_key, notes)
    if not ui or not ui.annotation or not notes then
        return 0
    end
    local annotations = ui.annotation.annotations
    if not annotations then
        return 0
    end
    local known = State.annotation_known(book_key)
    local local_by_id = {}
    for key, id in pairs(known) do
        local_by_id[id] = key
    end
    local changed = 0
    for _, note in ipairs(notes) do
        local id = note.id
        local key = local_by_id[id]
        if note.deleted_at then
            local index = M.find_local(ui, note, key)
            if index then
                table.remove(annotations, index)
                changed = changed + 1
            end
            if key then
                known[key] = nil
            end
        elseif note.xpointer0 then
            local index, item = M.find_local(ui, note, key)
            if index and item then
                if note.note ~= nil then
                    item.note = note.note
                end
                item.datetime_updated = datetime(note.updated_at) or item.datetime_updated
                if note.style then
                    item.drawer = drawer_of(note)
                end
                if note.color then
                    item.color = color_hex(note)
                end
                known[local_key(item)] = id
                if key and key ~= local_key(item) then
                    known[key] = nil
                end
            else
                local rolling = ui.rolling ~= nil
                local item_new = {
                    datetime = datetime(note.created_at) or os.date("%Y-%m-%d %H:%M:%S"),
                    datetime_updated = datetime(note.updated_at),
                    text = note.text,
                    note = note.note,
                    page = rolling and note.xpointer0 or tonumber(note.xpointer0) or 1,
                    pos0 = rolling and note.xpointer0 or nil,
                    pos1 = rolling and note.xpointer1 or nil,
                    drawer = drawer_of(note),
                    color = color_hex(note),
                    chapter = note.chapter,
                }
                local ok = pcall(ui.annotation.addItem, ui.annotation, item_new)
                if not ok then
                    logger.warn("MyBooks: add annotation failed", tostring(note.id))
                else
                    ui:handleEvent(Event:new("AnnotationsModified", { item_new }))
                    known[local_key(item_new)] = id
                    changed = changed + 1
                end
            end
        end
    end
    if changed > 0 then
        ui.doc_settings:saveSetting("annotations", ui.annotation.annotations)
        UIManager:setDirty(ui.view, "ui")
    end
    State.set_annotation_known(book_key, known)
    return changed
end

function M.exchange(api, ui, link, book_key)
    local notes, current = M.collect(ui, book_key)
    if not notes then
        return nil, "not_ready"
    end
    local payload = {
        book_id = link.book_id,
        format = link.format or "epub",
        ack = State.annotation_ack(book_key),
        notes = notes,
    }
    logger.dbg("MyBooks: annotations exchange", book_key, #notes)
    local rsp, err = api:post("/annotations", payload)
    if not rsp or err then
        logger.warn("MyBooks: annotations exchange failed", err)
        return nil, err
    end
    M.apply_server(ui, book_key, rsp.notes)
    local known = State.annotation_known(book_key)
    for key, id in pairs(current or {}) do
        known[key] = id
    end
    State.set_annotation_known(book_key, known)
    if rsp.ack then
        State.set_annotation_ack(book_key, rsp.ack)
    end
    return rsp
end

return M
