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

--- Carry capacity: vanilla natural maxWeight × powerMult via MaxWeightBonus (B42).
--- Do NOT setMaxWeight alone — vanilla Strength recalculates and overwrites it.
--- Issue1 (0.5.125): setMaxWeight → log said 22, UI stayed 20 (Str10). Baseline cur/mult was circular.
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

local function readMaxWeightBonus(player)
    local b = nil
    pcall(function()
        if type(player.getMaxWeightBonus) == "function" then
            b = tonumber(player:getMaxWeightBonus())
        end
    end)
    return b
end

local function writeMaxWeightBonus(player, bonus)
    local ok = false
    pcall(function()
        if type(player.setMaxWeightBonus) == "function" then
            player:setMaxWeightBonus(bonus)
            ok = true
        end
    end)
    return ok
end

local function writeMaxWeightAbsolute(player, w)
    if not w or w <= 0 then return false end
    local ok = false
    pcall(function()
        if type(player.setMaxWeight) == "function" then
            player:setMaxWeight(w)
            ok = true
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

local function vanillaStrengthPerk(player)
    local lvl = nil
    pcall(function()
        if not player or type(player.getPerkLevel) ~= "function" then return end
        local p = nil
        if Perks then p = Perks.Strength or Perks.STRENGTH end
        if p == nil and PerkFactory and PerkFactory.Perks then
            p = PerkFactory.Perks.Strength
        end
        if p ~= nil then lvl = tonumber(player:getPerkLevel(p)) end
    end)
    return lvl
end

--- Best-effort vanilla capacity with our previous Power bonus stripped.
local function estimateNaturalMaxWeight(player, data)
    local total = readMaxWeight(player)
    local bonus = readMaxWeightBonus(player)
    local our = tonumber(data._knoxPowerWeightBonus) or 0

    -- Path 1: MaxWeightBonus API — natural = total - our share of bonus
    if total and bonus ~= nil and our > 0 then
        local natural = total - our
        if natural >= 1 then return natural, "total_minus_our_bonus" end
    end
    if total and bonus ~= nil and (our == 0 or our < 0.01) then
        -- No recorded our-bonus: treat full bonus as foreign, natural = total - all bonus
        local natural = total - (bonus or 0)
        if natural >= 1 then return natural, "total_minus_all_bonus" end
    end

    -- Path 2: Strength fallback (Issue1: Str10 → UI 20 → ~2 per Strength level)
    local str = vanillaStrengthPerk(player)
    if str ~= nil then
        -- B42 observed default: 2 * Strength matches Str10→20; keep floor 8
        local byStr = math.max(8, 2 * str)
        if total and total > byStr + 0.5 and our == 0 then
            -- Prefer live total if it looks like pure vanilla (no our bonus yet)
            return total, "live_total_as_vanilla"
        end
        return byStr, "strength_formula_2x"
    end

    if total and total > 0 then return total, "live_total_fallback" end
    return 8, "default8"
end

function KnoxSystem.Power.syncCarry(player, reason)
    if not isIsoPlayer(player) then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data or not data.initialized then return end

    local lv = powerLevel(player)
    local mult = KnoxSystem.Power.mult(player)

    local natural, natSrc = estimateNaturalMaxWeight(player, data)
    if not natural or natural < 1 then natural = 8 end

    local beforeTotal = readMaxWeight(player)
    local beforeBonus = readMaxWeightBonus(player)
    local method = "none"
    local targetTotal = natural * mult
    local ourBonus = 0
    local wrote = false

    if lv < 1 or mult <= 1.0001 then
        -- Clear our bonus
        if (data._knoxPowerWeightBonus or 0) > 0 and writeMaxWeightBonus(player, math.max(0, (beforeBonus or 0) - (data._knoxPowerWeightBonus or 0))) then
            method = "clear_bonus"
            wrote = true
        end
        data._knoxPowerWeightBonus = 0
        data._powerLiveCarry = false
    else
        ourBonus = natural * (mult - 1)
        if ourBonus < 0 then ourBonus = 0 end

        -- Prefer additive bonus (survives vanilla Strength recalc of base max weight)
        local otherBonus = 0
        if beforeBonus ~= nil then
            otherBonus = math.max(0, (beforeBonus or 0) - (tonumber(data._knoxPowerWeightBonus) or 0))
        end
        local wantBonus = otherBonus + ourBonus

        if writeMaxWeightBonus(player, wantBonus) then
            data._knoxPowerWeightBonus = ourBonus
            method = "maxWeightBonus"
            wrote = true
            -- Some builds need a nudge on absolute max too
            local after = readMaxWeight(player)
            if after and natural and after < targetTotal - 0.5 then
                if writeMaxWeightAbsolute(player, targetTotal) then
                    method = "bonus_plus_setMaxWeight"
                end
            end
        else
            -- Fallback: force absolute every tick (vanilla may still fight us)
            if writeMaxWeightAbsolute(player, targetTotal) then
                data._knoxPowerWeightBonus = 0 -- not using bonus path
                method = "setMaxWeight_abs"
                wrote = true
            end
        end
        data._powerLiveCarry = wrote
    end

    local afterTotal = readMaxWeight(player)
    local afterBonus = readMaxWeightBonus(player)
    data._powerCarryBaseline = natural

    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local t = nowMs()
    local last = lastCarryLog[id] or 0
    local mismatch = afterTotal and targetTotal and math.abs(afterTotal - targetTotal) > 0.75
    -- Log periodically, or immediately if UI still wrong
    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power")
        and (mismatch or t <= 0 or last <= 0 or t - last > 5000) then
        lastCarryLog[id] = t
        KnoxSystem.Track.log("power", "carry_live", {
            reason = tostring(reason or "tick"),
            powerLv = lv,
            powerMult = mult,
            natural = natural,
            naturalSrc = natSrc,
            ourBonus = ourBonus,
            targetTotal = targetTotal,
            beforeTotal = beforeTotal or -1,
            beforeBonus = beforeBonus or -1,
            afterTotal = afterTotal or -1,
            afterBonus = afterBonus or -1,
            method = method,
            wrote = wrote and 1 or 0,
            mismatch = mismatch and 1 or 0,
            strPerk = vanillaStrengthPerk(player) or -1,
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

    -- Apply carry every update so vanilla Strength recalc cannot stick at base (Issue1)
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

print("[KnoxSystem] KS_Power loaded (LIVE: melee/knockdown/carry-bonus/smash; carry fix Issue1)")
