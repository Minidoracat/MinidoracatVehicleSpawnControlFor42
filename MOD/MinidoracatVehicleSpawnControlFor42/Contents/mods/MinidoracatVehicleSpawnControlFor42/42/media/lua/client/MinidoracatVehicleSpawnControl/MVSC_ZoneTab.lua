-- 「區域」分頁（設計 C2）：左＝分組區域卡片，右＝參數、來源組成（長條＋圖例）、車款表與批次操作。
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "MinidoracatVehicleSpawnControl/MVSC_Widgets"

local M = MinidoracatVehicleSpawnControl
local C, U, W = M.Client, M.UI, M.W
local T = U.T

MVSC_ZoneTab = ISPanel:derive("MVSC_ZoneTab")
local Tab = MVSC_ZoneTab
local PAD = W.PAD
local IN = 12
local GAP = 24   -- 參數欄與欄的距離，要明顯大於標籤到數值的 8px（組間距 > 組內距）
local CHK = 36   -- 列首勾選欄
local ARROW = 40 -- 列尾「在車輛分頁開啟」箭頭
local SHADE = { 0.46, 0.33, 0.25, 0.19 }

-- 面板上調整的四個參數（其餘仍可在 config.json 改）；車況 baseVehicleQuality 以 0–2 顯示成 0–200%
Tab.PARAMS = {
    { key = "spawnRate", label = "ParamSpawnRate", max = 100, step = 1, scale = 1 },
    { key = "chanceToSpawnBurnt", label = "ParamBurnt", max = 100, step = 1, scale = 1 },
    { key = "chanceToSpawnSpecial", label = "ParamSpecial", max = 100, step = 1, scale = 1 },
    { key = "baseVehicleQuality", label = "ParamQuality", max = 200, step = 5, scale = 100 },
}

function Tab:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.query = ""
    o.sel = W.selection()
    o.order = {}
    return o
end

function Tab:createChildren()
    local FH, FM = U.fontH(), U.fontH(UIFont.Medium)
    local ch = W.ctrlH()
    local tm = getTextManager()
    local lw = math.floor(self.width * 0.26)
    local rx = lw + PAD
    local rw = self.width - rx
    self.lw, self.rx, self.rw = lw, rx, rw
    local head = FH + IN * 2

    self.search = W.search(self, IN, head, lw - IN * 2, ch, T("SearchZone"))
    self.zoneList = W.list(self, IN - 4, head + ch + PAD, lw - IN * 2 + 8, self.height - head - ch - PAD - IN,
        FH + 12, Tab.drawZoneRow, self, Tab.onZone)
    self.zoneList.tab = self

    local ix, iw = rx + IN, rw - IN * 2
    self.ix, self.iw = ix, iw
    -- 整區還原和勾選無關，放在區域標題列右側，按下要確認
    local rzw = tm:MeasureStringX(UIFont.Small, T("ResetZone")) + 44
    self.resetZoneBtn = W.button(self, ix + iw - rzw, IN - 4, rzw, ch, T("ResetZone"), self, Tab.onResetZone, "secondary", "reload")

    -- 參數：四欄，標籤後緊接數值，下方滑桿
    self.paramY = IN + math.max(FM, ch) + 10
    self.cw = math.floor((iw - GAP * 3) / 4)
    self.sliders = {}
    for i, p in ipairs(Tab.PARAMS) do
        local s = W.slider(self, ix + (i - 1) * (self.cw + GAP) - 6, self.paramY + FH + 6, self.cw + 12, 18, 0, p.max, p.step, self, Tab.onParam)
        s.param = p
        self.sliders[i] = s
    end
    self.noteY = self.paramY + FH + 30
    self.barY = self.noteY + (FH + 2) * 2 + FH + 8 -- 說明最多換兩行，下面是「車型組成」標題
    self.barH = 22
    self.legendY = self.barY + self.barH + 6
    self.legendH = (FH + 6) * 2

    -- 批次列：「已選 N 款」＋清除，後面五顆都只作用在已選的車
    local by = self.legendY + self.legendH + PAD
    self.selW = tm:MeasureStringX(UIFont.Small, T("SelectedCount", "999"))
    local clw = tm:MeasureStringX(UIFont.Small, T("ClearSelection")) + 20
    self.clearBtn = W.button(self, ix + self.selW + 6, by, clw, ch, T("ClearSelection"), self, Tab.onClearSel, "ghost")
    local bx0 = ix + self.selW + 6 + clw + PAD
    local labels = { { "Halve", Tab.onHalve }, { "Double", Tab.onDouble }, { "SetWeight", Tab.onSetWeight },
        { "DisableInZone", Tab.onDisableSel }, { "ResetSelected", Tab.onResetSel, "reload" } }
    local bw = math.floor((ix + iw - bx0 - PAD * 4) / 5)
    self.batchBtns = {}
    for i, b in ipairs(labels) do
        self.batchBtns[i] = W.button(self, bx0 + (i - 1) * (bw + PAD), by, bw, ch, T(b[1]), self, b[2], "secondary", b[3])
    end
    self.batchY = by
    self.headerY = by + ch + PAD
    self.table = W.list(self, ix - 4, self.headerY + FH + 6, iw + 8, self.height - self.headerY - FH - 6 - IN,
        FH * 2 + 12, Tab.drawVehicleRow)
    self.table.tab = self
    self.table.onMouseDown = Tab.onTableMouseDown
    self.table.onMouseDoubleClick = Tab.onTableDoubleClick
    self:refresh()
end

-- ---------------------------------------------------------------- 資料
function Tab:refresh()
    if not C.data then return end
    local q = string.lower(self.query or "")
    local names = {}
    for z in pairs(C.data.base.zones) do
        if q == "" or string.find(string.lower(z), q, 1, true) or string.find(string.lower(U.zoneLabel(z)), q, 1, true) then
            names[z] = true
        end
    end
    local list = self.zoneList
    local keepY = list:getYScroll()
    list:clear()
    for _, g in ipairs(U.groupZones(names)) do
        list:addItem(T("Group_" .. g.group), { header = true })
        for _, z in ipairs(g.zones) do list:addItem(z, { zone = z }, U.zoneLabel(z) .. " <LINE> " .. z) end
    end
    list:setYScroll(keepY)
    if not self.zone or not C.data.base.zones[self.zone] then self.zone = C.data.base.zones.parkingstall and "parkingstall" or nil end
    self:rebuildTable()
end

local function byWeight(zone)
    return function(a, b)
        local wa, wb = C.weightOf(zone, a), C.weightOf(zone, b)
        if wa ~= wb then return wa > wb end
        return a < b
    end
end

-- 表格列：原始分布、草稿覆寫的聯集；移出的也列出（標示且 0%）。
-- 只在切換區域時依權重排序；編輯中維持順序，免得改完權重列就跳位（新加入的排最後）
function Tab:rebuildTable()
    local t = self.table
    local keepY = t:getYScroll()
    t:clear()
    if not self.zone then return end
    local base = C.data.base.zones[self.zone]
    local seen, rows = {}, {}
    local function add(s)
        if not seen[s] and C.data.catalog[s] then seen[s] = true; rows[#rows + 1] = s end
    end
    for s in pairs(base.vehicles) do add(s) end
    local dz = C.draft.zones[self.zone]
    if dz and dz.weights then
        for s in pairs(dz.weights) do add(s) end
    end
    if self.orderZone ~= self.zone then
        M.sortSafe(rows, byWeight(self.zone))
        self.order, self.orderZone = rows, self.zone
    else
        local order, kept, added = {}, {}, {}
        for _, s in ipairs(self.order) do
            if seen[s] then order[#order + 1] = s; kept[s] = true end
        end
        for _, s in ipairs(rows) do
            if not kept[s] then added[#added + 1] = s end
        end
        for _, s in ipairs(M.sortSafe(added)) do order[#order + 1] = s end
        self.order = order
    end
    for _, s in ipairs(self.order) do t:addItem(s, { full = s }, self:rowTip(s)) end
    self.sel:retain(self.order)
    t:setYScroll(keepY)
    self:syncSliders()
end

-- 列提示：完整名稱（欄內會截斷）與開啟方式（列尾箭頭只有圖示）
function Tab:rowTip(full)
    local v = C.data.catalog[full]
    return table.concat({ v.display, full, T("InfoSource", U.packName(v.source)), T("RowOpenHint") }, " <LINE> ")
end

-- 拖曳中的滑桿不回寫（不然會跟滑鼠搶值）
function Tab:syncSliders()
    if not self.zone then return end
    for i, p in ipairs(Tab.PARAMS) do
        local s = self.sliders[i]
        if not s.dragInside then s:setValue((C.paramOf(self.zone, p.key) or 0) * p.scale) end
    end
end

function Tab:onDraft()
    if self.zone then self:rebuildTable() end
end

function Tab:selected()
    return self.sel:keys()
end

-- ---------------------------------------------------------------- 事件
function Tab:onZone(item)
    if item.header then return end
    self.zone = item.zone
    self.sel:clear()
    self:rebuildTable()
end

function Tab:onParam(value, slider)
    if not self.zone then return end
    local p = slider.param
    local v = value / p.scale
    if p.scale ~= 1 then v = math.floor(v * 100 + 0.5) / 100 end
    C.setParam(self.zone, p.key, v)
end

-- 勾選欄＝加入／取消；列尾箭頭＝到「車輛」分頁；其他位置照清單慣例（點選、Ctrl、Shift）
function Tab.onTableMouseDown(list, x, y)
    local row = list:rowAt(x, y)
    if row < 1 or not list.items[row] then return true end
    local tab = list.tab
    if x > list:getWidth() - ARROW then
        if tab.panel then tab.panel:showVehicle(list.items[row].item.full) end
        return true
    end
    tab.sel:click(tab.order, row, x < CHK)
    return true
end

function Tab.onTableDoubleClick(list, x, y)
    local row = list:rowAt(x, y)
    if row > 0 and list.items[row] and list.tab.panel then list.tab.panel:showVehicle(list.items[row].item.full) end
    return true
end

-- 表頭勾選框全選／全取消；點組成長條或圖例的來源＝改選那個來源的所有車
function Tab:onMouseDown(x, y)
    local hx = self.ix - 4 + 12
    if x >= hx - 4 and x <= hx + 20 and y >= self.headerY - 4 and y <= self.headerY + U.fontH() + 4 then
        self.sel:toggleAll(self.order)
        return true
    end
    for _, r in ipairs(self.srcRects or {}) do
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            self:selectSource(r.src)
            return true
        end
    end
    return true
end

function Tab:selectSource(src)
    self.sel:clear()
    for _, s in ipairs(self.order) do
        if C.data.catalog[s].source == src then self.sel.set[s] = true end
    end
end

function Tab:onClearSel() self.sel:clear() end

local function scale(tab, factor)
    C.batch(function()
        for _, s in ipairs(tab:selected()) do C.setWeight(tab.zone, s, C.weightOf(tab.zone, s) * factor) end
    end)
end

function Tab:onHalve() scale(self, 0.5) end
function Tab:onDouble() scale(self, 2) end

function Tab:onSetWeight()
    local sel = self:selected()
    if #sel == 0 then return end
    local tab = self
    W.dialog({ title = T("SetWeight"), message = T("SetWeightPrompt"), input = "10", confirm = T("SetWeight"),
        onConfirm = function(text)
            local w = tonumber(text)
            if not w or w < 0 then return end
            C.batch(function()
                for _, s in ipairs(sel) do C.setWeight(tab.zone, s, w) end
            end)
        end })
end

function Tab:onDisableSel()
    local tab = self
    C.batch(function()
        for _, s in ipairs(tab:selected()) do C.setWeight(tab.zone, s, 0) end
    end)
end

function Tab:onResetSel()
    C.resetZoneWeights(self.zone, self:selected())
end

function Tab:onResetZone()
    local zone = self.zone
    if not zone then return end
    W.dialog({ title = T("ResetZone"), message = T("ConfirmResetZone", U.zoneLabel(zone)), confirm = T("ResetZoneConfirm"),
        danger = true, onConfirm = function() C.resetZone(zone) end })
end

-- ---------------------------------------------------------------- 繪製
local function zoneShares(zone)
    local eff = C.effective()
    local z = eff and eff[zone]
    local total, bySource, per, count = 0, {}, {}, {}
    if z then
        for s, def in pairs(z.vehicles) do
            total = total + def.spawnChance
            per[s] = def.spawnChance
            local src = C.data.catalog[s] and C.data.catalog[s].source or "?"
            bySource[src] = (bySource[src] or 0) + def.spawnChance
            count[src] = (count[src] or 0) + 1
        end
    end
    return total, bySource, per, count
end

local function inside(r, x, y)
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function Tab:prerender()
    local q = self.search:getText()
    if q ~= self.query then
        self.query = q
        self:refresh()
    end
    local nSel = self.sel:count()
    for _, b in ipairs(self.batchBtns) do b:setUsable(nSel > 0) end
    self.clearBtn:setVisible(nSel > 0)
    self.resetZoneBtn:setUsable(self.zone ~= nil and C.draft ~= nil and C.draft.zones[self.zone] ~= nil)
    -- 長條與圖例懸停：列出每個來源的完整名稱與占比（長條上的小區段放不下字）
    local mx, my = self:getMouseX(), self:getMouseY()
    local hover = self.compRect and inside(self.compRect, mx, my) and self:isMouseOver()
    W.tip(self, hover and self.srcTip or nil)
    W.card(self, 0, 0, self.lw, self.height)
    W.card(self, self.rx, 0, self.rw, self.height)
    U.text(self, T("ColZones"), IN, IN, "text")
end

function Tab:render()
    if not (C.data and self.zone) then return end
    local FH = U.fontH()
    local ix, iw = self.ix, self.iw
    local tm = getTextManager()
    local title = U.zoneLabel(self.zone)
    local tw = tm:MeasureStringX(UIFont.Medium, title)
    U.text(self, title, ix, IN, "text", UIFont.Medium)
    local key = self.zone
    local aliases = C.data.base.zones[self.zone].aliases
    if #aliases > 0 then key = key .. "   " .. T("Aliases", table.concat(aliases, ", ")) end
    U.text(self, U.fit(key, self.resetZoneBtn:getX() - ix - tw - 28), ix + tw + 14,
        IN + math.floor((U.fontH(UIFont.Medium) - FH) / 2), "textMuted")

    for i, p in ipairs(Tab.PARAMS) do
        local x = ix + (i - 1) * (self.cw + GAP)
        local v = C.paramOf(self.zone, p.key)
        local label = T(p.label)
        U.text(self, label, x, self.paramY, "textMuted")
        U.text(self, v and (U.num(v * p.scale) .. "%") or "-", x + tm:MeasureStringX(UIFont.Small, label) + 8, self.paramY, "text")
    end
    -- 沙盒「車輛產生率」再乘上每格生成機率（IsoChunk.java:981-987）；標籤沿用原版沙盒翻譯
    local rate = SandboxVars and SandboxVars.CarSpawnRate or 4
    local rateLabel = getTextOrNull("Sandbox_CarSpawnRate_option" .. tostring(rate)) or tostring(rate)
    local noteY = self.noteY
    for i, line in ipairs(U.wrap(T("SandboxNote", rateLabel), iw)) do
        if i > 2 then break end
        U.text(self, line, ix, noteY, "textFaint")
        noteY = noteY + FH + 2
    end
    self:drawComposition(ix, iw)

    U.text(self, T("SelectedCount", tostring(self.sel:count())), ix, self.batchY + math.floor((W.ctrlH() - FH) / 2), "text")
    local colW = math.floor((iw - CHK - ARROW) / 5)
    local hx = ix + CHK
    W.checkbox(self, ix - 4 + 12, self.headerY + math.floor((FH - 16) / 2), self.sel:state(self.order))
    U.text(self, T("ColVehicle"), hx, self.headerY, "textFaint")
    U.text(self, T("ColSource"), hx + colW * 2, self.headerY, "textFaint")
    U.textRight(self, T("ColWeight"), hx + colW * 4 - 8, self.headerY, "textFaint")
    U.textRight(self, T("ColShare"), hx + colW * 5 - 8, self.headerY, "textFaint")
end

-- 來源組成：灰階分段（有空間才寫字）＋下方圖例列出每個來源；點區段或圖例＝選取該來源
function Tab:drawComposition(ix, iw)
    local FH = U.fontH()
    local tm = getTextManager()
    local total, bySource, _, count = zoneShares(self.zone)
    U.text(self, T("Composition"), ix, self.barY - FH - 4, "textMuted")
    U.fill(self, ix, self.barY, iw, self.barH, { r = 1, g = 1, b = 1, a = 0.05 }, "pill")
    self.srcRects = {}
    self.compRect = { x = ix, y = self.barY, w = iw, h = self.legendY + self.legendH - self.barY }
    if total <= 0 then
        U.text(self, T("ZoneEmpty"), ix + 10, self.barY + math.floor((self.barH - FH) / 2), "textMuted")
        self.srcTip = nil
        return
    end
    local srcs = M.sortedKeys(bySource)
    M.sortSafe(srcs, function(a, b) return bySource[a] > bySource[b] end)
    local tip = {}
    local x = ix
    for i, src in ipairs(srcs) do
        local w = math.floor(iw * bySource[src] / total)
        if i == #srcs then w = ix + iw - x end
        local g = SHADE[math.min(i, #SHADE)]
        U.fill(self, x, self.barY, w, self.barH, { r = g, g = g, b = g, a = 1 }, "rect")
        local label = U.packName(src) .. "  " .. U.pct(bySource[src] / total * 100)
        if w > tm:MeasureStringX(UIFont.Small, label) + 16 then
            U.text(self, label, x + 8, self.barY + math.floor((self.barH - FH) / 2), "text")
        end
        self.srcRects[#self.srcRects + 1] = { x = x, y = self.barY, w = w, h = self.barH, src = src }
        tip[#tip + 1] = T("LegendLine", U.packName(src), U.pct(bySource[src] / total * 100), tostring(count[src]))
        x = x + w
    end
    -- 圖例：色塊＋名稱＋占比，最多兩列；放不下的收成「還有 N 個來源」（懸停提示仍列出全部）
    local moreW = tm:MeasureStringX(UIFont.Small, T("LegendMore", "99")) + 8
    local lx, line, placed = ix, 1, 0
    for i, src in ipairs(srcs) do
        local label = U.packName(src) .. "  " .. U.pct(bySource[src] / total * 100)
        local w = 14 + tm:MeasureStringX(UIFont.Small, label) + 18
        local reserve = (i < #srcs and line == 2) and moreW or 0
        if lx > ix and lx + w + reserve > ix + iw then
            if line == 2 then break end
            line, lx = 2, ix
        end
        if line == 2 and i < #srcs and lx > ix and lx + w + moreW > ix + iw then break end
        local ly = self.legendY + (line - 1) * (FH + 6)
        local g = SHADE[math.min(i, #SHADE)]
        U.fill(self, lx, ly + math.floor((FH - 10) / 2), 10, 10, { r = g, g = g, b = g, a = 1 }, "rect")
        U.text(self, label, lx + 14, ly, "text")
        self.srcRects[#self.srcRects + 1] = { x = lx, y = ly, w = w - 18, h = FH, src = src }
        lx = lx + w
        placed = i
    end
    if placed < #srcs then
        U.text(self, T("LegendMore", tostring(#srcs - placed)), lx, self.legendY + (line - 1) * (FH + 6), "textMuted")
    end
    tip[#tip + 1] = T("LegendHint")
    self.srcTip = table.concat(tip, " <LINE> ")
end

function Tab.drawZoneRow(list, y, item)
    local d = item.item
    local fh = U.fontH()
    if d.header then
        U.text(list, item.text, 10, y + math.floor((list.itemheight - fh) / 2) + 2, "textFaint")
        return y + list.itemheight
    end
    local w = W.rowBg(list, y, item, d.zone == list.tab.zone)
    local n = 0
    local eff = C.effective()
    if eff and eff[d.zone] then
        for _ in pairs(eff[d.zone].vehicles) do n = n + 1 end
    end
    local tm = getTextManager()
    local countText = tostring(n)
    local right = w - 12 - tm:MeasureStringX(UIFont.Small, countText)
    U.textRight(list, countText, w - 12, y + math.floor((list.itemheight - fh) / 2), "textMuted")
    -- 已修改：中性色徽章＋文字（設計文件 5.1 第 3 條），不用琥珀色塊
    local dz = C.draft.zones[d.zone]
    if dz ~= nil and M.diff(C.data.config.zones[d.zone] or {}, dz)[1] ~= nil then
        local bw = tm:MeasureStringX(UIFont.Small, T("Changed")) + 16
        right = right - 8 - bw
        W.badge(list, T("Changed"), right, y + math.floor((list.itemheight - 20) / 2), "textMuted")
    end
    U.text(list, U.fit(U.zoneLabel(d.zone), right - 28), 20, y + math.floor((list.itemheight - fh) / 2), "text")
    return y + list.itemheight
end

function Tab.drawVehicleRow(list, y, item)
    local tab = list.tab
    local full = item.item.full
    local v = C.data.catalog[full]
    local fh = U.fontH()
    local on = tab.sel:has(full)
    local w = W.rowBg(list, y, item, on)
    W.checkbox(list, 12, y + math.floor((list.itemheight - 16) / 2), on)
    local total, _, per = zoneShares(tab.zone)
    local weight = C.weightOf(tab.zone, full)
    local share = per[full] and total > 0 and per[full] / total * 100 or 0
    local colW = math.floor((w - CHK - ARROW) / 5)
    local x = 40
    local mid = y + math.floor((list.itemheight - fh) / 2)
    U.text(list, U.fit(v.display, colW * 2 - 12), x, y + 6, per[full] and "text" or "textFaint")
    U.text(list, U.fit(full, colW * 2 - 12), x, y + fh + 8, "textMuted")
    U.text(list, U.fit(U.packName(v.source), colW - 8), x + colW * 2, mid, "text")
    -- 狀態：只離開這一區＝已移出；所有區域都停用＝已停用
    if not per[full] then W.badge(list, C.isEnabled(full) and T("MarkRemoved") or T("MarkDisabled"), x + colW * 3, mid - 2, "textMuted")
    elseif v.new then W.badge(list, T("BadgeNew"), x + colW * 3, mid - 2, "textMuted", "tag") end
    local m = C.multOf("sources", v.source) * C.multOf("vehicles", full)
    U.textRight(list, U.num(weight) .. (m ~= 1 and ("  x" .. U.num(m)) or ""), x + colW * 4 - 8, mid, "text")
    -- 占比：數字＋中性細長條（琥珀只給選取）
    U.textRight(list, U.pct(share), x + colW * 5 - 8, mid - 4, "text")
    U.fill(list, x + colW * 4 + 8, mid + fh - 1, colW - 16, 3, { r = 1, g = 1, b = 1, a = 0.08 }, "rect")
    U.fill(list, x + colW * 4 + 8, mid + fh - 1, math.floor((colW - 16) * math.min(1, share / 100)), 3, { r = 1, g = 1, b = 1, a = 0.45 }, "rect")
    if not W.icon(list, "chevronRight", w - 30, y + math.floor((list.itemheight - 16) / 2), 16, "textMuted") then
        U.textRight(list, ">", w - 14, mid, "textMuted")
    end
    return y + list.itemheight
end
