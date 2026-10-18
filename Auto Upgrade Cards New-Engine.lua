script_name("Auto Upgrade Cards")
script_author("By Stalin")
script_version("1.6")

local ffi = require("ffi")

-- Android (MoonLoader Mobile) или ПК
local MOBILE = rawget(_G, "MONET_DPI_SCALE") ~= nil or ffi.os ~= "Windows"

local function tryRequire(name)
    local ok, module = pcall(require, name)
    if ok then return module end
end

local events   = tryRequire("samp.events")
local imgui    = tryRequire("mimgui")
local encoding = tryRequire("encoding")
local fa       = tryRequire("fAwesome5")

do
    local missing = {}
    if not events   then missing[#missing + 1] = "SAMP.Lua" end
    if not imgui    then missing[#missing + 1] = "mimgui" end
    if not encoding then missing[#missing + 1] = "encoding" end

    if #missing > 0 then
        local function toCp1251(s)
            if #"я" ~= 2 then return s end
            return (s:gsub("[\208\209][\128-\191]", function(c)
                local first, second = c:byte(1, 2)
                local code = (first - 208) * 64 + (second - 128) + 0x400
                if code >= 0x410 and code <= 0x44F then return string.char(code - 0x410 + 0xC0) end
                if code == 0x401 then return "\168" end
                if code == 0x451 then return "\184" end
                return "?"
            end))
        end

        function main()
            while not isSampAvailable() do wait(100) end
            local text = "{ff5555}[Auto Upgrade Cards] Не найдены библиотеки: {ffffff}" .. table.concat(missing, ", ")
            sampAddChatMessage(toCp1251(text), -1)
            thisScript():unload()
        end
        return
    end
end

local VERSION  = "1.6"
local TG_URL   = "https://t.me/edward_scripts"

encoding.default = "CP1251"
local utf8c    = encoding.UTF8
local SRC_UTF8 = (#"я" == 2)

local u8cache, u8count = {}, 0
local function u8(s)
    if SRC_UTF8 then return s end
    local v = u8cache[s]
    if not v then
        v = utf8c(s)
        if u8count > 400 then u8cache, u8count = {}, 0 end
        u8cache[s] = v
        u8count = u8count + 1
    end
    return v
end

local function cp(s)
    if SRC_UTF8 then return utf8c:decode(s) end
    return s
end

local function srcText(s)
    if SRC_UTF8 then return s end
    return utf8c:decode(s)
end

local function has(str, phrase)
    return str:find(phrase, 1, true) ~= nil
        or str:find(cp(phrase), 1, true) ~= nil
        or str:find(u8(phrase), 1, true) ~= nil
end

local function matchAny(str, pattern)
    return str:match(pattern) or str:match(cp(pattern)) or str:match(u8(pattern))
end

-- на случай, если сервер пришлёт текст как \uXXXX
local function unescapeU(str)
    if not str:find("\\u", 1, true) then return str end
    return (str:gsub("\\u(%x%x%x%x)", function(h)
        local c = tonumber(h, 16)
        if c < 0x80 then return string.char(c) end
        if c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64) end
        return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
    end))
end

local TABLE_POS = { x = 941.416, y = -850.7972, radius = 1.0 }

local CARD_ITEM        = 3206
local LUBE_ITEM        = 3204
local LUBE_PER_TRY     = 2
local PACKET_CEF       = 220
local MAX_CEF_LEN      = 30000
local MAX_RETRIES      = 3
local MAX_ERRORS       = 8
local OPEN_TIMEOUT     = 4.0
local RESULT_TIMEOUT   = 20.0
local DIALOG_TIMEOUT   = 5.0
local UPGRADE_DURATION = 11.5
local CLICK_DELAY      = 400

local settings = { cardsNum = 1, needLVL = 10, scanLevels = true, lowPC = MOBILE }

local state = {
    running      = false,
    stopping     = false,
    done         = 0,
    sessionStart = 0,
    sessionTime  = 0,
}

local stats = { attempts = 0, cards = 0, lube = 0, errors = 0, curAttempts = 0, curStart = 0, history = {} }

local ui = {
    main     = imgui.new.bool(false),
    needLVL  = imgui.new.int(10),
    cardsNum = imgui.new.int(1),
    tab      = 1,
    tabT     = 1,
    navY     = nil,
    openT    = 0,
    lastT    = nil,
    ring     = 0,
    status   = "",
    message  = "",
    dots     = 0,
    scanning = false,
}

local cef = { inventory = {}, slots = {}, opened = false, lastData = 0, current = nil, lube = nil,
              ifaceOpen = false, bitsSlot = nil }

local cardLevels = {}
local levelSeen  = {}
local knownCards = {}
local excluded   = {}
local signal     = { result = nil }
local forceSlot  = nil
local probeDone  = false
local lastUseAt  = -100
local pending    = nil
local dirtyAt    = nil
local sendFmt    = nil    -- выученный формат исходящего пакета 220/63 (берётся из реального клика)
local ownSend    = false  -- true, пока скрипт сам отправляет пакет (чтобы не учиться на своих)
local debugOn    = false  -- /upgdbg
local HK = { mode = "нет", count = { send = 0, recv = 0, rpc = 0 } }

local toasts = {}

local function notify(text, kind, duration)
    kind = kind or "info"
    local msg  = u8(text)
    local last = toasts[#toasts]
    if last and last.text == msg and os.clock() - last.t0 < 1.5 then
        last.t0 = os.clock()
        return
    end
    toasts[#toasts + 1] = { text = msg, kind = kind, t0 = os.clock(), dur = duration or (kind == "error" and 6 or 4) }
    while #toasts > 4 do table.remove(toasts, 1) end
end

local CONFIG_DIR  = getWorkingDirectory() .. "/config"
local CONFIG_PATH = CONFIG_DIR .. "/upg.json"

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

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

local function saveConfig()
    if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end
    local f = io.open(CONFIG_PATH, "w")
    if not f then return end
    f:write(string.format('{\n    "cardsNum": %d,\n    "needLVL": %d,\n    "scanLevels": %s,\n    "lowPC": %s,\n'
        .. '    "fmtHead": "%s",\n    "fmtCmd": %d,\n    "fmtLenW": %d,\n    "fmtTail": "%s"\n}\n',
        settings.cardsNum, settings.needLVL, tostring(settings.scanLevels), tostring(settings.lowPC),
        sendFmt and hexOf(sendFmt.head) or "", sendFmt and sendFmt.cmdPos or 0,
        sendFmt and sendFmt.lenW or 2, sendFmt and hexOf(sendFmt.tail) or ""))
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
                local src = type(data.settings) == "table" and data.settings or data
                settings.cardsNum   = clamp(math.floor(tonumber(src.cardsNum) or 1), 1, 100)
                settings.needLVL    = clamp(math.floor(tonumber(src.needLVL) or 10), 2, 10)
                settings.scanLevels = src.scanLevels ~= false
                if src.lowPC == nil then settings.lowPC = MOBILE else settings.lowPC = src.lowPC == true end
                if type(src.fmtHead) == "string" and src.fmtHead ~= "" then
                    local head = fromHex(src.fmtHead)
                    local pos  = math.floor(tonumber(src.fmtCmd) or 0)
                    if #head >= 2 and pos >= 2 and pos <= #head then
                        sendFmt = { head = head, cmdPos = pos, lenW = (tonumber(src.fmtLenW) == 4) and 4 or 2,
                                    tail = fromHex(src.fmtTail) }
                    end
                end
            end
        end
    end
    ui.cardsNum[0] = settings.cardsNum
    ui.needLVL[0]  = settings.needLVL
    saveConfig()
end

local function markDirty()
    dirtyAt = os.clock()
end

-- Новый протокол: пакет 220, тип 63 (клиент -> сервер).
-- По логу: 220, 63, iface=52, f1=-1, f2=<команда>, <json>
-- f2: 1 = переместить предмет, 2 = ПКМ по слоту, 3 = нажатие кнопки (использовать)
local cefSkip     = nil   -- раскладка заголовка пакета 84, определяется при приёме
local IFACE_INV   = 52
local SEND_TYPE   = 63
local GET_TYPE    = 84
local EV_MOVE, EV_SELECT, EV_USE = 1, 2, 3

-- Формат исходящего пакета 220/63 неизвестен заранее (по логу не видно ширину полей),
-- поэтому скрипт копирует заголовок из РЕАЛЬНОГО пакета, который клиент отправил при ручном клике
-- по предмету, и подставляет только команду (f2), длину и JSON. Формат сохраняется в upg.json.
-- Реальный формат из лога CEF Monitor: dc 3f | 34 | ff ff ff ff | cmd(int32) | len(u16) | json
-- т.е. после id/типа идут: iface=52 (1 байт), f1=-1 (int32), f2=команда (int32), длина (u16), текст.
local DEFAULT_FMT = { head = { 52, 255, 255, 255, 255, 0, 0, 0, 0 }, cmdPos = 6, lenW = 2, tail = {} }

local function dbgChat(text)
    if debugOn then
        pcall(sampAddChatMessage, cp("{FFAA00}[AUC dbg] {FFFFFF}" .. text), -1)
    end
end

local function buildRaw(fmt, cmd, payload)
    local raw = { PACKET_CEF, SEND_TYPE }
    for i, v in ipairs(fmt.head) do raw[#raw + 1] = (i == fmt.cmdPos) and cmd or v end
    local n = #payload
    raw[#raw + 1] = n % 256
    raw[#raw + 1] = math.floor(n / 256) % 256
    if fmt.lenW == 4 then
        raw[#raw + 1] = math.floor(n / 65536) % 256
        raw[#raw + 1] = math.floor(n / 16777216) % 256
    end
    for k = 1, n do raw[#raw + 1] = payload:byte(k) end
    for _, v in ipairs(fmt.tail) do raw[#raw + 1] = v end
    return raw
end

local function fmtKey(fmt)
    local head = {}
    for i, v in ipairs(fmt.head) do head[i] = (i == fmt.cmdPos) and 0 or v end
    return hexOf(head) .. "|" .. fmt.cmdPos .. "|" .. fmt.lenW .. "|" .. hexOf(fmt.tail)
end

-- raw: все байты пакета (1 = id 220, 2 = тип 63). Ищем JSON и 2/4 байта длины перед ним.
local function learnFormat(raw)
    local n = #raw
    if n < 9 or raw[1] ~= PACKET_CEF or raw[2] ~= SEND_TYPE then return false end
    for _, lenW in ipairs({ 2, 4 }) do
        for i = lenW + 4, n do
            if raw[i] == 0x7B then
                local L = raw[i - lenW] + raw[i - lenW + 1] * 256
                if lenW == 4 then L = L + raw[i - 2] * 65536 + raw[i - 1] * 16777216 end
                if L >= 2 and i + L - 1 <= n and raw[i + L - 1] == 0x7D then
                    local head, tail = {}, {}
                    for k = 3, i - lenW - 1 do head[#head + 1] = raw[k] end
                    for k = i + L, n do tail[#tail + 1] = raw[k] end
                    if head[1] ~= IFACE_INV then return false end
                    local cmdPos
                    if #head == 9 and head[2] == 255 and head[3] == 255 and head[4] == 255 and head[5] == 255 then
                        cmdPos = 6   -- iface, -1(int32), cmd(int32)
                    else
                        for k = #head, 2, -1 do
                            if head[k] ~= 0 then cmdPos = k break end
                        end
                    end
                    if not cmdPos then return false end
                    return true, { head = head, cmdPos = cmdPos, lenW = lenW, tail = tail }
                end
            end
        end
    end
    return false
end

local function sendCEF(cmd, payload)
    local fmt = sendFmt or DEFAULT_FMT
    local ok, err = pcall(function()
        local raw = buildRaw(fmt, cmd, payload)
        local bs = raknetNewBitStream()
        for _, v in ipairs(raw) do
            v = v % 256
            if v > 127 then v = v - 256 end
            raknetBitStreamWriteInt8(bs, v)
        end
        local send = raknetSendBitStreamEx or raknetSendBitStream
        ownSend = true
        local sent, e = pcall(send, bs, 1, 7, 0)
        ownSend = false
        raknetDeleteBitStream(bs)
        if not sent then error(e) end
        dbgChat((sendFmt and "SEND " or "SEND(guess) ") .. hexOf(raw))
    end)
    ownSend = false
    if not ok then dbgChat("sendCEF error: " .. tostring(err)) end
end

local function cefSelect(slot)
    sendCEF(EV_SELECT, string.format('{"slot":%d,"type":1}', slot))
end

local function cefUse(slot)
    sendCEF(EV_USE, string.format('{"action":1,"id":0,"slot":%d,"type":1}', slot))
end

local function cefMove(from, to)
    sendCEF(EV_MOVE, string.format('{"from":{"amount":1,"id":0,"slot":%d,"type":1},"to":{"slot":%d,"type":1}}', from, to))
end

local function chat(cmd)
    pcall(sampSendChat, cmd)
end

local function dialogActive()
    local ok, active = pcall(sampIsDialogActive)
    return ok and active
end

local function waitDialogClosed()
    local t = os.clock()
    while dialogActive() do
        if os.clock() - t > DIALOG_TIMEOUT then return end
        wait(10)
    end
end

local function waitFor(check, timeout, ignoreStop)
    local t = os.clock()
    while os.clock() - t < timeout do
        if check() then return true end
        if not ignoreStop and state.stopping then return false end
        wait(10)
    end
    return false
end

local function isExcluded(slot)
    for _, v in ipairs(excluded) do
        if v == slot then return true end
    end
    return false
end

local function exclude(slot)
    if slot and not isExcluded(slot) then excluded[#excluded + 1] = slot end
end

local function nearTable(extra)
    if not doesCharExist(PLAYER_PED) then return false end
    local x, y = getCharCoordinates(PLAYER_PED)
    return getDistanceBetweenCoords2d(x, y, TABLE_POS.x, TABLE_POS.y) < TABLE_POS.radius + (extra or 0)
end

local function cardLevel(slot)
    return cardLevels[slot] or 1
end

local function formatTime(sec)
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), math.floor(sec % 60))
end

local function resetStats()
    stats.attempts, stats.cards, stats.lube, stats.errors = 0, 0, 0, 0
    stats.curAttempts, stats.curStart, stats.history = 0, 0, {}
    state.sessionTime = 0
end

local function clearInventoryCache()
    cardLevels, levelSeen, knownCards, excluded = {}, {}, {}, {}
    cef.inventory, cef.slots, cef.lastData, cef.current = {}, {}, 0, nil
    probeDone = false
end

local function setMessage(text, status)
    ui.message = u8(text)
    ui.status  = status or ""
end

local function finish(reason, status)
    state.running, state.stopping = false, false
    signal.result, forceSlot, cef.current = nil, nil, nil
    excluded = {}
    setMessage(reason, status or "error")
    if reason == "Остановлен вручную" then
        notify(reason, "info")
    else
        notify(reason, status == "success" and "success" or "error")
    end
    saveConfig()
end

local function findNextCard()
    local list = {}
    for slot, item in pairs(cef.inventory) do
        if item == CARD_ITEM and not isExcluded(slot) then
            if cardLevel(slot) >= settings.needLVL then
                exclude(slot)
            else
                list[#list + 1] = slot
            end
        end
    end
    table.sort(list)
    return list[1]
end

local function openInventory()
    waitDialogClosed()
    if cef.opened and cef.lastData > 0 then return true end

    for _ = 1, 3 do
        cef.inventory, cef.lastData = {}, 0
        -- /invent переключает окно: если оно уже открыто, но данных нет, закрываем и открываем заново
        if cef.ifaceOpen then
            chat("/invent")
            waitFor(function() return not cef.ifaceOpen end, 2.0, true)
            wait(400)
        end
        chat("/invent")
        if waitFor(function() return cef.lastData > 0 end, OPEN_TIMEOUT) then
            wait(200)
            return true
        end
        if state.stopping then return false end
    end
    return false
end

local function unknownCards()
    local list = {}
    for slot, item in pairs(cef.inventory) do
        if item == CARD_ITEM and not levelSeen[slot] then list[#list + 1] = slot end
    end
    table.sort(list)
    return list
end

local function emptySlots()
    local list = {}
    for slot in pairs(cef.slots) do
        if not cef.inventory[slot] then list[#list + 1] = slot end
    end
    table.sort(list)
    return list
end

local function readLevels(shouldContinue)
    local cards = unknownCards()
    if #cards == 0 then return true end
    if #emptySlots() == 0 then
        notify("Нет свободного слота в инвентаре для чтения уровней", "warn")
        return false
    end

    local fails = 0
    for i, slot in ipairs(cards) do
        if not shouldContinue() then return false end
        ui.message = u8(string.format("Читаю уровни карт: %d / %d", i, #cards))

        local done = false
        for attempt = 1, 3 do
            local empty = emptySlots()[1]
            if levelSeen[slot] then done = true break end
            if not empty or cef.inventory[slot] ~= CARD_ITEM then break end

            levelSeen[empty] = nil
            cefMove(slot, empty)
            if waitFor(function() return levelSeen[empty] end, 3.0, true) then
                local level = cardLevels[empty] or 1
                levelSeen[slot] = nil
                cefMove(empty, slot)
                waitFor(function() return levelSeen[slot] end, 3.0, true)
                cardLevels[slot], levelSeen[slot] = level, true
                cardLevels[empty], levelSeen[empty] = nil, nil
                done = true
                break
            end
            cefMove(empty, slot)
            wait(900 * attempt)
        end

        if done then
            fails = 0
            wait(120)
        else
            fails = fails + 1
            if fails >= 3 then return false end
        end
    end
    return true
end

local function scanInventory()
    if state.running or ui.scanning then return end

    local total, unknown = 0, 0
    for slot in pairs(knownCards) do
        total = total + 1
        if not levelSeen[slot] then unknown = unknown + 1 end
    end
    if total > 0 and unknown == 0 then
        notify("Уровни уже известны. Нажмите «Очистить», чтобы прочитать заново", "info", 5)
        return
    end

    ui.scanning = true
    lua_thread.create(function()
        local good = false
        local ok = pcall(function()
            local openedHere = false
            if not (cef.opened and cef.lastData > 0) then
                if not openInventory() then
                    notify("Не удалось открыть инвентарь", "error")
                    return
                end
                openedHere = true
            end

            if next(cef.inventory) == nil or not next(knownCards) then
                notify("Видеокарт в инвентаре не найдено", "warn")
            else
                good = readLevels(function() return ui.scanning end)
            end

            wait(250)
        end)
        ui.scanning = false
        if ok and good then
            notify(cef.ifaceOpen and "Уровни обновлены. Закройте инвентарь вручную" or "Уровни видеокарт обновлены", "success", 5)
        elseif ok then
            notify("Не все уровни удалось определить", "warn")
        end
    end)
end

local function worker()
    local retries, errorsInRow = 0, 0

    local remain = UPGRADE_DURATION - (os.clock() - lastUseAt)
    if remain > 0 then
        setMessage("Жду окончания прошлого улучшения...")
        notify(string.format("Жду окончания прошлого улучшения (%d с)", math.ceil(remain)), "info")
        waitFor(function() return os.clock() - lastUseAt >= UPGRADE_DURATION end, remain + 1)
        signal.result = nil
    end

    while true do
        repeat
            if state.stopping then return finish("Остановлен вручную", "info") end
            if not nearTable(1.5) then return finish("Вы отошли от стола") end
            if state.done >= settings.cardsNum then
                return finish(string.format("Все %d карт улучшены!", settings.cardsNum), "success")
            end

            if not openInventory() then
                if state.stopping then return finish("Остановлен вручную", "info") end
                return finish("Не удалось открыть инвентарь")
            end

            if settings.scanLevels and not probeDone then
                probeDone = true
                readLevels(function() return not state.stopping end)
                if state.stopping then return finish("Остановлен вручную", "info") end
            end

            local slot = forceSlot
            forceSlot = nil
            if slot == nil or isExcluded(slot) then slot = findNextCard() end

            if not slot then
                local total, ready = 0, 0
                for s, item in pairs(cef.inventory) do
                    if item == CARD_ITEM then
                        total = total + 1
                        if cardLevel(s) >= settings.needLVL then ready = ready + 1 end
                    end
                end
                if total == 0 then return finish("Видеокарт в инвентаре не найдено") end
                if ready >= total then
                    return finish(string.format("Все видеокарты (%d шт.) уже имеют %d уровень или выше", total, settings.needLVL), "success")
                end
                return finish("Подходящих видеокарт больше нет")
            end

            cef.current   = slot
            signal.result = nil
            setMessage(string.format("Слот %d: улучшаю...", slot))
            if stats.curStart == 0 then stats.curStart = cardLevel(slot) end

            if not sendFmt then
                -- формат берём по умолчанию из лога; если игрок сам кликнет по карте, он уточнится
                dbgChat("формат пакета по умолчанию (из лога)")
            end
            cefSelect(slot)   -- как настоящий клиент: сперва выбор слота ({"slot":N,"type":1})
            wait(450)
            cefUse(slot)      -- затем «Использовать» ({"action":1,"id":0,"slot":N,"type":1})
            lastUseAt = os.clock()
            wait(300)
            waitDialogClosed()

            if not waitFor(function() return signal.result ~= nil end, RESULT_TIMEOUT, true) then
                retries = retries + 1
                cef.opened, cef.lastData, cef.inventory = false, 0, {}
                if retries >= MAX_RETRIES then return finish("Сервер не ответил на улучшение") end
                forceSlot = slot
                wait(1200)
                break
            end

            local res = signal.result
            signal.result = nil
            cef.opened, cef.lastData, cef.inventory = false, 0, {}
            if res.kind ~= "error" then errorsInRow = 0 end

            if res.kind == "success" then
                retries = 0
                stats.curAttempts = stats.curAttempts + 1
                stats.attempts    = stats.attempts + 1
                stats.lube        = stats.lube + LUBE_PER_TRY
                if res.level <= 0 then res.level = cardLevel(slot) + 1 end
                cardLevels[slot], levelSeen[slot] = res.level, true

                if res.level >= settings.needLVL then
                    state.done = state.done + 1
                    stats.cards = stats.cards + 1
                    table.insert(stats.history, { from = stats.curStart, to = res.level, tries = stats.curAttempts })
                    stats.curAttempts, stats.curStart = 0, 0
                    exclude(slot)
                    cef.current = nil
                    local text = string.format("Карта #%d улучшена до %d уровня", state.done, res.level)
                    setMessage(text, "success")
                    notify(text, "success")
                else
                    setMessage(string.format("Уровень %d, продолжаю", res.level))
                    forceSlot = slot
                end
                wait(900)

            elseif res.kind == "error" then
                stats.curAttempts = stats.curAttempts + 1
                stats.attempts    = stats.attempts + 1
                stats.lube        = stats.lube + LUBE_PER_TRY
                stats.errors      = stats.errors + 1
                errorsInRow       = errorsInRow + 1
                setMessage(string.format("Техническая ошибка (всего %d), пробую снова", stats.errors))
                notify(string.format("Техническая ошибка, пробую снова (всего: %d)", stats.errors), "warn", 3)
                if errorsInRow >= MAX_ERRORS then return finish("Слишком много технических ошибок подряд") end
                forceSlot = slot
                wait(1500)

            elseif res.kind == "max" then
                retries = 0
                notify("Карта на максимуме, ищу следующую", "info", 3)
                exclude(slot)
                stats.curStart, cef.current = 0, nil
                wait(900)

            elseif res.kind == "nolube" then
                return finish("Закончились смазки!")

            elseif res.kind == "nothouse" then
                return finish("Вы не в доме! Зайдите в дом и встаньте у стола в подвале")

            elseif res.kind == "othererr" then
                retries = retries + 1
                local text = res.text or "Ошибка сервера"
                setMessage(text)
                notify(text, "warn", 4)
                if retries >= MAX_RETRIES then return finish("Ошибка сервера: " .. text) end
                forceSlot = slot
                wait(1500)
            end
        until true
    end
end

local function startScript()
    if state.running then return end
    if ui.scanning then
        notify("Подождите, идёт чтение уровней", "warn")
        return
    end
    if not isSampAvailable() or not doesCharExist(PLAYER_PED) then return end
    if not nearTable() then
        setMessage("Для запуска встаньте возле стола в подвале", "error")
        notify("Для запуска встаньте возле стола в подвале", "warn")
        return
    end

    local total, ready, unknown = 0, 0, 0
    for slot in pairs(knownCards) do
        total = total + 1
        if levelSeen[slot] then
            if cardLevel(slot) >= settings.needLVL then ready = ready + 1 end
        else
            unknown = unknown + 1
        end
    end
    if total > 0 and unknown == 0 and ready >= total then
        local text = string.format("Все видеокарты (%d шт.) уже имеют %d уровень или выше", total, settings.needLVL)
        setMessage(text, "success")
        notify(text, "success")
        return
    end

    setMessage("")
    if not (cef.opened and cef.lastData > 0) then
        cef.inventory, cef.lastData = {}, 0
    end
    cef.current, signal.result, forceSlot = nil, nil, nil
    probeDone = false
    excluded = {}
    stats.curAttempts, stats.curStart, stats.history = 0, 0, {}
    state.done, state.stopping = 0, false
    state.sessionStart, state.sessionTime = os.clock(), 0
    state.running = true

    sampAddChatMessage(cp("{3685f5}| {ffffff}Запуск улучшения видеокарт..."), -1)

    lua_thread.create(function()
        local ok = pcall(worker)
        if not ok and state.running then finish("Внутренняя ошибка, запустите заново") end
    end)
end

local function requestStop()
    if not state.running or state.stopping then return end
    state.stopping = true
    setMessage("Останавливаю после текущей попытки...", "info")
    notify("Остановка после текущей попытки", "info")
end

local function openLink()
    if not MOBILE then
        pcall(function()
            ffi.cdef("void* ShellExecuteA(void*, const char*, const char*, const char*, const char*, int);")
        end)
        local ok = pcall(function()
            ffi.load("shell32").ShellExecuteA(nil, "open", TG_URL, nil, nil, 1)
        end)
        notify(ok and "Открываю Telegram-канал" or "Не удалось открыть ссылку", ok and "info" or "error", 3)
        return
    end

    -- на телефоне: пробуем открыть, и на всякий случай копируем ссылку в буфер
    pcall(os.execute, 'am start -a android.intent.action.VIEW -d "' .. TG_URL .. '" >/dev/null 2>&1')
    local copied = pcall(imgui.SetClipboardText, TG_URL)
    notify(copied and "Ссылка на канал скопирована в буфер" or ("Канал: " .. TG_URL), "info", 4)
end

function events.onShowDialog(id, style, title, btn1, btn2, text)
    if not state.running then return end
    local isUpgrade = id == 274 or (type(title) == "string" and title:find(cp("Улучшение видеокарты"), 1, true))
    if not isUpgrade and os.clock() - lastUseAt < 8 then
        local vc = cp("видеокарт")
        isUpgrade = (type(title) == "string" and title:find(vc, 1, true))
            or (type(text) == "string" and text:find(vc, 1, true))
    end
    if not isUpgrade then return end
    local button = 1
    if type(btn2) == "string" and btn2:find(cp("Улучшить"), 1, true) then button = 0 end
    pcall(sampSendDialogResponse, id, button, -1, "")
    return false
end

function events.onCreate3DText(creator, color, position, distance, testLOS, attached, id, text)
    if type(text) == "string" and text:find(cp("Чтобы улучшить видеокарту"), 1, true) then
        local newText = cp("Чтобы улучшить видеокарту,\nиспользуйте у стола\nчерез инвентарь\n\n"
            .. "{FFFFFF}Меню скрипта: введите: {FF0000}/upg\n"
            .. "{FFFFFF}By {FF0000}Stalin")
        return { creator, color, position, distance, testLOS, attached, id, newText }
    end
end

-- Заголовок пакета 84: [220][84][iface][sub][длина:int16][enc:int8][данные].
-- Точный размер iface/sub по логу не определить, поэтому пробуем несколько
-- вариантов и берём тот, где после разбора получился JSON.
local SKIP_TRY    = { 2, 4, 3, 1, 5, 6 }
local dumpedCount = 0

local function readAt(bs, skip, needJson)
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
    if needJson then
        local first = str:match("^%s*(.)")
        if first ~= "{" and first ~= "[" then return nil end
    end
    return str
end

local function dumpHeader(bs)
    if dumpedCount >= 2 then return end
    dumpedCount = dumpedCount + 1
    local parts = {}
    pcall(function()
        raknetBitStreamResetReadPointer(bs)
        local n = math.min(16, math.floor(raknetBitStreamGetNumberOfBitsUsed(bs) / 8))
        for i = 1, n do parts[i] = string.format("%02X", raknetBitStreamReadInt8(bs) % 256) end
        raknetBitStreamResetReadPointer(bs)
    end)
    sampAddChatMessage(cp("{FF5555}[Auto Upgrade Cards] {FFFFFF}Не удалось разобрать пакет 84. Начало: " .. table.concat(parts, " ")), -1)
end

local function readCefString(bs)
    raknetBitStreamResetReadPointer(bs)
    if raknetBitStreamGetNumberOfBitsUsed(bs) < 80 then return nil end

    raknetBitStreamIgnoreBits(bs, 8)
    local ptype = raknetBitStreamReadInt8(bs)

    if ptype == 17 then
        return readAt(bs, 4, false)   -- старый формат
    end
    if ptype ~= GET_TYPE then return nil end

    if cefSkip then
        local str = readAt(bs, cefSkip, true)
        if str then return str end
    end
    for _, skip in ipairs(SKIP_TRY) do
        local ok, str = pcall(readAt, bs, skip, true)
        if ok and str then
            cefSkip = skip
            return str
        end
    end
    dumpHeader(bs)
    return nil
end

local function parseInventory(str)
    for body in str:gmatch("{([^{}]-)}") do
        if body:find('"available"', 1, true) then
            local slot = tonumber(body:match('"slot"%s*:%s*(%d+)'))
            if slot then
                if body:match('"available"%s*:%s*(%d+)') == "1" then cef.slots[slot] = true end
                local item = tonumber(body:match('"item"%s*:%s*(%d+)'))
                if item then
                    cef.inventory[slot] = item
                    if item == CARD_ITEM then
                        knownCards[slot] = true
                        local level = tonumber(body:match('"text"%s*:%s*"(%d+)%s*[lL][vV][lL]"'))
                        if level then
                            cardLevels[slot], levelSeen[slot] = level, true
                        else
                            cardLevels[slot] = cardLevels[slot] or 1
                        end
                    else
                        knownCards[slot] = nil
                    end
                    if item == LUBE_ITEM then
                        cef.lube = tonumber(body:match('"amount"%s*:%s*(%d+)')) or cef.lube
                    end
                else
                    cef.inventory[slot] = nil
                    cardLevels[slot], levelSeen[slot], knownCards[slot] = nil, nil, nil
                end
            end
        end
    end
end

local function parseLevels(str)
    for slot, level in str:gmatch('"slot"%s*:%s*(%d+)[^}]-"text"%s*:%s*"(%d+)%s*[lL][vV][lL]"') do
        cardLevels[tonumber(slot)], levelSeen[tonumber(slot)] = tonumber(level), true
    end
    for level, slot in str:gmatch('"text"%s*:%s*"(%d+)%s*[lL][vV][lL]"[^}]-"slot"%s*:%s*(%d+)') do
        cardLevels[tonumber(slot)], levelSeen[tonumber(slot)] = tonumber(level), true
    end
end

function HK.hookReceivePacket(id, bs)
    if id ~= PACKET_CEF then return end

    local ok, str = pcall(readCefString, bs)
    pcall(raknetBitStreamResetReadPointer, bs)
    if not ok or type(str) ~= "string" then return end
    str = unescapeU(str)

    if debugOn and (str:find('"styleInt"', 1, true) or str:find('"bits"', 1, true)) then
        dbgChat("GET " .. str:sub(1, 150))
    end

    if str:find("lvl", 1, true) and str:find('"slot"', 1, true) then
        pcall(parseLevels, str)
    end

    -- данные инвентаря (тип 1): первый кусок содержит слот 0 и max_slot
    if str:find('"type":1,"items"', 1, true) then
        if str:find('"max_slot"', 1, true) and str:find('{"slot":0,', 1, true) then cef.inventory = {} end
        pcall(parseInventory, str)
        if str:find('"max_slot"', 1, true) then
            cef.opened, cef.lastData = true, os.clock()
        end
    end

    local bitsSlot = str:match('"slot"%s*:%s*(%d+)%s*,%s*"bits"')
    if bitsSlot then cef.bitsSlot = tonumber(bitsSlot) end

    local notHouse = has(str, "Вы не в доме")
    if notHouse and ui.scanning then
        ui.scanning = false
        notify("Вы не в доме! Чтение уровней остановлено", "error")
    end

    if not state.running then return end

    if has(str, "Вы успешно улучшили выбранную видеокарту") then
        local level = tonumber(matchAny(str, "видеокарту до (%d+)%-го уровня")) or 0
        signal.result = { kind = "success", level = level }
    elseif has(str, "При улучшении видеокарты вы допустили техническую ошибку") then
        signal.result = { kind = "error" }
    elseif has(str, "смазк") and has(str, "нужн") then
        signal.result = { kind = "nolube" }
    elseif has(str, "уже прокачана до максимального уровня") then
        signal.result = { kind = "max" }
    elseif notHouse then
        signal.result = { kind = "nothouse" }
    elseif str:find('"styleInt":2', 1, true) then
        local text = str:match('"text"%s*:%s*"(.-)"') or "Неизвестная ошибка сервера"
        signal.result = { kind = "othererr", text = srcText(text) }
    end
end

-- клиент шлёт 66/iface 52 с флагом: true = окно открыто, false = закрыто
local function readRaw(bs)
    local count = math.floor(raknetBitStreamGetNumberOfBitsUsed(bs) / 8)
    if count < 2 or count > 700 then return nil end
    raknetBitStreamResetReadPointer(bs)
    local raw = {}
    for i = 1, count do raw[i] = raknetBitStreamReadInt8(bs) % 256 end
    raknetBitStreamResetReadPointer(bs)
    return raw
end


-- ===== Диагностика: /upgsniff =====
-- Пишет в config/upg_sniff.txt ВСЕ исходящие пакеты и RPC в течение 25 секунд.
-- Нужно, чтобы увидеть, что именно клиент отправляет при нажатии «Использовать» на карте.
HK.sniff = { on = false, until_ = 0, lines = {}, total = 0 }
local SYNC_IDS = { [200]=1,[201]=1,[203]=1,[204]=1,[205]=1,[206]=1,[207]=1,[208]=1,[209]=1,[210]=1,[211]=1,[212]=1 }

function HK.sniffAdd(kind, id, bs)
    if not HK.sniff.on then return end
    HK.sniff.total = HK.sniff.total + 1
    if kind == "PKT" and SYNC_IDS[id] then return end
    local ok, raw = pcall(function()
        local total = raknetBitStreamGetNumberOfBytesUsed(bs)
        if not total or total < 1 then return "" end
        local n = math.min(total, 300)
        local ptr = raknetBitStreamGetDataPtr(bs)
        local p = ffi.cast("const uint8_t*", ffi.cast("uintptr_t", ptr))
        local t = {}
        for i = 1, n do t[i] = string.format("%02X", p[i - 1]) end
        return table.concat(t, " ")
    end)
    HK.sniff.lines[#HK.sniff.lines + 1] = string.format("[%.3f] %s id=%s  %s", os.clock(), kind, tostring(id), ok and raw or ("ERR " .. tostring(raw)))
end

function HK.sniffStart()
    if HK.sniff.on then return end
    HK.sniff.on, HK.sniff.until_, HK.sniff.lines, HK.sniff.total = true, os.clock() + 25, {}, 0
    sampAddChatMessage(cp("{FFAA00}[AUC] {FFFFFF}Хуки: " .. HK.mode), -1)
    sampAddChatMessage(cp("{FFAA00}[AUC] {FFFFFF}Запись 25 сек. Откройте инвентарь и нажмите «Использовать» на карте у стола."), -1)
    lua_thread.create(function()
        while os.clock() < HK.sniff.until_ do wait(100) end
        HK.sniff.on = false
        local text = table.concat(HK.sniff.lines, "\n")
        local saved = {}
        for _, path in ipairs({ getWorkingDirectory() .. "/upg_sniff.txt", CONFIG_DIR .. "/upg_sniff.txt" }) do
            local ok = pcall(function()
                if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end
                local f = io.open(path, "w")
                if f then f:write(text) f:close() saved[#saved + 1] = path end
            end)
        end
        sampAddChatMessage(cp(string.format("{FFAA00}[AUC] {FFFFFF}Готово. Событий: %d, строк: %d, файл: %s",
            HK.sniff.total, #HK.sniff.lines, saved[1] or "НЕ ЗАПИСАН")), -1)
        if HK.sniff.total == 0 then
            sampAddChatMessage(cp("{FF5555}[AUC] {FFFFFF}События не приходят - хуки не работают"), -1)
        end
        -- последние строки дублируем в чат: можно сделать скриншот
        for i = math.max(1, #HK.sniff.lines - 11), #HK.sniff.lines do
            sampAddChatMessage(cp("{AAAAAA}" .. HK.sniff.lines[i]:sub(1, 110)), -1)
        end
    end)
end

function HK.hookSendRpc(id, bs)
    HK.sniffAdd("RPC", id, bs)
end

function HK.hookSendPacket(id, bs)
    HK.sniffAdd("PKT", id, bs)
    if id ~= PACKET_CEF or ownSend then return end
    local ok, raw = pcall(readRaw, bs)
    if not ok or not raw or #raw < 4 then return end

    if raw[2] == 66 then
        local value = raw[3] + raw[4] * 256
        local iface = bit.band(value, 0x7FFF)
        local open  = bit.band(value, 0x8000) ~= 0
        if iface == IFACE_INV then
            cef.ifaceOpen = open
            if not open then cef.opened, cef.lastData = false, 0 end
        end
    elseif raw[2] == SEND_TYPE then
        local good, fmt = learnFormat(raw)
        if debugOn then dbgChat("CLIENT " .. hexOf(raw) .. (good and " (формат ок)" or " (не распознан)")) end
        if good then
            pcall(function()
                local cmd = raw[fmt.cmdPos]
                local from = #fmt.head + fmt.lenW + 3
                local chars = {}
                for k = from, #raw do chars[#chars + 1] = string.char(raw[k]) end
                local payload = table.concat(chars)
                local old = EV_MOVE .. "/" .. EV_SELECT .. "/" .. EV_USE
                if payload:find('"action"', 1, true) then EV_USE = cmd
                elseif payload:find('"from"', 1, true) then EV_MOVE = cmd
                elseif payload:find('"slot"', 1, true) then EV_SELECT = cmd end
                if old ~= EV_MOVE .. "/" .. EV_SELECT .. "/" .. EV_USE then
                    dbgChat("команды: move/select/use = " .. EV_MOVE .. "/" .. EV_SELECT .. "/" .. EV_USE)
                end
            end)
        end
        if good and (not sendFmt or fmtKey(sendFmt) ~= fmtKey(fmt)) then
            sendFmt = fmt
            markDirty()
            notify("Формат пакета изучен и сохранён", "success", 4)
            dbgChat("формат: " .. fmtKey(fmt))
        end
    end
end

local W, H       = 760, 540
local S          = 1   -- масштаб интерфейса (на телефоне подстраивается под экран)
local CONTENT_X  = 208
local CONTENT_W  = 532

local function V2(x, y) return imgui.ImVec2(x, y) end
local function V4(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end

local pal = {
    bg     = V4(0.040, 0.044, 0.068),
    card   = V4(0.082, 0.090, 0.132),
    card2  = V4(0.122, 0.134, 0.192),
    card3  = V4(0.170, 0.186, 0.262),
    border = V4(1, 1, 1, 0.07),
    violet = V4(0.520, 0.400, 1.000),
    pink   = V4(0.960, 0.360, 0.700),
    cyan   = V4(0.200, 0.830, 0.960),
    good   = V4(0.250, 0.860, 0.540),
    bad    = V4(0.960, 0.320, 0.380),
    warn   = V4(0.985, 0.790, 0.300),
    text   = V4(0.950, 0.960, 0.985),
    dim    = V4(0.560, 0.590, 0.690),
    white  = V4(1, 1, 1),
    tg     = V4(0.160, 0.620, 0.860),
}

local fonts = {}

local function lerp(a, b, t) return a + (b - a) * t end
local function ease(t) return 1 - (1 - t) ^ 3 end

local function mix(a, b, t)
    return V4(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t), lerp(a.w, b.w, t))
end

local uiAlpha, bx, by, frameDt = 1, 0, 0, 0.016
local hoverState = {}

local function C(color, alpha)
    return imgui.GetColorU32Vec4(V4(color.x, color.y, color.z, (alpha or color.w) * uiAlpha))
end

local function winPoint(x, y)
    local p = imgui.GetWindowPos()
    return V2(p.x + (bx + x) * S, p.y + (by + y) * S)
end

local function cursor(x, y)
    imgui.SetCursorPos(V2((bx + x) * S, (by + y) * S))
end

local function invBtn(id, size)
    return imgui.InvisibleButton(id, V2(size.x * S, size.y * S))
end

-- обёртка над DrawList: масштабирует радиусы, скругления и толщину линий
local dlReal
local dlProxy = {}
function dlProxy:AddRectFilled(a, b, col, r) dlReal:AddRectFilled(a, b, col, (r or 0) * S) end
function dlProxy:AddRect(a, b, col, r) dlReal:AddRect(a, b, col, (r or 0) * S) end
function dlProxy:AddCircleFilled(p, r, col, n) dlReal:AddCircleFilled(p, r * S, col, n) end
function dlProxy:AddCircle(p, r, col, n, th) dlReal:AddCircle(p, r * S, col, n, (th or 1) * S) end
function dlProxy:AddLine(a, b, col, th) dlReal:AddLine(a, b, col, (th or 1) * S) end
function dlProxy:AddTriangleFilled(a, b, c, col) dlReal:AddTriangleFilled(a, b, c, col) end
function dlProxy:AddRectFilledMultiColor(a, b, c1, c2, c3, c4) dlReal:AddRectFilledMultiColor(a, b, c1, c2, c3, c4) end
function dlProxy:AddText(p, col, s) dlReal:AddText(p, col, s) end
function dlProxy:PushClipRect(a, b, i) dlReal:PushClipRect(a, b, i) end
function dlProxy:PopClipRect() dlReal:PopClipRect() end

local function getDL()
    dlReal = imgui.GetWindowDrawList()
    return dlProxy
end

local function hoverT(id, hovered)
    if settings.lowPC then return hovered and 1 or 0 end
    local v = hoverState[id] or 0
    v = v + ((hovered and 1 or 0) - v) * math.min(1, frameDt * 14)
    hoverState[id] = v
    return v
end

local function fillRect(x, y, w, h, color, rounding, alpha)
    getDL():AddRectFilled(winPoint(x, y), winPoint(x + w, y + h), C(color, alpha), rounding or 0)
end

local function strokeRect(x, y, w, h, color, rounding, alpha)
    getDL():AddRect(winPoint(x, y), winPoint(x + w, y + h), C(color, alpha), rounding or 0)
end

local function gradientRect(x, y, w, h, left, right, alpha)
    getDL():AddRectFilledMultiColor(winPoint(x, y), winPoint(x + w, y + h),
        C(left, alpha), C(right, alpha), C(right, alpha), C(left, alpha))
end

local function glow(cx, cy, radius, color, alpha)
    local dl = getDL()
    for i = 1, 7 do
        local k = i / 7
        dl:AddCircleFilled(winPoint(cx, cy), radius * (1.1 - k * 0.85), C(color, alpha * 0.22), 32)
    end
end

local function card(x, y, w, h, rounding)
    fillRect(x, y, w, h, pal.card, rounding or 16)
    strokeRect(x, y, w, h, pal.border, rounding or 16)
end

local function textSize(str, font)
    if font then imgui.PushFont(font) end
    local s = imgui.CalcTextSize(str)
    if font then imgui.PopFont() end
    return s.x / S, s.y / S
end

local function drawText(x, y, str, color, font, alpha)
    if font then imgui.PushFont(font) end
    getDL():AddText(winPoint(x, y), C(color or pal.text, alpha), str)
    if font then imgui.PopFont() end
end

local ICON_CODES = {
    ICON_FA_HOME = 0xf015, ICON_FA_TH_LARGE = 0xf009, ICON_FA_SLIDERS_H = 0xf1de, ICON_FA_CHART_BAR = 0xf080,
    ICON_FA_TIMES = 0xf00d, ICON_FA_SYNC_ALT = 0xf2f1, ICON_FA_TRASH_ALT = 0xf2ed, ICON_FA_UNDO = 0xf0e2,
    ICON_FA_STAR = 0xf005, ICON_FA_TINT = 0xf043, ICON_FA_CHECK = 0xf00c, ICON_FA_EXCLAMATION = 0xf12a,
    ICON_FA_EXCLAMATION_TRIANGLE = 0xf071, ICON_FA_INFO = 0xf129, ICON_FA_PLAY = 0xf04b, ICON_FA_STOP = 0xf04d,
    ICON_FA_HOURGLASS_HALF = 0xf252,
}

local iconsReady = false
local iconCache = {}

local function glyph(name)
    if not iconsReady then return nil end
    local g = iconCache[name]
    if g == nil then
        local code = ICON_CODES[name]
        g = code and string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64) or false
        iconCache[name] = g
    end
    return g or nil
end

local function drawGlyph(name, cx, cy, color, font, alpha)
    local g = glyph(name)
    if not g then return false end
    local w, h = textSize(g, font)
    drawText(cx - w / 2, cy - h / 2, g, color, font, alpha)
    return true
end

local function withGlyph(name, label)
    local g = glyph(name)
    return g and (g .. "  " .. label) or label
end

local function textCenter(cx, y, str, color, font)
    local w = textSize(str, font)
    drawText(cx - w / 2, y, str, color, font)
end

local function textRight(rx, y, str, color, font)
    local w = textSize(str, font)
    drawText(rx - w, y, str, color, font)
end

local wrapCache, wrapCount = {}, 0

local function wrapText(str, maxW, font, maxLines)
    local key = str .. "|" .. maxW
    local cached = wrapCache[key]
    if cached then return cached end
    local lines, current = {}, ""
    for word in str:gmatch("%S+") do
        local try = current == "" and word or (current .. " " .. word)
        if textSize(try, font) > maxW and current ~= "" then
            lines[#lines + 1] = current
            current = word
        else
            current = try
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    while #lines > (maxLines or 3) do table.remove(lines) end
    if wrapCount > 60 then wrapCache, wrapCount = {}, 0 end
    wrapCache[key] = lines
    wrapCount = wrapCount + 1
    return lines
end

local function chip(id, label, x, y, w, h, active)
    cursor(x, y)
    local clicked = invBtn("##" .. id, V2(w, h))
    local t = hoverT(id, imgui.IsItemHovered())
    local round = h / 2
    if active then
        gradientRect(x + round, y, w - round * 2, h, pal.violet, pal.cyan)
        fillRect(x, y, round * 2, h, pal.violet, round)
        fillRect(x + w - round * 2, y, round * 2, h, pal.cyan, round)
    else
        fillRect(x, y, w, h, mix(pal.card2, pal.card3, t), round)
        strokeRect(x, y, w, h, pal.violet, round, 0.45 * t)
    end
    local tw, th = textSize(label, fonts.main)
    drawText(x + (w - tw) / 2, y + (h - th) / 2, label, active and pal.white or mix(pal.dim, pal.text, t), fonts.main)
    return clicked
end

local function toggle(id, x, y, value)
    cursor(x, y)
    local clicked = invBtn("##" .. id, V2(52, 28))
    local t = hoverState[id .. "v"] or (value and 1 or 0)
    t = settings.lowPC and (value and 1 or 0) or t + ((value and 1 or 0) - t) * math.min(1, frameDt * 14)
    hoverState[id .. "v"] = t
    fillRect(x, y, 52, 28, mix(pal.card3, pal.violet, t), 14)
    if t > 0.02 then fillRect(x, y, 52, 28, pal.cyan, 14, 0.35 * t) end
    getDL():AddCircleFilled(winPoint(x + 14 + t * 24, y + 14), 10, C(pal.white), 20)
    return clicked
end

local function helpIcon(id, x, y, text)
    cursor(x, y)
    invBtn("##help" .. id, V2(22, 22))
    local t = hoverT("help" .. id, imgui.IsItemHovered())
    local cx, cy = x + 11, y + 11
    local dl = getDL()
    dl:AddCircleFilled(winPoint(cx, cy), 10, C(mix(pal.card3, pal.violet, t)), 20)
    dl:AddCircle(winPoint(cx, cy), 10, C(pal.violet, 0.45 + 0.55 * t), 20, 1.2)
    local tw, th = textSize("?", fonts.bold)
    drawText(cx - tw / 2, cy - th / 2, "?", mix(pal.dim, pal.white, t), fonts.bold)
    if t > 0.02 and (not ui.help or t > ui.help.t) then
        ui.help = { text = text, x = bx + cx, y = by + cy, t = t }
    end
end

local scrollState = {}

local function scrollArea(id, x, y, w, h, contentH, drawContent)
    cursor(x, y)
    invBtn("##scroll" .. id, V2(w, h))
    local hovered = imgui.IsItemHovered()
    local active  = imgui.IsItemActive()

    local s = scrollState[id]
    if not s then
        s = { pos = 0, shown = 0, vel = 0, dragging = false, lastY = 0 }
        scrollState[id] = s
    end

    local maxScroll = math.max(0, contentH - h)
    if hovered then
        local wheel = imgui.GetIO().MouseWheel or 0
        if wheel ~= 0 then s.pos = s.pos - wheel * 68; s.vel = 0 end
    end

    -- прокрутка пальцем / перетаскиванием мыши + инерция после отпускания
    local my = imgui.GetMousePos().y
    if active then
        if s.dragging then
            local dy = (my - s.lastY) / S
            s.pos = s.pos - dy
            local v = -dy / math.max(frameDt, 0.004)
            s.vel = clamp(s.vel * 0.6 + v * 0.4, -5000, 5000)
        else
            s.vel = 0
        end
        s.dragging, s.lastY = true, my
    else
        s.dragging = false
        if math.abs(s.vel) > 12 then
            s.pos = s.pos + s.vel * frameDt
            s.vel = s.vel * math.max(0, 1 - frameDt * 3.5)
        else
            s.vel = 0
        end
    end
    if s.pos < 0 or s.pos > maxScroll then s.vel = 0 end
    s.pos = clamp(s.pos, 0, maxScroll)
    if active or settings.lowPC or math.abs(s.vel) > 0 then
        s.shown = s.pos
    else
        s.shown = lerp(s.shown, s.pos, math.min(1, frameDt * 16))
    end

    local dl = getDL()
    dl:PushClipRect(winPoint(x, y), winPoint(x + w, y + h), true)
    drawContent(x, y - s.shown, y, y + h)
    dl:PopClipRect()

    if maxScroll > 0 then
        local barH = math.max(30, h * h / contentH)
        local barY = y + (h - barH) * (s.shown / maxScroll)
        fillRect(x + w - 6, y, 4, h, pal.card2, 2)
        fillRect(x + w - 6, barY, 4, barH, (hovered or active) and pal.violet or pal.card3, 2)
    end
end

local function tile(x, y, w, h, label, value, color, iconName)
    card(x, y, w, h, 14)
    fillRect(x + 12, y + 14, 3, h - 28, color, 2)
    drawText(x + 24, y + 10, label, pal.dim, fonts.main)
    if iconName then drawGlyph(iconName, x + w - 22, y + h - 24, color, fonts.main, 0.85) end
    drawText(x + 24, y + h - 34, value, pal.text, fonts.big)
end

local function drawRing(cx, cy, radius, thick, frac)
    local dl = getDL()
    local center = winPoint(cx, cy)
    dl:AddCircle(center, radius, C(pal.card2), 64, thick)
    if frac <= 0 then return end
    local segs = math.max(4, math.floor(80 * frac))
    local prev
    for i = 0, segs do
        local t = i / segs
        local a = -math.pi / 2 + 2 * math.pi * frac * t
        local pt = V2(center.x + math.cos(a) * radius * S, center.y + math.sin(a) * radius * S)
        local col = C(mix(pal.violet, pal.cyan, t))
        if prev then dl:AddLine(prev, pt, col, thick) end
        dl:AddCircleFilled(pt, thick / 2, col, 12)
        prev = pt
    end
end

local function drawIcon(kind, cx, cy, color, alpha)
    local dl = getDL()
    local c = C(color, alpha)
    if kind == "home" then
        dl:AddTriangleFilled(winPoint(cx - 11, cy - 1), winPoint(cx, cy - 11), winPoint(cx + 11, cy - 1), c)
        dl:AddRectFilled(winPoint(cx - 7, cy - 1), winPoint(cx + 7, cy + 9), c, 2)
        dl:AddRectFilled(winPoint(cx - 2, cy + 3), winPoint(cx + 2, cy + 9), C(pal.card, alpha), 1)
    elseif kind == "grid" then
        for gx = 0, 1 do
            for gy = 0, 1 do
                local x, y = cx - 10 + gx * 11, cy - 10 + gy * 11
                dl:AddRectFilled(winPoint(x, y), winPoint(x + 9, y + 9), c, 3)
            end
        end
    elseif kind == "sliders" then
        local knobs = { -4, 5, -1 }
        for i = 0, 2 do
            local y = cy - 8 + i * 8
            dl:AddLine(winPoint(cx - 10, y), winPoint(cx + 10, y), c, 2)
            dl:AddCircleFilled(winPoint(cx + knobs[i + 1], y), 3.5, c, 12)
        end
    else
        dl:AddRectFilled(winPoint(cx - 10, cy), winPoint(cx - 4, cy + 10), c, 2)
        dl:AddRectFilled(winPoint(cx - 3, cy - 9), winPoint(cx + 3, cy + 10), c, 2)
        dl:AddRectFilled(winPoint(cx + 4, cy - 4), winPoint(cx + 10, cy + 10), c, 2)
    end
end

local TABS = {
    { name = "Главная",    icon = "home", glyph = "ICON_FA_HOME",    sub = "Автоматическое улучшение видеокарт" },
    { name = "Инвентарь",  icon = "grid", glyph = "ICON_FA_TH_LARGE",    sub = "Видеокарты и их уровни" },
    { name = "Настройки",  icon = "sliders", glyph = "ICON_FA_SLIDERS_H", sub = "Цель улучшения и количество карт" },
    { name = "Статистика", icon = "chart", glyph = "ICON_FA_CHART_BAR",   sub = "Итоги текущей сессии" },
}

local function drawBackground()
    if settings.lowPC then return end
    local t = os.clock()
    glow(300, 60, 220, pal.violet, 0.60 + 0.15 * math.sin(t * 0.8))
    glow(470, H - 20, 170, pal.cyan, 0.45 + 0.12 * math.sin(t * 0.7 + 1.5))
end

local function drawSidebar()
    local dl = getDL()
    fillRect(12, 12, 176, H - 24, pal.card, 18)
    strokeRect(12, 12, 176, H - 24, pal.border, 18)

    local white = C(pal.white)
    dl:AddRectFilled(winPoint(33, 41), winPoint(65, 59), white, 3)
    dl:AddRectFilled(winPoint(31, 38), winPoint(35, 62), white, 1)
    dl:AddRectFilled(winPoint(40, 59), winPoint(60, 62), white, 1)
    for i = 0, 1 do
        local fx = 44 + i * 13
        dl:AddCircleFilled(winPoint(fx, 50), 5.5, C(pal.violet), 16)
        dl:AddCircleFilled(winPoint(fx, 50), 1.8, white, 8)
        dl:AddLine(winPoint(fx - 4, 50), winPoint(fx + 4, 50), white, 1.2)
        dl:AddLine(winPoint(fx, 46), winPoint(fx, 54), white, 1.2)
    end
    drawText(78, 28, u8("Auto Upgrade"), pal.text, fonts.bold)
    drawText(78, 48, u8("Cards"), pal.dim, fonts.main)
    gradientRect(26, 92, 148, 1, pal.violet, pal.cyan, 0.6)

    local targetY = 112 + (ui.tab - 1) * 54
    ui.navY = (ui.navY and not settings.lowPC) and lerp(ui.navY, targetY, math.min(1, frameDt * 12)) or targetY
    fillRect(24, ui.navY, 152, 46, pal.violet, 14, 0.20)
    strokeRect(24, ui.navY, 152, 46, pal.violet, 14, 0.45)
    fillRect(24, ui.navY + 12, 4, 22, pal.cyan, 2)

    for i, tab in ipairs(TABS) do
        local y = 112 + (i - 1) * 54
        cursor(24, y)
        if invBtn("##tab" .. i, V2(152, 46)) and ui.tab ~= i then
            ui.tab, ui.tabT = i, 0
        end
        local t = hoverT("tab" .. i, imgui.IsItemHovered())
        local active = ui.tab == i
        if not active and t > 0.01 then fillRect(24, y, 152, 46, pal.card2, 14, t) end
        local col = active and pal.text or mix(pal.dim, pal.text, t)
        local iconColor = active and pal.cyan or col
        if not drawGlyph(tab.glyph, 50, y + 23, iconColor, fonts.big) then
            drawIcon(tab.icon, 50, y + 23, iconColor)
        end
        drawText(72, y + 13, u8(tab.name), col, fonts.bold)
    end

    local label, sx, widths, total = "By Stalin", 0, {}, 0
    for i = 1, #label do
        local ch = label:sub(i, i)
        widths[i] = ch == " " and 8 or textSize(ch, fonts.bold)
        total = total + widths[i] + 3
    end
    sx = 100 - (total - 3) / 2
    gradientRect(26, H - 78, 148, 1, pal.cyan, pal.violet, 0.5)
    local x = sx
    for i = 1, #label do
        local ch = label:sub(i, i)
        if ch ~= " " then drawText(x, H - 66, ch, mix(pal.violet, pal.cyan, (i - 1) / (#label - 1)), fonts.bold) end
        x = x + widths[i] + 3
    end
    textCenter(100, H - 42, "v" .. VERSION, pal.dim, fonts.main)
end

local function drawTelegramButton(x, y)
    local dl = getDL()
    cursor(x, y)
    local clicked = invBtn("##tg", V2(36, 36))
    local t = hoverT("tg", imgui.IsItemHovered())
    ui.tgHover = t
    dl:AddCircleFilled(winPoint(x + 18, y + 18), 19 + t * 3, C(pal.tg, 0.18 + 0.2 * t), 32)
    dl:AddCircleFilled(winPoint(x + 18, y + 18), 17, C(mix(pal.tg, V4(0.30, 0.74, 0.96), t)), 32)
    local cx, cy = x + 18, y + 18
    local function pt(px, py) return winPoint(cx + px * 1.5, cy + py * 1.5) end
    dl:AddTriangleFilled(pt(5.8, -5.6), pt(-6.6, -0.6), pt(-2.0, 1.6), C(pal.white))
    dl:AddTriangleFilled(pt(5.8, -5.6), pt(-2.0, 1.6), pt(0.2, 5.4), C(pal.white, 0.88))
    dl:AddTriangleFilled(pt(-2.0, 1.6), pt(0.2, 5.4), pt(1.6, 3.0), C(pal.white, 0.62))
    return clicked
end

local function drawCloseButton(x, y)
    local dl = getDL()
    cursor(x, y)
    local clicked = invBtn("##close", V2(36, 36))
    local t = hoverT("close", imgui.IsItemHovered())
    fillRect(x, y, 36, 36, mix(pal.card2, pal.bad, t), 12)
    local color = mix(pal.dim, pal.white, t)
    if not drawGlyph("ICON_FA_TIMES", x + 18, y + 18, color, fonts.bold) then
        local c = C(color)
        dl:AddLine(winPoint(x + 12, y + 12), winPoint(x + 24, y + 24), c, 2)
        dl:AddLine(winPoint(x + 24, y + 12), winPoint(x + 12, y + 24), c, 2)
    end
    return clicked
end

local function drawTgTooltip()
    local t = ui.tgHover or 0
    if t < 0.02 or ui.tgStart then return end
    local label = u8("Переход в тгк")
    local w = textSize(label, fonts.bold) + 32
    local x = W - 14 - w + (1 - t) * 8
    local y = 66 - (1 - t) * 6
    local save = uiAlpha
    uiAlpha = uiAlpha * t
    fillRect(x - 2, y - 2, w + 4, 40, pal.tg, 14, 0.12)
    fillRect(x, y, w, 36, pal.card2, 12, 0.98)
    strokeRect(x, y, w, 36, pal.tg, 12, 0.7)
    drawText(x + 16, y + 8, label, pal.text, fonts.bold)
    uiAlpha = save
end

local TG_DURATION = 2.5
local TG_LAND_AT    = 1.07
local TG_OPEN_AT    = 1.45
local TG_START      = { x = CONTENT_X + CONTENT_W - 94 + 18, y = 40 }
local TG_CONTROL    = { x = 300, y = 10 }
local TG_TARGET     = { x = W / 2, y = H / 2 - 36 }

local function backOut(x)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function tgCurve(s)
    local k = 1 - s
    local x = k * k * TG_START.x + 2 * k * s * TG_CONTROL.x + s * s * TG_TARGET.x
    local y = k * k * TG_START.y + 2 * k * s * TG_CONTROL.y + s * s * TG_TARGET.y
    local dx = 2 * k * (TG_CONTROL.x - TG_START.x) + 2 * s * (TG_TARGET.x - TG_CONTROL.x)
    local dy = 2 * k * (TG_CONTROL.y - TG_START.y) + 2 * s * (TG_TARGET.y - TG_CONTROL.y)
    return x, y, (math.atan2 or math.atan)(dy, dx)
end

local function drawPlane(x, y, angle, scale, alpha)
    local dl = getDL()
    local c, s = math.cos(angle), math.sin(angle)
    local function pt(px, py)
        return winPoint(x + (px * c - py * s) * scale, y + (px * s + py * c) * scale)
    end
    dl:AddTriangleFilled(pt(9, 0), pt(-8, -5.5), pt(-3, 0.5), C(pal.white, alpha))
    dl:AddTriangleFilled(pt(9, 0), pt(-3, 0.5), pt(-4.5, 6), C(pal.white, 0.86 * alpha))
    dl:AddTriangleFilled(pt(-3, 0.5), pt(-4.5, 6), pt(-1, 2.8), C(pal.white, 0.6 * alpha))
end

local function drawTgAnimation(menuA)
    if not ui.tgStart then return end
    local t = os.clock() - ui.tgStart
    if t >= TG_DURATION then
        ui.tgStart = nil
        return
    end
    if t >= TG_OPEN_AT and not ui.tgOpened then
        ui.tgOpened = true
        pending = "link"
    end

    cursor(0, 0)
    invBtn("##tgblock", V2(W, H))

    local fadeIn  = ease(math.min(1, t / 0.3))
    local fadeOut = 1 - ease(clamp((t - (TG_DURATION - 0.45)) / 0.45, 0, 1))
    local backIn  = ease(math.min(1, t / 0.16))
    local saved = uiAlpha

    local dl = getDL()
    uiAlpha = menuA * backIn * fadeOut
    fillRect(0, 0, W, H, V4(0.015, 0.05, 0.09), 22, 1)

    uiAlpha = menuA * fadeIn * fadeOut
    dl:PushClipRect(winPoint(7, 7), winPoint(W - 7, H - 7), true)
    if not settings.lowPC then glow(TG_TARGET.x, TG_TARGET.y, 260, pal.tg, 0.55 * ease(clamp((t - 0.5) / 0.6, 0, 1))) end

    local origin = winPoint(TG_START.x, TG_START.y)
    for i = 0, 2 do
        local p = (t - 0.05 - i * 0.22) / 1.2
        if p > 0 and p < 1 then
            dl:AddCircle(origin, ease(p) * 620, C(pal.tg, (1 - p) * 0.6), 64, 2.5)
        end
    end

    local flight = clamp((t - 0.12) / 0.95, 0, 1)
    if flight < 1 then
        local s = ease(flight)
        for k = 14, 1, -1 do
            local sk = s - k * 0.028
            if sk > 0 then
                local tx, ty = tgCurve(sk)
                dl:AddCircleFilled(winPoint(tx, ty), 6 * (1 - k / 16), C(pal.cyan, (1 - k / 15) * 0.55), 12)
            end
        end
        local x, y, angle = tgCurve(s)
        dl:AddCircleFilled(winPoint(x, y), 26, C(pal.tg, 0.22), 24)
        drawPlane(x, y, angle, 2.1, 1)
    end

    local lt = t - TG_LAND_AT
    if lt > 0 then
        local cx, cy = TG_TARGET.x, TG_TARGET.y
        local R = 44 * backOut(clamp(lt / 0.5, 0, 1))
        local c = winPoint(cx, cy)

        dl:AddCircleFilled(c, R + 16 + 5 * math.sin(t * 6), C(pal.tg, 0.16), 40)
        dl:AddCircleFilled(c, R, C(pal.tg), 40)
        dl:AddCircleFilled(winPoint(cx - R * 0.18, cy - R * 0.22), R * 0.72, C(V4(0.34, 0.76, 0.98), 0.55), 32)
        drawPlane(cx - 1, cy + 1 + 2 * math.sin(t * 5), -0.35, R / 44 * 3.3, 1)

        for i = 0, 13 do
            local a = t * 4.5 - i * 0.2
            local pt = winPoint(cx + math.cos(a) * (R + 20), cy + math.sin(a) * (R + 20))
            dl:AddCircleFilled(pt, 4.2 - i * 0.26, C(pal.cyan, 1 - i / 14), 10)
        end

        local p = clamp(lt / 0.9, 0, 1)
        for i = 1, 16 do
            local a = i * math.pi * 2 / 16 + 0.2
            local dist = R + 10 + ease(p) * (50 + (i % 3) * 28)
            dl:AddCircleFilled(winPoint(cx + math.cos(a) * dist, cy + math.sin(a) * dist),
                4 * (1 - p), C(i % 2 == 0 and pal.cyan or pal.white, 1 - p), 8)
        end

        local textA = ease(clamp((lt - 0.15) / 0.4, 0, 1))
        local title = u8("Переход в тгк")
        local w = textSize(title, fonts.huge)
        drawText(cx - w / 2, cy + R + 22, title, pal.text, fonts.huge, textA)
        local sub = t < TG_OPEN_AT and (u8("Открываю Telegram") .. string.rep(".", math.floor(t * 4) % 4)) or u8("Готово!")
        local sw = textSize(sub, fonts.main)
        drawText(cx - sw / 2, cy + R + 66, sub, t < TG_OPEN_AT and pal.dim or pal.good, fonts.main, textA)

        local barW, barX, barY = 240, cx - 120, cy + R + 96
        fillRect(barX, barY, barW, 6, pal.card2, 3, textA)
        local fill = barW * clamp(lt / (TG_OPEN_AT - TG_LAND_AT + 0.35), 0, 1)
        if fill > 4 then
            fillRect(barX, barY, fill, 6, pal.tg, 3, textA)
            gradientRect(barX + 3, barY, fill - 6, 6, pal.tg, pal.cyan, textA)
        end
    end

    dl:PopClipRect()
    uiAlpha = saved
end

local function drawHelpTooltip()
    local help = ui.help
    if not help or ui.tgStart then return end
    local lines = wrapText(help.text, 300, fonts.main, 7)
    local w, h = 328, 22 + #lines * 19
    local x = clamp(help.x - w / 2, 12, W - 12 - w)
    local y = help.y + 20
    if y + h > H - 10 then y = help.y - 20 - h end
    local saved = uiAlpha
    uiAlpha = uiAlpha * help.t
    fillRect(x - 2, y - 2, w + 4, h + 4, pal.violet, 14, 0.12)
    fillRect(x, y, w, h, pal.card2, 12, 0.98)
    strokeRect(x, y, w, h, pal.violet, 12, 0.6)
    for i, line in ipairs(lines) do
        drawText(x + 14, y + 11 + (i - 1) * 19, line, pal.text, fonts.main)
    end
    uiAlpha = saved
end

local function drawHeader()
    local tab = TABS[ui.tab]
    drawText(0, 24, u8(tab.name), pal.text, fonts.huge)
    drawText(2, 62, u8(tab.sub), pal.dim, fonts.main)
end

local function drawStartButton()
    local x, y, w, h = 0, 398, CONTENT_W, 58
    cursor(x, y)
    local clicked = invBtn("##startstop", V2(w, h))
    local t = hoverT("startstop", imgui.IsItemHovered())
    local running = state.running
    local colA = running and pal.bad or pal.violet
    local colB = running and pal.pink or pal.cyan
    if state.stopping then colA, colB = pal.card3, pal.card3 end
    colA, colB = mix(colA, pal.white, t * 0.12), mix(colB, pal.white, t * 0.12)

    local lowPC = settings.lowPC
    local pulse = (running and not lowPC) and (0.5 + 0.5 * math.sin(os.clock() * 3)) or 0
    if not lowPC then fillRect(x - 3, y - 3, w + 6, h + 6, colA, 20, 0.10 + 0.10 * t + 0.10 * pulse) end
    local dl = getDL()
    dl:AddRectFilled(winPoint(x, y), winPoint(x + w, y + h), C(colA), 18)
    dl:AddRectFilled(winPoint(x + w - 44, y), winPoint(x + w, y + h), C(colB), 18)
    gradientRect(x + 18, y, w - 36, h, colA, colB)

    if running and not state.stopping and not lowPC then
        local sheen = (os.clock() * 0.45) % 1
        local sx = x + 20 + (w - 100) * sheen
        gradientRect(sx, y + 4, 40, h - 8, V4(1, 1, 1, 0), V4(1, 1, 1, 0.20))
        gradientRect(sx + 40, y + 4, 40, h - 8, V4(1, 1, 1, 0.20), V4(1, 1, 1, 0))
    end
    strokeRect(x, y, w, h, pal.white, 18, 0.12)

    local label = u8(state.stopping and "ОСТАНОВКА..." or (running and "ОСТАНОВИТЬ" or "ЗАПУСТИТЬ"))
    label = withGlyph(state.stopping and "ICON_FA_HOURGLASS_HALF" or (running and "ICON_FA_STOP" or "ICON_FA_PLAY"), label)
    local tw, th = textSize(label, fonts.big)
    drawText(x + (w - tw) / 2, y + (h - th) / 2, label, pal.white, fonts.big)

    if clicked and not pending then
        pending = running and "stop" or "start"
    end
end

local function pageMain()
    card(0, 86, 236, 232)
    local target = settings.cardsNum > 0 and math.min(1, state.done / settings.cardsNum) or 0
    ui.ring = settings.lowPC and target or lerp(ui.ring, target, math.min(1, frameDt * 6))
    drawRing(118, 186, 64, 12, ui.ring)
    textCenter(118, 186 - 22, string.format("%d%%", math.floor(ui.ring * 100 + 0.5)), pal.text, fonts.huge)
    textCenter(118, 186 + 18, string.format("%d / %d", state.done, settings.cardsNum), pal.dim, fonts.main)
    textCenter(118, 284, u8("карт улучшено"), pal.dim, fonts.main)

    card(252, 86, 280, 94)
    local pulse = settings.lowPC and 1 or (0.55 + 0.45 * math.sin(os.clock() * 4))
    local running = state.running
    local dotColor = running and pal.good or pal.dim
    if running and not settings.lowPC then fillRect(264, 104, 12, 12, pal.good, 6, 0.25 * pulse) end
    getDL():AddCircleFilled(winPoint(274, 110), 5, C(dotColor, running and pulse or 1), 16)
    local statusText = state.stopping and u8("ОСТАНАВЛИВАЮ") or (running and (u8("РАБОТАЕТ") .. string.rep(".", ui.dots)) or u8("ОСТАНОВЛЕН"))
    drawText(290, 99, statusText, running and pal.good or pal.dim, fonts.bold)

    local message, color = ui.message, pal.dim
    if ui.status == "success" then color = pal.good
    elseif ui.status == "error" then color = pal.bad
    elseif ui.status == "info" then color = pal.cyan end
    if message == "" then
        message = running and u8("Идёт улучшение...") or u8("Встаньте у стола и нажмите ЗАПУСТИТЬ")
    end
    for i, line in ipairs(wrapText(message, 250, fonts.main, 3)) do
        drawText(268, 128 + (i - 1) * 17, line, color, fonts.main)
    end

    local level = (running and cef.current) and tostring(cardLevel(cef.current)) or "-"
    tile(252, 190, 88, 76, u8("Уровень"), level, pal.violet, "ICON_FA_STAR")
    tile(348, 190, 88, 76, u8("Попыток"), tostring(stats.curAttempts), pal.cyan, "ICON_FA_SYNC_ALT")
    tile(444, 190, 88, 76, u8("Смазки"), cef.lube and tostring(cef.lube) or "?", pal.pink, "ICON_FA_TINT")

    card(252, 276, 280, 42, 14)
    drawText(268, 288, u8("Время сессии"), pal.dim, fonts.main)
    textRight(516, 286, formatTime(state.sessionTime), pal.cyan, fonts.bold)

    card(0, 328, CONTENT_W, 56, 14)
    local cols = { 22, 202, 382 }
    local names = { u8("Целевой уровень"), u8("Количество карт"), u8("Чтение уровней") }
    local values = { tostring(settings.needLVL), tostring(settings.cardsNum), u8(settings.scanLevels and "ВКЛ" or "ВЫКЛ") }
    for i = 1, 3 do
        drawText(cols[i], 337, names[i], pal.dim, fonts.main)
        drawText(cols[i], 357, values[i], i == 3 and (settings.scanLevels and pal.good or pal.dim) or pal.text, fonts.bold)
    end

    drawStartButton()
    textCenter(CONTENT_W / 2, 472, u8("Перед запуском встаньте у стола в подвале"), pal.dim, fonts.main)
end

local function pageInventory()
    card(0, 86, CONTENT_W, 400)
    drawText(20, 102, u8("Видеокарты в инвентаре"), pal.text, fonts.bold)

    local slots = {}
    for slot in pairs(knownCards) do slots[#slots + 1] = slot end
    table.sort(slots)
    drawText(232, 104, u8("Всего: ") .. #slots, pal.dim, fonts.main)

    local busy = state.running or ui.scanning
    if chip("scan", withGlyph("ICON_FA_SYNC_ALT", u8(ui.scanning and "Читаю..." or "Обновить")), 328, 98, 96, 30, false) then
        if state.running then
            notify("Остановите улучшение, чтобы обновить инвентарь", "warn")
        elseif not ui.scanning then
            pending = "scan"
        end
    end
    if chip("clear", withGlyph("ICON_FA_TRASH_ALT", u8("Очистить")), 430, 98, 94, 30, false) then
        if busy then
            notify("Дождитесь окончания работы, затем очистите данные", "warn")
        else
            pending = "clear"
        end
    end

    if #slots == 0 then
        textCenter(CONTENT_W / 2, 270, u8("Данных нет"), pal.text, fonts.bold)
        textCenter(CONTENT_W / 2, 298, u8("Нажмите «Обновить», чтобы прочитать уровни видеокарт"), pal.dim, fonts.main)
        return
    end

    local cols, cw, ch, gap = 5, 92, 60, 8
    local slotWord, levelWord = u8("Слот "), u8("Ур. ")
    local contentH = math.ceil(#slots / cols) * (ch + gap)

    scrollArea("cards", 10, 142, 512, 336, contentH, function(ox, oy, top, bottom)
        for i, slot in ipairs(slots) do
            local x = ox + ((i - 1) % cols) * (cw + gap)
            local y = oy + math.floor((i - 1) / cols) * (ch + gap)
            if y > top - ch and y < bottom then
                local level   = cardLevel(slot)
                local done    = level >= settings.needLVL
                local current = state.running and cef.current == slot
                local accent  = done and pal.good or (current and pal.violet or pal.cyan)

                fillRect(x, y, cw, ch, pal.card2, 12)
                if current then
                    strokeRect(x, y, cw, ch, pal.violet, 12, settings.lowPC and 1 or (0.5 + 0.5 * math.sin(os.clock() * 5)))
                end
                drawText(x + 10, y + 6, slotWord .. slot, pal.dim, fonts.main)
                drawText(x + 10, y + 24, levelWord .. level, done and pal.good or pal.text, fonts.bold)
                local barW = cw - 20
                local frac = clamp((level - 1) / math.max(1, settings.needLVL - 1), 0, 1)
                fillRect(x + 10, y + ch - 11, barW, 5, pal.bg, 3)
                if frac > 0 then fillRect(x + 10, y + ch - 11, math.max(5, barW * frac), 5, accent, 3) end
            end
        end
    end)
end

local function sliderCard(y, title, id, vmin, vmax, format, presets, current, onPick, onSlide, tip)
    card(0, y, CONTENT_W, 108)
    drawText(20, y + 14, title, pal.text, fonts.bold)
    helpIcon(id, 20 + textSize(title, fonts.bold) + 10, y + 13, tip)
    textRight(512, y + 14, u8(string.format(format, current)), pal.cyan, fonts.bold)

    cursor(20, y + 36)
    invBtn("##" .. id, V2(492, 30))
    local hovered, active = imgui.IsItemHovered(), imgui.IsItemActive()
    if active then
        local rel = ((imgui.GetMousePos().x - imgui.GetWindowPos().x) / S - bx - 20) / 492
        local value = clamp(math.floor(vmin + rel * (vmax - vmin) + 0.5), vmin, vmax)
        if value ~= current then onSlide(value) end
    end

    local key = id .. "s"
    local goal = (current - vmin) / (vmax - vmin)
    local shown = settings.lowPC and goal or lerp(hoverState[key] or goal, goal, math.min(1, frameDt * 16))
    hoverState[key] = shown
    local t = hoverT(id .. "h", hovered or active)

    local ty, fill = y + 46, 492 * shown
    fillRect(20, ty, 492, 10, pal.card2, 5)
    if fill > 2 then
        fillRect(20, ty, math.max(10, fill), 10, pal.violet, 5)
        if fill > 20 then
            gradientRect(25, ty, fill - 10, 10, pal.violet, pal.cyan)
            fillRect(20 + fill - 10, ty, 10, 10, pal.cyan, 5)
        end
    end
    local dl = getDL()
    dl:AddCircleFilled(winPoint(20 + fill, ty + 5), 14 + t * 3, C(pal.cyan, 0.18 + 0.12 * t), 24)
    dl:AddCircleFilled(winPoint(20 + fill, ty + 5), 9, C(pal.white), 20)

    for i, v in ipairs(presets) do
        if chip(id .. v, tostring(v), 20 + (i - 1) * 74, y + 70, 66, 28, current == v) then onPick(v) end
    end
end

local function settingRow(id, y, title, tip)
    drawText(20, y + 3, title, pal.text, fonts.bold)
    helpIcon(id, 20 + textSize(title, fonts.bold) + 10, y + 3, tip)
end

local function pageSettings()
    sliderCard(86, u8("Требуемый уровень"), "lvl", 2, 10, "Уровень: %d", { 3, 5, 7, 10 },
        settings.needLVL,
        function(v) settings.needLVL, ui.needLVL[0] = v, v markDirty() end,
        function(v) settings.needLVL = v markDirty() end,
        u8("До какого уровня улучшать каждую видеокарту. Карты с таким или более высоким уровнем пропускаются."))

    sliderCard(204, u8("Количество видеокарт"), "cnt", 1, 100, "Карт: %d", { 1, 5, 10, 15, 25, 50, 100 },
        settings.cardsNum,
        function(v) settings.cardsNum, ui.cardsNum[0] = v, v markDirty() end,
        function(v) settings.cardsNum = v markDirty() end,
        u8("Сколько карт довести до целевого уровня за один запуск. Когда все они будут готовы, скрипт остановится."))

    card(0, 322, CONTENT_W, 188)

    settingRow("scan", 340, u8("Чтение уровней"),
        u8("Перед запуском каждая карта на миг переносится в пустой слот, чтобы узнать её уровень. Без этого все карты считаются первого уровня. Нужен хотя бы один свободный слот."))
    if toggle("scanLevels", 460, 340, settings.scanLevels) then
        settings.scanLevels = not settings.scanLevels
        markDirty()
    end
    gradientRect(20, 386, CONTENT_W - 40, 1, pal.card3, pal.card3)

    settingRow("anim", 402, u8("Выкл анимации"),
        u8("Режим для слабых ПК и телефонов: отключает все анимации и эффекты, меню работает без лишней нагрузки."))
    if toggle("lowPC", 460, 402, settings.lowPC) then
        settings.lowPC = not settings.lowPC
        if settings.lowPC then ui.openT, ui.tabT, ui.tgStart = 1, 1, nil end
        markDirty()
    end
    gradientRect(20, 448, CONTENT_W - 40, 1, pal.card3, pal.card3)

    settingRow("stats", 460, u8("Статистика"),
        u8("Счётчики карт, попыток, смазок и ошибок за текущую сессию. Кнопка обнуляет их."))
    if chip("resetStats", withGlyph("ICON_FA_UNDO", u8("Сбросить")), 396, 460, 116, 28, false) then
        resetStats()
        notify("Статистика сброшена", "info", 3)
    end
end

local function pageStats()
    local labels = { u8("Улучшено"), u8("Попыток"), u8("Смазок"), u8("Ошибок") }
    local values = { stats.cards, stats.attempts, stats.lube, stats.errors }
    local colors = { pal.good, pal.violet, pal.warn, pal.bad }
    local statIcons = { "ICON_FA_CHECK", "ICON_FA_SYNC_ALT", "ICON_FA_TINT", "ICON_FA_EXCLAMATION_TRIANGLE" }
    for i = 1, 4 do
        tile((i - 1) * 135, 86, 126, 76, labels[i], tostring(values[i]), colors[i], statIcons[i])
    end

    card(0, 174, CONTENT_W, 312)
    drawText(20, 188, u8("История сессии"), pal.text, fonts.bold)
    local avg = stats.cards > 0 and (stats.attempts / stats.cards) or 0
    textRight(512, 190, u8(string.format("В среднем %.1f попыток на карту", avg)), pal.dim, fonts.main)

    local rows = #stats.history
    if rows == 0 then
        textCenter(CONTENT_W / 2, 330, u8("Пока нет улучшенных карт"), pal.dim, fonts.main)
        return
    end

    scrollArea("history", 10, 222, 512, 254, rows * 28, function(ox, oy, top, bottom)
        for i = 1, rows do
            local row = stats.history[rows - i + 1]
            local y = oy + (i - 1) * 28
            if y > top - 28 and y < bottom then
                drawText(ox + 12, y + 4, "#" .. (rows - i + 1), pal.violet, fonts.bold)
                drawText(ox + 64, y + 4, u8(string.format("Ур. %d -> %d", row.from, row.to)), pal.text, fonts.main)
                drawText(ox + 224, y + 4, u8(string.format("Попыток: %d", row.tries)), pal.dim, fonts.main)
                drawText(ox + 384, y + 4, u8(string.format("Смазок: %d", row.tries * LUBE_PER_TRY)), pal.good, fonts.main)
            end
        end
    end)
end

local TOAST_W = 320
local TOAST_COLOR = { success = pal.good, error = pal.bad, warn = pal.warn, info = pal.cyan }

local TOAST_GLYPH = { success = "ICON_FA_CHECK", error = "ICON_FA_TIMES", warn = "ICON_FA_EXCLAMATION", info = "ICON_FA_INFO" }

local function drawToastIcon(kind, cx, cy, color, a)
    local dl = getDL()
    dl:AddCircleFilled(winPoint(cx, cy), 15, C(color, 0.16 * a), 24)
    dl:AddCircle(winPoint(cx, cy), 15, C(color, 0.55 * a), 24, 1.5)
    if drawGlyph(TOAST_GLYPH[kind] or TOAST_GLYPH.info, cx, cy, color, fonts.bold, a) then return end
    local c = C(color, a)
    if kind == "success" then
        dl:AddLine(winPoint(cx - 6, cy + 0.5), winPoint(cx - 1.5, cy + 5), c, 2.5)
        dl:AddLine(winPoint(cx - 1.5, cy + 5), winPoint(cx + 6.5, cy - 5), c, 2.5)
    elseif kind == "error" then
        dl:AddLine(winPoint(cx - 5, cy - 5), winPoint(cx + 5, cy + 5), c, 2.5)
        dl:AddLine(winPoint(cx + 5, cy - 5), winPoint(cx - 5, cy + 5), c, 2.5)
    elseif kind == "warn" then
        dl:AddLine(winPoint(cx, cy - 6), winPoint(cx, cy + 2), c, 2.5)
        dl:AddCircleFilled(winPoint(cx, cy + 6), 1.8, c, 8)
    else
        dl:AddCircleFilled(winPoint(cx, cy - 6), 1.8, c, 8)
        dl:AddLine(winPoint(cx, cy - 2), winPoint(cx, cy + 6), c, 2.5)
    end
end

local function drawToasts()
    local now = os.clock()
    local x0, y = W - 20 - TOAST_W, 72
    local i = 1
    while i <= #toasts do
        local t = toasts[i]
        local age = now - t.t0
        if age >= t.dur then
            table.remove(toasts, i)
        else
            if not t.lines then
                t.lines = wrapText(t.text, TOAST_W - 76, fonts.main, 3)
                t.h = math.max(56, 24 + #t.lines * 20)
            end
            local tin  = math.min(1, age / 0.35)
            local tout = math.min(1, (t.dur - age) / 0.35)
            local ein  = settings.lowPC and 1 or ease(tin)
            if settings.lowPC then tout = 1 end
            local a    = math.min(ein, tout)
            local x    = x0 + (1 - ein) * 70 + (1 - tout) * 30
            local col  = TOAST_COLOR[t.kind] or pal.cyan

            fillRect(x - 2, y - 2, TOAST_W + 4, t.h + 4, col, 16, 0.08 * a)
            fillRect(x, y, TOAST_W, t.h, pal.card2, 14, 0.98 * a)
            strokeRect(x, y, TOAST_W, t.h, col, 14, 0.5 * a)
            fillRect(x, y + 12, 4, t.h - 24, col, 2, a)
            drawToastIcon(t.kind, x + 36, y + t.h / 2 - 2, col, a)
            for li, line in ipairs(t.lines) do
                drawText(x + 62, y + 12 + (li - 1) * 20, line, pal.text, fonts.main, a)
            end
            fillRect(x + 14, y + t.h - 7, (TOAST_W - 28) * (1 - age / t.dur), 3, col, 2, 0.85 * a)

            y = y + t.h + 8
            i = i + 1
        end
    end
end

local function applyStyle()
    local st = imgui.GetStyle()
    st.WindowRounding    = 22 * S
    st.ChildRounding     = 10 * S
    st.FrameRounding     = 10 * S
    st.GrabRounding      = 10 * S
    st.ScrollbarRounding = 8 * S
    st.WindowBorderSize  = 0
    st.FrameBorderSize   = 0
    st.GrabMinSize       = 20 * S
    st.ScrollbarSize     = 8 * S
    st.WindowPadding     = V2(0, 0)
    st.FramePadding      = V2(12 * S, 8 * S)
    st.ItemSpacing       = V2(8 * S, 6 * S)

    local c = st.Colors
    c[imgui.Col.WindowBg]             = pal.bg
    c[imgui.Col.ChildBg]              = V4(0, 0, 0, 0)
    c[imgui.Col.Border]               = pal.border
    c[imgui.Col.Text]                 = pal.text
    c[imgui.Col.TextDisabled]         = pal.dim
    c[imgui.Col.FrameBg]              = pal.card2
    c[imgui.Col.FrameBgHovered]       = pal.card3
    c[imgui.Col.FrameBgActive]        = pal.card3
    c[imgui.Col.SliderGrab]           = pal.violet
    c[imgui.Col.SliderGrabActive]     = pal.cyan
    c[imgui.Col.ScrollbarBg]          = V4(0, 0, 0, 0)
    c[imgui.Col.ScrollbarGrab]        = pal.card3
    c[imgui.Col.ScrollbarGrabHovered] = pal.violet
    c[imgui.Col.ScrollbarGrabActive]  = pal.cyan
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil

    -- масштаб: на ПК не больше 1, на телефоне подгоняем окно под экран
    local sw, sh = getScreenResolution()
    local fit = math.min(sw * 0.92 / W, sh * 0.88 / H)
    S = MOBILE and clamp(fit, 0.6, 2.2) or clamp(fit, 0.6, 1.0)
    S = math.floor(S * 20 + 0.5) / 20

    local atlas  = imgui.GetIO().Fonts
    local ranges = atlas:GetGlyphRangesCyrillic()

    local dirs, regular, bold
    if MOBILE then
        local wd = getWorkingDirectory()
        dirs = { "/system/fonts/", "/system/font/", "/system/fonts/Roboto/", wd .. "/resource/fonts/", wd .. "/resource/", wd .. "/lib/" }
        regular = { "Roboto-Regular.ttf", "Roboto[wdth,wght].ttf", "NotoSans-Regular.ttf", "DroidSans.ttf", "SamsungOneUI-400.ttf", "arial.ttf", "segoeui.ttf" }
        bold    = { "Roboto-Bold.ttf", "Roboto[wdth,wght].ttf", "NotoSans-Bold.ttf", "DroidSans-Bold.ttf", "SamsungOneUI-700.ttf", "arialbd.ttf", "segoeuib.ttf" }
    else
        dirs = { (os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts\\" }
        regular = { "segoeui.ttf", "tahoma.ttf", "arial.ttf" }
        bold    = { "segoeuib.ttf", "tahomabd.ttf", "arialbd.ttf" }
    end

    local function load(files, size)
        size = size * S
        for _, dir in ipairs(dirs) do
            for _, file in ipairs(files) do
                if doesFileExist(dir .. file) then
                    local ok, f = pcall(function() return atlas:AddFontFromFileTTF(dir .. file, size, nil, ranges) end)
                    if ok and f then return f end
                end
            end
        end
        -- шрифт не найден: встроенный (кириллицы в нём может не быть)
        local ok, f = pcall(function()
            local cfg = imgui.ImFontConfig()
            cfg.SizePixels = size
            return atlas:AddFontDefault(cfg)
        end)
        if ok and f then return f end
        return atlas:AddFontDefault()
    end

    local iconRanges
    local iconFiles = {
        "fa-solid-900.ttf", "fonts/fa-solid-900.ttf", "fa-solid-900.otf", "fontawesome-webfont.ttf",
    }

    local function mergeIcons(size)
        size = size * S
        local config = imgui.ImFontConfig()
        config.MergeMode  = true
        config.PixelSnapH = true
        iconRanges = iconRanges or imgui.new.ImWchar[3](0xf000, 0xf8ff, 0)

        if fa then
            local ok = pcall(function()
                local data = fa.get_font_data_base85("solid")
                atlas:AddFontFromMemoryCompressedBase85TTF(data, size, config, iconRanges)
            end)
            if ok then return true end
        end

        local base = getWorkingDirectory() .. "/resource/"
        for _, file in ipairs(iconFiles) do
            if doesFileExist(base .. file) then
                local ok = pcall(function() atlas:AddFontFromFileTTF(base .. file, size, config, iconRanges) end)
                if ok then return true end
            end
        end
        return false
    end

    fonts.main = load(regular, 16)
    local ok1 = mergeIcons(15)
    fonts.bold = load(bold, 17)
    local ok2 = mergeIcons(16)
    fonts.big  = load(bold, 22)
    local ok3 = mergeIcons(20)
    fonts.huge = load(bold, 32)
    iconsReady = ok1 and ok2 and ok3

    applyStyle()
end)

local WINDOW_FLAGS = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar
    + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
    + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove

local function pushAlpha(value)
    if imgui.PushStyleVarFloat then
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, value)
        return true
    end
    return false
end

imgui.OnFrame(function() return ui.main[0] or ui.openT > 0.002 end, function()
    local now = os.clock()
    frameDt = now - (ui.lastT or now)
    if frameDt > 0.1 or frameDt < 0 then frameDt = 0.016 end
    ui.lastT = now

    local wasClosed = ui.openT < 0.05
    local goal = ui.main[0] and 1 or 0
    if settings.lowPC then
        ui.openT = goal
    else
        ui.openT = ui.openT + (goal - ui.openT) * math.min(1, frameDt * 12)
    end
    if math.abs(goal - ui.openT) < 0.004 then ui.openT = goal end
    if ui.openT <= 0 then return end
    if wasClosed and ui.main[0] then ui.tabT = 0 end

    local menuA = ease(ui.openT)
    uiAlpha = menuA
    ui.tgHover = 0
    ui.help = nil

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(V2(sw / 2, sh / 2 + (1 - menuA) * 30 * S), imgui.Cond.Always, V2(0.5, 0.5))
    imgui.SetNextWindowSize(V2(W * S, H * S), imgui.Cond.Always)

    local pushed = pushAlpha(menuA)
    imgui.Begin("##auc_main", nil, WINDOW_FLAGS)

    bx, by = 0, 0
    drawBackground()
    drawSidebar()

    bx = CONTENT_X
    if drawTelegramButton(CONTENT_W - 94, 22) and not ui.tgStart then
        if settings.lowPC then
            pending = "link"
        else
            ui.tgStart, ui.tgOpened = os.clock(), false
        end
    end
    if drawCloseButton(CONTENT_W - 50, 22) then ui.main[0] = false end

    ui.tabT = settings.lowPC and 1 or math.min(1, ui.tabT + frameDt * 3.4)
    local pageE = ease(ui.tabT)
    bx = CONTENT_X + (1 - pageE) * 40
    uiAlpha = menuA * pageE
    local pagePushed = pushAlpha(menuA * pageE)

    drawHeader()
    if ui.tab == 1 then pageMain()
    elseif ui.tab == 2 then pageInventory()
    elseif ui.tab == 3 then pageSettings()
    else pageStats() end

    if pagePushed then imgui.PopStyleVar() end

    bx, uiAlpha = 0, menuA
    drawToasts()
    drawTgTooltip()
    drawHelpTooltip()
    drawTgAnimation(menuA)

    imgui.End()
    if pushed then imgui.PopStyleVar() end
end)

local function runPending()
    local action = pending
    pending = nil
    if action == "start" then
        startScript()
    elseif action == "stop" then
        requestStop()
    elseif action == "scan" then
        scanInventory()
    elseif action == "clear" then
        clearInventoryCache()
        notify("Данные об инвентаре очищены. Нажмите «Обновить»", "success")
    elseif action == "link" then
        openLink()
    end
end

local function toggleMenu()
    if ui.main[0] then
        ui.main[0] = false
        return
    end
    if not isSampAvailable() then return end
    if nearTable() then
        ui.main[0] = true
    else
        sampAddChatMessage(cp("{FF0000}[Auto Upgrade Cards] {FFFFFF}Встаньте у стола в подвале и введите {FF0000}/upg"), -1)
    end
end

-- ===== Регистрация хуков RakNet =====
-- На мобильном лоадере глобальные onSendPacket/onReceivePacket сами не вызываются,
-- хуки нужно подключать через RakLua (так же делает CEF Monitor).

do
    local function reg(event, fn)
        local ok = pcall(function()
            local R = require("RakLua")
            R.registerHandler(RakLuaEvents[event], fn)
        end)
        if ok then return "RakLua" end
        local name = ({ OUTGOING_PACKET = "onSendPacket", INCOMING_PACKET = "onReceivePacket", OUTGOING_RPC = "onSendRpc" })[event]
        if name and pcall(addEventHandler, name, fn) then return "addEventHandler" end
        return nil
    end
    local m1 = reg("INCOMING_PACKET", function(id, bs) HK.count.recv = HK.count.recv + 1 pcall(HK.hookReceivePacket, id, bs) end)
    local m2 = reg("OUTGOING_PACKET", function(id, bs) HK.count.send = HK.count.send + 1 pcall(HK.hookSendPacket, id, bs) end)
    local m3 = reg("OUTGOING_RPC",    function(id, bs) HK.count.rpc  = HK.count.rpc  + 1 pcall(HK.hookSendRpc, id, bs) end)
    HK.mode = (m1 or "нет") .. "/" .. (m2 or "нет") .. "/" .. (m3 or "нет")
end

function main()
    if not MOBILE then
        if isSampLoaded and not isSampLoaded() then return end
        if isSampfuncsLoaded and not isSampfuncsLoaded() then return end
    end
    while not isSampAvailable() do wait(100) end

    loadConfig()
    local line = "{FF0000}======================================"
    sampAddChatMessage(cp(line), -1)
    sampAddChatMessage(cp("{FF0000}| {FFFFFF}Auto Upgrade Cards  v" .. VERSION .. " {FF0000}|"), -1)
    sampAddChatMessage(cp("{FF0000}| {FFFFFF}Автор: By {FF0000}Stalin {FF0000}|"), -1)
    sampAddChatMessage(cp(line), -1)
    sampAddChatMessage(cp("{FF0000}| {FFFFFF}Активация: {FF0000}/upg {FFFFFF}у стола"), -1)
    sampAddChatMessage(cp(line), -1)

    sampRegisterChatCommand("upg", toggleMenu)
    sampAddChatMessage(cp("{FF0000}| {FFFFFF}Хуки пакетов: {FF0000}" .. HK.mode), -1)
    sampRegisterChatCommand("upgsniff", HK.sniffStart)
    sampAddChatMessage(cp("{FF0000}| {FFFFFF}Диагностика: {FF0000}/upgsniff{FFFFFF} - записать пакеты при нажатии «Использовать»"), -1)

    lua_thread.create(function()
        while true do
            wait(50)
            if pending then
                if not pcall(runPending) then
                    pending = nil
                    notify("Внутренняя ошибка, попробуйте ещё раз", "error")
                end
            end
        end
    end)

    lua_thread.create(function()
        while true do
            wait(400)
            if state.running then
                ui.dots = ui.dots % 3 + 1
                state.sessionTime = os.clock() - state.sessionStart
            end
            if dirtyAt and os.clock() - dirtyAt > 1 then
                dirtyAt = nil
                saveConfig()
            end
        end
    end)

    while true do
        wait(250)
        if ui.main[0] and not state.running and not ui.scanning and not nearTable() then
            ui.main[0] = false
        end
    end
end

function onWindowMessage(msg, wparam)
    if MOBILE then return end
    if (msg == 256 or msg == 257) and wparam == 0x1B and ui.main[0]
            and not isGamePaused() and not sampIsChatInputActive()
            and not (isSampfuncsConsoleActive and isSampfuncsConsoleActive()) and not sampIsDialogActive() then
        consumeWindowMessage(true, false)
        if msg == 257 then ui.main[0] = false end
    end
end

function onScriptTerminate(script)
    if script == thisScript() then
        saveConfig()
        pcall(sampUnregisterChatCommand, "upg")
        pcall(sampUnregisterChatCommand, "upgsniff")
    end
end
