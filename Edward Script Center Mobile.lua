script_name("Edward Script Center Mobile")
script_author("EdwardDisney0")
script_version("3.0")

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
        function DLM:AddImage(tex, a, b, uv0, uv1, col_) self.d:AddImage(tex, sv(a), sv(b), uv0, uv1, col_) end

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

CURRENT_VERSION = "3.0"

local GITHUB = {
    repo          = "EdwardDisney0/Edward-Scripts-New-Engine",
    branch        = "main",
    raw           = "https://raw.githubusercontent.com/",
    scripts_list  = "Sscripts.json",
    script_center = "Edward%20Script%20Center%20Mobile.lua",
    version       = "version.json",
    notification  = "notification.json",
}

local function rawUrl(path)
    return GITHUB.raw .. GITHUB.repo .. "/" .. GITHUB.branch .. "/" .. path .. "?t=" .. os.time()
end

local SCRIPT_CENTER_FILENAME = "Edward Script Center.lua"

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
        while not finished and not data_received do
            wait(50)
            waited = waited + 50

            if waited > 25000 then break end
        end
        wait(30)
        local complete = finished or data_received
        if doesFileExist(tmp_path) then
            local f = io.open(tmp_path, "rb")
            if f then local raw = f:read("*a"); f:close(); content = complete and cleanBody(raw) or "" end
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
    autumn           = true,
    winter_seen      = 0,
    accent_r = 226, accent_g = 32, accent_b = 40,
    ui_scale = 0,
}

local toggle_anim = {
    notifications    = 1.0,
    auto_update      = 1.0,
    auto_list_update = 1.0,
    autumn           = 1.0,
}

function saveSettings()
    ensureConfigDir()
    local f = io.open(SETTINGS_FILE, "w")
    if f then
        f:write(string.format(
            '{"notifications":%s,"auto_update":%s,"auto_list_update":%s,"autumn":%s,"winter_seen":%d,"accent_r":%d,"accent_g":%d,"accent_b":%d,"ui_scale":%s}',
            tostring(settings.notifications),
            tostring(settings.auto_update),
            tostring(settings.auto_list_update),
            tostring(settings.autumn),
            tonumber(settings.winter_seen) or 0,
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
    settings.autumn           = rb("autumn",           true)
    settings.winter_seen      = tonumber(c:match('"winter_seen"%s*:%s*(%d+)') or "") or 0
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
    toggle_anim.autumn           = settings.autumn           and 1.0 or 0.0
end

local function notify(msg)
    if settings.notifications then
        sampAddChatMessage(msg, 0xFFFFFF)
    end
end

local main_window         = imgui.new.bool(false)
local notification_window = imgui.new.bool(false)
local notif_open_pending = false

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

local function scriptDir()
    local ok, p = pcall(function() return thisScript().path end)
    if ok and type(p) == "string" and p ~= "" then
        local d = p:gsub("\\", "/"):match("^(.*)/[^/]+$")
        if d and d ~= "" then return d end
    end
    return getWorkingDirectory()
end

local function findAllScriptCenterFiles()
    local dir = scriptDir()
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
    tryAdd(dir .. "/" .. base_name .. ".luac")
    for n = 1, 50 do
        tryAdd(dir .. "/" .. base_name .. " (" .. n .. ")." .. base_ext)
        tryAdd(dir .. "/" .. base_name .. " (" .. n .. ").lua")
        tryAdd(dir .. "/" .. base_name .. " (" .. n .. ").luac")
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


UIX.su = { show = false, stage = "", ver = "", cur = "", p = 0, target = 0, a = 0,
           closing = false, msg = "", t_end = 0, dismissed = "",
           guard = CONFIG_DIR .. "/self_update.txt" }
do
    local su = UIX.su
    function su.set(stage, target, ver)
        su.stage = stage
        if target then su.target = target end
        if ver then su.ver = ver end
        su.cur = trimVer(CURRENT_VERSION)
        if not su.show then su.p = 0; su.a = 0 end
        su.show = true; su.closing = false
        imgui.Process = true
    end
    function su.fail(msg)
        su.msg = msg; su.stage = "error"; su.t_end = os.clock() + 6
        su.cur = trimVer(CURRENT_VERSION)
        su.show = true; su.closing = false
        imgui.Process = true
        sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}" .. msg, 0xFFFFFF)
    end
    function su.selfPath()
        local ok, p = pcall(function() return thisScript().path end)
        if ok and p and p ~= "" then return (p:gsub("\\", "/")) end
        return getWorkingDirectory() .. "/" .. SCRIPT_CENTER_FILENAME
    end
    
    function su.unloadByPath(path)
        local lp = path:lower()
        if lp == su.selfPath():lower() then return end
        local ok, list = pcall(script.list)
        if not ok or not list then return end
        for _, scr in ipairs(list) do
            local sp = ""
            pcall(function() sp = ((scr.path or ""):gsub("\\", "/")):lower() end)
            if sp == lp then pcall(function() scr:unload() end) end
        end
    end
    
    function su.valid(content)
        if not content or #content < 2048 then return false end
        local head = content:sub(1, 64):lower()
        if head:find("^%s*<!doctype") or head:find("^%s*<html") or head:find("^404") then return false end
        return true
    end
    
    function su.recentlyTried(ver)
        local f = io.open(su.guard, "r")
        if not f then return false end
        local cc = f:read("*a") or ""; f:close()
        local v, t = cc:match("^(.-)|(%d+)")
        return v == tostring(ver) and (os.time() - (tonumber(t) or 0)) < 21600
    end
    function su.mark(ver)
        ensureConfigDir()
        local f = io.open(su.guard, "w")
        if f then f:write(tostring(ver) .. "|" .. os.time()); f:close() end
    end
end

function checkScriptCenterUpdate(quiet)
    if not connected_to_server or not check_delay_passed then return end
    if update_done or update_in_progress then return end
    local su = UIX.su
    if not quiet then notify("{FF0000}|{FFFFFF} Проверяю обновления {C0C0C0}Script Center...") end

    httpGetAsync(rawUrl(GITHUB.version),
        function(response)
            local data = decodeJson(encoding.UTF8:decode(response.text))
            if data and data.version then
                local latest  = trimVer(data.version)
                local current = trimVer(CURRENT_VERSION)
                if verNum(latest) > verNum(current) then
                    local cached = loadNotificationCache()
                    if cached.pass and cached.pass:find("VERSION_CHECK_") then saveNotificationCache("", "") end
                    notify("{FF0000}|{FFFFFF} {00FF00}Доступна новая версия: {C0C0C0}v" .. latest .. " {FFFFFF}(у вас v" .. current .. ")")
                    if settings.auto_update and (not quiet or not su.recentlyTried(latest)) then
                        su.set("found", 0.05, latest)
                        wait(1300)
                        downloadScriptCenterUpdate(latest)
                    elseif su.dismissed ~= latest then
                        su.set("ask", 0, latest)
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
                    wait(2000); notif_open_pending=true; has_new_notification=true
                    notify("{FF0000}|{FFFFFF} {FF0000}ВНИМАНИЕ! {FFFFFF}Требуется обновление {C0C0C0}Script Center! {FFFFFF}Откройте {C0C0C0}/ec")
                    saveNotificationCache("VERSION_CHECK_"..github_req_ver, github_message)
                elseif github_pass ~= (cached.pass or "") then
                    notif_open_pending=true; has_new_notification=true
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
                checkAndDeleteMarkedScripts(); wait(0)
                sortScriptsByStatus(); filterScripts(); invalidateInstallCache()
                status_text=u8("Загружено скриптов: "..#filtered_scripts.."  |  обновлено в "..os.date("%H:%M:%S"))
                if not quiet then notify("{FF0000}|{FFFFFF} Загружено {C0C0C0}"..#filtered_scripts.."{FFFFFF} скриптов") end
                wait(0); saveCachedScripts()
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
                wait(50)
                if os.remove(op) then sampAddChatMessage("{FF0000}|{FFFFFF} Старый файл {00FF00}удалён!",0xFFFFFF); wait(50)
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
                            wait(100)
                            local script_filename = script_info.file
                            if del_dup then
                                status_text = u8"Обнаружены дубликаты! Делаю полную перезагрузку..."
                                sampAddChatMessage("{FF0000}|{FFFFFF} {FF0000}ВНИМАНИЕ! {FFFFFF}Дубликаты — полная перезагрузка...",0xFFFFFF)
                                wait(200); reloadScripts()
                            else
                                local already_loaded = false
                                for _, scr in ipairs(script.list()) do
                                    if scr.filename == script_filename then
                                        already_loaded = true
                                        sampAddChatMessage("{FF0000}|{FFFFFF} Перезагружаю только {C0C0C0}"..name.."...",0xFFFFFF)
                                        wait(100); scr:reload()
                                        status_text = u8(res:gsub("^%l",string.upper).."! Перезагружен")
                                        sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Скрипт перезагружен!",0xFFFFFF)
                                        break
                                    end
                                end
                                if not already_loaded then
                                    sampAddChatMessage("{FF0000}|{FFFFFF} Загружаю {C0C0C0}"..name.." {FFFFFF}впервые...",0xFFFFFF)
                                    wait(100); script.load(script_filename)
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
    local su = UIX.su
    if update_in_progress then sampAddChatMessage("{FF0000}|{FFFFFF} {FF8800}Обновление уже выполняется...", 0xFFFFFF); return end
    if update_done then sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Скрипт уже обновлён.", 0xFFFFFF); return end
    update_in_progress = true
    su.mark(new_version)

    local dir       = scriptDir()
    local target    = dir .. "/" .. SCRIPT_CENTER_FILENAME
    local self_path = su.selfPath()
    local same_name = (self_path:lower() == target:lower())
    local tmp       = target .. ".new"
    local function fail(msg)
        os.remove(tmp)
        update_in_progress = false
        su.fail(msg)
    end
    su.set("download", 0.15, new_version)
    sampAddChatMessage("{FF0000}|{FFFFFF} Скачиваю {C0C0C0}новую версию v" .. new_version .. "...", 0xFFFFFF)

    httpGetAsync(rawUrl(GITHUB.script_center),
        function(response)
            local content = response.content or response.text
            if not su.valid(content) then fail("Ошибка: скачанный файл пуст или повреждён!"); return end
            local ld = loadstring or load
            if not ld(content) then fail("Ошибка: скачанный скрипт повреждён (синтаксис)!"); return end
            su.set("install", 0.72)

            
            os.remove(tmp)
            local outf = io.open(tmp, "wb")
            if not outf then fail("Ошибка: не удалось создать файл!"); return end
            outf:write(content); outf:close(); wait(100)
            local vf = io.open(tmp, "rb")
            local size = vf and vf:seek("end") or 0
            if vf then vf:close() end
            if size ~= #content then fail("Верификация провалена: файл записан не полностью!"); return end
            su.target = 0.86

            if same_name then
                
                local backup = target .. ".bak"
                os.remove(backup)
                if not os.rename(target, backup) then fail("Ошибка: не удалось заменить текущий файл!"); return end
                if not os.rename(tmp, target) then
                    os.rename(backup, target)
                    fail("Ошибка: не удалось установить новый файл!"); return
                end
                os.remove(backup)
                for _, p in ipairs(findAllScriptCenterFiles()) do
                    if p:lower() ~= target:lower() and not p:lower():find("%.new$") then
                        su.unloadByPath(p); wait(50); os.remove(p); wait(30)
                    end
                end
                local vw = io.open(VERSION_FILE, "w"); if vw then vw:write(new_version); vw:close() end
                update_in_progress = false; update_done = true
                su.set("restart", 1.0)
                sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Обновление установлено! v" .. new_version, 0xFFFFFF)
                sampAddChatMessage("{FF0000}|{FFFFFF} Перезагрузка через 2 секунды...", 0xFFFFFF)
                wait(2000); thisScript():reload()
                return
            end

            
            
            sampAddChatMessage("{FF0000}|{FFFFFF} Файл запущен под именем {C0C0C0}" .. (self_path:match("[^/]+$") or self_path) ..
                "{FFFFFF}, ставлю новую версию отдельно...", 0xFFFFFF)
            local tf = io.open(target, "rb")
            if tf then
                tf:close()
                su.unloadByPath(target); wait(200)
                if not os.remove(target) then
                    os.remove(target .. ".old")
                    if not os.rename(target, target .. ".old") then fail("Ошибка: не удалось освободить имя " .. SCRIPT_CENTER_FILENAME); return end
                end
            end
            if not os.rename(tmp, target) then fail("Ошибка: не удалось установить новый файл!"); return end
            for _, p in ipairs(findAllScriptCenterFiles()) do
                local lp = p:lower()
                if lp ~= target:lower() and lp ~= self_path:lower() and not lp:find("%.new$") then
                    su.unloadByPath(p); wait(50); os.remove(p); wait(30)
                end
            end
            os.remove(target .. ".old")

            local ok, res = pcall(script.load, target)
            if not ok or not res then ok, res = pcall(script.load, SCRIPT_CENTER_FILENAME) end
            if not ok or not res then
                
                update_in_progress = false
                su.fail("Не удалось запустить новую версию, перезапустите игру")
                return
            end
            local vw = io.open(VERSION_FILE, "w"); if vw then vw:write(new_version); vw:close() end
            update_in_progress = false; update_done = true
            su.set("restart", 1.0)
            sampAddChatMessage("{FF0000}|{FFFFFF} {00FF00}Обновление установлено! v" .. new_version, 0xFFFFFF)
            wait(600)
            os.remove(self_path)
            thisScript():unload()
        end,
        function(err)
            update_in_progress = false
            su.fail("Ошибка скачивания: " .. tostring(err))
        end
    )
end

local manual_busy = false
function manualRefresh()
    if manual_busy or loading or update_in_progress then return end
    manual_busy = true
    lua_thread.create(function()
        loadScriptsListNow(false, true)
        checkForNotification(true)
        checkScriptCenterUpdate(false)
        manual_busy = false
    end)
end




do
local SNOW_W, SNOW_H = 1199, 262



local SNOW = {
    side   = { x =    3, y =   3, w =  249, h =  96, ay = 17.7, ol = 7, orr = 0, cuts = { 41,148,172 } },
    search = { x =    3, y = 191, w =  686, h =  68, ay = 9.5, ol = 2, orr = 0, cuts = { 49,93,144,197,210,223,292,305,348,380,439,452,493,506,519,532,545,591,604,619,664 } },
    sort   = { x =  255, y =   3, w =  227, h =  95, ay = 10.8, ol = 1, orr = 0, cuts = { 30,45,58,86,114,127,158 } },
    bar    = { x =    3, y = 105, w = 1193, h =  80, ay = 35.5, ol = 8, orr = 3, cuts = { 207,293,308,329,353,421,438,451,464,481,494,507,581,597,610,623,638,651,664,677,719,748,789,804,817,830,843,899,913,946,1013,1039,1053,1066,1079,1092,1144 } },
    btn    = { x =  924, y = 191, w =  112, h =  30, ay = 5.5, ol = 5, orr = 8, cuts = { 28,41,54,67,80 } },
    nav    = { x =  692, y = 191, w =  229, h =  50, ay = 11.2, ol = 5, orr = 2, cuts = { 31,76,89,154 } },
    card   = { x = 1039, y = 191, w =   62, h =  24, ay = 2.3, ol = 0, orr = 0, cuts = { 31 } },
}
local SNOW_B64 = [==[
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
]==]

local function b64decode(s)
    local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local map = {}
    for i = 1, 64 do map[abc:byte(i)] = i - 1 end
    s = (s:gsub("[^A-Za-z0-9%+/]", ""))
    local n = #s
    local buf = ffi.new("uint8_t[?]", math.floor(n * 3 / 4) + 4)
    local byte, floor = string.byte, math.floor
    local o, i, k = 0, 1, 0
    while i + 3 <= n do
        local a, b, c2, d = byte(s, i, i + 3)
        local v = map[a] * 262144 + map[b] * 4096 + map[c2] * 64 + map[d]
        buf[o] = floor(v / 65536); buf[o + 1] = floor(v / 256) % 256; buf[o + 2] = v % 256
        o = o + 3; i = i + 4; k = k + 1
        if k >= 6000 then k = 0; wait(0) end
    end
    local rem = n - i + 1
    if rem == 2 then
        local v = map[byte(s, i)] * 262144 + map[byte(s, i + 1)] * 4096
        buf[o] = floor(v / 65536); o = o + 1
    elseif rem == 3 then
        local v = map[byte(s, i)] * 262144 + map[byte(s, i + 1)] * 4096 + map[byte(s, i + 2)] * 64
        buf[o] = floor(v / 65536); buf[o + 1] = floor(v / 256) % 256; o = o + 2
    end
    return ffi.string(buf, o)
end

local S = { W = SNOW_W, H = SNOW_H, atlas = SNOW, tex = nil, gen = false }
UIX.snow = S

local function texOk(t)
    if t == nil or t == false then return false end
    local n = tonumber(t)
    return n ~= nil and n ~= 0
end

local function makeTexture(data)
    local ok, t = pcall(function() return imgui.CreateTextureFromMemory(data, #data) end)
    if ok and texOk(t) then return t end
    pcall(ensureConfigDir)
    local path = CONFIG_DIR .. "/_snow_" .. os.time() .. ".png"
    local f = io.open(path, "wb")
    if f then
        f:write(data); f:close()
        ok, t = pcall(imgui.CreateTextureFromFile, path)
        os.remove(path)
        if ok and texOk(t) then return t end
    end
    return false
end


function S.ensure()
    if S.tex ~= nil then return end
    if not S.gen then
        S.gen = true
        lua_thread.create(function()
            local ok, data = pcall(b64decode, SNOW_B64)
            S.png = (ok and data) or false
        end)
    elseif S.png ~= nil then
        local data = S.png
        S.png = nil
        S.tex = data and makeTexture(data) or false
    end
end
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

do
    local last_text, last_font, last_width, last_scale, last_rows, last_height
    function UIX.notificationLayout(text, font, width)
        text = tostring(text or "")
        if text == last_text and font == last_font and width == last_width and UIX.S == last_scale then
            return last_rows, last_height
        end
        local body = text:gsub("\r\n", "\n"):gsub("\r", "\n")
        body = body:gsub("([%.%!%?]) +([A-Z\192-\223\168])", "%1\n\n%2")
        body = body:gsub("\n[ \t]*\n[ \t\n]*", "\n\n")
        body = body:gsub("^%s+", ""):gsub("%s+$", "")
        local rows, height = {}, 0
        for paragraph in (body .. "\n"):gmatch("(.-)\n") do
            if paragraph == "" then
                rows[#rows + 1] = ""
                height = height + 12
            else
                for _, line in ipairs(wrapText(font, U(paragraph), width)) do
                    rows[#rows + 1] = line
                    height = height + 25
                end
            end
        end
        last_text, last_font, last_width, last_scale = text, font, width, UIX.S
        last_rows, last_height = rows, height
        return rows, height
    end
end

UIX.mainDrag = { active = false, dx = 0, dy = 0 }

function UIX.dragMain(sw, sh, offset)
    local drag = UIX.mainDrag
    local minX, maxX = -154, math.max(-154, sw - 114)
    local maxY = math.max(0, sh - 94)
    main_pos.x = math.max(minX, math.min(maxX, main_pos.x))
    main_pos.y = math.max(0, math.min(maxY, main_pos.y))
    if notification_window[0] or UIX.su.show or anim.main_target ~= 1 then
        drag.active = false
        return
    end
    local io = imgui.GetIO()
    if not io.MouseDown[0] then drag.active = false; return end
    local mx, my = io.MousePos.x / UIX.S, io.MousePos.y / UIX.S
    if imgui.IsMouseClicked(0) then
        local x, y = main_pos.x + 14, main_pos.y + offset + 14
        drag.active = mx >= x and mx <= x + 240 and my >= y and my <= y + 80
        if drag.active then drag.dx, drag.dy = mx - main_pos.x, my - main_pos.y - offset end
    end
    if drag.active then
        main_pos.x = math.max(minX, math.min(maxX, mx - drag.dx))
        main_pos.y = math.max(0, math.min(maxY, my - drag.dy - offset))
    end
end

UIX.onScale = function()
    UIX.mainDrag.active = false
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
        local blocked = false
        if key == "autumn" and not settings.autumn and UIX.snow and UIX.snow.auto and not UIX.snow.auto() then
            blocked = true 
        end
        if not blocked then settings[key] = not settings[key] end
        if key == "autumn" and not settings.autumn and UIX.snow then UIX.snow.test = false end
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
    UIX.mainDrag.active = false
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
    { key = "auto_update",      title = "Авто-обновление Script Center",
      desc = "Сам скачивать и устанавливать новые версии Script Center, затем перезапускаться" },
    { key = "autumn",           title = "Сезонное оформление",
      desc = "Праздничное оформление меню" },
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

do


local S = UIX.snow
S.test, S.show = false, false
S.plans, S.plan_n = {}, 0
local auto_v, chk = false, -100

function S.auto()
    local d = os.date("*t")
    local md = d.month * 100 + d.day
    return md >= 1201 or md <= 220
end

function S.autoEnable()
    local d = os.date("*t")
    local md = d.month * 100 + d.day
    return md >= 1201 or md <= 110
end
function S.on()
    if S.test then return S.auto() end
    local cl = os.clock()
    if cl - chk > 30 then chk = cl; auto_v = S.auto() end
    return auto_v
end
function S.seasonCheck()
    if not S.auto() then
        
        if settings.autumn then settings.autumn = false; saveSettings() end
        return
    end
    if not S.autoEnable() then return end
    local d = os.date("*t")
    local season = (d.month == 12) and d.year or (d.year - 1)
    if settings.winter_seen == season then return end
    settings.winter_seen = season
    settings.autumn = true
    toggle_anim.autumn = 1.0
    saveSettings()
end

function S.frame()
    local cl = os.clock()
    if cl - (S.seasonT or -100) > 30 then S.seasonT = cl; pcall(S.seasonCheck) end
    S.show = (settings.autumn or S.test) and S.on()
    if S.show then S.ensure() end
end

function S.plan(kind, tw)
    local pk = S.plans[kind]
    if not pk then pk = {}; S.plans[kind] = pk end
    tw = math.floor(tw + 0.5)
    local pl = pk[tw]
    if pl then return pl end
    local P = S.atlas[kind]
    pl = {}
    local function item(dx, dw, ua, ub)
        pl[#pl + 1] = { dx = dx, dw = dw,
            uv0 = V2((P.x + ua) / S.W, P.y / S.H),
            uv1 = V2((P.x + ub) / S.W, (P.y + P.h) / S.H) }
    end
    local cuts = P.cuts
    local n = #cuts
    local eL, eR = cuts[1], P.w - cuts[n]
    local mid = tw - eL - eR
    local list, total = {}, 0
    if not ((tw > P.w * 0.9 and tw < P.w * 1.1) or n < 2 or mid < 10) then
        local i = 1
        while total < mid - 0.5 and #list < 300 do
            local Lw = cuts[i + 1] - cuts[i]
            if total > 0 and total + Lw - mid > Lw * 0.5 then break end
            list[#list + 1] = i
            total = total + Lw
            i = i + 1
            if i >= n then i = 1 end
        end
    end
    if total <= 0 then
        item(0, tw, 0, P.w)
    else
        local f = mid / total
        item(0, eL, 0, cuts[1])
        local px, a, prev = eL, list[1], list[1]
        for k = 2, #list + 1 do
            local cur = list[k]
            if cur ~= prev + 1 then
                local ua, ub = cuts[a], cuts[prev + 1]
                local sw = (ub - ua) * f
                item(px, sw, ua, ub)
                px = px + sw
                a = cur
            end
            prev = cur
        end
        item(tw - eR, eR, cuts[n], P.w)
    end
    S.plan_n = S.plan_n + 1
    if S.plan_n > 300 then S.plans = {}; S.plan_n = 0; pk = {}; S.plans[kind] = pk end
    pk[tw] = pl
    return pl
end

function S.cap(dl, x, y, w, kind, al)
    local tex = S.tex
    if not tex then return end
    local P = S.atlas[kind]
    if not P then return end
    local white = col(255, 255, 255, 255 * (al or 1))
    local x0, tw, yi = x - P.ol, w + P.ol + P.orr, y - P.ay
    local pl = S.plan(kind, tw)
    local y2 = yi + P.h
    for i = 1, #pl do
        local it = pl[i]
        local ax = x0 + it.dx
        dl:AddImage(tex, V2(ax, yi), V2(ax + it.dw, y2), it.uv0, it.uv1, white)
    end
end
end

local function drawStatusBar(dl, wp, W, H, PAD, BAR_H, total_visible, installed_n)
    local bx, by, bw = wp.x + PAD, wp.y + H - PAD - BAR_H, W - PAD*2
    dl:AddRectFilled(V2(bx, by), V2(bx+bw, by+BAR_H), col(16,16,19), 10)
    if UIX.snow.show then UIX.snow.cap(dl, bx + 4, by + 1, bw - 8, "bar") end
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
    if UIX.snow and UIX.snow.frame then UIX.snow.frame() end
    anim.main = approach(anim.main, anim.main_target, 9)
    if anim.main_target == 0 and anim.main <= 0 then
        main_window[0] = false
        imgui.Process = notification_window[0] or UIX.su.show

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
    if not main_pos then main_pos = V2((sw - W)/2, (sh - H)/2) end
    UIX.dragMain(sw, sh, (1 - ma)*28)
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
        imgui.WindowFlags.NoFocusOnAppearing)
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
    if UIX.snow.show then UIX.snow.cap(dl, sx0 + 2, top + 1, SIDE_W - 4, "side") end
    T(dl, F.logo, sx0+16, top+10, CL.white, "Edward")
    pill(dl, sx0+16 + TS(F.logo, "Edward").x + 10, top+16, "MOBILE", F.small, CL.red, ACC.fg())
    local scw = TS(F.logo, "Script ").x
    T(dl, F.logo, sx0+16,       top+40, CL.red,   "Script ")
    T(dl, F.logo, sx0+16 + scw, top+40, CL.white, "Center")
    T(dl, F.small, sx0+17, top+74, CL.grey, fitText(F.small, U"Зажмите заголовок и двигайте", SIDE_W - 32))

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
        if UIX.snow.show then
            UIX.snow.cap(dl, cx0, top + 1, sbw, "search")
            UIX.snow.cap(dl, sx, top + 1, sortW, "sort")
        end
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
        if #filtered_scripts > 0 then
            local origin = imgui.GetCursorScreenPos()
            local spacing = imgui.GetStyle().ItemSpacing.y / UIX.S
            local stride = 96 + spacing
            local count = #filtered_scripts
            local first = math.max(1, math.min(count, math.floor((UIX.clip0 - origin.y) / stride)))
            local last = math.max(first, math.min(count, math.ceil((UIX.clip1 - origin.y) / stride) + 1))
            if first > 1 then imgui.Dummy(V2(list_w, (first - 1) * stride - spacing)) end
            for i = first, last do
                imgui.PushIDInt(i)
                drawScriptCard(filtered_scripts[i])
                imgui.PopID()
            end
            if last < count then imgui.Dummy(V2(list_w, (count - last) * stride - spacing)) end
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

imgui.OnFrame(function()
    if notif_open_pending then notif_open_pending = false; openNotification() end
    return notification_window[0]
end, function()
    tickDt()
    applyBaseStyle()
    anim.notif = approach(anim.notif, notif_closing and 0 or 1, 6)
    if notif_closing and anim.notif <= 0 then
        notification_window[0] = false
        notif_closing = false
        return
    end
    local a = ease(anim.notif)
    UI_ALPHA = a
    local sw, sh = UIX.screen()

    local W = math.min(580, sw - 24)
    local lines, contentH = UIX.notificationLayout(notification_text, F.reg, W - 48)
    local textH = math.min(contentH, math.max(100, math.min(380, sh - 220)))
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
        imgui.WindowFlags.NoFocusOnAppearing)
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
    T(dl, F.reg, x + 58, y + 2, CL.white, U"Сообщение от разработчика")
    local sub = (notification_required_version ~= "")
        and U("Требуется версия v" .. notification_required_version .. " (у вас v" .. loadSavedVersion() .. ")")
        or U"Edward Script Center Mobile"
    imgui.SetCursorScreenPos(V2(x + 58, y + 26))
    imgui.PushStyleColor(imgui.Col.Text, (notification_required_version ~= "") and v4(255,110,110,255) or v4(150,150,158,255))
    imgui.TextUnformatted(sub)
    imgui.PopStyleColor()
    y = wp.y + 84
    dl:AddLine(V2(wp.x + 24, y), V2(wp.x + W - 24, y), col(45,45,52), 1)

    imgui.SetCursorScreenPos(V2(wp.x + 24, y + 12))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(0, 0))
    imgui.BeginChild("##notif_text", V2(W - 40, textH), false)
    local cdl = imgui.GetWindowDrawList()
    for _, ln in ipairs(lines) do
        local p = imgui.GetCursorScreenPos()
        if ln ~= "" then T(cdl, F.reg, p.x, p.y, col(210,210,216), ln) end
        imgui.Dummy(V2(W - 48, ln == "" and 12 or 25))
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
        if has_url then
            local rv = notification_required_version
            if rv ~= "" and verNum(rv) > verNum(CURRENT_VERSION) and not update_in_progress then
                lua_thread.create(function() downloadScriptCenterUpdate(rv) end)
            else
                openUrl(notification_update_url)
            end
        end
        closeNotification()
    end
    imgui.SetCursorScreenPos(V2(wp.x + 24 + bw2 + 12, byy))
    if ghostButton("##n_skip", U"Пропустить", bw2, 42) then closeNotification() end

    popF(F.reg)
    imgui.End()
    imgui.PopStyleVar()
    UI_ALPHA = 1
end)

imgui.OnFrame(function() return UIX.su.show end, function()
    local su = UIX.su
    tickDt()
    applyBaseStyle()
    su.a = approach(su.a, su.closing and 0 or 1, 7)
    if su.closing and su.a <= 0 then
        su.show = false; su.closing = false
        imgui.Process = main_window[0] or notification_window[0]
        return
    end
    local now = os.clock()
    if su.stage == "error" and now > su.t_end then su.closing = true end
    local dt = math.min(0.1, now - (su.lt or now)); su.lt = now
    if su.stage == "download" then su.target = math.min(0.62, su.target + dt * 0.05) end
    su.p = approach(su.p, su.target, 3)

    local a = ease(su.a)
    UI_ALPHA = a
    local sw, sh = UIX.screen()
    local W = math.min(470, sw - 24)
    local asking = (su.stage == "ask")
    local busy = (su.stage == "download" or su.stage == "install" or su.stage == "found")
    local H = asking and 148 or 102

    imgui.SetNextWindowPos(V2(sw / 2, 14 - (1 - a) * 44), imgui.Cond.Always, V2(0.5, 0))
    imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(a, 0.001))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.5)
    imgui.PushStyleColor(imgui.Col.WindowBg, v4(14, 14, 17, 250))
    imgui.PushStyleColor(imgui.Col.Border,   v4(ACC.r * 0.75, ACC.g * 0.75, ACC.b * 0.75, 255))
    imgui.Begin("##edward_selfupdate", nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse +
        imgui.WindowFlags.NoFocusOnAppearing)
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(3)
    pushF(F.reg)

    local wp = imgui.GetWindowPos()
    local dl = imgui.GetWindowDrawList()
    UIX.lightDL(dl)
    local x, y = wp.x + 20, wp.y + 16
    local cx, cy = x + 22, y + 22
    local pulse = 0.5 + 0.5 * math.sin(now * 4.5)
    local icon = IC.download
    if su.stage == "download" or su.stage == "install" then icon = IC.refresh
    elseif su.stage == "restart" then icon = IC.check
    elseif su.stage == "error" then icon = IC.close end
    local err = (su.stage == "error")
    dl:AddCircleFilled(V2(cx, cy), 22, err and col(255, 70, 70, 70) or ACC.t(0.3), 32)
    dl:AddCircle(V2(cx, cy), 22 + (busy and pulse * 3 or 0), err and col(255, 90, 90) or ACC.k(0.95), 32, 1.5)
    icon(dl, cx, cy, 20, CL.white)

    T(dl, F.bold, x + 58, y - 1, CL.white, U"Обновление Script Center")
    local sub
    if err then sub = U(su.msg)
    else sub = U("v" .. su.cur .. "  ->  v" .. su.ver) end
    T(dl, F.small, x + 58, y + 24, err and col(255, 110, 110) or ACC.k(1.0), sub)

    local st = ({
        found    = "Найдена новая версия",
        ask      = "Доступна новая версия",
        download = "Скачиваю обновление...",
        install  = "Проверяю и устанавливаю...",
        restart  = "Готово! Перезапуск...",
    })[su.stage]
    if asking then
        T(dl, F.small, x, y + 54, CL.grey, U"Установить сейчас? Скрипт перезапустится сам")
    elseif st then
        T(dl, F.small, x, y + 54, CL.grey, U(st))
        if busy then
            local pc = U(string.format("%d%%", math.floor(su.p * 100 + 0.5)))
            local ts = TS(F.small, pc)
            T(dl, F.small, wp.x + W - 20 - ts.x, y + 54, CL.grey, pc)
        end
    end

    if not asking and not err then
        local bx, by, bw = wp.x + 20, wp.y + H - 20, W - 40
        dl:AddRectFilled(V2(bx, by), V2(bx + bw, by + 6), col(45, 45, 52), 3)
        local fw = bw * math.max(0.04, math.min(1, su.p))
        dl:AddRectFilled(V2(bx, by), V2(bx + fw, by + 6), ACC.k(1.0), 3)
        if busy then
            local sx = bx + ((now * 0.8) % 1) * fw
            local x1, x2 = math.max(bx, sx - 36), math.min(bx + fw, sx)
            if x2 > x1 then dl:AddRectFilled(V2(x1, by), V2(x2, by + 6), col(255, 255, 255, 70), 3) end
        end
    end

    if asking then
        local bw2 = (W - 40 - 12) / 2
        local byy = wp.y + H - 16 - 40
        imgui.SetCursorScreenPos(V2(wp.x + 20, byy))
        if redButton("##su_ok", U"Обновить", bw2, 40, IC.download, F.bold) then
            su.stage = "download"; su.target = 0.1
            local ver = su.ver
            lua_thread.create(function() downloadScriptCenterUpdate(ver) end)
        end
        imgui.SetCursorScreenPos(V2(wp.x + 20 + bw2 + 12, byy))
        if ghostButton("##su_later", U"Позже", bw2, 40) then
            su.dismissed = su.ver
            su.closing = true
        end
    end

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



function onScriptTerminate(scr, quitGame)
    if scr ~= thisScript() then return end
    pcall(sampUnregisterChatCommand, "ec")
    pcall(sampUnregisterChatCommand, "ecwinter")
    local S = UIX.snow
    if S then
        local t = S.tex
        S.tex, S.show, S.test = false, false, false
        if t and t ~= 0 then pcall(imgui.ReleaseTexture, t) end
    end
end

local function ecWinterCmd()
    local S = UIX.snow
    if not S.auto() then
        sampAddChatMessage("{FF0000}|{FFFFFF} Оформление недоступно (сезон закончился 20 февраля)", 0xFFFFFF)
        S.test = false
        return
    end
    S.test = not S.test
    sampAddChatMessage("{FF0000}|{FFFFFF} Тест зимнего оформления: " ..
        (S.test and "{00FF00}включено" or "{C0C0C0}выключено"), 0xFFFFFF)
end

function main()

    if type(isSampAvailable) == "function" then
        while not isSampAvailable() do wait(50) end
    else
        wait(1000)
    end

    local reg_tries = 0
    while true do
        local ok = pcall(sampRegisterChatCommand, "ec", ecCommand)
        if ok then break end
        reg_tries = reg_tries + 1
        if reg_tries == 1 or reg_tries % 20 == 0 then
            print("[ESC] sampRegisterChatCommand пока недоступна, повтор...")
        end
        wait(250)
    end

    pcall(sampRegisterChatCommand, "ecwinter", ecWinterCmd)

    
    escStep("migrateOldConfigs", migrateOldConfigs)
    pcall(function() if not doesDirectoryExist(INSTALL_PATHS.cleo) then createDirectory(INSTALL_PATHS.cleo) end end)
    escStep("saveCurrentVersion", saveCurrentVersion)
    escStep("loadSettings", loadSettings)
    escStep("ACC.set", function() ACC.set(settings.accent_r, settings.accent_g, settings.accent_b) end)
    wait(0)
    escStep("loadCachedScripts", loadCachedScripts)
    wait(0)

    escStep("ui_stats", function()
        ui_stats.total     = getVisibleScriptsCount()
        ui_stats.installed = countInstalledScripts()
        ui_stats.cats      = buildCategories()
    end)
    ui_stats.fs_t = os.clock()
    ui_stats.t    = os.clock()
    connected_to_server = true
    check_delay_passed  = true
    ec_ready = true

    
    if type(sampGetGamestate) == "function" then
        local t = os.clock()
        while sampGetGamestate() ~= 3 and os.clock() - t < 60 do wait(50) end
    end
    if type(sampIsLocalPlayerSpawned) == "function" then
        local t = os.clock()
        while not sampIsLocalPlayerSpawned() and os.clock() - t < 60 do wait(50) end
    end
    wait(1200)

    sampAddChatMessage("{FF0000}|{FFFF00} Edward Script Center Mobile {FFFFFF}загружен", -1)
    sampAddChatMessage("{FF0000}|{c0c0c0} /ec {FFFFFF}- меню скриптов {FF0000}By {00FFFF}Edward", -1)

    lua_thread.create(function()
        wait(500)
        escStep("loadScriptsListNow", loadScriptsListNow, false)
        wait(250)
        escStep("checkForNotification", checkForNotification, true)
        wait(250)
        escStep("checkScriptCenterUpdate", checkScriptCenterUpdate, true)
        while true do
            wait(1800000)
            if not update_in_progress and not update_done then
                escStep("checkScriptCenterUpdate", checkScriptCenterUpdate, true)
            end
        end
    end)
    wait(-1)
end
