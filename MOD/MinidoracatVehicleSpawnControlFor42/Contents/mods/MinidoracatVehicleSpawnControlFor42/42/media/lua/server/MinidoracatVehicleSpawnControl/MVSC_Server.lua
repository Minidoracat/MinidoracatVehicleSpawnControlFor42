-- MinidoracatVehicleSpawnControl 伺服器端（MP 專用伺服器與單人的權威端；MP client 不跑）。
--   開服：快照原始 VehicleZoneDistribution → 列舉車輛 script 與來源 MOD → 讀 config.json → 改表 → VehicleType.Reset()
--   之後每 60 秒（真實時間）讀一次 config.json，內容變了才解析、驗證、套用。
-- 引擎事實：改表後必須 Reset() 才會生效；Reset 與生車同在伺服器主迴圈，可隨時呼叫
--   （VehicleType.java:231-234、GameServer.java:972；E2E spike-mp 2026-09-26 實機驗證）。
-- 檔案都在 <cacheDir>/Lua/MinidoracatVehicleSpawnControl/（getFileReader/Writer 的根，LuaManager.java:5932-5958,6723-6755）。
if isClient() then return end
require "MinidoracatVehicleSpawnControl/MVSC_Core"

local M = MinidoracatVehicleSpawnControl
local S = {}
M.Server = S

local DIR = "MinidoracatVehicleSpawnControl/"
S.CONFIG = DIR .. "config.json"
S.CATALOG = DIR .. "catalog.json"
S.STATUS = DIR .. "status.json"
S.STATE = DIR .. "state.json"
S.HISTORY = DIR .. "history.json"
S.HISTORY_MAX = 50
S.BACKUP_SLOTS = 10
S.POLL_MS = 60000

-- ---------------------------------------------------------------- 檔案
function S.readText(path)
    local r = getFileReader(path, false)
    if not r then return nil end
    local lines = {}
    local line = r:readLine()
    while line ~= nil do
        lines[#lines + 1] = line
        line = r:readLine()
    end
    r:close()
    return table.concat(lines, "\n")
end

function S.writeText(path, text)
    local w = getFileWriter(path, true, false)
    if not w then
        print(M.LOG .. "cannot write " .. path)
        return false
    end
    w:write(text)
    w:close()
    return true
end

local function writeJson(path, value)
    return S.writeText(path, M.jsonEncode(value, true) .. "\n")
end

-- ---------------------------------------------------------------- 車輛目錄
-- 來源以 script body 的載入紀錄判斷（BaseScriptObject.java:137-144：modId、body 交錯），不看 module 名。
-- 第一筆是建立者；之後的是覆寫者。
local function sourceName(modId)
    if modId == M.VANILLA then return "Project Zomboid" end
    local info = getModInfoByID(modId)
    return info and info:getName() or modId
end

local function displayName(script)
    local model = script:getCarModelName() or script:getName()
    local key = "IGUI_VehicleName" .. tostring(model)
    local text = getText(key)
    if text == nil or text == key then return script:getFullName() end
    return text
end

function S.collectScripts()
    local list = ScriptManager.instance:getAllVehicleScripts()
    local out = {}
    for i = 0, list:size() - 1 do
        local s = list:get(i)
        local full = s:getFullName()
        local bodies = s:getLoadedScriptBodies()
        local src, overrides = "unknown", {}
        if bodies and bodies:size() > 0 then
            src = bodies:get(0)
            for j = 2, bodies:size() - 1, 2 do
                local m = bodies:get(j)
                if m ~= src then overrides[#overrides + 1] = m end
            end
        end
        out[full] = { name = displayName(s), nameKey = tostring(s:getCarModelName() or s:getName()), source = src,
            sourceName = sourceName(src), overriddenBy = overrides, skins = s:getSkinCount() }
    end
    return out
end

-- ---------------------------------------------------------------- 狀態
local function loadState()
    local text = S.readText(S.STATE)
    local st = text and M.jsonDecode(text)
    if type(st) ~= "table" then st = {} end
    if type(st.firstSeen) ~= "table" then st.firstSeen = nil end
    st.revision = tonumber(st.revision) or 0
    return st
end

-- 首次安裝時現有車輛都記 0（不是「新偵測」）；之後才出現的記出現時間。
local function markSeen(st, scripts, now)
    local firstRun = st.firstSeen == nil
    st.firstSeen = st.firstSeen or {}
    local isNew = {}
    for full in pairs(scripts) do
        if st.firstSeen[full] == nil then st.firstSeen[full] = firstRun and 0 or now end
        if st.firstSeen[full] > 0 then isNew[full] = true end
    end
    return isNew
end

-- ---------------------------------------------------------------- 套用
local function writeLive(built)
    for name, z in pairs(built) do
        local live = S.base.zones[name].live
        local vehicles = {}
        for script, def in pairs(z.vehicles) do vehicles[script] = { index = def.index, spawnChance = def.spawnChance } end
        live.vehicles = vehicles
        for p in pairs(M.ZONE_PARAMS) do live[p] = z.params[p] end
    end
    VehicleType.Reset() -- 下一次生車時用新表重建快取
end

local function writeCatalog(built)
    local vehicles, zones = {}, {}
    for full, s in pairs(S.info.catalog) do
        local e = { name = s.name, source = s.source, sourceName = s.sourceName, skins = s.skins,
            new = S.info.isNew[full] == true, enabled = M.enabled(S.cfg, S.info, full), zones = {} }
        if #s.overriddenBy > 0 then e.overriddenBy = s.overriddenBy end
        vehicles[full] = e
    end
    for name, z in pairs(built) do
        local total = 0
        for _, def in pairs(z.vehicles) do total = total + def.spawnChance end
        local list = {}
        for script, def in pairs(z.vehicles) do
            list[script] = { weight = def.spawnChance, percent = math.floor(def.spawnChance / total * 1000 + 0.5) / 10 }
            local v = vehicles[script]
            if v then v.zones[#v.zones + 1] = name end
        end
        zones[name] = { aliases = S.base.zones[name].aliases, params = z.params, vehicles = list,
            original = S.base.zones[name].vehicles }
    end
    for _, v in pairs(vehicles) do M.sortSafe(v.zones) end
    writeJson(S.CATALOG, { revision = S.state.revision, generatedAt = getTimestampMs(),
        note = "Generated by the server. Read-only: edit config.json instead.", vehicles = vehicles, zones = zones })
end

local function writeStatus(ok, source, errors, warnings)
    local newList = {}
    for full in pairs(S.info.isNew) do newList[#newList + 1] = full end
    S.status = { ok = ok, source = source, revision = S.state.revision, checkedAt = getTimestampMs(),
        errors = errors or {}, warnings = warnings or {}, newVehicles = M.sortSafe(newList) }
    writeJson(S.STATUS, S.status)
end

-- 接受的設定依修訂號輪流寫進 10 個槽（Lua 沒有刪檔 API）；回傳槽號供變更紀錄還原
local function backup(text)
    local slot = S.state.revision % S.BACKUP_SLOTS + 1
    S.writeText(DIR .. "backups/config-" .. slot .. ".json", text)
    return slot
end

function S.readBackup(slot)
    return S.readText(DIR .. "backups/config-" .. slot .. ".json")
end

local function addHistory(entry)
    local list = S.history
    list[#list + 1] = entry
    while #list > S.HISTORY_MAX do table.remove(list, 1) end
    writeJson(S.HISTORY, list)
end

-- 通知線上管理員（MVSC_ServerNet 提供）。通知失敗不能中斷套用：此時修訂號已遞增、表已改好，
-- 中斷會讓 init 半途停下、輪詢永遠不啟動（E2E panel-mp 實踩：開服時 getOnlinePlayers 丟 NPE）。
local function notify(ok, source, errors)
    if not S.notify then return end
    local okCall, err = pcall(S.notify, ok, source, errors)
    if not okCall then print(M.LOG .. "notify failed: " .. tostring(err)) end
end

-- 這次套用改了什麼（變更紀錄的摘要）。開服時比對上一筆紀錄的備份（伺服器關著時可能有人改過檔），
-- 沒有可比的就不寫；其他情況比對目前生效的設定
S.HISTORY_CHANGES = 40
function S.changesFrom(source, cfg)
    local prev
    if source == "boot" then
        local last = S.history[#S.history]
        local raw = last and last.slot and M.jsonDecode(S.readBackup(last.slot) or "")
        local old = type(raw) == "table" and M.validate(raw, { zones = S.base.zones, aliasOf = S.base.aliasOf, scripts = S.info.scripts })
        if not old then return nil end
        prev = M.toRaw(old)
    else
        prev = M.toRaw(S.cfg)
    end
    return M.changes(prev, M.toRaw(cfg))
end

-- 解析＋驗證＋套用一份設定檔文字。失敗時保留目前生效的設定（也不寫檔）。
-- opts.write＝驗證通過後才寫入 config.json（面板套用、還原）；opts.user＝操作者（變更紀錄）。回 ok, errors。
function S.applyText(text, source, opts)
    opts = opts or {}
    local raw, perr = M.jsonDecode(text)
    local cfg, errors, warnings
    if raw == nil then
        errors, warnings = { tostring(perr) }, {}
    else
        cfg, errors, warnings = M.validate(raw, { zones = S.base.zones, aliasOf = S.base.aliasOf, scripts = S.info.scripts })
    end
    if not cfg then
        for _, e in ipairs(errors) do print(M.LOG .. "config rejected (" .. source .. "): " .. e) end
        if not opts.write then writeStatus(false, source, errors, warnings) end -- 面板送錯只回給送的人，不蓋掉檔案狀態
        notify(false, source, errors)
        return false, errors
    end
    if opts.write then
        S.writeText(S.CONFIG, text)
        S.lastText = S.readText(S.CONFIG) -- 讀回值當輪詢基準（readLine 會吃掉結尾換行）
    end
    local changes = S.changesFrom(source, cfg)
    -- 開服時和上一筆紀錄內容相同：照常重套（重開服後分布表回到原狀），但不加修訂號、不備份、不寫變更紀錄，
    -- 否則每次重啟都留一筆「與前一版內容相同」，10 個備份槽幾天內就被同一份設定洗掉（服主 2026-10-03 要求）。
    -- changes 為 nil（沒有上一筆可比，例如第一次開服）照常記成新修訂
    local unchanged = source == "boot" and changes ~= nil and #changes == 0
    S.cfg = cfg
    local built = M.build(S.base, cfg, S.info)
    writeLive(built)
    if not unchanged then S.state.revision = S.state.revision + 1 end
    writeJson(S.STATE, S.state) -- 開服時 markSeen 可能新增了首次出現的車，沒變更也要存
    local slot = nil
    if not unchanged then slot = backup(text) end
    writeCatalog(built)
    writeStatus(true, source, {}, warnings)
    if not unchanged then
        addHistory({ revision = S.state.revision, at = getTimestampMs(), source = source, user = opts.user or "", slot = slot,
            changes = changes and M.head(changes, S.HISTORY_CHANGES) or nil,
            changeCount = changes and #changes or nil })
    end
    for _, w in ipairs(warnings) do print(M.LOG .. "config warning: " .. w) end
    if unchanged then
        print(M.LOG .. "config unchanged since revision " .. S.state.revision .. ", re-applied without a new revision (boot)")
    else
        print(M.LOG .. "applied config revision " .. S.state.revision .. " (" .. source .. (opts.user and (", " .. opts.user) or "") .. ")")
    end
    notify(true, source, {})
    return true, {}
end

local function loadHistory()
    local text = S.readText(S.HISTORY)
    local list = text and M.jsonDecode(text)
    if type(list) ~= "table" then return {} end
    local out = {}
    for _, e in ipairs(list) do
        if type(e) == "table" and tonumber(e.revision) then out[#out + 1] = e end
    end
    return out
end

-- ---------------------------------------------------------------- 開服與輪詢
function S.init()
    if S.base then return end
    S.base = M.snapshot(VehicleZoneDistribution, function(name)
        local s = ScriptManager.instance:getVehicle(name)
        return s and s:getFullName() or nil
    end)
    local catalog = S.collectScripts()
    local scripts = {}
    for full in pairs(catalog) do scripts[full] = true end
    S.state = loadState()
    S.history = loadHistory()
    S.info = { catalog = catalog, scripts = scripts, sourceOf = {}, isNew = markSeen(S.state, scripts, getTimestampMs()) }
    for full, s in pairs(catalog) do S.info.sourceOf[full] = s.source end
    S.cfg = M.defaultConfig()

    local text = S.readText(S.CONFIG)
    if text == nil then
        S.writeText(S.CONFIG, M.jsonEncode(M.defaultConfig(), true) .. "\n")
        print(M.LOG .. "created default " .. S.CONFIG)
        -- 以讀回的內容當比對基準：readLine 會吃掉結尾換行，拿寫入字串比會被輪詢誤判成外部修改
        text = S.readText(S.CONFIG) or ""
    end
    S.lastText = text
    if not S.applyText(text, "boot") then
        -- 開服時設定檔壞掉：用原始分布（空設定）啟動，讓目錄與狀態仍可用
        local built = M.build(S.base, S.cfg, S.info)
        writeLive(built)
        writeJson(S.STATE, S.state)
        writeCatalog(built)
    end
    S.nextPoll = getTimestampMs() + S.POLL_MS
end

function S.poll()
    local text = S.readText(S.CONFIG)
    if text == nil or text == S.lastText then return end
    S.lastText = text
    S.applyText(text, "file")
end

local function onTick()
    if not S.base then return end
    local now = getTimestampMs()
    if now < S.nextPoll then return end
    S.nextPoll = now + S.POLL_MS
    S.poll()
end

-- OnInitGlobalModData 在專用伺服器與單人都會觸發，且早於第一次生車（E2E spike-mp）
Events.OnInitGlobalModData.Add(S.init)
Events.OnTick.Add(onTick)
