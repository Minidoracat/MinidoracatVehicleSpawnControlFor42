--[[
煙霧測試骨架：用假的 PZ 全域載入**真正的** MOD Lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

為什麼需要（兩類 luac -p 抓不到的錯誤，皆為正式服實際事故）：
- 改函式簽章漏改呼叫點：語法完全合法，要等該路徑真的執行才炸
  （實例：hotspotKey 兩參數改三參數，刪除成功後的 log 聚合路徑必崩）
- 邏輯回歸：安全把關（範圍／阻隔／保護規則）被改壞時，「執行到並斷言」是唯一防線

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/xpcall，Kahlua 沒有——本 harness **測不出**誤用，
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

-- 假檔案系統：getFileWriter 只允許 ini/cfg/txt/log/json（LuaManager.java:1035），其他副檔名回 nil（家族 e2e.md 踩坑錄）
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
local function addScript(full, modId, model, skins, overrider, wheels)
    local bodies = { modId, "body" }
    if overrider then bodies[3] = overrider; bodies[4] = "body2" end
    SCRIPTS[#SCRIPTS + 1] = {
        getFullName = function() return full end,
        getName = function() return string.match(full, "%.(.+)$") end,
        getCarModelName = function() return model end,
        getSkinCount = function() return skins end,
        getWheelCount = function() return wheels or 4 end,
        getLoadedScriptBodies = function() return javaList(bodies) end,
    }
end
addScript("Base.CarNormal", "pz-vanilla", "CarNormal", 3)
addScript("Base.SmallCar", "pz-vanilla", "SmallCar", 2, "SomeRetexture")
addScript("Base.VanAmbulance", "pz-vanilla", nil, 1)
addScript("MilPack.M35", "MilPack", nil, 1)
addScript("Base.PickUpTruck", "pz-vanilla", nil, 1)
addScript("Base.CarNormalBurnt", "pz-vanilla", nil, 1, nil, 0)
-- 3D 預覽的代理車種也是已註冊的車種（MOD 腳本 MinidoracatVehicleSpawnControl_PreviewVehicles.txt），目錄不得列出。
-- 01 是開機時的燒毀車外殼（零輪）；02 模擬單人預覽過、被載入成一般車的代理（有輪）
addScript("MVSCPreview.PreviewBurnt01", "MinidoracatVehicleSpawnControlFor42", nil, 0, nil, 0)
addScript("MVSCPreview.PreviewBurnt02", "MinidoracatVehicleSpawnControlFor42", nil, 1, nil, 4)
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

-- 假網路：ServerNet 以 sendServerCommand 回覆，送到本機玩家就交給 Client（模擬 MP）
local ME = { getUsername = function() return "admin1" end }
local admin = true
ME.getRole = function() return { hasCapability = function(_, cap) return admin and cap == "SandboxOptions" end } end
Capability = { SandboxOptions = "SandboxOptions" }
function getPlayer() return ME end
-- 真引擎：開服套用（OnInitGlobalModData）時 udpEngine 還沒建立，getOnlinePlayers 會 NPE（GameServer.java:3575）
local serverStarted = false
function getOnlinePlayers()
    if not serverStarted then error("NullPointerException: GameServer.udpEngine is null") end
    return javaList({ ME })
end
local sent = {}
local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deepcopy(x) end
    return o
end
function sendServerCommand(player, module, cmd, args)
    sent[#sent + 1] = cmd
    if player == ME and MinidoracatVehicleSpawnControl.Client then
        MinidoracatVehicleSpawnControl.Client.onServerCommand(module, cmd, deepcopy(args)) -- 網路序列化＝複製
    end
end
function sendClientCommand() error("client uses direct path when not isClient()") end

local resets = 0
VehicleType = { Reset = function() resets = resets + 1 end }

local function freshDistribution()
    local business = { vehicles = { ["Base.SmallCar"] = { index = -1, spawnChance = 10 } }, spawnRate = 8 }
    VehicleZoneDistribution = {
        parkingstall = { vehicles = {
            ["Base.CarNormal"] = { index = -1, spawnChance = 20 },
            ["Base.SmallCar"] = { index = -1, spawnChance = 15 },
            ["MilPack.M35"] = { index = -1, spawnChance = 2 },
            -- 查不到的車名：寫錯（'67 Impala 的 MOD 實見）、前後多了空白
            ["Base.67chevyImpala"] = { index = -1, spawnChance = 2 },
            ["Base.SmallCar "] = { index = -1, spawnChance = 4 },
        } },
        police = { vehicles = { ["Base.CarNormal"] = { index = 1, spawnChance = 5 }, PickUpTruck = { index = -1, spawnChance = 3 } }, specialCar = true, spawnRate = 50 },
        business = business,
        business2 = business,
        -- 和原版 42.21 一樣不是特殊區（原版 VehicleZoneDefinition.lua 的 luxuryDealership 沒有 specialCar）
        luxuryDealership = { vehicles = { ["Base.CarNormal"] = { index = -1, spawnChance = 1 } } },
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
require "MinidoracatVehicleSpawnControl/MVSC_ServerNet"
require "MinidoracatVehicleSpawnControl/MVSC_Client"
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
serverStarted = true
check(S.nextPoll ~= nil, "開服流程完整跑完（輪詢已排程）")
check(FS[DIR .. "config.json"] ~= nil, "建立 config.json")
check(resets == 1, "套用後呼叫一次 VehicleType.Reset")
check(live("parkingstall")["Base.CarNormal"].spawnChance == 20 and live("parkingstall")["MilPack.M35"].spawnChance == 2, "預設設定不改權重")
local cat = readJson(DIR .. "catalog.json")
check(cat and cat.vehicles["MilPack.M35"].source == "MilPack" and cat.vehicles["MilPack.M35"].sourceName == "Military Pack", "MOD 車依 script 載入紀錄分類")
check(cat.vehicles["Base.SmallCar"].source == "pz-vanilla" and cat.vehicles["Base.SmallCar"].overriddenBy[1] == "SomeRetexture", "被覆寫的原版車仍算原版，並列出覆寫者")
check(cat.vehicles["Base.CarNormal"].name == "Chevalier Nyala" and cat.vehicles["Base.VanAmbulance"].name == "Base.VanAmbulance", "顯示名稱走 IGUI_VehicleName，缺翻譯退回 script 名")
check(cat.zones.business and cat.zones.business.aliases[1] == "business2" and cat.zones.business2 == nil, "別名區域只列一次並記在 aliases")
check(math.abs(cat.zones.parkingstall.vehicles["Base.CarNormal"].percent - 54.1) < 0.01, "目錄顯示正規化後的占比")
check(cat.vehicles["MVSCPreview.PreviewBurnt01"] == nil, "3D 預覽的代理車種不進車輛目錄")
check(live("parkingstall")["Base.67chevyImpala"] == nil and live("parkingstall")["Base.SmallCar "] == nil
    and cat.zones.parkingstall.original["Base.67chevyImpala"] == nil, "區域表裡查不到的車名（寫錯、前後多空白）不留在生效表與目錄")
check(VehicleZoneDistribution.luxurydealership == VehicleZoneDistribution.luxuryDealership and cat.zones.luxuryDealership.aliases[1] == "luxurydealership"
    and cat.zones.luxurydealership == nil, "有大寫的區域補上指向同一張表的小寫名稱（引擎只用小寫查），目錄仍以原樣鍵列出")
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
check(VehicleZoneDistribution.business.chanceToSpawnSpecial == 0 and VehicleZoneDistribution.business.chanceToSpawnBurnt == 10,
    "清單空的區不再改抽特殊車；管理員明確設定的參數照用")
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
check(string.find(all, 'use "parkingstall"', 1, true) and string.find(all, 'configure "luxuryDealership" instead', 1, true) and string.find(all, 'configure "business" instead', 1, true)
    and string.find(all, "zones.parkingstall.weights.Base.CarNormal", 1, true), "錯誤指出路徑與改法")

print("情境六：整區所有車權重設 0 → 清單為空，不留 0 權重")
writeConfig({ zones = { police = { weights = { ["Base.CarNormal"] = 0, ["Base.PickUpTruck"] = 0 } } } })
advance(61000)
check(resets == 3 and next(live("police")) == nil, "police 清單為空")
check(VehicleZoneDistribution.police.specialCar == false and VehicleZoneDistribution.police.chanceToSpawnSpecial == 0
    and VehicleZoneDistribution.police.chanceToSpawnBurnt == 0, "清空的特殊區不當特殊區、不改抽特殊車與燒毀車（別的區不會抽到空清單，整區一台都不生）")
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

print("情境十：沒有權限的人拿不到資料也不能套用")
freshDistribution()
FS[DIR .. "config.json"] = "{}"
S.base = nil
fire("OnInitGlobalModData", false)
local Cl = M.Client
local N = M.ServerNet
N.ZONE_BATCH, N.VEHICLE_BATCH = 2, 2 -- 小批次，確保多段組裝真的被走到
admin = false
sent = {}
Cl.request()
check(sent[1] == "denied" and #sent == 1 and Cl.data == nil, "非管理員只收到 denied")
local revBefore = readJson(DIR .. "status.json").revision
Cl.data = { revision = revBefore }
Cl.draft = { zones = { parkingstall = { spawnRate = 99 } } }
Cl.apply(true)
check(readJson(DIR .. "status.json").revision == revBefore and VehicleZoneDistribution.parkingstall.spawnRate == nil, "非管理員強制套用也被伺服器拒絕")
Cl.data, Cl.draft = nil, nil

print("情境十一：管理員分批收到完整快照")
admin = true
sent = {}
Cl.request()
local zoneMsgs = 0
for _, c in ipairs(sent) do if c == "zones" then zoneMsgs = zoneMsgs + 1 end end
local zoneCount = 0
for _ in pairs(Cl.data.base.zones) do zoneCount = zoneCount + 1 end
check(zoneMsgs == 2 and zoneCount == 4 and Cl.data.base.aliasOf.business2 == "business", "區域分批送達並組回別名（" .. zoneMsgs .. " 批）")
check(Cl.data.catalog["MilPack.M35"].display == "MilPack.M35" and Cl.data.catalog["Base.CarNormal"].display == "Chevalier Nyala", "客戶端用自己的語言翻譯車名，缺翻譯退回 script 名")
check(Cl.data.revision == S.state.revision and #Cl.changes() == 0, "草稿等於伺服器設定")

print("情境十二：面板編輯後套用，伺服器寫檔並記錄是誰改的")
Cl.setWeight("parkingstall", "Base.CarNormal", 55)
Cl.setParam("parkingstall", "spawnRate", 40)
Cl.setEnabled("MilPack.M35", false)
check(#Cl.changes() == 3, "草稿記錄三項變更（" .. #Cl.changes() .. "）")
local eff = Cl.effective()
check(eff.parkingstall.vehicles["MilPack.M35"] == nil and eff.parkingstall.vehicles["Base.CarNormal"].spawnChance == 55, "客戶端即時算出套用後結果")
Cl.setWeight("parkingstall", "Base.SmallCar", 15)
check(#Cl.changes() == 3, "改回原始權重不算變更")
local rev0 = S.state.revision
local draftGap = true
Cl.on(function(ev) if ev == "applyResult" and Cl.draft == nil then draftGap = false end end)
Cl.apply(false)
check(draftGap, "套用後到新快照送達前草稿一直存在（面板每幀都讀它）")
check(S.state.revision == rev0 + 1 and live("parkingstall")["Base.CarNormal"].spawnChance == 55 and VehicleZoneDistribution.parkingstall.spawnRate == 40, "伺服器套用面板的設定")
local disk = M.jsonDecode(FS[DIR .. "config.json"])
check(disk.zones.parkingstall.weights["Base.CarNormal"] == 55 and disk.vehicles["MilPack.M35"].enabled == false, "config.json 寫入面板的設定")
local hist = readJson(DIR .. "history.json")
check(hist[#hist].source == "panel" and hist[#hist].user == "admin1" and hist[#hist].revision == rev0 + 1, "變更紀錄記下來源與操作者")
local found = {}
for _, c in ipairs(hist[#hist].changes or {}) do
    found[c.k .. "|" .. tostring(c.z) .. "|" .. tostring(c.s) .. "|" .. tostring(c.p) .. "|" .. tostring(c.b)] = true
end
check(hist[#hist].changeCount == 3 and found["weight|parkingstall|Base.CarNormal|nil|55"] and found["param|parkingstall|nil|spawnRate|40"]
    and found["vehicle|nil|MilPack.M35|enabled|false"], "變更紀錄逐項記下改了什麼（車名含點也完整保留）")
check(Cl.data.revision == rev0 + 1 and #Cl.changes() == 0, "套用後重新載入，沒有殘留的未套用變更")
local resetsNow = resets
advance(61000)
check(resets == resetsNow, "面板寫的檔不會被輪詢當成外部修改再套一次")

print("情境十三：編輯期間檔案被外部修改 → 提示過期，確認後才覆寫")
Cl.setWeight("parkingstall", "Base.CarNormal", 77)
local cfgNow = M.jsonDecode(FS[DIR .. "config.json"])
cfgNow.zones.police = { spawnRate = 5 }
writeConfig(cfgNow)
advance(61000)
check(Cl.stale == S.state.revision and Cl.weightOf("parkingstall", "Base.CarNormal") == 77, "外部修改只提示，不蓋掉編輯中的草稿")
local results = {}
Cl.on(function(ev, a) if ev == "applyResult" then results[#results + 1] = a end end)
Cl.apply(false)
check(results[1] and results[1].stale == true and live("parkingstall")["Base.CarNormal"].spawnChance == 55, "未確認前拒絕覆寫")
Cl.apply(true)
check(results[2] and results[2].ok and live("parkingstall")["Base.CarNormal"].spawnChance == 77, "確認後覆寫")

print("情境十四：面板送來無效設定不會寫檔，也不蓋掉檔案狀態")
local diskBefore = FS[DIR .. "config.json"]
local statusBefore = FS[DIR .. "status.json"]
Cl.draft.zones.parkingstall.spawnRate = 500
Cl.apply(false)
check(results[3] and results[3].ok == false and #results[3].errors == 1, "回報錯誤給送出的人")
check(FS[DIR .. "config.json"] == diskBefore and FS[DIR .. "status.json"] == statusBefore, "config.json 與 status.json 都沒被改")
Cl.discard()
check(#Cl.changes() == 0, "放棄變更回到伺服器設定")

print("情境十五：還原到舊修訂")
local target = S.state.revision - 2
Cl.restore(target)
check(results[4] and results[4].ok and live("parkingstall")["Base.CarNormal"].spawnChance == 55, "還原後生效的是舊修訂的設定")
check(readJson(DIR .. "history.json")[#readJson(DIR .. "history.json")].source == "restore", "還原也記進變更紀錄")
Cl.restore(S.state.revision - 10)
check(results[5] and results[5].ok == false, "超過保留範圍的修訂拒絕還原")

print("情境十六：toRaw／diff 往返")
local raw = { schema = 1, newVehicles = "keep", sources = {}, vehicles = { ["Base.CarNormal"] = { enabled = false } },
    zones = { parkingstall = { spawnRate = 20, weights = { ["Base.SmallCar"] = 3 } } } }
local cfgv = M.validate(raw, { zones = S.base.zones, aliasOf = S.base.aliasOf, scripts = S.info.scripts })
check(#M.diff(raw, M.toRaw(cfgv)) == 0, "validate 後轉回原格式沒有差異")
check(M.diff(raw, { schema = 1, newVehicles = "keep", sources = {}, vehicles = {}, zones = {} })[1] ~= nil, "有差異時列出路徑")

print("情境十七：面板的來源／車輛倍率（整包調降，其他來源占比跟著上升）")
Cl.discard()
Cl.setEnabled("MilPack.M35", true) -- 情境十二已套用停用；先放回區域清單
local n0 = #Cl.changes()
local function shares(zone)
    local total, by = 0, {}
    for s, def in pairs(Cl.effective()[zone].vehicles) do
        total = total + def.spawnChance
        local src = Cl.data.info.sourceOf[s]
        by[src] = (by[src] or 0) + def.spawnChance
    end
    return total, by
end
local mixedZone, modSrc
for zone in pairs(Cl.effective()) do
    local _, by = shares(zone)
    for src in pairs(by) do
        if src ~= M.VANILLA and by[M.VANILLA] then mixedZone, modSrc = zone, src end
    end
end
check(mixedZone ~= nil, "測試資料有同時含原版與 MOD 車的區域")
local t0, by0 = shares(mixedZone)
local baseW, baseT = 0, 0
for s2, d in pairs(Cl.data.base.zones[mixedZone].vehicles) do
    baseT = baseT + d.spawnChance
    if s2 == "MilPack.M35" then baseW = d.spawnChance end
end
local b0 = Cl.baseShare(mixedZone, "MilPack.M35")
Cl.setMultiplier("sources", M.VANILLA, 0.5)
check(Cl.baseShare(mixedZone, "MilPack.M35") == b0 and math.abs(b0 - baseW / baseT) < 1e-9, "原本占比照原始分布算，不受草稿影響")
local t1, by1 = shares(mixedZone)
local expect = by0[modSrc] / (by0[M.VANILLA] * 0.5 + by0[modSrc])
check(math.abs(by1[modSrc] / t1 - expect) < 1e-9 and by1[modSrc] / t1 > by0[modSrc] / t0,
    "原版整包 ×0.5 後 MOD 占比上升到 " .. string.format("%.1f%%", by1[modSrc] / t1 * 100))
check(#Cl.changes() == n0 + 1 and Cl.multOf("sources", M.VANILLA) == 0.5, "來源倍率記成一項變更")
Cl.setMultiplier("sources", M.VANILLA, 1)
check(#Cl.changes() == n0 and Cl.draft.sources[M.VANILLA] == nil, "倍率調回 1 不留覆寫")
Cl.setEnabled("MilPack.M35", false)
Cl.setMultiplier("vehicles", "MilPack.M35", 2)
Cl.setMultiplier("vehicles", "MilPack.M35", 1)
check(Cl.draft.vehicles["MilPack.M35"] and Cl.draft.vehicles["MilPack.M35"].enabled == false, "清掉車輛倍率不會連停用一起清掉")
Cl.discard()

-- 生效表的指紋（區域權重、塗裝序號與參數；jsonEncode 依鍵排序）
local function liveFingerprint()
    local out = {}
    for zone, def in pairs(VehicleZoneDistribution) do
        local p = {}
        for k in pairs(M.ZONE_PARAMS) do p[k] = def[k] end
        p.specialCar = def.specialCar
        out[zone] = { vehicles = def.vehicles, params = p }
    end
    return M.jsonEncode(out)
end

print("情境十八：重開服但設定沒變：照常套用，不新增修訂、備份與紀錄")
local revB = S.state.revision
local histN = #readJson(DIR .. "history.json")
local lastEntry = readJson(DIR .. "history.json")[histN]
local slotPath = DIR .. "backups/config-" .. (revB % S.BACKUP_SLOTS + 1) .. ".json"
local slotBefore = FS[slotPath]
local liveBefore = liveFingerprint()
freshDistribution()
S.base = nil
local resetsB = resets
fire("OnInitGlobalModData", false)
check(resets == resetsB + 1 and liveFingerprint() == liveBefore, "重開服後分布表回到原狀，設定照常重套並 Reset")
check(S.state.revision == revB and readJson(DIR .. "status.json").revision == revB and readJson(DIR .. "state.json").revision == revB, "修訂號不變")
check(#readJson(DIR .. "history.json") == histN and FS[slotPath] == slotBefore, "不新增變更紀錄，也不覆寫下一個備份槽")
local stB = readJson(DIR .. "status.json")
check(stB.ok == true and stB.source == "boot", "狀態仍記下這次開服檢查")
Cl.request()
local originSrc, originAt
if Cl.revisionOrigin then originSrc, originAt = Cl.revisionOrigin() end
check(Cl.data.revision == revB and originSrc == lastEntry.source and originAt == lastEntry.at,
    "面板的「修訂 #N｜來自…」描述目前修訂怎麼來的（" .. tostring(originSrc) .. "），不是較晚那次開服檢查")

print("情境十九：伺服器關著時改過設定檔：開服記一筆修訂並列出差異")
local cfgOff = M.jsonDecode(FS[DIR .. "config.json"])
cfgOff.zones = cfgOff.zones or {}
cfgOff.zones.luxuryDealership = cfgOff.zones.luxuryDealership or {}
cfgOff.zones.luxuryDealership.chanceToSpawnKey = 42
writeConfig(cfgOff)
freshDistribution()
S.base = nil
fire("OnInitGlobalModData", false)
local hOff = readJson(DIR .. "history.json")
local eOff = hOff[#hOff]
check(S.state.revision == revB + 1 and eOff.revision == revB + 1 and eOff.source == "boot" and #hOff == histN + 1, "開服發現檔案改過就記成新修訂")
local sawOff = false
for _, c in ipairs(eOff.changes or {}) do
    if c.k == "param" and c.z == "luxuryDealership" and c.p == "chanceToSpawnKey" and c.b == 42 then sawOff = true end
end
check(sawOff and eOff.changeCount == 1 and VehicleZoneDistribution.luxuryDealership.chanceToSpawnKey == 42, "紀錄只列出關服期間改的那一項，並已生效")

print("情境二十：3D 預覽的代理車種（換塗裝、拆零件、額度、只用全新外殼）")
-- 假引擎：客戶端用 getScriptManager()；原車種、樣板與代理各自假一份（Kahlua 方法呼叫都帶 self）
local function vec(x, y, z) return { x = function() return x end, y = function() return y end, z = function() return z end } end
local function fmodel(id, file)
    return { getId = function() return id end, getFile = function() return file end, getScale = function() return 1 end,
        getOffset = function() return vec(0, 0.5, 0) end, getRotate = function() return vec(0, 0, 0) end,
        getAttachmentNameParent = function() return nil end, getAttachmentNameSelf = function() return nil end }
end
local function fpart(id, models)
    return { getId = function() return id end, getModelCount = function() return #models end, getModel = function(_, k) return models[k + 1] end }
end
local function fvehicle(full, skins, parts, bodies)
    return { getFullName = function() return full end, getSkinCount = function() return skins end,
        getModel = function() return fmodel(nil, full .. "Body") end,
        getPartCount = function() return #parts end, getPart = function(_, i) return parts[i + 1] end,
        getWheel = function(_, i) return { getId = function() return "Wheel" .. i end } end,
        getLoadedScriptBodies = function() return javaList(bodies) end }
end
local PV_VEHICLES = {
    -- 遮罩寫在 template! 樣板裡（原版有 117 台車這樣寫）
    ["Base.Plain"] = fvehicle("Base.Plain", 2, { fpart("DoorFrontLeft", { fmodel("door", "PlainDoor") }) },
        { "pz-vanilla", "vehicle Plain { template! = PlainT, skin { texture = Vehicles/plain_b, } }" }),
    -- GloveBox 三個模型（車頂內裝、車頂、燈條）要拆；保險桿兩個模型是「多選一」款式（可裝物品兩種）不拆
    ["Mod.Van"] = fvehicle("Mod.Van", 2, {
        fpart("GloveBox", { fmodel("int", "VanInterior"), fmodel("roof", "VanRoof"), fmodel("bar", "VanLightbar") }),
        fpart("Bumper", { fmodel("bumper0", "VanBumper0"), fmodel("bumperA", "VanBumperA") }) },
        { "VanMod", "vehicle Van { skin { texture = Vehicles/van_a, } skin { texture = Vehicles/van_b, textureMask = Vehicles/van_b_mask, } textureMask = Vehicles/van_mask, }" }),
    ["Mod.Van2"] = fvehicle("Mod.Van2", 1, { fpart("GloveBox", { fmodel("int", "VanInterior"), fmodel("roof", "VanRoof") }) },
        { "VanMod", "vehicle Van2 { skin { texture = Vehicles/van2, } }" }),
}
local ITEMS = { Bumper = { "Base.VanBumper0", "Base.VanBumperA" }, GloveBox = { "Base.GloveBox" } }
local PROXIES = {}
for i = 1, 3 do
    local px = { loads = {}, skins = 0, parts = 0, bullet = 0, textures = 0 }
    px.getSkinCount = function() return px.skins end
    px.getPartCount = function() return px.parts end
    px.Load = function(_, _, text)
        px.loads[#px.loads + 1] = text
        for _ in string.gmatch(text, "skin%s*{") do px.skins = px.skins + 1 end
    end
    px.copyPartsFrom = function(_, src) px.parts = px.parts + src:getPartCount() end
    px.copyWheelsFrom = function() end
    px.toBullet = function() px.bullet = px.bullet + 1 end
    PROXIES[string.format("MVSCPreview.PreviewBurnt%02d", i)] = px
end
local PV_TEMPLATES = { PlainT = { getLoadedScriptBodies = function()
    return javaList({ "pz-vanilla", "template vehicle PlainT { skin { texture = Vehicles/plain_a, } textureMask = Vehicles/plain_mask, }" })
end } }
function getScriptManager()
    return { getVehicle = function(_, name) return PV_VEHICLES[name] or PROXIES[name] end,
        getVehicleTemplate = function(_, name) return PV_TEMPLATES[name] end }
end
function getCell() return {} end
BaseVehicle = {
    new = function()
        local bv = {}
        bv.setScript = function() end
        bv.getPartById = function(_, id)
            return { getItemType = function() return ITEMS[id] and javaList(ITEMS[id]) end,
                getWheelIndex = function() return -1 end, getParent = function() return nil end }
        end
        return bv
    end,
    LoadVehicleTextures = function(px) px.textures = px.textures + 1 end,
}
require "MinidoracatVehicleSpawnControl/MVSC_Preview"
local PV = M.Preview
local p1, p2, p3 = PROXIES["MVSCPreview.PreviewBurnt01"], PROXIES["MVSCPreview.PreviewBurnt02"], PROXIES["MVSCPreview.PreviewBurnt03"]
p2.parts = 1 -- 其他 MOD 開服時替所有車種加零件（Immersive Snow 的 ISnowShell），代理也有；這不算用過
local name, state = PV.resolve("Base.Plain", 0, "Vehicles/plain_a")
check(name == "Base.Plain" and state == "engine" and PV.remaining() == 3, "預設塗裝、沒有要拆的零件：直接預覽原車種，不用代理；其他 MOD 加過零件的代理也算全新")
name, state = PV.resolve("Base.Plain", 1, "Vehicles/plain_b")
local head = p1.loads[1] or ""
check(name == "MVSCPreview.PreviewBurnt01" and state == "proxy" and string.find(head, "texture = Vehicles/plain_b,", 1, true) ~= nil,
    "第 1 款塗裝載入代理")
check(string.find(head, "textureMask = Vehicles/plain_mask,", 1, true) ~= nil, "遮罩寫在 template! 樣板裡也找得到")
check(p1.parts == 1 and p1.bullet == 1 and p1.textures == 1, "代理複製零件，並更新物理與世界用的貼圖")
local loadsBefore = #p1.loads
check(PV.resolve("Base.Plain", 1, "Vehicles/plain_b") == name and #p1.loads == loadsBefore and PV.remaining() == 2, "看過的組合沿用同一個代理")
name, state = PV.resolve("Mod.Van", 0, "Vehicles/van_a")
local patch = p2.loads[2] or ""
check(name == "MVSCPreview.PreviewBurnt02" and state == "proxy", "有多模型零件的車，預設塗裝也用代理（其他 MOD 加過零件的代理照用）")
check(string.find(patch, "part GloveBox { model roof { scale = 0, } }", 1, true) ~= nil
    and string.find(patch, "part GloveBoxMVSC2 { model bar { file = VanLightbar,", 1, true) ~= nil, "原零件裡的其餘模型縮成 0、另開零件畫")
check(string.find(patch, "Bumper", 1, true) == nil, "「多選一」款式的零件不拆")
check(string.find(p2.loads[1] or "", "textureMask = Vehicles/van_mask,", 1, true) ~= nil, "第 0 款沒有自己的遮罩時用車種層級的")
p3.skins = 1 -- 模擬 Lua 單獨重載：記錄清掉了、代理仍是上次的內容
name, state = PV.resolve("Mod.Van", 1, "Vehicles/van_b")
check(name == nil and state == "exhausted" and #p3.loads == 0, "不重用已用過的代理；用完時第 1 款以後回 nil（改畫貼圖）")
name, state = PV.resolve("Mod.Van2", 0, "Vehicles/van2")
check(name == "Mod.Van2" and state == "exhausted", "用完時第 0 款照原車種顯示並標示額度用完")
check(PV.resolve("Mod.Van", 0, "Vehicles/van_a") == "MVSCPreview.PreviewBurnt02" and PV.resolve("Base.Plain", 0, "Vehicles/plain_a") == "Base.Plain",
    "用完後看過的組合與不需要代理的車照常")

print("情境二十一：世界上的代理車種一加入世界就換成一般車種")
-- 一律挑候選的最後一個：代理排在 SCRIPTS 最後，候選沒排除代理就會挑到它
function ZombRand(n) return n - 1 end
local function worldVehicle(full, skin)
    local v = { script = getVehicle(nil, full), skin = skin or -1, sets = 0 }
    v.getScript = function() return v.script end
    v.setScript = function(_, name) v.script = getVehicle(nil, name); v.sets = v.sets + 1 end
    v.getSkinCount = function() return v.script.getSkinCount() end
    v.getSkinIndex = function() return v.skin end
    v.setSkinIndex = function(_, i) v.skin = i end
    v.getX = function() return 10758.5 end
    v.getY = function() return 9772.5 end
    return v
end
local shell = worldVehicle("MVSCPreview.PreviewBurnt01", 7)
fire("OnSpawnVehicleStart", shell)
check(shell.script.getFullName() == "Base.CarNormalBurnt", "零輪的代理（拿掉車輛 MOD 後被頂替的殘骸、管理員生的）換成燒毀車")
check(shell.skin == 0, "沿用的塗裝序號超出新車種的塗裝數時重挑")
local used = worldVehicle("MVSCPreview.PreviewBurnt02")
fire("OnSpawnVehicleStart", used)
check(used.script.getWheelCount() > 0 and not M.isPreviewScript(used.script.getFullName()), "有輪的代理（單人預覽過的）換成一般車")
local normal = worldVehicle("Base.CarNormal", 2)
fire("OnSpawnVehicleStart", normal)
check(normal.sets == 0 and normal.skin == 2, "一般車種不動")

print("情境二十二：清單空的區不會被別的區抽到；清單恢復後回到原狀")
freshDistribution()
VehicleZoneDistribution.SwatOnly = { vehicles = { ["Base.CarNormal"] = { index = -1, spawnChance = 1 } }, specialCar = true }
writeConfig({ zones = { police = { weights = { ["Base.CarNormal"] = 0, ["Base.PickUpTruck"] = 0 } } } })
S.base = nil
fire("OnInitGlobalModData", false)
local pol = VehicleZoneDistribution.police
check(pol.specialCar == false and VehicleZoneDistribution.swatonly == nil and VehicleZoneDistribution.SwatOnly.specialCar == true,
    "特殊區不補小寫別名（每個鍵各算一個特殊區，補了抽到它的機會加倍）")
local emptyStall = { weights = { ["Base.CarNormal"] = 0, ["Base.SmallCar"] = 0, ["MilPack.M35"] = 0 } }
writeConfig({ zones = { parkingstall = emptyStall } })
advance(61000)
check(pol.specialCar == true and pol.chanceToSpawnSpecial == nil and pol.chanceToSpawnBurnt == nil, "清單恢復後回到原本的特殊區與參數")
check(next(live("parkingstall")) == nil and pol.chanceToSpawnNormal == 0 and VehicleZoneDistribution.SwatOnly.chanceToSpawnNormal == 0,
    "parkingstall 清空後特殊區不再換成一般車（換過去會抽到空清單）")
writeConfig({ zones = { parkingstall = emptyStall, police = { chanceToSpawnNormal = 30 } } })
advance(61000)
check(pol.chanceToSpawnNormal == 30 and noBadWeights(), "管理員明確設定的參數照用")

print("情境二十三：面板顯示實際會套用的參數（整區停用時特殊車、燒毀車是 0）")
Cl.request()
Cl.discard()
check(Cl.paramOf("police", "chanceToSpawnSpecial") == 5, "清單有車時顯示原本的值（區域沒寫就是引擎預設 5）")
Cl.batch(function()
    for s in pairs(Cl.data.base.zones.police.vehicles) do Cl.setWeight("police", s, 0) end
end)
check(Cl.paramOf("police", "chanceToSpawnSpecial") == 0 and Cl.paramOf("police", "chanceToSpawnBurnt") == 0,
    "整區停用後顯示實際會套用的 0，不是原本的 5")
Cl.setParam("police", "chanceToSpawnSpecial", 5)
check(Cl.draft.zones.police.chanceToSpawnSpecial == 5 and Cl.paramOf("police", "chanceToSpawnSpecial") == 5, "整區停用時拉到 5 記成明寫的參數")
Cl.setParam("police", "chanceToSpawnSpecial", 0)
check(Cl.draft.zones.police.chanceToSpawnSpecial == nil, "拉回實際會套用的 0 就移除覆寫，不留多餘的變更")
Cl.discard()

print("情境二十四：補車設定（預設關閉、範圍檢查、只寫和預設不同的值）")
local rctx = { zones = S.base.zones, aliasOf = S.base.aliasOf, scripts = S.info.scripts }
local rcfg = M.validate({ respawn = { enabled = true, unseenHours = 72 } }, rctx)
check(rcfg and rcfg.respawn.enabled == true and rcfg.respawn.unseenHours == 72 and rcfg.respawn.density == 100
    and rcfg.respawn.safehouseMargin == 10, "開啟並改門檻，其餘用預設")
check(M.validate({}, rctx).respawn.enabled == false, "沒寫這段＝關閉")
local _, rerrs = M.validate({ respawn = { unseenHours = 0, density = 5, safehouseMargin = 2.5, enabled = "yes" } }, rctx)
check(#rerrs == 4, "門檻 0、比例 5、外圍不是整數、開關不是布林都整份拒絕")
check(M.toRaw(M.validate({}, rctx)).respawn == nil, "沒寫 respawn 時轉回原格式也沒有這段")
local rch = M.changes({}, { respawn = { enabled = true, unseenHours = 72 } })
check(#rch == 2 and rch[1].k == "respawn" and rch[2].k == "respawn", "變更紀錄列出補車開關與門檻")
check(M.stallChance(16, 4) == 0.17 and M.stallChance(16, 5) == 0.33 and M.stallChance(16, 3) == 0.12
    and M.stallChance(16, 2) == 0.03 and M.stallChance(16, 1) == 0, "每格機率照引擎公式：一般 17%、高 33%、低 12%、極低 3%、無 0")
Cl.request()
Cl.discard()
Cl.setRespawn("enabled", true)
check(#Cl.changes() == 1, "面板開啟補車是一項變更")
Cl.setRespawn("enabled", false)
check(Cl.draft.respawn == nil and #Cl.changes() == 0, "關回預設就移除覆寫，草稿保持最小")
Cl.setRespawn("unseenHours", 99999)
check(Cl.respawnOf("unseenHours") == 8760, "門檻夾在 1–8760")
Cl.discard()

-- ===== 補車的假引擎（只在這幾個情境用；前面的情境不載入 MVSC_Respawn）=====
function getTimestamp() return math.floor(nowMs / 1000) end
function getWorld() return { getWorld = function() return "harness world" end } end
local MD = {}
ModData = { getOrCreate = function(key) MD[key] = MD[key] or {}; return MD[key] end }
local worldAge = 1000
function getGameTime() return { getWorldAgeHours = function() return worldAge end, getMinutesPerDay = function() return 90 end } end
function ZombRandFloat(a) return a end
function instanceof(o, cls) return type(o) == "table" and o._class == cls end
IsoDirections = { N = "N", S = "S", W = "W", E = "E" }
SandboxVars = { CarSpawnRate = 4, CarAlarm = 4, EnableVehicles = true }
local SAFEHOUSES = {}
SafeHouse = { getSafehouseList = function() return javaList(SAFEHOUSES) end }
IsoWorld = { class = {} }
__classmetatables = { [IsoWorld.class] = { __index = { registerVehiclesZone = function(_, _, kind, _, _, _, _, _, props)
    if kind ~= "Vehicle" and kind ~= "ParkingStall" then return nil end
    return { isFaceDirection = function() return props ~= nil and props.FaceDirection == true end }
end } } }
for _, sc in ipairs(SCRIPTS) do sc.getExtents = function() return vec(2, 1.5, 5) end end
local TYPES = {}
local function vtype(key) TYPES[key] = TYPES[key] or { key = key }; return TYPES[key] end
VehicleType.getTypeFromName = function(key) return VehicleZoneDistribution[key] and vtype(key) or nil end
VehicleType.getRandomVehicleType = function(name)
    local k = string.lower(name)
    return VehicleZoneDistribution[k] and vtype(k) or nil
end
VehicleType.hasTypeForZone = function(name) return VehicleZoneDistribution[string.lower(name)] ~= nil end
local SQ, OCC, PLACED = {}, {}, {}
local REJECT = false
local LATE = false -- 引擎要過幾幀才把剛放的車放進區塊的車輛清單（isVehicleIntersecting 暫時看不到；E2E respawn SP 實見）
local LOTZONE = { since = 500, cons = false }
LOTZONE.getHoursSinceLastSeen = function() return LOTZONE.since end
LOTZONE.haveCons = function() return LOTZONE.cons end
local function fsq(x, y)
    local s = { flags = {} }
    s.getX = function() return x end
    s.getY = function() return y end
    s.isSolidFloor = function() return true end
    s.isSolid = function() return false end
    s.isSolidTrans = function() return false end
    s.HasTree = function() return false end
    s.isWaterSquare = function() return false end
    s.isVehicleIntersecting = function() return OCC[x .. "," .. y] == true end
    s.getMovingObjects = function() return { isEmpty = function() return not s.flags.zombie end } end
    s.getDeadBody = function() return nil end
    s.getWorldObjects = function() return { isEmpty = function() return not s.flags.item end } end
    s.getObjects = function() return javaList(s.flags.built and { { _class = "IsoThumpable" } } or {}) end
    s.getZone = function() return LOTZONE end
    return s
end
for x = 1020, 1070 do
    for y = 1020, 1045 do SQ[x .. "," .. y] = fsq(x, y) end
end
function getCell() return { getGridSquare = function(_, x, y, z) return z == 0 and SQ[x .. "," .. y] or nil end } end
local function fchunk(wx, wy, isNew)
    return { isNewChunk = function() return isNew == true end,
        getGridSquare = function(_, x, y, z) return z == 0 and SQ[(wx * 8 + x) .. "," .. (wy * 8 + y)] or nil end }
end
-- addVehicleDebug：車心在格子西北角；佔用車心周圍的格子（之後 isVehicleIntersecting 看得到）
function addVehicleDebug(script, dir, skin, sq)
    local part = { getInventoryItem = function() return nil end,
        getLuaFunction = function(_, n) return n == "create" and "Vehicles.Create.Test" or nil end }
    part.setRandomCondition = function() part.randomized = true end
    local v = { script = script, dir = dir, skin = skin, x = sq.getX(), y = sq.getY(), part = part }
    v.getSqlId = function() return REJECT and -1 or 7 end
    v.setZone = function(_, z) v.zone = z end
    v.setVehicleType = function(_, t) v.vtype = t end
    v.setDoColor = function(_, b) v.doColor = b end
    v.setColorHSV = function(_, h, s, val) v.hsv = { h, s, val } end
    v.setAlarmed = function(_, b) v.alarmed = b end
    v.getPartCount = function() return 1 end
    v.getPartByIndex = function() return part end
    v.getScriptName = function() return script end
    v.setRust = function(_, r) v.rust = r end
    if not REJECT then
        if not LATE then
            for x = v.x - 1, v.x do
                for y = v.y - 2, v.y + 2 do OCC[x .. "," .. y] = true end
            end
        end
        PLACED[#PLACED + 1] = v
    end
    return v
end
Vehicles = { Create = { Test = function(_, part) part.created = true end } }
ME.px, ME.py = 5000, 5000
ME.getX = function() return ME.px end
ME.getY = function() return ME.py end
require "MinidoracatVehicleSpawnControl/MVSC_Respawn"
local R, T = M.Respawn, M.RespawnTrack
fire("OnServerStarted")
local H = 3600

print("情境二十五：玩家足跡（現實時間）與「這次有人來之前空了多久」")
T.init()
check(T.dir == "MinidoracatVehicleSpawnControl/respawn/harness_world/", "紀錄放在世界名子資料夾（不能當檔名的字元換成底線）")
local t0 = getTimestamp()
T.setEnabled(true, t0)
ME.px, ME.py = 10000, 10000
T.tick(t0)
local home = T.key(math.floor(10000 / 64), math.floor(10000 / 64))
check(T.cells[home] and T.cells[home].last == t0 and T.count() == 16, "玩家附近 88 格內的 64×64 格記成現在，一次最多 16 格")
check(T.cells[T.key(math.floor(10200 / 64), math.floor(10000 / 64))] == nil, "88 格外不記")
local homeChunk = T.key(1250, 1250)
ME.px = 20000
T.tick(t0 + 61)
local t1 = t0 + 8 * 24 * H
ME.px = 10000
T.tick(t1)
local q1, fe1 = T.quietBefore(home, homeChunk, t1)
check(q1 == t1 - t0 and fe1 == false, "離開 8 天後回來：從這次來的那刻往前算，空了 8 天")
T.tick(t1 + 300)
check(T.quietBefore(home, homeChunk, t1 + 300) == t1 - t0, "同一次來訪 5 分鐘後還是看來訪前（不是看最後一次）")
T.markRefilled(homeChunk, t1 + 300)
check(T.quietBefore(home, homeChunk, t1 + 400) < 0, "補過之後，同一次來訪不會再符合")
check(T.quietBefore(home, T.key(1251, 1250), t1 + 400) == t1 - t0, "同一格的其他區塊照常（還沒補過）")
ME.px = 20000
T.tick(t1 + 700)
check(T.quietBefore(home, T.key(1251, 1250), t1 + 700 + H) == 400 + H, "最後一次有人是 1 小時多前（已離開）：只空了 1 小時多，不到門檻")
local q2, fe2 = T.quietBefore(T.key(1, 1), T.key(8, 8), t1)
check(fe2 == true and q2 == t1 - t0, "開啟後沒人去過的格子：只能從開啟那刻算")

print("情境二十六：紀錄只寫伺服器本機檔，兩份輪流寫，寫到一半讀另一份")
T.save(t1 + 800)
local cells1 = T.count()
T.dir, T.enabledAt, T.cells, T.refilled = nil, nil, {}, {}
T.init()
check(T.enabledAt == t0 and T.count() == cells1 and T.refilled[homeChunk] == t1 + 300, "重開後讀回開啟時間、足跡與補過的區塊")
local mdKeys = {}
for k in pairs(MD[T.MODDATA]) do mdKeys[#mdKeys + 1] = k end
check(#mdKeys == 1 and mdKeys[1] == "worldId", "全域 ModData 只有世界識別碼，沒有玩家足跡")
T.save(t1 + 900)
local newest = T.dir .. (T.gen % 2 == 0 and "tracker-a.txt" or "tracker-b.txt")
check(FS[newest] ~= nil and FS[T.dir .. (T.gen % 2 == 0 and "tracker-b.txt" or "tracker-a.txt")] ~= nil, "兩份檔案都在")
local gen2 = T.gen
FS[newest] = string.gsub(FS[newest], "end gen=%d+\n$", "")
T.dir, T.enabledAt, T.cells = nil, nil, {}
T.init()
check(T.enabledAt == t0 and T.gen == gen2 - 1, "最新一份沒有結尾行（寫到一半當機）就讀上一份")
local realId = MD[T.MODDATA].worldId
MD[T.MODDATA].worldId = "another-world"
T.dir, T.enabledAt, T.cells = nil, nil, {}
T.init()
check(T.enabledAt == nil and T.count() == 0, "同名的另一個世界不沿用紀錄")
MD[T.MODDATA].worldId = realId
worldAge = worldAge + 10
T.dir, T.enabledAt, T.cells = nil, nil, {}
T.init()
check(T.enabledAt == nil, "世界在沒有記錄的情況下跑了 10 遊戲小時：從頭記")
worldAge = worldAge - 10
T.dir, T.enabledAt, T.cells = nil, nil, {}
T.init()
check(T.enabledAt == t0, "世界時間沒有多跑時照常讀回")

print("情境二十七：車位照引擎算法（方向、步距、重複區、塞車區、2 樓）")
local reg = __classmetatables[IsoWorld.class].__index.registerVehiclesZone
local W0 = {}
reg(W0, "", "ParkingStall", 100, 200, 0, 9, 5, nil)
reg(W0, "parkingstall", "ParkingStall", 100, 300, 0, 5, 2, nil)
reg(W0, "police", "ParkingStall", 200, 200, 0, 5, 12, { Direction = "E", FaceDirection = true })
reg(W0, "", "ParkingStall", 100, 200, 0, 9, 5, nil)
reg(W0, "TrafficJamW", "ParkingStall", 0, 0, 0, 30, 30, nil)
reg(W0, "", "ParkingStall", 300, 300, 1, 9, 5, nil)
reg(W0, "Forest", "Forest", 400, 400, 0, 9, 5, nil)
reg(W0, "parkingstall", "ParkingStall", 1030, 1030, 0, 30, 5, nil)
fire("OnLoadedMapZones")
check(#R.zones == 4 and R.indexOk == true, "重複區、塞車區、2 樓、非停車區都不收")
check(R.zones[1].dir == "N" and R.zones[2].dir == "W" and R.zones[3].dir == "E" and R.zones[3].face == true, "預設朝北；寬 5 高 2 朝西；Direction 屬性照用")
local function stallsIn(ck)
    local out, flat = {}, R.byChunk[ck] or {}
    for i = 1, #flat, 3 do out[#out + 1] = flat[i + 1] .. "," .. flat[i + 2] end
    return table.concat(out, " ")
end
check(stallsIn(T.key(12, 25)) == "101,202" and stallsIn(T.key(13, 25)) == "104,202 107,202", "朝北：每 3 格一位，從原點加 1.5 起算")
check(stallsIn(T.key(12, 37)) == "102,301", "朝西：x 從原點加 2.5、y 從原點加 1.5")
check(stallsIn(T.key(25, 25)) == "202,201 202,204 202,207" and stallsIn(T.key(25, 26)) == "202,210", "朝東：每排 3 格")
check(R.stallCount == 3 + 1 + 4 + 10, "四個區共 18 個車位")

print("情境二十八：補到這一格原版的平均車數，不是補滿；只補空位、不靠近玩家")
local LOT_BLOCK = T.key(16, 16)
writeConfig({ respawn = { enabled = true } })
advance(61000)
advance(1000)
check(R.on == true and T.enabledAt ~= nil, "設定檔開啟後補車開始執行")
ME.px, ME.py = 5000, 5000
nowMs = nowMs + 8 * 24 * H * 1000
fire("LoadChunk", fchunk(129, 129))
advance(5000)
check(#PLACED == 0, "區塊載入後先等 15 秒（存檔車還在讀資料庫）")
advance(11000)
local target = R.target(10 * M.stallChance(16, 4), 100, LOT_BLOCK)
check(#PLACED == target and target >= 1 and target <= 2, "10 個空車位、每格 17%：補 " .. target .. " 台（原版平均約 1.7 台），不是補滿")
local v1 = PLACED[1]
check(v1 and v1.vtype == "parkingstall" and v1.zone == "parkingstall" and v1.part.randomized and v1.part.created
    and v1.rust == 0, "補上的車照區域參數重抽零件車況、跑零件的 create")
fire("LoadChunk", fchunk(129, 129))
advance(16000)
check(#PLACED == target, "同一次來訪重新載入區塊不會再補")
local function resetLot()
    PLACED, OCC, T.refilled = {}, {}, {}
    R.fresh, R.justPlaced = {}, {}
    R.window = { start = getTimestamp(), placed = 0, blocks = 0, near = 0, blocked = 0, protected = 0, rejected = 0 }
end
VehicleZoneDistribution.parkingstall.spawnRate = 99 -- 每格 100%：方便看每一道門
resetLot()
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 10, "每格 100% 時 10 個空位都補")
resetLot()
OCC["1031,1032"], OCC["1034,1032"] = true, true
S.cfg.respawn.density = 50
R.fillBlock(LOT_BLOCK, getTimestamp())
check(R.target(10, 50, LOT_BLOCK) == 5 and #PLACED == 3, "比例 50%（目標 5 台）、已經有 2 台車：只補 3 台，已有的車算在內")
S.cfg.respawn.density = 100
resetLot()
S.cfg.respawn.density = 50
LATE = true
local hidden = {}
for x = 1040, 1058 do
    local k = x .. ",1032"
    if SQ[k] then hidden[k], SQ[k] = SQ[k], nil end
end
R.fillBlock(LOT_BLOCK, getTimestamp()) -- 單人先載入西邊 3 個車位所在的區塊
for k, s in pairs(hidden) do SQ[k] = s end
R.fillBlock(LOT_BLOCK, getTimestamp()) -- 其餘區塊下一幀才載入，剛放的車還看不到
LATE = false
check(#PLACED == R.target(10, 50, LOT_BLOCK), "區塊分兩次載入、剛放的車還看不到：合計仍只補到目標 "
    .. R.target(10, 50, LOT_BLOCK) .. " 台（實際 " .. #PLACED .. "）")
S.cfg.respawn.density = 100
resetLot()
SQ["1033,1033"].flags.item = true
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 8 and R.window.blocked == 2, "地上有物品的車位不放（車身含旋轉餘量，跨到相鄰兩格的範圍）")
SQ["1033,1033"].flags.item = nil
resetLot()
ME.px, ME.py = 1045, 1110
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 0 and R.window.near == 10, "玩家 88 格內一台都不放")
ME.px, ME.py = 5000, 5000
resetLot()
SAFEHOUSES[1] = { getX = function() return 1000 end, getY = function() return 1000 end, getX2 = function() return 1030 end, getY2 = function() return 1030 end }
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 6 and R.window.protected == 4, "安全屋外圍 10 格加半個車身內不放（車心 x < 1043 的 4 格）")
SAFEHOUSES[1] = nil
resetLot()
LOTZONE.cons = true
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 0 and R.window.protected == 10, "玩家在這區蓋過東西就不補")
LOTZONE.cons = false
resetLot()
LOTZONE.since = worldAge - 1
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 0, "沒人去過的區（只有引擎生故事時的標記）不補")
LOTZONE.since = 500
resetLot()
LOTZONE.since = worldAge - 1 -- 專用伺服器只在看見室內格子時更新區域（IsoGridSquare.CalcVisibility），戶外停車場常常沒記到
local seenAt = getTimestamp() - math.floor(7.5 * 24 * H) -- 足跡：開啟後、7.5 天前有人來過這一格
T.cells[LOT_BLOCK] = { last = seenAt, start = seenAt - H }
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 10, "引擎沒記到（多人只認看過室內），足跡有開啟後的來訪紀錄：照補")
T.cells[LOT_BLOCK] = nil
LOTZONE.since = 500
resetLot()
LOTZONE.since = worldAge - 1 -- 這次來訪前沒人看過
R.fillBlock(LOT_BLOCK, getTimestamp())
LOTZONE.since = 0 -- 玩家這次走進去看到了
R.fillBlock(LOT_BLOCK, getTimestamp()) -- 同一次來訪，區塊又排進佇列一次
check(#PLACED == 0, "這次來訪才第一次看見的區：同一次來訪再載入也不補")
LOTZONE.since = 500
resetLot()
for wx = 128, 132 do R.fresh[T.key(wx, 129)] = getTimestamp() end
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 0, "這次才第一次生成的區塊交給引擎，不補")
resetLot()
REJECT = true
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 0 and R.window.rejected == 10, "引擎沒把車放進世界（sqlId -1）不算數、不改車況")
REJECT = false
resetLot()
T.enabledAt = getTimestamp() - H
LOTZONE.since = 200
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 0, "剛開啟 1 小時、引擎記錄 200 遊戲小時前有人（約現實 12.5 小時）：不到 168 小時")
resetLot()
LOTZONE.since, worldAge = 3000, 5000
R.fillBlock(LOT_BLOCK, getTimestamp())
check(#PLACED == 10, "引擎記錄 3000 遊戲小時前有人（約現實 187 小時）：開啟當天就補")
worldAge = 1000
LOTZONE.since = 500
VehicleZoneDistribution.parkingstall.spawnRate = nil
writeConfig({})
advance(61000)
advance(1000)
check(R.on == false and T.enabledAt == nil and T.count() == 0, "關閉後停止記錄並清掉足跡")

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
