-- MinidoracatVehicleSpawnControl 現代化元件：全部畫在 MinidoracatUIFor42 的 Theme／Skin／Icons 上
-- （圓角 6px、pill、琥珀強調、單色圖示）。框架缺席時退回同值直角，功能不少一塊。
-- 與 Economy 的 ECWidgets 同一做法（元件由 consumer 自有）；第三個 MOD 需要時再提升進框架。
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "MinidoracatVehicleSpawnControl/MVSC_UI"

local M = MinidoracatVehicleSpawnControl
local U = M.UI
local W = {}
M.W = W

local FW = MinidoracatUI and MinidoracatUI.v1
local ICONS = FW and FW.API_REVISION and FW.API_REVISION >= 2 and FW.Icons or nil
local SKIN = FW and FW.API_REVISION and FW.API_REVISION >= 3 and FW.Skin or nil

W.PAD = 10
W.RADIUS_H = 28 -- 標準控制項高度

function W.icon(el, name, x, y, size, token)
    if not ICONS then return false end
    local c = type(token) == "table" and token or U.COL[token or "text"]
    return ICONS.draw(el, name, x, y, size or 16, c)
end

function W.ctrlH()
    return math.max(W.RADIUS_H, U.fontH() + 12)
end

-- 卡片：well 底＋細邊框（圓角）
function W.card(el, x, y, w, h)
    U.fill(el, x, y, w, h, "well")
    U.border(el, x, y, w, h, { r = 1, g = 1, b = 1, a = 0.08 })
end

-- 徽章：pill 形小標籤，一律「圖示或符號＋文字」，不只靠顏色
function W.badge(el, text, x, y, token)
    local tw = getTextManager():MeasureStringX(UIFont.Small, text)
    local h = 20
    local c = U.COL[token or "textMuted"]
    U.fill(el, x, y, tw + 16, h, { r = c.r, g = c.g, b = c.b, a = 0.14 }, "pill")
    U.border(el, x, y, tw + 16, h, { r = c.r, g = c.g, b = c.b, a = 0.55 }, "pill")
    U.text(el, text, x + 8, y + math.floor((h - U.fontH()) / 2), token or "textMuted")
    return tw + 16
end

-- ---------------------------------------------------------------- 按鈕
-- style: "primary"（琥珀填色，每個視圖一顆）｜"secondary"（well＋框）｜"ghost"（無框，懸停出底）｜"danger"（紅框紅字，只給破壞性操作）
MVSC_Button = ISButton:derive("MVSC_Button")
local Button = MVSC_Button

function W.button(parent, x, y, w, h, title, target, fn, style, icon)
    local b = Button:new(x, y, w, h, title, target, fn)
    b.style = style or "secondary"
    b.iconName = icon
    b:initialise()
    b:instantiate()
    parent:addChild(b)
    return b
end

function Button:prerender() end

function Button:render()
    local w, h = self.width, self.height
    local hover = self.enable and self:isMouseOver()
    local s = self.style
    local textToken = "text"
    if not self.enable then
        U.fill(self, 0, 0, w, h, { r = 1, g = 1, b = 1, a = 0.03 })
        U.border(self, 0, 0, w, h, { r = 1, g = 1, b = 1, a = 0.10 })
        textToken = "textFaint"
    elseif s == "primary" then
        local a = U.COL.accent
        local k = self.pressed and 0.85 or (hover and 1.1 or 1)
        U.fill(self, 0, 0, w, h, { r = math.min(1, a.r * k), g = math.min(1, a.g * k), b = math.min(1, a.b * k), a = 1 })
        textToken = "onAccent"
    elseif s == "danger" then
        local e = U.COL.errorText
        if hover then U.fill(self, 0, 0, w, h, { r = e.r, g = e.g, b = e.b, a = 0.12 }) end
        U.border(self, 0, 0, w, h, e)
        textToken = "errorText"
    elseif s == "ghost" then
        if hover or self.active then U.fill(self, 0, 0, w, h, self.active and "selected" or "hover") end
        textToken = self.active and "text" or "textMuted"
    else
        U.fill(self, 0, 0, w, h, hover and { r = 1, g = 1, b = 1, a = 0.10 } or { r = 1, g = 1, b = 1, a = 0.05 })
        U.border(self, 0, 0, w, h, self.active and "accent" or { r = 1, g = 1, b = 1, a = 0.16 })
    end
    local title = self.title or ""
    local tw = getTextManager():MeasureStringX(UIFont.Small, title)
    local iconSize = 16
    local hasIcon = self.iconName and ICONS
    local total = tw + (hasIcon and (iconSize + (tw > 0 and 6 or 0)) or 0)
    local x = math.floor((w - total) / 2)
    local fh = U.fontH()
    if hasIcon then
        W.icon(self, self.iconName, x, math.floor((h - iconSize) / 2), iconSize, textToken)
        x = x + iconSize + (tw > 0 and 6 or 0)
    end
    if tw > 0 then
        local fit = U.fit(title, w - 12 - (hasIcon and iconSize + 6 or 0))
        U.text(self, fit, x, math.floor((h - fh) / 2), textToken)
    end
end

function Button:setUsable(on) self.enable = on end

-- ---------------------------------------------------------------- 分頁列
-- 文字＋圖示，選中分頁下緣琥珀色 3px 底線
MVSC_Tabs = ISPanel:derive("MVSC_Tabs")
local Tabs = MVSC_Tabs

function W.tabs(parent, x, y, w, h, items, target, onSelect)
    local t = Tabs:new(x, y, w, h)
    t.items, t.target, t.onSelect, t.active = items, target, onSelect, 1
    t.background = false
    t:initialise()
    t:instantiate()
    parent:addChild(t)
    return t
end

function Tabs:layout()
    local x = 0
    self.rects = {}
    for i, it in ipairs(self.items) do
        local tw = getTextManager():MeasureStringX(UIFont.Small, it.title) + (it.icon and 22 or 0) + 28
        self.rects[i] = { x = x, w = tw }
        x = x + tw + 4
    end
end

function Tabs:onMouseDown(x)
    self:layout()
    for i, r in ipairs(self.rects) do
        if x >= r.x and x < r.x + r.w then
            self.active = i
            if self.onSelect then self.onSelect(self.target, i, self.items[i]) end
            return true
        end
    end
    return true
end

function Tabs:render()
    self:layout()
    local h = self.height
    local fh = U.fontH()
    U.fill(self, 0, h - 1, self.width, 1, { r = 1, g = 1, b = 1, a = 0.08 }, "rect")
    local mx, my = self:getMouseX(), self:getMouseY()
    for i, r in ipairs(self.rects) do
        local it = self.items[i]
        local on = i == self.active
        local hover = my >= 0 and my < h and mx >= r.x and mx < r.x + r.w
        if hover and not on then U.fill(self, r.x, 2, r.w, h - 6, "hover") end
        local token = on and "text" or "textMuted"
        local x = r.x + 14
        if it.icon then
            W.icon(self, it.icon, x, math.floor((h - 16) / 2) - 1, 16, on and "accent" or "textMuted")
            x = x + 22
        end
        U.text(self, it.title, x, math.floor((h - fh) / 2) - 1, token)
        if on then U.fill(self, r.x + 8, h - 3, r.w - 16, 3, "accent", "rect") end
    end
end

-- ---------------------------------------------------------------- 滑桿（Skin.slider 畫、這裡管拖曳）
MVSC_Slider = ISPanel:derive("MVSC_Slider")
local Slider = MVSC_Slider

function W.slider(parent, x, y, w, h, min, max, step, target, onChange)
    local s = Slider:new(x, y, w, h)
    s.min, s.max, s.step, s.value = min, max, step or 1, min
    s.target, s.onChange = target, onChange
    s.background = false
    s:initialise()
    s:instantiate()
    parent:addChild(s)
    return s
end

function Slider:setRange(min, max, step) self.min, self.max, self.step = min, max, step or self.step end

function Slider:setValue(v)
    self.value = math.max(self.min, math.min(self.max, v or self.min))
end

function Slider:valueAt(x)
    local r = math.max(0, math.min(1, (x - 6) / math.max(1, self.width - 12)))
    local v = self.min + (self.max - self.min) * r
    v = math.floor(v / self.step + 0.5) * self.step
    return math.max(self.min, math.min(self.max, v))
end

-- 不能叫 update：ISUIElement:update() 每幀由引擎無參數呼叫（E2E panel-mp 實踩，每幀報錯）
function Slider:dragTo(x)
    local v = self:valueAt(x)
    if v ~= self.value then
        self.value = v
        if self.onChange then self.onChange(self.target, v, self) end
    end
end

function Slider:onMouseDown(x) self.dragInside = true; self:dragTo(x); return true end
function Slider:onMouseMove() if self.dragInside then self:dragTo(self:getMouseX()) end return true end
function Slider:onMouseMoveOutside() if self.dragInside then self:dragTo(self:getMouseX()) end return true end
function Slider:onMouseUp() self.dragInside = false; return true end
function Slider:onMouseUpOutside() self.dragInside = false; return true end

function Slider:render()
    local ratio = (self.value - self.min) / math.max(0.0001, self.max - self.min)
    local a = U.COL.accent
    local colors = { track = { r = 1, g = 1, b = 1, a = 0.12 }, fill = { r = a.r, g = a.g, b = a.b, a = 1 },
        knob = { r = 1, g = 1, b = 1, a = 1 }, border = { r = 0, g = 0, b = 0, a = 0 } }
    local drawn = SKIN and SKIN.slider(self, 6, 0, self.width - 12, self.height, ratio, colors)
    if not drawn then
        local y = math.floor(self.height / 2) - 2
        self:drawRect(6, y, self.width - 12, 4, 0.12, 1, 1, 1)
        self:drawRect(6, y, math.floor((self.width - 12) * ratio), 4, 1, a.r, a.g, a.b)
    end
end

-- ---------------------------------------------------------------- 勾選框（在清單列裡直接畫）
function W.checkbox(el, x, y, on)
    local s = 16
    if on then
        U.fill(el, x, y, s, s, "accent")
        U.fill(el, x + 4, y + 7, 3, 3, "onAccent", "rect")
        U.fill(el, x + 6, y + 9, 3, 3, "onAccent", "rect")
        U.fill(el, x + 8, y + 7, 3, 3, "onAccent", "rect")
        U.fill(el, x + 10, y + 5, 3, 3, "onAccent", "rect")
    else
        U.border(el, x, y, s, s, { r = 1, g = 1, b = 1, a = 0.35 })
    end
end

-- 勾選列：勾選框＋文字，整列可點
MVSC_Check = ISPanel:derive("MVSC_Check")
local Check = MVSC_Check

function W.check(parent, x, y, w, label, target, onChange)
    local c = Check:new(x, y, w, math.max(22, U.fontH() + 6))
    c.label, c.target, c.onChange, c.checked = label, target, onChange, false
    c.background = false
    c:initialise()
    c:instantiate()
    parent:addChild(c)
    return c
end

function Check:onMouseDown()
    self.checked = not self.checked
    if self.onChange then self.onChange(self.target, self.checked, self) end
    return true
end

function Check:render()
    if self:isMouseOver() then U.fill(self, 0, 0, self.width, self.height, "hover") end
    W.checkbox(self, 4, math.floor((self.height - 16) / 2), self.checked)
    U.text(self, U.fit(self.label or "", self.width - 32), 28, math.floor((self.height - U.fontH()) / 2), "text")
end

-- ---------------------------------------------------------------- 搜尋框：圓角底＋放大鏡圖示＋提示字
MVSC_Search = ISPanel:derive("MVSC_Search")
local Search = MVSC_Search

function W.search(parent, x, y, w, h, placeholder)
    local s = Search:new(x, y, w, h)
    s.placeholder = placeholder
    s.background = false
    s:initialise()
    s:instantiate()
    parent:addChild(s)
    return s
end

function Search:createChildren()
    local fh = U.fontH()
    self.entry = ISTextEntryBox:new("", 30, math.floor((self.height - fh - 6) / 2), self.width - 38, fh + 6)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self:addChild(self.entry)
end

function Search:getText() return self.entry:getText() end

function Search:prerender()
    local focused = self.entry:isFocused()
    U.fill(self, 0, 0, self.width, self.height, { r = 1, g = 1, b = 1, a = 0.05 })
    U.border(self, 0, 0, self.width, self.height, focused and "accent" or { r = 1, g = 1, b = 1, a = 0.14 })
    if not W.icon(self, "search", 9, math.floor((self.height - 16) / 2), 16, "textMuted") then
        U.text(self, "?", 11, math.floor((self.height - U.fontH()) / 2), "textMuted")
    end
    if self.entry:getText() == "" and not focused then
        U.text(self, self.placeholder or "", 36, math.floor((self.height - U.fontH()) / 2), "textFaint")
    end
end

-- ---------------------------------------------------------------- 清單：原版 ISScrollingListBox 去框、列用圓角選取底
function W.list(parent, x, y, w, h, rowH, drawFn, target, onClick)
    local l = ISScrollingListBox:new(x, y, w, h)
    l:initialise()
    l:instantiate()
    l.itemheight = rowH
    l.drawBorder = false
    l.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    l.doDrawItem = drawFn
    if target then l:setOnMouseDownFunction(target, onClick) end
    parent:addChild(l)
    return l
end

-- 列底：選中＝selected 圓角底＋左側琥珀 3px；懸停＝hover
function W.rowBg(list, y, item, selected)
    local w = list:getWidth() - (list.vscroll and list.vscroll:isVisible() and 14 or 0)
    local h = list.itemheight
    if selected then
        U.fill(list, 4, y + 2, w - 8, h - 4, "selected")
        U.fill(list, 4, y + 6, 3, h - 12, "accent", "rect")
    elseif list.mouseoverselected == item.index then
        U.fill(list, 4, y + 2, w - 8, h - 4, "hover")
    end
    return w
end

-- ---------------------------------------------------------------- 對話框（確認／輸入數字／訊息清單）
MVSC_Dialog = ISPanel:derive("MVSC_Dialog")
local Dialog = MVSC_Dialog

-- opts = { title, message, lines = {...}, input = "預設值", confirm = "按鈕字", danger = bool, cancel = "按鈕字"|false, onConfirm = fn(value) }
function W.dialog(opts)
    local fh = U.fontH()
    local w = 460
    local lines = {}
    for _, l in ipairs(U.wrap(opts.message or "", w - 40)) do lines[#lines + 1] = l end
    local listH = opts.lines and math.min(#opts.lines, 12) * (fh + 4) + 12 or 0
    local h = 56 + #lines * (fh + 4) + listH + (opts.input and 44 or 0) + 60
    local d = Dialog:new(math.floor((getCore():getScreenWidth() - w) / 2), math.floor((getCore():getScreenHeight() - h) / 2), w, h)
    d.opts, d.msgLines = opts, lines
    d.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    d.moveWithMouse = true
    d:initialise()
    d:addToUIManager()
    d:setAlwaysOnTop(true)
    return d
end

function Dialog:createChildren()
    local o = self.opts
    local fh = U.fontH()
    local bh = W.ctrlH()
    local y = self.height - bh - 16
    if o.input then
        self.entry = ISTextEntryBox:new(tostring(o.input), 20, y - bh - 12, self.width - 40, bh)
        self.entry:initialise()
        self.entry:instantiate()
        self.entry:setOnlyNumbers(true)
        self:addChild(self.entry)
    end
    local bw = 140
    local x = self.width - 20 - bw
    W.button(self, x, y, bw, bh, o.confirm or U.T("Ok"), self, Dialog.onConfirm, o.danger and "danger" or "primary")
    if o.cancel ~= false then
        W.button(self, x - bw - 10, y, bw, bh, o.cancel or U.T("Cancel"), self, Dialog.onCancel, "secondary")
    end
    self.listY = 50 + #self.msgLines * (fh + 4)
end

function Dialog:onConfirm()
    local v = self.entry and self.entry:getText() or nil
    self:removeFromUIManager()
    if self.opts.onConfirm then self.opts.onConfirm(v) end
end

function Dialog:onCancel() self:removeFromUIManager() end

function Dialog:prerender()
    U.fill(self, 0, 0, self.width, self.height, { r = 0.09, g = 0.09, b = 0.10, a = 0.98 })
    U.border(self, 0, 0, self.width, self.height, { r = 1, g = 1, b = 1, a = 0.14 })
    local fh = U.fontH()
    U.text(self, self.opts.title or "", 20, 16, "text", UIFont.Medium)
    local y = 50
    for _, l in ipairs(self.msgLines) do
        U.text(self, l, 20, y, "textMuted")
        y = y + fh + 4
    end
    if self.opts.lines then
        local n = math.min(#self.opts.lines, 12)
        W.card(self, 20, y + 4, self.width - 40, n * (fh + 4) + 8)
        for i = 1, n do
            U.text(self, U.fit(self.opts.lines[i], self.width - 60), 30, y + 8 + (i - 1) * (fh + 4), "text")
        end
    end
end

-- ---------------------------------------------------------------- 彈出選單（取代原版右鍵選單：分組、可捲動）
MVSC_Picker = ISPanel:derive("MVSC_Picker")
local Picker = MVSC_Picker

-- groups = { { title = "...", items = { { label, value } } } }
function W.picker(x, y, groups, target, onPick)
    local fh = U.fontH()
    local rows = {}
    for _, g in ipairs(groups) do
        rows[#rows + 1] = { header = g.title }
        for _, it in ipairs(g.items) do rows[#rows + 1] = { label = it[1], value = it[2] } end
    end
    local w = 300
    local h = math.min(#rows * (fh + 10) + 16, 420)
    local sh = getCore():getScreenHeight()
    local p = Picker:new(x, math.min(y, sh - h - 10), w, h)
    p.rows, p.target, p.onPick = rows, target, onPick
    p.background = false
    p:initialise()
    p:addToUIManager()
    p:setAlwaysOnTop(true)
    return p
end

function Picker:createChildren()
    local fh = U.fontH()
    self.list = W.list(self, 6, 8, self.width - 12, self.height - 16, fh + 10, Picker.drawRow, self, Picker.onRow)
    for _, r in ipairs(self.rows) do self.list:addItem(r.header or r.label, r) end
end

function Picker:onRow(r)
    if r.header then return end
    self:removeFromUIManager()
    if self.onPick then self.onPick(self.target, r.value) end
end

function Picker.drawRow(list, y, item)
    local r = item.item
    if r.header then
        U.text(list, r.header, 10, y + 5, "textMuted")
    else
        W.rowBg(list, y, item, false)
        U.text(list, U.fit(r.label, list:getWidth() - 40), 22, y + 5, "text")
    end
    return y + list.itemheight
end

function Picker:prerender()
    U.fill(self, 0, 0, self.width, self.height, { r = 0.10, g = 0.10, b = 0.11, a = 0.98 })
    U.border(self, 0, 0, self.width, self.height, { r = 1, g = 1, b = 1, a = 0.16 })
end

-- 點到外面就關
function Picker:onMouseDownOutside() self:removeFromUIManager() end

-- ---------------------------------------------------------------- 視窗外殼：圓角 surface、自繪標題列、可拖曳
MVSC_Window = ISPanel:derive("MVSC_Window")
local Window = MVSC_Window

function Window:new(x, y, w, h, title)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title = title
    o.background = false
    o.moveWithMouse = true
    o.headerH = 48
    return o
end

function Window:createChildren()
    self.closeBtn = W.button(self, self.width - 44, 10, 32, 28, "", self, self.close, "ghost", "close")
end

function Window:prerender()
    U.fill(self, 0, 0, self.width, self.height, { r = 0.075, g = 0.075, b = 0.085, a = 0.97 })
    U.border(self, 0, 0, self.width, self.height, { r = 1, g = 1, b = 1, a = 0.12 })
    local x = 18
    if W.icon(self, "steeringwheel", x, 15, 20, "accent") then x = x + 30 end
    U.text(self, self.title or "", x, math.floor((self.headerH - U.fontH(UIFont.Medium)) / 2), "text", UIFont.Medium)
    if self.badge then
        local bw = getTextManager():MeasureStringX(UIFont.Small, self.badge) + 16 + (ICONS and 22 or 0)
        local bx = self.width - 60 - bw
        U.fill(self, bx, 14, bw, 20, { r = 1, g = 1, b = 1, a = 0.06 }, "pill")
        local tx = bx + 8
        if W.icon(self, "shieldCheck", tx, 16, 16, "accent") then tx = tx + 22 end
        U.text(self, self.badge, tx, 14 + math.floor((20 - U.fontH()) / 2), "textMuted")
    end
end

function Window:close()
    self:removeFromUIManager()
end
