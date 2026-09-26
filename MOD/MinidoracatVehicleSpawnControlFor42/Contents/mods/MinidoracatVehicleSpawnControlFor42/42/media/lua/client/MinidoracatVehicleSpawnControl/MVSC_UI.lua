-- MinidoracatVehicleSpawnControl 面板共用：主題色（MinidoracatUI 框架，缺席時退回同值直角）、文字、數字格式、區域分組。
require "MinidoracatVehicleSpawnControl/MVSC_Client"

local M = MinidoracatVehicleSpawnControl
local U = {}
M.UI = U

-- 家族 UI 框架（require=MinidoracatUIFor42）；缺席或版本不符就用同值色票＋直角繪製，不帶半套狀態運行
if not (MinidoracatUI and MinidoracatUI.v1) then pcall(require, "MinidoracatUI/V1") end
local FW = MinidoracatUI and MinidoracatUI.v1
local fwOk = FW ~= nil and FW.API_MAJOR == 1 and FW.API_REVISION >= 1 and FW.Theme ~= nil
U.theme = fwOk and FW.Theme.create({ variant = "dark" }) or nil
U.COL = U.theme and U.theme.colors or {
    surface = { r = 0, g = 0, b = 0, a = 0.8 }, well = { r = 0, g = 0, b = 0, a = 0.5 },
    border = { r = 0.4, g = 0.4, b = 0.4, a = 1 }, text = { r = 1, g = 1, b = 1, a = 1 },
    textMuted = { r = 0.62, g = 0.62, b = 0.62, a = 1 }, textFaint = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
    accent = { r = 1, g = 0.85, b = 0.4, a = 1 }, hover = { r = 1, g = 1, b = 1, a = 0.06 },
    selected = { r = 1, g = 1, b = 1, a = 0.12 }, errorSurface = { r = 0.3, g = 0.05, b = 0.05, a = 0.5 },
    errorText = { r = 0.9, g = 0.35, b = 0.3, a = 1 },
}
-- 琥珀底上的文字用深色（淺底 4.5:1），危險操作用 errorText（全面板唯一的紅）
U.COL.onAccent = { r = 0.1, g = 0.08, b = 0.02, a = 1 }

function U.fill(el, x, y, w, h, token, shape)
    local c = type(token) == "table" and token or U.COL[token]
    if not c then return end
    if U.theme then U.theme:fill(el, x, y, w, h, c, shape)
    else el:drawRect(x, y, w, h, c.a, c.r, c.g, c.b) end
end

function U.border(el, x, y, w, h, token, shape)
    local c = type(token) == "table" and token or U.COL[token]
    if not c then return end
    if U.theme then U.theme:border(el, x, y, w, h, c, shape)
    else el:drawRectBorder(x, y, w, h, c.a, c.r, c.g, c.b) end
end

function U.text(el, s, x, y, token, font)
    local c = type(token) == "table" and token or U.COL[token or "text"]
    el:drawText(tostring(s), x, y, c.r, c.g, c.b, c.a, font or UIFont.Small)
end

function U.textRight(el, s, x, y, token, font)
    local c = type(token) == "table" and token or U.COL[token or "text"]
    el:drawTextRight(tostring(s), x, y, c.r, c.g, c.b, c.a, font or UIFont.Small)
end

-- 文字截斷：寬度不夠就加 …，完整值由呼叫端放進 tooltip／資訊欄
function U.fit(s, w, font)
    s = tostring(s)
    local tm = getTextManager()
    font = font or UIFont.Small
    if tm:MeasureStringX(font, s) <= w then return s end
    local n = string.len(s)
    while n > 1 and tm:MeasureStringX(font, string.sub(s, 1, n) .. "...") > w do n = n - 1 end
    return string.sub(s, 1, n) .. "..."
end

-- 不把 nil 傳進 getText（42.20 起所有翻譯值都跑 String.formatted，佔位只用 %1–%3）
function U.T(key, a, b, c)
    local k = "IGUI_MVSC_" .. key
    if a == nil then return getText(k) end
    if b == nil then return getText(k, a) end
    if c == nil then return getText(k, a, b) end
    return getText(k, a, b, c)
end

function U.num(v)
    if v == nil then return "-" end
    if v == math.floor(v) then return tostring(math.floor(v)) end
    return string.format("%.2f", v)
end

function U.pct(v)
    if v == nil then return "-" end
    return string.format("%.1f%%", v)
end

-- 真實時間差轉「N 分鐘前」
function U.ago(ms)
    if not ms then return "-" end
    local d = math.max(0, math.floor((getTimestampMs() - ms) / 1000))
    if d < 60 then return U.T("AgoSeconds") end
    if d < 3600 then return U.T("AgoMinutes", tostring(math.floor(d / 60))) end
    if d < 86400 then return U.T("AgoHours", tostring(math.floor(d / 3600))) end
    return U.T("AgoDays", tostring(math.floor(d / 86400)))
end

function U.sourceLabel(source)
    return getTextOrNull("IGUI_MVSC_Source_" .. tostring(source)) or tostring(source)
end

-- 區域分組（原版鍵；其他一律「MOD 自訂」）。順序＝面板顯示順序。
U.ZONE_GROUPS = {
    { id = "Parking", zones = { "parkingstall", "trailerpark", "junkyard" } },
    { id = "Quality", zones = { "bad", "medium", "good", "sport", "luxuryDealership" } },
    { id = "Service", zones = { "police", "prison", "fire", "ranger", "ambulance", "postal", "farm", "business", "mccoy",
        "carpenter", "spiffo", "radio", "fossoil", "scarlet", "massgenfac", "transit", "network3", "kyheralds", "lectromax",
        "knoxdisti", "advertising", "airportshuttle", "airportservice" } },
    { id = "Traffic", zones = { "trafficjamw", "trafficjame", "trafficjamn", "trafficjams" } },
    { id = "Story", zones = { "trades", "delivery", "professional", "middleClass", "struggling", "evacuee", "racecar",
        "normalburnt", "specialburnt" } },
}

function U.zoneLabel(zone)
    return getTextOrNull("IGUI_MVSC_Zone_" .. zone) or zone
end

-- 回傳 { {group=id, zones={...}}, ... }，每組內依顯示名排序；不在表內的歸 Mod 組
function U.groupZones(names)
    local known, out = {}, {}
    for _, g in ipairs(U.ZONE_GROUPS) do
        local list = {}
        for _, z in ipairs(g.zones) do
            if names[z] then list[#list + 1] = z; known[z] = true end
        end
        if #list > 0 then out[#out + 1] = { group = g.id, zones = list } end
    end
    local rest = {}
    for z in pairs(names) do
        if not known[z] then rest[#rest + 1] = z end
    end
    if #rest > 0 then
        M.sortSafe(rest)
        out[#out + 1] = { group = "Mod", zones = rest }
    end
    return out
end

-- 依寬度換行：先以空白斷詞，單字仍太長（中日文沒有空白）就逐字斷
function U.wrap(s, w, font)
    font = font or UIFont.Small
    local tm = getTextManager()
    local out, line = {}, ""
    local function push(word)
        local cand = line == "" and word or (line .. " " .. word)
        if tm:MeasureStringX(font, cand) <= w then line = cand return end
        if line ~= "" then out[#out + 1] = line; line = "" end
        if tm:MeasureStringX(font, word) <= w then line = word return end
        local cur = ""
        for i = 1, string.len(word) do
            local ch = string.sub(word, i, i)
            if tm:MeasureStringX(font, cur .. ch) > w and cur ~= "" then out[#out + 1] = cur; cur = ch
            else cur = cur .. ch end
        end
        line = cur
    end
    for word in string.gmatch(tostring(s), "%S+") do push(word) end
    if line ~= "" then out[#out + 1] = line end
    return out
end

function U.fontH(font)
    return getTextManager():getFontHeight(font or UIFont.Small)
end
