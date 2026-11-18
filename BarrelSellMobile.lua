script_name('BarrelSell')
script_author('Edward')

pcall(require, 'lib.moonloader')
local imgui    = require 'mimgui'
local sampev   = require 'samp.events'
local inicfg   = require 'inicfg'
local encoding = require 'encoding'
local ffi      = require 'ffi'
encoding.default = 'CP1251'
local U8lib = encoding.UTF8

-- Файл можно сохранить и в UTF-8, и в Windows-1251: скрипт сам подстроится.
-- u8()     - строка из файла -> UTF-8 (для imgui и Telegram)
-- fromU8() - UTF-8 из imgui -> как в файле
-- toChat() - строка из файла -> CP1251 (для чата игры)
local FILE_UTF8 = (#'я' == 2)
local function u8(s)
    s = tostring(s or '')
    if FILE_UTF8 then return s end
    return U8lib(s)
end
local function fromU8(s)
    s = tostring(s or '')
    if FILE_UTF8 then return s end
    return U8lib:decode(s)
end
local function toChat(s)
    s = tostring(s or '')
    if FILE_UTF8 then return U8lib:decode(s) end
    return s
end

local function clampN(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
local function roundTenth(v) return math.floor(v * 10 + 0.5) / 10 end

-- обрезка строки по байтам без поломки UTF-8 символа на конце
local function cutStr(s, n)
    if #s <= n then return s end
    local t = s:sub(1, n)
    if FILE_UTF8 then
        local i = #t
        while i > 0 and t:byte(i) >= 128 and t:byte(i) < 192 do i = i - 1 end
        if i > 0 and t:byte(i) >= 192 then
            local b = t:byte(i)
            local need = b >= 240 and 4 or b >= 224 and 3 or 2
            if #t - i + 1 < need then t = t:sub(1, i - 1) end
        end
    end
    return t
end

-- ===================== МАСШТАБ (мобильная версия) =====================
-- MS    - масштаб меню (размер окна + шрифт), Z(n) - размер в пикселях с учётом MS
-- CUR_S - масштаб, на который делим CalcTextSize при рисовании оверлеев
local MS, ICON_K, CUR_S = 1, 1, 1
local function Z(n) return n * MS end
local FONT_MIN, FONT_MAX = 0.6, 2.0
local OV_MIN,   OV_MAX   = 0.5, 2.5

local function tsz(text)
    local v = imgui.CalcTextSize(text)
    return { x = v.x / CUR_S, y = v.y / CUR_S }
end

local RC_ALL = 15
do
    local ok, v = pcall(function()
        if imgui.DrawFlags and imgui.DrawFlags.RoundCornersAll then return imgui.DrawFlags.RoundCornersAll end
        if imgui.DrawCornerFlags and imgui.DrawCornerFlags.All then return imgui.DrawCornerFlags.All end
    end)
    if ok and v then RC_ALL = v end
end

-- обёртка над DrawList: все координаты и толщины масштабируются от точки (ox, oy)
local function scaled(dl, ox, oy, s)
    local V = imgui.ImVec2
    local function T(p) return V(ox + (p.x - ox) * s, oy + (p.y - oy) * s) end
    local P = {}
    function P:AddRectFilled(a, b, c, r, f)
        if f then return dl:AddRectFilled(T(a), T(b), c, (r or 0) * s, f) end
        return dl:AddRectFilled(T(a), T(b), c, (r or 0) * s)
    end
    function P:AddRect(a, b, c, r, f, th)
        return dl:AddRect(T(a), T(b), c, (r or 0) * s, f or RC_ALL, (th or 1) * s)
    end
    function P:AddRectFilledMultiColor(a, b, c1, c2, c3, c4)
        return dl:AddRectFilledMultiColor(T(a), T(b), c1, c2, c3, c4)
    end
    function P:AddText(p, c, t) return dl:AddText(T(p), c, t) end
    function P:AddLine(a, b, c, th) return dl:AddLine(T(a), T(b), c, (th or 1) * s) end
    function P:AddCircleFilled(c0, r, c, n) return dl:AddCircleFilled(T(c0), r * s, c, n or 0) end
    function P:AddCircle(c0, r, c, n, th) return dl:AddCircle(T(c0), r * s, c, n or 0, (th or 1) * s) end
    function P:AddConvexPolyFilled(arr, n, c)
        for i = 0, n - 1 do
            arr[i].x = ox + (arr[i].x - ox) * s
            arr[i].y = oy + (arr[i].y - oy) * s
        end
        return dl:AddConvexPolyFilled(arr, n, c)
    end
    return P
end

local function beginScale(v)
    local io  = imgui.GetIO()
    local old = io.FontGlobalScale
    io.FontGlobalScale = v
    return old
end

local function endScale(old, font)
    imgui.GetIO().FontGlobalScale = old
    if font then imgui.PushFont(font); imgui.PopFont() end
end

local function firstExisting(list)
    for _, p in ipairs(list) do
        if p and doesFileExist(p) then return p end
    end
end

-- ===================== НАСТРОЙКИ =====================
local LIMIT          = 50          -- сервер может поправить из сообщения про лимит
local WINDOW         = 7 * 60      -- то же самое
local STARTUP_IGNORE = 5
local DUP_WINDOW     = 0.5
local CFG_FILE       = 'BarrelSell.ini'
local LOG_FILE       = getWorkingDirectory() .. '/config/BarrelSell.log'
local LOG_KEEP       = 300

local ANIM_BLOCK_TIME = 3

local TRUNK_FILE     = getWorkingDirectory() .. '/config/BarrelSell.trunks'
local BARREL_IDS     = { [8480] = true, [8481] = true }   -- ID бочек
local BARREL_LITERS  = 100                                 -- литров в новой бочке
local DECAY_SEC      = 8 * 3600                            -- -1 л каждые 8 часов

local VEH_VERSION    = 2
local MENU_W, MENU_H = 920, 640

-- мобильные настройки интерфейса
local DEF_FONT = 1.1
local DEF_OV   = 1.0
do
    local ok, _, h = pcall(getScreenResolution)
    if ok and tonumber(h) then DEF_OV = roundTenth(clampN(h / 560, 0.8, 1.4)) end
end
local BTN_X, BTN_Y = 0.92, 0.06      -- кнопка меню (доля экрана)
-- всё про кнопку "достать бочку" держим в одной таблице (в Lua лимит 200 локальных переменных)
local BX = { SX = 0.92, SY = 0.20, tok = nil, seq = 0, dirty = false, ann = false,
             tpl = {}, inv = { items = {}, stamp = 0 } }

pcall(function() if createDirectory then createDirectory(getWorkingDirectory() .. '/config') end end)

local DEFAULT_VEHICLES = {
    { 'Пикап', 30 },
    { 'Dodge RAM', 30 },
    { 'MB X-Class', 30 },
    { 'Toyota Tundra', 30 },
    { 'Газель Next нефтевоз', 45 },
    { 'Ford Raptor', 45 },
    { 'MB 6x6', 45 },
    { 'Hennessey Velociraptor 6x6', 45 },
    { 'Ford Bronco 6x6', 60 },
    { 'Jeep Gladiator 6x6', 60 },
    { 'Дирижабль Магната Tier 1', 60 },
    { 'Iveco Trakker нефтевоз', 75 },
    { 'Cargobob нефтевоз', 75 },
    { 'Peterbilt 359', 105 },
    { 'Дирижабль Магната Tier 2', 113 },
    { 'Дирижабль Магната Tier 3', 173 },
    { 'Остальной транспорт', 10 },
}

local EMO = { stop = '\226\155\148', ok = '\226\156\133', barrel = '\240\159\155\162' }

local cfg = inicfg.load({
    main = { x = -1, y = -1, last = 0, sold = 0, earned = 0, az = 0, noanim = 1,
             chat = 1, hud = 1, enabled = 1, limit = 50, window = 420, vver = 0,
             fontscale = DEF_FONT, ovscale = DEF_OV, mbtn = 1, menusize = 2,
             btnx = BTN_X, btny = BTN_Y, sbtn = 1, sbtnx = BX.SX, sbtny = BX.SY },
    tg = { enabled = 0, token = '', chatId = '', onLimit = 1, onEnd = 1, onTrunk = 1 },
    vehicles = {},
}, CFG_FILE)
cfg.stats, cfg.plans = nil, nil       -- старые данные про владельцев больше не нужны
cfg.main.winStart = nil
cfg.main.shout, cfg.main.trunkOn, cfg.main.trunk, cfg.main.curVeh = nil, nil, nil, nil   -- устарело

LIMIT  = tonumber(cfg.main.limit)  or 50
WINDOW = tonumber(cfg.main.window) or 420
if LIMIT < 1 then LIMIT = 50 end
if WINDOW < 30 then WINDOW = 420 end

-- ===================== СОСТОЯНИЕ =====================
local loadClock  = os.clock()
local lastSale   = -100
local flashClock = -10
local lastSaleAt = tonumber(cfg.main.last) or 0     -- os.time() последней проданной бочки
local sold       = tonumber(cfg.main.sold) or 0
local earned     = tonumber(cfg.main.earned) or 0
local azTotal    = tonumber(cfg.main.az) or 0
local noAnim     = tonumber(cfg.main.noanim) ~= 0
local chatOn     = tonumber(cfg.main.chat) ~= 0
local show       = imgui.new.bool(tonumber(cfg.main.hud) ~= 0)
local fontS      = clampN(cfg.main.fontscale, FONT_MIN, FONT_MAX)
local ovS        = clampN(cfg.main.ovscale, OV_MIN, OV_MAX)
local mbtnOn     = tonumber(cfg.main.mbtn) ~= 0
BX.on = tonumber(cfg.main.sbtn) ~= 0
local menuMode   = math.floor(clampN(cfg.main.menusize, 1, 3))
local pos        = nil
local fontSmall, fontMid, fontBig
local salePending = {}
local sess       = { n = 0, money = 0 }
local dirty, lastChange = false, 0

local curVeh   = ''      -- машина, чей багажник открывали последним (UTF-8)

local wasLocked = (sold >= LIMIT and lastSaleAt ~= 0 and (lastSaleAt + WINDOW - os.time()) > 0)

local vehicles = {}
do
    if tonumber(cfg.main.vver) == VEH_VERSION then
        for i = 1, 200 do
            local s = cfg.vehicles and cfg.vehicles['v' .. i]
            if s then
                local name, n = tostring(s):match('^(.-)|(%d+)$')
                if name and name ~= '' then vehicles[#vehicles + 1] = { name = name, n = tonumber(n) } end
            end
        end
    else
        for _, d in ipairs(DEFAULT_VEHICLES) do vehicles[#vehicles + 1] = { name = d[1], n = d[2] } end
    end
end

local M   -- таблица меню, заполняется ниже

local PFX = '{FF0000}|{FFFF00} BarrelSell '
local CHAT_MAX = 140
local function say(text)
    text = toChat(PFX .. text)
    local line, color = '', '{FFFFFF}'
    for word in text:gmatch('%S+') do
        local try = (line == '') and word or (line .. ' ' .. word)
        if #try > CHAT_MAX and line ~= '' then
            sampAddChatMessage(line, -1)
            try = color .. word
        end
        line = try
        color = word:match('.*({%x%x%x%x%x%x})') or color
    end
    if line ~= '' then sampAddChatMessage(line, -1) end
end
local function info(text) if chatOn then say(text) end end

local function touch()
    dirty = true
    lastChange = os.clock()
end

-- ===================== УТИЛИТЫ =====================
local function stripColors(s) return (s:gsub('{%x%x%x%x%x%x}', '')) end

local function trim(str)
    return (tostring(str or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function urlEnc(str)
    return (str:gsub('[^%w%-_%.~]', function(c) return string.format('%%%02X', c:byte()) end))
end

-- русский текст может прийти и в UTF-8 (CEF), и в CP1251 (чат): ищем во всех видах
local vcache = {}
local function variants(w)
    local v = vcache[w]
    if not v then
        v = { w, u8(w), toChat(w) }
        vcache[w] = v
    end
    return v
end

local function has(s, w)
    for _, n in ipairs(variants(w)) do
        if s:find(n, 1, true) then return true end
    end
    return false
end

local function findAfter(s, w)
    for _, n in ipairs(variants(w)) do
        local _, e = s:find(n, 1, true)
        if e then return s:sub(e + 1) end
    end
end

local function fmtMoney(n)
    local s = tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1 '):reverse()
    return (s:gsub('^%s+', ''))
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format('%d:%02d', math.floor(sec / 60), sec % 60)
end

local function sanitize(s)
    s = tostring(s or ''):gsub('[|~=%c]', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return cutStr(s, 40)
end

-- ===================== TELEGRAM =====================
-- На ПК запросы идут через effil, на телефоне effil нет - берём copas (не блокирует игру),
-- а если и его нет - обычный ssl.https (на время запроса игра может на миг притормозить).
local effil_ok, effil = pcall(require, 'effil')
local copas_ok, copas = pcall(require, 'copas')
local chttp_ok, chttp = false, nil
if copas_ok then chttp_ok, chttp = pcall(require, 'copas.http') end
local https_ok, https = pcall(require, 'ssl.https')
local tgBackend = (effil_ok and 'effil')
               or ((copas_ok and chttp_ok and chttp) and 'copas')
               or ((https_ok and https) and 'https')
               or nil
if tgBackend == 'copas' then pcall(function() chttp.TIMEOUT = 15 end) end

local tgEnabled  = imgui.new.bool(tonumber(cfg.tg.enabled) ~= 0)
local tgOnLimit  = imgui.new.bool(tonumber(cfg.tg.onLimit) ~= 0)
local tgOnEnd    = imgui.new.bool(tonumber(cfg.tg.onEnd) ~= 0)
local tgOnTrunk  = imgui.new.bool(tonumber(cfg.tg.onTrunk) ~= 0)
local tgTokenBuf = imgui.new.char[128](tostring(cfg.tg.token or ''))
local tgChatBuf  = imgui.new.char[32](tostring(cfg.tg.chatId or ''))

local tgQueue = {}
local tgStatus, tgStatusKind = '', 'info'     -- kind: info | ok | err

-- GET из lua_thread: возвращает true, тело или false, причина
local function tgRequest(url)
    if tgBackend == 'effil' then
        local th = effil.thread(function(u)
            local sslh = require 'ssl.https'
            local ok, res, code = pcall(sslh.request, u)
            return { ok, res or '', tostring(code or '') }
        end)(url)
        local r  = th:get(0)
        local t0 = os.clock()
        while not r and os.clock() - t0 < 20 do
            wait(0)
            r = th:get(0)
        end
        if not r then
            pcall(function() th:cancel(0) end)
            return false, 'таймаут'
        end
        local ok, res, code = r[1], r[2], r[3]
        pcall(function() th:cancel(0) end)
        if not ok then return false, tostring(res) end
        if type(res) ~= 'string' or res == '' then return false, 'нет ответа (' .. tostring(code) .. ')' end
        return true, res
    elseif tgBackend == 'copas' then
        local done, ok, res, code = false, false, nil, nil
        copas.addthread(function()
            ok, res, code = pcall(chttp.request, url)
            done = true
        end)
        local t0 = os.clock()
        while not done and os.clock() - t0 < 20 do
            pcall(copas.step, 0)
            wait(0)
        end
        if not done then return false, 'таймаут' end
        if not ok then return false, tostring(res) end
        if type(res) ~= 'string' or res == '' then return false, 'нет ответа (' .. tostring(code) .. ')' end
        return true, res
    elseif tgBackend == 'https' then
        local ok, res, code = pcall(https.request, url)
        if not ok then return false, tostring(res) end
        if type(res) ~= 'string' or res == '' then return false, 'нет ответа (' .. tostring(code) .. ')' end
        return true, res
    end
    return false, 'нет сетевой библиотеки'
end

local function tgDescribe(res)
    if res:find('"ok":true', 1, true) then return true, 'Сообщение отправлено' end
    local code = tonumber(res:match('"error_code":(%d+)'))
    local desc = res:match('"description":"(.-)"') or '?'
    if code == 401 or code == 404 then return false, 'Неверный токен бота' end
    if code == 400 or code == 403 then
        return false, 'Бот не может написать вам: проверьте ID и нажмите Start у бота (' .. desc .. ')'
    end
    return false, 'Ошибка Telegram: ' .. desc
end

local function tgReady()
    return tgBackend ~= nil and trim(cfg.tg.token) ~= '' and trim(cfg.tg.chatId) ~= ''
end

-- force = true: отправить даже если уведомления выключены (кнопка теста)
local function tgNotify(emoji, text, force)
    if not tgReady() then return false end
    if not force and not tgEnabled[0] then return false end
    if #tgQueue >= 10 then table.remove(tgQueue, 1) end
    tgQueue[#tgQueue + 1] = emoji .. ' ' .. u8(text)
    return true
end

local function tgWorker()
    while true do
        if #tgQueue > 0 then
            local text = table.remove(tgQueue, 1)
            local url = string.format('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s',
                trim(cfg.tg.token), urlEnc(trim(cfg.tg.chatId)), urlEnc(text))
            local ok, res = tgRequest(url)
            if ok then
                local good, msg = tgDescribe(res)
                tgStatus, tgStatusKind = msg, good and 'ok' or 'err'
            else
                tgStatus, tgStatusKind = 'Нет связи: ' .. tostring(res), 'err'
            end
            wait(1200)
        else
            wait(200)
        end
    end
end

local function tgApply()
    cfg.tg.token  = trim(ffi.string(tgTokenBuf))
    cfg.tg.chatId = trim(ffi.string(tgChatBuf))
    cfg.tg.enabled = tgEnabled[0] and 1 or 0
    touch()
end

-- ===================== ЛОГИ ПРОДАЖ =====================
local logs = {}
local agg  = { all = { n = 0, money = 0, liters = 0 }, days = {} }

local function logAdd(t, liters, price, vehUtf8, noFile)
    logs[#logs + 1] = { t = t, l = liters, p = price, v = vehUtf8 or '' }
    if #logs > LOG_KEEP then table.remove(logs, 1) end

    local d = os.date('%Y-%m-%d', t)
    local day = agg.days[d]
    if not day then
        day = { n = 0, money = 0, liters = 0 }
        agg.days[d] = day
    end
    day.n, day.money, day.liters = day.n + 1, day.money + price, day.liters + liters
    agg.all.n      = agg.all.n + 1
    agg.all.money  = agg.all.money + price
    agg.all.liters = agg.all.liters + liters

    if not noFile then
        local ok, f = pcall(io.open, LOG_FILE, 'a')
        if ok and f then
            f:write(string.format('%d|%d|%d|%s\n', math.floor(t), math.floor(liters), math.floor(price), vehUtf8 or ''))
            f:close()
        end
    end
end

local function logLoad()
    local ok, f = pcall(io.open, LOG_FILE, 'r')
    if not ok or not f then return end
    for line in f:lines() do
        local t, l, p, v = line:match('^(%d+)|(%d+)|(%d+)|(.*)$')
        if t then logAdd(tonumber(t), tonumber(l), tonumber(p), (v:gsub('\r', '')), true) end
    end
    f:close()
end

local function logClear()
    local ok, f = pcall(io.open, LOG_FILE, 'w')
    if ok and f then f:close() end
    logs = {}
    agg  = { all = { n = 0, money = 0, liters = 0 }, days = {} }
    sess = { n = 0, money = 0 }
end

pcall(logLoad)

-- ===================== БАГАЖНИКИ =====================
-- Для каждой машины помним, какие бочки лежат в багажнике и когда их туда положили.
-- Нефть в бочке теряет 1 л каждые 8 часов (по реальному времени, в сети или нет).
-- Названия машин хранятся в UTF-8 (в памяти и в файле config/BarrelSell.trunks).
local trunks      = {}      -- [название] = { cap, put, took, items = { [слот] = { t, l } } }
local openTrunk   = ''      -- чей багажник открыт сейчас (из диалога "Багажник ...")
local pendingDlg  = nil     -- { id, name } показанный диалог выбора
local trunkAlerts = {}      -- машины, из которых достали последнюю бочку
local trunkDirty, trunkChange = false, 0
local UNKNOWN_VEH = u8('Неизвестная машина')

local function trunkTouch()
    trunkDirty, trunkChange = true, os.clock()
end

local function barrelLiters(b)
    return math.max(0, (b.l or BARREL_LITERS) - math.floor((os.time() - (b.t or os.time())) / DECAY_SEC))
end

local function getTrunk(name, create)
    local tr = trunks[name]
    if not tr and create then
        tr = { cap = nil, put = 0, took = 0, items = {} }
        trunks[name] = tr
    end
    return tr
end

local function trunkStats(tr)
    local n, l = 0, 0
    for _, b in pairs(tr.items) do n, l = n + 1, l + barrelLiters(b) end
    return n, l
end

local function trunkTotals()
    local n, l, v = 0, 0, 0
    for _, tr in pairs(trunks) do
        local c, lit = trunkStats(tr)
        if c > 0 then n, l, v = n + c, l + lit, v + 1 end
    end
    return n, l, v
end

local function saveTrunks()
    trunkDirty = false
    local ok, f = pcall(io.open, TRUNK_FILE, 'w')
    if not ok or not f then return end
    f:write('C|', curVeh, '\n')
    for name, tr in pairs(trunks) do
        f:write(string.format('V|%s|%d|%d|%d\n', name, tr.cap or 0, tr.put or 0, tr.took or 0))
        for slot, b in pairs(tr.items) do
            f:write(string.format('B|%s|%d|%d|%d\n', name, slot, b.t, b.l))
        end
    end
    f:close()
end

local function loadTrunks()
    local ok, f = pcall(io.open, TRUNK_FILE, 'r')
    if not ok or not f then return end
    for raw in f:lines() do
        local line = raw:gsub('\r', '')
        local c = line:match('^C|(.*)$')
        if c then
            curVeh = c
        else
            local name, cap, put, took = line:match('^V|(.-)|(%d+)|(%d+)|(%d+)$')
            if name then
                local tr = getTrunk(name, true)
                local capN = tonumber(cap) or 0
                tr.cap  = capN > 0 and capN or nil
                tr.put  = tonumber(put) or 0
                tr.took = tonumber(took) or 0
            else
                local bn, slot, t, l = line:match('^B|(.-)|(%d+)|(%d+)|(%d+)$')
                if bn then
                    getTrunk(bn, true).items[tonumber(slot)] = { t = tonumber(t), l = tonumber(l) }
                end
            end
        end
    end
    f:close()
end

pcall(loadTrunks)

-- вместимость: что сказал сервер, иначе из списка машин, иначе "Остальной транспорт"
local function trunkCap(name, tr)
    if tr and tr.cap then return tr.cap end
    local ln, other = name:lower(), nil
    local rest = u8('Остальной транспорт')
    for _, v in ipairs(vehicles) do
        local vn = u8(v.name)
        if vn == rest then
            other = v.n
        else
            local lv = vn:lower()
            if lv == ln or ln:find(lv, 1, true) then return v.n end
        end
    end
    return other
end

local function trunkClear(name)
    trunks[name] = nil
    trunkTouch()
end

-- диалог "Багажник Mercedes-Benz Gl63": [Открыть багажник / Заглянуть в багажник]
function sampev.onShowDialog(id, style, title, b1, b2, text)
    if not M.on or type(title) ~= 'string' then return end
    local cap = stripColors(title)
    if not has(cap, 'Багажник') then return end
    if not has(stripColors(tostring(text or '')), 'Заглянуть') then return end
    local name = sanitize(findAfter(cap, 'Багажник') or '')
    if name == '' then return end
    pendingDlg = { id = id, name = U8lib(name) }       -- из игры приходит CP1251
end

function sampev.onSendDialogResponse(dialogId, button, listitem, input)
    if not pendingDlg or dialogId ~= pendingDlg.id then return end
    local d = pendingDlg
    pendingDlg = nil
    if not M.on or button ~= 1 then return end
    openTrunk, curVeh = d.name, d.name
    getTrunk(d.name, true)
    trunkTouch()
end

local function barrelPercent(obj)
    return tonumber(obj:match('"text":"[^"]-(%d+)%%'))
end

local function onTrunkItems(action, items)
    local name = (openTrunk ~= '' and openTrunk) or (curVeh ~= '' and curVeh) or UNKNOWN_VEH
    local tr = getTrunk(name, true)

    if action == 0 then
        -- полный снимок багажника при открытии: подстраиваемся под сервер
        local fresh = {}
        for obj in items:gmatch('%b{}') do
            local slot = tonumber(obj:match('"slot":(%d+)'))
            local item = tonumber(obj:match('"item":(%d+)'))
            if slot and item and BARREL_IDS[item] then
                local pct = barrelPercent(obj) or BARREL_LITERS
                local cur = tr.items[slot]
                if cur and barrelLiters(cur) == pct then
                    fresh[slot] = cur
                else
                    fresh[slot] = { t = os.time(), l = pct }
                end
            end
        end
        tr.items = fresh
        trunkTouch()
        return
    end
    if action ~= 2 then return end

    -- обновление слотов: бочка появилась (положили) или слот опустел (достали)
    local changed = false
    for obj in items:gmatch('%b{}') do
        local slot = tonumber(obj:match('"slot":(%d+)'))
        local item = tonumber(obj:match('"item":(%d+)'))
        if slot then
            local cur = tr.items[slot]
            if item and BARREL_IDS[item] then
                local pct = barrelPercent(obj) or BARREL_LITERS
                if not cur then
                    tr.items[slot] = { t = os.time(), l = pct }
                    tr.put = (tr.put or 0) + 1
                elseif barrelLiters(cur) ~= pct then
                    tr.items[slot] = { t = os.time(), l = pct }
                end
                changed = true
            elseif cur then
                tr.items[slot] = nil
                tr.took = (tr.took or 0) + 1
                changed = true
                if next(tr.items) == nil then trunkAlerts[#trunkAlerts + 1] = name end
            end
        end
    end
    if changed then trunkTouch() end
end

local function handleInventoryEvent(str)
    local body = str:match('`(.*)`') or str
    for act, ty, items in body:gmatch('"action":(%d+),"data":{"type":(%d+),"items":(%b[])') do
        if tonumber(ty) == 13 then onTrunkItems(tonumber(act), items) end
    end
end

-- "В багажнике можно хранить не более 10 нефтяных бочек." - запоминаем лимит этой машины
local function learnTrunkCap(str)
    if not has(str, 'нефтян') then return end
    local rest = findAfter(str, 'можно хранить не более')
    local cap = rest and tonumber(rest:match('^%s*(%d+)'))
    if cap and cap > 0 and openTrunk ~= '' then
        local tr = getTrunk(openTrunk, true)
        if tr.cap ~= cap then
            tr.cap = cap
            trunkTouch()
        end
    end
end

-- ===================== СОХРАНЕНИЕ =====================
local function saveConfig()
    if pos then
        cfg.main.x = math.floor(pos.x)
        cfg.main.y = math.floor(pos.y)
    end
    cfg.main.last    = lastSaleAt
    cfg.main.sold    = sold
    cfg.main.earned  = earned
    cfg.main.az      = azTotal
    cfg.main.noanim  = noAnim and 1 or 0
    cfg.main.chat    = chatOn and 1 or 0
    cfg.main.hud     = show[0] and 1 or 0
    cfg.main.limit   = LIMIT
    cfg.main.window  = WINDOW
    cfg.main.vver    = VEH_VERSION
    cfg.main.fontscale = string.format('%.2f', fontS)
    cfg.main.ovscale   = string.format('%.2f', ovS)
    cfg.main.mbtn      = mbtnOn and 1 or 0
    cfg.main.sbtn      = BX.on and 1 or 0
    cfg.main.menusize  = menuMode
    if M and M.ov then
        cfg.main.btnx  = string.format('%.4f', M.ov.btn.x)
        cfg.main.btny  = string.format('%.4f', M.ov.btn.y)
        cfg.main.sbtnx = string.format('%.4f', M.ov.sell.x)
        cfg.main.sbtny = string.format('%.4f', M.ov.sell.y)
    end
    cfg.tg.enabled   = tgEnabled[0] and 1 or 0
    cfg.tg.onLimit   = tgOnLimit[0] and 1 or 0
    cfg.tg.onEnd     = tgOnEnd[0] and 1 or 0
    cfg.tg.onTrunk   = tgOnTrunk[0] and 1 or 0
    cfg.tg.token     = trim(ffi.string(tgTokenBuf))
    cfg.tg.chatId    = trim(ffi.string(tgChatBuf))
    cfg.vehicles = {}
    for i, v in ipairs(vehicles) do cfg.vehicles['v' .. i] = v.name .. '|' .. v.n end
    inicfg.save(cfg, CFG_FILE)
    dirty = false
end

-- ===================== ОКНО ЛИМИТА / КД =====================
-- КД считается от последней проданной бочки: lastSaleAt + WINDOW.
-- Если сервер написал "Осталось ещё 6:54" - подстраиваемся под него.
local function windowLeft()
    if lastSaleAt == 0 then return 0 end
    return math.max(0, lastSaleAt + WINDOW - os.time())
end

local function resetWindow()
    lastSaleAt = 0
    sold       = 0
    earned     = 0
    wasLocked  = false
end

local function saleTail(str)
    if not str then return nil end
    return findAfter(str, 'продали бочку')
end

local function registerSale(price, liters)
    if os.clock() - loadClock < STARTUP_IGNORE then return false end
    if os.clock() - lastSale < DUP_WINDOW then return false end
    lastSale   = os.clock()
    flashClock = os.clock()

    if lastSaleAt ~= 0 and windowLeft() <= 0 then resetWindow() end
    lastSaleAt = os.time()
    sold   = sold + 1
    earned = earned + (price or 0)
    salePending[#salePending + 1] = { t = os.time(), price = price or 0, liters = liters or 0 }
    return true
end

-- "[Ошибка] Вы можете сдать всего 50 бочек раз в 7 минут! Осталось ещё 6:54"
local function parseLimitMsg(str)
    if type(str) ~= 'string' then return false end
    str = stripColors(str)
    if not (has(str, 'бочек') and has(str, 'всего') and has(str, 'сталось')) then return false end

    local rest = findAfter(str, 'сталось')
    if not rest then return false end
    local secs
    local h, m, s = rest:match('(%d+):(%d+):(%d+)')
    if h then
        secs = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    else
        m, s = rest:match('(%d+):(%d+)')
        if not m then return false end
        secs = tonumber(m) * 60 + tonumber(s)
    end

    local lim  = tonumber((findAfter(str, 'всего') or ''):match('%d+'))
    local mins = tonumber((findAfter(str, 'раз в') or ''):match('%d+'))
    return true, secs, lim, mins
end

local function handleLimitMsg(str)
    local ok, secs, lim, mins = parseLimitMsg(str)
    if not ok then return false end
    if lim and lim > 0 then LIMIT = lim end
    if mins and mins > 0 then WINDOW = mins * 60 end
    if secs > WINDOW then WINDOW = secs end
    lastSaleAt = os.time() - (WINDOW - secs)
    if sold < LIMIT then sold = LIMIT end
    touch()
    return true
end

-- ===================== ИНВЕНТАРЬ И КНОПКА "ДОСТАТЬ БОЧКУ" =====================
-- Кнопка: /invent -> сервер присылает инвентарь кусками (type 1) -> берём слот с бочкой (8480/8481)
-- -> шлём пакеты "выбрать слот" и "использовать" (как делает сам клиент) -> ждём уведомление о продаже
-- ("Вы успешно продали бочку...") -> повторяем, пока бочки не кончатся или не упрёмся в лимит.
-- Формат пакетов 220/63 скрипт копирует с настоящих: один раз достань бочку из инвентаря руками,
-- он запомнит (и сохранит в config/BarrelSell.pkt).
-- BX.inv.items[слот] = ID предмета, inv.stamp - когда пришёл последний кусок инвентаря
-- BX.seq - сколько раз пришло уведомление о продаже, BX.tpl.sel / BX.tpl.use - записанные пакеты,
-- BX.tok не nil, пока идёт "достать бочки"
do
local PKT_FILE   = getWorkingDirectory() .. '/config/BarrelSell.pkt'
local inv, tpl   = BX.inv, BX.tpl
local sendingOwn = false

function BX.parse(str)
    local got = false
    for ty, items in str:gmatch('"type"%s*:%s*(%d+)%s*,%s*"items"%s*:%s*(%b[])') do
        if tonumber(ty) == 1 then
            for obj in items:gmatch('%b{}') do
                local slot = tonumber(obj:match('"slot"%s*:%s*(%d+)'))
                if slot then
                    inv.items[slot] = tonumber(obj:match('"item"%s*:%s*(%d+)'))
                    got = true
                    if inv.max and slot >= inv.max - 1 then inv.done = os.clock() end
                end
            end
        end
    end
    local mx = tonumber(str:match('"max_slot"%s*:%s*(%d+)'))
    if mx then inv.max = mx end
    if got then inv.stamp = os.clock() end
end

local function nextBarrelSlot()
    local best
    for slot, item in pairs(inv.items) do
        if BARREL_IDS[item] and (not best or slot < best) then best = slot end
    end
    return best
end

local function bytesStr(b) return string.char(unpack(b)) end

-- клиент сам шлёт 220/63 с пустой строкой "" при открытии инвентаря: берём из него заголовок
-- (строка идёт после u16-длины, после строки 1 байт хвоста)
local function findEmpty(b)
    local n = #b
    for i = 3, n - 2 do
        if b[i] == 34 and b[i + 1] == 34 and i + 1 == n - 1 and b[i - 2] + b[i - 1] * 256 == 2 then
            return i, i + 1
        end
    end
end

local function setTpl(k, b, p, r, c)
    local js, je
    if k == 'hdr' then js, je = findEmpty(b) else js, je = bytesStr(b):find('%b{}') end
    if not js then return false end
    local old = tpl[k]
    local same = old ~= nil and #old.b == #b
    if same then
        for i = 1, #b do
            if old.b[i] ~= b[i] then same = false break end
        end
    end
    tpl[k] = { b = b, js = js, je = je, p = p, r = r, c = c }
    return true, not same
end

function BX.save()
    BX.dirty = false
    local ok, f = pcall(io.open, PKT_FILE, 'w')
    if not ok or not f then return end
    for _, k in ipairs({ 'sel', 'use', 'hdr' }) do
        local t = tpl[k]
        if t then
            local hex = {}
            for i, v in ipairs(t.b) do hex[i] = string.format('%02x', v) end
            f:write(string.format('%s|%s|%s|%s|%s\n', k, tostring(t.p or ''), tostring(t.r or ''),
                tostring(t.c or ''), table.concat(hex)))
        end
    end
    f:close()
end

local function loadPkt()
    local ok, f = pcall(io.open, PKT_FILE, 'r')
    if not ok or not f then return end
    for line in f:lines() do
        local k, p, r, c, hex = line:match('^(%a+)|([^|]*)|([^|]*)|([^|]*)|(%x+)')
        if k == 'sel' or k == 'use' or k == 'hdr' then
            local b = {}
            for h in hex:gmatch('%x%x') do b[#b + 1] = tonumber(h, 16) end
            setTpl(k, b, tonumber(p), tonumber(r), tonumber(c))
        end
    end
    f:close()
    BX.ann = ((tpl.sel and tpl.use) or tpl.hdr) and true or false
end
pcall(loadPkt)

-- копируем настоящий исходящий пакет 220/63 с JSON {"slot":N,"type":1} (выбор) или
-- {"action":1,"id":0,"slot":N,"type":1} (использование бочки)
local function captureSend(id, bs, prio, rel, ch)
    raknetBitStreamResetReadPointer(bs)
    local n = raknetBitStreamGetNumberOfBytesUsed(bs)
    if not n or n < 8 or n > 200 then return end
    local b = {}
    for i = 1, n do b[i] = raknetBitStreamReadInt8(bs) % 256 end
    raknetBitStreamResetReadPointer(bs)
    if b[1] ~= id then table.insert(b, 1, id) end
    if b[2] ~= 63 then return end

    local json = bytesStr(b):match('%b{}')
    if not json then
        if findEmpty(b) then
            local ok, changed = setTpl('hdr', b, prio, rel, ch)
            if ok and changed then BX.dirty = true end
        end
        return
    end
    local slot = tonumber(json:match('"slot"%s*:%s*(%d+)'))
    if not slot or tonumber(json:match('"type"%s*:%s*(%d+)')) ~= 1 then return end

    local act = tonumber(json:match('"action"%s*:%s*(%d+)'))
    local k
    if act == nil then
        k = 'sel'
    elseif act == 1 and tonumber(json:match('"id"%s*:%s*(%d+)')) == 0 then
        k = 'use'
        local item = inv.items[slot]
        if item and not BARREL_IDS[item] then return end      -- использовали не бочку - не берём
    else
        return
    end
    local ok, changed = setTpl(k, b, prio, rel, ch)
    if ok and changed then BX.dirty = true end
end

function onSendPacket(id, bs, prio, rel, ch)
    if id ~= 220 or sendingOwn then return end
    pcall(captureSend, id, bs, prio, rel, ch)
end

-- собираем пакет из записанного: меняем только номер слота (и длину, если она есть перед строкой)
function BX.ready() return (tpl.sel and tpl.use) or tpl.hdr end

local FMT = { sel = '{"slot":%d,"type":1}', use = '{"action":1,"id":0,"slot":%d,"type":1}' }

local function buildPkt(t, slot)
    local b, js, je = t.b, t.js, t.je
    local json = bytesStr(b):sub(js, je)
    local nj, cnt
    if t.fmt then
        nj, cnt = string.format(t.fmt, slot), 1
    else
        nj, cnt = json:gsub('("slot"%s*:%s*)%d+', function(a) return a .. slot end, 1)
    end
    if cnt == 0 then return nil, 'в записанном пакете нет slot' end
    local L0, L1 = #json, #nj

    local out = {}
    for i = 1, js - 1 do out[i] = b[i] end
    if L1 ~= L0 then
        local patched = false
        for _, w in ipairs({ 4, 2, 1 }) do
            if not patched and js - w >= 1 then
                local v = 0
                for k = w, 1, -1 do v = v * 256 + b[js - w + k - 1] end
                if v == L0 then
                    local x = L1
                    for k = 1, w do
                        out[js - w + k - 1] = x % 256
                        x = math.floor(x / 256)
                    end
                    patched = true
                end
            end
        end
        if not patched then
            if L1 > L0 then return nil, 'длина пакета не совпала - достань бочку вручную ещё раз' end
            nj = nj:sub(1, -2) .. string.rep(' ', L0 - L1) .. '}'
        end
    end
    for i = 1, #nj do out[#out + 1] = nj:byte(i) end
    for i = je + 1, #b do out[#out + 1] = b[i] end
    return out
end

local function sendTpl(k, slot)
    local t = tpl[k]
    if not t and tpl.hdr then
        local h = tpl.hdr
        t = { b = h.b, js = h.js, je = h.je, p = h.p, r = h.r, c = h.c, fmt = FMT[k] }
    end
    if not t then return false, 'ещё не получен пакет клиента' end
    local out, err = buildPkt(t, slot)
    if not out then return false, err end
    local bs = raknetNewBitStream()
    for i = 1, #out do raknetBitStreamWriteInt8(bs, out[i]) end
    sendingOwn = true
    local ok, e = pcall(raknetSendBitStreamEx, bs, t.p or 1, t.r or 7, t.c or 1)
    sendingOwn = false
    raknetDeleteBitStream(bs)
    if not ok then return false, tostring(e) end
    return true
end

-- одна бочка: 'ok' - продана, 'none' - бочек нет, 'limit' - упёрлись в лимит, 'stop' - остановили, 'fail' + причина
local function sellOnce(tok)
    local function alive() return BX.tok == tok and M.on end

    local openAt = os.clock()
    sampSendChat('/invent')
    local t0 = os.clock()
    while alive() do
        wait(50)
        local now = os.clock()
        if inv.stamp > openAt and ((inv.done or 0) > openAt or now - inv.stamp > 0.35) then break end    -- инвентарь пришёл целиком
        if now - t0 > 4 then break end
    end
    if not alive() then return 'stop' end
    if not (inv.stamp > openAt) then return 'fail', 'инвентарь не открылся' end

    local slot = nextBarrelSlot()
    if not slot then return 'none' end

    -- как клиент: "выбрать слот" -> "использовать". Бочка берётся в руки и продаётся - ждём уведомление.
    -- Если пришло "бочка уже в руках" - просто ждём, пока предыдущая продастся.
    local seq = BX.seq
    local ok, err = sendTpl('sel', slot)
    if not ok then return 'fail', err end
    wait(150)
    if not alive() then return 'stop' end
    ok, err = sendTpl('use', slot)
    if not ok then return 'fail', err end

    local t = os.clock()
    while alive() and BX.seq == seq do
        wait(30)
        if os.clock() - t > 20 then break end
        if sold >= LIMIT and windowLeft() > 0 then break end
    end
    if not alive() then return 'stop' end
    if BX.seq ~= seq then
        inv.items[slot] = nil
        return 'ok'
    end
    if sold >= LIMIT and windowLeft() > 0 then return 'limit' end
    return 'fail', 'нет уведомления о продаже (стоишь не там, где можно сдать?)'
end

local function sellRun(tok)
    local used, fails = 0, 0
    say('{FFFFFF}Достаю бочки. {c0c0c0}Нажми кнопку ещё раз - стоп')
    while BX.tok == tok and M.on do
        if sold >= LIMIT and windowLeft() > 0 then break end
        local r, err = sellOnce(tok)
        if r == 'ok' then
            used, fails = used + 1, 0
            wait(900)
        elseif r == 'none' then
            if used > 0 then
                say('{FFFFFF}Бочки {00FF00}закончились{FFFFFF}, продано за этот заход: {FFD666}' .. used)
            else
                say('{FFFFFF}В инвентаре {FF0000}нет бочек')
            end
            break
        elseif r == 'limit' or r == 'stop' then
            break
        else
            fails = fails + 1
            if fails >= 2 then
                say('{FF0000}Не получилось: {FFFFFF}' .. tostring(err))
                break
            end
            wait(1000)
        end
    end
    if BX.tok == tok then BX.tok = nil end
end

function BX.toggle()
    if BX.tok then
        BX.tok = nil
        say('{FFFFFF}Достать бочки: {FF0000}стоп')
        return
    end
    if not M.on then
        say('{FF0000}Скрипт выключен{FFFFFF} - включи его в меню')
        return
    end
    local tok = {}
    BX.tok = tok
    lua_thread.create(function() sellRun(tok) end)
end
end   -- конец блока "достать бочку"

-- ===================== ПАКЕТЫ И ЧАТ =====================
local function readCefString(bs)
    raknetBitStreamResetReadPointer(bs)
    raknetBitStreamReadInt8(bs)
    local pType = raknetBitStreamReadInt8(bs)
    local str
    if pType == 17 then
        raknetBitStreamIgnoreBits(bs, 32)
        local length    = raknetBitStreamReadInt16(bs)
        local isEncoded = raknetBitStreamReadInt8(bs)
        str = (isEncoded ~= 0)
            and raknetBitStreamDecodeString(bs, length + isEncoded)
            or  raknetBitStreamReadString(bs, length)
    elseif pType == 84 then
        raknetBitStreamReadInt8(bs)
        raknetBitStreamReadInt8(bs)
        local length    = raknetBitStreamReadInt16(bs)
        local isEncoded = raknetBitStreamReadInt8(bs)
        str = (isEncoded ~= 0)
            and raknetBitStreamDecodeString(bs, length + isEncoded)
            or  raknetBitStreamReadString(bs, length)
    end
    raknetBitStreamResetReadPointer(bs)
    return str
end

function onReceivePacket(id, bs)
    if id ~= 220 or not M.on then return end
    local ok, str = pcall(readCefString, bs)
    raknetBitStreamResetReadPointer(bs)
    if not ok or type(str) ~= 'string' then return end

    if str:find('"items"', 1, true) and str:find('"slot"', 1, true) then pcall(BX.parse, str) end

    if str:find('event.inventory.playerInventory', 1, true) then
        pcall(handleInventoryEvent, str)
        return
    end

    if handleLimitMsg(str) then return end

    if str:find('cef.addNotification', 1, true) then pcall(learnTrunkCap, str) end

    if has(str, 'бочка в руках') then BX.hands = (BX.hands or 0) + 1 end

    local tail = saleTail(str)
    if tail then
        local liters, price = tail:match('(%d+)[^%d]+(%d+)')
        BX.seq = BX.seq + 1
        registerSale(tonumber(price), tonumber(liters))
    end
end

local AZ_PREFIX = '[Оптовая декларация]'

function sampev.onServerMessage(color, text)
    if not M.on or not text then return end
    if handleLimitMsg(text) then return end

    local clean = (text:gsub('{%x%x%x%x%x%x}', '')):gsub('^%s+', '')
    local rest
    for _, pfx in ipairs(variants(AZ_PREFIX)) do
        if clean:sub(1, #pfx) == pfx then
            rest = clean:sub(#pfx + 1)
            break
        end
    end
    if not rest then return end

    local n = rest:match('^[^%d]*(%d+)%s*AZ Coins')
    if not n then return end
    if not has(rest, 'декларац') then return end

    azTotal = azTotal + tonumber(n)
    touch()
end

local function animBlockActive()
    if not M.on or not noAnim then return false end
    return (os.clock() - lastSale) < ANIM_BLOCK_TIME
end

local function isMe(playerId)
    local ok, found, myId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    return ok and found and playerId == myId
end

function sampev.onApplyPlayerAnimation(playerId, animLib, animName, frameDelta, loop, lockX, lockY, freeze, time)
    if animBlockActive() and isMe(playerId) then
        return false
    end
end

function sampev.onTogglePlayerControllable(controllable)
    if animBlockActive() then
        if not controllable then return false end
    end
end

-- ===================== УВЕДОМЛЕНИЯ В TELEGRAM =====================
local function notifyLimit(left)
    if not tgOnLimit[0] then return end
    tgNotify(EMO.stop, string.format('BarrelSell: лимит %d бочек достигнут\nКД %s, снова можно в %s\nВыручка за окно: %s руб',
        LIMIT, fmtTime(left), os.date('%H:%M', os.time() + left), fmtMoney(earned)))
end

local function notifyEnd()
    if not tgOnEnd[0] then return end
    tgNotify(EMO.ok, 'BarrelSell: КД закончился, можно сдавать бочки!')
end

local function notifyTrunk(name)
    if not tgOnTrunk[0] then return end
    tgNotify(EMO.barrel, 'BarrelSell: багажник пуст' .. (name and name ~= '' and (' (' .. fromU8(name) .. ')') or '')
        .. '\nПродано за окно: ' .. sold .. ' / ' .. LIMIT)
end

-- ===================== ОБРАБОТКА ПРОДАЖ (основной поток) =====================
local function processSales()
    while #salePending > 0 do
        local s = table.remove(salePending, 1)
        logAdd(s.t, s.liters, s.price, curVeh)
        sess.n, sess.money = sess.n + 1, sess.money + s.price
        info('{FFFFFF}Продана бочка: {FFD666}+' .. fmtMoney(s.price) .. '{FFFFFF} руб  ({c0c0c0}'
            .. sold .. '/' .. LIMIT .. '{FFFFFF})')
        touch()
    end
end

local function processTrunkAlerts()
    while #trunkAlerts > 0 do
        local name = table.remove(trunkAlerts, 1)
        say('{FFFFFF}Багажник {FF0000}пуст {c0c0c0}(' .. fromU8(name) .. ')')
        notifyTrunk(name)
    end
end

-- ===================== РИСОВАНИЕ =====================
local W, H = 340, 148      -- размер окна продажи до масштабирования

local GREEN = { 46, 213, 170 }
local AMBER = { 255, 176, 46 }
local RED   = { 255, 84, 112 }
local BLUE  = { 90, 150, 255 }
local GRAY  = { 150, 156, 178 }
local DIM   = { 110, 116, 138 }
local GOLD  = { 255, 214, 102 }
local WHITE = { 255, 255, 255 }

local function col(r, g, b, a)
    return imgui.GetColorU32Vec4(imgui.ImVec4(r / 255, g / 255, b / 255, a or 1))
end

local function colT(t, a)
    return col(t[1], t[2], t[3], a)
end

local function approach(cur, target, speed, dt)
    local v = cur + (target - cur) * (1 - math.exp(-speed * dt))
    if math.abs(v - target) < 0.004 then return target end
    return v
end

local function ease(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

local function lerp(a, b, t) return a + (b - a) * t end

local tickT = {}
local function tick(key)
    local now  = os.clock()
    local last = tickT[key]
    tickT[key] = now
    if not last or now - last > 0.25 then return 0.016 end
    return math.min(now - last, 0.1)
end

-- обрезка UTF-8 строки по ширине (в пикселях текущего шрифта)
local function fit(text, maxw)
    if tsz(text).x <= maxw then return text end
    local cut = text
    while #cut > 0 and tsz(cut .. '..').x > maxw do
        cut = cut:gsub('[^\128-\191][\128-\191]*$', '')
    end
    return cut .. '..'
end

local faOk = false
local FA = {
    OIL = 0xf613, COINS = 0xf51e, GEAR = 0xf013, USERS = 0xf0c0, TRUCK = 0xf0d1,
    CHART = 0xf080, EYE = 0xf06e, SYNC = 0xf021, MESSAGE = 0xf075, BAN = 0xf05e,
    ARROWS = 0xf0b2, LAYER = 0xf5fd, CART = 0xf07a, POWER = 0xf011,
    LIST = 0xf022, SEND = 0xf1d8,
}
local function fa(cp)
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

M = {
    open     = imgui.new.bool(false),
    tab      = 1,
    edit     = nil,
    inVeh    = imgui.new.char[96](),
    inVehN   = imgui.new.int(10),
    slF      = { font = imgui.new.float(fontS), ov = imgui.new.float(ovS) },
    scaleDirty = false,
    confirmId = nil, confirmT = 0,
    showTok  = false,
    on       = tonumber(cfg.main.enabled) ~= 0,
    ov       = { btn = { x = tonumber(cfg.main.btnx) or BTN_X, y = tonumber(cfg.main.btny) or BTN_Y },
                 sell = { x = tonumber(cfg.main.sbtnx) or BX.SX, y = tonumber(cfg.main.sbtny) or BX.SY } },
    place = false, drag = nil, pick = 'hud', grab = nil, snap = nil,
    rects = {}, nudge = {},
}

M.anim, M.alpha, M.dt = 0, 0, 0.016
M.tabT, M.tabY, M.tabHov, M.closeH = -10, nil, {}, 0
M.tgA, M.tgH = {}, {}
M.btnA = 0
M.sellA = 0

M.tabIcons = { 'CHART', 'EYE', 'TRUCK', 'LIST', 'SEND', 'GEAR' }
M.tIcons = {
    master = 'POWER', hud = 'CHART', anim = 'BAN', chat = 'MESSAGE', mbtn = 'OIL', sbtn = 'OIL',
}

local function arcLine(dl, cx, cy, rx, ry, a0, a1, c, th)
    local V, n = imgui.ImVec2, 10
    local px, py
    for i = 0, n do
        local t = a0 + (a1 - a0) * i / n
        local x, y = cx + rx * math.cos(t), cy + ry * math.sin(t)
        if px then dl:AddLine(V(px, py), V(x, y), c, th) end
        px, py = x, y
    end
end

function M.drawBarrel(dl, cx, cy, s, c, a)
    a = a or 1
    local V = imgui.ImVec2
    local w, h  = s * 0.80, s
    local ry    = s * 0.10
    local yt, yb = cy - h / 2 + ry, cy + h / 2 - ry
    local th    = math.max(1.2, s * 0.07)
    local function hw(t) return w / 2 * (0.84 + 0.16 * math.sin(math.pi * t)) end

    local pts, N = {}, 10
    local hw0 = hw(0)
    for i = 0, 8 do
        local t = math.pi * i / 8
        pts[#pts + 1] = { cx - hw0 * math.cos(t), yt - ry * math.sin(t) }
    end
    for j = 1, N - 1 do
        local t = j / N
        pts[#pts + 1] = { cx + hw(t), yt + (yb - yt) * t }
    end
    for i = 0, 8 do
        local t = math.pi * i / 8
        pts[#pts + 1] = { cx + hw0 * math.cos(t), yb + ry * math.sin(t) }
    end
    for j = N - 1, 1, -1 do
        local t = j / N
        pts[#pts + 1] = { cx - hw(t), yt + (yb - yt) * t }
    end

    local okFill = pcall(function()
        local arr = (imgui.new or ffi.new)('ImVec2[?]', #pts)
        for i, p in ipairs(pts) do arr[i - 1].x, arr[i - 1].y = p[1], p[2] end
        dl:AddConvexPolyFilled(arr, #pts, colT(c, 0.26 * a))
    end)
    if not okFill then
        dl:AddRectFilled(V(cx - w / 2, cy - h / 2), V(cx + w / 2, cy + h / 2), colT(c, 0.26 * a), s * 0.25)
    end

    for _, t in ipairs({ 0.27, 0.73 }) do
        local y = yt + (yb - yt) * t
        local r = hw(t)
        arcLine(dl, cx, y, r, ry * 0.9, 0, math.pi, colT(c, 0.9 * a), th * 1.2)
    end

    local oc = colT(c, 0.95 * a)
    for i = 1, #pts do
        local p1, p2 = pts[i], pts[i % #pts + 1]
        dl:AddLine(V(p1[1], p1[2]), V(p2[1], p2[2]), oc, th)
    end

    arcLine(dl, cx, yt, hw0, ry, math.pi, math.pi * 3, colT(c, 0.7 * a), th * 0.9)
end

function M.icon(dl, name, cx, cy, c, a, font)
    if name == 'OIL' then
        M.drawBarrel(dl, cx, cy, ((font == fontBig) and 30 or 20) * ICON_K, c, a)
        return true
    end
    if not faOk or not FA[name] then return false end
    local s = fa(FA[name])
    imgui.PushFont(font or fontMid)
    local ts = tsz(s)
    dl:AddText(imgui.ImVec2(cx - ts.x / 2, cy - ts.y / 2), colT(c, a or 1), s)
    imgui.PopFont()
    return true
end

function M.v4(t, a)
    return imgui.ImVec4(t[1] / 255, t[2] / 255, t[3] / 255, a or 1)
end

-- в меню весь текст переносится по ширине окна
function M.text(c, s)
    imgui.PushStyleColor(imgui.Col.Text, M.v4(c))
    if M.inMenu then imgui.PushTextWrapPos(0) end
    imgui.TextUnformatted(s)
    if M.inMenu then imgui.PopTextWrapPos() end
    imgui.PopStyleColor()
end

function M.wrap(c, s)
    imgui.PushStyleColor(imgui.Col.Text, M.v4(c))
    imgui.PushTextWrapPos(0)
    imgui.TextUnformatted(s)
    imgui.PopTextWrapPos()
    imgui.PopStyleColor()
end

function M.wrapLines(text, maxw, maxLines)
    local lines, cur = {}, ''
    for word in tostring(text):gmatch('%S+') do
        local try = (cur == '') and word or (cur .. ' ' .. word)
        if cur ~= '' and imgui.CalcTextSize(try).x > maxw then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= '' then lines[#lines + 1] = cur end
    if maxLines and #lines > maxLines then
        for i = #lines, maxLines + 1, -1 do lines[i] = nil end
    end
    return lines
end

-- кнопка: сама растягивается под текст, не срабатывает при прокрутке пальцем
function M.btn(label, w, h, acc)
    acc = acc or BLUE
    local shown = label:match('^(.-)###') or label
    local t0 = imgui.CalcTextSize(shown)
    local padX = Z(14)
    if w and w > 0 and t0.x + padX * 2 > w then w = t0.x + padX * 2 end
    if h and h > 0 and t0.y + Z(12) > h then h = t0.y + Z(12) end
    imgui.PushStyleColor(imgui.Col.Button,        M.v4(acc, 0.16))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, M.v4(acc, 0.30))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  M.v4(acc, 0.45))
    imgui.PushStyleColor(imgui.Col.Text,          M.v4(acc, 1))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(Z(8), Z(3)))
    local r = imgui.Button(label, imgui.ImVec2(w or 0, h or Z(30)))
    imgui.PopStyleVar()
    imgui.PopStyleColor(4)
    if r and M.scrolling then r = false end
    return r
end

function M.confirmBtn(id, label, w, h, acc)
    local armed = (M.confirmId == id) and (os.clock() - M.confirmT < 3)
    local text  = (armed and u8'Точно?' or label) .. '###cf' .. id
    if M.btn(text, w, h, armed and RED or acc) then
        if armed then
            M.confirmId = nil
            return true
        end
        M.confirmId = id
        M.confirmT  = os.clock()
    end
    return false
end

function M.toggle(label, desc, value, icon)
    local V = imgui.ImVec2
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    local pw, ph = Z(44), Z(24)
    local hasIcon = icon and (faOk or icon == 'OIL')
    local tx = hasIcon and Z(58) or Z(16)
    local textMax = w - tx - pw - Z(16) - Z(14)
    if textMax < Z(60) then textMax = Z(60) end
    local tl = M.wrapLines(label, textMax, 2)
    local dlines = desc and M.wrapLines(desc, textMax, 3) or {}
    local lineH = imgui.CalcTextSize('Ag').y
    local h = Z(10) + #tl * lineH + (#dlines > 0 and (Z(3) + #dlines * lineH) or 0) + Z(10)
    if h < Z(44) then h = Z(44) end

    local clicked = imgui.InvisibleButton('##tg' .. label, V(w, h))
    if M.scrolling then clicked = false end
    local hov = imgui.IsItemHovered()
    local dt = M.dt or 0.016
    local a  = approach(M.tgA[label] or (value and 1 or 0), value and 1 or 0, 14, dt)
    local hv = approach(M.tgH[label] or 0, hov and 1 or 0, 16, dt)
    M.tgA[label], M.tgH[label] = a, hv
    local ea = ease(a)
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(p, V(p.x + w, p.y + h), col(255, 255, 255, 0.03 + 0.04 * hv), Z(12))

    if hasIcon then
        local isz = Z(32)
        local ix, iy = p.x + Z(12), p.y + h / 2 - isz / 2
        dl:AddRectFilled(V(ix, iy), V(ix + isz, iy + isz), col(lerp(255, GREEN[1], ea), lerp(255, GREEN[2], ea),
            lerp(255, GREEN[3], ea), lerp(0.06, 0.16, ea)), Z(10))
        M.icon(dl, icon, ix + isz / 2, iy + isz / 2,
            { lerp(150, GREEN[1], ea), lerp(156, GREEN[2], ea), lerp(178, GREEN[3], ea) }, 1, fontMid)
    end
    local yy = p.y + Z(10)
    for _, ln in ipairs(tl) do
        dl:AddText(V(p.x + tx, yy), col(235, 238, 248), ln)
        yy = yy + lineH
    end
    if #dlines > 0 then
        yy = yy + Z(3)
        for _, ln in ipairs(dlines) do
            dl:AddText(V(p.x + tx, yy), colT(DIM), ln)
            yy = yy + lineH
        end
    end

    local px, py = p.x + w - pw - Z(16), p.y + h / 2 - ph / 2
    if a > 0 then
        dl:AddRectFilled(V(px - Z(3), py - Z(3)), V(px + pw + Z(3), py + ph + Z(3)),
            col(GREEN[1], GREEN[2], GREEN[3], 0.16 * ea), ph / 2 + Z(3))
    end
    dl:AddRectFilled(V(px, py), V(px + pw, py + ph),
        col(lerp(48, GREEN[1], ea), lerp(53, GREEN[2], ea), lerp(72, GREEN[3], ea)), ph / 2)
    local kx = lerp(px + ph / 2, px + pw - ph / 2, ea)
    dl:AddCircleFilled(V(kx, py + ph / 2 + 1), ph / 2 - Z(3), col(0, 0, 0, 0.25), 18)
    dl:AddCircleFilled(V(kx, py + ph / 2), ph / 2 - Z(3), col(255, 255, 255), 18)
    if clicked then return not value, true end
    return value, false
end

-- прокрутка страницы пальцем (в mimgui на телефоне колесика нет)
function M.touchScroll()
    if M.sliderT and os.clock() - M.sliderT < 0.15 then return end
    if not imgui.IsMouseDown(0) then return end
    if imgui.GetScrollMaxY() <= 0 then return end
    local flags = (imgui.HoveredFlags and imgui.HoveredFlags.AllowWhenBlockedByActiveItem) or 0
    local thr = math.max(22, (M.sh or 1080) * 0.022)
    if imgui.IsWindowHovered(flags) and imgui.IsMouseDragging(0, thr) then
        M.scrolling = true
        local d = imgui.GetIO().MouseDelta
        imgui.SetScrollY(imgui.GetScrollY() - d.y)
    end
end

-- ===================== РАССТАНОВКА ПАЛЬЦЕМ =====================
-- Двигаем окно продажи и кнопку меню: тянешь пальцем или жмёшь стрелки, "Готово" - сохранить.
local EDIT_KEYS  = { 'hud', 'btn', 'sell' }
local EDIT_NAMES = { hud = 'Окно', btn = 'Кнопка', sell = 'Бочка' }

function M.editing()
    return M.place or M.drag ~= nil
end

function M.editable(key)
    return M.place or M.drag == key
end

function M.ovPos(key, w, h, sw, sh)
    local o = M.ov[key]
    local fx = math.max(0, math.min((sw - w) / sw, o.x))
    local fy = math.max(0, math.min((sh - h) / sh, o.y))
    o.x, o.y = fx, fy
    local x, y = fx * sw, fy * sh
    M.rects[key] = { x = x, y = y, w = w, h = h, t = os.clock() }
    return x, y
end

function M.moveBy(key, dx, dy)
    local r = M.rects[key]
    if not r then return end
    if key == 'hud' then
        if pos then pos.x, pos.y = pos.x + dx, pos.y + dy end
        return
    end
    local sw, sh = getScreenResolution()
    local o = M.ov[key]
    o.x = math.max(0, math.min((sw - r.w) / sw, (r.x + dx) / sw))
    o.y = math.max(0, math.min((sh - r.h) / sh, (r.y + dy) / sh))
    r.x, r.y = o.x * sw, o.y * sh
end

function M.drawCross(dl, cx, cy, r, c)
    local V = imgui.ImVec2
    local t = r * 0.45
    local th = math.max(2, r * 0.16)
    dl:AddLine(V(cx - r * 0.75, cy), V(cx + r * 0.75, cy), c, th)
    dl:AddLine(V(cx, cy - r * 0.75), V(cx, cy + r * 0.75), c, th)
    dl:AddTriangleFilled(V(cx, cy - r), V(cx - t, cy - r + t * 1.3), V(cx + t, cy - r + t * 1.3), c)
    dl:AddTriangleFilled(V(cx, cy + r), V(cx + t, cy + r - t * 1.3), V(cx - t, cy + r - t * 1.3), c)
    dl:AddTriangleFilled(V(cx - r, cy), V(cx - r + t * 1.3, cy + t), V(cx - r + t * 1.3, cy - t), c)
    dl:AddTriangleFilled(V(cx + r, cy), V(cx + r - t * 1.3, cy - t), V(cx + r - t * 1.3, cy + t), c)
end

function M.drawArrow(dl, cx, cy, r, dx, dy, c)
    local V = imgui.ImVec2
    local px, py = -dy, dx
    dl:AddTriangleFilled(V(cx + dx * r, cy + dy * r),
        V(cx - dx * r * 0.7 + px * r, cy - dy * r * 0.7 + py * r),
        V(cx - dx * r * 0.7 - px * r, cy - dy * r * 0.7 - py * r), c)
end

function M.editFrame(dl, key, x0, y0, x1, y1, r, e)
    if not M.editable(key) then return end
    local V = imgui.ImVec2
    local on = (M.pick == key)
    dl:AddRect(V(x0 - 3, y0 - 3), V(x1 + 3, y1 + 3), colT(on and GREEN or BLUE, (on and 1 or 0.45) * e),
        r + 3, RC_ALL, on and 3 or 1.5)
end

function M.startEdit(key)
    if not M.on then say('{FF0000}Скрипт выключен{FFFFFF} - включи его в меню') return end
    M.snap = { hud = pos and { x = pos.x, y = pos.y }, btn = { x = M.ov.btn.x, y = M.ov.btn.y },
               sell = { x = M.ov.sell.x, y = M.ov.sell.y } }
    M.place, M.drag, M.grab = (key == nil), key, nil
    M.pick = key or 'hud'
    if key == nil or key == 'hud' then show[0] = true end
    if key == nil or key == 'btn' then mbtnOn = true end
    if key == nil or key == 'sell' then BX.on = true end
    M.open[0] = false
    if key then
        say('{FFFFFF}Тяни пальцем или жми стрелки. {c0c0c0}Готово{FFFFFF} - сохранить')
    else
        say('{FFFFFF}Расстановка: выбери окно или кнопку и тяни пальцем. {c0c0c0}Готово{FFFFFF} - сохранить')
    end
end

function M.finishEdit(save)
    if not M.editing() then return false end
    local sn = M.snap
    if not save and sn then
        if sn.hud then pos = { x = sn.hud.x, y = sn.hud.y } end
        if sn.btn then M.ov.btn.x, M.ov.btn.y = sn.btn.x, sn.btn.y end
        if sn.sell then M.ov.sell.x, M.ov.sell.y = sn.sell.x, sn.sell.y end
    end
    M.place, M.drag, M.grab, M.snap = false, nil, nil, nil
    saveConfig()
    say(save and '{FFFFFF}Позиции {00FF00}сохранены' or '{FFFFFF}Изменения {FF0000}отменены')
    return true
end

local function flatFlags(extra)
    local f = imgui.WindowFlags
    return f.NoTitleBar + f.NoResize + f.NoMove + f.NoScrollbar + f.NoScrollWithMouse
         + (f.NoSavedSettings or 0) + f.NoCollapse + (extra or 0)
end

-- прозрачная зона поверх оверлея: ловит касание и перетаскивание
function M.zone(id, x, y, w, h)
    local V = imgui.ImVec2
    imgui.SetNextWindowPos(V(x, y), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(w, h), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(0, 0))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
    local clicked, active = false, false
    local f = imgui.WindowFlags
    if imgui.Begin(id, nil, flatFlags((f.NoBackground or 0) + (f.NoBringToFrontOnFocus or 0))) then
        imgui.SetCursorScreenPos(V(x, y))
        clicked = imgui.InvisibleButton(id .. 'b', V(w, h))
        active = imgui.IsItemActive()
    end
    imgui.End()
    imgui.PopStyleColor()
    imgui.PopStyleVar()
    return clicked, active
end

local function dragKey(key)
    local mp = imgui.GetMousePos()
    local g = M.grab
    if g and g.key == key then M.moveBy(key, mp.x - g.x, mp.y - g.y) end
    M.grab = { key = key, x = mp.x, y = mp.y }
end

local function fresh(key)
    local r = M.rects[key]
    return r and M.editable(key) and os.clock() - r.t < 0.3
end

local function padButton(id, size, draw)
    local V = imgui.ImVec2
    local p = imgui.GetCursorScreenPos()
    imgui.InvisibleButton(id, V(size, size))
    local act = imgui.IsItemActive()
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(p, V(p.x + size, p.y + size), col(255, 255, 255, act and 0.30 or 0.10), 10)
    draw(dl, p.x + size / 2, p.y + size / 2, act)
    return act
end

local function panelButton(label, h, c)
    imgui.PushStyleColor(imgui.Col.Button,        M.v4(c, 0.20))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, M.v4(c, 0.30))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  M.v4(c, 0.45))
    imgui.PushStyleColor(imgui.Col.Text,          M.v4(c, 1))
    local r = imgui.Button(label, imgui.ImVec2(0, h))
    imgui.PopStyleColor(4)
    return r
end

-- куда поставить панель управления, чтобы не закрывать оверлеи
local function panelSpot(sw, sh, pw, ph)
    local now = os.clock()
    local spots = {
        { sw / 2 - pw / 2, 6 }, { sw / 2 - pw / 2, sh - ph - 6 },
        { 6, 6 }, { sw - pw - 6, 6 }, { 6, sh - ph - 6 }, { sw - pw - 6, sh - ph - 6 },
        { sw / 2 - pw / 2, sh / 2 - ph / 2 },
    }
    local best, bestScore
    for _, p in ipairs(spots) do
        local score = 0
        for _, key in ipairs(EDIT_KEYS) do
            local r = M.rects[key]
            if r and now - r.t < 0.3 then
                local ix = math.min(p[1] + pw, r.x + r.w) - math.max(p[1], r.x)
                local iy = math.min(p[2] + ph, r.y + r.h) - math.max(p[2], r.y)
                if ix > 0 and iy > 0 then score = score + ix * iy * (key == M.pick and 4 or 1) end
            end
        end
        if not bestScore or score < bestScore - 1 then best, bestScore = p, score end
    end
    return best[1], best[2]
end

function M.editPanel(sw, sh)
    local V = imgui.ImVec2
    local now = os.clock()
    local active = false
    if not M.grab or not M.panelPos then
        local ps = M.panelSize or { x = 480, y = 110 }
        local x, y = panelSpot(sw, sh, ps.x, ps.y)
        M.panelPos = { x = x, y = y }
    end
    imgui.SetNextWindowPos(V(M.panelPos.x, M.panelPos.y), imgui.Cond.Always)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(10, 10))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V(6, 6))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V(14, 6))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.06, 0.09, 0.96))
    if imgui.Begin('##EditPanel', nil, flatFlags(imgui.WindowFlags.AlwaysAutoResize)) then
        M.panelSize = imgui.GetWindowSize()
        local hs = math.max(40, imgui.CalcTextSize('Ag').y + 18)
        if M.place then
            local first = true
            for _, key in ipairs(EDIT_KEYS) do
                if fresh(key) then
                    if not first then imgui.SameLine() end
                    first = false
                    if panelButton(u8(EDIT_NAMES[key]) .. '##pick' .. key, hs, M.pick == key and GREEN or BLUE) then
                        M.pick = key
                    end
                end
            end
        end
        if padButton('##mvc', hs, function(dl, cx, cy, act)
            M.drawCross(dl, cx, cy, hs * 0.3, act and colT(GREEN) or col(255, 255, 255))
        end) then
            dragKey(M.pick)
            active = true
        end
        for i, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
            imgui.SameLine()
            local held = padButton('##mv' .. i, hs, function(dl, cx, cy)
                M.drawArrow(dl, cx, cy, hs * 0.2, d[1], d[2], col(220, 225, 240))
            end)
            if held then
                local t = M.nudge[i]
                if not t then
                    M.nudge[i] = now + 0.35
                    M.moveBy(M.pick, d[1] * 2, d[2] * 2)
                elseif now >= t then
                    M.nudge[i] = now + 0.03
                    M.moveBy(M.pick, d[1] * 5, d[2] * 5)
                end
            else
                M.nudge[i] = nil
            end
        end
        imgui.SameLine(0, 14)
        if panelButton(u8'Готово##editok', hs, GREEN) then M.finishEdit(true) end
        imgui.SameLine()
        if panelButton(u8'Отмена##editno', hs, RED) then M.finishEdit(false) end
    end
    imgui.End()
    imgui.PopStyleColor()
    imgui.PopStyleVar(4)
    return active
end

function M.editUI(sw, sh)
    if not M.editing() then
        M.grab = nil
        return
    end
    if not fresh(M.pick) then
        for _, key in ipairs(EDIT_KEYS) do
            if fresh(key) then M.pick = key break end
        end
    end
    local active = false
    for _, key in ipairs(EDIT_KEYS) do
        if fresh(key) then
            local r = M.rects[key]
            local _, act = M.zone('##grab_' .. key, r.x, r.y, r.w, r.h)
            if act then
                M.pick = key
                dragKey(key)
                active = true
            end
        end
    end
    local gs = beginScale(fontS * math.max(0.9, math.min(1.6, sh / 600)))
    imgui.PushFont(fontSmall)
    if M.editing() and M.editPanel(sw, sh) then active = true end
    imgui.PopFont()
    endScale(gs, fontSmall)
    if not active then M.grab = nil end
end

-- ===================== ДЕЙСТВИЯ МЕНЮ =====================
M.toggles = {
    master = { u8'Скрипт включён', u8'Выкл - счёт, логи и уведомления не работают, меню остаётся. Запоминается',
        function() return M.on end,
        function(v) M.setEnabled(v) end },
    hud = { u8'Окно продажи', u8'Счётчик бочек, таймер КД, выручка и багажники на экране',
        function() return show[0] end,
        function(v) show[0] = v end },
    mbtn = { u8'Кнопка меню на экране', u8'Бочка на экране открывает меню без команды /oil',
        function() return mbtnOn end,
        function(v) mbtnOn = v end },
    sbtn = { u8'Кнопка "Достать бочку"', u8'Одно нажатие: /invent и по очереди продаёт бочки из инвентаря. Ещё раз - стоп',
        function() return BX.on end,
        function(v) BX.on = v end },
    anim = { u8'Блок анимации', u8'Не даёт серверу заморозить персонажа после продажи',
        function() return noAnim end,
        function(v) noAnim = v end },
    chat = { u8'Сообщения в чат', u8'Писать в чат о проданных бочках, лимите и пустом багажнике',
        function() return chatOn end,
        function(v) chatOn = v end },
}

function M.drawToggles(keys)
    for _, k in ipairs(keys) do
        local t = M.toggles[k]
        local nv, changed = M.toggle(t[1], t[2], t[3](), M.tIcons[k])
        if changed then
            t[4](nv)
            saveConfig()
        end
    end
end

function M.setFontScale(v)
    fontS = roundTenth(clampN(v, FONT_MIN, FONT_MAX))
    M.slF.font[0] = fontS
    M.scaleDirty = true
end

function M.setOvScale(v)
    ovS = roundTenth(clampN(v, OV_MIN, OV_MAX))
    M.slF.ov[0] = ovS
    M.scaleDirty = true
end

function M.setMenuMode(m)
    menuMode = math.floor(clampN(m, 1, 3))
    M.winPos = nil
    saveConfig()
end

function M.resetPos()
    pos = nil
    cfg.main.x, cfg.main.y = -1, -1
    M.ov.btn.x, M.ov.btn.y = BTN_X, BTN_Y
    M.ov.sell.x, M.ov.sell.y = BX.SX, BX.SY
    saveConfig()
end

function M.setEnabled(v)
    v = v and true or false
    if v == M.on then return end
    M.on = v
    cfg.main.enabled = v and 1 or 0
    if not v then
        M.place, M.drag, M.grab, M.snap = false, nil, nil, nil
        BX.tok = nil
        salePending = {}
    end
    saveConfig()
    say(v and '{FFFFFF}Скрипт {00FF00}включён' or '{FFFFFF}Скрипт {FF0000}выключен {FFFFFF}- счёт и уведомления не работают, меню открывается по {c0c0c0}/oil')
end

function M.resetAll()
    M.place, M.drag, M.grab, M.snap = false, nil, nil, nil
    noAnim, chatOn, mbtnOn, BX.on = true, true, true, true
    show[0] = true
    pos = nil
    cfg.main.x, cfg.main.y = -1, -1
    M.ov.btn.x, M.ov.btn.y = BTN_X, BTN_Y
    M.ov.sell.x, M.ov.sell.y = BX.SX, BX.SY
    M.winPos = nil
    menuMode = 2
    M.setFontScale(DEF_FONT)
    M.setOvScale(DEF_OV)
    M.on = false
    M.setEnabled(true)
    say('{FFFFFF}Настройки {00FF00}сброшены {FFFFFF}до заводских, скрипт включён')
end

-- ===================== СТРАНИЦЫ МЕНЮ =====================
function M.pageOverview()
    local V = imgui.ImVec2
    local dl = imgui.GetWindowDrawList()
    local left   = windowLeft()
    local inWin  = lastSaleAt ~= 0 and left > 0
    local locked = sold >= LIMIT and left > 0
    local acc    = locked and RED or (inWin and AMBER or GREEN)
    local status = locked and u8'ЛИМИТ - ждём конец КД' or (inWin and u8'ИДЁТ ПРОДАЖА' or u8'СВОБОДНО')

    if not M.on then
        imgui.PushFont(fontMid)
        M.text(RED, u8'СКРИПТ ВЫКЛЮЧЕН')
        imgui.PopFont()
        M.wrap(GRAY, u8'Продажи не считаются, уведомления не идут. Меню доступно.')
        if M.btn(u8'Включить скрипт###pwron', Z(190), Z(34), GREEN) then M.setEnabled(true) end
        imgui.Spacing()
    end
    imgui.PushFont(fontMid)
    M.text(acc, status)
    imgui.PopFont()

    local p0 = imgui.GetCursorScreenPos()
    local aw = imgui.GetContentRegionAvail().x
    local gp = Z(10)
    local cw, ch = (aw - gp) / 2, Z(76)
    local cards = {
        { u8'Продано бочек', sold .. ' / ' .. LIMIT, acc },
        { locked and u8'До конца КД' or u8'До сброса лимита', (inWin or locked) and fmtTime(left) or '--:--', BLUE },
        { u8'Выручка за окно, руб', fmtMoney(earned), WHITE },
        { 'AZ Coins', fmtMoney(azTotal), GOLD },
    }
    for i, c in ipairs(cards) do
        local cx = p0.x + ((i - 1) % 2) * (cw + gp)
        local cy = p0.y + math.floor((i - 1) / 2) * (ch + gp)
        dl:AddRectFilled(V(cx, cy), V(cx + cw, cy + ch), col(20, 23, 34), Z(12))
        dl:AddRect(V(cx, cy), V(cx + cw, cy + ch), colT(c[3], 0.28), Z(12), RC_ALL, Z(1.2))
        dl:AddText(V(cx + Z(14), cy + Z(10)), colT(GRAY), fit(c[1], cw - Z(20)))
        imgui.PushFont(fontBig)
        dl:AddText(V(cx + Z(14), cy + Z(28)), colT(c[3]), c[2])
        imgui.PopFont()
    end
    imgui.Dummy(V(aw, ch * 2 + gp))

    local bp = imgui.GetCursorScreenPos()
    dl:AddRectFilled(V(bp.x, bp.y), V(bp.x + aw, bp.y + Z(10)), col(30, 34, 48), Z(5))
    local f = aw * math.min(sold / LIMIT, 1)
    if f > 1 then dl:AddRectFilled(V(bp.x, bp.y), V(bp.x + f, bp.y + Z(10)), colT(acc), Z(5)) end
    imgui.Dummy(V(aw, Z(14)))
    M.text(GRAY, u8'Осталось продать до лимита: ' .. math.max(LIMIT - sold, 0))

    imgui.Spacing()
    local tn, tl, tv = trunkTotals()
    if tn > 0 then
        M.text(GOLD, u8'В багажниках: ' .. tn .. u8' бочек, ' .. tl .. u8' л  |  машин: ' .. tv)
    else
        M.text(DIM, u8'В багажниках бочек нет. Подробности - на вкладке "Машины".')
    end
    M.text(GRAY, u8'За всё время: ' .. agg.all.n .. u8' бочек, ' .. fmtMoney(agg.all.money) .. u8' руб')
    M.text(DIM, u8'Подробные логи - на вкладке "Логи".')
end

function M.pageOverlays()
    M.text(DIM, u8'ПОКАЗ НА ЭКРАНЕ')
    M.drawToggles({ 'hud', 'mbtn', 'sbtn' })
    if BX.ready() then
        M.text(GREEN, u8'Бочка: пакеты записаны, кнопка готова')
    else
        M.wrap(AMBER, u8'Бочка: пакет запишется сам при первом открытии инвентаря (/invent), можно просто нажать кнопку')
    end

    imgui.Spacing()
    M.text(DIM, u8'ПОЗИЦИЯ')
    M.wrap(GRAY, u8'Нажми кнопку - меню закроется, тяни окно или кнопку пальцем (или жми стрелки). Готово - сохранить.')
    local aw = imgui.GetContentRegionAvail().x
    local sp = Z(8)
    local bw = (aw - sp) / 2
    if M.btn(u8'Окно продажи###mvhud', bw, Z(42), BLUE) then M.startEdit('hud') end
    imgui.SameLine(0, sp)
    if M.btn(u8'Кнопка меню###mvbtn', bw, Z(42), BLUE) then M.startEdit('btn') end
    if M.btn(u8'Кнопка бочки###mvsell', bw, Z(42), BLUE) then M.startEdit('sell') end
    if M.btn(u8'Расставить всё###mvall', aw, Z(42), GREEN) then M.startEdit(nil) end
    M.wrap(GRAY, u8'Само меню двигается за крестик в шапке.')
    imgui.Spacing()
    if M.confirmBtn('resetpos', u8'Сбросить позиции', Z(220), Z(36), AMBER) then M.resetPos() end
end

function M.pageVehicles()
    local V  = imgui.ImVec2
    local dl = imgui.GetWindowDrawList()
    local tn, tl, tv = trunkTotals()

    M.text(DIM, u8'БОЧКИ В БАГАЖНИКАХ')
    M.text(GOLD, u8'Всего: ' .. tn .. u8' бочек, ' .. tl .. u8' л, машин: ' .. tv)
    M.wrap(DIM, u8'Открой багажник через диалог - запомню машину. Что кладёшь и достаёшь, записываю. '
        .. u8'Нефть в бочке теряет 1 л каждые 8 часов с момента, когда её положили (по реальному времени, в сети или нет).')
    imgui.Spacing()

    local names = {}
    for name in pairs(trunks) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        local ca, cb = trunkStats(trunks[a]), trunkStats(trunks[b])
        if ca ~= cb then return ca > cb end
        return a < b
    end)
    if #names == 0 then M.text(DIM, u8'Пока пусто. Открой багажник и положи бочки.') end

    local rmTrunk
    for i, name in ipairs(names) do
        local tr   = trunks[name]
        local n, lit = trunkStats(tr)
        local cap  = trunkCap(name, tr)
        local p0   = imgui.GetCursorScreenPos()
        local w    = imgui.GetContentRegionAvail().x
        local h    = Z(110)
        dl:AddRectFilled(p0, V(p0.x + w, p0.y + h), col(20, 23, 34), Z(10))
        if name == openTrunk then
            dl:AddRect(p0, V(p0.x + w, p0.y + h), colT(GREEN, 0.5), Z(10), RC_ALL, Z(1.2))
        end
        local cnt = n .. (cap and (' / ' .. cap) or '') .. u8' бочек'
        local cntW = imgui.CalcTextSize(cnt).x
        dl:AddText(V(p0.x + Z(14), p0.y + Z(9)), col(255, 255, 255), fit(name, w - cntW - Z(40)))
        dl:AddText(V(p0.x + w - Z(14) - cntW, p0.y + Z(9)), colT(n > 0 and GOLD or DIM), cnt)

        dl:AddText(V(p0.x + Z(14), p0.y + Z(31)), colT(GRAY),
            fit(u8'Нефти: ' .. lit .. u8' л   |   положено: ' .. (tr.put or 0) .. u8'   достано: ' .. (tr.took or 0), w - Z(28)))

        local g, ls = {}, {}
        for _, b in pairs(tr.items) do
            local l = barrelLiters(b)
            g[l] = (g[l] or 0) + 1
        end
        for l in pairs(g) do ls[#ls + 1] = l end
        table.sort(ls, function(a, b) return a > b end)
        local parts = {}
        for _, l in ipairs(ls) do parts[#parts + 1] = l .. u8' л x' .. g[l] end
        dl:AddText(V(p0.x + Z(14), p0.y + Z(52)), colT(n > 0 and BLUE or DIM),
            fit(#parts > 0 and table.concat(parts, '   ') or u8'пусто', w - Z(28)))

        imgui.SetCursorScreenPos(V(p0.x + w - Z(196), p0.y + Z(74)))
        if M.confirmBtn('trc' .. i, u8'Очистить запись', Z(182), Z(30), RED) then rmTrunk = name end
        imgui.SetCursorScreenPos(p0)
        imgui.Dummy(V(w, h))
    end
    if rmTrunk then trunkClear(rmTrunk) end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    M.text(DIM, M.edit and u8'РЕДАКТИРОВАНИЕ МАШИНЫ' or u8'НОВАЯ МАШИНА')
    local aw = imgui.GetContentRegionAvail().x
    imgui.PushItemWidth(aw - Z(140))
    imgui.InputTextWithHint('##vname', u8'Название, например: Peterbilt 359', M.inVeh, ffi.sizeof(M.inVeh))
    imgui.PopItemWidth()
    imgui.SameLine(0, Z(8))
    imgui.PushItemWidth(Z(132))
    imgui.InputInt('##vn', M.inVehN, 1, 5)
    imgui.PopItemWidth()

    if M.btn((M.edit and u8'Сохранить' or u8'Добавить') .. '###vform', Z(150), Z(34), GREEN) then
        local name = sanitize(fromU8(ffi.string(M.inVeh)))
        local n = math.max(1, M.inVehN[0])
        if name ~= '' then
            if M.edit and vehicles[M.edit] then
                vehicles[M.edit].name = name
                vehicles[M.edit].n    = n
            else
                vehicles[#vehicles + 1] = { name = name, n = n }
            end
            M.edit = nil
            ffi.fill(M.inVeh, ffi.sizeof(M.inVeh))
            M.inVehN[0] = 10
            saveConfig()
        end
    end
    if M.edit then
        imgui.SameLine(0, Z(8))
        if M.btn(u8'Отмена###vcancel', Z(110), Z(34), GRAY) then
            M.edit = nil
            ffi.fill(M.inVeh, ffi.sizeof(M.inVeh))
            M.inVehN[0] = 10
        end
    end
    imgui.SameLine(0, Z(8))
    if M.confirmBtn('vdef', u8'Вернуть стандартные', Z(190), Z(34), AMBER) then
        vehicles = {}
        for _, d in ipairs(DEFAULT_VEHICLES) do vehicles[#vehicles + 1] = { name = d[1], n = d[2] } end
        M.edit = nil
        saveConfig()
    end

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    M.text(DIM, u8'ВМЕСТИМОСТЬ МАШИН  (если сервер не сообщил лимит багажника, берётся отсюда)')

    local rm
    local curL = curVeh:lower()
    for i, v in ipairs(vehicles) do
        local p0 = imgui.GetCursorScreenPos()
        local w  = imgui.GetContentRegionAvail().x
        local h  = Z(48)
        local btnW = Z(100) + Z(40) + Z(6)
        dl:AddRectFilled(p0, V(p0.x + w, p0.y + h), col(20, 23, 34), Z(10))
        if curL ~= '' and u8(v.name):lower() == curL then
            dl:AddRect(p0, V(p0.x + w, p0.y + h), colT(GREEN, 0.5), Z(10), RC_ALL, Z(1.2))
        end
        local cnt = v.n .. u8' бочек'
        local cx = p0.x + w - btnW - Z(24) - imgui.CalcTextSize(cnt).x
        dl:AddText(V(p0.x + Z(14), p0.y + h / 2 - imgui.CalcTextSize('Ag').y / 2), col(255, 255, 255),
            fit(u8(v.name), cx - p0.x - Z(24)))
        dl:AddText(V(cx, p0.y + h / 2 - imgui.CalcTextSize('Ag').y / 2), colT(GOLD), cnt)
        imgui.SetCursorScreenPos(V(p0.x + w - btnW - Z(8), p0.y + Z(8)))
        if M.btn(u8'Изменить###ve' .. i, Z(100), Z(32), BLUE) then
            M.edit = i
            ffi.copy(M.inVeh, u8(v.name))
            M.inVehN[0] = v.n
        end
        imgui.SameLine(0, Z(6))
        if M.btn('x###vd' .. i, Z(40), Z(32), RED) then rm = i end
        imgui.SetCursorScreenPos(p0)
        imgui.Dummy(V(w, h))
    end
    if rm then
        table.remove(vehicles, rm)
        if M.edit == rm then M.edit = nil end
        saveConfig()
    end
    if #vehicles == 0 then M.text(DIM, u8'Список пуст.') end
end

function M.pageLogs()
    local V = imgui.ImVec2
    local dl = imgui.GetWindowDrawList()
    local aw = imgui.GetContentRegionAvail().x
    local today = agg.days[os.date('%Y-%m-%d')] or { n = 0, money = 0, liters = 0 }
    local all   = agg.all
    local avg   = all.n > 0 and math.floor(all.money / all.n) or 0

    local cards = {
        { u8'Сегодня',      today.n .. u8' бочек', fmtMoney(today.money) .. u8' руб', GREEN },
        { u8'За всё время', all.n .. u8' бочек',   fmtMoney(all.money) .. u8' руб',   BLUE },
        { u8'За эту игру',  sess.n .. u8' бочек',  fmtMoney(sess.money) .. u8' руб',  AMBER },
    }
    local p0 = imgui.GetCursorScreenPos()
    local gp = Z(8)
    local cw, ch = (aw - gp * 2) / 3, Z(84)
    for i, c in ipairs(cards) do
        local cx = p0.x + (i - 1) * (cw + gp)
        dl:AddRectFilled(V(cx, p0.y), V(cx + cw, p0.y + ch), col(20, 23, 34), Z(12))
        dl:AddRect(V(cx, p0.y), V(cx + cw, p0.y + ch), colT(c[4], 0.28), Z(12), RC_ALL, Z(1.2))
        dl:AddText(V(cx + Z(12), p0.y + Z(9)), colT(GRAY), fit(c[1], cw - Z(16)))
        imgui.PushFont(fontMid)
        dl:AddText(V(cx + Z(12), p0.y + Z(28)), colT(c[4]), fit(c[2], cw - Z(16)))
        imgui.PopFont()
        dl:AddText(V(cx + Z(12), p0.y + Z(58)), colT(GOLD), fit(c[3], cw - Z(16)))
    end
    imgui.Dummy(V(aw, ch + Z(4)))
    M.text(GRAY, u8'Средняя цена бочки: ' .. fmtMoney(avg) .. u8' руб   |   Литров всего: ' .. fmtMoney(all.liters))

    imgui.Spacing()
    M.text(DIM, u8'ПО ДНЯМ')
    local keys = {}
    for k in pairs(agg.days) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return a > b end)
    if #keys == 0 then M.text(DIM, u8'Пока пусто. Продай бочку - тут появится история.') end
    local rowH = Z(34)
    local th = imgui.CalcTextSize('Ag').y
    for i = 1, math.min(#keys, 7) do
        local k = keys[i]
        local d = agg.days[k]
        local p = imgui.GetCursorScreenPos()
        dl:AddRectFilled(p, V(p.x + aw, p.y + rowH), col(20, 23, 34), Z(8))
        dl:AddText(V(p.x + Z(12), p.y + rowH / 2 - th / 2), col(255, 255, 255), k:sub(9, 10) .. '.' .. k:sub(6, 7) .. '.' .. k:sub(1, 4))
        dl:AddText(V(p.x + aw * 0.28, p.y + rowH / 2 - th / 2), colT(GRAY), d.n .. u8' бочек')
        dl:AddText(V(p.x + aw * 0.50, p.y + rowH / 2 - th / 2), colT(GOLD), fmtMoney(d.money) .. u8' руб')
        dl:AddText(V(p.x + aw * 0.78, p.y + rowH / 2 - th / 2), colT(DIM), fmtMoney(d.liters) .. u8' л')
        imgui.Dummy(V(aw, rowH))
    end

    imgui.Spacing()
    M.text(DIM, u8'ПОСЛЕДНИЕ ПРОДАЖИ')
    if #logs == 0 then M.text(DIM, u8'Пока пусто.') end
    rowH = Z(32)
    for i = #logs, math.max(1, #logs - 39), -1 do
        local e = logs[i]
        local p = imgui.GetCursorScreenPos()
        dl:AddRectFilled(p, V(p.x + aw, p.y + rowH), col(20, 23, 34), Z(8))
        dl:AddText(V(p.x + Z(12), p.y + rowH / 2 - th / 2), colT(GRAY), os.date('%d.%m  %H:%M:%S', e.t))
        dl:AddText(V(p.x + aw * 0.27, p.y + rowH / 2 - th / 2), colT(DIM), e.l .. u8' л')
        dl:AddText(V(p.x + aw * 0.38, p.y + rowH / 2 - th / 2), colT(GOLD), '+' .. fmtMoney(e.p))
        if e.v ~= '' then
            dl:AddText(V(p.x + aw * 0.58, p.y + rowH / 2 - th / 2), colT(GRAY), fit(e.v, aw * 0.42 - Z(12)))
        end
        imgui.Dummy(V(aw, rowH))
    end

    imgui.Spacing()
    if M.confirmBtn('clrlog', u8'Очистить логи', Z(200), Z(36), RED) then logClear() end
end

function M.pageTelegram()
    if not tgBackend then
        M.wrap(RED, u8'Нет сетевой библиотеки (effil / copas / ssl.https) - отправка в Telegram недоступна')
    end

    M.text(DIM, u8'УВЕДОМЛЕНИЯ')
    local nv, ch = M.toggle(u8'Отправлять в Telegram', u8'Бот пришлёт сообщение, когда случится выбранное событие',
        tgEnabled[0], 'SEND')
    if ch then
        tgEnabled[0] = nv
        tgApply()
    end

    imgui.Spacing()
    M.text(DIM, u8'ДАННЫЕ БОТА')
    local aw = imgui.GetContentRegionAvail().x
    imgui.PushItemWidth(aw)
    local flags = M.showTok and 0 or imgui.InputTextFlags.Password
    if imgui.InputTextWithHint('##tgtoken', u8'Токен бота (выдаёт @BotFather)', tgTokenBuf,
        ffi.sizeof(tgTokenBuf), flags) then tgApply() end
    if imgui.InputTextWithHint('##tgchat', u8'Ваш Telegram ID (узнать у @userinfobot)', tgChatBuf,
        ffi.sizeof(tgChatBuf)) then tgApply() end
    imgui.PopItemWidth()
    if M.btn((M.showTok and u8'Скрыть токен' or u8'Показать токен') .. '###tgshow', Z(180), Z(32), GRAY) then
        M.showTok = not M.showTok
    end

    local chat = trim(ffi.string(tgChatBuf))
    if chat ~= '' and not chat:match('^%-?%d+$') then
        M.text(AMBER, u8'ID должен состоять только из цифр')
    end

    imgui.Spacing()
    M.text(DIM, u8'КОГДА УВЕДОМЛЯТЬ')
    local v1, c1 = M.toggle(u8'Лимит достигнут', u8'Продано максимум бочек, пошёл КД', tgOnLimit[0])
    if c1 then tgOnLimit[0] = v1; saveConfig() end
    local v2, c2 = M.toggle(u8'КД закончился', u8'Можно сдавать бочки снова', tgOnEnd[0])
    if c2 then tgOnEnd[0] = v2; saveConfig() end
    local v3, c3 = M.toggle(u8'Багажник пуст', u8'Достал последнюю бочку из багажника', tgOnTrunk[0])
    if c3 then tgOnTrunk[0] = v3; saveConfig() end

    imgui.Spacing()
    if M.btn(u8'Отправить тест###tgtest', Z(220), Z(36), GREEN) then
        tgApply()
        if not tgBackend then
            tgStatus, tgStatusKind = 'Нет сетевой библиотеки', 'err'
        elseif not tgReady() then
            tgStatus, tgStatusKind = 'Укажите токен бота и свой ID', 'err'
        else
            tgStatus, tgStatusKind = 'Отправляю...', 'info'
            tgNotify(EMO.ok, 'BarrelSell: тестовое уведомление. Всё работает!', true)
        end
    end
    local sc = (tgStatusKind == 'ok' and GREEN) or (tgStatusKind == 'err' and RED) or GRAY
    M.wrap(sc, u8(tgStatus ~= '' and tgStatus or 'Сначала открой своего бота и нажми Start'))

    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()
    M.text(DIM, u8'КАК НАСТРОИТЬ')
    M.wrap(GRAY, u8'1. В Telegram найди @BotFather, нажми Start и отправь /newbot. Задай имя и username (должен кончаться на bot). Он пришлёт токен - вставь в поле выше.')
    M.wrap(GRAY, u8'2. Найди @userinfobot, нажми Start - он пришлёт твой ID (только цифры). Вставь во второе поле.')
    M.wrap(GRAY, u8'3. Открой СВОЕГО бота и нажми Start - иначе он не сможет тебе писать.')
    M.wrap(GRAY, u8'4. Нажми "Отправить тест". Уведомления идут, только пока запущена игра со скриптом.')
    M.wrap(RED, u8'Токен никому не показывай - с ним можно управлять твоим ботом.')
end

-- строка "-  [ползунок]  +  Сброс"
function M.scaleRow(id, title, get, set, lo, hi, def, buf)
    local bh = Z(40)
    local sp = Z(8)
    M.text(DIM, title)
    local aw = imgui.GetContentRegionAvail().x
    local bsz, rsz = Z(48), Z(102)
    if M.btn('-###' .. id .. 'm', bsz, bh, RED) then set(get() - 0.1); saveConfig(); M.scaleDirty = false end
    imgui.SameLine(0, sp)
    imgui.PushItemWidth(aw - bsz * 2 - rsz - sp * 3)
    buf[0] = get()
    if imgui.SliderFloat('##' .. id, buf, lo, hi, '%.2f') then set(buf[0]) end
    if imgui.IsItemActive() then M.sliderT = os.clock() end
    imgui.PopItemWidth()
    imgui.SameLine(0, sp)
    if M.btn('+###' .. id .. 'p', bsz, bh, GREEN) then set(get() + 0.1); saveConfig(); M.scaleDirty = false end
    imgui.SameLine(0, sp)
    if M.btn(u8'Сброс###' .. id .. 'r', rsz, bh, AMBER) then set(def); saveConfig(); M.scaleDirty = false end
end

function M.pageSettings()
    M.text(DIM, u8'ГЛАВНЫЙ ВЫКЛЮЧАТЕЛЬ')
    M.drawToggles({ 'master' })

    imgui.Spacing()
    M.text(DIM, u8'РАЗМЕР МЕНЮ')
    do
        local aw = imgui.GetContentRegionAvail().x
        local sp = Z(8)
        local bw = (aw - sp * 2) / 3
        local bh = Z(42)
        local names = { u8'Маленькое', u8'Стандарт', u8'Большое' }
        for i = 1, 3 do
            if i > 1 then imgui.SameLine(0, sp) end
            if M.btn(names[i] .. '###msz' .. i, bw, bh, menuMode == i and GREEN or BLUE) then
                if menuMode ~= i then M.setMenuMode(i) end
            end
        end
    end

    imgui.Spacing()
    M.text(DIM, u8'РАЗМЕРЫ')
    M.scaleRow('fsz', u8'Шрифт', function() return fontS end,
        M.setFontScale, FONT_MIN, FONT_MAX, DEF_FONT, M.slF.font)
    M.scaleRow('osz', u8'Окно продажи и кнопка', function() return ovS end,
        M.setOvScale, OV_MIN, OV_MAX, DEF_OV, M.slF.ov)
    if M.scaleDirty and not imgui.IsMouseDown(0) then
        M.scaleDirty = false
        saveConfig()
    end

    imgui.Spacing()
    M.text(DIM, u8'ФУНКЦИИ')
    M.drawToggles({ 'anim', 'chat' })

    imgui.Spacing()
    M.text(DIM, u8'СБРОС')
    if M.confirmBtn('rst', u8'Сбросить счётчик, КД и AZ Coins', Z(300), Z(36), RED) then
        azTotal = 0
        resetWindow()
        saveConfig()
    end

    imgui.Spacing()
    M.wrap(DIM, u8'Сброс настроек: переключатели, размеры и позиции вернутся к заводским. Логи, машины, записи багажников и данные Telegram останутся.')
    if M.confirmBtn('rstsettings', u8'Сбросить все настройки скрипта', Z(320), Z(36), AMBER) then M.resetAll() end
end

M.tabs = {
    { u8'Обзор',     'pageOverview' },
    { u8'Окно',      'pageOverlays' },
    { u8'Машины',    'pageVehicles' },
    { u8'Логи',      'pageLogs' },
    { u8'Telegram',  'pageTelegram' },
    { u8'Настройки', 'pageSettings' },
}

function M.sidebar()
    local V   = imgui.ImVec2
    local dl  = imgui.GetWindowDrawList()
    local top = imgui.GetCursorScreenPos()
    local w   = imgui.GetContentRegionAvail().x
    local ih, gap = Z(42), Z(4)

    local ty = (M.tab - 1) * (ih + gap)
    M.tabY = M.tabY and approach(M.tabY, ty, 16, M.dt) or ty
    dl:AddRectFilled(V(top.x, top.y + M.tabY), V(top.x + w, top.y + M.tabY + ih), colT(BLUE, 0.15), Z(12))
    dl:AddRectFilled(V(top.x, top.y + M.tabY + Z(12)), V(top.x + Z(3), top.y + M.tabY + ih - Z(12)), colT(BLUE), 2)

    for i, t in ipairs(M.tabs) do
        imgui.SetCursorScreenPos(V(top.x, top.y + (i - 1) * (ih + gap)))
        local p0 = imgui.GetCursorScreenPos()
        local pressed = imgui.InvisibleButton('##tab' .. i, V(w, ih))
        if pressed and M.tab ~= i then
            M.tab  = i
            M.tabT = os.clock()
        end
        local hv = approach(M.tabHov[i] or 0, imgui.IsItemHovered() and 1 or 0, 16, M.dt)
        M.tabHov[i] = hv
        if M.tab ~= i and hv > 0 then
            dl:AddRectFilled(p0, V(p0.x + w, p0.y + ih), col(255, 255, 255, 0.05 * hv), Z(12))
        end
        local k  = (M.tab == i) and 1 or (0.55 * hv)
        local tc = col(lerp(150, 255, k), lerp(156, 255, k), lerp(178, 255, k))
        imgui.PushFont(fontMid)
        local th = imgui.CalcTextSize(t[1]).y
        if faOk and M.tabIcons[i] then
            local ic  = fa(FA[M.tabIcons[i]])
            local isz = imgui.CalcTextSize(ic)
            dl:AddText(V(p0.x + Z(28) - isz.x / 2 + Z(3) * hv, p0.y + ih / 2 - isz.y / 2),
                (M.tab == i) and colT(BLUE) or tc, ic)
            dl:AddText(V(p0.x + Z(48) + Z(3) * hv, p0.y + ih / 2 - th / 2), tc, t[1])
        else
            dl:AddText(V(p0.x + Z(18) + Z(3) * hv, p0.y + ih / 2 - th / 2), tc, t[1])
        end
        imgui.PopFont()
    end

    local left   = windowLeft()
    local inWin  = lastSaleAt ~= 0 and left > 0
    local locked = sold >= LIMIT and left > 0
    local acc    = locked and RED or (inWin and AMBER or GREEN)
    imgui.SetCursorPosY(imgui.GetWindowHeight() - Z(78))
    imgui.SetCursorPosX(Z(10))
    M.text(DIM, u8'Продано')
    imgui.SetCursorPosX(Z(10))
    imgui.PushFont(fontMid)
    M.text(acc, sold .. ' / ' .. LIMIT .. ((inWin or locked) and ('   ' .. fmtTime(left)) or ''))
    imgui.PopFont()
    local bp = imgui.GetCursorScreenPos()
    local bw = w - Z(20)
    dl:AddRectFilled(V(bp.x + Z(10), bp.y + Z(3)), V(bp.x + Z(10) + bw, bp.y + Z(7)), col(30, 34, 48), Z(3))
    local f = bw * math.min(sold / LIMIT, 1)
    if f > 1 then dl:AddRectFilled(V(bp.x + Z(10), bp.y + Z(3)), V(bp.x + Z(10) + f, bp.y + Z(7)), colT(acc), Z(3)) end
    imgui.Dummy(V(1, Z(10)))
end

function M.draw()
    local V   = imgui.ImVec2
    local dl  = imgui.GetWindowDrawList()
    local p   = imgui.GetWindowPos()
    local now = os.clock()
    local pulse = 0.5 + 0.5 * math.sin(now * 3)

    dl:AddRectFilledMultiColor(V(p.x + Z(24), p.y + 1), V(p.x + MENU_W / 2, p.y + Z(3)),
        colT(GREEN, 0), colT(GREEN, 0.9), colT(GREEN, 0.9), colT(GREEN, 0))
    dl:AddRectFilledMultiColor(V(p.x + MENU_W / 2, p.y + 1), V(p.x + MENU_W - Z(24), p.y + Z(3)),
        colT(GREEN, 0.9), colT(GREEN, 0), colT(GREEN, 0), colT(GREEN, 0.9))

    dl:AddCircleFilled(V(p.x + Z(34), p.y + Z(32)), Z(16) + pulse * 1.5, colT(GREEN, 0.14), 24)
    if not M.icon(dl, 'OIL', p.x + Z(34), p.y + Z(32), GREEN, 1, fontMid) then
        dl:AddCircleFilled(V(p.x + Z(34), p.y + Z(32)), Z(5), colT(GREEN), 16)
    end
    imgui.PushFont(fontMid)
    dl:AddText(V(p.x + Z(60), p.y + Z(21)), col(255, 255, 255), 'BarrelSell')
    local titleW = imgui.CalcTextSize('BarrelSell').x
    imgui.PopFont()
    dl:AddText(V(p.x + math.max(Z(60) + titleW + Z(16), Z(190)), p.y + Z(25)), colT(DIM), u8'продажа нефти  |  by Edward')
    dl:AddRectFilled(V(p.x + Z(18), p.y + Z(54)), V(p.x + MENU_W - Z(18), p.y + Z(55)), col(255, 255, 255, 0.06))

    local ex = p.x + MENU_W - Z(44)
    do   -- ВКЛ / ВЫКЛ
        local bx0, by0, bw, bh = ex - Z(92), p.y + Z(19), Z(80), Z(26)
        imgui.SetCursorScreenPos(V(bx0, by0))
        local pressed = imgui.InvisibleButton('##power', V(bw, bh))
        local ph = imgui.IsItemHovered()
        if pressed then M.setEnabled(not M.on) end
        local pc = M.on and GREEN or RED
        dl:AddRectFilled(V(bx0, by0), V(bx0 + bw, by0 + bh), colT(pc, ph and 0.30 or 0.16), Z(13))
        dl:AddCircleFilled(V(bx0 + Z(16), by0 + bh / 2), Z(4), colT(pc), 12)
        dl:AddText(V(bx0 + Z(28), by0 + Z(5)), colT(pc), M.on and u8'ВКЛ' or u8'ВЫКЛ')
    end

    imgui.SetCursorScreenPos(V(p.x + MENU_W - Z(52), p.y + Z(14)))
    local closePressed = imgui.InvisibleButton('##close', V(Z(40), Z(40)))
    local hov = imgui.IsItemHovered()
    if closePressed then M.open[0] = false end
    M.closeH = approach(M.closeH, hov and 1 or 0, 16, M.dt)
    local cx, cy = p.x + MENU_W - Z(32), p.y + Z(32)
    dl:AddCircleFilled(V(cx, cy), Z(14), col(lerp(255, RED[1], M.closeH), lerp(255, RED[2], M.closeH),
        lerp(255, RED[3], M.closeH), lerp(0.05, 0.30, M.closeH)), 20)
    local cc = col(lerp(150, RED[1], M.closeH), lerp(156, RED[2], M.closeH), lerp(178, RED[3], M.closeH))
    dl:AddLine(V(cx - Z(5), cy - Z(5)), V(cx + Z(5), cy + Z(5)), cc, Z(1.8))
    dl:AddLine(V(cx - Z(5), cy + Z(5)), V(cx + Z(5), cy - Z(5)), cc, Z(1.8))

    do   -- крестик-ручка: двигает само меню
        local hx0, hy0 = p.x + MENU_W - Z(184), p.y + Z(14)
        imgui.SetCursorScreenPos(V(hx0, hy0))
        imgui.InvisibleButton('##menumove', V(Z(40), Z(40)))
        local act = imgui.IsItemActive()
        dl:AddCircleFilled(V(hx0 + Z(20), hy0 + Z(18)), Z(17), colT(BLUE, act and 0.45 or 0.18), 20)
        M.drawCross(dl, hx0 + Z(20), hy0 + Z(18), Z(10), col(255, 255, 255))
        if act then
            local mp = imgui.GetMousePos()
            local last = M.menuHP
            if last and M.winPos then
                local sw, sh = getScreenResolution()
                M.winPos.x = math.max(0, math.min(sw - MENU_W, M.winPos.x + mp.x - last.x))
                M.winPos.y = math.max(0, math.min(sh - MENU_H, M.winPos.y + mp.y - last.y))
            end
            M.menuHP = { x = mp.x, y = mp.y }
        else
            M.menuHP = nil
        end
    end

    imgui.SetCursorPos(V(Z(14), Z(64)))
    imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(0, 0))
    imgui.BeginChild('##side', V(Z(170), MENU_H - Z(78)), true)
    imgui.PopStyleVar()
    M.sidebar()
    imgui.EndChild()
    imgui.PopStyleColor()

    local tabA = ease((now - M.tabT) / 0.22)
    local cw, ch = MENU_W - Z(206), MENU_H - Z(78)
    dl:AddRectFilled(V(p.x + Z(192), p.y + Z(64)), V(p.x + Z(192) + cw, p.y + Z(64) + ch), col(17, 19, 28), Z(16))
    dl:AddRect(V(p.x + Z(192), p.y + Z(64)), V(p.x + Z(192) + cw, p.y + Z(64) + ch), col(255, 255, 255, 0.05), Z(16), RC_ALL, 1)
    imgui.SetCursorPos(V(Z(192) + Z(14), Z(64) + Z(12) + (1 - tabA) * Z(10)))
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(M.alpha * tabA, 0.01))
    imgui.BeginChild('##content', V(cw - Z(28), ch - Z(24)), false)
    local page = M.tabs[M.tab]
    if page then M[page[2]]() end
    M.touchScroll()
    imgui.EndChild()
    imgui.PopStyleVar()
end

-- ===================== ИНИЦИАЛИЗАЦИЯ imgui =====================
imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    local atlas  = io.Fonts
    local ranges = atlas:GetGlyphRangesCyrillic()
    local wd = getWorkingDirectory()

    local faPath = firstExisting({
        wd .. '/resource/fonts/fa-solid-900.ttf',
        'moonloader/resource/fonts/fa-solid-900.ttf',
    })
    local faFail   = (faPath == nil)
    local faRanges = (not faFail) and imgui.new.ImWchar[3](0xf000, 0xf8ff, 0) or nil
    M.faRanges = faRanges
    local function mergeIcons(size)
        if faFail then return end
        local ok = pcall(function()
            local fc = imgui.ImFontConfig()
            fc.MergeMode  = true
            fc.PixelSnapH = true
            atlas:AddFontFromFileTTF(faPath, size, fc, faRanges)
        end)
        if not ok then faFail = true end
    end

    -- на телефоне Arial нет: берём что найдётся (шрифт лаунчера, Roboto, Noto)
    local regPath = firstExisting({
        wd .. '/resource/fonts/arial.ttf',
        wd .. '/resource/fonts/regular.ttf',
        wd .. '/lib/EagleSans-Reg.ttf',
        '/system/fonts/Roboto-Regular.ttf',
        '/system/fonts/RobotoStatic-Regular.ttf',
        '/system/fonts/NotoSans-Regular.ttf',
        '/system/fonts/DroidSans.ttf',
    })
    local boldPath = firstExisting({
        wd .. '/resource/fonts/arialbd.ttf',
        wd .. '/resource/fonts/bold.ttf',
        '/system/fonts/Roboto-Bold.ttf',
        '/system/fonts/RobotoStatic-Bold.ttf',
        '/system/fonts/NotoSans-Bold.ttf',
        '/system/fonts/DroidSans-Bold.ttf',
    }) or regPath
    local function addFont(path, size)
        if path then return atlas:AddFontFromFileTTF(path, size, nil, ranges) end
        return atlas:AddFontDefault()
    end
    fontSmall = addFont(regPath, 14)
    mergeIcons(13)
    fontMid   = addFont(boldPath, 18)
    mergeIcons(17)
    fontBig   = addFont(boldPath, 32)
    mergeIcons(28)
    faOk = not faFail

    local st = imgui.GetStyle()
    local V4 = imgui.ImVec4
    st.WindowRounding  = 18
    st.ChildRounding   = 12
    st.FrameRounding   = 9
    st.PopupRounding   = 10
    st.GrabRounding    = 8
    st.ScrollbarRounding = 8
    st.ScrollbarSize   = 22
    st.GrabMinSize     = 26
    st.FrameBorderSize = 0
    st.WindowBorderSize = 0
    st.ChildBorderSize = 0
    st.ItemSpacing     = imgui.ImVec2(8, 8)
    st.FramePadding    = imgui.ImVec2(10, 10)
    local c = st.Colors
    c[imgui.Col.Text]             = V4(0.92, 0.94, 0.98, 1)
    c[imgui.Col.TextDisabled]     = V4(0.45, 0.48, 0.58, 1)
    c[imgui.Col.WindowBg]         = V4(0.05, 0.06, 0.09, 0.97)
    c[imgui.Col.ChildBg]          = V4(0.065, 0.075, 0.11, 1)
    c[imgui.Col.PopupBg]          = V4(0.07, 0.08, 0.12, 0.98)
    c[imgui.Col.Border]           = V4(0.20, 0.23, 0.32, 0.6)
    c[imgui.Col.FrameBg]          = V4(0.11, 0.13, 0.19, 1)
    c[imgui.Col.FrameBgHovered]   = V4(0.15, 0.18, 0.26, 1)
    c[imgui.Col.FrameBgActive]    = V4(0.18, 0.22, 0.32, 1)
    c[imgui.Col.Button]           = V4(0.35, 0.59, 1.0, 0.16)
    c[imgui.Col.ButtonHovered]    = V4(0.35, 0.59, 1.0, 0.30)
    c[imgui.Col.ButtonActive]     = V4(0.35, 0.59, 1.0, 0.45)
    c[imgui.Col.ScrollbarBg]      = V4(0, 0, 0, 0)
    c[imgui.Col.ScrollbarGrab]    = V4(0.25, 0.28, 0.38, 1)
    c[imgui.Col.ScrollbarGrabHovered] = V4(0.32, 0.36, 0.48, 1)
    c[imgui.Col.ScrollbarGrabActive]  = V4(0.38, 0.43, 0.58, 1)
    c[imgui.Col.Separator]        = V4(0.16, 0.18, 0.26, 1)
    c[imgui.Col.TextSelectedBg]   = V4(0.35, 0.59, 1.0, 0.35)
    c[imgui.Col.CheckMark]        = V4(0.18, 0.84, 0.67, 1)
    c[imgui.Col.SliderGrab]       = V4(0.35, 0.59, 1.0, 0.9)
    c[imgui.Col.SliderGrabActive] = V4(0.18, 0.84, 0.67, 1)
end)

-- ===================== МЕНЮ (окно) =====================
imgui.OnFrame(function() return M.open[0] or M.anim > 0 end, function(self)
    self.HideCursor = not M.open[0]
    local dt = tick('menu')
    M.dt   = dt
    M.anim = approach(M.anim, M.open[0] and 1 or 0, 13, dt)
    local e = ease(M.anim)
    M.alpha = e
    if e <= 0.003 then return end

    local sw, sh = getScreenResolution()
    local V = imgui.ImVec2

    -- размер меню: режим (маленькое/стандарт/большое) * шрифт, но не больше экрана
    local mult = ({ 0.75, 1.0, 1.8 })[menuMode] or 1.0
    local L    = math.max(1, fontS)
    local room = math.min(sw * 0.97 / 920, sh * 0.95 / 640)
    local cap  = ({ 0.7, 0.85, 1.0 })[menuMode] or 0.85
    MS = math.min(mult * L, room * cap)
    M.sh = sh
    MENU_W, MENU_H = 920 * MS, 640 * MS
    CUR_S  = 1
    ICON_K = MS
    if not imgui.IsMouseDown(0) and not imgui.IsMouseReleased(0) then M.scrolling = false end

    local bg = (imgui.GetBackgroundDrawList or imgui.GetOverlayDrawList)()
    bg:AddRectFilled(V(0, 0), V(sw, sh), col(0, 0, 0, 0.28 * e))

    if not M.winPos or math.abs((M.winPos.w or 0) - MENU_W) > 0.5 then
        M.winPos = { x = sw / 2 - MENU_W / 2, y = sh / 2 - MENU_H / 2, w = MENU_W }
    end
    imgui.SetNextWindowPos(V(M.winPos.x, M.winPos.y + (1 - e) * Z(30)), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(MENU_W, MENU_H), imgui.Cond.Always)

    local gs0 = beginScale(MS * fontS / L)
    imgui.PushFont(fontSmall)
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, e)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, Z(20))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(Z(14), Z(14)))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V(Z(8), Z(8)))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V(Z(10), Z(10)))
    imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, Z(22))
    imgui.PushStyleVarFloat(imgui.StyleVar.GrabMinSize, Z(26))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.045, 0.05, 0.08, 0.98))

    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
                + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove
    if imgui.Begin('##BarrelSellMenu', nil, flags) then
        M.inMenu = true
        M.draw()
        M.inMenu = false
    end
    imgui.End()

    imgui.PopStyleColor()
    imgui.PopStyleVar(7)
    imgui.PopFont()
    endScale(gs0, fontSmall)
end)

-- ===================== ОКНО ПРОДАЖИ (HUD) =====================
imgui.OnFrame(function() return M.on and (show[0] or M.editable('hud')) end, function(self)
    self.HideCursor = not M.editing()
    local sw, sh = getScreenResolution()
    local S = ovS * math.max(1, fontS)
    local HW, HH = W * S, H * S
    if not pos then
        if cfg.main.x >= 0 and cfg.main.y >= 0 then
            pos = { x = cfg.main.x, y = cfg.main.y }
        else
            pos = { x = sw / 2 - HW / 2, y = sh * 0.08 }
        end
    end
    pos.x = math.max(0, math.min(sw - HW, pos.x))
    pos.y = math.max(0, math.min(sh - HH, pos.y))
    M.rects.hud = { x = pos.x, y = pos.y, w = HW, h = HH, t = os.clock() }

    local left     = windowLeft()
    local inWin    = lastSaleAt ~= 0 and left > 0
    local locked   = sold >= LIMIT and left > 0
    local acc      = locked and RED or (inWin and AMBER or GREEN)

    local now   = os.clock()
    local pulse = 0.5 + 0.5 * math.sin(now * 4)
    local flash = math.max(0, 1 - (now - flashClock) / 0.6)

    imgui.SetNextWindowPos(imgui.ImVec2(pos.x, pos.y), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(HW, HH))

    local gs0 = beginScale(ovS * fontS)
    CUR_S = S; ICON_K = 1

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 18 * S)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.05, 0.06, 0.09, 0.93))

    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
                + imgui.WindowFlags.NoMove + (imgui.WindowFlags.NoInputs or 0)

    if imgui.Begin('##BarrelSell', nil, flags) then
        local V  = imgui.ImVec2
        local p  = imgui.GetWindowPos()
        local dl = scaled(imgui.GetWindowDrawList(), p.x, p.y, S)

        if M.editable('hud') then
            local on = (M.pick == 'hud')
            dl:AddRect(p, V(p.x + W, p.y + H), colT(on and GREEN or BLUE, on and 1 or 0.45), 18, RC_ALL, on and 3 or 1.5)
        else
            dl:AddRect(p, V(p.x + W, p.y + H), colT(acc, 0.28 + 0.5 * flash), 18, RC_ALL, 1.5)
        end

        dl:AddRectFilledMultiColor(V(p.x + 18, p.y + 1), V(p.x + W / 2, p.y + 3),
            colT(acc, 0), colT(acc, 0.9), colT(acc, 0.9), colT(acc, 0))
        dl:AddRectFilledMultiColor(V(p.x + W / 2, p.y + 1), V(p.x + W - 18, p.y + 3),
            colT(acc, 0.9), colT(acc, 0), colT(acc, 0), colT(acc, 0.9))

        local dotR = 4 + ((locked or inWin) and pulse * 1.2 or 0)
        dl:AddCircleFilled(V(p.x + 24, p.y + 24), dotR + 3, colT(acc, 0.18), 16)
        dl:AddCircleFilled(V(p.x + 24, p.y + 24), dotR, colT(acc), 16)

        imgui.PushFont(fontSmall)
        local status, scol
        if M.editable('hud') then status, scol = u8'ПЕРЕМЕЩЕНИЕ', BLUE
        elseif locked then    status, scol = u8'ЛИМИТ', RED
        elseif inWin then     status, scol = u8'ИДЁТ ПРОДАЖА', AMBER
        else                  status, scol = u8'СВОБОДНО', GREEN end
        local st  = tsz(status)
        local hSm = tsz('Ag').y
        local px1 = p.x + W - 18
        local px0 = px1 - st.x - 20
        local title = u8'ПРОДАЖА НЕФТИ'
        if p.x + 38 + tsz(title).x > px0 - 8 then title = u8'НЕФТЬ' end
        dl:AddText(V(p.x + 38, p.y + 24 - hSm / 2), col(150, 156, 178), title)
        dl:AddRectFilled(V(px0, p.y + 24 - hSm / 2 - 3), V(px1, p.y + 24 + hSm / 2 + 3), colT(scol, 0.16), 10)
        dl:AddText(V(px0 + 10, p.y + 24 - hSm / 2), colT(scol), status)
        imgui.PopFont()

        imgui.PushFont(fontBig)
        local soldStr = tostring(sold)
        local ss = tsz(soldStr)
        dl:AddText(V(p.x + 20, p.y + 36), col(255, 255, 255), soldStr)
        local tStr = (inWin or locked) and fmtTime(left) or '--:--'
        local ts = tsz(tStr)
        dl:AddText(V(p.x + W - 20 - ts.x, p.y + 36),
            (inWin or locked) and colT(acc) or col(90, 96, 118), tStr)
        imgui.PopFont()

        imgui.PushFont(fontMid)
        dl:AddText(V(p.x + 24 + ss.x, p.y + 50), col(110, 116, 138), '/' .. LIMIT)
        imgui.PopFont()

        imgui.PushFont(fontSmall)
        local lbl1 = u8'продано бочек'
        local lbl2 = locked and u8'до конца КД' or u8'до сброса лимита'
        if 20 + tsz(lbl1).x + 10 > W - 20 - tsz(lbl2).x then lbl2 = locked and u8'до конца' or u8'до сброса' end
        dl:AddText(V(p.x + 20, p.y + 70), col(110, 116, 138), lbl1)
        dl:AddText(V(p.x + W - 20 - tsz(lbl2).x, p.y + 70), col(110, 116, 138), lbl2)
        imgui.PopFont()

        local x0, x1, y0, y1 = p.x + 20, p.x + W - 20, p.y + 90, p.y + 100
        local bw   = x1 - x0
        local fill = bw * math.min(sold / LIMIT, 1)
        dl:AddRectFilled(V(x0, y0), V(x1, y1), col(30, 34, 48), 5)
        if fill > 1 then
            local r = math.min(5, fill / 2)
            local glowA = 0.14 + 0.10 * ((locked and pulse) or 0) + 0.3 * flash
            dl:AddRectFilled(V(x0 - 2, y0 - 2), V(x0 + fill + 2, y1 + 2), colT(acc, glowA), 7)
            dl:AddRectFilled(V(x0, y0), V(x0 + fill, y1), colT(acc), r)
            if fill > 8 then
                dl:AddRectFilled(V(x0 + 2, y0 + 1), V(x0 + fill - 2, y0 + 4),
                    col(255, 255, 255, 0.22 + 0.3 * flash), 2)
            end
        end
        for i = 1, 4 do
            local tx = x0 + bw * i / 5
            dl:AddRectFilled(V(tx - 1, y0), V(tx + 1, y1), col(5, 6, 9, 0.9))
        end

        local ty0, ty1 = p.y + 105, p.y + 108
        dl:AddRectFilled(V(x0, ty0), V(x1, ty1), col(30, 34, 48), 2)
        if inWin then
            local tf = bw * (left / WINDOW)
            if tf > 1 then
                dl:AddRectFilled(V(x0, ty0), V(x0 + tf, ty1), colT(BLUE), math.min(2, tf / 2))
            end
        end

        imgui.PushFont(fontSmall)
        local money = u8'Выручка  ' .. fmtMoney(earned) .. u8' руб'
        local rest  = u8'Осталось  ' .. math.max(LIMIT - sold, 0)
        if 20 + tsz(money).x + 12 > W - 20 - tsz(rest).x then
            money = u8'Выручка  ' .. fmtMoney(earned)
            if 20 + tsz(money).x + 12 > W - 20 - tsz(rest).x then rest = tostring(math.max(LIMIT - sold, 0)) end
        end
        dl:AddText(V(x0, p.y + 110), col(150, 156, 178), money)
        dl:AddText(V(x1 - tsz(rest).x, p.y + 110), col(150, 156, 178), rest)
        dl:AddText(V(x0, p.y + 128), col(255, 214, 102), 'AZ Coins  ' .. fmtMoney(azTotal))
        local tnAll = trunkTotals()
        local tr = u8'Багажники  ' .. tnAll
        dl:AddText(V(x1 - tsz(tr).x, p.y + 128), colT(tnAll > 0 and BLUE or DIM), tr)
        imgui.PopFont()
    end
    imgui.End()

    imgui.PopStyleColor()
    imgui.PopStyleVar(2)
    endScale(gs0, fontSmall)
end)

-- ===================== КНОПКА МЕНЮ + РАССТАНОВКА =====================
imgui.OnFrame(function() return M.on end, function(self)
    self.HideCursor = not M.editing()
    local V   = imgui.ImVec2
    local dt  = tick('ov')
    local now = os.clock()
    local sw, sh = getScreenResolution()
    local dl0 = (imgui.GetBackgroundDrawList or imgui.GetOverlayDrawList)()
    local S   = ovS * math.max(1, fontS)
    local gs0 = beginScale(ovS * fontS)
    CUR_S = S; ICON_K = 1

    local wantBtn = (mbtnOn or M.editable('btn')) and not M.open[0]
    M.btnA = approach(M.btnA, wantBtn and 1 or 0, 12, dt)
    local btnRect
    if M.btnA > 0 then
        local e  = ease(M.btnA)
        local BS = 52
        local bx, by = M.ovPos('btn', BS * S, BS * S, sw, sh)
        local dl = scaled(dl0, bx, by, S)
        local pr = 0.5 + 0.5 * math.sin(now * 2.5)
        dl:AddCircleFilled(V(bx + BS / 2, by + BS / 2), BS / 2 + 3 * pr, colT(GREEN, 0.10 * e), 28)
        dl:AddCircleFilled(V(bx + BS / 2, by + BS / 2), BS / 2, col(14, 16, 25, 0.90 * e), 28)
        dl:AddCircle(V(bx + BS / 2, by + BS / 2), BS / 2, colT(GREEN, 0.7 * e), 28, 1.5)
        M.drawBarrel(dl, bx + BS / 2, by + BS / 2, 26, GREEN, e)
        M.editFrame(dl, 'btn', bx, by, bx + BS, by + BS, BS / 2, e)
        if wantBtn and e > 0.9 then btnRect = { x = bx, y = by, s = BS * S } end
    end

    local wantSell = (BX.on or M.editable('sell')) and not M.open[0]
    M.sellA = approach(M.sellA, wantSell and 1 or 0, 12, dt)
    local sellRect
    if M.sellA > 0 then
        local e = ease(M.sellA)
        local BS, BH = 52, 70
        local sx, sy = M.ovPos('sell', BS * S, BH * S, sw, sh)
        local dl = scaled(dl0, sx, sy, S)
        local run = BX.tok ~= nil
        local c   = run and RED or (BX.ready() and AMBER or GRAY)
        local pr  = 0.5 + 0.5 * math.sin(now * (run and 6 or 2.5))
        local cx, cy = sx + BS / 2, sy + BS / 2
        dl:AddCircleFilled(V(cx, cy), BS / 2 + 3 * pr, colT(c, (run and 0.22 or 0.10) * e), 28)
        dl:AddCircleFilled(V(cx, cy), BS / 2, col(14, 16, 25, 0.90 * e), 28)
        dl:AddCircle(V(cx, cy), BS / 2, colT(c, 0.8 * e), 28, 1.5)
        M.drawBarrel(dl, cx, cy, 26, c, e)
        imgui.PushFont(fontSmall)
        local label = run and u8'Стоп' or u8'Достать'
        dl:AddText(V(cx - tsz(label).x / 2, sy + BS + 4), colT(c, e), label)
        imgui.PopFont()
        M.editFrame(dl, 'sell', sx, sy, sx + BS, sy + BH, 14, e)
        if wantSell and e > 0.9 then sellRect = { x = sx, y = sy, w = BS * S, h = BH * S } end
    end
    endScale(gs0, fontSmall)

    if btnRect and not M.editing() then
        if M.zone('##oilbtn', btnRect.x, btnRect.y, btnRect.s, btnRect.s) then M.open[0] = true end
    end
    if sellRect and not M.editing() then
        if M.zone('##sellbtn', sellRect.x, sellRect.y, sellRect.w, sellRect.h) then BX.toggle() end
    end
    M.editUI(sw, sh)
end)

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() then saveConfig(); saveTrunks() end
end

-- ===================== ГЛАВНЫЙ ЦИКЛ =====================
local function mainTick()
    processSales()
    if BX.dirty then
        BX.save()
        if BX.ready() and not BX.ann then
            BX.ann = true
            say('{FFFFFF}Пакет инвентаря {00FF00}получен{FFFFFF} - кнопка на экране готова')
        end
    end
    processTrunkAlerts()
    local left = windowLeft()

    if sold >= LIMIT and left > 0 and not wasLocked then
        wasLocked = true
        say('{FF0000}лимит ' .. LIMIT .. ' бочек {FFFFFF}- ждите {c0c0c0}' .. fmtTime(left))
        notifyLimit(left)
    end

    if lastSaleAt ~= 0 and left <= 0 then
        local hadLimit = sold >= LIMIT or wasLocked
        resetWindow()
        saveConfig()
        if hadLimit then
            say('{00FF00}можно продавать снова')
            notifyEnd()
        end
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    if tgBackend then lua_thread.create(tgWorker) end

    sampRegisterChatCommand('oil', function()
        if not M.finishEdit(true) then M.open[0] = not M.open[0] end
    end)

    sampAddChatMessage(toChat('{FF0000}|{FFFF00} BarrelSell {FFFFFF}загружен' .. (M.on and '' or ' {FF0000}(ВЫКЛЮЧЕН)')
        .. '{FFFFFF}. Меню: {c0c0c0}/oil{FFFFFF} или кнопка-бочка. {FF0000}By {00FFFF}Edward'), -1)

    while true do
        wait(100)
        if M.on then mainTick() end
        if dirty and os.clock() - lastChange > 1 then saveConfig() end
        if trunkDirty and os.clock() - trunkChange > 1 then saveTrunks() end
    end
end
