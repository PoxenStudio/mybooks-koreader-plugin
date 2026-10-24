local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")

local DeviceInfo = require("mybooks_device")
local DialogUI = require("mybooks_dialog_ui")
local I18N = require("mybooks_i18n")
local MenuUI = require("mybooks_menu_ui")
local Metrics = require("mybooks_metrics")
local Page = require("mybooks_page")
local State = require("mybooks_state")
local TextEntry = require("mybooks_text_entry")
local Thumbnails = require("mybooks_thumbnails")
local Toast = require("mybooks_toast")

local M = {}

local FORMATS = { "epub", "pdf", "mobi", "azw3", "fb2", "txt", "cbz" }

local function value_row(title, value, hit)
    return {
        kind = "row",
        title = title,
        sub = value,
        face = Metrics.small_face(),
        sub_face = Metrics.meta_face(),
        hit = hit,
    }
end

local function toggle_row(title, enabled, hit)
    return {
        kind = "row",
        title = title,
        face = Metrics.small_face(),
        sub_face = Metrics.meta_face(),
        badge = enabled and I18N.T("on") or I18N.T("off"),
        hit = hit,
    }
end

local function language_label()
    local value = State.setting("language", "auto")
    if value == "zh" then
        return I18N.T("lang_zh")
    end
    if value == "en" then
        return I18N.T("lang_en")
    end
    return I18N.T("lang_auto")
end

function M.show(api)
    local page
    local function build()
        local cred = State.credentials()
        local rows = {
            MenuUI.section(I18N.T("account_section")),
            value_row(I18N.T("server_address"), cred.server_url or "—"),
            value_row(I18N.T("username"), cred.username or "—"),
            value_row(I18N.T("re_login"), "", function()
                require("mybooks_signin_page").show{
                    on_done = function(new_api)
                        api = new_api
                        page:set_items(build(), true)
                    end,
                }
            end),
            value_row(I18N.T("sign_out"), "", function()
                DialogUI.confirm(I18N.T("sign_out_confirm"), function()
                    State.clear_credentials()
                    State.clear_session()
                    State.clear_home()
                    require("mybooks_page").close_all()
                    Toast.show(I18N.T("signed_out"))
                    require("mybooks_signin_page").show()
                end)
            end),
            MenuUI.header(I18N.T("password_plain_hint")),

            MenuUI.section(I18N.T("interface_section"), { divider = true }),
            value_row(I18N.T("ui_language"), language_label(), function()
                DialogUI.choose(I18N.T("ui_language"), {
                    { text = I18N.T("lang_auto"), value = "auto" },
                    { text = I18N.T("lang_zh"), value = "zh" },
                    { text = I18N.T("lang_en"), value = "en" },
                }, function(value)
                    State.set_setting("language", value)
                    I18N.reset()
                    require("mybooks_page").close_all()
                    require("mybooks_home").show(api)
                end)
            end),

            MenuUI.section(I18N.T("browse_settings"), { divider = true }),
            value_row(I18N.T("view_mode"), I18N.T(State.setting("view_mode", "list") == "grid" and "view_grid" or "view_list"), function()
                DialogUI.choose(I18N.T("view_mode"), {
                    { text = I18N.T("view_list"), value = "list" },
                    { text = I18N.T("view_grid"), value = "grid" },
                }, function(value)
                    State.set_setting("view_mode", value)
                    page:set_items(build(), true)
                end)
            end),
            value_row(I18N.T("default_format"), tostring(State.setting("default_format", "epub")):upper(), function()
                local options = {}
                for _, fmt in ipairs(FORMATS) do
                    options[#options + 1] = { text = fmt:upper(), value = fmt }
                end
                DialogUI.choose(I18N.T("default_format"), options, function(value)
                    State.set_setting("default_format", value)
                    page:set_items(build(), true)
                end)
            end),
            value_row(I18N.T("clear_cache"), "", function()
                local removed = Thumbnails.clear()
                Toast.show(I18N.T("cache_cleared") .. " (" .. tostring(removed) .. ")")
            end),

            MenuUI.section(I18N.T("download_settings"), { divider = true }),
            value_row(I18N.T("download_dir"), DeviceInfo.download_dir(), function()
                TextEntry.input{
                    title = I18N.T("download_dir"),
                    value = DeviceInfo.download_dir(),
                    hint = I18N.T("directory_hint"),
                    on_save = function(value)
                        value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                        if value == "" then
                            return
                        end
                        DeviceInfo.ensure_dir(value)
                        if lfs.attributes(value, "mode") ~= "directory" then
                            Toast.error(I18N.T("err_write"))
                            return
                        end
                        G_reader_settings:saveSetting("mybooks_download_dir", value)
                        page:set_items(build(), true)
                    end,
                }
            end),
            toggle_row(I18N.T("auto_open"), State.setting("auto_open", true), function()
                State.set_setting("auto_open", not State.setting("auto_open", true))
                page:set_items(build(), true)
            end),

            MenuUI.section(I18N.T("sync_section"), { divider = true }),
            toggle_row(I18N.T("sync_progress"), State.setting("sync_progress", true), function()
                State.set_setting("sync_progress", not State.setting("sync_progress", true))
                page:set_items(build(), true)
            end),
            toggle_row(I18N.T("sync_reading_seconds"), State.setting("sync_reading_seconds", true), function()
                State.set_setting("sync_reading_seconds", not State.setting("sync_reading_seconds", true))
                page:set_items(build(), true)
            end),
            toggle_row(I18N.T("sync_annotations"), State.setting("sync_annotations", true), function()
                State.set_setting("sync_annotations", not State.setting("sync_annotations", true))
                page:set_items(build(), true)
            end),
            value_row(I18N.T("sync_status"), I18N.T("sync_status_fmt",
                #State.pending_keys(), #State.pending_seconds_keys(), State.links_count()), nil),
            value_row(I18N.T("sync_now"), "", function()
                local Sync = require("mybooks_sync")
                Sync.flush_pending(api)
                Sync.flush_state(api)
                Sync.flush_seconds(api)
                Toast.show(I18N.T("sync_done"))
                page:set_items(build(), true)
            end),

            MenuUI.section(I18N.T("about_section"), { divider = true }),
            value_row(I18N.T("version"), DeviceInfo.plugin_version()),
            value_row(I18N.T("site_address"), "https://mybooks.top"),
            value_row(I18N.T("device_id"), State.device_id()),
            value_row(I18N.T("state_file"), Metrics.format_size(State.size())),
        }
        return rows
    end

    page = Page:new{
        title = I18N.T("settings"),
        items = build(),
    }
    UIManager:show(page, "ui")
    return page
end

return M
