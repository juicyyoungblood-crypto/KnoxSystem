-- Personal Power LIVE — multiplies Strength-linked outcomes (+5%/level, ×2 at 20)
-- Covers: melee damage, carry capacity, knockdown chance, window smash force/speed.
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Stats"

KnoxSystem.Power = KnoxSystem.Power or {}

local MAG = 0.05
-- Extra knockdown chance at full Power (L20): 25% of melee hits (scales linearly)
local KNOCKDOWN_CHANCE_AT_20 = 0.25
-- Smash window: action time multiplier at L20 (0.5 = twice as fast)
local SMASH_TIME_AT_20 = 0.55

local lastCarryLog = {}
local lastCarryApply = {}
local CARRY_APPLY_MS = 1500

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return t or 0
end

local function isIsoPlayer(o)
    if not o then return false end
    local ok = false
    pcall(function()
        if instanceof and instanceof(o, "IsoPlayer") then ok = true end
    end)
    return ok
end

local function powerLevel(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 0 end
    return tonumber(data.stat_power) or tonumber(data.stat_strength) or 0
end

function KnoxSystem.Power.mult(player)
    local lv = powerLevel(player)
    if lv <= 0 then return 1 end
    if lv > 20 then lv = 20 end
    return 1 + MAG * lv
end

function KnoxSystem.Power.level(player)
    return powerLevel(player)
end

--- Bonus damage to apply on top of engine raw (so total ≈ raw * mult).
function KnoxSystem.Power.bonusDamage(player, raw)
    raw = tonumber(raw) or 0
    local m = KnoxSystem.Power.mult(player)
    if m <= 1.0001 or raw <= 0 then return 0 end
    return raw * (m - 1)
end

local function applyDamageToZombie(zombie, player, dmg, weapon)
    if not zombie or dmg <= 0 then return false end
    local ok = false
    pcall(function()
        if type(zombie.Hit) == "function" and weapon then
            ok = pcall(function() zombie:Hit(weapon, player, dmg, false, 1.0) end)
            if not ok then
                ok = pcall(function() zombie:Hit(weapon, player, dmg, false, 1.0, false) end)
            end
        end
    end)
    if not ok then
        pcall(function()
            if type(zombie.getHealth) == "function" and type(zombie.setHealth) == "function" then
                local h = tonumber(zombie:getHealth())
                if h then
                    zombie:setHealth(math.max(0, h - dmg))
                    ok = true
                end
            end
        end)
    end
    return ok
end

local function tryKnockdown(zombie, player, powerLv)
    if powerLv <= 0 or not zombie then return false end
    local chance = (powerLv / 20) * KNOCKDOWN_CHANCE_AT_20
    if chance <= 0 then return false end
    local roll = nil
    pcall(function()
        if ZombRandFloat then roll = ZombRandFloat(0, 1)
        elseif ZombRand then roll = ZombRand(1000) / 1000
        else roll = math.random()
        end
    end)
    if roll == nil then roll = math.random() end
    if roll >= chance then return false end
    pcall(function()
        if type(zombie.setKnockedDown) == "function" then zombie:setKnockedDown(true) end
        if type(zombie.setStaggerBack) == "function" then zombie:setStaggerBack(true) end
        if type(zombie.setHitReaction) == "function" then
            pcall(function() zombie:setHitReaction("Shotgun") end)
        end
    end)
    return true
end

--- Called after a melee hit on a zombie (from bootstrap / Melee).
local _powerHitDepth = 0
function KnoxSystem.Power.onMeleeHit(player, target, rawDamage, weapon)
    if _powerHitDepth > 0 then return end -- avoid recursive Hit → OnWeaponHitCharacter
    if not isIsoPlayer(player) then return end
    if not target then return end
    local isZ = false
    pcall(function()
        if instanceof and instanceof(target, "IsoZombie") then isZ = true end
    end)
    if not isZ then return end

    local lv = powerLevel(player)
    if lv <= 0 then return end
    local mult = KnoxSystem.Power.mult(player)
    local raw = tonumber(rawDamage) or 0
    local bonus = KnoxSystem.Power.bonusDamage(player, raw)
    local knocked = false
    local applied = false

    _powerHitDepth = _powerHitDepth + 1
    pcall(function()
        if bonus > 0.0001 then
            -- Prefer direct health drain to avoid re-firing weapon-hit events
            applied = false
            pcall(function()
                if type(target.getHealth) == "function" and type(target.setHealth) == "function" then
                    local h = tonumber(target:getHealth())
                    if h then
                        target:setHealth(math.max(0, h - bonus))
                        applied = true
                    end
                end
            end)
            if not applied then
                applied = applyDamageToZombie(target, player, bonus, weapon)
            end
        end
        knocked = tryKnockdown(target, player, lv)
    end)
    _powerHitDepth = _powerHitDepth - 1

    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power") then
        KnoxSystem.Track.log("power", "melee_live", {
            powerLv = lv,
            powerMult = mult,
            rawDmg = raw,
            bonusDmg = bonus,
            bonusApplied = applied and 1 or 0,
            knockdown = knocked and 1 or 0,
            knockdownChance = (lv / 20) * KNOCKDOWN_CHANCE_AT_20,
            livePowerApplied = 1,
            note = "bonus≈raw*(mult-1) via setHealth; knockdown chance scales to 25% at L20",
        })
    end
end

--- Carry capacity: store baseline once, then maxWeight = baseline * powerMult.
local function readMaxWeight(player)
    local w = nil
    pcall(function()
        if type(player.getMaxWeight) == "function" then
            w = tonumber(player:getMaxWeight())
        end
    end)
    if w == nil then
        pcall(function()
            local inv = player:getInventory()
            if inv and type(inv.getMaxWeight) == "function" then
                w = tonumber(inv:getMaxWeight())
            end
        end)
    end
    return w
end

local function writeMaxWeight(player, w)
    if not w or w <= 0 then return false end
    local ok = false
    pcall(function()
        if type(player.setMaxWeight) == "function" then
            player:setMaxWeight(w)
            ok = true
        end
    end)
    pcall(function()
        if type(player.setMaxWeightBonus) == "function" then
            -- Some builds: bonus additive on top of base
        end
    end)
    pcall(function()
        local inv = player:getInventory()
        if inv and type(inv.setMaxWeight) == "function" then
            inv:setMaxWeight(w)
            ok = true
        end
    end)
    return ok
end

function KnoxSystem.Power.syncCarry(player, reason)
    if not isIsoPlayer(player) then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data or not data.initialized then return end

    local lv = powerLevel(player)
    local mult = KnoxSystem.Power.mult(player)
    local cur = readMaxWeight(player)
    if not cur or cur <= 0 then return end

    -- Baseline: capacity as if Power were 0. Recompute each time from current/mult
    -- to tolerate vanilla Strength changes (vanilla updates max weight).
    local baseline = cur / mult
    if data._powerCarryBaseline and data._powerCarryBaseline > 0 then
        -- If vanilla Strength changed max a lot, refresh baseline when closer without our mult
        local expected = data._powerCarryBaseline * mult
        if math.abs(cur - expected) > 2.5 then
            -- external change — re-baseline from current assuming current mult already applied or not
            if mult > 1.001 and cur > data._powerCarryBaseline then
                baseline = cur / mult
            else
                baseline = cur
            end
            data._powerCarryBaseline = baseline
        else
            baseline = data._powerCarryBaseline
        end
    else
        data._powerCarryBaseline = baseline
    end

    local target = baseline * mult
    if target < 1 then target = 1 end
    -- Avoid thrash
    if math.abs(cur - target) < 0.05 then
        data._powerLiveCarry = true
        return
    end
    writeMaxWeight(player, target)
    data._powerLiveCarry = true

    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local t = nowMs()
    local last = lastCarryLog[id] or 0
    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power") and (t <= 0 or last <= 0 or t - last > 8000) then
        lastCarryLog[id] = t
        KnoxSystem.Track.log("power", "carry_live", {
            reason = tostring(reason or "tick"),
            powerLv = lv,
            powerMult = mult,
            baseline = baseline,
            maxWeight = target,
            livePowerApplied = 1,
        })
    end
end

function KnoxSystem.Power.onPlayerUpdate(player)
    if not isIsoPlayer(player) then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data or not data.initialized then return end
    if KnoxSystem.Stats and KnoxSystem.Stats.applyAll then
        KnoxSystem.Stats.applyAll(player, data)
    end
    data._powerLiveApplied = (powerLevel(player) > 0)
    data._strLiveApplied = data._powerLiveApplied

    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local t = nowMs()
    local last = lastCarryApply[id] or 0
    if t > 0 and last > 0 and (t - last) < CARRY_APPLY_MS then return end
    lastCarryApply[id] = t
    KnoxSystem.Power.syncCarry(player, "update")
end

--- Window smash / force: shorten smash timed action by Power mult.
local smashHooked = false
function KnoxSystem.Power.hookSmashWindow()
    if smashHooked then return end
    smashHooked = true
    pcall(function()
        require "TimedActions/ISSmashWindow"
    end)
    pcall(function()
        if not ISSmashWindow then return end
        if ISSmashWindow._knoxPowerHooked then return end
        ISSmashWindow._knoxPowerHooked = true

        local oldNew = ISSmashWindow.new
        if type(oldNew) == "function" then
            ISSmashWindow.new = function(self, character, window, ...)
                local o = oldNew(self, character, window, ...)
                pcall(function()
                    if not o or not character then return end
                    local mult = KnoxSystem.Power.mult(character)
                    if mult <= 1.001 then return end
                    -- Higher Power → less maxTime (faster smash / force)
                    local tFactor = 1 - (1 - SMASH_TIME_AT_20) * ((mult - 1) / 1.0)
                    -- mult 1→1.0, mult 2→SMASH_TIME_AT_20
                    local span = mult - 1 -- 0..1
                    if span > 1 then span = 1 end
                    tFactor = 1 - (1 - SMASH_TIME_AT_20) * span
                    if tFactor < 0.35 then tFactor = 0.35 end
                    if o.maxTime and o.maxTime > 0 then
                        o.maxTime = math.floor(o.maxTime * tFactor)
                    end
                    if o._knoxPower == nil then
                        o._knoxPower = true
                    end
                    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power") then
                        KnoxSystem.Track.log("power", "smash_window", {
                            powerLv = powerLevel(character),
                            powerMult = mult,
                            timeFactor = tFactor,
                            maxTime = o.maxTime or -1,
                            livePowerApplied = 1,
                        })
                    end
                end)
                return o
            end
        end

        -- Also boost chance / reduce failure if isValid checks strength
        local oldUpdate = ISSmashWindow.update
        if type(oldUpdate) == "function" then
            ISSmashWindow.update = function(self, ...)
                pcall(function()
                    local ch = self.character
                    if ch and KnoxSystem.Power.mult(ch) > 1.001 then
                        -- nudge job delta slightly faster each tick
                        if self.jobDelta and self.maxTime and self.maxTime > 0 then
                            local boost = (KnoxSystem.Power.mult(ch) - 1) * 0.015
                            self.jobDelta = math.min(1, (self.jobDelta or 0) + boost * 0.05)
                        end
                    end
                end)
                return oldUpdate(self, ...)
            end
        end
    end)

    -- Open door by force / remove barricade strength-ish actions
    pcall(function()
        require "TimedActions/ISRemoveBarricade"
        if ISRemoveBarricade and not ISRemoveBarricade._knoxPowerHooked then
            ISRemoveBarricade._knoxPowerHooked = true
            local oldNew = ISRemoveBarricade.new
            if type(oldNew) == "function" then
                ISRemoveBarricade.new = function(self, character, ...)
                    local o = oldNew(self, character, ...)
                    pcall(function()
                        local mult = KnoxSystem.Power.mult(character)
                        if mult <= 1.001 or not o or not o.maxTime then return end
                        local span = math.min(1, mult - 1)
                        local tFactor = 1 - (1 - SMASH_TIME_AT_20) * span
                        if tFactor < 0.35 then tFactor = 0.35 end
                        o.maxTime = math.floor(o.maxTime * tFactor)
                    end)
                    return o
                end
            end
        end
    end)
end

print("[KnoxSystem] KS_Power loaded (LIVE: melee dmg, knockdown, carry, window smash)")
