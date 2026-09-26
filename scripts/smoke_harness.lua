--[[
煙霧測試骨架：用假的 PZ 全域載入**真正的** MOD Lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

為什麼需要（兩類 luac -p 抓不到的錯誤，皆為正式服實際事故）：
- 改函式簽章漏改呼叫點：語法完全合法，要等該路徑真的執行才炸
  （實例：hotspotKey 兩參數改三參數，刪除成功後的 log 聚合路徑必崩）
- 邏輯回歸：安全把關（範圍／阻隔／保護規則）被改壞時，「執行到並斷言」是唯一防線

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/assert/xpcall，Kahlua 沒有——本 harness **測不出**誤用，
  那由 scripts/verify_mod.py 的靜態掃描負責（發版前兩者都要跑）
- Kahlua 專屬行為（table.sort 遞迴深度、Java instance field 不暴露、rawget 呼叫形式、
  每個 table 都是 LinkedHashMap 的記憶體成本）只能靠反編譯查證與實機測試

寫情境的原則：
- 情境要「執行到會炸的路徑」——刪除後的收尾、跨 tick 的第二輪、聚合輸出，都是重災區
- 安全邊界要有**反面**斷言（範圍外／被阻隔／受保護的對象必須存活），不是只測 happy path
- 新防線寫完先「植入違規證明它會抓」再信任它——測不出來的測試等於沒有測試
]]

-- 家族佈局固定，直接填死最省事；scaffold 時由模板替換佔位符
local MEDIA = "MOD/MinidoracatVehicleSpawnControlFor42/Contents/mods/MinidoracatVehicleSpawnControlFor42/42/media/lua"
-- ===== 假的 PZ 全域（依 MOD 實際用到的 API 增補）=====
-- 起始時間要夠大：週期類邏輯常寫成 now - lastAt >= interval 而 lastAt 初值 0
local nowMs = 5000000
function getTimestampMs() return nowMs end
function isClient() return false end
function isServer() return true end
local TEXT = { IGUI_VehicleNameCarNormal = "Chevalier Nyala", IGUI_VehicleNameSmallCar = "Chevalier Dart" }
function getText(key) return TEXT[key] or key end

local handlers = {}
Events = setmetatable({}, {
    __index = function(_, name)
        return { Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end }
    end,
})
local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end

-- java 風格清單（size()/get(i)，0-based）
local function javaList(items)
    return { size = function() return #items end, get = function(_, i) return items[i + 1] end, _raw = items }
end

-- 假檔案系統：getFileWriter 只允許 ini/cfg/txt/log/json（LuaManager.java:1034），其他副檔名回 nil（家族 e2e.md 踩坑錄）
local FS = {}
local ALLOWED = { ini = true, cfg = true, txt = true, log = true, json = true }
function getFileReader(path, _)
    local text = FS[path]
    if text == nil then return nil end
    local lines, i = {}, 0
    for line in string.gmatch(text .. "\n", "(.-)\r?\n") do lines[#lines + 1] = line end
    if string.sub(text, -1) == "\n" then lines[#lines] = nil end
    return { readLine = function() i = i + 1; return lines[i] end, close = function() end }
end
function getFileWriter(path, _, append)
    local ext = string.match(path, "%.(%w+)$")
    if not ALLOWED[ext or ""] then return nil end
    local buf = append and (FS[path] or "") or ""
    return { write = function(_, s) buf = buf .. s end, close = function() FS[path] = buf end }
end

-- 假車輛 script：來源由 getLoadedScriptBodies（modId、body 交錯）決定
local SCRIPTS = {}
local function addScript(full, modId, model, skins, overrider)
    local bodies = { modId, "body" }
    if overrider then bodies[3] = overrider; bodies[4] = "body2" end
    SCRIPTS[#SCRIPTS + 1] = {
        getFullName = function() return full end,
        getName = function() return string.match(full, "%.(.+)$") end,
        getCarModelName = function() return model end,
        getSkinCount = function() return skins end,
        getLoadedScriptBodies = function() return javaList(bodies) end,
    }
end
addScript("Base.CarNormal", "pz-vanilla", "CarNormal", 3)
addScript("Base.SmallCar", "pz-vanilla", "SmallCar", 2, "SomeRetexture")
addScript("Base.VanAmbulance", "pz-vanilla", nil, 1)
addScript("MilPack.M35", "MilPack", nil, 1)
addScript("Base.PickUpTruck", "pz-vanilla", nil, 1)
-- getVehicle 也接受不帶模組的短名（MOD 常這樣寫進區域表，E2E core-mp 實見 "SemiTruck"）
local function getVehicle(_, name)
    for _, sc in ipairs(SCRIPTS) do
        local full = sc.getFullName()
        if full == name or string.match(full, "%.(.+)$") == name then return sc end
    end
    return nil
end
ScriptManager = { instance = { getAllVehicleScripts = function() return javaList(SCRIPTS) end, getVehicle = getVehicle } }
function getModInfoByID(id)
    if id == "MilPack" then return { getName = function() return "Military Pack" end } end
    return nil
end

local resets = 0
VehicleType = { Reset = function() resets = resets + 1 end }

local function freshDistribution()
    local business = { vehicles = { ["Base.SmallCar"] = { index = -1, spawnChance = 10 } }, spawnRate = 8 }
    VehicleZoneDistribution = {
        parkingstall = { vehicles = {
            ["Base.CarNormal"] = { index = -1, spawnChance = 20 },
            ["Base.SmallCar"] = { index = -1, spawnChance = 15 },
            ["MilPack.M35"] = { index = -1, spawnChance = 2 },
        } },
        police = { vehicles = { ["Base.CarNormal"] = { index = 1, spawnChance = 5 }, PickUpTruck = { index = -1, spawnChance = 3 } }, specialCar = true, spawnRate = 50 },
        business = business,
        business2 = business,
        luxuryDealership = { vehicles = { ["Base.CarNormal"] = { index = -1, spawnChance = 1 } }, specialCar = true },
    }
end
freshDistribution()

-- ===== 載入受測程式碼 =====
local loaded = {}
function require(name)
    if loaded[name] then return true end
    loaded[name] = true
    for _, dir in ipairs({ "shared", "server", "client" }) do
        local chunk = loadfile(MEDIA .. "/" .. dir .. "/" .. name .. ".lua")
        if chunk then chunk() return true end
    end
    error("require 找不到: " .. name)
end
require "MinidoracatVehicleSpawnControl/MVSC_Json"
require "MinidoracatVehicleSpawnControl/MVSC_Core"
require "MinidoracatVehicleSpawnControl/MVSC_Server"
local M = MinidoracatVehicleSpawnControl
local S = M.Server
local DIR = "MinidoracatVehicleSpawnControl/"

-- ===== 測試工具 =====
local failures = 0
local function check(ok, label)
    if ok then print("  PASS  " .. label)
    else failures = failures + 1; print("  FAIL  " .. label) end
end
local function readJson(path) return FS[path] and M.jsonDecode(FS[path]) end
local function writeConfig(cfg) FS[DIR .. "config.json"] = M.jsonEncode(cfg, true) end
local function advance(ms) nowMs = nowMs + ms; fire("OnTick") end
local function live(zone) return VehicleZoneDistribution[zone].vehicles end
-- 不變式：生效的表裡絕不能有 <= 0 或 NaN 的權重（全 0 會變 NaN 並固定選最後一台）
local function noBadWeights()
    for _, def in pairs(VehicleZoneDistribution) do
        for _, v in pairs(def.vehicles) do
            if not (v.spawnChance > 0) then return false end
        end
    end
    return true
end

-- ===== 情境 =====
print("情境一：首次開服建立預設設定，原始分布不變")
fire("OnInitGlobalModData", true)
check(FS[DIR .. "config.json"] ~= nil, "建立 config.json")
check(resets == 1, "套用後呼叫一次 VehicleType.Reset")
check(live("parkingstall")["Base.CarNormal"].spawnChance == 20 and live("parkingstall")["MilPack.M35"].spawnChance == 2, "預設設定不改權重")
local cat = readJson(DIR .. "catalog.json")
check(cat and cat.vehicles["MilPack.M35"].source == "MilPack" and cat.vehicles["MilPack.M35"].sourceName == "Military Pack", "MOD 車依 script 載入紀錄分類")
check(cat.vehicles["Base.SmallCar"].source == "pz-vanilla" and cat.vehicles["Base.SmallCar"].overriddenBy[1] == "SomeRetexture", "被覆寫的原版車仍算原版，並列出覆寫者")
check(cat.vehicles["Base.CarNormal"].name == "Chevalier Nyala" and cat.vehicles["Base.VanAmbulance"].name == "Base.VanAmbulance", "顯示名稱走 IGUI_VehicleName，缺翻譯退回 script 名")
check(cat.zones.business and cat.zones.business.aliases[1] == "business2" and cat.zones.business2 == nil, "別名區域只列一次並記在 aliases")
check(math.abs(cat.zones.parkingstall.vehicles["Base.CarNormal"].percent - 54.1) < 0.01, "目錄顯示正規化後的占比")
local st = readJson(DIR .. "status.json")
check(st.ok == true and st.revision == 1 and #st.newVehicles == 0, "首次安裝時現有車輛都不算新偵測")
advance(61000)
check(resets == 1 and readJson(DIR .. "status.json").revision == 1, "開服後第一次輪詢不會把自己寫的檔當成外部修改（readLine 會吃掉結尾換行）")

print("情境二：外部修改設定檔，60 秒內輪詢套用")
writeConfig({ schema = 1, sources = { MilPack = { multiplier = 0.5 } }, vehicles = { ["Base.SmallCar"] = { enabled = false }, ["Base.PickUpTruck"] = { enabled = false } },
    zones = { parkingstall = { spawnRate = 30, weights = { ["Base.CarNormal"] = 40, ["Base.VanAmbulance"] = 4 }, skins = { ["Base.CarNormal"] = 2 } },
        business = { chanceToSpawnBurnt = 10 }, luxuryDealership = { chanceToSpawnKey = 100 } } })
advance(30000)
check(resets == 1, "未到輪詢時間不套用")
advance(31000)
check(resets == 2, "輪詢到變更後再 Reset 一次")
local p = live("parkingstall")
check(p["Base.CarNormal"].spawnChance == 40 and p["Base.CarNormal"].index == 2, "區域權重與指定塗裝生效")
check(p["Base.VanAmbulance"] and p["Base.VanAmbulance"].spawnChance == 4, "可以把車加進原本沒有它的區域")
check(p["MilPack.M35"].spawnChance == 1, "來源倍率套用在 MOD 車")
check(p["Base.SmallCar"] == nil and next(live("business")) == nil, "停用的車從所有區域移除（business 因此變空）")
check(VehicleZoneDistribution.parkingstall.spawnRate == 30 and VehicleZoneDistribution.business2.chanceToSpawnBurnt == 10, "區域參數生效，別名共用同一張表")
check(noBadWeights(), "生效表沒有 <= 0 的權重")
check(live("police").PickUpTruck == nil and live("police")["Base.PickUpTruck"] == nil, "區域表裡的短名也會被停用（快照時轉成完整名稱）")
check(VehicleZoneDistribution.luxuryDealership.chanceToSpawnKey == 100, "大小寫混用的原版區域鍵照原樣接受")
check(readJson(DIR .. "status.json").revision == 2 and FS[DIR .. "backups/config-3.json"] ~= nil, "修訂號遞增並備份被接受的設定")

print("情境三：內容沒變不重套")
advance(61000)
check(resets == 2, "設定檔未變時不 Reset")

print("情境四：JSON 語法錯誤保留舊設定並指出行號")
FS[DIR .. "config.json"] = '{\n  "zones": {\n    "parkingstall": { "spawnRate": 5, }\n  }\n}'
advance(61000)
st = readJson(DIR .. "status.json")
check(resets == 2 and VehicleZoneDistribution.parkingstall.spawnRate == 30, "語法錯誤不套用")
check(st.ok == false and string.find(st.errors[1], "^line 3:") ~= nil, "錯誤訊息帶行號：" .. tostring(st.errors[1]))

print("情境五：值錯誤全部列出且不套用")
writeConfig({ newVehicles = "maybe", zones = { Parkingstall = {}, luxurydealership = {}, business2 = {}, parkingstall = { spawnRate = 150, weights = { ["Base.CarNormal"] = -1 } } } })
advance(61000)
st = readJson(DIR .. "status.json")
local all = table.concat(st.errors, "\n")
check(resets == 2 and #st.errors == 6, "六個錯誤都回報且未套用（" .. #st.errors .. "）")
check(string.find(all, 'use "parkingstall"', 1, true) and string.find(all, 'use "luxuryDealership"', 1, true) and string.find(all, 'configure "business" instead', 1, true)
    and string.find(all, "zones.parkingstall.weights.Base.CarNormal", 1, true), "錯誤指出路徑與改法")

print("情境六：整區所有車權重設 0 → 清單為空，不留 0 權重")
writeConfig({ zones = { police = { weights = { ["Base.CarNormal"] = 0, ["Base.PickUpTruck"] = 0 } } } })
advance(61000)
check(resets == 3 and next(live("police")) == nil, "police 清單為空")
check(noBadWeights(), "生效表沒有 <= 0 的權重")
check(live("parkingstall")["Base.SmallCar"] ~= nil and VehicleZoneDistribution.parkingstall.spawnRate == nil, "每次都從原始分布重算（上一份設定的停用與參數不殘留）")

print("情境七：重開服後新偵測的 MOD 車依 newVehicles 政策")
addScript("MilPack.Scout", "MilPack", nil, 1)
freshDistribution()
VehicleZoneDistribution.parkingstall.vehicles["MilPack.Scout"] = { index = -1, spawnChance = 3 }
writeConfig({ newVehicles = "disable" })
S.base = nil
fire("OnInitGlobalModData", false)
st = readJson(DIR .. "status.json")
check(st.newVehicles[1] == "MilPack.Scout" and #st.newVehicles == 1, "重開服後只標出新出現的車")
check(live("parkingstall")["MilPack.Scout"] == nil and live("parkingstall")["MilPack.M35"] ~= nil, "disable 政策只擋新車")
check(readJson(DIR .. "catalog.json").vehicles["MilPack.Scout"].enabled == false, "目錄標示新車為停用")
writeConfig({ newVehicles = "disable", vehicles = { ["MilPack.Scout"] = { enabled = true } } })
advance(61000)
check(live("parkingstall")["MilPack.Scout"] ~= nil, "明確啟用後生效")

print("情境八：開服時設定檔損壞仍以原始分布啟動")
freshDistribution()
FS[DIR .. "config.json"] = "{ broken"
S.base = nil
local before = resets
fire("OnInitGlobalModData", false)
check(resets == before + 1 and live("parkingstall")["Base.CarNormal"].spawnChance == 20, "用原始分布啟動並 Reset")
check(readJson(DIR .. "status.json").ok == false and readJson(DIR .. "catalog.json") ~= nil, "狀態回報錯誤，目錄仍產生")

print("情境九：JSON 編解碼往返")
local round = M.jsonDecode(M.jsonEncode({ a = { 1, 2 }, b = "中文\n\"x\"", c = 0.25, d = {} }, true))
check(round and round.a[2] == 2 and round.b == "中文\n\"x\"" and round.c == 0.25, "縮排輸出可解回原值")

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
