-- Personal Power (System tab only, max 10 @ 2 SP)
-- Design ≥0.5.136:
--   NO getPerkLevel(Strength) hook
--   Carry: +1 max weight per Power level (UCWF if present, else MaxWeightBonus)
--   Melee: flat +10% of hit damage to zombie HP if Power≥1 (not bare hands/shove)
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Power = KnoxSystem.Power or {}

local POWER_MAX = 10
local CARRY_PER_LEVEL = 1.0          -- +1 lb/kg unit per Power rank
local MELEE_BONUS_FRAC = 0.10        -- flat 10% if Power ≥ 1
local UCWF_MOD_ID = "UCWF"           -- Workshop: Unified Carry Weight Framework
local UCWF_KEY = "KnoxSystem_Power"  -- unique modifier id for UCWF

function KnoxSystem.Power.maxLevel()
    return POWER_MAX
end

function KnoxSystem.Power.level(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 0 end
    local lv = tonumber(data.stat_power) or tonumber(data.stat_strength) or 0
    if lv < 0 then lv = 0 end
    if lv > POWER_MAX then lv = POWER_MAX end
    return lv
end

function KnoxSystem.Power.clampData(data)
    if not data then return end
    if (tonumber(data.stat_power) or 0) > 10 and not data._powerOver10Refund_v0128 then
        local before = tonumber(data.stat_power) or 0
        local refund = before
        data.skill_points_unspent = (tonumber(data.skill_points_unspent) or 0) + refund
        data.stat_power = 0
        data.stat_strength = 0
        if type(data.sp_cart_stats) == "table" then
            data.sp_cart_stats.Power = nil
            data.sp_cart_stats.Strength = nil
        end
        data._powerOver10Refund_v0128 = true
        print(string.format(
            "[KnoxSystem] Power over-cap refund (clampData): Power %d -> 0, +%d SP",
            before, refund
        ))
    end
    local p = tonumber(data.stat_power) or tonumber(data.stat_strength) or 0
    if p < 0 then p = 0 end
    if p > POWER_MAX then p = POWER_MAX end
    data.stat_power = p
    data.stat_strength = p
end

--- Vanilla Strength perk only (no Power). Hook removed.
function KnoxSystem.Power.getStrengthReal(player)
    if not player then return 0 end
    local lvl = 0
    pcall(function()
        local p = nil
        if Perks then p = Perks.Strength or Perks.STRENGTH end
        if p == nil and PerkFactory and PerkFactory.Perks then
            p = PerkFactory.Perks.Strength
        end
        if p ~= nil and type(player.getPerkLevel) == "function" then
            lvl = tonumber(player:getPerkLevel(p)) or 0
        end
    end)
    return lvl
end

--- Deprecated alias: effective == real (no Strength boost).
function KnoxSystem.Power.getStrengthEffective(player)
    return KnoxSystem.Power.getStrengthReal(player)
end

function KnoxSystem.Power.mult(_player)
    return 1
end

-- Stubs: hook fully removed
function KnoxSystem.Power.withRawPerkLevel(fn)
    if type(fn) == "function" then return fn() end
    return nil
end
function KnoxSystem.Power.hookPerkLevel() return false end
function KnoxSystem.Power.ensureInstanceHook(_player) end
function KnoxSystem.Power.hookUiRawDisplay() return false end
function KnoxSystem.Power.onMeleeHit(...) end
function KnoxSystem.Power.hookSmashWindow() end
function KnoxSystem.Power.bonusDamage(...) return 0 end

-- -------- Carry (+1 per Power) --------
local _carryLogMs = 0
local _ucwfResolved = nil -- cache which API path works

local function ucwfPresent()
    local ok = false
    pcall(function()
        if getActivatedMods then
            local mods = getActivatedMods()
            if mods and mods.contains and mods:contains(UCWF_MOD_ID) then ok = true end
            if not ok and mods and mods.contains and mods:contains("UnifiedCarryWeightFramework") then ok = true end
        end
    end)
    if not ok then
        pcall(function()
            if UCWF ~= nil then ok = true end
            if UCWF_API ~= nil then ok = true end
            if UnifiedCarryWeight ~= nil then ok = true end
        end)
    end
    return ok
end

--- Try UCWF APIs (framework ships examples; names vary by version).
local function applyUCWF(player, bonus)
    if _ucwfResolved == false then return false, "ucwf_missing" end

    local tried = {}
    local function mark(name, ok)
        tried[#tried + 1] = name .. (ok and "=ok" or "=no")
        return ok
    end

    -- Lazy require common paths once
    pcall(function() require "UCWF/UCWF" end)
    pcall(function() require "UCWF" end)
    pcall(function() require "shared/UCWF" end)

    local api = rawget(_G, "UCWF") or rawget(_G, "UCWF_API") or rawget(_G, "UnifiedCarryWeight")

    if type(api) == "table" then
        -- Pattern A: setNamedModifier(player, key, { totalFlat = n })
        if type(api.setModifier) == "function" then
            local ok = pcall(api.setModifier, api, player, UCWF_KEY, { totalFlat = bonus, totalMult = 1, baseFlat = 0, baseMult = 1 })
            if not ok then ok = pcall(api.setModifier, player, UCWF_KEY, bonus) end
            if mark("setModifier", ok) and ok then _ucwfResolved = "setModifier"; return true, "UCWF.setModifier" end
        end
        if type(api.SetModifier) == "function" then
            local ok = pcall(api.SetModifier, api, player, UCWF_KEY, { totalFlat = bonus })
            if not ok then ok = pcall(api.SetModifier, player, UCWF_KEY, bonus) end
            if mark("SetModifier", ok) and ok then _ucwfResolved = "SetModifier"; return true, "UCWF.SetModifier" end
        end
        if type(api.addTotalFlat) == "function" then
            local ok = pcall(api.addTotalFlat, api, player, UCWF_KEY, bonus)
            if not ok then ok = pcall(api.addTotalFlat, player, UCWF_KEY, bonus) end
            if mark("addTotalFlat", ok) and ok then _ucwfResolved = "addTotalFlat"; return true, "UCWF.addTotalFlat" end
        end
        if type(api.setTotalWeightBonus) == "function" then
            local ok = pcall(api.setTotalWeightBonus, api, player, UCWF_KEY, bonus)
            if not ok then ok = pcall(api.setTotalWeightBonus, player, UCWF_KEY, bonus) end
            if mark("setTotalWeightBonus", ok) and ok then _ucwfResolved = "setTotalWeightBonus"; return true, "UCWF.setTotalWeightBonus" end
        end
        if type(api.AddBonus) == "function" then
            local ok = pcall(api.AddBonus, api, player, UCWF_KEY, bonus, "total")
            if mark("AddBonus", ok) and ok then _ucwfResolved = "AddBonus"; return true, "UCWF.AddBonus" end
        end
        if type(api.registerBonus) == "function" then
            local ok = pcall(api.registerBonus, api, UCWF_KEY, function(_p) return bonus end)
            if mark("registerBonus", ok) and ok then _ucwfResolved = "registerBonus"; return true, "UCWF.registerBonus" end
        end
    end

    -- Global helpers some versions export
    if type(rawget(_G, "UCWF_SetPlayerTotalFlat")) == "function" then
        local ok = pcall(UCWF_SetPlayerTotalFlat, player, UCWF_KEY, bonus)
        if mark("UCWF_SetPlayerTotalFlat", ok) and ok then
            _ucwfResolved = "UCWF_SetPlayerTotalFlat"
            return true, "UCWF_SetPlayerTotalFlat"
        end
    end

    if not ucwfPresent() then
        _ucwfResolved = false
        return false, "ucwf_not_loaded"
    end
    return false, "ucwf_api_unknown:" .. table.concat(tried, ",")
end

local function applyDIYCarry(player, data, bonus)
    local prev = tonumber(data._knoxPowerWeightBonus) or 0
    local method = "none"
    local before, after = -1, -1

    pcall(function()
        if type(player.getMaxWeight) == "function" then
            before = tonumber(player:getMaxWeight()) or -1
        end
    end)

    local okBonus = false
    pcall(function()
        if type(player.setMaxWeightBonus) ~= "function" then return end
        local curBonus = 0
        if type(player.getMaxWeightBonus) == "function" then
            curBonus = tonumber(player:getMaxWeightBonus()) or 0
        end
        local others = curBonus - prev
        if others < 0 then others = 0 end
        player:setMaxWeightBonus(others + bonus)
        data._knoxPowerWeightBonus = bonus
        okBonus = true
        method = "maxWeightBonus"
    end)

    if not okBonus then
        pcall(function()
            if type(player.setMaxWeight) ~= "function" or type(player.getMaxWeight) ~= "function" then return end
            local cur = tonumber(player:getMaxWeight()) or 0
            local natural = cur - prev
            if natural < 1 then natural = cur end
            player:setMaxWeight(natural + bonus)
            data._knoxPowerWeightBonus = bonus
            method = "setMaxWeight"
        end)
    end

    pcall(function()
        if type(player.getMaxWeight) == "function" then
            after = tonumber(player:getMaxWeight()) or -1
        end
    end)
    return method, before, after
end

function KnoxSystem.Power.syncCarry(player)
    if not player then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data then return end

    local pow = KnoxSystem.Power.level(player)
    local wantBonus = pow * CARRY_PER_LEVEL
    if wantBonus < 0 then wantBonus = 0 end

    local before = -1
    pcall(function()
        if type(player.getMaxWeight) == "function" then
            before = tonumber(player:getMaxWeight()) or -1
        end
    end)

    local method, after = "none", before
    local ucwfOk, ucwfHow = applyUCWF(player, wantBonus)
    if ucwfOk then
        method = ucwfHow
        -- Clear DIY leftover so we don't double-stack if we switched to UCWF
        if (tonumber(data._knoxPowerWeightBonus) or 0) > 0 then
            applyDIYCarry(player, data, 0)
        end
        pcall(function()
            if type(player.getMaxWeight) == "function" then
                after = tonumber(player:getMaxWeight()) or after
            end
        end)
    else
        local diyMethod, b2, a2 = applyDIYCarry(player, data, wantBonus)
        method = diyMethod .. (ucwfHow and ("|" .. tostring(ucwfHow)) or "")
        before = b2
        after = a2
    end

    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    if ms - _carryLogMs > 4000 then
        _carryLogMs = ms
        if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("strength_apply") then
            KnoxSystem.Track.log("strength_apply", "carry", {
                reason = "carry",
                powerLv = pow,
                ourBonus = wantBonus,
                perLevel = CARRY_PER_LEVEL,
                maxWeightBefore = before,
                maxWeightAfter = after,
                method = method,
                note = "Power carry +1/level; UCWF preferred, DIY fallback; no Strength hook",
            })
        elseif KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power") then
            KnoxSystem.Track.log("power", "carry", {
                reason = "carry",
                powerLv = pow,
                ourBonus = wantBonus,
                maxWeightAfter = after,
                method = method,
            })
        end
    end
end

-- -------- Melee +10% (Power ≥ 1, not bare hands) --------
function KnoxSystem.Power.onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker or not target then return end
    local isP, isZ = false, false
    pcall(function()
        if instanceof and instanceof(attacker, "IsoPlayer") then isP = true end
    end)
    if not isP then return end
    pcall(function()
        if attacker.isLocalPlayer and not attacker:isLocalPlayer() then isP = false end
    end)
    if not isP then return end

    local pow = KnoxSystem.Power.level(attacker)
    if pow < 1 then return end

    pcall(function()
        if instanceof and instanceof(target, "IsoZombie") then isZ = true end
    end)
    if not isZ then return end
    local alive = true
    pcall(function()
        if target.isAlive and not target:isAlive() then alive = false end
    end)
    if not alive then return end

    -- Skip shove / bare hands
    local bare = false
    pcall(function()
        if weapon and weapon.isBareHands and weapon:isBareHands() then bare = true end
        if not bare and weapon and weapon.getFullType then
            local ft = string.lower(tostring(weapon:getFullType() or ""))
            if ft:find("barehands", 1, true) then bare = true end
        end
    end)
    if bare then return end

    local dmg = tonumber(damage) or 0
    if dmg <= 0 then return end
    local bonus = dmg * MELEE_BONUS_FRAC
    if bonus <= 0 then return end

    local hpBefore, hpAfter = -1, -1
    pcall(function()
        if target.getHealth then hpBefore = tonumber(target:getHealth()) or -1 end
        local nh = hpBefore - bonus
        if nh < 0 then nh = 0 end
        if target.setHealth then target:setHealth(nh) end
        if target.getHealth then hpAfter = tonumber(target:getHealth()) or nh end
    end)

    -- Throttle combat spam (~4 hits/sec max log)
    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    if not KnoxSystem.Power._lastMeleeLogMs then KnoxSystem.Power._lastMeleeLogMs = 0 end
    if (ms - KnoxSystem.Power._lastMeleeLogMs) >= 250 then
        KnoxSystem.Power._lastMeleeLogMs = ms
        if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("strength_apply") then
            KnoxSystem.Track.log("strength_apply", "melee_bonus", {
                reason = "melee_bonus",
                powerLv = pow,
                hitDamage = dmg,
                bonusFrac = MELEE_BONUS_FRAC,
                bonusDamage = bonus,
                hpBefore = hpBefore,
                hpAfter = hpAfter,
                note = "flat 10% bonus if Power>=1; not bare hands",
            })
        elseif KnoxSystem.Track and KnoxSystem.Track.isChannelOn("damage") then
            KnoxSystem.Track.log("damage", "power_melee_bonus", {
                reason = "melee_bonus",
                powerLv = pow,
                hitDamage = dmg,
                bonusDamage = bonus,
                hpAfter = hpAfter,
            })
        end
    end
end

function KnoxSystem.Power.onPlayerUpdate(player)
    local data = KnoxSystem.getPlayerData(player)
    if data then KnoxSystem.Power.clampData(data) end
    if player then KnoxSystem.Power.syncCarry(player) end
end

function KnoxSystem.Power.onGameStart(player)
    if player then
        pcall(function() KnoxSystem.Power.syncCarry(player) end)
    end
    if player and KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power") then
        local pow = KnoxSystem.Power.level(player)
        local real = KnoxSystem.Power.getStrengthReal(player)
        KnoxSystem.Track.log("power", "game_start", {
            reason = "game_start",
            powerLv = pow,
            strengthReal = real,
            carryPerLevel = CARRY_PER_LEVEL,
            meleeBonusFrac = MELEE_BONUS_FRAC,
            ucwfPresent = ucwfPresent() and 1 or 0,
            note = "Power=carry+1/lv + flat 10% melee; NO Strength getPerkLevel hook",
            liveApplied = (pow > 0) and 1 or 0,
        })
    end
end

print("[KnoxSystem] KS_Power loaded (carry+1/lv, melee+10%, no Strength hook)")
