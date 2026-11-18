script_name('OilTime')
script_author('Edward')

require 'lib.moonloader'
local imgui    = require 'mimgui'
local sampev   = require 'samp.events'
local inicfg   = require 'inicfg'
local ffi      = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local COOLDOWN       = 18
local STARTUP_IGNORE = 5
local DUP_WINDOW     = 3
local DIALOG_ID      = 502
local CFG_FILE       = 'OilTime.ini'

local SIZES      = { 0.8, 1.0, 1.35 }
local SIZE_NAMES = { 'Маленький', 'Стандарт', 'Большой' }

local cfg = inicfg.load({ main = {
    x = -1, y = -1, ix = -1, iy = -1,
    auto = 1, show = 1, icon = 1, size = 2, font = 100, isize = 68,
    kdEnd = 0, kdTotal = 1800, kdLimit = 0,
    mx = -99999, my = -99999
}, tg = {
    enabled = 0, token = '', chatId = '', onStart = 1, onEnd = 1
} }, CFG_FILE)

local V = imgui.ImVec2

local loadTime = os.clock()
local endTime  = 0
local active   = false
local bought   = 0
local pending  = false
local moveMode = false
local dirty, lastChange = false, 0

local show     = imgui.new.bool(tonumber(cfg.main.show) ~= 0)
local showIcon = imgui.new.bool(tonumber(cfg.main.icon) ~= 0)
local autoBool = imgui.new.bool(tonumber(cfg.main.auto) ~= 0)
local menu     = imgui.new.bool(false)
local fontPct  = imgui.new.int(math.min(160, math.max(70, tonumber(cfg.main.font) or 100)))
local sizeIdx  = math.min(3, math.max(1, tonumber(cfg.main.size) or 2))
local posX, posY = imgui.new.int(0), imgui.new.int(0)
local iconSize = imgui.new.int(math.min(140, math.max(40, tonumber(cfg.main.isize) or 68)))
local iposX, iposY = imgui.new.int(0), imgui.new.int(0)
local iconDrag = 0

local pos, ipos
local layout = { w = 300, h = 96 }
local fontSmall, fontBig

local function uiScale()
    local _, h = getScreenResolution()
    return math.min(2, math.max(0.8, h / 1080))
end

local function touch()
    dirty = true
    lastChange = os.clock()
end

local function trim(str)
    return (tostring(str or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function col(r, g, b, a)
    return imgui.GetColorU32Vec4(imgui.ImVec4(r / 255, g / 255, b / 255, a or 1))
end

local function vec(r, g, b, a)
    return imgui.ImVec4(r / 255, g / 255, b / 255, a or 1)
end

-- ===== КД лимита покупок (хранится как реальное время, переживает релог) =====
local kdEnd   = tonumber(cfg.main.kdEnd) or 0
local kdTotal = tonumber(cfg.main.kdTotal) or 1800
local kdLimit = tonumber(cfg.main.kdLimit) or 0     -- 0 = лимит ещё не известен (берём из сообщения сервера)
if kdEnd <= os.time() then kdEnd = 0 end
if kdTotal < 60 then kdTotal = 1800 end

local function kdLeft()
    if kdEnd <= 0 then return 0 end
    return math.max(0, kdEnd - os.time())
end

local function fmtMS(sec)
    sec = math.max(0, math.floor(sec))
    return string.format('%02d:%02d', math.floor(sec / 60), sec % 60)
end

local kdAnim, kdAnimT = 0, os.clock()
local function stepKdAnim()
    local now = os.clock()
    local dt  = math.min(0.1, now - kdAnimT)
    kdAnimT = now
    local target = kdLeft() > 0 and 1 or 0
    kdAnim = kdAnim + (target - kdAnim) * math.min(1, dt * 7)
    if math.abs(target - kdAnim) < 0.004 then kdAnim = target end
    return kdAnim * kdAnim * (3 - 2 * kdAnim)   -- smoothstep
end

-- ===== Telegram =====
local copas_ok, copas = pcall(require, 'copas')
local chttp_ok, chttp = pcall(require, 'copas.http')
local https_ok, https = pcall(require, 'ssl.https')
local tgBackend = (copas_ok and chttp_ok) and 'copas' or (https_ok and 'https' or nil)

local tgEnabled  = imgui.new.bool(tonumber(cfg.tg.enabled) ~= 0)
local tgOnStart  = imgui.new.bool(tonumber(cfg.tg.onStart) ~= 0)
local tgOnEnd    = imgui.new.bool(tonumber(cfg.tg.onEnd) ~= 0)
local tgShowTok  = imgui.new.bool(false)
local tgTokenBuf = imgui.new.char[128](tostring(cfg.tg.token or ''))
local tgChatBuf  = imgui.new.char[32](tostring(cfg.tg.chatId or ''))

local tgHelp = imgui.new.bool(false)
local tgHelpFocus = false

local tgQueue = {}
local tgStatus, tgStatusKind = '', 'info'   -- kind: info | ok | err
local tgBusy, tgStarted, tgLastSend, tgJob = false, 0, 0, 0

local function urlEnc(str)
    return (str:gsub('[^%w%-_%.~]', function(c) return string.format('%%%02X', c:byte()) end))
end

local function tgDescribe(res)
    if res:find('"ok":true', 1, true) then return true, 'Сообщение отправлено' end
    local code = tonumber(res:match('"error_code":(%d+)'))
    local desc = res:match('"description":"(.-)"') or '?'
    if code == 401 or code == 404 then return false, 'Неверный токен бота' end
    if code == 400 or code == 403 then
        return false, 'Бот не может написать вам: проверьте ID и нажмите Start у бота'
    end
    return false, 'Ошибка Telegram: ' .. desc
end

local function tgReady()
    return tgBackend ~= nil and trim(cfg.tg.token) ~= '' and trim(cfg.tg.chatId) ~= ''
end

local function tgFinish(job, ok, res)
    if job ~= tgJob then return end
    tgBusy = false
    tgLastSend = os.clock()
    if ok then
        local good, msg = tgDescribe(res)
        tgStatus, tgStatusKind = msg, good and 'ok' or 'err'
    else
        tgStatus, tgStatusKind = 'Нет связи: ' .. tostring(res), 'err'
    end
end

-- блокирующий запрос (запасной вариант, если copas не сработал)
local function tgBlocking(job, url)
    if not https_ok then return tgFinish(job, false, 'нет библиотеки ssl.https') end
    https.TIMEOUT = 8
    local ok, res = pcall(https.request, url)
    if ok and type(res) == 'string' and res ~= '' then
        tgFinish(job, true, res)
    else
        tgFinish(job, false, ok and 'нет ответа' or tostring(res))
    end
end

local function tgStart(url)
    tgJob = tgJob + 1
    local job = tgJob
    tgBusy, tgStarted = true, os.clock()
    if tgBackend == 'copas' then
        chttp.TIMEOUT = 15
        copas.addthread(function()
            local ok, body = pcall(chttp.request, url)
            if ok and type(body) == 'string' and body ~= '' then
                tgFinish(job, true, body)
            elseif job == tgJob then
                tgBlocking(job, url)
            end
        end)
    else
        tgBlocking(job, url)
    end
end

-- force = true: отправить даже если уведомления выключены (кнопка теста)
local function tgNotify(text, force)
    if not tgReady() then return false end
    if not force and tonumber(cfg.tg.enabled) == 0 then return false end
    if #tgQueue >= 10 then table.remove(tgQueue, 1) end
    table.insert(tgQueue, text)
    return true
end

-- вызывается из main(): шаг copas + очередь отправки
local function tgPump()
    if tgBusy and tgBackend == 'copas' then pcall(copas.step, 0) end
    if tgBusy and os.clock() - tgStarted > 25 then
        tgFinish(tgJob, false, 'таймаут')
    end
    if not tgBusy and #tgQueue > 0 and os.clock() - tgLastSend > 1.2 then
        local text = table.remove(tgQueue, 1)
        tgStart(string.format('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s',
            trim(cfg.tg.token), urlEnc(trim(cfg.tg.chatId)), urlEnc(text)))
    end
end

-- позиция окна меню (запоминается)
local menuX = tonumber(cfg.main.mx) or -99999
local menuY = tonumber(cfg.main.my) or -99999
local menuForce = nil

local function saveConfig()
    if pos then
        cfg.main.x = math.floor(pos.x)
        cfg.main.y = math.floor(pos.y)
    end
    if ipos then
        cfg.main.ix = math.floor(ipos.x)
        cfg.main.iy = math.floor(ipos.y)
    end
    cfg.main.auto = autoBool[0] and 1 or 0
    cfg.main.show = show[0] and 1 or 0
    cfg.main.icon = showIcon[0] and 1 or 0
    cfg.main.size = sizeIdx
    cfg.main.font = fontPct[0]
    cfg.main.isize = iconSize[0]
    cfg.main.kdEnd = kdEnd
    cfg.main.kdTotal = kdTotal
    cfg.main.kdLimit = kdLimit
    cfg.main.mx = math.floor(menuX)
    cfg.main.my = math.floor(menuY)
    cfg.tg.enabled = tgEnabled[0] and 1 or 0
    cfg.tg.onStart = tgOnStart[0] and 1 or 0
    cfg.tg.onEnd   = tgOnEnd[0] and 1 or 0
    cfg.tg.token   = trim(ffi.string(tgTokenBuf))
    cfg.tg.chatId  = trim(ffi.string(tgChatBuf))
    inicfg.save(cfg, CFG_FILE)
    dirty = false
end

local function ensurePos()
    local sw, sh = getScreenResolution()
    local ui = uiScale()
    if not pos then
        if cfg.main.x >= 0 and cfg.main.y >= 0 then
            pos = { x = cfg.main.x, y = cfg.main.y }
        else
            pos = { x = sw / 2 - 150 * ui, y = sh * 0.08 }
        end
    end
    if not ipos then
        if cfg.main.ix >= 0 and cfg.main.iy >= 0 then
            ipos = { x = cfg.main.ix, y = cfg.main.iy }
        else
            ipos = { x = 20 * ui, y = sh * 0.35 }
        end
    end
end

local function startTimer()
    if os.clock() - loadTime < STARTUP_IGNORE then return end
    if active and (endTime - os.clock()) > COOLDOWN - DUP_WINDOW then return end
    endTime = os.clock() + COOLDOWN
    active  = true
    bought  = bought + 1
end

local function isBarrelPurchase(str)
    if type(str) ~= 'string' then return false end
    return str:find('приобрели бочку', 1, true) ~= nil
        or str:find(u8:decode('приобрели бочку'), 1, true) ~= nil
end

local function stripColors(s)
    return (s:gsub('{%x%x%x%x%x%x}', ''))
end

-- ищет needle (UTF-8 или CP1251) и возвращает остаток строки после него
local function findAfter(str, needle)
    for _, n in ipairs({ needle, u8:decode(needle) }) do
        local _, e = str:find(n, 1, true)
        if e then return str:sub(e + 1) end
    end
end

-- "[Ошибка] Можно купить не более 28 бочек за 30 минут. Повторите через 24:40"
-- лимит (28, 14 и т.д.) и окно берутся прямо из сообщения сервера
local function parseLimit(str)
    if type(str) ~= 'string' then return false end
    str = stripColors(str)
    local lim  = findAfter(str, 'не более')
    local rest = findAfter(str, 'Повторите через')
    if not lim or not rest then return false end
    if not findAfter(str, 'бочек') then return false end

    local secs
    local h, m, s = rest:match('(%d+):(%d+):(%d+)')
    if h then
        secs = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    else
        m, s = rest:match('(%d+):(%d+)')
        if not m then return false end
        secs = tonumber(m) * 60 + tonumber(s)
    end

    local limit = tonumber(lim:match('%d+'))
    local mins  = tonumber((findAfter(str, 'бочек за') or ''):match('%d+'))
    return true, secs, limit, mins
end

local function handleLimit(str)
    local ok, secs, limit, mins = parseLimit(str)
    if not ok then return false end
    local wasKd = kdLeft() > 0
    kdEnd = os.time() + secs
    if limit then kdLimit = limit end
    kdTotal = (mins and mins > 0) and mins * 60 or 1800
    if kdTotal < secs then kdTotal = secs end
    active  = false
    saveConfig()
    if not wasKd and tgOnStart[0] then
        local lim = kdLimit > 0 and string.format('(%d за %d мин)', kdLimit, math.floor(kdTotal / 60)) or ''
        tgNotify(string.format('⛔ OilTime: лимит бочек достигнут %s\nКД %s, снова можно в %s',
            lim, fmtMS(secs), os.date('%H:%M', kdEnd)))
    end
    return true
end

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
    if id ~= 220 then return end
    local ok, str = pcall(readCefString, bs)
    if not ok then return end
    if handleLimit(str) then return end
    if isBarrelPurchase(str) then
        startTimer()
    end
end

function sampev.onServerMessage(color, text)
    handleLimit(text)
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if not autoBool[0] or id ~= DIALOG_ID then return end
    text = text or ''
    if text:find('бочк', 1, true) or text:find(u8:decode('бочк'), 1, true) then
        pending = true
        return false
    end
end

local function findFont(list)
    for _, p in ipairs(list) do
        if doesFileExist(p) then return p end
    end
end

local function applyStyle()
    local ui = uiScale()
    local st = imgui.GetStyle()
    st.WindowRounding   = 20 * ui
    st.FrameRounding    = 12 * ui
    st.GrabRounding     = 12 * ui
    st.WindowBorderSize = 0
    st.WindowPadding    = V(22 * ui, 20 * ui)
    st.FramePadding     = V(14 * ui, 12 * ui)
    st.ItemSpacing      = V(12 * ui, 14 * ui)
    st.GrabMinSize      = 34 * ui
    st.ScrollbarSize    = 20 * ui

    local c, C = st.Colors, imgui.Col
    c[C.WindowBg]         = vec(18, 19, 24, 0.98)
    c[C.Text]             = vec(235, 235, 240)
    c[C.FrameBg]          = vec(36, 37, 46)
    c[C.FrameBgHovered]   = vec(48, 49, 60)
    c[C.FrameBgActive]    = vec(60, 61, 74)
    c[C.CheckMark]        = vec(60, 208, 112)
    c[C.SliderGrab]       = vec(60, 208, 112)
    c[C.SliderGrabActive] = vec(245, 166, 35)
    c[C.Button]           = vec(44, 45, 56)
    c[C.ButtonHovered]    = vec(62, 64, 80)
    c[C.ButtonActive]     = vec(60, 208, 112)
    c[C.Separator]        = vec(52, 54, 66)
    c[C.Header]           = vec(44, 45, 60)
    c[C.HeaderHovered]    = vec(58, 60, 80)
    c[C.HeaderActive]     = vec(70, 72, 96)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    applyStyle()

    local atlas  = imgui.GetIO().Fonts
    local ranges = atlas:GetGlyphRangesCyrillic()
    local wd = getWorkingDirectory()

    local regular = findFont({
        wd .. '/resource/fonts/arial.ttf',
        wd .. '/resource/arial.ttf',
        '/system/fonts/Roboto-Regular.ttf',
        '/system/fonts/DroidSans.ttf',
        'C:\\Windows\\Fonts\\arial.ttf',
    })
    local bold = findFont({
        wd .. '/resource/fonts/arialbd.ttf',
        wd .. '/resource/arialbd.ttf',
        '/system/fonts/Roboto-Bold.ttf',
        'C:\\Windows\\Fonts\\arialbd.ttf',
    }) or regular

    if regular then
        fontSmall = atlas:AddFontFromFileTTF(regular, 20, nil, ranges)
        fontBig   = atlas:AddFontFromFileTTF(bold, 34, nil, ranges)
    else
        fontSmall = atlas:AddFontDefault()
        fontBig   = fontSmall
    end
end)

local function drawRing(dl, c, r, frac, color, th)
    if frac <= 0.005 then return end
    local n = math.max(2, math.floor(72 * frac))
    local a0, span = -math.pi / 2, 2 * math.pi * frac
    for i = 0, n - 1 do
        local a1 = a0 + span * (i / n)
        local a2 = a0 + span * ((i + 1) / n)
        dl:AddLine(
            V(c.x + math.cos(a1) * r, c.y + math.sin(a1) * r),
            V(c.x + math.cos(a2) * r, c.y + math.sin(a2) * r),
            color, th)
    end
end

local function ellipse(dl, cx, cy, rx, ry, color, fill)
    local n = 28
    for i = 0, n - 1 do
        local a1 = i / n * 2 * math.pi
        local a2 = (i + 1) / n * 2 * math.pi
        local p1 = V(cx + math.cos(a1) * rx, cy + math.sin(a1) * ry)
        local p2 = V(cx + math.cos(a2) * rx, cy + math.sin(a2) * ry)
        if fill then
            dl:AddTriangleFilled(V(cx, cy), p1, p2, color)
        else
            dl:AddLine(p1, p2, color, 1.2)
        end
    end
end

local function arc(dl, cx, cy, rx, ry, color, th)
    local n = 20
    for i = 0, n - 1 do
        local a1 = i / n * math.pi
        local a2 = (i + 1) / n * math.pi
        dl:AddLine(
            V(cx + math.cos(a1) * rx, cy + math.sin(a1) * ry),
            V(cx + math.cos(a2) * rx, cy + math.sin(a2) * ry),
            color, th)
    end
end

local function drawBarrel(dl, cx, cy, accU, accV, s)
    local hw, top, bot = 17 * s, cy - 19 * s, cy + 19 * s

    ellipse(dl, cx, bot + 6 * s, hw + 2 * s, 4 * s, col(0, 0, 0, 0.35), true)
    ellipse(dl, cx, bot, hw, 5 * s, col(40, 42, 46), true)
    dl:AddRectFilledMultiColor(V(cx - hw, top), V(cx + hw, bot),
        col(74, 76, 82), col(42, 44, 48), col(42, 44, 48), col(74, 76, 82))

    arc(dl, cx, cy - 8 * s,  hw, 3 * s, col(240, 240, 240), 1.6 * s)
    arc(dl, cx, cy + 12 * s, hw, 3 * s, col(240, 240, 240), 1.6 * s)

    if s >= 0.7 then
        imgui.SetWindowFontScale(0.62 * s)
        local ts = imgui.CalcTextSize('OIL')
        imgui.SetCursorScreenPos(V(cx - ts.x / 2, cy + 3 * s - ts.y / 2))
        imgui.TextColored(accV, 'OIL')
        imgui.SetWindowFontScale(1)
    end

    ellipse(dl, cx, top, hw, 5 * s, col(236, 236, 240), true)
    ellipse(dl, cx, top, hw, 5 * s, col(190, 190, 198), false)
    ellipse(dl, cx - 6 * s, top, 3.2 * s, 1.5 * s, col(28, 28, 32), true)
end

local function measure(font, scale, str)
    imgui.PushFont(font)
    imgui.SetWindowFontScale(scale)
    local s = imgui.CalcTextSize(str)
    imgui.PopFont()
    return s.x, s.y
end

local function put(font, scale, x, y, color, str)
    imgui.PushFont(font)
    imgui.SetWindowFontScale(scale)
    imgui.SetCursorScreenPos(V(x, y))
    imgui.TextColored(color, str)
    imgui.PopFont()
end

-- Оверлей таймера
imgui.OnFrame(function() return show[0] end, function(self)
    local sw, sh = getScreenResolution()
    local ui = uiScale()
    ensurePos()
    self.HideCursor = not moveMode

    local S  = ui * SIZES[sizeIdx]
    local F  = fontPct[0] / 100
    local ss = 0.9 * S * F
    local bs = 0.85 * S * F
    local left = endTime - os.clock()
    local kd   = kdLeft()
    local inKd = kd > 0
    local e    = stepKdAnim()

    if not moveMode then
        pos.x = math.max(0, math.min(pos.x, sw - layout.w))
        pos.y = math.max(0, math.min(pos.y, sh - layout.h))
    end

    imgui.SetNextWindowPos(V(pos.x, pos.y),
        moveMode and imgui.Cond.FirstUseEver or imgui.Cond.Always)
    imgui.SetNextWindowSize(V(layout.w, layout.h))

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14 * S)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(0, 0))
    imgui.PushStyleColor(imgui.Col.WindowBg, vec(23, 23, 28, 0.92))

    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
                + imgui.WindowFlags.NoScrollWithMouse
    if not moveMode then
        flags = flags + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoInputs
    end

    if imgui.Begin('##OilTimeOverlay', nil, flags) then
        local p  = imgui.GetWindowPos()
        local dl = imgui.GetWindowDrawList()
        if moveMode then pos.x, pos.y = p.x, p.y end

        local lab = inKd and 'Лимит достигнут, КД' or (active and 'Следующая бочка через' or 'Бочка готова')
        local big = inKd and fmtMS(kd)
            or (active and (string.format('%.1f', math.max(left, 0)) .. ' с') or 'Можно брать')
        local bl  = 'Куплено: ' .. bought
        local br  = moveMode and 'перемещение' or (autoBool[0] and 'авто' or 'ручн.')

        local w1, hs = measure(fontSmall, ss, 'Следующая бочка через')
        w1 = math.max(w1, (measure(fontSmall, ss, 'Лимит достигнут, КД')))
        local w2, hb = measure(fontBig, bs, 'Можно брать')
        local w3     = math.max(measure(fontBig, bs, '88.8 с'), (measure(fontBig, bs, '88:88')))
        local w4     = measure(fontSmall, ss, 'Куплено: 9999')
        local w5     = measure(fontSmall, ss, 'перемещение')
        local wr     = measure(fontSmall, ss, br)

        local tx  = 104 * S
        local nw0 = tx + math.max(w1, w2, w3, w4 + 16 * S + w5) + 18 * S
        local nh  = math.max(96 * S, 12 * S + hs + 2 * S + hb + 8 * S + hs + 12 * S)

        -- квадрат КД: плавно выезжает справа, окно расширяется вместе с ним
        local kdS = 0.7 * S * F
        local kdT = 0.72 * ss
        local wk, hk = measure(fontBig, kdS, 'КД')
        local wm, hm = measure(fontSmall, kdT, '88м')
        local q = math.max(52 * S, wk + 18 * S, wm + 18 * S, hk + hm + 16 * S)
        nh = math.max(nh, q + 16 * S)

        local nw = nw0 + (q + 10 * S) * e
        layout.w, layout.h = nw, nh

        local acc  = inKd and vec(235, 85, 85) or (active and vec(245, 166, 35) or vec(60, 208, 112))
        local accU = imgui.GetColorU32Vec4(acc)
        local center = V(p.x + 52 * S, p.y + nh / 2)
        local frac = inKd and math.min(1, math.max(0, 1 - kd / kdTotal))
            or (active and math.min(1, math.max(0, 1 - left / COOLDOWN)) or 1)

        dl:AddRectFilled(V(p.x, p.y + 14 * S), V(p.x + 4 * S, p.y + nh - 14 * S), accU, 2)
        drawRing(dl, center, 38 * S, 1, col(50, 50, 60), 3 * S)
        drawRing(dl, center, 38 * S, frac, accU, 3 * S)
        drawBarrel(dl, center.x, center.y, accU, acc, S)

        put(fontSmall, ss, p.x + tx, p.y + 12 * S, vec(170, 170, 180), lab)
        put(fontBig, bs, p.x + tx, p.y + 12 * S + hs + 2 * S,
            (active or inKd) and vec(255, 255, 255) or vec(60, 208, 112), big)

        local by = p.y + nh - 12 * S - hs
        put(fontSmall, ss, p.x + tx, by, vec(120, 120, 130), bl)
        put(fontSmall, ss, p.x + nw0 - 18 * S - wr, by,
            moveMode and vec(245, 166, 35) or (autoBool[0] and vec(60, 208, 112) or vec(120, 120, 130)), br)

        if e > 0.01 then
            local sc  = 0.6 + 0.4 * e
            local qw  = q * sc
            local qcx = p.x + nw0 - 8 * S + q / 2
            local qcy = p.y + nh / 2
            local x0, y0 = qcx - qw / 2, qcy - qw / 2
            local x1, y1 = qcx + qw / 2, qcy + qw / 2
            local rr = 10 * S * sc
            dl:AddRectFilled(V(x0, y0), V(x1, y1), col(235, 85, 85, 0.9 * e), rr)
            dl:AddRectFilled(V(x0 + 2 * S, y0 + 2 * S), V(x1 - 2 * S, y1 - 2 * S), col(40, 22, 26, 0.96 * e), rr - 1)

            local ty  = qcy - (hk + hm + 2 * S) / 2
            put(fontBig, kdS, qcx - wk / 2, ty, vec(255, 110, 110, e), 'КД')
            local mins = string.format('%dм', math.ceil(kdLeft() / 60))
            local wmm  = measure(fontSmall, kdT, mins)
            put(fontSmall, kdT, qcx - wmm / 2, ty + hk + 2 * S, vec(225, 205, 205, e), mins)
        end

        imgui.SetWindowFontScale(1)
    end
    imgui.End()

    imgui.PopStyleColor()
    imgui.PopStyleVar(2)
end)

-- Иконка-кнопка на экране (тап = меню, тянуть = переместить)
imgui.OnFrame(function() return showIcon[0] end, function(self)
    local sw, sh = getScreenResolution()
    local ui = uiScale()
    ensurePos()
    local isz = iconSize[0] * ui
    local k = isz / (68 * ui)
    local left = endTime - os.clock()
    local kd   = kdLeft()
    local inKd = kd > 0
    local e    = stepKdAnim()

    ipos.x = math.max(0, math.min(ipos.x, sw - isz))
    ipos.y = math.max(0, math.min(ipos.y, sh - isz))

    imgui.SetNextWindowPos(V(ipos.x, ipos.y), imgui.Cond.Always)
    imgui.SetNextWindowSize(V(isz, isz))

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, isz / 2)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V(0, 0))
    imgui.PushStyleColor(imgui.Col.WindowBg, vec(23, 23, 28, 0.9))

    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
                + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoMove

    if imgui.Begin('##OilTimeIcon', nil, flags) then
        local p  = imgui.GetWindowPos()
        local dl = imgui.GetWindowDrawList()

        local acc  = inKd and vec(235, 85, 85) or (active and vec(245, 166, 35) or vec(60, 208, 112))
        local accU = imgui.GetColorU32Vec4(acc)
        local c = V(p.x + isz / 2, p.y + isz / 2)
        local frac = inKd and math.min(1, math.max(0, 1 - kd / kdTotal))
            or (active and math.min(1, math.max(0, 1 - left / COOLDOWN)) or 1)

        drawRing(dl, c, isz / 2 - 5 * k * ui, 1, col(50, 50, 60), 3 * k * ui)
        drawRing(dl, c, isz / 2 - 5 * k * ui, frac, accU, 3 * k * ui)
        drawBarrel(dl, c.x, c.y, accU, acc, 0.5 * k * ui)

        -- мини-бейдж "КД" в углу иконки
        if e > 0.01 then
            local br = isz * 0.21 * (0.6 + 0.4 * e)
            local bc = V(p.x + isz * 0.76, p.y + isz * 0.24)
            dl:AddCircleFilled(bc, br, col(235, 85, 85, e), 24)
            dl:AddCircleFilled(bc, math.max(1, br - 2 * k * ui), col(40, 22, 26, e), 24)
            local tw, th = measure(fontSmall, 0.62 * k * ui, 'КД')
            put(fontSmall, 0.62 * k * ui, bc.x - tw / 2, bc.y - th / 2, vec(255, 110, 110, e), 'КД')
            imgui.SetWindowFontScale(1)
        end

        if not moveMode then
            imgui.SetCursorPos(V(0, 0))
            local clicked = imgui.InvisibleButton('##OilTimeIconBtn', V(isz, isz))
            if imgui.IsItemActive() then
                local d = imgui.GetIO().MouseDelta
                iconDrag = iconDrag + math.abs(d.x) + math.abs(d.y)
                if iconDrag > 12 * ui then
                    ipos.x = ipos.x + d.x
                    ipos.y = ipos.y + d.y
                    touch()
                end
            end
            if clicked then
                if iconDrag <= 12 * ui then menu[0] = not menu[0] end
                iconDrag = 0
            elseif not imgui.IsItemActive() then
                iconDrag = 0
            end
        end
    end
    imgui.End()

    imgui.PopStyleColor()
    imgui.PopStyleVar(2)
end)

imgui.OnFrame(function() return moveMode end, function(self)
    local sw, sh = getScreenResolution()
    local ui = uiScale()
    imgui.SetNextWindowPos(V(sw / 2, sh - 30 * ui), imgui.Cond.Always, V(0.5, 1))
    imgui.Begin('##OilTimeDone', nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize
        + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoCollapse)
    imgui.SetWindowFontScale(ui)
    if imgui.Button('Готово - закрепить', V(320 * ui, 64 * ui)) then
        moveMode = false
        saveConfig()
        menu[0] = true
    end
    imgui.End()
end)

-- ===================== МЕНЮ =====================

-- заголовок секции с цветной полоской
local function section(text, rgb)
    rgb = rgb or { 245, 166, 35 }
    local ui = uiScale()
    local p  = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    local h  = imgui.CalcTextSize('A').y
    dl:AddRectFilled(V(p.x, p.y + 1 * ui), V(p.x + 5 * ui, p.y + h - 1 * ui), col(rgb[1], rgb[2], rgb[3]), 2)
    imgui.SetCursorScreenPos(V(p.x + 14 * ui, p.y))
    imgui.TextColored(vec(175, 178, 195), text)
end

-- прокрутка перетаскиванием (тач) + защита от случайных нажатий после скролла
local function newScroller()
    return { track = false, scrolled = false, wasDown = false, startY = 0, held = false }
end
local menuScroll, helpScroll = newScroller(), newScroller()

local function btn(label, size)
    local r = imgui.Button(label, size)
    return r and not menuScroll.scrolled
end

local function chk(label, v)
    local r = imgui.Checkbox(label, v)
    return r and not menuScroll.scrolled
end

local function sld(label, v, mn, mx, fmt)
    local r = imgui.SliderInt(label, v, mn, mx, fmt)
    if imgui.IsItemActive() then menuScroll.held = true end
    return r
end

local function scrollUpdate(sc, ui, blocked)
    local down = imgui.IsMouseDown(0)
    if not down then
        if not sc.wasDown then sc.scrolled = false end
        sc.track = false
    end
    sc.wasDown = down

    if sc.held or blocked then sc.track = false end

    if imgui.IsMouseClicked(0) and imgui.IsWindowHovered() and not sc.held and not blocked then
        local mp, wp, ws = imgui.GetMousePos(), imgui.GetWindowPos(), imgui.GetWindowSize()
        local sbX = wp.x + ws.x - imgui.GetStyle().ScrollbarSize - 4 * ui
        if mp.x < sbX then
            sc.track = true
            sc.scrolled = false
            sc.startY = mp.y
        end
    end

    if sc.track and down then
        local mp = imgui.GetMousePos()
        if sc.scrolled or math.abs(mp.y - sc.startY) > 10 * ui then
            sc.scrolled = true
            imgui.SetScrollY(imgui.GetScrollY() - imgui.GetIO().MouseDelta.y)
        end
    end
end

-- Красивая карточка "Статус покупки"
local function drawStatusCard(ui)
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    local W  = imgui.GetContentRegionAvail().x
    local H  = 150 * ui

    local kd   = kdLeft()
    local left = endTime - os.clock()
    local state = (kd > 0) and 'kd' or ((active and left > 0) and 'cd' or 'ready')

    local rgb = ({ kd = { 235, 85, 85 }, cd = { 245, 166, 35 }, ready = { 60, 208, 112 } })[state]
    local accU    = col(rgb[1], rgb[2], rgb[3])
    local accBord = col(rgb[1], rgb[2], rgb[3], 0.85)
    local accSoft = col(rgb[1], rgb[2], rgb[3], 0.18)

    local limTxt = kdLimit > 0 and string.format('Лимит: %d бочек за %d мин.', kdLimit, math.floor(kdTotal / 60)) or nil

    local title, sub, l2, l3, frac
    if state == 'kd' then
        title = 'Идёт КД'
        sub   = limTxt or 'Лимит покупок достигнут.'
        l2    = 'через ' .. fmtMS(kd)
        l3    = string.format('КД: %d / %d мин.', math.ceil(kd / 60), math.floor(kdTotal / 60))
        frac  = math.min(1, math.max(0, 1 - kd / kdTotal))
    elseif state == 'cd' then
        title = 'Перезарядка'
        sub   = limTxt or 'Следующая бочка совсем скоро.'
        l2    = 'через ' .. string.format('%.1f с', math.max(left, 0))
        l3    = 'Куплено: ' .. bought
        frac  = math.min(1, math.max(0, 1 - left / COOLDOWN))
    else
        title = 'Можно купить!'
        sub   = limTxt or 'Покупка доступна прямо сейчас.'
        l2    = 'сейчас'
        l3    = 'Куплено: ' .. bought
        frac  = 1
    end

    local hs, hb, hm, hh = 0.9 * ui, 0.95 * ui, 0.8 * ui, 0.62 * ui

    local l1 = 'Следующая покупка:'
    local w1, h1 = measure(fontSmall, hs, l1)
    local w2, h2 = measure(fontBig, hm, l2)
    local w3, h3 = measure(fontSmall, hs, l3)
    local rcw = math.max(w1, w2, w3, (measure(fontBig, hm, 'через 88:88'))) + 40 * ui
    rcw = math.min(rcw, W * 0.5)

    local p2 = V(p.x + W, p.y + H)
    dl:AddRectFilled(p, p2, accBord, 18 * ui)
    dl:AddRectFilled(V(p.x + 2 * ui, p.y + 2 * ui), V(p2.x - 2 * ui, p2.y - 2 * ui), col(12, 14, 18), 16 * ui)

    put(fontBig, hh, p.x + 22 * ui, p.y + 14 * ui, vec(240, 240, 245), 'Статус покупки')

    local c = V(p.x + 58 * ui, p.y + 94 * ui)
    dl:AddCircleFilled(c, 31 * ui, accSoft, 40)
    drawRing(dl, c, 31 * ui, 1, accU, 2.5 * ui)
    if state == 'ready' then
        dl:AddLine(V(c.x - 12 * ui, c.y + 1 * ui), V(c.x - 4 * ui, c.y + 10 * ui), accU, 4 * ui)
        dl:AddLine(V(c.x - 4 * ui, c.y + 10 * ui), V(c.x + 13 * ui, c.y - 9 * ui), accU, 4 * ui)
    else
        dl:AddLine(c, V(c.x, c.y - 15 * ui), accU, 3.5 * ui)
        dl:AddLine(c, V(c.x + 11 * ui, c.y + 6 * ui), accU, 3.5 * ui)
        dl:AddCircleFilled(c, 3 * ui, accU, 12)
    end

    local tx = p.x + 108 * ui
    local _, tbh = measure(fontBig, hb, title)
    put(fontBig, hb, tx, p.y + 68 * ui, vec(rgb[1], rgb[2], rgb[3]), title)
    put(fontSmall, hs, tx, p.y + 68 * ui + tbh + 6 * ui, vec(165, 165, 175), sub)

    local rx, ry = p.x + W - rcw - 16 * ui, p.y + 16 * ui
    local rh = H - 32 * ui
    dl:AddRectFilled(V(rx, ry), V(rx + rcw, ry + rh), col(112, 78, 196, 0.9), 14 * ui)
    dl:AddRectFilled(V(rx + 2 * ui, ry + 2 * ui), V(rx + rcw - 2 * ui, ry + rh - 2 * ui), col(34, 26, 64), 12 * ui)

    local ix = rx + 20 * ui
    put(fontSmall, hs, ix, ry + 12 * ui, vec(205, 195, 235), l1)
    put(fontBig, hm, ix, ry + 12 * ui + h1 + 4 * ui, vec(255, 255, 255), l2)

    local by   = ry + rh - 12 * ui - h3
    local barY = by - 12 * ui
    local barW = rcw - 40 * ui
    dl:AddRectFilled(V(ix, barY), V(ix + barW, barY + 6 * ui), col(64, 52, 100), 3 * ui)
    if frac > 0.01 then
        dl:AddRectFilled(V(ix, barY), V(ix + barW * frac, barY + 6 * ui), col(176, 120, 255), 3 * ui)
    end
    put(fontSmall, hs, ix, by, vec(160, 150, 195), l3)

    imgui.SetWindowFontScale(ui)
    imgui.SetCursorScreenPos(p)
    imgui.Dummy(V(W, H))
end

local function tgApply()
    cfg.tg.token   = trim(ffi.string(tgTokenBuf))
    cfg.tg.chatId  = trim(ffi.string(tgChatBuf))
    cfg.tg.enabled = tgEnabled[0] and 1 or 0
    touch()
end

-- вставка из буфера обмена в поле ввода
local function pasteInto(buf, size)
    local ok, txt = pcall(imgui.GetClipboardText)
    txt = ok and trim(txt) or ''
    if txt == '' then
        tgStatus, tgStatusKind = 'Буфер обмена пуст - сначала скопируйте значение', 'err'
        return
    end
    ffi.fill(buf, size, 0)
    ffi.copy(buf, txt:sub(1, size - 1))
    tgApply()
    tgStatus, tgStatusKind = 'Вставлено из буфера обмена', 'info'
end

local function drawTelegram(ui, BH, sp)
    if tgBackend == nil then
        imgui.TextColored(vec(235, 85, 85), 'Не найдены сетевые библиотеки (copas / ssl.https) - отправка недоступна')
    end

    if chk('Отправлять уведомления в Telegram', tgEnabled) then tgApply() end

    local isz = 52 * ui
    imgui.SameLine(imgui.GetWindowWidth() - imgui.GetStyle().WindowPadding.x - isz)
    local helpOn = tgHelp[0]
    if helpOn then imgui.PushStyleColor(imgui.Col.Button, vec(112, 78, 196)) end
    if btn('i##tghelp', V(isz, isz)) then
        tgHelp[0] = not tgHelp[0]
        if tgHelp[0] then tgHelpFocus = true end
    end
    if helpOn then imgui.PopStyleColor() end

    local avail = imgui.GetContentRegionAvail().x
    local pw = 200 * ui
    local iw = avail - pw - sp

    imgui.PushItemWidth(iw)
    local tflags = tgShowTok[0] and 0 or imgui.InputTextFlags.Password
    if imgui.InputTextWithHint('##tgtoken', 'Токен бота (выдаёт @BotFather)', tgTokenBuf, 128, tflags) then tgApply() end
    imgui.PopItemWidth()
    imgui.SameLine()
    if btn('Вставить##pt', V(pw, BH)) then pasteInto(tgTokenBuf, 128) end

    imgui.PushItemWidth(iw)
    if imgui.InputTextWithHint('##tgchat', 'Ваш Telegram ID (узнать у @userinfobot)', tgChatBuf, 32) then tgApply() end
    imgui.PopItemWidth()
    imgui.SameLine()
    if btn('Вставить##pc', V(pw, BH)) then pasteInto(tgChatBuf, 32) end

    local chat = trim(ffi.string(tgChatBuf))
    if chat ~= '' and not chat:match('^%-?%d+$') then
        imgui.TextColored(vec(245, 166, 35), 'ID должен состоять только из цифр')
    end

    if chk('Показать токен', tgShowTok) then end
    imgui.SameLine()
    if chk('КД начался', tgOnStart) then touch() end
    imgui.SameLine()
    if chk('КД закончился', tgOnEnd) then touch() end

    if btn('Отправить тест##tgtest', V(300 * ui, BH)) then
        tgApply()
        if tgBackend == nil then
            tgStatus, tgStatusKind = 'Нет сетевых библиотек', 'err'
        elseif not tgReady() then
            tgStatus, tgStatusKind = 'Укажите токен бота и свой ID', 'err'
        else
            tgStatus, tgStatusKind = 'Отправляю...', 'info'
            tgNotify('✅ OilTime: тестовое уведомление. Всё работает!', true)
        end
    end
    imgui.SameLine()
    local c = (tgStatusKind == 'ok' and vec(60, 208, 112))
        or (tgStatusKind == 'err' and vec(235, 85, 85)) or vec(150, 150, 165)
    imgui.TextColored(c, tgStatus ~= '' and tgStatus or 'Сначала откройте своего бота и нажмите Start')
end

local SIZE_SHORT = { 'Малый', 'Станд.', 'Большой' }

imgui.OnFrame(function() return menu[0] and not moveMode end, function(self)
    local sw, sh = getScreenResolution()
    local ui = uiScale()
    ensurePos()
    local W  = math.min(1180 * ui, sw * 0.97)
    local BH = 52 * ui

    if menuForce then
        imgui.SetNextWindowPos(V(menuForce.x, menuForce.y), imgui.Cond.Always)
        menuForce = nil
    elseif menuX > -90000 and menuY > -90000 then
        imgui.SetNextWindowPos(V(menuX, menuY), imgui.Cond.Appearing)
    else
        imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    end
    imgui.SetNextWindowSizeConstraints(V(W, 0), V(W, sh * 0.98))

    if imgui.Begin('##OilTimeMenu', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize
        + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove) then
        imgui.SetWindowFontScale(ui)
        menuScroll.held = false

        local winW = imgui.GetWindowWidth()
        local pad  = imgui.GetStyle().WindowPadding
        local sp   = imgui.GetStyle().ItemSpacing.x

        -- не даём утащить меню за пределы экрана, запоминаем позицию
        local mp, ms = imgui.GetWindowPos(), imgui.GetWindowSize()
        local nx = math.max(100 * ui - ms.x, math.min(mp.x, sw - 100 * ui))
        local ny = math.max(0, math.min(mp.y, sh - 60 * ui))
        if math.abs(nx - mp.x) > 0.5 or math.abs(ny - mp.y) > 0.5 then
            menuForce = { x = nx, y = ny }
        end
        if math.abs(nx - menuX) > 0.5 or math.abs(ny - menuY) > 0.5 then
            menuX, menuY = nx, ny
            touch()
        end

        -- шапка (за неё можно перетаскивать меню)
        local hdrStart = imgui.GetCursorPos()
        imgui.PushFont(fontBig)
        imgui.TextColored(vec(245, 166, 35), 'OilTime')
        imgui.PopFont()
        imgui.TextColored(vec(120, 120, 130), 'Таймер покупки бочек нефти  |  By Edward  |  заголовок можно перетаскивать')
        local afterHeader = imgui.GetCursorPos()

        local xs = 56 * ui
        imgui.SetCursorPos(hdrStart)
        imgui.InvisibleButton('##OilTimeHdr', V(math.max(10, winW - 2 * pad.x - xs - sp), afterHeader.y - hdrStart.y))
        local hdrHeld = imgui.IsItemActive()
        if hdrHeld then
            local d = imgui.GetIO().MouseDelta
            if d.x ~= 0 or d.y ~= 0 then
                menuForce = { x = mp.x + d.x, y = mp.y + d.y }
            end
        end

        imgui.SetCursorPos(V(winW - pad.x - xs, pad.y - 4 * ui))
        imgui.PushStyleColor(imgui.Col.Button, vec(150, 45, 45))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, vec(190, 60, 60))
        imgui.PushStyleColor(imgui.Col.ButtonActive, vec(220, 70, 70))
        if btn('X##OilTimeClose', V(xs, xs)) then
            menu[0] = false
            saveConfig()
        end
        imgui.PopStyleColor(3)
        imgui.SetCursorPos(afterHeader)
        imgui.Separator()

        drawStatusCard(ui)
        imgui.Separator()

        imgui.Columns(3, '##OilTimeCols', false)

        local aw = imgui.GetContentRegionAvail().x
        section('Основное', { 60, 208, 112 })
        if chk('Показывать таймер', show) then touch() end
        if chk('Иконка на экране', showIcon) then touch() end
        if chk('Автопокупка бочки', autoBool) then
            if not autoBool[0] then pending = false end
            touch()
        end
        imgui.Separator()

        section('Размер окна')
        local bw = (aw - 2 * sp) / 3
        for i = 1, 3 do
            if i > 1 then imgui.SameLine() end
            local sel = sizeIdx == i
            if sel then imgui.PushStyleColor(imgui.Col.Button, vec(40, 160, 90)) end
            if btn(SIZE_SHORT[i] .. '##sz' .. i, V(bw, BH)) then
                sizeIdx = i
                touch()
            end
            if sel then imgui.PopStyleColor() end
        end

        section('Размер шрифта')
        imgui.PushItemWidth(-1)
        if sld('##font', fontPct, 70, 160, '%d%%') then touch() end
        imgui.PopItemWidth()

        imgui.NextColumn()
        section('Позиция таймера', { 112, 150, 255 })
        posX[0], posY[0] = math.floor(pos.x), math.floor(pos.y)
        imgui.PushItemWidth(-1)
        if sld('##px', posX, 0, sw, 'X: %d') then pos.x = posX[0]; touch() end
        if sld('##py', posY, 0, sh, 'Y: %d') then pos.y = posY[0]; touch() end
        imgui.PopItemWidth()
        if btn('Двигать таймер', V(-1, BH)) then
            show[0] = true
            moveMode = true
            menu[0] = false
        end
        if btn('Сбросить позицию', V(-1, BH)) then
            pos = { x = sw / 2 - 150 * ui, y = sh * 0.08 }
            touch()
        end

        imgui.NextColumn()
        section('Кнопка меню (иконку можно таскать)', { 176, 120, 255 })
        imgui.PushItemWidth(-1)
        if sld('##isz', iconSize, 40, 140, 'Размер: %d') then touch() end
        iposX[0], iposY[0] = math.floor(ipos.x), math.floor(ipos.y)
        if sld('##ipx', iposX, 0, sw, 'X: %d') then ipos.x = iposX[0]; touch() end
        if sld('##ipy', iposY, 0, sh, 'Y: %d') then ipos.y = iposY[0]; touch() end
        imgui.PopItemWidth()
        if btn('Сбросить кнопку', V(-1, BH)) then
            ipos = { x = 20 * ui, y = sh * 0.35 }
            iconSize[0] = 68
            touch()
        end

        imgui.Columns(1)
        imgui.Separator()

        section('Telegram уведомления', { 112, 150, 255 })
        drawTelegram(ui, BH, sp)
        imgui.Separator()

        local fw = imgui.GetContentRegionAvail().x
        local hw = (fw - 2 * sp) / 3
        if btn('Обнулить счётчик', V(hw, BH)) then bought = 0 end
        imgui.SameLine()
        if btn('Сбросить КД', V(hw, BH)) then
            kdEnd = 0
            saveConfig()
        end
        imgui.SameLine()
        if btn('Закрыть', V(hw, BH)) then
            menu[0] = false
            saveConfig()
        end

        scrollUpdate(menuScroll, ui, hdrHeld)
        imgui.SetWindowFontScale(1)
    end
    imgui.End()
end)

-- Справка: как создать бота, найти токен и ID
imgui.OnFrame(function() return tgHelp[0] and menu[0] and not moveMode end, function(self)
    local sw, sh = getScreenResolution()
    local ui = uiScale()
    local W  = math.min(900 * ui, sw * 0.97)

    imgui.SetNextWindowPos(V(sw / 2, sh / 2), imgui.Cond.Appearing, V(0.5, 0.5))
    imgui.SetNextWindowSizeConstraints(V(W, 0), V(W, sh * 0.96))
    if tgHelpFocus then
        imgui.SetNextWindowFocus()
        tgHelpFocus = false
    end

    if imgui.Begin('##OilTimeHelp', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize
        + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove) then
        imgui.SetWindowFontScale(ui)
        helpScroll.held = false

        local winW = imgui.GetWindowWidth()
        local pad  = imgui.GetStyle().WindowPadding

        imgui.PushFont(fontBig)
        imgui.TextColored(vec(112, 150, 255), 'Как настроить Telegram')
        imgui.PopFont()

        local xs = 56 * ui
        local afterHeader = imgui.GetCursorPos()
        imgui.SetCursorPos(V(winW - pad.x - xs, pad.y - 4 * ui))
        imgui.PushStyleColor(imgui.Col.Button, vec(150, 45, 45))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, vec(190, 60, 60))
        imgui.PushStyleColor(imgui.Col.ButtonActive, vec(220, 70, 70))
        if imgui.Button('X##OilTimeHelpClose', V(xs, xs)) and not helpScroll.scrolled then tgHelp[0] = false end
        imgui.PopStyleColor(3)
        imgui.SetCursorPos(afterHeader)
        imgui.Separator()

        local function head(t) imgui.TextColored(vec(245, 166, 35), t) end
        local function line(t)
            imgui.PushStyleColor(imgui.Col.Text, vec(220, 220, 228))
            imgui.TextWrapped(t)
            imgui.PopStyleColor()
        end

        head('1. Создать бота и получить токен')
        line('- В Telegram найдите @BotFather (с синей галочкой), нажмите Start и отправьте /newbot.')
        line('- Введите любое имя, затем username - он должен заканчиваться на bot (например oil_edward_bot).')
        line('- BotFather пришлёт токен вида 123456789:AAH-xxxx. Скопируйте его целиком и нажмите "Вставить" рядом с полем токена.')

        imgui.Separator()
        head('2. Узнать свой Telegram ID')
        line('- Найдите @userinfobot (или @getmyid_bot), нажмите Start. Строка Id в ответе - ваш ID (только цифры). Скопируйте и нажмите "Вставить" рядом с полем ID.')

        imgui.Separator()
        head('3. Запустить своего бота (обязательно)')
        line('- Откройте СВОЕГО бота по ссылке t.me/ваш_username и нажмите Start. Пока вы этого не сделали, бот не сможет вам писать.')

        imgui.Separator()
        head('4. Проверка')
        line('- Включите галочку и нажмите "Отправить тест". В Telegram придёт сообщение, а рядом с кнопкой появится "Сообщение отправлено".')

        imgui.Separator()
        head('Если не работает')
        line('- "Неверный токен бота" - токен скопирован не полностью.')
        line('- "Бот не может написать вам" - неверный ID или не нажат Start у своего бота.')
        line('- "Нет связи" - проверьте интернет.')

        imgui.Separator()
        imgui.TextColored(vec(235, 85, 85), 'Никому не показывайте токен.')
        imgui.TextColored(vec(120, 120, 130), 'Уведомления приходят, только пока запущена игра. Окно можно листать пальцем.')

        local fw = imgui.GetContentRegionAvail().x
        if imgui.Button('Понятно##helpok', V(fw, 60 * ui)) and not helpScroll.scrolled then tgHelp[0] = false end

        scrollUpdate(helpScroll, ui, false)
        imgui.SetWindowFontScale(1)
    end
    imgui.End()
end)

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() then saveConfig() end
end

function main()
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand('oiltime', function()
        menu[0] = not menu[0]
    end)

    sampRegisterChatCommand('oilmove', function()
        show[0] = true
        moveMode = true
        menu[0] = false
    end)

    sampRegisterChatCommand('oilauto', function()
        autoBool[0] = not autoBool[0]
        if not autoBool[0] then pending = false end
        touch()
        sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}автопокупка '
            .. (autoBool[0] and '{00FF00}ВКЛ' or '{FF0000}ВЫКЛ')), -1)
    end)

    sampRegisterChatCommand('oilkd', function()
        local kd = kdLeft()
        if kd > 0 then
            sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}КД: {FF5555}' .. fmtMS(kd)
                .. (kdLimit > 0 and ('  {c0c0c0}(лимит ' .. kdLimit .. ' бочек)') or '')), -1)
        else
            sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}КД нет - {3CD070}можно покупать'), -1)
        end
    end)

    sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}загружен  {c0c0c0}/oiltime {FFFFFF}- открыть меню'), -1)
    sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}команда  {c0c0c0}/oilmove {FFFFFF}- переместить таймер'), -1)
    sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}команда  {c0c0c0}/oilauto {FFFFFF}- вкл/выкл автопокупку, {c0c0c0}/oilkd {FFFFFF}- узнать КД {FF0000}By {00FFFF}Edward'), -1)

    while true do
        wait(30)
        if active and os.clock() >= endTime then
            active = false
        end
        tgPump()
        if not menu[0] then tgHelp[0] = false end
        if kdEnd > 0 and os.time() >= kdEnd then
            kdEnd = 0
            saveConfig()
            sampAddChatMessage(u8:decode('{FF0000}|{FFFF00} OilTime {FFFFFF}КД закончился - {3CD070}можно покупать бочки'), -1)
            if tgOnEnd[0] then tgNotify('✅ OilTime: КД закончился, можно покупать бочки!') end
        end
        if pending and autoBool[0] and not active then
            pending = false
            sampSendDialogResponse(DIALOG_ID, 1, -1, '')
        end
        if dirty and os.clock() - lastChange > 1 then
            saveConfig()
        end
    end
end
