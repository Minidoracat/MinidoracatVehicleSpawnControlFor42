-- 「車輛生成控制」主視窗：自繪外殼（MVSC_Window）＋分頁列＋四個視圖＋底部狀態列。
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "MinidoracatVehicleSpawnControl/MVSC_Widgets"
require "MinidoracatVehicleSpawnControl/MVSC_VehicleTab"
require "MinidoracatVehicleSpawnControl/MVSC_ZoneTab"

local M = MinidoracatVehicleSpawnControl
local C, U, W = M.Client, M.UI, M.W
local T = U.T
local PAD = W.PAD
local IN = 12

-- ---------------------------------------------------------------- 設定檔同步
MVSC_SyncView = ISPanel:derive("MVSC_SyncView")
local Sync = MVSC_SyncView

function Sync:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    return o
end

-- 版面由上往下累加，避免字級不同時重疊
function Sync:createChildren()
    local FH, FM = U.fontH(), U.fontH(UIFont.Medium)
    local ch = W.ctrlH()
    local y = IN
    local L = {}
    L.head = y; y = y + FM + 6
    L.detail = y; y = y + FH + 4
    L.path = y; y = y + FH + 4
    L.hint = y; y = y + FH + IN * 2
    L.policyLabel = y; y = y + FH + 8
    L.policy = y; y = y + ch + IN * 2
    L.listLabel = y; y = y + FH + 8
    L.list = y
    self.L = L
    W.button(self, self.width - IN - 220, IN, 220, ch, T("Reload"), self, Sync.onReload, "secondary", "reload")
    local bw = 280
    self.keepBtn = W.button(self, IN, L.policy, bw, ch, T("NewKeep"), self, Sync.onPolicy, "secondary")
    self.keepBtn.mode = "keep"
    self.disableBtn = W.button(self, IN + bw + PAD, L.policy, bw, ch, T("NewDisable"), self, Sync.onPolicy, "secondary")
    self.disableBtn.mode = "disable"
    self.lines = W.list(self, IN - 4, L.list, self.width - IN * 2 + 8, self.height - L.list - IN, FH + 12, Sync.drawLine)
    self:refresh()
end

function Sync:refresh()
    if not C.data then return end
    local st = C.data.status or {}
    self.lines:clear()
    for _, e in ipairs(st.errors or {}) do self.lines:addItem(e, { kind = "error" }, e) end
    for _, w in ipairs(st.warnings or {}) do self.lines:addItem(w, { kind = "warning" }, w) end
    for _, s in ipairs(st.newVehicles or {}) do
        local v = C.data.catalog[s]
        self.lines:addItem(s, { kind = "new", name = v and v.display or s }, (v and v.display or s) .. " <LINE> " .. s)
    end
end

function Sync:onPolicy(button) C.setNewVehicles(button.mode) end
function Sync:onReload() C.request() end

function Sync:prerender()
    W.card(self, 0, 0, self.width, self.height)
    local mode = C.draft and C.draft.newVehicles or "keep"
    self.keepBtn.active = mode == "keep"
    self.disableBtn.active = mode == "disable"
end

function Sync:render()
    if not C.data then return end
    local L = self.L
    local st = C.data.status or {}
    local failed = st.ok == false
    local x = IN
    if W.icon(self, failed and "close" or "clipboardCheck", x, L.head + 2, 20, failed and "errorText" or "text") then x = x + 28 end
    U.text(self, failed and T("SyncFailed") or T("SyncOk"), x, L.head, failed and "errorText" or "text", UIFont.Medium)
    U.text(self, T("SyncDetail", tostring(st.revision or C.data.revision), U.sourceLabel(st.source), U.ago(st.checkedAt)), IN, L.detail, "textMuted")
    U.text(self, T("ConfigPath") .. "  Zomboid/Lua/MinidoracatVehicleSpawnControl/config.json", IN, L.path, "textMuted")
    U.text(self, U.fit(T("SyncHint"), self.width - IN * 2), IN, L.hint, "textFaint")
    U.text(self, T("NewPolicy"), IN, L.policyLabel, "text")
    U.text(self, T("SyncList"), IN, L.listLabel, "text")
    if #self.lines.items == 0 then U.text(self, T("SyncNothing"), IN + 8, L.list + 8, "textFaint") end
end

function Sync.drawLine(list, y, item)
    local d = item.item
    local w = W.rowBg(list, y, item, false)
    local fh = U.fontH()
    local mid = y + math.floor((list.itemheight - 20) / 2)
    local token = d.kind == "error" and "errorText" or "textMuted"
    local label = d.kind == "error" and T("LineError") or (d.kind == "warning" and T("LineWarning") or T("BadgeNew"))
    local bw = W.badge(list, label, 10, mid, token, d.kind == "new" and "tag" or nil)
    local text = d.kind == "new" and (d.name .. "  (" .. item.text .. ")") or item.text
    U.text(list, U.fit(text, w - bw - 30), 20 + bw, y + math.floor((list.itemheight - fh) / 2), "text")
    return y + list.itemheight
end

-- ---------------------------------------------------------------- 變更紀錄
MVSC_HistoryView = ISPanel:derive("MVSC_HistoryView")
local Hist = MVSC_HistoryView

function Hist:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    return o
end

function Hist:createChildren()
    local FH = U.fontH()
    local ch = W.ctrlH()
    self.list = W.list(self, IN - 4, IN * 2 + FH * 2, self.width - IN * 2 + 8, self.height - IN * 4 - FH * 2 - ch,
        FH + 18, Hist.drawRow)
    self.list.onMouseDown = function(list, x, y)
        local row = list:rowAt(x, y)
        if row > 0 then list.selected = row end
        return true
    end
    self.restoreBtn = W.button(self, IN, self.height - IN - ch, 280, ch, T("Restore"), self, Hist.onRestore, "secondary", "reload")
    self:refresh()
end

function Hist:refresh()
    if not C.data then return end
    self.list:clear()
    local h = C.data.history or {}
    for i = #h, 1, -1 do self.list:addItem(tostring(h[i].revision), h[i]) end
end

function Hist:selectedEntry()
    local row = self.list.items[self.list.selected]
    return row and row.item
end

function Hist:canRestore(e)
    return e ~= nil and C.data ~= nil and e.revision ~= C.data.revision and C.data.revision - e.revision < 10
end

function Hist:onRestore()
    local e = self:selectedEntry()
    if not self:canRestore(e) then return end
    W.dialog({ title = T("Restore"), message = T("ConfirmRestore", tostring(e.revision)), confirm = T("Restore"),
        onConfirm = function() C.restore(e.revision) end })
end

function Hist:prerender()
    W.card(self, 0, 0, self.width, self.height)
    self.restoreBtn:setUsable(self:canRestore(self:selectedEntry()))
end

function Hist:render()
    local FH = U.fontH()
    U.text(self, T("HistoryHint"), IN, IN, "textMuted")
    local x = IN + 18
    local hy = IN * 2 + FH
    U.text(self, T("ColRevision"), x, hy, "textFaint")
    U.text(self, T("ColWhen"), x + 170, hy, "textFaint")
    U.text(self, T("ColFrom"), x + 340, hy, "textFaint")
    U.text(self, T("ColWho"), x + 510, hy, "textFaint")
end

function Hist.drawRow(list, y, item)
    local e = item.item
    local w = W.rowBg(list, y, item, list.selected == item.index)
    local fh = U.fontH()
    local mid = y + math.floor((list.itemheight - fh) / 2)
    local x = 18
    U.text(list, "#" .. tostring(e.revision), x, mid, "text")
    if C.data and e.revision == C.data.revision then W.badge(list, T("Current"), x + 60, mid - 2, "textMuted") end
    U.text(list, U.ago(e.at), x + 170, mid, "textMuted")
    U.text(list, U.sourceLabel(e.source), x + 340, mid, "text")
    if e.user and e.user ~= "" then U.text(list, U.fit(e.user, w - x - 530), x + 510, mid, "textMuted") end
    return y + list.itemheight
end

-- ---------------------------------------------------------------- 主視窗
MVSC_Panel = MVSC_Window:derive("MVSC_Panel")
local P = MVSC_Panel

function P:new()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- 依字級等比放大：自動字級在 1440p 以上會變大（Core.java:3248-3271），固定尺寸會把按鈕與說明截斷
    local k = math.max(1, U.fontH() / 16)
    local w = math.min(sw - 40, math.floor(1280 * k))
    local h = math.min(sh - 40, math.floor(780 * k))
    local o = MVSC_Window.new(self, math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h, T("Title"))
    o.badge = T("AdminBadge")
    return o
end

function P:createChildren()
    MVSC_Window.createChildren(self)
    local FH = U.fontH()
    local ch = W.ctrlH()
    local tabsH = FH + 22
    self.tabs = W.tabs(self, 16, self.headerH, self.width - 32, tabsH, {
        { title = T("TabVehicles"), icon = "steeringwheel" },
        { title = T("TabZones"), icon = "layers" },
        { title = T("TabSync"), icon = "document" },
        { title = T("TabHistory"), icon = "clipboardCheck" },
    }, self, P.onTab)
    self.barH = ch + 24
    local vy = self.headerH + tabsH + PAD
    local vw, vh = self.width - 32, self.height - vy - self.barH
    self.vehicleTab = MVSC_VehicleTab:new(16, vy, vw, vh)
    self.zoneTab = MVSC_ZoneTab:new(16, vy, vw, vh)
    self.syncView = MVSC_SyncView:new(16, vy, vw, vh)
    self.historyView = MVSC_HistoryView:new(16, vy, vw, vh)
    self.zoneTab.panel = self
    self.views = { self.vehicleTab, self.zoneTab, self.syncView, self.historyView }
    for i, v in ipairs(self.views) do
        v:initialise()
        self:addChild(v)
        v:setVisible(i == 1)
    end

    local by = self.height - self.barH + math.floor((self.barH - ch) / 2)
    local bw = 170
    self.applyBtn = W.button(self, self.width - 16 - bw, by, bw, ch, T("Apply"), self, P.onApply, "primary")
    self.discardBtn = W.button(self, self.width - 16 - bw * 2 - PAD, by, bw, ch, T("Discard"), self, P.onDiscard, "secondary")
    self.changesBtn = W.button(self, math.floor(self.width / 2) - 130, by, 260, ch, "", self, P.onChanges, "secondary", "document")

    self.listener = function(event, args) self:onEvent(event, args) end
    C.on(self.listener)
    if C.data then self:onEvent("loaded") end
    C.request()
end

function P:onTab(index)
    for i, v in ipairs(self.views) do v:setVisible(i == index) end
    if index == 2 then self.zoneTab:rebuildTable() end
end

function P:showVehicle(full)
    self.tabs.active = 1
    self:onTab(1)
    self.vehicleTab:select(full)
end

function P:showTab(index)
    self.tabs.active = index
    self:onTab(index)
end

function P:onEvent(event, args)
    if event == "loaded" then
        self.vehicleTab:refresh()
        self.zoneTab:refresh()
        self.syncView:refresh()
        self.historyView:refresh()
    elseif event == "draft" then
        self.vehicleTab:onDraft()
        self.zoneTab:onDraft()
    elseif event == "status" then
        self.syncView:refresh()
    elseif event == "applyResult" then
        if args.stale then
            W.dialog({ title = T("StaleTitle"), message = T("StaleConfirm", tostring(args.revision)), confirm = T("Overwrite"),
                danger = true, onConfirm = function() C.apply(true) end })
        elseif not args.ok then
            W.dialog({ title = T("ApplyFailed"), message = "", lines = args.errors or {}, cancel = false })
        else
            self.flash = T("Applied", tostring(args.revision))
            self.flashUntil = getTimestampMs() + 6000
        end
    elseif event == "denied" then
        self.flash = T("Denied")
        self.flashUntil = getTimestampMs() + 8000
    end
end

function P:onApply()
    if C.hasChanges() then C.apply(false) end
end

-- 放棄會丟掉所有未套用的編輯且無法復原，先確認（WCAG 3.3.4）
function P:onDiscard()
    local n = #C.changes()
    if n == 0 then return end
    local panel = self
    W.dialog({ title = T("Discard"), message = T("ConfirmDiscard", tostring(n)), confirm = T("Discard"), danger = true,
        onConfirm = function()
            C.discard()
            panel.vehicleTab:rebuildZones()
            panel.zoneTab:rebuildTable()
        end })
end

function P:onChanges()
    local list = C.changes()
    if #list == 0 then return end
    W.dialog({ title = T("PendingTitle", tostring(#list)), message = T("PendingHint"), lines = list, cancel = false })
end

function P:prerender()
    MVSC_Window.prerender(self)
    local n = #C.changes()
    self.changesBtn:setTitle(T("PendingButton", tostring(n)))
    self.changesBtn:setUsable(n > 0)
    self.applyBtn:setUsable(n > 0 and C.data ~= nil)
    self.discardBtn:setUsable(n > 0)
    -- 底部狀態列：分隔線＋狀態圖示＋文字
    local by = self.height - self.barH
    U.fill(self, 1, by, self.width - 2, 1, { r = 1, g = 1, b = 1, a = 0.08 }, "rect")
    local FH = U.fontH()
    local y = by + math.floor((self.barH - FH) / 2)
    local text, token, icon
    if self.flash and getTimestampMs() < self.flashUntil then text, token, icon = self.flash, "text", "clipboardCheck"
    elseif C.loading or not C.data then text, token, icon = T("Loading"), "textMuted", "reload"
    elseif C.stale then text, token, icon = T("StaleNotice", tostring(C.stale)), "text", "reload"
    else
        local st = C.data.status or {}
        local bad = st.ok == false
        text = T(bad and "BarFileError" or "BarSynced", tostring(C.data.revision), U.sourceLabel(st.source), U.ago(st.checkedAt))
        token, icon = bad and "errorText" or "textMuted", bad and "close" or "clipboardCheck"
    end
    local x = 18
    if W.icon(self, icon, x, by + math.floor((self.barH - 16) / 2), 16, token) then x = x + 24 end
    U.text(self, U.fit(text, self.changesBtn:getX() - x - 16), x, y, token)
end

function P:render()
    if not C.data then
        U.text(self, T("Loading"), math.floor(self.width / 2) - 60, math.floor(self.height / 2), "textMuted", UIFont.Medium)
    end
end

function P:close()
    C.off(self.listener)
    self:removeFromUIManager()
    if MVSC_Panel.instance == self then MVSC_Panel.instance = nil end
end

function MVSC_Panel.toggle()
    if MVSC_Panel.instance then
        MVSC_Panel.instance:close()
        return
    end
    local p = MVSC_Panel:new()
    p:initialise()
    p:addToUIManager()
    MVSC_Panel.instance = p
end
