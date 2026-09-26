-- MinidoracatVehicleSpawnControl 核心（純邏輯，不碰引擎）：設定驗證、原始分布快照、計算套用後的區域表。
-- 引擎事實（出處見 AGENTS.md「API 出處對照」與踩坑錄）：
--   * VehicleType.init 以 100/權重總和正規化；權重全 0 會變 NaN 並固定選到最後一台（VehicleType.java:72-81、IsoChunk.java:1318-1330）
--     → 停用一律「從清單移除」，套用結果不得出現 <= 0 的權重。
--   * 清單為空時 RandomizeModel 回 false，該區域本次不生車（IsoChunk.java:1000-1002,1314-1316）→ 這就是「整區停用」。
--   * spawnRate=0 仍有 1%（IsoChunk.java:992 用 <=），所以不拿 spawnRate 當停用開關。
--   * 快取以原樣鍵存入、查詢先轉小寫（VehicleType.java:55,135,160,173）。原版與 MOD 都有大小寫混用的區域鍵
--     （luxuryDealership、middleClass、MOD 的 SemiTankerOnly），所以設定檔的區域名必須和執行期表的鍵完全相同，不強制小寫。
require "MinidoracatVehicleSpawnControl/MVSC_Json"
MinidoracatVehicleSpawnControl = MinidoracatVehicleSpawnControl or {}
local M = MinidoracatVehicleSpawnControl

M.MOD_ID = "MinidoracatVehicleSpawnControlFor42"
M.LOG = "[MinidoracatVehicleSpawnControlFor42] "
M.SCHEMA = 1
M.VANILLA = "pz-vanilla" -- ScriptManager.java:651

-- 可覆寫的區域參數與範圍（VehicleType.java:20-36,87-133 讀取的數值欄位）
M.ZONE_PARAMS = {
    spawnRate = { 0, 100 },
    chanceToSpawnNormal = { 0, 100 },
    chanceToSpawnBurnt = { 0, 100 },
    chanceToSpawnSpecial = { 0, 100 },
    chanceToPartDamage = { 0, 100 },
    chanceToSpawnKey = { 0, 100 },
    baseVehicleQuality = { 0, 2 },
}

function M.defaultConfig()
    return { schema = M.SCHEMA, newVehicles = "keep", sources = {}, vehicles = {}, zones = {} }
end

-- ---------------------------------------------------------------- 原始分布快照
-- dist＝VehicleZoneDistribution。business2–12 等別名指向同一張表：以表身分分組，
-- 字典序最小的鍵當正式名稱，其他記成 aliases（只寫回一次，也不接受別名當設定鍵）。
-- resolve(name) 回完整 script 名或 nil：MOD 常用不帶模組的短名（如 "SemiTruck"，E2E core-mp 實見），引擎查得到
-- （ScriptManager.getVehicle），但停用與倍率以完整名稱比對，所以快照時統一成完整名稱；同名合併時權重相加。
local function copyVehicles(vehicles, resolve)
    local out = {}
    if type(vehicles) ~= "table" then return out end
    for script, def in pairs(vehicles) do
        if type(def) == "table" then
            local name = tostring(script)
            local full = resolve and resolve(name) or name
            local w = tonumber(def.spawnChance) or 0
            local cur = out[full]
            if cur then cur.spawnChance = cur.spawnChance + w
            else out[full] = { index = tonumber(def.index) or -1, spawnChance = w } end
        end
    end
    return out
end

function M.snapshot(dist, resolve)
    local byTable, keysOf = {}, {}
    for key, def in pairs(dist) do
        if type(def) == "table" then
            local k = tostring(key)
            if not keysOf[def] then keysOf[def] = {}; byTable[#byTable + 1] = def end
            local list = keysOf[def]
            list[#list + 1] = k
        end
    end
    local base = { zones = {}, aliasOf = {} }
    for _, def in ipairs(byTable) do
        local keys = M.sortSafe(keysOf[def])
        local name = keys[1]
        local params = {}
        for p in pairs(M.ZONE_PARAMS) do params[p] = def[p] end
        local aliases = {}
        for i = 2, #keys do aliases[#aliases + 1] = keys[i]; base.aliasOf[keys[i]] = name end
        base.zones[name] = { vehicles = copyVehicles(def.vehicles, resolve), params = params, aliases = aliases, live = def }
    end
    return base
end

-- ---------------------------------------------------------------- 驗證
-- 回 cfg, errors, warnings。有任何 error 整份拒絕（保留舊設定）；warning 只是被忽略的項目。
local function isObject(v) return type(v) == "table" and v ~= M.JSON_NULL end

local function checkNumber(v, lo, hi)
    return type(v) == "number" and v == v and v >= lo and (hi == nil or v <= hi)
end

-- ctx = { zones = base.zones, aliasOf = base.aliasOf, scripts = { [fullName] = true } }
function M.validate(raw, ctx)
    local errors, warnings = {}, {}
    local function err(path, msg) errors[#errors + 1] = path .. ": " .. msg end
    local function warn(path, msg) warnings[#warnings + 1] = path .. ": " .. msg end
    if not isObject(raw) then
        err("(root)", "must be a JSON object { ... }")
        return nil, errors, warnings
    end
    local cfg = M.defaultConfig()
    local known = { schema = true, revision = true, newVehicles = true, sources = true, vehicles = true, zones = true }
    for k in pairs(raw) do
        if not known[k] then warn(k, "unknown key, ignored") end
    end
    if raw.schema ~= nil and raw.schema ~= M.SCHEMA then err("schema", "must be " .. M.SCHEMA) end
    if raw.newVehicles ~= nil then
        if raw.newVehicles == "keep" or raw.newVehicles == "disable" then cfg.newVehicles = raw.newVehicles
        else err("newVehicles", 'must be "keep" or "disable"') end
    end

    if raw.sources ~= nil then
        if not isObject(raw.sources) then err("sources", "must be an object { \"<modId>\": { ... } }")
        else
            for modId, s in pairs(raw.sources) do
                local path = "sources." .. modId
                if not isObject(s) then err(path, "must be an object like { \"multiplier\": 0.5 }")
                else
                    local entry = {}
                    if s.multiplier ~= nil then
                        if checkNumber(s.multiplier, 0) then entry.multiplier = s.multiplier
                        else err(path .. ".multiplier", "must be a number >= 0") end
                    end
                    cfg.sources[modId] = entry
                end
            end
        end
    end

    if raw.vehicles ~= nil then
        if not isObject(raw.vehicles) then err("vehicles", "must be an object { \"<Module.Script>\": { ... } }")
        else
            for script, v in pairs(raw.vehicles) do
                local path = "vehicles." .. script
                if not isObject(v) then err(path, "must be an object like { \"enabled\": false }")
                else
                    local entry = {}
                    if v.enabled ~= nil then
                        if type(v.enabled) == "boolean" then entry.enabled = v.enabled
                        else err(path .. ".enabled", "must be true or false") end
                    end
                    if v.multiplier ~= nil then
                        if checkNumber(v.multiplier, 0) then entry.multiplier = v.multiplier
                        else err(path .. ".multiplier", "must be a number >= 0") end
                    end
                    if not ctx.scripts[script] then warn(path, "vehicle script not found (mod removed?), kept but has no effect") end
                    cfg.vehicles[script] = entry
                end
            end
        end
    end

    if raw.zones ~= nil then
        if not isObject(raw.zones) then err("zones", "must be an object { \"<zone>\": { ... } }")
        else
            -- 大小寫不同但其實存在的鍵：報錯並給正確寫法（不然管理員會以為設定生效了）
            local byLower = {}
            for name in pairs(ctx.zones) do byLower[string.lower(name)] = name end
            for alias in pairs(ctx.aliasOf) do
                local k = string.lower(alias)
                byLower[k] = byLower[k] or alias
            end
            for zone, z in pairs(raw.zones) do
                local path = "zones." .. zone
                local exact = byLower[string.lower(zone)]
                if not ctx.zones[zone] and not ctx.aliasOf[zone] and exact then
                    err(path, 'zone names are case-sensitive, use "' .. exact .. '"')
                elseif ctx.aliasOf[zone] then
                    err(path, 'is an alias of "' .. ctx.aliasOf[zone] .. '", configure "' .. ctx.aliasOf[zone] .. '" instead')
                elseif not isObject(z) then
                    err(path, "must be an object")
                else
                    if not ctx.zones[zone] then warn(path, "zone not found (mod removed?), kept but has no effect") end
                    local entry = { params = {}, weights = {}, skins = {} }
                    for k, v in pairs(z) do
                        local range = M.ZONE_PARAMS[k]
                        if range then
                            if checkNumber(v, range[1], range[2]) then entry.params[k] = v
                            else err(path .. "." .. k, "must be a number from " .. range[1] .. " to " .. range[2]) end
                        elseif k ~= "weights" and k ~= "skins" then
                            warn(path .. "." .. k, "unknown key, ignored")
                        end
                    end
                    if z.weights ~= nil then
                        if not isObject(z.weights) then err(path .. ".weights", "must be an object { \"<Module.Script>\": <number> }")
                        else
                            for script, w in pairs(z.weights) do
                                if not checkNumber(w, 0) then err(path .. ".weights." .. script, "must be a number >= 0 (0 removes it from this zone)")
                                else
                                    entry.weights[script] = w
                                    if not ctx.scripts[script] then warn(path .. ".weights." .. script, "vehicle script not found, ignored") end
                                end
                            end
                        end
                    end
                    if z.skins ~= nil then
                        if not isObject(z.skins) then err(path .. ".skins", "must be an object { \"<Module.Script>\": <index> }")
                        else
                            for script, i in pairs(z.skins) do
                                if not checkNumber(i, -1) or i ~= math.floor(i) then err(path .. ".skins." .. script, "must be a whole number, -1 means random")
                                else entry.skins[script] = i end
                            end
                        end
                    end
                    cfg.zones[zone] = entry
                end
            end
        end
    end
    if #errors > 0 then return nil, M.sortSafe(errors), M.sortSafe(warnings) end
    return cfg, errors, M.sortSafe(warnings)
end

-- ---------------------------------------------------------------- 計算
-- info = { sourceOf = { [script] = modId }, isNew = { [script] = true }, scripts = { [script] = true } }
-- 回 { [zone] = { vehicles = {...}, params = {...} } }，vehicles 只含權重 > 0 的車。
function M.enabled(cfg, info, script)
    local v = cfg.vehicles[script]
    if v and v.enabled ~= nil then return v.enabled end
    if cfg.newVehicles == "disable" and info.isNew[script] then return false end
    return true
end

function M.multiplier(cfg, info, script)
    local m = 1
    local src = cfg.sources[info.sourceOf[script] or ""]
    if src and src.multiplier then m = m * src.multiplier end
    local v = cfg.vehicles[script]
    if v and v.multiplier then m = m * v.multiplier end
    return m
end

function M.build(base, cfg, info)
    local out = {}
    for name, zone in pairs(base.zones) do
        local zc = cfg.zones[name]
        local weights = {}
        for script, def in pairs(zone.vehicles) do weights[script] = { index = def.index, w = def.spawnChance } end
        if zc then
            for script, w in pairs(zc.weights) do
                if info.scripts[script] then
                    local cur = weights[script]
                    if cur then cur.w = w else weights[script] = { index = -1, w = w } end
                end
            end
        end
        local vehicles = {}
        for script, e in pairs(weights) do
            local w = e.w * M.multiplier(cfg, info, script)
            if w > 0 and M.enabled(cfg, info, script) then
                local index = e.index
                if zc and zc.skins[script] ~= nil then index = zc.skins[script] end
                vehicles[script] = { index = index, spawnChance = w }
            end
        end
        local params = {}
        for p in pairs(M.ZONE_PARAMS) do
            if zc and zc.params[p] ~= nil then params[p] = zc.params[p] else params[p] = zone.params[p] end
        end
        out[name] = { vehicles = vehicles, params = params }
    end
    return out
end
