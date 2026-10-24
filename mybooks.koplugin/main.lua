local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local I18N = require("mybooks_i18n")
local State = require("mybooks_state")

local MyBooks = WidgetContainer:extend{
    name = "mybooks",
    is_doc_only = false,
}

function MyBooks:init()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    Dispatcher:registerAction("mybooks_open_home", {
        category = "none",
        event = "MyBooksOpenHome",
        title = I18N.T("app_title"),
        general = true,
    })
    logger.dbg("MyBooks: plugin initialized", State.device_id())
end

function MyBooks:has_api()
    return State.api() ~= nil
end

function MyBooks:in_reader()
    return self.ui and self.ui.document ~= nil
end

function MyBooks:addToMainMenu(menu_items)
    if self:in_reader() then
        menu_items.mybooks = {
            text = I18N.T("app_title"),
            sorting_hint = "tools",
            sub_item_table = {
                {
                    text = I18N.T("open_home"),
                    callback = function()
                        self:open_home()
                    end,
                },
                {
                    text = I18N.T("sync_now"),
                    callback = function()
                        self:sync_now()
                    end,
                },
                {
                    text = I18N.T("link_book"),
                    callback = function()
                        self:link_book()
                    end,
                },
                {
                    text = I18N.T("unlink_book"),
                    callback = function()
                        self:unlink_book()
                    end,
                },
                {
                    text = I18N.T("sync_annotations"),
                    callback = function()
                        self:sync_annotations()
                    end,
                },
                {
                    text = I18N.T("settings"),
                    callback = function()
                        require("mybooks_settings_page").show(State.api())
                    end,
                },
            },
        }
        return
    end
    menu_items.mybooks = {
        text = I18N.T("app_title"),
        sorting_hint = "tools",
        callback = function()
            self:open_home()
        end,
    }
end

function MyBooks:open_home()
    local api = State.api()
    if not api then
        require("mybooks_signin_page").show()
        return
    end
    require("mybooks_home").show(api)
end

function MyBooks:sync_now()
    local api = State.api()
    if not api or not self:in_reader() then
        return
    end
    local Sync = require("mybooks_sync")
    Sync.flush_pending(api)
    Sync.flush_state(api)
    if Sync.link_for_ui(self.ui) then
        Sync.on_close_document(api, self.ui)
    end
end

function MyBooks:sync_annotations()
    local api = State.api()
    if not api or not self:in_reader() then
        return
    end
    local Sync = require("mybooks_sync")
    local link = Sync.link_for_ui(self.ui)
    if not link then
        return
    end
    require("mybooks_annotations").exchange(api, self.ui, link, Sync.book_key(link))
    require("mybooks_toast").show(I18N.T("sync_done"))
end

function MyBooks:link_book()
    local api = State.api()
    if not api or not self:in_reader() then
        return
    end
    require("mybooks_link_page").show(api, self.ui)
end

function MyBooks:unlink_book()
    if not self:in_reader() then
        return
    end
    require("mybooks_link_page").unlink(self.ui)
end

function MyBooks:onMyBooksOpenHome()
    self:open_home()
    return true
end

function MyBooks:onReaderReady()
    if not self:has_api() then
        return
    end
    logger.dbg("MyBooks: reader ready", tostring(self.ui and self.ui.document and self.ui.document.file))
    local Sync = require("mybooks_sync")
    Sync.on_open_document(State.api(), self.ui, true)
    Sync.mark_opened(State.api(), self.ui)
end

function MyBooks:onCloseDocument()
    if not self:has_api() or not self:in_reader() then
        return
    end
    logger.dbg("MyBooks: closing document")
    require("mybooks_sync").on_close_document(State.api(), self.ui)
end

function MyBooks:onPageUpdate()
    if not self:has_api() or not self:in_reader() then
        return
    end
    require("mybooks_sync").on_page_update(State.api(), self.ui)
end

function MyBooks:onSuspend()
    if not self:has_api() or not self:in_reader() then
        return
    end
    require("mybooks_sync").on_suspend(State.api(), self.ui)
end

return MyBooks
