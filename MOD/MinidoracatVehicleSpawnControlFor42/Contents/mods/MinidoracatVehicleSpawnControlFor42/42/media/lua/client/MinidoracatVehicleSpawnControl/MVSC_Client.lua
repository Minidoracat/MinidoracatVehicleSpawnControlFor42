-- MinidoracatVehicleSpawnControl 客戶端資料模型：收伺服器快照、維護未套用的草稿、用共用核心即時算占比。
-- 伺服器才是權威；這裡只送意圖（apply／restore），結果以伺服器回覆與 changed 通知為準。
require "MinidoracatVehicleSpawnControl/MVSC_Core"

local M = MinidoracatVehicleSpawnControl
local C = {}
M.Client = C
M.NET_MODULE = "MinidoracatVehicleSpawnControl"

C.data = nil      -- { revision, base = { zones, aliasOf }, catalog, info, config, status, history }
C.draft = nil     -- raw 設定（與 config.json 同格式），面板編輯的對象
C.listeners = {}

-- ---------------------------------------------------------------- 傳輸
function C.send(cmd, args)
    local p = getPlayer()
    if isClient() then
        sendClientCommand(p, M.NET_MODULE, cmd, args or {})
    elseif M.ServerNet then
        M.ServerNet.onClientCommand(M.NET_MODULE, cmd, p, args or {}) -- 單人：同一個 Lua 狀態直接呼叫
    end
end

function C.on(fn) C.listeners[#C.listeners + 1] = fn end
function C.off(fn)
    for i = #C.listeners, 1, -1 do
        if C.listeners[i] == fn then table.remove(C.listeners, i) end
    end
end
local function emit(event, args)
    for _, fn in ipairs(C.listeners) do fn(event, args) end
end

function C.request()
    C.loading = { zones = {}, vehicles = {} }
    C.send("hello", {})
end

-- ---------------------------------------------------------------- 快照組裝
local function buildInfo(catalog)
    local info = { scripts = {}, sourceOf = {}, isNew = {} }
    for full, v in pairs(catalog) do
        info.scripts[full] = true
        info.sourceOf[full] = v.source
        if v.new then info.isNew[full] = true end
    end
    return info
end

local function localName(v, full)
    local key = "IGUI_VehicleName" .. tostring(v.nameKey)
    local text = getText(key)
    if text ~= nil and text ~= key then return text end
    if v.name and v.name ~= full then return v.name end
    return full
end

local function finishSnapshot(args)
    local L = C.loading
    local base = { zones = {}, aliasOf = {} }
    for name, z in pairs(L.zones) do
        base.zones[name] = { vehicles = z.vehicles or {}, params = z.params or {}, aliases = z.aliases or {} }
        for _, a in ipairs(z.aliases or {}) do base.aliasOf[a] = name end
    end
    for full, v in pairs(L.vehicles) do v.display = localName(v, full) end
    local dirty = C.hasChanges()
    C.data = { revision = args.revision, base = base, catalog = L.vehicles, info = buildInfo(L.vehicles),
        config = args.config or M.toRaw(M.defaultConfig()), status = args.status or {}, history = args.history or {} }
    C.loading = nil
    C.stale = nil
    if not dirty or C.replaceDraft then C.draft = M.copy(C.data.config) end
    C.replaceDraft = nil
    C.version = (C.version or 0) + 1
    emit("loaded", args)
end

C.handlers = {
    begin = function(args) C.loading = { sync = args.sync, zones = {}, vehicles = {} } end,
    zones = function(args)
        if not C.loading or C.loading.sync ~= args.sync then return end
        for k, v in pairs(args.items) do C.loading.zones[k] = v end
    end,
    vehicles = function(args)
        if not C.loading or C.loading.sync ~= args.sync then return end
        for k, v in pairs(args.items) do C.loading.vehicles[k] = v end
    end,
    done = function(args)
        if not C.loading or C.loading.sync ~= args.sync then return end
        finishSnapshot(args)
    end,
    applyResult = function(args)
        -- 套用成功：下一份快照直接成為草稿。草稿本身不清空——快照送達前面板每幀都還在讀它
        if args.ok then C.replaceDraft = true end
        emit("applyResult", args)
        if args.ok then C.request() end
    end,
    changed = function(args)
        if not C.data then return end
        if args.ok and args.revision ~= C.data.revision then
            if C.hasChanges() then
                C.stale = args.revision -- 有未套用的編輯：只提示，不蓋掉
                emit("stale", args)
            else
                C.request()
            end
        elseif not args.ok and args.source == "file" then
            C.data.status = { ok = false, source = "file", revision = C.data.revision, errors = args.errors or {} }
            emit("status", args)
        end
    end,
    denied = function(args) emit("denied", args) end,
}

function C.onServerCommand(module, command, args)
    if module ~= M.NET_MODULE then return end
    local fn = C.handlers[command]
    if fn then fn(args or {}) end
end
Events.OnServerCommand.Add(C.onServerCommand)

-- 目前生效的修訂是怎麼來、何時套用的（回傳 source, at）。開服時設定沒變不會新增修訂，status 記的是較晚那次
-- 開服檢查，所以先從變更紀錄找這個修訂；找不到（紀錄被截掉）才退回 status
function C.revisionOrigin()
    local d = C.data
    if not d then return nil, nil end
    local h = d.history or {}
    for i = #h, 1, -1 do
        if h[i].revision == d.revision then return h[i].source, h[i].at end
    end
    local st = d.status or {}
    return st.source, st.checkedAt
end

-- ---------------------------------------------------------------- 草稿
function C.changes()
    if not (C.data and C.draft) then return {} end
    return M.diff(C.data.config, C.draft)
end

function C.hasChanges()
    return #C.changes() > 0
end

function C.discard()
    if C.data then C.draft = M.copy(C.data.config) end
    C.version = (C.version or 0) + 1
    emit("draft")
end

function C.apply(force)
    if not (C.data and C.draft) then return end
    C.send("apply", { base = C.data.revision, config = C.draft, force = force == true })
end

function C.restore(revision)
    C.send("restore", { revision = revision })
end

-- 草稿轉成 validate 結構才能交給 build；草稿只會由面板產生，驗證失敗代表程式錯
function C.effective()
    if not (C.data and C.draft) then return nil end
    if C.cacheVersion == C.version and C.cache then return C.cache end
    local cfg = M.validate(C.draft, { zones = C.data.base.zones, aliasOf = C.data.base.aliasOf, scripts = C.data.info.scripts })
    cfg = cfg or M.defaultConfig()
    C.cache = M.build(C.data.base, cfg, C.data.info)
    C.cacheCfg = cfg
    C.cacheVersion = C.version
    return C.cache
end

local function touched()
    C.version = (C.version or 0) + 1
    if (C.muted or 0) == 0 then emit("draft") end
end

-- 批次編輯：中間不發 draft 事件，結束只發一次（一次改上百台車時面板不必逐台重建）
function C.batch(fn)
    C.muted = (C.muted or 0) + 1
    local ok, err = pcall(fn)
    C.muted = C.muted - 1
    touched()
    if not ok then error(err) end
end

local function zoneEntry(zone)
    C.draft.zones[zone] = C.draft.zones[zone] or {}
    return C.draft.zones[zone]
end

-- 設區域權重；等於原始權重就移除覆寫（草稿保持最小）
function C.setWeight(zone, script, w)
    w = math.max(0, math.floor(w * 100 + 0.5) / 100)
    local z = zoneEntry(zone)
    local orig = C.data.base.zones[zone] and C.data.base.zones[zone].vehicles[script]
    z.weights = z.weights or {}
    if orig and orig.spawnChance == w then z.weights[script] = nil else z.weights[script] = w end
    touched()
end

function C.setParam(zone, param, v)
    local z = zoneEntry(zone)
    local orig = C.data.base.zones[zone] and C.data.base.zones[zone].params[param]
    if orig == nil then orig = M.PARAM_DEFAULTS[param] end
    if orig == v then z[param] = nil else z[param] = v end
    touched()
end

function C.setEnabled(script, enabled)
    local v = C.draft.vehicles[script] or {}
    if enabled then v.enabled = nil else v.enabled = false end
    if C.draft.newVehicles == "disable" and enabled and C.data.info.isNew[script] then v.enabled = true end
    C.draft.vehicles[script] = v
    if v.enabled == nil and v.multiplier == nil then C.draft.vehicles[script] = nil end
    touched()
end

function C.resetZoneWeights(zone, scripts)
    local z = C.draft.zones[zone]
    if z and z.weights then
        for _, s in ipairs(scripts) do z.weights[s] = nil end
    end
    touched()
end

function C.resetZone(zone)
    C.draft.zones[zone] = nil
    touched()
end

function C.setNewVehicles(mode)
    C.draft.newVehicles = mode
    touched()
end

-- 倍率（設計 4.1 的來源層／車輛層）：kind 是 "sources" 或 "vehicles"；1 表示沒有覆寫
function C.multOf(kind, key)
    local e = C.draft[kind] and C.draft[kind][key]
    return e and e.multiplier or 1
end

function C.setMultiplier(kind, key, m)
    m = math.max(0, math.floor(m * 100 + 0.5) / 100)
    C.draft[kind] = C.draft[kind] or {}
    local e = C.draft[kind][key] or {}
    if m == 1 then e.multiplier = nil else e.multiplier = m end
    C.draft[kind][key] = e
    local empty = true -- Kahlua 沒有 next()
    for _ in pairs(e) do empty = false break end
    if empty then C.draft[kind][key] = nil end
    touched()
end

-- 目前（草稿）某區某車的權重：有覆寫用覆寫，否則原始
function C.weightOf(zone, script)
    local z = C.draft.zones[zone]
    if z and z.weights and z.weights[script] ~= nil then return z.weights[script] end
    local orig = C.data.base.zones[zone] and C.data.base.zones[zone].vehicles[script]
    return orig and orig.spawnChance or 0
end

function C.paramOf(zone, param)
    local z = C.draft.zones[zone]
    if z and z[param] ~= nil then return z[param] end
    local v = C.data.base.zones[zone] and C.data.base.zones[zone].params[param]
    if v == nil then return M.PARAM_DEFAULTS[param] end
    return v
end

-- 原本（沒有任何覆寫）時某車在某區的占比 0–1；每份快照算一次
function C.baseShare(zone, script)
    if C.baseFor ~= C.data then
        C.baseFor, C.baseShares = C.data, {}
        for name, z in pairs(M.build(C.data.base, M.defaultConfig(), C.data.info)) do
            local total, shares = 0, {}
            for _, def in pairs(z.vehicles) do total = total + def.spawnChance end
            for s, def in pairs(z.vehicles) do shares[s] = total > 0 and def.spawnChance / total or 0 end
            C.baseShares[name] = shares
        end
    end
    local z = C.baseShares[zone]
    return z and z[script] or 0
end

function C.isEnabled(script)
    local cfg = C.effective() and C.cacheCfg
    return cfg and M.enabled(cfg, C.data.info, script)
end
