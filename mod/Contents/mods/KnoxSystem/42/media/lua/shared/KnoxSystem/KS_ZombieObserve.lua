-- Observe zombies near the player for World Rank / tier scaling verification.
-- Logs once per zombie (id) when first seen; again on melee hit with combat fields.
-- Note: spawn-stamp tiers + stat kits are design-locked but not fully applied yet —
-- liveApplied reflects whether knox modData tier package is present.
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_WorldRank"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.ZombieObserve = KnoxSystem.ZombieObserve or {}

local SCAN_INTERVAL_MS = 2000
local SEE_RANGE = 18 -- tiles-ish
local seen = {} -- [zombieKey] = true (lifetime of session)
local lastScan = {}

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return t or 0
end

local function playerId(player)
    local id = 0
    pcall(function() id = player:getPlayerNum() or 0 end)
    return id
end

local function zombieKey(z)
    local parts = {}
    pcall(function()
        if type(z.getOnlineID) == "function" then
            local id = z:getOnlineID()
            if id ~= nil and id ~= -1 then parts[#parts + 1] = "oid:" .. tostring(id) end
        end
    end)
    pcall(function()
        if type(z.getRemoteID) == "function" then
            local id = z:getRemoteID()
            if id ~= nil and id ~= -1 then parts[#parts + 1] = "rid:" .. tostring(id) end
        end
    end)
    pcall(function()
        local x = math.floor((z:getX() or 0) * 10)
        local y = math.floor((z:getY() or 0) * 10)
        local o = ""
        if type(z.getOutfitName) == "function" then o = tostring(z:getOutfitName() or "") end
        parts[#parts + 1] = string.format("xy:%d:%d:%s", x, y, o)
    end)
    if #parts == 0 then return "ptr:" .. tostring(z) end
    return table.concat(parts, "|")
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

local function tryBool(obj, method)
    local v = nil
    pcall(function()
        if obj and type(obj[method]) == "function" then
            v = obj[method](obj) and true or false
        end
    end)
    return v
end

local function tryStr(obj, method)
    local v = nil
    pcall(function()
        if obj and type(obj[method]) == "function" then
            v = tostring(obj[method](obj))
        end
    end)
    return v
end

local function dist2(player, z)
    local d = nil
    pcall(function()
        local px, py = player:getX(), player:getY()
        local zx, zy = z:getX(), z:getY()
        if px and py and zx and zy then
            local dx, dy = px - zx, py - zy
            d = math.sqrt(dx * dx + dy * dy)
        end
    end)
    return d
end

local function knoxModData(z)
    local md = nil
    pcall(function()
        if type(z.getModData) == "function" then md = z:getModData() end
    end)
    return md
end

--- Draft designed mults from World Rank (for compare when live scaling not applied).
local function designedFromWorldRank(rank)
    rank = tonumber(rank) or 0
    -- Soft draft only — not product-locked combat numbers; for TrackLog delta later
    local healthMult = 1 + rank * 0.04
    local dmgMult = 1 + rank * 0.03
    local speedMult = 1 + rank * 0.02
    return healthMult, dmgMult, speedMult
end

function KnoxSystem.ZombieObserve.snapshot(zombie, player, reason)
    if not zombie then return nil end
    reason = tostring(reason or "see")

    local health = tryNum(zombie, "getHealth")
    local maxHealth = tryNum(zombie, "getMaxHealth")
    if maxHealth == nil then maxHealth = tryNum(zombie, "getMaxHp") end
    local speedMod = tryNum(zombie, "getSpeedMod")
    if speedMod == nil then speedMod = tryNum(zombie, "getPathSpeed") end
    local walkType = tryStr(zombie, "getWalkType")
    local outfit = tryStr(zombie, "getOutfitName")
    local crawler = tryBool(zombie, "isCrawling")
    if crawler == nil then crawler = tryBool(zombie, "isCrawler") end
    local fakeDead = tryBool(zombie, "isFakeDead")
    local useless = tryBool(zombie, "isUseless")
    local virtual = tryBool(zombie, "isVirtual") 

    local md = knoxModData(zombie)
    local tier = nil
    local elite = nil
    local knoxStamped = 0
    local tierName, tags = "", ""
    local hpMult, dmgMult, speedMult, sightMult, hearMult = -1, -1, -1, -1, -1
    local sprinter, gearBag, gearWeapon, gearCraft, gearCount = 0, "", "", "", 0
    local inten, stampPL, stampDays = -1, -1, -1
    if md then
        tier = md.knoxTier or md.knox_system_tier or md.systemTier or md.tier
        elite = md.knoxElite or md.elite
        tierName = tostring(md.knoxTierName or "")
        tags = tostring(md.knoxTags or "")
        hpMult = tonumber(md.knoxHpMult) or -1
        dmgMult = tonumber(md.knoxDmgMult) or -1
        speedMult = tonumber(md.knoxSpeedMult) or -1
        sightMult = tonumber(md.knoxSightMult) or -1
        hearMult = tonumber(md.knoxHearMult) or -1
        sprinter = md.knoxSprinter and 1 or 0
        gearBag = tostring(md.knoxGearBag or "")
        gearWeapon = tostring(md.knoxGearWeapon or "")
        gearCraft = tostring(md.knoxGearCraft or "")
        gearCount = tonumber(md.knoxGearCount) or 0
        inten = tonumber(md.knoxIntensity) or -1
        stampPL = tonumber(md.knoxPL) or -1
        stampDays = tonumber(md.knoxDays) or -1
        if md.knoxWorldScaled or tier ~= nil or elite ~= nil or md.knoxSystem == true then
            knoxStamped = 1
        end
    end

    local rank, pl, days, pb, db = 0, 0, 0, 0, 0
    if player and KnoxSystem.WorldRank and KnoxSystem.WorldRank.compute then
        rank, pl, days, pb, db = KnoxSystem.WorldRank.compute(player)
    end
    local dHealth, dDmg, dSpeed = designedFromWorldRank(rank)

    local d = dist2(player, zombie)

    return {
        reason = reason,
        zKey = zombieKey(zombie),
        health = health ~= nil and health or -1,
        maxHealth = maxHealth ~= nil and maxHealth or -1,
        speedMod = speedMod ~= nil and speedMod or -1,
        walkType = walkType or "",
        outfit = outfit or "",
        crawler = crawler and 1 or 0,
        fakeDead = fakeDead and 1 or 0,
        dist = d ~= nil and d or -1,
        -- World Rank context (observer)
        worldRank = rank,
        personalLevel = pl,
        worldDays = days,
        plBand = pb,
        dayBand = db,
        -- Knox stamp
        knoxTier = tier ~= nil and tonumber(tier) or -1,
        knoxTierName = tierName,
        knoxElite = (elite and 1) or 0,
        knoxTags = tags,
        knoxStamped = knoxStamped,
        liveTierApplied = knoxStamped,
        hpMult = hpMult,
        dmgMult = dmgMult,
        speedMult = speedMult,
        sightMult = sightMult,
        hearMult = hearMult,
        madeSprinter = sprinter,
        gearBag = gearBag,
        gearWeapon = gearWeapon,
        gearCraft = gearCraft,
        gearCount = gearCount,
        stampIntensity = inten,
        stampPL = stampPL,
        stampDays = stampDays,
        -- Designed comparison (coarse rank-based; stamp uses tier tables)
        designedHealthMult = dHealth,
        designedDmgMult = dDmg,
        designedSpeedMult = dSpeed,
        note = knoxStamped == 1 and "knox_scaled" or "pending_stamp_or_disabled",
    }
end

function KnoxSystem.ZombieObserve.log(zombie, player, reason, extra)
    if not zombie or not KnoxSystem.Track then return end
    if not KnoxSystem.Track.isChannelOn("zombie") then return end
    local snap = KnoxSystem.ZombieObserve.snapshot(zombie, player, reason)
    if not snap then return end
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            snap[k] = v
        end
    end
    KnoxSystem.Track.log("zombie", "observe", snap)
end

--- First-see log (once per zombie key per session).
function KnoxSystem.ZombieObserve.onSee(zombie, player, reason)
    if not zombie or not player then return end
    -- Ensure world stamp before first observe (if update hook missed)
    pcall(function()
        if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.stamp then
            KnoxSystem.WorldZombies.stamp(zombie, "observe")
        end
    end)
    local key = zombieKey(zombie)
    if seen[key] and reason ~= "hit" and reason ~= "force" then
        return
    end
    if reason ~= "hit" then
        seen[key] = true
    elseif not seen[key] then
        seen[key] = true
    end
    KnoxSystem.ZombieObserve.log(zombie, player, reason or "see")
end

local function foreachNearbyZombie(player, range, fn)
    pcall(function()
        local cell = nil
        if type(player.getCell) == "function" then cell = player:getCell() end
        if not cell and getCell then cell = getCell() end
        if not cell then return end

        local list = nil
        pcall(function()
            if type(cell.getZombieList) == "function" then list = cell:getZombieList() end
        end)
        if list then
            local n = 0
            pcall(function() n = list:size() end)
            for i = 0, (n or 0) - 1 do
                local z = nil
                pcall(function() z = list:get(i) end)
                if z then
                    local d = dist2(player, z)
                    if d == nil or d <= range then
                        fn(z, d)
                    end
                end
            end
            return
        end

        -- Fallback: square ring
        local px, py, pz = 0, 0, 0
        pcall(function()
            px = math.floor(player:getX() or 0)
            py = math.floor(player:getY() or 0)
            pz = math.floor(player:getZ() or 0)
        end)
        local r = math.floor(range)
        for dx = -r, r do
            for dy = -r, r do
                local sq = nil
                pcall(function() sq = cell:getGridSquare(px + dx, py + dy, pz) end)
                if sq and type(sq.getMovingObjects) == "function" then
                    local mov = nil
                    pcall(function() mov = sq:getMovingObjects() end)
                    if mov then
                        local mn = 0
                        pcall(function() mn = mov:size() end)
                        for i = 0, (mn or 0) - 1 do
                            local o = nil
                            pcall(function() o = mov:get(i) end)
                            if o and instanceof(o, "IsoZombie") then
                                fn(o, dist2(player, o))
                            end
                        end
                    end
                end
            end
        end
    end)
end

function KnoxSystem.ZombieObserve.resetSession()
    seen = {}
    lastScan = {}
end

function KnoxSystem.ZombieObserve.onPlayerUpdate(player)
    if not player then return end
    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn("zombie") then return end

    local id = playerId(player)
    local t = nowMs()
    local last = lastScan[id] or 0
    if t > 0 and last > 0 and (t - last) < SCAN_INTERVAL_MS then return end
    lastScan[id] = t

    local logged = 0
    foreachNearbyZombie(player, SEE_RANGE, function(z, d)
        if logged >= 12 then return end -- cap per scan
        local key = zombieKey(z)
        if not seen[key] then
            KnoxSystem.ZombieObserve.onSee(z, player, "see")
            logged = logged + 1
        end
    end)
end

--- Called from melee hit path with damage context.
function KnoxSystem.ZombieObserve.onMeleeHit(player, zombie, damage)
    if not player or not zombie then return end
    pcall(function()
        if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.stamp then
            KnoxSystem.WorldZombies.stamp(zombie, "hit")
        end
    end)
    local key = zombieKey(zombie)
    local first = not seen[key]
    seen[key] = true
    KnoxSystem.ZombieObserve.log(zombie, player, first and "hit_first" or "hit", {
        hitRawDmg = tonumber(damage) or 0,
    })
end

print("[KnoxSystem] KS_ZombieObserve loaded (TrackLog channel: zombie)")
