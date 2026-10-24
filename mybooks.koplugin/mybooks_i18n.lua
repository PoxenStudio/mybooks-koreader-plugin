local gettext = require("gettext")
local State = require("mybooks_state")

local M = {}

local strings = {
    app_title = { zh = "MyBooks", en = "MyBooks" },
    home = { zh = "首页", en = "Home" },
    browse = { zh = "分类浏览", en = "Browse" },
    search = { zh = "搜索", en = "Search" },
    settings = { zh = "设置", en = "Settings" },
    sign_in = { zh = "登录", en = "Sign in" },
    sign_out = { zh = "退出登录", en = "Sign out" },
    account = { zh = "账号", en = "Account" },
    server_address = { zh = "服务器地址", en = "Server address" },
    username = { zh = "用户名", en = "Username" },
    password = { zh = "密码", en = "Password" },
    test_connection = { zh = "测试连接", en = "Test connection" },
    connect = { zh = "连接", en = "Connect" },
    cancel = { zh = "取消", en = "Cancel" },
    ok = { zh = "确定", en = "OK" },
    back = { zh = "返回", en = "Back" },
    close = { zh = "关闭", en = "Close" },
    retry = { zh = "重试", en = "Retry" },
    loading = { zh = "正在加载…", en = "Loading…" },
    refresh = { zh = "刷新", en = "Refresh" },
    download = { zh = "下载", en = "Download" },
    download_open = { zh = "下载并打开", en = "Download and open" },
    open = { zh = "打开", en = "Open" },
    read = { zh = "阅读", en = "Read" },
    open_home = { zh = "打开 MyBooks 首页", en = "Open MyBooks home" },
    details = { zh = "详情", en = "Details" },
    favorite = { zh = "收藏", en = "Favorite" },
    unfavorite = { zh = "取消收藏", en = "Unfavorite" },
    unwant = { zh = "取消待读", en = "Remove from to-read" },
    mark_read = { zh = "标记已读", en = "Mark as read" },
    mark_unread = { zh = "标记未读", en = "Mark as unread" },
    mark_reading = { zh = "标记在读", en = "Mark as reading" },
    sync_section = { zh = "同步", en = "Sync" },
    sync_progress = { zh = "同步阅读进度", en = "Sync reading progress" },
    sync_reading_seconds = { zh = "同步阅读时长", en = "Sync reading time" },
    sync_annotations = { zh = "同步标注与笔记", en = "Sync highlights and notes" },
    sync_status = { zh = "待同步数据（进度 / 时长 / 已关联）", en = "Pending (progress / time / linked)" },
    sync_status_fmt = { zh = "%d / %d / %d", en = "%d / %d / %d" },
    sync_now = { zh = "立即同步", en = "Sync now" },
    sync_done = { zh = "同步完成", en = "Sync finished" },
    link_book = { zh = "关联到服务器书籍", en = "Link to a server book" },
    unlink_book = { zh = "取消关联", en = "Unlink from server" },
    link_title = { zh = "选择匹配的书籍：%s", en = "Choose a matching book: %s" },
    link_done = { zh = "已关联：%s", en = "Linked: %s" },
    unlink_done = { zh = "已取消关联", en = "Unlinked" },
    link_no_match = { zh = "未找到匹配的书籍", en = "No matching book found" },
    link_no_document = { zh = "当前没有打开的书", en = "No book is open" },
    my_favorites = { zh = "我的收藏", en = "My favorites" },
    my_wishlist = { zh = "我的待读", en = "My to-read" },
    my_read = { zh = "我的已读", en = "My read" },
    reading_now = { zh = "在读书籍", en = "Reading now" },
    categories = { zh = "分类", en = "Categories" },
    tags = { zh = "标签", en = "Tags" },
    authors = { zh = "作者", en = "Authors" },
    latest = { zh = "最新", en = "Latest" },
    reading = { zh = "在读", en = "Reading" },
    finished = { zh = "已读", en = "Finished" },
    to_read = { zh = "待读", en = "To read" },
    all_books = { zh = "全部书籍", en = "All books" },
    no_books = { zh = "暂无书籍", en = "No books" },
    no_results = { zh = "没有找到结果", en = "No results found" },
    no_reading_now = { zh = "暂无在读书籍，去分类浏览挑一本", en = "Nothing in progress, browse the library" },
    not_logged_in = { zh = "尚未登录", en = "Not signed in" },
    login_hint = { zh = "请先登录服务器", en = "Sign in to your server first" },
    invalid_credentials = { zh = "用户名或密码不正确", en = "Incorrect username or password" },
    cannot_connect = { zh = "无法连接服务器（检查地址/网络）", en = "Cannot reach the server (check address/network)" },
    address_invalid = { zh = "服务器地址无效，请勿填写 /books 或 /opds 地址", en = "Invalid address, do not use a /books or /opds URL" },
    connected_as = { zh = "已连接：%s", en = "Connected: %s" },
    password_plain_hint = { zh = "密码以明文保存在本机设置文件中", en = "Password is stored in plain text on this device" },
    download_dir = { zh = "下载目录", en = "Download directory" },
    view_mode = { zh = "列表样式", en = "View mode" },
    view_list = { zh = "列表", en = "List" },
    view_grid = { zh = "网格", en = "Grid" },
    ui_language = { zh = "界面语言", en = "Interface language" },
    lang_auto = { zh = "跟随 KOReader", en = "Follow KOReader" },
    lang_zh = { zh = "中文", en = "Chinese" },
    lang_en = { zh = "English", en = "English" },
    downloading = { zh = "正在下载 %s", en = "Downloading %s" },
    download_done = { zh = "下载完成", en = "Download complete" },
    download_exists = { zh = "文件已存在，是否覆盖？", en = "File already exists, overwrite?" },
    choose_format = { zh = "选择格式", en = "Choose format" },
    download_failed = { zh = "下载失败：%s", en = "Download failed: %s" },
    no_format = { zh = "没有可下载的格式", en = "No downloadable format" },
    not_downloaded = { zh = "尚未下载到本机", en = "Not downloaded yet" },
    no_more = { zh = "没有更多了", en = "No more items" },
    first_page = { zh = "已是第一页", en = "First page" },
    last_page = { zh = "已是最后一页", en = "Last page" },
    total_books = { zh = "共 %s 本", en = "%s books" },
    progress = { zh = "进度", en = "Progress" },
    reading_time = { zh = "阅读时长", en = "Reading time" },
    published = { zh = "出版", en = "Published" },
    publisher = { zh = "出版社", en = "Publisher" },
    series = { zh = "丛书", en = "Series" },
    isbn = { zh = "ISBN", en = "ISBN" },
    language = { zh = "语言", en = "Language" },
    formats = { zh = "格式", en = "Formats" },
    size = { zh = "体积", en = "Size" },
    description = { zh = "简介", en = "Description" },
    expand = { zh = "展开", en = "Expand" },
    more = { zh = "更多", en = "More" },
    about = { zh = "关于", en = "About" },
    version = { zh = "版本", en = "Version" },
    device = { zh = "设备", en = "Device" },
    cache_cleared = { zh = "封面缓存已清理", en = "Cover cache cleared" },
    clear_cache = { zh = "清理封面缓存", en = "Clear cover cache" },
    err_network = { zh = "网络错误", en = "Network error" },
    err_auth = { zh = "登录已失效", en = "Authentication failed" },
    err_http = { zh = "服务器错误", en = "Server error" },
    err_forbidden = { zh = "没有权限", en = "Permission denied" },
    err_missing = { zh = "书籍不存在", en = "Book not found" },
    err_json = { zh = "服务器响应异常", en = "Bad server response" },
    err_write = { zh = "无法写入文件", en = "Cannot write file" },
    err_rename = { zh = "无法完成文件写入", en = "Cannot finalize file" },
    err_disabled = { zh = "KOReader 服务未启用", en = "KOReader service is disabled" },
    err_busy = { zh = "服务器繁忙，请稍后重试", en = "Server busy, try again later" },
    search_hint = { zh = "输入书名、作者或 Calibre 表达式", en = "Title, author or Calibre expression" },
    type_to_search = { zh = "输入关键字开始搜索", en = "Type a keyword to search" },
    enter_keyword = { zh = "请输入搜索关键字", en = "Enter a keyword" },
    no_categories = { zh = "暂无分类", en = "No categories" },
    no_tags = { zh = "暂无标签", en = "No tags" },
    no_authors = { zh = "暂无作者", en = "No authors" },
    load_more = { zh = "继续加载", en = "Load more" },
    home_reading = { zh = "在读书籍", en = "Reading now" },
    view_all = { zh = "全部", en = "All" },
    today_reading = { zh = "今日 %s", en = "Today %s" },
    streak_days = { zh = "连续 %d 天", en = "%d-day streak" },
    today = { zh = "今日", en = "Today" },
    streak = { zh = "连续", en = "Streak" },
    unit_hours = { zh = "小时", en = "h" },
    unit_days = { zh = "天", en = "d" },
    browse_section = { zh = "分类浏览", en = "Browse" },
    account_section = { zh = "账号", en = "Account" },
    browse_settings = { zh = "浏览", en = "Browsing" },
    interface_section = { zh = "界面", en = "Interface" },
    download_settings = { zh = "下载", en = "Downloads" },
    about_section = { zh = "关于", en = "About" },
    connecting = { zh = "正在测试连接…", en = "Testing connection…" },
    test_ok = { zh = "连接成功：%s", en = "Connected: %s" },
    re_login = { zh = "重新登录", en = "Sign in again" },
    sign_out_confirm = { zh = "退出登录会清除本机凭据，已下载的书不受影响。确定退出？", en = "Signing out removes credentials on this device. Downloaded books are kept. Continue?" },
    signed_out = { zh = "已退出登录", en = "Signed out" },
    default_format = { zh = "默认格式", en = "Default format" },
    auto_open = { zh = "下载后自动打开", en = "Open after download" },
    on = { zh = "开", en = "On" },
    off = { zh = "关", en = "Off" },
    description_empty = { zh = "暂无简介", en = "No description" },
    collapse = { zh = "收起", en = "Collapse" },
    server_version = { zh = "服务器版本", en = "Server version" },
    site_address = { zh = "站点地址", en = "Site address" },
    device_id = { zh = "设备标识", en = "Device ID" },
    state_file = { zh = "状态文件", en = "State file" },
    reading_stats = { zh = "阅读统计", en = "Reading stats" },
    started_on = { zh = "%s 开始", en = "Started %s" },
    finished_on = { zh = "%s 完成", en = "Finished %s" },
    rating = { zh = "评分", en = "Rating" },
    status = { zh = "状态", en = "Status" },
    download_progress = { zh = "下载中 %d%%", en = "Downloading %d%%" },
    directory_hint = { zh = "输入完整目录路径", en = "Full directory path" },
    no_local_file = { zh = "本机尚未下载该书", en = "Not downloaded on this device" },
}

local cached_lang

local function detect_lang()
    if cached_lang then
        return cached_lang
    end
    local lang = nil
    local ok, saved = pcall(function()
        return State.setting("language", "auto")
    end)
    if ok and (saved == "zh" or saved == "en") then
        lang = saved
    end
    if not lang then
        pcall(function()
            if gettext.current_lang then
                lang = tostring(gettext.current_lang)
            end
        end)
        if (not lang or lang == "") and G_reader_settings then
            local ok_saved, reader_lang = pcall(function()
                return G_reader_settings:readSetting("language")
            end)
            if ok_saved and reader_lang then
                lang = tostring(reader_lang)
            end
        end
    end
    cached_lang = (lang and lang ~= "") and lang or "en"
    return cached_lang
end

function M.reset()
    cached_lang = nil
end

function M.lang()
    return detect_lang()
end

function M.T(key, ...)
    local entry = strings[key]
    if not entry then
        return key
    end
    local is_zh = detect_lang():lower():match("^zh") ~= nil
    local text = is_zh and entry.zh or entry.en
    local args = { ... }
    if #args > 0 then
        local ok, formatted = pcall(string.format, text, unpack(args))
        if ok then
            return formatted
        end
    end
    return text
end

return M
