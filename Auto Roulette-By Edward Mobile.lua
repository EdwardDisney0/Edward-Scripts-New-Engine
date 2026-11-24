script_name("Auto Roulette")
script_version("3.0")
script_author("By Edward")

require 'lib.moonloader'
local ffi = require 'ffi'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local events = require 'lib.samp.events'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

-- ===================== КОНСТАНТЫ =====================
local PACKET_CEF   = 220
local SEND_TYPE    = 63     -- клиент -> сервер: клик/событие CEF
local GET_TYPE     = 84     -- сервер -> клиент: JSON
local UI_TYPE      = 62     -- сервер -> клиент: открыть/закрыть интерфейс (iface, флаг 0x80 = открыть)
local IFACE_INV    = 52     -- инвентарь
local IFACE_ROUL   = 76     -- меню рулетки
local MAX_CEF_LEN  = 32767
local EV_SELECT, EV_USE = 2, 3   -- команды 220/63: 2 = выбрать слот, 3 = использовать (как в Box Opener / Auto Upgrade Cards)

local ROULETTES = {
    { name = "Бронзовая рулетка",  item = 8,  model = 5587 },
    { name = "Серебряная рулетка", item = 9,  model = 5588 },
    { name = "Золотая рулетка",    item = 10, model = 5590 },
}

local CONFIG_DIR  = getWorkingDirectory() .. "/config"
local CONFIG_PATH = CONFIG_DIR .. "/auto_roulette.json"

-- ===================== СОСТОЯНИЕ =====================
local cfg   = { on = { false, false, false }, cnt = { 1, 1, 1 }, scale = 100, anim = 0, notify = true }
local state = { running = false, stopping = false, prog = { 0, 0, 0 }, skip = {}, total = 0, cur = 0, virts = 0, msg = "", kind = "info" }
local cef   = { inv = {}, amount = {}, lastData = 0, invOpen = false }
local roul  = { opened = false, closed = false, waiting = false, iface = 76, ready = false, msg = false, slot = 0, takeSent = false, taken = false, money = 0 }
local ui    = {
    main = imgui.new.bool(false),
    cnt  = { imgui.new.int(1), imgui.new.int(1), imgui.new.int(1) },
}
local pending, dirtyAt = nil, nil
local itemMenu = { slot = nil, seq = 0 }   -- ответ меню предмета: 220/84, iface 52, sub 3
local sendFmt, cefSkip, ownSend = nil, nil, false
local SKIP_TRY = { 2, 4, 3, 1, 5, 6 }
local HK = {}
local rate = { t = 0, gap = 0.25 }     -- t: когда сервер последний раз ответил "Нельзя так часто открывать интерфейс"
local RATE_TEXT = "Нельзя так часто"
local RATE_ERR  = "rate"

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function say(text)
    pcall(sampAddChatMessage, "{FF0000}| {FFFFFF}" .. text, -1)
end

local function setMsg(text, kind)
    state.msg, state.kind = text, kind or "info"
end

local function markDirty() dirtyAt = os.clock() end


local function hexOf(t)
    local out = {}
    for i = 1, #t do out[i] = string.format("%02X", t[i]) end
    return table.concat(out, " ")
end

local function fromHex(str)
    local t = {}
    for h in tostring(str or ""):gmatch("%x%x") do t[#t + 1] = tonumber(h, 16) end
    return t
end

-- ===================== КОНФИГ =====================
local function saveConfig()
    if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end
    local f = io.open(CONFIG_PATH, "w")
    if not f then return end
    f:write(string.format('{\n'
        .. '    "on1": %s, "cnt1": %d,\n    "on2": %s, "cnt2": %d,\n    "on3": %s, "cnt3": %d,\n'
        .. '    "scale": %d,\n    "pause": %d,\n    "notify": %s\n}\n',
        tostring(cfg.on[1]), cfg.cnt[1], tostring(cfg.on[2]), cfg.cnt[2], tostring(cfg.on[3]), cfg.cnt[3],
        cfg.scale, cfg.anim, tostring(cfg.notify)))
    f:close()
end

local function loadConfig()
    if doesFileExist(CONFIG_PATH) then
        local f = io.open(CONFIG_PATH, "r")
        if f then
            local text = f:read("*a") or ""
            f:close()
            local ok, data = pcall(decodeJson, text)
            if ok and type(data) == "table" then
                for i = 1, 3 do
                    cfg.on[i]  = data["on" .. i] == true
                    cfg.cnt[i] = clamp(math.floor(tonumber(data["cnt" .. i]) or 1), 1, 9999)
                end
                cfg.scale = clamp(math.floor(tonumber(data.scale) or 100), 50, 100)
                cfg.anim  = clamp(math.floor(tonumber(data.pause) or 0), 0, 20)
                cfg.notify = data.notify ~= false
            end
        end
    end
    for i = 1, 3 do
        ui.cnt[i][0] = cfg.cnt[i]
    end
    saveConfig()
end

-- ===================== ЧТЕНИЕ ПАКЕТОВ =====================
-- Входящий 220/84: [220][84][заголовок skip байт][len int16][encoded int8][данные]
-- Размер заголовка подбирается автоматически и запоминается (cefSkip).
local function readAt(bs, skip)
    raknetBitStreamResetReadPointer(bs)
    raknetBitStreamIgnoreBits(bs, 16 + skip * 8)
    local length  = raknetBitStreamReadInt16(bs)
    local encoded = raknetBitStreamReadInt8(bs)

    if not length or not encoded then return nil end
    if length <= 0 or length > MAX_CEF_LEN then return nil end
    if encoded < 0 or encoded > 8 then return nil end

    local unreadBytes = math.floor(raknetBitStreamGetNumberOfUnreadBits(bs) / 8)
    if unreadBytes <= 0 then return nil end

    local str
    if encoded ~= 0 then
        if unreadBytes < 2 then return nil end
        str = raknetBitStreamDecodeString(bs, length + encoded)
    else
        if unreadBytes < length then return nil end
        str = raknetBitStreamReadString(bs, length)
    end
    if type(str) ~= "string" or #str == 0 then return nil end
    local first = str:match("^%s*(.)")
    if first ~= "{" and first ~= "[" then return nil end
    return str
end

-- Раскладки заголовка 220/84: [220][84][iface int8][sub 8/16/32][len 16/32][enc int8][данные]
-- (как в Box Opener). Рабочая раскладка запоминается.
local RX_LAYOUTS = {
    { sub = 32, len = 32 }, { sub = 8, len = 32 }, { sub = 32, len = 16 },
    { sub = 8, len = 16 },  { sub = 16, len = 16 }, { sub = 16, len = 32 },
}
local rxIdx = 1

local function readN(bs, n)
    if n == 8 then return raknetBitStreamReadInt8(bs)
    elseif n == 16 then return raknetBitStreamReadInt16(bs) end
    return raknetBitStreamReadInt32(bs)
end

local function tryRx(bs, L)
    raknetBitStreamResetReadPointer(bs)
    raknetBitStreamReadInt8(bs)
    raknetBitStreamReadInt8(bs)
    local iface = raknetBitStreamReadInt8(bs)
    local sub   = readN(bs, L.sub)
    local len   = readN(bs, L.len)
    local enc   = raknetBitStreamReadInt8(bs)
    if not len or len <= 0 or len > MAX_CEF_LEN or (enc ~= 0 and enc ~= 1) then return end
    local str
    if enc ~= 0 then str = raknetBitStreamDecodeString(bs, len + 1)
    else str = raknetBitStreamReadString(bs, len) end
    if type(str) ~= "string" or not str:find("^%s*[%[{]") then return end
    return iface, sub, str
end

local function parseMobilePacket(bs)
    local iface, sub, str = tryRx(bs, RX_LAYOUTS[rxIdx])
    if str then return iface, sub, str end
    for i, L in ipairs(RX_LAYOUTS) do
        if i ~= rxIdx then
            iface, sub, str = tryRx(bs, L)
            if str then rxIdx = i return iface, sub, str end
        end
    end
end

local function readCefString(bs)
    raknetBitStreamResetReadPointer(bs)
    if raknetBitStreamGetNumberOfBitsUsed(bs) < 80 then return nil end
    raknetBitStreamIgnoreBits(bs, 8)
    local ptype = raknetBitStreamReadInt8(bs)
    if ptype ~= GET_TYPE then return nil end

    local okm, _, _, mstr = pcall(parseMobilePacket, bs)
    if okm and mstr then return mstr end

    if cefSkip then
        local ok, str = pcall(readAt, bs, cefSkip)
        if ok and str then return str end
    end
    for _, skip in ipairs(SKIP_TRY) do
        local ok, str = pcall(readAt, bs, skip)
        if ok and str then
            cefSkip = skip
            return str
        end
    end
    return nil
end

-- Входящий 220/62: [220][62][iface][флаг]  (флаг 0x80 = открыт, 0 = закрыт)
local function readUi(bs)
    raknetBitStreamResetReadPointer(bs)
    if raknetBitStreamGetNumberOfBitsUsed(bs) < 32 then return nil end
    raknetBitStreamIgnoreBits(bs, 8)
    if raknetBitStreamReadInt8(bs) ~= UI_TYPE then return nil end
    local iface = raknetBitStreamReadInt8(bs) % 256
    local flag  = raknetBitStreamReadInt8(bs) % 256
    return iface, flag
end

local function parseInventory(str)
    for body in str:gmatch("{([^{}]-)}") do
        if body:find('"available"', 1, true) then
            local slot = tonumber(body:match('"slot"%s*:%s*(%d+)'))
            if slot then
                local item = tonumber(body:match('"item"%s*:%s*(%d+)'))
                if item then
                    cef.inv[slot] = item
                    cef.amount[slot] = tonumber(body:match('"amount"%s*:%s*(%d+)')) or cef.amount[slot]
                else
                    cef.inv[slot], cef.amount[slot] = nil, nil
                end
            end
        end
    end
end

function HK.hookReceivePacket(id, bs)
    if id ~= PACKET_CEF then return end

    local iface, flag = readUi(bs)
    if iface then
        local open = flag >= 128
        if iface == IFACE_INV then
            cef.invOpen = open
        else
            if open then
                -- любой интерфейс, открывшийся после "использовать" - это меню рулетки
                if roul.waiting then roul.opened, roul.iface = true, iface end
            elseif roul.opened then
                roul.closed = true
                if roul.takeSent then roul.taken = true end   -- меню закрылось после забора приза
            end
        end
        pcall(raknetBitStreamResetReadPointer, bs)
        return
    end

    -- меню предмета приходит как 220/84, iface 52, sub 3: фиксируем сам факт прихода
    local isMenu = false
    pcall(function()
        raknetBitStreamResetReadPointer(bs)
        raknetBitStreamIgnoreBits(bs, 8)
        if raknetBitStreamReadInt8(bs) ~= GET_TYPE then return end
        local a = raknetBitStreamReadInt8(bs) % 256
        local b = raknetBitStreamReadInt8(bs) % 256
        if a == IFACE_INV and b == 3 then
            itemMenu.seq = itemMenu.seq + 1
            isMenu = true
        end
    end)

    local ok, str = pcall(readCefString, bs)
    pcall(raknetBitStreamResetReadPointer, bs)
    if not ok or type(str) ~= "string" then return end

    if isMenu then itemMenu.slot = tonumber(str:match('"slot":(%d+)')) end

    if str:find(RATE_TEXT, 1, true) or str:find(u8(RATE_TEXT), 1, true) then rate.t = os.clock() end

    -- список призов рулетки (sysName = crate) тоже означает, что меню открылось
    if roul.waiting and str:find('"sysName":"crate"', 1, true) then roul.opened, roul.ready = true, true end

    if str:find('"type":1,"items"', 1, true) then
        if str:find('"max_slot"', 1, true) then
            if str:find('{"slot":0,', 1, true) then cef.inv, cef.amount = {}, {} end
            pcall(parseInventory, str)
            cef.lastData = os.clock()
        else
            pcall(parseInventory, str)   -- одиночное обновление слота
            -- приз пришёл в другой слот (слот самой рулетки обновляется при прокрутке)
            if roul.takeSent then
                for sl in str:gmatch('"slot"%s*:%s*(%d+)') do
                    if tonumber(sl) ~= roul.slot then roul.taken = true end
                end
            end
        end
    end
end

-- ===================== ОТПРАВКА ПАКЕТОВ =====================
local function sendBitStream(bs)
    local send = raknetSendBitStreamEx or raknetSendBitStream
    ownSend = true
    local ok = pcall(send, bs, 1, 7, 0)
    ownSend = false
    return ok
end

-- 220/63 (клиент -> сервер): [220][63][iface int8][-1 int32][cmd int32][len int16][json]
local function sendCEF(cmd, payload)
    pcall(function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, PACKET_CEF)
        raknetBitStreamWriteInt8(bs, SEND_TYPE)
        raknetBitStreamWriteInt8(bs, IFACE_INV)
        raknetBitStreamWriteInt32(bs, -1)
        raknetBitStreamWriteInt32(bs, cmd)
        raknetBitStreamWriteInt16(bs, #payload)
        raknetBitStreamWriteString(bs, payload)
        sendBitStream(bs)
        raknetDeleteBitStream(bs)
    end)
end

local function cefSelect(slot)
    sendCEF(EV_SELECT, string.format('{"slot":%d,"type":1}', slot))
end

local function cefUse(slot)
    sendCEF(EV_USE, string.format('{"action":1,"id":0,"slot":%d,"type":1}', slot))
end

-- выбрать слот -> дождаться ответа меню предмета (220/84, iface 52, sub 3) -> "Использовать"
-- (настоящий клиент нажимает "Использовать" через ~0.4-0.5 с после выбора). Вызывать только из потока.
local function cefUseItem(slot)
    itemMenu.slot = nil
    local seq0 = itemMenu.seq
    cefSelect(slot)
    local t0 = os.clock()
    while itemMenu.slot ~= slot and itemMenu.seq == seq0 and os.clock() - t0 < 1.0 do wait(0) end
    wait(150)
    cefUse(slot)
end

-- Кнопки меню рулетки: [220][63][76][int32 0][int32 N][int16 0]
-- N = 0 - запустить прокрутку, 1 и 2 - забрать приз / закрыть (как в дампе)
local function sendRoul(n)
    pcall(function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, PACKET_CEF)
        raknetBitStreamWriteInt8(bs, SEND_TYPE)
        raknetBitStreamWriteInt8(bs, roul.iface)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteInt32(bs, n)
        raknetBitStreamWriteInt16(bs, 0)
        sendBitStream(bs)
        raknetDeleteBitStream(bs)
    end)
end

-- ===================== ИСХОДЯЩИЕ ПАКЕТЫ =====================
-- клиент шлёт 220/66: iface + флаг (бит 0x8000 = окно открыто)
local function readRaw(bs)
    local count = math.floor(raknetBitStreamGetNumberOfBitsUsed(bs) / 8)
    if count < 2 or count > 700 then return nil end
    raknetBitStreamResetReadPointer(bs)
    local raw = {}
    for i = 1, count do raw[i] = raknetBitStreamReadInt8(bs) % 256 end
    raknetBitStreamResetReadPointer(bs)
    return raw
end

function HK.hookSendPacket(id, bs)
    if id ~= PACKET_CEF or ownSend then return end
    local ok, raw = pcall(readRaw, bs)
    if not ok or not raw or #raw < 4 then return end
    if raw[2] == 66 then
        local value = raw[3] + raw[4] * 256
        if bit.band(value, 0x7FFF) == IFACE_INV then
            cef.invOpen = bit.band(value, 0x8000) ~= 0
        end
    end
end

do
    local function reg(event, fn)
        local ok = pcall(function()
            local R = require("RakLua")
            R.registerHandler(RakLuaEvents[event], fn)
        end)
        if ok then return "RakLua" end
        local name = ({ OUTGOING_PACKET = "onSendPacket", INCOMING_PACKET = "onReceivePacket" })[event]
        if name and pcall(addEventHandler, name, fn) then return "addEventHandler" end
        return nil
    end
    reg("INCOMING_PACKET", function(id, bs) pcall(HK.hookReceivePacket, id, bs) end)
    reg("OUTGOING_PACKET", function(id, bs) pcall(HK.hookSendPacket, id, bs) end)
end

-- ===================== СТАТИСТИКА =====================
local STATS_PATH = CONFIG_DIR .. "/auto_roulette_stats.txt"
local stats = {}
local lastRun = { n = 0, t = 0, v = 0 }   -- последний запуск целиком: сколько открыто и за сколько секунд
for i = 1, 3 do stats[i] = { opened = 0, time = 0, lastN = 0, lastT = 0, prizes = {} } end
local function cntText(n) return (n >= 9999) and "все" or tostring(n) end
local statsDirty = nil
local function markStatsDirty() statsDirty = os.clock() end

local function fmtNum(n)
    n = tonumber(n) or 0
    if math.abs(n - math.floor(n + 0.5)) < 0.005 then
        local s = string.format("%.0f", n)
        local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
        out = out:gsub("^ ", "")
        return out
    end
    return string.format("%.2f", n)
end

local function fmtTime(sec)
    sec = math.floor((tonumber(sec) or 0) + 0.5)
    local h, m, s = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%dч %02dм %02dс", h, m, s) end
    if m > 0 then return string.format("%dм %02dс", m, s) end
    return string.format("%dс", s)
end

local function fmtDur(sec)
    sec = math.floor((tonumber(sec) or 0) + 0.5)
    local h, m, s2 = math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60
    if h > 0 then return string.format("%d ч %02d мин %02d сек", h, m, s2) end
    if m > 0 then return string.format("%d мин %02d сек", m, s2) end
    return string.format("%d сек", s2)
end

local function saveStats()
    if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end
    local f = io.open(STATS_PATH, "w")
    if not f then return end
    for i = 1, 3 do
        local S = stats[i]
        f:write(string.format("R\t%d\t%d\t%.3f\t%d\t%.3f\n", i, S.opened, S.time, S.lastN, S.lastT))
        for _, p in pairs(S.prizes) do
            f:write(string.format("P\t%d\t%d\t%.4f\t%s\t%s\n", i, p.count, p.sum, p.kind, p.name))
        end
    end
    f:write(string.format("L\t%d\t%.3f\t%d\n", lastRun.n, lastRun.t, lastRun.v))
    f:close()
end

local function loadStats()
    if not doesFileExist(STATS_PATH) then return end
    local f = io.open(STATS_PATH, "r")
    if not f then return end
    for line in f:lines() do
        line = line:gsub("\r", "")
        local i, opened, tm, ln, lt = line:match("^R\t(%d+)\t(%d+)\t([%d%.]+)\t(%d+)\t([%d%.]+)$")
        if i and stats[tonumber(i)] then
            local S = stats[tonumber(i)]
            S.opened, S.time, S.lastN, S.lastT = tonumber(opened), tonumber(tm), tonumber(ln), tonumber(lt)
        else
            local pi, cnt, sum, kind, name = line:match("^P\t(%d+)\t(%d+)\t([%-%d%.eE%+]+)\t(%a+)\t(.+)$")
            if pi and stats[tonumber(pi)] then
                if kind == "inv" then   -- старые записи "msg" (всё подряд из чата) отбрасываем
                    stats[tonumber(pi)].prizes[kind .. ":" .. name] =
                        { count = tonumber(cnt), sum = tonumber(sum) or 0, kind = kind, name = name }
                end
            else
                local ln, lt, lv = line:match("^L\t(%d+)\t([%d%.]+)\t?(%d*)$")
                if ln then lastRun.n, lastRun.t, lastRun.v = tonumber(ln), tonumber(lt), tonumber(lv) or 0 end
            end
        end
    end
    f:close()
end

local function parseNum(tok)
    tok = tok:gsub("[%.,]+$", "")
    if tok:match("^%d+([%.,]%d%d%d)+$") then
        return tonumber((tok:gsub("[%.,]", "")))
    elseif tok:find("[%.,]") then
        return tonumber((tok:gsub(",", ".")))
    end
    return tonumber(tok)
end

-- "Бронзовый сундук (x2)" -> "Бронзовый сундук", 2
local QTY_PATTERNS = {
    "%s*%(?[xXхХ]%s*(%d+)%s*%)?%s*$",
    "%s*%((%d+)%s*шт%.?%)%s*$",
    "%s*(%d+)%s*шт%.?%s*$",
    "%s*%((%d+)%)%s*$",
}
local function stripQty(name)
    for _, p in ipairs(QTY_PATTERNS) do
        local q = name:match(p)
        if q then return (name:gsub(p, "")), tonumber(q) end
    end
    return name, 1
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Разбор строго сообщения "Добавлено в инвентарь: ..." -> название, количество
local function parseMessage(text)
    text = trim((text:gsub("{%x%x%x%x%x%x}", "")))
    local inv = text:match("Добавлено в инвентарь%s*:?%s*(.+)$")
    if not inv then return nil end
    inv = inv:gsub("[%.!%s]+$", "")
    local name, qty = stripQty(inv)
    name = trim(name)
    if name == "" then return nil end
    return "inv", name, qty
end

local function addPrize(ri, kind, name, qty)
    local key = kind .. ":" .. name
    local S = stats[ri]
    local p = S.prizes[key]
    if not p then
        p = { count = 0, sum = 0, kind = kind, name = name }
        S.prizes[key] = p
    end
    p.count = p.count + 1
    p.sum = p.sum + (qty or 1)
end

-- Сообщения чата собираются только пока идёт открытие рулетки (и 1.5 сек после неё)
local cap = { idx = nil, open = false, committed = false, untilT = 0, buf = {} }

local function capReset(ri)
    cap.idx, cap.open, cap.committed, cap.untilT, cap.buf = ri, false, false, 0, {}
end

local function capCommit()
    if not cap.idx then return end
    for _, e in ipairs(cap.buf) do addPrize(cap.idx, e[1], e[2], e[3]) end
    cap.buf, cap.committed, cap.open, cap.untilT = {}, true, false, os.clock() + 1.5
    markStatsDirty()
end

local function capDiscard()
    cap.buf, cap.open, cap.committed, cap.untilT = {}, false, false, 0
end

local function capFeed(text)
    if not cap.idx then return end
    -- проверка: берём ТОЛЬКО сообщения "Добавлено в инвентарь", остальной чат игнорируем
    if not text:gsub("{%x%x%x%x%x%x}", ""):find("Добавлено в инвентарь", 1, true) then return end
    local active = cap.open or (cap.committed and os.clock() < cap.untilT)
    if not active then return end
    local kind, name, qty = parseMessage(text)
    if not kind then return end
    if cap.committed then
        addPrize(cap.idx, kind, name, qty)
        markStatsDirty()
    else
        cap.buf[#cap.buf + 1] = { kind, name, qty }
    end
end

local function resetStats()
    for i = 1, 3 do stats[i] = { opened = 0, time = 0, lastN = 0, lastT = 0, prizes = {} } end
    lastRun.n, lastRun.t, lastRun.v = 0, 0, 0
    markStatsDirty()
end

-- сообщение сервера: приз + пометка "забрано"
function events.onServerMessage(color, text)
    if type(text) ~= "string" then return end
    if roul.takeSent and text:gsub("{%x%x%x%x%x%x}", ""):find("Добавлено в инвентарь", 1, true) then
        roul.taken, roul.msg = true, true
    end
    pcall(capFeed, text)
end

-- приз-деньги: в чате текста нет, приходит только RPC изменения денег
local moneyBase = nil

local function moneyReceived(delta)
    if delta <= 0 or not roul.takeSent or not cap.idx then return end
    if cap.open then
        roul.money = roul.money + delta
        state.virts = state.virts + delta
        roul.taken = true
        cap.buf[#cap.buf + 1] = { "inv", "Деньги", delta }
    elseif cap.committed and os.clock() < cap.untilT then
        roul.money = roul.money + delta
        state.virts = state.virts + delta
        addPrize(cap.idx, "inv", "Деньги", delta)
        markStatsDirty()
    end
end

function events.onGivePlayerMoney(money)
    if type(money) ~= "number" then return end
    if moneyBase then moneyBase = moneyBase + money end
    pcall(moneyReceived, money)
end

function events.onSetPlayerMoney(money)
    if type(money) ~= "number" then return end
    local base = moneyBase
    moneyBase = money
    if base and money > base then pcall(moneyReceived, money - base) end
end

-- ===================== ЛОГИКА =====================
local function chat(cmd) pcall(sampSendChat, cmd) end

local function dialogActive()
    local ok, active = pcall(sampIsDialogActive)
    return ok and active
end

local function waitDialogClosed()
    local t = os.clock()
    while dialogActive() do
        if os.clock() - t > 5 then return end
        wait(10)
    end
end

local function waitFor(check, timeout, ignoreStop)
    local t = os.clock()
    while os.clock() - t < timeout do
        if check() then return true end
        if not ignoreStop and state.stopping then return false end
        wait(0)
    end
    return false
end

local function finish(text, kind)
    state.elapsed = state.runStart and (os.clock() - state.runStart) or 0
    if state.total > 0 then lastRun.n, lastRun.t, lastRun.v = state.total, state.elapsed, state.virts end
    if state.virts > 0 then text = text .. string.format(". Получено виртов: %s", fmtNum(state.virts)) end
    state.running, state.stopping, state.cur = false, false, 0
    pcall(saveStats)
    setMsg(text, kind or "info")
    if cfg.notify then say(text) end
    saveConfig()
end

local function slowDown()
    rate.gap = math.min(rate.gap + 0.15, 1.2)
end

-- /invent -> ждём все куски инвентаря (пакеты 220/84 с "max_slot")
local function openInventory(strict)
    waitDialogClosed()
    for attempt = 1, 6 do
        if state.stopping then return false end
        if attempt > 1 then setMsg("Открываю инвентарь, попытка " .. attempt .. "...", "info") end
        if cef.invOpen then
            chat("/invent")
            waitFor(function() return not cef.invOpen end, 1.5, true)
            wait(150)
        end
        cef.lastData = 0
        local tReq = os.clock()
        chat("/invent")
        if waitFor(function() return cef.lastData > 0 or rate.t >= tReq end, 3.0) then
            if cef.lastData > 0 then
                waitFor(function() return os.clock() - cef.lastData > 0.2 end, 2.0, true)
                return true
            end
            -- "Нельзя так часто открывать интерфейс" - подождать и повторить
            slowDown()
            waitFor(function() return false end, 1.2)
        end
        if state.stopping then return false end
    end
    if not strict and next(cef.inv) ~= nil then
        say("Инвентарь не прислал данные заново - использую последние известные")
        return true
    end
    return false
end

local function findSlot(item)

    local best
    for slot, it in pairs(cef.inv) do
        if it == item and (not best or slot < best) then best = slot end
    end
    return best
end

-- одна рулетка: выбрать -> использовать -> (меню) запустить -> забрать приз -> сразу выйти
local function openOne(slot, ri)
    capReset(ri)
    roul.opened, roul.closed, roul.ready, roul.msg, roul.money = false, false, false, false, 0
    roul.taken, roul.takeSent, roul.slot = false, false, slot
    setMsg(string.format("%s: открываю (слот %d)", ROULETTES[ri].name, slot), "info")
    for attempt = 1, 2 do
        local tReq = os.clock()
        roul.waiting = true
        cefUseItem(slot)
        waitFor(function() return roul.opened or rate.t >= tReq end, 4.0, true)
        if roul.opened then break end
        roul.waiting = false
        if rate.t >= tReq then return false, RATE_ERR end
        if attempt == 2 then return false, "Меню рулетки не открылось" end
        wait(500)
    end
    roul.waiting = false
    waitFor(function() return roul.ready end, 1.0, true)   -- список призов пришёл - меню готово
    wait(150)
    cap.open = true                              -- с этого момента пишем сообщения чата
    sendRoul(0)                                  -- запустить прокрутку
    wait(math.floor(cfg.anim * 1000))            -- пауза (по умолчанию 0 - сразу)
    roul.takeSent = true
    local t0 = os.clock()
    while os.clock() - t0 < 14 do
        sendRoul(1)
        sendRoul(2)
        if waitFor(function() return roul.taken end, 1.5, true) then
            -- дожидаемся закрытия меню, иначе следующий /invent не сработает
            if not waitFor(function() return roul.closed end, 0.6, true) then
                sendRoul(2)
                waitFor(function() return roul.closed end, 1.0, true)
            end
            -- сообщение о призе должно успеть записаться в статистику до следующего подхода
            if not roul.msg and roul.money == 0 then
                waitFor(function() return roul.msg or roul.money > 0 end, 0.3, true)
            end
            return true
        end
    end
    return false, "Приз не подтверждён"
end

-- рулетки этого типа в инвентаре больше нет (игрок потратил) - пропускаем и идём дальше
local function outOfStock(ri, r)
    state.skip[ri] = true
    local msg
    if cfg.cnt[ri] >= 9999 then
        msg = string.format("%s: больше нет в инвентаре (открыто %d)", r.name, state.prog[ri])
    else
        msg = string.format("%s: закончились (открыто %d из %d), иду дальше", r.name, state.prog[ri], cfg.cnt[ri])
    end
    if cfg.notify then say(msg) end
    setMsg(msg, "info")
end

local function worker()
    state.runStart, state.elapsed = os.clock(), 0
    for ri, r in ipairs(ROULETTES) do
        if cfg.on[ri] then
            state.cur = ri
            local target = cfg.cnt[ri]
            local S = stats[ri]
            S.lastN, S.lastT = 0, 0
            while state.prog[ri] < target do
                if state.stopping then return finish("Остановлено вручную", "info") end
                setMsg(string.format("%s: %d / %s", r.name, state.prog[ri], cntText(target))
                    .. (state.virts > 0 and string.format("  |  Вирты: +%s", fmtNum(state.virts)) or ""), "info")

                local t0 = os.clock()
                if not openInventory() then
                    if state.stopping then return finish("Остановлено вручную", "info") end
                    return finish("Не удалось открыть инвентарь", "error")
                end

                local slot = findSlot(r.item)
                if not slot then
                    outOfStock(ri, r)
                    break
                end

                local ok, err = openOne(slot, ri)
                if not ok and err == RATE_ERR then
                    -- сервер ответил "Нельзя так часто открывать интерфейс": пауза и весь подход заново
                    capDiscard()
                    slowDown()
                    waitFor(function() return false end, 1.2)
                elseif not ok then
                    capDiscard()
                    -- возможно, рулетки просто закончились - перепроверяем свежий инвентарь
                    local still = false
                    if not state.stopping and openInventory(true) then still = findSlot(r.item) ~= nil end
                    if not still then
                        if state.stopping then return finish("Остановлено вручную", "info") end
                        outOfStock(ri, r)
                        break
                    end
                    return finish(err, "error")
                end
                if ok then
                    capCommit()
                    local dt = os.clock() - t0
                    S.opened, S.time = S.opened + 1, S.time + dt
                    S.lastN, S.lastT = S.lastN + 1, S.lastT + dt
                    state.prog[ri] = state.prog[ri] + 1
                    state.total = state.total + 1
                    markStatsDirty()
                    waitFor(function() return false end, rate.gap)   -- небольшая пауза между подходами
                end
            end
        end
    end
    local lost = {}
    for ri, r in ipairs(ROULETTES) do
        if state.skip[ri] then lost[#lost + 1] = string.format("%s (%d)", r.name, state.prog[ri]) end
    end
    local text = string.format("Готово! Открыто: %d за %s", state.total, fmtDur(os.clock() - state.runStart))
    if #lost > 0 then text = text .. ". Закончились: " .. table.concat(lost, ", ") end
    return finish(text, "success")
end

local function startScript()
    if state.running then return end
    if not isSampAvailable() then return end
    local any = false
    for i = 1, 3 do if cfg.on[i] then any = true end end
    if not any then
        setMsg("Отметьте хотя бы одну рулетку", "error")
        return
    end
    state.prog = { 0, 0, 0 }
    state.virts = 0
    rate.gap = 0.25
    state.skip = {}
    state.total, state.cur, state.stopping = 0, 0, false
    state.running = true
    setMsg("Запуск...", "info")
    lua_thread.create(function()
        local ok = pcall(worker)
        if not ok and state.running then finish("Внутренняя ошибка, запустите заново", "error") end
    end)
end

local function requestStop()
    if not state.running or state.stopping then return end
    state.stopping = true
    setMsg("Остановка после текущей рулетки...", "info")
end

-- ===================== МЕНЮ =====================
local function V2(x, y) return imgui.ImVec2(x, y) end
local function V4(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end

local C = {
    bg     = V4(0.05, 0.055, 0.08),
    card   = V4(0.11, 0.12, 0.17),
    card2  = V4(0.18, 0.19, 0.26),
    accent = V4(0.20, 0.60, 1.00),
    good   = V4(0.20, 0.80, 0.40),
    bad    = V4(0.92, 0.25, 0.25),
    warn   = V4(0.98, 0.78, 0.25),
    text   = V4(0.96, 0.97, 1.00),
    dim    = V4(0.58, 0.60, 0.70),
    clear  = V4(0, 0, 0, 0),
}
-- цвета рулеток: бронза / серебро / золото
local RC = { V4(0.86, 0.54, 0.24), V4(0.80, 0.84, 0.92), V4(1.00, 0.82, 0.25) }

local loadIcons

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    if loadIcons then pcall(loadIcons) end

    local st = imgui.GetStyle()
    st.WindowRounding, st.FrameRounding, st.GrabRounding = 16, 12, 12
    st.ScrollbarSize, st.WindowBorderSize = 18, 0
    st.Colors[imgui.Col.WindowBg]        = C.bg
    st.Colors[imgui.Col.ChildBg]         = C.clear
    st.Colors[imgui.Col.Text]            = C.text
    st.Colors[imgui.Col.FrameBg]         = C.card2
    st.Colors[imgui.Col.FrameBgHovered]  = C.card2
    st.Colors[imgui.Col.FrameBgActive]   = C.card2
    st.Colors[imgui.Col.CheckMark]       = C.good
    st.Colors[imgui.Col.SliderGrab]      = C.accent
    st.Colors[imgui.Col.SliderGrabActive] = C.accent
    st.Colors[imgui.Col.Button]          = C.card2
    st.Colors[imgui.Col.ButtonHovered]   = C.card2
    st.Colors[imgui.Col.ButtonActive]    = C.accent
    st.Colors[imgui.Col.Header]          = C.card
    st.Colors[imgui.Col.HeaderHovered]   = C.card
    st.Colors[imgui.Col.HeaderActive]    = C.card2
    st.Colors[imgui.Col.Separator]       = C.card2

    local ranges = io.Fonts:GetGlyphRangesCyrillic()
    local wd = getWorkingDirectory()
    local files = {
        wd .. "/resource/fonts/trebucbd.ttf", wd .. "/resource/fonts/arial.ttf",
        "/system/fonts/Roboto-Regular.ttf", "/system/fonts/Roboto[wdth,wght].ttf",
        "/system/fonts/NotoSans-Regular.ttf", "/system/fonts/DroidSans.ttf",
    }
    for _, path in ipairs(files) do
        if doesFileExist(path) then
            local ok, f = pcall(function() return io.Fonts:AddFontFromFileTTF(path, 30.0, nil, ranges) end)
            if ok and f then return end
        end
    end
end)

-- ---------- прокрутка пальцем ----------
-- Листать можно за любое место списка (в том числе за кнопки): если палец сдвинулся
-- больше порога, нажатия на кнопки в этот жест игнорируются.
local drag = { active = false, moved = false, inputActive = false, sy = 0, ly = 0, vel = 0 }
local view = { tab = 1, confirm = 0, open = { false, false, false }, edit = nil, editFresh = false, editSeen = false }

local function dragScroll(s)
    local mp = imgui.GetIO().MousePos
    if imgui.IsMouseClicked(0) and imgui.IsWindowHovered() and not drag.inputActive then
        drag.active, drag.sy, drag.ly, drag.vel = true, mp.y, mp.y, 0
    end
    if drag.active then
        if imgui.IsMouseDown(0) then
            if not drag.moved and math.abs(mp.y - drag.sy) > 14 * s then
                drag.moved, drag.ly = true, mp.y
            end
            if drag.moved then
                local dy = mp.y - drag.ly
                imgui.SetScrollY(imgui.GetScrollY() - dy)
                drag.vel, drag.ly = dy, mp.y
            end
        else
            drag.active = false
        end
    elseif math.abs(drag.vel) > 0.5 then
        imgui.SetScrollY(imgui.GetScrollY() - drag.vel)   -- инерция
        drag.vel = drag.vel * 0.92
    else
        drag.vel = 0
    end
end

-- ---------- отрисовка (дизайн по макету) ----------
view.hold = view.hold or {}

local DW, DH = 1085, 600     -- размер окна в "дизайн-единицах"
local S = 1                  -- текущий масштаб
local OX, OY = 0, 0          -- начало координат текущей области (экран)
local dl                     -- DrawList текущего окна

local K = {
    bg    = V4(0.030, 0.045, 0.080), panel = V4(0.055, 0.075, 0.120), panel2 = V4(0.085, 0.110, 0.170),
    line  = V4(0.16, 0.24, 0.40),    blue  = V4(0.10, 0.48, 1.00),    cyan   = V4(0.20, 0.78, 1.00),
    text  = V4(0.96, 0.97, 1.00),    dim   = V4(0.55, 0.63, 0.76),    good   = V4(0.25, 0.85, 0.50),
    bad   = V4(0.95, 0.30, 0.35),    warn  = V4(0.98, 0.78, 0.25),    white  = V4(1, 1, 1),
}
local RCOL   = { V4(0.93, 0.50, 0.25), V4(0.66, 0.76, 0.96), V4(1.00, 0.78, 0.20) }
local RDESC  = { "Награды: обычные призы", "Награды: ценные призы", "Награды: редкие и уникальные призы" }
local RSHORT = { "Бронзовые", "Серебряные", "Золотые" }

local colFn = imgui.GetColorU32Vec4 or imgui.ColorConvertFloat4ToU32
local function U(c, a) return colFn(V4(c.x, c.y, c.z, a or c.w)) end
local function P(x, y) return V2(OX + x * S, OY + y * S) end

-- кэш перекодировки строк в UTF-8 (чтобы не гонять u8 каждый кадр)
local u8cache, u8count = {}, 0
local function U8(str)
    local v = u8cache[str]
    if v then return v end
    v = u8(str)
    if u8count > 600 then u8cache, u8count = {}, 0 end
    u8cache[str], u8count = v, u8count + 1
    return v
end

local function fill(x, y, w, h, c, r, a)
    dl:AddRectFilled(P(x, y), P(x + w, y + h), U(c, a), (r or 0) * S)
end
local function frame(x, y, w, h, c, r, a)
    dl:AddRect(P(x, y), P(x + w, y + h), U(c, a), (r or 0) * S)
end
local function line(x1, y1, x2, y2, c, th, a)
    dl:AddLine(P(x1, y1), P(x2, y2), U(c, a), (th or 1) * S)
end
local function disc(x, y, r, c, a)
    dl:AddCircleFilled(P(x, y), r * S, U(c, a), 32)
end
local function ring(x, y, r, c, th, a)
    dl:AddCircle(P(x, y), r * S, U(c, a), 32, (th or 1) * S)
end

local function setPx(px) pcall(imgui.SetWindowFontScale, px * S / 30) end
local function tw(str, px)
    setPx(px)
    return imgui.CalcTextSize(U8(str)).x / S
end
-- ax: 0 слева, 0.5 по центру, 1 справа; ay: 0 сверху, 0.5 по центру
local function T(x, y, str, c, px, ax, a, ay)
    setPx(px)
    local s = U8(str)
    local sz = imgui.CalcTextSize(s)
    if ax and ax ~= 0 then x = x - sz.x / S * ax end
    if ay and ay ~= 0 then y = y - sz.y / S * ay end
    dl:AddText(P(x, y), U(c, a), s)
end

local wrapCache, wrapCount = {}, 0
local function wrapLines(str, px, maxW, maxLines)
    local key = px .. "|" .. maxW .. "|" .. (maxLines or 0) .. "|" .. str
    if wrapCache[key] then return wrapCache[key] end
    local lines, cur = {}, ""
    for word in str:gmatch("%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if cur ~= "" and tw(try, px) > maxW then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if maxLines and #lines > maxLines then
        local cut = {}
        for k = 1, maxLines do cut[k] = lines[k] end
        cut[maxLines] = cut[maxLines] .. "..."
        lines = cut
    end
    if wrapCount > 200 then wrapCache, wrapCount = {}, 0 end
    wrapCache[key], wrapCount = lines, wrapCount + 1
    return lines
end

local function hit(id, x, y, w, h)
    imgui.SetCursorScreenPos(P(x, y))
    local clicked = imgui.InvisibleButton(id, V2(w * S, h * S))
    return clicked and not drag.moved, imgui.IsItemHovered(), imgui.IsItemActive()
end

local function clipBegin(x, y, w, h) dl:PushClipRect(P(x, y), P(x + w, y + h), true) end
local function clipEnd() dl:PopClipRect() end

-- ---------- иконки рулеток ----------
local ICON_B64 = {
[[
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
]],
[[
iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAMAAABlApw1AAACf1BMVEWbn50fIh4eHR9XYWVymqSSqK6XnJheYmROVV1XXmRibJqYp64ZGBMmIx51k567wb7Z
2t1WFBt4i5fQ1NcAAP8PcA8A//9qdYN2iJOAbW6Qh3u1xcfW5ebh4eBOTD1SboO4uHHAv8EtTF9BPDNBPi9AOy5/H39KRTuvf3+06en//wBgUj9reYFwgX2G
f4OSkH+qvcWxvcS00Mj/AAAAAAAGBAMYFRArJBs6MyowKiW2tbKrqqd2dnNpaWaWlZFDOi7W1tTIyMeLiYZXVVHn5+cjHBVMSUdNRTiLhHrMxLitpZnEua+k
mo9sZFqFenH19PJkWU/+/v52ho9RZXCYpKqLm6VMWma7w8YzVWlseoR+fn80NkW0vME2R1Lo49rj29Pc4uMxLUF5kptVVFRdYF1FOUjY3eD8+/z6+/s6OjdZ
d4h9gH0rTGM5Ny73+Pg5Niw6Niuqqqo4NS03NCz39/g5Ni0XFRBtXGJ4kqEqJSM9QD5/fwCVl5j19fUNCwkpKCYtKyZVVQBdUD1/f/8NCwYvKiY7YnaFmq2h
jonArqbZ4N4OCwUYFhIXFRAdOUp/AACcoJ2Po6v09fUVFBEtKiZ///+Im6uRpqy8vb/Q09IOCwcVFQ4XFRAYFyQlIxw8UVwAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADa4TlFAAAAoHRSTlOfE+jmFyVnHKReDehWpOP5awlkoQEOAVuf/5rV
E9Mi/wP/4mOb3gNoBgUB/4JL//+jya4BAP7+/v7+/v7+/v7+/v7+//7+/v7+/v/+//7//P4E/v7+/f3+/v4C//7//v/+//wD/v//LVAM/v7/MGxvzgNPjZCt
0P/+Mf8CCa4uDtAD/wKvU/9P////bEqT/wL/z9NymQIzSwjNlC2y/23+O2WqlgAAHS9JREFUeNrtnYl7HMWVwCWf8cEVCIQQQpLNZpPsvTvTd1d3V6nPmR6N
ZkaSJVu2YguBDy4TjG0IGMIRG1ggnAnXv7rvVVUfc7ck2yHfNw8kz4xaPe9X76j3qrpHc7V/cJmbAcwAZgAzgBnADGAGMAOYAcwAZgAzgBnADGAGMAOYAcwA
9iRL6+t/+tP6wNN1/H7gM/7o4Yce/p4CLH355dLSUv7stwfn5yccfe78+fXDh9d/vX703DnAWnro7wgAo/wCiHhy9OiBA+++e2hu7uOPP37srw8++yU8PXTo
XZDPP//84MHPjx44evCnSyPPs34ORPAA0dLDD91JgCXQ+rP19XPrpZfuv//+ubm5Y8vLvWVCyNmzyz3DMD7uXMUXer3l5eWznc7a/l/u/4GUIyiPHDkMsn5g
fWnSm9UeWlr/7E+ffXYA3ndpTwBLMNhHP1sqnWTppwe/gAGfm7vPME4ZXLxVD2UVnvZW4WtZCCGUdoBBimWjrHDZjyKw/u2RIz9894svwFoHQA4eFcYp6/Db
pV0BLK0feOGF4kQ4bv9+5MgX//PYai5SfxQTvk6dWj11ij/K0YCMH2eicCb8hlgcrCOESOLle++999jHcw/eDxoDyxdfHDoo3G+pMsDD6I7lFw68ehDG5tkH
H/zrYwYMrnEffDNNoZDQ0AXxVjmEKV82+wRoVlelgfLD8ke9HndAFM7Qw6P/G0JqGd2wd6z38X89uzRMMDdm0LNHr4JBf/jDH88dO8ZP3TPgP3gzdBfpL6j1
aqYOenyvV1JZDD5qXZD1egRNAN96+UHeL/hRp05xOKSBo+AQdL4L+7tcLnQee7r2oyoAoP4LRw8/Aor/+N6zZ892KA7GqgHveBalc/bs1bMdsD/3hF5J4WKQ
uVaxh6qYpjyiJyWzGcTOfbkBCDEJPwxPCG8Ehxm/AJejW9+tdLsrJ0BWVrrm/UtLSxUs8OojP7a6VrcLKl5dW+vanQ4atdPh+l+9in6LQ7KyYmXeC0K5SAeQ
Q4vBcEqqaMjXctreRwR1NuSw51GEg9/BESfGKS8m3e+6Ui5Ya6tP16YCLNUO3dtZs7h6a/B95dLGxsYJLuI8KxsnMwngx/w1SCuWbVmWSDNrFB5mYAiNEctt
lWkpghofcaNAvoUDCD9+GbzTM+jKiV+esEgzSXprK/svrHUw0mnPXHyq3wTDAC/UDnXoRRjatZXg5MkNJjUUqq90N/RMfg8C306WZGMjCER6XAEgq4vOu9bJ
zQYwublkwpETBYas4RkG6eIwUbPRiHv8oWVFZg+U4ZhgEHfxD7XJAOu1Q4RaUfQflD15kq3g2FolWflGl8qi+hwjY9F/X7CdPKnpJzfgty+UfIynzI4Iit7V
q1fvzZIo98cuxUzWs05sbFzq0oiYy134fctOLYy2U66QzcW/9KeiuWH9MaCalLQcp221LDuiPP/QKGq1LEvXgyB4UgrH0H/P9Zc8OcK+b06C313auMSjDz1t
TQTOGp4Mcsu9F0Ce6Hbfeecd9M5Ll050eeRYwco7MPBdy+wB/JrFrrMuPeVuCllYXHx6MsCXc5gY49hoa6EVNSmYM26AJAQAorbf5hJIebIkwi4n0akA5pv9
K7kwxjY21jqYSzY2wA+/g6C6dGJYVjqtVtOA+H3iwlqXdSGUIF+vnTzJLG9zIZPJAEu1gx5ALpw+7TKtZcSxGZ85jeLGDTNJTCdotVqPPvqobb8M/4O0X85h
SvLkk99oa5nX8cKhyxiEyAkeUILg5P+BXAIRyoMheCpIIwLhenV5jW0E3R44lbGywWxjoQB4djLA/aA/istSbwFA8FcWBZLnmjptNps8XbZyedSW8rKwDox3
ECg22CtqwX/oeuCJgbbBdbc50QrbOKnv27dvIyfAeaqz9oTNmN2BeffYqe4GYwScfrMDRjO57ptVAB4U+i96zFgckIXFxGk0bt5MQG42c4Ho4FpGHEewaCEB
VDwwaRL4qRVoDALKsvgxlpUGGgqYAAef5/gLZzHPUqYFjECS3V6GgSC33O3NTmCxjyoCwE/mTqOqC4vGMMDiYitwG1x4WJjmTTMRAspSScPNo9KGAUehNACB
pFpoR9ImKCkLgwDd6BIO/YULmGGx+HFh4Fe6HQjDbc9m3Y5769YmDWxGhPtsbk8FODwXc58/baaG9J6S2GkZoCwJJpAEeJr4fxS6Z864PHrOuMBgMCeNIJ1R
0mxiSotsdDQMbQBA9bGCOgUOv+nCwHfXsDD0bKgA3M1bmyTYEgCL2+72lCBeqr06Z8Q84TYZ4ZWaezqLHoiHNI2xJLh586Z5U2puDJAgSMNuLXJ6/nuAEoNb
wJGiwoZjSAtC/zpEMgT1ftT+GJQTq+62u7ntrTDb8kBV196yLqImJGCBsIDrPj4VYH2uAXrHsUcYRRREgJE8A1qABG0T/SThA83FbMK4m4mwQCaNdnNRxr4Q
j0ViWFxevzZMagUQBTjV4czGa8VVcJvtzU0PJi9rFQ+1mWV7GcCmAJiaRuEFw+WuS1gEWTR2YziHUN+LG2FbpCAs2mQIk2ZJMqogWQTDLeaZryHyYGYRzyAt
BiGw8R3o3+G+z2V7e2EbADqWAQPnbaEp4HiqSQtsVgD4XW3O5JHXIMwCm2NJ7AoCfDkMMH1C2qGYeuBbK8Inf/7zn5vwBVjwAAI5cQg43Okidxu2WTw54wIA
lLo4JUDKX8YCXBYK25uuB7nHMjwXrMZgAoMj2fVAIwvb1SywXvsJn3kNgzKLe6w89xkPAYKA2rrjOAGcvG1jOsEEiiCFwLOmQ0FLxD6Dgey6CYwpTw3Clr8w
CTT5OPpQ0pnoP7I1AhNADHSs1YVbtwycEmycVDYCrbcDgATVN4yI2Ql2uNyf4OQxZkUAaNczURRf1SGZQ0IUyT9DiKgeuWbDy8bV84hFG14hUG3RjoW9BPRk
WNxh4wCHb7vuorvCKDWw5yNQoMOpYVYMNswSwFOTAH4uAUwjCmwC0ZlglhH5HKjCkKb1MYI4uuYEAZSAqgUGa4gshnEL5S3hCYifxYBqEQGwYyCkQ5exTfC4
H20vcBcinY+wJyA22AAIWFB44OJkgBcgBhqGAEgpj0g5IfF3ngSQiw41qw1J04sFAbBQm4o+piF6LkIvYpXe4QyUoAkkresRG14wXN7UcMPuCGC9NtfgFjAB
gJgCINffCJ0SgCIrZ0f3VV9RygCabZjSZ0AT8MeUFk0+NwCviEB/qKvpR2UAFxxs1cUFA+iHMwCoCioC/AYAMIYBgKXchYQFOFWjUQLwNSeEcNbDIMzlzRQc
1glbLQDIKgkQw7AgI+R9v5mAAXid2gFHumh1zD6AU6v8CfT7RBSyMGMElQF+jgAx6J8IAHiAFpDzbRxkAKqDsQUEgMGlnYZt+Jam7XYaWXoK05uRTdIcgPAJ
gp9R6J83elSYRvqba+SLRkTU4VqwRT0JsD0N4MvaIdA3KQC4CzVE/DVi5kQIoIe8bOYEDicAtdviO3zZLT3Fqdo0REJLTATIZrkk4Q5kQakDyqMdMgtwAK8n
FjB66Gd2d8UiPcPN2xnoyCa3lAIArAwAbYogprAAlBXgDGnQYnWlzU3LBxu+UO3UaqXpv4Zv4gtp2kKAhKvFw4kD5FN3E7pT2eVwI0B89wUxlnykJ1YdiSHm
6M1SP7M4EeBVDoDNVxQwKqKuwWdmMT9ja2nECVTN0G0LvfE7bwjEQwsALARITJl0ygBYWqMBLLsQqz+Gs1IFB35xc3MI4A8/nbQqAQCxAKBgAenGqLuLFV4M
5RB/7IrSCDwEyroINQMA7FagaG7BhKYJAOFBgAB1GcFKumnC+KMBJgBgVBBIRKJ6E1IUUoMhMAEgxWrHdkyRSTxM57GRFEUbmiYrF6D2x84lOYYeDsZRU1MC
8GA2OIDwIUImAxhod/5E1PBDFqgKEEEysVqBYsYlgVK+r+40M/vgF3zDQgePahpJDoBGFFlIdjOlGCgDyMG+xecAT+ovCTYXbmWmmALw89ohrH4grFptLGsC
pZlr73mQTc3MBiZvTUSu7/MmPnWUALCcagGAgQDNcQBZ0Yg28AoDlNwoA1iaCPC72m9+wnt0ajHoz62gbooIEOMs1OQAoCRvLONiuhIOJnxFxHCDx3EjRhcy
pAdlAGkOkGROU+p5cgB3ZwC1c7XnILFDcncQAJImRHIMTu4JAMOUSiYiO5UkAxD2MbMEgIWsYQVoAelAAiCdApCp7nmlH8GzhSlro+u1fwkZVgdO0MLWu16H
uZa1GSRIgoPP/RgBZIGR+1cfgCmmbiP7qR1iaStjeMgCZh62ucojhTvawuOTAV6p/VPIyxsntCNHZ1g1aDpfxMF/sJmBictq0UTq7p4WrUJsGFl8kGYjy78e
p/RwysI1ozawDwFcLAAW8iAY0l1G+sLiH6sDpHo9gLrB6RNOoupOGMCcawMIOgy6Ck7f0kug0Re1U8zjxPBkzOpKhOu6FOeMzIcsO+IArgSQI9037rh9YwgT
TQVAF+LiOHaqDQNwI0gQXYVnGhZDAYMqKOUNJu7RZNaBaQ/jBizQFgAqFS7UKkwApQQfXF7Iedn+R647Kk9IkaOmAazXfrafpSl0oqHzcttBAKeCoFnyJ2Eb
+i+eiczGGR4nLu+s0AIIAF8cYKsAMEt7tBmCVJ4SQ3QV1QDO1X4WtvlybNtppwCg1MNBZaeRqEKgvXQCGAqwTBS2+XjrPiViNSMDwH+JScqbmnk5jajoOZkv
yTQ6DeAZGEGGLuS300APfD9bcWZBOKxwOISnFZgSxYeGTbqQAji4Y8Ibsi0kYMyGYRa6l3YA8QhUH4xgEyJ2MaG/MasAaDwAHF3BIH15n44dnRSOEo6RoSiR
BoFY0dUgtdvOyzo0cr6gUqRAmqYkKe2Ko4+h8h/xhxbT64oFFAH8LjMxC02eB15BC3BtAAAHbZ8eZv6daRqUtgHCkLGRGEXGAv11P0jToP4kKCG0L68BhJQQ
UijPte/xsbdYoOGhzDV0/q9n7gTAlwD9CiEHat8uRFhnyBxaLhyAOXUHAMAaOPwlgIBSeYUBtSzpONwalOniuMA16/goMMlUgFrt/D9nFsDMYel+2TV412ul
XHL9RXvJ2CifkiYAgEACqMMAFykfeBQirIEINMiOYgum+NcwKwA8IAE0XHjQNMXPgpK1eetVrCHaJQ7Qvv3mm2+ODAs4i+9wC2gjAcRGGh98DO4NHds3OyiO
YW4OsFDBAs/LIK5ze2cepFkJ4X053zEqYewvYbxZYpBBI34ZANoSAKQ/BjRIRbZFUXvbDjR4X8UmdvmIfoBnKwJoeO582nVssUoH1TQuixCgwK8MBBv5Vpq7
lvSeIgwUrd0OFE2r63wC7wMAV6V869hi1zXh9cwj9ZKVSi5UAeCBPgBNzLFa2GgS3qKYUGg2xRpPQ2zhUb73xVlAfTBICFooOhZMudS1FMPEqfOQ6AeoM9HF
X7QhWJQCoHTAAukDeGEiwOvDALgCnSSpqjmpxfdiRNsVQ7toiJUG6G+w1gaK0M9W7vQSAQJAoGgiCQ0AYBBgENvX9ykTAexKFvhRCUCW0eAKYbMZFIvQGtTU
dtRMRCPJ19vQtwzcjuxfrc4BbExXmohhfwCAiSUiyJrSb5hLyofsDKA2GoA0WT6woIEP/6tqiGvp+OZRghc3GSY4V1Dy7pyg7uBKmO2MBNBwu0zX9ykQznVp
AY8VZ6nbi8IgAuDpnQMgQ9QUOxu6iAldtAU+ZET8H54GIg+SqKxdhlCHZBxgDIwCgJ/jC4pFTZIBuAQXv/kTaEoon5ABwJgO8EoOoPQB0ESu6mrFi8VMq6NR
AMdvEdKvnUDg+zko6ggA6TgKRoIAsKEVsAjt8h9QU5NH2GYlgJdk9u4HSFw7t0ChNwj+K5+reh06AX9gv8OXACKoKwKsemaPbvEnxMsArCoWOJcB9FtAS+J0
PICeMagWafhDe0+qAMAeYbQFxL+2dbFkAaioGf+J6Qb1nQE4Yh7qByClGBiJIF6xjdgfsX2WAaijADKBRCRjwHb5RqAE8PoBntodQNRMRwJo/TFhDcZAaUOq
OgCjBppAZCLTkNMbLlFVAfjVSBeKmvYYgHy6xsohScYCqFUAROJRFOwHqC4AzPrOAF4SBdAgAMkASkrLCIaqjbWh4cRYJ0Qds3lZACijASAPm/Z1QWAYliaP
MsmOAN6ofcp37zT8fXUagKridUApzGRQJyigo/WfyTgAZQoAZCHLuMgkAMlfL1mgWgy86IwGsLJ5IPN7mIktrOaMRgusr/PgtcZboAoAdGECwKP565BG62UL
TF3c/dVIANoPgBk9JG6jkdAoil2vYYn3SMmeLGBagQSw8gQWuJYEIKQCwBtjLEAkgC8DV9VAbxOvhoO5K/Ky5LlHAONiwH8oAXTnZWprUBeJ39gNgF5koRyA
O3+axI1mk7SYgxeTxdklIFYU+bfBAroB76YxrLKh0MuKVGJWAuD7A1oGIKYqPY8BBAD3sbwmNZOorfn1gCQR1bJU2F/MjQTwxwBgGsXlHziXYprQp2GPppTm
6gygVgkAayFfy+phrZUDYAiTBo2g8dZwtNMkifIWNh07kVUAgM4Yhk1BI9gesexA7S82iOlVAxBzUh+AblNLTqjwGjEiw2gForOCbj9KCwC6JwDsaXD+0gwb
G9MRAH+ZAvBKDgCjqxQAVtIS54L4jRpRsxFpau72SbsEsG8PACYLdA0rCM3Ssyp1VwDaEEAUUwmg2nFEXNBfkbEXkbgAoFTdQwwYuLYIrqnhQvAQgGm60wE+
rF3WRgIYIjoVVTOIRSPNz68OInHMsrdqR4m+FwC+yItrLAMAiqgvKgDUJICOMVB2ISKmKkWPzFaS+w9kKiuJjRyAJV4FgPoEABM7geiiXXKhgKlyTt4RQL8F
svyoMCOiZqDnSqgwmTXzFrxNyO0AoFEZACsMOGtAcIPj8d0BqGkGQBOYErRCS40gQKZT1Ix2D2AXAMIC8ifUiz2DErFF88f13QCoOYBmRIQGWjHdalAMEabm
AHSPAMYwACntdS/8ceqNcM8MA8C7pjSSbR01IEsU/azWikiSZsV7GpHbAmANAuSbZLsGkBZIjCgJdDVbcFB9PW0lpuXkxdydAHALgMXqAOooAB0vBxLrpilp
mM1W204io0EdidSmUwB8kOkAeMlREcR9AH/YG0DAQ1iF0I1jXKdOmo0YF9odqTYjewdI9ghwrQSgDwLYcZJg6ak6egjOjzvWuLCeWyCgdNcATGYhgpdllgCU
nVtArBbK9xQA7YgDtOK40XKyMkJr8yvwoasJ1cwC0e4BmATga+1FDChmaau7AsDrIwEY71QUfi1ZyneOQw2XdZmFBC0m0xAju7aAXhVg2t2s5wcAVAnQAgDd
ixN+y4nZJJHNAnSmEE3QlibYgwV0uxLAszsBKK3lsKQJL+gx7pORZtM4fSY2khbDtQjdapLUEVMDGGoigD/ZAmYOkO4eYH4kQNrgAAYknqRlteJGFEInk0QO
qOPTOApDZc8A0A+QDICpe7CANsoC3DfQhQjeiUeJhW0nhHYbjlNbTVkxsilZaDIAbnMnBr+iixXVtGIafQDrU4N4FEBIEUAzozTUdKjouSa65oSp7aiKSlPG
fSggjR0DSE11W1xwYPJde6bkBN+Y/AYVQVDFhZ6X6+Z1eWVDCUDRlIEtRkUPrLauaIHoEIIpM/EIAAVzWqCx7IoJk19NVLKAzj+pIgOYfk/96+MARJ5R9cER
hFTq+HImS5s7jgElxa0Zfi2aBLgIAIFSv+0Aeq5G3ur5QsJ2KAvs1uQ06o8C4JdJyE9E4AB4NdQAgJHdYFABYKwLgfuouAKt8j093AdW5c99lYWi02XFGtfw
XU6+NEBFgDy6iysBoZyeDvBACUDNAQIE8POiGHdYSwLhrHLNgohMAPBHAqR2ZQCvCkDthtz9woI/V9GJaL7TjeNe2KYPJJgwD0wCKBFwgLTsQvnVgBUB7hkB
oOswRbUCnvPGaY8Ak8rpCgD8olOehMYAeAtP9V/rMRZAHbCAqttREltqdg/iSPUhnHdhAWbbBQAgoAEGAMwdAbzEd18GAXBDoGGaVMn234eU1zXWgtp0Qhaa
AMAvJ80Btlg5BsySCRaemu5CAkAdBIAwMI2GRwN5Kcqg+iy18DKoaHcAeDVbBmAPA2Qf4uO5VQD00QC+z0wXSmnbH9g2BesEKXZmVjrRApNcSEiEnylg4eWw
QwBmdQu8OAYAX7OwY20F5ZlJ1cI0otBc2jCIVjT+btcJAPZkAJIh3Odt7g0AqlK8n5vQUGz4wdinEYE22W5hIQkuZKnjARSh/hDAVunzZy4iAMRwWBykla6t
ruRCIwGymOVNZGLQFJsxLQxT0ogT2sTFhCYhUSusT7SAoowAYH0foAMATF6ymwPg6Ijrk929WgAR8G43EjFN1R0WJY0m3s7RAADo7ZXxtxkr/DqvCgD2IIAs
Uz/aAwD33VLM2hFpJs20jU5rUPB9YrhWoE68Tzp3oGGAsg8BQDoagBO4S9MBnhthgfwuesGhM2LgPWXiIlh+I6Uz7UZvxVeKS9b7AfpMEA0D5K2Cafy1CgC/
CIIrPQBQtFB+2MLrRpuovZW29fp0UZTxAGlxcyvWEUMAkiCpCqBPBhDv244BAPdyNaVe3yPAVum+PgsNUNpB4QBZs7NTAGU8AOTnILX56pav7kz/YQCWlgD4
zSIlgKAotYkJAOu7APDrexJlIkAQlE0gPMgZAhAQ5uMVLPC2ANBvEwBGzFQANgCgjQSg1Jy7uwBcXchcUwCAIC3urcQQKG3CAYAsM9AGcwPV9CiAy5roufYK
0K/xFAuwra0tZEg5QFjahJN3SECVga3modq0Tb4PM4DbEgPCBMp0C2QAWzb/bIoygJZ9WloaBPtfnfpxnR9yF9JvWxBXBWACgAkPGgbAD4kJgyO1CgCXiyxU
zyqJuwAghX+azRCA3Qa30sIjtSoAz9x9gBJBOgIADIN3s2lHaq9U+cjaa3pxn4V/NwDCfhtgCJSyKM50+Kl013/wo4qfevxMGYBXb3cWwBkCgGKsfBAf/eef
O1c7VwXgFelCfg7g31kAXwtGAJSuDFTw0sPnDtdqVS1w+AauHPqZC91pAGUUQPlWJ13TX3qmNnL4xwDcU7Su/LaMMcXcDmaCCcUoAIRhgRDwaUyYQB6oPX95
rPqjAN6ofeuXr5XCJSD/jgI410uf9AmFHAfwswNvPPdq7X8/3NFnrx/eN6TCHQXQrvd9WKnmiDwu1gDvObeLD48/vgeFK8TAEAD/qLcCgC/NCv3fularnd/F
p9+/7d9tgILA4Uvjn75//L33jr+264/vP75vstv87W/7bjNAjoD6Y9bZ098feKA2/61EUAYiGBS48gk/6LX3P3jrStFy7SEGxI3i/O7dEPS/cfm2/AGFX1/7
9p6vr/g3Xnz7k2JOgSnlnrdLf6Bi/qvj7/3trX3KGNUrA+QfhqDpN5772e37ExZL89wLP8F35RcPaS+OMO48GOO9YZ/aGUB2V8un52/f3+AQpzr3BtR3xz/9
+grY9vjrtQlZ4TU0Rv+cO7IjGw8AQ/R67Xzt9lmgb5y/+mrob0qMOGr++HsffH2lvgMAvXxf3ad39a+gjJPXwac++fpKv8pTAfje7rXvBUBmjdc++eCtCgDZ
/Zggb9fOfY8AuFypACAvLNRvvL3z899xgLeGV1lGAPC7jl88X/s+A5RntYHdS36f/oSa/+8K8N7UWoNfCPD85V2e/44DvDa9WFKhYzxf+74CnHtrmv5iej//
fQWovXZF6bs2bhBAf+nyXk5/F/4i3FcfXEHVFeWeD64MISg3Lp+HLvZ7DQDuMT//yQcfvD9f+/CrQf1ffH333nP3AEry/pWSJymfXtvzCe/6HxWcf//be/bx
VZuvv712G873d/mriA/Mz1+7Nn97zjX7s44zgBnADGAGMAOYAcwAZgAzgBnADOAfVv4fZ53OkYMWPo0AAAAASUVORK5CYII=
]],
[[
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
]],
}
local B64A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64M = {}
for i = 1, #B64A do B64M[B64A:byte(i)] = i - 1 end

local function b64decode(str)
    str = str:gsub("[^%w%+/]", "")
    local buf = ffi.new("uint8_t[?]", math.floor(#str * 3 / 4) + 4)
    local n, i = 0, 1
    while i <= #str do
        local a, b, c, d = str:byte(i, i + 3)
        local v = B64M[a] * 262144 + B64M[b] * 4096 + (c and B64M[c] or 0) * 64 + (d and B64M[d] or 0)
        buf[n] = math.floor(v / 65536) % 256
        n = n + 1
        if c then buf[n] = math.floor(v / 256) % 256 n = n + 1 end
        if d then buf[n] = v % 256 n = n + 1 end
        i = i + 4
    end
    return buf, n
end

local icons = {}
loadIcons = function()
    for i = 1, 3 do
        local ok, tex = pcall(function()
            local buf, len = b64decode(ICON_B64[i])
            return imgui.CreateTextureFromFileInMemory(buf, len)
        end)
        if ok and tex then icons[i] = tex end
    end
end

-- ---------- общие элементы ----------
local function setCount(i, v)
    v = clamp(math.floor(v), 1, 9999)
    ui.cnt[i][0], cfg.cnt[i] = v, v
    markDirty()
end

local function cntLabel(n) return (n >= 9999) and "Все" or tostring(n) end

-- кнопка "+" / "-": клик = шаг, удержание = автоповтор с ускорением
local function stepper(id, x, y, w, h, dir, apply)
    local clicked, hov, act = hit(id, x, y, w, h)
    fill(x, y, w, h, K.panel2, 10)
    frame(x, y, w, h, act and K.cyan or K.line, 10, act and 1 or 0.8)
    local cx, cy = x + w / 2, y + h / 2
    line(cx - 7, cy, cx + 7, cy, K.text, 2.2)
    if dir > 0 then line(cx, cy - 7, cx, cy + 7, K.text, 2.2) end

    local now = os.clock()
    local hd = view.hold[id]
    local rep = hd and hd.rep
    if act then
        if not hd then
            hd = { t = now, last = now, rep = false }
            view.hold[id] = hd
        end
        local held = now - hd.t
        if held > 0.45 and now - hd.last > (held > 2.0 and 0.03 or 0.08) then
            hd.last, hd.rep = now, true
            apply(dir * (held > 3.5 and 10 or (held > 1.8 and 3 or 1)))
        end
    elseif hd then
        view.hold[id] = nil
    end
    if clicked and not rep then apply(dir) end
end

local function switch(id, x, y, on)
    local clicked = hit(id, x, y, 56, 30)
    fill(x, y, 56, 30, on and K.blue or K.panel2, 15)
    frame(x, y, 56, 30, on and K.cyan or K.line, 15, 0.9)
    disc(on and (x + 41) or (x + 15), y + 15, 11, K.white)
    return clicked
end

-- ---------- шапка и вкладки ----------
local function drawHeader()
    local lx, ly = 54, 50
    disc(lx, ly, 32, K.panel2)
    ring(lx, ly, 32, K.blue, 3)
    ring(lx, ly, 22, K.cyan, 2, 0.8)
    for k = 0, 11 do
        local a = k * math.pi / 6
        local co, si = math.cos(a), math.sin(a)
        line(lx + co * 25, ly + si * 25, lx + co * 29, ly + si * 29, K.cyan, 2, 0.9)
    end
    disc(lx, ly, 6, K.blue)
    disc(lx, ly, 2.5, K.white)

    T(100, 14, "Auto Roulette", K.text, 42)
    local full, part = tw("Auto Roulette", 42), tw("Roulette", 42)
    T(100 + full - part, 14, "Roulette", K.cyan, 42)
    local pw = tw("by Edward", 15) + 22
    local px = 100 + full + 16
    fill(px, 26, pw, 26, K.blue, 6, 0.16)
    frame(px, 26, pw, 26, K.blue, 6, 0.8)
    T(px + pw / 2, 39, "by Edward", K.cyan, 15, 0.5, nil, 0.5)
    T(100, 64, "Автоматическое открытие рулеток", K.dim, 18)

    -- бейдж сервера
    local bx, by, bw, bh = DW - 72 - 14 - 176, 14, 176, 54
    fill(bx, by, bw, bh, K.panel, 14)
    frame(bx, by, bw, bh, K.line, 14, 0.8)
    fill(bx + 10, by + 10, 34, 34, K.blue, 9)
    T(bx + 27, by + 27, "R", K.white, 24, 0.5, nil, 0.5)
    T(bx + 54, by + 8, "Rodina RP", K.text, 17)
    disc(bx + 58, by + 40, 3.5, state.running and K.good or K.cyan)
    T(bx + 67, by + 32, state.running and "Скрипт работает" or "Скрипт активен", K.dim, 13)

    -- закрыть
    local cx, cy, cw, ch = DW - 72, 24, 50, 34
    local clicked, hov = hit("##close", cx, cy, cw, ch)
    fill(cx, cy, cw, ch, hov and K.panel2 or K.panel, 10)
    frame(cx, cy, cw, ch, K.line, 10, 0.8)
    line(cx + 17, cy + 11, cx + 33, cy + 23, K.text, 2.2)
    line(cx + 33, cy + 11, cx + 17, cy + 23, K.text, 2.2)
    if clicked then ui.main[0] = false end

    line(22, 96, DW - 22, 96, K.line, 1, 0.6)
end

local TABS = { "Рулетки", "Статистика", "Настройки" }
local function drawTabs()
    local x = 22
    for k, name in ipairs(TABS) do
        local w = tw(name, 17) + 40
        local clicked, hov = hit("##tab" .. k, x, 106, w, 36)
        if view.tab == k then
            fill(x, 106, w, 36, K.blue, 18, 0.22)
            frame(x, 106, w, 36, K.blue, 18, 0.95)
        else
            fill(x, 106, w, 36, K.panel, 18, hov and 1 or 0.6)
            frame(x, 106, w, 36, K.line, 18, 0.6)
        end
        T(x + w / 2, 124, name, view.tab == k and K.text or K.dim, 17, 0.5, nil, 0.5)
        if clicked then view.tab, view.edit = k, nil end
        x = x + w + 10
    end
    if state.running then
        local cur = ROULETTES[state.cur]
        local txt = string.format("Идёт открытие: %s %d / %s  |  %s", cur and cur.name or "",
            state.prog[state.cur] or 0, cntLabel(cfg.cnt[state.cur] or 0),
            fmtTime(os.clock() - (state.runStart or os.clock())))
        T(DW - 22, 124, txt, K.good, 16, 1, nil, 0.5)
    end
end

-- ---------- вкладка "Рулетки" ----------
local function drawCard(i, x, y, w, h)
    local r, rc, on, running = ROULETTES[i], RCOL[i], cfg.on[i], state.running
    if on then fill(x - 2, y - 2, w + 4, h + 4, rc, 18, 0.07) end
    fill(x, y, w, h, K.panel, 16)
    if on then
        local pulse = (running and state.cur == i) and (0.75 + 0.25 * math.sin(os.clock() * 4)) or 0.9
        frame(x, y, w, h, rc, 16, pulse)
        frame(x + 1, y + 1, w - 2, h - 2, rc, 15, 0.35)
    else
        frame(x, y, w, h, K.line, 16, 0.7)
    end
    local a = on and 1 or 0.45

    -- переключатель вкл/выкл (кружок в углу)
    if on then
        disc(x + w - 24, y + 24, 10, rc)
        line(x + w - 29, y + 24, x + w - 25, y + 28, K.bg, 2.2)
        line(x + w - 25, y + 28, x + w - 19, y + 20, K.bg, 2.2)
    else
        ring(x + w - 24, y + 24, 10, K.dim, 1.6, 0.8)
    end

    -- иконка
    local is = 150
    local ix, iy = x + (w - is) / 2, y + 18
    disc(x + w / 2, iy + is / 2, is * 0.5, rc, on and 0.10 or 0.04)
    if icons[i] then
        dl:AddImage(icons[i], P(ix, iy), P(ix + is, iy + is), V2(0, 0), V2(1, 1), U(K.white, a))
    else
        fill(ix + 25, iy + 25, 100, 100, rc, 18, a * 0.8)
    end

    T(x + w / 2, y + 205, r.name, on and K.text or K.dim, 22, 0.5, nil, 0.5)
    T(x + w / 2, y + 238, RDESC[i], K.dim, 14, 0.5, nil, 0.5)
    fill(x + w / 2 - 16, y + 262, 32, 3, rc, 2, a)

    if not running then
        local clicked = hit("##card" .. i, x, y, w, 282)
        if clicked then
            cfg.on[i] = not cfg.on[i]
            view.edit = nil
            markDirty()
        end
    end

    -- блок количества
    local bx, by, bw, bh = x + 14, y + 290, w - 28, 92
    fill(bx, by, bw, bh, K.panel2, 12, on and 1 or 0.5)
    frame(bx, by, bw, bh, K.line, 12, 0.7)

    if running then
        T(bx + bw / 2, by + 10, on and "Открыто" or "Не выбрана", K.dim, 14, 0.5)
        if on then
            local tot = cfg.cnt[i]
            T(bx + bw / 2, by + 44, string.format("%d / %s", state.prog[i], cntLabel(tot)), K.text, 24, 0.5, nil, 0.5)
            local frac = (tot >= 9999) and (state.skip[i] and 1 or 0) or clamp(state.prog[i] / math.max(tot, 1), 0, 1)
            fill(bx + 14, by + 72, bw - 28, 8, K.bg, 4)
            if frac > 0 then fill(bx + 14, by + 72, (bw - 28) * frac, 8, rc, 4) end
            if state.skip[i] then T(bx + bw / 2, by + 28, "закончились", K.warn, 12, 0.5) end
        end
        return
    end
    if not on then
        T(bx + bw / 2, by + bh / 2, "Нажмите, чтобы включить", K.dim, 14, 0.5, nil, 0.5)
        return
    end

    T(bx + bw / 2 - 20, by + 10, "Количество", K.dim, 14, 0.5)
    -- "Все"
    local all = cfg.cnt[i] >= 9999
    local ac = hit("##all" .. i, bx + bw - 54, by + 6, 46, 24)
    fill(bx + bw - 54, by + 6, 46, 24, all and rc or K.bg, 8, all and 0.35 or 1)
    frame(bx + bw - 54, by + 6, 46, 24, all and rc or K.line, 8, 0.9)
    T(bx + bw - 31, by + 18, "Все", all and K.text or K.dim, 13.5, 0.5, nil, 0.5)
    if ac then setCount(i, all and 10 or 9999) view.edit = nil end

    local ry, rh = by + 40, 44
    local function apply(d)
        if cfg.cnt[i] < 9999 then setCount(i, math.min(cfg.cnt[i] + d, 9998)) end
        view.edit = nil
    end
    stepper("##m" .. i, bx + 10, ry, 44, rh, -1, apply)
    stepper("##p" .. i, bx + bw - 54, ry, 44, rh, 1, apply)

    local vx, vw = bx + 60, bw - 120
    if view.edit == i then
        imgui.SetCursorScreenPos(P(vx, ry + 6))
        if view.editFresh then imgui.SetKeyboardFocusHere() view.editFresh = false end
        setPx(22)
        imgui.PushItemWidth(vw * S)
        imgui.PushStyleColor(imgui.Col.FrameBg, K.bg)
        if imgui.InputInt("##cnt" .. i, ui.cnt[i], 0, 0) then setCount(i, ui.cnt[i][0]) end
        imgui.PopStyleColor()
        imgui.PopItemWidth()
        if imgui.IsItemActive() then view.editSeen = true
        elseif view.editSeen then view.edit = nil end
    else
        local vc = hit("##val" .. i, vx, ry, vw, rh)
        T(vx + vw / 2, ry + rh / 2, cntLabel(cfg.cnt[i]), K.text, 26, 0.5, nil, 0.5)
        if vc then
            ui.cnt[i][0] = cfg.cnt[i]
            view.edit, view.editFresh, view.editSeen = i, true, false
        end
    end
end

local function drawStartPanel()
    local px, py, pw, ph = 785, 150, 278, 430
    fill(px, py, pw, ph, K.panel, 16)
    frame(px, py, pw, ph, K.line, 16, 0.7)
    local running = state.running

    -- кнопка запуска
    local bx, by, bw, bh = px + 14, py + 14, pw - 28, 66
    local clicked, hov, act = hit("##go", bx, by, bw, bh)
    local base = running and K.bad or K.blue
    fill(bx - 3, by - 3, bw + 6, bh + 6, base, 20, 0.18)
    fill(bx, by, bw, bh, base, 16, act and 0.80 or 1)
    fill(bx + 2, by + 2, bw - 4, bh * 0.45, K.white, 14, 0.10)
    frame(bx, by, bw, bh, K.white, 16, 0.18)
    local label = state.stopping and "Остановка..." or (running and "Остановить" or "Запустить")
    local lw = tw(label, 26)
    local lcx, mid = bx + bw / 2 + 16, by + bh / 2
    local left = lcx - lw / 2
    if running then
        fill(left - 34, mid - 9, 18, 18, K.white, 3)
    else
        dl:AddTriangleFilled(P(left - 36, mid - 11), P(left - 36, mid + 11), P(left - 14, mid), U(K.white))
    end
    T(lcx, mid, label, K.white, 26, 0.5, nil, 0.5)
    if clicked and not pending then pending = running and "stop" or "start" end

    -- пояснение / статус
    local iy = by + bh + 22
    ring(px + 28, iy + 9, 9, K.cyan, 1.6, 0.9)
    T(px + 28, iy + 9, "i", K.cyan, 13, 0.5, nil, 0.5)
    local msg, mcol
    if running then
        msg, mcol = (state.msg ~= "" and state.msg or "Идёт открытие..."), K.warn
    elseif state.msg ~= "" then
        msg = state.msg
        mcol = (state.kind == "success") and K.good or ((state.kind == "error") and K.bad or K.cyan)
    else
        msg, mcol = "Скрипт будет открывать указанные количества рулеток по порядку. После завершения - уведомление.", K.cyan
    end
    local lines = wrapLines(msg, 14, 196, 4)
    for k, ln in ipairs(lines) do T(px + 46, iy + (k - 1) * 19, ln, mcol, 14, 0, 0.9) end

    -- всего к открытию
    local sx, sy, sw, sh = px + 14, py + 190, pw - 28, 158
    fill(sx, sy, sw, sh, K.panel2, 12)
    frame(sx, sy, sw, sh, K.line, 12, 0.7)
    local total, any = 0, false
    for i = 1, 3 do
        if cfg.on[i] then
            if cfg.cnt[i] >= 9999 then any = true else total = total + cfg.cnt[i] end
        end
    end
    T(sx + 14, sy + 20, "Всего рулеток к открытию", K.text, 14.5, 0, nil, 0.5)
    T(sx + sw - 14, sy + 20, any and "Все" or tostring(total), K.cyan, 28, 1, nil, 0.5)
    line(sx + 14, sy + 42, sx + sw - 14, sy + 42, K.line, 1, 0.7)
    for i = 1, 3 do
        local cy = sy + 68 + (i - 1) * 30
        disc(sx + 22, cy, 6, RCOL[i], cfg.on[i] and 1 or 0.35)
        T(sx + 40, cy, RSHORT[i], cfg.on[i] and K.text or K.dim, 15, 0, nil, 0.5)
        local val = "-"
        if cfg.on[i] then
            val = running and string.format("%d / %s", state.prog[i], cntLabel(cfg.cnt[i])) or cntLabel(cfg.cnt[i])
        end
        T(sx + sw - 14, cy, val, cfg.on[i] and K.text or K.dim, 16, 1, nil, 0.5)
    end

    -- подпись
    local fx, fy = px + pw / 2, py + 462 - 24
    local cc = K.dim
    fill(fx - 9, fy + 4, 18, 4, cc, 1, 0.8)
    dl:AddTriangleFilled(P(fx - 9, fy + 4), P(fx - 9, fy - 6), P(fx - 3, fy + 4), U(cc, 0.8))
    dl:AddTriangleFilled(P(fx - 5, fy + 4), P(fx, fy - 9), P(fx + 5, fy + 4), U(cc, 0.8))
    dl:AddTriangleFilled(P(fx + 9, fy + 4), P(fx + 9, fy - 6), P(fx + 3, fy + 4), U(cc, 0.8))
    T(fx, py + 392, "Удачи в открытии!", K.dim, 16, 0.5)
    T(fx, py + 414, "Auto Roulette by Edward", K.dim, 12, 0.5, 0.7)
end

local function drawRoulettesTab()
    local cw, gap = 238, 14
    for i = 1, 3 do drawCard(i, 22 + (i - 1) * (cw + gap), 150, cw, 400) end
    drawStartPanel()
end

-- ---------- прокручиваемые вкладки ----------
-- fn(width) рисует содержимое от (0,0) и возвращает высоту
local function scrollTab(id, fn)
    local x, y, w, h = 22, 150, DW - 44, DH - 150 - 16
    imgui.SetCursorScreenPos(P(x, y))
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.BeginChild(id, V2(w * S, h * S), false, imgui.WindowFlags.NoScrollbar)
    imgui.PopStyleVar()
    local dl0, ox0, oy0 = dl, OX, OY
    dl = imgui.GetWindowDrawList()
    local cp = imgui.GetCursorScreenPos()
    OX, OY = cp.x, cp.y
    local ok, total = pcall(fn, imgui.GetContentRegionAvail().x / S)
    imgui.SetCursorScreenPos(P(0, 0))
    imgui.Dummy(V2(1, ((ok and total or 0) + 8) * S))
    dragScroll(S)
    imgui.EndChild()
    dl, OX, OY = dl0, ox0, oy0
end

-- ---------- вкладка "Статистика" ----------
local function drawStatsContent(cw)
    local y = 0
    fill(0, y, cw, 70, K.panel, 14)
    frame(0, y, cw, 70, K.line, 14, 0.7)
    T(18, y + 12, "Последний запуск", K.cyan, 16)
    if lastRun.n > 0 then
        T(18, y + 36, string.format("Открыто %s шт. за %s", fmtNum(lastRun.n), fmtDur(lastRun.t)), K.text, 19)
        T(cw - 18, y + 12, "Получено виртов", K.dim, 13, 1)
        T(cw - 18, y + 34, "+" .. fmtNum(lastRun.v), K.good, 20, 1)
    else
        T(18, y + 36, "Запусков пока не было", K.dim, 17)
    end
    y = y + 82

    for i, r in ipairs(ROULETTES) do
        local St, rc = stats[i], RCOL[i]
        local open = view.open[i]
        local hh = 92
        fill(0, y, cw, hh, K.panel, 14)
        frame(0, y, cw, hh, K.line, 14, 0.7)
        fill(0, y + 16, 4, hh - 32, rc, 2)
        if icons[i] then
            dl:AddImage(icons[i], P(16, y + 14), P(16 + 64, y + 14 + 64), V2(0, 0), V2(1, 1), U(K.white, 1))
        end
        T(94, y + 12, r.name, rc, 21)
        if St.opened > 0 then
            T(94, y + 42, string.format("Открыто %s шт. за %s", fmtNum(St.opened), fmtDur(St.time)), K.text, 18)
            T(94, y + 66, string.format("В среднем %s на рулетку", fmtDur(St.time / St.opened)), K.dim, 14)
        else
            T(94, y + 42, "Ещё не открывалась", K.dim, 17)
        end
        local mp = St.prizes["inv:Деньги"]
        if mp and mp.sum > 0 then
            T(cw - 60, y + 66, "Вирты: +" .. fmtNum(mp.sum), K.good, 15, 1)
        end
        if St.lastN > 0 then
            T(cw - 60, y + 16, "Последний запуск", K.dim, 13, 1)
            T(cw - 60, y + 36, string.format("%s шт. за %s", fmtNum(St.lastN), fmtDur(St.lastT)), K.text, 16, 1)
        end
        -- стрелка раскрытия
        local ax, ay = cw - 30, y + hh / 2
        if open then
            dl:AddTriangleFilled(P(ax - 8, ay + 4), P(ax + 8, ay + 4), P(ax, ay - 6), U(K.dim))
        else
            dl:AddTriangleFilled(P(ax - 8, ay - 4), P(ax + 8, ay - 4), P(ax, ay + 6), U(K.dim))
        end
        if hit("##hdr" .. i, 0, y, cw, hh) then view.open[i] = not open end
        y = y + hh + 8

        if open then
            local list = {}
            for _, p in pairs(St.prizes) do list[#list + 1] = p end
            table.sort(list, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.name < b.name
            end)
            if #list == 0 then
                T(18, y + 4, "Призы пока не записаны", K.dim, 15)
                y = y + 34
            else
                local colW = (cw - 14) / 2
                for k, p in ipairs(list) do
                    local cx = ((k - 1) % 2) * (colW + 14)
                    local cy = y + math.floor((k - 1) / 2) * 52
                    fill(cx, cy, colW, 46, K.panel2, 10)
                    local pct = (St.opened > 0) and (p.count / St.opened * 100) or 0
                    clipBegin(cx + 12, cy, colW - 150, 46)
                    T(cx + 14, cy + 8, p.name, K.text, 16)
                    clipEnd()
                    T(cx + colW - 12, cy + 7, string.format("%.1f%%", pct), K.cyan, 18, 1)
                    T(cx + colW - 12, cy + 27, (p.name == "Деньги" and string.format("%s раз, +%s вирт", fmtNum(p.count), fmtNum(p.sum))
                        or string.format("выпало %s раз", fmtNum(p.count))), K.dim, 12.5, 1)
                    fill(cx + 12, cy + 36, colW - 150, 4, K.bg, 2)
                    if pct > 0 then fill(cx + 12, cy + 36, (colW - 150) * math.min(pct / 100, 1), 4, rc, 2) end
                end
                y = y + math.ceil(#list / 2) * 52 + 4
            end
        end
        y = y + 6
    end

    -- сброс
    local armed = os.clock() - view.confirm < 4
    local clicked = hit("##reset", 0, y, cw, 50)
    fill(0, y, cw, 50, armed and K.bad or K.panel, 14, armed and 0.9 or 1)
    frame(0, y, cw, 50, armed and K.bad or K.line, 14, 0.8)
    T(cw / 2, y + 25, armed and "Нажмите ещё раз - сбросить всё" or "Сбросить статистику", K.text, 17, 0.5, nil, 0.5)
    if clicked then
        if armed then resetStats() view.confirm = 0 else view.confirm = os.clock() end
    end
    return y + 50
end

-- ---------- вкладка "Настройки" ----------
local function settingCard(x, y, w, h, title, desc)
    fill(x, y, w, h, K.panel, 14)
    frame(x, y, w, h, K.line, 14, 0.7)
    T(x + 18, y + 18, title, K.text, 18)
    T(x + 18, y + 48, desc, K.dim, 13.5)
end

local function valueStepper(id, x, y, text, onMinus, onPlus)
    stepper("##" .. id .. "m", x, y, 40, 40, -1, onMinus)
    T(x + 40 + 45, y + 20, text, K.text, 19, 0.5, nil, 0.5)
    stepper("##" .. id .. "p", x + 130, y, 40, 40, 1, onPlus)
end

local function drawSettingsContent(cw)
    local colW = (cw - 14) / 2
    local x2 = colW + 14

    settingCard(0, 0, colW, 100, "Масштаб меню", "Размер окна на экране")
    valueStepper("scale", colW - 18 - 170, 30, cfg.scale .. "%",
        function(d) cfg.scale = clamp(cfg.scale + d * 5, 50, 100) markDirty() end,
        function(d) cfg.scale = clamp(cfg.scale + d * 5, 50, 100) markDirty() end)

    settingCard(x2, 0, colW, 100, "Пауза перед забором приза", "Секунды, 0 = сразу")
    valueStepper("pause", x2 + colW - 18 - 170, 30, cfg.anim .. " сек.",
        function(d) cfg.anim = clamp(cfg.anim + d, 0, 20) markDirty() end,
        function(d) cfg.anim = clamp(cfg.anim + d, 0, 20) markDirty() end)

    settingCard(0, 114, cw, 100, "Сообщения в чат", "Итоги и ошибки после открытия")
    if switch("##sw_notify", cw - 18 - 56, 114 + 35, cfg.notify) then cfg.notify = not cfg.notify markDirty() end

    return 214
end

-- ---------- окно ----------
local function drawWindow()
    fill(0, 0, DW, DH, K.bg, 22)
    frame(0, 0, DW, DH, K.blue, 22, 0.75)
    frame(1, 1, DW - 2, DH - 2, K.blue, 21, 0.25)
    drawHeader()
    drawTabs()
    if view.tab == 1 then drawRoulettesTab()
    elseif view.tab == 2 then scrollTab("##stats", drawStatsContent)
    else scrollTab("##settings", drawSettingsContent) end
end

imgui.OnFrame(function() return ui.main[0] end, function()
    local sw, sh = getScreenResolution()
    S = clamp(math.min(sw * 0.97 / DW, sh * 0.95 / DH), 0.3, 3.0) * clamp(cfg.scale, 50, 100) / 100

    imgui.GetIO().FontGlobalScale = 1
    imgui.GetStyle().FramePadding = V2(8 * S, 6 * S)
    if imgui.IsMouseClicked(0) then drag.moved = false end
    drag.inputActive = false

    imgui.SetNextWindowPos(V2(sw / 2, sh / 2), imgui.Cond.Always, V2(0.5, 0.5))
    imgui.SetNextWindowSize(V2(DW * S, DH * S), imgui.Cond.Always)
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, V2(0, 0))
    imgui.PushStyleColor(imgui.Col.WindowBg, V4(0, 0, 0, 0))
    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
    if imgui.Begin("##autoroul", nil, flags) then
        local wp = imgui.GetWindowPos()
        OX, OY = wp.x, wp.y
        dl = imgui.GetWindowDrawList()
        pcall(drawWindow)
    end
    imgui.End()
    imgui.PopStyleColor()
    imgui.PopStyleVar()
end)

-- ===================== MAIN =====================
local function runPending()
    local action = pending
    pending = nil
    if action == "start" then startScript() elseif action == "stop" then requestStop() end
end

function main()
    while not isSampAvailable() do wait(100) end

    loadConfig()
    pcall(loadStats)
    sampRegisterChatCommand("rul", function() ui.main[0] = not ui.main[0] end)
    say("Auto Roulette v3.0 {FF0000}By Edward{FFFFFF}  |  меню: {FF0000}/rul")

    while true do
        wait(50)
        if pending then
            if not pcall(runPending) then
                pending = nil
                setMsg("Внутренняя ошибка, попробуйте ещё раз", "error")
            end
        end
        if dirtyAt and os.clock() - dirtyAt > 1 then
            dirtyAt = nil
            saveConfig()
        end
        if statsDirty and os.clock() - statsDirty > 1 then
            statsDirty = nil
            pcall(saveStats)
        end
    end
end

function onScriptTerminate(script)
    if script == thisScript() then
        pcall(saveConfig)
        pcall(saveStats)
        pcall(sampUnregisterChatCommand, "rul")
    end
end
