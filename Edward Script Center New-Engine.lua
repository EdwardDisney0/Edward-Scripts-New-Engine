script_name("Edward Script Center Mobile")
script_author("EdwardDisney0")
script_version("2.6")

require "lib.moonloader"
local imgui = require("mimgui")
local sampev = require("lib.samp.events")
local encoding = require("encoding")
local ffi = require("ffi")

local UIX = { S = 1, mobile = false, clip0 = -1e9, clip1 = 1e9, stats_dirty = false }
do
    local R = imgui
    local bit = require("bit")
    local floor, abs = math.floor, math.abs
    local g = _G
    UIX.mobile = true

    local proxy = setmetatable({}, {
        __index = R,
        __newindex = function(_, k, v) R[k] = v end,
    })
    imgui = proxy

    local V = R.ImVec2
    local S = 1

    function UIX.setScale(ns)
        ns = math.max(0.6, math.min(UIX.maxS or 4, ns))
        if abs(ns - S) < 0.001 then return end
        S = ns
        UIX.S = ns
        pcall(function() R.GetIO().FontGlobalScale = ns / (UIX.B or ns) end)
        if UIX.onScale then pcall(UIX.onScale) end
    end
    local installed = false
    local touch = { owner = nil, drag = false, moved = 0, vel = 0 }
    local cstack, cn = {}, 0
    local dl_cache, dl_n = {}, 0
    local flags_failed = false

    function UIX.screen()
        local w, h = 0, 0
        local ok, io_ = pcall(R.GetIO)
        if ok and io_ then w, h = io_.DisplaySize.x, io_.DisplaySize.y end
        if not w or w < 100 or not h or h < 100 then w, h = getScreenResolution() end
        return w / S, h / S
    end

    function UIX.winSize(sw, sh)
        return math.min(sw - 12, 1400), math.min(sh - 12, 760)
    end

    function UIX.calcScale(override)
        if override and override > 0 then return math.max(0.6, math.min(4, override)) end
        local ok, rw, rh = pcall(getScreenResolution)
        if not ok or not rw or not rh or rw < 100 or rh < 100 then return 1 end
        if rh > rw then rw, rh = rh, rw end
        local s = math.min(rh / 540, rw / 900)
        return math.max(1, math.min(s, 3.2))
    end

    function UIX.lightDL(w)
        if flags_failed then return end
        local d = (type(w) == "table") and w.d or w
        local ok = pcall(function() d.Flags = bit.band(d.Flags, bit.bnot(7)) end)
        if not ok then flags_failed = true end
    end

    local function touchScroll(name)
        local io_ = R.GetIO()
        local dt = io_.DeltaTime
        if not dt or dt <= 0 then dt = 0.016 end
        local wp, ws = R.GetWindowPos(), R.GetWindowSize()
        local m = io_.MousePos
        local inside = m.x >= wp.x and m.x <= wp.x + ws.x and m.y >= wp.y and m.y <= wp.y + ws.y
        if R.IsMouseClicked(0) then
            if inside then
                touch.owner, touch.moved, touch.vel, touch.drag = name, 0, 0, false
            elseif touch.owner == name then
                touch.owner, touch.drag = nil, false
            end
        end
        if touch.owner ~= name then return end
        if io_.MouseDown[0] then
            local dy = io_.MouseDelta.y
            touch.moved = touch.moved + abs(dy)
            if not touch.drag and touch.moved > 10 * S then touch.drag = true end
            if touch.drag then
                R.SetScrollY(R.GetScrollY() - dy)
                touch.vel = touch.vel * 0.6 + (-dy / dt) * 0.4
            end
        elseif touch.drag and abs(touch.vel) > 60 then
            local y = R.GetScrollY() + touch.vel * dt
            local mx = R.GetScrollMaxY()
            if y < 0 then y = 0; touch.vel = 0 elseif y > mx then y = mx; touch.vel = 0 end
            R.SetScrollY(y)
            touch.vel = touch.vel * (1 - math.min(1, 4.5 * dt))
        else
            touch.owner, touch.drag = nil, false
        end
    end

    function UIX.init(s)
        if installed then return end
        installed = true
        S = s
        UIX.S = s
        local scaled = true

        local function sv(v) return V(v.x * S, v.y * S) end
        local function dv(v) return V(v.x / S, v.y / S) end

        if scaled then
            rawset(proxy, "SetCursorScreenPos", function(p) return R.SetCursorScreenPos(sv(p)) end)
            rawset(proxy, "GetCursorScreenPos", function() return dv(R.GetCursorScreenPos()) end)
            rawset(proxy, "GetContentRegionAvail", function() return dv(R.GetContentRegionAvail()) end)
            rawset(proxy, "GetWindowPos", function() return dv(R.GetWindowPos()) end)
            rawset(proxy, "GetWindowSize", function() return dv(R.GetWindowSize()) end)
            rawset(proxy, "CalcTextSize", function(...) return dv(R.CalcTextSize(...)) end)
            rawset(proxy, "GetFontSize", function() return R.GetFontSize() / S end)
            rawset(proxy, "Dummy", function(sz) return R.Dummy(sv(sz)) end)
            rawset(proxy, "PushItemWidth", function(w) return R.PushItemWidth(w * S) end)
            rawset(proxy, "SetNextWindowPos", function(p, cond, pivot) return R.SetNextWindowPos(sv(p), cond, pivot) end)
            rawset(proxy, "SetNextWindowSize", function(sz, cond) return R.SetNextWindowSize(sv(sz), cond) end)
            local alpha_id = tonumber(R.StyleVar.Alpha) or 0
            rawset(proxy, "PushStyleVarVec2", function(var, v) return R.PushStyleVarVec2(var, sv(v)) end)
            rawset(proxy, "PushStyleVarFloat", function(var, f)
                if tonumber(var) == alpha_id then return R.PushStyleVarFloat(var, f) end
                return R.PushStyleVarFloat(var, f * S)
            end)
        end

        rawset(proxy, "InvisibleButton", function(id, sz, ...)
            local r = R.InvisibleButton(id, scaled and sv(sz) or sz, ...)
            if touch.drag then
                if R.IsMouseClicked(0) then touch.drag = false else return false end
            end
            return r
        end)

        rawset(proxy, "BeginChild", function(id, sz, ...)
            cn = cn + 1
            cstack[cn] = id
            local r = R.BeginChild(id, (scaled and sz) and sv(sz) or sz, ...)
            UIX.lightDL(R.GetWindowDrawList())
            return r
        end)

        rawset(proxy, "EndChild", function()
            local name = cstack[cn]
            if cn > 0 then cn = cn - 1 end
            if name then pcall(touchScroll, name) end
            return R.EndChild()
        end)

        local DLM = {}
        DLM.__index = DLM
        function DLM:AddRect(a, b, c, r, fl, th) self.d:AddRect(sv(a), sv(b), c, r and r * S, fl, (th or 1) * S) end
        function DLM:AddRectFilled(a, b, c, r) self.d:AddRectFilled(sv(a), sv(b), c, r and r * S) end
        function DLM:AddCircleFilled(p, r, c, n) self.d:AddCircleFilled(sv(p), r * S, c, n) end
        function DLM:AddCircle(p, r, c, n, th) self.d:AddCircle(sv(p), r * S, c, n, (th or 1) * S) end
        function DLM:AddLine(a, b, c, th) self.d:AddLine(sv(a), sv(b), c, (th or 1) * S) end
        function DLM:AddTriangleFilled(a, b, c, col_) self.d:AddTriangleFilled(sv(a), sv(b), sv(c), col_) end
        function DLM:AddQuadFilled(a, b, c, d, col_) self.d:AddQuadFilled(sv(a), sv(b), sv(c), sv(d), col_) end
        function DLM:AddRectFilledMultiColor(a, b, c1, c2, c3, c4) self.d:AddRectFilledMultiColor(sv(a), sv(b), c1, c2, c3, c4) end
        function DLM:AddText(p, c, t) self.d:AddText(V(floor(p.x * S + 0.5), floor(p.y * S + 0.5)), c, t) end

        local function wrapDL(d)
            local key = tonumber(ffi.cast("uintptr_t", d))
            local w = dl_cache[key]
            if w and w.d == d then return w end
            dl_n = dl_n + 1
            if dl_n > 64 then dl_cache, dl_n = {}, 1 end
            w = setmetatable({ d = d }, DLM)
            dl_cache[key] = w
            return w
        end
        rawset(proxy, "GetWindowDrawList", function() return wrapDL(R.GetWindowDrawList()) end)
        rawset(proxy, "GetBackgroundDrawList", function() return wrapDL(R.GetBackgroundDrawList()) end)
    end
end
local json
do
    local ok, lib = pcall(require, "dkjson")
    if not ok then ok, lib = pcall(require, "cjson") end
    if ok and type(lib) == "table" and lib.encode and lib.decode then
        json = lib
    else

        local J = {}
        local esc = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
        local function escStr(s)
            return '"' .. s:gsub('[%c"\\]', function(c)
                return esc[c] or string.format("\\u%04x", c:byte())
            end) .. '"'
        end
        local function isArray(tb)
            local n = 0
            for k in pairs(tb) do
                if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
                n = n + 1
            end
            return n == #tb
        end
        local function enc(v, out)
            local tv = type(v)
            if tv == "nil" then out[#out+1] = "null"
            elseif tv == "boolean" then out[#out+1] = tostring(v)
            elseif tv == "number" then
                out[#out+1] = (v ~= v or v == math.huge or v == -math.huge) and "null" or string.format("%.14g", v)
            elseif tv == "string" then out[#out+1] = escStr(v)
            elseif tv == "table" then
                if next(v) == nil or isArray(v) then
                    out[#out+1] = "["
                    for i = 1, #v do
                        if i > 1 then out[#out+1] = "," end
                        enc(v[i], out)
                    end
                    out[#out+1] = "]"
                else
                    out[#out+1] = "{"
                    local first = true
                    for k, val in pairs(v) do
                        if not first then out[#out+1] = "," end
                        first = false
                        out[#out+1] = escStr(tostring(k)) .. ":"
                        enc(val, out)
                    end
                    out[#out+1] = "}"
                end
            else out[#out+1] = "null" end
        end
        function J.encode(v) local out = {}; enc(v, out); return table.concat(out) end

        local function u8c(cp)
            if cp < 0x80 then return string.char(cp)
            elseif cp < 0x800 then return string.char(0xC0 + math.floor(cp/64), 0x80 + cp % 64)
            elseif cp < 0x10000 then return string.char(0xE0 + math.floor(cp/4096), 0x80 + math.floor(cp/64) % 64, 0x80 + cp % 64)
            else return string.char(0xF0 + math.floor(cp/262144), 0x80 + math.floor(cp/4096) % 64, 0x80 + math.floor(cp/64) % 64, 0x80 + cp % 64) end
        end
        local function skip(s, i) return s:find("[^ \t\r\n]", i) or #s + 1 end
        local dec
        local function decStr(s, i)
            local buf, j = {}, i + 1
            while true do
                local c = s:find('["\\]', j)
                if not c then error("unterminated string") end
                buf[#buf+1] = s:sub(j, c - 1)
                if s:sub(c, c) == '"' then return table.concat(buf), c + 1 end
                local e = s:sub(c + 1, c + 1)
                if e == "u" then
                    local cp = tonumber(s:sub(c + 2, c + 5), 16)
                    if not cp then error("bad \\u escape") end
                    j = c + 6
                    if cp >= 0xD800 and cp < 0xDC00 and s:sub(j, j + 1) == "\\u" then
                        local lo = tonumber(s:sub(j + 2, j + 5), 16)
                        if lo and lo >= 0xDC00 and lo < 0xE000 then
                            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                            j = j + 6
                        end
                    end
                    buf[#buf+1] = u8c(cp)
                else
                    local map = { b="\b", f="\f", n="\n", r="\r", t="\t" }
                    buf[#buf+1] = map[e] or e
                    j = c + 2
                end
            end
        end
        dec = function(s, i)
            i = skip(s, i)
            local c = s:sub(i, i)
            if c == "{" then
                local o = {}
                i = skip(s, i + 1)
                if s:sub(i, i) == "}" then return o, i + 1 end
                while true do
                    i = skip(s, i)
                    if s:sub(i, i) ~= '"' then error("object key expected") end
                    local k; k, i = decStr(s, i)
                    i = skip(s, i)
                    if s:sub(i, i) ~= ":" then error("':' expected") end
                    local v; v, i = dec(s, i + 1)
                    o[k] = v
                    i = skip(s, i)
                    local d = s:sub(i, i)
                    if d == "," then i = i + 1
                    elseif d == "}" then return o, i + 1
                    else error("',' or '}' expected") end
                end
            elseif c == "[" then
                local a, n = {}, 0
                i = skip(s, i + 1)
                if s:sub(i, i) == "]" then return a, i + 1 end
                while true do
                    local v; v, i = dec(s, i)
                    n = n + 1; a[n] = v
                    if n % 6 == 0 and coroutine.running() then wait(0) end
                    i = skip(s, i)
                    local d = s:sub(i, i)
                    if d == "," then i = i + 1
                    elseif d == "]" then return a, i + 1
                    else error("',' or ']' expected") end
                end
            elseif c == '"' then return decStr(s, i)
            elseif s:sub(i, i + 3) == "true" then return true, i + 4
            elseif s:sub(i, i + 4) == "false" then return false, i + 5
            elseif s:sub(i, i + 3) == "null" then return nil, i + 4
            else
                local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
                if not num or num == "" then error("unexpected character at " .. i) end
                return tonumber(num), i + #num
            end
        end
        function J.decode(s)
            if type(s) ~= "string" then return nil, 1, "string expected" end
            if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
            local ok2, res = pcall(function() local v = dec(s, 1); return v end)
            if ok2 then return res, #s + 1 end
            return nil, 1, tostring(res)
        end
        json = J
    end
end
encoding.default = 'CP1251'
u8 = encoding.UTF8

CURRENT_VERSION = "2.6"

local GITHUB = {
    repo          = "EdwardDisney0/Edward-Scripts-New-Engine",
    branch        = "main",
    raw           = "https://raw.githubusercontent.com/",
    api           = "https://api.github.com/repos/",
    scripts_list  = "Sscripts.json",
    script_center = "Edward%20Script%20Center.luac",
    version       = "version.json",
    notification  = "notification.json",
}
local repo_sha      = nil

local function rawUrl(path)
    if repo_sha then
        return GITHUB.raw .. GITHUB.repo .. "/" .. repo_sha .. "/" .. path
    end
    return GITHUB.raw .. GITHUB.repo .. "/" .. GITHUB.branch .. "/" .. path .. "?t=" .. os.time()
end

local SCRIPT_CENTER_FILENAME = "Edward Script Center.luac"

local CONFIG_DIR = getWorkingDirectory() .. "/config/Edward Central Scripts"
local function ensureConfigDir()
    local base = getWorkingDirectory() .. "/config"
    if not doesDirectoryExist(base) then createDirectory(base) end
    if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end
end

local dlstatus_ok, dlstatus = pcall(function() return require('moonloader').download_status end)
dlstatus_ok = dlstatus_ok and dlstatus ~= nil and type(downloadUrlToFile) == "function"

do
    local okg, gd = pcall(function() return getGameDirectory() end)
    GAME_DIR = (okg and type(gd) == "string" and gd ~= "") and gd or getWorkingDirectory()
end
function sfCmd(cmd)
    if type(runSampfuncsConsoleCommand) == "function" then pcall(runSampfuncsConsoleCommand, cmd) end
end
function openUrl(url)
    pcall(function() imgui.SetClipboardText(url) end)
    pcall(function() sampAddChatMessage("{FF0000}|{FFFFFF} Ссылка скопирована в буфер: {C0C0C0}" .. url, 0xFFFFFF) end)
end

local http_tmp_counter = 0

local function cleanBody(s)
    s = tostring(s or "")
    if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
    return s
end

local function isBadBody(s)
    return s == "" or s:match("^%s*404: Not Found") ~= nil or s:match("^%s*400: Bad Request") ~= nil
end

local function httpViaRequests(url, on_success, on_error)
    local ok_e, effil = pcall(require, "effil")
    if ok_e and effil then
        local ok_t, handle = pcall(function()
            local runner = effil.thread(function(u)
                local okr, req = pcall(require, "requests")
                if not okr then return 0, "requests" end
                local ok2, resp = pcall(req.get, u)
                if ok2 and resp then return resp.status_code, resp.text end
                return 0, tostring(resp)
            end)
            return runner(url)
        end)
        if ok_t and handle then
            local waited = 0
            while true do
                local okst, st = pcall(function() return handle:status() end)
                if not okst or st == "failed" or st == "canceled" then
                    on_error("Нет соединения")
                    return
                elseif st == "completed" then
                    local okg, code, body = pcall(function() return handle:get() end)
                    body = cleanBody(body)
                    if okg and code == 200 and not isBadBody(body) then
                        on_success({ status_code = 200, text = body, content = body })
                    else
                        on_error(okg and ("Код: " .. tostring(code)) or "Нет соединения")
                    end
                    return
                end
                wait(50)
                waited = waited + 50
                if waited > 20000 then
                    pcall(function() handle:cancel() end)
                    on_error("Таймаут соединения")
                    return
                end
            end
        end
    end

    local okq, requests = pcall(require, "requests")
    if not okq or not requests then on_error("Нет соединения"); return end
    local ok, response = pcall(requests.get, url)
    if ok and response and response.status_code == 200 then
        local body = cleanBody(response.text or response.content)
        if isBadBody(body) then on_error("Пустой ответ"); return end
        on_success({ status_code = 200, text = body, content = body })
    else
        on_error(ok and ("Код: " .. tostring(response and response.status_code)) or "Нет соединения")
    end
end

local function httpGetAsync(url, on_success, on_error)
    if not dlstatus_ok then
        return httpViaRequests(url, on_success, on_error)
    end

    ensureConfigDir()
    http_tmp_counter = http_tmp_counter + 1
    local tmp_path = CONFIG_DIR .. "/_http_" .. tostring(os.clock()):gsub("[^%d]", "") .. "_" .. http_tmp_counter .. ".tmp"
    if doesFileExist(tmp_path) then os.remove(tmp_path) end

    local data_received = false
    local finished = false

    local okd = pcall(downloadUrlToFile, url, tmp_path, function(id, status, p1, p2)
        if status == dlstatus.STATUS_ENDDOWNLOADDATA then
            data_received = true
        elseif status == dlstatus.STATUSEX_ENDDOWNLOAD then
            finished = true
        end
    end)

    local content = ""
    if okd then
        local waited = 0
        while not finished do
            wait(50)
            waited = waited + 50

            if data_received and waited > 1500 then break end
            if waited > 12000 then break end
        end
        wait(30)
        if doesFileExist(tmp_path) then
            local f = io.open(tmp_path, "rb")
            if f then content = cleanBody(f:read("*a")); f:close() end
            os.remove(tmp_path)
        end
    end

    if not isBadBody(content) then
        on_success({ status_code = 200, text = content, content = content })
        return
    end

    httpViaRequests(url, on_success, on_error)
end

local INSTALL_PATHS = {
    moonloader = getWorkingDirectory(),
    cleo       = GAME_DIR .. "/cleo",
    root       = GAME_DIR
}

local CACHE_FILE         = CONFIG_DIR .. "/scripts_cache.json"
local NOTIFICATION_CACHE = CONFIG_DIR .. "/notification_cache.json"
local VERSION_FILE       = CONFIG_DIR .. "/version.txt"
local SETTINGS_FILE      = CONFIG_DIR .. "/settings.json"

local settings = {
    notifications    = true,
    auto_update      = true,
    auto_list_update = true,
    accent_r = 226, accent_g = 32, accent_b = 40,
    ui_scale = 0,
}

local toggle_anim = {
    notifications    = 1.0,
    auto_update      = 1.0,
    auto_list_update = 1.0,
}

function saveSettings()
    ensureConfigDir()
    local f = io.open(SETTINGS_FILE, "w")
    if f then
        f:write(string.format(
            '{"notifications":%s,"auto_update":%s,"auto_list_update":%s,"accent_r":%d,"accent_g":%d,"accent_b":%d,"ui_scale":%s}',
            tostring(settings.notifications),
            tostring(settings.auto_update),
            tostring(settings.auto_list_update),
            settings.accent_r, settings.accent_g, settings.accent_b,
            string.format("%.2f", tonumber(settings.ui_scale) or 0)
        ))
        f:close()
    end
end

function loadSettings()
    local f = io.open(SETTINGS_FILE, "r")
    if not f then return end
    local c = f:read("*all"); f:close()
    local function rb(key, def)
        local v = c:match('"' .. key .. '"%s*:%s*(%a+)')
        if v == "true" then return true end
        if v == "false" then return false end
        return def
    end
    settings.notifications    = rb("notifications",    true)
    settings.auto_update      = rb("auto_update",      true)
    settings.auto_list_update = rb("auto_list_update", true)
    local function rn(key, def)
        local v = tonumber(c:match('"' .. key .. '"%s*:%s*(%d+)') or "")
        if v and v >= 0 and v <= 255 then return v end
        return def
    end
    settings.accent_r = rn("accent_r", 226)
    settings.accent_g = rn("accent_g", 32)
    settings.accent_b = rn("accent_b", 40)
    settings.ui_scale = tonumber(c:match('"ui_scale"%s*:%s*([%d%.]+)') or "") or 0
    toggle_anim.notifications    = settings.notifications    and 1.0 or 0.0
    toggle_anim.auto_update      = settings.auto_update      and 1.0 or 0.0
    toggle_anim.auto_list_update = settings.auto_list_update and 1.0 or 0.0
end

local function notify(msg)
    if settings.notifications then
        sampAddChatMessage(msg, 0xFFFFFF)
    end
end

local main_window         = imgui.new.bool(false)
local notification_window = imgui.new.bool(false)

local main_active_tab = 0

local scripts_list     = {}
local filtered_scripts = {}
local loading          = false
local conn_ok          = true
local status_text      = u8"Нажмите 'Обновить список' для загрузки скриптов"
local search_text      = imgui.new.char[256]()

local selected_script_file = nil
local library_filter       = "all"
local category_filter      = nil
local sort_mode            = 0

local notification_text             = ""
local notification_pass             = ""
local notification_update_url       = ""
local notification_required_version = ""
local has_new_notification          = false

local update_in_progress = false
local update_done        = false

local connected_to_server = false
local check_delay_passed  = false

local install_cache       = {}
local install_cache_dirty = true

local function checkInstalledOne(s, out)
    local ip  = INSTALL_PATHS[s.install_type or "moonloader"] or INSTALL_PATHS.moonloader
    local f   = io.open(ip .. "/" .. s.file, "r")
    if f then
        f:close()
        out[s.file] = true
    elseif s.old_file and s.old_file ~= "" then
        local of = io.open(ip .. "/" .. s.old_file, "r")
        if of then of:close(); out[s.file] = true
        else out[s.file] = false end
    else
        out[s.file] = false
    end
end

local install_rebuilding = false
local function rebuildInstallCacheAsync()
    if install_rebuilding then return end
    install_rebuilding = true
    install_cache_dirty = false
    lua_thread.create(function()
        local list = scripts_list
        local out = {}
        for i = 1, #list do
            checkInstalledOne(list[i], out)
            if i % 6 == 0 then wait(0) end
        end
        install_cache = out
        UIX.stats_dirty = true
        install_rebuilding = false
    end)
end

local function invalidateInstallCache()
    install_cache_dirty = true
    UIX.stats_dirty = true
end

function isScriptInstalled(si)
    if install_cache_dirty then rebuildInstallCacheAsync() end
    return install_cache[si.file] or false, nil
end

function decodeJson(jsonString)
    local ok, decoded = pcall(function() return (json.decode(jsonString)) end)
    if ok and type(decoded) == "table" then return decoded end
    local scripts = {}
    for block in jsonString:gmatch('{[^{}]*}') do
        local s = {}
        for k, v in block:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do s[k]=v end
        if s.name and s.file then table.insert(scripts, s) end
    end
    return {scripts=scripts}
end

function sortScriptsByStatus()
    table.sort(scripts_list, function(a, b)
        local as = tonumber(a.status) or 0
        local bs = tonumber(b.status) or 0
        if as ~= bs then return as > bs end
        return (a.name or "") < (b.name or "")
    end)
end

local parseHashtags
do
local tags_cache = {}
local EMPTY_TAGS = {}
parseHashtags = function(s)
    if not s or s == "" then return EMPTY_TAGS end
    local cached = tags_cache[s]
    if cached then return cached end
    local tags = {}
    tags_cache[s] = tags
    for tag in s:gmatch("#([%w\128-\255_]+)") do
        table.insert(tags, tag)
    end
    if #tags == 0 then
        for tag in s:gmatch("([%w\128-\255_]+)") do
            table.insert(tags, tag)
        end
    end
    return tags
end
end

local function buildCategories()
    local counts, order = {}, {}
    for _, s in ipairs(scripts_list) do
        if not (s.delete and (s.delete=="true" or s.delete==true or s.delete=="1")) then
            for _, tag in ipairs(parseHashtags(s.hashtags)) do
                if not counts[tag] then counts[tag]=0; table.insert(order, tag) end
                counts[tag] = counts[tag] + 1
            end
        end
    end
    local cats = {}
    for _, tag in ipairs(order) do table.insert(cats, {name=tag, count=counts[tag]}) end
    table.sort(cats, function(a,b) return a.count > b.count end)
    return cats
end

local function countInstalledScripts()
    local n = 0
    for _, s in ipairs(scripts_list) do
        if not (s.delete and (s.delete=="true" or s.delete==true or s.delete=="1")) and isScriptInstalled(s) then
            n = n + 1
        end
    end
    return n
end

function syncWithGitHub()
    local new_sha = nil
    httpGetAsync(GITHUB.api .. GITHUB.repo .. "/git/refs/heads/" .. GITHUB.branch .. "?t=" .. os.time(),
        function(r) new_sha = (r.text or ""):match('"sha"%s*:%s*"(%x+)"') end,
        function(err) end)
    if new_sha then repo_sha = new_sha; return true end
    return false
end

local function lower1251(str)
    str = (str or ""):lower()
    str = str:gsub("[\192-\223]", function(c) return string.char(c:byte() + 32) end)
    str = str:gsub("\168", "\184")
    return str
end

function filterScripts()
    local q = lower1251(u8:decode(ffi.string(search_text))):gsub("^%s+", ""):gsub("%s+$", "")
    q = q:gsub("^#", "")

    local function visible(s)
        if s.delete and (s.delete=="true" or s.delete==true or s.delete=="1") then return false end
        if library_filter == "installed" and not isScriptInstalled(s) then return false end
        if category_filter then
            local ok = false
            for _, tag in ipairs(parseHashtags(s.hashtags)) do
                if tag == category_filter then ok = true; break end
            end
            if not ok then return false end
        end
        return true
    end

    local function has(text, query)
        if query == "" then return true end
        if not text or text == "" then return false end
        return lower1251(text):find(query, 1, true) ~= nil
    end

    filtered_scripts = {}
    for _, s in ipairs(scripts_list) do
        if visible(s) and (has(s.name,q) or has(s.description,q) or has(s.author,q) or has(s.hashtags,q)) then
            table.insert(filtered_scripts, s)
        end
    end

    if sort_mode == 1 then
        table.sort(filtered_scripts, function(a,b) return (a.name or "") < (b.name or "") end)
    else
        table.sort(filtered_scripts, function(a,b)
            local as = tonumber(a.status) or 0
            local bs = tonumber(b.status) or 0
            if as ~= bs then return as > bs end
            return (a.name or "") < (b.name or "")
        end)
    end
end

function getInstallPath(si)
    return INSTALL_PATHS[si.install_type or "moonloader"] or INSTALL_PATHS.moonloader
end
function getScriptTypeName(si)
    return ({moonloader="MoonLoader",cleo="CLEO",root="Root"})[si.install_type or "moonloader"] or "MoonLoader"
end
function getVisibleScriptsCount()
    local n = 0
    for _, s in ipairs(scripts_list) do
        if not (s.delete and (s.delete=="true" or s.delete==true or s.delete=="1")) then n=n+1 end
    end
    return n
end

function saveCurrentVersion()
    local f = io.open(VERSION_FILE,"w")
    if f then f:write(CURRENT_VERSION); f:close() end
end
function loadSavedVersion()
    local f = io.open(VERSION_FILE,"r")
    if f then local v=f:read("*all"); f:close(); return v end
    return CURRENT_VERSION
end
function saveCachedScripts()
    ensureConfigDir()
    local f = io.open(CACHE_FILE,"w")
    if not f then return end

    local function clean(v)
        local r = tostring(v or ""):gsub("\r", ""):gsub("\n", "\\n"):gsub('"', "'")
        return r
    end
    local parts = {}
    for _, sc in ipairs(scripts_list) do
        parts[#parts+1] = string.format(
            '{"name":"%s","file":"%s","description":"%s","author":"%s","version":"%s",'..
            '"install_type":"%s","telegram":"%s","status":"%s","delete":"%s","info":"%s","hashtags":"%s","image":"%s","old_file":"%s"}',
            clean(sc.name),clean(sc.file),clean(sc.description),clean(sc.author),clean(sc.version),
            clean(sc.install_type or "moonloader"),clean(sc.telegram),
            clean(sc.status or "0"),clean(sc.delete or "false"),clean(sc.info),clean(sc.hashtags),
            clean(sc.image),clean(sc.old_file))
    end
    f:write('{"scripts":[' .. table.concat(parts, ",") .. ']}'); f:close()
end
function loadCachedScripts()
    local f = io.open(CACHE_FILE,"r")
    if not f then return end
    local c=f:read("*all"); f:close()
    local data=decodeJson(c)
    if data and data.scripts then
        scripts_list=data.scripts
        sortScriptsByStatus(); filterScripts(); invalidateInstallCache()
        status_text=u8("Загружено: "..#filtered_scripts.." скриптов")
    end
end
function saveNotificationCache(pass,message)
    ensureConfigDir()
    pass    = tostring(pass == nil and "" or pass)
    message = tostring(message == nil and "" or message)
    local f=io.open(NOTIFICATION_CACHE,"w")
    if f then
        f:write(json.encode({pass = pass, message = message, timestamp = os.time()}))
        f:close()
    end
end
function loadNotificationCache()
    local f=io.open(NOTIFICATION_CACHE,"r")
    if f then
        local c=f:read("*all"); f:close()
        local d=decodeJson(c)
        if type(d)=="table" and d.pass ~= nil then
            d.pass = tostring(d.pass)
            d.message = tostring(d.message or "")
            return d
        end
    end
    return {pass="",message="",timestamp=0}
end

local function parseScriptCenterName(filename)
    local base, ext = filename:match("^(.-)%s*%(%d+%)%.([^%.]+)$")
    if base and ext then return base, ext end
    base, ext = filename:match("^(.+)%.([^%.]+)$")
    if base and ext then return base, ext end
    return filename, ""
end

local function findAllScriptCenterFiles()
    local dir = getWorkingDirectory()
    local canonical = SCRIPT_CENTER_FILENAME
    local base_name, base_ext = parseScriptCenterName(canonical)
    local found = {}
    local seen  = {}
    local function tryAdd(path)
        if seen[path] then return end
        local f = io.open(path, "rb")
        if f then f:close(); seen[path]=true; table.insert(found, path) end
    end
    tryAdd(dir .. "/" .. canonical)
    tryAdd(dir .. "/" .. base_name .. ".lua")
    for n = 1, 50 do
        tryAdd(dir .. "/" .. base_name .. " (" .. n .. ")." .. base_ext)
        tryAdd(dir .. "/" .. base_name .. " (" .. n .. ").lua")
    end
    return found
end

local function verNum(v)
    v = tostring(v or ""):gsub("^%s*[vV]?", "")
    local a, b, c = v:match("^(%d+)%.?(%d*)%.?(%d*)")
    return (tonumber(a) or 0) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end

local function trimVer(v) return (tostring(v or ""):gsub("%s+", "")) end

local function isTrue(v)
    return v == true or v == 1 or v == "true" or v == "1" or v == "True" or v == "TRUE"
end

function checkScriptCenterUpdate(quiet)
    if not connected_to_server or not check_delay_passed then return end
    if update_done or update_in_progress then return end
    if not quiet then notify("{FF0000}|{FFFFFF} Проверяю обновления {C0C0C0}Script Center...") end

    httpGetAsync(rawUrl(GITHUB.version),
        function(response)
            local data = decodeJson(encoding.UTF8:decode(response.text))
            if data and data.version then
                local latest  = trimVer(data.version)
                local current = trimVer(CURRENT_VERSION)
                if verNum(latest) > verNum(current) then
                    notify("{FF0000}|{FFFFFF} {00FF00}Доступна новая версия: {C0C0C0}v" .. latest)
                    notify("{FF0000}|{FFFFFF} Текущая версия: {C0C0C0}v" .. current)
                    local url = tostring(data.update_url or data.url or "")
                    if url ~= "" then
                        notification_update_url = url
                        notification_required_version = latest
                        notification_text = tostring(data.message or ("Доступна новая версия Edward Script Center Mobile v" .. latest))
                        notification_pass = "VERSION_CHECK_" .. latest
                        local cached = loadNotificationCache()
                        if cached.pass ~= notification_pass then
                            has_new_notification = true
                            notification_window[0] = true
                        end
                    end
                else
                    local cached = loadNotificationCache()
                    if cached.pass and cached.pass:find("VERSION_CHECK_") then saveNotificationCache("", "") end
                    if not quiet then notify("{FF0000}|{FFFFFF} У вас установлена {00FF00}последняя версия {C0C0C0}v" .. current) end
                end
            elseif not quiet then
                notify("{FF0000}|{FFFFFF} Не удалось {C0C0C0}прочитать version.json")
            end
        end,
        function(err)
            if not quiet then notify("{FF0000}|{FFFFFF} Не удалось проверить обновления {C0C0C0}Script Center: " .. tostring(err)) end
        end
    )
end

function checkForNotification(no_wait)
    if not connected_to_server or not check_delay_passed then return end
    if not settings.notifications then return end
    if not no_wait then wait(8000) end

    httpGetAsync(rawUrl(GITHUB.notification),
        function(response)
            local data = decodeJson(encoding.UTF8:decode(response.text))
            if data and data.message and isTrue(data.enabled) and data.pass ~= nil then
                local github_pass    = tostring(data.pass)
                local github_message = tostring(data.message)
                local github_upd_url = tostring(data.update_url or "")
                local github_req_ver = trimVer(data.required_version)
                local cached         = loadNotificationCache()
                local cur_ver        = trimVer(CURRENT_VERSION)
                notification_text             = github_message
                notification_pass             = github_pass
                notification_update_url       = github_upd_url
                notification_required_version = github_req_ver
                local ver_mismatch = false
                if github_req_ver ~= "" then
                    local function pv(ver) return verNum(ver) end
                    if pv(cur_ver) < pv(github_req_ver) then
                        ver_mismatch = true
                        notify("{FF0000}|{FFFFFF} {FF0000}ТРЕБУЕТСЯ ОБНОВЛЕНИЕ!")
                        notify("{FF0000}|{FFFFFF} {C0C0C0}Текущая версия: v"..cur_ver)
                    end
                end
                if ver_mismatch then
                    wait(2000); notification_window[0]=true; has_new_notification=true
                    notify("{FF0000}|{FFFFFF} {FF0000}ВНИМАНИЕ! {FFFFFF}Требуется обновление {C0C0C0}Script Center! {FFFFFF}Откройте {C0C0C0}/ec")
                    saveNotificationCache("VERSION_CHECK_"..github_req_ver, github_message)
                elseif github_pass ~= (cached.pass or "") then
                    notification_window[0]=true; has_new_notification=true
                    notify("{FF0000}|{FFFFFF} {FFFFFF}Новое уведомление от {C0C0C0}разработчика! {FFFFFF}Откройте {C0C0C0}/ec")
                else
                    has_new_notification=false
                end
            else
                notification_text=""; notification_pass=""
                notification_update_url=""; notification_required_version=""
                has_new_notification=false
            end
        end,
        function(err)
            notify("{FF0000}|{FFFFFF} Не удалось {C0C0C0}проверить уведомления: " .. tostring(err))
        end
    )
end

function loadScriptsListNow(quiet, force)
    if not connected_to_server or not check_delay_passed then return end
    if not settings.auto_list_update and not force then
        if not quiet then notify("{FF0000}|{FFFFFF} {C0C0C0}Загрузка списка при запуске отключена в настройках") end
        return
    end
    loading=true
    status_text=u8"Загружаю список скриптов..."
    if not quiet then notify("{FF0000}|{FFFFFF} Загружаю {C0C0C0}список скриптов...") end

    httpGetAsync(rawUrl(GITHUB.scripts_list),
        function(response)
            local data = decodeJson(encoding.UTF8:decode(response.text))
            if data and data.scripts then
                scripts_list=data.scripts
                checkAndDeleteMarkedScripts(); wait(500)
                sortScriptsByStatus(); filterScripts(); invalidateInstallCache()
                status_text=u8("Загружено скриптов: "..#filtered_scripts.."  |  обновлено в "..os.date("%H:%M:%S"))
                if not quiet then notify("{FF0000}|{FFFFFF} Загружено {C0C0C0}"..#filtered_scripts.."{FFFFFF} скриптов") end
                wait(150); saveCachedScripts()
                conn_ok=true
            else
                status_text=u8"Ошибка: Не удалось прочитать JSON"
                if not quiet then notify("{FF0000}|{FFFFFF} Ошибка {C0C0C0}парсинга JSON") end
            end
            loading=false
        end,
        function(err)
            status_text=u8"Ошибка загрузки: "..err
            if not quiet then notify("{FF0000}|{FFFFFF} Ошибка загрузки: {C0C0C0}"..err) end
            loading=false
            conn_ok=false
        end
    )
end

function loadScriptsList()
    lua_thread.create(function() loadScriptsListNow(false) end)
end

local function unloadScriptIfLoaded(filename)
    local ok_iter, list = pcall(script.list)
    if not ok_iter or not list then return false end
    for _, scr in ipairs(list) do
        if scr.filename == filename then
            local ok = pcall(function() scr:unload() end)
            if not ok then pcall(function() scr:remove() end) end
            return true
        end
    end
    return false
end

function checkAndDeleteMarkedScripts()
    if not scripts_list or #scripts_list==0 then return end
    local n=0
    for _, s in ipairs(scripts_list) do
        if s.delete and (s.delete=="true" or s.delete==true or s.delete=="1") then
            local ip=getInstallPath(s); local path=ip.."/"..s.file
            local fc=io.open(path,"r")
            if fc then
                fc:close()
                if (not s.install_type or s.install_type=="moonloader") and unloadScriptIfLoaded(s.file) then
                    wait(300)
                end
                if os.remove(path) then
                    n=n+1
                    sampAddChatMessage("{FF0000}|{FFFFFF} Автоудаление: {C0C0C0}"..s.name.." {FFFFFF}удалён",0xFFFFFF)
                    wait(100)
                else
                    sampAddChatMessage("{FF0000}|{FFFFFF} Ошибка автоудаления: {C0C0C0}"..s.name,0xFFFFFF)
                end
            end
            if s.old_file and s.old_file~="" then
                local op=ip.."/"..s.old_file; local of=io.open(op,"r")
                if of then
                    of:close()
                    if os.remove(op) then
                        sampAddChatMessage("{FF0000}|{FFFFFF} Старая версия {C0C0C0}"..s.old_file.." {FFFFFF}удалена",0xFFFFFF)
                        wait(100)
                    end
                end
            end
        end
    end
    if n>0 then
        sampAddChatMessage("{FF0000}|{FFFFFF} Автоудаление завершено: удалено {C0C0C0}"..n.." {FFFFFF}скриптов",0xFFFFFF)
        sampAddChatMessage("{FF0000}|{FFFFFF} Перезагрузите скрипты {C0C0C0}(MoonLoader) {FFFFFF}для применения",0xFFFFFF)
        invalidateInstallCache()
    end
end

local function checkAsiConflict(script_info)
    local base = script_info.file:match("^(.+)%.[^%.]+$") or script_info.file
    local asi_name = base .. ".asi"
    local asi_path = GAME_DIR .. "/" .. asi_name
    local f = io.open(asi_path, "rb")
    if f then f:close(); return true, asi_name, asi_path end
    return false, asi_name, asi_path
end

local function reportAsiConflict(script_info, asi_name)
    sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}ОШИБКА! {FFFFFF}Действие заблокировано.", 0xFFFFFF)
    sampAddChatMessage("{FF0000}|{FFFFFF} В корне игры найден файл: {FF0000}"..asi_name, 0xFFFFFF)
    sampAddChatMessage("{FF0000}|{FFFFFF} Удалите {C0C0C0}"..asi_name.." {FFFFFF}вручную из папки GTA SA", 0xFFFFFF)
    status_text = u8("Ошибка: найден "..asi_name.." в корне игры — удалите вручную")
end

function downloadScript(script_info, is_update)
    local asi_found, asi_name = checkAsiConflict(script_info)
    if asi_found then reportAsiConflict(script_info, asi_name); return end

    lua_thread.create(function()
        if script_info.install_type == "root" then
            local ip_pre = getInstallPath(script_info)
            local pre_f = io.open(ip_pre .. "/" .. script_info.file, "rb")
            if pre_f then
                pre_f:close()
                sampAddChatMessage("{FF0000}|{FFFFFF} ASI: {FF8800}выгружаю для обновления...", 0xFFFFFF)
                sfCmd("pfree " .. script_info.file)
                wait(800)
            end
        end

        loading=true
        local name=script_info.name
        local action=is_update and "Обновляю" or "Скачиваю"
        local ip=getInstallPath(script_info)
        local type_name=getScriptTypeName(script_info)
        local install_type=script_info.install_type or "moonloader"
        local del_dup=false
        if script_info.old_file and script_info.old_file~="" then
            local op=ip.."/"..script_info.old_file
            local of=io.open(op,"r")
            if of then
                of:close()
                sampAddChatMessage("{FF0000}|{FFFFFF} Удаляю {C0C0C0}старый файл...",0xFFFFFF)
                wait(200)
                if os.remove(op) then sampAddChatMessage("{FF0000}|{FFFFFF} Старый файл {00FF00}удалён!",0xFFFFFF); wait(300)
                else sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}Ошибка удаления старого файла!",0xFFFFFF) end
            end
        end
        local base=script_info.file:match("(.+)%.[^%.]+$") or script_info.file
        local ext=script_info.file:match("%.([^%.]+)$") or ""
        for i=1,50 do
            local dup=base.." ("..i..")."..ext
            local dp=ip.."/"..dup
            local df=io.open(dp,"r")
            if df then
                df:close()
                sampAddChatMessage("{FF0000}|{FFFFFF} Найден дубликат: {C0C0C0}"..dup,0xFFFFFF)
                if os.remove(dp) then sampAddChatMessage("{FF0000}|{FFFFFF} Дубликат {00FF00}удалён!",0xFFFFFF); del_dup=true; wait(100) end
            end
        end
        status_text=u8(action..": "..name.." ("..type_name..")")
        sampAddChatMessage("{FF0000}|{FFFFFF} "..action.." {C0C0C0}"..name.." {FFFFFF}в {C0C0C0}"..type_name,0xFFFFFF)
        local encoded=script_info.file:gsub(" ","%%20")
        local url=rawUrl(encoded)
        local binary=script_info.file:match("%.luac$") or script_info.file:match("%.cs$") or
                     script_info.file:match("%.cleo$") or script_info.file:match("%.asi$") or
                     script_info.file:match("%.dll$")

        httpGetAsync(url,
            function(response)
                local path=ip.."/"..script_info.file
                local outf=io.open(path,"wb")
                if outf then
                    local content=binary and response.content or response.text
                    if content then
                        outf:write(content); outf:close(); invalidateInstallCache()
                        local res=is_update and "обновлен" or "скачан"
                        if script_info.old_file and script_info.old_file~="" then
                            sampAddChatMessage("{FF0000}|{FFFFFF} Скрипт {C0C0C0}"..name.."{FFFFFF} успешно {00FF00}обновлён с новым названием!",0xFFFFFF)
                        else
                            sampAddChatMessage("{FF0000}|{FFFFFF} Скрипт {C0C0C0}"..name.."{FFFFFF} успешно {00FF00}"..res.."!",0xFFFFFF)
                        end
                        if install_type == "moonloader" then
                            wait(300)
                            local script_filename = script_info.file
                            if del_dup then
                                status_text = u8"Обнаружены дубликаты! Делаю полную перезагрузку..."
                                sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}ВНИМАНИЕ! {FFFFFF}Дубликаты — полная перезагрузка...",0xFFFFFF)
                                wait(500); reloadScripts()
                            else
                                local already_loaded = false
                                for _, scr in ipairs(script.list()) do
                                    if scr.filename == script_filename then
                                        already_loaded = true
                                        sampAddChatMessage("{FF0000}|{FFFFFF} Перезагружаю только {C0C0C0}"..name.."...",0xFFFFFF)
                                        wait(300); scr:reload()
                                        status_text = u8(res:gsub("^%l",string.upper).."! Перезагружен")
                                        sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Скрипт перезагружен!",0xFFFFFF)
                                        break
                                    end
                                end
                                if not already_loaded then
                                    sampAddChatMessage("{FF0000}|{FFFFFF} Загружаю {C0C0C0}"..name.." {FFFFFF}впервые...",0xFFFFFF)
                                    wait(300); script.load(script_filename)
                                    status_text = u8(res:gsub("^%l",string.upper).."! Загружен")
                                    sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Скрипт загружен!",0xFFFFFF)
                                end
                            end
                        elseif install_type=="cleo" then
                            status_text=u8(res:gsub("^%l",string.upper).."! CLEO загружается...")
                            sampAddChatMessage("{FF0000}|{FFFFFF} CLEO-скрипт загружается...",0xFFFFFF)
                            lua_thread.create(function()
                                wait(500); sfCmd("cs "..script_info.file.." 1")
                                wait(300); sampAddChatMessage("{FF0000}|{FFFFFF} CLEO-скрипт {00FF00}активирован!",0xFFFFFF)
                            end)
                        elseif install_type=="root" then
                            local asi_filename = script_info.file
                            status_text = u8"ASI: загружаю плагин..."
                            sampAddChatMessage("{FF0000}|{FFFFFF} ASI: {C0C0C0}загружаю плагин...", 0xFFFFFF)
                            wait(600)
                            sfCmd("pload " .. asi_filename)
                            wait(500)
                            status_text = u8("ASI загружен: " .. asi_filename)
                            sampAddChatMessage("{FF0000}|{FFFFFF} ASI: {00FF00}загружен! {C0C0C0}" .. asi_filename, 0xFFFFFF)
                        end
                    else
                        status_text=u8"Ошибка: Файл пуст"
                        sampAddChatMessage("{FF0000}|{FFFFFF} Ошибка: файл пустой",0xFFFFFF)
                        outf:close(); os.remove(path)
                    end
                else
                    status_text=u8"Ошибка: Не удалось сохранить файл"
                    sampAddChatMessage("{FF0000}|{FFFFFF} Ошибка сохранения файла",0xFFFFFF)
                end
                loading=false
            end,
            function(err)
                status_text=u8"Ошибка скачивания: "..err
                sampAddChatMessage("{FF0000}|{FFFFFF} Ошибка скачивания: {C0C0C0}"..err,0xFFFFFF)
                loading=false
            end
        )
    end)
end

function updateScript(si) downloadScript(si, true) end

function deleteScript(si)
    local asi_found, asi_name = checkAsiConflict(si)
    if asi_found then reportAsiConflict(si, asi_name); return end

    lua_thread.create(function()
        local ip=getInstallPath(si); local deleted=false

        if not si.install_type or si.install_type=="moonloader" then
            if unloadScriptIfLoaded(si.file) then wait(300) end
            if si.old_file and si.old_file~="" and unloadScriptIfLoaded(si.old_file) then
                wait(300)
            end
        end

        if os.remove(ip.."/"..si.file) then
            deleted=true
            sampAddChatMessage("{FF0000}|{FFFFFF} Скрипт {C0C0C0}"..si.name.."{FFFFFF} удалён",0xFFFFFF)
        end
        if si.old_file and si.old_file~="" then
            if os.remove(ip.."/"..si.old_file) then
                deleted=true
                sampAddChatMessage("{FF0000}|{FFFFFF} Старая версия {C0C0C0}"..si.old_file.."{FFFFFF} удалена",0xFFFFFF)
            end
        end
        if deleted then status_text=u8"Скрипт удален"; invalidateInstallCache()
        else
            status_text=u8"Ошибка: Файл не найден"
            sampAddChatMessage("{FF0000}|{FFFFFF} {C0C0C0}Файл не найден",0xFFFFFF)
        end
    end)
end

function downloadScriptCenterUpdate(new_version)
    if update_in_progress then sampAddChatMessage("{FF0000}|{FFFFFF} {FF8800}Обновление уже выполняется...", 0xFFFFFF); return end
    if update_done then sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Скрипт уже обновлён.", 0xFFFFFF); return end
    update_in_progress = true
    local dir    = getWorkingDirectory()
    local target = dir .. "/" .. SCRIPT_CENTER_FILENAME
    local backup = target .. ".bak"
    sampAddChatMessage("{FF0000}|{FFFFFF} Скачиваю {C0C0C0}новую версию v"..new_version.."...", 0xFFFFFF)
    local all_existing = findAllScriptCenterFiles()

    httpGetAsync(rawUrl(GITHUB.script_center),
        function(response)
            local content = response.content or response.text
            if not content or content == "" then
                sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}Ошибка: скачанный файл пуст!", 0xFFFFFF)
                update_in_progress = false; return
            end
            os.remove(backup)
            local has_canonical = false
            do local fc = io.open(target, "rb"); if fc then fc:close(); has_canonical = true end end
            if has_canonical then
                if not os.rename(target, backup) then os.remove(target) end
                wait(150)
            end
            for _, path in ipairs(all_existing) do
                if path ~= target and path ~= backup then os.remove(path); wait(80) end
            end
            wait(200)
            local outf = io.open(target, "wb")
            if not outf then
                sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}Ошибка: не удалось создать файл!", 0xFFFFFF)
                if has_canonical then os.rename(backup, target) end
                update_in_progress = false; return
            end
            outf:write(content); outf:close(); wait(200)
            local verify = io.open(target, "rb")
            if not verify then
                sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}Верификация провалена!", 0xFFFFFF)
                if has_canonical then os.rename(backup, target) end
                update_in_progress = false; return
            end
            local file_size = verify:seek("end"); verify:close()
            if not file_size or file_size == 0 then
                sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}Файл пустой!", 0xFFFFFF)
                os.remove(target); if has_canonical then os.rename(backup, target) end
                update_in_progress = false; return
            end
            os.remove(backup)
            local vf = io.open(VERSION_FILE, "w"); if vf then vf:write(new_version); vf:close() end
            local leftover = findAllScriptCenterFiles()
            for _, path in ipairs(leftover) do
                if path ~= target then os.remove(path); wait(50) end
            end
            update_in_progress = false; update_done = true
            sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Обновление установлено! v"..new_version, 0xFFFFFF)
            sampAddChatMessage("{FF0000}|{FFFFFF} Перезагрузка через 2 секунды...", 0xFFFFFF)
            wait(2000); thisScript():reload()
        end,
        function(err)
            sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}Ошибка скачивания: {C0C0C0}"..err, 0xFFFFFF)
            update_in_progress = false
        end
    )
end

local manual_busy = false
function manualRefresh()
    if manual_busy or loading or update_in_progress then return end
    manual_busy = true
    lua_thread.create(function()
        syncWithGitHub()
        loadScriptsListNow(false, true)
        checkForNotification(true)
        checkScriptCenterUpdate(false)
        manual_busy = false
    end)
end

local V2 = imgui.ImVec2
local F = {}

local FA_CODES = {
    grid = 0xf009,  list = 0xf0ca,  installed = 0xf058, cart = 0xf07a,
    gear = 0xf013,  monitor = 0xf108, gamepad = 0xf11b, dots = 0xf141,  tag = 0xf292,
    search = 0xf002, sort = 0xf160, chevron = 0xf078, check = 0xf00c,  close = 0xf00d,
    plus = 0xf067,  download = 0xf019, refresh = 0xf2f1, trash = 0xf2ed, plane = 0xf1d8,
    info = 0xf05a,  edit = 0xf304,  bell = 0xf0f3,   shop = 0xf54e,    market = 0xf54f,
    helper = 0xf1cd, hands = 0xf4c4, star = 0xf005,  coin = 0xf51e,    log = 0xf15c,
    airplane = 0xf072, eye = 0xf06e, bag = 0xf49e,   shield = 0xf3ed,  chip = 0xf2db,
    gun = 0xf05b,   robot = 0xf544, tshirt = 0xf553, dice = 0xf522,
}

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

imgui.OnInitialize(function()
    pcall(function()
        local ov = nil
        local f = io.open(SETTINGS_FILE, "r")
        if f then
            local c = f:read("*a"); f:close()
            ov = tonumber(c:match('"ui_scale"%s*:%s*([%d%.]+)'))
        end
        local s0 = UIX.calcScale(ov)
        UIX.auto = UIX.calcScale(nil)
        UIX.B = s0
        UIX.maxS = math.min(4, s0 * 1.6)
        UIX.init(s0)
    end)
    local io = imgui.GetIO()

    local ok_r, ranges = pcall(function()
        return imgui.new.ImWchar[19]({
            0x0020, 0x007E,
            0x00A0, 0x00BF,
            0x0401, 0x0401,
            0x0410, 0x044F,
            0x0451, 0x0451,
            0x2010, 0x2027,
            0x2030, 0x203A,
            0x2116, 0x2116,
            0x20BD, 0x20BD,
            0 })
    end)
    if ok_r and ranges then
        F._text_ranges = ranges
    else
        ok_r, ranges = pcall(function() return io.Fonts:GetGlyphRangesCyrillic() end)
    end
    if not ok_r or not ranges then return end
    local cfg = nil
    pcall(function()
        cfg = imgui.ImFontConfig()
        cfg.OversampleH = 1
        cfg.OversampleV = 1
        cfg.PixelSnapH = true
    end)
    F._cfg = cfg
    local font_dirs = {}
    do
        local okf, fdir = pcall(function() return getFolderPath(0x14) end)
        if okf and type(fdir) == "string" and fdir ~= "" then font_dirs[#font_dirs+1] = fdir end
        local wd = getWorkingDirectory()
        font_dirs[#font_dirs+1] = wd .. "/resource/fonts"
        font_dirs[#font_dirs+1] = wd .. "/fonts"
        font_dirs[#font_dirs+1] = wd .. "/lib/fonts"
        font_dirs[#font_dirs+1] = wd .. "/../fonts"
        font_dirs[#font_dirs+1] = "/system/fonts"
    end
    local function add(files, size)
        for _, dir in ipairs(font_dirs) do
            for _, name in ipairs(files) do
                local path = dir .. "/" .. name
                if doesFileExist(path) then
                    local ok, font = pcall(function() return io.Fonts:AddFontFromFileTTF(path, math.floor(size * (UIX.B or UIX.S) + 0.5), cfg, ranges) end)
                    if ok and font then return font end
                end
            end
        end
        return nil
    end
    F.reg   = add({"segoeui.ttf", "arial.ttf", "trebuc.ttf", "Roboto-Regular.ttf", "DroidSans.ttf", "NotoSans-Regular.ttf"}, 17)
    F.small = add({"segoeui.ttf", "arial.ttf", "trebuc.ttf", "Roboto-Regular.ttf", "DroidSans.ttf", "NotoSans-Regular.ttf"}, 15)
    F.bold  = add({"segoeuib.ttf", "arialbd.ttf", "trebucbd.ttf", "Roboto-Bold.ttf", "DroidSans-Bold.ttf", "NotoSans-Bold.ttf", "Roboto-Regular.ttf", "DroidSans.ttf"}, 17)
    F.h1    = add({"segoeuib.ttf", "arialbd.ttf", "trebucbd.ttf", "Roboto-Bold.ttf", "DroidSans-Bold.ttf", "NotoSans-Bold.ttf", "Roboto-Regular.ttf", "DroidSans.ttf"}, 21)
    F.logo  = add({"segoeuib.ttf", "arialbd.ttf", "trebucbd.ttf", "Roboto-Bold.ttf", "DroidSans-Bold.ttf", "NotoSans-Bold.ttf", "Roboto-Regular.ttf", "DroidSans.ttf"}, 25)
    if F.reg then
        pcall(function() io.FontGlobalScale = UIX.S / (UIX.B or UIX.S) end)
    else
        UIX.B = 1
        UIX.maxS = 4
        pcall(function() io.FontGlobalScale = UIX.S end)
    end

    local fa_path = getWorkingDirectory() .. "/resource/fonts/fa-solid-900.ttf"
    if doesFileExist(fa_path) then
        local codes, seen = {}, {}
        for _, c in pairs(FA_CODES) do if not seen[c] then seen[c] = true; codes[#codes+1] = c end end
        table.sort(codes)
        local arr = {}
        for _, c in ipairs(codes) do arr[#arr+1] = c; arr[#arr+1] = c end
        arr[#arr+1] = 0
        local ok_arr, ranges_arr = pcall(function() return imgui.new.ImWchar[#arr](arr) end)
        if ok_arr and ranges_arr then
            F._fa_ranges = ranges_arr
            local function addFa(size)
                local ok, font = pcall(function() return io.Fonts:AddFontFromFileTTF(fa_path, math.floor(size * (UIX.B or UIX.S) + 0.5), cfg, F._fa_ranges) end)
                return ok and font or nil
            end
            F.fa14 = addFa(14)
            F.fa16 = addFa(16)
            F.fa22 = addFa(22)
        end
    end
end)

local anim = {
    main = 0, main_target = 0,
    panel = 0, panel_target = 0,
    content = 1,
    notif = 0,
    page = 1,
}
local hover_anim = {}
local active_anim = {}
local ui_stats = { t = -100, total = 0, installed = 0, cats = {} }
local notif_closing = false
local main_pos = nil

local FRAME_DT = 0.016
local function dt() return FRAME_DT end
local function tickDt()
    local d = imgui.GetIO().DeltaTime
    if not d or d <= 0 then d = 0.016 end
    FRAME_DT = math.min(d, 0.1)
end
local function approach(v, target, speed)
    if v < target then return math.min(target, v + dt()*speed) end
    return math.max(target, v - dt()*speed)
end
local function ease(t) t = math.max(0, math.min(1, t)); return 1 - (1 - t)^3 end
local function lerp(a, b, t) return a + (b - a) * t end

local UI_ALPHA = 1

local col
do
    local floor = math.floor
    col = function(r, g, b, a)
        a = (a or 255) * UI_ALPHA
        if a < 0 then a = 0 elseif a > 255 then a = 255 end
        return floor(r + 0.5) + floor(g + 0.5) * 256 + floor(b + 0.5) * 65536 + floor(a + 0.5) * 16777216
    end
end
local function v4(r, g, b, a)
    return imgui.ImVec4(r/255, g/255, b/255, (a or 255)/255 * UI_ALPHA)
end
local CL_RAW = {
    white = {255,255,255}, text = {225,225,230}, grey = {150,150,158}, dim = {105,105,112},
    red = {226,32,40}, redH = {245,55,62}, redD = {180,20,28},
    panel = {17,17,20}, panelB = {38,38,44},
    card = {20,20,24}, cardH = {26,26,31}, cardB = {42,42,48},
    green = {70,215,100}, pill = {36,36,41},
}
local ACC = { r = 226, g = 32, b = 40, ver = 1, save_at = nil,
    buf = imgui.new.float[3](226 / 255, 32 / 255, 40 / 255),
    presets = {
        { 226, 32, 40,   "Красный" },    { 240, 120, 30,  "Оранжевый" }, { 232, 180, 40, "Золотой" },
        { 50, 190, 90,   "Зелёный" },    { 30, 185, 190,  "Бирюзовый" }, { 55, 125, 240, "Синий" },
        { 150, 85, 235,  "Фиолетовый" }, { 230, 65, 150,  "Розовый" },   { 215, 215, 222, "Белый" },
    },
}
function ACC.c(a) return col(ACC.r, ACC.g, ACC.b, a) end
function ACC.k(k, a)
    return col(math.min(255, ACC.r * k), math.min(255, ACC.g * k), math.min(255, ACC.b * k), a)
end
function ACC.t(t, a)
    return col(17 + (ACC.r - 17) * t, 17 + (ACC.g - 17) * t, 20 + (ACC.b - 20) * t, a)
end
function ACC.light() return (ACC.r * 0.299 + ACC.g * 0.587 + ACC.b * 0.114) > 165 end
function ACC.fg(a) if ACC.light() then return col(20, 20, 24, a) end return col(255, 255, 255, a) end
function ACC.set(r, g, b)
    r, g, b = math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
    ACC.r, ACC.g, ACC.b = r, g, b
    ACC.ver = ACC.ver + 1
    ACC.buf[0], ACC.buf[1], ACC.buf[2] = r / 255, g / 255, b / 255
end

local CL = setmetatable({}, { __index = function(_, k)
    if k == "red"  then return ACC.c() end
    if k == "redH" then return col(ACC.r + (255 - ACC.r) * 0.15, ACC.g + (255 - ACC.g) * 0.15, ACC.b + (255 - ACC.b) * 0.15) end
    if k == "redD" then return ACC.k(0.8) end
    local c = CL_RAW[k]; return col(c[1], c[2], c[3], c[4])
end })

local STYLE_DIRTY = true
local applyBaseStyle
do
local base_style_colors = nil
local acc_style_colors, acc_style_ver = nil, -1
applyBaseStyle = function()
    if not STYLE_DIRTY and acc_style_ver == ACC.ver then return end
    STYLE_DIRTY = false
    local style  = imgui.GetStyle()
    local c      = style.Colors
    if not base_style_colors then
        local V4 = imgui.ImVec4
        base_style_colors = {
            { imgui.Col.WindowBg, V4(0.043, 0.043, 0.051, 0.98) },
            { imgui.Col.ChildBg, V4(0, 0, 0, 0) },
            { imgui.Col.PopupBg, V4(0.078, 0.078, 0.094, 0.98) },
            { imgui.Col.Border, V4(0.22, 0.22, 0.25, 1) },
            { imgui.Col.BorderShadow, V4(0, 0, 0, 0) },
            { imgui.Col.Text, V4(0.90, 0.90, 0.92, 1) },
            { imgui.Col.TextDisabled, V4(0.50, 0.50, 0.54, 1) },
            { imgui.Col.TextSelectedBg, V4(0.85, 0.12, 0.15, 0.45) },
            { imgui.Col.FrameBg, V4(0.075, 0.075, 0.09, 1) },
            { imgui.Col.FrameBgHovered, V4(0.10, 0.10, 0.12, 1) },
            { imgui.Col.FrameBgActive, V4(0.12, 0.12, 0.14, 1) },
            { imgui.Col.TitleBg, V4(0.06, 0.06, 0.07, 1) },
            { imgui.Col.TitleBgActive, V4(0.08, 0.08, 0.09, 1) },
            { imgui.Col.TitleBgCollapsed, V4(0.06, 0.06, 0.07, 1) },
            { imgui.Col.Button, V4(0.12, 0.12, 0.14, 1) },
            { imgui.Col.ButtonHovered, V4(0.80, 0.13, 0.16, 1) },
            { imgui.Col.ButtonActive, V4(0.70, 0.08, 0.11, 1) },
            { imgui.Col.Header, V4(0.35, 0.06, 0.08, 1) },
            { imgui.Col.HeaderHovered, V4(0.50, 0.08, 0.10, 1) },
            { imgui.Col.HeaderActive, V4(0.60, 0.10, 0.12, 1) },
            { imgui.Col.ScrollbarBg, V4(0, 0, 0, 0) },
            { imgui.Col.ScrollbarGrab, V4(0.55, 0.08, 0.11, 1) },
            { imgui.Col.ScrollbarGrabHovered, V4(0.75, 0.10, 0.13, 1) },
            { imgui.Col.ScrollbarGrabActive, V4(0.88, 0.13, 0.16, 1) },
            { imgui.Col.CheckMark, V4(0.89, 0.13, 0.16, 1) },
            { imgui.Col.SliderGrab, V4(0.89, 0.13, 0.16, 1) },
            { imgui.Col.SliderGrabActive, V4(0.95, 0.20, 0.24, 1) },
            { imgui.Col.Separator, V4(0.20, 0.20, 0.23, 1) },
            { imgui.Col.SeparatorHovered, V4(0.80, 0.13, 0.16, 1) },
            { imgui.Col.SeparatorActive, V4(0.89, 0.13, 0.16, 1) },
        }
    end
    for i = 1, #base_style_colors do
        local e = base_style_colors[i]
        c[e[1]] = e[2]
    end
    if acc_style_ver ~= ACC.ver then
        acc_style_ver = ACC.ver
        local V4 = imgui.ImVec4
        local r, g, b = ACC.r / 255, ACC.g / 255, ACC.b / 255
        acc_style_colors = {
            { imgui.Col.ScrollbarGrab,        V4(r * 0.6, g * 0.6, b * 0.6, 1) },
            { imgui.Col.ScrollbarGrabHovered, V4(r * 0.8, g * 0.8, b * 0.8, 1) },
            { imgui.Col.ScrollbarGrabActive,  V4(r, g, b, 1) },
            { imgui.Col.Header,               V4(r * 0.4, g * 0.4, b * 0.4, 1) },
            { imgui.Col.HeaderHovered,        V4(r * 0.55, g * 0.55, b * 0.55, 1) },
            { imgui.Col.HeaderActive,         V4(r * 0.7, g * 0.7, b * 0.7, 1) },
            { imgui.Col.ButtonHovered,        V4(r * 0.9, g * 0.9, b * 0.9, 1) },
            { imgui.Col.ButtonActive,         V4(r * 0.75, g * 0.75, b * 0.75, 1) },
            { imgui.Col.CheckMark,            V4(r, g, b, 1) },
            { imgui.Col.SliderGrab,           V4(r, g, b, 1) },
            { imgui.Col.SliderGrabActive,     V4(r, g, b, 1) },
            { imgui.Col.TextSelectedBg,       V4(r, g, b, 0.45) },
            { imgui.Col.SeparatorHovered,     V4(r * 0.9, g * 0.9, b * 0.9, 1) },
            { imgui.Col.SeparatorActive,      V4(r, g, b, 1) },
        }
    end
    for i = 1, #acc_style_colors do
        local e = acc_style_colors[i]
        c[e[1]] = e[2]
    end
    style.WindowRounding    = 12
    style.ChildRounding     = 10
    style.FrameRounding     = 8
    style.PopupRounding     = 10
    style.ScrollbarRounding = 6
    style.GrabRounding      = 6
    style.WindowBorderSize  = 1
    style.FrameBorderSize   = 0
    style.ChildBorderSize   = 0
    style.PopupBorderSize   = 1
    style.ScrollbarSize     = 6 * UIX.S
end
end

local U
do
    local u8_cache, u8_count = {}, 0
    U = function(str)
        local r = u8_cache[str]
        if r then return r end
        r = u8(str)
        u8_count = u8_count + 1
        if u8_count > 3000 then u8_cache, u8_count = {}, 0 end
        u8_cache[str] = r
        return r
    end
end
local function pushF(f) if f then imgui.PushFont(f) end end
local function popF(f)  if f then imgui.PopFont() end end

local TS, fitText, wrapText, T, clearTexts
do
local ts_cache, ts_count = {}, 0
local fit_cache, wrap_cache = {}, {}
local function clearTextCaches()
    ts_cache, ts_count, fit_cache, wrap_cache = {}, 0, {}, {}
end
clearTexts = clearTextCaches
TS = function(font, s)
    local fk = font or 0
    local c = ts_cache[fk]
    if not c then c = {}; ts_cache[fk] = c end
    local r = c[s]
    if r then return r end
    pushF(font); local v = imgui.CalcTextSize(s); popF(font)
    r = { x = v.x, y = v.y }
    ts_count = ts_count + 1
    if ts_count > 6000 then clearTextCaches(); c = {}; ts_cache[fk] = c end
    c[s] = r
    return r
end
T = function(dl, font, x, y, c, s) pushF(font); dl:AddText(V2(x, y), c, s); popF(font) end

local fitTextRaw
fitText = function(font, s, maxw)
    if maxw <= 0 then return "" end
    if maxw >= 16 then maxw = maxw - maxw % 8 end
    local fk = font or 0
    local c = fit_cache[fk]
    if not c then c = {}; fit_cache[fk] = c end
    local key = s .. "\0" .. math.floor(maxw)
    local r = c[key]
    if r then return r end
    r = fitTextRaw(font, s, maxw)
    c[key] = r
    ts_count = ts_count + 1
    if ts_count > 6000 then clearTextCaches() end
    return r
end
fitTextRaw = function(font, s, maxw)
    if TS(font, s).x <= maxw then return s end
    local chars = {}
    for ch in s:gmatch("[%z\1-\127\192-\255][\128-\191]*") do chars[#chars+1] = ch end
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if TS(font, table.concat(chars, "", 1, mid) .. "...").x <= maxw then lo = mid else hi = mid - 1 end
    end
    return table.concat(chars, "", 1, lo) .. "..."
end

local wrapTextRaw
wrapText = function(font, s, maxw, maxlines)
    if maxw >= 16 then maxw = maxw - maxw % 8 end
    local fk = font or 0
    local c = wrap_cache[fk]
    if not c then c = {}; wrap_cache[fk] = c end
    local key = s .. "\0" .. math.floor(maxw) .. "\0" .. (maxlines or 999)
    local r = c[key]
    if r then return r end
    r = wrapTextRaw(font, s, maxw, maxlines)
    c[key] = r
    ts_count = ts_count + 1
    if ts_count > 6000 then clearTextCaches() end
    return r
end
wrapTextRaw = function(font, s, maxw, maxlines)
    maxlines = maxlines or 999
    local lines, cur, cut = {}, "", false
    for word in s:gmatch("%S+") do
        local t = (cur == "") and word or (cur .. " " .. word)
        if TS(font, t).x <= maxw then
            cur = t
        else
            if cur ~= "" then lines[#lines+1] = cur end
            cur = word
            if #lines >= maxlines then cut = true; cur = ""; break end
        end
    end
    if cur ~= "" then
        if #lines < maxlines then lines[#lines+1] = cur else cut = true end
    end
    for k = 1, #lines do lines[k] = fitText(font, lines[k], maxw) end
    if cut and #lines > 0 then lines[#lines] = fitText(font, lines[#lines] .. " ...", maxw) end
    return lines
end
end

UIX.onScale = function()
    clearTexts()
    main_pos = nil
    STYLE_DIRTY = true
    anim.page = 0
end

local function wrapCached(s, key, font, str, w, ml)
    local c = s._wc
    if not c or c.w ~= w then c = { w = w }; s._wc = c end
    local r = c[key]
    if r then return r end
    r = wrapText(font, str, w, ml)
    c[key] = r
    return r
end

local function L(dl, x1, y1, x2, y2, c, t) dl:AddLine(V2(x1, y1), V2(x2, y2), c, t or 1.6) end
local IC = {}
function IC.grid(dl, cx, cy, s, c)
    local a, g = s*0.36, s*0.14
    for _, o in ipairs({{-1,-1},{1,-1},{-1,1},{1,1}}) do
        local x = cx + (o[1] < 0 and (-g/2 - a) or g/2)
        local y = cy + (o[2] < 0 and (-g/2 - a) or g/2)
        dl:AddRect(V2(x, y), V2(x+a, y+a), c, 2, nil, 1.5)
    end
end
function IC.list(dl, cx, cy, s, c)
    local h = s/2
    for k = -1, 1 do
        dl:AddCircleFilled(V2(cx-h*0.75, cy+k*h*0.6), 1.6, c, 8)
        L(dl, cx-h*0.35, cy+k*h*0.6, cx+h*0.9, cy+k*h*0.6, c, 1.6)
    end
end
function IC.installed(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h, cy-h+1), V2(cx+h, cy+h), c, 3, nil, 1.5)
    L(dl, cx-h*0.45, cy+1, cx-h*0.1, cy+h*0.4, c, 1.8)
    L(dl, cx-h*0.1, cy+h*0.4, cx+h*0.5, cy-h*0.3, c, 1.8)
end
function IC.cart(dl, cx, cy, s, c)
    local h = s/2
    L(dl, cx-h, cy-h*0.75, cx-h*0.6, cy-h*0.75, c)
    L(dl, cx-h*0.6, cy-h*0.75, cx-h*0.3, cy+h*0.35, c)
    L(dl, cx-h*0.3, cy+h*0.35, cx+h*0.7, cy+h*0.35, c)
    L(dl, cx+h*0.7, cy+h*0.35, cx+h*0.9, cy-h*0.4, c)
    L(dl, cx+h*0.9, cy-h*0.4, cx-h*0.5, cy-h*0.4, c)
    dl:AddCircleFilled(V2(cx-h*0.15, cy+h*0.78), 1.8, c, 8)
    dl:AddCircleFilled(V2(cx+h*0.55, cy+h*0.78), 1.8, c, 8)
end
function IC.gear(dl, cx, cy, s, c)
    for k = 0, 7 do
        local a = k*math.pi/4
        L(dl, cx+math.cos(a)*s*0.28, cy+math.sin(a)*s*0.28, cx+math.cos(a)*s*0.48, cy+math.sin(a)*s*0.48, c, 2.2)
    end
    dl:AddCircle(V2(cx, cy), s*0.3, c, 20, 1.6)
    dl:AddCircle(V2(cx, cy), s*0.11, c, 12, 1.5)
end
function IC.monitor(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h, cy-h*0.75), V2(cx+h, cy+h*0.4), c, 2, nil, 1.5)
    L(dl, cx, cy+h*0.4, cx, cy+h*0.8, c)
    L(dl, cx-h*0.45, cy+h*0.85, cx+h*0.45, cy+h*0.85, c)
end
function IC.gamepad(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h, cy-h*0.5), V2(cx+h, cy+h*0.55), c, 5, nil, 1.5)
    L(dl, cx-h*0.62, cy, cx-h*0.18, cy, c)
    L(dl, cx-h*0.4, cy-h*0.22, cx-h*0.4, cy+h*0.22, c)
    dl:AddCircleFilled(V2(cx+h*0.35, cy-h*0.1), 1.5, c, 8)
    dl:AddCircleFilled(V2(cx+h*0.6, cy+h*0.14), 1.5, c, 8)
end
function IC.dots(dl, cx, cy, s, c)
    for k = -1, 1 do dl:AddCircleFilled(V2(cx+k*s*0.32, cy), s*0.09+0.6, c, 8) end
end
function IC.tag(dl, cx, cy, s, c)
    local h = s/2
    L(dl, cx-h*0.2, cy-h*0.8, cx-h*0.45, cy+h*0.8, c)
    L(dl, cx+h*0.45, cy-h*0.8, cx+h*0.2, cy+h*0.8, c)
    L(dl, cx-h*0.8, cy-h*0.3, cx+h*0.8, cy-h*0.3, c)
    L(dl, cx-h*0.8, cy+h*0.3, cx+h*0.8, cy+h*0.3, c)
end
function IC.search(dl, cx, cy, s, c)
    dl:AddCircle(V2(cx-s*0.08, cy-s*0.08), s*0.32, c, 20, 1.6)
    L(dl, cx+s*0.16, cy+s*0.16, cx+s*0.42, cy+s*0.42, c, 1.8)
end
function IC.sort(dl, cx, cy, s, c)
    local h = s/2
    L(dl, cx-h*0.35, cy-h, cx-h*0.35, cy+h, c)
    L(dl, cx-h*0.35, cy-h, cx-h*0.75, cy-h*0.55, c)
    L(dl, cx-h*0.35, cy-h, cx+h*0.05, cy-h*0.55, c)
    L(dl, cx+h*0.35, cy-h, cx+h*0.35, cy+h, c)
    L(dl, cx+h*0.35, cy+h, cx-h*0.05, cy+h*0.55, c)
    L(dl, cx+h*0.35, cy+h, cx+h*0.75, cy+h*0.55, c)
end
function IC.chevron(dl, cx, cy, s, c)
    L(dl, cx-s*0.3, cy-s*0.15, cx, cy+s*0.15, c, 1.8)
    L(dl, cx, cy+s*0.15, cx+s*0.3, cy-s*0.15, c, 1.8)
end
function IC.check(dl, cx, cy, s, c)
    L(dl, cx-s*0.32, cy, cx-s*0.08, cy+s*0.25, c, 2)
    L(dl, cx-s*0.08, cy+s*0.25, cx+s*0.34, cy-s*0.24, c, 2)
end
function IC.close(dl, cx, cy, s, c)
    L(dl, cx-s*0.3, cy-s*0.3, cx+s*0.3, cy+s*0.3, c, 1.8)
    L(dl, cx+s*0.3, cy-s*0.3, cx-s*0.3, cy+s*0.3, c, 1.8)
end
function IC.minus(dl, cx, cy, s, c)
    L(dl, cx-s*0.36, cy, cx+s*0.36, cy, c, 2)
end
function IC.plus(dl, cx, cy, s, c)
    L(dl, cx-s*0.36, cy, cx+s*0.36, cy, c, 2)
    L(dl, cx, cy-s*0.36, cx, cy+s*0.36, c, 2)
end
function IC.download(dl, cx, cy, s, c)
    L(dl, cx, cy-s*0.45, cx, cy+s*0.15, c, 1.8)
    L(dl, cx-s*0.28, cy-s*0.1, cx, cy+s*0.18, c, 1.8)
    L(dl, cx+s*0.28, cy-s*0.1, cx, cy+s*0.18, c, 1.8)
    L(dl, cx-s*0.42, cy+s*0.42, cx+s*0.42, cy+s*0.42, c, 1.8)
end
function IC.refresh(dl, cx, cy, s, c)
    local r, prev = s*0.38, nil
    for k = 0, 14 do
        local a = math.rad(-50 + k*20)
        local p = V2(cx + math.cos(a)*r, cy + math.sin(a)*r)
        if prev then dl:AddLine(prev, p, c, 1.7) end
        prev = p
    end
    local a = math.rad(-50)
    local px, py = cx + math.cos(a)*r, cy + math.sin(a)*r
    L(dl, px, py, px - s*0.05, py - s*0.3, c, 1.7)
    L(dl, px, py, px + s*0.27, py + s*0.02, c, 1.7)
end
function IC.trash(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h*0.6, cy-h*0.45), V2(cx+h*0.6, cy+h*0.9), c, 2, nil, 1.5)
    L(dl, cx-h*0.85, cy-h*0.62, cx+h*0.85, cy-h*0.62, c)
    L(dl, cx-h*0.25, cy-h*0.88, cx+h*0.25, cy-h*0.88, c)
end
function IC.plane(dl, cx, cy, s, c)
    local h = s/2
    dl:AddTriangleFilled(V2(cx-h, cy-h*0.05), V2(cx+h, cy-h*0.8), V2(cx+h*0.5, cy+h*0.8), c)
    dl:AddTriangleFilled(V2(cx-h*0.15, cy+h*0.12), V2(cx+h*0.62, cy-h*0.45), V2(cx-h*0.05, cy+h*0.72), col(0,0,0,90))
end
function IC.info(dl, cx, cy, s, c)
    dl:AddCircle(V2(cx, cy), s*0.46, c, 24, 1.5)
    L(dl, cx, cy-s*0.04, cx, cy+s*0.24, c, 1.8)
    dl:AddCircleFilled(V2(cx, cy-s*0.2), 1.6, c, 8)
end
function IC.edit(dl, cx, cy, s, c)
    local h = s/2
    L(dl, cx-h*0.7, cy+h*0.7, cx+h*0.5, cy-h*0.5, c, 2.4)
    L(dl, cx+h*0.5, cy-h*0.5, cx+h*0.75, cy-h*0.75, c, 1.4)
    L(dl, cx-h*0.85, cy+h*0.85, cx-h*0.6, cy+h*0.8, c, 1.4)
end
function IC.bell(dl, cx, cy, s, c)
    local h = s/2
    dl:AddCircleFilled(V2(cx, cy-h*0.15), h*0.62, c, 20)
    dl:AddRectFilled(V2(cx-h*0.62, cy-h*0.15), V2(cx+h*0.62, cy+h*0.45), c)
    dl:AddRectFilled(V2(cx-h*0.85, cy+h*0.4), V2(cx+h*0.85, cy+h*0.58), c, 2)
    dl:AddCircleFilled(V2(cx, cy+h*0.78), h*0.18, c, 10)
end

local function btnBase(id, w, h)
    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(id, V2(w, h))
    return p, clicked, imgui.IsItemHovered(), imgui.IsItemActive()
end

local function drawLabel(dl, p, w, h, label, iconfn, font, c)
    local ts = TS(font, label)
    local iw = iconfn and 22 or 0
    local x = p.x + (w - ts.x - iw) / 2
    if iconfn then iconfn(dl, x + 7, p.y + h/2, 14, c) end
    T(dl, font, x + iw, p.y + (h - ts.y) / 2, c, label)
end

local function redButton(id, label, w, h, iconfn, font, disabled)
    local dl = imgui.GetWindowDrawList()
    local p, clicked, hov, act = btnBase(id, w, h)
    if disabled then hov, act, clicked = false, false, false end
    local r = math.min(9, h/2)
    local fill = disabled and ACC.k(0.53) or (act and CL.redD or (hov and CL.redH or CL.red))
    dl:AddRectFilled(p, V2(p.x+w, p.y+h), fill, r)
    drawLabel(dl, p, w, h, label, iconfn, font or F.bold, disabled and ACC.fg(160) or ACC.fg())
    return clicked
end

local function ghostButton(id, label, w, h, iconfn, danger, font)
    local dl = imgui.GetWindowDrawList()
    local p, clicked, hov = btnBase(id, w, h)
    local r = math.min(9, h/2)
    local fill = danger and (hov and col(70,16,20) or col(40,12,15)) or (hov and col(38,38,44) or col(24,24,28))
    local brd  = danger and col(200,35,42) or col(62,62,70)
    dl:AddRectFilled(p, V2(p.x+w, p.y+h), fill, r)
    dl:AddRect(p, V2(p.x+w, p.y+h), brd, r, nil, 1.2)
    drawLabel(dl, p, w, h, label, iconfn, font or F.reg, danger and col(255,95,100) or CL.text)
    return clicked
end

local function iconButton(id, w, h, iconfn, tooltip)
    local dl = imgui.GetWindowDrawList()
    local p, clicked, hov = btnBase(id, w, h)
    dl:AddRectFilled(p, V2(p.x+w, p.y+h), hov and col(44,44,50) or col(30,30,35), 7)
    dl:AddRect(p, V2(p.x+w, p.y+h), col(58,58,65), 7, nil, 1)
    iconfn(dl, p.x + w/2, p.y + h/2, 14, hov and CL.white or CL.text)
    return clicked
end

local function pill(dl, x, y, text, font, bg, fg, dotc)
    local ts = TS(font, text)
    local pad = 8
    local dw = dotc and 12 or 0
    local w, h = ts.x + pad*2 + dw, ts.y + 6
    dl:AddRectFilled(V2(x, y), V2(x+w, y+h), bg, h/2)
    if dotc then dl:AddCircleFilled(V2(x+pad+3, y+h/2), 3.5, dotc, 12) end
    T(dl, font, x+pad+dw, y+3, fg, text)
    return w, h
end

local function navItem(id, iconfn, label, count, active, width, boxed)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local w = width or imgui.GetContentRegionAvail().x
    local h = boxed and 42 or 40
    local clicked = imgui.InvisibleButton(id, V2(w, h))
    local hov = imgui.IsItemHovered()
    local p2 = V2(p.x+w, p.y+h)
    local a = active and 1 or 0
    local hv = hov and 1 or 0
    if boxed then
        dl:AddRectFilled(p, p2, col(22,22,26), 9)
        dl:AddRect(p, p2, col(52,52,60), 9, nil, 1.2)
    end
    if hv > 0.01 then dl:AddRectFilled(p, p2, col(30,30,35, 255*hv*(1-a)), 9) end
    if a > 0.01 then
        dl:AddRectFilled(p, p2, ACC.t(0.3, 255*a), 9)
        dl:AddRect(p, p2, ACC.k(0.95, 255*a), 9, nil, 1.3)
    end
    local tc = col(lerp(205,255,a), lerp(205,255,a), lerp(212,255,a))
    if iconfn then iconfn(dl, p.x+19, p.y+h/2, 16, tc) end
    local lbl = fitText(F.reg, label, w - 40 - (count and 34 or 8))
    T(dl, F.reg, p.x+36, p.y + (h - TS(F.reg, lbl).y)/2, tc, lbl)
    if count then
        local s = tostring(count)
        local cs = TS(F.small, s)
        local pw = math.max(26, cs.x + 14)
        local px, py = p.x + w - pw - 8, p.y + (h-20)/2
        dl:AddRectFilled(V2(px, py), V2(px+pw, py+20), active and ACC.k(0.7) or col(38,38,44), 10)
        T(dl, F.small, px + (pw-cs.x)/2, py + (20-cs.y)/2, active and CL.white or CL.grey, s)
    end
    return clicked
end

local function sectionLabel(text)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    imgui.Dummy(V2(w, 30))
    dl:AddLine(V2(p.x+4, p.y+5), V2(p.x+w-4, p.y+5), col(40,40,46), 1)
    T(dl, F.small, p.x+6, p.y+12, CL.grey, text)
end

do
local function arcLines(dl, cx, cy, r, a0, a1, c, t, seg)
    seg = seg or 12
    local prev
    for k = 0, seg do
        local a = math.rad(a0 + (a1 - a0) * k / seg)
        local p = V2(cx + math.cos(a)*r, cy + math.sin(a)*r)
        if prev then dl:AddLine(prev, p, c, t or 1.6) end
        prev = p
    end
end
function IC.shop(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRectFilled(V2(cx-h, cy-h*0.8), V2(cx+h, cy-h*0.35), c, 2)
    for k = 0, 3 do
        local x = cx - h + (k + 0.5) * (s/4)
        dl:AddCircleFilled(V2(x, cy-h*0.35), s/8, c, 10)
    end
    dl:AddRect(V2(cx-h*0.82, cy-h*0.25), V2(cx+h*0.82, cy+h*0.9), c, 1, nil, 1.5)
    dl:AddRect(V2(cx-h*0.25, cy+h*0.2), V2(cx+h*0.25, cy+h*0.9), c, 1, nil, 1.4)
end
function IC.helper(dl, cx, cy, s, c)
    dl:AddCircle(V2(cx, cy), s*0.46, c, 24, 1.6)
    dl:AddCircle(V2(cx, cy), s*0.2, c, 16, 1.6)
    for k = 0, 3 do
        local a = k*math.pi/2 + math.pi/4
        L(dl, cx+math.cos(a)*s*0.2, cy+math.sin(a)*s*0.2, cx+math.cos(a)*s*0.46, cy+math.sin(a)*s*0.46, c, 3)
    end
end
function IC.star(dl, cx, cy, s, c)
    local pts = {}
    for k = 0, 9 do
        local r = (k % 2 == 0) and s*0.5 or s*0.21
        local a = math.rad(-90 + k*36)
        pts[#pts+1] = V2(cx + math.cos(a)*r, cy + 1 + math.sin(a)*r)
    end
    for k = 1, 10 do
        dl:AddTriangleFilled(V2(cx, cy+1), pts[k], pts[k % 10 + 1], c)
    end
end
function IC.coin(dl, cx, cy, s, c)
    local h = s/2
    dl:AddCircle(V2(cx, cy), h*0.92, c, 24, 1.6)
    dl:AddCircle(V2(cx, cy), h*0.62, c, 20, 1.1)
    L(dl, cx, cy-h*0.42, cx, cy+h*0.42, c, 1.6)
    L(dl, cx-h*0.2, cy-h*0.22, cx+h*0.22, cy-h*0.22, c, 1.4)
    L(dl, cx-h*0.22, cy+h*0.22, cx+h*0.2, cy+h*0.22, c, 1.4)
end
function IC.log(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h*0.7, cy-h), V2(cx+h*0.7, cy+h), c, 2, nil, 1.5)
    for k = 0, 2 do
        local y = cy - h*0.45 + k*h*0.45
        L(dl, cx-h*0.4, y, cx+h*(k == 2 and 0.1 or 0.4), y, c, 1.5)
    end
end
function IC.airplane(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRectFilled(V2(cx-h*0.12, cy-h), V2(cx+h*0.12, cy+h*0.75), c, 3)
    dl:AddTriangleFilled(V2(cx, cy-h*0.35), V2(cx-h, cy+h*0.2), V2(cx+h, cy+h*0.2), c)
    dl:AddTriangleFilled(V2(cx, cy+h*0.5), V2(cx-h*0.45, cy+h*0.95), V2(cx+h*0.45, cy+h*0.95), c)
end
function IC.eye(dl, cx, cy, s, c)
    local h = s/2
    arcLines(dl, cx, cy+h*0.9, h*1.35, 222, 318, c, 1.6, 10)
    arcLines(dl, cx, cy-h*0.9, h*1.35, 42, 138, c, 1.6, 10)
    dl:AddCircle(V2(cx, cy), h*0.36, c, 16, 1.6)
    dl:AddCircleFilled(V2(cx, cy), h*0.14, c, 10)
end
function IC.bag(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h*0.75, cy-h*0.5), V2(cx+h*0.75, cy+h), c, 4, nil, 1.5)
    arcLines(dl, cx, cy-h*0.5, h*0.35, 180, 360, c, 1.5, 8)
    dl:AddRect(V2(cx-h*0.4, cy+h*0.2), V2(cx+h*0.4, cy+h*0.7), c, 2, nil, 1.3)
end
function IC.shield(dl, cx, cy, s, c)
    local h = s/2
    local p = { V2(cx, cy-h), V2(cx+h*0.8, cy-h*0.6), V2(cx+h*0.7, cy+h*0.2), V2(cx, cy+h),
                V2(cx-h*0.7, cy+h*0.2), V2(cx-h*0.8, cy-h*0.6) }
    for k = 1, #p do dl:AddLine(p[k], p[k % #p + 1], c, 1.6) end
    L(dl, cx-h*0.32, cy, cx-h*0.05, cy+h*0.28, c, 1.7)
    L(dl, cx-h*0.05, cy+h*0.28, cx+h*0.38, cy-h*0.25, c, 1.7)
end
function IC.chip(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRect(V2(cx-h*0.62, cy-h*0.62), V2(cx+h*0.62, cy+h*0.62), c, 2, nil, 1.5)
    dl:AddRectFilled(V2(cx-h*0.25, cy-h*0.25), V2(cx+h*0.25, cy+h*0.25), c, 1)
    for k = -1, 1 do
        local o = k*h*0.35
        L(dl, cx+o, cy-h*0.62, cx+o, cy-h, c, 1.3); L(dl, cx+o, cy+h*0.62, cx+o, cy+h, c, 1.3)
        L(dl, cx-h*0.62, cy+o, cx-h, cy+o, c, 1.3); L(dl, cx+h*0.62, cy+o, cx+h, cy+o, c, 1.3)
    end
end
function IC.gun(dl, cx, cy, s, c)
    local h = s/2
    dl:AddRectFilled(V2(cx-h, cy-h*0.55), V2(cx+h, cy-h*0.12), c, 2)
    dl:AddTriangleFilled(V2(cx-h*0.05, cy-h*0.2), V2(cx+h*0.55, cy-h*0.2), V2(cx+h*0.35, cy+h*0.95), c)
    dl:AddTriangleFilled(V2(cx-h*0.05, cy-h*0.2), V2(cx+h*0.35, cy+h*0.95), V2(cx-h*0.15, cy+h*0.8), c)
    arcLines(dl, cx-h*0.2, cy-h*0.1, h*0.3, 0, 180, c, 1.4, 6)
end

end

do
IC.hands  = IC.helper
IC.market = IC.shop
IC.robot  = IC.gear
IC.tshirt = IC.monitor
IC.dice   = IC.gamepad
local function faFont(s)
    if s <= 12 then return F.fa14
    elseif s <= 15 then return F.fa14
    elseif s <= 19 then return F.fa16 or F.fa14
    else return F.fa22 or F.fa16 end
end
for name, code in pairs(FA_CODES) do
    local vec, glyph = IC[name], utf8char(code)
    IC[name] = function(dl, cx, cy, s, c)
        local f = faFont(s)
        if f then
            local ts = TS(f, glyph)
            T(dl, f, math.floor(cx - ts.x / 2 + 0.5), math.floor(cy - ts.y / 2 + 0.5), c, glyph)
        elseif vec then
            vec(dl, cx, cy, s, c)
        end
    end
end
end

local CAT_ICON_RULES = {
    { IC.shield, { "\224\237\242\232", "anti" } },
    { IC.chip, { "\224\241\232", "asi" }, true },
    { IC.chip, { "\234\235\229\238", "cleo" } },
    { IC.gun, { "\227\229\242\242\238", "\238\240\243\230", "ghetto" } },
    { IC.hands, { "\239\238\236\238\249" } },
    { IC.helper, { "\245\229\235\239\229\240", "helper" } },
    { IC.star, { "\239\238\239\243\235\255\240" } },
    { IC.star, { "\242\238\239", "top" }, true },
    { IC.coin, { "\244\224\240\236", "farm" } },
    { IC.log, { "\235\238\227\229\240", "\235\238\227", "log" } },
    { IC.airplane, { "\235\238\226\235" } },
    { IC.eye, { "\226\232\231\243\224\235", "visual" } },
    { IC.bag, { "\232\237\226" } },
    { IC.shop, { "\246\240" }, true },
    { IC.shop, { "\235\224\226\234" } },
    { IC.market, { "\240\251\237" } },
    { IC.cart, { "\242\238\240\227\238\226", "\241\234\243\239" } },
    { IC.robot, { "\224\226\242\238\236\224\242" } },
    { IC.gear, { "\224\226\242\238", "auto" } },
    { IC.tshirt, { "\241\234\232\237" } },
    { IC.monitor, { "\232\237\242\229\240\244" } },
    { IC.dice, { "\240\243\235\229\242", "\234\224\231\232\237" } },
    { IC.gamepad, { "\232\227\240" } },
}

local function catIcon(name)
    local n = (name or ""):lower():gsub("[\192-\223]", function(ch) return string.char(ch:byte() + 32) end)
    for _, r in ipairs(CAT_ICON_RULES) do
        for _, key in ipairs(r[2]) do
            if r[3] then
                if n == key then return r[1] end
            elseif n:find(key, 1, true) then
                return r[1]
            end
        end
    end
    return IC.tag
end

local function pushPopupStyle()
    imgui.PushStyleColor(imgui.Col.PopupBg, v4(20,20,24,250))
    imgui.PushStyleColor(imgui.Col.Border,  v4(55,55,62,255))
    imgui.PushStyleVarFloat(imgui.StyleVar.PopupRounding, 10)
    imgui.PushStyleVarFloat(imgui.StyleVar.PopupBorderSize, 1)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(6, 6))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(4, 2))
end
local function popPopupStyle()
    imgui.PopStyleVar(4)
    imgui.PopStyleColor(2)
end

local function menuItem(id, label, iconfn, danger, checked)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    local h = 32
    local clicked = imgui.InvisibleButton(id, V2(w, h))
    local hov = imgui.IsItemHovered()
    if hov then dl:AddRectFilled(p, V2(p.x+w, p.y+h), danger and col(70,16,20) or ACC.t(0.2), 7) end
    if checked then dl:AddRectFilled(V2(p.x+2, p.y+8), V2(p.x+5, p.y+h-8), CL.red, 2) end
    local c = danger and col(255,95,100) or ((checked or hov) and CL.white or CL.text)
    local tx = p.x + 12
    if iconfn then iconfn(dl, p.x+20, p.y+h/2, 14, c); tx = p.x + 36 end
    T(dl, F.reg, tx, p.y + (h - TS(F.reg, label).y)/2, c, label)
    if clicked then imgui.CloseCurrentPopup() end
    return clicked
end

local function inputField(id, buf, width, placeholder, lpad)
    lpad = lpad or 12
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local h = 40
    dl:AddRectFilled(p, V2(p.x+width, p.y+h), col(19,19,23), 10)
    imgui.PushStyleColor(imgui.Col.FrameBg,        v4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, v4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,  v4(0,0,0,0))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)
    local fs = imgui.GetFontSize()
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(4, (h - fs)/2))
    imgui.SetCursorScreenPos(V2(p.x + lpad - 4, p.y))
    imgui.PushItemWidth(width - lpad - 8)
    local changed = imgui.InputText(id, buf, ffi.sizeof(buf))
    local act = imgui.IsItemActive()
    local hov = imgui.IsItemHovered()
    imgui.PopItemWidth()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(3)
    dl:AddRect(p, V2(p.x+width, p.y+h), act and ACC.k(0.9) or (hov and col(70,70,78) or col(48,48,55)), 10, nil, 1.2)
    if placeholder and ffi.string(buf) == "" and not act then
        T(dl, nil, p.x + lpad, p.y + (h - fs)/2, CL.dim, placeholder)
    end
    return changed
end

local function toggleSwitch(key, x, y)
    local dl = imgui.GetWindowDrawList()
    imgui.SetCursorScreenPos(V2(x, y))
    if imgui.InvisibleButton("##tg_" .. key, V2(48, 26)) then
        settings[key] = not settings[key]
        saveSettings()
    end
    toggle_anim[key] = approach(toggle_anim[key] or 0, settings[key] and 1 or 0, 7)
    local a = ease(toggle_anim[key])
    dl:AddRectFilled(V2(x, y), V2(x+48, y+26), col(lerp(52,ACC.r,a), lerp(52,ACC.g,a), lerp(58,ACC.b,a)), 13)
    local kx = lerp(x+13, x+35, a)
    dl:AddCircleFilled(V2(kx+1, y+14), 10, col(0,0,0,70), 20)
    dl:AddCircleFilled(V2(kx, y+13), 10, col(255,255,255), 20)
end

local function switchPage(tab)
    if tab ~= nil then main_active_tab = tab end
    anim.page = 0
end

local function openMainWindow()
    if anim.main_target ~= 1 then anim.page = 0 end
    STYLE_DIRTY = true
    invalidateInstallCache()
    main_window[0] = true
    imgui.Process = true
    anim.main_target = 1
end
local function closeMainWindow()
    anim.main_target = 0
end
local function openNotification()
    STYLE_DIRTY = true
    notification_window[0] = true
    notif_closing = false
end
local function closeNotification()
    notif_closing = true
end

local function selectScript(s)
    if selected_script_file ~= s.file then
        if anim.panel > 0.3 then anim.content = 0 end
        selected_script_file = s.file
    end
    anim.panel_target = 1
end
local function closePanel()
    anim.panel_target = 0
end

local function openTelegram(s)
    local url = (s and s.telegram and s.telegram ~= "") and s.telegram or "https://t.me/edward_scripts"
    openUrl(url)
end

local ICON_PALETTE = {
    {230,45,55},{240,140,40},{165,75,235},{55,140,245},
    {235,195,45},{45,195,110},{230,65,165},{40,190,200},
}
local function scriptHue(s)
    local n, str = 0, (s.name or s.file or "")
    for k = 1, #str do n = n + str:byte(k) end
    return ICON_PALETTE[n % #ICON_PALETTE + 1]
end

local function drawScriptIcon(dl, s, x, y, sz)
    local h = s._hue
    if not h then
        h = scriptHue(s)
        s._hue = h
        s._letter = U((s.name or "?"):sub(1, 1):upper())
    end
    local r = sz * 0.22
    dl:AddRectFilled(V2(x, y), V2(x+sz, y+sz), col(h[1]*0.22, h[2]*0.22, h[3]*0.22), r)
    dl:AddRect(V2(x, y), V2(x+sz, y+sz), col(h[1], h[2], h[3], 170), r, nil, 1.5)
    local letter = s._letter
    local font = (sz >= 48) and F.logo or F.h1
    local ts = TS(font, letter)
    T(dl, font, x + (sz - ts.x)/2, y + (sz - ts.y)/2, col(h[1], h[2], h[3]), letter)
end

local info_cache = {}
local function infoBlocks(s)
    local src = s.info or ""
    local c = info_cache[s.file]
    if c and c.src == src then return c.blocks end
    local out = {}
    local txt = src:gsub("\\n", "\n")
    for line in (txt .. "\n"):gmatch("(.-)\n") do
        local l = line:gsub("^%s+", ""):gsub("%s+$", "")
        if l == "" then
            if #out > 0 and out[#out].t ~= "gap" then out[#out+1] = { t = "gap" } end
        else
            local b = l:match("^\226\128\162%s*(.+)$") or l:match("^[\149\150\151%-%*]%s*(.+)$")
            if b then
                out[#out+1] = { t = "bullet", s = b }
            elseif #l <= 40 and l:sub(-1) == ":" then
                out[#out+1] = { t = "head", s = l:sub(1, -2) }
            else
                out[#out+1] = { t = "text", s = l }
            end
        end
    end
    info_cache[s.file] = { src = src, blocks = out }
    return out
end

local TOP_LABEL = { [3] = "TOP 1", [2] = "TOP 2", [1] = "TOP 3" }

local PREP_LEFT = 3
local function drawScriptCard(s)
    local p0 = imgui.GetCursorScreenPos()
    local full_w = imgui.GetContentRegionAvail().x
    local x, y = p0.x + 5, p0.y + 4
    local w, h = full_w - 12, 90

    if p0.y + h + 10 < UIX.clip0 or p0.y > UIX.clip1 then
        imgui.Dummy(V2(full_w - 2, h + 6))
        return
    end
    local RW = 148
    local installed = isScriptInstalled(s)
    local sel = (selected_script_file == s.file) and anim.panel_target == 1
    local dl = imgui.GetWindowDrawList()

    imgui.SetCursorScreenPos(V2(x, y))
    if imgui.InvisibleButton("##card", V2(w - RW, h)) then
        if sel then closePanel() else selectScript(s) end
    end
    local hov = imgui.IsItemActive()

    local tx = x + 84
    local maxw = w - RW - 84 - 6
    local cc = s._cc
    if not cc or cc.mw ~= maxw then
        if PREP_LEFT <= 0 then

            dl:AddRectFilled(V2(x, y), V2(x + w, y + h), col(20,20,24), 12)
            dl:AddRect(V2(x, y), V2(x + w, y + h), col(42,42,48), 12, nil, 1)
            imgui.SetCursorScreenPos(p0)
            imgui.Dummy(V2(full_w - 2, h + 6))
            return
        end
        PREP_LEFT = PREP_LEFT - 1
        local st = tonumber(s.status) or 0
        local lab = TOP_LABEL[st]
        local topw = lab and (TS(F.small, lab).x + 22) or 0
        local name = fitText(F.bold, U(s.name or ""), maxw - topw)
        cc = {
            mw = maxw, st = st, lab = lab, name = name,
            nx = lab and (TS(F.bold, name).x + 8) or 0,
            desc = fitText(F.small, U(s.description or ""), maxw),
            ver = U("v" .. (s.version or "?")),
            tags = {},
        }
        local tgx = 0
        for _, tag in ipairs(parseHashtags(s.hashtags)) do
            local lbl = U("#" .. tag)
            local ts = TS(F.small, lbl)
            local pw = ts.x + 12
            if tgx + pw > maxw then break end
            cc.tags[#cc.tags + 1] = { lbl = lbl, x = tgx, pw = pw, th = ts.y }
            tgx = tgx + pw + 6
        end
        s._cc = cc
    end

    local p1, p2 = V2(x, y), V2(x + w, y + h)
    if sel then
        dl:AddRectFilled(p1, p2, ACC.t(0.08), 12)
        dl:AddRect(p1, p2, ACC.c(), 12, nil, 1.5)
    else
        dl:AddRectFilled(p1, p2, hov and col(26,26,31) or col(20,20,24), 12)
        dl:AddRect(p1, p2, hov and col(62,62,70) or col(42,42,48), 12, nil, 1)
    end

    drawScriptIcon(dl, s, x + 12, y + 16, 58)

    T(dl, F.bold, tx, y + 10, CL.white, cc.name)
    if cc.lab then
        local st = cc.st
        local bg = (st == 3) and col(90,68,10) or (st == 2 and col(95,16,20) or col(50,50,56))
        local fg = (st == 3) and col(255,210,80) or (st == 2 and col(255,110,110) or col(200,200,205))
        pill(dl, tx + cc.nx, y + 11, cc.lab, F.small, bg, fg)
    end
    T(dl, F.small, tx, y + 35, CL.grey, cc.desc)

    local tgy = y + 60
    for _, tg in ipairs(cc.tags) do
        local gx = tx + tg.x
        dl:AddRectFilled(V2(gx, tgy), V2(gx + tg.pw, tgy + 22), col(34,34,39), 6)
        T(dl, F.small, gx + 6, tgy + (22 - tg.th)/2, col(170,170,178), tg.lbl)
    end

    local rx = x + w - RW
    T(dl, F.small, rx + 8, y + 9, CL.text, cc.ver)
    dl:AddCircleFilled(V2(rx + 12, y + 40), 3.5, installed and CL.green or col(120,120,128), 8)
    T(dl, F.small, rx + 20, y + 31, installed and CL.green or CL.grey,
        installed and U"Установлен" or U"Не установлен")

    local bh  = 34
    local by0 = y + 52
    imgui.SetCursorScreenPos(V2(rx + 6, by0))
    if redButton("##act", installed and U"Обновить" or U"Скачать", 98, bh, nil, F.bold, loading) then
        selectScript(s)
        if installed then updateScript(s) else downloadScript(s, false) end
    end
    imgui.SetCursorScreenPos(V2(rx + 110, by0))
    if iconButton("##more", 34, bh, IC.dots) then imgui.OpenPopup("##morepop") end

    if imgui.IsPopupOpen("##morepop") then
        imgui.SetNextWindowSize(V2(210, 0))
        pushPopupStyle()
        if imgui.BeginPopup("##morepop") then
            if menuItem("##m_open", U"Подробнее", IC.info) then selectScript(s) end
            if installed then
                if menuItem("##m_upd", U"Обновить", IC.refresh) and not loading then selectScript(s); updateScript(s) end
            else
                if menuItem("##m_dl", U"Скачать", IC.download) and not loading then selectScript(s); downloadScript(s, false) end
            end
            if menuItem("##m_tg", U"Telegram автора", IC.plane) then openTelegram(s) end
            if installed then
                if menuItem("##m_del", U"Удалить", IC.trash, true) and not loading then deleteScript(s) end
            end
            imgui.EndPopup()
        end
        popPopupStyle()
    end

    imgui.SetCursorScreenPos(p0)
    imgui.Dummy(V2(full_w - 2, h + 6))
end

local function drawDetails(x0, y0, w, h, base_alpha)
    local dl = imgui.GetWindowDrawList()
    local s = nil
    if selected_script_file then
        for _, it in ipairs(scripts_list) do
            if it.file == selected_script_file then s = it; break end
        end
    end

    UI_ALPHA = base_alpha
    dl:AddRectFilled(V2(x0, y0), V2(x0+w, y0+h), CL.panel, 12)
    dl:AddRect(V2(x0, y0), V2(x0+w, y0+h), ACC.t(0.2), 12, nil, 1)
    if not s then return end

    UI_ALPHA = base_alpha * ease(anim.content)
    local installed = isScriptInstalled(s)
    local tags = parseHashtags(s.hashtags)
    local pad = 16
    local x, y, iw = x0 + pad, y0 + pad, w - pad*2

    drawScriptIcon(dl, s, x, y, 56)
    local cbs = 34
    T(dl, F.h1, x + 68, y + 4, CL.white, fitText(F.h1, U(s.name or ""), iw - 68 - cbs - 6))
    imgui.SetCursorScreenPos(V2(x + iw - cbs, y))
    if iconButton("##det_close", cbs, cbs, IC.close, U"Скрыть (ESC)") then closePanel() end
    local pw = pill(dl, x + 68, y + 33, U("v" .. (s.version or "?")), F.small, CL.pill, CL.text)
    if installed then
        pill(dl, x + 68 + pw + 6, y + 33, U"Установлен", F.small, col(22,60,34), CL.green, CL.green)
    else
        pill(dl, x + 68 + pw + 6, y + 33, U"Не установлен", F.small, col(40,40,46), CL.grey, col(120,120,128))
    end
    y = y + 74

    local by = y0 + h - pad - (installed and 86 or 86)

    imgui.SetCursorScreenPos(V2(x, y))
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(UI_ALPHA, 0.001))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(0, 0))
    imgui.BeginChild("##det_scroll", V2(iw + 8, by - y - 12), false)
    local cdl = imgui.GetWindowDrawList()
    local cw = iw - 4

    local function block(hh, fn)
        local p = imgui.GetCursorScreenPos()
        fn(p.x, p.y)
        imgui.Dummy(V2(cw, hh))
    end
    block(28, function(bx, byy) T(cdl, F.bold, bx, byy, CL.white, U"Описание") end)
    local desc_txt = s._dt
    if not desc_txt then
        desc_txt = (s.description or ""):gsub("\\n", " ")
        s._dt = desc_txt
    end
    local dlines = wrapCached(s, "d", F.reg, U(desc_txt), cw)
    for _, ln in ipairs(dlines) do
        block(24, function(bx, byy) T(cdl, F.reg, bx, byy, col(200,200,206), ln) end)
    end
    imgui.Dummy(V2(cw, 10))

    local blocks = infoBlocks(s)
    if #blocks > 0 then
        block(28, function(bx, byy) T(cdl, F.bold, bx, byy, CL.white, U"О скрипте") end)
        for bi, b in ipairs(blocks) do
            if b.t == "gap" then
                imgui.Dummy(V2(cw, 8))
            elseif b.t == "head" then
                block(30, function(bx, byy)
                    cdl:AddRectFilled(V2(bx, byy+6), V2(bx+3, byy+22), CL.red, 2)
                    T(cdl, F.bold, bx + 10, byy + 3, CL.white, U(b.s))
                end)
            elseif b.t == "bullet" then
                local ls = wrapCached(s, bi, F.reg, U(b.s), cw - 26)
                for k, ln in ipairs(ls) do
                    block(24, function(bx, byy)
                        if k == 1 then
                            cdl:AddRectFilled(V2(bx, byy+3), V2(bx+17, byy+20), CL.red, 4)
                            IC.check(cdl, bx + 8.5, byy + 11.5, 12, ACC.fg())
                        end
                        T(cdl, F.reg, bx + 26, byy, col(212,212,218), ln)
                    end)
                end
                imgui.Dummy(V2(cw, 4))
            else
                for _, ln in ipairs(wrapCached(s, -bi, F.reg, U(b.s), cw)) do
                    block(24, function(bx, byy) T(cdl, F.reg, bx, byy, col(200,200,206), ln) end)
                end
            end
        end
        imgui.Dummy(V2(cw, 10))
    end

    block(28, function(bx, byy) T(cdl, F.bold, bx, byy, CL.white, U"Информация") end)
    local rows = {
        { U"Версия:",    U(s.version or "-") },
        { U"Автор:",     U(s.author or "-") },
        { U"Категория:", tags[1] and U(tags[1]) or "-" },
        { U"Тип:",       U(getScriptTypeName(s)) },
    }
    for _, r in ipairs(rows) do
        block(23, function(bx, byy)
            T(cdl, F.small, bx, byy, CL.grey, r[1])
            local vs = fitText(F.small, r[2], cw - 90)
            T(cdl, F.small, bx + cw - TS(F.small, vs).x, byy, CL.text, vs)
        end)
    end
    imgui.Dummy(V2(cw, 6))
    imgui.EndChild()
    imgui.PopStyleVar(3)

    dl:AddLine(V2(x, by - 8), V2(x + iw, by - 8), col(40,40,46), 1)

    imgui.SetCursorScreenPos(V2(x, by))
    local main_lbl = loading and U"Выполняется..." or (installed and U"Обновить скрипт" or U"Скачать скрипт")
    if redButton("##det_main", main_lbl, iw, 42, installed and IC.refresh or IC.download, F.bold, loading) then
        if installed then updateScript(s) else downloadScript(s, false) end
    end
    imgui.SetCursorScreenPos(V2(x, by + 52))
    if installed then
        local hw = (iw - 10) / 2
        if ghostButton("##det_tg", U"Telegram", hw, 34, IC.plane) then openTelegram(s) end
        imgui.SetCursorScreenPos(V2(x + hw + 10, by + 52))
        if ghostButton("##det_del", U"Удалить", hw, 34, IC.trash, true) then
            if not loading then deleteScript(s) end
        end
    else
        if ghostButton("##det_tg", U"Telegram автора", iw, 34, IC.plane) then openTelegram(s) end
    end
end

local function pageHeader(dl, x0, y0, title, subtitle)
    T(dl, F.h1, x0 + 20, y0 + 18, CL.white, title)
    if subtitle then T(dl, F.small, x0 + 21, y0 + 46, CL.grey, subtitle) end
end

local SETTINGS_ROWS = {
    { key = "notifications",    title = "Уведомления",
      desc = "Проверять уведомления разработчика при запуске" },
    { key = "auto_list_update", title = "Обновлять список при запуске",
      desc = "Скачивать список скриптов с GitHub при входе в игру. Вручную - кнопкой обновления" },
}

local function drawSettingsPage(x0, y0, w, h)
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(V2(x0, y0), V2(x0+w, y0+h), CL.panel, 12)
    dl:AddRect(V2(x0, y0), V2(x0+w, y0+h), CL.panelB, 12, nil, 1)
    pageHeader(dl, x0, y0, U"Настройки", U"Изменения сохраняются автоматически")

    local x, y, rw = x0 + 20, y0 + 84, w - 40
    imgui.SetCursorScreenPos(V2(x0 + 10, y0 + 76))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(0, 0))
    imgui.BeginChild("##set_scroll", V2(w - 20, h - 86), false)
    dl = imgui.GetWindowDrawList()
    local cp0 = imgui.GetCursorScreenPos()
    x, y, rw = cp0.x + 10, cp0.y + 8, w - 40
    for _, r in ipairs(SETTINGS_ROWS) do
        local on = settings[r.key]
        dl:AddRectFilled(V2(x, y), V2(x+rw, y+68), CL.card, 12)
        dl:AddRect(V2(x, y), V2(x+rw, y+68), on and ACC.t(0.35) or CL.cardB, 12, nil, 1)
        T(dl, F.bold, x + 18, y + 11, CL.white, U(r.title))
        T(dl, F.small, x + 18, y + 38, CL.grey, U(r.desc))
        toggleSwitch(r.key, x + rw - 18 - 48, y + 21)
        y = y + 76
    end

    do
        local ch = 72
        local auto = UIX.auto or 1
        local curS = UIX.pending or UIX.S
        local pct = math.floor(curS / auto * 100 + 0.5)
        local isAuto = (tonumber(settings.ui_scale) or 0) == 0
        dl:AddRectFilled(V2(x, y), V2(x+rw, y+ch), CL.card, 12)
        dl:AddRect(V2(x, y), V2(x+rw, y+ch), CL.cardB, 12, nil, 1)
        T(dl, F.bold, x + 18, y + 11, CL.white, U"Размер меню")
        T(dl, F.small, x + 18, y + 38, CL.grey, U"Меняется сразу, перезапуск не нужен")

        local by0 = y + (ch - 36) / 2
        local ax = x + rw - 18 - 86
        local px_ = ax - 8 - 40
        local vx = px_ - 8 - 104
        local mx = vx - 8 - 40
        local function setPct(np)
            np = math.max(40, np)
            local ns = auto * np / 100
            ns = math.max(0.6, math.min(UIX.maxS or 4, ns))
            UIX.pending = ns
            settings.ui_scale = (math.abs(ns - auto) < 0.01) and 0 or ns
            UIX.save_at = imgui.GetTime() + 0.6
        end
        imgui.SetCursorScreenPos(V2(mx, by0))
        if iconButton("##sc_minus", 40, 36, IC.minus) then setPct(pct - 10) end
        dl:AddRectFilled(V2(vx, by0), V2(vx+104, by0+36), col(19,19,23), 9)
        dl:AddRect(V2(vx, by0), V2(vx+104, by0+36), col(48,48,55), 9, nil, 1.2)
        local vt = U(pct .. "%" .. (isAuto and " авто" or ""))
        local vts = TS(F.bold, vt)
        T(dl, F.bold, vx + (104 - vts.x)/2, by0 + (36 - vts.y)/2, CL.white, vt)
        imgui.SetCursorScreenPos(V2(px_, by0))
        if iconButton("##sc_plus", 40, 36, IC.plus) then setPct(pct + 10) end
        imgui.SetCursorScreenPos(V2(ax, by0))
        if ghostButton("##sc_auto", U"Авто", 86, 36) then setPct(100) end
        y = y + ch + 8
    end

    y = y + 4
    dl:AddRectFilled(V2(x, y), V2(x+rw, y+106), CL.card, 12)
    dl:AddRect(V2(x, y), V2(x+rw, y+106), ACC.t(0.35), 12, nil, 1)
    T(dl, F.bold, x + 18, y + 11, CL.white, U"Цвет оформления")
    T(dl, F.small, x + 18, y + 36, CL.grey, U"Линии, рамки, кнопки и подсветка меню")
    local sx, sy = x + 30, y + 78
    for i, pr in ipairs(ACC.presets) do
        local cx = sx + (i - 1) * 40
        imgui.SetCursorScreenPos(V2(cx - 15, sy - 15))
        if imgui.InvisibleButton("##acc" .. i, V2(30, 30)) then
            ACC.set(pr[1], pr[2], pr[3]); ACC.save_at = imgui.GetTime() + 0.3
        end
        local hov = imgui.IsItemHovered()
        local sel = (ACC.r == pr[1] and ACC.g == pr[2] and ACC.b == pr[3])
        if sel then
            dl:AddCircle(V2(cx, sy), 17, CL.white, 32, 2)
        elseif hov then
            dl:AddCircle(V2(cx, sy), 16, col(255,255,255,90), 32, 1.5)
        end
        dl:AddCircleFilled(V2(cx, sy), 12, col(pr[1], pr[2], pr[3]), 32)
    end
    local ccx = sx + #ACC.presets * 40 + 4
    imgui.SetCursorScreenPos(V2(ccx - 14, sy - 14))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 14)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(6, 6))
    if imgui.ColorEdit3("##acc_custom", ACC.buf, imgui.ColorEditFlags.NoInputs + imgui.ColorEditFlags.NoLabel) then
        ACC.set(ACC.buf[0] * 255, ACC.buf[1] * 255, ACC.buf[2] * 255); ACC.save_at = imgui.GetTime() + 0.6
    end
    imgui.PopStyleVar(2)
    T(dl, F.small, ccx + 22, sy - 10, CL.grey, U"Свой цвет")
    if UIX.save_at and imgui.GetTime() > UIX.save_at then
        UIX.save_at = nil
        saveSettings()
    end
    if ACC.save_at and imgui.GetTime() > ACC.save_at then
        ACC.save_at = nil
        settings.accent_r, settings.accent_g, settings.accent_b = ACC.r, ACC.g, ACC.b
        saveSettings()
    end
    y = y + 106 + 10

    dl:AddRectFilled(V2(x, y), V2(x+rw, y+72), ACC.t(0.06), 12)
    dl:AddRect(V2(x, y), V2(x+rw, y+72), ACC.t(0.35), 12, nil, 1)
    T(dl, F.logo, x + 18, y + 8, CL.white, "Edward")
    local ew = TS(F.logo, "Edward ").x
    T(dl, F.logo, x + 18 + ew, y + 8, CL.red, "Script Center")
    pill(dl, x + 18 + ew + TS(F.logo, "Script Center ").x + 4, y + 14, "MOBILE", F.small, CL.red, ACC.fg())
    T(dl, F.small, x + 19, y + 44, CL.grey, U("Версия v" .. CURRENT_VERSION .. " Mobile   |   Автор: EdwardDisney0"))
    imgui.SetCursorScreenPos(V2(x + rw - 18 - 170, y + 18))
    if ghostButton("##set_tg", U"Наш Telegram", 170, 36, IC.plane) then openTelegram(nil) end
    imgui.SetCursorScreenPos(V2(x, y + 72 + 12))
    imgui.Dummy(V2(rw, 2))
    imgui.EndChild()
    imgui.PopStyleVar(2)
end

local function drawStatusBar(dl, wp, W, H, PAD, BAR_H, total_visible, installed_n)
    local bx, by, bw = wp.x + PAD, wp.y + H - PAD - BAR_H, W - PAD*2
    dl:AddRectFilled(V2(bx, by), V2(bx+bw, by+BAR_H), col(16,16,19), 10)
    dl:AddRect(V2(bx, by), V2(bx+bw, by+BAR_H), CL.panelB, 10, nil, 1)
    local cy = by + BAR_H/2
    local ty = cy - TS(F.small, "A").y/2
    local x = bx + 14

    local dotc, stxt
    if loading then dotc, stxt = col(240,200,40), U"Загрузка..."
    elseif conn_ok then dotc, stxt = CL.green, U"Соединение: стабильно"
    else dotc, stxt = col(235,60,60), U"Нет соединения" end
    if loading then
        local pulse = (math.sin(os.clock() * 6) + 1) / 2
        dl:AddCircleFilled(V2(x+4, cy), 4.5 + pulse*3, col(240,200,40, 60*(1-pulse)), 16)
    end
    dl:AddCircleFilled(V2(x+4, cy), 4.5, dotc, 12); x = x + 14
    T(dl, F.small, x, ty, CL.text, stxt); x = x + TS(F.small, stxt).x + 8

    local hb = 32
    imgui.SetCursorScreenPos(V2(x, cy - hb/2))
    local rp = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton("##reload", V2(hb, hb)) then manualRefresh() end
    local rh = imgui.IsItemHovered()
    IC.refresh(dl, rp.x+hb/2, rp.y+hb/2, 14, rh and CL.white or CL.grey)
    x = x + hb + 12

    local function divider()
        dl:AddLine(V2(x, by+9), V2(x, by+BAR_H-9), col(50,50,56), 1); x = x + 14
    end
    divider()
    local t1 = U("Скриптов в базе: " .. total_visible)
    T(dl, F.small, x, ty, CL.grey, t1); x = x + TS(F.small, t1).x + 14
    divider()
    local t2 = U("Установлено: " .. installed_n)
    T(dl, F.small, x, ty, CL.grey, t2); x = x + TS(F.small, t2).x + 14

    if has_new_notification then
        local nt = U"Уведомление"
        local nw = TS(F.small, nt).x + 38
        local nh = 30
        imgui.SetCursorScreenPos(V2(x, cy - nh/2))
        if redButton("##notif", nt, nw, nh, IC.bell, F.small) then openNotification() end
        x = x + nw + 12
    end

    local rx = bx + bw - 10
    imgui.SetCursorScreenPos(V2(rx - hb, cy - hb/2))
    local cp = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton("##close", V2(hb, hb)) then closeMainWindow() end
    local pressed = imgui.IsItemActive()
    dl:AddRectFilled(cp, V2(cp.x+hb, cp.y+hb), pressed and CL.redD or CL.red, 9)
    IC.close(dl, cp.x+hb/2, cp.y+hb/2, 14, ACC.fg())
    rx = rx - hb - 14

    if bw > 980 then
        local tgt = "Telegram - https://t.me/edward_scripts"
        local tw = TS(F.small, tgt).x
        local tgh = 30
        imgui.SetCursorScreenPos(V2(rx - tw - 22, cy - tgh/2))
        if imgui.InvisibleButton("##tglink", V2(tw + 22, tgh)) then openTelegram(nil) end
        local th = imgui.IsItemHovered()
        IC.plane(dl, rx - tw - 11, cy, 14, col(60,160,235))
        T(dl, F.small, rx - tw, ty, th and CL.white or CL.grey, tgt)
        rx = rx - tw - 22 - 12
        dl:AddLine(V2(rx, by+9), V2(rx, by+BAR_H-9), col(50,50,56), 1)
        rx = rx - 12
    end
    local byw = TS(F.bold, "By Edward").x
    T(dl, F.bold, rx - byw, cy - TS(F.bold, "By Edward").y/2, CL.red, "By Edward")
    rx = rx - byw - 16

    if status_text and status_text ~= "" and rx - x > 40 then
        T(dl, F.small, x, ty, CL.dim, fitText(F.small, status_text, rx - x))
    end
end

imgui.OnFrame(function() return main_window[0] end, function()
    PREP_LEFT = 3
    if UIX.pending then local pn = UIX.pending; UIX.pending = nil; UIX.setScale(pn) end
    tickDt()
    applyBaseStyle()
    anim.main = approach(anim.main, anim.main_target, 9)
    if anim.main_target == 0 and anim.main <= 0 then
        main_window[0] = false
        imgui.Process = notification_window[0]

        hover_anim, active_anim = {}, {}
        clearTexts()
        selected_script_file = nil
        anim.panel, anim.panel_target = 0, 0
        STYLE_DIRTY = true
        collectgarbage("step", 200)
        return
    end
    anim.panel   = approach(anim.panel, anim.panel_target, 5)
    anim.content = approach(anim.content, 1, 6)
    anim.page    = approach(anim.page, 1, anim.main < 1 and 3.5 or 6)
    if anim.panel_target == 0 and anim.panel <= 0 then selected_script_file = nil end

    local ma = ease(anim.main)
    UI_ALPHA = ma
    local sw, sh = UIX.screen()
    local W, H = UIX.winSize(sw, sh)
    if not (sw and sh and W and H) or sw < 64 or sh < 64 or W < 64 or H < 64 or W ~= W or H ~= H then
        UI_ALPHA = 1
        return
    end
    if not main_pos then main_pos = V2((sw - W)/2, (sh - H)/2) end
    imgui.SetNextWindowPos(V2(main_pos.x, main_pos.y + (1 - ma)*28), imgui.Cond.Always)
    imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(ma, 0.001))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.5)
    imgui.PushStyleColor(imgui.Col.WindowBg, v4(11,11,13,250))
    imgui.PushStyleColor(imgui.Col.Border,   v4(ACC.r*0.7, ACC.g*0.7, ACC.b*0.7, 255))
    imgui.Begin("##edward_script_center", nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar +
        imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove +
        (imgui.WindowFlags.NoFocusOnAppearing or 0))
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(3)
    pushF(F.reg)

    local wp = imgui.GetWindowPos()
    local dl = imgui.GetWindowDrawList()
    UIX.lightDL(dl)

    local PAD, GAP, SIDE_W, RIGHT_W, BAR_H = 14, 12, 240, 310, 40
    local top    = wp.y + PAD
    local colH   = H - PAD*2 - BAR_H - 10
    local sx0    = wp.x + PAD
    local cx0    = sx0 + SIDE_W + GAP
    local full_w = W - PAD*2 - SIDE_W - GAP

    local now = os.clock()
    local st_dirty = UIX.stats_dirty
    if st_dirty or now - ui_stats.t > 20.0 then
        ui_stats.t = now
        UIX.stats_dirty = false
        local prev_inst = ui_stats.installed
        ui_stats.total     = getVisibleScriptsCount()
        ui_stats.installed = countInstalledScripts()
        ui_stats.cats      = buildCategories()
        if library_filter == "installed" and (st_dirty or ui_stats.installed ~= prev_inst) then filterScripts() end
    end
    local total_visible = ui_stats.total
    local installed_n   = ui_stats.installed

    dl:AddRectFilled(V2(sx0, top), V2(sx0+SIDE_W, top+colH), CL.panel, 12)
    dl:AddRect(V2(sx0, top), V2(sx0+SIDE_W, top+colH), CL.panelB, 12, nil, 1)
    T(dl, F.logo, sx0+16, top+10, CL.white, "Edward")
    pill(dl, sx0+16 + TS(F.logo, "Edward").x + 10, top+16, "MOBILE", F.small, CL.red, ACC.fg())
    local scw = TS(F.logo, "Script ").x
    T(dl, F.logo, sx0+16,       top+40, CL.red,   "Script ")
    T(dl, F.logo, sx0+16 + scw, top+40, CL.white, "Center")
    T(dl, F.small, sx0+17, top+74, CL.grey, U"Скрипты для твоей игры")

    local navTop = top + 102
    local navH   = colH - 102 - 60
    imgui.SetCursorScreenPos(V2(sx0+10, navTop))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(2, 2))
    imgui.BeginChild("##sidenav", V2(SIDE_W-20, navH), false, imgui.WindowFlags.NoScrollbar)
    imgui.PopStyleVar()

    if navItem("##nav_all", IC.grid, U"Все скрипты", total_visible,
            main_active_tab == 0 and library_filter == "all") then
        switchPage(0); library_filter = "all"; category_filter = nil; filterScripts()
    end
    if navItem("##nav_inst", IC.installed, U"Установленные", installed_n,
            main_active_tab == 0 and library_filter == "installed") then
        switchPage(0); library_filter = "installed"; category_filter = nil; filterScripts()
    end

    sectionLabel(U"Категории")
    if navItem("##cat_all", IC.list, U"Все категории", total_visible,
            main_active_tab == 0 and category_filter == nil) then
        switchPage(0); category_filter = nil; filterScripts()
    end
    for k, cat in ipairs(ui_stats.cats) do
        if navItem("##cat_" .. k, catIcon(cat.name), U(cat.name), cat.count,
                main_active_tab == 0 and category_filter == cat.name) then
            switchPage(0); category_filter = cat.name; filterScripts()
        end
    end
    imgui.EndChild()

    imgui.SetCursorScreenPos(V2(sx0+12, top+colH-52))
    if navItem("##nav_set", IC.gear, U"Настройки", nil, main_active_tab == 2, SIDE_W-24, true) then
        switchPage((main_active_tab == 2) and 0 or 2)
    end

    local pe = ease(anim.page)
    local page_alpha = ma * pe
    local cx0_base = cx0
    cx0 = cx0 + math.floor((1 - pe) * 18)
    UI_ALPHA = page_alpha
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(page_alpha, 0.001))
    if main_active_tab == 0 then
        local pa = ease(anim.panel)
        local list_w = full_w - pa * (RIGHT_W + GAP)

        local sortW = 220
        local sbw = list_w - sortW - 10
        imgui.SetCursorScreenPos(V2(cx0, top))
        local search_changed = false
        do
            local p = V2(cx0, top)
            search_changed = inputField("##search", search_text, sbw, U"Поиск скриптов...", 38)
            IC.search(dl, p.x+20, p.y+20, 16, CL.grey)
        end
        if search_changed then filterScripts() end
        if ffi.string(search_text) ~= "" then
            imgui.SetCursorScreenPos(V2(cx0+sbw-32, top+9))
            local cp = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##sclear", V2(22, 22)) then
                search_text = imgui.new.char[256]()
                filterScripts()
            end
            IC.close(dl, cp.x+11, cp.y+11, 12, imgui.IsItemHovered() and CL.white or CL.grey)
        end

        local sx = cx0 + sbw + 10
        imgui.SetCursorScreenPos(V2(sx, top))
        if imgui.InvisibleButton("##sortbtn", V2(sortW, 40)) then imgui.OpenPopup("##sortpop") end
        local shov = imgui.IsItemHovered()
        local sopen = imgui.IsPopupOpen("##sortpop")
        dl:AddRectFilled(V2(sx, top), V2(sx+sortW, top+40), (shov or sopen) and col(26,26,31) or col(19,19,23), 10)
        dl:AddRect(V2(sx, top), V2(sx+sortW, top+40), sopen and col(205,35,42) or col(48,48,55), 10, nil, 1.2)
        IC.sort(dl, sx+20, top+20, 14, CL.text)
        local slbl = (sort_mode == 0) and U"Сначала популярные" or U"По алфавиту (А-Я)"
        T(dl, F.small, sx+36, top + (40 - TS(F.small, slbl).y)/2, CL.text, slbl)
        IC.chevron(dl, sx+sortW-20, top+20, 14, CL.grey)
        if sopen then
            imgui.SetNextWindowPos(V2(sx, top+46))
            imgui.SetNextWindowSize(V2(sortW, 0))
        end
        pushPopupStyle()
        if imgui.BeginPopup("##sortpop") then
            if menuItem("##srt0", U"Сначала популярные", nil, false, sort_mode == 0) then sort_mode = 0; filterScripts(); anim.page = 0 end
            if menuItem("##srt1", U"По алфавиту (А-Я)",  nil, false, sort_mode == 1) then sort_mode = 1; filterScripts(); anim.page = 0 end
            imgui.EndPopup()
        end
        popPopupStyle()

        local ly = top + 52
        imgui.SetCursorScreenPos(V2(cx0 - 4, ly))
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.BeginChild("##list", V2(list_w + 8, colH - 52), false)
        imgui.PopStyleVar()
        do
            local lp, ls = imgui.GetWindowPos(), imgui.GetWindowSize()
            UIX.clip0, UIX.clip1 = lp.y, lp.y + ls.y
        end
        if #filtered_scripts == 0 then
            local ldl = imgui.GetWindowDrawList()
            local p = imgui.GetCursorScreenPos()
            local msg = (#scripts_list > 0) and U"Ничего не найдено" or U"Список пуст - нажмите обновить внизу"
            T(ldl, F.reg, p.x + (list_w - TS(F.reg, msg).x)/2, p.y + 40, CL.grey, msg)
            imgui.Dummy(V2(list_w, 80))
        end
        for i, s in ipairs(filtered_scripts) do
            imgui.PushIDInt(i)
            drawScriptCard(s)
            imgui.PopID()
        end
        imgui.EndChild()

        if anim.panel > 0.001 then
            local px = cx0 + full_w - RIGHT_W + (1 - pa) * (RIGHT_W * 0.55)
            drawDetails(px, top, RIGHT_W, colH, page_alpha * pa)
            UI_ALPHA = page_alpha
        end

    else
        drawSettingsPage(cx0, top, full_w, colH)
    end
    imgui.PopStyleVar()
    cx0 = cx0_base
    UI_ALPHA = ma

    drawStatusBar(dl, wp, W, H, PAD, BAR_H, total_visible, installed_n)

    popF(F.reg)
    imgui.End()
    imgui.PopStyleVar()
    UI_ALPHA = 1
end)

imgui.OnFrame(function() return notification_window[0] end, function()
    tickDt()
    applyBaseStyle()
    anim.notif = approach(anim.notif, notif_closing and 0 or 1, 6)
    if notif_closing and anim.notif <= 0 then
        notification_window[0] = false
        notif_closing = false
        anim.notif_frames = 0
        return
    end
    local a = ease(anim.notif)
    UI_ALPHA = a
    local sw, sh = UIX.screen()
    if not (sw and sh) or sw < 64 or sh < 64 or sw ~= sw or sh ~= sh then
        UI_ALPHA = 1
        return
    end
    -- do not create both ImGui windows in the same moment: wait until the main window has settled
    if main_window[0] and (anim.main or 1) < 0.35 then
        UI_ALPHA = 1
        return
    end
    -- skip the first frames after the window is requested (ImGui state may still be settling)
    anim.notif_frames = (anim.notif_frames or 0) + 1
    if anim.notif_frames < 4 then
        UI_ALPHA = 1
        return
    end

    local W = math.min(580, sw - 24)
    pushF(F.reg)
    local lines = {}
    for para in (U(notification_text or "") .. "\n"):gmatch("(.-)\n") do
        if para == "" then lines[#lines+1] = ""
        else for _, ln in ipairs(wrapText(F.reg, para, W - 48)) do lines[#lines+1] = ln end end
    end
    popF(F.reg)
    local textH = math.min(#lines * 25, math.max(100, math.min(380, sh - 220)))
    local H = 96 + textH + 84

    local bg = imgui.GetBackgroundDrawList()
    bg:AddRectFilled(V2(0, 0), V2(sw, sh), col(0,0,0,120))

    imgui.SetNextWindowPos(V2(sw/2, sh/2 + (1 - a)*24), imgui.Cond.Always, V2(0.5, 0.5))
    imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(a, 0.001))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.5)
    imgui.PushStyleColor(imgui.Col.WindowBg, v4(14,14,17,252))
    imgui.PushStyleColor(imgui.Col.Border,   v4(ACC.r*0.75, ACC.g*0.75, ACC.b*0.75, 255))
    imgui.Begin("##edward_notification", nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        (imgui.WindowFlags.NoFocusOnAppearing or 0))
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(3)
    pushF(F.reg)

    local wp = imgui.GetWindowPos()
    local dl = imgui.GetWindowDrawList()
    UIX.lightDL(dl)
    local x, y = wp.x + 24, wp.y + 22
    dl:AddCircleFilled(V2(x + 22, y + 22), 22, ACC.t(0.3), 32)
    dl:AddCircle(V2(x + 22, y + 22), 22, ACC.k(0.95), 32, 1.5)
    IC.bell(dl, x + 22, y + 22, 20, CL.white)
    T(dl, F.h1, x + 58, y + 2, CL.white, U"Сообщение от разработчика")
    local sub = (notification_required_version ~= "")
        and U("Требуется версия v" .. notification_required_version .. " (у вас v" .. loadSavedVersion() .. ")")
        or U"Edward Script Center Mobile"
    T(dl, F.small, x + 58, y + 26, (notification_required_version ~= "") and col(255,110,110) or CL.grey, sub)
    y = wp.y + 84
    dl:AddLine(V2(wp.x + 24, y), V2(wp.x + W - 24, y), col(45,45,52), 1)

    imgui.SetCursorScreenPos(V2(wp.x + 24, y + 12))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(0, 0))
    imgui.BeginChild("##notif_text", V2(W - 40, textH), false)
    local cdl = imgui.GetWindowDrawList()
    for _, ln in ipairs(lines) do
        local p = imgui.GetCursorScreenPos()
        T(cdl, F.reg, p.x, p.y, col(210,210,216), ln)
        imgui.Dummy(V2(W - 48, 25))
    end
    imgui.EndChild()
    imgui.PopStyleVar(2)

    local bw2 = (W - 48 - 12) / 2
    local byy = wp.y + H - 24 - 42
    imgui.SetCursorScreenPos(V2(wp.x + 24, byy))
    local has_url = notification_update_url and notification_update_url ~= ""
    if redButton("##n_ok", has_url and U"Обновить" or U"Понятно", bw2, 42, has_url and IC.download or IC.check, F.bold) then
        has_new_notification = false
        saveNotificationCache(notification_pass, notification_text)
        if has_url then openUrl(notification_update_url) end
        closeNotification()
    end
    imgui.SetCursorScreenPos(V2(wp.x + 24 + bw2 + 12, byy))
    if ghostButton("##n_skip", U"Пропустить", bw2, 42) then closeNotification() end

    popF(F.reg)
    imgui.End()
    imgui.PopStyleVar()
    UI_ALPHA = 1
end)

function sampev.onServerMessage(color, text)
    local clean = text:gsub("{%x%x%x%x%x%x}","")
    if clean:find("event.setActiveView") then
        return false
    end
end

function migrateOldConfigs()
    ensureConfigDir()
    local old = getWorkingDirectory() .. "/config/"
    local list = {
        { old .. "scripts_cache.json",        CACHE_FILE,         '"scripts"' },
        { old .. "notification_cache.json",   NOTIFICATION_CACHE, '"pass"' },
        { old .. "script_center_version.txt", VERSION_FILE,       nil },
        { old .. "settings.json",             SETTINGS_FILE,      '"auto_list_update"' },
    }
    for _, m in ipairs(list) do
        if doesFileExist(m[1]) and not doesFileExist(m[2]) then
            local ours = true
            if m[3] then
                local f = io.open(m[1], "r")
                local c = f and f:read("*a") or ""
                if f then f:close() end
                ours = c:find(m[3], 1, true) ~= nil
            end
            if ours then os.rename(m[1], m[2]) end
        end
    end
end

local ec_ready = false

local function ecCommand()
    if not ec_ready then
        sampAddChatMessage("{FF0000}|{FFFFFF} Edward Script Center Mobile ещё загружается...", -1)
        return
    end
    if anim.main_target == 1 then closeMainWindow() else openMainWindow() end
end

local function escStep(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        print("[ESC] " .. name .. ": " .. tostring(err))
    end
    return ok
end

function onScriptTerminate(scr, quit)
    local ts = type(thisScript) == "function" and thisScript() or nil
    if ts == nil or scr == ts then
        pcall(function()
            main_window[0] = false
            notification_window[0] = false
            imgui.Process = false
        end)
    end
end

function main()

    if type(isSampAvailable) == "function" then
        while not isSampAvailable() do wait(100) end
    else
        wait(3000)
    end

    local reg_tries = 0
    while true do
        local ok = pcall(sampRegisterChatCommand, "ec", ecCommand)
        if ok then break end
        reg_tries = reg_tries + 1
        if reg_tries == 1 or reg_tries % 20 == 0 then
            print("[ESC] sampRegisterChatCommand пока недоступна, повтор...")
        end
        wait(500)
    end

    escStep("migrateOldConfigs", migrateOldConfigs)
    wait(200)
    pcall(function() if not doesDirectoryExist(INSTALL_PATHS.cleo) then createDirectory(INSTALL_PATHS.cleo) end end)
    escStep("saveCurrentVersion", saveCurrentVersion)
    escStep("loadSettings", loadSettings)
    escStep("ACC.set", function() ACC.set(settings.accent_r, settings.accent_g, settings.accent_b) end)
    wait(200)
    escStep("loadCachedScripts", loadCachedScripts)
    wait(200)

    escStep("ui_stats", function()
        ui_stats.total     = getVisibleScriptsCount()
        ui_stats.installed = countInstalledScripts()
        ui_stats.cats      = buildCategories()
    end)
    wait(300)
    ui_stats.fs_t = os.clock()
    ui_stats.t    = os.clock()
    connected_to_server = true
    check_delay_passed  = true
    ec_ready = true

    if type(sampGetGamestate) == "function" then
        local t = os.clock()
        while sampGetGamestate() ~= 3 and os.clock() - t < 60 do wait(100) end
    end
    if type(sampIsLocalPlayerSpawned) == "function" then
        local t = os.clock()
        while not sampIsLocalPlayerSpawned() and os.clock() - t < 60 do wait(100) end
    end
    wait(3000)

    sampAddChatMessage("{FF0000}|{FFFF00} Edward Script Center Mobile {FFFFFF}загружен", -1)
    sampAddChatMessage("{FF0000}|{c0c0c0} /ec {FFFFFF}- меню скриптов {FF0000}By {00FFFF}Edward", -1)

    lua_thread.create(function()
        wait(1500)
        escStep("syncWithGitHub", syncWithGitHub)
        escStep("loadScriptsListNow", loadScriptsListNow, false)
        wait(500)
        escStep("checkForNotification", checkForNotification)
        wait(500)
        escStep("checkScriptCenterUpdate", checkScriptCenterUpdate, true)
    end)
    wait(-1)
end
