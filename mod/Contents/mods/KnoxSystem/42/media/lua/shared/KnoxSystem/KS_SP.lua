-- KnoxSystem Skill Points cart + commit
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"
require "KnoxSystem/KS_Level"
require "KnoxSystem/KS_SystemSkills"

KnoxSystem.SP = KnoxSystem.SP or {}

local STAT_KEYS = {
    Power = "stat_power",
    Strength = "stat_power", -- legacy cart key alias
    Endurance = "stat_endurance",
    Mind = "stat_mind",
    Resilience = "stat_resilience",
}

-- Per-stat caps / SP cost (Power = effective Strength ranks)
local STAT_MAX = {
    Power = 10,
    Endurance = 20,
    Mind = 20,
    Resilience = 20,
}
local STAT_COST = {
    Power = 2,
    Endurance = 1,
    Mind = 1,
    Resilience = 1,
}

local function statMax(statName)
    return STAT_MAX[statName] or 20
end

local function statCostPerLevel(statName)
    return STAT_COST[statName] or 1
end

function KnoxSystem.SP.statField(statName)
    return STAT_KEYS[statName]
end

function KnoxSystem.SP.isSystemSkill(name)
    return KnoxSystem.SystemSkills and KnoxSystem.SystemSkills.DEFS and KnoxSystem.SystemSkills.DEFS[name] ~= nil
end

function KnoxSystem.SP.getData(player)
    return KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
end

function KnoxSystem.SP.ensureCarts(data)
    if type(data.sp_cart_stats) ~= "table" then data.sp_cart_stats = {} end
    if type(data.sp_cart_skills) ~= "table" then data.sp_cart_skills = {} end
    -- Rename cart key Strength → Power
    if data.sp_cart_stats.Strength and not data.sp_cart_stats.Power then
        data.sp_cart_stats.Power = data.sp_cart_stats.Strength
    end
    data.sp_cart_stats.Strength = nil
    if KnoxSystem.SystemSkills and KnoxSystem.SystemSkills.ensureFields then
        KnoxSystem.SystemSkills.ensureFields(data)
    end
end

function KnoxSystem.SP.costOneSkillLevel(targetLevel)
    if targetLevel < 1 then return 0 end
    return math.ceil(targetLevel / 2)
end

function KnoxSystem.SP.costSkillPending(currentLevel, pending)
    local cost = 0
    pending = pending or 0
    for i = 1, pending do
        cost = cost + KnoxSystem.SP.costOneSkillLevel(currentLevel + i)
    end
    return cost
end

function KnoxSystem.SP.costStatPending(statName, pending)
    pending = pending or 0
    return pending * statCostPerLevel(statName)
end

function KnoxSystem.SP.totalCartCostStats(data)
    KnoxSystem.SP.ensureCarts(data)
    local total = 0
    for name, pend in pairs(data.sp_cart_stats) do
        pend = pend or 0
        if pend > 0 then
            if KnoxSystem.SP.isSystemSkill(name) then
                local def = KnoxSystem.SystemSkills.DEFS[name]
                local cur = data[def.field] or 0
                total = total + KnoxSystem.SystemSkills.costPending(name, cur, pend)
            else
                total = total + KnoxSystem.SP.costStatPending(name, pend)
            end
        end
    end
    return total
end

function KnoxSystem.SP.totalCartCostSkills(data, player)
    KnoxSystem.SP.ensureCarts(data)
    local total = 0
    for skillKey, pend in pairs(data.sp_cart_skills) do
        local cur = KnoxSystem.SP.getBaseSkillLevel(player, skillKey)
        total = total + KnoxSystem.SP.costSkillPending(cur, pend)
    end
    return total
end

function KnoxSystem.SP.unspent(data)
    return data.skill_points_unspent or 0
end

function KnoxSystem.SP.availableAfterCarts(data, player, excludeTab)
    local unspent = KnoxSystem.SP.unspent(data)
    if excludeTab == "skills" then
        return unspent - KnoxSystem.SP.totalCartCostStats(data)
    elseif excludeTab == "stats" then
        return unspent - KnoxSystem.SP.totalCartCostSkills(data, player)
    end
    return unspent - KnoxSystem.SP.totalCartCostStats(data) - KnoxSystem.SP.totalCartCostSkills(data, player)
end

function KnoxSystem.SP.availableForStatsCart(data, player)
    return KnoxSystem.SP.unspent(data) - KnoxSystem.SP.totalCartCostStats(data)
end

function KnoxSystem.SP.availableForSkillsCart(data, player)
    return KnoxSystem.SP.unspent(data) - KnoxSystem.SP.totalCartCostSkills(data, player)
end

function KnoxSystem.SP.getBaseSkillLevel(player, skillKey)
    if not player then return 0 end
    local perk = KnoxSystem.SP.resolvePerk(skillKey)
    if not perk then return 0 end
    -- Strength must use REAL level (Power boosts getPerkLevel for gameplay checks only)
    local function read()
        local ok, lvl = pcall(function() return player:getPerkLevel(perk) end)
        if ok and lvl then return tonumber(lvl) or 0 end
        return 0
    end
    if skillKey == "Strength" or (Perks and perk == Perks.Strength) then
        if KnoxSystem.Power and KnoxSystem.Power.withRawPerkLevel then
            return KnoxSystem.Power.withRawPerkLevel(read)
        end
    end
    return read()
end

function KnoxSystem.SP.resolvePerk(skillKey)
    if not skillKey then return nil end
    if Perks and Perks[skillKey] then return Perks[skillKey] end
    local aliases = {
        Aiming = "Aiming", Reloading = "Reloading",
        ["Long Blade"] = "LongBlade", LongBlade = "LongBlade",
        ["Long Blunt"] = "Blunt", LongBlunt = "Blunt", Blunt = "Blunt",
        Maintenance = "Maintenance",
        ["Short Blade"] = "SmallBlade", ShortBlade = "SmallBlade", SmallBlade = "SmallBlade",
        ["Short Blunt"] = "SmallBlunt", ShortBlunt = "SmallBlunt", SmallBlunt = "SmallBlunt",
        Blacksmithing = "Blacksmith", Blacksmith = "Blacksmith",
        Carpentry = "Woodwork", Woodwork = "Woodwork", Carving = "Carving", Cooking = "Cooking",
        Electrical = "Electricity", Electricity = "Electricity",
        Glassmaking = "Glassmaking", Knapping = "FlintKnapping", FlintKnapping = "FlintKnapping",
        Masonry = "Masonry", Mechanics = "Mechanics", Pottery = "Pottery", Tailoring = "Tailoring",
        Welding = "MetalWelding", MetalWelding = "MetalWelding", MetalWork = "MetalWelding",
        Agriculture = "Farming", Farming = "Farming",
        ["Animal Care"] = "Husbandry", AnimalCare = "Husbandry", Husbandry = "Husbandry",
        Butchering = "Butchering", Fitness = "Fitness",
        Lightfooted = "Lightfoot", Lightfoot = "Lightfoot", Nimble = "Nimble",
        Running = "Sprinting", Sprinting = "Sprinting", Sprint = "Sprinting",
        Sneaking = "Sneak", Sneak = "Sneak", Strength = "Strength",
        ["First Aid"] = "Doctor", FirstAid = "Doctor", Doctor = "Doctor",
        Fishing = "Fishing", Foraging = "PlantScavenging", PlantScavenging = "PlantScavenging",
        Tracking = "Tracking", Trapping = "Trapping",
    }
    local key = aliases[skillKey] or skillKey
    if Perks and Perks[key] then return Perks[key] end
    local nospace = tostring(skillKey):gsub("%s+", "")
    if Perks and Perks[nospace] then return Perks[nospace] end
    if aliases[nospace] and Perks and Perks[aliases[nospace]] then return Perks[aliases[nospace]] end
    if Perks and Perks.FromString then
        for _, try in ipairs({ skillKey, key, nospace }) do
            local ok, p = pcall(function() return Perks.FromString(try) end)
            if ok and p then return p end
        end
    end
    return nil
end

function KnoxSystem.SP.skillMaxLevel(player, skillKey)
    return 10
end

function KnoxSystem.SP.plusStat(player, statName)
    local data = KnoxSystem.SP.getData(player)
    if not data then return false, "no data" end
    KnoxSystem.SP.ensureCarts(data)

    if KnoxSystem.SP.isSystemSkill(statName) then
        local def = KnoxSystem.SystemSkills.DEFS[statName]
        local cur = data[def.field] or 0
        local pend = data.sp_cart_stats[statName] or 0
        if cur + pend >= def.max then return false, "max" end
        local nextCost = def.costPerLevel or 5
        if KnoxSystem.SP.availableForStatsCart(data, player) < nextCost then return false, "sp" end
        data.sp_cart_stats[statName] = pend + 1
        return true
    end

    local field = STAT_KEYS[statName]
    if not field then return false, "bad stat" end
    local cur = data[field] or 0
    local pend = data.sp_cart_stats[statName] or 0
    local maxL = statMax(statName)
    if cur + pend >= maxL then return false, "max" end
    local nextCost = statCostPerLevel(statName)
    if KnoxSystem.SP.availableForStatsCart(data, player) < nextCost then return false, "sp" end
    data.sp_cart_stats[statName] = pend + 1
    return true
end

function KnoxSystem.SP.minusStat(player, statName)
    local data = KnoxSystem.SP.getData(player)
    if not data then return false end
    KnoxSystem.SP.ensureCarts(data)
    local pend = data.sp_cart_stats[statName] or 0
    if pend <= 0 then return false end
    pend = pend - 1
    if pend <= 0 then data.sp_cart_stats[statName] = nil else data.sp_cart_stats[statName] = pend end
    return true
end

function KnoxSystem.SP.plusSkill(player, skillKey)
    local data = KnoxSystem.SP.getData(player)
    if not data then return false, "no data" end
    KnoxSystem.SP.ensureCarts(data)
    local perk = KnoxSystem.SP.resolvePerk(skillKey)
    if not perk then return false, "no perk" end
    local cur = KnoxSystem.SP.getBaseSkillLevel(player, skillKey)
    local pend = data.sp_cart_skills[skillKey] or 0
    local maxL = KnoxSystem.SP.skillMaxLevel(player, skillKey)
    if cur + pend >= maxL then return false, "max" end
    local nextCost = KnoxSystem.SP.costOneSkillLevel(cur + pend + 1)
    if KnoxSystem.SP.availableForSkillsCart(data, player) < nextCost then return false, "sp" end
    data.sp_cart_skills[skillKey] = pend + 1
    return true
end

function KnoxSystem.SP.minusSkill(player, skillKey)
    local data = KnoxSystem.SP.getData(player)
    if not data then return false end
    KnoxSystem.SP.ensureCarts(data)
    local pend = data.sp_cart_skills[skillKey] or 0
    if pend <= 0 then return false end
    pend = pend - 1
    if pend <= 0 then data.sp_cart_skills[skillKey] = nil else data.sp_cart_skills[skillKey] = pend end
    return true
end

function KnoxSystem.SP.confirmStats(player)
    local data = KnoxSystem.SP.getData(player)
    if not data then return false, "no data" end
    KnoxSystem.SP.ensureCarts(data)
    local cost = KnoxSystem.SP.totalCartCostStats(data)
    if cost <= 0 then return false, "empty" end
    if KnoxSystem.SP.unspent(data) < cost then return false, "sp" end

    for statName, pend in pairs(data.sp_cart_stats) do
        if pend and pend > 0 then
            if KnoxSystem.SP.isSystemSkill(statName) then
                local def = KnoxSystem.SystemSkills.DEFS[statName]
                local cur = data[def.field] or 0
                local add = math.min(pend, def.max - cur)
                data[def.field] = cur + add
                print(string.format("[KnoxSystem] SystemSkill %s -> %d", statName, data[def.field]))
            else
                local field = STAT_KEYS[statName]
                if field then
                    local cur = data[field] or 0
                    local add = math.min(pend, statMax(statName) - cur)
                    data[field] = cur + add
                    if field == "stat_power" and KnoxSystem.Power and KnoxSystem.Power.clampData then
                        KnoxSystem.Power.clampData(data)
                    end
                    print(string.format("[KnoxSystem] Stat %s -> %d", statName, data[field]))
                end
            end
        end
    end
    data.skill_points_unspent = KnoxSystem.SP.unspent(data) - cost
    data.sp_cart_stats = {}
    if KnoxSystem.Stats and KnoxSystem.Stats.applyAll then
        KnoxSystem.Stats.applyAll(player, data)
    end
    if KnoxSystem.Power and KnoxSystem.Power.onGameStart then
        pcall(function() KnoxSystem.Power.onGameStart(player) end)
    end
    if KnoxSystem.Power and KnoxSystem.Power.onPowerChanged then
        pcall(function() KnoxSystem.Power.onPowerChanged(player) end)
    end
    if KnoxSystem.UCWF and KnoxSystem.UCWF.recomputeCarryWeight_KnoxPower then
        pcall(function() KnoxSystem.UCWF.recomputeCarryWeight_KnoxPower(player) end)
    end
    if KnoxSystem.DStorage and KnoxSystem.DStorage.sync then
        local okSync, errSync = pcall(function()
            KnoxSystem.DStorage.sync(player, data)
        end)
        if not okSync then
            print("[KnoxSystem] DStorage.sync ERROR after confirmStats: " .. tostring(errSync))
        end
    else
        print("[KnoxSystem] DStorage.sync missing after confirmStats (module not loaded?)")
    end
    print(string.format("[KnoxSystem] Confirmed stats cart (-%d SP, remaining %d)", cost, data.skill_points_unspent))
    return true
end

function KnoxSystem.SP.confirmSkills(player)
    local data = KnoxSystem.SP.getData(player)
    if not data then return false, "no data" end
    KnoxSystem.SP.ensureCarts(data)
    local cost = KnoxSystem.SP.totalCartCostSkills(data, player)
    if cost <= 0 then return false, "empty" end
    if KnoxSystem.SP.unspent(data) < cost then return false, "sp" end

    for skillKey, pend in pairs(data.sp_cart_skills) do
        local perk = KnoxSystem.SP.resolvePerk(skillKey)
        if perk and pend and pend > 0 then
            for i = 1, pend do
                local ok, err = pcall(function()
                    player:LevelPerk(perk)
                end)
                if not ok then
                    print("[KnoxSystem] LevelPerk failed " .. tostring(skillKey) .. " " .. tostring(err))
                end
            end
            print(string.format("[KnoxSystem] Skill %s +%d levels -> %d",
                skillKey, pend, KnoxSystem.SP.getBaseSkillLevel(player, skillKey)))
        end
    end
    data.skill_points_unspent = KnoxSystem.SP.unspent(data) - cost
    data.sp_cart_skills = {}
    print(string.format("[KnoxSystem] Confirmed skills cart (-%d SP, remaining %d)", cost, data.skill_points_unspent))
    return true
end

function KnoxSystem.SP.clearCartsOnDeath(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return end
    data.sp_cart_stats = {}
    data.sp_cart_skills = {}
end

KnoxSystem.SP.PURCHASABLE_SKILLS = {
    "Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance",
    "Aiming", "Reloading",
    "Sprinting", "Lightfooted", "Nimble", "Sneaking",
    "Strength", "Fitness",
    "Woodwork", "Cooking", "Farming", "Doctor", "Electricity", "MetalWelding",
    "Mechanics", "Tailoring", "PlantScavenging", "Fishing", "Trapping",
}

print("[KnoxSystem] KS_SP loaded")
