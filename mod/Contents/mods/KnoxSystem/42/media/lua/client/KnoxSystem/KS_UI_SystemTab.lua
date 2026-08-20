-- KnoxSystem System TAB (Phase 3.15 — Skills-tab catalog locked + categories)
-- Goal: System content works; vanilla tabs work; optional blue sheet chrome
-- without blanking Info/Health/Protection/Temperature.

require "ISUI/ISPanel"
require "ISUI/ISLabel"
require "ISUI/ISButton"
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Level"
require "KnoxSystem/KS_WorldRank"
require "KnoxSystem/KS_SP"
require "KnoxSystem/KS_Stats"
require "KnoxSystem/KS_BaseSkills"
require "KnoxSystem/KS_Class"

KS_SystemTabView = ISPanel:derive("KS_SystemTabView")

-- Class skill row: name + 10 XP boxes (fill like Skills tab pips)
KS_ClassSkillRow = ISPanel:derive("KS_ClassSkillRow")
local BOX_N = 10
local BOX_W, BOX_H, BOX_GAP = 14, 12, 3
local NAME_W = 130

local CLASS_SKILL_DESC = {
    MeleeProficiency = "Gain XP from melee hits and stomps on zombies.\nEach level: +3% melee effectiveness, +8% less blade sharpness loss (80% at 10).",
    Armored = "Gain XP while wearing protective gear.\nEach level improves worn protection (~+2.5% scratch/bite/bullet; shows on Protection tab).\nDecreases the stress of being Uncomfortable (6% of stress gain per level, every 5s; 60% at 10).",
    Charge = "Press G while walking/running/sprinting. Standing blocked.\nBlocked at Winded+ moodle (2+). Costs sprint stamina while charging.\nDash 20+5/level ticks. Pushes zombies (no wall clip).",
}

function KS_ClassSkillRow:initialise()
    ISPanel.initialise(self)
end

function KS_ClassSkillRow:createChildren()
    self.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.lbl = ISLabel:new(0, 1, 14, self.skillDisplay or "Skill", 0.85, 0.9, 1, 1, UIFont.Small, true)
    self.lbl:initialise(); self.lbl:instantiate(); self:addChild(self.lbl)
    self.level = 0
    self.xp = 0
    self.need = 1
    self.maxLevel = 10
    self.tipTitle = self.skillDisplay or "Skill"
    self.tipBody = ""
    self.mouseOver = false
end

function KS_ClassSkillRow:buildTipText()
    local frac = 0
    if self.level < self.maxLevel then
        frac = math.max(0, math.min(1, self.xp / self.need))
    end
    local desc = CLASS_SKILL_DESC[self.skillId] or "Class skill"
    local body
    if self.level >= self.maxLevel then
        body = string.format("Level %d (MAX)\n\n%s", self.level, desc)
    else
        body = string.format("Level %d\nXP: %.0f / %.0f  (%.0f%% to next)\n\n%s",
            self.level, self.xp, self.need, frac * 100, desc)
    end
    self.tipTitle = self.skillDisplay or "Skill"
    self.tipBody = body
    return body
end

function KS_ClassSkillRow:setProgress(level, xp, need, maxLevel)
    self.level = tonumber(level) or 0
    self.xp = tonumber(xp) or 0
    self.need = math.max(1, tonumber(need) or 1)
    self.maxLevel = tonumber(maxLevel) or 10
    if self.lbl then
        self.lbl:setName(string.format("%s: %d", self.skillDisplay or "Skill", self.level))
    end
    self:buildTipText()
end

function KS_ClassSkillRow:ensureTooltip()
    if self.tooltipUI then return self.tooltipUI end
    local ok, tip = pcall(function()
        require "ISUI/ISToolTip"
        local t = ISToolTip:new()
        t:initialise()
        t:setVisible(false)
        t:setAlwaysOnTop(true)
        t.maxLineWidth = 320
        return t
    end)
    if ok and tip then
        self.tooltipUI = tip
        return tip
    end
    return nil
end

function KS_ClassSkillRow:showTooltip()
    local tip = self:ensureTooltip()
    if not tip then return end
    self:buildTipText()
    pcall(function()
        if tip.setName then tip:setName(self.tipTitle) end
        tip.description = self.tipBody or ""
        if tip.setOwner then tip:setOwner(self) end
        if not tip:getIsVisible() then
            tip:addToUIManager()
            tip:setVisible(true)
        end
        -- follow cursor
        local mx, my = getMouseX(), getMouseY()
        if tip.setX then tip:setX(mx + 16) end
        if tip.setY then tip:setY(my + 12) end
    end)
end

function KS_ClassSkillRow:hideTooltip()
    local tip = self.tooltipUI
    if not tip then return end
    pcall(function()
        tip:setVisible(false)
        if tip.removeFromUIManager then tip:removeFromUIManager() end
    end)
end

function KS_ClassSkillRow:onMouseMove(dx, dy)
    ISPanel.onMouseMove(self, dx, dy)
    self.mouseOver = true
    self:showTooltip()
end

function KS_ClassSkillRow:onMouseMoveOutside(dx, dy)
    ISPanel.onMouseMoveOutside(self, dx, dy)
    self.mouseOver = false
    self:hideTooltip()
end

function KS_ClassSkillRow:prerender()
    ISPanel.prerender(self)
    -- Hit area highlight when hovering
    if self.mouseOver then
        local w = self:getWidth() or self.width or 200
        local h = self:getHeight() or self.height or 18
        self:drawRect(0, 0, w, h, 0.15, 0.2, 0.45, 0.7)
    end
    local x0 = NAME_W
    local y0 = 2
    local lv = self.level or 0
    local frac = 0
    if lv < (self.maxLevel or 10) then
        frac = math.max(0, math.min(1, (self.xp or 0) / math.max(1, self.need or 1)))
    end
    for i = 0, BOX_N - 1 do
        local bx = x0 + i * (BOX_W + BOX_GAP)
        self:drawRectBorder(bx, y0, BOX_W, BOX_H, 1, 0.35, 0.55, 0.75)
        self:drawRect(bx + 1, y0 + 1, BOX_W - 2, BOX_H - 2, 0.35, 0.06, 0.10, 0.16)
        if i < lv then
            self:drawRect(bx + 1, y0 + 1, BOX_W - 2, BOX_H - 2, 0.95, 0.25, 0.55, 0.95)
        elseif i == lv and lv < BOX_N then
            local fw = math.floor((BOX_W - 2) * frac + 0.5)
            if fw > 0 then
                self:drawRect(bx + 1, y0 + 1, fw, BOX_H - 2, 0.95, 0.45, 0.75, 1.0)
            end
        end
    end
end

function KS_ClassSkillRow:new(x, y, width, height, skillId, skillDisplay)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.skillId = skillId
    o.skillDisplay = skillDisplay
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    return o
end


local COL = {
    bg = { r = 0.05, g = 0.114, b = 0.247, a = 1.0 },
    accent = { r = 0.36, g = 0.72, b = 1, a = 1 },
    muted = { r = 0.7, g = 0.78, b = 0.88, a = 1 },
    locked = { r = 0.45, g = 0.45, b = 0.5, a = 1 },
    btn = { r = 0.10, g = 0.22, b = 0.36, a = 1 },
    btnOn = { r = 0.15, g = 0.40, b = 0.60, a = 1 },
}

local SYSTEM_TAB_TITLE = "System"
local STAT_ORDER = { "Power", "Endurance", "Mind", "Resilience" }
local SYS_SKILL_ORDER = { "Analyze", "D. Storage" }
local CLASS_ORDER = { "Warrior", "Thief", "Ranger", "Mage", "Crafter" }
local CLASS_SKILLS = {
    Warrior = { "Melee Proficiency", "Charge", "Armored" },
    Thief = { "Scavenger", "Backstab", "Dodge" },
    Ranger = { "Ranged Proficiency", "Woods Lore", "Camouflage" },
    Mage = { "Firebolt", "Chain Lightning", "Alarm" },
    Crafter = { "Hard Worker", "Craftsman", "Enchanting" },
}
local MVP_SELECTABLE = { Warrior = true }

local PAD = 12
local DEFAULT_W = 460
-- System sheet width is FIXED (no growth loop to full screen). Height tracks content.
local SYSTEM_FIXED_W = 460
local OUTER_TITLE_H = 28
local OUTER_PAD = 6
local CONFIRM_BTN_W = 200

function KS_SystemTabView:initialise()
    ISPanel.initialise(self)
    self.selectedClassView = nil
    self._built = false
    self._contentH = 480
end

function KS_SystemTabView:panelInnerWidth()
    local w = self:getWidth() or self.width or DEFAULT_W
    if w < 200 then w = DEFAULT_W end
    return w
end

function KS_SystemTabView:centerLabelX(lab)
    if not lab then return end
    local pw = self:panelInnerWidth()
    local lw = 80
    pcall(function()
        if lab.getWidth then lw = lab:getWidth() or lw end
    end)
    if not lw or lw < 10 then
        -- rough estimate from name length
        local n = ""
        pcall(function() n = lab.name or lab:getName() or "" end)
        lw = math.max(40, tostring(n):len() * 8)
    end
    local x = math.floor((pw - lw) / 2)
    if x < 0 then x = 0 end
    if lab.setX then lab:setX(x) else lab.x = x end
end

function KS_SystemTabView:centerButtonX(btn, btnW)
    if not btn then return end
    btnW = btnW or CONFIRM_BTN_W
    local pw = self:panelInnerWidth()
    local x = math.floor((pw - btnW) / 2)
    if x < PAD then x = PAD end
    if btn.setX then btn:setX(x) else btn.x = x end
    if btn.setWidth then btn:setWidth(btnW) end
    btn.width = btnW
end

function KS_SystemTabView:layoutCenteredChrome()
    self:centerLabelX(self.lblName)
    self:centerButtonX(self.btnConfirmStats, CONFIRM_BTN_W)
    self:centerButtonX(self.btnConfirmSkills, CONFIRM_BTN_W)
    self:centerButtonX(self.btnConfirmClass, CONFIRM_BTN_W)
end

function KS_SystemTabView:createChildren()
    self.backgroundColor = { r = COL.bg.r, g = COL.bg.g, b = COL.bg.b, a = 1 }
    self.borderColor = { r = 0, g = 0, b = 0, a = 0 }

    local w = self.width or DEFAULT_W
    if w < 200 then w = DEFAULT_W end
    local cw = w - PAD * 2
    local y = 8

    self.lblName = ISLabel:new(0, y, 22, "Survivor", 1, 1, 1, 1, UIFont.Medium, true)
    self.lblName:initialise(); self.lblName:instantiate(); self:addChild(self.lblName)
    self:centerLabelX(self.lblName)
    y = y + 28

    local colW = math.floor((cw - 10) / 2)
    self.statRows = {}
    local yL = y
    for _, statName in ipairs(STAT_ORDER) do
        local lab = ISLabel:new(PAD, yL + 2, 16, statName .. ": 0", 1, 1, 1, 1, UIFont.Small, true)
        lab:initialise(); lab:instantiate(); self:addChild(lab)
        local btnM = ISButton:new(PAD + colW - 68, yL, 28, 18, "-", self, KS_SystemTabView.onMinusStat)
        btnM.internal = statName; btnM:initialise(); btnM:instantiate(); self:addChild(btnM)
        local btnP = ISButton:new(PAD + colW - 36, yL, 28, 18, "+", self, KS_SystemTabView.onPlusStat)
        btnP.internal = statName; btnP:initialise(); btnP:instantiate(); self:addChild(btnP)
        self.statRows[statName] = { label = lab, plus = btnP, minus = btnM }
        yL = yL + 22
    end
    -- System skills (Analyze max2, D. Storage max8) — same cart, 5 SP / level
    yL = yL + 4
    local sysHdr = ISLabel:new(PAD, yL, 14, "System Skills (5 SP/lv)", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    sysHdr:initialise(); sysHdr:instantiate(); self:addChild(sysHdr)
    yL = yL + 18
    for _, skName in ipairs(SYS_SKILL_ORDER) do
        local lab = ISLabel:new(PAD, yL + 2, 16, skName .. ": 0/2", 1, 1, 1, 1, UIFont.Small, true)
        lab:initialise(); lab:instantiate(); self:addChild(lab)
        local btnM = ISButton:new(PAD + colW - 68, yL, 28, 18, "-", self, KS_SystemTabView.onMinusStat)
        btnM.internal = skName; btnM:initialise(); btnM:instantiate(); self:addChild(btnM)
        local btnP = ISButton:new(PAD + colW - 36, yL, 28, 18, "+", self, KS_SystemTabView.onPlusStat)
        btnP.internal = skName; btnP:initialise(); btnP:instantiate(); self:addChild(btnP)
        self.statRows[skName] = { label = lab, plus = btnP, minus = btnM, systemSkill = true }
        yL = yL + 22
    end

    self.rightLabels = {}
    local yR = y
    for _, name in ipairs({ "Level", "Exp to Next", "World Rank", "Unspent SP" }) do
        local lab = ISLabel:new(PAD + colW + 10, yR, 16, name .. ": —", 1, 1, 1, 1, UIFont.Small, true)
        lab:initialise(); lab:instantiate(); self:addChild(lab)
        self.rightLabels[name] = lab
        yR = yR + 20
    end

    self.lblCartStats = ISLabel:new(PAD + colW + 10, yR + 4, 14, "Stat cart: 0 SP", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblCartStats:initialise(); self.lblCartStats:instantiate(); self:addChild(self.lblCartStats)
    y = math.max(yL, yR + 24) + 8

    self.btnConfirmStats = ISButton:new(0, y, CONFIRM_BTN_W, 22, "Confirm Stat Spend", self, KS_SystemTabView.onConfirmStats)
    self.btnConfirmStats:initialise(); self.btnConfirmStats:instantiate()
    self.btnConfirmStats.backgroundColor = { r = COL.btn.r, g = COL.btn.g, b = COL.btn.b, a = 1 }
    self:addChild(self.btnConfirmStats)
    self:centerButtonX(self.btnConfirmStats, CONFIRM_BTN_W)
    y = y + 30

    self.lblClassHeader = ISLabel:new(PAD, y, 16, "Class", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblClassHeader:initialise(); self.lblClassHeader:instantiate(); self:addChild(self.lblClassHeader)
    y = y + 20

    self.classButtons = {}
    local btnGap, btnH = 6, 22
    local btnW = math.max(64, math.floor((cw - btnGap * 4) / 5))
    local bx = PAD
    for _, cname in ipairs(CLASS_ORDER) do
        local b = ISButton:new(bx, y, btnW, btnH, cname, self, KS_SystemTabView.onClassClick)
        b.internal = cname; b:initialise(); b:instantiate()
        b.backgroundColor = { r = COL.btn.r, g = COL.btn.g, b = COL.btn.b, a = 1 }
        self:addChild(b)
        self.classButtons[cname] = b
        bx = bx + btnW + btnGap
    end
    y = y + btnH + 8

    -- PL10+: Confirm locks selected class (Warrior only works for now)
    self.btnConfirmClass = ISButton:new(0, y, CONFIRM_BTN_W, 22, "Confirm", self, KS_SystemTabView.onConfirmClass)
    self.btnConfirmClass:initialise(); self.btnConfirmClass:instantiate()
    self.btnConfirmClass.backgroundColor = { r = COL.btnOn.r, g = COL.btnOn.g, b = COL.btnOn.b, a = 1 }
    self:addChild(self.btnConfirmClass)
    self:centerButtonX(self.btnConfirmClass, CONFIRM_BTN_W)
    self.btnConfirmClass:setVisible(false)
    y = y + 26

    self.lblClassMsg = ISLabel:new(PAD, y, 14, "", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblClassMsg:initialise(); self.lblClassMsg:instantiate(); self:addChild(self.lblClassMsg)
    y = y + 18

    self.lblSkillsHeader = ISLabel:new(PAD, y, 16, "Class Skills", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblSkillsHeader:initialise(); self.lblSkillsHeader:instantiate(); self:addChild(self.lblSkillsHeader)
    y = y + 20

    -- Warrior class skill rows with XP boxes (hidden/empty until relevant)
    self.classSkillRows = {}
    self.lblClassSkillsComing = ISLabel:new(PAD + 8, y, 16, "", COL.locked.r, COL.locked.g, COL.locked.b, 1, UIFont.Small, true)
    self.lblClassSkillsComing:initialise(); self.lblClassSkillsComing:instantiate(); self:addChild(self.lblClassSkillsComing)

    local rowH = 18
    local rowW = cw
    local warriorSkills = (KnoxSystem.Class and KnoxSystem.Class.WARRIOR_SKILLS) or {
        { id = "MeleeProficiency", display = "Melee Proficiency" },
        { id = "Armored", display = "Armored" },
        { id = "Charge", display = "Charge" },
    }
    for _, sk in ipairs(warriorSkills) do
        local row = KS_ClassSkillRow:new(PAD, y, rowW, rowH, sk.id, sk.display)
        row:initialise(); row:instantiate(); row:createChildren()
        self:addChild(row)
        self.classSkillRows[#self.classSkillRows + 1] = row
        y = y + rowH + 4
    end
    self.lblClassHint = ISLabel:new(PAD + 8, y, 14, "", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblClassHint:initialise(); self.lblClassHint:instantiate(); self:addChild(self.lblClassHint)
    y = y + 20

    self.lblBaseHeader = ISLabel:new(PAD, y, 16, "Base Skills (Spend SP to increase)", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblBaseHeader:initialise(); self.lblBaseHeader:instantiate(); self:addChild(self.lblBaseHeader)
    y = y + 20

    -- Categories + skill names match Skills tab (Issue4/Issue5)
    self.baseSkillRows = {}
    self.categoryHeaders = {}
    local half = math.floor(cw / 2)
    local btnSz = 24
    local cats = (KnoxSystem.BaseSkills and KnoxSystem.BaseSkills.CATEGORIES) or {}
    for _, cat in ipairs(cats) do
        local hdr = ISLabel:new(PAD, y, 16, cat.header, COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
        hdr:initialise(); hdr:instantiate(); self:addChild(hdr)
        self.categoryHeaders[#self.categoryHeaders + 1] = hdr
        y = y + 18
        local col = 0
        for _, sk in ipairs(cat.skills or {}) do
            local perk = sk.perk
            local display = sk.display or perk
            local x0 = PAD + col * half
            local lab = ISLabel:new(x0, y + 2, 14, display .. ": 0", 0.85, 0.9, 1, 1, UIFont.Small, true)
            lab:initialise(); lab:instantiate(); self:addChild(lab)
            local rightEdge = x0 + half - 6
            local btnP = ISButton:new(rightEdge - btnSz, y, btnSz, 16, "+", self, KS_SystemTabView.onPlusSkill)
            btnP.internal = perk; btnP:initialise(); btnP:instantiate()
            btnP.tooltip = "SP cost on hover"
            self:addChild(btnP)
            local btnM = ISButton:new(rightEdge - btnSz * 2 - 4, y, btnSz, 16, "-", self, KS_SystemTabView.onMinusSkill)
            btnM.internal = perk; btnM:initialise(); btnM:instantiate(); self:addChild(btnM)
            self.baseSkillRows[perk] = { label = lab, plus = btnP, minus = btnM, display = display }
            col = col + 1
            if col > 1 then
                col = 0
                y = y + 20
            end
        end
        if col ~= 0 then y = y + 20 end
        y = y + 6
    end
    y = y + 4

    self.lblCartSkills = ISLabel:new(PAD, y, 14, "Skill cart: 0 SP", COL.accent.r, COL.accent.g, COL.accent.b, 1, UIFont.Small, true)
    self.lblCartSkills:initialise(); self.lblCartSkills:instantiate(); self:addChild(self.lblCartSkills)
    y = y + 20

    self.btnConfirmSkills = ISButton:new(0, y, CONFIRM_BTN_W, 22, "Confirm Skill Spend", self, KS_SystemTabView.onConfirmSkills)
    self.btnConfirmSkills:initialise(); self.btnConfirmSkills:instantiate()
    self.btnConfirmSkills.backgroundColor = { r = COL.btn.r, g = COL.btn.g, b = COL.btn.b, a = 1 }
    self:addChild(self.btnConfirmSkills)
    self:centerButtonX(self.btnConfirmSkills, CONFIRM_BTN_W)
    y = y + 36

    self._contentH = y
    self._built = true
    -- Preferred size for ISTabPanel / window
    self:setHeight(y)
    self.height = y
    -- Long skill list: allow mouse-wheel scroll inside System tab only
    pcall(function()
        self:setScrollChildren(true)
        self:setScrollHeight(y + 8)
    end)
end

function KS_SystemTabView:onMouseWheel(del)
    local h = self:getHeight() or self.height or 0
    local sh = self._contentH or 0
    if sh <= h then return false end
    pcall(function()
        local cur = 0
        if self.getYScroll then cur = self:getYScroll() or 0 end
        -- default wheel: up shows content above
        if self.setYScroll then self:setYScroll(cur - (del * 28)) end
    end)
    return true
end

function KS_SystemTabView:prerender()
    local w = self:getWidth() or self.width or 1
    local h = self:getHeight() or self.height or 1
    self.backgroundColor = { r = COL.bg.r, g = COL.bg.g, b = COL.bg.b, a = 1 }
    self:drawRectStatic(0, 0, w, h, 1, COL.bg.r, COL.bg.g, COL.bg.b)
    ISPanel.prerender(self)
end

function KS_SystemTabView:render()
    ISPanel.render(self)
    self:refreshData()
end

function KS_SystemTabView:onClassClick(btn)
    if not btn or not btn.internal then return end
    local cname = btn.internal
    local player = self:getPlayer()
    local data = player and KnoxSystem.SP.getData(player) or nil
    if not data then return end

    -- Locked: can only view own class
    if data.class_locked and data.class_id then
        if string.lower(cname) ~= data.class_id then return end
        self.selectedClassView = cname
        return
    end

    -- Preview only — Confirm locks
    self.selectedClassView = cname
    if self.lblClassMsg then self.lblClassMsg:setName("") end
end

function KS_SystemTabView:onConfirmClass()
    local player = self:getPlayer()
    local data = player and KnoxSystem.SP.getData(player) or nil
    if not data then return end
    if data.class_locked and data.class_id then return end
    if (data.personal_level or 0) < 10 then
        if self.lblClassMsg then
            self.lblClassMsg:setName("Reach Personal Level 10 first")
            self.lblClassMsg:setColor(COL.locked.r, COL.locked.g, COL.locked.b, 1)
        end
        return
    end

    local cname = self.selectedClassView or "Warrior"
    if MVP_SELECTABLE[cname] then
        local ok, err = KnoxSystem.Class.select(player, string.lower(cname))
        if ok then
            if self.lblClassMsg then
                self.lblClassMsg:setName("Class locked: " .. cname)
                self.lblClassMsg:setColor(COL.accent.r, COL.accent.g, COL.accent.b, 1)
            end
        else
            if self.lblClassMsg then
                self.lblClassMsg:setName("Could not lock class (" .. tostring(err) .. ")")
            end
        end
    else
        -- Other classes: Coming Soon! — no lock
        if self.lblClassMsg then
            self.lblClassMsg:setName("Coming Soon!")
            self.lblClassMsg:setColor(1, 0.85, 0.4, 1)
        end
        print("[KnoxSystem] Class Confirm on " .. cname .. " → Coming Soon!")
    end
end

function KS_SystemTabView:onPlusStat(btn)
    local p = self:getPlayer()
    if p and btn then KnoxSystem.SP.plusStat(p, btn.internal) end
end
function KS_SystemTabView:onMinusStat(btn)
    local p = self:getPlayer()
    if p and btn then KnoxSystem.SP.minusStat(p, btn.internal) end
end
function KS_SystemTabView:onConfirmStats()
    local p = self:getPlayer()
    if p then KnoxSystem.SP.confirmStats(p) end
end
function KS_SystemTabView:onPlusSkill(btn)
    local p = self:getPlayer()
    if not p or not btn or btn.enable == false then return end
    KnoxSystem.SP.plusSkill(p, btn.internal)
end
function KS_SystemTabView:onMinusSkill(btn)
    local p = self:getPlayer()
    if p and btn then KnoxSystem.SP.minusSkill(p, btn.internal) end
end
function KS_SystemTabView:onConfirmSkills()
    local p = self:getPlayer()
    if p then KnoxSystem.SP.confirmSkills(p) end
end

function KS_SystemTabView:getPlayer()
    if self.char then return self.char end
    if self.playerNum ~= nil and getSpecificPlayer then return getSpecificPlayer(self.playerNum) end
    return getPlayer()
end

function KS_SystemTabView:setCharacter(player)
    self.char = player
end

function KS_SystemTabView:refreshData()
    local player = self:getPlayer()
    if not player or not KnoxSystem then return end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not data then return end
    KnoxSystem.SP.ensureCarts(data)

    local name = "Survivor"
    pcall(function()
        local d = player:getDescriptor()
        if d then
            name = ((d:getForename() or "") .. " " .. (d:getSurname() or "")):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then name = "Survivor" end
        end
    end)
    if self.lblName then
        self.lblName:setName(name)
        self:centerLabelX(self.lblName)
    end
    self:layoutCenteredChrome()

    for _, statName in ipairs(STAT_ORDER) do
        local row = self.statRows and self.statRows[statName]
        if row then
            local field = KnoxSystem.SP.statField(statName)
            local cur = data[field] or 0
            local pend = data.sp_cart_stats[statName] or 0
            row.label:setName(pend > 0 and string.format("%s: %d (+%d)", statName, cur, pend)
                or string.format("%s: %d", statName, cur))
            if statName == "Power" then
                -- Show 2 SP/lv in label suffix when at 0 pending for clarity
                local base = pend > 0 and string.format("Power: %d (+%d)", cur, pend) or string.format("Power: %d", cur)
                row.label:setName(base .. " [2 SP]")
            end
            row.minus:setVisible(pend > 0)
            local maxStat = (statName == "Power") and 10 or 20
            local needSp = (statName == "Power") and 2 or 1
            local avail = KnoxSystem.SP.availableForStatsCart(data, player)
            row.plus:setVisible((avail >= needSp and cur + pend < maxStat) or pend > 0)
        end
    end
    for _, skName in ipairs(SYS_SKILL_ORDER) do
        local row = self.statRows and self.statRows[skName]
        if row and KnoxSystem.SystemSkills and KnoxSystem.SystemSkills.DEFS[skName] then
            local def = KnoxSystem.SystemSkills.DEFS[skName]
            local cur = data[def.field] or 0
            local pend = data.sp_cart_stats[skName] or 0
            local maxL = def.max or 2
            local cost = def.costPerLevel or 5
            row.label:setName(pend > 0
                and string.format("%s: %d/%d (+%d) [%dSP]", skName, cur, maxL, pend, cost)
                or string.format("%s: %d/%d [%dSP/lv]", skName, cur, maxL, cost))
            row.minus:setVisible(pend > 0)
            local canPlus = (cur + pend < maxL) and (KnoxSystem.SP.availableForStatsCart(data, player) >= cost)
            row.plus:setVisible(canPlus or pend > 0)
        end
    end

    local pl = data.personal_level or 0
    local sp = data.skill_points_unspent or 0
    if self.rightLabels then
        if self.rightLabels["Level"] then self.rightLabels["Level"]:setName(string.format("Level: %d", pl)) end
        if self.rightLabels["Exp to Next"] then
            self.rightLabels["Exp to Next"]:setName(string.format("Exp to Next: %.0f", KnoxSystem.Level.xpToNextLevel(data)))
        end
        if self.rightLabels["World Rank"] then
            self.rightLabels["World Rank"]:setName(string.format("World Rank: %d", KnoxSystem.WorldRank.compute(player)))
        end
        if self.rightLabels["Unspent SP"] then self.rightLabels["Unspent SP"]:setName(string.format("Unspent SP: %d", sp)) end
    end

    local scost = KnoxSystem.SP.totalCartCostStats(data)
    if self.lblCartStats then
        self.lblCartStats:setName(string.format("Stat cart: %d SP (remain %d)", scost, math.max(0, sp - scost)))
    end
    if self.btnConfirmStats then self.btnConfirmStats:setEnable(scost > 0 and sp >= scost) end

    if not self.selectedClassView then
        if data.class_id then
            self.selectedClassView = data.class_id:sub(1, 1):upper() .. data.class_id:sub(2)
        else
            self.selectedClassView = "Warrior"
        end
    end

    for _, cname in ipairs(CLASS_ORDER) do
        local b = self.classButtons and self.classButtons[cname]
        if b then
            local isLockedPick = data.class_locked and data.class_id == string.lower(cname)
            local otherLocked = data.class_locked and data.class_id and data.class_id ~= string.lower(cname)
            local isViewing = self.selectedClassView == cname
            if isLockedPick then
                b:setTitle(cname .. " *")
                b.backgroundColor = { r = COL.btnOn.r, g = COL.btnOn.g, b = COL.btnOn.b, a = 1 }
                b.enable = true
            elseif otherLocked then
                b:setTitle(cname)
                b.backgroundColor = { r = 0.12, g = 0.12, b = 0.14, a = 1 }
                b.enable = false
            else
                b:setTitle(cname)
                b.backgroundColor = isViewing
                    and { r = COL.btnOn.r, g = COL.btnOn.g, b = COL.btnOn.b, a = 1 }
                    or { r = COL.btn.r, g = COL.btn.g, b = COL.btn.b, a = 1 }
                b.enable = true
            end
        end
    end

    -- Confirm class: only when PL>=10 and not yet locked
    local showConfirm = (not data.class_locked) and (pl >= 10)
    if self.btnConfirmClass then
        self.btnConfirmClass:setVisible(showConfirm)
        self.btnConfirmClass.enable = showConfirm
        self:centerButtonX(self.btnConfirmClass, CONFIRM_BTN_W)
    end
    if self.lblClassMsg and data.class_locked and data.class_id then
        local dn = data.class_id:sub(1, 1):upper() .. data.class_id:sub(2)
        self.lblClassMsg:setName("Locked: " .. dn)
        self.lblClassMsg:setColor(COL.accent.r, COL.accent.g, COL.accent.b, 1)
    end

    local viewClass = self.selectedClassView or "Warrior"
    local available = MVP_SELECTABLE[viewClass] == true
    local isOwn = data.class_id and string.lower(viewClass) == data.class_id
    if self.lblSkillsHeader then self.lblSkillsHeader:setName("Class Skills — " .. viewClass) end

    local showBars = available or isOwn
    local cs = data.class_skills or {}
    if self.lblClassSkillsComing then
        if not showBars then
            self.lblClassSkillsComing:setName("Coming later")
            self.lblClassSkillsComing:setVisible(true)
        else
            self.lblClassSkillsComing:setName("")
            self.lblClassSkillsComing:setVisible(false)
        end
    end
    for _, row in ipairs(self.classSkillRows or {}) do
        if row then
            row:setVisible(showBars)
            if showBars then
                local id = row.skillId
                local blob = cs[id] or { level = 0, xp = 0 }
                local lv = blob.level or 0
                local xp = blob.xp or 0
                local need = 1
                if KnoxSystem.Class and KnoxSystem.Class.xpToNext then
                    need = KnoxSystem.Class.xpToNext(lv)
                end
                -- Preview before lock: show empty bars at 0
                if not isOwn and not data.class_id then
                    lv, xp = 0, 0
                end
                row:setProgress(lv, xp, need, 10)
            end
        end
    end
    if self.lblClassHint then
        if not data.class_id then
            if pl < 10 then
                self.lblClassHint:setName("Reach Personal Level 10, then Confirm")
            else
                self.lblClassHint:setName("Select a class, then press Confirm")
            end
            self.lblClassHint:setVisible(true)
        else
            self.lblClassHint:setName("")
            self.lblClassHint:setVisible(false)
        end
    end

    for skillKey, row in pairs(self.baseSkillRows or {}) do
        local cur = KnoxSystem.SP.getBaseSkillLevel(player, skillKey)
        local pend = data.sp_cart_skills[skillKey] or 0
        local maxL = KnoxSystem.SP.skillMaxLevel(player, skillKey)
        local nextTarget = cur + pend + 1
        local nextCost = KnoxSystem.SP.costOneSkillLevel(nextTarget)
        local atMax = (cur + pend) >= maxL
        local canAfford = (not atMax) and (KnoxSystem.SP.availableForSkillsCart(data, player) >= nextCost)

        local dname = row.display or (KnoxSystem.BaseSkills and KnoxSystem.BaseSkills.displayName(skillKey)) or skillKey
        row.label:setName(pend > 0 and string.format("%s: %d (+%d)", dname, cur, pend)
            or string.format("%s: %d", dname, cur))
        row.minus:setVisible(pend > 0)
        row.plus:setVisible(true)
        if atMax then
            row.plus.enable = false
            row.plus.tooltip = "Max level"
        else
            row.plus.enable = canAfford
            local tip = canAfford
                and string.format("Costs %d SP to raise to level %d", nextCost, nextTarget)
                or string.format("Costs %d SP to raise to level %d (have %d)", nextCost, nextTarget,
                    math.max(0, KnoxSystem.SP.availableForSkillsCart(data, player)))
            row.plus.tooltip = tip
            if row.plus.setTooltip then pcall(function() row.plus:setTooltip(tip) end) end
        end
        if row.plus.enable then
            row.plus.backgroundColor = { r = COL.btn.r, g = COL.btn.g, b = COL.btn.b, a = 1 }
            row.plus.textColor = { r = 1, g = 1, b = 1, a = 1 }
        else
            row.plus.backgroundColor = { r = 0.18, g = 0.18, b = 0.20, a = 1 }
            row.plus.textColor = { r = 0.45, g = 0.45, b = 0.48, a = 1 }
        end
    end

    local kcost = KnoxSystem.SP.totalCartCostSkills(data, player)
    if self.lblCartSkills then
        self.lblCartSkills:setName(string.format("Skill cart: %d SP (remain %d)", kcost, math.max(0, sp - kcost)))
    end
    if self.btnConfirmSkills then self.btnConfirmSkills:setEnable(kcost > 0 and sp >= kcost) end
end

function KS_SystemTabView:new(x, y, width, height, playerNum)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum or 0
    o.char = nil
    o.selectedClassView = nil
    o._contentH = 480
    o._built = false
    o.anchorLeft = true
    o.anchorRight = true
    o.anchorTop = true
    o.anchorBottom = true
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColor = { r = COL.bg.r, g = COL.bg.g, b = COL.bg.b, a = 1 }
    return o
end

------------------------------------------------------------------------
-- Injection — minimal: add System tab only. Do not resize panel every frame.
-- Do not paint vanilla tab views. Window blue via soft backgroundColor only.
------------------------------------------------------------------------

KnoxSystem.UI = KnoxSystem.UI or {}
KnoxSystem.UI.SystemTabView = KS_SystemTabView

local function findTabPanel(window)
    if window and window.panel and type(window.panel.addView) == "function" then
        return window.panel
    end
    return nil
end

local function alreadyHasSystemTab(tabPanel)
    if not tabPanel then return false end
    local list = tabPanel.viewList or tabPanel.views
    if not list then return false end
    for _, entry in pairs(list) do
        if type(entry) == "table" then
            if (entry.name or entry.tabname) == SYSTEM_TAB_TITLE then return true end
            if entry.view and entry.view.Type == "KS_SystemTabView" then return true end
        end
    end
    return false
end

local function softBlueWindow(window)
    if not window then return end
    -- Soft tint only on the collapsable window — never on child tab views
    window.backgroundColor = { r = COL.bg.r, g = COL.bg.g, b = COL.bg.b, a = 1 }
end

local function ensureSystemTab(window)
    if not window then return false end
    local tabPanel = findTabPanel(window)
    if not tabPanel then
        return false
    end

    softBlueWindow(window)

    if alreadyHasSystemTab(tabPanel) then
        window.knoxTabPanel = tabPanel
        pcall(function()
            local list = tabPanel.viewList or tabPanel.views
            for _, entry in pairs(list or {}) do
                if type(entry) == "table" and entry.view and entry.view.Type == "KS_SystemTabView" then
                    window.knoxSystemView = entry.view
                end
            end
        end)
        return true
    end

    local playerNum = window.playerNum or 0
    local pw = tabPanel.width or (tabPanel.getWidth and tabPanel:getWidth()) or DEFAULT_W
    if not pw or pw < 200 then pw = DEFAULT_W end
    local ph = 500

    local view = KS_SystemTabView:new(0, 0, pw, ph, playerNum)
    view:initialise()
    view:instantiate()
    -- After createChildren, height is content height
    if view._contentH then
        view:setHeight(view._contentH)
        view.height = view._contentH
    end
    pcall(function()
        view:setCharacter(getSpecificPlayer and getSpecificPlayer(playerNum) or getPlayer())
    end)

    local ok, err = pcall(function()
        tabPanel:addView(SYSTEM_TAB_TITLE, view)
    end)
    if not ok then
        print("[KnoxSystem] addView failed: " .. tostring(err))
        return false
    end

    window.knoxSystemView = view
    window.knoxTabPanel = tabPanel
    print(string.format("[KnoxSystem] System tab added (contentH=%s)", tostring(view._contentH)))
    return true
end

--- Fit System sheet: FIXED width, height from content (clamped to screen).
--- Never derive width from current view/panel width (that runaway-expands to fullscreen).
local function fitWindowToSystem(window)
    if not window or not window.knoxSystemView then return end
    local view = window.knoxSystemView
    local tabPanel = window.panel or findTabPanel(window)
    local contentH = tonumber(view._contentH) or 480
    if contentH < 200 then contentH = 480 end

    pcall(function()
        local tabH = (tabPanel and tabPanel.tabHeight) or 22
        local needW = SYSTEM_FIXED_W
        local needH = contentH + tabH + OUTER_TITLE_H + OUTER_PAD

        local screenH, screenW = 900, 1600
        pcall(function()
            screenW = getCore():getScreenWidth() or screenW
            screenH = getCore():getScreenHeight() or screenH
        end)

        local maxH = math.min(needH, screenH - 48)
        if maxH < 400 then maxH = math.min(400, screenH - 48) end
        -- Width stays fixed unless screen is narrower
        local maxW = math.min(needW, screenW - 48)
        if maxW < 360 then maxW = math.min(360, screenW - 20) end

        -- Skip no-op if already correct (stop thrashing)
        local curW = window.width or 0
        local curH = window.height or 0
        pcall(function()
            if window.getWidth then curW = window:getWidth() or curW end
            if window.getHeight then curH = window:getHeight() or curH end
        end)
        local wOk = math.abs((curW or 0) - maxW) <= 2
        local hOk = math.abs((curH or 0) - maxH) <= 2
        if not wOk or not hOk then
            if window.setWidth then window:setWidth(maxW) end
            if window.setHeight then window:setHeight(maxH) end
            window.width = maxW
            window.height = maxH
        end
        softBlueWindow(window)

        local pw = maxW - 8
        local ph = maxH - OUTER_TITLE_H
        if ph < 200 then ph = maxH - 16 end

        if tabPanel then
            local tpW = tabPanel.width or 0
            local tpH = tabPanel.height or 0
            if math.abs(tpW - pw) > 2 or math.abs(tpH - ph) > 2 then
                if tabPanel.setWidth then tabPanel:setWidth(pw) end
                if tabPanel.setHeight then tabPanel:setHeight(ph) end
                tabPanel.width = pw
                tabPanel.height = ph
            end
        end

        local clientH = ph - tabH
        if clientH < 160 then clientH = math.max(160, ph - 20) end

        if view.setWidth then view:setWidth(pw) end
        view.width = pw
        if view.setHeight then view:setHeight(clientH) end
        view.height = clientH

        pcall(function()
            view:setScrollChildren(true)
            view:setScrollHeight(contentH + 16)
        end)

        -- Do not force setY every tick (fights ISTabPanel). Only if clearly wrong.
        pcall(function()
            local vy = view.y or 0
            if view.getY then vy = view:getY() or vy end
            if vy < 1 and tabH > 0 then
                if view.setY then view:setY(tabH) end
                view.y = tabH
            end
        end)
    end)
end

local function tryPatchCharacterInfoWindow()
    pcall(function()
        require "ISUI/ISCharacterInfoWindow"
        if not ISCharacterInfoWindow then return end
        -- Bump forces re-apply after 3.19 breakage (raw wrap killed tab/chrome)
        if ISCharacterInfoWindow._knoxPatchVer == "3.20" then return end
        ISCharacterInfoWindow._knoxPatchVer = "3.20"
        ISCharacterInfoWindow._knoxSystemTabPatched = true

        local oldCreate = ISCharacterInfoWindow.createChildren
        ISCharacterInfoWindow.createChildren = function(self, ...)
            if oldCreate then oldCreate(self, ...) end
            pcall(function()
                ensureSystemTab(self)
                softBlueWindow(self)
                local panel = self.panel
                if panel and panel.activateView and not panel._knoxAct320 then
                    panel._knoxAct320 = true
                    local oldAct = panel.activateView
                    panel.activateView = function(pself, name)
                        local result = oldAct(pself, name)
                        local n = tostring(name or ""):lower()
                        softBlueWindow(self)
                        if n:find("system", 1, true) then
                            fitWindowToSystem(self)
                        end
                        return result
                    end
                end
            end)
            if not self.knoxSystemView then
                self._knoxRetry = 0
            end
        end

        -- Plain update — no withRaw wrapper on the whole window (that broke System tab)
        local oldUpdate = ISCharacterInfoWindow.update
        if oldUpdate then
            ISCharacterInfoWindow.update = function(self, ...)
                oldUpdate(self, ...)
                pcall(function()
                    if self.knoxSystemView then
                        local p = getSpecificPlayer and getSpecificPlayer(self.playerNum or 0) or getPlayer()
                        self.knoxSystemView:setCharacter(p)
                        local v = self.knoxSystemView
                        local visible = v and v.getIsVisible and v:getIsVisible()
                        if visible then
                            self._knoxFitTick = (self._knoxFitTick or 0) + 1
                            if self._knoxFitTick >= 30 then
                                self._knoxFitTick = 0
                                fitWindowToSystem(self)
                            end
                        end
                    elseif (self._knoxRetry or 0) < 30 then
                        self._knoxRetry = (self._knoxRetry or 0) + 1
                        if self._knoxRetry == 2 or self._knoxRetry == 8 or self._knoxRetry == 18 then
                            ensureSystemTab(self)
                            softBlueWindow(self)
                        end
                    end
                    softBlueWindow(self)
                end)
            end
        end

        local oldPre = ISCharacterInfoWindow.prerender
        ISCharacterInfoWindow.prerender = function(self, ...)
            softBlueWindow(self)
            if oldPre then oldPre(self, ...) end
        end

        -- Skills tab only: wrap skill progress bars when panel exists (raw Strength pips)
        pcall(function()
            if KnoxSystem.Power and KnoxSystem.Power.hookUiRawDisplay then
                KnoxSystem.Power.hookUiRawDisplay()
            end
        end)

        print("[KnoxSystem] Character info patch 3.20 (System tab + blue chrome restored; skill bars raw Strength)")
    end)
end

local function tryPatchExistingInstance()
    pcall(function()
        if ISCharacterInfoWindow and ISCharacterInfoWindow.instance then
            ensureSystemTab(ISCharacterInfoWindow.instance)
        end
        if getPlayerData then
            local pd = getPlayerData(0)
            if pd then
                for _, key in ipairs({ "characterInfo", "infoWindow" }) do
                    if pd[key] then ensureSystemTab(pd[key]) end
                end
            end
        end
    end)
end

function KnoxSystem.UI.focusSystemTab()
    tryPatchExistingInstance()
    local win = ISCharacterInfoWindow and ISCharacterInfoWindow.instance
    if not win and getPlayerData then
        local pd = getPlayerData(0)
        win = pd and (pd.characterInfo or pd.infoWindow)
    end
    if win then
        pcall(function()
            win:setVisible(true)
            if win.bringToTop then win:bringToTop() end
        end)
        ensureSystemTab(win)
        local tabPanel = win.knoxTabPanel or findTabPanel(win)
        if tabPanel and tabPanel.activateView then
            pcall(function() tabPanel:activateView(SYSTEM_TAB_TITLE) end)
        end
        fitWindowToSystem(win)
        return
    end
    print("[KnoxSystem] Open character sheet (C), then System tab")
end

KnoxSystem.UI._patchCharacterInfo = tryPatchCharacterInfoWindow
KnoxSystem.UI._patchExisting = tryPatchExistingInstance
KnoxSystem.UI._ensureSystemTab = ensureSystemTab

print("[KnoxSystem] KS_UI_SystemTab 3.21 loaded (class skill tooltips + Charge 4.4)")
