local Device = require("device")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local Meta = require("mybooks_meta")

local M = {}

function M.model()
    local ok, model = pcall(function() return Device:info() end)
    if ok and model then
        return tostring(model)
    end
    if Device.model then
        return tostring(Device.model)
    end
    return "KOReader"
end

function M.plugin_version()
    return Meta.version
end

function M.cache_dir()
    local dir = DataStorage:getDataDir() .. "/cache/mybooks"
    M.ensure_dir(dir)
    return dir
end

function M.download_dir()
    local saved = G_reader_settings:readSetting("mybooks_download_dir")
    if saved and saved ~= "" then
        return saved
    end
    local dir = DataStorage:getDataDir() .. "/mybooks"
    M.ensure_dir(dir)
    return dir
end

function M.ensure_dir(path)
    if path and path ~= "" and not lfs.attributes(path, "mode") then
        util.makePath(path)
    end
    return path
end

function M.safe_filename(name)
    name = tostring(name or "")
    name = name:gsub("[/\\%z\1-\31:*?\"<>|]", "_")
    name = name:gsub("%s+", " ")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name > 120 then
        name = name:sub(1, 120)
    end
    if name == "" then
        name = "book"
    end
    return name
end

function M.file_exists(path)
    return path and path ~= "" and lfs.attributes(path, "mode") == "file"
end

function M.file_size(path)
    local attr = lfs.attributes(path)
    if attr and attr.size then
        return attr.size
    end
    return nil
end

return M
