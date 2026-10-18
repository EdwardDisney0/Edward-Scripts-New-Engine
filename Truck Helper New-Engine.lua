script_name('Truck Helper')
script_author('By Stalin')
script_version('1.1-neom')

pcall(require, 'moonloader')
pcall(require, 'sampfuncs')
local sampev = require 'samp.events'
-- NeoMLoader: RakNet-хуки (пакеты CEF) идут через RakLua; на MonetLoader его нет
local NEOM = pcall(require, 'RakLua') and type(addEventHandler) == 'function'
-- ==================================================================== 
-- MonetLoader / mimgui: слой совместимости со старым ПК-API imgui.
-- Скрипт работает в "виртуальных" координатах (как на ПК), а на границе
-- с mimgui всё умножается на K (масштаб под экран телефона).
-- ====================================================================
local imgui = (function()
    local m = require 'mimgui'
    local sh = setmetatable({}, {__index = m})
    local gsr = getScreenResolution
    local FORCE_SCALE = nil -- можно вручную задать, например 1.5 (если интерфейс слишком мелкий/крупный)

    local K = 1
    do
        local ok, w, h = pcall(gsr)
        if ok and w and h and w > 0 and h > 0 then K = math.min(w, h) / 700 end
        K = FORCE_SCALE or math.max(1, math.min(2.6, K))
    end

    local RV2 = m.ImVec2
    local MB = {K = K, RV2 = RV2, theme = true}
    sh.MB = MB

    function MB.res() local w, h = gsr() return w / K, h / K end
    function MB.touchScroll()
        pcall(function()
            if m.IsWindowHovered(32) and m.IsMouseDown(0) then
                local d = m.GetIO().MouseDelta
                if d.y ~= 0 and math.abs(d.y) >= math.abs(d.x) then
                    m.SetScrollY(m.GetScrollY() - d.y)
                end
            end
        end)
    end
    function MB.key(vk)
        local f = rawget(_G, 'isKeyJustPressed')
        if not f then return false end
        local ok, r = pcall(f, vk)
        return ok and r == true
    end

    local function V(x, y) return {x = x or 0, y = y or 0} end
    local function toR(v) return RV2((v and v.x or 0) * K, (v and v.y or 0) * K) end
    local function fromR(v) return {x = v.x / K, y = v.y / K} end
    sh.ImVec2 = V

    -- ---- позиции / размеры (виртуальные <-> реальные) ----
    function sh.GetCursorScreenPos() return fromR(m.GetCursorScreenPos()) end
    function sh.SetCursorScreenPos(v) m.SetCursorScreenPos(toR(v)) end
    function sh.GetCursorPosX() return m.GetCursorPosX() / K end
    function sh.GetCursorPosY() return m.GetCursorPosY() / K end
    function sh.SetCursorPosY(y) m.SetCursorPosY(y * K) end
    function sh.GetWindowPos() return fromR(m.GetWindowPos()) end
    function sh.GetWindowSize() return fromR(m.GetWindowSize()) end
    function sh.GetWindowWidth() return m.GetWindowWidth() / K end
    function sh.GetWindowHeight() return m.GetWindowHeight() / K end
    function sh.GetMousePos() return fromR(m.GetMousePos()) end
    function sh.GetItemRectSize() return fromR(m.GetItemRectSize()) end
    function sh.GetContentRegionAvailWidth() return m.GetContentRegionAvail().x / K end
    function sh.GetScrollY() return m.GetScrollY() / K end
    function sh.GetScrollMaxY() return m.GetScrollMaxY() / K end
    function sh.SetScrollY(y) m.SetScrollY(y * K) end
    function sh.CalcTextSize(t) return fromR(m.CalcTextSize(tostring(t))) end

    function sh.SetNextWindowPos(p, cond) m.SetNextWindowPos(toR(p), cond or 0, RV2(0, 0)) end
    function sh.SetNextWindowSize(s, cond) m.SetNextWindowSize(toR(s), cond or 0) end
    function sh.PushItemWidth(w) m.PushItemWidth(w * K) end
    function sh.PushTextWrapPos(x) m.PushTextWrapPos((x or 0) * K) end
    function sh.SameLine(o, s) m.SameLine((o or 0) * K, s and s * K or -1) end
    function sh.IsMouseHoveringRect(a, b) return m.IsMouseHoveringRect(toR(a), toR(b), true) end

    local variant = {}
    local function flex(key, f, short, long)
        if variant[key] ~= 'long' then
            local ok, r = pcall(f, short())
            if ok then variant[key] = 'short' return r end
            variant[key] = 'long'
        end
        return f(long())
    end

    function sh.Button(l, s) return m.Button(l, s and toR(s) or RV2(0, 0)) end
    function sh.InvisibleButton(l, s)
        local sz = toR(s)
        return flex('ib', m.InvisibleButton, function() return l, sz end, function() return l, sz, 0 end)
    end
    function sh.Dummy(s) m.Dummy(toR(s)) end
    function sh.BeginChild(id, s, border, flags) return m.BeginChild(id, toR(s), border and true or false, flags or 0) end
    function sh.Begin(name, open, flags) return m.Begin(name, open and open._c or nil, flags or 0) end

    function sh.PushStyleVar(idx, v)
        if type(v) == 'table' then
            local f = m.PushStyleVarVec2 or m.PushStyleVar
            return f(idx, RV2(v.x * K, v.y * K))
        end
        if idx ~= m.StyleVar.Alpha then v = v * K end
        local f = m.PushStyleVarFloat or m.PushStyleVar
        return f(idx, v)
    end

    function sh.IsItemHovered(f) return m.IsItemHovered(f or 0) end
    function sh.IsWindowHovered(f) return m.IsWindowHovered(f or 0) end
    function sh.IsMouseClicked(b, r) return m.IsMouseClicked(b or 0, r or false) end
    function sh.IsKeyPressed() return false end -- на телефоне нет клавиатуры
    function sh.SwitchContext() end

    -- ---- текст без printf-форматирования ----
    local TU = m.TextUnformatted or function(t) m.Text((tostring(t):gsub('%%', '%%%%'))) end
    function sh.Text(t) TU(tostring(t)) end
    function sh.TextColored(c, t)
        m.PushStyleColor(m.Col.Text, c) TU(tostring(t)) m.PopStyleColor(1)
    end
    function sh.TextDisabled(t)
        m.PushStyleColor(m.Col.Text, m.GetStyle().Colors[m.Col.TextDisabled]) TU(tostring(t)) m.PopStyleColor(1)
    end
    function sh.SetTooltip(t) m.BeginTooltip() TU(tostring(t)) m.EndTooltip() end

    -- ---- старые ImBool / ImInt / ImFloat с полем .v ----
    local function boxed(ctor, init)
        local c = ctor(init)
        return setmetatable({}, {
            __index = function(_, k) if k == 'v' then return c[0] elseif k == '_c' then return c end end,
            __newindex = function(_, k, val) if k == 'v' then c[0] = val end end,
        })
    end
    function sh.ImBool(v) return boxed(m.new.bool, v and true or false) end
    function sh.ImInt(v) return boxed(m.new.int, math.floor(v or 0)) end
    function sh.ImFloat(v) return boxed(m.new.float, v or 0) end
    function sh.Checkbox(l, b) return m.Checkbox(l, b._c) end
    function sh.SliderFloat(l, f, mn, mx, fmt)
        fmt = fmt or '%.3f'
        return flex('sl', m.SliderFloat, function() return l, f._c, mn, mx, fmt end, function() return l, f._c, mn, mx, fmt, 0 end)
    end
    function sh.InputInt(l, i, step, fast)
        step, fast = step or 1, fast or 100
        return flex('ii', m.InputInt, function() return l, i._c, step, fast end, function() return l, i._c, step, fast, 0 end)
    end

    -- ---- draw list (координаты в виртуальном пространстве) ----
    local DL = {}
    DL.__index = DL
    local dl = setmetatable({}, DL)
    function DL:AddRectFilled(a, b, col, r) self.r:AddRectFilled(toR(a), toR(b), col, (r or 0) * K, 0) end
    function DL:AddRect(a, b, col, r, _, th) self.r:AddRect(toR(a), toR(b), col, (r or 0) * K, 0, (th or 1) * K) end
    function DL:AddCircleFilled(c, rad, col, seg) self.r:AddCircleFilled(toR(c), rad * K, col, seg or 0) end
    function DL:AddCircle(c, rad, col, seg, th) self.r:AddCircle(toR(c), rad * K, col, seg or 0, (th or 1) * K) end
    function DL:AddLine(a, b, col, th) self.r:AddLine(toR(a), toR(b), col, (th or 1) * K) end
    function DL:AddText(p, col, t)
        local rp, rt = toR(p), tostring(t)
        local r = self.r
        if variant.at ~= 'long' then
            local ok = pcall(r.AddText, r, rp, col, rt)
            if ok then variant.at = 'short' return end
            variant.at = 'long'
        end
        r:AddText(rp, col, rt, nil)
    end
    function sh.GetWindowDrawList() dl.r = m.GetWindowDrawList() return dl end

    return sh
end)()


local SCRIPT_VERSION = '1.0'
local TELEGRAM_URL = 'https://t.me/edward_scripts'
local BOT_URL = 'https://t.me/Edward_Scripts_Bot'
local ROOT = getWorkingDirectory() .. '/config/TruckHelper'
local FILES = {
    settings = ROOT .. '/settings.json',
    stats    = ROOT .. '/stats.json',
    history  = ROOT .. '/history.json',
    vehicles = ROOT .. '/vehicles.json',
    items    = ROOT .. '/items.json',
}
for _, name in ipairs({'unparsed.json', 'report.txt', 'menu_guard.txt', 'menu_trace.txt'}) do
    pcall(os.remove, ROOT .. '/' .. name)
end
local OLD_LUA_FILE = getWorkingDirectory() .. '/config/TruckHelper2.lua'
local FA_PATH = getWorkingDirectory() .. '/resource/fonts/fa-solid-900.ttf'

local ICON_CP = {
    truck = 0xF0D1, home = 0xF015, chart = 0xF201, cog = 0xF013, coins = 0xF51E,
    car = 0xF1B9, gift = 0xF06B, wallet = 0xF555, clock = 0xF017, trophy = 0xF091,
    target = 0xF140, trash = 0xF1F8, move = 0xF0B2, eye = 0xF06E, palette = 0xF53F,
    close = 0xF00D, check = 0xF00C, cash = 0xF53A, history = 0xF1DA, bars = 0xF080,
    sync = 0xF021, save = 0xF0C7, info = 0xF05A, fire = 0xF06D, stopwatch = 0xF2F2,
    bolt = 0xF0E7, star = 0xF005, calendar = 0xF073, sliders = 0xF1DE, bell = 0xF0F3,
    folder = 0xF07B, warn = 0xF071, list = 0xF03A, keyboard = 0xF11C, power = 0xF011,
    wrench = 0xF0AD, percent = 0xF295, tag = 0xF02B, gas = 0xF52F, shield = 0xF3ED, bullhorn = 0xF0A1,
    hourglass = 0xF252, level = 0xF3BF, box = 0xF466, gauge = 0xF3FD, users = 0xF0C0, question = 0xF059,
}

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local ENC_OK = #'\208\145\208\190\208\189\209\131\209\129' == 10

local Charset = {}
do
    local CP1251_EXTRA = {
        [0x80]=0x0402, [0x81]=0x0403, [0x82]=0x201A, [0x83]=0x0453, [0x84]=0x201E, [0x85]=0x2026,
        [0x86]=0x2020, [0x87]=0x2021, [0x88]=0x20AC, [0x89]=0x2030, [0x8A]=0x0409, [0x8B]=0x2039,
        [0x8C]=0x040A, [0x8D]=0x040C, [0x8E]=0x040B, [0x8F]=0x040F, [0x90]=0x0452, [0x91]=0x2018,
        [0x92]=0x2019, [0x93]=0x201C, [0x94]=0x201D, [0x95]=0x2022, [0x96]=0x2013, [0x97]=0x2014,
        [0x98]=0x003F, [0x99]=0x2122, [0x9A]=0x0459, [0x9B]=0x203A, [0x9C]=0x045A, [0x9D]=0x045C,
        [0x9E]=0x045B, [0x9F]=0x045F, [0xA0]=0x00A0, [0xA1]=0x040E, [0xA2]=0x045E, [0xA3]=0x0408,
        [0xA4]=0x00A4, [0xA5]=0x0490, [0xA6]=0x00A6, [0xA7]=0x00A7, [0xA8]=0x0401, [0xA9]=0x00A9,
        [0xAA]=0x0404, [0xAB]=0x00AB, [0xAC]=0x00AC, [0xAD]=0x00AD, [0xAE]=0x00AE, [0xAF]=0x0407,
        [0xB0]=0x00B0, [0xB1]=0x00B1, [0xB2]=0x0406, [0xB3]=0x0456, [0xB4]=0x0491, [0xB5]=0x00B5,
        [0xB6]=0x00B6, [0xB7]=0x00B7, [0xB8]=0x0451, [0xB9]=0x2116, [0xBA]=0x0454, [0xBB]=0x00BB,
        [0xBC]=0x0458, [0xBD]=0x0405, [0xBE]=0x0455, [0xBF]=0x0457,
    }
    local C2U = {}
    for b = 0xC0, 0xFF do C2U[b] = 0x410 + (b - 0xC0) end
    for b, cp in pairs(CP1251_EXTRA) do C2U[b] = cp end
    local U2C = {}
    for b, cp in pairs(C2U) do U2C[cp] = b end

    local function hasHigh(s) return s:find('[\128-\255]') ~= nil end

    local function isValidUtf8(s)
        local i, n = 1, #s
        while i <= n do
            local c = s:byte(i)
            if c < 0x80 then
                i = i + 1
            elseif c >= 0xC2 and c <= 0xDF then
                local c2 = s:byte(i + 1)
                if not c2 or c2 < 0x80 or c2 > 0xBF then return false end
                i = i + 2
            elseif c >= 0xE0 and c <= 0xEF then
                local c2, c3 = s:byte(i + 1, i + 2)
                if not (c2 and c3 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF) then return false end
                i = i + 3
            elseif c >= 0xF0 and c <= 0xF4 then
                local c2, c3, c4 = s:byte(i + 1, i + 3)
                if not (c2 and c3 and c4 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF and c4 >= 0x80 and c4 <= 0xBF) then return false end
                i = i + 4
            else
                return false
            end
        end
        return true
    end

    local function cp1251ToUtf8(s)
        return (s:gsub('[\128-\255]', function(ch)
            local cp = C2U[ch:byte()]
            return cp and utf8char(cp) or '?'
        end))
    end

    local function utf8ToCp1251(s)
        return (s:gsub('[\194-\244][\128-\191]*', function(seq)
            local n, c1, cp = #seq, seq:byte(1), 63
            if n == 2 then cp = (c1 - 0xC0) * 64 + (seq:byte(2) - 0x80)
            elseif n == 3 then cp = (c1 - 0xE0) * 4096 + (seq:byte(2) - 0x80) * 64 + (seq:byte(3) - 0x80) end
            local b = U2C[cp]
            return b and string.char(b) or '?'
        end))
    end

    local function toUtf8(s)
        if not hasHigh(s) or isValidUtf8(s) then return s end
        return cp1251ToUtf8(s)
    end

    Charset.hasHigh = hasHigh
    Charset.isValidUtf8 = isValidUtf8
    Charset.toUtf8 = toUtf8
    Charset.utf8ToCp1251 = utf8ToCp1251
end
local icons = setmetatable({}, {__index = function() return '' end})

local fonts = {}
local font_keep = {}
local fa_ok = false
local fonts_ready = false
local fa_warned = false

font_keep.fa_b64 = [[
AAEAAAAMAIAAAwBAR0RFRgASADAAACKsAAAAFk9TLzJDh1K2AAAfFAAAAGBjbWFwy4/D0gAAH3QAAAGMZ2FzcP//AAMAACKkAAAA
CGdseWaO0v0HAAAAzAAAHKhoZWFkHUvCqwAAHfgAAAA2aGhlYQRDAnAAAB7wAAAAJGhtdHhc1gBQAAAeMAAAAL5sb2NhrLmkzgAA
HZQAAABibWF4cABRAVsAAB10AAAAIG5hbWUcDzYNAAAhAAAAAYJwb3N0/94AGQAAIoQAAAAgAAEAD/+6AjEBwQAYAAABNjIfAh4B
DwEXFgYvAQcGJj8BJyY2PwEBAwkoCUGSFAwOahkDIBGDgxEgAxlqDgwUkgGuEhKEFgImDmeSExcJREQKGBOSZw4mAhYAAAEAAAAB
AgABfwAUAAA3JyY0PwE2Mh8BNzYyHwEWFAcBBiKupwcHJQcVCHDwCBUHJQcH/tkHFgmmBxYHJAgIcPAICCQHFgf+2ggAAf//AA8B
YQFxACMAADcXFhQPAQYiLwEHBiIvASY0PwEnJjQ/ATYyHwE3NjIfARYUB/NkCQkWChoJZGQJGgoWCQlkZAkJFgoaCWRkCRoKFgkJ
wGQJGgoWCQlkZAkJFgoaCWRkCRoKFgkJZGQJCRYKGgkAAgAH/8cB+AHAACQANAAAAR4BFRQGIiY1NDY3NhYfARYGBw4BFRQWMzI2
NTQmJy4BPwE+AQcUBisBIiY9ATQ2OwEyFhUBkDA4kc2SODAJFQUQBAQHICRiRkVjJCAHBAQQBRVfDgogCg4OCiAKDgGKIms9Z5GR
Zz1qIwYFCRwIEgUYRilFY2JHJ0cYBRIIHAkF2AoODgrwCg4OCgAAAgAQ/8EB8AG/ADwARAAAJRYHBgcGLwEGBxUUBwYnJj0BJicH
BicmJyY/ASY0NycmNzY3Nh8BNjc1NDc2FxYdARYXNzYXFhcWDwEWBwYyNjQmIgYUAecJAxEmBggrGyIJNzYKIhsqCQYmEQMJKgMD
KgkDESYGCSobIgk3NwkiGyoJBiYRAwkqBgbeQi8vQi+EBAo1KQcEGRcMMQoCDAwCCjEMFxkEByk1CQUZESQRGQQKNSkHBRgXDDEK
AgwMAgoxDBcZBAcpNQoEGSMjLS9CLy9CAAAC////4AJBAaAAHQBDAAABNjIfARUUBisBIiY9ATQmKwEiBh0BFAYrASImPQElFhUU
DwEGIyIvASYiDwEGIyIvASY1ND8BNjIfATU0NjsBMhYdAQEYBAgEuAkHcAcJCQdABwkJB3AHCQHcBAMZBAUFA+sECATrAwQGBBkD
BP0OIg1aBwU4BQcBLAICmKQHCQoGYAcJCQdgBgoJB6QxBAYEAx8FA8ICAsIDBR8DBAYE0AsLSkkFBwcFiwACAAj/yAH4AbgABwAd
AAASMhYUBiImNAU2NTQvATU0JisBIgYdARQfARYzMjeZzpGRzpEBVAQGOgkHIAcJD0MEBggEAbiRzpGRzqgEBggFKpAHCQkHnBMM
MQQGAAIAAP/AAgABwAApAFMAAAE0MTQ2OwEyHQEUBisBIiY9ATQ2MxcuASMiBgcGKwEiJjU0NT4BMzIWFwMyNjc2OwEyFhUUBw4B
IyImJxcUMRQGKwEiPQE0NjsBMhYdARQGIyceAQG5BwUvDAcFyAUHBwVmGE0tPl8OAgoxBQcRiVo4YiO9PWAOAgoxBQcBEIlaOGIj
BAcFLwwHBcgFBwcFZhhNAbMBBQcMyAUHBwUvBQcFJCpMOwkHBQEBV3MuKf6vTDsJBwUBAVdzLilSAQUHDMgFBwcFLwUHBSQqAAAC
AAD/wAIAAcAAEQAZAAA9ATQ2OwEyHwEWFA8BBiIvASY2IgYUFjI2NBwUzBQO1A4OzA4oDtQOhCgcHCgcxMwUHA7UDigOzA4O1A7Q
HCgcHCgABgAA//ACAAGQAA8AHwAvAD8ATwBfAAA3MhYdARQGKwEiJj0BNDYzEzIWHQEUBisBIiY9ATQ2MxcyFh0BFAYrASImPQE0
NjMFMhYdARQGIyEiJj0BNDYzATIWHQEUBiMhIiY9ATQ2MwUyFh0BFAYjISImPQE0NjNQBwkJB0AHCQkHQAcJCQdABwkJB0AHCQkH
QAcJCQcB4AcJCQf+wAcJCQcBQAcJCQf+wAcJCQcBQAcJCQf+wAcJCQdQCQdABwkJB0AHCQFACQdABwkJB0AHCaAJB0AHCQkHQAcJ
sAkHIAcJCQcgBwkBQAkHIAcJCQcgBwmgCQcgBwkJByAHCQADAAj/yAH4AbgABwAqADIAAAAUBiImNDYyByIHBh8BFjc+ATMyFhUU
BgcOAh0BFDsBMj0BND4CNTQmBiIGFBYyNjQB+JHOkZHOYEorBgkjCQcQFxIRHQ8REhEUDDgMGh8aSCAmGxsmGwEnzpGRzpFSQAkH
GgcJExETDgsNCgoMHhMEDAwBCRIQJhoqPPgbJhsbJgAAAwAI/8gB+AG4AAcADwAnAAASMhYUBiImNCQiBhQWMjY0FzU0KwE1NCsB
Ih0BFDsBFSMiHQEUOwEymc6Rkc6RAQkiGRkiGQ4MDAxADAwMDAwMWAwBuJHOkZHOIxkiGRki5RgMZAwMGAxADBgMAAAFAAD/4AIA
AaAABgANAC4ANwBBAAAzNTMVIyImBTUzFRQGIxMyFh0BFAYjISImPQE0NjsBJjU0NjMyFhc+ATMyFhUUByEzLgEjIgYUFjMyNjQm
IyIOAQcgwKANEwEAwBMNIA0TCQf+IAcJEw0sCjQkHi4bGy4eJDQK/uRWIyESERcX3xEXFxEMESAZgKATE6CADRMBQBMNUAcJCQdQ
DRMTFSQ0ICQkIDQkFBQ1GxciFxciFwckJQAAAQAA/8ABgAHEACEAABMUHgMVFAYiJjU0NzYWHQEUFjMyNjU0LgQ2NzYW2CMxMSNx
nnE3Cx4lGhsmExodEwYVGgoiAagcMiwyTS9PcXFPTjkMDBFVGyYlGxEgGhwiKj0lDwoAAAMAAAAAAkABgAAPABkAKwAAJRYUBw4B
IiYnJjQ3PgEyFgcyNjU0JiIGFBY3MhYUBiImNTQ3FjMyNjU0JzYCPQMDKpi2mCoDAyqYtpjzPFRUeFRUPCg4OE85BAwQFBwJDM8H
EAdQYWFQBxAHUGFh71Q8PFRUeFTwOE85OScNDAkcFBAMBAAAA//4/8ACSAHBAAsAEwAhAAAlFgYjISImNxM2MhcCIgYUFjI2NCcX
FDsBMjU3NCYrASIGAjoNGxz+IBwbDfAOOA4XJhsbJhtaCAwwDAgHBUAFBwgYMDAYAaAYGP62GyYbGybAiAsLiAYHBwAACAAA/8AB
wAHAAAkAFQAhAC0AOQBFAFEAbwAAFREhERQGIyEiJiUVFDsBMj0BNCsBIh0BFDsBMj0BNCsBIicVFDsBMj0BNCsBIh0BFDsBMj0B
NCsBIicVFDsBMj0BNCsBIh0BFDsBMj0BNCsBIgEyFh0BITU0NjsBNTQ2OwEyFh0BMzU0NjsBMhYdAQHAHBT+oBQcAUAMKAwMKAwM
KAwMKAyADCgMDCgMDCgMDCgMgAwoDAwoDAwoDAwoDAFQFBz+QBwUMAkHIAcJgAkHIAcJEAEQ/vAUHBzYKAwMKAyMKAwMKAx0KAwM
KAyMKAwMKAx0KAwMKAyMKAwMKAwBQBwUMDAUHDAHCQkHMDAHCQkHMAABAAAAAAIAAYAAEQAAATIWHQEUBiMhIiY1ETQ2OwEXAdAU
HBwU/mAUHBwUoEABQBwU4BQcHBQBIBQcQAAFAAAAAAIAAYAADwAfAC8APwBUAAAlIiY9ATQ2OwEyFh0BFAYjMyImPQE0NjsBMhYd
ARQGIyEiJj0BNDY7ATIWHQEUBiMzIiY9ATQ2OwEyFh0BFAYjFzIWHQEUBiMhIiY1ETQ2OwEyFhURAU0FCAgFJgUICAU6BQgIBSYF
CAgF/roFCAgFJgUICAU6BQgIBSYFCAgF3QcJCQf+MA0TCQcgBwmACAWGBQgIBYYFCAgF5gUICAXmBQgIBUYFCAgFRgUICAXGBQgI
BcYFCEAJByAHCRMNAVAHCQkH/tAAAwAA/8ACQAHAADMAOwBDAAABMhYdARQHBgcOAQ8BFTMyFh0BFCMhIj0BNDY7ATUuAicmJyY9
ATQ2OwE1NDYzITIWHQEFFhcmJyMVFCU1IwYHNjc2AigKDj4wPg4iCgowGyUM/tgMJRswBA4kDj4wPg4KaA4KARAKDv6jExcLAkAB
wEACCxcTIwGADgo4OC0iBxgkBwdIHhoMDAwMGh5IAgomGAciLTg4Cg4oCg4OCiiBDQgpLRAXFxAtKQgNGgAAAgAA/8ACQAHAACwA
NAAAJBQHFRQGIyIvASYrAQYVFBcWBisBIicmNTQ3IyImPQE0NjsBMj8BNjMyFh0BBxEHBiMVMhcCQCAQEAsJVUJVHAQaCxITSxQI
GQIiGyUlG8BVQlUJCxAQQCFUa2tU9UoSmQoWB0Q1EBArIhAjETU6EBAlG2AbJTVEBxYKmcQBGhpDYEMAAAL///+/AgUBxQAcACQA
AAEWBgcOAScHBiImND8BJjY3PgEXHgEPAR8BNzYWADI2NCYiBhQB/AkUGx5QJtUTNSUT1Q0SHRtKJAcDBUoLREsFDf48FA4OFA4B
UyRJHB0SDdUTJTUT1iVRHRsUCQINBUtEC0oFA/6ODhQODhQAAAH///+/AgABwQA7AAAlBwYiLwEmNjsBNSMVFAYvASY0PwE2Fh0B
MzUjIiY/ATYyHwEWBisBFTM1NDYfARYUDwEGJj0BIxUzMhYBYE8HFAdPCwwQM2UdDE8HB08MHWUzEA0MTwcUB08LDBAzZR0MTwcH
TwwdZTMQDRZPBwdPDB1lMxAMC08HFAdPDA0QM2UdDE8HB08MHWUzEAwLTwcUB08MDRAzZR0AAAYAAP/gAoABoAAHAA8AHQAlADkA
RwAANiImNDYyFhQEIiY0NjIWFAcyFh0BFAYrAS4BJzYzKgEmNDYyFhQHMhYdARQGIyEiJj0BNDY7ARYyNycOAQcjIiY9ATQ2OwEy
ejQmJjQmAZo0JiY0JiAaJhMNQgUoHhMaklxCQlxCIzBDHBT+4BQcQzAJIUYh1x4oBUINEyYaQBrgJjQmJjQmJjQmJjRGJhogDRMj
OhATQlxCQlxiQzAdFBwcFB0wQxAQDRA6IxMNIBomAAADAAD/4AHAAaAAEQAZACgAAAEWFREUBiMhIiY1ETQ2MyEyFwIyNjQmIgYU
EzQvASYrASIdARQ7ATI1AbIOHBT+oBQcHBQBDBQOmTYlJTYloAQDBATlDAzoDAE+DhT+9BQcHBQBYBQcDv6OJTYlJTYBDAQEAwQM
aAwMAAQAAP/AAoABwAAnAC8ANwA8AAAlMhYdARQGKwEUBiImNSMUBiImNSMiJjURNDYzITIWHQEzMh8BFh0BBDI2NCYiBhQEMjY0
JiIGFDc1JyMVAnAHCQkHMDhQOIA4UDgQFBwcFAFAFBwsFA5kDv4sKBwcKBwBXCgcHCgcgGQsYAkHIAcJKDg4KCg4OCgcFAFAFBwc
FDAOZA4UbHAcKBwcKBwcKBwcKLQMZHAAAf/+/8ABRAHAABcAAAEyFgcDBiMiJj8BIyImPwE+ATsBMhYPAQEoDg4HsAcODA4DLncL
DgEgAQ4JkAwOAyoBIBgM/tAMEgzCEAvwCQwTC4IAAAL////AAcEBwAAFACkAABYiJjUzFDcWFRQGIyEiJjU0NzY3PgI1NDY3NTQ2
MhYdAR4BFRQeARcW+jQmgJcJEg7+gA4SCQECDxEUSDgTGhM4SBQRDwJAJRsbcQoMDRMTDQwKAQMPGEMsOlYLFQ0TEw0VC1Y6LEMY
DwMADQAAAAACQAGAAA8AGwAnADMAPwBLAFcAYwBvAHsAhwCTAJ8AACkBIiY1ETQ2MyEyFhURFAYBNTQrASIdARQ7ATI3NTQrASId
ARQ7ATI3NTQrASIdARQ7ATI3NTQrASIdARQ7ATI3NTQrASIdARQ7ATIFNTQrASIdARQ7ATI3NTQrASIdARQ7ATI3NTQrASIdARQ7
ATI3NTQrASIdARQ7ATIFNTQrASIdARQ7ATIlNTQrASIdARQ7ATI3NTQrASIdARQ7ATICEP4gFBwcFAHgFBwc/lwMKAwMKAxgDCgM
DCgMYAwoDAwoDGAMKAwMKAxgDCgMDCgM/rAMKAwMKAxgDCgMDCgMYAwoDAwoDGAMKAwMKAz+sAwoDAwoDAEgDOgMDOgMYAwoDAwo
DBwUASAUHBwU/uAUHAEMKAwMKAwMKAwMKAwMKAwMKAwMKAwMKAwMKAwMKAxUKAwMKAwMKAwMKAwMKAwMKAwMKAwMKAxUKAwMKAwM
KAwMKAwMKAwMKAwABAAA/8gB8AG4AAcADwAXAB8AABIyFhQGIiY0EjI2NCYiBhQ2MhYUBiImNBYyNjQmIgYUkc6Rkc6RrJhsbJhs
g2pLS2pLZjQmJjQmAbiRzpGRzv7hbJhsbJjMS2pLS2p1JjQmJjQABP/+AAACAgGAADUAPwBOAF0AAAEyFg8BBisBFh0BFAcVFAYr
ASImPQEhFRQGKwEiJj0BJj0BNDcjIi8BJjY7ATc+ATsBMhYfASUHIScuASsBIgYHOgI+AzU0JiIGFBYhMjY0JiIGFRQeAzoBAfQG
BwEGAwkUFhATDSANE/8AEw0gDRMQFhQJAwYBBwY8EQw5IoAiOQwR/twUAQAUBRkOgA4ZOQINBgsGBwMiHBISAU4OEhIcIgMHBgsG
DQEQCQYYCRMdMBgSNg0TEw0gIA0TEw02EhgwHRMJGAYJKiAmJiAqEjIyDRERrwECAwYEDyESHBISHBIhDwQGAwIBAAACAAj/xwH5
AbgAJQA3AAAAFAYjIicuAT8BPgEXFjMyNjQmIyIHFxYGKwEiJj0BNDYfATYzMgMOAS8BNTQ2OwEyFh0BFx4BBwH4kWdYRAgBCAsG
EwcyQExsbExJNTMHCAuRBwkUBzJIY2ckBhQIQQ4KEAoOKQgCBgEnzZI3BxUICwYBBShsmGwyMwcUCQeRCwgHMkX+uggDBjOICg4O
CmggBhQIAAMAAP/gAgABoAAjAEcAawAAJTIWHQEUBiMhFRQGKwEiJj0BIyImPQE0NjsBNTQ2OwEyFh0BJTIWHQEUBisBFRQGKwEi
Jj0BISImPQE0NjMhNTQ2OwEyFh0BNzIWHQEUBisBFRQGKwEiJj0BIyImPQE0NjsBNTQ2OwEyFh0BAfAHCQkH/rAJByAHCVAHCQkH
UAkHIAcJAVAHCQkHUAkHIAcJ/rAHCQkHAVAJByAHCVAHCQkH0AkHIAcJ0AcJCQfQCQcgBwlACQcgBwkQBwkJBxAJByAHCRAHCQkH
EKAJByAHCRAHCQkHEAkHIAcJEAcJCQcQoAkHIAcJEAcJCQcQCQcgBwkQBwkJBxAAAgAA/8ABwAHBABcAIQAAATIWHQEUBiMhIiY9
ATQ2OwE3NjsBMh8BAQMhAw4BKwEiJgGwBwkJB/5gBwkJB3gJBw9yDwcJ/v0VAYAVARwT9hMcAaAJByAHCQkHIAcJEw0NE/5NAVP+
rRMaGgAAAgAAAAACAAGAABQAMgAAJTIWHQEUBiMhIiY1ETQ2OwEyFhURATIWHQEUBi8BBwYiLwEHBi8BJj8BNjIfATcnJjYzAfAH
CQkH/jANEwkHIAcJAZAHCR4LIGAKGgpJLgsMFgwMRAoaCklJIAsMEEAJByAHCRMNAVAHCQkH/tABIAkHdhAMCyBgCQlKLgwMFgwL
RQkJSkogCx4AAAMAAP/AAYABwAApAC8ANQAAATIWHQEUBiMUBgceARUyFh0BFAYjISImPQE0NjM0NjcuATUiJj0BNDYzAS4BIgYH
EzY1IxQXAWgKDg4KRDU1RAoODgr+sAoODgpENTVECg4OCgEFDTI8Mg26C9ALAcAOChAKDkNrEhJrQw4KEAoODgoQCg5DaxISa0MO
ChAKDv6AJCwsJAEAHiIiHgAABf/8/8ABxAHAAAcADwAXAB8ALQAANiImNDYyFhQmIgYUFjI2NBYyFhQGIiY0FjI2NCYiBhQTMzIW
BwEGKwEiJjcBNp5cQkJcQlwoHBwoHIJcQkJcQlwoHBwoHGggDg4I/pEHDCIODgkBcAfgQlxCQlxeHCgcHCjEQlxCQlxeHCgcHCgB
pBoM/jAKGgwB0AoAAgAQ/8ABtgHAACIAMAAAJRQGIiY1NDY3NSMiPQE0OwEyHQEUKwEVFhc3Nh8BFg8CFgc1NCYrASIGHQEUOwEy
AbB6rHplSxwMDHgMDBw4LBsJCBwJCR0BIrAHBSgFBwwoDJBWenpWTXUMIgwoDAwoDCIJJBsJCRwICR0BM2KYBAgIBJgMAAAB//3/
wAFFAcEAGQAAARYGKwERFAYrASImPwE2OwERIyImPwE2MhcBOgoMEEAOCsQIBgY4AwVUQBAMCmgIFAgBSAsd/rgKDg8FOAQBEB0L
cAgIAAACABD/vAHwAcAAFgAbAAABHgEVFA4CBwYnLgM1NDY/ATYyFwM+ATcnAdIOECxGSCQSEipNQCcQDsAIFAgSS2MCsAFsBRgP
TolbPA4ICBFDX4JHDxgFUAQE/kYlomxKAAAHAAD/4AJAAaAADQAbACMAKwA8AEYATgAAEjIWFRQHBiMhIicmNTQlIgYUFjMyPwE0
NjEuAQIyNjQmIgYUNjI2NCYiBhQlNi4BBg8BDgEVFBczNjU0JzcWMzI2NCYjIgcWMjY0JiIGFKnuqScJEv5EEgknASANExMNCQkJ
AwMQ2BoTExoTQxoTExoTARcDCRMSAz0ZIwluCRdMChENExMNBQYuGhMTGhMBoKl3TkMPD0NOd2kTGhMGHAEFCw3+4BMaExMajRMa
ExMaNQoSBgkJuAIlGREPDxEdE38PExoTAt4TGhMTGgAAAwAA/8ACAAHAAAgAEQAbAAABMBcjNTMyFhcnFSM2MTc+ATMHIRUUBiMh
IiY1Af4B740QGQXb7wEzBRkQYwIAHBT+YBQcAQcHwBIPIcAHmA8S4PAUHBwUAAYAAP/AAgABwAAJABEAHQAkACwANAAANRYgNxUU
BiImNQAiJjQ2MhYUBR4BMjY3FRQGIiY1JTU2NxUUBiQyFhQGIiY0BSYnNjcVFAY9AQY9cZ5xAY+ecXGecf4AHmh0aB5xnnEBoD8h
NP6koHBwoHABmwwwbjM3KysrKxomJhoBQCY0JiY00hkbGxk0GiYmGik/CxgrER6PL0IvL0IJIhcFJSsSHgADAAD/wAIAAcAADwBA
AEQAACEyFh0BFAYjISImPQE0NjMBFh0BFAYnLgE9ATQmKwEVIRE0NjsBMhYdATMyFh0BFBYyNj0BLgE9AScmND8BNjIXBzUjFQFQ
BwkJB/7ABwkJBwHdEy8hGyUXEQj+4CYaoBomCCQ0DhQOFBwmBAQMBA4EnKAJByAHCQkHIAcJAVUTG98gKwMDLB0cERdwAWAaJiYa
wDQkIAoODgqhAx8VPiYEDgQMBASmgIAAAAYAAP/gAoEBoQAdACMAKQAxADcAPQAAARYVERQGIyInJiMiBiMiJyY1ETQ2MzIXFjMy
NjMyBRUyNjcmAxYXLgEjNjI2NCYiBhQFNQ4BBxY3NSYnHgECbRMTDQUGKzE+9j4/NRMTDQUGKzE+9j4//fgXIwUkGx4iASUa70Iv
L0IvAWAUHgQfFxoeASABiggW/sMOEgINPhYIFgE9DhICDT5kPR4WAv7qCwMaJBE4UDg4UFQ6AxsTA+YxCgMYIwAF//f/ugIAAcsA
FQAdACUALQA1AAATNh4BFRQGKwEiBhcWBgcGLgI3PgECMjY0JiIGFDYyNjQmIgYUNjI2NCYiBhQWMjY0JiIGFMxQj1UmG1AmKBEP
Gh8vaFApDQ9uLxoTExoTMxoTExoTkxoTExoTkxoTExoTAbsQPX9OGyZAIhw7BQcqUH1DSm3+1BMaExMabRMaExMaLRMaExMaUxMa
ExMaAAIAAP/gAgABoAAcACQAAAEyFhURFAYjISImNRE0NjMhMhYVFAYjISIGFBYzBDI2NCYiBhQBzRUeHhX+cxslJRsBcBQcCQf+
gAcJCQcBQxoTExoTAUAcFP8AFBwlGwFAGyUcFAcJCQ4J0BMaExMaAAABAAAAMAFaACAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAA
AAAtAFIAiwDZAUMBoAHOAjwCZQLkAy4DZQPBA/MENgRsBPQFEgWABeAGKgZpBr0HIgdfB7QH3QgaCNoJDQmMCd4KYwqZCuYLNQt9
C8AL6gwaDI4Mug0NDWsNyg4cDlQAAAABAAABS4YkLEAJJ18PPPUACwIAAAAAAN0wfgAAAAAA3TB+Cf/s/7QClQHNAAAACAACAAAA
AAAAAgAAAAJAAA8CAAAAAWAAAAIAAAcCAAAQAkAAAAIAAAgCAAAAAgAAAAIAAAACAAAIAgAACAIAAAABgAAAAkAAAAJA//kBwAAA
AgAAAAIAAAACQAAAAkAAAAIAAAACAAAAAoAAAAHAAAACgAAAAUD//wHAAAACQAAAAfAAAAIA//8CAAAIAgAAAAHAAAACAAAAAYAA
AAHA//0BwAAQAUD//gIAABACQAAAAgAAAAIAAAACAAAAAoAAAAIA//gAAAAAAAEAAAHA/8AAAAKA/+wAAAKVAAEAAAAAAAAAAAAA
AAAAAAAvAAQB+wOEAAUAAAFMAWYAAABHAUwBZgAAAPUAGQCEAAACAAUDAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFBmRWQAgPAF9VUB
wP/AAC4BzABUAAAAAQAAAAABOgGlAAAAIAABAAAAAgAAAAMAAAAUAAMAAQAAABQABAF4AAAAWgBAAAUAGvAF8A3wEfAT8BXwF/Ah
8CvwOvBa8GvwbvBx8HPwe/CA8JHwofCt8LLwwPDH8NHw5/Dz8RzxQPG58drx3vH48gHyUvKV8vLzv/Pt8/30ZvUe9S/1OvU/9VX/
/wAA8AXwDPAR8BPwFfAX8CHwK/A68Fnwa/Bt8HHwc/B78IDwkfCh8K3wsvDA8Mfw0fDn8PPxHPFA8bnx2vHe8fjyAfJS8pXy8vO/
8+3z/fRm9R71L/U69T/1Vf//D/wP9g/zD/IP8Q/wD+cP3g/QD7IPog+hD58Png+XD5MPgw90D2kPZQ9YD1IPSQ80DykPAQ7eDmYO
Rg5DDioOIg3SDZANNAxoDDsMLAvECw0K/QrzCu8K2gABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABwBaAAMAAQQJAAAANAAAAAMAAQQJAAEA
MgA0AAMAAQQJAAIACgBmAAMAAQQJAAMAQABwAAMAAQQJAAQAMgA0AAMAAQQJAAUATACwAAMAAQQJAAYALAD8AEMAbwBwAHkAcgBp
AGcAaAB0ACAAKABjACkAIABGAG8AbgB0ACAAQQB3AGUAcwBvAG0AZQBGAG8AbgB0ACAAQQB3AGUAcwBvAG0AZQAgADUAIABGAHIA
ZQBlACAAUwBvAGwAaQBkAFMAbwBsAGkAZABGAG8AbgB0ACAAQQB3AGUAcwBvAG0AZQAgADUAIABGAHIAZQBlACAAUwBvAGwAaQBk
AC0ANQAuADEANQAuADQAMwAzADEALgA1ADIANAAgACgARgBvAG4AdAAgAEEAdwBlAHMAbwBtAGUAIAB2AGUAcgBzAGkAbwBuADoA
IAA1AC4AMQA1AC4ANAApAEYAbwBuAHQAQQB3AGUAcwBvAG0AZQA1AEYAcgBlAGUALQBTAG8AbABpAGQAAAADAAAAAAAA/9sAGQAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAf//AAIAAQAAAAwAAAAAAAAAAgABAAEALwACAAA=
]]

imgui.OnInitialize(function()
    if fonts_ready then return end
    fonts_ready = true
    local okInit, errInit = pcall(function()
        local K = imgui.MB.K
        local imio = imgui.GetIO()
        local cyr = imio.Fonts:GetGlyphRangesCyrillic()
        local ranges = cyr
        pcall(function()
            local builder = imgui.ImFontGlyphRangesBuilder()
            builder:AddRanges(cyr)
            builder:AddText('\226\128\154\226\128\158\226\128\166\226\128\160\226\128\161\226\130\172\226\128\176\226\128\185\226\128\152\226\128\153\226\128\156\226\128\157\226\128\162\226\128\147\226\128\148\226\132\162\226\128\186\226\132\150')
            local vec = imgui.ImVector_ImWchar()
            builder:BuildRanges(vec)
            font_keep.builder, font_keep.vec = builder, vec
            ranges = vec.Data
        end)
        font_keep.cyr = ranges

        local wd = getWorkingDirectory()
        pcall(function()
            local B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            local T = {}
            for i = 1, 64 do T[B:byte(i)] = i - 1 end
            local data = font_keep.fa_b64:gsub('[^%w%+/]', '')
            local out, n = {}, 0
            for i = 1, #data - 3, 4 do
                local a, b, c, d = data:byte(i, i + 3)
                local v = T[a] * 262144 + T[b] * 4096 + T[c] * 64 + T[d]
                n = n + 1
                out[n] = string.char(math.floor(v / 65536), math.floor(v / 256) % 256, v % 256)
            end
            local rest = #data % 4
            if rest >= 2 then
                local i = #data - rest + 1
                local a, b, c = data:byte(i, i + 2)
                local v = T[a] * 4096 + T[b] * 64 + (rest == 3 and T[c] or 0)
                n = n + 1
                out[n] = rest == 3 and string.char(math.floor(v / 1024) % 256, math.floor(v / 4) % 256) or string.char(math.floor(v / 16) % 256)
            end
            local bin = table.concat(out)
            local path = ROOT .. '/fa-icons.ttf'
            local f = io.open(path, 'rb')
            local same = false
            if f then same = (#f:read('*a') == #bin) f:close() end
            if not same then
                createDirectory(getWorkingDirectory() .. '/config')
                createDirectory(ROOT)
                local w = io.open(path, 'wb')
                if w then w:write(bin) w:close() end
            end
            FA_PATH = path
        end)
        font_keep.fa_b64 = nil
        for _, p in ipairs({FA_PATH, wd .. '/resource/fonts/fa-solid-900.ttf', wd .. '/lib/fa-solid-900.ttf', wd .. '/fa-solid-900.ttf'}) do
            if doesFileExist(p) then FA_PATH, fa_ok = p, true break end
        end

        local regular, bold
        local pairs_list = {
            {wd .. '/resource/fonts/arial.ttf', wd .. '/resource/fonts/arialbd.ttf'},
            {'/system/fonts/Roboto-Regular.ttf', '/system/fonts/Roboto-Bold.ttf'},
            {'/system/fonts/RobotoStatic-Regular.ttf', '/system/fonts/RobotoStatic-Bold.ttf'},
            {'/system/fonts/NotoSans-Regular.ttf', '/system/fonts/NotoSans-Bold.ttf'},
            {'/system/fonts/DroidSans.ttf', '/system/fonts/DroidSans-Bold.ttf'},
        }
        for _, pr in ipairs(pairs_list) do
            if doesFileExist(pr[1]) then
                regular = pr[1]
                bold = doesFileExist(pr[2]) and pr[2] or regular
                break
            end
        end

        local function make(path, size, fa_size)
            local font = imio.Fonts:AddFontFromFileTTF(path, size * K, nil, ranges)
            font_keep[#font_keep + 1] = font
            if fa_ok then
                local font_config = imgui.ImFontConfig()
                font_config.MergeMode = true
                font_config.PixelSnapH = true
                local fa_ranges = imgui.new.ImWchar[3](0xF000, 0xF8FF, 0)
                local merged = imio.Fonts:AddFontFromFileTTF(FA_PATH, fa_size * K, font_config, fa_ranges)
                font_keep[#font_keep + 1] = font_config
                font_keep[#font_keep + 1] = fa_ranges
                font_keep[#font_keep + 1] = merged
            end
            return font
        end

        if regular then
            fonts.main  = make(regular, 16, 15)
            fonts.title = make(bold, 18, 17)
            fonts.big   = make(bold, 27, 25)
        else
            font_keep.noFont = true
        end
        if fa_ok then
            for name, cp in pairs(ICON_CP) do icons[name] = utf8char(cp) end
        end
    end)
end)

local UNW = {}

local function pushFont(f) if f then imgui.PushFont(f) UNW[#UNW + 1] = 'font' end end
local function popFont(f) if f then imgui.PopFont() UNW[#UNW] = nil end end

local function pushVar(idx, v) imgui.PushStyleVar(idx, v) UNW[#UNW + 1] = 'var' end
local function popVar(n) n = n or 1 imgui.PopStyleVar(n) for _ = 1, n do UNW[#UNW] = nil end end
local function pushCol(idx, c) imgui.PushStyleColor(idx, c) UNW[#UNW + 1] = 'col' end
local function popCol(n) n = n or 1 imgui.PopStyleColor(n) for _ = 1, n do UNW[#UNW] = nil end end

local function beginWin(name, open, flags)
    imgui.Begin(name, open, flags)
    UNW[#UNW + 1] = 'win'
end
local function endWin() imgui.End() UNW[#UNW] = nil end

local function beginChild(id, size, border, flags)
    if flags then imgui.BeginChild(id, size, border, flags) else imgui.BeginChild(id, size, border) end
    UNW[#UNW + 1] = 'child'
    return true
end
local function endChild()
    imgui.EndChild()
    UNW[#UNW] = nil
end
local function beginChildP(px, py, id, size, border, flags)
    pushVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(px, py))
    beginChild(id, size, border, flags)
    return true
end
local function endChildP()
    endChild()
    popVar()
end

local function unwindTo(mark)
    for i = #UNW, mark + 1, -1 do
        local k = UNW[i]
        UNW[i] = nil
        pcall(function()
            if k == 'var' then imgui.PopStyleVar(1)
            elseif k == 'col' then imgui.PopStyleColor(1)
            elseif k == 'font' then imgui.PopFont()
            elseif k == 'child' then imgui.EndChild()
            elseif k == 'win' then imgui.End() end
        end)
    end
end

local function safeCall(name, fn)
    local mark = #UNW
    local ok = xpcall(fn, function(e) imgui.MB.err = '[' .. tostring(name) .. '] ' .. debug.traceback(tostring(e), 2) return e end)
    if not ok then
        unwindTo(mark)
        return false
    end
    return true
end

local Store = {}
do
    local KEY_ORDER = {
        'name', 'base_name', 'tier', 'model', 'kind', 'tracked', 'builtin', 'auto',
        'duration', 'hours', 'runs', 'drops', 'count', 'qty', 'unit', 'total',
        'bonus_total', 'bonus_last', 'bonus_max', 'last',
        'first_seen', 'last_seen', 'variants',
        'time', 'text', 't', 'd', 'v', 'n', 'q', 'k', 'dur',
    }
    local KEY_RANK = {}
    for i, k in ipairs(KEY_ORDER) do KEY_RANK[k] = i end
    local function keyLess(a, b)
        local ra, rb = KEY_RANK[a], KEY_RANK[b]
        if ra and rb then return ra < rb end
        if ra then return true end
        if rb then return false end
        return a < b
    end

    local ESC = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
    local function jsonStr(s)
        s = s:gsub('[%c"\\]', function(c) return ESC[c] or string.format('\\u%04x', c:byte()) end)
        return '"' .. s .. '"'
    end

    local function jsonEncode(v, ind)
        ind = ind or ''
        local t = type(v)
        if t == 'boolean' then return tostring(v) end
        if t == 'number' then
            if v ~= v or v == math.huge or v == -math.huge then return '0' end
            if v == math.floor(v) and math.abs(v) < 1e15 then return string.format('%.0f', v) end
            return string.format('%.6g', v)
        end
        if t == 'string' then return jsonStr(v) end
        if t ~= 'table' then return 'null' end
        if next(v) == nil then return '[]' end

        local ni = ind .. '  '
        local parts = {}
        if #v > 0 then
            for i = 1, #v do parts[#parts + 1] = ni .. jsonEncode(v[i], ni) end
            return '[\n' .. table.concat(parts, ',\n') .. '\n' .. ind .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys, keyLess)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            parts[#parts + 1] = ni .. jsonStr(k) .. ': ' .. jsonEncode(val, ni)
        end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. ind .. '}'
    end

    local function jsonDecode(s)
        local pos = 1
        local function skip() pos = s:find('%S', pos) or (#s + 1) end
        local parseValue

        local function parseString()
            local out, i = {}, pos + 1
            while true do
                local j = s:find('["\\]', i)
                if not j then error('unterminated string') end
                out[#out + 1] = s:sub(i, j - 1)
                if s:sub(j, j) == '"' then pos = j + 1 break end
                local n = s:sub(j + 1, j + 1)
                if n == 'u' then
                    local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
                    out[#out + 1] = utf8char(cp)
                    i = j + 6
                else
                    local map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
                    out[#out + 1] = map[n] or n
                    i = j + 2
                end
            end
            return table.concat(out)
        end

        parseValue = function()
            skip()
            local c = s:sub(pos, pos)
            if c == '{' then
                local obj = {}
                pos = pos + 1
                skip()
                if s:sub(pos, pos) == '}' then pos = pos + 1 return obj end
                while true do
                    skip()
                    if s:sub(pos, pos) ~= '"' then error('object key expected at ' .. pos) end
                    local k = parseString()
                    skip()
                    if s:sub(pos, pos) ~= ':' then error('colon expected at ' .. pos) end
                    pos = pos + 1
                    obj[k] = parseValue()
                    skip()
                    local d = s:sub(pos, pos)
                    pos = pos + 1
                    if d == '}' then return obj end
                    if d ~= ',' then error('comma expected at ' .. pos) end
                end
            elseif c == '[' then
                local arr = {}
                pos = pos + 1
                skip()
                if s:sub(pos, pos) == ']' then pos = pos + 1 return arr end
                while true do
                    arr[#arr + 1] = parseValue()
                    skip()
                    local d = s:sub(pos, pos)
                    pos = pos + 1
                    if d == ']' then return arr end
                    if d ~= ',' then error('comma expected at ' .. pos) end
                end
            elseif c == '"' then
                return parseString()
            elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
            elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
            elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
            else
                local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
                if not num or num == '' then error('unexpected symbol at ' .. pos) end
                pos = pos + #num
                return tonumber(num)
            end
        end

        local res = parseValue()
        return res
    end

    local function ensureDirs()
        local cdir = getWorkingDirectory() .. '/config'
        if not doesDirectoryExist(cdir) then createDirectory(cdir) end
        if not doesDirectoryExist(ROOT) then createDirectory(ROOT) end
    end

    local function readJson(path)
        local f = io.open(path, 'rb')
        if not f then return nil end
        local s = f:read('*a')
        f:close()
        local ok, res = pcall(jsonDecode, s)
        if ok and type(res) == 'table' then return res end
        pcall(os.remove, path .. '.bak')
        pcall(os.rename, path, path .. '.bak')
        return nil
    end

    local function writeJson(path, tbl)
        local tmp = path .. '.tmp'
        local f = io.open(tmp, 'wb')
        if not f then return false end
        f:write(jsonEncode(tbl), '\n')
        f:close()
        os.remove(path)
        if not os.rename(tmp, path) then
            local g = io.open(path, 'wb')
            if not g then return false end
            g:write(jsonEncode(tbl), '\n')
            g:close()
            os.remove(tmp)
        end
        return true
    end

    Store.decodeJson = jsonDecode
    Store.readJson = readJson
    Store.writeJson = writeJson
    Store.ensureDirs = ensureDirs
end

local THEMES = {
    {name = '\208\158\209\128\208\176\208\189\208\182\208\181\208\178\209\139\208\185', c = {255, 165, 0}},
    {name = '\208\161\208\184\208\189\208\184\208\185',     c = {64, 156, 255}},
    {name = '\208\145\208\184\209\128\209\142\208\183\208\190\208\178\209\139\208\185', c = {32, 201, 190}},
    {name = '\208\151\208\181\208\187\209\145\208\189\209\139\208\185',   c = {72, 205, 130}},
    {name = '\208\164\208\184\208\190\208\187\208\181\209\130\208\190\208\178\209\139\208\185', c = {160, 110, 255}},
    {name = '\208\160\208\190\208\183\208\190\208\178\209\139\208\185',   c = {255, 105, 170}},
    {name = '\208\154\209\128\208\176\209\129\208\189\209\139\208\185',   c = {255, 82, 82}},
    {name = '\208\160\208\176\208\180\209\131\208\179\208\176 (\208\191\208\187\208\176\208\178\208\189\208\190 \208\191\208\181\209\128\208\181\208\187\208\184\208\178\208\176\208\181\209\130\209\129\209\143)', c = {255, 80, 80}, rainbow = true},
}

local KIND = {
    truck  = {name = '\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', short = '\208\160\208\176\208\177. \208\148\208\145', icon = 'users', c = {255, 165, 0}},
    car    = {name = '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129',  short = '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129', icon = 'car',    c = {64, 156, 255}},
    other  = {name = '\208\159\209\128\208\190\209\135\208\184\208\181',      icon = 'wallet', c = {72, 205, 130}},
    chests = {name = '\208\155\208\176\209\128\209\134\209\139',       icon = 'gift',   c = {255, 214, 10}},
    items  = {name = '\208\151\208\176\209\130\208\190\209\135\208\186\208\184',     icon = 'star',   c = {190, 120, 255}},
}

local DEF_CFG = {
    theme = 1,
    enabled = true,
    value = {chest = 400000, eternal = 20000000, tempHour = 10000},
    sessionHours = 0,
    notify = true,
    menu = {x = -1, y = -1},
    bonus_dot_thousands = true,
    track = {truck = true, car = true, chests = true, items = true, other = true,
             pack = true,
             expenses = true,
             skill = true,
             orders = true,
             salaryHint = true,
             promo = true,
             percent = true,
                 salary = true,
                 silent = true,
                 unknown = false},
    other_min = 1000,
    other_max = 0,
    goal = {enabled = true, amount = 1000000},
    orders = {
        enabled = true,
        key = 0x48,
        bx = -1, by = -1,
        mode = 'per_km',
        speed = 60,
        fragilityPenalty = 25,
        capacity = 0,
        myTier = 0,
        minPayout = 0,
        onlyGreat = false,
        chatHint = true,
        x = 50, y = 74,
        scale = 1.0,
        autoSpeed = true,
        showEmpty = true,
        linger = 2,
    },
    overlay = {
        enabled = false, x = 40, y = 300, opacity = 0.90, scale = 1.0, hideOnCursor = true,
        show = {total = true, truck = true, car = true, other = true, chests = true, items = true,
                today = true, hourly = true, session = true, goal = true, order = true, expenses = true, skill = true, trips = true, hp = true, salary = true, promo = true},
    },
}
local DEF_STATS = {
    truck  = {total = 0, count = 0, last = 0},
    car    = {total = 0, count = 0, last = 0},
    other  = {total = 0, count = 0, last = 0},
    chests = {total = 0, drops = 0, last = ''},
    items  = {total = 0, drops = 0, last = ''},
    eternal = {total = 0, drops = 0, last = ''},
    ignored = {total = 0, count = 0},
    expenses = {fuel = 0, repair = 0, fine = 0, total = 0, count = 0},
    orders = {done = 0, unpaid = 0, paid = 0, seconds = 0, km = 0, byCategory = {}, byTier = {}, byCustomer = {}, speeds = {}},
    skill = {title = '', level = 0, exp = 0, maxExp = 0, gain = 0, gains = {}},
    salary = {percent = 0, last = '', count = 0, paid = 0, extra = 0, penalty = 0, penaltyAt = '', penaltyReason = '', other = false, reason = ''},
    goalRound = {day = '', base = 0, done = false},
    promo = {job = '', percent = 0, endsAt = 0, count = 0, paid = 0},
    periodStart = '',
    noticeDay = '',
    session = {},
    days = {},
    goal_day = '',
}
local DEF_HIST = {truck = {}, car = {}, other = {}, chests = {}, items = {}, ignored = {}, expenses = {}, orders = {}, journal = {}, recent = {}}

local function deepcopy(v)
    if type(v) ~= 'table' then return v end
    local r = {}
    for k, x in pairs(v) do r[k] = deepcopy(x) end
    return r
end

local function applyDefaults(t, d)
    for k, v in pairs(d) do
        if type(t[k]) ~= type(v) then
            t[k] = deepcopy(v)
        elseif type(v) == 'table' then
            applyDefaults(t[k], v)
        end
    end
end

local had_settings = doesFileExist(FILES.settings)
Store.ensureDirs()

local cfg = Store.readJson(FILES.settings) or {}
local stats   = Store.readJson(FILES.stats) or {}
local history   = Store.readJson(FILES.history) or {}
applyDefaults(cfg, DEF_CFG)
applyDefaults(stats, DEF_STATS)
applyDefaults(history, DEF_HIST)

local vehicleCatalog = {list = {}, idx = {}}
local itemCatalog = {list = {}, idx = {}}

local dirty = {}
local last_save = 0
local function mark(...)
    for _, n in ipairs({...}) do dirty[n] = true end
end

local function payload(name)
    if name == 'settings' then return cfg end
    if name == 'stats' then return stats end
    if name == 'history' then return history end
    if name == 'vehicles' then return {vehicles = vehicleCatalog.list} end
    if name == 'items' then return {items = itemCatalog.list} end
end

local function saveAll()
    if not ENC_OK then return false end
    Store.ensureDirs()
    local all_ok = true
    for name in pairs(dirty) do
        if Store.writeJson(FILES[name], payload(name)) then dirty[name] = nil else all_ok = false end
    end
    return all_ok
end

local function fmt(n)
    n = math.floor((n or 0) + 0.5)
    local s = tostring(math.abs(n))
    local out = s:reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', '')
    if n < 0 then out = '-' .. out end
    return out
end

local function fmtShort(n)
    if n >= 1000000 then return string.format('%.1fM', n / 1000000) end
    if n >= 1000 then return string.format('%.0fk', n / 1000) end
    return tostring(math.floor(n))
end

local function fmtDur(sec)
    sec = math.max(0, math.floor(sec))
    return string.format('%02d:%02d:%02d', math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

local function fmtMinSec(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds >= 3600 then
        return string.format('%d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

local function plural(n, one, few, many)
    n = math.floor(math.abs(n))
    local last, tens = n % 10, n % 100
    if tens >= 11 and tens <= 14 then return many end
    if last == 1 then return one end
    if last >= 2 and last <= 4 then return few end
    return many
end

local function lowerRu(s)
    s = s:lower()
    s = s:gsub('\208([\144-\159])', function(c) return '\208' .. string.char(c:byte() + 32) end)
    s = s:gsub('\208([\160-\175])', function(c) return '\209' .. string.char(c:byte() - 32) end)
    s = s:gsub('\208\129', '\209\145')
    return s
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
local function normName(s) return trim((s:gsub('%s+', ' '))) end
local function nowStamp() return os.date('%Y-%m-%d %H:%M:%S') end
local function todayKey() return os.date('%Y-%m-%d') end

local function pushLimited(list, item, limit)
    table.insert(list, 1, item)
    while #list > limit do table.remove(list) end
end

local function dayRec(key)
    local d = stats.days[key]
    if not d then
        d = {}
        stats.days[key] = d
        local keys = {}
        for k in pairs(stats.days) do keys[#keys + 1] = k end
        if #keys > 45 then
            table.sort(keys)
            for i = 1, #keys - 45 do stats.days[keys[i]] = nil end
        end
    end
    for _, f in ipairs({'money', 'chests', 'items', 'truck', 'car', 'other', 'expense', 'trips', 'eternal', 'bestTrip'}) do d[f] = d[f] or 0 end
    if type(d.hours) ~= 'table' then d.hours = {} end
    return d
end

local function totalMoney() return stats.truck.total + stats.car.total + stats.other.total end
local function todayMoney() return dayRec(todayKey()).money end

local function last7()
    local now = os.date('*t')
    now.hour, now.min, now.sec = 12, 0, 0
    local base = os.time(now)
    local keys = {}
    for i = 6, 0, -1 do keys[#keys + 1] = os.date('%Y-%m-%d', base - i * 86400) end
    return keys
end

local function newSession()
    return {start = os.time(), lastSeen = os.time(), idle = 0, money = 0, truck = 0, car = 0, other = 0, chests = 0,
            items = 0, eternal = 0, jobs = 0, log = {}, expense = 0, expenseLog = {}}
end

local SESSION_GAP = 1800
if type(stats.session) ~= 'table' or not stats.session.start
    or os.time() - (stats.session.lastSeen or stats.session.start) > SESSION_GAP then
    stats.session = newSession()
end
local session = stats.session
if type(session.log) ~= 'table' then session.log = {} end
if type(session.expenseLog) ~= 'table' then session.expenseLog = {} end
local Hooks = {}

local balance = nil
local money_events_seen = false
local pending_reset = nil
local unclaimed_gains = {}
local job_credits = {}
local money_notes = {}
local flash = {text = '', t = -100, kind = 'truck'}

local menu = imgui.ImBool(false)
local pending = {}

local chat_utf8 = false

local function detectChatEncoding(raw)
    if Charset.hasHigh(raw) then chat_utf8 = Charset.isValidUtf8(raw) end
end

local function chatOut(s)
    if chat_utf8 then return s end
    return Charset.utf8ToCp1251(s)
end

local function sendChat(msg)
    local th = THEMES[cfg.theme] or THEMES[1]
    local text = string.format('{%02X%02X%02X}[Truck Helper]: {FFFFFF}%s', th.c[1], th.c[2], th.c[3], msg)
    sampAddChatMessage(chatOut((text:gsub('%%', '%%%%'))), -1)
end

local function sendRaw(text)
    sampAddChatMessage(chatOut((text:gsub('%%', '%%%%'))), -1)
end

local chat_queue = {}
local function say(msg) chat_queue[#chat_queue + 1] = msg end
local function sayRaw(text) chat_queue[#chat_queue + 1] = {raw = text} end
local function flushChat()
    while #chat_queue > 0 do
        local m = table.remove(chat_queue, 1)
        if type(m) == 'table' then pcall(sendRaw, m.raw) else pcall(sendChat, m) end
    end
end

local function sayBanner()
    local line = '{FF0000}======================================'
    sayRaw(line)
    sayRaw('{FF0000}\194\166{FFFFFF} TRUCK HELPER v' .. SCRIPT_VERSION .. ' {FF0000}\194\166')
    sayRaw('{FF0000}\194\166{FFFFFF} - By {FF0000}Stalin{FFFFFF} - {FF0000}\194\166')
    sayRaw(line)
    sayRaw('{FF0000}\194\166{FFFFFF} \208\154\208\190\208\188\208\176\208\189\208\180\208\176: {FF0000}\194\166')
    sayRaw('{FF0000}\194\166{FFFFFF} {00FF00}/db{FFFFFF} - \208\179\208\187\208\176\208\178\208\189\208\190\208\181 \208\188\208\181\208\189\209\142 {FF0000}\194\166')
    sayRaw(line)
end

local function notify(msg)
    if cfg.notify then say(msg) end
end

local function setFlash(kind, text)
    flash.kind, flash.text, flash.t = kind, text, os.clock()
end

local HOURLY_WINDOW = 3600
local WORK_PAUSE = 900
local RATE_MIN_SECONDS = 600

local function touchWork()
    local now = os.time()
    if not session.workStart then
        session.workStart, session.lastWork, session.pauses = now, now, 0
        return
    end
    local gap = now - (session.lastWork or now)
    if gap > WORK_PAUSE then session.pauses = (session.pauses or 0) + gap - 120 end
    session.lastWork = now
end

local function windowSum(log, since)
    local sum, count = 0, 0
    for i = #log, 1, -1 do
        local entry = log[i]
        if entry.time < since then break end
        sum = sum + entry.amount
        count = count + 1
    end
    return sum, count
end

local function workedSeconds()
    if not session.workStart then return 0 end
    local last = session.lastWork or session.workStart
    local finish = math.min(os.time(), last + 600)
    return math.max(0, finish - session.workStart - (session.pauses or 0) - session.idle)
end

local function hourlyRates()
    local worked = workedSeconds()
    if worked < RATE_MIN_SECONDS then
        return nil, session.workStart and ('\208\181\209\137\209\145 ' .. math.ceil((RATE_MIN_SECONDS - worked) / 60) .. ' \208\188\208\184\208\189') or '\208\189\208\181\209\130 \208\180\208\176\208\189\208\189\209\139\209\133'
    end
    return {gross = session.money / worked * 3600, net = (session.money - session.expense) / worked * 3600,
            hasExpense = session.expense > 0, worked = worked}
end

local function hourlyText()
    local rates, reason = hourlyRates()
    if not rates then return reason end
    return '~ ' .. fmt(rates.gross) .. ' \209\128\209\131\208\177.'
end

local function hourlyNetText()
    local rates = hourlyRates()
    if not rates or not rates.hasExpense then return nil end
    return '~ ' .. fmt(rates.net) .. ' \209\128\209\131\208\177.'
end

local function goalProgress()
    local round = stats.goalRound
    local key = todayKey()
    if round.day ~= key then round.day, round.base, round.done = key, 0, false end
    return math.max(0, todayMoney() - round.base)
end

local function checkGoal()
    if not cfg.goal.enabled or cfg.goal.amount <= 0 then return end
    local progress = goalProgress()
    local round = stats.goalRound
    if not round.done and progress >= cfg.goal.amount then
        round.done = true
        mark('stats')
        say('\208\166\208\181\208\187\209\140 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176! \208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\189\208\190: ' .. fmt(progress) .. ' \209\128\209\131\208\177. \208\158\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\188\208\181\208\189\209\142 (/db), \209\135\209\130\208\190\208\177\209\139 \208\189\208\176\209\135\208\176\209\130\209\140 \208\183\208\176\208\189\208\190\208\178\208\190 \208\184\208\187\208\184 \208\191\208\190\209\129\209\130\208\176\208\178\208\184\209\130\209\140 \208\189\208\190\208\178\209\131\209\142 \209\134\208\181\208\187\209\140.')
    end
end

local Catalog = {}
do
    local function splitTier(name)
        local tier = name:match('[Tt]ier%s*(%d+)') or name:match('[Tt]ire%s*(%d+)')
        local base = name:gsub('%s*[Tt]ier%s*%d+', ''):gsub('%s*[Tt]ire%s*%d+', '')
        return normName(base), tonumber(tier) or 0
    end

    local function durationHours(text)
        local n, unit = text:match('(%d+)%s*(%S*)')
        n = tonumber(n)
        if not n then return 0 end
        unit = unit or ''
        if unit:find('^\208\188\208\184\208\189') then return n / 60 end
        if unit:find('^\209\135') then return n end
        if unit:find('^\208\180\208\189') or unit:find('^\209\129\209\131\209\130') then return n * 24 end
        if unit:find('^\208\189\208\181\208\180') then return n * 168 end
        if unit:find('^\208\188\208\181\209\129') then return n * 720 end
        return 0
    end

    local function newVehicle(name, auto)
        local base, tier = splitTier(name)
        local v = {
            name = name, base_name = base, tier = tier, model = 0,
            runs = 0, bonus_total = 0, bonus_last = 0, bonus_max = 0, pack_runs = 0, pack_total = 0, pack_last = 0,
            first_seen = nowStamp(), last_seen = nowStamp(), auto = auto,
        }
        vehicleCatalog.list[#vehicleCatalog.list + 1] = v
        vehicleCatalog.idx[name] = v
        return v
    end

    local function newItem(name, kind, auto)
        local it = {
            name = name, kind = kind,
            tracked = (kind == 'contract') or (name:find('\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185', 1, true) ~= nil),
            drops = 0, qty = 0, unit = '', variants = {},
            first_seen = nowStamp(), last_seen = nowStamp(), auto = auto,
        }
        itemCatalog.list[#itemCatalog.list + 1] = it
        itemCatalog.idx[name] = it
        return it
    end

    local function loadCatalogs()
        local vj = Store.readJson(FILES.vehicles)
        if vj and type(vj.vehicles) == 'table' then
            for _, v in ipairs(vj.vehicles) do
                if type(v) == 'table' and type(v.name) == 'string' and not vehicleCatalog.idx[v.name] then
                    local base, tier = splitTier(v.name)
                    v.base_name = v.base_name or base
                    v.tier = v.tier or tier
                    for _, f in ipairs({'model', 'runs', 'bonus_total', 'bonus_last', 'bonus_max', 'pack_runs', 'pack_total', 'pack_last'}) do v[f] = tonumber(v[f]) or 0 end
                    v.first_seen = v.first_seen or nowStamp()
                    v.last_seen = v.last_seen or v.first_seen
                    vehicleCatalog.list[#vehicleCatalog.list + 1] = v
                    vehicleCatalog.idx[v.name] = v
                end
            end
        end
        local ij = Store.readJson(FILES.items)
        if ij and type(ij.items) == 'table' then
            for _, it in ipairs(ij.items) do
                local lowered = type(it) == 'table' and type(it.name) == 'string' and lowerRu(it.name) or ''
                local keep = (it.kind == 'chest' and lowered:find('\208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185', 1, true))
                    or (it.kind == 'contract' and lowered:find('\208\180\208\184\208\178\208\184\208\180\208\181\208\189', 1, true))
                if keep and not itemCatalog.idx[it.name] then
                    it.kind = it.kind or 'item'
                    if it.tracked == nil then it.tracked = true end
                    for _, f in ipairs({'drops', 'qty'}) do it[f] = tonumber(it[f]) or 0 end
                    it.unit = it.unit or ''
                    it.variants = type(it.variants) == 'table' and it.variants or {}
                    it.first_seen = it.first_seen or nowStamp()
                    it.last_seen = it.last_seen or it.first_seen
                    itemCatalog.list[#itemCatalog.list + 1] = it
                    itemCatalog.idx[it.name] = it
                end
            end
        end

    end

    local function currentVehicleModel()
        local ok, m = pcall(function()
            if isCharInAnyCar(PLAYER_PED) then return getCarModel(storeCarCharIsInNoSave(PLAYER_PED)) end
            return 0
        end)
        return (ok and type(m) == 'number') and m or 0
    end

    local TRUCK_MODELS = {
        [403] = true, [414] = true, [455] = true, [456] = true, [498] = true, [499] = true, [515] = true,
        [524] = true, [525] = true, [543] = true, [552] = true, [554] = true, [578] = true, [609] = true,
    }

    local function isWorkModel(model)
        if model <= 0 then return false end
        if TRUCK_MODELS[model] then return true end
        for _, vehicle in ipairs(vehicleCatalog.list) do
            if vehicle.model == model and vehicle.runs > 0 then return true end
        end
        return false
    end

    local function currentTier()
        local model = currentVehicleModel()
        local best, bestSeen = 0, ''
        for _, vehicle in ipairs(vehicleCatalog.list) do
            if vehicle.tier and vehicle.tier > 0 and vehicle.runs > 0 then
                if model > 0 and vehicle.model == model then return vehicle.tier end
                if vehicle.last_seen > bestSeen then best, bestSeen = vehicle.tier, vehicle.last_seen end
            end
        end
        return best
    end

    local ENDINGS = {'\208\190\208\185', '\208\181\208\185', '\208\190\208\188', '\208\176\208\188', '\208\176\209\133', '\208\176', '\209\143', '\208\181', '\208\184', '\209\131', '\209\139', '\209\142', '\208\190'}

    local function vehicleKey(name)
        local first, rest = name:match('^(%S+)%s*(.*)$')
        first = lowerRu(first or '')
        for _, ending in ipairs(ENDINGS) do
            if #first - #ending >= 6 and first:sub(-#ending) == ending then
                first = first:sub(1, #first - #ending)
                break
            end
        end
        return first .. ' ' .. lowerRu(rest or '')
    end

    local function findVehicle(name)
        local v = vehicleCatalog.idx[name]
        if v then return v end
        local key = vehicleKey(name)
        for _, candidate in ipairs(vehicleCatalog.list) do
            if vehicleKey(candidate.name) == key then return candidate end
        end
        return nil
    end

    local function touchVehicle(name, bonus)
        name = normName(name)
        if name == '' then name = '\208\157\208\181\208\184\208\183\208\178\208\181\209\129\209\130\208\189\209\139\208\185 \209\130/\209\129' end
        local v, created = findVehicle(name), false
        if not v then v = newVehicle(name, true) created = true end
        if v.name ~= name then
            vehicleCatalog.idx[v.name] = nil
            v.name = name
            vehicleCatalog.idx[name] = v
        end
        v.runs = v.runs + 1
        v.bonus_total = v.bonus_total + bonus
        v.bonus_last = bonus
        v.bonus_max = math.max(v.bonus_max, bonus)
        v.last_seen = nowStamp()
        local m = currentVehicleModel()
        if m > 0 then v.model = m end
        mark('vehicles')
        return v, created
    end

    local function touchPack(vehicleText, packName, amount)
        local name = normName(vehicleText)
        if lowerRu(name):find('\208\187\208\184\209\135\208\189', 1, true) then name = '\208\155\208\184\209\135\208\189\209\139\208\185 \209\130/\209\129' end
        local v, created = findVehicle(name), false
        if not v then v = newVehicle(name, true) created = true end
        v.pack_runs = (v.pack_runs or 0) + 1
        v.pack_total = (v.pack_total or 0) + amount
        v.pack_last = amount
        v.pack_name = packName
        v.last_seen = nowStamp()
        mark('vehicles')
        return v, created
    end

    local function touchItem(name, kind, qty, unit, duration)
        name = normName(name)
        local it, created = itemCatalog.idx[name], false
        if not it then it = newItem(name, kind, true) created = true end
        it.drops = it.drops + 1
        it.qty = it.qty + qty
        it.last_seen = nowStamp()
        if unit and unit ~= '' then it.unit = unit end
        if duration and duration ~= '' then
            local var
            for _, x in ipairs(it.variants) do
                if x.duration == duration then var = x break end
            end
            if not var then
                var = {duration = duration, hours = durationHours(duration), drops = 0, qty = 0}
                it.variants[#it.variants + 1] = var
            end
            var.drops = var.drops + 1
            var.qty = var.qty + qty
        end
        mark('items')
        return it, created
    end

    Catalog.currentTier = currentTier
    Catalog.isWorkModel = isWorkModel
    Catalog.currentVehicleModel = currentVehicleModel
    Catalog.loadCatalogs = loadCatalogs
    Catalog.touchVehicle = touchVehicle
    Catalog.touchPack = touchPack
    Catalog.touchItem = touchItem
end

local function bumpHour(field, amount)
    local hour = tostring(tonumber(os.date('%H')))
    local day = dayRec(todayKey())
    local record = day.hours[hour]
    if not record then record = {m = 0, t = 0, c = 0} day.hours[hour] = record end
    record[field] = (record[field] or 0) + amount
end

local function journal(kind, text, value)
    pushLimited(history.journal, {t = os.date('%H:%M:%S'), d = todayKey(), k = kind, text = text, v = value or 0}, 200)
end

local function addIncome(kind, amount, extra)
    if not amount or amount <= 0 then return end
    touchWork()
    local st = stats[kind]
    st.total = st.total + amount
    st.count = st.count + 1
    st.last = amount

    local e = {t = os.date('%H:%M:%S'), d = os.date('%d.%m'), v = amount}
    if extra then
        e.name = extra.name
        if extra.drivers and extra.drivers > 0 then e.n = extra.drivers end
    end
    pushLimited(history[kind], e, 50)
    pushLimited(history.recent, {v = amount, k = kind}, 30)
    bumpHour('m', amount)
    local label = e.name or (kind == 'truck' and '\208\160\208\181\208\185\209\129' or (kind == 'car' and '\208\145\208\190\208\189\209\131\209\129 \209\130/\209\129' or '\208\159\209\128\208\190\209\135\208\181\208\181'))
    if e.n then label = label .. ' (\208\178\208\190\208\180\208\184\209\130\208\181\208\187\208\181\208\185: ' .. e.n .. ')' end
    journal(kind, label, amount)

    local day = dayRec(todayKey())
    day.money = day.money + amount
    day[kind] = day[kind] + amount

    session.money = session.money + amount
    session[kind] = session[kind] + amount
    session.jobs = session.jobs + 1
    session.log[#session.log + 1] = {time = os.time(), amount = amount}
    while #session.log > 0 and session.log[1].time < os.time() - HOURLY_WINDOW - 60 do table.remove(session.log, 1) end

    setFlash(kind, '+' .. fmt(amount) .. ' \209\128\209\131\208\177.')
    checkGoal()
    mark('stats', 'history')
    if Hooks.onIncome then Hooks.onIncome(kind, amount) end
end

local EXPENSE_LABEL = {fuel = '\209\130\208\190\208\191\208\187\208\184\208\178\208\190', repair = '\209\128\208\181\208\188\208\190\208\189\209\130', fine = '\209\136\209\130\209\128\208\176\209\132'}

local function addExpense(kind, amount, text)
    local st = stats.expenses
    st[kind] = (st[kind] or 0) + amount
    st.total = st.total + amount
    st.count = st.count + 1
    pushLimited(history.expenses, {t = os.date('%H:%M:%S'), d = os.date('%d.%m'), v = amount, kind = kind, text = text}, 50)
    dayRec(todayKey()).expense = dayRec(todayKey()).expense + amount
    session.expense = session.expense + amount
    session.expenseLog[#session.expenseLog + 1] = {time = os.time(), amount = amount}
    while #session.expenseLog > 0 and session.expenseLog[1].time < os.time() - HOURLY_WINDOW - 60 do
        table.remove(session.expenseLog, 1)
    end
    journal('expense', EXPENSE_LABEL[kind] or kind, amount)
    notify('\208\160\208\176\209\129\209\133\208\190\208\180 (' .. (EXPENSE_LABEL[kind] or kind) .. '): -' .. fmt(amount) .. ' \209\128\209\131\208\177.')
    mark('stats', 'history')
end

local function addChestDrop(name, qty)
    local it, created = Catalog.touchItem(name, 'chest', qty)
    if it.tracked and cfg.track.chests then
        stats.chests.total = stats.chests.total + qty
        stats.chests.drops = stats.chests.drops + 1
        stats.chests.last = nowStamp()
        pushLimited(history.chests, {t = os.date('%H:%M:%S'), d = os.date('%d.%m'), name = it.name, q = qty}, 50)
        dayRec(todayKey()).chests = dayRec(todayKey()).chests + qty
        session.chests = session.chests + qty
        bumpHour('c', qty)
        journal('chest', it.name .. ' x' .. qty, qty)
        setFlash('chests', '+' .. qty .. ' \209\136\209\130. ' .. it.name)
        notify('\208\155\208\176\209\128\208\181\209\134: ' .. it.name .. ' x' .. qty .. ' (\208\178\209\129\208\181\208\179\208\190: ' .. stats.chests.total .. ')')
        mark('stats', 'history')
    elseif created then
        notify('\208\157\208\190\208\178\209\139\208\185 \208\187\208\176\209\128\208\181\209\134 \208\183\208\176\208\191\208\190\208\188\208\189\208\181\208\189: ' .. it.name .. ' (\208\178 \208\190\208\177\209\137\208\184\208\185 \209\129\209\135\209\145\209\130 \208\189\208\181 \208\178\209\133\208\190\208\180\208\184\209\130 - \208\178\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\178\208\190 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 "\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139")')
    end
end

local function isEternalText(text)
    return lowerRu(text or ''):find('\208\178\208\181\209\135\208\189', 1, true) ~= nil
end

local function addBonusItem(name, qty, unit, duration)
    local it, created = Catalog.touchItem(name, 'contract', qty, unit, duration)
    if it.tracked and cfg.track.items then
        local eternal = isEternalText(duration) or isEternalText(name)
        stats.items.total = stats.items.total + qty
        stats.items.drops = stats.items.drops + 1
        stats.items.last = nowStamp()
        local day = dayRec(todayKey())
        day.items = day.items + qty
        session.items = session.items + qty
        if eternal then
            stats.eternal.total = stats.eternal.total + qty
            stats.eternal.drops = stats.eternal.drops + 1
            stats.eternal.last = nowStamp()
            day.eternal = day.eternal + qty
            session.eternal = (session.eternal or 0) + qty
        end
        pushLimited(history.items, {t = os.date('%H:%M:%S'), d = os.date('%d.%m'), name = it.name, q = qty, dur = duration or '', e = eternal}, 50)
        local kindText = eternal and '\208\178\208\181\209\135\208\189\209\139\208\185' or '\208\178\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\185'
        journal('item', '\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180 (' .. kindText .. ') x' .. qty, qty)
        setFlash('items', '+' .. qty .. ' \209\136\209\130. (' .. kindText .. ')')
        notify('\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180 (' .. kindText .. '): ' .. it.name .. ' +' .. qty .. ' \209\136\209\130., \208\178\209\129\208\181\208\179\208\190 \208\178\208\181\209\135\208\189\209\139\209\133: ' .. stats.eternal.total ..
            ', \208\178\209\128\208\181\208\188\208\181\208\189\208\189\209\139\209\133: ' .. (stats.items.total - stats.eternal.total))
        mark('stats', 'history')
    end
    if created then notify('\208\157\208\190\208\178\209\139\208\185 \208\191\209\128\208\181\208\180\208\188\208\181\209\130 \208\183\208\176\208\191\208\190\208\188\208\189\208\181\208\189: ' .. it.name) end
end

local Ledger = {}
do
    local IGNORE_REASON_TEXT = {
        admin = '\208\178\209\139\208\180\208\176\209\135\208\176 \208\176\208\180\208\188\208\184\208\189\208\190\208\188', transfer = '\208\191\208\181\209\128\208\181\208\178\208\190\208\180 \208\190\209\130 \208\184\208\179\209\128\208\190\208\186\208\176',
        sale = '\208\191\209\128\208\190\208\180\208\176\208\182\208\176 / \208\191\208\190\208\186\209\131\208\191\208\186\208\176', unknown = '\208\189\208\181 \209\129\208\178\209\143\208\183\208\176\208\189\208\190 \209\129 \209\128\208\176\208\177\208\190\209\130\208\190\208\185',
    }

    local MONEY_NOTE_RULES = {
        {reason = 'admin',    words = {'\208\178\209\139\208\180\208\176\208\187', '\208\178\209\139\208\180\208\176\208\189', '\208\176\208\180\208\188\208\184\208\189\208\184\209\129\209\130\209\128\208\176\209\130\208\190\209\128'}},
        {reason = 'transfer', words = {'\208\191\208\181\209\128\208\181\208\178\208\181\208\187', '\208\191\208\181\209\128\208\181\208\178\209\145\208\187', '\208\191\208\181\209\128\208\181\208\178\208\181\208\187\208\184', '\208\191\208\181\209\128\208\181\208\180\208\176\208\187', '\208\190\209\130\208\191\209\128\208\176\208\178\208\184\208\187 \208\178\208\176\208\188', '\208\191\208\190\208\187\209\131\209\135\208\184\208\187\208\184 \208\190\209\130'}},
        {reason = 'sale',     words = {'\208\191\209\128\208\190\208\180\208\176\208\187', '\208\191\209\128\208\190\208\180\208\176\208\187\208\184', '\208\186\209\131\208\191\208\184\208\187', '\208\186\209\131\208\191\208\187\208\181\208\189'}},
    }

    local gain_log = {}
    local lastJobTime = -1000
    local SILENT_JOB_WINDOW = 120
    local SILENT_MAX_AMOUNT = 3000000

    local function markJobActivity(now) lastJobTime = now touchWork() end

    local function drainQueue(queue, amount, maxAge, now)
        local i = 1
        while i <= #queue and amount > 0 do
            local entry = queue[i]
            if now - entry.time > maxAge then
                table.remove(queue, i)
            else
                local taken = math.min(entry.amount, amount)
                entry.amount = entry.amount - taken
                amount = amount - taken
                if entry.amount <= 0.5 then table.remove(queue, i) else i = i + 1 end
            end
        end
        return amount
    end

    local function onJobIncome(amount, now)
        lastJobTime = now
        local rest = drainQueue(unclaimed_gains, amount, 30, now)
        if rest > 0.5 then job_credits[#job_credits + 1] = {amount = rest, time = now} end
    end

    local function onBalanceGain(delta, now)
        local rest = drainQueue(job_credits, delta, 15, now)
        if rest > 0.5 then unclaimed_gains[#unclaimed_gains + 1] = {amount = rest, time = now} end
    end

    local function applyBalance(newValue)
        if balance == nil then balance = newValue return end
        local delta = newValue - balance
        balance = newValue
        if delta > 0 then
            local t = os.clock()
            gain_log[#gain_log + 1] = {time = t, delta = delta}
            while #gain_log > 0 and gain_log[1].time < t - 180 do table.remove(gain_log, 1) end
            onBalanceGain(delta, t)
        end
    end

    function Ledger.gainSince(since)
        local sum = 0
        for i = #gain_log, 1, -1 do
            if gain_log[i].time < since then break end
            sum = sum + gain_log[i].delta
        end
        return sum
    end

    local function noteMoneyMessage(text, now)
        if not text:find('\209\128\209\131\208\177', 1, true) then return end
        local lower = lowerRu(text)
        for _, rule in ipairs(MONEY_NOTE_RULES) do
            for _, word in ipairs(rule.words) do
                if lower:find(word, 1, true) then
                    money_notes[#money_notes + 1] = {reason = rule.reason, time = now}
                    return
                end
            end
        end
    end

    local function classifyGain(gainTime)
        for i = #money_notes, 1, -1 do
            if math.abs(money_notes[i].time - gainTime) <= 3 then return money_notes[i].reason end
        end
        return 'unknown'
    end

    local function isSilentJobIncome(amount, reason, gainTime)
        if reason ~= 'unknown' or not cfg.track.other then return false end
        if amount < cfg.other_min or (cfg.other_max > 0 and amount > cfg.other_max) then return false end
        if cfg.track.unknown then return true end
        if not cfg.track.silent or amount > SILENT_MAX_AMOUNT then return false end
        return gainTime - lastJobTime <= SILENT_JOB_WINDOW or Catalog.isWorkModel(Catalog.currentVehicleModel())
    end

    local function registerUnexplainedGain(amount, reason, gainTime)
        if reason == 'unknown' and Ledger.consumeOrderPayout then
            local customer = Ledger.consumeOrderPayout(amount)
            if customer then
                addIncome('truck', amount, {name = '\208\151\208\176\208\186\208\176\208\183: ' .. customer})
                notify('\208\146\209\139\208\191\208\187\208\176\209\130\208\176 \208\183\208\176 \208\183\208\176\208\186\208\176\208\183: +' .. fmt(amount) .. ' \209\128\209\131\208\177. (' .. customer .. ')')
                return
            end
        end
        if reason == 'unknown' and amount <= SILENT_MAX_AMOUNT and Ledger.consumeSalary then
            local percent = Ledger.consumeSalary(amount, gainTime)
            if percent then
                if cfg.track.other and cfg.track.salary then
                    addIncome('other', amount, {name = '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176 (+' .. string.format('%g', percent) .. '%)'})
                    notify('\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176: +' .. fmt(amount) .. ' \209\128\209\131\208\177. (\208\177\208\190\208\189\209\131\209\129 \208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186\208\176 ' .. string.format('%g', percent) .. '%)')
                end
                return
            end
        end
        if isSilentJobIncome(amount, reason, gainTime) then
            addIncome('other', amount, {name = '\208\145\208\181\208\183 \209\129\208\190\208\190\208\177\209\137\208\181\208\189\208\184\209\143 (\208\178 \209\128\208\176\208\177\208\190\209\130\208\181)'})
            notify('\208\159\208\190\209\129\209\130\209\131\208\191\208\187\208\181\208\189\208\184\208\181 \208\177\208\181\208\183 \209\129\208\190\208\190\208\177\209\137\208\181\208\189\208\184\209\143 \208\183\208\176\209\129\209\135\208\184\209\130\208\176\208\189\208\190: +' .. fmt(amount) .. ' \209\128\209\131\208\177.')
            return
        end
        stats.ignored.total = stats.ignored.total + amount
        stats.ignored.count = stats.ignored.count + 1
        pushLimited(history.ignored, {t = os.date('%H:%M:%S'), d = os.date('%d.%m'), v = amount, why = reason}, 30)
        mark('stats', 'history')
        notify('\208\157\208\181 \208\180\208\190\209\133\208\190\208\180: +' .. fmt(amount) .. ' \209\128\209\131\208\177. (' .. (IGNORE_REASON_TEXT[reason] or '?') .. ') - \208\178 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\209\131 \208\189\208\181 \208\178\208\186\208\187\209\142\209\135\208\181\208\189\208\190')
    end

    local function settleUnclaimedGains(now)
        local i = 1
        while i <= #unclaimed_gains do
            local gain = unclaimed_gains[i]
            if now - gain.time >= 3 then
                table.remove(unclaimed_gains, i)
                registerUnexplainedGain(gain.amount, classifyGain(gain.time), gain.time)
            else
                i = i + 1
            end
        end
        for _, list in ipairs({job_credits, money_notes}) do
            local j = 1
            while j <= #list do
                if now - list[j].time > 30 then table.remove(list, j) else j = j + 1 end
            end
        end

        if pending_reset and now - pending_reset.time >= 1.5 then
            balance = 0
            pending_reset = nil
        end
    end

    local function onFirstMoneyEvent()
        if not money_events_seen then
            money_events_seen = true
            balance = nil
        end
    end

    function sampev.onSetPlayerMoney(money)
        if not cfg.enabled then return end
        onFirstMoneyEvent()
        pending_reset = nil
        applyBalance(money)
    end

    function sampev.onResetPlayerMoney()
        if not cfg.enabled then return end
        onFirstMoneyEvent()
        pending_reset = {time = os.clock(), before = balance}
    end

    function sampev.onGivePlayerMoney(money)
        if not cfg.enabled then return end
        onFirstMoneyEvent()
        if pending_reset and os.clock() - pending_reset.time < 1.5 then

            balance = pending_reset.before
            pending_reset = nil
            applyBalance(money)
        elseif balance ~= nil then
            applyBalance(balance + money)
        end
    end

    Ledger.IGNORE_REASON_TEXT = IGNORE_REASON_TEXT
    Ledger.markJobActivity = markJobActivity
    Ledger.onJobIncome = onJobIncome
    Ledger.noteMoneyMessage = noteMoneyMessage
    Ledger.applyBalance = applyBalance
    Ledger.settleUnclaimedGains = settleUnclaimedGains

    function Ledger.resetBaseline()
        balance = nil
        pending_reset = nil
        unclaimed_gains = {}
        job_credits = {}
        money_notes = {}
    end
end

local money_fn_idx = nil
local function readMoney()
    local fns = {
        function() return getPlayerMoney(PLAYER_HANDLE) end,
        function() return storeScore(PLAYER_HANDLE) end,
        function() return getPlayerMoney() end,
    }
    if money_fn_idx then
        local ok, m = pcall(fns[money_fn_idx])
        if ok and type(m) == 'number' then return m end
        money_fn_idx = nil
    end
    for i, fn in ipairs(fns) do
        local ok, m = pcall(fn)
        if ok and type(m) == 'number' then money_fn_idx = i return m end
    end
    return nil
end

local function looksLikePlayerChat(text)
    if text:find('^[%w_%.%-]+%s*%[%d+%]') then return true end
    if text:find('^%u[%w%.%-]*_%u[%w%.%-]*%s*:') then return true end
    return false
end

local function parseInt(s)
    return tonumber((tostring(s):gsub('%D', ''))) or 0
end

local function parseBonus(s)
    s = s:gsub('%s', '')
    if cfg.bonus_dot_thousands then s = s:gsub('%.', '') end
    return tonumber(s) or 0
end

local function extractQty(s)
    local n = s:match('[xX]%s*(%d+)')
        or s:match('\209\133%s*(%d+)')
        or s:match('\208\165%s*(%d+)')
        or s:match('(%d+)%s*[xX]%f[%W]')
        or s:match('(%d+)%s*\209\133%s')
        or s:match('(%d+)%s*\209\133$')
        or s:match('\208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178%S*%s*[:%-]?%s*(%d+)')
        or s:match('(%d+)%s*\209\136\209\130')
        or s:match('%((%d+)%)')
        or s:match('^%s*(%d+)%s')
    n = tonumber(n)
    if n and n >= 1 then return math.floor(n) end
    return 1
end

local function handlePack(text, now)
    local pack, vehicle, _, amt = text:match('^\208\151\208\176 \209\131\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\189\209\139\208\185%s+(.-)%s+\208\186%s+(.-)%s+\208\146\209\139 \208\191\208\190\208\187\209\131\209\135\208\176\208\181\209\130\208\181%s+(%S+)%s+(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    local bonus = amt and parseBonus(amt) or 0
    if not pack or bonus <= 0 then return end

    Ledger.onJobIncome(bonus, now)
    local veh, created = Catalog.touchPack(vehicle, pack, bonus)
    if created then notify('\208\157\208\190\208\178\208\176\209\143 \208\188\208\176\209\136\208\184\208\189\208\176 \208\183\208\176\208\191\208\190\208\188\208\189\208\181\208\189\208\176: ' .. veh.name) end
    if cfg.track.pack then
        addIncome('car', bonus, {name = pack .. ' (' .. veh.name .. ')'})
        notify('\208\162\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186 (' .. veh.name .. '): +' .. fmt(bonus) .. ' \209\128\209\131\208\177.')
    end
end

local function handleTruck(text, now)
    local m = text:match('\208\146\209\139 \208\191\208\190\208\187\209\131\209\135\208\184\208\187\208\184%s+(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    local d = text:match('\209\128\208\176\208\177\208\190\209\130\209\131%s+(%d+)%s+\208\189\208\176\208\189\209\143\209\130')
    local money = m and parseInt(m) or 0
    if money <= 0 then return end
    Ledger.onJobIncome(money, now)
    if cfg.track.truck then
        addIncome('truck', money, {drivers = tonumber(d) or 0})
        notify('\208\160\208\181\208\185\209\129: +' .. fmt(money) .. ' \209\128\209\131\208\177.' .. (d and (' (\208\178\208\190\208\180\208\184\209\130\208\181\208\187\208\181\208\185: ' .. d .. ')') or ''))
    end
end

local function handleVehicleBonus(text, now)
    local name, _, amt = text:match('^\208\151\208\176 \209\128\208\176\208\177\208\190\209\130\209\131 \208\189\208\176%s+(.-)%s+\208\146\209\139 \208\191\208\190\208\187\209\131\209\135\208\176\208\181\209\130\208\181%s+(%S+)%s+(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    local bonus = amt and parseBonus(amt) or 0
    if not name or bonus <= 0 then return end

    Ledger.onJobIncome(bonus, now)
    if name:find('\208\187\208\184\209\135\208\189\208\190\208\188', 1, true) then name = '\208\155\208\184\209\135\208\189\209\139\208\185 \209\130/\209\129' end
    local veh, created = Catalog.touchVehicle(name, bonus)
    if created then notify('\208\157\208\190\208\178\208\176\209\143 \208\188\208\176\209\136\208\184\208\189\208\176 \208\183\208\176\208\191\208\190\208\188\208\189\208\181\208\189\208\176: ' .. veh.name) end
    if cfg.track.car then
        addIncome('car', bonus, {name = veh.name})
        notify('\208\145\208\190\208\189\209\131\209\129 (' .. veh.name .. '): +' .. fmt(bonus) .. ' \209\128\209\131\208\177.')
    end
end

local function handleBonusItem(text, now)
    local body = text:match('^%[\208\145\208\190\208\189\209\131\209\129%]%s*\208\146\209\139 \208\191\208\190\208\187\209\131\209\135\208\184\208\187\208\184%s+(.+)$')
    if not body then return end

    local moneyText = body:match('^(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    if moneyText then
        local amount = parseBonus(moneyText)
        if amount > 0 then
            Ledger.onJobIncome(amount, now)
            if cfg.track.other then
                addIncome('other', amount, {name = '\208\145\208\190\208\189\209\131\209\129'})
                notify('\208\145\208\190\208\189\209\131\209\129: +' .. fmt(amount) .. ' \209\128\209\131\208\177.')
            end
            return
        end
    end

    local name, rest = body:match('^(.-)%s+\208\178 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\181%s+(.+)$')
    local qty, unit, duration = 1, '', ''
    if name then
        local qtyText, after = rest:match('^[%+x]?%s*(%d+)%s*(.*)$')
        if not qtyText then return end
        qty = tonumber(qtyText) or 1
        unit = trim(after:match('^([^%.%-%(]*)') or '')
        duration = after:match('%((.-)%)') or after:match('%-%s*(.+)$') or ''
    else

        local head, tail = body:match('^(.-)%s*%((.-)%)%s*$')
        if not head then head, tail = body:match('^(.-)%.?%s+%-%s+(.+)$') end
        if head then name, duration = head, tail else name = body end
    end
    name = trim((name:gsub('%.%s*$', '')))
    duration = trim(duration)
    if name == '' then return end
    if not lowerRu(name):find('\208\180\208\184\208\178\208\184\208\180\208\181\208\189', 1, true) then return end
    Ledger.markJobActivity(now)
    addBonusItem(name, qty, unit, duration)
end
local function handleInventory(text)
    local seg = trim(text:match('^\208\148\208\190\208\177\208\176\208\178\208\187\208\181\208\189\208\190 \208\178 \208\184\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140:?%s*(.*)$') or '')
    seg = trim((seg:gsub('%.?%s*\208\167\209\130\208\190\208\177\209\139 \208\190\209\130\208\186\209\128\209\139\209\130\209\140 \208\184\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140.*$', '')))

    if not (seg:find('\208\176\209\128\208\181\209\134', 1, true) or seg:find('\208\176\209\128\209\134', 1, true)) then return end
    if not lowerRu(seg):find('\208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185', 1, true) then return end

    Ledger.markJobActivity(os.clock())
    local name = seg:match('"(.-)"') or seg:match('\194\171(.-)\194\187')
    local outside = seg:gsub('".-"', ''):gsub('\194\171.-\194\187', '')
    local qty = extractQty(outside)
    if not name or name == '' then
        name = trim((outside:gsub('%b()', ''):gsub('[xX]%s*%d+', ''):gsub('\209\133%s*%d+', ''):gsub('\208\165%s*%d+', ''):gsub('%d+%s*\209\136\209\130%.?', '')))
        if name == '' then name = '\208\155\208\176\209\128\208\181\209\134' end
    end
    addChestDrop(name, qty)
end

local function parseLeftSeconds(text)
    local days = tonumber(text:match('(%d+)%s*\208\180\208\189')) or 0
    local hours = tonumber(text:match('(%d+)%s*\209\135')) or 0
    local minutes = tonumber(text:match('(%d+)%s*\208\188\208\184\208\189')) or 0
    return days * 86400 + hours * 3600 + minutes * 60
end

local promoContext = nil

local function handlePromo(text, now)
    if not cfg.track.promo then return end
    local promo = stats.promo
    local job, percent = text:match('\208\157\208\176 \209\128\208\176\208\177\208\190\209\130\208\181 "(.-)" \208\180\208\181\208\185\209\129\209\130\208\178\209\131\208\181\209\130 \208\176\208\186\209\134\208\184\209\143 %+(%d+[%.,]?%d*)%%')
    if not job then job, percent = text:match('\208\157\208\176 \209\128\208\176\208\177\208\190\209\130\208\181 \194\171(.-)\194\187 \208\180\208\181\208\185\209\129\209\130\208\178\209\131\208\181\209\130 \208\176\208\186\209\134\208\184\209\143 %+(%d+[%.,]?%d*)%%') end
    if not job then job, percent = text:match('\208\177\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181:%s*"(.-)"%s*%+(%d+[%.,]?%d*)%%') end
    if not job then job, percent = text:match('\208\177\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181:%s*\194\171(.-)\194\187%s*%+(%d+[%.,]?%d*)%%') end
    if job then
        promoContext = job
        if not job:find('\208\148\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186', 1, true) then return end
        promo.job = job
        promo.percent = tonumber((percent:gsub(',', '.'))) or 0
        local left = parseLeftSeconds(text:match('\208\148\208\190 \208\183\208\176\208\178\208\181\209\128\209\136\208\181\208\189\208\184\209\143:(.*)$') or '')
        if left > 0 then promo.endsAt = os.time() + left end
        mark('stats')
        return
    end
    local rest = text:match('\208\191\209\128\208\190\208\180\208\187\208\184\209\130\209\129\209\143(.*)$')
    if rest then
        if promoContext and not promoContext:find('\208\148\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186', 1, true) then return end
        local left = parseLeftSeconds(rest)
        if left > 0 then
            promo.endsAt = os.time() + left
            mark('stats')
        end
        return
    end
    local amountText = text:match('\208\191\208\190\208\187\209\131\209\135\208\184\208\187\208\184%s+%+?(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    local amount = amountText and parseBonus(amountText) or 0
    if amount > 0 then
        Ledger.markJobActivity(now)
        Ledger.onJobIncome(amount, now)
        promo.paid = promo.paid + amount
        promo.count = promo.count + 1
        if cfg.track.other then
            addIncome('other', amount, {name = '\208\144\208\186\209\134\208\184\209\143' .. (promo.percent > 0 and (' +' .. string.format('%g', promo.percent) .. '%') or '')})
            notify('\208\144\208\186\209\134\208\184\209\143 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133: +' .. fmt(amount) .. ' \209\128\209\131\208\177.')
        end
        mark('stats')
    end
end

local salaryHint = nil
local recentSalary = nil
local SALARY_HINT_WINDOW = 30

local function accountSalaryBonus(amount, percent)
    local extra = math.floor(amount * percent / (100 + percent))
    local salary = stats.salary
    salary.paid = salary.paid + amount
    salary.extra = salary.extra + extra
    mark('stats')
    return extra
end

local function noteSalaryPaid(amount, now)
    local hint = salaryHint
    if hint and not hint.used and now - hint.time <= SALARY_HINT_WINDOW then
        hint.used = true
        return accountSalaryBonus(amount, hint.percent), hint.percent
    end
    recentSalary = {time = now, amount = amount}
    return nil
end

local function handleSalaryHint(text, now)
    local raw = text:match('^%[\208\159\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\176%]%s*\208\146\208\176\209\136\208\176 \209\128\208\176\208\177\208\190\209\135\208\176\209\143 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \209\131\208\178\208\181\208\187\208\184\209\135\208\181\208\189\208\176 \208\189\208\176%s+(%d+[%.,]?%d*)%s*%%')
    if not raw or not cfg.track.salaryHint then return end
    local percent = tonumber((raw:gsub(',', '.'))) or 0
    if percent <= 0 then return end
    local salary = stats.salary
    salary.percent, salary.last, salary.count = percent, nowStamp(), salary.count + 1
    local label = string.format('%g', percent)
    local reasonText = trim(text:match('\208\191\208\190\209\129\208\186\208\190\208\187\209\140\208\186\209\131%s+(.-)%.?%s*$') or '')
    local bodyguard = lowerRu(reasonText ~= '' and reasonText or text):find('\208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186', 1, true) ~= nil
    salary.other = not bodyguard
    salary.reason = reasonText
    local who = bodyguard and '\208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186' or (reasonText ~= '' and reasonText or '\208\191\209\128\208\184\209\135\208\184\208\189\208\176 \208\189\208\181 \209\131\208\186\208\176\208\183\208\176\208\189\208\176')
    journal('info', '\208\145\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181 +' .. label .. '% (' .. who .. ')', 0)
    notify('\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \209\131\208\178\208\181\208\187\208\184\209\135\208\181\208\189\208\176 \208\189\208\176 ' .. label .. '% (' .. who .. ')')
    local hint = {time = now, percent = percent}
    salaryHint = hint
    local recent = recentSalary
    if recent and now - recent.time <= 15 then
        hint.used = true
        recentSalary = nil
        accountSalaryBonus(recent.amount, percent)
    end
    mark('stats', 'history')
end

local function handleSalaryPenalty(text, now)
    if not cfg.track.salaryHint then return false end
    local raw = text:match('\208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133 \209\129\208\189\208\184\208\182\208\181\208\189\208\176 \208\189\208\176%s+(%d+[%.,]?%d*)%s*%%')
    if not raw then return false end
    local percent = tonumber((raw:gsub(',', '.'))) or 0
    if percent <= 0 then return false end
    local label = string.format('%g', percent)
    local reason = text:find('\208\182\208\184\208\187\208\190\208\179\208\190 \208\184\208\188\209\131\209\137\208\181\209\129\209\130\208\178\208\176', 1, true) and '\208\189\208\181\209\130 \208\182\208\184\208\187\209\140\209\143' or '\209\136\209\130\209\128\208\176\209\132'
    stats.salary.penalty, stats.salary.penaltyAt, stats.salary.penaltyReason = percent, nowStamp(), reason
    journal('info', '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \209\129\208\189\208\184\208\182\208\181\208\189\208\176 \208\189\208\176 ' .. label .. '% (' .. reason .. ')', 0)
    notify('\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \209\129\208\189\208\184\208\182\208\181\208\189\208\176 \208\189\208\176 ' .. label .. '% (' .. reason .. ')')
    mark('stats', 'history')
    return true
end

Ledger.consumeSalary = function(amount, now)
    local hint = salaryHint
    if not (hint and not hint.used and now - hint.time <= SALARY_HINT_WINDOW) then return nil end
    hint.used = true
    accountSalaryBonus(amount, hint.percent)
    return hint.percent
end

local function handleSalary(text, now)
    local lower = lowerRu(text)
    if not lower:find('\208\183\208\176\209\128\208\191\208\187\208\176\209\130', 1, true) then return false end
    if not (lower:find('\208\191\208\190\208\187\209\131\209\135', 1, true) or lower:find('\208\189\208\176\209\135\208\184\209\129\208\187', 1, true) or lower:find('\208\178\209\139\208\191\208\187\208\176\209\135', 1, true)) then return false end
    local amountText = text:match('(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    local amount = amountText and parseInt(amountText) or 0
    if amount <= 0 then return false end

    Ledger.onJobIncome(amount, now)
    local extra, percent = noteSalaryPaid(amount, now)
    if cfg.track.other and cfg.track.salary then
        addIncome('other', amount, {name = '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176'})
        notify('\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176: +' .. fmt(amount) .. ' \209\128\209\131\208\177.' .. (extra and (' (\208\184\208\183 \208\189\208\184\209\133 \208\177\208\190\208\189\209\131\209\129 \208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186\208\176 ' .. string.format('%g', percent) .. '%: +' .. fmt(extra) .. ' \209\128\209\131\208\177.)') or ''))
    end
    return true
end

local function handleIdle(text)
    local seconds = tonumber(text:match('^\208\146\209\139 \208\191\209\128\208\190\209\129\209\130\208\190\209\143\208\187\208\184 \208\178 AFK (%d+) \209\129\208\181\208\186'))
    if not seconds then return false end
    session.idle = session.idle + seconds
    return true
end

local EXPENSE_KINDS = {
    {kind = 'fuel',   words = {'\208\183\208\176\208\191\209\128\208\176\208\178', '\209\130\208\190\208\191\208\187\208\184\208\178', '\208\177\208\181\208\189\208\183\208\184\208\189'}},
    {kind = 'repair', words = {'\209\128\208\181\208\188\208\190\208\189\209\130', '\208\191\208\190\209\135\208\184\208\189\208\186', '\208\190\209\130\209\128\208\181\208\188\208\190\208\189\209\130\208\184\209\128'}},
    {kind = 'fine',   words = {'\209\136\209\130\209\128\208\176\209\132'}},
}
local SPEND_WORDS = {'\208\191\208\190\209\130\209\128\208\176\209\130\208\184\208\187', '\208\191\208\190\209\130\209\128\208\176\209\135\208\181\208\189', '\208\190\208\191\208\187\208\176\209\130\208\184\208\187', '\208\190\208\191\208\187\208\176\209\135\208\181\208\189', '\209\129\208\191\208\184\209\129\208\176\208\189', '\208\183\208\176\208\191\208\187\208\176\209\130\208\184\208\187', '\208\190\208\177\208\190\209\136\208\187', '\208\190\208\177\208\190\209\136\208\181\208\187', '\208\190\208\177\208\190\209\136\209\145\208\187', '\209\129\209\130\208\190\208\184\208\188\208\190\209\129\209\130', '\209\129\208\189\209\143\209\130\208\190', '\208\178\209\139\209\135\209\130\208\181\208\189', '\209\129 \208\178\208\176\209\129'}

local function handleExpense(text, now)
    if not cfg.track.expenses then return false end
    local lower = lowerRu(text)
    if not lower:find('\209\128\209\131\208\177', 1, true) then return false end
    local kind
    for _, rule in ipairs(EXPENSE_KINDS) do
        for _, word in ipairs(rule.words) do
            if lower:find(word, 1, true) then kind = rule.kind break end
        end
        if kind then break end
    end
    if not kind then return false end
    local spends = false
    for _, word in ipairs(SPEND_WORDS) do
        if lower:find(word, 1, true) then spends = true break end
    end
    local amountText = text:match('(%d[%d%.%s]*)%s*\209\128\209\131\208\177')
    local amount = amountText and parseInt(amountText) or 0
    if not spends or amount <= 0 then return false end
    addExpense(kind, amount, text)
    return true
end

local function normalizeText(t)
    t = t:gsub('{%x%x%x%x%x%x}', '')
    t = t:gsub('\194\160', ' ')
    t = t:gsub('\226\128[\147\148]', '-')
    return trim(t)
end

local lastWorkLineAt = -1000

local function handleChat(raw)
    local text = normalizeText(raw)
    if text == '' or looksLikePlayerChat(text) then return end
    local now = os.clock()
    if text:find('^%[TRUCK%]') or text:find('^\208\151\208\176%s') or text:find('^%[\208\145\208\190\208\189\209\131\209\129%]') or text:find('^%[\208\159\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\176%]')
        or text:find('^%[\208\144\208\186\209\134\208\184\209\143') or text:find('^%[\208\152\208\189\209\132\208\190\209\128\208\188\208\176\209\134\208\184\209\143%]') then
        lastWorkLineAt = now
    end

    if text:find('^%[TRUCK%]') then
        Ledger.markJobActivity(now)
        if text:find('\208\146\209\139 \208\191\208\190\208\187\209\131\209\135\208\184\208\187\208\184', 1, true) then handleTruck(text, now) end
        return
    end
    if text:find('^\208\151\208\176 \209\131\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\189\209\139\208\185') then Ledger.markJobActivity(now) handlePack(text, now) return end
    if text:find('^\208\151\208\176 \209\128\208\176\208\177\208\190\209\130\209\131 \208\189\208\176') then Ledger.markJobActivity(now) handleVehicleBonus(text, now) return end
    if text:find('^%[\208\145\208\190\208\189\209\131\209\129%]') then handleBonusItem(text, now) return end
    if text:find('^%[\208\159\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\176%]') then handleSalaryHint(text, now) return end
    if text:find('^%[\208\144\208\186\209\134\208\184\209\143 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133%]') then handlePromo(text, now) return end
    if text:find('^%[\208\152\208\189\209\132\208\190\209\128\208\188\208\176\209\134\208\184\209\143%]') and handleSalaryPenalty(text, now) then return end
    if text:find('^\208\148\208\190\208\177\208\176\208\178\208\187\208\181\208\189\208\190 \208\178 \208\184\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140') then handleInventory(text) return end
    if handleIdle(text) then return end
    if handleSalary(text, now) or handleExpense(text, now) then return end
    Ledger.noteMoneyMessage(text, now)
end

function sampev.onServerMessage(color, text)
    if not ENC_OK or not cfg.enabled then return end
    detectChatEncoding(text)
    pcall(handleChat, Charset.toUtf8(text))
end

if ENC_OK then Catalog.loadCatalogs() end

local function migrateOld()
    local chunk = loadfile(OLD_LUA_FILE)
    if not chunk then return false end
    pcall(setfenv, chunk, {})
    local ok, old = pcall(chunk)
    if not ok or type(old) ~= 'table' or type(old.cfg) ~= 'table' then return false end

    for k, v in pairs(old.cfg) do cfg[k] = v end
    applyDefaults(cfg, DEF_CFG)
    local os_ = type(old.stats) == 'table' and old.stats or {}
    for _, kind in ipairs({'truck', 'car', 'other'}) do
        local o = os_[kind]
        if type(o) == 'table' then
            stats[kind].total, stats[kind].count, stats[kind].last = o.total or 0, o.count or 0, o.last or 0
            history[kind] = type(o.history) == 'table' and o.history or {}
            for _, e in ipairs(history[kind]) do
                if e.x then
                    if kind == 'truck' and e.x > 0 then e.n = e.x end
                    e.x = nil
                end
            end
        end
    end
    if type(os_.chests) == 'table' then
        stats.chests.total = os_.chests.total or 0
        stats.chests.last = os_.chests.last or ''
        history.chests = type(os_.chests.history) == 'table' and os_.chests.history or {}
    end
    stats.days = type(os_.days) == 'table' and os_.days or {}
    stats.goal_day = os_.goal_day or ''
    history.recent = type(os_.recent) == 'table' and os_.recent or {}
    return true
end

local migrated = false
if ENC_OK and not had_settings and doesFileExist(OLD_LUA_FILE) then migrated = migrateOld() end
mark('settings', 'stats', 'history', 'vehicles', 'items')

local Orders = {}

do
    local state = {
        windowOpen = false,
        category = '',
        list = {},
        updatedAt = 0,
        lastPickAt = -100,
        pending = nil,
        demoUntil = 0,
        capturingKey = false,
        editing = false,
        editFirst = false,
        editRestore = nil,
        detectedCapacity = nil,
        pickedTotal = 0, pickedByScript = 0,
        hintPending = false,
        active = nil,
        lastPos = nil, lastOdoAt = 0,
        lastCounter = nil, lastTimer = nil,
        closedAt = -100,
        lastIncomeAt = -1000,
        cursorCef = false, cursorAt = -1000,
        pendingFinish = nil,
        mobile = rawget(_G, 'MONET_VERSION') ~= nil or NEOM,
    }
    Orders.state = state

    local function parseSeconds(text)
        local h, m, sec = text:match('^(%d+):(%d+):(%d+)')
        if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
        m, sec = text:match('^(%d+):(%d+)')
        if m then return tonumber(m) * 60 + tonumber(sec) end
        sec = text:match('^(%d+)%s*\209\129\208\181\208\186')
        if sec then return tonumber(sec) end
        m = text:match('^(%d+)%s*\208\188\208\184\208\189')
        if m then return tonumber(m) * 60 end
        return nil
    end

    local function parseOrder(raw, category, index, receivedAt)
        if type(raw) ~= 'table' or type(raw.items) ~= 'table' then return nil end
        local fields = {}
        for _, item in ipairs(raw.items) do
            if type(item) == 'table' and type(item.title) == 'string' then fields[item.title] = tostring(item.value or '') end
        end
        if not (fields['\208\159\209\128\208\181\208\188\208\184\209\143'] and fields['\208\160\208\176\209\129\209\129\209\130\208\190\209\143\208\189\208\184\208\181']) then return nil end

        local customer = fields['\208\151\208\176\208\186\208\176\208\183\209\135\208\184\208\186'] or '?'
        local urgent = customer:find('[\208\161\209\128\208\190\209\135\208\189\208\190]', 1, true) ~= nil
        local tier = tonumber(customer:match('%[Tier%s*(%d+)%]'))
        while true do
            local rest = customer:match('^%b[]%s*(.*)$')
            if not rest then break end
            customer = rest
        end

        local cargo, weight = (fields['\208\162\208\190\208\178\208\176\209\128'] or ''):match('^(.-)%s*%((%d+)%s*\208\186\208\179%)')
        local distanceText = ((fields['\208\160\208\176\209\129\209\129\209\130\208\190\209\143\208\189\208\184\208\181'] or ''):match('([%d%.,]+)') or ''):gsub(',', '.')
        local km = tonumber(distanceText)
        return {
            index = index, category = category, receivedAt = receivedAt,
            customer = trim(customer), urgent = urgent, tier = tier,
            cargo = cargo or (fields['\208\162\208\190\208\178\208\176\209\128'] or ''), weight = tonumber(weight) or 0,
            km = km or 0, timeBase = parseSeconds(fields['\208\146\209\128\208\181\208\188\209\143'] or '') or 0,
            payout = parseInt(fields['\208\159\209\128\208\181\208\188\208\184\209\143']), fragility = tonumber((fields['\208\165\209\128\209\131\208\191\208\186\208\190\209\129\209\130\209\140'] or ''):match('(%d+)')) or 0,
        }
    end

    local function appendOrders(list, category)
        local now = os.clock()
        for _, raw in ipairs(list) do
            local order = parseOrder(raw, category, #state.list, now)
            if order then state.list[#state.list + 1] = order end
        end
    end

    function Orders.evaluate(order, now)
        local o = cfg.orders
        local timeLeft = order.timeBase - (now - order.receivedAt)
        local driveSeconds = order.km / Orders.effectiveSpeed() * 3600
        if timeLeft < driveSeconds * 1.1 + 20 then return nil, '\208\189\208\181 \209\133\208\178\208\176\209\130\208\184\209\130 \208\178\209\128\208\181\208\188\208\181\208\189\208\184' end
        local capacity = o.capacity > 0 and o.capacity or state.detectedCapacity
        if capacity and capacity > 0 and order.weight > capacity then return nil, '\209\130\209\143\208\182\208\181\208\187\208\181\208\181 \208\179\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\209\145\208\188\208\189\208\190\209\129\209\130\208\184' end
        local myTier = Orders.myTier()
        if myTier > 0 and order.tier and order.tier > myTier then return nil, '\208\189\209\131\208\182\208\181\208\189 Tier ' .. order.tier .. ' (\209\131 \208\178\208\176\209\129 ' .. myTier .. ')' end
        if o.minPayout > 0 and order.payout < o.minPayout then return nil, '\208\188\208\176\208\187\208\181\208\189\209\140\208\186\208\176\209\143 \208\191\209\128\208\181\208\188\208\184\209\143' end

        local base = order.payout
        if o.mode ~= 'total' then base = order.payout / math.max(order.km, 0.1) end
        local penalty = 1 - (o.fragilityPenalty / 100) * (order.fragility / 100)
        return base * penalty
    end

    function Orders.effectiveSpeed()
        local o = cfg.orders
        local speeds = stats.orders.speeds
        if o.autoSpeed and #speeds >= 5 then
            local copy = {}
            for i, value in ipairs(speeds) do copy[i] = value end
            table.sort(copy)
            return math.max(30, math.min(120, copy[math.ceil(#copy / 2)]))
        end
        return math.max(o.speed, 10)
    end

    function Orders.myTier()
        if cfg.orders.myTier > 0 then return cfg.orders.myTier, false end
        return Catalog.currentTier(), true
    end

    function Orders.rank(now)
        local rows, suitable, sum = {}, 0, 0
        for _, order in ipairs(state.list) do
            local score, reason = Orders.evaluate(order, now)
            rows[#rows + 1] = {order = order, score = score, reason = reason,
                               timeLeft = order.timeBase - (now - order.receivedAt)}
            if score then suitable = suitable + 1 sum = sum + score end
        end
        table.sort(rows, function(a, b)
            if (a.score ~= nil) ~= (b.score ~= nil) then return a.score ~= nil end
            if a.score and b.score and a.score ~= b.score then return a.score > b.score end
            return a.order.index < b.order.index
        end)
        local best = rows[1] and rows[1].score and rows[1] or nil
        local great = best ~= nil and suitable >= 2 and best.score >= (sum / suitable) * 1.25
        return rows, best, great, suitable
    end

    local function extractPayload(text)
        local _, body = text:match("executeEvent%('[^']+',%s*([`'])(.*)%1%);?%s*$")
        return body
    end

    local function setWindowOpen(open)
        if state.windowOpen and not open then state.closedAt = os.clock() end
        state.windowOpen = open
        if open then state.updatedAt = os.clock() end
    end

    local function bump(map, key, entry)
        local group = map[key]
        if not group then group = {count = 0, paid = 0, seconds = 0, km = 0} map[key] = group end
        group.count = group.count + 1
        group.paid = group.paid + entry.paid
        group.seconds = group.seconds + entry.seconds
        group.km = group.km + (entry.km or 0)
    end

    local function trimCustomers(map, limit)
        local keys = {}
        for key in pairs(map) do keys[#keys + 1] = key end
        while #keys > limit do
            local worst, worstIndex = nil, 1
            for i, key in ipairs(keys) do
                if not worst or map[key].count < map[worst].count then worst, worstIndex = key, i end
            end
            map[worst] = nil
            table.remove(keys, worstIndex)
        end
    end

    local function finishActive(result, paid, endedAt)
        local a = state.active
        if not a then return end
        state.active = nil
        state.pendingFinish = nil
        session.activeOrder = nil
        local estimated
        if result == 'done' and cfg.track.percent and salaryHint and not salaryHint.used
            and salaryHint.time >= a.pickedAt and salaryHint.time <= (endedAt or os.clock()) + 10 then
            local base = windowSum(session.log, a.pickedAtTime)
            local extra = math.floor(base * salaryHint.percent / 100)
            if extra > 0 then
                salaryHint.used = true
                addIncome('other', extra, {name = '\208\159\209\128\208\190\209\134\208\181\208\189\209\130 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139 +' .. string.format('%g', salaryHint.percent) .. '% (\208\190\209\134\208\181\208\189\208\186\208\176)'})
                estimated = extra
            end
        end
        local cash = Ledger.gainSince((endedAt or os.clock()) - 12)
        if paid == nil then paid = windowSum(session.log, a.pickedAtTime) end
        if result == 'done' and paid <= 0 then result = 'unpaid' end
        local seconds = math.floor((endedAt or os.clock()) - a.pickedAt)
        local entry = {t = os.date('%H:%M:%S'), d = os.date('%d.%m'), customer = a.customer, cargo = a.cargo,
                       category = a.category, tier = a.tier, weight = a.weight, km = a.km, payout = a.payout,
                       paid = paid, seconds = seconds, result = result, note = a.note, cash = cash, estimated = estimated}
        pushLimited(history.orders, entry, 100)
        local st = stats.orders
        if result == 'done' then
            st.done = st.done + 1
            st.paid = st.paid + entry.paid
            st.seconds = st.seconds + seconds
            st.km = st.km + a.km
            bump(st.byCategory, a.category ~= '' and a.category or '?', entry)
            bump(st.byTier, a.tier and tostring(a.tier) or '0', entry)
            bump(st.byCustomer, a.customer, entry)
            trimCustomers(st.byCustomer, 40)
            if a.km >= 0.5 and seconds >= 20 then
                local speed = a.km / seconds * 3600
                if speed >= 15 and speed <= 130 then
                    st.speeds[#st.speeds + 1] = math.floor(speed)
                    while #st.speeds > 20 do table.remove(st.speeds, 1) end
                end
            end
            local day = dayRec(todayKey())
            day.trips = day.trips + 1
            if entry.paid > day.bestTrip then day.bestTrip = entry.paid end
            bumpHour('t', 1)
            session.trips = (session.trips or 0) + 1
            journal('trip', '\208\151\208\176\208\186\208\176\208\183: ' .. a.customer .. ' (\208\177\208\176\208\187\208\176\208\189\209\129 +' .. fmt(cash) .. ')', entry.paid)
            setFlash('truck', '\208\151\208\176\208\186\208\176\208\183 \209\129\208\180\208\176\208\189: +' .. fmt(entry.paid) .. ' \209\128\209\131\208\177.')
            notify('\208\151\208\176\208\186\208\176\208\183 \209\129\208\180\208\176\208\189: ' .. a.customer .. ', \208\178\209\129\208\181\208\179\208\190 +' .. fmt(entry.paid) .. ' \209\128\209\131\208\177. \208\183\208\176 ' .. fmtMinSec(seconds) ..
                ' (\208\189\208\176 \208\177\208\176\208\187\208\176\208\189\209\129 \208\191\209\128\208\184\209\136\208\187\208\190 +' .. fmt(cash) .. ')' .. (estimated and (', \208\184\208\183 \208\189\208\184\209\133 \208\191\209\128\208\190\209\134\208\181\208\189\209\130 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139 \208\191\208\190 \208\190\209\134\208\181\208\189\208\186\208\181 +' .. fmt(estimated)) or ''))
        elseif result == 'unpaid' then
            st.unpaid = st.unpaid + 1
        end
        mark('stats', 'history')
    end

    function Orders.completeSoon(reason)
        if state.active and not state.pendingFinish then
            state.pendingFinish = {time = os.clock(), reason = reason}
        end
    end

    function Orders.cursorVisible()
        if state.cursorCef and os.clock() - state.cursorAt < 600 then return true end
        local ok, active = pcall(sampIsCursorActive)
        return ok and active == true
    end

    function Orders.resetRuntime()
        state.list, state.category, state.updatedAt = {}, '', 0
        state.pending, state.active, state.pendingFinish = nil, nil, nil
        state.pickedTotal, state.pickedByScript = 0, 0
        state.detectedCapacity = nil
        state.lastCounter, state.lastTimer, state.lastPos = nil, nil, nil
        state.hintPending, state.demoUntil = false, 0
        state.cursorCef = false
    end

    function Orders.suspend()
        state.windowOpen, state.list, state.hintPending = false, {}, false
        state.demoUntil, state.editing = 0, false
    end

    function Orders.snapshotActive()
        local a = state.active
        if not a then session.activeOrder = nil return end
        local now = os.clock()
        session.activeOrder = {
            customer = a.customer, weight = a.weight, cargo = a.cargo, category = a.category, tier = a.tier,
            km = a.km, payout = a.payout, traveled = math.floor(a.traveled), pickedAtTime = a.pickedAtTime,
            deadlineTime = a.deadline and (os.time() + math.floor(a.deadline - now)) or nil, timeLimit = a.timeLimit,
        }
    end

    local function restoreActive()
        local saved = session.activeOrder
        if type(saved) ~= 'table' or not saved.pickedAtTime or os.time() - saved.pickedAtTime > 5400 then
            session.activeOrder = nil
            return
        end
        local now = os.clock()
        state.active = {
            customer = saved.customer, weight = saved.weight, cargo = saved.cargo or '', category = saved.category or '',
            tier = saved.tier, km = saved.km or 0, payout = saved.payout or 0, traveled = saved.traveled or 0,
            pickedAtTime = saved.pickedAtTime, pickedAt = now - (os.time() - saved.pickedAtTime),
            deadline = saved.deadlineTime and (now + (saved.deadlineTime - os.time())) or nil, timeLimit = saved.timeLimit,
        }
    end
    restoreActive()

    function Orders.abandonActive()
        finishActive('abandoned', 0)
    end

    Hooks.onIncome = function(kind, amount)
        state.lastIncomeAt = os.clock()
        local a = state.active
        if a and a.payout > 0 and os.clock() - a.pickedAt > 15 and amount >= a.payout * 0.5 and amount <= a.payout * 1.3 then
            Orders.completeSoon('income')
        end
    end

    local function findListedOrder(weight, customer)
        for _, order in ipairs(state.list) do
            if order.weight == weight and order.customer == customer then return order end
        end
    end

    local function beginActive(weight, customer, hint)
        finishActive('abandoned', 0)
        touchWork()
        local listed = (hint and hint.weight == weight and hint.customer == customer and hint) or findListedOrder(weight, customer)
        local now = os.clock()
        state.active = {
            customer = customer, weight = weight, pickedAt = now, pickedAtTime = os.time(), traveled = 0,
            cargo = listed and listed.cargo or '', category = listed and listed.category or '',
            tier = listed and listed.tier, km = listed and listed.km or 0, payout = listed and listed.payout or 0,
        }
        state.lastPos = nil
        if state.lastCounter and now - state.lastCounter.time < 3 then state.active.payout = state.lastCounter.value end
        if state.lastTimer and now - state.lastTimer.time < 3 then
            state.active.deadline = now + state.lastTimer.seconds
            state.active.timeLimit = state.lastTimer.seconds
        end
    end

    function Orders.consumePayout(amount)
        local a = state.active
        if not a or os.clock() - a.pickedAt > 3600 then return nil end
        if a.payout > 0 and (amount < a.payout * 0.5 or amount > a.payout * 1.3) then return nil end
        Orders.completeSoon('payout')
        return a.customer
    end
    Ledger.consumeOrderPayout = Orders.consumePayout

    function Orders.activeInfo(now)
        local a = state.active
        if not a then return nil end
        local left = a.deadline and (a.deadline - now) or nil
        local remainingKm = math.max(0, a.km - a.traveled / 1000)
        local need = remainingKm / Orders.effectiveSpeed() * 3600
        local status = 'ok'
        if left then
            if left <= 0 then status = 'late' elseif left < need * 1.05 + 5 then status = 'risk' end
        end
        return {order = a, left = left, remainingKm = remainingKm, need = need, status = status,
                delivered = state.pendingFinish ~= nil, arrived = a.arrived}
    end

    local function handleNotice(text)
        local delivered = text:match('\209\131\209\129\208\191\208\181\209\136\208\189\208\190 \208\180\208\190\209\129\209\130\208\176\208\178\208\184\208\187\208\184%s+(.-)%.%s') or text:match('\209\131\209\129\208\191\208\181\209\136\208\189\208\190 \208\180\208\190\209\129\209\130\208\176\208\178\208\184\208\187\208\184%s+(.-)%.')
        if delivered and state.active then
            state.active.note = delivered
            Orders.completeSoon('delivered')
        end
    end

    local function handleSkill(text)
        if not cfg.track.skill then return end
        local ok, data = pcall(Store.decodeJson, extractPayload(text) or '')
        local info = ok and type(data) == 'table' and type(data[1]) == 'table' and data[1]
        if not info or not tostring(info.title or ''):find('\208\148\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186', 1, true) then return end
        local skill = stats.skill
        skill.title = tostring(info.title)
        local from, to = tonumber(info.currentExp), tonumber(info.nextExp)
        local level = tonumber(info.currentLevel) or skill.level
        skill.level = level
        skill.exp = to or from or skill.exp
        skill.maxExp = tonumber(info.maxExp) or skill.maxExp
        if from and to and to > from then
            skill.gain = to - from
            skill.gains[#skill.gains + 1] = skill.gain
            while #skill.gains > 8 do table.remove(skill.gains, 1) end
        end
        mark('stats')
    end

    local function handleLoadNotice(text)
        local kg, customer = text:match('\208\146\209\139 \208\183\208\176\208\179\209\128\209\131\208\183\208\184\208\187\208\184 (%d+) \208\186\208\179 \209\130\208\190\208\178\208\176\209\128\208\176 \208\180\208\187\209\143 \208\183\208\176\208\186\208\176\208\183\209\135\208\184\208\186\208\176 ([^"]+)"')
        if not kg then return end
        state.pickedTotal = state.pickedTotal + 1
        local pending = state.pending
        state.pending = nil
        state.takeFails, state.takeBroken = 0, false
        if cfg.track.orders then beginActive(tonumber(kg), trim(customer), pending and pending.order) end
        if pending and os.clock() - pending.time < 10 then
            state.pickedByScript = state.pickedByScript + 1
            local same = pending.order.weight == tonumber(kg) and pending.order.customer == trim(customer)
            if same then notify('\208\151\208\176\208\186\208\176\208\183 \208\178\208\183\209\143\209\130: ' .. customer .. ', ' .. kg .. ' \208\186\208\179')
            else say('\208\146\208\189\208\184\208\188\208\176\208\189\208\184\208\181: \208\178\208\183\209\143\209\130 \208\180\209\128\209\131\208\179\208\190\208\185 \208\183\208\176\208\186\208\176\208\183, \209\135\208\181\208\188 \208\190\208\182\208\184\208\180\208\176\208\187\208\190\209\129\209\140 (' .. customer .. ', ' .. kg .. ' \208\186\208\179). \208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\189\208\190\208\188\208\181\209\128\208\176 \208\183\208\176\208\186\208\176\208\183\208\190\208\178.') end
        end
    end

    local function handleQuestText(text)
        if state.active and text:find('\208\146\209\139\208\177\208\181\209\128\208\184\209\130\208\181 \208\183\208\176\208\186\208\176\208\183', 1, true) and os.clock() - state.active.pickedAt > 5 then
            Orders.completeSoon('quest')
        end
        local digits = text:match('\208\179\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\208\181\208\188\208\189\208\190\209\129\209\130\209\140[^%d]*(%d[%d%s%.]*)%s*\208\186\208\179') or text:match('\208\179\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\209\145\208\188\208\189\208\190\209\129\209\130\209\140[^%d]*(%d[%d%s%.]*)%s*\208\186\208\179')
        local value = digits and parseInt(digits) or 0
        if value > 0 then state.detectedCapacity = value end
    end

    function Orders.handleEvent(raw)
        local text = Charset.toUtf8(raw)
        if text:find('cef.toggleServerCursor', 1, true) then
            state.cursorCef = text:match('toggleServerCursor.-%[(%a+)') == 'true'
            state.cursorAt = os.clock()
        end
        if text:find('event.setActiveView', 1, true) then
            setWindowOpen(text:find('SideMenuProperties', 1, true) ~= nil)
        elseif text:find('sideMenu.property.initialize', 1, true) or text:find('sideMenu.property.push', 1, true) then
            local isInit = text:find('sideMenu.property.initialize', 1, true) ~= nil
            local ok, data = pcall(Store.decodeJson, extractPayload(text) or '')
            if not (ok and type(data) == 'table' and type(data[1]) == 'table') then return end
            if isInit then
                state.list = {}
                state.category = type(data[2]) == 'string' and data[2] or ''
            end
            appendOrders(data[1], state.category)
            state.updatedAt = os.clock()
            if isInit and #state.list > 0 then
                state.windowOpen = true
                state.hintPending = true
            end
        elseif text:find('cef.toggleServerCursor', 1, true) and text:find('[false', 1, true) then
            setWindowOpen(false)
        elseif text:find('cef.addNotification', 1, true) then
            handleLoadNotice(text)
            handleNotice(text)
        elseif text:find('customizedCounter.initializeType', 1, true) then
            if text:find('"none"', 1, true) and state.active and os.clock() - state.active.pickedAt > 5 then
                Orders.completeSoon('counter')
            end
        elseif text:find('updateLevelInformation', 1, true) then
            handleSkill(text)
        elseif text:find('customizedCounter.initializeCounter', 1, true) then
            local digits = text:match('initializeCounter.-(%d[%d%s]*)%s*\209\128\209\131\208\177')
            if digits then
                state.lastCounter = {value = parseInt(digits), time = os.clock()}
                if state.active then state.active.payout = state.lastCounter.value end
            end
        elseif text:find('customizedCounter.initializeTimerRevert', 1, true) then
            local seconds = tonumber(text:match('initializeTimerRevert.-%[%s*(%d+)'))
            if seconds then
                state.lastTimer = {seconds = seconds, time = os.clock()}
                if state.active then
                    state.active.deadline = os.clock() + seconds
                    state.active.timeLimit = seconds
                end
            end
        end
    end

    -- ================= ПК: CEF-события (packet 220 / type 17) и квест-текст (172) =================
    local function parsePc(bs)
        raknetBitStreamSetReadOffset(bs, 0)
        raknetBitStreamIgnoreBits(bs, 8)
        local packetType = raknetBitStreamReadInt8(bs) % 256
        if packetType == 17 then
            raknetBitStreamIgnoreBits(bs, 32)
            local length = raknetBitStreamReadInt16(bs) % 65536
            local encoded = raknetBitStreamReadInt8(bs) % 256
            local text
            if encoded ~= 0 then text = raknetBitStreamDecodeString(bs, length + encoded)
            else text = raknetBitStreamReadString(bs, length) end
            Orders.handleEvent(text)
        elseif packetType == 172 then
            raknetBitStreamIgnoreBits(bs, 8)
            local length = raknetBitStreamReadInt8(bs) % 256
            handleQuestText(Charset.toUtf8(raknetBitStreamReadString(bs, length)))
        elseif packetType == 84 then
            Orders.onMobile(bs)
        end
    end

    -- ================= МОБАЙЛ: packet 220 / type 84 =================
    -- layout: [220][84][iface u8][sub u8][len u16][enc u8][text]
    -- iface 68: sub 0 = категория, sub 1 = JSON-список заказов
    -- iface 6 : sub 0 = JSON-уведомление {"text":"Вы загрузили N кг..."}
    -- iface 8 : sub 8 = премия за активный заказ, sub 9 = секунды до дедлайна (тикает раз в секунду)
    local M_LIST, M_NOTICE, M_HUD = 68, 6, 8
    local mobileCategory = ''
    local mobileSeen = false

    local function readText(bs)
        local length = raknetBitStreamReadInt16(bs) % 65536
        if length == 0 or length > 20000 then return nil end
        local encoded = raknetBitStreamReadInt8(bs) % 256
        if encoded ~= 0 then return raknetBitStreamDecodeString(bs, length + encoded) end
        return raknetBitStreamReadString(bs, length)
    end

    function Orders.onMobile(bs)
        local iface = raknetBitStreamReadInt8(bs) % 256
        -- ранний выход: чужие интерфейсы не декодируем вообще
        if iface ~= M_LIST and iface ~= M_NOTICE and iface ~= M_HUD then return end
        local sub = raknetBitStreamReadInt8(bs) % 256
        if iface == M_LIST then
            if sub > 1 then return end
        elseif iface == M_NOTICE then
            if sub ~= 0 then return end
        elseif sub ~= 8 and sub ~= 9 then
            return
        end
        local raw = readText(bs)
        if not raw then return end
        local now = os.clock()

        if iface == M_LIST then
            if sub == 0 then
                mobileCategory = trim(Charset.toUtf8(raw))
            else
                local ok, data = pcall(Store.decodeJson, Charset.toUtf8(raw))
                if not (ok and type(data) == 'table') then return end
                mobileSeen = true
                state.mobile = true
                state.list = {}
                state.category = mobileCategory
                appendOrders(data, mobileCategory)
                setWindowOpen(true)
                if #state.list > 0 then state.hintPending = true end
            end
        elseif iface == M_NOTICE then
            local text = Charset.toUtf8(raw)
            handleLoadNotice(text)
            handleNotice(text)
            if text:find('\208\146\209\139 \208\183\208\176\208\179\209\128\209\131\208\183\208\184\208\187\208\184', 1, true) then
                setWindowOpen(false)
            end
        elseif sub == 8 then
            local value = parseInt(raw)
            if value and value > 0 then
                state.lastCounter = {value = value, time = now}
                if state.active then state.active.payout = value end
            end
        else
            local seconds = tonumber(raw)
            if seconds and seconds >= 0 then
                state.lastTimer = {seconds = seconds, time = now}
                local a = state.active
                if a then
                    a.deadline = now + seconds
                    if not a.timeLimit or seconds > a.timeLimit then a.timeLimit = seconds end
                end
            end
        end
    end

    -- исходящие: закрытие окна заказов (type 63, iface 68, f1=0) 
    local function parseSend(bs)
        raknetBitStreamSetReadOffset(bs, 0)
        raknetBitStreamIgnoreBits(bs, 8)
        local t = raknetBitStreamReadInt8(bs) % 256
        if t == 63 then
            local iface = raknetBitStreamReadInt8(bs) % 256
            local f1 = raknetBitStreamReadInt32(bs)
            -- f1 = 0: кнопка "закрыть" в списке заказов
            if iface == M_LIST and f1 == 0 and state.windowOpen then
                setWindowOpen(false)
                state.closedAt = -100 -- без "задержки" карточки: исчезает сразу
            end
        end
    end

    function Orders.onSend(bs)
        if not (cfg.enabled and state.mobile) then return end
        local offset = raknetBitStreamGetReadOffset(bs)
        pcall(parseSend, bs)
        raknetBitStreamSetReadOffset(bs, offset)
    end

    function Orders.onPacket(bs)
        if not cfg.enabled then return end
        local offset = raknetBitStreamGetReadOffset(bs)
        local ok = pcall(parsePc, bs)
        raknetBitStreamSetReadOffset(bs, offset)
        return ok
    end

    local function sendCefCommand(command)
        local ok = pcall(function()
            local bs = raknetNewBitStream()
            raknetBitStreamWriteInt8(bs, 220)
            raknetBitStreamWriteInt8(bs, 18)
            raknetBitStreamWriteInt16(bs, #command)
            raknetBitStreamWriteString(bs, command)
            raknetBitStreamWriteInt32(bs, 0)
            local sent = raknetSendBitStreamEx(bs, 2, 9, 6)
            raknetDeleteBitStream(bs)
            if sent == false then error('send failed') end
        end)
        return ok
    end
    Orders.sendCefCommand = sendCefCommand

    -- клик по заказу на мобиле: [220][63][iface u8][f1 i32][f2 i32][len u8][text]
    -- f1 = 1 (взять), f2 = индекс заказа (с нуля)
    local MOBILE_CLICK = {iface = 68, f1 = 1}
    local function sendMobileClick(index)
        local ok = pcall(function()
            local bs = raknetNewBitStream()
            raknetBitStreamWriteInt8(bs, 220)
            raknetBitStreamWriteInt8(bs, 63)
            raknetBitStreamWriteInt8(bs, MOBILE_CLICK.iface)
            raknetBitStreamWriteInt32(bs, MOBILE_CLICK.f1)
            raknetBitStreamWriteInt32(bs, index)
            raknetBitStreamWriteInt8(bs, 0)
            local sent = raknetSendBitStreamEx(bs, 2, 9, 6)
            raknetDeleteBitStream(bs)
            if sent == false then error('send failed') end
        end)
        return ok
    end

    function Orders.demoActive() return os.clock() < state.demoUntil end

    Orders.lastReason = 'closed'

    function Orders.cardStatus(now)
        if now < state.demoUntil or state.editing then
            local demo = {index = 0, category = '\208\158\209\128\209\131\208\182\208\184\208\181', receivedAt = now, customer = '\208\157\208\181\209\132\209\130\208\181\208\177\208\176\208\183\208\176', urgent = false,
                          cargo = '\208\162\208\176\208\189\208\186\208\190\208\178\209\139\208\181 \208\179\209\131\209\129\208\181\208\189\208\184\209\134\209\139', weight = 19800, km = 2.4, timeBase = 1800,
                          payout = 891000, fragility = 40}
            Orders.lastReason = 'shown'
            return {row = {order = demo, score = 371000, timeLeft = 1800}, great = true, demo = true}, 'shown'
        end
        local reason
        local lingering = not state.windowOpen and now - state.closedAt < cfg.orders.linger
        if not cfg.orders.enabled then reason = 'off'
        elseif state.takeBroken then reason = 'closed'
        elseif not (state.windowOpen or lingering) then reason = 'closed'
        elseif #state.list == 0 then reason = 'empty'
        else
            local _, best, great = Orders.rank(now)
            if not best then reason = 'none'
            elseif cfg.orders.onlyGreat and not great then reason = 'notgreat'
            else
                Orders.lastReason = 'shown'
                return {row = best, great = great, closed = not state.windowOpen}, 'shown'
            end
        end
        Orders.lastReason = reason
        return nil, reason
    end

    function Orders.cardEntry(now) return (Orders.cardStatus(now)) end

    function Orders.emptyEntry(now)
        local rows = Orders.rank(now)
        local counts, order = {}, {}
        for _, row in ipairs(rows) do
            local why = row.reason or '?'
            if not counts[why] then counts[why] = 0 order[#order + 1] = why end
            counts[why] = counts[why] + 1
        end
        local lines = {}
        for i, why in ipairs(order) do
            if i > 4 then break end
            lines[#lines + 1] = why .. ': ' .. counts[why]
        end
        return {empty = true, lines = lines, total = #rows, closed = not state.windowOpen}
    end

    function Orders.needsDraw(cardAlpha)
        return (cfg.orders.enabled and (state.windowOpen or os.clock() - state.closedAt < cfg.orders.linger)) or Orders.demoActive() or state.editing or (cardAlpha or 0) > 0.01
    end

    -- Не удалось взять заказ (пакет не ушёл / заказ не взялся): после нескольких попыток
    -- прячем карточку и кнопку, чтобы не мешали. /dbo пробует взять вручную.
    local TAKE_MAX_FAILS = 3
    function Orders.registerTakeFail()
        state.pending = nil
        state.takeFails = (state.takeFails or 0) + 1
        if state.takeFails >= TAKE_MAX_FAILS and not state.takeBroken then
            state.takeBroken = true
            setWindowOpen(false)
            state.closedAt = -100
            say('\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \208\178\208\183\209\143\209\130\209\140 \208\183\208\176\208\186\208\176\208\183 - \208\186\208\189\208\190\208\191\208\186\208\176 \209\129\208\186\209\128\209\139\209\130\208\176 (/dbo - \208\178\209\128\209\131\209\135\208\189\209\131\209\142).')
        end
    end

    function Orders.pickBest(force)
        local now = os.clock()
        if state.takeBroken and not force then return false end
        if not (cfg.orders.enabled and state.windowOpen) or now - state.lastPickAt < 1.5 then return false end
        local _, best = Orders.rank(now)
        if not best then return false end
        state.lastPickAt = now
        state.pending = {order = best.order, time = now}
        local sent
        if state.mobile then sent = sendMobileClick(best.order.index)
        else sent = sendCefCommand('sideMenu.property.submit|' .. best.order.index) end
        if not sent then
            Orders.registerTakeFail()
            return false
        end
        if state.mobile then
            setWindowOpen(false)
            state.closedAt = -100 -- карточка пропадает сразу после нажатия
        end
        say('\208\145\208\181\209\128\209\131 \208\183\208\176\208\186\208\176\208\183: ' .. best.order.customer .. ' (' .. best.order.cargo .. ', ' .. fmt(best.order.payout) .. ' \209\128\209\131\208\177.)')
        return true
    end

    local KEY_NAMES = {
        [0x08] = 'Backspace', [0x09] = 'Tab', [0x0D] = 'Enter', [0x10] = 'Shift', [0x11] = 'Ctrl', [0x12] = 'Alt',
        [0x14] = 'CapsLock', [0x20] = 'Space', [0x21] = 'PageUp', [0x22] = 'PageDown', [0x23] = 'End', [0x24] = 'Home',
        [0x25] = 'Left', [0x26] = 'Up', [0x27] = 'Right', [0x28] = 'Down', [0x2D] = 'Insert', [0x2E] = 'Delete',
    }
    function Orders.keyName(vk)
        if KEY_NAMES[vk] then return KEY_NAMES[vk] end
        if vk >= 0x30 and vk <= 0x39 then return string.char(vk) end
        if vk >= 0x41 and vk <= 0x5A then return string.char(vk) end
        if vk >= 0x60 and vk <= 0x69 then return 'Num' .. (vk - 0x60) end
        if vk >= 0x70 and vk <= 0x87 then return 'F' .. (vk - 0x6F) end
        return string.format('0x%02X', vk)
    end

    function Orders.startKeyCapture() state.capturingKey = true end

    function Orders.startEdit()
        state.editing, state.editFirst = true, true
        state.editRestore = {x = cfg.orders.x, y = cfg.orders.y, scale = cfg.orders.scale}
        menu.v = false
        say('\208\159\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\208\181 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131 \208\191\208\176\208\187\209\140\209\134\208\181\208\188, \208\186\208\189\208\190\208\191\208\186\208\184 \208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140 \208\184 \208\158\209\130\208\188\208\181\208\189\208\176 - \208\189\208\176 \209\129\208\176\208\188\208\190\208\185 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\181.')
    end

    local function stopEdit(save)
        if not state.editing then return end
        state.editing = false
        if save then
            mark('settings')
            say('\208\159\208\190\208\187\208\190\208\182\208\181\208\189\208\184\208\181 \208\184 \209\128\208\176\208\183\208\188\208\181\209\128 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\184 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\209\139.')
        elseif state.editRestore then
            cfg.orders.x, cfg.orders.y, cfg.orders.scale = state.editRestore.x, state.editRestore.y, state.editRestore.scale
        end
    end

    Orders.stopEdit = stopEdit

    function Orders.resetPosition()
        cfg.orders.x, cfg.orders.y, cfg.orders.scale = 50, 74, 1.0
        cfg.orders.bx, cfg.orders.by = -1, -1
        mark('settings')
    end

    local function chatHint(now)
        local entry, reason = Orders.cardStatus(now)
        if entry then
            local order = entry.row.order
            say((entry.great and '\208\154\209\128\209\131\209\130\208\190\208\185 \208\183\208\176\208\186\208\176\208\183: ' or '\208\155\209\131\209\135\209\136\208\184\208\185 \208\183\208\176\208\186\208\176\208\183: ') .. (order.urgent and '[\208\161\209\128\208\190\209\135\208\189\208\190] ' or '') .. order.customer ..
                ' - ' .. order.cargo .. ', ' .. fmt(order.weight) .. ' \208\186\208\179, ' .. string.format('%.1f', order.km) .. ' \208\186\208\188, ' ..
                fmt(order.payout) .. ' \209\128\209\131\208\177. (' .. fmt(order.payout / math.max(order.km, 0.1)) .. ' \209\128\209\131\208\177./\208\186\208\188)' .. (state.mobile and '' or ('. \208\146\208\183\209\143\209\130\209\140: [' .. Orders.keyName(cfg.orders.key) .. ']')))
        elseif reason == 'none' then
            local rows = Orders.rank(now)
            local reasons = {}
            for _, row in ipairs(rows) do
                local why = row.reason or '?'
                reasons[why] = (reasons[why] or 0) + 1
            end
            local parts = {}
            for why, count in pairs(reasons) do parts[#parts + 1] = why .. ' x' .. count end
            say('\208\159\208\190\208\180\209\133\208\190\208\180\209\143\209\137\208\184\209\133 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\189\208\181\209\130 (' .. table.concat(parts, ', ') .. ')')
        end
    end

    function Orders.tick(now)
        if state.editing then
            if imgui.MB.key(0x02) or imgui.MB.key(0x0D) then
                stopEdit(true)
            elseif imgui.MB.key(0x1B) then
                stopEdit(false)
            elseif imgui.MB.key(0x6B) or imgui.MB.key(0xBB) then
                cfg.orders.scale = math.min(2.5, cfg.orders.scale + 0.05)
            elseif imgui.MB.key(0x6D) or imgui.MB.key(0xBD) then
                cfg.orders.scale = math.max(0.5, cfg.orders.scale - 0.05)
            end
            return
        end
        if state.capturingKey then
            for vk = 0x08, 0xFE do
                if vk ~= 0x01 and vk ~= 0x02 and vk ~= 0x04 and imgui.MB.key(vk) then
                    state.capturingKey = false
                    if vk ~= 0x1B then
                        cfg.orders.key = vk
                        mark('settings')
                        say('\208\154\208\187\208\176\208\178\208\184\209\136\208\176 "\208\178\208\183\209\143\209\130\209\140 \208\183\208\176\208\186\208\176\208\183": ' .. Orders.keyName(vk))
                    end
                    return
                end
            end
            return
        end
        local a = state.active
        if a then
            if now - state.lastOdoAt >= 0.5 then
                state.lastOdoAt = now
                local ok, x, y = pcall(getCharCoordinates, PLAYER_PED)
                if ok and x then
                    local step = 0
                    if state.lastPos then
                        local dx, dy = x - state.lastPos.x, y - state.lastPos.y
                        step = math.sqrt(dx * dx + dy * dy)
                        if step < 250 then a.traveled = a.traveled + step end
                    end
                    state.lastPos = {x = x, y = y}
                    if step < 1.5 then a.stillSince = a.stillSince or now else a.stillSince = nil end
                end
            end
            if a.km > 0 and a.traveled / 1000 >= a.km - 0.05 and a.stillSince and now - a.stillSince >= 20
                and now - a.pickedAt > 60 and not a.arrived then
                a.arrived, a.arrivedAt = true, now
            end
            if a.arrived and now - a.arrivedAt >= 120 then Orders.completeSoon('arrived') end
            local pending = state.pendingFinish
            local quiet = now - math.max(lastWorkLineAt, state.lastIncomeAt)
            if pending and ((now - pending.time >= 3 and quiet >= 1.5 and #unclaimed_gains == 0) or now - pending.time >= 12) then
                finishActive('done', nil, pending.time)
            elseif (a.deadline and now > a.deadline + 90) or now - a.pickedAt > 5400 then
                finishActive('unpaid', 0)
            end
        else
            state.lastPos = nil
        end
        if state.pending and now - state.pending.time > 6 then Orders.registerTakeFail() end
        if state.windowOpen and now - state.updatedAt > 600 then state.windowOpen = false end
        if state.hintPending and state.windowOpen and now - state.updatedAt >= 0.5 then
            state.hintPending = false
            if cfg.orders.enabled and cfg.orders.chatHint then chatHint(now) end
        end
        if not (cfg.orders.enabled and state.windowOpen) then return end
        if imgui.MB.key(cfg.orders.key) then
            local busy = false
            pcall(function() busy = sampIsChatInputActive() or sampIsDialogActive() end)
            if not busy then Orders.pickBest() end
        end
    end
end

local function onRecvPkt(id, bs)
    if id == 220 then Orders.onPacket(bs) end
end

local function onSendPkt(id, bs)
    if id == 220 then Orders.onSend(bs) end
end

-- NeoMLoader: через addEventHandler (RakLua); иначе классические глобальные хуки.
-- Одновременно не регистрируем, чтобы пакет не обрабатывался дважды.
if NEOM then
    addEventHandler('onReceivePacket', onRecvPkt)
    addEventHandler('onSendPacket', onSendPkt)
else
    onReceivePacket = onRecvPkt
    onSendPacket = onSendPkt
end

local function vehicleHealth()
    local ok, hp = pcall(function()
        if isCharInAnyCar(PLAYER_PED) then return getCarHealth(storeCarCharIsInNoSave(PLAYER_PED)) end
    end)
    if ok and type(hp) == 'number' then return hp end
    return nil
end

local Data = {}

do
    local RETENTION_DAYS = 7

    local function parseKey(key)
        local y, m, d = tostring(key):match('^(%d+)-(%d+)-(%d+)$')
        if not y then return nil end
        return os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12})
    end

    function Data.periodDay()
        local start, today = parseKey(stats.periodStart), parseKey(todayKey())
        if not start or not today then return 1 end
        return math.floor((today - start) / 86400 + 0.5) + 1
    end

    function Data.weekInfo()
        local day = Data.periodDay()
        return {day = math.max(1, math.min(day, RETENTION_DAYS)), total = RETENTION_DAYS, lastDay = day >= RETENTION_DAYS}
    end

    local function summary()
        local lines = {}
        local function add(text) lines[#lines + 1] = text end
        add('Truck Helper - \208\184\209\130\208\190\208\179\208\184 \208\189\208\181\208\180\208\181\208\187\208\184')
        add('\208\159\208\181\209\128\208\184\208\190\208\180: ' .. stats.periodStart .. ' - ' .. todayKey())
        add('')
        add('\208\148\208\190\209\133\208\190\208\180 \208\178\209\129\208\181\208\179\208\190: ' .. fmt(totalMoney()) .. ' \209\128\209\131\208\177.')
        for _, kind in ipairs({'truck', 'car', 'other'}) do
            add('  ' .. KIND[kind].name .. ': ' .. fmt(stats[kind].total) .. ' \209\128\209\131\208\177. (\208\190\208\191\208\181\209\128\208\176\209\134\208\184\208\185: ' .. stats[kind].count .. ')')
        end
        add('\208\155\208\176\209\128\209\134\208\190\208\178: ' .. stats.chests.total .. ', \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\190\208\178: \208\178\209\128\208\181\208\188\208\181\208\189\208\189\209\139\209\133 ' .. (stats.items.total - stats.eternal.total) .. ', \208\178\208\181\209\135\208\189\209\139\209\133 ' .. stats.eternal.total)
        local ex = stats.expenses
        add('\208\160\208\176\209\129\209\133\208\190\208\180\209\139: ' .. fmt(ex.total) .. ' \209\128\209\131\208\177. (\209\130\208\190\208\191\208\187\208\184\208\178\208\190 ' .. fmt(ex.fuel or 0) .. ', \209\128\208\181\208\188\208\190\208\189\209\130 ' .. fmt(ex.repair or 0) .. ', \209\136\209\130\209\128\208\176\209\132\209\139 ' .. fmt(ex.fine or 0) .. ')')
        add('\208\167\208\184\209\129\209\130\209\139\208\185 \208\180\208\190\209\133\208\190\208\180: ' .. fmt(totalMoney() - ex.total) .. ' \209\128\209\131\208\177.')
        add('\208\157\208\181 \208\180\208\190\209\133\208\190\208\180 (\208\178\209\139\208\180\208\176\209\135\208\176, \208\191\208\181\209\128\208\181\208\178\208\190\208\180\209\139): ' .. fmt(stats.ignored.total) .. ' \209\128\209\131\208\177.')
        if stats.promo.count > 0 then
            add('\208\144\208\186\209\134\208\184\208\184 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133: \208\178\209\139\208\191\208\187\208\176\209\130 ' .. stats.promo.count .. ' \208\189\208\176 ' .. fmt(stats.promo.paid) .. ' \209\128\209\131\208\177.')
        end
        if stats.salary.count > 0 then
            add('\208\145\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181 (\208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186): \208\191\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185 +' .. string.format('%g', stats.salary.percent) .. '%, \208\180\208\190\208\191. \208\178\209\139\208\191\208\187\208\176\209\130\208\176 ' .. fmt(stats.salary.extra) .. ' \209\128\209\131\208\177.')
        end
        add('')
        add('\208\159\208\190 \208\180\208\189\209\143\208\188:')
        local keys = {}
        for key in pairs(stats.days) do keys[#keys + 1] = key end
        table.sort(keys)
        local bestDay, bestMoney = nil, 0
        for _, key in ipairs(keys) do
            local money = stats.days[key].money or 0
            add('  ' .. key .. ': ' .. fmt(money) .. ' \209\128\209\131\208\177.')
            if money > bestMoney then bestDay, bestMoney = key, money end
        end
        if bestDay then add('\208\155\209\131\209\135\209\136\208\184\208\185 \208\180\208\181\208\189\209\140: ' .. bestDay .. ' (' .. fmt(bestMoney) .. ' \209\128\209\131\208\177.)') end
        add('')
        local st = stats.orders
        add('\208\151\208\176\208\186\208\176\208\183\208\190\208\178 \209\129\208\180\208\176\208\189\208\190: ' .. st.done .. ', \208\177\208\181\208\183 \208\189\208\176\208\185\208\180\208\181\208\189\208\189\208\190\208\185 \208\178\209\139\208\191\208\187\208\176\209\130\209\139: ' .. st.unpaid)
        if st.done > 0 then
            add('\208\146\209\139\208\191\208\187\208\176\209\135\208\181\208\189\208\190 \208\191\208\190 \208\183\208\176\208\186\208\176\208\183\208\176\208\188: ' .. fmt(st.paid) .. ' \209\128\209\131\208\177., \208\178 \209\129\209\128\208\181\208\180\208\189\208\181\208\188 ' .. fmt(st.paid / st.done) .. ' \209\128\209\131\208\177.')
            if st.seconds > 0 then add('\208\160\209\131\208\177./\209\135\208\176\209\129 \208\178 \208\191\209\131\209\130\208\184: ' .. fmt(st.paid / (st.seconds / 3600))) end
        end
        if stats.skill.level > 0 then
            add('\208\157\208\176\208\178\209\139\208\186 "' .. stats.skill.title .. '": ' .. stats.skill.level .. ' \209\131\209\128., ' .. stats.skill.exp .. '/' .. stats.skill.maxExp)
        end
        return table.concat(lines, '\n')
    end

    function Data.archive(reason)
        local text = summary()
        local dir = ROOT .. '/archive'
        pcall(function() if not doesDirectoryExist(dir) then createDirectory(dir) end end)
        local path = string.format('%s/week_%s_%s.txt', dir, stats.periodStart ~= '' and stats.periodStart or todayKey(), todayKey())
        local f = io.open(path, 'wb')
        if not f then return nil end
        f:write(text, '\n')
        f:close()
        if reason == 'manual' then pcall(setClipboardText, text) end
        return 'config/TruckHelper/archive/' .. path:match('[^/]+$')
    end

    function Data.goalRestart()
        stats.goalRound = {day = todayKey(), base = todayMoney(), done = false}
        mark('stats')
    end

    function Data.goalSet(amount)
        cfg.goal.amount = math.max(1000, math.floor(amount or 0))
        mark('settings')
        Data.goalRestart()
    end

    function Data.newSession()
        stats.session = newSession()
        session = stats.session
        Orders.snapshotActive()
        mark('stats')
    end

    function Data.resetStatistics()
        for key in pairs(stats) do stats[key] = nil end
        applyDefaults(stats, DEF_STATS)
        for key in pairs(history) do history[key] = nil end
        applyDefaults(history, DEF_HIST)
        stats.session = newSession()
        session = stats.session
        stats.periodStart = todayKey()
        Orders.snapshotActive()
        mark('stats', 'history')
    end

    function Data.resetAll()
        Orders.resetRuntime()
        Data.resetStatistics()
        vehicleCatalog.list, vehicleCatalog.idx = {}, {}
        itemCatalog.list, itemCatalog.idx = {}, {}
        Ledger.resetBaseline()
        for key in pairs(cfg) do cfg[key] = nil end
        applyDefaults(cfg, DEF_CFG)
        mark('settings', 'stats', 'history', 'vehicles', 'items')
    end

    function Data.setEnabled(on)
        if cfg.enabled == on then return end
        cfg.enabled = on
        mark('settings')
        if on then
            Ledger.resetBaseline()
            say('\208\161\208\186\209\128\208\184\208\191\209\130 \208\178\208\186\208\187\209\142\209\135\209\145\208\189.')
        else
            Orders.suspend()
            say('\208\161\208\186\209\128\208\184\208\191\209\130 \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189. \208\146\208\186\208\187\209\142\209\135\208\184\209\130\209\140: /db')
        end
    end

    function Data.checkWeek()
        if stats.periodStart == '' then
            stats.periodStart = todayKey()
            mark('stats')
        end
        local day = Data.periodDay()
        if day > RETENTION_DAYS then
            local path = Data.archive('auto')
            Data.resetStatistics()
            say('\208\159\209\128\208\190\209\136\208\187\208\176 \208\189\208\181\208\180\208\181\208\187\209\143: \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \209\129\208\177\209\128\208\190\209\136\208\181\208\189\208\176' .. (path and (', \208\184\209\130\208\190\208\179\208\184 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\209\139: ' .. path) or '') .. '. \208\157\208\176\209\135\208\184\208\189\208\176\209\142 \208\189\208\190\208\178\209\131\209\142 \208\189\208\181\208\180\208\181\208\187\209\142.')
        elseif day == RETENTION_DAYS and stats.noticeDay ~= todayKey() then
            stats.noticeDay = todayKey()
            mark('stats')
            say('\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185 \208\180\208\181\208\189\209\140 \208\189\208\181\208\180\208\181\208\187\208\184 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\184: \208\178 \208\191\208\190\208\187\208\189\208\190\209\135\209\140 \208\190\208\189\208\176 \209\129\208\177\209\128\208\190\209\129\208\184\209\130\209\129\209\143, \208\184\209\130\208\190\208\179\208\184 \209\129\208\190\209\133\209\128\208\176\208\189\209\142 \208\178 \208\176\209\128\209\133\208\184\208\178 \209\129\208\176\208\188.')
        end
    end
end

local ACC = {r = 255, g = 165, b = 0}

local function rgba(r, g, b, a) return imgui.ImVec4(r / 255, g / 255, b / 255, a or 1) end
local function packColor(r, g, b, a)
    a = math.floor((a or 1) * 255 + 0.5)
    return a * 16777216 + b * 65536 + g * 256 + r
end
local function accentColor(a) return rgba(ACC.r, ACC.g, ACC.b, a) end
local function accentColor32(a) return packColor(ACC.r, ACC.g, ACC.b, a) end
local function kindColor(kind, a) local c = KIND[kind].c return rgba(c[1], c[2], c[3], a) end

local DIM   = rgba(140, 148, 165)
local WHITE = rgba(232, 235, 242)
local GREEN = rgba(72, 205, 130)
local RED   = rgba(255, 82, 82)

local function hsvToRgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local r, g, b
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function applyTheme()
    local th = THEMES[cfg.theme] or THEMES[1]
    if th.rainbow then
        ACC.r, ACC.g, ACC.b = hsvToRgb((os.clock() / 12) % 1, 0.72, 1)
    else
        ACC.r, ACC.g, ACC.b = th.c[1], th.c[2], th.c[3]
    end

    imgui.SwitchContext()
    local style = imgui.GetStyle()
    local colors = style.Colors

    local function sset(k, v) pcall(function()
        local K = imgui.MB.K
        if type(v) == 'table' then style[k] = imgui.MB.RV2(v.x * K, v.y * K) else style[k] = v * K end
    end) end
    local function col(name, r, g, b, a)
        local idx = imgui.Col[name]
        if idx then colors[idx] = rgba(r, g, b, a) end
    end

    sset('WindowPadding', imgui.ImVec2(16, 16))
    sset('FramePadding', imgui.ImVec2(10, 6))
    sset('ItemSpacing', imgui.ImVec2(10, 8))
    sset('ItemInnerSpacing', imgui.ImVec2(8, 6))
    sset('WindowRounding', 12)
    sset('ChildWindowRounding', 10)
    sset('ChildRounding', 10)
    sset('FrameRounding', 7)
    sset('PopupRounding', 8)
    sset('ScrollbarRounding', 8)
    sset('GrabRounding', 7)
    sset('ScrollbarSize', 8)
    sset('GrabMinSize', 14)
    sset('WindowBorderSize', 1)
    sset('ChildBorderSize', 1)
    sset('FrameBorderSize', 0)
    sset('PopupBorderSize', 1)

    col('Text', 232, 235, 242, 1)
    col('TextDisabled', 120, 128, 146, 1)
    col('WindowBg', 13, 15, 21, 0.98)
    col('ChildWindowBg', 19, 22, 31, 1)
    col('ChildBg', 19, 22, 31, 1)
    col('PopupBg', 19, 22, 31, 0.98)
    col('Border', 255, 255, 255, 0.07)
    col('BorderShadow', 0, 0, 0, 0)
    col('FrameBg', 28, 32, 44, 1)
    col('FrameBgHovered', 36, 41, 57, 1)
    col('FrameBgActive', 42, 48, 66, 1)
    col('TitleBg', 13, 15, 21, 1)
    col('TitleBgActive', 13, 15, 21, 1)
    col('TitleBgCollapsed', 13, 15, 21, 1)
    col('ScrollbarBg', 0, 0, 0, 0)
    col('ScrollbarGrab', 50, 56, 74, 1)
    col('ScrollbarGrabHovered', 70, 78, 102, 1)
    col('ScrollbarGrabActive', ACC.r, ACC.g, ACC.b, 1)
    col('CheckMark', ACC.r, ACC.g, ACC.b, 1)
    col('SliderGrab', ACC.r, ACC.g, ACC.b, 0.9)
    col('SliderGrabActive', ACC.r, ACC.g, ACC.b, 1)
    col('Button', 33, 38, 52, 1)
    col('ButtonHovered', 44, 50, 69, 1)
    col('ButtonActive', ACC.r, ACC.g, ACC.b, 0.85)
    col('Header', ACC.r, ACC.g, ACC.b, 0.25)
    col('HeaderHovered', ACC.r, ACC.g, ACC.b, 0.40)
    col('HeaderActive', ACC.r, ACC.g, ACC.b, 0.55)
    col('Separator', 255, 255, 255, 0.09)
    col('SeparatorHovered', ACC.r, ACC.g, ACC.b, 0.6)
    col('SeparatorActive', ACC.r, ACC.g, ACC.b, 0.9)
    col('TextSelectedBg', ACC.r, ACC.g, ACC.b, 0.35)
end

local UI = {
    tab = 1, helpId = 0, wheelConsumed = false, cardStack = {}, dead = {},
    menuAlpha = 0, menuTarget = 0, menuLast = os.clock(),
    overlayEdit = false, overlayRestore = nil, overlayFirst = false,
    confirmReset = 0, confirmAll = 0, groupX = 0, period = 'today',
    panelH = {}, panelStack = {}, menuX = nil, menuY = nil, dragOffset = nil, dragging = false, goalEdit = false, goalInput = nil,
}
local ui = {}
local pages = {}
local widgetState = {}

local function widgetKey(tbl, key) return tostring(tbl) .. ':' .. key end

function ui.wflags(...)
    local f = 0
    for _, n in ipairs({...}) do f = f + (imgui.WindowFlags[n] or 0) end
    return f
end

local function plain(text)
    return (text:gsub('\226\128[\147\148]', '-'):gsub('\194\160', ' '))
end

local function cutText(text, maxChars)
    local count, pos = 0, 1
    for chunk in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        count = count + 1
        if count > maxChars then return text:sub(1, pos - 1) .. '...' end
        pos = pos + #chunk
    end
    return text
end

function ui.help(title, text)
    UI.helpId = UI.helpId + 1
    local size = 18
    local origin = imgui.GetCursorScreenPos()
    imgui.InvisibleButton('##help' .. UI.helpId, imgui.ImVec2(size, size))
    local hovered = imgui.IsItemHovered()
    local drawList = imgui.GetWindowDrawList()
    local center = imgui.ImVec2(origin.x + size / 2, origin.y + size / 2)
    drawList:AddCircleFilled(center, size / 2 - 1, hovered and accentColor32(0.95) or packColor(255, 255, 255, 0.12), 20)
    local mark = '?'
    local ts = imgui.CalcTextSize(mark)
    drawList:AddText(imgui.ImVec2(center.x - ts.x / 2, center.y - ts.y / 2),
        hovered and packColor(20, 20, 24, 1) or packColor(200, 205, 218, 1), mark)
    if hovered then
        imgui.BeginTooltip()
        imgui.PushTextWrapPos(330)
        if title then imgui.TextColored(accentColor(), title) end
        imgui.Text(text or title)
        imgui.PopTextWrapPos()
        imgui.EndTooltip()
    end
end

local function withHelp(help)
    if not help then return end
    imgui.SameLine(0, 6)
    ui.help(help[1], help[2])
end

function ui.iconText(iconName, text, iconColor, textColor, columnWidth)
    local icon = icons[iconName]
    if icon ~= '' then
        local startX = imgui.GetCursorPosX() - UI.groupX
        imgui.TextColored(iconColor or accentColor(), icon)
        imgui.SameLine(startX + (columnWidth or 24))
    end
    if textColor then imgui.TextColored(textColor, text) else imgui.Text(text) end
end

function ui.pageTitle(iconName, title, help)
    pushFont(fonts.big)
    ui.iconText(iconName, title, nil, nil, 38)
    popFont(fonts.big)
    if help then
        imgui.SameLine(0, 10)
        imgui.SetCursorPosY(imgui.GetCursorPosY() + 9)
        ui.help(help[1], help[2])
    end
    imgui.Spacing()
end

function ui.sectionLabel(iconName, title, help)
    imgui.Spacing()
    imgui.Spacing()
    ui.iconText(iconName, title, accentColor())
    if help then
        imgui.SameLine(0, 8)
        ui.help(help[1], help[2])
    end
    imgui.Spacing()
end

function ui.checkbox(label, tbl, key, file, help, iconName)
    local k = widgetKey(tbl, key)
    local b = widgetState[k]
    if not b then b = imgui.ImBool(tbl[key]) widgetState[k] = b end
    b.v = tbl[key]
    local shown = label
    if iconName and icons[iconName] ~= '' then shown = icons[iconName] .. '  ' .. label end
    if imgui.Checkbox(shown .. '##' .. k, b) then
        tbl[key] = b.v
        mark(file or 'settings')
    end
    withHelp(help)
end

function ui.slider(label, tbl, key, mn, mx, fmtStr, help)
    local k = widgetKey(tbl, key)
    local f = widgetState[k]
    if not f then f = imgui.ImFloat(tbl[key]) widgetState[k] = f end
    f.v = tbl[key]
    if imgui.SliderFloat(label .. '##' .. k, f, mn, mx, fmtStr or '%.2f') then
        tbl[key] = f.v
        mark('settings')
    end
    withHelp(help)
end

function ui.inputInt(label, tbl, key, step, fast, help)
    local k = widgetKey(tbl, key)
    local iv = widgetState[k]
    if not iv then iv = imgui.ImInt(tbl[key]) widgetState[k] = iv end
    iv.v = tbl[key]
    if imgui.InputInt(label .. '##' .. k, iv, step, fast) then
        if iv.v < 0 then iv.v = 0 end
        tbl[key] = iv.v
        mark('settings')
    end
    withHelp(help)
end

function ui.coloredButton(label, w, h, r, g, b)
    pushCol(imgui.Col.Button, rgba(r, g, b, 0.22))
    pushCol(imgui.Col.ButtonHovered, rgba(r, g, b, 0.38))
    pushCol(imgui.Col.ButtonActive, rgba(r, g, b, 0.60))
    local pressed = imgui.Button(label, imgui.ImVec2(w, h))
    popCol(3)
    return pressed
end

function ui.iconButton(iconName, text, w, h)
    return imgui.Button(icons[iconName] .. '  ' .. text .. '##b' .. iconName .. text, imgui.ImVec2(w, h or 30))
end

function ui.dangerButton(iconName, text, w, h)
    return ui.coloredButton(icons[iconName] .. '  ' .. text .. '##d' .. iconName .. text, w, h or 30, 255, 82, 82)
end

function ui.cardBegin(w, h)
    local origin = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    local corner = imgui.ImVec2(origin.x + w, origin.y + h)
    drawList:AddRectFilled(origin, corner, packColor(24, 28, 39, 1), 10)
    drawList:AddRect(origin, corner, packColor(255, 255, 255, 0.07), 10)
    imgui.SetCursorScreenPos(imgui.ImVec2(origin.x + 12, origin.y + 10))
    imgui.BeginGroup()
    UI.groupX = imgui.GetCursorPosX()
    UI.cardStack[#UI.cardStack + 1] = {origin = origin, w = w, h = h}
end

function ui.cardEnd()
    local card = table.remove(UI.cardStack)
    imgui.EndGroup()
    UI.groupX = 0
    imgui.SetCursorScreenPos(card.origin)
    imgui.Dummy(imgui.ImVec2(card.w, card.h))
end

function ui.panelBegin(id, w, iconName, title, help)
    local origin = imgui.GetCursorScreenPos()
    local height = UI.panelH[id] or 80
    local drawList = imgui.GetWindowDrawList()
    local corner = imgui.ImVec2(origin.x + w, origin.y + height)
    drawList:AddRectFilled(origin, corner, packColor(24, 28, 39, 1), 10)
    drawList:AddRect(origin, corner, packColor(255, 255, 255, 0.07), 10)
    imgui.SetCursorScreenPos(imgui.ImVec2(origin.x + 14, origin.y + 12))
    imgui.BeginGroup()
    UI.groupX = imgui.GetCursorPosX()
    UI.panelStack[#UI.panelStack + 1] = {id = id, origin = origin, w = w}
    ui.iconText(iconName, title, accentColor(), nil, 26)
    if help then
        imgui.SameLine(0, 8)
        ui.help(help[1], help[2])
    end
    imgui.Spacing()
end

function ui.panelEnd()
    local panel = table.remove(UI.panelStack)
    imgui.Spacing()
    imgui.EndGroup()
    UI.groupX = 0
    local size = imgui.GetItemRectSize()
    local height = size.y + 24
    UI.panelH[panel.id] = height
    imgui.SetCursorScreenPos(panel.origin)
    imgui.Dummy(imgui.ImVec2(panel.w, height))
    imgui.Spacing()
end

local function leftText(seconds)
    seconds = math.max(0, math.floor(seconds))
    local days, hours = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24
    if days > 0 then return days .. ' \208\180\208\189. ' .. hours .. ' \209\135.' end
    local minutes = math.floor(seconds / 60) % 60
    if hours > 0 then return hours .. ' \209\135. ' .. minutes .. ' \208\188\208\184\208\189.' end
    return minutes .. ' \208\188\208\184\208\189.'
end

function ui.labelValue(label, value, col, w)
    local x = imgui.GetCursorPosX() - UI.groupX
    imgui.TextColored(DIM, label)
    imgui.SameLine(x + w - imgui.CalcTextSize(value).x)
    if col then imgui.TextColored(col, value) else imgui.Text(value) end
end

function ui.statCard(iconName, label, value, unit, color, width, height)
    ui.cardBegin(width, height)
    ui.iconText(iconName, label, rgba(color[1], color[2], color[3]), DIM, 22)
    pushFont(fonts.title)
    imgui.Text(value)
    popFont(fonts.title)
    if unit then imgui.TextColored(DIM, unit) end
    ui.cardEnd()
end

function ui.progressBar(frac, w, h)
    frac = math.max(0, math.min(1, frac))
    local p = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    drawList:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), packColor(255, 255, 255, 0.08), h / 2)
    if frac > 0 then
        drawList:AddRectFilled(p, imgui.ImVec2(p.x + math.max(h, w * frac), p.y + h), accentColor32(1), h / 2)
    end
    imgui.Dummy(imgui.ImVec2(w, h))
end

function ui.ring(cx, cy, radius, thickness, fraction, color32)
    local drawList = imgui.GetWindowDrawList()
    local segments = 56
    fraction = math.max(0, math.min(1, fraction))
    for i = 0, segments - 1 do
        local a0 = -math.pi / 2 + (i / segments) * 2 * math.pi
        local a1 = -math.pi / 2 + ((i + 1) / segments) * 2 * math.pi
        local p0 = imgui.ImVec2(cx + math.cos(a0) * radius, cy + math.sin(a0) * radius)
        local p1 = imgui.ImVec2(cx + math.cos(a1) * radius, cy + math.sin(a1) * radius)
        local lit = (i + 0.5) / segments <= fraction
        drawList:AddLine(p0, p1, lit and color32 or packColor(255, 255, 255, 0.09), thickness)
    end
end

function ui.recentChart(w, h)
    local list = history.recent
    local p = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    imgui.Dummy(imgui.ImVec2(w, h))
    if #list == 0 then
        drawList:AddText(imgui.ImVec2(p.x, p.y + h / 2 - 8), packColor(140, 148, 165, 1), '\208\159\208\190\208\186\208\176 \208\189\208\181\209\130 \208\180\208\176\208\189\208\189\209\139\209\133')
        return
    end
    local n = math.min(#list, 24)
    local maxv = 1
    for i = 1, n do maxv = math.max(maxv, list[i].v) end
    local gap = 4
    local bw = (w - gap * (n - 1)) / n
    local mp = imgui.GetMousePos()
    local hovered
    for i = 1, n do
        local e = list[n - i + 1]
        local bh = math.max(3, (h - 4) * e.v / maxv)
        local x0 = p.x + (i - 1) * (bw + gap)
        local c = KIND[e.k] and KIND[e.k].c or {255, 255, 255}
        local hov = mp.x >= x0 and mp.x <= x0 + bw and mp.y >= p.y and mp.y <= p.y + h
        drawList:AddRectFilled(imgui.ImVec2(x0, p.y + h - bh), imgui.ImVec2(x0 + bw, p.y + h),
            packColor(c[1], c[2], c[3], hov and 1 or 0.75), 3)
        if hov then hovered = e end
    end
    if hovered then
        imgui.SetTooltip('+' .. fmt(hovered.v) .. ' \209\128\209\131\208\177. - ' .. (KIND[hovered.k] and KIND[hovered.k].name or ''))
    end
end

function ui.daysChart(w, h)
    local keys = last7()
    local vals, maxv = {}, 1
    for i, k in ipairs(keys) do
        local d = stats.days[k]
        vals[i] = d and (d.money or 0) or 0
        maxv = math.max(maxv, vals[i])
    end
    if cfg.goal.enabled and cfg.goal.amount > 0 then maxv = math.max(maxv, cfg.goal.amount) end

    local p = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    imgui.Dummy(imgui.ImVec2(w, h + 22))
    local gap = 14
    local bw = (w - gap * 6) / 7
    local mp = imgui.GetMousePos()
    local hoveredIndex

    for i = 1, 7 do
        local x0 = p.x + (i - 1) * (bw + gap)
        local bh = math.max(3, (h - 20) * vals[i] / maxv)
        local top = p.y + h - bh
        local hov = mp.x >= x0 and mp.x <= x0 + bw and mp.y >= p.y and mp.y <= p.y + h + 20
        local alpha = (i == 7) and 1 or (hov and 0.9 or 0.45)
        drawList:AddRectFilled(imgui.ImVec2(x0, top), imgui.ImVec2(x0 + bw, p.y + h), accentColor32(alpha), 4)
        if vals[i] > 0 then
            local text = fmtShort(vals[i])
            drawList:AddText(imgui.ImVec2(x0 + bw / 2 - imgui.CalcTextSize(text).x / 2, math.max(p.y, top - 18)),
                packColor(232, 235, 242, 1), text)
        end
        local label = keys[i]:sub(9, 10) .. '.' .. keys[i]:sub(6, 7)
        drawList:AddText(imgui.ImVec2(x0 + bw / 2 - imgui.CalcTextSize(label).x / 2, p.y + h + 4), packColor(140, 148, 165, 1), label)
        if hov then hoveredIndex = i end
    end

    if cfg.goal.enabled and cfg.goal.amount > 0 then
        local gy = p.y + h - (h - 20) * cfg.goal.amount / maxv
        drawList:AddLine(imgui.ImVec2(p.x, gy), imgui.ImVec2(p.x + w, gy), packColor(72, 205, 130, 0.7), 1)
    end
    if hoveredIndex then
        local d = stats.days[keys[hoveredIndex]]
        imgui.SetTooltip(string.format('%s: %s \209\128\209\131\208\177.', keys[hoveredIndex], fmt(d and d.money or 0)))
    end
end

local function listBegin(id, height, width)
    beginChild(id, imgui.ImVec2(width or 0, height), true)
end

local function listEnd()
    if imgui.IsWindowHovered() and imgui.GetScrollMaxY() > 0 then UI.wheelConsumed = true end
    endChild()
end

function ui.hoursChart(w, h, hours)
    local p = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    imgui.Dummy(imgui.ImVec2(w, h + 20))
    local maxv = 1
    for hour = 0, 23 do
        local r = hours[tostring(hour)]
        if r then maxv = math.max(maxv, r.m) end
    end
    local gap = 3
    local bw = (w - gap * 23) / 24
    local mp = imgui.GetMousePos()
    local hovered
    for hour = 0, 23 do
        local r = hours[tostring(hour)] or {m = 0, t = 0, c = 0}
        local x0 = p.x + hour * (bw + gap)
        local bh = r.m > 0 and math.max(3, (h - 6) * r.m / maxv) or 2
        local hov = mp.x >= x0 and mp.x <= x0 + bw and mp.y >= p.y and mp.y <= p.y + h + 18
        local color = r.m > 0 and accentColor32(hov and 1 or 0.75) or packColor(255, 255, 255, hov and 0.22 or 0.08)
        drawList:AddRectFilled(imgui.ImVec2(x0, p.y + h - bh), imgui.ImVec2(x0 + bw, p.y + h), color, 2)
        if hour % 3 == 0 then
            drawList:AddText(imgui.ImVec2(x0, p.y + h + 4), packColor(140, 148, 165, 1), tostring(hour))
        end
        if hov then hovered = hour end
    end
    if hovered then
        local r = hours[tostring(hovered)] or {m = 0, t = 0, c = 0}
        imgui.SetTooltip(string.format('%02d:00 - %02d:00\n\208\148\208\190\209\133\208\190\208\180: %s \209\128\209\131\208\177.\n\208\160\208\181\208\185\209\129\208\190\208\178: %d\n\208\155\208\176\209\128\209\134\208\181\208\178: %d',
            hovered, (hovered + 1) % 24, fmt(r.m), r.t or 0, r.c or 0))
    end
end

local function skillTripsLeft()
    local skill = stats.skill
    local sum, count = 0, 0
    for _, gain in ipairs(skill.gains or {}) do sum = sum + gain count = count + 1 end
    local gain = count > 0 and sum / count or (skill.gain or 0)
    if gain > 0 and (skill.maxExp or 0) > (skill.exp or 0) then
        return math.ceil((skill.maxExp - skill.exp) / gain)
    end
    return nil
end

local function estimatedTotal()
    return totalMoney() + stats.chests.total * cfg.value.chest + stats.eternal.total * cfg.value.eternal
end

function ui.link(text, tip)
    local p = imgui.GetCursorScreenPos()
    local size = imgui.CalcTextSize(text)
    local clicked = imgui.InvisibleButton('##link' .. text, imgui.ImVec2(size.x, size.y))
    local hovered = imgui.IsItemHovered()
    local drawList = imgui.GetWindowDrawList()
    local color = hovered and accentColor32(1) or packColor(110, 168, 255, 1)
    drawList:AddText(p, color, text)
    if hovered then
        drawList:AddLine(imgui.ImVec2(p.x, p.y + size.y), imgui.ImVec2(p.x + size.x, p.y + size.y), color, 1)
        imgui.SetTooltip(tip)
    end
    return clicked
end

function ui.para(text, width, color)
    imgui.PushTextWrapPos(UI.groupX + width)
    if color then imgui.TextColored(color, text) else imgui.Text(text) end
    imgui.PopTextWrapPos()
end

function ui.goalPrompt(iw)
    local round = stats.goalRound
    if not (cfg.goal.enabled and round.done) then return end
    local height = UI.goalEdit and 132 or 88
    ui.cardBegin(iw, height)
    ui.iconText('trophy', '\208\166\208\181\208\187\209\140 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176!', GREEN, GREEN, 26)
    imgui.TextColored(DIM, '\208\157\208\176\209\135\208\176\209\130\209\140 \208\183\208\176\208\189\208\190\208\178\208\190 \209\129 \209\130\208\190\208\185 \208\182\208\181 \209\129\209\131\208\188\208\188\208\190\208\185 \208\184\208\187\208\184 \208\191\208\190\209\129\209\130\208\176\208\178\208\184\209\130\209\140 \208\189\208\190\208\178\209\131\209\142 \209\134\208\181\208\187\209\140?')
    local bw = math.floor((iw - 24 - 8) / 2)
    if ui.coloredButton('\208\157\208\176\209\135\208\176\209\130\209\140 \208\183\208\176\208\189\208\190\208\178\208\190##goal_restart', bw, 28, 72, 205, 130) then
        UI.goalEdit = false
        Data.goalRestart()
    end
    imgui.SameLine(0, 8)
    if ui.coloredButton('\208\157\208\190\208\178\208\176\209\143 \209\134\208\181\208\187\209\140##goal_new', bw, 28, ACC.r, ACC.g, ACC.b) then
        UI.goalEdit = true
        UI.goalInput = imgui.ImInt(cfg.goal.amount)
    end
    if UI.goalEdit and UI.goalInput then
        imgui.PushItemWidth(180)
        imgui.InputInt('\209\128\209\131\208\177. \208\178 \208\180\208\181\208\189\209\140##goal_amount', UI.goalInput, 100000, 500000)
        imgui.PopItemWidth()
        imgui.SameLine(0, 8)
        if imgui.Button('\208\147\208\190\209\130\208\190\208\178\208\190##goal_ok', imgui.ImVec2(90, 26)) then
            UI.goalEdit = false
            Data.goalSet(UI.goalInput.v)
        end
    end
    ui.cardEnd()
    imgui.Spacing()
end

local OVERLAY_WIDTH = 300

local function finishOverlayEdit(save)
    if not UI.overlayEdit then return end
    UI.overlayEdit = false
    if save then
        mark('settings')
        say('\208\159\208\190\208\187\208\190\208\182\208\181\208\189\208\184\208\181 \208\190\208\178\208\181\209\128\208\187\208\181\209\143 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\208\190.')
    elseif UI.overlayRestore then
        cfg.overlay.x, cfg.overlay.y = UI.overlayRestore.x, UI.overlayRestore.y
    end
end

local function startOverlayEdit()
    UI.overlayEdit, UI.overlayFirst = true, true
    UI.overlayRestore = {x = cfg.overlay.x, y = cfg.overlay.y}
    menu.v = false
    UI.menuTarget, UI.menuAlpha = 0, 0
end

local function drawOverlay()
    local o = cfg.overlay
    local visible = o.show
    local scale = o.scale
    local padding = 12
    local width = math.floor(OVERLAY_WIDTH * scale)
    local iconColumn = 24 * scale
    local editing = UI.overlayEdit

    pushVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(padding, padding))
    pushVar(imgui.StyleVar.WindowRounding, 10)
    pushCol(imgui.Col.WindowBg, imgui.ImVec4(0.050, 0.058, 0.082, o.opacity))
    pushFont(fonts.main)

    if not editing or UI.overlayFirst then
        local sx, sy = imgui.MB.res()
        imgui.SetNextWindowPos(imgui.ImVec2(math.max(0, math.min(sx - width, o.x)), math.max(0, math.min(sy - 80, o.y))), imgui.Cond.Always)
        UI.overlayFirst = false
    end

    local flags = ui.wflags('NoTitleBar', 'NoResize', 'AlwaysAutoResize', 'NoScrollbar', 'NoSavedSettings',
                            'NoFocusOnAppearing', 'NoBringToFrontOnFocus')
    if not editing then flags = flags + ui.wflags('NoMove') end

    beginWin('##th_overlay', nil, flags)
    imgui.SetWindowFontScale(scale)
    imgui.Dummy(imgui.ImVec2(width - padding * 2, 0))

    pushFont(fonts.title)
    ui.iconText('truck', 'TRUCK HELPER', nil, nil, iconColumn)
    popFont(fonts.title)
    if visible.session then
        local clock = fmtDur(os.time() - session.start)
        imgui.SameLine(width - padding - imgui.CalcTextSize(clock).x)
        imgui.TextColored(DIM, clock)
    end
    imgui.Separator()

    local function row(iconName, label, value, color)
        ui.iconText(iconName, label, color, DIM, iconColumn)
        imgui.SameLine(width - padding - imgui.CalcTextSize(value).x)
        imgui.Text(value)
    end

    if visible.total  then row('coins',    '\208\151\208\176 \208\189\208\181\208\180\208\181\208\187\209\142',  fmt(totalMoney()) .. ' \209\128\209\131\208\177.',       accentColor()) end
    if visible.truck  then row('users',    KIND.truck.name, fmt(stats.truck.total) .. ' \209\128\209\131\208\177.', kindColor('truck')) end
    if visible.car    then row('car',      '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129', fmt(stats.car.total) .. ' \209\128\209\131\208\177.',    kindColor('car')) end
    if visible.other  then row('wallet',   '\208\159\209\128\208\190\209\135\208\184\208\181',     fmt(stats.other.total) .. ' \209\128\209\131\208\177.',  kindColor('other')) end
    if visible.trips then
        local last = history.orders[1]
        local tail = (last and last.result == 'done' and last.paid > 0) and (' (+' .. fmtShort(last.paid) .. ')') or ''
        row('check', '\208\160\208\181\208\185\209\129\209\139', stats.orders.done .. tail, kindColor('truck'))
    end
    if visible.chests then
        local worth = cfg.value.chest > 0 and (' (' .. fmtShort(stats.chests.total * cfg.value.chest) .. ')') or ''
        row('gift', '\208\155\208\176\209\128\209\134\209\139', stats.chests.total .. ' \209\136\209\130.' .. worth, kindColor('chests'))
    end
    if visible.items then
        local temp = stats.items.total - stats.eternal.total
        row('star', '\208\146\209\128\208\181\208\188. \208\180\208\184\208\178.', temp .. ' \209\136\209\130. (' .. fmtShort(temp * cfg.value.tempHour) .. '/\209\135)', kindColor('items'))
        local worth = cfg.value.eternal > 0 and (' (' .. fmtShort(stats.eternal.total * cfg.value.eternal) .. ')') or ''
        row('star', '\208\146\208\181\209\135\208\189. \208\180\208\184\208\178.', stats.eternal.total .. ' \209\136\209\130.' .. worth, rgba(255, 214, 10))
    end
    if visible.today  then row('calendar', '\208\161\208\181\208\179\208\190\208\180\208\189\209\143',    '+' .. fmt(todayMoney()) .. ' \209\128\209\131\208\177.', GREEN) end
    if visible.hourly then
        row('bolt', '\208\146 \209\135\208\176\209\129', hourlyText(), accentColor())
        local net = hourlyNetText()
        if net then row('bolt', '\208\167\208\184\209\129\209\130\209\139\208\188\208\184 \208\178 \209\135\208\176\209\129', net, GREEN) end
    end
    if visible.expenses and stats.expenses.total > 0 then
        row('warn', '\208\160\208\176\209\129\209\133\208\190\208\180\209\139', '-' .. fmt(stats.expenses.total) .. ' \209\128\209\131\208\177.', RED)
    end
    if visible.skill and stats.skill.level > 0 then
        row('trophy', '\208\163\209\128\208\190\208\178\208\181\208\189\209\140', stats.skill.level .. ' (' .. stats.skill.exp .. '/' .. stats.skill.maxExp .. ')', kindColor('items'))
        local left = skillTripsLeft()
        if left then imgui.TextColored(DIM, '\208\180\208\190 \209\129\208\187\208\181\208\180. \209\131\209\128\208\190\208\178\208\189\209\143 ~' .. left .. ' ' .. plural(left, '\209\128\208\181\208\185\209\129', '\209\128\208\181\208\185\209\129\208\176', '\209\128\208\181\208\185\209\129\208\190\208\178')) end
    end
    if visible.promo and stats.promo.percent > 0 and stats.promo.endsAt > os.time() then
        row('bullhorn', '\208\144\208\186\209\134\208\184\209\143 +' .. string.format('%g', stats.promo.percent) .. '%', leftText(stats.promo.endsAt - os.time()), GREEN)
    end
    if visible.salary and stats.salary.percent > 0 then
        row(stats.salary.other and 'coins' or 'shield', stats.salary.other and '\208\145\208\190\208\189\209\131\209\129 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139' or '\208\145\208\190\208\189\209\131\209\129 \208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186\208\176', '+' .. string.format('%g', stats.salary.percent) .. '%', GREEN)
    end
    if visible.salary and stats.salary.penalty > 0 then
        row('warn', stats.salary.penaltyReason == '\208\189\208\181\209\130 \208\182\208\184\208\187\209\140\209\143' and '\208\168\209\130\209\128\208\176\209\132: \208\189\208\181\209\130 \208\182\208\184\208\187\209\140\209\143' or '\208\168\209\130\209\128\208\176\209\132 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139', '-' .. string.format('%g', stats.salary.penalty) .. '%', RED)
    end
    if visible.hp then
        local hp = vehicleHealth()
        if hp then row('car', '\208\161\208\190\209\129\209\130\208\190\209\143\208\189\208\184\208\181 \209\130/\209\129', math.floor(hp) .. ' HP', kindColor('car')) end
    end

    if visible.goal and cfg.goal.enabled and cfg.goal.amount > 0 then
        local fraction = goalProgress() / cfg.goal.amount
        local percent = math.floor(math.min(fraction, 9.99) * 100) .. '%'
        row('target', '\208\166\208\181\208\187\209\140 \208\180\208\189\209\143', percent, fraction >= 1 and GREEN or accentColor())
        ui.progressBar(fraction, width - padding * 2, 6 * scale)
    end

    if visible.order then
        local info = Orders.activeInfo(os.clock())
        if info then
            imgui.Separator()
            row('truck', plain(info.order.customer), fmt(info.order.payout) .. ' \209\128\209\131\208\177.', kindColor('truck'))
            if info.delivered then
                imgui.TextColored(GREEN, '\209\129\208\180\208\176\208\189, \209\129\209\135\208\184\209\130\208\176\209\142 \208\178\209\139\208\191\208\187\208\176\209\130\209\131')
            elseif info.arrived then
                imgui.TextColored(GREEN, '\208\189\208\176 \208\188\208\181\209\129\209\130\208\181, \208\182\208\180\209\131 \208\178\209\139\208\191\208\187\208\176\209\130\209\131')
            else
                local timeText = info.left and ('\208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 ' .. fmtMinSec(info.left)) or '\209\130\208\176\208\185\208\188\208\181\209\128 \208\189\208\181 \208\191\208\190\208\187\209\131\209\135\208\181\208\189'
                imgui.TextColored(DIM, timeText .. ' | \208\181\209\137\209\145 ~' .. string.format('%.1f', info.remainingKm) .. ' \208\186\208\188')
                local labels = {ok = '\209\131\209\129\208\191\208\181\208\178\208\176\208\181\209\130\208\181', risk = '\208\157\208\149 \208\163\208\161\208\159\208\149\208\146\208\144\208\149\208\162\208\149', late = '\208\178\209\128\208\181\208\188\209\143 \208\178\209\139\209\136\208\187\208\190'}
                imgui.TextColored(info.status == 'ok' and GREEN or RED, labels[info.status])
            end
        end
    end

    local age = os.clock() - flash.t
    if age < 5 then
        local alpha = age < 3.5 and 1 or (5 - age) / 1.5
        local color = kindColor(flash.kind, alpha)
        ui.iconText('bolt', flash.text, color, color, iconColumn)
    end

    local saveNow, cancelNow = false, false
    if editing then
        imgui.Separator()
        imgui.TextColored(accentColor(), '\208\159\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\208\181 \208\190\208\178\208\181\209\128\208\187\208\181\208\185 \208\191\208\176\208\187\209\140\209\134\208\181\208\188')
        if imgui.Button('-##ov_minus', imgui.ImVec2(30, 26)) then o.scale = math.max(0.6, o.scale - 0.05) mark('settings') end
        imgui.SameLine(0, 6)
        if imgui.Button('+##ov_plus', imgui.ImVec2(30, 26)) then o.scale = math.min(2.5, o.scale + 0.05) mark('settings') end
        if imgui.Button('\208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140##ov_save', imgui.ImVec2(math.floor(width / 2 - padding - 4), 26)) then saveNow = true end
        imgui.SameLine(0, 8)
        if imgui.Button('\208\158\209\130\208\188\208\181\208\189\208\176##ov_cancel', imgui.ImVec2(math.floor(width / 2 - padding - 4), 26)) then cancelNow = true end
    end

    local winPos, winSize = imgui.GetWindowPos(), imgui.GetWindowSize()
    imgui.GetWindowDrawList():AddRectFilled(imgui.ImVec2(winPos.x, winPos.y + 12),
        imgui.ImVec2(winPos.x + 3, winPos.y + winSize.y - 12), accentColor32(1), 2)
    if editing then o.x, o.y = winPos.x, winPos.y end

    endWin()
    popFont(fonts.main)
    popCol(1)
    popVar(2)

    if cancelNow then finishOverlayEdit(false) elseif saveNow then finishOverlayEdit(true) end
end

do
local CARD_WIDTH = 370
Orders.CARD_WIDTH = CARD_WIDTH
local orderCard = {alpha = 0, lastFrame = os.clock(), entry = nil}

function Orders.cardAlpha() return orderCard.alpha end

function Orders.drawCard()
    local now = os.clock()
    local entry = Orders.cardStatus(now)
    if not entry and Orders.lastReason == 'none' and cfg.orders.showEmpty then entry = Orders.emptyEntry(now) end
    local step = math.min(0.1, now - orderCard.lastFrame) / 0.25
    orderCard.lastFrame = now
    if entry then orderCard.entry = entry end
    if entry then orderCard.alpha = math.min(1, orderCard.alpha + step) else orderCard.alpha = math.max(0, orderCard.alpha - step) end
    if orderCard.alpha <= 0.01 then orderCard.entry = nil orderCard.alpha = 0 return end

    local editing = Orders.state.editing
    local e = orderCard.entry
    local order = e.row and e.row.order
    local scale = cfg.orders.scale
    local width = math.floor(CARD_WIDTH * scale)
    local pad = 12
    local sx, sy = imgui.MB.res()

    pushVar(imgui.StyleVar.Alpha, orderCard.alpha)
    pushVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(pad, pad))
    pushVar(imgui.StyleVar.WindowRounding, 10)
    pushCol(imgui.Col.WindowBg, imgui.ImVec4(0.050, 0.058, 0.082, 0.96))
    pushFont(fonts.main)

    if not editing or Orders.state.editFirst then
        local x = sx * cfg.orders.x / 100 - width / 2
        local y = sy * cfg.orders.y / 100 + (editing and 0 or (1 - orderCard.alpha) * 14)
        x = math.max(0, math.min(sx - width, x))
        y = math.max(0, math.min(sy - 200 * scale, y))
        imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.Always)
        Orders.state.editFirst = false
    end
    local flags = ui.wflags('NoTitleBar', 'NoResize', 'AlwaysAutoResize', 'NoScrollbar', 'NoSavedSettings',
        'NoFocusOnAppearing', 'NoBringToFrontOnFocus')
    if not editing then flags = flags + ui.wflags('NoMove', 'NoInputs') end
    beginWin('##th_order_card', nil, flags)
    imgui.SetWindowFontScale(scale)
    imgui.Dummy(imgui.ImVec2(width - pad * 2, 0))

    if e.empty then
        pushFont(fonts.title)
        ui.iconText('warn', '\208\157\208\181\209\130 \208\191\208\190\208\180\209\133\208\190\208\180\209\143\209\137\208\184\209\133 \208\183\208\176\208\186\208\176\208\183\208\190\208\178', accentColor(), nil, 26)
        popFont(fonts.title)
        imgui.Separator()
        for _, line in ipairs(e.lines) do imgui.Text(line) end
        imgui.TextColored(DIM, '\208\146\209\129\208\181\208\179\208\190 \208\178 \209\129\208\191\208\184\209\129\208\186\208\181: ' .. e.total)
        imgui.TextColored(DIM, '\208\159\209\128\208\190\208\178\208\181\209\128\209\140\209\130\208\181 \208\178\208\186\208\187\208\176\208\180\208\186\209\131 "\208\151\208\176\208\186\208\176\208\183\209\139": Tier \208\184 \208\179\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\209\145\208\188\208\189\208\190\209\129\209\130\209\140')
    else
        local title = e.great and '\208\154\209\128\209\131\209\130\208\190\208\185 \208\183\208\176\208\186\208\176\208\183' or '\208\155\209\131\209\135\209\136\208\184\208\185 \208\183\208\176\208\186\208\176\208\183'
        if e.demo then title = title .. ' (\208\191\209\128\208\184\208\188\208\181\209\128)' end
        pushFont(fonts.title)
        ui.iconText('bolt', title, e.great and GREEN or accentColor(), nil, 26)
        popFont(fonts.title)
        if order.category ~= '' then
            imgui.SameLine(width - pad - imgui.CalcTextSize(order.category).x)
            imgui.TextColored(DIM, order.category)
        end
        imgui.Separator()

        local customer = plain(order.customer)
        if order.urgent then customer = '[\208\161\209\128\208\190\209\135\208\189\208\190] ' .. customer end
        imgui.Text(customer)
        imgui.TextColored(DIM, plain(order.cargo) .. ', ' .. fmt(order.weight) .. ' \208\186\208\179' .. (order.tier and (', Tier ' .. order.tier) or ''))
        imgui.Text(fmt(order.payout) .. ' \209\128\209\131\208\177.')
        local distance = string.format('%.1f \208\186\208\188', order.km)
        imgui.SameLine(width - pad - imgui.CalcTextSize(distance).x)
        imgui.TextColored(DIM, distance)
        imgui.TextColored(GREEN, fmt(order.payout / math.max(order.km, 0.1)) .. ' \209\128\209\131\208\177./\208\186\208\188')
        local timeText = '\208\178\209\128\208\181\208\188\209\143 ' .. fmtMinSec(e.row.timeLeft) .. ' | \209\133\209\128\209\131\208\191\208\186\208\190\209\129\209\130\209\140 ' .. order.fragility .. '%'
        imgui.SameLine(width - pad - imgui.CalcTextSize(timeText).x)
        imgui.TextColored(DIM, timeText)

        imgui.Separator()
        if e.closed then
            imgui.TextColored(DIM, '\208\190\208\186\208\189\208\190 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\183\208\176\208\186\209\128\209\139\209\130\208\190')
        else
            local mob = Orders.state.mobile
            if not mob then
                imgui.TextColored(accentColor(), '[' .. Orders.keyName(cfg.orders.key) .. ']')
                imgui.SameLine(0, 8)
                imgui.Text('\208\178\208\183\209\143\209\130\209\140 \209\141\209\130\208\190\209\130 \208\183\208\176\208\186\208\176\208\183')
            end
            local criterion = cfg.orders.mode == 'total' and '\208\191\208\190 \209\128\208\176\208\183\208\188\208\181\209\128\209\131 \208\191\209\128\208\181\208\188\208\184\208\184' or '\208\191\208\190 \209\128\209\131\208\177./\208\186\208\188'
            if mob then
                imgui.TextColored(DIM, criterion)
            else
                imgui.SameLine(width - pad - imgui.CalcTextSize(criterion).x)
                imgui.TextColored(DIM, criterion)
            end
        end

    end

    local saveNow, cancelNow = false, false
    if editing then
        imgui.Separator()
        imgui.TextColored(accentColor(), '\208\159\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\208\181 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131 \208\191\208\176\208\187\209\140\209\134\208\181\208\188, \209\128\208\176\208\183\208\188\208\181\209\128 - \208\186\208\189\208\190\208\191\208\186\208\176\208\188\208\184')
        if imgui.Button('-##card_minus', imgui.ImVec2(30, 26)) then cfg.orders.scale = math.max(0.5, cfg.orders.scale - 0.05) end
        imgui.SameLine(0, 6)
        if imgui.Button('+##card_plus', imgui.ImVec2(30, 26)) then cfg.orders.scale = math.min(2.5, cfg.orders.scale + 0.05) end
        imgui.SameLine(0, 6)
        local bw = math.floor((width - pad * 2 - 30 * 2 - 6 * 3) / 2)
        if imgui.Button('\208\161\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140##card_save', imgui.ImVec2(bw, 26)) then saveNow = true end
        imgui.SameLine(0, 6)
        if imgui.Button('\208\158\209\130\208\188\208\181\208\189\208\176##card_cancel', imgui.ImVec2(bw, 26)) then cancelNow = true end
    end

    local winPos, winSize = imgui.GetWindowPos(), imgui.GetWindowSize()
    if editing then
        cfg.orders.x = math.max(0, math.min(100, (winPos.x + winSize.x / 2) / sx * 100))
        cfg.orders.y = math.max(0, math.min(100, winPos.y / sy * 100))
    end
    imgui.GetWindowDrawList():AddRectFilled(imgui.ImVec2(winPos.x, winPos.y + 12),
        imgui.ImVec2(winPos.x + 3, winPos.y + winSize.y - 12), accentColor32(orderCard.alpha), 2)
    endWin()
    popFont(fonts.main)
    popCol(1)
    popVar(3)

    if cancelNow then Orders.stopEdit(false) elseif saveNow then Orders.stopEdit(true) end
end
end

local function cardWidth(iw, count, gap) return math.floor((iw - gap * (count - 1)) / count) end

local function goalTexts()
    local goal = cfg.goal.amount
    local today = goalProgress()
    local fraction = goal > 0 and today / goal or 0
    return goal, today, fraction
end

local function goalStreak()
    if not cfg.goal.enabled or cfg.goal.amount <= 0 then return 0 end
    local now = os.date('*t')
    now.hour, now.min, now.sec = 12, 0, 0
    local base = os.time(now)
    local count = 0
    for i = 0, 44 do
        local d = stats.days[os.date('%Y-%m-%d', base - i * 86400)]
        local reached = d and (d.money or 0) >= cfg.goal.amount
        if reached then count = count + 1 elseif i > 0 then break end
    end
    return count
end

local function goalForecast(remaining)
    local rates = hourlyRates()
    if not rates or rates.gross <= 0 then return '\208\191\209\128\208\190\208\179\208\189\208\190\208\183 \208\191\208\190\209\143\208\178\208\184\209\130\209\129\209\143 \208\191\208\190\209\129\208\187\208\181 10 \208\188\208\184\208\189\209\131\209\130 \209\128\208\176\208\177\208\190\209\130\209\139' end
    local minutes = math.ceil(remaining / rates.gross * 60)
    if minutes >= 600 then return '\208\191\209\128\208\184 \209\130\208\176\208\186\208\190\208\188 \209\130\208\181\208\188\208\191\208\181 \209\134\208\181\208\187\209\140 \208\189\208\181 \208\178\209\139\208\191\208\190\208\187\208\189\208\184\209\130\209\140' end
    local text = minutes < 60 and (minutes .. ' \208\188\208\184\208\189') or (math.floor(minutes / 60) .. ' \209\135 ' .. minutes % 60 .. ' \208\188\208\184\208\189')
    return '\208\191\209\128\208\184 ' .. fmtShort(rates.gross) .. ' \208\178 \209\135\208\176\209\129 \209\134\208\181\208\187\209\140 \209\135\208\181\209\128\208\181\208\183 ' .. text
end

function pages.dashboard(iw)
    ui.pageTitle('home', '\208\158\208\177\208\183\208\190\209\128')
    local week = Data.weekInfo()
    if week.lastDay then
        ui.cardBegin(iw, 56)
        ui.iconText('warn', '\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185 \208\180\208\181\208\189\209\140 \208\189\208\181\208\180\208\181\208\187\208\184 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\184', RED, RED, 24)
        imgui.TextColored(DIM, '\208\146 \208\191\208\190\208\187\208\189\208\190\209\135\209\140 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \209\129\208\177\209\128\208\190\209\129\208\184\209\130\209\129\209\143. \208\152\209\130\208\190\208\179\208\184 \208\189\208\181\208\180\208\181\208\187\208\184 \209\129\208\190\209\133\209\128\208\176\208\189\209\142 \208\178 \208\176\209\128\209\133\208\184\208\178.')
        ui.cardEnd()
        imgui.Spacing()
    end
    ui.goalPrompt(iw)
    local promo = stats.promo
    if cfg.track.promo and promo.percent > 0 and promo.endsAt > os.time() then
        ui.cardBegin(iw, 56)
        ui.iconText('bullhorn', '\208\144\208\186\209\134\208\184\209\143 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\181 "' .. promo.job .. '": +' .. string.format('%g', promo.percent) .. '% \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181', GREEN, nil, 26)
        imgui.TextColored(DIM, '\208\148\208\190 \208\183\208\176\208\178\208\181\209\128\209\136\208\181\208\189\208\184\209\143: ' .. leftText(promo.endsAt - os.time()))
        ui.cardEnd()
        imgui.Spacing()
    end

    local gap = 10
    imgui.TextColored(DIM, '\208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\189\208\190 \208\183\208\176 \208\189\208\181\208\180\208\181\208\187\209\142')
    pushFont(fonts.big)
    imgui.Text(fmt(totalMoney()) .. ' \209\128\209\131\208\177.')
    popFont(fonts.big)
    imgui.TextColored(DIM, '\208\161\208\181\208\179\208\190\208\180\208\189\209\143')
    imgui.SameLine(0, 6)
    imgui.TextColored(GREEN, '+' .. fmt(todayMoney()) .. ' \209\128\209\131\208\177.')
    imgui.SameLine(0, 20)
    imgui.TextColored(DIM, '\208\161 \209\131\209\135\209\145\209\130\208\190\208\188 \208\187\208\176\209\128\209\134\208\190\208\178 \208\184 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\190\208\178')
    imgui.SameLine(0, 6)
    imgui.TextColored(accentColor(), fmt(estimatedTotal()) .. ' \209\128\209\131\208\177.')
    imgui.SameLine(0, 6)
    ui.help('\208\158\209\134\208\181\208\189\208\186\208\176', '\208\146\208\176\209\136\208\184 \208\180\208\181\208\189\209\140\208\179\208\184 \208\191\208\187\209\142\209\129 \208\191\209\128\208\184\208\188\208\181\209\128\208\189\208\176\209\143 \209\129\209\130\208\190\208\184\208\188\208\190\209\129\209\130\209\140 \208\187\208\176\209\128\209\134\208\190\208\178 \208\184 \208\178\208\181\209\135\208\189\209\139\209\133 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\190\208\178. \208\166\208\181\208\189\209\139 \208\178\209\139 \208\183\208\176\208\180\208\176\209\145\209\130\208\181 \208\189\208\176 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 \194\171\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139\194\187.')
    imgui.Spacing()

    local cw = cardWidth(iw, 4, gap)
    for i, kind in ipairs({'truck', 'car', 'other', 'chests'}) do
        local info = KIND[kind]
        local value = kind == 'chests' and tostring(stats.chests.total) or fmt(stats[kind].total)
        ui.statCard(info.icon, info.short or info.name, value, kind == 'chests' and '\209\136\209\130.' or '\209\128\209\131\208\177.', info.c, cw, 92)
        if i < 4 then imgui.SameLine(0, gap) end
    end
    imgui.Spacing()

    local hw = cardWidth(iw, 2, gap)
    local inner = hw - 24
    ui.cardBegin(hw, 236)
    ui.iconText('stopwatch', '\208\161\208\181\209\129\209\129\208\184\209\143')
    imgui.SameLine(0, 8)
    ui.help('\208\161\208\181\209\129\209\129\208\184\209\143', '\194\171\208\146 \209\135\208\176\209\129\194\187 - \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\181\209\130\208\181 \208\178 \209\135\208\176\209\129 \208\183\208\176 \209\141\209\130\209\131 \208\184\208\179\209\128\209\131. \208\159\209\128\208\190\209\129\209\130\208\190\208\185 \208\189\208\181 \209\129\209\135\208\184\209\130\208\176\208\181\209\130\209\129\209\143. \208\167\208\184\209\129\208\187\208\190 \208\191\208\190\209\143\208\178\208\187\209\143\208\181\209\130\209\129\209\143 \209\135\208\181\209\128\208\181\208\183 10 \208\188\208\184\208\189\209\131\209\130 \209\128\208\176\208\177\208\190\209\130\209\139.')
    imgui.Spacing()
    ui.labelValue('\208\146\209\128\208\181\208\188\209\143', fmtDur(os.time() - session.start), nil, inner)
    ui.labelValue('\208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\189\208\190', '+' .. fmt(session.money) .. ' \209\128\209\131\208\177.', GREEN, inner)
    ui.labelValue('\208\146 \209\135\208\176\209\129', hourlyText(), accentColor(), inner)
    ui.labelValue('\208\160\208\181\208\185\209\129\208\190\208\178', tostring(session.trips or 0), kindColor('truck'), inner)
    ui.labelValue('\208\155\208\176\209\128\209\134\208\190\208\178', tostring(session.chests), kindColor('chests'), inner)
    ui.labelValue('\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\190\208\178 (\208\178\209\128\208\181\208\188. / \208\178\208\181\209\135\208\189.)', (session.items - (session.eternal or 0)) .. ' / ' .. (session.eternal or 0), kindColor('items'), inner)
    ui.labelValue('\208\160\208\176\209\129\209\133\208\190\208\180\209\139', '-' .. fmt(session.expense) .. ' \209\128\209\131\208\177.', RED, inner)
    ui.cardEnd()

    imgui.SameLine(0, gap)

    local goal, today, fraction = goalTexts()
    ui.cardBegin(hw, 236)
    ui.iconText('target', '\208\166\208\181\208\187\209\140 \208\180\208\189\209\143')
    imgui.SameLine(0, 8)
    ui.help('\208\148\208\189\208\181\208\178\208\189\208\176\209\143 \209\134\208\181\208\187\209\140', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\178\209\139 \209\133\208\190\209\130\208\184\209\130\208\181 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\209\130\209\140 \208\183\208\176 \208\180\208\181\208\189\209\140. \208\156\208\181\208\189\209\143\208\181\209\130\209\129\209\143 \208\189\208\176 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 \194\171\208\144\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\176\194\187.')
    imgui.Spacing()
    if cfg.goal.enabled and goal > 0 then
        local p = imgui.GetCursorScreenPos()
        local color = fraction >= 1 and packColor(72, 205, 130, 1) or accentColor32(1)
        ui.ring(p.x + 44, p.y + 44, 36, 7, fraction, color)
        local percent = math.floor(fraction * 100) .. '%'
        pushFont(fonts.title)
        local ts = imgui.CalcTextSize(percent)
        imgui.GetWindowDrawList():AddText(imgui.ImVec2(p.x + 44 - ts.x / 2, p.y + 44 - ts.y / 2), packColor(232, 235, 242, 1), percent)
        popFont(fonts.title)
        imgui.SetCursorScreenPos(imgui.ImVec2(p.x + 100, p.y + 4))
        imgui.BeginGroup()
        imgui.TextColored(DIM, '\208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\189\208\190')
        imgui.Text(fmt(today) .. ' \209\128\209\131\208\177.')
        imgui.TextColored(DIM, '\208\166\208\181\208\187\209\140')
        imgui.Text(fmt(goal) .. ' \209\128\209\131\208\177.')
        imgui.EndGroup()
        imgui.SetCursorScreenPos(imgui.ImVec2(p.x, p.y + 96))
        ui.labelValue(fraction >= 1 and '\208\146\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176' or '\208\158\209\129\209\130\208\176\208\187\208\190\209\129\209\140', fraction >= 1 and '\208\158\209\130\208\187\208\184\209\135\208\189\208\190!' or (fmt(goal - today) .. ' \209\128\209\131\208\177.'),
            fraction >= 1 and GREEN or accentColor(), inner)
        ui.labelValue('\208\161\208\181\209\128\208\184\209\143 \208\180\208\189\208\181\208\185 \209\129 \209\134\208\181\208\187\209\140\209\142', tostring(goalStreak()), nil, inner)
    else
        imgui.TextColored(DIM, '\208\166\208\181\208\187\209\140 \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189\208\176 (\208\178\208\186\208\187\208\176\208\180\208\186\208\176 "\208\144\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\176")')
    end
    ui.cardEnd()
    imgui.Spacing()

    ui.cardBegin(iw, 130)
    ui.iconText('chart', '\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\181 \208\191\208\190\209\129\209\130\209\131\208\191\208\187\208\181\208\189\208\184\209\143')
    imgui.SameLine(0, 8)
    ui.help('\208\147\209\128\208\176\209\132\208\184\208\186', '\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\181 24 \208\178\209\139\208\191\208\187\208\176\209\130\209\139. \208\157\208\176\208\178\208\181\208\180\208\184\209\130\208\181 \208\189\208\176 \209\129\209\130\208\190\208\187\208\177\208\184\208\186, \209\135\209\130\208\190\208\177\209\139 \209\131\208\178\208\184\208\180\208\181\209\130\209\140 \209\129\209\131\208\188\208\188\209\131.')
    ui.recentChart(iw - 24, 64)
    ui.cardEnd()
end

do
    local TITLE = {
        truck = {'\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', '\208\148\208\181\208\189\209\140\208\179\208\184 \208\190\209\130 \208\189\208\176\208\189\209\143\209\130\209\139\209\133 \208\178\208\176\208\188\208\184 \208\178\208\190\208\180\208\184\209\130\208\181\208\187\208\181\208\185. \208\161\209\135\208\184\209\130\208\176\209\142\209\130\209\129\209\143 \209\129\208\176\208\188\208\184, \208\189\208\184\209\135\208\181\208\179\208\190 \208\178\208\178\208\190\208\180\208\184\209\130\209\140 \208\189\208\181 \208\189\209\131\208\182\208\189\208\190.'},
        car = {'\208\145\208\190\208\189\209\131\209\129\209\139 \208\183\208\176 \209\130\209\128\208\176\208\189\209\129\208\191\208\190\209\128\209\130', '\208\148\208\190\208\191\208\187\208\176\209\130\209\139 \208\183\208\176 \209\130\208\190, \208\189\208\176 \209\135\209\145\208\188 \208\178\209\139 \208\181\208\180\208\181\209\130\208\181: \208\183\208\176 \208\187\208\184\209\135\208\189\209\139\208\185 \209\130\209\128\208\176\208\189\209\129\208\191\208\190\209\128\209\130, \208\183\208\176 \209\132\209\131\209\128\209\131 \208\184 \208\183\208\176 \209\130\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186.'},
        other = {'\208\159\209\128\208\190\209\135\208\184\208\181 \208\180\208\190\209\133\208\190\208\180\209\139', '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176, \208\177\208\190\208\189\209\131\209\129\209\139 \208\190\209\130 \208\176\208\186\209\134\208\184\208\185 \208\184 \208\180\209\128\209\131\208\179\208\184\208\181 \208\180\208\181\208\189\208\181\208\182\208\189\209\139\208\181 \208\189\208\176\208\179\209\128\208\176\208\180\209\139 \208\183\208\176 \209\128\208\176\208\177\208\190\209\130\209\131.'},
    }

    local function showVehicles(iw)
        ui.panelBegin('veh', iw, 'car', '\208\159\208\190 \208\188\208\176\209\136\208\184\208\189\208\176\208\188', {'\208\159\208\190 \208\188\208\176\209\136\208\184\208\189\208\176\208\188', '\208\154\208\176\208\186\208\184\208\181 \208\188\208\176\209\136\208\184\208\189\209\139 \208\191\209\128\208\184\208\189\208\181\209\129\208\187\208\184 \208\177\208\190\208\189\209\131\209\129\209\139 \208\184 \209\129\208\186\208\190\208\187\209\140\208\186\208\190. Tier - \209\141\209\130\208\190 \208\186\208\187\208\176\209\129\209\129 \209\132\209\131\209\128\209\139 (1, 2 \208\184\208\187\208\184 3). \208\162\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186 \208\183\208\176\208\191\208\184\209\129\209\139\208\178\208\176\208\181\209\130\209\129\209\143 \208\186 \209\129\208\178\208\190\208\181\208\185 \208\188\208\176\209\136\208\184\208\189\208\181.'})
        local w = iw - 28
        local sorted = {}
        for _, v in ipairs(vehicleCatalog.list) do sorted[#sorted + 1] = v end
        table.sort(sorted, function(a, b)
            if a.bonus_total ~= b.bonus_total then return a.bonus_total > b.bonus_total end
            return a.name < b.name
        end)
        listBegin('##veh_list', 132, w)
        local cols = {0, w * 0.44, w * 0.53, w * 0.63, w * 0.82}
        for i, head in ipairs({'\208\156\208\176\209\136\208\184\208\189\208\176', 'Tier', '\208\160\208\176\208\183', '\208\145\208\190\208\189\209\131\209\129\209\139, \209\128\209\131\208\177.', '\208\159\208\176\208\186'}) do
            if i > 1 then imgui.SameLine(cols[i]) end
            imgui.TextColored(DIM, head)
        end
        if #sorted == 0 then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\191\209\131\209\129\209\130\208\190') end
        for _, v in ipairs(sorted) do
            imgui.TextColored(accentColor(), cutText(plain(v.name), 22))
            imgui.SameLine(cols[2]); imgui.Text(v.tier > 0 and tostring(v.tier) or '-')
            imgui.SameLine(cols[3]); imgui.Text(tostring(v.runs))
            imgui.SameLine(cols[4]); imgui.TextColored(kindColor('car'), fmt(v.bonus_total))
            imgui.SameLine(cols[5]); imgui.TextColored(kindColor('items'), (v.pack_total or 0) > 0 and fmt(v.pack_total) or '-')
        end
        listEnd()
        ui.panelEnd()
    end

    local function showIgnored(iw)
        ui.panelBegin('ign', iw, 'warn', '\208\157\208\181 \208\180\208\190\209\133\208\190\208\180', {'\208\157\208\181 \208\180\208\190\209\133\208\190\208\180', '\208\148\208\181\208\189\209\140\208\179\208\184 \208\189\208\181 \208\183\208\176 \209\128\208\176\208\177\208\190\209\130\209\131: \208\191\208\190\208\180\208\176\209\128\208\186\208\184 \208\190\209\130 \208\176\208\180\208\188\208\184\208\189\208\184\209\129\209\130\209\128\208\176\209\134\208\184\208\184, \208\191\208\181\209\128\208\181\208\178\208\190\208\180\209\139 \208\190\209\130 \208\184\208\179\209\128\208\190\208\186\208\190\208\178, \208\191\209\128\208\190\208\180\208\176\208\182\208\184. \208\146 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \208\190\208\189\208\184 \208\189\208\181 \208\178\209\133\208\190\208\180\209\143\209\130.'})
        imgui.TextColored(DIM, '\208\146\209\129\208\181\208\179\208\190: ' .. fmt(stats.ignored.total) .. ' \209\128\209\131\208\177. (' .. stats.ignored.count .. ' \209\128\208\176\208\183)')
        listBegin('##ignored', 110, iw - 28)
        if #history.ignored == 0 then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\189\208\184\209\135\208\181\208\179\208\190') end
        for _, entry in ipairs(history.ignored) do
            imgui.TextColored(DIM, (entry.d or '') .. ' ' .. (entry.t or ''))
            imgui.SameLine(120)
            imgui.Text('+' .. fmt(entry.v) .. ' \209\128\209\131\208\177.')
            imgui.SameLine(270)
            imgui.TextColored(DIM, Ledger.IGNORE_REASON_TEXT[entry.why] or Ledger.IGNORE_REASON_TEXT.unknown)
        end
        listEnd()
        if ui.iconButton('trash', '\208\158\209\135\208\184\209\129\209\130\208\184\209\130\209\140 \209\129\208\191\208\184\209\129\208\190\208\186', 180) then
            history.ignored = {}
            stats.ignored.total, stats.ignored.count = 0, 0
            mark('stats', 'history')
        end
        ui.panelEnd()
    end

    local function showHistory(kind, iw)
        ui.panelBegin('hist_' .. kind, iw, 'history', '\208\152\209\129\209\130\208\190\209\128\208\184\209\143')
        listBegin('##hist' .. kind, 150, iw - 28)
        local list = history[kind]
        if #list == 0 then imgui.TextDisabled('\208\152\209\129\209\130\208\190\209\128\208\184\209\143 \208\191\209\131\209\129\209\130\208\176') end
        for _, entry in ipairs(list) do
            imgui.TextColored(DIM, (entry.d or '') .. ' ' .. (entry.t or ''))
            imgui.SameLine(120)
            imgui.TextColored(kindColor(kind), '+' .. fmt(entry.v) .. ' \209\128\209\131\208\177.')
            if entry.n and entry.n > 0 then
                imgui.SameLine(270)
                imgui.TextColored(DIM, entry.n .. ' \208\178\208\190\208\180\208\184\209\130.')
            elseif entry.name then
                imgui.SameLine(270)
                imgui.TextColored(DIM, cutText(plain(entry.name), 28))
            end
        end
        listEnd()
        if ui.iconButton('trash', '\208\158\209\135\208\184\209\129\209\130\208\184\209\130\209\140 \208\184\209\129\209\130\208\190\209\128\208\184\209\142', 190) then history[kind] = {} mark('history') end
        ui.panelEnd()
    end

    function pages.income(kind, iw)
        local info = KIND[kind]
        local st = stats[kind]
        ui.pageTitle(info.icon, TITLE[kind][1], {TITLE[kind][1], TITLE[kind][2]})

        local gap = 10
        local cw = cardWidth(iw, 4, gap)
        local average = st.count > 0 and st.total / st.count or 0
        ui.statCard('coins', '\208\146\209\129\208\181\208\179\208\190', fmt(st.total), '\209\128\209\131\208\177.', info.c, cw, 92)
        imgui.SameLine(0, gap)
        ui.statCard('bars', '\208\158\208\191\208\181\209\128\208\176\209\134\208\184\208\185', tostring(st.count), '\209\136\209\130.', info.c, cw, 92)
        imgui.SameLine(0, gap)
        ui.statCard('bolt', '\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185', '+' .. fmt(st.last), '\209\128\209\131\208\177.', info.c, cw, 92)
        imgui.SameLine(0, gap)
        ui.statCard('chart', '\208\161\209\128\208\181\208\180\208\189\208\181\208\181', fmt(average), '\209\128\209\131\208\177.', info.c, cw, 92)
        imgui.Spacing()

        local day = dayRec(todayKey())
        ui.panelBegin('today_' .. kind, iw, 'calendar', '\208\161\208\181\208\179\208\190\208\180\208\189\209\143 \208\184 \208\183\208\176 \209\129\208\181\209\129\209\129\208\184\209\142')
        local inner = iw - 28
        ui.labelValue('\208\161\208\181\208\179\208\190\208\180\208\189\209\143', '+' .. fmt(day[kind]) .. ' \209\128\209\131\208\177.', kindColor(kind), inner)
        ui.labelValue('\208\151\208\176 \209\129\208\181\209\129\209\129\208\184\209\142', '+' .. fmt(session[kind]) .. ' \209\128\209\131\208\177.', kindColor(kind), inner)
        ui.panelEnd()

        if kind == 'car' then showVehicles(iw) end
        showHistory(kind, iw)
        if kind == 'other' then showIgnored(iw) end
    end
end

do
local function isEternalVariant(text)
    return lowerRu(text or ''):find('\208\178\208\181\209\135\208\189', 1, true) ~= nil
end

function pages.items(iw)
    ui.pageTitle('gift', '\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139', {'\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139', '\208\155\208\176\209\128\209\134\209\139 \208\184 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\189\209\139\208\181 \208\180\208\190\208\179\208\190\208\178\208\190\209\128\209\139. \208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \208\184 \208\178\208\181\209\135\208\189\209\139\208\181 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139 \209\129\209\135\208\184\209\130\208\176\209\142\209\130\209\129\209\143 \208\190\209\130\208\180\208\181\208\187\209\140\208\189\208\190.'})
    local gap = 10
    local cw = cardWidth(iw, 4, gap)
    local day = dayRec(todayKey())
    local temp = stats.items.total - stats.eternal.total
    ui.statCard('gift', '\208\155\208\176\209\128\209\134\209\139', tostring(stats.chests.total), '~ ' .. fmtShort(stats.chests.total * cfg.value.chest) .. ' \209\128\209\131\208\177.', KIND.chests.c, cw, 92)
    imgui.SameLine(0, gap)
    ui.statCard('star', '\208\146\209\128\208\181\208\188. \208\180\208\184\208\178.', tostring(temp), fmtShort(temp * cfg.value.tempHour) .. ' \209\128\209\131\208\177./\209\135', KIND.items.c, cw, 92)
    imgui.SameLine(0, gap)
    ui.statCard('star', '\208\146\208\181\209\135\208\189. \208\180\208\184\208\178.', tostring(stats.eternal.total), '~ ' .. fmtShort(stats.eternal.total * cfg.value.eternal) .. ' \209\128\209\131\208\177.', {255, 214, 10}, cw, 92)
    imgui.SameLine(0, gap)
    ui.statCard('calendar', '\208\161\208\181\208\179\208\190\208\180\208\189\209\143', tostring(day.chests), '\208\187\208\176\209\128\209\134\208\190\208\178', KIND.chests.c, cw, 92)
    imgui.Spacing()

    local inner = iw - 28
    ui.panelBegin('it_value', iw, 'coins', '\208\166\208\181\208\189\208\176 \208\184 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190', {'\208\166\208\181\208\189\208\176 \208\184 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190', '\208\146\208\191\208\184\209\136\208\184\209\130\208\181 \209\134\208\181\208\189\209\131 \208\183\208\176 \209\136\209\130\209\131\208\186\209\131: \209\129\208\186\209\128\208\184\208\191\209\130 \209\131\208\188\208\189\208\190\208\182\208\184\209\130 \208\181\209\145 \208\189\208\176 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 \208\184 \208\191\208\190\208\186\208\176\208\182\208\181\209\130 \209\129\209\131\208\188\208\188\209\131. \208\154\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 \209\129\209\135\208\184\209\130\208\176\208\181\209\130\209\129\209\143 \209\129\208\176\208\188\208\190. \208\166\208\181\208\189\209\139 \208\189\209\131\208\182\208\189\209\139 \209\130\208\190\208\187\209\140\208\186\208\190 \208\180\208\187\209\143 \208\190\209\134\208\181\208\189\208\186\208\184.'})
    local function priceRow(title, tbl, key, qty, suffix, color)
        imgui.TextColored(DIM, title)
        imgui.SameLine(130)
        imgui.PushItemWidth(150)
        ui.inputInt('', tbl, key, 0, 0)
        imgui.PopItemWidth()
        imgui.SameLine(0, 10)
        imgui.TextColored(DIM, 'x ' .. qty .. ' \209\136\209\130. =')
        imgui.SameLine(0, 6)
        imgui.TextColored(color, fmt(qty * tbl[key]) .. suffix)
    end
    priceRow('\208\155\208\176\209\128\208\181\209\134, \209\128\209\131\208\177.', cfg.value, 'chest', stats.chests.total, ' \209\128\209\131\208\177.', kindColor('chests'))
    priceRow('\208\146\208\181\209\135\208\189\209\139\208\185 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180', cfg.value, 'eternal', stats.eternal.total, ' \209\128\209\131\208\177.', rgba(255, 214, 10))
    priceRow('\208\146\209\128\208\181\208\188. \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180 \208\178 \209\135\208\176\209\129', cfg.value, 'tempHour', temp, ' \209\128\209\131\208\177./\209\135', kindColor('items'))
    imgui.Spacing()
    ui.labelValue('\208\161\209\130\208\190\208\184\208\188\208\190\209\129\209\130\209\140 \208\187\208\176\209\128\209\134\208\190\208\178 \208\184 \208\178\208\181\209\135\208\189\209\139\209\133 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\190\208\178', fmt(stats.chests.total * cfg.value.chest + stats.eternal.total * cfg.value.eternal) .. ' \209\128\209\131\208\177.', GREEN, inner)
    ui.panelEnd()

    ui.panelBegin('it_chests', iw, 'gift', '\208\155\208\176\209\128\209\134\209\139', {'\208\155\208\176\209\128\209\134\209\139', '\208\161\209\135\208\184\209\130\208\176\209\142\209\130\209\129\209\143 \209\130\208\190\208\187\209\140\208\186\208\190 \208\187\208\176\209\128\209\134\209\139 \208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186\208\176. \208\158\209\129\209\130\208\176\208\187\209\140\208\189\209\139\208\181 \208\187\208\176\209\128\209\134\209\139 \209\129\208\186\209\128\208\184\208\191\209\130 \208\189\208\181 \209\130\209\128\208\190\208\179\208\176\208\181\209\130.'})
    local any = false
    for _, it in ipairs(itemCatalog.list) do
        if it.kind == 'chest' then
            any = true
            imgui.Text(it.name)
            local text = it.qty .. ' \209\136\209\130. / ' .. it.drops .. ' \209\128\208\176\208\183'
            imgui.SameLine(inner - imgui.CalcTextSize(text).x)
            imgui.TextColored(DIM, text)
        end
    end
    if not any then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\191\209\131\209\129\209\130\208\190') end
    ui.panelEnd()

    ui.panelBegin('it_div', iw, 'star', '\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\189\209\139\208\181 \208\180\208\190\208\179\208\190\208\178\208\190\209\128\209\139', {'\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \208\184 \208\178\208\181\209\135\208\189\209\139\208\181', '\208\146\208\181\209\135\208\189\209\139\208\185 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180 \208\190\209\129\209\130\208\176\209\145\209\130\209\129\209\143 \208\189\208\176\208\178\209\129\208\181\208\179\208\180\208\176, \208\178\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\185 \208\180\208\181\208\185\209\129\209\130\208\178\209\131\208\181\209\130 \208\190\208\179\209\128\208\176\208\189\208\184\209\135\208\181\208\189\208\189\208\190\208\181 \208\178\209\128\208\181\208\188\209\143 (\208\189\208\176\208\191\209\128\208\184\208\188\208\181\209\128, \209\129\209\131\209\130\208\186\208\184 \208\184\208\187\208\184 \208\189\208\181\208\180\208\181\208\187\209\142).'})
    any = false
    for _, it in ipairs(itemCatalog.list) do
        if it.kind ~= 'chest' then
            any = true
            imgui.TextColored(kindColor('items'), it.name)
            local tempVars, eternalVars = {}, {}
            for _, v in ipairs(it.variants) do
                if isEternalVariant(v.duration) or isEternalVariant(it.name) then eternalVars[#eternalVars + 1] = v else tempVars[#tempVars + 1] = v end
            end
            table.sort(tempVars, function(a, b) return (a.hours or 0) < (b.hours or 0) end)
            local function block(title, color, list)
                local qty = 0
                for _, v in ipairs(list) do qty = qty + v.qty end
                imgui.TextColored(color, '  ' .. title)
                local total = qty .. ' \209\136\209\130.'
                imgui.SameLine(inner - imgui.CalcTextSize(total).x)
                imgui.TextColored(color, total)
                for _, v in ipairs(list) do
                    imgui.TextColored(DIM, '      ' .. (v.duration ~= '' and v.duration or '\208\177\208\181\208\183 \209\129\209\128\208\190\208\186\208\176'))
                    local vs = v.qty .. ' \209\136\209\130. / ' .. v.drops .. ' \209\128\208\176\208\183'
                    imgui.SameLine(inner - imgui.CalcTextSize(vs).x)
                    imgui.TextColored(DIM, vs)
                end
            end
            block('\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181', kindColor('items'), tempVars)
            block('\208\146\208\181\209\135\208\189\209\139\208\181', rgba(255, 214, 10), eternalVars)
        end
    end
    if not any then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\191\209\131\209\129\209\130\208\190') end
    ui.panelEnd()

    ui.panelBegin('it_hist', iw, 'history', '\208\152\209\129\209\130\208\190\209\128\208\184\209\143', {'\208\152\209\129\209\130\208\190\209\128\208\184\209\143', '\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\181 \208\191\208\190\208\187\209\131\209\135\208\181\208\189\208\189\209\139\208\181 \208\187\208\176\209\128\209\134\209\139 \208\184 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139.'})
    listBegin('##hist_chests', 92, inner)
    if #history.chests == 0 then imgui.TextDisabled('\208\155\208\176\209\128\209\134\208\181\208\178 \208\191\208\190\208\186\208\176 \208\189\208\181\209\130') end
    for _, e in ipairs(history.chests) do
        imgui.TextColored(DIM, (e.d or '') .. ' ' .. (e.t or ''))
        imgui.SameLine(120)
        imgui.TextColored(kindColor('chests'), '+' .. (e.q or 1) .. ' \209\136\209\130.')
        imgui.SameLine(200)
        imgui.TextColored(DIM, e.name or '')
    end
    listEnd()
    listBegin('##hist_items', 100, inner)
    if #history.items == 0 then imgui.TextDisabled('\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\190\208\178 \208\191\208\190\208\186\208\176 \208\189\208\181\209\130') end
    for _, e in ipairs(history.items) do
        local eternal = e.e or isEternalVariant(e.dur)
        imgui.TextColored(DIM, (e.d or '') .. ' ' .. (e.t or ''))
        imgui.SameLine(120)
        imgui.TextColored(eternal and rgba(255, 214, 10) or kindColor('items'), '+' .. (e.q or 1) .. ' \209\136\209\130.')
        imgui.SameLine(190)
        imgui.TextColored(eternal and rgba(255, 214, 10) or DIM, eternal and '\208\146\208\181\209\135\208\189\209\139\208\185' or ('\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\185' .. ((e.dur and e.dur ~= '') and (' | ' .. e.dur) or '')))
    end
    listEnd()
    if ui.iconButton('trash', '\208\158\209\135\208\184\209\129\209\130\208\184\209\130\209\140 \208\184\209\129\209\130\208\190\209\128\208\184\209\142', 190) then history.chests = {} history.items = {} mark('history') end
    ui.panelEnd()
end
end

do
local WEEKDAY = {'\208\146\209\129', '\208\159\208\189', '\208\146\209\130', '\208\161\209\128', '\208\167\209\130', '\208\159\209\130', '\208\161\208\177'}

local function dayKeyOffset(days)
    local now = os.date('*t')
    now.hour, now.min, now.sec = 12, 0, 0
    return os.date('%Y-%m-%d', os.time(now) + days * 86400)
end

local function periodKeys()
    local p = UI.period
    if p == 'week' then return last7() end
    if p == 'yesterday' then return {dayKeyOffset(-1)} end
    if p == 'today' then return {todayKey()} end
    return {p}
end

local function periodName()
    local p = UI.period
    if p == 'today' then return '\209\129\208\181\208\179\208\190\208\180\208\189\209\143' end
    if p == 'yesterday' then return '\208\178\209\135\208\181\209\128\208\176' end
    if p == 'week' then return '\208\183\208\176 \208\189\208\181\208\180\208\181\208\187\209\142' end
    return p
end

local function periodStats(keys)
    local r = {money = 0, truck = 0, car = 0, other = 0, chests = 0, items = 0, eternal = 0, trips = 0, best = 0,
               expense = 0, hours = {}, activeHours = 0, set = {}}
    for _, key in ipairs(keys) do
        r.set[key] = true
        local d = stats.days[key]
        if d then
            for _, f in ipairs({'money', 'truck', 'car', 'other', 'chests', 'items', 'eternal', 'trips', 'expense'}) do
                r[f] = r[f] + (d[f] or 0)
            end
            r.best = math.max(r.best, d.bestTrip or 0)
            for hour, h in pairs(d.hours or {}) do
                local acc = r.hours[hour]
                if not acc then acc = {m = 0, t = 0, c = 0} r.hours[hour] = acc end
                acc.m, acc.t, acc.c = acc.m + (h.m or 0), acc.t + (h.t or 0), acc.c + (h.c or 0)
            end
        end
    end
    for _, h in pairs(r.hours) do if h.m > 0 then r.activeHours = r.activeHours + 1 end end
    r.temp = r.items - r.eternal
    return r
end

local function drawCalendar(iw)
    local keys = last7()
    local gap = 6
    local cw = math.floor((iw - gap * 6) / 7)
    local today = todayKey()
    for i, key in ipairs(keys) do
        local d = stats.days[key]
        local money = d and d.money or 0
        local p = imgui.GetCursorScreenPos()
        if imgui.InvisibleButton('##cal' .. i, imgui.ImVec2(cw, 46)) then UI.period = key end
        local hovered = imgui.IsItemHovered()
        local selected = UI.period == key or (UI.period == 'today' and key == today)
        local drawList = imgui.GetWindowDrawList()
        local corner = imgui.ImVec2(p.x + cw, p.y + 46)
        local fill = packColor(255, 255, 255, 0.05)
        if cfg.goal.enabled and cfg.goal.amount > 0 and money >= cfg.goal.amount then fill = packColor(72, 205, 130, 0.35)
        elseif money > 0 then fill = accentColor32(0.26) end
        drawList:AddRectFilled(p, corner, fill, 8)
        if selected or hovered then
            drawList:AddRect(p, corner, selected and accentColor32(1) or packColor(255, 255, 255, 0.35), 8)
        end
        local y, m, dd = key:match('(%d+)-(%d+)-(%d+)')
        local weekday = tonumber(os.date('%w', os.time({year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12})))
        drawList:AddText(imgui.ImVec2(p.x + 9, p.y + 6), packColor(140, 148, 165, 1), WEEKDAY[weekday + 1])
        drawList:AddText(imgui.ImVec2(p.x + 9, p.y + 24), packColor(232, 235, 242, 1), dd .. '.' .. m)
        if hovered then imgui.SetTooltip(key .. ': ' .. fmt(money) .. ' \209\128\209\131\208\177.') end
        if i < 7 then imgui.SameLine(0, gap) end
    end
end

local JOURNAL_ICON = {trip = 'check', truck = 'truck', car = 'car', other = 'wallet', chest = 'gift', item = 'star', expense = 'warn'}

function pages.analytics(iw)
    ui.pageTitle('chart', '\208\144\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\176')

    ui.goalPrompt(iw)
    local goal, today, fraction = goalTexts()
    ui.cardBegin(iw, 196)
    ui.iconText('target', '\208\166\208\181\208\187\209\140 \208\189\208\176 \208\180\208\181\208\189\209\140')
    imgui.SameLine(0, 8)
    ui.help('\208\166\208\181\208\187\209\140 \208\189\208\176 \208\180\208\181\208\189\209\140', '\208\154\208\190\208\187\209\140\209\134\208\190 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130, \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \209\134\208\181\208\187\208\184 \209\131\208\182\208\181 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\190. \208\159\209\128\208\190\208\179\208\189\208\190\208\183 - \208\186\208\190\208\179\208\180\208\176 \208\178\209\139 \208\180\208\190\208\185\208\180\209\145\209\130\208\181 \208\180\208\190 \208\189\208\181\209\145 \208\191\209\128\208\184 \209\130\208\176\208\186\208\190\208\188 \209\130\208\181\208\188\208\191\208\181.')
    imgui.Separator()
    local p = imgui.GetCursorScreenPos()
    local enabled = cfg.goal.enabled and goal > 0
    local color = fraction >= 1 and packColor(72, 205, 130, 1) or accentColor32(1)
    ui.ring(p.x + 66, p.y + 72, 56, 10, enabled and fraction or 0, color)
    local percent = enabled and (math.floor(fraction * 100) .. '%') or '-'
    pushFont(fonts.big)
    local ts = imgui.CalcTextSize(percent)
    imgui.GetWindowDrawList():AddText(imgui.ImVec2(p.x + 66 - ts.x / 2, p.y + 72 - ts.y / 2), packColor(232, 235, 242, 1), percent)
    popFont(fonts.big)
    imgui.SetCursorScreenPos(imgui.ImVec2(p.x + 150, p.y + 4))
    imgui.BeginGroup()
    if enabled then
        pushFont(fonts.title)
        imgui.Text(fmt(today) .. ' \208\184\208\183 ' .. fmt(goal) .. ' \209\128\209\131\208\177.')
        popFont(fonts.title)
        if fraction >= 1 then
            imgui.TextColored(GREEN, '\208\166\208\181\208\187\209\140 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176! \208\162\208\176\208\186 \208\180\208\181\209\128\208\182\208\176\209\130\209\140')
        else
            imgui.TextColored(DIM, '\208\158\209\129\209\130\208\176\208\187\208\190\209\129\209\140 ' .. fmt(goal - today) .. ' \209\128\209\131\208\177.')
            imgui.TextColored(DIM, goalForecast(goal - today))
        end
        imgui.Spacing()
        ui.progressBar(fraction, iw - 190, 10)
        imgui.TextColored(DIM, '\208\161\208\181\209\128\208\184\209\143 \208\180\208\189\208\181\208\185 \209\129 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\189\208\190\208\185 \209\134\208\181\208\187\209\140\209\142: ' .. goalStreak())
    else
        imgui.TextColored(DIM, '\208\166\208\181\208\187\209\140 \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189\208\176')
    end
    imgui.EndGroup()
    ui.cardEnd()
    imgui.Spacing()
    ui.checkbox('\208\148\208\189\208\181\208\178\208\189\208\176\209\143 \209\134\208\181\208\187\209\140 \208\178\208\186\208\187\209\142\209\135\208\181\208\189\208\176', cfg.goal, 'enabled', nil,
        {'\208\148\208\189\208\181\208\178\208\189\208\176\209\143 \209\134\208\181\208\187\209\140', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \209\133\208\190\209\130\208\184\209\130\208\181 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\209\130\209\140 \208\183\208\176 \208\180\208\181\208\189\209\140. \208\159\209\128\208\190\208\179\209\128\208\181\209\129\209\129 \208\178\208\184\208\180\208\181\208\189 \208\178 \208\190\208\178\208\181\209\128\208\187\208\181\208\181 \208\184 \208\189\208\176 \208\158\208\177\208\183\208\190\209\128\208\181.'})
    imgui.PushItemWidth(200)
    ui.inputInt('\208\166\208\181\208\187\209\140, \209\128\209\131\208\177. \208\178 \208\180\208\181\208\189\209\140', cfg.goal, 'amount', 50000, 250000)
    imgui.PopItemWidth()

    ui.sectionLabel('calendar', '\208\154\208\176\208\187\208\181\208\189\208\180\208\176\209\128\209\140 \208\189\208\181\208\180\208\181\208\187\208\184', {'\208\154\208\176\208\187\208\181\208\189\208\180\208\176\209\128\209\140', '\208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \208\180\208\181\208\189\209\140, \209\135\209\130\208\190\208\177\209\139 \209\131\208\178\208\184\208\180\208\181\209\130\209\140, \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\178\209\139 \208\178 \209\130\208\190\209\130 \208\180\208\181\208\189\209\140 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\187\208\184. \208\151\208\181\208\187\209\145\208\189\209\139\208\185 - \209\134\208\181\208\187\209\140 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176, \208\190\209\128\208\176\208\189\208\182\208\181\208\178\209\139\208\185 - \208\177\209\139\208\187 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186, \209\129\208\181\209\128\209\139\208\185 - \208\191\209\131\209\129\209\130\208\190.'})
    drawCalendar(iw)
    imgui.Spacing()
    local bw = math.floor((iw - 16) / 3)
    for i, preset in ipairs({{'today', '\208\161\208\181\208\179\208\190\208\180\208\189\209\143'}, {'yesterday', '\208\146\209\135\208\181\209\128\208\176'}, {'week', '\208\146\209\129\209\143 \208\189\208\181\208\180\208\181\208\187\209\143'}}) do
        local r, g, b = 60, 68, 90
        if UI.period == preset[1] then r, g, b = ACC.r, ACC.g, ACC.b end
        if ui.coloredButton(preset[2] .. '##preset' .. preset[1], bw, 28, r, g, b) then UI.period = preset[1] end
        if i < 3 then imgui.SameLine(0, 8) end
    end

    local r = periodStats(periodKeys())
    local money = r.money
    local chestValue, eternalValue = r.chests * cfg.value.chest, r.eternal * cfg.value.eternal
    ui.sectionLabel('bars', '\208\161\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176: ' .. periodName(), {'\208\161\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \208\191\208\181\209\128\208\184\208\190\208\180\208\176', '\208\152\209\130\208\190\208\179\208\184 \208\183\208\176 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\209\139\208\185 \208\180\208\181\208\189\209\140 \208\184\208\187\208\184 \208\189\208\181\208\180\208\181\208\187\209\142. \194\171\208\161\209\128\208\181\208\180\208\189\208\184\208\185 \208\180\208\190\209\133\208\190\208\180 \208\178 \209\135\208\176\209\129\194\187 \209\129\209\135\208\184\209\130\208\176\208\181\209\130\209\129\209\143 \208\191\208\190 \209\135\208\176\209\129\208\176\208\188, \208\186\208\190\208\179\208\180\208\176 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\187\208\184. \208\155\208\176\209\128\209\134\209\139 \208\184 \208\178\208\181\209\135\208\189\209\139\208\181 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139 - \208\191\208\190 \208\178\208\176\209\136\208\184\208\188 \209\134\208\181\208\189\208\176\208\188.'})
    local rows = {
        {'\208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \209\129 \209\128\208\181\208\185\209\129\208\190\208\178', fmt(r.truck + r.car) .. ' \209\128\209\131\208\177.', kindColor('truck')},
        {'\208\160\208\181\208\185\209\129\208\190\208\178', tostring(r.trips), nil},
        {'\208\161\209\128\208\181\208\180\208\189\208\184\208\185 \208\180\208\190\209\133\208\190\208\180 \208\178 \209\135\208\176\209\129', fmt(r.activeHours > 0 and money / r.activeHours or 0) .. ' \209\128\209\131\208\177./\209\135', accentColor()},
        {'\208\155\209\131\209\135\209\136\208\184\208\185 \209\128\208\181\208\185\209\129', fmt(r.best) .. ' \209\128\209\131\208\177.', kindColor('truck')},
        {'\208\159\209\128\208\190\209\135\208\184\208\181 \208\180\208\190\209\133\208\190\208\180\209\139', fmt(r.other) .. ' \209\128\209\131\208\177.', kindColor('other')},
        {'\208\155\208\176\209\128\209\134\209\139', r.chests .. ' \209\136\209\130. (' .. fmt(chestValue) .. ' \209\128\209\131\208\177.)', kindColor('chests')},
        {'\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', r.temp .. ' \209\136\209\130. (' .. fmt(r.temp * cfg.value.tempHour) .. ' \209\128\209\131\208\177./\209\135)', kindColor('items')},
        {'\208\146\208\181\209\135\208\189\209\139\208\181 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', r.eternal .. ' \209\136\209\130. (' .. fmt(eternalValue) .. ' \209\128\209\131\208\177.)', rgba(255, 214, 10)},
        {'\208\160\208\176\209\129\209\133\208\190\208\180\209\139', '-' .. fmt(r.expense) .. ' \209\128\209\131\208\177.', RED},
        {'\208\158\208\177\209\137\208\184\208\185 \208\180\208\190\209\133\208\190\208\180 (\208\180\208\181\208\189\209\140\208\179\208\184 + \208\190\209\134\208\181\208\189\208\186\208\176)', fmt(money + chestValue + eternalValue) .. ' \209\128\209\131\208\177.', GREEN},
    }
    ui.cardBegin(iw, 20 + #rows * 22 + 96)
    local inner = iw - 24
    for _, row in ipairs(rows) do ui.labelValue(row[1], row[2], row[3], inner) end
    imgui.Spacing()
    imgui.TextColored(DIM, '\208\161\209\130\209\128\209\131\208\186\209\130\209\131\209\128\208\176 \208\180\208\190\209\133\208\190\208\180\208\190\208\178')
    local sp = imgui.GetCursorScreenPos()
    local drawList = imgui.GetWindowDrawList()
    local barH = 12
    drawList:AddRectFilled(sp, imgui.ImVec2(sp.x + inner, sp.y + barH), packColor(255, 255, 255, 0.08), 6)
    local segments = {
        {'\208\160\208\181\208\185\209\129\209\139', r.truck + r.car, {255, 165, 0}},
        {'\208\159\209\128\208\190\209\135\208\184\208\181', r.other, {72, 205, 130}},
        {'\208\155\208\176\209\128\209\134\209\139', chestValue, {255, 214, 10}},
        {'\208\146\208\181\209\135\208\189\209\139\208\181', eternalValue, {190, 120, 255}},
    }
    local sum = 0
    for _, seg in ipairs(segments) do sum = sum + seg[2] end
    if sum > 0 then
        local x = sp.x
        for _, seg in ipairs(segments) do
            local width = inner * seg[2] / sum
            if width > 0.5 then
                drawList:AddRectFilled(imgui.ImVec2(x, sp.y), imgui.ImVec2(x + width, sp.y + barH), packColor(seg[3][1], seg[3][2], seg[3][3], 1), 0)
                x = x + width
            end
        end
    end
    imgui.Dummy(imgui.ImVec2(inner, barH))
    for i, seg in ipairs(segments) do
        local pct = sum > 0 and math.floor(seg[2] / sum * 100 + 0.5) or 0
        imgui.TextColored(rgba(seg[3][1], seg[3][2], seg[3][3]), seg[1] .. ' ' .. pct .. '%')
        if i < #segments then imgui.SameLine(0, 16) end
    end
    ui.cardEnd()

    ui.sectionLabel('chart', '\208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \208\191\208\190 \209\135\208\176\209\129\208\176\208\188', {'\208\159\208\190 \209\135\208\176\209\129\208\176\208\188', '\208\146 \208\186\208\176\208\186\208\184\208\181 \209\135\208\176\209\129\209\139 \209\129\209\131\209\130\208\190\208\186 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\181\209\130\208\181 \208\177\208\190\208\187\209\140\209\136\208\181. \208\157\208\176\208\178\208\181\208\180\208\184\209\130\208\181 \208\189\208\176 \209\129\209\130\208\190\208\187\208\177\208\184\208\186, \209\135\209\130\208\190\208\177\209\139 \209\131\208\178\208\184\208\180\208\181\209\130\209\140 \208\191\208\190\208\180\209\128\208\190\208\177\208\189\208\190\209\129\209\130\208\184.'})
    ui.cardBegin(iw, 132)
    ui.hoursChart(iw - 24, 84, r.hours)
    ui.cardEnd()

    ui.sectionLabel('trophy', '\208\162\208\190\208\191 \209\130\208\190\209\135\208\181\208\186 \209\128\208\176\208\183\208\179\209\128\209\131\208\183\208\186\208\184', {'\208\162\208\190\209\135\208\186\208\184 \209\128\208\176\208\183\208\179\209\128\209\131\208\183\208\186\208\184', '\208\154\209\131\208\180\208\176 \208\178\209\139 \209\135\208\176\209\137\208\181 \208\178\209\129\208\181\208\179\208\190 \208\178\208\190\208\183\208\184\208\187\208\184 \208\179\209\128\209\131\208\183\209\139.'})
    local top = {}
    for name, group in pairs(stats.orders.byCustomer) do top[#top + 1] = {name = name, count = group.count} end
    table.sort(top, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
    if #top == 0 then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\189\208\181\209\130 \208\180\208\176\208\189\208\189\209\139\209\133 - \209\129\208\180\208\176\208\185\209\130\208\181 \208\183\208\176\208\186\208\176\208\183') end
    for i = 1, math.min(5, #top) do
        imgui.TextColored(accentColor(), i .. '.')
        imgui.SameLine(0, 8)
        imgui.Text(cutText(plain(top[i].name), 34))
        local text = tostring(top[i].count)
        imgui.SameLine(iw - imgui.CalcTextSize(text).x)
        imgui.TextColored(DIM, text)
    end

    ui.sectionLabel('list', '\208\150\209\131\209\128\208\189\208\176\208\187 \209\129\208\190\208\177\209\139\209\130\208\184\208\185: ' .. periodName(), {'\208\150\209\131\209\128\208\189\208\176\208\187', '\208\146\209\129\209\145, \209\135\209\130\208\190 \208\178\209\139 \208\191\208\190\208\187\209\131\209\135\208\184\208\187\208\184 \208\183\208\176 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\209\139\208\185 \208\180\208\181\208\189\209\140: \208\178\209\139\208\191\208\187\208\176\209\130\209\139, \208\187\208\176\209\128\209\134\209\139, \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139, \208\183\208\176\208\186\208\176\208\183\209\139 \208\184 \209\128\208\176\209\129\209\133\208\190\208\180\209\139.'})
    listBegin('##journal', 240)
    local w = imgui.GetWindowWidth() - 34
    local shown = 0
    for _, e in ipairs(history.journal) do
        if r.set[e.d] then
            shown = shown + 1
            imgui.TextColored(DIM, e.t or '')
            imgui.SameLine(72)
            local kindKey = ({trip = 'truck', chest = 'chests', item = 'items'})[e.k] or e.k
            imgui.TextColored(KIND[kindKey] and kindColor(kindKey) or (e.k == 'expense' and RED or DIM), icons[JOURNAL_ICON[e.k] or 'info'])
            imgui.SameLine(98)
            imgui.Text(cutText(plain(e.text or ''), 32))
            if e.k ~= 'chest' and e.k ~= 'item' and (e.v or 0) > 0 then
                local value = (e.k == 'expense' and '-' or '+') .. fmt(e.v or 0) .. ' \209\128\209\131\208\177.'
                imgui.SameLine(w - imgui.CalcTextSize(value).x)
                imgui.TextColored(e.k == 'expense' and RED or GREEN, value)
            end
        end
    end
    if shown == 0 then imgui.TextDisabled('\208\161\208\190\208\177\209\139\209\130\208\184\208\185 \208\189\208\181\209\130') end
    listEnd()
    if ui.iconButton('trash', '\208\158\209\135\208\184\209\129\209\130\208\184\209\130\209\140 \208\182\209\131\209\128\208\189\208\176\208\187', 190) then history.journal = {} mark('history') end
end
end
do
    local REASON_TEXT = {
        shown = '\208\154\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\191\208\190\208\186\208\176\208\183\208\176\208\189\208\176',
        off = '\208\159\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\176 \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189\208\176',
        closed = '\208\158\208\186\208\189\208\190 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\183\208\176\208\186\209\128\209\139\209\130\208\190',
        empty = '\208\161\208\191\208\184\209\129\208\190\208\186 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\191\209\131\209\129\209\130',
        none = '\208\157\208\181\209\130 \208\191\208\190\208\180\209\133\208\190\208\180\209\143\209\137\208\184\209\133 \208\183\208\176\208\186\208\176\208\183\208\190\208\178',
        notgreat = '\208\155\209\131\209\135\209\136\208\184\208\185 \208\183\208\176\208\186\208\176\208\183 \208\189\208\181 \208\178\209\139\208\180\208\181\208\187\209\143\208\181\209\130\209\129\209\143 (\208\178\208\186\208\187\209\142\209\135\209\145\208\189 \209\128\208\181\208\182\208\184\208\188 "\209\130\208\190\208\187\209\140\208\186\208\190 \208\178\209\139\208\179\208\190\208\180\208\189\209\139\208\181")',
        error = '\208\158\209\136\208\184\208\177\208\186\208\176 \208\190\209\130\209\128\208\184\209\129\208\190\208\178\208\186\208\184 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\184, \208\191\208\190\208\178\209\130\208\190\209\128 \209\135\208\181\209\128\208\181\208\183 \208\191\208\176\209\128\209\131 \209\129\208\181\208\186\209\131\208\189\208\180',
    }

    local function showOrdersTable(w, now)
        local rows, best, _, suitable = Orders.rank(now)
        local state = Orders.state
        imgui.TextColored(DIM, (state.windowOpen and '\208\158\208\186\208\189\208\190 \208\190\209\130\208\186\209\128\209\139\209\130\208\190' or '\208\158\208\186\208\189\208\190 \208\183\208\176\208\186\209\128\209\139\209\130\208\190') .. '  |  ' ..
            (state.category ~= '' and state.category or '-') .. '  |  \208\183\208\176\208\186\208\176\208\183\208\190\208\178 ' .. #rows .. ', \208\191\208\190\208\180\209\133\208\190\208\180\209\143\209\130 ' .. suitable)
        listBegin('##orders_list', 210, w)
        local cw = imgui.GetWindowWidth() - 34
        if #rows == 0 then imgui.TextDisabled('\208\158\209\130\208\186\209\128\208\190\208\185\209\130\208\181 \208\190\208\186\208\189\208\190 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\189\208\176 \208\177\208\176\208\183\208\181 - \209\129\208\191\208\184\209\129\208\190\208\186 \208\191\208\190\209\143\208\178\208\184\209\130\209\129\209\143 \208\183\208\180\208\181\209\129\209\140') end
        for rank, row in ipairs(rows) do
            local order = row.order
            local good = row.score ~= nil
            local color = good and (row == best and GREEN or WHITE) or DIM
            imgui.TextColored(color, string.format('%2d. %s%s', rank, order.urgent and '! ' or '', cutText(plain(order.customer), 28)))
            local pay = fmt(order.payout) .. ' \209\128\209\131\208\177.'
            imgui.SameLine(cw - imgui.CalcTextSize(pay).x)
            imgui.TextColored(color, pay)
            local details = cutText(plain(order.cargo), 26) .. ', ' .. fmt(order.weight) .. ' \208\186\208\179, ' ..
                string.format('%.1f \208\186\208\188', order.km) .. (order.tier and (', Tier ' .. order.tier) or '')
            imgui.TextColored(DIM, '     ' .. details)
            local tail = good and (fmt(order.payout / math.max(order.km, 0.1)) .. ' \209\128\209\131\208\177./\208\186\208\188') or row.reason
            imgui.SameLine(cw - imgui.CalcTextSize(tail).x)
            imgui.TextColored(good and GREEN or DIM, tail)
        end
        listEnd()
    end

    function pages.orders(iw)
        ui.pageTitle('list', '\208\151\208\176\208\186\208\176\208\183\209\139', {'\208\155\209\131\209\135\209\136\208\184\208\185 \208\183\208\176\208\186\208\176\208\183', '\208\154\208\190\208\179\208\180\208\176 \208\178\209\139 \208\190\209\130\208\186\209\128\209\139\208\178\208\176\208\181\209\130\208\181 \209\129\208\191\208\184\209\129\208\190\208\186 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\189\208\176 \208\177\208\176\208\183\208\181, \209\129\208\186\209\128\208\184\208\191\209\130 \208\178\209\139\208\177\208\184\209\128\208\176\208\181\209\130 \208\187\209\131\209\135\209\136\208\184\208\185 \208\184 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \208\181\208\179\208\190 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\190\208\185. \208\151\208\176\208\186\208\176\208\183\209\139, \208\189\208\176 \208\186\208\190\209\130\208\190\209\128\209\139\208\181 \208\189\208\181 \209\133\208\178\208\176\209\130\208\184\209\130 \208\178\209\128\208\181\208\188\208\181\208\189\208\184, \209\129\208\187\208\184\209\136\208\186\208\190\208\188 \209\130\209\143\208\182\209\145\208\187\209\139\208\181 \208\184\208\187\208\184 \209\130\209\128\208\181\208\177\209\131\209\142\209\130 Tier \208\178\209\139\209\136\208\181 \208\178\208\176\209\136\208\181\208\179\208\190, \208\189\208\181 \208\191\209\128\208\181\208\180\208\187\208\176\208\179\208\176\209\142\209\130\209\129\209\143.'})
        local o = cfg.orders
        local state = Orders.state
        local inner = iw - 28
        local half = math.floor(inner / 2)

        ui.panelBegin('ord_list', iw, 'list', '\208\161\208\191\208\184\209\129\208\190\208\186 \208\189\208\176 \208\177\208\176\208\183\208\181')
        showOrdersTable(inner, os.clock())
        local _, reason = Orders.cardStatus(os.clock())
        if UI.dead.card and UI.dead.card > os.clock() then reason = 'error' end
        imgui.TextColored(DIM, REASON_TEXT[reason] or '')
        ui.panelEnd()

        ui.panelBegin('ord_hint', iw, 'eye', '\208\159\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\176')
        ui.checkbox('\208\154\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\183\208\176\208\186\208\176\208\183\208\176', o, 'enabled', nil, {'\208\154\208\176\209\128\209\130\208\190\209\135\208\186\208\176', '\208\157\208\181\208\177\208\190\208\187\209\140\209\136\208\190\208\181 \208\190\208\186\208\190\209\136\208\186\208\190 \209\129 \208\187\209\131\209\135\209\136\208\184\208\188 \208\183\208\176\208\186\208\176\208\183\208\190\208\188. \208\159\208\190\209\143\208\178\208\187\209\143\208\181\209\130\209\129\209\143, \208\186\208\190\208\179\208\180\208\176 \208\190\209\130\208\186\209\128\209\139\209\130 \209\129\208\191\208\184\209\129\208\190\208\186 \208\183\208\176\208\186\208\176\208\183\208\190\208\178. \208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\186\209\128\209\131\208\179\208\187\209\131\209\142 \208\186\208\189\208\190\208\191\208\186\209\131 \209\129 \209\132\209\131\209\128\208\190\208\185, \209\135\209\130\208\190\208\177\209\139 \208\178\208\183\209\143\209\130\209\140 \208\183\208\176\208\186\208\176\208\183. \208\154\208\189\208\190\208\191\208\186\209\131 \208\188\208\190\208\182\208\189\208\190 \208\191\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\209\140 \208\191\208\176\208\187\209\140\209\134\208\181\208\188.'}, 'eye')
        imgui.SameLine(half)
        ui.checkbox('\208\162\208\190\208\187\209\140\208\186\208\190 \208\178\209\139\208\179\208\190\208\180\208\189\209\139\208\181', o, 'onlyGreat', nil, {'\208\162\208\190\208\187\209\140\208\186\208\190 \208\178\209\139\208\179\208\190\208\180\208\189\209\139\208\181', '\208\159\208\190\208\186\208\176\208\183\209\139\208\178\208\176\209\130\209\140 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131, \209\130\208\190\208\187\209\140\208\186\208\190 \208\181\209\129\208\187\208\184 \208\187\209\131\209\135\209\136\208\184\208\185 \208\183\208\176\208\186\208\176\208\183 \208\183\208\176\208\188\208\181\209\130\208\189\208\190 \208\187\209\131\209\135\209\136\208\181 \208\190\209\129\209\130\208\176\208\187\209\140\208\189\209\139\209\133.'}, 'star')
        ui.checkbox('\208\159\209\131\209\129\209\130\208\176\209\143 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\176', o, 'showEmpty', nil, {'\208\159\209\131\209\129\209\130\208\176\209\143 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\176', '\208\149\209\129\208\187\208\184 \208\189\208\184 \208\190\208\180\208\184\208\189 \208\183\208\176\208\186\208\176\208\183 \208\189\208\181 \208\191\208\190\208\180\209\133\208\190\208\180\208\184\209\130, \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\190\208\177\209\138\209\143\209\129\208\189\208\184\209\130 \208\191\208\190\209\135\208\181\208\188\209\131: \208\188\208\176\208\187\208\190 \208\178\209\128\208\181\208\188\208\181\208\189\208\184, \209\130\209\143\208\182\209\145\208\187\209\139\208\185 \208\179\209\128\209\131\208\183 \208\184\208\187\208\184 \208\178\209\139\209\129\208\190\208\186\208\184\208\185 Tier.'}, 'warn')
        imgui.SameLine(half)
        ui.checkbox('\208\161\209\130\209\128\208\190\208\186\208\176 \208\178 \209\135\208\176\209\130\208\181', o, 'chatHint', nil, {'\208\161\209\130\209\128\208\190\208\186\208\176 \208\178 \209\135\208\176\209\130\208\181', '\208\162\208\190 \208\182\208\181 \209\129\208\176\208\188\208\190\208\181 \208\186\208\190\209\128\208\190\209\130\208\186\208\190 \208\178 \209\135\208\176\209\130\208\181. \208\159\208\190\208\187\208\181\208\183\208\189\208\190, \208\181\209\129\208\187\208\184 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131 \208\189\208\181 \208\178\208\184\208\180\208\189\208\190.'}, 'bell')
        ui.checkbox('\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140 \208\191\208\190 \209\128\208\181\208\185\209\129\208\176\208\188', o, 'autoSpeed', nil, {'\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140', '\208\159\208\190\209\129\208\187\208\181 5 \209\129\208\180\208\176\208\189\208\189\209\139\209\133 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \209\129\208\186\209\128\208\184\208\191\209\130 \209\129\208\176\208\188 \209\131\208\183\208\189\208\176\208\181\209\130 \208\178\208\176\209\136\209\131 \209\129\209\128\208\181\208\180\208\189\209\142\209\142 \209\129\208\186\208\190\209\128\208\190\209\129\209\130\209\140 \208\184 \209\130\208\190\209\135\208\189\208\181\208\181 \208\190\209\134\208\181\208\189\208\184\209\130, \209\131\209\129\208\191\208\181\208\181\209\130\208\181 \208\187\208\184 \208\178\209\139.'}, 'bolt')
        imgui.Spacing()
        if not state.mobile then
        imgui.TextColored(DIM, '\208\154\208\187\208\176\208\178\208\184\209\136\208\176 "\208\178\208\183\209\143\209\130\209\140 \208\183\208\176\208\186\208\176\208\183":')
        imgui.SameLine(0, 8)
        imgui.TextColored(accentColor(), state.capturingKey and '\208\189\208\176\208\182\208\188\208\184\209\130\208\181 \208\186\208\187\208\176\208\178\208\184\209\136\209\131 (Esc - \208\190\209\130\208\188\208\181\208\189\208\176)' or Orders.keyName(o.key))
        imgui.SameLine(0, 16)
        if ui.iconButton('keyboard', '\208\157\208\176\208\183\208\189\208\176\209\135\208\184\209\130\209\140', 130, 26) then Orders.startKeyCapture() end
        end
        imgui.TextColored(DIM, '\208\167\209\130\208\190 \209\129\209\135\208\184\209\130\208\176\209\130\209\140 \208\187\209\131\209\135\209\136\208\184\208\188:')
        imgui.SameLine(0, 8)
        for _, mode in ipairs({{'per_km', '\208\160\209\131\208\177. \208\183\208\176 \208\186\208\184\208\187\208\190\208\188\208\181\209\130\209\128'}, {'total', '\208\157\208\176\208\184\208\177\208\190\208\187\209\140\209\136\208\176\209\143 \208\191\209\128\208\181\208\188\208\184\209\143'}}) do
            local r, g, b = 60, 68, 90
            if o.mode == mode[1] then r, g, b = ACC.r, ACC.g, ACC.b end
            if ui.coloredButton(mode[2] .. '##mode' .. mode[1], 150, 26, r, g, b) then o.mode = mode[1] mark('settings') end
            imgui.SameLine(0, 8)
        end
        ui.help('\208\154\209\128\208\184\209\130\208\181\209\128\208\184\208\185', '\194\171\208\160\209\131\208\177. \208\183\208\176 \208\186\208\184\208\187\208\190\208\188\208\181\209\130\209\128\194\187 - \208\183\208\176\208\186\208\176\208\183 \209\129 \208\187\209\131\209\135\209\136\208\181\208\185 \208\190\208\191\208\187\208\176\209\130\208\190\208\185 \208\183\208\176 \208\186\208\176\208\182\208\180\209\139\208\185 \208\186\208\184\208\187\208\190\208\188\208\181\209\130\209\128. \194\171\208\157\208\176\208\184\208\177\208\190\208\187\209\140\209\136\208\176\209\143 \208\191\209\128\208\181\208\188\208\184\209\143\194\187 - \208\191\209\128\208\190\209\129\209\130\208\190 \209\129\208\176\208\188\209\139\208\185 \208\180\208\190\209\128\208\190\208\179\208\190\208\185 \208\183\208\176\208\186\208\176\208\183.')
        ui.panelEnd()

        ui.panelBegin('ord_params', iw, 'sliders', '\208\159\208\176\209\128\208\176\208\188\208\181\209\130\209\128\209\139 \208\190\209\134\208\181\208\189\208\186\208\184')
        imgui.TextColored(DIM, '\208\156\208\190\208\185 Tier:')
        imgui.SameLine(0, 8)
        for _, t in ipairs({{0, '\208\144\208\178\209\130\208\190'}, {1, 'Tier 1'}, {2, 'Tier 2'}, {3, 'Tier 3'}}) do
            local r, g, b = 60, 68, 90
            if o.myTier == t[1] then r, g, b = ACC.r, ACC.g, ACC.b end
            if ui.coloredButton(t[2] .. '##tier' .. t[1], 76, 26, r, g, b) then o.myTier = t[1] mark('settings') end
            imgui.SameLine(0, 6)
        end
        ui.help('Tier', 'Tier - \208\186\208\187\208\176\209\129\209\129 \208\178\208\176\209\136\208\181\208\185 \209\132\209\131\209\128\209\139 (1, 2 \208\184\208\187\208\184 3). \194\171\208\144\208\178\209\130\208\190\194\187 - \209\129\208\186\209\128\208\184\208\191\209\130 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\208\184\209\130 \209\129\208\176\208\188. \208\151\208\176\208\186\208\176\208\183\209\139 \209\129 Tier \208\178\209\139\209\136\208\181 \208\178\208\176\209\136\208\181\208\179\208\190 \208\189\208\181 \208\191\209\128\208\181\208\180\208\187\208\176\208\179\208\176\209\142\209\130\209\129\209\143.')
        imgui.Spacing()
        imgui.PushItemWidth(240)
        ui.slider('\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140, \208\186\208\188/\209\135', o, 'speed', 30, 120, '%.0f', {'\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140', '\208\146\208\176\209\136\208\176 \209\129\209\128\208\181\208\180\208\189\209\143\209\143 \209\129\208\186\208\190\209\128\208\190\209\129\209\130\209\140. \208\159\208\190 \208\189\208\181\208\185 \209\129\208\186\209\128\208\184\208\191\209\130 \209\128\208\181\209\136\208\176\208\181\209\130, \209\131\209\129\208\191\208\181\208\181\209\130\208\181 \208\187\208\184 \208\178\209\139 \208\180\208\190\208\178\208\181\208\183\209\130\208\184 \208\183\208\176\208\186\208\176\208\183 \208\178\208\190\208\178\209\128\208\181\208\188\209\143.'})
        ui.slider('\208\168\209\130\209\128\208\176\209\132 \208\183\208\176 \209\133\209\128\209\131\208\191\208\186\208\190\209\129\209\130\209\140, %', o, 'fragilityPenalty', 0, 60, '%.0f', {'\208\165\209\128\209\131\208\191\208\186\208\190\209\129\209\130\209\140', '\208\157\208\176\209\129\208\186\208\190\208\187\209\140\208\186\208\190 \209\129\208\189\208\184\208\182\208\176\209\130\209\140 \208\190\209\134\208\181\208\189\208\186\209\131 \209\133\209\128\209\131\208\191\208\186\208\190\208\179\208\190 \208\179\209\128\209\131\208\183\208\176. \208\167\208\181\208\188 \208\177\208\190\208\187\209\140\209\136\208\181 \208\183\208\189\208\176\209\135\208\181\208\189\208\184\208\181, \209\130\208\181\208\188 \208\188\208\181\208\189\209\140\209\136\208\181 \209\129\208\186\209\128\208\184\208\191\209\130 \208\187\209\142\208\177\208\184\209\130 \209\133\209\128\209\131\208\191\208\186\208\184\208\181 \208\183\208\176\208\186\208\176\208\183\209\139.'})
        ui.slider('\208\148\208\181\209\128\208\182\208\176\209\130\209\140 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131, \209\129\208\181\208\186', o, 'linger', 0, 5, '%.1f', {'\208\151\208\176\208\180\208\181\209\128\208\182\208\186\208\176', '\208\158\208\186\208\189\208\190 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \209\135\208\176\209\129\209\130\208\190 \208\183\208\176\208\186\209\128\209\139\208\178\208\176\208\181\209\130\209\129\209\143 \209\135\208\181\209\128\208\181\208\183 \208\191\208\176\209\128\209\131 \209\129\208\181\208\186\209\131\208\189\208\180. \208\154\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\190\209\129\209\130\208\176\209\145\209\130\209\129\209\143 \208\181\209\137\209\145 \208\189\208\176 \209\141\209\130\208\190 \208\178\209\128\208\181\208\188\209\143, \209\135\209\130\208\190\208\177\209\139 \208\178\209\139 \209\131\209\129\208\191\208\181\208\187\208\184 \208\181\209\145 \208\191\209\128\208\190\209\135\208\184\209\130\208\176\209\130\209\140.'})
        ui.inputInt('\208\147\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\209\145\208\188\208\189\208\190\209\129\209\130\209\140, \208\186\208\179', o, 'capacity', 500, 5000, {'\208\147\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\209\145\208\188\208\189\208\190\209\129\209\130\209\140', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\186\208\179 \208\178\208\181\208\183\209\145\209\130 \208\178\208\176\209\136\208\176 \209\132\209\131\209\128\208\176. \208\158\209\129\209\130\208\176\208\178\209\140\209\130\208\181 0, \208\184 \209\129\208\186\209\128\208\184\208\191\209\130 \208\178\208\190\208\183\209\140\208\188\209\145\209\130 \209\141\209\130\208\190 \208\184\208\183 \208\183\208\176\208\180\208\176\208\189\208\184\209\143 \209\129\208\176\208\188.'})
        ui.inputInt('\208\156\208\184\208\189\208\184\208\188\208\176\208\187\209\140\208\189\208\176\209\143 \208\191\209\128\208\181\208\188\208\184\209\143, \209\128\209\131\208\177.', o, 'minPayout', 10000, 100000)
        imgui.PopItemWidth()
        local myTier, autoTier = Orders.myTier()
        imgui.TextColored(DIM, '\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140 ' .. string.format('%.0f', Orders.effectiveSpeed()) .. ' \208\186\208\188/\209\135' ..
            (o.autoSpeed and #stats.orders.speeds >= 5 and ' (\208\191\208\190 \208\178\208\176\209\136\208\184\208\188 \209\128\208\181\208\185\209\129\208\176\208\188)' or '') ..
            '  |  Tier ' .. (myTier > 0 and (myTier .. (autoTier and ' (\208\176\208\178\209\130\208\190)' or '')) or '\208\189\208\181 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\209\145\208\189') ..
            '  |  \208\178\208\183\209\143\209\130\208\190: ' .. state.pickedTotal)
        ui.panelEnd()

        imgui.PushItemWidth(240)
        ui.slider('\208\160\208\176\208\183\208\188\208\181\209\128 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\184 \208\184 \208\186\208\189\208\190\208\191\208\186\208\184', o, 'scale', 0.5, 2.5, '%.2f')
        imgui.PopItemWidth()
        local bw = math.floor((iw - 8) / 2)
        if ui.iconButton('move', '\208\157\208\176\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131', bw) then Orders.startEdit() end
        imgui.SameLine(0, 8)
        if ui.iconButton('sync', '\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\191\208\190\208\187\208\190\208\182\208\181\208\189\208\184\208\181', bw) then Orders.resetPosition() end
        if ui.iconButton('eye', '\208\159\208\190\208\186\208\176\208\183\208\176\209\130\209\140 \208\191\209\128\208\184\208\188\208\181\209\128', bw) then state.demoUntil = os.clock() + (state.mobile and 30 or 8) end
        if state.active then
            imgui.SameLine(0, 8)
            if ui.dangerButton('trash', '\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\183\208\176\208\186\208\176\208\183', bw) then Orders.abandonActive() end
        end
    end
end

do
    local RESULT_TEXT = {done = '\209\129\208\180\208\176\208\189', unpaid = '\208\178\209\139\208\191\208\187\208\176\209\130\208\176 \208\189\208\181 \208\189\208\176\208\185\208\180\208\181\208\189\208\176', abandoned = '\208\177\209\128\208\190\209\136\208\181\208\189'}

    local function putRight(text, rightX)
        imgui.SameLine(rightX - imgui.CalcTextSize(text).x)
        imgui.Text(text)
    end

    local function showGroup(map, nameOf, iw, limit)
        local rows = {}
        for key, group in pairs(map) do
            rows[#rows + 1] = {key = key, g = group, rate = group.seconds > 0 and group.paid / (group.seconds / 3600) or 0}
        end
        table.sort(rows, function(a, b) return a.rate > b.rate end)
        if #rows == 0 then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\189\208\181\209\130 \208\180\208\176\208\189\208\189\209\139\209\133 - \209\129\208\180\208\176\208\185\209\130\208\181 \209\133\208\190\209\130\209\143 \208\177\209\139 \208\190\208\180\208\184\208\189 \208\183\208\176\208\186\208\176\208\183') return end
        imgui.TextColored(DIM, '\208\157\208\176\208\183\208\178\208\176\208\189\208\184\208\181')
        putRight('\208\183\208\176\208\186\208\176\208\183\208\190\208\178', iw - 300)
        putRight('\209\129\209\128. \208\178\209\139\208\191\208\187\208\176\209\130\208\176', iw - 190)
        putRight('\209\129\209\128. \208\178\209\128\208\181\208\188\209\143', iw - 90)
        putRight('\209\128\209\131\208\177./\209\135\208\176\209\129', iw - 8)
        for i, row in ipairs(rows) do
            if i > limit then break end
            imgui.Text(cutText(plain(nameOf(row.key)), 24))
            putRight(tostring(row.g.count), iw - 300)
            putRight(fmt(row.g.paid / row.g.count), iw - 190)
            putRight(fmtMinSec(row.g.seconds / row.g.count), iw - 90)
            imgui.SameLine(iw - 8 - imgui.CalcTextSize(fmt(row.rate)).x)
            imgui.TextColored(GREEN, fmt(row.rate))
        end
    end

    function pages.orderHistory(iw)
        ui.pageTitle('history', '\208\152\209\129\209\130\208\190\209\128\208\184\209\143 \208\183\208\176\208\186\208\176\208\183\208\190\208\178', {'\208\152\209\129\209\130\208\190\209\128\208\184\209\143 \208\183\208\176\208\186\208\176\208\183\208\190\208\178', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\191\209\128\208\184\208\189\209\145\209\129 \208\186\208\176\208\182\208\180\209\139\208\185 \209\129\208\180\208\176\208\189\208\189\209\139\208\185 \208\183\208\176\208\186\208\176\208\183. \194\171\208\160\209\131\208\177./\209\135\208\176\209\129\194\187 - \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \208\178 \208\180\208\190\209\128\208\190\208\179\208\181, \208\177\208\181\208\183 \208\191\209\128\208\190\209\129\209\130\208\190\208\181\208\178 \208\188\208\181\208\182\208\180\209\131 \208\183\208\176\208\186\208\176\208\183\208\176\208\188\208\184.'})
        local st = stats.orders
        local gap = 10
        local cw = cardWidth(iw, 4, gap)
        local average = st.done > 0 and st.paid / st.done or 0
        local perHour = st.seconds > 0 and st.paid / (st.seconds / 3600) or 0
        ui.statCard('check', '\208\161\208\180\208\176\208\189\208\190', tostring(st.done), '\208\183\208\176\208\186\208\176\208\183\208\190\208\178', KIND.truck.c, cw, 92)
        imgui.SameLine(0, gap)
        ui.statCard('coins', '\208\146\209\139\208\191\208\187\208\176\209\135\208\181\208\189\208\190', fmt(st.paid), '\209\128\209\131\208\177.', KIND.truck.c, cw, 92)
        imgui.SameLine(0, gap)
        ui.statCard('chart', '\208\146 \209\129\209\128\208\181\208\180\208\189\208\181\208\188', fmt(average), '\209\128\209\131\208\177. \208\183\208\176 \208\183\208\176\208\186\208\176\208\183', KIND.truck.c, cw, 92)
        imgui.SameLine(0, gap)
        ui.statCard('bolt', '\208\160\209\131\208\177./\209\135\208\176\209\129', fmt(perHour), '\208\178 \208\191\209\131\209\130\208\184, \208\177\208\181\208\183 \208\191\209\128\208\190\209\129\209\130\208\190\209\143', KIND.truck.c, cw, 92)

        imgui.TextColored(DIM, '\208\161\208\186\208\190\209\128\208\190\209\129\209\130\209\140 \208\191\208\190 \208\178\208\176\209\136\208\184\208\188 \209\128\208\181\208\185\209\129\208\176\208\188: ' ..
            (#st.speeds >= 5 and (string.format('%.0f', Orders.effectiveSpeed()) .. ' \208\186\208\188/\209\135') or ('\208\188\208\176\208\187\208\190 \208\180\208\176\208\189\208\189\209\139\209\133 (' .. #st.speeds .. ' \208\184\208\183 5)')) ..
            '  |  \208\177\208\181\208\183 \208\189\208\176\208\185\208\180\208\181\208\189\208\189\208\190\208\185 \208\178\209\139\208\191\208\187\208\176\209\130\209\139: ' .. st.unpaid)

        ui.sectionLabel('bars', '\208\159\208\190 \208\186\208\176\209\130\208\181\208\179\208\190\209\128\208\184\209\143\208\188')
        showGroup(st.byCategory, function(k) return k end, iw - 20, 8)
        ui.sectionLabel('star', '\208\159\208\190 Tier')
        showGroup(st.byTier, function(k) return k == '0' and '\208\177\208\181\208\183 Tier' or ('Tier ' .. k) end, iw - 20, 5)
        ui.sectionLabel('trophy', '\208\151\208\176\208\186\208\176\208\183\209\135\208\184\208\186\208\184')
        showGroup(st.byCustomer, function(k) return k end, iw - 20, 6)

        ui.sectionLabel('history', '\208\159\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\181 \208\183\208\176\208\186\208\176\208\183\209\139')
        listBegin('##orders_done', 170)
        local w = imgui.GetWindowWidth() - 34
        if #history.orders == 0 then imgui.TextDisabled('\208\159\208\190\208\186\208\176 \208\191\209\131\209\129\209\130\208\190') end
        for _, e in ipairs(history.orders) do
            imgui.TextColored(DIM, (e.d or '') .. ' ' .. (e.t or ''))
            imgui.SameLine(110)
            imgui.TextColored(e.result == 'done' and WHITE or DIM, cutText(plain(e.customer or '?'), 24))
            local right = e.result == 'done' and ('+' .. fmt(e.paid) .. ' \209\128\209\131\208\177.  ' .. fmtMinSec(e.seconds or 0)) or ((RESULT_TEXT[e.result] or '') .. '  ' .. fmtMinSec(e.seconds or 0))
            imgui.SameLine(w - imgui.CalcTextSize(right).x)
            imgui.TextColored(e.result == 'done' and GREEN or DIM, right)
        end
        listEnd()

        if ui.iconButton('trash', '\208\158\209\135\208\184\209\129\209\130\208\184\209\130\209\140 \208\184\209\129\209\130\208\190\209\128\208\184\209\142 \208\183\208\176\208\186\208\176\208\183\208\190\208\178', 260) then
            history.orders = {}
            stats.orders = {done = 0, unpaid = 0, paid = 0, seconds = 0, km = 0, byCategory = {}, byTier = {}, byCustomer = {}, speeds = {}}
            mark('stats', 'history')
        end
    end
end

do
    local BODY = rgba(196, 202, 216)

    local function entry(width, term, text)
        imgui.TextColored(accentColor(), term)
        ui.para(text, width, BODY)
        imgui.Spacing()
    end

    function pages.faq(iw)
        ui.pageTitle('question', 'FAQ - \208\186\208\176\208\186 \208\178\209\129\209\145 \209\128\208\176\208\177\208\190\209\130\208\176\208\181\209\130', {'FAQ', '\208\154\208\190\209\128\208\190\209\130\208\186\208\190 \208\184 \208\191\208\190\208\189\209\143\209\130\208\189\208\190: \209\135\209\130\208\190 \208\190\208\183\208\189\208\176\209\135\208\176\209\142\209\130 \209\134\208\184\209\132\209\128\209\139 \208\184 \208\186\208\189\208\190\208\191\208\186\208\184.'})
        local w = iw - 28

        ui.panelBegin('faq_about', iw, 'truck', '\208\167\209\130\208\190 \209\131\208\188\208\181\208\181\209\130 Truck Helper')
        ui.para('\208\173\209\130\208\190 \208\191\208\190\208\188\208\190\209\137\208\189\208\184\208\186 \208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186\208\176. \208\158\208\189 \209\129\208\176\208\188 \209\129\209\135\208\184\209\130\208\176\208\181\209\130, \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\187\208\184, \208\191\208\190\208\180\209\129\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \209\129\208\176\208\188\209\139\208\185 \208\178\209\139\208\179\208\190\208\180\208\189\209\139\208\185 \208\183\208\176\208\186\208\176\208\183 \208\189\208\176 \208\177\208\176\208\183\208\181 \208\184 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \208\179\208\187\208\176\208\178\208\189\208\190\208\181 \208\178 \208\188\208\176\208\187\208\181\208\189\209\140\208\186\208\190\208\188 \208\190\208\186\208\190\209\136\208\186\208\181 \208\191\208\190\208\178\208\181\209\128\209\133 \208\184\208\179\209\128\209\139. \208\146\208\178\208\190\208\180\208\184\209\130\209\140 \208\189\208\184\209\135\208\181\208\179\208\190 \208\189\208\181 \208\189\209\131\208\182\208\189\208\190: \209\129\208\186\209\128\208\184\208\191\209\130 \208\183\208\176\208\188\208\181\209\135\208\176\208\181\209\130 \208\178\209\139\208\191\208\187\208\176\209\130\209\139 \208\184 \209\129\208\190\208\177\209\139\209\130\208\184\209\143 \209\128\208\176\208\177\208\190\209\130\209\139 \209\129\208\176\208\188.', w, BODY)
        imgui.Spacing()
        entry(w, '\208\154\208\176\208\186 \208\190\209\130\208\186\209\128\209\139\209\130\209\140 \208\188\208\181\208\189\209\142', '\208\154\208\190\208\188\208\176\208\189\208\180\208\176 /db. \208\151\208\176\208\186\209\128\209\139\209\130\209\140 - \208\186\208\189\208\190\208\191\208\186\208\176 \209\129 \208\186\209\128\208\181\209\129\209\130\208\184\208\186\208\190\208\188. \208\158\208\186\208\189\208\190 \208\188\208\190\208\182\208\189\208\190 \208\191\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\209\140 \208\183\208\176 \208\178\208\181\209\128\209\133\208\189\209\142\209\142 \208\191\208\190\208\187\208\190\209\129\209\131.')
        ui.panelEnd()

        ui.panelBegin('faq_overlay', iw, 'eye', '\208\158\208\186\208\190\209\136\208\186\208\190 \208\189\208\176 \209\141\208\186\209\128\208\176\208\189\208\181 (\208\190\208\178\208\181\209\128\208\187\208\181\208\185)')
        entry(w, '\208\151\208\176 \208\189\208\181\208\180\208\181\208\187\209\142', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\187\208\184 \208\183\208\176 \209\130\208\181\208\186\209\131\209\137\209\131\209\142 \208\189\208\181\208\180\208\181\208\187\209\142. \208\161\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \209\133\209\128\208\176\208\189\208\184\209\130\209\129\209\143 7 \208\180\208\189\208\181\208\185, \208\191\208\190\209\130\208\190\208\188 \208\184\209\130\208\190\208\179\208\184 \209\129\208\190\209\133\209\128\208\176\208\189\209\143\209\142\209\130\209\129\209\143 \208\178 \208\176\209\128\209\133\208\184\208\178 \208\184 \209\129\209\135\209\145\209\130 \208\189\208\176\209\135\208\184\208\189\208\176\208\181\209\130\209\129\209\143 \208\183\208\176\208\189\208\190\208\178\208\190.')
        entry(w, '\208\161\208\181\208\179\208\190\208\180\208\189\209\143', '\208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \209\129 \208\191\208\190\208\187\209\131\208\189\208\190\209\135\208\184.')
        entry(w, '\208\146 \209\135\208\176\209\129', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\180\208\181\208\189\208\181\208\179 \208\178 \209\135\208\176\209\129 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\181\209\130\208\181 \208\178 \209\141\209\130\208\190\208\185 \208\184\208\179\209\128\208\190\208\178\208\190\208\185 \209\129\208\181\209\129\209\129\208\184\208\184. \208\161\209\135\208\184\209\130\208\176\208\181\209\130\209\129\209\143 \208\191\208\190 \208\178\209\128\208\181\208\188\208\181\208\189\208\184, \208\186\208\190\208\179\208\180\208\176 \208\178\209\139 \209\128\208\181\208\176\208\187\209\140\208\189\208\190 \209\128\208\176\208\177\208\190\209\130\208\176\208\187\208\184, \208\191\209\128\208\190\209\129\209\130\208\190\208\185 \208\189\208\181 \209\131\209\135\208\184\209\130\209\139\208\178\208\176\208\181\209\130\209\129\209\143. \208\166\208\184\209\132\209\128\208\176 \208\191\208\190\209\143\208\178\208\187\209\143\208\181\209\130\209\129\209\143 \208\191\208\190\209\129\208\187\208\181 10 \208\188\208\184\208\189\209\131\209\130 \209\128\208\176\208\177\208\190\209\130\209\139.')
        entry(w, '\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', '\208\148\208\181\208\189\209\140\208\179\208\184 \208\190\209\130 \208\189\208\176\208\189\209\143\209\130\209\139\209\133 \208\178\208\176\208\188\208\184 \208\178\208\190\208\180\208\184\209\130\208\181\208\187\208\181\208\185.')
        entry(w, '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129', '\208\148\208\190\208\191\208\187\208\176\209\130\209\139 \208\183\208\176 \209\130\209\128\208\176\208\189\209\129\208\191\208\190\209\128\209\130: \208\183\208\176 \208\187\208\184\209\135\208\189\209\139\208\185 \209\130/\209\129, \208\183\208\176 \209\130\208\184\208\191 \208\178\208\176\209\136\208\181\208\185 \209\132\209\131\209\128\209\139 \208\184 \208\183\208\176 \209\130\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186.')
        entry(w, '\208\159\209\128\208\190\209\135\208\184\208\181', '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176, \208\177\208\190\208\189\209\131\209\129\209\139 \208\190\209\130 \208\176\208\186\209\134\208\184\208\185 \208\184 \208\180\209\128\209\131\208\179\208\184\208\181 \208\180\208\181\208\189\208\181\208\182\208\189\209\139\208\181 \208\189\208\176\208\179\209\128\208\176\208\180\209\139.')
        entry(w, '\208\160\208\181\208\185\209\129\209\139', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\178\209\139 \209\129\208\180\208\176\208\187\208\184. \208\146 \209\129\208\186\208\190\208\177\208\186\208\176\209\133 - \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\191\209\128\208\184\208\189\209\145\209\129 \208\191\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185.')
        entry(w, '\208\163\209\128\208\190\208\178\208\181\208\189\209\140', '\208\146\208\176\209\136 \209\128\208\176\208\177\208\190\209\135\208\184\208\185 \209\131\209\128\208\190\208\178\208\181\208\189\209\140 \208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186\208\176 \208\184 \208\191\209\128\208\184\208\188\208\181\209\128\208\189\208\190 \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \209\128\208\181\208\185\209\129\208\190\208\178 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 \208\180\208\190 \209\129\208\187\208\181\208\180\209\131\209\142\209\137\208\181\208\179\208\190.')
        entry(w, '\208\155\208\176\209\128\209\134\209\139 \208\184 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', '\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139, \208\186\208\190\209\130\208\190\209\128\209\139\208\181 \208\178\209\139 \208\191\208\190\208\187\209\131\209\135\208\176\208\181\209\130\208\181 \208\183\208\176 \209\128\208\176\208\177\208\190\209\130\209\131. \208\159\208\190\208\180\209\128\208\190\208\177\208\189\208\181\208\181 - \208\189\208\184\208\182\208\181.')
        entry(w, '\208\154\208\176\208\186 \208\178\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\190\208\178\208\181\209\128\208\187\208\181\208\185', '\208\159\208\190 \209\131\208\188\208\190\208\187\209\135\208\176\208\189\208\184\209\142 \208\190\208\186\208\190\209\136\208\186\208\190 \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189\208\190. \208\146\208\186\208\187\209\142\209\135\208\184\209\130\208\181 \208\181\208\179\208\190 \208\178 \208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\176\209\133, \208\178 \208\177\208\187\208\190\208\186\208\181 \194\171\208\158\208\178\208\181\209\128\208\187\208\181\208\185\194\187: \208\179\208\176\208\187\208\190\209\135\208\186\208\176 \194\171\208\159\208\190\208\186\208\176\208\183\209\139\208\178\208\176\209\130\209\140 \208\190\208\178\208\181\209\128\208\187\208\181\208\185\194\187. \208\162\208\176\208\188 \208\182\208\181 \208\178\209\139\208\177\208\184\209\128\208\176\208\181\209\130\209\129\209\143, \208\186\208\176\208\186\208\184\208\181 \209\129\209\130\209\128\208\190\208\186\208\184 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\209\130\209\140.')
        entry(w, '\208\158\208\178\208\181\209\128\208\187\208\181\208\185 \208\191\209\128\209\143\209\135\208\181\209\130\209\129\209\143 \209\129\208\176\208\188', '\208\154\208\190\208\179\208\180\208\176 \208\189\208\176 \209\141\208\186\209\128\208\176\208\189\208\181 \208\191\208\190\209\143\208\178\208\187\209\143\208\181\209\130\209\129\209\143 \208\186\209\131\209\128\209\129\208\190\209\128 (\209\130\208\181\208\187\208\181\209\132\208\190\208\189, \208\184\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140), \208\190\208\186\208\190\209\136\208\186\208\190 \209\129\208\186\209\128\209\139\208\178\208\176\208\181\209\130\209\129\209\143, \209\135\209\130\208\190\208\177\209\139 \208\189\208\181 \208\188\208\181\209\136\208\176\209\130\209\140. \208\173\209\130\208\190 \208\188\208\190\208\182\208\189\208\190 \208\178\209\139\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\178 \208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\176\209\133.')
        ui.panelEnd()

        ui.panelBegin('faq_orders', iw, 'list', '\208\159\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\176 \208\191\208\190 \208\183\208\176\208\186\208\176\208\183\208\176\208\188')
        entry(w, '\208\154\208\176\208\186 \209\141\209\130\208\190 \209\128\208\176\208\177\208\190\209\130\208\176\208\181\209\130', '\208\154\208\190\208\179\208\180\208\176 \208\178\209\139 \208\190\209\130\208\186\209\128\209\139\208\178\208\176\208\181\209\130\208\181 \209\129\208\191\208\184\209\129\208\190\208\186 \208\183\208\176\208\186\208\176\208\183\208\190\208\178 \208\189\208\176 \208\177\208\176\208\183\208\181, \209\129\208\186\209\128\208\184\208\191\209\130 \208\178\209\139\208\177\208\184\209\128\208\176\208\181\209\130 \208\187\209\131\209\135\209\136\208\184\208\185 \208\184 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131. \208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\186\209\128\209\131\208\179\208\187\209\131\209\142 \208\186\208\189\208\190\208\191\208\186\209\131 \209\129 \209\132\209\131\209\128\208\190\208\185, \209\135\209\130\208\190\208\177\209\139 \208\178\208\183\209\143\209\130\209\140 \208\181\208\179\208\190. \208\154\208\189\208\190\208\191\208\186\209\131 \208\188\208\190\208\182\208\189\208\190 \208\191\208\181\209\128\208\181\209\130\208\176\209\137\208\184\209\130\209\140 \208\191\208\176\208\187\209\140\209\134\208\181\208\188.')
        entry(w, '\208\167\209\130\208\190 \208\183\208\189\208\176\209\135\208\184\209\130 "\208\187\209\131\209\135\209\136\208\184\208\185"', '\208\160\209\131\208\177. \208\183\208\176 \208\186\208\184\208\187\208\190\208\188\208\181\209\130\209\128 - \208\183\208\176\208\186\208\176\208\183, \208\186\208\190\209\130\208\190\209\128\209\139\208\185 \208\191\208\187\208\176\209\130\208\184\209\130 \208\177\208\190\208\187\209\140\209\136\208\181 \208\183\208\176 \208\186\208\176\208\182\208\180\209\139\208\185 \208\186\208\184\208\187\208\190\208\188\208\181\209\130\209\128 \208\191\209\131\209\130\208\184. \208\157\208\176\208\184\208\177\208\190\208\187\209\140\209\136\208\176\209\143 \208\191\209\128\208\181\208\188\208\184\209\143 - \208\191\209\128\208\190\209\129\209\130\208\190 \209\129\208\176\208\188\209\139\208\185 \208\177\208\190\208\187\209\140\209\136\208\190\208\185 \208\183\208\176\208\186\208\176\208\183 \208\191\208\190 \208\180\208\181\208\189\209\140\208\179\208\176\208\188.')
        entry(w, '\208\159\208\190\209\135\208\181\208\188\209\131 \208\183\208\176\208\186\208\176\208\183\208\176 \208\189\208\181\209\130 \208\178 \208\191\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\181', '\208\157\208\176 \208\189\208\181\208\179\208\190 \208\189\208\181 \209\133\208\178\208\176\209\130\208\184\209\130 \208\178\209\128\208\181\208\188\208\181\208\189\208\184, \208\179\209\128\209\131\208\183 \209\130\209\143\208\182\208\181\208\187\208\181\208\181 \208\178\208\176\209\136\208\181\208\185 \208\179\209\128\209\131\208\183\208\190\208\191\208\190\208\180\209\138\209\145\208\188\208\189\208\190\209\129\209\130\208\184 \208\184\208\187\208\184 \208\189\209\131\208\182\208\181\208\189 Tier \208\178\209\139\209\136\208\181 \208\178\208\176\209\136\208\181\208\179\208\190. Tier - \209\141\209\130\208\190 \208\186\208\187\208\176\209\129\209\129 \208\178\208\176\209\136\208\181\208\185 \209\132\209\131\209\128\209\139 (1, 2 \208\184\208\187\208\184 3), \208\190\208\177\209\139\209\135\208\189\208\190 \209\129\208\186\209\128\208\184\208\191\209\130 \208\190\208\191\209\128\208\181\208\180\208\181\208\187\209\143\208\181\209\130 \208\181\208\179\208\190 \209\129\208\176\208\188.')
        entry(w, '\208\162\208\190\208\187\209\140\208\186\208\190 \208\178\209\139\208\179\208\190\208\180\208\189\209\139\208\181', '\208\154\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\191\208\190\209\143\208\178\208\187\209\143\208\181\209\130\209\129\209\143, \209\130\208\190\208\187\209\140\208\186\208\190 \208\181\209\129\208\187\208\184 \208\187\209\131\209\135\209\136\208\184\208\185 \208\183\208\176\208\186\208\176\208\183 \208\183\208\176\208\188\208\181\209\130\208\189\208\190 \208\187\209\131\209\135\209\136\208\181 \208\190\209\129\209\130\208\176\208\187\209\140\208\189\209\139\209\133.')
        entry(w, '\208\159\209\131\209\129\209\130\208\176\209\143 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\176', '\208\149\209\129\208\187\208\184 \208\189\208\184\209\135\208\181\208\179\208\190 \208\189\208\181 \208\191\208\190\208\180\209\133\208\190\208\180\208\184\209\130, \208\186\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\190\208\177\209\138\209\143\209\129\208\189\208\184\209\130 \208\191\208\190\209\135\208\181\208\188\209\131, \209\135\209\130\208\190\208\177\209\139 \208\178\209\139 \208\189\208\181 \208\179\208\176\208\180\208\176\208\187\208\184.')
        entry(w, '\208\152\209\129\209\130\208\190\209\128\208\184\209\143 \208\183\208\176\208\186\208\176\208\183\208\190\208\178', '\208\159\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130, \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\191\209\128\208\184\208\189\209\145\209\129 \208\186\208\176\208\182\208\180\209\139\208\185 \209\129\208\180\208\176\208\189\208\189\209\139\208\185 \208\183\208\176\208\186\208\176\208\183 \208\184 \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\180\208\181\208\189\208\181\208\179 \208\178 \209\135\208\176\209\129 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\181\209\130\208\181, \208\191\208\190\208\186\208\176 \208\181\208\180\208\181\209\130\208\181.')
        ui.panelEnd()

        ui.panelBegin('faq_money', iw, 'coins', '\208\158\209\130\208\186\209\131\208\180\208\176 \208\177\208\181\209\128\209\131\209\130\209\129\209\143 \208\180\208\181\208\189\209\140\208\179\208\184')
        entry(w, '\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', '\208\146\209\139\208\191\208\187\208\176\209\130\209\139 \208\183\208\176 \209\128\208\176\208\177\208\190\209\130\209\131 \208\189\208\176\208\189\209\143\209\130\209\139\209\133 \208\178\208\190\208\180\208\184\209\130\208\181\208\187\208\181\208\185.')
        entry(w, '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129', '\208\148\208\190\208\191\208\187\208\176\209\130\208\176 \208\183\208\176 \209\130\208\190, \208\189\208\176 \209\135\209\145\208\188 \208\178\209\139 \208\181\208\180\208\181\209\130\208\181: \208\189\208\176 \208\187\208\184\209\135\208\189\208\190\208\188 \209\130\209\128\208\176\208\189\209\129\208\191\208\190\209\128\209\130\208\181 \208\184 \208\189\208\176 \209\132\209\131\209\128\208\181 \209\129 Tier.')
        entry(w, '\208\162\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186', '\208\148\208\190\208\191\208\187\208\176\209\130\208\176 \208\183\208\176 \209\131\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\189\209\139\208\185 \208\189\208\176 \209\132\209\131\209\128\209\131 \209\130\209\142\208\189\208\184\208\189\208\179. \208\151\208\176\208\191\208\184\209\129\209\139\208\178\208\176\208\181\209\130\209\129\209\143 \208\186 \209\130\208\190\208\185 \208\188\208\176\209\136\208\184\208\189\208\181, \208\186 \208\186\208\190\209\130\208\190\209\128\208\190\208\185 \208\190\208\189 \209\131\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189, \208\178\209\139 \209\131\208\178\208\184\208\180\208\184\209\130\208\181 \209\141\209\130\208\190 \208\189\208\176 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 "\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129".')
        entry(w, '\208\159\209\128\208\190\209\135\208\184\208\181 \208\180\208\190\209\133\208\190\208\180\209\139', '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176, \208\176\208\186\209\134\208\184\208\184 \208\184 \208\190\209\129\209\130\208\176\208\187\209\140\208\189\209\139\208\181 \208\180\208\181\208\189\208\181\208\182\208\189\209\139\208\181 \208\177\208\190\208\189\209\131\209\129\209\139.')
        entry(w, '\208\157\208\181 \208\180\208\190\209\133\208\190\208\180', '\208\148\208\181\208\189\209\140\208\179\208\184, \208\186\208\190\209\130\208\190\209\128\209\139\208\181 \208\191\209\128\208\184\209\136\208\187\208\184 \208\189\208\181 \208\183\208\176 \209\128\208\176\208\177\208\190\209\130\209\131 (\208\178\209\139\208\180\208\176\209\135\208\176 \208\190\209\130 \208\176\208\180\208\188\208\184\208\189\208\184\209\129\209\130\209\128\208\176\209\134\208\184\208\184, \208\191\208\181\209\128\208\181\208\178\208\190\208\180\209\139, \208\191\209\128\208\190\208\180\208\176\208\182\208\184), \208\178 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\209\131 \208\189\208\181 \208\191\208\190\208\191\208\176\208\180\208\176\209\142\209\130.')
        ui.panelEnd()

        ui.panelBegin('faq_percent', iw, 'percent', '\208\145\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181, \209\136\209\130\209\128\208\176\209\132 \208\184 \208\176\208\186\209\134\208\184\208\184')
        entry(w, '\208\145\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181', '\208\149\209\129\208\187\208\184 \209\131 \208\178\208\176\209\136\208\181\208\179\208\190 \208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186\208\176 \208\181\209\129\209\130\209\140 \208\190\209\129\208\190\208\177\208\176\209\143 \209\133\208\176\209\128\208\176\208\186\209\130\208\181\209\128\208\184\209\129\209\130\208\184\208\186\208\176 (\208\184\208\187\208\184 \208\181\209\129\209\130\209\140 \208\180\209\128\209\131\208\179\208\176\209\143 \208\191\209\128\208\184\209\135\208\184\208\189\208\176), \209\128\208\176\208\177\208\190\209\135\208\176\209\143 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \209\128\208\176\209\129\209\130\209\145\209\130 \208\189\208\176 \208\189\208\181\209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\191\209\128\208\190\209\134\208\181\208\189\209\130\208\190\208\178. \208\159\209\128\208\190\209\134\208\181\208\189\209\130 \208\177\209\139\208\178\208\176\208\181\209\130 \208\187\209\142\208\177\209\139\208\188. \208\161\208\186\209\128\208\184\208\191\209\130 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \208\181\208\179\208\190 \208\178 \208\190\208\178\208\181\209\128\208\187\208\181\208\181 \208\184 \208\191\208\190\208\180\208\191\208\184\209\129\209\139\208\178\208\176\208\181\209\130 \208\191\209\128\208\184\209\135\208\184\208\189\209\131: "\208\145\208\190\208\189\209\131\209\129 \208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186\208\176" \208\184\208\187\208\184 \208\191\209\128\208\190\209\129\209\130\208\190 "\208\145\208\190\208\189\209\131\209\129 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139".')
        entry(w, '\208\168\209\130\209\128\208\176\209\132: \208\189\208\181\209\130 \208\182\208\184\208\187\209\140\209\143', '\208\149\209\129\208\187\208\184 \209\131 \208\178\208\176\209\129 \208\189\208\181\209\130 \208\182\208\184\208\187\208\190\208\179\208\190 \208\184\208\188\209\131\209\137\208\181\209\129\209\130\208\178\208\176, \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133 \209\131\208\188\208\181\208\189\209\140\209\136\208\176\208\181\209\130\209\129\209\143. \208\161\208\186\209\128\208\184\208\191\209\130 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \209\141\209\130\208\190\209\130 \209\136\209\130\209\128\208\176\209\132.')
        entry(w, '\208\144\208\186\209\134\208\184\208\184', '\208\152\208\189\208\190\208\179\208\180\208\176 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\181 \208\180\208\181\208\185\209\129\209\130\208\178\209\131\208\181\209\130 \208\176\208\186\209\134\208\184\209\143, \208\189\208\176\208\191\209\128\208\184\208\188\208\181\209\128 +20% \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181. \208\146 \208\190\208\178\208\181\209\128\208\187\208\181\208\181 \208\178\208\184\208\180\208\189\208\190 \208\191\209\128\208\190\209\134\208\181\208\189\209\130 \208\184 \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 \208\178\209\128\208\181\208\188\208\181\208\189\208\184, \208\176 \208\177\208\190\208\189\209\131\209\129 \208\190\209\130 \208\176\208\186\209\134\208\184\208\184 \208\191\208\190\208\191\208\176\208\180\208\176\208\181\209\130 \208\178 "\208\159\209\128\208\190\209\135\208\184\208\181".')
        entry(w, '\208\159\209\128\208\190\209\134\208\181\208\189\209\130 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139 (\208\190\209\134\208\181\208\189\208\186\208\176)', '\208\149\209\129\208\187\208\184 \209\129\208\181\209\128\208\178\208\181\209\128 \208\189\208\176\208\191\208\184\209\129\208\176\208\187 \208\191\209\128\208\190 \208\191\209\128\208\190\209\134\208\181\208\189\209\130, \208\189\208\190 \208\180\208\181\208\189\209\140\208\179\208\184 \208\183\208\176 \208\189\208\181\208\179\208\190 \208\189\208\181 \208\191\209\128\208\184\209\136\208\187\208\184, \209\129\208\186\209\128\208\184\208\191\209\130 \208\188\208\190\208\182\208\181\209\130 \208\180\208\190\208\177\208\176\208\178\208\184\209\130\209\140 \208\181\208\179\208\190 \208\186 \209\128\208\181\208\185\209\129\209\131 \208\186\208\176\208\186 \208\190\209\134\208\181\208\189\208\186\209\131, \209\135\209\130\208\190\208\177\209\139 \208\178\209\139 \208\178\208\184\208\180\208\181\208\187\208\184, \209\129\208\186\208\190\208\187\209\140\208\186\208\190 "\208\180\208\190\208\187\208\182\208\189\208\190" \208\177\209\139\209\130\209\140. \208\146 \208\182\209\131\209\128\208\189\208\176\208\187\208\181 \209\130\208\176\208\186\208\176\209\143 \208\183\208\176\208\191\208\184\209\129\209\140 \208\191\208\190\208\188\208\181\209\135\208\181\208\189\208\176. \208\157\208\181 \208\189\209\131\208\182\208\189\208\190 - \208\178\209\139\208\186\208\187\209\142\209\135\208\184\209\130\208\181 \208\178 \208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\176\209\133, \208\178 \209\128\208\176\208\183\208\180\208\181\208\187\208\181 \194\171\208\167\209\130\208\190 \209\129\209\135\208\184\209\130\208\176\209\130\209\140\194\187.')
        ui.panelEnd()

        ui.panelBegin('faq_items', iw, 'gift', '\208\155\208\176\209\128\209\134\209\139 \208\184 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139')
        entry(w, '\208\155\208\176\209\128\209\134\209\139', '\208\155\208\176\209\128\208\181\209\134 \208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186\208\176 - \208\189\208\176\208\179\209\128\208\176\208\180\208\176 \208\183\208\176 \209\128\208\176\208\177\208\190\209\130\209\131. \208\148\209\128\209\131\208\179\208\184\208\181 \208\187\208\176\209\128\209\134\209\139 \209\129\208\186\209\128\208\184\208\191\209\130 \208\189\208\181 \209\129\209\135\208\184\209\130\208\176\208\181\209\130. \208\154\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 \209\129\209\135\208\184\209\130\208\176\208\181\209\130\209\129\209\143 \209\129\208\176\208\188\208\190. \208\166\208\181\208\189\209\131 \208\190\208\180\208\189\208\190\208\179\208\190 \208\187\208\176\209\128\209\134\208\176 \208\178\208\191\208\184\209\136\208\184\209\130\208\181 \208\189\208\176 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 "\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139" \208\178 \208\177\208\187\208\190\208\186\208\181 "\208\166\208\181\208\189\208\176 \208\184 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190": \209\129\208\186\209\128\208\184\208\191\209\130 \209\131\208\188\208\189\208\190\208\182\208\184\209\130 \208\181\209\145 \208\189\208\176 \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 \208\184 \208\191\208\190\208\186\208\176\208\182\208\181\209\130 \209\129\209\131\208\188\208\188\209\131 \208\178 \208\190\208\178\208\181\209\128\208\187\208\181\208\181, \208\189\208\176 \208\158\208\177\208\183\208\190\209\128\208\181 \208\184 \208\178 \208\176\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\181.')
        entry(w, '\208\146\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', '\208\148\208\181\208\185\209\129\209\130\208\178\209\131\209\142\209\130 \208\190\208\179\209\128\208\176\208\189\208\184\209\135\208\181\208\189\208\189\208\190\208\181 \208\178\209\128\208\181\208\188\209\143 \208\184 \208\191\209\128\208\184\208\189\208\190\209\129\209\143\209\130 \208\180\208\190\209\133\208\190\208\180 \208\186\208\176\208\182\208\180\209\139\208\185 \209\135\208\176\209\129. \208\148\208\190\209\133\208\190\208\180 \209\129 \208\190\208\180\208\189\208\190\208\179\208\190 \208\178\209\139 \209\130\208\190\208\182\208\181 \208\183\208\176\208\180\208\176\209\145\209\130\208\181 \208\189\208\176 "\208\159\209\128\208\181\208\180\208\188\208\181\209\130\208\176\209\133".')
        entry(w, '\208\146\208\181\209\135\208\189\209\139\208\181 \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', '\208\158\209\129\209\130\208\176\209\142\209\130\209\129\209\143 \208\189\208\176\208\178\209\129\208\181\208\179\208\180\208\176. \208\146\208\191\208\184\209\136\208\184\209\130\208\181 \209\134\208\181\208\189\209\131 \208\190\208\180\208\189\208\190\208\179\208\190 \208\189\208\176 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 "\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139", \208\186\208\190\208\187\208\184\209\135\208\181\209\129\209\130\208\178\208\190 \209\129\208\186\209\128\208\184\208\191\209\130 \208\191\208\190\209\129\209\135\208\184\209\130\208\176\208\181\209\130 \209\129\208\176\208\188, \208\176 \209\129\209\131\208\188\208\188\209\131 \208\191\208\190\208\186\208\176\208\182\208\181\209\130 \209\128\209\143\208\180\208\190\208\188.')
        ui.panelEnd()

        ui.panelBegin('faq_goal', iw, 'target', '\208\166\208\181\208\187\209\140 \208\180\208\189\209\143')
        entry(w, '\208\154\208\176\208\186 \208\191\208\190\209\129\209\130\208\176\208\178\208\184\209\130\209\140', '\208\157\208\176 \208\178\208\186\208\187\208\176\208\180\208\186\208\181 "\208\144\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\176" \209\131\208\186\208\176\208\182\208\184\209\130\208\181, \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \209\133\208\190\209\130\208\184\209\130\208\181 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\209\130\209\140 \208\183\208\176 \208\180\208\181\208\189\209\140. \208\154\208\190\208\187\209\140\209\134\208\190 \208\184 \209\136\208\186\208\176\208\187\208\176 \208\191\208\190\208\186\208\176\208\182\209\131\209\130 \208\191\209\128\208\190\208\179\209\128\208\181\209\129\209\129, \208\176 \208\191\209\128\208\190\208\179\208\189\208\190\208\183 - \208\186\208\190\208\179\208\180\208\176 \208\178\209\139 \208\180\208\190\208\185\208\180\209\145\209\130\208\181 \208\180\208\190 \209\134\208\181\208\187\208\184.')
        entry(w, '\208\154\208\190\208\179\208\180\208\176 \209\134\208\181\208\187\209\140 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176', '\208\161\208\186\209\128\208\184\208\191\209\130 \208\189\208\176\208\191\208\184\209\136\208\181\209\130 \208\190\208\177 \209\141\209\130\208\190\208\188 \208\178 \209\135\208\176\209\130, \208\176 \208\178 \208\188\208\181\208\189\209\142 \208\191\209\128\208\181\208\180\208\187\208\190\208\182\208\184\209\130 \208\189\208\176\209\135\208\176\209\130\209\140 \208\183\208\176\208\189\208\190\208\178\208\190 \209\129 \209\130\208\190\208\185 \208\182\208\181 \209\129\209\131\208\188\208\188\208\190\208\185 \208\184\208\187\208\184 \208\191\208\190\209\129\209\130\208\176\208\178\208\184\209\130\209\140 \208\189\208\190\208\178\209\131\209\142 \209\134\208\181\208\187\209\140.')
        entry(w, '\208\161\208\181\209\128\208\184\209\143 \208\180\208\189\208\181\208\185', '\208\161\208\186\208\190\208\187\209\140\208\186\208\190 \208\180\208\189\208\181\208\185 \208\191\208\190\208\180\209\128\209\143\208\180 \208\178\209\139 \208\178\209\139\208\191\208\190\208\187\208\189\209\143\208\187\208\184 \209\134\208\181\208\187\209\140.')
        ui.panelEnd()

        ui.panelBegin('faq_analytics', iw, 'chart', '\208\144\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\176')
        entry(w, '\208\154\208\176\208\187\208\181\208\189\208\180\208\176\209\128\209\140 \208\189\208\181\208\180\208\181\208\187\208\184', '\208\157\208\176\208\182\208\188\208\184\209\130\208\181 \208\189\208\176 \208\180\208\181\208\189\209\140, \209\135\209\130\208\190\208\177\209\139 \208\191\208\190\209\129\208\188\208\190\209\130\209\128\208\181\209\130\209\140 \208\181\208\179\208\190 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\209\131. \208\151\208\181\208\187\209\145\208\189\209\139\208\185 \208\180\208\181\208\189\209\140 - \209\134\208\181\208\187\209\140 \208\178\209\139\208\191\208\190\208\187\208\189\208\181\208\189\208\176, \208\190\209\128\208\176\208\189\208\182\208\181\208\178\209\139\208\185 - \208\177\209\139\208\187 \208\180\208\190\209\133\208\190\208\180, \209\129\208\181\209\128\209\139\208\185 - \208\191\209\131\209\129\209\130\208\190.')
        entry(w, '\208\147\209\128\208\176\209\132\208\184\208\186 \208\191\208\190 \209\135\208\176\209\129\208\176\208\188', '\208\159\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130, \208\178 \208\186\208\176\208\186\208\184\208\181 \209\135\208\176\209\129\209\139 \209\129\209\131\209\130\208\190\208\186 \208\178\209\139 \208\183\208\176\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\181\209\130\208\181 \208\177\208\190\208\187\209\140\209\136\208\181 \208\178\209\129\208\181\208\179\208\190.')
        entry(w, '\208\162\208\190\208\191 \209\130\208\190\209\135\208\181\208\186 \209\128\208\176\208\183\208\179\209\128\209\131\208\183\208\186\208\184', '\208\154\209\131\208\180\208\176 \208\178\209\139 \209\135\208\176\209\137\208\181 \208\178\209\129\208\181\208\179\208\190 \208\178\208\190\208\183\208\184\208\187\208\184 \208\179\209\128\209\131\208\183\209\139.')
        entry(w, '\208\150\209\131\209\128\208\189\208\176\208\187', '\208\146\209\129\208\181 \208\178\209\139\208\191\208\187\208\176\209\130\209\139, \208\187\208\176\209\128\209\134\209\139, \208\180\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139, \209\128\208\181\208\185\209\129\209\139 \208\184 \209\128\208\176\209\129\209\133\208\190\208\180\209\139 \208\183\208\176 \208\178\209\139\208\177\209\128\208\176\208\189\208\189\209\139\208\185 \208\180\208\181\208\189\209\140.')
        ui.panelEnd()

        ui.panelBegin('faq_questions', iw, 'info', '\208\167\208\176\209\129\209\130\209\139\208\181 \208\178\208\190\208\191\209\128\208\190\209\129\209\139')
        entry(w, '\208\159\208\190\209\135\208\181\208\188\209\131 "\208\151\208\176\208\186\208\176\208\183 \209\129\208\180\208\176\208\189" \208\191\208\190\209\143\208\178\208\187\209\143\208\181\209\130\209\129\209\143 \208\189\208\181 \209\129\209\128\208\176\208\183\209\131?', '\208\159\208\190\209\129\208\187\208\181 \209\129\208\180\208\176\209\135\208\184 \209\129\208\181\209\128\208\178\208\181\209\128 \208\191\209\128\208\184\209\129\209\139\208\187\208\176\208\181\209\130 \208\189\208\181\209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\178\209\139\208\191\208\187\208\176\209\130 \208\191\208\190\208\180\209\128\209\143\208\180. \208\161\208\186\209\128\208\184\208\191\209\130 \208\182\208\180\209\145\209\130 \208\191\208\176\209\128\209\131 \209\129\208\181\208\186\209\131\208\189\208\180, \209\135\209\130\208\190\208\177\209\139 \209\129\208\187\208\190\208\182\208\184\209\130\209\140 \208\184\209\133 \208\178 \208\190\208\180\208\189\209\131 \209\129\209\131\208\188\208\188\209\131.')
        entry(w, '\208\159\208\190\209\135\208\181\208\188\209\131 \208\178 "\208\146 \209\135\208\176\209\129" \208\189\208\176\208\191\208\184\209\129\208\176\208\189\208\190 "\208\181\209\137\209\145 10 \208\188\208\184\208\189"?', '\208\148\208\187\209\143 \209\135\208\181\209\129\209\130\208\189\208\190\208\185 \209\134\208\184\209\132\209\128\209\139 \208\189\209\131\208\182\208\189\208\190 \208\189\208\181\208\188\208\189\208\190\208\179\208\190 \208\191\208\190\209\128\208\176\208\177\208\190\209\130\208\176\209\130\209\140. \208\167\208\181\209\128\208\181\208\183 10 \208\188\208\184\208\189\209\131\209\130 \209\135\208\184\209\129\208\187\208\190 \208\191\208\190\209\143\208\178\208\184\209\130\209\129\209\143.')
        entry(w, '\208\154\208\176\208\186 \208\191\208\181\209\128\208\181\208\180\208\178\208\184\208\189\209\131\209\130\209\140 \208\190\208\186\208\189\208\176?', '\208\156\208\181\208\189\209\142 - \208\183\208\176 \208\178\208\181\209\128\209\133\208\189\209\142\209\142 \208\191\208\190\208\187\208\190\209\129\209\131. \208\158\208\178\208\181\209\128\208\187\208\181\208\185 - \208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184, \208\186\208\189\208\190\208\191\208\186\208\176 "\208\159\208\181\209\128\208\181\208\188\208\181\209\129\209\130\208\184\209\130\209\140 \208\190\208\178\208\181\209\128\208\187\208\181\208\185". \208\154\208\176\209\128\209\130\208\190\209\135\208\186\208\176 \208\183\208\176\208\186\208\176\208\183\208\176 - \208\178\208\186\208\187\208\176\208\180\208\186\208\176 "\208\151\208\176\208\186\208\176\208\183\209\139", \208\186\208\189\208\190\208\191\208\186\208\176 "\208\157\208\176\209\129\209\130\209\128\208\190\208\184\209\130\209\140 \208\186\208\176\209\128\209\130\208\190\209\135\208\186\209\131".')
        entry(w, '\208\154\208\176\208\186 \208\178\209\139\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\178\209\129\209\145 \209\129\209\128\208\176\208\183\209\131?', '\208\154\209\128\208\176\209\129\208\189\208\176\209\143 \208\186\208\189\208\190\208\191\208\186\208\176 \208\191\208\184\209\130\208\176\208\189\208\184\209\143 \208\178 \208\178\208\181\209\128\209\133\208\189\208\181\208\185 \209\135\208\176\209\129\209\130\208\184 \208\188\208\181\208\189\209\142. \208\146\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\190\208\177\209\128\208\176\209\130\208\189\208\190 \208\188\208\190\208\182\208\189\208\190 \208\186\208\190\208\188\208\176\208\189\208\180\208\190\208\185 /db.')
        entry(w, '\208\166\208\184\209\132\209\128\209\139 \208\189\208\181 \209\129\209\133\208\190\208\180\209\143\209\130\209\129\209\143 \209\129 \208\188\208\190\208\184\208\188\208\184?', '\208\157\208\176\208\191\208\184\209\136\208\184\209\130\208\181 \208\178 \208\189\208\176\209\136\208\181\208\188 \208\177\208\190\209\130\208\181: \208\191\209\128\208\184\208\187\208\190\208\182\208\184\209\130\208\181 \209\129\208\186\209\128\208\184\208\189\209\136\208\190\209\130 \208\188\208\181\208\189\209\142 \208\184 \208\190\208\191\208\184\209\136\208\184\209\130\208\181, \209\135\209\130\208\190 \208\184\208\188\208\181\208\189\208\189\208\190 \208\189\208\181 \209\129\209\133\208\190\208\180\208\184\209\130\209\129\209\143.')
        ui.panelEnd()

        ui.panelBegin('faq_dev', iw, 'wrench', '\208\161\208\186\209\128\208\184\208\191\209\130 \208\181\209\137\209\145 \208\180\208\190\209\128\208\176\208\177\208\176\209\130\209\139\208\178\208\176\208\181\209\130\209\129\209\143')
        ui.para('Truck Helper \208\191\208\190\209\129\209\130\208\190\209\143\208\189\208\189\208\190 \209\128\208\176\208\183\208\178\208\184\208\178\208\176\208\181\209\130\209\129\209\143: \208\188\209\139 \208\180\208\190\208\177\208\176\208\178\208\187\209\143\208\181\208\188 \208\189\208\190\208\178\209\139\208\181 \209\132\209\131\208\189\208\186\209\134\208\184\208\184 \208\184 \209\136\208\187\208\184\209\132\209\131\208\181\208\188 \208\188\208\181\208\187\208\190\209\135\208\184. \208\167\209\130\208\190-\209\130\208\190 \209\128\208\176\208\177\208\190\209\130\208\176\208\181\209\130 \208\189\208\181 \209\130\208\176\208\186, \208\189\208\181 \209\133\208\178\208\176\209\130\208\176\208\181\209\130 \208\189\209\131\208\182\208\189\208\190\208\185 \209\132\209\131\208\189\208\186\209\134\208\184\208\184 \208\184\208\187\208\184 \208\181\209\129\209\130\209\140 \208\184\208\180\208\181\209\143, \208\186\208\176\208\186 \209\129\208\180\208\181\208\187\208\176\209\130\209\140 \209\131\208\180\208\190\208\177\208\189\208\181\208\181? \208\157\208\176\208\191\208\184\209\136\208\184\209\130\208\181 \208\189\208\176\208\188 \208\178 \208\177\208\190\209\130\208\176.', w, BODY)
        imgui.Spacing()
        ui.para('\208\167\208\184\209\130\208\176\208\181\208\188 \208\178\209\129\209\145 \208\184 \209\131\209\135\208\184\209\130\209\139\208\178\208\176\208\181\208\188 \208\191\208\190\208\182\208\181\208\187\208\176\208\189\208\184\209\143 \208\184\208\179\209\128\208\190\208\186\208\190\208\178. \208\167\208\181\208\188 \208\191\208\190\208\180\209\128\208\190\208\177\208\189\208\181\208\181 \208\190\208\191\208\184\209\136\208\181\209\130\208\181, \209\135\209\130\208\190 \208\189\208\176\208\182\208\176\208\187\208\184 \208\184 \209\135\209\130\208\190 \209\131\208\178\208\184\208\180\208\181\208\187\208\184, \209\130\208\181\208\188 \208\177\209\139\209\129\209\130\209\128\208\181\208\181 \208\184\209\129\208\191\209\128\208\176\208\178\208\184\208\188.', w, BODY)
        imgui.Spacing()
        if ui.iconButton('bell', '\208\157\208\176\208\191\208\184\209\129\208\176\209\130\209\140 \208\178 \208\177\208\190\209\130\208\181', 240) then pending.openLink = BOT_URL end
        ui.panelEnd()

        ui.panelBegin('faq_contact', iw, 'bullhorn', '\208\156\209\139 \208\178 Telegram')
        ui.para('\208\161\208\178\208\181\208\182\208\184\208\181 \208\178\208\181\209\128\209\129\208\184\208\184, \208\189\208\190\208\178\209\139\208\181 \209\129\208\186\209\128\208\184\208\191\209\130\209\139 \208\184 \208\190\209\130\208\178\208\181\209\130\209\139 \208\189\208\176 \208\178\208\190\208\191\209\128\208\190\209\129\209\139 - \208\178 \208\189\208\176\209\136\208\181\208\188 Telegram-\208\186\208\176\208\189\208\176\208\187\208\181.', w, BODY)
        imgui.Spacing()
        if ui.iconButton('bullhorn', '\208\159\208\181\209\128\208\181\208\185\209\130\208\184 \208\178 Telegram', 240) then pending.openLink = TELEGRAM_URL end
        ui.panelEnd()
    end
end

function pages.settings(iw)
    ui.pageTitle('cog', '\208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184')
    local o = cfg.overlay
    local inner = iw - 28
    local half = math.floor(inner / 2)

    ui.panelBegin('st_power', iw, 'power', '\208\160\208\176\208\177\208\190\209\130\208\176 \209\129\208\186\209\128\208\184\208\191\209\130\208\176', {'\208\159\208\190\208\187\208\189\208\190\208\181 \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\181', '\208\161\208\186\209\128\208\184\208\191\209\130 \208\191\208\181\209\128\208\181\209\129\209\130\208\176\208\189\208\181\209\130 \209\129\209\135\208\184\209\130\208\176\209\130\209\140 \208\180\208\181\208\189\209\140\208\179\208\184 \208\184 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\209\130\209\140 \208\190\208\186\208\189\208\176. \208\146\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \208\190\208\177\209\128\208\176\209\130\208\189\208\190 \208\188\208\190\208\182\208\189\208\190 \208\186\208\190\208\188\208\176\208\189\208\180\208\190\208\185 /db.'})
    if ui.dangerButton('power', '\208\146\209\139\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \209\129\208\186\209\128\208\184\208\191\209\130 \208\191\208\190\208\187\208\189\208\190\209\129\209\130\209\140\209\142', 300) then pending.disable = true end
    ui.panelEnd()

    ui.panelBegin('st_theme', iw, 'palette', '\208\166\208\178\208\181\209\130\208\190\208\178\208\176\209\143 \209\130\208\181\208\188\208\176')
    for i, th in ipairs(THEMES) do
        local p = imgui.GetCursorScreenPos()
        local r = 13
        if imgui.InvisibleButton('##theme' .. i, imgui.ImVec2(r * 2 + 6, r * 2 + 6)) then
            cfg.theme = i
            pending.theme = true
            mark('settings')
        end
        local hov = imgui.IsItemHovered()
        local drawList = imgui.GetWindowDrawList()
        local ctr = imgui.ImVec2(p.x + r + 3, p.y + r + 3)
        local swatch = th.rainbow and {ACC.r, ACC.g, ACC.b} or th.c
        drawList:AddCircleFilled(ctr, r, packColor(swatch[1], swatch[2], swatch[3], 1), 24)
        if cfg.theme == i then drawList:AddCircle(ctr, r + 3, packColor(255, 255, 255, 0.9), 24, 2) end
        if hov then imgui.SetTooltip(th.name) end
        imgui.SameLine(0, 8)
    end
    imgui.NewLine()
    if ui.iconButton('sync', '\208\146\208\181\209\128\208\189\209\131\209\130\209\140 \208\188\208\181\208\189\209\142 \208\178 \209\134\208\181\208\189\209\130\209\128', 230, 26) then
        cfg.menu.x, cfg.menu.y = -1, -1
        UI.menuX, UI.menuY = nil, nil
        mark('settings')
    end
    ui.panelEnd()

    ui.panelBegin('st_overlay', iw, 'eye', '\208\158\208\178\208\181\209\128\208\187\208\181\208\185')
    ui.checkbox('\208\159\208\190\208\186\208\176\208\183\209\139\208\178\208\176\209\130\209\140 \208\190\208\178\208\181\209\128\208\187\208\181\208\185', o, 'enabled', nil, nil, 'eye')
    imgui.SameLine(half)
    ui.checkbox('\208\159\209\128\209\143\209\130\208\176\209\130\209\140 \208\191\209\128\208\184 \208\186\209\131\209\128\209\129\208\190\209\128\208\181', o, 'hideOnCursor', nil, {'\208\159\209\128\209\143\209\130\208\176\209\130\209\140 \208\191\209\128\208\184 \208\186\209\131\209\128\209\129\208\190\209\128\208\181', '\208\158\208\178\208\181\209\128\208\187\208\181\208\185 \209\129\208\186\209\128\209\139\208\178\208\176\208\181\209\130\209\129\209\143, \208\186\208\190\208\179\208\180\208\176 \208\189\208\176 \209\141\208\186\209\128\208\176\208\189\208\181 \208\186\209\131\209\128\209\129\208\190\209\128 (\209\130\208\181\208\187\208\181\209\132\208\190\208\189, \208\184\208\189\208\178\208\181\208\189\209\130\208\176\209\128\209\140). \208\159\208\190\208\186\208\176 \208\190\209\130\208\186\209\128\209\139\209\130\208\190 \208\188\208\181\208\189\209\142 \209\129\208\186\209\128\208\184\208\191\209\130\208\176, \208\190\208\189 \208\190\209\129\209\130\208\176\209\145\209\130\209\129\209\143.'}, 'shield')
    imgui.Spacing()
    imgui.PushItemWidth(240)
    ui.slider('\208\159\209\128\208\190\208\183\209\128\208\176\209\135\208\189\208\190\209\129\209\130\209\140 \209\132\208\190\208\189\208\176', o, 'opacity', 0.30, 1.0)
    ui.slider('\208\156\208\176\209\129\209\136\209\130\208\176\208\177', o, 'scale', 0.60, 2.50)
    imgui.PopItemWidth()
    imgui.Spacing()
    imgui.TextColored(DIM, '\208\154\208\176\208\186\208\184\208\181 \209\129\209\130\209\128\208\190\208\186\208\184 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\209\130\209\140')
    local rows = {
        {'session', '\208\146\209\128\208\181\208\188\209\143 \209\129\208\181\209\129\209\129\208\184\208\184', 'stopwatch'}, {'total', '\208\151\208\176 \208\189\208\181\208\180\208\181\208\187\209\142', 'coins'},
        {'truck', '\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', 'users'}, {'car', '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129', 'car'},
        {'other', '\208\159\209\128\208\190\209\135\208\184\208\181', 'wallet'}, {'trips', '\208\160\208\181\208\185\209\129\209\139', 'check'},
        {'chests', '\208\155\208\176\209\128\209\134\209\139', 'gift'}, {'items', '\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', 'star'},
        {'today', '\208\161\208\181\208\179\208\190\208\180\208\189\209\143', 'calendar'}, {'hourly', '\208\148\208\190\209\133\208\190\208\180 \208\178 \209\135\208\176\209\129', 'bolt'},
        {'goal', '\208\166\208\181\208\187\209\140 \208\180\208\189\209\143', 'target'}, {'order', '\208\144\208\186\209\130\208\184\208\178\208\189\209\139\208\185 \208\183\208\176\208\186\208\176\208\183', 'truck'},
        {'expenses', '\208\160\208\176\209\129\209\133\208\190\208\180\209\139', 'gas'}, {'skill', '\208\163\209\128\208\190\208\178\208\181\208\189\209\140', 'trophy'},
        {'salary', '\208\145\208\190\208\189\209\131\209\129 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181', 'shield'}, {'promo', '\208\144\208\186\209\134\208\184\209\143', 'bullhorn'},
        {'hp', '\208\161\208\190\209\129\209\130\208\190\209\143\208\189\208\184\208\181 \209\130/\209\129', 'gauge'},
    }
    for i, r in ipairs(rows) do
        ui.checkbox(r[2], o.show, r[1], nil, nil, r[3])
        if i % 2 == 1 then imgui.SameLine(half) end
    end
    imgui.NewLine()
    if ui.iconButton('move', '\208\159\208\181\209\128\208\181\208\188\208\181\209\129\209\130\208\184\209\130\209\140 \208\190\208\178\208\181\209\128\208\187\208\181\208\185', half - 4) then startOverlayEdit() end
    imgui.SameLine(0, 8)
    if ui.iconButton('sync', '\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\191\208\190\208\183\208\184\209\134\208\184\209\142', half - 4) then o.x, o.y = 40, 300 mark('settings') end
    ui.panelEnd()

    ui.panelBegin('st_read', iw, 'sliders', '\208\167\209\130\208\190 \209\129\209\135\208\184\209\130\208\176\209\130\209\140', {'\208\167\209\130\208\190 \208\183\208\176\208\188\208\181\209\135\208\176\208\181\209\130 \209\129\208\186\209\128\208\184\208\191\209\130', '\208\167\209\130\208\190 \209\129\208\186\209\128\208\184\208\191\209\130 \208\183\208\176\208\188\208\181\209\135\208\176\208\181\209\130 \208\178 \208\184\208\179\209\128\208\181. \208\163\208\177\208\181\209\128\208\184\209\130\208\181 \208\179\208\176\208\187\208\190\209\135\208\186\209\131, \208\181\209\129\208\187\208\184 \209\135\209\130\208\190-\209\130\208\190 \209\129\209\135\208\184\209\130\208\176\209\130\209\140 \208\189\208\181 \208\189\209\131\208\182\208\189\208\190. \208\154\209\128\208\176\209\129\208\189\208\176\209\143 \208\186\208\189\208\190\208\191\208\186\208\176 \208\191\208\184\209\130\208\176\208\189\208\184\209\143 \208\190\209\130\208\186\208\187\209\142\209\135\208\176\208\181\209\130 \208\178\209\129\209\145 \209\129\209\128\208\176\208\183\209\131.'})
    local items = {
        {'truck', '\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', 'users', {'\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145', '\208\148\208\181\208\189\209\140\208\179\208\184 \208\190\209\130 \208\189\208\176\208\189\209\143\209\130\209\139\209\133 \208\178\208\190\208\180\208\184\209\130\208\181\208\187\208\181\208\185.'}},
        {'car', '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129', 'car', {'\208\145\208\190\208\189\209\131\209\129\209\139 \208\183\208\176 \209\130\209\128\208\176\208\189\209\129\208\191\208\190\209\128\209\130', '\208\148\208\190\208\191\208\187\208\176\209\130\209\139 \208\183\208\176 \208\187\208\184\209\135\208\189\209\139\208\185 \209\130\209\128\208\176\208\189\209\129\208\191\208\190\209\128\209\130 \208\184 \208\183\208\176 \209\132\209\131\209\128\209\131 (Tier 1, 2, 3).'}},
        {'pack', '\208\162\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186', 'wrench', {'\208\162\209\142\208\189\208\184\208\189\208\179-\208\191\208\176\208\186', '\208\148\208\190\208\191\208\187\208\176\209\130\208\176 \208\183\208\176 \209\131\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\189\209\139\208\185 \209\130\209\142\208\189\208\184\208\189\208\179. \208\151\208\176\208\191\208\184\209\129\209\139\208\178\208\176\208\181\209\130\209\129\209\143 \208\186 \209\129\208\178\208\190\208\181\208\185 \208\188\208\176\209\136\208\184\208\189\208\181.'}},
        {'chests', '\208\155\208\176\209\128\209\134\209\139', 'gift', {'\208\155\208\176\209\128\209\134\209\139', '\208\162\208\190\208\187\209\140\208\186\208\190 \208\187\208\176\209\128\209\134\209\139 \208\180\208\176\208\187\209\140\208\189\208\190\208\177\208\190\208\185\209\137\208\184\208\186\208\176. \208\148\209\128\209\131\208\179\208\184\208\181 \208\187\208\176\209\128\209\134\209\139 \208\184\208\179\208\189\208\190\209\128\208\184\209\128\209\131\209\142\209\130\209\129\209\143.'}},
        {'items', '\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', 'star', {'\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\209\139', '\208\148\208\184\208\178\208\184\208\180\208\181\208\189\208\180\208\189\209\139\208\181 \208\180\208\190\208\179\208\190\208\178\208\190\209\128\209\139. \208\146\208\181\209\135\208\189\209\139\208\181 \208\184 \208\178\209\128\208\181\208\188\208\181\208\189\208\189\209\139\208\181 \209\129\209\135\208\184\209\130\208\176\209\142\209\130\209\129\209\143 \208\190\209\130\208\180\208\181\208\187\209\140\208\189\208\190. \208\148\209\128\209\131\208\179\208\184\208\181 \208\191\209\128\208\181\208\180\208\188\208\181\209\130\209\139 \208\184\208\179\208\189\208\190\209\128\208\184\209\128\209\131\209\142\209\130\209\129\209\143.'}},
        {'other', '\208\159\209\128\208\190\209\135\208\184\208\181 \208\177\208\190\208\189\209\131\209\129\209\139', 'wallet', {'\208\159\209\128\208\190\209\135\208\184\208\181 \208\180\208\190\209\133\208\190\208\180\209\139', '\208\148\208\181\208\189\208\181\208\182\208\189\209\139\208\181 \208\177\208\190\208\189\209\131\209\129\209\139 \208\184 \208\189\208\176\208\179\209\128\208\176\208\180\209\139 \208\183\208\176 \208\176\208\186\209\134\208\184\208\184.'}},
        {'salary', '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176', 'cash', {'\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176', '\208\151\208\176\209\128\208\191\208\187\208\176\209\130\208\176, \208\186\208\190\209\130\208\190\209\128\209\131\209\142 \208\178\209\139 \208\191\208\190\208\187\209\131\209\135\208\176\208\181\209\130\208\181.'}},
        {'promo', '\208\144\208\186\209\134\208\184\208\184 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133', 'bullhorn', {'\208\144\208\186\209\134\208\184\208\184 \208\189\208\176 \209\128\208\176\208\177\208\190\209\130\208\176\209\133', '\208\144\208\186\209\134\208\184\208\184 \208\178\209\128\208\190\208\180\208\181 \194\171+20% \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181\194\187. \208\146 \208\190\208\178\208\181\209\128\208\187\208\181\208\181 \208\178\208\184\208\180\208\189\208\190 \208\191\209\128\208\190\209\134\208\181\208\189\209\130 \208\184 \209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 \208\178\209\128\208\181\208\188\208\181\208\189\208\184, \208\176 \208\177\208\190\208\189\209\131\209\129 \208\184\208\180\209\145\209\130 \208\178 \194\171\208\159\209\128\208\190\209\135\208\184\208\181\194\187.'}},
        {'salaryHint', '\208\145\208\190\208\189\209\131\209\129 \208\190\209\133\209\128\208\176\208\189\208\189\208\184\208\186\208\176 \208\184 \209\136\209\130\209\128\208\176\209\132', 'shield', {'\208\145\208\190\208\189\209\131\209\129 \208\184 \209\136\209\130\209\128\208\176\209\132 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139', '\208\154\208\190\208\179\208\180\208\176 \209\129\208\181\209\128\208\178\208\181\209\128 \208\191\208\184\209\136\208\181\209\130, \209\135\209\130\208\190 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\176 \208\178\209\139\209\128\208\190\209\129\208\187\208\176 \208\184\208\187\208\184 \209\131\208\191\208\176\208\187\208\176 \208\189\208\176 N%, \209\129\208\186\209\128\208\184\208\191\209\130 \208\191\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \209\141\209\130\208\190\209\130 \208\191\209\128\208\190\209\134\208\181\208\189\209\130 \208\178 \208\190\208\178\208\181\209\128\208\187\208\181\208\181. \208\159\209\128\208\190\209\134\208\181\208\189\209\130 \208\177\209\139\208\178\208\176\208\181\209\130 \208\187\209\142\208\177\209\139\208\188.'}},
        {'percent', '\208\159\209\128\208\190\209\134\208\181\208\189\209\130 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\209\139 (\208\190\209\134\208\181\208\189\208\186\208\176)', 'coins', {'\208\159\209\128\208\190\209\134\208\181\208\189\209\130 \208\186\208\176\208\186 \208\180\208\190\209\133\208\190\208\180', '\208\149\209\129\208\187\208\184 \209\129\208\181\209\128\208\178\208\181\209\128 \209\129\208\190\208\190\208\177\209\137\208\184\208\187 \208\190 \208\191\209\128\208\184\208\177\208\176\208\178\208\186\208\181 \208\186 \208\183\208\176\209\128\208\191\208\187\208\176\209\130\208\181, \208\189\208\190 \208\180\208\181\208\189\209\140\208\179\208\184 \208\183\208\176 \208\189\208\181\209\145 \208\189\208\181 \208\191\209\128\208\184\209\136\208\187\208\184, \209\129\208\186\209\128\208\184\208\191\209\130 \208\180\208\190\208\177\208\176\208\178\208\184\209\130 \208\181\209\145 \208\186 \209\128\208\181\208\185\209\129\209\131 \208\186\208\176\208\186 \208\190\209\134\208\181\208\189\208\186\209\131 (\209\141\209\130\208\190 \208\191\208\190\208\188\208\181\209\135\208\181\208\189\208\190). \208\157\208\181 \208\189\209\131\208\182\208\189\208\190 - \208\178\209\139\208\186\208\187\209\142\209\135\208\184\209\130\208\181.'}},
        {'expenses', '\208\160\208\176\209\129\209\133\208\190\208\180\209\139', 'gas', {'\208\160\208\176\209\129\209\133\208\190\208\180\209\139', '\208\162\209\128\208\176\209\130\209\139 \208\189\208\176 \208\183\208\176\208\191\209\128\208\176\208\178\208\186\209\131, \209\128\208\181\208\188\208\190\208\189\209\130 \208\184 \209\136\209\130\209\128\208\176\209\132\209\139.'}},
        {'orders', '\208\161\208\187\208\181\208\182\208\181\208\189\208\184\208\181 \208\183\208\176 \208\183\208\176\208\186\208\176\208\183\208\190\208\188', 'box', {'\208\161\208\187\208\181\208\182\208\181\208\189\208\184\208\181 \208\183\208\176 \208\183\208\176\208\186\208\176\208\183\208\190\208\188', '\208\159\208\190\208\186\208\176\208\183\209\139\208\178\208\176\208\181\209\130 \208\178\208\183\209\143\209\130\209\139\208\185 \208\183\208\176\208\186\208\176\208\183 \208\178 \208\190\208\178\208\181\209\128\208\187\208\181\208\181 (\209\129\208\186\208\190\208\187\209\140\208\186\208\190 \208\190\209\129\209\130\208\176\208\187\208\190\209\129\209\140 \208\178\209\128\208\181\208\188\208\181\208\189\208\184) \208\184 \208\183\208\176\208\191\208\184\209\129\209\139\208\178\208\176\208\181\209\130 \209\129\208\180\208\176\208\189\208\189\209\139\208\181 \208\183\208\176\208\186\208\176\208\183\209\139 \208\178 \208\184\209\129\209\130\208\190\209\128\208\184\209\142.'}},
        {'silent', '\208\148\208\181\208\189\209\140\208\179\208\184 \208\177\208\181\208\183 \209\129\208\190\208\190\208\177\209\137\208\181\208\189\208\184\209\143', 'coins', {'\208\148\208\181\208\189\209\140\208\179\208\184 \208\177\208\181\208\183 \209\129\208\190\208\190\208\177\209\137\208\181\208\189\208\184\209\143', '\208\148\208\181\208\189\209\140\208\179\208\184 \208\177\208\181\208\183 \208\191\208\190\209\143\209\129\208\189\208\181\208\189\208\184\209\143, \208\191\208\190\208\186\208\176 \208\178\209\139 \208\178 \209\128\208\176\208\177\208\190\209\130\208\181, \209\129\209\135\208\184\209\130\208\176\209\142\209\130\209\129\209\143 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\186\208\190\208\188. \208\159\208\190\208\180\208\176\209\128\208\186\208\184 \208\184 \208\191\208\181\209\128\208\181\208\178\208\190\208\180\209\139 \208\189\208\181 \209\129\209\135\208\184\209\130\208\176\209\142\209\130\209\129\209\143.'}},
        {'unknown', '\208\155\209\142\208\177\209\139\208\181 \208\189\208\181\208\190\208\191\208\190\208\183\208\189\208\176\208\189\208\189\209\139\208\181', 'warn', {'\208\157\208\181 \209\128\208\181\208\186\208\190\208\188\208\181\208\189\208\180\209\131\208\181\209\130\209\129\209\143', '\208\155\209\142\208\177\209\139\208\181 \208\189\208\181\208\191\208\190\208\189\209\143\209\130\208\189\209\139\208\181 \208\180\208\181\208\189\209\140\208\179\208\184 \209\129\209\130\208\176\208\189\209\131\209\130 \208\180\208\190\209\133\208\190\208\180\208\190\208\188 (\208\186\209\128\208\190\208\188\208\181 \208\191\208\190\208\180\208\176\209\128\208\186\208\190\208\178 \208\184 \208\191\208\181\209\128\208\181\208\178\208\190\208\180\208\190\208\178). \208\151\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \208\188\208\190\208\182\208\181\209\130 \208\191\208\190\208\187\209\131\209\135\208\184\209\130\209\140\209\129\209\143 \208\183\208\176\208\178\209\139\209\136\208\181\208\189\208\189\209\139\208\188.'}},
    }
    for i, item in ipairs(items) do
        ui.checkbox(item[2], cfg.track, item[1], nil, item[4], item[3])
        if i % 2 == 1 then imgui.SameLine(half) end
    end
    imgui.NewLine()
    ui.checkbox('\208\145\208\190\208\189\209\131\209\129 38.587 = 38 587 \209\128\209\131\208\177.', cfg, 'bonus_dot_thousands', nil,
        {'\208\162\208\190\209\135\208\186\208\176 \208\178 \209\129\209\131\208\188\208\188\208\181', '\208\146 \208\177\208\190\208\189\209\131\209\129\208\176\209\133 \209\130\208\190\209\135\208\186\208\176 - \209\141\209\130\208\190 \209\128\208\176\208\183\208\180\208\181\208\187\208\184\209\130\208\181\208\187\209\140 \209\130\209\139\209\129\209\143\209\135: 38.587 \208\183\208\189\208\176\209\135\208\184\209\130 38 587 \209\128\209\131\208\177\208\187\208\181\208\185.'}, 'percent')
    if cfg.track.unknown or cfg.track.silent then
        imgui.PushItemWidth(180)
        ui.inputInt('\208\156\208\184\208\189\208\184\208\188\209\131\208\188, \209\128\209\131\208\177.', cfg, 'other_min', 500, 5000)
        ui.inputInt('\208\156\208\176\208\186\209\129\208\184\208\188\209\131\208\188, \209\128\209\131\208\177. (0 - \208\177\208\181\208\183 \208\187\208\184\208\188\208\184\209\130\208\176)', cfg, 'other_max', 5000, 50000,
            {'\208\159\208\190\209\128\208\190\208\179\208\184', '\208\161\209\131\208\188\208\188\209\139 \208\188\208\181\208\189\209\140\209\136\208\181 \208\188\208\184\208\189\208\184\208\188\209\131\208\188\208\176 \208\184\208\187\208\184 \208\177\208\190\208\187\209\140\209\136\208\181 \208\188\208\176\208\186\209\129\208\184\208\188\209\131\208\188\208\176 \208\178 \208\180\208\190\209\133\208\190\208\180 \208\189\208\181 \208\184\208\180\209\131\209\130.'})
        imgui.PopItemWidth()
    end
    ui.panelEnd()

    ui.panelBegin('st_notify', iw, 'bell', '\208\163\208\178\208\181\208\180\208\190\208\188\208\187\208\181\208\189\208\184\209\143')
    ui.checkbox('\208\161\208\190\208\190\208\177\209\137\208\181\208\189\208\184\209\143 \208\178 \209\135\208\176\209\130 \208\190 \208\180\208\190\209\133\208\190\208\180\208\181', cfg, 'notify', nil, {'\208\161\208\190\208\190\208\177\209\137\208\181\208\189\208\184\209\143 \208\178 \209\135\208\176\209\130', '\208\161\208\186\209\128\208\184\208\191\209\130 \208\191\208\184\209\136\208\181\209\130 \208\178 \209\135\208\176\209\130 \208\190 \208\186\208\176\208\182\208\180\208\190\208\185 \208\178\209\139\208\191\208\187\208\176\209\130\208\181, \209\129\208\180\208\176\208\189\208\189\208\190\208\188 \208\183\208\176\208\186\208\176\208\183\208\181 \208\184 \208\191\209\128\208\181\208\180\208\188\208\181\209\130\208\181.'}, 'bell')
    ui.panelEnd()

    ui.panelBegin('st_data', iw, 'save', '\208\148\208\176\208\189\208\189\209\139\208\181', {'\208\165\209\128\208\176\208\189\208\181\208\189\208\184\208\181', '\208\161\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \209\133\209\128\208\176\208\189\208\184\209\130\209\129\209\143 7 \208\180\208\189\208\181\208\185. \208\146 \208\191\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185 \208\180\208\181\208\189\209\140 \209\129\208\186\209\128\208\184\208\191\209\130 \208\191\209\128\208\181\208\180\209\131\208\191\209\128\208\181\208\180\208\184\209\130 \208\184 \209\129\208\190\209\133\209\128\208\176\208\189\208\184\209\130 \208\184\209\130\208\190\208\179\208\184 \208\178 \208\176\209\128\209\133\208\184\208\178, \208\191\208\190\209\130\208\190\208\188 \208\189\208\176\209\135\208\189\209\145\209\130\209\129\209\143 \208\189\208\190\208\178\208\176\209\143 \208\189\208\181\208\180\208\181\208\187\209\143. \208\148\208\176\208\189\208\189\209\139\208\181 \209\129\208\190\209\133\209\128\208\176\208\189\209\143\209\142\209\130\209\129\209\143 \209\129\208\176\208\188\208\184.'})
    local week = Data.weekInfo()
    ui.labelValue('\208\157\208\181\208\180\208\181\208\187\209\143 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\184', '\208\180\208\181\208\189\209\140 ' .. week.day .. ' \208\184\208\183 ' .. week.total .. (week.lastDay and ' (\208\191\208\190\209\129\208\187\208\181\208\180\208\189\208\184\208\185)' or ''), week.lastDay and RED or nil, inner)
    imgui.Spacing()
    imgui.PushItemWidth(120)
    ui.inputInt('\208\161\208\177\209\128\208\176\209\129\209\139\208\178\208\176\209\130\209\140 \209\129\208\181\209\129\209\129\208\184\209\142 \208\186\208\176\208\182\208\180\209\139\208\181 N \209\135', cfg, 'sessionHours', 1, 1,
        {'\208\144\208\178\209\130\208\190\209\129\208\177\209\128\208\190\209\129 \209\129\208\181\209\129\209\129\208\184\208\184', '\208\161\208\177\209\128\208\176\209\129\209\139\208\178\208\176\208\181\209\130 \209\130\208\190\208\187\209\140\208\186\208\190 \209\129\209\135\209\145\209\130\209\135\208\184\208\186 \209\129\208\181\209\129\209\129\208\184\208\184 (\208\178\209\128\208\181\208\188\209\143 \208\184 \194\171\208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\176\208\189\208\190 \208\183\208\176 \209\129\208\181\209\129\209\129\208\184\209\142\194\187). \208\158\208\177\209\137\208\176\209\143 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \208\190\209\129\209\130\208\176\209\145\209\130\209\129\209\143. 0 - \208\189\208\181 \209\129\208\177\209\128\208\176\209\129\209\139\208\178\208\176\209\130\209\140.'})
    imgui.PopItemWidth()
    imgui.Spacing()
    local bw = half - 4
    if ui.iconButton('history', '\208\152\209\130\208\190\208\179\208\184 \208\189\208\181\208\180\208\181\208\187\208\184 \208\178 \208\176\209\128\209\133\208\184\208\178', bw) then pending.archive = true end
    imgui.SameLine(0, 8)
    if UI.confirmReset > os.clock() then
        if ui.dangerButton('trash', '\208\162\208\190\209\135\208\189\208\190 \209\129\208\177\209\128\208\190\209\129\208\184\209\130\209\140?', bw) then
            UI.confirmReset = 0
            pending.resetStats = true
        end
    else
        if ui.iconButton('trash', '\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\209\131', bw) then UI.confirmReset = os.clock() + 4 end
    end
    if UI.confirmAll > os.clock() then
        if ui.dangerButton('trash', '\208\162\208\190\209\135\208\189\208\190 \209\129\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\146\208\161\208\129?', bw) then
            UI.confirmAll = 0
            pending.resetAll = true
        end
    else
        if ui.iconButton('trash', '\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\178\209\129\209\145', bw) then UI.confirmAll = os.clock() + 4 end
    end
    imgui.SameLine(0, 8)
    ui.help('\208\161\208\177\209\128\208\190\209\129', '\194\171\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\209\131\194\187 \208\190\208\177\208\189\209\131\208\187\209\143\208\181\209\130 \208\183\208\176\209\128\208\176\208\177\208\190\209\130\208\190\208\186 \208\184 \208\184\209\129\209\130\208\190\209\128\208\184\209\142. \194\171\208\161\208\177\209\128\208\190\209\129\208\184\209\130\209\140 \208\178\209\129\209\145\194\187 \208\190\209\135\208\184\209\137\208\176\208\181\209\130 \208\178\208\190\208\190\208\177\209\137\208\181 \208\178\209\129\209\145, \208\178\208\186\208\187\209\142\209\135\208\176\209\143 \208\189\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184.')
    ui.panelEnd()
end

local function openMenu()
    menu.v = true
    UI.menuX, UI.menuY = nil, nil
    UI.menuTarget = 1
    UI.menuLast = os.clock()
end

local function closeMenu()
    UI.menuTarget = 0
end

local drawMenu, drawOffPanel
do
local TABS = {
    {id = 'dashboard',    icon = 'home',    name = '\208\158\208\177\208\183\208\190\209\128'},
    {id = 'orders',       icon = 'list',    name = '\208\151\208\176\208\186\208\176\208\183\209\139'},
    {id = 'orderHistory', icon = 'history', name = '\208\152\209\129\209\130\208\190\209\128\208\184\209\143 \208\183\208\176\208\186\208\176\208\183\208\190\208\178'},
    {id = 'truck',        icon = 'users',   name = '\208\160\208\176\208\177\208\190\209\130\208\189\208\184\208\186\208\184 \208\148\208\145'},
    {id = 'car',          icon = 'car',     name = '\208\145\208\190\208\189\209\131\209\129\209\139 \209\130/\209\129'},
    {id = 'items',        icon = 'gift',    name = '\208\159\209\128\208\181\208\180\208\188\208\181\209\130\209\139'},
    {id = 'other',        icon = 'wallet',  name = '\208\159\209\128\208\190\209\135\208\184\208\181 \208\180\208\190\209\133\208\190\208\180\209\139'},
    {id = 'analytics',    icon = 'chart',   name = '\208\144\208\189\208\176\208\187\208\184\209\130\208\184\208\186\208\176'},
    {id = 'settings',     icon = 'cog',     name = '\208\157\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184'},
    {id = 'faq',          icon = 'question', name = 'FAQ'},
}

local MW, MH, SIDE_W
do
    local vw, vh = imgui.MB.res()
    MW = math.floor(math.max(700, math.min(1040, vw - 30)))
    MH = math.floor(math.max(420, math.min(600, vh - 30)))
    SIDE_W = 215
end

local function updateMenuAnim(now)
    local step = math.min(0.1, now - UI.menuLast) / 0.18
    UI.menuLast = now
    if UI.menuAlpha < UI.menuTarget then
        UI.menuAlpha = math.min(UI.menuTarget, UI.menuAlpha + step)
    elseif UI.menuAlpha > UI.menuTarget then
        UI.menuAlpha = math.max(UI.menuTarget, UI.menuAlpha - step)
    end
    if UI.menuTarget == 0 and UI.menuAlpha <= 0.001 then menu.v = false end
end

local function tabButton(i, w, h)
    local tabInfo = TABS[i]
    local selected = UI.tab == i
    local p = imgui.GetCursorScreenPos()
    if imgui.InvisibleButton('##tab' .. i, imgui.ImVec2(w, h)) then UI.tab = i end
    local hovered = imgui.IsItemHovered()
    local drawList = imgui.GetWindowDrawList()
    if selected then
        drawList:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), accentColor32(0.18), 8)
        drawList:AddRectFilled(imgui.ImVec2(p.x, p.y + 8), imgui.ImVec2(p.x + 3, p.y + h - 8), accentColor32(1), 2)
    elseif hovered then
        drawList:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), packColor(255, 255, 255, 0.06), 8)
    end
    drawList:AddText(imgui.ImVec2(p.x + 14, p.y + h / 2 - 8), selected and accentColor32(1) or packColor(140, 148, 165, 1), icons[tabInfo.icon])
    drawList:AddText(imgui.ImVec2(p.x + 42, p.y + h / 2 - 8), selected and packColor(255, 255, 255, 1) or packColor(170, 176, 192, 1), tabInfo.name)
end

local function renderPage(cw)
    local id = TABS[UI.tab].id
    if id == 'dashboard' then pages.dashboard(cw)
    elseif id == 'orders' then pages.orders(cw)
    elseif id == 'orderHistory' then pages.orderHistory(cw)
    elseif id == 'truck' or id == 'car' or id == 'other' then pages.income(id, cw)
    elseif id == 'items' then pages.items(cw)
    elseif id == 'analytics' then pages.analytics(cw)
    elseif id == 'settings' then pages.settings(cw)
    elseif id == 'faq' then pages.faq(cw) end
end

local function forwardWheel()
    local wheel = 0
    pcall(function() wheel = imgui.GetIO().MouseWheel end)
    if wheel ~= 0 and not UI.wheelConsumed and not imgui.IsWindowHovered() then
        local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
        if imgui.IsMouseHoveringRect(pos, imgui.ImVec2(pos.x + size.x, pos.y + size.y)) then
            local y = imgui.GetScrollY() - wheel * 60
            imgui.SetScrollY(math.max(0, math.min(imgui.GetScrollMaxY(), y)))
        end
    end
    imgui.MB.touchScroll()
    UI.wheelConsumed = false
end

function drawMenu()
    updateMenuAnim(os.clock())
    if not menu.v then return end
    UI.helpId = 0
    local sx, sy = imgui.MB.res()

    pushVar(imgui.StyleVar.Alpha, math.max(0.02, UI.menuAlpha))
    pushFont(fonts.main)
    local x = UI.menuX or (cfg.menu.x >= 0 and cfg.menu.x) or (sx / 2 - MW / 2)
    local y = UI.menuY or (cfg.menu.y >= 0 and cfg.menu.y) or (sy / 2 - MH / 2)
    x = math.max(0, math.min(sx - MW, x))
    y = math.max(0, math.min(sy - 80, y))
    imgui.SetNextWindowSize(imgui.ImVec2(MW, MH), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(x, y + (1 - UI.menuAlpha) * 18), imgui.Cond.Always)
    beginWin('##th_menu', nil, ui.wflags('NoTitleBar', 'NoResize', 'NoCollapse', 'NoSavedSettings', 'NoScrollbar', 'NoMove'))

    pushFont(fonts.title)
    ui.iconText('truck', 'Truck Helper', nil, nil, 28)
    popFont(fonts.title)
    imgui.SameLine(0, 10)
    imgui.TextColored(DIM, 'v' .. SCRIPT_VERSION .. ' | By Stalin |')
    imgui.SameLine(0, 6)
    if ui.link('\208\162\208\147\208\154', '\208\158\209\130\208\186\209\128\209\139\209\130\209\140 Telegram-\208\186\208\176\208\189\208\176\208\187') then pending.openLink = TELEGRAM_URL end
    local week = Data.weekInfo()
    local weekText = '\208\157\208\181\208\180\208\181\208\187\209\143: \208\180\208\181\208\189\209\140 ' .. week.day .. '/' .. week.total
    local weekX = MW - 130 - imgui.CalcTextSize(weekText).x
    imgui.SameLine(0, 6)
    local dragW = math.max(20, weekX - imgui.GetCursorPosX() - 8)
    imgui.InvisibleButton('##th_drag', imgui.ImVec2(dragW, 28))
    if imgui.IsItemActive() then
        local mouse, winPos = imgui.GetMousePos(), imgui.GetWindowPos()
        if not UI.dragOffset then UI.dragOffset = {x = mouse.x - winPos.x, y = mouse.y - winPos.y} end
        UI.menuX, UI.menuY = mouse.x - UI.dragOffset.x, mouse.y - UI.dragOffset.y
        UI.dragging = true
    else
        UI.dragOffset = nil
        if UI.dragging then
            UI.dragging = false
            cfg.menu.x, cfg.menu.y = UI.menuX or -1, UI.menuY or -1
            mark('settings')
        end
    end
    if imgui.IsItemHovered() and not UI.dragging then imgui.SetTooltip('\208\159\208\190\209\130\209\143\208\189\208\184\209\130\208\181, \209\135\209\130\208\190\208\177\209\139 \208\191\208\181\209\128\208\181\208\188\208\181\209\129\209\130\208\184\209\130\209\140 \208\190\208\186\208\189\208\190') end
    imgui.SameLine(weekX)
    imgui.TextColored(week.lastDay and RED or DIM, weekText)
    imgui.SameLine(MW - 114)
    if ui.coloredButton(icons.power .. '##th_power', 44, 28, 255, 82, 82) then pending.disable = true end
    if imgui.IsItemHovered() then imgui.SetTooltip('\208\146\209\139\208\186\208\187\209\142\209\135\208\184\209\130\209\140 \209\129\208\186\209\128\208\184\208\191\209\130 \208\191\208\190\208\187\208\189\208\190\209\129\209\130\209\140\209\142') end
    imgui.SameLine(0, 6)
    if imgui.Button(icons.close .. '##th_close', imgui.ImVec2(44, 28)) then closeMenu() end
    if imgui.IsItemHovered() then imgui.SetTooltip('\208\151\208\176\208\186\209\128\209\139\209\130\209\140') end
    imgui.Separator()

    local bodyH = imgui.GetWindowHeight() - imgui.GetCursorPosY() - 12
    beginChildP(8, 8, '##th_side', imgui.ImVec2(SIDE_W, bodyH), true, ui.wflags('NoScrollbar'))
    for i = 1, #TABS do
        tabButton(i, SIDE_W - 20, 38)
        imgui.Spacing()
    end
    imgui.MB.touchScroll()
    endChildP()

    imgui.SameLine(0, 10)
    beginChildP(16, 12, '##th_content', imgui.ImVec2(0, bodyH), true)
    renderPage(math.floor(imgui.GetContentRegionAvailWidth()) - 2)
    forwardWheel()
    endChildP()

    endWin()
    popFont(fonts.main)
    popVar(1)
end

function drawOffPanel()
    updateMenuAnim(os.clock())
    if not menu.v then return end
    local sx, sy = imgui.MB.res()
    local w, h = 360, 150
    pushVar(imgui.StyleVar.Alpha, math.max(0.02, UI.menuAlpha))
    pushVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(18, 16))
    pushFont(fonts.main)
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sx / 2 - w / 2, sy / 2 - h / 2 + (1 - UI.menuAlpha) * 18), imgui.Cond.Always)
    beginWin('##th_off', nil, ui.wflags('NoTitleBar', 'NoResize', 'NoCollapse', 'NoSavedSettings', 'NoScrollbar'))
    pushFont(fonts.title)
    ui.iconText('power', 'Truck Helper \208\178\209\139\208\186\208\187\209\142\209\135\208\181\208\189', RED, nil, 28)
    popFont(fonts.title)
    imgui.Separator()
    imgui.TextColored(DIM, '\208\159\208\190\208\180\209\129\209\135\209\145\209\130, \208\190\208\178\208\181\209\128\208\187\208\181\208\185 \208\184 \208\191\208\190\208\180\209\129\208\186\208\176\208\183\208\186\208\184 \208\190\209\130\208\186\208\187\209\142\209\135\208\181\208\189\209\139.')
    imgui.Spacing()
    if imgui.Button(icons.power .. '  \208\146\208\186\208\187\209\142\209\135\208\184\209\130\209\140##th_on', imgui.ImVec2(160, 32)) then pending.enable = true end
    imgui.SameLine(0, 10)
    if imgui.Button(icons.close .. '  \208\151\208\176\208\186\209\128\209\139\209\130\209\140##th_off_close', imgui.ImVec2(140, 32)) then closeMenu() end
    endWin()
    popFont(fonts.main)
    popVar(2)
end
end

local function guarded(name, fn)
    if (UI.dead[name] or 0) > os.clock() then return false end
    if not safeCall(name, fn) then
        UI.dead[name] = os.clock() + 3
        return false
    end
    return true
end

function Orders.drawTake()
    local sx, sy = imgui.MB.res()
    local scale = cfg.orders.scale
    local width = math.floor(Orders.CARD_WIDTH * scale)
    local mob = Orders.state.mobile
    local bw, bh = 150, 46
    if mob then bw = math.floor(76 * math.max(0.8, scale)) bh = bw end
    local cx, cy = sx * cfg.orders.x / 100, sy * cfg.orders.y / 100
    local x = cx + width / 2 + 10
    if x + bw > sx then x = cx - width / 2 - bw - 10 end
    x = math.max(0, math.min(sx - bw, x))
    local y = math.max(0, math.min(sy - bh - 10, cy))
    local bxp, byp = cfg.orders.bx or -1, cfg.orders.by or -1
    if mob and bxp >= 0 and byp >= 0 then
        x = math.max(0, math.min(sx - bw, sx * bxp / 100 - bw / 2))
        y = math.max(0, math.min(sy - bh, sy * byp / 100 - bh / 2))
    end
    pushFont(fonts.main)
    imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.Always)
    if mob then
        pushVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
        pushVar(imgui.StyleVar.WindowBorderSize, 0)
        pushCol(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
        beginWin('##th_take', nil, ui.wflags('NoTitleBar', 'NoResize', 'AlwaysAutoResize', 'NoScrollbar', 'NoSavedSettings', 'NoFocusOnAppearing', 'NoBackground'))
        local p = imgui.GetCursorScreenPos()
        local clicked = imgui.InvisibleButton('##th_take_btn', imgui.ImVec2(bw, bh))
        local held = imgui.IsItemActive()
        local drag = Orders.state.takeDrag
        if not drag then drag = {moved = 0} Orders.state.takeDrag = drag end
        if held then
            local d = imgui.GetIO().MouseDelta
            local K = imgui.MB.K
            local dx, dy = d.x / K, d.y / K
            drag.moved = drag.moved + math.abs(dx) + math.abs(dy)
            if drag.moved > 8 then
                local ncx, ncy = x + bw / 2 + dx, y + bh / 2 + dy
                cfg.orders.bx = math.max(0, math.min(100, ncx / sx * 100))
                cfg.orders.by = math.max(0, math.min(100, ncy / sy * 100))
            end
        end
        local c = imgui.ImVec2(p.x + bw / 2, p.y + bh / 2)
        local dl = imgui.GetWindowDrawList()
        dl:AddCircleFilled(imgui.ImVec2(c.x, c.y + 3), bw / 2, packColor(0, 0, 0, 0.35), 48)
        dl:AddCircleFilled(c, bw / 2, held and packColor(ACC.r * 0.7, ACC.g * 0.7, ACC.b * 0.7, 1) or accentColor32(1), 48)
        dl:AddCircle(c, bw / 2 - 1, packColor(255, 255, 255, 0.85), 48, 2)
        local glyph = icons.truck
        imgui.SetWindowFontScale(1.9 * math.max(0.8, scale))
        local ts = imgui.CalcTextSize(glyph)
        dl:AddText(imgui.ImVec2(c.x - ts.x / 2, c.y - ts.y / 2), packColor(255, 255, 255, 1), glyph)
        imgui.SetWindowFontScale(1)
        if clicked then
            if drag.moved <= 8 then Orders.pickBest() else mark('settings') end
        end
        if not held then drag.moved = 0 end
        endWin()
        popCol(1)
        popVar(2)
    else
        pushVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(6, 6))
        beginWin('##th_take', nil, ui.wflags('NoTitleBar', 'NoResize', 'AlwaysAutoResize', 'NoScrollbar', 'NoSavedSettings', 'NoFocusOnAppearing'))
        if imgui.Button(icons.bolt .. '  \208\146\208\183\209\143\209\130\209\140##th_take_btn', imgui.ImVec2(bw, bh)) then Orders.pickBest() end
        endWin()
        popVar(1)
    end
    popFont(fonts.main)
end

function imgui.OnDrawFrame()
    if not ENC_OK then return end
    if imgui.MB.theme then imgui.MB.theme = false pcall(applyTheme) end
    if not cfg.enabled then
        if menu.v then guarded('off', drawOffPanel) end
        return
    end
    if cfg.overlay.enabled or UI.overlayEdit then
        local hidden = cfg.overlay.hideOnCursor and not UI.overlayEdit and not menu.v and Orders.cursorVisible()
        if not hidden then guarded('overlay', drawOverlay) end
    end
    if Orders.needsDraw(Orders.cardAlpha()) then
        if not guarded('card', Orders.drawCard) then Orders.lastReason = 'error' end
    end
    if cfg.orders.enabled and (Orders.state.windowOpen or Orders.demoActive()) and not (Orders.state.takeBroken and not Orders.demoActive()) and not Orders.state.editing and not menu.v then guarded('take', Orders.drawTake) end
    if menu.v and not guarded('menu', drawMenu) then closeMenu() end
end

imgui.OnFrame(function() return imgui.Process == true end, function() imgui.OnDrawFrame() end)


function main()
    repeat wait(0) until isSampAvailable()

    if not ENC_OK then
        sampAddChatMessage('{FF5555}[Truck Helper]: ENCODING ERROR - the script file is damaged, download it again and reload (Ctrl+R).', -1)
        wait(-1)
    end

    imgui.MB.theme = true
    Data.checkWeek()

    sampRegisterChatCommand('dbo', function() Orders.pickBest(true) end)
    sampRegisterChatCommand('db', function()
        if menu.v and UI.menuTarget == 1 then closeMenu() else openMenu() end
    end)

    sayBanner()
    if migrated then say('\208\148\208\176\208\189\208\189\209\139\208\181 \208\184\208\183 \208\191\209\128\208\190\209\136\208\187\208\190\208\185 \208\178\208\181\209\128\209\129\208\184\208\184 (v2.0) \208\184\208\188\208\191\208\190\209\128\209\130\208\184\209\128\208\190\208\178\208\176\208\189\209\139.') end
    if session.workStart and #session.log > 0 then say('\208\161\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \209\129\208\181\209\129\209\129\208\184\208\184 \208\178\208\190\209\129\209\129\209\130\208\176\208\189\208\190\208\178\208\187\208\181\208\189\208\176 \208\191\208\190\209\129\208\187\208\181 \208\191\208\181\209\128\208\181\208\183\208\176\208\179\209\128\209\131\208\183\208\186\208\184.') end

    local last_poll, last_flush, last_snapshot, last_week, last_rainbow = 0, 0, 0, 0, 0
    while true do
        wait(0)
        local now = os.clock()

        local wantProcess = menu.v
        if cfg.enabled then
            wantProcess = wantProcess or cfg.overlay.enabled or UI.overlayEdit or Orders.needsDraw(Orders.cardAlpha())
            wantProcess = wantProcess or (cfg.orders.enabled and Orders.state.windowOpen and not Orders.state.editing)
        end
        imgui.Process = wantProcess
        imgui.ShowCursor = menu.v or UI.overlayEdit or Orders.state.editing

        flushChat()

        local theme = THEMES[cfg.theme]
        if theme and theme.rainbow and now - last_rainbow >= 0.05 then
            last_rainbow = now
            imgui.MB.theme = true
        end

        if pending.theme then pending.theme = false imgui.MB.theme = true end
        if pending.save then
            pending.save = false
            for _, n in ipairs({'settings', 'stats', 'history', 'vehicles', 'items'}) do mark(n) end
            say(saveAll() and '\208\148\208\176\208\189\208\189\209\139\208\181 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\209\139.' or '\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \209\129\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140 \208\180\208\176\208\189\208\189\209\139\208\181!')
        end
        if pending.archive then
            pending.archive = false
            local path = Data.archive('manual')
            say(path and ('\208\152\209\130\208\190\208\179\208\184 \208\189\208\181\208\180\208\181\208\187\208\184 \209\129\208\190\209\133\209\128\208\176\208\189\208\181\208\189\209\139: ' .. path) or '\208\157\208\181 \209\131\208\180\208\176\208\187\208\190\209\129\209\140 \209\129\208\190\209\133\209\128\208\176\208\189\208\184\209\130\209\140 \208\184\209\130\208\190\208\179\208\184.')
        end
        if pending.resetStats then
            pending.resetStats = false
            Data.resetStatistics()
            say('\208\161\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176 \209\129\208\177\209\128\208\190\209\136\208\181\208\189\208\176.')
        end
        if pending.resetAll then
            pending.resetAll = false
            Data.resetAll()
            pending.theme = true
            say('\208\146\209\129\209\145 \209\129\208\177\209\128\208\190\209\136\208\181\208\189\208\190: \209\129\209\130\208\176\209\130\208\184\209\129\209\130\208\184\208\186\208\176, \208\184\209\129\209\130\208\190\209\128\208\184\209\143, \208\183\208\176\208\186\208\176\208\183\209\139, \208\186\208\176\209\130\208\176\208\187\208\190\208\179\208\184 \208\184 \208\189\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184.')
        end
        if pending.openLink then
            local url = pending.openLink
            pending.openLink = nil
            if url == TELEGRAM_URL or url == BOT_URL then
                pcall(setClipboardText, url)
                say('\208\161\209\129\209\139\208\187\208\186\208\176 \209\129\208\186\208\190\208\191\208\184\209\128\208\190\208\178\208\176\208\189\208\176 \208\178 \208\177\209\131\209\132\208\181\209\128 \208\190\208\177\208\188\208\181\208\189\208\176: ' .. url)
            end
        end
        if pending.disable then
            pending.disable = false
            Data.setEnabled(false)
        end
        if pending.enable then
            pending.enable = false
            Data.setEnabled(true)
        end

        if fonts_ready and font_keep.noFont and not font_keep.warned then
            font_keep.warned = true
            say('\208\157\208\181 \208\189\208\176\208\185\208\180\208\181\208\189 \209\136\209\128\208\184\209\132\209\130 \209\129 \208\186\208\184\209\128\208\184\208\187\208\187\208\184\209\134\208\181\208\185 (/system/fonts/Roboto-Regular.ttf). \208\159\208\190\208\187\208\190\208\182\208\184\209\130\208\181 arial.ttf \208\178 moonloader/resource/fonts.')
        end
        if fonts_ready and not fa_ok and not fa_warned then
            fa_warned = true
            say('\208\157\208\181 \208\189\208\176\208\185\208\180\208\181\208\189 moonloader/resource/fonts/fa-solid-900.ttf - \208\184\208\186\208\190\208\189\208\186\208\184 \208\190\209\130\208\186\208\187\209\142\209\135\208\181\208\189\209\139.')
        end

        if cfg.enabled then
            Orders.tick(now)

            if now - last_flush >= 0.5 then
                last_flush = now
                Ledger.settleUnclaimedGains(now)
            end

            if not money_events_seen and now - last_poll >= 1 then
                last_poll = now
                local m = readMoney()
                if m then Ledger.applyBalance(m) end
            end

            if now - last_snapshot >= 20 then
                last_snapshot = now
                session.lastSeen = os.time()
                Orders.snapshotActive()
                mark('stats')
            end
        end

        if now - last_week >= 30 then
            last_week = now
            Data.checkWeek()
            if cfg.enabled and cfg.sessionHours > 0 and os.time() - session.start >= cfg.sessionHours * 3600 then
                Data.newSession()
                say('\208\161\208\181\209\129\209\129\208\184\209\143 \209\129\208\177\209\128\208\190\209\136\208\181\208\189\208\176 \208\191\208\190 \209\130\208\176\208\185\208\188\208\181\209\128\209\131.')
            end
        end

        if next(dirty) and now - last_save >= 3 then
            last_save = now
            saveAll()
        end
    end
end

function onScriptTerminate(scr, quit_game)
    if scr == thisScript() then
        session.lastSeen = os.time()
        pcall(Orders.snapshotActive)
        mark('stats')
        saveAll()
    end
end