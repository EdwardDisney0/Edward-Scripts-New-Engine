local imgui    = require("mimgui")
local encoding = require("encoding")
local sampev   = require("samp.events")
local ffi      = require("ffi")
local lfsOk, lfs = pcall(require, "lfs")

encoding.default = "CP1251"
local u8 = encoding.UTF8


local BASE = ""
pcall(function() BASE = getWorkingDirectory() end)

local function fileExists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function ensureDir(path)
	if doesDirectoryExist(path) then
		return
	end

	if lfsOk and lfs then
		pcall(lfs.mkdir, path)
	end

	if not doesDirectoryExist(path) and createDirectory then
		pcall(createDirectory, path)
	end
end



local monoClock = os.clock
pcall(function()
	ffi.cdef[[
		typedef struct { long tv_sec; long tv_nsec; } vp_timespec;
		int clock_gettime(int clk_id, vp_timespec *tp);
	]]
	local ts = ffi.new("vp_timespec[1]")
	local function mono()
		ffi.C.clock_gettime(1, ts)
		return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) / 1e9
	end
	mono()
	monoClock = mono
end)


local json = {}
do
	local escMap = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}

	local function encStr(s)
		return '"' .. (s:gsub('[%c"\\]', function(c) return escMap[c] or string.format("\\u%04x", c:byte()) end)) .. '"'
	end

	local function isArray(t)
		local n = 0
		for k in pairs(t) do
			if type(k) ~= "number" then
				return false
			end
			n = n + 1
		end
		return n == #t
	end

	local function enc(v)
		local tv = type(v)
		if tv == "string" then
			return encStr(v)
		elseif tv == "number" then
			return string.format("%.14g", v)
		elseif tv == "boolean" then
			return tostring(v)
		elseif tv == "table" then
			local out = {}
			if isArray(v) then
				for i = 1, #v do
					out[i] = enc(v[i])
				end
				return "[" .. table.concat(out, ",") .. "]"
			end
			for k, val in pairs(v) do
				out[#out + 1] = encStr(tostring(k)) .. ":" .. enc(val)
			end
			return "{" .. table.concat(out, ",") .. "}"
		end
		return "null"
	end

	function json.encode(v)
		return enc(v)
	end

	function json.decode(s)
		local pos = 1
		local parse
		local escapes = {b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/"}

		local function perr()
			error("json parse error at " .. pos)
		end

		local function ws()
			pos = s:find("%S", pos) or (#s + 1)
		end

		local function str()
			pos = pos + 1
			local buf = {}
			while true do
				local a = s:find('["\\]', pos)
				if not a then perr() end
				buf[#buf + 1] = s:sub(pos, a - 1)
				pos = a
				local c = s:sub(pos, pos)
				if c == '"' then
					pos = pos + 1
					break
				end
				local n = s:sub(pos + 1, pos + 1)
				if n == "u" then
					local code = tonumber(s:sub(pos + 2, pos + 5), 16) or perr()
					buf[#buf + 1] = code < 256 and string.char(code) or "?"
					pos = pos + 6
				else
					buf[#buf + 1] = escapes[n] or n
					pos = pos + 2
				end
			end
			return table.concat(buf)
		end

		parse = function()
			ws()
			local c = s:sub(pos, pos)

			if c == "{" then
				pos = pos + 1
				local t = {}
				ws()
				if s:sub(pos, pos) == "}" then
					pos = pos + 1
					return t
				end
				while true do
					ws()
					if s:sub(pos, pos) ~= '"' then perr() end
					local k = str()
					ws()
					if s:sub(pos, pos) ~= ":" then perr() end
					pos = pos + 1
					t[k] = parse()
					ws()
					local d = s:sub(pos, pos)
					pos = pos + 1
					if d == "}" then
						return t
					elseif d ~= "," then
						perr()
					end
				end
			elseif c == "[" then
				pos = pos + 1
				local t = {}
				ws()
				if s:sub(pos, pos) == "]" then
					pos = pos + 1
					return t
				end
				while true do
					t[#t + 1] = parse()
					ws()
					local d = s:sub(pos, pos)
					pos = pos + 1
					if d == "]" then
						return t
					elseif d ~= "," then
						perr()
					end
				end
			elseif c == '"' then
				return str()
			elseif s:sub(pos, pos + 3) == "true" then
				pos = pos + 4
				return true
			elseif s:sub(pos, pos + 4) == "false" then
				pos = pos + 5
				return false
			elseif s:sub(pos, pos + 3) == "null" then
				pos = pos + 4
				return nil
			end

			local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
			if not num or num == "" then perr() end
			pos = pos + #num
			return tonumber(num)
		end

		return parse()
	end
end


local function ImBuffer(size)
	local obj = { size = size, ptr = ffi.new("char[?]", size) }

	return setmetatable(obj, {
		__index = function(t, k)
			if k == "v" then
				return ffi.string(t.ptr)
			end
		end,
		__newindex = function(t, k, val)
			if k == "v" then
				val = tostring(val or "")
				local n = math.min(#val, t.size - 1)
				ffi.copy(t.ptr, val, n)
				t.ptr[n] = 0
			else
				rawset(t, k, val)
			end
		end,
	})
end

local function ImBool(v)
	local obj = { ptr = ffi.new("bool[1]", v and true or false) }

	return setmetatable(obj, {
		__index = function(t, k)
			if k == "v" then
				return t.ptr[0]
			end
		end,
		__newindex = function(t, k, val)
			if k == "v" then
				t.ptr[0] = val and true or false
			else
				rawset(t, k, val)
			end
		end,
	})
end

local function ImInt(v)
	local obj = { ptr = ffi.new("int[1]", v or 0) }

	return setmetatable(obj, {
		__index = function(t, k)
			if k == "v" then
				return t.ptr[0]
			end
		end,
		__newindex = function(t, k, val)
			if k == "v" then
				t.ptr[0] = tonumber(val) or 0
			else
				rawset(t, k, val)
			end
		end,
	})
end


local function pushID(id)
	local f
	if type(id) == "number" then
		f = imgui.PushIDInt or imgui.PushID
		f(id)
	else
		f = imgui.PushIDStr or imgui.PushID
		f(tostring(id))
	end
end

local function pushVar(idx, v)
	local f
	if type(v) == "number" then
		f = imgui.PushStyleVarFloat or imgui.PushStyleVar
	else
		f = imgui.PushStyleVarVec2 or imgui.PushStyleVar
	end
	f(idx, v)
end

local function pushCol(idx, v)
	local f = imgui.PushStyleColorVec4 or imgui.PushStyleColor
	f(idx, v)
end

local function addCircleFilled(dl, center, radius, col)
	dl:AddCircleFilled(center, radius, col, 32)
end


local UI_SCALE  = 1.5   
local FONT_SIZE = 17.0 * UI_SCALE
local mainFont = nil


local ICON_FONT_B64 = [[
AAEAAAAMAIAAAwBAR0RFRgASABoAAA8sAAAAFk9TLzJDiVKCAAABSAAAAGBjbWFwbG1fYAAAAhAAAADUZ2FzcP//AAMAAA8kAAAA
CGdseWZv2Z79AAADHAAAC6RoZWFkJwAOVQAAAMwAAAA2aGhlYQRDAlYAAAEEAAAAJGhtdHgu5AAaAAABqAAAAGZsb2NhJtAj+gAA
AuQAAAA2bWF4cAAiAGEAAAEoAAAAIG5hbWUESQikAAAOwAAAAERwb3N0/94AGQAADwQAAAAgAAEAAAFLhiSsrX4nXw889QAJAgAA
AAAA3TB+AAAAAADm6cm0//z/uQKCAccAAAAIAAIAAAAAAAAAAQAAAcD/wAAAAoD//f/8AoMAAQAAAAAAAAAAAAAAAAAAABkAAQAA
ABoAYAAHAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAEAfsDhAAFAAABTAFmAAAARwFMAWYAAAD1ABkAhAAAAgAFAwAAAAAAAAAAAAAA
AAAAAAAAAAAAAABQZkVkAIDwB/UhAcD/wAAuAcwAVAAAAAEAAAAAAToBpQAAACAAAQIAAAABwAAAAgAAAAFgAAACAAAQAgAACAIA
AAACAAAAAcAAAAHAAAABwAAAAgAAAAIAAAgBwAAAAcAAAAIA//8CQAAAAgD//QHAAAABQP//AgAAAAHAAAACQAAAAUAAAAKA//8A
AAAAAAAAAgAAAAMAAAAUAAMAAQAAABQABADAAAAALAAgAAQADPAH8A3wE/AX8CHwOvBN8FDwWfBo8HXwevCV8Mfw5/HY8fjywvPN
9J71If//AADwB/AM8BPwF/Ah8DrwS/BQ8FnwZ/B18HrwlfDH8Ofx2PH48sLzzfSe9SH//w/6D/YP8Q/uD+UPzQ+9D7sPsw+mD5oP
lg98D0sPLA48Dh0NVAxKC3oK+AABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACsAUACJ
APMBIQGPAg4CJwJWAnICogLsAxwDNwNXA5sDxgQDBCwEVwSNBPsFMQV8BdIAAAACAAD/wAHAAcAABwAbAAAkIiY0NjIWFAcyFhUV
FAYjISImNTU0NjMzFjI3ARVqS0tqSyY3TxwU/qAUHE83ESNMI8BLaktLamtPNyoUHBwUKjdPEBAAAAEAAAABAgABfwAUAAA3JyY0
Nzc2MhcXNzYyFxcWFAcBBiKupwcHJQcVCHDwCBUHJQcH/tkHFgmmBxYHJAgIcPAICCQHFgf+2ggAAQAAABABYAFwACMAADcXFhQH
BwYiJycHBiInJyY0NzcnJjQ3NzYyFxc3NjIXFxYUB/NkCQkWChoJZGQJGgoWCQlkZAkJFgoaCWRkCRoKFgkJwGQJGgoWCQlkZAkJ
FgoaCWRkCRoKFgkJZGQJCRYKGgkAAgAQ/8IB8AG+ADwARAAAJRYHBgcGJycGBxUUBwYnJjU1JicHBicmJyY3NyY0NycmNzY3NhcX
Njc1NDc2FxYVFRYXNzYXFhcWBwcWBwYyNjQmIgYUAecJAxEmBggrGyIJNzYKIhsqCQYmEQMJKgMDKgkDESYGCSobIgk3NwkiGyoJ
BiYRAwkqBgbeQi8vQi+EBAo1KQcEGRcMMQoCDAwCCjEMFxkEByk1CQUZESQRGQQKNSkHBRgXDDEKAgwMAgoxDBcZBAcpNQoEGSMj
LS9CLy9CAAACAAj/yAH4AbgABwAdAAASMhYUBiImNAU2NTQnJzU0JiMjIgYVFRQXFxYzMjeZzpGRzpEBVAQGOgkHIAcJD0MEBggE
AbiRzpGRzqgEBggFKpAHCQkHnBMMMQQGAAIAAP/AAgABwAApAFMAAAE0MTQ2MzMyFRUUBiMjIiY1NTQ2MxcmJiMiBgcGIyMiJjU0
NTY2MzIWFwMyNjc2MzMyFhUUBwYGIyImJxcUMRQGIyMiNTU0NjMzMhYVFRQGIycWFgG5BwUvDAcFyAUHBwVmGE0tPl8OAgoxBQcR
iVo4YiO9PWAOAgoxBQcBEIlaOGIjBAcFLwwHBcgFBwcFZhhNAbMBBQcMyAUHBwUvBQcFJCpMOwkHBQEBV3MuKf6vTDsJBwUBAVdz
LilSAQUHDMgFBwcFLwUHBSQqAAAGAAD/8AIAAZAADwAfAC8APwBPAF8AADcyFhUVFAYjIyImNTU0NjMTMhYVFRQGIyMiJjU1NDYz
FzIWFRUUBiMjIiY1NTQ2MwUyFhUVFAYjISImNTU0NjMBMhYVFRQGIyEiJjU1NDYzBTIWFRUUBiMhIiY1NTQ2M1AHCQkHQAcJCQdA
BwkJB0AHCQkHQAcJCQdABwkJBwHgBwkJB/7ABwkJBwFABwkJB/7ABwkJBwFABwkJB/7ABwkJB1AJB0AHCQkHQAcJAUAJB0AHCQkH
QAcJoAkHQAcJCQdABwmwCQcgBwkJByAHCQFACQcgBwkJByAHCaAJByAHCQkHIAcJAAEAAP+5AcABxwALAAAlFhQHBQYmNRE0NhcB
qBgY/qAXMTMV6Q42DtAOGxwBoB4ZDgAAAgAA/+EBwAGhAA8AHwAAFyMiJjURNDYzMzIWFREUBiUUBiMjIiY1ETQ2MzMyFhWQYBQc
HBRgFBwcARwcFGAUHBwUYBQcHxwUAWAUHBwU/qAUHDAUHBwUAWAUHBwUAAEAAP/gAcABoAAPAAABMhYVERQGIyEiJjURNDYzAZAU
HBwU/qAUHBwUAaAcFP6gFBwcFAFgFBwAAQAA//oCAAGGAB8AAAERFCMjIjU1BwYmNTUHBiY1ETQ2Fxc1NDYXFzU0MzMyAgAMKAys
DyWsDyUlD6wlD6wMKAwBdP6YDAyYnQ0SFISdDRIUAUAUEg2cgxQSDZyXDAAAAwAI/8gB+AG4AAcAKgAyAAAAFAYiJjQ2MgciBwYX
FxY3NjYzMhYVFAYHDgIVFRQzMzI1NTQ+AjU0JgYiBhQWMjY0AfiRzpGRzmBKKwYJIwkHEBcSER0PERIRFAw4DBofGkggJhsbJhsB
J86Rkc6RUkAJBxoHCRMREw4LDQoKDB4TBAwMAQkSECYaKjz4GyYbGyYAAAEAAP/gAcABoAAjAAAlMhYVFRQGIyMVFAYjIyImNTUj
IiY1NTQ2MzM1NDYzMzIWFRUBoA0TEw2QEw0gDROQDRMTDZATDSANE/ATDSANE5ANExMNkBMNIA0TkA0TEw2QAAEAAACQAcAA8AAP
AAAlMhYVFRQGIyEiJjU1NDYzAaANExMN/oANExMN8BMNIA0TEw0gDRMAAAH////gAgABoAASAAASMhYUBiMiJwYjIiY+AjcmNTSW
1JaWajgzQUwFBAcRHAY5AaB6rHoTMwoHFTEWOUpWAAABAAD/wAJCAcAALgAAJQYjIRchMhYHBxYVFAYiJjU0NyMWFRQGIiY1NDcD
IyImNTU0NjMzMhYXFyEyFgcCEAQT/tsGAQ0LDgIGICEuIRHSESEuIRxGRgoODgpnCA0CCQGJDA4DkxMgEgsZDyMXISEXGBAQGBch
IRcgEQFXDgoQCg4LCC0SCwAAAf/8/8ACAAHEABcAAAEWFRQAIyInJyY3NzYXFzY2NycmNzc2FwHtE/7wwBMEGAUTcBAMMTtbGzwO
BzAIEwGnBBPA/vATaBMIMAcOPBtcOjILEXASBQADAAD/4AHAAaAAEQAZACgAAAEWFREUBiMhIiY1ETQ2MyEyFwIyNjQmIgYUEzQn
JyYjIyIVFRQzMzI1AbIOHBT+oBQcHBQBDBQOmTYlJTYloAQDBATlDAzoDAE+DhT+9BQcHBQBYBQcDv6OJTYlJTYBDAQEAwQMaAwM
AAH////AAUQBwAAXAAABMhYHAwYjIiY3NyMiJjc3NjYzMzIWBwcBKA4OB7AHDgwOAy53Cw4BIAEOCZAMDgMqASAYDP7QDBIMwhAL
8AkMEwuCAAAB////vAICAcQAFgAAATYWBwMGBicnBwYmNTUTNiYHBScmJjcB3A0ZAkgCFQp9QAog8QMIBP7hag4CDQG9BxEP/lAL
DAU0TQ0LEVEBJQUHA/0sBh4HAAIAAP/AAcABwAAXACEAAAEyFhUVFAYjISImNTU0NjMzNzYzMzIXFwEDIQMGBiMjIiYBsAcJCQf+
YAcJCQd4CQcPcg8HCf79FQGAFQEcE/YTHAGgCQcgBwkJByAHCRMNDRP+TQFT/q0TGhoAAAcAAP/gAkABoAAJABMAHwArADcAPwBR
AAABMhYVFSE1NDYzAxEhERQGIyEiJiUVFDMzMjU1NCMjIhUVFDMzMjU1NCMjIhUVFDMzMjU1NCMjIiYiBhQWMjY0BwYWMzMyNicm
JiMjBiInIyIGAhAUHP3AHBQwAkAcFP4gFBwBYAiQCAiQCAiQCAiQCAiQCAiQCJY0JiY0Jq0CCgi6CAoCBiIVCBMqEwgVIgGgHBQQ
EBQc/nABMP7QFBwc/BAICBAISBAICBAISBAICBAIgCY0JiY0pgcNDAgTGQgIGQADAAD/wAFAAcAADwAXACMAAAEyFhURFAYjIyIm
NRE0NjMSMjY0JiIGFDcRNCMjIhURFDMzMgEQFBwcFOAUHBwUYxoTExoTkAzIDAzIDAHAHBT+YBQcHBQBoBQc/iATGhMTGlkBOAwM
/sgMAAAD//7/3gKCAaEAFwAiAC0AACUyNzcVFAYHBwYnJyYmNTUXFjMyNzcXFjcWBgcHBicnNzYXITYXFwcGJycmJjcBqgcGiQ4K
2Q8Q2AoOiQYHHA5AQA7wBAYIxgwGXPoMBf3qBQz6XAYMxggGBMACJ7ILEQM2BAQ2AxELsicCF2trF3AHDgI4BAuYIAEKCgEgmAsE
OAIOBwACAAD/wAKAAcAADwA7AAAhMhYVFRQGIyEiJjU1NDYzADIWFAYjIicHIScGIyImNDYyFhUUBxcWNjc3JjU0NjIWFRQHFxYW
NzcmNTQCEAcJCQf+YAcJCQcBzCgcHBQDBUj+gEgFAxQcHCgcBEgLGwZSEhwoHBJSBhoMSAQJByAHCQkHIAcJAUAcKBwBwcEBHCgc
HBQKCisHBwuPDxYUHBwUFg+PCwcHKwoKFAAAAAABABIAAwABBAkAAQAyAAAARgBvAG4AdAAgAEEAdwBlAHMAbwBtAGUAIAA1ACAA
RgByAGUAZQAgAFMAbwBsAGkAZAADAAAAAAAA/9sAGQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAf//AAIAAQAAAAwAAAAAAAAAAgAB
AAEAGQACAAA=
]]

local function b64decode(data)
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local map = {}
	for i = 1, #alphabet do
		map[alphabet:byte(i)] = i - 1
	end

	local out, buf, bits = {}, 0, 0

	for i = 1, #data do
		local v = map[data:byte(i)]

		if v then
			buf = buf * 64 + v
			bits = bits + 6

			if bits >= 8 then
				bits = bits - 8
				local divisor = 2 ^ bits
				out[#out + 1] = string.char(math.floor(buf / divisor))
				buf = buf % divisor
			end
		end
	end

	return table.concat(out)
end

local ICON_FONT_PATH = BASE .. "/resource/fonts/vp_icons.ttf"
local HAS_ICONS = false
pcall(function()
	local bytes = b64decode(ICON_FONT_B64)
	ensureDir(BASE .. "/resource")
	ensureDir(BASE .. "/resource/fonts")

	local needWrite = true
	local f = io.open(ICON_FONT_PATH, "rb")
	if f then
		needWrite = (f:seek("end") ~= #bytes)
		f:close()
	end

	if needWrite then
		local out = io.open(ICON_FONT_PATH, "wb")
		if out then
			out:write(bytes)
			out:close()
		end
	end

	HAS_ICONS = fileExists(ICON_FONT_PATH)
end)
local ICON_GLYPH_RANGE = imgui.new.ImWchar[3](0xf000, 0xf8ff, 0)




local TAG_ADVANCE           = 28.0 * UI_SCALE   
local TAG_PLACEHOLDER_RANGE = imgui.new.ImWchar[3](0x0101, 0x0105, 0)
local mainFontPath  = nil
local tagFontReady  = false

local FONT_CANDIDATES = {
	BASE .. "/resource/fonts/arialbd.ttf",
	BASE .. "/resource/fonts/arial.ttf",
	"/system/fonts/Roboto-Bold.ttf",
	"/system/fonts/Roboto-Medium.ttf",
	"/system/fonts/Roboto-Regular.ttf",
	"/system/fonts/NotoSans-Bold.ttf",
	"/system/fonts/NotoSans-Regular.ttf",
	"/system/fonts/DroidSans.ttf",
}

local function fa(codepoint)
	if not HAS_ICONS then
		return ""
	end

	return string.char(
		0xE0 + bit.rshift(codepoint, 12),
		0x80 + bit.band(bit.rshift(codepoint, 6), 0x3F),
		0x80 + bit.band(codepoint, 0x3F)
	)
end

local function fa_ph(codepoint)
	if not HAS_ICONS then
		return ""
	end

	return string.char(0xC0 + bit.rshift(codepoint, 6), 0x80 + bit.band(codepoint, 0x3F))
end

local ICON = {
	PLAY    = fa(0xf04b),
	STOP    = fa(0xf04d),
	SAVE    = fa(0xf0c7),
	PAPER   = fa(0xf1d8),
	CLOCK   = fa(0xf017),
	CHECK   = fa(0xf00c),
	PAUSE   = fa(0xf04c),
	SKIP    = fa(0xf050),
	BOLT    = fa(0xf0e7),
	PLUS    = fa(0xf067),
	MINUS   = fa(0xf068),
	TRASH   = fa(0xf1f8),
	EMPTY   = fa(0xf49e),
	SYNC    = fa(0xf021),
	CROWN   = fa(0xf521),
	PHONE   = fa(0xf095),
	GEAR    = fa(0xf013),
	LIST    = fa(0xf03a),
	MESSAGE = fa(0xf075),
	USER    = fa(0xf007),
	ID_CARD = fa(0xf2c2),
	CART    = fa(0xf07a),
	XMARK   = fa(0xf00d),
	QUESTION = fa(0xf059),
}


if not HAS_ICONS then
	ICON.XMARK    = "X"
	ICON.PLUS     = "+"
	ICON.MINUS    = "-"
	ICON.TRASH    = "x"
	ICON.SYNC     = "~"
	ICON.QUESTION = "?"
end

local THEME = {
	WINDOW_BG          = imgui.ImVec4(0.08, 0.09, 0.13, 0.98),
	TITLE_BG           = imgui.ImVec4(0.10, 0.11, 0.17, 1),
	TITLE_BG_ACTIVE    = imgui.ImVec4(0.14, 0.16, 0.28, 1),

	ACCENT             = imgui.ImVec4(0.30, 0.55, 0.95, 1),
	ACCENT_HOVER       = imgui.ImVec4(0.40, 0.65, 1.00, 1),
	ACCENT_ACTIVE      = imgui.ImVec4(0.22, 0.42, 0.80, 1),

	BUTTON_RUN         = imgui.ImVec4(0.16, 0.62, 0.31, 1),
	BUTTON_RUN_HOVER   = imgui.ImVec4(0.22, 0.78, 0.40, 1),
	BUTTON_RUN_ACTIVE  = imgui.ImVec4(0.12, 0.50, 0.24, 1),

	BUTTON_STOP        = imgui.ImVec4(0.75, 0.20, 0.20, 1),
	BUTTON_STOP_HOVER  = imgui.ImVec4(0.90, 0.28, 0.28, 1),
	BUTTON_STOP_ACTIVE = imgui.ImVec4(0.60, 0.14, 0.14, 1),

	DANGER             = imgui.ImVec4(0.65, 0.16, 0.18, 1),
	DANGER_HOVER       = imgui.ImVec4(0.82, 0.24, 0.26, 1),
	DANGER_ACTIVE      = imgui.ImVec4(0.50, 0.10, 0.12, 1),

	BUTTON_SECONDS     = imgui.ImVec4(0.35, 0.40, 0.75, 1),
	BUTTON_MINUTES     = imgui.ImVec4(0.75, 0.40, 0.35, 1),

	TEXT_READY         = imgui.ImVec4(0.30, 0.90, 0.40, 1),
	TEXT_WAITING       = imgui.ImVec4(0.95, 0.85, 0.25, 1),
	TEXT_PAUSED        = imgui.ImVec4(0.95, 0.55, 0.15, 1),
	TEXT_MUTED         = imgui.ImVec4(0.52, 0.54, 0.61, 1),

	GOLD               = imgui.ImVec4(1.00, 0.82, 0.20, 1),
	VIOLET             = imgui.ImVec4(0.62, 0.45, 0.95, 1),
	SILVER             = imgui.ImVec4(0.58, 0.60, 0.66, 1),
	RED                = imgui.ImVec4(1.00, 0.30, 0.30, 1),
	CYAN               = imgui.ImVec4(0.25, 0.78, 1.00, 1),
}

local UI = {
	BG         = imgui.ImVec4(0.050, 0.050, 0.068, 0.985),
	PANEL      = imgui.ImVec4(0.074, 0.074, 0.098, 1),
	CARD       = imgui.ImVec4(0.092, 0.092, 0.122, 1),
	FIELD      = imgui.ImVec4(0.054, 0.054, 0.074, 1),
	FIELD_HOV  = imgui.ImVec4(0.068, 0.068, 0.092, 1),
	FIELD_ACT  = imgui.ImVec4(0.062, 0.062, 0.084, 1),
	BORDER     = imgui.ImVec4(1, 1, 1, 0.065),
	RED        = imgui.ImVec4(0.91, 0.16, 0.22, 1),
	RED_HOVER  = imgui.ImVec4(1.00, 0.28, 0.33, 1),
	RED_ACTIVE = imgui.ImVec4(0.74, 0.11, 0.17, 1),
	TEXT       = imgui.ImVec4(0.95, 0.95, 0.97, 1),
	MUTED      = imgui.ImVec4(0.56, 0.57, 0.66, 1),
	BTN        = imgui.ImVec4(0.135, 0.135, 0.175, 1),
	BTN_HOVER  = imgui.ImVec4(0.20, 0.20, 0.26, 1),
	BTN_ACTIVE = imgui.ImVec4(0.10, 0.10, 0.14, 1),
	CLEAR      = imgui.ImVec4(0, 0, 0, 0),
}

local WIN_W, WIN_H  = 880 * UI_SCALE, 660 * UI_SCALE
local WIN_PAD       = 14 * UI_SCALE
local HEADER_H      = 64 * UI_SCALE
local SIDEBAR_W     = 184 * UI_SCALE
local STATUS_H      = 132 * UI_SCALE
local FIELD_PAD_X   = 26 * UI_SCALE
local FIELD_PAD_Y   = 8 * UI_SCALE

local function V2(x, y)
	return imgui.ImVec2(x, y)
end

local function c32(v, a)
	if a then
		return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(v.x, v.y, v.z, a))
	end

	return imgui.ColorConvertFloat4ToU32(v)
end

local function shade(color, amount)
	local function clamp01(v) return math.max(0, math.min(1, v)) end
	return imgui.ImVec4(clamp01(color.x + amount), clamp01(color.y + amount), clamp01(color.z + amount), color.w)
end

local NEUTRAL_CHANNEL_BG         = imgui.ImVec4(0.19, 0.20, 0.26, 1)
local NEUTRAL_CHANNEL_BG_HOVER   = imgui.ImVec4(0.25, 0.27, 0.34, 1)
local NEUTRAL_CHANNEL_BG_ACTIVE  = imgui.ImVec4(0.15, 0.16, 0.21, 1)
local NEUTRAL_CHANNEL_TEXT       = imgui.ImVec4(0.85, 0.86, 0.90, 1)

local CHANNEL_PRESETS = {
	{ key = "s",      label = "S",      color = THEME.CYAN },
	{ key = "al",     label = "AL",     color = THEME.VIOLET },
	{ key = "b",      label = "B",      color = THEME.RED },
	{ key = "custom", label = "CUSTOM", color = THEME.SILVER },
}

local DEBUG = false  

local function dbg(msg)
	if DEBUG then
		pcall(sampAddChatMessage, "{FFA500}[VPR debug]{FFFFFF} " .. tostring(msg), -1)
		print("[VPR debug] " .. tostring(msg))
	end
end

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end





local Touch = {
	SLOP        = 10 * UI_SCALE,  
	FRICTION    = 4.5,            

	area        = nil,    
	tracking    = false,  
	dragging    = false,  
	blockClicks = false,  
	startY      = 0,
	startScroll = 0,
	samples     = {},
	velocity    = 0,      
	inertiaPos  = nil,
	lastTime    = 0,

	activeFieldRect    = nil,    
	caretToEnd         = false,  
	caretToEndDeadline = 0,
}


function Touch.tapAllowed()
	return not Touch.blockClicks
end

function Touch.tooltip(text)
	if not Touch.dragging and imgui.IsItemHovered() then
		imgui.SetTooltip(text)
	end
end


local mainMenu = { state = false, duration = 0.25, alpha = 0.00, last = monoClock() }

function mainMenu.switch()
	mainMenu.state = not mainMenu.state
	dbg("menu " .. (mainMenu.state and "open" or "close") .. ", font=" .. tostring(mainFont ~= nil))
	return true
end

function mainMenu.update()
	local now = monoClock()
	local dt = math.min(0.1, math.max(0, now - mainMenu.last))
	mainMenu.last = now

	local step = dt / mainMenu.duration
	if mainMenu.state then
		mainMenu.alpha = math.min(1, mainMenu.alpha + step)
	else
		mainMenu.alpha = math.max(0, mainMenu.alpha - step)
	end
end

local VARIABLES = {
	{tag = "{id}",    label = u8("ID"),     desc = u8("\194\224\248 \232\227\240\238\226\238\233 ID"),               icon = ICON.ID_CARD, glyph = fa(0xf2c2), ph = fa_ph(0x101)},
	{tag = "{name}",  label = u8("\205\232\234"),    desc = u8("\194\224\248 \237\232\234 (Name_Surname)"),       icon = ICON.USER,    glyph = fa(0xf007), ph = fa_ph(0x102)},
	{tag = ":lavka:", label = u8("\203\224\226\234\224"),  desc = u8("\194\241\242\224\226\232\242 :lavka<ID>:"),          icon = ICON.CART,    glyph = fa(0xf07a), ph = fa_ph(0x103)},
	{tag = ":call1:", label = u8("\210\229\235. 1"), desc = u8("\194\241\242\224\226\232\242 :call<\237\238\236\229\2401>:"),       icon = ICON.PHONE,   glyph = fa(0xf095), ph = fa_ph(0x104)},
	{tag = ":call2:", label = u8("\210\229\235. 2"), desc = u8("\194\241\242\224\226\232\242 :call<\237\238\236\229\2402>:"),       icon = fa(0xf3cd),   glyph = fa(0xf3cd), ph = fa_ph(0x105)},
}

imgui.OnInitialize(function()
	imgui.GetIO().IniFilename = nil

	local fonts = imgui.GetIO().Fonts

	for _, path in ipairs(FONT_CANDIDATES) do
		if fileExists(path) then
			mainFont = fonts:AddFontFromFileTTF(path, FONT_SIZE, nil, fonts:GetGlyphRangesCyrillic())
			mainFontPath = path
			break
		end
	end

	if mainFont == nil then
		
		mainFont = fonts:AddFontDefault()
	end

	if HAS_ICONS then
		local cfg = imgui.ImFontConfig()
		cfg.MergeMode  = true
		cfg.PixelSnapH = true
		fonts:AddFontFromFileTTF(ICON_FONT_PATH, FONT_SIZE, cfg, ICON_GLYPH_RANGE)
	end

	
	if not mainFontPath then
		dbg("tag placeholder font: no main ttf found")
	end

	if HAS_ICONS and mainFontPath then
		local okTag, errTag = pcall(function()
			local cfg = imgui.ImFontConfig()
			cfg.MergeMode  = true
			cfg.PixelSnapH = true
			cfg.GlyphMinAdvanceX = TAG_ADVANCE
			cfg.GlyphMaxAdvanceX = TAG_ADVANCE
			local f = fonts:AddFontFromFileTTF(mainFontPath, FONT_SIZE, cfg, TAG_PLACEHOLDER_RANGE)
			tagFontReady = (f ~= nil)
		end)
		dbg("tag placeholder font: " .. tostring(tagFontReady) .. ", ok=" .. tostring(okTag) .. ", err=" .. tostring(errTag) .. ", path=" .. tostring(mainFontPath))
	end

	applyStyle()
	dbg("imgui init ok, font loaded: " .. tostring(mainFont ~= nil) .. ", icons: " .. tostring(HAS_ICONS))
end)

local activeTab = 1
local activeInputBuffer = nil

local blocks = {}
local nextBlockId = 1
local pendingDelete = nil

local vrGroups = {}
local nextGroupId = 1
local pendingGroupDelete = nil

local VR_INTERVAL_MS = 5 * 60 * 1000

local autoSkipDialog = ImBool(true)
local autoStartEnabled = ImBool(false)
local AUTOSTART_DELAY_SEC = 30
local phoneNumber1 = ImBuffer(32)
local phoneNumber2 = ImBuffer(32)
local runningToggle = ImBool(false)
local toggleAnimState = {}
local showVrFaq = ImBool(false)
local faqAnim = 0.0
local faqAnimClock = monoClock()
local faqBlockInputs = false
local faqRender = nil
local FAQ_FADE_SEC = 0.18
local currentMenuHeight = 680
local timerWheelCaptured = false

local CONFIG_DIR  = BASE .. "/config/vip_piar"
local CONFIG_PATH = CONFIG_DIR .. "/vip_piar.json"

local SEND_DELAY_SEC = 0.7
local SEND_THREAD_DELAY_MS = 1000

local recentScriptMessages = {}
local SCRIPT_MESSAGE_TTL_MS = 6000

local lastSentText = ""
local lastSentChannel = ""
local awaitingOwnMessageDialog = false
local lastVrGroup = nil
local lastSentEntity = nil

local awaitingSecondDialog      = false
local awaitingSecondDialogSince = 0
local AWAIT_SECOND_DIALOG_TIMEOUT_MS = 5000

local running = false

local primingDone      = false
local primingIndex     = 1
local primingStageTime = 0
local PRIMING_GAP_SEC  = 5

local lastAutoSaveTime = 0
local AUTOSAVE_INTERVAL_SEC = 3

function getTimeMs()
	return monoClock() * 1000
end

local function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function stripColors(s)
	s = s:gsub("{%x%x%x%x%x%x%x%x}", "")
	s = s:gsub("{%x%x%x%x%x%x}", "")
	return s
end

local function createBlock(channelIndex, customChannel, text, enabled, timer, useSeconds)
	local block = {
		id                = nextBlockId,
		channelIndex      = channelIndex or 1,
		customChannel     = ImBuffer(32),
		buffer            = ImBuffer(256),
		enabled           = ImBool(enabled or false),
		timer             = ImInt(timer or 5),
		use_seconds       = ImBool(useSeconds or false),
		last_sent         = 0,
		next_send_time    = 0,
		pause_start_time  = 0,
		was_sent          = false,
		show_paused       = false,
		ready_after_pause = false,
	}

	block.customChannel.v = customChannel or ""
	block.buffer.v = u8(text or "")

	nextBlockId = nextBlockId + 1
	table.insert(blocks, block)

	return block
end

local function createVrGroup(enabled)
	local group = {
		id                = nextGroupId,
		enabled           = ImBool(enabled or false),
		messages          = {},
		currentIndex      = 1,
		last_sent         = 0,
		next_send_time    = 0,
		pause_start_time  = 0,
		was_sent          = false,
		show_paused       = false,
		ready_after_pause = false,
	}

	nextGroupId = nextGroupId + 1
	table.insert(vrGroups, group)

	return group
end

local function createGroupMessage(group, text)
	local msgObj = { buffer = ImBuffer(256) }
	msgObj.buffer.v = u8(text or "")
	table.insert(group.messages, msgObj)
	return msgObj
end

local function findNextGroupMessageIndex(group)
	if #group.messages == 0 then
		return nil
	end

	local start = group.currentIndex

	for i = 0, #group.messages - 1 do
		local idx = ((start - 1 + i) % #group.messages) + 1
		local msgObj = group.messages[idx]

		if msgObj and string.len(msgObj.buffer.v) > 0 then
			return idx
		end
	end

	return nil
end

local function resolveChannel(block)
	local preset = CHANNEL_PRESETS[block.channelIndex]

	if preset.key == "custom" then
		return trim(block.customChannel.v):lower()
	end

	return preset.key
end










local myIdent = {
	manualId     = nil,   
	lastGoodId   = nil,
	configLoaded = false,

	joinNick   = nil,   
	savedNick  = nil,   
	initId     = nil,   
	serverId   = nil,   
	serverNick = nil,
	remote     = {},    
	outgoing   = {},    
	id         = nil,   
	nick       = nil,
	source     = "none",
	checkedAt  = -100,
	lastLog    = nil,
}

do
local MAX_PLAYER_ID = 1003

local function validNick(s)
	return type(s) == "string" and #s >= 3 and #s <= 24
		and s:match("^[%w_%.%[%]%$@=%(%)]+$") ~= nil
		and s:find("%a") ~= nil
		and not s:match("^%d*Player_%x%x%x%x%x%x%x%x+$")   
		and not s:match("^%d*Player_%x+$")
end

local function validId(id)
	return type(id) == "number" and id >= 0 and id <= MAX_PLAYER_ID and id == math.floor(id)
end


local function isOtherPlayer(id)
	local nick = myIdent.remote[id]

	if not nick then
		return false
	end

	return nick ~= (myIdent.joinNick or myIdent.serverNick)
end

local function nickOf(id)
	if not validId(id) then
		return nil
	end

	local ok, nick = pcall(sampGetPlayerNickname, id)

	if ok and type(nick) == "string" and nick ~= "" then
		return nick
	end

	return nil
end

local function idByHandle()
	local ped = PLAYER_PED or playerPed
	local ok, res, id = pcall(sampGetPlayerIdByCharHandle, ped)

	if ok and res and validId(id) then
		return id
	end

	return nil
end


local function idByScan()
	local ped = PLAYER_PED or playerPed

	for i = 0, MAX_PLAYER_ID do
		local ok, res, handle = pcall(sampGetCharHandleBySampPlayerId, i)

		if ok and res and handle == ped then
			return i
		end
	end

	return nil
end


local function ownNickGuess()
	if myIdent.joinNick then
		return myIdent.joinNick
	end

	if myIdent.serverNick then
		return myIdent.serverNick
	end

	
	return myIdent.savedNick
end


local function idByNick(nick)
	if not nick then
		return nil
	end

	local maxId = MAX_PLAYER_ID
	local okMax, m = pcall(sampGetMaxPlayerId, false)

	if okMax and type(m) == "number" and m >= 0 and m < MAX_PLAYER_ID then
		maxId = m
	end

	for i = 0, maxId do
		if nickOf(i) == nick and not isOtherPlayer(i) then
			return i
		end
	end

	return nil
end

local function resolveIdentity()
	
	local ver = myIdent.q and myIdent.q.verified

	if ver and not myIdent.manualId then
		return ver.id, ver.nick, "idcmd"
	end

	local strongNick = myIdent.joinNick or myIdent.serverNick
	local hintNick = strongNick or myIdent.savedNick

	
	local byNick = idByNick(hintNick)

	if byNick then
		return byNick, hintNick, "nick"
	end

	
	if myIdent.serverId and not isOtherPlayer(myIdent.serverId) then
		return myIdent.serverId, myIdent.serverNick or hintNick or nickOf(myIdent.serverId), "server"
	end

	
	local g = myIdent.q and myIdent.q.guess

	if g and not hintNick and not isOtherPlayer(g.id) then
		return g.id, g.nick, "idcmd?"
	end

	
	local cands = {}

	local function add(id, src, prio)
		if not validId(id) then
			return
		end

		for _, c in ipairs(cands) do
			if c.id == id then
				c.votes = c.votes + 1
				c.src = c.src .. "+" .. src
				c.prio = math.max(c.prio, prio)
				return
			end
		end

		cands[#cands + 1] = { id = id, src = src, prio = prio, votes = 1 }
	end

	add(idByHandle(), "game", 3)
	add(idByScan(), "scan", 2)
	add(myIdent.initId, "init", 1)

	local best, bestScore = nil, nil

	for _, c in ipairs(cands) do
		local nick = nickOf(c.id)
		local score = c.prio + (c.votes - 1) * 4

		if isOtherPlayer(c.id) then
			score = score - 100   
		end

		if hintNick then
			if nick == hintNick then
				score = score + 10
			elseif nick then
				score = score - (strongNick and 100 or 5)
			end
		end

		c.nick = nick

		if not bestScore or score > bestScore then
			best, bestScore = c, score
		end
	end

	if best and bestScore > -50 then
		return best.id, best.nick or hintNick, best.src .. "?"
	end

	
	if best then
		return best.id, best.nick or hintNick, best.src .. "?"
	end

	return nil, hintNick, "none"
end

local function refreshIdentity(force)
	local now = monoClock()

	if not force and now - myIdent.checkedAt < 2 then
		return
	end

	myIdent.checkedAt = now

	local id, nick, source = resolveIdentity()

	if id then
		myIdent.id = id
		myIdent.lastGoodId = id
	end

	if nick then
		myIdent.nick = nick
	end

	myIdent.source = source

	local logLine = tostring(id) .. " / " .. tostring(nick) .. " / " .. tostring(source)

	if logLine ~= myIdent.lastLog then
		myIdent.lastLog = logLine
		dbg("my id = " .. tostring(id) .. ", nick = " .. tostring(nick) .. " (" .. tostring(source) .. ")")
	end

	
	local vq = myIdent.q and myIdent.q.verified
	local confirmed = (vq and vq.nick) or myIdent.joinNick or myIdent.serverNick

	if myIdent.configLoaded and confirmed and confirmed ~= myIdent.savedNick then
		myIdent.savedNick = confirmed
		pcall(saveConfig)
	end
end

local function getMyId()
	if myIdent.manualId then
		return myIdent.manualId
	end

	refreshIdentity(false)

	return myIdent.id or myIdent.lastGoodId or 0
end

local function getMyNickname()
	if myIdent.manualId then
		return myIdent.joinNick or myIdent.serverNick or nickOf(myIdent.manualId) or myIdent.nick or ""
	end

	refreshIdentity(false)

	return myIdent.nick or nickOf(myIdent.id) or ""
end

local function setServerIdentity(id, nick)
	if not validId(id) or isOtherPlayer(id) then
		return
	end

	if myIdent.serverId ~= id or (nick and myIdent.serverNick ~= nick) then
		myIdent.serverId = id
		myIdent.serverNick = nick or myIdent.serverNick
		myIdent.checkedAt = -100
		dbg("server shows my id = " .. tostring(id) .. " (" .. tostring(myIdent.serverNick) .. ")")
	end
end


local function rememberOutgoing(text)
	text = stripColors(tostring(text or ""))
	local body = trim((text:gsub("^/%S*%s*", "")))

	if #body < 4 then
		return
	end

	local list = myIdent.outgoing
	list[#list + 1] = { text = body, at = monoClock() }

	if #list > 6 then
		table.remove(list, 1)
	end
end


local function inOwnText(fragment)
	for _, o in ipairs(myIdent.outgoing) do
		if o.text:find(fragment, 1, true) then
			return true
		end
	end

	return false
end

local function isOwnEcho(text, exact)
	local now = monoClock()

	for i = #myIdent.outgoing, 1, -1 do
		local o = myIdent.outgoing[i]

		if now - o.at <= 8 then
			if exact then
				if trim(text) == o.text then
					return true
				end
			else
				
				local plain = (o.text:gsub(":[^:%s]+:", "\1"))

				for chunk in plain:gmatch("[^\1]+") do
					chunk = trim(chunk)

					if #chunk >= 8 and text:find(chunk:sub(1, 40), 1, true) then
						return true
					end
				end
			end
		end
	end

	return false
end


local function findIdAfterNick(text, nick)
	local pos = 1

	while true do
		local s, e = text:find(nick, pos, true)

		if not s then
			return nil
		end

		local before = s > 1 and text:sub(s - 1, s - 1) or ""
		local digits = text:match("^%s?%[(%d+)%]", e + 1)

		if digits and not before:match("[%w_]") and not inOwnText(nick .. "[" .. digits .. "]") then
			local id = tonumber(digits)

			if validId(id) then
				return id
			end
		end

		pos = e + 1
	end
end

local function learnIdentityFromServerText(text)
	if not text or text == "" then
		return
	end

	local nick = ownNickGuess()

	if nick then
		local id = findIdAfterNick(text, nick)

		if id then
			setServerIdentity(id, nick)
		end

		return
	end

	
	if #myIdent.outgoing == 0 or not isOwnEcho(text, false) then
		return
	end

	local found = nil

	for n, d in text:gmatch("([%w_]+)%[(%d+)%]") do
		local id = tonumber(d)

		if validId(id) and validNick(n) and not isOtherPlayer(id) and not inOwnText(n .. "[" .. d .. "]") then
			if found and found.id ~= id then
				return   
			end

			found = { id = id, nick = n }
		end
	end

	if found then
		setServerIdentity(found.id, found.nick)
	end
end

local function resetConnectionIdentity()
	myIdent.remote = {}
	myIdent.initId = nil
	myIdent.serverId = nil
	myIdent.serverNick = nil
	myIdent.checkedAt = -100

	if myIdent.resetQuery then
		myIdent.resetQuery()
	end
end

function sampev.onSendClientJoin(version, mod, nickname)
	resetConnectionIdentity()

	if validNick(nickname) then
		myIdent.joinNick = nickname
		myIdent.savedNick = nickname
	end

	dbg("connecting as " .. tostring(nickname))
end

function sampev.onInitGame(playerId)
	resetConnectionIdentity()
	myIdent.initId = validId(playerId) and playerId or nil
	dbg("onInitGame: id = " .. tostring(playerId))
end

function sampev.onPlayerJoin(playerId, color, isNpc, nickname)
	if not validId(playerId) then
		return
	end

	
	if nickname and nickname == myIdent.joinNick then
		setServerIdentity(playerId, nickname)
		return
	end

	myIdent.remote[playerId] = tostring(nickname or "?")

	if myIdent.serverId == playerId then
		myIdent.serverId = nil
	end

	if myIdent.id == playerId then
		myIdent.checkedAt = -100
	end
end

function sampev.onPlayerQuit(playerId)
	if validId(playerId) then
		myIdent.remote[playerId] = nil
	end
end

function sampev.onSendChat(message)
	rememberOutgoing(message)
end

function sampev.onSendCommand(command)
	rememberOutgoing(command)
end


function sampev.onChatMessage(playerId, text)
	if validId(playerId) and text and #myIdent.outgoing > 0 and isOwnEcho(stripColors(text), true) then
		setServerIdentity(playerId, nil)
	end
end


myIdent.validNick           = validNick
myIdent.refresh             = refreshIdentity
myIdent.getId               = getMyId
myIdent.getNick             = getMyNickname
myIdent.idByHandle          = idByHandle
myIdent.idByScan            = idByScan
myIdent.nickOf              = nickOf
myIdent.learnFromServerText = learnIdentityFromServerText


function myIdent.pinId(id)
	local nick = nickOf(id)

	if myIdent.q then
		myIdent.q.verified = nil
		myIdent.q.tries = 99   
	end

	if not validNick(nick) then
		myIdent.manualId = id   
		return false, nick
	end

	myIdent.manualId = nil
	myIdent.savedNick = nick
	myIdent.warned = true
	myIdent.checkedAt = -100
	pcall(saveConfig)

	return true, nick
end












local Q = {
	busy     = false,
	waiting  = nil,
	reply    = nil,
	cache    = {},    
	lastSend = -100,
	verified = nil,   
	guess    = nil,   
	tries    = 0,
	nextTry  = 0,
	epoch    = 0,     
}
myIdent.q = Q


function Q.parse(text)
	text = text:gsub("{%x%x%x%x%x%x%x%x}", ""):gsub("{%x%x%x%x%x%x}", "")

	local id, rest = text:match("[Ii][Dd]:%s*(%d+)%s*|%s*[^:|]-:%s*(.+)$")

	if not id then
		return nil
	end

	local nick = rest:match("^(%S+)")

	if not nick then
		return nil
	end

	return { id = tonumber(id), nick = nick, device = rest:match("%s%[([^%]]+)%]%s*$") }
end


function Q.ownNicks()
	local set = {}

	for _, n in ipairs({ myIdent.joinNick, myIdent.serverNick, myIdent.savedNick }) do
		if validNick(n) then
			set[n:lower()] = true
		end
	end

	return set
end


function Q.confirm(r)
	if not r or not validId(r.id) or not validNick(r.nick) then
		return false
	end

	local old = Q.verified

	if old and old.id == r.id and old.nick == r.nick then
		return true
	end

	Q.verified = { id = r.id, nick = r.nick, device = r.device }
	Q.guess = nil
	myIdent.checkedAt = -100
	dbg("id confirmed by server: " .. tostring(r.id) .. " / " .. tostring(r.nick))

	if myIdent.savedNick ~= r.nick then
		myIdent.savedNick = r.nick
		pcall(saveConfig)
	end

	return true
end


function myIdent.onIdReply(text)
	
	if Q.waiting and not Q.reply and text:find("\205\232\247\229\227\238 \237\229 \237\224\233\228\229\237\238") then
		Q.reply = { notfound = true }
		return false
	end

	local r = Q.parse(text)

	if not r then
		return false
	end

	
	if Q.ownNicks()[r.nick:lower()] then
		Q.confirm(r)

		if Q.waiting and not Q.reply and tostring(Q.waiting):lower() == r.nick:lower() then
			Q.reply = r
		end

		return false
	end

	
	local w = Q.waiting

	if w and not Q.reply and w:match("^%d+$") and r.id == tonumber(w) then
		Q.reply = r
	end

	return false
end


function Q.ask(arg)
	arg = tostring(arg)

	local key = arg:lower()
	local e = Q.cache[key]

	if e and monoClock() < e.till then
		return e.r
	end

	local gap = 2.0 - (monoClock() - Q.lastSend)

	if gap > 0 then
		wait(math.floor(gap * 1000))
	end

	
	if Q.verified then
		return nil
	end

	Q.reply = nil
	Q.waiting = arg
	Q.lastSend = monoClock()
	sampSendChat("/id " .. arg)

	local deadline = monoClock() + 6.0

	while monoClock() < deadline and not Q.reply and not Q.verified do
		wait(50)
	end

	local r = Q.reply
	local timedOut = r == nil

	if r and r.notfound then
		r = nil
		timedOut = false
	end

	Q.waiting, Q.reply = nil, nil

	
	if r then
		Q.cache[key] = { r = r, till = monoClock() + 60 }
	elseif not timedOut then
		Q.cache[key] = { r = nil, till = monoClock() + 15 }
	end

	return r
end


function Q.find()
	local epoch = Q.epoch
	local nicks, seen = {}, {}

	for _, n in ipairs({ myIdent.joinNick, myIdent.savedNick, myIdent.serverNick }) do
		if validNick(n) and not seen[n:lower()] then
			seen[n:lower()] = true
			nicks[#nicks + 1] = n
		end
	end

	
	for _, n in ipairs(nicks) do
		local r = Q.ask(n)

		if epoch ~= Q.epoch then
			return nil
		end

		if Q.verified then
			return Q.verified, nil
		end

		if r and r.nick:lower() == n:lower() then
			return r, nil
		end
	end

	if #nicks > 0 then
		return nil, nil
	end

	
	local okScan, scan = pcall(idByScan)
	local cands = { myIdent.initId, okScan and scan or nil }

	for _, id in ipairs(cands) do
		local r = Q.ask(id)

		if epoch ~= Q.epoch then
			return nil
		end

		if Q.verified then
			return Q.verified, nil
		end

		if r and not (r.device and r.device:lower():find("pc", 1, true)) and validNick(r.nick) then
			return r, nil   
		end
	end

	return nil, nil
end


function myIdent.autoTick(spawned)
	if not spawned or Q.verified or Q.busy or monoClock() < Q.nextTry then
		return
	end

	Q.busy = true
	Q.tries = Q.tries + 1

	local epoch = Q.epoch

	lua_thread.create(function()
		local ok, r, g = pcall(Q.find)

		if epoch ~= Q.epoch then
			return   
		end

		Q.busy, Q.waiting, Q.reply = false, nil, nil

		if ok and r then
			Q.confirm(r)
		else
			if ok and g and not Q.verified then
				Q.guess = { id = g.id, nick = g.nick, device = g.device }
				myIdent.checkedAt = -100
			end

			Q.nextTry = monoClock() + math.min(60, 8 * Q.tries)
		end
	end)
end


function myIdent.resetQuery()
	Q.epoch = Q.epoch + 1
	Q.verified, Q.guess, Q.tries, Q.nextTry, Q.cache = nil, nil, 0, 0, {}
	Q.busy, Q.waiting, Q.reply = false, nil, nil
end
end

local function substituteVariables(text)
	local nickname = myIdent.getNick()
	local id = myIdent.getId()

	
	local function esc(v) return (tostring(v):gsub("%%", "%%%%")) end

	text = text:gsub("{name}", esc(nickname))
	text = text:gsub("{id}", esc(id))
	text = text:gsub(":lavka:", esc(":lavka" .. tostring(id) .. ":"))
	text = text:gsub(":call1:", esc(":call" .. trim(phoneNumber1.v) .. ":"))
	text = text:gsub(":call2:", esc(":call" .. trim(phoneNumber2.v) .. ":"))

	return text
end

local phoneErrorUntil    = 0
local phoneErrorLastChat = 0
local phoneErrorIndex    = 1
local phoneStopRequested = false

local function missingPhoneIn(text)
	if not text or text == "" then
		return nil
	end

	if text:find(":call1:", 1, true) and trim(phoneNumber1.v) == "" then
		return 1
	end

	if text:find(":call2:", 1, true) and trim(phoneNumber2.v) == "" then
		return 2
	end

	return nil
end

local function isPhoneConfigured()
	return trim(phoneNumber1.v) ~= "" or trim(phoneNumber2.v) ~= ""
end

local function reportPhoneNotConfigured(stopRunning)
	local now = monoClock()

	if stopRunning then
		phoneStopRequested = true
	end

	if now - phoneErrorLastChat < 5 then
		return
	end

	phoneErrorLastChat = now
	phoneErrorIndex    = 0
	phoneErrorUntil    = now + 6
	activeTab          = 3

	sampAddChatMessage("{FF0000}|{FFFFFF} \206\248\232\225\234\224: \243\234\224\230\232\242\229 \237\238\236\229\240 \242\229\235\229\244\238\237\224 \226 \237\224\241\242\240\238\233\234\224\245 (/vpr - \205\224\241\242\240\238\233\234\232)", -1)
end

local function findMissingPhone()
	for _, block in ipairs(blocks) do
		if block.enabled.v then
			local idx = missingPhoneIn(block.buffer.v)

			if idx then
				return idx
			end
		end
	end

	for _, group in ipairs(vrGroups) do
		if group.enabled.v then
			for _, msgObj in ipairs(group.messages) do
				local idx = missingPhoneIn(msgObj.buffer.v)

				if idx then
					return idx
				end
			end
		end
	end

	return nil
end

local function reportMissingPhone(index, stopRunning)
	local now = monoClock()

	if stopRunning then
		phoneStopRequested = true
	end

	if now - phoneErrorLastChat < 5 then
		return
	end

	phoneErrorLastChat = now
	phoneErrorIndex    = index
	phoneErrorUntil    = now + 6
	activeTab          = 3

	sampAddChatMessage("{FF0000}|{FFFFFF} \206\248\232\225\234\224: \243\234\224\230\232\242\229 \237\238\236\229\240 \242\229\235\229\244\238\237\224 " .. index .. " \226 \237\224\241\242\240\238\233\234\224\245 (/vpr - \205\224\241\242\240\238\233\234\232)", -1)
end

function applyStyle()
	local style = imgui.GetStyle()

	local function setCol(name, value)
		pcall(function()
			local idx = imgui.Col[name]
			if idx ~= nil then
				style.Colors[idx] = value
			end
		end)
	end

	local function setStyle(name, value)
		pcall(function() style[name] = value end)
	end

	setCol("WindowBg",             UI.BG)
	setCol("ChildWindowBg",        UI.CLEAR)
	setCol("ChildBg",              UI.CLEAR)
	setCol("PopupBg",              imgui.ImVec4(0.075, 0.075, 0.100, 0.98))
	setCol("Border",               UI.BORDER)
	setCol("Text",                 UI.TEXT)
	setCol("TextSelectedBg",       imgui.ImVec4(0.91, 0.16, 0.22, 0.35))
	setCol("Button",               UI.BTN)
	setCol("ButtonHovered",        UI.BTN_HOVER)
	setCol("ButtonActive",         UI.BTN_ACTIVE)
	setCol("FrameBg",              UI.FIELD)
	setCol("FrameBgHovered",       UI.FIELD_HOV)
	setCol("FrameBgActive",        UI.FIELD_ACT)
	setCol("CheckMark",            UI.RED)
	setCol("ScrollbarBg",          UI.CLEAR)
	setCol("ScrollbarGrab",        imgui.ImVec4(0.91, 0.16, 0.22, 0.45))
	setCol("ScrollbarGrabHovered", imgui.ImVec4(0.91, 0.16, 0.22, 0.75))
	setCol("ScrollbarGrabActive",  UI.RED)

	setStyle("WindowRounding",    (14 * UI_SCALE))
	setStyle("ChildWindowRounding", (10 * UI_SCALE))
	setStyle("ChildRounding",     (10 * UI_SCALE))
	setStyle("FrameRounding",     (8 * UI_SCALE))
	setStyle("GrabRounding",      (8 * UI_SCALE))
	setStyle("ScrollbarRounding", (6 * UI_SCALE))
	setStyle("ScrollbarSize",     (6 * UI_SCALE))
	setStyle("WindowPadding",     imgui.ImVec2((10 * UI_SCALE), (8 * UI_SCALE)))
	setStyle("FramePadding",      imgui.ImVec2((8 * UI_SCALE), (4 * UI_SCALE)))
	setStyle("ItemSpacing",       imgui.ImVec2((8 * UI_SCALE), (8 * UI_SCALE)))
end

function saveConfig()
	ensureDir(BASE .. "/config")
	ensureDir(CONFIG_DIR)

	local data = {
		autoskip_dialog = autoSkipDialog.v,
		autostart       = autoStartEnabled.v,
		phone1          = phoneNumber1.v,
		phone2          = phoneNumber2.v,
		my_nick         = myIdent.savedNick,
		blocks          = {},
		vr_groups       = {},
	}

	for _, block in ipairs(blocks) do
		table.insert(data.blocks, {
			channel_index  = block.channelIndex,
			custom_channel = block.customChannel.v,
			text           = u8:decode(block.buffer.v),
			enabled        = block.enabled.v,
			timer          = block.timer.v,
			use_seconds    = block.use_seconds.v,
		})
	end

	for _, group in ipairs(vrGroups) do
		local messages = {}

		for _, msgObj in ipairs(group.messages) do
			table.insert(messages, u8:decode(msgObj.buffer.v))
		end

		table.insert(data.vr_groups, {
			enabled  = group.enabled.v,
			messages = messages,
		})
	end

	local ok, encoded = pcall(function() return json.encode(data, {indent = true}) end)

	if not ok or not encoded then
		ok, encoded = pcall(function() return json.encode(data) end)
	end

	if not ok or not encoded then
		sampAddChatMessage("{FF0000}|{FFFFFF} \206\248\232\225\234\224 \241\238\245\240\224\237\229\237\232\255 \237\224\241\242\240\238\229\234.", -1)
		return
	end

	local file = io.open(CONFIG_PATH, "w")

	if not file then
		sampAddChatMessage("{FF0000}|{FFFFFF} \206\248\232\225\234\224 \241\238\245\240\224\237\229\237\232\255 \237\224\241\242\240\238\229\234.", -1)
		return
	end

	file:write(encoded)
	file:close()
end

local function maybeAutoSave()
	local now = os.time()

	if now - lastAutoSaveTime >= AUTOSAVE_INTERVAL_SEC then
		lastAutoSaveTime = now
		saveConfig()
	end
end

function loadConfig()
	if not doesFileExist(CONFIG_PATH) then
		return
	end

	local file = io.open(CONFIG_PATH, "r")

	if not file then
		return
	end

	local content = file:read("*a")
	file:close()

	local ok, data = pcall(function() return json.decode(content) end)

	if not ok or type(data) ~= "table" then
		return
	end

	autoSkipDialog.v = data.autoskip_dialog and true or false
	autoStartEnabled.v = data.autostart and true or false
	phoneNumber1.v = data.phone1 or ""
	phoneNumber2.v = data.phone2 or ""

	if not myIdent.savedNick and myIdent.validNick(data.my_nick) then
		myIdent.savedNick = data.my_nick
	end

	if type(data.blocks) == "table" then
		for _, item in ipairs(data.blocks) do
			createBlock(item.channel_index, item.custom_channel, item.text, item.enabled, item.timer, item.use_seconds)
		end
	end

	if type(data.vr_groups) == "table" then
		for _, item in ipairs(data.vr_groups) do
			local group = createVrGroup(item.enabled)

			if type(item.messages) == "table" then
				for _, text in ipairs(item.messages) do
					createGroupMessage(group, text)
				end
			end
		end
	end
end

function cleanupOldMessages()
	local now = getTimeMs()

	for text, sentAt in pairs(recentScriptMessages) do
		if now - sentAt > SCRIPT_MESSAGE_TTL_MS then
			recentScriptMessages[text] = nil
		end
	end
end

function isScriptMessage(text)
	cleanupOldMessages()
	return recentScriptMessages[text] ~= nil
end

local function markOwnAd(fullText)
	lastSentText = fullText
	lastSentChannel = "vr"
	awaitingOwnMessageDialog = true
	awaitingSecondDialog = false
	recentScriptMessages[fullText] = getTimeMs()
end

local function clearOwnAd()
	awaitingOwnMessageDialog = false
	awaitingSecondDialog = false
	recentScriptMessages = {}
end

function sendBlock(block)
	if not (block.enabled.v and string.len(block.buffer.v) > 0) then
		return false
	end

	local missingPhone = missingPhoneIn(block.buffer.v)

	if missingPhone then
		reportMissingPhone(missingPhone, true)
		return false
	end

	local channel = resolveChannel(block)
	local message = substituteVariables(u8:decode(block.buffer.v))
	local fullText = channel ~= "" and ("/" .. channel .. " " .. message) or message

	local intervalMs = block.use_seconds.v and block.timer.v * 1000 or block.timer.v * 60 * 1000
	block.next_send_time    = getTimeMs() + intervalMs + SEND_DELAY_SEC * 1000
	block.last_sent         = os.time()
	block.pause_start_time  = 0
	block.show_paused       = false
	block.ready_after_pause = false
	block.was_sent          = true

	lastSentEntity = block

	if fullText:sub(1, 4):lower() == "/vr " then
		markOwnAd(fullText)
	end

	lua_thread.create(function()
		wait(SEND_THREAD_DELAY_MS)
		sampSendChat(fullText)
		wait(100)
		sampAddChatMessage("{FF0000}|{FFFFFF} \206\242\239\240\224\226\235\229\237\238: " .. (channel ~= "" and channel:upper() or "chat"), -1)
	end)

	return true
end

function sendGroupMessage(group)
	if not group.enabled.v then
		return false
	end

	local idx = findNextGroupMessageIndex(group)

	if not idx then
		return false
	end

	local msgObj = group.messages[idx]

	local missingPhone = missingPhoneIn(msgObj.buffer.v)

	if missingPhone then
		reportMissingPhone(missingPhone, true)
		return false
	end

	local message = substituteVariables(u8:decode(msgObj.buffer.v))
	local fullText = "/vr " .. message

	markOwnAd(fullText)
	lastVrGroup = group
	lastSentEntity = group

	group.next_send_time    = getTimeMs() + VR_INTERVAL_MS + SEND_DELAY_SEC * 1000
	group.last_sent         = os.time()
	group.pause_start_time  = 0
	group.show_paused       = false
	group.ready_after_pause = false
	group.was_sent          = true
	group.currentIndex      = idx % #group.messages + 1

	lua_thread.create(function()
		wait(SEND_THREAD_DELAY_MS)
		sampSendChat(fullText)
		wait(100)
		sampAddChatMessage("{FF0000}|{FFFFFF} \206\242\239\240\224\226\235\229\237\238: VR", -1)
	end)

	return true
end

function checkMessages()
	local nowMs = getTimeMs()
	local nowSec = os.time()

	cleanupOldMessages()

	if not primingDone then
		local senders = {}

		for _, block in ipairs(blocks) do
			table.insert(senders, { kind = "block", ref = block })
		end

		for _, group in ipairs(vrGroups) do
			table.insert(senders, { kind = "group", ref = group })
		end

		if primingIndex <= #senders then
			local item = senders[primingIndex]
			local enabled = item.ref.enabled.v
			local nonEmpty

			if item.kind == "block" then
				nonEmpty = string.len(item.ref.buffer.v) > 0
			else
				nonEmpty = findNextGroupMessageIndex(item.ref) ~= nil
			end

			local readyByCooldown = nowMs >= item.ref.next_send_time

			if enabled and nonEmpty and readyByCooldown then
				if primingStageTime == 0 then
					item.ref.was_sent = false
					local sent

					if item.kind == "block" then
						sent = sendBlock(item.ref)
					else
						sent = sendGroupMessage(item.ref)
					end

					if sent then
						primingStageTime = nowSec
					end
				elseif nowSec - primingStageTime >= PRIMING_GAP_SEC then
					primingIndex = primingIndex + 1
					primingStageTime = 0
				end
			else
				primingIndex = primingIndex + 1
			end
		else
			primingDone = true
		end

		return
	end

	for _, block in ipairs(blocks) do
		if block.enabled.v and string.len(block.buffer.v) > 0
			and not block.show_paused and not block.ready_after_pause
			and (nowMs >= block.next_send_time or not block.was_sent)
			and sendBlock(block)
		then
			return true
		end
	end

	for _, group in ipairs(vrGroups) do
		if group.enabled.v and findNextGroupMessageIndex(group) ~= nil
			and not group.show_paused and not group.ready_after_pause
			and (nowMs >= group.next_send_time or not group.was_sent)
			and sendGroupMessage(group)
		then
			return true
		end
	end
end

local function updateEntityPauseState(entity, isReady)
	local nowSec = os.time()

	if not isReady then
		return
	end

	if not running and entity.pause_start_time > 0 then
		if nowSec - entity.pause_start_time < 3 then
			entity.show_paused = true
			entity.ready_after_pause = false
		else
			entity.show_paused = false
			entity.ready_after_pause = true
		end
	elseif running then
		entity.show_paused = false
		entity.ready_after_pause = false
	end
end

function updateStatuses()
	for _, block in ipairs(blocks) do
		updateEntityPauseState(block, block.enabled.v and string.len(block.buffer.v) > 0)
	end

	for _, group in ipairs(vrGroups) do
		updateEntityPauseState(group, group.enabled.v and findNextGroupMessageIndex(group) ~= nil)
	end
end

function getTimeLeftDisplay(entity)
	local msLeft = entity.next_send_time - getTimeMs()

	if msLeft <= 0 then
		return "\195\238\242\238\226\238", THEME.TEXT_READY, ICON.CHECK
	end

	local secLeft = math.ceil(msLeft / 1000)
	local minutes = math.floor(secLeft / 60)
	local seconds = secLeft % 60
	local label

	if minutes > 0 then
		label = minutes .. " \236\232\237 " .. seconds .. " \241\229\234"
	else
		label = seconds .. " \241\229\234"
	end

	return label, THEME.TEXT_WAITING, ICON.CLOCK
end

local function setFontScale(scale)
	pcall(imgui.SetWindowFontScale, scale)
end

local function textAt(x, y, color, text, scale)
	if scale then
		setFontScale(scale)
	end

	imgui.SetCursorScreenPos(V2(x, y))
	pushCol(imgui.Col.Text, color)
	imgui.Text(text)
	imgui.PopStyleColor()

	if scale then
		setFontScale(1.0)
	end
end

local function textWidth(text, scale)
	if scale then
		setFontScale(scale)
	end

	local w = imgui.CalcTextSize(text).x

	if scale then
		setFontScale(1.0)
	end

	return w
end

local function drawToggleSwitch(id, boolVar, width, height, onColor)
	width = width or (44 * UI_SCALE)
	height = height or (22 * UI_SCALE)
	onColor = onColor or UI.RED

	if toggleAnimState[id] == nil then
		toggleAnimState[id] = boolVar.v and 1 or 0
	end

	local target = boolVar.v and 1 or 0
	toggleAnimState[id] = toggleAnimState[id] + (target - toggleAnimState[id]) * 0.25

	pushID(id)

	local pos = imgui.GetCursorScreenPos()
	local clicked = imgui.InvisibleButton("##toggle", imgui.ImVec2(width, height)) and Touch.tapAllowed()

	if clicked then
		boolVar.v = not boolVar.v
	end

	pcall(function()
		local drawList = imgui.GetWindowDrawList()
		local t = toggleAnimState[id]

		local bgColor = imgui.ImVec4(
			0.19 + (onColor.x - 0.19) * t,
			0.19 + (onColor.y - 0.19) * t,
			0.245 + (onColor.z - 0.245) * t,
			1
		)

		if t > 0.05 then
			drawList:AddRectFilled(
				imgui.ImVec2(pos.x - 2, pos.y - 2),
				imgui.ImVec2(pos.x + width + 2, pos.y + height + 2),
				c32(imgui.ImVec4(onColor.x, onColor.y, onColor.z, 0.16 * t)), height / 2 + 2
			)
		end

		drawList:AddRectFilled(pos, imgui.ImVec2(pos.x + width, pos.y + height), c32(bgColor), height / 2)

		local knobRadius = (height - (6 * UI_SCALE)) / 2
		local knobX = pos.x + knobRadius + (3 * UI_SCALE) + t * (width - height)
		local knobY = pos.y + height / 2

		addCircleFilled(drawList, imgui.ImVec2(knobX, knobY), knobRadius, c32(imgui.ImVec4(1, 1, 1, 1)))
	end)

	imgui.PopID()

	return clicked
end

local function drawVariableChips(x, y)
	local label = u8("\210\229\227\232:")

	pcall(function()
		imgui.GetWindowDrawList():AddText(V2(x, y + (5 * UI_SCALE)), c32(UI.MUTED), label)
	end)

	local labelWidth = imgui.CalcTextSize(label).x
	imgui.SetCursorScreenPos(V2(x + labelWidth + (12 * UI_SCALE), y))

	pushCol(imgui.Col.Button, imgui.ImVec4(0.91, 0.16, 0.22, 0.14))
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(0.91, 0.16, 0.22, 0.28))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(0.91, 0.16, 0.22, 0.40))
	pushCol(imgui.Col.Text, imgui.ImVec4(1.00, 0.68, 0.72, 1))
	pushVar(imgui.StyleVar.FrameRounding, (13 * UI_SCALE))
	pushVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2((6 * UI_SCALE), (6 * UI_SCALE)))

	for i, item in ipairs(VARIABLES) do
		if i > 1 then
			imgui.SameLine()
		end

		local chipLabel = item.icon and (item.icon .. u8("  ") .. item.label) or item.label

		if imgui.Button(chipLabel, imgui.ImVec2(0, (26 * UI_SCALE))) then
			local blockedPhoneIndex = nil

			if item.tag == ":call1:" and trim(phoneNumber1.v) == "" then
				blockedPhoneIndex = 1
			elseif item.tag == ":call2:" and trim(phoneNumber2.v) == "" then
				blockedPhoneIndex = 2
			end

			if blockedPhoneIndex then
				reportMissingPhone(blockedPhoneIndex, false)
			elseif activeInputBuffer then
				activeInputBuffer.v = activeInputBuffer.v .. item.tag
			end
		end

		if imgui.IsItemHovered() then
			imgui.SetTooltip(item.desc)
		end
	end

	imgui.PopStyleVar(2)
	imgui.PopStyleColor(4)
end

local FIELD_BG        = UI.FIELD
local FIELD_BG_HOVER  = UI.FIELD_HOV
local FIELD_BG_ACTIVE = UI.FIELD_ACT



local function drawTagOverlayPlain(text, textStartX, textY, editing, rightEdge, frameTop, frameBottom)
	if editing or not text or text == "" or not rightEdge or not frameTop or not frameBottom then
		return
	end

	
	local parts = {}
	local pos = 1

	while pos <= #text do
		local bs, be, bitem

		for _, item in ipairs(VARIABLES) do
			local a, b = text:find(item.tag, pos, true)

			if a and (not bs or a < bs) then
				bs, be, bitem = a, b, item
			end
		end

		if not bs then
			parts[#parts + 1] = { text = text:sub(pos) }
			break
		end

		if bs > pos then
			parts[#parts + 1] = { text = text:sub(pos, bs - 1) }
		end

		parts[#parts + 1] = { item = bitem }
		pos = be + 1
	end

	local hasTag = false

	for _, part in ipairs(parts) do
		if part.item then
			hasTag = true
		end
	end

	if not hasTag then
		return
	end

	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()
	local clipL = textStartX - 2 * UI_SCALE
	local clipR = rightEdge - 6 * UI_SCALE

	pcall(function()
		dl:PushClipRect(V2(clipL, frameTop), V2(clipR, frameBottom), true)

		
		dl:AddRectFilled(V2(clipL, frameTop + 2 * UI_SCALE), V2(clipR, frameBottom - 2 * UI_SCALE), c32(UI.FIELD), 4 * UI_SCALE)

		local x = textStartX

		for _, part in ipairs(parts) do
			if part.item then
				local item = part.item
				local label = (item.icon and item.icon ~= "") and (item.icon .. u8(" ") .. item.label) or item.label
				local w = imgui.CalcTextSize(label).x + 14 * UI_SCALE
				local top = textY - 2 * UI_SCALE

				dl:AddRectFilled(V2(x, top), V2(x + w, top + lineH + 4 * UI_SCALE), c32(imgui.ImVec4(0.36, 0.11, 0.16, 1)), 5 * UI_SCALE)
				dl:AddRect(V2(x, top), V2(x + w, top + lineH + 4 * UI_SCALE), c32(imgui.ImVec4(0.70, 0.22, 0.30, 1)), 5 * UI_SCALE)
				dl:AddText(V2(x + 7 * UI_SCALE, textY), c32(imgui.ImVec4(1.00, 0.68, 0.72, 1)), label)

				x = x + w + 3 * UI_SCALE
			else
				dl:AddText(V2(x, textY), c32(UI.TEXT), part.text)
				x = x + imgui.CalcTextSize(part.text).x
			end
		end

		dl:PopClipRect()
	end)
end






local tagMode = nil   
local TAG_CHIP_GAP = 2 * UI_SCALE

local function ensureTagMode()
	if tagMode then
		return tagMode
	end

	tagMode = "plain"

	if not (HAS_ICONS and tagFontReady) then
		dbg("tag mode: plain, icons=" .. tostring(HAS_ICONS) .. " fontReady=" .. tostring(tagFontReady))
		return tagMode
	end

	local naturals = {}

	for i, item in ipairs(VARIABLES) do
		if not item.ph or item.ph == "" or not item.icon or item.icon == "" then
			return tagMode
		end

		local okAdv, adv = pcall(function() return imgui.CalcTextSize(item.ph).x end)
		local okNat, nat = pcall(function() return imgui.CalcTextSize(item.icon).x end)

		
		if not okAdv or not okNat or adv < nat + 6 * UI_SCALE then
			dbg("tag mode: plain, advance " .. tostring(adv) .. " icon " .. tostring(nat))
			return tagMode
		end

		naturals[i] = nat
	end

	tagMode = "font"
	dbg("tag mode: font")

	for i, item in ipairs(VARIABLES) do
		item.glyph   = item.ph
		item.natural = naturals[i]
	end

	return tagMode
end

local measureCache, measureCacheSize = {}, 0

local function measureText(str)
	if str == "" then
		return 0
	end

	local cached = measureCache[str]

	if cached then
		return cached
	end

	local n = math.max(1, math.min(16, math.floor(2000 / #str)))
	local withText = imgui.CalcTextSize(string.rep(str .. "|", n)).x
	local onlyBars = imgui.CalcTextSize(string.rep("|", n)).x
	local w = (withText - onlyBars) / n

	if measureCacheSize > 500 then
		measureCache, measureCacheSize = {}, 0
	end

	measureCache[str] = w
	measureCacheSize = measureCacheSize + 1

	return w
end

local function fieldBgColor(active)
	if active then
		return FIELD_BG_ACTIVE
	end

	if imgui.IsItemHovered() then
		return FIELD_BG_HOVER
	end

	return FIELD_BG
end

local function findTagMatches(text)
	local matches = {}
	local searchStart = 1

	while searchStart <= #text do
		local bestStart, bestStop, bestItem, bestIsGlyph = nil, nil, nil, false

		for _, item in ipairs(VARIABLES) do
			local s, e = text:find(item.tag, searchStart, true)

			if s and (not bestStart or s < bestStart) then
				bestStart, bestStop, bestItem, bestIsGlyph = s, e, item, false
			end

			s, e = text:find(item.glyph, searchStart, true)

			if s and (not bestStart or s < bestStart) then
				bestStart, bestStop, bestItem, bestIsGlyph = s, e, item, true
			end
		end

		if not bestStart then
			break
		end

		matches[#matches + 1] = { start = bestStart, stop = bestStop, item = bestItem, isGlyph = bestIsGlyph }
		searchStart = bestStop + 1
	end

	return matches
end

local function drawTagOverlay(text, textStartX, textY, editing, rightEdge, frameTop, frameBottom)
	if ensureTagMode() ~= "font" then
		return drawTagOverlayPlain(text, textStartX, textY, editing, rightEdge, frameTop, frameBottom)
	end

	if not text or text == "" then
		return
	end

	local matches = findTagMatches(text)

	if #matches == 0 then
		return
	end

	
	if editing and rightEdge then
		if textStartX + measureText(text) > rightEdge - 26 * UI_SCALE then
			return
		end
	end

	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()
	local coverColor = c32(fieldBgColor(editing))
	local chipFill   = c32(imgui.ImVec4(0.36, 0.11, 0.16, 1))
	local chipBorder = c32(imgui.ImVec4(0.70, 0.22, 0.30, 1))
	local chipTextCol = c32(imgui.ImVec4(1.00, 0.68, 0.72, 1))
	local round = 5 * UI_SCALE
	local chipH = lineH + 4 * UI_SCALE

	local pushed = false

	pcall(function()
		if rightEdge and frameTop and frameBottom then
			dl:PushClipRect(V2(textStartX - 2 * UI_SCALE, frameTop), V2(rightEdge, frameBottom), true)
			pushed = true
		end

		for idx, m in ipairs(matches) do
			local item = m.item
			local raw = text:sub(m.start, m.stop)
			local iconOnly = item.icon
			local fullLabel = m.isGlyph and iconOnly or (iconOnly .. u8("  ") .. item.label)

			local fullWidth = measureText(fullLabel)
			local iconOnlyWidth = measureText(iconOnly)

			local chipLabel, chipLabelWidth, chipX, chipWidth, labelX
			local gap = 0

			chipX = textStartX + measureText(text:sub(1, m.start - 1))

			if m.isGlyph then
				chipWidth = measureText(raw)
				chipLabel, chipLabelWidth = iconOnly, iconOnlyWidth
				labelX = chipX + math.floor((chipWidth - (item.natural or iconOnlyWidth)) / 2 + 0.5)
				gap = TAG_CHIP_GAP
			else
				local rawWidth = measureText(raw)

				if editing then
					if fullWidth + 6 * UI_SCALE <= rawWidth then
						chipLabel, chipLabelWidth = fullLabel, fullWidth
					else
						chipLabel, chipLabelWidth = iconOnly, iconOnlyWidth
					end

					chipWidth = math.max(rawWidth, 4 * UI_SCALE)
				else
					local nextStart = matches[idx + 1] and matches[idx + 1].start or (#text + 1)
					local availableWidth = measureText(text:sub(m.start, nextStart - 1))

					if fullWidth + 10 * UI_SCALE <= availableWidth then
						chipLabel, chipLabelWidth = fullLabel, fullWidth
					else
						chipLabel, chipLabelWidth = iconOnly, iconOnlyWidth
					end

					chipWidth = math.min(availableWidth, math.max(rawWidth, chipLabelWidth + 10 * UI_SCALE))
				end

				labelX = chipX + (chipWidth - chipLabelWidth) / 2
			end

			local chipY = textY - 2 * UI_SCALE

			
			if m.isGlyph and frameTop and frameBottom then
				local textTop    = chipY
				local textBottom = chipY + chipH

				if textTop > frameTop then
					dl:AddRectFilled(V2(chipX - 2, frameTop), V2(chipX + chipWidth + 2, textTop), coverColor)
				end

				if frameBottom > textBottom then
					dl:AddRectFilled(V2(chipX - 2, textBottom), V2(chipX + chipWidth + 2, frameBottom), coverColor)
				end

				dl:AddRectFilled(V2(chipX + 1, textTop), V2(chipX + chipWidth - 1, textBottom), coverColor)
			end

			dl:AddRectFilled(V2(chipX + gap, chipY), V2(chipX + chipWidth - gap, chipY + chipH), chipFill, round)
			dl:AddText(V2(labelX, textY), chipTextCol, chipLabel)

			if m.isGlyph then
				dl:AddRect(V2(chipX + gap, chipY), V2(chipX + chipWidth - gap, chipY + chipH), chipBorder, round)
			end
		end
	end)

	if pushed then
		pcall(function() dl:PopClipRect() end)
	end
end

local viewBuffers   = setmetatable({}, { __mode = "k" })
local viewLastCanon = setmetatable({}, { __mode = "k" })

local function replacePlain(text, from, to)
	local out, pos = {}, 1

	while true do
		local s, e = text:find(from, pos, true)

		if not s then
			break
		end

		out[#out + 1] = text:sub(pos, s - 1)
		out[#out + 1] = to
		pos = e + 1
	end

	out[#out + 1] = text:sub(pos)

	return table.concat(out)
end

local function tagsToGlyphs(text)
	for _, item in ipairs(VARIABLES) do
		text = replacePlain(text, item.tag, item.glyph)
	end

	return text
end

local function glyphsToTags(text)
	for _, item in ipairs(VARIABLES) do
		text = replacePlain(text, item.glyph, item.tag)
	end

	return text
end

local function viewTextOf(buffer)
	local view = viewBuffers[buffer]

	return view and view.v or buffer.v
end





do
	local fieldWasActive = setmetatable({}, { __mode = "k" })
	local focusRequest = nil

	
	
	local inputCallback, inputCallbackFlags = nil, 0

	pcall(function()
		local function onInput(data)
			if Touch.caretToEnd then
				Touch.caretToEnd = false
				local len = data.BufTextLen
				data.CursorPos = len
				data.SelectionStart = len
				data.SelectionEnd = len
			end
		end

		local function cb(data)
			pcall(onInput, data)
			return 0
		end

		local flag = imgui.InputTextFlags.CallbackAlways

		if flag == nil then
			return
		end

		for _, ctype in ipairs({ "ImGuiInputTextCallback", "int (*)(ImGuiInputTextCallbackData*)" }) do
			local ok, ptr = pcall(ffi.cast, ctype, cb)

			if ok and ptr ~= nil then
				inputCallback, inputCallbackFlags = ptr, flag
				break
			end
		end
	end)

	
	function Touch.input(label, key, ptr, size)
		local pos = imgui.GetCursorScreenPos()
		local w = imgui.CalcItemWidth()
		local h = imgui.GetFrameHeight()

		if not fieldWasActive[key] and w > 1 and h > 1 then
			if imgui.InvisibleButton(label .. "_tap", V2(w, h)) and Touch.tapAllowed() then
				focusRequest = key
			end

			imgui.SetCursorScreenPos(pos)
		end

		if focusRequest == key then
			focusRequest = nil
			Touch.caretToEnd = true
			Touch.caretToEndDeadline = monoClock() + 1.5
			pcall(imgui.SetKeyboardFocusHere, 0)
		end

		if inputCallback then
			imgui.InputText(label, ptr, size, inputCallbackFlags, inputCallback)
		else
			imgui.InputText(label, ptr, size)
		end

		local active = imgui.IsItemActive()
		fieldWasActive[key] = active or nil

		if active then
			pcall(function()
				local mn, mx = imgui.GetItemRectMin(), imgui.GetItemRectMax()
				Touch.activeFieldRect = { mn.x, mn.y, mx.x, mx.y }
			end)
		end

		return active
	end

	
	if jit then
		pcall(jit.off, Touch.input, true)

		if type(imgui.InputText) == "function" then
			pcall(jit.off, imgui.InputText, true)
		end
	end
end

local function inputTextWithTags(label, buffer)
	local fontMode = ensureTagMode() == "font"

	pushCol(imgui.Col.FrameBg, FIELD_BG)
	pushCol(imgui.Col.FrameBgHovered, FIELD_BG_HOVER)
	pushCol(imgui.Col.FrameBgActive, FIELD_BG_ACTIVE)

	if not fontMode then
		Touch.input(label, buffer, buffer.ptr, buffer.size)
		imgui.PopStyleColor(3)
		return
	end

	local view = viewBuffers[buffer]

	if not view then
		view = ImBuffer(buffer.size)
		viewBuffers[buffer] = view
		viewLastCanon[buffer] = nil
	end

	
	local canon = buffer.v

	if viewLastCanon[buffer] ~= canon then
		view.v = tagsToGlyphs(canon)
	end

	Touch.input(label, buffer, view.ptr, view.size)
	imgui.PopStyleColor(3)

	local newCanon = glyphsToTags(view.v)

	if newCanon ~= canon then
		pcall(function() buffer.v = newCanon end)
	end

	viewLastCanon[buffer] = buffer.v

	
	if not imgui.IsItemActive() then
		local want = tagsToGlyphs(buffer.v)

		if view.v ~= want then
			view.v = want
		end
	end
end

local function drawChannelButton(block, preset)
	local c = preset.color

	pushVar(imgui.StyleVar.FrameRounding, (13 * UI_SCALE))
	pushCol(imgui.Col.Button, imgui.ImVec4(c.x, c.y, c.z, 0.16))
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(c.x, c.y, c.z, 0.30))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(c.x, c.y, c.z, 0.42))
	pushCol(imgui.Col.Text, c)

	local clicked = imgui.Button(preset.label, imgui.ImVec2((88 * UI_SCALE), (26 * UI_SCALE))) and Touch.tapAllowed()

	imgui.PopStyleColor(4)
	imgui.PopStyleVar()

	if preset.key == "custom" then
		Touch.tooltip(u8("\202\235\232\234 - \241\236\229\237\232\242\252 \234\224\237\224\235\nCUSTOM: \242\229\234\241\242 \238\242\239\240\224\226\235\255\229\242\241\255 \234\224\234 \229\241\242\252,\n\241\226\238\254 \234\238\236\224\237\228\243 (\237\224\239\240\232\236\229\240 /o) \239\232\248\232 \239\240\255\236\238 \226 \241\238\238\225\249\229\237\232\232"))
	else
		Touch.tooltip(u8("\202\235\232\234 - \241\236\229\237\232\242\252 \234\224\237\224\235"))
	end

	if clicked then
		block.channelIndex = block.channelIndex % #CHANNEL_PRESETS + 1
	end
end

local repeatState = {}

local function repeatButton(id, label, size)
	local now = getTimeMs()
	local clicked = imgui.Button(label, size) and Touch.tapAllowed()
	local held = imgui.IsItemActive() and not Touch.dragging

	if not repeatState[id] then
		repeatState[id] = { held = false, nextFire = 0 }
	end

	local st = repeatState[id]

	if held then
		if not st.held then
			st.held = true
			st.nextFire = now + 350
		elseif now >= st.nextFire then
			st.nextFire = now + 55
			clicked = true
		end
	else
		st.held = false
	end

	return clicked
end

local function neutralButtonColors()
	pushCol(imgui.Col.Button, UI.BTN)
	pushCol(imgui.Col.ButtonHovered, UI.BTN_HOVER)
	pushCol(imgui.Col.ButtonActive, UI.BTN_ACTIVE)
	pushCol(imgui.Col.Text, NEUTRAL_CHANNEL_TEXT)
end

local function drawTimerControl(block, x, y)
	local maxValue = block.use_seconds.v and 5000 or 60
	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()

	local caption = ICON.CLOCK .. u8(" \200\237\242\229\240\226\224\235")
	pcall(function()
		dl:AddText(V2(x, y + ((26 * UI_SCALE) - lineH) / 2), c32(UI.MUTED), caption)
	end)

	local bx = x + imgui.CalcTextSize(caption).x + (14 * UI_SCALE)

	pushVar(imgui.StyleVar.FrameRounding, (8 * UI_SCALE))

	imgui.SetCursorScreenPos(V2(bx, y))
	neutralButtonColors()
	if repeatButton("timer_minus_" .. tostring(block.id), ICON.MINUS, imgui.ImVec2((28 * UI_SCALE), (26 * UI_SCALE))) then
		block.timer.v = math.max(1, block.timer.v - 1)
	end
	imgui.PopStyleColor(4)

	local vx = bx + (28 * UI_SCALE) + (4 * UI_SCALE)
	imgui.SetCursorScreenPos(V2(vx, y))
	imgui.InvisibleButton("##timer_value", imgui.ImVec2((84 * UI_SCALE), (26 * UI_SCALE)))

	local unitWord = block.use_seconds.v and u8("\241\229\234") or u8("\236\232\237")
	local valueText = string.format("%d %s", block.timer.v, unitWord)

	pcall(function()
		dl:AddRectFilled(V2(vx, y), V2(vx + (84 * UI_SCALE), y + (26 * UI_SCALE)), c32(UI.FIELD), (8 * UI_SCALE))
		local tw = imgui.CalcTextSize(valueText).x
		dl:AddText(V2(vx + ((84 * UI_SCALE) - tw) / 2, y + ((26 * UI_SCALE) - lineH) / 2), c32(UI.TEXT), valueText)
	end)

	Touch.tooltip(u8("\202\240\243\242\232\242\229 \234\238\235\229\241\238 \236\251\248\232, \247\242\238\225\251 \236\229\237\255\242\252 \225\251\241\242\240\229\229"))

	if imgui.IsItemHovered() then
		local wheel = imgui.GetIO().MouseWheel

		if wheel and wheel ~= 0 then
			block.timer.v = math.max(1, math.min(maxValue, block.timer.v + (wheel > 0 and 1 or -1)))
			timerWheelCaptured = true
		end
	end

	imgui.SetCursorScreenPos(V2(vx + (84 * UI_SCALE) + (4 * UI_SCALE), y))
	neutralButtonColors()
	if repeatButton("timer_plus_" .. tostring(block.id), ICON.PLUS, imgui.ImVec2((28 * UI_SCALE), (26 * UI_SCALE))) then
		block.timer.v = math.min(maxValue, block.timer.v + 1)
	end
	imgui.PopStyleColor(4)

	imgui.SetCursorScreenPos(V2(vx + (84 * UI_SCALE) + (4 * UI_SCALE) + (28 * UI_SCALE) + (8 * UI_SCALE), y))
	pushCol(imgui.Col.Button, block.use_seconds.v and THEME.BUTTON_SECONDS or THEME.BUTTON_MINUTES)

	if imgui.Button(ICON.SYNC, imgui.ImVec2((28 * UI_SCALE), (26 * UI_SCALE))) and Touch.tapAllowed() then
		local oldValue = block.timer.v
		block.use_seconds.v = not block.use_seconds.v

		if block.use_seconds.v then
			block.timer.v = math.min(oldValue * 60, 5000)
		else
			block.timer.v = math.min(math.max(1, math.floor(oldValue / 60)), 60)
		end
	end

	imgui.PopStyleColor()

	Touch.tooltip(u8("\209\236\229\237\232\242\252 \229\228\232\237\232\246\251: \236\232\237\243\242\251 / \241\229\234\243\237\228\251"))

	imgui.PopStyleVar()
end

local function trashButton(width, height)
	pushVar(imgui.StyleVar.FrameRounding, (8 * UI_SCALE))
	pushCol(imgui.Col.Button, UI.CLEAR)
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(0.91, 0.16, 0.22, 0.25))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(0.91, 0.16, 0.22, 0.45))
	pushCol(imgui.Col.Text, THEME.RED)

	local clicked = imgui.Button(ICON.TRASH, imgui.ImVec2(width, height)) and Touch.tapAllowed()

	imgui.PopStyleColor(4)
	imgui.PopStyleVar()

	return clicked
end

local function drawStatusPill(dl, rightX, y, entity)
	local statusText, statusColor, statusIcon

	if running then
		statusText, statusColor, statusIcon = getTimeLeftDisplay(entity)
	elseif entity.show_paused then
		statusText, statusColor, statusIcon = "\207\224\243\231\224", THEME.TEXT_PAUSED, ICON.PAUSE
	else
		statusText, statusColor, statusIcon = "\195\238\242\238\226\238", THEME.TEXT_READY, ICON.CHECK
	end

	local text = statusIcon .. u8(" " .. statusText)
	local pillW = imgui.CalcTextSize(text).x + (22 * UI_SCALE)
	local lineH = imgui.GetTextLineHeight()

	pcall(function()
		dl:AddRectFilled(V2(rightX - pillW, y), V2(rightX, y + (26 * UI_SCALE)), c32(statusColor, 0.12), (13 * UI_SCALE))
		dl:AddText(V2(rightX - pillW + (11 * UI_SCALE), y + ((26 * UI_SCALE) - lineH) / 2), c32(statusColor), text)
	end)
end

local function drawCardProgress(dl, x, y, w, entity, intervalMs)
	local msLeft = entity.next_send_time - getTimeMs()
	local total = intervalMs + SEND_DELAY_SEC * 1000
	local frac = math.max(0, math.min(1, 1 - msLeft / total))

	pcall(function()
		dl:AddRectFilled(V2(x, y), V2(x + w, y + (3 * UI_SCALE)), c32(UI.FIELD), 2)

		if frac > 0.01 then
			dl:AddRectFilled(V2(x, y), V2(x + w * frac, y + (3 * UI_SCALE)), c32(UI.RED), 2)
		end
	end)
end

local function drawCardFrame(dl, pos, cardW, cardH, accent)
	pcall(function()
		dl:AddRectFilled(pos, V2(pos.x + cardW, pos.y + cardH), c32(UI.CARD), (12 * UI_SCALE))
		dl:AddRect(pos, V2(pos.x + cardW, pos.y + cardH), c32(UI.BORDER), (12 * UI_SCALE))
		dl:AddRectFilled(V2(pos.x, pos.y + (16 * UI_SCALE)), V2(pos.x + (3 * UI_SCALE), pos.y + cardH - (16 * UI_SCALE)), c32(accent), 2)
	end)
end

local function drawBlockRow(block, index)
	pushID(index)

	local preset = CHANNEL_PRESETS[block.channelIndex]
	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()
	local fieldH = lineH + FIELD_PAD_Y * 2
	local pad = (12 * UI_SCALE)
	local cardW = imgui.GetWindowWidth() - (26 * UI_SCALE)
	local cardH = (10 * UI_SCALE) + (26 * UI_SCALE) + (8 * UI_SCALE) + fieldH + (8 * UI_SCALE) + (26 * UI_SCALE) + (16 * UI_SCALE)
	local pos = imgui.GetCursorScreenPos()

	drawCardFrame(dl, pos, cardW, cardH, preset.color)

	local x0 = pos.x + pad + (4 * UI_SCALE)
	local y1 = pos.y + (10 * UI_SCALE)

	imgui.SetCursorScreenPos(V2(x0, y1))
	drawChannelButton(block, preset)

	imgui.SetCursorScreenPos(V2(x0 + (88 * UI_SCALE) + (14 * UI_SCALE), y1 + (3 * UI_SCALE)))
	drawToggleSwitch("blk_en_" .. tostring(block.id), block.enabled, (40 * UI_SCALE), (20 * UI_SCALE))

	pcall(function()
		dl:AddText(
			V2(x0 + (88 * UI_SCALE) + (14 * UI_SCALE) + (40 * UI_SCALE) + (10 * UI_SCALE), y1 + ((26 * UI_SCALE) - lineH) / 2),
			c32(block.enabled.v and UI.TEXT or UI.MUTED),
			block.enabled.v and u8("\192\234\242\232\226\237\238") or u8("\194\251\234\235\254\247\229\237\238")
		)
	end)

	local trashX = pos.x + cardW - pad - (28 * UI_SCALE)
	imgui.SetCursorScreenPos(V2(trashX, y1))
	if trashButton((28 * UI_SCALE), (26 * UI_SCALE)) then
		pendingDelete = block.id
	end

	if block.enabled.v and string.len(block.buffer.v) > 0 then
		drawStatusPill(dl, trashX - (8 * UI_SCALE), y1, block)
	end

	local y2 = y1 + (26 * UI_SCALE) + (8 * UI_SCALE)
	imgui.SetCursorScreenPos(V2(pos.x + pad, y2))
	pushVar(imgui.StyleVar.FramePadding, imgui.ImVec2(FIELD_PAD_X, FIELD_PAD_Y))
	imgui.PushItemWidth(cardW - pad * 2)
	inputTextWithTags("##text", block.buffer)
	imgui.PopItemWidth()
	imgui.PopStyleVar()

	local isTextActive = imgui.IsItemActive()

	if isTextActive then
		activeInputBuffer = block.buffer
	end

	local ipos = imgui.GetItemRectMin()

	pcall(function()
		dl:AddText(V2(ipos.x + (8 * UI_SCALE), ipos.y + FIELD_PAD_Y), c32(UI.MUTED), ICON.MESSAGE)
	end)

	if block.buffer.v == "" then
		local hintText = preset.key == "custom" and u8("/\234\238\236\224\237\228\224 \242\229\234\241\242 \241\238\238\225\249\229\237\232\255...") or u8("\210\229\234\241\242 \241\238\238\225\249\229\237\232\255...")

		pcall(function()
			dl:AddText(V2(ipos.x + (26 * UI_SCALE), ipos.y + FIELD_PAD_Y), c32(UI.MUTED), hintText)
		end)
	else
		local imax = nil
		pcall(function() imax = imgui.GetItemRectMax() end)
		drawTagOverlay(viewTextOf(block.buffer), ipos.x + (26 * UI_SCALE), ipos.y + FIELD_PAD_Y, isTextActive, imax and imax.x or nil, ipos.y, imax and imax.y or nil)
	end

	local y3 = y2 + fieldH + (8 * UI_SCALE)
	drawTimerControl(block, pos.x + pad + (4 * UI_SCALE), y3)

	if running and block.enabled.v and string.len(block.buffer.v) > 0 and block.was_sent then
		local intervalMs = block.use_seconds.v and block.timer.v * 1000 or block.timer.v * 60 * 1000
		drawCardProgress(dl, pos.x + pad, pos.y + cardH - (10 * UI_SCALE), cardW - pad * 2, block, intervalMs)
	end

	imgui.SetCursorScreenPos(V2(pos.x, pos.y + cardH))
	imgui.Dummy(V2(cardW, (10 * UI_SCALE)))

	imgui.PopID()
end

local function drawVrGroupCard(group, index)
	pushID(index)

	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()
	local fieldH = lineH + FIELD_PAD_Y * 2
	local pad = (12 * UI_SCALE)
	local count = #group.messages
	local cardW = imgui.GetWindowWidth() - (26 * UI_SCALE)
	local cardH = (10 * UI_SCALE) + (26 * UI_SCALE) + (8 * UI_SCALE) + count * (fieldH + (8 * UI_SCALE)) + (30 * UI_SCALE) + (16 * UI_SCALE)
	local pos = imgui.GetCursorScreenPos()

	drawCardFrame(dl, pos, cardW, cardH, THEME.GOLD)

	local x0 = pos.x + pad + (4 * UI_SCALE)
	local y1 = pos.y + (10 * UI_SCALE)

	pcall(function()
		dl:AddText(V2(x0, y1 + ((26 * UI_SCALE) - lineH) / 2), c32(THEME.GOLD), ICON.CROWN .. u8(" \195\240\243\239\239\224 " .. index))
	end)

	local titleW = imgui.CalcTextSize(ICON.CROWN .. u8(" \195\240\243\239\239\224 " .. index)).x

	imgui.SetCursorScreenPos(V2(x0 + titleW + (18 * UI_SCALE), y1 + (3 * UI_SCALE)))
	drawToggleSwitch("grp_en_" .. tostring(group.id), group.enabled, (40 * UI_SCALE), (20 * UI_SCALE), THEME.GOLD)

	pcall(function()
		dl:AddText(
			V2(x0 + titleW + (18 * UI_SCALE) + (40 * UI_SCALE) + (10 * UI_SCALE), y1 + ((26 * UI_SCALE) - lineH) / 2),
			c32(group.enabled.v and UI.TEXT or UI.MUTED),
			group.enabled.v and u8("\192\234\242\232\226\237\224") or u8("\194\251\234\235\254\247\229\237\224")
		)
	end)

	local trashX = pos.x + cardW - pad - (28 * UI_SCALE)
	imgui.SetCursorScreenPos(V2(trashX, y1))
	if trashButton((28 * UI_SCALE), (26 * UI_SCALE)) then
		pendingGroupDelete = group.id
	end

	if group.enabled.v and findNextGroupMessageIndex(group) then
		drawStatusPill(dl, trashX - (8 * UI_SCALE), y1, group)
	end

	local pendingMsgIndex = nil
	local rowY = y1 + (26 * UI_SCALE) + (8 * UI_SCALE)
	local nextIdx = findNextGroupMessageIndex(group)

	local nextAlpha = 0.40
	if group.enabled.v then
		nextAlpha = running and (0.75 + 0.25 * math.sin(monoClock() * 4)) or 0.90
	end

	for mi, msgObj in ipairs(group.messages) do
		pushID(mi)

		pcall(function()
			dl:AddText(V2(pos.x + pad + (4 * UI_SCALE), rowY + FIELD_PAD_Y), c32(THEME.GOLD), mi .. ".")
		end)

		if mi == nextIdx then
			pcall(function()
				local ay = rowY + fieldH / 2
				dl:AddTriangleFilled(V2(pos.x + (5 * UI_SCALE), ay - (5 * UI_SCALE)), V2(pos.x + (5 * UI_SCALE), ay + (5 * UI_SCALE)), V2(pos.x + (12 * UI_SCALE), ay), c32(THEME.GOLD, nextAlpha))
			end)
		end

		imgui.SetCursorScreenPos(V2(pos.x + pad + (26 * UI_SCALE), rowY))
		pushVar(imgui.StyleVar.FramePadding, imgui.ImVec2(FIELD_PAD_X, FIELD_PAD_Y))
		imgui.PushItemWidth(cardW - pad * 2 - (26 * UI_SCALE) - (28 * UI_SCALE) - (6 * UI_SCALE))
		inputTextWithTags("##groupmsg", msgObj.buffer)
		imgui.PopItemWidth()
		imgui.PopStyleVar()

		local isTextActive = imgui.IsItemActive()

		if isTextActive then
			activeInputBuffer = msgObj.buffer
		end

		local ipos = imgui.GetItemRectMin()
		local iend = nil
		pcall(function() iend = imgui.GetItemRectMax() end)

		pcall(function()
			dl:AddText(V2(ipos.x + (8 * UI_SCALE), ipos.y + FIELD_PAD_Y), c32(UI.MUTED), ICON.MESSAGE)
		end)

		if msgObj.buffer.v == "" then
			pcall(function()
				dl:AddText(V2(ipos.x + (26 * UI_SCALE), ipos.y + FIELD_PAD_Y), c32(UI.MUTED), u8("\209\238\238\225\249\229\237\232\229 " .. mi .. "..."))
			end)
		else
			local imax = nil
			pcall(function() imax = imgui.GetItemRectMax() end)
			drawTagOverlay(viewTextOf(msgObj.buffer), ipos.x + (26 * UI_SCALE), ipos.y + FIELD_PAD_Y, isTextActive, imax and imax.x or nil, ipos.y, imax and imax.y or nil)
		end

		if mi == nextIdx and iend then
			pcall(function()
				local oc = c32(THEME.GOLD, nextAlpha)
				dl:AddRect(ipos, iend, oc, (8 * UI_SCALE))
				dl:AddRect(V2(ipos.x + 1, ipos.y + 1), V2(iend.x - 1, iend.y - 1), oc, (7 * UI_SCALE))
			end)
		end

		imgui.SetCursorScreenPos(V2(trashX, rowY))
		if trashButton((28 * UI_SCALE), fieldH) then
			pendingMsgIndex = mi
		end

		imgui.PopID()

		rowY = rowY + fieldH + (8 * UI_SCALE)
	end

	if pendingMsgIndex then
		table.remove(group.messages, pendingMsgIndex)
	end

	imgui.SetCursorScreenPos(V2(pos.x + pad, rowY))
	pushVar(imgui.StyleVar.FrameRounding, (8 * UI_SCALE))
	pushCol(imgui.Col.Button, UI.CLEAR)
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(1.00, 0.82, 0.20, 0.10))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(1.00, 0.82, 0.20, 0.18))
	pushCol(imgui.Col.Text, UI.MUTED)

	if imgui.Button(ICON.PLUS .. u8("  \196\238\225\224\226\232\242\252 \241\238\238\225\249\229\237\232\229"), imgui.ImVec2(cardW - pad * 2, (30 * UI_SCALE))) and Touch.tapAllowed() then
		createGroupMessage(group, "")
	end

	imgui.PopStyleColor(4)
	imgui.PopStyleVar()

	pcall(function()
		dl:AddRect(V2(pos.x + pad, rowY), V2(pos.x + cardW - pad, rowY + (30 * UI_SCALE)), c32(UI.MUTED, 0.35), (8 * UI_SCALE))
	end)

	if running and group.enabled.v and findNextGroupMessageIndex(group) and group.was_sent then
		drawCardProgress(dl, pos.x + pad, pos.y + cardH - (10 * UI_SCALE), cardW - pad * 2, group, VR_INTERVAL_MS)
	end

	imgui.SetCursorScreenPos(V2(pos.x, pos.y + cardH))
	imgui.Dummy(V2(cardW, (10 * UI_SCALE)))

	imgui.PopID()
end

local function pointInRect(p, x1, y1, x2, y2)
	return p.x >= x1 and p.x <= x2 and p.y >= y1 and p.y <= y2
end

local FAQ_TITLE = ICON.QUESTION .. u8("  FAQ: \234\224\234 \239\238\235\252\231\238\226\224\242\252\241\255 VR \227\240\243\239\239\224\236\232")
local FAQ_LINES = {
	u8("\198\236\232 \"\205\238\226\224\255 VR \227\240\243\239\239\224\""),
	u8("\196\238\225\224\226\235\255\233 \241\238\238\225\249\229\237\232\255 \234\237\238\239\234\238\233 \"\196\238\225\224\226\232\242\252 \241\238\238\225\249\229\237\232\229\"\n(\236\238\230\237\238 \237\229\241\234\238\235\252\234\238)"),
	u8("\194\234\235\254\247\232 \227\240\243\239\239\243 \239\229\240\229\234\235\254\247\224\242\229\235\229\236 \"\192\234\242\232\226\237\224\"\n\232 \231\224\239\243\241\242\232 \240\224\241\241\251\235\234\243"),
	u8("\209\238\238\225\249\229\237\232\255 \227\240\243\239\239\251 \243\245\238\228\255\242 \239\238 \238\247\229\240\229\228\232, \239\238 \238\228\237\238\236\243,\n\232\237\242\229\240\226\224\235 5 \236\232\237\243\242, \239\238\241\235\229 \239\238\241\235\229\228\237\229\227\238 - \241\237\238\226\224 \241 \239\229\240\226\238\227\238"),
	u8("\209\242\240\229\235\234\224 \232 \240\224\236\234\224 \239\238\234\224\231\251\226\224\254\242, \234\224\234\238\229 \241\238\238\225\249\229\237\232\229\n\243\233\228\184\242 \241\235\229\228\243\254\249\232\236"),
}

local function drawVrFaq(rightX, y, hdrH, wp)
	local dl = imgui.GetWindowDrawList()
	local label = ICON.QUESTION .. u8("  FAQ")
	local bw = imgui.CalcTextSize(label).x + (24 * UI_SCALE)
	local bh = (26 * UI_SCALE)
	local bx = rightX - bw - (10 * UI_SCALE)
	local by = y + (hdrH - bh) / 2

	imgui.SetCursorScreenPos(V2(bx, by))
	pushVar(imgui.StyleVar.FrameRounding, (9 * UI_SCALE))
	pushCol(imgui.Col.Button, UI.CARD)
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(THEME.CYAN.x, THEME.CYAN.y, THEME.CYAN.z, 0.14))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(THEME.CYAN.x, THEME.CYAN.y, THEME.CYAN.z, 0.24))
	pushCol(imgui.Col.Text, THEME.CYAN)

	local clicked = imgui.Button(label .. "##faq_btn", imgui.ImVec2(bw, bh))

	imgui.PopStyleColor(4)
	imgui.PopStyleVar()

	pcall(function()
		dl:AddRect(V2(bx, by), V2(bx + bw, by + bh), c32(THEME.GOLD, 0.30), (9 * UI_SCALE))
	end)

	if clicked then
		showVrFaq.v = not showVrFaq.v
	end

	local now = monoClock()
	local step = math.min(0.05, now - faqAnimClock) / FAQ_FADE_SEC
	faqAnimClock = now

	if showVrFaq.v then
		faqAnim = math.min(1, faqAnim + step)
	else
		faqAnim = math.max(0, faqAnim - step)
	end

	faqBlockInputs = false
	faqRender = nil

	if faqAnim <= 0 then
		return
	end

	local padX, padY = (16 * UI_SCALE), (12 * UI_SCALE)
	local textOffset = (22 * UI_SCALE)
	local lineH = imgui.GetTextLineHeight()

	local contentW = imgui.CalcTextSize(FAQ_TITLE).x
	local contentH = lineH + (10 * UI_SCALE)

	for i, line in ipairs(FAQ_LINES) do
		local sz = imgui.CalcTextSize(line)
		contentW = math.max(contentW, textOffset + sz.x)
		contentH = contentH + sz.y + (i < #FAQ_LINES and (8 * UI_SCALE) or 0)
	end

	local popupW = contentW + padX * 2 + (6 * UI_SCALE)
	local popupH = contentH + padY * 2
	local px = math.min(bx, wp.x + WIN_W - WIN_PAD - popupW)
	local py = y + hdrH + (4 * UI_SCALE)

	local mouse = imgui.GetIO().MousePos

	if showVrFaq.v and not clicked and imgui.IsMouseClicked(0)
		and not pointInRect(mouse, bx, by, bx + bw, by + bh)
		and not pointInRect(mouse, px, py, px + popupW, py + popupH) then
		showVrFaq.v = false
	end

	faqBlockInputs = faqAnim > 0.05 and pointInRect(mouse, px, py, px + popupW, py + popupH)

	local t = faqAnim
	local ease = t * t * (3 - 2 * t)

	faqRender = {
		x1 = px,
		y1 = py + (1 - ease) * (6 * UI_SCALE),
		w = popupW,
		h = popupH,
		alpha = ease * mainMenu.alpha,
		padX = padX,
		padY = padY,
		textOffset = textOffset,
		lineH = lineH,
	}
end


local function drawVrFaqPopup()
	local r = faqRender

	if not r then
		return
	end

	local dl = imgui.GetWindowDrawList()
	local alpha = r.alpha
	local x1, y1 = r.x1, r.y1
	local x2, y2 = x1 + r.w, y1 + r.h

	local clipped = pcall(function() dl:PushClipRectFullScreen() end)

	pcall(function()
		dl:AddRectFilled(V2(x1 + 2, y1 + (4 * UI_SCALE)), V2(x2 + 2, y2 + (4 * UI_SCALE)), c32(imgui.ImVec4(0, 0, 0, 1), 0.28 * alpha), (12 * UI_SCALE))
		dl:AddRectFilled(V2(x1, y1), V2(x2, y2), c32(imgui.ImVec4(0.075, 0.075, 0.100, 1), alpha), (12 * UI_SCALE))
		dl:AddRect(V2(x1, y1), V2(x2, y2), c32(THEME.GOLD, 0.30 * alpha), (12 * UI_SCALE))

		local ty = y1 + r.padY

		dl:AddText(V2(x1 + r.padX, ty), c32(THEME.CYAN, alpha), FAQ_TITLE)
		ty = ty + r.lineH + (10 * UI_SCALE)

		for i, line in ipairs(FAQ_LINES) do
			dl:AddText(V2(x1 + r.padX, ty), c32(THEME.GOLD, alpha), tostring(i) .. ".")
			dl:AddText(V2(x1 + r.padX + r.textOffset, ty), c32(UI.MUTED, alpha), line)
			ty = ty + imgui.CalcTextSize(line).y + (8 * UI_SCALE)
		end
	end)

	if clipped then
		pcall(function() dl:PopClipRect() end)
	end
end


do
local function scrollGetY()
	local ok, v = pcall(function() return imgui.GetScrollY() end)
	return (ok and type(v) == "number") and v or 0
end

local function scrollMaxY()
	local ok, v = pcall(function() return imgui.GetScrollMaxY() end)
	return (ok and type(v) == "number") and v or 0
end

local function scrollSetY(v)
	if pcall(function() imgui.SetScrollY(v) end) then
		return
	end

	if pcall(function() imgui.SetScrollYFloat(v) end) then
		return
	end

	pcall(function() imgui.SetScrollY_Float(v) end)
end



local function touchScrollUpdate(areaName)
	local ts = Touch
	local io = imgui.GetIO()
	local mouse = io.MousePos
	local wpos = imgui.GetWindowPos()
	local wsize = imgui.GetWindowSize()
	local now = monoClock()
	local maxY = scrollMaxY()
	local dt = clamp(now - ts.lastTime, 0, 0.05)
	local mouseValid = mouse.x > -10000 and mouse.y > -10000

	ts.lastTime = now

	
	local editRect = ts.activeFieldRect
	ts.activeFieldRect = nil

	if imgui.IsMouseClicked(0) then
		ts.inertiaPos = nil   
		ts.velocity = 0
		ts.dragging = false
		ts.area = areaName
		ts.tracking = mouseValid
			and pointInRect(mouse, wpos.x, wpos.y, wpos.x + wsize.x, wpos.y + wsize.y)
			and not showVrFaq.v
			and not (editRect and pointInRect(mouse, editRect[1], editRect[2], editRect[3], editRect[4]))
		ts.startY = mouse.y
		ts.startScroll = scrollGetY()
		ts.samples = { { t = now, y = mouse.y } }
	end

	if ts.tracking and ts.area == areaName then
		if imgui.IsMouseDown(0) then
			if mouseValid then
				if not ts.dragging and maxY > 0 and math.abs(mouse.y - ts.startY) >= ts.SLOP then
					ts.dragging = true
					ts.startY = mouse.y
					ts.startScroll = scrollGetY()
				end

				if ts.dragging then
					scrollSetY(clamp(ts.startScroll - (mouse.y - ts.startY), 0, maxY))

					local s = ts.samples
					s[#s + 1] = { t = now, y = mouse.y }

					while #s > 2 and now - s[1].t > 0.1 do
						table.remove(s, 1)
					end
				end
			end

			if ts.dragging then
				ts.blockClicks = true
			end
		else
			
			if ts.dragging then
				ts.blockClicks = true   

				local s = ts.samples
				local first, last = s[1], s[#s]

				if first and last and now - last.t < 0.1 and last.t - first.t > 0.01 then
					ts.velocity = clamp((last.y - first.y) / (last.t - first.t), -6000, 6000)
					ts.inertiaPos = clamp(ts.startScroll - (last.y - ts.startY), 0, maxY)
				end
			end

			ts.tracking = false
			ts.dragging = false
		end
	end

	
	if ts.inertiaPos and not ts.dragging and ts.area == areaName then
		if math.abs(ts.velocity) < 30 or maxY <= 0 then
			ts.inertiaPos = nil
		else
			ts.inertiaPos = ts.inertiaPos - ts.velocity * dt
			ts.velocity = ts.velocity * math.exp(-ts.FRICTION * dt)

			if ts.inertiaPos <= 0 or ts.inertiaPos >= maxY then
				ts.inertiaPos = clamp(ts.inertiaPos, 0, maxY)
				ts.velocity = 0
			end

			scrollSetY(ts.inertiaPos)
		end
	end
end


local function drawScrollIndicator()
	local maxY = scrollMaxY()

	if maxY < 1 then
		return
	end

	local wpos = imgui.GetWindowPos()
	local wsize = imgui.GetWindowSize()
	local trackTop = wpos.y + (6 * UI_SCALE)
	local trackH = wsize.y - (12 * UI_SCALE)
	local barH = math.max(28 * UI_SCALE, trackH * wsize.y / (wsize.y + maxY))
	local barY = trackTop + (trackH - barH) * clamp(scrollGetY() / maxY, 0, 1)
	local x2 = wpos.x + wsize.x - (3 * UI_SCALE)
	local x1 = x2 - (4 * UI_SCALE)
	local busy = Touch.dragging or Touch.inertiaPos ~= nil

	pcall(function()
		local dl = imgui.GetWindowDrawList()
		dl:AddRectFilled(V2(x1, trackTop), V2(x2, trackTop + trackH), c32(UI.BORDER), (2 * UI_SCALE))
		dl:AddRectFilled(V2(x1, barY), V2(x2, barY + barH), c32(UI.RED, busy and 0.85 or 0.40), (2 * UI_SCALE))
	end)
end


function Touch.beginArea(name, x, y, w, h)
	imgui.SetCursorScreenPos(V2(x, y))

	local flags = 0

	pcall(function()
		flags = bit.bor(imgui.WindowFlags.NoScrollWithMouse, imgui.WindowFlags.NoScrollbar)

		if faqBlockInputs and imgui.WindowFlags.NoInputs then
			flags = bit.bor(flags, imgui.WindowFlags.NoInputs)
		end
	end)

	imgui.BeginChild(name, V2(w, h), false, flags)

	touchScrollUpdate(name)
	timerWheelCaptured = false
end

function Touch.endArea()
	
	if not timerWheelCaptured then
		pcall(function()
			local wheel = imgui.GetIO().MouseWheel

			if wheel and wheel ~= 0 and imgui.IsWindowHovered() then
				Touch.inertiaPos = nil
				scrollSetY(clamp(scrollGetY() - wheel * (60 * UI_SCALE), 0, scrollMaxY()))
			end
		end)
	end

	drawScrollIndicator()
	drawVrFaqPopup()

	imgui.EndChild()
end
end

local function toggleRunning()
	if not running then
		if not isPhoneConfigured() then
			reportPhoneNotConfigured(false)
			return
		end

		local missingPhone = findMissingPhone()

		if missingPhone then
			reportMissingPhone(missingPhone, false)
			return
		end
	end

	running = not running

	if not running then
		local now = os.time()

		for _, block in ipairs(blocks) do
			if block.enabled.v and string.len(block.buffer.v) > 0 then
				block.pause_start_time = now
				block.show_paused = true
				block.ready_after_pause = false
			end
		end

		for _, group in ipairs(vrGroups) do
			if group.enabled.v and findNextGroupMessageIndex(group) then
				group.pause_start_time = now
				group.show_paused = true
				group.ready_after_pause = false
			end
		end

		sampAddChatMessage("{FF0000}|{FFFFFF} \192\226\242\238-\241\238\238\225\249\229\237\232\255 \226\251\234\235\254\247\229\237\251", -1)
	else
		for _, block in ipairs(blocks) do
			block.pause_start_time  = 0
			block.show_paused       = false
			block.ready_after_pause = false
		end

		for _, group in ipairs(vrGroups) do
			group.pause_start_time  = 0
			group.show_paused       = false
			group.ready_after_pause = false
		end

		primingDone      = false
		primingIndex     = 1
		primingStageTime = 0

		sampAddChatMessage("{00FF00}|{FFFFFF} \192\226\242\238-\241\238\238\225\249\229\237\232\255 \226\234\235\254\247\229\237\251", -1)
		checkMessages()
	end

	saveConfig()
end

local function countActive()
	local now = getTimeMs()
	local activeBlocks, activeGroups = 0, 0
	local nextMs = nil

	local function track(entity)
		if not running then
			return
		end

		local left = entity.was_sent and math.max(0, entity.next_send_time - now) or 0

		if not nextMs or left < nextMs then
			nextMs = left
		end
	end

	for _, block in ipairs(blocks) do
		if block.enabled.v and string.len(block.buffer.v) > 0 then
			activeBlocks = activeBlocks + 1
			track(block)
		end
	end

	for _, group in ipairs(vrGroups) do
		if group.enabled.v and findNextGroupMessageIndex(group) then
			activeGroups = activeGroups + 1
			track(group)
		end
	end

	return activeBlocks, activeGroups, nextMs
end

local function drawStatusCard(x, y, w)
	local h = STATUS_H
	local dl = imgui.GetWindowDrawList()
	local activeBlocks, activeGroups, nextMs = countActive()
	local lineH = imgui.GetTextLineHeight()

	pcall(function()
		dl:AddRectFilled(V2(x, y), V2(x + w, y + h), c32(UI.PANEL), (14 * UI_SCALE))
		dl:AddRect(V2(x, y), V2(x + w, y + h), running and c32(UI.RED, 0.45) or c32(UI.BORDER), (14 * UI_SCALE))
	end)

	local dotColor = running and THEME.TEXT_READY or UI.MUTED

	pcall(function()
		if running then
			local pulse = 0.5 + 0.5 * math.sin(monoClock() * 3)
			addCircleFilled(dl, V2(x + (26 * UI_SCALE), y + (26 * UI_SCALE)), (5 * UI_SCALE) + (4 * UI_SCALE) * pulse, c32(dotColor, 0.18))
		end

		addCircleFilled(dl, V2(x + (26 * UI_SCALE), y + (26 * UI_SCALE)), (5 * UI_SCALE), c32(dotColor))
	end)

	textAt(x + (40 * UI_SCALE), y + (18 * UI_SCALE), dotColor, running and u8("\192\234\242\232\226\237\224") or u8("\206\241\242\224\237\238\226\235\229\237\224"))
	textAt(x + (22 * UI_SCALE), y + (42 * UI_SCALE), UI.TEXT, running and u8("\208\224\241\241\251\235\234\224 \240\224\225\238\242\224\229\242 \226 \244\238\237\238\226\238\236 \240\229\230\232\236\229") or u8("\208\224\241\241\251\235\234\224 \238\241\242\224\237\238\226\235\229\237\224"))
	if monoClock() < phoneErrorUntil then
		textAt(x + (22 * UI_SCALE), y + (64 * UI_SCALE), UI.RED, u8("\211\234\224\230\232\242\229 \237\238\236\229\240 \242\229\235\229\244\238\237\224 " .. phoneErrorIndex .. " \226 \237\224\241\242\240\238\233\234\224\245"), 0.85)
	else
		textAt(x + (22 * UI_SCALE), y + (64 * UI_SCALE), UI.MUTED, u8("\209\238\238\225\249\229\237\232\255 \238\242\239\240\224\226\235\255\254\242\241\255 \239\238 \231\224\228\224\237\237\238\236\243 \232\237\242\229\240\226\224\235\243"), 0.85)
	end

	runningToggle.v = running
	imgui.SetCursorScreenPos(V2(x + w - (22 * UI_SCALE) - (56 * UI_SCALE), y + (28 * UI_SCALE)))

	if drawToggleSwitch("run_toggle", runningToggle, (56 * UI_SCALE), (28 * UI_SCALE)) then
		toggleRunning()
	end

	if imgui.IsItemHovered() then
		imgui.SetTooltip(u8("\199\224\239\243\241\242\232\242\252 / \238\241\242\224\237\238\226\232\242\252 \240\224\241\241\251\235\234\243"))
	end

	pcall(function()
		dl:AddLine(V2(x + (16 * UI_SCALE), y + (88 * UI_SCALE)), V2(x + w - (16 * UI_SCALE), y + (88 * UI_SCALE)), c32(UI.BORDER), 1)
	end)

	local nextLabel = "--:--"

	if running and nextMs then
		local secLeft = math.ceil(nextMs / 1000)
		nextLabel = string.format("%02d:%02d", math.floor(secLeft / 60), secLeft % 60)
	end

	local stats = {
		{ ICON.LIST,  u8("\192\234\242\232\226\237\251\245 \225\235\238\234\238\226"),    tostring(activeBlocks) },
		{ ICON.CROWN, u8("\192\234\242\232\226\237\251\245 VR \227\240\243\239\239"),  tostring(activeGroups) },
		{ ICON.CLOCK, u8("\209\235\229\228\243\254\249\224\255 \238\242\239\240\224\226\234\224"), nextLabel },
	}

	local colW = w / 3

	for i, stat in ipairs(stats) do
		local sx = x + colW * (i - 1) + (22 * UI_SCALE)
		local cy = y + (110 * UI_SCALE)

		if i > 1 then
			pcall(function()
				dl:AddLine(V2(x + colW * (i - 1), cy - (16 * UI_SCALE)), V2(x + colW * (i - 1), cy + (16 * UI_SCALE)), c32(UI.BORDER), 1)
			end)
		end

		pcall(function()
			addCircleFilled(dl, V2(sx + (16 * UI_SCALE), cy), (16 * UI_SCALE), c32(UI.RED, 0.14))
		end)

		local iconW = imgui.CalcTextSize(stat[1]).x
		textAt(sx + (16 * UI_SCALE) - iconW / 2, cy - lineH / 2, UI.RED, stat[1])
		textAt(sx + (42 * UI_SCALE), cy - (17 * UI_SCALE), UI.MUTED, stat[2], 0.8)
		textAt(sx + (42 * UI_SCALE), cy - (3 * UI_SCALE), UI.TEXT, stat[3])
	end
end

local function drawNavItem(id, icon, label, tab, badge, x, y, w, h)
	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()

	imgui.SetCursorScreenPos(V2(x, y))
	local clicked = imgui.InvisibleButton("##nav" .. tostring(id), imgui.ImVec2(w, h))
	local hovered = imgui.IsItemHovered()
	local active = activeTab == tab

	pcall(function()
		if active then
			dl:AddRectFilled(V2(x - 2, y - 2), V2(x + w + 2, y + h + 2), c32(UI.RED, 0.12), (13 * UI_SCALE))
			dl:AddRectFilled(V2(x, y), V2(x + w, y + h), c32(UI.RED), (11 * UI_SCALE))
		elseif hovered then
			dl:AddRectFilled(V2(x, y), V2(x + w, y + h), c32(imgui.ImVec4(1, 1, 1, 1), 0.06), (11 * UI_SCALE))
		end

		local textColor = (active or hovered) and UI.TEXT or UI.MUTED
		dl:AddText(V2(x + (16 * UI_SCALE), y + (h - lineH) / 2), c32(textColor), icon)
		dl:AddText(V2(x + (44 * UI_SCALE), y + (h - lineH) / 2), c32(textColor), label)

		if badge then
			local badgeText = tostring(badge)
			local bw = imgui.CalcTextSize(badgeText).x + (14 * UI_SCALE)
			local bx = x + w - (12 * UI_SCALE) - bw

			dl:AddRectFilled(V2(bx, y + h / 2 - (10 * UI_SCALE)), V2(bx + bw, y + h / 2 + (10 * UI_SCALE)), active and c32(imgui.ImVec4(0, 0, 0, 1), 0.25) or c32(UI.BTN), (10 * UI_SCALE))
			dl:AddText(V2(bx + (7 * UI_SCALE), y + (h - lineH) / 2), c32(active and UI.TEXT or UI.MUTED), badgeText)
		end
	end)

	if clicked then
		activeTab = tab
	end
end

local function drawSidebar(wp)
	local dl = imgui.GetWindowDrawList()
	local sx = wp.x + WIN_PAD
	local sy = wp.y + HEADER_H + (12 * UI_SCALE)
	local sh = WIN_H - HEADER_H - (12 * UI_SCALE) - WIN_PAD

	pcall(function()
		dl:AddRectFilled(V2(sx, sy), V2(sx + SIDEBAR_W, sy + sh), c32(UI.PANEL), (14 * UI_SCALE))
		dl:AddRect(V2(sx, sy), V2(sx + SIDEBAR_W, sy + sh), c32(UI.BORDER), (14 * UI_SCALE))
	end)

	textAt(sx + (20 * UI_SCALE), sy + (16 * UI_SCALE), UI.MUTED, u8("\204\197\205\222"), 0.8)

	local items = {
		{ ICON.LIST,  u8("\193\235\238\234\232"),     1, #blocks },
		{ ICON.CROWN, u8("VR \227\240\243\239\239\251"), 2, #vrGroups },
		{ ICON.GEAR,  u8("\205\224\241\242\240\238\233\234\232"), 3, nil },
	}

	for i, item in ipairs(items) do
		drawNavItem(i, item[1], item[2], item[3], item[4], sx + (10 * UI_SCALE), sy + (40 * UI_SCALE) + (i - 1) * (50 * UI_SCALE), SIDEBAR_W - (20 * UI_SCALE), (42 * UI_SCALE))
	end

	local fy = sy + sh - (74 * UI_SCALE)

	pcall(function()
		dl:AddLine(V2(sx + (16 * UI_SCALE), fy), V2(sx + SIDEBAR_W - (16 * UI_SCALE), fy), c32(UI.BORDER), 1)
	end)

	local byWidth = textWidth(u8("By "))
	textAt(sx + (20 * UI_SCALE), fy + (12 * UI_SCALE), UI.RED, u8("By"))
	textAt(sx + (20 * UI_SCALE) + byWidth, fy + (12 * UI_SCALE), THEME.CYAN, u8("Edward"))

	local linkText = ICON.PAPER .. u8(" Telegram-Edward")
	local linkW = imgui.CalcTextSize(linkText).x

	imgui.SetCursorScreenPos(V2(sx + (20 * UI_SCALE), fy + (38 * UI_SCALE)))
	local clicked = imgui.InvisibleButton("##telegram_link", imgui.ImVec2(linkW, (20 * UI_SCALE)))
	local hovered = imgui.IsItemHovered()

	pcall(function()
		dl:AddText(V2(sx + (20 * UI_SCALE), fy + (38 * UI_SCALE)), c32(THEME.CYAN, hovered and 1 or 0.8), linkText)
	end)

	if clicked then
		imgui.SetClipboardText("https://t.me/edward_scripts")
		sampAddChatMessage("{FF0000}|{FFFFFF} Telegram: https://t.me/edward_scripts (copied)", -1)
	end

	if hovered then
		imgui.SetTooltip(u8("\206\242\234\240\251\242\252 Telegram"))
	end
end

local logoTexture = false

local function drawHeader(wp)
	local dl = imgui.GetWindowDrawList()
	local lx = wp.x + WIN_PAD + (4 * UI_SCALE)
	local ly = wp.y + (12 * UI_SCALE)

	if logoTexture then
		pcall(function()
			addCircleFilled(dl, V2(lx + (20 * UI_SCALE), ly + (20 * UI_SCALE)), (24 * UI_SCALE), c32(UI.RED, 0.10))
		end)

		imgui.SetCursorScreenPos(V2(lx - (6 * UI_SCALE), ly - 1))
		imgui.Image(logoTexture, imgui.ImVec2((52 * UI_SCALE), (41 * UI_SCALE)))
	else
		pcall(function()
			dl:AddRectFilled(V2(lx - (3 * UI_SCALE), ly - (3 * UI_SCALE)), V2(lx + (43 * UI_SCALE), ly + (43 * UI_SCALE)), c32(UI.RED, 0.16), (15 * UI_SCALE))
			dl:AddRectFilled(V2(lx, ly), V2(lx + (40 * UI_SCALE), ly + (40 * UI_SCALE)), c32(UI.RED), (12 * UI_SCALE))
		end)

		setFontScale(1.35)
		local iconW = imgui.CalcTextSize(ICON.PAPER).x
		local iconH = imgui.GetTextLineHeight()
		textAt(lx + (20 * UI_SCALE) - iconW / 2, ly + (20 * UI_SCALE) - iconH / 2, UI.TEXT, ICON.PAPER)
		setFontScale(1.0)
	end

	local vipW = textWidth(u8("VIP"), 1.3)
	textAt(lx + (54 * UI_SCALE), ly - 2, THEME.GOLD, u8("VIP"), 1.3)
	textAt(lx + (54 * UI_SCALE) + vipW + (8 * UI_SCALE), ly - 2, UI.TEXT, u8("Piar"), 1.3)
	textAt(lx + (54 * UI_SCALE), ly + (24 * UI_SCALE), UI.MUTED, u8("\192\226\242\238\236\224\242\232\247\229\241\234\224\255 \240\224\241\241\251\235\234\224 \226 \247\224\242 \232 VR"), 0.85)

	imgui.SetCursorScreenPos(V2(wp.x + WIN_W - WIN_PAD - (38 * UI_SCALE), wp.y + (15 * UI_SCALE)))
	pushVar(imgui.StyleVar.FrameRounding, (10 * UI_SCALE))
	pushCol(imgui.Col.Button, UI.CLEAR)
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(0.91, 0.16, 0.22, 0.30))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(0.91, 0.16, 0.22, 0.50))
	pushCol(imgui.Col.Text, UI.MUTED)

	if imgui.Button(ICON.XMARK .. "##close", imgui.ImVec2((34 * UI_SCALE), (34 * UI_SCALE))) then
		mainMenu.switch()
	end

	imgui.PopStyleColor(4)
	imgui.PopStyleVar()

	pcall(function()
		dl:AddLine(V2(wp.x + WIN_PAD, wp.y + HEADER_H), V2(wp.x + WIN_W - WIN_PAD, wp.y + HEADER_H), c32(UI.BORDER), 1)
	end)
end

local SECTION_BIG_H = 38 * UI_SCALE

local function drawSectionHeader(x, y, w, title, count, buttonLabel, buttonColor, big)
	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()
	local hh = big and SECTION_BIG_H or (28 * UI_SCALE)

	textAt(x + 2, y + (hh - lineH) / 2, UI.TEXT, title)

	if count then
		local titleW = imgui.CalcTextSize(title).x
		local countText = tostring(count)
		local cw = imgui.CalcTextSize(countText).x + (16 * UI_SCALE)

		pcall(function()
			dl:AddRectFilled(V2(x + titleW + (14 * UI_SCALE), y + (hh - (20 * UI_SCALE)) / 2), V2(x + titleW + (14 * UI_SCALE) + cw, y + (hh - (20 * UI_SCALE)) / 2 + (20 * UI_SCALE)), c32(UI.BTN), (10 * UI_SCALE))
			dl:AddText(V2(x + titleW + (22 * UI_SCALE), y + (hh - lineH) / 2), c32(UI.MUTED), countText)
		end)
	end

	local rounding = big and (12 * UI_SCALE) or (9 * UI_SCALE)
	local bw = imgui.CalcTextSize(buttonLabel).x + (big and (64 * UI_SCALE) or (30 * UI_SCALE))
	local bx = x + w - bw - (6 * UI_SCALE)

	imgui.SetCursorScreenPos(V2(bx, y))
	pushVar(imgui.StyleVar.FrameRounding, rounding)
	pushCol(imgui.Col.Button, UI.CLEAR)
	pushCol(imgui.Col.ButtonHovered, imgui.ImVec4(buttonColor.x, buttonColor.y, buttonColor.z, 0.16))
	pushCol(imgui.Col.ButtonActive, imgui.ImVec4(buttonColor.x, buttonColor.y, buttonColor.z, 0.28))
	pushCol(imgui.Col.Text, buttonColor)

	local clicked = imgui.Button(buttonLabel, imgui.ImVec2(bw, hh))

	imgui.PopStyleColor(4)
	imgui.PopStyleVar()

	pcall(function()
		dl:AddRect(V2(bx, y), V2(x + w - (6 * UI_SCALE), y + hh), c32(buttonColor, 0.75), rounding)
	end)

	return clicked, bx, hh
end

local function drawEmptyState(line1, line2)
	local width = imgui.GetWindowWidth()

	imgui.Dummy(imgui.ImVec2(0, (50 * UI_SCALE)))

	local msg = ICON.EMPTY .. u8(" " .. line1)
	imgui.SetCursorPosX((width - imgui.CalcTextSize(msg).x) / 2)
	pushCol(imgui.Col.Text, UI.MUTED)
	imgui.Text(msg)

	local hint = u8(line2)
	imgui.SetCursorPosX((width - imgui.CalcTextSize(hint).x) / 2)
	imgui.Text(hint)
	imgui.PopStyleColor()

	imgui.Dummy(imgui.ImVec2(0, (10 * UI_SCALE)))
end

local function drawSettingsTab(x, y, w)
	local dl = imgui.GetWindowDrawList()
	local lineH = imgui.GetTextLineHeight()

	local cardA = (86 * UI_SCALE)

	pcall(function()
		dl:AddRectFilled(V2(x, y), V2(x + w, y + cardA), c32(UI.CARD), (12 * UI_SCALE))
		dl:AddRect(V2(x, y), V2(x + w, y + cardA), c32(UI.BORDER), (12 * UI_SCALE))
	end)

	imgui.SetCursorScreenPos(V2(x + (20 * UI_SCALE), y + (18 * UI_SCALE)))
	drawToggleSwitch("autoskip_toggle", autoSkipDialog, (48 * UI_SCALE), (24 * UI_SCALE))

	textAt(
		x + (20 * UI_SCALE) + (48 * UI_SCALE) + (14 * UI_SCALE), y + (18 * UI_SCALE) + ((24 * UI_SCALE) - lineH) / 2,
		autoSkipDialog.v and THEME.TEXT_READY or UI.MUTED,
		u8("\192\226\242\238\239\240\238\239\243\241\234 \228\232\224\235\238\227\224 \240\229\234\235\224\236\251: ") .. (autoSkipDialog.v and u8("\194\202\203") or u8("\194\219\202\203"))
	)

	textAt(x + (20 * UI_SCALE), y + (54 * UI_SCALE), UI.MUTED, u8("\197\241\235\232 \226\251\234\235\254\247\232\242\252 - \228\232\224\235\238\227\232 \239\238\228\242\226\229\240\230\228\229\237\232\255 \240\229\234\235\224\236\251 \237\243\230\237\238 \225\243\228\229\242 \239\238\228\242\226\229\240\230\228\224\242\252 \226\240\243\247\237\243\254"), 0.85)

	local sy2 = y + cardA + (12 * UI_SCALE)

	pcall(function()
		dl:AddRectFilled(V2(x, sy2), V2(x + w, sy2 + cardA), c32(UI.CARD), (12 * UI_SCALE))
		dl:AddRect(V2(x, sy2), V2(x + w, sy2 + cardA), c32(UI.BORDER), (12 * UI_SCALE))
	end)

	imgui.SetCursorScreenPos(V2(x + (20 * UI_SCALE), sy2 + (18 * UI_SCALE)))
	drawToggleSwitch("autostart_toggle", autoStartEnabled, (48 * UI_SCALE), (24 * UI_SCALE))

	textAt(
		x + (20 * UI_SCALE) + (48 * UI_SCALE) + (14 * UI_SCALE), sy2 + (18 * UI_SCALE) + ((24 * UI_SCALE) - lineH) / 2,
		autoStartEnabled.v and THEME.TEXT_READY or UI.MUTED,
		u8("\192\226\242\238\226\234\235\254\247\229\237\232\229 \239\240\232 \231\224\245\238\228\229 \226 \232\227\240\243: ") .. (autoStartEnabled.v and u8("\194\202\203") or u8("\194\219\202\203"))
	)

	textAt(x + (20 * UI_SCALE), sy2 + (54 * UI_SCALE), UI.MUTED, u8("\207\238\241\235\229 \231\224\245\238\228\224 \226 \232\227\240\243 \240\224\241\241\251\235\234\224 \241\224\236\224 \226\234\235\254\247\232\242\241\255 \247\229\240\229\231 " .. AUTOSTART_DELAY_SEC .. " \241\229\234"), 0.85)

	local by = sy2 + cardA + (12 * UI_SCALE)
	local cardB = (118 * UI_SCALE)

	pcall(function()
		dl:AddRectFilled(V2(x, by), V2(x + w, by + cardB), c32(UI.CARD), (12 * UI_SCALE))
		dl:AddRect(V2(x, by), V2(x + w, by + cardB), c32(UI.BORDER), (12 * UI_SCALE))
	end)

	textAt(x + (20 * UI_SCALE), by + (14 * UI_SCALE), UI.TEXT, ICON.PHONE .. u8(" \205\238\236\229\240\224 \242\229\235\229\244\238\237\238\226"))
	textAt(x + (20 * UI_SCALE) + textWidth(ICON.PHONE .. u8(" \205\238\236\229\240\224 \242\229\235\229\244\238\237\238\226")) + (12 * UI_SCALE), by + (17 * UI_SCALE), UI.MUTED, u8("(\242\229\227\232 :call1: / :call2:)"), 0.85)

	local colW = (w - (40 * UI_SCALE) - (14 * UI_SCALE)) / 2

	textAt(x + (20 * UI_SCALE), by + (44 * UI_SCALE), UI.MUTED, u8("\210\229\235\229\244\238\237 1"), 0.85)
	textAt(x + (20 * UI_SCALE) + colW + (14 * UI_SCALE), by + (44 * UI_SCALE), UI.MUTED, u8("\210\229\235\229\244\238\237 2"), 0.85)

	pushVar(imgui.StyleVar.FramePadding, imgui.ImVec2((12 * UI_SCALE), (8 * UI_SCALE)))
	pushVar(imgui.StyleVar.FrameRounding, (8 * UI_SCALE))

	imgui.SetCursorScreenPos(V2(x + (20 * UI_SCALE), by + (66 * UI_SCALE)))
	imgui.PushItemWidth(colW)
	Touch.input("##phone1", phoneNumber1, phoneNumber1.ptr, phoneNumber1.size)
	imgui.PopItemWidth()

	if monoClock() < phoneErrorUntil and (phoneErrorIndex == 1 or phoneErrorIndex == 0) then
		pcall(function()
			dl:AddRect(imgui.GetItemRectMin(), imgui.GetItemRectMax(), c32(UI.RED), (8 * UI_SCALE))
		end)
	end

	imgui.SetCursorScreenPos(V2(x + (20 * UI_SCALE) + colW + (14 * UI_SCALE), by + (66 * UI_SCALE)))
	imgui.PushItemWidth(colW)
	Touch.input("##phone2", phoneNumber2, phoneNumber2.ptr, phoneNumber2.size)
	imgui.PopItemWidth()

	if monoClock() < phoneErrorUntil and (phoneErrorIndex == 2 or phoneErrorIndex == 0) then
		pcall(function()
			dl:AddRect(imgui.GetItemRectMin(), imgui.GetItemRectMax(), c32(UI.RED), (8 * UI_SCALE))
		end)
	end

	imgui.PopStyleVar(2)

	return (by + cardB) - y
end

local frameLogged = false
imgui.OnFrame(function() return mainMenu.alpha > 0 end, function(self)
	self.HideCursor = true

	if mainFont == nil then
		return
	end

	if not frameLogged then
		frameLogged = true
		dbg("first frame drawn")
	end

	updateStatuses()
	maybeAutoSave()

	
	Touch.blockClicks = false

	if Touch.caretToEnd and monoClock() > Touch.caretToEndDeadline then
		Touch.caretToEnd = false
	end

	pushVar(imgui.StyleVar.Alpha, mainMenu.alpha)
	imgui.PushFont(mainFont)

	local ds = imgui.GetIO().DisplaySize
	local screenW, screenH = ds.x, ds.y
	WIN_W = math.min(880 * UI_SCALE, math.floor(screenW - (20 * UI_SCALE)))
	WIN_H = math.min(660 * UI_SCALE, math.floor(screenH - (20 * UI_SCALE)))
	imgui.SetNextWindowSize(imgui.ImVec2(WIN_W, WIN_H), imgui.Cond.Always)
	imgui.SetNextWindowPos(imgui.ImVec2(screenW / 2 - WIN_W / 2, screenH / 2 - WIN_H / 2), imgui.Cond.Always)

	
	local windowFlags = bit.bor(
		imgui.WindowFlags.NoCollapse,
		imgui.WindowFlags.NoResize,
		imgui.WindowFlags.NoTitleBar,
		imgui.WindowFlags.NoScrollbar,
		imgui.WindowFlags.NoScrollWithMouse,
		imgui.WindowFlags.NoMove
	)

	if imgui.Begin("VIP Piar By Edward##main", nil, windowFlags) then
		local wp = imgui.GetWindowPos()

		drawHeader(wp)
		drawSidebar(wp)

		local cx = wp.x + WIN_PAD + SIDEBAR_W + (14 * UI_SCALE)
		local cw = WIN_W - WIN_PAD * 2 - SIDEBAR_W - (14 * UI_SCALE)
		local cy = wp.y + HEADER_H + (12 * UI_SCALE)

		drawStatusCard(cx, cy, cw)

		local y = cy + STATUS_H + (12 * UI_SCALE)

		if activeTab ~= 2 then
			showVrFaq.v = false
			faqAnim = 0.0
			faqBlockInputs = false
			faqRender = nil
		end

		if activeTab == 3 then
			
			local areaTop = y - (8 * UI_SCALE)
			Touch.beginArea("settingsContent", cx - (10 * UI_SCALE), areaTop, cw + (20 * UI_SCALE), wp.y + WIN_H - WIN_PAD - areaTop)

			local top = imgui.GetCursorScreenPos().y + (8 * UI_SCALE)
			local contentH = drawSettingsTab(cx, top, cw) or 0

			imgui.SetCursorScreenPos(V2(cx, top + contentH))
			imgui.Dummy(V2(cw, (10 * UI_SCALE)))

			Touch.endArea()
		else
			drawVariableChips(cx, y)
			y = y + (26 * UI_SCALE) + (12 * UI_SCALE)

			local addClicked
			local hdrH = (28 * UI_SCALE)
			if activeTab == 1 then
				addClicked = drawSectionHeader(cx, y, cw, u8("\209\239\232\241\238\234 \225\235\238\234\238\226"), #blocks, ICON.PLUS .. u8("  \205\238\226\251\233 \225\235\238\234"), UI.RED)

				if addClicked then
					local defaultIndex = (#blocks % #CHANNEL_PRESETS) + 1
					createBlock(defaultIndex, "", "", false, 5, false)
				end
			else
				local btnX
				addClicked, btnX, hdrH = drawSectionHeader(cx, y, cw, u8("VR \227\240\243\239\239\251"), #vrGroups, ICON.PLUS .. u8("  \205\238\226\224\255 VR \227\240\243\239\239\224"), THEME.GOLD, true)

				drawVrFaq(btnX, y, hdrH, wp)

				if addClicked then
					local group = createVrGroup(false)
					createGroupMessage(group, "")
				end
			end

			local listY = y + hdrH + (10 * UI_SCALE)
			local listH = wp.y + WIN_H - WIN_PAD - listY

			Touch.beginArea("tabContent", cx - (10 * UI_SCALE), listY - (8 * UI_SCALE), cw + (20 * UI_SCALE), listH + (8 * UI_SCALE))

			if activeTab == 1 then
				if #blocks == 0 then
					drawEmptyState("\207\238\234\224 \237\229\242 \225\235\238\234\238\226", "\205\224\230\236\232 \"\205\238\226\251\233 \225\235\238\234\" \226\251\248\229, \247\242\238\225\251 \237\224\247\224\242\252")
				end

				pendingDelete = nil

				for index, block in ipairs(blocks) do
					drawBlockRow(block, index)
				end

				if pendingDelete ~= nil then
					for i, block in ipairs(blocks) do
						if block.id == pendingDelete then
							table.remove(blocks, i)
							break
						end
					end

					pendingDelete = nil
				end
			else
				if #vrGroups == 0 then
					drawEmptyState("\207\238\234\224 \237\229\242 VR \227\240\243\239\239", "\195\240\243\239\239\224 \238\242\239\240\224\226\235\255\229\242 \241\238\238\225\249\229\237\232\255 \239\238 \238\247\229\240\229\228\232 \240\224\231 \226 5 \236\232\237\243\242")
				end

				pendingGroupDelete = nil

				for index, group in ipairs(vrGroups) do
					drawVrGroupCard(group, index)
				end

				if pendingGroupDelete ~= nil then
					for i, group in ipairs(vrGroups) do
						if group.id == pendingGroupDelete then
							table.remove(vrGroups, i)
							break
						end
					end

					pendingGroupDelete = nil
				end
			end

			Touch.endArea()
		end
	end

	imgui.End()
	imgui.PopFont()
	imgui.PopStyleVar()
end)

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
	if not text or not title then
		return
	end

	local cleanTitle = stripColors(title)
	local cleanText  = stripColors(text)

	if awaitingSecondDialog and getTimeMs() - awaitingSecondDialogSince > AWAIT_SECOND_DIALOG_TIMEOUT_MS then
		awaitingSecondDialog = false
	end

	local ownMessageValid = lastSentText ~= ""
		and lastSentChannel == "vr"
		and isScriptMessage(lastSentText)

	if awaitingSecondDialog then
		awaitingSecondDialog = false

		if ownMessageValid then
			recentScriptMessages[lastSentText] = nil
			sampSendDialogResponse(dialogId, 1, -1, "")
			return false
		end

		return
	end

	local isOwnMessage = awaitingOwnMessageDialog and ownMessageValid

	local isAdDialog = cleanText:find("\194\224\248\229 \241\238\238\225\249\229\237\232\229 \255\226\235\255\229\242\241\255 \240\229\234\235\224\236\238\233")
		or cleanText:find("\209\242\238\232\236\238\241\242\252 \240\229\234\235\224\236\237\238\227\238 \241\238\238\225\249\229\237\232\255")
		or cleanTitle:find("\208\229\234\235\224\236\224 \226 VIP%-\247\224\242")
		or cleanText:find("\194\251 \241\238\225\232\240\224\229\242\229\241\252 \239\238\228\224\242\252 \240\229\234\235\224\236\243")

	if not isAdDialog then
		return
	end

	if isOwnMessage then
		awaitingOwnMessageDialog = false
		sampSendDialogResponse(dialogId, 1, -1, "")
		awaitingSecondDialog = true
		awaitingSecondDialogSince = getTimeMs()
		return false
	end

	if autoSkipDialog.v then
		sampSendDialogResponse(dialogId, 0, -1, "")
		return false
	end

	return
end

function sampev.onServerMessage(color, text)
	if not text then
		return
	end

	local cleanText = stripColors(text)

	
	local okHide, hide = pcall(myIdent.onIdReply, cleanText)

	if okHide and hide then
		return false
	end

	
	pcall(myIdent.learnFromServerText, cleanText)

	if cleanText:find("\231\224\239\240\229\249\224\229\242\241\255 \232\241\239\238\235\252\231\238\226\224\242\252 \239\238\228\238\225\237\251\229 \241\232\236\226\238\235\251") then
		clearOwnAd()

		if lastSentEntity then
			lastSentEntity.next_send_time    = getTimeMs()
			lastSentEntity.was_sent          = false
			lastSentEntity.show_paused       = false
			lastSentEntity.ready_after_pause = false
		end

		return
	end

	if not (cleanText:find("\238\242\239\240\224\226") and cleanText:find("\238\241\242\224\235\238\241\252")) then
		return
	end

	clearOwnAd()

	if not lastVrGroup then
		return
	end

	local minutes, seconds = cleanText:match("(%d+)%s*\236\232\237\243\242.-%s+(%d+)%s*\241\229\234\243\237\228")

	if not minutes then
		seconds = cleanText:match("(%d+)%s*\241\229\234\243\237\228")
		minutes = seconds and "0" or nil
	end

	if not minutes then
		return
	end

	local waitMs = (tonumber(minutes) * 60 + tonumber(seconds)) * 1000

	lastVrGroup.next_send_time    = getTimeMs() + waitMs
	lastVrGroup.was_sent          = true
	lastVrGroup.show_paused       = false
	lastVrGroup.ready_after_pause = false
end

function main()
	repeat
		wait(100)
	until isSampAvailable()

	loadConfig()
	if myIdent.savedNick and not myIdent.validNick(myIdent.savedNick) then
		myIdent.savedNick = nil
	end

	myIdent.configLoaded = true

	sampRegisterChatCommand("vpr", function()
		mainMenu.switch()
	end)

	
	sampRegisterChatCommand("vprwho", function()
		local q = myIdent.q
		local v = q and q.verified

		sampAddChatMessage("{FF0000}|{FFFFFF} {id}=" .. tostring(myIdent.getId()) .. "  {name}=" .. tostring(myIdent.getNick())
			.. "  source=" .. tostring(myIdent.source) .. "  server-confirmed=" .. (v and (v.id .. "/" .. v.nick) or "no"), -1)
	end)

	
	sampRegisterChatCommand("vprme", function(arg)
		arg = trim(arg or "")

		if not myIdent.validNick(arg) then
			sampAddChatMessage("{FF0000}|{FFFFFF} Usage: {ffd700}/vprme Nick_Name", -1)
			return
		end

		myIdent.manualId = nil
		myIdent.savedNick = arg
		myIdent.resetQuery()
		myIdent.checkedAt = -100
		pcall(saveConfig)
		sampAddChatMessage("{FF0000}|{FFFFFF} Nickname set: {ffd700}" .. arg .. "{FFFFFF}, checking the id...", -1)
	end)

	sampAddChatMessage("{FF0000}|{FFFFFF} {ffd700}VIP {FFFFFF}Piar is loaded. {c0c0c0}/vpr {FF0000}By {00FFFF}Edward", -1)

	local wasSpawned = false
	local autoStartSince = nil

	while true do
		wait(0)

		mainMenu.update()

		local okSpawn, spawned = pcall(sampIsLocalPlayerSpawned)
		spawned = okSpawn and spawned and true or false

		if spawned and not wasSpawned then
			autoStartSince = monoClock()
		elseif not spawned then
			autoStartSince = nil
		end

		wasSpawned = spawned

		pcall(myIdent.autoTick, spawned)

		if autoStartSince and monoClock() - autoStartSince >= AUTOSTART_DELAY_SEC then
			autoStartSince = nil

			if autoStartEnabled.v and not running then
				toggleRunning()
			end
		end

		if phoneStopRequested then
			phoneStopRequested = false

			if running then
				toggleRunning()
			end
		end

		if running then
			checkMessages()
		end
	end
end