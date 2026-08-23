-- Personal Power (System tab only, max 10 @ 2 SP)
-- Design ≥0.5.139:
--   NO getPerkLevel(Strength) hook
--   Carry: +1 max weight per Power level (UCWF if present, else MaxWeightBonus)
--   Melee dmg: +10% of hit * PowerLv (weapons only, not ranged/shove)
--   Thumpables/trees: same % using door/tree damage as base
--   Knock/stagger reroll if vanilla failed: chance = 2*Power + 0.4*Str; stagger band +13
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Sandbox"

KnoxSystem.Power = KnoxSystem.Power or {}

local POWER_MAX = 10
local CARRY_PER_LEVEL = 1.0          -- +1 weight unit per Power rank (not sandboxed yet — ask before adding option)
local STAGGER_BAND = 13              -- not sandboxed yet
local KNOCK_PER_STR = 0.4            -- not sandboxed yet

local function meleeBonusPerLevel()
    if KnoxSystem.Sandbox and KnoxSystem.Sandbox.powerMeleeBonusPerLevel then
        return KnoxSystem.Sandbox.powerMeleeBonusPerLevel()
    end
    return 0.10
end

local function knockPerPower()
    if KnoxSystem.Sandbox and KnoxSystem.Sandbox.powerKnockPointsPerLevel then
        return KnoxSystem.Sandbox.powerKnockPointsPerLevel()
    end
    return 2.0
end

local UCWF_MOD_ID = "UnifiedCarryWeightFramework"
local UCWF_KEY = "KnoxSystem_Power"

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

-- -------- Carry (+1 per Power) via UCWF author format + layered DIY --------
-- Author client pattern (MusicManiac UCWF):
--   require("UnifiedCarryWeightFramework"); UnifiedCarryWeightFramework.recomputeAll()  [SP]
--   sendClientCommand(player, "UCWF", "update_weight", {})  [MP_Client]
-- We were NOT on that format before (wrong require paths / guessed APIs).
local _carryLogMs = 0
local _ucwfLoadTried = false
local _ucwfFw = nil           -- UnifiedCarryWeightFramework table after require
local _ucwfRegistered = false
local _ucwfRegHow = "none"
local _lastRecomputePow = -999
local _recomputeCooldownMs = 0

local function knoxGameMode()
    -- Author-identical branching
    local ok, mode = pcall(function()
        if not isClient() and not isServer() then
            return "SP"
        elseif isClient() then
            return "MP_Client"
        end
        return "MP_Server"
    end)
    if ok and mode then return mode end
    return "SP"
end

local function ucwfModActive()
    local ok = false
    local foundId = nil
    pcall(function()
        if not getActivatedMods then return end
        local mods = getActivatedMods()
        if not mods then return end

        -- One-time dump so we can see the exact mod id string UCWF uses
        if not KnoxSystem.Power._modListLogged then
            KnoxSystem.Power._modListLogged = true
            local ids = {}
            pcall(function()
                if mods.size then
                    for i = 0, mods:size() - 1 do
                        ids[#ids + 1] = tostring(mods:get(i) or "")
                    end
                end
            end)
            -- ArrayList / table fallbacks
            pcall(function()
                if #ids == 0 and type(mods) == "table" then
                    for k, v in pairs(mods) do
                        ids[#ids + 1] = tostring(v) .. (type(k) ~= "number" and ("@" .. tostring(k)) or "")
                    end
                end
            end)
            pcall(function()
                if mods.toString then
                    print("[KnoxSystem] getActivatedMods(): " .. tostring(mods:toString()))
                end
            end)
            if #ids > 0 then
                print("[KnoxSystem] Activated mods (" .. tostring(#ids) .. "): " .. table.concat(ids, " | "))
            else
                print("[KnoxSystem] Activated mods: (could not enumerate; type=" .. type(mods) .. ")")
            end
        end

        local function matchId(id)
            if not id then return false end
            local s = tostring(id)
            local low = s:lower():gsub("%s+", "")
            -- Match workshop id / folder-ish names
            if low == "unifiedcarryweightframework" then return true end
            if low == "ucwf" then return true end
            if low:find("unifiedcarryweight", 1, true) then return true end
            if low:find("unifiedcarry", 1, true) then return true end
            if low:find("ucwf", 1, true) then return true end
            return false
        end

        if mods.contains then
            -- Exact ids commonly used
            local candidates = {
                "UnifiedCarryWeightFramework",
                "UCWF",
                "Unified Carry Weight Framework",
            }
            for i = 1, #candidates do
                local c = candidates[i]
                local hit = false
                pcall(function() hit = mods:contains(c) and true or false end)
                if hit then ok = true; foundId = c; break end
            end
        end

        if not ok and mods.size then
            local n = mods:size()
            for i = 0, n - 1 do
                local id = nil
                pcall(function() id = mods:get(i) end)
                if matchId(id) then ok = true; foundId = tostring(id); break end
            end
        end
    end)

    if not ok then
        pcall(function()
            if type(rawget(_G, "UnifiedCarryWeightFramework")) == "table" then
                ok = true
                foundId = "global:UnifiedCarryWeightFramework"
            end
        end)
    end

    if ok and not KnoxSystem.Power._ucwfActiveLogged then
        KnoxSystem.Power._ucwfActiveLogged = true
        print("[KnoxSystem] UCWF detected as active via: " .. tostring(foundId))
    end
    return ok
end

--- Load framework once. Author path require often FAILS in B42 even when mod is loaded
--- (file already executed as a script, not a module). Prefer globals + package.loaded scan.
local function getUCWF()
    if _ucwfLoadTried then return _ucwfFw end
    _ucwfLoadTried = true

    if knoxGameMode() == "MP_Server" then
        print("[KnoxSystem] UCWF glue: MP_Server — skip client require")
        return nil
    end

    local function accept(name, obj)
        if type(obj) == "table" then
            _ucwfFw = obj
            print("[KnoxSystem] UCWF table found via " .. tostring(name))
            return true
        end
        return false
    end

    -- 1) Known globals (note: their client log uses "United" typo once)
    local globalNames = {
        "UnifiedCarryWeightFramework",
        "UnitedCarryWeightFramework",
        "UnitedCarryWeightFramework_Client",
        "UCWF",
        "UCWF_API",
    }
    for i = 1, #globalNames do
        local n = globalNames[i]
        if accept("global:" .. n, rawget(_G, n)) then break end
    end

    -- 2) package.loaded scan (no new require WARN)
    if not _ucwfFw then
        pcall(function()
            local loaded = package and package.loaded
            if type(loaded) ~= "table" then return end
            for k, v in pairs(loaded) do
                local lk = string.lower(tostring(k))
                if type(v) == "table" and (
                    lk:find("unifiedcarry", 1, true)
                    or lk:find("unitedcarry", 1, true)
                    or lk:find("ucwf", 1, true)
                    or lk:find("carryweight", 1, true)
                ) then
                    if accept("package.loaded:" .. tostring(k), v) then return end
                end
            end
        end)
    end

    -- 3) Soft require once — only paths that match author / workshop file name
    --    (failed require WARNs once; _ucwfLoadTried prevents spam)
    if not _ucwfFw then
        local paths = {
            "UnifiedCarryWeightFramework",
            "shared/UnifiedCarryWeightFramework",
            "UnitedCarryWeightFramework",
            "UnitedCarryWeightFramework_Client",
        }
        for i = 1, #paths do
            local ok, res = pcall(function() return require(paths[i]) end)
            if ok and accept("require:" .. paths[i], res) then break end
            if not ok then
                -- global may still be set as side effect of a partial load
                if accept("post-require-global", rawget(_G, "UnifiedCarryWeightFramework")) then break end
            end
        end
    end

    -- 4) Brute scan _G once for tables with recomputeAll
    if not _ucwfFw then
        pcall(function()
            for k, v in pairs(_G) do
                if type(v) == "table" and type(v.recomputeAll) == "function" then
                    local lk = string.lower(tostring(k))
                    if lk:find("carry", 1, true) or lk:find("ucwf", 1, true) or lk:find("weight", 1, true) then
                        if accept("scan:" .. tostring(k), v) then return end
                    end
                end
            end
        end)
    end

    if type(_ucwfFw) == "table" then
        local keys = {}
        for k, v in pairs(_ucwfFw) do
            keys[#keys + 1] = tostring(k) .. "=" .. type(v)
        end
        table.sort(keys)
        print("[KnoxSystem] UCWF loaded keys: " .. table.concat(keys, ", "))
    else
        print("[KnoxSystem] UCWF: no framework table (require failed / no global). DIY uses maxWeightBase.")
        _ucwfFw = nil
    end
    return _ucwfFw
end

--- Best-effort: register +1*Power as a total flat bonus provider (names vary by UCWF version).
local function ensureUCWFRegistration(fw)
    if _ucwfRegistered or type(fw) ~= "table" then return end
    _ucwfRegistered = true

    local function powerBonusFor(_player)
        local p = _player
        if not p and getPlayer then p = getPlayer() end
        if not p then return 0 end
        return KnoxSystem.Power.level(p) * CARRY_PER_LEVEL
    end

    local tried = {}
    local function try(name, fn)
        local ok = pcall(fn)
        tried[#tried + 1] = name .. (ok and "=ok" or "=no")
        if ok then
            _ucwfRegHow = name
            print("[KnoxSystem] UCWF register via " .. name)
            return true
        end
        return false
    end

    -- Dynamic provider patterns
    if type(fw.addModifier) == "function" then
        if try("addModifier_fn", function()
            fw.addModifier(UCWF_KEY, function(player)
                return { totalFlat = powerBonusFor(player), totalMult = 1, baseFlat = 0, baseMult = 1 }
            end)
        end) then return end
        if try("addModifier_num", function()
            fw.addModifier(UCWF_KEY, powerBonusFor(getPlayer and getPlayer() or nil))
        end) then return end
    end
    if type(fw.registerModifier) == "function" then
        if try("registerModifier", function()
            fw.registerModifier(UCWF_KEY, function(player)
                return { totalFlat = powerBonusFor(player) }
            end)
        end) then return end
    end
    if type(fw.addTotalFlat) == "function" then
        if try("addTotalFlat", function()
            fw.addTotalFlat(UCWF_KEY, powerBonusFor(getPlayer and getPlayer() or nil))
        end) then return end
    end
    if type(fw.setTotalFlat) == "function" then
        if try("setTotalFlat", function()
            fw.setTotalFlat(UCWF_KEY, powerBonusFor(getPlayer and getPlayer() or nil))
        end) then return end
    end
    if type(fw.SetModifier) == "function" then
        if try("SetModifier", function()
            fw.SetModifier(UCWF_KEY, { totalFlat = powerBonusFor(getPlayer and getPlayer() or nil) })
        end) then return end
    end
    if type(fw.addBonus) == "function" then
        if try("addBonus", function()
            fw.addBonus(UCWF_KEY, powerBonusFor(getPlayer and getPlayer() or nil), "total")
        end) then return end
    end
    if type(fw.registerBonus) == "function" then
        if try("registerBonus", function()
            fw.registerBonus(UCWF_KEY, powerBonusFor)
        end) then return end
    end

    -- Table slot patterns
    if type(fw.modifiers) == "table" then
        if try("modifiers_table", function()
            fw.modifiers[UCWF_KEY] = function(player)
                return { totalFlat = powerBonusFor(player) }
            end
        end) then return end
    end
    if type(fw.bonuses) == "table" then
        if try("bonuses_table", function()
            fw.bonuses[UCWF_KEY] = powerBonusFor
        end) then return end
    end

    print("[KnoxSystem] UCWF register failed (" .. table.concat(tried, ",") .. ") — will layer after recomputeAll")
    _ucwfRegHow = "layer_after_recompute"
end

--- Update registered static bonus values when Power changes (for non-function APIs).
local function pushUCWFBonusValue(fw, bonus)
    if type(fw) ~= "table" then return end
    pcall(function()
        if type(fw.setTotalFlat) == "function" then fw.setTotalFlat(UCWF_KEY, bonus) end
        if type(fw.addTotalFlat) == "function" then fw.addTotalFlat(UCWF_KEY, bonus) end
        if type(fw.SetModifier) == "function" then fw.SetModifier(UCWF_KEY, { totalFlat = bonus }) end
        if type(fw.setModifier) == "function" then fw.setModifier(UCWF_KEY, { totalFlat = bonus }) end
        if type(fw.addBonus) == "function" then fw.addBonus(UCWF_KEY, bonus, "total") end
    end)
end

--- Author recompute path (SP direct / MP client command). Throttled + on Power change.
local function ucwfRecompute(player, pow)
    local mode = knoxGameMode()
    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    local powerChanged = (pow ~= _lastRecomputePow)
    local due = (ms - _recomputeCooldownMs) > 2000
    if not powerChanged and not due then return "throttled" end
    _lastRecomputePow = pow
    _recomputeCooldownMs = ms

    if mode == "SP" then
        local fw = getUCWF()
        if fw and type(fw.recomputeAll) == "function" then
            ensureUCWFRegistration(fw)
            pushUCWFBonusValue(fw, pow * CARRY_PER_LEVEL)
            local ok = pcall(function() fw.recomputeAll() end)
            if ok then return "recomputeAll" end
            return "recomputeAll_fail"
        end
        return "no_fw"
    elseif mode == "MP_Client" then
        local ok = pcall(function()
            local p = player
            if sendClientCommand then
                sendClientCommand(p, "UCWF", "update_weight", {})
            end
        end)
        return ok and "sendClientCommand" or "send_fail"
    end
    return "server_skip"
end

--- DIY carry — exact +1 final capacity per Power level.
--- B42 BodyDamage each tick:
---   setMaxWeight( (int)(getMaxWeightBase() * getWeightMod()) - injury )
---   then * maxWeightDelta for IsoPlayer
--- So we freeze vanilla maxWeightBase once, then set base so floor(base*wmod) lands on
--- natural + Power, and also setMaxWeight(target) every tick for UI consistency.
local CARRY_HARD_CAP = 100
local CARRY_SANE_MAX = 50

local function clampNum(n, lo, hi, fallback)
    n = tonumber(n)
    if n == nil or n ~= n then return fallback end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function applyLayeredCarry(player, data, bonus)
    local method = "none"
    local before, after = -1, -1
    bonus = clampNum(bonus, 0, POWER_MAX * CARRY_PER_LEVEL, 0)
    bonus = math.floor(bonus + 1e-6) -- whole pounds only

    local function readMax()
        local w = -1
        pcall(function() w = tonumber(player:getMaxWeight()) or -1 end)
        return w
    end
    local function readBase()
        local b = -1
        pcall(function()
            if player.getMaxWeightBase then b = tonumber(player:getMaxWeightBase()) or -1 end
        end)
        return b
    end
    local function readWeightMod()
        local m = 1
        pcall(function()
            if player.getWeightMod then m = tonumber(player:getWeightMod()) or 1 end
        end)
        if not m or m < 0.05 then m = 1 end
        return m
    end
    local function readDelta()
        local d = 1
        pcall(function()
            if player.getMaxWeightDelta then d = tonumber(player:getMaxWeightDelta()) or 1 end
        end)
        if not d or d < 0.05 then d = 1 end
        return d
    end

    if not KnoxSystem.Power._carryApiLogged then
        KnoxSystem.Power._carryApiLogged = true
        print(string.format(
            "[KnoxSystem] Carry snapshot: max=%s base=%s wmod=%s delta=%s",
            tostring(readMax()), tostring(readBase()), tostring(readWeightMod()), tostring(readDelta())
        ))
    end

    before = readMax()
    if before > CARRY_HARD_CAP then
        -- scrub old overflow
        pcall(function()
            if player.setMaxWeightBase and data._knoxCarryOrigBase then
                player:setMaxWeightBase(data._knoxCarryOrigBase)
            end
            if player.setMaxWeight then player:setMaxWeight(20) end
        end)
        data._knoxCarryBaseBoost = nil
        data._knoxPowerWeightBonus = 0
        before = readMax()
        method = "emergency_reset"
    end

    local wmod = readWeightMod()
    local delta = readDelta()
    local curBase = readBase()

    -- Freeze original base ONLY while unboosted / first time
    if not data._knoxCarryOrigBase or data._knoxCarryOrigBase < 1 then
        data._knoxCarryOrigBase = clampNum(curBase > 0 and curBase or 8, 1, CARRY_HARD_CAP, 8)
    end

    -- Vanilla final capacity estimate (no Power), matching engine casts as closely as possible
    -- maxWeight = (int)(base * wmod); then (int)(maxWeight * delta)
    local function finalFromBase(base)
        local m = math.floor(base * wmod + 1e-6)
        if m < 0 then m = 0 end
        m = math.floor(m * delta + 1e-6)
        return m
    end

    local natural = finalFromBase(data._knoxCarryOrigBase)
    if natural < 1 then
        -- Fallback: current max minus last applied bonus
        natural = math.max(1, math.floor((before > 0 and before or 20) - (tonumber(data._knoxPowerWeightBonus) or 0)))
    end

    local target = natural + bonus
    target = clampNum(target, 1, CARRY_SANE_MAX, natural)

    -- Invert: find base B such that finalFromBase(B) == target (search small window)
    local newBase = data._knoxCarryOrigBase
    if bonus > 0 then
        -- Ideal continuous solution before floor: target/delta/wmod
        local ideal = target / (delta * wmod)
        newBase = ideal
        -- Nudge until floor math hits target (or as close as possible)
        local bestB, bestErr = ideal, 999
        for step = -20, 20 do
            local b = ideal + step * 0.01
            if b < 1 then b = 1 end
            local f = finalFromBase(b)
            local err = math.abs(f - target)
            if err < bestErr then
                bestErr = err
                bestB = b
                if err == 0 then break end
            end
        end
        newBase = bestB
    end
    newBase = clampNum(newBase, 1, CARRY_HARD_CAP, data._knoxCarryOrigBase)

    pcall(function()
        if not player.setMaxWeightBase then return end
        player:setMaxWeightBase(newBase)
        method = "setMaxWeightBase"
    end)

    -- Force displayed/final max every tick (BodyDamage may have already run this frame)
    pcall(function()
        if not player.setMaxWeight then return end
        player:setMaxWeight(target)
        method = method == "none" and "setMaxWeight" or (method .. "+setMaxWeight")
    end)

    after = readMax()

    if bonus <= 0 then
        pcall(function()
            if player.setMaxWeightBase and data._knoxCarryOrigBase then
                player:setMaxWeightBase(data._knoxCarryOrigBase)
            end
        end)
        data._knoxPowerWeightBonus = 0
        data._knoxPowerWeightAppliedOk = true
        after = readMax()
        method = method .. "|clear"
    else
        data._knoxPowerWeightBonus = bonus
        data._knoxPowerWeightAppliedOk = (after >= target - 0.1)
        if not data._knoxPowerWeightAppliedOk then
            method = method .. "|STUCK_READBACK"
        end
        method = method .. string.format("|nat=%d tgt=%d", natural, target)
    end

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

    -- 1) Author UCWF recompute (SP / MP client)
    local rc = ucwfRecompute(player, pow)

    -- 2) Always layer +Power after recompute (UCWF may wipe DIY; we re-apply)
    local method, b2, after = applyLayeredCarry(player, data, wantBonus)
    if b2 >= 0 then before = b2 end
    method = method .. "|ucwf:" .. tostring(rc) .. "|reg:" .. tostring(_ucwfRegHow)

    local ms = 0
    if getTimestampMs then pcall(function() ms = getTimestampMs() or 0 end) end
    if ms - _carryLogMs > 4000 then
        _carryLogMs = ms
        local mode = knoxGameMode()
        if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("strength_apply") then
            KnoxSystem.Track.log("strength_apply", "carry", {
                reason = "carry",
                powerLv = pow,
                ourBonus = wantBonus,
                perLevel = CARRY_PER_LEVEL,
                maxWeightBefore = before,
                maxWeightAfter = after,
                gameMode = mode,
                ucwfMod = ucwfModActive() and 1 or 0,
                method = method,
                note = "UCWF author recomputeAll + layered +1/Power",
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

--- Call when Power is bought (immediate recompute).
function KnoxSystem.Power.onPowerChanged(player)
    _lastRecomputePow = -999
    KnoxSystem.Power.syncCarry(player)
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

--- True shove / unarmed push (no Analyze plate, no Power weapon snip).
--- Note: shove with a weapon equipped still often reports that weapon in the event.
function KnoxSystem.Power.isShoveHit(attacker, weapon, damage)
    local shove = false
    pcall(function()
        if attacker and attacker.isDoShove and attacker:isDoShove() then shove = true end
    end)
    pcall(function()
        if attacker and attacker.getVariableBoolean then
            if attacker:getVariableBoolean("bShove") then shove = true end
            if attacker:getVariableBoolean("bDoShove") then shove = true end
            if attacker:getVariableBoolean("ShoveAnim") then shove = true end
            if attacker:getVariableBoolean("bShoveAiming") then shove = true end
        end
    end)
    pcall(function()
        if attacker and attacker.getVariableString then
            local st = string.lower(tostring(attacker:getVariableString("AttackType") or ""))
            if st:find("shove", 1, true) then shove = true end
            local an = string.lower(tostring(attacker:getVariableString("AttackAnim") or ""))
            if an:find("shove", 1, true) then shove = true end
        end
    end)
    pcall(function()
        if not weapon then shove = true end
        if weapon and weapon.isBareHands and weapon:isBareHands() then shove = true end
        if weapon and weapon.getFullType then
            local ft = string.lower(tostring(weapon:getFullType() or ""))
            if ft:find("barehands", 1, true) then shove = true end
        end
        if weapon and weapon.getSwingAnim then
            local a = string.lower(tostring(weapon:getSwingAnim() or ""))
            if a:find("shove", 1, true) then shove = true end
        end
    end)
    local dmg = tonumber(damage)
    if dmg ~= nil and dmg <= 0 then
        shove = true
    end
    return shove
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
    if pow < 1 then
        KnoxSystem.Power._lastHitWasShove = false
        KnoxSystem.Power._lastHitBonusDamage = 0
        return
    end

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

    local shove = KnoxSystem.Power.isShoveHit(attacker, weapon, damage)
    local bare = shove
    pcall(function()
        if weapon and weapon.isBareHands and weapon:isBareHands() then bare = true end
        if not bare and weapon and weapon.getFullType then
            local ft = string.lower(tostring(weapon:getFullType() or ""))
            if ft:find("barehands", 1, true) then bare = true end
        end
        if not weapon then bare = true end
    end)

    KnoxSystem.Power._lastHitWasShove = shove and true or false
    KnoxSystem.Power._lastHitBonusDamage = 0
    KnoxSystem.Power._lastHitEventDamage = tonumber(damage) or 0

    local dmg = tonumber(damage) or 0
    local bonus = 0
    local hpBefore, hpAfter = -1, -1

    local vanillaKD, vanillaStagger = readControlFlags(target)
    local vanillaControlled = (vanillaKD == 1) or (vanillaStagger == 1)

    -- 1) Damage bonus: weapons only (not shove / bare)
    if (not bare) and (not shove) and dmg > 0 then
        bonus = dmg * meleeBonusPerLevel() * pow
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
    KnoxSystem.Power._lastHitBonusDamage = bonus or 0
    KnoxSystem.Power._lastHitEventDamage = dmg

    -- 2) Compensated knock/stagger reroll if vanilla control failed this hit
    local strReal = KnoxSystem.Power.getStrengthReal(attacker)
    local knockChance, staggerChance, roll = -1, -1, -1
    local rerollAttempted = 0
    local rerollOutcome = "skipped_vanilla_already_controlled"
    local setKnockOk, setStaggerOk = -1, -1

    if not vanillaControlled then
        -- Skip Power knock/stagger if Relentless/Anchored (or elite KD immune)
        local immuneKd, immuneSt = false, false
        pcall(function()
            if KnoxSystem.Modifiers and KnoxSystem.Modifiers.getCombatBundle then
                local b = KnoxSystem.Modifiers.getCombatBundle(target)
                if b then
                    immuneKd = b.knockdown_immune and true or false
                    -- Relentless is KD-only; still allow Power stagger. Anchored blocks both.
                    immuneSt = (b.stagger_immune or b.knockback_immune) and true or false
                end
            end
        end)
        if immuneKd and immuneSt then
            rerollAttempted = 0
            rerollOutcome = "skipped_mod_immune"
        else
        rerollAttempted = 1
        rerollOutcome = "miss" -- default until roll decides
        knockChance = (knockPerPower() * pow) + (KNOCK_PER_STR * strReal)
        staggerChance = knockChance + STAGGER_BAND
        pcall(function()
            if ZombRand then
                roll = ZombRand(100) -- typically 0..99
            else
                roll = math.floor(math.random() * 100)
            end
        end)
        if type(roll) ~= "number" then roll = 0 end

        if (not immuneKd) and roll < knockChance then
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
        elseif (not immuneSt) and roll < staggerChance then
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
            rerollOutcome = immuneKd and "miss_kd_immune" or "miss"
        end
        end
    end

    -- Final control veto: KD immune and/or Anchored full lock
    pcall(function()
        if not KnoxSystem.Modifiers then return end
        if KnoxSystem.Modifiers.isKnockdownImmune and KnoxSystem.Modifiers.isKnockdownImmune(target) then
            if KnoxSystem.Modifiers.forceNoKnockdown then
                KnoxSystem.Modifiers.forceNoKnockdown(target, false)
            end
        end
        if KnoxSystem.Modifiers.isControlLocked and KnoxSystem.Modifiers.isControlLocked(target) then
            if KnoxSystem.Modifiers.forceNoStagger then
                KnoxSystem.Modifiers.forceNoStagger(target, false)
            end
        end
    end)

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
            bonusPerLevel = meleeBonusPerLevel(),
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

    local bonus = baseHit * meleeBonusPerLevel() * pow
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
            bonusPerLevel = meleeBonusPerLevel(),
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
    local bonus = baseHit * meleeBonusPerLevel() * pow

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
            meleeBonusPerLevel = meleeBonusPerLevel(),
            knockPerPower = knockPerPower(),
            knockPerStr = KNOCK_PER_STR,
            staggerBand = STAGGER_BAND,
            ucwfPresent = ucwfModActive() and 1 or 0,
            note = "Power: +1 carry/lv; dmg 10%*Power weapons+thumpables; knock reroll +stagger13 if vanilla failed; no Strength hook",
            liveApplied = (pow > 0) and 1 or 0,
        })
    end
end

print("[KnoxSystem] KS_Power loaded (carry UCWF author format + layer; dmg 10%*Power; knock reroll; no Strength hook)")
