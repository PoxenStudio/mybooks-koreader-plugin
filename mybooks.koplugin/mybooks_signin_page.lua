local UIManager = require("ui/uimanager")
local logger = require("logger")

local Api = require("mybooks_api")
local I18N = require("mybooks_i18n")
local ListView = require("mybooks_list_view")
local MenuUI = require("mybooks_menu_ui")
local Page = require("mybooks_page")
local State = require("mybooks_state")
local TextEntry = require("mybooks_text_entry")
local Toast = require("mybooks_toast")

local M = {}

local FIELDS = {
    { key = "server_url", label = "server_address", password = false },
    { key = "username", label = "username", password = false },
    { key = "password", label = "password", password = true },
}

local function mask(value, hidden)
    if hidden and value ~= "" then
        return "••••••"
    end
    if value == "" then
        return "—"
    end
    return value
end

function M.show(opts)
    opts = opts or {}
    local saved = State.credentials()
    local data = {
        server_url = saved.server_url or "",
        username = saved.username or "",
        password = saved.password or "",
    }
    local page
    local function build()
        local rows = {
            MenuUI.header(I18N.T("login_hint")),
        }
        for _, field in ipairs(FIELDS) do
            local key = field.key
            rows[#rows + 1] = {
                kind = "row",
                title = I18N.T(field.label),
                sub = mask(data[key], field.password),
                hit = function()
                    TextEntry.input{
                        title = I18N.T(field.label),
                        value = data[key],
                        password = field.password,
                        on_save = function(value)
                            data[key] = value or ""
                            page:set_items(build(), true)
                        end,
                    }
                end,
            }
        end
        rows[#rows + 1] = MenuUI.header(I18N.T("password_plain_hint"))
        return rows
    end

    local function error_text(err)
        if err == "auth" then
            return I18N.T("invalid_credentials")
        end
        if err == "network" then
            return I18N.T("cannot_connect")
        end
        if err == "address" then
            return I18N.T("address_invalid")
        end
        return ListView.error_text(err)
    end

    local function check()
        local url, url_err = Api.normalize_url(data.server_url)
        if not url then
            logger.dbg("MyBooks: invalid address", url_err)
            return nil, "address"
        end
        local api = Api.new{
            server_url = url,
            username = data.username,
            password = data.password,
            device_id = State.device_id(),
        }
        Toast.loading(I18N.T("connecting"))
        local rsp, err = api:get("/session")
        Toast.dismiss()
        if err then
            return nil, err
        end
        return rsp, nil, url, api
    end

    page = Page:new{
        title = I18N.T("sign_in"),
        items = build(),
        on_close = opts.on_close,
    }
    page.footer_buttons = {
        {
            text = I18N.T("test_connection"),
            hit = function()
                local rsp, err = check()
                if err then
                    Toast.error(error_text(err))
                    return
                end
                Toast.show(I18N.T("test_ok", rsp.user and rsp.user.nickname or ""))
            end,
        },
        {
            text = I18N.T("sign_in"),
            hit = function()
                local rsp, err, url, api = check()
                if err then
                    Toast.error(error_text(err))
                    return
                end
                if saved.server_url ~= url or saved.username ~= data.username then
                    State.clear_home()
                end
                State.save_credentials{
                    server_url = url,
                    username = data.username,
                    password = data.password,
                }
                State.set_session(rsp, url)
                page:close()
                Toast.show(I18N.T("connected_as", rsp.user and rsp.user.nickname or ""))
                if opts.on_done then
                    opts.on_done(api)
                else
                    require("mybooks_home").show(api)
                end
            end,
        },
    }
    UIManager:show(page, "ui")
    return page
end

return M
