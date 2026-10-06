-- 3D 預覽換塗裝與補零件：把車種載入代理車種（media/scripts/MinidoracatVehicleSpawnControl_PreviewVehicles.txt）再交給遊戲內建的預覽畫。
-- 遊戲內建的預覽只畫第 0 款塗裝（UI3DScene.java:6115-6117）、每個零件只畫第一個模型（:7439），沒有切換的命令；
-- 代理車種只在本機記憶體改，退回主選單或進遊戲時腳本從檔案重讀（IngameState.java:980,1048、Core.java:3882,3931），
-- 代理回到燒毀車外殼。車種註冊後刪不掉、塗裝只能附加（VehicleScript.java:341-345），所以一個代理只給一個（車、塗裝）用，
-- 同一次進遊戲內重複看同一個組合沿用同一個代理；用完就退回貼圖（面板說明會註明）。
require "MinidoracatVehicleSpawnControl/MVSC_Core"

local M = MinidoracatVehicleSpawnControl
local P = {}
M.Preview = P

local PREFIX = "PreviewBurnt"

local slots      -- 代理車種名（依 MOD 腳本實際有幾個）
local nextSlot = 1
local built = {} -- ["車種#塗裝"] = 代理完整名稱
local splitCache = {}

local function proxyFull(name) return M.PREVIEW_MODULE .. "." .. name end

local function slotList()
    if not slots then
        slots = {}
        local sm = getScriptManager()
        for i = 1, 99 do
            local name = string.format("%s%02d", PREFIX, i)
            if not sm:getVehicle(proxyFull(name)) then break end
            slots[#slots + 1] = name
        end
    end
    return slots
end

local function v3(v) return string.format("%.6f %.6f %.6f", v:x(), v:y(), v:z()) end

-- 腳本原文（getLoadedScriptBodies：modId、原文交錯；BaseScriptObject.java:137-144），依載入順序
local function bodiesOf(script)
    local out = {}
    local b = script and script:getLoadedScriptBodies()
    if b then
        for i = 1, b:size() - 1, 2 do out[#out + 1] = b:get(i) end
    end
    return out
end

-- 依載入順序掃 skin 區塊與車種層級的 textureMask；`template! = X` 會把整個樣板載入在那個位置（VehicleScript.java:288-294）。
-- Skin 類別沒暴露給 Lua，遮罩只能從原文取；原版有 117 台車的遮罩寫在樣板裡
local function scanBody(body, acc, depth)
    local pos, NONE = 1, 1e30
    while true do
        local tS, tE, tName = string.find(body, "template!%s*=%s*([%w_%.]+)", pos)
        local sS, sE, sBody = string.find(body, "skin%s*{([^{}]*)}", pos)
        local mS, mE, mask = string.find(body, "textureMask%s*=%s*([^,%s}]+)", pos)
        local first = math.min(tS or NONE, sS or NONE, mS or NONE)
        if first == NONE then return end
        if first == sS then
            if string.find(sBody, "texture%s*=") then
                acc.skins[#acc.skins + 1] = string.match(sBody, "textureMask%s*=%s*([^,%s}]+)") or false
            end
            pos = sE + 1
        elseif first == tS then
            local t = depth < 4 and getScriptManager():getVehicleTemplate(tName)
            if t then
                for _, tb in ipairs(bodiesOf(t)) do scanBody(tb, acc, depth + 1) end
            end
            pos = tE + 1
        else
            acc.mask = mask
            pos = mE + 1
        end
    end
end

-- 第 k 款（0 起算）的遮罩：塗裝自己的優先，否則車種層級的（BaseVehicle.java:586-589 copyMissingFrom）
local function maskOf(src, k)
    local acc = { skins = {}, mask = nil }
    for _, body in ipairs(bodiesOf(src)) do scanBody(body, acc, 0) end
    local own = #acc.skins == src:getSkinCount() and acc.skins[k + 1] or nil
    return own or acc.mask
end

-- 要拆開的模型：零件有多個模型、而且不是「多選一」的款式（可裝物品只有一種）時，第 2 個以後的模型
-- 遊戲內建的預覽畫不出來（它把第一個模型畫好幾次）。KI5 保險桿、裝甲這類每個模型對應一種物品的不拆。
-- Lua 讀不到零件的 wheel／parent／itemType 欄位，用不加入世界的暫時車取（VehiclePart.java:131,474,678）
local function splitsOf(full)
    if splitCache[full] then return splitCache[full] end
    local out = {}
    local s = getScriptManager():getVehicle(full)
    local bv = BaseVehicle.new(getCell())
    bv:setScript(full)
    for i = 0, s:getPartCount() - 1 do
        local sp = s:getPart(i)
        if sp:getModelCount() > 1 then
            local vp = bv:getPartById(sp:getId())
            local items = vp and vp:getItemType()
            if not (items and items:size() > 1) then
                local wi = vp and vp:getWheelIndex() or -1
                local parent = vp and vp:getParent()
                for mk = 1, sp:getModelCount() - 1 do
                    local m = sp:getModel(mk)
                    if m:getFile() and m:getId() then
                        out[#out + 1] = { part = sp:getId(), index = mk, model = m,
                            wheel = wi >= 0 and s:getWheel(wi):getId() or nil, parent = parent and parent:getId() or nil }
                    end
                end
            end
        end
    end
    splitCache[full] = out
    return out
end

-- 原零件裡把要拆的模型縮成 0（引擎照樣會用第一個模型的網格畫在它的位置），另開一個只有這個模型的零件
local function splitText(splits)
    local t = {}
    for _, e in ipairs(splits) do
        local m = e.model
        t[#t + 1] = "part " .. e.part .. " { model " .. m:getId() .. " { scale = 0, } }"
        local s = "part " .. e.part .. "MVSC" .. e.index .. " {"
        if e.wheel then s = s .. " wheel = " .. e.wheel .. "," end
        if e.parent then s = s .. " parent = " .. e.parent .. "," end
        s = s .. " model " .. m:getId() .. " { file = " .. m:getFile() .. ", offset = " .. v3(m:getOffset())
            .. ", rotate = " .. v3(m:getRotate()) .. string.format(", scale = %.6f,", m:getScale())
        if m:getAttachmentNameParent() then s = s .. " attachmentParent = " .. m:getAttachmentNameParent() .. "," end
        if m:getAttachmentNameSelf() then s = s .. " attachmentSelf = " .. m:getAttachmentNameSelf() .. "," end
        t[#t + 1] = s .. " } }"
    end
    return t
end

local function build(slot, full, k, skinTex)
    local sm = getScriptManager()
    local src = sm:getVehicle(full)
    local px = sm:getVehicle(proxyFull(slot))
    local m = src:getModel()
    local mask = maskOf(src, k)
    px:Load(slot, string.format("vehicle %s { model { file = %s, scale = %.6f, offset = %s, rotate = %s, } skin { texture = %s,%s } }",
        slot, m:getFile(), m:getScale(), v3(m:getOffset()), v3(m:getRotate()), skinTex,
        mask and (" textureMask = " .. mask .. ",") or ""))
    -- 零件要原樣複製：預覽只對有 door／window 區塊的零件播「關上」的動畫（UI3DScene.java:6519-6526）
    px:copyPartsFrom(src, "*")
    px:copyWheelsFrom(src, "*")
    local patch = splitText(splitsOf(full))
    if #patch > 0 then px:Load(slot, "vehicle " .. slot .. " {\n" .. table.concat(patch, "\n") .. "\n}") end
    -- 物理與世界用的貼圖是開機時依外殼建的，跟著換掉；否則單人把用過的代理生到世界上，車輛 MOD 的輪胎處理會出錯（實測）
    px:toBullet()
    BaseVehicle.LoadVehicleTextures(px)
end

-- 預覽 full 的第 k 款（0 起算）。回傳 要給 setVehicleScript 的車種（nil＝改用貼圖）, 狀態：
--   "engine"：直接用原車種（第 0 款、沒有要拆的零件）；"proxy"：代理；"exhausted"：代理用完或建立失敗
function P.resolve(full, k, skinTex)
    local key = full .. "#" .. k
    if built[key] then return built[key], "proxy" end
    local okSplit, splits = pcall(splitsOf, full)
    if not okSplit then print(M.LOG .. "preview parts of " .. full .. " unreadable: " .. tostring(splits)) end
    if k == 0 and (not okSplit or #splits == 0) then return full, "engine" end
    -- 沒有塗裝的車種（少數 MOD）：第 0 款照原樣顯示
    if not skinTex then return k == 0 and full or nil, k == 0 and "engine" or "exhausted" end
    local list = slotList()
    while nextSlot <= #list do
        local slot = list[nextSlot]
        nextSlot = nextSlot + 1
        local px = getScriptManager():getVehicle(proxyFull(slot))
        -- 只用全新的外殼：Lua 單獨重載（腳本沒重讀）時，記錄清掉了但代理還是上次的內容
        if px and px:getSkinCount() == 0 and px:getPartCount() == 0 then
            local ok, err = pcall(build, slot, full, k, skinTex)
            if not ok then
                print(M.LOG .. "preview proxy for " .. key .. " failed: " .. tostring(err))
                return k == 0 and full or nil, "exhausted"
            end
            built[key] = proxyFull(slot)
            return built[key], "proxy"
        end
    end
    return k == 0 and full or nil, "exhausted"
end

-- 這次進遊戲還有幾個代理可用（E2E 與除錯用）
function P.remaining()
    local list, n = slotList(), 0
    for i = nextSlot, #list do
        local px = getScriptManager():getVehicle(proxyFull(list[i]))
        if px and px:getSkinCount() == 0 and px:getPartCount() == 0 then n = n + 1 end
    end
    return n
end

return P
