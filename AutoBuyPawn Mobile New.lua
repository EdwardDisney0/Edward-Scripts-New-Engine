script_name('AutoBuyPawn Mobile')
script_author('Edward')
script_version('1.0')

require 'lib.moonloader'
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
local sampev = require 'lib.samp.events'
pcall(require, 'RakLua')

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new, str = imgui.new, ffi.string
local V2, V4 = imgui.ImVec2, imgui.ImVec4
local min, max, floor = math.min, math.max, math.floor
local bit = require 'bit'

local DPI = max(1, min(tonumber(MONET_DPI_SCALE) or 2.5, 4))
local zoom = 1
local function d(v) return floor(v * DPI * zoom + 0.5) end
local LINE = max(1, DPI * 0.5)
local ROW, GAP, DAYS_ROW, BTN, HEAD
local applyScale

local DLG_LIST, DLG_SEARCH, DLG_PRICE, DLG_DAYS = 532, 539, 533, 538
local CEF_IFACE, CEF_SELECT, MENU_ITEM = 84, 2, 25
local MENU_TITLE = 'Изменить товары для выкупа'
local DIR = getWorkingDirectory() .. '/config/'
local FILE = DIR .. 'AutoBuyPawn_mobile.lua'
local DAYS_ITEMS = { [5131] = true }

local cfg = { active = 'Default', configs = { Default = {} }, delay = 0, v = 2, skipsame = true, days = {}, scale = 100, pngIcons = false }
local db = { items = {}, time = 0 }
local byId = {}
local dirty, lastSave = false, 0
local dbVer, selVer = 0, 0
local priceBuf, daysBuf = {}, {}
local editing, editFocus

local st = { mode = 'idle', page = 0, found = 0, tmp = {}, seen = {}, queue = {}, total = 0, done = 0, fail = 0, skipped = 0, last = 0, title = '' }
local shown = new.bool(false)
local tab = 1
local ui = { search = new.char[96](), newName = new.char[48](), delay = new.int(0), scale = new.int(100) }
local fMain, fBig, fSmall

local function msg(s)
    sampAddChatMessage('{9B5CFF}[AutoBuy] {FFFFFF}' .. u8:decode(s), -1)
end

local function lower(s)
    s = s:gsub('\208[\144-\159]', function(c) return '\208' .. string.char(c:byte(2) + 32) end)
    s = s:gsub('\208[\160-\175]', function(c) return '\209' .. string.char(c:byte(2) - 32) end)
    s = s:gsub('\208\129', '\209\145')
    return s:lower()
end

local function noColors(s) return (s:gsub('{%x%x%x%x%x%x}', '')) end

local function number(n)
    local s = tostring(floor(tonumber(n) or 0)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', '')
    return s
end

local function price(n)
    if (tonumber(n) or 0) <= 0 then return 'Не скупается' end
    return number(n)
end

local function serialize(v)
    local t = type(v)
    if t == 'table' then
        local out = {}
        for k, x in pairs(v) do
            local key = type(k) == 'number' and ('[%d]'):format(k) or ('[%q]'):format(k)
            out[#out + 1] = key .. '=' .. serialize(x)
        end
        return '{' .. table.concat(out, ',') .. '}'
    elseif t == 'string' then
        return ('%q'):format(v)
    elseif t == 'number' and v == floor(v) then
        return ('%d'):format(v)
    end
    return tostring(v)
end

local function reindex()
    byId = {}
    dbVer = dbVer + 1
    for _, it in ipairs(db.items) do
        it.l = lower(it.name)
        byId[it.id] = it
    end
end

local function save()
    createDirectory(DIR)
    local items = {}
    for i, it in ipairs(db.items) do items[i] = { id = it.id, name = it.name, cur = it.cur } end
    local f = io.open(FILE, 'wb')
    if f then
        f:write('return ' .. serialize({ cfg = cfg, db = { items = items, time = db.time } }))
        f:close()
    end
    dirty, lastSave = false, os.clock()
end

local function load()
    local chunk = loadfile(FILE)
    local ok, data = false, nil
    if chunk then ok, data = pcall(chunk) end
    if ok and type(data) == 'table' then
        if type(data.cfg) == 'table' then
            for k, v in pairs(data.cfg) do cfg[k] = v end
        end
        if type(data.db) == 'table' then db = data.db end
    end
    if type(cfg.configs) ~= 'table' or not next(cfg.configs) then cfg.configs = { Default = {} } end
    if not cfg.configs[cfg.active] then cfg.active = next(cfg.configs) end
    if type(cfg.days) ~= 'table' then cfg.days = {} end
    db.items = db.items or {}
    ui.delay[0] = cfg.delay or 0
    cfg.scale = tonumber(cfg.scale) or 100
    ui.scale[0] = cfg.scale
    applyScale(cfg.scale)
    reindex()
end

local function configNames()
    local t = {}
    for k in pairs(cfg.configs) do t[#t + 1] = k end
    table.sort(t)
    return t
end

local function resetEdit()
    priceBuf, daysBuf, editing = {}, {}, nil
end

local picked = { list = {}, ver = -1, dbv = -1, name = nil }
local function pickedItems()
    if picked.ver ~= selVer or picked.dbv ~= dbVer or picked.name ~= cfg.active then
        local sel, list = cfg.configs[cfg.active], {}
        for _, it in ipairs(db.items) do
            if sel[it.id] ~= nil then list[#list + 1] = it end
        end
        picked = { list = list, ver = selVer, dbv = dbVer, name = cfg.active }
    end
    return picked.list
end

local function selectionChanged()
    selVer = selVer + 1
    dirty = true
end

local function sendClick(a, b)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, CEF_IFACE)
    raknetBitStreamWriteInt32(bs, a)
    raknetBitStreamWriteInt32(bs, b)
    raknetBitStreamWriteInt16(bs, 0)
    if raknetSendBitStreamEx then
        raknetSendBitStreamEx(bs, 1, 7, 0)
    else
        raknetSendBitStream(bs)
    end
    raknetDeleteBitStream(bs)
end

local function respond(id, button, item, input)
    local delay = cfg.delay or 0
    if delay <= 0 then
        sampSendDialogResponse(id, button, item, input or '')
        return
    end
    lua_thread.create(function()
        wait(delay)
        sampSendDialogResponse(id, button, item, input or '')
    end)
end

local function parseList(text)
    local lines = {}
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = line:gsub('\r', '') end
    local items, nextIdx = {}, nil
    for i = 2, #lines do
        local line = noColors(lines[i])
        if line:find('Следующая страница', 1, true) then
            nextIdx = i - 2
        elseif line ~= '' and not line:find('Предыдущая страница', 1, true) then
            local first, _, last = line:match('^(.-)\t(.-)\t(.*)$')
            local name, id = (first or line):match('^(.-)%s*%[(%d+)%]%s*$')
            if name then
                items[#items + 1] = { id = tonumber(id), name = name, cur = tonumber(((last or ''):gsub('%D', ''))) or 0 }
            end
        end
    end
    return items, nextIdx
end

local function stop(reason)
    st.mode, st.cur, st.queue = 'idle', nil, {}
    msg(reason)
end

local function openBusinessMenu(nextMode, title)
    st.mode, st.next, st.title = 'await', nextMode, title
    st.ready, st.menuId = nil, nil
    st.waitFrom, st.last = os.clock(), os.clock()
    shown[0] = false
    sampProcessChatInput('/bmenu')
    msg('Выберите ломбард в меню бизнеса - дальше скрипт всё сделает сам')
end

local function startWork()
    st.mode, st.ready = st.next, nil
    st.last = os.clock()
    if not pcall(sendClick, st.menuId or MENU_ITEM, CEF_SELECT) then
        stop('Не удалось отправить пакет, операция отменена')
    end
end

local function startScan()
    if st.mode ~= 'idle' then return end
    st.page, st.found, st.tmp, st.seen = 0, 0, {}, {}
    openBusinessMenu('scan', 'Загрузка списка товаров...')
end

local function finishScan()
    db.items = st.tmp
    db.time = os.time()
    reindex()
    st.mode = 'idle'
    dirty = true
    shown[0] = true
    msg('Список обновлён. Товаров: ' .. #db.items)
end

local function startPlace(remove)
    if st.mode ~= 'idle' then return end
    if #db.items == 0 then
        msg('Сначала обновите список товаров')
        return
    end
    local sel = cfg.configs[cfg.active]
    local queue, skipped = {}, 0
    for _, it in ipairs(db.items) do
        local days = DAYS_ITEMS[it.id] and (cfg.days[it.id] or -1) or nil
        if remove then
            if (it.cur or 0) > 0 then queue[#queue + 1] = { id = it.id, name = it.name, price = 0, days = days } end
        elseif sel[it.id] then
            if sel[it.id] <= 0 or (cfg.skipsame and it.cur == sel[it.id]) then
                skipped = skipped + 1
            else
                queue[#queue + 1] = { id = it.id, name = it.name, price = sel[it.id], days = days }
            end
        end
    end
    if #queue == 0 then
        msg(remove and 'Нечего снимать' or ('Нечего выставлять (пропущено: ' .. skipped .. ')'))
        return
    end
    st.queue, st.cur = queue, nil
    st.total, st.done, st.fail, st.skipped = #queue, 0, 0, skipped
    openBusinessMenu('place', remove and 'Снятие товаров со скупки...' or 'Выставление товаров на скупку...')
end

local function finishPlace()
    st.mode = 'idle'
    shown[0] = true
    dirty = true
    msg(('Готово. Успешно: %d, ошибок: %d, пропущено: %d'):format(st.done, st.fail, st.skipped))
end

function sampev.onShowDialog(id, style, title, button1, button2, text)
    if st.mode == 'idle' then
        if st.closeUntil and id == DLG_LIST and os.clock() < st.closeUntil then
            st.closeUntil = nil
            respond(DLG_LIST, 0, -1)
            return false
        end
        return
    end

    local cur = st.cur
    if id == DLG_LIST then
        if not noColors(u8(title)):find('Скупка ломбарда', 1, true) then return end
        st.last = os.clock()
        if st.mode == 'scan' then
            local items, nextIdx = parseList(u8(text))
            local added = 0
            st.page = st.page + 1
            for _, it in ipairs(items) do
                if not st.seen[it.id] then
                    st.seen[it.id] = true
                    st.tmp[#st.tmp + 1] = it
                    added = added + 1
                end
            end
            st.found = #st.tmp
            if nextIdx and added > 0 and st.page < 300 then
                respond(DLG_LIST, 1, nextIdx)
            else
                finishScan()
                respond(DLG_LIST, 0, -1)
            end
            return false
        elseif st.mode == 'place' then
            if cur then
                if cur.ok then st.done = st.done + 1 else st.fail = st.fail + 1 end
            end
            st.cur = table.remove(st.queue, 1)
            if st.cur then
                st.cur.tries = 0
                respond(DLG_LIST, 1, 0)
            else
                finishPlace()
                respond(DLG_LIST, 0, -1)
            end
            return false
        end
    end

    if st.mode ~= 'place' or not cur then return end

    if id == DLG_SEARCH then
        st.last = os.clock()
        cur.tries = (cur.tries or 0) + 1
        if cur.tries > 1 then
            respond(DLG_SEARCH, 0, -1)
        else
            cur.sent = true
            respond(DLG_SEARCH, 1, -1, tostring(cur.id))
        end
        return false
    elseif id == DLG_DAYS then
        st.last = os.clock()
        if noColors(text):find('[' .. cur.id .. ']', 1, true) then
            respond(DLG_DAYS, 1, -1, tostring(cur.days or -1))
        else
            respond(DLG_DAYS, 0, -1)
        end
        return false
    elseif id == DLG_PRICE then
        st.last = os.clock()
        if cur.ok then
            cur.ok = false
            respond(DLG_PRICE, 0, -1)
        elseif cur.sent or noColors(text):find('[' .. cur.id .. ']', 1, true) then
            cur.ok = true
            if byId[cur.id] then byId[cur.id].cur = cur.price end
            respond(DLG_PRICE, 1, -1, tostring(cur.price))
        else
            respond(DLG_PRICE, 0, -1)
        end
        return false
    end
end

local function readCef(bs)
    local ok, text, kind = pcall(function()
        raknetBitStreamResetReadPointer(bs)
        raknetBitStreamIgnoreBits(bs, 8)
        local kind = raknetBitStreamReadInt8(bs)
        if kind == 17 then
            raknetBitStreamIgnoreBits(bs, 32)
        elseif kind == 84 then
            raknetBitStreamIgnoreBits(bs, 16)
        else
            return
        end
        local len = raknetBitStreamReadInt16(bs)
        local enc = raknetBitStreamReadInt8(bs)
        if enc ~= 0 then return raknetBitStreamDecodeString(bs, len + enc), kind end
        return raknetBitStreamReadString(bs, len), kind
    end)
    pcall(raknetBitStreamResetReadPointer, bs)
    if ok then return text, kind end
end

local function onPacket(id, bs)
    if id ~= 220 or (st.mode ~= 'await' and st.mode ~= 'place') then return end
    local text, kind = readCef(bs)
    if not text then return end

    if st.mode == 'await' then
        if kind == 84 and text:find('"items"', 1, true) then
            local utf = u8(text)
            if utf:find(MENU_TITLE, 1, true) then
                st.menuId = tonumber(utf:match('"id"%s*:%s*(%d+)%s*,%s*"title"%s*:%s*"' .. MENU_TITLE .. '"'))
                st.ready = st.ready or os.clock()
            end
        end
        return
    end

    if kind ~= 17 or not text:find('cef.addNotification', 1, true) then return end
    if not text:find('"type"%s*:%s*"error"') then return end
    local desc = text:match('"description"%s*:%s*"(.-)"')
    st.err = ('Остановлено: %s (выставлено %d из %d)'):format(desc and u8(desc) or 'неизвестная ошибка', st.done, st.total)
    st.mode, st.cur, st.queue = 'idle', nil, {}
    st.closeUntil = os.clock() + 3
end

if not pcall(addEventHandler, 'onReceivePacket', onPacket) then
    onReceivePacket = onPacket
end

local bg = V4(0.043, 0.039, 0.082, 0.985)
local card = V4(0.082, 0.073, 0.148, 1)
local rowBg = V4(0.108, 0.095, 0.190, 1)
local accent = V4(0.60, 0.38, 1.00, 1)
local accentDark = V4(0.44, 0.24, 0.92, 1)
local blue = V4(0.25, 0.55, 1.00, 1)
local textCol = V4(0.95, 0.94, 1.00, 1)
local dim = V4(0.62, 0.58, 0.78, 1)
local green = V4(0.20, 0.85, 0.45, 1)
local white = V4(1, 1, 1, 1)
local clear = V4(0, 0, 0, 0)
local blueA, blueB = V4(0.52, 0.30, 1.0, 1), V4(0.22, 0.50, 1.0, 1)
local redA, redB = V4(0.62, 0.14, 0.26, 1), V4(0.42, 0.08, 0.18, 1)

local fade, fadeTo, frameDt, lastFrame = 0, 0, 0.016, os.clock()

local function rgba(c)
    return imgui.ColorConvertFloat4ToU32(V4(c.x, c.y, c.z, c.w * fade))
end

local function shade(c, k)
    return V4(min(c.x * k, 1), min(c.y * k, 1), min(c.z * k, 1), c.w)
end

local function fill(dl, x, y, w, h, c, r)
    dl:AddRectFilled(V2(x, y), V2(x + w, y + h), rgba(c), r or 0)
end

local function outline(dl, x, y, w, h, c, r)
    dl:AddRect(V2(x, y), V2(x + w, y + h), rgba(c), r or 0, 0, LINE)
end

local function gradient(dl, x, y, w, h, r, c1, c2)
    r = min(r, w / 2, h / 2)
    local a, b = rgba(c1), rgba(c2)
    dl:AddRectFilled(V2(x, y), V2(x + w, y + h), b, r)
    dl:AddRectFilled(V2(x, y), V2(x + r * 2, y + h), a, r)
    dl:AddRectFilledMultiColor(V2(x + r, y), V2(x + w - r, y + h), a, b, b, a)
end

local function points(x, y, s, ...)
    local a, out = { ... }, {}
    for i = 1, #a, 2 do out[#out + 1] = V2(x + a[i] * s, y + a[i + 1] * s) end
    return out
end

local function polygon(dl, p, col)
    local n, area = #p, 0
    for i = 1, n do
        local a, b = p[i], p[i % n + 1]
        area = area + a.x * b.y - b.x * a.y
    end
    if area < 0 then
        local rev = {}
        for i = n, 1, -1 do rev[#rev + 1] = p[i] end
        p = rev
    end
    for i = 2, n - 1 do dl:AddTriangleFilled(p[1], p[i], p[i + 1], col) end
end

local function polyline(dl, p, col, th, closed)
    for i = 1, closed and #p or #p - 1 do
        dl:AddLine(p[i], p[i % #p + 1], col, th)
    end
    for i = 1, #p do dl:AddCircleFilled(p[i], th / 2, col) end
end

local function icon(dl, kind, x, y, s, c, hole)
    local col = rgba(c)
    local cut = rgba(hole or card)
    local function P(fx, fy) return V2(x + fx * s, y + fy * s) end
    local function pts(...) return points(x, y, s, ...) end
    if kind == 'cart' then
        polyline(dl, pts(0.02, 0.14, 0.20, 0.14, 0.34, 0.66, 0.90, 0.66), col, s * 0.10)
        polygon(dl, pts(0.25, 0.28, 0.98, 0.28, 0.87, 0.55, 0.33, 0.55), col)
        dl:AddCircleFilled(P(0.45, 0.86), s * 0.09, col)
        dl:AddCircleFilled(P(0.80, 0.86), s * 0.09, col)
    elseif kind == 'info' then
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.5, col)
        dl:AddCircleFilled(P(0.5, 0.29), s * 0.075, cut)
        polyline(dl, pts(0.5, 0.46, 0.5, 0.73), cut, s * 0.13)
    elseif kind == 'gear' then
        for i = 0, 7 do
            local a = i * math.pi / 4
            local dx, dy = math.cos(a), math.sin(a)
            local function G(r, w) return P(0.5 + dx * r - dy * w, 0.5 + dy * r + dx * w) end
            polygon(dl, { G(0.30, -0.095), G(0.30, 0.095), G(0.49, 0.072), G(0.49, -0.072) }, col)
        end
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.37, col)
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.15, cut)
    elseif kind == 'crown' then
        polygon(dl, pts(0.06, 0.08, 0.01, 0.76, 0.44, 0.76), col)
        polygon(dl, pts(0.94, 0.08, 0.56, 0.76, 0.99, 0.76), col)
        polygon(dl, pts(0.50, 0.00, 0.17, 0.76, 0.83, 0.76), col)
        dl:AddRectFilled(P(0, 0.80), P(1, 0.98), col, s * 0.07)
    elseif kind == 'plane' then
        polygon(dl, pts(0.02, 0.47, 0.98, 0.04, 0.40, 0.66), col)
        polygon(dl, pts(0.98, 0.04, 0.40, 0.66, 0.62, 0.98), rgba(shade(c, 0.8)))
        polygon(dl, pts(0.40, 0.66, 0.62, 0.98, 0.40, 0.92), rgba(shade(c, 0.58)))
    elseif kind == 'trash' then
        local th = max(1.6, s * 0.09)
        polyline(dl, pts(0.10, 0.25, 0.90, 0.25), col, th)
        polyline(dl, pts(0.36, 0.25, 0.36, 0.10, 0.64, 0.10, 0.64, 0.25), col, th)
        polyline(dl, pts(0.20, 0.35, 0.26, 0.92, 0.74, 0.92, 0.80, 0.35), col, th)
        polyline(dl, pts(0.42, 0.47, 0.42, 0.78), col, th)
        polyline(dl, pts(0.58, 0.47, 0.58, 0.78), col, th)
    elseif kind == 'bolt' then
        local p = pts(0.66, 0.00, 0.14, 0.58, 0.47, 0.58, 0.36, 1.00, 0.90, 0.38, 0.56, 0.38)
        polygon(dl, { p[1], p[2], p[3], p[6] }, col)
        polygon(dl, { p[6], p[3], p[4], p[5] }, col)
    elseif kind == 'refresh' then
        local a0, a1 = math.rad(-30), math.rad(262)
        local arc = {}
        for i = 0, 20 do
            local a = a0 + (a1 - a0) * i / 20
            arc[#arc + 1] = P(0.5 + math.cos(a) * 0.33, 0.54 + math.sin(a) * 0.33)
        end
        polyline(dl, arc, col, max(1.8, s * 0.11))
        local ex, ey = 0.5 + math.cos(a1) * 0.33, 0.54 + math.sin(a1) * 0.33
        local tx, ty, nx, ny = -math.sin(a1), math.cos(a1), math.cos(a1), math.sin(a1)
        polygon(dl, { P(ex + tx * 0.20, ey + ty * 0.20), P(ex + nx * 0.15, ey + ny * 0.15), P(ex - nx * 0.15, ey - ny * 0.15) }, col)
    end
end

local PALETTE = {
    V4(0.95, 0.75, 0.20, 1), V4(0.35, 0.70, 1.00, 1), V4(0.65, 0.45, 1.00, 1), V4(0.25, 0.85, 0.60, 1),
    V4(1.00, 0.50, 0.35, 1), V4(0.90, 0.45, 0.80, 1), V4(0.55, 0.80, 0.35, 1), V4(0.86, 0.88, 0.97, 1),
}
local GOLD, CYAN, GRAY = V4(0.98, 0.78, 0.20, 1), V4(0.30, 0.80, 1.00, 1), V4(0.62, 0.66, 0.78, 1)
local KEYWORDS = {
    { 'слит', 5, GOLD }, { 'алмаз', 0, CYAN }, { 'бриллиант', 0, CYAN }, { 'монет', 2, GOLD },
    { 'ящик', 1, GRAY }, { 'кирпич', 5, V4(0.85, 0.40, 0.25, 1) }, { 'железо', 5, GRAY }, { 'сталь', 5, GRAY },
    { 'пластик', 4, V4(0.30, 0.60, 1.00, 1) }, { 'зелье', 4, V4(0.65, 0.45, 1.00, 1) },
    { 'компонент', 3, V4(0.35, 0.60, 1.00, 1) }, { 'видеокарт', 3, V4(0.25, 0.85, 0.60, 1) },
    { 'усы', 1, V4(0.86, 0.88, 0.97, 1) },
}

local function itemLook(it)
    if not it.shape then
        for _, k in ipairs(KEYWORDS) do
            if it.l and it.l:find(k[1], 1, true) then
                it.shape, it.color = k[2], k[3]
                break
            end
        end
        if not it.shape then
            it.shape = (it.id * 13 + 3) % 7
            it.color = PALETTE[(it.id * 5 + 1) % #PALETTE + 1]
        end
    end
    return it.shape, it.color
end

local function itemShape(dl, x, y, s, it)
    local shape, c = itemLook(it)
    local base, light, dark = rgba(c), rgba(shade(c, 1.3)), rgba(shade(c, 0.55))
    local function P(fx, fy) return V2(x + fx * s, y + fy * s) end
    local function pts(...) return points(x, y, s, ...) end
    if shape == 0 then
        polygon(dl, pts(0.20, 0.12, 0.80, 0.12, 1.00, 0.38, 0.00, 0.38), light)
        polygon(dl, pts(0.00, 0.38, 0.50, 0.38, 0.50, 0.96), dark)
        polygon(dl, pts(0.50, 0.38, 1.00, 0.38, 0.50, 0.96), base)
    elseif shape == 1 then
        polygon(dl, pts(0.05, 0.27, 0.50, 0.51, 0.50, 0.97, 0.05, 0.73), base)
        polygon(dl, pts(0.50, 0.51, 0.95, 0.27, 0.95, 0.73, 0.50, 0.97), dark)
        polygon(dl, pts(0.50, 0.03, 0.95, 0.27, 0.50, 0.51, 0.05, 0.27), light)
    elseif shape == 2 then
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.48, dark, 24)
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.42, base, 24)
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.18, light, 16)
    elseif shape == 3 then
        dl:AddRectFilled(P(0.12, 0.12), P(0.88, 0.88), base, s * 0.18)
        dl:AddRectFilled(P(0.27, 0.27), P(0.73, 0.73), dark, s * 0.09)
        dl:AddRectFilled(P(0.38, 0.38), P(0.62, 0.62), light, s * 0.06)
    elseif shape == 4 then
        dl:AddRectFilled(P(0.35, 0.02), P(0.65, 0.16), dark, s * 0.05)
        dl:AddRectFilled(P(0.40, 0.12), P(0.60, 0.42), light, s * 0.04)
        dl:AddRectFilled(P(0.19, 0.34), P(0.81, 0.97), base, s * 0.18)
        dl:AddRectFilled(P(0.28, 0.50), P(0.38, 0.86), light, s * 0.05)
    elseif shape == 5 then
        polygon(dl, pts(0.25, 0.22, 0.96, 0.22, 0.80, 0.46, 0.04, 0.46), light)
        polygon(dl, pts(0.04, 0.46, 0.80, 0.46, 0.80, 0.80, 0.04, 0.80), base)
        polygon(dl, pts(0.80, 0.46, 0.96, 0.22, 0.96, 0.56, 0.80, 0.80), dark)
    else
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.48, base, 24)
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.34, dark, 20)
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.27, base, 20)
        dl:AddCircleFilled(P(0.5, 0.5), s * 0.13, light, 12)
    end
end

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, e = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + e * 16777216
end

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CODE_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function huffman(lengths, n)
    local count, symbol, offs = {}, {}, { [1] = 0 }
    for i = 0, 15 do count[i] = 0 end
    for i = 0, n - 1 do count[lengths[i]] = count[lengths[i]] + 1 end
    for i = 1, 14 do offs[i + 1] = offs[i] + count[i] end
    for i = 0, n - 1 do
        local len = lengths[i]
        if len ~= 0 then
            symbol[offs[len]] = i
            offs[len] = offs[len] + 1
        end
    end
    return { count = count, symbol = symbol }
end

local fixedLit, fixedDist
local function fixedTables()
    if fixedLit then return fixedLit, fixedDist end
    local l = {}
    for i = 0, 143 do l[i] = 8 end
    for i = 144, 255 do l[i] = 9 end
    for i = 256, 279 do l[i] = 7 end
    for i = 280, 287 do l[i] = 8 end
    local dd = {}
    for i = 0, 29 do dd[i] = 5 end
    fixedLit, fixedDist = huffman(l, 288), huffman(dd, 30)
    return fixedLit, fixedDist
end

local function inflate(src)
    local pos, buf, cnt = 1, 0, 0
    local out, n = {}, 0

    local function bits(need)
        local v = buf
        while cnt < need do
            v = bit.bor(v, bit.lshift(src:byte(pos), cnt))
            pos = pos + 1
            cnt = cnt + 8
        end
        buf = bit.rshift(v, need)
        cnt = cnt - need
        return bit.band(v, bit.lshift(1, need) - 1)
    end

    local function decode(h)
        local code, first, index = 0, 0, 0
        for len = 1, 15 do
            code = bit.bor(code, bits(1))
            local c = h.count[len]
            if code - c < first then return h.symbol[index + (code - first)] end
            index = index + c
            first = (first + c) * 2
            code = code * 2
        end
        error('bad code')
    end

    local function codes(lit, dist)
        while true do
            local sym = decode(lit)
            if sym < 256 then
                n = n + 1
                out[n] = sym
            elseif sym == 256 then
                return
            else
                sym = sym - 257
                local len = LEN_BASE[sym + 1] + bits(LEN_EXTRA[sym + 1])
                local ds = decode(dist)
                local back = DIST_BASE[ds + 1] + bits(DIST_EXTRA[ds + 1])
                for _ = 1, len do
                    n = n + 1
                    out[n] = out[n - back]
                end
            end
        end
    end

    repeat
        local last, kind = bits(1), bits(2)
        if kind == 0 then
            buf, cnt = 0, 0
            local len = u16(src, pos)
            pos = pos + 4
            for i = 0, len - 1 do out[n + i + 1] = src:byte(pos + i) end
            n, pos = n + len, pos + len
        elseif kind == 1 then
            codes(fixedTables())
        elseif kind == 2 then
            local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
            local lengths = {}
            for i = 0, 18 do lengths[i] = 0 end
            for i = 1, ncode do lengths[CODE_ORDER[i]] = bits(3) end
            local lencode = huffman(lengths, 19)
            local all, i = {}, 0
            while i < nlen + ndist do
                local sym = decode(lencode)
                if sym < 16 then
                    all[i] = sym
                    i = i + 1
                else
                    local prev, rep = 0, 0
                    if sym == 16 then
                        prev, rep = all[i - 1], 3 + bits(2)
                    elseif sym == 17 then
                        rep = 3 + bits(3)
                    else
                        rep = 11 + bits(7)
                    end
                    for _ = 1, rep do
                        all[i] = prev
                        i = i + 1
                    end
                end
            end
            local lit, dist = {}, {}
            for k = 0, nlen - 1 do lit[k] = all[k] end
            for k = 0, ndist - 1 do dist[k] = all[nlen + k] end
            codes(huffman(lit, nlen), huffman(dist, ndist))
        else
            error('bad block')
        end
    until last == 1

    local parts = {}
    for i = 1, n, 4096 do
        parts[#parts + 1] = string.char(unpack(out, i, min(i + 4095, n)))
    end
    return table.concat(parts)
end

local ICON_DIR = getWorkingDirectory() .. '/resource/autobuy_icons/'
local zip = {}
local icons = { tex = {}, ready = {}, want = {}, order = {}, budget = 2 }

local function zipPaths()
    local list = {
        '/storage/emulated/0/Android/data/com.rodina21.game.web/files/models.zip',
        '/sdcard/Android/data/com.rodina21.game.web/files/models.zip',
        getWorkingDirectory() .. '/../models.zip',
    }
    local ok, game = pcall(getGameDirectory)
    if ok and game then list[#list + 1] = game .. '/models.zip' end
    return list
end

local function openZip()
    for _, path in ipairs(zipPaths()) do
        local f = io.open(path, 'rb')
        if f then
            local size = f:seek('end')
            local tailLen = min(size, 65557)
            f:seek('set', size - tailLen)
            local tail = f:read(tailLen)
            local at
            for i = #tail - 21, 1, -1 do
                if tail:sub(i, i + 3) == 'PK\5\6' then
                    at = i
                    break
                end
            end
            if at then
                local count, dirSize, dirOff = u16(tail, at + 10), u32(tail, at + 12), u32(tail, at + 16)
                f:seek('set', dirOff)
                local dir = f:read(dirSize)
                local entries, p = {}, 1
                for _ = 1, count do
                    if dir:sub(p, p + 3) ~= 'PK\1\2' then break end
                    local nameLen, extraLen, noteLen = u16(dir, p + 28), u16(dir, p + 30), u16(dir, p + 32)
                    local id = dir:sub(p + 46, p + 45 + nameLen):match('^items/(%d+)%.webp$')
                    if id then
                        entries[tonumber(id)] = { off = u32(dir, p + 42), method = u16(dir, p + 10), size = u32(dir, p + 20) }
                    end
                    p = p + 46 + nameLen + extraLen + noteLen
                end
                zip.file, zip.entries = f, entries
                return true
            end
            f:close()
        end
    end
    return false
end

local function readIcon(id)
    local e = zip.entries[id]
    if not e then return end
    zip.file:seek('set', e.off)
    local head = zip.file:read(30)
    zip.file:seek('set', e.off + 30 + u16(head, 27) + u16(head, 29))
    local data = zip.file:read(e.size)
    if e.method == 0 then return data end
    if e.method == 8 then return inflate(data) end
end

local function convertToPng(id, data)
    local png = ICON_DIR .. id .. '.png'
    if doesFileExist(png) then return png end
    local webp = ICON_DIR .. id .. '.webp'
    local f = io.open(webp, 'wb')
    if not f then return end
    f:write(data)
    f:close()
    local ok = pcall(function()
        local env = require('android.jnienv')
        local util = require('android.jnienv-util')
        local jin, jout = env.NewStringUTF(webp), env.NewStringUTF(png)
        local bitmap = util.CallStaticObjectMethod('android/graphics/BitmapFactory', 'decodeFile', '(Ljava/lang/String;)Landroid/graphics/Bitmap;', jin)
        assert(bitmap ~= nil, 'decode failed')
        local format = util.GetStaticObjectField('android/graphics/Bitmap$CompressFormat', 'PNG', 'Landroid/graphics/Bitmap$CompressFormat;')
        local stream = util.CallConstructor('java/io/FileOutputStream', '(Ljava/lang/String;)V', jout)
        util.CallBooleanMethod(bitmap, 'compress', '(Landroid/graphics/Bitmap$CompressFormat;ILjava/io/OutputStream;)Z', format, ffi.cast('jint', 100), stream)
        util.CallVoidMethod(stream, 'close', '()V')
        util.CallVoidMethod(bitmap, 'recycle', '()V')
        for _, ref in ipairs({ jin, jout, format, stream, bitmap }) do env.DeleteLocalRef(ref) end
    end)
    os.remove(webp)
    if ok and doesFileExist(png) then return png end
end

local function prepareIcon(id)
    local cached = ICON_DIR .. id .. '.png'
    if cfg.pngIcons and doesFileExist(cached) then
        icons.ready[id] = { path = cached }
        return
    end
    local ok, data = pcall(readIcon, id)
    if not ok or not data then
        icons.tex[id] = false
    elseif cfg.pngIcons then
        local png = convertToPng(id, data)
        if png then
            icons.ready[id] = { path = png }
        else
            icons.tex[id] = false
        end
    else
        icons.ready[id] = { data = data }
    end
end

local function iconWorker()
    if not openZip() then
        icons.off = true
        return
    end
    createDirectory(getWorkingDirectory() .. '/resource')
    createDirectory(ICON_DIR)
    while true do
        wait(30)
        local handled = 0
        for id in pairs(icons.want) do
            icons.want[id] = nil
            prepareIcon(id)
            handled = handled + 1
            if handled >= 3 then break end
        end
    end
end

local function iconTexture(id)
    local tex = icons.tex[id]
    if tex ~= nil then return tex end
    if icons.off then return false end
    local src = icons.ready[id]
    if not src then
        icons.want[id] = true
        return
    end
    if icons.budget <= 0 then return end
    icons.budget = icons.budget - 1
    icons.ready[id] = nil
    local ok, handle = pcall(function()
        if src.data then return imgui.CreateTextureFromMemory(src.data) end
        return imgui.CreateTextureFromFile(src.path)
    end)
    if ok and handle and handle ~= 0 then
        icons.tex[id] = handle
        icons.order[#icons.order + 1] = id
        if #icons.order > 400 then
            for _ = 1, 100 do
                local old = table.remove(icons.order, 1)
                pcall(imgui.ReleaseTexture, icons.tex[old])
                icons.tex[old] = nil
            end
        end
        return handle
    end
    if src.data then
        cfg.pngIcons = true
        dirty = true
        icons.want[id] = true
        return
    end
    icons.tex[id] = false
    return false
end

local function itemIcon(dl, x, y, s, it)
    local tex = iconTexture(it.id)
    if tex then
        dl:AddImage(tex, V2(x, y), V2(x + s, y + s), V2(0, 0), V2(1, 1), rgba(white))
    else
        itemShape(dl, x, y, s, it)
    end
end

local WF = imgui.WindowFlags
local NO_SCROLL = WF.NoScrollbar + WF.NoScrollWithMouse

local scrolls = {}
local dragged = 0
local function isDragging() return dragged > d(8) end

local function touchScroll(key, skipWhenActive)
    local s = scrolls[key]
    if not s then
        s = { down = false, y = 0, speed = 0 }
        scrolls[key] = s
    end
    local down = imgui.IsMouseDown(0)
    if down and skipWhenActive and imgui.IsAnyItemActive() then
        s.down, s.speed = false, 0
        return
    end
    if down and (s.down or imgui.IsWindowHovered(imgui.HoveredFlags.ChildWindows)) then
        local y = imgui.GetIO().MousePos.y
        if s.down then
            local dy = y - s.y
            dragged = dragged + math.abs(dy)
            imgui.SetScrollY(imgui.GetScrollY() - dy)
            s.speed = s.speed * 0.6 - dy / frameDt * 0.4
        else
            s.speed = 0
        end
        s.down, s.y = true, y
        return
    end
    s.down = false
    if math.abs(s.speed) > d(30) then
        local top = imgui.GetScrollMaxY()
        local y = imgui.GetScrollY() + s.speed * frameDt
        if y < 0 or y > top then s.speed = 0 end
        imgui.SetScrollY(max(0, min(y, top)))
        s.speed = s.speed * max(0, 1 - frameDt * 4.5)
    else
        s.speed = 0
    end
end

local function beginCard(id, w, h, pad)
    imgui.PushStyleColor(imgui.Col.ChildBg, card)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, d(10))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(pad, pad))
    imgui.BeginChild(id, V2(w, h), 1, NO_SCROLL)
    imgui.PopStyleVar(2)
    imgui.PopStyleColor()
end

local function beginScroll(id)
    imgui.PushStyleColor(imgui.Col.ChildBg, clear)
    imgui.BeginChild(id, V2(0, 0), false, 0)
    imgui.PopStyleColor()
end

local function centered(s, col)
    imgui.SetCursorPosX(max(0, (imgui.GetWindowWidth() - imgui.CalcTextSize(s).x) / 2))
    imgui.TextColored(col or textCol, s)
end

local function button(id, w, h, label, c1, c2, ic)
    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(id, V2(w, h))
    local down = imgui.IsItemActive()
    local k = down and 0.8 or 1
    local y = p.y + (down and d(1) or 0)
    local dl = imgui.GetWindowDrawList()
    gradient(dl, p.x, y, w, h, d(10), shade(c1, k), shade(c2, k))
    outline(dl, p.x, y, w, h, V4(1, 1, 1, 0.2), d(10))
    local size = imgui.CalcTextSize(label)
    local iw = ic and d(22) or 0
    local x = p.x + (w - iw - size.x) / 2
    if ic then icon(dl, ic, x, y + (h - d(16)) / 2, d(16), white, c2) end
    dl:AddText(V2(x + iw, y + (h - size.y) / 2), rgba(white), label)
    return clicked
end

local function buttonWidth(label, ic)
    return imgui.CalcTextSize(label).x + (ic and d(22) or 0) + d(28)
end

local function iconButton(id, kind, size, col)
    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(id, V2(size, size))
    local down = imgui.IsItemActive()
    local dl = imgui.GetWindowDrawList()
    fill(dl, p.x, p.y, size, size, down and V4(0.30, 0.20, 0.60, 1) or V4(0.14, 0.12, 0.26, 1), d(8))
    outline(dl, p.x, p.y, size, size, V4(0.55, 0.38, 1.0, 0.55), d(8))
    local pad = size * 0.24
    icon(dl, kind, p.x + pad, p.y + pad, size - pad * 2, down and shade(col, 1.3) or col)
    return clicked
end

local function toggle(id, key)
    local w, h = d(46), d(26)
    local p = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton(id, V2(w, h)) then
        cfg[key] = not cfg[key]
        dirty = true
    end
    local on = cfg[key]
    local dl = imgui.GetWindowDrawList()
    fill(dl, p.x, p.y, w, h, on and accentDark or V4(0.20, 0.18, 0.32, 1), h / 2)
    dl:AddCircleFilled(V2(p.x + (on and w - h / 2 or h / 2), p.y + h / 2), h / 2 - d(3), rgba(white), 20)
end

local function pill(id, w, h, label, active)
    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(id, V2(w, h))
    local dl = imgui.GetWindowDrawList()
    fill(dl, p.x, p.y, w, h, active and accentDark or V4(0.16, 0.14, 0.28, 1), h / 2)
    local size = imgui.CalcTextSize(label)
    dl:AddText(V2(p.x + (w - size.x) / 2, p.y + (h - size.y) / 2), rgba(active and white or dim), label)
    return clicked
end

local function progress(w, h, frac)
    local p = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    fill(dl, p.x, p.y, w, h, V4(0.035, 0.03, 0.08, 1), h / 2)
    if frac then
        gradient(dl, p.x, p.y, max(h, w * frac), h, h / 2, V4(0.55, 0.32, 1, 1), V4(0.25, 0.55, 1, 1))
    else
        local len = w * 0.3
        local from = ((os.clock() * 0.9) % 1) * (w + len) - len
        local x0, x1 = max(0, from), min(w, from + len)
        if x1 > x0 then gradient(dl, p.x + x0, p.y, x1 - x0, h, h / 2, V4(0.55, 0.32, 1, 0.5), V4(0.25, 0.55, 1, 1)) end
    end
    imgui.Dummy(V2(w, h))
end

local function cardTitle(kind, title, col)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local s = d(30)
    fill(dl, p.x, p.y, s, s, V4(col.x, col.y, col.z, 0.16), d(9))
    outline(dl, p.x, p.y, s, s, V4(col.x, col.y, col.z, 0.45), d(9))
    icon(dl, kind, p.x + d(6), p.y + d(6), s - d(12), col)
    imgui.SetCursorScreenPos(V2(p.x + s + d(10), p.y + (s - imgui.GetTextLineHeight()) / 2))
    imgui.Text(title)
    imgui.SetCursorScreenPos(V2(p.x, p.y + s + d(8)))
end

local filtered, lastQuery, lastVer = {}, nil, -1
local scrollTop = false
local function filteredItems()
    local q = lower(str(ui.search))
    if q ~= lastQuery or lastVer ~= dbVer then
        filtered = {}
        local num = tonumber(q)
        for _, it in ipairs(db.items) do
            if q == '' or it.l:find(q, 1, true) or (num and tostring(it.id):find(q, 1, true)) then
                filtered[#filtered + 1] = it
            end
        end
        lastQuery, lastVer = q, dbVer
        scrollTop = true
    end
    return filtered
end

local function drawVisible(list, heightOf, drawRow, sel)
    local top, view = imgui.GetScrollY(), imgui.GetWindowHeight()
    local y, skipped = 0, 0
    for _, it in ipairs(list) do
        local h = heightOf(it)
        if y + h < top - h or y > top + view + h then
            skipped = skipped + h + GAP
        else
            if skipped > 0 then
                imgui.Dummy(V2(1, skipped - GAP))
                skipped = 0
            end
            drawRow(it, h, sel)
        end
        y = y + h + GAP
    end
    if skipped > 0 then imgui.Dummy(V2(1, skipped - GAP)) end
end

local function toggleItem(it, sel)
    if sel[it.id] ~= nil then
        sel[it.id] = nil
    else
        sel[it.id] = (it.cur or 0) > 0 and it.cur or 0
    end
    priceBuf[it.id] = nil
    selectionChanged()
end

local function itemRowLeft(it, h, sel)
    imgui.PushIDInt(it.id)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    local clicked = imgui.InvisibleButton('##row', V2(w, h))
    local on = sel[it.id] ~= nil
    local bgCol = on and V4(0.09, 0.20, 0.18, 1) or rowBg
    if imgui.IsItemActive() then bgCol = V4(0.20, 0.16, 0.36, 1) end
    fill(dl, p.x, p.y, w, h, bgCol, d(9))
    outline(dl, p.x, p.y, w, h, on and V4(0.2, 0.85, 0.45, 0.55) or V4(0.6, 0.4, 1, 0.14), d(9))
    if on then fill(dl, p.x, p.y + d(10), d(3), h - d(20), green, 2) end
    if clicked and not isDragging() then toggleItem(it, sel) end

    itemIcon(dl, p.x + d(9), p.y + (h - d(30)) / 2, d(30), it)

    local cx, cy, r = p.x + w - d(24), p.y + h / 2, d(12)
    if on then
        dl:AddCircleFilled(V2(cx, cy), r, rgba(green), 24)
        polyline(dl, { V2(cx - r * 0.45, cy), V2(cx - r * 0.1, cy + r * 0.4), V2(cx + r * 0.5, cy - r * 0.35) }, rgba(V4(0.02, 0.10, 0.05, 1)), d(2.2))
    else
        local line = rgba(V4(0.62, 0.58, 0.78, 0.9))
        dl:AddCircle(V2(cx, cy), r, line, 24, LINE * 1.5)
        dl:AddLine(V2(cx - r * 0.45, cy), V2(cx + r * 0.45, cy), line, LINE * 1.6)
        dl:AddLine(V2(cx, cy - r * 0.45), V2(cx, cy + r * 0.45), line, LINE * 1.6)
    end

    imgui.PushClipRect(V2(p.x + d(46), p.y), V2(p.x + w - d(42), p.y + h), true)
    imgui.SetCursorScreenPos(V2(p.x + d(48), p.y + d(5)))
    imgui.Text(it.name)
    imgui.PushFont(fSmall)
    imgui.SetCursorScreenPos(V2(p.x + d(48), p.y + h - d(5) - imgui.GetTextLineHeight()))
    imgui.TextColored(dim, 'Цена скупки: ')
    imgui.SameLine(0, 0)
    imgui.TextColored((it.cur or 0) > 0 and accent or dim, price(it.cur))
    imgui.PopFont()
    imgui.PopClipRect()

    imgui.SetCursorScreenPos(p)
    imgui.Dummy(V2(w, h))
    imgui.PopID()
end

local function itemRowRight(it, h, sel)
    imgui.PushIDInt(it.id)
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    fill(dl, p.x, p.y, w, h, rowBg, d(9))
    outline(dl, p.x, p.y, w, h, V4(0.6, 0.4, 1, 0.16), d(9))
    fill(dl, p.x, p.y + d(10), d(3), ROW - d(20), accent, 2)
    itemIcon(dl, p.x + d(9), p.y + (ROW - d(30)) / 2, d(30), it)

    local removeX = p.x + w - BTN - d(8)
    local fieldW = d(104)
    local fieldX = removeX - d(6) - fieldW

    imgui.PushClipRect(V2(p.x + d(46), p.y), V2(fieldX - d(4), p.y + ROW), true)
    imgui.SetCursorScreenPos(V2(p.x + d(48), p.y + d(5)))
    imgui.Text(it.name)
    imgui.PushFont(fSmall)
    imgui.SetCursorScreenPos(V2(p.x + d(48), p.y + ROW - d(5) - imgui.GetTextLineHeight()))
    imgui.TextColored(dim, 'Сейчас: ' .. price(it.cur))
    imgui.PopFont()
    imgui.PopClipRect()

    local frameH = imgui.GetFrameHeight()
    if editing == it.id then
        priceBuf[it.id] = priceBuf[it.id] or new.int(sel[it.id] or 0)
        local buf = priceBuf[it.id]
        imgui.SetCursorScreenPos(V2(fieldX, p.y + (ROW - frameH) / 2))
        imgui.PushItemWidth(fieldW)
        if editFocus then
            imgui.SetKeyboardFocusHere(0)
            editFocus = false
        end
        if imgui.InputInt('##pr', buf, 0, 0) then
            buf[0] = max(0, min(buf[0], 2000000000))
            sel[it.id] = buf[0]
            dirty = true
        end
        imgui.PopItemWidth()
        if imgui.IsItemDeactivated() then editing = nil end
    else
        local fh = d(32)
        imgui.SetCursorScreenPos(V2(fieldX, p.y + (ROW - fh) / 2))
        local fp = imgui.GetCursorScreenPos()
        if imgui.InvisibleButton('##pr', V2(fieldW, fh)) and not isDragging() then
            editing, editFocus = it.id, true
            priceBuf[it.id] = new.int(sel[it.id] or 0)
        end
        fill(dl, fp.x, fp.y, fieldW, fh, V4(0.055, 0.048, 0.110, 1), d(8))
        outline(dl, fp.x, fp.y, fieldW, fh, V4(0.6, 0.4, 1, 0.45), d(8))
        local txt = number(sel[it.id])
        local size = imgui.CalcTextSize(txt)
        dl:AddText(V2(fp.x + fieldW - size.x - d(10), fp.y + (fh - size.y) / 2), rgba(textCol), txt)
    end

    imgui.SetCursorScreenPos(V2(removeX, p.y + (ROW - BTN) / 2))
    local bp = imgui.GetCursorScreenPos()
    local removed = imgui.InvisibleButton('##rm', V2(BTN, BTN))
    fill(dl, bp.x, bp.y, BTN, BTN, imgui.IsItemActive() and V4(0.62, 0.13, 0.25, 1) or V4(0.20, 0.10, 0.18, 1), d(8))
    outline(dl, bp.x, bp.y, BTN, BTN, V4(1, 0.35, 0.45, 0.7), d(8))
    dl:AddLine(V2(bp.x + BTN * 0.3, bp.y + BTN / 2), V2(bp.x + BTN * 0.7, bp.y + BTN / 2), rgba(V4(1, 0.55, 0.62, 1)), LINE * 2)
    if removed and not isDragging() then
        sel[it.id] = nil
        priceBuf[it.id] = nil
        if editing == it.id then editing = nil end
        selectionChanged()
    end

    if DAYS_ITEMS[it.id] then
        local days = cfg.days[it.id] or -1
        local y = p.y + ROW
        imgui.PushFont(fSmall)
        imgui.SetCursorScreenPos(V2(p.x + d(12), y + (DAYS_ROW - imgui.GetTextLineHeight()) / 2))
        imgui.TextColored(dim, 'Срок скупки:')
        imgui.PopFont()
        imgui.SetCursorScreenPos(V2(p.x + d(104), y + d(3)))
        if pill('##forever', d(96), d(28), 'Навсегда', days == -1) and not isDragging() then
            days = days == -1 and 30 or -1
            cfg.days[it.id] = days
            daysBuf[it.id] = nil
            dirty = true
        end
        if days ~= -1 then
            daysBuf[it.id] = daysBuf[it.id] or new.int(days)
            local buf = daysBuf[it.id]
            imgui.SetCursorScreenPos(V2(p.x + d(212), y + (DAYS_ROW - frameH) / 2))
            imgui.PushItemWidth(d(84))
            if imgui.InputInt('##days', buf, 0, 0) then
                buf[0] = max(1, min(buf[0], 9999))
                cfg.days[it.id] = buf[0]
                dirty = true
            end
            imgui.PopItemWidth()
            imgui.PushFont(fSmall)
            imgui.SetCursorScreenPos(V2(p.x + d(302), y + (DAYS_ROW - imgui.GetTextLineHeight()) / 2))
            imgui.TextColored(dim, 'дн.')
            imgui.PopFont()
        end
    end

    imgui.SetCursorScreenPos(p)
    imgui.Dummy(V2(w, h))
    imgui.PopID()
end

local function beginList(id)
    imgui.PushStyleColor(imgui.Col.ChildBg, clear)
    imgui.BeginChild(id, V2(0, 0), false, 0)
    imgui.PopStyleColor()
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(d(6), GAP))
end

local function endList()
    imgui.PopStyleVar()
    imgui.EndChild()
end

local function listLeft(sel)
    local list = filteredItems()
    beginList('##leftlist')
    touchScroll('left')
    if scrollTop then
        scrollTop = false
        imgui.SetScrollY(0)
    end
    if #list > 0 then
        drawVisible(list, function() return ROW end, itemRowLeft, sel)
    else
        local w, h = imgui.GetWindowWidth(), imgui.GetWindowHeight()
        if #db.items == 0 then
            imgui.SetCursorPosY(max(0, h / 2 - d(52)))
            centered('Список товаров пуст', textCol)
            centered('Загрузим все предметы ломбарда', dim)
            imgui.Dummy(V2(1, d(4)))
            imgui.SetCursorPosX((w - d(190)) / 2)
            if button('##loadlist', d(190), d(38), 'Загрузить список', blueA, blueB, 'refresh') and not isDragging() then
                startScan()
            end
        else
            imgui.SetCursorPosY(max(0, h / 2 - d(20)))
            centered('Ничего не найдено', textCol)
            centered('Попробуйте другое название', dim)
        end
    end
    endList()
end

local function listRight(sel)
    local list = pickedItems()
    beginList('##rightlist')
    touchScroll('right')
    if #list > 0 then
        drawVisible(list, function(it) return DAYS_ITEMS[it.id] and ROW + DAYS_ROW or ROW end, itemRowRight, sel)
    else
        imgui.SetCursorPosY(max(0, imgui.GetWindowHeight() / 2 - d(30)))
        centered('Пока ничего не выбрано', textCol)
        centered('Нажмите на товар слева', dim)
    end
    endList()
end

local function paneLeft(sel)
    local frameH = imgui.GetFrameHeight()
    imgui.PushItemWidth(imgui.GetContentRegionAvail().x - frameH - d(6))
    imgui.InputTextWithHint('##search', 'Поиск среди ' .. #db.items .. ' товаров (название или ID)', ui.search, ffi.sizeof(ui.search))
    imgui.PopItemWidth()
    imgui.SameLine(0, d(6))
    if iconButton('##refresh', 'refresh', frameH, accent) and not isDragging() then startScan() end
    listLeft(sel)
end

local function paneRight(sel)
    local frameH = imgui.GetFrameHeight()
    local width = imgui.GetWindowWidth()
    local count = #pickedItems()
    local y = imgui.GetCursorPosY()
    imgui.PushFont(fSmall)
    imgui.SetCursorPosY(y + (frameH - imgui.GetTextLineHeight()) / 2)
    imgui.TextColored(dim, 'Выбрано: ' .. count .. (width > d(380) and '  |  нажмите на цену, чтобы изменить' or ''))
    imgui.PopFont()
    imgui.SameLine(width - d(8) - frameH)
    imgui.SetCursorPosY(y)
    if iconButton('##clr', 'trash', frameH, V4(1, 0.30, 0.40, 1)) and count > 0 and not isDragging() then
        cfg.configs[cfg.active] = {}
        resetEdit()
        selectionChanged()
    end
    listRight(cfg.configs[cfg.active])
end

local function paneBusy(w, h)
    beginCard('##busy', w, h, d(12))
    local width = imgui.GetWindowWidth()
    local barW = min(width - d(40), d(380))
    imgui.SetCursorPosY(max(d(8), h / 2 - d(78)))
    imgui.PushFont(fBig)
    centered(st.title, textCol)
    imgui.PopFont()
    imgui.Dummy(V2(0, d(6)))
    local frac
    if st.mode == 'await' then
        centered('Откройте ломбард в меню бизнеса (/bmenu) и выберите его', dim)
    elseif st.mode == 'scan' then
        centered('Страница: ' .. st.page .. '  |  найдено товаров: ' .. st.found, dim)
    else
        centered('Выполнено: ' .. (st.done + st.fail) .. ' из ' .. st.total .. '  |  ошибок: ' .. st.fail, dim)
        frac = min((st.done + st.fail) / max(st.total, 1), 1)
    end
    imgui.Dummy(V2(0, d(8)))
    imgui.SetCursorPosX((width - barW) / 2)
    progress(barW, d(10), frac)
    imgui.Dummy(V2(0, d(16)))
    imgui.SetCursorPosX((width - d(160)) / 2)
    if button('##cancel', d(160), d(42), 'Отмена', redA, redB, 'trash') then stop('Операция отменена') end
    imgui.EndChild()
end

local function tabMain(w, h)
    local busy = st.mode ~= 'idle'
    local gap, top = d(8), d(46)

    imgui.SetCursorPos(V2(0, (top - imgui.GetFrameHeight()) / 2))
    imgui.PushItemWidth(d(150))
    if imgui.BeginCombo('##cfg', cfg.active) then
        for _, name in ipairs(configNames()) do
            if imgui.Selectable(name, name == cfg.active, 0, V2(0, d(34))) and name ~= cfg.active then
                cfg.active = name
                resetEdit()
                selectionChanged()
            end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth()

    imgui.SameLine(0, gap)
    imgui.SetCursorPosY((top - d(26)) / 2)
    toggle('##skip', 'skipsame')
    imgui.SameLine(0, d(8))
    imgui.SetCursorPosY((top - imgui.GetTextLineHeight()) / 2)
    imgui.Text(w < d(760) and 'Пропуск' or 'Пропускать уже выставленные')

    if not busy then
        local bh = d(40)
        local w1, w2 = buttonWidth('Выставить всё', true), buttonWidth('Снять всё', true)
        imgui.SetCursorPos(V2(w - w1 - w2 - gap, (top - bh) / 2))
        if button('##place', w1, bh, 'Выставить всё', blueA, blueB, 'plane') then startPlace(false) end
        imgui.SetCursorPos(V2(w - w2, (top - bh) / 2))
        if button('##remove', w2, bh, 'Снять всё', redA, redB, 'trash') then startPlace(true) end
    end

    local listH = h - top - gap
    imgui.SetCursorPos(V2(0, top + gap))
    if busy then
        paneBusy(w, listH)
        return
    end

    local leftW = floor((w - gap) / 2)
    local sel = cfg.configs[cfg.active]
    beginCard('##left', leftW, listH, d(8))
    paneLeft(sel)
    imgui.EndChild()
    imgui.SetCursorPos(V2(leftW + gap, top + gap))
    beginCard('##right', w - gap - leftW, listH, d(8))
    paneRight(sel)
    imgui.EndChild()
end

local STEPS = {
    'Откройте меню командой /skup и нажмите кнопку обновления рядом с поиском. Скрипт отправит /bmenu - выберите нужный ломбард в меню бизнеса, дальше он сам пролистает все страницы скупки и соберёт список товаров.',
    'Нажмите на товар слева, чтобы добавить его. Цену скупки меняйте справа: нажмите на цену и введите число.',
    '"Выставить всё" - скрипт откроет /bmenu (выберите ломбард) и сам введёт ID и цену для каждого выбранного товара. Если у вас несколько ломбардов - выбирайте нужный.',
    '"Снять всё" - так же, но ставит цену 0 для всех товаров, которые сейчас скупаются.',
    'Можно создать несколько конфигов (вкладка "Настройки") и быстро переключаться между ними в верхней панели.',
    'Если сервер не отвечает 10 секунд - операция сама отменяется. Кнопка "Отмена" останавливает её сразу.',
    'Для "Сертификата Дополнения VIP" в строке товара можно выбрать срок: "Навсегда" (отправится -1) или число дней.',
    'Иконки товаров берутся из models.zip игры (Android/data/com.rodina21.game.web/files). Если файла нет, рисуются значки-заглушки.',
    'Списки прокручиваются перетаскиванием пальцем. Размер меню меняется в настройках. Настройки сохраняются в moonloader/config/AutoBuyPawn_mobile.lua.',
}

local function tabInfo()
    beginScroll('##infoscroll')
    touchScroll('info', false)
    local gap, pad = d(8), d(12)
    local width = imgui.GetContentRegionAvail().x
    local colW = floor((width - gap) / 2)
    local textW = colW - pad * 2 - d(38)
    local function height(i)
        if not STEPS[i] then return 0 end
        return max(d(56), imgui.CalcTextSize(STEPS[i], nil, false, textW).y + pad * 2)
    end
    local function step(i, h)
        beginCard('##step' .. i, colW, h, pad)
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()
        local s = d(28)
        gradient(dl, wp.x + pad, wp.y + pad, s, s, s / 2, V4(0.55, 0.32, 1, 1), V4(0.30, 0.45, 1, 1))
        local num = tostring(i)
        local size = imgui.CalcTextSize(num)
        dl:AddText(V2(wp.x + pad + (s - size.x) / 2, wp.y + pad + (s - size.y) / 2), rgba(white), num)
        imgui.SetCursorPos(V2(pad + d(38), pad))
        imgui.TextWrapped(STEPS[i])
        imgui.EndChild()
    end
    for i = 1, #STEPS, 2 do
        local h = max(height(i), height(i + 1))
        step(i, h)
        if STEPS[i + 1] then
            imgui.SameLine(0, gap)
            step(i + 1, h)
        end
    end
    beginCard('##infofoot', width, d(64), pad)
    local wp = imgui.GetWindowPos()
    icon(imgui.GetWindowDrawList(), 'info', wp.x + pad, wp.y + d(18), d(26), accent)
    imgui.PushFont(fSmall)
    imgui.SetCursorPos(V2(d(50), d(10)))
    imgui.TextColored(dim, 'Команда открытия меню')
    imgui.SetCursorPos(V2(d(50), d(13) + imgui.GetTextLineHeight()))
    imgui.PopFont()
    imgui.TextColored(accent, '/skup')
    imgui.EndChild()
    imgui.EndChild()
end

local function tabSettings()
    beginScroll('##setscroll')
    touchScroll('settings', true)
    local gap, pad = d(8), d(12)
    local colW = floor((imgui.GetContentRegionAvail().x - gap) / 2)
    local inner = colW - pad * 2

    beginCard('##s1', colW, d(196), pad)
    cardTitle('bolt', 'Скорость работы', accent)
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local delay = ui.delay[0]
    local line = imgui.GetCursorScreenPos()
    imgui.PushFont(fBig)
    imgui.TextColored(accent, delay .. ' мс')
    imgui.PopFont()
    local mode = delay == 0 and 'Турбо' or (delay <= 80 and 'Быстро' or 'Безопасно')
    local mw, mh = imgui.CalcTextSize(mode).x + d(22), d(26)
    local mx = wp.x + colW - pad - mw
    fill(dl, mx, line.y, mw, mh, V4(accent.x, accent.y, accent.z, 0.18), mh / 2)
    outline(dl, mx, line.y, mw, mh, V4(accent.x, accent.y, accent.z, 0.5), mh / 2)
    dl:AddText(V2(mx + d(11), line.y + (mh - imgui.GetTextLineHeight()) / 2), rgba(accent), mode)
    imgui.PushItemWidth(-1)
    if imgui.SliderInt('##delay', ui.delay, 0, 800) then
        cfg.delay = ui.delay[0]
        dirty = true
    end
    imgui.PopItemWidth()
    imgui.PushStyleColor(imgui.Col.Text, dim)
    imgui.TextWrapped('0 = максимально быстро. Если сервер кикает или зависает - поставьте 30-80')
    imgui.PopStyleColor()
    imgui.EndChild()

    imgui.SameLine(0, gap)

    beginCard('##s2', colW, d(196), pad)
    cardTitle('plane', 'Конфиги', blue)
    imgui.TextColored(dim, 'Активный:')
    imgui.SameLine(0, d(8))
    imgui.TextColored(textCol, cfg.active)
    imgui.Dummy(V2(1, d(2)))
    local createW = buttonWidth('Создать')
    imgui.PushItemWidth(inner - createW - d(8))
    imgui.InputTextWithHint('##newcfg', 'Название нового конфига', ui.newName, ffi.sizeof(ui.newName))
    imgui.PopItemWidth()
    imgui.SameLine(0, d(8))
    if button('##mkcfg', createW, imgui.GetFrameHeight(), 'Создать', blueA, blueB) then
        local name = str(ui.newName):gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' and not cfg.configs[name] then
            cfg.configs[name] = {}
            cfg.active = name
            resetEdit()
            selectionChanged()
            ffi.fill(ui.newName, ffi.sizeof(ui.newName))
        end
    end
    imgui.Dummy(V2(1, d(2)))
    if button('##delcfg', inner, d(38), 'Удалить активный конфиг', redA, redB, 'trash') and #configNames() > 1 then
        cfg.configs[cfg.active] = nil
        cfg.active = configNames()[1]
        resetEdit()
        selectionChanged()
    end
    imgui.EndChild()

    beginCard('##s3', colW, d(150), pad)
    cardTitle('gear', 'Размер меню', blue)
    imgui.PushFont(fBig)
    imgui.TextColored(blue, ui.scale[0] .. '%')
    imgui.PopFont()
    imgui.PushItemWidth(-1)
    imgui.SliderInt('##scale', ui.scale, 60, 150, '%d%%')
    imgui.PopItemWidth()
    if imgui.IsItemDeactivatedAfterEdit() then
        cfg.scale = ui.scale[0]
        applyScale(cfg.scale)
        dirty = true
    end
    imgui.PushStyleColor(imgui.Col.Text, dim)
    imgui.TextWrapped('Применяется, когда отпустите ползунок')
    imgui.PopStyleColor()
    imgui.EndChild()

    imgui.SameLine(0, gap)

    beginCard('##s4', colW, d(150), pad)
    cardTitle('trash', 'Кэш списка', V4(1, 0.30, 0.42, 1))
    imgui.PushStyleColor(imgui.Col.Text, dim)
    imgui.TextWrapped('Удаляет сохранённый список товаров. Выбранные товары и конфиги не затрагиваются - список можно загрузить заново.')
    imgui.PopStyleColor()
    imgui.Dummy(V2(1, d(4)))
    if button('##clearcache', inner, d(38), 'Очистить список товаров', redA, redB, 'trash') then
        db.items, db.time = {}, 0
        reindex()
        dirty = true
    end
    imgui.EndChild()

    beginCard('##s5', colW * 2 + gap, d(120), pad)
    cardTitle('crown', 'О скрипте', accent)
    for _, row in ipairs({ { 'Скрипт', 'Lombard Helper Mobile' }, { 'Версия', '1.0' }, { 'Автор', 'Edward' }, { 'Команда меню', '/skup' } }) do
        imgui.TextColored(dim, row[1] .. ':')
        imgui.SameLine(0, d(8))
        imgui.TextColored(accent, row[2])
        imgui.SameLine(0, d(24))
    end
    imgui.EndChild()

    imgui.Dummy(V2(1, d(4)))
    imgui.EndChild()
end

local TABS = { { 'АвтоСкуп', 'cart', '##tab1' }, { 'Инфо', 'info', '##tab2' }, { 'Настройки', 'gear', '##tab3' } }

local function drawHeader(w)
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local pad = d(10)

    icon(dl, 'crown', wp.x + pad, wp.y + d(12), d(28), accent, bg)
    imgui.PushFont(fBig)
    local titleW = imgui.CalcTextSize('Lombard Helper').x
    imgui.SetCursorPos(V2(pad + d(38), d(5)))
    imgui.TextColored(accent, 'Lombard Helper')
    imgui.PopFont()
    imgui.PushFont(fSmall)
    imgui.SetCursorPos(V2(pad + d(38), d(27)))
    imgui.TextColored(dim, 'AUTO BUY SYSTEM')
    imgui.PopFont()

    local x, th = pad + d(38) + titleW + d(18), d(36)
    for i, t in ipairs(TABS) do
        local tw = d(48) + imgui.CalcTextSize(t[1]).x
        imgui.SetCursorPos(V2(x, (HEAD - th) / 2))
        local p = imgui.GetCursorScreenPos()
        if imgui.InvisibleButton(t[3], V2(tw, th)) then tab = i end
        local on = tab == i
        if on then
            gradient(dl, p.x, p.y, tw, th, d(10), V4(0.55, 0.32, 1.0, 1), V4(0.36, 0.20, 0.86, 1))
        elseif imgui.IsItemActive() then
            fill(dl, p.x, p.y, tw, th, V4(1, 1, 1, 0.08), d(10))
        end
        icon(dl, t[2], p.x + d(10), p.y + (th - d(20)) / 2, d(20), on and white or V4(0.55, 0.38, 0.95, 1), bg)
        dl:AddText(V2(p.x + d(34), p.y + (th - imgui.GetTextLineHeight()) / 2), rgba(on and white or V4(0.72, 0.66, 0.95, 1)), t[1])
        x = x + tw + d(6)
    end

    local cs = d(38)
    local cx = w - pad - cs
    imgui.SetCursorPos(V2(cx, (HEAD - cs) / 2))
    local cp = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton('##close', V2(cs, cs)) then shown[0] = false end
    fill(dl, cp.x, cp.y, cs, cs, imgui.IsItemActive() and V4(0.62, 0.13, 0.25, 1) or V4(0.30, 0.10, 0.18, 1), d(10))
    outline(dl, cp.x, cp.y, cs, cs, V4(1, 0.35, 0.45, 0.55), d(10))
    local mx, my, o = cp.x + cs / 2, cp.y + cs / 2, cs * 0.17
    dl:AddLine(V2(mx - o, my - o), V2(mx + o, my + o), rgba(white), LINE * 2.2)
    dl:AddLine(V2(mx + o, my - o), V2(mx - o, my + o), rgba(white), LINE * 2.2)

    local label, col = 'Онлайн', green
    if st.mode ~= 'idle' then
        label = st.mode == 'await' and 'Ожидание' or (st.mode == 'scan' and 'Загрузка' or 'Работает')
        col = V4(1, 0.7, 0.2, 1)
    end
    local pw = d(46) + imgui.CalcTextSize(label).x
    local px = cx - d(10) - pw
    if px > x + d(6) then
        local ph = d(32)
        local py = wp.y + (HEAD - ph) / 2
        fill(dl, wp.x + px, py, pw, ph, V4(0.10, 0.09, 0.18, 1), ph / 2)
        outline(dl, wp.x + px, py, pw, ph, V4(col.x, col.y, col.z, 0.35), ph / 2)
        local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
        dl:AddCircleFilled(V2(wp.x + px + d(16), py + ph / 2), d(4) + d(4) * pulse, rgba(V4(col.x, col.y, col.z, 0.22 * (1 - pulse) + 0.04)), 20)
        dl:AddCircleFilled(V2(wp.x + px + d(16), py + ph / 2), d(4), rgba(col), 16)
        dl:AddText(V2(wp.x + px + d(28), py + (ph - imgui.GetTextLineHeight()) / 2), rgba(col), label)
    end

    dl:AddLine(V2(wp.x + pad, wp.y + HEAD), V2(wp.x + w - pad, wp.y + HEAD), rgba(V4(0.6, 0.4, 1, 0.22)), LINE)
end

local styleReady = false

local function resize()
    ROW, GAP, DAYS_ROW, BTN, HEAD = d(46), d(5), d(36), d(34), d(52)
end
resize()

local function setStyle()
    local s = imgui.GetStyle()
    s.WindowRounding, s.ChildRounding, s.FrameRounding = d(14), d(10), d(8)
    s.GrabRounding, s.ScrollbarRounding, s.ScrollbarSize = d(8), d(8), d(7)
    s.PopupRounding = d(10)
    s.GrabMinSize = d(24)
    s.ItemSpacing = V2(d(6), d(6))
    s.FramePadding = V2(d(8), d(6))
    s.WindowBorderSize, s.FrameBorderSize, s.ChildBorderSize = LINE, LINE, LINE
    local c, col = s.Colors, imgui.Col
    c[col.WindowBg] = bg
    c[col.ChildBg] = card
    c[col.PopupBg] = V4(0.08, 0.07, 0.15, 1)
    c[col.Border] = V4(0.55, 0.38, 1.0, 0.22)
    c[col.Text] = textCol
    c[col.Button] = rowBg
    c[col.ButtonHovered] = V4(0.30, 0.20, 0.60, 1)
    c[col.ButtonActive] = accentDark
    c[col.FrameBg] = V4(0.055, 0.048, 0.110, 1)
    c[col.FrameBgHovered] = V4(0.12, 0.10, 0.22, 1)
    c[col.FrameBgActive] = V4(0.16, 0.12, 0.30, 1)
    c[col.ScrollbarBg] = clear
    c[col.ScrollbarGrab] = V4(0.44, 0.24, 0.92, 0.7)
    c[col.ScrollbarGrabHovered] = accent
    c[col.ScrollbarGrabActive] = accent
    c[col.Header] = V4(0.30, 0.20, 0.60, 0.6)
    c[col.HeaderHovered] = V4(0.40, 0.25, 0.80, 0.8)
    c[col.HeaderActive] = V4(0.44, 0.24, 0.92, 0.9)
    c[col.SliderGrab] = accent
    c[col.SliderGrabActive] = accent
end

applyScale = function(percent)
    zoom = max(0.6, min((tonumber(percent) or 100) / 100, 1.5))
    resize()
    if styleReady then
        setStyle()
        pcall(function() imgui.GetIO().FontGlobalScale = zoom end)
    end
end

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    styleReady = true
    setStyle()
    pcall(function() io.FontGlobalScale = zoom end)
    local path = getWorkingDirectory() .. '/lib/mimgui/trebucbd.ttf'
    if not doesFileExist(path) then path = '/system/fonts/Roboto-Regular.ttf' end
    local config = imgui.ImFontConfig()
    pcall(function() config.OversampleH, config.OversampleV = 1, 1 end)
    local ranges = io.Fonts:GetGlyphRangesCyrillic()
    fMain = io.Fonts:AddFontFromFileTTF(path, d(14), config, ranges)
    fBig = io.Fonts:AddFontFromFileTTF(path, d(19), config, ranges)
    fSmall = io.Fonts:AddFontFromFileTTF(path, d(11.5), config, ranges)
    io.FontDefault = fMain
end)

local glyphs = {}
for c = 32, 126 do glyphs[#glyphs + 1] = string.char(c) end
for c = 0x410, 0x44F do glyphs[#glyphs + 1] = string.char(0xC0 + floor(c / 64), 0x80 + c % 64) end
glyphs[#glyphs + 1] = '\208\129\209\145'
glyphs = table.concat(glyphs)

local fontsReady, refreshLeft, shownTab = false, 0, nil
local function prepareFonts()
    if not fontsReady then
        fontsReady = true
        for _, f in ipairs({ fMain, fBig, fSmall }) do
            imgui.PushFont(f)
            imgui.CalcTextSize(glyphs)
            imgui.PopFont()
        end
        refreshLeft = 3
    end
    if tab ~= shownTab then
        shownTab = tab
        refreshLeft = 3
    end
end

local function refreshFonts()
    if refreshLeft == 0 then return end
    refreshLeft = refreshLeft - 1
    if refreshLeft == 0 then pcall(imgui.InvalidateFontsTexture) end
end

local open = new.bool(true)

local function drawWindow()
    local now = os.clock()
    frameDt = min(0.05, max(0.001, now - lastFrame))
    lastFrame = now
    fadeTo = shown[0] and 1 or 0
    fade = fade + (fadeTo - fade) * min(1, frameDt * (shown[0] and 14 or 18))
    if fadeTo == 0 and fade < 0.015 then fade = 0 end
    if fadeTo == 1 and fade > 0.995 then fade = 1 end
    if fade == 0 and not shown[0] then return end

    if imgui.IsMouseClicked(0) then dragged = 0 end
    prepareFonts()

    icons.budget = 2
    local sw, sh = getScreenResolution()
    local w, h = min(sw - d(8), d(920)), min(sh - d(8), d(470))
    imgui.SetNextWindowPos(V2(sw / 2, sh / 2 + (1 - fade) * d(14)), imgui.Cond.Always, V2(0.5, 0.5))
    imgui.SetNextWindowSize(V2(w, h), imgui.Cond.Always)
    open[0] = true
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, max(fade, 0.02))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
    local visible = imgui.Begin('##autobuypawn', open, WF.NoTitleBar + WF.NoResize + WF.NoCollapse + WF.NoMove + NO_SCROLL)
    imgui.PopStyleVar()

    if visible then
        drawHeader(w)
        local pad = d(10)
        local cw, ch = w - pad * 2, h - HEAD - d(6) - pad
        imgui.SetCursorPos(V2(pad, HEAD + d(6)))
        imgui.PushStyleColor(imgui.Col.ChildBg, clear)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.BeginChild('##content', V2(cw, ch), false, NO_SCROLL)
        imgui.PopStyleVar()
        imgui.PopStyleColor()
        if tab == 1 then
            tabMain(cw, ch)
        elseif tab == 2 then
            tabInfo()
        else
            tabSettings()
        end
        imgui.EndChild()
    end

    imgui.End()
    imgui.PopStyleVar()
    refreshFonts()
end

imgui.OnFrame(function() return shown[0] or fade > 0 end, drawWindow)

function main()
    while not isSampAvailable() do wait(100) end
    load()
    sampRegisterChatCommand('skup', function()
        shown[0] = not shown[0]
        if not shown[0] then editing = nil end
    end)
    msg('Скрипт загружен. Меню: /skup | by Edward')
    lua_thread.create(iconWorker)
    while true do
        wait(100)
        if st.err then
            msg(st.err)
            st.err = nil
        end
        if st.mode == 'await' then
            if st.ready and os.clock() - st.ready > 0.4 then
                startWork()
            elseif os.clock() - st.waitFrom > 60 then
                stop('Ломбард не выбран за 60 секунд, операция отменена')
            end
        elseif st.mode ~= 'idle' and os.clock() - st.last > 10 then
            stop('Сервер не ответил, операция остановлена')
        end
        if dirty and os.clock() - lastSave > 1.5 then save() end
    end
end

addEventHandler('onScriptTerminate', function(scr)
    if scr == script.this and dirty then save() end
end)
