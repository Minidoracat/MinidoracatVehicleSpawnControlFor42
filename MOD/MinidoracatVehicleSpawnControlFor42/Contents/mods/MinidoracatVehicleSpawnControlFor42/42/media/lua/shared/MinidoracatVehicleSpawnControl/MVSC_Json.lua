-- MinidoracatVehicleSpawnControl JSON：解碼沿用 MinidoracatEconomyFor42 ECCore.lua 的 jsonDecode（家族第二個 consumer，
-- 第三個出現時再抽共用）；編碼改成縮排輸出，因為 config.json 是給管理員手動編輯的。
-- Kahlua 沒有 next／assert／xpcall，排序用 M.sortSafe（table.sort 是遞迴 quicksort，verify_mod.py 禁用）。
MinidoracatVehicleSpawnControl = MinidoracatVehicleSpawnControl or {}
local M = MinidoracatVehicleSpawnControl

-- 插入排序：清單都是區域名／腳本名，數百筆以內
function M.sortSafe(list, less)
    less = less or function(a, b) return a < b end
    for i = 2, #list do
        local v = list[i]
        local j = i - 1
        while j >= 1 and less(v, list[j]) do
            list[j + 1] = list[j]
            j = j - 1
        end
        list[j + 1] = v
    end
    return list
end

function M.sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    return M.sortSafe(keys)
end

-- ---------------------------------------------------------------- encode
local function jsonString(s)
    local out = string.gsub(s, '[%c"\\]', function(ch)
        if ch == '"' then return '\\"' end
        if ch == "\\" then return "\\\\" end
        if ch == "\n" then return "\\n" end
        if ch == "\r" then return "\\r" end
        if ch == "\t" then return "\\t" end
        return string.format("\\u%04x", string.byte(ch))
    end)
    return '"' .. out .. '"'
end

local function jsonNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%.0f", n) end
    local s = string.format("%.6f", n)
    s = string.gsub(s, "0+$", "")
    return s
end

local function isArray(t)
    local n = #t
    if n == 0 then return false end
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then return false end
    end
    return true
end

-- 物件鍵排序輸出（檔案 diff 穩定）；空表輸出 {}。indent 為 nil 時輸出單行。
local function encode(value, indent, level)
    local t = type(value)
    if t == "string" then return jsonString(value) end
    if t == "number" then return jsonNumber(value) end
    if t == "boolean" then return value and "true" or "false" end
    if t ~= "table" then return "null" end
    if level > 12 then return '"<depth>"' end
    local nl, pad, padIn, sep = "", "", "", ":"
    if indent then
        nl = "\n"
        pad = string.rep(indent, level)
        padIn = string.rep(indent, level + 1)
        sep = ": "
    end
    local parts = {}
    if isArray(value) then
        for i = 1, #value do parts[i] = padIn .. encode(value[i], indent, level + 1) end
        return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad .. "]"
    end
    local keys = M.sortedKeys(value)
    if #keys == 0 then return "{}" end
    for i, k in ipairs(keys) do
        local v = value[k]
        if v == nil then v = value[tonumber(k)] end
        parts[i] = padIn .. jsonString(k) .. sep .. encode(v, indent, level + 1)
    end
    return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad .. "}"
end

function M.jsonEncode(value, pretty)
    return encode(value, pretty and "  " or nil, 0)
end

-- ---------------------------------------------------------------- decode
-- 成功回 value；失敗回 nil, 訊息（含行號，給管理員直接定位）。null 解成 M.JSON_NULL，鍵不遺失。
M.JSON_NULL = setmetatable({}, { __tostring = function() return "null" end })

local function lineOf(s, pos)
    local line = 1
    for _ in string.gmatch(string.sub(s, 1, pos - 1), "\n") do line = line + 1 end
    return line
end

local function decodeError(s, pos, msg)
    return nil, "line " .. lineOf(s, pos) .. ": " .. msg .. " near '" .. string.sub(s, pos, pos + 12) .. "'"
end

local function skipSpace(s, pos)
    local _, e = string.find(s, "^[ \t\r\n]*", pos)
    return e + 1
end

local decodeValue

local function unicodeChar(code)
    -- Kahlua 字串是 UTF-16（StringLib.java:760-768）；離線 Lua 是 UTF-8
    if utf8 and utf8.char then return utf8.char(code) end
    if code < 65536 then return string.char(code) end
    code = code - 65536
    return string.char(55296 + math.floor(code / 1024), 56320 + code % 1024)
end

local function decodeString(s, pos)
    local out = {}
    local i = pos + 1
    local n = #s
    while i <= n do
        local c = string.sub(s, i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local e = string.sub(s, i + 1, i + 1)
            if e == "n" then out[#out + 1] = "\n"
            elseif e == "t" then out[#out + 1] = "\t"
            elseif e == "r" then out[#out + 1] = "\r"
            elseif e == "b" then out[#out + 1] = "\b"
            elseif e == "f" then out[#out + 1] = "\f"
            elseif e == "u" then
                local hex = string.sub(s, i + 2, i + 5)
                if not string.match(hex, "^%x%x%x%x$") then return nil, i end
                local code = tonumber(hex, 16)
                if code >= 55296 and code <= 56319 then
                    local lowHex = string.sub(s, i + 8, i + 11)
                    if string.sub(s, i + 6, i + 7) ~= "\\u" or not string.match(lowHex, "^%x%x%x%x$") then return nil, i end
                    local low = tonumber(lowHex, 16)
                    if low < 56320 or low > 57343 then return nil, i end
                    code = 65536 + (code - 55296) * 1024 + low - 56320
                    i = i + 6
                elseif code >= 56320 and code <= 57343 then
                    return nil, i
                end
                out[#out + 1] = unicodeChar(code)
                i = i + 4
            elseif e == '"' or e == "\\" or e == "/" then
                out[#out + 1] = e
            else
                return nil, i
            end
            i = i + 2
        else
            if string.byte(c) < 32 then return nil, i end
            out[#out + 1] = c
            i = i + 1
        end
    end
    return nil, pos
end

decodeValue = function(s, pos)
    pos = skipSpace(s, pos)
    local c = string.sub(s, pos, pos)
    if c == "{" then
        local obj = {}
        pos = skipSpace(s, pos + 1)
        if string.sub(s, pos, pos) == "}" then return obj, pos + 1 end
        while true do
            pos = skipSpace(s, pos)
            if string.sub(s, pos, pos) ~= '"' then return decodeError(s, pos, "expected a quoted key") end
            local key, np = decodeString(s, pos)
            if not key then return decodeError(s, pos, "bad string") end
            pos = skipSpace(s, np)
            if string.sub(s, pos, pos) ~= ":" then return decodeError(s, pos, "expected ':'") end
            local value, np2 = decodeValue(s, pos + 1)
            if type(np2) ~= "number" then return nil, np2 end
            obj[key] = value
            pos = skipSpace(s, np2)
            local d = string.sub(s, pos, pos)
            if d == "," then pos = pos + 1
            elseif d == "}" then return obj, pos + 1
            else return decodeError(s, pos, "expected ',' or '}'") end
        end
    elseif c == "[" then
        local arr = {}
        pos = skipSpace(s, pos + 1)
        if string.sub(s, pos, pos) == "]" then return arr, pos + 1 end
        while true do
            local value, np = decodeValue(s, pos)
            if type(np) ~= "number" then return nil, np end
            arr[#arr + 1] = value
            pos = skipSpace(s, np)
            local d = string.sub(s, pos, pos)
            if d == "," then pos = pos + 1
            elseif d == "]" then return arr, pos + 1
            else return decodeError(s, pos, "expected ',' or ']'") end
        end
    elseif c == '"' then
        local str, np = decodeString(s, pos)
        if not str then return decodeError(s, pos, "unterminated string") end
        return str, np
    elseif string.sub(s, pos, pos + 3) == "true" then return true, pos + 4
    elseif string.sub(s, pos, pos + 4) == "false" then return false, pos + 5
    elseif string.sub(s, pos, pos + 3) == "null" then return M.JSON_NULL, pos + 4
    else
        local numStr = string.match(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        local num = numStr and tonumber(numStr)
        if not num then return decodeError(s, pos, "unexpected token") end
        return num, pos + #numStr
    end
end

function M.jsonDecode(s)
    if type(s) ~= "string" then return nil, "not a string" end
    local value, np = decodeValue(s, 1)
    if type(np) ~= "number" then return nil, np end
    np = skipSpace(s, np)
    if np <= #s then return decodeError(s, np, "unexpected text after the end") end
    return value
end
