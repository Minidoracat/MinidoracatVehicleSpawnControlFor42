-- 「區域」分頁（設計 C2）：左＝分組區域卡片，右＝參數卡片（滑桿）、來源組成長條、車款表與批次操作。
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
    o.checked = {}
    return o
end

function Tab:createChildren()
    local FH = U.fontH()
    local ch = W.ctrlH()
    local lw = math.floor(self.width * 0.26)
    local rx = lw + PAD
    local rw = self.width - rx
    self.lw, self.rx, self.rw = lw, rx, rw
    local head = FH + IN * 2

    self.search = W.search(self, IN, head, lw - IN * 2, ch, T("SearchZone"))
    self.zoneList = W.list(self, IN - 4, head + ch + PAD, lw - IN * 2 + 8, self.height - head - ch - PAD - IN,
        FH + 12, Tab.drawZoneRow, self, Tab.onZone)
    self.zoneList.tab = self

    -- 參數卡片：四欄，標籤＋數值＋滑桿
    local ix, iw = rx + IN, rw - IN * 2
    self.paramY = head + U.fontH(UIFont.Medium) + 8
    local cw = math.floor((iw - PAD * 3) / 4)
    self.sliders = {}
    for i, p in ipairs(Tab.PARAMS) do
        local s = W.slider(self, ix + (i - 1) * (cw + PAD) - 6, self.paramY + FH + 6, cw + 12, 18, 0, p.max, p.step, self, Tab.onParam)
        s.param = p
        self.sliders[i] = s
    end
    self.noteY = self.paramY + FH + 30
    self.barY = self.noteY + FH * 2 + 14
    self.barH = 22

    local by = self.barY + self.barH + PAD * 2
    local labels = { { "Halve", Tab.onHalve }, { "Double", Tab.onDouble }, { "SetWeight", Tab.onSetWeight },
        { "DisableInZone", Tab.onDisableSel }, { "Reset", Tab.onReset, "reload" } }
    local bw = math.floor((iw - 150 - PAD * 4) / 5)
    self.batchBtns = {}
    for i, b in ipairs(labels) do
        self.batchBtns[i] = W.button(self, ix + 150 + (i - 1) * (bw + PAD), by, bw, ch, T(b[1]), self, b[2], "secondary", b[3])
    end
    self.batchY = by
    self.headerY = by + ch + PAD
    self.table = W.list(self, ix - 4, self.headerY + FH + 6, iw + 8, self.height - self.headerY - FH - 6 - IN,
        FH * 2 + 12, Tab.drawVehicleRow)
    self.table.tab = self
    self.table.onMouseDown = Tab.onTableMouseDown
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
        for _, z in ipairs(g.zones) do list:addItem(z, { zone = z }) end
    end
    list:setYScroll(keepY)
    if not self.zone or not C.data.base.zones[self.zone] then self.zone = C.data.base.zones.parkingstall and "parkingstall" or nil end
    self:rebuildTable()
end

-- 表格列：原始分布、草稿覆寫的聯集；停用的也列出（標示且 0%）
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
    M.sortSafe(rows, function(a, b)
        local wa, wb = C.weightOf(self.zone, a), C.weightOf(self.zone, b)
        if wa ~= wb then return wa > wb end
        return a < b
    end)
    for _, s in ipairs(rows) do t:addItem(s, { full = s }) end
    t:setYScroll(keepY)
    self:syncSliders()
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
    local out = {}
    for s, on in pairs(self.checked) do
        if on then out[#out + 1] = s end
    end
    return out
end

-- ---------------------------------------------------------------- 事件
function Tab:onZone(item)
    if item.header then return end
    self.zone = item.zone
    self.checked = {}
    self:rebuildTable()
end

function Tab:onParam(value, slider)
    if not self.zone then return end
    local p = slider.param
    local v = value / p.scale
    if p.scale ~= 1 then v = math.floor(v * 100 + 0.5) / 100 end
    C.setParam(self.zone, p.key, v)
end

-- 勾選欄只切換勾選；右側箭頭跳到「車輛」分頁；其他位置選取
function Tab.onTableMouseDown(list, x, y)
    local row = list:rowAt(x, y)
    if row < 1 or not list.items[row] then return true end
    local full = list.items[row].item.full
    local tab = list.tab
    if x < 36 then
        tab.checked[full] = not tab.checked[full]
    elseif x > list:getWidth() - 40 then
        if tab.panel then tab.panel:showVehicle(full) end
    else
        list.selected = row
    end
    return true
end

local function scale(tab, factor)
    for _, s in ipairs(tab:selected()) do C.setWeight(tab.zone, s, C.weightOf(tab.zone, s) * factor) end
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
            for _, s in ipairs(sel) do C.setWeight(tab.zone, s, w) end
        end })
end

function Tab:onDisableSel()
    for _, s in ipairs(self:selected()) do C.setWeight(self.zone, s, 0) end
end

function Tab:onReset()
    local sel = self:selected()
    if #sel == 0 then C.resetZone(self.zone) else C.resetZoneWeights(self.zone, sel) end
end

-- ---------------------------------------------------------------- 繪製
local function zoneShares(zone)
    local eff = C.effective()
    local z = eff and eff[zone]
    local total, bySource, per = 0, {}, {}
    if z then
        for s, def in pairs(z.vehicles) do
            total = total + def.spawnChance
            per[s] = def.spawnChance
            local src = C.data.catalog[s] and C.data.catalog[s].source or "?"
            bySource[src] = (bySource[src] or 0) + def.spawnChance
        end
    end
    return total, bySource, per
end

function Tab:prerender()
    local q = self.search:getText()
    if q ~= self.query then
        self.query = q
        self:refresh()
    end
    local nSel = #self:selected()
    for _, b in ipairs(self.batchBtns) do b:setUsable(nSel > 0 or b == self.batchBtns[5]) end
    W.card(self, 0, 0, self.lw, self.height)
    W.card(self, self.rx, 0, self.rw, self.height)
    U.text(self, T("ColZones"), IN, IN, "text")
end

function Tab:render()
    if not (C.data and self.zone) then return end
    local FH = U.fontH()
    local rx, rw = self.rx, self.rw
    local ix, iw = rx + IN, rw - IN * 2
    local tm = getTextManager()
    local title = U.zoneLabel(self.zone)
    U.text(self, title, ix, IN, "text", UIFont.Medium)
    local key = self.zone
    local aliases = C.data.base.zones[self.zone].aliases
    if #aliases > 0 then key = key .. "   " .. T("Aliases", table.concat(aliases, ", ")) end
    U.text(self, U.fit(key, iw - tm:MeasureStringX(UIFont.Medium, title) - 20), ix + tm:MeasureStringX(UIFont.Medium, title) + 14,
        IN + math.floor((U.fontH(UIFont.Medium) - FH) / 2), "textMuted")

    local cw = math.floor((iw - PAD * 3) / 4)
    for i, p in ipairs(Tab.PARAMS) do
        local x = ix + (i - 1) * (cw + PAD)
        local v = C.paramOf(self.zone, p.key)
        U.text(self, T(p.label), x, self.paramY, "textMuted")
        U.textRight(self, v and (U.num(v * p.scale) .. "%") or "-", x + cw, self.paramY, "text")
    end
    -- 沙盒「車輛產生率」再乘上每格生成機率（IsoChunk.java:981-987）；標籤沿用原版沙盒翻譯
    local rate = SandboxVars and SandboxVars.CarSpawnRate or 4
    local rateLabel = getTextOrNull("Sandbox_CarSpawnRate_option" .. tostring(rate)) or tostring(rate)
    U.text(self, U.fit(T("SandboxNote", rateLabel), iw), ix, self.noteY, "textFaint")

    -- 來源組成：灰階分段＋文字標籤（不靠顏色辨識）
    local total, bySource = zoneShares(self.zone)
    U.text(self, T("Composition"), ix, self.barY - FH - 4, "textMuted")
    U.fill(self, ix, self.barY, iw, self.barH, { r = 1, g = 1, b = 1, a = 0.05 }, "pill")
    if total > 0 then
        local srcs = M.sortedKeys(bySource)
        M.sortSafe(srcs, function(a, b) return bySource[a] > bySource[b] end)
        local x = ix
        local shade = { 0.46, 0.33, 0.25, 0.19 }
        for i, src in ipairs(srcs) do
            local w = math.floor(iw * bySource[src] / total)
            if i == #srcs then w = ix + iw - x end
            local g = shade[math.min(i, #shade)]
            U.fill(self, x, self.barY, w, self.barH, { r = g, g = g, b = g, a = 1 }, "rect")
            local name = src == M.VANILLA and T("Source_pz-vanilla") or src
            for _, v in pairs(C.data.catalog) do
                if v.source == src then name = v.sourceName or src break end
            end
            if w > 48 then U.text(self, U.fit(name .. "  " .. U.pct(bySource[src] / total * 100), w - 12), x + 8, self.barY + math.floor((self.barH - FH) / 2), "text") end
            x = x + w
        end
    else
        U.text(self, T("ZoneEmpty"), ix + 10, self.barY + math.floor((self.barH - FH) / 2), "textMuted")
    end

    U.text(self, T("SelectedCount", tostring(#self:selected())), ix, self.batchY + math.floor((W.ctrlH() - FH) / 2), "text")
    local colW = math.floor((iw - 36 - 40) / 5)
    local hx = ix + 36
    U.text(self, T("ColVehicle"), hx, self.headerY, "textFaint")
    U.text(self, T("ColSource"), hx + colW * 2, self.headerY, "textFaint")
    U.textRight(self, T("ColWeight"), hx + colW * 4 - 8, self.headerY, "textFaint")
    U.textRight(self, T("ColShare"), hx + colW * 5 - 8, self.headerY, "textFaint")
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
    local label = U.zoneLabel(d.zone)
    local dz = C.draft.zones[d.zone]
    local changed = dz ~= nil and M.diff(C.data.config.zones[d.zone] or {}, dz)[1] ~= nil
    U.text(list, U.fit(label, w - 80), 20, y + math.floor((list.itemheight - fh) / 2), "text")
    if changed then U.fill(list, w - 42, y + math.floor(list.itemheight / 2) - 3, 6, 6, "accent", "rect") end
    U.textRight(list, tostring(n), w - 12, y + math.floor((list.itemheight - fh) / 2), "textMuted")
    return y + list.itemheight
end

function Tab.drawVehicleRow(list, y, item)
    local tab = list.tab
    local full = item.item.full
    local v = C.data.catalog[full]
    local fh = U.fontH()
    local w = W.rowBg(list, y, item, list.selected == item.index)
    W.checkbox(list, 12, y + math.floor((list.itemheight - 16) / 2), tab.checked[full])
    local total, _, per = zoneShares(tab.zone)
    local weight = C.weightOf(tab.zone, full)
    local share = per[full] and total > 0 and per[full] / total * 100 or 0
    local colW = math.floor((w - 36 - 40) / 5)
    local x = 40
    local mid = y + math.floor((list.itemheight - fh) / 2)
    U.text(list, U.fit(v.display, colW * 2 - 12), x, y + 6, per[full] and "text" or "textFaint")
    U.text(list, U.fit(full, colW * 2 - 12), x, y + fh + 8, "textMuted")
    U.text(list, U.fit(v.sourceName or v.source, colW - 8), x + colW * 2, mid, "text")
    if not per[full] then W.badge(list, T("MarkDisabled"), x + colW * 3, mid - 2, "textMuted")
    elseif v.new then W.badge(list, T("BadgeNew"), x + colW * 3, mid - 2, "accent") end
    U.textRight(list, U.num(weight), x + colW * 4 - 8, mid, "text")
    -- 占比：數字＋細長條
    U.textRight(list, U.pct(share), x + colW * 5 - 8, mid - 4, "text")
    U.fill(list, x + colW * 4 + 8, mid + fh - 1, colW - 16, 3, { r = 1, g = 1, b = 1, a = 0.08 }, "rect")
    U.fill(list, x + colW * 4 + 8, mid + fh - 1, math.floor((colW - 16) * math.min(1, share / 100)), 3, "accent", "rect")
    if not W.icon(list, "chevronRight", w - 30, y + math.floor((list.itemheight - 16) / 2), 16, "textMuted") then
        U.textRight(list, ">", w - 14, mid, "textMuted")
    end
    return y + list.itemheight
end
