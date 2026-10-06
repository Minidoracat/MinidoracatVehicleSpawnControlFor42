-- 「車輛」分頁（設計 C1）：左＝來源（含整包倍率）與車款（可多選），中＝3D 預覽或批次摘要，右＝此車各區域權重或批次操作。
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "Vehicles/ISUI/ISUI3DScene"
require "MinidoracatVehicleSpawnControl/MVSC_Widgets"
require "MinidoracatVehicleSpawnControl/MVSC_Preview"

local M = MinidoracatVehicleSpawnControl
local C, U, W = M.Client, M.UI, M.W
local T = U.T

MVSC_VehicleTab = ISPanel:derive("MVSC_VehicleTab")
local Tab = MVSC_VehicleTab
local PAD = W.PAD
local IN = 12 -- 卡片內距
local ALL = "*"
local MULTS = { 0, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 5 } -- 倍率步進器的預設刻度

-- ---------------------------------------------------------------- 資料
local function sourcesOf(catalog)
    local counts, news, names = {}, {}, {}
    for _, v in pairs(catalog) do
        counts[v.source] = (counts[v.source] or 0) + 1
        if v.new then news[v.source] = (news[v.source] or 0) + 1 end
        names[v.source] = v.sourceName
    end
    local mods = {}
    for src in pairs(counts) do
        if src ~= M.VANILLA then mods[#mods + 1] = src end
    end
    M.sortSafe(mods, function(a, b) return string.lower(names[a] or a) < string.lower(names[b] or b) end)
    return counts, news, names, mods
end

-- 車款分組：同顯示名的變體收成一組（原版有 34 個 script 同名，設計文件限制 6）
function Tab:buildGroups()
    local q = string.lower(self.query or "")
    local groups, order = {}, {}
    for full, v in pairs(C.data.catalog) do
        local okSrc = self.source == ALL or v.source == self.source
        local okQ = q == "" or string.find(string.lower(v.display), q, 1, true) or string.find(string.lower(full), q, 1, true)
        if okSrc and okQ then
            local g = groups[v.display]
            if not g then g = { name = v.display, members = {} }; groups[v.display] = g; order[#order + 1] = v.display end
            g.members[#g.members + 1] = full
        end
    end
    M.sortSafe(order, function(a, b) return string.lower(a) < string.lower(b) end)
    local out = {}
    for _, name in ipairs(order) do
        M.sortSafe(groups[name].members)
        out[#out + 1] = groups[name]
    end
    return out
end

-- 塗裝色票：每款的原始貼圖縮圖，點一下切換 3D 預覽的塗裝（MVSC_Preview）。
-- 名稱只能由 BaseVehicle:getSkin() 取得：建一台不加入世界的車逐款讀（Skin 類別沒暴露給 Lua）
local skinCache = {}
local function skinsOf(full)
    if skinCache[full] == nil then
        local names = {}
        local ok = pcall(function()
            local bv = BaseVehicle.new(getCell())
            bv:setScript(full)
            for i = 0, bv:getSkinCount() - 1 do
                bv:setSkinIndex(i)
                names[#names + 1] = bv:getSkin()
            end
        end)
        skinCache[full] = ok and names or {}
    end
    return skinCache[full]
end

-- 有些 MOD 會替車種加上綁了輪子、卻沒有模型的零件（例：Immersive Snow 0.5.2 的 ISnowWheel*）。引擎預覽的 initWheelModel
-- 直接讀這種零件的模型清單（null）→ 每幀 NPE，被 UIManager 接住後該幀其餘 UI 全部不畫（UI3DScene.java:7375）。
-- Lua 讀不到零件的 wheel 欄位，改用不加入世界的暫時車以 getWheelIndex 判斷；回傳第一個這種零件的 id。不快取：那類 MOD 之後可能補上模型
local function brokenWheelPart(full)
    local found
    local ok, err = pcall(function()
        local bv = BaseVehicle.new(getCell())
        bv:setScript(full)
        for i = 0, bv:getPartCount() - 1 do
            local part = bv:getPartByIndex(i)
            local sp = part:getScriptPart()
            if part:getWheelIndex() >= 0 and sp and sp:getModelCount() == 0 then
                found = part:getId()
                return
            end
        end
    end)
    if not ok then print(M.LOG .. "preview check failed for " .. tostring(full) .. ": " .. tostring(err)) end
    return found
end

-- 倍率在預設刻度間跳；手動輸入的非刻度值往相鄰刻度靠
local function stepMult(v, dir)
    v = v or 1
    if dir > 0 then
        for _, m in ipairs(MULTS) do
            if m > v + 1e-9 then return m end
        end
        return v
    end
    for i = #MULTS, 1, -1 do
        if MULTS[i] < v - 1e-9 then return MULTS[i] end
    end
    return 0
end

local function fmtMult(v)
    if v == nil then return T("MultMixed") end
    if v == 0 then return T("MultOff") end
    return "x" .. U.num(v) -- 遊戲字型沒有「×」
end

-- 權重：1 以上每次 ±1，不到 1 時 ±0.1（原版有 0.15 這類小權重）；大數字點數值直接輸入
local function stepWeight(v, dir)
    v = v or 0
    local step = (v < 1 or (dir < 0 and v <= 1)) and 0.1 or 1
    return math.max(0, math.floor((v + dir * step) * 100 + 0.5) / 100)
end

-- ---------------------------------------------------------------- 建立
function Tab:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.source = ALL
    o.query = ""
    o.expanded = {}
    o.zoneRows = {}
    o.sel = W.selection()
    o.viewX, o.viewY = 0, 0
    o.skin = 0 -- 預覽中的塗裝（0 起算）
    return o
end

function Tab:createChildren()
    local FH, FM = U.fontH(), U.fontH(UIFont.Medium)
    local ch = W.ctrlH()
    local h = self.height
    local lw = math.floor(self.width * 0.27)
    local mw = math.floor(self.width * 0.39)
    local mx = lw + PAD
    local rx = mx + mw + PAD
    local rw = self.width - rx
    self.cols = { { 0, lw }, { mx, mw }, { rx, rw } }
    local head = FH + IN * 2 -- 卡片標題列
    local sw = ch * 2 + 96 -- 步進器寬
    self.stepW = sw

    -- 左：來源（高度依來源數，最多 6 列）＋整包倍率＋車款
    self.search = W.search(self, IN, head, lw - IN * 2, ch, T("SearchVehicle"))
    self.srcTop = head + ch + PAD
    self.srcRowH = FH + 12
    self.sourceList = W.list(self, IN - 4, self.srcTop, lw - IN * 2 + 8, self.srcRowH * 4, self.srcRowH, Tab.drawSourceRow, self, Tab.onSource)
    self.sourceList.tab = self
    self.srcMult = W.stepper(self, lw - IN - sw, 0, sw, ch, {
        get = function() return C.multOf("sources", self.source) end,
        set = function(v) C.setMultiplier("sources", self.source, v) end,
        step = stepMult, format = fmtMult, title = T("SourceMult"), prompt = T("MultPrompt") })
    self.vehicleList = W.list(self, IN - 4, 0, lw - IN * 2 + 8, 100, FH * 2 + 12, Tab.drawVehicleRow)
    self.vehicleList.tab = self
    self.vehicleList.onMouseDown = Tab.onVehicleMouseDown
    self:layoutLeft(4)

    -- 中：3D 預覽（全程只有一個場景，AGENTS 鐵則）
    local sceneTop = head
    local sceneH = math.floor(h * 0.58) - sceneTop
    self.scene = ISUI3DScene:new(mx + IN, sceneTop, mw - IN * 2, sceneH)
    self.scene:initialise()
    self.scene:instantiate()
    self.scene.background = true
    self.scene.backgroundColor = { r = 0.045, g = 0.045, b = 0.05, a = 1 }
    self.scene.borderColor = { r = 1, g = 1, b = 1, a = 0.06 }
    self:addChild(self.scene)
    local j = self.scene.javaObject
    -- 左鍵旋轉、右鍵（或 Shift＋左鍵）平移、滾輪以畫面中心縮放、雙擊重設。
    -- 平移量自己記：UI3DScene 沒有讀寫 viewX／viewY 的命令，原版朝游標縮放會改掉它，重設就歸不了零
    self.scene:setView("UserDefined")
    self.scene.onMouseDown = Tab.sceneDown
    self.scene.onMouseUp = Tab.sceneUp
    self.scene.onMouseUpOutside = Tab.sceneUp
    self.scene.onRightMouseDown = Tab.sceneRightDown
    self.scene.onRightMouseUp = Tab.sceneRightUp
    self.scene.onRightMouseUpOutside = Tab.sceneRightUp
    self.scene.onMouseMove = Tab.sceneMove
    self.scene.onMouseMoveOutside = Tab.sceneMove
    self.scene.onMouseWheel = Tab.sceneWheel
    self.scene.onMouseDoubleClick = Tab.sceneDouble
    j:fromLua1("setMaxZoom", 20)
    self:setAngle(Tab.ANGLES.iso)
    j:fromLua1("setDrawGrid", false)
    j:fromLua1("createVehicle", "v")
    j:fromLua2("setObjectVisible", "v", false)
    local views = { { "ViewFront", "front" }, { "ViewSide", "side" }, { "ViewTop", "top" }, { "ViewReset", "iso" } }
    local bw = math.floor((mw - IN * 2 - PAD * 3) / 4)
    local by = self.scene:getBottom() + PAD
    self.viewBtns = {}
    for i, v in ipairs(views) do
        local b = W.button(self, mx + IN + (i - 1) * (bw + PAD), by, bw, ch, T(v[1]), self, Tab.onView, "secondary",
            v[2] == "iso" and "reload" or nil)
        b.view = v[2]
        self.viewBtns[i] = b
    end
    self.infoY = by + ch + IN
    self.clearBtn = W.button(self, mx + IN, h - IN - ch, math.min(mw - IN * 2, 200), ch, T("ClearSelection"), self, Tab.onClearSel, "secondary")

    -- 右（單台）：此車倍率＋各區域權重列＋加入區域／停用
    self.vehMult = W.stepper(self, rx + rw - IN - sw, head, sw, ch, {
        get = function() return self.selectedFull and C.multOf("vehicles", self.selectedFull) or 1 end,
        set = function(v) if self.selectedFull then C.setMultiplier("vehicles", self.selectedFull, v) end end,
        step = stepMult, format = fmtMult, title = T("VehicleMult"), prompt = T("MultPrompt") })
    local boxTop = head + ch + PAD
    local bottomH = ch * 2 + PAD * 2 + IN
    self.zoneBox = ISPanel:new(rx + IN, boxTop, rw - IN * 2, h - boxTop - bottomH)
    self.zoneBox:initialise()
    self.zoneBox:instantiate()
    self.zoneBox.background = false
    self.zoneBox:addScrollBars()
    self.zoneBox:setScrollChildren(true)
    self.zoneBox.onMouseWheel = function(box, del)
        box:setYScroll(box:getYScroll() - del * 40)
        return true
    end
    self.zoneBox.prerender = function(box) box:setStencilRect(0, 0, box.width, box.height) end
    self.zoneBox.render = function(box) box:clearStencilRect() end
    self:addChild(self.zoneBox)
    local ay = self.zoneBox:getBottom() + PAD
    self.addBtn = W.button(self, rx + IN, ay, rw - IN * 2, ch, T("AddZone"), self, Tab.onAddZone, "secondary", "layers")
    self.toggleBtn = W.button(self, rx + IN, ay + ch + PAD, rw - IN * 2, ch, T("DisableEverywhere"), self, Tab.onToggle, "danger")

    -- 右（多台）：所有區域倍率、加入／移出區域、啟用／停用
    self.batchY = head
    self.batchMult = W.stepper(self, rx + rw - IN - sw, self.batchY, sw, ch, {
        get = function() return self:commonMult() end,
        set = function(v)
            local keys = self.sel:keys()
            C.batch(function()
                for _, k in ipairs(keys) do C.setMultiplier("vehicles", k, v) end
            end)
        end,
        step = stepMult, format = fmtMult, title = T("BatchMult"), prompt = T("MultPrompt") })
    local y = self.batchY + ch + PAD * 2
    self.batchBtns = {}
    local specs = { { "BatchAddZone", Tab.onBatchAdd, "secondary", "layers" }, { "BatchRemoveZone", Tab.onBatchRemove, "secondary" },
        { "BatchEnable", Tab.onBatchEnable, "secondary" }, { "BatchDisable", Tab.onBatchDisable, "danger" } }
    for i, s in ipairs(specs) do
        self.batchBtns[i] = W.button(self, rx + IN, y, rw - IN * 2, ch, T(s[1], "0"), self, s[2], s[3], s[4])
        y = y + ch + PAD
    end
    self:updateMode()
    self:refresh()
end

-- 來源清單依內容決定高度，剩下的空間給車款清單
function Tab:layoutLeft(nSources)
    local FH, ch = U.fontH(), W.ctrlH()
    local srcH = math.min(math.max(nSources, 1), 6) * self.srcRowH
    W.placeList(self.sourceList, self.srcTop, srcH)
    self.multY = self.srcTop + srcH + PAD
    self.srcMult:setY(self.multY)
    self.vehTop = self.multY + ch + PAD
    W.placeList(self.vehicleList, self.vehTop + FH + 8, self.height - self.vehTop - FH - 8 - IN)
end

-- ---------------------------------------------------------------- 重建
function Tab:refresh()
    if not C.data then return end
    local counts, news, names, mods = sourcesOf(C.data.catalog)
    local total = 0
    for _, n in pairs(counts) do total = total + n end
    local list = self.sourceList
    list:clear()
    list:addItem(T("SourceAll"), { key = ALL, count = total })
    list:addItem(T("Source_pz-vanilla"), { key = M.VANILLA, count = counts[M.VANILLA] or 0, new = news[M.VANILLA] },
        T("Source_pz-vanilla"))
    for _, src in ipairs(mods) do
        list:addItem(names[src] or src, { key = src, count = counts[src], new = news[src] }, (names[src] or src) .. " <LINE> " .. src)
    end
    self:layoutLeft(#list.items)
    self:rebuildVehicles()
    -- 重新載入（例如套用後）保留選取，只拿掉已不存在的車
    for k in pairs(self.sel.set) do
        if not C.data.catalog[k] then self.sel.set[k] = nil end
    end
    self:afterSelect()
end

function Tab:rebuildVehicles()
    local list = self.vehicleList
    local keepY = list:getYScroll()
    list:clear()
    local groups = self:buildGroups()
    -- 目前篩選下的所有車款（含收合群組內的變體），給「全選」用
    self.filtered = {}
    for _, g in ipairs(groups) do
        for _, full in ipairs(g.members) do self.filtered[#self.filtered + 1] = full end
    end
    for _, g in ipairs(groups) do
        if #g.members == 1 then
            list:addItem(g.name, { kind = "vehicle", full = g.members[1] }, self:vehicleTip(g.members[1]))
        else
            list:addItem(g.name, { kind = "group", name = g.name, members = g.members }, g.name)
            if self.expanded[g.name] or (self.query or "") ~= "" then
                for _, full in ipairs(g.members) do list:addItem(full, { kind = "vehicle", full = full, child = true }, self:vehicleTip(full)) end
            end
        end
    end
    list:setYScroll(keepY)
end

function Tab:vehicleTip(full)
    local v = C.data.catalog[full]
    return table.concat({ v.display, full, T("InfoSource", U.packName(v.source)) }, " <LINE> ")
end

-- 目前清單看得到的車款列（Shift 範圍選取用這個順序）
function Tab:visibleKeys()
    local keys = {}
    for _, it in ipairs(self.vehicleList.items) do
        if it.item.kind == "vehicle" then keys[#keys + 1] = it.item.full end
    end
    return keys
end

-- 外部指定一台車（區域分頁的「開啟」、E2E）：只選這台並預覽
function Tab:select(full)
    if not (C.data and C.data.catalog[full]) then return end
    self.sel:only(full)
    self.expanded[C.data.catalog[full].display] = true
    self:focus(full)
    self:updateMode()
    self:rebuildVehicles()
    self:rebuildZones()
end

function Tab:focus(full)
    self.selectedFull = full
    self.skin = 0
    self.blockedPart = brokenWheelPart(full)
    if self.blockedPart then
        print(M.LOG .. "preview skipped for " .. full .. ": part " .. self.blockedPart .. " has a wheel but no model")
    end
    self:showPreview()
end

-- 把選中的車與塗裝送進 3D 場景：要換塗裝或補零件時交給代理車種，代理用完時第 1 款以後改畫貼圖（render）
function Tab:showPreview()
    local j = self.scene.javaObject
    local name, state
    if self.blockedPart then
        state = "blocked"
    else
        name, state = M.Preview.resolve(self.selectedFull, self.skin, skinsOf(self.selectedFull)[self.skin + 1])
    end
    self.previewState = state
    self.shownScript = name
    if name then j:fromLua2("setVehicleScript", "v", name) end
    j:fromLua2("setObjectVisible", "v", name ~= nil)
    -- 初始化當下模型若還沒載入，場景會一直空白直到再次 setVehicleScript（UI3DScene.java:6101-6105）
    self.resetAt = name and 30 or nil
    self:updateMode()
end

-- 代理用完時，第 1 款以後的塗裝改以原始貼圖顯示在預覽區
function Tab:showsTexture()
    return self.mode == "single" and self.previewState == "exhausted" and self.shownScript == nil
end

function Tab:afterSelect()
    local n = self.sel:count()
    if n == 1 then
        local k = self.sel:keys()[1]
        if k ~= self.selectedFull then self:focus(k) end
    elseif n == 0 then
        self.selectedFull = nil
    end
    self:updateMode()
    self:rebuildZones()
end

-- 三種模式：沒選（empty）、一台（single）、多台（batch）
function Tab:updateMode()
    local n = self.sel:count()
    local mode = n == 0 and "empty" or (n == 1 and "single" or "batch")
    self.mode = mode
    local single, batch = mode == "single", mode == "batch"
    -- 場景是子元件、會蓋住本分頁的繪製：改畫貼圖時先收起來
    self.scene:setVisible(single and not self:showsTexture())
    for _, b in ipairs(self.viewBtns) do
        b:setVisible(not batch)
        b:setUsable(single)
    end
    self.clearBtn:setVisible(batch)
    self.vehMult:setVisible(single)
    self.zoneBox:setVisible(single)
    self.addBtn:setVisible(single)
    self.toggleBtn:setVisible(single)
    self.batchMult:setVisible(batch)
    for _, b in ipairs(self.batchBtns) do b:setVisible(batch) end
    if batch then self.batchBtns[4]:setTitle(T("BatchDisable", tostring(n))) end
end

-- 這台車出現的區域：原始分布有它，或草稿把它加進去
function Tab:zonesOf(full)
    local out = {}
    for name, z in pairs(C.data.base.zones) do
        local dz = C.draft.zones[name]
        if z.vehicles[full] or (dz and dz.weights and dz.weights[full] ~= nil) then out[#out + 1] = name end
    end
    return M.sortSafe(out, function(a, b) return string.lower(U.zoneLabel(a)) < string.lower(U.zoneLabel(b)) end)
end

function Tab:rebuildZones()
    for _, row in ipairs(self.zoneRows) do self.zoneBox:removeChild(row) end
    self.zoneRows = {}
    local full = self.selectedFull
    if self.mode ~= "single" or not (full and C.data) then return end
    local rh = U.fontH() + W.ctrlH() + 22
    local y = 0
    for _, zone in ipairs(self:zonesOf(full)) do
        local row = MVSC_ZoneWeightRow:new(0, y, self.zoneBox.width - 12, rh, self, zone)
        row:initialise()
        row:instantiate()
        self.zoneBox:addChild(row)
        self.zoneRows[#self.zoneRows + 1] = row
        y = y + rh + 6
    end
    self.zoneBox:setScrollHeight(y)
    local enabled = C.isEnabled(full)
    self.toggleBtn:setTitle(enabled and T("DisableEverywhere") or T("EnableEverywhere"))
    self.toggleBtn.style = enabled and "danger" or "secondary"
end

-- 區域列的步進器每幀讀草稿，不需要逐列同步
function Tab:onDraft() end

function Tab:commonMult()
    local v
    for _, k in ipairs(self.sel:keys()) do
        local m = C.multOf("vehicles", k)
        if v == nil then v = m elseif v ~= m then return nil end
    end
    return v
end

-- ---------------------------------------------------------------- 事件
function Tab:onSource(item)
    self.source = item.key
    self:rebuildVehicles()
end

-- 群組列：勾選框＝全選／取消這組變體，其餘位置展開／收合；車款列：清單慣例（點選、Ctrl、Shift、勾選框）
function Tab.onVehicleMouseDown(list, x, y)
    local row = list:rowAt(x, y)
    if row < 1 or not list.items[row] then return true end
    local tab, d = list.tab, list.items[row].item
    if d.kind == "group" then
        if x >= 30 and x < 52 then
            tab:toggleMany(d.members)
        else
            tab.expanded[d.name] = not tab.expanded[d.name]
            tab:rebuildVehicles()
        end
        return true
    end
    local keys = tab:visibleKeys()
    local at
    for i, k in ipairs(keys) do
        if k == d.full then at = i end
    end
    local cx = d.child and 30 or 8
    tab.sel:click(keys, at, x >= cx - 4 and x < cx + 22)
    tab:afterSelect()
    return true
end

function Tab:toggleMany(keys)
    local all = self.sel:state(keys) == true
    for _, k in ipairs(keys) do self.sel.set[k] = (not all) or nil end
    self:afterSelect()
end

-- 車款標題列的勾選框：全選／取消目前篩選下的所有車款；塗裝色票：切換預覽的塗裝
function Tab:onMouseDown(x, y)
    if x >= IN - 4 and x <= IN + 24 and y >= self.vehTop - 2 and y <= self.vehTop + U.fontH() + 4 then
        self.sel:toggleAll(self.filtered or {})
        self:afterSelect()
        return true
    end
    if self.mode == "single" and self.swatches then
        for i, r in ipairs(self.swatches) do
            if x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[3] then
                if self.skin ~= i - 1 then
                    self.skin = i - 1
                    self:showPreview()
                end
                return true
            end
        end
    end
    return true
end

function Tab:onClearSel()
    self.sel:clear()
    self:afterSelect()
end

-- 與原版預設視角同角度（UI3DScene.java:2604-2627）；iso＝開啟時的斜俯視
Tab.ANGLES = { front = { 0, 0, 0 }, side = { 0, 270, 0 }, top = { 0, 90, 90 }, iso = { 25, 135, 0 } }
local ZOOM = 5

function Tab:setAngle(a)
    self.rot = { a[1], a[2], a[3] }
    self.zoom = ZOOM
    local j = self.scene.javaObject
    j:fromLua3("setViewRotation", a[1], a[2], a[3])
    j:fromLua1("setZoom", ZOOM)
    self:pan(self.viewX, self.viewY) -- 平移歸零
end

-- dragView(dx, dy)：viewX -= dx、viewY -= dy（UI3DScene.java:1052-1058）；引擎取整數，這裡同步記
function Tab:pan(dx, dy)
    dx, dy = math.floor(dx + 0.5), math.floor(dy + 0.5)
    if dx == 0 and dy == 0 then return end
    self.scene.javaObject:fromLua2("dragView", dx, dy)
    self.viewX, self.viewY = self.viewX - dx, self.viewY - dy
end

function Tab:onView(button)
    self:setAngle(Tab.ANGLES[button.view])
end

-- 以下掛在 scene 上，self 是 scene、parent 是本分頁
function Tab.sceneDown(scene)
    scene.mouseDown = true
    scene.panning = isShiftKeyDown()
    return true
end

function Tab.sceneUp(scene)
    scene.mouseDown, scene.panning = false, false
    return true
end

function Tab.sceneRightDown(scene)
    scene.rightDown = true
    return true
end

function Tab.sceneRightUp(scene)
    scene.rightDown = false
    return true
end

function Tab.sceneMove(scene, dx, dy)
    local tab = scene.parent
    if scene.rightDown or (scene.mouseDown and scene.panning) then
        tab:pan(dx, dy)
        return
    end
    if not scene.mouseDown then return end
    local r = tab.rot
    r[2] = (r[2] + dx / 2) % 360
    r[1] = math.max(-89, math.min(89, r[1] + dy / 2))
    scene.javaObject:fromLua3("setViewRotation", r[1], r[2], r[3])
end

-- 以畫面中心縮放並保留平移：平移量是「縮放後像素」，要依 zoomMult 比例換算（UI3DScene.java:378-380,2597）
function Tab.sceneWheel(scene, del)
    local tab = scene.parent
    local z = math.max(1, math.min(20, tab.zoom - del))
    if z == tab.zoom then return true end
    local r = math.exp((z - tab.zoom) * 0.2)
    scene.javaObject:fromLua1("setZoom", z)
    tab:pan(tab.viewX - tab.viewX * r, tab.viewY - tab.viewY * r)
    tab.zoom = z
    return true
end

function Tab.sceneDouble(scene)
    scene.parent:setAngle(Tab.ANGLES.iso)
    return true
end

function Tab:targets()
    return { self.selectedFull }
end

local function zonePickerGroups(names)
    local groups = {}
    for _, g in ipairs(U.groupZones(names)) do
        local items = {}
        for _, z in ipairs(g.zones) do items[#items + 1] = { U.zoneLabel(z), z } end
        groups[#groups + 1] = { title = T("Group_" .. g.group), items = items }
    end
    return groups
end

function Tab:onAddZone(button)
    local present = {}
    for _, z in ipairs(self:zonesOf(self.selectedFull)) do present[z] = true end
    local names = {}
    for z in pairs(C.data.base.zones) do
        if not present[z] then names[z] = true end
    end
    W.picker(button:getAbsoluteX(), button:getAbsoluteY() + button.height + 4, zonePickerGroups(names), self, Tab.addToZone)
end

function Tab:addToZone(zone)
    for _, full in ipairs(self:targets()) do C.setWeight(zone, full, 10) end
    self:rebuildZones()
end

function Tab:onToggle()
    local full = self.selectedFull
    if C.isEnabled(full) then
        local v = C.data.catalog[full]
        W.dialog({ title = T("DisableEverywhere"), message = T("ConfirmDisable", v.display), confirm = T("DisableEverywhere"),
            danger = true, onConfirm = function()
                C.setEnabled(full, false)
                self:rebuildZones()
            end })
    else
        C.setEnabled(full, true)
        self:rebuildZones()
    end
end

-- 批次：加入區域只補「還不在那區」的車（權重 10），不動已有的權重
function Tab:onBatchAdd(button)
    local names = {}
    for z in pairs(C.data.base.zones) do names[z] = true end
    W.picker(button:getAbsoluteX(), button:getAbsoluteY() + button.height + 4, zonePickerGroups(names), self, Tab.batchAddTo)
end

function Tab:batchAddTo(zone)
    local keys = self.sel:keys()
    C.batch(function()
        for _, k in ipairs(keys) do
            if C.weightOf(zone, k) == 0 then C.setWeight(zone, k, 10) end
        end
    end)
end

function Tab:onBatchRemove(button)
    local names, any = {}, false
    for _, k in ipairs(self.sel:keys()) do
        for _, z in ipairs(self:zonesOf(k)) do
            if C.weightOf(z, k) > 0 then names[z], any = true, true end
        end
    end
    if not any then return end
    W.picker(button:getAbsoluteX(), button:getAbsoluteY() + button.height + 4, zonePickerGroups(names), self, Tab.batchRemoveFrom)
end

function Tab:batchRemoveFrom(zone)
    local keys = self.sel:keys()
    C.batch(function()
        for _, k in ipairs(keys) do C.setWeight(zone, k, 0) end
    end)
end

function Tab:onBatchEnable()
    local keys = self.sel:keys()
    C.batch(function()
        for _, k in ipairs(keys) do C.setEnabled(k, true) end
    end)
end

function Tab:onBatchDisable()
    local keys = self.sel:keys()
    W.dialog({ title = T("BatchDisable", tostring(#keys)), message = T("ConfirmBatchDisable", tostring(#keys)),
        confirm = T("BatchDisable", tostring(#keys)), danger = true, onConfirm = function()
            C.batch(function()
                for _, k in ipairs(keys) do C.setEnabled(k, false) end
            end)
        end })
end

-- ---------------------------------------------------------------- 繪製
function Tab:prerender()
    -- 中文輸入法組字送出不觸發 onTextChange（家族 pitfalls UI 段）：每幀比對文字
    local q = self.search:getText()
    if q ~= self.query then
        self.query = q
        self:rebuildVehicles()
    end
    if self.resetAt then
        self.resetAt = self.resetAt - 1
        if self.resetAt <= 0 then
            self.resetAt = nil
            if self.shownScript then self.scene.javaObject:fromLua2("setVehicleScript", "v", self.shownScript) end
        end
    end
    self.srcMult:setVisible(self.source ~= ALL)
    for i, c in ipairs(self.cols) do
        W.card(self, c[1], 0, c[2], self.height)
        local batch = self.mode == "batch"
        local title = ({ T("ColVehicles"), batch and T("BatchListTitle") or T("ColPreview"), batch and T("BatchPanel") or T("WhereSpawns") })[i]
        U.text(self, title, c[1] + IN, IN, "text")
    end
end

function Tab:render()
    local FH, FM = U.fontH(), U.fontH(UIFont.Medium)
    local ch = W.ctrlH()
    -- 左：整包倍率列、車款標題（含全選勾選框）
    local multTextY = self.multY + math.floor((ch - FH) / 2)
    if self.source ~= ALL then
        U.text(self, U.fit(T("SourceMult"), self.cols[1][2] - IN * 2 - self.stepW - 8), IN, multTextY, "textMuted")
    else
        U.text(self, U.fit(T("SourceMultHint"), self.cols[1][2] - IN * 2), IN, multTextY, "textFaint")
    end
    local keys = self.filtered or {}
    W.checkbox(self, IN, self.vehTop + math.floor((FH - 16) / 2), self.sel:state(keys))
    U.text(self, T("ColModelsCount", tostring(#keys)), IN + 24, self.vehTop, "textMuted")
    if self.sel:count() > 0 then
        U.textRight(self, T("SelectedCount", tostring(self.sel:count())), self.cols[1][2] - IN, self.vehTop, "text")
    end

    local mx, mw = self.cols[2][1], self.cols[2][2]
    local x = mx + IN
    local rx, rw = self.cols[3][1], self.cols[3][2]
    if self.mode == "batch" then
        self:drawBatchSummary(x, IN + FH + IN, mw - IN * 2)
        U.text(self, U.fit(T("BatchMult"), rw - IN * 2 - self.stepW - 8), rx + IN, self.batchY + math.floor((ch - FH) / 2), "textMuted")
        return
    end
    local sc = self.scene
    if self.mode == "empty" then
        U.textRight(self, T("DragHint"), mx + mw - IN, IN, "textFaint")
        U.fill(self, sc:getX(), sc:getY(), sc.width, sc.height, sc.backgroundColor, "rect")
        local pick = T("PickVehicle")
        U.text(self, pick, sc:getX() + math.floor((sc.width - getTextManager():MeasureStringX(UIFont.Small, pick)) / 2),
            sc:getY() + math.floor((sc.height - FH) / 2), "textMuted")
        local y = self.zoneBox:getY()
        for _, line in ipairs(U.wrap(T("EmptyRight"), rw - IN * 2)) do
            U.text(self, line, rx + IN, y, "textMuted")
            y = y + FH + 2
        end
        return
    end

    local full = self.selectedFull
    local names = skinsOf(full)
    if self:showsTexture() then
        U.textRight(self, T("SkinPeek", tostring(self.skin + 1), tostring(#names)), mx + mw - IN, IN, "text")
        U.fill(self, sc:getX(), sc:getY(), sc.width, sc.height, sc.backgroundColor, "rect")
        local tex = names[self.skin + 1] and getTexture("media/textures/" .. names[self.skin + 1] .. ".png")
        if tex then
            local size = math.min(sc.width, sc.height)
            self:drawTextureScaled(tex, sc:getX() + math.floor((sc.width - size) / 2), sc:getY(), size, size, 1, 1, 1, 1)
        end
    else
        U.textRight(self, U.fit(T("DragHint"), mw - IN * 2 - getTextManager():MeasureStringX(UIFont.Small, T("ColPreview")) - 16),
            mx + mw - IN, IN, "textFaint")
    end
    local v = C.data.catalog[full]
    local y = self.infoY
    U.text(self, U.fit(v.display, mw - IN * 2, UIFont.Medium), x, y, "text", UIFont.Medium)
    y = y + FM + 2
    U.text(self, U.fit(full, mw - IN * 2), x, y, "textMuted")
    y = y + FH + 10
    -- 資訊晶片：來源、塗裝、狀態（狀態一律中性色＋圖示）
    local bx = x
    bx = bx + W.badge(self, T("InfoSource", U.packName(v.source)), bx, y, "text") + 6
    bx = bx + W.badge(self, T("InfoSkins", tostring(v.skins or 0)), bx, y, "text") + 6
    if not C.isEnabled(full) then bx = bx + W.badge(self, T("StatusDisabled"), bx, y, "textMuted", "lock") + 6 end
    if v.new then W.badge(self, T("BadgeNew"), bx, y, "textMuted", "tag") end
    y = y + 28
    local notes = { self.blockedPart and T("PreviewBlockedNote") or (#names > 1 and T("PreviewPaintNote") or T("PreviewColorNote")) }
    if self.previewState == "exhausted" then notes[2] = T("PreviewQuotaNote") end
    for _, note in ipairs(notes) do
        for i, line in ipairs(U.wrap(note, mw - IN * 2)) do
            if i > 2 then break end
            U.text(self, line, x, y, "textFaint")
            y = y + FH + 2
        end
    end
    self.swatches = nil
    if #names > 1 then self:drawSwatches(names, x, y + 6, mw - IN * 2, self.height - IN - y - 6) end

    U.text(self, U.fit(T("VehicleMult"), rw - IN * 2 - self.stepW - 8), rx + IN, self.vehMult:getY() + math.floor((ch - FH) / 2), "textMuted")
    if #self.zoneRows == 0 then
        local ly = self.zoneBox:getY() + 4
        for _, line in ipairs(U.wrap(T("NoZones"), self.zoneBox.width)) do
            U.text(self, line, self.zoneBox:getX(), ly, "textMuted")
            ly = ly + FH + 2
        end
    end
end

-- 多選時中欄：各來源台數與車名清單（名字在左側清單的提示裡看得到全文）
function Tab:drawBatchSummary(x, y, w)
    local FH, FM = U.fontH(), U.fontH(UIFont.Medium)
    local keys = self.sel:keys()
    U.text(self, T("BatchTitle", tostring(#keys)), x, y, "text", UIFont.Medium)
    y = y + FM + 8
    local bySrc, order = {}, {}
    for _, k in ipairs(keys) do
        local src = C.data.catalog[k] and C.data.catalog[k].source or "?"
        if not bySrc[src] then bySrc[src] = 0; order[#order + 1] = src end
        bySrc[src] = bySrc[src] + 1
    end
    for _, src in ipairs(order) do
        U.text(self, U.fit(T("BatchBySource", U.packName(src), tostring(bySrc[src])), w), x, y, "textMuted")
        y = y + FH + 4
    end
    y = y + 8
    local maxY = self.clearBtn:getY() - 8
    for i, k in ipairs(keys) do
        if y + FH * 2 > maxY then
            U.text(self, T("BatchMore", tostring(#keys - i + 1)), x, y, "textMuted")
            break
        end
        U.text(self, U.fit(C.data.catalog[k].display, w), x, y, "text")
        y = y + FH + 2
    end
end

-- 依可用空間縮放色票，塞不下的列不畫（12 款在 1280x780 面板約兩列）；預覽中的那款用強調色框，滑過的框變亮
function Tab:drawSwatches(names, x, y, w, h)
    local gap, s = 6, 64
    local cols = 1
    while true do
        cols = math.max(1, math.floor((w + gap) / (s + gap)))
        if s <= 28 or math.ceil(#names / cols) * (s + gap) - gap <= h then break end
        s = s - 4
    end
    local mx, my = self:getMouseX(), self:getMouseY()
    self.swatches = {}
    for i, name in ipairs(names) do
        local sx = x + ((i - 1) % cols) * (s + gap)
        local sy = y + math.floor((i - 1) / cols) * (s + gap)
        if sy + s > y + h then break end
        local tex = getTexture("media/textures/" .. name .. ".png")
        U.fill(self, sx, sy, s, s, "well", "rect")
        if tex then self:drawTextureScaled(tex, sx, sy, s, s, 1, 1, 1, 1) end
        local hover = self:isMouseOver() and mx >= sx and mx < sx + s and my >= sy and my < sy + s
        local col = self.skin == i - 1 and U.COL.accent or { r = 1, g = 1, b = 1, a = hover and 0.6 or 0.15 }
        U.border(self, sx, sy, s, s, col, "rect")
        self.swatches[i] = { sx, sy, s }
    end
end

function Tab.drawSourceRow(list, y, item)
    local d = item.item
    local tab = list.tab
    local w = W.rowBg(list, y, item, tab.source == d.key)
    local fh = U.fontH()
    local tm = getTextManager()
    local mid = y + math.floor((list.itemheight - fh) / 2)
    local rx = w - 12
    U.textRight(list, tostring(d.count), rx, mid, "textMuted")
    rx = rx - tm:MeasureStringX(UIFont.Small, tostring(d.count)) - 8
    local m = d.key ~= ALL and C.multOf("sources", d.key) or 1
    if m ~= 1 then
        local label = fmtMult(m)
        rx = rx - tm:MeasureStringX(UIFont.Small, label) - 16
        W.badge(list, label, rx, y + math.floor((list.itemheight - 20) / 2), "text")
        rx = rx - 6
    end
    if d.new and d.new > 0 then
        local label = T("BadgeNewCount", tostring(d.new))
        rx = rx - tm:MeasureStringX(UIFont.Small, label) - 32
        W.badge(list, label, rx, y + math.floor((list.itemheight - 20) / 2), "textMuted", "tag")
        rx = rx - 6
    end
    U.text(list, U.fit(item.text, rx - 22), 14, mid, "text")
    return y + list.itemheight
end

function Tab.drawVehicleRow(list, y, item)
    local d = item.item
    local tab = list.tab
    local fh = U.fontH()
    local tm = getTextManager()
    if d.kind == "group" then
        local w = W.rowBg(list, y, item, false)
        local cy = y + math.floor((list.itemheight - 16) / 2)
        local open = tab.expanded[d.name]
        if not W.icon(list, open and "chevronDown" or "chevronRight", 8, cy, 16, "textMuted") then
            U.text(list, open and "v" or ">", 10, cy, "textMuted")
        end
        W.checkbox(list, 30, cy, tab.sel:state(d.members))
        local count = T("Variants", tostring(#d.members))
        U.textRight(list, count, w - 12, y + math.floor((list.itemheight - fh) / 2), "textMuted")
        U.text(list, U.fit(d.name, w - 12 - tm:MeasureStringX(UIFont.Small, count) - 64), 54, y + math.floor((list.itemheight - fh) / 2), "text")
        return y + list.itemheight
    end
    local on = tab.sel:has(d.full)
    local w = W.rowBg(list, y, item, on)
    local v = C.data.catalog[d.full]
    local cx = d.child and 30 or 8
    W.checkbox(list, cx, y + math.floor((list.itemheight - 16) / 2), on)
    local x = cx + 24
    local enabled = C.isEnabled(d.full)
    local right = w - 8
    local m = C.multOf("vehicles", d.full)
    if not enabled then
        right = right - tm:MeasureStringX(UIFont.Small, T("MarkDisabled")) - 32
        W.badge(list, T("MarkDisabled"), right, y + 5, "textMuted", "lock")
    elseif v.new then
        right = right - tm:MeasureStringX(UIFont.Small, T("BadgeNew")) - 32
        W.badge(list, T("BadgeNew"), right, y + 5, "textMuted", "tag")
    elseif m ~= 1 then
        right = right - tm:MeasureStringX(UIFont.Small, fmtMult(m)) - 16
        W.badge(list, fmtMult(m), right, y + 5, "text")
    end
    U.text(list, U.fit(v.display, right - x - 6), x, y + 6, enabled and "text" or "textFaint")
    U.text(list, U.fit(d.full, w - x - 12), x, y + fh + 8, "textMuted")
    return y + list.itemheight
end

-- ---------------------------------------------------------------- 區域列（名稱＋占比、權重步進器、移出此區域）
MVSC_ZoneWeightRow = ISPanel:derive("MVSC_ZoneWeightRow")
local Row = MVSC_ZoneWeightRow

function Row:new(x, y, w, h, tab, zone)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.tab, o.zone = tab, zone
    o.background = false
    return o
end

function Row:createChildren()
    local fh, ch = U.fontH(), W.ctrlH()
    local tab, zone = self.tab, self.zone
    self.stepper = W.stepper(self, 8, fh + 12, tab.stepW, ch, {
        get = function() return C.weightOf(zone, tab.selectedFull) end,
        set = function(v) C.setWeight(zone, tab.selectedFull, v) end,
        step = stepWeight, format = function(v) return T("WeightValue", U.num(v or 0)) end,
        title = T("SetWeight"), prompt = T("WeightPrompt") })
    local bw = getTextManager():MeasureStringX(UIFont.Small, T("DisableInZone")) + 28
    self.removeBtn = W.button(self, self.width - bw - 8, fh + 12, bw, ch, T("DisableInZone"), self, Row.onRemove, "secondary")
end

function Row:onRemove()
    C.setWeight(self.zone, self.tab.selectedFull, 0)
end

function Row:prerender()
    local full = self.tab.selectedFull
    local eff = C.effective()
    local z = eff and eff[self.zone]
    local total, mine = 0, nil
    if z then
        for s, def in pairs(z.vehicles) do
            total = total + def.spawnChance
            if s == full then mine = def.spawnChance end
        end
    end
    self.removeBtn:setUsable(C.weightOf(self.zone, full) > 0)
    U.fill(self, 0, 0, self.width, self.height, { r = 1, g = 1, b = 1, a = 0.035 })
    local tm = getTextManager()
    local now = U.pct(mine and total > 0 and mine / total * 100 or 0)
    local orig = U.pct(C.baseShare(self.zone, full) * 100)
    local right = orig == now and T("ShareInZone", now) or T("ShareVsBase", now, orig)
    local rx = self.width - 10
    U.textRight(self, right, rx, 6, mine and "textMuted" or "textFaint")
    rx = rx - tm:MeasureStringX(UIFont.Small, right) - 8
    if not mine then
        local label = C.isEnabled(full) and T("MarkRemoved") or T("MarkDisabled")
        rx = rx - tm:MeasureStringX(UIFont.Small, label) - 16
        W.badge(self, label, rx, 4, "textMuted")
        rx = rx - 6
    end
    U.text(self, U.fit(U.zoneLabel(self.zone), rx - 18), 10, 6, "text")
end
