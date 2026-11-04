script_name("Klad Helper")
script_authors("Edward")

local ev = require 'samp.events'
local json = require 'dkjson'
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local CFG_DIR   = getWorkingDirectory() .. '/config'
local CHAT_UTF8 = false

local function chat(s)
    if CHAT_UTF8 then s = u8(s) end
    sampAddChatMessage(s, -1)
end

local function looksUtf8(s)
    local i, n, multi = 1, #s, false
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then i = i + 1
        elseif b >= 0xC2 and b <= 0xDF then
            local c = s:byte(i + 1); if not c or c < 0x80 or c > 0xBF then return false end
            i = i + 2; multi = true
        elseif b >= 0xE0 and b <= 0xEF then
            local c1, c2 = s:byte(i + 1), s:byte(i + 2)
            if not c1 or not c2 or c1 < 0x80 or c1 > 0xBF or c2 < 0x80 or c2 > 0xBF then return false end
            i = i + 3; multi = true
        else return false end
    end
    return multi
end
local function norm(s)
    s = tostring(s or "")
    if looksUtf8(s) then
        local ok, d = pcall(function() return u8:decode(s) end)
        if ok and d then return d end
    end
    return s
end
local ITEMS_LIST = {
    "Укроп","Материалы","Золото","Серебро","Мото ящик","Крышечка R-Cola","Подарок",
    "Сертификат на AZ Coins","Семейный талон","Бронза","Ящик Marvel","Ящик Американских звезд",
    "Авто ящик","Ящик Джентльмена","Бронзовая рулетка","Серебряная рулетка","Золотая рулетка",
    "Коленвал (improv)","Распредвал (improv)","Прямоток (improv)","Турбокомпрессор (improv)",
    "Нагнетатель (improv)","Сцепление (improv)","КПП (improv)","Дифференциал (improv)",
    "Подвеска (improv)","Тормоза (improv)",
    "Коленвал (sport)","Распредвал (sport)","Прямоток (sport)","Турбокомпрессор (sport)",
    "Нагнетатель (sport)","Сцепление (sport)","КПП (sport)","Дифференциал (sport)",
    "Подвеска (sport)","Тормоза (sport)",
    "Коленвал (sport+)","Распредвал (sport+)","Прямоток (sport+)","Турбокомпрессор (sport+)",
    "Нагнетатель (sport+)","Сцепление (sport+)","КПП (sport+)","Дифференциал (sport+)",
    "Подвеска (sport+)","Тормоза (sport+)",
    "Чип-тюнинг (STAGE 1)","Чип-тюнинг (STAGE 2)","Чип-тюнинг (STAGE 3)",
    "Кусок чертежа","Чертеж Гучи","Чертеж Луи Витон","Чертеж Шанель","Чертеж Найк",
    "Чертеж Адидас","Чертеж Суприм","Чертеж одежды","Чертеж музыкальных инструментов",
    "Чертеж дисков","Чертеж шлемов","Чертеж причесок","Чертеж Барбер","Чертеж сумок бизнесмена",
    "Чертеж винилов","Чертеж бамперов","Чертеж спойлеров","Чертеж крыльев ангела",
    "Чертеж предметов майнинга","Чертеж масок","Чертеж досок для серфинга","Чертеж костяных маски",
    "Чертеж нашивок","Чертеж головных уборов","Чертеж шарфов","Чертеж предметов для участка",
    "Чертеж новогодних предметов","Чертеж капотов","Чертеж предметов теплицы","DeLorean DMC-12",
    "Компенсатор (Deagle)","Цевьё (Deagle)","Приклад (Deagle)",
    "Компенсатор (M4)","Цевьё (M4)","Приклад (M4)",
    "Компенсатор (AK-47)","Цевьё (AK-47)","Приклад (AK-47)",
    "Компенсатор (Country Rifle)","Цевьё (Country Rifle)","Приклад (Country Rifle)",
    "Компенсатор (MP5)","Цевьё (MP5)","Приклад (MP5)",
    "Компенсатор (Shotgun)","Цевьё (Shotgun)","Приклад (Shotgun)",
    "Компенсатор (Uzi)","Цевьё (Uzi)","Приклад (Uzi)",
    "Компенсатор (Sniper Rifle)","Цевьё (Sniper Rifle)","Приклад (Sniper Rifle)",
    "Крылья ангелов (зеленые)","Крылья ангелов (голубые)","Крылья ангелов (синие)",
    "Крылья ангелов (фиолетовые)","Крылья ангелов (черные)","Крылья ангелов (белые)",
    "Крылья ангелов (красные)","Крылья ангелов (желтые)",
    "Фотоаппарат","Канистра на бедро",
    "Диски-1","Диски-2","Диски-3","Диски-4","Диски-5","Диски-6","Диски-7",
    "Диски-8","Диски-9","Диски-10","Диски-11","Диски-12","Диски-13","Диски-14",
    "Диски-15","Диски-16","Диски-17",
}

local KLAD_COORDS = {
    {662.2833, -1023.2820, 37.9996},{617.2049, -985.9263, 35.6239},{698.3946, -894.2959, 34.8125},
    {719.1682, -1022.2174, 34.0112},{620.9334, -996.3545, 35.6767},{620.0105, -948.0887, 37.9534},
    {688.7455, -958.7740, 37.0255},{643.5681, -1010.2860, 41.7452},{702.9244, -1001.5508, 34.6395},
    {608.7305, -974.9351, 35.2351},{625.9965, -963.7627, 39.7405},{616.1764, -961.2691, 35.1559},
    {656.3830, -1039.9372, 35.7439},{651.8837, -968.6265, 38.4829},{653.1677, -991.3493, 35.2977},
    {665.8975, -893.0772, 34.5556},{693.3423, -976.0838, 38.1525},{661.7413, -925.1516, 34.6257},
    {694.6822, -932.6195, 37.3607},{648.7445, -1028.0118, 35.6966},{682.3065, -926.2387, 34.5024},
    {642.3909, -972.2863, 35.3888},{648.6083, -907.0199, 34.2342},{674.6378, -969.0570, 34.5337},
    {658.3722, -951.9749, 34.8932},{669.2776, -908.8499, 33.9101},{671.6741, -1015.8754, 38.3806},
    {628.7800, -1027.5563, 35.7806},{637.7869, -1015.8815, 42.8698},{617.6980, -971.1764, 35.3707},
    {700.3185, -926.9878, 37.6190},{679.8557, -888.7298, 35.3595},{686.5773, -912.1717, 41.2689},
    {641.3538, -935.3186, 37.8394},{643.1062, -1017.1610, 42.7381},{607.8727, -954.3286, 34.7982},
    {658.4100, -898.0656, 34.0783},{698.3103, -1001.2537, 37.0766},{640.4938, -943.7207, 40.9358},
    {695.3915, -989.0150, 34.3297},{646.4165, -933.7815, 34.9597},{650.6213, -963.9051, 38.3955},
    {659.9974, -959.5834, 38.5785},{700.6653, -936.2243, 34.4023},{623.2397, -979.9030, 35.5708},
    {697.0354, -979.6433, 37.4981},{638.2488, -915.5055, 35.1630},{636.2996, -938.8073, 37.7765},
    {668.7281, -959.1689, 34.7220},{700.4897, -994.5342, 37.3749},{628.9905, -1010.8421, 35.6533},
    {683.9072, -915.6095, 41.3761},{679.2723, -1010.1912, 34.6406},{686.6422, -973.9338, 34.5565},
    {637.1811, -953.8310, 35.2607},{665.7637, -984.4908, 34.6692},{671.3028, -983.3789, 34.8453},
    {709.9200, -930.9788, 34.4838},{614.1329, -955.1283, 38.1603},{624.4068, -971.4665, 39.2804},
    {679.4451, -978.4008, 34.5868},{697.5875, -995.2892, 37.2878},{659.8938, -966.7417, 37.4829},
    {702.7980, -955.5957, 34.6397},{703.6506, -999.4403, 40.0914},{677.9513, -936.6154, 34.6475},
    {696.6897, -909.2708, 34.6130},{623.2301, -940.9538, 34.1976},{669.4428, -901.8733, 34.3521},
    {647.2107, -982.0861, 35.3437},{716.0654, -1026.8245, 34.3699},{678.8733, -1017.6286, 34.7991},
    {669.1935, -1006.6626, 34.9192},{646.2660, -966.2932, 38.5806},{679.9181, -953.4051, 36.9010},
    {685.7229, -961.5743, 37.0862},{623.5552, -934.1241, 34.2989},{672.7010, -1033.9490, 35.5408},
    {655.1928, -1016.0168, 35.3833},{682.1204, -1037.2251, 35.3530},{630.4920, -1021.5254, 35.7704},
    {643.8636, -921.1787, 35.0627},{601.1092, -945.5415, 34.7408},{685.5076, -984.7718, 34.6466},
    {668.1647, -998.3349, 34.8401},{626.7167, -953.3335, 35.1491},{701.3402, -983.5728, 37.7893},
    {670.6518, -962.6350, 34.6623},{692.8704, -889.9748, 34.8165},{698.3519, -916.1419, 34.5654},
    {696.7782, -970.8947, 34.4192},{654.5455, -930.3702, 34.8802},{659.4080, -973.3150, 38.4667},
    {658.6523, -1004.2227, 35.1457},{683.6567, -997.0003, 34.5860},{714.7801, -1000.7869, 33.7639},
    {693.3295, -976.0893, 38.1537},{637.2757, -928.1133, 34.8969},{631.1375, -921.2405, 35.1648},
    {666.4355, -970.8406, 38.3848},{693.7900, -961.7611, 34.4977},{630.4187, -979.2467, 38.8315},
    {598.8584, -953.3455, 34.5176},{687.2002, -931.8423, 34.6137},{632.6988, -985.7730, 38.9623},
    {657.1914, -1033.3564, 35.7389},{602.6422, -966.3785, 34.7868},{654.1944, -912.2311, 34.1946},
    {672.5309, -931.6529, 34.6263},{638.6028, -1010.1963, 42.0769},{692.9817, -940.0695, 34.6670},
    {645.6962, -959.8268, 35.2728},{684.7202, -955.7024, 36.8590},{657.8409, -979.6901, 34.7047},
    {677.4548, -997.4909, 34.6726},{630.4714, -995.8715, 35.5583},{641.9217, -1034.8780, 35.7680},
    {632.8868, -943.5758, 34.3710},{643.5708, -1005.6211, 42.1176},{691.4265, -1012.4284, 34.3382},
    {669.2825, -1027.4372, 38.8055},{673.5989, -1032.8113, 35.4968},{653.1856, -942.6812, 34.7759},
    {621.9834, -1015.7807, 35.6754},
}

local showMainUI   = { v = false }
local activeTab    = 1
local selectedDate = nil

local logFile    = CFG_DIR .. '/klad_log.json'
local filterFile = CFG_DIR .. '/Klad_filter.json'

local allDates   = {}
local dateStats  = {}
local itemFilter = {}

local fontInitialized    = false
local mountainMenuActive = false
local isKladChest        = false
local currentChestItems  = {}
local autoSelectEnabled  = { v = true }

local searchBuf = imgui.new.char[256]()

local settingsFile  = CFG_DIR .. '/klad_settings.json'
local accent        = { 0.58, 0.25, 0.95 }
local hsvState      = { h = 0.75, s = 0.74, v = 0.95 }
local cfg = {
    alpha      = 0.97,
    startDelay = 400,
    pickDelay  = 150,
    chatNotify = true,
    anim       = true,
    glow       = true,
    uiScale    = 1.0,
}
local tabAt = 0
local settingsDirty = false
local histPage, detailPage, rewardPage = 1, 1, 1
local detailItems   = {}
local confirmClear, confirmClearAt = false, 0
local totalChestsAll, totalItemsAll = 0, 0
local sessionChests, sessionItems   = 0, 0
local lastChestItems = {}
local chestSeenAt, lastItemAt, lastSaveAt = -100, 0, -100
local F = {}

local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end

local function hsv2rgb(h, s, v)
    local i = math.floor(h * 6); local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v else return v, p, q end
end

local function rgb2hsv(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d, h = mx - mn, 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end

local function setAccentRGB(r, g, b)
    accent[1], accent[2], accent[3] = r, g, b
    hsvState.h, hsvState.s, hsvState.v = rgb2hsv(r, g, b)
end

local function setAccentHSV()
    accent[1], accent[2], accent[3] = hsv2rgb(hsvState.h, hsvState.s, hsvState.v)
end

local PRESETS = {
    { "Фиолетовый", .58, .25, .95 },
    { "Синий",      .20, .45, .95 },
    { "Голубой",    .10, .72, .90 },
    { "Зелёный",    .18, .78, .40 },
    { "Золотой",    .95, .72, .15 },
    { "Оранжевый",  .98, .50, .15 },
    { "Красный",    .95, .25, .32 },
    { "Розовый",    .95, .30, .70 },
}

local function saveSettings()
    local f = io.open(settingsFile, 'w+')
    if f then
        f:write(json.encode({
            accent = { accent[1], accent[2], accent[3] },
            alpha = cfg.alpha, startDelay = cfg.startDelay, pickDelay = cfg.pickDelay,
            chatNotify = cfg.chatNotify, anim = cfg.anim, glow = cfg.glow,
            auto = autoSelectEnabled.v, tab = activeTab,
            uiScale = cfg.uiScale,
        }, { indent = true }))
        f:close()
    end
end

local function loadSettings()
    local f = io.open(settingsFile, 'r')
    if not f then return end
    local c = f:read('*a'); f:close()
    local ok, d = pcall(json.decode, c)
    if not ok or type(d) ~= 'table' then return end
    if type(d.accent) == 'table' and tonumber(d.accent[1]) and tonumber(d.accent[2]) and tonumber(d.accent[3]) then
        setAccentRGB(clamp01(d.accent[1]), clamp01(d.accent[2]), clamp01(d.accent[3]))
    end
    if tonumber(d.alpha) then cfg.alpha = math.min(1, math.max(0.6, d.alpha)) end
    if tonumber(d.startDelay) then cfg.startDelay = math.min(2000, math.max(100, d.startDelay)) end
    if tonumber(d.pickDelay) then cfg.pickDelay = math.min(1000, math.max(50, d.pickDelay)) end
    if type(d.chatNotify) == 'boolean' then cfg.chatNotify = d.chatNotify end
    if type(d.anim) == 'boolean' then cfg.anim = d.anim end
    if type(d.glow) == 'boolean' then cfg.glow = d.glow end
    if type(d.auto) == 'boolean' then autoSelectEnabled.v = d.auto end
    if tonumber(d.uiScale) then cfg.uiScale = math.min(1.6, math.max(0.5, d.uiScale)) end
    if tonumber(d.tab) and d.tab >= 1 and d.tab <= 5 then activeTab = math.floor(d.tab) end
end

local glassAlpha    = 0.88
local animationTime = 0.0
local pulseEffect   = 0.0
local shimmerEffect = 0.0

local kladPointsActive  = false

local kladPickups   = {}
local kladDone      = {}
local kladDoneCount = 0

local function clearMarks()
    for _, id in pairs(kladPickups) do pcall(removePickup, id) end
    kladPickups = {}
end

local function resetCollected()
    kladDone, kladDoneCount = {}, 0
end

local function playerPos()
    local ok, x, y, z = pcall(getCharCoordinates, PLAYER_PED)
    if ok and x then return x, y, z end
end

local lastCollectCheck = 0
local function checkCollectedPickups()
    if not kladPointsActive then return end
    if os.clock() - lastCollectCheck < 0.1 then return end
    lastCollectCheck = os.clock()
    local px, py, pz = playerPos()
    if not px then return end
    for i, c in ipairs(KLAD_COORDS) do
        if not kladDone[i] then
            local taken = false
            local h = kladPickups[i]
            if h then
                local ok, res = pcall(hasPickupBeenCollected, h)
                if ok and res then taken = true end
            end
            if not taken then
                local dx, dy, dz = c[1] - px, c[2] - py, c[3] - pz
                if dx * dx + dy * dy < 1.6 * 1.6 and math.abs(dz) < 3.5 then taken = true end
            end
            if taken then
                kladDone[i] = true
                kladDoneCount = kladDoneCount + 1
                if h then pcall(removePickup, h); kladPickups[i] = nil end
            end
        end
    end
end

local function spawnKladPickups(silent)
    clearMarks()
    local cnt = 0
    for i, c in ipairs(KLAD_COORDS) do
        if not kladDone[i] then
            local ok, r1, r2 = pcall(createPickup, 19198, 22, c[1], c[2], c[3])
            local handle = ok and ((type(r2) == 'number' and r2) or (type(r1) == 'number' and r1)) or nil
            if handle then kladPickups[i] = handle end
            cnt = cnt + 1
        end
    end
    kladPointsActive = true
    if not silent then
        chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Метки созданы! {c0c0c0}(" .. cnt .. " шт.)", -1)
    end
end

local function removeKladPickups()
    clearMarks()
    kladPointsActive = false
    chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Все метки убраны!", -1)
end

local function loadFilter()
    local f = io.open(filterFile, 'r')
    if f then
        local content = f:read('*a'); f:close()
        return json.decode(content) or {}
    end
    return {}
end

local function saveFilter()
    local f = io.open(filterFile, 'w+')
    if f then
        f:write(json.encode(itemFilter, { indent = true })); f:close()
    end
end

local function initFilter()
    local saved = loadFilter()
    for _, name in ipairs(ITEMS_LIST) do
        if saved[name] ~= nil then
            itemFilter[name] = saved[name]
        else
            itemFilter[name] = true
        end
    end
    saveFilter()
end

local FONT_REG  = { '/system/fonts/Roboto-Regular.ttf', '/system/fonts/RobotoStatic-Regular.ttf',
                    '/system/fonts/NotoSans-Regular.ttf', '/system/fonts/DroidSans.ttf' }
local FONT_BOLD = { '/system/fonts/Roboto-Bold.ttf', '/system/fonts/RobotoStatic-Bold.ttf',
                    '/system/fonts/NotoSans-Bold.ttf', '/system/fonts/DroidSans-Bold.ttf' }

local function firstExisting(list)
    for _, p in ipairs(list) do if doesFileExist(p) then return p end end
end

local function initFont()
    if fontInitialized then return true end
    local ok = pcall(function()
        local fonts = imgui.GetIO().Fonts
        local bundled = getWorkingDirectory() .. '/lib/mimgui/trebucbd.ttf'
        local reg  = firstExisting(FONT_REG)  or (doesFileExist(bundled) and bundled or nil)
        local bold = firstExisting(FONT_BOLD) or reg
        local function add(path, size)
            if not path then return nil end
            local okf, f = pcall(function()
                return fonts:AddFontFromFileTTF(path, size, nil, fonts:GetGlyphRangesCyrillic())
            end)
            if okf and f ~= nil then return f end
            okf, f = pcall(function() return fonts:AddFontFromFileTTF(path, size) end)
            if okf and f ~= nil then return f end
            return nil
        end

        F.reg = { add(reg, 16.0),  16.0 }
        F.s   = { add(reg, 14.0),  14.0 }
        F.b   = { add(bold, 17.0), 17.0 }
        F.h   = { add(bold, 24.0), 24.0 }
        F.xl  = { add(bold, 34.0), 34.0 }
    end)
    fontInitialized = ok
    return ok
end

local function applyTheme()
    local ok, style = pcall(imgui.GetStyle)
    if not ok or not style then return end
    local function setS(k, v) pcall(function() style[k] = v end) end
    local function setV(k, x, y) pcall(function() style[k] = imgui.ImVec2(x, y) end) end
    setS('WindowRounding', 18.0); setS('ChildRounding', 14.0)
    setS('FrameRounding', 12.0);  setS('PopupRounding', 16.0)
    setS('ScrollbarRounding', 10.0); setS('GrabRounding', 8.0); setS('TabRounding', 12.0)
    setV('WindowPadding', 18, 18); setV('FramePadding', 12, 8)
    setV('ItemSpacing', 14, 10);   setV('ItemInnerSpacing', 8, 6)
    setS('ScrollbarSize', 14.0); setS('GrabMinSize', 12.0)
    setS('WindowBorderSize', 0); setS('ChildBorderSize', 0)
    setS('PopupBorderSize', 0);  setS('FrameBorderSize', 0); setS('TabBorderSize', 0)
    local r, g, b = accent[1], accent[2], accent[3]
    local function K(k, a) return imgui.ImVec4(clamp01(r*k + .008), clamp01(g*k + .008), clamp01(b*k + .014), a) end
    local okc, c = pcall(function() return style.Colors end)
    if not okc or not c then return end
    local function setC(name, v) pcall(function() c[imgui.Col[name]] = v end) end
    setC('WindowBg', K(.10, cfg.alpha)); setC('ChildBg', K(.14, .7)); setC('PopupBg', K(.12, .96))
    setC('Border', imgui.ImVec4(0,0,0,0)); setC('BorderShadow', imgui.ImVec4(0,0,0,0))
    setC('Text', imgui.ImVec4(0.96,0.95,1.0, 1.0)); setC('TextDisabled', imgui.ImVec4(0.5,0.45,0.6, 0.75))
    setC('TextSelectedBg', K(.6, .4))
    setC('TitleBg', K(.2, .88)); setC('TitleBgActive', K(.35, .92)); setC('TitleBgCollapsed', K(.15, .75))
    setC('Button', K(.34, .70)); setC('ButtonHovered', K(.50, .82)); setC('ButtonActive', K(.70, .90))
    setC('FrameBg', K(.20, .70)); setC('FrameBgHovered', K(.30, .80)); setC('FrameBgActive', K(.40, .90))
    setC('ScrollbarBg', K(.05, .25)); setC('ScrollbarGrab', K(.50, .65))
    setC('ScrollbarGrabHovered', K(.70, .82)); setC('ScrollbarGrabActive', K(.90, .92))
    setC('CheckMark', K(1.3, 1.0)); setC('SliderGrab', K(.90, .85)); setC('SliderGrabActive', K(1.2, 1.0))
    setC('Tab', K(.20, .55)); setC('TabHovered', K(.55, .82)); setC('TabActive', K(.45, .92))
    setC('TabUnfocused', K(.12, .45)); setC('TabUnfocusedActive', K(.30, .65))
    setC('Header', K(.40, .55)); setC('HeaderHovered', K(.60, .75)); setC('HeaderActive', K(.80, .85))
    setC('Separator', K(.60, .45)); setC('SeparatorHovered', K(.85, .72)); setC('SeparatorActive', K(1.1, .88))
    setC('ResizeGrip', K(.40, .25)); setC('ResizeGripHovered', K(.60, .55)); setC('ResizeGripActive', K(.85, .75))
end

imgui.OnInitialize(function()
    if not initFont() then
        chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Ошибка загрузки шрифта")
    end
    pcall(applyTheme)
end)

local CEF_ID, SUB_VIEW_IN, SUB_SEND, SUB_VIEW_OUT, SUB_TEXT = 220, 62, 63, 66, 84
local TEXT_BIT_OFS  = 73
local MIN_TEXT_SIZE = 60
local mountainView  = 0x65
local lastViewOpen  = { id = nil, t = -100 }

local dbgOn = false
local function dbg(m)
    if dbgOn then chat("{FF0000}| {c0c0c0}[dbg] {FFFFFF}" .. tostring(m)) end
end

local sendWarned = false
local function sendSelect(id)
    dbg("send select id=" .. tostring(id) .. " view=" .. tostring(mountainView))
    local s = tostring(id)
    local ok, err = pcall(function()
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, CEF_ID)
        raknetBitStreamWriteInt8(bs, SUB_SEND)
        raknetBitStreamWriteInt8(bs, mountainView)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteInt32(bs, 1)
        raknetBitStreamWriteInt16(bs, #s)
        raknetBitStreamWriteString(bs, s)
        raknetSendBitStream(bs)
        raknetDeleteBitStream(bs)
    end)
    if not ok and not sendWarned then
        sendWarned = true
        chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Не удалось отправить пакет: {c0c0c0}" .. tostring(err))
    end
end

local pendingVehicles = nil
local function startAutoSelectFiltered(vehicles)
    if not autoSelectEnabled.v then dbg("autoselect OFF in settings"); return end
    if not isKladChest then dbg("not klad chest"); return end
    pendingVehicles = vehicles
end

local function processAutoSelect()
    if not pendingVehicles then return end
    local list = pendingVehicles
    pendingVehicles = nil
    dbg("autoselect start, items=" .. #list)
    wait(cfg.startDelay)
    for _, v in ipairs(list) do
        local name = norm(v.title or "")
        if itemFilter[name] ~= false then
            sendSelect(v.id)
            wait(cfg.pickDelay)
        end
    end
end

local function loadLog()
    local f = io.open(logFile, 'r')
    if f then
        local c = f:read('*a'); f:close()
        return json.decode(c) or {}
    end
    return {}
end

local function saveChest(items, fromTimer)
    if #items == 0 then return end

    local merge = fromTimer and (os.clock() - lastSaveAt) < 6
    lastSaveAt = os.clock()
    if not merge then
        sessionChests = sessionChests + 1
        lastChestItems = {}
    end
    for _, item in ipairs(items) do
        sessionItems = sessionItems + item.count
        table.insert(lastChestItems, { name = item.name, count = item.count })
    end
    local data = loadLog()
    local date = os.date('%d.%m.%Y')
    if not data[date] then data[date] = { chests_opened = 0, items = {} } end
    if not merge then data[date].chests_opened = data[date].chests_opened + 1 end
    for _, item in ipairs(items) do
        local found = false
        for _, ex in ipairs(data[date].items) do
            if ex.name == item.name then
                ex.count = ex.count + item.count; found = true; break
            end
        end
        if not found then
            table.insert(data[date].items, { name = item.name, count = item.count })
        end
    end
    local f = io.open(logFile, 'w+')
    if f then f:write(json.encode(data, { indent = true })); f:close() end
    if cfg.chatNotify then chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Сохранен клад #{c0c0c0}" .. data[date].chests_opened, -1) end
end

local function prepareDates()
    local data = loadLog()
    allDates = {}; dateStats = {}
    totalChestsAll, totalItemsAll = 0, 0
    for date, dayData in pairs(data) do
        table.insert(allDates, date)
        local total = 0
        for _, it in ipairs(dayData.items) do total = total + it.count end
        totalChestsAll = totalChestsAll + (dayData.chests_opened or 0)
        totalItemsAll  = totalItemsAll + total
        dateStats[date] = {
            chests     = dayData.chests_opened,
            totalItems = total,
            items      = dayData.items
        }
    end
    table.sort(allDates, function(a, b)
        local da,ma,ya = a:match("(%d+)%.(%d+)%.(%d+)")
        local db,mb,yb = b:match("(%d+)%.(%d+)%.(%d+)")
        return os.time{day=da,month=ma,year=ya} > os.time{day=db,month=mb,year=yb}
    end)
end

local function bsReset(bs)
    if raknetBitStreamResetReadPointer then pcall(raknetBitStreamResetReadPointer, bs)
    elseif raknetBitStreamSetReadOffset then pcall(raknetBitStreamSetReadOffset, bs, 0) end
end

local function bsBytes(bs)
    local ok, s = pcall(function()
        local ptr = raknetBitStreamGetDataPtr(bs)
        local n   = raknetBitStreamGetNumberOfBytesUsed(bs)
        if not ptr or not n or n <= 0 then return nil end
        return ffi.string(ffi.cast('const char*', ffi.cast('uintptr_t', ptr)), n)
    end)
    return ok and s or nil
end

local function readHead(bs)
    local raw = bsBytes(bs)
    if raw and #raw >= 2 then
        return raw:byte(1), raw:byte(2), raw:byte(3), raw:byte(4), #raw
    end
    local ok, a, b, c, d, n = pcall(function()
        local n = raknetBitStreamGetNumberOfBytesUsed(bs)
        bsReset(bs)
        local function r() return (raknetBitStreamReadInt8(bs) or 0) % 256 end
        local a, b = r(), r()
        local c = n >= 3 and r() or nil
        local d = n >= 4 and r() or nil
        return a, b, c, d, n
    end)
    bsReset(bs)
    if ok then return a, b, c, d, n end
end

local OFS_TRY = { TEXT_BIT_OFS, 72, 74, 80, 88, 64, 56 }
local function decodeText(bs, nbytes)
    local maxn = math.min(32768, math.max(1024, nbytes * 8))
    for _, ofs in ipairs(OFS_TRY) do
        local ok, str = pcall(function()
            bsReset(bs)
            raknetBitStreamIgnoreBits(bs, ofs)
            return raknetBitStreamDecodeString(bs, maxn)
        end)
        if ok and type(str) == 'string' and str ~= '' and (str:find('[', 1, true) or str:find('{', 1, true)) then
            bsReset(bs)
            return str, ofs
        end
        if not ok then dbg("decode error @" .. ofs .. ": " .. tostring(str)) end
    end
    bsReset(bs)
end

local KNOWN_ITEMS = {}
for _, name in ipairs(ITEMS_LIST) do KNOWN_ITEMS[name] = true end

local function openMountain()
    mountainMenuActive = true
    chestSeenAt        = os.clock()
    if os.clock() - lastItemAt > 3 then currentChestItems = {} end
end

local function closeMountain()
    if mountainMenuActive and #currentChestItems > 0 then
        saveChest(currentChestItems)
        currentChestItems = {}
    end
    mountainMenuActive = false
    isKladChest        = false
end

local function onViewState(view, flag)
    if not view then return end
    dbg(string.format("view 0x%02X flag 0x%02X (klad view 0x%02X)", view, flag or 0, mountainView))
    if (flag or 0) >= 128 then
        lastViewOpen.id, lastViewOpen.t = view, os.clock()
        if view == mountainView then openMountain() end
    elseif view == mountainView then
        closeMountain()
    end
end

local function parseVehicles(str)
    local arr = str:match("%b[]")
    if not arr then return nil end
    local ok, d = pcall(json.decode, arr)
    if not ok or type(d) ~= 'table' then return nil end
    if type(d[1]) == 'table' and type(d[1][1]) == 'table' then d = d[1] end
    if type(d[1]) ~= 'table' or d[1].id == nil or type(d[1].title) ~= 'string' then return nil end
    return d
end

local function onCefText(str)
    str = norm(str)
    dbg("text: " .. str:sub(1, 90):gsub("%s+", " "))
    if str:find("из клада", 1, true) then
        isKladChest = true
        chestSeenAt = os.clock()
        return
    end
    local list = parseVehicles(str)
    if not list then return end
    if not mountainMenuActive and lastViewOpen.id and os.clock() - lastViewOpen.t < 0.5 then
        mountainView = lastViewOpen.id
    end
    openMountain()
    dbg("list items: " .. #list)
    local known = 0
    for _, v in ipairs(list) do
        if KNOWN_ITEMS[norm(v.title)] then known = known + 1 end
    end
    isKladChest = known >= math.ceil(#list * 0.6)
    dbg("known " .. known .. "/" .. #list .. " klad=" .. tostring(isKladChest) .. " auto=" .. tostring(autoSelectEnabled.v))
    if isKladChest then startAutoSelectFiltered(list) end
end

local function onSendPacketKlad(id, bs)
    if id ~= CEF_ID then return end
    local pid, sub, a, b = readHead(bs)
    if sub == SUB_VIEW_OUT then onViewState(a, b) end
    bsReset(bs)
end

local function onReceivePacketKlad(id, bs)
    if id ~= CEF_ID then return end
    local pid, sub, a, b, n = readHead(bs)
    if sub == SUB_VIEW_IN then
        onViewState(a, b)
    elseif sub == SUB_TEXT and n and n >= MIN_TEXT_SIZE then
        local near = mountainMenuActive or os.clock() - chestSeenAt < 12 or os.clock() - lastViewOpen.t < 1
        if near then
            local str, ofs = decodeText(bs, n)
            dbg("84 n=" .. n .. " decoded=" .. tostring(str ~= nil) .. " ofs=" .. tostring(ofs))
            if str then onCefText(str) end
        end
    end
    bsReset(bs)
end

addEventHandler('onSendPacket', onSendPacketKlad)
addEventHandler('onReceivePacket', onReceivePacketKlad)

local DL, OX, OY, DT = nil, 0, 0, 0.016
local SC = 1.0
local function updateScale(w, h, fh, fw)
    local sw, sh = getScreenResolution()
    local auto = math.min(sh * (fh or 0.94) / h, sw * (fw or 0.97) / w)
    SC = math.max(0.6, math.min(2.6, auto * cfg.uiScale))
end
local P = { ar = .58, ag = .25, ab = .95, pulse = 1 }
local WW, WH = 1000, 580

local function c4(r, g, b, a) return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a)) end
local function A(k, a) return c4(clamp01(P.ar*k + .008), clamp01(P.ag*k + .008), clamp01(P.ab*k + .014), a or 1) end
local function L(k, a) return c4(P.ar + (1-P.ar)*k, P.ag + (1-P.ag)*k, P.ab + (1-P.ab)*k, a or 1) end
local function W(a) return c4(1, 1, 1, a or 1) end
local GREEN, RED = {.25,.85,.45}, {.95,.32,.38}
local function GC(a) return c4(GREEN[1], GREEN[2], GREEN[3], a or 1) end
local function RC(a) return c4(RED[1], RED[2], RED[3], a or 1) end
local function V(x, y) return imgui.ImVec2(OX + x * SC, OY + y * SC) end

local function rectF(x1, y1, x2, y2, col, r) DL:AddRectFilled(V(x1, y1), V(x2, y2), col, (r or 0) * SC, 0) end
local function rectS(x1, y1, x2, y2, col, r, th) DL:AddRect(V(x1, y1), V(x2, y2), col, (r or 0) * SC, 0, (th or 1) * SC) end
local function line(x1, y1, x2, y2, col, th) DL:AddLine(V(x1, y1), V(x2, y2), col, (th or 1) * SC) end
local function circF(x, y, r, col, seg) DL:AddCircleFilled(V(x, y), r * SC, col, seg or 24) end
local function circS(x, y, r, col, th, seg) DL:AddCircle(V(x, y), r * SC, col, seg or 24, (th or 1) * SC) end
local function tri(x1, y1, x2, y2, x3, y3, col) DL:AddTriangleFilled(V(x1, y1), V(x2, y2), V(x3, y3), col) end
local function quad(x1, y1, x2, y2, x3, y3, x4, y4, col) tri(x1, y1, x2, y2, x3, y3, col); tri(x1, y1, x3, y3, x4, y4, col) end

local U8C, U8N = {}, 0
local function U(s)
    local v = U8C[s]
    if not v then
        v = u8(s)
        if U8N > 1500 then U8C = {}; U8N = 0 end
        U8C[s] = v; U8N = U8N + 1
    end
    return v
end
local function pushF(f) if f and f[1] then imgui.PushFont(f[1], f[2] * SC); return true end return false end
local function TS(s, f)
    local p = pushF(f); local sz = imgui.CalcTextSize(U(s)); if p then imgui.PopFont() end
    return sz.x / SC, sz.y / SC
end
local function TX(x, y, s, col, f)
    local p = pushF(f); DL:AddText(V(x, y), col, U(s)); if p then imgui.PopFont() end
end
local function TXC(cx, y, s, col, f) local w = TS(s, f); TX(cx - w/2, y, s, col, f) end
local function TXR(xr, y, s, col, f) local w = TS(s, f); TX(xr - w, y, s, col, f) end
local function TXM(x, cy, s, col, f) local _, h = TS(s, f); TX(x, cy - h/2, s, col, f) end

local function fit(s, maxw, f)
    if TS(s, f) <= maxw then return s end
    while #s > 1 and TS(s .. "..", f) > maxw do s = s:sub(1, #s - 1) end
    return s .. ".."
end

local function strLower(s)
    local r = {}
    for i = 1, #s do
        local b = s:byte(i)
        if (b >= 65 and b <= 90) or (b >= 192 and b <= 223) then b = b + 32
        elseif b == 168 then b = 184 end
        r[i] = string.char(b)
    end
    return table.concat(r)
end
local function matchItem(name, needle)
    if needle == "" then return true end
    return strLower(name):find(strLower(needle), 1, true) ~= nil
end

local EA = {}
local function ease(id, target, speed)
    local v = EA[id]; if v == nil then v = target end
    if not cfg.anim then EA[id] = target; return target end
    v = v + (target - v) * math.min(1, DT * (speed or 14))
    EA[id] = v
    return v
end

local function hit(id, x, y, w, h)
    imgui.SetCursorScreenPos(V(x, y))
    local clicked = imgui.InvisibleButton(id, imgui.ImVec2(w * SC, h * SC))
    return clicked, imgui.IsItemHovered(), imgui.IsItemActive()
end

local Ic = {}
local function th(s, k) return math.max(1.5, s * k) end
function Ic.clock(cx, cy, s, c)
    circS(cx, cy, s*.42, c, th(s, .1), 28)
    line(cx, cy, cx, cy - s*.24, c, th(s, .09)); line(cx, cy, cx + s*.17, cy + s*.09, c, th(s, .09))
end
function Ic.gear(cx, cy, s, c, c2)
    for i = 0, 7 do
        local a = i * math.pi / 4
        local ca, sa = math.cos(a), math.sin(a)
        line(cx + ca*s*.30, cy + sa*s*.30, cx + ca*s*.47, cy + sa*s*.47, c, s*.17)
    end
    circF(cx, cy, s*.35, c, 24); circF(cx, cy, s*.15, c2, 16)
end
function Ic.bolt(cx, cy, s, c)
    tri(cx + s*.12, cy - s*.46, cx - s*.28, cy + s*.06, cx + s*.04, cy + s*.06, c)
    tri(cx - s*.12, cy + s*.46, cx + s*.28, cy - s*.06, cx - s*.04, cy - s*.06, c)
end
function Ic.gift(cx, cy, s, c, c2)
    rectF(cx - s*.40, cy - s*.12, cx + s*.40, cy + s*.44, c, s*.06)
    rectF(cx - s*.46, cy - s*.30, cx + s*.46, cy - s*.06, c, s*.06)
    rectF(cx - s*.06, cy - s*.30, cx + s*.06, cy + s*.44, c2, 0)
    circS(cx - s*.14, cy - s*.40, s*.12, c, th(s, .08), 12)
    circS(cx + s*.14, cy - s*.40, s*.12, c, th(s, .08), 12)
end
function Ic.pin(cx, cy, s, c, c2)
    circF(cx, cy - s*.12, s*.30, c, 24)
    tri(cx - s*.26, cy - s*.02, cx + s*.26, cy - s*.02, cx, cy + s*.46, c)
    circF(cx, cy - s*.12, s*.11, c2, 14)
end
function Ic.close(cx, cy, s, c)
    line(cx - s*.3, cy - s*.3, cx + s*.3, cy + s*.3, c, th(s, .13))
    line(cx + s*.3, cy - s*.3, cx - s*.3, cy + s*.3, c, th(s, .13))
end
function Ic.chevL(cx, cy, s, c)
    line(cx + s*.14, cy - s*.3, cx - s*.14, cy, c, th(s, .12)); line(cx - s*.14, cy, cx + s*.14, cy + s*.3, c, th(s, .12))
end
function Ic.chevR(cx, cy, s, c)
    line(cx - s*.14, cy - s*.3, cx + s*.14, cy, c, th(s, .12)); line(cx + s*.14, cy, cx - s*.14, cy + s*.3, c, th(s, .12))
end
function Ic.back(cx, cy, s, c)
    local t = th(s, .12)
    line(cx + s*.32, cy, cx - s*.3, cy, c, t)
    line(cx - s*.3, cy, cx - s*.04, cy - s*.27, c, t); line(cx - s*.3, cy, cx - s*.04, cy + s*.27, c, t)
end
function Ic.trash(cx, cy, s, c)
    local t = th(s, .09)
    line(cx - s*.4, cy - s*.28, cx + s*.4, cy - s*.28, c, t * 1.2)
    line(cx - s*.14, cy - s*.28, cx - s*.14, cy - s*.40, c, t); line(cx + s*.14, cy - s*.28, cx + s*.14, cy - s*.40, c, t)
    line(cx - s*.14, cy - s*.40, cx + s*.14, cy - s*.40, c, t)
    line(cx - s*.3, cy - s*.16, cx - s*.24, cy + s*.42, c, t); line(cx + s*.3, cy - s*.16, cx + s*.24, cy + s*.42, c, t)
    line(cx - s*.24, cy + s*.42, cx + s*.24, cy + s*.42, c, t)
    line(cx, cy - s*.08, cx, cy + s*.30, c, t); line(cx - s*.11, cy - s*.08, cx - s*.09, cy + s*.30, c, t); line(cx + s*.11, cy - s*.08, cx + s*.09, cy + s*.30, c, t)
end
function Ic.cube(cx, cy, s, c, c2, c3)
    quad(cx, cy - s*.46, cx + s*.40, cy - s*.23, cx, cy, cx - s*.40, cy - s*.23, c)
    quad(cx - s*.40, cy - s*.23, cx, cy, cx, cy + s*.46, cx - s*.40, cy + s*.23, c2)
    quad(cx + s*.40, cy - s*.23, cx, cy, cx, cy + s*.46, cx + s*.40, cy + s*.23, c3 or c2)
end
function Ic.star(cx, cy, s, c)
    local R, r, px, py = s*.48, s*.2, {}, {}
    for k = 0, 9 do
        local a = -math.pi/2 + k * math.pi/5
        local rad = (k % 2 == 0) and R or r
        px[k] = cx + math.cos(a)*rad; py[k] = cy + math.sin(a)*rad
    end
    for k = 0, 9 do local k2 = (k + 1) % 10; tri(cx, cy, px[k], py[k], px[k2], py[k2], c) end
end
function Ic.diamond(cx, cy, s, c, c2)
    quad(cx - s*.25, cy - s*.34, cx + s*.25, cy - s*.34, cx + s*.46, cy - s*.08, cx - s*.46, cy - s*.08, c)
    tri(cx - s*.46, cy - s*.08, cx + s*.46, cy - s*.08, cx, cy + s*.44, c)
    local t = 1.2
    line(cx - s*.46, cy - s*.08, cx + s*.46, cy - s*.08, c2, t)
    line(cx - s*.25, cy - s*.34, cx - s*.12, cy - s*.08, c2, t); line(cx + s*.25, cy - s*.34, cx + s*.12, cy - s*.08, c2, t)
    line(cx - s*.12, cy - s*.08, cx, cy + s*.44, c2, t); line(cx + s*.12, cy - s*.08, cx, cy + s*.44, c2, t)
end
function Ic.coin(cx, cy, s, c, c2) circF(cx, cy, s*.44, c, 24); circS(cx, cy, s*.30, c2, th(s, .07), 20) end
function Ic.cap(cx, cy, s, c, c2) circF(cx, cy, s*.44, c, 24); circS(cx, cy, s*.28, c2, th(s, .07), 20) end
function Ic.box(cx, cy, s, c, c2)
    rectF(cx - s*.42, cy - s*.34, cx + s*.42, cy + s*.42, c, s*.08)
    rectF(cx - s*.42, cy - s*.34, cx + s*.42, cy - s*.14, c2, s*.08)
    rectF(cx - s*.07, cy - s*.34, cx + s*.07, cy + s*.10, c2, 0)
end
function Ic.leaf(cx, cy, s, c, c2)
    quad(cx - s*.4, cy + s*.4, cx - s*.38, cy - s*.05, cx + s*.4, cy - s*.42, cx + s*.05, cy + s*.38, c)
    line(cx - s*.38, cy + s*.4, cx + s*.2, cy - s*.22, c2, th(s, .07))
end
function Ic.ticket(cx, cy, s, c, c2)
    rectF(cx - s*.46, cy - s*.28, cx + s*.46, cy + s*.28, c, s*.08)
    circF(cx - s*.46, cy, s*.1, c2, 10); circF(cx + s*.46, cy, s*.1, c2, 10)
    line(cx - s*.2, cy - s*.1, cx + s*.2, cy - s*.1, c2, th(s, .07)); line(cx - s*.2, cy + s*.1, cx + s*.12, cy + s*.1, c2, th(s, .07))
end
function Ic.crown(cx, cy, s, c)
    local pts = { {-.4,-.3}, {-.2,0}, {0,-.3}, {.2,0}, {.4,-.3}, {.4,.3}, {-.4,.3} }
    local ox, oy = cx, cy + s*.1
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        tri(ox, oy, cx + a[1]*s, cy + a[2]*s, cx + b[1]*s, cy + b[2]*s, c)
    end
end
function Ic.plane(cx, cy, s, c, c2)
    tri(cx - s*.46, cy, cx + s*.46, cy - s*.38, cx + s*.02, cy + s*.2, c)
    tri(cx + s*.02, cy + s*.2, cx + s*.46, cy - s*.38, cx - s*.06, cy + s*.40, c2)
end
function Ic.calendar(cx, cy, s, c, c2)
    rectF(cx - s*.42, cy - s*.34, cx + s*.42, cy + s*.42, c, s*.1)
    rectF(cx - s*.33, cy - s*.06, cx + s*.33, cy + s*.33, c2, s*.05)
    line(cx - s*.2, cy - s*.46, cx - s*.2, cy - s*.24, c, th(s, .1)); line(cx + s*.2, cy - s*.46, cx + s*.2, cy - s*.24, c, th(s, .1))
end
function Ic.refresh(cx, cy, s, c)
    local r, t = s*.34, th(s, .12)
    local a0, a1, n = math.rad(-30), math.rad(250), 14
    local px, py = cx + math.cos(a0)*r, cy + math.sin(a0)*r
    for i = 1, n do
        local a = a0 + (a1 - a0) * i / n
        local x, y = cx + math.cos(a)*r, cy + math.sin(a)*r
        line(px, py, x, y, c, t); px, py = x, y
    end
    local tx, ty = -math.sin(a1), math.cos(a1)
    local nx, ny = math.cos(a1), math.sin(a1)
    tri(px + tx*s*.24, py + ty*s*.24, px + nx*s*.17, py + ny*s*.17, px - nx*s*.17, py - ny*s*.17, c)
end
function Ic.move(cx, cy, s, c)
    local t, h = th(s, .1), s*.14
    line(cx - s*.38, cy, cx + s*.38, cy, c, t); line(cx, cy - s*.38, cx, cy + s*.38, c, t)
    tri(cx - s*.5, cy, cx - s*.32, cy - h, cx - s*.32, cy + h, c)
    tri(cx + s*.5, cy, cx + s*.32, cy - h, cx + s*.32, cy + h, c)
    tri(cx, cy - s*.5, cx - h, cy - s*.32, cx + h, cy - s*.32, c)
    tri(cx, cy + s*.5, cx - h, cy + s*.32, cx + h, cy + s*.32, c)
end
function Ic.search(cx, cy, s, c)
    circS(cx - s*.08, cy - s*.08, s*.28, c, th(s, .1), 20)
    line(cx + s*.13, cy + s*.13, cx + s*.4, cy + s*.4, c, th(s, .13))
end
function Ic.check(cx, cy, s, c)
    line(cx - s*.3, cy, cx - s*.08, cy + s*.24, c, th(s, .14)); line(cx - s*.08, cy + s*.24, cx + s*.32, cy - s*.24, c, th(s, .14))
end

function Ic.spark(cx, cy, s, c)
    quad(cx, cy - s*.5, cx + s*.12, cy, cx, cy + s*.5, cx - s*.12, cy, c)
    quad(cx - s*.5, cy, cx, cy - s*.12, cx + s*.5, cy, cx, cy + s*.12, c)
end
function Ic.wheel(cx, cy, s, c, c2)
    circF(cx, cy, s*.44, c, 24); circF(cx, cy, s*.30, c2, 20)
    for i = 0, 3 do
        local a = i * math.pi / 4
        line(cx + math.cos(a)*s*.30, cy + math.sin(a)*s*.30, cx - math.cos(a)*s*.30, cy - math.sin(a)*s*.30, c, th(s, .07))
    end
    circF(cx, cy, s*.09, c, 10)
end
function Ic.chip(cx, cy, s, c, c2)
    for i = -1, 1 do
        line(cx + i*s*.2, cy - s*.46, cx + i*s*.2, cy + s*.46, c, th(s, .07))
        line(cx - s*.46, cy + i*s*.2, cx + s*.46, cy + i*s*.2, c, th(s, .07))
    end
    rectF(cx - s*.32, cy - s*.32, cx + s*.32, cy + s*.32, c, s*.06)
    rectF(cx - s*.16, cy - s*.16, cx + s*.16, cy + s*.16, c2, s*.04)
end
function Ic.doc(cx, cy, s, c, c2)
    rectF(cx - s*.34, cy - s*.44, cx + s*.34, cy + s*.44, c, s*.06)
    for i = 0, 2 do line(cx - s*.2, cy - s*.22 + i*s*.2, cx + s*.2, cy - s*.22 + i*s*.2, c2, th(s, .07)) end
end
function Ic.gun(cx, cy, s, c, c2)
    rectF(cx - s*.46, cy - s*.22, cx + s*.46, cy + s*.02, c, s*.04)
    quad(cx - s*.12, cy + s*.02, cx + s*.12, cy + s*.02, cx + s*.04, cy + s*.44, cx - s*.14, cy + s*.44, c)
    rectF(cx + s*.2, cy - s*.34, cx + s*.34, cy - s*.22, c2, 1)
end
function Ic.wings(cx, cy, s, c, c2)
    for k = -1, 1, 2 do
        tri(cx + k*s*.04, cy + s*.24, cx + k*s*.5, cy - s*.36, cx + k*s*.3, cy + s*.1, c)
        tri(cx + k*s*.04, cy + s*.24, cx + k*s*.5, cy - s*.1, cx + k*s*.24, cy + s*.3, c2)
    end
end
function Ic.camera(cx, cy, s, c, c2)
    rectF(cx - s*.46, cy - s*.26, cx + s*.46, cy + s*.36, c, s*.08)
    rectF(cx - s*.2, cy - s*.4, cx + s*.12, cy - s*.24, c, s*.04)
    circF(cx, cy + s*.06, s*.2, c2, 18); circS(cx, cy + s*.06, s*.12, c, th(s, .06), 14)
end
function Ic.can(cx, cy, s, c, c2)
    rectF(cx - s*.34, cy - s*.3, cx + s*.34, cy + s*.44, c, s*.06)
    quad(cx + s*.1, cy - s*.3, cx + s*.3, cy - s*.46, cx + s*.34, cy - s*.36, cx + s*.34, cy - s*.3, c)
    rectF(cx - s*.2, cy - s*.12, cx + s*.2, cy + s*.26, c2, s*.04)
end
function Ic.car(cx, cy, s, c, c2)
    quad(cx - s*.46, cy + s*.12, cx - s*.34, cy - s*.1, cx + s*.34, cy - s*.1, cx + s*.46, cy + s*.12, c)
    quad(cx - s*.28, cy - s*.1, cx - s*.16, cy - s*.34, cx + s*.16, cy - s*.34, cx + s*.28, cy - s*.1, c)
    rectF(cx - s*.46, cy + s*.04, cx + s*.46, cy + s*.22, c, s*.04)
    circF(cx - s*.26, cy + s*.24, s*.12, c2, 12); circF(cx + s*.26, cy + s*.24, s*.12, c2, 12)
end

local WINGC = {
    {"зелен", .3, .85, .45}, {"голуб", .4, .85, 1}, {"син", .25, .45, 1}, {"фиолет", .65, .35, 1},
    {"черн", .25, .25, .3}, {"бел", .95, .95, 1}, {"красн", .95, .3, .3}, {"желт", .98, .85, .25},
}
local function itemIcon(name, cx, cy, s)
    local n = strLower(name)
    local function has(w) return n:find(w, 1, true) ~= nil end
    local dark = c4(.08, .08, .12, 1)
    local metal
    if has("золот") then metal = {c4(.98,.80,.22,1), c4(.72,.52,.08,1)}
    elseif has("серебр") then metal = {c4(.82,.86,.95,1), c4(.52,.58,.72,1)}
    elseif has("бронз") then metal = {c4(.85,.52,.28,1), c4(.56,.30,.14,1)} end
    if has("рулетк") then Ic.wheel(cx, cy, s, (metal or {c4(.9,.3,.3,1)})[1], dark)
    elseif has("sport+") then Ic.gear(cx, cy, s, c4(1,.6,.25,1), dark)
    elseif has("sport") then Ic.gear(cx, cy, s, c4(.4,.65,1,1), dark)
    elseif has("improv") then Ic.gear(cx, cy, s, c4(.45,.85,.5,1), dark)
    elseif has("чип") then Ic.chip(cx, cy, s, c4(.35,.9,.85,1), dark)
    elseif has("чертеж") or has("чертёж") then Ic.doc(cx, cy, s, c4(.45,.7,1,1), dark)
    elseif has("компенсатор") or has("цев") or has("приклад") then Ic.gun(cx, cy, s, c4(.7,.72,.8,1), dark)
    elseif has("крылья") then
        local col = {.9,.9,1}
        for _, w in ipairs(WINGC) do if has(w[1]) then col = {w[2], w[3], w[4]}; break end end
        Ic.wings(cx, cy, s, c4(col[1], col[2], col[3], 1), c4(col[1]*.65, col[2]*.65, col[3]*.65, 1))
    elseif has("диск") then Ic.wheel(cx, cy, s, c4(.75,.78,.88,1), dark)
    elseif has("фотоаппарат") then Ic.camera(cx, cy, s, c4(.7,.72,.85,1), dark)
    elseif has("канистр") then Ic.can(cx, cy, s, c4(.9,.35,.3,1), c4(.55,.15,.12,1))
    elseif has("delorean") then Ic.car(cx, cy, s, c4(.8,.82,.9,1), dark)
    elseif metal then Ic.coin(cx, cy, s, metal[1], metal[2])
    elseif has("укроп") then Ic.leaf(cx, cy, s, c4(.35,.85,.45,1), c4(.12,.45,.22,1))
    elseif has("материал") then Ic.box(cx, cy, s, c4(.80,.60,.35,1), c4(.55,.38,.20,1))
    elseif has("ящик") then Ic.box(cx, cy, s, c4(.95,.70,.25,1), c4(.70,.45,.12,1))
    elseif has("крышеч") then Ic.cap(cx, cy, s, c4(.95,.30,.30,1), c4(1,1,1,.9))
    elseif has("подар") then Ic.gift(cx, cy, s, c4(1,.45,.78,1), dark)
    elseif has("сертификат") then Ic.ticket(cx, cy, s, c4(.30,.80,1,1), dark)
    elseif has("талон") then Ic.ticket(cx, cy, s, c4(1,.70,.30,1), dark)
    else Ic.diamond(cx, cy, s, c4(.45,.85,1,1), c4(.15,.35,.6,1)) end
end

local function pill(id, x, y, w, h, label, icon, kind, f)
    local clicked, hov = hit(id, x, y, w, h)
    local t = ease(id, hov and 1 or 0)
    local r, g, b
    if kind == 'green' then r, g, b = GREEN[1], GREEN[2], GREEN[3]
    elseif kind == 'red' then r, g, b = RED[1], RED[2], RED[3]
    elseif kind == 'pink' then r, g, b = 1, .38, .78
    else r, g, b = clamp01(P.ar*1.2 + .1), clamp01(P.ag*1.2 + .1), clamp01(P.ab*1.1 + .05) end
    rectF(x, y, x + w, y + h, c4(r*.25, g*.25, b*.25, .55 + .3*t), h*.3)
    rectS(x, y, x + w, y + h, c4(r, g, b, .7 + .3*t), h*.3, 1.4)
    local col = c4(clamp01(r + .25), clamp01(g + .25), clamp01(b + .25), 1)
    local tw = TS(label, f or F.b)
    local total = tw + (icon and 28 or 0)
    local sx = x + (w - total) / 2
    if icon then icon(sx + 10, y + h/2, 20, col, c4(r*.25, g*.25, b*.25, 1)) end
    TXM(sx + (icon and 28 or 0), y + h/2, label, col, f or F.b)
    return clicked
end

local function drawSwitch(id, x, y, val, w, h)
    w, h = w or 46, h or 24
    local t = ease(id .. "sw", val and 1 or 0, 14)
    rectF(x, y, x + w, y + h, c4(.22 + (P.ar - .22)*t, .2 + (P.ag - .2)*t, .28 + (P.ab - .28)*t, 1), h/2)
    circF(x + h/2 + (w - h)*t, y + h/2, h/2 - 3, W(1), 18)
end
local function switchBtn(id, x, y, val)
    local clicked = hit(id, x, y, 46, 24)
    drawSwitch(id, x, y, val)
    return clicked
end

local function slider(id, x, y, w, v, vmin, vmax)
    local _, hov, act = hit(id, x - 8, y - 9, w + 16, 22)
    local changed = false
    local t = (v - vmin) / (vmax - vmin)
    if act then
        local mx = (imgui.GetMousePos().x - OX) / SC
        t = clamp01((mx - x) / w); v = vmin + t * (vmax - vmin); changed = true
    end
    t = clamp01(t)
    rectF(x, y - 3, x + w, y + 3, A(.3, .95), 3)
    rectF(x, y - 3, x + math.max(6, w*t), y + 3, A(1.1), 3)
    local k = ease(id .. "k", (hov or act) and 1 or 0)
    circF(x + w*t, y, 7 + 2*k, W(1), 18)
    circS(x + w*t, y, 7 + 2*k, A(1.2), 2, 18)
    return v, changed
end

local function pager(xr, y, page, pages)
    local bw, gap, tw = 42, 8, 76
    local rx = xr - bw
    local tx = rx - gap - tw
    local lx = tx - gap - bw
    local delta = 0
    for i = 1, 2 do
        local x = (i == 1) and lx or rx
        local enabled = (i == 1) and page > 1 or page < pages
        local clicked, hov = hit("##pg" .. i, x, y, bw, bw)
        local t = ease("pg" .. i, (hov and enabled) and 1 or 0)
        rectF(x, y, x + bw, y + bw, A(.25 + .25*t, enabled and .95 or .5), 12)
        rectS(x, y, x + bw, y + bw, A(1, enabled and (.55 + .3*t) or .2), 12, 1.2)
        local ic = enabled and L(.6) or L(.2, .5)
        if i == 1 then Ic.chevL(x + bw/2, y + bw/2, 24, ic) else Ic.chevR(x + bw/2, y + bw/2, 24, ic) end
        if clicked and enabled then delta = (i == 1) and -1 or 1 end
    end
    TXC(tx + tw/2, y + bw/2 - 11, page .. " / " .. pages, W(1), F.b)
    return delta
end

local function markDirty() settingsDirty = true; applyTheme() end

local function closeMenu()
    showMainUI.v = false
    selectedDate = nil
end

local function doClear()
    local f = io.open(logFile, 'w')
    if f then
        f:write(json.encode({})); f:close()
        chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}История очищена", -1)
        prepareDates()
        selectedDate = nil; histPage = 1
    end
end

local function header(icon, title, sub)
    circF(300, 122, 26, A(.3, .9), 32)
    circS(300, 122, 26, A(1.2, .9), 2, 32)
    icon(300, 122, 26, L(.45), A(.3))
    TX(342, 98, title, W(1), F.h)
    TX(342, 130, sub, L(.45, .9), F.s)
end

local function footer(title, sub, page, pages)
    rectF(258, 500, 986, 566, A(.14, .9), 16)
    rectS(258, 500, 986, 566, A(.9, .4), 16, 1)
    circF(296, 533, 22, A(.5, .95), 28)
    circF(296, 524, 2.6, W(1), 10)
    line(296, 531, 296, 543, W(1), 3)
    TX(332, 512, title, W(1), F.b)
    TX(332, 536, sub, L(.45, .9), F.s)
    if pages then
        local d = pager(968, 512, page, pages)
        return d
    end
    return 0
end

local function card(x, y, w, h, title)
    rectF(x, y, x + w, y + h, A(.2, .85), 14)
    rectS(x, y, x + w, y + h, A(.9, .3), 14, 1)
    if title then TX(x + 16, y + 12, title, W(1), F.b) end
end

local function dotText(x, y, on, onText, offText)
    local c = on and GC(1) or RC(1)
    circF(x + 4, y + 10, 4, c, 12)
    TX(x + 14, y, on and onText or offText, c, F.b)
end

local function enabledCount()
    local n = 0
    for _, name in ipairs(ITEMS_LIST) do if itemFilter[name] then n = n + 1 end end
    return n
end

local function xf(ox, oy, a, sc)
    local ca, sa = math.cos(a), math.sin(a)
    sc = sc or 1
    return function(u, v) u, v = u * sc, v * sc; return ox + u * ca - v * sa, oy + u * sa + v * ca end
end
local function ptri(f, u1, v1, u2, v2, u3, v3, col)
    local x1, y1 = f(u1, v1); local x2, y2 = f(u2, v2); local x3, y3 = f(u3, v3)
    tri(x1, y1, x2, y2, x3, y3, col)
end
local function pquad(f, u1, v1, u2, v2, u3, v3, u4, v4, col)
    ptri(f, u1, v1, u2, v2, u3, v3, col); ptri(f, u1, v1, u3, v3, u4, v4, col)
end
local function pline(f, u1, v1, u2, v2, col, t)
    local x1, y1 = f(u1, v1); local x2, y2 = f(u2, v2); line(x1, y1, x2, y2, col, t)
end
local function pell(f, u0, v0, a, b, col)
    local cx, cy = f(u0, v0)
    local n = 22
    for k = 1, n do
        local a1, a2 = (k - 1) / n * math.pi * 2, k / n * math.pi * 2
        local x1, y1 = f(u0 + math.cos(a1) * a, v0 + math.sin(a1) * b)
        local x2, y2 = f(u0 + math.cos(a2) * a, v0 + math.sin(a2) * b)
        tri(cx, cy, x1, y1, x2, y2, col)
    end
end

local function arcLine(cx, cy, r, a0, a1, col, th)
    local n = math.max(2, math.ceil((a1 - a0) / 0.15))
    local x0, y0 = cx + math.cos(a0) * r, cy + math.sin(a0) * r
    for i = 1, n do
        local a = a0 + (a1 - a0) * i / n
        local x1, y1 = cx + math.cos(a) * r, cy + math.sin(a) * r
        line(x0, y0, x1, y1, col, th)
        x0, y0 = x1, y1
    end
end
local function ellS(cx, cy, rx, ry, col, th)
    local n, x0, y0 = 30, cx + rx, cy
    for i = 1, n do
        local a = i / n * math.pi * 2
        local x1, y1 = cx + math.cos(a) * rx, cy + math.sin(a) * ry
        line(x0, y0, x1, y1, col, th)
        x0, y0 = x1, y1
    end
end
local function ellF(cx, cy, rx, ry, col)
    local n = 28
    for i = 1, n do
        local a1, a2 = (i - 1) / n * math.pi * 2, i / n * math.pi * 2
        tri(cx, cy, cx + math.cos(a1) * rx, cy + math.sin(a1) * ry, cx + math.cos(a2) * rx, cy + math.sin(a2) * ry, col)
    end
end
local function gem(cx, cy, s, c1, c2)
    quad(cx, cy - s, cx + s * .75, cy - s * .15, cx, cy + s, cx - s * .75, cy - s * .15, c1)
    tri(cx - s * .75, cy - s * .15, cx, cy - s, cx, cy + s, c2)
    tri(cx, cy - s, cx + s * .75, cy - s * .15, cx, cy - s * .15, W(.35))
end

local function drawLogo()
    local t = cfg.anim and animationTime or 0
    local bob = cfg.anim and math.sin(t * 1.8) * 2 or 0
    local pl = 0.85 + 0.15 * P.pulse
    local pu = cfg.anim and (0.5 + 0.5 * math.sin(t * 3)) or 1
    local cx, cy = 130, 88

    circF(cx, cy, 80, A(1, .035 * pl), 44)
    circF(cx, cy, 64, A(1, .05 * pl), 40)
    circF(cx, cy, 46, A(1, .07 * pl), 36)

    for i = 0, 17 do
        local a0 = i / 18 * math.pi * 2 + t * 0.35
        arcLine(cx, cy, 70, a0, a0 + 0.20, A(1.45, .8), 2.4)
    end
    circS(cx, cy, 62, A(1, .38), 1.2, 48)
    for i = 0, 3 do
        local a = i / 4 * math.pi * 2 - t * 0.5 + math.pi / 4
        gem(cx + math.cos(a) * 62, cy + math.sin(a) * 62, 4.8, L(.5, .95), A(1.1, .95))
    end

    ellF(cx, 140, 56, 9, c4(0, 0, 0, .30))
    ellS(cx, 140, 56, 9, A(1, .25), 1)

    local gold, gold2 = c4(.97, .83, .43, 1), c4(.66, .48, .19, 1)
    local goldL = c4(1, .96, .74, .75)
    local wood, woodL = c4(.72, .13, .11, 1), c4(.96, .42, .32, .8)
    local sv = xf(103, 30 + bob, -0.42, .92)
    pell(sv, 0, 14, 17.5, 15.5, gold2)
    pell(sv, 0, 14, 15.5, 13.5, gold)
    ptri(sv, -17.5, 14, 17.5, 14, 0, 49, gold2)
    ptri(sv, -15.5, 14, 15.5, 14, 0, 45.5, gold)
    ptri(sv, -10, 6, -3.5, 3, -6.5, 30, goldL)
    pline(sv, 0, 0, 0, 45, gold2, 1.6)
    pquad(sv, -3.8, 44, 3.8, 44, 3.2, 69, -3.2, 69, gold2)
    pquad(sv, -3.4, 67, 3.4, 67, 3.4, 113, -3.4, 113, wood)
    pline(sv, -1.6, 70, -1.6, 111, woodL, 1.3)
    pline(sv, -11, 113, 11, 113, gold, 3.6); pline(sv, -11, 113, -11, 127, gold, 3.6)
    pline(sv, 11, 113, 11, 127, gold, 3.6);  pline(sv, -11, 127, 11, 127, gold, 3.6)
    pline(sv, -11, 113, 11, 113, goldL, 1.2)

    local dark, dark2 = c4(.11, .10, .16, 1), c4(.21, .19, .29, 1)
    local dv = xf(158, 26 + bob, 0.5, .92)

    local ux, uy
    for i = 0, 10 do
        local a = math.pi * i / 10
        local x, y = dv(math.cos(a) * 15, 8 + math.sin(a) * 7)
        if ux then line(ux, uy, x, y, dark2, 5); line(ux, uy, x, y, A(1.4, .9), 1.4) end
        ux, uy = x, y
    end
    pline(dv, -15, 8, -18, -6, dark2, 4.5); pline(dv, 15, 8, 18, -6, dark2, 4.5)
    pline(dv, -15, 8, -18, -6, A(1.4, .9), 1.3); pline(dv, 15, 8, 18, -6, A(1.4, .9), 1.3)

    pquad(dv, -10.5, 13, 10.5, 13, 10.5, 35, -10.5, 35, dark)
    pquad(dv, -7.5, 16, 7.5, 16, 7.5, 27, -7.5, 27, A(1.55, .6 + .4 * pu))
    for k = -1, 1 do
        local bx, by = dv(k * 4.5, 31)
        circF(bx, by, 1.5, L(.55, .9), 8)
    end
    pline(dv, -10.5, 13, 10.5, 13, A(1.3, .9), 1.2)

    pquad(dv, -2.8, 35, 2.8, 35, 2.8, 108, -2.8, 108, dark2)
    pline(dv, 0, 37, 0, 106, A(1.45, .85), 1.4)
    for _, v in ipairs({ 55, 78 }) do
        pquad(dv, -4.6, v, 4.6, v, 4.6, v + 6, -4.6, v + 6, dark)
        pline(dv, -4.6, v, 4.6, v, A(1.3, .9), 1)
    end

    pell(dv, 0, 114, 27, 13, A(.9, .28 * pl))
    pell(dv, 0, 114, 23.5, 10.8, dark)
    pell(dv, 0, 114, 19, 8.2, A(1.25, .92))
    pell(dv, 0, 114, 15.8, 6.4, dark2)
    pell(dv, 0, 114, 9.5, 3.8, L(.55, .5 + .4 * pu))

    local hx, hy = dv(0, 114)
    if cfg.anim then
        for k = 0, 2 do
            local ph = (t * 0.6 + k / 3) % 1
            local r = 14 + ph * 40
            ellS(hx, hy + 3, r, r * 0.3, A(1.5, (1 - ph) * .85), 1.6)
        end
    end

    local gy = 30 + bob * 1.6
    circF(cx, gy, 13, A(1.3, .12 + .1 * pu), 24)
    gem(cx, gy, 8.5, L(.55, 1), A(1.2, 1))
    local k = cfg.anim and (0.6 + 0.4 * math.sin(t * 3)) or 1
    Ic.spark(cx + 17, gy - 9, 9 * k, W(.95 * k))
    Ic.spark(54, 126 + bob, 9 * (2 - k), L(.6, .85))
    Ic.spark(206, 118 + bob, 7 * k, L(.6, .85))
end

local function setTab(i)
    activeTab = i; selectedDate = nil
    tabAt = os.clock(); settingsDirty = true
end

local function drawSidebar()
    rectF(14, 14, 246, 566, A(.13, .94), 18)
    rectS(14, 14, 246, 566, A(.9, .5), 18, 1.2)
    DL:PushClipRect(V(20, 20), V(240, 560), true)
    tri(246, 14, 246, 300, 60, 14, A(1, .06))
    tri(14, 566, 14, 380, 200, 566, A(1, .05))
    DL:PopClipRect()

    drawLogo()
    local sat = 0.55
    local function title(y, str, last)
        local f = F.xl
        local total = TS(str, f)
        local x = 130 - total / 2
        for k = 1, #str do
            local ch = str:sub(k, k)
            local col
            if cfg.anim then
                local r, g, b = hsv2rgb(((animationTime * 0.08) + k * 0.07) % 1, sat, 1)
                col = c4(r, g, b, 1)
            else col = last and A(1.35) or W(1) end
            TX(x, y, ch, col, f)
            x = x + TS(ch, f)
        end
    end
    title(164, "KLAD", false)
    title(200, "Helper", true)
    line(34, 247, 62, 247, A(1, .6), 1.5); line(198, 247, 226, 247, A(1, .6), 1.5)
    TXC(130, 238, "Edward Scripts", L(.5, .9), F.s)

    rectF(28, 276, 232, 392, A(.22, .85), 14)
    rectS(28, 276, 232, 392, A(.9, .35), 14, 1)
    Ic.cube(56, 306, 30, L(.55), A(.9), A(.55))
    TX(84, 288, "Всего кладов:", L(.5, .95), F.s)
    TX(84, 304, tostring(totalChestsAll), W(1), F.h)
    line(44, 334, 216, 334, A(1, .2), 1)
    Ic.gift(56, 362, 28, L(.55), A(.22))
    TX(84, 342, "Получено наград:", L(.5, .95), F.s)
    TX(84, 358, tostring(totalItemsAll), W(1), F.h)

    local function stat(y, label, on, onT, offT)
        local c = on and GC(1) or RC(1)
        circF(38, y + 10, 4, c, 12)
        TX(50, y, label, L(.5, .9), F.s)
        TXR(226, y, on and onT or offT, c, F.s)
    end
    stat(408, "Автосбор", autoSelectEnabled.v, "ВКЛ", "ВЫКЛ")
    stat(432, "Метки на карте", kladPointsActive, "ВКЛ", "ВЫКЛ")
    stat(456, "Сундук сейчас", isKladChest, "открыт", "нет")

    line(40, 488, 220, 488, A(1, .25), 1)
    local bw1 = TS("By ", F.b)
    local bw2 = TS("Edward", F.b)
    local sx = 130 - (bw1 + bw2) / 2
    local tw2 = 0.8 + 0.2 * P.pulse
    Ic.spark(sx - 14, 510, 12 * tw2, A(1.5))
    Ic.spark(sx + bw1 + bw2 + 14, 510, 12 * tw2, A(1.5))
    TX(sx, 499, "By ", L(.5), F.b)
    TX(sx + bw1, 499, "Edward", A(1.4), F.b)

    local ttw = TS("Telegram-Edward", F.s)
    local tx0 = 130 - (22 + 8 + ttw) / 2
    local clicked, hov = hit("##tg", tx0 - 4, 526, ttw + 40, 28)
    circF(tx0 + 10, 540, 11, hov and c4(.25,.75,1,1) or c4(.16,.62,.9,1), 20)
    Ic.plane(tx0 + 9, 540, 15, W(1), c4(.78,.9,1,1))
    TX(tx0 + 28, 531, "Telegram-Edward", hov and W(1) or L(.5), F.s)
    if hov then line(tx0 + 28, 549, tx0 + 28 + ttw, 549, L(.5), 1) end
    if clicked then
        pcall(imgui.SetClipboardText, 'https://t.me/edward_scripts')
        chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Ссылка скопирована: {c0c0c0}t.me/edward_scripts")
    end
end

local TABS = {
    { "История",   Ic.clock },
    { "Автосбор",  Ic.bolt  },
    { "Награды",   Ic.gift  },
    { "Карта",     Ic.pin   },
    { "Настройки", Ic.gear  },
}

local function drawTabs()
    local x = 266
    for i, t in ipairs(TABS) do
        local tw, tth = TS(t[1], F.b)
        local w, y, h = tw + 52, 24, 46
        local clicked, hov = hit("##tab" .. i, x, y, w, h)
        local act = (activeTab == i)
        local e = ease("tab" .. i, (hov or act) and 1 or 0)
        local ic, tc
        if act then
            if cfg.glow then rectS(x - 1, y - 1, x + w + 1, y + h + 1, A(1.2, .22 * P.pulse), 15, 3) end
            rectF(x, y, x + w, y + h, A(.62, .98), 14)
            rectF(x + 6, y + 2, x + w - 6, y + 4, W(.12), 2)
            rectS(x, y, x + w, y + h, A(1.4, .85), 14, 1.2)
            rectF(x + 14, y + h - 4, x + w - 14, y + h - 2, A(1.6), 1)
            if cfg.anim then
                local sx = x + ((animationTime * 0.45) % 1.3 - 0.15) * w
                DL:PushClipRect(V(x + 2, y + 2), V(x + w - 2, y + h - 2), true)
                quad(sx, y, sx + 18, y, sx + 4, y + h, sx - 14, y + h, W(.16))
                DL:PopClipRect()
            end
            ic, tc = W(1), W(1)
        else
            rectF(x, y, x + w, y + h, A(.2 + .12*e, .8), 14)
            rectS(x, y, x + w, y + h, A(.9, .22 + .3*e), 14, 1)
            ic, tc = L(.45 + .25*e), L(.5 + .3*e)
        end
        t[2](x + 23, y + h/2, 20, ic, act and A(.62) or A(.25))
        TX(x + 40, y + (h - tth)/2, t[1], tc, F.b)
        if clicked and activeTab ~= i then setTab(i) end
        x = x + w + 6
    end
    line(916, 30, 916, 64, A(1, .3), 1)
    local clicked, hov = hit("##close", 932, 24, 46, 46)
    rectF(932, 24, 978, 70, hov and c4(.9, .25, .35, .9) or A(.2, .8), 14)
    rectS(932, 24, 978, 70, hov and c4(1, .4, .5, 1) or A(.9, .3), 14, 1)
    Ic.close(955, 47, 22, W(1))
    if clicked then closeMenu() end
end

local function drawHistory()
    if selectedDate == nil then
        header(Ic.clock, "История кладов", "Здесь отображается ваша история полученных наград")
        if confirmClear and os.clock() - confirmClearAt > 3 then confirmClear = false end
        if pill("##clear", 762, 100, 206, 44, confirmClear and "Точно очистить?" or "Очистить историю",
                Ic.trash, confirmClear and 'red' or 'pink') then
            if confirmClear then doClear(); confirmClear = false
            else confirmClear = true; confirmClearAt = os.clock() end
        end

        local PER = 6
        local pages = math.max(1, math.ceil(#allDates / PER))
        histPage = math.min(math.max(histPage, 1), pages)
        if #allDates == 0 then
            Ic.cube(622, 282, 64, L(.4, .5), A(.8, .5), A(.5, .5))
            TXC(622, 336, "Пока нет записей", L(.6), F.h)
            TXC(622, 374, "Откройте клад — и история появится здесь", L(.4, .85), F.reg)
        end
        local today = os.date('%d.%m.%Y')
        for i = 1, PER do
            local date = allDates[(histPage - 1) * PER + i]
            if not date then break end
            local st = dateStats[date]
            local y = 164 + (i - 1) * 52
            local clicked, hov = hit("##hr" .. i, 276, y, 692, 46)
            local e = ease("hr" .. i, hov and 1 or 0)
            rectF(276, y, 968, y + 46, A(.18 + .1*e, .9), 12)
            rectS(276, y, 968, y + 46, A(1, .12 + .35*e), 12, 1)
            Ic.calendar(306, y + 23, 24, L(.45), A(.18))
            TX(340, y + 12, date, W(1), F.b)
            local dw = TS(date, F.b)
            if date == today then
                rectF(350 + dw, y + 12, 350 + dw + 70, y + 34, A(.6, .9), 8)
                TXC(350 + dw + 35, y + 14, "Сегодня", W(1), F.s)
            end
            Ic.cube(580, y + 23, 22, L(.55), A(.9), A(.55))
            TXM(600, y + 23, "Кладов: " .. st.chests, L(.65), F.reg)
            Ic.gift(752, y + 23, 22, L(.55), A(.18))
            TXM(772, y + 23, "Предметов: " .. st.totalItems, L(.65), F.reg)
            Ic.chevR(948, y + 23, 20, L(.4 + .4*e))
            if clicked then
                selectedDate = date; detailPage = 1
                detailItems = {}
                for _, it in ipairs(st.items) do table.insert(detailItems, it) end
                table.sort(detailItems, function(a, b) return a.count > b.count end)
            end
        end
        local d = footer("Всего собрано кладов: " .. totalChestsAll,
            "Вы получаете награды за найденные клады на карте.", histPage, pages)
        histPage = histPage + d
    else
        local st = dateStats[selectedDate]
        if not st then selectedDate = nil; return end
        local clicked, hov = hit("##back", 276, 98, 48, 48)
        rectF(276, 98, 324, 146, A(.25 + (hov and .15 or 0), .95), 14)
        rectS(276, 98, 324, 146, A(1.2, .6), 14, 1.2)
        Ic.back(300, 122, 26, L(.6))
        if clicked then selectedDate = nil; return end
        TX(342, 98, "Клады за " .. selectedDate, W(1), F.h)
        TX(342, 130, "Кладов: " .. st.chests .. "   |   Предметов: " .. st.totalItems, L(.45, .9), F.s)

        local PER = 6
        local pages = math.max(1, math.ceil(#detailItems / PER))
        detailPage = math.min(math.max(detailPage, 1), pages)
        local maxc = 1
        for _, it in ipairs(detailItems) do if it.count > maxc then maxc = it.count end end
        for i = 1, PER do
            local it = detailItems[(detailPage - 1) * PER + i]
            if not it then break end
            local y = 164 + (i - 1) * 52
            rectF(276, y, 968, y + 46, A(.18, .9), 12)
            rectS(276, y, 968, y + 46, A(1, .12), 12, 1)
            rectF(286, y + 6, 320, y + 40, A(.1, .95), 10)
            rectS(286, y + 6, 320, y + 40, A(1, .3), 10, 1)
            itemIcon(it.name, 303, y + 23, 22)
            TXM(336, y + 23, fit(it.name, 250, F.b), W(1), F.b)
            rectF(600, y + 20, 880, y + 26, A(.1, .95), 3)
            rectF(600, y + 20, 600 + math.max(6, 280 * it.count / maxc), y + 26, A(1.2), 3)
            TXR(950, y + 12, "x" .. it.count, L(.4), F.b)
        end
        local d = footer("Всего предметов: " .. st.totalItems, "Дата: " .. selectedDate, detailPage, pages)
        detailPage = detailPage + d
    end
end

local function drawAuto()
    header(Ic.bolt, "Автосбор призов", "Автоматически забирает призы из клада по вашему фильтру")
    local on = autoSelectEnabled.v
    TXR(910, 112, on and "Включён" or "Выключен", on and GC(1) or RC(1), F.b)
    if switchBtn("##autoTg", 922, 110, on) then autoSelectEnabled.v = not autoSelectEnabled.v; settingsDirty = true end

    local chips = {
        { Ic.bolt, "Режим", on and "Активен" or "Отключён", on },
        { Ic.gift, "В фильтре", enabledCount() .. " из " .. #ITEMS_LIST, true },
        { Ic.cube, "Клад сейчас", (mountainMenuActive and isKladChest) and "Открыт" or "Ожидание", mountainMenuActive and isKladChest },
    }
    for i, c in ipairs(chips) do
        local x = 276 + (i - 1) * 235
        local chipClick, chipHov = false, false
        if i == 2 then chipClick, chipHov = hit("##chipf", x, 164, 221, 64) end
        local ce = ease("chip" .. i, chipHov and 1 or 0)
        rectF(x, 164, x + 221, 228, A(.2 + .1 * ce, .85), 14)
        rectS(x, 164, x + 221, 228, A(1, .3 + .4 * ce), 14, 1)
        if i == 2 then Ic.chevR(x + 200, 196, 18, L(.35 + .45 * ce)); if chipClick then setTab(3) end end
        circF(x + 34, 196, 20, A(.35, .95), 24)
        c[1](x + 34, 196, 22, L(.55), A(.35), A(.6))
        TX(x + 64, 174, c[2], L(.5, .95), F.s)
        TX(x + 64, 194, c[3], c[4] and W(1) or L(.6), F.b)
    end

    card(276, 242, 340, 236, "Тайминг сбора")
    TX(292, 282, "Задержка перед сбором", L(.5, .95), F.reg)
    TXR(600, 282, cfg.startDelay .. " мс", W(1), F.b)
    local v, ch = slider("##sd", 292, 322, 308, cfg.startDelay, 100, 2000)
    if ch then cfg.startDelay = math.floor(v / 50 + .5) * 50; settingsDirty = true end
    TX(292, 342, "Пауза между призами", L(.5, .95), F.reg)
    TXR(600, 342, cfg.pickDelay .. " мс", W(1), F.b)
    v, ch = slider("##pd", 292, 382, 308, cfg.pickDelay, 50, 1000)
    if ch then cfg.pickDelay = math.floor(v / 10 + .5) * 10; settingsDirty = true end
    if pill("##all", 292, 418, 148, 40, "Забрать все", Ic.check, 'green') then
        for _, name in ipairs(ITEMS_LIST) do itemFilter[name] = true end; saveFilter()
    end
    if pill("##none", 452, 418, 148, 40, "Пропустить", nil, 'red') then
        for _, name in ipairs(ITEMS_LIST) do itemFilter[name] = false end; saveFilter()
    end

    local live = #currentChestItems > 0
    local list = live and currentChestItems or lastChestItems
    card(628, 242, 340, 236, live and "Текущий клад" or "Последний клад")
    if #list == 0 then
        Ic.cube(798, 336, 46, L(.4, .5), A(.8, .5), A(.5, .5))
        TXC(798, 376, "Пока пусто", L(.55), F.b)
        TXC(798, 400, "Откройте клад — призы появятся здесь", L(.4, .85), F.s)
    else
        for i = 1, math.min(5, #list) do
            local it = list[i]
            local y = 280 + (i - 1) * 38
            rectF(642, y, 954, y + 32, A(.12, .9), 9)
            itemIcon(it.name, 662, y + 16, 20)
            TXM(684, y + 16, fit(it.name, 190, F.reg), W(1), F.reg)
            TXR(942, y + 7, "x" .. it.count, L(.4), F.b)
        end
        if #list > 5 then TXR(954, 466 - 12, "и ещё " .. (#list - 5), L(.4, .8), F.s) end
    end
    footer("Сессия: открыто кладов " .. sessionChests .. ", предметов " .. sessionItems,
        "Автосбор забирает только призы, отмеченные во вкладке «Награды».")
end

local function drawRewards()
    header(Ic.gift, "Награды клада", "Отметьте призы для автосбора")

    rectF(700, 102, 968, 142, A(.18, .95), 14)
    rectS(700, 102, 968, 142, A(1, .4), 14, 1)
    Ic.search(722, 122, 20, L(.5))
    imgui.SetCursorScreenPos(V(742, 103))
    imgui.PushItemWidth(224 * SC)
    local pfs = pushF(F.reg)
    local pvs = pcall(imgui.PushStyleVar, imgui.StyleVar.FramePadding, imgui.ImVec2(4 * SC, 11 * SC))
    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0, 0, 0, 0))
    imgui.InputText("##search", searchBuf, 256)
    imgui.PopStyleColor(3); imgui.PopItemWidth()
    if pvs then imgui.PopStyleVar() end
    if pfs then imgui.PopFont() end
    local searchStr = ffi.string(searchBuf)
    if searchStr == "" and not imgui.IsItemActive() then
        TXM(752, 122, "Поиск награды...", L(.3, .7), F.reg)
    end
    local needle = encoding.UTF8:decode(searchStr)

    if pill("##allr", 276, 156, 150, 36, "Забрать все", Ic.check, 'green') then
        for _, name in ipairs(ITEMS_LIST) do itemFilter[name] = true end; saveFilter()
    end
    if pill("##nonr", 438, 156, 170, 36, "Пропустить все", Ic.close, 'red') then
        for _, name in ipairs(ITEMS_LIST) do itemFilter[name] = false end; saveFilter()
    end
    TXR(968, 164, "Выбрано: " .. enabledCount() .. " / " .. #ITEMS_LIST, L(.5, .95), F.b)

    local filtered = {}
    for _, name in ipairs(ITEMS_LIST) do if matchItem(name, needle) then table.insert(filtered, name) end end
    local PER = 10
    local pages = math.max(1, math.ceil(#filtered / PER))
    rewardPage = math.min(math.max(rewardPage, 1), pages)
    if #filtered == 0 then TXC(622, 320, "Ничего не найдено", L(.5), F.h) end
    for i = 1, PER do
        local name = filtered[(rewardPage - 1) * PER + i]
        if not name then break end
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y = 276 + col * 352, 204 + row * 56
        local on = itemFilter[name]
        local clicked, hov = hit("##rw" .. i, x, y, 340, 50)
        local e = ease("rw" .. i, hov and 1 or 0)
        rectF(x, y, x + 340, y + 50, A(.18 + .1*e, .9), 12)
        rectS(x, y, x + 340, y + 50, on and A(1.3, .5 + .2*e) or A(1, .12 + .2*e), 12, 1.2)
        rectF(x + 8, y + 8, x + 42, y + 42, A(.1, .95), 10)
        rectS(x + 8, y + 8, x + 42, y + 42, A(1, .3), 10, 1)
        itemIcon(name, x + 25, y + 25, 22)
        TX(x + 54, y + 7, fit(name, 212, F.b), on and W(1) or L(.35, .8), F.b)
        TX(x + 54, y + 28, on and "Забирать" or "Пропуск", on and GC(1) or RC(.9), F.s)
        drawSwitch("##rwsw" .. i, x + 282, y + 13, on)
        if clicked then itemFilter[name] = not on; saveFilter() end
    end
    local d = footer("Выбрано призов: " .. enabledCount() .. " из " .. #ITEMS_LIST,
        "Не отмеченные призы автосбор пропускает.", rewardPage, pages)
    rewardPage = rewardPage + d
end

local function drawMap()
    header(Ic.pin, "Точки кладов", "Метки появляются прямо на месте нахождения кладов")
    local on = kladPointsActive
    rectF(738, 104, 968, 140, on and c4(.1, .3, .15, .8) or c4(.3, .1, .12, .8), 14)
    rectS(738, 104, 968, 140, on and GC(.7) or RC(.7), 14, 1.2)
    dotText(756, 112, on, "Активно: " .. (#KLAD_COORDS - kladDoneCount) .. " меток", "Метки не активны")

    local acts = {
        { "Включить",     "Создать метки",       Ic.pin,     GREEN },
        { "Перезагрузить","Пересоздать заново",  Ic.refresh, { clamp01(P.ar*1.2 + .1), clamp01(P.ag*1.2 + .1), clamp01(P.ab*1.1 + .05) } },
        { "Удалить",      "Убрать с карты",      Ic.trash,   RED },
    }
    for i, a in ipairs(acts) do
        local x = 276 + (i - 1) * 235
        local clicked, hov = hit("##act" .. i, x, 160, 221, 84)
        local e = ease("act" .. i, hov and 1 or 0)
        local c = a[4]
        rectF(x, 160, x + 221, 244, c4(c[1]*.22, c[2]*.22, c[3]*.22, .65 + .25*e), 16)
        rectS(x, 160, x + 221, 244, c4(c[1], c[2], c[3], .55 + .4*e), 16, 1.4)
        circF(x + 42, 202, 26, c4(c[1]*.35, c[2]*.35, c[3]*.35, 1), 28)
        a[3](x + 42, 202, 26, c4(clamp01(c[1] + .3), clamp01(c[2] + .3), clamp01(c[3] + .3), 1), c4(c[1]*.35, c[2]*.35, c[3]*.35, 1))
        TX(x + 80, 182, a[1], W(1), F.b)
        TX(x + 80, 206, a[2], c4(clamp01(c[1] + .25), clamp01(c[2] + .25), clamp01(c[3] + .25), .85), F.s)
        if clicked then
            if i == 1 then
                if not kladPointsActive then spawnKladPickups()
                else chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Метки уже активны! Используй Перезагрузить.", -1) end
            elseif i == 2 then
                resetCollected()
                spawnKladPickups()
                chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Метки перезагружены!", -1)
            else
                if kladPointsActive then removeKladPickups()
                else chat("{FF0000}| {FFFFFF}Klad Helper {FFFFFF}Нет активных меток для удаления.", -1) end
            end
        end
    end

    card(276, 260, 692, 150, "Как это работает")
    local lines = {
        "Жёлтые маркеры ставятся на точках кладов, подобранные скрываются.",
        "Нашли точку клада которой нет в скрипте? Введи /save и напиши нам — добавим!",
        "Метки видны только локально (только тебе), другие игроки их не видят.",
    }
    for i, t in ipairs(lines) do
        local y = 296 + (i - 1) * 27
        circF(300, y + 10, 3.5, A(1.3), 10)
        TX(314, y, t, L(.5, .95), F.reg)
    end

    footer("Осталось точек: " .. (#KLAD_COORDS - kladDoneCount) .. " из " .. #KLAD_COORDS, "Метки видны только вам — другие игроки их не видят.")
end

local scaleDraft = nil
local function drawSettings()
    header(Ic.gear, "Настройки", "Внешний вид меню и поведение скрипта")
    if pill("##reset", 786, 100, 182, 44, "Сбросить", Ic.refresh, 'accent') then
        setAccentRGB(PRESETS[1][2], PRESETS[1][3], PRESETS[1][4])
        cfg.alpha, cfg.startDelay, cfg.pickDelay = 0.97, 400, 150
        cfg.chatNotify, cfg.anim, cfg.glow = true, true, true
        autoSelectEnabled.v = true
        cfg.uiScale = 1.0; scaleDraft = nil
        markDirty()
    end

    card(276, 160, 340, 318, "Цвет меню")
    TX(292, 196, "Готовые темы", L(.5, .95), F.s)
    for i, p in ipairs(PRESETS) do
        local cx, cy = 308 + (i - 1) * 38, 232
        local clicked, hov = hit("##pr" .. i, cx - 15, cy - 15, 30, 30)
        local sel = math.abs(accent[1] - p[2]) + math.abs(accent[2] - p[3]) + math.abs(accent[3] - p[4]) < .03
        local e = ease("pr" .. i, (hov or sel) and 1 or 0)
        circF(cx, cy, 12 + 2*e, c4(p[2], p[3], p[4], 1), 24)
        if sel then circS(cx, cy, 17, W(.95), 2, 24) end
        if clicked then setAccentRGB(p[2], p[3], p[4]); markDirty() end
    end
    TX(292, 262, "Оттенок", L(.5, .95), F.s)
    local N = 48
    for i = 0, N - 1 do
        local r, g, b = hsv2rgb(i / N, 1, 1)
        rectF(292 + i * 308 / N, 286, 292 + (i + 1) * 308 / N + 1, 302, c4(r, g, b, 1), 0)
    end
    rectS(292, 286, 600, 302, A(1, .5), 3, 1)
    local _, hov, act = hit("##hue", 288, 282, 316, 24)
    if act then
        hsvState.h = clamp01(((imgui.GetMousePos().x - OX) / SC - 292) / 308) * 0.9999
        setAccentHSV(); markDirty()
    end
    local hx = 292 + hsvState.h * 308
    circF(hx, 294, 9, W(1), 18)
    do local r, g, b = hsv2rgb(hsvState.h, 1, 1); circF(hx, 294, 6, c4(r, g, b, 1), 18) end

    TX(292, 316, "Насыщенность", L(.5, .95), F.s)
    TXR(600, 316, math.floor(hsvState.s * 100 + .5) .. "%", W(1), F.s)
    local v, ch = slider("##sat", 292, 348, 308, hsvState.s, 0.15, 1)
    if ch then hsvState.s = v; setAccentHSV(); markDirty() end
    TX(292, 366, "Яркость", L(.5, .95), F.s)
    TXR(600, 366, math.floor(hsvState.v * 100 + .5) .. "%", W(1), F.s)
    v, ch = slider("##val", 292, 398, 308, hsvState.v, 0.45, 1)
    if ch then hsvState.v = v; setAccentHSV(); markDirty() end
    rectF(292, 426, 600, 462, A(.1, .95), 10)
    circF(312, 444, 11, A(1), 20)
    circS(312, 444, 11, W(.8), 1.5, 20)
    TXM(334, 444, string.format("#%02X%02X%02X", math.floor(accent[1]*255 + .5), math.floor(accent[2]*255 + .5), math.floor(accent[3]*255 + .5)), W(1), F.b)
    TXR(586, 436, "цвет меню", L(.4, .8), F.s)

    card(628, 160, 340, 318, "Окно и поведение")
    TX(644, 196, "Прозрачность окна", L(.5, .95), F.s)
    TXR(952, 196, math.floor(cfg.alpha * 100 + .5) .. "%", W(1), F.s)
    v, ch = slider("##alpha", 644, 228, 308, cfg.alpha, 0.6, 1)
    if ch then cfg.alpha = v; markDirty() end

    local shown = scaleDraft or cfg.uiScale
    TX(644, 246, "Масштаб меню", L(.5, .95), F.s)
    TXR(952, 246, math.floor(shown * 100 + .5) .. "%", W(1), F.s)
    v, ch = slider("##uiscale", 644, 278, 308, shown, 0.5, 1.6)
    if ch then scaleDraft = math.floor(v * 20 + .5) / 20 end
    if scaleDraft and not imgui.IsMouseDown(0) then
        if scaleDraft ~= cfg.uiScale then cfg.uiScale = scaleDraft; settingsDirty = true end
        scaleDraft = nil
    end
    local rows = {
        { "Анимации интерфейса", "anim" },
        { "Свечение рамки",      "glow" },
        { "Уведомления в чат",   "chatNotify" },
    }
    for i, r in ipairs(rows) do
        local y = 298 + (i - 1) * 44
        rectF(644, y, 952, y + 38, A(.12, .9), 12)
        TXM(660, y + 19, r[1], W(1), F.reg)
        if switchBtn("##cfg" .. i, 892, y + 7, cfg[r[2]]) then cfg[r[2]] = not cfg[r[2]]; settingsDirty = true end
    end
    local y = 430
    rectF(644, y, 952, y + 38, A(.12, .9), 12)
    TXM(660, y + 19, "Автосбор призов", W(1), F.reg)
    if switchBtn("##cfgauto", 892, y + 7, autoSelectEnabled.v) then autoSelectEnabled.v = not autoSelectEnabled.v; settingsDirty = true end
    footer("Настройки сохраняются автоматически", "Команда: /kh — открыть меню.")
end

local function drawMainFrame()
    DT = imgui.GetIO().DeltaTime
    if cfg.anim then animationTime = animationTime + DT end
    pulseEffect   = math.sin(animationTime * 2.0) * 0.15 + 0.85
    shimmerEffect = math.sin(animationTime * 3.0) * 0.05 + 0.95

    updateScale(WW, WH, 0.94, 0.97)
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2((sw - WW * SC) / 2, (sh - WH * SC) / 2), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(WW * SC, WH * SC), imgui.Cond.Always)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
                + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoMove
    if imgui.Begin(u8"Klad Helper", nil, flags) then
        local wp = imgui.GetWindowPos()
        OX, OY = wp.x, wp.y
        DL = imgui.GetWindowDrawList()
        P.ar, P.ag, P.ab = accent[1], accent[2], accent[3]
        P.pulse = cfg.anim and pulseEffect or 1

        rectF(0, 0, WW, WH, A(.085, cfg.alpha), 18)
        DL:PushClipRect(V(8, 8), V(WW - 8, WH - 8), true)
        tri(760, 0, 900, 0, 420, WH, A(1, .035))
        tri(250, 0, 330, 0, 0, 330, A(1, .045))
        tri(WW, 300, WW, WH, 640, WH, A(1, .04))
        DL:PopClipRect()
        rectS(.5, .5, WW - .5, WH - .5, A(1.1, .9), 18, 1.5)
        if cfg.glow then
            rectS(2.5, 2.5, WW - 2.5, WH - 2.5, A(1.3, .22 * P.pulse), 17, 1)
            rectS(4.5, 4.5, WW - 4.5, WH - 4.5, A(1.3, .10 * P.pulse), 16, 1)
        end

        drawSidebar()
        drawTabs()
        rectF(258, 84, 986, 490, A(.15, .88), 16)
        rectS(258, 84, 986, 490, A(.9, .4), 16, 1)

        if activeTab == 1 then drawHistory()
        elseif activeTab == 2 then drawAuto()
        elseif activeTab == 3 then drawRewards()
        elseif activeTab == 4 then drawMap()
        else drawSettings() end
        local fade = cfg.anim and clamp01((os.clock() - tabAt) / 0.25) or 1
        if fade < 1 then
            rectF(258, 84, 986, 490, A(.15, (1 - fade) * .95), 16)
            rectF(258, 500, 986, 566, A(.14, (1 - fade) * .95), 16)
        end
    end
    imgui.End()
    imgui.PopStyleColor()
end

imgui.OnFrame(function() return showMainUI.v end,
    function(sub) sub.HideCursor = false; sub.LockPlayer = true end,
    function() drawMainFrame() end)

addEventHandler('onScriptTerminate', function(scr)
    local me = (script and script.this) or (thisScript and thisScript())
    if scr == me then clearMarks() end
end)

local function stripColors(str) return (str:gsub("{%x%x%x%x%x%x}", "")) end

function ev.onServerMessage(color, text)
    if type(text) ~= "string" then return end
    local clean = norm(stripColors(text))
    if not clean:find("Добавлено в инвентарь:", 1, true) then return end

    local inChest = mountainMenuActive or isKladChest or (os.clock() - chestSeenAt < 12)
    if not inChest then return end

    local patterns = {
        'чертёж%s*"([^"]+)"%s*%((%d+)%s*шт%)',    'чертёж%s*"([^"]+)"',
        'предмет%s*"([^"]+)"%s*%((%d+)%s*шт%)',    'предмет%s*"([^"]+)"',
        'аксессуар%s*"([^"]+)"%s*%((%d+)%s*шт%)',  'аксессуар%s*"([^"]+)"',
        'ларец%s*"([^"]+)"%s*%((%d+)%s*шт%)',      'ларец%s*"([^"]+)"',
        'ящик%s*"([^"]+)"%s*%((%d+)%s*шт%)',       'ящик%s*"([^"]+)"',
        'одежда%s*"([^"]+)"',
        'объект%s*"([^"]+)"',
        'тех%. тюнинг%s*"([^"]+)"',

        'инвентарь:%s*[^"]-"([^"]+)"%s*%((%d+)%s*шт%)',
        'инвентарь:%s*[^"]-"([^"]+)"',
    }
    for _, pat in ipairs(patterns) do
        local name, count = clean:match(pat)
        if name then
            table.insert(currentChestItems, { name = name, count = tonumber(count) or 1 })
            lastItemAt = os.clock()
            return
        end
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    if not doesDirectoryExist(CFG_DIR) then
        createDirectory(CFG_DIR)
    end

    initFilter()
    loadSettings()
    pcall(applyTheme)

    sampRegisterChatCommand("kh", function()
        prepareDates()
        selectedDate = nil
        showMainUI.v = true
    end)

    chat(
        "{FF0000}|{FFFF00} Klad Helper {FFFFFF}Загружен {c0c0c0}/kh {FF0000}By {00FFFF}Edward",
        -1
    )

    local lastSettingsSave = os.clock()
    while true do
        wait(0)
        if settingsDirty and os.clock() - lastSettingsSave >= 0.6 then
            settingsDirty = false; lastSettingsSave = os.clock(); saveSettings()
        end

        checkCollectedPickups()
        processAutoSelect()

        if #currentChestItems > 0 then
            local idle = os.clock() - lastItemAt
            if (not mountainMenuActive and idle > 2.5) or idle > 8 then
                local items = currentChestItems
                currentChestItems = {}
                saveChest(items, true)
            end
        end

    end
end
