-- KnoxSystem Personal Stat effects + TrackLog snapshots (Strength / Endurance-Stamina)
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Stats = KnoxSystem.Stats or {}

local MAG = 0.05 -- +5% per level draft (design/stats.yaml)

local lastStaminaLog = {}
local lastEndurance = {}
local lastEnduranceT = {}
-- Quiet by default: 10s idle, 4s when moving/sprint/charge
local STAMINA_IDLE_MS = 10000
local STAMINA_ACTIVE_MS = 4000

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return t or 0
end

local function perkLevel(player, perkName)
    local lvl = nil
    pcall(function()
        if not Perks or not player or type(player.getPerkLevel) ~= "function" then return end
        local p = Perks[perkName] or Perks[string.upper(perkName)] or Perks[string.lower(perkName)]
        if p == nil and PerkFactory and PerkFactory.Perks then
            p = PerkFactory.Perks[perkName]
        end
        if p ~= nil then
            lvl = tonumber(player:getPerkLevel(p))
        end
    end)
    return lvl
end

local function tryEndurance(player)
    local v = nil
    pcall(function()
        local st = player:getStats()
        if not st then return end
        if type(st.getEndurance) == "function" then v = tonumber(st:getEndurance()) end
        if v == nil and type(st.getPcEndurance) == "function" then v = tonumber(st:getPcEndurance()) end
        if v == nil and CharacterStat and type(st.get) == "function" then
            local cs = CharacterStat.ENDURANCE or CharacterStat.Endurance
            if cs then v = tonumber(st:get(cs)) end
        end
    end)
    return v
end

--- Vanilla Endurance is a 0–1 CharacterStat (max is fixed at 1.0; Fitness changes drain/regen, not pool size).
local function tryEnduranceMax(player)
    local mx = 1.0
    pcall(function()
        if CharacterStat and CharacterStat.ENDURANCE and CharacterStat.ENDURANCE.getMaximumValue then
            mx = tonumber(CharacterStat.ENDURANCE:getMaximumValue()) or 1.0
        end
    end)
    -- Some builds expose getMaxEndurance — try without assuming it exists
    pcall(function()
        local st = player and player:getStats()
        if st and type(st.getMaxEndurance) == "function" then
            local m = tonumber(st:getMaxEndurance())
            if m and m > 0 then mx = m end
        end
    end)
    pcall(function()
        if player and type(player.getMaxEndurance) == "function" then
            local m = tonumber(player:getMaxEndurance())
            if m and m > 0 then mx = m end
        end
    end)
    return mx
end

local function tryFatigue(player)
    local v = nil
    pcall(function()
        local st = player:getStats()
        if st and type(st.getFatigue) == "function" then v = tonumber(st:getFatigue()) end
    end)
    return v
end

local function enduranceMoodle(player)
    local lvl = 0
    pcall(function()
        local moodles = player:getMoodles()
        if not moodles or type(moodles.getMoodleLevel) ~= "function" then return end
        local mt = MoodleType and (MoodleType.Endurance or MoodleType.ENDURANCE)
        if mt ~= nil then lvl = tonumber(moodles:getMoodleLevel(mt)) or 0 end
    end)
    return lvl
end

local function isSprinting(player)
    local s = false
    pcall(function()
        if type(player.isSprinting) == "function" then s = player:isSprinting() and true or false end
        if not s and type(player.IsSprinting) == "function" then s = player:IsSprinting() and true or false end
    end)
    return s
end

local function isRunning(player)
    local s = false
    pcall(function()
        if type(player.isRunning) == "function" then s = player:isRunning() and true or false end
    end)
    return s
end

local function weightInfo(player)
    local w, maxW, enc = -1, -1, -1
    pcall(function()
        local inv = player:getInventory()
        if inv and type(inv.getCapacityWeight) == "function" then
            w = tonumber(inv:getCapacityWeight()) or -1
        end
        if type(player.getMaxWeight) == "function" then
            maxW = tonumber(player:getMaxWeight()) or -1
        elseif type(player.getInventoryWeight) == "function" then
            -- fallback
        end
        if inv and type(inv.getMaxWeight) == "function" then
            maxW = tonumber(inv:getMaxWeight()) or maxW
        end
        if type(player.getEncumbranceMoodle) == "function" then
            -- n/a
        end
        if w >= 0 and maxW > 0 then
            enc = w / maxW
        end
    end)
    return w, maxW, enc
end

local function chargeActive(player)
    local on = 0
    pcall(function()
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Charge then
            local st = KnoxSystem.Warrior.Charge.getState and KnoxSystem.Warrior.Charge.getState(player)
            if st and (st.active or st.phase) then
                on = 1
                if type(st.phase) == "string" then
                    -- encode phase length in a separate field later
                end
            end
            if KnoxSystem.Warrior.Charge.isActive and KnoxSystem.Warrior.Charge.isActive(player) then
                on = 1
            end
        end
    end)
    return on
end

function KnoxSystem.Stats.applyAll(player, data)
    if not player or not data then return end
    local power = tonumber(data.stat_power) or tonumber(data.stat_strength) or 0
    data.stat_power = power
    data.stat_strength = power -- legacy mirror
    data._strMult = 1 + MAG * power
    data._powerMult = data._strMult
    data._endMult = 1 + MAG * (data.stat_endurance or 0)
    data._mindSpellMult = 1 + MAG * (data.stat_mind or 0)
    data._mindManaFlat = 5 * (data.stat_mind or 0)
    data._mindManaRegen = 0.05 * (data.stat_mind or 0)
    data._resHealMult = 1 + MAG * (data.stat_resilience or 0)
    data._resInfectionPP = -5 * (data.stat_resilience or 0)
    data._resImmune = (data.stat_resilience or 0) >= 20
    data._strLiveApplied = false
    data._powerLiveApplied = false
    data._endLiveApplied = false
end

function KnoxSystem.Stats.meleeDamageMult(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 1 end
    if not data._powerMult and not data._strMult then KnoxSystem.Stats.applyAll(player, data) end
    return data._powerMult or data._strMult or 1
end

function KnoxSystem.Stats.enduranceMult(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 1 end
    if not data._endMult then KnoxSystem.Stats.applyAll(player, data) end
    return data._endMult or 1
end

function KnoxSystem.Stats.snapshotPower(player)
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if data then KnoxSystem.Stats.applyAll(player, data) end
    local personal = data and (tonumber(data.stat_power) or tonumber(data.stat_strength) or 0) or 0
    local mult = data and (data._powerMult or data._strMult or 1) or 1
    local basePerk = perkLevel(player, "Strength")
    local live = false
    if personal > 0 then live = true end
    if data and (data._powerLiveApplied or data._powerLiveCarry) then live = true end
    return {
        personalPower = personal,
        powerMult = mult,
        personalStrength = personal,
        strengthMult = mult,
        magPerLevel = MAG,
        baseStrengthPerk = basePerk ~= nil and basePerk or -1,
        design = "outcome_mult_on_base_Strength_effectiveness",
        liveApplied = live and 1 or 0,
        note = live and "live_melee_carry_knockdown_smash" or "moddata_only",
    }
end

-- legacy name
function KnoxSystem.Stats.snapshotStrength(player)
    return KnoxSystem.Stats.snapshotPower(player)
end

function KnoxSystem.Stats.snapshotStamina(player)
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if data then KnoxSystem.Stats.applyAll(player, data) end
    local personal = data and (data.stat_endurance or 0) or 0
    local mult = data and (data._endMult or 1) or 1
    local fitness = perkLevel(player, "Fitness")
    local endu = tryEndurance(player)
    local enduMax = tryEnduranceMax(player)
    local enduPct = -1
    if endu ~= nil and enduMax and enduMax > 0 then
        enduPct = (endu / enduMax) * 100.0
    end
    local moodle = enduranceMoodle(player)
    local sprint = isSprinting(player) and 1 or 0
    local run = isRunning(player) and 1 or 0
    local fat = tryFatigue(player)
    local w, maxW, enc = weightInfo(player)
    local chg = chargeActive(player)

    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local t = nowMs()
    local prev = lastEndurance[id]
    local prevT = lastEnduranceT[id] or 0
    local dEnd = 0
    local dPerSec = 0
    if endu ~= nil and prev ~= nil and t > prevT and prevT > 0 then
        dEnd = endu - prev
        local dt = (t - prevT) / 1000.0
        if dt > 0.05 then dPerSec = dEnd / dt end
    end

    return {
        personalEndurance = personal,
        staminaMult = mult,
        magPerLevel = MAG,
        baseFitnessPerk = fitness ~= nil and fitness or -1,
        enduranceBar = endu ~= nil and endu or -1,       -- current 0–max (vanilla usually 0–1)
        enduranceMax = enduMax,                           -- pool max (vanilla Endurance stat max = 1.0)
        endurancePct = enduPct,                           -- current as % of max
        enduranceDelta = dEnd,
        endurancePerSec = dPerSec, -- negative = draining
        enduranceMoodle = moodle,
        fatigue = fat ~= nil and fat or -1,
        weight = w,
        maxWeight = maxW,
        encumbrance = enc,
        sprinting = sprint,
        running = run,
        chargeActive = chg,
        design = "outcome_mult_on_base_Fitness_effectiveness",
        liveApplied = (data and data._endLiveApplied) and 1 or 0,
        note = (data and data._endLiveApplied) and "live" or "moddata_only_not_vanilla_yet",
    }
end

function KnoxSystem.Stats.logPower(player, reason)
    if not player or not KnoxSystem.Track then return end
    local snap = KnoxSystem.Stats.snapshotPower(player)
    snap.reason = tostring(reason or "tick")
    if KnoxSystem.Track.isChannelOn("power") then
        KnoxSystem.Track.log("power", "snapshot", snap)
    elseif KnoxSystem.Track.isChannelOn("strength") then
        KnoxSystem.Track.log("strength", "snapshot", snap)
    end
end

function KnoxSystem.Stats.logStrength(player, reason)
    KnoxSystem.Stats.logPower(player, reason)
end

function KnoxSystem.Stats.logStamina(player, reason)
    if not player or not KnoxSystem.Track then return end
    local snap = KnoxSystem.Stats.snapshotStamina(player)
    snap.reason = tostring(reason or "tick")
    KnoxSystem.Track.log("stamina", "snapshot", snap)
    -- advance delta baseline after log
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local endu = tryEndurance(player)
    if endu ~= nil then
        lastEndurance[id] = endu
        lastEnduranceT[id] = nowMs()
    end
end

--- Stamina tracker: throttled (idle 10s / active 4s). Skip pure-idle tiny deltas.
function KnoxSystem.Stats.onPlayerUpdate(player)
    if not player then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data or not data.initialized then return end
    KnoxSystem.Stats.applyAll(player, data)

    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn("stamina") then return end

    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    local t = nowMs()

    local reason = "idle"
    local active = false
    if chargeActive(player) == 1 then
        reason = "charge"
        active = true
    elseif isSprinting(player) then
        reason = "sprint"
        active = true
    elseif isRunning(player) then
        reason = "run"
        active = true
    else
        local moving = false
        pcall(function()
            if type(player.isPlayerMoving) == "function" then moving = player:isPlayerMoving() end
        end)
        if moving then
            reason = "walk"
            active = true
        end
    end

    local interval = active and STAMINA_ACTIVE_MS or STAMINA_IDLE_MS
    local last = lastStaminaLog[id] or 0
    if t > 0 and last > 0 and (t - last) < interval then return end

    -- Skip idle logs when bar barely moved (cuts console spam while standing)
    if reason == "idle" and last > 0 then
        local endu = tryEndurance(player)
        local prev = lastEndurance[id]
        if endu ~= nil and prev ~= nil and math.abs(endu - prev) < 0.005 then
            lastStaminaLog[id] = t
            return
        end
    end

    lastStaminaLog[id] = t
    KnoxSystem.Stats.logStamina(player, reason)
end

print("[KnoxSystem] KS_Stats loaded (stamina tracker + Resilience-derived fields)")
