script_name('MissGuard(Мисс Охранник) Mobile')
script_version('8.2-mobile')

require 'lib.moonloader'
local imgui    = require 'mimgui'
local inicfg   = require 'inicfg'
local sampev   = require 'samp.events'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new = imgui.new

local clock = os.clock
if type(getGameTimer) == 'function' then
    local okt, tv = pcall(getGameTimer)
    if okt and type(tv) == 'number' then clock = function() return getGameTimer() / 1000 end end
end

local PK = { IN_SUB = 84, OUT_SUB = 63, inLayout = nil, inSeen = 0, inOk = 0, inFail = 0,
             tpl = nil, ring = {}, ringIn = 0, learned = false }
function PK.hex(s) return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end)) end
function PK.unhex(h) return (h:gsub('%x%x', function(x) return string.char(tonumber(x, 16)) end)) end
PK.win = {}
PK.tpls, PK.idKeys = {}, {}
function PK.encTpl(t) return t and ('x' .. PK.hex(t.prefix) .. ':' .. PK.hex(t.tail) .. ':' .. t.lenOff) or '' end
function PK.decTpl(s)
    if type(s) ~= 'string' then return nil end
    local p, t, o = s:match('^x(%x*):(%x*):(%d+)$')
    if not p or #p < 6 then return nil end
    return { prefix = PK.unhex(p), tail = PK.unhex(t), lenOff = tonumber(o), lenSize = 2 }
end

local INVENT_CMD       = '/invent'
local MAX_FEEDS        = 20
local DIALOG_GUARD     = 1628
local INI_NAME         = 'MissGuard.ini'
local STARTUP_DELAY    = 30
local STARVE_WAIT      = 5
local AUTO_SPAWN_BELOW = 25
local FEED_PAUSE       = 6.5
local DRAIN_MIN        = 3
local RETRY_SEC        = 300
local RETRY_NOFOOD     = 600
local THRESHOLDS       = { 10, 20, 30, 40, 50, 60, 70, 80, 90 }

local FOODS = {
    { id = 18,  name = 'Чипсы' },
    { id = 203, name = 'Большой бургер' },
    { id = 204, name = 'Средний бургер' },
    { id = 205, name = 'Маленький бургер' },
    { id = 206, name = 'Большая картошка' },
    { id = 207, name = 'Маленькая картошка' },
    { id = 208, name = 'Кола' },
    { id = 209, name = 'Куриный шашлык' },
    { id = 210, name = 'Свиной шашлык' },
    { id = 211, name = 'Говяжий стейк' },
    { id = 212, name = 'Лимонад' },
    { id = 0,   name = 'Любая' },
}
local FOOD_BY_ID = {}
for _, f in ipairs(FOODS) do if f.id > 0 then FOOD_BY_ID[f.id] = f end end

local ini = inicfg.load({
    main = {
        threshold = 50,
        hideNoFood = true, hideBelow = 25, watch = 30,
        autoStart = true, prefId = -1, food = 203, hiddenNoFood = false, agent = true, agentSound = true,
        scriptOn = true, autoSpawn = true, hidePackets = true,
        uiScale = 90, fontMul = 100, lockWin = true, agentScale = 100, agentCps = 30, agentVol = 45, agentCorner = 0,
        tplUse = '', tplSel = '', tplClk = '', chatLog = false, autoFeed = true,
    }
}, INI_NAME)

if (tonumber(ini.main.uiScale) or 0) <= 80 then ini.main.uiScale = 90 end
local hiddenNoFood = ini.main.hiddenNoFood and true or false

local S = {
    threshold  = new.int(ini.main.threshold),
    hideNoFood = new.bool(ini.main.hideNoFood),
    hideBelow  = new.int(ini.main.hideBelow),
    watch      = new.int(ini.main.watch),
    autoStart  = new.bool(ini.main.autoStart),
    prefId     = new.int(ini.main.prefId),
    food       = new.int(ini.main.food),
    agent      = new.bool(ini.main.agent),
    agentSound = new.bool(ini.main.agentSound),
    scriptOn   = new.bool(ini.main.scriptOn ~= false),
    autoSpawn  = new.bool(ini.main.autoSpawn ~= false),
    hidePkts   = new.bool(ini.main.hidePackets ~= false),
    uiScale    = new.int(ini.main.uiScale or 90),
    fontMul    = new.int(ini.main.fontMul or 100),
    lockWin    = new.bool(ini.main.lockWin ~= false),
    agentScale = new.int(ini.main.agentScale or 100),
    agentCps   = new.int(ini.main.agentCps or 30),
    agentVol   = new.int(ini.main.agentVol or 45),
    agentCorner= new.int(ini.main.agentCorner or 0),
    autoFeed   = new.bool(ini.main.autoFeed ~= false),
    chatLog    = new.bool(ini.main.chatLog == true),
}
do
    PK.tpls.use = PK.decTpl(ini.main.tplUse)
    PK.tpls.sel = PK.decTpl(ini.main.tplSel)
    PK.tpls.clk = PK.decTpl(ini.main.tplClk)
end
S.hideUntil = 0
local dirty = false
local function saveIni()
    local m = ini.main
    m.threshold = S.threshold[0]
    m.hideNoFood = S.hideNoFood[0]
    m.hideBelow, m.watch, m.autoStart = S.hideBelow[0], S.watch[0], S.autoStart[0]
    m.prefId, m.food = S.prefId[0], S.food[0]
    m.agent, m.agentSound = S.agent[0], S.agentSound[0]
    m.scriptOn, m.autoSpawn, m.hidePackets = S.scriptOn[0], S.autoSpawn[0], S.hidePkts[0]
    m.hiddenNoFood = hiddenNoFood
    m.uiScale, m.fontMul, m.lockWin = S.uiScale[0], S.fontMul[0], S.lockWin[0]
    m.chatLog = S.chatLog[0]
    m.autoFeed = S.autoFeed[0]
    m.agentScale, m.agentCps, m.agentVol, m.agentCorner = S.agentScale[0], S.agentCps[0], S.agentVol[0], S.agentCorner[0]
    m.tplUse, m.tplSel, m.tplClk = PK.encTpl(PK.tpls.use), PK.encTpl(PK.tpls.sel), PK.encTpl(PK.tpls.clk)
    inicfg.save(ini, INI_NAME)
    dirty = false
end

local guard, satiety, health = nil, nil, nil
local guards = {}
local maxHealth = {}
local foodSlots = {}
local selfSend, busy = false, false
local invOpen = false
local cycle, enabled = false, true
local nextRun, nextWatch = 0, 0
local satStamp = 0
local starving = false
local invStamp, visibleStamp, errStamp, farStamp = 0, 0, 0, 0
local selStamp = 0
local foodStamp = 0
local feedAck, notifStamp = 0, 0
local dialogWant, dialogDone = nil, false
local needStartup, startupAt = false, 0
local startupTries = 0
local win = new.bool(false)

local CHAT_LOG = false
local function msg(t)
    if not (CHAT_LOG or S.chatLog[0]) then return end
    sampAddChatMessage(u8:decode('{FF8A1F}[Auto Guard Feeder]{FFFFFF} ' .. t), -1)
end

local AGENT_MOOD = { 'good', 'good', 'ask', 'good', 'ask', 'ask', 'bad', 'bad', 'good', 'ask', 'bad', 'good' }
local AGENT_LINES = {
    'Привет! Я Мисс Минутка. Сейчас я проверю твой инвентарь, чтобы понять, есть ли охранник и еда.',
    'Всё идёт по плану! Охранника покормлю вовремя.',
    'Хм... Еды маловато. Я за тобой слежу.',
    'Ура! Охранник сыт и доволен!',
    'Ой! Охранник слишком далеко. Прячу его и зову заново!',
    'Так, а что у нас с едой? Секундочку, проверяю инвентарь...',
    'Сервер ругается! Кормить можно только раз в несколько секунд, подожду.',
    'Еда закончилась... Охраннику придётся поголодать.',
    'Всё под контролем. Охранник заспавнен, можно отдыхать.',
    'Ждём... Сервер отвечает не сразу, потерпи ещё немного.',
    'Ай! Что-то пошло не так. Смотри чат.',
    'Меняю охранников: прячу текущего и зову выбранного!',
}
local AGENT_INTRO = {
    startup   = { 1, 'Привет! Сейчас я проверяю твой инвентарь, чтобы понять, есть ли охранник и сколько у него еды.' },
    start     = { 2, 'Включаю авто-кормление. Слежу за сытостью охранника!' },
    scan      = { 6, 'Секундочку, смотрю инвентарь...' },
    now       = { 4, 'Кормлю охранника прямо сейчас!' },
    swap      = { 12, 'Меняю охранника: прячу текущего и зову выбранного.' },
    hide      = { 10, 'Прячу охранника...' },
    autocheck = { 6, 'Проверяю, нужен ли авто-спавн...' },
}
local agent = { q = {}, cur = nil, slide = 0, last = 0, emo = 1, pos = 1 }

local function agentSay(emo, text, now)
    local it = { emo = emo, text = text }
    if now or not agent.cur then
        agent.q = {}
        it.t0 = clock()
        agent.cur = it
    else
        agent.q[#agent.q + 1] = it
    end
end

local function agentNote(emo, text)
    if S.agent[0] then agentSay(emo, text, true) end
end

local noFoodMsg = nil
local function agentFinish(mode, ok, fed)
    local nf = noFoodMsg noFoodMsg = nil
    local sat = satiety and tostring(math.floor(satiety + 0.5)) or '?'
    if ok and nf then
        if fed and fed > 0 then
            agentSay(8, string.format('Покормила %d раз(а), но еда закончилась (%s). Сытость: %s%%.', fed, nf, sat), true)
        else
            agentSay(8, 'В инвентаре нет еды (' .. nf .. '). Покормить охранника не удалось.', true)
        end
        return
    end
    if not S.agent[0] then return end
    if not ok then agentSay(11, AGENT_LINES[11], true) return end
    if fed and fed > 0 then
        agentSay(4, string.format('Готово! Покормила охранника: %d раз(а). Сытость: %s%%.', fed, sat), true)
        return
    end
    if starving then agentSay(8, AGENT_LINES[8], true) return end
    if mode == 'feed' then return end
    if mode == 'hide' and not guard then agentSay(10, 'Охранник спрятан.', true) return end
    if guard then
        agentSay(9, string.format('Охранник на месте. Сытость: %s%%.', sat), true)
    else
        agentSay(3, 'Охранника сейчас нет. Выбери его в меню, и я заспавню.', true)
    end
end

local function estSatiety()
    if not satiety then return nil end
    return math.max(0, satiety - (clock() - satStamp) / (DRAIN_MIN * 60))
end

local function scheduleNext(fresh, minDelay)
    local now = clock()
    local est = estSatiety()
    local d, calc
    if not fresh or not est then
        d = RETRY_SEC
    elseif starving then
        d = RETRY_NOFOOD
    else
        d = math.max(minDelay or 60, (est - S.threshold[0]) * DRAIN_MIN * 60)
        calc = true
    end
    nextRun = now + d
    return d, calc
end

function PK.writeRaw(bs, s)
    for i = 1, #s do raknetBitStreamWriteInt8(bs, s:byte(i)) end
end
function PK.patchLen(pre, off, size, val)
    local t = {}
    for i = 1, #pre do t[i] = pre:byte(i) end
    for k = 1, size do
        t[off + k] = val % 256
        val = math.floor(val / 256)
    end
    local out = {}
    for i = 1, #t do out[i] = string.char(t[i]) end
    return table.concat(out)
end
function PK.getTpl(role)
    return PK.tpls[role] or PK.tpls.sel or PK.tpls.clk or PK.tpls.use
end
function PK.hdr(win, len, ev)
    return string.char(220, 63, win, 255, 255, 255, 255, ev or 0, 0, 0, 0, len % 256, math.floor(len / 256))
end
local function sendCef(evt)
    local name, json = evt:match('^([%w_]+)|?(.*)$')
    local role
    if name == 'useItemOnSecurity' then role = 'use'
    elseif name == 'selectSecurity' then role = 'sel'
    elseif name == 'clickOnMenu' then role = 'clk'
    elseif name == 'requestShowingInventory' then role = 'tab40'
    elseif name == 'requestInventoryTab' then role = 'tab34'
    elseif name == 'openInventory' then role = 'open'
    else
        return false
    end
    local bs = raknetNewBitStream()
    if role == 'tab40' then
        PK.writeRaw(bs, PK.hdr(0x40, 0))
    elseif role == 'tab34' then
        PK.writeRaw(bs, PK.hdr(0x34, 2) .. '""')
    elseif role == 'open' then
        local tpl = PK.tpls.open
        if tpl then PK.writeRaw(bs, tpl.prefix .. '""')
        else PK.writeRaw(bs, PK.hdr(0x08, 2) .. '""') end
    else
        if not json or json == '' then raknetDeleteBitStream(bs) return false end
        PK.writeRaw(bs, PK.hdr(0x40, #json, role == 'use' and 5 or (role == 'clk' and 3 or 6)) .. json)
    end
    selfSend = true
    if raknetSendBitStream then raknetSendBitStream(bs) else raknetSendBitStreamEx(bs, 1, 9, 6) end
    selfSend = false
    raknetDeleteBitStream(bs)
    return true
end

function PK.ack(win, shown)
    local bs = raknetNewBitStream()
    PK.writeRaw(bs, string.char(220, 66, win, shown and 0x80 or 0))
    selfSend = true
    if raknetSendBitStream then raknetSendBitStream(bs) else raknetSendBitStreamEx(bs, 1, 9, 6) end
    selfSend = false
    raknetDeleteBitStream(bs)
end

local function waitUntil(cond, ms)
    local lim = clock() + ms / 1000
    while clock() < lim and not cond() do wait(50) end
    return cond()
end

local function findGuard(id)
    for _, g in ipairs(guards) do if g.id == id then return g end end
end

local function guardIndex(id)
    for i, g in ipairs(guards) do if g.id == id then return i end end
end

local function guardLabel(g, i)
    if g.name and g.name ~= '' then return g.name end
    return string.format('Охранник %02d', i)
end

local function foodName()
    local sel = S.food[0]
    for _, f in ipairs(FOODS) do if f.id == sel then return f.name end end
    return 'Любая'
end

local function foodList()
    local have = {}
    for _, e in pairs(foodSlots) do
        if e.amount ~= 0 then have[e.item] = true end
    end
    local out = {}
    for _, f in ipairs(FOODS) do
        if f.id == 0 or f.id == S.food[0] or have[f.id] then out[#out + 1] = f end
    end
    return out
end

local function foodMatches(item)
    local sel = S.food[0]
    return sel == 0 or sel == item
end

local function pickSlot()
    local best
    for slot, f in pairs(foodSlots) do
        if f.amount ~= 0 and foodMatches(f.item) and (not best or slot < best) then best = slot end
    end
    return best
end

local function foodCount()
    local n, unk = 0, false
    for _, f in pairs(foodSlots) do
        if foodMatches(f.item) then
            if f.amount < 0 then unk = true n = n + 1 else n = n + f.amount end
        end
    end
    return n, unk
end

local function foodText()
    local n, unk = foodCount()
    if n == 0 then return 'Еды (' .. foodName() .. ') нет.' end
    return string.format('Еда (%s): %s%d шт', foodName(), unk and '>=' or '', n)
end

local function fmtHours(h)
    local hh = math.floor(h)
    local mm = math.floor((h - hh) * 60 + 0.5)
    if mm == 60 then hh, mm = hh + 1, 0 end
    if hh > 0 then return string.format('%d ч %02d мин', hh, mm) end
    return string.format('%d мин', mm)
end

local function openMenu(needGuard)
    local need = (needGuard ~= false)
    local t0 = clock()
    if PK.win[0x34] then
        PK.weOpened = false
        local tf = clock()
        sendCef('requestInventoryTab|52')
        if not waitUntil(function() return foodStamp >= tf end, 2500) then
            tf = clock()
            sendCef('requestInventoryTab|52')
            waitUntil(function() return foodStamp >= tf end, 2500)
        end
        wait(300)
    else
        local function opened() return PK.win[0x34] or visibleStamp >= t0 end
        sampSendChat(INVENT_CMD)
        if not waitUntil(opened, 3000) then
            sendCef('openInventory|')
            if not waitUntil(opened, 3000) then
                msg('Инвентарь не открылся.')
                return false
            end
        end
        PK.weOpened = true
        wait(700)
    end

    local t1 = clock()
    for _ = 1, 2 do
        sendCef('requestShowingInventory|63')
        if waitUntil(function() return invStamp >= t1 end, 3000) then break end
    end
    if invStamp < t1 then
        msg('Сервер не прислал список охранников.')
        return false
    end
    if need and not guard then
        msg('Нет заспавненного охранника.')
        return false
    end
    msg('Список охранников получен.')
    wait(200)
    return true
end

local function closeMenu()
    wait(200)
    if PK.weOpened and PK.win[0x34] then
        sampSendChat(INVENT_CMD)
        waitUntil(function() return not PK.win[0x34] end, 2500)
    end
    PK.weOpened = false
end

local function feedOnce()
    local slot = pickSlot()
    if not slot then
        msg('Еда не найдена в инвентаре: ' .. foodName() .. '.')
        return false
    end
    local f = foodSlots[slot]
    local amount = f.amount
    if amount < 0 then amount = 1 end

    sendCef(string.format(
        'useItemOnSecurity|{"from":{"amount":%d,"id":0,"slot":%d,"type":1},"id":%d}',
        amount, slot, guard))
    return true
end

local hideGuard, swapTo

local function feedToFull()
    local fed, stall, errs, respawned = 0, 0, 0, false
    local starved = (satiety or 100) <= 0
    if starved then
        msg(string.format('Сытость 0%% - после первой порции жду %d сек.', STARVE_WAIT))
    end
    while fed < MAX_FEEDS do
        if not guard then break end
        if satiety and satiety >= 100 then break end
        local before = satiety
        local tFeed = clock()
        if not feedOnce() then break end
        waitUntil(function() return feedAck >= tFeed or notifStamp >= tFeed end, 3000)

        if farStamp >= tFeed then
            if respawned then msg('Охранник опять далеко, стоп.') break end
            respawned = true
            msg('Охранник далеко - прячу и спавню заново.')
            agentNote(5, AGENT_LINES[5])
            local id = guard
            if not hideGuard(true) then break end
            wait(600)
            if not swapTo(id) then break end
            stall, errs = 0, 0
        elseif feedAck >= tFeed then
            fed = fed + 1
            errs = 0
            local t = clock()
            sendCef('requestShowingInventory|63')
            if not waitUntil(function() return invStamp >= t end, 2500) then break end
            if satiety == before then stall = stall + 1 else stall = 0 end
            if stall >= (starved and 3 or 2) then msg('Сытость не меняется, стоп.') break end
            if not (satiety and satiety >= 100) then
                wait(math.floor(math.max(FEED_PAUSE, (starved and fed == 1) and STARVE_WAIT or 0) * 1000))
            end
        else
            errs = errs + 1
            if errs >= 6 then msg('Сервер не принимает кормление, стоп.') break end
            wait(1500)
        end
    end
    return fed
end

local function healthPct()
    if not guard or not health then return nil end
    local m = maxHealth[guard] or 0
    if m <= 0 then return nil end
    return health / m * 100
end

local function healthLow()
    local p = healthPct()
    return p ~= nil and p <= S.hideBelow[0]
end

local function waitQuiet(quietMs, maxMs)
    local lim = clock() + maxMs / 1000
    while clock() < lim do
        local last = math.max(selStamp, invStamp)
        if clock() - last >= quietMs / 1000 then return true end
        wait(50)
    end
    return false
end

local function clickMenuChoose(id, word)
    dialogWant, dialogDone = word, false
    local ok = false
    waitQuiet(600, 3000)
    for attempt = 1, 5 do
        msg(string.format('Охранник id=%d, попытка %d', id, attempt))
        local t = clock()
        sendCef(string.format('selectSecurity|{"id":%d}', id))
        waitUntil(function() return selStamp >= t end, 1500)
        wait(350)
        sendCef(string.format('clickOnMenu|{"id":%d}', id))
        if waitUntil(function() return dialogDone end, 2500) then ok = true break end
        waitQuiet(600, 2500)
    end
    dialogWant = nil
    return ok
end

function hideGuard(keepCycle)
    if not guard then msg('Нет заспавненного охранника.') return false end
    if not clickMenuChoose(guard, 'Спрятать') then
        msg('Диалог охранника не появился.')
        return false
    end
    wait(500)
    local t = clock()
    sendCef('requestShowingInventory|63')
    waitUntil(function() return invStamp >= t end, 2000)
    if guard == nil then
        msg('Охранник спрятан.')
        starving = false
        if cycle and not keepCycle then cycle = false msg('Цикл остановлен.') end
        return true
    end
    msg('Не удалось подтвердить, что охранник спрятан.')
    return false
end

function swapTo(target)
    local g = findGuard(target)
    if not g then msg('Охранник не найден в списке.') return false end
    if guard == target then msg('Этот охранник уже заспавнен.') return true end
    if g.died == 1 then msg('Этот охранник погиб.') return false end

    if guard then
        msg('Прячу текущего охранника...')
        if not hideGuard(true) then return false end
        wait(600)
    end

    local t0 = clock()
    if not clickMenuChoose(target, 'Заспавнить') then
        msg('Диалог охранника не появился.')
        return false
    end
    agentNote(6, 'Охранник призывается, это может занять до 30 секунд.')
    local deadline = clock() + 40
    wait(1500)
    while clock() < deadline do
        local t1 = clock()
        sendCef('requestShowingInventory|63')
        waitUntil(function() return invStamp >= t1 end, 2500)
        if guard == target or errStamp >= t0 then break end
        wait(2000)
    end

    if guard == target then
        starving = false
        hiddenNoFood = false
        dirty = true
        local i = guardIndex(target)
        msg('Заспавнен: ' .. guardLabel(findGuard(target) or {}, i or 0))
        return true
    end
    if errStamp >= t0 then
        msg('Сервер: уже заспавнен другой охранник.')
    else
        msg('Не удалось заспавнить охранника.')
    end
    return false
end

local function autoSpawnCheck()
    if not S.autoSpawn[0] then return false end
    local pref = S.prefId[0]
    if pref < 0 or not findGuard(pref) then
        msg('Приоритетный охранник не выбран.')
        return false
    end
    if guard == pref then
        msg('Приоритетный охранник уже заспавнен.')
        return true
    end
    if guard and satiety and satiety >= AUTO_SPAWN_BELOW then
        msg(string.format('Запас еды %d%% (>= %d%%) - авто-спавн не нужен.', satiety, AUTO_SPAWN_BELOW))
        return true
    end
    msg(guard and string.format('Запас еды ниже %d%% - меняю на приоритетного.', AUTO_SPAWN_BELOW)
               or 'Охранника нет - спавню приоритетного.')
    return swapTo(pref)
end

local function watchTick()
    if busy then return end
    busy = true
    local wasOpen = win[0]
    win[0] = false
    local t0 = clock()
    local ok, err = pcall(function()
        if not openMenu(false) then return end
        if not guard then starving = false return end
        if healthLow() then
            msg(string.format('Здоровье %d%% - прячу охранника.', math.floor(healthPct() or 0)))
            if hideGuard() then hiddenNoFood = true dirty = true end
        end
    end)
    if not ok then msg('Ошибка: ' .. tostring(err)) end
    if visibleStamp >= t0 then closeMenu() end
    busy = false
    S.hideUntil = clock() + 1.2
    if wasOpen then wait(300) win[0] = true end
end

local function session(mode, arg)
    if busy then return end
    busy = true
    local wasOpen = win[0]
    win[0] = false
    local tStart = clock()
    local fedCount
    local intro = AGENT_INTRO[mode]
    if intro then agentNote(intro[1], intro[2]) end

    local ok, err = pcall(function()
        local needGuard = (mode == 'feed' or mode == 'now' or mode == 'hide')
        if not openMenu(needGuard) then
            if mode == 'startup' and startupTries < 6 then
                startupTries = startupTries + 1
                needStartup, startupAt = true, clock() + 15
            end
            if mode == 'startup' or mode == 'start' then msg('Не удалось проверить охранника.') end
            return
        end

        if mode == 'scan' then
            msg(string.format('Охранник: %s, запас еды: %s', tostring(guard), satiety and (satiety .. '%') or '-'))
            msg(foodText())
            autoSpawnCheck()
            return
        end
        if mode == 'autocheck' then autoSpawnCheck() return end
        if mode == 'swap' then
            if swapTo(arg) and guard then enabled = true end
            return
        end
        if mode == 'hide' then hideGuard() return end

        if mode == 'startup' or mode == 'start' then
            if not guard and hiddenNoFood and pickSlot() then
                hiddenNoFood = false
                dirty = true
            end
            if not guard and hiddenNoFood then
                msg('Охранник спрятан из-за нехватки еды - не спавню.')
            elseif not guard and S.prefId[0] >= 0 and S.autoSpawn[0] then
                msg('Охранника нет - спавню приоритетного.')
                swapTo(S.prefId[0])
            end
            if not guard then
                enabled, cycle = false, false
                msg('Охранника нет - скрипт отключён.')
                if S.autoFeed[0] and startupTries < 10 then
                    startupTries = startupTries + 1
                    needStartup, startupAt = true, clock() + 60
                end
                return
            end
            enabled = true
            msg(foodText())
            if not pickSlot() then noFoodMsg = foodName() end
            if mode == 'start' or S.autoStart[0] or S.autoFeed[0] then
                cycle = true
                msg(string.format('Авто-кормление включено: кормлю при сытости %d%%.', S.threshold[0]))
            end
            return
        end

        if satiety and satiety < AUTO_SPAWN_BELOW then autoSpawnCheck() end
        if not guard then return end

        local noNeed
        if satiety then
            if mode == 'now' then noNeed = satiety >= 100 else noNeed = satiety > S.threshold[0] end
        end
        if noNeed then
            msg('Запас еды ' .. satiety .. '% - кормить не нужно.')
            starving = false
            return
        end

        if not pickSlot() then
            msg('Еда закончилась: ' .. foodName() .. '.')
            noFoodMsg = foodName()
            starving = S.hideNoFood[0]
            if S.hideNoFood[0] then
                if healthLow() then
                    msg(string.format('Здоровье %d%% - прячу охранника.', math.floor(healthPct() or 0)))
                    if hideGuard() then hiddenNoFood = true dirty = true end
                else
                    msg('Охранник остаётся, слежу за здоровьем.')
                    nextWatch = clock() + S.watch[0]
                end
            end
            return
        end
        starving = false

        local fed = feedToFull()
        fedCount = fed
        if not pickSlot() and (not satiety or satiety < 100) then noFoodMsg = foodName() end
        msg(string.format('Покормил: %d раз(а), запас еды: %s', fed, satiety and (satiety .. '%') or '-'))
        msg(foodText())
    end)
    if not ok then msg('Ошибка: ' .. tostring(err)) end
    agentFinish(mode, ok, fedCount)

    if cycle and enabled then
        local first = (mode == 'start' or mode == 'startup')
        local d, calc = scheduleNext(invStamp >= tStart, first and 5 or 60)
        if calc and not first then
            msg(string.format('Следующее кормление примерно через %s (при %d%%).',
                fmtHours(d / 3600), S.threshold[0]))
        end
    end

    if visibleStamp >= tStart then closeMenu() end
    busy = false
    S.hideUntil = clock() + 1.2
    if not S.scriptOn[0] then cycle = false end
    if wasOpen then wait(300) win[0] = true end
end

local function run(mode, arg)
    if not S.scriptOn[0] then msg('Скрипт выключен. Включи его в меню (/fm) или командой /fmpower.') return end
    if busy then return end
    if mode == 'autocheck' and not S.autoSpawn[0] then msg('Авто-спавн выключен.') return end
    lua_thread.create(function() session(mode, arg) end)
end

function setScript(on)
    S.scriptOn[0] = on and true or false
    dirty = true
    if on then
        needStartup, startupAt = true, clock() + 2
        msg('Скрипт ВКЛЮЧЁН.')
    else
        cycle, starving, needStartup = false, false, false
        agent.q, agent.cur = {}, nil
        msg('Скрипт ВЫКЛЮЧЕН: авто-кормление, авто-спавн и проверки остановлены.')
    end
end

local function handleInventory(data)
    local d = data and data[1] and data[1].data
    if not d then return end
    local action = data[1].action

    if action == 1 and d.securities then
        local found
        local list = {}
        for _, s in ipairs(d.securities) do
          if s.id ~= nil then
            local okn, name = pcall(u8, tostring(s.name or ''))
            list[#list + 1] = {
                id = s.id, slot = s.slot, name = okn and name or '',
                level = s.level or 1, health = s.health or 0, satiety = s.satiety or 0,
                spawned = s.spawned or 0, died = s.died or 0,
            }
            if s.spawned == 1 and s.died == 0 then
                found = s.id
                satiety = s.satiety
                satStamp = clock()
                health = s.health
                if s.health > (maxHealth[s.id] or 0) then maxHealth[s.id] = s.health end
            end
          end
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        guards = list
        if not found then health, satiety = nil, nil end
        guard = found
        invStamp = clock()
        return
    end

    if action == 2 and d.type == 1 and d.items then
        foodStamp = clock()
        for _, it in ipairs(d.items) do
            if FOOD_BY_ID[it.item] then
                local cur = foodSlots[it.slot]
                local amt = it.amount
                if amt == nil then amt = (cur and cur.amount) or -1 end
                if cur and cur.amount ~= amt then feedAck = clock() end
                foodSlots[it.slot] = { item = it.item, amount = amt }
            elseif it.slot and it.slot >= 0 then
                if foodSlots[it.slot] then feedAck = clock() end
                foodSlots[it.slot] = nil
            end
        end
    end
end

do

local unpack_ = table.unpack or unpack

local function bytesToStr(b, i, j)
    local parts, k = {}, i
    while k <= j do
        local e = math.min(j, k + 2047)
        parts[#parts + 1] = string.char(unpack_(b, k, e))
        k = e + 1
    end
    return table.concat(parts)
end

local function u16(b, i) return b[i] + b[i + 1] * 256 end
local function u32(b, i) return b[i] + b[i + 1] * 256 + b[i + 2] * 65536 + b[i + 3] * 16777216 end

local function validUtf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local need
        if c < 0x80 then need = 0
        elseif c >= 0xC2 and c <= 0xDF then need = 1
        elseif c >= 0xE0 and c <= 0xEF then need = 2
        elseif c >= 0xF0 and c <= 0xF4 then need = 3
        else return false end
        for j = 1, need do
            local d = s:byte(i + j)
            if not d or d < 0x80 or d > 0xBF then return false end
        end
        i = i + need + 1
    end
    return true
end

local bit_ = require("bit")
local band_, rshift_ = bit_.band, bit_.rshift
local FREQ = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 722, 0, 0, 2, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    11084, 58, 63, 1, 0, 31, 0, 317, 64, 64, 44, 0, 695, 62, 980, 266,
    69, 67, 56, 7, 73, 3, 14, 2, 69, 1, 167, 9, 1, 2, 25, 94,
    0, 195, 139, 34, 96, 48, 103, 56, 125, 653, 21, 5, 23, 64, 85, 44,
    34, 7, 92, 76, 147, 12, 14, 57, 15, 39, 15, 1, 1, 1, 2, 3,
    0, 3611, 845, 1077, 1884, 5870, 841, 1057, 2501, 3212, 164, 531, 2019, 1330, 3056, 4037,
    848, 47, 2586, 2919, 4771, 1707, 535, 1106, 152, 1243, 100, 0, 2, 0, 10, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
}

local HT
local function huffTree()
    if HT then return HT end
    local L, R, W, V, list = {}, {}, {}, {}, {}
    local cnt = 0
    local function ins(id)
        local w, pos = W[id], #list + 1
        for i = 1, #list do
            if not (W[list[i]] < w) then pos = i; break end
        end
        table.insert(list, pos, id)
    end
    for c = 0, 255 do
        cnt = cnt + 1
        local f = FREQ[c + 1]
        W[cnt] = (f ~= 0) and f or 1
        V[cnt] = c
        ins(cnt)
    end
    while true do
        local a = table.remove(list, 1)
        local b = table.remove(list, 1)
        cnt = cnt + 1
        L[cnt], R[cnt], W[cnt] = a, b, W[a] + W[b]
        if #list == 0 then break end
        ins(cnt)
    end
    HT = { root = cnt, L = L, R = R, V = V }
    return HT
end

local function huffDecode(b, n, startBit, count)
    local t = huffTree()
    local L, R, V, root = t.L, t.R, t.V, t.root
    local out, oc, node, o, total = {}, 0, root, startBit, n * 8
    while oc < count and o < total do
        local byte = b[rshift_(o, 3) + 1]
        local bt = band_(rshift_(byte, 7 - band_(o, 7)), 1)
        node = (bt == 1) and R[node] or L[node]
        o = o + 1
        if not L[node] then
            oc = oc + 1
            out[oc] = V[node]
            node = root
        end
    end
    if oc == 0 then return "", o end
    return bytesToStr(out, 1, oc), o
end

local function textClass(s)
    local n = #s
    if n == 0 then return nil end
    local bad, high, cyr = 0, 0, 0
    for i = 1, n do
        local c = s:byte(i)
        if (c < 32 and c ~= 9 and c ~= 10 and c ~= 13) or c == 127 then bad = bad + 1 end
        if c >= 128 then
            high = high + 1
            if c >= 0xC0 or c == 0xA8 or c == 0xB8 or c == 0xB9 then cyr = cyr + 1 end
        end
    end
    if bad > n * 0.02 then return nil end
    if high == 0 then return "ascii" end
    if validUtf8(s) then return "utf8" end
    if cyr >= high * 0.85 then return "cp1251" end
    return nil
end

local function decodeCef(b, n)
    local cands = {}
    local function try(layout, len, start, prio)
        if len < 2 or start < 3 or start + len - 1 > n then return end
        local trail = n - (start + len - 1)
        if trail > 8 then return end
        local s = bytesToStr(b, start, start + len - 1)
        local cls = textClass(s)
        if not cls then return end
        local score = (trail == 0 and 1000 or 500 - trail * 10) - prio
        if len < 3 then score = score - 200 end
        cands[#cands + 1] = { layout = layout, text = s, trail = trail, score = score, cls = cls }
    end

    if n >= 11 then
        local cnt = u16(b, 5)
        if cnt >= 2 and cnt <= 60000 then
            local ok, s, endBit = pcall(huffDecode, b, n, 73, cnt)
            if ok and type(s) == "string" and #s == cnt then
                local cls = textClass(s)
                if cls then
                    cands[#cands + 1] = {
                        layout = "huff@73", text = s, trail = math.max(0, math.floor((n * 8 - endBit) / 8)),
                        score = 1500, cls = cls,
                    }
                end
            end
        end
    end
    if n >= 10 and b[9] == 0 then
        try("i32,u16,flag0", u16(b, 7), 10, 0)
    end
    for k = 3, 12 do
        if k <= n then try("u8@" .. k, b[k], k + 1, 1 + k) end
        if k + 1 <= n then try("u16@" .. k, u16(b, k), k + 2, 2 + k) end
    end
    for k = 3, 10 do
        if k + 3 <= n then try("u32@" .. k, u32(b, k), k + 4, 3 + k) end
    end

    local best
    for _, c in ipairs(cands) do
        if not best or c.score > best.score then best = c end
    end
    if best then return best.layout, best.text, best.trail, best.cls end

    local bs, bl, cs, cl = 0, 0, 0, 0
    for i = 3, n do
        local c = b[i]
        if c >= 32 and c < 127 then
            if cl == 0 then cs = i end
            cl = cl + 1
            if cl > bl then bs, bl = cs, cl end
        else
            cl = 0
        end
    end
    if bl >= 6 then return "scan", bytesToStr(b, bs, bs + bl - 1), 0, "ascii" end
    return "binary", "", 0, nil
end

PK.decodeFast = function(b, n)
    if n < 7 then return nil end
    local len = u16(b, 5)
    if b[7] == 0 then
        if len >= 1 and 7 + len <= n then
            local s = bytesToStr(b, 8, 7 + len)
            local cls = textClass(s)
            if cls then return s, cls end
        end
        return nil
    end
    if n >= 11 and len >= 2 and len <= 60000 then
        local ok, s = pcall(huffDecode, b, n, 73, len)
        if ok and type(s) == 'string' and #s == len then
            local cls = textClass(s)
            if cls then return s, cls end
        end
    end
    local _, text, _, cls = decodeCef(b, n)
    if cls then return text, cls end
end
PK.bytesToStr = bytesToStr

end

PK.ffi = require('ffi')
function PK.bytes(bs)
    local total = raknetBitStreamGetNumberOfBytesUsed(bs)
    if not total or total < 2 then return nil end
    local ptr = raknetBitStreamGetDataPtr(bs)
    if not ptr or ptr == 0 then return nil end
    local n = math.min(total, 16384)
    local p = PK.ffi.cast('const uint8_t*', PK.ffi.cast('uintptr_t', ptr))
    local b = {}
    for i = 1, n do b[i] = p[i - 1] end
    return b, n, total
end
function PK.toGame(text, cls)
    if cls == 'utf8' then
        local ok, r = pcall(function() return u8:decode(text) end)
        if ok and r then return r end
    end
    return text
end
function PK.dumpAdd(dir, raw, text)
    local r = PK.ring
    local pv = text and (' | ' .. text:sub(1, 90):gsub('[%c]', '.')) or ''
    r[#r + 1] = dir .. ' [' .. #raw .. 'b] ' .. PK.hex(raw:sub(1, 96)) .. pv
    if #r > 28 then table.remove(r, 1) end
end
function PK.readIn(bs)
    local b, n = PK.bytes(bs)
    if not b or b[1] ~= 220 or b[2] ~= PK.IN_SUB then return nil end
    PK.inSeen = PK.inSeen + 1
    local text, cls = PK.decodeFast(b, n)
    local str
    if text and cls then
        PK.inOk = PK.inOk + 1
        str = PK.toGame(text, cls)
    end
    if (not str or PK.ringIn < 10) and #PK.ring < 28 then
        PK.ringIn = PK.ringIn + 1
        PK.dumpAdd('IN', PK.bytesToStr(b, 1, math.min(n, 96)), str)
    end
    return str
end
function PK.extract(str)
    local json = str:match('`(.*)`')
    if not json then
        local p = str:find('[%[{]')
        if not p then return nil end
        json = str:sub(p)
    end
    local ok, d = pcall(decodeJson, json)
    if not ok or type(d) ~= 'table' then return nil end
    if type(d[1]) == 'table' and d[1].action and d[1].data then return d, 'data' end
    if d.securities then return { { action = 1, data = d } }, 'data' end
    if d.type == 1 and d.items then return { { action = 2, data = d } }, 'data' end
    if d.skin and d.accsPages then return nil, 'open' end
    return nil
end

local TXT_ONE_GUARD = u8:decode('одновременно')
local TXT_FAR_GUARD = u8:decode('слишком далеко от охранника')

local function parseIncoming(bs)
    local str = PK.readIn(bs)
    if not str then return end
    local find = string.find
    local isInv = find(str, 'nventory', 1, true) and true or false
    local ours = false
    if find(str, 'setPlayerInventoryVisible', 1, true) then
        if find(str, '[true]', 1, true) then
            visibleStamp = clock()
            invOpen = true
        elseif find(str, '[false]', 1, true) then
            invOpen = false
        end
    end
    if find(str, 'cef.addNotification', 1, true) then
        if find(str, TXT_ONE_GUARD, 1, true) then errStamp = clock() ours = true end
        if find(str, '"type":"error"', 1, true) then notifStamp = clock() ours = true end
        if find(str, TXT_FAR_GUARD, 1, true) then farStamp = clock() ours = true end
    end
    do
        local ty = str:sub(1, 48):match('"type"%s*:%s*(%d+)')
        if ty == '28' or ty == '30' then selStamp = clock() end
    end
    local data, kind = PK.extract(str)
    if kind == 'open' then
        isInv = true
        visibleStamp = clock()
        invOpen = true
    elseif data then
        isInv = true
        handleInventory(data)
    end

    return false
end

PK.onRecv = function(id, bs)
    if id ~= 220 then return end
    if not (S.scriptOn[0] or busy) then return end
    pcall(parseIncoming, bs)
end
addEventHandler('onReceivePacket', PK.onRecv)

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if dialogWant then
        local needle = u8:decode(dialogWant)
        msg(string.format('Диалог %d: %s', id, tostring(title)))
        if id == DIALOG_GUARD or tostring(text):find(needle, 1, true) then
            local idx, i = 0, 0
            for line in tostring(text):gmatch('[^\n]+') do
                if line:find(needle, 1, true) then idx = i break end
                i = i + 1
            end
            PK.ack(0x04, true)
            sampSendDialogResponse(id, 1, idx, '')
            PK.ack(0x04, false)
            PK.ack(0x04, false)
            dialogDone = true
            return false
        end
    end
end

function sampev.onInitGame()
    startupTries = 0
    needStartup = true
    startupAt = clock() + STARTUP_DELAY
end

function PK.learn(raw)
    if true then return end
    local p = raw:find('{', 3, true)
    local q = raw:find('}[^}]*$')
    if not p or not q or q < p then return end
    local json = raw:sub(p, q)
    local pre, tail = raw:sub(1, p - 1), raw:sub(q + 1)
    if #pre > 24 or #tail > 12 then return end
    local off
    for o = 0, #pre - 2 do
        if pre:byte(o + 1) + pre:byte(o + 2) * 256 == #json then off = o break end
    end
    if not off then return end
    local role
    if json:find('"from"', 1, true) then
        role = 'use'
    else
        local key = PK.hex(PK.patchLen(pre, off, 2, 0))
        local idx
        for i, k in ipairs(PK.idKeys) do if k == key then idx = i end end
        if not idx and #PK.idKeys < 2 then
            PK.idKeys[#PK.idKeys + 1] = key
            idx = #PK.idKeys
        end
        role = (idx == 1 and 'sel') or (idx == 2 and 'clk') or nil
    end
    if role and not PK.tpls[role] then
        PK.tpls[role] = { prefix = pre, tail = tail, lenOff = off, lenSize = 2 }
        PK.learned = true
        dirty = true
    end
end
function PK.saveDump()
    local L = { 'Auto Guard Feeder dump  ' .. os.date('%Y-%m-%d %H:%M:%S'),
                'in: seen=' .. PK.inSeen .. ' ok=' .. PK.inOk }
    for _, role in ipairs({ 'use', 'sel', 'clk' }) do
        local t = PK.tpls[role]
        L[#L + 1] = 'tpl ' .. role .. ': ' .. (t and ('prefix=' .. PK.hex(t.prefix) .. ' tail=' .. PK.hex(t.tail) .. ' lenOff=' .. t.lenOff) or 'none')
    end
    for _, l in ipairs(PK.ring) do L[#L + 1] = l end
    local dir = getWorkingDirectory() .. '/config'
    if not doesDirectoryExist(dir) then createDirectory(dir) end
    local path = dir .. '/AutoGuardFeeder_dump.txt'
    local f = io.open(path, 'w')
    if not f then return nil end
    f:write(table.concat(L, '\n'))
    f:close()
    return path
end

local function parseOutgoing(bs)
    local b, n = PK.bytes(bs)
    if not b or b[1] ~= 220 then return end
    if b[2] == 66 and n == 4 then
        PK.win[b[3]] = (b[4] == 0x80)
        if b[3] == 0x34 then invOpen = PK.win[0x34] end
    end
    local raw = PK.bytesToStr(b, 1, n)
    if n == 15 and raw:sub(14) == '""' and not selfSend then
        PK.tpls.open = { prefix = raw:sub(1, 13), tail = '', lenOff = 11, lenSize = 2 }
    end
    if n > 4 then PK.dumpAdd('OUT', raw, raw:sub(14)) end
    PK.learn(raw)
    local p, q = raw:find('{', 3, true), raw:find('}[^}]*$')
    if not p or not q or not raw:find('"from"', 1, true) then return end
    local okj, d = pcall(decodeJson, raw:sub(p, q))
    if not okj or type(d) ~= 'table' then return end
    if tonumber(d.id) then guard = tonumber(d.id) end
    local from = d.from
    if type(from) == 'table' and from.slot and from.amount and foodSlots[from.slot] then
        local left = from.amount - 1
        foodSlots[from.slot].amount = left > 0 and left or 0
        if left <= 0 then foodSlots[from.slot] = nil end
    end
end

PK.onSend = function(id, bs)
    if id ~= 220 or selfSend then return end
    pcall(parseOutgoing, bs)
end
addEventHandler('onSendPacket', PK.onSend)

local MM_B64 = [[
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
]]
local AGENT_FILE = 'agent_v1.png'
local AGENT_B64 = [[
iVBORw0KGgoAAAANSUhEUgAAA4AAAAJYCAMAAAAE8HiTAAABgFBMVEXXl2PaYiJSIxBrSTRMIQ6fWylXIQxRJQ7mhSzRPSNuXVKQxNm4o5Cggmukdlvaqo
ejLggxHBGMMxMpJiRvlaGWUx61UhM8IRX74LyuNR7HVBP8wmxnRSGocUt9uM86S1DJhCJ2Tiz47eGTZENaeIPGfkm/g1jChVrAOiEvPUJzSzYAAAD6cx35
diIsBwD54sr33cPzahhMFgUXAQBuJwn217qRNgzNWBU4EwevRxH6gyqrNwqOKwhwNBVTJBDwyajMRwzYYxrrupJDDQFtRzPwbCIvFQlmHAToWhEnFAo1FQ
nzw5v88tqMZ1FVNim5Uxash275p01IFgbLqY3jSCc4FQmVQxNIFwbStJgnDAN1Vkb3ljlHGAcjDQPymkXaRSXOl3A5FAiVeGVmOyi0k3nVu6M6Ewg7Ege1
moTbxKtGGQeHvNE3DAIbEQupeFj89uOGW0UuDQKVcltMLCGOVjD5pSzGPQuwZiw2DQL6t2c1DQI7IhlLJBLUaCL7s1gzDQIJLiGaAAAAgHRSTlP29J/5VP
jVKvnp+vv6+vj5+CZh+/tokVH5obD5NJT7+6pM+3L7+bW9uvuCAPv6+fv6+vj5+fr6+vj6+vn5+Pf6+fr5+Pn6L/j3FE75+vn5+vn6z/n7bvmv+i35+ZAU
+vn3jvn4+fqvzvr6cfvQCvn6+E75+Pj4+fiv+ZD6cPr6bh1L8boAAQAASURBVHja7P2JcxtHlj6KktrbI3nrmZ7p7oh349343YgboaoEKrNQC5YCQGzcQF
CkCVLcLFK7RpsltRbLsv/1d87JzKqsQoGkRICS+6m6bUuUKCEr88uzfec7M9e/Pl+fr89ne2a+voKvz9fnKwC/Pl+frwD8+nx9vj5fAfj1+fp8BeDX5+vz
9fkKwK/P1+crAL8+H/3cpOffaUG//LKxsXFAD/xgcfHm3tdd/grAL+uMLv7xx69vHz9+zPTDW61Lly69/eOXPy8W9xY3Du49vs9GH843Dxa7X2H4FYBfwj
H9ZXeN46kU9JjnNOCct+C/9zb+dDbj5i8H9+Wa4pXgE6TWdv/tH/8Olv7m4qNdeDY3N/E/jx5d6O7t/f8LAPf29rrdLnhs8IM/4YW6t7i5ps4kj1y35nle
SM/Qq7qcxycXQbj75zmrN399TOBjQVR79ebDhw82PZ1Ox3GaTccfDOXi6Pn1z4vB7uLBvfuBcanAbvVow9bunYGF/5wA3Ouie/M25d7cv3/vT+XY7D2Slg
9O6cUPs3BArczj+KHncolNPLD84M9wVm8ewIkEuxcN38yW6RldGayt6ePaxJ8VgwuLu3h1ks8SBEFs33GvXE/t19qj7r8jAG/+Eq9d0LUTGJcQ2pLNjZsL
X/wGbkj08Ytvyvs7eEidzGNZeHBtQKEbMO4SFNnjL9xn6/5B6ONDWBUsy46fFPjU6uzOwCMr/2fD4N7GJicLz2vDi28+zM5K6970B3BjRhzcFhc8GVrb2s
bevxUA9xYPyLuBk+vWhgNcfIeOa9PH1XvatZn25XNK9F1A9AlWe3Plxo39sm05o48+qghDJ3RhSVXCYOvSL1/ssh7BxSjA9M3u38A7xZEfP0FgZonwRdv2
8ZxiqNt69OfwXRY27gfktwzfzOzv0N0Zr5H+jVcmgNAN/UYVT+P9jZv/JgDsbtxX986r2Ss7uHbp3aSu147y21hwbuML3cILdE7dN/vvfv+XRp+0d/Fjp0
AJP3VCWJNbqfRgZa1fv8Sj2t0Fj1IEiL4b8Z1imTZQ/SdZlrpl4Hrhbo8zvjvdSxPcxnv3DrpPTrXKTfSbee0NrJLuTkuty453Dn/s0L3iNuYJg621C3t/
egB2N/DYClj6DCwdvZs8u4HXKvo2tH7GNr9Aa7G4huf04sy7f/6+E6MPjyXacHx831eATC/LBzPohhKCB18aBBcQfizCc7mjbB+uqemHQ/BLXDeCB7NM4a
BJi7MSIw8/8d0W76ElnCYEF1XeZ617CvgFsHe1i/vyCFrG/ZLcn7R6hUHuzTthrwUrm4J9P0sAds/h9crper1RNs6tlQ0u4ntXYpB/YY5NF+HHX+3//vsN
OqeEvFC5zkLoUgQGEb78VWNNBMGGhOCjL2pZG/jxz1/BcymxRauKAlWH0CkKuTruDn1He9gSgrQ0SlzsTmu/FlssOrz64BsIqP/7FPCLXin0qcvedEHl5a
93DZDYgFUBBOfJzX705wXgIho/uHi06dN5NJ8S9vgM0XAkgZM+sFV0F3a/HAjKLXxz43f0Xsiz9D2XMkhcFiHoqWEgT762FyoQat8Gz2lVQpB/OdZ9Ea3f
UMNPepX4JUpG+E2nI90yMoiU+wQz4np+vDRanY+O6FQOqnw42y48W372rLTNgsVP2juM2i/C3u2oqxOO4ADOX82lxyPrTnFg5s5ECFY4bOfGnxOA5LNFr2
Z+l7erzM9X3YAlZWuhr1a0G2Yk1fTgrbX++ILctOjijXcAP/xwHXlMIy9sZoMIG/YWoQmhYjjvJF/GHRW8IiG49mXkmbprXIjaFRUTyZQRWHncCjvrokkb
0cQMId4vTWkA1a/4Pea6rSmta5GtFArFAjzPDgX76L9hgeA3c0M7LjLTknAMdCKe13Azk0QvHMEq43CPAgThVy/8+QBIPhuc2t/3y9Jjk65li2NAgfGSfP
AqcjmeWHW36tPseC2A4JdgLS7AoQsQfjfonPoenLUIPqv0YqzkLMqNK8t8WgAIrZjJDDvkmI2h4H7zCzDudKvMavjhlQ+fOAs+I8Okft5EmDJ34Ohl4xc9
aQSncWNusgfLhL9CYRkQ+JF1qkXwXNwrCn6WM6gFVL8dfPjQiTNLTZ3+4+oA6pXDK3H9+fl5D9Mx3T8XANHuA/x+/30fF25J8EXeoEnet/a/k439MKB3EL
ghJrnhVcH76dDCFz//QQU7sf87uWlWk5Jkgw92efSAqsWof5M9CVzfin8P3Cmwx5WKi3v9uY1gV94q0vukywGXRbeJnVeAN2CoqitoBhMjyFkPjeDbid8s
a2yrED/b4r6Jrs01vrZx1Ju8xwR/g9kHPFIDl3zR2bLKwycpXplL8yLaMEeXJuCrYYtVAIEU6F74EwFQ+Wzv3u3T2mB3BR9+yCIvdbeS3cBXAJeOoxJSdh
MXvvlZi/NoyDkGELgU38OFzOoaEnxyiGfHH1Y6qO6AfiP+1LIbLTSCFNp/Xtv+CLYEHLMb+7gsuBgYfzVbLstIwZa3y5EgdHANnm8lDioaQfCvWzcnDsD1
grKAxULppdgwIhz5jI3QuvcFQ89lB+2cB/eo+6aMVbC8Myiz12GEN4uTGAd4NT0wgniE+e6fBoAY2wevZv4JFw94nmgIPLh2ysaS7dHFy6tIlnfRDMr8RY
j0hMXPeVCFOL+v4FeFW+WN2kD62HhBsDBlAQ34kWWo4XIsncywnB5EguCHwkk99xmDWiSEvEL4lSX83Df7+3p/0FkGd8Q/CoP4a2g08azGeSa4XOB9tHYn
+1l32WqhCI9E4BbTYeA5xm7f2aqv9wN2L/87D+C2/H/ekQ8GaxTB8Mq//rWT8VzCWi00kw/k4kgI6hxTi4UOWEHYskkFDjPTNn8Q/rT3JfxCDlb/A1478S
JDCH3D8TsLGAwEQlC6Q447vfzaCQKQgPw0CmM9Db/kw4aYTPKscSdVXSlwDuA0W5L5A39MyyMj2Fr7XIHgZfRIKPqzaVnu7P6NcpJLKuOyhFc+ygjKXBQX
QRhHuWWHCxfi49bmZF0QtlJMnsKhckJ/4+xQBoZbATsY47pcnHlHtS+5dRjDJyVAWoSPOUAvE+hSArQp08KYeoJIEAA4X5lY4DBdAGJwEc28e4eZT9ghfr
FMC48X2QQvU0R25pzatvFj3FnEqEwJhy3R+vWzxUkR7iF8kiHuYWImpIkL2ZEAVJQ0qgL6OsmNbiggENOhrc8TCF4A03V+X14rYQChwj7EgbaxG7gs4V05
GoDSEZWXi2RzWY4reujBXJrozXKP3SmUSiVlBAsr7De85SO2ulykry6vs5zk6CLc/G9kDBTiFaMK8FYKgHSDitpIpsl3BRj3+GqpMD4/35hv8AlVcacKwF
1Y+KuZd+jbDLiQDAvbRFkTD6175ah9hRgEIejLyqDd6Qn2+DNlP4eYQIMAHe76N/tyJQm4LJ/WcjQAMZaFb0dvjX7WwYRFtUK5mNbncK7BdrA3yvzBQbu4
cyMdHcDHRQC69jEAlL8Vj6oV1yqq4GDjzTJJBC4yXi/G+AMnNOiiA/ocHNMSAbPQHjWBu3AzzPwTrQC8e8z1pq7OGFoEwGHZzn7dIuMeZ4IbrAX4w1zMRB
zsaQJwk/xu9D5h4TyGn7G0Ju3ulSPgJx+MTHx5Ym3Y5dbNs8efEG9iN21IHkzGuNFlwo8DoGMpU2E5HelW9zAVQ4Hg2TvXuxBVX8GcroXmr1bOHE3cAdqi
o5Zl/m74Q9xmsmsSgWwSu7UAD/I/74t2QcMPaxFs8/oTzusYE5INLLxgm6PhX3QDgyDHwxjidyrg5pw0DwEYptwvXVnCdTllZdvhSgrnG40JIXB6ANy7Dw
Z9H+2+U6O7dV/HfgmwaHejvLdhuqPqcg2VG4ov6pczxx+7+PuNHTJ/nO7QDLjg/1wBcPSo2gYCMamLRjBUq8TA1q1UPwsCwUPhMzIxDy/1DXpm6Y+MniXV
qZ2TAdBGM+qX9a4hAt1JJEO7mxyuivsH3SeXA8zDJLWIFXbhAusvFyQCCYBrI/irzfxzn8wfXDGKaGCPAeDAygGgZTdduDNV14AN8W0FEYipmC8XgF2wGZ
hbs60Bo4UbqZcYgM5YAGa5F+i8V5F6j4EgfNeZnlWIIYLZd+h+hmT+9ndsa8QmwLbA52oe5awh/ny351MmwFPFX9tSCGydNQJ3IeYjWi6eTbcslzWSB1PL
sk7wUBGRsaGlu3o8JhF4Oi+U8rSSpXL/v89xtrWs4Vcs3A34peQLgMHtDCgAfxffvduB6E+wwb8U0SCHfC0ByPw8C0jGHaJ1fRphq8N5v9EABO5+qQDEM3
vxnbL7b7ImwwQgywdgpjxhy0sIv94hBB6cLf6uYPhnoZ34l8riZoDmWK7awCPSoOh+ttCXxmSMCxGttIG9GIEbZ2v/EH/7dLkN97PupwagXJZ1ooeSFgBm
S2+gx3qIwPunrP6x5+t3H27d2Y4YW4tYVCKsyUzoKhygxCKW5jhLxdIbjL169w42DKzxLGydnbnijU/uqgs0m51JjLsKhSFu4AziwIkgcEoAXAzAucG0L9
r9nRs3duzczRoLQFWlT3/Rw4MAF5hE4O5ZHVSw5cEMpV9cEZX/pbIU2QUBOtGcD8pH4c/nzG1KTxqZMBKtHURgVXmhZ5eJeYT4eyfxB+7n/mhklBgGEVrW
iSHo0N2ivFC07oDAt6f5oIw90Ph60Mbe+3bBqEX0ISqM8Vd/Llgaf4LwB1tX24Gts5yjARioDx7HQfJHykfFHVM1+RiBp70zpwPARYabC1sayiRbecxuOS
3KHI6c1GYYhgNnxE8PZaVbIfCPM8Qf+Z8c3M8dvYmjDyXsh/ZR5WqsVlu6NzBkrVB6oRa8B8Df91V2dvmlC5zx/Xcz+3QTXBmDP0snB738Mu2Yi6bKuD7I
dLcAAu+dxgCuLqskJyY+v2FCrBZKlAulvEvUjz3Q+rU0F0bhD7fuIgVBqgMOO3CccgaAXGWbYhph1lrK8+eo3BQHH7TRcE9LUZ4KAGHdtRuIPw9Mhs465X
F+MHEh3OwW+qq5Zzia6OasQkUmtIbsTM7qHsRAM7iJYMsHdE7H4I/qEBDZjQegvEGTNpdGC1MxmL/BZL9XqU4gXjq5W83ARXm3j7bB3bmBvpk9prjAcvZo
zH5qi+ERAuUW493SO4XDstfipcTiFZYLW23BtgqEP4Rl4cG3OitTmknX4S/AOXz3O+KPXdRJCMci2g5yknIA6FoGoY5+nMpH+IEI6UXha5EI7J3yzpwGAD
cCUcPqH9l97X7aJwUg3DMCmz+xGyYb+6Ppr+D6O5huOxMEIofin4Q/6ac5ztgUy5iTqjxU8My8mHQf3yehJKWBceSV7+mkrp0F/hY4Q7O+79AeEaUnl/Kp
M9UnBmBy12hudoNxDyvyn+qqddntGH0U+xUKD1buJACU5T/6paWVFP4gDopmbtjOPGcfCH/y81aljJtI8Xtsu4NfqykmpH4baQRaGFGR10JOmItOKFbkvz
AAwrprSDtokt0fcW3MTcsD4FBgJwgS0sH2JAhUBXz4jlB2S8LC2fStxSYTb96dCH/55jzGn+95/kjYAX+qR5xnMOnCrXz/PSJw8wzM+hpjs4A/io32qT40
Fk6OLAR+BABlQKxsoGNVWM+r8k82FN1WZAKwEAORAFgslMgbJQP4NHV7LWDsgPgL2CxmmNQHdvF8wRO6YnjFWA2tc5j4ntlsvFxME88fyRbBjnmIwMrp7s
zJA7AbkP8JNlok2c9Ux1H+mVVfHwRDx9L1TxYkZRn9nvANOE6ng67R42kjcDcQmMs18KdbT3Ny8G7+SSWn0w+duEEpuVLoRrVkUzlRYr7Hjs9fzuJagWXd
sJwq7NW+7CwerY4lrhnZs5G2lbIsTOetGI9nz7H1e6l6EN7yT9usPc6/ixnYCnnxjwr1dcVMg//NRSYNbeESYzO/o/2Dc7hf1niqCUUat+wBb2YsPRtcsW
yzCkoGsCNbQhTfgstMN+0YWsDG6cqBkwcgxX9lDB1mKcct99bxB9TgaBbQsMg0koQJmwm7CwDqZk4FUb58G+WZKyI4VXbtZAWI2u8QRMhNBPxp+QU7zyK4
QuQB0DFoMKOGMaC4XlLZKooSM23X+hEs6wYaBw9jhNhHye/Lkel5Z7RpxQld1w2dcUGvq25WG21o1XM/+Zhusr7Mv6D7WTSgCKCrv9iS2Ri0hqupcsc5xi
7q/EtiBsKgWdZ6E5ZxmapYdzCytX4t4hzbyGx9lQbgl3XwhxAGEgJ7gi1+OQB8LCLAHxyn4MqN/Z24/EUag7qzI2G4gJc54rUlSlvwAzdb2caTGkgqpcs4
m2rhDJwYfuMd1R8uSvzFAMy7+ZueF18fqa+TTFrSK59N3fiYiOnYFeKkUSJm2nldxlF2EK6waOfGfvmYsgLeK2z07vBaUlLaG+uRC09l/UPRqwACP7HGss
hZv14yMJjwYApPvyuUYgD2iZqdJK9f/VNvXUzBsrxmEvgl0gUUA2K1v5l10VwllOI6dkylQO8a21msUHiz6IS2TpE6mzQA7wm+T/gTV5BiGJe/YA2Csip2
YgZJmYG7fiY8TFkK20lbTeo7AO+GnhZvsWkWzjbBiUEunSeG/9rfoa5Eq4N6Gq7rNY8ihJhNgU0lfBMNUvnT2KcGP5sYPnihIC8bndDp1jjXyDnBGhEvH4
M/GaiOrBYcth6JZ7ue53pOPpXJZ0In7dEJ9T45W7HL2e1bSzEGjWfraTHGX7H03LyO10T07oZtVXDrysblbo8lHVu+9tGS2zFgkTckCSruJKQYsBnyALrS
CfVO4YTOTPrIBnhk4fabjfFX9lEvLBwMQg+s95jDavzUOSLRoTknHonqwAmaZhhIlyhsYihqyGGSriTppSCgak5erJddkj3EuydCkXPPz6lg2GgfcHPl1Y
oA9KbcmwRx7RCCA4eChDHlP+uYHfApdgiVJGPuecaLksklY87eQ+f6E0u3GyhD1781t1Svl1IAvLNeiPFXrJsA3MC7Ey8B8LHLx7DnklJ7to266jW1B4c0
mJgRIoYSgT7rzTcar1G4cPGLAOAu+t37yB98k1T/ILr1lG6KFZ6EUmHsqJ2f06DUhXJCp2ct8BL9Hdnv5Kgp1xOJ1IFbAUCdiB2CbfKurwKI3INuW1Wsc+
OJxUyo56ETOsVaBFwrEfV19HCTdsYW1I/cIY5qIeOUXdWRdiDE5Mp/oZW5n+xbd88FqJfXfjoXA5AiwTsPDYWKuXYCwIVAXPxnGQ4i2Pjy8fQ5e+xNE4cR
kQjLcVEigmCRlu6JCrigFXBC174EAC4G4hXYfYgaBpr9Qlm0QSwZdgJOrxNaKj724/gvOxakgaQ9aTOm54TSJUpV3CsxlwdtO/OcE7KyJP5CHb7nQFDer7
K0Ar+M5XiPqmZTo/kswB9+5R0lYIY5rHLbPr71D+0fXSqOcwQCcc2u7DCnJVaqsK5PbuVc+O0S0Rb7W0WCm0zGfFdP8jFLc1FyFA4Yn7mB5cjZG2X7uGBh
NPtr55VxuVGQp7ABH879hkydLX5+AC6AncZGOdpaXfaEl+DbJ9pWzQ91ZdMDeJoDUy0thUBPuuFI9mVTUnNYRBoTVarfkDetqcnct6yTIhAlNHwrOaTpw2
pIjbSatjSBPQRgdYp5mF0uLiKxFQKZHVJhipul8O7zvIFVPm6rHM8dWMmEiDGMUPRPnUD4qpkFTGDV/XQOvQRgEPCVuxp+AMD1GICF+tytpBl+kbGnv+Nf
OtzZsY+6IK38jFrOlDnLqoVXlMfqWEMVBmIeZr5CmgY8+5GfnDkA11iw/64MMU1tZ78c1y7xBNr2yTBIv4mrbIUT+CNSf+jROtoJ7eDNyqfkhMJtQjQKWI
2spsiEBMRrxwapBqeH9Zy0nRhFoCQZuppmgCYQy/F/TMsAimD/xj4mX8s7ZgAIn7NK/BAeHgtAJ91inLePsBKXzienAgatDE3gJ5ZYsHN/pX9nq25W4YuF
ej1pg1g6L+4/ia18DXyXJuPlI+zfiTqsUpMek2MI1/JAcpg4mwcT+NpLU326u2uM3T/onikAzyFpZB9CvqAc602B8+wbmq328dIith1IxhacymwJQp5VTr
lgQXxfPLrTSVnsMvEUHVAWqEw9fRZXuR4nao6Dzek5CfcsxwbGq3KFZCZWpAlEpuuUErsBRn42ZeeTBmnpV5IuOVxo7jH973kz2EZZQQGSfGx0QjsOFeZd
r1r9xL6Ic5y11wtxG2AMwGIptn91MIB6XMRvEDzsd8BbaZbtSUAvLwtFx9DukAl8XakgJ9QstILrg5M+D84QgF0sWt+gBOhO0vVomaUz59jGauQdME8mbD
jXoYTZtkzKR07HqskjCyawN42UBViKGjqgVWRgx+Gsk3Ioj1uKl+Suj7t0HCZ/KxoKb4omsEs9gGTXDXE6+SLR+EnB9uPWl5o+mjNeB+kiSh7AwRo+AtAJ
pAn8FAIvqZ4tx7AraPjFJflSfekWF+diAyjamDwTtXxv2j41AJFrpzqqtQmsGAymRc5uXy2V1tsnYMBODoBrAh1Q+GCDHbPr2BRrrzRPYAKbSJItl8ue7H
8EN8ZLurhqpL6KN4+vWl7QBE4hD7MreUw+lqrLhkbmifGHAOQnRCo8Q6paOxQrIQRb05Ge2sX2sDLGZrNGdKQEGUJrLMcgr+Di4CQ2P9H/trP486XUkacT
hlUygec+4TJkh88Mw5d9CqVb/ds4Lk7pVT+CvbthWxFrlm3HmtIDwHOUllOIUWDYS3YMR8iAuV5evsaOHWAxMQAuSgd0AFdreuaa5WuuhO02j3JCba2vyd
3I9RSbF73sMFY9dwl/nkzuiIqyHXzy/GVpAJFP9UElYGSjlPMx7ks8vfIEALQ5I19dm0B3KpTQLmcRtkAgs2DHTvc8YOvJCe8WKlp6NCAJZyik21uVPhz+
eWphTXRCqcpZ9XqfYAIXWZTxPVN00MJ3t4PgfXR+RSh7sybayIUE5Jc9eavkS7CfzgSG0gSip+aoROhN/XmpgapQLDzri/tnBUA8seiAMttQHpQA1IagGR
xrAVFfWsTsH/JvoiAmQGv8UT3GCRChEFygCbw5BQN4g7yYTDM/GMUTZnRHUi5jZd9CbCBX9ArMr1W8yvfVqZjA3YBdfAdLoDA9xauucat84nU5yJNHeoHn
4dwZN5bElltI7T4af2gC5XABF3zQT4oCd8GgFDMAjKsPxQf99rd3iSTzQtqbLu0d/HXNKz4FLGM6N1KNKZ9kApvaBDaIwSTe6vpVv6BbpKL00Vy4ubi42J
0GAKloNmOjA5pp5rAcNtC0x2MBCPsq3rf7/e0V3MWQUgND5YF2SB5IyYnJhatwmLMJi/XurbEaWArLZVduZMRsHNdUazsdBGPNxRr8hAuijThEh6HOwImb
wD3OXFlZGfwr1VgMx7VZ/piLxRWB1yRyBemdh8b0avI/RYw/JNzjwjq2j8o3GAXufQoAi2ouWSHujadnfUUcqqiwVNimKscm0wYQHJiASX2MTB+YnQu7j4
GhbTeooRDPt0uVCFerYRyw1YJsUiwuH5qFl423coDF/cXJAxBL8NiCFJXLqWIsOSGuLPc22eCoGhNq+Aixckdmtu5uY8sk6oir1/cB8Sc0mDFbE3AS+euh
CZzsSb2gDCDzVAXCVAnDENX2PZe7OJDk432X9BDBDxwFv5qojO7SF4gRCqaiNflWj13OLmJgy/jOTpqY6gzKJy7Wyk4HJx5KAw6t9sZkJYXwZ+StRRUrRh
YV46ufQEijqYAKfHV84hbcwqr4693lgurLLaxjOwREjDMzZTSA6Hzhy+X+5F1QebN06E+tMT9EBOqV4QQLLR58N+7Q6B4gkWD78HA7YsHBpAF4wLD3ESxG
c7T/tgxm0fJpgDMEDEetyhNstSj1HeHTXw3QE+Xq/pIXK/MNDrsnQowuQuZO2AQurIlL78poAHOIFC6YZBSYl9NEB/ZHbCQdRz81iy1kLFDcGle6NCHrVV
Rz/M2JG8Do9x1Mh6ABzHeHT1Sr9dRdoVNsDQYYU8kY6urhjrFNGN5ieAnfVgUE8o++LSFyRUF6wt7S3Mx3S0uSElosPBXnqTtCqsMUttBt32C1mf2yw2pl
KRDFAikWmdLZ+5jbZvxWShOIxpZ80J54rJJA/UKcsI3kahfOBSLor8vPfWhkRycDwL1AvAGzP4BPlEeK4DwV2eUundgSwfqyprbDhfbwZYK/sosvkjfNoo
RDtRhnvsWrkzWBj5i4KCPAf406Zn4gaCTudr+PfrJ38o2kdXieiT9SUqPaBu2jrYvxVWphnXBu6REXb7BDlQzgEQA8zm0OpVeSGHUkyHp6KATYQ9eOs49x
hldW5SEK/ISk9SaL1kv1paWludXzUcCfzwEE0RA+FSsFQxEN7OF91M5+c6NcHjLpU6OeZ0BawaGKVJuhi0k+/3QIVDulqITcrxhpmMXWShKqrmBc+uQ3MM
X9ekHOtcDhovzJRAF4wKj3g7N03s+TzShXPGLxrT54cNhWAzzGiBoh/gqx2EexHhCRgg5uqPqyTR/ApcwhtvG0JmkCUTDlBhVyP+yM3JQYdArx8gFpU979
hgnXOelGSg/TVWYDhz96eKt4uo8CX1+nY1WRtVWtenzCfLQ9ZCrBsjxxcQw/y7ZyVAvyRGKaWdjOcxFrHHluxlVziDnZwZpglXzQj63bPgGrub26+vT8ez
nPPFolAD6VCqHaOZ1bj+DK6uIiKezR2rMuMQvsKkEuTvKxyLetU0IwFEMMheCNNmQaRgZ8cH7W46IlAvCHS5xt31WeMjXvJ7TVmQkZwG/fla1Q9igkn1G9
BcBf9EBF0Chp5eeqaTmRWF0uJrkucup1dEEIzIwIoaIZ/oXwn94kTeAFLl79jiFrVM4jBcIV/02pQD5PYXkrEu4J91FV3F2Jt6Yr51y4TU1qtoZIr0NuBe
brqxOvRFzg7NUN8NlbvDw24dkconUInaMQ6IqwPGI3/UTTdhTSHi2sA9/pSj7ax6ZhFs5RACJYsLm4gMM4o/P9p89ZsBVnR0tzT28HLPjh+oaooRwtC5Ph
fz612boeNV8KFj/eaVxQVbuhLhZfVBCAoasIoee0D1pCAP7wQwTnP1XFLCSNGxMB4AZEgNgEyFNcK4wVah/K5ZoQ7eIzNb+mUDgcFTtTbY5to9OL6qvrpW
uCxem00fDRAefC6aBPVZ3kYaUaBB2bvGM4YKK/HPdhPyutCO9E+VDlgaqkvOVFdDvHMaSD+Xsu+4xjH3SiaRhaFtWvynYeBEm4DU2MEIE3djY1JjONnuNE
MzNXj0rtHPxax1Y+KIpTfLyOQXd3bW3tYHEhZnrho6dElEpz/Qi/cI480H3bqjHHTpNXAXs+aScnj3BPZwOxMdWnUY8B5UFD7YOijpQaVlGK2DnGnpeWzS
JKobgyWQCCxSASdmjED9LfEqwG+DtfMPxKRKAzunDwT+6m1AYKq+Cebb+U+zrmPdXwaqWuFz7Bw4q5CuwlY81sZRodDo4XRcKKKtQjlYU/CQKbnA0IgCrg
s8vmAAJwqanLUVQr3mmoy+Mc60jKC/sYCDnZ7JJjDQIUDGs21RjRfOEbuyYGdl42wzXks7Oa5sgagX2aRx8Uu61OzR3s/vbbJRbN0RaA89nHqfbgal6+3g
3YbJn8DCeWNnE0bdpVwBPSk5XzOY6+MXOrFbaGNdJ8wLRjLPS6Qm2BZAaeqFn28OkeBkwEDwrpOqYx23ciAFykpD0YQNQYcn1Tyc3DTOb5NImosD26cFxL
35g7Bc81eRcLhMG4VzSQPmhFVN3JBUxdbNjBa7uW4rIoT9gTQd2U54K3iVUE+/jrUuqOuChqivVO38pMAHEwiYVHpQI+qFclH/TRpD1QQD6njCuOXjZfLE
0YHepudo/lZ5ds+wPjdgaAin/GmDMOgOBc07VDEvxe71MF0jKlottzKFNRX5qhYe6NCosuIAsF7rSBEQzBwoZKy0U+3PPgI0gI+kftG9WauOsNiBHiZAr4
jiza4sQ8sK46CLynXMLVZQnAu4K1HxZSkm7F4v88ZxNNwqyJ8xQBenJEl2dSk5qReF8qpFQdi6X3WmQrUU+xubhbMFkO67Gj4I0n9IEPildrg/Uqk/NBJZ
UQOQXpjKBs6Wfi2nLKUy7CVXHcAEs6C00fggSGnXQ0CjoukyY66CqtizLZnvRB1ybrge7L2g2SF+AgVlKXC/ytg8SzJMXSPASGwrD3iZwvkT3DcU5oU1kk
bIwnH/SXSQCQz9HTBxvjVkJkY557soGJeNsj58WJ2R3DeIQxCmJjZO+T1pvgR+RCB5E+gnJCc9bmI2kdS0cdJCZXZs1a/CIGgVQoOQweFLVshtYyLfWNRP
AEANhl7JqsAV7xkHnAaJKa+piw6nUt5K/IQwW4FvAtpTbJBztZNBw7CF7j5R9ZEcZS4Dxv6QzUBJ5Nxm+UVTPGkKMeUcz9R6c6SvnJ+GmXV4RvH2P9nFDF
LdwN8Ye8mSQJLKWviftJPihKhKo86MSajfekY03UTJtqOgxHf8fXgIPOsUEWafLUvPT4F1yWCQ9jE+gwPlaeghK81ETm0cXy6yRcavG8vjQ39wo5cXj6G5
UWv3xPXCxbSM90knoV6rP5cK0h5HqOjn5lPDg2enBcM1yUTeKOYfRxQwflAZ4/cK65O/taFiLItdwQh8rpXL1bkNrdsXRUab0tjCB4AgA8gNhiBmPzMtUK
KLMe09C46C8XlXSjmui2vfJihdkZAHriTipNdNXIVh1RvA+p3Wy+yiqTY8NQM4vTZDX0t9CiS0VBLNXhXl5bTmtzPdhevTMy4zCb3fCYEOaGxndU7AXYcj
kVjGl1IWKSdDT0QH+XtgjF6FQw5FKol3Qkpqq3eafT0d2CdragTQX+XMaI5ExgglcWIk4jTWE6Xoy1b819K6SaYyUMGz12iWEI2FR64/oDhmgjiUjVM4tk
yUjjEZKM7fN0voY3E1URScBDoha9DgduFrfVeC3JMLhhC4wZ+VkDgGCJ5r4NxOPuRKloa+IVeWx4ppqu+rwDW5EFIGIqmqbtKl5EQWaICVzMwUMDgKXCN2
a6eLybgIlD25mvsGp1UsSRbiAuUrIwLMs6nWA1vAL8qo/5kSCtywUfVIjovfCPcj8HPIU+xlpOHvML3UDXQW4PVaypZDaxWvwmY1dI4W1A1DNP5+OH8d+c
zaw0g+xcTvJUQlOrPHWLNpk7LplBeVC0FEJdLJNp7WDoSpP5QwSiPCA1wQ9YaDJxCIGU3k2Z6A6Xt7v0P9KBrc8yj1RCsJouZXTkBYYFqEja2gqrvE4qgR
tsJcknFg0DWKg/jQS7dPnJ9SeTiwExBYPJNaVZoz4bzumiexUMoJF+LdQDFuT4lU12Pt3t9dI4su74KSDo2wAAG3ALtibUwrpB6wFv8IMkqhADDifUV1gL
bo5tow8UvM9rFEqMH8qSODupx83yg2Mhh3kpuSwB2JpYEBiTCyhT4likriinT9PPI9OL1nPBRyfHlT2RHteRqkW4zBkDQKzFU0eEcKsUBE5kbvzGJp4lAi
BJI0EUKGo7uG3NzGdD7qBJZNTT7pjwrCQWT44j1/vuulzXLEgnmku4ES2r5uNf5UuVMAnAHlE/18Q1DcD6VkFPj8GpMhFTF1/Ad7sTAuCaiKjFWlU+yx28
XAMZkDdTtQU5TjGQCxpkXMnDlAG8a57WwDliDA8cHGcee80mVYjYZNF+fKFU9OsXLs53gKU9SNVK6oGGaPMohusYBI7eJ1XRUEEgPZMLAkmvABU2ouSWd3
U1GoMzd6QngHzKcibj6Qa5fT2qEaJnFm5SgJYVMyVMMZkgUILwN+Y2Ko15asnDlqCLAECXj9A+5ey4dE6bplNy5SVbdkrQRobIRMPyXX1imy4JglI+lYcd
u2yXVb4V7qrXUtY86OJltxWf+e2tguaO19Gt4y9X2u2Vl3BuJCN7ZgI7e/FGx3GTgrndxDoSOctD0TbPazE+sNRVa5uHdD0VAj5IHVp/PACp22x+nk8uCF
xjQxypI8m80tnH3QhkJhs96mQ9y4fx5wyPxZ8ZBQYsXeS3Yzqs53Q6HVcBsDexZv9HDAMFZ4Dzf7Q1w6NFwp2OVRN5qsFOwDO9GzaP8gFYpielaZ65KDEI
pFlldLFMsGrbaqDXMK8A+AETTSOVEmol5U5WiYfJodTZENDTiRf1njyZMXWZ1kLzIHYuq/yubPhn/HVFyxP+wHWlCs7K6vmiap+6+/L99rW7SmG/dPUbKR
E3c/qdxew23KzmACRfqkDbPG0w4OOIJLdpJLMtV4aKcaXymglAEY4HICW453H23oSCwD3OkErhi6GqkXdCV/qYVHhdMTOgpcJK/DnH+KBwB7E4/ek3HafT
9D03G47EDEywRABA0rGtVj+RNDI+BOw46DAk6ZOy/UGlMHNTzRQI22lLwjw7TRtVv7WJ+hSeBy6bbHjJzhfH9rwOjbX0KAszOebgroIAmUAmZBk+C0An94
6knKE28gkNVgaAQzv59ppQFcSkpUw9HcVe4sFrpWr+6PplnpSKC/VLlAeFo12/W1h+tlyQlDD4+SqlTE8NwE30QO0B0VKNnjc5yokF9VTOvrCdAKtp3K0O
/2tRViuV1s43KQB64wGIffEIQFH1JnNYkUqx00m8L1IIdhm5+gCMb0wDCAZdJH6ylTNaSFd/yZ0xGKFhlJPbJd4yRwCiOJrKwkzIV0Mi9k5HdnFnux9w+/
JKDnSujNuB8iwyvaEv2ya45TVsNIv3SghZ3c6UKmT2FL0+r/ppwhTjq2ASAtSQwIIyojzMUgHC2NlMZx5wJGA5W1WhEmH6zHFZwtCi+2mST4caAl6rLMwu
ABACr7jovXK1kHQQy+MtE6PL32DZ/tQA5OI85UCbGe1cnPcTpj1Q+PvfJ8CKq050QVEOpqBG36SASpw9eyxXCNMW8/NoMvhpBpEb9d2gjDkY0YyVZzFlgR
bdgZtwddkE4JbxKQc5dWsS0sYIcTjCaGqOTyrh9FWql2EW5v5ETume5KHNsxGfUtLlRZ6X70gTaP6CHw9Jt5uDISYoREzs0q7AYHSCIu4Tl2Uccq4nyjPf
lGOGyQcl/rzP/Ozfjulsb4T/irszcrvLDKhrJmYUi4Zb6GbbtYr5Cl0cluc4NaHToOeu/+CyB8spAKZmqkkESpra6QHYZeIidn/wvGKKl2SD5PMwCYSSO5
ccye2CSRbIWMDoCABCdA8ARJMxGb/mEYvAo0bNK1MAUwVpbsqlToWqIo84oqOHkTZlZ6ySGkAB1RtaBEDw1fikcjDnZYejNdoZTtuXC0An9uZsDcBB2cJs
lMtZ7uPqMWypLK/MkEqt/qr3SW3xRx1BOSyrUWlUhFvGvplmFoCuyiRkjB3GArXM1FQ0gDJAMHQ1pVUM0eAHPMkJqruLgoaKIqNt/vBbJLY17axQWrlbyM
BPF8WLKBhzWgBSEQJDAytnRo6LqRXTA103zZq+JilC6OvJp/LTnU+XrY8AIET34IKGojeh5PYmq92wHQqKMsqzNJRjK5WDWTU+JrdGynpy6qpwT8y4l0I3
HceRrGVvYj2BF7i4+C8yaFaO2HGHueW8FnHS/neMmbHgtA09rvJJAbFpMgAcWk5q7GXMtFHRp8tcmYWZYP/mY1kK8CsNj6RAvew4UUprcmsEf5RtSeejVb
40TOeDNY9NFgRThAX0ETr4H0lG67G1S5zp6jfWvduFNHMqoVtOxAIiDQY/dGb4nVRRasVVeAXAO4bFiFIAPIxHD+cB8GhdAAIg9yajD7rG2jt400cj81TI
3zWItYVMrijnBvKO4RGMLmggu8eJjOahLsVkGiIeMXYRQsDqqKsp58cNxwDQaerUBWVdkKSdSuZG7ShjAfNLFB11s1iyDjHR5hUwAi4pI1QaVVqIN7IVqD
rsZVQpML9ZUQBM+yAjVV1yBTSTO/OeQjkjAWd1SgDCs91PDEp/fRSAsoG41Mf44rQA3BRtAOAwXQbT5CQkBCQ1eKSmmhbDMQF4rRDjr3AyAOoSKwGQSIYT
ycKssYtlx5KtENlZKgqAMa88DUB/5AM6Gn/jaARmqIShVUf1YBAAPW9iJWtKgpZVsWjkNZYHYlAe9c/kF1zX4F07rlBBH0Cvv3prrv4/2yIDwGwnBKZIHe
zCwJsFxwB7EyOjxXkIVQ1XAMzyAdA6DuORVnYqNxOkAEj5TJHTW4xJAaz9+U72Pan0bkNU51UhkH2D/Cg5ubCwdWcUf9jCUS+VVskPPy0AqQpouzyvx93H
HEwKgH3z9nTMJPVqYgHx/2kABs44ARMiOSEAsclkEgK9C5y9AgA2tJ5zigXf4dqk51jAbC+Ayr15R6jd5XiDqpNNtwROKluxyYJ9ACAPrJwiHgZN5STU06
MEOhjquQFzUraS8RWA3vpcXSb2ljMA5MaAM5uSpCTG5VOpHwAYojbhpMhoiX1HmgoCEHOalgFAO24JTMSEzOIIxu5lE4CWn5t1V86MM+oo6PqKqM6qAeMR
HvZ2QD1Apbtm/kU2D5O61NytNqNL6LQADHAMhsPz+nHgQ32TAWBqt5oJoTcBoCpDbB8FQKPdCU9slADw9MQtnOxoIxtzmNuMy9IANGNAiOat0UIvP1rjyD
YLacMhthREEoBSoX5C2Yq9NUwtoYpVXq0EDpeVUrd2mgPPjSQdhBkMa/wTrqXnRC/30wAMkklYPiVJdSVX0pZJ8022Ok4QgAuc8p6NBjJVLCtiTqbXMneI
DP5ShZsSRY4K9pqj4XzZz20LsEcBqMiKfXJCSzoUlDm79vmVlZU2PCv4ct9OgAnTZcFMuePnxjl2ml82AkDfBOBhcrBHAcjzAAhHNsRmQCoDzbMWdlnySQ
DwjQJgbs3jodG0mCbsZHItlIIRqb60MQBEKxFJzRNP1jVlP8RkAVi7IRnXOeU+uxYo5Su44B0/k+EUXhqAz7S0Ab2D5ZhbqCPhuMOKG/UJXFhEOQsUqKc6
xCQ1FzdpYRKAKoN9lM6ikVxxnBQNjRR/3CyNB19N8ygAYuhQbVQq3yMAVfh3t5QdZlGoP9gOdNWG31ucBBd0EW/WTpjLVQEAXkvRW7IAjAWK4WS8KJiK/+
l7VaRiQAdMBZ5YTmfeAGDFnQAAuwBAC5M64ZWcaIm6hgtxwtbM6srmzkxGU1aojhaoD5NCGmKYE2tZdq56E2qdwzIgVmtpXlBOtc/jxCWz/bA6Wl0wWaK2
zb5ZNo+UScaL/RpFrnRTVApSDLKRi1aZdCGQGiMAGwhATwPQtscg0Cjv0ROGqbgu5IGf426ViTjqjzrwFNtqAJIFbBu2JKMFsbxcerAiRPDbwqS6ITYoae
+JPInoBICFwjEAbLJvklNdyG6r0W2nssTx1dp0CIAAQwLg6VOGXW0BEYD2aF1lq2DOBXkYpK6JzDfUjEzOuESoTdF9UvCUAJSt41VvUsJMXS5e7eBhGZZt
ayQ+cnx/1PDlXX+wiNZ53VUtz1SqEhMDUL0sebVw7taa2OAst48AWJ3w+LVNTL/6EoDgggKOXNftcXhQfG58pxhSWDCzWU7xuHLlUnkOAO0UAL0KDdWhPE
FO5UHD8k4g7i/En/yUADxgF3ccq5rfhiIBGE/RyCRhmB+L3oBn007qgFnfLn0Hh6nt9h0nIJMhAXh6vwbu0jch2FfhXSnn1I2wEJ/oexRKKfcrmzvjzMkJ
W7NxiAYgntaalQDQmzwABybvylA28UO3ZXr8mdqCKfXS+2v6XBWusiwA46OJM66Q/6oOcKAA6E0BgGQC5xUAXQhpuXnMjmjVNCY5WUfk2in8YCzLWNcAdE
gdWwIwoHyG7JW5W8iZqlYonRfBwoQAeI+92cFb5AgAGlKfqTKECUCr9Vdz3mIx3Y5ktJGkWiXhenViAHJPUtFPH89zKZvlNrOIQXGhwxQTxiBjjwIQ56qN
JG3t3FQpGgkvDJHEBQCktp3eRAHYwjKgLXvGMmdQzxmTkcnK89X1eqGdbkYxr6CE6C+39G6QC8C0szd1AF7fZdxyGlVq9PaYXeZBEB+zMbCSWgWc+sP5+F
ptDECRV2nSFjAUOFscJ6tGKBdMh+TZw3Yxb6xhofRS3PsIAC4sbmwsLuT/2n3YWEsKguZIXYsXBXOSWzprGK9GtpnF3RAyE/o+neB3jLZrfU/DgxNdGZxY
jATptC5O4CplK/1VHPjYamYQg0ySbdO9yJj0LAC9pHGcskZ+OAyzvjr8zAcjkfyMBx1bDXT2JgnAN2UNwPSndPXMgGDl1bfrcugCAtBYWGjgKDTITbKo9V
5kAOjkJ5uyAJzsQCu4OENrvkqpaARg7NjnDSmW6SYpw4PN8oyHR7IjlPcz2vRJAKxgEiakoB0LnAD8vn5F7X6pmIfAdfERsoQHciG7Y1hAV8q2w8YBMGkf
lwbuat5dKcX+1gtFI2ZNk0F9A4C2h6bCbzYVUUX2D8wrAJ42sl9YY1yWTr8LRC8FQNkPuFIsjiGDHunsYEdFoNRgUpk4PeUsjhRlI7BqXJ0YAJkJwHStqI
a+1e3+HQ0+XNY3JsE6YbnKfPVymti4IjL+6igXWy4sA8CDiQIQ9QhRn7JG+r/Nsu9V8Jj4fq5OlDNILldHeh6jOdKsrzBQjVZpJA8kFU1vGNhJ2Gh9Sa2z
b+uqYGpmz1Gu96TS9Iscd+f5CkuUDM3smgJglCvJSj0OhnpY2rM0C/GwDNI6KhYUHTtV4k6NhEjpADkKgGpfT28Bz7Ho4TJJGi/fYayRASAm2B6m6OUPA3
F83zDhr+dyIdzB0K3ZI/3i5qBIBUDmVsEZdj02EcrIImMXy7kuKJYWnBr4H6V019g4AHaMPZWFrn62YuTkrSsBYK86DQuIhsLDWQUEwFiWL39HPC5FsWL/
JHVTqLMVhiPlQN2JFf9OIjH4OB6CtDYAgIFwO67gddUw+lx8S2Ms5FS1on51pRMrYwP+2tRev5prA29iGVDOOxhl+oPb/N6waumGeINfZqt91XayWMrkF9
0su8n8KaC/kwDwlBbwQottLet5jyusas5IIIvronibWYg27//mWPyhqUaKBZz/o+vy6E0QuZ65xCqE6+/eZCxgDMCcbvZQ3DV61sizNgHomsFcFKgIR7W2
mfxenJuSFwKqEVlq+NqUAAjemOOLyEbVcTRKVj78bKvpuh7JEudtRbxQp0KtHeYf4qR/hyYxOChM2BNVaQDBDoeBWKH7rDS3tCJuzyzJuWpziEGJvzl+Qg
u4gOPm6TjiRKWFYwCYzMSNm0DqSp9UlxgSiplIbxVXamMKgHAJGzFIOYPATKennQDwJJH94r3H8NzLi2vXtPtObCLRazjppLUMAk1bYaaVnJG6hYFAlKUU
YbrzJReALgKwytwWl3WBzYm6oLadQ+cLxdV4oqRa1VgAepkgMJ0vQy3HsQCUKSfXmxIAF1nVl+5QbntxUh0LsUIWeCbPMMOAtS3fi7Txz2XJJklsjg2cus
+RdJ8agF2cp1afm5tbb9Mkmf6r21H06tYSjjbEuWoJEWjmGI9sRScwwSR1cwDICYC1lC5BM8nar2cAmIR2JnOLxMsfFMx41ex1dcbLF6NP48ELaIiTWsCF
+4AEzsnA3v/vhUyugtdjOkDpNgBwXje36SEDxkQsna4VJg1y3K7LwemDsZ39hn4fXqgu461qhUpzfHGyMaCl78cr5YRPe60QEwYLI5I8CcGafu83qSuomM
4ED+28y9KOW+LRt55KDAjPWxZiPzOex6MbUIhyLZjnpxsXJfbKiD5MDMPN4yYIzLYxx41OeP9jpz+timoSfgN7U/tLZPXWlSsX3A9Qx3QJn9WAnSwLCgbw
gXYgS+9zAiwAIFEMa2X0qwPVH+3ZI11Go+TJtBSA3RTnU9ntpGgv8nvVjP4danZxqycC4JM1eDXrpeLD9WvtAF7yvW7qvtlOLMFcJNzGvLwim75++VWxnt
alT45fNOZT0hFvHaMulSJWYKzJufc9MitarHV6W4FlCAKgLsQjjy/0NG+T+qGV3S+MWjU31UWPcUUKgIfiWP0sW9HgTAD+MXEA3mStgDSW8pSjMvV37IWH
i9gLHascPyjs5g9jQoIIr4RemnlMSxm4oZZLsOj+79jzxC/gwpWtwYhAEb2YmZv77qW4t9CFZ2Fh4RHlU1a/BaOYGLOZY4hmcY96KcgFYLQjAWgqmXqaC+
HEap9J0iJdBoxbjiG6qhdSVZP6iuJoNccAULtP6PBXTgrAA8bX5WyH5cLDazji1oDgGg73VhpyxVsB88ACIi8ZXpwK62Gd2+lJU4mxcOXUryz5jL6rFUeJ
R/qgsiGXABhwJTjbm0AitMtJewgl5MBDCj1FtPa0DWytJGyJkdqC2R1HLzwjtPUwyDRDjJHmRQ1zS+m9TXr2oeZlyY2qMesYAFo1vUDw9DGtPkDfrebyVL
9jc7SYItXRYbNDObIglGpvPnLMe0Kq01h+pQHbhgCPhDAcx4XdQBLc73dPxoT5LVaKKIx1QTGtkAag7uag2k+9kO7H0EGgCDopsrosGiZDh9AH3CY1Y4gV
yznj7PRMBU/4pAhQPREAwabfeVaM6ZzFrW14JWvqZnmCeo7x3/6tYGGlyhXvLT6rPVmJToo68RALsC7NMPSThp5UrV119h/Tm4vLkeNZ4EqlgQfz85gJPS
XDZ49Toxw1GxpnzNXXu6sj8EI8wCoFQLMrWeXLcpW2SPHCHqMfCRclsoM0AG9OHoCoVo8Jg/CIfFgsdpNDukur22BCJ9ebEeTqAQaJsuTj6FHssupJ5S6t
0Ka0xx8vpmvqu/fuHZhfmjmaXnAY153vipxXlgCwGVM0A57Uw+TEh0K6cCaSyN6czcWDUgy++vq17ZW/vtcl4sjz8/oNY00YJaR5gmt1kd3O9CY/PIw0BB
davBR/3LnbohqOSlmXB+JwOVXXiWubzbJHYukU3ecqY4/hW5hfo/EsnQFqcCn8zTv4MX457cmUAHSvNDP0cTuvDLt8bTwA4Y7YSmeC76aVqewxCsphkqyo
TrYf0LT0HqkyDY655+wmO/4J81fS5OoIoz+BxCUsA9JshDBWMQlJofDco8XucR/5YwCYawFJSw+8L1fSqQbNpm0y7cyqEW1vRLQnIcVJDC8UosBvCiWySt
fOY9MG472aR0/NjSLPGSPIzFksJX2Ca/UR6y+nObKF5eI1gOD9xYXrXZZMPirNBKzRSBR1k5lr6qJIMKwacnh5wIIAmzR8g9frmGN23GO1KRyigmLTjhw5
Mk+PD07PwSkBiGIpyJhweLwmHmoAqmBdp8vSQSCazXSXVVrmpPDsG9WSJEZ0VzLqYXEdfkoAhBPrUuhzVBt0ItN0zDNW7LzhSnHlWtlRkjJw/nCemwbgfC
OswLX+5ASf+BgXNBma+TA/BgwQgAHNppb6yOnKtZvclkp0XsZMAsvwvu7wt5W5vLpc2uqvoHX3wqaTSj41RxLGit/V4uSyBScF4HNzuqZqKi0dBoJduvD/
TcxjoX5RcH+eKx2QsBmXVuxBepIoHFdiTkJA5SchsB13gfrJYJYjs+O6WBEhAD3GWxqATug1UAriVOWITQnAgCmJSxw72YxZDeBWrhido1TfzKXiar/mak
Zt8qX0a45QUFZ6ixqAfEoA7DLWITbD0bOn7XjsxxGPO95fsZ1QJgZ8WjLebABBJzaAjUoDXvOJpgock4Rpx1nM0vscxZU9FszaUr7VykrRUSQ00HUzPaG6
JFkWsKk0ACO+hPH73GAV0Mc9v2PnDMzIZ+g1mdvB2RhcXqvHAXCxFck+yTSGluv9gPHbhn86dwkBWJXgs1IVI9d0wejtrOJx/XDFwewzj+VVaCs8g1SZLg
Pmbm0oquCBpgBY8XzqmmntnsoyUGKQE0kr9J2RsSoiJZ5XeHYY99kKg4qrrDr7azEjNyn9Gj42vWQrxeFQMraqk9WEMWN8kp3yjqYFKjWKY57hEQCkKcIh
+u4kSojaMj0/FrH0K42qOGHUcHQdMMmClgrnc+7gvfvsg412zsl97/DVSDxUsQVSLSjD2A+igDllkswMWKizG2WcosAx2stJueTHTZTf8DrIAeRylMkJOL
vPS6ViRqiDYsE+fJyXmrYHHqhg4bz/AT+Mmdckve+XJfP81be2VgMWDJrUWdeJB4+h+YvEicmitCZPamy5zG1VIYyoIP6kJa2eqiC4K+NPHJGSW6gbpNo8
SME1SU2kmnDktZqqBeL1vP0yoiK0k4dAZJyLmpTP1AB8OxUA7nGSaB+MtcWGGPuxHugRf4TWD+B66BPaDY2/+ddYij9h8WjmmKLZurZdhVWRcwIIgFZ+Q6
6qk2MUWFQ8J2kDS3PBYMdWQ0sGGoB+r6fZrk6zeax+X+xJNDp4A/ROBsDrj1qsv1RK65pIK798t83iDGfhFtYz/Xk7y8mVdBh1/paXi1uH52kocOTyijGU
1dbzrNlRDYMj1F6rR9veafFqq4ftZfN+VQsDn0pw4xHDaWtWHhlU0Xbfp53KpCOJegDS/FvYu9Xl9PtbLrWpgJLPF7StiuQs99TUmWmUAaWvTdm9Tlqdzb
ZPGgQmOt8ZYYr8Jt2mqEmKMBgAuCxjBzQ8uYWfOaawcj5hcW+DF/RkJLYYSParNSb2BkN3h+jzlNh8+R6eaOW9uNiUyQk3mdQc+qq2aTd6rYB7zeMSWUr3
CJuROJV3TyTKtMvEysxSKTNnmuRNlh8Eh8uK4bgKLhj4oPl/t1SoXy7c7cO1j0NXJFcnlvE1ZtKxo1rmc5mgtmQsM9ZyAYBhRXNxnNNYjQs4FKKDAia5AK
RtSgPwqlDVCpVZ0YOopX5iTVxbTjH8766kZq6OAFDmYDqtaZYBaaHyDaY7VHMBGI7Cj7so292TNJhwDGvXti1D0p+myfkYAVVwZjyJs+GcwhNXWY4G4JP7
sjKm5l3zETfoHgtJzDIcB0DSUVmu68QmNkl7XrUW4aRRf+Ab90m5rLpybJU3HB7jgyoVPwAg+PPuiefJPoJPcvvaXGkEgBD5lF6U5PCawlOcRhWOU5B3xY
Nnhatt6XgkdEETgM3qyO1aO7YKGFINFcx6DwNacMjnK41Y6d0/Re2sy8WAojd3DKXBYS8zHsF5ZQvoI6HZswxXvOyxPtxYcSHiG5GZZ50ZT+S0eKeTSoLe
vD6lIBB9qrIxI9cau+LU5rBe5eefZuH56aef/1LlgjlHRZBKF0x6oOABggMWOg4G15iAcT/CwM8cd6G8TOLt5YfbjD/K2JMhpbdrYwFYLvP33wQY3Q0wsa
lJP2ZaI10R9D05SmrgNuxjASjn6WEOhvfccU2L2cN4DiAY9WdKyyP50IJ0lwGA3woO4aWTK+iD5X+2uo1zczsp3ksySMJ3c+tKx4W2nuQHuXif4NwCFjaM
Xl1XPD4FAD3LQT820QO209qgsVcZt7qLuMXWRXGVMFGdt61BIKLtw6tb8Nz5ZkUI90OGr2SnNkpSXGMq9rSSoFRwIc4Ec8epr5qikYnnySs/wfMzPviDiq
hZxwNwIDwnLoI1sPrwugH48z6GaT4WgE8WFrqLG+cCdtv01g4z6tOP5HI5z2OqSPw1I2UnrCO14tSdErq6ql0+zgW1KWkB6+54DJPCLcYunGzRl89hurJ9
CyBYLKW5ctIAlgp3AC80hmOUBi8LP4J5zbTgZDxJwvHzi0x+jipuJlcvRwihQYf/8ZSuL/FjPtlx46i4RunBsqkTkQDQ5hmKT+FBLDbvMi4nVuq2YXCvcX
az0N308bxKO2d+dVyG78CZrypJprfTAuCG9EFrpnxErgtq+KCCVX/6qSGhRzD8iY8JqjK5Y2RNYO0IU4DzmLzw5YzAj7goZ0Zw1725cXDv/n1druVRu2Rk
C/vpevwFSUGuMWdMCPjBxd1JDN4RjQ1lu+nxREjAPh6AVF2iHL3LiG356ISrfvLDOaSOR9/WMTGUlbAiOmhbuG5GAyRx/pucETNAu5wG/pyBx7MjSzjv9X
ojsgExxTchOckaYggbCgecDAXTPezS1flkE7iJNE2iY+sJCYlWhq2aArczAl7rEOEGaJMJgEEMwHjFfogBReh3RjRvMl1PsE/zgL8Ob7nuVHMw16/vBXTH
+ErONM7W5TBakg2q/NT4y0/x8/NPr/NSMPbIVAQ5kwIJ5hUIAZ0O+p+Iv48ZqDOTaZW7z+LZN9HLle1rVx8WH5bSCgTmxLqbLdlmKfwxSVBea9r5qozZq6
kZumYR1LKt4wHYpFeAeumky8v4yYdDPOmSGexvFXWSdllXXKhzeQsOHPNyMVP2W1KxKa4pOVdUi4FHdiGFvp73PV2tuXNLTHNkl9EDJTvRc+mhhlw/Di+t
U0SBjxhlQZR4wUiHs8woHNKbMKS/H/QpaJRccjc9KWpUVt/4oodJgSQf1aRQHW+WFsRa37tTCwHpqpFOmRYHJZX9Wi1HaMJN8PfzT6nHxSls1jg9Ub0qj6
EmEV4rYNdDzQHlHyeOOWOiDxPqwct2/8761sM6OmLZZD18aV2kGDGcDogvvHxqh5cFJviYVWdkgJwj+x/NhoqMpkE+EkIREiMdTAzafjiulz5i8ZcjMFX9
UuFh//xK9HL7DppDnFojSwx9lH1y8u6BphsalUjbGroDfyBH5oksx7f6M4b1sMEVMRiRO/ciP2WIuGTTtxjZP4wCH22QqpC2rp8+1atLBTLH0ufSOFBJSk
HcKZSMxtzCs/pL2WUMF4sRAlqZmNdJ9clJLDMcCeyoBBXtU6fTqSIAwQudYgh4/fovyM6yzUls9gCHI2mbb6a8FP5mU+j7+adGTq5qpLJiS0VaqbZfqfoJ
/j4qTtAAfPIbImDlcL1eHJEUjX9EZby0CVyDfe3QjPE8n9ExXE/ZSsVEMNDCVPhY1O8TZE/uIAVAO9+HoGwz8d1wmFCl8hqFCVsnJk0+ucSCb7GkXnz48O
6Dbfhkh/CzutacqAeMs9zsru8Y6Qg4XQEPRgfFkifh/kyBPW5qL1MFVGQMrXqgYnrqcGGtqitzhRyTCgnF16p+MoFkAYNAKtmGyZgulVGKU7icuPP6ADxD
HRLf2AQnlz034lFr8WSSGpMApGJRB/78agXbPKbFg5FPgJMoiB+pTTuKETAnEYHR+6juyDT+YK9cI1JOwo9Mi7/tyU4kCmy9yrwzD/9G/H2cd60A+AT8sW
B7vYAz5KXwf0wRSc9VKhUORWD216EMDrZ5jQna0j4LhKvg2soGLB+thjIbIoeFYGWHKY8CsMlqHemBMmqea2Ab1okZI+dYdDde4fJyvS/Eytby+mo8dgTD
HiszVM7Qh9Gfwml2HC+vuwVcmzi0/xl8vzQAkSUEwGVxW6yK6RWrQNc1H7GqpfTfHKvy6aZjTZcY3eznMKirkXgRv4/C+opQgrXHqetnW1RC1S0QyZ7P8g
f4SwF/IRib13BHulPQo0i3fErYSY6HVD7Wre2WKRNCv8J/yuKvIlwr3wKaAYMk11FphThLjU/CnwbgJmPthwZls5gnqx1rRdxMJZ0cK19vK6dw4HpOc5gH
uJFxBPZIyJsz124oBsoD5bp3B3uR+YmqEYstXi+UEtnSAp64YH31jq5urTOZgsh4LvnbwsWopDv4Moi/nzGtVhHDkYOvUKv5sCqmd5hqGq+2sKxygfEIu3
MdNaf1VEGgIkXbecGNrGix6PAu7P/D9cMVwbycyp5zpKqUwrNiwAqZVIJ9Cm3iK7mNymsSm7o5RQB25UodmR905M6E9kgGQo299TIG8KefuPDHVrVjLWks
wtsdldmlu5/8z4/OLs0o1jXbLvzfeO/ho9X/c+A30hrfpey67YzjjmecN0mmP46Fh9fVqP89em5kzIQeKDXP+bONRsNx4I5d657EJKQiHlratgjoHpI+6A
q6ttaI55JXGbSbrRz8vdZp7Z9/4jmirjFVDecXdMilwVYk4rXKavUiXY1uiIP6fHliup8cBEo0DLNzDJNZQRCgU+L1/XuUlebehzziXCbms/ILSr6rLtle
x9aMSYfhHPXXOJW2dX2az5pSv8Cxo5bMq/tla6T6SWNcGPs5i79q5v43d9o2cqiYV+pYvuqcVjmIj87uzqiPvP0Mwp+tB6sv+v3D1asPi2PQJ0fLb6Q87q
Fk1jknG8Ss5fjzmXj5FTPFVQszcTDETNID7alLqNEgOl54Ejd0sXW7WDJ42YpupyUdpagj5y0/A8DxmieZ0sPPpldzcSQHSq+i6SpF+KZtNVVM72oDyDEE
fMQUp6OJZN9TWMA9Lo9lM/NJUstx/GazORhibeGDnTMbw5azJBynSaSKMRCkFxaS5QnEQLIlpKfSeP36daM3GaW3o5p4kHdnO0Fgl4nvwj+UU9qrBh0N7s
kMAl/nNgI6EdySZjYGa1SwXZY0gJ+MPwnABcbu3rnNqfYQvVxZOd/+5k4e9goKgL+NsF9JceDIVm9TdmEMDZbU5vnoPEBL5W+Y0WtPMjLM78gqfEtGgBJ/
1IPXOg6Bm+xpIbs8VO1nMSGktMo4vN68dHuec5LmFrZ+NlLbjZ9cEeYqI9gDTj0hg7gR4gNTBtDFc9oN1KheME/VBoaap2iIkJG1m77eshhLBIpGR2PIOB
7i9gCFD7yBU85X3qTuUCekrewgGVHFth4BsHryeu0pTKDTsQD45XKI4gvlPGa29E+r2RIEzxsNiQr+vGlY/lDuC807VPhrfWT+0wDgf+NVFW2v3k1iv/pR
ALz020bXiC2a1BXPTxqn53eCtNzKXyhf+LMncspvqpPbi0MRVJFxFQ9IhYCN+bgjix/XjoV9SYkIUby+5VW2opdaugV/H88M9ziCx5NCoFlaAiyy3IIG7q
BdwZjXIQNoyoahM7gI+HPjFGjFdXqfXomPfdAwPYE5R3FPO/x5gpgD15RO8XIHL8T77NEAkFCuAVyEBgIQfdApA3CRip54NJpl5TjZeTVLLFa4P71OBYGu
cHOPrAgEHHT9vWqOKp0+iT9MwH+KdzJzXU5/aK8XlpeXC2PHmhULGWGze8m+hpjfruXX4vMFekZ56JWfYyaeOxoD25bmLfCBThnApdRwUDCFo7NWfd0wAX
gsAh/xWIM3dcFsobC/AuA6JldHsob2WNUFw7L3fkp5oNUjuPV20+WOrg/YnVYrNoDBLnhIRpv19+Gp0odrYI7k9eekwJKNrrVXObpSbPAgLT8fTJqc/z44
kinR9G0c16cMoAtb9BrOamuqSVB8HjPKzfuUDy2P8O4MBEai8tPrn80AkOemlnxFkIwT1qHiJikD6H4i/hCAG4zd3ioUiqXiaJfciP0rLD9grL+6HbBg0b
D3ZI9SRSHLc08syNGqaCLsz2Qtcp08re1QU4OllAF0aYoCHHnSL0oh8OaRNcD2aLUTtZg4W1W1MAIgRCxhprfb9cbSe0ViAFOZ7RynOsWApY4Wp6MaITQA
ucSfrns0GqfT3l+UqkHk66aImtnkRB5pCX1gTBpxzzd51s3wGLJSByJ1Fyeo+piCkQDk02OCaoKWZL7bnlafzbXzFhXGmBEszFYYH5PL8DFS4BKBZRXVol
WvVjyvgiys1t71TwQgR6+rmBT/cisQyde3Bao61NuCd+OQV0pZNo1ENEpHjWtpzGYsej9r9OG7gJdm5zNflIXh1DgIBnBgYycSd6tuD7nYXgqA+Fcc4YFG
7M5ySpRCtUasc7Gq6KGldfCxGpUMeFBJwxsnwKsQKPjPmbxavgFM+pjgO0OpvE0GEIe74p/Ti5P+BEAuTsMg2SN9MxpnkzYIVlizx8sOmFowzHMs6/hkW8
rB5cSv64CtABel0TgTAF5/q9bYI6OVT6WWrz4UvZ9iBMJmfxi3t34LEfhBisPCbalKtpVqtUIW4BP1CmawkHBX9QBkbWAhC8Ai+miiT+plK7r99T5OAMeu
XC9Z3YDO4RgJBjudh6lK6/eTuol4ficW/alc82Tw6oosmmLSq7oAQdZqsZ5vJQC0jvTXusaYo2Kh3j+/fbXwDDBYh7jvlhxUQkmYSiVMh6QyFG3m20BLFZ
0ykf3PGB8fVVhCkQdX1eHAACpOW0AyW3FWo9EAAJyKw3wghSvRBJYTOXZsgsLZ2CNzLbKfGGO5nHEK44sz6C5AyFlFrX0wgF7DPzMA3mxJRqg/StGyM48n
emqzfgb/0xmrbl5u4uxWEl0LpFON4Q+OUSV/bu36pwLwkVTEKpXMAvwIAlVYVC+s9vtS22WLBdIE/iG4LePRmNMRSjvgjMuD2p0gKbr/RIlgnQ2uiCNc14
5LqW1P6oFaHWz0JNoyZ7uLLdbyDROIcpw3xwOQl4zrpXR1O3h/WCrU630RzMg3Uao/F6hO7cPfdCU2FogwMY4qjn5yDru3x/yjlQ0Q1r4y2y614kbtdoB6
AYk9gbPbEqdjcC2SwFkH8z1mSdnVrzRH99hcWhB+BCdGs9JgZfMIwCoZwPnZMwKgyvnSMJgrmkphmx0tBgkdbEBjtvEaR4vZR4wXKH/g1B5mcZWZJgdUmr
9PH4yHAGzrsSgEsbtbW3frOZopUjH3uwSnesYZuDYDmyrInlqYJ5HlnCAPI7JMoJ7wx3It9Pc11agBbQCxbwA+yCXwTg0ENo8I9gGA9QSAyDovHbJgdWkm
ENG3JbqN6nMRqh9X/Hl1i+omTsGPEJ2UCDThN+uhWMNYA6hYFZ6afkat8Hy1Dq96NZJt5toAnr6HYI1KjUTjT0ygdJv9Y3kU1YF1YkZacrvg4jukWeBhjm
y+cSZJmKTsqcLA1PwVK8NCV7em4OHRHYCAQI9U8dBboQk6rhzecZrK5sz1DbSAkvpyd7VNTQnB+5Xt1fQIHP3cmlMALC73heI935M3h6NYTlJRYqwhy/Qj
/5yuwzSYe9Q+I8eCMm9c6by2qtIA3pPMcEoOa3mW6vgocIFcUN17Qytavhux24F4NePOoUden1ulRHulAZ6Gmg8jbxZ+JOXAz7IrKuSAHjUvCzVgnLizEx
yddepDeVZ8oeZsUADonbDh/8hmVTZA/VY1KoxyL5FQTv0x+IPXemL4JQ0ePhYCAYAuTppyFAAZ25g6AFF9i5BnuYnwngai76QyMmUbuz084tgfq0KBiU/c
LNKOrHi9VoufqsGfYkAZDj1ASdwV1Bm4+/DhwxFvVD4z17ZkrIhDbO8v6JyTrypM5Zh85x2jP6TKCu5sOl/RM7Tt8l+EhQKvoaxpudIAaomRBSxbY1uedt
HHJg0XUO9NE2G0Hvs6E8G3S3O1Ps1QnLstIrCpFd+2tMUITW2zcexQQGBg3CoVSawYP65VOqAWUbYYdeGu6kaw5QeBfI84b+fTw4xRs4A7lbjUUpruBBym
vP4c+0jn2pUdjg3wyhuOAmB1ulTQxNzLU4lvN43AMJ4Tbpl6ROmpOvmlQ4k/y1GXP/ifvHc6iakZ/KRtTK6sCLa9nhpUnFLJUiNLZuB4qnQNzg846Bo9kO
DNNLGphsRM7OO0wUPGRpl4laMMZ3K5OlK7wZet424cVOwKNyT9Etf1yUffHU+EOSzEvac6zn0uXuH0RBSory89ZezcBU79/LbsT2kqmtwxn9DpCfdnXdyt
0jfYOgTJfRU1WQK0h1SCaAX1km4CW77KaKCR3whbLGdA6icwsgeK1dCkQ9WTSa0rJ0htOjm5NGt8xGQ6oEg4kUVaLEP0pkwFTZwc3pFWOI1AB0JenlOUd7
IzdXJoQDjUBU6WJadcYP29+n31VGPEZ2gM9e2t9UCsPFxeLqhkTCmrVCSd1FL9W2rapL6kvghajN07eLS7piJen7wt5OEOThAiuJjWzfRCYgrUPp5t70q+
e08aQB5fqY/QpoZYJQ55xfFb411zcLyLyehCFeSuimiuXqhjkyANVuTnzvFWSLdoq1mWxZPw2PEO4IOLwKPEUoULboS0eSCk9LFy16gE0Xr5P4XYOOMt51
uNRginqTsRs8DVVC0p1KsmqlhH2fSPe4zshu0L7NhxHCxBzMdjg1pnkIPB54LKWeK+NQ0E4rkLxzUamWnP0a5/2KvAJ/sHZ8+tkMIfUkB/OBUAr+8iC1S0
Y00Gg/9izC1G/JXW2fuSwiiqpvhKxAVug7Kk2g+voIbWaB5lZImSkZZphsylTObQLulitStEm3SN9rJdxedC/epew2mNt4ALAQkuplNNEoAF+Kf03Yrgzz
lbu0TXKFV+ymi0vROdQmQic9SXZF4msMgecuonwx1FawQGsAc2qd2/qzSMSZuGTw5/13/RI3xcUpDGs3icXvenog9NDclmzqMDOu8YHugvZwJAZDuRSm8K
gWWUkY/GtBmlvjjk6ciY+jHhaHccUhjmnsRf73QCN8QFXUQY3V3Ob0GKD2ipXl9awemMsmOwHogqvFbfRVFS7WdHoqlYE/mSpqmf4caYIeBshXn2cdq1sq
0XL1a/1XLTGncX9Dx5dCYalfCoaH+TuKDmUyo9FSsIwNJcaTUS4tsSuAWbm6yGxypEIFph5YQHsSM94WHTNuUXLRvVLNI5OEcVqjGmp4x2+/l5xs7f1X7G
lhAe+p/dyRzKt0yS23zptMBF4ZcnYfqcjGycPAyYrp+f7yFfi8Lyedkzd/2Mnl1G82s7phfa4RRGOJnyVg9lRlIEgopQ1ZqE/R/HfyhTJQlLWAQ8lUGX7U
hPflOq7GOacImePbc0d5tmrUjp2jsCAmtyBBuvX7usRyEqlphycih23v2PIULKAkrepX28FJrUI+aSteXG48YXAzUsSlLVGkdG+//NeXrMXbG+dFs8X0IA
LtX7bTCGgEPx+Lf7QhG4es4JvLTEBnRyRtv7QawOmqQp4I+n+TKsBxaTOLn1PqNZvVSOBBPIJ4Y/qlArfX04XuVOItpjeKEfD0gP0xojFW5M18/PokBMD0
54w1GiYb+eFQCRejAkUWGf61yoB85eKtFOQx9VE7iZHB0gE6JszHB2alRZw69UAX9Ygof/sVPKa8zEEev68pgqPLXm1Ofmlm5FYqUUyzOhb0RpJq/aQIY7
CnFIbWdnVCA0zwulupfRj+wp/9Hs+88DYA2LZvMYWKB2kRtnJzZYgj94Go3ekXnDc63b5oyVEhXhby2VEIBzS33xtL5Ur0fi0W9q8KlH1Dr7JC7yOPVTOJ
NBMptbL8aWSkwoBb+iieBbL0X/fyQAnwrY472Jnck1RYeBGwWPVzmjJqFvh48AIcmzivSyKE5A13oe3BpB8y0avYqDE7fFmRlAiUA4lx0H006eHMQmpYbT
AAz1uGBzUfBJmVOOB+00I1FzaAifVYVoXeIPe5B+mAQAYV9uF5ZHNNDoqdcRfUvrz5lYqce/eIdKq0SS671GE8h8PQnVSkZ06K6WPHaTnPLh/iz1wBtccG
e0K2akM7esulvAYigOjLQOC5tGsxLmIhvH1Ju6Ebuo1kc3zExbsGvogWIJYi54PzdXx1vm4PI50WpqBI6ZEpoVrItvzdGCA4uvGWklqhJ/PdQNOtQDeosF
+Juf0w1YX2enHM6ZWXaLnBXJ6C/bOfY7vjTtk2BPRfNBallkVAJsCZqFfVV6hk7PIwP49gwBCC63JDOAlyloEEnIjCEy4wEo5QeEFxfx4fuGFhWLYv9TJm
BOGdDOJOTIlS2CYEnjDo4h4G6OnvXVdiBEe64Qc9IiTA5Ip6xaeV3BfJ8m3w4sJ51c0lKw2S11qBjhVn6ueCgc51jOaFtaVspPFa0dLnQG9FJXhrE88eLh
TPiN46awXuCsDcsszb3qr848hfW9X51bgrX9T32ufo2tYjGgtC02Fy5w1RQ0FoGWzmPY2RGJuWoArumlYZbQsaoCzJ+M+xQCiys4CBRe9FLE9iZ5JDdxmj
2+SSfb65g4n7Y1tm6SK+tKJSVu7pxPLXmd2XlX8Hhuc6tSccWZFAFTFn+oZ1VRDcbP6isqgkV6b9WlqNmV2AqNTCAZNEj/U+LvtP50rAsKARRrH363Ds+t
W6tPn7ejIHjZPt/H5/xturlfLM0punap1McIsCGvNs9/jcktlU1vko8zKpU8RtnMqamKvG9ZmfFeeeqvTalFhUIwyFqWeoZrjx6hbmwSLVs2RYDH8PMeBW
JlCxC4/jzCmb2vZubIAa3Xl/r9OrHxin3Bz+3KHv0OUaVH4kA1y8GP23riOV5N3xlFoNQBKhtREgqLYFPudrFg6tFh3+Ud/DD1l+yHSZ5IiDZUTtBno1KJ
lkHSHqtMNKImQ3w24Wbx58zOVlkQU+QbPVQlPFMDSOQD/b59MMZNK49PPgpAksDCSeroppfxOx2Jvw7mP7EAUSX8Xbo+KQBe765JDn4QJMrqWvsfCw1ttI
Z1igHr9VX4wHEDrNfE8k5PZZoslWAbhZCT35fs+GEyszX5FZ/L7qs0f0bmDGUFgsaXRC+pEoLaLVbSvOo3TuLrLHIRPF1CY9+Pns8sSfgt1ddX9Kz44jZJ
2mGnhVIl4yMDHui0CTfLJQmD0dnOmvqsEgIyS+F0iJPQ13qQsSznKuNzgD+wgBMFIJK0eEwJaY6ZWBj6ecmYMXweZS3UDZzgb37WUwE0JTEauGWtszWA8s
JRU8Nx0ndopiWMRqts85xUaaw5lKlC5TrLkV2prDdJ/KWk6bsHazygZ+3cud+6OJ1ld3MNnkvnLp9j0Ry6o3WMmUqAP3BANfPZo5kUqAfoJOH3KABr1E2W
vmzHWjo61dzOiCc0A6ZGAqMXAC/g9jp8nvV+JLX9nHlL469youwUXDoierG+VK/PoL9dhxUuzT0NgocqHC6tYKGMo95HT/c4hVcy8oLlGvymYfauqNHI5k
wcqG5Q/N1lgCLmX2SSHPGnp1LEz23xHF72+sTT9pvaJlhyp3KUPQeM1XI7GDsfcnYMme90DSre8wDxhwnQCjNkhRsN3LFz18/6WVhrMVJUciiS4/5o5Q83
qzaqAeDQLTQMmNeRTeB22EL8oQIMaTCtXZ8oAK/TTCR40mM4n8h7BGtkdEpLmCXnYSwBEVaJ4ICnlAJZUtZzyllsDTJ6nxnNkSzzp8lUDGyKiHFS47cajI
EL7uKxlc2zpT45QJa6E/xGyE52bJ/8xsH5bH/79OmcelZXRLSlE1Fb2HASVivgzwrqtKCxLJmPTYk1J2MBUZxWRT9p+1FuIr8T/hPhaEUqUrUYe17Iqb2S
CSy1xb3rk0egknGt5HTASYpaIPwRJUgLvBLm5VyZDtFNAsZJzAlePr6rWcRfxXBK8FZsXT/7Z2+TUxc3mWGPjcxyIg/a7Ga1kwDXCQPh6vZPpPfjgEuNv0
l40zMn/Y2LcFBfAPzqc6svGTmg+ulVGlIXA5xQktFEnV4+WzZTmaoA6h5RY4p7c3RgLJiRsldVtDDumvPgDTxf1jLey+scfQingjbQ9xF/J8xcLJyjMVvs
1dOZW7eevooEO58IE0IIWGk4vkRgS4a2NYGusdGkgtQKd+Qy8eVwZ2dkDGLZH0gjofGHhryQA8DSXMRW4WqZQtZiTYcLEP3w5ggAaUncGtUyCpNcy8j2oR
gkxQwe0e/I/mlJN2kA4SW2/rj+OZ5HspOPWmUIggOrXE6y1SMAtGMFOGpSUtlAn8v0C5w95PNMpp55YgCi9IQIVtq3I5SkIxUzib9KFf4VhqoxkaqAMrpI
U9A9WYAZfZr+wEkEghKaCHZVSA8pCSxQhYmEQKvUN75eiLsTnz2MMKLCFNf8fOWjtJcXHq0FUq0b/7UyExPSS3Nw+yGLv1FtVFCOyCfKWEiZ7WS74iFiqT
puk2UYF/FCkHovD6nGn9mbmOi01ZfaIoILYRq9OzR1qSMJBnxU943HcaqdET8NWMsZMxkp9DrkWcM+UP5FFwCVAXyNBvDS9c/z7G0y1NmniBsgCEjyHD0n
lqphTITp7F+5jLMqhZoxgzhF4HqVRINpMoS6mY/4vX/IoYHBvW73gLRcwD2Daw3AV6n2UBn64J70+ZUbYiKwo/SURgoRIVPxr7xmbFMCAcUdTN1N2TWOw4
NQtIGxV+R+qmlGD0nCL/Tn5+FN8Y+zGt3FjU1sQ3/17a25RJqx9EowyaGqVBrfV1WPh8qmxRvla42KjOwPz52JG6fjVMIoRM9tvVAyjJ/+0dJSX3zUxLWP
I8S0fK1Gj2xsZ4yhSwOQ9L/9cSJ/mDCEpVU7lH9B+2e0R8Mtzc8+A2OyYCUxtyPnwIK35g79OG3uh4NUd5LlDGoB9mM7egYr0nG1BG/4yRpopwPg9es/LP
6yKHP7e3/o2ZOcK1X2tzdRD04j0GdmI2TZGzci1hOyxTwn7+0aTijd1JiyQPxxsFQvv7nzYL24fv6qltFfviNExak0fPAOPoG5tcDZraUlyoQmwrzgab+e
JxK/L5WPJRcUq0JDqxyvLKNRoevcMtcxUmTD7w7VbC8P8bedVgjWbfpIxwnOdad1HsFHsVRiCUvMToYu4F2x9DRxJ54nR78ysPOEfMuEwKG8dDp4C5r+J+
LPneJYzpPcOW/RnqEcirwEcTsDACF5ZaYUsd30hy6irzIfww9nHrumBP3EuEkzp1jRwVos67m2qWpuNN7dUde8FwtMfhjTIy9dUy2cEzuhdqz2LjOhNtb9
KOWDfjhmLreKOkpbuas6igrnBW98j29n81Pezhr7riSrfwU5s/MWxEGV17KPtDIvxUwwipXa25h3pT1DT3k46pLRlePmREsQ1VOMBO6nI0dw3k0ESgsZAK
49mdZ53JAIlC3EpnyIQ8M7OBjn0PNqXhjLIipoGovFjSEhey/0EYnwB0UoVg5RQJUxE3+f1wHVS0ZvP0yaaxGDqMfuwioHvt+keV21COWKuBs2LcuEH9fe
J6Y6WpPjJs2c6rv3ur/g0zWuaaaETIj8w3UzeE1kOegmCYFndVMtPYAGfEAKhgMMJ+bnHdKGC74tLuuejMI6owYNGqksBE4//sSgaY0dLhvM0NIq4e+1zP
S+RgBKQRjy3HD2AethNg13p9UcGeMh6U0848bZ1KhUcaRwBiqdVrloF3L1WAGAz8XaFI8jGADtSMNODeKmCMmXq+kqMHMHjq/no7lU7dMliYEXD4qHA4pF
vxDAB/uE1q5ipRzQ8LM6oOq4HsDSetSPoow6gLDGg7RGtOuFTdXUpuEnEvNXbX3cFNjpAjDviVMS1D8XUv3dYVTpdMbISQeWnTs02a65vhq4Gjqou0s8ku
d1s3Gx8PA9jZVEGbMVYhB8otO2y3hJiYMSGYaJoPJaCimABfRp+ufjNd3iZ9PsAwzRcaKJWUUxY8O4HippaQ7Cz5OQpmwcr4KnZg7FNFR46nNzt6c6xWSX
kvOxjJ2nJyg4PUnBeLl9uLp62Kb0VMsNYwC60q1RvaDtaw8ePLi2jcOGRYSlWJwRx1nsZFMOw6eRLI+uf/bn5gHNffJtU4ACLbTvh2EI/27G05sVgTXEHh
W3qoaPYOzYmmhUPnkA7rXigixReJBiZg0CIQbpJqyk2iACx6zAmBV68MzlH4L2D/0aETxYTncRLd8N2FUyiPVv4ax8ctGsy9nt4jM1oHRmRZAmoSx1+vjy
PVjX4t6jFhpB5cOgT4paPnaO8HJZpkGNglPTg8DC0+wFvycwqVZlwcNCqZgDwaW5mSmrF2Ej9kDtVMdlYAQlBB08c9vrxeVnz54V+nxlexvehmztx+sywg
ChWWPImsKxkvC7ni0XkasfeE3cpoosuyXPPIl6b17/Ep7uLpm5YVN71pnKg7o15I8HJMVfrTRw8EHDR8POzk3Wjs9MwdBjp7v2s6vSYljO0OCgm/XBUQCm
ihFlaf7IDPXgGMihtqnjuvxAwCEGBC7dOtWJXeQsWif3804b3zsOvW4oNXUIYVqSW4qMPViSPLdk0jBVlqd87nKeFK1pL+GA6lFHWGCqVqrg1kYkMZDR4M
EaCHigwcJUDyOWx4Y6+xCi/g3lXABb7bvSDK+3D2lu61Y/oswRuiC4W0Mwd4d363fX72xTCxVuyBa8tQA8lSpFlzp5j/+jEvylvS8CgFhOI85lj1ohjTy9
FLtWkIT7MkT/mulqG5hIhN+lSbvRUwAgcX96cnSVDHTChCWdHkqg6+1ZACa/DYkI8KvYAM+xY6BUyFHLfy5w0EN9aT04VeMACgPAdd+OiAzLvVDWOdH8hU
bhZxGg2JIZGPQ/0RTojHa6lNvRa2qGFEaYOW0hhyB974rbaHML9XpGIKNev8Umz4EZsfrIIdC94kQSuXIF/nOoUkIPnj98RszwZ6VryOG+gn51D0mSwQvy
19H21esPtiQE72B+ySVes5UMtscAsPWpoxMmv+QWGW4m0y9eOnywNI0+rFF+xlVnAB6UnmCXJi+mMTOVVe4GrCWl7iDWqUinzcr2gMQWkAV5AMTfPeBERO
h0qJkkEG0qUyciUfqwBuxWvT6HQkqnu6AOpMRNcH8D7pAYgg2KvI0/+g81WFrGEQ6eOYrd0RvVSXnpSSM1AHNtGHfIM9mhtI0ewVLlCEBYTf9uOhKsL83B
Ke9O/TxuBuAuaj8ZP1gVXvThMvFSC+uHihde2qYzC1dhs+mgNDRayPjTFr+7fR5/XlyGDeCqLyWFP87YzS8Df0hB4NzMu8DGeTL+a8B/Kp6rJgPA16Xx8+
fB+OEBeDwNLZvpAJDsvCsDCjknzh2nzu6lO8nMi4hSFg6JejhV1uJsJdFHNE1gsfBUtJfmlsBm8FN/8Ee7B4vUYIgQJOH7HqEyzTv6FfGpLBp1H3ouNZFw
tzYMw8EAtnLoefFWhjrys2QNGL1PKWcjxG3KJK2kLWAJaTBnoV97fQPOotchjghY7AaetG05pLxUkrWewrO74H/2XOISYnbeE/30xMhC8UVwKBFIWsa9Kg
X+cQWi9+Xgb7PF1ZMgkGc7f7hbVeDDkVsNmW36dTpLmBIAr++9ZTHHCSHYkhnDURITAdApjzLsJfzoYHQw5++yoL6cTtXrH5W+C4J1sIDP2f1JXiJgHfQ0
yrfZt3/zHJOzuuSUTaLO47w8Y/aoUHYxntmk8zYAv+8V/FChq4Rh7PtUYFuqz7Xh7z04iyP5mAZOWVSZRAlB+kASgOojPQxEUMEFSlvuJpPd4r1Y3gpQLQ
EsOfIlfK8VaiMI+PvMFfiUa9ZqRQS/CPZh4+Yfl/Ai7bluzaUOI2R5VsKE5tzQDMvHU1vAzNTW+kdAPouKixxsmcfZcvYoE4Yxy5Dvp5ZXiqw0kwkrbdUq
E3eeGaMqCgltslBaui1WMWiatM345eAtPL/muh43f0WMub6lK0aOinSbvn5i6OHgNGSTYyZVEZqqmGpkv4CrsFWCc/vevFjq9fXbgkVnYgL3wDvmTHkazr
zD2epyMT01cUWQeAVtBYVCQbt/Z6sOAC0VdUWoUH//Ho34d1SxtXztoc/TSOq3Xwj+NloscgGBURQFMl9+c+MtBR0cPVGNvRDpLuiLyuv0/sYU7ff0AHj9
JhbNwphkjdxWJjFoW3GQAAFR5A7tsqmC6qNABQ81/LBehuo3z0dHNmkA1vviVX31DAXv5Nn9lTwYLERYRgItndCOx4bS2eWKziu5s2hXmfi2VC+1/6qXBm
gszT0NBHs+t3LKaUgnrBrxBpI7eAh+KA0crheKqZd8CFdh2YpDOqdBrjULope3b99+8bCgAvK7yCggrS6HZFnppcw3TtiZObHnydEJGF5zAYERGEAeZ4Vu
/vHrY4oVIOZoJdRKsnz3Dm5ON3s0M9ULh6tuDl3bDCPJ8pHy13HFpaxkiOHQNsMaF/JQy/PrUR0ULumnObNiinqk01PGsUtj8ayv1MV7Mo7XLf2GKq35+C
Gd2Z40fvIAs/t0r95jL0v1+kqgDn2pWLrzHODXvrWEsgNnYgEbFUwUsV5IujdtSTIqauH+emDOyZYb5tA3SP+8L7XlioUXYrVQR60SnybaV2L8nV0P4A8H
97Bh4P69g7yTgGL1gD/wNwF/rczvuPnLr7++TZQgAHu//nLzDCLXqQLw+gKGUXrqEyGN7CCFRoOmVG+xFZUXsEfMJkAfpoZl40gF0Ujin8/jiRXmxHolUQ
MAhH1e614/++fmgRSmkVlQswuZkOeHFS/Sv8EwfvHYikUm+sjheRhT0O4etp+u1+tLS9/xM8hdAABJUQSzL72w44q+luVS6lCrglVTt4kjRR9RdsBzAyGi
9WXaknrA66TkTbKHfjXG31kVIH65T84kvW4R3Bs5Ddjwgvir1dwxzXz3MAODoizs3ll96Jlpm4g1Stk7VJFQ9SZfUgjh65FbI4FvV8orUcLQIaoeHuF5up
dVunCLEqAPVlMVCBWk1Ot9trbYfXL98zyLm/f1sHsI6KvITaYcKC5KWgnuqsCv2ouzNPeSY9EHx+2BEXWVSBujPhOcCQCZT0xz9EMZD8QLCcDC+kP5jgFR
32cA6FhhVRlFIkquSmruefG8BHGAlM9xqo5fIfydUQL0JriRUf/BQ7zC7vRfIilKQ3Chu7Gx2D0X46/Gx3jFj1ESiWO768b1fxMASggKVkvptlJ5rOZSLx
M9ONAILUisZ2g5frWFB5dabwMRkVpKcWW9kM6AUyQ4t9QWG9c/49NdS/F5hYhz2pjSJvB9b4KPSsE6aIFQuU2S40leFxzApTn0q8/gs2ObpUQgBKnwmTUA
n29RzrmETcmmC0rZJNdwr1EapITf1GdBDXZUJkAtL6wQfeiM8LeIc02LyzpPXnrQBitIh2JhV793XosIgGPLkrgzAVnAxX8fAIJr8BYhyIdNFekljgxmvj
uU/U6epFtLw49eHo1SOXypsp8mApG2zNni5wTgrmyMTCpLPdQMprQ2ZrfdHtwzCfgC6eXo3OqTTXKZHqYKgaiFvHImdYjHFLMhBENyKbeJmloogWdJNcAA
R/uZAITL0W2YX6gydrteqiMAYemeqsq4aP/EGeKvXXomX2GRRqgX1lcE21y4vhC12Mrz/nYA1wNJOdfGzvP7QW4jP0vewMyZ/C03JcWk5/mdJD8oGa8y/4
lHQH+to9GHhRlpNf74rRWtwxavJL2rhoD33NJTwT4n/roc89hy5wLO8p/Hb3/94+ZNdcfi70y8oO7B/YBMoMEEnav3BTuLQOStotr6ZAVdsSJfbp0/wKrP
sy0JQIPbAg6oa6V8UnBDby8tzd1mvUql0ZH4C3nFOzv8wQ58Y2TnyIkoFK7BMbpwjvEHqDi9ykRA/icYwDFqLr+wIKLnDNPpM2f09+xtrHGWMLYyg1SNxj
FKEWJRBkyHSxnht2jczrHW01Ip6lOwUUzRtupz33H2WT3QNX1zcmqGunnzlz9+ffv27WN83r799dc/fvlFH8RfEYGc8uDm4XyywcShMScG7N+Ls2HCXD+g
oeBYNEAEgjWT8ynq/BqVXQGA1YbJLUO9zIGZFYVNc1siaL+nKYAqfmhUei47O0Oyxl6m6ex0RxM1LmDrz+jnW23BIsLfOM/+D4YVQteNzrBwMnN2x3QT2W
Safjcc+MrblLKSPvJIyNtsSfQpBlhMQYAQuj3DKUVXTDGXSxgBTrlt4PjwA+9NfgKlul8oTydv2YNMAm6bmD7Ujbi03j4jIgx8epT9JhM33wgrXLRJFqAe
SUZaPUJhKtMCWj5PJ2Wc+e+xciu10mlDG68bGfrsdJ8NRrOFUo5RQTnQ7PmyHHSCRpDVhtFIBSJ+fqUszb8rAPe4ZsEmnDv1xJQvTjlERKIKmdYSYO2CE4
8BCrzJa3cSANJUo7OgLY9/7jO1cSeJHZh2c8BtNb/+5B6sr48aweDMrWI/1FkZdU6DrVRGBYc3PK3j0w7gX/B2nwteQV2ABIBexgN1nEpYxSmRr1X7ZAPC
P36G+AMDeL5QWMYnzVMsPHsIp64NNp2qmmgRwQBujjcR5KLWojOk7pwdADcl4DD9cP9+kJEB4Ji3oJRLT2OPslEmtxMiJRFRgQpzobG3hrFSxD5jDEgGkA
DITsBF/QPQim5OzQ0yEEPaAgo/tl8GcBnd757dxiSACqsNlOvH1pJV0Uch5jrWASUtOQ75POpsMQEICITfQPibb7x+Tfh7fHYNSFysPiuuv+gfrifcONXI
sQUvU7Sp6bmAlFUcPD7uj2lxDcBf//0A2OUsNndg1m4ubmyutWRuUBLUW3Gi8PFaixkhVfIs3BcoBVp/f9fIVoD/+e06+4xZ0LeMuyc2gJhpi2q1/GLUhh
QoFSxYO8Pl/MJYHNNVfKfRQmd/qb50XtyiCVkrCoENPYzAHerezjhy/75R9Z15lU2V+Fs7uxV0W+zhVkRnJ+o/JKXKGIHLd0TQfy9k/bjw7Cqmy8bcbXuM
6535498PgJtJniJe3Z5MVzx+LJvw7t872PjlJnLv7lFWERmzGSMhVnBwWrClyz311Ui0v5ub+4x1wJuMuTVlAE/iuTxm8T07mg3vLm4cHGx0zzaiXWM8ps
xZzix5j7efP30qAkRgfa6N4zFkb3LY8Oed6sBKqOdq9nujqmfAozVkZytAschePuS8dvt2LQoAbnWzVlwsbIvDwiH8I+VjV8G9Pxi3k2pngrOaYn+GAOyi
56UMYO7ts5fx6lSclDESDIfmrYsHenjK+q1v23Nz331OAN5DgmGtRgbwhB4r7bIL+/xldAksxhKeDWxLkkNUpE740zmIA0szkUxfkzxA2KhWTD0jPfnBmZ
eFDJLN5GcqwPQLW+nz9m16IiaCVbNbGMmsD5e3bt+N5V7Hcdx/0b7JWbYvnhUAD2AHEYHRiea93sSwMKKmkR+yp7df+k61jKKvQeNs5+aiz+aCLrKWq1Jn
J4wcuNxn+o7FLwKBmyjNSwDEJCZKuFR7cFNyuFOi/upTHJ+IJN1WTzbseNWK7ychIVo+v+FLdIbEaLt3tjmxXzALXavdJvRcAgi24+HjxUKpcA0rPCUl+V
pH3YTumDMaaddk498NgAtJopCfJDZfk7991BvfYGxllQcPNQARf98tPf1sdYgFhBOtLDgpGWCTPB2EbCDufzYCa+Z1o5wyjuOyJQJfJzMQZJYsDJGtCxis
IsgqjbwHLSRSQx//csYf/2aLBbX4uQ3X9ksdpBCt7/0K4fFuaRkrrPkc98V72L+qARhsdv+tANi9lCQqdk96SPMrMqicxNl2whgB/N0KzqhmNvrsqg96cg
OIok5R/D1BEIuKf8ZnYQ1bch1/XrVqzksEvm7IcgJ3K435eRotKhUbtFQYqqgYAPSoyfjsu9/TAARLyFnwYLkQs9JWBQ68erYebeF5yVUO2qSl0b1Yo3QO
X/y3AeAi9WhpA3iy5hQwdPqIZl/Ek8Xdc1xOBiwtQfg3t4Qa1p/j2Ha7i79xujWlATxh4KDb0mh1tNeXul8CAns48FH3Ss8j/kiVsUJ+J4nycVfrGRF5Hj
1OQ7tBtln9+jk+fkunTyQAMRJkq5KRhgAsBVeJ1bMSrMN1/W3OTsEJbd+6zWhbAID9b4NPmS/yRQKwe5+UTwJtAE+Wne7y2Ae9vzHyJp50A9Zex5HZ8Nxq
s7N6Wel7Bbl1aufp1jyxhuAldbvA6xDbW6uf6fNnEIjyaBU/ltDwUZO4My8VMUnZjfHdhb29vZuLi7trnKsOcqzfwqO7yN9+JmN+LwtARCDe0QTA4vL2IQ
FwXawsYb7gfs59/7R0KwgUAMVqaT1K8yT+tABcDFh0uPVCGUD3pOO2yEoofzzve26CwVk533/RJxHPz9GJe49UGQIVNmCHy0m9YHSiYx80uFMq3QnY2ucP
Bc8hxio+yoBJPTDHKluYXgkpKdraNMwGwPDg7eM02Xxt45fPJv25oTLLaRu4TSrnEP0tX5UALJ0XT2+9zOEY3Wf9EjL6VRJG3F4q3TqjVOiUAQhA+qZUeC
F7b+GY3nZZsHGi4y2kV++ydj+C3R8xggfxVBD+22fYcvBZ+uuldaOmd1JBjA2OdOwaNabB7fGiVC/cEZ+XTK68jk2uqw1SDROwp5UV7x3k3XE3Fx/pPpDg
swoPdmN2QxwGYj1iG7xPKZmwKnmtt3Dk5KgT1mVEu1uVs0WY4HfgZ+2zyStMGYCLqOVZ2jpcCUh5ij2da5/EtMPlepsrAEZzc/1cu7l4cO/evd1HnyWPuM
lwkPzWir54gwCFXE5iiEkA/zl9HxzuYJWKxitT18A+2Tk+p3oag1g5E684cUS1ZBOuVuRMBJ9XeZClfND4UmzrgmBdjduIIBzafTJ6Sl9SD3JpvX8e/Ko7
pcLSUql/NlXaKQNwF0XusJW9vr7af/5qlUp2x94svzK2fovJnp2o/93c0vmzJDad7MbdWi4WvkWLQZZM8LlbwYmiwDWA7hLcQpjM4Jq00Rf3v5CFPdo0pU
2pdZEdJc62oTj1wZlKn408BxkfVIcFzzPjNvoiuJC3nVGigoO9g6X6Uum5+HcA4Dl2p5BwY0tIWnlxrNjeD4x9V9h6vrKy0u4/qMM3Ld05o4j45DHHNl2t
W32VyAyefwd2Ojg+CFpk7Nbc3K3n7duwtpJkDpcK2+L+ky9mcXvdxcWNR+fOXUL2LvVYHRx5FZG5jD6v+PXNrA+qKGWYiTEBuJrfN3OfpoQX4ob6UmmpHo
lf//wAXDjHni8nACwiAPvHAnBDPC8Yk9qXEIDsyZcEwAP2QlF9S1urh4erd9YxHRucwAfdgAB/bo48omUFP6wUfwkxYPb5jbocEYBHBLcLgWxihcN+r/sZ
mzLvpSqB6nHhBlmNK/LF+jgAdgNx+3/Mfl7YlFXBun96AF5Ab2b9WbIwLNu9PDbeOWDfUveIau2qz9XPi4Mv6myeY/3lzDCxubmZ4ATMsnviOQAwGURPo8
kOBTvX/eIAuClVpI9h+GxKigV44cgf+WycAmwyuZ0TBnK+HrcIEgD5kxz8wTF9VTJ2tFhYh2Wf+1MCsAsODD7dH344F7Bo9duXq0VDaWiuLY49pgfguhcT
dWZMEItzC1/Q0QTDrqfpxsqIJGJ2PIoOcIxMDECJvwcCZwqd++8vCn4Lv3EMq9zoaMr4wiWpdVRzBaar+Wez5L/mmcAab/GoHp8jAuDIdz5ZE+0XjN1eX9
amYhkHrbX5mZS3JgrAhcVza4HOnaE6Ub/w7FnxzrpyuOpzt/rv4ReOwxI49N8tJ43NW69YELF7X44P2l2Di/V2cTkdXqyfiGQAMeDMkgnAQmFVvF8vra4w
dumHL+iKiVQl1g2O6jLu0sgkSvyzlVLp+WekFOSawBrnvdslJfG9tFTvi7WcRGEwh3qmrP2gLndlfZsF3xbv3j4LPtoEAUh0VsDKyvnzKy9JDJr1UeXkGf
Xt9bfbK5yJoH0CysgBC/o4GgszU+tP28+/q9dfsfuLn91L6+Kz8N+ctR/W27e3jClp9aVbJ+xtuM+iW0v1YhKY9M+v4nykwmog+Lkv5JZBXEUKgOyIsd9P
OIu+DSLqxQq24fiufL7+jj/yEqG1GnO5DGhKAMDS+dE+RVjrt6V6of5iJWBB+8VWsXTrVf8OOTjPz2DYwcQASJSzaPvBXUqfFOt3H/RXGE4OkHa9tLXaf/
68v7pVen68D/oIc/QRHMxSaW59q751rb0SqMmZB4ufxRftbiChlXRrgoA9R2dlfbWE9guFSErryCcLzp30bL+aqcP30ezZ4pbC8f/9rNBnrXM/fCH4u/1d
n/KKw4g/52Nt4AYLZm5FQcCj9iGsowRL+HzZpMe5TmgECEQ1Z7gj6/X6yujn22Uv63W6AksPt+7W4aTeWb1zZ3V1fau0fMimLjY0IQA+2QWTt3KnFAe8hL
r17UC8fxC7atjMDn54dJyrhncSvIXVu+ih1Q9X0JhKwWICwMFZW8InG1J6PohevnxPVr79oChzZeuHh4f9baxFwBVx7qSnG2+qwztXH+qUWxF2/+HV1W+x
724TG+I/syHcZO1i8XlAJT7GZ2bGqj4+Fi+W5urr63dL8nUUV84mczEucslzQuF6uI0jp1Boan00T7bA2Wqpnmhc0nGTEmHvt69us2n3uU0GgCjN/vKBMd
SqVJJpzLvbQvSTbMrcHOzX6jG+Gvg17RIdSvgTDgMh3oNdxcbs+t2rh20EwMGZWkGcIRvcPrx6F2OJUn1rdZsL8fIOKW3V169tU71ytf78hLdllwf9dhS8
bK/W9XyZ5eKddqCk4gjp9xY/KwTXsCxWqD948fz58xe3vlvqj6tJPxa3VEaJNnj5EFlrC08+04f/JReBlxhATOKv9GI0o7vI+FxdjSQtPOyTLtb24eqd1R
ffRPDjgF1a+PIBiG7VYTEZKVfUg9wBQQ/ek+ZzSYXB8NRvH20Cf+N8jvqX4RvOw1Ff1a+HMjkPMV0RHJzZHqNrHbx4WEhSLsty8EBbasmTFB5cDvU5fjLy
IJiXEkQjBf0nwp9xB0eJvASj+GD9wWq/jZ2vwWdsElwgAJZ0eum7uafjSrePxXm4UeNbt8/6qxBI3bv/+PFjHBF21q7K29wwMALXpQ4OKJy8ldFwdhe2Qx
vAO4EIvvmuLk8a3P93+3AtBtMNzCcBwCfw0teXR/CnfNF6W068okm28BKW6t8eadef4ChA+UruRiJA+Jl/LpzbBy/PTrVvI4A4th5nW4q67rDeFsF6UjfC
4nr/RJowCy12Sx9aNYF9RbCVwy114JcR3+C6q/GBn+F5cg+iiZJ0YoqluZmZufa40u0GE+e34ozunW/rKJKFAQOKicA1cn/jbCP2PEooOqGsX0Lf67scGa
w1doizuHFnvxHssC596ZLanjp4YMG5Lx2A91lwd7mYtoAxasCX/EY8KEimHQXC6IkfEapvMLiv9Gzy7XqhUEzNS0azU/rmjEzEEyxlriudO0N2Gc0DXJfr
y0aFEydkn+BW2GAvl2Krgd96jTFUjqVtj/8avHvBmTtD1HWR2762tnkOl9y/3a7jh5GSH0/HaqQs4CTx7dUH63Rul4vgwbGVPibiSg+3rm2/N2eEnVEYmI
tAFs3hFbk96oFCCHhLGfvz4pv6srENRYoOHq6I4ODLBuCB1AVPW0ADgoDAl6o1Gd0AcNaioyoRa3BdkQEsvUQxnWIhPbBcmiGII8+CKXSOsxWavFWKP0By
r4BD89BkwsCyTpAChOUtzS2VYlvaF9FVmYkpqrhZ4vvh9tnJIlzvHsgEF9VwmVgFC39XTimrrz9dGV+HAADePh8EL5+jGVx+gJqAWyWjOnoHvjc4SxLTH3
mcUBSJeVonLYqRz9JtsfXSHH7YbbEqh7+a43/w520RbHzJAOxycbgcB305+IMfb98pSAs4R1HgUbMcugDnpZJ8I98uZ2ZSx69leZWdgRj2fxP+Mq51HOEW
Cu2V2CQC/pbaJxDGxhsXAaj+KPAOtlHMOXt74d37IDgjBHbvY6hz/vDB+vrVB4dot6JviY51fuXle/ylsev6jQVbJcUrWL6mnPVS/J7gq1dfCnaWrVa/ji
LwNmrE3F6icVM38wC4ug7W+5p4kPHi1N2PpnGK7tbpAbjGVgqjts+8SMBYrMqxfksIwLml50cAEFy0uTk0BevixXJqELVpBbGDZ+obC9EorxdS0EscYvoY
36gaiwRg/wS6aIuMf6cAWCS5oGvSyGdeoJxrEJ2Jo41hbvtBSUWglGKCIPAubhvmQfu3bo11QdcouJLU8lX4nmVjfrHyE8AtPVME3htBILXHB+tL63mkui
7nqxch4rnLHiyPXoLKkEeMP/liAQhXyNXR+zuTjSnQRDHiguJJfX7EMJUDsb20hN+30k7znQvq/OvWppWpD5/b4LqZKn9j4NMcGi7o0osTAHCDUTeE+nMe
BneWC8blUkxN2FqGnZ+6o40pFxmDGssD/5fUx5cxb4b7xRfGVFTW63WZsN4S3xSTvK4RNiw/+MwIBAsIUeBq6XzugVlj0fNiqdD+djnt4xiX/fI6m153/K
kBeMCiMcgrpA+rCpTwpL46AoD3xQu4UuFKelksjD7GCMtbbNoty5y1M7uRBWDhYf2jAdimdiTpxG5fW47/3EIafrIuFbBgugWXJ/e1flja/11/z+4+06N6
x2XNFtntOlVUYC1BOz2gL7lUlq+yM1WNfJvjhXK2up4vl7+J6y9u9QupMD81CL24vD093dlTAxC8EP3ZjwFgaUkDsC3GcnYXmFhFAC6vPlguFrJ7aqK5fn
7KHVuLnK1nBvLG25O9EuondUF32SvdDwhW41ohLtgUCsUsAOFXpq4Wc4/x9eXU7aLawosr7+MKC0S3m/mXb7+0JA3g9ooM/kYBSPHVmZY1/xjJhYIP+vR2
PlF8kQnw4LYeFuLSQ2LC423Ymt42nBaAC5w9yAdgxvwBYjT+5sCnXjgagIXC1ljo6T/u1pQP5wbY9mwBxIhxCgYXu1ivL+VmufMAWFdRE8C2GF9SxdGrhn
rlV6Y7fHuD8a3lVHo3+RgrckQurmyM8vgmW63LtTxsY5hRKhYz8FNrO8/OVHIDp6CmODEAQIjn8yWh77MtPMCl0RNr/GRlapohpwUghIBbhSORp2O2utTx
XFpaRcrjWAAGYrVez38LaQAuHV3NOP2zSW2JWQd0BCV0SJFpUT/JXMdd1sbfqpaWd1EZllb2Ck7ReHTZaO4h+RB91egxtzSTH4tusu8UAO8+LGj2YXrb5R
314Izay/Vzk2XcUNQgHyPefC94WIzrTMW83YXteDG1BUwAgHdzARhf6fSTElUAMQV6bYVEJJ+Mt6gmAHOPp3L66renK2W0xl6kkiO5n4M+niQa9k8iC73B
VrAUWkpZiXEAxLxVMM1bZjMV5aY/C/zdde1dj8mD3qccjNzi0ritolVEZz074H4agmys+PGTx0E9z/wVUm7Jnandg6cGIM+3gOZ6sAcC58xtba1uR0KggM
/mEcf+aak+EsvneKAoVHF/unv4tBD7h0ccLxz4US/hFL0TWMAuC+bqdW0CxwEwXnaxvjJFQTgUdyskt38KfrHfvSTHKeQCkCzgaN4wdVnhKkrtM5e12yBF
54g0QpEX97g7LuYJ6mNvefUaSqX1qY28mEAMuFU4KgIsUey3hB2r2E/EIpSbb43NKS2sIVe5lAkkitkrFf/Qenu6kcU9aQEzFchCJluJJUBYHfjVPDiBBe
yiCDoO3SsUC4Uj8KftPBzd6c29AH9Y8l1GP0j8c0pd38oHIMaAmFEqlY6In5B/Ud/+DNM7/ogVTo8aWQEAfFg4An502JA9+euXC8D/SV+iRtYCmwTwfNbX
v72NFP/IdVHr84icGPx52J8VZx1zTig1Bcnk+FQBGEvTjBjhpGCHn2Rp6VY/Egx1948vTC7C6lfx45d0trtwBABL2EI6PUXGNezTyQegNoEydX0r3wPbZc
8Rn6UcF87Ech3vys8xPueXt6q/6+34jXnCMNd9NP6W6uvsSwVgl7faq0slbNdTyqaqHRA7dCTzbO5Wn4SxGa9FJPp6sHcUoMFDfbpUzxDaMvgjl/a5mC4A
F9nt0kiCPumKUPdLvX4L75ao5p6o2tUFt4i11zG1WMxJq47gD3Z+agBc4K27BRN/xUxsq/FX6ucXbh/BZYLhhZHBL+QGCzPs88yvun795i+/HNMVtca+zR
YwzTsIN3kJM+5fqAv6hLdcHvVvzVGfQ/oB7M2sAviEYFGk9Zbvb+wdkxeoRezVrfqYzBx55IQ/ZINO2QJGM6WMK5xkROmCAQBieyIjmfnWiSYfXmKYEng+
s6QyMdoOZkIvCb96aVtME4AG0644esvIKvxSfes5y08CHjDObt+hpFJpJDOVLKKOivBflrR56sBFmQ9v7gJ9/iW4gb5UAF4/x/gQRzeuPH+6emtdVvq21m
durT7tn18hjj1EwjjiY23z3kl6NLuMTmi/VCiWcsuJFFPW60/Rpk41tfYIvMr2TD17vZN9p4zu0txqm0w7qgq2TjgjZhFVxCKc81vXWuiZ3EccO9dLaOWn
p/neHQVgIR29Y+Xo1ja19i3kJjoi2PqX/TtbWQjGS4BfWFoNRHA2gxY+6Z4NWP9/SrkFzIK6ZOtzAftSyxA02tH1AGKBmiWg1VuwvYVmIrk0ZPXRyT0/Cq
fa66Xx6EO3j017xDqcT6TRP51ZKqmHdDGkcZ9bR8da0MQZHN619ttJuUobqPd3Hu6Y20/nSjnpC0I4GZX6rRXURJjaLfOEADhi4FUIQUevH2HaetxYRzlE
DoP6809n5kol3dWo3xb+CRgf4xi3jS8VgIuM8/5SqTRSAtR7DYtoT6/35vTdEE9+o6lWrud5OCoWxcwjFCtH6Ll0PFt892M0ThbVhJ72nfjkyzOB4QYanv
WnCL8TD/v8dBPYkscravdXb82sK/OO1r3f/mtAth0967XfNhY/ZkQT6oXTSCFY4tP1emqJ6uDif7a+Bec2OoI0NIkYcMYI2lPQgztmaxWFasB/icaOi+2u
tVgQ1QJsJYS3hAr9S+qBFwXv6fZ7PBtRwO5f/2KfNQh6ov5WvZS+O5aoXAReyHofJ9QcfLEAJD1e9MFaXEIPIcj1jJ3W2ubGx84M6O6iGBcALDr/9Nbc0l
ISU2JQ+RzVDjnaVT7tjvFHeMN7VEYi6/4e1hYENDAvAONO18v9jY9mSz9Z3OT4skhN8+X5F6vrEEHrraeje+fpNuatOKrjTs/KAwDdV3fmSukHj97crW+f
0wdgAfkvm+Pe9JMLm3KfcddpllIUvVyBR74oeE0ueUC7Xy7+0NPxajxYeUGJDH2BLJEPMofpe8yb8YUvGIC4l90LjzbX1tSkYjqu9+8fgGX4tM+98AOElr
Uhbh0K/fb7L54+fdHvtzGhA+iTm7o5fcWGLh4vTsrPOM82kqadpsJTVuntxqdGBt3u4mO9EAbIXmlv9+HZbrdXIoqcg4j+iqmqo8PdD5dIrd1/urp6i55V
CN3pE1D4IDNn945e5MLixsEuaoW78iVx+cj35NL6DrrXr3/RCERPOoJtwKHLq6t3bt26s7q6+qLfxjm7Afpa05MHnag0/ZMF4zllG80GGAnXG8rgUsS4lk
Elwu9s+PXdjbeqnquGbNMJwy89PjjtJ0C9Qzq2OALFGMqHf5es2KwtTvnktSBycM2JgPLy5NKPYQeLJ1U2Wzx4LEfGKydIukETeU3TfxY2HsuNMLeBVhPJ
K3KKOpgzX+5bWYQAg8vR1vG8KRVV8t0zlfr55dfUQPRgUpJ7C4ubtBouQ2a9Ru2/b059kd01CNBTb5iMu7R8mx8pQo6m8N5j/aJImHCju3D9z/H88pjpOe
rmceNTN+AzX/TNJO9VnV5VP4Sg8nMovy505WiISWNgcePe/ftpE8Qe39s4I1HN7sZmEL/i2BQ+vrfx6X89+T/X/3RPd/EPdc3yOIfx+PGvG1Peh5kv/b3c
xHv1LSm93rt38HH5xj/L8+TJAo2lxQecvr2zPb5PrsMrPtikZ3cX3vDek3/Dd3xyHMI+7OJ7WDwTYdaZ61+fr8/X57M9XwH49fn6fAXg1+fr8xWAX5+vz9
fnKwC/Pl+frwD8+nx9vj5fAfj1+fp8BeDX5+vz9fkKwK/P1+crAL8+X5+vz1cAfn2+Pl8B+PX5+nx9vgLw6/P1+QrAr8+/+YPtGo/g2d3Ff1+40O0u7H19
K39yAN6ETV1c7Ha7e1/38gtG3oVHu5trQbpVvAfPpXO7j7oLX9/Qnw6A3cWNg7dv38bN06jfv7a2S61wf7rjuSgNA5mFf7uLZKH7aFP2ppLKpNysFj7Yst
pzXbfH13b/hNs2zsTv7m5u6s7IR4tnYeRnznhDF3c3SVZMiHhL5SPk7q7t/jnuVLxE7t1fS4m54KGEe6Tb/feA4d7GJmKP5F1rw4tvPnz40FSPPwhJSwal
3eSq/9Rr3kNFMdUErw8mTXXha5uP/n064hceaUcmiGrnX118g1v6oQPb6vu0n1J9Cbdz8UvezgUl45AYhYySD+ebZ9NNPdXNWuOkvxgN31zZ39kpl8u2ZT
nwWJZl23YZ/rGbIanycrCDrbOV6Zmk4YOV8sQVi/WkeIu1pDjF5h839/70ANxD/SGSFLz4ZmZ/f38HN9ROHgt3F3BIMnZwijcvfJkY3Hu0ySX2uFsbhgO8
Qjp4Lpt0jeBRlCjc3PjzYhA3C3crqL25cuPGv3YIbbZD+IshqLbND1Ghlfc4b60t/skCQvSw1a3vDi9+mJVLkiv78IFOoxSWRqNw888MwJsHpHUZvZrdv3
Hjxo6+TGkvLQQf/Zw21vG9ngw1fv3iTnCXzAJ8uNqrN7Nl+cjLgx55TNUtglfnr4t/RvihLjIuoPZmH/fKMvBm4w8t46FNgy1DIWUXzODmhT8R/M5xaRNq
sJnKxutTqVeLuymF61qtS48W/pwA3NtYk7fpvsSeukHNY6vwqH5u+XLRrbe/fEH7dfmcVESs4S0C25XsUgqA9N9mWOXSf/nTOWbdTYprXY0+ZfXszKMuTE
v/ou8SBFlrbfFPc81omyBNfLwaZQlio2A1Q5fc0VZrc/Kx0cwZbCjYeIk+O0aZ5YDH5vsD/FdTfy05zbCh1RYNHfpCDvDCb5dIwhrW8fuNG/KqtOys9dOu
NG6fAxjktGl/Jgh2ZVqpNnvjd9gu415UTjbsVtPpdPRC5S/LNwEQZG4VTOHmCT2XvYXPDD8WXZyhWwavkMw+xkZB2sNmpdeCC6bF+O7enwqACD+4ZWZ+/3
2/LBfU9D13RIuZu17oO+YRtmzHa5HlX/v8B5gyErBfgL7fFfqclP2z7cQdTW5RDI96dG9+nKm9fOHC5cufy/rBztQg8NunpIu8K+PQPNHujmrDQdMxnVFY
etPDQVn8hIf0wuzPP342Kw8REQf0/b5TNvYrhT8jSsKcUxkuGN7zqnzSEPw4AC4sXL7848lf28JuIER0Ud6mGMNjwE4hb80Lw3AATxgO9Wwzxr0QQRg7PQ
BB7oFr85kneyz8hrECO49WYb+srTiljDyS6kbVeg9vEMcyDAP9zK/24N5srZ08pfTjrPzm2b+dOQYfSfjNqkiBItqBxykzj8NoPG+I2+XhzAj6mitvTauj
w8Em7JZHEDzWuu39/Je//PRZIkZ1Kvfj3UQj7vhqO+nxcDt9J4NJn1bX+ohRexMEIADvv/72j9l5PBon/bNj+NFlOh+6FELBpplBvXHNRvjrFd+x4hvJd1
t4pX5OI7jwG14a/JXMHin3eaBNQhCoWSSBYcmt2HXDXQMI9k5sxy//Yx4eBeDZ/zpLJ6271nMDEc0qp8xCLxp2DGAGa2rCWsrxY8tXQBPaPMRgJ75y4JC6
8G0tfhy2FgCAn8UEPoLtjHQ+wpLRgqcGYMnLVDEPGKzcPKu4mZxFFQiOJhjonhCAC/R+5+nxT3YsFrmE3z7dMriX0XDgpF3t+KhKH64D9y3saQi/S//GkH
Ovylq7n6soceESD0TwSl6XhD5Mi2ERYoh3ZOKLdpqDIQ4yE2TI4Td25CrLNjmiJxtgfXnWwB8+/3V2ZgE/JLv4LzyXZBNgx9DGNeOLMl00woPrUx0QMWgl
yQs4pGQEN48F4M+fAYDdNVgVwG+fLlPym3E7gwhvmTiugEAplIVpeAP0VUedyQaHC6Y6walVJ7WAf5tXRwP+OQkA9zbh3L658Y7g5xP6ZnUxFxbe9K30Qw
uH3wBGD96H19TpbtuqMi/kkzX7J9+uS2jpEH6UkpCnEk7cwKGwYDRwd6gshgfXyBtalRbvtdjm8SiY9WP8qf/Mno0jegEpLay28zuZP8uhXXAHuEiz7JBT
eKGMNZ7SpETvMYwcgrWbRwPw559/OnMA7sIFf5HgJ6N0/PCR8lrSqTTlluH+R2QRtLMagoUIe3DB7J0pAC878/HlfAIAduEU1vbf3UBnJoRF12Z3VDmXzB
oYimgUf9omhuCL1gCCskJo+y2OTs3mmSfNnuz24BKszfyOOQnaLoBWbdC0jDqRZY2UI2QlE+yCrc+qjbERZ4+PSw/+17w/r15zbAfnzwKBj3gP7sg3tE48
Y+i8IPosK72yYa02HMn90p1JbovexJAxcFuOni16+SdwQclP/ftffjwz8xcw94paJdk+uGQcXVUhE+40m8bq4LbBIifeRU4cVzgu6zWOW97EAbg3m/hGxx
+JRTB/T9+B+aPNZMMrO+WygTFXwEl2cvCnfw5HnXmOPr6wYq/SGjcmeaopecYv/o73JS4EUFW7WFblIWJiYWhk1P+SxVhNvERchKD6WgjOTOuYOccLs/Pz
GRf0ZK/7tO7nZsuNRK1MhSIJv9qHsgp4jevFHmLqJSwrF9TwTOEsCz5MjH6zp9Kh4//Sv0MM+Bdc2o8//eWMLOEuejMAP1ylvDWGH8q2Uf5y0DSwmp06k4
DBAf5eTzmheMG0WAW8stbmGQLw+t+ckwPwAMzfjX/OgNfmI/zKGTpFmbIxjuVYOblf9RWwGSyMX40HTs5UpzXn5wTB/O3/vo8HzqlA+H1xf79saVfLGnBa
BLnJaXqIdMT8GkLQsiknA0YQggd+9CVyWcJv/sfLCwuXf/yHdkVnp33RcA6h3CuZfIGDCTtG/oq5ILlHQ8GYGJohYVyCgBck+EDafPwFj/UqcGOtjfPTLi
P+vsebHf77l7+fkfnjV2Qsbzdr4INdtMvZbeNIMrTtEa+MnB8vzsg4PVZtwAldu3l2ALzsxMHJMQC8eR/8bDB/ZTTWwav4Kk3uFI8A6IwFoDzAsKO+Jesx
Vgg/Br/77JgxC5gTRKeMytGeTJyVlVdMR85FKrZv2ylaT2pBTQlBKlU7dIv0joxlJQDjqO9H/b6nax9+A/wFwUXKydNKa1cy8IsXBAAEC5j5qlw/Fo3Av2
vqL9gVxivop+Uf0b2//0UlQdEVPYtyxAWssFBGHj8q/PhDuWw5TmYd5JtZyc+TunTTQz87RiDEuaE3dnlTqQP+QyHwOACS+/nPd7CFEAoM92X4lNq0DABT
DCfzJ7BkT9NEfcb9Kmv9cVbJTwyKopnfKfUZGvDTewN4QgAO6DNbOQ/9LjQnnqN5rnAmj45lfwT4GTHfj2dhAs+1eI1FV2Cb4EMOsA6xn4VfvEUhWsDQck
bidnXheOS1KAc9ZK1RBP74lx8v7+0tXPgLPQvaFT0b/GE0UaY8rXA/qGSv2qocAJomQcZ+cB5dX1+2cLhDcIvYH2cGwB+VDzrvXDim+BfNUPbFFe7sjRs5
d2m5NgLA2MtJkKjelMxwdzAVMw8b/OuZZF/OcbcG96WMiVzKW5ftTL7FI3+sPA6AMqawQrLjKmocIALHu2VUBpxNu/1U/JliFAjhH6x0X660Bq7Lzo2dcv
6FYpczALSyBFHcsMiXeW673GCskjESl3/6+aefsQKP8JMpGPzB9D3QR1wEs2D+KKMg+Btp4x3zttQAZNyy4yg39QLKTfjlio4EfVheA7zs3bMC4EKcHDjK
Jdqk7Oc+mb+LmG+yR9ahlpm1gE7oeUOZOdSGn16Wb3XIhWuCDTwbBC6cw1MJ9yUaBTB/hhk3AEin0TOT8iPsbEpbox0nFxQPKONYQzrK0/9xxO2fn14aZm
GNuR4bgmWwHULPFV3uzENgOcQC9dA8t9kHMRxqvA7giFZarHUzlfr8CyIQnp8IdmcTAu7C0vZxPzEbBpu2s5OzyuRk2nbuBYRmXZoEicAW8zAQ3DwjAF7/
rxMAcI2JizO/g/nziFNRHqW84GdHQ8+dkaVhAOz6JjPdssHO+HZHpkYZn4fj+/YM8Ocp/KH5i678rs14ajE+nkY3AaCdtFalEGg3I7hFlIvjt1ofsWUL5H
Qc43KcZqUuc4cSf+gyimFs/nIi2zwAjoIQLyxPfbHssxZSt1iCwL//9BPC7+e//KQyn2cCwE0uamgM6EYPPlBFLN/IjwNgcsN4eMPI19PkrNo45kKdJAAv
H0/PAPy9ejcD+OPCk5uZB0AqQ/D02jwhqJ0FbLzZGmJh3NGI7UcPEThlG7hwifD3zxv0imPzZ0apElxIXoq0v2zZY6JBsOPorYb0yw46Lu6J3ZYFVXz9cV
orRfy9kokJ+IxvzHg9tVb1BemCGmXAbASP3qcfgZFQCAwZ96ppG/j3v/z8E6Dw79qqkzXcOwv8SSNfK2vrN3LJwM9kcGSPiYHJnkCc7Gk0TgCBH0PG/sdx
AAT/8+I7sH8+E4N/Uf6Q2C1pCMIejQCwPFRkCt8LMMhI+OkdrOpqBIasigj8Y8r4q7lshvAXsmAWdy6Tk1a7R92Btj1aRBndPaRnqcI9WAVA4MaJw24E4J
Rc0EvK/pXp6o8w+ZmTFDMWIgFYHgkpzCZBeDzBm3FJnnKhLQNhewuXL19Ofv73qQeBMf4s8IkH1MmZtdwJAIWuLeXwtJqeJKi78Q3jtE6NwI8BoA5J/nYM
/hp0bncIbQ2vouO6rAU0ag5Nmb+WhHrhW6n+EEKgtpOVeZe1fpkm/piL+NunLGxtR63DIK9aOu2H1UzWyQlxbcvJbp/TE1XZ52HJOPCPk71vWRicDgdol0
Wv2HnCX8cVtZ2kydhKJcOSR1vATIlwhNnrsRiBAEZE4PjE0wUKC/9+eWpG8Bzg7/d3+1hlZ3yWFjngjbx7U/oBaAHz/U9XLyu5YcAGeojAzWkA8MfLIx6R
cxQAd9H/BPyFLCqrcxtKhRc/MYL0j6dyTcn51KwtxJ3HM/1ZIdXb1DtoNHqmSzMF/NXYlX/uUKHv4o0bN7JFzHQ1kzVHe+LR6bSSKqfixsC1qeLaUPSqJ7
GBl+cV+/0f08Ffi79itd9/R/yBp72D9i9Fth4163kW0HjQQjjU3RomCIQw80gEUhAIbulf/vL//n1vOvi7dOPdDl0Lbvlf+OGHTLScIwFo5+aAWSDcmGvn
02uwm4xVXp8GgTNH3L8jRGCVhsk/EI/Q/r0rO6GIkNMrM/XYsAIgDNP76rGARdZIfUJnXkLfcowUDR7ZQN84rV6jwRmfEv66cFxq4s07mX55g83vcZxg0D
7iXQCX5kraHjgo5EPudOYKtaoageCigZE9htazcFkzYabkgf7GWxeD6EaCv1gkq9z0DcLBcRbQCHYj0/UMEhtRrRhe2t7lC+l+Y+TEUGJmKtzsS1xECn9g
5KmWCygLmHcEAK3cGNBBY+LLjk8M5X0l3cBalYr76dWImaP8n+zW09fm52cX8uvvNcAf2D/k1JcV/rBl02mGWL+0jUI8uKBuGoCOTiHK9kgn/Wuh4I5OrH
mzlVMmno7KCvKhePV7GT4AZ29U3dagXhllSyoEwdVyJR0lqVYyHo5eL4A7FST1WLV3JIni8t9mqfnrSI//tIXpV1Gg8XdxZydONMFN33JsawSAcR1wJD0a
bxIyfFWom9hAcLm95IRexgIEJmGSzO7lv/wkCxNT6E4657JA4q8mvB0qscD/e9p1SWOQ9igXgJaKOML4RPpxXARns4Ksu43JAvBybufR35xx7RBdjvV3wp
/223xZEsrhaXU8z2umvq7aV624/pBJ5nva+IPj10AETqVL/lIL8FeT+BOyNyBV5Ep7lU0EoJcOkqQyERr+cJSi7QlPIRCsApjxsV7Z33TrJWLwH9OIABc4
G9bEld9xTZHGn7wdK+CeuJruYxRWdBkiHOOBOqR10JQOqnFnwrJ72CDIEHILf1HPzz8lDufej5QZ/ennia/0ghsEMxT/uWTk1UqaLdi4ckLh0X03lIQhJs
woAH2meFn65wHxEGl9bqXCP5WVNgaAC1oYYWE0DZPnE8GGBjP/3LcaLNrXcRPnvgzqMniy7JyCteofp73LASA4hEOVyuHghFanQgv9jbNBEP2+Q3/dxRv7
GfyVXS+1CPRJRC21SeB7wsefR4oSC8sZAGLyyaNEDFmFsQ2C8O51S9K8M6USxBqrvQIXu9yhN6uPpvIx0LMu59ybaAFFLgCTGnYSy6PBlxmpnqhWkZTWlX
3wP6la4N9T/IMf//7jxPG30OPsIrak4t2njLzK6wkV6WUA6HMeeLmpbFhezzLiEfJCbfVL1U9H4My4isN8brw3O6YdYpNh5hAzfDsSf+iENHUg5Di5azKd
TC+U4lqW42WTiBKfgUrEwDVcwUTM5MNAcEAHLtu/QYnmUfyBxePZqq1IXYq201SCTY47ikBcCIfj60hXx62yVn4Y+A/dEgj/n5IoxaMWv8jOK/zVdlKdR2
TnuGXnFRs81/XGVFooIm6WDY+dvBYsJMFRrVZdGTdc/svffwSw/Yy1+Kk3IW267NW7G3aH4j+TYWcPcCesNBNNXauOPUqooH4y7pgZAERg4BCeHWT8IOlu
b2IA/NGZz6+6y1+4nJeA+ecNe54HZVXMBaM/tBzrxI/rylpfeRCN3rBkNESkVs/57GyjNXkndLc1HIpZjIo8MST8pd43uifN1PXRDEN/pAAhrblfdQOVKD
OvGScQks2L6Ws3f8dU8QHe8z9+nFIPchcMAwSA+3Q0I5OXZctgVXLscqkg+cxzi1IUg3KqqFal1iWyP73vIUxqPTIzLz//PKuWn6oLTnJD3QDiIfj7Q8Bf
pieg6YZZ/NkjZc3UL/tOtnpIXjamZBoYBn5iOXBmfMEvD4GSEHphNACswU0D9/5sTKZw/JPDD5ZY48rNcd2cXXbI1Q5lDD1gldlZb+K1iC6PBuIVFgB9UV
P4Mw2DL0u043LwVkrKLqzYvufaIzLSPpbuFa8OvJY8J/Rvqvo3RVW0S8yDqwZMA5yhoLyzY2fsACCw1czyB+0RerJ5GWH2IjSTp7IEMaBvo0woNuguGOW/
n3/+mVZ4+f9Fn3QKi13s8WAfAnp411EGf0ds49F3TbpvZyjTah04m1VMxHyKbkoeAPf+kerK/jGThhmlRq0xfuNdGTZhcGM/j0rvH4E8nX5ijizJs2HZzm
2wg110ZIYt4vNYi7g00e3aW8O0PJbFnFa0o/IvqV5NCtxTm2e2NCZ1FPxJ1cukYDQCQyxGoJPtsaqXSymQbfHOFFvkyAF9hSl5uFQ+xMyshPZiezpJkR8x
5DxhkiJMjqnDVTECr5tKulqGXij1Aypu9sRt4B532UWZUAO/rGx9xDMegnZapL+GaTVaaKtCYWB3IgC87Djz4zQRqBKRAeCFlnj6rkyGw1yo42v2lWvbR2
6fjXeIT7w1l8mqvWxjjQNeJJwMkIOHf94Ao8AKYxNtkN9lwxq7AvizesEI/jDSBhfLOXIduo4Jy3B6laxwiv6JR1kMB6mk6JWNnLu92WnSP2MHNLqBsS4X
g50U0TyO6FqDo7dsZPG+n3NOQ+bq1s5spvBHCcC9WRRn+lmqU0w4AOTn/7lPCbXZGzt23m6NM+jjADj6CxxpW5Qj7WVvmFO5oLPjVUlmAZz/lblq2Hl0QA
O+o3hbKk3f0zUhfhwA8S7BWXMeshVUc6cGoNxHWYnx5Rnn0gTyiZ5KTmlBdHUvopBwtkLLAhbaxx5Ksn9N32uFiYFMU0jJkFPaSbh5TuiCbIufYmriHPMu
iivom2EAWE6aOUyVN+ej4GeleaNJgt/DvK9FpEkvfUAVAH/8CXloCz9O/MJ51HM5BoDgcwxvjHT4G59zPADLfjPDr89Q8zAxFziqSkhOaGtxIgCM5RD0s5
BOw/wtk4EJbryz5UVj6rw4LTJmHXQv7TFr1dNYXKZHdoaSvO16yR+FnC906XxVyYZ3Gs6iCZygVCE4oPwS0iJ9cZ7412YQjh4ycuCtE+DP8UikN+iFzkjr
uA07CpelS/2NcCa/r46a8T0qwU/RAF7mfDaooan3BZs17N+4ItFHeG3KsCSHG64bn5w0cL0rKfYBdsJfIC72zwtTMfMuv/hPcEAxANwpj12OHdrjATjk9k
gpKQPiUBVbyMmGI9maVCF+4b9MABrlwIXZ2f+6nN5Q9uafM/KiSUVFDquVsYUDLlq/fGTywmOCrfQPD7cj7AiEb+kQIzv+VabcP83TdgJ3njihEwscHrXc
82x/Hz90kFbRkPx3huSlHHLWSAt8GKBmOw5jQwWRTNt4yHiHskn0nqQJHNmxyz/+bXaaSmhrbPhKzKBeKxfDcrr36Ji+jhPawaSyBuGH4FKWirPq91XD4n
8vRdGm1Aqxt9njtX/ieXTZ7E4OtUz/qMZzjJzmOg1FzbatPOU7/WfgmQyVk10lStofEwIgyiPkIzCTMl64xCLkGrBgZychsSi+h49i1y4Xrp92cjIlCCHa
WwV8SqsAwaiDUhSWHtNG4kdYb0tMIKwWvLQJ8mH2wAFlbzAtSBXATFdcqOvq1vi2P50/xCESd+4+3FpdgbvEy6St4Y9xbYz+dFtEZQwre4r4A1/7IqyRfL
OonKJ8jnADP+ox3G1TSqUmZIU3xCjQjU3ggurD/ft02nHhQmUzcpFeHqcgYbd6I50dySIGQnhpanq26mRj5CUvaTKBLcYmBsA0BGfH+QkXWuza7+iAvkG1
YcconcPXmMvVOPjIz71YcQ3w21YLhWKxVCoVC6U2GBAmeNPK4g/dtohMIJZ2K/PzEAVOygQ+ag0vRTfKHSubSJLmD3AjS8zH+WchEyvyKikU77wUzDX0bq
jAzQK56zJ5DZem+2nl21PkJtjwvNgvdzCr3ExncLO9/B8BPrpQ/JEeCpyGxVpS252zyvcV3jqnXVBZevhxKvr0C+CAnv8dM3lInrBzGSC4bNivwUglyVgD
nF7XHtO5pM9DqPpzqRQBF+ovkwOgoUIxrgXi+kKP1d6VHTi4pCqZIq/4pLK40u9vkznIc6fpg/91fZmOLDylQmEbvbemTGfYHRzYIthQMtSsAbEp8c3w+X
m/OqkoEDMw6Kl04JSUKZFkxzMa0abxMDZ8R2anm0y05TrggYUEyfWrqCIko4auAQKQLk3ONs8Sf7DUD+LVDZkfKSce40gs+zEmkNA6pLVl/zS0QRVl/+mA
xuXbC2Tm9378cQoX0CMOBnCHyH+DI0JWj9pSbROZdsra+RBKuE55BIOpri2XyT5dFlAp4vEkAXj98t9iBP5tjO0gU8/FbDmeDtB0Ze8p3C+ivf4/6FputS
UC7ZGw3Rfi6nJRWQ18/ue8gLcm7R/xKwRLXiJnjtWh3q7G/DwY/Ml0ReyyYVS7QRnQgWyAVx/P93jAvUFClCwfCUAX8aeWsnxIpltFWcjMY0z3NWLkTjEt
wz6BM1X8BgM4FCiV5Ui6Wb5Bd1zvY+JAB3tcpWKvnZHGwWYL2bXstGSt7CzumzWXt3/Xabsx+CvbNSaYb1J3UgBUu4axvF3OIcfEUGxiXEFchCox0v6YJA
BNPzTPVVhYY3BynYaolZ1knBp3LbAmeH2Ab1ki17KwGodR6UPLxepyiQBYLEhHtP5ecMtoOufNpCk2xJCX4ifwQXFixCToMF1sTb2yg69SUSbiSrIvp1CC
0R3g8DhvYJftcYoh8OGiUiFG4ApTkDPxpwnlrCljDBcJIpvpK+9vPy5M0wDOBu0bmliEUgS5/bWh4M3yCTCopSg8FGsazVSo12L4aK4p0TStZ7HnBmQAo4
SPnCWWl5s8Fla2tLiwIRSjqro+/i5jxoARReozQjVszH9TFNj7SILICSQpLsyORyBGgDekYXIMhQkcMdbkgq0T/ACAxeLyA9XDmCZ4heK8NHzxwS0VrgqB
bXaq+uYmZx4TGJHkW3IXgsBqi52bhMMCBpBKEB77cKNsRNimvKeskzDu2eVxaWu8S/Q6ltcl/pT6my/xd0WLFckz2QmCajXd4C9bLqeWhAFbf1FcKZP7K2
8CntPdYDvWUHC/fFw6NK6uQKAwHGWq0Q1GHCIcIYgJ0Uq1ehbCkliDv0EG0MsNZpVqOeM+2AnLMHuWiUcJQLIBzB3k6587HvwRyNKXaW2PosA/JgzAuCQx
m+fRXJpBDszQMoXmURGSB4I9WC7qgAh8slXBR7ePs7tx0CQBCL/zG6HFjnrMS0/IwmI8LtZlAECsfE4iYucX2UUygLVUxUi5IRbOGhEsam9vrwQCJyDkns
PyQKzE94jyQCl/ZKtOa91DLQ++o4wCHsldo8gz1Tr8Am/NRjUU4SVCDl1wqCdvmgnSQXZIye14Gxhnd70r1miiogz2wycTKC9N4VU9PoktO8bMgwG8grdH
1HJyAAirHUhYcQ/9KW3QYjZ2kqlBmVMuZ7Fyb3SiHq4PL1h4mZTzIBP4kQs8mSiTDAUv57Gant5AT9FKJ4jKvhswwx5IZG2ne8mkKegXSkUDgcXC6so3q4
GQxHq4QTPMUAjpwSHsgEvXAAB+fNIplxkyjCK0fGAAcyu26Ky018G7XC7UDyPBhna+Zo+4Q3cJ+tK4WAVA6r2GP4L7hv8SyuoRGIUqzjKL8xCX5YCyadUB
H7Vqb9gsdiExDKZtrG/KRm8nlT4j4QyWyZuNL70wLJM62fhYIpODtQ0C+hMrwv2+OpEtO8bMe7wmDeAwJ14NhzTaFz8ajj4eWCNKOImZ5KRF36GZjzgxd9
g04EzrC5BW0SSZaaw5ViqV6sc1x594PuBsHj14l0U3dmwf78qySSVMJyQ0AOtBq5M5uD32UBtAAmCxcIiOXkCU5Zy6MLhOyDzoWE0MAitVfnqdXjSA4g0y
I5mbS9mFbQju6CB1udRn6dqRTiR2WFAqJpdJWwFQmkCt+5YQ0jiddeyUM5O5l+enSsVeY29q0Q51QaBRspo9+Rld7Xc5jkagH+KIzmO5P3g7CT4zc16wtM
uqmiJRZTKxEIxM4KXp4m/vkgcOTceGCBCDhzALwFrk4si/qo8qmCwW+UyXKCSXXChelu2EPXgbNLI6dfMEqIlABF9iaGGtE0zg2hQAeH3hct7ZFRfflW2X
o2aiDNp10xRcDnczAES3LEyb8A9s28Af/vMALyfE4LjoGZO+HRRAqAIAv3c/uvCZZxVqwT5FgL6dFzFEIrr7LF5EYflBoBFoyqSBMf+mUNIALBVWJLMupR
1qNiDLwL3KqjTPOeOCTikI7Lb4LHuzAx4mkYidmGYUC9eFcpAFZn/dGmYAHfu4Lgj4Tbfm5paemslq0i3itHwkEDWFshAyDdOabhpm0XWjfbhkfMTWgFIo
ZvLEpnE73L8iP2ckwhHLrb7gkgJc4uCEV8zgxJFubEUS0Vzqw6amiI9b4MzpnLdgZqbcxNYVjmOA7Njjho97vlDMGMC79fcG8Uce2nWV/NS+24r23MIxAE
TnrSN7kuYrk3BoNlvDAAtjFud2NmKQcVpwN/al6WOuB+AHj5AnPXE18aaLBgBZaGax6bswI+HK/kAXnZakEnHBmWIvxC4bDgKMAPFvV1tAaT5yQ205R7SG
pRGxcmtm5v8BV63lH+mGggUR0czc3Fy9tCpSSTY0oDGBSHIIkTj58VmKj9/QWvBqh+Sfm5hjkEbKyaSr41Qa3kWjRXZVYU9VAKP4TJJLI++XgcIqDlCg2u
rH+qCnAeBeT5x/NwOXaBM1ExmpD+qOcIbQSiHwwXuxcl40UweXB0n2k/65yrTj5o4BIMCdSDFgr+Yb1cqpfVDwQIdYtIWzF+Yk0cFIs9UU/jChq/QxLEPi
HNZST6x5sQA+mXZCXaOHLK4yceSjgZcj4/ZdI9ye/ce0egHX2GxU+1cH++D9ZACsNIIqX0G4EaJfWpqBB3/ij1X8RulGJm4D/kol2Lu+mWSjrJPQhhUJFB
1J1/q+MmUftMtrwRUbKThYDAMvUeWZEvw1ZZlLJ2pzZNBsOymUJt8WKLfMlkE9UxpU0gR61FQgPtoHHSNJ8bfLJxoET6TCwCWhQUKNHLCNpZEVZQ40wLYY
nkjhmQB02PZyykoufxNHTtwZp33AHUmwaCAAXSOD8WkOS8tzI2xOddHd8gZ2mo9UxljWxF+p8PB8FOAWpr2WDlvRtwj9K15JSr3XNmbtwX3aoVo8Oi3mvT
a1o4keKEZH8A7Nq33AcWOUNJaPCYc+FmTnZt7NyGt1TPoTjae4iNavoIx+aMWz2/A7tYI7/oX0HRHzvp+2D7rrUp7XCenTaAM/NFIKgWhm6pTlnKvX06uJ
b8+BiFLtaayWBBdcOuscbxg4k91TAhCTnv/4r+OUOrAPaR8TejR8UjpcirTFxWoGgCu0JalKBCz9znI6UFxJndp86rb0dHxRAQB+f2ofdLd1kTxQB3N+Qz
2eSV98aACpThIbt0LppWSnZlgFvthW3rSsA24bAAxHWYQym9SxKyJN0JpqdpB5bximYBpKdiCWofOYavTCMXCc+HTIX5pDBAZ5ydBYmPhbMH/ahdmiZg8t
zKtGjGvSF2YTqRY/5Tzo3qVa8KbckbVpO45y5TgHSpkNSRnL2AwltZCRzowNYzx4xnKVKKqygKGRdqywhvzLPtYHHQdAaomfPdoQboIHWgZANEnlBkmT8N
YruLUfWPBQHVu1Oev6MJoyRl46UVMsPAySUzuuJbtCmRw8wM48OTSniyjWwAO9Qh6oT7IT5K/EfgeYdsSVmSbqC/khm5mOcHFoVF2SOqB0p3O6qolCiC0R
lBk8i9G/mAO9hACsKvmyhPjp6wmGcAmxl5rPgwjksUxo+oTKHMTqEpo/TT7ox1ETnAp6jXq5mBDpYOTbq1S9qdLRutzjZRWqKG9RZmNdFQCkxO3Uh8sJPk
Lji9opaiYJtbLvJppbMg1jUXa5+pE+6FgASmEulOYaB0LKgSIQbLWJLqZlMeouD9BvM9gteGzj5EqyzF6QydNcTfAnwjFyAb5sTUKjjwDsfSz7NeuWebUI
c6DoQ/jqQ8Y1LbvTYlsIQKrtSQMYyORKClVUoLxjlj2R+BM/PI+KSIgnebQqLOLt9PHX5Ww2eCM90DQH22AR2h84W0/ckrm5WzQEKuWOOHCJhi1a2fOSGe
g/DLimTTphx0w8UkCF5UdewcJna5oeaK22Q/eIH8cS9GHDmPzvZwQXLZ7TMuGiATXjBkvz93KbJh1pcB3Wq3yck30EAJNOiL/9mJcWX2TIw/bJEstZfgBB
2gGwG6uFuLJOZlD7lqhkq+12p3U+lagpLl8zzIY3RpbKwbESeMcGmAZFe386t2zAX+3ThYlDglTihIdxpLaSJIlkCjT+iM1U7O6phK5+7hoAHHGnZeuEJw
0hWMDq6aspJ6AUglEKkIbmZ3nxJjfQM+q3cO/U2zJFM7Aase8SuoqgBbt0aC4a/O4wUQZ1DNsh04QdJ8LVTpMPurdWi16VsQjIjY4b8rG1gLc70hMQCj/b
quMwN+ft6OY/a3QSsgwZwYf6yFr8iQBIhjCvCv9uH9xIp2zIBUvfxkW7UczzLUVkxS0dTfZNkt+gf/opv21MAyGXAwiwKRcA6J1qN/eQhhZ7oPD5ewqCKn
/gpk9Y6o5I3xDoTqcWY3jTo2oy8t7VndRVrzV1eohshIj2lQ0Yjep0QCQeFOLmlBLyIlQqV075pVyfsTIINUwPRoyISqrvoeoROL8CbpvqRMVERnKgfJaI
Gp45fstWPjZelAM7oy0h438764Fazij7WqWPc6RIfHlgqTEefNBzk3BBxyszqZDi1buyzaN0l5TM7AalNAC3ROKOxaQfn+mwSZcBjcxFgtQsAF1pe7AOUS
FN8I3TeKDuMMD2VDeQc/2cAUIwUHWGDhdbBTOVhHFOvBIzdIc3X1cJ0LgQmBzTYU4QZdWID4qVQAyLpk9R5uyiS94Zelc5+WVFJ1gp6nWUSnBx6mqmUGZc
gjTZpsPlJEVcKL3H1qNc1R8wPJ2OlIapTjEIfMQpzLXCVLIhTUEymPbqeuDciPc00qwcWVRHqhzktWRJu4AL/P5jOMontYCj9MQF4oE6zCuPNOv7bMUMAQ
tIcBnNyduZsCmTu+djFKuIRGLZVIeQADxFR8SjlhfVJA1NU6+tEPlZVSW1876UbtZIKGamECZ8niqryzVrAJrWvJa3aeD4lCmwp7Do8bTx1221ZoNXGAIG
bu57TUy+pvOUcBHCMPgqpvLdVry0FcNfJbpvrvArVY+QnUKrnSIhe9d1LyIA3cDJkTTFNJCXHoikkrROZvqcG+SXXqIx2pS2rK2Szsj3H9N0Nb4MkX0uj2
xoMIPTWEa7VuwBpg7HBXc6eYS3RTpsouo1yzUwWe/AwqWGBED3NHXdzdaQX7zRkZFsIiRM/hb9Ve20ASyYHzGV3PQkAHWoiO6Y4U7nbZpPOUOnxT3ig/4w
9RCwN8viEHBMb0OH6e4UWkfprzEAB6Z2e9lNfNC6QTYsrJo82dQweaIQYjLGoyzMlIqdC5dq0Rt8q8YlY5sVF+V+2+lnECdmYiPvjqm9kH7tWIoWCiFVPo
rtczwAZ2f/8bcfL4ymQh+hFkUsOZj6NMORyMlIytPgHXLDK8wEYPFYAMYp7aEEYMWRAPz03dxb42FwZQeVE/04aS6HgloyI3EYNzjE9UzjExrDuwwAFlS6
NAFgrjCqTAegXFj1THoEmHeRqoDhEeSWgVgpGJ0pV0VMjBhYGZlw/QsPlg0AbulC78jkbkx0kBCN53nTK8V3W7XoCmr7GF6/kbV0iKBtW1kANlNsA6oCji
l+OgnZINv6yGq20+lQR4R3conesQCc/cc//vZfP16+vLAwdkNf3VAZ7eyn8bAxJ5/hwmjMmEzrepTiH28BrdG4yVJtlvDDeeYBAEnu9ZN3c4HLENDRSedU
NwrSYB7I5qLkI5qh3SC15ruJsUw1JLHckXNEXqOQFnsCq9MPAjdZePH9v0imtTmW3umJFwWjNTO5N9OW7YNRLnqxbLwduHWcfABisU0DcHrXTZe7OgQcIe
va8tLLalxLcoyXTcuEY/LEPCfNFJNhlNJW5SPodvkAPAJ3Zln3huoOGgXg1cK44E5LAVl5ANweA8DUJLMmq8lEcfXUAOy23FqEEpksSotdqR/1ROYTpgCY
OpSe2Mq43UncqxIY2VpvDb6MrD2XALg2XfztcTaoXdqhUQnWuBkrEAKmooLkQjTLntRjoD1QRQBKhDiatuFLmAbCRboyXDeAwNa0iAeLPff8jtWxa6Zjll
JZCi1nFIA0EijVyjFuREnZy4r1xocGLnGwgLoU3zoVAE+WVJvZl1XxLErs2khwNwJAi0ThjgBgTAY1C59y+F7gqkoNAdA7Bbv+AvMi2DBLLyM1ekMRrAtp
ung7lag1aXUP0u0fhdJ7kTTljsyMJ93XASlXIgB7024UX+CsCWt15GUzhuTQ4UEptYLR7TC0kjNZGPV6/DEARF+JyGgeNmCdm84qH/Vc7ITocJ6draPpc/
6IlD6RItyUliJWWtxOOUeMtzzIhkbxmRkyv9PpNJhb8T6iFD/z6caD75clETQlty8nV26NB2AtDoJHkjDL36YA6OQNxMArPEKVJAVAvE4/2Xt7xIb8FYSA
8TLSCKRyiom/dKmSJWQJBOBqtv/K+K3NTFGJFMNDIiU2RO97CgKnSwft8qAZvEGtdjXV185tNVkxF2CQCdIAdI19epla9bYYGGR2c8Vu4NiyDjFFAJ5zo4
soT8tcOw+AZY/l3TseS/1+2c2DU8ZzSNoW93OkxWQmJ7Q6HUyDfoxbdgoAgu9m6XKJ4rnGueyjAag+9wCNRlEXz7JMGDeWObTL1Jfc9AfhMKTZLARA3iMA
nqYOsdkaBBfLRtUnyY/hYposKmbb+q+ZAPQTKQMfo6f0b71rUmFktw+pneJqcHyiT5NLfHYmALzA+Cz7QAAcjtV38bEPwqyrGxV3E4BmIRALNXHpvvAi4S
tnAcgSAPam1ZEEAJy1HcX1ydFC86JRv5I6h6MUNU9xDaQgYaZYE4W58JO5iY4zrwH4y5QBuMiifVTBaCaMvzhPPQrAQ5GtiSGfNSasqUK8ETalANj0XM5J
IlQgQQEbkhz6z6kByIck35OUplMDGKmemQGgyfFkYWIumywdDCGNJPGom2p4LmxuczD0UOeHI3kC/hq4Mr8/gzToI+bOsllyecOxAEyZcZTRMq29kZ7iJj
LrJgAPYw5zttxGiWZU6oTzOS2He2/Nja4AzAciHB0ggACsjQjVOzUqtPC07Kcm+/DhSKOEF45Elpbub3GwDoEAPHlcNPPpG1rboYA+m/IiGkE2BrwmzJqY
cqc7rB/nGCUEt5iZ4Yh9UMPjQYmDCADY0QCsnoaOvQYA3Kep13mKjyOEgoxZ0w1hKm+2klHgQBEcs6SCAGy6SXGiKaOxeQnAaTdEnGO1iwTALMcjDcCr8X
aki0cGn5WGomcBWBwB4MjIQYoOcZCed6rS0TEAdKXkjW+PTMGlZMuwnKKgOyE3dEOSUmczyZ/VfCc+GNSyHI4GRkoUiMfKTN6J1RdPAcA2ADDg+QB8kAHg
g4wLKr+n1U5IFARAox1JqmNr8pkJQFsBMODzpwTg3mN3+H4f/fqU+pBRHlrJ1OENUCkxozhgTCVsVDn+QZp/h+bH8F/p7dnzLQRgZWphUVw1Gl4MyrYqeY
7psZWp3GJO9Za450lGcxSARdkzYgAwnT2ThWpJhTl9G/XYVK97fsehSktOmIsADMtxOo/gp/bH5VbKXDtB6MYZNO4NHKtc1gNYIYoop7QqZIREJOWOAmCl
NXUAHjBMNzF3jCeT4ZitG1nQZJlulDqvxVSZu2kbMb+eHkgiIwhAnFEWA/BT/Zkuq2EVIo+MqwFYzBBhUh9Rt4epDuotk40txSuuUY9kogKv8/dSdopjYI
U+y/dnAcDBkCMAXdWoaufOiTOLmcv9PABmLaAi66kdPFRJGCs95cSSHeoOMu9kP8RUAHiTu8Odzhi2KwFwkBAnmx7XaWp4NVm92mHiZ6Mes+uFflNzU5oD
z9IQbDYH4RBV06nI30GdrQrVId5OGYC/Mkw3sdrITUPtgIcZACamTXixBSwjeyQusBXkQBOTtB2zJjmP3JrnhWGIt7cCIAMAegRA9ukAdJEJKgfTj6aWHf
YyC8BMrdIA4GA0DVooLK8GhqWk8S34bZHrwa2KPWQUy35PAJyuWt8mnLJoR5arFAAdJ6VBRYmSh0cB0M4DYKSEUDUD1pA4UpYCTqzvODRYJwHgVFJOXQ3A
wLLzJsjYXlOloFGbN6b51K54WQBGNS27ZD6cHk0niaVhJMHkiksApKb4kw9pmfn0DcWcNsudvtY0q7OSl/VeJI22SfklXbAvmq5qzbykHbWd0thzKXLHuI
9ViNMBMGrv2FLY1M6BYCsqZaSlUrxyySzXvbvsvCEeE3dPPPx2e1uxFUiRdzjw9QxFqZqA7MFqtdKbPgBrMQAHPHn85IACAO8aQW8agE4S76QAuGJO1oHr
qZkAcFBzXXVkQ6kTP30AIt3cjoKxWm4EG6W0GwcSV8zsKCG05mJvchaBiSMmhUvkyDkVG1lnC8A1sICWIwkDxkBHZTlWCqmGXJNkNjC6B82st4qwhEEZHV
PxlACEaKKhAfiJ/swiq/FXBMDB6NijWOksoarSv0zZDBOAcO2WCqYOh36e3RXJvO1k6oDjSIF6CcDvp12J3yQiDN7tAU7NzNB5lJidazQ1ZgAYOEZ9lOcW
4mmfWScJ/LiZeqMsvQJgdWoA7CEAk/Yis4DsDwbgQnmeyzNmzbLKnltOIbA85CS7IUaMoAwLlXCQHSbI9FAH0TlLAM6WrSYLy2k1b0WLUxJ9cYOOUYcwiI
hO62U2yx/vedMeo5cKAXIka6W9RrUiXdBPBqDHsQzoxy80kzdzE65O0uhwfqQQqJV5HxRGQ8YipoDD/Gl7GoDVM6DCaAtIAEyllY0Zm16qfpTStUlJFJkA
bJtLLb1nRuYl/m0oK0OyMFO3gAjAjqUZynqknKVm/SVarQaYmgDAmpcGIPiWVLQN2agRhC/FclNYrmiBiXddz9EAFGcNwI7v473iRjwui2EdopTSElvPNu
RaUmZqK1NoU/ZFuPY4AOKEJKVp20BFsVO4oItsSM0rYQLANAQ9g+sf9xmZ1TETgE3WHgWgLAeOSfyTEmIMQHY2AIT4qOwmR1HLuykAXjXrgIc5HVV2PDZO
3fyp0v3dWARVat7Gf41XbhIASYSqOq0kzCLvXQQAkvC/5TSRugE2z9fKyXnGDKXALZWcMVn/fEBRY9MdhSDNB1K+TFOmZuh7qqypXFDvLAFoxKFukm1/Ea
sSqoj+pXa4rxgARDn3NACx+BvISHGETBHrj7mW05k+AEnKOSV1JldkFiJ8Mx3tirtSnD6N2eL7MTk52yWlorMB4K4JQIwBI9fFxJbX0TEErfeOCadV01Mt
jwGgWbqHANkzBl6Hrvo7vKEURnMSAF6fFgDLEoBNHmRSZalychz/SXaSGkFuiL14UigV5f54Ogik8c1OatS85UiNhiaVebxK9UySMATAYdlQCOlpAOr8vR
HQ69t0eMWsz7IU+ZeeQ9Tv5aprK4c1rKJ52Mrqa3BBT5OEuUAAlHVbO0PeUJzcdgZMavZ0LgDjUU9pD/SucHNGTshgFsf9ts4YgIwa3pJBsQnL1krx6czi
kdRgj7/HMw7kejpqzGNKUu7MpzKEL3rSBZ0eAB0CYChSnaW2neaQq18ZyGkEzZplp4dTW81IZzXK9qCmMBj89f/6P98kfO6MpJwcW+KeGQAvSgA2k/VUdY
rBirSWSrw5uj/VTzEURijMqCd2NRY2sHNIw7aUPLYbzJMA5J9ciL/ALsYAVIlZmWiNC16t92lxmyxfxwSg5QRBvTASA8oQMINAFSoj3W6ecQKgOCMAYgu1
zgKlJ5HixdlOOZSJrQ+axvwuO0n+iSBl8ldUDiZ3fKIEIIrCTEuB4wLEgGXJFpbDEkwWnZ3oZJMjqaie+B4GQ3Nb5FMb2Mk4XQgU/vqf8Pzvf/zH//41Z4
0SgIECYPWMALhjYRnCobVEWKk0ZmsrH9TwLa+h3RCBk8pHOPx9+njDv5+VAn7UTEilTBUy8D+r1dNU0C60NAD1y3aafjis+fFhc1MdU1o7qp3OKMWAHWYJ
2bKpbmTSk6J8OwRAXwKQi+kmYR6xgacA2NRMkJhFn2xHlFRSSsVSlFT7YoHBZOAvneNvCoY0qBkCZsXAQxzhpVSZpg7AIP6I4Gx7pqQEyvDD89e//pXH/D
Jr4Bsiiuo3Nz1Dg8Muh8HV//hffP7jP//q5uTrKKIAADo9BcC3UwfgGwRgrWz5yBGwNCFHiZ2z91lnDDw3ISnWpjkYGB3VWn56xRimkKuKJqfLSgCeprfl
Qku7oAM4VJ4bcRXLXkm8ykODm6UBuKUDcymQmGwaN1X6kkM5ykrUEltw/zY0AC9NGYAhFeLhlvDNmyCHCpPcNd/EznbNqNM4RoFBjiBQ1w7On0uRtMxxNH
BvagB+z6ckRAwAHCIAUXgi9MLQ933VgxJ7ja3/cxVN2X/+xzctPQYXLkFHEf9TfK5mSrCKffMf/x+JwG/SZL5ELI47GH8y6ZZNG4C7BMAgmWmZatqzsqoU
+HwTBWyg2DxJJlBsPUsD8BuRqxubSPlzGtGJnDvvdP2AEoAyPFFZapYirig2aDYMLLwQZnhvSqpkYkYKi8J8fUWljtQQEoBT1kW7gKPJynSnDEY3TH9hQE
J1cbS7GgNwYJabjEKiJsDKppaXzB771GiCl5wOMT0AurUy1TNji2CZ5w2s1F//Qz7/CxbQMYcCW2hJUiPKHKPV1bG9v/7n/0oA/u9f3WyzoWRioPKiE/DK
xxzKUwDw4g3LkvneeH3mJNuXxfShldLl6HP5fjISGZuwH5rSkoW+cPNqcvGJ6VAVgkiv32OC7RQd8YstL7ooAXglZCM1L5nvu5vyQQuaMidix8xYNUqCP0
uWglX4esAz2VzjtIckWetKAE5XnX6R1S4GKFkrNa20YcqS0JHOE0/CSEgHPN0UDR9d1ff6y4Zz/kDrjRgtXXH1XjouVco4taakgLOgAOiRdpmpoiD/D3fe
fypH8upfacydkx617fpGjJCmsTXZ//kPhcD/w4yZn1bSvl2L2ebV6bcj7TLUcnB5ngqdJGQfPksnD7HKPsBJPCxwk3np5SYLtpb1mV2ut0WctMrVRLNREs
YhPx8ZXKeSpOgyj/pTwBe84ussMwbn5gigw8wAJ7mgPlGZ3LKhw04ZRcOglx7e3dp6uC18dRWnLyndIWdVzgaAXeZSO5IjNa2S7ulMv0485VA6LXELS1a7
QpnAh+Ytu8I6I9lEQ4LKIfF/KcI4nd4rbEcqU8/jwMrhgjpgAP9XWcD//GtGnNGXWZvQyhEiIgTy/0sDEMBr54qFEQBdCcBpN+RusNoOlj6ckUKd2oAe21
ouGgBEzboeBH0yBRUac6o5e1EvPFteXi6UVgPhOtl+6uTP7GjRcJy/iAUlqcH4yycfylrtPAGwVu7QEBJJejdSy50sWUf7llv97b4SJZb4C10XoAbnDOdZ
l66+OP8eVaUDZNKHHTuvQVvOR5I2ocqmLIu2wKMm+2CTXIOVkm0xaUxlX1xbjn2WpPvRT8iGxmyyZDREUcrYh+aEWdsQuaKRHh1URQu8KXYf7226ROrM7/
rH1MQ3ACIFwDDjR7pyVnd+7gEWHwPwf9EHzSS0aSbwQLf8n4UkxSKL/n/s/Yl3E0m2Lo56AMPhMFStPn2617vdZ/z97l1vkRlSRqRy0JCSnJLlSQNWecCY
KuMBbA4YCmioLqD6X39774jISSkDtmyq7qs8dbooMLYiI77Y07e//UDKARtmTtEcLFX4/riQVJ4vvYZ9VL3GIpGZKrdt4W3fOjjYm/UE90f0DBQV29rgHg
fT6QjiHrgiBuBZaU1Lz+zaHBZuvcAwm323bUoJgsS0oLLDjlYLORCE6O4Vtd5I/FGCmxOHyRsOWx7cMSG3bRt9ZOQp5XnUNNTR6lwWAPm01zepjSsez5Gy
yDLCVvzzSN9bSEm0pg0XSeIrcTgu6S8rawn+anbul5Ekd2HAq4gwFzidBSUpykqjMwdGrvgXbcX+xXOzgZwTJ0zzIEjgVQDsZDTXpAsbBblf0PB4dk0Y5k
ldoXKi2Joeu8aC41UVNZVKhVJPfi262qGfmtRl9hW1wvatLIdWowHzxwEc66qkYst54/icp6j7LKgF5TZmzXL8Jj2hs1fIe1ChUM8ItKRd99CiITEBNpIM
aVItJ2eiB5iitmaiXbwy7xprerMqRRjx4Y3UEEqZ972VakIebO9TJZtoJLyfmODsdQ9wY0sag71EZKTbAfUgEIMmgKN9kMrYF1Xz/IfN38mGGWOU/GCajS
QArZF6pWWNH8cNC9Z/99/SWRi9t9iPK0cef4nmxpkB+NDDiMIVOj/ddNV46lh2sc+8YdQZt/UHxVIyXd+3slVa+E6+71opVnfkfbs1ONGMvdwqbgU04AzV
fSTj50tor3m1FL4R4JmsCStH5EOnzw+y/Q1acILLTcYAXY5kxi8HQ/ExbnkYqe+mpOklOxmLmfYlALAf1MooHZtiqyTr67EUI4YDx1vwHJZKszTOswP3iy
dUpzlu2TRrwRciAkvoDhRbrG8auQNRVIrDbbelCOoFzoZYtimrRt59ruhUBMB/t00jL8tgjO1i4soC/tv//I+qBKaMIErCEAfgyw7lOXRBBTUEUn6sTPNS
bcswkrECFkO3h3R2t7aF9DqVIl+ecH9mGFSEPwdONxzvwep/FV4com+n5uqBLew4X9B7nJdJ4hveNPyIDRm056bPmywoFUuJYiCcthcvXhReHKm56jTjma
uRZs2qK/n36WJLngcqRVJ8hjkYvDIveEr1DvMdMPft1OzXnM/nsu3C4WC753mye8BD8qOSKQoT6Smc3v1KTTguHg9eh3mC97GlpSJZm2TAnYtrPl7u2LWy
FqDJK/z8S1RNH6UnGeZ4COLV+gdtAP9FbJjxO0sIthOtAiVhPj/Ne3YAbgokHVAiwWraLGgFgrtO4LjJ1K3NRNDavtET8GdmbByNU590Ahics+5xfVvOkV
jdZrNoes025zzkYD2c8wRPT9mG9w5+RoOC9lz8YUuEonhG4c7h0WCv2+0Jx414PVbf74+7TxJzsNLjXCzyyFUSlD+8WAA+ZU7fwzxWU84+NXPxZxnXHfFa
5qM2ZPuczTsY6Dcd22mmlU3h3fdu3BoMbvTY6GBAI5WQ0fZBVSF2LirXa9tBWU+dzhEe9sCKYRHwn/8f3rbGMHTHDIY1F0NC778hAPuZO1XWV+Fbwn06ie
Esn3WjgveJzRfudR+QsA1OyCupdeJH5Vocmku2gdcU63UEYONRqNmiYPswsR8EslnCKx0Iuw3uLe5lyLDb+uy+G7Kxr5rIx7TjwThp+MFvBdhcRQ+Ab+vW
7GtVrgCfbDRpls5GjdGgVrQvZcmrlyFNf/cas5tI1zdNj2cscjLf5docnGjKR5WTnrSZrk3LsN9SnQLcdseq3WvVWiem3V3cgM5rtu1Nm/G4uRG65r+rKs
QN28wDoGGY5tgiWPUPkQWsZsN68nrbaC5kYjC8f+EAXGacell9l4RBXmDN2eu+eh+XGPRQUmtcUe/TKMTYA2u92JuGagmFIdsqvGcNuHw9Xq1UaU7dOS7M
0LFnFXt3JPiL687sfb1A8Dve6yH0wDj03ebHj82ma33q849ZpuLBoCVXOZidCwbgEudNr2+2LVUSz3/7Pq+5Easw5UnnSXYgS9lyXcsaf41GjQjoAVVEp4
pJUL5wUWYeLuS+GtSQ93H896oO+AdHAzCmI2DzkdHs+36/mRcVlbUD+2///O/sY9aJMDzbQCJaaHdwQOdn+zNnB+ACY9NlOEBOlR0E3Rc0u/KgUKj3RGjl
kR8TnulnA5Bka2XD0hH1mxe2vGFhWzjYbM2xDg//PgeFa2nOhrgoPTFoBIDo0PRKxUJp2IIA1N7AXJFWokv4WTGryRgX+iVjwrIc4OOyDuIPQujlCwYgpk
GDmtlGIX533Nu3XDlwPLl+vaRk0mFkaIB12g0U8SR1CHhR7vbCGrglG2W5xlHvA/vL/oV8UARgO1MwQTKa7v3jkbedkkq7oSNIMaK8jXRGKrNw1ql8wQjg
swPwIWdXy2bZ5mxv9f0RAPCY7Rew3BCIPKUmI827Mw2z/EkEmjh4VpGdjkhGmwB4S9guvSTs/e+cq4CGaVApK+6XzURO2UzPkPMBgUMwfoH/0RwNFdLDY5
IYTN87Vko5h9rhcZqV6gZ8eNEA3GT+hifTSk7Wf8r1/seSkUaWPjaG1w2BrkCaVpsTDya8qAnVgD+2QYUlQJqTE+qYFZkG/ef/+YOTlS/FuazJ7vdaM7v0
su/pHA6ZwExEj+59Be5TFsJ1un7xALy7htpscJF79ZI3BAAeKGb8AePjB9DJ42ltUFn3U0YQiShsqHutCYBD77AwFJ0K3HQSgDhQ+tHZXZbQ57Jya8dtgK
n8nWpGYa8FwN48/ZrXNfxU/jPCnwNBWAzfJlUBTa5DwAsfUY3i9E1ynUzOP8//SO2b7peUOXfrVCc7dg5UtOiIfqRHUb0oa79kYya6z6jdmI8MeKWV/0GX
0h0zNZQa/l3JKk+MDIFwIwDeJHXNRJcFzQ3E8Zyk0PAFRINzAHAHDm25/JHNFY4BgNgisEUALM3lTjdMbKVSseDup/Bn+iwoSeXzAaltrx6AR7oFQT/q/B
AAG4v2ORC48MyhfghFC4vJ7ekIpmx5wnZPj/Rwg7CjyXbclLMZLRrZo45VNpPtcUTdvUByZDrg5U3elwFZs5xc7afTYToR4/pOVSoN8qC24Vpjs9oZE8k9
MzL3F1aGnwPvr7FoESPMHBUAJ0fn//nnf/u3qJKXMuIj7fJCOFm5TS8qI96AOKupcuCq3ZhuGCYTE59/nZ4DgMuMoRvJW4VDdvO/kLV0CABEzrXOKY7N/0
Xag6fuPuHipVJ5eMUOSfOgVygcemD+YKkIwMbiIiAwPOuV+vCZXZt9oCZ8q9DGSHOo6PUiR9D8BADRg5EtTXYzh0tImkBCdmHTyhapxmmrEPD+xQOQM1v2
9blIYk0mbcfkRGOfnNwWUtNEL83TNUIIlUZGeNHT9FPpUlfKvPILbYW4woW9CABUdNC0sqzc2M4fqI7+b//zz3/AcaHJaVh5kk1pBBqxBYQokDUszps6Ui
nL2U8VqgJWLwmAS5y6xFgLor9BIQHAm0jeHU8pSN417umXrxuyI9Vx3ZLqMb3uC1JKgGsUaZYVFwBo2Yyf9fz+jFwY6RFG4znSjaTURu3nn7NEigyuXCE8
2/H7fd8eRWCscNdxpYRaoi4GHii7cPzdvdbRfUUW52nb3bfdUyrQcrYsKUkHs0H38PD4+PhweLC3HcDvVJujjR54xQZJwTgi34Cz1JGCTD9ekAPKLauBHl
HTaFtGTq7X1XTOf/vnf+emlXwFfo4Er5Rxjzkhpq9bAtEHrfhUctOKeDYmmTrIj/ymAgbmMlxQiOrxPmWzhZLXJQ0tdEEBJHWPOaeYtaSsKz89BeMgC0UW
vwNsdf2vunfzv/5riIUnFiL+KouL8hyftYq2HG5Q4cjkSR808/gfy2Z+fSieV9IRyGRV/9nMKzA17Xi+TNmBGzSqi1W9C+5F0hkKrhwzJxLBUTUCwY3TAF
huopBhb2+rtNo6eBET8m4hO82xzFR/PTG1PVxmORIN523pgdoXd9nscJQLbLyt2JKhBD7N9YwJdMTNuKUvNYD5Y1atqdPhId44/QRHQRcCFR8bxS1kOive
TiSCUi/Eo8sA4DLdp7xXKvR6hVJhGDXBtxLzVEc31E8Z+dPod2AAZV6nsLpF5fgXR2AH/2sgWMcmY08eqOviytfPeCyfbfCNsvJBcyvxZn5xMN1d2+SCJq
emUqAjIYgexmOptHzbEboI8eNF4w/OJ7MbjRBzBRZNJoxI81zEIzvGWvf33S1qUJqVbZ5Ewy4cseEtT8hYPsmjlTEGb0q3Ad4timK3OQQOHSe8mMsGHGwk
lzXQA9SjCxKVFMN3DDP8g+5n+Od/8RpGwgTaiTks8DErP3z33Xc/fIP8pHaiGsP//X/+TX+DG5xcGhF81NMSFi2HOnSqlBh8eAkAfAh3Trlsv68Xuugflj
w9EeJAsIo1NqJPyzM2zbE8GLixAiU3svqKtA9WWy05bte2GVEOGuj0w+utiLOm8X+ya+SDWoznm7+c6qCZE9U6qpMpSZAfGTDeduRoeSSGyLS84qFddBHi
/hPAQ6VRedth1MzFRdNQM1occo2FP5YxUO6DQzkoaV3wbdVnTQAUh6vH24Ji+WQHoKuifEmKQu+C+leQtsQv6LJZY9QA0agCbDC/RW3xcbHWEfCb6IFqE/
iHqhHXN90o81n9px+qVYDfDz8gBqerquXT1A1JCQBauEqP8Y/lsk/gx4ACpwU1XP/zE73nASD4oA7+8C28CVEsTE8bK/VEp2HlhX9Ey00ro47J15jE5Y5E
JwNsPQPnFlOhPVRR4SwEBLqLDVl464gz3qtPwQclDagaiRVlw788kUuz2cykK2DLy+VsK5OR99eRte4aioziw3Ub2mgAL5iH9ggZBJaFCQLtn9UkAKVQnx
RbHxsHiO3Ci2j6yqwWoSAAbmHHkvTUYg0KOKtVtbtN0q+gn8nB3GMYeiGdEFfIAbVczCnbQpnAWNukRoLyQhfS/5kApEpiJJShPM8fvptuvP1BPgDC76Y5
i/UZXPEvkQf6z/+CPw/VHVDUmZPCcgOOpFN1Go2G2/nsHT0XANEHhdD6FQBjj5Ivh1rRFZzhRSsXgKkQUElrjnFVuXijxUWPaGxP4VZPdmmD3cARG9WKSw
aQJHTPmEdcCJ2AhpOh4HaG5lHOqbaXSSmZO1ZioqOdUdY285KLmgvjgsPWlNxlmxGhp3PBNJhljtlX8JHQaVf+mSdo3p+jRHCaeflPuUJbBN4g0s1avaHa
I5UFHBbkHNJ4uIYWCJDI5m3DCJhLmGdVytGHF0G625R6e2gAq1UmSDze0Z+KenXAU1YAlB3xXlPzJgw97anzw3eAnsbbt9L+fTc9Pf0Nq0Q728gA0LLavi
fIBrnIcscyJBrARmPR+Wyyz7kAuMRxNgT2UG+/JjPVVeIuha7gFStJSo49uWYm3nXyyec4mcYjdd9SEYLMbYoFe2AAV29JGTFEoMrB0GAfcbbk9sM18EHl
SWNZ7kO/OdqgC3Ep3HrU3aH/0A+bZi6Pe4wXbhk1RUND8IUX3AmxtAkvyqGXhBk6m/wzq0LRtxON/R6XfrECMVuXTEMpMnUrCcCb6KIUi6sHGdUmumuqCo
BylIBp47Z9Qwhcm/hyF5h0rRcr38ASVW+G7pUjtRGwii779yQApcyGdI6V/Zv+Tj8IwWl8vE509UbNTFKb0MJcq+uoIrz0Y7kEIMTan3unnguAd3dwidix
uuXdfFFY3QuklgHsTUswp5lqCzAy/raSJ8ZpLXnmD2L7QUniD2wrSQUVjmbliFrYSZw6gJdaxP1yz5pc2wEf1JVCIk7aBDosbGYTKc2Q7Q/rWydcXvoSgE
1D80SoYeDUkoV8BTa4LOD42Bjndy6SiL00wz0sYtJLagACdYqCszYm7zzkQ5THNfJhcLtdLLzuRqocL47eF+IkzE0VI6xuj0xYNGkPsc5kk1SDS35L5Zu3
DVjvxMnYYACtRbXEqh6uBYGff91QQzTBA18M/4DNRBKBN5TrhWenKgF4FfD23Q+VilP5RqFv+ofpTuSDxlxQIqMRMJFdiEqr1CzBOiFD/E0vLsIif74MAC
54EGd/xAEKWCAvFN8fKPwVDhBddrOcw0ZIDhzNqwXiumqMvamrsAMsYI+I2IUu9mrfxJ1E/HEUK9H4Q3/ubGSSa+CDSlpEoPu95Qm0k2MF4kz2fnEV1QaD
RIIsytr6DtJEtLDGWLMSHUkwCfRTLswALuBbcjRJtfENNmuTqBXc+phe4LpakANA6X9u45W3HQFw9aZXUtuiAKgGD/C8gNfpYyNSVeZ6yAB+A9ahEp69bj
vOFZN23cIyBGdzc6xqYHOQ55mGnKVGLkBV/Ms/6+cGj6bSyLSgqE7/UIlmB/KqhON3tohGQZSd9/8TpVH/v5RFo4HVqJNJPDu4TatvG9PkCl+4NL2O7rnU
by8FRy8KLwaBvBpLha294banqFdjAFj9J7Dz4K9nhueRsJHwDhKChsNBAavwx1vKANoKf3C5+xEbyD8jnfIh5xty+qQrElIfFu6K0OOc44lb7A7d+S/mua
oB6b+ATHqp7CsY90+RNlCNSIaqQYRnLqF8Dv7AS+hrCi7FgJilV6G4hfW9frmcJ6klc1EOCg0XC7OtGIBDr04joGiXh0pREgWq/Jw2LFlgXaS2K9n2gQ7a
dGPStcArzNN3DBz9tSVMyZgUd8Itg1dcBYsvWIi/KQc8KHFdM5mXp9i+5rvNj83+ho3N3pgNZSwmnFkeAjgik6rL3xauHG5qAwDtBjll8CnYpQDwPhN9Ej
EoDGlUcaurWldLYKwOtzH4N/ItYFiB1YGzXcEIITNBmLNgazUSp0TFOyW8ReV+BUA4uEvLiUbas/ugzPHwOqMoMBr4S8UxllGqgHA9mpl7EptHsyyJIiJ4
ORhuDQc9TMCPl/YmVSRpAFGMQlxYDWJhzVPDtLQHKvVK5GwNrAUm1HPN0Y5UX8jZNNsJXapD71hvcQKAhWNm59Bn6Mc42gCiHExDPnyyo2h2lFas9bbhc/
YB8/PcVOUWRCARVuCKZN4fUGTjxr9gP1I5uiNsWQL0HDdqNS6broMN10xmcGWEcd2+cfPmTcQv6jKp9woLxC9ogGMGqO1MK0/4kgB492e0GjY7LqweDFax
AHGzoISykBQzDAQbYbRK/L39TuZ6v0uzYeTdTHJqeuSAigPlL+uBwl8HDccScd5NRX86Y4FpgfOatHRNpbRLNlhmaNOsf9MK9bSWIphATUQy+0gUed8dyt
bF1RIKieWXVmg4gxS1ETbqKvrOhfFAwQ6wmuO7ljoqrsRfSGPk8N53c3qKknkkTknOYqH7Pp67XfdojDzJoWFvigJg8TXPeqBSr52Tq/cxDG1uV1WGorHo
fglb6zMSaWxDmnkI4Bi/RpJhG4akGhmmhQ6/6eKVzd73XiOP9Q833uvh6nLSO8RLfUv25EblJiS/cj8OcsDH8Tzv/R9uEIAVAOEelTE1lvAjAC5WPndXzw
vAbzEZQVFgYYh9C/UDLVQnlcN6QmQasyQVu/KdTvVyz8oU6hnfKhS1Nl4sxkK73sUivDSAc1SJdKO+bX7WjoJNVvMclXbplwFP5Y9k//jHrF+GDtVQmeN6
CzWEEX7UR7Z/VIpl+HeFHMNm5qiNNNFy4nzR0JEHkouLISd/APyBe+JXHHWI0AXFJCSXjTZufPXlAxDnHcoREXICxCpKExy/P6of1kulP6MfPtSjIVCUMN
sFaEjL50sbY3c4LfdtA9lLuFvhxAryyEqWAGxU4F5bgt/6h0qLOphZA/xhyY61Dg7hGNWHXYz0/ERDiC9bWCzLymyWZUUdrD5GGMzDDLj4w7//yx86hnJA
VdUf8QcAXLQ0AH+8FABCFGjjeHQ5l6uIhJhSwnYVii2BDnhqMDMOSfrh7Q+KbIBT1ZIHFa6jXS2pnYZfsVTf9aIIkFQ3dmT2TdXiz3iQF7iU9CSWMrofCn
/NRGUsmoKLvHMSrq2/FBxrnQS/1lAm5tWnnfek/rtpGiPn2qYiFWycNgj2xUwGBPvnyfSs5VQtC85go4G9atgTIQegO8I5tbuxw+qyFewQcFbfOni1PfsH
8uEE/Ku3vXdweNAqSGIajf0wUgqHhlSmtGV4wO1Q1chU5RYZ9JOqfmIRQl7uuMI5BODdJ2oQly3HEsKObh+uqmrKaqmL25uWYE4FQqn2cSoVwi57Lw+Qh3
6zi7okqIgkc1nKDgIAMaVccSq4wEZ4WQBc8tBq2LIgFAm1JgSkZ0WqM0v25XyTAGCaBwwGslUoFpNTJSL7V5/fZ8oAqnLuU1b1fV9m2c9MhkFXTdVbXepx
7AsvKk5nTqaSSEO4nSAALcdT8IseeAVTnnCyvXa6tVdTUSAoqlDRtnIhPuiCwh/d3ojAxUYDK472TMg5HU4k8Lh5kvmRHiNlYAqrhcOg1fPk2Az59jnXI2
Nbg0P0u+GelTFVuhZqeZTvbXcY/ugU/mC/JpYL1QB0K1gdnlO/hyOxcZIayoYxEQxTquZHngjdyOZZpzQi04MhyavS6guJ4NKwBRFjX94syg6SMDO8lY7j
Ny4VgHfXkQ7jsqBOCdB4roeeyFJ/nwqIMBcl+A8//JPi+0zztEYXGMAtPaozKQWI/uxKVx8B/Zp3UJiwatvuOQAIR5X5fZVRAZcJEAghHbdG3UfKtbaKCQ
D6XIjeEZzR+OMC/lZOZDNnTnKRHFCkSQkk8vhvF6mCOfluXOx9aBLK6P7uuIsNvwPe54eluzNwTjBnSR8mfwaHUgGAqH61cHyrR3U0JfYdYaz90XWwQVB4
ve1tiMzzJB3R/LSlUAPEDGF1cZqS9BqBk4oDAYD40RuVRgWA/s1DdS5RqZteL+Bvv55WV14depKwliZq5Qpr0DxEb5ia4XUEiHSuG4BuLHeoZnoesI4lxw
02Ls0FRRqsgwd3v6TMX2rYXwFpEqyaYS7b3/0QEe70rJCISN8aGbSuwv/6QOEPyVty6x4z8t396uKZXdAl+GYbpsHhvpSpHMyE2h1rNP6jCYCwzhKNpCyd
YFOU8F6VMtMDS/N/3xeyupmWKNQlQPJDiUlXaWDFsDP5DtWlOcauaiEasETVqovVt6dL8qWBA2/pTOg4Gwi2+mD1cK+H9A7/Y9QRkBAlxFxh05c6RrW2Of
rCNgQlJ90wlC0fzE7iDw9C+HByAFxchP9vdFht6a46G9xUF764UcocKlROIV9krDB2klhoCy+eUkeXbKEOsZVvY/e9dEBRGX1OdmQA/Cz3spIwSDVEPwOM
cKtUjAGYmApY7AneSI7WgdgjBmBFcSi0ABkTR/pdFVMjPusQAOoavBZi+lFGM/CSK9bi2ZIwS/DWNihacUlH0Y1YVekpB+q/+3TRKACC9/myXkhMVSf8rc
y/iVTCsywElZNAB5Rj8+aiFIuZmzz+RP96JIBlWdWOw9im4p8sPcEfXpYetV8eI71UdsXrWex4UzKFaYXClAyOHkuQ1CBO+GcdKgFy5F2QtDYmKTR7aSIr
f0jFOlppw2a2AuDdZyoMpDu9JO/NgsomFUsQG/FRCbvR6SCyYnS0WkwM7yaNym1wYiooRQgLDDHDOjPDmKvzzZcIwLubYMTQS26VEvPCY1cU2fLVxcSi2s
yelinQ7374LqKbK+EpxmWhNzGkTvrd9SmuHVDd8n8fvAt1nVYai2frc5mRBXXDCBSWHbi2owxmjD5TTaZk+3JpJQjkWW9YSF4StDX1KcAfb+Df8Xk/0xAo
WSEWHkYuOpWGnDMz8QaBK1zUHkQCbdbiIpg/78NShM9nPJQzb+HsuOU0bzzu7XMkqac8pi0kEg4djaKUt03Hse0ILvtwnz7llHy0NIMXSZiT8L4fcibTTY
bV+IaFV+IidRWH0aCoZCnhnRWPbsL+FYcZElYei1fLVWAX3IvE8O6Sym746IA62NQC99uHNc3MWqx8dkfgJAC4xLHo4hICY2tQiOKieU/YjURBDVBWmf4O
/PXq2x9s4aQy4A7NhB4FYKk+DOIAkC1IL19NZyAGhH+mQvwVrppWDBSlUAG1k+zeSFfJIAaUi/rzkHl7xXRggbi80+XYG+/SMmOZcC1yaqkuCAQgr7jKEE
yYi7ZkM698Xbt6i43FBiCejuXDZXiWlhZ+4sRzjVzupApcNgoaU6dPqIbmzCEi7gtlOVwqHMGB3JTpLt9YdI2YQj8RJ3QNJ7/ST6alRr4Z0vAA5KjUkMhO
FLa2gwHclAHzjRzHeQSAYEIPXhSG3e1BKRHrF9G1C11Uoyf8PfkQGUDLBU/4cqho0Sl2CYH7pZEpQmgT9vGspciQodMJKZMm7NQEE6uqD3gagBJ/rKPwhx
nQh5sJ/FmNxepZsvlwd3Bl58D09WXWkIuY4JbeFaQvd+U0yiN243i1kI1Ut7oe6qQ0GhYpoWima+TJuDKRwzudDvxk1cvYZOFkyclXOuLqA40NFz4NZwHg
b2n9Gc315TMfnq5xjJBkqbpZjgaJxYlb08jXaRpt+KA0q28aZrpog/wTWZ7tkNMSLqmEly65yTBwIhqhm3gSdCGCRd8SK6E2F3uFUtafOmCteqnHKhU3x+
XMXiVIfxr2gr3jYvop1N/D8VX4W/vwQUeAcBp9/rmiFBMBILxWdKcbnveynp3ihbb/JQCwkXCycXcCcB6bG4GTuD4jAKYLEAp/cHLg2HYQf9jsuLyGHni0
kYuLZxLb2mTso/KiLNdDPozMEvkjgp+RTNvBKtFTWzcLUbEzomltI/zAs2y46uZEOnfEopEmAZWmcCEdxl2LatLNMPKaJvPMcK9c1mqCbsfhbO3a3btPnw
jhzW63cPTK2swchIGmdIAlmygFLJc75mklwvQftu1InigqBdqiYmJ8ZAuJP+m03F1aS3c/NSZSg3kq2+HJ3ruAwGcLMjchiB9YGolnCquHrDWPV8OpCpr6
ULKgK7aLL6LMos62FW4KJmNbwN/MGuO+q0l/7HLakdTDww6JfDns4E4pM0xd0lcIgAmlzaarhbHTM7wWHSLVZEqA9fqujP8U/pbuLmzGTTb02s9WTYObY6
OsvsPbtw4L5G40iSuSI0tR/oghKgkElwoyqFesg2Jh9Xgb7UunWnmrFmu4suU/qmvLC5LLi6QjU9b4TBqAc2z2QeQeujip4MrdJXAYegdUszvseowFDpcO
hOknSK3qhoSrg1ppT1EgHhmvbpUT38KoYYEaAEhNEBgALse0sXiQJ91oP0/EAiQOA3K9H1+ZQebLzYEn5aKzefXVIQvEbItLFffUNGYr2xtgwNvYe5Emha
gq2w2pngZOxYzH7GblG186/fblNOTq+yfsLEoEstnVVESk0xURABNTcc2RUQoIwIpU4k0U1cCFXTmBu8xT8Z94cmVhh3pM41eOvV5nSahtgqmQWblGo4KC
KUpU3+XxjZ6KfqpsX3ajFkox7wUXuVq6gaU9u/L2LRYXIilC2e4q+33JJYOwB28SG11Qx7ar7uQt4EPO3pXjQvIiIGzmyhrzBhG/77AlWFBDIRjlElvpeo
kjPCEJSuZnTA6iNH2k/2BKnmkCfw5PdjwucV0z1Bz6CUSBa8xJnAaps8H2Ci9e1Ok8FXNsYBdiwyETfrbybnuslhYWhutobzVOLMbfB9UZBHuPbg/1daEH
R1X4xuer708CgJxVIPbFDJAfatG6qJCO3DRwQRuNSGMsiu6bzZFRJmjIDiT/KcYf8g5eIpNC9iDNbKIuqFJ90u+8epYmz6UOGEC69Bpq2DWjERE08t0vj5
hAZO0i5TymHBR1x+Itj7VOcC7HW/A/9cxAC8VGPKr8WQhpOJGmo7l0sCCcv9fxkRY60RgQ7MH09biI7KN8pyd6hzG9tlDYI2lHphHImqaVHNyEbyIxXS1S
uLGspFpcrLjIFLlSC98I1YLPQpqGFG5m3Q6d+MYc/gQSoeuyEKGebyoY9r56QWK1g1z8FQr1gK0MxMh8OawaRol5lbEQrdWoAp8OsQrb4JseH2F85EuwVh
bhNq9+/o5Oog7IOBoQjjlfhw9XM7a6UF/poSBe9vJ0ucf6hpWOfRHIvVLchwTPfBdu45PSAA4MFnMpdcPh1FYrVgzAypmURq5wD8f1Wi4BEMASMjlnmWRE
Yl3LSHwwlA5y2kXGYGAwO5ivw2ek/EuSxsSJU4MdVn3AH07WVvgLpZE1Fr/BPMhEuWhXyK7r5hMb4ceoRpSo0haOpE5w38Tip4+NV/FtyKVY1siMMRdefi
3hZ8apYkd3oSsZC4k/X6r3sIw5uMK4GjJBDQwTGYuxRpGlMoD+InzXluKIH8cOVRo9A9G9CvuV1fRWupExAMHBPi6MA+CWQD46CkD4chif2/giAzgJAD4G
b3DxLSLQQZGfQZKVjKmi+i6Y5wQATU0JFcLJqqgsQvgqXkYGFL7RAdwu2/OlOlxYGMtL+NFY6EY1QiCE8vwsyQpWe4Dsl6oaNs+ebsoWJFkQsc1yYgqxgY
P1eL1QHAUgMiP+XKrP168y3kjk1dD/47wJBtWTBzzCH10k+JVto9LwJ1yGuBLycjxcQ+wf1LuipWi6cXhwJKMXVxIZGM4IVgD0pU7BSH6+DDgVXrp/UP+a
R9Fuuanb0yX+OozNfZtNffmG71RpwLDlTiQNc1+14NJtvLi4yBlRx4peL8Efk1DUqet5zoNOJQtAC0vqzXIy7yZoQmUeOYsk+pA4UmgJInKgM4WzEj4/IX
9+AN5nWAxxaVIY/OSAnRSSrIPSysq+4H4EwOh4OoKNAhA7moWYresus8KQB90tcEPrcMlIz97u69jRrepCF5znpTPESnPogeI97Fc7VUmvoRSBVivnzXJc
EaOIbiC1v0d4qkUdq3I/DUBrsUkGRuYIYvytzWHiuA0AxIh9sqqEC9ybjkWQB4UXQ/AqSqUMUXD1lXfQE8r0wRWB/ANTFfCIPJgDQCnhkyeV6iqBO/qRsv
5QobIRBg1zm5ubO8tLiQ/IO7bjQwjsU1JqEn1Jj7CepIpweCNL4NXZ3qrmg8SZiQG2EZfq++SwmFmJV5aQ+0FfyFNdkXkWEFkm2INeOPSo6I8nGFVB/3GJ
AFyXUw4aEP04YL1Kr6QNVF5kvb6C+kwqMZ+EIF6ntSx7F94efpfg1bCOD7hNdexwwl/3hBycqElRSFrxVZJBJ7m/OASUyQp0BFHK5+HdFAJdTn2euhwLkU
2gCYVxu1QERggEV07wqrEy40hRMFlW3B0hK5mMPX76JCLxwI95OmEAsuZ1nZ4crhaLgTguRPgrRjdGb1h6TfMNLCnBIQuC5Q3KaeYkQBUAc0uCONzEgQvF
wMUaKfzpx9NUuLtLTHUiuLZzjj7OrBMqiWcGTuytqLGSJRKSzVqt4/3BKpzMFmMVMgynARBT2TRyYXhYKOZYwEPJc4NgM3QlKbLBvyQfeH4A/iRP0uLbCr
iPKIs2rHXrWrmuXp9vIQdXVjxHAGhnhd+xoKAE3DnnXVkEJANY9wTAz5VVYc1kqqqdPpsTc42zadUw0Hhb0dIsa3E6ITqUpiKN3Ja1h2LskSQd0tJKlwCY
PLdt/Ca2JrlJAxiyJ1c2lXishXquE5YFxQbx6+Sld9id1RKNVizFfWJx4PoKBVwBgWVDmy6IzMp9PTEglWvJAWAGgX1KXik2FgYjGLOjn/u6Ozg6Qla3Lk
4v6AoMeP8Nw57MvE5wQm3ldGBO7khavv3hKGwAgcGghADkYwDYL0fSeAhATF+9fFXKcUFRi5OoWwBEoTKgHfYl7J7zA/AZ8W8wDdOwxSu8K7YCtn1wh5yy
+RMksITVSsPKss5xn20jPQ8ZzrwP59Pbvf2mtb23FRUzSnUklHbIkCTmfLqoNYfDoM4WQl2RAJRiWlXBlvRVyjQ9Dg8l5WIs33EcTVONCiyZpzTfE3bDt1
ILBfuGvblt8rl5p0NM1ivYRvWNJMIY1TPFr6fTC7ich0C0ncJsL1M0UQCsDzGL56kLp4zBG4W9H+2aas7JVEHTABxtPwJbr9IvmJUG/GEpfHtYlPznwxuM
PbmviCsRgwIB+Hgiq16XCDTwEu/onraDrVy7NfSm6hQaVRqZsorFUwldag8YFgqt7cKYZ7snrzTY+4prUX/1l9yn5wegoryj4AFXM3KLt94L5vVa+z0wW7
P7JIFmjWqDgauZok8YRnMDxbOYzPomS4oFMIC8wjuJyh82o3cstyPOnEV7yqVsAcUN1VgbaY2aGeREyqYtvL5RkUa5pYrvhVRfS/xLuCQqDX8xMYgaoz5p
+1F8UtbfGZsB/LmLujc1nLgs6BWOrDrL6FBNteQNlcscMTkiOIIJxLSyg5YPngoL/USCxUhTJcE5HRsDqokQyv10sfO32gmZ6G0pjQTsgj3skZuxE3Em6S
q1JzWtZQcOj4ukqMVFqWZTonumkOEr0aa1bGxuq/oV1xwdXimSAMQq4ItXrwuFfAO4+mpWfvsbcEArDRfw90Uid+cG4H0NQAsB+IpYB4CdYbcHV6vXe3lQ
2mXI14mGd0U9Eap2Gbe1+Cii5yxi03lcRZTvq9QTHqyO+wmVAHCaqiivdWYmRQqATlwQfrimaDbSM8OhPuz13rALHqiyfgnwxR9z9RAvCerP1/oi8Hdtmd
LG/m+svyOS59ZUULgoZ3ROXKb2ISCBpiu+WkUlz1aam1SXmJC/UQ+wi40SvojAps1sN56xnWkoRnJr3D5txv9D9tOmoc4q/cntDqYTuwXVCKReVxdunw9x
Dwv81UVrcu2QM8Q0BSvkKjmpSBwlg55iaeDNemgAK1GLYxKAG2mz3jv2hmPwh/Rf+f33CIDwEr5sXPMEAKj12RqVTqQmgS4HpU6wju6xasVB5RTbdxNNEd
hFpvo6y4a7Ib8ADqVs/khWblbrPaxkLBq+nWS/uBUUuvrHeQ1FRJ/9R4IhI4hpI49gTTCIRl8MaAxp5i6NAQj3O9w51YavSVGoFsP9KJ/DtZgwyc1QRxwC
0GWTCYEy3EgssVfYEEe6DW6upriBpW7vSAevSJSfu4KzI5pyI7BuwV0jMf58DAAzJKFmjYmaVCpGTfqOQ1J/3dWIs6B2coAZHt9KANDtTE4Q4ApqBWHGzx
Zyrwr1I/nvdMRQAquARRjPrlhZjqtN5bG4wIIkK4zzxrmghWOdDuVUyvpCkdcJAtCtgJeVuSlKK/NYBqx+U7EWfdwTnCHrSttSlsVYU8qgQoC00aS2hgpp
b+pEKv7/gSdkwtiyY+4Z1v7ZuUrYD6VItLo9UkP6nnKBQ+HlukK2V6DJ23d0k1WW70o34cvdUo9xcCylAUFnxFEVXT+UsrTof+7vk2CxJA5janXiBlDncm
1O/lc9/XHBGt0SvaFOb70R/NoVGffI/bAwC92PwGcaMYEpAmCWkoZrtd3EXePASj3RyvZm43XAmG0lAdgIJyiJs4Qth6zjS0VvREcvZqIlj+WuJwRHUWQO
JtM0E7N1XNt2mrEOpYs5QemTjX3I070N3htj4ZeKLE8QgNZb8EF76Q+KADwB9FDCwYDV2FLcDcxBrVaTjCwMLACWTcklWlz0aed01hy82Vns8HnbwPu1on
SGAH4oPhxuLp3HU0swCH2KznbuJzKkGiZkkWlK/TCZ/8wCEM/5SwIgsUlrjI4ksl9kRkLij++uzE91lR6JVUFv7SJ0sbHN6mPndd5RwY973AN3uoC55fmX
gi/dXViDo1idLismLE7M3Wim+iE1AAVLjW8jpw25brZrmWqWJw6ipl0NilkvARH4SkXYCoKLk9ZFxTaZ+IcXvb3VuIUB9ZRKWC+a30WcVipVG5Pr6JmV1Y
OruK59NDiucPbga/YKpXHo25IlqGKXmEVffJlOMAbESgQTs5nE4PxKDwXALBVSGVZTTVDgYRjiIAVSjo0VDxZJ4b2lhSjrA9SA407lrRQxoWkpWC3EQdzn
1bXb0V0sMq/q4+isqFa1w5UzxiXwVg9UZq2YOdCRU1oCIwkAtEgnm2kDasiMBPUEeHxQn5+vl7Z6hMDFis8mQsTKrQVyVYzOuswqGHuF8cH8/Bvx5DkeW9
wPR0tPuA6XE7dTJAlMXDM7KT1YJrlptH5UUZEBc1W6nwE7Sru++nPMwnWaYNHbE9cDWHj0xPPYkWQltyQXraBpkd0BXjvzXYEeYwVCHilqE9rORt9tUl0I
jqjrbzjSLXN8jCj3ZLw/LI5w0updRZlsiTOlI84NwIcsTPWBAHZWk/iry5vB9ttlpeCZo8SsYQA7H9KQYOF1D24eDbotVMPjNrwqmqRoNACAYCRdHAL8hd
Fu3mXJFX8ooqeC47S2+XR5Yenh3aUreJU6ro98elrMvmxsyVoUnY1B1jmSXt0NQJoTtcdUUUlRjlPjLJhHdgF8aYD1ssUKvxhNUEmHYT3ZjJKTsC0U3rDB
n0v1O3f2hXyNDzexP6MPmJLlAcyIsWDDNZR7RsuBk6kjYzQWBFS4HVF+bZHq6tr8wc8e7tdHOtOUuL2wyU/HWw9ZTJsX4AEsy7YVzEz39DCBAiBvyN7UV+
bn5wPCX0V3sDt2ZmqlcsvgzxenAYDSoS3d3sreJoVBS3WdB2c7j+cvQ8zpViwwXqEP/qM3KMkSQqm+sjLfBTDN0Xocty01fNqpECJSLrF88lywfwwT2PIB
o1GtVHTJzPCph7WBV+xP53dcHvK4k1pmLp2IBLD25KcnaoCaNuoHr0uFUfzFxe16vUfzAfC20XQdH5Yv2dce259qcT4lpeK2POajjtRFydKTfadOnKlSbv
yyEgTzcD9OeUK7EVc6PEQImiqFSxiET7/hNhNSaPqXH/uO7ckQSucAbNo8zkI+h8XrgSrBrZbqKY2uwg0RLAICcf8XsYy7cBGrX2ODF+hygonvzVM8g4Zv
pcVuD+/Mr7yk1jFfHiuVhHfdho/lXnx8nLFi6F5Th0kF8PpJq15KBSHFUiAVEjDT8fDrAPBRFEi5nQZe6hDDd+/UqQw/dYKNGrDDy494dKcYatBzkrDlKn
U76avJFDZmbGyiSb/VYwDdagPghzh99uNkzmhC/hPxVwHjWsWDGF+DtmI1QeQkbhVSVcBi5INKL2TANFvOlJOrfC6i7Cd7OQ/30ctgS7ej2ZZ9QfPSozN4
DIfmTSmPRlyE0LwFpuBlxD+gQhqXVPfII6FtwdRLAFvXd+Hp932nFqAINMZOMTEQ0RqSYCTfXJhhSJCsUxrtuLtXT9HXC8ee6Fs+nnsLUzAXM557mTFk4c
ESWyLYxYQ8wA+WG+AuzKrNdbQ7ltRbjFlZmisAjvVLOAN1iBxP0HGPX2KJMnPwY+rbZ1zHJMjYetq2jXPvGxV0S5gX9Hq9APfOUxfcMrbxwZ+EAEPH910X
/BkXrxyZnKeTisavo1WXkSSFbUKyYI3l1cVK1UWmzMREzRe4mh0jJbWqFR0P4ierohSt26hQCkySHbxSioaWEJ6iCzaANVR0ZzhsHFeTnHBB3gA9n3rpNh
/I2B1mIeBmAAC4IklEQVT78cILHU29yY4KhaFTzOuHK8KV7c1jMTpJQ7m/qc6lGTdLWxSze6PuWdOKR8KjQLEnq5zI+FyjcJnE+/a8vYw+QglMoG36WKBZ
nLYnrYeTWD0bAGbm6ZJpTcG/h4PXcB6D7ksuvE0l7g13iGHEqotRclbdoOB1S7+MnfwZv1fAdldgE6muiQTJAQvqRXT1hmdNpk2gHemJ1qKR1WXAjPSoqd
tlLXHEHi5DdJxxtIXu6e/YdofUbbApz+M4hwau1IbbcAF4ePXSGAWOsR9/+nBybhrpI8i37lT0scNMmEtodN86EAAoKcib+Muk7SsmGCb1lasCB6Rq4WgM
UyP4MXGycgc2sIRaCF1KD+/DH69fJP7ACLQKhTudUqE4yp0rgfPJbne9LAtgeU2GAX0rpVdA7gf5aA0Xyc76N2XhwQnJa8d1PsH9XmJ4U+Ebq88KnYpJAH
AoWLtZtUwX+693Lu7+Ea0hBnwrt1FQLwiw8jAn7/ormGQLk7FelntOblmlRm+D4x52wYDCS/N24VvW1QPx1UDa1t5Z+YQTAOC6Usd1O7ofsoIghMeWUlhp
o7MTsux9Gj8hX9tEdRtOCBQi9KXpc12deUlBegJRIOsoX99oVI2EToZVldcJKsVIJiWcnJY4SPcDxtSK0vxVgVK7ivjic+lPE/UMVhLckfiD8G+AhD24l5
VS4MU9z5+w4YtBWM8phMEHuBMIPJcfRjZoU/Y8S9ZEZBpG1ECjtBlncjAQ3KOP5d4sUPqnVPrz1ntxczWtW0z13Z7wTTj1NCv3wqYD333sCe/lLtlA2cft
Pfp2aWH98WOpkLq0vMMTB8+2MfbzwdHu+5gD7XAdg9g0dkUEJ1N35rvMezUvKSb13X0muvjt51dmz1zNnYwkRZVkHCKmpis9x0ouy/Gp3C+Sktp59Ojnn3
+i5+efH60vLy88lO57hEBkz5D9U57A5oQdlmX54fEwVXwj0omyDF8OZnSxTWKoZH0gemEHhRwAwrGawsLf2wrqDkKoGir40Wd+vDADGwUIlN+l9FpsgTl8
yeaeXywA4WoMSlOhZkWmQkBKvwwPUOAqp5q9xj2K/MDPNFIBkU6g0Ssj35RFxu/ZI703GoD1AC+sYiGrIlDoiqoJJwTxt3CRLgB+rgBMHwtmvv3T8kJ2rU
trcDd6XsIXEyJpDjw6p6H6IqFnqgfdg93dQbfHhIwr5qf2zx4UTU1mnX4EQCOCIEqkLuWlBiT+vPEvP5Rf4nF1Oakd5mvrk78ud7hOIhF4oohQ1hGMxUql
o8bkEbmeeSelSLEmEniQuhk2OMmWzFsA+pwIfnefewwv4rrUuCkNxOz8nfkWm7l70c8a652EJ4VS2lpTPn7llvAghBnTibgQGQcup7JkwiOFvei8hmvrC8
m0QEBa1C16czmliCPBKxDvs4vFHxo5MOchD2aujS2WKlvgba6l3LJQPuCQrREONUzZ45m5CJ9wGHanpgYtJs6elJiILCF4lRg+2W6irgABW26OYZl5gcTf
+LTRjjKB8EVrT9dURnRt52IyFptc1YXpto+iACfiqFXlWGoJuFcsbE3pEc06+zLsUkK+UXFoBElI6JOZXDphCyzAi1L9pdK856EBYssXDsAlOFrhfpo+UL
zzagC+FBjAk3lvbAmAZiYmki5cDSaj4cScS4Oh/nBt50rm2zxjhwDAXeFlSiARbY8x0kpbW7h78e9gYWmcp/EhdsYoGn94P/Wov0+T/6QR/LBMgqM7a/B3
NlGJl9HETrxkvyoAMeNkk9cWdcsuYlVoPfdLIRwGCHqntE0tyBcDX4c51If3f/zx/sWVyxCBdjMFQLjomxqARLCTtR6yeAO4Nd9MrWgMgi0ZtDxKI+mYAd
CnChmwOd4SXTpvEH9FBcD6azZ1pyee3b2E0zcDBmArU73casG7Zaw7FYzP3K3rY4cDdce5aLhCnnfNPmLdAoqI7K3mUifRlUcD+vjuV32egzMmjcGpc9Ie
gwn0PIJp5NA9f/6cDOzjJ2gZznM4JwPAu089LMlWUclHlYW8/L6oh3DabQXA0xKr3A5kBnH94jdih1Pxq9GILKDs9Y0JduyOnC6ABbwt7G8MWt3BAAKBk5
f7XnQqkVfnIPpk/Z48F7pl1tkJxArFgtZZ7LF9j7HLOWVX5sI3f840w5XAa2Inu6dxNyg6IuOw8/Du/fs//uNnFaw/fvx4c3Nn5+nTMAol1nNKU2z453nO
jvO5y4U6Wdf1r4s/tPL6LJ52Gf6D4kgCYI7JeL50vg8xNanFPMZgrSrTuU2/w8bMvVlnvAarxtU8OrWKKr2d4FLOKQbrHddyqT9P67M2dNcFNnl5W/Hgp/
qACHIi4Z9ho3uV/E5pLp490RE88azW2aA+X4+EFleQnXBpt/+3PNwtpWcYlpALGQTPFk4p7kbO2cJYr8eTqbI8Nits83Cevc/thiULKNijpa+MP3TG6Izx
03valD8GxvIiNm1qYt/p/mMVs9ukRDDGqINtozYIfvp01CcsqNmXZgLvLqxJVhU2WWDFA5BYrTao9PgWHr8j+FD3sNaxmi4oJEAjgV3uNrIHdNbi2c/r93
HTFAAxD0UALEUAHHps7srlnbMPLLizUkrmQep3sBtgZunU0lKgPv/4L/GUBczjYD1irIXVwLhomlLTvMDy35cEyOhlBQjAU7/wmfBUQMR/zQAECD6KMklP
1j9h2k63+mQoZbsSe3Ypu7FMEKxWGtPwIPAqdrUC2INf+ZUqGvSBjvnmpULbGpd5sgRtbe3Rj/ejNISHWxZwVJ1/yrpJAHbZpd7/S3OsBp85NkWl+TvzA3
FqFXINvS5K4I9lSi+ETK4wl0/3fB2dAEXH3qrH/gOxh+6IS8hAfXLLmYcnLAB7cbomxmPhBTIg8pZ/1QDEXVleh2f54fiAlteUMub6J26nGj32RdKV0/ux
STWtDoCQnopTrVQirxK1pYcoz7ZSr8+jnCZbWlpYfvr06aOdnUePHsGaFxbSFsAL5PHcJEqKBiCOS+Ss9Vrwy0PgtwGzd+t1reqF+Jvvnaqkeh/r0hJc47
cJDQh8SeCJ3GDiw23UhcBFb3fVeL7IBX4l2MJXB+Bj8LLggNU+ycgFqyEPY3D+BpyLBuCnLmNGVh+X8gkK4Bq9HXg4e3JpQfnOWtQMwSUtjunhN5Rybg2G
8/O7XUq7rH3qeiUbAkEs9rt6HOymcgDv7ItgZSVgHy7vtV+zmdfV/CkqHbfEqVXITXz7FB15C58KoWo835lZmroqXqJw5vsbhWiUhmrdaQn21fF3F5wxBS
v2mV9ZY95vHIDrZPUJVp9wp5+GvKYWfZneysLTzbUIfMqbfkQUiqVHXEZ9qvo881kBRq2GeVD4j8HKvNRGKOwG+7eRRb95ie/92hy88O7u1PwKPnewR+W0
CPAhD7X7cco985TChBomynJR+sd3gu1CuLe9WkxJIpJK0NcPAdEDVVf8p1TZnsTWYPk3DMDnC1cotyJRtfPJA0xfaCNW1y6qCJ9//BYWrly5At7lctqtXH
o6x1Xti3/6VlhTDg6lzjZZb2Ve9YWWtrAp9+RSAXh36QPqs3pzsycn3avwS+/U16+ghbbhFM3uZX1HjvNTrwLOB8Hr7CQN5DDzr54CVR4oPF74qZ6wdfU+
4IU8WVj6jQJQ+Xfa6n+SgzTDeRQFEt3i6wcNd59/4DIfxj99gnZUtBsw78rSB8ZOZBQoB8nXSy8vuwq29GFN1ScBfqczN5bW1Dad6oFiFkZ/2dq1vNfx7d
X9VsCOElPRMANTX7nDv3YJcGH90WOMhtRZ/OSXczKWctKv9+TR898gALEhlwf6JoGd/YScEqpb2bTmGue3Tl7C31j/+ghcVrnNz3ChlkOd74V1z3nMG9Yj
iYZ6fcv7ClmIpeWnO5szM8kxKTk4ncFklLINp5vpJ3EQxflOznquXZ0/IIW7eCRMCQLQ/Qvqwf3c509rdBN5toqGPvlprnDpzuBmkqbY8m8OgJuMbe9ude
Ng9hNNtTOwZM5lvBiw/ZWV+X3Bv7oNfI7ZebSAnxGXfstlKbMmOcsetmLrunS93hKP7/4anw8qC6WBddo9s+yxyAfluc2Nz2fenOxH2ddCaYW60lun2tVL
wB9c5q3BGxWj258WF0JiOq8pf+bk1lUmJriAywHgOgNPZHUXPnkgITU48U7zQtc5e7XSYjV09oQIUEoMAveZr3s4l9FtobguyGmjy3ota7BYAqDN3iBf3m
Otel1KdJZQqGrh14g/OGpB96AF96RMb54m8/w4AmrNC6bgL+V87cIc1/cOyqZM1VdWdgP2dWuAS5ztb5VucXJQwADyN97pCNwM2ZuufCV2IPbnp3YD8eS3
BUAIKgaozij16nHjdpGKsXnKOxoUcHwboO/99s0S3J13VlriqwIQ6Wo8Ng38Ex8GfM5AOXIsWCkNPUDg/rBOpfzd3q+hDp0b67DteuGERR98f/ygg8dMvH
mjvpCLkz+X9vK4TQtcvETqEA5P3PVOdruoA3Dlqy7yKWlVHXhM8ggYXxmcWmteYOz2ylWBVVH4O68PUMlqgvfnpQBwIeRaZbe0dfPoaLh1Zwq7lMf63Iy0
3raGN4eHJXl7Yun4awIQYtKXw9ueTJzxYJ+dHjk8YXyqKyhd4/UG9ZXSAblp+91Xr15iI+f6rxF/d2fwvZcOesQkD7h4g/XC+2OiYdaFO9EjKprXRYj18g
ry60xsUwWydCcgmZ9w7ivb/k05s7M0aCFj0gtuz5e6p5E8N9mblflBK/A8r7d9k8Rg5r3fGAC/DYN0T2hh/s78wXgfdAenMBQT9EW8P5n3FW9OsA1gw/H6
Jk5gq3RyKpVnGW38Se+9977XPSqRBLwnPnxQUhze5q/S/8TSyRHKiJaGr1q94HVvewpViNbHfGlrfv5ku9frbXdvllZJuj83rn2EGq+7w+FJgPyGYObK86
++SKlth8ZgOBzO11fqw1NK8Q9DNrUyXyjUj49LWlx1i/3GAHgtwCGjpYSOAyrljGdjSQAWo65X+N/5QIyMGr/U9OdL8KHrg+1ewPnr1m699Oo0hs4j9nLl
DgFP6sWUSrBn395d+nYGng+/UvihBbxDw4zoQ+PA0fmVl/nG4TlcSLCHeBxfvHihJn7lYvX5U9W2yoIr1779+uW/53Nq+l1Rc+s/A4B1VUeRhPzV7QmGEJ
cBQFTr53U1lU5ZwFN1pJ6inFeEQNLR4l63NTE1wi9/rjAlbgLGmDqKVra8UwhMO9gAqMifcgFd4c08v/srf2bYdiExSx555618AC4RAOdLsVPz4qYYkzNd
+DCHQscfln4NS3y+A37wgIY2yQ5rWCS4oE9Oy9mc1OXhVXPWVvdwRMakioEXCMClBXyWvl0P2fZWNzioRzuLmiQtcSrPtwsuQgzAbu9VvQAoZOtLS1/jGC
/MkQXUF0gdrs0pdioAW3BrxvArvMI9m1n6VcNvYZN57FXE26TGq11vzC49QVnflVJUYnhxhKWltfwVPl/6OtsW//yFhSsfPly58u23sMbBHsSskXsFHujg
1HBihqHUe3wYj7uvb9ePArZ2BZ7lhYWlXyUAFx49fqa7VRm7DTZ/62CXLpDV1dXCHSQ0n0YmWeZs/6Cu3bdSfVgsDfe2W1yTMy9p357LK2TpA2cBHE016B
nJHPX53mkuKHz+l/HHL9VfBnuHe5zNwQn49tuFX5UlhMP5JzicH67AIrv1m69l5wLuFMrNBuN26QMTs/Px4L/iXrCHM5fgVH748Kc/LTz/9azx+cLMnG7W
xJTRwYsX9duDkupRLq0MZ09PqF2rMdbaUtPcYC8PhoXV+nA/FuV4MvPt818XABfWn7BIHJsKeV0cK4PCmqWjwd72Pg5f6TH2p/Hf4gNmqILWKzkosFDvBt
iBwIPX9P3OpYLzudu2/oSUsEJshea3C4evW1vaCSnVp3qnZzJn9A1CuzY8KkHI32VSAs/zHq//SsLApSsza/pweizYgo85rKtIpzS/+9IbW/BcquEEgt26
Ul2qH4KDstfTMgFwKv/061ji0gci8HpBa3t7uxVgyrYFCMKL9PDm8AiCevYJZsvzWcyd9bqD3bp0Z1aHqIjAvN5+C4ew49/n689/PQBEcQoWbA+26hQE1Y
dYhhawarpzjm8Outvdk8EdnFo2/puss2C32x0MSQKwtEcgPjos4Xjzw4NtQCN7snyBl+ySVOWjK+Q1/rLXrRcG+90taY9P9nFqySn3BzJKcNda3YHcs9Kg
J7/h68CjG+TJo69/QJdmAhrxsA+H88Y+fjBvewtbF45fdbdbPThlAMAxia9vAxagFtX73izeMy8KNEbOe93avrF9Q57KX0Ou9wq2NMLROVYkpOOjl7CsHs
lU1Qcve1hbOJk9tePtChdvht3W7ParQ0rNH2/DQnt7Q6l3Uzwe7s3CizhzYWnSAHyOpM/WEa1XRUyrhcNXsOquvCxXX6wWcGrS/O4pQSBEvgerOB6QFHwA
quo7ak7TcBvWfHH0bEzccbhCSjLtsrUHVwjbLq5ugXUobr3cD/a7p7MhFsAFnR90u68OjtGelAbv4Qa5cUA3SPH4aG8WAfz42697OBfwcO7vDTVB7hBvSv
S04cpDhx9uD3C018ZGRsP5watXt24S/oYAvz90b+phvPD3e1hu+dqOKG7k/gENNIqkiUs4IYLmc+BJnMdZLacqRMJKp1ZW6nLiV7Fw5AkPoJh6DvfeC/Zs
4dcAwAVc8TCKfqK6Q33PE/ulxNhAWPj++CO8znpRwubwvUAXPPp+MhNyvM0uKim6sAa2a1BPTWI8hM/vHa0SnR9iI/i/3dMYVZsMh/CU8Aop0oAE0bpZXI
01+oqHe3AK+Ncsxz+fwZtyWEwJ5h52mWgV5WhUWOb8ymAM5wP2uVtCnQta1OotIfaPSknxXfBlW+wrpq1lLgxi9wN1FqOGfISgJ26rzcCJKytdcVoWVLxZ
mZ9XRHpYqYfDnhL8coom0Uk7W4vH1KTxR8N/iskWMFlyqW+LIEIgLXsgwnEMoDVxWwt51T3vqKBKGMlvunoTIHER3Jhl2LUB5mCjD49RKIShQtxKfPxxCX
r5GsTtFZwEQQIohx6NZI8TFhRjFQeB+IrCmEsQGuFNWUwcTfxYWy3RS6xyvjdGbyLk8/UV1WC1elu8PlJZ63gKIEAQrODXNIKbnL1RE+JjU4CHcRUOo5Is
LeIqT+tNWWaoaq7xtydax0mJqWjcReEQ/LTHz782AAF/W6uFYiHdg6mqnkd6a4tkAlfmx7aFLTBvS2W4i6+D49U0oNXyX9R7F0HpWuesVVrN/Dy65bZeYw
FJn000geO9FlTCVpt2jBPGC+lJEgjp1eL210PgEgrzlmKpiMSbvSVaMQJXTvIj9Tn2sq5X+GJPdAsvUvNKVWmicGNsZeJy7N9Jthk4uh1u6alNdBRbYiwd
+xHryak6staZ3srk9z3jdk4UgI8ZPy6Mfjb1cVcPWXe1GHWFoQ3ZHHfr7NdpCFtxdbtXWM3/dvB7vcnPFljHEmQhZb2V20uveCvetflgnA/6fE10V6Iq9W
tvmLhBEpPl4T5lZ5kqPolnDunuxVJxBH/oWrC9F9Eqh14eGRQ8nd36ioz44OsHq9mR3cXIY2NPvpINhJ28vTqCP73KFwdKsg1HeK68EmMLEWsM9nJF7dt7
WmlqHxNHZfssXugkAbjOwkP16YqFUZtVXD30DukoFko0rHKs6/0Ibuc6xXpDhb9CDv7ghHiTVmrE2CZ9r6XO5vZr3dk2j2OOfxqbQtrFKjV+0hddrz66An
0l3RKnSsJe2DPDI7LfiIGAbUKnQ18zvbxD9YFi3Lr0Zl4fvRjRvtZ7hKyRr2PlcSdXi8VCLgRxlXty8DHZ+YOxRWm5l9rU772QR0LnB1LHGwzCGbokJglA
LpuO8q4H+ZFXj9SAS/K86yfjChGP2W1ifBUL3ePVUWMfbfPq0YT1zeF1t4qJ7FEmli2sto5o3B0BcOzHBw/6zvy8vEGOe/XVcS4BfL8bX6Ux6UqQvmYy5u
HFzb0IgCuzYjPPx26trFCfX7Fwa7AaDS3NUaHf/jqtj8/nwn35kXJsgfyXzLPhKleGY4PAhdAb6li3NCikv0XWsd06g+D51CQNYKuQ/Dh5m3uzHoe+K6cA
cEAApPpu8viObG9vsvp2O4wfxgDMTrXDkojcA7o2B+N+9lMKGyQAB1t5+Iu96AtRW/7UNVML94vjHzxJRTVEMD9D+BxDwBXVaHuUN/9T4bFIYyCefQUAfu
B8WBi9RGNt0mJBc2FOByDaeg3AUiHPMSrqy4dum68IwDU2jO1yoTiSi9G+KS36VBOyxg5K9dRIrVz8wTcbiEnq9oIBvF1I1E9GPA3YtaIOHLClOL+S91T0
5DRATHlnLpA0Aourg6/QH/7BxsNZOA2DcX4ib5OeQ2CkAZhdUiEzD7fwVbr/n8+EV8fb+ELyMMJCVvIjXZmOiAFYGP+qlOTUGSbFTw6Ay2y/kEZacSR4i+
ab1GUQNRaAg1EAFkZuWEzmeJMUK34a8noxVb9UHn/2jZML+kkApuYhjFhUXWW5ALXlT2VgwjeF4qkA1BL2nwNAednm+SfyN4dfYwwSaSrkRrjZqAIBiP1I
98dZQD6vYsBTLyt1PQdf7INODoCPwHqMmnoZkCe8G9kMgQhc2R83H2KTAJiCWv72luqtSQpnz0BoVEql5sf4jnVVpB4DQKpCrBRHD2MxG5QUSvts7ZLThE
sB9Vble5/JhdbnsSEwZ5OUC1qPQ78c90R7QvXg8q+Yu8s83Cokg/kxHw/zgbCQAzbeBUU5u3raDcsLAOV5/PLjODkAPmbDwmg0kfFFlWuDAER95CdjgfDn
eimBv0JxxPhJIJe2WTjJLNJRIWuw1b9Tu4gXCCZxvXG+gHdH5yjGhH5xgbElvIeXezi/5bxeKBU/9eDRHMc3mMFhF0rre1wCRn8X+A6Xr0L4IQzqpSwAi6
nPGeNvvtQVp2RBB6U79VIyiihkb6xoZnlpW3hfDYDPmKpBpACY8VLkfHJ00Oooj/VkXDonWIlMYDHnftX+2wpcOZMD4BJem+kbrjAaM0j81UtDPq7EtcDZ
VElKoJ0WM+CGoUDhZQPwSignuH8CgOSAjmkInGFsF5MXqXRVrgHEFX4NADI7NUY8x4Gif2iRpd3xiSIcMTCERZRGasNpM1OQmt9fPvRiYgB8/gyb3pMXRC
GZctJXhYIfdWGN1X19xFgPEFjKxk+ZB0mZryc4wXOBh8fZ1FEUA8ZbR/Bbue2xcQBcZowP6oTA8QAsSKmb+utLB+CHsPdJAMprcmX+xMvlCuzA5g3AdNRj
lmVuDQK3aCW4vPE6iSigVhp1rrOjQmGROCqji1MdxwEQe6tOVogXkpdUTcaWJdxN9nUtYCppGDueCow0XQ/2bepVDzUlxyYAwQJ6cIRLpULuhNXIDs2j2N
jkAPics63RzFHipSvrVyrN3w4EGzswdSHknO3v0lem/aB0XgbeRgkCycseFAQWsHgaANVHg306CYSXawE/hDxgvV1sEkgAMGeFK7TCywfgQhiUCuOTJjKA
wdthiOOOg2C8AvEaqyE5WFWVxiRjErv57KsBcHPc6Y04yJi5qK9MUTtjcJomOES+Lc563TtZZkXqu6Eb6E10d1UhZTTOjvRg8IfOv4IVwAL4KdObaw4Y8Z
NhfRSAcSQMcTAt4LLLZNc4Hc4xECR+NixzqFbJ2FKuY2bXPNHr7q7EOj/Z9CIZ+NKBJ75CEmYpDAqF0zK8ci+nqLGzVjtlWN4CasFyxlsHOuLNf2eYFd6F
tf70FQHYjeLeQpZ6XFKz6YZg+4QA9AWchXNjebo7qA3LBT8ppdAXJT+lHaoPsCV0clyu53NsazUn0xUjHq6Qg5dSqDw4Jbu+9IzZTs1j3iwe0FKiSaAQJV
9wASuvUDH7so/nNbAOqwnNuXitUnMBnyFphuB4w/xVQpgbOKi638IVFkYRqLZo6yX2yF8+2ed+KIVcctzGkl7l8DZcMV6AU5hP+4TLUpcep0PW4/NcSjXL
yLmtXVzr16sDPmad/ZP5lVL2qevBkFuDl69R8RXuVWwyX7tyqg8Pq4bdD14NS6U//zmhkEbfC38xP+gJj09QoZHu9UHs7I8sZGXqBK0CTtnOn4UQf6efGU
6vREv/8kCe0MQ3lSuAQw4eXnDpHqgU3EnIDKWPJd4xUsAc53MyPmY+2dKm2iEvmB2Apf9z4mzqXdoazOIJ/xpMGJqf/WpLieKP7uQQu+HhLJJkEfvp1DO0
8AQ3E780aL0aruSfb9TvONNuTrIQbzuc97oHw/mVevLzYff7oNt6TWLguGcY835KFWXhEQtDFsDFA6s+2IrCKTwhK/PDAZ2RwJ5skXeOdThvnWRfMv7Ird
2T7dck/6HGl8ycvgAS5mB01XioJ7K1IpdAJ3xrePCq9R5PsP0VJnWB9erwoAsvNbtKuVG0T2qVO+NXubApV4ji30GrO7izBfuuRvAOpwavtnGH+NjxnRf8
rKELBadxMEwfxvktOoukiW3LRW5+0kCjribdqLSbs68GU3qttFj4jnDTiM8b2nNxALz7SHlmnhf0Wtvd7it4uigugmojeFXSzGP2eGHhs3YEBwpyuWjheb
3WLHzL7o3tWf39KIoM1ydrG0K7xkOP91ovu3sDfPZedV/Cj3xPMjwBLeDRo5/Xlz/d5baw/OjxE9g1ABmnl/K6J5/AoxnXHv7JVxlUMsM4uI8ct+nGq9u0
zNukAkOrVAftyZPHjz6xyqXlRztrtMJAiu++D4LXr18H7+UC8RsFPPw6gx3hlrE3HFgInsbZFkoybbdme7RE3Em5lWs7n7OTtNTlddpM2jOBa5Xb+ZoWy+
Q+n2U3J9kNsfwMTRx+Rq5E2EmICNXcbdoLMPbrX9Cf+XwJvmNIqw7S3xFnLGEUOWndH/DORn+c+ony+uCPvqjB9P5PcgE4cB2/qefRhE9bfTf26Gs0yy3N
gX/pOHA806tknIa+4z59turc8+XH8u/J+XkBzvemoSd4wnkYrn0tUQoUFuG1jQ2nJpdJL169evnu2Reenufra7RUNTc2iNaKI7DImm6eofl4sh3xy09oGw
NbfcqaWi6t99mjH7/8Ay78/Ex+x1ot+pa48jO8wM86m+u0AvhxjnxSP5BvLn/xChaersE5jLZKH1L8do+Xv1a3+Ic1CbeaWqIafqc+15MvU00EQ/hMwlcC
OFD7zby1rym/uLS86clZHtFpxFXqz7Z5lpe/sL6mbEp8wvVqz7jYqYkvO5LkjZ9nPz1aP/thA1/uSeZbPnv86ML2dmH58RP6IYQaNAc0l/jx+vJZf+LSwv
LO4ydPIiVXztfO8d0m83x7ZXPNi5YZWfo1eK9LZ1ri+uMnazx61tZmPix/dSHwpeWdTS/jysBn2zzPy3++sLy+SSv1mKf2E7/jWRd7IcrYDx/Cp1x/urPz
dH15eSLtQs+X7t5fVs/Cw4vWOX8OkPkwox6SNF9aOv/3hAfC3z/hN/tV6EbDx1l+OjOzSc/ODq7zXMukFarn16OMjatc/qCeK1euTeTlw1IXrqE0/Z/+hM
rp5/mOU3d/f35/fn++2vM7AH9/fn9+B+Dvz+/P7wD8/fn9+f35HYC/P78/vwPw9+f35/fndwD+/vz+/A7A35/fn9+f3wH4+/P78zsAf39+f35/fgfg78/v
z+8A/P35/fkNPw/hWVjQ/GJ4fgfg78/vz2U8SwvL6zubqnnD81SX5hq25y78/wMA6eaB5/7vR+E39tz/cXn90c8/P/7pp59/frS+/ONvbweXlnfWZBuyoK
599Qj9X4DDneWFpf9LAXgftu/xkydeqlXw8T++cmvc789n3JnLTzfXnumTmjq7zx7/vL7w8Ldxf6w/5nIN1I7sOH6/77puv+/7jmPbPBIGWNtcfvh/GQDv
//jop+jWUfIA1Cspf2Nz/f8ec3h/eXkdnn/gsw5Ozf2Hv+31LKxv6pZdz4vUDmKlA3loN9cXln7Vq1jeXFMf1XZ8t2niU5YP/IL+s+n6joJhyDcvxy5cBg
CXHz1R2IO1b/TdpkXLNSyr6aolIwp//o1jEAKLkdZ91XG+tvn0t2nmwWOTLeVeMHv13XS5HB1Z+XyMjyzzAIS/0rvm4fqaVDbggD1L4s3Ax4wf/R9t19H3
ypMfl37zAFTXpxBesPFuOrNu/UvLdWwyhT/9+BvF3lMVWYiEmAUJWoSxFsLaox8XflvGcGHHw4uT195d//77e98/QODhnlnyMaQRARj2EYWoNoaG8Nfnkv
xMYR6z/SZ9fjNx/PR/GRqB9L+u08E9g817dP83DMCl5U0e0rkMrl59ANundi6FQf0blm/j8T1NifJXiz4V1qOi2obfbzbb7bZanmWRjScjARgM1zavLP1G
lrW0vIboC65Of3/vXoQ92rgECK3IgrgbuIFo7p/+mrZw4R/SKdHoy5q95H/pL8DfJDuItuOnhd8oABd26NTBKq5O4w5GWyYXrT0ZI/5dafv55m8Jggsoo4
YXR015aNEmqi1ViwQYdsgmorTab8L4gUljwZupe7h3ZubeNPQiI0NIv/lxw+bchkv3V7OFUlKX8Y2PZmJn1NmDz96EIKjZTKwhsXltX0HwQqUVLwqApAyN
4UPw7vtf7pW150mbhqvGpymDwcRl2nZtiiV+IxBcWn/i0XSPq+CigYdGSzHUWY1vVXnnGFYfMGjbHbCDy79yV/TKGsDPu3r93i+IPoU1uENQ/1I9tl3DXI
b0Xgy5i/CvptOpOQDBX4UjQ/AD1/Ndwnc2MtkWmRbEnOgGhId0RCM4mngcCYJPf2MAVPqgDByYe3ILpUNG6/bSUrC1DddKBBVNWHMY7vwGHDUyEoC+d+Si
RTdoIj6Sv5OwHhjsVp0qhIa/Zk97AeHHr37/yy8KfbBvMsaDyxGVP6tVqW1LaTXYPn20ZfxUtX3f/hVAcOEJBeC16QcPEratqaEnxWal+KtO6GKCtCm97A
iCwqNJIMu/IQBi8MAdHOvwDo6mSeePYgQurxrf76P5a7p9f8MJKEZ0cBfbctV9Sl7sPPwNwA+C26l7kZFIujHSx47su/7zcrnt2/YG+NrhqcNpLvK59p9/
OfV6W0f4od/yfVkH5zp5n7hY4DZp9jdqAaLQVqdWH9qq3e93xs51uaxbhG742vV7DyKn2fIJe9yGA2hlwj9DW0XPdqQllObQ8LnA0Szh5sPfCAAJflf7AW
zivV8eyOgBVu5BmJRMAasICW1e3wkwQezq37eqHPy0r7t/n9reTfLRZISU8G3wVPobG1JV20cXzUqHhBgT+h0brCA4Nl/DRiz9dXd3d+raqW4bv4q+p0n2
Ap0w3DjDGMlgkJlA64g30UYz8Qd9bvf98OLMxqcfNRvnqoQf7UyfkkROvy3vRiNxNUYLk7YeD6MRhROWo/zQH38TANz0BNuYrgn2BjZRZl5w5dxpmnEByU
gvW2207RvK9vshXjqbD3/N8ONvyEjo2B6R58iZAyKlxRw4MraIn7LlYAzFJjnb8LOfv07RszTOboBD8ube32XU3kcv5up04rhmolu1hxDdwsLtvqHrg2XT
Zg4EUHzt69R212V8c/Xe3/QnajqerEPoM2iMPuqjt/tV+lpLIxRDQfJDHz/81QPwPgR/9vRHLuypX3753rTQ7HPBaq6Zm+2N105fyLiGYJMzG5yYhV87/P
TtiglcSTQAsxc/4NQE8vdp62MIQqTLsdY0d9mFz293CX+7f8m1jjNwympT/+sXtH7WBhxDDKDKme2yMNXZjLeRUGm5VYbbF0GwH9rNr2QEF+QUgNr398px
MkVwP2Gjy+VxACQMWn4g4C/g8ZW/7+NQSMbC5V85AHdgE9yyI9g7vERxXxxMxMjchIyLzPH3j9EPGO+rt1DFFYe/woz9DDqfSfiRhYcrE+J3K2kXlMNpNf
0aRR6VZtIOupxV0W7MXO4lc00B8I95BzfA4OHvf8fYDzeOvyk/wPJR+p40fLDwwknYEeV/g10HCCpWF5h5m/kWXKI7X8f8he/uPVB19T5eKykT0O5v9KOi
YA4E4TfdGmKWlmzQaoSNkfvOrxmAC7BQp9zkIrj+93to/tB7hju0rDPz4Gn6xjgA0v7Cu7ItuYU+HOmQbZ52m3+NDMYcGPTZ7+/d+/6B9JapeBls6CDJsu
JyZyLsa/t2yMitMaM/cgCTaDYuNeOrAfjXnNoDF6J273+h90n35rty2vjpjUMAMr88WjmD6JbjBazXvQF7CYtcu9RI4v5jGotqX0cDQH40fKaNNnnRuorp
Y5jgKtZLrjeGe2SB18r7hmbHwEowsTjpwH2CAHwKK22W+4xtfA/WwcL8kUxCxb4L7JzcH2PMAycVNlcG+C7cp/w0N/Q/r106/p5iaeX6L7q20vZxjPabaR
0kKWuRDO4jDFp+B0wnhMLarSmDEXQqGPJfphH86+4YAD6Fm+WdNH8u3KHv0Pc0Rz00CUDRz3XfynBMhWPps95n3IJF8ksMBJc9iLo9hskX2gI3ENIqJz+m
ra8QSUBLuteW1Y4y16YFu2O7OmkIJ9PBC/P+rxOASxAZ2WYZbN67e3CJWrSL0+inRUt3kRjjjwAw4wRAeOSozEzI/dMCwX/942VnEOc4o+SS9D4TUVKc6X
bd/MACFwRxEhiZZhzvO6xDacZLTPhek0mYv45GDyKYAvzBsmzhXR0N/aJ1KADm5kUxuhVwg6pLBnbcXbzEgsTDTQirW3gEyxSa4pW/YZYzgQFaQPTVzAyt
J05mq8AW3Wr4QksZQTeEqGHS9+WkALi0BkstGzbj07/cK8PHd5h39ft75dTCuV73yNam/suHi5NejMV5pTM+jr/+H5eLvysduFOm0PyZbdobITauRzV4Wq
GDK8yNKuSeUjLOsSK7CCcU3dDLHBQvTeBfs9cnA/cTk5940W+U//YgB37yfzHEHwGg/l9KWHhgBA3paDc5BIL2ZQWCy3DAWi3Bp+5RsGrBUmpW2k+mf7kI
wI4Z19sTAHRszKTFvDvXFjovUYaQ1gajONHE0tTE8Of1AX+i9j3somVAIOiUZSU3cT2iCxqMeKCjlQnYNlfaTLKBY1IxSw8eXCpf5gNs78a9e/dkbg2Tux
vKwY6KYrSztmHmAlDer5bvRTuKe8pZFd3Qny85CvxrdvsEZl/Actkpv2UcAGF/LB0xRauPwgg4s65CIKyvsggInLmEle3AlnRbIvie8g9Gkz6GcjHjlgfc
CEqKWTkW0LBlDcnXq7boonX0IbXFpBE4GQA+XMPwD6662XuEP595H+8p85cAINoHZo3YvtHNhmPgq7tqPAL/8re//eclup+Yogfv+t73aP7gXgQ7obgiRk
RespD8xPMAmPzvDS/KNMFfwVu1w9hPl7aSP+5mAYj4e4P4s8DL6j+Q3ILcSySKoJoRAONTHLOAMJCPC0pUEdy88HWBEee398EEPKCrzkfc5O2DpWDmplFJ
X+VLkhpcorFRxGBKuWQageGPvy4ALnCFv41fsPpgOaL2QB3OmDIhqym4biN9akcifSQu1/DtmfgaO+PiwD/+7W//n0sN/4Lr96T72abs7r17CTuh0MQFXa
15Lrbp2KoQVYa/H/rRkbBFp4LptUtLFoITuvvfmez1O7w4YeO47FwxR59oOXh6vZEI0Ei2eGJ+qaLJJfDLxiUgEIPYW4HYwOwnJuCF18+PxI22uUFBoBF3
4eqvg/2zXcvqV61kWAj2gLkqjugI2+cTrI9NAoALAeNtOEiEP/Jirt5L4C+GWhNpIhsq1WvkFuWj33EAgRbFkrTgnNTTf/ztwd++vUT81bD4UG63TUoS3s
uzE/JqbeYmeV2GRjOuAjrqsgGPjXUwELwYBC798a9//c/0DOWlqRQAr0n8mRZsXE2av4TJy5YbDBMOqeBGpqU8c8zLsChHWUXYdULgxcaB65hEmoOTJ/EH
lspKZnHT/DkdKsRuszyjPiaQyrIjIpEaNTBtI7OheMdizDCxTMzURPDXIc+E7B/6HO+wezpTWjGUgRA1c0wTZLLWBEZEIRDsKi54bTSW+duDB3+7pDzo0h
oH71q5n5ilePDLvXJOrsWQ8VFumaUqPGFHRJF2VVbM6K+iX4MJ7gsIaZf+DyU9r2Uzof+d2D4hJP642HjwtwT+XMe27f7ILuEm2gk9gzHdrbbQJgbiiEbj
gkvyyx4LdmuEP4QPF07KMJvpTxoFgZnIh3M3eyIV+c6V1TH6IkBgmGsSvg4Al+Byw/hO1H75+/eU15umKvVocEe+t+DZrUrgLuWROhAHIgLBhQEEzo16oA
DAB5diAhc6IXvzyz100trg2wTT9+LoL6dG5qcCe90Gg+wMqxyfhgptqeRSYhxYvZCC4H9P7dKTRuBfYgu4FDCJvyYXV//2II4bKMuLhiKbI5O3aCauhSOK
VPsMAlXg5Av77duOuMBqxALgb2of/U/8iZh7LWfuhrQ/bctgKAPAhmMZ41iimFZUKcKQOc7Ersup8xsHxj+iWaAsNuDPu54o/qX+ZaGBEJ4VOywqjWa4vt
+3Rg6tLRoYAzfAQ3PCbJZi6cHf8PmPS8Ef0/izwP2k+HbEc6b/N/voZDt5iV4nqoFG9TQW2QjKhV4IAv/PrnrSN9V//zGRuniDgQMsDIt/OrGJRkRg8x+4
25lEPldLTC3PpQy3q5055Y879N9tuJ2rbyfpt+UlIaauihrRH/Guc8un2GadjaiM42PlItCSCCQHNqSQ4VcBQAiOwo/IeQju/QL27yPzylnrEK3JkgUYzY
XRZsLsB1KwyspsqoHVCAoD6XSuZw0gIfDindAlm0f4A9BsZMyfMneKdI8AtOVvphaDx5ZnTgGc+ao67xECJ+yFPp/SAJxKIfC5/q8rnpilwJ2zj9L+RfYL
ycgmlk3sVB3bYhkAyvw2WEv4xzWS/T02OANW5MUgAi8o0bTGvN2rwv7+gTpkzST+tE5I6tXLINDIIYTkELVU/oUQKOHLMW326NcAwBnO+ibcOd71X743zY
/S/o3hmcFeeJoDlHgcLfcKDriRogxZHrfk9jmYqb+frkGo54+XhD8kcfoizi/lEHnwE8Niggy7xyBWlsf65XQvHW6prTWAWOggAiedK/yrRuDU/36eazqE
fe8XugCmqaapD60fMcrK7cgxk38GplH0U7cL8p+477oAsWayQA/ro4K9BRcTBwROympkn8eM3ToR/PsHmLVzmSoi66V89B3HdxWnU32yNgWBOQDUTappU6
iEDaLIsiqwdDQRUto5AfiBI/EDtw/zL22PnYI/XFxHcWESv4kpYdvxHdvDfc3YCIaJGANvHIezZ/HP/U9l/+C5/h8XGgdi/jPGH+aXyuPJ5NI/46MALPtM
b17SLWrbiEBLVqDgiNoT58Rci03gf+csjsOx/XsZM13T98qJSMngPioxRdF5EoBNiBfS1gH5Wm1Tdiol0odtdAhcsoCwvGoFLpjwIhIxj8CL3mXs+gMjwl
/yw0llSLtZTtpsCgKbuZQQ07Wyvy/tRxsQKKOItqRPhF8dgAs2xOgGuPhXicUUiOlT8KciIZFiiuALs126dLAhsJkJmn3hGm2IBqWDpm3+0r/G+CMjeIGs
bDDxsxH+vGlNAzXHAFAVyUZzu76dU1ZDL61GnVoYJ9mVrJ2fRNk9RuC1nNo1myL8iXcJTg/eF9pNMQ0jncJIEQdV14OgdBIRfVCcIoFAV3AkpVhtOPGVyk
QLaHEBwmP7fw/YO+1/pnjiTa4kveH3y4mP7VNFLBeAG6Gbd8W6zTYyy13twqJB//lrA3AOC4BmnxKgmAh9l0NiSsfq8C5SyzZrYBkik+hXM9Q8gJ4lCTEO
modlWdl6kMYf5mL+eO1iaGkfOhDdyvjPETK/hPcnz90jXYdoGuOIzNniC3J+HCy6UCrUwTjp2YRX8BdsfqDn/2T/6Kkn3v2d6u9X7z3I4c4ZSX2irMttJr
qOmjmVJNo/uEFt2WLQZJ0GntmJh4ELnHlTb8SbB6r+0E/GPE1kRtjYI+3TnkUmDauy3M1r6XBUhT4V5JtkWS3LlcULy6wICgN//LoAnKELwWLe9xDHw7ve
0PWHUxDotpMhvWEl2dng3hhpcTGrKUNlh3UoiIfz9K/Xr1/P4O8B/Pf1C4kFr9mwuF/uldtttH8Kf8ix581cAMr0Wj+HX2CMgSC6NdrfBicUHKZJ61Qs/e
V/SwhO/edIAFj7+/do2Wt/K2dhlY7GzZGabuSnGH4/l0mhurKQVEgWvsIqbxvgxkzaCV2DAPAWs79XiVffTH5SwF+1qaY/0DyI6A9938330bDGmaUxyaQw
IrAibEwrtY0O1eOffVUAwt2zAc6YLa6i+ovL7Af3vj8NfxnitfR1bDNVsEgfTqvZrMGVhknysIqH8+ndb//yH38bMYB/+4+/PL+YBIwnsLvDbBvK/zRkBO
DJ8liuiWde0xivOZKsTKlMhXJr4AbrYJx0AUox17AFAhC4lC4gCbhcDLjVA5n+zCWwjrIlUmsY8/uxC2NxlRq1eNh42+hMrIIdMWBYa4p7U1iAB/Q4qdY/
8Ef8MaTc/C2Cmz5Tn1d/SRUOLaMKHpvM9YQTcULPA8A5qsArBxRedFke0NMrKlGhScYXKmZIbTi2t1pNUnTHpCLrWNIE+rasJF37jyz8LioGnOPiDdk/AB
bEt7pM3e4AAp38dLXv+00zrnEauXQoXZoylOWzdHm4WpmMY5NjBv86lcnDzCgHlIuPZSMncXs6XWlMU0v6d4kUDTaDWpV9Vm00KhNO9D4MGd9tYQCIkibC
ThrncjNqa0i0bZz6RJQzYyTNxGSbKrwurE5bFLPb5w/ZzwHAD5h0NkzOrv9yz7SqEEfkJAhzOCGqBpizfZp0oGZ9RI9DjUlVP6Kk/eX69WQO5qISMB9sNi
fxB6/9apRfsqQN7OcSWUeNh5nvBcROnK/YJtIJrfBJG4kIg/+dzMNcAwcUdbMqYqNsZbsytZYYuG3lT0LNGo/KhBOKttB/27Anu7pHjJ2csNo9VYS1khm8
MnKpjPE2L2PDTcOUueq0pAFVqpmmBIHpEwyD2nZbMrTWvhoAF2xwQNvgN/WxAxfiiO8T9k/r1+WJbuT+rlZHReyFkWK4Gl8KFgK7Osk/k1m053+MEPjgwl
KgC7bnTcEZhQDQxvi2HDtWbVs1lKUKuMaII+c2y3kvIAYgTTdxsGBNzHPMhDoXVS5L1N/Jf/G+v4egt82R7IkUlLBxfDN3mmXj1P5Npbg1Ru4PluV58k2h
CXw7gTObNICM7U8F7Dq9ZVv0yyluI3PyQtPcy5JOJeDPXnRd6qW3MjRC8vZMSeeyDQAgRQzVc5vAswNwhnPiRSAFxlxk7HqiAEEraBr5Jn/ET5EDM2DHnS
ACnpcUsMcXCc5BNXnjRAj8ywVWIMQ7wh++8wfx8lSHCreSyXkjzx6WN3jWsqQzGE1uy6DSld+VYSYUwH3xGg5XwKZj6tpmVqrIZyldFJdrfgRzxnkr6nji
uAFuA1DLGSV+mU0DJ1S66yaZwOokSxFgACkDKkNoRzMcpAF07U/Ry1KNHCRnIBXqnXSCRhYNNXXeCNAJhVtZSvo8+0oAvGYzuLbBOZ7WDmg5cciaNNyJyG
XmuJUn9YtwaALXk7p50NtvvU7K23LLaIaskzCB2I1Ez79e2BF9aovaPRkACq+cqq/gp640UznD/JvGFTpdmiSsRT5qk0teM4aBlg4skHMQXnhzIATw98gA
KpEeeWrLFWmLKejx9l92t3s4omwUgfGrcEK9b1U12sRvJAFIGQxLMTCrDSwGTswELjD2ZooFlPprSqpfogHedbV3nJ+GiKqappKlxYQDl7PkbDdSEsH8G2
P9iEBpyKAd8wJkAn/8OgCUBrAJ7vcv32MGNCpAKJ5xdHnmRoHJd2LJqRFaSLrXwmc2ZQGR3ADBQ7XqcKFJ2dckAC/MAV2Ce+86ONd41Yl3qFFkpnIqcniA
m6KKjK6Ti7BvjisDkmvD2uSEyt4rCwu8F0FJG7k/OXv3C5ypTgd8R8e24ni0iR/EFszrHhderBaKW9tCdMxxRsTlQnivez3wXZgIXdlA3hxhXjqKXxP6lb
fO5CQdNhmfarF3ZYscUDfboREhLS8NYaQ6JSrElxG2HBSESllOFP26YSzhRH+3AiEDHAurw85fijgrABds6o9yMEuPvbjT38f4Q2lCxmuOU+Nx5+YYH8Do
S01p9QQt/aQB6Etx4mo14XT/68UawB3Mu+BsizagI57wlKHIU2f7KVWXPhNSVmsUgCZViZGOIWsRlFuroAnEPMwFSxVuQugAW9Znbrm8gXLKUVnSa1LRq3
e4ulooFIvFQuEg7v9LN7mYhuuJYO+4AF843Eb70TeMvudkdKYxiSjp0eAlkgmckP7Gcsiu/r8eGEDKRdgRu3+k+yinNyD2SAzFryPtF0MNHXXtSDYEENhx
kjhGcjI2pqFcw7lN4NQ5DGDb/EhZQrjhNu4lKrnYd6vuD9fuWGOTv1LVViR9zQiA+yn82RUSF+HVaqXDHidN4IVFgA87jH9PDLQG4+UHWf9R3+26vfGUxL
YQsV50aqwJl30FqhaBpNC2KfsGqheXh4lKuFd/KVsGhqBNCrh9JYbpwm0P+GsVC8UCAbBUKhwJ5o/WAmWX/3YdcErPMECXJ0DymeHGfOgNF3+ELWXuGG9U
GtVJ8e02sQlQGkDEhJl1MMeOQhgJGvA/Ao0/S/kCPEKglWkqgIvEaE8mCjwjAJfmqAYPBpACea/8IMmNF/wj1fJosEUzN0TScWLm6WkAzqV+22m0TaPKAY
BO2gRenC4aGMB3xEDDRp0HZir/F1lDbNo5HYCW0vnxVT4/8Y14LEyClDyAQBsJI2QCO4xNwAQuXfvLX/IpejvM+/57Cw0g3WxxdxxJEAmxXSiUigp/YAT3
IlWiJI8CLeVegYCKX1qo9yjqsFCQTHmhZauq5Erkbzis8hZN4NykIsATFjxA7aAN4Z9KPMpyBkbKnlivjJFGORxVnx2tSpgEd0yEsnPXAs8IwKecty1Mgf
5CgfzVBAMNr7l2Vo4jxxX301OE5LOvAZjGpr0I15sPAKSzuRObwAvzQBeQA/pAlgacci5PB8DlyhzKaQC08IB7NJSuaaXkY2RtVycNmrTdGAWG0gSe3037
o9Tg/d+jPNklLt6QCAU3NWFS1ZkN6nnslYol8j6L9BQKPRE1kUUAxOtngMBTT7FQAgSS/eO+KoWjLjZeMi4qkZDHYDdQIIZNIgrciSNAy+On8o6iafY5Qr
QqoOfJ5gipMawrTWkA4p81wHOB2L0dcqwaPbp0AC7pGuC7Xx5Yps1TDGxfOvwpPclsnZaaq0bx50UhYOq3YVctpKPxDp3NqGv1P65fmAc6hxEgTRH3wJyb
OaUytQb3VABSToJ17FDNAw46jpXgVlSj6qGpFTiMqqhWqpNoi5D4Qw7o1NR/p3NVT5k3RSTQvvS56DJgVYlALrx6oUSWD+GF/xSGKpg3k9VOX9ygr4sRWP
eEqG3UNLFALpL+i1MilIrxlQnRYR6GonXikQGEk+ib4wuufZyO4wWOa4zfrKiIkZis45LEpDViAOn6tOQCcavCSwfgDPc+4lv1vv8FeeIbqVKtnRS/TjHM
1O83fXvU+UwDsJf+fb6Idr/T4d9QhkKbwD9emCoacmCkA+qIjfLIalQx0JHZidMAiPVLx5RVFooGlW9GXJpqqlkZSxFtDMLgVkUTeE6a4ZLGHwJwd+qvf0
yYwTU2e89sWzZXnHfykz2Z6nOEOEBcJQAIz6xwk+KD9L+sF32d9kIHmrlEXXMS1zbx0Agh6E8A/hoT6Y1fZ+z2VXEVZdgNzvMS0ZHwgIC7Dwca2+7Y7bKZ
Oyogo3o5rNHv6spFqkrE/UsGIBjAmokO2AZGgDWmfWe5tKqbIUCqAZY4Lc+2XZzVJoQQeQCMcjBB5g9IPwcAiD6oHe3etYtShHk4x9n1e/jqXcbzr00LI6
hILnI8/oTnqtSU23eEZ+nRLC5PC6tYZAIxuY3NnnjNsHMWGnbjBxGY0CZcgNV9j3WsDT2GBOvuHquV0asSLYWrooQW/ftAoSoxiMURWwXtqqqvK4GvKoK+
sh9cJbBpeUoSnXxQvzoJqsEaC04Cj4ZAILzz6yQU6sC1h74MDYE1yrmFafh8OWGjSW5JTv3QNAJPBfK4VT9fMgCv2OwjMQem/g47BvuWcs+sbL7e6m/YXN
k8TLwLNu7p5RchlNKf3bE7lW+SxfiLYoHCAgNtAP0cnqTsNWMiR38pq4VGRTFL5d18ITUb6Hz6me+qqvGYDZBR4I8TBGDS/kHwBKtDedpmPNEe1UnNMqlL
HBYi8EUArHs83ccCBnA7ChHV15VK4KuKQOd1MfS15TQos1yTPpsFiCRxinP7oJiCuQ1nzwK7yj1r3MxJR0TicxBoR2KQI21kshyUpaeh62xY+SNqfKltVw
WLEF4yAGd4QGl0TMGU/YQEjmFmqS5NxS8bD7pcALJRAJpGteOE33zzDdw4evcuygOd6bB3f5OFcW/kPlGJaZINM43TZq3BPcncZHMObBt1iOfwtGUpWRoL
pGRXzlstew5Wb1eFgP+Z7kPi7A2yl7mdsml+G/BnctFdjbAXAbBYmGVWppGMHRdyvq4lpKwBGEgPRxMphxXiKV+JPVV8KnSe1wfdYexkHwwBeu3CKY8BYK
K9gaIgPxzRJFJtgG4eVQJdTSN/1gdpVRF//lw+6FkA+FCmYPrszf8CDzTgZWP05qApwO4GCr3kwG+cDzomBJQvsex0GmEVTGCHsYtlai3YIScDiG6hEgnJ
bILEnyuTa5kgIXmvOpn2OEp2G/kVKlcVBW0khGJ6+3yr/M8pNYvz2vMRFszU93h2+uWsaB/AyjssFEaRVbiFgj3JN8C3X4zir1g40sM721zw+GoGZHNlOa
qNilM9fx6Us/0Tj5cxbLZZM1+gABskEulbSm1yObYi84UBs/IlC5zs944HnTRlMfebc/mgZwHgNQxYUeXj+t/L5kfUW3f8uMqlMr5tSXFBoHlBkCk5BI7j
2KfkYIJcAFY6bgd80G+qEymSnVZk6aCJaFuyvFvuI6s1VSNSxTP0qzmOvc1BIH1V4FmZDlXq2c6tEZOik6VmA1cm0Rv/l79OTf31L6Newgx6oBhBGDEAde
nMhgiwkIPAwk1sRE11Hm+tJr4gsoClgCn9b9cxEvSDMh1YNCncrzgOP2+OaZmxq+8YpWCsqKFjBCW2cLIkXJQgGNksKmOMVA/lRVPLb4dsSp5lRWAe9Nml
AnCHykcWRzYveqAPILSJxpASqR9Mn4IUEatbvZS941LUbhSB78eFgBKAfset8gr5oI8uFIAdMBEPLBICwWF/XKqWptqMuAxoKbmG3CsrXwHHGemms3jmrk
3pWZBmqtTwO9e2foJEcfUewl0L5ccuFlqMo9VcC3gsE4Kxls/rxBfgPyoWXO3qxp30YS67Mp9BhQhSmTyvB+r9v/tsGntVfNX2NzoytJ+onsTTkfhIKyeE
pvaYTuRy385XBDA4VQmVD3qpAJzDHCgczllk8wb8uukhl0nrFFnEL5OGTtbV91tBwuMUPJKeH5sEHYEmZkHLPnch5v0Gbxx+sR4oq90zLKr2fFQyL0hmiV
wZnI4USnoLsgjR1xqjAdcc7SZvRGMLEskdU6XibDWxzJFpmAtpzI080I1yojFDe8hevVDItYHveSIjb5lhVxcJVSJGA3BI0suGzvZGJ5/OOMlsVSqptpYz
50CnOC+bSLPxqPVhRHvAUO5GuvcPs/css19w8WzkdBvH0r5mjkyTj35gm7iD50iYnQGASzbcIBbYXrxHwRCXPypzYDevE79Mg43PRhZNJKvqcm+kTHZuDm
YkBOSWAqDL7G+qF+2D7nTYuwcU24W2LBioT+HKBlq/wx0I5qt6xh/i0c1pB7QoVzXiGtmJL854PVTebcu+XPRBL6Qn4koY/J1mOLpmdj4seaCZFEyhcLS3
Bf/qsbgijdfvsFCMQ7/E36kHQooUGgmdW/wZASNf3RF4uzjnVGdaYOLNO1YrgwFsgj3AxhLbHfUSeU7zrRVLV0S0cjfWrkhJGpSxeG25vuO4ef6N7BWtni
dhdgYAXuHeNFmH7x9gWs+lE4igA+/eThYZgjxeC/y5FSnPj8nBBGMAGLoWErKr1fBCO1Zt7j0oW+QS0gWKY0rkFYOjl+HNfzTLcI8nrknXYyPZbV2sHa3h
pjXRUyML8OxaRkMoH/QipNyXZsB1wWCUZ5vbiZQ2iLmdMvgrtcB92SsUtlmiJG06XqlQvNXb3hpFYCum59G3/76sO8lltxJFuOdtjF/WVXj0QPtUbcA4KD
01dEPPU8kg0HREP9W/D1vVH21XjdRR8NSOOqJY/Se1LvutfXYf9AwAnOFBGa1DgKOgVEM1BGejOZW5vNYGIZjuZLXFmBzMSAhIFxYBkDMEIL/Ifjn0QB/E
BokOja0g6CMA4VZ00mqKiMDmyFwrTG2n6QiRnRsDQOwaaFPxoyLzoMsX4IHa7BZyDJg9OqMKnJLjgi6/K/t3Q3ieEDdf3GDtpBmfLRRnMbAYFtLwKxa6Ik
gB8N49Q9mdDXx7UYR7rkLEI+adBBACSulYTLkyyTSyYvK1GYhmXmsSJT3TTaluSs6XnE7dpiq/cdAcbUZz2CLs1jmDwLMAMMTgwUU2E0byis3knFLVC0YC
OnXff24ISD0D5Q0AoE0AvNAg8Kn2QJUmKd37kr9DZXRTt9eYSQlolu18xJORq4hmuCl6Rep0cA8bgK0oTpr8PXNtJqQMk6tn/SQPpi96OqKj/4N/juTN01
vdY0meFt97sSdoEEapkMRfAeloXkotZ+rvpiWJC5Iiyrm6Xc4TRkAIeNvjZaOtODZ2FPfEjB3yQM2c1iRqJM8DoGWpRh3fCRIWRVDlIltro+SPGjxz9iDw
ywH4cI7qRw1KpVlMdnK7edTqVj4AUehTheUiF4AjIaAaOO4w14LwCBF4IcMsY6LrdaS6m74CiiJrUcOmbBazmZuVaPdZthhscZ6bWQPT6CRVf5J/VhMY2B
PHt6KUiCeMvzXGa38n+nJ/NOVQE91CktpCfRDSb6nfSgGQ3SzKwD7yWSMA3hSsmRSomlopWySLxrmKgdXtco4qy0POWhACPiD1e8xUG3H0Y+sePvUneYIE
uvBuRCGttoDa6Uw3A6SmvZTNpl/jPqaViMkuzsNG+3IALvCwSfb3+gOSFFHSc6e1NqRdylgrLvO3euNCQDVKEQFYER0C4MV1jD+0qcVMZUtSSZW4adU2Rt
gxjsgkty1WyxPyQ7VhHxtWE9pFEYnPFxVsy5WVwAuYFLEQsJe7V/+OYRBN0s4UvdL9RQVqg1DEiaMkAMsfvdItjLrgD3pZAG6lU1Lm3+tTVBpWHQTovsss
zOPz5WDeiKsPrLaEku7uRlUlO9Zy8U3DNPNn5CZrh2id+9fJ8HGWRxuR817U33SdDnm7sjEeRQyqjc6ZszBfDsArnE8jeLwH5baWEDm9t2ifjQFgP99ieq
M5GBnFAwB9wWUQeGFZmGWbbVAKps2TXqWZ6M2U/JisOkXqyw2puq9V3zAV2G72SWyYq2JopKeZOAguqti2lUDo5IPA53NsvzCc+jusIfBy2la5zG0W4/Jf
V22s2DtiyeLY++PXQqlHHhfSLuixl7yKylNbx/MSgA5lqsqYNiTlqSfnysG82xfvyvB9g4Ssm499X67ObybpZSOG0BFuylvpu4o4wrJsZfxNX2XujQ0e6u
PdxB+AmyXsRvXMNdsvB+BTHtAUjOABsWEsanbsiFNaG+YyANyIpDRTuPXGhoC2GQGwQWnQREvS5ENAzqbL5HPG7eppC4ZjC0eqfm2zn5SBpUDRV8x7zGNL
4EVbm9JMjxp8DZqI2DatMKxI2vlkGQczzKsXdqcwB6PK8OmDyeGPk90NxaKmUIgbt5IAdHpDEdnGDADraQDOSwBSoyjSwso+AhC5MOfwr3eYdxvlQOHbes
m6f/mj40ciWXaC8jDqiDI7CgMiVQBPcre8Xvd18sBS7EEQ7Cc2sElBYNtcZLxx9izMeAAuLSzkqxmE2P1gsdkyts5wSUHIc0F7+d3tMQAtHGw1CsCcEJBS
gwRAl3nVKtJBLywNuokhIA4g82XoPQJA2AUnUeaKAgnFJ0wAsP8AwwUnGO0A8fx20raWDQtCD2+D3DSjrQbmoqGfqDTMAmcHheLULiVBtc5XYirnR0YplT
gIpA5buWnbt8IkAG8MRGQbM5XD0vskAM2/r9TntedOAOyzjiPToOfYJMZPPO8BSjnLefXxR4s0BgzFPjVH5jlJI15NCEi7obpNwGx0d7fqhRsiBcCAxlyQ
LLZMjHLbpyI4blbIfOfMwcI4AP5pDm3t2npeEtQpt+GTbCBb2VPBkCM+v7dIbCSaUHMs5mgI2NSen2stMlb95htwzi5MtGguDGgEklljTWPk8sTPXZMFrY
zCKdb9/AwAXWS85vHO4yZDTBBqKX4uSxeYBsW2+CoGNROsBC5xhmX2+fl72Ofol7Mi+gDAXqrDqFg4ZBEAb/DE19s3tiNTsJ0FYJCKhr+fr38vAdgk0Jf7
eH5x2tw54nhMgrK5BzQPYqOcFkiORyPZ5RG2Xzy0uuk4tmNoCSYbW+Zb3cHwTp1ajG+I5KnFPk4V12Nzr+27xC8wKBeg0qCTBeAOlwY5R8JxDUIkBGDfxO
FhjlxVhY3Xd9lnoxYwKpXlADCnCqh5Uq5sV/0m0ZQ78SpgR1G0kOuXP1WF65J0RmbD4DzNlODJ3g9vhNxqKsmK6E885dVILgwA0J5oFmaTeceFUmF+ZQql
3vrlkbPZjACookBVhJABul2Oh0HYN3oRAFujAEzxgsrfm6rtl9ll65vy1Eu8YqvnAiBn++8EVmupDJ9Lrc0BoKa24OAfrpIrMsVtOt7BYUlTewrF1b3Mpa
nzur7jNw0l7mDKDo+2zVBn6sdJAhDioN7RYX2r67EwE4UsrRERrU8AxIqW0jwen4OZGwtA6s8csZg5OVDXxWluPg5os9k3BMCLSoMCAN+V26pHOr+MwDQt
Obnp1EqbrLDH70RerdsiI3Sq6JeR80BlRizPEcfedqQE3I8TdEDFrVU4XVMrf7ck77ucPrBgwmfl+dMu6Oog+tCzvaRCvT0bK5e3Rl3QZr5QOLeNSnWlQO
Qaxs8HwNY7cfVBTiNfEoC1DADR7vUTKtBCyAHaWAH1Si/+S/cVF5M3T6IhNYrYI+ogR3E0RzgAwH9MEIAL6KsQs7beyuYBljgB0BHoF7oUhYLPdBoAR6oq
frJhecRi9kar8D7pMiEAcSqKBOBFsUGvcDatGGO1XLoKtZZauROBLCdZYW+CA+G9bnUPturg1kT5RLWoROVBJt88CissKfBOgz8IgJMbFghuG2U4Tw7+Tu
nrcrPvum6z2YwYZhqAUUJl9Vb0oXuenwJgHCjMpivxhZKXGb4eHVkeGHNXC3DAsW1XnAOADzm7+kYC0M428iVUyZ0kANPYo4MYuHoOLMSnN18ku68OR9IQ
OaTCsoMkHLMycQB+4LxeKElPZDuTCgcAfpQApI4IF2fXW9aiMz4J6p0CQBQn0m52fggobNK2xUSUKwHoXCgAdzi/rng6GyNyypIRlzhfsVmUbk2cHsWQZ3
Z4WNKnMgPAmIjhkmCX71rKJcCwgtiggL9J8rGvdNge9bp35+5Ro4ahc9AeUxP8RgEYe2KBl2w3cHrRrqILmkncsOQU5MR74nyRdUlIre552+fQhXnI2Jur
4l2ZErdGbis7bJRSB6OpW35tlCspNjT+MBuxlwJg6X0OAEcGz21gQwSyQRuds1bip/Kz1S+l3A5+nP10vWaBhx+RsA+nEOtV+g4xnc9ubYh5r/I4ZwDoZf
HnyKZ6myyg4lFcDE1SJkGDckSMzpPjoWsvHTy5vq1nCfnJQvzeau5ZTtA1CIFughTTlgxfVwJwgrO8luAjyl73G94UAtCKiUhSKwoB2EvX4RMf2kMdPP0x
y877GIDbirgdF+J58qAmDiznFbFHik+FV2IwkONWz/LcBwC2xDQBkBvZSoM+Wg4BMDV6ZITgEinc8V6aTjCb9kGd3FKGf2EA3CtEnMDD9Flf4LxNriM6an
3mWglhu9wcTC8npkuaD1XBEEFrf/TLUcChCs6ZXXXcGICdToddVCFwLqw9iFVC8tqsazypEpO+W9MATOQHi6vpqCKttRYLopvU5knahFWHtFMmtK4PHaaO
2La4XsZyR4IJSIYbbXaa1pJ0QUn/JhY/Tyz5RoqOjVQ0e5T9rADoKACCCeTgXD05OwCv7mcAODL8tNx0DSzujFUBE4m2QNNJNUKiGHjqS514IQkc9nFKi9
UAANoTBmAreqmYkX2SBiDqUDkMJbRiAFpZYuf43iIvTURuK0+oN/rlgkm1fvV6NQCr8k9/+scF9Ks+7JDKqW7bG1W5w8g76jHtZ2dbpNQOwtRxHrLkG+LG
mLltHXy91DIgATipOsQaB++vKNuFpssW1ht5Ms9MKSH2vpTqwk3kIkTNtEb9FlUHLKbJ2E5aklre0HBwEYCtEj1wwAdFj62fGYDvNACDLACjbkA/XQPyXr
/ZzxFaUH+xL45SYlQ3cwA4UtN3abKqSwD8aZIAxBgw+jSwCUtpKmgbAfix7boOi8PYTC1+bG+R4CONjSJhMb3kV7optghmQRGANotYJT+tP5w4AK8SAKXS
T85wVTPgkpGLesvZGp9IKhvYXrJT4DgF1Xy1UZVUaJtyTNkE2aBX4JUdyRRnT1w3CYCWzMHAoz8LT/fDE68zvlrixFMKgCkmDLHX+vqMfuT6QXleA11Qtk
XZhUIdrO1AsLMDsCaTZZ5tZKrt9GYjURSlStTqHgzvZMwaS5YQ25l6Zt0TYwCYnLuGQjkAwM6EAbhAmxV/lKQPCn/WtCDokSAA71DZQPCERV4OZn/E8NvZ
EcaEwGwIKATfyDh/DlukTh3sCbThnw5W0LzHyxMGYL8cKyRps5f8xFhe+khq51jbS0NQ8ES2xhHHhbikVnr/SQCaGQBWJzSkBT1r3vLg06Dxee99bxAAdV
G6XI478rdSaMK9z7hreuJfdLxRRjRVhuhFDZ9mP+UbWB73mThQXz4LYH8tHp0VgLcVAGXSKuulGB3NlGPefncwrBeVcU75aSKqU2gaXiHZV/xZADQ0AB9P
EIB315LhC7zR9RQAHdkbB/cK+deOsoGe+KzeorgMGOWgXJLun6vVcNCjem/cz5FYoe4r8EABfWgf3jYq2AgcPp2cGXzI2bsybWMEwJQRRFOPjf/6/HnBy9
ROIXtG/5W+uKnr2qSsKTIx4OjQ2ahlgADoEAAnUgi81tl/9QeadVSqe3O/4D1m5TbpHGTRpAlnQcRHlyX7CICvM/24dc+LFtWP6Ace62Pn3iIXr+Tcs8Ie
gP2sJnCBAKgonWae0K7p2wFnwZuTO3dKyfBUjKbCIjWCpCknsCavj1MBaE8agOth0gdtJUqBSzNEWPWovFWqb70C2FWUTpb4rN6ihL6kZRk57bxidEh3ZB
ysRXBm4MXZtkMAnG40iAG/MykILuUBMOXjuPGKgtnBcL40SG2qG3/ipthLAjDl//CR8XTq/ztkAdsSgFV7QgCcCW/v9Ui7urQlWr/gC7dySJJ9BY9kGtSL
TUCSti00xedGhot9JOxY6SEiUxLpBPxQW3l62Oh0kHGuzgJAwwvGTWUh7e60R32YScjwBKbabDb11XVvBIAjnAyXhiRREkZMFIBwDKnPUl5u2xqA366vIT
0teHlQ/7P6mKvHAZPaX6b7eb1FXjKJ71a5Q1SEpmqDDLnt+K7u4skAkAMAQ84FjwDYaNDfDcEKToyv/PEUAFq+NtHg2dypUzQzSF2r/ThXaIazSQDeHKHX
JUscqlxtYY5r8gBcCw+3twmAxaF4c08DMOm1SZLPbAZOWyLmYqXko4S2gMPM39gW/dhxcPu+7284jlPbQGaCY1TFbKRz2MWM7OOzAnCfXFCDB6aZn62GW+
J9McMReJ8GoGclMrU1cZwygSnqkhtP+TLSFrBtNBgCcJJZUGz32I7PDgHw+dKHOYTI670tsOkUTNBN9mLIhFK/tHNyMHkhoF6EIXkwvtJqt5qu6ypRgFGl
W3yfHRqWggDsoAvaWFxclEQinK+19nBCFnC6rKYCGFEDYGLauZB6b4OtejHuAM+5KimhIrt7FABLXuotjF4wWQCS9sZEALgQBoXW3ip9jFfi5HusGo2qfe
NxTvQjRVLzFOunWueNSE5EzGYEDEtBSjsmEWeW0V44pGGBadCS1yL5iqWzAfDdvvgY0TFHWSqytCAOM7dDa5TiGQWBTXFjNQnAm6NWQ00iSCdhpAWcKBMG
DYFqTMFLc5Y9Wroyg+jr7W2puanFaC5VKSBMGdgqlKCPn1KGj1LUNgUHfnYCcK7SOza4ViUAWQxAnYLFKXx8YTIA/JgAYISltts0Zcunzb2DeqyDmcwUkq
tWjgciUlgRI3A7+WUjANTkWC5jQD5JAH5g2y9aB6tFqZl0iwDYzADQyARC6kMf43CBluco9exYw0E9W5kjPkwsLV2dK/eZDz/gfV1e34Ver1jcOhuh4qHH
rrYIgCM9RzH7BgnLtzIZ2hyOdTzx2M5oovbiGkxgGHk9TUjWkC7ohMnYd59zKXeFQXupJTyJPmRSEEGmmDhWCEDLd+ywkjCBYlxvUTJNaMv4opkqR1unTB
qq4PjWDgGwig6oFSMQ1Wwnwc+mGJBMXkcqt1uu6qbl1JwEF7nvlWI9zGIxEyxE9CcSvUnmslZvspGk/oiZRypaW0qHgQdanQzj5/kaO3ixfXOVEPJKINnc
zahDq8/cjKnV6votHG7PDl6hVbMMMw7bDf6+h6FdRhEG4xU3jYO4doHErQaT0z8RgK+LRXh3ZyJUeEhF+yjdLiNd80+dmEQllvZqyPItoCzcgwlMR7OZOn
xqCFgMQBx3cSoAF9Y31zhfW1/6fADenWG3VyUAS/UA+xS7W4XVQhJ5an548dATUmXBNpoxzbw3nggaTTr2uZRmyIzdG/f0mYusbztkHUyCvn2rXFAFWgxL
7k8GgFE9wGxGHDNimSky9uGLBAILhVT3dC05EpgqgfGWvk7R8EeOqZTrwh5P0qSYHABhUYcvbslZDqsDqn41mZ/jguKlqAKhxHxq8Ba1mHdUVzc2xNF20D
sqZKKsY6+TLMklv3m5BhuIACxKAM4GAMDgbFy7JwjAPgpc1UQKROXU+L8gEdYV8yieqci2bIvD1LyL2AQ2y8np1hEAHdGQAPTD8QD8dk4zHvjy5wPwA3sp
Jy4WBoF4vz0spUZwRAAE+9gVDLwyj/FqkhDaG9MLmEo+WH6l0hyd/WzkT1p0WLttVhCAvNMBB7QBAKy4GoBSmGYyAFQ1sWaqzzECYJMdvSgkzmi6e7oWbR
FlFZNp/Rd7MfmyqQFojor5IgCpG4Jc0AkAcDnkpRfDY83IoTY55uS1qsIP7mZtGvrOdN2TPHTMXt5+kQSpypp2s9JUSSqot2g1BABQuqCzYJ5KvbPp2z0R
V9+IDVN2aRtxk21/w0kaQT+hM6zCgDTBJQ3Aj6KXT0Owy3qGTSprVXZoSlGFOZWx9drn2Fr7untza7jHmbfwBQAkNlqh3gq2j0o6H1pIeJ8yqV0aMMEgBL
WRzo+BUzoJGpxahDeibCexK/zyqQC0OSy2yqQEMOcQBrqNasOKEeiee6yzBOADS06qdMsQKnlRR62adFtuJ4jzpJ65lwNAU1Gr0xTf94kcTL4LKp0anI2s
ATgBJgxSCwv1krZRXDJIRgc6SqOdHfu3OkQdaXAg8SQ2NQIpwzEiiy0NYD4A29h0oZVHcZjutgTgWQKHx6x2lVgoava1qZts4Z4sxxa4rfmv0QcdiPEWEK
kTe6t5tUD3+kivkxmzJhzqiMdl3H/8hK1tJhe0tAZYGBZXV1+svjjOGyo0HoAyfDkYyJxnMZUbiyxgvYsjwRsSfYlShJffC2hbI4OeI20+w/bLpw675LbZ
bnMOp7ITsjAkFDqxC0oNsec2gfDCajVuu2WjgsdOrSeqjcibfLaQyTuwJGUy+bH9JMMQBz1LLI8OyIrJBninmpUYgBNI7q6xhNxnaY7UKIIRyTcNk1YmrV
J6b2MW05ZFde07Y8liNeWJS1vpmuMQCMbdsiq6eaJQ6N2Cg9U6WyVwh9lXmW2SSgvYvD7nqUavuHIltvTsppyAfaS4YgZimGKEDujL7evXE9nSZJ2DUtY2
qzhE11xXOfK4hWyZs+BIOo9Fam/+ghhwTwnUFfW88IwHirXK2xge2liMk9tCGEjyYLKttePxZTa5e4oXKqOWthVKVcJwbmaNh0zScOLUwLmnzt1dWKNPGv
av+ziazHIQegrhethIzSulbcR7kUxvprTS2OtUFu6GQqBlJOYiZamgFFyQKFOVn/9KuYv940m5zxYmisCgWWaucLfPqG8+tvA9Ni21lJJEA1I3uxk7oWo6
Z2LyU5bnY24I31rsxGmbHljQ427vTITsdcbfoSUnGkpKXS89kMwlvBcTHYspH1RXF6LnI/sDclX16v/rBU3G4HYke9F0jZQ2gtXGlla/Kp6RVuKN4eEQDv
2aGon6gbPt4mqULz9k7NvPBCDq99QL6ddbjCaBS/QNuzh3U9iNSsOKg3N/bHe73RwPMNI8s7LlnNSXkCBFg9mUmkC/ZWlh/Rke+KZj23YFRausynlH6i3M
wWc/OppjfHERPP8oU5IUgSn7LF18Tm5qqouX8mS3XiSzAHuyudg08kUbYvVoRwFwAjMCl1RKW7XtvUIKJOCpmcgapvho7CA6M2D/enqQCebMbDfxxdyrr6
ojItMqhx4fH85je4lFSVD5vest+PfWVOtMadBl5r0LPGq2gJ9pxsRrpDCmlU4PU0Z69ea4pjApWu6KPwylt7C6Wihu7c16woM72NI1QI4sLTWN1myCTW+3
LfiZHSS1PgFHAx8ISWboUz5iYMbiLFDh+PMBuBmy2VJq/lRsAQl8t1s09ZZXGW8k8KcbA2sqBBSJqZzlch5nKKp2e+kOneTgPKmCgExQqUzf0amzh7BEm/
jg2NWK+DyfwViwQ28A7760z2xA+UbTSFVGohEqacJWqtWvP8KfO15NzlA/3BsE+ROV5XQUmRvhjPBXDc85KF4DcEuFEZLcws0oDWpm1UlpLPCgoLOBw/eS
2CIX3jQSA+5RxbC+Ks0L4e/4fVzYzjGBKHlaFRE7bAtfIgBQnKXnHxsCcXijFOY1JC0AA4VmZryRL7YziaJeUpMiuW6j2aQCJ9hojGaPurOoyWj7ye45SW
615QgYjD+pl6Djc7EOl8LroiYvUGbpEU07LabqGp/pgoLrul1IJXCTjufBdkCcOi471hqW8j9VRc7tyNG48OgMBgMbXh7Tf6PEwZy082aYWS0yz7YW1WyW
hCzvDiV2tAu6eL669fM5zodYbHkxkBdq6GfklxRxvpfOvheDZFSRWlw5mQegY/rilvCTgmTxaFc9nwxuYs+TAJxAWolaOI+TshE9ylSykYFbehMrTLSGJc
BgCZWk3FxTrfLB77dWo/BqiFowCZpT+uvLqHMMIfVwVUfOWMKYnz8bAB964mqLdMFI4tqyedV3o6kpiU58g4thoZQA4IvEbRnPUTNoAhYOOjE/BqJ7dOM1
atbYG65lJO9gUytooX4PSW9bmFeqwhu7D0fxVUHSU24KTMkA/oZqiGnEw3n22e1IrVhjoJiMtI8Ptj3qsLIdVm2QOISbruIRXSSunuGX+k3DGFNmiAZpJJ
QqjNRox7j3kQCWKY5dYTT2UT6L5wTgFbsjY/C6zV5uEdHcMSxjBICO2EohMCk30TSTqV06eL2SOnSIP3BQ7ITKtuE7bioEdKWN7WgATkCU6VsNQLWdA5of
FuS3JFpyGht7P7s9+54mIuYkrWMEilf11Rer4K7VuwIsUqTBNLqXG+CBVvUEekyHIJtqfr53JgDe9UTtjUyD9uWMoqz+oP61lNlI7lYvypklpcx9/E1bXo
JoXGp+0yyXU/BDnkQ1jFwd0wiwPw68MsdB07bJhlLIBekFy89nGEtAH/89zNvNqXzixH4pTSFQWc8DtMr4+Wy/0cAxU77rso2R0bDgbCJ9BB+lNmQZpz4W
XFR8hBzpOs24VY1um4bgVTuZGlxawySYRuBi41xls+dznatyyV3pzW+BC+2PSv7IYlkUU6WY89wYqW73xfvhqi6jlm7Q6Y9Utl0kOfhtdQ+1OYegAnkqMg
czES720gzjx/E9DH6fh5O3nfyEpbxDLbhDOVzz7fxzHc+dtoW3fXDz6BYcjKCp81R5AEQqfQOZa9GZQn9gZT44GxVmUwTvpDwkqURmmnKTV4uNfLRkVmlL
RLbBjVblRO1JzSqeWVlXNIwUN4uckwo1gnqea+rpSKxio2jEEy/yM3piJsKftmCllSCvTj2V24zkJRl+CQAOh1tbu1O3IRIFANrMp8wjH6kmZxgJp/HLIt
MuMo2VsuXFiawgHE0ZAtp2YiDwDgstNd8cnmn/XGUziAC7ZABLAS+hNwFHVfC2OTLS3eLU614cVRCRrTiW1lmSZxGsu2IyHO55kWCKUrgV2N7FHRkVuqJm
yDiaAOhMogz4AfxjL0FvgX9amKx01d2S75XIm6+cnZiOhPmmlRxu79rSJsAKYrs/yrABY+lYHfEynVco1efP2JC0ztg7z6OJBUE0ujd7USpyX5KSLfvC1M
OjT2zxWKIiCiDL5XzXGx0E3EbMwWDygkEI+OjuEouJ7C1hKwECLbIK+APLu/5ZAHzOMclQzLGA8j9X5k8Y1h4aKBBqqRk0o6888lhkocAfS3UxpYatnwWg
j1TR0JenoEkFB87AACbMwnLir4EnOu2cKwnzgbObq/jGhqgKRwEbxIJOOat5h0H/raQQCg0xiZohDLfDQ+7ECVS0E8Ijl054vpnw0fDtKejaLmXq+/S6HC
49UH5+AM5wFgTsOEWwfoVpGIvbOXq2xpiBelj46zsdLoWGnb50O+Qd4/bd5ikRRkQEBQN4mDxNiMDdM7b8LzD2Zo4UieToayMHgIbOw/RSZxkVIjW5MMat
j8m8hPag69RqvpW3ICyJOfZHWlJbTsjFRSywaFZpCctvB6sJx7dUmgL79+jzuKDr6REdxUQEKPsg5ucD4VUai7iDbcNlTh4As5/cqZXNcSVAX4+BT/1+k5
Oee8eVuXGXWiGi2tjSwhJ158cVNWNx0T5X0nAm5NKwdeH2on4rYmoYo5qvbfY+VawuFeo96dQ0adIO5x7jSYJ5c4NcOqeffTFmX02/BlOOk5OVvo6tATh3
Tvw95eykcMK2XiQzsbt01zuZpvjT8GeWDSc1MlZfMGYuiHO+F+eLXLwslFK3ebH0Sjw526hVT1y9KqO/ftx/oXOfaTlSJ069Ss+3MPDQ8QAPzkxb/OjD08
hZoQKQbAIjoYvdJiaoIzy8EnpaSLC+z9jgRfJ8rJzAj1v+zG6INSVKWEhwX5JDqwr1lZZglYbl0JxYJaKQE/+mH9s2zPH4Gy3Sg+Fw5Nl0SPyKSHc2peZ/
XniUpNao6w5CwPA8OYslGxOWlEaGm5r6HYtoAhtlc8St8tOcJUBgae/1+1nidzVDUiFSqqIJtviYBL3rUFcWb5ebSvS+yas6B3POKsQyh5t49YAdJIuRRb
hApQ+aMO6W3bGMRG9OJtjzR/TNvQ0jJ/YY0xtb7rNKRdBrTQNw/6wD2DZZILMwEATyBADNqIQcd7A7oruaij0LheEsXCKV5BdlPjvOfHZ82zVzDYoswxNt
12ZOB9uK1+OCB7zf2yn8zbfA91n+zHakhVD3eGnmS6blkgDoNRqLaoCeL3wjq4Sc54oErJ9ttSXPxlYzOHPSAa5NU00skoNvowdKiYnHnmCvWzd6Xlymge
+/uOicy2MDACo1xn1qmZE1F87sLADRaU5RJskxKJQKBzSB0vR5GPJ+OaW8YZyWB7bQuoCvDR4ojkaC0y7xZ587CTpHWoT1UB9AaQLqLVT5tOJWOllld0bz
J9LjMiw7T1czy6zIOasxxZTBid7GLGEpCcAt76xZMyzFIxemjXG0m83yJRYiGWk3Ckni+PGgJ7hvlMfdHWazpke3jKMVGFKVF3kwlRAX8TgSIAG/OukgwX
+D+7m28Ln9gMs4QiDlfxYy4v91dEEb04uWLZtHOTc+0csgX0kg7L6RsPKUu5JXq3ByqCH4BRDfYrwLVrbdJg8UExNM9IbwiUqHt8Dx67jqQmq45xq6GgOw
9NrDHIx257lVHr3XmyxFnKdgu+7ZKnXhukY579ocGyZZFTLzkQf6djIhoKwAFgr7QcoHq59QeS+ea4IAA2/fyuGQJcZXjg5Za5rGmOg/7d2WP7Kqz0iRsJ
QMAkuDMwftGATWUJ4dI3JnJM2eodk5Yrb+QgZjx0OktzCnXTZHC9I6/RASqU3JM4xx3ALPooR1x8Euh+dPog7aldsx4RVzJl34VjNLn92Qu55U5R1pOKE1
vGKecBYXF3GEZVsntI1PPwEyhZqJ66YZeTZWPkHNgrMB29ykhG+VaDD4N7pKFKNQOgho1izchI2Gc77enecpAKoll26z0dVJn+plpmmnMMs+lnVb2if7q3
JSHlJjC+y+F3mg59TFvsL28YOtDnQWRq6vPuVh+OQScxwLJTw1MCb72awx+CMEjiY98cD6ify17NtpdESvENOKZXceBEtrS2dc2xqrXUW/iMYKf/Ly91lw
8+atG63e+z9g+nOjnWeqdeMpj1QLrPE+XRM9UOQBODSscoHxkqqtzNewC02DZrgv2Ny3X9AR/4i8lmRbdMRAU4g8QDlMDgBcpNqAYTH+mUfNphriRt9tNr
HRPMhlUGbrvnK6uK7Cd2ggViHiH5a2BZnPxbdwba2d01/bVy4oizThiruj4alO63ULSZ5RYVv45Uzq0DSNT8PQTDa34IBqn1WqkvJ63hBwRkr7FOpssBoF
9cVifb5HpyuQ954j8yr9OHeYfsbijzE+6nPiP004IdwtR63jcIE2GKnSFxNpvVJ9F37skzPqGKwzfhVi7ngY/Kkv2VVSmszjNd9tj78ftexWovEj98todI
H2QD/oV00N7FPoHZUUbWyKC+/D8y+RpEjkYIopC6hQWe/CKmYYgxjQ9WUm10kkdLX1z293S0oXikhNbLRNMH2rWvCi25YvOsoAHsYE4BKKnLCKYb1tnFvE
diYMilESRj8rQQ5FQCfXSpF3jrR5p2yOmYn8SfypU6qA2ImKED+eF4Av5V7Opkbf1utvSBUK84cY3+GFGnxMJjCMBKXFZqc8djmv9cEhsZFoBBtsu681sZ
OuVH2fvu5sbstDooM2ZRNc9fSLzqrYjuPjvW9ZpzaANx2eL1w3muIAsys90Crj13Cq3VABcKUmBluH8mAcwMuDP737BQBc4BqAhTj6i3rJtgYoMsEXnq8J
x6pyVxl/j1sxCwL+tWFbYw7bRuL2jIfWNPMacOP9pClQbZWCWVPRlwYgIbDxFidGPDrfcf0QsmO6Zm6Lo1ia4KXIXIURqhwRDOqF1RcvXhRKtzw5WHfkLJ
axem0Zn8CgbgWUHp+jmdjnbQaUY64g7qp3ZVpJA/BEtgRzzzTgvXos0R+fqGHL/Cc79ennAVAlbWxL8nybEEfbIiilQ5li6bbwDu94ZxNGwzyovSE2lB6f
dWorm/ExpoakktKp+97CkpAYVXgdDd9JFk6FX+CTzT3/dl+6ZXggIa719lUes77VBWv1RQDc5LJ7M5v7lAWOve7eQYvVliC64BC/+b4UOfMjf5luc+S1jE
OgbCsLw7DztlGxI1rdacezzWuovMHsStXhfA6W15vdG+oMLTF/+FvA33kneS1w0gTDQnycNSxsqR4/a9RkwX5523uDW8ibjzyujMgScrpQabj5KQ+0KZmI
mPFvfFOdiAf6gYbCy2j5oB7bnzomP1zN/XYhnmiWzREqswoAw9MBmDdlhm4T2mYkSGOa0rc4zRFMHald0qkfnnXQ1TKYQNndb2RGyeWFsinFIddK1atzB+
3YpxsFmULGBvGQXbk7w71DlQyv9wT24Kqlvlg9Yqd2PE6N8kCVJGiqkTT5ixMRLGGLCwPrS91YcpJJ1KhC4gXCHXfY6HYMO1VUtW7QoKPcTvgElcFhH8EA
dpiD1G9SBu69Zuz1QfQBtzyUyz63LOHzNRX+lniQqPC9EV7Vb6a2VisUuRuBDC1kt8dIEpcUvzm37YBzxxiXTtNySDjstN02qtXGZHKg4BYxNDuS09OL6L
2leulE6ZzQVHvf0eHqSNt3zP8f+2yUc3uLfVnDdYkMa6Ngz3ZGbGbLQ0ptvdgVZ7w5wW7X4Afge04n4s3TsWPZYJqlWClZRavp+vbIPdMcMXvJsEi1rfjU
trb0rS2tFgSAu/tiNjmTh5j6X2IB2b4XpPOeCVIMhV5d8mpnOOs0Og1fwsclRqwRTc4Rzvj7noq6HX9xenq6YeMIpLKR35yqDoVLBU80gBW8pBjxKutgiK
nZn07US+Svf3tu2vKMJDMUwe0k4TMpSzXvyZYOKzPvTgmGNl33o0x7jqzBl4VKS85otcbw8HQKNFCkmY6vPdDzNeNeg6Nh69x4sdR7XV9V+KvX9+Eiayqt
XCPpe8YKpeqwsk89fJSCIYc+E5EJ42KOKTRbZGbJ1wOxR47oAfJIzvL8DF4YnA2LcpF+UuHTGAtFmezyuL3h+z7Kdjt27vhOkXNfJsv8XIpqd0K4Jz/Awc
FRDiRSdiJa6bJdsfj6NBM4NVJeGcyy4/SrKhZiCi2ljsECAgDDSqPasXBaHnEafclJR/x5eeJLiYVYfgdDwKpNmhLmKVjFPws8sAtYhKdJLK0tub4XhcNZ
0aJbHbNpZ09np2tLsh16i3VfxNTBPfYaMcidj7q8kPRe9Hih0QXAm6i64yN+nbLXwxaUwJtfde0OpXvDc1Xhl2wumn32cjUemnITa0gAPzSAimBgq/g7W+
0yI8rPmOGWIqUWl85syIW0berOKlOmzqqK/XRM89I7kIm9A8bPtsL7Idug6A+nSfEMD9Ice6gsp9kPogUIkTe/M5t4y0zwgEBqQ2Z/OlXmLS1xOXkb2Riv
M0OWUILgtDnjUyOO9dGtrNqqoqWp2ikc9hlyb6qNbyqdCtonKcfSlEohzAOH0PxU4t2ldBN1AZwSOxuoOYVSIpaDKVAwKIOCLpFT77+3Bf+5sjLvTWZi9Z
pQ6kUtL8HaL7UOt/ZaHkKwWU7YwNOorxSY8MZ4oVMzPW7VEbZirdmNCvY6gwE8XxFwhotauckitedVcPlaQ4Bffb6LIQ4n2o4rY52cFgYtnpxv9qhMwlUD
SE4HEn2PDZT5aTPiq1TRSCjSEFnkoSJmwy7ys24X+BdE15QGILEbcWOimd/q4ebmdsMwxl9y48xoiaZWDiEDaKMBfHT3CvPuKKn4gXi1ms6dIJ1x7fMB+C
d2s4hUmJFHcRfqmJa/grlS3njbsTsch3Sa1JjP1a3v6YGr4x1xreSZk18yUw4NduraJjX6If6wTSqRS1sF72VYmocnmMwMk3XGZaR0zFDNTAvoDbEqcdgN
YIecfOpyroiUbY3vxMr0+YCnp+Ys+g4pCoT8nM3wuEMYnIvZ1WiOTk+IoDXbAt8Q1cXxmoyaWfKbiGKpZWn07Mo//QDXQ6fyw3f4/PBP1VBE+u5jWGiyxx
jl5W6vFnXy+s/Ix5RJ7GLvzNmzHyEKpChW1qIzM+JNd8wQ4ripKPN0qrLfFochZvsATe0myNCPIkA3BAPIFu7OIMmOuMOrXUGisauF4xIpyslBbF9kAfde
vBKD1WIu/MB/aaHiDKZgcIAk73CbxonQqHokBGGWxB5X+TLzFbDTcotpWpuF9KzFRS7sKhfBcZqXQ8KNuyuTA6CeCgWR8+vI/mkq+mrpFTZnWOWklko+Av
G/g9pnVd91W6CjB7W5jjIt4blSMJuUADEaHos3s35b5oz4zBUP9VWp9ymabpKHnuQkXFZF2E1XO28Rez/88PYt/OIHWytx5tlQmSCX9WrOvCHFn+AFH7zZ
UlWkEqrFfzjrIrlS+Sd5aj/Tu2gzbp0S2cDtguMXk2b9m2++qarJzHlaQPFQE0VAsEPw4x7fXXoiDpRf9mJPDF7AVddtDfAm37r98vYQDucXxYDbLyBqrK
cHpUaFt/kWOqCoNorjwSo2IBCc0AqtuoZegMWF/dksrGxsi/tVSf5tvKD7BjqgHM5LUI9HpulP1gWrOD8/NalJzpsRxXN7UChl5Kjgxe5L2rg59mKJfEu/
Nq42PNIDZJl95B3SljdcF2sQnfCcALzGUanAtLDVYriqORUQLXc9NrNwd2lOYPqOpqMK2xz7EWOpc9H5AWH3XfWbH6Z/UM8/wf99V5HzaHJ9WFkCpJ49uw
q31wl5wCcB62r8lVAhYu7sVh5xTZJlFmdWCoB2NIkrc7ck/9tF9ZQoCESPTrXYJIVg0lk3qbEvb6dqVXYCssOijItWj/EA7bHeUAKmPr8Ll95p8VEWgEvo
fx6y11Enr05dE8ntdiC8p4g/QRNqKxXe6XC/KpcOr8BVnbdfgsCU1+CkGImKZ4uS10hB21otjmgx1wPxcn6lK9hkJnQucC05WBokiYvaiyt0Wf69OnJ4fX
O8xreVxh82VSsH1PWNalUXIc6DwBlOI0CtRgOiuAPtuGOTvyzXfGDYRUNxpyP8fLU6eYrVU/3uu7eAvx8q09/9kHy++056PKMio8qBcS25gVXbYyKY3d73
RHBzVfMoCq+QDHO2QuBTD7VRHMWg7Uet01JjQffYmLks+JirhPPWuZfIxjjJv4Bp6WyLZF/SFto8rGArPLXi6jMCPujLlugWVmXymTo+9tkpVIOcOuAhzg
/o1eNkRwmcvN3d3QEGQWvLqF0r7EWXAFgNbc5d3lHDgKTg7Liw6DOQiB6sbOSxpGKKDQ4oNcIz6RdrHn1EZxoIb36XnXVA8Mizw1oJ+dNicYSK3kUv9LQZ
Mp/mn/nMSRtBW1SUqk3V8jsKgZ3zIHDJxjQdyuS89SHk65aoCg8OYOmlHMYAX2A7NJvRkhenkS7Dq19EPlrlu8ZbCbgffsgAkPMshzR+AbaQsiXUyEk0Qs
F6UvRQhtcQQzjVvJkJn17iGvY0NBoNTrJcbYh+3JgD7yTILKZ5Sk5UlXRdnx7Htt0M/vqKIBE9Tar+oyI9GkDyGvfjwkP9NZ5UxXdVdOXgFI7W1GgtDHVR
tt57g5W6vKTAa7iz7+EdwZ7MLCx9AJtt09a+RRPIOWu48vIxKBFj5bWF5SEwTwqBiPeuRB9F1khPxgxoqOZmxL35CoDzPbbvnZcFmo0Ciwk58GxCahZuc8
uwTuGUfcID8FWYHD0b9D4pAKy4Gn/fVM7TDHGFc6Vp2oA9EqK3qzy+20yKxl5DEb6qckIjox5nY/S40Mj+/TDm+W6a87Hn2pGqKWCEFQC5NzgurMbe1UAI
u9HonKGN7BpYLdRFaTQqTJpA8HZ1B4ZRS6t4n7YduUc1weIG09gxEix7BDrKIaIUBad+zWW2n0iW3Bbd1eT4BrplxpvAEQB+y2k8fHFbBN2hBOD8rpSYX5
v5cOXpGhIHpQbZ24aPuqBhw6jIcjx+qJSg53iw5abvCcOeOg7IbwjbVILnGC0PpQHU+aCI1dEdM/fprEc35MfJvtEMAIuFOkctA+N0AI71s4kj4iURWHZZ
0G5TyFHp+B0FQHIv2JlL8TNhTSV1Ft9WkO7A9gfD+a1duD2oM/QKD0PWqdjy7PrCNg0r1dHn16xEI1Jn+juZeMl5pjueNSbE9SW5oILzJansC7d1/UVCT+
4VE7zxdtH9ctY5snwca5EQaFPRwDIrER3eUQxHaxzMcuUbrDwJGF82fZSTl4pJAxLRLWN3lQWM0iT1gNX1MBXtsW154w3EVH4TNfzVPbDwve7J4GQWNbD3
eZSM5ipesXDxDiMODJl/8hmTc++TACzn8JTztLKRSC9tPoXVbdMNw6rDJI8i6RSqfr36gHk7S3cn92wyJG2NwZ+6tTtWZCssN9s/nnevpCJdR498JPzJod
RkiUKnGnZsW+EPiXdnLEU8nJPOpdRqrDQqEH+hlB5s5OY1FCrEnn0eOnCx+VJYyzFT+sPID3Ups0H52B+mp6d/iDGYAuN33COX3MpkhXFKgTKw4CnCZdLh
bG6OtMIkLXy13pLiXpZR/dLBcph+QZ1YAmCDqxSyrRrCJP5SM1DHAnBsJTcW7EOboBCI2VYKnOG3O466N0iOSdU460OtqJQQgqp74y+YHEkKJnmlheO9nl
LX9fYHKy3WCaUkcKUSbW2DGmp9QqCsUbtx4Jtkm9e4P2oA227OOBazIzx8j2Us7aPQBMQPeBKHiR6phFYGdl/xSeKPxmJEAMyrhtYDwRrxOUuubLyAiJnk
MWF1O7qtuUyptQ2rY1dCeMHwKACC83i27O5DrrM6hADaJ7725MmTzQ9Ld5eurCEZ17FxCCgPsdFElkGSxTvYhJpJIxcxLTH93TRCUE6GQwn4f0pAUEqyWE
ldFko0uegDtvEetacbVgMzlleuUKscZRdKA48G+zRoHumXmcCHEn/SBmCeSV43rpykaalcinVKuJNnscf4NKQWIBGIZWmvSUOZWFjR8phLnDgGeDjq9V0C
YPrQfBkA7z6KW+KPD7pv3rw82aVKm1OpNGhbbV97N+DcsDWFwNBSdydvmominuS9AIo3MnWmsu8R43VEiomkM8tNeTDbHMujkkofq5zGAKyjBbw70ec+xy
660hj4wek5Qe8nOmeOcJKSsDmXblYsT+U2pOJWoMUojSpHhh7r4KgZ9ThnbPFYCHliXMdiw+3A4YeTsgTwW9hkNFXAcYjdF0pZEVtNTEuU/wA9BgGQg8mb
nq4gD5dz5JXDL7AWrwCIJqGpBNJjyWHT9eSkNcB5YxorxehR76yJ3jH1tb0K4GLHHAoVkb9Qzm5T4Y8A6CNFWFbOfUFA4Rkysi5FmGPIoafZQPh0NsUMbd
puWhTVNR07ktNYo/hI6pzuM3ZntVgoJIV1t06pkuUJ8z4RXd08tlqoz9OzC4jXU5D8qsLfWxtbLXYY+TGKnYMCIv3s0tCv9M0RrXKP+TlvxHUQfx7guI2L
B/yBIb6pPlGqCIhXzsrEAYhj3rZHO7Ji93cI27EYDbUweKS1a+YHuekdlhls5tGIFEwT6tgidGQ3qI0jNxrkO1Y64kzppStolfS8qnbD9UM1r2fp6RoxWp
yKU0UT6ECg2SHZJZ5AILUg0daQra6CuXM8HAukRIqbPkSV4TcAwbdvvyMSmC1ESr4RdTXkzVJV+IOnwTHRL1iru92TvJqG31jUM7W+ZIPw4CzS02ggc52r
NBbWGwGAH3mkYmBm9aVOLcuO4QtWAYECC9RWIPqqPGM7sdVWwgN4Ob8JbrPgUJJh6lqTd0DTAz8fgN8y0U30IAGs51daolOpaLcGxxEp/CHJZiekiIMr59
Oy9fWjw5y2l6yemZGqCmN+gsebfCV99GTbbYvw58FdWS/FFNAEAEvzK91zKTHlPo8g5CwWxuCvUARvoLOo1kreSELt2jzFsUmAkXrw4K8HevC16YedakfO
maxWfPmmG0jM2DkTAOUIXvIqrYZbZeHc0+Xl9U1Pws9xVK2xU3FsWccDBDpSB0tW/+Sod+rexI1GPa1yPCjAbDqKGlOhIXs+uKyRIIBkEDIcnw7hGH87va
jNohPicDapSl2F0FRf6QZA/vN97WVP5o7I/iH+wJeljhkKAx0aVZ17qswvB6AuhwrPJVEjXzX8dMAhUASzhccMea6UsBzaB4UW44Pj0uFge1CUzW2lnnh8
90sAiKX9l8meinmU0XLiMYBV11qM8acQiEnLpjyTjiSTR3k+n/QJMuKp6PgLJ8mCiXNRDqY54Bt1JCsZUzB5LiFWIVb2z9sIn4/A/dJqMc/8oUu/D7f6Yj
KtCWe4nMeEbCdGr6SFol0UtoVDX1GDRXwcfN+RCAz9RfWiMcl8FqbylTDRJGRhqSyen8c7bkP2O1XtEJucwRNFtjQhMB4wp2pqNqYAhLD1XMpypDdFqq2d
DpONQPgTzLgM58v4D/FXmZ7WHeeWlGbxglqNBRCZNhYjM935/DmdEAB2rCjFW6WeGk/Jyqt7JLfBwzDNnIqg+WkfFL1QYqcFsgG/7FJefk1yP+4zlB7vFp
BjV3o5gOPRokkhPdkyDvjbFadQYfLHky14rHe4GmkylV6hv1BZ1DKzjm9N42yIiGQKCHRQy5SoMEiokpLx+srvpMZ2RZJoLDYdSV4kdpLVLBInBvzBIeFc
7BVy0Ech4JCx5YkD8O6Ox4Kt1RzzJ6VMEICJHQIXxTZztAstjgNbDTNn4Bq2grqeSh6QC6YBGHKmy4KGiz7oGdIwCzyMMxBWA0vGhOyOA1dntRojEPxK+L
koqWLh+aLXTh0Q1ViwUHg1Gr5I3Y++7ze1qKS1gYkVX0WNnmKikPAI0inbbcLf4rQVaUG4VYvaYFCNxE5EqSg889nX6A5VilV+6RtSVZiD90bKspbRxBSe
YaUbG5OCUfntmNp/GScu3DYktgl/YQiee6i4V8/EaxQYOEAE1nex0X/38Give1RQ+EERzyd3vxCAlObtbikfdtgSSD1rRLdH1V+cbsDRiBMET/GFGoucLK
GchhA0y2rUjhtVnlMpXwRgMHr9gP2UOXSJP8ydzYnBar2UYKZGWJivv5x4CCiroYzhqM7MaET5Q1f2Bad0VEzg8TynnEMrUJ3V+YrvPmNJ/IFpQlYDpur5
ovbMKgCGM9DMH3ZUHI6fcbHhhL5brTZc9W39itvwCX/VDvYFwm1OMxZx0zCZCRdgGPMqXT0jD2tJFZW+1RBsRuIOHdniS39ioyKJ1SZi4eL0YiwyWXVI8J
xr0bEIf0ZVPP58A+hEf5M0Ffjy0g68OVvG5HitmUYuAOHMueP6of2ab2QOaDKGtHBSAilhm02wNrEE9DISQeuB8A7q8zJIejlYLeDANlUmW5kVX8IFjShp
M/CWXm/vDfa6EDCj/as0tBKD2/EXwZtP9cBewf4k3MKa7gWhuQ20TTVMwYyMOKEiEx+x/j6j3aND2UE+Fl9YWmNHLwaHqb4MrS405bGZyePv+VxYu8pwSn
eplJJyplcKVxoBMJ6T1+Z0/49cnFyFuaMzGLCg62nS/QZ6hvSAM3tlhsUpzLdnnBA4R1l4heJGA8KHTsWIjm3FBf+vqkRWQyo42uTyO1j9AytSc5OmQKOE
9CE95hhx222cUutHtyw5MFa7DV8MC6osLsasrk6TgGz5OObFNmT5k7jUnw/Ap4w19UdabPgh5XfvbsKPko2pygbGynQpWgsxrUfrRn2MjS3poo6KNVkK1x
QuNDF5HIesjwV4n8UtOBIndyQAWycJpmQd5yY+vvvlALx7909znoqXMWn2zTcVcNlV4snxwTCFOyM205FbqGqWeP81ac5FzeN5c0DsUV1JN0DJcKWmYuNV
CSh/DgAsSAnADBZW5s/BpT+VZxGe/PkNfLyDgppmkGDCrOzCHZECICIQpW1y1PhZmvcZ4a8ZCFsreTkp/C3MMTu+4c8IwKecJ+aWwsb5nUWDyKEUITQwe2
hT2xMSuirwY2TQjbGDmebZWQmgEcUyEjGP0jyat20rFTVkSlELLpIlAYHq+1m2r6W7jMUOZ3HTD8aanzuncy35eiAOUlJAzzyuHAoDbJWfnv2uMw1Y3vQT
SkxRnxF60NKAJwGop6hKcyCnJbvoMoSxW4KC2KVSoT7cOnlTx5bAUutlAn4r26fj7xQA3r27tP7o8eMnSDnH3qOGeqYXsVwVjmjdP9zESUb4SSuGdMea4D
/VSJOh2cyJdol5neqId22aWAOXp6vSL+FT6fUP6q2ims0UZ2NKNCWGfX74/iW9BFP1lZN9VMBITwKkvCt8SswfJNdkddI6dnEzgTOCP4uSFI4Ry8JH+Fsj
hcmqq73Fs1rApJ8mB55VjWiQqeE2LDKB8OkePw1ZtfEWEMipr3oR3MemmeqGS/GUcK5zbqKi3OQOKcUJ9ISs9mKHdZBKAOHk4qL8Zo4dU06tuT58pPjHcP
aZAFzibCMaSY4G8GmUOFTkF4y9MbuXpebIrmA5UCjVZmQasvFYjfPIEHpl1gPcFWXewf7xxJFjXp34nmj63iCFqtDlK9jxjxzq+hAMxOkLm/p0QP8Ek9KO
rwHoUNSbF5gsc+If2CSKLNMpeC26cRdketJzVWDuSu+C5Qeo2G+iMBi8V9vphBrlyxCP9pTscKmUMICAv5M355YjHN3kgL2pr8yXTjjS8QalxLRu7AzhKL
XUzhg2XHauOJ89Cj88pZiuMiRyI/ixzaW7CzblYziVesgCnqnV+CmPyGjS+Lh63isC0HcbLgoZ40FaRnGRig8/yCFKKlkwM0kuSxEFEyrKIwrEZWMDG2Ws
RQrgOzjBHGW0eAONILyhqEUdwNHxrUr8AwAATz+bBNqPTHOjEvPVl5XApdwMeY1kgm9bpDSgEykX4txF+m6p7cL3FUBwLPGH11UngaklkmOSchRbrDWPpQ
jWG2KTeH1+dxv28hMR0tRnrHmd0qocKRpyQuOzH8eWsJURdHRPIzaEovJLOSmmogDoOk5fj0sCN1V4qNgPsTvAlqN7xKM9YfuDgDo76t2EAwrXSzBY2Z1c
K0QCgFMrK/MtjGHADe9GCZgi4A+d+gBPazakdcD0p6gXavBhFn6Yv3csnaAKE/hDTuuc9OCaG+SKIwDP1pO0xhIuHtyEZHasOAuDtilcVvem3fB9h8vgG0
8v93PnGlsKgNYI7U4mdiH6474FUQqi2AYv1wEA4kR2cENdy7UTQZVRtWPzh983XPhsADZjAFYTdPUZbcXUyOm+kf6g5kfVP28k6xSqPs8z2Iz6lOhKwqaO
tsSfgxfXZtIgo0wDySas7gnv5e5K6YB53d3d3VeYPAk+1e0/9VmrXn7sxZ37P59yIu6vYbOOVSUIKgcINRc5zlQtZ8qiZcXGbvZrSAvsE9nVpOgP4Jd0cn
/yApoYVhi24hLgCQ9ezc/fmecXAcBbgD+xv1XfGg5a3SI1sKGi2Pz8yhSm3itwR/hGZgSL76RFNqTP430sJ2sshs8x04EOkkXnhJKfHHnS6+Rt0znAvhAs
PcFu87O1GhNdWY98LzuVKAJE77OC7SXh5sPIc+n4xDyFH4lb4HJpobMQzAGgzhFKnWK8O9DhhF9VsUZO+JvD0BaizoqTcOrQH1XXg0Ue6Oem0q5E3YvSAi
YyjEkEmoSa9IxCR6ktRf5nxjjy0eKEQe6Kh9odbbpPK+Q4xOZ6iaOEmSYuIr012D5pUWsvaX98kqY89bkben95/dHPP//jH/c/7fuEziIWKRQE0SPoU/Gn
5rtRm78W82v6NSQoRaqbbYdLzXqedEl+ZCiiDCHuVlCKhV23VualINP9C3BB/3wiNKt2a7B3tHUIATX+vFse7kKDzHSF8mbWaJe1BuVHTHK4Ze3M0OQdwS
Pxkia8JYk/JkckPHzMRNXQvPuqsfj27ANnZECgNehIHB9jvMVpiCLw563dT1BH4TrxqfvC0f08gkIHKzkPPtcC6oW5dnTpIn6x0kENVeHOw4XNEAUaK85i
O/aDnU6iDOh8frFlQbmg+I189JPCGIEfuJR51nPBeVIprUw5aSd3ygCAU0gppuwfWL6HOV2yJBAnV3y4EdGgqCBw+QkTvUTzQ70rVXdoDMzj5c/oEpi6O+
kHyb7w/rER27FiHbimL6WGeGDXag49diB/x/F1PoNKROTmZjIPsM4WxH+FLW+4mpzuUUeWKpv4GmZYMBXQNB+KOI+38XMG+92TqS593oqrZLXUKbVGyNdq
H7kW/pZ3PTYlqKH38L9+nH0RREZefiYIM2rvq9Zi5axyDaplDjxCNMQV1BUA19Al7hbBL1WaAuAzWBUaLK4GVAAEud6XU11QgqDcbdOU+WtMEjca32C2QN
6j8FGEx32sREZpjYhtQLy1z75mHlKtmWQfOx2HTPlM5AEtrFHWS6UVMJPQjEY0lWWmM79TpYz6p6KfnTVPyUDlyeMvKw5gr/oNdhajf4ZH3QtpnkGkg13f
PWntBwI+1PPPWs/kAagg6DR8G2yhG18yJL+BqPNoShQqtjuwJ1Y0q9Otan3wf+TkvtiwUK/XvWhqA9UCS3fmu8J7PukVwFW6j/MkI6WP48G2EqHH20UCEL
YHT6njWuMbkRxubygrabk10iHWBVGXxIkT5u/uYyZrMDq/Cj/mjGRsfRwRglW/gUlPl4iTFboFvbUrOdG77TfICFab8VTqmkucnSihikHtRgqA8Kd9Whj8
rXbblHcMIN2VlBcVAi3toPsHbmnEBqhWovIi4O8L/OxNUr0EI40sv8UqiaVvLqu/vzQTMikHSUNFsBJmXVdD7vIE+xJd0XIgYMoFhSs2rFjSdceoFqtvpI
hKv1hbwwRTpSrexxJmeCRXVuon4rNb5C4CgAhB9Pt9HxDVcVwj3fWoNjMZ5uLxjAZD8byywkKPVO1KrcToPmTCzE95Z7cRp+W6kQCeoMOu0mSo/bn9kwAQ
2CDak7RpgqhaEUkyPaDAtCRJ1MIwNzYpMmCi1j+y93hO18H81WK3DPe/4p9z4sxTHpLGqG3LH0UXHN/MI2bcx5ul8ZaSM1S+VdPrea3fTJQDm27TiObwwJ
LbfQfjHl8WO0jyvOouuvAPJsvXrqVuZRZWVTVr0SU+MeZr8GjzLwgiroQ0tqHqy2l+VR+3gPGdBWr22ORyJkwMIVoNJpfwxuuXx4zQRtKSqKV6GqVTbVJq
eBGcaRvbMwl/sAhSNBTCbjfechGN3cDzAk5Zvff54y4uBoDwvp8S5c+x5SXcTMLNUsSmyIFx/aQ+fz77+Ns5JMeVBlJ6XzUDzs/fCc463erU508Al6BeyA
yo+TOEgdgNGFatqKambg4bDKGZGR6hWcvuBvKFyVSqlTcdBT9b2j97Zv0JjrS0Us8i0m3PSXRd3gxTY0dm1u+PMTZYxwUj+BZcVLBnYF3aFAIRexpnqiq7
HPN9yJ8hYTL9ufHIdiqL05gGjZKs8Q94RLurMUj4mybArz38sssR3PQNPzECp0J9TmtPP2zqZfoJ/V2AiZIQcV0zX4AYfg/9G1uHtLhwLIqhsDcA0GiAa+
6A++nJbmn6/D4cWvBZ3beVEBD4QtsExN9AfH5t+qIAiFcVxt5Y0vLovftu3jzjNPg8TAeOyakszYBzEwSe6KrBgCiJvRuIC6jDoxPqMS1QGM9WL5VW5lfm
A0a9cVFVDXdLCu3jFEjXbWoANd2+jzeQkPiMiI+unYYfTVDCcC3zYI5v8/xLuX//R8yf/fzzP368//BT+bOqlMIQzHZlUtqgxeEB7zgbft+Fp+/7jiN3Lc
D4XaVXEavcoR4HNBjs55Ef9nB9TXXUVxpoJhvyu3yh7AaRsZ0kUwcz7bQBjJ3snlylK60ZCTRJ19+lzF88uXikZRVsvZ5RakmnepHgB241mT/pfsKmOZW3
DSmkQdEhqkKx4KZS0kP8DeF8PP8VABBeOLiiYWKYB0Z9zoYUgNtwnMQBXNtJ1MPG8eIXdp4x9oSJ/akVfAB+XU94yxfz2Wc8NjuqDQ6gr7dooqzOv+gkE1
jCaDlcFhZU/4+NfZQRWumcJrzP3mC4dbTtsQTDOOJZ8YhyfznPw02UxEA5qA5TmWlli/s6Y5a4K+0N14qdGnIEMd4E+IGtCOfyr9H7j55F74hECtlPX5rD
friGZNksVa5Bdx1rzd+ZP5GpPamRQn6zAx9OVqPLZmYQYpQ3a2sfTUYLspKN8KugfBUm50NGilmVtxWKZP2OdIHAbQ+FaB3VJfmlPvC+RCRs6qL39MramO
k6Qimhhms7ywuYBfAiBJ7uVHnYU31ycvKy5519wvjnlNHY8EWmHwnZb/VZ8WT5Zzw7MsWYosM0UV+S+l0xzeuDPUxCymirmTQdaj1CC3JQWsUpjof7LNWf
Qw7oGWlo582fwTEDCOLAvND2reS14Oqn2bQ0G0wF8HhmAX7TAL8K/s1TPvj99c3o4v1p/QwlJAhXO1m2qmFhjhfe7u6d3TtTGJhzTkZcE9LtUGAhrJmI1t
N80TLdohgtUGJNRxiYVHKw7Ms/rIWorlhpqMZYR+VsFt9iRCjE+1Z3MHi1DT7Zl4j0TV34nsJ9xT0vvjgTKHz2E3hFEdtFIjAIPkW+WngSwffx8kV9anQJ
Q771IqFFSllXAKDsb/4HQtDDwZxlM2I5p1lncdFLcu1cp6PtI/naHtuuq+jyBQr+2mn8QZw4d/fSn/s/y0CNzCCJcLlJEEbLa0eolP43lgQaAAInpNrfp4
C+sHAfnjN+xn9k5tdSeIr98Ys2AnB36oQAyMiPNqxUms8Dr7nfzLaG0ZBOJyDPZkOib1HZdVat2GHId3AobRhi4l41ptua1r349m2jyqNDyde+xChcOAB3
IHCjE4fZ4kcYizx+TPHIj5mBmj8RAIMg4J8U6Lm//vjZs58eLV/cp95EvoXNaIRdSgl/HjuAZdT5SFYxbb8ZIS2TfUlknDT6ItuPXdytUqw7sDpgoprwP9
9WJjDz92wPQdDGFgmKH8KO47vJ5lk1CSIGH9pMyRNG15XN3L/oT/iIoVhuhiiHQSX3hlO7gEBPhjxUCJWfVeXDHDkLwovL0bWaqoxRcEpetb5akMdTpWrm
5oJ0i0JWXWyoC6nq611efAtuKYqngaVZe/Rlm3bRAARXLghUSLT2qWst8kG/vft1nwVqLsO89ewxMkAj3XEIAWejHvWl5c1Ip6/ftPLVhvGU+jWuxl4x7/
3rHj6vPdJm6G7FJdyBEJEWBeAvvJBW/8+LG9afIe6SzkqoMkwyxdSEX1AKFC98sH1+BdxP8sPYs39cRti6SZOV0y8aO+VYrzRPAPReSmcDg1qfvBTNlyBb
p8N1FQZ5mBdytX2XMsmq6IfX5qbG1H3k9y0uqppoRef1FxtvsW2FLSx9eUJ+6sLfFLfRqmFfwfKnPHuJv8A732S88z/P54hCbaGktNc9jNWp4AFX8ad0pK
hSTLCHG32MjjTwmnhIa3Tjyqkfve3BYV2BuVQ6PLi112OsG2daZwXH5BpGLIS/9a/4CiBQU86yp6YVsswkWfxPOLgY7FYBqzLZ9uiy7owdSXlJGsDF6UVH
HBSKdQAg660M5L3BqRzWb2fjhGRIG3MfdCzvIl3Ik9Ork9zn+yE2+S8qapoyro23DWKInslfuWAArmO+L8CHfVI/dw2rDOprvy4Ar3BiFFoY1YOdah0cK9
nxFRLpTy6PceW+RNN1OI/bGyT20P0W77tbxdUXq8n5FvAMe/+/7q7tt22jyxt24gJB6iDYh/R193G7GPIjPc7k65rMUly2EkWCEKGIFhxAV8syYseR8tCt
vei/vufMDClS4kWOJTlZPqTNxaLm8jv38zu6P41re6ZMP0EH4y0SjutbqC94WAZRS/VpaJkH+2J4lOlESyUZtc7Vx51+PSIKG2IF+P6Pd8T/hU/xutFvTf
OIEOO+U4sx+OHtP+KIzX9nrZQlD/e/3v1nQgMPCn3pvWAb/P5eVBC8/+0PWd6H6u/Pb1v8lgEIe4ABd3TsKhu+2oSdxmD9+0nvnlCAaD2+f8e9a+Z3vZsb
z8YO91SaslFLaQmNLY07Tu4rjuUKaGrWWzw3ByM7HjFiBDY9UIG/iQN9cvz9ehGHpZnUI/Gifv+d51B+1zj6pNSRMyd2aSefa7JclSMIoPCOkUjQbn8lr8
xX5ldkq8C8R02KEQOd2RXUJbFc4dQecwJ4cZqTdp6HjFlFXlkrSwrQVfxmar7tAhArDPljrFFT5dQ4Wg0D/vWnJ7174AH+U/SPv+WRBY27b0LM9zOeYnJH
4f45jfZff35Kpo3zR8pRjy4NFo1n78IfBSTu8GhGOHf4/XvufTSeGH9nKZe8U/9Yd86+/P3Xn39+Sj2TSavGR06A26A9cqL9t+VMkG/25K1gSsFUSCDwZz
KfTwI1BBvE2V+E60Emwi+YHfqvRXBa1IMA9H6Tk4mJJvV6gUhpa7zg4O0ff7xPatsvvjnutLflQzRORckHWaPhEmzQ0xiuX57w7oF187//jIUkbyA4OeaM
ZVrrPmVn1DUR4OV3NL28s7MvjfY5f67aIKfnYTM17WWZ5rAZkLjJkRrYRsf5rpwnxh8qQIM771pZS3Aapk/gsp7xSDRHA/rrM0HgA5ZEgI0y6K/LfWycH/
IkmAxCCxK64+TRROd14uUyniYqYmT92FmUWwikPkJabhWAkxSi1rCoQF+e8n9/qm2e7foBzxXRUiFuhCB42e+QNsVZSlXIK8pKApbntVtw9aIF6NIc20Lx
dfVAEh765JjPh3hq81MgSzjk5VmhP+PsrbZ5ZpC1DNGrlqgCBDuDDxVX1GZIhibycVohS/kyTruf2Cd66sk6Dn+CxcpikeIUh6gmsYNfUNv+XQCwLxTg6e
mptlZYBVSKccqf4ycNAbaJ8c+Mj/7H+9/evXu/dMUcTQR4uX9beEevakfN6GtAs/TaaW43VYl0g2KqgzP+EvIdqD88OxzDwt2BUmvkSwLUzTODrGuJPsOe
e2b0pP6LGAspdsq8smz9z2XZyqe0kUy0rNXqXPT77YYoDGjLipAKnX7WuDrvdM6vnEe2AmwRgHXGFaDA01pRFbRBxYMRuFan7zwZALPFhmIQa9bRbskAL6
ZNSLE1e6PO7DCH4j5NtO9ju79CXQAgqT259yeliyGts4pyHGEGwMM2Nib8W6LWN64r5kErI0aOUJpR85UV6EvBhHMOLo5Bp1j3MyYc+84OvvveNoUoRmBO
11aA0gbljyFt8f5TnOcVAvA/lgG41BqECRYQLwbGHwp1hNM67tmemu4hXsWfqni6jXX02GihXdW/A/xh/RLITXQIqtzxDmpA6WY8ibys37fAshy6lEMw6h
LiiaQRBRt0qabjoyaj1qwkzIfN+8Ko1n5oANZraIBKg3K9zPo9i23QU0KC4NbQn8QXvMoQDMZjeLLn0QDpwteGtlehjtiHc3yV4tDAkVU5AAx0w3QtCwne
7r8H+KEzcJxIwoqIVS22Whh5CnFZPyTaTQ/0cBBZYa/LdHKTTIt+BRItY08g+Y0h8kbF3/UvEX7Cgz37QQHoOI1GO21PrreSPmbcEhX4FTTCrf6wwY0bs2
gW9DxyFDCWRvezEdBkdYUB3p/AkVh0VAD8LgfjFRXIh14bsFjLtHXifBcAPEfzWgrCKtm5Pla3gr/9Gjly6d4Qu1Mwz2CMknHtoAL9LADBAjUwKa2V6fUv
hMRGdftHBGD9qiW93ONEm60lGi+IPuxyFcjtGSMEm8LTdyGFVhygmD0yGa7AJ3wJcNSdL43GJMGfUdI0u6+RQVNN6rkv/S6NPcHM0N2AGK5p4mK178IArc
ceIK7udTVYk3Pe/Vnt80TA4dFe8NVguj6fmakOass9yGKoJeNm5T6RBODxTgK7e5u/vVhyYHeN+FxOjPWq+sEBnP1ypMt+JT+gKvIAsqcIhx7GNqgcAfIW
R1yKGINzkZUuOCSjqAYJPI45nyIqOIVtcvk5xW+RQBHndxhhGID+Y8++C/zty4Z99AArSyIaZKECJ+3GblX4OYiKr7eg/tCEgG20FCVVbWSZfub6OHFdSH
ma65PMXoP0+fjDARAuHZuN1aapyXjKySmmStbo0AdtoVDPYMzwvWDKp6th891TOBbPmJwnKllf3r59R0SlRxvD10MbpctxbF63i0OgPDUl8BcZJGrmDN1F
EgPs4eTZrDdPjb3rRodH4I0kf1sdvmbJZsimnv7O1DjsMBYZ0XCoDzGEdZNMDuFbay35gI04yKeV3qqLOH29i7DSpgEIXz6CHRkZiQEqho5UK8CajeUiFA
eNxkqCuq7xFAAExz6e1IEFoW+x0bP2hZ+gzgJkotFkxQCW2F0XG2c4uEPijyHFzMqUUcSfeyRblfef3P7kGbUa92/5DWTruHXtJNptEOMA+dh31sfYIYKi
S4F70tsTNX2LPA91YdfTAPxL12JjuSzX8zcWJYt6kPaPBkCnxqc1UQ9z8Njw+OGUDPfsNbzADhnF1hqN5RhddL/u9vnJEGO6/vEPLHZ/i/R8XBMwnUWK6j
4X/MIoI8FsLLxtLWLH+BszzuydHbOtcmJhtwefOiST/Z+unxp/yCx9O3IDEYvmCnANHdDmFffiYh+YZogTSXa0FI1LNax+6ZHbHpl9zgDQdEdZt/STbki/
odTXPkOjGleEWaGzHwuA5yCS+DULkWeIce331cIpflU/2RI8uDSZiMlNUFt/Erfo9b+e4jwDztwF9uexFCDgQ1wiQT4NPYOzG2jEZsUTeg/JTJECxde7yk
Kw8DET4nFdnCdwZB58unpq+PHse4hugNATohuuMrDSJzjE2pAVT19dkw70HUlNp4bTA0QV31DzUz62UIDmrU6uU+Z1bIEaFSn2CYmBynPRzg8FwFnsBU9H
nu0fvJiNLMsK9MrubgnA9Dxoanq6Tg7vd2uZXTv3+4eHnKUA2YkEr2BfynojBpDV82wDvB93VhzRbpEjrvWocqTfCWNULE3Cz+rdeLdgsunz0avw6+TJK2
DOCW/nOWJifgAoNNsjVUZon+hDm8QZ0XkI66L+jopi7mtDGVHGmEOKREuVLqCWfBHnfMIFhXQBS0fBOEwEEI/BqR3ColjjxwHgPi9DkGmvpvhFVMVWLeKC
3DbFviV6gt4iawNSArzZlXXmtPlE0lTTN0lxP+0TfzGXwrX2ens9K+55ybWqPXEVTEP/OTXs2nQDD6BnGyluOM3XPj11CLRFuoLbGTv1sSBL/+reVHgPDU
bs/wE7hbf6zAOKy1QCfTeF2VfC3kJpb3te+HWUBiC1zKNE7u+jFGWxC8hKp/a1kRdNANAgN9bI17fJDbJxAM5T05zlVeUlQVVraIgSotgFhP8d3ensBfgU
Hkuxcmw19tIWGUxm+Ha327V9iRDGoyPXjT78bZTk1THPi2MYvcKKpXPiC5ESCJp7aRmZr+wFpwN/ZGU9u3jzpGEYjEOromJgHHR93z/Ys9yDcjC1iGFZR7
4BWzYIqaDPaV7uqICpQeZSWIfTpqqYUSrAjNEtQ58kut0IIk+4gCenTCNap1Klg04numZRerAV8vVtALBxATdp8Hkp0mdayA5QiSDwJYYhlXcbnUj/xUtT
SmQQWVfbVoLXbewJY3CPpjEJE42C7pwTDzVe46QTzdbY9HN6MkUpABs1MmqiwjvSu4p0a0Fz7s2REQ2Tpd4oMkHcTMdh4NkMod5684SRGPBZRaJE/MKX5w
aElSXDNH3mWqYog46HSTW9nZQxo9OKMTFlubhBin0woKTYB+fWN5UeEYrtuaHtDQuDe42abrseESQ4d55JTSXaZiRwgwB0AH7GwNaDDAJBEmFr8ho2CRY1
aN3B6DLCuNZY8rAAGJqfKeiMw2fONvUDcoyQYWCm3Xgxh3c2BwiCg6MNTIxQXMYmjqIg/qKSegmQKSNQlHvDuOEPtwPZ9HXduO29oukiUcUMsJCRPV0vUv
0wsbATGnDLvdFLAUj0AACY0GyIn7vbVUdVC4381HdOD66jAYmdgzZhU7hLlzaTUwB6mHot8huG4Fx4tm13hUqnKjW+WwDWseizfd9ovK7X4QYz7HsbGYNk
P5DHCCfVL8/pyNVA+8SY2T5Shy2q+VCw0ssX9lw2Kk/OG1tBYR2EB+FtQ6qaBGFjFKov0WbUwMWH34y9UKGxanfdnlHGHjHBqYJDPlpNhl/MHld+Nxalq9
2B0wGskz0RJRxKoNh84WgSGt7XS3sCiO4lAIybjLv6HSE7iSl1apqp5AAQvvkvr1iSoj0nt7LjOQxmnne098q6KapxbJEAySdpSg6bbIs18o8A4Jf+Il4B
0GCkK3wAFQQHNWWw3bV6tyDYr9a6AKMmRm2aKeYiRYm6d3rsLQm3aQt02A2GAbzVltkEGyBDiI1hWsoNrVEQTadRL/DAlGFlEbW+JDOS6SqT40+7cRcRmV
TeGLEegGjeURC/Xsei+WfPnNf1ay6BtCOPDJrx1vOectfTy4MwFzoLXTNj/HV1j45gGTjx/hqe7QoNe2l4gAif75kjcFviMtY3MQD5qHGKg457pAyANGUC
qc0AyZ2+MwDW2xcyXoE8s4aAxkDcTlB86tSzu57n3dpDzlHcWuMUWjyklS3VUiIbOyTALxubpjmNRp7PCsiqHvNggZmnFsFPnMQA/MORjBFhnJAlnASl1p
Zztd/SmA7OFdxpy0XK5uGrHPTF72liDQNpbT0YU7/fl51xvCd8/5CwW8BRaCc8pSp13RCnnVfEQXSj59LFkUX2AU6VUmEZh/uHLXgu+u2Gsx0YXh9qRE5s
XdgrYH72nt+CmfFsERpkZjLBD7skXll7hQDUD6hJReMm/4nPU1AgrTffFQCdc165aA8ux4JrYRoObJxC3I3kElX68oUvIOof2evUUzS05Votfoq67gfTNC
qnIxvV4QYhCLYvIYFSij9ARsg464gIuzWV8Mg7sG0P7llFxI8PbcXhoqaJRS/g4pu0UNUiBF+yrRdzcUrvxK4QnG8eSk/YX6pEoN9NK+wFX1F6vq6KROrE
vglNTDihuRaAnUCxVIFlZyltJ5X007FGbtXPwimnfD4YWMTWEDsknqXdCz8VH0Xf3S/Kb7ZTd4H/wEvmBz4yw30/AMRwYc0OzKVgZ2Ajj7Qq3XFsPo3CML
Rc2iNrJGaxrC9OQEj8TX0425cyN7HQEagWCZts7Dz3GeCjqZY+aIlM7/S0jKA8nU4re/gcMJMMwrzR6Ab0iW5bJfgTan863y4CG5zHCJztcDyl5nR8OcAQ
LPEvFSzzARB5BhN5EqaRqn124CwwheKDOApEcFg1B/+CxsH8hTcIgp+9rs//hdbeAgSfHTPC42I8ZICVRa4VYO54+O/Pnj27bzj117CWwdSeR4u55taeXZ
zba4EsMpXYEaKej4bdSCPafb+PzDEbDgV+AwAv4MvcRkpTSbN88TB0CMjwx3FAjK+XVzva1ZVodd45QBflkqoCKsd/mXbvkxlFyqWhM7ahK9oG/EWKWgVA
FAh3urGIXKpYy8JntZRLl/MaCUcJF5dvmbQC6WDC+1vsDOST4+eDsZqumDAvu6icebYSHYloNOt2vZuwuoKiQ4wwOPB9+4WwVODrj+CjWDcYq0rszpsvvT
lmwhubh+BrrB/3ByGfzudae8GBIUe9StJuwB/GFsJAVq3R6OcDNCoLIY3f3p6NXr58CSqGjsV2zFPafNI+e0IAOrCg5+M477J8ey4NooWKMAfighHLXWNk
b4NoJk0BEPCn654q2yJSbJoyBfdC31CvSJ3HKGk1AOG1Y6Yvwt44qszibeyswredu2bP1kBSM529Mqla8TK0vX2yrVQaJnv8S3X16KYDpmvcEhBJPa7iqV
2RQAL9Hgi/WOgMkB5dXTcGSWA0tmrUSzCQtpGeuG5zFms2tG17iNGIhCrfmM9FdGIuZ+CogayuIMUVvNctMpzxSl9bcNmhw48pWgOjGi9sn79h0q4/EQBx
YkCQpD1XPSXaFfc5BqBq4lTnu0obVFqgSQpAGev6pXhPrPZSjawYFNE3Mz3ogmH9R/XD42GXJK5YlbOScCB4uST4qOketUBZ7oV7cFmL8Kekch+IwPl2Kh
Drh8n5ZSOwiDnzFv2fuCBe4RZ2r4JRuUN8MPuEVS18dF9ncTRuaf9CUOxsGwH9xmLip6QiZy+CiJfhmtHoBeAHrUrc3SjwuvaBF/aKE/Ea6VEriqaxrRPc
CX0e/x40qI0J2w0VZz0QgOD+GVEzD33qAhlsrCxUGQWrnB7oVQRTvHA5+Sk4fZayC5PijHQj+YhsQgc6NTJcB3/SOPRkTYsqs01iIniZev9SIyOuKU2KI0
Ny/L9M6j+GekS2wskF5ufQLHZBLzXZFMZ/x7s1KpLQGjmCEzaThUwN3Z42lQLVjhHe/a0EdZ2r8/P9/f1n+6ig7JGZro5RxwND51PceR4Cvi8OmWOFmoC6
Jk0lVXSfhztSRcrcWiCbCQTuPVD/1Q5RlGQZnrP3qBno/kL8CTk60CuCCnUttgPFpzS7d6aSvvrqCrWmMoI9eLQhcEHSXRiKUgFGOmemEi9O1GpZ5bX/bc
JCXjRquQazaP6uZTZUDmrZRjqwoxFbLbC3RcjdJ9MkpY1OlXlQaoM2aiwyF2Fd0Nz6IMu+mLHhlUu21SznNQ5E5/UUaQUMu0kHRI/rQ5CDwN0rsJ8cVICm
KVnL/0050P2XvH9laTWmR/SN9Io/CICOVjumSg7FuqoqKTMx0IPkkHmsgo6qzEWHkLGSaDqlGd6lr2ouAClaoY+tuof97ipZLbf8fxklpYS8IzAFQMu1Sx
MRfaxWFqqSeHTZ90o82/T/C8+DbZ5krI95azXfCI4zP76f7DZXFTelLu45KFTXNeMKIrivl00lL6OqJJG1bfI83INvt2pg8+TO2NcHTWlt46kN8+HTJgZe
2AVl8iBfJisKfOAm5lg+BIDXrZoWKas3dAFA8afN2V3q79CQqeyGwBiMkkoCdqOMnF7J0IsH3I1HitN2XCW2LFTy8gMc9ba3AkC9DIAXui8B2GNWnuOspD
ZTybD1blpXYE2yqtD8MoAk93p3mchSXN2otBmnA85VAkCq/KxjFEfJjyyJz7/Ut8deeA8O0lgpiKDBhnLZidOTeA39pGBBYIHGY8O7JGzmS0xcUXcTCHwI
APcFydDq/cnAEP9zMEp13yAAq8jNAICpAL8SjZTiS5JwTIM6emy0vkOMHJWerx0EAF++SP59AsAyHTGJAUhvvlJ1laBexpyyC8QXRWTTQ9paNWy4VQsAGP
836ippH7dXKjuxcMt1qfzKJhPmgZKnWuPfelvrl3+tkbmpFB6kMiDCfcD4tdnLlQPXGCezZIb784iNl+RJdrQVLOVihwB0NMk3sXRiOaGEsRdvuXAkHgrA
cWGsIvvYj/UoNNEzq1QnIeKl0cvYXBRR0DU0IGZiXNPshbkjWhIAplxdbijNN6wqHCzbKonxym1QLscKTQDo9kq3mJGRuwDgYEU+C6sobZQq9E4n2ymoB/
0n+tfy3XfaHHR5pxu3yvIznHWwiACAUgD542b205SMBlSV7uOFyd5DtEUtVArDFVnZME6UISh0t9oEdRbVekphgGf1CR7JXe+IuPtqVEnJycMvHDUZkxUA
tOalmupCN1yEH0YUaWykF2nAzAjd7oZJiTvczC9JPipJSoImaZYKABLSc7kJyn8wVGg+ANOLxkPbygDk/aTmvQCAVJlFigQgkhjmrOuMMMu1qBzcGDbVVG
ta1kQRV8J4dBxw7yHawlaypuaSj5Z3gSkWB2FrVjkA6zhdWFUKo5DLXfbyCdnjmpXbhERKfkYuByPLjcYmH+gQlo8F6hMWxQRMVM3bu6WBnUml22CzY0qv
Md5Ey0sNFpN7BSdWFQDh2HrIqR/jltIcwRWfWxw7M9lW5g2ggs9ZX2a3qSmbwlwrH4AOMSyRVcEDVuJzz4SoF2KFR+L7uwKgw3NESq4bs6xBFt8Y04CcYd
6pygNeKiuXMStEs5zSwkaal7eLVgNwRSkoSqFHqGTEABUANCuESxubcgX/mUULS7CXVSCcPj3abMSenx8tzHGuHCrP4PIqpkaZ1YfdcxZdgd/qYcXgpsoa
lYnf8HAW1sIMbuaiYni3EIBosWWSz2pulEzewPlj6SrWB2Cjpk2VRbCsqpwqpQAtc7hGIr7bXLJss8VneRrQdP3HjTMRAFRWgrn5fkR26wWoTEzpOqWpU2
KLXYB7Smmpj5luxDfpLdkoKXGDZ3pUNXdO4arIQTXhVlbatYiHADRpXn9xfugaDMFtzKC51vRuSYYzIwT4ceSGJRzNsOBcE6G0GsfN8ior3mPXsj4A+8RQ
8+bclUYuuBWD7RCfKgGIXSBLebIMAtUVACJx9uP8JMFVkASMFCWTklNKTlJalRZ2qpQewRV2+ri8bLQIgMqqVEN4z8lGfaW/RYhCXXmXvGkp71ZWurq8zq
dUXfWJbYqVVcirlEymwTYAeEbISCmVcAkEcRJjQVgCVPoezwOm5NRSu2+W2Dx4bBjmIQAcpqGvqBXRQ14zjSrCmrHq3E+LaLyjfiVxpGZIdzJekkl7ekUl
dLVWCJVlj0VN/bKkMJJ95/ovCrAosAqANRy1EHAVaFJavFcpgYvTOtFv3mgQpiEyLspqAC3PB+XlIiZnDS4NMYHc5IV2uQUMeSpDNelWNCBX8JUAlIUwoB
S83GOr47AJyzWVZWogJWc9+FnBY53AhwDQVwr9v1ybDffD3fP4Ja0KVnbI8SnhVbyKmm91Z9Lx3JOm7qPbdsCHaeYUZUploK70fMSNZ2FwdMsbjnFAdal5
7dQIziLwj3p7OMK1OOW4ACAy1nPVs9FwvSNGJyx7e1lDK6PgrRvs+ipNNk9gC25xtiFVc+rzcyJXeGw+2QoADbqGBuSSxTKtWzltZzWqBF6t6WYSRkqOQS
3+3kQAXuwIgO3YBC0sZlz+CysaeYeEM4pV6mmHkdMPGrJP0IW0WTbRlFRYGw7SGurkkbmyCRlSJVsxkY225ASGKI083k6uGXzSVcVt6hDt9IOBFfqBmS1b
UPOiVsL8pBx/G52OxQG4jJElG2Oxt9QKsGvOOC1fXp9ox4R5oWvmInBVa8BH35Bt0IY2UiUVJQBEulATW3bzB1BjLpHYoSxGS1XhL0+Vk0FAJL/fFQAxV/
455+YUlMop4y4TKgIp9tk6JoRxempo+ny0lK/ORkEXVloAeCWPjGh/IiThGVxsdUazZ78M5YYnkuEg+nDSYxXhGzYcGqcfTjVdF6yHeXnUBZ8zh58JVrvG
NlsJw3OeBXUAKTkgwpkh9ucyOLqqudM4x0TD3jlLVfLM2SVPED46IFsB4BmWclQBkHsOPc/QyWkBU2YHzooRu2eZK47H8mg5pD6MGNmZCdomBBtNFDUbbc
7Pmk+DA2Q0MHCGEFzAdbrXsdPXOOWXu3tpKoU5QdmUdeQL1dp4JAAB8qLdRCm5mLFmkKxQGuOjxlG+1KpbTOsd/BGcZIasOaOcpS3KXzj6otkdrO14szEY
Ph9dEC+mBuBkqt/kY73ycMYYF4eV16uBS8MBCpoX5TuX2QBkdAD/dBt5wHqtBIBy1gi2GIc2X5tRIDhxQM1zUPvG1z2aKY5fzoAJOwUb5ds7AyBcudtQlh
2VhPNkx6LGJ/3yW7pe72Idqd8RhTgPw0fW6NzqFxV0EMBAF3f6kbK0TWonp8iHHUR0Vc1mTJcwENwmBp/aJZ7JepNznHPBUGQca0h38HPuu/jlN61wJm7/
8aZLQa81cnJM/FlIf0ljcJFDxztl9WZcBOLhYY/rReX6nE8IQbizOvEHES0UnGIPu8hOvZWxe2eg4Gmugl+s0IyOhvAFbGStqLUL06UElgP3ayjuRF7CSG
xW74CwRw/xfFAekIsGbzSmBZVhIOAu8QB1HHGcUGisP96p3rj4hFYryF6kEmC+7f08ugyj8Xg6nY6j8HI08DgnADhUBletj6ZmahGG5iF85Tt42ctoatJM
OQo1x+FlEL9VM/hQ+FqrM0GyvQfI58Z5CymZT0/wXbCy7mwU8QqZ+OqbVvQK3nPH2Q/45N1NDzgBCXpyAp97Z89GoaCTVxPkuVY4mh1wvgWDW9bwfFrv5J
CjSzP4sDZiHAShmXc9UIDdGvxsta3w3bxGARfkmBdyia7FrRc8BBSgxYZLvU+49IF/iWrAzQrLOAgOnzbXuTDZWSUMZgpOPxzjEd353UGAwJjyaBnHRoDY
4LpBO+YAInC3J/2HzgyvO40WHtPJB/EhGaYBOUiIz87Cv9xAT/K1eNsJmlv805nh+wcvuvC8sJHxlMnXaoaYLEe+mT3+2unguz58QNEhyYbhZTY+/vyOCa
JAfA0fzLd5TphzuFWwr4IUBQfQeN5sNvM8r2v7d3ydQsKgYGs/gMuzvm8gJUR87sw46M7k9ZhOoygcBUiMRrjURM2+Hca3T4Q7ozMxb4Mr+F9+EdIl4rKF
Wy/wRWu1VrlkuW5MxD3mgsiwvWAURnE9IawnmAlbSDMeb4I9BIDIn6nxu6+xmA9bTveRQ7aYvKVsLeOlWNe2RPAG7uoHOapVPnLstZDQbCPEONf7fJcB8R
9O8JO1JdQzjveDD/FbtfNHXB/Oxwl7eMLfBfuYohaH4zzFvxBjMbcyLr7BdRWKm+P0uxfLhD9GLrEHc4/XX795cw9XWwpOjTONZiY/CQGGa9MOt8P35oDp
yDePsTkXLp6ULXPGwa8Jze58XIdX0Gm3O+I7x+YA4xzGTO4ak7bQ42uVHtSQe68JBffh+fPnYiSjxh+BDNs+gD9iD/CNinUFGGxikEYCOvG+BPuT842JUW
dfXHl8E8Aw9RwcyPdKzh+ttf9Yellnn5NyivuOI7yT54TPpOXL0zqNLTFJ4/wq3FbcVPluubfxRfv26Rviw/GzPySSkz9iJpgQYNr+1vrhUW8dixdJa0Ji
RYsD1oCXB6zN6YM/VNOOF3cPb6O8juKkNjA892GcMPU3HW0FF6cxFon0HDYyP6X+5l7c1ZVHQ8N2oxcUAc+S49Jifaul1CFrddqboWS9dhqdZGHa4on/pH
W11SlQdUdOFSDLr2bg1j7y1dzVrdWkUD6OoS3vRm1TW1j09naL383jzN08juUnuLQPfXtmr9ACEzgU+3WxkXu+9/D70+5PGMtDBgYmnE1fFz5/CZ5+H35p
NLZ3gk6jfTGZLC9sMrm46DcaGxfbDmzjBbxPXH24s61Whw9R+HUXD59q1YcvIB/0+DZnUYidTO/ip8mOluY0+hfynWBL12q1WCl8O/RhNf2LScoz+XTx1w
b5sb9tOMt1/YyfoHgQGc7Zx/oTzpbccEjbEc9u3vYRn1//vz3X8T7CAn/d9c0AHJ53OiA6+3g1N/D667p4Pm58Lf8HzN1bWID7ATgAAAAASUVORK5CYII=
]]
local AGENT_SND_B64 = {
    appear = [[
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
QACXAOAAEgE=
]],
    blip1 = [[
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
]],
    blip2 = [[
UklGRsAIAABXQVZFZm10IBAAAAABAAEAIlYAAESsAAACABAAZGF0YZwIAAAAADIAxACiAbMC2wMBBRIGDgdHByUGzwRwAzICNQGKAC0ABQDn/5T/zf5U/f
b6mvc/8wPu/eha6CPosOhL6iXtSvGi9u780APYCpIRlReSHGMgEiPXJBYm2x4rFyYQPwq+BbUC/wA9AOb/VP/c/eb6APbv7rvlstpYzkDKV8q+yxfPydR+
3U3ocvQzAcENVBlEIx4rtzArNN01aDZ6MHMkoRmTEJ4J0QT1AZQACwCe/4/+Ovwq+CfyPOq34BvWBc7Uzn7QktNq2CXfnud08Rr85QYmET8auiFVJw0rHC
3wLdYtYiOxGU0RlQqzBZIC5QAxAN//Sv/c/R/7yvbM8E/pruBt1wDWBNcI2W7caOHw58vvkfi4Aa0K4hLgGVsfNyOPJa0mBCfrIVwZtBFZC4IGNANFAVwA
AgCv/9v+FP0K+pn1zu/j6DvhN9zU3Brea+AF5PjoJe9F9vD9pwXyDF8TnRiBHAwfbCD1ICUgrxjPEeULNAfTA7ABkgAdAOL/bf9U/kP8C/mk9C/v8ehJ4v
HhuOI/5Mnmduo+7/P0SPvYATwIDA73EskWchkIG8Qb+hu4F6EROQzDB2UEIQLTADkA/v+9/xj/vv15+zL49fPv7mrpYebZ5tLnkOk87N/vX/SI+Qv/kAS+
CUcO8hGkFGEWTRekF4gWNRFWDCwI5QSQAhwBXQAQAOb/iv+y/iT9wfqG94zzCO8/6n3qFus+7CPu2vBZ9H34Dv3DAVAGbgrjDYwQYBJzE+4TDxSVEEAMbg
hOBfcCaQGIACMA/P/J/0n/Qv6R/Cb6Dfdo827vqO0F7sLuEfAM8rf0//e6+7H/ogNPB4IKEw3xDiEQvRD0EMkP/guKCJwFUwO2AbkAOgAIAOr/ov/8/tH9
DPyt+cn2hfNi8JzwEfHx8VrzWvXo9+r6Nf6UAdEEuwcoCgIMRA39DU0OYg6VC4IIzwWfA/8B7wBXABUA+//T/3D/qf5m/Z77W/m39tnz3vIl87bzsfQo9h
34gPoz/QsA3AJ5BboHhQnPCp4LBgwpDA4LWgjoBdkDQQIkAXkAJQAEAO3/tf82/1b+B/1K+y/50/bR9P30V/UA9g33hvhk+pL88f5bAakDuAVsB7YIkwkP
CkMKTwoWCOcFAAR4AlgBnQA4AA0A+//c/4//+f4I/rj8Evso+Rj3mfbQ9j73+vcQ+X/6O/wu/jkAPAIWBKwF7QbRB14Iogi4CL0H0AUVBKMChgHDAE8AFw
ABAPD/xP9j/7z+xP1+/Pb6Qvn+9yD4Zfjk+Kz5wfoe/LL9Z/8hAcUCOgRsBVAG6AY7B10HUQelBRgEwQKuAecAaAAkAAcA+//j/6f/Nv+D/oz9WPz2+nr5
Rvlw+cP5UPod+yr8bf3V/kwAuwELAykECQWmBQYGMwZABmoFCwTSAs4BCAGBADMADgAAAPP/0f+H/wn/Uv5k/Uf8DftE+l76k/rz+of7U/xR/Xb+sf/sAB
cCHgP0A5ME+wQyBUgFIgXwA9YC5AEkAZsARAAXAAQA/P/o/7v/Zf/h/iv+S/1K/Dn7L/tQ+4/7+PuP/FT9P/5D/08AVQFDAg0DqQMVBFUEcwR7BMkDzwLy
ATwBsgBWACEACQAAAPX/2/+j/0X/vv4P/kH9Xvzl+/n7Ifxp/Nf8bf0m/vr+3f++AJIBTALiAlADlwO8A8oDmQO+AvcBTAHHAGcALAAOAAIA/P/t/8r/iv
8n/6L+//1F/YL8jvyn/Nf8Jf2V/SX+z/6L/0sABQGuATsCqALzAh4DMQM3A6UC9AFXAdcAeAA5ABUABQAAAPf/4/+4/3L/D/+P/vn9Vv0Q/R/9Pv10/cX9
M/66/lT/9v+XAC4BsQEaAmYClgKvArcChQLpAVwB5ACHAEUAHQAJAAEA/f/x/9b/pv9d//v+hP7+/YD9if2c/cD9+/1N/rb+Mv+5/0IAxwA+AaIB7QEhAj
4CSwJOAtkBWwHsAJMAUQAlAA0AAwAAAPn/6f/J/5X/S//u/oL+DP7m/fH9Cf4x/m7+vv4g/4//AwB3AOIAPgGHAbwB3QHtAfMBwwFVAfAAnABbAC4AEwAF
AAAA/f/0/+D/u/+F/z7/5/6G/jb+Pf5L/mf+kv7P/hz/df/X/zkAlwDrADEBZgGJAZ0BpQGnAUoB8ACjAGQANgAYAAgAAgAAAPr/7v/W/6//ef81/+b+kv
5//oj+mf64/uX+IP9n/7f/CgBcAKgA6QAcAUEBVwFiAWUBPAHtAKYAawA+AB4ADAADAAAA/v/3/+f/zP+k/3D/Mf/r/rj+vf7J/t3+/f4q/2L/o//p/y8A
cgCuAN8AAwEbASgBLgErAeYApwBwAEQAJAAQAAUAAQAAAPz/8v/g/8P/m/9q/zH/9P7s/vP+Af8X/zj/ZP+Y/9H/DQBIAH0AqwDPAOgA9wD+AAAB3QClAH
MASQApABQACAACAAAA/v/5/+3/2f+7/5X/Z/81/xX/Gf8i/zH/Sf9q/5P/wv/1/yYAVgCAAKIAvADMANUA2ADRAKAAcwBNAC4AGAAKAAMAAAAAAP3/9f/n
/9L/tf+R/2f/PP87/0D/Sv9b/3T/k/+5/+P/DQA3AF0AfQCWAKcAsgC2ALgAmgByAE8AMgAcAA0ABQABAAAA///6//H/4v/M/7D/j/9r/1j/W/9i/23/f/
+X/7X/1//7/x8AQQBeAHYAiACTAJkAmwCTAHAAUAA0AB8AEAAHAAIAAAAAAP3/+P/t/93/yP+u/5D/cf9z/3f/f/+L/53/tf/Q/+7/DAAqAEUAWwBtAHkA
gACDAIMAbABPADYAIgATAAkAAwAAAAAA///8//X/6f/Z/8X/rf+T/4j/iv+P/5j/pf+3/83/5f///xgAMABFAFYAYgBqAG4AbwBnAE4ANwAkABUACwAEAA
EAAAAAAP7/+v/y/+b/1v/D/67/mv+b/57/pP+u/7v/zP/g/w==
]],
    blip3 = [[
UklGRsAIAABXQVZFZm10IBAAAAABAAEAIlYAAESsAAACABAAZGF0YZwIAAAAAD0A6gDnAQsDMAQ+BTMGSwX7A54CcQGeAC0AAwDf/2X/N/4D/Jr4APRt7q
3sbOwd7SfvwfLe9yv+HgUODFUScRciG30d7B4fGnASoAtLBrwC2QAiAMj/0f5L/Hz3C/AW5i/a6tMR1PLVZtrX4SjssfhiBvQTJSD7KfowPzV/N5UyMiT5
FqAMswXoAWIA2P/V/gf8ePbE7STiZ9TEye/Kwc0w06fb+eZn9MYCwBAPHcAmYC0TMYgyDjE8I/QWJw1PBlICjgD7/1T/Z/1C+Wjy5+hS3abQVdFP02DXC9
5L55ryCP9uC6gWyR9LJioq4StRLOQhuRaIDdoGvQLBABMAo/9Z/lH7/fVK7prktdkK12bYZduV4BLohfEy/B8HSBHMGRwgFSQGJp0mYyBNFsINUgcmA/oA
KgDS//z+z/y6+I3yg+o14RrcBt0x3yzjLukD8R36rAPNDK0Uuxq8HtwgniHCHrgV2A20B4oDOAFCAO//Zv/g/cv65PVH72XnkOAx4bviv+WD6vTwqPj3AB
oJVBASFgwaThw7HQod/xTLDf4H5QN4AV4AAQCp/5/+Vvx++Bnzd+wn5e3k/+U+6PzrPPG19+H+FQaoDA0S8RVLGF4ZqBkoFJ8NMgg2BLgBfgAPANL/Iv94
/X76IvaZ8FLqP+j76KDqh+3E8Sr3T/2lA5UJmg5dEsQU9xVaFjoTVg1PCHoE9wGhAB0A6v95/0n+A/yH+PLzme4w66/r3+wX73ry8fYs/LQBBweoC0APqR
H3EnQTOhL2DFUIsQQyAsYALAD6/7H/3v4p/Wf6pPYf8sftHu707qDwT/P49mP7LwDsBCkJjwzxDlIQ6BALEYEMSAjaBGcC7QA+AAMA1P9G/wP+2/vM+AD1
yfBL8N/wHfI29DD35PoH/zUDDwc+CpEM/g2qDtoO+wsoCPUElQIUAVEACwDp/4z/ov75/IL6Wfe88zryn/KH8yX1i/eg+in+1QFNBUEIfgryC7AM8AxpC/
kHAwW8AjkBZwAUAPb/uv8V/9H92vs++Sz27/M09Nr0Fvb/94r6iv29ANcDkAayCCUK8gpBC8wKuwcDBdsCXAF+AB0A/v/Y/2b/dP7n/MT6Lfhw9Z/1FPYB
94P4l/of/eX/pQIhBSQHkQhpCcYJ3glxB/gE8QJ7AZUAKAADAOr/nv/s/rf9/PvQ+WH35PY09+P3EPm/+t78QP+tAe0DzgUxBw4IeQiZCB4H4gT/ApUBrA
A0AAgA9f/D/0T/Vv7y/CT7EPkE+Dr4ufig+fv6vfzG/uYA7AKpBP4F3gZTB3wHxAbDBAUDqwHCAEIADQD8/9z/gv/P/rT9N/x0+gH5J/mB+TH6RPu3/HD+
SQAXArED9ATTBVAGggZlBpsEAwO8AdcAUAATAAAA7P+u/yn/Sv4U/Zf79vn7+Tr6vfqW+8T8N/7Q/2oB3gIPBOkEbAWnBbYFbQT7AsgB6QBeABoAAgD1/8
z/a/++/sP9hfwf+7j64/pD++v74PwW/nX/3QAuAkkDHQSjBOUE+gQ6BOwCzwH4AGsAIgAFAPv/4f+b/xf/Tv5G/RT8X/t8+8L7Q/wG/Qf+Mv9tAJsBoQJr
A/IDOgRVBAME1wLRAQQBeAAqAAkA///u/73/Wv+6/uL93/zy+wb8OPyZ/DT9B/4E/xUAIgESAtICVwOkA8QDyAO+As8BDgGEADIADAAAAPb/1f+L/w7/Xv
6F/ZT8gvyk/O38Zv0S/ub+0v+/AJoBTQLQAh8DRANOA6ICyQEUAY8AOwARAAIA+//l/7D/T//B/gz+Pf3w/Af9PP2a/ST+1f6g/3AANQHcAVoCqwLUAuEC
ggK/ARcBlwBDABUABAD+//D/yv+A/w//ef7J/VH9Yf2H/c/9Pf7P/nv/MQDhAHsB8wFEAnACgQJgArIBGAGeAEoAGgAGAAAA9//d/6X/TP/R/jz+p/2y/c
z9Av5a/tH+Yv8AAJwAKQGaAeoBGQItAjICogEWAaQAUQAfAAgAAAD7/+n/wf97/xf/m/4Q/vr9DP40/nj+2f5T/9v/ZADkAE4BnAHMAeMB6gGQAREBpwBX
ACUACwABAP7/8v/V/5//T//n/nD+Ov5G/mP+mP7m/kv/v/83AKoADQFYAYgBogGqAX0BCwGoAFwAKQAOAAIA///4/+P/uv96/yX/wP5y/nv+j/63/vX+Sf
+r/xQAewDVABwBTQFoAXMBaAECAagAYAAuABEABAAAAPz/7f/P/53/V/8C/6X+qv64/tb+B/9L/57/+f9UAKYA6QAZATUBQgFFAfkApgBjADIAFAAFAAAA
/v/0/97/t/9+/zf/5/7U/t3+9P4a/1H/lv/l/zQAfgC9AOsACQEXARsB7QCjAGUANQAXAAcAAQD///n/6f/L/57/Y/8e//n+//4P/y3/Wf+S/9X/GwBeAJ
cAxADhAPEA9wDiAJ8AZQA4ABoACAABAAAA/P/x/9r/tv+G/0z/Gf8e/yn/QP9j/5L/y/8HAEIAdwCiAL8A0ADWANUAmgBlADoAHAAKAAIAAAD+//b/5v/J
/6L/cf87/zr/Qf9S/23/lP/E//j/LABdAIQAoQCyALoAvACUAGQAPAAeAAwAAwAAAP//+v/u/9j/uP+P/2H/Uv9X/2P/ef+Y/8D/7f8aAEYAawCGAJgAoQ
CkAI0AYgA9ACAADgAEAAAAAAD9//T/4//K/6j/gf9o/2v/dP+E/53/vv/k/wwAMwBVAHAAgQCLAI4AhQBfAD0AIgAQAAUAAQAAAP7/+P/s/9f/vP+a/3v/
ff+D/5D/o/++/9//AQAkAEMAXABtAHcAfAB9AFsAPAAjABEABgABAAAA///7//L/4v/M/7D/kf+N/5H/mv+q/8D/2//5/xcAMwBLAFwAZgBrAG0AWAA7AC
QAEwAHAAIAAAAAAP3/9v/q/9j/wf+m/5v/nv+l/7H/wv/Z/w==
]],
    good = [[
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
/Kj8Uv1r/sj/LgFhAi4DgAM=
]],
    bad = [[
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
35/KX8Uvz/+6z7WvsH+7X6rPoC+1f7rfsC/Ff8q/z//FP9p/37/U7+of70/kb/mP/q/zsAjADeAC4BfwHQASACcAK/Ag8DXgOtA/sDSgSYBOYEMAXeBI0E
PATrA5sDSgP6AqoCWwILArwBbQEfAdAAggA0AOj/mv9N/wD/tP5n/hv+z/2D/Tj97fyi/Ff8DfzC+3j7LvtB+4/73Psp/HX8wvwO/Vr9pf3x/Tz+h/7R/h
z/Zv+w//r/QgCMANUAHgFmAa8B9wE/AoYCzgIVA1wDowPqAzAEdgSfBFUEDATDA3oDMgPpAqECWQISAsoBgwE8AfUArwBpACIA3v+Y/1L/Df/I/oP+P/76
/bb9cv0v/ev8qPxl/CL83/ud+8f7DPxS/Jf83Pwg/WX9qf3t/TH+df64/vz+P/+B/8T/BgBIAIoAzAANAU4BkAHRARECUgKSAtICEgNSA5ID0QMQBB0E2w
OZA1gDFgPVApQCUwISAtEBkQFRAREB0QCSAFMAFADW/5f/WP8a/9z+nv5g/iP+5f2o/Wv9Lv3y/LX8efw9/AH8Pfx8/Lv8+fw3/XX9sv3w/S3+av6n/uT+
If9d/5n/1f8QAEsAhwDCAP0AOAFzAa0B5wEiAlsClQLPAggDQQN6A7MDqgNuAzMD+AK9AoICRwINAtMBmQFfASUB7ACyAHkAQAAHAND/l/9f/yf/7/63/n
/+SP4R/tr9o/1s/Tb9//zJ/JP8b/yn/OD8GP1Q/Yj9wP33/S7+Zv6d/tP+Cv9B/3f/rf/j/xgATgCDALgA7gAjAVcBjAHAAfUBKQJdApECxAL4AisDXgND
Aw0D2AKjAm4COQIEAs8BmwFnATIB/wDLAJcAZAAwAP7/y/+Y/2b/M/8B/8/+nf5r/jn+B/7W/aX9dP1D/RL94fzT/Ab9OP1r/Z390P0C/jT+Zv6X/sn++v
4s/13/jv++/+//HgBPAH8ArwDfAA4BPgFtAZ0BzAH7ASkCWAKHArUC4wIRA+cCtwKHAlcCJwL4AcgBmQFpAToBCwHdAK4AgABRACMA9v/I/5r/bf8//xL/
5f64/ov+Xv4x/gX+2f2s/YD9VP0p/Sz9Wv2H/bX94v0Q/j3+av6X/sP+8P4c/0n/df+h/83/+f8jAE8AegClANAA+wAmAVEBewGmAdAB+gEkAk4CeAKhAs
EClgJqAj8CFALpAb4BkwFoAT4BEwHpAL8AlQBrAEIAGADw/8b/nf90/0v/Iv/6/tH+qf6A/lj+MP4I/uD9uf2R/Wr9e/2l/c799/0g/kj+cf6a/sL+6v4S
/zr/Yv+K/7L/2f8AACcATgB1AJwAwwDpABABNgFdAYMBqQHPAfQBGgJAAmUCdAJNAiYC/wHYAbEBigFkAT4BFwHxAMsApQB/AFoANAAPAOr/xf+g/3v/Vv
8y/w3/6f7E/qD+fP5Y/jT+EP7s/cn9pf3C/ef9DP4x/lb+e/6f/sT+6P4M/zH/Vf94/5z/wP/j/wYAKQBNAHAAkwC2ANgA+wAeAUABYgGFAacByQHrAQ0C
LgIvAgwC6QHGAaMBgAFdAToBGAH1ANMAsQCPAG0ASwApAAcA5//F/6T/gv9h/0D/H//+/t7+vf6c/nz+XP47/hv++/3g/QH+I/5E/mX+hv6n/sj+6f4K/y
v/S/9r/4z/rP/M/+z/CwArAEsAagCKAKkAyQDoAAcBJgFFAWQBggGhAcAB3gH8AfIB0gGyAZMBcwFUATUBFQH2ANcAuACaAHsAXAA+AB8AAQDk/8X/p/+J
/2z/Tv8w/xP/9f7Y/rr+nf6A/mP+Rv4p/hv+Of5Y/nb+k/6x/s/+7f4K/yj/Rf9i/4D/nf+6/9f/8/8PACwASABlAIEAngC6ANYA8gAOASoBRQFhAX0BmA
G0Ac8BuwGfAYIBZgFJAS0BEQH1ANkAvQChAIUAagBOADIAFwD9/+L/xv+r/5D/dv9b/0D/Jf8L//D+1v68/qH+h/5t/lP+UP5s/of+ov69/tf+8v4N/yj/
Qv9c/3f/kf+r/8X/3//5/xIALABGAF8AeQCSAKwAxQDeAPgAEQEqAUMBWwF0AY0BpAGKAXEBVwE9ASQBCgHxANgAvwClAIwAcwBaAEIAKQAQAPn/4P/I/6
//l/9//2f/T/83/x//B//v/tj+wP6o/pH+ev6A/pj+sf7J/uH++f4R/yn/Qf9Z/3H/if+g/7j/0P/n//7/FQAsAEMAWgBxAIgAnwC2AMwA4wD6ABABJwE9
AVMBaQF2AV8BSAExARoBAwHsANUAvgCnAJEAegBkAE0ANwAhAAsA9f/f/8n/s/+e/4j/cv9c/0f/Mf8c/wf/8f7c/sf+sv6d/qr+wP7W/uz+Av8X/y3/Q/
9Y/27/g/+Z/67/w//Y/+3/AQAWACsAQABVAGoAfgCTAKcAvADQAOQA+QANASEBNQFJAU0BOAEjAQ8B+gDlANEAvACoAJMAfwBqAFYAQgAuABoABgDz/9//
y/+4/6T/kP8AAAkAJwBYAJ0A9gBiAeIBdgIdA9gDpwSJBX8GiQenCNgJHQt1DOINYg/1EP0Q4BCwEGwQFBCoDykPlg7wDTUNZwyGC5AKhwlrCDoH9gWeBD
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
X0SPTb9G/1AvaV9ij3u/dN+OD4cvkE+pb6KPu6+0z83fxv/QD+kf4i/7P/QwDUAGQB9AGFAhUDpQM0BMQEVAXjBXIGAgeRByAIrgg9CcsJWgroCnYLigv6
CmkK2QlICbgIKAiZBwkHeQbqBVsFywQ8BK0DHwOQAgICcwHlAFcAyv88/67+If6T/Qb9efzr+1/70vpF+rj5LPmg+BT4iPf89nD25PVZ9c30o/Qx9b/1TP
ba9mf39PeB+A75m/ko+rT6QfvN+1n85fxx/f39if4U/6D/KgC1AEABywFWAuECawP1A4AECgWUBR4GpwYxB7sHRAjNCFYJ3wloCvEKMAulChoKjwkECXoI
7wdlB9sGUQbHBT0FswQpBKADFgONAgQCewHyAGkA4v9Z/9H+Sf7B/Tn9sfwp/KH7GvuS+gv6hPn9+Hb47/dp9+L2XPbW9VD1/PSE9Qz2lfYd96X3Lfi0+D
z5xPlL+tL6Wfvg+2f87vx1/fv9gv4I/47/EwCZAB8BpAEqAq8CNAO6Az8ExARIBc0FUgbWBloH3gdiCOYIagnuCXEK2QpTCs0JSAnCCD0IuAcyB60GKAak
BR8FmgQWBJIDDgOJAgYCggH+AHoA+P91//H+bv7r/Wj95vxj/OH7Xvvc+lr62PlW+dT4U/jR91D3zvZN9sz1UvXV9Vj22/Ze9+H3ZPjm+Gn56/lu+vD6cv
v0+3X89/x5/fr9e/79/n7///9+AP8AgAEAAoECAQOBAwEEgQQBBYAFAAZ/Bv4Gfgf9B3wI+gh5CfgJdgoECoMJAgmCCAEIgQcBB4EGAQaBBQIFggQDBIMD
BAOFAgYChwEJAYoADACO/xD/kv4U/pb9GP2a/B38n/si+6X6KPqr+S75sfg1+Lj3PPe/9kP2x/Uj9qL2IPee9xz4mvgX+ZX5EvqQ+g37ivsH/IT8Af19/f
r9dv7y/m//6/9mAOIAXQHZAVQC0AJLA8YDQQS8BDcFsgUsBqcGIQebBxYIkAgKCYMJ/Qm2CToJvghDCMcHTAfRBlYG2gVgBeUEagTvA3UD+wKAAgYCjAES
AZgAHwCm/y3/s/46/sH9SP3P/Fb83ftl++z6dPr8+YP5C/mT+Bz4pPcs97X2PvZw9un2Y/fc91X4zvhH+cD5Ofqx+ir7ovsa/JL8Cv2C/fr9cv7q/mH/2P
9PAMYAPQG0ASsCoQIYA48DBQR7BPEEZwXdBVMGyQY/B7QHKgifCBQJiQlrCfQIfQgGCI8HGAehBisGtQU+BcgEUgTcA2YD8AJ7AgUCkAEbAaUAMAC8/0f/
0/5e/un9df0A/Yz8GPyk+zD7vPpJ+tX5Yfnu+Hv4CPiV9yL3r/a69i/3pPcY+I34Afl2+er5XvrS+kb7uvsu/KH8Ff2I/fv9b/7i/lX/yP85AKwAHwGRAQ
MCdgLoAloDzAM9BK8EIQWSBQQGdQbmBlcHyAc5CKoIGwkiCa8IPAjKB1gH5QZzBgEGjwUeBawEOgTJA1cD5gJ1AgQCkwEiAbEAQADR/2D/8P6A/hD+oP0w
/cD8UPzg+3H7AfuS+iP6tPlF+db4Z/j494r3G/cC93P34/dT+MP4M/mj+RP6g/rz+mL70vtB/LD8H/2O/f39bP7b/kn/uP8lAJQAAgFwAd4BTAK6AigDlQ
MDBHAE3QRLBbgFJQaSBv4GawfYB0QIsQjbCGwI/geQByIHtAZGBtkFawX9BJAEIwS1A0gD2wJuAgIClQEoAbwATwDk/3j/DP+g/jT+yP1c/fH8hfwa/K77
Q/vY+m36AvqX+Sz5wvhX+O33gvdI97T3IPiM+Pj4ZPnQ+Tz6p/oS+3776ftU/L/8Kv2V/QD+av7V/j//qv8TAH0A5wBRAbsBJQKOAvgCYQPLAzQEnQQGBW
8F2AVBBqoGEgd7B+MHTAiWCCsIwQdXB+4GhAYaBrEFRwXeBHQECwSiAzkD0AJoAv8BlgEuAcUAXQD2/47/Jv++/lb+7v2G/R/9t/xQ/On7gvsb+7T6Tfrm
+X/5Gfmy+Ez45feM9/T3XPjE+Cz5lPn7+WP6yvoy+5n7APxn/M78Nf2c/QP+af7Q/jb/nf8CAGgAzgA0AZoBAAJlAssCMAOWA/sDYATFBCoFjwX0BVkGvQ
YiB4YH6wdPCOwHhgcgB7sGVQbvBYoFJAW/BFkE9AOPAyoDxQJgAvwBlwEyAc4AagAFAKL/Pv/a/nb+Ev6u/Uv95/yE/CD8vfta+/f6lPox+s75bPkJ+ab4
RPji9zL4lvj6+F75wvkm+or67fpR+7T7F/x6/N78Qf2j/Qb+af7M/i7/kf/z/1QAtgAZAXsB3AE+AqACAgNjA8UDJgSHBOkESgWrBQwGbAbNBi4HjgfvB6
8HTQfrBokGJwbFBWMFAgWgBD8E3QN8AxsDugJZAvgBlwE2AdYAdQAUALX/Vf/1/pT+NP7U/XX9Ff21/FX89vuX+zf72Pp5+hr6u/lc+f34nvhA+G/4z/gv
+Y/57/lP+q/6D/tv+877LvyN/O38TP2r/Qr+af7I/if/hv/k/0IAoAD/AF0BuwEZAncC1QIzA5ED7wNMBKoEBwVlBcIFHwZ8BtkGNgeTB3QHFQe3BlkG+g
WcBT4F4ASCBCUExwNpAwwDrgJRAvQBlgE5AdwAfwAjAMf/av8O/7H+Vf74/Zz9QP3k/Ij8LPzQ+3T7Gfu9+mL6Bvqr+VD59fiZ+Kn4Bvlj+b/5HPp4+tT6
MPuM++j7RPyg/Pz8WP2z/Q/+av7F/iH/fP/X/zEAjADnAEEBnAH2AVECqwIGA2ADugMUBG4EyAQiBXwF1QUvBogG4gY7BzoH3waEBikGzwV0BRoFvwRlBA
sEsQNWA/wCowJJAu8BlQE8AeIAiQAwANf/fv8l/8z+c/4a/sL9af0Q/bj8X/wH/K/7Vvv++qb6Tvr3+Z/5R/nv+OL4PPmV+e75R/qf+vj6Ufuq+wL8Wvyz
/Av9Y/27/RP+a/7D/hv/c//K/yEAeADQACcBfgHVASwCgwLaAjEDiAPfAzUEjATiBDgFjwXlBTsGkQbnBgIHqgZTBvsFpAVNBfYEnwRIBPEDmwNEA+0Clw
JAAuoBlAE+AecAkQA7AOf/kf87/+X+kP46/uX9kP06/eX8kPw7/Ob7kfs9++j6k/o/+ur5lvlC+Rr5cPnF+Rv6cfrG+hv7cfvG+xv8cPzF/Br9b/3E/Rn+
bf7C/hb/a/+//xIAZgC6AA4BYgG2AQoCXgKxAgUDWAOsA/8DUgSlBPgESwWeBfEFRAaXBssGdwYjBs8FewUnBdMEgAQsBNgDhQMyA94CiwI4AuUBkgE/Ae
wAmQBGAPX/ov9Q//3+q/5Z/gf+tf1j/RH9v/xt/Bv8yvt4+yb71fqE+jL64fmQ+VD5ovn1+Uf6mfrs+j77kPvi+zT8hvzY/Cn9e/3N/R7+b/7B/hL/Y/+0
/wQAVQCmAPcASAGZAekBOgKKAtsCKwN7A8sDGwRrBLsECwVbBasF+gVKBpYGRQb0BaMFUwUCBbEEYQQQBMADcAMfA88CfwIvAt8BjwE/AfAAoABRAAEAs/
9j/xT/xf52/if+2P2J/Tr96/yc/E78//ux+2L7FPvG+nf6Kfrb+Y350/kj+nL6wfoQ+1/7rvv9+0z8m/zq/Dj9h/3V/ST+cv7A/g//Xf+r//n/RgCUAOEA
LwF9AcoBGAJlArICAANNA5oD5wM0BIEEzgQbBWcFtAUBBk0GFQbHBXkFKwXeBJAEQwT1A6gDWwMNA8ACcwImAtkBjAFAAfMApgBaAA0Awv91/yn/3f6R/k
X++f2t/WH9Ff3J/H78Mvzn+5v7UPsE+7n6bvoj+tj5A/pP+pz66Po0+4D7zPsY/GT8sPz8/Ef9k/3e/Sr+df7A/gz/V/+i/+3/NwCCAM0AGAFiAa0B9wFC
AowC1wIhA2sDtQP/A0kEkwTdBCcFcQW6BQQG5gWbBVAFBQW6BHAEJQTbA5ADRgP8ArECZwIdAtMBiQE/AfYArABiABgA0P+G/z3/9P6q/mH+GP7P/Yb9Pf
30/Kv8Y/wa/NH7iftA+/j6sPpo+h/6Mvp7+sT6DvtX+6D76fsy/Hv8xPwN/Vb9n/3n/TD+ef7B/gn/Uv+a/+L/KQBxALkAAQFJAZEB2QEgAmgCsAL3Aj4D
hgPNAxQEWwSjBOoEMAV3Bb4FuAVwBSgF4ASYBFAECATBA3kDMgPqAqMCWwIUAs0BhgE/AfgAsQBqACMA3f+W/1D/Cf/D/nz+Nv7w/an9Y/0d/df8kfxL/A
X8wPt6+zT77/qp+mT6X/ql+uz6Mvt5+7/7BvxM/JL82fwf/WX9q/3x/Tb+fP7C/gj/Tf+T/9j/HQBiAKcA7AAyAXcBvAEBAkYCigLPAhQDWQOdA+IDJgRr
BK8E8wQ3BXsFiwVGBQEFuwR2BDEE7AOnA2IDHgPZApQCTwILAsYBggE9AfkAtQBxACwA6f+l/2H/Hv/a/pb+Uv4P/sv9h/1E/QH9vfx6/Df89Pux+277K/
vo+qX6ivrO+hL7Vvua+977Ivxl/Kn87Pww/XP9t/36/T3+gP7D/gb/Sf+M/8//EQBUAJYA2QAbAV4BoAHjASUCZwKpAusCLQNvA7ED8wM1BHcEuAT6BDwF
YAUdBdsEmARWBBME0QOOA0wDCgPIAoYCRAICAsABfgE8AfoAuAB3ADUA9f+z/3L/Mf/v/q7+bf4s/uv9qv1p/Sj95/yn/Gb8Jfzl+6T7ZPsj++P6tfr2+j
j7efu6+/z7Pfx+/L/8AP1B/YL9wv0D/kT+hP7F/gX/Rv+G/8f/BgBGAIYAxgAGAUYBhgHGAQYCRgKFAsUCBANEA4MDwwMCBEEEgATABP8ENgX2BLYEdgQ2
BPYDtgN2AzYD9wK3AncCOAL4AbkBeQE6AfsAvAB8AD0A///A/4H/Q/8E/8X+hv5I/gn+y/2M/U79D/3R/JP8VfwX/Nn7m/td+x/74fod+1z7m/va+xn8V/
yW/NT8E/1R/ZD9zv0M/kv+if7H/gX/Q/+B/7///f85AHcAtQDyADABbgGrAegBJgJjAqAC3QIaA1cDlAPRAw4ESwSIBMQEAQXQBJIEVAQXBNkDnANeAyED
5AKmAmkCLALvAbIBdQE4AfsAvgCBAEUACADM/5D/U/8X/9v+nv5i/ib+6v2u/XL9Nv36/L78gvxG/Av8z/uT+1j7HPtD+4D7vPv5+zX8cfyt/Or8Jv1i/Z
792v0W/lL+jv7J/gX/Qf98/7j/8/8uAGkApADgABsBVgGRAcwBBwJCAn0CuALzAi0DaAOjA90DGARSBI0ExwSqBG8ENAT4A70DggNHAwwD0QKWAlsCIALl
AasBcAE1AfsAwACGAEsAEQDY/57/Y/8p/+/+tf57/kH+B/7N/ZT9Wv0g/ef8rfx0/Dr8AfzH+477Vfto+6L73PsW/FD8ivzE/P78OP1y/az95v0f/ln+kv
7M/gX/P/94/7H/6/8jAFwAlQDOAAcBQAF5AbIB6gEjAlwClALNAgYDPgN2A68D5wMfBFgEkASGBE0EFATbA6IDaQMwA/cCvwKGAk0CFQLcAaQBawEzAfoA
wgCKAFIAGQDi/6r/cv86/wL/y/6T/lv+I/7s/bT9ff1F/Q791vyf/Gj8Mfz5+8L7i/uL+8P7+/sz/Gv8o/zb/BP9Sv2C/br98f0p/mD+l/7P/gb/Pf90/6
z/4/8ZAFAAhwC9APQAKwFiAZgBzwEGAjwCcwKpAt8CFgNMA4IDuAPvAyUEWwRjBCwE9QO+A4cDUQMaA+MCrQJ2AkACCQLTAZwBZgEwAfkAwwCNAFcAIQDs
/7b/gP9K/xX/3/6p/nT+Pv4J/tP9nv1o/TP9/vzI/JP8Xvwp/PT7v/uu++T7GvxQ/Ib8u/zx/Cf9XP2S/cf9/f0y/mf+nf7S/gf/PP9x/6b/2/8PAEQAeQ
CuAOMAFwFMAYEBtQHqAR4CUgKHArsC7wIkA1gDjAPAA/QDKARBBAwE1wOiA24DOQMEA9ACmwJnAjIC/gHJAZUBYQEtAfgAxACQAFwAKAD1/8H/jf9a/yb/
8v6//ov+V/4k/vD9vf2K/Vb9I/3w/L38ivxW/CP88PvQ+wT8N/xr/J/80/wG/Tr9bv2h/dX9CP47/m/+ov7V/gj/O/9v/6L/1f8GADkAbACfANIABQE3AW
oBnAHPAQECNAJmApkCywL9Ai8DYQOUA8YD+AMgBO0DugOHA1QDIgPvArwCigJXAiUC8gHAAY4BWwEpAfcAxQCTAGEALwD+/8z/mv9o/zb/BP/T/qH+cP4+
/gz+2/2q/Xj9R/0W/eT8s/yC/FH8IPzw+yL8VPyG/Lj86vwb/U39f/2w/eL9E/5F/nb+p/7Z/gr/O/9s/53/zv///y8AYACRAMIA8wAkAVQBhQG2AeYBFw
JHAngCqALYAgkDOQNpA5kDyQP5A88DngNtAzwDCwPaAqoCeQJIAhgC5wG3AYYBVgEmAfUAxQCVAGUANQAEANX/pf91/0b/Fv/m/rb+hv5X/if+9/3I/Zj9
af05/Qr92/yr/Hz8Tfwe/ED8cPyg/ND8AP0w/WD9j/2//e/9Hv5O/n3+rf7c/gz/O/9q/5n/yf/4/yYAVQCEALMA4gARAUABbwGdAcwB+wEpAlgChwK1Au
QCEgNAA28DnQPLA7EDggNTAyQD9QLGApcCaAI6AgsC3AGuAX8BUAEiAfMAxQCXAGgAOgAMAN7/sP+C/1T/Jv/4/sr+nP5u/kD+E/7l/bf9if1c/S79Af3T
/Kb8ePxL/F38i/y6/Oj8Fv1E/XL9oP3O/fv9Kf5X/oX+sv7g/g7/O/9p/5b/xP/x/x0ASwB4AKUA0gD/ACwBWQGGAbMB4AENAjoCZwKUAsAC7QIaA0YDcw
OfA5QDZwM6Aw0D4AKyAoUCWAIrAv4B0QGkAXgBSwEeAfEAxQCYAGsAPwASAOf/uv+O/2L/Nf8J/93+sf6F/lj+LP4A/tT9qP18/VH9Jf35/M38ovx2/Hr8
pvzS/P/8K/1X/YT9sP3c/Qj+NP5g/oz+uP7k/hD/PP9n/5P/v//r/xUAQQBsAJgAwwDvABoBRQFxAZwBxwHyAR4CSQJ0Ap8CygL1AiADSgN1A3kDTQMiA/
YCywKfAnQCSAIdAvIBxwGbAXABRQEaAe8AxACZAG4AQwAYAO//xP+Z/2//RP8Z/+/+xP4=
]],
    ask = [[
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
==
]],
}
local MM_FILE = 'miss_minutes_v2.png'
local ICONS_FILE = 'tva_icons_v1.png'
local ICONS_B64 = [[
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
9iZMHZyjz2QAAAAASUVORK5CYII=
]]

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64IDX = {}
for i = 1, 64 do B64IDX[B64:byte(i)] = i - 1 end

local bit = require('bit')
local unpack = table.unpack or unpack
local function b64decode(s)
    s = s:gsub('[^%w%+/]', '')
    local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
    local byte, char, idx = string.byte, string.char, B64IDX
    local n = #s
    local full = n - n % 4
    local parts, np, tmp, nt = {}, 0, {}, 0
    for i = 1, full, 4 do
        local a, b, c, d = byte(s, i, i + 3)
        local v = bor(lshift(idx[a], 18), lshift(idx[b], 12), lshift(idx[c], 6), idx[d])
        tmp[nt + 1], tmp[nt + 2], tmp[nt + 3] = rshift(v, 16), band(rshift(v, 8), 255), band(v, 255)
        nt = nt + 3
        if nt >= 3000 then
            np = np + 1
            parts[np] = char(unpack(tmp, 1, nt))
            nt = 0
        end
    end
    local rem = n - full
    if rem >= 2 then
        local a, b, c = byte(s, full + 1, full + 3)
        local v = bor(lshift(idx[a], 18), lshift(idx[b], 12), lshift(c and idx[c] or 0, 6))
        tmp[nt + 1] = rshift(v, 16) nt = nt + 1
        if rem == 3 then tmp[nt + 1] = band(rshift(v, 8), 255) nt = nt + 1 end
    end
    if nt > 0 then np = np + 1 parts[np] = char(unpack(tmp, 1, nt)) end
    return table.concat(parts)
end

local function ensureFile(name, b64)
    local dir = getWorkingDirectory() .. '/resource'
    if not doesDirectoryExist(dir) then createDirectory(dir) end
    dir = dir .. '/tva'
    if not doesDirectoryExist(dir) then createDirectory(dir) end
    local path = dir .. '/' .. name
    if not doesFileExist(path) then
        local f = io.open(path, 'wb')
        if not f then return nil end
        f:write(b64decode(b64))
        f:close()
    end
    return path
end

local V = imgui.ImVec4
local function rgb(r, g, b, a) return V(r / 255, g / 255, b / 255, (a or 255) / 255) end
local C = {
    orange  = rgb(236, 108, 14),  orangeD = rgb(184, 74, 6),   orangeL = rgb(248, 152, 62),
    cream   = rgb(254, 238, 219), panel   = rgb(253, 226, 198), edge    = rgb(243, 160, 92),
    btn     = rgb(241, 193, 150), btnH    = rgb(246, 207, 170), white   = rgb(255, 255, 255),
    text    = rgb(58, 32, 14),    muted   = rgb(150, 120, 95),  off     = rgb(229, 213, 197),
    good    = rgb(52, 150, 78),   bad     = rgb(210, 58, 38),   track   = rgb(246, 210, 176),
    brown   = rgb(150, 88, 56),
}
local function toU32(c)
    return math.floor(c.w * 255 + 0.5) * 16777216 + math.floor(c.z * 255 + 0.5) * 65536
         + math.floor(c.y * 255 + 0.5) * 256 + math.floor(c.x * 255 + 0.5)
end
local U = {}
for k, v in pairs(C) do U[k] = toU32(v) end

local F, TEX, ATLAS, AGENT_TEX = {}, nil, nil, nil
local FS = { body = 20, small = 17, brand = 38 }

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local fonts = imgui.GetIO().Fonts
    local FONT_FILES = { getWorkingDirectory() .. '/lib/mimgui/trebucbd.ttf', '/system/fonts/Roboto-Bold.ttf',
        '/system/fonts/Roboto-Regular.ttf', '/system/fonts/NotoSans-Bold.ttf', '/system/fonts/DroidSans-Bold.ttf' }
    local function add(size, ranges)
        for _, path in ipairs(FONT_FILES) do
            if doesFileExist(path) then
                local okf, f = pcall(function() return fonts:AddFontFromFileTTF(path, size, nil, ranges) end)
                if okf and f then return f end
            end
        end
        return fonts:AddFontDefault()
    end
    local cyr = fonts:GetGlyphRangesCyrillic()
    F.body  = add(FS.body, cyr)
    F.small = add(FS.small, cyr)
    F.title = add(24, cyr)
    F.big   = add(40)
    local BRAND_B64 = [[
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
Aq0YZ0kgNRE1N0Z5SAYI/ekCH/0UAfD+EAAAAQAQ//oCkALuACwAABYmNTQ2NjMyFw4CFRQWMzI2NjU0JiYjIgYGFRQWFSImNTQ2NjMyFhUUBgYjy19Ae1Qe
FixRMhweMWE/FTgzTYRPCjIzcbtnfXBQp3oGYGlZ3p4IGqLITTY+jdZjPksmP3VNGxkCKCxFfk6IeGvooQAAAQAGAAACUQLuACEAABM3Az4CNTQmIyIGFRQW
FSImNTQ2NjMyFhYVFAYGIyMDI+aURzBRLj4+eokONjVppFJPajNHhFYFPZACfBT+sgRMcDY8TIBzJR0CLTRAeUs2WTZBfE/+4wAAAgAQ/48CkALuAD0ARQAA
BCYmJwYjIiY1NDY2MzIXDgIVFRQXNjMyFzY2NTQmJiMiBgYVFBYVIiY1NDY2MzIWFRQGBgcWFjMyNwYGIyY3JiMiBxYzAdQyGQ0tMFRfQHtUHhYsUTICJBot
IzNIFTgzTYRPCjIzcbtnfXAqVj8aOCsGEBMxI60QFCUQDQ4icSExJw5gaVnenggaoshNEhEICRtC42o+SyY/dU0bGQIoLEV+Toh4SqmYLycqAjElvAsiBCkA
AAEABv/vAkgC7gA7AAAENTQ2NzY2NTQjIgcDIxM3BzMyNjY1NCYjIgYGFRQWFSImNTQ2NjMyFhYVFAYHFhYVFAYHBgYVFBYXBiMBZg0MDg48EBFQkIiUMQgn
QiU3N1F6Qw42NWmkUktmMjoyJh8ODQgOFRI9JhFDFjktL0IaRAT+hwJ8FOc2UScuOzpuSyUdAi00QHlLLEkrL14eCzMmHUEwHzwUFyQHEQAAAQAi/+4CKQLz
ADkAABYmJjU0NjYzMhYXIgYVFBYzMjY1NCYnJiY1NDY2MzIWFRQGIyInNjY1NCYjIgYVFBYXHgIVFAYGI7ZgNCU/JiMwBjQ+NCs1RTQ0Njc6ZkBRYSoiJhcT
FiYhKDMuMSgxI0d7SxIsTzQsSCojHzcvKzRHNi9UPD5ZNTRTMExAKjQfDi4ZICY5LChFNis+US9AaDwAAAEABgAAAs8C7QAcAAABIyIGFRQWFSImNTQ2NjMy
FxYzMjcGBiMiJicDIwErDFljDjY1Rpl2QkxAMkA0Aj49IEA7ipAClllxJR0CLTRHdUgMCxVBPgoM/X4AAAH/+//5AvoC8gAgAAAEJjU0NxMGBhUUFyImNTQ2
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
AAcD6AAAAADWF54PAAAAANYfcG7+NP4WBg0D6AAAAAcAAgAAAAAAAAMqAAAA2QAAApwACQKBAAwB8QATApcABgHLAAcBywAJAkIAEwKZAAwBdwAGAhgAEQJZ
AAYBewAGAxMAQwKcAAYCmQAQAj0ABgKZABACWQAGAjoAIgHhAAYCzP/7AmcABgPCAAYCbAAGAmwABgIeAAsCDv/zAbz/+QGA//MCDf/zAYD/8wEL/zAB+//z
Afn/2gEL//gA8P82Agb/2gEL//gC8P/aAfn/2gG3//IB1P+lAeb/8wF4/9oBfv/gAQv/+AH5//gBnv/3ApX/+AIKAAAB5v/4AawAAAKcAAkCfgAGAoEADAGQ
AAwCnf/nAcsABwHLAAcDCf/SAg3/9gLBAAwCwQAMAnsADAIl/+IDEwBDApkADAKZABACsAAMAj0ABgHxABMB4QAGAoQADAMSABMCbAAGArcADAK0AAwDigAM
A6YADAKAAAwCygAMA40ADAIg//UDsgAMAnb/0gIO//MBrv/zAcH/8gF3/+sB+//zAYD/8wGA//MDcv/bAfIAAAH5//gB+f/4AfX/2gIu/9oDO//aAfv/2gG3
//IB+f/aAdT/pQGA//MC8P/aAeb/+ALi//ICCgAAAfkAGQIX//gC8P/4Aw7/+AHA//oBwP/6Ao//+gGd/8wCo//aAg//2gIiABUBPQAVAez/9AICAAYB3P/+
AgUADwH0ABAB0AA5AfP//gHpAA0BewAyAXsAMgD4/5wCAwBVAWoAKgELACkA2AAYAQEAIAKTADwBBwAfAbkALgFhAFAAxABQARQALgE3AAsBvAAkAWAALQFg
/78BkP/5AZD/xAG1AJYBnf+8ASIAEwIkAA4BugAPAgMAIAFqAAcBZgAHAa8AMQMcADICsP/3AqoADgIUANsBpQAyAAD+8ADJABgAAP7d/xIAAAABAAAD6P8G
AAAF4/40/uQGDQABAAAAAAAAAAAAAAAAAAAApwAEAlIBkAAFAAACigJYAAAASwKKAlgAAAFeADIBLAAAAAAFAAAAAAAAAAAAAgEAAAAAAAAAAAAAAABJTVBB
AMAAIARRA+j/BgAAA+gB6gAAAAQAAAAAAfQC7AAAACAAAwAAAAIAAAADAAAAFAADAAEAAAAUAAQA9AAAACAAIAAEAAAALwA5AEAAWgBgAHoAfgQBBBUEJQQs
BDUERQRPBFH//wAAACAAMAA6AEEAWwBhAHsEAQQQBBYEJgQtBDYERgRR//8AAABIAAD/wQAA/7sAAPw7/Cb8JwAA/Cf8KAAA/AwAAQAgAAAAPAAAAEYAAABO
AAAAAAAAAE4AAAAAAFYAAAAAAAEAiQCNAIoAmQCfAKEAjgCWAJcAhQCaAIgAmACLAJAAhwCPAJ0AmwCcAIwAoACUAIYAlQCjAJEApQCSAKIAkwCeAE4ATQBP
AFAAUgBTAFEAbwBuAHAAcQBzAHQAcgB1AHYAdwADAAAAAAAA/7UAMgAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAf//AA8=
]]
    local bpath = ensureFile('brand_lobster_v1.ttf', BRAND_B64)
    BRAND_B64 = nil
    if bpath then
        local okf, bf = pcall(function() return fonts:AddFontFromFileTTF(bpath, FS.brand, nil, cyr) end)
        if okf and bf then F.brand = bf end
    end
    F.brand = F.brand or F.body

    local function tex(file, b64)
        local okm, tx = pcall(function() return imgui.CreateTextureFromMemory(b64decode(b64)) end)
        if okm and tx ~= nil and tx ~= 0 then return tx end
        local p = ensureFile(file, b64)
        if p then
            local okf, tf = pcall(imgui.CreateTextureFromFile, p)
            if okf then return tf end
        end
    end
    TEX = tex(MM_FILE, MM_B64)
    ATLAS = tex(ICONS_FILE, ICONS_B64)
    AGENT_TEX = tex(AGENT_FILE, AGENT_B64)
    MM_B64, ICONS_B64, AGENT_B64 = nil, nil, nil
end)

local PW, PH, TOP = 760, 728, 64
local DW, DH = PW, PH + TOP
local K, WX, WY, DL, FM = 0.84, 0, 0, nil, 1

local function P(x, y) return imgui.ImVec2(WX + x * K, WY + (y + TOP) * K) end

local function rbox(x, y, w, h, rnd, fill, border, bw)
    if border then
        DL:AddRectFilled(P(x, y), P(x + w, y + h), border, rnd * K)
        DL:AddRectFilled(P(x + bw, y + bw), P(x + w - bw, y + h - bw), fill, math.max(0, rnd - bw) * K)
    else
        DL:AddRectFilled(P(x, y), P(x + w, y + h), fill, rnd * K)
    end
end
local function line(x1, y1, x2, y2, c, w) DL:AddLine(P(x1, y1), P(x2, y2), c, w * K) end
local function dot(cx, cy, r, c) DL:AddCircleFilled(P(cx, cy), r * K, c, 28) end
local function ring(cx, cy, r, c, w) DL:AddCircle(P(cx, cy), r * K, c, 32, w * K) end
local function tri(x1, y1, x2, y2, x3, y3, c) DL:AddTriangleFilled(P(x1, y1), P(x2, y2), P(x3, y3), c) end

local function T(font, x, y, col, s)
    local fm = (font == F.body or font == F.small) and FM or 1
    local px = (font == F.body and FS.body) or (font == F.small and FS.small) or 0
    imgui.PushFont(font)
    imgui.SetWindowFontScale(K * fm)
    imgui.SetCursorScreenPos(P(x, y + px * (1 - fm) / 2))
    imgui.TextColored(col, s)
    imgui.SetWindowFontScale(1)
    imgui.PopFont()
end
local twCache = { body = {}, small = {}, other = {} }
local twCount, twK = 0, nil
local function TW(font, s)
    if twK ~= K + FM * 1000 or twCount > 600 then
        twCache = { body = {}, small = {}, other = {} }
        twCount, twK = 0, K + FM * 1000
    end
    local fc = (font == F.body and twCache.body) or (font == F.small and twCache.small) or twCache.other
    local w = fc[s]
    if w then return w end
    imgui.PushFont(font)
    imgui.SetWindowFontScale(K * ((font == F.body or font == F.small) and FM or 1))
    w = imgui.CalcTextSize(s).x / K
    imgui.SetWindowFontScale(1)
    imgui.PopFont()
    fc[s] = w
    twCount = twCount + 1
    return w
end
local function TC(font, cx, y, col, s) T(font, cx - TW(font, s) / 2, y, col, s) end

local fitCache, fitK, fitN = {}, nil, 0
local function fitText(font, s, maxw)
    if fitK ~= K + FM * 1000 or fitN > 300 then fitCache, fitK, fitN = {}, K + FM * 1000, 0 end
    local nk = maxw * 4 + ((font == F.body) and 1 or 2)
    local t = fitCache[nk]
    if not t then t = {} fitCache[nk] = t end
    local hit = t[s]
    if hit then return hit end
    local src, res = s, nil
    if TW(font, s) <= maxw then
        res = s
    else
        while #s > 1 do
            local i = #s
            while i > 1 and s:byte(i) >= 0x80 and s:byte(i) < 0xC0 do i = i - 1 end
            s = s:sub(1, i - 1)
            if TW(font, s .. '..') <= maxw then res = s .. '..' break end
        end
        res = res or s
    end
    t[src] = res
    fitN = fitN + 1
    return res
end

local function btnLabel(x, y, w, h, col, s, dx)
    dx = dx or 0
    local cx = x + w / 2 + dx
    local maxw = w - 12 - math.abs(dx) * 2
    if TW(F.body, s) <= maxw then
        TC(F.body, cx, y + (h - FS.body) / 2 - 1, col, s)
    elseif TW(F.small, s) <= maxw then
        TC(F.small, cx, y + (h - FS.small) / 2 - 1, col, s)
    else
        local a, b = s:match('^(.-)%s+(.+)$')
        if a then
            local lh = FS.small
            local ty = y + (h - lh * 2 - 2) / 2
            TC(F.small, cx, ty, col, a)
            TC(F.small, cx, ty + lh + 1, col, b)
        else
            TC(F.small, cx, y + (h - FS.small) / 2 - 1, col, fitText(F.small, s, maxw))
        end
    end
end

local function button(id, x, y, w, h, style, dis)
    imgui.SetCursorScreenPos(P(x, y))
    local pressed = imgui.InvisibleButton(id, imgui.ImVec2(w * K, h * K))
    local hov = imgui.IsItemHovered()
    if style == 'none' then return pressed, C.text end
    if dis then style, pressed, hov = 'off', false, false end
    local fill, border, tc
    if style == 'sel' or style == 'primary' then
        fill, border, tc = hov and U.orangeL or U.orange, U.orangeD, C.white
    elseif style == 'ghost' then
        fill, border, tc = hov and U.white or U.cream, U.orange, C.text
    elseif style == 'off' then
        fill, tc = U.off, C.muted
    else
        fill, tc = hov and U.btnH or U.btn, C.text
    end
    local rnd = (style == 'primary' or style == 'ghost') and 12 or 9
    rbox(x, y, w, h, rnd, fill, border, 2)
    return pressed, tc
end

local AW, AH, CELL = 480, 120, 48
local function icon(i, cx, cy, size, c)
    if not ATLAS then return end
    DL:AddImage(ATLAS, P(cx - size / 2, cy - size / 2), P(cx + size / 2, cy + size / 2),
        imgui.ImVec2(i * CELL / AW, 0), imgui.ImVec2((i + 1) * CELL / AW, CELL / AH), c)
end
local function logoImg(x, y, w, c)
    if not ATLAS then return false end
    local h = w * 69 / 192
    DL:AddImage(ATLAS, P(x, y), P(x + w, y + h),
        imgui.ImVec2(0, CELL / AH), imgui.ImVec2(192 / AW, (CELL + 69) / AH), c)
    return true
end
local function iShield(cx, cy, s, c1)  icon(0, cx, cy, s * 1.15, c1) end
local function iFork(cx, cy, s, c)     icon(1, cx, cy, s * 1.15, c) end
local function iClock(cx, cy, r, c)    icon(2, cx, cy, r * 2.2, c) end
local function iGear(cx, cy, r, c)     icon(3, cx, cy, r * 2.3, c) end
local function iPlay(cx, cy, s, c)     icon(4, cx, cy, s * 1.1, c) end
local function iRefresh(cx, cy, r, c)  icon(5, cx, cy, r * 2.6, c) end
local function iEyeOff(cx, cy, w, c)   icon(6, cx, cy, w * 2.4, c) end
local function iBolt(cx, cy, s, c)     icon(7, cx, cy, s * 1.1, c) end

local function missMinutesFallback(x, y, s)
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.42
    dot(cx, cy, r + 5, U.orangeD)
    dot(cx, cy, r, U.orange)
    dot(cx, cy, r * 0.82, U.panel)
    dot(cx - r * 0.28, cy - r * 0.15, r * 0.14, U.text)
    dot(cx + r * 0.28, cy - r * 0.15, r * 0.14, U.text)
    local px, py
    for a = 20, 160, 10 do
        local px2, py2 = cx + math.cos(math.rad(a)) * r * 0.42, cy + r * 0.05 + math.sin(math.rad(a)) * r * 0.3
        if px then line(px, py, px2, py2, U.text, 3) end
        px, py = px2, py2
    end
end

local SW = { anim = {}, last = clock() }
local C_TRACK_OFF = rgb(205, 180, 155)
local function mixCol(a, b, t)
    return toU32(V(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, 1))
end
function SW.draw(x, y, t, dis)
    local w, h = 46, 24
    local col = dis and U.off or mixCol(C_TRACK_OFF, C.good, t)
    rbox(x, y, w, h, h / 2, col, U.orangeD, 2)
    local kx = x + 12 + (w - 24) * t
    dot(kx, y + h / 2 + 1, 10, U.edge)
    dot(kx, y + h / 2, 10, U.white)
end
function SW.row(id, x, y, w, h, label, on, dis, pill)
    imgui.SetCursorScreenPos(P(x, y))
    local pressed = imgui.InvisibleButton(id, imgui.ImVec2(w * K, h * K))
    local hov = imgui.IsItemHovered() and not dis
    if dis then pressed = false end
    if pill then
        rbox(x, y, w, h, h / 2, hov and U.white or U.cream, U.orange, 2)
    elseif hov then
        rbox(x, y, w, h, 9, U.cream)
    end
    local a = SW.anim[id]
    if not a then a = on and 1 or 0 SW.anim[id] = a end
    local dt = math.min(0.1, clock() - SW.last)
    a = a + ((on and 1 or 0) - a) * math.min(1, dt * 16)
    if math.abs(a - (on and 1 or 0)) < 0.01 then a = on and 1 or 0 end
    SW.anim[id] = a
    T(F.body, x + (pill and 16 or 10), y + (h - FS.body) / 2 - 1, dis and C.muted or C.text, fitText(F.body, label, w - 80))
    SW.draw(x + w - 46 - (pill and 12 or 8), y + (h - 24) / 2, a, dis)
    return pressed
end

local UI = { tab = 0, def = {} }
UI.spawnLabel = 'Авто-спавн при еде < ' .. AUTO_SPAWN_BELOW .. '%'

function UI.card(x, y, w, h, title, ic, isz)
    rbox(x, y, w, h, 16, U.panel, U.edge, 2)
    icon(ic, x + 24, y + 21, isz, U.orangeD)
    T(F.body, x + 44, y + 10, C.orangeD, title)
end

function UI.slider(id, x, y, w, label, val, vmin, vmax, unit, step, deferred)
    step = step or 1
    local shown = (deferred and UI.def[id]) or val
    T(F.small, x, y, C.text, label)
    local vt = shown .. (unit or '')
    T(F.small, x + w - TW(F.small, vt), y, C.orangeD, vt)

    local pm = button(id .. 'm', x, y + 22, 30, 30, 'norm')
    TC(F.body, x + 15, y + 22 + 4, C.text, '-')
    local pp = button(id .. 'p', x + w - 30, y + 22, 30, 30, 'norm')
    TC(F.body, x + w - 15, y + 22 + 4, C.text, '+')
    if pm then val = math.max(vmin, val - step) shown = val end
    if pp then val = math.min(vmax, val + step) shown = val end

    local tx0, tw = x + 40, w - 80
    imgui.SetCursorScreenPos(P(tx0, y + 20))
    imgui.InvisibleButton(id, imgui.ImVec2(tw * K, 34 * K))
    local active = imgui.IsItemActive()
    if active then
        local t = (imgui.GetIO().MousePos.x - P(tx0, 0).x) / (tw * K)
        t = math.max(0, math.min(1, t))
        local nv = math.floor((vmin + t * (vmax - vmin)) / step + 0.5) * step
        nv = math.max(vmin, math.min(vmax, nv))
        if deferred then UI.def[id] = nv else val = nv end
        shown = nv
    elseif deferred and UI.def[id] then
        val, UI.def[id] = UI.def[id], nil
        shown = val
    end
    local t = (shown - vmin) / (vmax - vmin)
    rbox(tx0, y + 33, tw, 8, 4, U.track)
    rbox(tx0, y + 33, math.max(8, tw * t), 8, 4, U.orange)
    dot(tx0 + tw * t, y + 37, 12, U.orangeD)
    dot(tx0 + tw * t, y + 37, 9, U.white)
    return val
end

function UI.resetAll()
    S.uiScale[0], S.fontMul[0], S.lockWin[0] = 90, 100, true
    S.agentScale[0], S.agentCps[0], S.agentVol[0], S.agentCorner[0] = 100, 30, 45, 0
    S.autoStart[0], S.hideNoFood[0], S.hideBelow[0], S.watch[0] = true, true, 25, 30
    dirty = true
end

local CORNERS = { { 0, 'Авто' }, { 1, 'Пр. низ' }, { 2, 'Лев. низ' }, { 3, 'Пр. верх' }, { 4, 'Лев. верх' } }

function UI.settings(off)
    local v, pr, tc
    UI.card(24, 140, 348, 186, 'ВНЕШНИЙ ВИД', 3, 25)
    v = UI.slider('s_ui', 38, 178, 320, 'Размер меню', S.uiScale[0], 40, 105, '%', 5, true)
    if v ~= S.uiScale[0] then S.uiScale[0] = v dirty = true end
    v = UI.slider('s_fm', 38, 234, 320, 'Размер текста', S.fontMul[0], 80, 130, '%', 5)
    if v ~= S.fontMul[0] then S.fontMul[0] = v dirty = true end
    if SW.row('s_lock', 32, 290, 332, 28, 'Закрепить по центру', S.lockWin[0]) then
        S.lockWin[0] = not S.lockWin[0] dirty = true
    end

    UI.card(24, 336, 348, 226, 'КОРМЛЕНИЕ И ЗДОРОВЬЕ', 1, 22)
    if SW.row('s_start', 32, 372, 332, 28, 'Запускать при входе в игру', S.autoStart[0]) then
        S.autoStart[0] = not S.autoStart[0] dirty = true
    end
    if SW.row('s_nofood', 32, 402, 332, 28, 'Прятать охранника без еды', S.hideNoFood[0]) then
        S.hideNoFood[0] = not S.hideNoFood[0] dirty = true
    end
    v = UI.slider('s_hb', 38, 438, 320, 'Прятать при здоровье до', S.hideBelow[0], 5, 90, '%', 5)
    if v ~= S.hideBelow[0] then S.hideBelow[0] = v dirty = true end
    v = UI.slider('s_w', 38, 494, 320, 'Проверка здоровья раз в', S.watch[0], 10, 120, ' сек', 5)
    if v ~= S.watch[0] then S.watch[0] = v dirty = true end

    pr, tc = button('s_reset', 24, 574, 348, 40, 'ghost')
    btnLabel(24, 574, 348, 40, tc, 'Сбросить все настройки')
    if pr then UI.resetAll() end
    T(F.small, 30, 630, C.muted, 'Auto Guard Feeder ' .. (thisScript().version or ''))

    UI.card(388, 140, 348, 322, 'МИСС МИНУТКА', 2, 25)
    v = UI.slider('s_as', 402, 178, 320, 'Размер', S.agentScale[0], 50, 200, '%', 10)
    if v ~= S.agentScale[0] then S.agentScale[0] = v dirty = true end
    v = UI.slider('s_cps', 402, 234, 320, 'Скорость печати', S.agentCps[0], 10, 80, ' симв/с', 5)
    if v ~= S.agentCps[0] then S.agentCps[0] = v dirty = true end
    v = UI.slider('s_vol', 402, 290, 320, 'Громкость звуков', S.agentVol[0], 0, 100, '%', 5)
    if v ~= S.agentVol[0] then S.agentVol[0] = v dirty = true end
    T(F.small, 402, 348, C.text, 'Угол появления')
    for i, c in ipairs(CORNERS) do
        local bx = 402 + (i - 1) * 65
        local sel = S.agentCorner[0] == c[1]
        pr, tc = button('s_cn' .. i, bx, 372, 60, 40, sel and 'sel' or 'norm')
        btnLabel(bx, 372, 60, 40, tc, c[2])
        if pr then S.agentCorner[0] = c[1] dirty = true end
    end
    pr, tc = button('s_demo', 402, 420, 320, 32, 'ghost')
    btnLabel(402, 420, 320, 32, tc, 'Показать пример')
    if pr then agentSay(4, 'Привет! Вот так я выгляжу с текущими настройками.', true) end
end

function UI.main(off)
    rbox(24, 140, 348, 72, 16, U.panel, U.edge, 2)
    iShield(60, 174, 34, U.orange)
    T(F.small, 100, 146, C.orangeD, 'АКТИВНЫЙ ОХРАННИК')
    rbox(100, 168, 262, 34, 10, U.cream, U.orange, 2)
    local ag = guard and findGuard(guard)
    local aname = ag and guardLabel(ag, guardIndex(guard)) or 'не заспавнен'
    T(F.body, 112, 174, ag and C.text or C.muted, fitText(F.body, aname, 240))

    rbox(388, 140, 348, 72, 16, U.panel, U.edge, 2)
    iFork(424, 174, 34, U.orange)
    T(F.small, 458, 146, C.orangeD, 'ЗАПАС ЕДЫ')
    local cnt, unk = foodCount()
    local bag = 'в инвентаре: ' .. cnt .. (unk and '+' or '')
    T(F.small, 722 - TW(F.small, bag), 146, C.muted, bag)
    local est = estSatiety()
    local shown = est and math.floor(est + 0.5)
    local pct = shown or 0
    local low = shown ~= nil and shown < AUTO_SPAWN_BELOW
    T(F.big, 458, 162, low and C.bad or C.orangeD, shown and (shown .. '%') or '--')
    rbox(562, 180, 158, 16, 8, U.track)
    if pct > 0 then rbox(562, 180, math.max(16, 158 * math.min(100, pct) / 100), 16, 8, low and U.bad or U.orange) end

    rbox(24, 222, 348, 142, 16, U.panel, U.edge, 2)
    iShield(46, 239, 18, U.orange)
    T(F.body, 62, 229, C.orangeD, 'ВЫБРАТЬ АКТИВНОГО')
    for i = 1, 4 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local bx, by, bw, bh = 38 + col * 164, 256 + row * 52, 156, 44
        local g = guards[i]
        local sel = g and S.prefId[0] == g.id
        local pr, tc = button('g' .. i, bx, by, bw, bh, sel and 'sel' or 'norm', g == nil or busy or off)
        if pr then
            S.prefId[0] = g.id dirty = true
            if g.died == 1 then agentNote(8, 'Этот охранник погиб.')
            elseif guard == g.id then agentNote(9, 'Этот охранник уже заспавнен.')
            else run('swap', g.id) end
        end
        iShield(bx + 24, by + 21, 20, sel and U.white or (g and U.brown or U.muted))
        local label = g and guardLabel(g, i) or string.format('Охранник %02d', i)
        btnLabel(bx, by, bw, bh, tc, fitText(F.body, label, bw - 66), 12)
        if g then
            if g.died == 1 then dot(bx + bw - 14, by + 13, 5, U.bad)
            elseif g.spawned == 1 then dot(bx + bw - 14, by + 13, 5, U.good) end
        end
    end

    rbox(388, 222, 348, 224, 16, U.panel, U.edge, 2)
    iFork(404, 238, 20, U.orange)
    T(F.body, 422, 229, C.orangeD, 'ЕДА')
    for i, f in ipairs(foodList()) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local bx, by, bw, bh = 402 + col * 109, 256 + row * 46, 102, 40
        local sel = S.food[0] == f.id
        local pr, tc = button('f' .. i, bx, by, bw, bh, sel and 'sel' or 'norm')
        if pr then S.food[0] = f.id dirty = true end
        btnLabel(bx, by, bw, bh, tc, f.name)
    end

    iClock(38, 389, 11, U.orangeD)
    T(F.body, 58, 378, C.orangeD, 'КОРМИТЬ ПРИ СЫТОСТИ')
    for i, v in ipairs(THRESHOLDS) do
        local idx = i - 1
        local row = idx < 5 and 0 or 1
        local col = idx < 5 and idx or idx - 5
        local bx, by, bw, bh = 24 + col * 71, 404 + row * 44, 64, 36
        local sel = S.threshold[0] == v
        local pr, tc = button('c' .. i, bx, by, bw, bh, sel and 'sel' or 'norm')
        if pr then
            S.threshold[0] = v dirty = true
            if cycle and enabled and not busy then scheduleNext(true, 5) end
        end
        btnLabel(bx, by, bw, bh, tc, v .. '%')
    end

    rbox(24, 496, 348, 178, 16, U.panel, U.edge, 2)
    iGear(46, 513, 11, U.orangeD)
    T(F.body, 62, 503, C.orangeD, 'НАСТРОЙКИ')
    local rx, rw, rh = 32, 332, 28

    if SW.row('sw_auto', rx, 530, rw, rh, 'Авто-кормление', cycle and enabled, off or busy) then
        if cycle then cycle = false S.autoFeed[0] = false dirty = true
        else S.autoFeed[0] = true dirty = true run('start') end
    end
    if SW.row('sw_spawn', rx, 558, rw, rh, UI.spawnLabel, S.autoSpawn[0]) then
        S.autoSpawn[0] = not S.autoSpawn[0] dirty = true
    end
    if SW.row('sw_agent', rx, 586, rw, rh, 'Подсказки Мисс Минутки', S.agent[0]) then
        S.agent[0] = not S.agent[0] dirty = true
        if not S.agent[0] then agent.q, agent.cur = {}, nil end
    end
    if SW.row('sw_sound', rx, 614, rw, rh, 'Звуки Мисс Минутки', S.agentSound[0]) then
        S.agentSound[0] = not S.agentSound[0] dirty = true
    end

    rbox(388, 458, 348, 216, 16, U.panel, U.edge, 2)
    iGear(404, 475, 11, U.orangeD)
    T(F.body, 426, 465, C.orangeD, 'УПРАВЛЕНИЕ')

    local pr, tc
    pr, tc = button('spawn', 402, 492, 320, 38, 'primary', busy or off)
    iPlay(402 + 36, 511, 18, (busy or off) and U.muted or U.white)
    btnLabel(402, 492, 320, 38, tc, 'Заспавнить выбранного', 14)
    if pr then
        if S.prefId[0] < 0 then agentNote(3, 'Сначала выбери охранника.') else run('swap', S.prefId[0]) end
    end

    pr, tc = button('feed', 402, 536, 320, 38, 'ghost', busy or off)
    iFork(402 + 66, 555, 18, U.orangeD)
    btnLabel(402, 536, 320, 38, tc, 'Покормить сейчас', 14)
    if pr then run('now') end

    pr, tc = button('scan', 402, 580, 154, 38, 'ghost', busy or off)
    iRefresh(402 + 15, 596, 8, U.orangeD)
    btnLabel(402, 580, 154, 38, tc, 'Обновить данные', 12)
    if pr then run('scan') end

    pr, tc = button('hide', 568, 580, 154, 38, 'ghost', busy or off)
    iEyeOff(568 + 17, 596, 10, U.orangeD)
    btnLabel(568, 580, 154, 38, tc, 'Скрыть охранника', 12)
    if pr then run('hide') end

    pr, tc = button('check', 402, 624, 320, 38, 'ghost', busy or off or not S.autoSpawn[0])
    iBolt(402 + 56, 643, 20, U.orangeD)
    btnLabel(402, 624, 320, 38, tc, 'Проверить авто-спавн', 14)
    if pr then run('autocheck') end

end

local function drawUI()
    SW.last = SW.last or clock()
    local off = not S.scriptOn[0]

    rbox(0, 0, PW, PH, 26, U.cream, U.orange, 5)
    T(F.brand, 36, 11, C.edge, 'Мисс Минутка')
    T(F.brand, 34, 9, C.orangeD, 'Мисс Минутка')
    T(F.small, 40, 58, C.muted, 'помощник по охране')

    if SW.row('sw_script', 290, 22, 176, 36, 'Скрипт', not off, false, true) then setScript(off) end

    if TEX then
        imgui.SetCursorScreenPos(P(480, -60))
        imgui.Image(TEX, imgui.ImVec2(260 * K, 157 * K))
    else
        missMinutesFallback(532, -64, 200)
    end

    DL:AddRectFilled(P(5, 82), P(PW - 5, 126), U.orange, 0)
    for i = 0, 2 do line(640 + i * 16, 124, 654 + i * 16, 84, U.cream, 4) end
    T(F.title, 30, 92, C.white, fitText(F.title, 'АВТОКОРМЛЕНИЕ ОХРАННИКА', 390))

    local cl = button('close', 698, 84, 54, 40, 'none')
    ring(726, 104, 13, U.white, 2.4)
    icon(9, 726, 104, 13, U.white)
    if cl then win[0] = false end

    for i, name in ipairs({ 'Главная', 'Настройки' }) do
        local bx = 424 + (i - 1) * 134
        local sel = UI.tab == i - 1
        local tp = button('tab' .. i, bx, 88, 128, 32, 'none')
        rbox(bx, 88, 128, 32, 16, sel and U.white or U.orange, U.white, 2)
        TC(F.small, bx + 64, 88 + 7, sel and C.orangeD or C.white, name)
        if tp then UI.tab = i - 1 end
    end

    if UI.tab == 1 then UI.settings(off) else UI.main(off) end

    local st, stc
    if off then st, stc = 'Скрипт выключен', C.bad
    elseif busy then st, stc = 'Работаю...', C.orangeD
    elseif #guards == 0 then st, stc = 'Нет данных - открой инвентарь и вкладку охранников', C.muted
    elseif not enabled then st, stc = 'Скрипт отключён (нет охранника)', C.bad
    elseif starving then st, stc = 'Нет еды, слежу за здоровьем', C.orangeD
    elseif cycle then
        st, stc = string.format('Кормлю при %d%% - через %s', S.threshold[0],
            fmtHours(math.max(0, nextRun - clock()) / 3600)), C.good
    else st, stc = 'Ожидание', C.muted end
    rbox(24, 686, 712, 30, 15, U.panel, U.edge, 2)
    dot(46, 701, 6, off and U.bad or (busy and U.orange or ((cycle and enabled) and U.good or U.muted)))
    T(F.small, 62, 692, stc, fitText(F.small, st, 650))

    SW.last = clock()
end

local function u8len(s)
    local n = 0
    for i = 1, #s do local b = s:byte(i) if b < 0x80 or b >= 0xC0 then n = n + 1 end end
    return n
end
local function u8left(s, n)
    if n <= 0 then return '' end
    local cnt = 0
    for i = 1, #s do
        local b = s:byte(i)
        if b < 0x80 or b >= 0xC0 then
            cnt = cnt + 1
            if cnt > n then return s:sub(1, i - 1) end
        end
    end
    return s
end
local function agCol(r, g, b, a) return math.floor(a) * 16777216 + b * 65536 + g * 256 + r end

local function agWrap(text, maxw, ts)
    imgui.PushFont(F.body)
    imgui.SetWindowFontScale(ts)
    local lines, cur, widest = {}, '', 0
    for w in text:gmatch('%S+') do
        local try = (cur == '') and w or (cur .. ' ' .. w)
        if cur ~= '' and imgui.CalcTextSize(try).x > maxw then
            lines[#lines + 1] = cur
            widest = math.max(widest, imgui.CalcTextSize(cur).x)
            cur = w
        else
            cur = try
        end
    end
    if cur ~= '' then
        lines[#lines + 1] = cur
        widest = math.max(widest, imgui.CalcTextSize(cur).x)
    end
    imgui.SetWindowFontScale(1)
    imgui.PopFont()
    return lines, widest
end

local AGENT_SND = {}
local function agentSoundInit()
    for name, b64 in pairs(AGENT_SND_B64) do
        local path = ensureFile('agent_v1_' .. name .. '.wav', b64)
        if path and type(loadAudioStream) == 'function' then
            local ok, st = pcall(loadAudioStream, path)
            if ok and st then AGENT_SND[name] = st end
        end
    end
    AGENT_SND_B64 = nil
end
local function agentPlay(name)
    if not S.agentSound[0] then return end
    local st = AGENT_SND[name]
    if not st then return end
    pcall(function()
        setAudioStreamState(st, 0)
        setAudioStreamVolume(st, (S.agentVol[0] / 100))
        setAudioStreamState(st, 1)
    end)
end

local function curTotal(c)
    local t = c.total
    if not t then t = u8len(c.text) c.total = t end
    return t
end

imgui.OnFrame(function() return agent.cur ~= nil or agent.slide > 0 end, function(self)
    self.HideCursor = true
    local sw, sh = getScreenResolution()
    local now = clock()
    local dt = math.min(0.1, math.max(0, now - agent.last))
    agent.last = now
    if S.agentCorner[0] > 0 then agent.pos = S.agentCorner[0] end

    local cur = agent.cur
    if cur then
        local total = curTotal(cur)
        local hold = cur.hold or math.max(2.5, total * 0.045)
        if now > cur.t0 + total / S.agentCps[0] + hold then
            if #agent.q > 0 then
                cur = table.remove(agent.q, 1)
                cur.t0 = now
                agent.cur = cur
            else
                cur, agent.cur = nil, nil
            end
        end
    end
    if cur then
        agent.emo = cur.emo
        if not cur.started then
            cur.started = true
            if agent.slide < 0.2 then
                agentPlay('appear')
                if S.agentCorner[0] == 0 then
                    local np = math.random(1, 3)
                    if np >= agent.pos then np = np + 1 end
                    agent.pos = np
                end
            end
        end
        local total = curTotal(cur)
        local typed = math.floor((now - cur.t0) * S.agentCps[0])
        if typed < total then
            if typed - (cur.blipAt or 0) >= 2 then
                cur.blipAt = typed
                agentPlay('blip' .. math.random(1, 3))
            end
        elseif not cur.done then
            cur.done = true
            agentPlay(AGENT_MOOD[cur.emo] or 'ask')
        end
    end
    local dir = cur and 1 or -1
    agent.slide = math.max(0, math.min(1, agent.slide + dir * dt * 3.2))
    local ease = agent.slide * agent.slide * (3 - 2 * agent.slide)
    local alpha = math.floor(255 * math.min(1, agent.slide * 1.6))
    local s = math.max(0.75, sh / 1080) * (S.agentScale[0] / 100)

    imgui.SetNextWindowPos(imgui.ImVec2(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(sw, sh), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.Begin('##agent_mm', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
        + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoInputs)
    local dl = imgui.GetWindowDrawList()

    local pos = agent.pos or 1
    local onRight = (pos == 1 or pos == 3)
    local onBottom = (pos == 1 or pos == 2)
    local cw, ch = 224 * 1.15 * s, 200 * 1.15 * s
    local cx1
    if onRight then
        cx1 = sw - cw - 12 * s + (1 - ease) * (cw + 40 * s)
    else
        cx1 = 12 * s - (1 - ease) * (cw + 40 * s)
    end
    local bob = math.sin(now * 4) * 4 * s * ease
    local cy1, cy2
    if onBottom then
        cy2 = sh * 0.80 + bob
        cy1 = cy2 - ch
    else
        cy1 = sh * 0.07 + bob
        cy2 = cy1 + ch
    end
    if AGENT_TEX then
        local e = (agent.emo or 1) - 1
        local col, row = e % 4, math.floor(e / 4)
        local u0, u1 = col / 4, (col + 1) / 4
        if not onRight then u0, u1 = u1, u0 end
        dl:AddImage(AGENT_TEX, imgui.ImVec2(cx1, cy1), imgui.ImVec2(cx1 + cw, cy2),
            imgui.ImVec2(u0, row / 3), imgui.ImVec2(u1, (row + 1) / 3), agCol(255, 255, 255, alpha))
    end

    if cur then
        local ts = s
        local pad = 16 * s
        if cur.wrapTs ~= ts then
            cur.wLines, cur.wWidest = agWrap(cur.text, 320 * s, ts)
            cur.wLens = {}
            for i, ln in ipairs(cur.wLines) do cur.wLens[i] = u8len(ln) end
            cur.wrapTs = ts
        end
        local lines, widest, lens = cur.wLines, cur.wWidest, cur.wLens
        local lineH = 20 * ts * 1.22
        local bw = widest + pad * 2
        local bh = pad * 2 + #lines * lineH
        local bx1, bx2
        if onRight then
            bx2 = cx1 + 10 * s
            bx1 = math.max(8 * s, bx2 - bw)
        else
            bx1 = cx1 + cw - 10 * s
            bx2 = math.min(sw - 8 * s, bx1 + bw)
        end
        local by2 = cy1 + ch * 0.55
        local by1 = math.max(8 * s, by2 - bh)
        by2 = by1 + bh
        local orange, white = agCol(236, 108, 14, alpha), agCol(255, 255, 255, alpha)
        local bd = 2.5 * s

        local dx = onRight and 1 or -1
        local tx, ty = (onRight and bx2 - 3 * s or bx1 + 3 * s), by2 - 30 * s
        dl:AddTriangleFilled(imgui.ImVec2(tx, ty - 3 * s), imgui.ImVec2(tx, ty + 22 * s), imgui.ImVec2(tx + dx * 22 * s, ty + 26 * s), orange)
        dl:AddTriangleFilled(imgui.ImVec2(tx - dx * 2 * s, ty), imgui.ImVec2(tx - dx * 2 * s, ty + 18 * s), imgui.ImVec2(tx + dx * 16 * s, ty + 23 * s), white)
        dl:AddRectFilled(imgui.ImVec2(bx1, by1), imgui.ImVec2(bx2, by2), orange, 18 * s)
        dl:AddRectFilled(imgui.ImVec2(bx1 + bd, by1 + bd), imgui.ImVec2(bx2 - bd, by2 - bd), white, 16 * s)
        dl:AddTriangleFilled(imgui.ImVec2(tx - dx * 2 * s, ty + 1), imgui.ImVec2(tx - dx * 2 * s, ty + 17 * s), imgui.ImVec2(tx + dx * 3 * s, ty + 18 * s), white)

        local total = curTotal(cur)
        local typed = math.floor((now - cur.t0) * S.agentCps[0])
        local left = typed
        imgui.PushFont(F.body)
        imgui.SetWindowFontScale(ts)
        for i, ln in ipairs(lines) do
            if left <= 0 then break end
            local shown = (left >= lens[i]) and ln or u8left(ln, left)
            if typed < total and left <= lens[i] and math.floor(now * 2.5) % 2 == 0 then shown = shown .. '|' end
            imgui.SetCursorScreenPos(imgui.ImVec2(bx1 + pad, by1 + pad + (i - 1) * lineH))
            imgui.TextColored(imgui.ImVec4(0.05, 0.05, 0.05, alpha / 255), shown)
            left = left - lens[i] - 1
        end
        imgui.SetWindowFontScale(1)
        imgui.PopFont()
    end

    imgui.End()
    imgui.PopStyleVar(2)
end)

imgui.OnFrame(function() return win[0] end, function()
    local sw, sh = getScreenResolution()
    K = math.max(0.25, math.min(sw * 0.96 / DW, sh * 0.96 / DH) * (S.uiScale[0] / 100))
    FM = S.fontMul[0] / 100
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), S.lockWin[0] and imgui.Cond.Always or imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(DW * K, DH * K), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.Begin('##guard_control', nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
        + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoSavedSettings
        + (S.lockWin[0] and imgui.WindowFlags.NoMove or 0))
    local wp = imgui.GetWindowPos()
    WX, WY = wp.x, wp.y
    DL = imgui.GetWindowDrawList()
    drawUI()
    imgui.End()
    imgui.PopStyleVar(2)
end)

function onWindowMessage(m, w, l)
    if m == 0x100 and w == 0x1B and win[0] and not sampIsChatInputActive() then
        consumeWindowMessage(true, false)
        win[0] = false
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand('missguard', function() win[0] = not win[0] end)
    sampRegisterChatCommand('mg',       function() win[0] = not win[0] end)
    sampRegisterChatCommand('feed',     function() run('now') end)
    sampRegisterChatCommand('fmset',    function() UI.tab = 1 win[0] = true end)
    sampRegisterChatCommand('fmpower',  function() setScript(not S.scriptOn[0]) end)
    sampRegisterChatCommand('fmspawn',  function()
        S.autoSpawn[0] = not S.autoSpawn[0] dirty = true
        msg('Авто-спавн охранника: ' .. (S.autoSpawn[0] and 'ВКЛ' or 'ВЫКЛ'))
    end)
    sampRegisterChatCommand('fmpkt',    function()
        S.hidePkts[0] = not S.hidePkts[0] dirty = true
        msg('Скрытие инвентаря и пакетов: ' .. (S.hidePkts[0] and 'ВКЛ' or 'ВЫКЛ'))
    end)
    sampRegisterChatCommand('agent',    function()
        S.agent[0] = not S.agent[0] dirty = true
        if not S.agent[0] then agent.q, agent.cur = {}, nil end
        msg('Подсказки Мисс Минутки: ' .. (S.agent[0] and 'ВКЛ' or 'ВЫКЛ'))
    end)
    sampRegisterChatCommand('agentsound', function()
        S.agentSound[0] = not S.agentSound[0] dirty = true
        msg('Звуки Мисс Минутки: ' .. (S.agentSound[0] and 'ВКЛ' or 'ВЫКЛ'))
    end)

    while not (sampGetGamestate() == 3 or sampIsLocalPlayerSpawned()) do wait(200) end
    wait(1500)
    sampAddChatMessage(u8:decode('{FF0000}| {FF8A1F}Мисс Охранник {FFFFFF}загружена и работает {FF0000}By {00FFFF}Edward {C0C0C0}/mg {FFFFFF}- активация меню'), -1)
    if not S.scriptOn[0] then
        sampAddChatMessage(u8:decode('{FF8A1F}[Auto Guard Feeder]{FFFFFF} Скрипт сейчас ВЫКЛЮЧЕН. Включить: кнопка в меню или /fmpower.'), -1)
    end
    pcall(agentSoundInit)

    needStartup = true
    startupAt = clock() + (S.autoFeed[0] and STARTUP_DELAY or 3)

    while true do
        wait(200)

        if S.scriptOn[0] and needStartup and not busy and clock() >= startupAt
           and (sampGetGamestate() == 3 or sampIsLocalPlayerSpawned()) then
            needStartup = false
            session('startup')
        end

        if S.scriptOn[0] and cycle and enabled and not busy and clock() >= nextRun then
            nextRun = clock() + 60
            session('feed')
        end

        if S.scriptOn[0] and starving and enabled and not busy and clock() >= nextWatch then
            nextWatch = clock() + S.watch[0]
            watchTick()
        end

        if PK.learned then
            PK.learned = false
            agentNote(4, 'Запомнила формат пакетов твоего телефона. Теперь можно кормить!')
        end

        if dirty then saveIni() end
    end
end

function onScriptTerminate(s)
    if s == thisScript() then saveIni() end
end