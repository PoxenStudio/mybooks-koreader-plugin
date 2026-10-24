local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local M = {}

local function db_path()
    return DataStorage:getSettingsDir() .. "/statistics.sqlite3"
end

function M.available()
    local ok, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok then
        return false
    end
    return SQ3 ~= nil and lfs.attributes(db_path(), "mode") == "file"
end

function M.entries(watermarks, floor, tz_offset, cutoff)
    if not M.available() then
        return nil
    end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn
    local ok, err = pcall(function()
        conn = SQ3.open(db_path(), "ro")
    end)
    if not ok or not conn then
        logger.warn("MyBooks: stats db open failed", err)
        return nil
    end
    watermarks = watermarks or {}
    floor = tonumber(floor) or 0
    cutoff = tonumber(cutoff) or os.time()
    local buckets = {}
    local updates = {}
    local stmt
    local read_ok, read_err = pcall(function()
        stmt = conn:prepare([[
            SELECT b.md5, p.start_time, p.duration
            FROM page_stat_data p JOIN book b ON b.id = p.id_book
            WHERE p.start_time > ? AND p.duration > 0
            ORDER BY p.start_time
        ]])
        stmt:bind(floor)
        for row in stmt:rows() do
            local md5 = tostring(row[1] or "")
            local start_time = tonumber(row[2]) or 0
            local duration = tonumber(row[3]) or 0
            local since = tonumber(watermarks[md5])
            if since and md5 ~= "" and duration > 0 and start_time > since and start_time + duration < cutoff then
                local day = os.date("!%Y-%m-%d", start_time + (tonumber(tz_offset) or 0))
                local key = md5 .. "|" .. day
                local bucket = buckets[key]
                if not bucket then
                    bucket = { md5 = md5, date = day, seconds = 0, last = 0 }
                    buckets[key] = bucket
                end
                bucket.seconds = bucket.seconds + duration
                bucket.last = math.max(bucket.last, start_time)
                updates[md5] = math.max(updates[md5] or 0, start_time)
            end
        end
    end)
    if stmt then
        pcall(stmt.close, stmt)
    end
    pcall(conn.close, conn)
    if not read_ok then
        logger.warn("MyBooks: stats query failed", read_err)
        return nil
    end

    local list = {}
    for _, bucket in pairs(buckets) do
        list[#list + 1] = bucket
    end
    table.sort(list, function(a, b)
        return a.last < b.last
    end)
    return list, updates
end

return M
