-- 「車輛」分頁（設計 C1）：左＝來源與車款卡片，中＝3D 預覽卡片，右＝各區域權重卡片。
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "Vehicles/ISUI/ISUI3DScene"
require "MinidoracatVehicleSpawnControl/MVSC_Widgets"

local M = MinidoracatVehicleSpawnControl
local C, U, W = M.Client, M.UI, M.W
local T = U.T

MVSC_VehicleTab = ISPanel:derive("MVSC_VehicleTab")
local Tab = MVSC_VehicleTab
local PAD = W.PAD
local IN = 12 -- 卡片內距
local ALL = "*"

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

function Tab:groupOf(full)
    local v = C.data.catalog[full]
    local members = {}
    for f, x in pairs(C.data.catalog) do
        if x.display == v.display then members[#members + 1] = f end
    end
    return M.sortSafe(members)
end

-- 塗裝色票：3D 預覽只能顯示第 0 款（AGENTS 踩坑），各款改以原始貼圖縮圖呈現。
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
    return o
end

function Tab:createChildren()
    local FH = U.fontH()
    local ch = W.ctrlH()
    local h = self.height
    local lw = math.floor(self.width * 0.27)
    local mw = math.floor(self.width * 0.39)
    local mx = lw + PAD
    local rx = mx + mw + PAD
    local rw = self.width - rx
    self.cols = { { 0, lw }, { mx, mw }, { rx, rw } }
    local head = FH + IN * 2 -- 卡片標題列

    -- 左：來源＋車款
    self.search = W.search(self, IN, head, lw - IN * 2, ch, T("SearchVehicle"))
    local srcTop = head + ch + PAD
    local srcH = math.floor((h - srcTop) * 0.30)
    self.sourceList = W.list(self, IN - 4, srcTop, lw - IN * 2 + 8, srcH, FH + 12, Tab.drawSourceRow, self, Tab.onSource)
    self.sourceList.tab = self
    self.vehTop = srcTop + srcH + PAD
    self.vehicleList = W.list(self, IN - 4, self.vehTop + FH + 8, lw - IN * 2 + 8, h - self.vehTop - FH - 8 - IN,
        FH * 2 + 12, Tab.drawVehicleRow, self, Tab.onVehicle)
    self.vehicleList.tab = self

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
    -- 原版 ISUI3DScene 左鍵拖曳是 dragView（平移），滾輪 zoom 會朝滑鼠位置偏移（UI3DScene.java:902-914,1052-1058）。
    -- 預覽改成：左鍵拖曳轉視角、滾輪以中心縮放，車永遠置中；視角一律 UserDefined，按鈕只換角度
    self.scene:setView("UserDefined")
    self.scene.onMouseDown = Tab.sceneDown
    self.scene.onMouseMove = Tab.sceneMove
    self.scene.onMouseMoveOutside = Tab.sceneMove
    self.scene.onMouseWheel = Tab.sceneWheel
    j:fromLua1("setMaxZoom", 20)
    self:setAngle(Tab.ANGLES.iso)
    j:fromLua1("setDrawGrid", false)
    j:fromLua1("createVehicle", "v")
    j:fromLua2("setObjectVisible", "v", false)
    local views = { { "ViewFront", "front" }, { "ViewSide", "side" }, { "ViewTop", "top" }, { "ViewReset", "iso" } }
    local bw = math.floor((mw - IN * 2 - PAD * 3) / 4)
    local by = self.scene:getBottom() + PAD
    for i, v in ipairs(views) do
        local b = W.button(self, mx + IN + (i - 1) * (bw + PAD), by, bw, ch, T(v[1]), self, Tab.onView, "secondary",
            v[2] == "iso" and "reload" or nil)
        b.view = v[2]
    end
    self.infoY = by + ch + IN

    -- 右：區域權重（列可捲動）
    local bottomH = ch * 3 + PAD * 3 + IN
    self.zoneBox = ISPanel:new(rx + IN, head, rw - IN * 2, h - head - bottomH)
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
    self.groupCheck = W.check(self, rx + IN, ay, rw - IN * 2, "", self, nil)
    self.addBtn = W.button(self, rx + IN, ay + ch + PAD, rw - IN * 2, ch, T("AddZone"), self, Tab.onAddZone, "secondary", "layers")
    self.toggleBtn = W.button(self, rx + IN, ay + (ch + PAD) * 2, rw - IN * 2, ch, T("DisableEverywhere"), self, Tab.onToggle, "danger")
    self:refresh()
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
    list:addItem(T("Source_pz-vanilla"), { key = M.VANILLA, count = counts[M.VANILLA] or 0, new = news[M.VANILLA] })
    for _, src in ipairs(mods) do list:addItem(names[src] or src, { key = src, count = counts[src], new = news[src] }) end
    self:rebuildVehicles()
    self:rebuildZones()
end

function Tab:rebuildVehicles()
    local list = self.vehicleList
    local keepY = list:getYScroll()
    list:clear()
    for _, g in ipairs(self:buildGroups()) do
        if #g.members == 1 then
            list:addItem(g.name, { kind = "vehicle", full = g.members[1] })
        else
            list:addItem(g.name, { kind = "group", name = g.name, count = #g.members })
            if self.expanded[g.name] or (self.query or "") ~= "" then
                for _, full in ipairs(g.members) do list:addItem(full, { kind = "vehicle", full = full, child = true }) end
            end
        end
    end
    list:setYScroll(keepY)
end

function Tab:select(full)
    if not (C.data and C.data.catalog[full]) then return end
    self.selectedFull = full
    local v = C.data.catalog[full]
    self.expanded[v.display] = true
    self.groupMembers = self:groupOf(full)
    self.groupCheck.label = T("ApplyToVariants", v.display, tostring(#self.groupMembers))
    self.groupCheck.checked = false
    local j = self.scene.javaObject
    j:fromLua2("setVehicleScript", "v", full)
    j:fromLua2("setObjectVisible", "v", true)
    -- 初始化當下模型若還沒載入，場景會一直空白直到再次 setVehicleScript（UI3DScene.java:6101-6105）
    self.resetAt = 30
    self.swatches, self.peek = nil, nil
    self.scene:setVisible(true)
    self:rebuildVehicles()
    self:rebuildZones()
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
    local hasSel = full ~= nil and C.data ~= nil
    self.addBtn:setVisible(hasSel)
    self.toggleBtn:setVisible(hasSel)
    self.groupCheck:setVisible(hasSel and self.groupMembers ~= nil and #self.groupMembers > 1)
    if not hasSel then return end
    local rh = U.fontH() * 2 + 30
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

function Tab:onDraft()
    for _, row in ipairs(self.zoneRows) do row:sync() end
end

-- ---------------------------------------------------------------- 事件
function Tab:onSource(item)
    self.source = item.key
    self:rebuildVehicles()
end

function Tab:onVehicle(item)
    if item.kind == "group" then
        self.expanded[item.name] = not self.expanded[item.name]
        self:rebuildVehicles()
    else
        self:select(item.full)
    end
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
end

function Tab:onView(button)
    self:setAngle(Tab.ANGLES[button.view])
end

-- 以下三個掛在 scene 上，self 是 scene、parent 是本分頁
function Tab.sceneDown(scene)
    scene.mouseDown = true
    return true
end

function Tab.sceneMove(scene, dx, dy)
    if not scene.mouseDown then return end
    local r = scene.parent.rot
    r[2] = (r[2] + dx / 2) % 360
    r[1] = math.max(-89, math.min(89, r[1] + dy / 2))
    scene.javaObject:fromLua3("setViewRotation", r[1], r[2], r[3])
end

function Tab.sceneWheel(scene, del)
    local tab = scene.parent
    tab.zoom = math.max(1, math.min(20, tab.zoom - del))
    scene.javaObject:fromLua1("setZoom", tab.zoom)
    return true
end

function Tab:targets()
    if self.groupCheck:isVisible() and self.groupCheck.checked then return self.groupMembers end
    return { self.selectedFull }
end

function Tab:onAddZone(button)
    local present = {}
    for _, z in ipairs(self:zonesOf(self.selectedFull)) do present[z] = true end
    local names = {}
    for z in pairs(C.data.base.zones) do
        if not present[z] then names[z] = true end
    end
    local groups = {}
    for _, g in ipairs(U.groupZones(names)) do
        local items = {}
        for _, z in ipairs(g.zones) do items[#items + 1] = { U.zoneLabel(z), z } end
        groups[#groups + 1] = { title = T("Group_" .. g.group), items = items }
    end
    W.picker(button:getAbsoluteX(), button:getAbsoluteY() + button.height + 4, groups, self, Tab.addToZone)
end

function Tab:addToZone(zone)
    for _, full in ipairs(self:targets()) do C.setWeight(zone, full, 10) end
    self:rebuildZones()
end

function Tab:onToggle()
    local full = self.selectedFull
    if C.isEnabled(full) then
        local v = C.data.catalog[full]
        local tab = self
        W.dialog({ title = T("DisableEverywhere"), message = T("ConfirmDisable", v.display), confirm = T("DisableEverywhere"),
            danger = true, onConfirm = function()
                for _, f in ipairs(tab:targets()) do C.setEnabled(f, false) end
                tab:rebuildZones()
            end })
    else
        for _, f in ipairs(self:targets()) do C.setEnabled(f, true) end
        self:rebuildZones()
    end
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
            if self.selectedFull then self.scene.javaObject:fromLua2("setVehicleScript", "v", self.selectedFull) end
        end
    end
    -- 滑到色票上：暫時收起 3D 場景，在同位置放大該款貼圖（場景是子元件，會蓋住父層繪製）
    local peek
    if self.swatches then
        local mx, my = self:getMouseX(), self:getMouseY()
        for i, r in ipairs(self.swatches) do
            if mx >= r[1] and mx < r[1] + r[3] and my >= r[2] and my < r[2] + r[3] then peek = i end
        end
    end
    if peek ~= self.peek then
        self.peek = peek
        self.scene:setVisible(peek == nil)
    end
    for i, c in ipairs(self.cols) do
        W.card(self, c[1], 0, c[2], self.height)
        local title = ({ T("ColVehicles"), T("ColPreview"), T("WhereSpawns") })[i]
        U.text(self, title, c[1] + IN, IN, "text")
    end
end

function Tab:render()
    local FH = U.fontH()
    U.text(self, T("ColModels"), IN, self.vehTop, "textMuted")
    local mx, mw = self.cols[2][1], self.cols[2][2]
    local full = self.selectedFull
    local names = full and skinsOf(full) or {}
    local peek = self.peek and self.swatches and self.swatches[self.peek]
    if peek then
        U.textRight(self, T("SkinPeek", tostring(self.peek), tostring(#names)), mx + mw - IN, IN, "accent")
        local sc = self.scene
        U.fill(self, sc:getX(), sc:getY(), sc.width, sc.height, sc.backgroundColor, "rect")
        if peek[4] then
            local size = math.min(sc.width, sc.height)
            self:drawTextureScaled(peek[4], sc:getX() + math.floor((sc.width - size) / 2), sc:getY(), size, size, 1, 1, 1, 1)
        end
    else
        U.textRight(self, T("DragHint"), mx + mw - IN, IN, "textFaint")
    end
    local x, y = mx + IN, self.infoY
    if not (full and C.data and C.data.catalog[full]) then
        U.text(self, T("PickVehicle"), x, y, "textMuted")
        return
    end
    local v = C.data.catalog[full]
    U.text(self, U.fit(v.display, mw - IN * 2, UIFont.Medium), x, y, "text", UIFont.Medium)
    y = y + U.fontH(UIFont.Medium) + 2
    U.text(self, U.fit(full, mw - IN * 2), x, y, "textMuted")
    y = y + FH + 10
    -- 資訊晶片：來源、塗裝、狀態
    local bx = x
    bx = bx + W.badge(self, T("InfoSource", v.sourceName or v.source), bx, y, "text") + 6
    bx = bx + W.badge(self, T("InfoSkins", tostring(v.skins or 0)), bx, y, "text") + 6
    if not C.isEnabled(full) then bx = bx + W.badge(self, T("StatusDisabled"), bx, y, "errorText") + 6 end
    if v.new then W.badge(self, T("BadgeNew"), bx, y, "accent") end
    y = y + 28
    if #names > 1 then
        U.text(self, U.fit(T("PreviewSkinHover"), mw - IN * 2), x, y, "textFaint")
        y = y + FH + 8
        self:drawSwatches(names, x, y, mw - IN * 2, self.height - IN - y)
    else
        U.text(self, U.fit(T("PreviewSkinNote"), mw - IN * 2), x, y, "textFaint")
    end
    if #self.zoneRows == 0 then U.text(self, U.fit(T("NoZones"), self.zoneBox.width), self.zoneBox:getX(), self.zoneBox:getY() + 4, "textMuted") end
end

-- 依可用空間縮放色票，塞不下的列不畫（12 款在 1280x780 面板約兩列）
function Tab:drawSwatches(names, x, y, w, h)
    local gap, s = 6, 64
    local cols = 1
    while true do
        cols = math.max(1, math.floor((w + gap) / (s + gap)))
        if s <= 28 or math.ceil(#names / cols) * (s + gap) - gap <= h then break end
        s = s - 4
    end
    self.swatches = {}
    for i, name in ipairs(names) do
        local sx = x + ((i - 1) % cols) * (s + gap)
        local sy = y + math.floor((i - 1) / cols) * (s + gap)
        if sy + s > y + h then break end
        local tex = getTexture("media/textures/" .. name .. ".png")
        U.fill(self, sx, sy, s, s, "well", "rect")
        if tex then self:drawTextureScaled(tex, sx, sy, s, s, 1, 1, 1, 1) end
        U.border(self, sx, sy, s, s, self.peek == i and U.COL.accent or { r = 1, g = 1, b = 1, a = 0.15 }, "rect")
        self.swatches[i] = { sx, sy, s, tex }
    end
end

function Tab.drawSourceRow(list, y, item)
    local d = item.item
    local w = W.rowBg(list, y, item, list.tab.source == d.key)
    local fh = U.fontH()
    U.text(list, U.fit(item.text, w - 110), 14, y + math.floor((list.itemheight - fh) / 2), "text")
    local rx = w - 12
    U.textRight(list, tostring(d.count), rx, y + math.floor((list.itemheight - fh) / 2), "textMuted")
    if d.new and d.new > 0 then
        local label = T("BadgeNewCount", tostring(d.new))
        local bw = getTextManager():MeasureStringX(UIFont.Small, label) + 16
        W.badge(list, label, rx - 34 - bw, y + math.floor((list.itemheight - 20) / 2), "accent")
    end
    return y + list.itemheight
end

function Tab.drawVehicleRow(list, y, item)
    local d = item.item
    local fh = U.fontH()
    local sel = d.kind == "vehicle" and d.full == list.tab.selectedFull
    local w = W.rowBg(list, y, item, sel)
    if d.kind == "group" then
        local cy = y + math.floor((list.itemheight - 16) / 2)
        local open = list.tab.expanded[d.name]
        if not W.icon(list, open and "chevronDown" or "chevronRight", 10, cy, 16, "textMuted") then
            U.text(list, open and "v" or ">", 12, cy, "textMuted")
        end
        U.text(list, U.fit(d.name, w - 130), 32, y + math.floor((list.itemheight - fh) / 2), "text")
        U.textRight(list, T("Variants", tostring(d.count)), w - 12, y + math.floor((list.itemheight - fh) / 2), "textMuted")
    else
        local v = C.data.catalog[d.full]
        local x = d.child and 32 or 14
        local label = v.display
        local enabled = C.isEnabled(d.full)
        U.text(list, U.fit(label, w - x - 80), x, y + 6, enabled and "text" or "textFaint")
        U.text(list, U.fit(d.full, w - x - 20), x, y + fh + 8, "textMuted")
        if not enabled then W.badge(list, T("MarkDisabled"), w - 12 - getTextManager():MeasureStringX(UIFont.Small, T("MarkDisabled")) - 16, y + 5, "textMuted")
        elseif v.new then W.badge(list, T("BadgeNew"), w - 12 - getTextManager():MeasureStringX(UIFont.Small, T("BadgeNew")) - 16, y + 5, "accent") end
    end
    return y + list.itemheight
end

-- ---------------------------------------------------------------- 區域列（卡片內一列：名稱、權重／占比、滑桿、移出）
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
    local fh = U.fontH()
    local bw = 72
    self.slider = W.slider(self, 4, fh + 12, self.width - bw - 16, 18, 0, 100, 1, self, Row.onSlide)
    self.removeBtn = W.button(self, self.width - bw - 6, fh + 8, bw, 24, T("RemoveFromZone"), self, Row.onRemove, "ghost")
    self:sync(true)
end

function Row:sync(force)
    local w = C.weightOf(self.zone, self.tab.selectedFull)
    if force or not self.slider.dragInside then
        self.slider:setRange(0, math.max(100, math.ceil(w * 2)), 1)
        self.slider:setValue(w)
    end
end

function Row:onSlide(value)
    for _, full in ipairs(self.tab:targets()) do C.setWeight(self.zone, full, value) end
end

function Row:onRemove()
    for _, full in ipairs(self.tab:targets()) do C.setWeight(self.zone, full, 0) end
    self:sync(true)
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
    U.fill(self, 0, 0, self.width, self.height, { r = 1, g = 1, b = 1, a = 0.035 })
    U.text(self, U.fit(U.zoneLabel(self.zone), self.width - 190), 10, 6, "text")
    local w = C.weightOf(self.zone, full)
    local right = T("WeightShare", U.num(w), U.pct(mine and total > 0 and mine / total * 100 or 0))
    local rx = self.width - 10
    U.textRight(self, right, rx, 6, mine and "textMuted" or "textFaint")
    if not mine then
        local tw = getTextManager():MeasureStringX(UIFont.Small, right)
        W.badge(self, T("MarkDisabled"), rx - tw - 16 - getTextManager():MeasureStringX(UIFont.Small, T("MarkDisabled")) - 16, 4, "textMuted")
    end
end
