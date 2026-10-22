-- MinidoracatVehicleSpawnControl 已探索停車區補車（設計：docs/design-proposals/vehicle-spawn-control.md 第 9 節）。
-- 伺服器與單人跑；MP 客戶端在檔頭就返回。只加車：不刪、不移、不修已在世界上的車（verify_mod.py 擋刪車與移車的呼叫）。
--   開服：包住 IsoWorld 方法表的 registerVehiclesZone，記下原版 doMapZones 登記的每個停車區與 Direction 屬性
--     （Lua 讀不到 VehicleZone.dir）→ OnLoadedMapZones 照 IsoChunk.AddVehicles_OnZone（IsoChunk.java:941-1118）的算法算出車位。
--   LoadChunk：舊區塊（不是 isNewChunk）有車位就把它的 64×64 格排進佇列；新區塊引擎剛生過車。
--   OnTick：專用伺服器等 SETTLE_MP 秒才檢查（LoadChunk 時舊區塊的存檔車還在背景讀資料庫，ServerMap.java:809,817-825、
--     VehiclesDB2.java:343-348,491-522；引擎沒有讀完的事件），每個 tick 最多處理一格：補到這一格原生的平均車數（R.target）。
--   每格機率照引擎公式（spawnRate 依沙盒 CarSpawnRate 換算再加 1%），車種用引擎的 VehicleType.getRandomVehicleType 抽（燒毀車、
--   特殊車照區域參數），車款依目前生效表的 spawnChance 加權，放車用 addVehicleDebug（唯一會把車寫進區塊與車輛資料庫的 Lua 入口），
--   同一個 tick 內把車況改回引擎生車的樣子（R.naturalize）。
if isClient() then return end
require "MinidoracatVehicleSpawnControl/MVSC_Server"
require "MinidoracatVehicleSpawnControl/MVSC_RespawnTrack"

local M = MinidoracatVehicleSpawnControl
local S, T = M.Server, M.RespawnTrack
local R = {}
M.Respawn = R

R.SETTLE_MP = 15      -- 秒
R.TTL = 300           -- 秒：佇列裡放太久（玩家一直在附近）就丟掉
R.MP_MIN = 88         -- 車心離每位線上玩家至少幾格（切比雪夫距離）：在客戶端最大載入範圍外
R.SP_MIN = 40         -- 單人：只補在剛進入視窗的外圈
R.REPORT_EVERY = 600  -- 秒
R.RECENT_MAX = 8
R.JUST_PLACED = 60    -- 秒：剛放的車要過幾幀才進到區塊的車輛清單，這段時間 isVehicleIntersecting 看不到（E2E respawn SP 實見）
local ORIG_KEY = "MinidoracatVehicleSpawnControl_registerVehiclesZone"

R.zones = {}          -- [i] = { name, x, y, w, h, dir, face }
R.byChunk = {}        -- [區塊鍵] = { 區號, x, y, 區號, x, y, ... }
R.chunksOfBlock = {}  -- [64×64 格鍵] = { 區塊鍵, ... }
R.queue = {}          -- [64×64 格鍵] = 進佇列的秒數
R.fresh = {}          -- [區塊鍵] = 這次才第一次生成的時間（引擎剛生過車，不補）
R.recent = {}
R.justPlaced = {}     -- [車位格鍵] = 放車的秒數：單人區塊陸續載入時，同一格接連補兩次也算得到剛放的車
R.placedTotal = 0

local function newWindow(now) return { start = now, placed = 0, blocks = 0, near = 0, blocked = 0, protected = 0, rejected = 0 } end
R.window = newWindow(0)

-- ---------------------------------------------------------------- 停車區索引
local seenRect = {}
local function indexZone(name, kind, x, y, z, w, h, props, zone)
    if z ~= 0 then return end -- AddVehicles_OnZone 只在 z=0 放車（IsoChunk.java:976）
    local n = (name ~= nil and name ~= "") and name or kind
    if n == nil or n == "TestVehicles" or string.find(string.lower(n), "trafficjam", 1, true) then return end
    local rect = x .. "," .. y .. "," .. w .. "," .. h
    if seenRect[rect] then return end -- checkVehiclesZones 刪掉位置大小相同的重複區（IsoMetaGrid.java:872-913）
    seenRect[rect] = true
    local dir = props and props.Direction
    if dir ~= "N" and dir ~= "S" and dir ~= "W" and dir ~= "E" then dir = nil end
    R.zones[#R.zones + 1] = { name = n, x = x, y = y, w = w, h = h, dir = dir, face = zone:isFaceDirection() == true }
end

-- 同 Vehicle Manager 包 permanentlyRemove 的做法（方法表在 __classmetatables[類別].__index）；
-- 原版 doMapZones（metazoneHandler.lua:120,143）在 OnLoadMapZones 才呼叫，晚於本檔載入。多邊線停車區由 Java 直接登記，不經過這裡
function R.installZoneIndex()
    local cls = IsoWorld and IsoWorld.class
    local mt = cls and __classmetatables and __classmetatables[cls]
    local methods = mt and mt.__index
    local orig = methods and (rawget(methods, ORIG_KEY) or methods.registerVehiclesZone)
    if orig == nil then return false end
    rawset(methods, ORIG_KEY, orig) -- Lua 重載時不疊包
    methods.registerVehiclesZone = function(world, name, kind, x, y, z, w, h, props)
        local zone = orig(world, name, kind, x, y, z, w, h, props)
        if zone then
            local ok, err = pcall(indexZone, name, kind, x, y, z, w, h, props, zone)
            if not ok then R.indexError = tostring(err) end
        end
        return zone
    end
    return true
end

-- 車位照 AddVehicles_OnZone：預設朝北；寬 4–6、高 ≤3 或 ≥6 的區朝西；有 Direction 屬性照它（:942-957）。
-- 南北向每 3 格一位、每排 5 格；東西向反過來。車位格＝區的原點加半個步距起算（:960-976）
local function stallsOf(z, add)
    local dir = z.dir
    if not dir then dir = (z.w >= 4 and z.w <= 6 and (z.h <= 3 or z.h >= 6)) and "W" or "N" end
    local sx, sy = 3, 5
    if dir == "W" or dir == "E" then sx, sy = 5, 3 end
    local y = z.y + sy / 2
    while y < z.y + z.h do
        local x = z.x + sx / 2
        while x < z.x + z.w do
            add(math.floor(x), math.floor(y))
            x = x + sx
        end
        y = y + sy
    end
    return dir
end

function R.buildIndex()
    R.byChunk, R.chunksOfBlock = {}, {}
    local stalls = 0
    for zi, z in ipairs(R.zones) do
        z.dir = stallsOf(z, function(tx, ty)
            local wx, wy = math.floor(tx / 8), math.floor(ty / 8)
            local ck = T.key(wx, wy)
            local list = R.byChunk[ck]
            if not list then
                list = {}
                R.byChunk[ck] = list
                local bk = T.key(math.floor(wx / 8), math.floor(wy / 8))
                local chunks = R.chunksOfBlock[bk] or {}
                chunks[#chunks + 1] = ck
                R.chunksOfBlock[bk] = chunks
            end
            list[#list + 1] = zi
            list[#list + 1] = tx
            list[#list + 1] = ty
            stalls = stalls + 1
        end)
    end
    R.stallCount = stalls
    R.indexOk = R.installed == true and stalls > 0
    if R.indexOk then
        print(M.LOG .. "respawn: indexed " .. #R.zones .. " parking zones (" .. stalls .. " stalls)")
    else
        print(M.LOG .. "respawn: zone index NOT installed (" .. tostring(R.indexError or (R.installed and "no zones registered"
            or "IsoWorld method table not found")) .. "), respawn stays off")
    end
end

-- ---------------------------------------------------------------- 機率與目標
-- 這個停車區的車位放車機率（引擎查表一律轉小寫，VehicleType.java:173）
function R.stallChance(name)
    local def = VehicleZoneDistribution[string.lower(name)]
    return M.stallChance(def and def.spawnRate, SandboxVars.CarSpawnRate)
end

-- 只看座標：同一格每次得到同一個 0–1 的數，所以目標固定、不會越補越多
function R.hash01(key)
    return ((key % 1000003) * 7919 + math.floor(key / 1000003) * 104729) % 1000003 / 1000003
end

function R.target(sum, density, key)
    return math.floor(sum * density / 100 + R.hash01(key))
end

-- ---------------------------------------------------------------- 引擎抽車
local typeNames, scriptKeys = nil, {}
-- getRandomVehicleType 回傳的 VehicleType 在 Lua 讀不到 name（Kahlua 不匯出 instance field）：和 getTypeFromName 比對物件找出區名
local function typeName(vt)
    if not typeNames then
        typeNames = {}
        for key in pairs(VehicleZoneDistribution) do
            if type(key) == "string" then
                local t = VehicleType.getTypeFromName(key)
                if t then typeNames[t] = key end
            end
        end
    end
    return typeNames[vt]
end

-- 照 IsoChunk.RandomizeModel（:1317-1358）：依生效表的 spawnChance 加權抽車款；index > -1 用指定塗裝，否則隨機
local function pickScript(name)
    local def = VehicleZoneDistribution[name]
    local list = def and def.vehicles
    if type(list) ~= "table" then return nil end
    local keys = scriptKeys[name]
    if not keys then
        keys = M.sortedKeys(list)
        scriptKeys[name] = keys
    end
    local total = 0
    for _, s in ipairs(keys) do total = total + (list[s] and list[s].spawnChance or 0) end
    if total <= 0 then return nil end
    local r = ZombRandFloat(0, total)
    local pick = keys[#keys]
    for _, s in ipairs(keys) do
        r = r - (list[s] and list[s].spawnChance or 0)
        if r < 0 then pick = s break end
    end
    return pick, list[pick] and list[pick].index
end

-- ---------------------------------------------------------------- 安全檢查
-- 車心照 AddVehicles_OnZone :1054-1098：車頭靠區的那一邊，車位格可能往前挪一格，最後夾在那一格內
local function engineCenter(z, tx, ty, len)
    local vx, vy = tx + 0.5, ty + 0.5
    if z.dir == "N" then
        vy = z.y + len / 2 + 0.5
        if vy >= ty + 1 then ty = ty + 1 end
    elseif z.dir == "S" then
        vy = z.y + z.h - len / 2 - 0.5
        if vy < ty then ty = ty - 1 end
    elseif z.dir == "W" then
        vx = z.x + len / 2 + 0.5
        if vx >= tx + 1 then tx = tx + 1 end
    else
        vx = z.x + z.w - len / 2 - 0.5
        if vx < tx then tx = tx - 1 end
    end
    return math.max(tx + 0.005, math.min(tx + 0.995, vx)), math.max(ty + 0.005, math.min(ty + 0.995, vy))
end

-- addVehicleDebug 把車心放在格子的西北角（LuaManager.java:10814-10815），角度多 ±0.2 弧度（:10806）：
-- 車身外框加上旋轉與 0.3 格餘量，回傳要檢查的格子範圍
local function footprint(cx, cy, dir, len, wid)
    local hx, hy = wid / 2, len / 2
    if dir == "W" or dir == "E" then hx, hy = len / 2, wid / 2
    elseif dir == nil then hx, hy = len / 2, len / 2 end
    local ex, ey = hx + 0.2 * hy + 0.3, hy + 0.2 * hx + 0.3
    return math.floor(cx - ex), math.floor(cy - ey), math.floor(cx + ex), math.floor(cy + ey)
end

-- isVehicleIntersecting 看得到已載入的車（IsoGridSquare.java:9895-9916）；有人、殭屍、動物、屍體、地上物品、玩家蓋的東西都不放
function R.squareFree(sq)
    if not sq or not sq:isSolidFloor() or sq:isSolid() or sq:isSolidTrans() or sq:HasTree() or sq:isWaterSquare() then return false end
    if sq:isVehicleIntersecting() or not sq:getMovingObjects():isEmpty() or sq:getDeadBody() ~= nil then return false end
    if not sq:getWorldObjects():isEmpty() then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        if instanceof(objs:get(i), "IsoThumpable") then return false end
    end
    return true
end

function R.farFromPlayers(x, y)
    local min = isServer() and R.MP_MIN or R.SP_MIN
    for _, p in ipairs(T.players()) do
        if math.max(math.abs(p:getX() - x), math.abs(p:getY() - y)) < min then return false end
    end
    return true
end

-- 原版 SafeHouse 的範圍是 [x, x2) × [y, y2)（SafeHouse.java:596-653）；安全屋 MOD 建的也是原版 SafeHouse
function R.nearSafehouse(x, y, margin)
    local list = SafeHouse.getSafehouseList()
    for i = 0, list:size() - 1 do
        local s = list:get(i)
        if x >= s:getX() - margin and x < s:getX2() + margin and y >= s:getY() - margin and y < s:getY2() + margin then return true end
    end
    return false
end

-- ---------------------------------------------------------------- 自然車況
local function luaFunction(path)
    local f = _G
    for part in string.gmatch(path, "[^%.]+") do
        if type(f) ~= "table" then return nil end
        f = f[part]
    end
    return type(f) == "function" and f or nil
end

-- 警報機率照 AddVehicles_OnZone :1009-1032（沙盒 CarAlarm）；燒毀與撞爛的車不裝
function R.alarmRoll(v)
    local chance = ({ -1, 3, 8, 15, 25, 50 })[SandboxVars.CarAlarm or 4] or 15
    local n = string.lower(v:getScriptName() or "")
    if string.find(n, "burnt", 1, true) or string.find(n, "smashed", 1, true) then return false end
    return ZombRand(100) < chance
end

-- addVehicleDebug 把車設成近新：零件 setGeneralPartCondition(1.3, 10)、鏽 0（LuaManager.java:10825-10826），也沒設 vehicleType。
-- 引擎生車時零件在 vehicleType 設好之後才建（VehicleParts.createParts → Lua Vehicles.Create.*），這裡照同樣的順序重做：
-- 每個零件 setRandomCondition（讀這一區的 baseVehicleQuality 與 chanceToPartDamage，VehiclePart.java:225-291），
-- 再跑零件的 create（電瓶電量、油量、車門上鎖、引擎品質；已有零件物品時不會重建物品，Vehicles.lua:1153-1194）。
-- 警報要先設：車門沒上鎖時 Create.Door 會把它關掉（Vehicles.lua:165-170）。鑰匙在放車當下已由引擎用預設 70% 決定（無法補）
function R.naturalize(v, zoneName, name, def)
    v:setZone(zoneName)
    v:setVehicleType(name)
    if def.specialCar == true then
        v:setDoColor(false)
        v:setColorHSV(0, 0.1, 0.9) -- 引擎生特殊車時不上色的值（BaseVehicle.java:733-735）
    end
    if R.alarmRoll(v) then v:setAlarmed(true) end
    for i = 0, v:getPartCount() - 1 do
        local part = v:getPartByIndex(i)
        part:setRandomCondition(part:getInventoryItem())
        local fname = part:getLuaFunction("create")
        local fn = fname and luaFunction(fname)
        if fn then pcall(fn, v, part) end
    end
    local q = tonumber(def.baseVehicleQuality) or 1.0
    v:setRust(ZombRand(100) < 100 - math.min(q * 120, 100) and 1 or 0)
end

-- ---------------------------------------------------------------- 放一台
-- 回傳 "placed" 或跳過的原因
function R.placeAt(c, cfg)
    local vt = VehicleType.getRandomVehicleType(c.z.name)
    local name = vt and typeName(vt)
    local def = name and VehicleZoneDistribution[name]
    local script, index
    if def then script, index = pickScript(name) end
    local vs = script and ScriptManager.instance:getVehicle(script)
    if not vs then return "rejected" end -- 清單空的區：引擎在這裡也不生車（RandomizeModel 回 false）
    local ext = vs:getExtents()
    local len, wid = ext:z(), ext:x()
    local dir = c.z.dir
    if def.randomAngle == true then dir = nil
    elseif not c.z.face then
        if dir == "N" or dir == "S" then dir = ZombRand(2) == 0 and "N" or "S"
        else dir = ZombRand(2) == 0 and "W" or "E" end
    end
    local vx, vy = engineCenter(c.z, c.tx, c.ty, len)
    local cx, cy = math.floor(vx + 0.5), math.floor(vy + 0.5)
    if not R.farFromPlayers(cx, cy) then return "near" end
    if R.nearSafehouse(cx, cy, cfg.safehouseMargin + math.ceil(len / 2)) then return "protected" end
    local x0, y0, x1, y1 = footprint(cx, cy, dir, len, wid)
    local cell = getCell()
    for x = x0, x1 do
        for y = y0, y1 do
            if not R.squareFree(cell:getGridSquare(x, y, 0)) then return "blocked" end
        end
    end
    local skin = tonumber(index)
    if not skin or skin < 0 then skin = ZombRand(math.max(1, vs:getSkinCount())) end
    local v = addVehicleDebug(script, dir and IsoDirections[dir] or nil, skin, cell:getGridSquare(cx, cy, 0))
    -- 放不下時照樣回傳車物件，但沒進世界、sqlId 是 -1（家族 pitfalls.md「addVehicleDebug 放不下車時照樣回傳車物件」）
    if not v or v:getSqlId() == -1 then return "rejected" end
    R.naturalize(v, c.z.name, name, def)
    return "placed"
end

-- ---------------------------------------------------------------- 一格 64×64
-- 引擎記在區上的資料（隨世界存檔）：hourLastSeen 在玩家看見格子時更新（Meta.java:17-38），
-- haveConstruction＝玩家在這區蓋過東西（Zone.java:245-269）。原版物資重生用同一組門檻（LootRespawn.java:112-115）。
-- 專用伺服器只在看見「房間裡的格子」時更新（ServerLOS → IsoGridSquare.CalcVisibility，room 為 nil 就跳過，javap 確認），
-- 戶外停車場要同一區有人看過室內才記得到；單人由 LightingJNI 記，戶外也算（LightingJNI.java:1510-1521）
local function zoneInfo(zone)
    local since = zone:getHoursSinceLastSeen()
    local seenAt = getGameTime():getWorldAgeHours() - since
    -- hourLastSeen 是 0（沒人看過）或 1（引擎生故事時把 0 加 1，IsoChunk.java:1861,3059）都不算有人來過
    return { visited = seenAt >= 2, built = zone:haveCons(),
        estimate = since * getGameTime():getMinutesPerDay() * 2.5 } -- 遊戲小時換成現實秒數（一天 minutesPerDay 分鐘）
end

function R.fillBlock(bk, now)
    local cfg = S.cfg and S.cfg.respawn
    local chunks = R.chunksOfBlock[bk]
    if not (R.on and cfg and chunks) then return end
    if SandboxVars.EnableVehicles == false or SandboxVars.CarSpawnRate == 1 then return end
    local need = cfg.unseenHours * 3600
    local cell = getCell()
    local zones, quiet, hasType = {}, {}, {}
    local sum, count, candidates, evaluated = 0, 0, {}, {}
    for _, ck in ipairs(chunks) do
        local flat = R.byChunk[ck]
        for i = 1, #flat, 3 do
            local z, tx, ty = R.zones[flat[i]], flat[i + 1], flat[i + 2]
            local sq = cell:getGridSquare(tx, ty, 0)
            local zone = sq and sq:getZone()
            local info = zone and zones[zone]
            if zone and not info then
                info = zoneInfo(zone)
                zones[zone] = info
            end
            if z and hasType[z.name] == nil then hasType[z.name] = VehicleType.hasTypeForZone(z.name) == true end
            if info then
                local q = quiet[ck]
                if not q then
                    local secs, fromEnable = T.quietBefore(bk, ck, now)
                    q = { secs = secs, fromEnable = fromEnable }
                    quiet[ck] = q
                end
                local secs = q.secs
                if q.fromEnable and secs < need then secs = math.max(secs, info.estimate) end -- 開啟後還沒滿門檻：用引擎的遊戲時間換算
                -- 時間到了的區塊一律記成補過，車位這次才第一次被看見也一樣：同一次來訪不會在玩家看過之後再補
                local due = secs >= need and not R.fresh[ck]
                if due then evaluated[ck] = true end
                -- 只算有人去過的車位：沒人去過的地方車不會少，補了只會比原本多。有人去過＝引擎記到有人看過這一區，
                -- 或足跡在這次來訪之前就有紀錄（開啟後有人來過這一格 88 格內；多人戶外靠這一條）
                if (info.visited or not q.fromEnable) and hasType[z.name] then
                    sum = sum + R.stallChance(z.name)
                    local jp = R.justPlaced[T.key(tx, ty)]
                    local occupied = (jp ~= nil and now - jp < R.JUST_PLACED) or sq:isVehicleIntersecting()
                    if occupied then count = count + 1 end
                    if due and not occupied then
                        if info.built then R.window.protected = R.window.protected + 1
                        else candidates[#candidates + 1] = { z = z, tx = tx, ty = ty } end
                    end
                end
            end
        end
    end
    local hasEvaluated = false
    for ck in pairs(evaluated) do
        hasEvaluated = true
        T.markRefilled(ck, now) -- 補過（或確認不用補）就重新計時
    end
    if not hasEvaluated then return end
    R.window.blocks = R.window.blocks + 1
    local target = R.target(sum, cfg.density, bk)
    local placed, first = 0, nil
    while count + placed < target and #candidates > 0 do
        local c = table.remove(candidates, ZombRand(#candidates) + 1)
        local result = R.placeAt(c, cfg)
        if result == "placed" then
            placed = placed + 1
            first = first or c
            R.justPlaced[T.key(c.tx, c.ty)] = now
        else
            R.window[result] = (R.window[result] or 0) + 1
        end
    end
    if placed > 0 then
        R.placedTotal = R.placedTotal + placed
        R.window.placed = R.window.placed + placed
        table.insert(R.recent, 1, { x = first.tx, y = first.ty, zone = first.z.name, n = placed, at = now })
        while #R.recent > R.RECENT_MAX do table.remove(R.recent) end
        print(M.LOG .. "respawn: +" .. placed .. " at " .. first.tx .. "," .. first.ty .. " " .. first.z.name
            .. " (block target " .. target .. ", had " .. count .. ")")
    end
end

-- ---------------------------------------------------------------- 事件
local function chunkOrigin(chunk)
    for x = 0, 7 do
        for y = 0, 7 do
            local sq = chunk:getGridSquare(x, y, 0)
            if sq then return sq:getX() - x, sq:getY() - y end -- IsoChunk 沒有 Lua 讀得到的 wx／wy
        end
    end
end

function R.onLoadChunk(chunk)
    if not R.on then return end
    local ox, oy = chunkOrigin(chunk)
    if not ox then return end
    local wx, wy = math.floor(ox / 8), math.floor(oy / 8)
    local ck = T.key(wx, wy)
    if not R.byChunk[ck] then return end
    local now = getTimestamp()
    if chunk:isNewChunk() then
        R.fresh[ck] = now -- 引擎剛照原版生過車
    else
        R.fresh[ck] = nil
    end
    local bk = T.key(math.floor(wx / 8), math.floor(wy / 8))
    R.queue[bk] = R.queue[bk] or now
end

local lastError, lastErrorAt = nil, 0
local function logError(err, now)
    err = tostring(err)
    if err ~= lastError or now - lastErrorAt >= 600 then -- 同一種錯每 10 分鐘只印一次
        print(M.LOG .. "respawn: error " .. err)
        lastError, lastErrorAt = err, now
    end
end

function R.drain(now)
    local settle = isServer() and R.SETTLE_MP or 0
    local expired, due = {}, nil
    for bk, at in pairs(R.queue) do
        if now - at > R.TTL then expired[#expired + 1] = bk
        elseif not due and now - at >= settle then due = bk end
    end
    for _, bk in ipairs(expired) do R.queue[bk] = nil end
    if not due then return end
    if not isServer() and #T.players() == 0 then return end -- 單人：玩家還沒進場就先等（距離檢查要有人）
    R.queue[due] = nil
    local ok, err = pcall(R.fillBlock, due, now)
    if not ok then logError(err, now) end
end

function R.report(now)
    local w = R.window
    if w.placed > 0 or w.near + w.blocked + w.protected + w.rejected > 0 then
        print(M.LOG .. "respawn: last 10 min +" .. w.placed .. " in " .. w.blocks .. " blocks, skipped: player near " .. w.near
            .. ", blocked " .. w.blocked .. ", safehouse or built " .. w.protected .. ", rejected " .. w.rejected)
    end
    R.lastWindow = w
    R.window = newWindow(now)
    local old = {}
    for k, at in pairs(R.justPlaced) do
        if now - at >= R.JUST_PLACED then old[#old + 1] = k end
    end
    for _, k in ipairs(old) do R.justPlaced[k] = nil end
    if S.status then
        S.status.respawn = R.summary(now)
        S.writeText(S.STATUS, M.jsonEncode(S.status, true) .. "\n")
    end
end

-- 面板與 status.json 用（只送統計與最近補在哪，不送玩家足跡）
function R.summary(now)
    now = now or getTimestamp()
    local cfg = S.cfg and S.cfg.respawn or M.RESPAWN_DEFAULTS
    local recent = {}
    for i, e in ipairs(R.recent) do recent[i] = { x = e.x, y = e.y, zone = e.zone, n = e.n, ago = now - e.at } end
    local w = R.lastWindow or R.window
    return { on = R.on == true, indexOk = R.indexOk == true, zones = #R.zones, stalls = R.stallCount or 0,
        placed = R.placedTotal, recent = recent,
        window = { placed = w.placed, near = w.near, blocked = w.blocked, protected = w.protected, rejected = w.rejected },
        trackedFor = T.enabledAt and (now - T.enabledAt) or 0, unseenHours = cfg.unseenHours }
end

function R.configure(cfg, now)
    R.cfgSeen = cfg
    typeNames, scriptKeys = nil, {} -- 套用會 VehicleType.Reset()，型別物件全部換新
    local rc = cfg and cfg.respawn or M.RESPAWN_DEFAULTS
    T.keepSeconds = rc.unseenHours * 3600
    local want = rc.enabled == true and R.indexOk == true
    if want ~= (R.on == true) then
        print(M.LOG .. "respawn: " .. (want and ("on, refill parking stalls left alone for " .. rc.unseenHours .. " real hours") or "off"))
    end
    R.on = want
    T.setEnabled(want, now)
    if not want then R.queue = {} end
end

local function onTick()
    if not S.base then return end
    local now = getTimestamp()
    if not T.dir then T.init() end
    if S.cfg ~= R.cfgSeen then R.configure(S.cfg, now) end
    if not R.on then return end
    if now ~= R.lastSecond then
        R.lastSecond = now
        T.tick(now)
        if now - (T.savedAt or 0) >= T.SAVE_EVERY then T.save(now) end
        if now - R.window.start >= R.REPORT_EVERY then R.report(now) end
    end
    if isServer() and not T.serverStarted then return end
    R.drain(now)
end

R.installed = R.installZoneIndex()
R.window = newWindow(getTimestamp())
Events.OnLoadedMapZones.Add(R.buildIndex)
Events.LoadChunk.Add(R.onLoadChunk)
Events.OnTick.Add(onTick)
Events.OnSave.Add(function() if R.on then T.save(getTimestamp()) end end)
