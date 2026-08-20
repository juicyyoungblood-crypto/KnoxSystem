-- PL10 class pick modal (Warrior only MVP)
require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "KnoxSystem/KS_Class"
require "KnoxSystem/KS_ModData"

KS_ClassModal = ISPanel:derive("KS_ClassModal")

local COL = {
    bg = { r = 0.05, g = 0.114, b = 0.247, a = 0.96 },
    accent = { r = 0.36, g = 0.72, b = 1, a = 1 },
    muted = { r = 0.7, g = 0.78, b = 0.88, a = 1 },
    btn = { r = 0.10, g = 0.22, b = 0.36, a = 1 },
    btnOn = { r = 0.15, g = 0.40, b = 0.60, a = 1 },
    locked = { r = 0.35, g = 0.35, b = 0.4, a = 1 },
}

function KS_ClassModal:initialise()
    ISPanel.initialise(self)
end

function KS_ClassModal:createChildren()
    self.backgroundColor = COL.bg
    self.borderColor = { r = COL.accent.r, g = COL.accent.g, b = COL.accent.b, a = 0.8 }

    local w = self.width
    local y = 16
    local title = ISLabel:new(0, y, 24, "Choose Your Class", 1, 1, 1, 1, UIFont.Medium, true)
    title:initialise(); title:instantiate(); self:addChild(title)
    title:setX(math.floor((w - 180) / 2))
    y = y + 32

    local sub = ISLabel:new(20, y, 16, "Personal Level 10 — this choice is permanent.", COL.muted.r, COL.muted.g, COL.muted.b, 1, UIFont.Small, true)
    sub:initialise(); sub:instantiate(); self:addChild(sub)
    y = y + 28

    local classes = {
        { id = "warrior", label = "Warrior", ok = true },
        { id = "thief", label = "Thief", ok = false },
        { id = "ranger", label = "Ranger", ok = false },
        { id = "mage", label = "Mage", ok = false },
        { id = "crafter", label = "Crafter", ok = false },
    }
    self.classButtons = {}
    for _, c in ipairs(classes) do
        local bw = w - 40
        local b = ISButton:new(20, y, bw, 28, c.label, self, KS_ClassModal.onPick)
        b.internal = c.id
        b:initialise(); b:instantiate()
        if c.ok then
            b.backgroundColor = { r = COL.btnOn.r, g = COL.btnOn.g, b = COL.btnOn.b, a = 1 }
            b.enable = true
        else
            b:setTitle(c.label .. "  (Coming later)")
            b.backgroundColor = { r = COL.locked.r, g = COL.locked.g, b = COL.locked.b, a = 1 }
            b.enable = false
        end
        self:addChild(b)
        self.classButtons[c.id] = b
        y = y + 34
    end

    y = y + 8
    local note = ISLabel:new(20, y, 14, "Warrior: Melee Proficiency, Armored, Charge (G).", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    note:initialise(); note:instantiate(); self:addChild(note)
end

function KS_ClassModal:onPick(btn)
    if not btn or not btn.internal or btn.enable == false then return end
    local player = self.player or getPlayer()
    local ok, err = KnoxSystem.Class.select(player, btn.internal)
    if ok then
        self:close()
        pcall(function()
            if HaloTextHelper and player then
                HaloTextHelper.addText(player, "Class: Warrior", HaloTextHelper.getColorGreen())
            end
        end)
    else
        print("[KnoxSystem] Class pick failed: " .. tostring(err))
    end
end

function KS_ClassModal:close()
    self:setVisible(false)
    if self.removeFromUIManager then self:removeFromUIManager() end
    KnoxSystem.UI._classModal = nil
end

function KS_ClassModal:prerender()
    self:drawRectStatic(0, 0, self.width, self.height, COL.bg.a, COL.bg.r, COL.bg.g, COL.bg.b)
    ISPanel.prerender(self)
end

function KS_ClassModal:new(x, y, w, h, player)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.backgroundColor = COL.bg
    return o
end

KnoxSystem.UI = KnoxSystem.UI or {}

function KnoxSystem.UI.showClassModal(player)
    player = player or getPlayer()
    if not player then return end
    if not KnoxSystem.Class.shouldOfferModal(player) then return end
    if KnoxSystem.UI._classModal then
        pcall(function() KnoxSystem.UI._classModal:setVisible(true) end)
        return
    end
    local sw, sh = 800, 600
    pcall(function()
        sw = getCore():getScreenWidth()
        sh = getCore():getScreenHeight()
    end)
    local w, h = 360, 320
    local x = math.floor((sw - w) / 2)
    local y = math.floor((sh - h) / 2)
    local m = KS_ClassModal:new(x, y, w, h, player)
    m:initialise()
    m:instantiate()
    m:addToUIManager()
    m:setAlwaysOnTop(true)
    KnoxSystem.UI._classModal = m
    print("[KnoxSystem] Class pick modal shown")
end

function KnoxSystem.UI.tryClassModal(player)
    pcall(function()
        if KnoxSystem.Class.shouldOfferModal(player or getPlayer()) then
            KnoxSystem.UI.showClassModal(player or getPlayer())
        end
    end)
end
