-- Analyze system skill
-- L1: HP + elite + loot colors | L2: damage + mods
-- Screen-space stacked plates (zombie ChatElement is 1-line; setMaxChatLines not in Lua)
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_SystemSkills"

KnoxSystem.Analyze = KnoxSystem.Analyze or {}
KnoxSystem.Analyze.PLATE_REV = 21

KnoxSystem.Analyze.MOD_LABELS = {
    tough_skin = "Thick Skin",
    thick_skin = "Thick Skin",
    heavy_hit = "Heavy Hit",
    Heavy_Hit = "Heavy Hit",
    relentless = "Relentless",
    system_hardened = "Sys.Hardened",
    sprinter = "Sprinter",
    runner = "Runner",
}

local RARITY_COLOR = {
    trash     = { r = 0.45, g = 0.45, b = 0.45 },
    common    = { r = 0.92, g = 0.92, b = 0.92 },
    uncommon  = { r = 0.20, g = 0.80, b = 0.30 },
    rare      = { r = 0.25, g = 0.45, b = 1.00 },
    epic      = { r = 0.65, g = 0.25, b = 0.90 },
    legendary = { r = 1.00, g = 0.55, b = 0.10 },
}

local MAX_DIST = 14.0
-- Only treat as "engine faded" when alpha is in (0, MIN) — NOT when alpha is 0
-- (many zombies report getAlpha=0 while fully drawn → was hiding almost all plates)
local MIN_ALPHA = 0.15
local DMG_LIFE_MS = 1500          -- damage float lifetime (also post-death hold)
local DMG_DEATH_HOLD_MS = 1500    -- keep dmg plate this long after zombie leaves list / dies
local DMG_DISPLAY_SCALE = 100     -- engine HP float → display (0.3 → 30, 2.0 → 200)
-- Plate colors (bright)
local DMG_COL_UNDER = { r = 0.25, g = 0.75, b = 1.00 } -- bright blue — below weapon base (moodles/debuffs)
local DMG_COL_BASE  = { r = 0.25, g = 1.00, b = 0.35 } -- bright green — normal band
local DMG_COL_CRIT  = { r = 1.00, g = 0.20, b = 0.18 } -- bright red — crit
local LINE_H = 14
local HEAD_OFF_PX = 158
local POS_SAMPLE_MS = 250
local POS_LERP = 0.35

local plates = {}
local nextPlateId = 1

local function zKey(z)
    -- STABLE key for zombie lifetime. NEVER use world XY (moves every tile → ghost double plates).
    if not z then return "nil" end
    local id = nil
    pcall(function()
        local md = z:getModData()
        if md then
            if md.knoxPlateId then
                id = md.knoxPlateId
            else
                id = nextPlateId
                nextPlateId = nextPlateId + 1
                md.knoxPlateId = id
            end
        end
    end)
    if id ~= nil then return "p:" .. tostring(id) end
    pcall(function()
        if type(z.getOnlineID) == "function" then
            local oid = z:getOnlineID()
            if oid ~= nil and oid ~= -1 then id = "o:" .. tostring(oid) end
        end
    end)
    if id ~= nil then return tostring(id) end
    return tostring(z)
end

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return tonumber(t) or 0
end

local function num(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

local function analyzeLevel(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 0 end
    return KnoxSystem.SystemSkills.analyzeLevel(data)
end

function KnoxSystem.Analyze.level(player)
    return analyzeLevel(player or getPlayer())
end

function KnoxSystem.Analyze.hasL1(player)
    return analyzeLevel(player or getPlayer()) >= 1
end

function KnoxSystem.Analyze.hasL2(player)
    return analyzeLevel(player or getPlayer()) >= 2
end

function KnoxSystem.Analyze.eliteChatRange()
    return 10.0
end

function KnoxSystem.Analyze.maxSeeDist()
    return MAX_DIST
end

local function playerIndex(player)
    local pn = 0
    pcall(function()
        if player and player.getPlayerNum then pn = player:getPlayerNum() or 0 end
    end)
    return num(pn, 0)
end

local function ifloor(n)
    return math.floor(num(n, 0))
end

-- zKey defined above (stable plate id)

local function losClear(player, z)
    local ok = false
    pcall(function()
        if type(player.CanSee) == "function" then
            ok = player:CanSee(z) and true or false
        end
    end)
    if ok then return true end
    pcall(function()
        local cell = nil
        if type(player.getCell) == "function" then cell = player:getCell() end
        if not cell and getCell then cell = getCell() end
        if not cell or not LosUtil or not LosUtil.lineClear then return end
        local result = LosUtil.lineClear(
            cell,
            ifloor(player:getX()), ifloor(player:getY()), ifloor(player:getZ() or 0),
            ifloor(z:getX()), ifloor(z:getY()), ifloor(z:getZ() or 0),
            false
        )
        local blocked = false
        if LosUtil.TestResults and LosUtil.TestResults.Blocked ~= nil then
            blocked = (result == LosUtil.TestResults.Blocked)
        else
            blocked = tostring(result or ""):find("Blocked") ~= nil
        end
        ok = (not blocked) and (result ~= nil)
    end)
    return ok
end

-- Player look/facing cone. CanSee is geometric LOS only — turning around still
-- has LOS, which is why plates stuck after vision-cone fade (Issue face-away).
-- halfRad ~ 1.4 (~80°) each side ≈ 160° FOV; fully turned away = hide.
local LOOK_HALF_RAD = 1.40

local function inLookCone(player, z)
    local px, py = num(player:getX(), 0), num(player:getY(), 0)
    local zx, zy = num(z:getX(), 0), num(z:getY(), 0)
    local dx, dy = zx - px, zy - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.35 then return true end -- on top of player
    dx, dy = dx / len, dy / len

    local fx, fy = 0, 1
    local got = false
    pcall(function()
        if type(player.getForwardDirectionX) == "function" then
            fx = num(player:getForwardDirectionX(), 0)
            fy = num(player:getForwardDirectionY(), 1)
            got = true
        end
    end)
    if not got then
        pcall(function()
            if type(player.getLookAngleRadians) == "function" then
                local a = num(player:getLookAngleRadians(), 0)
                fx = math.cos(a)
                fy = math.sin(a)
                got = true
            elseif type(player.getDirectionAngleRadians) == "function" then
                local a = num(player:getDirectionAngleRadians(), 0)
                fx = math.cos(a)
                fy = math.sin(a)
                got = true
            end
        end)
    end
    if not got then return true end -- can't know facing; don't over-hide

    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 0.01 then return true end
    fx, fy = fx / fl, fy / fl

    local dot = fx * dx + fy * dy
    return dot >= math.cos(LOOK_HALF_RAD)
end

--- Visible enough to plate.
--- Hit flash only: canSee was failing every tick (targetAlpha often 0 = unknown,
--- treated as faded) so plates cleared instantly except onDamage force-show.
function KnoxSystem.Analyze.canSeeTarget(player, z)
    if not player or not z then return false, 0 end

    local dist = 999
    pcall(function()
        local dx = num(player:getX(), 0) - num(z:getX(), 0)
        local dy = num(player:getY(), 0) - num(z:getY(), 0)
        dist = math.sqrt(dx * dx + dy * dy)
    end)
    if dist > MAX_DIST then return false, 0 end

    local dead = false
    pcall(function()
        if type(z.isDead) == "function" and z:isDead() then dead = true end
    end)
    if dead then return false, 0 end

    if not inLookCone(player, z) then
        return false, 0
    end

    local pn = playerIndex(player)
    local alpha, tAlpha = nil, nil
    pcall(function()
        if type(z.getAlpha) == "function" then
            local a = z:getAlpha(pn)
            if a == nil then a = z:getAlpha() end
            if a ~= nil then alpha = num(a, nil) end
        end
    end)
    pcall(function()
        if type(z.getTargetAlpha) == "function" then
            local a = z:getTargetAlpha(pn)
            if a == nil then a = z:getTargetAlpha() end
            if a ~= nil then tAlpha = num(a, nil) end
        end
    end)

    local vis = math.max(alpha or 0, tAlpha or 0)

    -- Only treat as engine-faded when alpha is PARTIAL (0 < a < MIN).
    -- Alpha == 0 is unknown on many zombies and must not hide plates.
    local function isPartialFade(a)
        return a ~= nil and a > 0.001 and a < MIN_ALPHA
    end
    if isPartialFade(tAlpha) or isPartialFade(alpha) then
        return false, vis
    end

    local hasLos = losClear(player, z)
    if hasLos then
        if vis >= MIN_ALPHA then return true, vis end
        return true, 1.0 -- LOS + facing, alpha unknown
    end

    -- No LOS: foliage only if clearly drawn
    if vis >= 0.55 then
        return true, vis
    end

    return false, 0
end

-- ---------------------------------------------------------------------------
-- Loot rarity
-- ---------------------------------------------------------------------------
function KnoxSystem.Analyze.itemRarity(item)
    if item == nil or item == false then return "common" end
    if type(item) ~= "userdata" and type(item) ~= "table" then return "common" end

    -- Prefer InventoryTheme (Item Rarity UI data)
    if KnoxSystem.UI and KnoxSystem.UI.itemRarityLabel then
        local ok, label = pcall(function() return KnoxSystem.UI.itemRarityLabel(item) end)
        if ok and type(label) == "string" and label ~= "" then
            return label
        end
    end

    local junk = false
    pcall(function()
        if type(item.hasTag) == "function" and ItemTag and ItemTag.Junk then
            junk = item:hasTag(ItemTag.Junk)
        end
    end)
    if junk then return "trash" end

    local cat = ""
    pcall(function()
        if type(item.getDisplayCategory) == "function" then
            cat = tostring(item:getDisplayCategory() or ""):lower()
        end
    end)
    if cat == "junk" or cat == "memento" or cat:find("junk") or cat:find("memento") then
        return "trash"
    end
    return "common"
end

function KnoxSystem.Analyze.rarityColor(rarity)
    return RARITY_COLOR[rarity] or RARITY_COLOR.common
end

function KnoxSystem.Analyze.hpBarText(frac)
    frac = num(frac, 1)
    local segs = 10
    local filled = math.floor(frac * segs + 0.5)
    if filled < 0 then filled = 0 end
    if filled > segs then filled = segs end
    local s = "HP ["
    for i = 1, segs do
        s = s .. (i <= filled and "|" or ".")
    end
    s = s .. string.format("] %d%%", math.floor(frac * 100 + 0.5))
    return s
end

local function hpFrac(z)
    local h, peak = nil, nil
    pcall(function() h = z:getHealth() end)
    pcall(function()
        local md = z:getModData()
        if md then peak = num(md.knoxHealthPeak, nil) end
    end)
    h = num(h, nil)
    if not h or h < 0 then return 1 end
    if not peak or peak < h then peak = math.max(h, 1.2) end
    pcall(function()
        local md = z:getModData()
        if md then md.knoxHealthPeak = math.max(num(md.knoxHealthPeak, 0), peak) end
    end)
    return math.max(0, math.min(1, h / peak))
end

local function collectModIds(z)
    local seen, ordered = {}, {}
    local function add(id)
        if not id or id == "" or id == "elite_core" then return end
        id = tostring(id):gsub("^%s+", ""):gsub("%s+$", "")
        local key = id:lower()
        if seen[key] then return end
        seen[key] = true
        ordered[#ordered + 1] = id
    end
    local wt = ""
    pcall(function() wt = tostring(z:getWalkType() or "") end)
    local low = wt:lower()
    if low:find("sprint") then add("sprinter")
    elseif low:find("fast") then add("runner")
    else
        local n = tonumber(wt)
        if n and n >= 4 then add("runner") end
    end
    local md = nil
    pcall(function() md = z:getModData() end)
    if md then
        for piece in string.gmatch(tostring(md.knoxTags or ""), "[^,]+") do add(piece) end
        if type(md.knoxEliteMods) == "table" then
            for _, id in ipairs(md.knoxEliteMods) do add(tostring(id)) end
        elseif type(md.knoxEliteMods) == "string" then
            for piece in string.gmatch(md.knoxEliteMods, "[^,]+") do add(piece) end
        end
        if md.knoxSprinter == true or md.knoxSprinter == 1 then add("sprinter") end
    end
    return ordered
end

function KnoxSystem.Analyze.formatModsLine(z)
    local ids = collectModIds(z)
    if #ids == 0 then return nil end
    local labels = {}
    for _, id in ipairs(ids) do
        local lab = KnoxSystem.Analyze.MOD_LABELS[id] or KnoxSystem.Analyze.MOD_LABELS[id:lower()]
        if not lab then
            lab = id:gsub("_", " ")
            lab = lab:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b:lower() end)
        end
        labels[#labels + 1] = lab
    end
    return table.concat(labels, " - ")
end

local function eliteLabel(z)
    local md = nil
    pcall(function() md = z:getModData() end)
    if not md or not md.knoxElite then return nil end
    local tier = num(md.knoxTier, 0)
    local name = tostring(md.knoxTierName or "")
    if name == "" then name = "Elite" end
    return string.format("* ELITE T%s %s *", tostring(tier), name)
end

local function upsertPlate(z, vis, dmgText)
    local key = zKey(z)
    local p = plates[key]
    if not p then
        p = {}
        plates[key] = p
    end
    p.z = z
    p.zx = num(nil, 0)
    p.zy = 0
    p.zz = 0
    pcall(function()
        p.zx = num(z:getX(), 0)
        p.zy = num(z:getY(), 0)
        p.zz = num(z:getZ(), 0)
    end)
    p.alpha = num(vis, 1)
    p.seen = nowMs()
    p.mods = KnoxSystem.Analyze.formatModsLine(z)
    local frac = hpFrac(z)
    p.hp = KnoxSystem.Analyze.hpBarText(frac)
    p.hpFrac = frac
    p.elite = eliteLabel(z)
    if dmgText then
        p.dmg = dmgText
        p.dmgBorn = nowMs()
    end
end

--- Classify engine event damage vs weapon base for plate color.
--- Returns "under" | "base" | "crit", plus rgb.
function KnoxSystem.Analyze.classifyHitTier(eventDamage, weapon, target, meta)
    local e = num(eventDamage, 0)
    local tier = "base"
    local col = DMG_COL_BASE

    local baseMin, baseMax, baseAvg = -1, -1, -1
    local critMult = 2.0
    pcall(function()
        if not weapon then return end
        if weapon.getMinDamage then baseMin = tonumber(weapon:getMinDamage()) or -1 end
        if weapon.getMaxDamage then baseMax = tonumber(weapon:getMaxDamage()) or -1 end
        if baseMin > 0 and baseMax > 0 then baseAvg = (baseMin + baseMax) * 0.5 end
        if weapon.getCritDmgMultiplier then
            critMult = tonumber(weapon:getCritDmgMultiplier()) or critMult
        elseif weapon.getCriticalDamageMultiplier then
            critMult = tonumber(weapon:getCriticalDamageMultiplier()) or critMult
        end
        if critMult < 1.2 then critMult = 2.0 end
    end)
    if meta then
        if num(meta.baseMin, -1) > 0 then baseMin = num(meta.baseMin, baseMin) end
        if num(meta.baseMax, -1) > 0 then baseMax = num(meta.baseMax, baseMax) end
        if num(meta.baseAvg, -1) > 0 then baseAvg = num(meta.baseAvg, baseAvg) end
        if num(meta.critDmgMult, -1) > 1 then critMult = num(meta.critDmgMult, critMult) end
    end
    if baseAvg <= 0 and baseMin > 0 and baseMax > 0 then
        baseAvg = (baseMin + baseMax) * 0.5
    end
    if baseAvg <= 0 and baseMax > 0 then baseAvg = baseMax end
    if baseMin <= 0 and baseMax > 0 then baseMin = baseMax * 0.5 end

    -- Ground / crawl: vanilla already multiplies eventDamage; scale thresholds up
    local ground = false
    pcall(function()
        if target then
            if target.isKnockedDown and target:isKnockedDown() then ground = true end
            if target.isCrawling and target:isCrawling() then ground = true end
            if target.isOnFloor and target:isOnFloor() then ground = true end
        end
    end)
    if meta and (meta.targetKnockedDown == 1 or meta.targetCrawling == 1) then
        ground = true
    end
    local gMul = ground and 2.2 or 1.0

    -- Explicit crit flags if the build exposes them
    local flaggedCrit = false
    pcall(function()
        if weapon and weapon.isCritical and weapon:isCritical() then flaggedCrit = true end
    end)
    pcall(function()
        if meta and meta.isCrit == 1 then flaggedCrit = true end
    end)

    if flaggedCrit then
        tier, col = "crit", DMG_COL_CRIT
    elseif baseMin > 0 and e > 0 and e < baseMin * 0.92 * gMul then
        -- Clearly under modified weapon floor (moodles / exhausted / bad angle)
        tier, col = "under", DMG_COL_UNDER
    elseif baseAvg > 0 and e > 0 then
        -- Crit band: near baseAvg * critMult * ground (skill can push "normal" above baseMax)
        local critFloor = baseAvg * critMult * gMul * 0.88
        -- Also treat very high vs baseMax as crit
        local critFloor2 = (baseMax > 0) and (baseMax * critMult * gMul * 0.80) or critFloor
        local critThresh = math.min(critFloor, critFloor2)
        if critFloor2 > critThresh then critThresh = critFloor end -- use avg-based primarily
        if e >= critFloor * 0.95 or e >= critFloor2 * 0.95 then
            tier, col = "crit", DMG_COL_CRIT
        elseif baseMin > 0 and e < baseMin * gMul * 0.98 then
            tier, col = "under", DMG_COL_UNDER
        else
            tier, col = "base", DMG_COL_BASE
        end
    elseif e > 0 then
        tier, col = "base", DMG_COL_BASE
    end

    return tier, col.r, col.g, col.b, {
        baseMin = baseMin,
        baseMax = baseMax,
        baseAvg = baseAvg,
        critMult = critMult,
        ground = ground and 1 or 0,
        gMul = gMul,
        flaggedCrit = flaggedCrit and 1 or 0,
    }
end

function KnoxSystem.Analyze.onDamageDealt(attacker, target, damage, meta)
    local player = attacker
    if not player or not KnoxSystem.Analyze.hasL2(player) then return end
    local ok, vis = KnoxSystem.Analyze.canSeeTarget(player, target)
    if not ok then
        ok, vis = true, 1
    end
    local dmg = num(damage, 0)
    if dmg <= 0 then return end
    local shown = math.floor(dmg * DMG_DISPLAY_SCALE + 0.5)
    if shown < 1 and dmg > 0 then shown = 1 end

    local eventDmg = dmg
    local weapon = nil
    if type(meta) == "table" then
        if num(meta.eventDamage, -1) >= 0 then eventDmg = num(meta.eventDamage, dmg) end
        weapon = meta.weapon
    end

    local tier, cr, cg, cb, cref = KnoxSystem.Analyze.classifyHitTier(eventDmg, weapon, target, meta)

    upsertPlate(target, vis, tostring(shown))
    local key = zKey(target)
    if plates[key] then
        plates[key].dmg = tostring(shown)
        plates[key].dmgBorn = nowMs()
        plates[key].dmgTier = tier or "base"
        plates[key].dmgR = cr or DMG_COL_BASE.r
        plates[key].dmgG = cg or DMG_COL_BASE.g
        plates[key].dmgB = cb or DMG_COL_BASE.b
    end

    if type(meta) == "table" then
        meta.dmgTier = tier
        if cref then
            meta.tierBaseMin = cref.baseMin
            meta.tierBaseMax = cref.baseMax
            meta.tierBaseAvg = cref.baseAvg
            meta.tierCritMult = cref.critMult
            meta.tierGround = cref.ground
            meta.tierFlaggedCrit = cref.flaggedCrit
        end
    end
end

function KnoxSystem.Analyze.onPlayerUpdate(player)
    if not player then return end
    -- Ensure ModData exists early so hasL1 works before first XP hit
    pcall(function() KnoxSystem.getPlayerData(player) end)
    if not KnoxSystem.Analyze.hasL1(player) then return end

    local l2 = KnoxSystem.Analyze.hasL2(player)
    local t = nowMs()

    local cell = nil
    pcall(function() cell = getCell() end)
    if not cell or not cell.getZombieList then return end
    local list = nil
    pcall(function() list = cell:getZombieList() end)
    if not list then return end
    local n = 0
    pcall(function() n = list:size() end)

    local seenNow = {}
    for i = 0, math.min(n, 120) - 1 do
        local z = nil
        pcall(function() z = list:get(i) end)
        if z then
            local ok, vis = KnoxSystem.Analyze.canSeeTarget(player, z)
            if ok then
                local key = zKey(z)
                seenNow[key] = true
                local prevDmg = plates[key] and plates[key].dmg or nil
                local prevBorn = plates[key] and plates[key].dmgBorn or nil
                upsertPlate(z, vis, nil)
                -- Clear corpse-hold once zombie is visible again
                if plates[key] then plates[key].goneAt = nil end
                if prevDmg and prevBorn and (t - prevBorn) <= DMG_LIFE_MS then
                    plates[key].dmg = prevDmg
                    plates[key].dmgBorn = prevBorn
                end
                if not l2 then
                    plates[key].mods = nil
                    plates[key].dmg = nil
                end
                -- If zombie just died but still in list, freeze death timer for dmg hold
                pcall(function()
                    if z.isDead and z:isDead() and plates[key] and plates[key].dmg then
                        if not plates[key].goneAt then plates[key].goneAt = t end
                    end
                end)
            end
        end
    end
    for key, p in pairs(plates) do
        if not p then
            plates[key] = nil
        elseif not seenNow[key] then
            -- Keep damage plate after death / despawn for DMG_DEATH_HOLD_MS
            local dmgAlive = p.dmg and p.dmgBorn and (t - p.dmgBorn) <= math.max(DMG_LIFE_MS, DMG_DEATH_HOLD_MS)
            if dmgAlive then
                if not p.goneAt then p.goneAt = t end
                -- Strip live chrome; leave last world pos + dmg float
                p.hp = nil
                p.mods = nil
                p.elite = nil
                p.z = nil -- freeze plateWorldPos on last zx/zy/zz
                if (t - p.goneAt) > DMG_DEATH_HOLD_MS then
                    plates[key] = nil
                end
            elseif p.seen and (t - p.seen) > 250 then
                plates[key] = nil
            end
        else
            if p.dmgBorn and (t - p.dmgBorn) > DMG_LIFE_MS then
                -- Still allow death-hold window if marked gone/dead
                if p.goneAt and (t - p.goneAt) <= DMG_DEATH_HOLD_MS then
                    -- keep dmg
                else
                    p.dmg = nil
                    p.dmgBorn = nil
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Projection: only Lua numbers. Never Core.tileScale (causes __mul errors).
-- ---------------------------------------------------------------------------
local function worldToScreen(x, y, z)
    x = num(x, nil)
    y = num(y, nil)
    z = num(z, 0)
    if x == nil or y == nil then return nil, nil end

    local pn = 0
    pcall(function()
        local player = getPlayer and getPlayer() or nil
        if player and player.getPlayerNum then pn = num(player:getPlayerNum(), 0) end
    end)

    local sx, sy = nil, nil
    pcall(function()
        if IsoUtils and IsoUtils.XToScreenExact then
            -- 4th arg = floor/screenZ, NOT player index
            sx = IsoUtils.XToScreenExact(x, y, z, 0)
            sy = IsoUtils.YToScreenExact(x, y, z, 0)
        end
    end)
    if sx == nil or sy == nil then
        pcall(function()
            if not IsoUtils then return end
            sx = IsoUtils.XToScreen(x, y, z, 0)
            sy = IsoUtils.YToScreen(x, y, z, 0)
            local ox, oy = 0, 0
            if IsoCamera then
                if IsoCamera.getOffX then ox = num(IsoCamera.getOffX(), 0) end
                if IsoCamera.getOffY then oy = num(IsoCamera.getOffY(), 0) end
            end
            sx = num(sx, 0) - ox
            sy = num(sy, 0) - oy
        end)
    end

    sx = num(sx, nil)
    sy = num(sy, nil)
    if sx == nil or sy == nil then return nil, nil end

    local zoom = 1
    pcall(function()
        local core = getCore and getCore() or nil
        if core and core.getZoom then
            zoom = num(core:getZoom(pn), 1)
        end
    end)
    if zoom < 0.05 then zoom = 1 end
    sx = sx / zoom
    sy = sy / zoom

    -- Head lift in *screen* pixels (do NOT divide by zoom again — that pinned text on torso)
    sy = sy - HEAD_OFF_PX

    return sx, sy
end

local function drawText(text, x, y, r, g, b, a)
    if not text then return end
    x = num(x, nil); y = num(y, nil)
    if x == nil or y == nil then return end
    a = num(a, 1)
    if a <= 0.02 then return end
    r = num(r, 1); g = num(g, 1); b = num(b, 1)
    pcall(function()
        local tm = getTextManager and getTextManager() or nil
        local font = UIFont and (UIFont.Small or UIFont.Medium) or nil
        if not tm or not font then return end
        if tm.DrawStringCentre then
            tm:DrawStringCentre(font, x, y, tostring(text), r, g, b, a)
        elseif tm.DrawString then
            tm:DrawString(font, x, y, tostring(text), r, g, b, a)
        end
    end)
end

local function plateWorldPos(p)
    local zx, zy, zz = num(p.zx, nil), num(p.zy, nil), num(p.zz, 0)
    local z = p.z
    if z then
        pcall(function()
            if type(z.isDead) == "function" and z:isDead() then return end
            zx = num(z:getX(), zx)
            zy = num(z:getY(), zy)
            zz = num(z:getZ(), zz)
        end)
    end
    return zx, zy, zz
end

function KnoxSystem.Analyze.drawPlates()
    local player = getPlayer and getPlayer() or nil
    if not player then return end
    if not KnoxSystem.Analyze.hasL1(player) then return end
    local l2 = KnoxSystem.Analyze.hasL2(player)
    local t = nowMs()

    for _, p in pairs(plates) do
        if p then
            local zx, zy, zz = plateWorldPos(p)
            if zx ~= nil and zy ~= nil then
                -- Re-sample screen anchor on a short interval (not every render tick)
                local lastSamp = num(p.posSampleAt, 0)
                if lastSamp == 0 or (t - lastSamp) >= POS_SAMPLE_MS then
                    local tsx, tsy = worldToScreen(zx, zy, zz or 0)
                    if tsx ~= nil and tsy ~= nil then
                        p.targetSx = tsx
                        p.targetSy = tsy
                        p.posSampleAt = t
                        if p.drawSx == nil then
                            p.drawSx = tsx
                            p.drawSy = tsy
                        end
                    end
                end

                local sx = num(p.drawSx, nil)
                local sy = num(p.drawSy, nil)
                local tx = num(p.targetSx, nil)
                local ty = num(p.targetSy, nil)
                if sx ~= nil and sy ~= nil and tx ~= nil and ty ~= nil then
                    -- Smooth follow toward last sample (single plate only)
                    local dx = tx - sx
                    local dy = ty - sy
                    local dist2 = dx * dx + dy * dy
                    -- Snap if very close or huge jump (teleport / first frames)
                    if dist2 < 4 or dist2 > 120 * 120 then
                        sx, sy = tx, ty
                    else
                        local k = POS_LERP
                        if k < 0 then k = 0 end
                        if k > 1 then k = 1 end
                        sx = sx + dx * k
                        sy = sy + dy * k
                    end
                    p.drawSx = sx
                    p.drawSy = sy
                elseif tx ~= nil and ty ~= nil then
                    sx, sy = tx, ty
                    p.drawSx, p.drawSy = sx, sy
                end

                if sx ~= nil and sy ~= nil then
                    local a = num(p.alpha, 1)
                    if a > 1 then a = 1 end
                    if a < 0.1 then a = 0.1 end

                    -- Near head → up: mods (lowest), HP, dmg, elite
                    local y = sy
                    if l2 and p.mods and p.mods ~= "" then
                        drawText(p.mods, sx, y, 0.75, 0.88, 1.0, a)
                        y = y - LINE_H
                    end
                    if p.hp then
                        local frac = num(p.hpFrac, 0.5)
                        -- Red (low) → bright yellow (mid) → green (full).
                        -- Old mid was muddy olive and washed out on grass/dirt.
                        local hr, hg, hb
                        if frac >= 0.5 then
                            local t = (frac - 0.5) * 2.0 -- 0..1 mid→full
                            hr = 1.0 - 0.75 * t
                            hg = 0.88 + 0.07 * t
                            hb = 0.05
                        else
                            local t = frac * 2.0 -- 0..1 low→mid
                            hr = 1.0
                            hg = 0.12 + 0.76 * t
                            hb = 0.04
                        end
                        drawText(p.hp, sx, y, hr, hg, hb, a)
                        y = y - LINE_H
                    end
                    if l2 and p.dmg and p.dmgBorn then
                        local age = t - p.dmgBorn
                        local holdOk = age <= DMG_LIFE_MS
                        if p.goneAt and (t - p.goneAt) <= DMG_DEATH_HOLD_MS then
                            holdOk = true
                        end
                        if holdOk then
                            local life = DMG_LIFE_MS
                            if p.goneAt then
                                life = math.max(life, DMG_DEATH_HOLD_MS)
                            end
                            local fade = 1 - (age / life)
                            if fade < 0.15 then fade = 0.15 end
                            if fade > 1 then fade = 1 end
                            local dr = num(p.dmgR, DMG_COL_BASE.r)
                            local dg = num(p.dmgG, DMG_COL_BASE.g)
                            local db = num(p.dmgB, DMG_COL_BASE.b)
                            drawText(p.dmg, sx, y, dr, dg, db, a * fade)
                            y = y - LINE_H
                        end
                    end
                    if p.elite then
                        drawText(p.elite, sx, y, 1.0, 0.82, 0.15, a)
                    end
                end
            end
        end
    end
end

local drawHooked = false
local drawHookEvent = nil
function KnoxSystem.Analyze.ensureOverlay()
    -- Re-bind if event lost after reload; prefer Post so plates draw above world
    if drawHooked and drawHookEvent then return end
    local function addDraw(evName)
        local ev = Events and Events[evName]
        if not ev or not ev.Add then return false end
        ev.Add(function()
            pcall(function() KnoxSystem.Analyze.drawPlates() end)
        end)
        drawHooked = true
        drawHookEvent = evName
        print("[KnoxSystem] Analyze plates on " .. evName)
        return true
    end
    if not addDraw("OnPostUIDraw") then
        if not addDraw("OnPreUIDraw") then
            print("[KnoxSystem] Analyze plates: NO UI draw event available")
        end
    end
end

function KnoxSystem.Analyze.render()
    KnoxSystem.Analyze.drawPlates()
end

-- ---------------------------------------------------------------------------
-- Loot colors: handled by KS_UI_InventoryTheme
-- ---------------------------------------------------------------------------
function KnoxSystem.Analyze.patchInventory()
    print("[KnoxSystem] Analyze PLATE_REV=" .. tostring(KnoxSystem.Analyze.PLATE_REV)
        .. " inventory colors → KS_UI_InventoryTheme")
end

function KnoxSystem.Analyze.onGameStart()
    plates = {}
    drawHooked = false
    drawHookEvent = nil
    print(string.format(
        "[KnoxSystem] Analyze PLATE_REV=%s plates + overlay rebind",
        tostring(KnoxSystem.Analyze.PLATE_REV)
    ))
    KnoxSystem.Analyze.patchInventory()
    KnoxSystem.Analyze.ensureOverlay()
    pcall(function()
        local p = getPlayer()
        if p then KnoxSystem.getPlayerData(p) end
    end)
end

print(string.format(
    "[KnoxSystem] KS_Analyze loaded PLATE_REV=%s (safe project + passive plates)",
    tostring(KnoxSystem.Analyze.PLATE_REV)
))
