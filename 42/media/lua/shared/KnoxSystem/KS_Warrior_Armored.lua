-- Warrior: Armored — XP, Uncomfortable stress relief, live protection mult
-- Protection: multiplies worn clothing scratch/bite/bullet defense (B42 Clothing setters).
-- That feeds combat (getDefForPart / bite-scratch rolls) and Protection tab UI automatically.
require "KnoxSystem/KS_Class"
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Warrior = KnoxSystem.Warrior or {}
KnoxSystem.Warrior.Armored = KnoxSystem.Warrior.Armored or {}

local PASSIVE_INTERVAL_MS = 10000
local XP_PER_SCORE = 0.015
local XP_ON_MITIGATE = 8.0
local PROT_PER_LEVEL = 0.025

-- Stress relief while Uncomfortable: 6% × level of 5s stress gain (L10=60%).
local STRESS_RELIEF_INTERVAL_MS = 5000
local STRESS_REFUND_PCT_PER_LEVEL = 0.06

-- Re-apply clothing defense boost (non-cyclical via modData baselines).
local PROT_SYNC_INTERVAL_MS = 2000

local lastPassive = {}
local lastStressRelief = {}
local stressWindowStart = {}
local lastProtSync = {}
local lastProtMultApplied = {}
local lastIncomingLogMs = {}

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then
            t = getTimestampMs()
        else
            t = os.time() * 1000
        end
    end)
    return t or 0
end

local function playerId(player)
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    return id
end

local function isClothingItem(item)
    if not item then return false end
    local ok = false
    pcall(function()
        if instanceof(item, "Clothing") then ok = true end
    end)
    if ok then return true end
    pcall(function()
        if item.isClothing and item:isClothing() then ok = true end
    end)
    return ok
end

local function readDefenses(item)
    local s, b, u = 0, 0, 0
    pcall(function()
        if type(item.getScratchDefense) == "function" then s = tonumber(item:getScratchDefense()) or 0 end
    end)
    pcall(function()
        if type(item.getBiteDefense) == "function" then b = tonumber(item:getBiteDefense()) or 0 end
    end)
    pcall(function()
        if type(item.getBulletDefense) == "function" then u = tonumber(item:getBulletDefense()) or 0 end
    end)
    return s, b, u
end

local function writeDefenses(item, scratch, bite, bullet)
    pcall(function()
        if type(item.setScratchDefense) == "function" then item:setScratchDefense(scratch) end
    end)
    pcall(function()
        if type(item.setBiteDefense) == "function" then item:setBiteDefense(bite) end
    end)
    pcall(function()
        if type(item.setBulletDefense) == "function" then item:setBulletDefense(bullet) end
    end)
end

local function getModData(item)
    local md = nil
    pcall(function()
        if type(item.getModData) == "function" then md = item:getModData() end
    end)
    return md
end

local function ensureBaseline(item)
    local md = getModData(item)
    if not md then return nil end
    if type(md.knoxArmoredBase) ~= "table" then
        local s, b, u = readDefenses(item)
        md.knoxArmoredBase = { scratch = s, bite = b, bullet = u }
    end
    return md.knoxArmoredBase
end

local function restoreItemDefense(item)
    if not item then return false end
    local md = getModData(item)
    if not md or type(md.knoxArmoredBase) ~= "table" then return false end
    local base = md.knoxArmoredBase
    writeDefenses(item, base.scratch or 0, base.bite or 0, base.bullet or 0)
    md.knoxArmoredBase = nil
    md.knoxArmoredMult = nil
    return true
end

local function applyItemDefense(item, mult)
    if not item or not isClothingItem(item) then return false end
    local can = false
    pcall(function()
        if type(item.setScratchDefense) == "function" or type(item.setBiteDefense) == "function" then
            can = true
        end
    end)
    if not can then return false end

    local base = ensureBaseline(item)
    if not base then return false end
    mult = tonumber(mult) or 1
    if mult < 1 then mult = 1 end

    local function boost(v)
        v = tonumber(v) or 0
        local out = v * mult
        if out > 100 then out = 100 end
        if out < 0 then out = 0 end
        return out
    end

    writeDefenses(item, boost(base.scratch), boost(base.bite), boost(base.bullet))
    local md = getModData(item)
    if md then md.knoxArmoredMult = mult end
    return true
end

local function eachWornItem(player, fn)
    pcall(function()
        local worn = player:getWornItems()
        if not worn then return end
        local n = 0
        pcall(function() n = worn:size() end)
        for i = 0, (n or 0) - 1 do
            local item = nil
            pcall(function()
                if worn.getItemByIndex then
                    item = worn:getItemByIndex(i)
                elseif worn.get then
                    local wi = worn:get(i)
                    if wi and wi.getItem then item = wi:getItem() end
                end
            end)
            if item then fn(item) end
        end
    end)
end

local function eachInventoryItem(player, fn)
    pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = nil
        pcall(function()
            if type(inv.getItems) == "function" then items = inv:getItems() end
        end)
        if not items then return end
        local n = 0
        pcall(function() n = items:size() end)
        for i = 0, (n or 0) - 1 do
            local item = nil
            pcall(function() item = items:get(i) end)
            if item then fn(item) end
        end
    end)
end

local function itemIdKey(item)
    local k = nil
    pcall(function()
        if type(item.getID) == "function" then k = item:getID() end
    end)
    if k ~= nil then return tostring(k) end
    return tostring(item)
end

--- Baseline (unboosted) score for XP — avoids XP inflation from our mult.
local function itemDefenseScore(item)
    if not item then return 0 end
    local md = getModData(item)
    if md and type(md.knoxArmoredBase) == "table" then
        local b = md.knoxArmoredBase
        local score = (tonumber(b.scratch) or 0) + (tonumber(b.bite) or 0) + (tonumber(b.bullet) or 0)
        if score > 0 then return score end
    end
    local s, b, u = readDefenses(item)
    local score = s + b + u
    if score <= 0 and isClothingItem(item) then score = 1 end
    return score
end

local function wornProtectionScore(player)
    local score = 0
    eachWornItem(player, function(item)
        score = score + itemDefenseScore(item)
    end)
    return score
end

local function sumWornLiveDefenses(player)
    local scratch, bite, bullet = 0, 0, 0
    eachWornItem(player, function(item)
        local s, b, u = readDefenses(item)
        scratch = scratch + s
        bite = bite + b
        bullet = bullet + u
    end)
    return scratch, bite, bullet
end

local function sumWornBaseDefenses(player)
    local scratch, bite, bullet = 0, 0, 0
    eachWornItem(player, function(item)
        local md = getModData(item)
        if md and type(md.knoxArmoredBase) == "table" then
            scratch = scratch + (tonumber(md.knoxArmoredBase.scratch) or 0)
            bite = bite + (tonumber(md.knoxArmoredBase.bite) or 0)
            bullet = bullet + (tonumber(md.knoxArmoredBase.bullet) or 0)
        else
            local s, b, u = readDefenses(item)
            scratch = scratch + s
            bite = bite + b
            bullet = bullet + u
        end
    end)
    return scratch, bite, bullet
end

local function getCharacterStat(nameUpper, nameAlt)
    if not CharacterStat then return nil end
    if CharacterStat[nameUpper] then return CharacterStat[nameUpper] end
    if CharacterStat.getById then
        return CharacterStat.getById(nameUpper) or (nameAlt and CharacterStat.getById(nameAlt)) or nil
    end
    return nil
end

local function getStatValue(player, stat)
    local v = nil
    pcall(function()
        local st = player:getStats()
        if st and stat and type(st.get) == "function" then
            v = tonumber(st:get(stat))
        end
    end)
    return v
end

local function setStatValue(player, stat, value)
    pcall(function()
        local st = player:getStats()
        if st and stat and type(st.set) == "function" and value ~= nil then
            st:set(stat, value)
        end
    end)
end

local function getUncomfortableLevel(player)
    local lvl = 0
    pcall(function()
        local moodles = player:getMoodles()
        if not moodles or type(moodles.getMoodleLevel) ~= "function" then return end
        local mt = nil
        if MoodleType then
            mt = MoodleType.UNCOMFORTABLE or MoodleType.Uncomfortable or MoodleType.DISCOMFORT or MoodleType.Discomfort
        end
        if mt ~= nil then
            lvl = tonumber(moodles:getMoodleLevel(mt)) or 0
        end
    end)
    return lvl
end

function KnoxSystem.Warrior.Armored.getLevel(player)
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    return KnoxSystem.Class.getSkillLevel(data, "Armored")
end

function KnoxSystem.Warrior.Armored.protectionMult(player)
    return 1.0 + KnoxSystem.Warrior.Armored.getLevel(player) * PROT_PER_LEVEL
end

function KnoxSystem.Warrior.Armored.stressRefundPct(level)
    level = tonumber(level) or 0
    if level < 1 then return 0 end
    local pct = STRESS_REFUND_PCT_PER_LEVEL * level
    if pct > 1 then pct = 1 end
    return pct
end

--- Apply/remove Armored mult on clothing. Non-cyclical: always base * mult from modData baseline.
function KnoxSystem.Warrior.Armored.syncProtection(player, reason)
    if not player then return end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    local id = playerId(player)
    local warrior = data and KnoxSystem.Class.isWarrior(data)
    local lv = warrior and KnoxSystem.Warrior.Armored.getLevel(player) or 0
    local mult = (warrior and lv >= 1) and KnoxSystem.Warrior.Armored.protectionMult(player) or 1.0

    local wornKeys = {}
    local applied = 0
    local restored = 0

    if mult > 1.0001 then
        eachWornItem(player, function(item)
            wornKeys[itemIdKey(item)] = true
            if applyItemDefense(item, mult) then applied = applied + 1 end
        end)
    else
        eachWornItem(player, function(item)
            wornKeys[itemIdKey(item)] = true
            if restoreItemDefense(item) then restored = restored + 1 end
        end)
    end

    -- Unequipped gear must not keep the boost
    eachInventoryItem(player, function(item)
        local key = itemIdKey(item)
        if not wornKeys[key] then
            if restoreItemDefense(item) then restored = restored + 1 end
        end
    end)

    local baseS, baseB, baseU = sumWornBaseDefenses(player)
    local liveS, liveB, liveU = sumWornLiveDefenses(player)

    local prev = lastProtMultApplied[id]
    lastProtMultApplied[id] = mult
    local changed = (prev == nil) or (math.abs((prev or 0) - mult) > 0.0001) or reason == "force"

    if KnoxSystem.Track and (changed or reason == "clothing" or reason == "game_start") then
        KnoxSystem.Track.log("protection", "sync", {
            reason = tostring(reason or "tick"),
            armoredLv = lv,
            protMult = mult,
            itemsBoosted = applied,
            itemsRestored = restored,
            baseScratch = baseS,
            baseBite = baseB,
            baseBullet = baseU,
            liveScratch = liveS,
            liveBite = liveB,
            liveBullet = liveU,
            warrior = warrior and 1 or 0,
        })
    end
end

--- Incoming hit / damage — log mult + defense totals; mint mitigate XP (debounced).
function KnoxSystem.Warrior.Armored.onIncomingHit(player, info)
    if not player then return end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not data or not KnoxSystem.Class.isWarrior(data) then return end

    -- Debounce: WeaponHit + GetDamage can both fire for one attack
    local id = playerId(player)
    local t = nowMs()
    local lastI = lastIncomingLogMs[id] or 0
    if t > 0 and lastI > 0 and (t - lastI) < 200 then
        return
    end
    lastIncomingLogMs[id] = t

    local lv = KnoxSystem.Warrior.Armored.getLevel(player)
    local mult = KnoxSystem.Warrior.Armored.protectionMult(player)
    local baseS, baseB, baseU = sumWornBaseDefenses(player)
    local liveS, liveB, liveU = sumWornLiveDefenses(player)

    info = info or {}
    local dmg = tonumber(info.damage) or tonumber(info.amount) or 0
    local dtype = tostring(info.damageType or info.dtype or info.kind or "?")

    if KnoxSystem.Track then
        KnoxSystem.Track.log("protection", "incoming_hit", {
            damage = dmg,
            damageType = dtype,
            armoredLv = lv,
            protMult = mult,
            baseScratch = baseS,
            baseBite = baseB,
            baseBullet = baseU,
            liveScratch = liveS,
            liveBite = liveB,
            liveBullet = liveU,
            note = "live*=base*protMult (cap 100/item); combat/UI read Clothing getters",
        })
    end

    if dmg > 0 and (liveS + liveB + liveU) > 0 then
        local mitigatedGuess = dmg * math.min(0.5, (liveS + liveB + liveU) / 300.0)
        if mitigatedGuess > 0.05 then
            KnoxSystem.Warrior.Armored.onMitigated(player, mitigatedGuess)
        end
    end
end

function KnoxSystem.Warrior.Armored.applyUncomfortableStressRelief(player)
    if not player then return end
    local lv = KnoxSystem.Warrior.Armored.getLevel(player)
    if lv < 1 then return end
    if getUncomfortableLevel(player) < 1 then
        local idClear = playerId(player)
        if stressWindowStart[idClear] ~= nil and KnoxSystem.Track then
            KnoxSystem.Track.log("stress", "window_clear", {
                reason = "uncomfortable_off",
                armoredLv = lv,
            })
        end
        stressWindowStart[idClear] = nil
        lastStressRelief[idClear] = nil
        return
    end

    local id = playerId(player)
    local t = nowMs()
    local stressStat = getCharacterStat("STRESS", "Stress")
    if not stressStat then
        if KnoxSystem.Track then
            KnoxSystem.Track.log("stress", "skip_no_stress_stat", { armoredLv = lv })
        end
        return
    end

    local cur = getStatValue(player, stressStat)
    if cur == nil then return end

    local unc = getUncomfortableLevel(player)

    if stressWindowStart[id] == nil then
        stressWindowStart[id] = cur
        lastStressRelief[id] = t
        if KnoxSystem.Track then
            KnoxSystem.Track.log("stress", "window_open", {
                stress0 = cur,
                uncomfortable = unc,
                armoredLv = lv,
                intervalMs = STRESS_RELIEF_INTERVAL_MS,
                refundPct = KnoxSystem.Warrior.Armored.stressRefundPct(lv),
            })
        end
        return
    end

    local last = lastStressRelief[id] or 0
    if t > 0 and last > 0 and (t - last) < STRESS_RELIEF_INTERVAL_MS then
        return
    end
    lastStressRelief[id] = t

    local start = tonumber(stressWindowStart[id]) or cur
    local gain = cur - start
    if gain < 0 then gain = 0 end

    local pct = KnoxSystem.Warrior.Armored.stressRefundPct(lv)
    local refund = gain * pct
    local before = cur
    if refund > 0 then
        local nextVal = cur - refund
        if nextVal < start then nextVal = start end
        if nextVal < 0 then nextVal = 0 end
        setStatValue(player, stressStat, nextVal)
        cur = nextVal
    end

    if KnoxSystem.Track then
        KnoxSystem.Track.log("stress", "window_tick", {
            stressStart = start,
            stressBefore = before,
            stressAfter = cur,
            gain = gain,
            refund = refund,
            refundPct = pct,
            uncomfortable = unc,
            armoredLv = lv,
            intervalMs = STRESS_RELIEF_INTERVAL_MS,
            protMult = KnoxSystem.Warrior.Armored.protectionMult(player),
        })
    end

    stressWindowStart[id] = cur
end

function KnoxSystem.Warrior.Armored.onPlayerUpdate(player)
    if not player then return end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    local id = playerId(player)
    local t = nowMs()

    -- Protection sync for warriors; also restores boosts if class lost
    local lastP = lastProtSync[id] or 0
    if t <= 0 or lastP <= 0 or (t - lastP) >= PROT_SYNC_INTERVAL_MS then
        lastProtSync[id] = t
        KnoxSystem.Warrior.Armored.syncProtection(player, "tick")
    end

    if not data or not KnoxSystem.Class.isWarrior(data) then return end

    KnoxSystem.Warrior.Armored.applyUncomfortableStressRelief(player)

    local last = lastPassive[id] or 0
    if t > 0 and (t - last) < PASSIVE_INTERVAL_MS then return end
    lastPassive[id] = t
    local score = wornProtectionScore(player)
    if score > 0 then
        KnoxSystem.Class.addSkillXp(player, "Armored", score * XP_PER_SCORE, "armor_passive")
    end
end

function KnoxSystem.Warrior.Armored.onClothingUpdated(player)
    if not player then return end
    KnoxSystem.Warrior.Armored.syncProtection(player, "clothing")
end

function KnoxSystem.Warrior.Armored.onMitigated(player, mitigatedAmount)
    if not player then return end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not KnoxSystem.Class.isWarrior(data) then return end
    local xp = XP_ON_MITIGATE
    if mitigatedAmount and mitigatedAmount > 0 then
        xp = xp + mitigatedAmount * 0.5
    end
    KnoxSystem.Class.addSkillXp(player, "Armored", xp, "armor_mitigate")
end
