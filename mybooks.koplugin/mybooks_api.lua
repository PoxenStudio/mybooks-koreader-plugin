local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local rapidjson = require("rapidjson")
local socketurl = require("socket.url")
local sha2 = require("ffi/sha2")
local socketutil = require("socketutil")
local logger = require("logger")

local Meta = require("mybooks_meta")
local DeviceInfo = require("mybooks_device")

local Api = {}
Api.__index = Api

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Api.normalize_url(url)
    url = trim(url)
    url = url:gsub("/+$", "")
    if url == "" then
        return nil, "empty"
    end
    if url:find("[%s%?#]") then
        return nil, "invalid"
    end
    if url:match("/books$") then
        return nil, "download"
    end
    if url:match("/opds$") then
        return nil, "opds"
    end
    if not url:match("^https?://") then
        url = "https://" .. url
    end
    local rest = url:match("^https?://(.+)$")
    if not rest or rest == "" then
        return nil, "invalid"
    end
    return url
end

function Api:resolve(url)
    if not url or url == "" then
        return nil
    end
    if url:match("^https?://") then
        -- Keep the scheme the server handed us, but upgrade plain http to https
        -- when the configured server itself is https (reverse proxy setups),
        -- so we never downgrade a secure site.
        if self.server_url:match("^https://") then
            return (url:gsub("^http://", "https://"))
        end
        return url
    end
    if url:sub(1, 1) == "/" then
        return self.server_url .. url
    end
    return self.server_url .. "/" .. url
end

function Api.query(params)
    if not params then
        return ""
    end
    local parts = {}
    for key, value in pairs(params) do
        if value ~= nil and value ~= "" then
            parts[#parts + 1] = socketurl.escape(tostring(key)) .. "=" .. socketurl.escape(tostring(value))
        end
    end
    table.sort(parts)
    return table.concat(parts, "&")
end

function Api.new(opts)
    local self = setmetatable({}, Api)
    self.server_url = Api.normalize_url(opts.server_url) or ""
    self.username = opts.username or ""
    self.password = opts.password or ""
    self.device_id = opts.device_id or ""
    self.device_name = opts.device_name or DeviceInfo.model()
    self.block_timeout = opts.block_timeout or 15
    self.total_timeout = opts.total_timeout or 60
    logger.dbg("MyBooks: api ready", self.server_url)
    return self
end

function Api:url(path, params)
    local query = Api.query(params)
    local url = self.server_url .. Meta.api_prefix .. path
    if query ~= "" then
        url = url .. "?" .. query
    end
    return url
end

function Api:headers(json)
    local headers = {
        ["Accept"] = json and "application/json" or "*/*",
        ["User-Agent"] = "KOReader-MyBooks/" .. Meta.version,
        ["X-MyBooks-Client"] = Meta.client_header,
        ["X-MyBooks-Device"] = self.device_id .. " (" .. self.device_name .. ")",
        ["Connection"] = "close",
    }
    if json then
        headers["Content-Type"] = "application/json"
    end
    if self.username ~= "" then
        headers["Authorization"] = "Basic " .. sha2.bin_to_base64(self.username .. ":" .. self.password)
    end
    return headers
end

local function request_lib(url)
    if url:match("^https://") then
        return https
    end
    return http
end

local function sanitize(value)
    if type(value) ~= "table" then
        return value
    end
    for key, item in pairs(value) do
        if type(item) == "userdata" then
            value[key] = nil
        elseif type(item) == "table" then
            sanitize(item)
        end
    end
    return value
end

function Api:request(method, path, opts)
    opts = opts or {}
    local url = opts.url or self:url(path, opts.params)
    logger.dbg("MyBooks: request", method, url)
    local chunks = {}
    local req = {
        url = url,
        method = method,
        headers = self:headers(opts.body ~= nil),
        sink = ltn12.sink.table(chunks),
    }
    if opts.body then
        local ok, encoded = pcall(rapidjson.encode, opts.body)
        if not ok then
            return nil, "encode", nil
        end
        req.source = ltn12.source.string(encoded)
    end
    socketutil:set_timeout(self.block_timeout, self.total_timeout)
    local ok, err, code, rheaders, rstatus = pcall(request_lib(url).request, req)
    socketutil:reset_timeout()
    if not ok then
        logger.warn("MyBooks: request failed", err)
        return nil, "network", nil
    end
    local http_code = tonumber(code)
    local http_status = type(rstatus) == "string" and rstatus or nil
    if not http_code then
        logger.warn("MyBooks: network error", rheaders)
        return nil, "network", nil
    end
    local text = table.concat(chunks)
    if http_code ~= 200 then
        local body_snippet = text and text:sub(1, 500) or ""
        logger.warn("MyBooks: http status", http_code, http_status, "url", url, "body", body_snippet)
        local reason = "http"
        if http_code == 401 then
            reason = "auth"
        elseif http_code == 403 then
            reason = "forbidden"
        elseif http_code == 404 then
            reason = "missing"
        end
        return nil, reason, http_code, text
    end
    local decoded, data = pcall(rapidjson.decode, text)
    if not decoded or type(data) ~= "table" then
        logger.warn("MyBooks: invalid json", "url", url, "status", http_code, "body", (text or ""):sub(1, 500))
        return nil, "json", http_code, text
    end
    sanitize(data)
    if data.err and data.err ~= "ok" then
        return data, data.err, http_code, text
    end
    return data, nil, http_code, text
end

function Api:get(path, params)
    return self:request("GET", path, { params = params })
end

function Api:absolute(path, params)
    local query = Api.query(params)
    local url = self.server_url .. path
    if query ~= "" then
        url = url .. "?" .. query
    end
    return url
end

function Api:get_abs(path, params)
    return self:request("GET", nil, { url = self:absolute(path, params) })
end

function Api:post(path, body, params)
    return self:request("POST", path, { body = body or {}, params = params })
end

function Api:download(book_id, fmt, dest_path, part_path, progress_cb, resume, expected)
    local url = self.server_url .. "/api/book/" .. book_id .. "." .. fmt
    local offset = 0
    if resume then
        local probe = io.open(part_path, "rb")
        if probe then
            offset = probe:seek("end") or 0
            probe:close()
        end
    end
    local headers = self:headers(false)
    if offset > 0 then
        headers["Range"] = "bytes=" .. offset .. "-"
    end
    local file = io.open(part_path, offset > 0 and "ab" or "wb")
    if not file then
        logger.err("MyBooks: cannot open part file", part_path)
        return nil, "write"
    end
    local received = offset
    local total = tonumber(expected)
    if total and offset >= total then
        local done = os.rename(part_path, dest_path)
        return done and dest_path or nil, done and nil or "rename"
    end
    if progress_cb then
        progress_cb(received, total)
    end
    local file_closed = false
    local function close_file()
        if not file_closed then
            file_closed = true
            file:close()
        end
    end
    local write_error = nil
    local sink = function(chunk, err)
        if chunk then
            local ok = file:write(chunk)
            if not ok then
                write_error = "write"
                close_file()
                return nil, "write"
            end
            received = received + #chunk
            if progress_cb then
                progress_cb(received, total)
            end
            return 1
        end
        close_file()
        if err then
            return nil, err
        end
        return 1
    end
    socketutil:set_timeout(self.block_timeout, 3600)
    local ok, err, code, rheaders = pcall(request_lib(url).request, {
        url = url,
        method = "GET",
        headers = headers,
        sink = sink,
    })
    socketutil:reset_timeout()
    close_file()
    if not ok then
        logger.warn("MyBooks: download failed", err)
        return nil, "network"
    end
    local http_code = tonumber(code)
    local http_headers = type(rheaders) == "table" and rheaders or nil
    if write_error then
        return nil, write_error
    end
    if not http_code then
        return nil, "network"
    end
    if http_code ~= 200 and http_code ~= 206 then
        if http_code == 401 then
            return nil, "auth", http_code
        elseif http_code == 403 then
            return nil, "forbidden", http_code
        elseif http_code == 404 then
            return nil, "missing", http_code
        end
        return nil, "http", http_code
    end
    if offset > 0 and http_code == 200 then
        pcall(os.remove, part_path)
        logger.warn("MyBooks: server ignored Range, restarting download")
        return self:download(book_id, fmt, dest_path, part_path, progress_cb, false, expected)
    end
    if not total and http_headers and http_headers["content-length"] then
        total = tonumber(http_headers["content-length"])
    end
    local renamed = os.rename(part_path, dest_path)
    if not renamed then
        return nil, "rename"
    end
    return dest_path, nil, code, received, total
end

function Api:fetch_file(url, dest_path)
    local headers = self:headers(false)
    headers["Accept"] = "image/*"
    local file = io.open(dest_path, "wb")
    if not file then
        return nil, "write"
    end
    local closed = false
    local function close_file()
        if not closed then
            closed = true
            file:close()
        end
    end
    local write_error = nil
    local sink = function(chunk, err)
        if chunk then
            local wrote = file:write(chunk)
            if not wrote then
                write_error = "write"
                close_file()
                return nil, write_error
            end
            return 1
        end
        close_file()
        if err then
            return nil, err
        end
        return 1
    end
    socketutil:set_timeout(self.block_timeout, 300)
    local ok, _, code = pcall(request_lib(url).request, {
        url = url,
        method = "GET",
        headers = headers,
        sink = sink,
    })
    socketutil:reset_timeout()
    close_file()
    if not ok then
        pcall(os.remove, dest_path)
        return nil, "network"
    end
    if write_error then
        pcall(os.remove, dest_path)
        return nil, write_error
    end
    local http_code = tonumber(code)
    if not http_code then
        pcall(os.remove, dest_path)
        return nil, "network"
    end
    if http_code ~= 200 then
        pcall(os.remove, dest_path)
        return nil, "http", http_code
    end
    return dest_path
end

function Api:book_file_url(book_id, fmt)
    return self.server_url .. "/api/book/" .. book_id .. "." .. fmt
end

return Api
