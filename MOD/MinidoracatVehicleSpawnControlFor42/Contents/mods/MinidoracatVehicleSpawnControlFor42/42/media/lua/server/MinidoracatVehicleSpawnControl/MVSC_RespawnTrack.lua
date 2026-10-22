-- MinidoracatVehicleSpawnControl 補車：玩家足跡（現實時間）。伺服器與單人跑；MP 客戶端在檔頭就返回。
--   每秒讀一次每位玩家的座標，把附近 NEAR 格內的 64×64 格（伺服器一次載入的 cell）記成現在的時間。時間取 getTimestamp()
--   （系統時鐘的秒數，LuaManager.java:9287-9289）：關服、PauseEmpty 暫停的時間照算，和日長設定無關。
--   每格三個時間：last＝最後一次有人、start＝這次來訪開始、prev＝這次來訪前最後一次有人；超過 GAP 秒沒人靠近就算來訪結束。
--   補車只問 quietBefore：「這次有人來之前，這一格空了多久」。單人的區塊要玩家走近才載入，那時這格已記成現在，所以不能只看 last。
--   紀錄只寫伺服器本機檔 Zomboid/Lua/MinidoracatVehicleSpawnControl/respawn/<世界名>/tracker-a|b.txt（兩份輪流寫，檔頭檔尾帶代數，
--   寫到一半當機就讀另一份）。不放全域 ModData：任何登入的玩家都能要走整張全域表（GlobalModDataRequestPacket.java:15,32、
--   GlobalModData.java:171-205），這份紀錄等於全服玩家的行蹤。全域 ModData 只放隨機的世界識別碼，用來認出同名的另一個世界
--   （Zomboid/Lua 是整台機器共用、也不跟存檔回溯，家族 pitfalls.md「Lua 不能刪檔、不能改名」）。
if isClient() then return end
require "MinidoracatVehicleSpawnControl/MVSC_Server"

local M = MinidoracatVehicleSpawnControl
local S = M.Server
local T = {}
M.RespawnTrack = T

T.CELL = 64          -- 伺服器一次載入 64×64 格
T.NEAR = 88          -- 客戶端載入範圍最大約 ±87 格（GameServer.java:2808 把範圍夾在 12–20 個區塊寬）
T.GAP = 600          -- 秒：超過這麼久沒人靠近，這次來訪就算結束
T.MOVE = 16          -- 玩家移動這麼多格才重記
T.REMARK = 60        -- 秒：站著不動也每這麼久重記一次
T.SAVE_EVERY = 300   -- 秒
T.MODDATA = "MinidoracatVehicleSpawnControl_Respawn"
local HEADER = "# MinidoracatVehicleSpawnControl respawn tracker v1"

T.cells, T.refilled, T.marked = {}, {}, {}
T.enabledAt = nil    -- 秒；nil＝沒在記（關閉中）
T.keepSeconds = 168 * 3600
T.gen = 0

-- 鍵：64×64 格與 8×8 區塊都用 x * 65536 + y（世界座標為正，乘積遠小於 2^53）
function T.key(x, y) return x * 65536 + y end

function T.players()
    local out = {}
    if isServer() then
        if not T.serverStarted then return out end -- 開服前 getOnlinePlayers 會 NPE（GameServer.java:3575）
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do out[#out + 1] = list:get(i) end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

local function touch(key, now)
    local c = T.cells[key]
    if not c then
        T.cells[key] = { last = now, start = now } -- 開啟後第一次有人來：沒有 prev
        return
    end
    if now - c.last > T.GAP then c.prev, c.start = c.last, now end -- 新的一次來訪
    c.last = now
end

function T.markAround(x, y, now)
    local C, R = T.CELL, T.NEAR
    for gx = math.floor((x - R) / C), math.floor((x + R) / C) do
        for gy = math.floor((y - R) / C), math.floor((y + R) / C) do
            touch(T.key(gx, gy), now)
        end
    end
end

-- 每秒一次：玩家移動 MOVE 格以上或滿 REMARK 秒才重記，每次最多 16 格
function T.tick(now)
    if not T.enabledAt then return end
    for _, p in ipairs(T.players()) do
        local id = isServer() and p:getUsername() or p:getPlayerNum()
        local x, y = p:getX(), p:getY()
        local m = T.marked[id]
        if not m or now - m.at >= T.REMARK or math.max(math.abs(x - m.x), math.abs(y - m.y)) >= T.MOVE then
            T.markAround(x, y, now)
            T.marked[id] = { x = x, y = y, at = now }
        end
    end
end

-- 這一格在「這次有人來」之前空了幾秒。fromEnable＝開啟後（或重新開啟後）還沒有紀錄，只能從開啟那刻算；
-- 補過的區塊從補的那刻重新計時，同一次來訪不會補第二次
function T.quietBefore(cellKey, chunkKey, now)
    local c = T.cells[cellKey]
    local here = c ~= nil and now - c.last <= T.GAP
    local visitStart = here and c.start or now
    local before = 0
    if c then before = here and (c.prev or 0) or c.last end
    before = math.max(before, T.refilled[chunkKey] or 0)
    local fromEnable = before < T.enabledAt
    if fromEnable then before = T.enabledAt end
    return visitStart - before, fromEnable
end

function T.markRefilled(chunkKey, now)
    T.refilled[chunkKey] = now
end

function T.count()
    local n = 0
    for _ in pairs(T.cells) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------- 開關
-- 關閉期間沒有紀錄：關閉就清空，再開啟時從頭記（enabledAt＝開啟的時間）
function T.setEnabled(on, now)
    if on and not T.enabledAt then
        T.enabledAt = now
        T.cells, T.refilled, T.marked = {}, {}, {}
        T.save(now)
    elseif not on and T.enabledAt then
        T.enabledAt = nil
        T.cells, T.refilled, T.marked = {}, {}, {}
        T.save(now)
    end
end

-- ---------------------------------------------------------------- 存檔
local function parse(text)
    if not text then return nil end
    local lines = {}
    for line in string.gmatch(text, "[^\n]+") do lines[#lines + 1] = line end
    if lines[1] ~= HEADER or #lines < 3 then return nil end
    local head = lines[2]
    local gen = tonumber(string.match(head, "gen=(%d+)"))
    if not gen or lines[#lines] ~= "end gen=" .. string.format("%.0f", gen) then return nil end -- 沒寫完
    local d = { gen = gen, world = string.match(head, "world=(%S+)"), enabledAt = tonumber(string.match(head, "enabledAt=(%d+)")) or 0,
        worldAge = tonumber(string.match(head, "worldAge=([%d%.]+)")) or 0, cells = {}, refilled = {}, cellCount = 0, refillCount = 0 }
    for i = 3, #lines - 1 do
        local line = lines[i]
        local cx, cy, last, start, prev = string.match(line, "^c (%d+) (%d+) (%d+) (%d+) (%d+)$")
        if cx then
            local c = { last = tonumber(last), start = tonumber(start) }
            if tonumber(prev) > 0 then c.prev = tonumber(prev) end
            d.cells[T.key(tonumber(cx), tonumber(cy))] = c
            d.cellCount = d.cellCount + 1
        else
            local wx, wy, at = string.match(line, "^r (%d+) (%d+) (%d+)$")
            if wx then
                d.refilled[T.key(tonumber(wx), tonumber(wy))] = tonumber(at)
                d.refillCount = d.refillCount + 1
            end
        end
    end
    return d
end

local function worldAge()
    return getGameTime():getWorldAgeHours()
end

function T.save(now)
    if not T.dir then return end
    T.gen = T.gen + 1
    T.savedAt = now
    local gen = string.format("%.0f", T.gen)
    local lines = { HEADER, "gen=" .. gen .. " world=" .. T.worldId .. string.format(" enabledAt=%.0f savedAt=%.0f worldAge=%.2f",
        T.enabledAt or 0, now, worldAge()) }
    local cellCut, refillCut = now - T.keepSeconds - 86400, now - T.keepSeconds
    local drop = {}
    for key, c in pairs(T.cells) do
        if c.last < cellCut then drop[#drop + 1] = key
        else
            lines[#lines + 1] = string.format("c %.0f %.0f %.0f %.0f %.0f", math.floor(key / 65536), key % 65536, c.last, c.start, c.prev or 0)
        end
    end
    for _, key in ipairs(drop) do T.cells[key] = nil end
    drop = {}
    for key, at in pairs(T.refilled) do
        if at < refillCut then drop[#drop + 1] = key
        else lines[#lines + 1] = string.format("r %.0f %.0f %.0f", math.floor(key / 65536), key % 65536, at) end
    end
    for _, key in ipairs(drop) do T.refilled[key] = nil end
    drop = {}
    for id, m in pairs(T.marked) do
        if now - m.at > 3600 then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do T.marked[id] = nil end
    lines[#lines + 1] = "end gen=" .. gen
    S.writeText(T.dir .. (T.gen % 2 == 0 and "tracker-a.txt" or "tracker-b.txt"), table.concat(lines, "\n") .. "\n")
end

-- 第一個 tick 才做（世界時間與全域 ModData 都已載入）：認世界、讀兩份紀錄中較新且完整的那份
function T.init()
    if T.dir then return end
    local world = tostring(getWorld():getWorld() or "world")
    T.dir = "MinidoracatVehicleSpawnControl/respawn/" .. string.gsub(world, "[^%w%-_]", "_") .. "/"
    local md = ModData.getOrCreate(T.MODDATA)
    if type(md.worldId) ~= "string" then md.worldId = string.format("%.0f-%d", getTimestampMs(), ZombRand(1000000)) end
    T.worldId = md.worldId
    local best, file
    for _, f in ipairs({ "tracker-a.txt", "tracker-b.txt" }) do
        local d = parse(S.readText(T.dir .. f))
        if d and (not best or d.gen > best.gen) then best, file = d, f end
    end
    if not best then return end
    T.gen = best.gen
    if best.world ~= T.worldId then
        print(M.LOG .. "respawn: tracker file " .. file .. " belongs to another world with the same name, starting fresh")
        return
    end
    if best.enabledAt == 0 then return end -- 存檔時是關閉的
    -- 世界在沒有記錄的情況下跑過（MOD 拿掉一陣子又裝回）：那段時間的足跡不知道，從頭記。
    -- 容許兩次存檔間隔換成遊戲時間再加 1 小時（正常重開服時最後一次存檔到關服之間也會走一點遊戲時間）
    local slack = T.SAVE_EVERY * 2 / 60 * 24 / getGameTime():getMinutesPerDay() + 1
    local gap = worldAge() - best.worldAge
    if gap > slack then
        print(M.LOG .. string.format("respawn: world ran %.1f game hours without tracking, starting fresh", gap))
        return
    end
    T.enabledAt, T.cells, T.refilled = best.enabledAt, best.cells, best.refilled
    print(M.LOG .. "respawn: tracker loaded " .. best.cellCount .. " cells, " .. best.refillCount .. " refilled chunks ("
        .. file .. ", gen " .. best.gen .. ")")
end

Events.OnServerStarted.Add(function() T.serverStarted = true end)
