-- Knox System Phase 5: spawn-stamp world scaling on zombies
-- Design: design/world_scaling.yaml + ADR 0019
-- Modifier loadouts: KS_Modifiers (catalog/tiers — add mods there, not here)
-- Elite loot: inv+wear attempt, then guaranteed ground drop on death.
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_WorldRank"
require "KnoxSystem/KS_WorldSpawn"
require "KnoxSystem/KS_Modifiers"
require "KnoxSystem/KS_Goblin"
require "KnoxSystem/KS_Config"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Sandbox"

KnoxSystem.WorldZombies = KnoxSystem.WorldZombies or {}

local INTENSITY_DEFAULT = 1.0

-- System Tier baseline stats only. Named Modifier tags come from KS_Modifiers loadout.
local TIER_KIT = {
    [0] = { name = "Untouched", hp = 1.00, dmg = 1.00, speed = 1.00, hear = 1.00, sight = 1.00, sprinter = 0.00 },
    [1] = { name = "Stirred",   hp = 1.15, dmg = 1.10, speed = 1.05, hear = 1.05, sight = 1.05, sprinter = 0.06 },
    [2] = { name = "Marked",    hp = 1.35, dmg = 1.20, speed = 1.10, hear = 1.10, sight = 1.10, sprinter = 0.12 },
    [3] = { name = "Claimed",   hp = 1.60, dmg = 1.35, speed = 1.15, hear = 1.20, sight = 1.20, sprinter = 0.20 },
    [4] = { name = "Apex",      hp = 2.00, dmg = 1.50, speed = 1.20, hear = 1.25, sight = 1.30, sprinter = 0.30 },
}

local ELITE_BASE_CHANCE = { [0] = 0.00, [1] = 0.02, [2] = 0.04, [3] = 0.07, [4] = 0.12 }
local ELITE_EXTRA = { hp = 1.50, dmg = 1.25, speed = 1.08, sight = 1.35, hear = 1.30, sprinter = 0.25 }

local PL_WEIGHTS = {
    ["0-9"]   = { [0] = 90, [1] = 10, [2] = 0,  [3] = 0,  [4] = 0 },
    ["10-24"] = { [0] = 60, [1] = 30, [2] = 10, [3] = 0,  [4] = 0 },
    ["25-49"] = { [0] = 35, [1] = 35, [2] = 22, [3] = 8,  [4] = 0 },
    ["50-99"] = { [0] = 15, [1] = 30, [2] = 35, [3] = 18, [4] = 2 },
    ["100"]   = { [0] = 5,  [1] = 20, [2] = 35, [3] = 30, [4] = 10 },
}
local DAY_WEIGHTS = {
    ["0-14"]   = { [0] = 85, [1] = 15, [2] = 0,  [3] = 0,  [4] = 0 },
    ["15-30"]  = { [0] = 55, [1] = 30, [2] = 15, [3] = 0,  [4] = 0 },
    ["31-60"]  = { [0] = 30, [1] = 35, [2] = 25, [3] = 10, [4] = 0 },
    ["61-120"] = { [0] = 15, [1] = 30, [2] = 35, [3] = 18, [4] = 2 },
    ["121+"]   = { [0] = 10, [1] = 25, [2] = 35, [3] = 25, [4] = 5 },
}

local PL_BLEND, DAY_BLEND = 0.55, 0.45

-- Prefer item types that exist in base B42; death drop will still try them.
local ELITE_BAGS = {
    "Base.Bag_BigHikingBag",
    "Base.Bag_NormalHikingBag",
    "Base.Bag_ALICEpack",
    "Base.Bag_ALICEpack_Army",
    "Base.Bag_SurvivorBag",
    "Base.Bag_Schoolbag",
    "Base.Bag_DuffelBag",
}
local ELITE_WEAPONS = {
    "Base.Pistol", "Base.Pistol2", "Base.Pistol3",
    "Base.Revolver", "Base.Revolver_Long",
    "Base.Shotgun", "Base.DoubleBarrelShotgun",
    "Base.AssaultRifle", "Base.HuntingRifle",
    "Base.Machete", "Base.Katana", "Base.Nightstick",
    "Base.BaseballBat", "Base.Axe",
}
local ELITE_CRAFT = {
    "Base.ScrapMetal", "Base.ElectronicsScrap", "Base.ElectricWire",
    "Base.Pipe", "Base.MetalPipe", "Base.SheetMetal", "Base.SmallSheetMetal",
    "Base.DuctTape", "Base.Glue", "Base.Woodglue", "Base.Nails", "Base.Screws",
    "Base.BlowTorch", "Base.WeldingRods", "Base.GunPowder",
    "Base.Bullets9mm", "Base.ShotgunShells", "Base.556Bullets",
    "Base.Battery", "Base.Aluminum", "Base.BarbedWire",
}

local function intensity()
    local c = KnoxSystem.Config and KnoxSystem.Config.WorldScaling
    local i = c and tonumber(c.intensity)
    if i == nil then i = INTENSITY_DEFAULT end
    if i < 0 then i = 0 end
    if i > 3 then i = 3 end
    return i
end

local function enabled()
    local c = KnoxSystem.Config and KnoxSystem.Config.WorldScaling
    if c and c.enabled == false then return false end
    return true
end

local function plBandKey(pl)
    pl = tonumber(pl) or 0
    if pl >= 100 then return "100" end
    if pl >= 50 then return "50-99" end
    if pl >= 25 then return "25-49" end
    if pl >= 10 then return "10-24" end
    return "0-9"
end

local function dayBandKey(days)
    days = tonumber(days) or 0
    if days >= 121 then return "121+" end
    if days >= 61 then return "61-120" end
    if days >= 31 then return "31-60" end
    if days >= 15 then return "15-30" end
    return "0-14"
end

local function blendWeights(pl, days, inten)
    local pw = PL_WEIGHTS[plBandKey(pl)] or PL_WEIGHTS["0-9"]
    local dw = DAY_WEIGHTS[dayBandKey(days)] or DAY_WEIGHTS["0-14"]
    local out, sum = {}, 0
    for t = 0, 4 do
        local w = (pw[t] or 0) * PL_BLEND + (dw[t] or 0) * DAY_BLEND
        if t >= 2 and inten ~= 1 then w = w * inten end
        if inten <= 0 then w = (t == 0) and 1 or 0 end
        out[t] = w
        sum = sum + w
    end
    if sum <= 0 then out[0] = 1; sum = 1 end
    return out, sum
end

local function randFloat(lo, hi)
    lo = lo or 0
    hi = hi or 1
    local r = nil
    pcall(function()
        if ZombRandFloat then
            r = ZombRandFloat(0, 1)
            r = lo + r * (hi - lo)
        end
    end)
    if r == nil then r = lo + math.random() * (hi - lo) end
    return r
end

local function rollTier(pl, days, inten)
    local weights, sum = blendWeights(pl, days, inten)
    local r, acc = randFloat(0, sum), 0
    for t = 0, 4 do
        acc = acc + (weights[t] or 0)
        if r <= acc then return t end
    end
    return 0
end

local function rollElite(tier, inten)
    local base = ELITE_BASE_CHANCE[tier] or 0
    local chance = base * (inten > 0 and inten or 0)
    if chance <= 0 then return false, chance end
    return randFloat(0, 1) < chance, chance
end

local function refPlayer()
    local p = nil
    pcall(function() if getPlayer then p = getPlayer() end end)
    if p then return p end
    for i = 0, 3 do
        local pp = nil
        pcall(function() if getSpecificPlayer then pp = getSpecificPlayer(i) end end)
        if pp then return pp end
    end
    return nil
end

local function tryNum(obj, method)
    local v = nil
    pcall(function()
        if obj and type(obj[method]) == "function" then
            v = tonumber(obj[method](obj))
        end
    end)
    return v
end

local function isCrawler(z)
    local c = false
    pcall(function()
        if type(z.isCrawling) == "function" then c = z:isCrawling() end
        if not c and type(z.isCrawler) == "function" then c = z:isCrawler() end
    end)
    return c and true or false
end

local function isZombieObj(zombie)
    if not zombie then return false end
    local ok = false
    pcall(function()
        if instanceof and instanceof(zombie, "IsoZombie") then ok = true end
    end)
    if ok then return true end
    pcall(function()
        if type(zombie.isZombie) == "function" and zombie:isZombie() then ok = true end
    end)
    if ok then return true end
    pcall(function()
        if type(zombie.getWalkType) == "function" and type(zombie.getHealth) == "function" then
            ok = true
        end
    end)
    return ok
end

local function pick(list)
    if not list or #list < 1 then return nil end
    local i = math.floor(randFloat(0, #list)) + 1
    if i < 1 then i = 1 end
    if i > #list then i = #list end
    return list[i]
end

local function createItem(typeName)
    if not typeName or typeName == "" then return nil end
    local item = nil
    pcall(function()
        if InventoryItemFactory and InventoryItemFactory.CreateItem then
            item = InventoryItemFactory.CreateItem(typeName)
        end
    end)
    if not item then
        pcall(function()
            if instanceItem then item = instanceItem(typeName) end
        end)
    end
    return item
end

local function addItemToInv(inv, typeName)
    if not inv or not typeName then return false, nil end
    local item = createItem(typeName)
    if not item then return false, nil end
    local ok = false
    pcall(function()
        inv:AddItem(item)
        ok = true
    end)
    return ok, item
end

local function tryWearBag(zombie, item)
    -- IsoZombie has no setWornItem/setAttachedItem (B42) — calling them throws even inside pcall.
    -- Elite loot is delivered via inventory + guaranteed ground drop on death instead.
    return false
end

local function applySpeedPackage(zombie, kit, elite, sprinterRoll)
    local madeSprinter = 0
    local walkBefore, walkAfter = "", ""
    pcall(function()
        if type(zombie.getWalkType) == "function" then
            walkBefore = tostring(zombie:getWalkType() or "")
        end
    end)
    walkAfter = walkBefore
    if sprinterRoll and not isCrawler(zombie) then
        local wt = pick({ "sprint1", "sprint2", "sprint3" }) or "sprint1"
        pcall(function()
            if type(zombie.setWalkType) == "function" then
                zombie:setWalkType(wt)
                madeSprinter = 1
                walkAfter = wt
            end
        end)
    end
    local speedBefore = tryNum(zombie, "getSpeedMod")
    local speedAfter = speedBefore
    local mult = (kit.speed or 1) * (elite and ELITE_EXTRA.speed or 1)
    if speedBefore and speedBefore > 0 then
        pcall(function()
            if type(zombie.setSpeedMod) == "function" then
                zombie:setSpeedMod(speedBefore * mult)
            end
        end)
        speedAfter = tryNum(zombie, "getSpeedMod")
    end
    return {
        walkBefore = walkBefore, walkAfter = walkAfter, madeSprinter = madeSprinter,
        speedBefore = speedBefore or -1, speedAfter = speedAfter or -1, speedMultApplied = mult,
    }
end

local function applySightHearing(zombie, kit, elite)
    local sightMult = (kit.sight or 1) * (elite and ELITE_EXTRA.sight or 1)
    local hearMult = (kit.hear or 1) * (elite and ELITE_EXTRA.hear or 1)
    local sightBefore = tryNum(zombie, "getSight") or tryNum(zombie, "getVisionDistance")
    local hearBefore = tryNum(zombie, "getHearing") or tryNum(zombie, "getHearDistance")
    local sightAfter, hearAfter = sightBefore, hearBefore
    local function boost(getName, setName, mult)
        local before = tryNum(zombie, getName)
        if before and before > 0 then
            pcall(function()
                if type(zombie[setName]) == "function" then zombie[setName](zombie, before * mult) end
            end)
            return tryNum(zombie, getName)
        end
        return before
    end
    sightAfter = boost("getSight", "setSight", sightMult) or sightAfter
    hearAfter = boost("getHearing", "setHearing", hearMult) or hearAfter
    return {
        sightBefore = sightBefore or -1, sightAfter = sightAfter or -1,
        hearBefore = hearBefore or -1, hearAfter = hearAfter or -1,
        sightMult = sightMult, hearMult = hearMult,
    }
end

local function applyHealthMult(zombie, mult)
    mult = tonumber(mult) or 1
    if mult < 0.05 then mult = 0.05 end
    local hBefore = tryNum(zombie, "getHealth")
    local maxBefore = tryNum(zombie, "getMaxHealth")
    local hAfter, maxAfter = hBefore, maxBefore
    if hBefore and hBefore > 0 and mult ~= 1 then
        pcall(function()
            if type(zombie.setHealth) == "function" then zombie:setHealth(hBefore * mult) end
        end)
        hAfter = tryNum(zombie, "getHealth")
    end
    if maxBefore and maxBefore > 0 and mult ~= 1 then
        pcall(function()
            if type(zombie.setMaxHealth) == "function" then zombie:setMaxHealth(maxBefore * mult) end
        end)
        maxAfter = tryNum(zombie, "getMaxHealth")
    end
    pcall(function()
        local md = zombie:getModData()
        if md then
            local peak = hAfter or hBefore or 1
            if maxAfter and maxAfter > peak then peak = maxAfter end
            md.knoxHealthPeak = peak
        end
    end)
    return {
        healthBefore = hBefore or -1, healthAfter = hAfter or -1,
        maxHealthBefore = maxBefore or -1, maxHealthAfter = maxAfter or -1,
        hpMultApplied = mult,
    }
end

-- Back-compat wrapper (old kit path)
local function applyHealth(zombie, kit, elite)
    local mult = (kit and kit.hp or 1) * (elite and ELITE_EXTRA.hp or 1)
    return applyHealthMult(zombie, mult)
end

local function applyEliteGear(zombie)
    local inv = nil
    pcall(function() inv = zombie:getInventory() end)
    local bag, wep = "", ""
    local crafts, drops = {}, {}
    local count = 0

    local bagType = pick(ELITE_BAGS)
    if inv and bagType then
        local ok, item = addItemToInv(inv, bagType)
        if ok then
            bag = bagType
            count = count + 1
            drops[#drops + 1] = bagType
            tryWearBag(zombie, item)
        else
            drops[#drops + 1] = bagType
            bag = bagType
        end
    elseif bagType then
        drops[#drops + 1] = bagType
        bag = bagType
    end

    if randFloat(0, 1) < 0.70 then
        local wType = pick(ELITE_WEAPONS)
        if inv and wType then
            local ok = addItemToInv(inv, wType)
            if ok then
                wep = wType
                count = count + 1
                drops[#drops + 1] = wType
            else
                drops[#drops + 1] = wType
                wep = wType
            end
        elseif wType then
            drops[#drops + 1] = wType
            wep = wType
        end
    end

    local nCraft = 1 + math.floor(randFloat(0, 3))
    for _ = 1, nCraft do
        local cType = pick(ELITE_CRAFT)
        if inv and cType then
            local ok = addItemToInv(inv, cType)
            if ok then
                crafts[#crafts + 1] = cType
                count = count + 1
                drops[#drops + 1] = cType
            else
                crafts[#crafts + 1] = cType
                drops[#drops + 1] = cType
            end
        elseif cType then
            crafts[#crafts + 1] = cType
            drops[#drops + 1] = cType
        end
    end

    return {
        gearBag = bag,
        gearWeapon = wep,
        gearCraft = table.concat(crafts, ","),
        gearCount = count,
        dropList = table.concat(drops, "|"),
    }
end

local function getSquare(zombie)
    local sq = nil
    pcall(function()
        if type(zombie.getCurrentSquare) == "function" then sq = zombie:getCurrentSquare() end
    end)
    if sq then return sq end
    pcall(function()
        local cell = getCell and getCell() or nil
        if cell and type(zombie.getX) == "function" then
            sq = cell:getGridSquare(
                math.floor(zombie:getX()),
                math.floor(zombie:getY()),
                math.floor(zombie:getZ() or 0)
            )
        end
    end)
    return sq
end

local function spawnWorldItem(sq, zombie, typeName)
    local item = createItem(typeName)
    if not item then return false end
    local ok = false
    if sq then
        pcall(function()
            if type(sq.AddWorldInventoryItem) == "function" then
                local dx, dy = 0.5, 0.5
                pcall(function()
                    dx = (zombie:getX() or 0) - sq:getX()
                    dy = (zombie:getY() or 0) - sq:getY()
                end)
                sq:AddWorldInventoryItem(item, dx, dy, 0)
                ok = true
            end
        end)
    end
    if not ok then
        pcall(function()
            local inv = zombie:getInventory()
            if inv then inv:AddItem(item); ok = true end
        end)
    end
    return ok
end

function KnoxSystem.WorldZombies.dropEliteLoot(zombie, reason)
    if not zombie then return false end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if not md then return false end
    if not (md.knoxElite == true or md.knoxElite == 1) then return false end
    if md.knoxLootDropped then return false end

    local listStr = tostring(md.knoxGearDropList or "")
    if listStr == "" then
        local parts = {}
        if md.knoxGearBag and tostring(md.knoxGearBag) ~= "" then parts[#parts + 1] = md.knoxGearBag end
        if md.knoxGearWeapon and tostring(md.knoxGearWeapon) ~= "" then parts[#parts + 1] = md.knoxGearWeapon end
        if md.knoxGearCraft and tostring(md.knoxGearCraft) ~= "" then
            for piece in string.gmatch(tostring(md.knoxGearCraft), "[^,]+") do
                parts[#parts + 1] = piece
            end
        end
        listStr = table.concat(parts, "|")
    end

    -- Always drop something for elite even if list empty (fallback kit)
    if listStr == "" then
        listStr = "Base.Bag_Schoolbag|Base.ScrapMetal|Base.DuctTape"
    end

    local sq = getSquare(zombie)
    local dropped, failed = 0, 0
    local droppedTypes = {}
    for typeName in string.gmatch(listStr, "[^|]+") do
        typeName = tostring(typeName or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if typeName ~= "" then
            if spawnWorldItem(sq, zombie, typeName) then
                dropped = dropped + 1
                droppedTypes[#droppedTypes + 1] = typeName
            else
                failed = failed + 1
            end
        end
    end

    md.knoxLootDropped = true

    if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("zombie") then
        KnoxSystem.Track.log("zombie", "elite_death_loot", {
            reason = tostring(reason or "death"),
            tier = tonumber(md.knoxTier) or -1,
            tierName = tostring(md.knoxTierName or ""),
            dropList = listStr,
            dropped = dropped,
            failed = failed,
            droppedTypes = table.concat(droppedTypes, ","),
        })
    end
    return dropped > 0
end

function KnoxSystem.WorldZombies.onZombieDead(zombie)
    pcall(function()
        if KnoxSystem.Goblin and KnoxSystem.Goblin.onDeath then
            if KnoxSystem.Goblin.onDeath(zombie, "OnZombieDead") then
                return
            end
        end
        KnoxSystem.WorldZombies.dropEliteLoot(zombie, "OnZombieDead")
    end)
end

local failLogCount = 0
local function failStamp(reason, extra)
    if failLogCount > 40 then return end
    failLogCount = failLogCount + 1
    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn("zombie") then return end
    extra = extra or {}
    extra.fail = tostring(reason or "?")
    KnoxSystem.Track.log("zombie", "stamp_fail", extra)
end

function KnoxSystem.WorldZombies.stamp(zombie, reason)
    local okOuter, result = pcall(function()
        if not zombie then
            failStamp("nil_zombie", { reason = tostring(reason) })
            return false
        end
        if not enabled() then
            failStamp("disabled", { reason = tostring(reason) })
            return false
        end
        if not isZombieObj(zombie) then
            failStamp("not_zombie", { reason = tostring(reason) })
            return false
        end

        local md = nil
        pcall(function()
            if type(zombie.getModData) == "function" then md = zombie:getModData() end
        end)
        if not md then
            failStamp("no_moddata", { reason = tostring(reason) })
            return false
        end
        if md.knoxWorldScaled then
            return false
        end

        local inten = intensity()
        local player = refPlayer()
        local pl, days, worldRank = 0, 0, 0
        if player and KnoxSystem.WorldRank then
            local rank, ppl, d = KnoxSystem.WorldRank.compute(player)
            worldRank = rank or 0
            pl = ppl or 0
            days = d or 0
        elseif KnoxSystem.WorldRank then
            days = KnoxSystem.WorldRank.getWorldAgeDays() or 0
        end

        local profile = nil
        if KnoxSystem.WorldSpawn and KnoxSystem.WorldSpawn.profile then
            profile = KnoxSystem.WorldSpawn.profile(worldRank)
        end

        -- Modifier framework: Goblin first (exclusive)
        if KnoxSystem.Modifiers and KnoxSystem.Modifiers.rollGoblin then
            local isGoblin, goblinId = KnoxSystem.Modifiers.rollGoblin()
            if isGoblin then
                -- Neighborhood picks sprinter vs fast shambler (design); ignore WR gate.
                md.knoxWorldScaled = true
                md.knoxSystem = true
                md.knoxGoblin = true
                md.knoxTier = 0
                md.knoxTierName = "Goblin"
                md.knoxElite = false
                md.knoxEliteRank = 0
                md.knoxEliteLabel = nil
                md.knoxGoblinExclusive = true -- never elite / never other loadout
                md.knoxTags = goblinId or "goblin"
                md.knoxEliteMods = { goblinId or "goblin" }
                md.knoxHpMult = 1
                md.knoxDmgMult = 1
                md.knoxSightMult = 1
                md.knoxHearMult = 1
                md.knoxWorldRank = worldRank
                md.knoxPL = pl
                md.knoxDays = days
                md.knoxIntensity = inten
                md.knoxLootDropped = false
                md.knoxGoblinLootDropped = false
                if KnoxSystem.Goblin and KnoxSystem.Goblin.onStamp then
                    KnoxSystem.Goblin.onStamp(zombie, md)
                else
                    -- fallback light sprint roll if Goblin module missing
                    local gSprint, gCh = false, 0
                    if KnoxSystem.WorldSpawn and KnoxSystem.WorldSpawn.rollGoblinSprinter then
                        gSprint, gCh = KnoxSystem.WorldSpawn.rollGoblinSprinter()
                    end
                    md.knoxSprinter = gSprint and true or false
                    md.knoxSprintChance = gCh or 0
                    md.knoxSpeedMult = gSprint and 1.2 or 1.05
                end
                if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("zombie") then
                    KnoxSystem.Track.log("zombie", "goblin_stamp", {
                        reason = tostring(reason or "stamp"),
                        neighbors = md.knoxGoblinNeighbors or -1,
                        sprinter = md.knoxSprinter and 1 or 0,
                        wr = worldRank,
                        note = "Exclusive Goblin — no elite/loadout",
                    })
                end
                return true
            end
        end

        -- Elite promote (WR curve) — Elite Rank replaces old System Tier elite bundle
        local elite, eliteChance = false, 0.02
        if profile and KnoxSystem.WorldSpawn.rollIsElite then
            elite, eliteChance = KnoxSystem.WorldSpawn.rollIsElite(profile)
        else
            elite, eliteChance = rollElite(0, inten)
        end
        local eliteRankId, rankDef = 0, nil
        if elite and KnoxSystem.WorldSpawn and KnoxSystem.WorldSpawn.rollEliteRank then
            eliteRankId, rankDef = KnoxSystem.WorldSpawn.rollEliteRank(profile)
        elseif elite then
            eliteRankId, rankDef = 1, (KnoxSystem.WorldSpawn and KnoxSystem.WorldSpawn.getEliteRankDef(1)) or nil
        end

        -- H1: base HP from WR only, then elite rank HP mult
        local hpMult = (profile and profile.hpMultBase) or 1
        if elite and rankDef and rankDef.hp_mult then
            hpMult = hpMult * rankDef.hp_mult
        end
        local dmgMult = 1
        local speedMult = 1
        local sightMult = 1
        local hearMult = 1
        if elite and rankDef then
            dmgMult = rankDef.dmg_mult or 1
            speedMult = rankDef.speed_mult or 1
            sightMult = rankDef.sight_mult or 1
            hearMult = rankDef.hear_mult or 1
        end

        -- Sprinter S1: Knox only adds chance at WR>=5; else leave vanilla (no Knox stamp)
        local doSprint, sprintChance, knoxDrove = false, 0, false
        if profile and KnoxSystem.WorldSpawn.rollKnoxSprinter then
            doSprint, sprintChance, knoxDrove = KnoxSystem.WorldSpawn.rollKnoxSprinter(profile, isCrawler(zombie))
        end
        if doSprint and KnoxSystem.Sandbox and KnoxSystem.Sandbox.knoxMayStampSprinters then
            if not KnoxSystem.Sandbox.knoxMayStampSprinters() then
                doSprint = false
                sprintChance = 0
            end
        end

        -- Loadout from Modifiers + WorldSpawn recipe
        local modList = {}
        if KnoxSystem.Modifiers and KnoxSystem.Modifiers.rollLoadout then
            modList = KnoxSystem.Modifiers.rollLoadout(worldRank, elite, profile) or {}
        end
        for _, mid in ipairs(modList) do
            if mid == "anchored" then
                doSprint = false
                break
            end
        end

        local kitFake = { hp = 1, dmg = dmgMult, speed = speedMult, sight = sightMult, hear = hearMult }
        local hpMultFinal = hpMult
        -- Fold Evolved etc. hp_mult after tags assigned below — applied post-modList
        local hpInfo = applyHealthMult(zombie, hpMultFinal)
        local spdInfo = applySpeedPackage(zombie, kitFake, false, doSprint)
        local senseInfo = applySightHearing(zombie, kitFake, false)
        local gearInfo = { gearBag = "", gearWeapon = "", gearCraft = "", gearCount = 0, dropList = "" }
        if elite then gearInfo = applyEliteGear(zombie) end

        local tierName = "Normal"
        local eliteLabel = nil
        if elite and rankDef then
            tierName = rankDef.display or "Elite"
            eliteLabel = rankDef.display_zombie or tierName
        end

        md.knoxWorldScaled = true
        md.knoxSystem = true
        md.knoxGoblin = false
        md.knoxTier = elite and eliteRankId or 0 -- store elite rank id when elite; 0 normal
        md.knoxTierName = tierName
        md.knoxElite = elite and true or false
        md.knoxEliteRank = elite and eliteRankId or 0
        md.knoxEliteLabel = eliteLabel
        md.knoxTags = (KnoxSystem.Modifiers and KnoxSystem.Modifiers.toTagsString(modList)) or ""
        md.knoxEliteMods = modList
        -- Easy combat cache + Evolved HP top-up
        if KnoxSystem.Modifiers and KnoxSystem.Modifiers.applyStampPassives then
            local evoHp = KnoxSystem.Modifiers.applyStampPassives(zombie, md) or 1
            if evoHp and evoHp > 1.001 then
                local extra = applyHealthMult(zombie, evoHp)
                if extra and extra.hpMultApplied then
                    hpInfo.hpMultApplied = (hpInfo.hpMultApplied or 1) * extra.hpMultApplied
                end
            end
        end
        md.knoxHpMult = hpInfo.hpMultApplied
        md.knoxDmgMult = dmgMult
        md.knoxSpeedMult = spdInfo.speedMultApplied or speedMult
        md.knoxSightMult = senseInfo.sightMult or sightMult
        md.knoxHearMult = senseInfo.hearMult or hearMult
        md.knoxSprinter = spdInfo.madeSprinter == 1
        md.knoxSprintChance = sprintChance
        md.knoxSprintKnox = knoxDrove and 1 or 0
        md.knoxWorldRank = worldRank
        md.knoxPL = pl
        md.knoxDays = days
        md.knoxIntensity = inten
        md.knoxHpBaseWR = profile and profile.hpMultBase or 1
        md.knoxEliteChance = eliteChance
        md.knoxGearBag = gearInfo.gearBag
        md.knoxGearWeapon = gearInfo.gearWeapon
        md.knoxGearCraft = gearInfo.gearCraft
        md.knoxGearCount = gearInfo.gearCount
        md.knoxGearDropList = gearInfo.dropList or ""
        md.knoxLootDropped = false

        if elite then
            pcall(function()
                if KnoxSystem.EliteTell and KnoxSystem.EliteTell.onEliteStamped then
                    KnoxSystem.EliteTell.onEliteStamped(zombie, eliteRankId, eliteLabel or tierName)
                else
                    local desc = nil
                    if type(zombie.getDescriptor) == "function" then desc = zombie:getDescriptor() end
                    if desc then
                        if type(desc.setForename) == "function" then desc:setForename("ELITE") end
                        if type(desc.setSurname) == "function" then
                            desc:setSurname(tostring(eliteLabel or tierName or "Elite"))
                        end
                    end
                    if type(zombie.addLineChatElement) == "function" then
                        local label = string.format("* %s *", tostring(eliteLabel or tierName or "Elite"))
                        local font = UIFont and (UIFont.Medium or UIFont.Small) or nil
                        if font then
                            zombie:addLineChatElement(label, 1.0, 0.82, 0.15, font, 45.0, "knox_elite")
                        else
                            zombie:addLineChatElement(label, 1.0, 0.82, 0.15)
                        end
                    end
                end
            end)
        end

        if KnoxSystem.Track and KnoxSystem.Track.isChannelOn("zombie") then
            KnoxSystem.Track.log("zombie", "stamp", {
                reason = tostring(reason or "spawn"),
                eliteRank = eliteRankId or 0,
                tierName = tierName,
                elite = elite and 1 or 0,
                eliteChance = eliteChance or 0,
                eliteLabel = eliteLabel or "",
                tags = md.knoxTags or "",
                worldRank = worldRank,
                personalLevel = pl,
                worldDays = days,
                intensity = inten,
                sprinterChance = sprintChance,
                madeSprinter = spdInfo.madeSprinter,
                walkBefore = spdInfo.walkBefore,
                walkAfter = spdInfo.walkAfter,
                speedBefore = spdInfo.speedBefore,
                speedAfter = spdInfo.speedAfter,
                speedMult = spdInfo.speedMultApplied,
                healthBefore = hpInfo.healthBefore,
                healthAfter = hpInfo.healthAfter,
                hpMult = hpInfo.hpMultApplied,
                maxHealthBefore = hpInfo.maxHealthBefore,
                maxHealthAfter = hpInfo.maxHealthAfter,
                dmgMult = dmgMult,
                sightMult = senseInfo.sightMult,
                hearMult = senseInfo.hearMult,
                gearCount = gearInfo.gearCount,
                liveTierApplied = 1,
                knoxStamped = 1,
            })
        end
        return true
    end)

    if not okOuter then
        failStamp("exception", { err = tostring(result), reason = tostring(reason) })
        return false
    end
    return result and true or false
end

function KnoxSystem.WorldZombies.onZombieUpdate(zombie)
    if not zombie then return end
    -- Cheap path: only stamp if not already scaled
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if not md or not md.knoxWorldScaled then
        KnoxSystem.WorldZombies.stamp(zombie, "update")
        pcall(function()
            if type(zombie.getModData) == "function" then md = zombie:getModData() end
        end)
    end
    -- Relentless / Anchored: clear KD if engine re-applied after hit frame
    pcall(function()
        if KnoxSystem.Modifiers and KnoxSystem.Modifiers.maintainImmunities then
            KnoxSystem.Modifiers.maintainImmunities(zombie)
        end
    end)
    -- Goblin flee / LOS despawn / neighborhood speed
    pcall(function()
        if KnoxSystem.Goblin and KnoxSystem.Goblin.onZombieUpdate then
            KnoxSystem.Goblin.onZombieUpdate(zombie)
        end
    end)
    pcall(function()
        local dead = false
        if type(zombie.isDead) == "function" then dead = zombie:isDead() end
        if type(zombie.isAlive) == "function" and not zombie:isAlive() then dead = true end
        if dead then
            if KnoxSystem.Goblin and KnoxSystem.Goblin.onDeath then
                KnoxSystem.Goblin.onDeath(zombie, "update_dead")
            end
            KnoxSystem.WorldZombies.dropEliteLoot(zombie, "update_dead")
        end
    end)
end

function KnoxSystem.WorldZombies.getDamageMult(zombie)
    if not zombie then return 1 end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if md and md.knoxDmgMult then return tonumber(md.knoxDmgMult) or 1 end
    return 1
end

print("[KnoxSystem] KS_WorldZombies loaded (WorldSpawn curves + Modifier loadout + Elite Rank + elite loot)")
