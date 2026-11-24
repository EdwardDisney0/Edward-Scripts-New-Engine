script_name('Vehicle Rename Mobile')
script_author('Edward')
script_version('2.0')

require 'lib.moonloader'
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
pcall(require, 'RakLua')

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new, str = imgui.new, ffi.string
local V2, V4 = imgui.ImVec2, imgui.ImVec4
local min, max, floor, abs = math.min, math.max, math.floor, math.abs

local DPI = max(1, min(tonumber(MONET_DPI_SCALE) or 2.5, 4))
local function d(v) return floor(v * DPI + 0.5) end

local IFACE = 91
local TOLERANCE = 350
local CONFIG = getWorkingDirectory() .. '/config/VehicleRename_mobile.tsv'

local cars, assignRec, listItems = {}, {}, {}
local mine = {}
local enabled = true
local menuOpen, inDetail = false, false
local cur
local dirty = false
local stats = { tooBig = 0, trimmed = 0 }
local panel = new.bool(false)
local input = new.char[128]()
local focusFrames = 0
local lingerUntil = 0

local function msg(text)
    sampAddChatMessage('{D2772C}[VehRename] {FFFFFF}' .. u8:decode(text), -1)
end

local function encodeName(s)
    local out = {}
    for ch in s:gmatch('[\1-\127\194-\244][\128-\191]*') do
        local n, cp = #ch, nil
        if n == 1 then
            cp = ch:byte()
        elseif n == 2 then
            cp = (ch:byte(1) - 192) * 64 + (ch:byte(2) - 128)
        elseif n == 3 then
            cp = (ch:byte(1) - 224) * 4096 + (ch:byte(2) - 128) * 64 + (ch:byte(3) - 128)
        else
            cp = (ch:byte(1) - 240) * 262144 + (ch:byte(2) - 128) * 4096 + (ch:byte(3) - 128) * 64 + (ch:byte(4) - 128)
        end
        if cp < 128 then
            out[#out + 1] = ch
        elseif cp >= 0x410 and cp <= 0x44F then
            out[#out + 1] = string.char(cp - 0x410 + 0xC0)
        elseif cp == 0x401 then
            out[#out + 1] = '\168'
        elseif cp == 0x451 then
            out[#out + 1] = '\184'
        elseif cp < 0x10000 then
            out[#out + 1] = ('\\u%04x'):format(cp)
        else
            cp = cp - 0x10000
            out[#out + 1] = ('\\u%04x\\u%04x'):format(0xD800 + floor(cp / 1024), 0xDC00 + cp % 1024)
        end
    end
    return table.concat(out)
end

local function toUtf8(s)
    local rest = s:gsub('[\194-\223][\128-\191]', ''):gsub('[\224-\239][\128-\191][\128-\191]', ''):gsub('[\240-\244][\128-\191][\128-\191][\128-\191]', '')
    if rest:find('[\128-\255]') then return u8(s) end
    return s
end

local function clean(s)
    s = s:gsub('[\1-\31\127`\\"$]', '')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function loadConfig()
    local f = io.open(CONFIG, 'rb')
    if not f then return end
    local data = f:read('*a') or ''
    f:close()
    if data:sub(1, 3) == '\239\187\191' then data = data:sub(4) end
    for line in (data .. '\n'):gmatch('(.-)\r?\n') do
        local uid, sys, rating, rating0, idx, hint, title, name = line:match('^car3\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(%d*)\t(.-)\t(.*)$')
        if uid and name ~= '' then
            cars[uid] = {
                name = name, sys = sys, rating = tonumber(rating), idx = tonumber(idx), title = title,
                rating0 = tonumber(rating0) ~= 0 and tonumber(rating0) or nil, hint = hint ~= '' and hint or nil,
            }
        end
    end
end

local function saveConfig()
    createDirectory(getWorkingDirectory() .. '/config')
    local f = io.open(CONFIG, 'w')
    if not f then
        msg('Не удалось сохранить список: ' .. CONFIG)
        return
    end
    f:write('\239\187\191')
    for uid, c in pairs(cars) do
        if c.sys then
            f:write('car3\t', uid, '\t', c.sys, '\t', tostring(c.rating or 0), '\t', tostring(c.rating0 or 0), '\t',
                tostring(c.idx or 0), '\t', tostring(c.hint or ''), '\t', (c.title or ''):gsub('[\t\r\n]', ' '), '\t', c.name, '\n')
        end
    end
    f:close()
    dirty = false
end

local function nextUid()
    local top = 1000
    for k in pairs(cars) do
        local n = tonumber(k)
        if n and n >= top then top = n + 1 end
    end
    return tostring(top)
end

local function stringEnd(s, from)
    while true do
        local q = s:find('["\\]', from)
        if not q then return end
        if s:sub(q, q) == '"' then return q end
        from = q + 2
    end
end

local ITEM = '{%s*"id"%s*:%s*%d+%s*,%s*"title"%s*:%s*"'

local function eachItem(text, fn)
    local pos = 1
    while true do
        local start = text:find(ITEM, pos)
        if not start then return end
        local _, stop = text:find('^%b{}', start)
        if not stop then return end
        local obj = text:sub(start, stop)
        if obj:find('"sysName"', 1, true) then
            local idx, from = obj:match('^{%s*"id"%s*:%s*(%d+)%s*,%s*"title"%s*:%s*"()')
            local last = stringEnd(obj, from)
            if last then fn(start, stop, obj, tonumber(idx), from, last) end
        end
        pos = stop + 1
    end
end

local function parseItems(text)
    eachItem(text, function(_, _, obj, idx, from, last)
        local labels = obj:match('"labels"%s*:%s*(%b[])') or ''
        local raw = obj:sub(from, last - 1)
        listItems[idx] = {
            idx = idx, raw = raw, title = u8(raw),
            sys = obj:match('"sysName"%s*:%s*"?(%d+)'),
            status = obj:match('"status"%s*:%s*"([^"]*)"') or '',
            rating = tonumber(obj:match('"rarityLevel"%s*:%s*(%d+)')) or 0,
            dbId = labels:match('"title"%s*:%s*"(%d+)"%s*,%s*"icon"%s*:%s*"icon%-id"'),
        }
    end)
end

local function ratingGap(item, rec)
    local gap = rec.rating and abs(item.rating - rec.rating) or 0
    if rec.rating0 then gap = min(gap, abs(item.rating - rec.rating0)) end
    return gap
end

local function computeAssign()
    local assign, owner = {}, {}
    local groups, records = {}, {}
    for _, it in pairs(listItems) do
        if it.sys then
            groups[it.sys] = groups[it.sys] or {}
            table.insert(groups[it.sys], it)
        end
    end
    for uid, rec in pairs(cars) do
        if rec.sys then
            records[rec.sys] = records[rec.sys] or {}
            table.insert(records[rec.sys], { uid = uid, rec = rec })
        end
    end

    for sys, items in pairs(groups) do
        local recs = records[sys]
        if recs then
            local pairsList = {}
            for _, it in ipairs(items) do
                for _, e in ipairs(recs) do
                    pairsList[#pairsList + 1] = {
                        it = it, e = e, gap = ratingGap(it, e.rec),
                        same = not e.rec.title or e.rec.title == '' or e.rec.title == it.title,
                        hint = (it.dbId and it.dbId == e.rec.hint) and 0 or 1,
                        near = abs(it.idx - (e.rec.idx or it.idx)),
                    }
                end
            end
            table.sort(pairsList, function(a, b)
                if a.gap ~= b.gap then return a.gap < b.gap end
                if a.hint ~= b.hint then return a.hint < b.hint end
                if a.near ~= b.near then return a.near < b.near end
                return a.it.idx < b.it.idx
            end)
            local single = #items == 1 and #recs == 1
            local usedItem, usedRec = {}, {}
            for _, p in ipairs(pairsList) do
                if not usedItem[p.it.idx] and not usedRec[p.e.uid] and p.same and (single or p.gap <= TOLERANCE) then
                    usedItem[p.it.idx], usedRec[p.e.uid] = true, true
                    local it, rec = p.it, p.e.rec
                    assign[it.idx], owner[it.idx] = rec.name, p.e.uid
                    local before = table.concat({ rec.rating or 0, rec.rating0 or 0, tostring(rec.hint), tostring(rec.idx), tostring(rec.title) }, '|')
                    if it.status == 'loaded' then
                        rec.rating, rec.hint = it.rating, it.dbId
                    else
                        rec.rating0, rec.hint = it.rating, nil
                    end
                    rec.rating, rec.rating0 = rec.rating or it.rating, rec.rating0 or it.rating
                    rec.idx, rec.title = it.idx, it.title
                    local after = table.concat({ rec.rating or 0, rec.rating0 or 0, tostring(rec.hint), tostring(rec.idx), tostring(rec.title) }, '|')
                    if before ~= after then dirty = true end
                end
            end
        end
    end

    assignRec = owner
    return assign
end

local function patchChunk(text, assign)
    local parts, pos, changed = {}, 1, false
    eachItem(text, function(start, stop, obj, idx, from, last)
        local name = assign[idx]
        parts[#parts + 1] = text:sub(pos, start - 1)
        if name then
            parts[#parts + 1] = obj:sub(1, from - 1) .. encodeName(name) .. obj:sub(last)
            changed = true
        else
            parts[#parts + 1] = obj
        end
        pos = stop + 1
    end)
    parts[#parts + 1] = text:sub(pos)
    if changed then return table.concat(parts) end
end

local function replacePlain(text, old, new)
    local out, pos, found = {}, 1, false
    while true do
        local a, b = text:find(old, pos, true)
        if not a then break end
        out[#out + 1] = text:sub(pos, a - 1)
        out[#out + 1] = new
        pos, found = b + 1, true
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out), found
end

local canEmulate = type(raknetEmulPacketReceiveBitStream) == 'function'

local function emit(iface, sub, text)
    local pack = #text > 1024
    local mark = mine[text] or { count = 0 }
    mark.count, mark.time = mark.count + 1, os.clock()
    mine[text] = mark
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 84)
    raknetBitStreamWriteInt8(bs, iface)
    raknetBitStreamWriteInt8(bs, sub)
    raknetBitStreamWriteInt16(bs, #text)
    if pack then
        raknetBitStreamWriteInt8(bs, 1)
        raknetBitStreamEncodeString(bs, text)
    else
        raknetBitStreamWriteInt8(bs, 0)
        raknetBitStreamWriteString(bs, text)
    end
    raknetEmulPacketReceiveBitStream(220, bs)
    raknetDeleteBitStream(bs)
end

local function rewriteInPlace(bs, packet, text)
    if 7 + #text <= packet.total then
        raknetBitStreamSetWriteOffset(bs, 32)
        raknetBitStreamWriteInt16(bs, #text)
        raknetBitStreamWriteInt8(bs, 0)
        raknetBitStreamWriteString(bs, text)
        return true
    end
    local tmp = raknetNewBitStream()
    raknetBitStreamWriteInt8(tmp, 220)
    raknetBitStreamWriteInt8(tmp, 84)
    raknetBitStreamWriteInt8(tmp, packet.iface)
    raknetBitStreamWriteInt8(tmp, packet.sub)
    raknetBitStreamWriteInt16(tmp, #text)
    raknetBitStreamWriteInt8(tmp, 1)
    raknetBitStreamEncodeString(tmp, text)
    local size = raknetBitStreamGetNumberOfBytesUsed(tmp)
    local fits = size <= packet.total
    if fits then
        raknetBitStreamSetWriteOffset(bs, 32)
        raknetBitStreamWriteBuffer(bs, raknetBitStreamGetDataPtr(tmp) + 4, size - 4)
    end
    raknetDeleteBitStream(tmp)
    return fits
end

local function readPacket(bs)
    local total = raknetBitStreamGetNumberOfBytesUsed(bs)
    if not total or total < 3 then return end
    local ptr = raknetBitStreamGetDataPtr(bs)
    if not ptr or ptr == 0 then return end
    local p = ffi.cast('const uint8_t*', ffi.cast('uintptr_t', ptr))
    local packet = { kind = p[1], iface = p[2], total = total }
    if packet.kind == 62 then
        packet.opened = p[3] >= 128
    elseif packet.kind == 63 and total >= 11 then
        packet.a = p[3] + p[4] * 256 + p[5] * 65536 + p[6] * 16777216
        packet.b = p[7] + p[8] * 256 + p[9] * 65536 + p[10] * 16777216
    elseif packet.kind == 84 and total >= 7 then
        packet.sub = p[3]
        local len, enc = p[4] + p[5] * 256, p[6]
        if enc == 0 then
            if total >= 7 + len then packet.text = ffi.string(p + 7, len) end
        else
            raknetBitStreamResetReadPointer(bs)
            raknetBitStreamIgnoreBits(bs, 56)
            packet.text = raknetBitStreamDecodeString(bs, len + enc)
            raknetBitStreamResetReadPointer(bs)
        end
    end
    return packet
end

local function titleOf(name)
    return '"' .. encodeName(name) .. '"'
end

local function deliver(bs, packet, text)
    if rewriteInPlace(bs, packet, text) then return end
    if canEmulate then
        emit(packet.iface, packet.sub, text)
        return false
    end
    stats.tooBig = stats.tooBig + 1
end

local function withName(text, name)
    if text == cur.raw then return u8:decode(name) end
    local out, found = replacePlain(text, '"' .. cur.raw .. '"', titleOf(name))
    if found then return out end
end

local function nameOfCurrent()
    if not cur then return end
    if cur.uid and cars[cur.uid] then return cars[cur.uid].name end
end

local function utf8Len(s)
    return select(2, s:gsub('[^\128-\191]', ''))
end

local function utf8Sub(s, n)
    local i, c = 1, 0
    while i <= #s and c < n do
        local b = s:byte(i)
        i = i + (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1)
        c = c + 1
    end
    return s:sub(1, i - 1)
end

local LOOK = {
    { '\208\176', 'a' }, { '\208\181', 'e' }, { '\208\190', 'o' }, { '\209\128', 'p' },
    { '\209\129', 'c' }, { '\209\131', 'y' }, { '\209\133', 'x' },
    { '\208\144', 'A' }, { '\208\146', 'B' }, { '\208\149', 'E' }, { '\208\154', 'K' },
    { '\208\156', 'M' }, { '\208\157', 'H' }, { '\208\158', 'O' }, { '\208\160', 'P' },
    { '\208\161', 'C' }, { '\208\162', 'T' }, { '\208\163', 'Y' }, { '\208\165', 'X' },
}

local function lookalike(s)
    for _, p in ipairs(LOOK) do s = s:gsub(p[1], p[2]) end
    return s
end

local NO_PLATE = '"' .. encodeName('Без номеров') .. '"'
local NO_PLATE_LOOK = '"' .. encodeName(lookalike('Без номеров')) .. '"'
local NO_PLATE_SHORT = '"' .. encodeName('Б/н') .. '"'
local MAX_LEVEL = 2

local function buildList(text, assign, level, exact)
    local names = assign
    if level > 0 and not exact then
        names = {}
        for k, n in pairs(assign) do names[k] = lookalike(n) end
    end
    local out = patchChunk(text, names)
    if not out then return nil, names end
    if level >= 1 then out = replacePlain(out, NO_PLATE, level >= 2 and NO_PLATE_SHORT or NO_PLATE_LOOK) end
    return out, names
end

local function deliverList(bs, packet, text, assignAll)
    local assign = {}
    eachItem(text, function(_, _, _, idx)
        if assignAll[idx] then assign[idx] = assignAll[idx] end
    end)
    if not next(assign) then return end

    for level = 0, MAX_LEVEL do
        local out = buildList(text, assign, level)
        if not out then return end
        if rewriteInPlace(bs, packet, out) then return end
    end

    local _, base = buildList(text, assign, MAX_LEVEL)
    local longest = 0
    for _, n in pairs(base) do longest = max(longest, utf8Len(n)) end
    for limit = longest - 1, 1, -1 do
        local short = {}
        for k, n in pairs(base) do short[k] = utf8Sub(n, limit) end
        local out = buildList(text, short, MAX_LEVEL, true)
        if out and rewriteInPlace(bs, packet, out) then
            stats.trimmed = stats.trimmed + 1
            return
        end
    end
    stats.tooBig = stats.tooBig + 1
end

local function onReceive(id, bs)
    if id ~= 220 then return end
    local packet = readPacket(bs)
    if not packet or packet.iface ~= IFACE then return end

    if packet.kind == 62 then
        mine = {}
        menuOpen, inDetail = packet.opened, false
        if packet.opened then
            cur = nil
            listItems = {}
        else
            panel[0] = false
        end
        return
    end

    local text = packet.text
    if packet.kind ~= 84 or not text then return end
    local mark = mine[text]
    if mark then
        mine[text] = nil
        if os.clock() - mark.time < 0.5 then return end
    end

    if text:find('"sysName"', 1, true) and text:match('^%s*%[') then
        parseItems(text)
        if not enabled or not next(cars) then return end
        local assign = computeAssign()
        if dirty then saveConfig() end
        return deliverList(bs, packet, text, assign)
    end

    if cur and cur.raw and (text == cur.raw or text:find('"' .. cur.raw .. '"', 1, true)) then
        local name = enabled and nameOfCurrent()
        local out = name and withName(text, name)
        if out then return deliver(bs, packet, out) end
    end
end

local function selectVehicle(idx)
    local item = listItems[idx]
    if not item then return end
    inDetail = true
    cur = { idx = idx, item = item, raw = item.raw, title = item.title, uid = assignRec[idx] }
end

local function onSend(id, bs)
    if id ~= 220 then return end
    local packet = readPacket(bs)
    if not packet or packet.iface ~= IFACE or packet.kind ~= 63 then return end
    if packet.b == 0 then
        selectVehicle(packet.a)
    elseif packet.b == 3 then
        inDetail = false
        panel[0] = false
    elseif packet.b == 4 then
        menuOpen, inDetail = false, false
        panel[0] = false
    end
end

local function guarded(fn)
    return function(...)
        local ok, res = pcall(fn, ...)
        if ok then return res end
        stats.lastErr = tostring(res)
        return nil
    end
end
onReceive, onSend = guarded(onReceive), guarded(onSend)

if not pcall(addEventHandler, 'onReceivePacket', onReceive) then onReceivePacket = onReceive end
if not pcall(addEventHandler, 'onSendPacket', onSend) then onSendPacket = onSend end

local function sendSelect(idx)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, IFACE)
    raknetBitStreamWriteInt32(bs, idx)
    raknetBitStreamWriteInt32(bs, 0)
    raknetBitStreamWriteInt16(bs, 0)
    if raknetSendBitStreamEx then
        raknetSendBitStreamEx(bs, 1, 7, 0)
    else
        raknetSendBitStream(bs)
    end
    raknetDeleteBitStream(bs)
end

local function refreshDetail()
    if not cur or not inDetail then return end
    local ok = pcall(sendSelect, cur.idx)
    if not ok then msg('Откройте машину заново, чтобы увидеть новое название') end
end

local function applyName(name)
    if not cur then return end
    name = clean(toUtf8(name or ''))
    local item = cur.item
    if name == '' then
        if cur.uid then cars[cur.uid] = nil end
        assignRec[cur.idx] = nil
        cur.uid = nil
    elseif item and item.sys then
        local uid = cur.uid
        if not uid then
            for k, r in pairs(cars) do
                if r.sys == item.sys and r.idx == item.idx and r.title == item.title then
                    uid = k
                    break
                end
            end
        end
        uid = uid or nextUid()
        local prev = cars[uid]
        local loaded = item.status == 'loaded'
        cars[uid] = {
            name = name, sys = item.sys, idx = item.idx, title = item.title,
            rating = loaded and item.rating or (prev and prev.rating) or item.rating,
            rating0 = (not loaded) and item.rating or (prev and prev.rating0) or item.rating,
            hint = loaded and item.dbId or nil,
        }
        assignRec[item.idx] = uid
        cur.uid = uid
    else
        msg('Не удалось определить машину. Закройте меню и откройте его заново')
        return
    end
    saveConfig()
    refreshDetail()
    msg(name == '' and 'Имя сброшено' or ('Сохранено: ' .. name))
end

local function openPanel()
    if not cur then return end
    ffi.fill(input, ffi.sizeof(input), 0)
    ffi.copy(input, (nameOfCurrent() or ''):sub(1, 120))
    focusFrames = 6
    panel[0] = true
end

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    local path = getWorkingDirectory() .. '/lib/mimgui/trebucbd.ttf'
    if not doesFileExist(path) then path = '/system/fonts/Roboto-Regular.ttf' end
    local font = io.Fonts:AddFontFromFileTTF(path, d(15), nil, io.Fonts:GetGlyphRangesCyrillic())
    if font then io.FontDefault = font end
    local style = imgui.GetStyle()
    style.FramePadding = V2(d(10), d(8))
    style.ItemSpacing = V2(d(8), d(8))
    style.WindowPadding = V2(d(12), d(12))
    style.WindowRounding = d(12)
    style.FrameRounding = d(8)
end)

local THEME = {
    { imgui.Col.WindowBg, V4(0.09, 0.10, 0.12, 0.97) },
    { imgui.Col.PopupBg, V4(0.12, 0.13, 0.16, 1) },
    { imgui.Col.Border, V4(0.30, 0.34, 0.40, 0.55) },
    { imgui.Col.Text, V4(0.94, 0.95, 0.97, 1) },
    { imgui.Col.TitleBg, V4(0.12, 0.13, 0.16, 1) },
    { imgui.Col.TitleBgActive, V4(0.16, 0.18, 0.22, 1) },
    { imgui.Col.TitleBgCollapsed, V4(0.12, 0.13, 0.16, 1) },
    { imgui.Col.FrameBg, V4(0.14, 0.15, 0.19, 1) },
    { imgui.Col.FrameBgHovered, V4(0.18, 0.20, 0.25, 1) },
    { imgui.Col.FrameBgActive, V4(0.21, 0.24, 0.30, 1) },
    { imgui.Col.Button, V4(0.16, 0.42, 0.82, 1) },
    { imgui.Col.ButtonHovered, V4(0.22, 0.50, 0.92, 1) },
    { imgui.Col.ButtonActive, V4(0.12, 0.34, 0.70, 1) },
}

local function pushTheme()
    for _, t in ipairs(THEME) do imgui.PushStyleColor(t[1], t[2]) end
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, d(14))
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, d(10))
end

local function popTheme()
    imgui.PopStyleVar(2)
    imgui.PopStyleColor(#THEME)
end

local function dangerButton(label, size)
    imgui.PushStyleColor(imgui.Col.Button, V4(0.62, 0.14, 0.26, 1))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, V4(0.75, 0.2, 0.34, 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, V4(0.5, 0.1, 0.2, 1))
    local pressed = imgui.Button(label, size)
    imgui.PopStyleColor(3)
    return pressed
end

local function visible()
    return menuOpen and inDetail and cur ~= nil
end

local function drawUi()
    if not visible() then
        panel[0] = false
        return
    end
    local sw, sh = getScreenResolution()
    pushTheme()
    if not panel[0] then
        imgui.SetNextWindowPos(V2(sw * 0.575, sh * 0.47), imgui.Cond.Always, V2(1, 0.5))
        imgui.Begin('##vrbutton', nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)
        if imgui.Button('Переименовать', V2(0, d(44))) then openPanel() end
        imgui.End()
        popTheme()
        return
    end
    imgui.SetNextWindowPos(V2(sw / 2, sh * 0.12), imgui.Cond.Always, V2(0.5, 0))
    imgui.SetNextWindowSize(V2(min(sw * 0.8, d(520)), 0), imgui.Cond.Always)
    imgui.Begin('Название машины##vrpanel', panel, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove)
    imgui.TextColored(V4(0.62, 0.66, 0.72, 1), 'Оригинал: ' .. cur.title)
    imgui.PushItemWidth(-1)
    if focusFrames > 0 then
        imgui.SetKeyboardFocusHere(0)
        focusFrames = focusFrames - 1
    end
    local entered = imgui.InputText('##vrname', input, ffi.sizeof(input), imgui.InputTextFlags.EnterReturnsTrue)
    imgui.PopItemWidth()
    if entered or imgui.Button('Сохранить', V2(-1, d(44))) then
        applyName(str(input))
        panel[0] = false
    end
    if dangerButton('Сбросить название', V2(-1, d(44))) then
        applyName('')
        panel[0] = false
    end
    imgui.TextColored(V4(0.45, 0.72, 1, 1), 'By')
    imgui.SameLine(0, d(6))
    imgui.TextColored(V4(1, 0.48, 0.48, 1), 'Edward')
    imgui.End()
    popTheme()
end

imgui.OnFrame(function()
    if visible() then
        lingerUntil = os.clock() + 0.6
        return true
    end
    return os.clock() < lingerUntil
end, drawUi)

function main()
    while not isSampAvailable() do wait(100) end
    loadConfig()

    sampRegisterChatCommand('vname', function(arg)
        arg = arg or ''
        if not visible() then
            msg('Откройте меню транспорта и выберите машину')
            return
        end
        if arg:match('^%s*$') then
            openPanel()
        elseif arg:match('^%s*reset%s*$') then
            applyName('')
        else
            applyName(arg)
        end
    end)

    sampRegisterChatCommand('vrt', function()
        enabled = not enabled
        msg('Подмена названий: ' .. (enabled and 'вкл' or 'выкл'))
    end)

    msg('Загружен. В меню транспорта нажмите «Переименовать» или /vname {73B8FF}By {FF7A7A}Edward')
    while true do
        wait(100)
        if dirty then saveConfig() end
        if stats.lastErr and stats.lastErr ~= stats.toldErr then
            stats.toldErr = stats.lastErr
            pcall(msg, 'Ошибка: ' .. stats.lastErr:sub(1, 160))
        end
        if stats.trimmed > 0 and not stats.toldTrim then
            stats.toldTrim = true
            msg('Название длинное: в списке оно показано сокращённым, в карточке машины полностью')
        end
        if stats.tooBig > 0 and not stats.told then
            stats.told = true
            msg('Название не поместилось в пакет и не будет показано. Попробуйте название короче')
        end
    end
end
