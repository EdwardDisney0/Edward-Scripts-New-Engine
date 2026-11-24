script_name('Enchant Master')
script_author('By Stalin')
script_version('4.0 mobile')

require 'lib.moonloader'
local imgui    = require 'mimgui'
local encoding = require 'encoding'
local ffi      = require 'ffi'
local bit      = require 'bit'

local okSampev, sampev = pcall(require, 'samp.events')
if not okSampev then okSampev, sampev = pcall(require, 'lib.samp.events') end
if not okSampev or type(sampev) ~= 'table' then sampev = {} end

local decodeJson = decodeJson or function(s) return require('dkjson').decode(s) end

encoding.default = 'CP1251'
local u8  = encoding.UTF8
local new = imgui.new

local SRC_UTF8 = (#'я' == 2)
local tCache = {}

local function T(s)
    if SRC_UTF8 then return s end
    if not tCache[s] then tCache[s] = u8(s) end
    return tCache[s]
end

local function V4(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end
local function P(x, y) return imgui.ImVec2(x, y) end
local function U32(r, g, b, a) return imgui.GetColorU32Vec4(V4(r, g, b, a)) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t) return a + (b - a) * t end

 
 
 
local SC, FA = 1, 1
local SCB = 1             
local scalePending = false
local ORG = {x = 0, y = 0}
local HITCLIP = nil

local function setOrigin(x, y) ORG.x, ORG.y = x, y end
local function TX(x) return ORG.x + (x - ORG.x) * SC end
local function TY(y) return ORG.y + (y - ORG.y) * SC end
local function tp(p) return imgui.ImVec2(TX(p.x), TY(p.y)) end

local function fadeCol(c)
    if FA >= 0.999 then return c end
    local a = bit.rshift(c, 24)
    local r = bit.bor(bit.band(c, 0x00FFFFFF), bit.lshift(math.floor(a * FA + 0.5), 24))
    if r < 0 then r = r + 4294967296 end
    return r
end

local DLP = {}
DLP.__index = DLP
function DLP:AddRectFilled(a, b, col, r, fl) return self.r:AddRectFilled(tp(a), tp(b), fadeCol(col), (r or 0) * SC, fl or 0) end
function DLP:AddRect(a, b, col, r, fl, th) return self.r:AddRect(tp(a), tp(b), fadeCol(col), (r or 0) * SC, fl or 0, (th or 1) * SC) end
function DLP:AddLine(a, b, col, th) return self.r:AddLine(tp(a), tp(b), fadeCol(col), (th or 1) * SC) end
function DLP:AddTriangleFilled(a, b, c, col) return self.r:AddTriangleFilled(tp(a), tp(b), tp(c), fadeCol(col)) end
function DLP:AddCircleFilled(c, r, col, seg) return self.r:AddCircleFilled(tp(c), r * SC, fadeCol(col), seg or 0) end
function DLP:AddCircle(c, r, col, seg, th) return self.r:AddCircle(tp(c), r * SC, fadeCol(col), seg or 0, (th or 1) * SC) end
function DLP:AddRectFilledMultiColor(a, b, c1, c2, c3, c4)
    return self.r:AddRectFilledMultiColor(tp(a), tp(b), fadeCol(c1), fadeCol(c2), fadeCol(c3), fadeCol(c4))
end
function DLP:AddText(pos, col, s) return self.r:AddText(tp(pos), fadeCol(col), s) end
function DLP:AddImage(tex, a, b, uv0, uv1, col)
    return self.r:AddImage(tex, tp(a), tp(b), uv0 or imgui.ImVec2(0, 0), uv1 or imgui.ImVec2(1, 1), fadeCol(col or 0xFFFFFFFF))
end
function DLP:PushClipRect(a, b, inter) return self.r:PushClipRect(tp(a), tp(b), inter or false) end
function DLP:PopClipRect() return self.r:PopClipRect() end

local function wrapDL(real) return setmetatable({r = real}, DLP) end
local function winDL() return wrapDL(imgui.GetWindowDrawList()) end
local function bgDL() return wrapDL(imgui.GetBackgroundDrawList()) end

 
local touch = {stamp = -1, down = false, was = false, released = false, pressed = false,
               x = -1, y = -1, sx = -1, sy = -1, dx = 0, dy = 0, moved = 0}

local function trackTouch()
    local now = imgui.GetTime()
    if touch.stamp == now then return end
    touch.stamp = now
    touch.frame = (touch.frame or 0) + 1
    local down = imgui.IsMouseDown(0)
    local mp = imgui.GetMousePos()
    touch.pressed = imgui.IsMouseClicked(0)
    if touch.pressed then
        touch.sx, touch.sy, touch.x, touch.y, touch.moved = mp.x, mp.y, mp.x, mp.y, 0
    end
    if down then
        touch.dx, touch.dy = mp.x - touch.x, mp.y - touch.y
        touch.x, touch.y = mp.x, mp.y
        touch.moved = math.max(touch.moved, math.abs(mp.x - touch.sx) + math.abs(mp.y - touch.sy))
    else
        touch.dx, touch.dy = 0, 0
    end
    touch.released = (not down) and touch.was
    touch.was = down
    touch.down = down
end

local function inR(px, py, x1, y1, x2, y2) return px >= x1 and px <= x2 and py >= y1 and py <= y2 end
local function clipOK(px, py)
    return not HITCLIP or inR(px, py, HITCLIP[1], HITCLIP[2], HITCLIP[3], HITCLIP[4])
end

local function computeScale(userPct)
    local base = 1
    pcall(function()
        local rw, rh = getScreenResolution()
        if rw and rh and rw > 100 and rh > 100 then
            if rh > rw then rw, rh = rh, rw end
            base = math.max(0.8, math.min(math.min(rh / 860, rw / 900), 2.4))
        end
    end)
    SCB = math.max(0.6, math.min(base, 3.5))
    SC = math.max(0.6, math.min(base * (userPct or 100) / 100, 3.5))
end

local ICON_SHARP_B64  = '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'
local ICON_AMULET_B64 = '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'

 
local ACCENTS = {
    {name = 'Неон',    c = {0.10, 0.60, 1.00}, c2 = {0.58, 0.30, 1.00}},
    {name = 'Изумруд', c = {0.12, 0.85, 0.55}, c2 = {0.10, 0.55, 0.95}},
    {name = 'Рубин',   c = {1.00, 0.25, 0.35}, c2 = {0.80, 0.25, 0.75}},
    {name = 'Закат',   c = {1.00, 0.60, 0.15}, c2 = {1.00, 0.25, 0.45}},
    {name = 'Лёд',     c = {0.35, 0.85, 1.00}, c2 = {0.55, 0.65, 1.00}},
}

 
local cfgDir  = getWorkingDirectory() .. '/config'
local cfgFile = cfgDir .. '/enchant_master.json'
local dirty, dirtyAt = false, 0

local cfg = {
    ver      = 2,
    pos      = {x = 300, y = 120},
    panelPos = {x = -1, y = -1},
    page     = 'logs',
    settings = {enabled = true, alpha = 96, glow = 60, accent = 1, scale = 100},
    enchant  = {mode = 2, target = 5},
    names    = {},
    stats    = {},
    amuletOnly = {},
    logs     = {},
}

local function markDirty() dirty, dirtyAt = true, os.clock() end

local function jsonStr(s)
    local out = s:gsub('[%z\1-\31"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        if c == '\n' then return '\\n' end
        return ('\\u%04x'):format(c:byte())
    end)
    return '"' .. out .. '"'
end

local function toJson(v, depth)
    if type(v) == 'string' then return jsonStr(v) end
    if type(v) ~= 'table' then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    if #keys == 0 then return '{}' end
    table.sort(keys)
    local pad = ('    '):rep(depth + 1)
    local lines = {}
    for _, k in ipairs(keys) do
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        lines[#lines + 1] = pad .. jsonStr(k) .. ': ' .. toJson(val, depth + 1)
    end
    return '{\n' .. table.concat(lines, ',\n') .. '\n' .. ('    '):rep(depth) .. '}'
end

local function saveConfig()
    if not doesDirectoryExist(cfgDir) then createDirectory(cfgDir) end
    local f = io.open(cfgFile, 'w')
    if not f then return end
    f:write(toJson(cfg, 0))
    f:close()
    dirty = false
end

local function loadConfig()
    local f = io.open(cfgFile, 'r')
    if not f then return end
    local text = f:read('*a')
    f:close()
    local ok, data = pcall(decodeJson, text)
    if not ok or type(data) ~= 'table' then return end

    if type(data.pos) == 'table' then
        cfg.pos.x = tonumber(data.pos.x) or cfg.pos.x
        cfg.pos.y = tonumber(data.pos.y) or cfg.pos.y
    end
    if type(data.panelPos) == 'table' then
        cfg.panelPos.x = tonumber(data.panelPos.x) or cfg.panelPos.x
        cfg.panelPos.y = tonumber(data.panelPos.y) or cfg.panelPos.y
    end
    if type(data.page) == 'string' then cfg.page = data.page end

    if type(data.settings) == 'table' then
        for key, default in pairs(cfg.settings) do
            local v = data.settings[key]
            if type(default) == 'boolean' then
                if type(v) == 'boolean' then cfg.settings[key] = v end
            elseif tonumber(v) then
                cfg.settings[key] = tonumber(v)
            end
        end
    end
    if tonumber(data.ver) ~= 2 then cfg.settings.accent = 1 end

    if type(data.enchant) == 'table' then
        cfg.enchant.mode   = tonumber(data.enchant.mode) or cfg.enchant.mode
        cfg.enchant.target = tonumber(data.enchant.target) or cfg.enchant.target
    end
    if type(data.names) == 'table' then
        for k, v in pairs(data.names) do
            if type(v) == 'string' then cfg.names[tostring(k)] = v end
        end
    end
    if type(data.amuletOnly) == 'table' then
        for k, v in pairs(data.amuletOnly) do
            if v == true then cfg.amuletOnly[tostring(k)] = true end
        end
    end
    if type(data.stats) == 'table' then
        for name, s in pairs(data.stats) do
            if type(s) == 'table' then
                cfg.stats[tostring(name)] = {ok = tonumber(s.ok) or 0, fail = tonumber(s.fail) or 0,
                                             level = tonumber(s.level) or 0, max = tonumber(s.max) or 0}
            end
        end
    end

    if type(data.logs) == 'table' then
        for k, l in pairs(data.logs) do
            if type(l) == 'table' and tonumber(l.item) and type(l.h) == 'string' then
                local last = tonumber(l.last)
                if not last then
                    local f, o
                    for ff, oo in l.h:gmatch('(%d+):([01])') do f, o = tonumber(ff), tonumber(oo) end
                    last = f and (f + o) or 0
                end
                cfg.logs[tostring(k)] = {item = tonumber(l.item), t = tonumber(l.t) or 0, h = l.h,
                                         last = last, u = tonumber(l.u) or (tonumber(l.t) or 0) * 1000}
            end
        end
    end

    local st = cfg.settings
    st.alpha  = clamp(st.alpha, 50, 100)
    st.glow   = clamp(st.glow, 0, 100)
    st.accent = clamp(math.floor(st.accent), 1, #ACCENTS)
    st.scale  = clamp(st.scale, 60, 250)
    cfg.enchant.target = clamp(math.floor(cfg.enchant.target), 1, 13)
    cfg.enchant.mode   = clamp(math.floor(cfg.enchant.mode), 1, 3)
end

 
local function accent(a, k)
    local c = ACCENTS[cfg.settings.accent].c
    k = k or 1
    return V4(c[1] * k, c[2] * k, c[3] * k, a or 1)
end
local function accU(a, k) return imgui.GetColorU32Vec4(accent(a, k)) end
local function acc2U(a, k)
    local c = ACCENTS[cfg.settings.accent].c2
    k = k or 1
    return U32(c[1] * k, c[2] * k, c[3] * k, a or 1)
end
local function mixU(t, a, k)
    local A = ACCENTS[cfg.settings.accent]
    k = k or 1
    return U32(lerp(A.c[1], A.c2[1], t) * k, lerp(A.c[2], A.c2[2], t) * k, lerp(A.c[3], A.c2[3], t) * k, a or 1)
end
local function glowK() return cfg.settings.glow / 60 end

 
local themeReady = false
local fontMain, fontMed, fontTitle, fontBig, fontSmall, fontLabel, fontSign

local function withFont(font, fn)
    if font then imgui.PushFont(font) end
    fn()
    if font then imgui.PopFont() end
end

local function findFont(names)
    for _, p in ipairs(names) do
        if doesFileExist(p) then return p end
    end
end

local function applyTheme()
    if not themeReady then return end
    local s = imgui.GetStyle()
    local c, col = s.Colors, imgui.Col
    s.WindowRounding, s.ChildRounding, s.PopupRounding = 18, 12, 10
    s.FrameRounding, s.GrabRounding, s.ScrollbarRounding = 10, 20, 20
    s.WindowPadding = P(14, 12)
    s.FramePadding  = P(10, 8)
    s.ItemSpacing   = P(10, 10)
    s.GrabMinSize   = 22
    s.ScrollbarSize = 8
    s.WindowBorderSize, s.ChildBorderSize, s.FrameBorderSize = 0, 0, 0

    c[col.Text]             = V4(0.93, 0.95, 1.0)
    c[col.TextDisabled]     = V4(0.55, 0.60, 0.74)
    c[col.WindowBg]         = V4(0.035, 0.045, 0.095, 0.96)
    c[col.ChildBg]          = V4(0, 0, 0, 0)
    c[col.PopupBg]          = V4(0.05, 0.06, 0.12, 0.98)
    c[col.Border]           = V4(0.16, 0.20, 0.34, 1)
    c[col.FrameBg]          = V4(0.07, 0.085, 0.16, 1)
    c[col.FrameBgHovered]   = V4(0.10, 0.12, 0.22, 1)
    c[col.FrameBgActive]    = V4(0.13, 0.15, 0.27, 1)
    c[col.CheckMark]        = accent(1)
    c[col.SliderGrab]       = accent(0.95, 0.95)
    c[col.SliderGrabActive] = accent(1)
    c[col.Button]           = V4(0.10, 0.12, 0.22, 1)
    c[col.ButtonHovered]    = V4(0.16, 0.18, 0.32, 1)
    c[col.ButtonActive]     = accent(1, 0.65)
    c[col.Separator]        = V4(0.14, 0.17, 0.30, 1)
    c[col.ScrollbarBg]      = V4(0, 0, 0, 0)
    c[col.ScrollbarGrab]    = V4(0.25, 0.30, 0.50, 1)
    c[col.TextSelectedBg]   = accent(0.4)
end

 
local b64idx = {}
do
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    for i = 1, #chars do b64idx[chars:byte(i)] = i - 1 end
end

local function b64decode(s)
    s = s:gsub('[^%w%+/=]', '')
    local out, n = {}, 0
    for i = 1, #s, 4 do
        local a, b, c, d = s:byte(i, i + 3)
        local v1, v2 = b64idx[a], b64idx[b]
        if not v1 or not v2 then break end
        local v3, v4 = c and b64idx[c], d and b64idx[d]
        local n24 = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        n = n + 1; out[n] = string.char(math.floor(n24 / 65536) % 256)
        if v3 then n = n + 1; out[n] = string.char(math.floor(n24 / 256) % 256) end
        if v4 then n = n + 1; out[n] = string.char(n24 % 256) end
    end
    return table.concat(out)
end

local icons = {}

local function loadIcon(name, b64)
    local ok, tex = pcall(function()
        if not doesDirectoryExist(cfgDir) then createDirectory(cfgDir) end
        local dir = cfgDir .. '/enchant_master'
        if not doesDirectoryExist(dir) then createDirectory(dir) end
        local path = dir .. '/' .. name .. '.png'
        local data = b64decode(b64)
        local f = io.open(path, 'rb')
        local same = false
        if f then same = (f:read('*a') == data); f:close() end
        if not same then
            local w = io.open(path, 'wb')
            if w then w:write(data); w:close() end
        end
        local t = imgui.CreateTextureFromFile(path)
        if not t then t = imgui.CreateTextureFromFileInMemory(data, #data) end
        return t
    end)
    if ok and tex then icons[name] = tex end
end

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    local ranges = io.Fonts:GetGlyphRangesCyrillic()

    computeScale(100)           
    local wd = getWorkingDirectory()
    local trebuc = wd .. '/lib/mimgui/trebucbd.ttf'
    local regular = findFont({'/system/fonts/Roboto-Regular.ttf', '/system/fonts/NotoSans-Regular.ttf',
                              '/system/fonts/DroidSans.ttf', trebuc})
    local bold    = findFont({'/system/fonts/Roboto-Bold.ttf', '/system/fonts/NotoSans-Bold.ttf',
                              '/system/fonts/DroidSans-Bold.ttf', trebuc}) or regular
    local script  = findFont({'/system/fonts/Roboto-Italic.ttf', '/system/fonts/NotoSans-Italic.ttf'}) or bold

    local function load(path, size)
        if path then return io.Fonts:AddFontFromFileTTF(path, math.floor(size * SC + 0.5), nil, ranges) end
    end
    fontMain  = load(regular, 17)
    fontSmall = load(regular, 15)
    fontMed   = load(bold, 19)
    fontLabel = load(bold, 15)
    fontTitle = load(bold, 26)
    fontBig   = load(bold, 34)
    fontSign  = load(script, 24)

    loadIcon('sharp', ICON_SHARP_B64)
    loadIcon('amulet', ICON_AMULET_B64)

    themeReady = true
    applyTheme()
    computeScale(cfg.settings.scale)
    pcall(function() io.FontGlobalScale = SC / SCB end)
end)

 
local function chat(text)
    pcall(sampAddChatMessage, u8:decode(text), -1)
end

local dbgOn, dbgT0 = false, 0
local function dbg(tag, str)
    if not dbgOn then return end
    local f = io.open(cfgDir .. '/enchant_master_log.txt', 'a')
    if not f then return end
    f:write(('%7.3f  %-7s %s\n'):format(os.clock() - dbgT0, tag, tostring(str):sub(1, 400)))
    f:close()
end

local sendSlotsPacket, sendStartPacket

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
local function unescapeU(s)
    return (s:gsub('\\u(%x%x%x%x)', function(h) return utf8char(tonumber(h, 16)) end))
end

 
local SHARP_ID, AMULET_ID = 3578, 7883
local DEFAULT_SHARP = SHARP_ID
local ITEM_NAMES = {[SHARP_ID] = 'Точилка', [AMULET_ID] = 'Амулет'}

local MODES = {
    {name = 'Амулет',           short = 'Амулет',  ids = {AMULET_ID}},
    {name = 'Точилка',          short = 'Точилка', ids = {SHARP_ID}},
    {name = 'Амулет + точилка', short = 'Оба',     ids = {AMULET_ID, SHARP_ID}},
}

local ABORT = T('Остановлено')

local fav  = {}
local inv  = {}
local plan = {}
local solo = nil    
local function runEntries() return solo and {solo} or plan end
local shop = {visible = false, category = 0, index = -1, left = -1, right = -1,
              need = DEFAULT_SHARP, needStamp = 0, ready = false, chance = 0,
              lastOut = 0, readyStamp = 0, cost = 0}
local ench = {running = false, cancel = false, result = nil, needAmulet = false, curItem = nil,
              n = 0, ok = 0, fail = 0, status = '', level = 0, runId = 0,
              evt = nil, errText = nil, skipped = 0, skipWhy = ''}
local ui = {picking = false, pickFrom = -1, hint = nil, scroll = 0, panelClosed = false, logOpen = {}}
local sessionId = os.time()
local armed = nil           
local armedStart             

local function resetShop()
    shop.index, shop.left, shop.right = -1, -1, -1
    shop.need, shop.needStamp, shop.ready, shop.chance = DEFAULT_SHARP, 0, false, 0
    shop.readyStamp = 0
end

local function invFind(id, exclude)
    local best, bestAmount
    for slot, s in pairs(inv) do
        if s.item == id and slot ~= exclude and (s.amount or 1) > 0 then
            local a = s.amount or 1
            if not best or a > bestAmount or (a == bestAmount and slot < best) then
                best, bestAmount = slot, a
            end
        end
    end
    return best
end

local function invCount(id, exclude)
    local n = 0
    for slot, s in pairs(inv) do
        if s.item == id and slot ~= exclude then n = n + (s.amount or 1) end
    end
    return n
end

local function sendSlots(index, left, right)
    shop.index, shop.left, shop.right = index, left, right
    sendSlotsPacket(index, left, right)
end

local function statFor(id)
    local key = tostring(id)
    if not cfg.stats[key] then cfg.stats[key] = {ok = 0, fail = 0, level = 0, max = 0} end
    return cfg.stats[key]
end

local function enchantName(item)
    return cfg.names[tostring(item)] or ((T('Предмет #%d')):format(item))
end

local function keyName(key)
    if tonumber(key) then return enchantName(tonumber(key)) end
    return key
end

local function rightGone()
    if shop.right < 0 then return false end
    local r = inv[shop.right]
    return (not r) or (r.amount or 1) <= 0
end

local function curInv()
    if shop.index < 0 then return nil end
    return inv[shop.index]
end

local function findEntry(slot)
    for i, e in ipairs(plan) do
        if e.slot == slot then return e, i end
    end
end

local function isForcedAmulet()
    local it = curInv()
    if not it then return false end
    if cfg.amuletOnly[tostring(it.item)] then return true end
    return shop.need == AMULET_ID
end

local function hint(text) ui.hint = {text = text, t = os.clock()} end

 
 
 
local logSeq = 0
local slotLog = {}

local function logAttempt(id, slot, from, ok)
    local key = slotLog[slot]
    local l = key and cfg.logs[key]
    if not (l and l.item == id and l.last == from) then
        l, key = nil, nil
        local bestU = -1
        for k, v in pairs(cfg.logs) do
            if v.item == id and v.last == from and (v.u or 0) > bestU then
                key, l, bestU = k, v, v.u or 0
            end
        end
    end
    if not l then
        logSeq = logSeq + 1
        key = tostring(os.time()) .. '_' .. tostring(id) .. '_' .. logSeq
        l = {item = id, t = os.time(), u = 0, last = from, h = ''}
        cfg.logs[key] = l
        local count, oldest, oldU = 0, nil, math.huge
        for k, v in pairs(cfg.logs) do
            count = count + 1
            if k ~= key and (v.u or 0) < oldU then oldest, oldU = k, v.u or 0 end
        end
        if count > 40 and oldest then cfg.logs[oldest] = nil end
    end
    l.h = l.h .. (l.h ~= '' and ',' or '') .. tostring(from) .. ':' .. (ok and '1' or '0')
    if #l.h > 4000 then l.h = (l.h:sub(-3500):gsub('^[^,]*,', '')) end
    l.last = ok and (from + 1) or from
    logSeq = logSeq + 1
    l.u = os.time() * 1000 + logSeq % 1000
    slotLog[slot] = key
    return key
end

 
 
 
 
 
 
 
 
 
 
local EV_INV, EV_SHOP = 0x34, 0x3B
local lastStartOut = 0

local u16, bytesToStr, huffDecode
do
local unpack_ = table.unpack or unpack

function bytesToStr(b, i, j)
    local parts, k = {}, i
    while k <= j do
        local e = math.min(j, k + 2047)
        parts[#parts + 1] = string.char(unpack_(b, k, e))
        k = e + 1
    end
    return table.concat(parts)
end

function u16(b, i) return b[i] + b[i + 1] * 256 end
local function u32(b, i) return b[i] + b[i + 1] * 256 + b[i + 2] * 65536 + b[i + 3] * 16777216 end


 
 
local bit_ = bit
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

 
function huffDecode(b, n, startBit, count)
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


end


local function readBytes(bs)
    local total = raknetBitStreamGetNumberOfBytesUsed(bs)
    if not total or total < 2 then return nil end
    local ptr = raknetBitStreamGetDataPtr(bs)
    if not ptr or ptr == 0 then return nil end
    local n = math.min(total, 4096)
    local p = ffi.cast('const uint8_t*', ffi.cast('uintptr_t', ptr))
    local b = {}
    for i = 1, n do b[i] = p[i - 1] end
    return b, n
end

local function inText(b, n)
    if n < 8 then return nil end
    local len, flag = u16(b, 5), b[7]
    if len == 0 or len > 60000 then return nil end
    if flag == 0 then
        if 7 + len > n then return nil end
        return bytesToStr(b, 8, 7 + len)
    elseif flag == 1 then
        local ok, s = pcall(huffDecode, b, n, 73, len)
        if ok and type(s) == 'string' and #s == len then return s end
    end
    return nil
end

local function applyInventory(d)
    if type(d) ~= 'table' or d.type ~= 1 or type(d.items) ~= 'table' then return end
    for _, it in ipairs(d.items) do
        if it.slot then
            local old = inv[it.slot]
            local keep = (old and old.item == it.item) and old.enchant or 0
            inv[it.slot] = it.item and {item = it.item, enchant = tonumber(it.enchant) or keep,
                                        amount = tonumber(it.amount) or 1} or nil
            local fresh = inv[it.slot]
            local st = fresh and it.slot == shop.index and cfg.stats[tostring(fresh.item)]
            if st and it.enchant ~= nil then st.level = fresh.enchant end
        end
    end
    for _, pe in ipairs(runEntries()) do
        local s = inv[pe.slot]
        if s and s.item == pe.item and pe.state ~= 'run' then pe.level = tonumber(s.enchant) or pe.level end
    end
end

 
local function commitAttempt(success)
    local evt = ench.evt
    ench.evt = nil
    local id = (ench.running and ench.curItem) or (curInv() and curInv().item)
    if cfg.settings.enabled and id then
        local s = statFor(id)
        if success then
            s.ok, ench.ok = s.ok + 1, ench.ok + 1
        else
            s.fail, ench.fail = s.fail + 1, ench.fail + 1
        end
        local cur = curInv()
        local from
        if evt and os.clock() - evt.t < 3 then from = evt.from end
        from = from or (ench.running and ench.level) or (cur and tonumber(cur.enchant)) or 0
        logAttempt(id, shop.index, from, success)
        markDirty()
    end
    ench.result = {ok = success, confirmed = true}
end

local function onCefEvent(ev, action, text)
    if ev == EV_INV then
        if action ~= 2 then return end
        local ok, d = pcall(decodeJson, text)
        if ok then applyInventory(d) end
    elseif ev == EV_SHOP then
        if action == 3 then
             
            shop.need = tonumber((text:gsub('[^%d]', ''))) or shop.need
            shop.needStamp = os.clock()
            return
        end
        local ok, d = pcall(decodeJson, text)
        if not ok or type(d) ~= 'table' then return end
        if action == 2 then
            shop.ready = (tonumber(d.available) or 0) == 1
            shop.readyStamp = os.clock()
            shop.cost = tonumber(d.cost) or shop.cost
            shop.chance = tonumber(d.chance) or 0
        elseif action == 1 then
             
            local okS = (tonumber(d.success) or 0) > 0
            local cur = curInv()
            local from
            if ench.running then
                from = ench.level
            else
                from = math.max(0, (cur and tonumber(cur.enchant) or 0) - (okS and 1 or 0))
            end
            ench.evt = {ok = okS, t = os.clock(), from = from}
            if shop.visible or ench.running then commitAttempt(okS) end
        end
    end
end

local function onSlotsOut(s)
    shop.lastOut = os.clock()
    local ok, d = pcall(decodeJson, s)
    if ok and type(d) == 'table' then
        shop.index = tonumber(d.index) or -1
        shop.left  = tonumber(d.left) or -1
        shop.right = tonumber(d.right) or -1
        if not ench.running then
            local sr = shop.right >= 0 and inv[shop.right]
            if sr then fav[sr.item] = shop.right end
        end
    end
end

local function onIn(id, bs)
    if id ~= 220 then return end
    local b, n = readBytes(bs)
    if not b or b[1] ~= 220 then return end
    local sub = b[2]
    if sub == 62 then
        if n >= 4 and b[3] == EV_SHOP then
            if b[4] >= 128 then
                shop.visible = true
                if shop.category == 0 then resetShop() end
                if armed and not armed.starting then
                    lua_thread.create(function()
                        wait(400)
                        if armed and not armed.starting and shop.visible then
                            chat((T('{FFD700}[Enchant Master]{FFFFFF} Цель +%d принята. Нажми на предмет в верстаке - заточка начнётся сама.')):format(armed.target))
                        end
                    end)
                end
            else
                shop.visible, shop.category = false, 0
            end
        end
    elseif sub == 84 and n >= 8 then
        local ev, action = b[3], b[4]
        if ev ~= EV_INV and ev ~= EV_SHOP then return end
        local text = inText(b, n)
        if not text then return end
        dbg('IN', ('%02X/%d %s'):format(ev, action, text))
        onCefEvent(ev, action, text)
    end
end

local function onOut(id, bs)
    if id ~= 220 then return end
    local b, n = readBytes(bs)
    if not b or b[1] ~= 220 then return end
    local sub = b[2]
    if sub == 66 then
        if n >= 4 and b[3] == EV_SHOP and b[4] < 128 then
            shop.visible, shop.category = false, 0
            if ench.running then ench.cancel = true end
        end
        return
    end
    if sub ~= 63 or n < 14 or b[3] ~= EV_SHOP then return end
    local action = b[8] + b[9] * 256
    local len = u16(b, 12)
    if 13 + len > n then return end
    local s = bytesToStr(b, 14, 13 + len)
    dbg('OUT', ('%d %s'):format(action, s))
    if action == 2 then lastStartOut = os.clock(); return end
    if action ~= 1 then return end
     
    if ench.running and not ench.cancel and shop.right >= 0 and not rightGone() then
        local r = s:match('"right":%s*(-?%d+)')
        if r and tonumber(r) == -1 then
            dbg('BLOCK', s)
            return false
        end
    end
    onSlotsOut(s)
     
    if armed and not armed.starting and not ench.running and shop.visible and shop.index >= 0 then
        armed.starting = true
        local slot, t0 = shop.index, os.clock()
        lua_thread.create(function() armedStart(slot, t0) end)
    end
end

do
    local function guard(fn)
        return function(id, bs)
            local ok, r = pcall(fn, id, bs)
            if ok then return r end
        end
    end
    local gIn, gOut = guard(onIn), guard(onOut)
    local rakOk = pcall(function()
        local R = require('RakLua')
        R.registerHandler(RakLuaEvents.INCOMING_PACKET, gIn)
        R.registerHandler(RakLuaEvents.OUTGOING_PACKET, gOut)
    end)
    if not rakOk then
        onReceivePacket = gIn
        onSendPacket = gOut
    end
end

local function sendOut(ev, action, payload)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, ev)
    raknetBitStreamWriteInt32(bs, -1)
    raknetBitStreamWriteInt32(bs, action)
    raknetBitStreamWriteInt16(bs, #payload)
    raknetBitStreamWriteString(bs, payload)
    if not pcall(raknetSendBitStream, bs) then pcall(raknetSendBitStreamEx, bs, 1, 9, 0) end
    raknetDeleteBitStream(bs)
end

function sendSlotsPacket(index, left, right)
    sendOut(EV_SHOP, 1, ('{"index":%d,"left":%d,"right":%d}'):format(index, left, right))
end

function sendStartPacket()
    dbg('SCRIPT', 'startEnchant')
    sendOut(EV_SHOP, 2, '0')
end

local function parseEnchantMessage(text)
    if not cfg.settings.enabled then return end
    local clean = u8((text:gsub('{%x%x%x%x%x%x}', '')))
    if dbgOn and (clean:find(T('точ'), 1, true) or clean:find(T('улучш'), 1, true)) then dbg('CHAT', clean) end
    if not clean:find(T('удалось улучшить предмет'), 1, true) then return end

    local name = clean:match(T('предмет') .. '%s+(.-)%s+%S+%s+%+%d+%s+' .. T('на') .. '%s+%+%d+')
    local id = (ench.running and ench.curItem) or (curInv() and curInv().item)
    if name and id then
        cfg.names[tostring(id)] = (name:gsub('%s*%(id:?%s*%d+%)', ''))
        markDirty()
    end
end

function sampev.onServerMessage(color, text)
    pcall(parseEnchantMessage, text)
end

 
local function pickSlot(mode)
    for _, id in ipairs(mode.ids) do
        local slot = fav[id]
        if not (slot and slot ~= shop.index and inv[slot] and inv[slot].item == id) then
            slot = invFind(id, shop.index)
        end
        if slot then return slot end
    end
end

local function placed()
    return shop.right >= 0 and inv[shop.right] ~= nil and shop.ready
end

local function onLocked()
    local cur = curInv()
    local lvl = (cur and tonumber(cur.enchant)) or ench.level or 0
    local okm, money = pcall(function() return getPlayerMoney(PLAYER_HANDLE) end)
    if okm and type(money) == 'number' and shop.cost > 0 and money < shop.cost then
        return (T('не хватает денег на заточку (нужно %d)')):format(shop.cost)
    end
    if cur and lvl > 0 then
        statFor(cur.item).max = lvl
        markDirty()
    end
    return (T('максимум +%d, выше этот предмет не точится')):format(lvl)
end

local QUIET_AFTER_GAME = 0.3
local SETTLE = 0.25
local ENCHANT_DELAY = 120

local function ensurePlaced(mode, forced)
    if placed() then return nil end

    local inactive = 0
    for _ = 1, 6 do
        while os.clock() - shop.lastOut < QUIET_AFTER_GAME and not ench.cancel do wait(20) end
        if ench.cancel then return ABORT end

        local slot = pickSlot(mode)
        if not slot then
            if forced then return T('нужен Точильный Амулет, а его нет в сумке') end
            if mode == MODES[1] then return T('закончились амулеты') end
            if mode == MODES[2] then return T('закончились точилки') end
            return T('закончились точилки и амулеты')
        end

        shop.ready = false
        sendSlots(shop.index, shop.left, slot)
        local t0 = os.clock()
        while not shop.ready and not ench.cancel and os.clock() - t0 < 2.5 do wait(20) end
        if ench.cancel then return ABORT end

        if shop.ready then
            local settle = os.clock()
            while os.clock() - settle < SETTLE and not ench.cancel do wait(20) end
            if placed() and shop.lastOut <= t0 then return nil end
        elseif shop.readyStamp > t0 then
            inactive = inactive + 1
            if inactive >= 2 then return onLocked() end
        end
    end
    return T('не удалось положить расходник в верстак')
end

local function entryMode(e)
    if cfg.amuletOnly[tostring(e.item)] or (shop.index == e.slot and shop.need == AMULET_ID) then
        return MODES[1], true
    end
    return MODES[clamp(math.floor(e.mode), 1, #MODES)], false
end

 
local function switchTo(e)
    local t0 = os.clock()
    shop.right, shop.ready = -1, false
    shop.need, shop.needStamp = DEFAULT_SHARP, 0
    sendSlots(e.slot, -1, -1)
    while shop.readyStamp <= t0 and not ench.cancel and os.clock() - t0 < 2.5 do wait(20) end
    if ench.cancel then return false, ABORT end
    if shop.readyStamp <= t0 then return false, T('верстак не ответил при смене предмета') end
    local t1 = os.clock()
    while shop.needStamp <= t0 and not ench.cancel and os.clock() - t1 < 1.0 do wait(20) end
    if ench.cancel then return false, ABORT end
    return true
end

local function failKind(err)
    return (err == ABORT) and 'abort' or 'fail', err
end

 
local function trySend(e, maxWait)
    local mode, forced = entryMode(e)
    local err = ensurePlaced(mode, forced)
    if err then return failKind(err) end

    local t0 = os.clock()
    while not shop.ready and not ench.cancel and os.clock() - t0 < 3 do wait(20) end
    if ench.cancel then return 'abort', ABORT end
    wait(30)
    if not placed() then
        err = ensurePlaced(mode, forced)
        if err then return failKind(err) end
    end

    ench.result, ench.needAmulet, ench.errAt = nil, false, nil
    ench.evt, ench.errText = nil, nil
    ench.curItem = e.item
    sendStartPacket()

    t0 = os.clock()
    while not ench.result and not ench.needAmulet and not ench.errText and not ench.cancel and os.clock() - t0 < maxWait do
         
        if ench.evt and os.clock() - ench.evt.t > 1.5 then
            ench.evt = nil
            return 'noconfirm'
        end
        wait(20)
    end
    if ench.cancel then return 'abort', ABORT end
    if ench.result then return 'ok' end
    if ench.needAmulet then ench.needAmulet = false; return 'amulet' end
    if ench.errText then local m = ench.errText; ench.errText = nil; return 'error', m end
    return 'timeout'
end

 
local function enchantEntry(e)
    local level = tonumber((inv[e.slot] or {}).enchant) or e.level or 0
    local tries, amuletTries, errTries = 0, 0, 0

    while true do
        if ench.cancel then return 'abort', ABORT end
        if not shop.visible then return 'abort', T('Верстак закрыт') end

        local cur = inv[e.slot]
        if not cur or cur.item ~= e.item then return 'fail', T('предмет не найден в инвентаре') end

        e.level = level
        if level >= e.target then return 'done', (T('уже +%d')):format(level) end
        local sk = cfg.stats[tostring(e.item)]
        if sk and (sk.max or 0) > 0 and level >= sk.max then
            return 'fail', (T('максимум +%d, выше этот предмет не точится')):format(level)
        end

        if shop.index ~= e.slot then
            local ok, err = switchTo(e)
            if not ok then return failKind(err) end
        end
        if rightGone() then shop.right, shop.ready = -1, false end

        tries = tries + 1
        ench.level = level
        ench.status = (T('%s: +%d > +%d, попытка %d')):format(enchantName(e.item), level, e.target, tries)

        local st, msg = trySend(e, 4)
        if st == 'timeout' or st == 'noconfirm' then
            shop.ready = false
            st, msg = trySend(e, 6)
        end

        if st == 'abort' or st == 'fail' then
            return st, msg
        elseif st == 'amulet' then
            amuletTries = amuletTries + 1
            if amuletTries > 3 then return 'fail', T('сервер требует амулет, но заточка не проходит') end
            shop.right, shop.ready = -1, false
            wait(200)
        elseif st == 'error' then
            errTries = errTries + 1
            ench.skipped, ench.skipWhy = ench.skipped + 1, msg
            if errTries >= 2 then
                return 'fail', (T('сервер отклонил попытку: %s (в лог не записано)')):format(msg)
            end
            wait(300)
        elseif st == 'noconfirm' then
            ench.skipped, ench.skipWhy = ench.skipped + 1, T('нет уведомления об улучшении')
            return 'fail', T('сервер не подтвердил попытку (нет уведомления об улучшении), в лог не записано')
        elseif st == 'timeout' then
            return 'fail', T('верстак не ответил: заточка не началась (в лог не записано)')
        else
            errTries = 0
            local res = ench.result
            ench.n = ench.n + 1
            local tRes = os.clock()
            local waited = os.clock()
            while os.clock() - waited < 0.35 and not ench.cancel do
                if rightGone() then break end
                if shop.readyStamp > tRes and shop.ready then break end
                wait(20)
            end
            if ench.cancel then return 'abort', ABORT end
            if rightGone() then shop.right, shop.ready = -1, false end

            local now = inv[e.slot]
            local seen = now and tonumber(now.enchant) or level
            if res.ok then level = math.max(seen, level + 1) else level = seen end
            e.level = level

            local stat = cfg.stats[tostring(e.item)]
            if stat then
                stat.level = level
                if res.ok and (stat.max or 0) > 0 and level > stat.max then stat.max = 0 end
                markDirty()
            end
            if res.ok then
                chat((T('{FFD700}[Enchant Master]{FFFFFF} %s: {30E060}+%d{FFFFFF} (цель +%d)')):format(enchantName(e.item), level, e.target))
            end
            if res.ok and level >= e.target then return 'done', (T('достигнут +%d')):format(level) end
            wait(ENCHANT_DELAY)
        end
    end
end

local function nextPending()
    for _, e in ipairs(runEntries()) do
        if e.state == 'wait' then return e end
    end
end

local function runPlan()
    ench.n = 0
    local nDone, nFail = 0, 0
    while true do
        local e = nextPending()
        if not e then break end
        e.state, e.note = 'run', ''
        local kind, msg = enchantEntry(e)
        if kind == 'abort' then
            e.state = 'wait'
            return msg
        elseif kind == 'done' then
            e.state, e.note = 'done', msg or ''
            nDone = nDone + 1
        else
            e.state = 'fail'
            e.note = (msg or '') .. (T('  (+%d из +%d)')):format(e.level or 0, e.target)
            nFail = nFail + 1
        end
    end
    if nFail > 0 then
        local first
        for _, e in ipairs(runEntries()) do
            if e.state == 'fail' then first = e; break end
        end
        local s = (T('Готово: %d успешно, %d с ошибкой')):format(nDone, nFail)
        if first then s = s .. ': ' .. enchantName(first.item) .. ' - ' .. first.note end
        return s
    end
    return (T('Готово: заточено предметов - %d')):format(nDone)
end

 
local function getTarget()
    local e = shop.index >= 0 and findEntry(shop.index)
    return e and e.target or cfg.enchant.target
end
local function getMode()
    local e = shop.index >= 0 and findEntry(shop.index)
    return e and e.mode or cfg.enchant.mode
end
local function setTarget(v)
    local e = shop.index >= 0 and findEntry(shop.index)
    if e then e.target = v; if e.state ~= 'run' then e.state, e.note = 'wait', '' end end
    cfg.enchant.target = v
    markDirty()
end
local function setMode(v)
    local e = shop.index >= 0 and findEntry(shop.index)
    if e then e.mode = v end
    cfg.enchant.mode = v
    markDirty()
end

local MAX_PLAN = 50
local MAX_ROWS = 5

 
local function makeEntry()
    local it = curInv()
    if not it then return nil, T('Сначала положи предмет в верстак') end
    local level = tonumber(it.enchant) or 0
    local target = cfg.enchant.target
    if target <= level then
        return nil, (T('Цель должна быть выше текущего уровня +%d')):format(level)
    end
    return {slot = shop.index, item = it.item, level = level, target = target,
            mode = cfg.enchant.mode, state = 'wait', note = ''}
end

local function addDraft()
    if not curInv() then return false, T('Сначала положи предмет в верстак') end
    if findEntry(shop.index) then return true end
    if #plan >= MAX_PLAN then return false, (T('В плане максимум %d предметов')):format(MAX_PLAN) end
    local e, msg = makeEntry()
    if not e then return false, msg end
    plan[#plan + 1] = e
    ui.scroll = math.max(0, #plan - MAX_ROWS)    
    return true
end

local function onAddGoal()
    if ench.running then return end
    if ui.picking then ui.picking = false; return end
    local ok, msg = addDraft()
    if not ok then hint(msg); return end
    if #plan >= MAX_PLAN then
        hint((T('План заполнен: максимум %d предметов')):format(MAX_PLAN))
        return
    end
    ui.picking, ui.pickFrom = true, shop.index
end

local function selectEntry(e)
    if ench.running or not shop.visible then return end
    local it = inv[e.slot]
    if not it or it.item ~= e.item then hint(T('Предмета нет в инвентаре')); return end
    ui.picking = false
    if shop.index == e.slot then return end
    shop.right, shop.ready = -1, false
    shop.need, shop.needStamp = DEFAULT_SHARP, 0
    sendSlots(e.slot, -1, -1)
end

local function stopEnchant()
    if ench.running then ench.cancel = true end
end

local runReq = false
local function runJob()
        local ok, res = pcall(runPlan)
        ench.running = false
        local list = runEntries()
        solo = nil
        for _, e in ipairs(list) do
            if e.state == 'run' then e.state = 'wait' end
        end
        ench.status = ok and res or tostring(res)
        if ench.status == ABORT then
            chat(T('{FFD700}[Enchant Master]{FFFFFF} Заточка остановлена'))
        end
        if ench.status ~= ABORT then
            chat('{FFD700}[Enchant Master]{FFFFFF} ' .. ench.status)
            chat((T('{FFD700}[Enchant Master]{FFFFFF} Попыток: %d, успешно: %d, неудачно: %d')):format(ench.ok + ench.fail, ench.ok, ench.fail))
            for _, e in ipairs(list) do
                if e.state == 'fail' then
                    chat('{FF6060} - ' .. enchantName(e.item) .. ': {FFFFFF}' .. e.note)
                end
            end
        end
end

local function startPlan()
    if ench.running then return end
    if not cfg.settings.enabled then
        hint(T('Скрипт выключен в настройках'))
        return
    end
    if not shop.visible then hint(T('Открой верстак')); return end
     
     
    solo = nil
    if #plan == 0 then
        if not curInv() then hint(T('Положи предмет в верстак и выбери цель')); return end
        local e, msg = makeEntry()
        if not e then hint(msg); return end
        solo = e
    end

    ui.picking = false
    for _, e in ipairs(runEntries()) do e.state, e.note = 'wait', '' end
    ench.running, ench.cancel = true, false
    ench.runId = os.time()
    ench.status = T('Запуск...')
    runReq = true
end

local function resetPlan()
    if ench.running then return end
    plan = {}
    ui.picking, ui.scroll = false, 0
    ench.status = ''
    ench.ok, ench.fail, ench.n = 0, 0, 0
end


 
 
 
local ARM_TTL = 600

local function startSolo(slot, t0)
     
    local w0 = os.clock()
    while shop.readyStamp <= t0 and os.clock() - w0 < 2 and not ench.cancel do wait(20) end
    wait(150)

    local a = armed
    if not a or ench.running or not shop.visible or shop.index ~= slot then
        if a then a.starting = false end
        return
    end
    local it = inv[slot]
    if not it then
        a.starting = false
        chat(T('{FFD700}[Enchant Master]{FFFFFF} {FF6060}Предмет не найден в инвентаре, нажми на него ещё раз'))
        return
    end
    local level = tonumber(it.enchant) or 0
    if level >= a.target then
        a.starting = false
        chat((T('{FFD700}[Enchant Master]{FFFFFF} {FF6060}Предмет уже +%d, цель +%d. Выбери другой предмет или введи другую команду')):format(level, a.target))
        return
    end
    local sk = cfg.stats[tostring(it.item)]
    if sk and (sk.max or 0) > 0 and level >= sk.max then
        a.starting = false
        chat((T('{FFD700}[Enchant Master]{FFFFFF} {FF6060}У этого предмета максимум +%d, выше он не точится')):format(sk.max))
        return
    end

    solo = {slot = slot, item = it.item, level = level, target = a.target,
            mode = cfg.enchant.mode, state = 'wait', note = ''}
    armed = nil
    ench.running, ench.cancel = true, false
    ench.runId = os.time()
    ench.ok, ench.fail, ench.n = 0, 0, 0
    ench.status = T('Запуск...')
    chat((T('{FFD700}[Enchant Master]{FFFFFF} Точу {FFFFFF}%s{FFFFFF}: +%d > +%d. Остановить: {FFD700}/em stop')):format(enchantName(it.item), level, a.target))
    runJob()
end
armedStart = startSolo

local function cmdTarget(n)
    return function()
        if not cfg.settings.enabled then
            chat(T('{FFD700}[Enchant Master]{FFFFFF} {FF6060}Скрипт выключен (/em - включить)'))
            return
        end
        if ench.running then
            chat(T('{FFD700}[Enchant Master]{FFFFFF} {FF6060}Заточка уже идёт. Остановить: /em stop'))
            return
        end
        local mode = MODES[clamp(math.floor(cfg.enchant.mode), 1, #MODES)]
        armed = {target = n, t = os.clock(), starting = false}
        if shop.visible and curInv() then
             
            armed.starting = true
            local slot = shop.index
            lua_thread.create(function() armedStart(slot, -1) end)
            return
        end
        chat((T('{FFD700}[Enchant Master]{FFFFFF} Команда принята: точим до {30E060}+%d{FFFFFF} (расходник: %s). Открой верстак и нажми на предмет.')):format(n, mode.name))
    end
end

local function cmdStop()
    if ench.running then
        ench.cancel = true
    elseif armed then
        armed = nil
        chat(T('{FFD700}[Enchant Master]{FFFFFF} Команда отменена'))
    else
        chat(T('{FFD700}[Enchant Master]{FFFFFF} Нечего останавливать'))
    end
end

local menu = {open = false, alpha = 0, eased = 0, duration = 0.22}
local function toggleMenu() menu.open = not menu.open end



local function setEnabled(value)
    cfg.settings.enabled = value
    if not value then stopEnchant() end
    markDirty()
end

local function cmdEm(param)
    param = (param or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local low = param:lower()
    if low == '' then toggleMenu(); return end
    if low == 'stop' or param == T('стоп') then cmdStop(); return end
    local n = tonumber(param:match('^%+?(%d+)$'))
    if not n or n < 1 or n > 13 then
        chat(T('{FFD700}[Enchant Master]{FFFFFF} {FF6060}/em 13 - точить до +13, /em stop - стоп, /em - меню'))
        return
    end
    cmdTarget(n)()
end

local inputs = {
    alpha = new.int(96),
    glow  = new.int(60),
    scale = new.int(100),
}

local function syncUI()
    inputs.alpha[0] = cfg.settings.alpha
    inputs.glow[0]  = cfg.settings.glow
    inputs.scale[0] = cfg.settings.scale
end

 
local D, IC = {}, {}
local anim = {}

local function approach(key, target, speed)
    local v = anim[key] or target
    v = v + (target - v) * clamp(imgui.GetIO().DeltaTime * (speed or 14), 0, 1)
    anim[key] = v
    return v
end

function D.txt(dl, font, x, y, col, s)
    if font then imgui.PushFont(font) end
    dl:AddText(P(x, y), col, s)
    if font then imgui.PopFont() end
end

function D.tw(font, s)
    if font then imgui.PushFont(font) end
    local v = imgui.CalcTextSize(s).x / SC
    if font then imgui.PopFont() end
    return v
end

function D.ctxt(dl, font, x, y, w, h, col, s)
    if font then imgui.PushFont(font) end
    local ts = imgui.CalcTextSize(s)
    dl:AddText(P(x + (w - ts.x / SC) / 2, y + (h - ts.y / SC) / 2), col, s)
    if font then imgui.PopFont() end
end

 
 
function D.hit(id, x, y, w, h)
    trackTouch()
    local x1, y1, x2, y2 = TX(x), TY(y), TX(x + w), TY(y + h)
    if HITCLIP then
         
        x1, y1 = math.max(x1, HITCLIP[1]), math.max(y1, HITCLIP[2])
        x2, y2 = math.min(x2, HITCLIP[3]), math.min(y2, HITCLIP[4])
        if x2 - x1 < 1 or y2 - y1 < 1 then return false, false end
    end
    imgui.SetCursorScreenPos(P(x1, y1))
    local pressed = imgui.InvisibleButton('##h' .. id .. '_' .. math.floor(x) .. '_' .. math.floor(y), P(x2 - x1, y2 - y1))
    local active = imgui.IsItemActive()
    local still = true
    pcall(function()
        local dd = imgui.GetMouseDragDelta(0, 0)
        still = math.abs(dd.x) + math.abs(dd.y) < 14 * SC
    end)
    return pressed and still, active and still
end

function D.glowCircle(dl, cx, cy, r, strength)
    local g = glowK()
    if g < 0.02 then return end
    for i = 1, 8 do
        local k = (1 - i / 9) ^ 2 * (strength or 0.2) * g
        dl:AddCircle(P(cx, cy), r + i * 2, accU(k), 48, 2)
    end
end

function D.glowRect(dl, x, y, w, h, r, strength)
    local g = glowK()
    if g < 0.02 then return end
    for i = 1, 6 do
        local k = (1 - i / 7) ^ 2 * (strength or 0.25) * g
        dl:AddRect(P(x - i * 1.5, y - i * 1.5), P(x + w + i * 1.5, y + h + i * 1.5), accU(k), r + i * 1.5, 15, 1.5)
    end
end

function D.gloss(dl, x, y, w, h, r, a)
    dl:AddRectFilled(P(x + 4, y + 2), P(x + w - 4, y + h * 0.5), U32(1, 1, 1, a or 0.12), math.max(2, r - 3))
end

function D.pill(dl, x, y, w, h, cL, cR, r)
    r = math.min(r or 8, h / 2, w / 2)
    dl:AddRectFilled(P(x, y), P(x + r * 2, y + h), cL, r)
    dl:AddRectFilled(P(x + w - r * 2, y), P(x + w, y + h), cR, r)
    dl:AddRectFilledMultiColor(P(x + r, y), P(x + w - r, y + h), cL, cR, cR, cL)
end

function D.box(dl, x, y, w, h, r, hot)
    r = math.min(r, 8)
    dl:AddRectFilled(P(x, y), P(x + w, y + h), U32(0.055, 0.068, 0.13, 0.96), r)
    if hot then
        D.glowRect(dl, x, y, w, h, r, 0.22)
        dl:AddRect(P(x, y), P(x + w, y + h), accU(0.85), r, 15, 1.5)
    else
        dl:AddRect(P(x, y), P(x + w, y + h), U32(0.16, 0.20, 0.34, 1), r, 15, 1)
    end
end

function D.dashed(dl, x0, y0, x1, y1, col)
    local dash, gap = 6, 5
    local x = x0
    while x < x1 do
        local e = math.min(x + dash, x1)
        dl:AddLine(P(x, y0), P(e, y0), col, 1.3)
        dl:AddLine(P(x, y1), P(e, y1), col, 1.3)
        x = x + dash + gap
    end
    local y = y0
    while y < y1 do
        local e = math.min(y + dash, y1)
        dl:AddLine(P(x0, y), P(x0, e), col, 1.3)
        dl:AddLine(P(x1, y), P(x1, e), col, 1.3)
        y = y + dash + gap
    end
end

function D.ring(dl, cx, cy, r, frac, col, back, thick)
    local seg = 56
    local start = -math.pi / 2
    for i = 0, seg - 1 do
        local a0 = start + i / seg * math.pi * 2
        local a1 = start + (i + 1) / seg * math.pi * 2
        local c = ((i + 0.5) / seg <= frac) and col or back
        dl:AddLine(P(cx + math.cos(a0) * r, cy + math.sin(a0) * r),
                   P(cx + math.cos(a1) * r, cy + math.sin(a1) * r), c, thick)
    end
end

local SEG_T = {0.30, 0.65, 0.90, 1.0, 0.75, 0.30, 0.0, 0.0}

local function chamferPts(x0, y0, x1, y1, c)
    return {P(x0 + c, y0), P(x1 - c, y0), P(x1, y0 + c), P(x1, y1 - c),
            P(x1 - c, y1), P(x0 + c, y1), P(x0, y1 - c), P(x0, y0 + c)}
end

function D.chamferLine(dl, x0, y0, x1, y1, c, a, k, th)
    local p = chamferPts(x0, y0, x1, y1, c)
    for i = 1, 8 do
        dl:AddLine(p[i], p[i % 8 + 1], mixU(SEG_T[i], a, k), th)
    end
end

function D.chamferFill(dl, x0, y0, x1, y1, c, col)
    dl:AddRectFilled(P(x0, y0 + c), P(x1, y1 - c), col, 0)
    dl:AddRectFilled(P(x0 + c, y0), P(x1 - c, y0 + c), col, 0)
    dl:AddRectFilled(P(x0 + c, y1 - c), P(x1 - c, y1), col, 0)
    dl:AddTriangleFilled(P(x0, y0 + c), P(x0 + c, y0), P(x0 + c, y0 + c), col)
    dl:AddTriangleFilled(P(x1 - c, y0), P(x1, y0 + c), P(x1 - c, y0 + c), col)
    dl:AddTriangleFilled(P(x1, y1 - c), P(x1 - c, y1), P(x1 - c, y1 - c), col)
    dl:AddTriangleFilled(P(x0 + c, y1), P(x0, y1 - c), P(x0 + c, y1 - c), col)
end

 
function D.neon(dl, bg, x0, y0, x1, y1, c)
    local g = glowK()
    if g > 0.02 then
        for i = 1, 7 do
            local a = (1 - i / 8) ^ 2 * 0.30 * g
            D.chamferLine(bg, x0 - i * 2, y0 - i * 2, x1 + i * 2, y1 + i * 2, c + i * 2, a, 1, 2)
        end
    end
    D.chamferFill(dl, x0, y0, x1, y1, c, U32(0.032, 0.040, 0.085, cfg.settings.alpha / 100))
    local top, bot = U32(0.12, 0.35, 0.95, 0.12), U32(0.12, 0.35, 0.95, 0)
    dl:AddRectFilledMultiColor(P(x0 + c, y0 + 2), P(x1 - c, y0 + 130), top, top, bot, bot)
    D.chamferLine(dl, x0 + 1, y0 + 1, x1 - 1, y1 - 1, c, 1, 1, 2)
    D.chamferLine(dl, x0 + 6, y0 + 6, x1 - 6, y1 - 6, math.max(4, c - 4), 0.16, 1, 1)
end

 
function IC.star(dl, cx, cy, r, col)
    local pts = {{0, -1}, {0.22, -0.22}, {1, 0}, {0.22, 0.22}, {0, 1}, {-0.22, 0.22}, {-1, 0}, {-0.22, -0.22}}
    for i = 1, 8 do
        local a, b = pts[i], pts[i % 8 + 1]
        dl:AddTriangleFilled(P(cx, cy), P(cx + a[1] * r, cy + a[2] * r), P(cx + b[1] * r, cy + b[2] * r), col)
    end
end

function IC.gem(dl, cx, cy, r, a)
    a = a or 1
    local p1, p2 = P(cx - 0.55 * r, cy - 0.6 * r), P(cx + 0.55 * r, cy - 0.6 * r)
    local p3, p4, p5 = P(cx + r, cy - 0.05 * r), P(cx, cy + r), P(cx - r, cy - 0.05 * r)
    local m = P(cx, cy - 0.05 * r)
    dl:AddTriangleFilled(m, p1, p2, mixU(0.1, a, 1.0))
    dl:AddTriangleFilled(m, p2, p3, mixU(0.5, a, 0.85))
    dl:AddTriangleFilled(m, p3, p4, mixU(0.9, a, 0.7))
    dl:AddTriangleFilled(m, p4, p5, mixU(0.7, a, 0.6))
    dl:AddTriangleFilled(m, p5, p1, mixU(0.3, a, 0.8))
end

local function quad(dl, p1, p2, p3, p4, col)
    dl:AddTriangleFilled(p1, p2, p3, col)
    dl:AddTriangleFilled(p1, p3, p4, col)
end

function IC.cube(dl, cx, cy, col)
    quad(dl, P(cx, cy - 9), P(cx + 9, cy - 4.5), P(cx, cy), P(cx - 9, cy - 4.5), col)
    quad(dl, P(cx - 9, cy - 4.5), P(cx, cy), P(cx, cy + 9), P(cx - 9, cy + 4.5), U32(0.2, 0.55, 0.95, 1))
    quad(dl, P(cx, cy), P(cx + 9, cy - 4.5), P(cx + 9, cy + 4.5), P(cx, cy + 9), U32(0.35, 0.4, 0.95, 1))
end

function IC.target(dl, cx, cy, col)
    dl:AddCircle(P(cx, cy), 8, col, 20, 2)
    dl:AddCircleFilled(P(cx, cy), 3, col, 12)
    dl:AddLine(P(cx, cy - 11), P(cx, cy - 6), col, 2)
    dl:AddLine(P(cx, cy + 11), P(cx, cy + 6), col, 2)
    dl:AddLine(P(cx - 11, cy), P(cx - 6, cy), col, 2)
    dl:AddLine(P(cx + 11, cy), P(cx + 6, cy), col, 2)
end

function IC.flag(dl, cx, cy, col)
    dl:AddLine(P(cx - 6, cy - 9), P(cx - 6, cy + 10), col, 2)
    dl:AddTriangleFilled(P(cx - 5, cy - 9), P(cx + 8, cy - 4), P(cx - 5, cy + 2), col)
end

function IC.dice(dl, x, y, s, col)
    dl:AddRectFilled(P(x, y), P(x + s, y + s), col, s * 0.22)
    local d = U32(1, 1, 1, 0.95)
    for _, p in ipairs({{0.28, 0.28}, {0.72, 0.28}, {0.5, 0.5}, {0.28, 0.72}, {0.72, 0.72}}) do
        dl:AddCircleFilled(P(x + s * p[1], y + s * p[2]), s * 0.075, d, 8)
    end
end

function IC.trash(dl, cx, cy, col)
    dl:AddLine(P(cx - 7, cy - 5), P(cx + 7, cy - 5), col, 2)
    dl:AddLine(P(cx - 2, cy - 8), P(cx + 2, cy - 8), col, 2)
    dl:AddLine(P(cx - 5, cy - 3), P(cx - 4, cy + 8), col, 2)
    dl:AddLine(P(cx + 5, cy - 3), P(cx + 4, cy + 8), col, 2)
    dl:AddLine(P(cx - 4, cy + 8), P(cx + 4, cy + 8), col, 2)
    dl:AddLine(P(cx, cy - 2), P(cx, cy + 6), col, 1.5)
end

function IC.refresh(dl, cx, cy, col)
    local n = 14
    for i = 0, n - 1 do
        local a0 = 0.5 + i * (1.55 * math.pi / n)
        local a1 = 0.5 + (i + 1) * (1.55 * math.pi / n)
        dl:AddLine(P(cx + math.cos(a0) * 7, cy + math.sin(a0) * 7), P(cx + math.cos(a1) * 7, cy + math.sin(a1) * 7), col, 2)
    end
    dl:AddTriangleFilled(P(cx + 7, cy - 6), P(cx + 11, cy + 1), P(cx + 3, cy + 1), col)
end

function IC.play(dl, cx, cy, col)
    dl:AddTriangleFilled(P(cx - 6, cy - 9), P(cx + 8, cy), P(cx - 6, cy + 9), col)
end

function IC.stop(dl, cx, cy, col)
    dl:AddRectFilled(P(cx - 7, cy - 7), P(cx + 7, cy + 7), col, 3)
end

function IC.plus(dl, cx, cy, col, s)
    s = s or 7
    dl:AddLine(P(cx - s, cy), P(cx + s, cy), col, 2.2)
    dl:AddLine(P(cx, cy - s), P(cx, cy + s), col, 2.2)
end

function IC.cross(dl, cx, cy, col, s)
    s = s or 7
    dl:AddLine(P(cx - s, cy - s), P(cx + s, cy + s), col, 2.2)
    dl:AddLine(P(cx + s, cy - s), P(cx - s, cy + s), col, 2.2)
end

function IC.pencil(dl, cx, cy, col)
    dl:AddLine(P(cx - 5, cy + 5), P(cx + 5, cy - 5), col, 3)
    dl:AddTriangleFilled(P(cx - 7, cy + 7), P(cx - 7, cy + 3), P(cx - 3, cy + 7), col)
end

function IC.check(dl, cx, cy, col)
    dl:AddLine(P(cx - 6, cy), P(cx - 2, cy + 4), col, 2.5)
    dl:AddLine(P(cx - 2, cy + 4), P(cx + 6, cy - 5), col, 2.5)
end

function IC.warn(dl, cx, cy, col)
    dl:AddCircle(P(cx, cy), 9, col, 20, 2)
    dl:AddLine(P(cx, cy - 4), P(cx, cy + 1), col, 2.2)
    dl:AddCircleFilled(P(cx, cy + 5), 1.4, col, 8)
end

function IC.nav(dl, kind, cx, cy, col)
    if kind == 'stats' then
        dl:AddRectFilled(P(cx - 9, cy + 1), P(cx - 4, cy + 9), col, 3)
        dl:AddRectFilled(P(cx - 2, cy - 4), P(cx + 3, cy + 9), col, 3)
        dl:AddRectFilled(P(cx + 5, cy - 9), P(cx + 10, cy + 9), col, 3)
    elseif kind == 'items' then
        IC.cube(dl, cx, cy, col)
    elseif kind == 'settings' then
        dl:AddCircle(P(cx, cy), 5, col, 16, 2)
        for _, d in ipairs({{0, -9, 0, -6}, {0, 9, 0, 6}, {-9, 0, -6, 0}, {9, 0, 6, 0}}) do
            dl:AddLine(P(cx + d[1], cy + d[2]), P(cx + d[3], cy + d[4]), col, 2.5)
        end
    else
        dl:AddCircle(P(cx, cy), 9, col, 20, 2)
        dl:AddCircleFilled(P(cx, cy - 4), 1.8, col, 8)
        dl:AddLine(P(cx, cy - 1), P(cx, cy + 5), col, 2.5)
    end
end

 
function D.consumable(dl, kind, x, y, s, alpha)
    alpha = alpha or 1
    local tex = icons[kind]
    if tex then
        dl:AddImage(tex, P(x, y), P(x + s, y + s), P(0, 0), P(1, 1), U32(1, 1, 1, alpha))
        return
    end
    local cx, cy, r = x + s / 2, y + s / 2, s * 0.42
    if kind == 'sharp' then
        dl:AddCircleFilled(P(cx, cy), r, U32(0.78, 0.32, 0.14, alpha), 32)
        dl:AddCircleFilled(P(cx, cy), r * 0.16, U32(0.1, 0.05, 0.04, alpha), 12)
    else
        dl:AddCircle(P(cx, cy), r, U32(0.62, 0.66, 0.72, alpha), 28, 3)
        IC.gem(dl, cx, cy + r * 0.2, r * 0.5, alpha)
    end
end

function D.section(dl, kind, x, y, text)
    IC[kind](dl, x + 10, y + 10, accU(1))
    D.txt(dl, fontLabel, x + 28, y + 2, accU(1), text)
end

 
local PW, PAD = 530, 16
local ROW_H, ROW_GAP = 46, 6


 
 
 
 
local FL = {scroll = 0}
local FLS = {down = false, y = 0, drag = 0, inside = false, speed = 0}
do
    local SP = 6
    local st = {left = 0, right = 0, cx = 0, cy = 0, maxY = 0, wrap = false, nextW = nil,
                prevTop = 0, prevRight = 0, col = 0, stack = {}, hov = false, slider = false,
                area = nil, base = 0}

    local function toU32(v)
        if type(v) == 'number' then return v end
        return imgui.GetColorU32Vec4(v)
    end
    local function lineH() return imgui.CalcTextSize('Ay').y / SC end
    local function advance(w, h)
        st.prevTop, st.prevRight = st.cy, st.cx + w
        st.cx = st.left
        st.cy = st.cy + h + SP
        if st.cy > st.maxY then st.maxY = st.cy end
    end

    function FL.begin(ax, ay, aw, ah, padX, padY)
        st.area = {ax, ay, aw, ah}
        st.left, st.right = ax + padX, ax + aw - padX
        st.base = ay + padY
        st.cx, st.cy = st.left, st.base - FL.scroll
        st.maxY = st.cy
        st.wrap, st.nextW, st.slider = false, nil, false
        st.stack, st.col = {}, U32(0.88, 0.91, 1, 1)
        FL.dl = winDL()
        FL.dl:PushClipRect(P(ax, ay), P(ax + aw, ay + ah), true)
        HITCLIP = {TX(ax), TY(ay), TX(ax + aw), TY(ay + ah)}
    end

    function FL.finish()
        FL.dl:PopClipRect()
        local ax, ay, aw, ah = st.area[1], st.area[2], st.area[3], st.area[4]
        local contentH = st.maxY - (st.base - FL.scroll) + 12
        local maxScroll = math.max(0, contentH - (ah - 8))
         
        local io = imgui.GetIO()
        local dt = math.min(0.05, math.max(0.001, io.DeltaTime))
        local mp = io.MousePos
        if imgui.IsMouseDown(0) then
            if not FLS.down then
                FLS.down, FLS.y, FLS.drag, FLS.speed = true, mp.y, 0, 0
                FLS.inside = inR(mp.x, mp.y, HITCLIP[1], HITCLIP[2], HITCLIP[3], HITCLIP[4])
            else
                local dy = mp.y - FLS.y
                FLS.y = mp.y
                FLS.drag = FLS.drag + math.abs(dy)
                if FLS.inside and not st.slider and FLS.drag > 10 * SC then
                    FL.scroll = FL.scroll - dy / SC
                    FLS.speed = FLS.speed * 0.6 + (-dy / SC / dt) * 0.4
                end
            end
        else
            FLS.down = false
            if math.abs(FLS.speed) > 30 then
                FL.scroll = FL.scroll + FLS.speed * dt
                FLS.speed = FLS.speed * math.max(0, 1 - dt * 4.5)
            else
                FLS.speed = 0
            end
        end
        local before = FL.scroll
        FL.scroll = clamp(FL.scroll, 0, maxScroll)
        if FL.scroll ~= before then FLS.speed = 0 end
        if maxScroll > 0 then
            local th = math.max(30, (ah - 16) * (ah - 8) / contentH)
            local ty = ay + 8 + (ah - 16 - th) * (FL.scroll / maxScroll)
            FL.dl:AddRectFilled(P(ax + aw - 7, ty), P(ax + aw - 3, ty + th), accU(0.7), 2)
        end
        HITCLIP = nil
    end

    function FL.GetWindowDrawList() return FL.dl end
    function FL.GetCursorScreenPos() return P(st.cx, st.cy) end
    function FL.GetContentRegionAvail() return P(st.right - st.cx, 0) end
    function FL.GetCursorPosX() return st.cx - st.left end
    function FL.SetCursorPosX(v) st.cx = st.left + v end
    function FL.Spacing() st.cy = st.cy + 8; if st.cy > st.maxY then st.maxY = st.cy end end
    function FL.Dummy(size) advance(size.x, size.y) end
    function FL.SameLine(_, spacing) st.cx = st.prevRight + (spacing or 8); st.cy = st.prevTop end
    function FL.SetNextItemWidth(w) st.nextW = w end
    function FL.PushTextWrapPos() st.wrap = true end
    function FL.PopTextWrapPos() st.wrap = false end
    function FL.PushStyleColor(_, v) st.stack[#st.stack + 1] = st.col; st.col = toU32(v) end
    function FL.PopStyleColor() st.col = table.remove(st.stack) or st.col end
    function FL.IsItemHovered() return st.hov end

    function FL.InvisibleButton(_, size)
        local clicked, hov = D.hit('fl', st.cx, st.cy, size.x, size.y)
        st.hov = hov
        advance(size.x, size.y)
        return clicked
    end

    local function wrapInto(lines, para, maxW)
        local cur = ''
        for word in para:gmatch('%S+') do
            local cand = (cur == '') and word or (cur .. ' ' .. word)
            if cur ~= '' and imgui.CalcTextSize(cand).x / SC > maxW then
                lines[#lines + 1] = cur
                cur = word
            else
                cur = cand
            end
        end
        lines[#lines + 1] = cur
    end

    local function text(s)
        s = tostring(s)
        local maxW = st.wrap and (st.right - st.cx) or nil
        local lh = lineH()
        local lines = {}
        for para in (s .. '\n'):gmatch('(.-)\n') do
            if maxW then wrapInto(lines, para, maxW) else lines[#lines + 1] = para end
        end
        local wmax = 0
        for i, ln in ipairs(lines) do
            FL.dl:AddText(P(st.cx, st.cy + (i - 1) * lh), st.col, ln)
            wmax = math.max(wmax, imgui.CalcTextSize(ln).x / SC)
        end
        advance(wmax, #lines * lh)
    end
    FL.TextUnformatted = text
    FL.Text = text

    function FL.SliderInt(_, var, lo, hi, fmt)
        local w = st.nextW or (st.right - st.cx)
        st.nextW = nil
        local x, y, h = st.cx, st.cy, 42
        local x1, y1, x2, y2 = TX(x), TY(y), TX(x + w), TY(y + h)
        local changed = false
        trackTouch()
        if touch.down and inR(touch.sx, touch.sy, x1, y1, x2, y2) and clipOK(touch.sx, touch.sy) then
            local t = clamp((touch.x - x1) / math.max(1, x2 - x1), 0, 1)
            local v = math.floor(lo + t * (hi - lo) + 0.5)
            if v ~= var[0] then var[0] = v; changed = true end
            st.slider = true
        end
        local t = (var[0] - lo) / math.max(1, hi - lo)
        local s = (fmt or '%d'):format(var[0])
        local dl = FL.dl
        dl:AddText(P(x + w - imgui.CalcTextSize(s).x / SC, y), U32(0.75, 0.82, 1, 1), s)
        dl:AddRectFilled(P(x, y + 24), P(x + w, y + 32), U32(0.12, 0.15, 0.28, 1), 4)
        dl:AddRectFilled(P(x, y + 24), P(x + w * t, y + 32), accU(1), 4)
        dl:AddCircleFilled(P(x + w * t, y + 28), 11, U32(1, 1, 1, 1), 20)
        advance(w, h)
        return changed
    end
end

local MW, MH = 560, 640

local function section(text)
    FL.Spacing()
    local dl = FL.GetWindowDrawList()
    local p = FL.GetCursorScreenPos()
    dl:AddRectFilled(P(p.x, p.y + 4), P(p.x + 4, p.y + 22), accU(1), 2)
    FL.SetCursorPosX(FL.GetCursorPosX() + 14)
    withFont(fontMed, function()
        FL.PushStyleColor(imgui.Col.Text, accent())
        FL.TextUnformatted(T(text))
        FL.PopStyleColor()
    end)
    FL.Spacing()
end

local function coloredText(color, text)
    FL.PushStyleColor(imgui.Col.Text, color)
    FL.TextUnformatted(text)
    FL.PopStyleColor()
end

local function pillButton(id, label, w, h, style)
    local dl = FL.GetWindowDrawList()
    local p = FL.GetCursorScreenPos()
    local clicked = FL.InvisibleButton('##pb_' .. id, P(w, h))
    local t = approach('pb_' .. id, FL.IsItemHovered() and 1 or 0)
    if style == 'neutral' then
        dl:AddRectFilled(p, P(p.x + w, p.y + h), U32(0.09, 0.11, 0.2 + 0.05 * t, 1), 8)
        dl:AddRect(p, P(p.x + w, p.y + h), U32(0.22, 0.27, 0.45, 1), 8)
    else
        D.pill(dl, p.x, p.y, w, h, mixU(0, 1, 0.85 + 0.15 * t), mixU(1, 1, 0.85 + 0.15 * t))
        D.gloss(dl, p.x, p.y, w, h, 8, 0.16)
    end
    D.ctxt(dl, fontMed, p.x, p.y, w, h, U32(1, 1, 1, 1), label)
    return clicked
end

local function slider(label, id, var, lo, hi, fmt, onChange)
    FL.Text(T(label))
    FL.SetNextItemWidth(FL.GetContentRegionAvail().x)
    if FL.SliderInt('##' .. id, var, lo, hi, fmt) then
        cfg.settings[id] = var[0]
        markDirty()
        if onChange then onChange() end
    end
end

local function card(dl, x, y, w, h, hot)
    D.box(dl, x, y, w, h, 14, hot)
end

local function parseHist(h)
    local list = {}
    for from, ok in tostring(h or ''):gmatch('(%d+):([01])') do
        list[#list + 1] = {from = tonumber(from), ok = ok == '1'}
    end
    return list
end

local function drawLogsPage()
    local w = FL.GetContentRegionAvail().x
    local dl = FL.GetWindowDrawList()

    local keys = {}
    for k in pairs(cfg.logs) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return (cfg.logs[a].u or 0) > (cfg.logs[b].u or 0) end)

    section('Логи заточки')
    if #keys == 0 then
        coloredText(V4(0.55, 0.60, 0.74), T('Логов пока нет: они появятся после первой заточки'))
        return
    end
    FL.PushTextWrapPos(0)
    coloredText(V4(0.55, 0.60, 0.74), T('Нажми на предмет, чтобы увидеть, с какой попытки была удача, а с какой неудача.'))
    FL.PopTextWrapPos()
    FL.Spacing()

    for _, k in ipairs(keys) do
        local l = cfg.logs[k]
        local list = parseHist(l.h)
        local okN = 0
        for _, a in ipairs(list) do if a.ok then okN = okN + 1 end end
        local failN = #list - okN
        local open = ui.logOpen[k]

        local p = FL.GetCursorScreenPos()
        local clicked = FL.InvisibleButton('##lg' .. k, P(w, 62))
        local hov = FL.IsItemHovered()
        if clicked then open = not open; ui.logOpen[k] = open end
        card(dl, p.x, p.y, w, 62, open or hov)

        local lname = enchantName(l.item)
        D.txt(dl, fontMed, p.x + 14, p.y + 8, U32(0.96, 0.97, 1, 1), lname)
        if #list > 0 then
            D.txt(dl, fontSmall, p.x + 24 + D.tw(fontMed, lname), p.y + 12, accU(1),
                ('+%d > +%d'):format(list[1].from, l.last or list[1].from))
        end
        D.txt(dl, fontSmall, p.x + 14, p.y + 34, U32(0.6, 0.66, 0.88, 1),
            (T('%s   |   попыток: %d')):format(os.date('%d.%m %H:%M', l.t or 0), #list))

        local c1 = (T('Удач %d')):format(okN)
        local c2 = (T('Неудач %d')):format(failN)
        local w2 = D.tw(fontLabel, c2) + 20
        local w1 = D.tw(fontLabel, c1) + 20
        local rx = p.x + w - 40 - w2
        dl:AddRectFilled(P(rx, p.y + 20), P(rx + w2, p.y + 42), U32(1, 0.35, 0.4, 0.14), 6)
        dl:AddRect(P(rx, p.y + 20), P(rx + w2, p.y + 42), U32(1, 0.35, 0.4, 0.5), 6, 15, 1)
        D.ctxt(dl, fontLabel, rx, p.y + 20, w2, 22, U32(1, 0.45, 0.5, 1), c2)
        local lx = rx - 8 - w1
        dl:AddRectFilled(P(lx, p.y + 20), P(lx + w1, p.y + 42), U32(0.3, 0.9, 0.5, 0.14), 6)
        dl:AddRect(P(lx, p.y + 20), P(lx + w1, p.y + 42), U32(0.3, 0.9, 0.5, 0.5), 6, 15, 1)
        D.ctxt(dl, fontLabel, lx, p.y + 20, w1, 22, U32(0.35, 0.95, 0.55, 1), c1)

        local ax, ay = p.x + w - 20, p.y + 31
        if open then
            dl:AddTriangleFilled(P(ax - 6, ay - 3), P(ax + 6, ay - 3), P(ax, ay + 4), accU(1))
        else
            dl:AddTriangleFilled(P(ax - 3, ay - 6), P(ax + 4, ay), P(ax - 3, ay + 6), U32(0.6, 0.66, 0.9, 1))
        end

        if open then
            local oks, fails = {}, {}
            for i, a in ipairs(list) do
                if a.ok then oks[#oks + 1] = tostring(i) else fails[#fails + 1] = tostring(i) end
            end
            FL.PushTextWrapPos(0)
            coloredText(V4(0.35, 0.95, 0.55), T('Удача на попытках: ') .. (#oks > 0 and table.concat(oks, ', ') or '-'))
            coloredText(V4(1, 0.45, 0.5), T('Неудача на попытках: ') .. (#fails > 0 and table.concat(fails, ', ') or '-'))
            FL.PopTextWrapPos()
            FL.Spacing()
            for i, a in ipairs(list) do
                local rp = FL.GetCursorScreenPos()
                FL.Dummy(P(w, 26))
                if i % 2 == 1 then dl:AddRectFilled(rp, P(rp.x + w, rp.y + 26), U32(1, 1, 1, 0.03), 8) end
                D.txt(dl, fontLabel, rp.x + 14, rp.y + 4, U32(0.6, 0.66, 0.9, 1), (T('Попытка %d')):format(i))
                local to = a.ok and (a.from + 1) or a.from
                D.txt(dl, fontMain, rp.x + 120, rp.y + 3, U32(0.9, 0.93, 1, 1), ('+%d > +%d'):format(a.from, to))
                if a.ok then
                    D.txt(dl, fontLabel, rp.x + 230, rp.y + 4, U32(0.35, 0.95, 0.55, 1), T('УДАЧА'))
                else
                    D.txt(dl, fontLabel, rp.x + 230, rp.y + 4, U32(1, 0.45, 0.5, 1), T('НЕУДАЧА'))
                end
            end
            FL.Spacing()
        end
    end

    FL.Spacing()
    if pillButton('clearlogs', T('Очистить логи'), 200, 38, 'neutral') then
        cfg.logs = {}
        ui.logOpen = {}
        markDirty()
    end
end

local function drawStatsPage()
    local w = FL.GetContentRegionAvail().x
    local dl = FL.GetWindowDrawList()

    section('Эта сессия')
    local p = FL.GetCursorScreenPos()
    local h = 100
    FL.Dummy(P(w, h))
    card(dl, p.x, p.y, w, h, false)

    local total = ench.ok + ench.fail
    local frac = total > 0 and ench.ok / total or 0
    local cx, cy = p.x + 56, p.y + h / 2
    D.ring(dl, cx, cy, 31, 1, U32(0.14, 0.17, 0.3, 1), U32(0.14, 0.17, 0.3, 1), 8)
    if total > 0 then D.ring(dl, cx, cy, 31, frac, U32(0.3, 0.9, 0.5, 1), U32(1, 0.35, 0.4, 0.75), 8) end
    D.ctxt(dl, fontMed, cx - 31, cy - 31, 62, 62, U32(1, 1, 1, 1), total > 0 and ('%.0f%%'):format(frac * 100) or '-')

    local tx = p.x + 112
    D.txt(dl, fontBig, tx, p.y + 8, U32(1, 1, 1, 1), tostring(total))
    D.txt(dl, fontMain, tx, p.y + 50, U32(0.6, 0.66, 0.88, 1), T('попыток за сессию'))
    D.txt(dl, fontMain, tx, p.y + 72, U32(0.3, 0.9, 0.5, 1), (T('Успешно: %d')):format(ench.ok))
    D.txt(dl, fontMain, tx + 130, p.y + 72, U32(1, 0.4, 0.45, 1), (T('Неудач: %d')):format(ench.fail))

    section('По предметам')
    local list = {}
    for key, s in pairs(cfg.stats) do list[#list + 1] = {key = key, s = s} end
    table.sort(list, function(a, b) return (a.s.ok + a.s.fail) > (b.s.ok + b.s.fail) end)

    if #list == 0 then
        coloredText(V4(0.55, 0.6, 0.74), T('Пока пусто, статистика появится после первой заточки'))
        return
    end

    for _, item in ipairs(list) do
        local s = item.s
        local all = s.ok + s.fail
        local f = all > 0 and s.ok / all or 0
        local rp = FL.GetCursorScreenPos()
        FL.Dummy(P(w, 70))
        card(dl, rp.x, rp.y, w, 70, false)

        local rx, ry = rp.x + 40, rp.y + 35
        D.ring(dl, rx, ry, 20, 1, U32(0.14, 0.17, 0.3, 1), U32(0.14, 0.17, 0.3, 1), 6)
        if all > 0 then D.ring(dl, rx, ry, 20, f, U32(0.3, 0.9, 0.5, 1), U32(1, 0.35, 0.4, 0.75), 6) end
        D.ctxt(dl, fontSmall, rx - 20, ry - 20, 40, 40, U32(1, 1, 1, 1), ('%.0f'):format(f * 100))

        D.txt(dl, fontMed, rp.x + 76, rp.y + 10, U32(0.96, 0.97, 1, 1), keyName(item.key))
        D.txt(dl, fontSmall, rp.x + 76, rp.y + 38, U32(0.6, 0.66, 0.88, 1),
            (T('Уровень +%d   |   удач %d   |   неудач %d')):format(s.level, s.ok, s.fail))
    end

    FL.Spacing()
    if pillButton('reset', T('Сбросить статистику'), 220, 38, 'neutral') then
        cfg.stats = {}
        ench.ok, ench.fail = 0, 0
        markDirty()
    end
end

local function drawSettingsPage()
    section('Оформление')
    FL.Text(T('Цвет интерфейса'))
    FL.Spacing()
    local dl = FL.GetWindowDrawList()
    local w = FL.GetContentRegionAvail().x
    local n, gap = #ACCENTS, 8
    local sw = (w - gap * (n - 1)) / n
    for i, a in ipairs(ACCENTS) do
        local p = FL.GetCursorScreenPos()
        if FL.InvisibleButton('##acc' .. i, P(sw, 62)) then
            cfg.settings.accent = i
            markDirty()
            applyTheme()
        end
        local sel = cfg.settings.accent == i
        local t = approach('acc' .. i, sel and 1 or (FL.IsItemHovered() and 0.5 or 0))
        D.pill(dl, p.x, p.y + 2, sw, 34, U32(a.c[1], a.c[2], a.c[3], 1), U32(a.c2[1], a.c2[2], a.c2[3], 1))
        dl:AddRectFilled(P(p.x + 8, p.y + 5), P(p.x + sw - 8, p.y + 16), U32(1, 1, 1, 0.14), 6)
        if sel then
            dl:AddRect(P(p.x - 3, p.y - 1), P(p.x + sw + 3, p.y + 39), U32(1, 1, 1, 0.95), 8, 15, 2)
        elseif t > 0.01 then
            dl:AddRect(P(p.x - 3, p.y - 1), P(p.x + sw + 3, p.y + 39), U32(1, 1, 1, 0.4 * t), 8, 15, 1.5)
        end
        D.ctxt(dl, fontSmall, p.x, p.y + 40, sw, 18, sel and U32(1, 1, 1, 1) or U32(0.62, 0.68, 0.88, 1), T(a.name))
        if i < n then FL.SameLine(0, gap) end
    end
    FL.Dummy(P(0, 8))
    slider('Прозрачность окна', 'alpha', inputs.alpha, 50, 100, '%d%%', applyTheme)
    slider('Яркость свечения', 'glow', inputs.glow, 0, 100, '%d%%')
    slider('Масштаб интерфейса (применяется, когда отпустишь палец)', 'scale', inputs.scale, 60, 250, '%d%%', function() scalePending = true end)

    section('Расходники')
    FL.PushTextWrapPos(0)
    coloredText(V4(0.6, 0.66, 0.88), T('Предметы, которые скрипт запомнил как «только амулет»: ') .. tostring((function()
        local c = 0
        for _ in pairs(cfg.amuletOnly) do c = c + 1 end
        return c
    end)()))
    FL.PopTextWrapPos()
    FL.Spacing()
    if pillButton('clearamu', T('Забыть «только амулет»'), 240, 38, 'neutral') then
        cfg.amuletOnly = {}
        markDirty()
    end
end

local function drawAboutPage()
    local dl = FL.GetWindowDrawList()
    local w = FL.GetContentRegionAvail().x
    local p = FL.GetCursorScreenPos()
    local h = 88
    FL.Dummy(P(w, h))
    card(dl, p.x, p.y, w, h, true)
    local cx, cy = p.x + 48, p.y + h / 2
    dl:AddCircleFilled(P(cx, cy), 28, U32(0.04, 0.07, 0.2, 1), 40)
    D.glowCircle(dl, cx, cy, 28, 0.3)
    dl:AddCircle(P(cx, cy), 28, accU(1), 40, 2)
    IC.star(dl, cx, cy, 16, U32(0.75, 0.92, 1, 1))
    D.txt(dl, fontTitle, p.x + 92, p.y + 14, U32(1, 1, 1, 1), 'ENCHANT MASTER')
    D.txt(dl, fontMain, p.x + 92, p.y + 50, U32(0.6, 0.66, 0.88, 1), (T('Версия %s')):format(thisScript().version))

    section('Как пользоваться')
    FL.PushTextWrapPos(0)
    FL.TextUnformatted(T('1. Выбери расходник: /em - Настройки - Расходник.'))
    FL.TextUnformatted(T('2. Введи в чате /em 13 (цель +13, можно от 1 до 13) - скрипт ответит, что команда принята.'))
    FL.TextUnformatted(T('3. Открой верстак и нажми на предмет - заточка пойдёт сама.'))
    FL.TextUnformatted(T('4. Ход и итог заточки выводятся в чат.'))
    FL.TextUnformatted(T('Если предмету нужен только амулет - скрипт определяет это сам.'))
    FL.TextUnformatted(T('/em stop - остановить заточку или отменить команду.'))
    FL.TextUnformatted(T('/em без цифры - это меню (логи, статистика, настройки).'))
    FL.PopTextWrapPos()
end

local function drawEnchantPage()
    section('Расходник для заточки')
    local w = FL.GetContentRegionAvail().x
    local gap = 8
    local bw = (w - gap * 2) / 3
    for i, m in ipairs(MODES) do
        if pillButton('mode' .. i, T(m.short), bw, 44, cfg.enchant.mode == i and 'accent' or 'neutral') then
            cfg.enchant.mode = i
            markDirty()
        end
        if i < #MODES then FL.SameLine(0, gap) end
    end
    FL.Dummy(P(0, 8))

    section('Как точить')
    FL.PushTextWrapPos(0)
    FL.TextUnformatted(T('1. Введи в чате /em 13 (цель +13, можно от 1 до 13).'))
    FL.TextUnformatted(T('2. Открой верстак и нажми на предмет - заточка пойдёт сама.'))
    FL.TextUnformatted(T('3. Остановить: /em stop.'))
    FL.TextUnformatted(T('Если предмету нужен только амулет - скрипт определяет это сам.'))
    FL.PopTextWrapPos()
end

local PAGES = {
    {id = 'enchant',  title = 'Заточка',    draw = drawEnchantPage},
    {id = 'logs',     title = 'Логи',       draw = drawLogsPage},
    {id = 'stats',    title = 'Статистика', draw = drawStatsPage},
    {id = 'settings', title = 'Настройки',  draw = drawSettingsPage},
}

local function findPage(id)
    for _, page in ipairs(PAGES) do
        if page.id == id then return page end
    end
    return PAGES[1]
end

local pageState = {id = nil, t = 1}

local function drawMenu()
    if scalePending and not imgui.IsMouseDown(0) then
        scalePending = false
        computeScale(cfg.settings.scale)
        pcall(function() imgui.GetIO().FontGlobalScale = SC / SCB end)
    end
    local step = imgui.GetIO().DeltaTime / menu.duration
    menu.alpha = clamp(menu.alpha + (menu.open and step or -step), 0, 1)
    menu.eased = menu.alpha * menu.alpha * (3 - 2 * menu.alpha)
    FA = math.max(0.001, menu.eased)

    local io = imgui.GetIO()
    local mx = math.max(0, (io.DisplaySize.x - MW * SC) / 2)
    local my = math.max(0, (io.DisplaySize.y - MH * SC) / 2)
    imgui.SetNextWindowPos(P(mx, my), imgui.Cond.Always)
    imgui.SetNextWindowSize(P(MW * SC, MH * SC), imgui.Cond.Always)
    local WF = imgui.WindowFlags
    local flags = WF.NoTitleBar + WF.NoResize + WF.NoScrollbar + WF.NoCollapse
                + WF.NoScrollWithMouse + WF.NoBackground + WF.NoSavedSettings + WF.NoMove
    imgui.Begin('##enchant_menu', nil, flags)
    if fontMain then imgui.PushFont(fontMain) end

    local wp = imgui.GetWindowPos()
    setOrigin(wp.x, wp.y)
    local dl, bg = winDL(), bgDL()
    local x0, y0 = wp.x, wp.y
    local x1, y1 = x0 + MW, y0 + MH
    local inner = MW - PAD * 2
    D.neon(dl, bg, x0, y0, x1, y1, 18)

     
    local lcx, lcy = x0 + 48, y0 + 42
    dl:AddCircleFilled(P(lcx, lcy), 27, U32(0.04, 0.07, 0.2, 1), 40)
    D.glowCircle(dl, lcx, lcy, 27, 0.3)
    dl:AddCircle(P(lcx, lcy), 27, accU(0.95), 40, 2)
    IC.star(dl, lcx, lcy, 15, U32(0.75, 0.92, 1, 1))
    local title = 'ENCHANT MASTER'
    D.txt(dl, fontTitle, x0 + 92, y0 + 24, U32(1, 1, 1, 1), title)
    local sx = x0 + 92 + D.tw(fontTitle, title) + 18
    local on = cfg.settings.enabled
    local pc = on and {0.30, 0.92, 0.50} or {1, 0.4, 0.42}
    local pulse = on and (0.5 + 0.5 * math.sin(os.clock() * 3)) or 0
    dl:AddCircleFilled(P(sx + 5, y0 + 42), 5 + 2 * pulse, U32(pc[1], pc[2], pc[3], 0.25), 14)
    dl:AddCircleFilled(P(sx + 5, y0 + 42), 4.5, U32(pc[1], pc[2], pc[3], 1), 14)
    D.txt(dl, fontLabel, sx + 18, y0 + 33, U32(pc[1], pc[2], pc[3], 1), on and T('ВКЛЮЧЁН') or T('ВЫКЛЮЧЕН'))

    dl:AddLine(P(x1 - 70, y0 + 24), P(x1 - 70, y0 + 60), U32(0.2, 0.25, 0.42, 1), 1)
    local cl, chov = D.hit('mclose', x1 - 56, y0 + 25, 34, 34)
    local ct = approach('m_close', chov and 1 or 0)
    dl:AddCircleFilled(P(x1 - 39, y0 + 42), 16, U32(1, 1, 1, 0.04 + 0.1 * ct), 24)
    IC.cross(dl, x1 - 39, y0 + 42, U32(0.85 + 0.15 * ct, 0.9, 1, 1), 7)
    if cl then menu.open = false end
    dl:AddRectFilledMultiColor(P(x0 + 22, y0 + 72), P(x1 - 22, y0 + 73), mixU(0, 0.6, 1), mixU(1, 0.6, 1), mixU(1, 0.6, 1), mixU(0, 0.6, 1))

     
    local tx0, ty0, th = x0 + PAD, y0 + 86, 44
    local n = #PAGES
    local bw = (inner - 8) / n
    dl:AddRectFilled(P(tx0, ty0), P(tx0 + inner, ty0 + th), U32(0.05, 0.06, 0.12, 1), 8)
    dl:AddRect(P(tx0, ty0), P(tx0 + inner, ty0 + th), U32(0.16, 0.20, 0.34, 1), 8, 15, 1)
    local curIdx = 1
    for i, pg in ipairs(PAGES) do if pg.id == cfg.page then curIdx = i end end
    local ix = approach('m_tab_ix', curIdx - 1, 12)
    local hx = tx0 + 4 + ix * bw
    D.pill(dl, hx, ty0 + 4, bw, th - 8, mixU(0, 1, 0.9), mixU(1, 1, 0.9))
    D.gloss(dl, hx, ty0 + 4, bw, th - 8, 8, 0.16)
    for i, pg in ipairs(PAGES) do
        local bx2 = tx0 + 4 + (i - 1) * bw
        local clicked, hov = D.hit('tab' .. pg.id, bx2, ty0 + 4, bw, th - 8)
        if clicked then cfg.page = pg.id; markDirty() end
        local sel = cfg.page == pg.id
        D.ctxt(dl, fontMain, bx2, ty0 + 4, bw, th - 8,
            sel and U32(1, 1, 1, 1) or (hov and U32(0.9, 0.93, 1, 1) or U32(0.62, 0.68, 0.88, 1)), T(pg.title))
    end

     
    local cx0, cy0 = x0 + PAD, y0 + 146
    local ch = MH - 146 - 86
    D.box(dl, cx0, cy0, inner, ch, 14, false)
    if pageState.id ~= cfg.page then
        pageState.id = cfg.page
        pageState.t = 0
        FL.scroll = 0
    end
    pageState.t = clamp(pageState.t + imgui.GetIO().DeltaTime / 0.28, 0, 1)
    local pe = pageState.t * pageState.t * (3 - 2 * pageState.t)
    local faSaved = FA
    FA = FA * math.max(0.001, pe)
    FL.begin(cx0 + 4, cy0 + 4, inner - 8, ch - 8, 10, 4 + (1 - pe) * 14)
    findPage(cfg.page).draw()
    FL.finish()
    FA = faSaved

     
    do
        local bx, by, bw2 = x0 + PAD, y1 - 18 - 52, inner
        local clicked, hov = D.hit('power', bx, by, bw2, 52)
        if clicked then setEnabled(not on) end
        local t = approach('power_hot', hov and 1 or 0)
        dl:AddRectFilled(P(bx, by), P(bx + bw2, by + 52), U32(pc[1], pc[2], pc[3], 0.12 + 0.1 * t), 8)
        dl:AddRect(P(bx, by), P(bx + bw2, by + 52), U32(pc[1], pc[2], pc[3], 0.6), 8, 15, 1.5)
        dl:AddCircleFilled(P(bx + 28, by + 26), 6 + 5 * pulse, U32(pc[1], pc[2], pc[3], on and 0.18 or 0), 20)
        dl:AddCircleFilled(P(bx + 28, by + 26), 6, U32(pc[1], pc[2], pc[3], 1), 14)
        D.txt(dl, fontMed, bx + 48, by + 14, U32(pc[1], pc[2], pc[3], 1), on and T('Скрипт включён') or T('Скрипт выключен'))
        local hintT = on and T('нажми, чтобы выключить') or T('нажми, чтобы включить')
        D.txt(dl, fontSmall, bx + bw2 - D.tw(fontSmall, hintT) - 20, by + 17, U32(0.6, 0.68, 0.9, 1), hintT)
    end

    if fontMain then imgui.PopFont() end
    imgui.End()
    FA = 1
end

imgui.OnFrame(function() return menu.open or menu.alpha > 0 end, function(self)
    self.HideCursor = not menu.open
    drawMenu()
end)

loadConfig()
cfg.page = 'enchant'
syncUI()

local function registerCmd(name, fn)
    for _ = 1, 40 do
        if pcall(sampRegisterChatCommand, name, fn) then return true end
        wait(250)
    end
    return false
end

function main()
    if type(isSampAvailable) == 'function' then
        while not isSampAvailable() do wait(100) end
    else
        wait(3000)
    end

    registerCmd('em', cmdEm)
    registerCmd('mstop', cmdStop)
    registerCmd('emlog', function()
        dbgOn = not dbgOn
        if dbgOn then
            dbgT0 = os.clock()
            pcall(function()
                if not doesDirectoryExist(cfgDir) then createDirectory(cfgDir) end
                local f = io.open(cfgDir .. '/enchant_master_log.txt', 'w')
                if f then f:close() end
            end)
        end
        chat(T('{FFD700}[Enchant Master]{FFFFFF} лог пакетов: ') .. (dbgOn and 'ON' or 'OFF')
             .. ' (moonloader/config/enchant_master_log.txt)')
    end)

    chat(T('{FF3030}[Enchant Master]{FFFFFF} By {FF3030}Stalin{FFFFFF} mobile v4.0 загружен. Заточка до +13: {FFD700}/em 13{FFFFFF}, стоп: {FFD700}/em stop{FFFFFF}, меню: {FFD700}/em'))

    while true do
        wait(50)
        if runReq then
            runReq = false
            lua_thread.create(runJob)
        end
        if armed and not armed.starting and os.clock() - armed.t > ARM_TTL then
            armed = nil
            chat(T('{FFD700}[Enchant Master]{FFFFFF} Команда заточки истекла, введи её заново'))
        end
        if dirty and os.clock() - dirtyAt > 1 then
            pcall(saveConfig)
        end
    end
end

function onScriptTerminate(scr, quit)
    if scr == thisScript() then pcall(saveConfig) end
end
