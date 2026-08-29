-- KnoxSystem Goblin (Tier 0): flee AI, LOS despawn, death loot table
-- Design: design/zombie_mutations.yaml goblin + docs/adr/0034-goblin-tier-zero.md
--
-- User script review (lessons applied):
--   - Flag is md.knoxGoblin (stamp), not isLootGoblin
--   - Despawn = 15s LOS break (design), not 30s
--   - Do not rely on getGameTime():getModData().tickCount (often missing)
--   - Throttle via getTimestampMs; accumulate unseen with real dt
--   - pcall all Java APIs (CanSee, pathToLocationF, removeFromWorld, IsoUtils)
--   - Flee + clear target; neighborhood speed is separate (stamp + re-eval)
--   - Death: 2 equal-weight rolls from fixed table (not elite gear)

require "KnoxSystem/KS_ModData"

KnoxSystem = KnoxSystem or {}
KnoxSystem.Goblin = KnoxSystem.Goblin or {}

local G = KnoxSystem.Goblin

-- design/zombie_mutations.yaml death_loot (B42 ids verified via KS_ItemRarityData)
G.LOS_DESPAWN_SECONDS = 15
G.FLEE_TRIGGER_DIST = 20
G.FLEE_TARGET_DIST = 15
G.NEIGHBOR_RADIUS = 12
G.SPRINTER_OTHERS_LT = 5
G.UPDATE_MS = 400
G.NEIGHBOR_REEVAL_MS = 2500

--- Equal-weight death table: two independent rolls.
G.LOOT_TABLE = {
    { fullType = "Base.Bag_ALICEpack_Army", label = "Military Bag" },
    { fullType = "Base.Sledgehammer", label = "Sledgehammer" },
    { fullType = "Base.Bag_BigHikingBag", label = "Big Hiking Bag" },
    {
        fullType = "Base.AssaultRifle",
        label = "M16 + mag + scope",
        extras = { "Base.556Clip", "Base.x2Scope" }, -- best-effort attachments/ammo
    },
    { fullType = "Base.Hat_PartyHat_TINT", label = "Party Hat" },
    { fullType = "Base.SpiffoSuit", label = "Spiffo / bunny-style costume" },
    { fullType = "Base.Katana", label = "Katana" },
}

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() or 0 end
    end)
    if t == 0 then
        pcall(function()
            local gt = getGameTime and getGameTime()
            if gt and gt.getWorldAgeHours then
                t = math.floor((gt:getWorldAgeHours() or 0) * 3600 * 1000)
            end
        end)
    end
    return t
end

local function track(kind, fields)
    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn then return end
    if not KnoxSystem.Track.isChannelOn("zombie") and not KnoxSystem.Track.isChannelOn("loot") then
        -- still allow damage-channel free log via print throttle only
    end
    pcall(function()
        local ch = "zombie"
        if KnoxSystem.Track.isChannelOn("loot") and kind:find("loot", 1, true) then ch = "loot" end
        if KnoxSystem.Track.isChannelOn(ch) then
            KnoxSystem.Track.log(ch, kind, fields)
        end
    end)
end

function G.isGoblin(zombie)
    if not zombie then return false end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if not md then return false end
    if md.knoxGoblin == true or md.knoxGoblin == 1 then return true end
    local tags = string.lower(tostring(md.knoxTags or ""))
    return tags:find("goblin", 1, true) ~= nil
end

function G.countOtherZombies(zombie, radius)
    radius = tonumber(radius) or G.NEIGHBOR_RADIUS
    local n = 0
    pcall(function()
        local cell = zombie:getCell()
        if not cell or not cell.getZombieList then return end
        local list = cell:getZombieList()
        if not list then return end
        local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
        local r2 = radius * radius
        local size = list:size() or 0
        for i = 0, size - 1 do
            local z = list:get(i)
            if z and z ~= zombie then
                local ok = true
                pcall(function()
                    if z.isDead and z:isDead() then ok = false end
                end)
                if ok then
                    local x, y, zedZ = z:getX(), z:getY(), z:getZ()
                    if zedZ == zz then
                        local dx, dy = x - zx, y - zy
                        if dx * dx + dy * dy <= r2 then
                            n = n + 1
                        end
                    end
                end
            end
        end
    end)
    return n
end

--- Apply sprinter vs fast shambler from neighborhood (design).
function G.applyNeighborhoodSpeed(zombie, md, reason)
    if not zombie or not md then return false end
    local others = G.countOtherZombies(zombie, G.NEIGHBOR_RADIUS)
    local wantSprint = others < G.SPRINTER_OTHERS_LT
    md.knoxGoblinNeighbors = others
    md.knoxGoblinWantSprint = wantSprint and 1 or 0

    local crawler = false
    pcall(function()
        if zombie.isCrawling and zombie:isCrawling() then crawler = true end
        if zombie.isBecomeCrawler and zombie:isBecomeCrawler() then crawler = true end
    end)
    if crawler then
        md.knoxSprinter = false
        return false
    end

    -- Already matching?
    if wantSprint and md.knoxSprinter then return wantSprint end
    if (not wantSprint) and (not md.knoxSprinter) and md.knoxGoblinSpeedApplied then
        return wantSprint
    end

    pcall(function()
        if wantSprint then
            -- Prefer shared speed helper if WorldZombies exposes it later; direct set.
            if zombie.setCanWalk then zombie:setCanWalk(true) end
            if zombie.setWalkType then zombie:setWalkType("sprint1") end
            -- B42 common sprinter mark
            if zombie.setSpeedMod then zombie:setSpeedMod(1.2) end
            md.knoxSprinter = true
            md.knoxSpeedMult = 1.2
        else
            -- Fast shambler: not full sprint
            if zombie.setWalkType then zombie:setWalkType("1") end -- fast-ish
            if zombie.setSpeedMod then zombie:setSpeedMod(1.05) end
            md.knoxSprinter = false
            md.knoxSpeedMult = 1.05
        end
        md.knoxGoblinSpeedApplied = true
        md.knoxGoblinSpeedReason = tostring(reason or "eval")
    end)
    return wantSprint
end

local function getLocalPlayer()
    local p = nil
    pcall(function()
        if getPlayer then p = getPlayer() end
    end)
    if p then return p end
    pcall(function()
        if getSpecificPlayer then p = getSpecificPlayer(0) end
    end)
    return p
end

local function distSq(a, b)
    local d = nil
    pcall(function()
        if IsoUtils and IsoUtils.DistanceToSquared then
            d = IsoUtils.DistanceToSquared(a:getX(), a:getY(), b:getX(), b:getY())
        end
    end)
    if d then return d end
    local dx = a:getX() - b:getX()
    local dy = a:getY() - b:getY()
    return dx * dx + dy * dy
end

local function playerCanSee(player, zombie)
    local see = false
    pcall(function()
        if player.CanSee then see = player:CanSee(zombie) and true or false end
    end)
    if see then return true end
    -- Fallback: LOS via square / isSightBlocked if available
    pcall(function()
        if player.canSee and player:canSee(zombie) then see = true end
    end)
    return see
end

local function fleeFrom(zombie, player)
    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
    local px, py = player:getX(), player:getY()
    local dx, dy = zx - px, zy - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then
        dx, dy, len = 1, 0, 1
    end
    dx, dy = dx / len, dy / len
    local fleeX = zx + dx * G.FLEE_TARGET_DIST
    local fleeY = zy + dy * G.FLEE_TARGET_DIST
    pcall(function()
        if zombie.pathToLocationF then
            zombie:pathToLocationF(fleeX, fleeY, zz)
        elseif zombie.pathToLocation then
            zombie:pathToLocation(math.floor(fleeX), math.floor(fleeY), zz)
        end
    end)
    pcall(function()
        if zombie.setTarget then zombie:setTarget(nil) end
    end)
    pcall(function()
        if zombie.setUseless then zombie:setUseless(true) end -- don't fight while fleeing if API exists
    end)
end

local function despawn(zombie, md, reason)
    md.knoxGoblinDespawned = true
    track("goblin_despawn", {
        reason = tostring(reason or "los"),
        unseen = tonumber(md.knoxGoblinUnseenSec) or 0,
        note = "Goblin removed without corpse after LOS timeout",
    })
    pcall(function()
        if zombie.removeFromWorld then zombie:removeFromWorld() end
    end)
    pcall(function()
        if zombie.removeFromSquare then zombie:removeFromSquare() end
    end)
end

--- Throttled OnZombieUpdate body for Goblins only.
function G.onZombieUpdate(zombie)
    if not zombie or not G.isGoblin(zombie) then return end
    local md = nil
    pcall(function() md = zombie:getModData() end)
    if not md or md.knoxGoblinDespawned then return end

    local t = nowMs()
    local last = tonumber(md.knoxGoblinLastMs) or 0
    if last > 0 and (t - last) < G.UPDATE_MS then return end
    local dt = 0.4
    if last > 0 and t > last then
        dt = math.min(2.0, (t - last) / 1000.0)
    end
    md.knoxGoblinLastMs = t

    -- Dead → loot path handles drops; skip AI
    local dead = false
    pcall(function()
        if zombie.isDead and zombie:isDead() then dead = true end
        if zombie.isAlive and not zombie:isAlive() then dead = true end
    end)
    if dead then return end

    -- Neighborhood speed re-eval (not every tick)
    local lastN = tonumber(md.knoxGoblinLastNeighborMs) or 0
    if lastN == 0 or (t - lastN) >= G.NEIGHBOR_REEVAL_MS then
        md.knoxGoblinLastNeighborMs = t
        G.applyNeighborhoodSpeed(zombie, md, "update")
    end

    local player = getLocalPlayer()
    if not player then return end
    local pDead = false
    pcall(function()
        if player.isDead and player:isDead() then pDead = true end
    end)
    if pDead then return end

    -- LOS despawn (15s): ONLY after the goblin STARTS RUNNING (flee engage).
    -- Seeing it alone must NOT arm the timer — player can plan/approach freely.
    -- Engage = first time it enters flee range and path-flees.
    local d2 = distSq(zombie, player)
    local trigger2 = G.FLEE_TRIGGER_DIST * G.FLEE_TRIGGER_DIST
    local inFleeRange = d2 < trigger2

    -- Flee first so "starts running" is the engage signal
    if inFleeRange then
        fleeFrom(zombie, player)
        md.knoxGoblinFleeing = true
        md.knoxGoblinEngaged = true -- armed: may despawn after LOS break
    else
        md.knoxGoblinFleeing = false
    end

    if md.knoxGoblinEngaged then
        if playerCanSee(player, zombie) then
            md.knoxGoblinUnseenSec = 0
        else
            md.knoxGoblinUnseenSec = (tonumber(md.knoxGoblinUnseenSec) or 0) + dt
            if md.knoxGoblinUnseenSec >= G.LOS_DESPAWN_SECONDS then
                despawn(zombie, md, "los_timeout_after_flee")
                return
            end
        end
    else
        md.knoxGoblinUnseenSec = 0
    end
end

local function spawnItem(sq, zombie, fullType)
    if not fullType or fullType == "" then return false end
    local ok = false
    pcall(function()
        if sq and sq.AddWorldInventoryItem then
            local it = sq:AddWorldInventoryItem(fullType, 0.5, 0.5, 0)
            if it then ok = true end
        end
    end)
    if not ok then
        pcall(function()
            local inv = zombie and zombie.getInventory and zombie:getInventory()
            if inv and inv.AddItem then
                inv:AddItem(fullType)
                ok = true
            end
        end)
    end
    return ok
end

local function getSquare(zombie)
    local sq = nil
    pcall(function()
        if zombie.getCurrentSquare then sq = zombie:getCurrentSquare() end
        if not sq and zombie.getSquare then sq = zombie:getSquare() end
        if not sq and getCell then
            local cell = getCell()
            if cell and cell.getGridSquare then
                sq = cell:getGridSquare(
                    math.floor(zombie:getX()),
                    math.floor(zombie:getY()),
                    math.floor(zombie:getZ())
                )
            end
        end
    end)
    return sq
end

local function pickLootEntry()
    local n = #G.LOOT_TABLE
    if n < 1 then return nil end
    local i = 1
    pcall(function()
        if ZombRand then
            i = ZombRand(n) + 1 -- 0..n-1
        else
            i = math.random(1, n)
        end
    end)
    if i < 1 then i = 1 end
    if i > n then i = n end
    return G.LOOT_TABLE[i]
end

--- On death: always 2 equal-weight rolls.
function G.onDeath(zombie, reason)
    if not zombie or not G.isGoblin(zombie) then return false end
    local md = nil
    pcall(function() md = zombie:getModData() end)
    if not md then return false end
    if md.knoxGoblinLootDropped or md.knoxLootDropped then return false end

    local sq = getSquare(zombie)
    local dropped, failed = {}, {}
    for _ = 1, 2 do
        local entry = pickLootEntry()
        if entry then
            if spawnItem(sq, zombie, entry.fullType) then
                dropped[#dropped + 1] = entry.fullType
                if type(entry.extras) == "table" then
                    for _, ex in ipairs(entry.extras) do
                        if spawnItem(sq, zombie, ex) then
                            dropped[#dropped + 1] = ex
                        end
                    end
                end
            else
                failed[#failed + 1] = entry.fullType
            end
        end
    end

    md.knoxGoblinLootDropped = true
    md.knoxLootDropped = true -- block elite path double-dip if misflagged

    track("goblin_death_loot", {
        reason = tostring(reason or "death"),
        dropped = table.concat(dropped, ","),
        failed = table.concat(failed, ","),
        count = #dropped,
        note = "2 equal-weight rolls from Goblin fixed table",
    })
    return #dropped > 0
end

--- Called from stamp after Goblin exclusive path.
function G.onStamp(zombie, md)
    if not zombie or not md then return end
    md.knoxGoblin = true
    md.knoxGoblinUnseenSec = 0
    md.knoxGoblinLootDropped = false
    G.applyNeighborhoodSpeed(zombie, md, "stamp")
end

print("[KnoxSystem] KS_Goblin loaded (flee AI + 15s LOS despawn + death loot x2)")
