-- Warrior: Melee Proficiency — XP + full damage-chain TrackLog
-- Chain (logged): weapon base min/max → engine raw hit → vanilla weapon skill perk
--                 → vanilla Strength perk → personal Power mult → Melee Proficiency mult
require "KnoxSystem/KS_Class"
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Stats"

KnoxSystem.Warrior = KnoxSystem.Warrior or {}
KnoxSystem.Warrior.Melee = KnoxSystem.Warrior.Melee or {}

local XP_PER_DAMAGE = 1.0
local EFF_PER_LEVEL = 0.03 -- +3% Melee Proficiency design
local SPD_PER_LEVEL = 0.02

local MELEE_PERKS = {
    "Axe", "LongBlunt", "ShortBlunt", "LongBlade", "ShortBlade",
    "Spear", "Maintenance", "SmallBlade", "Blunt",
}

-- Map weapon category strings → primary perk name
local CAT_TO_PERK = {
    axe = "Axe",
    longblade = "LongBlade",
    shortblade = "ShortBlade",
    smallblade = "SmallBlade",
    blade = "LongBlade",
    longblunt = "LongBlunt",
    shortblunt = "ShortBlunt",
    blunt = "Blunt",
    spear = "Spear",
    improvised = "Blunt",
}

local function perkLevel(player, perkName)
    local lvl = nil
    pcall(function()
        if not player or type(player.getPerkLevel) ~= "function" then return end
        local p = nil
        if Perks then
            p = Perks[perkName] or Perks[string.upper(perkName)]
        end
        if p == nil and PerkFactory and PerkFactory.Perks then
            p = PerkFactory.Perks[perkName]
        end
        if p ~= nil then
            lvl = tonumber(player:getPerkLevel(p))
        end
    end)
    return lvl
end

local function numWeapon(weapon, getters)
    if not weapon then return nil end
    for i = 1, #getters do
        local g = getters[i]
        local v = nil
        pcall(function()
            if type(weapon[g]) == "function" then
                v = tonumber(weapon[g](weapon))
            end
        end)
        if v ~= nil then return v end
    end
    return nil
end

local function weaponInfo(weapon)
    local info = {
        weapon = "bare_or_unknown",
        ranged = 0,
        categories = "",
        baseMin = -1,
        baseMax = -1,
        baseAvg = -1,
        baseDoor = -1,
        critChance = -1,
        critDmgMult = -1,
    }
    if not weapon then return info end
    pcall(function()
        if weapon.getName then info.weapon = tostring(weapon:getName() or info.weapon) end
        if weapon.getDisplayName then info.weapon = tostring(weapon:getDisplayName() or info.weapon) end
        if weapon.getType then info.weaponType = tostring(weapon:getType()) end
        if weapon.getFullType then
            pcall(function() info.fullType = tostring(weapon:getFullType()) end)
        end
        if weapon.isRanged and weapon:isRanged() then info.ranged = 1 end
        if weapon.getCategories then
            local cats = weapon:getCategories()
            if cats then
                local parts = {}
                local n = 0
                pcall(function() n = cats:size() end)
                for i = 0, (n or 0) - 1 do
                    local c = nil
                    pcall(function() c = cats:get(i) end)
                    if c then parts[#parts + 1] = tostring(c) end
                end
                info.categories = table.concat(parts, ",")
            end
        end
        if weapon.getSwingAnim then
            pcall(function() info.swingAnim = tostring(weapon:getSwingAnim()) end)
        end
    end)
    local mn = numWeapon(weapon, { "getMinDamage", "getMinDmg" })
    local mx = numWeapon(weapon, { "getMaxDamage", "getMaxDmg" })
    if mn ~= nil then info.baseMin = mn end
    if mx ~= nil then info.baseMax = mx end
    if mn ~= nil and mx ~= nil then info.baseAvg = (mn + mx) * 0.5 end
    local door = numWeapon(weapon, { "getDoorDamage" })
    if door ~= nil then info.baseDoor = door end
    local cc = numWeapon(weapon, { "getCriticalChance", "getCritChance" })
    if cc ~= nil then info.critChance = cc end
    local cm = numWeapon(weapon, { "getCritDmgMultiplier", "getCriticalDamageMultiplier" })
    if cm ~= nil then info.critDmgMult = cm end
    return info
end

local function resolveWeaponSkillPerk(weapon, categories)
    local blob = string.lower(tostring(categories or ""))
    -- Prefer longer/more specific keys first
    local order = {
        "longblade", "shortblade", "smallblade", "longblunt", "shortblunt",
        "axe", "spear", "blunt", "blade", "improvised",
    }
    for i = 1, #order do
        local k = order[i]
        if blob:find(k, 1, true) and CAT_TO_PERK[k] then
            return CAT_TO_PERK[k]
        end
    end
    -- fallback from type name
    local t = ""
    pcall(function()
        if weapon and weapon.getType then t = string.lower(tostring(weapon:getType() or "")) end
    end)
    for i = 1, #order do
        local k = order[i]
        if t:find(k, 1, true) and CAT_TO_PERK[k] then
            return CAT_TO_PERK[k]
        end
    end
    return nil
end

local function meleePerkSnapshot(player)
    local parts = {}
    local sum = 0
    local count = 0
    for i = 1, #MELEE_PERKS do
        local name = MELEE_PERKS[i]
        local lv = perkLevel(player, name)
        if lv ~= nil then
            parts[#parts + 1] = string.format("%s=%d", name, lv)
            sum = sum + lv
            count = count + 1
        end
    end
    return table.concat(parts, ","), sum, count
end

function KnoxSystem.Warrior.Melee.getLevel(player)
    local data = KnoxSystem.getPlayerData and KnoxSystem.getPlayerData(player)
    if not data then
        data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    end
    return KnoxSystem.Class.getSkillLevel(data, "MeleeProficiency")
end

function KnoxSystem.Warrior.Melee.damageMult(player)
    local lv = KnoxSystem.Warrior.Melee.getLevel(player)
    return 1.0 + lv * EFF_PER_LEVEL
end

function KnoxSystem.Warrior.Melee.attackSpeedMult(player)
    local lv = KnoxSystem.Warrior.Melee.getLevel(player)
    return 1.0 + lv * SPD_PER_LEVEL
end

--- Full designed stack + weapon base stats for TrackLog.
--- raw = engine-reported hit damage (already includes vanilla skill/str internally).
function KnoxSystem.Warrior.Melee.calcBreakdown(player, damage, weapon)
    damage = tonumber(damage) or 0
    local meleeLv = KnoxSystem.Warrior.Melee.getLevel(player)
    local meleeEffMult = KnoxSystem.Warrior.Melee.damageMult(player)
    local meleeSpdMult = KnoxSystem.Warrior.Melee.attackSpeedMult(player)

    local powerMult = 1
    local personalPower = 0
    if KnoxSystem.Stats then
        if KnoxSystem.Stats.meleeDamageMult then
            powerMult = KnoxSystem.Stats.meleeDamageMult(player) or 1
        end
        local snap = nil
        if KnoxSystem.Stats.snapshotPower then
            snap = KnoxSystem.Stats.snapshotPower(player)
        elseif KnoxSystem.Stats.snapshotStrength then
            snap = KnoxSystem.Stats.snapshotStrength(player)
        end
        if snap then
            personalPower = snap.personalPower or snap.personalStrength or 0
            powerMult = snap.powerMult or snap.strengthMult or powerMult
        end
    end

    local baseStrPerk = perkLevel(player, "Strength") -- vanilla Strength skill
    local w = weaponInfo(weapon)
    local wSkillName = resolveWeaponSkillPerk(weapon, w.categories) or ""
    local wSkillLv = -1
    if wSkillName ~= "" then
        local lv = perkLevel(player, wSkillName)
        if lv ~= nil then wSkillLv = lv end
    end

    local perkStr, perkSum, perkCount = meleePerkSnapshot(player)

    -- Theoretical Knox stack ON TOP of engine raw (raw already baked vanilla mods)
    local afterPower = damage * powerMult
    local designedDmg = damage * powerMult * meleeEffMult
    local xp = damage * XP_PER_DAMAGE

    -- From weapon plate (script min/max) — pre-vanilla
    local baseAvg = w.baseAvg
    local designedFromBase = -1
    if baseAvg and baseAvg > 0 then
        -- Reference only: baseAvg * power * melee (vanilla skill not modeled as a clean mult)
        designedFromBase = baseAvg * powerMult * meleeEffMult
    end

    return {
        -- Chain labels (grep-friendly order)
        chain = "baseWeapon → engineRaw(vanilla skill+str) → ×Power → ×MeleeProf",
        baseMin = w.baseMin,
        baseMax = w.baseMax,
        baseAvg = w.baseAvg,
        rawDmg = damage, -- engine hit
        weaponSkill = wSkillName,
        weaponSkillLv = wSkillLv,
        baseStrengthPerk = baseStrPerk ~= nil and baseStrPerk or -1, -- vanilla Strength
        personalPower = personalPower, -- Knox Power (was Strength)
        powerMult = powerMult,
        powerLv = personalPower,
        meleeLv = meleeLv,
        meleeEffMult = meleeEffMult,
        meleeSpdMult = meleeSpdMult,
        dmgAfterPower = afterPower,
        dmgAfterMelee = damage * meleeEffMult,
        designedDmg = designedDmg, -- raw * power * meleeProf
        designedFromBaseAvg = designedFromBase,
        xpGain = xp,
        xpPerDmg = XP_PER_DAMAGE,
        designLever = "prefer_base_melee_skill_effectiveness",
        effPerLevel = EFF_PER_LEVEL,
        liveMeleeApplied = 0,
        livePowerApplied = (personalPower > 0) and 1 or 0,
        -- legacy keys
        strMult = powerMult,
        personalStrength = personalPower, -- legacy alias
        liveStrApplied = 0,
        dmgAfterStr = afterPower,
        weapon = w.weapon,
        weaponType = w.weaponType or "",
        fullType = w.fullType or "",
        weaponCats = w.categories or "",
        critChance = w.critChance,
        critDmgMult = w.critDmgMult,
        ranged = w.ranged,
        meleePerks = perkStr,
        meleePerkSum = perkSum,
        meleePerkCount = perkCount,
        note = "rawDmg=engine (vanilla weapon skill+Strength baked in); Power LIVE adds bonus≈raw*(powerMult-1) + knockdown; designedDmg=raw*powerMult*meleeEffMult",
    }
end

function KnoxSystem.Warrior.Melee.onDealtDamage(player, target, damage, weapon)
    if not player or not damage or damage <= 0 then return end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")

    if weapon == nil then
        pcall(function()
            if type(player.getPrimaryHandItem) == "function" then
                weapon = player:getPrimaryHandItem()
            end
        end)
    end

    local br = KnoxSystem.Warrior.Melee.calcBreakdown(player, damage, weapon)
    local isWarrior = KnoxSystem.Class.isWarrior(data)
    br.warrior = isWarrior and 1 or 0

    if isWarrior then
        KnoxSystem.Class.addSkillXp(player, "MeleeProficiency", br.xpGain, "melee_dmg")
        -- Sharpness dull negation (A2): refund after vanilla applied loss on this hit
        local sharpInfo = KnoxSystem.Warrior.Melee.refundSharpnessLoss(player, weapon, "combat_hit")
        if sharpInfo then
            br.sharpPrev = sharpInfo.prev
            br.sharpAfterVanilla = sharpInfo.afterVanilla
            br.sharpRestored = sharpInfo.restored
            br.sharpFinal = sharpInfo.final
            br.sharpNegatePct = sharpInfo.negatePct
            br.sharpLive = 1
        end
    end

    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("damage") then
        local tgt = "?"
        pcall(function()
            if target and target.getOutfitName then tgt = tostring(target:getOutfitName()) end
            if target and target.getName then tgt = tostring(target:getName() or tgt) end
        end)
        br.target = tgt
        br.dmgMult = br.meleeEffMult
        br.spdMult = br.meleeSpdMult
        br.scaledDmg = br.designedDmg
        KnoxSystem.Track.log("damage", "melee_hit", br)

        if KnoxSystem.Stats then
            if KnoxSystem.Stats.logPower then
                KnoxSystem.Stats.logPower(player, "melee_hit")
            elseif KnoxSystem.Stats.logStrength then
                KnoxSystem.Stats.logStrength(player, "melee_hit")
            end
        end
    end
end

---------------------------------------------------------------------------
-- Sharpness degradation negation (A2)
-- 8% less sharpness loss per Melee Proficiency level → 80% at L10.
-- Vanilla dulls in Java first; we snapshot held weapons, then refund delta.
---------------------------------------------------------------------------
local SHARP_NEGATE_PER_LEVEL = 0.08
local sharpSnap = {} -- [playerId][weaponKey] = sharpness

local function isIsoPlayer(o)
    local ok = false
    pcall(function()
        if o and instanceof and instanceof(o, "IsoPlayer") then ok = true end
    end)
    return ok
end

local function playerNum(player)
    local id = 0
    pcall(function() if player and player.getPlayerNum then id = player:getPlayerNum() or 0 end end)
    return id
end

local function weaponKey(weapon)
    if not weapon then return nil end
    local k = nil
    pcall(function()
        if weapon.getID then k = "id:" .. tostring(weapon:getID()) end
    end)
    if k then return k end
    pcall(function()
        if weapon.getFullType then k = "ft:" .. tostring(weapon:getFullType()) end
    end)
    if k then return k end
    return tostring(weapon)
end

function KnoxSystem.Warrior.Melee.getSharpness(weapon)
    if not weapon then return nil end
    local v = numWeapon(weapon, {
        "getSharpness", "getHeadSharpness", "getBladeSharpness",
    })
    if v ~= nil then return v end
    -- Some builds store on modData
    pcall(function()
        local md = weapon:getModData()
        if md then
            if md.sharpness ~= nil then v = tonumber(md.sharpness) end
            if v == nil and md.Sharpness ~= nil then v = tonumber(md.Sharpness) end
        end
    end)
    return v
end

function KnoxSystem.Warrior.Melee.setSharpness(weapon, value)
    if not weapon or value == nil then return false end
    value = tonumber(value)
    if value == nil then return false end
    local ok = false
    pcall(function()
        if type(weapon.setSharpness) == "function" then
            weapon:setSharpness(value)
            ok = true
        end
    end)
    if not ok then
        pcall(function()
            if type(weapon.setHeadSharpness) == "function" then
                weapon:setHeadSharpness(value)
                ok = true
            end
        end)
    end
    if not ok then
        pcall(function()
            local md = weapon:getModData()
            if md then
                md.sharpness = value
                ok = true
            end
        end)
    end
    return ok
end

function KnoxSystem.Warrior.Melee.getSharpnessMax(weapon)
    if not weapon then return nil end
    local mx = numWeapon(weapon, { "getSharpnessMax", "getMaxSharpness" })
    if mx ~= nil then return mx end
    -- Cap often tied to condition / head condition
    local cond = numWeapon(weapon, { "getCondition", "getHeadCondition" })
    local condMax = numWeapon(weapon, { "getConditionMax", "getMaxCondition", "getHeadConditionMax" })
    if cond ~= nil and condMax ~= nil and condMax > 0 then
        -- sharpness scale sometimes 0–1, sometimes 0–10; use current max guess from condition ratio
        local cur = KnoxSystem.Warrior.Melee.getSharpness(weapon)
        if cur ~= nil and cur <= 1.01 then
            return 1.0
        end
        return condMax
    end
    local cur = KnoxSystem.Warrior.Melee.getSharpness(weapon)
    if cur ~= nil and cur <= 1.01 then return 1.0 end
    return nil
end

function KnoxSystem.Warrior.Melee.sharpnessNegateFraction(player)
    local lv = KnoxSystem.Warrior.Melee.getLevel(player)
    if lv < 1 then return 0 end
    if lv > 10 then lv = 10 end
    local f = SHARP_NEGATE_PER_LEVEL * lv
    if f > 0.95 then f = 0.95 end -- hard safety; design L10 = 0.80
    return f
end

local function handsWeapons(player)
    local list = {}
    pcall(function()
        if type(player.getPrimaryHandItem) == "function" then
            local w = player:getPrimaryHandItem()
            if w then list[#list + 1] = w end
        end
        if type(player.getSecondaryHandItem) == "function" then
            local w = player:getSecondaryHandItem()
            if w then list[#list + 1] = w end
        end
    end)
    return list
end

--- Snapshot held weapons' sharpness (call frequently so hit can see pre-dull value).
function KnoxSystem.Warrior.Melee.snapshotHeldSharpness(player)
    if not isIsoPlayer(player) then return end
    local id = playerNum(player)
    sharpSnap[id] = sharpSnap[id] or {}
    local bag = sharpSnap[id]
    local seen = {}
    local weapons = handsWeapons(player)
    for i = 1, #weapons do
        local w = weapons[i]
        local key = weaponKey(w)
        local s = KnoxSystem.Warrior.Melee.getSharpness(w)
        if key and s ~= nil then
            bag[key] = s
            seen[key] = true
        end
    end
    -- drop keys for weapons no longer held (avoid stale undo)
    for k, _ in pairs(bag) do
        if not seen[k] then bag[k] = nil end
    end
end

--- After vanilla may have dulled: restore fraction of any drop vs last snapshot.
--- Returns info table if a refund applied, or nil.
function KnoxSystem.Warrior.Melee.refundSharpnessLoss(player, weapon, reason)
    if not isIsoPlayer(player) or not weapon then return nil end
    local data = KnoxSystem.getPlayerData(player)
    if not data or not KnoxSystem.Class.isWarrior(data) then return nil end
    local lv = KnoxSystem.Warrior.Melee.getLevel(player)
    if lv < 1 then return nil end

    local frac = KnoxSystem.Warrior.Melee.sharpnessNegateFraction(player)
    if frac <= 0 then return nil end

    local key = weaponKey(weapon)
    local id = playerNum(player)
    local bag = sharpSnap[id]
    local prev = bag and key and bag[key] or nil
    local cur = KnoxSystem.Warrior.Melee.getSharpness(weapon)
    if cur == nil then return nil end

    -- If no prev, try weapon modData cache
    if prev == nil then
        pcall(function()
            local md = weapon:getModData()
            if md and md._knoxSharpSnap ~= nil then prev = tonumber(md._knoxSharpSnap) end
        end)
    end
    if prev == nil then
        -- seed and exit
        if bag and key then bag[key] = cur end
        pcall(function()
            local md = weapon:getModData()
            if md then md._knoxSharpSnap = cur end
        end)
        return nil
    end

    local loss = prev - cur
    if loss <= 1e-6 then
        -- no dull (or sharpness increased); refresh snap
        if bag and key then bag[key] = cur end
        pcall(function()
            local md = weapon:getModData()
            if md then md._knoxSharpSnap = cur end
        end)
        return nil
    end

    local restore = loss * frac
    local final = cur + restore
    local mx = KnoxSystem.Warrior.Melee.getSharpnessMax(weapon)
    if mx ~= nil and final > mx then final = mx end
    if final > prev then final = prev end -- never above pre-hit

    local wrote = KnoxSystem.Warrior.Melee.setSharpness(weapon, final)
    local afterWrite = KnoxSystem.Warrior.Melee.getSharpness(weapon) or final
    if bag and key then bag[key] = afterWrite end
    pcall(function()
        local md = weapon:getModData()
        if md then md._knoxSharpSnap = afterWrite end
    end)

    local info = {
        reason = tostring(reason or "hit"),
        meleeLv = lv,
        negatePct = frac,
        prev = prev,
        afterVanilla = cur,
        loss = loss,
        restored = restore,
        final = afterWrite,
        wrote = wrote and 1 or 0,
        liveSharpNegate = 1,
    }

    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("damage") then
        KnoxSystem.Track.log("damage", "sharpness_refund", info)
    end
    return info
end

--- Tree / world / thump dull path (A2).
function KnoxSystem.Warrior.Melee.onWorldWeaponUse(player, weapon, reason)
    if not isIsoPlayer(player) then return end
    if weapon == nil then
        pcall(function()
            if type(player.getPrimaryHandItem) == "function" then
                weapon = player:getPrimaryHandItem()
            end
        end)
    end
    if not weapon then return end
    -- ranged skip
    local ranged = false
    pcall(function()
        if weapon.isRanged and weapon:isRanged() then ranged = true end
    end)
    if ranged then return end
    KnoxSystem.Warrior.Melee.refundSharpnessLoss(player, weapon, reason or "world_use")
    -- also secondary if dual
    pcall(function()
        local sec = player:getSecondaryHandItem()
        if sec and sec ~= weapon then
            KnoxSystem.Warrior.Melee.refundSharpnessLoss(player, sec, (reason or "world_use") .. "_sec")
        end
    end)
end

--- Throttled snapshot on player update so combat/tree hits have a baseline.
local lastSnapMs = {}
function KnoxSystem.Warrior.Melee.onPlayerUpdate(player)
    if not isIsoPlayer(player) then return end
    local id = playerNum(player)
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    local last = lastSnapMs[id] or 0
    -- high frequency so we catch pre-dull value near hits
    if t > 0 and last > 0 and (t - last) < 50 then return end
    lastSnapMs[id] = t
    KnoxSystem.Warrior.Melee.snapshotHeldSharpness(player)
end

print("[KnoxSystem] KS_Warrior_Melee loaded (damage chain + sharpness refund A2 8%/lv)")
