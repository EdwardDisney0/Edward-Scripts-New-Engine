script_name('Mining Tools')
script_author('Edward')
script_version('2.7.0-mobile')

local dlstatus = (select(2, pcall(require, 'moonloader')) or {}).download_status or {}

local IS_MOBILE = (MONET_VERSION ~= nil)
local imgui    = require 'mimgui'
local encoding = require 'encoding'
local ffi      = require 'ffi'
local bit      = require 'bit'
local sampev   = require 'samp.events'
local json
do
    local okj, lib = pcall(require, 'dkjson')
    local isDk = okj
    if not okj then okj, lib = pcall(require, 'cjson') end
    if okj and type(lib) == 'table' then
        if isDk then
            json = lib
        else

            json = {
                encode = function(v) return lib.encode(v) end,
                decode = function(str) return lib.decode(str) end,
            }
        end
    else

        local M = {}
        local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        local function encStr(str)
            return '"' .. str:gsub('[%c"\\]', function(c) return ESC[c] or string.format('\\u%04x', c:byte()) end) .. '"'
        end
        local function enc(v, pretty, lvl)
            local t = type(v)
            if t == 'nil' then return 'null' end
            if t == 'boolean' then return tostring(v) end
            if t == 'number' then
                if v ~= v or v == math.huge or v == -math.huge then return 'null' end
                if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%d', v) end
                return string.format('%.14g', v)
            end
            if t == 'string' then return encStr(v) end
            if t ~= 'table' then return 'null' end
            local inner = pretty and ('\n' .. string.rep('  ', lvl + 1)) or ''
            local outer = pretty and ('\n' .. string.rep('  ', lvl)) or ''
            local parts = {}
            if next(v) == nil or #v > 0 then
                for i = 1, #v do parts[i] = enc(v[i], pretty, lvl + 1) end
                if #parts == 0 then return '[]' end
                return '[' .. inner .. table.concat(parts, ',' .. inner) .. outer .. ']'
            end
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            for i, k in ipairs(keys) do
                local val = v[k]
                if val == nil then val = v[tonumber(k)] end
                parts[i] = encStr(k) .. (pretty and ': ' or ':') .. enc(val, pretty, lvl + 1)
            end
            return '{' .. inner .. table.concat(parts, ',' .. inner) .. outer .. '}'
        end
        function M.encode(v, opts)
            return enc(v, type(opts) == 'table' and opts.indent, 0)
        end

        local function utf8char(cp)
            if cp < 0x80 then return string.char(cp) end
            if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
            return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
        end
        local UNESC = { b = '\b', f = '\f', n = '\n', r = '\r', t = '\t', ['"'] = '"', ['\\'] = '\\', ['/'] = '/' }

        function M.decode(str)
            if type(str) ~= 'string' then error('not a string') end
            local pos = 1
            local function skip() pos = str:find('[^ \t\r\n]', pos) or (#str + 1) end
            local function parseString()
                local out = {}
                pos = pos + 1
                while true do
                    local c = str:sub(pos, pos)
                    if c == '' then error('unterminated string') end
                    if c == '"' then pos = pos + 1; break end
                    if c == '\\' then
                        local n = str:sub(pos + 1, pos + 1)
                        if n == 'u' then
                            local cp = tonumber(str:sub(pos + 2, pos + 5), 16)
                            if not cp then error('bad escape') end
                            out[#out + 1] = utf8char(cp)
                            pos = pos + 6
                        else
                            if not UNESC[n] then error('bad escape') end
                            out[#out + 1] = UNESC[n]
                            pos = pos + 2
                        end
                    else
                        local a, b = str:find('[^"\\]+', pos)
                        out[#out + 1] = str:sub(a, b)
                        pos = b + 1
                    end
                end
                return table.concat(out)
            end
            local parseValue
            function parseValue()
                skip()
                local c = str:sub(pos, pos)
                if c == '{' then
                    pos = pos + 1
                    local obj = {}
                    skip()
                    if str:sub(pos, pos) == '}' then pos = pos + 1; return obj end
                    while true do
                        skip()
                        if str:sub(pos, pos) ~= '"' then error('expected key') end
                        local k = parseString()
                        skip()
                        if str:sub(pos, pos) ~= ':' then error('expected :') end
                        pos = pos + 1
                        obj[k] = parseValue()
                        skip()
                        local d = str:sub(pos, pos)
                        pos = pos + 1
                        if d == '}' then return obj elseif d ~= ',' then error('expected , or }') end
                    end
                elseif c == '[' then
                    pos = pos + 1
                    local arr, n = {}, 0
                    skip()
                    if str:sub(pos, pos) == ']' then pos = pos + 1; return arr end
                    while true do
                        n = n + 1
                        arr[n] = parseValue()
                        skip()
                        local d = str:sub(pos, pos)
                        pos = pos + 1
                        if d == ']' then return arr elseif d ~= ',' then error('expected , or ]') end
                    end
                elseif c == '"' then
                    return parseString()
                elseif str:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
                elseif str:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
                elseif str:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
                end
                local a, b = str:find('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
                if not a then error('unexpected character at ' .. pos) end
                pos = b + 1
                return tonumber(str:sub(a, b))
            end
            return parseValue()
        end
        json = M
    end
end

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local VERSION = '2.7.0'
local floor, min, max, sin, cos, pi = math.floor, math.min, math.max, math.sin, math.cos, math.pi

pcall(function()
    if sampev.INTERFACE.INCOMING_RPCS[61][2].dialogId == 'uint16' then
        sampev.INTERFACE.INCOMING_RPCS[61] = {
            'onShowDialog',
            { dialogId = 'uint16' },
            { style = 'uint8' },
            { title = 'string8' },
            { button1 = 'string8' },
            { button2 = 'string8' },
            { text = 'encodedString4096' },
            { placeholder = 'string8' },
        }
    end
end)

local DIALOG = {
    cardList = 269,
    cardMenu = 270,
    coolant  = 25271,
    accept   = 271,
}

local function isCardListId(dialogId)
    return dialogId == DIALOG.cardList
end

local CONFIG_ROOT = getWorkingDirectory() .. '/config'
local CONFIG_DIR  = CONFIG_ROOT .. '/Mining Tools'
local CONFIG_PATH = CONFIG_DIR .. '/config.json'

local function ensureConfigDir()
    createDirectory(CONFIG_ROOT)
    createDirectory(CONFIG_DIR)
end

local function defaultConfig()
    return {
        isReloaded        = false,
        active            = true,
        useCoolantPercent = 50,
        autoMode          = false,
        hideDialog        = true,
        rate              = 0,
        page              = 1,
        rtx4090           = false,
        lastService       = 0,
        coolantPortions   = 1,
    }
end

local function loadConfig()
    local result = defaultConfig()
    local file = io.open(CONFIG_PATH, 'r')
    if not file then return result end
    local content = file:read('*all')
    file:close()

    local ok, saved = pcall(json.decode, content)
    if ok and type(saved) == 'table' then
        for key, default in pairs(result) do
            if saved[key] ~= nil and type(saved[key]) == type(default) then
                result[key] = saved[key]
            end
        end
    end
    return result
end

local cfg = loadConfig()
cfg.active = true
cfg.useCoolantPercent = 50
if cfg.coolantPortions ~= 2 then cfg.coolantPortions = 1 end

local function saveConfig()
    ensureConfigDir()
    local file = io.open(CONFIG_PATH, 'w')
    if file then
        file:write(json.encode(cfg, { indent = true }))
        file:close()
    end
end

local function clamp(value, lo, hi)
    if value < lo then return lo elseif value > hi then return hi end
    return value
end

local function fmtNum(n)
    local s = tostring(floor((n or 0) + 0.5))
    local negative = s:sub(1, 1) == '-'
    if negative then s = s:sub(2) end
    s = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return (negative and '-' or '') .. s
end

local function isUtf8(str)
    if not str:find('[\128-\255]') then return nil end
    local i, len = 1, #str
    while i <= len do
        local c = str:byte(i)
        if c < 0x80 then
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = str:byte(i + 1)
            if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
            i = i + 2
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = str:byte(i + 1, i + 2)
            if not c3 or c2 < 0x80 or c2 > 0xBF or c3 < 0x80 or c3 > 0xBF then return false end
            i = i + 3
        else
            return false
        end
    end
    return true
end

local function toChat(str)
    if isUtf8(str) then return u8:decode(str) end
    return str
end

local function chat(text)
    sampAddChatMessage(toChat('{FF0000}|{1FE4F0} Mining Tools {FFFFFF}' .. tostring(text) .. ' {FF0000}By {00FFFF}Edward'), -1)
end

local toasts = {}
local MAX_TOASTS = 4

local function notify(title, lines, kind)
    if type(lines) == 'string' then lines = { lines } end
    table.insert(toasts, { title = title, lines = lines or {}, kind = kind or 'ok', born = os.clock() })
    while #toasts > MAX_TOASTS do table.remove(toasts, 1) end
end

local state = {
    window       = imgui.new.bool(false),
    working      = false,
    listDialog   = 0,
    cardStamp    = 0,
    cards        = {},
    earnings     = { btc = 0 },
    minCoolant   = 100,
    withdrawn    = { btc = 0 },
    autoReady    = false,
    manualOpen   = false,
    beforeWithdraw = nil,
    hiddenList   = false,
    checkPending = false,
    hideUntil    = 0,
    filling      = false,
    fillMsg      = nil,
    fontMissing  = false,
}

local HIDE_BY_TITLE = { 'Вывод прибыли видеокарты', 'Выберите тип жидкости', '^Полка №%d+', '^Стойка №%d+' }
local HIDE_BY_TEXT  = { 'Забрать прибыль', 'Достать видеокарту', 'Баланс Bitcoin' }

local function shouldHideDialog(title, text)
    for _, pattern in ipairs(HIDE_BY_TITLE) do
        if title:find(pattern) then return true end
    end
    for _, pattern in ipairs(HIDE_BY_TEXT) do
        if text:find(pattern) then return true end
    end
    return false
end

local function looksLikeCardList(title, text)
    return title:find('^{......}Выберите видеокарту')
        or title:find('^Полка №%d+')
        or text:find('Баланс Bitcoin')
        or text:find('Обзор всех видеокарт')
end

local function parseCardLine(line, index)
    local working = line:find('{......}Работает') ~= nil
    if not working and not line:find('{......}На паузе') then return nil end
    local clean = (line:gsub('%b{}', ''))
    return {
        index     = index,
        level     = tonumber(clean:match('(%d+) уровень')) or 0,
        profit    = tonumber(clean:match('(%d+%.%d+) BTC')) or 0,
        shelf     = tonumber(clean:match('№(%d+)')),
        working   = working,
        btc       = tonumber(line:match('(%d+)%.%d+ BTC')) or 0,
        coolant   = tonumber(line:match('(%d+%.%d+)%%?%s*$')) or 0,
        fluidType = line:find('BTC') and 1 or 0,
    }
end

local function parseCardList(dialogId, text)
    state.listDialog = dialogId
    state.cards      = {}
    state.earnings   = { btc = 0 }
    state.minCoolant = 101

    local index = -1
    for line in text:gmatch('[^\n\r]+') do
        index = index + 1
        local card = parseCardLine(line, index)
        if card then
            table.insert(state.cards, card)
            state.minCoolant   = math.min(state.minCoolant, card.coolant)
            state.earnings.btc = state.earnings.btc + card.btc
        end
    end
    if state.minCoolant > 100 then state.minCoolant = 0 end
end

local function setCursor(on)
    if IS_MOBILE then return end
    pcall(sampToggleCursor, on)
end

local function isListOpen()
    return state.hiddenList or (sampIsDialogActive() and isCardListId(sampGetCurrentDialogId()))
end

local function closeHiddenList()
    if not state.hiddenList then return end
    state.hiddenList = false
    sampSendDialogResponse(DIALOG.cardList, 0, -1, '')
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text, placeholder)
    if not cfg.active then return end

    local isList     = looksLikeCardList(title, text)
    local isMainList = isCardListId(dialogId)

    if isList and (not state.working or isMainList) then
        parseCardList(dialogId, text)
        state.cardStamp = state.cardStamp + 1
        if not state.working then state.autoReady = cfg.autoMode end

        if not state.working and os.clock() >= state.hideUntil and isMainList then
            state.checkPending = true
        end
    end

    if state.working and shouldHideDialog(title, text) then return false end

    if not state.working and os.clock() < state.hideUntil and dialogId ~= DIALOG.cardList then
        if dialogId == DIALOG.cardMenu or dialogId == DIALOG.accept or dialogId == DIALOG.coolant
            or shouldHideDialog(title, text) then
            return false
        end
    end

    if cfg.hideDialog and isList and isMainList then
        if not state.working then state.hiddenList = true end
        return false
    end

    if not state.working then state.hiddenList = false end
end

function sampev.onServerMessage(color, text)
    if not cfg.active then return end

    if state.filling and not text:find('состояние системы охлаждения восстановлено')
        and (text:find('[Оо]хлаж') or text:find('жидкост')) then
        state.fillMsg = (text:gsub('%b{}', ''))
    end

    if text:find('^Вы вывели {ffffff}%d+ BTC{ffff00}') then
        local amount = tonumber(text:match('Вы вывели {ffffff}(%d+)'))
        state.withdrawn.btc = state.withdrawn.btc + amount
    elseif text:find('^Добавлено в инвентарь') and text:find('BTC') then
        state.withdrawn.btc = state.withdrawn.btc + (tonumber(text:match('%((%d+) шт%)')) or 1)
    elseif text:find('Выводить прибыль можно только целыми частями')
        or text:find('состояние системы охлаждения восстановлено') then
        return false
    end
end

local Actions = {}

function Actions.markService()
    cfg.lastService = os.time()
    saveConfig()
end

local function requireBasement()
    if isListOpen() then return true end
    notify('Только в подвале', { 'Основной функционал работает только', 'в подвале майнинга у видеокарт.' }, 'warn')
    return false
end

local function setFrozen(on)
    pcall(function()
        lockPlayerControl(on)
        freezeCharPosition(PLAYER_PED, on)
    end)
end

function onScriptTerminate(scr)
    if scr == thisScript() then setFrozen(false) end
end

local function runTask(taskFunction)
    if state.working then
        notify('Занято', 'Уже выполняется другая операция.', 'warn')
        return
    end

    lua_thread.create(function()
        state.working = true
        local function send(dialogId, button, listitem)
            sampSendDialogResponse(dialogId, button, listitem, '')
        end

        setFrozen(true)
        local ok, res = pcall(taskFunction, send)
        setFrozen(false)
        if not ok then
            notify('Ошибка', tostring(res):sub(1, 90), 'err')
            if sampIsDialogActive() then sampCloseCurrentDialogWithButton(0) end
        elseif res == true then
            Actions.markService()
        end

        wait(150)
        if state.window[0] then state.hiddenList = true end
        state.hideUntil = os.clock() + 1.5
        state.working = false
    end)
end

local function coolantSlot(card)
    if card.fluidType == 1 then return 0 end
    return nil
end

local function portionsFor(card)
    return cfg.coolantPortions == 2 and 2 or 1
end

local function filterCards(predicate)
    local result = {}
    for _, card in ipairs(state.cards) do
        if predicate(card) then table.insert(result, card) end
    end
    return result
end

local function stepWithdraw(send, listId, cards)
    for _, card in ipairs(cards) do
        send(listId, 1, card.index - 1)
        send(DIALOG.cardMenu, 1, 1)
        send(DIALOG.accept, 1, 0)
        send(DIALOG.cardMenu, 0, 0)
    end
end

local function stepSwitch(send, listId, cards)
    for _, card in ipairs(cards) do
        send(listId, 1, card.index - 1)
        send(DIALOG.cardMenu, 1, 0)
        send(DIALOG.cardMenu, 0, 0)
    end
end

local function stepFill(send, listId, cards)
    for _, card in ipairs(cards) do
        local slot = coolantSlot(card)
        if slot ~= nil then
            for _ = 1, portionsFor(card) do
                send(listId, 1, card.index - 1)
                send(DIALOG.cardMenu, 1, 2)
                send(DIALOG.coolant, 1, slot)
            end
        end
        send(DIALOG.cardMenu, 0, 0)
    end
end

local function withdrawReport(cards)
    local total = state.withdrawn.btc
    if total <= 0 then
        for _, card in ipairs(cards) do total = total + card.btc end
    end
    return 'Снято: ' .. total .. ' BTC (с видеокарт: ' .. #cards .. ')'
end

local function waitFillSettle(stampBefore)
    local startedAt  = os.clock()
    local lastStamp  = state.cardStamp
    local lastChange = os.clock()
    while os.clock() - startedAt < 1.5 do
        wait(50)
        if state.cardStamp ~= lastStamp then
            lastStamp, lastChange = state.cardStamp, os.clock()
        end
        if lastStamp ~= stampBefore and os.clock() - lastChange >= 0.25 then break end
    end
end

local function fillReport(cards, stampBefore)
    local filled = {}
    for _, card in ipairs(cards) do
        if coolantSlot(card) ~= nil then filled[#filled + 1] = card end
    end
    if #filled == 0 then return {}, nil end

    local verified  = state.cardStamp ~= stampBefore
    local refreshed = {}
    if verified then
        for _, card in ipairs(state.cards) do refreshed[card.index] = card end
    end

    local good, failed = {}, 0
    for _, card in ipairs(filled) do
        local fresh = refreshed[card.index]
        if verified and fresh and fresh.coolant < card.coolant + 0.5 then
            failed = failed + 1
        else
            good[#good + 1] = card
        end
    end

    if failed == #filled then
        return { 'Уровень жидкости не изменился.', 'Возможно, у вас нет охлаждайки.' }, 'fail'
    end

    local portionsMin, portionsMax, levelMin, levelMax = 99, 0, 101, -1
    for _, card in ipairs(good) do
        local portions = portionsFor(card)
        portionsMin, portionsMax = min(portionsMin, portions), max(portionsMax, portions)
        local fresh = refreshed[card.index]
        local level = fresh and fresh.coolant or min(100, card.coolant + 50 * portions)
        levelMin, levelMax = min(levelMin, level), max(levelMax, level)
    end

    local portionsText = portionsMin == portionsMax and tostring(portionsMin) or (portionsMin .. '-' .. portionsMax)
    local lo, hi = floor(levelMin), floor(levelMax)
    local levelText = lo == hi and (lo .. '%') or (lo .. '-' .. hi .. '%')
    local lines = {
        'Залито видеокарт: ' .. #good .. ' (по ' .. portionsText .. ' порции)',
        'Уровень жидкости: ' .. levelText,
    }
    if failed > 0 then
        lines[#lines + 1] = 'Не залито: ' .. failed .. ' шт. Проверьте охлаждайку.'
        return lines, 'partial'
    end
    return lines, 'ok'
end

local function reportFillFailure(lines)
    notify('Не удалось залить жидкость', lines, 'err')
    local extra = state.fillMsg and (' Сервер: {FFFF00}' .. state.fillMsg:sub(1, 80)) or ''
    chat('{FF4B4B}Не удалось залить жидкость{FFFFFF} - уровень не изменился, возможно нет охлаждайки.' .. extra)
end

local function beginFill()
    state.filling, state.fillMsg = true, nil
end

local function endFill()
    state.filling = false
end

function Actions.withdraw()
    if not requireBasement() then return end
    local cards = filterCards(function(card) return card.btc >= 1 end)
    if #cards == 0 then return notify('Снятие', 'Нет криптовалюты для снятия.', 'info') end

    state.withdrawn = { btc = 0 }
    state.beforeWithdraw = state.earnings.btc
    local listId = state.listDialog
    runTask(function(send)
        stepWithdraw(send, listId, cards)
        wait(100)
        notify('Снятие BTC', { withdrawReport(cards) }, 'ok')
        return true
    end)
end

function Actions.fill(percent)
    if not requireBasement() then return end
    local threshold = percent or cfg.useCoolantPercent
    local cards = filterCards(function(card) return card.coolant < threshold end)
    if #cards == 0 then return notify('Охлаждение', 'Во всех видеокартах достаточно жидкости.', 'info') end

    local listId = state.listDialog
    local stamp  = state.cardStamp
    runTask(function(send)
        beginFill()
        local ok, err = pcall(function()
            stepFill(send, listId, cards)
            waitFillSettle(stamp)
        end)
        endFill()
        if not ok then error(err, 0) end

        local lines, status = fillReport(cards, stamp)
        if status == 'fail' then
            reportFillFailure(lines)
        elseif status == 'partial' then
            notify('Заливка жидкости', lines, 'warn')
        elseif #lines > 0 then
            notify('Заливка жидкости', lines, 'info')
        end
        return status ~= 'fail'
    end)
end

function Actions.switchCards(enable)
    if not requireBasement() then return end
    local cards = filterCards(function(card) return card.working ~= enable end)
    if #cards == 0 then
        return notify('Видеокарты', 'Видеокарты и так уже ' .. (enable and 'включены.' or 'выключены.'), 'info')
    end

    local listId = state.listDialog
    local stamp  = state.cardStamp
    runTask(function(send)
        stepSwitch(send, listId, cards)
        waitFillSettle(stamp)

        local failed = {}
        if state.cardStamp ~= stamp then
            local fresh = {}
            for _, card in ipairs(state.cards) do fresh[card.index] = card end
            for _, card in ipairs(cards) do
                local now = fresh[card.index]
                if now and now.working ~= enable then
                    failed[#failed + 1] = '№' .. (card.shelf or (card.index + 1))
                end
            end
        end

        local done = #cards - #failed
        if done > 0 then
            notify('Видеокарты', (enable and 'Включено' or 'Выключено') .. ' видеокарт: ' .. done,
                enable and 'ok' or 'warn')
        end
        if #failed > 0 then
            local text = table.concat(failed, ', ')
            if #text > 30 then text = #failed .. ' шт.' end
            notify(enable and 'Не удалось включить' or 'Не удалось выключить',
                { 'Не изменились: ' .. text, enable and 'Возможно, нет охлаждайки.' or 'Попробуйте ещё раз.' }, 'err')
        end
        return done > 0
    end)
end

local function notifyIfNothingToDo()
    if #state.cards == 0 then return end
    local lowCoolant = 0
    for _, card in ipairs(state.cards) do
        if not card.working or card.btc >= 1 then return end
        if card.coolant < cfg.useCoolantPercent then lowCoolant = lowCoolant + 1 end
    end
    local lines = { 'Работают: ' .. #state.cards .. ', снимать нечего.' }
    if lowCoolant > 0 then lines[2] = 'Жидкости мало: ' .. lowCoolant .. ' шт.' end
    notify('Тут нечего делать', lines, lowCoolant > 0 and 'info' or 'ok')
end

local function warnNoCooling()
    local list = {}
    for _, card in ipairs(state.cards) do
        if not card.working and card.coolant < 1 then list[#list + 1] = '№' .. (card.shelf or (card.index + 1)) end
    end
    if #list == 0 then return end
    local text = table.concat(list, ', ')
    if #text > 34 then text = #list .. ' шт.' end
    notify('Нет охлаждения', { 'Не работают без жидкости: ' .. text, 'Залейте охлаждайку.' }, 'err')
end

function Actions.auto(manual)
    local threshold = cfg.useCoolantPercent
    local toWithdraw, toEnable, toFill = {}, {}, {}
    for _, card in ipairs(state.cards) do
        if card.btc >= 1 then table.insert(toWithdraw, card) end
        if not card.working then
            table.insert(toEnable, card)
            if card.coolant < threshold then table.insert(toFill, card) end
        end
    end

    if #toWithdraw == 0 and #toEnable == 0 then
        if manual then notify('Авто режим', 'Включён. Сейчас делать нечего.', 'info') end
        return
    end

    state.withdrawn = { btc = 0 }
    if #toWithdraw > 0 then state.beforeWithdraw = state.earnings.btc end
    local listId = state.listDialog
    local stamp  = state.cardStamp
    runTask(function(send)

        if #toWithdraw > 0 then
            stepWithdraw(send, listId, toWithdraw)
            wait(#toFill > 0 and 300 or 150)
        end
        local fillStamp = state.cardStamp
        if #toFill > 0 then
            beginFill()
            local ok, err = pcall(function()
                stepFill(send, listId, toFill)
                waitFillSettle(fillStamp)
            end)
            endFill()
            if not ok then error(err, 0) end
            wait(100)
        end
        if #toEnable > 0 then
            stepSwitch(send, listId, toEnable)
            wait(150)
        end
        wait(100)

        local lines = {}
        if #toWithdraw > 0 then table.insert(lines, withdrawReport(toWithdraw)) end
        if #toEnable > 0 then table.insert(lines, 'Включено видеокарт: ' .. #toEnable) end
        local fillLines, fillStatus = fillReport(toFill, fillStamp)
        local kind = 'ok'
        if fillStatus == 'fail' then
            reportFillFailure(fillLines)
        else
            for _, line in ipairs(fillLines) do table.insert(lines, line) end
            if fillStatus == 'partial' then kind = 'warn' end
        end
        if #lines > 0 then notify('Авто режим', lines, kind) end
        return #toWithdraw > 0 or fillStatus ~= 'fail'
    end)
end

local RATE_MIN, RATE_MAX = 1000, 100000000
local rateState = { busy = false, time = 0 }

local RATE_SOURCES = {
    { name = 'Binance',
      urls = { 'https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT' },
      calc = function(d) return tonumber(d[1].price) end },
    { name = 'CoinGecko',
      urls = { 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd' },
      calc = function(d) return d[1].bitcoin.usd end },
    { name = 'CryptoCompare',
      urls = { 'https://min-api.cryptocompare.com/data/price?fsym=BTC&tsyms=USD' },
      calc = function(d) return d[1].USD end },
    { name = 'Coinbase',
      urls = { 'https://api.coinbase.com/v2/prices/BTC-USD/spot' },
      calc = function(d) return tonumber(d[1].data.amount) end },
    { name = 'Coinbase (курсы)',
      urls = { 'https://api.coinbase.com/v2/exchange-rates?currency=BTC' },
      calc = function(d) return tonumber(d[1].data.rates.USD) end },
}

local function readWholeFile(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local body = file:read('*all')
    file:close()
    if body and #body > 0 then return body end
    return nil
end

local function downloadEffil(url)
    local okEffil, effil = pcall(require, 'effil')
    if not okEffil then return nil, 'нет effil' end
    local runner = effil.thread(function(u)
        local okr, requests = pcall(require, 'requests')
        if not okr then return nil, 'нет requests' end
        local ok, resp = pcall(requests.get, u, { headers = { ['User-Agent'] = 'Mozilla/5.0' } })
        if ok and resp and resp.status_code == 200 then return resp.text end
        return nil, 'нет ответа'
    end)
    local task = runner(url)
    local startedAt = os.clock()
    while true do
        local st = task:status()
        if st ~= 'running' and st ~= 'paused' then break end
        if os.clock() - startedAt > 8 then
            pcall(function() task:cancel(0) end)
            return nil, 'таймаут'
        end
        wait(50)
    end
    if task:status() ~= 'completed' then return nil, 'нет ответа' end
    local body, why = task:get()
    if not body or #body == 0 then return nil, why or 'нет ответа' end
    return body
end

local function downloadAsync(url)
    if IS_MOBILE or pcall(require, 'effil') then
        local body, why = downloadEffil(url)
        if body then return body end
        if IS_MOBILE then return nil, why end
    end
    if type(downloadUrlToFile) ~= 'function' then return nil, 'нет загрузчика' end
    ensureConfigDir()
    local tmpPath = CONFIG_DIR .. '/rate.tmp'
    os.remove(tmpPath)

    local finished = false
    downloadUrlToFile(url, tmpPath, function(_, status)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD or status == dlstatus.STATUS_ENDDOWNLOADDATA then
            finished = true
        end
    end)

    local startedAt = os.clock()
    while not finished and os.clock() - startedAt < 8 do wait(50) end
    if finished then wait(100) end

    local body = readWholeFile(tmpPath)
    os.remove(tmpPath)
    if not body then return nil, 'нет ответа' end
    return body
end

local wininet
local function downloadSync(url)
    if IS_MOBILE then return nil, 'нет wininet' end
    if not wininet then
        local ok, lib = pcall(ffi.load, 'wininet')
        if not ok then return nil, 'нет wininet' end
        for _, declaration in ipairs({
            'void* InternetOpenA(const char* agent, unsigned long access, const char* proxy, const char* bypass, unsigned long flags);',
            'void* InternetOpenUrlA(void* hNet, const char* url, const char* headers, unsigned long hdrLen, unsigned long flags, uintptr_t ctx);',
            'int InternetReadFile(void* h, void* buf, unsigned long n, unsigned long* got);',
            'int InternetCloseHandle(void* h);',
            'int InternetSetOptionA(void* h, unsigned long opt, void* buf, unsigned long len);',
        }) do pcall(ffi.cdef, declaration) end
        wininet = lib
    end

    local net = wininet.InternetOpenA('Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 0, nil, nil, 0)
    if net == nil then return nil, 'нет ответа' end

    local timeoutMs = ffi.new('unsigned long[1]', 3000)
    for _, option in ipairs({ 2, 5, 6 }) do wininet.InternetSetOptionA(net, option, timeoutMs, 4) end

    local handle = wininet.InternetOpenUrlA(net, url, nil, 0, 0x80000000 + 0x04000000, 0)
    if handle == nil then
        wininet.InternetCloseHandle(net)
        return nil, 'нет ответа'
    end

    local buffer, got, parts, total = ffi.new('char[4096]'), ffi.new('unsigned long[1]'), {}, 0
    while total < 65536 and wininet.InternetReadFile(handle, buffer, 4096, got) ~= 0 and got[0] > 0 do
        parts[#parts + 1] = ffi.string(buffer, got[0])
        total = total + got[0]
    end
    wininet.InternetCloseHandle(handle)
    wininet.InternetCloseHandle(net)

    if total == 0 then return nil, 'нет ответа' end
    return table.concat(parts)
end

local function downloadJson(url, useWinInet)
    local body, reason
    if useWinInet then body, reason = downloadSync(url) else body, reason = downloadAsync(url) end
    if not body then return nil, reason end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= 'table' then return nil, 'ответ не JSON' end
    return data
end

local function fetchRate(useWinInet, sourceLimit)
    local errors = {}
    for i, source in ipairs(RATE_SOURCES) do
        if sourceLimit and i > sourceLimit then break end

        local answers, reason = {}, nil
        for k, url in ipairs(source.urls) do
            local data, why = downloadJson(url, useWinInet)
            if not data then reason = why; break end
            answers[k] = data
        end

        if not reason then
            local ok, value = pcall(source.calc, answers)
            value = ok and tonumber(value) or nil
            if value and value >= RATE_MIN and value <= RATE_MAX then
                return floor(value + 0.5), source.name
            end
            reason = 'неверные данные'
        end
        errors[#errors + 1] = source.name .. ': ' .. reason
    end
    return nil, errors
end

local function attemptRate(useWinInet, sourceLimit, errors)
    local ok, value, second = pcall(fetchRate, useWinInet, sourceLimit)
    if ok and value then return value, second end

    if not ok then

        if useWinInet then errors[#errors + 1] = 'WinInet: ' .. tostring(value):sub(1, 40) end
        return nil
    end

    local prefix = useWinInet and 'WinInet ' or ''
    for i = 1, 2 do
        if second and second[i] then errors[#errors + 1] = prefix .. second[i] end
    end
    return nil
end

local function updateRate(manual, afterDone, silent)
    if rateState.busy then return end
    rateState.busy = true

    lua_thread.create(function()
        local errors = {}
        local value, sourceName = attemptRate(false, nil, errors)
        if not value then
            value, sourceName = attemptRate(true, 3, errors)
        end
        rateState.busy = false

        if value then
            cfg.rate = value
            rateState.time = os.time()
            rateState.source = sourceName
            saveConfig()
            if not silent then
                notify('Курс BTC', { 'Обновлён: ' .. fmtNum(value) .. ' руб.', 'Источник: ' .. sourceName }, 'ok')
            end
        elseif not silent then
            local lines = { 'Курс не изменён.' }
            for i = 1, math.min(#errors, 4) do lines[#lines + 1] = errors[i] end
            notify('Не удалось обновить курс', lines, 'err')
        end
        if afterDone then afterDone() end
    end)
end

local WIN_W, WIN_H, SCALE = 976, 544, 1

local function fitScale()
    if not IS_MOBILE then return 1 end
    local ok, sw, sh = pcall(getScreenResolution)
    if not ok or not sw or sw <= 0 or not sh or sh <= 0 then return 1 end
    return clamp(min(sw * 0.94 / WIN_W, sh * 0.82 / (WIN_H + 30)), 0.5, 3)
end
local originX, originY, drawList = 0, 0, nil
local Font, iconFonts = {}, {}
local glyphRanges, faRanges

local Palette = {
    bg    = 0x04060B, frame = 0x1C222C, headLine = 0x151A23, sideLine = 0x12161F,
    card0 = 0x0C111A, card1 = 0x0A0D15, cardLine = 0x1B212B,
    tile  = 0x090E19, tileLine = 0x1C2330, divider = 0x1A2029,
    white = 0xF2F5FA, text  = 0xC6CDD8, muted = 0x8C95A8, dim = 0x5D6679,
    green = 0x2EE6B0, blue = 0x2EB8FF, ice = 0x55CCFF, orange = 0xF7931A,
    gold  = 0xF5A623, red = 0xF0554B,
}

local poolVec
do
local VEC_POOL_SIZE, vecPoolIndex, vecPool = 64, 0, {}
for i = 1, VEC_POOL_SIZE do vecPool[i] = imgui.ImVec2(0, 0) end
function poolVec(x, y)
    vecPoolIndex = vecPoolIndex % VEC_POOL_SIZE + 1
    local v = vecPool[vecPoolIndex]
    v.x, v.y = x, y
    return v
end
end
local function toScreen(x, y) return poolVec(originX + x * SCALE, originY + y * SCALE) end

local function rgba(hex, a)
    a = a or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return floor(a * 255 + 0.5) * 16777216 + (hex % 256) * 65536
        + (floor(hex / 256) % 256) * 256 + floor(hex / 65536) % 256
end

local function mixColor(h1, h2, t)
    local r1, g1, b1 = floor(h1 / 65536) % 256, floor(h1 / 256) % 256, h1 % 256
    local r2, g2, b2 = floor(h2 / 65536) % 256, floor(h2 / 256) % 256, h2 % 256
    return floor(r1 + (r2 - r1) * t + 0.5) * 65536 + floor(g1 + (g2 - g1) * t + 0.5) * 256
        + floor(b1 + (b2 - b1) * t + 0.5)
end

local function circleSegs(r) return clamp(floor(r * SCALE + 8), 10, 64) end
local function cornerSegs(r) return clamp(floor(r * SCALE * 0.6 + 2), 2, 12) end

local function roundRectPath(x, y, w, h, tl, tr, br, bl)
    tr, br, bl = tr or tl, br or tl, bl or tl
    local m = min(w, h) / 2
    tl, tr, br, bl = min(tl, m), min(tr, m), min(br, m), min(bl, m)
    drawList:PathClear()
    if tl > 0 then drawList:PathArcTo(toScreen(x + tl, y + tl), tl * SCALE, pi, pi * 1.5, cornerSegs(tl)) else drawList:PathLineTo(toScreen(x, y)) end
    if tr > 0 then drawList:PathArcTo(toScreen(x + w - tr, y + tr), tr * SCALE, pi * 1.5, pi * 2, cornerSegs(tr)) else drawList:PathLineTo(toScreen(x + w, y)) end
    if br > 0 then drawList:PathArcTo(toScreen(x + w - br, y + h - br), br * SCALE, 0, pi * 0.5, cornerSegs(br)) else drawList:PathLineTo(toScreen(x + w, y + h)) end
    if bl > 0 then drawList:PathArcTo(toScreen(x + bl, y + h - bl), bl * SCALE, pi * 0.5, pi, cornerSegs(bl)) else drawList:PathLineTo(toScreen(x, y + h)) end
end

local function fillRoundRect(x, y, w, h, col, tl, tr, br, bl)
    roundRectPath(x, y, w, h, tl, tr, br, bl)
    drawList:PathFillConvex(col)
end

local function strokeRoundRect(x, y, w, h, col, tl, tr, br, bl)
    local function s(v) return v and max(0, v - 0.5) end
    roundRectPath(x + 0.5, y + 0.5, w - 1, h - 1, s(tl), s(tr), s(br), s(bl))
    drawList:PathStroke(col, true, SCALE)
end

local nativeGradient
do
    local ok, f = pcall(function() return imgui.ShadeVertsLinearColorGradientKeepAlpha end)
    if ok and f then nativeGradient = f end
end

local function applyGradient(vs, x0, y0, x1, y1, h0, h1)
    local ve = drawList.VtxBuffer.Size
    if ve <= vs then return end
    if nativeGradient then
        nativeGradient(drawList, vs, ve, toScreen(x0, y0), toScreen(x1, y1), rgba(h0), rgba(h1))
        return
    end
    local ax, ay = originX + x0 * SCALE, originY + y0 * SCALE
    local gx, gy = (x1 - x0) * SCALE, (y1 - y0) * SCALE
    local len2 = gx * gx + gy * gy
    local data = drawList.VtxBuffer.Data
    for i = vs, ve - 1 do
        local v = data[i]
        local t = len2 > 0 and clamp(((v.pos.x - ax) * gx + (v.pos.y - ay) * gy) / len2, 0, 1) or 0
        v.col = floor(v.col / 16777216) % 256 * 16777216 + rgba(mixColor(h0, h1, t)) % 16777216
    end
end

local function gradientRoundRect(x, y, w, h, h0, h1, a, dir, tl, tr, br, bl)
    local vs = drawList.VtxBuffer.Size
    fillRoundRect(x, y, w, h, rgba(h0, a), tl, tr, br, bl)
    if dir == 'h' then applyGradient(vs, x, y, x + w, y, h0, h1) else applyGradient(vs, x, y, x, y + h, h0, h1) end
end

local function gradientCornerRect(x, y, w, h, r, h0, h1, a, tTR, tBL)
    local L = 1 / (tTR * tTR / (w * w) + tBL * tBL / (h * h))
    local vs = drawList.VtxBuffer.Size
    fillRoundRect(x, y, w, h, rgba(h0, a), r)
    applyGradient(vs, x, y, x + tTR * L / w, y + tBL * L / h, h0, h1)
end

local function glowRoundRect(x, y, w, h, r, hex, a, spread)
    local col = rgba(hex, a / 5)
    for i = 5, 1, -1 do
        local e = spread * i / 5
        fillRoundRect(x - e, y - e, w + e * 2, h + e * 2, col, r + e)
    end
end

local function fillCircle(cx, cy, r, col)
    drawList:AddCircleFilled(toScreen(cx, cy), r * SCALE, col, circleSegs(r))
end

local function glowCircle(cx, cy, r, hex, a, spread)
    local col = rgba(hex, a / 5)
    for i = 5, 1, -1 do fillCircle(cx, cy, r + spread * i / 5, col) end
end

local function drawLine(x1, y1, x2, y2, col, th)
    drawList:AddLine(toScreen(x1, y1), toScreen(x2, y2), col, (th or 1) * SCALE)
end

local function drawHLine(x1, x2, y, col)
    drawList:AddRectFilled(toScreen(x1, y), toScreen(x2, y + 1), col)
end

local toUtf8
do
local u8cache, u8count = {}, 0
function toUtf8(str)
    local r = u8cache[str]
    if not r then
        if u8count > 300 then u8cache, u8count = {}, 0 end
        r = isUtf8(str) == false and u8(str) or str
        u8cache[str], u8count = r, u8count + 1
    end
    return r
end
end

local fontAscent
do
local ascentMode
function fontAscent()
    if ascentMode ~= 'none' then
        if ascentMode == nil or ascentMode == 'baked' then
            local ok, v = pcall(function() return ffi.C.igGetFontBaked().Ascent end)
            if ok and type(v) == 'number' then ascentMode = 'baked'; return v end
            ascentMode = (ascentMode == nil) and 'font' or 'none'
        end
        if ascentMode == 'font' then
            local ok, v = pcall(function() return imgui.GetFont().Ascent end)
            if ok and type(v) == 'number' then return v end
            ascentMode = 'none'
        end
    end
    local ok, s = pcall(function() return imgui.GetFontSize() end)
    return (ok and type(s) == 'number' and s or 16) * 0.82
end
end

local function drawText(font, str, x, base, col, align)
    str = toUtf8(str)
    local fp = font.f
    if fp then imgui.PushFont(fp) end
    local px = originX + x * SCALE
    if align then
        local w = imgui.CalcTextSize(str).x
        px = align == 'c' and px - w / 2 or px - w
    end
    drawList:AddText(poolVec(px, originY + base * SCALE - fontAscent()), col, str)
    if fp then imgui.PopFont() end
end

local function textWidth(font, str)
    str = toUtf8(str)
    local fp = font.f
    if fp then imgui.PushFont(fp) end
    local w = imgui.CalcTextSize(str).x
    if fp then imgui.PopFont() end
    return w / SCALE
end

local ICON_SIZES = { 18, 21, 24, 28, 32 }
local ICONS = {
    gear = 0xF013, snowflake = 0xF2DC, droplet = 0xF043, bolt = 0xF0E7, database = 0xF1C0,
    coins = 0xF51E, refresh = 0xF021, info = 0xF129, check = 0xF00C, warn = 0xF071, chevron = 0xF054, xmark = 0xF00D, minus = 0xF068, plus = 0xF067, plane = 0xF1D8,
    chart = 0xF080, hourglass = 0xF254, calendar = 0xF274,
}
local iconWidths = {}
for k, cp in pairs(ICONS) do
    ICONS[k] = string.char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
end

local drawIcon
do
local vcx, vcy, vr, vcol, vth = 0, 0, 1, 0, 1
local function pt(x, y) return toScreen(vcx + x * vr, vcy + y * vr) end
local function ln(x1, y1, x2, y2, k) drawList:AddLine(pt(x1, y1), pt(x2, y2), vcol, vth * (k or 1) * SCALE) end
local function ring(x, y, r, k) drawList:AddCircle(pt(x, y), r * vr * SCALE, vcol, circleSegs(r * vr), vth * (k or 1) * SCALE) end
local function disc(x, y, r) drawList:AddCircleFilled(pt(x, y), r * vr * SCALE, vcol, circleSegs(r * vr)) end
local function tri(x1, y1, x2, y2, x3, y3) drawList:AddTriangleFilled(pt(x1, y1), pt(x2, y2), pt(x3, y3), vcol) end
local function box(x1, y1, x2, y2) drawList:AddRectFilled(pt(x1, y1), pt(x2, y2), vcol) end

local V = {}
V.gear = function()
    for i = 0, 7 do
        local an = i * pi / 4
        ln(cos(an) * 0.62, sin(an) * 0.62, cos(an) * 0.98, sin(an) * 0.98, 1.9)
    end
    ring(0, 0, 0.6, 1.2)
    ring(0, 0, 0.2, 1)
end
V.snowflake = function()
    for i = 0, 2 do
        local an = i * pi / 3
        ln(-cos(an) * 0.95, -sin(an) * 0.95, cos(an) * 0.95, sin(an) * 0.95, 0.9)
    end
    for k = 0, 5 do
        local b = k * pi / 3
        local mx, my = cos(b) * 0.62, sin(b) * 0.62
        ln(mx, my, mx + cos(b + 0.8) * 0.3, my + sin(b + 0.8) * 0.3, 0.8)
        ln(mx, my, mx + cos(b - 0.8) * 0.3, my + sin(b - 0.8) * 0.3, 0.8)
    end
end
V.droplet = function()
    disc(0, 0.3, 0.55)
    tri(0, -0.95, -0.494, 0.058, 0.494, 0.058)
end
V.bolt = function()
    ln(0.3, -0.95, -0.3, 0.1, 2.2)
    ln(-0.3, 0.1, 0.25, 0.1, 2.2)
    ln(0.25, 0.1, -0.3, 0.95, 2.2)
end
V.database = function()
    for _, yc in ipairs({ -0.62, 0, 0.62 }) do
        ln(-0.55, yc, 0.55, yc, 2.6)
    end
end
V.coins = function()
    disc(0.25, -0.2, 0.55)
    ring(-0.2, 0.25, 0.55, 1.3)
end
V.refresh = function()
    local a0, a1 = 0.35 * pi, 1.85 * pi
    drawList:PathClear()
    drawList:PathArcTo(pt(0, 0), 0.68 * vr * SCALE, a0, a1, 20)
    drawList:PathStroke(vcol, false, vth * SCALE)
    local ex, ey = 0.68 * cos(a1), 0.68 * sin(a1)
    local tx, ty, nx, ny = -sin(a1), cos(a1), cos(a1), sin(a1)
    tri(ex + tx * 0.5, ey + ty * 0.5, ex + nx * 0.34, ey + ny * 0.34, ex - nx * 0.34, ey - ny * 0.34)
end
V.info = function()
    ring(0, 0, 0.9, 1)
    disc(0, -0.42, 0.11)
    ln(0, -0.08, 0, 0.5, 1.3)
end
V.check = function()
    ln(-0.7, 0.05, -0.2, 0.55, 1.5)
    ln(-0.2, 0.55, 0.75, -0.5, 1.5)
end
V.warn = function()
    ln(0, -0.9, 0.9, 0.75, 1)
    ln(0.9, 0.75, -0.9, 0.75, 1)
    ln(-0.9, 0.75, 0, -0.9, 1)
    ln(0, -0.25, 0, 0.25, 1.2)
    disc(0, 0.52, 0.09)
end
V.chevron = function()
    ln(-0.3, -0.7, 0.4, 0, 1.4)
    ln(0.4, 0, -0.3, 0.7, 1.4)
end
V.xmark = function()
    ln(-0.7, -0.7, 0.7, 0.7, 1.3)
    ln(-0.7, 0.7, 0.7, -0.7, 1.3)
end
V.chart = function()
    box(-0.85, 0.1, -0.45, 0.85)
    box(-0.2, -0.3, 0.2, 0.85)
    box(0.45, -0.85, 0.85, 0.85)
end
V.hourglass = function()
    ln(-0.6, -0.9, 0.6, -0.9, 1.3)
    ln(-0.6, 0.9, 0.6, 0.9, 1.3)
    tri(-0.5, -0.8, 0.5, -0.8, 0, 0)
    tri(0, 0, -0.5, 0.8, 0.5, 0.8)
end
V.calendar = function()
    ln(-0.8, -0.6, 0.8, -0.6, 1)
    ln(0.8, -0.6, 0.8, 0.85, 1)
    ln(0.8, 0.85, -0.8, 0.85, 1)
    ln(-0.8, 0.85, -0.8, -0.6, 1)
    box(-0.8, -0.6, 0.8, -0.2)
    ln(-0.4, -0.9, -0.4, -0.45, 1.2)
    ln(0.4, -0.9, 0.4, -0.45, 1.2)
end

function drawIcon(name, px, cx, cy, col)
    local f = (not IS_MOBILE) and iconFonts[px] or nil
    if f then
        local str = ICONS[name]
        imgui.PushFont(f)
        local key = px .. name
        local w = iconWidths[key]
        if not w then w = imgui.CalcTextSize(str).x; iconWidths[key] = w end
        drawList:AddText(poolVec(originX + cx * SCALE - w / 2, originY + cy * SCALE - f.FontSize / 2), col, str)
        imgui.PopFont()
        return true
    end
    local draw = V[name]
    if not draw then return false end
    vcx, vcy, vr, vcol = cx, cy, px * 0.42, col
    vth = max(1.4, vr * 0.2)
    draw()
    return true
end
end

local antiAliasOff
do
local hasDrawListFlags, savedDrawListFlags
function antiAliasOff(on)
    if hasDrawListFlags == nil then hasDrawListFlags = pcall(function() return drawList.Flags end) end
    if not hasDrawListFlags then return end
    if on then
        savedDrawListFlags = drawList.Flags
        drawList.Flags = bit.band(savedDrawListFlags, bit.bnot(2))
    else
        drawList.Flags = savedDrawListFlags
    end
end
end

local function buildBlade(ax, ay, cx, cy, bx, by, wtip, wmax)
    local n, pts = 16, {}
    for i = 0, n do
        local t = i / n
        local u = 1 - t
        local px = u * u * ax + 2 * u * t * cx + t * t * bx
        local py = u * u * ay + 2 * u * t * cy + t * t * by
        local dx = 2 * u * (cx - ax) + 2 * t * (bx - cx)
        local dy = 2 * u * (cy - ay) + 2 * t * (by - cy)
        local l = math.sqrt(dx * dx + dy * dy)
        local w = (wtip + (wmax - wtip) * sin(pi * t) ^ 0.9) / 2
        pts[i] = { px - dy / l * w, py + dx / l * w, px + dy / l * w, py - dx / l * w }
    end
    return { pts = pts, n = n, ax = ax, ay = ay, bx = bx, by = by, capRadius = wtip / 2 }
end

local PICKAXE_SHAPES = {
    single = { h = { 2.4, 21.6, 16.9, 7.1, 2.9, 1.45 }, s = buildBlade(6.0, 2.4, 16.5, 6.7, 21.6, 16.3, 1.6, 3.7) },
    cross  = { h = { 2.6, 21.4, 19.3, 4.7, 3.0, 1.5 },  s = buildBlade(13.6, 1.0, 20.2, 3.8, 23.2, 10.4, 1.9, 3.9) },
}

local function drawPickaxe(cx, cy, size, col, kind, mirror)
    local k, m = size / 24, mirror and -1 or 1
    local function P(px, py) return toScreen(cx + (px - 12) * m * k, cy + (py - 12) * k) end
    local p = PICKAXE_SHAPES[kind]
    local h, st = p.h, p.s
    drawList:AddLine(P(h[1], h[2]), P(h[3], h[4]), col, h[5] * k * SCALE)
    drawList:AddCircleFilled(P(h[1], h[2]), h[6] * k * SCALE, col, 12)
    local pts, n = st.pts, st.n
    antiAliasOff(true)
    for i = 0, n - 1 do
        local a, b = pts[i], pts[i + 1]
        drawList:AddTriangleFilled(P(a[1], a[2]), P(b[1], b[2]), P(b[3], b[4]), col)
        drawList:AddTriangleFilled(P(a[1], a[2]), P(b[3], b[4]), P(a[3], a[4]), col)
    end
    antiAliasOff(false)
    drawList:PathClear()
    for i = 0, n do drawList:PathLineTo(P(pts[i][1], pts[i][2])) end
    for i = n, 0, -1 do drawList:PathLineTo(P(pts[i][3], pts[i][4])) end
    drawList:PathStroke(col, true, 1)
    drawList:AddCircleFilled(P(st.ax, st.ay), st.capRadius * k * SCALE, col, 10)
    drawList:AddCircleFilled(P(st.bx, st.by), st.capRadius * k * SCALE, col, 10)
end

local function drawCrossedPickaxes(cx, cy, size, col)
    drawPickaxe(cx, cy, size, col, 'cross', false)
    drawPickaxe(cx, cy, size, col, 'cross', true)
end

local BTC_LOGO = {}
do
    local ang = math.rad(14)
    local ca, sa = cos(ang), sin(ang)
    local OX = -1.6
    local function R(x, y)
        x = x + OX
        return x * ca - y * sa, x * sa + y * ca
    end
    local T = 4.0
    local rects, arcs = {}, {}
    local function rect(x0, y0, x1, y1)
        local ax, ay = R(x0, y0); local bx, by = R(x1, y0)
        local cx, cy = R(x1, y1); local dx, dy = R(x0, y1)
        rects[#rects + 1] = { ax, ay, bx, by, cx, cy, dx, dy }
    end
    local stemR = -4.5
    rect(-8.5, -14, stemR, 14)
    for _, b in ipairs({ { 1.5, -6.5, 5.5 }, { 2.5, 5.5, 6.5 } }) do
        local bx, by, r = b[1], b[2], b[3]
        rect(stemR - 0.2, by - r - T / 2, bx + 0.3, by - r + T / 2)
        rect(stemR - 0.2, by + r - T / 2, bx + 0.3, by + r + T / 2)
        local px, py = R(bx, by)
        arcs[#arcs + 1] = { px, py, r }
    end
    for _, tx in ipairs({ -3.0, 1.8 }) do
        rect(tx - 1.3, -19.5, tx + 1.3, -13.8)
        rect(tx - 1.3, 13.8, tx + 1.3, 19.5)
    end
    BTC_LOGO.rects, BTC_LOGO.arcs, BTC_LOGO.T, BTC_LOGO.ang = rects, arcs, T, ang
end

local function drawBitcoinLogo(cx, cy, k, col)
    for _, r in ipairs(BTC_LOGO.rects) do
        drawList:PathClear()
        for i = 0, 3 do drawList:PathLineTo(toScreen(cx + r[i * 2 + 1] * k, cy + r[i * 2 + 2] * k)) end
        drawList:PathFillConvex(col)
    end
    for _, a in ipairs(BTC_LOGO.arcs) do
        drawList:PathClear()
        drawList:PathArcTo(toScreen(cx + a[1] * k, cy + a[2] * k), a[3] * k * SCALE,
            -pi / 2 + BTC_LOGO.ang, pi / 2 + BTC_LOGO.ang, 28)
        drawList:PathStroke(col, false, BTC_LOGO.T * k * SCALE)
    end
end

local animValues = {}
local frameDelta = 1 / 60
local inputLocked = false
local function animate(id, target, speed)
    local v = animValues[id]
    if v == nil then v = target end
    v = v + (target - v) * min(1, frameDelta * (speed or 14))
    animValues[id] = v
    return v
end

local function hitArea(id, x, y, w, h)
    imgui.SetCursorScreenPos(toScreen(x, y))
    local clicked = imgui.InvisibleButton(id, poolVec(max(1, w * SCALE), max(1, h * SCALE)))
    return clicked and not inputLocked, imgui.IsItemHovered(), imgui.IsItemActive()
end

local function drawCard(x, y, w, h)
    gradientRoundRect(x, y, w, h, Palette.card0, Palette.card1, 1, 'v', 12)
    strokeRoundRect(x, y, w, h, rgba(Palette.cardLine), 12)
end

local function drawCardHeader(x, y, w, title, tx)
    drawText(Font.bold16, title, tx, y + 33.2, rgba(Palette.white))
    drawHLine(x + 17, x + w - 15, y + 51, rgba(Palette.divider))
end

local function drawStatusPill(x, y, w, h, label, on, outlined)
    local hex = on and Palette.green or 0x6B7488
    if outlined then
        fillRoundRect(x, y, w, h, rgba(on and 0x0A1B1B or 0x10141C), 7)
        strokeRoundRect(x, y, w, h, rgba(hex, on and 0.28 or 0.35), 7)
    else
        fillRoundRect(x, y, w, h, rgba(on and 0x0A2A25 or 0x131821), 7)
        strokeRoundRect(x, y, w, h, rgba(hex, 0.10), 7)
    end
    local sx = x + (w - (15.6 + textWidth(Font.bold11, label))) / 2 + 1.2
    local dx, dy = sx + 3.8, y + h / 2
    if on then glowCircle(dx, dy, 3.8, hex, 0.45, 5) end
    fillCircle(dx, dy, 3.8, rgba(hex))
    drawText(Font.bold11, label, sx + 15.6, y + h / 2 + 4.0, rgba(hex))
end

local function drawToggle(id, x, y, value)
    local w, h = 40, 23
    local clicked, hov = hitArea(id, x, y, w, h)
    if clicked then value = not value; saveConfig() end
    local t = animate(id, value and 1 or 0, 16)
    local hv = animate(id .. 'h', hov and 1 or 0)
    fillRoundRect(x, y, w, h, rgba(mixColor(mixColor(0x1A2131, 0x0F7A5C, t), 0x2A3345, hv * 0.25 * (1 - t))), h / 2)
    strokeRoundRect(x, y, w, h, rgba(mixColor(0x252D3D, 0x1AA37F, t), 0.9), h / 2)
    local kx = x + 11.5 + (w - 23) * t
    if t > 0.01 then glowCircle(kx, y + h / 2, 8.3, 0xFFFFFF, 0.10 * t, 3) end
    fillCircle(kx, y + h / 2, 8.3, rgba(mixColor(0x6F83A6, 0xEAF8FB, t)))
    return value
end

local function drawSmallButton(id, x, y, w, h, plus, iconName)
    local clicked, hov, act = hitArea(id, x, y, w, h)
    local hv = animate(id, hov and 1 or 0)
    fillRoundRect(x, y, w, h, rgba(act and 0x121A26 or mixColor(0x162130, 0x1E2B3D, hv)), 8)
    strokeRoundRect(x, y, w, h, rgba(mixColor(0x222D3B, 0x33445A, hv)), 8)
    local cx, cy = x + w / 2, y + h / 2
    local col = rgba(mixColor(0xB9C6D6, 0xFFFFFF, hv))
    if not drawIcon(iconName or (plus and 'plus' or 'minus'), 18, cx, cy, col) then
        drawLine(cx - 7, cy, cx + 7, cy, col, 2.2)
        if plus then drawLine(cx, cy - 7, cx, cy + 7, col, 2.2) end
    end
    return clicked
end

local editState = { id = nil, buf = nil, focus = false }
local drawEditBox
do
local COL_CLEAR = imgui.ImVec4(0, 0, 0, 0)
local COL_TEXT = imgui.ImVec4(0.95, 0.96, 0.98, 1)
local COL_SELECTION = imgui.ImVec4(0, 0, 0, 0)

function drawEditBox(id, x, y, w, h, display, raw, onCommit, font)
    font = font or Font.semi13
    local editing = editState.id == id
    local hov = false
    if not editing then
        local clicked
        clicked, hov = hitArea(id, x, y, w, h)
        if clicked then
            editState.id, editState.focus, editing = id, true, true
            editState.buf = imgui.new.char[64](toUtf8(raw))
            editState.initial = toUtf8(raw)
        end
    end
    local hv = animate(id, (hov or editing) and 1 or 0)
    fillRoundRect(x, y, w, h, rgba(editing and 0x0B1320 or 0x0A0E18), 8)
    strokeRoundRect(x, y, w, h, rgba(editing and 0x2EB89A or mixColor(0x1D2431, 0x3A4A60, hv)), 8)
    if not editing then
        drawText(font, display, x + w / 2, y + h / 2 + 4.85, rgba(Palette.white), 'c')
        return
    end
    local fp = font.f
    if fp then imgui.PushFont(fp) end
    local curText = ffi.string(editState.buf)
    local tw = imgui.CalcTextSize(curText).x
    if curText ~= '' and curText == editState.initial then
        local twd = tw / SCALE
        fillRoundRect(x + (w - twd) / 2 - 6, y + (h - 22) / 2, twd + 12, 22, rgba(0x2EB89A, 0.30), 6)
    end
    imgui.PushStyleColor(imgui.Col.FrameBg, COL_CLEAR)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, COL_CLEAR)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, COL_CLEAR)
    imgui.PushStyleColor(imgui.Col.Text, COL_TEXT)
    imgui.PushStyleColor(imgui.Col.TextSelectedBg, COL_SELECTION)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding,
        poolVec(max(8 * SCALE, (w * SCALE - tw) / 2), (h * SCALE - imgui.GetFontSize()) / 2))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)
    imgui.SetCursorScreenPos(toScreen(x, y))
    imgui.PushItemWidth(w * SCALE)
    if editState.focus then
        imgui.SetKeyboardFocusHere(0)
        editState.focus = false
    end
    local enter = imgui.InputText('##in' .. id, editState.buf, 64,
        imgui.InputTextFlags.EnterReturnsTrue + imgui.InputTextFlags.AutoSelectAll)
    local done = enter or imgui.IsItemDeactivated()
    imgui.PopItemWidth()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(5)
    if fp then imgui.PopFont() end
    if done then
        editState.id = nil
        onCommit(u8:decode(ffi.string(editState.buf)))
    end
end
end

local function numberCommit(minV, maxV, set)
    return function(v)
        local n = tonumber((v:gsub(',', '.'):match('[%d%.]+') or ''))
        if n then set(clamp(floor(n + 0.5), minV, maxV)); saveConfig() end
    end
end

local function drawSlider(id, x, y, w, value, minV, maxV, step)
    local kr = 13
    local _, hov, act = hitArea(id, x - kr, y - 18, w + kr * 2, 36)
    local io = imgui.GetIO()
    if act then
        local t = clamp((io.MousePos.x - originX - (x + kr) * SCALE) / ((w - kr * 2) * SCALE), 0, 1)
        value = floor((minV + t * (maxV - minV)) / step + 0.5) * step
        saveConfig()
    elseif hov and io.MouseWheel ~= 0 then
        value = clamp(value + (io.MouseWheel > 0 and step or -step), minV, maxV)
        saveConfig()
    end
    local kx = x + kr + (w - kr * 2) * (value - minV) / (maxV - minV)
    fillRoundRect(x, y - 7, w, 14, rgba(0x1B2434), 7)
    if kx - x > 1 then
        glowRoundRect(x, y - 7, kx - x, 14, 7, 0x1EA8FF, 0.22, 6)
        gradientRoundRect(x, y - 7, kx - x, 14, 0x149EFF, 0x24C8FF, 1, 'h', 7)
    end
    local hv = animate(id, (hov or act) and 1 or 0)
    glowCircle(kx, y, kr, 0x2EC0FF, 0.35 + hv * 0.2, 9)
    fillCircle(kx, y, kr, rgba(0xC4EAFF))
    fillCircle(kx, y, kr - 3.2, rgba(0xA9E2FF))
    return value
end

local function drawBigButton(id, x, y, w, h, c0, c1, tTR, tBL, border, glowHex)
    local clicked, hov, act = hitArea(id, x, y, w, h)
    local hv = animate(id, hov and 1 or 0)
    glowRoundRect(x, y, w, h, 10, glowHex, 0.16 + hv * 0.14, 10)
    gradientCornerRect(x, y, w, h, 10, mixColor(c0, 0xFFFFFF, hv * 0.07), mixColor(c1, 0xFFFFFF, hv * 0.05),
        act and 0.85 or 1, tTR, tBL)
    strokeRoundRect(x, y, w, h, rgba(border, 0.75 + hv * 0.25), 10)
    return clicked, hv
end

local function drawFooter()
    if not (state.manualOpen and not isListOpen()) then
        drawText(Font.medium11, 'Больше битков — больше возможностей', 921.5, 530.5, rgba(Palette.dim), 'r')
        drawHLine(938.5, 961.5, 526, rgba(0x262C38))
        return
    end
    fillRoundRect(159, 507, 802.5, 29, rgba(0x1E1707), 8)
    strokeRoundRect(159, 507, 802.5, 29, rgba(Palette.gold, 0.40), 8)
    drawIcon('warn', 18, 179, 521.5, rgba(Palette.gold))
    drawText(Font.medium125, 'Основной функционал работает только в подвале майнинга — подойдите к видеокартам и откройте их' .. (IS_MOBILE and '.' or ' (Alt).'),
        197, 525.7, rgba(0xF3D9A4))
end

local function closeWindow()
    if sampIsDialogActive() and isCardListId(sampGetCurrentDialogId()) then
        state.hiddenList = false
        sampCloseCurrentDialogWithButton(0)
    else
        closeHiddenList()
    end
    if state.manualOpen then
        state.manualOpen = false
        setCursor(false)
    end
    state.window[0] = false
end

local function drawHeader()
    gradientRoundRect(0, 0, WIN_W, 81, 0x0C121C, 0x080B12, 1, 'h', 14, 14, 0, 0)
    drawHLine(0, WIN_W, 81, rgba(Palette.headLine))

    local x1, y1, x2, y2, n = 94, 1, 130, 64, 12
    for i = 0, n - 1 do
        local t0, t1 = i / n, (i + 1) / n
        local a = sin(pi * (t0 + t1) / 2)
        local ax, ay = x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0
        local bx, by = x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1
        drawLine(ax, ay, bx, by, rgba(Palette.green, 0.10 * a), 7)
        drawLine(ax, ay, bx, by, rgba(Palette.green, 0.18 * a), 3.5)
        drawLine(ax, ay, bx, by, rgba(0x3FF5C8, 0.85 * a), 1.3)
    end
    drawLine(660, 1, 612.5, 81, rgba(0xFFFFFF, 0.045), 1)
    drawLine(677.5, 1, 630, 81, rgba(0xFFFFFF, 0.045), 1)

    glowRoundRect(20, 11, 67, 69, 13, Palette.green, 0.10, 9)
    gradientRoundRect(20, 11, 67, 69, 0x0B302D, 0x052220, 1, 'v', 13)
    strokeRoundRect(20, 11, 67, 69, rgba(0x1E6B5E, 0.55), 13)
    drawCrossedPickaxes(54.5, 45, 40, rgba(0x19E6B4))

    drawText(Font.title, 'MINING ', 136, 42.5, rgba(Palette.white))
    drawText(Font.title, 'TOOLS', 136 + textWidth(Font.title, 'MINING '), 42.5, rgba(Palette.green))
    drawText(Font.subtitle, 'Управление майнингом и охлаждением', 136.5, 64, rgba(Palette.muted))

    local on = cfg.active
    local pClicked, pHov = hitArea('##power', 720, 22, 112, 32)
    local pv = animate('power', pHov and 1 or 0)
    if pv > 0.01 then fillRoundRect(720, 22, 112, 32, rgba(0xFFFFFF, 0.05 * pv), 8) end
    if pClicked then
        cfg.active = not cfg.active
        on = cfg.active
        notify('Mining Tools', on and 'Скрипт включен.' or 'Скрипт отключён.', on and 'ok' or 'warn')
    end
    local sc = on and 0x1EE8B4 or 0x6B7488
    if on then glowCircle(732, 37.5, 4.5, sc, 0.5, 6) end
    fillCircle(732, 37.5, 4.5, rgba(sc))
    drawText(Font.bold12, on and 'АКТИВНО' or 'ПАУЗА', 746.5, 42.3, rgba(on and 0x3DDBB0 or Palette.muted))

    fillRoundRect(844, 24, 65, 27.5, rgba(0x0B0D16), 8)
    strokeRoundRect(844, 24, 65, 27.5, rgba(0x1F2430), 8)
    drawText(Font.medium13, 'v' .. VERSION, 876.5, 42.2, rgba(0x9AA3B5), 'c')

    local clicked, hov = hitArea('##close', 929, 15, 32, 32)
    local hv = animate('close', hov and 1 or 0)
    if hv > 0.01 then fillRoundRect(929, 15, 32, 32, rgba(Palette.red, 0.12 * hv), 8) end
    drawIcon('xmark', 32, 944.8, 31, rgba(mixColor(Palette.red, 0xFF8A80, hv)))
    if clicked then closeWindow() end
end

local function drawNavItem(id, y, label, active, gear)
    local x, w, h = 4, 135, 46
    local clicked, hov = hitArea(id, x, y, w, h)
    local hv = animate(id, hov and 1 or 0)
    if active then
        glowRoundRect(x, y, w, h, 9, Palette.green, 0.06, 6)
        gradientRoundRect(x, y, w, h, 0x074139, 0x06302F, 1, 'h', 9)
        strokeRoundRect(x, y, w, h, rgba(0x1B6E5E, 0.75), 9)
        glowRoundRect(x, y + 5, 3, h - 10, 1.5, 0x2EE6C0, 0.45, 4)
        fillRoundRect(x, y + 5, 3, h - 10, rgba(0x2EE6C0), 1.5)
    elseif hv > 0.01 then
        fillRoundRect(x, y, w, h, rgba(0x121824, hv), 9)
    end
    local ic = active and rgba(0x21E3B2) or rgba(mixColor(0x7F8FB3, 0xB4C2DD, hv))
    if gear then drawIcon(gear == true and 'gear' or gear, 21, x + 28.5, y + h / 2, ic) else drawCrossedPickaxes(x + 27, y + h / 2, 21, ic) end
    drawText(active and Font.semi125 or Font.medium125, label, 53, y + h / 2 + 5.3,
        active and rgba(Palette.white) or rgba(mixColor(0x8D95A8, 0xD5DCE8, hv)))
    return clicked
end

local TG_URL = 'https://t.me/edward_scripts'

local function openUrl(url)
    if IS_MOBILE then
        pcall(function() imgui.SetClipboardText(url) end)
        notify('Telegram', { 'Ссылка скопирована:', url }, 'info')
        pcall(os.execute, 'am start -a android.intent.action.VIEW -d "' .. url .. '"')
        return
    end
    pcall(ffi.cdef, 'void* ShellExecuteA(void*, const char*, const char*, const char*, const char*, int);')
    local ok = pcall(function() ffi.load('shell32').ShellExecuteA(nil, 'open', url, nil, nil, 1) end)
    if not ok then os.execute('start "" "' .. url .. '"') end
end

local labelA, labelB = u8("By "), u8("Edward")
local COL_BY, COL_EDWARD = 0xFF4B4B, 0x1FE4F0

local DEMO = { btc = 47, coolant = 68 }

local function isDemo()
    return state.manualOpen and not isListOpen()
end

local MINING_RATES = { 0.03, 0.06, 0.09, 0.12, 0.15, 0.18, 0.21, 0.24, 0.27, 0.30 }
local CARD_CAPACITY = 9.0
local RTX_BONUS = 1.25

local DEMO_CARDS
local function demoCards()
    if DEMO_CARDS then return DEMO_CARDS end
    local levels = { 3, 5, 5, 7, 2, 9, 4, 6, 8, 10, 1, 5 }
    local profits = { 2.4, 5.1, 7.8, 0.6, 8.9, 3.3, 4.7, 1.2, 6.4, 0.2, 9.0, 5.5 }
    DEMO_CARDS = {}
    for i = 1, 12 do
        DEMO_CARDS[i] = { shelf = i, on = i ~= 5 and i ~= 9, level = levels[i], profit = profits[i] }
    end
    return DEMO_CARDS
end

local function cardRate(level)
    return (MINING_RATES[level] or 0) * (cfg.rtx4090 and RTX_BONUS or 1)
end

local function getAnalytics()
    local src = {}
    if isDemo() then
        src = demoCards()
    else
        for i, c in ipairs(state.cards) do
            src[i] = { shelf = c.shelf or (c.index + 1), on = c.working, level = c.level or 0, profit = c.profit or 0 }
        end
    end
    local a = { list = {}, balance = 0, speed = 0, daily = 0, working = 0, real = #src > 0 }
    local best
    for i, c in ipairs(src) do
        local item = { shelf = c.shelf, on = c.on, level = c.level, profit = c.profit, rate = cardRate(c.level) }
        local left = math.max(0, CARD_CAPACITY - item.profit)
        a.balance = a.balance + item.profit
        if item.profit >= CARD_CAPACITY then
            item.days = 0
        elseif item.on and item.rate > 0 then
            item.days = math.ceil(left / item.rate - 1e-9)
        end
        if item.on and item.rate > 0 then
            a.working = a.working + 1
            a.speed = a.speed + item.rate
        end
        if item.days and (not best or item.days < best) then
            best = item.days
            a.nextShelf = item.shelf
        end
        a.list[i] = item
    end
    a.daily = a.speed * 24
    a.nextDays = best
    return a
end

local function farmStats()
    local st = { cells = {}, total = 0, working = 0, ready = 0, coolant = 0, real = true }
    if isDemo() then
        for i = 1, 12 do
            st.cells[i] = { on = i ~= 5 and i ~= 9, btc = i % 3 == 0 }
        end
        st.coolant = DEMO.coolant
    else
        for i, card in ipairs(state.cards) do
            st.cells[i] = { on = card.working, btc = card.btc >= 1 }
        end
        st.coolant = #state.cards > 0 and state.minCoolant or 0
        st.real = #state.cards > 0
    end
    st.total = #st.cells
    for _, c in ipairs(st.cells) do
        if c.on then st.working = st.working + 1 end
        if c.btc then st.ready = st.ready + 1 end
    end
    return st
end

local function drawFarmRow(label, value, y, valueColor)
    drawText(Font.medium11, label, 26, y, rgba(0x7D879B))
    drawText(Font.bold12, value, 118, y, rgba(valueColor or Palette.white), 'r')
end

local function drawFarmPanel()
    local st = farmStats()
    local px, py, pw = 12, 262, 120
    local cell, gap, cols = 12, 4, 6
    local rows = st.real and max(1, math.ceil(min(st.total, 24) / cols)) or 2
    local gx, gy = 26, py + 60
    local ay = gy + rows * (cell + gap) - gap + 20
    local ph = ay + 24 + 5 + 14 - py

    gradientRoundRect(px, py, pw, ph, 0x0D131E, 0x090D16, 1, 'v', 10)
    strokeRoundRect(px, py, pw, ph, rgba(0x1A2230), 10)

    local pulse = 0.5 + 0.5 * sin(os.clock() * 3)
    glowCircle(30, py + 15, 3.2, Palette.green, 0.35 * pulse, 5)
    fillCircle(30, py + 15, 3.2, rgba(Palette.green, 0.6 + 0.4 * pulse))
    drawText(Font.bold11, 'ФЕРМА', 40, py + 19, rgba(0xB7C0D0))
    drawHLine(px + 10, px + pw - 10, py + 28, rgba(Palette.divider))

    drawFarmRow('Работают', st.real and (st.working .. ' из ' .. st.total) or '—', py + 48, st.real and (st.working == st.total and 0x3DDBB0 or 0xFFA53D) or Palette.muted)

    if st.real then
        for i = 1, min(st.total, 24) do
            local c = st.cells[i]
            local cx = gx + ((i - 1) % cols) * (cell + gap)
            local cy = gy + floor((i - 1) / cols) * (cell + gap)
            if c.btc then
                local al = 0.7 + 0.3 * pulse
                glowRoundRect(cx, cy, cell, cell, 3, Palette.orange, 0.18 * pulse, 3)
                fillRoundRect(cx, cy, cell, cell, rgba(0xF7931A, al), 3)
            elseif c.on then
                fillRoundRect(cx, cy, cell, cell, rgba(0x1EE8B4, 0.85), 3)
            else
                fillRoundRect(cx, cy, cell, cell, rgba(0x1E2636), 3)
                strokeRoundRect(cx, cy, cell, cell, rgba(0x2A3448), 3)
            end
        end
    else
        drawText(Font.medium11, 'откройте видеокарты', 72, gy + 12, rgba(Palette.dim), 'c')
        drawText(Font.medium11, 'в подвале майнинга', 72, gy + 28, rgba(Palette.dim), 'c')
    end

    drawFarmRow('К снятию', st.real and tostring(st.ready) or '—', ay, st.ready > 0 and 0xFFA53D or Palette.muted)
    drawFarmRow('Жидкость', st.real and (floor(st.coolant) .. '%') or '—', ay + 24, 0x3BB8FF)
    fillRoundRect(26, ay + 31, 92, 5, rgba(0x141B28), 2.5)
    local pct = st.real and clamp(st.coolant / 100, 0, 1) or 0
    if pct > 0.02 then
        local vs = drawList.VtxBuffer.Size
        fillRoundRect(26, ay + 31, 92 * pct, 5, rgba(0x2EB8FF), 2.5)
        applyGradient(vs, 26, ay + 31, 118, ay + 31, 0x1A6FE0, 0x3BD0FF)
    end
end

local function drawTgButton(x, y, w, h)
    local clicked, hov, act = hitArea('##tgLink', x, y, w, h)
    local hv = animate('##tgLink', hov and 1 or 0)
    glowRoundRect(x, y, w, h, 10, 0x2AABEE, 0.05 + hv * 0.12, 8)
    fillRoundRect(x, y, w, h, rgba(act and 0x0C1626 or mixColor(0x0B1320, 0x10203A, hv)), 10)
    strokeRoundRect(x, y, w, h, rgba(mixColor(0x1C2A3E, 0x2AABEE, hv * 0.85)), 10)

    local sq = h - 14
    local ix, iy = x + 7, y + 7
    gradientRoundRect(ix, iy, sq, sq, 0x37B9F5, 0x1B7FCB, 1, 'v', 8)
    local cx, cy = ix + sq / 2, iy + sq / 2
    if not drawIcon('plane', 18, cx - 0.5, cy + 0.5, rgba(0xFFFFFF)) then
        drawList:AddTriangleFilled(toScreen(cx - 8, cy), toScreen(cx + 8, cy - 7), toScreen(cx + 3, cy + 8), rgba(0xFFFFFF))
    end
    local tx = ix + sq + 9
    drawText(Font.bold13, 'Telegram', tx, y + h / 2 + 4.6, rgba(mixColor(0xD5DCE8, 0xFFFFFF, hv)))
    if clicked then openUrl(TG_URL) end
end

local function drawSidebarFooterImpl()
    drawTgButton(12, 464, 120, 46)

    local base = 'Mining Tools '
    local font = Font.medium125
    local total = textWidth(font, base) + textWidth(font, labelA) + textWidth(font, labelB)
    if total > 120 then font = Font.medium11; total = textWidth(font, base) + textWidth(font, labelA) + textWidth(font, labelB) end
    local x, y = 14, 530
    drawText(font, base, x, y, rgba(0x6F7890))
    x = x + textWidth(font, base)
    drawText(font, labelA, x, y, rgba(COL_BY))
    x = x + textWidth(font, labelA)
    drawText(font, labelB, x, y, rgba(COL_EDWARD))
end

local function drawSidebar()
    gradientRoundRect(0, 82, 144, 462, 0x090D16, 0x080B12, 1, 'v', 10, 10, 10, 14)
    strokeRoundRect(0, 82, 144, 462, rgba(Palette.sideLine), 10, 10, 10, 14)
    if drawNavItem('##nav1', 101, 'Главная', cfg.page == 1, false) then cfg.page = 1; saveConfig() end
    if drawNavItem('##nav3', 153, 'Аналитика', cfg.page == 3, 'chart') then cfg.page = 3; saveConfig() end
    if drawNavItem('##nav2', 205, 'Настройки', cfg.page == 2, true) then cfg.page = 2; saveConfig() end
    drawSidebarFooterImpl()
end

local function fadeVertices(vs, a)
    if a >= 0.999 then return end
    local data = drawList.VtxBuffer.Data
    for i = vs, drawList.VtxBuffer.Size - 1 do
        local c = data[i].col
        data[i].col = c % 16777216 + floor(floor(c / 16777216) * a + 0.5) * 16777216
    end
end

local HINTS = {
    threshold = {
        title = 'Заливка жидкости', icon = 'droplet', col = 0x2EB8FF,
        blocks = {
            { kind = 'p', lines = { 'Одна охлаждайка даёт +50% жидкости,', 'две охлаждайки — +100%.' } },
            { kind = 'ex', col = 0x2EB8FF, title = 'Что заливается',
              lines = { 'Карты, где жидкости меньше 50%', 'Больше 50% — остаются как есть' } },
            { kind = 'p', lines = { 'Кнопка «ЗАЛИТЬ» льёт столько охлаждаек,', 'сколько выбрано: 1 или 2.' } },
            { kind = 'ex', col = 0xF5A623, title = 'Авто режим',
              lines = { 'Заливает по тому же правилу только', 'выключенные видеокарты. Работающие не трогает.' } },
        },
    },
    auto = {
        title = 'Авто режим', icon = 'bolt', col = 0xF5A623,
        blocks = {
            { kind = 'p', lines = { 'Срабатывает сам при открытии диалога', 'с видеокартами и делает только нужное:' } },
            { kind = 'steps', items = {
                { 'Снимает BTC с карт, где он есть (хоть 1)' },
                { 'Включает выключенные видеокарты' },
                { 'Заливает жидкость в выключенные карты,', 'если её меньше 50%' },
            } },
            { kind = 'ex', col = 0x2EE6B0, title = 'Пример 1: по 9 BTC, карты выключены',
              lines = { 'Снимет BTC, включит карты, зальёт жидкость' } },
            { kind = 'ex', col = 0x2EB8FF, title = 'Пример 2: 2-4 BTC, карты работают',
              lines = { 'Только снимет BTC. Не включит и не зальёт' } },
        },
    },
}
local currentHint, shownHint = nil, nil

local function isMouseOver(x, y, w, h)
    if not imgui.IsWindowHovered() then return false end
    local mp = imgui.GetIO().MousePos
    local px, py = originX + x * SCALE, originY + y * SCALE
    return mp.x >= px and mp.x <= px + w * SCALE and mp.y >= py and mp.y <= py + h * SCALE
end

local function drawInfoBadge(cx, cy, hot)
    glowCircle(cx, cy, 8, Palette.ice, hot and 0.25 or 0.08, 4)
    fillCircle(cx, cy, 8, rgba(hot and 0x1E3A55 or 0x162130))
    drawText(Font.bold11, '?', cx, cy + 4, rgba(hot and 0xFFFFFF or 0x8FB4D6), 'c')
end

local HINT_LINE_H = 19

local function hintWidth(t)
    local need = 0
    for _, b in ipairs(t.blocks) do
        if b.kind == 'p' then
            for _, s in ipairs(b.lines) do need = max(need, textWidth(Font.medium13, s)) end
        elseif b.kind == 'ex' then
            need = max(need, textWidth(Font.bold12, b.title) + 34)
            for _, s in ipairs(b.lines) do need = max(need, textWidth(Font.medium13, s) + 34) end
        elseif b.kind == 'steps' then
            for _, it in ipairs(b.items) do
                for _, s in ipairs(it) do need = max(need, textWidth(Font.medium13, s) + 32) end
            end
        end
    end
    return need
end

local function hintBody(t, x, y, w, draw)
    local cy = y
    for _, b in ipairs(t.blocks) do
        if b.kind == 'p' then
            if draw then
                for i, s in ipairs(b.lines) do drawText(Font.medium13, s, x, cy + 14 + (i - 1) * HINT_LINE_H, rgba(Palette.text)) end
            end
            cy = cy + #b.lines * HINT_LINE_H + 9
        elseif b.kind == 'ex' then
            local h = 35 + #b.lines * HINT_LINE_H
            if draw then
                fillRoundRect(x, cy, w, h, rgba(b.col, 0.09), 9)
                strokeRoundRect(x, cy, w, h, rgba(b.col, 0.26), 9)
                fillRoundRect(x + 8, cy + 9, 3, h - 18, rgba(b.col), 1.5)
                drawText(Font.bold12, b.title, x + 22, cy + 21, rgba(b.col))
                for i, s in ipairs(b.lines) do drawText(Font.medium13, s, x + 22, cy + 25 + i * HINT_LINE_H, rgba(Palette.text)) end
            end
            cy = cy + h + 10
        elseif b.kind == 'steps' then
            for n, it in ipairs(b.items) do
                if draw then
                    fillCircle(x + 10, cy + 9, 10, rgba(t.col, 0.18))
                    drawText(Font.bold11, tostring(n), x + 10, cy + 13, rgba(t.col), 'c')
                    for i, s in ipairs(it) do drawText(Font.medium13, s, x + 32, cy + 14 + (i - 1) * HINT_LINE_H, rgba(Palette.text)) end
                end
                cy = cy + #it * HINT_LINE_H + 7
            end
            cy = cy + 4
        end
    end
    return cy - y
end

local function drawHint(t, ax, ay, above, a)
    local pad = 16
    local w = clamp(hintWidth(t) + pad * 2, 340, 500)
    local h = 68 + hintBody(t, 0, 0, w - pad * 2, false) + 4
    local x = clamp(ax, 12, WIN_W - w - 12)
    local y = clamp(above and (ay - h - 8) or ay, 90, WIN_H - h - 12) + (1 - a) * 8

    local vs = drawList.VtxBuffer.Size
    glowRoundRect(x, y, w, h, 14, t.col, 0.12, 10)
    gradientRoundRect(x, y, w, h, 0x0F1520, 0x090D15, 0.98, 'v', 14)
    strokeRoundRect(x, y, w, h, rgba(t.col, 0.38), 14)

    local cx, cy = x + pad + 14, y + 30
    glowCircle(cx, cy, 14, t.col, 0.18, 5)
    fillCircle(cx, cy, 14, rgba(t.col, 0.16))
    if not drawIcon(t.icon, 18, cx, cy, rgba(t.col)) then drawText(Font.bold13, '?', cx, cy + 5, rgba(t.col), 'c') end
    drawText(Font.bold16, t.title, x + pad + 38, y + 36, rgba(Palette.white))
    drawHLine(x + pad, x + w - pad, y + 56, rgba(Palette.divider))
    hintBody(t, x + pad, y + 68, w - pad * 2, true)
    fadeVertices(vs, a)
end

local function drawMining()
    drawCard(159, 96, 365, 262)
    drawPickaxe(187.5, 124, 24, rgba(0x22E3B0), 'single')
    drawCardHeader(159, 96, 365, 'МАЙНИНГ', 215)
    drawStatusPill(419, 111, 90, 25, cfg.active and 'АКТИВЕН' or 'ПАУЗА', cfg.active, false)

    glowCircle(219, 204.5, 33.5, Palette.orange, 0.10, 9)
    local vs = drawList.VtxBuffer.Size
    fillCircle(219, 204.5, 33.5, rgba(0x2A1D0F))
    applyGradient(vs, 195, 175, 243, 235, 0x33220F, 0x1B130A)
    drawList:AddCircle(toScreen(219, 204.5), 33 * SCALE, rgba(0xF7931A, 0.45), 56, 1.2 * SCALE)
    drawBitcoinLogo(219.5, 204.5, 1.05, rgba(0xFFA53D))

    drawText(Font.medium145, 'Битки (BTC)', 275.5, 181, rgba(Palette.text))
    local curBtc = isDemo() and DEMO.btc or state.earnings.btc
    local withdrawnBtc = state.withdrawn.btc > 0 and state.withdrawn.btc
        or (state.beforeWithdraw and max(0, state.beforeWithdraw - state.earnings.btc)) or 0
    local blockLeft = 509
    if withdrawnBtc > 0 and not isDemo() then
        local numStr = fmtNum(withdrawnBtc)
        local rubStr = '\226\137\136 ' .. fmtNum(withdrawnBtc * cfg.rate) .. u8(' руб')
        local blockW = max(textWidth(Font.number30, numStr), textWidth(Font.medium14, rubStr), textWidth(Font.medium145, 'Снято'))
        blockLeft = 509 - blockW
        drawList:AddLine(toScreen(blockLeft - 16, 178), toScreen(blockLeft - 16, 252), rgba(Palette.divider), 1 * SCALE)
        drawText(Font.medium145, 'Снято', 509, 181, rgba(Palette.text), 'r')
        drawText(Font.number30, numStr, 509, 215.8, rgba(0x2EE6B0), 'r')
        drawText(Font.medium14, rubStr, 509, 243, rgba(0x2EE6B0, 0.6), 'r')
    end
    drawText(Font.number30, fmtNum(curBtc), 274, 215.8, rgba(Palette.white))
    if state.beforeWithdraw and not isDemo() then
        local nx = 274 + textWidth(Font.number30, fmtNum(state.earnings.btc)) + 14
        local was = 'было ' .. fmtNum(state.beforeWithdraw)
        if nx + textWidth(Font.medium14, was) < blockLeft - 26 then
            drawText(Font.medium14, was, nx, 214.8, rgba(0x4E5769))
        end
    end
    drawText(Font.medium14, '\226\137\136 ' .. fmtNum((isDemo() and DEMO.btc or state.earnings.btc) * cfg.rate) .. u8(' руб'), 273.5, 243, rgba(0x7F889B))
    drawHLine(176, 509, 266, rgba(Palette.divider))

    local clicked, hv = drawBigButton('##withdraw', 175, 282, 334, 61.5, 0x04775D, 0x033848, 0.62, 0.36, 0x2A8C79, 0x10C090)
    drawIcon('database', 24, 227, 313.5, rgba(mixColor(0x7AF0C8, 0xB0FFE4, hv)))
    drawText(Font.bold16, 'СНЯТЬ КРИПТУ', 258, 319.6, rgba(0xEAFFF7))
    drawIcon('chevron', 18, 478 + hv * 2, 313.5, rgba(0x7FE8D4))
    if clicked then Actions.withdraw() end
end

local function drawCooling()
    drawCard(539, 96, 422, 262)
    drawIcon('snowflake', 28, 570.5, 123.5, rgba(Palette.ice))
    drawCardHeader(539, 96, 422, 'ОХЛАЖДЕНИЕ', 599)
    local minCoolant = isDemo() and DEMO.coolant or state.minCoolant
    local on = minCoolant >= cfg.useCoolantPercent
    drawStatusPill(844, 111, 101, 25, on and 'В НОРМЕ' or 'ЗАЛИВКА', on, true)

    glowCircle(577.5, 180, 18, 0x1A6FB8, 0.22, 7)
    fillCircle(577.5, 180, 18, rgba(0x0B1A2B))
    drawIcon('droplet', 24, 577.5, 180, rgba(0x3BB5FF))

    drawText(Font.medium14, 'Заливка жидкости', 605.5, 182, rgba(0xA9B2C3))
    local thrHover = isMouseOver(559, 163, 235, 74)
    drawInfoBadge(605.5 + textWidth(Font.medium14, 'Заливка жидкости') + 14, 177, thrHover)
    if thrHover then currentHint = { HINTS.threshold, 559, 244 } end
    local portions = cfg.coolantPortions == 2 and 2 or 1
    drawText(Font.number30, '+' .. (portions * 50) .. '%', 604.5, 226.3, rgba(Palette.white))

    fillRoundRect(810, 179, 130, 48.5, rgba(0x0A1321), 8)
    strokeRoundRect(810, 179, 130, 48.5, rgba(0x1A2536), 8)
    drawText(Font.regular12, 'Текущий уровень', 821, 198, rgba(0x7D8A9C))
    drawText(Font.bold13, floor(minCoolant) .. '%', 820.5, 218, rgba(0x3BB8FF))

    for i = 1, 2 do
        local sel = portions == i
        local bx = 565 + (i - 1) * 192.5
        local pressed
        if sel then
            pressed = drawBigButton('##fp' .. i, bx, 250, 180, 46, 0x0875CC, 0x00469A, 0.52, 0.48, 0x2B86D6, 0x1A6FE0)
        else
            pressed = drawBigButton('##fp' .. i, bx, 250, 180, 46, 0x141B29, 0x0D121C, 0.52, 0.48, 0x2A3447, 0x3A4A66)
        end
        drawText(Font.bold13, i == 1 and '1 ОХЛАЖДАЙКА' or '2 ОХЛАЖДАЙКИ', bx + 90, 268, rgba(sel and 0xFFFFFF or Palette.text), 'c')
        drawText(Font.medium11, '+' .. (i * 50) .. '% жидкости', bx + 90, 283, rgba(sel and 0xCFE6FF or Palette.muted), 'c')
        if pressed and not sel then cfg.coolantPortions = i; saveConfig() end
    end

    local clicked = drawBigButton('##fillbtn', 565, 306, 372.5, 40, 0x0875CC, 0x00469A, 0.52, 0.48, 0x2B86D6, 0x1A6FE0)
    local label = portions == 1 and 'ЗАЛИТЬ 1 ОХЛАЖДАЙКУ' or 'ЗАЛИТЬ 2 ОХЛАЖДАЙКИ'
    local total = 31 + textWidth(Font.bold135, label)
    local startX = 565 + (372.5 - total) / 2
    drawIcon('droplet', 21, startX + 10.5, 326, rgba(0xF4FAFF))
    drawText(Font.bold135, label, startX + 31, 331, rgba(0xFFFFFF))
    if clicked then Actions.fill() end
end

local function drawQuick()
    drawCard(159, 372, 802.5, 128)
    drawIcon('bolt', 21, 184.5, 396, rgba(0xD4E6FF))
    drawText(Font.bold14, 'БЫСТРЫЕ ДЕЙСТВИЯ', 207.5, 400.4, rgba(Palette.white))

    local y, h = 421, 64

    local tx1, w1 = 172, 490
    fillRoundRect(tx1, y, w1, h, rgba(Palette.tile), 10)
    strokeRoundRect(tx1, y, w1, h, rgba(Palette.tileLine), 10)
    glowCircle(tx1 + 33, y + 32.5, 22.5, Palette.green, 0.10, 6)
    fillCircle(tx1 + 33, y + 32.5, 22.5, rgba(0x0B3A33))
    drawPickaxe(tx1 + 33.5, y + 32.5, 25, rgba(0x2EF0C4), 'single')
    local cardsTotal, cardsOn, stopped = 0, 0, {}
    if isDemo() then
        cardsTotal, cardsOn, stopped = 12, 10, { 5, 9 }
    else
        cardsTotal = #state.cards
        for _, card in ipairs(state.cards) do
            if card.working then
                cardsOn = cardsOn + 1
            else
                stopped[#stopped + 1] = card.shelf or (card.index + 1)
            end
        end
    end
    if cardsTotal > 0 then
        local allOn = cardsOn == cardsTotal
        drawText(Font.bold13, 'Работают ' .. cardsOn .. ' из ' .. cardsTotal, tx1 + 70, 448.5,
            rgba(allOn and 0x2EF0C4 or 0xFFA53D))
        local line = allOn and 'все включены' or ('стоят: №' .. table.concat(stopped, ', №'))
        if textWidth(Font.medium11, line) > 106 then line = 'стоят: ' .. #stopped .. ' шт.' end
        drawText(Font.medium11, line, tx1 + 70, 466, rgba(allOn and Palette.muted or 0xE0A060))
    else
        drawText(Font.medium125, 'Работа', tx1 + 70, 448.5, rgba(Palette.text))
        drawText(Font.medium125, 'видеокарт', tx1 + 70, 466, rgba(Palette.text))
    end

    if drawBigButton('##cardsOn', tx1 + 180, y + 11, 142, 42, 0x04775D, 0x033848, 0.62, 0.36, 0x2A8C79, 0x10C090) then
        Actions.switchCards(true)
    end
    drawText(Font.bold13, 'ВКЛЮЧИТЬ', tx1 + 180 + 71, y + 11 + 26, rgba(0xEAFFF7), 'c')

    if drawBigButton('##cardsOff', tx1 + 332, y + 11, 142, 42, 0x8A2A30, 0x45141B, 0.62, 0.36, 0xB5525A, 0xF0554B) then
        Actions.switchCards(false)
    end
    drawText(Font.bold13, 'ОТКЛЮЧИТЬ', tx1 + 332 + 71, y + 11 + 26, rgba(0xFFECEC), 'c')

    local tx2, w2 = 675, 273
    fillRoundRect(tx2, y, w2, h, rgba(Palette.tile), 10)
    strokeRoundRect(tx2, y, w2, h, rgba(Palette.tileLine), 10)
    glowCircle(tx2 + 33, y + 32.5, 22.5, Palette.gold, 0.10, 6)
    fillCircle(tx2 + 33, y + 32.5, 22.5, rgba(0x2A2316))
    drawIcon('bolt', 24, tx2 + 33, y + 32.5, rgba(0xF7A93A))
    drawText(Font.medium125, 'Авто', tx2 + 70, 448.5, rgba(Palette.text))
    local autoHover = isMouseOver(tx2, y, w2 - 70, h)
    drawInfoBadge(tx2 + 70 + textWidth(Font.medium125, 'Авто') + 14, 444, autoHover)
    if autoHover then currentHint = { HINTS.auto, tx2 + w2 - 380, y - 4, true } end
    drawText(Font.medium125, 'режим', tx2 + 70, 466, rgba(Palette.text))
    cfg.autoMode = drawToggle('##auto', tx2 + w2 - 40 - 22, 442, cfg.autoMode)

    drawFooter()
end

local SETTINGS_ROWS = { 186, 303.5, 421 }

local function drawRowLabel(x, row, label, hint)
    local cy = SETTINGS_ROWS[row] + 20
    drawText(Font.medium14, label, x, cy - 2, rgba(Palette.white))
    drawText(Font.regular12, hint, x, cy + 16, rgba(Palette.muted))
end

local function drawSettings()
    drawCard(159, 96, 365, 262)
    drawIcon('gear', 21, 187.5, 123.5, rgba(0x22E3B0))
    drawCardHeader(159, 96, 365, 'НАСТРОЙКИ', 215)

    local y1, bx = SETTINGS_ROWS[1], 341
    drawRowLabel(176, 1, 'Курс битка', 'при запуске и по кнопке')
    fillRoundRect(bx, y1, 116, 40, rgba(0x0A0E18), 8)
    strokeRoundRect(bx, y1, 116, 40, rgba(0x1D2431), 8)
    local rateStr = cfg.rate > 0 and (fmtNum(cfg.rate) .. ' руб') or 'загрузка...'
    drawText(Font.semi13, rateStr, bx + 58, y1 + 24.85, rgba(Palette.white), 'c')
    if drawSmallButton('##rateRefresh', bx + 124, y1, 44, 40, true, 'refresh') then updateRate(true) end

    drawHLine(176, 509, SETTINGS_ROWS[2] - 38.5, rgba(Palette.divider))

    drawRowLabel(176, 2, 'Обновлено', 'последний раз')
    local upd = rateState.time > 0 and os.date('%H:%M', rateState.time) or 'ещё нет'
    drawText(Font.semi13, upd, 509, SETTINGS_ROWS[2] + 25, rgba(Palette.white), 'r')

    drawCard(539, 96, 422, 262)
    drawIcon('snowflake', 28, 570.5, 123.5, rgba(Palette.ice))
    drawCardHeader(539, 96, 422, 'ОПЦИИ', 599)

    drawRowLabel(556, 1, 'Перезагрузка', 'перезагрузить скрипт')
    if drawBigButton('##reload', 835, SETTINGS_ROWS[1], 110, 40, 0x04775D, 0x033848, 0.62, 0.36, 0x2A8C79, 0x10C090) then
        cfg.isReloaded = true
        saveConfig()
        thisScript():reload()
    end
    drawText(Font.bold13, 'СБРОС', 890, SETTINGS_ROWS[1] + 24.7, rgba(0xEAFFF7), 'c')

    drawHLine(556, 945, SETTINGS_ROWS[2] - 38.5, rgba(Palette.divider))

    drawRowLabel(556, 2, 'Скрытие диалога', 'прятать окно диалога сервера')
    cfg.hideDialog = drawToggle('##hideDialog', 905, SETTINGS_ROWS[2] + 8.5, cfg.hideDialog)

    drawCard(159, 372, 802.5, 128)
    drawIcon('chart', 21, 187.5, 399, rgba(0x22E3B0))
    drawCardHeader(159, 372, 802.5, 'АНАЛИТИКА', 215)
    drawText(Font.medium14, 'Аксессуар RTX 4090', 176, 452, rgba(Palette.white))
    drawText(Font.regular12, '+25% к скорости добычи в расчётах и прогнозах', 176, 470, rgba(Palette.muted))
    cfg.rtx4090 = drawToggle('##rtx4090', 905, 442, cfg.rtx4090)
    drawFooter()
end

local function drawStatTile(x, w, label, value, sub, icon, hex)
    drawCard(x, 96, w, 88)
    glowCircle(x + 34, 140, 20, hex, 0.10, 6)
    fillCircle(x + 34, 140, 20, rgba(mixColor(hex, 0x000000, 0.82)))
    drawIcon(icon, 21, x + 34, 140, rgba(hex))
    drawText(Font.medium11, label, x + 66, 124, rgba(Palette.muted))
    drawText(Font.bold16, value, x + 66, 148, rgba(Palette.white))
    if sub and sub ~= '' then drawText(Font.regular12, sub, x + 66, 168, rgba(Palette.dim)) end
end

local function fmtBtc(n) return string.format('%.2f', n) end

local function drawAnalytics()
    local a = getAnalytics()
    local gapX = 14
    local w = (802.5 - gapX * 3) / 4
    local x1 = 159
    local rate = cfg.rate

    drawStatTile(x1, w, 'Общий Баланс', a.real and (fmtBtc(a.balance) .. ' BTC') or '—',
        a.real and rate > 0 and ('\226\137\136 ' .. fmtNum(a.balance * rate) .. u8(' руб')) or '', 'coins', 0xFFB020)
    drawStatTile(x1 + (w + gapX), w, 'Скорость Фермы', a.real and (fmtBtc(a.speed) .. ' BTC/ч') or '—',
        a.real and ('работает карт: ' .. a.working .. '/' .. #a.list) or '', 'bolt', 0x2EC8FF)
    drawStatTile(x1 + (w + gapX) * 2, w, 'Доход за 24ч', a.real and (fmtBtc(a.daily) .. ' BTC') or '—',
        a.real and rate > 0 and ('\226\137\136 ' .. fmtNum(a.daily * rate) .. u8(' руб')) or '', 'calendar', 0x3DDBB0)

    local fullText, fullSub, fullHex = '—', '', 0xF7A93A
    if a.real then
        if a.nextDays == nil then
            fullText, fullSub, fullHex = 'Не работает', '', 0x6B7488
        elseif a.nextDays <= 0 then
            fullText, fullSub, fullHex = 'Заполнено!', a.nextShelf and ('карта №' .. a.nextShelf) or '', 0xF0554B
        else
            fullText = a.nextDays .. ' PayDay'
            fullSub = a.nextShelf and ('карта №' .. a.nextShelf) or ''
            fullHex = a.nextDays <= 2 and 0xFF8A3D or 0x3DDBB0
        end
    end
    drawStatTile(x1 + (w + gapX) * 3, w, 'След. Заполнение', fullText, fullSub, 'hourglass', fullHex)

    drawCard(159, 198, 802.5, 302)
    drawIcon('chart', 21, 187.5, 225, rgba(0x22E3B0))
    drawCardHeader(159, 198, 802.5, 'Карты и Прогноз', 215)
    if cfg.rtx4090 then
        fillRoundRect(853, 212, 92, 24, rgba(0x0A2A25), 7)
        strokeRoundRect(853, 212, 92, 24, rgba(Palette.green, 0.28), 7)
        drawText(Font.bold11, 'RTX 4090 +25%', 899, 228.5, rgba(Palette.green), 'c')
    end

    if not a.real then
        drawText(Font.medium14, 'Откройте видеокарты в подвале майнинга — здесь появятся расчёты', 560, 360, rgba(Palette.dim), 'c')
        drawFooter()
        return
    end

    local perCol = 8
    local single = #a.list <= perCol
    local colX = single and { 175 } or { 175, 567 }
    local L = single
        and { lvl = 72, bar = 175, barW = 290, pct = 480, btc = 650, days = 770, rowW = 786 }
        or  { lvl = 62, bar = 118, barW = 130, pct = 256, btc = 304, days = 380, rowW = 388 }
    local fHead = single and Font.medium125 or Font.medium11
    local fNum  = single and Font.semi135 or Font.semi125
    local fLvl  = single and Font.medium14 or Font.medium125
    local fPct  = single and Font.medium125 or Font.medium11
    local fVal  = single and Font.bold14 or Font.bold12
    local barH  = single and 8 or 6
    local top = 278
    local ROW = single and clamp(floor(210 / max(#a.list, 1)), 30, 46) or 26

    for c = 1, #colX do
        local x0 = colX[c]
        drawText(fHead, '№', x0, top - 9, rgba(Palette.dim))
        drawText(fHead, 'Уровень', x0 + L.lvl, top - 9, rgba(Palette.dim))
        drawText(fHead, 'Заполненность', x0 + L.bar, top - 9, rgba(Palette.dim))
        drawText(fHead, 'BTC', x0 + L.btc, top - 9, rgba(Palette.dim), 'r')
        drawText(fHead, 'До полного', x0 + L.days, top - 9, rgba(Palette.dim), 'r')
    end

    for i, item in ipairs(a.list) do
        if i > perCol * 2 then break end
        local c = (single or i <= perCol) and 1 or 2
        local r = single and (i - 1) or ((i - 1) % perCol)
        local x0, y = colX[c], top + r * ROW
        if r % 2 == 0 then fillRoundRect(x0 - 8, y - 2, L.rowW, ROW - 2, rgba(0xFFFFFF, 0.025), 6) end
        local base = y + (ROW - 2) / 2 + (single and 4.5 or 3.5)
        local cy = base - 4.5

        fillCircle(x0 + 4, cy, single and 4 or 3.5, rgba(item.on and 0x1EE8B4 or 0x4A5366))
        drawText(fNum, tostring(item.shelf), x0 + 16, base, rgba(Palette.text))
        drawText(fLvl, item.level > 0 and ('Ур. ' .. item.level) or '—', x0 + L.lvl, base, rgba(Palette.muted))

        local frac = clamp(item.profit / CARD_CAPACITY, 0, 1)
        local hex = frac >= 0.9 and 0xF0554B or (frac >= 0.65 and 0xF7A93A or 0x2EE6B0)
        fillRoundRect(x0 + L.bar, cy - barH / 2, L.barW, barH, rgba(0x141B28), barH / 2)
        if frac > 0.01 then fillRoundRect(x0 + L.bar, cy - barH / 2, L.barW * frac, barH, rgba(hex), barH / 2) end
        drawText(fPct, floor(frac * 100 + 0.5) .. '%', x0 + L.pct, base, rgba(Palette.dim))

        drawText(fVal, fmtBtc(item.profit), x0 + L.btc, base, rgba(item.profit > 0 and Palette.white or Palette.dim), 'r')

        local ftxt, fcol = '—', 0x4A5366
        if item.days then
            if item.days <= 0 then ftxt, fcol = 'Полно', 0xF0554B
            else ftxt, fcol = item.days .. ' PayDay', item.days <= 2 and 0xFF8A3D or 0x6FD6FF end
        end
        drawText(fVal, ftxt, x0 + L.days, base, rgba(fcol), 'r')
    end
    if #a.list > perCol * 2 then
        drawText(Font.medium11, 'и ещё ' .. (#a.list - perCol * 2) .. ' карт', 560, 490, rgba(Palette.dim), 'c')
    end
    drawFooter()
end

local windowPlaced = false
local WINDOW_FLAGS
local windowFade = 0

local function drawWindow()
    if not windowPlaced then
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2 + 15), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        windowPlaced = true
    end
    WINDOW_FLAGS = WINDOW_FLAGS or (imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
        + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoSavedSettings)
    imgui.SetNextWindowSize(poolVec(WIN_W * SCALE, (WIN_H + 30) * SCALE), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, poolVec(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
    imgui.Begin('##MiningTools', nil, WINDOW_FLAGS)
    imgui.PopStyleVar(3)

    local ok, err = pcall(function()
        local p = imgui.GetWindowPos()
        local e = windowFade * windowFade * (3 - 2 * windowFade)
        originX, originY = p.x, p.y + (1 - e) * 22
        drawList = imgui.GetWindowDrawList()
        frameDelta = imgui.GetIO().DeltaTime
        inputLocked = not state.window[0]
        local vs0 = drawList.VtxBuffer.Size
        currentHint = nil
        fillRoundRect(0, 0, WIN_W, WIN_H, rgba(Palette.bg), 14)
        drawHeader()
        drawSidebar()
        if cfg.page == 3 then
            drawAnalytics()
        elseif cfg.page == 2 then
            drawSettings()
        else
            drawMining()
            drawCooling()
            drawQuick()
        end
        strokeRoundRect(0, 0, WIN_W, WIN_H, rgba(Palette.frame), 14)
        if currentHint then shownHint = currentHint end
        local hintAlpha = animate('tipfade', currentHint and 1 or 0, 16)
        if hintAlpha > 0.01 and shownHint then drawHint(shownHint[1], shownHint[2], shownHint[3], shownHint[4], hintAlpha) end
        fadeVertices(vs0, e)
    end)
    imgui.End()

    if not ok then
        state.window[0] = false
        state.manualOpen = false
        windowFade = 0
        notify('Ошибка меню', tostring(err):sub(1, 90), 'err')
        pcall(chat, '{FF5555}Ошибка меню: {FFFFFF}' .. tostring(err):sub(1, 160))
    end
end

local drawToasts
do
local TOAST_LIFE = 5
local TOAST_COLORS = { ok = 0x2EE6B0, info = 0x2EB8FF, warn = 0xF5A623, err = 0xF0554B }
local TOAST_ICONS = { ok = 'check', info = 'info', warn = 'warn', err = 'xmark' }
local TOAST_FALLBACK = { ok = '+', info = 'i', warn = '!', err = 'x' }
local toastFlags

function drawToasts()
    local now = os.clock()
    frameDelta = imgui.GetIO().DeltaTime
    for i = #toasts, 1, -1 do
        if now - toasts[i].born > TOAST_LIFE then table.remove(toasts, i) end
    end
    if #toasts == 0 then return end

    local gap, margin, room = 10, 20, 50
    local maxW, off, geo = 0, 0, {}
    for i = #toasts, 1, -1 do
        local t = toasts[i]
        local w = textWidth(Font.bold14, t.title)
        for _, l in ipairs(t.lines) do w = max(w, textWidth(Font.medium13, l)) end
        w = clamp(w + 92, 320, 560)
        local h = #t.lines > 0 and (54 + #t.lines * 19) or 46
        geo[i] = { w = w, h = h, target = off }
        maxW = max(maxW, w)
        off = off + h + gap
    end
    local winW = maxW + margin * 2
    local winH = off - gap + margin * 2 + room

    local sw, sh = getScreenResolution()
    toastFlags = toastFlags or (imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoInputs
        + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoMove)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2 - winW * SCALE / 2, sh - (30 - room + winH) * SCALE), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(winW * SCALE, winH * SCALE), imgui.Cond.Always)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, poolVec(0, 0))
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
    imgui.Begin('##MiningToasts', nil, toastFlags)
    imgui.PopStyleVar(3)

    pcall(function()
        local p = imgui.GetWindowPos()
        originX, originY = p.x, p.y
        drawList = imgui.GetWindowDrawList()
        for i, t in ipairs(toasts) do
            local g = geo[i]
            t.off = (t.off or g.target) + (g.target - (t.off or g.target)) * min(1, frameDelta * 12)

            local age = now - t.born
            local fin = clamp(age / 0.5, 0, 1)
            local ein = 1 - (1 - fin) ^ 3
            local leave = clamp((age - (TOAST_LIFE - 0.5)) / 0.5, 0, 1)
            local eout = leave ^ 3
            local a = ein * (1 - eout)
            local slide = (1 - ein) * 46 + eout * 36

            local col = TOAST_COLORS[t.kind] or TOAST_COLORS.ok
            local x = margin + (maxW - g.w) / 2
            local y = winH - room - margin - t.off - g.h + slide
            local vs = drawList.VtxBuffer.Size

            glowRoundRect(x, y, g.w, g.h, 14, col, 0.10, 10)
            gradientRoundRect(x, y, g.w, g.h, 0x0F1520, 0x090D15, 0.98, 'v', 14)
            strokeRoundRect(x, y, g.w, g.h, rgba(col, 0.38), 14)

            local cx, cy = x + 34, y + g.h / 2 - 2
            glowCircle(cx, cy, 17, col, 0.18, 6)
            fillCircle(cx, cy, 17, rgba(col, 0.16))
            local icon = TOAST_ICONS[t.kind] or 'check'
            if not drawIcon(icon, 18, cx, cy, rgba(col)) then
                drawText(Font.bold14, TOAST_FALLBACK[t.kind] or '+', cx, cy + 5, rgba(col), 'c')
            end

            drawText(Font.bold14, t.title, x + 68, y + 31, rgba(Palette.white))
            for j, l in ipairs(t.lines) do
                drawText(Font.medium13, l, x + 68, y + 54 + (j - 1) * 19, rgba(Palette.text))
            end

            local bx, bw = x + 68, g.w - 68 - 20
            local frac = clamp(1 - age / TOAST_LIFE, 0, 1)
            fillRoundRect(bx, y + g.h - 9, bw, 2, rgba(0xFFFFFF, 0.06), 1)
            if frac > 0.01 then fillRoundRect(bx, y + g.h - 9, bw * frac, 2, rgba(col, 0.85), 1) end

            fadeVertices(vs, a)
        end
    end)
    imgui.End()
end
end

imgui.OnFrame(function() return #toasts > 0 end, function(self)
    self.HideCursor = true
    drawToasts()
end)

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    local fonts = io.Fonts

    local builder = imgui.ImFontGlyphRangesBuilder()
    builder:AddRanges(fonts:GetGlyphRangesDefault())
    builder:AddText(toUtf8('АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя—–•…№') .. '\226\137\136')
    glyphRanges = imgui.ImVector_ImWchar()
    builder:BuildRanges(glyphRanges)
    local ranges, latin = glyphRanges[0].Data, fonts:GetGlyphRangesDefault()

    SCALE = fitScale()

    local wd = getWorkingDirectory()
    local dir = wd .. '/resource/mining_tools/'
    local searchDirs = { wd .. '/resource/fonts/', '/system/fonts/', '/system/font/', '/product/fonts/' }
    if not IS_MOBILE then
        local okf, win = pcall(getFolderPath, 0x14)
        if okf and win then searchDirs = { win .. '\\' } end
    end
    local function addFontFile(path, size, rng)
        local list = { u8(path) }
        if list[1] ~= path then list[2] = path end
        for _, p in ipairs(list) do
            local ok, f = pcall(fonts.AddFontFromFileTTF, fonts, p, size, nil, rng)
            if ok and f ~= nil then return f end
        end
    end
    local function loadFontFile(file, em, fallback, rng)
        rng = rng or ranges
        if doesFileExist(dir .. file) then
            local f = addFontFile(dir .. file, em * (file:find('Montserrat') and 1.219 or 1.21) * SCALE, rng)
            if f then return { f = f } end
        end
        for _, folder in ipairs(searchDirs) do
            for _, fb in ipairs(fallback) do
                if doesFileExist(folder .. fb) then
                    local f = addFontFile(folder .. fb, em * 1.33 * SCALE, rng)
                    if f then return { f = f } end
                end
            end
        end
        state.fontMissing = true
        return {}
    end
    local BOLD = { 'segoeuib.ttf', 'arialbd.ttf', 'Roboto-Bold.ttf', 'RobotoStatic-Bold.ttf', 'NotoSans-Bold.ttf', 'DroidSans-Bold.ttf', 'Roboto[wdth,wght].ttf' }
    local REG  = { 'segoeui.ttf', 'arial.ttf', 'Roboto-Regular.ttf', 'RobotoStatic-Regular.ttf', 'NotoSans-Regular.ttf', 'DroidSans.ttf', 'Roboto[wdth,wght].ttf' }
    local SEMI = { 'seguisb.ttf', 'segoeuib.ttf', 'arialbd.ttf', 'Roboto-Medium.ttf', 'RobotoStatic-Medium.ttf', 'Roboto-Bold.ttf', 'NotoSans-Bold.ttf', 'Roboto[wdth,wght].ttf' }
    Font.title = loadFontFile('Montserrat-Bold.ttf', 28.4, BOLD, latin)
    Font.subtitle   = loadFontFile('Inter-Regular.ttf', 16, REG)
    Font.bold16   = loadFontFile('Inter-Bold.ttf', 16.5, BOLD)
    Font.bold14   = loadFontFile('Inter-Bold.ttf', 14, BOLD)
    Font.bold135  = loadFontFile('Inter-Bold.ttf', 13.5, BOLD)
    Font.bold13   = loadFontFile('Inter-Bold.ttf', 13, BOLD)
    Font.bold12   = loadFontFile('Inter-Bold.ttf', 12, BOLD)
    Font.bold11   = loadFontFile('Inter-Bold.ttf', 11, BOLD)
    Font.medium145  = loadFontFile('Inter-Medium.ttf', 14.5, REG)
    Font.medium14   = loadFontFile('Inter-Medium.ttf', 14, REG)
    Font.medium13   = loadFontFile('Inter-Medium.ttf', 13, REG)
    Font.medium125  = loadFontFile('Inter-Medium.ttf', 12.5, REG)
    Font.medium11   = loadFontFile('Inter-Medium.ttf', 11, REG)
    Font.semi135  = loadFontFile('Inter-SemiBold.ttf', 13.5, SEMI)
    Font.semi13   = loadFontFile('Inter-SemiBold.ttf', 13, SEMI)
    Font.semi125  = loadFontFile('Inter-SemiBold.ttf', 12.5, SEMI)
    Font.regular12   = loadFontFile('Inter-Regular.ttf', 12, REG)
    Font.number30   = loadFontFile('Inter-Bold.ttf', 30.5, BOLD, latin)

    local fa = wd .. '/resource/fonts/fa-solid-900.ttf'
    if not IS_MOBILE and doesFileExist(fa) then
        local fb = imgui.ImFontGlyphRangesBuilder()
        for _, str in pairs(ICONS) do fb:AddText(str) end
        faRanges = imgui.ImVector_ImWchar()
        fb:BuildRanges(faRanges)
        for _, px in ipairs(ICON_SIZES) do iconFonts[px] = addFontFile(fa, px * SCALE, faRanges[0].Data) end
    end
end)

imgui.OnFrame(function() return state.window[0] or windowFade > 0 end, function(self)
    local step = imgui.GetIO().DeltaTime
    if state.window[0] then windowFade = min(1, windowFade + step / 0.30) else windowFade = max(0, windowFade - step / 0.22) end
    self.HideCursor = not state.window[0]
    if windowFade > 0 then drawWindow() end
end)

local escConsumed = false
if not IS_MOBILE then addEventHandler('onWindowMessage', function(msg, wparam)
    if wparam ~= 0x1B then return end
    if msg == 0x100 and state.hiddenList and cfg.active and not state.working then
        escConsumed = true
        consumeWindowMessage(true, false)
        closeHiddenList()
    elseif msg == 0x100 and state.manualOpen and state.window[0] and not state.working and not isListOpen() then
        escConsumed = true
        consumeWindowMessage(true, false)
        closeWindow()
    elseif msg == 0x101 and escConsumed then
        escConsumed = false
        consumeWindowMessage(true, false)
    end
end) end

local function updateWhenActive(watch)
    local listOpen  = isListOpen()
    if state.hiddenList then watch.ignoreOpenDialog = false end

    if watch.ignoreOpenDialog and not listOpen then watch.ignoreOpenDialog = false end
    local listReady = listOpen and not watch.ignoreOpenDialog

    if state.checkPending then
        state.checkPending = false
        if listReady and not state.working then
            notifyIfNothingToDo()
            warnNoCooling()
        end
    end

    state.window[0] = listReady or state.manualOpen or (state.window[0] and state.working)
    if not state.window[0] then state.beforeWithdraw = nil end

    if cfg.autoMode ~= watch.prevAuto then
        watch.prevAuto = cfg.autoMode
        if cfg.autoMode then
            state.autoReady   = true
            watch.autoManual  = listOpen
        end
    end

    if state.autoReady and listReady and not state.working then
        state.autoReady = false
        local manual = watch.autoManual
        watch.autoManual = false
        if cfg.autoMode then Actions.auto(manual) end
    end
end

local function updateWhenPaused()
    closeHiddenList()
    state.checkPending = false
    state.window[0] = state.manualOpen
    if not state.window[0] then state.beforeWithdraw = nil end
end

function main()
    while not isSampAvailable() do wait(100) end

    chat('загружен (mobile)  {c0c0c0}/mt{FFFFFF} - открыть настройки, в подвале майнинга меню откроется само')

    sampRegisterChatCommand('mt', function()
        if state.window[0] then
            closeWindow()
            return
        end
        state.manualOpen = true
        state.window[0] = true
        if not isListOpen() then
            setCursor(true)
            notify('Только в подвале майнинга', { 'Основной функционал работает', 'только в подвале майнинга.' }, 'warn')
        end
    end)

    lua_thread.create(function()
        wait(4000)
        if state.fontMissing then
            chat('{FFAA00}не найден шрифт с кириллицей. Положи arial.ttf в moonloader/resource/fonts/ или Inter-*.ttf в resource/mining_tools/')
        end
    end)

    updateRate(false, nil, true)

    if cfg.isReloaded then
        cfg.isReloaded = false
        saveConfig()
    end

    local watch = {
        ignoreOpenDialog = sampIsDialogActive() and isCardListId(sampGetCurrentDialogId()),
        prevAuto         = cfg.autoMode,
        autoManual       = false,
    }

    while true do
        wait(0)
        if cfg.active then
            updateWhenActive(watch)
        else
            updateWhenPaused()
        end
    end
end
