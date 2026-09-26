-- MinidoracatVehicleSpawnControl 伺服器端網路命令（管理面板）。
--   權限：每個命令都在伺服器重新檢查 Capability.SandboxOptions（原版「沙盒設定」同一權限，ISAdminPanelUI.lua:226；
--   預設 moderator／admin 有，Roles.java:448-471）。UI 的 enable 只是方便，不是防線。
--   傳輸：目錄與區域分批送（單一命令走 1 MB 緩衝，UdpConnection.java:39-44）。
--   單人：sendServerCommand 在非伺服器端是 no-op（LuaManager.java:8942-8946），所以直接呼叫 client 的處理函式。
if isClient() then return end
require "MinidoracatVehicleSpawnControl/MVSC_Server"

local M = MinidoracatVehicleSpawnControl
local S = M.Server
local N = {}
M.ServerNet = N

M.NET_MODULE = "MinidoracatVehicleSpawnControl"
N.ZONE_BATCH = 8
N.VEHICLE_BATCH = 60

function N.canAdmin(player)
    if not isServer() then return true end -- 單人：本機玩家就是擁有者（入口只在 debug 選單出現）
    local role = player and player:getRole()
    return role ~= nil and role:hasCapability(Capability.SandboxOptions)
end

function N.reply(player, cmd, args)
    if isServer() then
        sendServerCommand(player, M.NET_MODULE, cmd, args or {})
    elseif M.Client and M.Client.onServerCommand then
        M.Client.onServerCommand(M.NET_MODULE, cmd, args or {})
    end
end

local function statusCopy()
    return M.copy(S.status or {})
end

-- 面板需要的全部資料：原始分布、車輛目錄、目前設定、狀態、變更紀錄
function N.sendSnapshot(player)
    N.syncId = (N.syncId or 0) + 1
    local sync = N.syncId
    local zoneNames, vehicleNames = M.sortedKeys(S.base.zones), M.sortedKeys(S.info.catalog)
    N.reply(player, "begin", { sync = sync, revision = S.state.revision, zones = #zoneNames, vehicles = #vehicleNames })
    local batch = {}
    local n = 0
    for _, name in ipairs(zoneNames) do
        local z = S.base.zones[name]
        batch[name] = { vehicles = M.copy(z.vehicles), params = M.copy(z.params), aliases = M.copy(z.aliases) }
        n = n + 1
        if n >= N.ZONE_BATCH then N.reply(player, "zones", { sync = sync, items = batch }); batch, n = {}, 0 end
    end
    if n > 0 then N.reply(player, "zones", { sync = sync, items = batch }) end
    batch, n = {}, 0
    for _, full in ipairs(vehicleNames) do
        local v = S.info.catalog[full]
        batch[full] = { nameKey = v.nameKey, name = v.name, source = v.source, sourceName = v.sourceName,
            skins = v.skins, new = S.info.isNew[full] == true }
        n = n + 1
        if n >= N.VEHICLE_BATCH then N.reply(player, "vehicles", { sync = sync, items = batch }); batch, n = {}, 0 end
    end
    if n > 0 then N.reply(player, "vehicles", { sync = sync, items = batch }) end
    N.reply(player, "done", { sync = sync, revision = S.state.revision, config = M.toRaw(S.cfg),
        status = statusCopy(), history = M.copy(S.history) })
end

local function username(player)
    return player and player:getUsername() or "local"
end

N.handlers = {}

N.handlers.hello = function(player)
    N.sendSnapshot(player)
end

-- args = { base = 面板載入時的修訂號, config = raw 設定, force = 覆寫外部修改 }
N.handlers.apply = function(player, args)
    if type(args.config) ~= "table" then
        N.reply(player, "applyResult", { ok = false, errors = { "missing config" } })
        return
    end
    if not args.force and tonumber(args.base) ~= S.state.revision then
        N.reply(player, "applyResult", { ok = false, stale = true, revision = S.state.revision })
        return
    end
    local text = M.jsonEncode(args.config, true) .. "\n"
    local ok, errors = S.applyText(text, "panel", { write = true, user = username(player) })
    N.reply(player, "applyResult", { ok = ok, errors = errors, revision = S.state.revision })
end

-- args = { revision }：只能還原到備份槽還沒被覆寫的修訂（最近 10 次）
N.handlers.restore = function(player, args)
    local rev = tonumber(args.revision)
    local entry
    for _, e in ipairs(S.history) do
        if e.revision == rev then entry = e end
    end
    if not entry or S.state.revision - rev >= S.BACKUP_SLOTS then
        N.reply(player, "applyResult", { ok = false, errors = { "backup for revision " .. tostring(rev) .. " is no longer kept" } })
        return
    end
    local text = S.readBackup(entry.slot)
    if not text then
        N.reply(player, "applyResult", { ok = false, errors = { "backup file missing" } })
        return
    end
    local ok, errors = S.applyText(text, "restore", { write = true, user = username(player) })
    N.reply(player, "applyResult", { ok = ok, errors = errors, revision = S.state.revision })
end

function N.onClientCommand(module, command, player, args)
    if module ~= M.NET_MODULE then return end
    local fn = N.handlers[command]
    if not fn then return end
    if not N.canAdmin(player) then
        print(M.LOG .. "denied " .. tostring(command) .. " from " .. username(player))
        N.reply(player, "denied", {})
        return
    end
    if not S.base then
        N.reply(player, "applyResult", { ok = false, errors = { "server not ready" } })
        return
    end
    fn(player, type(args) == "table" and args or {})
end

-- 任何來源套用或拒絕後，通知線上有權限的人（面板開著就會提示重新載入）
-- 開服套用時伺服器網路還沒啟動：OnInitGlobalModData 早於 GameServer.startServer 建立 udpEngine，
-- 這時 getOnlinePlayers 會 NPE（GameServer.java:3560）；也沒有人在線，直接略過。
S.notify = function(ok, source, errors)
    if source == "boot" then return end
    local args = { ok = ok, source = source, revision = S.state and S.state.revision or 0, errors = errors }
    if not isServer() then
        N.reply(nil, "changed", args)
        return
    end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if N.canAdmin(p) then N.reply(p, "changed", args) end
    end
end

Events.OnClientCommand.Add(N.onClientCommand)
