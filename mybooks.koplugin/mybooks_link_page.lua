local util = require("util")
local logger = require("logger")

local DialogUI = require("mybooks_dialog_ui")
local I18N = require("mybooks_i18n")
local ListView = require("mybooks_list_view")
local State = require("mybooks_state")
local Toast = require("mybooks_toast")

local M = {}

local function book_format(file_path)
    local suffix = tostring(file_path):match("%.([%w]+)$")
    return suffix and suffix:lower() or "epub"
end

local function md5_of(path)
    if type(util.partialMD5) ~= "function" then
        return nil
    end
    local ok, digest = pcall(util.partialMD5, path)
    if ok then
        return digest
    end
    return nil
end

local function doc_meta(ui)
    local props = ui.doc_props or {}
    local title = props.title
    local author = props.authors
    if type(author) == "table" then
        local names = {}
        for _, item in ipairs(author) do
            names[#names + 1] = tostring(item)
        end
        author = table.concat(names, ", ")
    end
    if not title or title == "" then
        title = tostring(ui.document.file or ""):match("([^/]+)%.[%w]+$") or ""
    end
    return tostring(title or ""), tostring(author or "")
end

function M.link(api, ui, book)
    if not book or not book.id then
        return
    end
    local file_path = ui.document.file
    local info = {
        book_id = book.id,
        format = book_format(file_path),
        title = book.title,
        author = book.author,
        md5 = md5_of(file_path),
        path = file_path,
        pushed_at = 0,
    }
    State.set_link(file_path, info)
    State.set_book(book.id, {
        title = book.title,
        author = book.author,
        img = book.img,
        thumb = book.thumb,
        formats = book.formats,
    })
    local Sync = require("mybooks_sync")
    Sync.push_state(api, info, { download = true })
    logger.dbg("MyBooks: linked", file_path, book.id)
    Toast.show(I18N.T("link_done", book.title or tostring(book.id)))
end

function M.unlink(ui)
    State.remove_link(ui.document.file)
    Toast.show(I18N.T("unlink_done"))
end

function M.show(api, ui)
    if not ui or not ui.document then
        Toast.show(I18N.T("link_no_document"))
        return
    end
    local title, author = doc_meta(ui)
    Toast.loading(I18N.T("loading"))
    local rsp, err = api:post("/match", { title = title, author = author, limit = 10 })
    Toast.dismiss()
    if err or not rsp then
        Toast.error(ListView.error_text(err or "network"))
        return
    end
    local candidates = rsp.candidates or {}
    if #candidates == 0 then
        Toast.show(I18N.T("link_no_match"))
        return
    end
    local options = {}
    for _, book in ipairs(candidates) do
        options[#options + 1] = {
            text = string.format("%s — %s", tostring(book.title or ""), tostring(book.author or "")),
            value = book,
        }
    end
    DialogUI.choose(I18N.T("link_title", title), options, function(book)
        M.link(api, ui, book)
    end)
end

return M
