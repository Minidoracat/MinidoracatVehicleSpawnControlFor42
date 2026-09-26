-- 入口：原版管理面板（多人）最後一格加「車輛生成控制」；debug 選單（單人測試）。
-- 原版在 create() 內加完所有按鈕、依標題排序排成兩欄、最後放「關閉」（ISAdminPanelUI.lua:157-189）。
-- 這裡等原函式跑完才把按鈕放進下一格，不改動任何原版按鈕的位置或排序（使用者要求）。
require "ISUI/AdminPanel/ISAdminPanelUI"
require "MinidoracatVehicleSpawnControl/MVSC_Panel"

local M = MinidoracatVehicleSpawnControl
local U = M.UI

local function allowed()
    local p = getPlayer()
    local role = p and p:getRole()
    return role ~= nil and role:hasCapability(Capability.SandboxOptions) -- 同原版「沙盒設定」按鈕（ISAdminPanelUI.lua:226）
end
M.canOpenPanel = allowed

if ISAdminPanelUI then
    local origCreate = ISAdminPanelUI.create
    function ISAdminPanelUI:create()
        origCreate(self)
        -- 原版的 UI_BORDER_SPACING／BUTTON_HGT 是該檔 local（ISAdminPanelUI.lua:7-8），從排好的按鈕反推格子
        local buttons = {}
        for _, child in ipairs(self.childrenInOrder) do -- children 是以 ID 為鍵的 map（家族 pitfalls UI 段）
            if child ~= self.cancel and child.Type == "ISButton" then buttons[#buttons + 1] = child end
        end
        if #buttons == 0 then return end
        local x0, y0 = math.huge, math.huge
        for _, b in ipairs(buttons) do
            x0 = math.min(x0, b:getX())
            y0 = math.min(y0, b:getY())
        end
        local w, h = buttons[1]:getWidth(), buttons[1]:getHeight()
        local dx, dy, bottom = nil, nil, 0
        for _, b in ipairs(buttons) do
            if b:getX() > x0 then dx = math.min(dx or math.huge, b:getX() - x0) end
            if b:getY() > y0 then dy = math.min(dy or math.huge, b:getY() - y0) end
            bottom = math.max(bottom, b:getBottom())
        end
        dx = dx or (w + 10)
        dy = dy or (h + 10)
        local count = #buttons
        local col, row = count % 2, math.floor(count / 2)
        local btn = ISButton:new(x0 + col * dx, y0 + row * dy, w, h, U.T("Title"), self, function() MVSC_Panel.toggle() end)
        btn:initialise()
        btn:instantiate()
        btn.borderColor = self.buttonBorderColor
        btn.tooltip = U.T("AdminTooltip")
        self:addChild(btn)
        self.mvscBtn = btn
        local gap = dy - h
        bottom = math.max(bottom, btn:getBottom())
        self.cancel:setY(bottom + gap)
        self:setHeight(self.cancel:getBottom() + gap + 1)
    end

    local origUpdate = ISAdminPanelUI.updateButtons
    function ISAdminPanelUI:updateButtons()
        origUpdate(self) -- 可能因權限不足直接關閉面板
        if self.mvscBtn then self.mvscBtn.enable = allowed() end
    end
end

-- 單人沒有管理面板（ISEquippedItem.lua:905 只在 isClient() 建立），debug 模式由 debug 選單開啟
local okDebug = pcall(require, "DebugUIs/DebugMenu/ISDebugMenu")
if okDebug and ISDebugMenu then
    local origSetup = ISDebugMenu.setupButtons
    function ISDebugMenu:setupButtons()
        self:addButtonInfo(U.T("Title"), function() MVSC_Panel.toggle() end, "MAIN")
        origSetup(self)
    end
end
