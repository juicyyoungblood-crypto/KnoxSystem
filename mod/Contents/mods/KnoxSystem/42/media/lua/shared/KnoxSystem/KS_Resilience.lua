-- Personal Stat: Resilience — System Infection + mundane disease resist
-- Design: 5% resist/level → 100% at 20; immune at 20.
-- Zombie virus: AFTER vanilla infects, roll once (roll < chance → purge).
-- Diseases: same chance — cold, food sickness, fake-infection sickness, wound infections.
-- L20: continuous scrub. Rising-on-death block remains Phase 6.

require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Resilience = KnoxSystem.Resilience or {}

local PP_PER_LEVEL = 5
local lastInfected = {}
local lastDisease = {} -- bool edge for mundane disease process
local lastRollMs = {}
local lastDiseaseRollMs = {}
local lastScrubLogMs = {}
local lastDiseaseLogMs = {}
local ROLL_COOLDOWN_MS = 250
local DISEASE_ROLL_COOLDOWN_MS = 400
local SCRUB_LOG_COOLDOWN_MS = 5000
local DISEASE_THRESH = 0.05 -- ignore tiny float noise on sickness meters

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
    if ok then return true end
    pcall(function()
        if type(o.getPlayerNum) == "function" and type(o.getBodyDamage) == "function" then
            ok = true
        end
    end)
    return ok
end

local function playerId(player)
    local id = 0
    if not player then return 0 end
    if type(player.getPlayerNum) ~= "function" then return 0 end
    pcall(function()
        id = player:getPlayerNum()
        if id == nil then id = 0 end
    end)
    return id or 0
end

local function bodyDamage(player)
    if not player or type(player.getBodyDamage) ~= "function" then return nil end
    local bd = nil
    pcall(function() bd = player:getBodyDamage() end)
    return bd
end

local function numCall(obj, getter)
    local v = nil
    pcall(function()
        if obj and type(obj[getter]) == "function" then
            v = tonumber(obj[getter](obj))
        end
    end)
    return v
end

local function boolCall(obj, getter)
    local v = false
    pcall(function()
        if obj and type(obj[getter]) == "function" then
            v = obj[getter](obj) and true or false
        end
    end)
    return v
end

function KnoxSystem.Resilience.getLevel(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 0 end
    return tonumber(data.stat_resilience) or 0
end

function KnoxSystem.Resilience.resistChancePercent(player)
    local lvl = KnoxSystem.Resilience.getLevel(player)
    if lvl <= 0 then return 0 end
    if lvl >= 20 then return 100 end
    return math.min(100, PP_PER_LEVEL * lvl)
end

function KnoxSystem.Resilience.isImmune(player)
    return KnoxSystem.Resilience.getLevel(player) >= 20
end

function KnoxSystem.Resilience.isInfected(player)
    local bd = bodyDamage(player)
    if not bd then return false end
    return boolCall(bd, "isInfected") or boolCall(bd, "IsInfected")
end

---------------------------------------------------------------------------
-- System (zombie) infection
---------------------------------------------------------------------------

function KnoxSystem.Resilience.hasInfectionProcess(player)
    local bd = bodyDamage(player)
    if not bd then return false end
    if KnoxSystem.Resilience.isInfected(player) then return true end
    local lvl = numCall(bd, "getInfectionLevel")
    if lvl and lvl > 0.001 then return true end
    local t = numCall(bd, "getInfectionTime")
    if t ~= nil and t >= 0 then return true end
    local mort = numCall(bd, "getInfectionMortalityDuration")
    local growth = numCall(bd, "getInfectionGrowthRate")
    if mort and mort > 0.0001 and t ~= nil and t >= 0 then return true end
    if growth and growth > 0 and (lvl and lvl > 0) then return true end
    -- note: fake infection is MUNDANE sickness, handled in disease path
    local partHit = false
    pcall(function()
        if type(bd.getBodyParts) ~= "function" then return end
        local parts = bd:getBodyParts()
        if not parts or type(parts.size) ~= "function" then return end
        for i = 0, parts:size() - 1 do
            local bp = parts:get(i)
            if bp then
                pcall(function()
                    -- Body-part Knox flag (not wound sepsis)
                    if type(bp.IsInfected) == "function" and bp:IsInfected() then partHit = true end
                    if type(bp.isInfected) == "function" and bp:isInfected() then partHit = true end
                end)
            end
            if partHit then break end
        end
    end)
    return partHit
end

local function clearBodyPartKnox(bd)
    pcall(function()
        if type(bd.getBodyParts) ~= "function" then return end
        local parts = bd:getBodyParts()
        if not parts or type(parts.size) ~= "function" then return end
        for i = 0, parts:size() - 1 do
            local bp = parts:get(i)
            if bp then
                pcall(function()
                    if type(bp.SetInfected) == "function" then bp:SetInfected(false) end
                    if type(bp.setInfected) == "function" then bp:setInfected(false) end
                end)
            end
        end
    end)
end

function KnoxSystem.Resilience.clearInfection(player, bd)
    if not bd then bd = bodyDamage(player) end
    if not bd then return false end
    local ok = false
    pcall(function()
        if type(bd.setInfected) == "function" then bd:setInfected(false) end
        if type(bd.setInf) == "function" then bd:setInf(false) end
        if type(bd.setIsInfected) == "function" then bd:setIsInfected(false) end
        if type(bd.setInfectionLevel) == "function" then bd:setInfectionLevel(0) end
        if type(bd.setInfectionTime) == "function" then bd:setInfectionTime(-1) end
        if type(bd.setInfectionGrowthRate) == "function" then bd:setInfectionGrowthRate(0) end
        if type(bd.setInfectionMortalityDuration) == "function" then
            bd:setInfectionMortalityDuration(0)
        end
        ok = true
    end)
    clearBodyPartKnox(bd)
    pcall(function()
        if type(bd.setInfected) == "function" then bd:setInfected(false) end
        if type(bd.setInfectionLevel) == "function" then bd:setInfectionLevel(0) end
        if type(bd.setInfectionTime) == "function" then bd:setInfectionTime(-1) end
        if type(bd.setInfectionMortalityDuration) == "function" then
            bd:setInfectionMortalityDuration(0)
        end
    end)
    return ok
end

local function snapshotInfection(bd)
    if not bd then return {} end
    return {
        level = numCall(bd, "getInfectionLevel") or -1,
        time = numCall(bd, "getInfectionTime") or -999,
        mort = numCall(bd, "getInfectionMortalityDuration") or -1,
        growth = numCall(bd, "getInfectionGrowthRate") or -1,
    }
end

local function snapInf(player)
    local bd = bodyDamage(player)
    local s = snapshotInfection(bd)
    s.infected = KnoxSystem.Resilience.isInfected(player) and 1 or 0
    return s
end

local function halo(player, msg)
    pcall(function()
        if type(player.setHaloNote) == "function" then
            player:setHaloNote(msg, 120, 220, 160, 90.0)
        end
    end)
end

local function roll100()
    local r = nil
    pcall(function()
        if ZombRand then r = ZombRand(100) end
    end)
    if r == nil then r = math.floor(math.random() * 100) end
    return r
end

function KnoxSystem.Resilience.purgeInfection(player, reason, quiet)
    if not isIsoPlayer(player) then return false end
    local before = snapInf(player)
    KnoxSystem.Resilience.clearInfection(player, bodyDamage(player))
    if KnoxSystem.Resilience.hasInfectionProcess(player) then
        KnoxSystem.Resilience.clearInfection(player, bodyDamage(player))
    end
    local after = snapInf(player)
    local id = playerId(player)
    lastInfected[id] = KnoxSystem.Resilience.isInfected(player)

    if not quiet then
        local t = nowMs()
        local last = lastScrubLogMs[id] or 0
        if t <= 0 or last <= 0 or (t - last) >= SCRUB_LOG_COOLDOWN_MS then
            lastScrubLogMs[id] = t
            print(string.format(
                "[KnoxSystem] Resilience: PURGE reason=%s before={inf=%s lvl=%s t=%s mort=%s} after={inf=%s lvl=%s t=%s mort=%s}",
                tostring(reason or ""),
                tostring(before.infected), tostring(before.level), tostring(before.time), tostring(before.mort),
                tostring(after.infected), tostring(after.level), tostring(after.time), tostring(after.mort)
            ))
            if KnoxSystem.Track then
                KnoxSystem.Track.log("resilience", "purge", {
                    reason = tostring(reason or ""),
                    resilience = KnoxSystem.Resilience.getLevel(player),
                    beforeInf = before.infected,
                    beforeTime = before.time,
                    beforeMort = before.mort,
                    afterInf = after.infected,
                    afterTime = after.time,
                    afterMort = after.mort,
                    stillProcess = KnoxSystem.Resilience.hasInfectionProcess(player) and 1 or 0,
                })
            end
        end
    end
    return not KnoxSystem.Resilience.hasInfectionProcess(player)
end

function KnoxSystem.Resilience.tryResistInfection(player, reason)
    if not isIsoPlayer(player) then return false end
    local chance = KnoxSystem.Resilience.resistChancePercent(player)
    local lvl = KnoxSystem.Resilience.getLevel(player)
    if chance <= 0 then return false end

    local id = playerId(player)
    local t = nowMs()
    if lastRollMs[id] and t > 0 and (t - lastRollMs[id]) < ROLL_COOLDOWN_MS then
        if lvl >= 20 then
            KnoxSystem.Resilience.purgeInfection(player, "immune_cd:" .. tostring(reason or ""), false)
            return true
        end
        return false
    end
    lastRollMs[id] = t

    local roll = roll100()
    local success = (lvl >= 20) or (roll < chance)
    local before = snapInf(player)

    if success then
        KnoxSystem.Resilience.purgeInfection(player, reason or "resist", false)
        halo(player, lvl >= 20 and "System Infection blocked" or "System Infection resisted")
        print(string.format(
            "[KnoxSystem] Resilience: %s roll=%s chance=%s%% level=%s reason=%s stillProcess=%s beforeTime=%s beforeMort=%s",
            lvl >= 20 and "BLOCK" or "RESIST",
            tostring(roll), tostring(chance), tostring(lvl), tostring(reason or ""),
            tostring(KnoxSystem.Resilience.hasInfectionProcess(player)),
            tostring(before.time), tostring(before.mort)
        ))
        if KnoxSystem.Track then
            KnoxSystem.Track.log("resilience", lvl >= 20 and "block_ok" or "resist_ok", {
                reason = tostring(reason or "new_infection"),
                resilience = lvl,
                chancePct = chance,
                roll = roll,
                infectionTimeBefore = before.time,
                mortBefore = before.mort,
                stillInfected = KnoxSystem.Resilience.isInfected(player) and 1 or 0,
                stillProcess = KnoxSystem.Resilience.hasInfectionProcess(player) and 1 or 0,
            })
        end
        lastInfected[id] = false
        return true
    end

    print(string.format(
        "[KnoxSystem] Resilience: FAIL resist roll=%s chance=%s%% level=%s reason=%s",
        tostring(roll), tostring(chance), tostring(lvl), tostring(reason or "")
    ))
    if KnoxSystem.Track then
        KnoxSystem.Track.log("resilience", "resist_fail", {
            reason = tostring(reason or "new_infection"),
            resilience = lvl,
            chancePct = chance,
            roll = roll,
        })
    end
    lastInfected[id] = true
    return false
end

---------------------------------------------------------------------------
-- Mundane disease: cold, food sickness, fake-infection illness, wound sepsis
---------------------------------------------------------------------------

local function woundInfectionSum(bd)
    local sum = 0
    local any = false
    pcall(function()
        if type(bd.getBodyParts) ~= "function" then return end
        local parts = bd:getBodyParts()
        if not parts or type(parts.size) ~= "function" then return end
        for i = 0, parts:size() - 1 do
            local bp = parts:get(i)
            if bp then
                pcall(function()
                    if type(bp.isInfectedWound) == "function" and bp:isInfectedWound() then
                        any = true
                    end
                    if type(bp.IsInfectedWound) == "function" and bp:IsInfectedWound() then
                        any = true
                    end
                    if type(bp.getWoundInfectionLevel) == "function" then
                        local w = tonumber(bp:getWoundInfectionLevel()) or 0
                        if w > DISEASE_THRESH then
                            sum = sum + w
                            any = true
                        end
                    end
                    if type(bp.getInfectionTime) == "function" then
                        -- wound timers exist on some builds; ignore Knox bite time
                    end
                end)
            end
        end
    end)
    return sum, any
end

function KnoxSystem.Resilience.snapshotDisease(player)
    local bd = bodyDamage(player)
    local s = {
        cold = 0,
        coldStr = 0,
        food = 0,
        fake = 0,
        wound = 0,
        woundAny = 0,
        poison = 0,
    }
    if not bd then return s end
    pcall(function()
        if boolCall(bd, "HasACold") or boolCall(bd, "hasACold") then s.cold = 1 end
        s.coldStr = numCall(bd, "getColdStrength") or numCall(bd, "getColdSicknessLevel") or 0
        if s.coldStr and s.coldStr > DISEASE_THRESH then s.cold = 1 end
        s.food = numCall(bd, "getFoodSicknessLevel") or 0
        s.fake = numCall(bd, "getFakeInfectionLevel") or 0
        s.poison = numCall(bd, "getPoisonLevel") or 0
        local wsum, wany = woundInfectionSum(bd)
        s.wound = wsum
        s.woundAny = wany and 1 or 0
    end)
    return s
end

function KnoxSystem.Resilience.hasDiseaseProcess(player)
    local s = KnoxSystem.Resilience.snapshotDisease(player)
    if s.cold == 1 then return true end
    if s.food and s.food > DISEASE_THRESH then return true end
    if s.fake and s.fake > DISEASE_THRESH then return true end
    if s.woundAny == 1 then return true end
    if s.poison and s.poison > DISEASE_THRESH then return true end
    return false
end

function KnoxSystem.Resilience.clearDiseases(player, bd)
    if not bd then bd = bodyDamage(player) end
    if not bd then return false end
    local ok = false
    pcall(function()
        if type(bd.setHasACold) == "function" then bd:setHasACold(false) end
        if type(bd.setColdStrength) == "function" then bd:setColdStrength(0) end
        if type(bd.setColdSicknessLevel) == "function" then bd:setColdSicknessLevel(0) end
        if type(bd.setFoodSicknessLevel) == "function" then bd:setFoodSicknessLevel(0) end
        if type(bd.setFakeInfectionLevel) == "function" then bd:setFakeInfectionLevel(0) end
        if type(bd.setIsFakeInfected) == "function" then bd:setIsFakeInfected(false) end
        if type(bd.setPoisonLevel) == "function" then bd:setPoisonLevel(0) end
        -- Time-to-sick fields if present
        if type(bd.setTimeToSneezeOrCough) == "function" then bd:setTimeToSneezeOrCough(0) end
        ok = true
    end)
    pcall(function()
        if type(bd.getBodyParts) ~= "function" then return end
        local parts = bd:getBodyParts()
        if not parts or type(parts.size) ~= "function" then return end
        for i = 0, parts:size() - 1 do
            local bp = parts:get(i)
            if bp then
                pcall(function()
                    if type(bp.setInfectedWound) == "function" then bp:setInfectedWound(false) end
                    if type(bp.SetInfectedWound) == "function" then bp:SetInfectedWound(false) end
                    if type(bp.setWoundInfectionLevel) == "function" then bp:setWoundInfectionLevel(0) end
                    if type(bp.SetWoundInfectionLevel) == "function" then bp:SetWoundInfectionLevel(0) end
                end)
            end
        end
    end)
    return ok
end

function KnoxSystem.Resilience.purgeDiseases(player, reason, quiet)
    if not isIsoPlayer(player) then return false end
    local before = KnoxSystem.Resilience.snapshotDisease(player)
    KnoxSystem.Resilience.clearDiseases(player, bodyDamage(player))
    if KnoxSystem.Resilience.hasDiseaseProcess(player) then
        KnoxSystem.Resilience.clearDiseases(player, bodyDamage(player))
    end
    local after = KnoxSystem.Resilience.snapshotDisease(player)
    local id = playerId(player)
    lastDisease[id] = KnoxSystem.Resilience.hasDiseaseProcess(player)

    if not quiet then
        local t = nowMs()
        local last = lastDiseaseLogMs[id] or 0
        if t <= 0 or last <= 0 or (t - last) >= SCRUB_LOG_COOLDOWN_MS then
            lastDiseaseLogMs[id] = t
            print(string.format(
                "[KnoxSystem] Resilience: DISEASE_PURGE reason=%s before={cold=%s food=%.2f fake=%.2f wound=%s poison=%.2f} after={cold=%s food=%.2f fake=%.2f wound=%s}",
                tostring(reason or ""),
                tostring(before.cold), tonumber(before.food) or 0, tonumber(before.fake) or 0,
                tostring(before.woundAny), tonumber(before.poison) or 0,
                tostring(after.cold), tonumber(after.food) or 0, tonumber(after.fake) or 0,
                tostring(after.woundAny)
            ))
            if KnoxSystem.Track then
                KnoxSystem.Track.log("resilience", "disease_purge", {
                    reason = tostring(reason or ""),
                    resilience = KnoxSystem.Resilience.getLevel(player),
                    beforeCold = before.cold,
                    beforeFood = before.food,
                    beforeFake = before.fake,
                    beforeWound = before.woundAny,
                    beforePoison = before.poison,
                    afterCold = after.cold,
                    afterFood = after.food,
                    afterFake = after.fake,
                    afterWound = after.woundAny,
                    stillDisease = KnoxSystem.Resilience.hasDiseaseProcess(player) and 1 or 0,
                })
            end
        end
    end
    return not KnoxSystem.Resilience.hasDiseaseProcess(player)
end

function KnoxSystem.Resilience.tryResistDisease(player, reason)
    if not isIsoPlayer(player) then return false end
    if not KnoxSystem.Resilience.hasDiseaseProcess(player) then return false end
    local chance = KnoxSystem.Resilience.resistChancePercent(player)
    local lvl = KnoxSystem.Resilience.getLevel(player)
    if chance <= 0 then return false end

    local id = playerId(player)
    local t = nowMs()
    if lastDiseaseRollMs[id] and t > 0 and (t - lastDiseaseRollMs[id]) < DISEASE_ROLL_COOLDOWN_MS then
        if lvl >= 20 then
            KnoxSystem.Resilience.purgeDiseases(player, "disease_immune_cd:" .. tostring(reason or ""), false)
            return true
        end
        return false
    end
    lastDiseaseRollMs[id] = t

    local roll = roll100()
    local success = (lvl >= 20) or (roll < chance)
    local before = KnoxSystem.Resilience.snapshotDisease(player)

    if success then
        KnoxSystem.Resilience.purgeDiseases(player, reason or "disease_resist", false)
        local label = "illness"
        if before.cold == 1 then label = "cold"
        elseif (before.food or 0) > DISEASE_THRESH then label = "food sickness"
        elseif (before.fake or 0) > DISEASE_THRESH then label = "sickness"
        elseif before.woundAny == 1 then label = "wound infection"
        elseif (before.poison or 0) > DISEASE_THRESH then label = "poison"
        end
        halo(player, lvl >= 20 and ("Blocked " .. label) or ("Resisted " .. label))
        print(string.format(
            "[KnoxSystem] Resilience: DISEASE_%s roll=%s chance=%s%% level=%s reason=%s kind=%s still=%s",
            lvl >= 20 and "BLOCK" or "RESIST",
            tostring(roll), tostring(chance), tostring(lvl), tostring(reason or ""),
            label, tostring(KnoxSystem.Resilience.hasDiseaseProcess(player))
        ))
        if KnoxSystem.Track then
            KnoxSystem.Track.log("resilience", lvl >= 20 and "disease_block_ok" or "disease_resist_ok", {
                reason = tostring(reason or "disease_edge"),
                resilience = lvl,
                chancePct = chance,
                roll = roll,
                kind = label,
                beforeCold = before.cold,
                beforeFood = before.food,
                beforeFake = before.fake,
                beforeWound = before.woundAny,
                stillDisease = KnoxSystem.Resilience.hasDiseaseProcess(player) and 1 or 0,
            })
        end
        lastDisease[id] = false
        return true
    end

    print(string.format(
        "[KnoxSystem] Resilience: DISEASE_FAIL roll=%s chance=%s%% level=%s reason=%s",
        tostring(roll), tostring(chance), tostring(lvl), tostring(reason or "")
    ))
    if KnoxSystem.Track then
        KnoxSystem.Track.log("resilience", "disease_resist_fail", {
            reason = tostring(reason or "disease_edge"),
            resilience = lvl,
            chancePct = chance,
            roll = roll,
            beforeCold = before.cold,
            beforeFood = before.food,
            beforeFake = before.fake,
            beforeWound = before.woundAny,
        })
    end
    lastDisease[id] = true
    return false
end

local function tickDisease(player, reasonPrefix)
    local id = playerId(player)
    local lvl = KnoxSystem.Resilience.getLevel(player)
    local now = KnoxSystem.Resilience.hasDiseaseProcess(player)
    local prev = lastDisease[id]

    if lvl >= 20 and now then
        KnoxSystem.Resilience.tryResistDisease(player, (reasonPrefix or "disease") .. "_immune")
        lastDisease[id] = false
        return
    end

    if prev == nil then
        if lvl >= 20 and now then
            KnoxSystem.Resilience.tryResistDisease(player, "disease_load")
            lastDisease[id] = false
        else
            lastDisease[id] = now
        end
        return
    end

    if now and not prev then
        KnoxSystem.Resilience.tryResistDisease(player, reasonPrefix or "disease_edge")
        lastDisease[id] = KnoxSystem.Resilience.hasDiseaseProcess(player)
        return
    end

    lastDisease[id] = now
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

function KnoxSystem.Resilience.onPlayerUpdate(player)
    if not isIsoPlayer(player) then return end
    local data = KnoxSystem.getPlayerData(player)
    if not data or not data.initialized then return end

    pcall(function()
        if KnoxSystem.Stats and KnoxSystem.Stats.applyAll then
            KnoxSystem.Stats.applyAll(player, data)
        end
    end)

    local id = playerId(player)
    local lvl = KnoxSystem.Resilience.getLevel(player)
    local nowInf = KnoxSystem.Resilience.isInfected(player)
    local process = KnoxSystem.Resilience.hasInfectionProcess(player)
    local prev = lastInfected[id]

    if lvl >= 20 and process then
        KnoxSystem.Resilience.purgeInfection(player, "immune_tick", false)
        lastInfected[id] = false
    elseif prev == nil then
        if lvl >= 20 and process then
            KnoxSystem.Resilience.purgeInfection(player, "immune_load", false)
            lastInfected[id] = false
        else
            lastInfected[id] = nowInf or process
        end
    elseif (nowInf or process) and not prev then
        KnoxSystem.Resilience.tryResistInfection(player, "infection_edge")
        lastInfected[id] = KnoxSystem.Resilience.isInfected(player)
            or KnoxSystem.Resilience.hasInfectionProcess(player)
    else
        lastInfected[id] = nowInf or (process and true or false)
    end

    -- Mundane diseases every update (same resist chance)
    tickDisease(player, "disease_edge")
end

function KnoxSystem.Resilience.onPlayerGetDamage(player, damageType, damage)
    if not isIsoPlayer(player) then return end
    local id = playerId(player)
    local lvl = KnoxSystem.Resilience.getLevel(player)
    local dtype = tostring(damageType or ""):upper()
    local process = KnoxSystem.Resilience.hasInfectionProcess(player)

    if lvl >= 20 then
        if process or dtype:find("INFECT", 1, true) then
            KnoxSystem.Resilience.tryResistInfection(player, "immune_dmg:" .. dtype)
            lastInfected[id] = false
        elseif dtype:find("BLEED", 1, true) or dtype:find("BITE", 1, true)
            or dtype:find("SCRATCH", 1, true) or dtype:find("LACER", 1, true) then
            if KnoxSystem.Resilience.hasInfectionProcess(player) then
                KnoxSystem.Resilience.tryResistInfection(player, "immune_bleed_probe")
                lastInfected[id] = false
            end
        end
        -- Wound sepsis / sickness may flip on damage frames too
        tickDisease(player, "disease_dmg")
        return
    end

    local was = lastInfected[id]
    if was == nil then
        lastInfected[id] = KnoxSystem.Resilience.isInfected(player)
            or KnoxSystem.Resilience.hasInfectionProcess(player)
        was = lastInfected[id]
    end
    local nowProcess = KnoxSystem.Resilience.isInfected(player)
        or KnoxSystem.Resilience.hasInfectionProcess(player)
    if nowProcess and not was then
        KnoxSystem.Resilience.tryResistInfection(player, "get_damage:" .. tostring(damageType or ""))
        lastInfected[id] = KnoxSystem.Resilience.isInfected(player)
            or KnoxSystem.Resilience.hasInfectionProcess(player)
    elseif dtype:find("INFECT", 1, true) and lvl > 0 then
        if not lastRollMs[id] or (nowMs() - (lastRollMs[id] or 0)) > ROLL_COOLDOWN_MS then
            KnoxSystem.Resilience.tryResistInfection(player, "infection_dmg_tick")
        end
        lastInfected[id] = KnoxSystem.Resilience.hasInfectionProcess(player)
    else
        if not nowProcess then lastInfected[id] = false end
    end

    tickDisease(player, "disease_dmg")
end

function KnoxSystem.Resilience.resetSession()
    lastInfected = {}
    lastDisease = {}
    lastRollMs = {}
    lastDiseaseRollMs = {}
    lastScrubLogMs = {}
    lastDiseaseLogMs = {}
end

print("[KnoxSystem] KS_Resilience loaded (System Infection + cold/sickness/wound disease resist)")
