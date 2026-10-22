-- 「補車」分頁（已探索停車區補車，伺服器 MVSC_Respawn）：開關、門檻（現實小時）、補到原版平均的比例、安全屋外圍，
-- 和其他分頁一樣改的是草稿、按「套用變更」才生效。下半部是伺服器在快照裡回報的統計（不含玩家足跡）。
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "MinidoracatVehicleSpawnControl/MVSC_Widgets"

local M = MinidoracatVehicleSpawnControl
local C, U, W = M.Client, M.UI, M.W
local T = U.T
local IN = 12
local STEP_W = 240

MVSC_RespawnTab = ISPanel:derive("MVSC_RespawnTab")
local Tab = MVSC_RespawnTab

function Tab:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    return o
end

-- 一天以內每次 1 小時，之後每次 1 天
local function stepHours(v, dir)
    v = v or M.RESPAWN_DEFAULTS.unseenHours
    if dir > 0 then return v < 24 and v + 1 or v + 24 end
    return v <= 24 and v - 1 or v - 24
end

-- 一般停車格每個車位有車的機率（照目前草稿與沙盒「車輛數量」）：說明 100% 是原版平均、不是每格補滿
local function stallPercent()
    local rate = C.data and C.draft and C.data.base.zones.parkingstall and C.paramOf("parkingstall", "spawnRate") or nil
    return U.num(math.floor(M.stallChance(rate, SandboxVars and SandboxVars.CarSpawnRate) * 100 + 0.5)) .. "%" -- 翻譯不放裸 %
end

Tab.ROWS = {
    { key = "unseenHours", label = "RespawnHours", prompt = "RespawnHoursPrompt", step = stepHours,
        format = function(v) return T("HoursValue", U.num(v or 0)) end,
        tip = function() return T("RespawnHoursTip", U.num(C.respawnOf("unseenHours"))) end },
    { key = "density", label = "RespawnDensity", prompt = "RespawnDensityPrompt",
        step = function(v, dir) return (v or 100) + dir * 10 end,
        format = function(v) return U.num(v or 0) .. "%" end,
        tip = function() return T("RespawnDensityTip", stallPercent()) end },
    { key = "safehouseMargin", label = "RespawnMargin", prompt = "RespawnMarginPrompt",
        step = function(v, dir) return (v or 0) + dir * 5 end,
        format = function(v) return T("TilesValue", U.num(v or 0)) end,
        tip = function() return T("RespawnMarginTip") end },
}

-- 版面由上往下累加，避免字級不同時重疊
function Tab:createChildren()
    local FH, FM = U.fontH(), U.fontH(UIFont.Medium)
    local ch = W.ctrlH()
    local tm = getTextManager()
    local y = IN
    local L = {}
    L.head = y; y = y + math.max(FM, ch) + 8
    L.intro = y; y = y + (FH + 2) * 2 + IN -- 說明最多兩行
    local labelW = 0
    for _, r in ipairs(Tab.ROWS) do labelW = math.max(labelW, tm:MeasureStringX(UIFont.Small, T(r.label))) end
    self.labelW = labelW + 24
    self.steppers = {}
    L.rows = {}
    for i, r in ipairs(Tab.ROWS) do
        L.rows[i] = y
        local row = r
        self.steppers[i] = W.stepper(self, IN + self.labelW, y, STEP_W, ch, {
            get = function() return C.data and C.respawnOf(row.key) or nil end,
            set = function(v) if C.draft then C.setRespawn(row.key, v) end end,
            step = row.step, format = row.format, title = T(row.label), prompt = T(row.prompt) })
        y = y + ch + 10
    end
    L.hint = y; y = y + FH + IN * 2
    L.stats = y; y = y + (FH + 6) * 4 + 8
    L.listLabel = y; y = y + FH + 8
    L.list = y
    self.L = L
    local bw = 130
    self.onBtn = W.button(self, self.width - IN - bw, IN, bw, ch, T("RespawnOn"), self, Tab.onToggle, "secondary")
    self.onBtn.mode = true
    self.offBtn = W.button(self, self.width - IN - bw * 2 - W.PAD, IN, bw, ch, T("RespawnOff"), self, Tab.onToggle, "secondary")
    self.offBtn.mode = false
    W.button(self, self.width - IN - 220, L.stats - 4, 220, ch, T("Reload"), self, Tab.onReload, "secondary", "reload")
    self.recent = W.list(self, IN - 4, L.list, self.width - IN * 2 + 8, self.height - L.list - IN, FH + 12, Tab.drawRecent)
    self:refresh()
end

function Tab:onToggle(button)
    if C.draft then C.setRespawn("enabled", button.mode) end
end

function Tab:onReload() C.request() end

function Tab:refresh()
    if not self.recent then return end
    self.recent:clear()
    local r = C.data and C.data.respawn
    for _, e in ipairs(r and r.recent or {}) do self.recent:addItem(tostring(e.zone), e) end
end

-- 滑過一列的標籤就顯示那一列的說明（門檻是現實時間、100% 是原版平均）；滑過數值時由數值按鈕自己的提示顯示同一段
function Tab:respawnRow(mx, my)
    local ch = W.ctrlH()
    for i, y in ipairs(self.L.rows) do
        if my >= y and my < y + ch and mx >= IN and mx < IN + self.labelW then return i end
    end
end

function Tab:prerender()
    W.card(self, 0, 0, self.width, self.height)
    local on = C.data ~= nil and C.draft ~= nil and C.respawnOf("enabled") == true
    self.onBtn.active = on
    self.offBtn.active = not on
    self.onBtn:setUsable(C.draft ~= nil)
    self.offBtn:setUsable(C.draft ~= nil)
    for i, s in ipairs(self.steppers) do s.opts.tip = Tab.ROWS[i].tip() end
    local row = self:isMouseOver() and self:respawnRow(self:getMouseX(), self:getMouseY()) or nil
    W.tip(self, row and Tab.ROWS[row].tip() or nil)
end

function Tab:render()
    local L = self.L
    local FH = U.fontH()
    local x = IN
    if W.icon(self, "carSedan", x, L.head + 2, 20, "text") then x = x + 28 end
    U.text(self, T("RespawnTitle"), x, L.head, "text", UIFont.Medium)
    local intro = U.wrap(T("RespawnIntro"), self.width - IN * 2)
    for i = 1, math.min(2, #intro) do U.text(self, intro[i], IN, L.intro + (i - 1) * (FH + 2), "textMuted") end
    local ch = W.ctrlH()
    for i, r in ipairs(Tab.ROWS) do
        U.text(self, T(r.label), IN, L.rows[i] + math.floor((ch - FH) / 2), "text")
    end
    U.text(self, U.fit(T("RespawnHint"), self.width - IN * 2), IN, L.hint, "textFaint")
    self:drawStats()
    U.text(self, T("RespawnRecent"), IN, L.listLabel, "text")
    if #self.recent.items == 0 then U.text(self, T("RespawnNone"), IN + 8, L.list + 8, "textFaint") end
end

-- 伺服器目前的狀態（不是草稿）：套用後重新載入才會更新
function Tab:drawStats()
    local L = self.L
    local FH = U.fontH()
    local r = C.data and C.data.respawn
    local lines = {}
    local token = "textMuted"
    if not r then
        lines[1] = T("RespawnStateWaiting")
    elseif not r.indexOk then
        lines[1], token = T("RespawnStateBroken"), "errorText"
    elseif r.on then
        lines[1] = T("RespawnStateOn", U.num(r.placed or 0))
        local hours = math.floor((r.trackedFor or 0) / 3600)
        if hours < (r.unseenHours or 0) then lines[2] = T("RespawnTracking", U.num(hours), U.num(r.unseenHours))
        else lines[2] = T("RespawnTrackingDone", U.num(math.floor(hours / 24))) end
        local w = r.window or {}
        lines[3] = T("RespawnWindow", U.num(w.placed or 0))
        lines[4] = T("RespawnSkipped", U.num(w.near or 0), U.num(w.blocked or 0), U.num(w.protected or 0))
    else
        lines[1] = T("RespawnStateOff")
    end
    for i, s in ipairs(lines) do
        U.text(self, U.fit(s, self.width - IN * 2 - 240), IN, L.stats + (i - 1) * (FH + 6), i == 1 and token or "textMuted")
    end
end

function Tab.drawRecent(list, y, item)
    local e = item.item
    local w = W.rowBg(list, y, item, false)
    local fh = U.fontH()
    local ty = y + math.floor((list.itemheight - fh) / 2)
    U.text(list, U.fit(T("RespawnRow", U.zoneLabel(tostring(e.zone)), tostring(e.x) .. "," .. tostring(e.y)), w - 260), 16, ty, "text")
    U.text(list, "+" .. tostring(e.n), w - 230, ty, "accent")
    U.text(list, U.ago(e.atMs), w - 170, ty, "textMuted")
    return y + list.itemheight
end
