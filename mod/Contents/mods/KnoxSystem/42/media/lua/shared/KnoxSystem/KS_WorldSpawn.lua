-- World Rank → spawn profile curves (D2).
-- Catalog of named mods stays in KS_Modifiers; this file owns WR scaling only.
-- Curve style A2: ease-in (slow early, steeper late) between WR1 and WR40 anchors.
-- H1: base HP mult from WR only (no old System Tier HP ladder).
-- S1: Knox does not add sprinters below WR5 (vanilla/sandbox still apply); Goblin may sprint earlier.
-- E2: elite full 6-mod spine only late (ease-in); early elites = 1–2 T1.
require "KnoxSystem/KS_ModData"

KnoxSystem.WorldSpawn = KnoxSystem.WorldSpawn or {}

local WR_MIN, WR_MAX = 1, 40

-- Anchors (locked)
local HP_WR1, HP_WR40 = 1.00, 2.50 -- 250% at WR40
local ELITE_CH_WR1, ELITE_CH_WR40 = 0.02, 0.05
local SPRINT_WR5, SPRINT_WR40 = 0.005, 0.05 -- 0.5% → 5%; gate WR>=5
local SPRINT_GATE = 5

-- Elite Rank packages (replace old System Tier elite bundle for elites)
-- display_zombie names for Analyze/EliteTell later
local ELITE_RANKS = {
    [1] = {
        id = 1, key = "apex", display = "Apex", display_zombie = "Apex Zombie",
        hp_mult = 1.25, dmg_mult = 1.10, speed_mult = 1.00, sight_mult = 1.00, hear_mult = 1.00,
        detection_chance_bonus = 0.25, damage_taken_mult = 1.0,
        knockdown_chance_mult = 1.0, knockdown_immune = false, screech_on_death = false,
    },
    [2] = {
        id = 2, key = "elite", display = "Elite", display_zombie = "Elite Zombie",
        hp_mult = 1.50, dmg_mult = 1.15, speed_mult = 1.05, sight_mult = 1.30, hear_mult = 1.20,
        detection_chance_bonus = 0.0, damage_taken_mult = 0.80,
        knockdown_chance_mult = 1.0, knockdown_immune = false, screech_on_death = false,
    },
    [3] = {
        id = 3, key = "system_elite", display = "System Elite", display_zombie = "System Elite Zombie",
        hp_mult = 2.00, dmg_mult = 1.20, speed_mult = 1.08, sight_mult = 1.30, hear_mult = 1.25,
        detection_chance_bonus = 0.0, damage_taken_mult = 0.70,
        knockdown_chance_mult = 0.50, knockdown_immune = false, screech_on_death = false,
    },
    [4] = {
        id = 4, key = "system_champion", display = "System Champion", display_zombie = "System Champion Zombie",
        hp_mult = 2.50, dmg_mult = 1.25, speed_mult = 1.10, sight_mult = 1.30, hear_mult = 1.30,
        detection_chance_bonus = 0.0, damage_taken_mult = 0.50,
        knockdown_chance_mult = 0.0, knockdown_immune = true, screech_on_death = true,
    },
}

-- Rank weights at WR1 and WR40 (then ease-in blend + renormalize)
local RANK_W_WR1 = { [1] = 100, [2] = 0, [3] = 0, [4] = 0 }
local RANK_W_WR40 = { [1] = 40, [2] = 30, [3] = 20, [4] = 10 }

local function clamp(n, a, b)
    n = tonumber(n) or 0
    if n < a then return a end
    if n > b then return b end
    return n
end

--- A2 ease-in: slow start, steeper late. t in [0,1] → [0,1]
function KnoxSystem.WorldSpawn.easeIn(t)
    t = clamp(t, 0, 1)
    return t * t -- quadratic
end

--- Progress 0..1 from WR1..WR40 (WR<=1 → 0, WR>=40 → 1)
function KnoxSystem.WorldSpawn.progress(wr)
    wr = tonumber(wr) or 0
    if wr <= WR_MIN then return 0 end
    if wr >= WR_MAX then return 1 end
    return KnoxSystem.WorldSpawn.easeIn((wr - WR_MIN) / (WR_MAX - WR_MIN))
end

local function lerp(a, b, u)
    return a + (b - a) * u
end

local function blendWeights(a, b, u)
    local out, sum = {}, 0
    for i = 1, 4 do
        local v = lerp(tonumber(a[i]) or 0, tonumber(b[i]) or 0, u)
        if v < 0 then v = 0 end
        out[i] = v
        sum = sum + v
    end
    if sum <= 0 then
        return { [1] = 1, [2] = 0, [3] = 0, [4] = 0 }
    end
    for i = 1, 4 do out[i] = out[i] / sum end
    return out
end

function KnoxSystem.WorldSpawn.getEliteRankDef(rankId)
    return ELITE_RANKS[tonumber(rankId) or 0]
end

--- Full spawn profile for this World Rank (UI name).
function KnoxSystem.WorldSpawn.profile(worldRank)
    local wr = tonumber(worldRank) or 0
    if wr < 0 then wr = 0 end
    if wr > WR_MAX then wr = WR_MAX end
    local u = KnoxSystem.WorldSpawn.progress(wr) -- 0 at WR1, 1 at WR40

    local hpBase = lerp(HP_WR1, HP_WR40, u)
    -- Below WR1: treat like WR1 anchors for HP/elite
    if wr < WR_MIN then
        hpBase = HP_WR1
        u = 0
    end

    local eliteChance = lerp(ELITE_CH_WR1, ELITE_CH_WR40, u)
    if wr < WR_MIN then eliteChance = ELITE_CH_WR1 end

    local knoxSprint = 0
    local knoxAddsSprinter = false
    if wr >= SPRINT_GATE then
        knoxAddsSprinter = true
        -- ease-in from WR5 → WR40 on top of gate
        local su = 0
        if wr >= WR_MAX then
            su = 1
        elseif wr <= SPRINT_GATE then
            su = 0
        else
            su = KnoxSystem.WorldSpawn.easeIn((wr - SPRINT_GATE) / (WR_MAX - SPRINT_GATE))
        end
        knoxSprint = lerp(SPRINT_WR5, SPRINT_WR40, su)
    end

    -- Normal loadout (E2-ish complexity via ease-in; hard empty at WR<=1)
    local normal = {
        force_empty = (wr <= WR_MIN), -- Goblin-only path for mods
        count_min = 0,
        count_max = 0,
        max_t3 = 0,
        max_t2 = 0,
        max_tier = 1,
    }
    if wr > WR_MIN then
        -- count: ease toward 1–5 at WR40 (uniform in range after min floats up)
        local cLo = lerp(0, 1, u)
        local cHi = lerp(0, 5, u)
        normal.count_min = math.floor(cLo + 1e-6)
        normal.count_max = math.max(normal.count_min, math.floor(cHi + 1e-6))
        if normal.count_max < 1 and u > 0.05 then
            normal.count_max = 1
        end
        -- caps ease in: T2/T3 only later
        normal.max_t3 = (u >= 0.55) and 1 or 0
        normal.max_t2 = (u < 0.25) and 0 or (u < 0.70 and 1 or 2)
        normal.max_tier = 1
        if u >= 0.70 then normal.max_tier = 3
        elseif u >= 0.35 then normal.max_tier = 2 end
        if wr >= WR_MAX then
            normal.count_min, normal.count_max = 1, 5
            normal.max_t3, normal.max_t2, normal.max_tier = 1, 2, 3
        end
    end

    -- Elite loadout E2: early 1–2 T1 only; full 6-spine only late
    local eliteLoadout = {
        mode = "t1_only", -- or "spine"
        count_min = 1,
        count_max = 2,
        max_tier = 1,
        spine = false,
    }
    if wr >= WR_MAX or u >= 0.90 then
        eliteLoadout.mode = "spine"
        eliteLoadout.spine = true
        eliteLoadout.count_min = 6
        eliteLoadout.count_max = 6
        eliteLoadout.max_tier = 4
        eliteLoadout.t4 = { min = 1, max = 2 }
        eliteLoadout.t3 = { min = 1, max = 2 }
        eliteLoadout.t2 = { min = 1, max = 2 }
        -- t1 fill to 6
    elseif u >= 0.55 then
        -- mid: growing T1–T2, not full spine yet
        eliteLoadout.mode = "growing"
        eliteLoadout.count_min = 2
        eliteLoadout.count_max = math.min(5, 2 + math.floor(u * 4))
        eliteLoadout.max_tier = (u >= 0.75) and 3 or 2
    end

    return {
        worldRank = wr,
        progress = u,
        hpMultBase = hpBase,
        eliteChance = eliteChance,
        eliteRankWeights = blendWeights(RANK_W_WR1, RANK_W_WR40, u),
        knoxAddsSprinter = knoxAddsSprinter,
        knoxSprinterChance = knoxSprint,
        normalLoadout = normal,
        eliteLoadout = eliteLoadout,
        -- retained for debug
        anchors = {
            hp_wr1 = HP_WR1, hp_wr40 = HP_WR40,
            elite_wr1 = ELITE_CH_WR1, elite_wr40 = ELITE_CH_WR40,
            sprint_gate = SPRINT_GATE, sprint_wr5 = SPRINT_WR5, sprint_wr40 = SPRINT_WR40,
        },
    }
end

local function randFloat(lo, hi)
    lo = lo or 0
    hi = hi or 1
    local r = nil
    pcall(function()
        if ZombRandFloat then r = lo + ZombRandFloat(0, 1) * (hi - lo) end
    end)
    if r == nil then r = lo + math.random() * (hi - lo) end
    return r
end

function KnoxSystem.WorldSpawn.rollEliteRank(profile)
    local w = profile and profile.eliteRankWeights or RANK_W_WR1
    local roll = randFloat(0, 1)
    local acc = 0
    for i = 1, 4 do
        acc = acc + (tonumber(w[i]) or 0)
        if roll <= acc then return i, ELITE_RANKS[i] end
    end
    return 1, ELITE_RANKS[1]
end

function KnoxSystem.WorldSpawn.rollIsElite(profile)
    local ch = profile and tonumber(profile.eliteChance) or ELITE_CH_WR1
    return randFloat(0, 1) < ch, ch
end

--- Roll Knox sprinter flag for non-Goblin. Returns doSprint, chanceUsed, knoxDrove
--- S1: below gate chance=0 (do not force sprinter; leave vanilla alone — we simply don't stamp sprint).
function KnoxSystem.WorldSpawn.rollKnoxSprinter(profile, isCrawler)
    if isCrawler then return false, 0, false end
    if not profile or not profile.knoxAddsSprinter then
        return false, 0, false
    end
    local ch = tonumber(profile.knoxSprinterChance) or 0
    if ch <= 0 then return false, 0, true end
    return (randFloat(0, 1) < ch), ch, true
end

--- Goblin sprinter: neighborhood-driven (prefer KS_Goblin.applyNeighborhoodSpeed).
--- Fallback if Goblin module missing: ~35% random.
function KnoxSystem.WorldSpawn.rollGoblinSprinter()
    return randFloat(0, 1) < 0.35, 0.35
end

print("[KnoxSystem] KS_WorldSpawn loaded (A2 ease-in WR1→40; HP→250%; H1/S1/E2/D2)")
