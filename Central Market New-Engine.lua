script_name("Central Market")
script_version("1.1")
script_author("By Edward")

require 'lib.moonloader'
local ffi = require 'ffi'
local lfs = require 'lfs'
local androidEnvUtil = require('android.jnienv-util')
local cjson = require 'cjson'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local imgui = require 'mimgui'
local fa = require 'fAwesome6'
local raknet = require 'lib.samp.raknet'
local events = require 'lib.samp.events'
local getTplBuf, getTplDelayBuf, applyTplVars, stripColorTags,
      normalizeItemLabel, writeJsonToDisk, readJsonFromDisk, sendDialogReplyDelayed,
      watchShopProximity, stopBuyingScan, finishBuyingScan, processBuyingPage,
      parseMobileCEF, finishInventoryScan, startInventoryScan, sendMobileCEFClick, sendMobileCEFClose, sendMobileCEFPacket,
      processSellingCoroutine, formatCash, toLowerRu, renderSourceCard,
      renderTargetCard, DrawAccentButton


local menu_open = imgui.new.bool(false)
local buy_config_modal_open = imgui.new.bool(false)
local menu_alpha = 0.0
local last_ui_scale = 1.0

function animateMenuFade(target_open)
    local start_alpha = menu_alpha
    local start_time = os.clock()
    local duration = 0.22
    lua_thread.create(function()
        while true do
            wait(0)
            local t = (os.clock() - start_time) / duration
            if t < 0 then t = 0 end
            if t > 1 then t = 1 end
            local target_alpha = target_open and 1.0 or 0.0
            menu_alpha = start_alpha + (target_alpha - start_alpha) * t
            if t >= 1 then break end
        end
        menu_alpha = target_open and 1.0 or 0.0
    end)
end
local drag_scroll = { left_down = false, left_y = 0, right_down = false, right_y = 0, settings_down = false, settings_y = 0 }
local current_tab = 1

local LocalNickname = nil

local RunState = {
    auto_pr = { global_cooldown = 0, last_vr_time = 0, pending_vr_response = false },
    buying_scan = { active = false, stage = nil, current_page = 1, all_items = {}, current_dialog_id = nil },
    inventory_scan = { 
        active = false, stage = "", has_received_data = false, last_packet_time = 0, current_dialog_id = nil
    },
    selling = {
        active = false, stage = "", current_idx = 1, total = 0, current_item = nil, available_items = {}, last_packet_time = 0
    },
    buying = {
        active = false, stage = "", current_idx = 1, total = 0, current_item = nil
    }
}

local tpl_bufs = {}
local tpl_delay_bufs = {}

local QUALITY_TAGS = {
    "Улучшение оружия", "Унив. тюнинг", "Виз. тюнинг", "Тех. тюнинг", "Авто. номер",
    "Аксессуар", "Сертификат", "Приманка", "Саженец", "Улучшение",
    "Винила", "Объект", "Одежда", "Телефон", "Урожай", "Чертёж",
    "Предмет", "Актер", "Ларец", "Рыба", "Семя", "Туша", "Шкура", "Ящик"
}


local filter_buf_sell = ffi.new('char[128]')
local filter_buf_buy = ffi.new('char[128]')
local target_filter_sell = ffi.new('char[128]')
local target_filter_buy = ffi.new('char[128]')
local qty_bufs_sell = {}
local qty_bufs_buy = {}
local cost_bufs_sell = {}
local cost_bufs_buy = {}

local edit_modal = {
    active = false,
    item = nil,
    index = nil,
    is_sell = false,
    target_table = nil,
    buf_price = ffi.new('char[32]'),
    buf_amount = ffi.new('char[32]')
}

local swipe_state = {
    start_pos = imgui.ImVec2(0, 0),
    is_dragging = false,
    col = 0,
    threshold = 10.0
}

local list_cache_sell = { query = nil, items = {} }
local list_cache_buy = { query = nil, items = {} }

local open_cef_list = {}
local prev_menu_open = false

local ROOT_DIR = getWorkingDirectory() .. '/CentralMarket/'
local FILE_INVENTORY = ROOT_DIR .. 'cm_inventory.json'
local FILE_CATALOG = ROOT_DIR .. 'cm_buyable.json'
local FILE_NAMES = ROOT_DIR .. 'data/cm_items_db.json'
local FILE_CFG_SELL = ROOT_DIR .. 'cm_config_sell.json'
local FILE_CFG_BUY = ROOT_DIR .. 'cm_config_buy.json'
local FILE_SETTINGS = ROOT_DIR .. 'cm_settings.json'
local FILE_BUY_PROFILES = ROOT_DIR .. 'cm_buy_profiles.json'

local Prefs = {
    auto_name = false,
    shop_name = "Telegram @edward_scripts",
    auto_pr = { active = false, items = {} },
    dialog_delay = 150,  
    cef_delay = 1200,
    show_float_button = true,
    float_btn_always_visible = false,
    float_btn_x = 0.012,
    float_btn_y = 0.40,
    win_w = 92,
    win_h = 88,
    font_pct = 100,
    fmt_head = "",
    fmt_cmd = 0,
    fmt_lenw = 2,
    fmt_tail = "",
    ev_click = 2
}

local FLOAT_BTN_DEFAULT_X = 0.012
local FLOAT_BTN_DEFAULT_Y = 0.40
local FLOAT_BTN_W = 250.0
local FLOAT_BTN_H = 70.0

local Palette = {
    bg_main          = imgui.ImVec4(0.03, 0.03, 0.03, 1.00),
    bg_secondary     = imgui.ImVec4(0.12, 0.12, 0.12, 1.00),
    bg_tertiary      = imgui.ImVec4(0.20, 0.20, 0.20, 1.00),
    accent_primary   = imgui.ImVec4(0.00, 0.55, 1.00, 1.00),
    accent_success   = imgui.ImVec4(0.00, 0.75, 0.00, 1.00),
    accent_danger    = imgui.ImVec4(0.90, 0.10, 0.10, 1.00),
    text_primary     = imgui.ImVec4(1.00, 1.00, 1.00, 1.00),
    text_secondary   = imgui.ImVec4(0.55, 0.55, 0.55, 1.00),
    border           = imgui.ImVec4(1.00, 1.00, 1.00, 0.10)
}

local fnt_main = nil
local fnt_icons = nil
local fnt_icons_lg = nil

local stock_items = {}
local catalog_items = {}
local name_lookup = {}


function readJsonFromDisk(path)
    local f = io.open(path, "r")
    if f then
        local str = f:read("*a")
        f:close()
        local ok, res = pcall(cjson.decode, str)
        return ok and res or {}
    end
    return {}
end


local sell_cfg = readJsonFromDisk(FILE_CFG_SELL)
local buy_cfg = readJsonFromDisk(FILE_CFG_BUY)
local buy_profiles = readJsonFromDisk(FILE_BUY_PROFILES)
local selected_buy_profile = nil
local buy_profile_name_buf = ffi.new('char[64]')

local loaded_sets = readJsonFromDisk(FILE_SETTINGS)
if loaded_sets.auto_name ~= nil then Prefs.auto_name = loaded_sets.auto_name end
if loaded_sets.shop_name then Prefs.shop_name = loaded_sets.shop_name end
if loaded_sets.auto_pr then Prefs.auto_pr = loaded_sets.auto_pr end
if loaded_sets.dialog_delay then Prefs.dialog_delay = tonumber(loaded_sets.dialog_delay) or Prefs.dialog_delay end
if loaded_sets.cef_delay then Prefs.cef_delay = tonumber(loaded_sets.cef_delay) or Prefs.cef_delay end
if loaded_sets.show_float_button ~= nil then Prefs.show_float_button = loaded_sets.show_float_button end
if loaded_sets.float_btn_always_visible ~= nil then Prefs.float_btn_always_visible = loaded_sets.float_btn_always_visible end
if loaded_sets.float_btn_x then Prefs.float_btn_x = tonumber(loaded_sets.float_btn_x) or Prefs.float_btn_x end
if loaded_sets.float_btn_y then Prefs.float_btn_y = tonumber(loaded_sets.float_btn_y) or Prefs.float_btn_y end
for _, k in ipairs({ "win_w", "win_h", "font_pct", "fmt_head", "fmt_cmd", "fmt_lenw", "fmt_tail", "ev_click" }) do
    if loaded_sets[k] ~= nil then Prefs[k] = loaded_sets[k] end
end
Prefs.win_w    = math.max(50, math.min(100, math.floor(tonumber(Prefs.win_w) or 92)))
Prefs.win_h    = math.max(50, math.min(100, math.floor(tonumber(Prefs.win_h) or 88)))
Prefs.font_pct = math.max(70, math.min(140, math.floor(tonumber(Prefs.font_pct) or 100)))

local b_auto_name = imgui.new.bool(Prefs.auto_name)
local buf_shop_name = ffi.new('char[64]', Prefs.shop_name)
local i_dialog_delay = imgui.new.int(Prefs.dialog_delay)
local i_cef_delay = imgui.new.int(Prefs.cef_delay)
local SZ = { w = imgui.new.int(Prefs.win_w), h = imgui.new.int(Prefs.win_h), f = imgui.new.int(Prefs.font_pct), drag = {} }
function SZ.slider(title, id, ref, vmin, vmax, fmt, key)
    imgui.TextColored(Palette.text_secondary, title)
    imgui.PushItemWidth(520)
    imgui.SliderInt(id, ref, vmin, vmax, fmt)
    imgui.PopItemWidth()
    local active = imgui.IsItemActive()
    if SZ.drag[key] and not active then
        Prefs[key] = ref[0]
        writeJsonToDisk(FILE_SETTINGS, Prefs)
    end
    SZ.drag[key] = active
    imgui.Spacing()
end
local b_show_float_button = imgui.new.bool(Prefs.show_float_button)
local b_float_always_visible = imgui.new.bool(Prefs.float_btn_always_visible)
local b_float_btn_move_mode = imgui.new.bool(false)
local i_debug_subid = imgui.new.int(8)
local b_debug_flag = imgui.new.bool(false)

stock_items = readJsonFromDisk(FILE_INVENTORY)
catalog_items = readJsonFromDisk(FILE_CATALOG)
local raw_names = readJsonFromDisk(FILE_NAMES)
if raw_names then
    for k, v in pairs(raw_names) do
        name_lookup[tostring(k)] = type(v) == "table" and v.n or v
    end
end

function events.onShowDialog(id, style, title, b1, b2, text)
    local clean_title = stripColorTags(title)
    local clean_text = stripColorTags(text)


    if id == 8 and (clean_title:find("Название лавки") or clean_title:find("Название")) then
        if Prefs.auto_name and Prefs.shop_name ~= "" then
            lua_thread.create(function()
                wait(200)
                sampSendDialogResponse(id, 1, 0, u8:decode(Prefs.shop_name))
            end)
            return false
        end
    end

    if RunState.inventory_scan.active then
        if id == 731 or id == 1191 then
            if RunState.inventory_scan.stage == "settings" then
                local list_idx = -1
                local current_idx = 0
                for line in text:gmatch("[^\r\n]+") do
                    local c_line = stripColorTags(line):gsub("%s+", "")
                    if c_line:find("Настройкиинвентаря") then 
                        list_idx = (style == 5 and current_idx - 1) or current_idx 
                        break 
                    end
                    current_idx = current_idx + 1
                end
                if list_idx ~= -1 then
                    sampSendDialogResponse(id, 1, list_idx, "")
                end
            elseif RunState.inventory_scan.stage == "parsing" then
                sampSendDialogResponse(id, 0, 0, "")
            end
            return false
        end
        
        if id == 734 or id == 1190 then
            if RunState.inventory_scan.stage == "settings" then
                local list_idx = -1
                local current_idx = 0
                local is_enabled = false
                
                for line in text:gmatch("[^\r\n]+") do
                    local c_line = stripColorTags(line):gsub("%s+", "")
                    if c_line:find("Новыйинвентарь") or c_line:find("НовыйCEFинвентарь") then
                        list_idx = (style == 5 and current_idx - 1) or current_idx
                        if c_line:find("Включено") or c_line:find("Включен") then 
                            is_enabled = true 
                        end
                        break
                    end
                    current_idx = current_idx + 1
                end
                
                if list_idx ~= -1 then
                    if is_enabled then
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Перезапуск CEF инвентаря...", -1)
                        sampSendDialogResponse(id, 1, list_idx, "")
                    else
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Чтение пакетов инвентаря...", -1)
                        RunState.inventory_scan.stage = "parsing"
                        sampSendDialogResponse(id, 1, list_idx, "")
                    end
                end
            elseif RunState.inventory_scan.stage == "parsing" then
                sampSendDialogResponse(id, 0, 0, "")
            end
            return false
        end
    end

    if RunState.buying_scan.active then
        if RunState.buying_scan.stage == 'waiting_dialog' and (title:find("Управление лавкой") or title:find("Лавка") or id == 9) then
            RunState.buying_scan.stage = 'waiting_category_menu'
            local idx = 0
            local target_idx = 1
            for line in text:gmatch("[^\r\n]+") do
                if stripColorTags(line):find("Выставить товар на скупку") then target_idx = idx break end
                idx = idx + 1
            end
            sampSendDialogResponse(id, 1, target_idx, "")
            return false
        end
        
        if RunState.buying_scan.stage == 'waiting_category_menu' and (title:find("Скупка:") or id == 10 or id == 801) then
            RunState.buying_scan.stage = 'waiting_full_list_menu'
            local idx = 0
            local target_idx = 1
            for line in text:gmatch("[^\r\n]+") do
                if stripColorTags(line):find("Поиск по категориям") then target_idx = idx break end
                idx = idx + 1
            end
            sampSendDialogResponse(id, 1, target_idx, "")
            return false
        end
        
        if RunState.buying_scan.stage == 'waiting_full_list_menu' and (id == 911 or id == 802 or title:find("Категории для поиска") or text:find("Весь список")) then
            RunState.buying_scan.stage = 'processing_page'
            local idx = 0
            local target_idx = -1
            for line in text:gmatch("[^\r\n]+") do
                if stripColorTags(line):find("Весь список") then target_idx = idx break end
                idx = idx + 1
            end
            if target_idx == -1 then target_idx = idx - 1 end
            sampSendDialogResponse(id, 1, target_idx, "")
            return false
        end
        
        if RunState.buying_scan.stage == 'processing_page' and (id == 10 or title:find("Скупка:") or title:find("Весь список") or title:find("Страница")) then
            processBuyingPage(text, id)
            return false
        end
        
        if RunState.buying_scan.stage == 'closing' then
            sampSendDialogResponse(id, 0, 0, "")
            if title:find("Управление лавкой") or title:find("Лавка") or id == 9 then
                RunState.buying_scan.active = false
                menu_open[0] = true
            end
            return false
        end
    end

    if RunState.buying.active then
        if RunState.buying.stage == 'waiting_dialog' and (title:find("Управление лавкой") or title:find("Лавка") or id == 9) then
            RunState.buying.current_item = buy_cfg[RunState.buying.current_idx]
            RunState.buying.stage = 'waiting_search_menu'
            sendDialogReplyDelayed(id, 1, 1, "")
            return false
        end

        if RunState.buying.stage == 'waiting_search_menu' and (id == 10 or id == 801 or title:find("Скупка:")) then
            RunState.buying.stage = 'waiting_search_input'
            sendDialogReplyDelayed(id, 1, 0, "")
            return false
        end

        if RunState.buying.stage == 'waiting_search_input' and (id == 909 or text:find("название") or text:find("индекс")) then
            RunState.buying.stage = 'waiting_amount_price'
            local item_id = RunState.buying.current_item.model_id or RunState.buying.current_item.index
            if not item_id then
                for _, db_item in ipairs(catalog_items) do
                    if db_item.name == RunState.buying.current_item.name then
                        item_id = db_item.index
                        break
                    end
                end
            end
            sendDialogReplyDelayed(id, 1, 0, tostring(item_id or RunState.buying.current_item.name))
            return false
        end

        if RunState.buying.stage == 'waiting_amount_price' and (id == 11 or text:find("через запятую") or text:find("количество") or text:find("цену") or text:find("штук") or text:find("цвет")) then
            local input_str = ""
            local text_lower = text:lower()

            if text_lower:find("цвет аксессуара") or text_lower:find("и цвет") then
                local color_id = math.max(0, math.floor(RunState.buying.current_item.amount or 0))
                input_str = string.format("%d,%d", math.floor(RunState.buying.current_item.price), color_id)
            elseif text_lower:find("количество") or text_lower:find("штук") then
                local amount = math.max(1, math.floor(RunState.buying.current_item.amount or 1))
                input_str = string.format("%d,%d", amount, math.floor(RunState.buying.current_item.price))
            else
                input_str = string.format("%d,%d", math.floor(RunState.buying.current_item.amount or 1), math.floor(RunState.buying.current_item.price))
            end
            
            sendDialogReplyDelayed(id, 1, 0, input_str)

            RunState.buying.current_idx = RunState.buying.current_idx + 1
            if RunState.buying.current_idx > RunState.buying.total then
                RunState.buying.stage = 'closing'
            else
                RunState.buying.current_item = buy_cfg[RunState.buying.current_idx]
                RunState.buying.stage = 'waiting_search_menu'
            end
            return false
        end

        if RunState.buying.stage == 'closing' then
            sampSendDialogResponse(id, 0, 0, "")
            if title:find("Управление лавкой") or title:find("Лавка") or id == 9 then
                RunState.buying.active = false
                menu_open[0] = true
                sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Все товары выставлены на скупку!", -1)
            end
            return false
        end
    end

    if RunState.selling.active then
        if RunState.selling.stage == 'waiting_dialog' and (title:find("Управление лавкой") or title:find("Лавка") or id == 9) then
            local target_idx = 0
            local current = 0
            for line in text:gmatch("[^\r\n]+") do
                if stripColorTags(line):find("Выставить товар на продажу") then target_idx = current break end
                current = current + 1
            end
            sampSendDialogResponse(id, 1, target_idx, "")
            
            RunState.selling.available_items = {}
            RunState.selling.last_packet_time = 0
            RunState.selling.stage = 'waiting_cef_data'
            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Сбор данных лавки...", -1)
            return false
        end
        
        if RunState.selling.stage == 'waiting_input' and (id == 240 or text:find("цену") or text:find("через запятую") or text:find("количество")) then
            local input_str = ""
            local text_lower = text:lower()
            
            if text_lower:find("через запятую") or text_lower:find("введите количество") or text_lower:find("укажите количество") then
                local sell_amount = RunState.selling.current_item.amount
                if RunState.selling.current_item.use_max then
                    local clean_dialog_text = stripColorTags(text)
                    local max_qty = clean_dialog_text:match("[Вв]ыставить%s*(%d+)%s*шт")
                    if not max_qty then max_qty = clean_dialog_text:match("(%d+)%s*шт%.?%s*$") end
                    if max_qty then sell_amount = tonumber(max_qty) end
                end
                input_str = string.format("%d,%d", sell_amount, RunState.selling.current_item.price)
            else
                input_str = tostring(RunState.selling.current_item.price)
            end
            
            sampSendDialogResponse(id, 1, 0, input_str)
            RunState.selling.stage = 'next_item'
            return false
        end
        
        if RunState.selling.stage == 'closing' then
            sampSendDialogResponse(id, 0, 0, "")
            if title:find("Управление лавкой") or title:find("Лавка") or id == 9 then
                RunState.selling.active = false
                menu_open[0] = true
            end
            return false
        end
    end
end

-- ================== ПАКЕТЫ CEF (как в Auto Upgrade Cards) ==================
local PK = {
    CEF = 220, SEND_TYPE = 63, GET_TYPE = 84, IFACE = 60, MAX_LEN = 32767,
    skipTry = { 2, 4, 3, 1, 5, 6 }, skip = nil,
    ev = tonumber(Prefs.ev_click) or 2,
    fmt = nil, ownSend = false,
    default = { head = { 60, 255, 255, 255, 255, 2, 0, 0, 0 }, cmdPos = 6, lenW = 2, tail = {} },
    mode = "none", count = { send = 0, recv = 0 }
}

do
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

    -- формат отправки, выученный раньше
    if type(Prefs.fmt_head) == "string" and Prefs.fmt_head ~= "" then
        local head = fromHex(Prefs.fmt_head)
        local pos = math.floor(tonumber(Prefs.fmt_cmd) or 0)
        if #head >= 2 and pos >= 2 and pos <= #head then
            PK.fmt = { head = head, cmdPos = pos, lenW = (tonumber(Prefs.fmt_lenw) == 4) and 4 or 2, tail = fromHex(Prefs.fmt_tail) }
        end
    end

    local function fmtKey(fmt)
        local head = {}
        for i, v in ipairs(fmt.head) do head[i] = (i == fmt.cmdPos) and 0 or v end
        return hexOf(head) .. "|" .. fmt.cmdPos .. "|" .. fmt.lenW .. "|" .. hexOf(fmt.tail)
    end

    local function saveFmt()
        Prefs.fmt_head = PK.fmt and hexOf(PK.fmt.head) or ""
        Prefs.fmt_cmd  = PK.fmt and PK.fmt.cmdPos or 0
        Prefs.fmt_lenw = PK.fmt and PK.fmt.lenW or 2
        Prefs.fmt_tail = PK.fmt and hexOf(PK.fmt.tail) or ""
        Prefs.ev_click = PK.ev
        writeJsonToDisk(FILE_SETTINGS, Prefs)
    end

    -- читает JSON из входящего пакета 220/84; смещение заголовка подбирается и запоминается
    local function readAt(bs, skip)
        raknetBitStreamResetReadPointer(bs)
        raknetBitStreamIgnoreBits(bs, 16)
        local hdr = {}
        for i = 1, skip do hdr[i] = raknetBitStreamReadInt8(bs) % 256 end
        local length  = raknetBitStreamReadInt16(bs)
        local encoded = raknetBitStreamReadInt8(bs)

        if not length or not encoded then return nil end
        if length <= 0 or length > PK.MAX_LEN then return nil end
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
        return str, hdr[1], hdr[2]
    end

    local function readCefString(bs)
        raknetBitStreamResetReadPointer(bs)
        if raknetBitStreamGetNumberOfBitsUsed(bs) < 80 then return nil end
        raknetBitStreamIgnoreBits(bs, 8)
        local ptype = raknetBitStreamReadInt8(bs)
        if ptype ~= PK.GET_TYPE then return nil end

        if PK.skip then
            local ok, str, a, b = pcall(readAt, bs, PK.skip)
            if ok and str then return str, a, b end
        end
        for _, skip in ipairs(PK.skipTry) do
            local ok, str, a, b = pcall(readAt, bs, skip)
            if ok and str then
                PK.skip = skip
                return str, a, b
            end
        end
        return nil
    end

    PK.readString = readCefString

    local function readRaw(bs)
        local count = math.floor(raknetBitStreamGetNumberOfBitsUsed(bs) / 8)
        if count < 2 or count > 700 then return nil end
        raknetBitStreamResetReadPointer(bs)
        local raw = {}
        for i = 1, count do raw[i] = raknetBitStreamReadInt8(bs) % 256 end
        raknetBitStreamResetReadPointer(bs)
        return raw
    end

    -- распознаёт формат клика (220, 63, 60, ...json) по пакету, который отправил сам клиент
    local function learnFormat(raw)
        local n = #raw
        if n < 9 or raw[1] ~= PK.CEF or raw[2] ~= PK.SEND_TYPE then return false end
        for _, lenW in ipairs({ 2, 4 }) do
            for i = lenW + 4, n do
                if raw[i] == 0x7B then
                    local L = raw[i - lenW] + raw[i - lenW + 1] * 256
                    if lenW == 4 then L = L + raw[i - 2] * 65536 + raw[i - 1] * 16777216 end
                    if L >= 2 and i + L - 1 <= n and raw[i + L - 1] == 0x7D then
                        local head, tail = {}, {}
                        for k = 3, i - lenW - 1 do head[#head + 1] = raw[k] end
                        for k = i + L, n do tail[#tail + 1] = raw[k] end
                        if head[1] ~= PK.IFACE then return false end
                        local cmdPos
                        if #head == 9 and head[2] == 255 and head[3] == 255 and head[4] == 255 and head[5] == 255 then
                            cmdPos = 6
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

    local function buildRaw(fmt, cmd, payload)
        local raw = { PK.CEF, PK.SEND_TYPE }
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

    -- отправка готового битстрима (свои пакеты не попадают в хук отправки)
    function PK.send(bs)
        local send = raknetSendBitStreamEx or raknetSendBitStream
        PK.ownSend = true
        local ok = pcall(send, bs, 1, 7, 0)
        PK.ownSend = false
        return ok
    end

    local function sendCEF(cmd, payload)
        local fmt = PK.fmt or PK.default
        pcall(function()
            local raw = buildRaw(fmt, cmd, payload)
            local bs = raknetNewBitStream()
            for _, v in ipairs(raw) do
                v = v % 256
                if v > 127 then v = v - 256 end
                raknetBitStreamWriteInt8(bs, v)
            end
            PK.send(bs)
            raknetDeleteBitStream(bs)
        end)
    end

    function sendMobileCEFClick(slot, model_id, amount)
        local json_str = string.format('{"amount":%d,"id":%d,"slot":%d,"type":1}', amount, model_id, slot)
        sendCEF(PK.ev, json_str)
    end

    function PK.hookSend(id, bs)
        if id ~= PK.CEF or PK.ownSend then return end
        local ok, raw = pcall(readRaw, bs)
        if not ok or not raw or #raw < 9 or raw[2] ~= PK.SEND_TYPE then return end
        local good, fmt = learnFormat(raw)
        if not good then return end
        local cmd = raw[fmt.cmdPos]
        local from = #fmt.head + fmt.lenW + 3
        local chars = {}
        for k = from, #raw do chars[#chars + 1] = string.char(raw[k]) end
        local payload = table.concat(chars)
        if not payload:find('"slot"', 1, true) then return end
        local changed = (not PK.fmt) or fmtKey(PK.fmt) ~= fmtKey(fmt) or PK.ev ~= cmd
        PK.fmt, PK.ev = fmt, cmd
        if changed then
            pcall(saveFmt)
            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Формат пакета изучен и сохранён", -1)
        end
    end
end

local lastInteractPromptId = nil
local lastInteractTime = 0
local lastSeenInteractPromptId = nil

function sendMarketInteract(promptId)
    if promptId == lastInteractPromptId and (os.clock() - lastInteractTime) < 2 then
        return
    end
    lastInteractPromptId = promptId
    lastInteractTime = os.clock()

    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 63)
    raknetBitStreamWriteInt8(bs, 8)
    raknetBitStreamWriteInt32(bs, 7)
    raknetBitStreamWriteInt32(bs, promptId)
    raknetBitStreamWriteInt16(bs, 0)
    PK.send(bs)
    raknetDeleteBitStream(bs)
end

function PK.hookReceive(id, bs)
    if id ~= PK.CEF then return end
    local saved_offset = raknetBitStreamGetReadOffset(bs)
    local ok, json_str, interfaceid, subid = pcall(PK.readString, bs)
    pcall(raknetBitStreamSetReadOffset, bs, saved_offset)
    if not ok or type(json_str) ~= "string" or json_str == "" then return end
    json_str = json_str:gsub("%z", "")

    local automation_active = RunState.inventory_scan.active or RunState.buying_scan.active or RunState.selling.active or RunState.buying.active

    if interfaceid == 8 and subid == 18 then
        local pok, pdata = pcall(cjson.decode, json_str)
        if pok and type(pdata) == "table" and pdata.id then
            lastSeenInteractPromptId = pdata.id
            if automation_active then
                sendMarketInteract(pdata.id)
            end
        end
    end

    if automation_active then
        parseMobileCEF(interfaceid, json_str)
    end
end

-- регистрация хуков: RakLua, а если его нет - addEventHandler
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
    local m1 = reg("INCOMING_PACKET", function(id, bs) PK.count.recv = PK.count.recv + 1 pcall(PK.hookReceive, id, bs) end)
    local m2 = reg("OUTGOING_PACKET", function(id, bs) PK.count.send = PK.count.send + 1 pcall(PK.hookSend, id, bs) end)
    PK.mode = (m1 or "none") .. "/" .. (m2 or "none")
end


local CYRILLIC_LOWER_MAP = {}
for i = 0, 255 do
    local char = string.char(i)
    if i >= 192 and i <= 223 then
        CYRILLIC_LOWER_MAP[char] = string.char(i + 32)
    elseif i == 168 then
        CYRILLIC_LOWER_MAP[char] = string.char(184)
    else
        CYRILLIC_LOWER_MAP[char] = string.lower(char)
    end
end


imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    
    local style = imgui.GetStyle()
    style.WindowRounding    = 16.0
    style.ChildRounding     = 12.0
    style.FrameRounding     = 12.0
    style.ScrollbarSize     = 26.0
    style.ScrollbarRounding = 10.0
    style.WindowPadding     = imgui.ImVec2(0, 0)
    style.ItemSpacing       = imgui.ImVec2(10, 10)
    style.FramePadding       = imgui.ImVec2(10, 8)

    style.Colors[imgui.Col.WindowBg]             = Palette.bg_main
    style.Colors[imgui.Col.ChildBg]              = Palette.bg_secondary
    style.Colors[imgui.Col.Text]                 = Palette.text_primary
    style.Colors[imgui.Col.TextDisabled]         = Palette.text_secondary
    style.Colors[imgui.Col.Border]               = Palette.border
    style.Colors[imgui.Col.ScrollbarBg]          = imgui.ImVec4(0,0,0,0)
    style.Colors[imgui.Col.ScrollbarGrab]        = Palette.bg_tertiary
    style.Colors[imgui.Col.ScrollbarGrabHovered] = Palette.bg_tertiary
    style.Colors[imgui.Col.ScrollbarGrabActive]  = Palette.accent_primary

    local config = imgui.ImFontConfig()
    config.MergeMode = false
    
    local font_path = getWorkingDirectory() .. '/resource/fonts/trebucbd.ttf'
    
    fnt_main = io.Fonts:AddFontFromFileTTF(font_path, 30.0, config, io.Fonts:GetGlyphRangesCyrillic())
    
    local icon_config = imgui.ImFontConfig()
    icon_config.MergeMode = true
    icon_config.GlyphOffset = imgui.ImVec2(0, 2)
    local fa_ranges = imgui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    
    fnt_icons = io.Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), 28.0, icon_config, fa_ranges)
    
    local large_icon_config = imgui.ImFontConfig()
    fnt_icons_lg = io.Fonts:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), 40.0, large_icon_config, fa_ranges)
end)

imgui.OnFrame(
    function() return menu_open[0] or menu_alpha > 0.001 or RunState.inventory_scan.active or RunState.buying_scan.active or RunState.selling.active or RunState.buying.active end,
    function(this)
        local io = imgui.GetIO()
        local sw, sh = getScreenResolution()

        local ui_scale = math.min(1.0, (sh * 0.88) / 1020)
        if ui_scale < 0.55 then ui_scale = 0.55 end
        if ui_scale ~= last_ui_scale then
            imgui.GetStyle():ScaleAllSizes(ui_scale / last_ui_scale)
            last_ui_scale = ui_scale
        end
        local fscale = math.max(0.7, math.min(1.4, (tonumber(Prefs.font_pct) or 100) / 100))
        io.FontGlobalScale = ui_scale * fscale
        
        local win_w = sw * 0.98
        local win_h = sh * 0.90
        if win_w > 1200 then win_w = 1200 end

        if RunState.inventory_scan.active or RunState.buying_scan.active or RunState.selling.active or RunState.buying.active then
            local mod_w, mod_h = 460.0 * math.max(1.0, fscale), 280.0 * math.max(1.0, fscale)
            imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
            imgui.SetNextWindowSize(imgui.ImVec2(mod_w, mod_h), imgui.Cond.Always)
            
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(Palette.bg_secondary.x, Palette.bg_secondary.y, Palette.bg_secondary.z, 0.98))
            imgui.PushStyleColor(imgui.Col.Border, Palette.accent_primary)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 20.0)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 2.0)
            
            if imgui.Begin("##ScanningModal", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove) then
                local p = imgui.GetCursorScreenPos()
                local dl = imgui.GetWindowDrawList()
                
                local title = ""
                local subtitle = ""
                local icon = fa('spinner')
                local is_waiting = false
                local items_count = 0
                local accent_color = Palette.accent_primary

                if RunState.inventory_scan.active then
                    accent_color = Palette.accent_success
                    icon = fa('box_open')
                    items_count = #stock_items
                    if RunState.inventory_scan.stage == "waiting_user" then
                        title = u8"Ожидание инвентаря"
                        subtitle = u8"Пожалуйста, откройте свой инвентарь"
                        is_waiting = true
                    elseif RunState.inventory_scan.stage == "settings" then
                        title = u8"Настройка инвентаря"
                        subtitle = u8"Подготовка интерфейса CEF..."
                    elseif RunState.inventory_scan.stage == "parsing" then
                        title = u8"Чтение предметов"
                        subtitle = u8"Сбор данных... Не закрывайте окно"
                    end
                elseif RunState.buying_scan.active then
                    icon = fa('shop')
                    items_count = #RunState.buying_scan.all_items
                    if RunState.buying_scan.stage == 'waiting_dialog' then
                        title = u8"Ожидание лавки"
                        subtitle = u8"Откройте диалоговое окно лавки"
                        is_waiting = true
                    elseif RunState.buying_scan.stage == 'waiting_category_menu' or RunState.buying_scan.stage == 'waiting_full_list_menu' then
                        title = u8"Навигация по меню"
                        subtitle = u8"Открываем полный список товаров..."
                    elseif RunState.buying_scan.stage == 'processing_page' then
                        title = u8"Сканирование товаров"
                        subtitle = u8"Считывание страницы: " .. RunState.buying_scan.current_page
                    elseif RunState.buying_scan.stage == 'closing' then
                        title = u8"Завершение"
                        subtitle = u8"Автоматическое закрытие диалогов..."
                    end
                elseif RunState.selling.active then
                    icon = fa('paper_plane')
                    items_count = RunState.selling.total
                    if RunState.selling.stage == 'waiting_dialog' then
                        title = u8"Ожидание лавки"
                        subtitle = u8"Откройте диалоговое окно лавки"
                        is_waiting = true
                    elseif RunState.selling.stage == 'waiting_cef' then
                        title = u8"Загрузка инвентаря"
                        subtitle = u8"Ожидание интерфейса лавки..."
                    elseif RunState.selling.stage == 'waiting_input' or RunState.selling.stage == 'next_item' then
                        title = u8"Выставление товаров"
                        local cur_name = RunState.selling.current_item and u8(RunState.selling.current_item.name) or u8"Товар"
                        subtitle = string.format(u8"Товар (%d из %d):\n%s", RunState.selling.current_idx, RunState.selling.total, cur_name)
                    elseif RunState.selling.stage == 'closing' then
                        title = u8"Завершение"
                        subtitle = u8"Закрываем окна..."
                    end
                elseif RunState.buying.active then
                    icon = fa('cart_arrow_down')
                    items_count = RunState.buying.total
                    if RunState.buying.stage == 'waiting_dialog' then
                        title = u8"Ожидание лавки"
                        subtitle = u8"Откройте диалоговое окно лавки"
                        is_waiting = true
                    elseif RunState.buying.stage == 'closing' then
                        title = u8"Завершение"
                        subtitle = u8"Закрываем окна..."
                    else
                        title = u8"Скупка товаров"
                        local cur_name = RunState.buying.current_item and u8(RunState.buying.current_item.name) or u8"Товар"
                        subtitle = string.format(u8"Товар (%d из %d):\n%s", RunState.buying.current_idx, RunState.buying.total, cur_name)
                    end
                end

                local bar_margin = 30.0
                local bar_h = 6.0
                local bar_y = p.y + 26.0
                local bar_w = mod_w - bar_margin * 2

                dl:AddRectFilled(imgui.ImVec2(p.x + bar_margin, bar_y), imgui.ImVec2(p.x + bar_margin + bar_w, bar_y + bar_h), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(accent_color.x, accent_color.y, accent_color.z, 0.18)), bar_h/2)

                if is_waiting then
                    local pulse = (math.sin(os.clock() * 4) + 1) * 0.5
                    local seg_w = bar_w * 0.32
                    local seg_x = p.x + bar_margin + (bar_w - seg_w) * pulse
                    dl:AddRectFilled(imgui.ImVec2(seg_x, bar_y), imgui.ImVec2(seg_x + seg_w, bar_y + bar_h), imgui.ColorConvertFloat4ToU32(accent_color), bar_h/2)
                else
                    local t = (os.clock() * 0.6) % 1.0
                    local seg_w = bar_w * 0.4
                    local seg_x = p.x + bar_margin + (bar_w - seg_w) * t
                    dl:AddRectFilled(imgui.ImVec2(seg_x, bar_y), imgui.ImVec2(seg_x + seg_w, bar_y + bar_h), imgui.ColorConvertFloat4ToU32(accent_color), bar_h/2)
                end

                imgui.PushFont(fnt_main)

                local function drawCentered(text, y, col)
                    for line in text:gmatch("[^\r\n]+") do
                        local sz = imgui.CalcTextSize(line)
                        imgui.SetCursorScreenPos(imgui.ImVec2(p.x + (mod_w - sz.x)/2, y))
                        imgui.TextColored(col, line)
                        y = y + imgui.GetFontSize() + 6
                    end
                    return y
                end

                local title_y = drawCentered(title, bar_y + bar_h + 34, Palette.text_primary)
                local sub_y = drawCentered(subtitle, title_y + 6, Palette.text_secondary)
                
                if items_count > 0 then
                    local badge_txt = u8"Найдено товаров: " .. items_count
                    local bsz = imgui.CalcTextSize(badge_txt)
                    local bx = p.x + (mod_w - (bsz.x + 24))/2
                    local by = sub_y + 10
                    dl:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx + bsz.x + 24, by + bsz.y + 12), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(accent_color.x, accent_color.y, accent_color.z, 0.2)), 8.0)
                    dl:AddText(imgui.ImVec2(bx + 12, by + 6), imgui.ColorConvertFloat4ToU32(accent_color), badge_txt)
                end
                
                imgui.PopFont()

                local btn_h = 45.0
                local btn_w = mod_w - 40.0
                local btn_y = p.y + mod_h - btn_h - 20.0
                local btn_x = p.x + 20.0

                imgui.SetCursorScreenPos(imgui.ImVec2(btn_x, btn_y))
                if imgui.InvisibleButton("##cancel_scan", imgui.ImVec2(btn_w, btn_h)) then
                    if RunState.inventory_scan.active then RunState.inventory_scan.active = false end
                    if RunState.buying_scan.active then stopBuyingScan() end
                    if RunState.buying.active then RunState.buying.active = false end
                    menu_open[0] = true
                end

                local btn_active = imgui.IsItemActive()
                local c_bg = btn_active and imgui.ImVec4(Palette.accent_danger.x*0.8, Palette.accent_danger.y*0.8, Palette.accent_danger.z*0.8, 1) or Palette.bg_main
                
                dl:AddRectFilled(imgui.ImVec2(btn_x, btn_y), imgui.ImVec2(btn_x + btn_w, btn_y + btn_h), imgui.ColorConvertFloat4ToU32(c_bg), 12.0)
                dl:AddRect(imgui.ImVec2(btn_x, btn_y), imgui.ImVec2(btn_x + btn_w, btn_y + btn_h), imgui.ColorConvertFloat4ToU32(Palette.accent_danger), 12.0, 15, 1.5)

                imgui.PushFont(fnt_main)
                local c_txt = u8"Остоновить Сканирование"
                local csz = imgui.CalcTextSize(c_txt)
                dl:AddText(imgui.ImVec2(btn_x + (btn_w - csz.x)/2, btn_y + (btn_h - csz.y)/2), imgui.ColorConvertFloat4ToU32(Palette.accent_danger), c_txt)
                imgui.PopFont()
            end
            imgui.End()
            imgui.PopStyleVar(2)
            imgui.PopStyleColor(2)
            if not menu_open[0] then return end
        end

        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menu_alpha)
        local fixed_w = sw * (tonumber(Prefs.win_w) or 92) / 100
        local fixed_h = sh * (tonumber(Prefs.win_h) or 88) / 100
        if CM_WinCenterX == nil then CM_WinCenterX, CM_WinCenterY = sw / 2, sh / 2 end
        imgui.SetNextWindowPos(imgui.ImVec2(CM_WinCenterX, CM_WinCenterY), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(fixed_w, fixed_h), imgui.Cond.Always)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar

        imgui.PushStyleColor(imgui.Col.WindowBg, Palette.bg_main)
        imgui.PushStyleColor(imgui.Col.FrameBg, Palette.bg_tertiary)
        imgui.PushStyleColor(imgui.Col.Button, Palette.bg_tertiary)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.30, 0.30, 0.30, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.40, 0.40, 0.40, 1.0))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.06, 0.06, 0.06, 1.0))
        imgui.PushStyleColor(imgui.Col.Text, Palette.text_primary)

        if imgui.Begin("CentralMarketMobile", menu_open, flags) then
            imgui.PushFont(fnt_main)

            local window_width = imgui.GetWindowWidth()

            imgui.SetCursorPos(imgui.ImVec2(0, 0))
            imgui.InvisibleButton("##cm_drag_handle", imgui.ImVec2(window_width - 62, 60))
            if imgui.IsItemActive() and imgui.IsMouseDragging(0) then
                local mdelta = imgui.GetIO().MouseDelta
                CM_WinCenterX = CM_WinCenterX + mdelta.x
                CM_WinCenterY = CM_WinCenterY + mdelta.y
            end

            imgui.SetCursorPosX(window_width - 62)
            imgui.SetCursorPosY(8)
            if imgui.Button("X##close_main", imgui.ImVec2(52, 52)) then
                menu_open[0] = false
            end

            local title_text = "Central Market"
            local title_w = imgui.CalcTextSize(title_text).x
            imgui.SetCursorPosX((window_width - title_w) / 2)
            imgui.SetCursorPosY(10)
            imgui.Text(title_text)
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            local tab_btn_w = (window_width - 40) / 4
            local prev_tab_col = current_tab == 2
            if prev_tab_col then imgui.PushStyleColor(imgui.Col.Button, Palette.accent_primary) end
            if imgui.Button(u8"Скупка", imgui.ImVec2(tab_btn_w, 58)) then current_tab = 2 end
            if prev_tab_col then imgui.PopStyleColor() end
            imgui.SameLine()
            local is_sell_tab = current_tab == 1
            if is_sell_tab then imgui.PushStyleColor(imgui.Col.Button, Palette.accent_success) end
            if imgui.Button(u8"Продажа", imgui.ImVec2(tab_btn_w, 58)) then current_tab = 1 end
            if is_sell_tab then imgui.PopStyleColor() end
            imgui.SameLine()
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.62, 0.86, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.22, 0.70, 0.95, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.10, 0.50, 0.72, 1.0))
            if imgui.Button(u8"Telegram", imgui.ImVec2(tab_btn_w, 58)) then
                local tg_url = "https://t.me/edward_scripts"

                local opened = pcall(function()
                    local env = require("android.jnienv")
                    local urlStr = env.NewStringUTF(tg_url)
                    local uri = androidEnvUtil.CallStaticObjectMethod("android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;", urlStr)
                    local actionView = androidEnvUtil.GetStaticObjectField("android/content/Intent", "ACTION_VIEW", "Ljava/lang/String;")
                    local intent = androidEnvUtil.CallConstructor("android/content/Intent", "(Ljava/lang/String;Landroid/net/Uri;)V", actionView, uri)
                    androidEnvUtil.CallVoidMethod(require("android.jni-raw").activity, "startActivity", "(Landroid/content/Intent;)V", intent)
                end)

                if opened then
                    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Открываю Telegram...", -1)
                else
                    if type(setClipboardText) == "function" then
                        pcall(setClipboardText, tg_url)
                    end
                    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Telegram: {00FFFF}" .. tg_url, -1)
                    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Ссылка скопирована в буфер обмена, вставьте её в браузер/Telegram", -1)
                end
            end
            imgui.PopStyleColor(3)
            imgui.SameLine()
            local is_settings_tab = current_tab == 3
            if is_settings_tab then imgui.PushStyleColor(imgui.Col.Button, Palette.accent_primary) end
            if imgui.Button(u8"Настройки", imgui.ImVec2(tab_btn_w, 58)) then current_tab = 3 end
            if is_settings_tab then imgui.PopStyleColor() end
            imgui.Separator()

            if current_tab == 1 or current_tab == 2 then
                local is_sell = (current_tab == 1)
                local source_items = is_sell and stock_items or catalog_items
                local target_config = is_sell and sell_cfg or buy_cfg
                local cfg_path = is_sell and FILE_CFG_SELL or FILE_CFG_BUY

                if imgui.Button(u8"Обновить список", imgui.ImVec2(560, 52)) then
                    if is_sell then
                        menu_open[0] = false
                        startInventoryScan()
                    else
                        RunState.buying_scan = {active=true, stage='waiting_dialog', current_page=1, all_items={}, current_dialog_id=nil}
                        watchShopProximity(function() return RunState.buying_scan end)
                        if lastSeenInteractPromptId then sendMarketInteract(lastSeenInteractPromptId) end
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Подойдите к лавке и нажмите кнопку взаимодействия!", -1)
                        menu_open[0] = false
                    end
                end
                imgui.SameLine()
                imgui.Dummy(imgui.ImVec2(10, 0))
                imgui.SameLine()

                local is_running
                if is_sell then is_running = RunState.selling.active else is_running = RunState.buying.active end
                if is_running then
                    if imgui.Button(u8"Стоп", imgui.ImVec2(300, 52)) then
                        if is_sell then RunState.selling.active = false else RunState.buying.active = false end
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Остановлено пользователем!", -1)
                    end
                else
                    local btn_label = is_sell and u8"Выставить" or u8"Начать скупку"
                    if imgui.Button(btn_label, imgui.ImVec2(300, 52)) then
                        if #target_config == 0 then
                            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Список пуст!", -1)
                        else
                            if is_sell then
                                RunState.selling = { active = true, stage = 'waiting_dialog', current_idx = 1, total = #sell_cfg, current_item = nil }
                                watchShopProximity(function() return RunState.selling end)
                                if lastSeenInteractPromptId then sendMarketInteract(lastSeenInteractPromptId) end
                                sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Откройте лавку для автоматической продажи!", -1)
                            else
                                RunState.buying = { active = true, stage = 'waiting_dialog', current_idx = 1, total = #buy_cfg, current_item = nil }
                                watchShopProximity(function() return RunState.buying end)
                                if lastSeenInteractPromptId then sendMarketInteract(lastSeenInteractPromptId) end
                                sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Откройте лавку для автоматической скупки!", -1)
                            end
                            menu_open[0] = false
                        end
                    end
                end

                if not is_sell then
                    imgui.SameLine()
                    if imgui.Button(u8"Конфиги##openbuyconfigs", imgui.ImVec2(180, 52)) then
                        buy_config_modal_open[0] = true
                    end
                end

                local search_buf = is_sell and filter_buf_sell or filter_buf_buy
                imgui.PushItemWidth(420)
                imgui.InputTextWithHint("##search_left", u8"Введите название товара для поиска...", search_buf, 256)
                imgui.PopItemWidth()
                imgui.SameLine()
                if imgui.Button("X##clear_left", imgui.ImVec2(40, 40)) then
                    ffi.fill(search_buf, ffi.sizeof(search_buf))
                end
                imgui.SameLine()
                imgui.Dummy(imgui.ImVec2(10, 0))
                imgui.SameLine()

                local target_search_buf = is_sell and target_filter_sell or target_filter_buy
                imgui.PushItemWidth(460)
                local right_hint = is_sell and u8"Поиск в списке на продажу..." or u8"Поиск в списке скупки..."
                imgui.InputTextWithHint("##search_right", right_hint, target_search_buf, 128)
                imgui.PopItemWidth()
                imgui.SameLine()
                if imgui.Button(u8"X##clear_right", imgui.ImVec2(40, 40)) then
                    ffi.fill(target_search_buf, ffi.sizeof(target_search_buf))
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                imgui.Columns(2, "TradeColumnsFB", false)
                imgui.SetColumnWidth(0, 630)
                local list_area_h = math.max(300, imgui.GetContentRegionAvail().y - 10)
                imgui.Text(u8"Доступные товары:")
                local left_child_id = is_sell and "LeftListFB_sell" or "LeftListFB_buy"
                if imgui.BeginChild(left_child_id, imgui.ImVec2(610, list_area_h), true) then
                    local wheel = imgui.GetIO().MouseWheel
                    if wheel ~= 0 and imgui.IsWindowHovered() then imgui.SetScrollY(imgui.GetScrollY() - wheel * 45) end
                    local mp_l = imgui.GetIO().MousePos
                    if imgui.IsMouseDown(0) and (imgui.IsWindowHovered() or drag_scroll.left_down) then
                        if drag_scroll.left_down then
                            imgui.SetScrollY(imgui.GetScrollY() - (mp_l.y - drag_scroll.left_y))
                        end
                        drag_scroll.left_down = true
                        drag_scroll.left_y = mp_l.y
                    else
                        drag_scroll.left_down = false
                    end
                    local search_text = toLowerRu(u8:decode(ffi.string(search_buf)))
                    local ui_cache = is_sell and list_cache_sell or list_cache_buy

                    local filtered
                    if ui_cache.query == search_text and ui_cache.source == source_items then
                        filtered = ui_cache.items
                    else
                        filtered = {}
                        for i, item in ipairs(source_items) do
                            local nm = item.name or ""
                            if search_text == "" or toLowerRu(nm):find(search_text, 1, true) then
                                filtered[#filtered + 1] = { idx = i, item = item, name = nm }
                            end
                        end
                        ui_cache.query = search_text
                        ui_cache.source = source_items
                        ui_cache.items = filtered
                    end

                    local total_f = #filtered
                    if total_f > 0 then
                        local row_h = imgui.GetTextLineHeightWithSpacing() + 4
                        local scroll_y = imgui.GetScrollY()
                        local view_h = list_area_h
                        local first = math.max(1, math.floor(scroll_y / row_h) - 3)
                        local last = math.min(total_f, math.ceil((scroll_y + view_h) / row_h) + 3)

                        if first > 1 then imgui.Dummy(imgui.ImVec2(1, (first - 1) * row_h)) end

                        for fi = first, last do
                            local f = filtered[fi]
                            local item = f.item
                            local i = f.idx
                            local disp = f.name
                            if item.amount then disp = disp .. " [В наличии: " .. item.amount .. "]" end

                            local already_added = false
                            for _, v in ipairs(target_config) do
                                if v.name == item.name then already_added = true break end
                            end

                            if already_added then imgui.PushStyleColor(imgui.Col.Text, Palette.text_secondary) end
                            if imgui.Selectable(u8(disp) .. "##srcfb" .. i, false) then
                                if not already_added then
                                    table.insert(target_config, {
                                        name = item.name,
                                        model_id = item.model_id or item.index,
                                        amount = item.max_amount or 1,
                                        max_amount = item.max_amount,
                                        price = 1000,
                                        use_max = false
                                    })
                                    writeJsonToDisk(cfg_path, target_config)
                                    if is_sell then qty_bufs_sell = {} cost_bufs_sell = {} else qty_bufs_buy = {} cost_bufs_buy = {} end
                                end
                            end
                            if already_added then imgui.PopStyleColor() end
                        end

                        if last < total_f then imgui.Dummy(imgui.ImVec2(1, (total_f - last) * row_h)) end
                    else
                        imgui.TextColored(Palette.text_secondary, u8"Список пуст. Нажмите 'Обновить список'")
                    end
                end
                imgui.EndChild()

                imgui.NextColumn()
                imgui.Text(is_sell and u8"Список для продажи:" or u8"Список для скупки:")
                if is_sell then
                    imgui.SameLine()
                    if imgui.Button(u8"Добавить всё##addall", imgui.ImVec2(200, 36)) then
                        for _, item in ipairs(source_items) do
                            local already_added = false
                            for _, v in ipairs(target_config) do
                                if v.name == item.name then already_added = true break end
                            end
                            if not already_added then
                                table.insert(target_config, {
                                    name = item.name,
                                    model_id = item.model_id or item.index,
                                    amount = item.max_amount or 1,
                                    max_amount = item.max_amount,
                                    price = 1000,
                                    use_max = false
                                })
                            end
                        end
                        writeJsonToDisk(cfg_path, target_config)
                        qty_bufs_sell = {} cost_bufs_sell = {}
                    end
                end
                imgui.SameLine()
                if imgui.Button(u8"Очистить всё##clearall", imgui.ImVec2(200, 36)) then
                    for k in pairs(target_config) do target_config[k] = nil end
                    writeJsonToDisk(cfg_path, target_config)
                    if is_sell then qty_bufs_sell = {} cost_bufs_sell = {} else qty_bufs_buy = {} cost_bufs_buy = {} end
                end
                local right_child_id = is_sell and "RightListFB_sell" or "RightListFB_buy"
                local avail_r = imgui.GetContentRegionAvail()
                local right_child_w = math.max(740, avail_r.x - 8)
                if imgui.BeginChild(right_child_id, imgui.ImVec2(right_child_w, list_area_h), true) then
                    local wheel_r = imgui.GetIO().MouseWheel
                    if wheel_r ~= 0 and imgui.IsWindowHovered() then imgui.SetScrollY(imgui.GetScrollY() - wheel_r * 45) end
                    local mp_r = imgui.GetIO().MousePos
                    if imgui.IsMouseDown(0) and (imgui.IsWindowHovered() or drag_scroll.right_down) then
                        if drag_scroll.right_down then
                            imgui.SetScrollY(imgui.GetScrollY() - (mp_r.y - drag_scroll.right_y))
                        end
                        drag_scroll.right_down = true
                        drag_scroll.right_y = mp_r.y
                    else
                        drag_scroll.right_down = false
                    end
                    local tsearch = toLowerRu(u8:decode(ffi.string(target_search_buf)))
                    local remove_idx = nil
                    local amt_bufs = is_sell and qty_bufs_sell or qty_bufs_buy
                    local price_bufs = is_sell and cost_bufs_sell or cost_bufs_buy

                    local content_w = imgui.GetContentRegionAvail().x
                    local BTN_W, AMT_W, PRICE_W, M_W = 44, 80, 160, 40
                    local GAP, RIGHT_MARGIN = 16, 24
                    local COL_BTN_X   = content_w - RIGHT_MARGIN - BTN_W
                    local COL_UNIT2_X = COL_BTN_X - GAP - 34
                    local COL_PRICE_X = COL_UNIT2_X - GAP - PRICE_W
                    local COL_UNIT1_X = COL_PRICE_X - GAP - 30
                    local COL_AMT_X   = COL_UNIT1_X - GAP - AMT_W
                    local COL_M_X     = is_sell and (COL_AMT_X - GAP - M_W) or COL_AMT_X
                    local COL_NAME_W  = math.max(180, COL_M_X - GAP)


                    local function fitRowName(raw_name)
                        local full_u8 = u8(raw_name)
                        if imgui.CalcTextSize(full_u8).x <= COL_NAME_W then return full_u8 end
                        local cut = #raw_name
                        local result = full_u8
                        while cut > 0 do
                            cut = cut - 1
                            local candidate_u8 = u8(raw_name:sub(1, cut) .. "...")
                            if imgui.CalcTextSize(candidate_u8).x <= COL_NAME_W then
                                result = candidate_u8
                                break
                            end
                        end
                        return result
                    end

                    if is_sell then
                        imgui.SetCursorPosX(COL_M_X)
                        imgui.TextColored(Palette.text_secondary, u8"")
                    end
                    imgui.SetCursorPosX(COL_AMT_X)
                    imgui.TextColored(Palette.text_secondary, u8"Кол-во")
                    imgui.SameLine(COL_PRICE_X)
                    imgui.TextColored(Palette.text_secondary, u8"Цена")
                    imgui.Separator()

                    for i, item in ipairs(target_config) do
                        if tsearch == "" or toLowerRu(item.name):find(tsearch, 1, true) then
                            local row_id = "fbrow" .. tostring(is_sell) .. i

                            imgui.Text(fitRowName(string.format("%d. %s", i, item.name)))

                            if is_sell then
                                imgui.SameLine(COL_M_X)
                                local m_on = item.use_max == true
                                if m_on then imgui.PushStyleColor(imgui.Col.Button, Palette.accent_success) end
                                if imgui.Button(u8"M##max" .. row_id, imgui.ImVec2(M_W, 40)) then
                                    item.use_max = not m_on
                                    writeJsonToDisk(cfg_path, target_config)
                                end
                                if m_on then imgui.PopStyleColor() end
                            end

                            if not amt_bufs[i] then amt_bufs[i] = ffi.new('char[16]', tostring(item.amount or 1)) end
                            imgui.SameLine(COL_AMT_X)
                            imgui.PushItemWidth(AMT_W)
                            if imgui.InputText("##amt" .. row_id, amt_bufs[i], 16, imgui.InputTextFlags.CharsDecimal) then
                                item.amount = tonumber(ffi.string(amt_bufs[i])) or item.amount
                                writeJsonToDisk(cfg_path, target_config)
                            end
                            imgui.PopItemWidth()
                            imgui.SameLine(COL_UNIT1_X)
                            imgui.Text(u8"шт")

                            if not price_bufs[i] then price_bufs[i] = ffi.new('char[16]', tostring(item.price or 0)) end
                            imgui.SameLine(COL_PRICE_X)
                            imgui.PushItemWidth(PRICE_W)
                            if imgui.InputText("##price" .. row_id, price_bufs[i], 16, imgui.InputTextFlags.CharsDecimal) then
                                item.price = tonumber(ffi.string(price_bufs[i])) or item.price
                                writeJsonToDisk(cfg_path, target_config)
                            end
                            imgui.PopItemWidth()
                            imgui.SameLine(COL_UNIT2_X)
                            imgui.Text(u8"руб")

                            imgui.SameLine(COL_BTN_X)
                            if imgui.Button(u8"X##rm" .. row_id, imgui.ImVec2(BTN_W, 40)) then
                                remove_idx = i
                            end
                            imgui.Separator()
                        end
                    end
                    if remove_idx then
                        table.remove(target_config, remove_idx)
                        if is_sell then qty_bufs_sell = {} cost_bufs_sell = {} else qty_bufs_buy = {} cost_bufs_buy = {} end
                        writeJsonToDisk(cfg_path, target_config)
                    end
                    if #target_config == 0 then
                        imgui.TextColored(Palette.text_secondary, u8"Список пуст. Добавьте товары из левого списка")
                    end
                end
                imgui.EndChild()
                imgui.Columns(1)

            elseif current_tab == 3 then
                local settings_child_h = imgui.GetContentRegionAvail().y - 60
                if settings_child_h < 100 then settings_child_h = 100 end
                imgui.BeginChild("##SettingsScroll", imgui.ImVec2(0, settings_child_h), false)

                local settings_wheel = imgui.GetIO().MouseWheel
                if settings_wheel ~= 0 and imgui.IsWindowHovered() then imgui.SetScrollY(imgui.GetScrollY() - settings_wheel * 45) end
                local mp_s = imgui.GetIO().MousePos
                if imgui.IsMouseDown(0) and (imgui.IsWindowHovered() or drag_scroll.settings_down) then
                    if drag_scroll.settings_down then
                        imgui.SetScrollY(imgui.GetScrollY() - (mp_s.y - drag_scroll.settings_y))
                    end
                    drag_scroll.settings_down = true
                    drag_scroll.settings_y = mp_s.y
                else
                    drag_scroll.settings_down = false
                end

                imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(10.0, 10.0))
                imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(10.0, 15.0))
                imgui.Spacing()

                imgui.TextColored(Palette.accent_primary, u8"Автоматизация имени")
                if imgui.Checkbox(u8"Авто-выставление названия лавки##fbautoname", b_auto_name) then
                    Prefs.auto_name = b_auto_name[0]
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                end
                imgui.Spacing()

                imgui.TextColored(Palette.text_secondary, u8"Название вашей лавки:")
                imgui.PushItemWidth(520)
                if imgui.InputText("##shopnamefb", buf_shop_name, 64) then
                    Prefs.shop_name = ffi.string(buf_shop_name)
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                end
                imgui.PopItemWidth()

                imgui.Dummy(imgui.ImVec2(0, 10))
                imgui.Separator()
                imgui.Spacing()

                imgui.TextColored(Palette.accent_primary, u8"Размер окна и шрифт")
                imgui.Spacing()
                imgui.TextColored(Palette.text_secondary, u8"Применяется после отпускания ползунка")
                imgui.Spacing()

                SZ.slider(u8"Ширина окна", "##winwfb", SZ.w, 50, 100, u8"%d %%", "win_w")
                SZ.slider(u8"Высота окна", "##winhfb", SZ.h, 50, 100, u8"%d %%", "win_h")
                SZ.slider(u8"Размер шрифта", "##fontfb", SZ.f, 70, 140, u8"%d %%", "font_pct")

                if imgui.Button(u8"Сбросить размеры и шрифт", imgui.ImVec2(520, 52)) then
                    Prefs.win_w, Prefs.win_h, Prefs.font_pct = 92, 88, 100
                    SZ.w[0], SZ.h[0], SZ.f[0] = 92, 88, 100
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                end

                imgui.Dummy(imgui.ImVec2(0, 10))
                imgui.Separator()
                imgui.Spacing()

                imgui.TextColored(Palette.accent_primary, u8"Задержки / Скорость")
                imgui.Spacing()

                imgui.TextColored(Palette.text_secondary, u8"КД между диалогами (скупка): чем меньше, тем быстрее")
                imgui.PushItemWidth(520)
                imgui.SliderInt("##dialogdelayfb", i_dialog_delay, 0, 2000, u8"%d мс")
                imgui.PopItemWidth()
                if i_dialog_delay[0] < 0 then i_dialog_delay[0] = 0 end
                imgui.Spacing()

                imgui.TextColored(Palette.text_secondary, u8"Задержка выставления через CEF (продажа): чем ниже, тем быстрее")
                imgui.PushItemWidth(520)
                imgui.SliderInt("##cefdelayfb", i_cef_delay, 200, 5000, u8"%d мс")
                imgui.PopItemWidth()
                if i_cef_delay[0] < 100 then i_cef_delay[0] = 100 end

                imgui.PopStyleVar(2)

                imgui.Dummy(imgui.ImVec2(0, 10))
                imgui.Separator()
                imgui.Spacing()

                imgui.TextColored(Palette.accent_primary, u8"Плавающая кнопка Central Market")
                imgui.Spacing()

                if imgui.Checkbox(u8"Показывать кнопку на экране##fbshowfloat", b_show_float_button) then
                    Prefs.show_float_button = b_show_float_button[0]
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                end

                if imgui.Checkbox(u8"Показывать кнопку даже при открытом меню##fbalwaysvis", b_float_always_visible) then
                    Prefs.float_btn_always_visible = b_float_always_visible[0]
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                end

                imgui.Spacing()
                if imgui.Checkbox(u8"Режим перемещения кнопки (потяните кнопку)##fbmovemode", b_float_btn_move_mode) then
                    if not b_float_btn_move_mode[0] then
                        writeJsonToDisk(FILE_SETTINGS, Prefs)
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Позиция кнопки сохранена!", -1)
                    end
                end

                imgui.Spacing()
                local settings_btn_w = (imgui.GetContentRegionAvail().x - 10) / 2
                if imgui.Button(u8"Сбросить позицию кнопки", imgui.ImVec2(settings_btn_w, 52)) then
                    Prefs.float_btn_x = FLOAT_BTN_DEFAULT_X
                    Prefs.float_btn_y = FLOAT_BTN_DEFAULT_Y
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                end
                imgui.SameLine()
                imgui.Dummy(imgui.ImVec2(10, 0))
                imgui.SameLine()
                if imgui.Button(u8"Сохранить настройки", imgui.ImVec2(settings_btn_w, 52)) then
                    Prefs.auto_name = b_auto_name[0]
                    Prefs.shop_name = ffi.string(buf_shop_name)
                    Prefs.dialog_delay = i_dialog_delay[0]
                    Prefs.cef_delay = i_cef_delay[0]
                    Prefs.show_float_button = b_show_float_button[0]
                    Prefs.float_btn_always_visible = b_float_always_visible[0]
                    writeJsonToDisk(FILE_SETTINGS, Prefs)
                    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Настройки успешно сохранены!", -1)
                end

                imgui.Dummy(imgui.ImVec2(0, 15))
                imgui.EndChild()

            end

            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.90, 0.10, 0.10, 1.0), "By ")
            imgui.SameLine(nil, 0)
            imgui.TextColored(imgui.ImVec4(0.00, 1.00, 1.00, 1.0), "Edward")

            if current_tab == 1 or current_tab == 2 then
                local is_sell_footer = (current_tab == 1)
                local target_footer = is_sell_footer and sell_cfg or buy_cfg
                local total = 0
                for _, v in ipairs(target_footer) do
                    total = total + (tonumber(v.price) or 0) * (tonumber(v.amount) or 0)
                end
                local footer_text = string.format(is_sell_footer and "Общая сумма продажи: %s руб" or "Общая сумма скупки: %s руб", formatCash(total))
                local ftw = imgui.CalcTextSize(u8(footer_text)).x
                imgui.SameLine()
                imgui.SetCursorPosX(window_width - ftw - 10)
                imgui.TextColored(is_sell_footer and Palette.accent_success or Palette.accent_primary, u8(footer_text))
            end

            imgui.PopFont()
        end
        imgui.End()
        imgui.PopStyleColor(7)
        imgui.PopStyleVar()

        if buy_config_modal_open[0] and menu_open[0] then
            local modal_w = math.min(sw * 0.55, 700)
            local modal_h = math.min(sh * 0.75, 680)
            if CM_ConfigCenterX == nil then CM_ConfigCenterX, CM_ConfigCenterY = sw / 2, sh / 2 end
            imgui.SetNextWindowPos(imgui.ImVec2(CM_ConfigCenterX, CM_ConfigCenterY), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
            imgui.SetNextWindowSize(imgui.ImVec2(modal_w, modal_h), imgui.Cond.Always)
            imgui.SetNextWindowFocus()
            imgui.PushStyleColor(imgui.Col.WindowBg, Palette.bg_main)
            imgui.PushStyleColor(imgui.Col.Text, Palette.text_primary)
            imgui.PushStyleColor(imgui.Col.Border, Palette.accent_primary)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1.5)
            local modal_flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
            if imgui.Begin(u8"Конфиги скупки", buy_config_modal_open, modal_flags) then
                local modal_win_w = imgui.GetWindowWidth()

                imgui.SetCursorPos(imgui.ImVec2(0, 0))
                imgui.InvisibleButton("##cfg_drag_handle", imgui.ImVec2(modal_win_w - 54, 46))
                if imgui.IsItemActive() and imgui.IsMouseDragging(0) then
                    local mdelta = imgui.GetIO().MouseDelta
                    CM_ConfigCenterX = CM_ConfigCenterX + mdelta.x
                    CM_ConfigCenterY = CM_ConfigCenterY + mdelta.y
                end

                imgui.SetCursorPosX(modal_win_w - 50)
                imgui.SetCursorPosY(6)
                if imgui.Button("X##close_buyconfigs", imgui.ImVec2(40, 40)) then
                    buy_config_modal_open[0] = false
                    ffi.fill(buy_profile_name_buf, ffi.sizeof(buy_profile_name_buf))
                end
                local modal_title = u8"Конфиги скупки"
                local modal_title_w = imgui.CalcTextSize(modal_title).x
                imgui.SetCursorPosX((modal_win_w - modal_title_w) / 2)
                imgui.SetCursorPosY(10)
                imgui.TextColored(Palette.accent_primary, modal_title)
                imgui.Dummy(imgui.ImVec2(0, 10))
                imgui.Separator()
                imgui.Spacing()

                imgui.TextColored(Palette.accent_primary, u8"Сохранить текущий список скупки как:")
                imgui.PushItemWidth(-140)
                imgui.InputTextWithHint("##newprofilename", u8"Название нового профиля...", buy_profile_name_buf, 64)
                imgui.PopItemWidth()
                imgui.SameLine()
                if imgui.Button(u8"Сохранить", imgui.ImVec2(120, 40)) then
                    local pname = ffi.string(buy_profile_name_buf)
                    if pname ~= "" then
                        local ok, copy = pcall(cjson.decode, cjson.encode(buy_cfg))
                        if ok then
                            buy_profiles[pname] = copy
                            writeJsonToDisk(FILE_BUY_PROFILES, buy_profiles)
                            selected_buy_profile = pname
                            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Профиль сохранён: " .. u8:decode(pname), -1)
                        end
                    end
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()
                imgui.TextColored(Palette.accent_primary, u8"Сохранённые профили:")
                imgui.Spacing()

                local profile_names = {}
                for name in pairs(buy_profiles) do table.insert(profile_names, name) end
                table.sort(profile_names)

                imgui.BeginChild("##BuyProfilesList", imgui.ImVec2(-1, -60), true)
                if #profile_names == 0 then
                    imgui.TextColored(Palette.text_secondary, u8"Пока нет сохранённых профилей")
                end
                for _, pname in ipairs(profile_names) do
                    local is_sel = (pname == selected_buy_profile)
                    if is_sel then imgui.PushStyleColor(imgui.Col.Header, Palette.accent_primary) end
                    if imgui.Selectable(pname .. "##profsel", is_sel, nil, imgui.ImVec2(0, 34)) then
                        selected_buy_profile = pname
                    end
                    if is_sel then imgui.PopStyleColor() end
                end
                imgui.EndChild()

                imgui.Spacing()

                local modal_btn_w = (imgui.GetContentRegionAvail().x - 10) / 2
                if imgui.Button(u8"Загрузить##loadprofile", imgui.ImVec2(modal_btn_w, 44)) then
                    if selected_buy_profile and buy_profiles[selected_buy_profile] then
                        local ok, copy = pcall(cjson.decode, cjson.encode(buy_profiles[selected_buy_profile]))
                        if ok and type(copy) == "table" then
                            for k in pairs(buy_cfg) do buy_cfg[k] = nil end
                            for i, v in ipairs(copy) do buy_cfg[i] = v end
                            writeJsonToDisk(FILE_CFG_BUY, buy_cfg)
                            qty_bufs_buy = {}
                            cost_bufs_buy = {}
                            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Профиль загружен: " .. u8:decode(selected_buy_profile), -1)
                        end
                    end
                end
                imgui.SameLine()
                if imgui.Button(u8"Удалить##delprofile", imgui.ImVec2(modal_btn_w, 44)) then
                    if selected_buy_profile then
                        buy_profiles[selected_buy_profile] = nil
                        writeJsonToDisk(FILE_BUY_PROFILES, buy_profiles)
                        selected_buy_profile = nil
                    end
                end
            end
            imgui.End()
            imgui.PopStyleVar()
            imgui.PopStyleColor(3)
        end
    end
)

function ToggleMenu()
    menu_open[0] = not menu_open[0]
    if menu_open[0] then
        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Меню открыто!", -1)
    end
end

imgui.OnFrame(
    function()
        return Prefs.show_float_button and (not menu_open[0] or Prefs.float_btn_always_visible) and not RunState.inventory_scan.active and not RunState.buying_scan.active and not RunState.selling.active and not RunState.buying.active
    end,
    function(this)
        local sw, sh = getScreenResolution()

        local pos_x = Prefs.float_btn_x * sw
        local pos_y = Prefs.float_btn_y * sh

        imgui.SetNextWindowPos(imgui.ImVec2(pos_x, pos_y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(FLOAT_BTN_W, FLOAT_BTN_H), imgui.Cond.Always)

        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar +
                      imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoMove +
                      imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoNav

        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))

        if imgui.Begin("##CMFloatButton", nil, flags) then
            local p = imgui.GetCursorScreenPos()
            local dl = imgui.GetWindowDrawList()

            local gold_top       = imgui.ImVec4(1.00, 0.87, 0.35, 1.00)
            local gold_bottom    = imgui.ImVec4(0.85, 0.62, 0.02, 1.00)
            local gold_top_hov   = imgui.ImVec4(1.00, 0.92, 0.50, 1.00)
            local gold_bottom_hov= imgui.ImVec4(0.95, 0.70, 0.05, 1.00)
            local gold_top_act   = imgui.ImVec4(0.80, 0.60, 0.05, 1.00)
            local gold_bottom_act= imgui.ImVec4(0.65, 0.47, 0.00, 1.00)
            local border_dark    = imgui.ImVec4(0.45, 0.30, 0.00, 1.00)
            local shine          = imgui.ImVec4(1.00, 1.00, 1.00, 0.35)
            local text_outline   = imgui.ImVec4(0.30, 0.16, 0.00, 1.00)

            imgui.InvisibleButton("##cm_float_btn", imgui.ImVec2(FLOAT_BTN_W, FLOAT_BTN_H))
            local hovered = imgui.IsItemHovered()
            local active = imgui.IsItemActive()

            if b_float_btn_move_mode[0] and active then
                local delta = imgui.GetIO().MouseDelta
                if delta.x ~= 0 or delta.y ~= 0 then
                    Prefs.float_btn_x = Prefs.float_btn_x + (delta.x / sw)
                    Prefs.float_btn_y = Prefs.float_btn_y + (delta.y / sh)

                    local max_x = 1.0 - (FLOAT_BTN_W / sw)
                    local max_y = 1.0 - (FLOAT_BTN_H / sh)
                    if Prefs.float_btn_x < 0 then Prefs.float_btn_x = 0 end
                    if Prefs.float_btn_y < 0 then Prefs.float_btn_y = 0 end
                    if Prefs.float_btn_x > max_x then Prefs.float_btn_x = max_x end
                    if Prefs.float_btn_y > max_y then Prefs.float_btn_y = max_y end
                end
            elseif not b_float_btn_move_mode[0] and hovered and imgui.IsMouseReleased(0) then
                ToggleMenu()
            end

            local fill_col
            if active then
                fill_col = gold_bottom_act
            elseif hovered then
                fill_col = gold_top_hov
            else
                fill_col = gold_top
            end

            local rounding = 18.0
            local p_max = imgui.ImVec2(p.x + FLOAT_BTN_W, p.y + FLOAT_BTN_H)

            dl:AddRectFilled(imgui.ImVec2(p.x + 2, p.y + 5), imgui.ImVec2(p_max.x + 2, p_max.y + 6), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0,0,0,0.40)), rounding)

            dl:AddRectFilled(p, p_max, imgui.ColorConvertFloat4ToU32(fill_col), rounding)

            dl:AddRectFilled(imgui.ImVec2(p.x + 3, p.y + FLOAT_BTN_H * 0.55), imgui.ImVec2(p_max.x - 3, p_max.y - 3), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0,0,0,0.12)), rounding * 0.5)

            dl:AddRect(p, p_max, imgui.ColorConvertFloat4ToU32(border_dark), rounding, 15, 2.0)

            dl:AddRectFilled(imgui.ImVec2(p.x + 10, p.y + 4), imgui.ImVec2(p_max.x - 10, p.y + FLOAT_BTN_H * 0.32), imgui.ColorConvertFloat4ToU32(shine), 10.0)

            local function drawOutlinedText(font, text, x, y, col)
                imgui.PushFont(font)
                local ocol = imgui.ColorConvertFloat4ToU32(text_outline)
                dl:AddText(imgui.ImVec2(x - 1, y - 1), ocol, text)
                dl:AddText(imgui.ImVec2(x + 1, y - 1), ocol, text)
                dl:AddText(imgui.ImVec2(x - 1, y + 1), ocol, text)
                dl:AddText(imgui.ImVec2(x + 1, y + 1), ocol, text)
                dl:AddText(imgui.ImVec2(x, y), col, text)
                imgui.PopFont()
            end

            local icon = fa('shop')
            imgui.PushFont(fnt_icons)
            local isz = imgui.CalcTextSize(icon)
            imgui.PopFont()

            imgui.PushFont(fnt_main)
            local label = u8"Central Market"
            local tsz = imgui.CalcTextSize(label)
            imgui.PopFont()

            local gap = 10.0
            local total_w = isz.x + gap + tsz.x
            local start_x = p.x + (FLOAT_BTN_W - total_w) / 2
            local center_y = p.y + FLOAT_BTN_H / 2

            drawOutlinedText(fnt_icons, icon, start_x, center_y - isz.y / 2, 0xFFFFFFFF)
            drawOutlinedText(fnt_main, label, start_x + isz.x + gap, center_y - tsz.y / 2, 0xFFFFFFFF)

            if b_float_btn_move_mode[0] then
                imgui.PushFont(fnt_main)
                local hint = u8"Перетащите кнопку"
                local hsz = imgui.CalcTextSize(hint)
                dl:AddRectFilled(imgui.ImVec2(p.x, p.y - hsz.y - 10), imgui.ImVec2(p.x + hsz.x + 16, p.y - 4), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0,0,0,0.75)), 6.0)
                dl:AddText(imgui.ImVec2(p.x + 8, p.y - hsz.y - 7), imgui.ColorConvertFloat4ToU32(gold_top), hint)
                imgui.PopFont()
            end
        end
        imgui.End()
        imgui.PopStyleVar(2)
    end
)

function main()
    while not isSampAvailable() do wait(100) end
    
    lua_thread.create(function()
        local wait_start = 0
        while true do
            wait(150)
            if RunState.selling.active then
                if RunState.selling.stage == 'waiting_cef_data' then
                    if wait_start == 0 then wait_start = os.clock() end
                    
                    local now = os.clock()
                    if RunState.selling.last_packet_time > 0 and (now - RunState.selling.last_packet_time > 0.5) then
                        RunState.selling.stage = 'running'
                        wait_start = 0
                        processSellingCoroutine()
                    elseif now - wait_start > 10.0 then
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Ошибка: Данные лавки не поступили (таймаут).", -1)
                        RunState.selling.active = false
                        wait_start = 0
                    end
                else
                    wait_start = 0
                end
            else
                wait_start = 0
            end
        end
    end)

    sampRegisterChatCommand('centralmarket', ToggleMenu)
    sampRegisterChatCommand('cm', ToggleMenu)

    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}загружен, {c0c0c0}/cm{FFFFFF} - открыть меню {FF0000}By {00FFFF}Edward", -1)

    while true do
        wait(0)
        

        if menu_open[0] ~= prev_menu_open then
            prev_menu_open = menu_open[0]
            animateMenuFade(menu_open[0])
        end
    end
end
function DrawAccentButton(id, label, w, h, col, icon, dl)
    local p = imgui.GetCursorScreenPos()
    local clicked = false
    if imgui.InvisibleButton(id, imgui.ImVec2(w, h)) then clicked = true end
    local active = imgui.IsItemActive()
    local bg = active and imgui.ImVec4(col.x*0.8, col.y*0.8, col.z*0.8, 1) or col
    dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), imgui.ColorConvertFloat4ToU32(bg), 12.0)
    
    local c_w = 0
    imgui.PushFont(fnt_icons)
    local i_sz = icon and imgui.CalcTextSize(icon) or imgui.ImVec2(0,0)
    imgui.PopFont()
    imgui.PushFont(fnt_main)
    local t_sz = imgui.CalcTextSize(label)
    imgui.PopFont()
    
    if icon then c_w = i_sz.x + 10 + t_sz.x else c_w = t_sz.x end
    local start_x = p.x + (w - c_w) / 2
    
    if icon then
        imgui.PushFont(fnt_icons)
        dl:AddText(imgui.ImVec2(start_x, p.y + (h - i_sz.y)/2), 0xFFFFFFFF, icon)
        imgui.PopFont()
        start_x = start_x + i_sz.x + 10
    end
    imgui.PushFont(fnt_main)
    dl:AddText(imgui.ImVec2(start_x, p.y + (h - t_sz.y)/2), 0xFFFFFFFF, label)
    imgui.PopFont()
    
    return clicked
end

function renderTargetCard(item, is_sell, index, target_table)
    local w = imgui.GetContentRegionAvail().x
    local h = 80.0 
    local p = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()

    imgui.SetCursorScreenPos(p)
    imgui.InvisibleButton("##tgt_"..tostring(is_sell).."_"..index, imgui.ImVec2(w, h))
    local is_active = imgui.IsItemActive()

    if imgui.IsItemHovered() and imgui.IsMouseReleased(0) and not swipe_state.is_dragging then
        edit_modal.active = true
        edit_modal.item = item
        edit_modal.index = index
        edit_modal.is_sell = is_sell
        edit_modal.target_table = target_table
        ffi.copy(edit_modal.buf_price, tostring(item.price))
        ffi.copy(edit_modal.buf_amount, tostring(item.amount or 1))
    end

    local bg_col = is_active and Palette.bg_tertiary or Palette.bg_secondary
    dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), imgui.ColorConvertFloat4ToU32(bg_col), 12.0)
    
    local accent = is_sell and Palette.accent_success or Palette.accent_primary
    dl:AddRectFilled(p, imgui.ImVec2(p.x + 6, p.y + h), imgui.ColorConvertFloat4ToU32(accent), 12.0, 1 + 8)

    imgui.PushFont(fnt_icons)
    local gear_icon = fa('gear')
    local gsz = imgui.CalcTextSize(gear_icon)
    local gear_x = p.x + w - gsz.x - 15.0
    dl:AddText(imgui.ImVec2(gear_x, p.y + (h - gsz.y)/2), imgui.ColorConvertFloat4ToU32(Palette.text_secondary), gear_icon)
    imgui.PopFont()

    local text_x = p.x + 20.0
    imgui.PushFont(fnt_main)
    local name_str = u8(item.name)
    
    dl:PushClipRect(imgui.ImVec2(text_x, p.y), imgui.ImVec2(gear_x - 10, p.y + h), true)
    dl:AddText(imgui.ImVec2(text_x, p.y + 12), imgui.ColorConvertFloat4ToU32(Palette.text_primary), name_str)
    dl:PopClipRect()

    local price_str = formatCash(item.price) .. " $  •  " .. (item.amount or 1) .. " шт."
    dl:AddText(imgui.ImVec2(text_x, p.y + 40), imgui.ColorConvertFloat4ToU32(accent), price_str)
    imgui.PopFont()

    imgui.Dummy(imgui.ImVec2(0, 8))
end

function renderSourceCard(item, is_sell, index, target_table)
    local w = imgui.GetContentRegionAvail().x
    local h = 65.0 
    local p = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()

    local is_added = false
    if is_sell then
        for _, v in ipairs(target_table) do
            if v.name == item.name then is_added = true break end
        end
    end

    imgui.SetCursorScreenPos(p)
    imgui.InvisibleButton("##src_"..tostring(is_sell).."_"..index, imgui.ImVec2(w, h))
    local is_active = imgui.IsItemActive()

    if imgui.IsItemHovered() and imgui.IsMouseReleased(0) and not swipe_state.is_dragging then
        if not is_added then
            table.insert(target_table, {
                name = item.name,
                model_id = item.model_id or item.index,
                amount = item.max_amount or 1, 
                max_amount = item.max_amount,
                price = 1000,
                use_max = false
            })
            if is_sell then writeJsonToDisk(FILE_CFG_SELL, sell_cfg) else writeJsonToDisk(FILE_CFG_BUY, buy_cfg) end
        end
    end

    local bg_col = Palette.bg_main
    local border_col = Palette.border
    if is_added then
        bg_col = imgui.ImVec4(Palette.accent_success.x, Palette.accent_success.y, Palette.accent_success.z, 0.15)
        border_col = imgui.ImVec4(Palette.accent_success.x, Palette.accent_success.y, Palette.accent_success.z, 0.4)
    elseif is_active then
        bg_col = Palette.bg_tertiary
    end

    dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), imgui.ColorConvertFloat4ToU32(bg_col), 10.0)
    dl:AddRect(p, imgui.ImVec2(p.x + w, p.y + h), imgui.ColorConvertFloat4ToU32(border_col), 10.0, 15, 1.5)

    local icon_sz = 40.0
    local icon_x = p.x + 12.0
    local icon_y = p.y + (h - icon_sz) / 2
    local icon_bg = is_added and Palette.accent_success or Palette.bg_tertiary
    local icon_text_col = is_added and Palette.bg_main or Palette.text_secondary
    dl:AddCircleFilled(imgui.ImVec2(icon_x + icon_sz/2, icon_y + icon_sz/2), icon_sz/2, imgui.ColorConvertFloat4ToU32(icon_bg))
    
    imgui.PushFont(fnt_icons)
    local item_icon = is_added and fa('check') or (is_sell and fa('box') or fa('tag'))
    local isz = imgui.CalcTextSize(item_icon)
    dl:AddText(imgui.ImVec2(icon_x + (icon_sz - isz.x)/2, icon_y + (icon_sz - isz.y)/2), imgui.ColorConvertFloat4ToU32(icon_text_col), item_icon)
    imgui.PopFont()

    imgui.PushFont(fnt_icons)
    local plus_icon = is_added and fa('check') or fa('plus')
    local psz = imgui.CalcTextSize(plus_icon)
    local p_col = is_added and Palette.accent_success or (is_active and Palette.accent_success or Palette.text_secondary)
    local plus_x = p.x + w - psz.x - 15.0
    dl:AddText(imgui.ImVec2(plus_x, p.y + (h - psz.y)/2), imgui.ColorConvertFloat4ToU32(p_col), plus_icon)
    imgui.PopFont()

    local text_x = icon_x + icon_sz + 12.0
    imgui.PushFont(fnt_main)
    local name_str = u8(item.name)
    local text_y = p.y + (h - imgui.GetFontSize()) / 2
    
    dl:PushClipRect(imgui.ImVec2(text_x, p.y), imgui.ImVec2(plus_x - 10, p.y + h), true)
    
    if item.amount then
        dl:AddText(imgui.ImVec2(text_x, p.y + 10), imgui.ColorConvertFloat4ToU32(is_added and Palette.text_secondary or Palette.text_primary), name_str)
        dl:AddText(imgui.ImVec2(text_x, p.y + 36), imgui.ColorConvertFloat4ToU32(Palette.text_secondary), u8"В наличии: " .. item.amount)
    else
        dl:AddText(imgui.ImVec2(text_x, text_y), imgui.ColorConvertFloat4ToU32(Palette.text_primary), name_str)
    end
    
    dl:PopClipRect()
    imgui.PopFont()

    imgui.Dummy(imgui.ImVec2(0, 8))
end

function toLowerRu(str)
    if type(str) ~= "string" then return "" end
    return (str:gsub(".", CYRILLIC_LOWER_MAP))
end

function formatCash(amount)
    local left, num, right = string.match(tostring(amount), '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1.'):reverse()) .. right
end

function processSellingCoroutine()
    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Активных слотов в лавке: " .. #RunState.selling.available_items .. ". Ищем совпадения...", -1)
    wait(1000) 
    
    local items_exhibited = 0
    
    for i, config_item in ipairs(sell_cfg) do
        if not RunState.selling.active then 
            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Выставление принудительно остановлено!", -1)
            break 
        end
        
        local display_name = config_item.name and tostring(config_item.name) or "Неизвестный товар"
        
        local target_model_id = tonumber(config_item.model_id)
        if not target_model_id then
            for _, inv_item in ipairs(stock_items) do
                if inv_item.name == config_item.name then
                    target_model_id = tonumber(inv_item.model_id)
                    break
                end
            end
        end
        
        local matched_slots = {}
        if target_model_id then
            for _, available in ipairs(RunState.selling.available_items) do
                if available.model_id == target_model_id then
                    table.insert(matched_slots, available)
                    if not config_item.use_max then break end
                end
            end
        end
        
        if #matched_slots > 0 then
            for _, match in ipairs(matched_slots) do
                if not RunState.selling.active then break end
                
                RunState.selling.current_idx = i
                RunState.selling.current_item = config_item
                RunState.selling.stage = 'waiting_input'
                
                sampAddChatMessage(string.format("{FF0000}| {FFFF00} Central Market {FFFFFF}Выставляем: %s (Слот: %d)", display_name, match.slot), -1)
                
                sendMobileCEFClick(match.slot, match.model_id, match.amount)
                
                local wait_time = 0
                while RunState.selling.stage == 'waiting_input' and RunState.selling.active do
                    wait(100)
                    wait_time = wait_time + 100
                    if wait_time > 9000 then 
                        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Таймаут окна ввода цены для: " .. display_name, -1)
                        break 
                    end
                end
                
                if RunState.selling.stage == 'next_item' then
                    items_exhibited = items_exhibited + 1
                    wait(Prefs.cef_delay or 1200)
                end
            end
        else
            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Пропущен: " .. display_name .. " (Не найден или серый слот)", -1)
        end
    end
    
    if RunState.selling.active then
        RunState.selling.stage = 'closing'
        sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Закрытие меню лавки...", -1)
        
        local function sendShopClosePacket(subid, flag)
            local bs = raknetNewBitStream()
            raknetBitStreamWriteInt8(bs, 220)
            raknetBitStreamWriteInt8(bs, 66)
            raknetBitStreamWriteInt8(bs, subid)
            raknetBitStreamWriteBool(bs, flag)
            PK.send(bs)
            raknetDeleteBitStream(bs)
        end
        
        sendShopClosePacket(60, true)
        wait(60)
        sendShopClosePacket(8, false)
        wait(60)
        sendShopClosePacket(60, false)
        
        local wait_close = 0
        while RunState.selling.active and wait_close < 3000 do
            wait(100)
            wait_close = wait_close + 100
        end
    end
end

function sendMobileCEFPacket(subid, close_flag)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(bs, 220)
    raknetBitStreamWriteInt8(bs, 66)
    raknetBitStreamWriteInt8(bs, subid)
    raknetBitStreamWriteBool(bs, close_flag)
    PK.send(bs)
    raknetDeleteBitStream(bs)
end

function sendMobileCEFClose()
    lua_thread.create(function()
        local close_sequence = {64, 65, 66, 67, 52, 8}
        for _, subid in ipairs(close_sequence) do
            sendMobileCEFPacket(subid, false)
            wait(60)
        end
    end)
end

function startInventoryScan()
    if RunState.inventory_scan.active then return end
    stock_items = {}
    RunState.inventory_scan.active = true
    RunState.inventory_scan.stage = "waiting_user"
    RunState.inventory_scan.has_received_data = false
    RunState.inventory_scan.last_packet_time = 0
    RunState.inventory_scan.current_dialog_id = nil
    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Открываю инвентарь для сканирования...", -1)
    sampSendChat("/invent")
    lua_thread.create(function()
        local start_time = os.clock()
        while RunState.inventory_scan.active do
            wait(150)
            local now = os.clock()
            if RunState.inventory_scan.stage == "parsing" and RunState.inventory_scan.has_received_data then
                if (now - RunState.inventory_scan.last_packet_time > 1.0) then
                    finishInventoryScan()
                    break
                end
            end
            if now - start_time > 30.0 and not RunState.inventory_scan.has_received_data then
                sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Ошибка: Таймаут. Вы не открыли инвентарь.", -1)
                RunState.inventory_scan.active = false
                menu_open[0] = true
                break
            end
        end
    end)
end

function finishInventoryScan()
    RunState.inventory_scan.active = false
    
    sendMobileCEFClose()
    
    if RunState.inventory_scan.current_dialog_id then
        sampSendDialogResponse(RunState.inventory_scan.current_dialog_id, 0, 0, "")
        RunState.inventory_scan.current_dialog_id = nil
    end
    
    table.sort(stock_items, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    
    writeJsonToDisk(FILE_INVENTORY, stock_items)
    list_cache_sell.query = nil
    
    sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}Инвентарь считан: " .. #stock_items .. " слотов.", -1)
    
    menu_open[0] = true
end

function parseMobileCEF(msgId, json_str)
    local ok, data = pcall(cjson.decode, json_str)
    if not ok or type(data) ~= "table" or type(data.items) ~= "table" then return end

    if RunState.selling.active and RunState.selling.stage == 'waiting_cef_data' and msgId == 52 then
        local received_valid_items = false
        
        for _, item in ipairs(data.items) do
            if tonumber(item.available) == 1 and item.item then
                table.insert(RunState.selling.available_items, {
                    slot = tonumber(item.slot),
                    model_id = tonumber(item.item),
                    amount = tonumber(item.amount) or 1
                })
                received_valid_items = true
            end
        end
        
        if received_valid_items or RunState.selling.last_packet_time == 0 then
            RunState.selling.last_packet_time = os.clock()
        end
    end

    if RunState.inventory_scan.active and (RunState.inventory_scan.stage == "parsing" or RunState.inventory_scan.stage == "waiting_user") and (msgId == 52 or msgId == 64 or msgId == 67) then
        if RunState.inventory_scan.stage == "waiting_user" then RunState.inventory_scan.stage = "parsing" end
        RunState.inventory_scan.last_packet_time = os.clock()
        RunState.inventory_scan.has_received_data = true

        if tonumber(data.type) == 1 then
            for _, item in ipairs(data.items) do
                if tonumber(item.available) == 1 and item.item and tonumber(item.is_use) ~= 1 then
                    local m_id = tonumber(item.item)
                    local name = name_lookup[tostring(m_id)]
                    
                    if name then
                        local exists = false
                        for _, v in ipairs(stock_items) do
                            if v.slot == tonumber(item.slot) and v.model_id == m_id then 
                                exists = true 
                                break 
                            end
                        end
                        
                        if not exists then
                            table.insert(stock_items, {
                                name = name, 
                                amount = tonumber(item.amount) or 1, 
                                model_id = m_id,
                                slot = tonumber(item.slot),
                                max_amount = tonumber(item.amount) or 1
                            })
                        end
                    end
                end
            end
        end
    end
end

function processBuyingPage(dialog_text, dialog_id)
    RunState.buying_scan.current_dialog_id = dialog_id

    local next_page_idx = -1
    local current_idx = 0
    
    local sorted_prefixes = {}
    for _, p in ipairs(QUALITY_TAGS) do table.insert(sorted_prefixes, p) end
    table.sort(sorted_prefixes, function(a, b) return #a > #b end)

    for line in dialog_text:gmatch("[^\r\n]+") do
        local clean = stripColorTags(line)
        
        if clean:find("Следующая страница") or clean:find("^%s*>") then
            next_page_idx = current_idx
        elseif not clean:find("Поиск предмета") and not clean:find("Поиск по категориям") and not clean:find("Предыдущая страница") then
            local raw_name, item_id = clean:match("^(.-)%s*%[(%d+)%]$")
            if raw_name and item_id then
                local name = raw_name
                
                for _, pfx in ipairs(sorted_prefixes) do
                    local safe_pfx = pfx:gsub("%.", "%%.")
                    if name:match("^" .. safe_pfx .. "%s+") then
                        name = name:sub(#pfx + 2)
                        break
                    end
                end
                
                table.insert(RunState.buying_scan.all_items, { 
                    name = normalizeItemLabel(name), 
                    index = tonumber(item_id) 
                })
            end
        end
        current_idx = current_idx + 1
    end

    if next_page_idx ~= -1 then
        RunState.buying_scan.current_page = RunState.buying_scan.current_page + 1
        sampSendDialogResponse(dialog_id, 1, next_page_idx, "")
    else
        finishBuyingScan()
    end
end

function finishBuyingScan()
    local unique_items = {}
    local seen = {}
    for _, item in ipairs(RunState.buying_scan.all_items) do
        local key = item.name .. "_" .. item.index
        if not seen[key] then
            seen[key] = true
            table.insert(unique_items, item)
            name_lookup[tostring(item.index)] = item.name
        end
    end
    
    catalog_items = unique_items
    writeJsonToDisk(FILE_CATALOG, catalog_items)
    writeJsonToDisk(FILE_NAMES, name_lookup)
    
    sampAddChatMessage('{FF0000}| {FFFF00} Central Market {FFFFFF}База товаров обновлена: ' .. #catalog_items .. ' шт.', -1)
    list_cache_buy.query = nil
    
    if RunState.buying_scan.current_dialog_id then 
        sampSendDialogResponse(RunState.buying_scan.current_dialog_id, 0, 0, "") 
    end

    RunState.buying_scan.stage = 'closing'
    
    lua_thread.create(function()
        local start = os.clock()
        while RunState.buying_scan.active and RunState.buying_scan.stage == 'closing' do
            wait(100)
            if os.clock() - start > 1.5 then
                RunState.buying_scan.active = false
                menu_open[0] = true
                break
            end
        end
    end)
end

function stopBuyingScan()
    if RunState.buying_scan.current_dialog_id then 
        sampSendDialogResponse(RunState.buying_scan.current_dialog_id, 0, 0, "") 
    end
    sampAddChatMessage('{FF0000}| {FFFF00} Central Market {FFFFFF}Сканирование прервано', -1)
    
    RunState.buying_scan.stage = 'closing'
    lua_thread.create(function()
        local start = os.clock()
        while RunState.buying_scan.active and RunState.buying_scan.stage == 'closing' do
            wait(100)
            if os.clock() - start > 1.5 then
                RunState.buying_scan.active = false
                break
            end
        end
    end)
end

function watchShopProximity(state_getter, timeout_ms)
    lua_thread.create(function()
        wait(timeout_ms or 6000)
        local st = state_getter()
        if st.active and st.stage == 'waiting_dialog' then
            st.active = false
            menu_open[0] = true
            sampAddChatMessage("{FF0000}| {FFFF00} Central Market {FFFFFF}- Вы не рядом с лавкой, открыть диалог не удалось", -1)
        end
    end)
end

function sendDialogReplyDelayed(id, response, list_item, input_text)
    local delay = tonumber(Prefs.dialog_delay) or 0
    if delay <= 0 then
        sampSendDialogResponse(id, response, list_item, input_text)
    else
        lua_thread.create(function()
            wait(delay)
            sampSendDialogResponse(id, response, list_item, input_text)
        end)
    end
end

function writeJsonToDisk(path, data)
    local clean_path = path:gsub("\\", "/")
    
    if not doesDirectoryExist(ROOT_DIR) then lfs.mkdir(ROOT_DIR) end
    if not doesDirectoryExist(ROOT_DIR .. 'data') then lfs.mkdir(ROOT_DIR .. 'data') end
    
    local f = io.open(clean_path, "w")
    if f then f:write(cjson.encode(data)); f:close() end
end

function normalizeItemLabel(name)
    local original = name
    name = name:gsub("{%x%x%x%x%x%x}", ""):gsub("%[.-%]", ""):gsub("^[оеш]?[втг]%s+", "")
    return name:match("^%s*(.-)%s*$") or ""
end

function stripColorTags(text)
    if type(text) ~= 'string' or text == "" then return "" end
    return text:gsub("{%x%x%x%x%x%x}", ""):gsub("%[%x%x%x%x%x%x%]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

function applyTplVars(text)
    if not text then return "" end
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local myName = LocalNickname or "Unknown"
    local vars = {
        ["{id}"] = tostring(myId),
        ["{name}"] = myName,
        ["{name_space}"] = myName:gsub("_", " "),
        ["{lvl}"] = tostring(sampGetPlayerScore(myId)),
        ["{time}"] = os.date("%H:%M")
    }
    return text:gsub("{(.-)}", function(k) return vars["{"..k.."}"] or "{"..k.."}" end)
end

function getTplDelayBuf(idx, delay)
    if not tpl_delay_bufs[idx] then tpl_delay_bufs[idx] = ffi.new('char[32]', tostring(delay or 60)) end
    return tpl_delay_bufs[idx]
end

function getTplBuf(idx, text)
    if not tpl_bufs[idx] then tpl_bufs[idx] = ffi.new('char[256]', text or "") end
    return tpl_bufs[idx]
end

