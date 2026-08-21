-- Personal Power (System tab only, max 10 @ 2 SP)
-- Design ≥0.5.139:
--   NO getPerkLevel(Strength) hook
--   Carry: +1 max weight per Power level (UCWF if present, else MaxWeightBonus)
--   Melee dmg: +10% of hit * PowerLv (weapons only, not ranged/shove)
--   Thumpables/trees: same % using door/tree damage as base
--   Knock/stagger reroll if vanilla failed: chance = 2*Power + 0.4*Str; stagger band +13
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Power = KnoxSystem.Power or {}

local POWER_MAX = 10
local CARRY_PER_LEVEL = 1.0          -- +1 weight unit per Power rank
local MELEE_BONUS_PER_LEVEL = 0.10   -- +10% of hit damage per Power level (weapons only)
local KNOCK_PER_POWER = 2.0          -- knockChance += 2 * PowerLv
local KNOCK_PER_STR = 0.4            -- knockChance += Str * 0.4
local STAGGER_BAND = 13              -- stagger window above KD (vanilla~25; half for reroll)

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
local _ucwfResolved = nil -- string path name, "none", or "disabled"
local _ucwfRequireOnce = false
local _ucwfApi = nil
local _ucwfGiveUp = false -- true after we know API doesn't move weight

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
            if rawget(_G, "UCWF") ~= nil then ok = true end
            if rawget(_G, "UCWF_API") ~= nil then ok = true end
            if rawget(_G, "UnifiedCarryWeight") ~= nil then ok = true end
        end)
    end
    return ok
end

--- One-time global lookup only (no require — UCWF loads itself; require spam WARNs in B42)
local function discoverUCWF()
    if _ucwfRequireOnce then
        return _ucwfApi
    end
    _ucwfRequireOnce = true

    _ucwfApi = rawget(_G, "UCWF") or rawget(_G, "UCWF_API") or rawget(_G, "UnifiedCarryWeight")
        or rawget(_G, "UCW") or rawget(_G, "CarryWeightFramework")
        or rawget(_G, "UnitedCarryWeightFramework")
        or rawget(_G, "UnitedCarryWeightFramework_Client")

    if type(_ucwfApi) == "table" and not KnoxSystem.Power._ucwfKeysLogged then
        KnoxSystem.Power._ucwfKeysLogged = true
        local keys = {}
        for k, v in pairs(_ucwfApi) do
            keys[#keys + 1] = tostring(k) .. "=" .. type(v)
        end
        table.sort(keys)
        print("[KnoxSystem] UCWF API keys: " .. table.concat(keys, ", "))
    elseif not _ucwfApi then
        print("[KnoxSystem] UCWF: no global API table found (DIY MaxWeightBonus only; framework may still load)")
    end
    return _ucwfApi
end

--- Try UCWF APIs. After first confirmed no-op / unknown, stop calling forever this session.
local function applyUCWF(player, bonus)
    if _ucwfGiveUp or _ucwfResolved == "disabled" or _ucwfResolved == "none" then
        return false, "ucwf_skip"
    end

    local api = discoverUCWF()
    local tried = {}
    local function mark(name, ok)
        tried[#tried + 1] = name .. (ok and "=ok" or "=no")
        return ok
    end

    if type(api) == "table" then
        local candidates = {
            "setModifier", "SetModifier", "addTotalFlat", "setTotalWeightBonus",
            "AddBonus", "addBonus", "SetPlayerModifier", "setPlayerTotalFlat",
            "registerBonus", "setFlatBonus", "addFlatBonus", "SetBonus",
        }
        for i = 1, #candidates do
            local name = candidates[i]
            local fn = api[name]
            if type(fn) == "function" then
                local ok1 = pcall(fn, api, player, UCWF_KEY, bonus)
                local ok2 = pcall(fn, player, UCWF_KEY, bonus)
                local ok3 = pcall(fn, api, player, UCWF_KEY, { totalFlat = bonus })
                local ok4 = pcall(fn, api, UCWF_KEY, bonus)
                if (ok1 or ok2 or ok3 or ok4) and mark(name, true) then
                    _ucwfResolved = name
                    return true, "UCWF." .. name
                else
                    mark(name, false)
                end
            end
        end
        -- One brute pass over weight-ish methods
        for k, v in pairs(api) do
            if type(v) == "function" then
                local lk = string.lower(tostring(k))
                if lk:find("bonus", 1, true) or lk:find("modifier", 1, true) or lk:find("weight", 1, true) then
                    local ok1 = pcall(v, api, player, UCWF_KEY, bonus)
                    local ok2 = pcall(v, player, UCWF_KEY, bonus)
                    if (ok1 or ok2) and mark("brute_" .. tostring(k), true) then
                        _ucwfResolved = "brute_" .. tostring(k)
                        return true, "UCWF." .. tostring(k)
                    end
                end
            end
        end
    end

    if type(rawget(_G, "UCWF_SetPlayerTotalFlat")) == "function" then
        local ok = pcall(UCWF_SetPlayerTotalFlat, player, UCWF_KEY, bonus)
        if mark("UCWF_SetPlayerTotalFlat", ok) and ok then
            _ucwfResolved = "UCWF_SetPlayerTotalFlat"
            return true, "UCWF_SetPlayerTotalFlat"
        end
    end

    if not ucwfPresent() then
        _ucwfResolved = "none"
        return false, "ucwf_not_loaded"
    end
    -- Present but no working call this tick — caller validates weight; may set give-up
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

    local function readMax()
        local w = -1
        pcall(function()
            if type(player.getMaxWeight) == "function" then
                w = tonumber(player:getMaxWeight()) or -1
            end
        end)
        return w
    end
    local function readBonus()
        local b = 0
        pcall(function()
            if type(player.getMaxWeightBonus) == "function" then
                b = tonumber(player:getMaxWeightBonus()) or 0
            end
        end)
        return b
    end

    local before = readMax()
    local method = "none"
    local after = before

    -- Always apply DIY MaxWeightBonus first (works without UCWF; UCWF may stack or own calc)
    local diyMethod, _, diyAfter = applyDIYCarry(player, data, wantBonus)
    method = diyMethod or "none"
    after = diyAfter or readMax()

    -- Try UCWF only until we know it works or give up (no per-tick require spam)
    if wantBonus > 0 and not _ucwfGiveUp then
        local beforeUc = readMax()
        local ucwfOk, ucwfHow = applyUCWF(player, wantBonus)
        if ucwfOk then
            local afterUc = readMax()
            if afterUc >= (beforeUc + math.max(0.5, wantBonus * 0.5)) then
                method = tostring(ucwfHow) .. "+diy"
                after = afterUc
            else
                -- No-op API — stop hammering UCWF this session
                _ucwfGiveUp = true
                _ucwfResolved = "none"
                method = diyMethod .. "|ucwf_noop:" .. tostring(ucwfHow)
                after = readMax()
                print("[KnoxSystem] UCWF call did not raise maxWeight — using DIY only")
            end
        else
            method = diyMethod .. "|" .. tostring(ucwfHow)
            if tostring(ucwfHow or ""):find("ucwf_api_unknown", 1, true)
                or tostring(ucwfHow or "") == "ucwf_not_loaded"
                or tostring(ucwfHow or "") == "ucwf_skip" then
                _ucwfGiveUp = true
                _ucwfResolved = "none"
                if tostring(ucwfHow or ""):find("unknown", 1, true) then
                    print("[KnoxSystem] UCWF present but API unknown — using DIY only")
                end
            end
            -- Re-assert DIY / force if framework overwrites
            if tostring(ucwfHow or ""):find("ucwf", 1, true) then
                pcall(function()
                    if type(player.setMaxWeightBonus) == "function" then
                        local others = readBonus() - (tonumber(data._knoxPowerWeightBonus) or 0)
                        if others < 0 then others = 0 end
                        player:setMaxWeightBonus(others + wantBonus)
                        data._knoxPowerWeightBonus = wantBonus
                    end
                    local now = readMax()
                    if wantBonus > 0 and before > 0 and now < before + wantBonus * 0.5 then
                        if type(player.setMaxWeight) == "function" then
                            player:setMaxWeight(before + wantBonus)
                            method = method .. "|force_setMaxWeight"
                        end
                    end
                end)
                after = readMax()
            end
        end
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
                maxWeightBonus = readBonus(),
                ucwfPresent = ucwfPresent() and 1 or 0,
                method = method,
                note = "DIY MaxWeightBonus always; UCWF only if maxWeight actually rises",
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

-- -------- Combat: damage (weapons) + knock/stagger reroll (weapons + failed shove) --------
-- Damage: +10% of hit damage * PowerLv (not bare hands, not ranged)
-- Knock: only if vanilla did NOT already stagger/knock this hit ("failed" control)
--   knockChance = 2*Power + 0.4*Strength
--   stagger if roll in [knockChance, knockChance+13)
local function readControlFlags(target)
    -- returns knockedDown, staggerBack as 0/1, or -1 if API missing
    local kd, st = -1, -1
    pcall(function()
        if target and target.isKnockedDown then
            kd = target:isKnockedDown() and 1 or 0
        end
    end)
    pcall(function()
        if target and target.isStaggerBack then
            st = target:isStaggerBack() and 1 or 0
        end
    end)
    return kd, st
end

local function logPowerCombat(fields)
    if not KnoxSystem.Track then return end
    if KnoxSystem.Track.isChannelOn("strength_apply") then
        KnoxSystem.Track.log("strength_apply", fields.reason or "power_hit", fields)
    elseif KnoxSystem.Track.isChannelOn("power") then
        KnoxSystem.Track.log("power", fields.reason or "power_hit", fields)
    elseif KnoxSystem.Track.isChannelOn("damage") then
        KnoxSystem.Track.log("damage", fields.reason or "power_hit", fields)
    end
end

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

    -- Ranged: no Power damage / knock
    local ranged = false
    pcall(function()
        if weapon and weapon.isRanged and weapon:isRanged() then ranged = true end
    end)
    if ranged then return end

    local bare = false
    pcall(function()
        if weapon and weapon.isBareHands and weapon:isBareHands() then bare = true end
        if not bare and weapon and weapon.getFullType then
            local ft = string.lower(tostring(weapon:getFullType() or ""))
            if ft:find("barehands", 1, true) then bare = true end
        end
        if not weapon then bare = true end -- nil weapon ≈ shove/unarmed
    end)

    local dmg = tonumber(damage) or 0
    local bonus = 0
    local hpBefore, hpAfter = -1, -1

    -- Vanilla control BEFORE our reroll (engine usually already applied this frame)
    local vanillaKD, vanillaStagger = readControlFlags(target)
    local vanillaControlled = (vanillaKD == 1) or (vanillaStagger == 1)

    -- 1) Damage bonus: weapons only, scales 10% per Power level
    if (not bare) and dmg > 0 then
        bonus = dmg * MELEE_BONUS_PER_LEVEL * pow
        if bonus > 0 then
            pcall(function()
                if target.getHealth then hpBefore = tonumber(target:getHealth()) or -1 end
                local nh = hpBefore - bonus
                if nh < 0 then nh = 0 end
                if target.setHealth then target:setHealth(nh) end
                if target.getHealth then hpAfter = tonumber(target:getHealth()) or nh end
            end)
        end
    end

    -- 2) Compensated knock/stagger reroll if vanilla control failed this hit
    local strReal = KnoxSystem.Power.getStrengthReal(attacker)
    local knockChance, staggerChance, roll = -1, -1, -1
    local rerollAttempted = 0
    local rerollOutcome = "skipped_vanilla_already_controlled"
    local setKnockOk, setStaggerOk = -1, -1

    if not vanillaControlled then
        rerollAttempted = 1
        rerollOutcome = "miss" -- default until roll decides
        knockChance = (KNOCK_PER_POWER * pow) + (KNOCK_PER_STR * strReal)
        staggerChance = knockChance + STAGGER_BAND
        pcall(function()
            if ZombRand then
                roll = ZombRand(100) -- typically 0..99
            else
                roll = math.floor(math.random() * 100)
            end
        end)
        if type(roll) ~= "number" then roll = 0 end

        if roll < knockChance then
            setKnockOk = 0
            local ok = pcall(function()
                if target.setKnockedDown then
                    target:setKnockedDown(true)
                    setKnockOk = 1
                else
                    setKnockOk = -1 -- API missing
                end
            end)
            if not ok then setKnockOk = 0 end
            if setKnockOk == 1 then
                rerollOutcome = "knockdown"
            elseif setKnockOk == -1 then
                rerollOutcome = "knockdown_api_missing"
            else
                rerollOutcome = "knockdown_set_failed"
            end
        elseif roll < staggerChance then
            setStaggerOk = 0
            local ok = pcall(function()
                if target.setStaggerBack then
                    target:setStaggerBack(true)
                    setStaggerOk = 1
                else
                    setStaggerOk = -1
                end
            end)
            if not ok then setStaggerOk = 0 end
            if setStaggerOk == 1 then
                rerollOutcome = "stagger"
            elseif setStaggerOk == -1 then
                rerollOutcome = "stagger_api_missing"
            else
                rerollOutcome = "stagger_set_failed"
            end
        else
            rerollOutcome = "miss"
        end
    end

    -- Final control flags after our attempt (verify setters stuck)
    local finalKD, finalStagger = readControlFlags(target)

    -- Always log control outcome (this is the diagnostic the player asked for).
    -- Slight throttle only to avoid multi-target hit spam same frame.
    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    if not KnoxSystem.Power._lastCtrlLogMs then KnoxSystem.Power._lastCtrlLogMs = 0 end
    local forceLog = (rerollAttempted == 1) or (vanillaControlled) or (bonus > 0)
    if forceLog and (ms - KnoxSystem.Power._lastCtrlLogMs) >= 50 then
        KnoxSystem.Power._lastCtrlLogMs = ms
        logPowerCombat({
            reason = bare and "shove_control" or "melee_power",
            powerLv = pow,
            strengthReal = strReal,
            bareHands = bare and 1 or 0,
            hitDamage = dmg,
            bonusPerLevel = MELEE_BONUS_PER_LEVEL,
            bonusDamage = bonus,
            hpBefore = hpBefore,
            hpAfter = hpAfter,
            -- Vanilla original (pre-reroll)
            vanillaKnockedDown = vanillaKD,
            vanillaStaggerBack = vanillaStagger,
            vanillaControlled = vanillaControlled and 1 or 0,
            -- Reroll
            rerollAttempted = rerollAttempted,
            rerollOutcome = rerollOutcome, -- skipped_vanilla_already_controlled | miss | knockdown | stagger | *_api_missing | *_set_failed
            knockChance = knockChance,
            staggerChance = staggerChance,
            staggerBand = STAGGER_BAND,
            roll = roll,
            setKnockedDownOk = setKnockOk,
            setStaggerBackOk = setStaggerOk,
            -- After reroll
            finalKnockedDown = finalKD,
            finalStaggerBack = finalStagger,
            note = "vanilla KD/stagger T/F + reroll outcome; dmg 10%*Power weapons only",
        })
    end
end

-- -------- Thumpables (doors / windows / fences / barricades): mirror weapon Power bonus --------
-- Same scale as melee: bonus = baseHit * 0.10 * PowerLv
-- baseHit prefers weapon:getDoorDamage(); fallback small constant.
-- No knock/stagger (objects). Bare hands skipped (doorDamage usually 0).
function KnoxSystem.Power.onWeaponHitThumpable(attacker, weapon, thumpable, damageArg)
    if not attacker or not thumpable then return end

    local isP = false
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

    -- Skip characters if mis-routed
    local isChar = false
    pcall(function()
        if instanceof and instanceof(thumpable, "IsoZombie") then isChar = true end
        if instanceof and instanceof(thumpable, "IsoPlayer") then isChar = true end
    end)
    if isChar then return end

    local bare = false
    pcall(function()
        if weapon and weapon.isBareHands and weapon:isBareHands() then bare = true end
        if not bare and weapon and weapon.getFullType then
            local ft = string.lower(tostring(weapon:getFullType() or ""))
            if ft:find("barehands", 1, true) then bare = true end
        end
    end)
    if bare then return end

    local ranged = false
    pcall(function()
        if weapon and weapon.isRanged and weapon:isRanged() then ranged = true end
    end)
    if ranged then return end

    -- Base hit amount this swing (vanilla already applied something; we add Power %)
    local baseHit = tonumber(damageArg) or 0
    if baseHit <= 0 then
        pcall(function()
            if weapon and weapon.getDoorDamage then
                baseHit = tonumber(weapon:getDoorDamage()) or 0
            end
        end)
    end
    if baseHit <= 0 then
        pcall(function()
            if weapon and weapon.getTreeDamage then
                baseHit = tonumber(weapon:getTreeDamage()) or 0
            end
        end)
    end
    if baseHit <= 0 then baseHit = 1 end -- minimal tick so Power still matters on odd weapons

    local bonus = baseHit * MELEE_BONUS_PER_LEVEL * pow
    if bonus <= 0 then return end

    local name = "?"
    local hpBefore, hpAfter = -1, -1
    local method = "none"
    local destroyed = 0

    pcall(function()
        if thumpable.getName then name = tostring(thumpable:getName() or name) end
        if (name == "?" or name == "" or name == "nil") and thumpable.getSprite and thumpable:getSprite() then
            local spr = thumpable:getSprite()
            if spr and spr.getName then name = tostring(spr:getName() or name) end
        end
    end)

    -- Prefer Damage(amount) if present; else setHealth
    pcall(function()
        if thumpable.getHealth then
            hpBefore = tonumber(thumpable:getHealth()) or -1
        elseif thumpable.getThumpCondition then
            hpBefore = tonumber(thumpable:getThumpCondition()) or -1
        end
    end)

    local applied = false
    pcall(function()
        if type(thumpable.Damage) == "function" then
            thumpable:Damage(bonus)
            method = "Damage"
            applied = true
        end
    end)
    if not applied then
        pcall(function()
            if type(thumpable.setHealth) == "function" and hpBefore >= 0 then
                local nh = hpBefore - bonus
                if nh < 0 then nh = 0 end
                thumpable:setHealth(nh)
                method = "setHealth"
                applied = true
            end
        end)
    end
    if not applied then
        pcall(function()
            -- Some IsoThumpable use condition 0..1
            if type(thumpable.setThumpCondition) == "function" and type(thumpable.getThumpCondition) == "function" then
                local c = tonumber(thumpable:getThumpCondition()) or 1
                local maxHp = 100
                pcall(function()
                    if thumpable.getMaxHealth then maxHp = tonumber(thumpable:getMaxHealth()) or maxHp end
                end)
                if maxHp < 1 then maxHp = 100 end
                local hpEst = c * maxHp
                local nh = hpEst - bonus
                if nh < 0 then nh = 0 end
                thumpable:setThumpCondition(nh / maxHp)
                method = "setThumpCondition"
                applied = true
                hpBefore = hpEst
            end
        end)
    end

    pcall(function()
        if thumpable.getHealth then
            hpAfter = tonumber(thumpable:getHealth()) or -1
        elseif thumpable.getThumpCondition and hpBefore >= 0 then
            local maxHp = 100
            pcall(function()
                if thumpable.getMaxHealth then maxHp = tonumber(thumpable:getMaxHealth()) or maxHp end
            end)
            hpAfter = (tonumber(thumpable:getThumpCondition()) or 0) * maxHp
        end
        if thumpable.isDestroyed and thumpable:isDestroyed() then destroyed = 1 end
        if hpAfter == 0 or (hpBefore > 0 and hpAfter >= 0 and hpAfter < hpBefore and hpAfter <= 0.01) then
            -- best-effort
        end
    end)

    -- Throttle object spam
    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    if not KnoxSystem.Power._lastThumpLogMs then KnoxSystem.Power._lastThumpLogMs = 0 end
    if (ms - KnoxSystem.Power._lastThumpLogMs) >= 100 then
        KnoxSystem.Power._lastThumpLogMs = ms
        logPowerCombat({
            reason = "thump_power",
            powerLv = pow,
            object = name,
            baseHit = baseHit,
            bonusPerLevel = MELEE_BONUS_PER_LEVEL,
            bonusDamage = bonus,
            hpBefore = hpBefore,
            hpAfter = hpAfter,
            method = method,
            applied = applied and 1 or 0,
            destroyed = destroyed,
            note = "Power thumpable mirror: +10%*Power of door/tree damage onto object HP",
        })
    end
end

-- Trees: same Power % using tree damage as base
function KnoxSystem.Power.onWeaponHitTree(attacker, weapon, ...)
    if not attacker then return end
    local isP = false
    pcall(function()
        if instanceof and instanceof(attacker, "IsoPlayer") then isP = true end
    end)
    if not isP then return end
    local pow = KnoxSystem.Power.level(attacker)
    if pow < 1 then return end

    -- Tree HP is often not exposed the same way; log intended bonus for now + try Damage on arg
    local baseHit = 0
    pcall(function()
        if weapon and weapon.getTreeDamage then baseHit = tonumber(weapon:getTreeDamage()) or 0 end
    end)
    if baseHit <= 0 then
        pcall(function()
            if weapon and weapon.getDoorDamage then baseHit = tonumber(weapon:getDoorDamage()) or 0 end
        end)
    end
    if baseHit <= 0 then baseHit = 1 end
    local bonus = baseHit * MELEE_BONUS_PER_LEVEL * pow

    -- Optional: first extra arg might be square/tree object on some builds
    local treeObj = select(1, ...)
    local applied = 0
    pcall(function()
        if treeObj and type(treeObj.Damage) == "function" then
            treeObj:Damage(bonus)
            applied = 1
        end
    end)

    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    if not KnoxSystem.Power._lastTreeLogMs then KnoxSystem.Power._lastTreeLogMs = 0 end
    if (ms - KnoxSystem.Power._lastTreeLogMs) >= 200 then
        KnoxSystem.Power._lastTreeLogMs = ms
        logPowerCombat({
            reason = "tree_power",
            powerLv = pow,
            baseHit = baseHit,
            bonusDamage = bonus,
            applied = applied,
            note = "Power tree bonus (best-effort; engine tree HP may ignore Lua)",
        })
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
            meleeBonusPerLevel = MELEE_BONUS_PER_LEVEL,
            knockPerPower = KNOCK_PER_POWER,
            knockPerStr = KNOCK_PER_STR,
            staggerBand = STAGGER_BAND,
            ucwfPresent = ucwfPresent() and 1 or 0,
            note = "Power: +1 carry/lv; dmg 10%*Power weapons+thumpables; knock reroll +stagger13 if vanilla failed; no Strength hook",
            liveApplied = (pow > 0) and 1 or 0,
        })
    end
end

print("[KnoxSystem] KS_Power loaded (carry+1/lv, dmg 10%*Power melee+thump, knock reroll, no Strength hook)")
