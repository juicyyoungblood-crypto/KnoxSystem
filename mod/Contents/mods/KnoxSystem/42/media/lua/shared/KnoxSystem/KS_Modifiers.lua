-- Zombie Modifier catalog + loadout framework
-- Add mods via KnoxSystem.Modifiers.register({...}) — no spawn-script rewrite needed.
-- WorldZombies only asks: rollGoblin? / rollLoadout(worldRank, elite) → ids + tags string.
-- Combat/AI effects are separate (apply later by id); this module is data + pick rules.
require "KnoxSystem/KS_ModData"

KnoxSystem.Modifiers = KnoxSystem.Modifiers or {}

local byId = {}       -- id -> def
local byTier = {}     -- tier -> { id, ... }  (ordered registration)
local byFamily = {}   -- family -> { id, ... }
local antiHard = {}   -- list of {a,b} pairs (sorted a<b for lookup)
local antiSet = {}    -- "a|b" -> true

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

local function clamp(n, a, b)
    n = tonumber(n) or 0
    if n < a then return a end
    if n > b then return b end
    return n
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

--- Register or replace a Modifier definition.
--- Required: id (string), modifier_tier (0-4), display (string)
--- Optional: family, analyze_label, kind, potency, weight, effects (table), flags...
function KnoxSystem.Modifiers.register(def)
    if type(def) ~= "table" or not def.id then return false end
    local id = tostring(def.id)
    local tier = tonumber(def.modifier_tier)
    if tier == nil then tier = 1 end
    tier = math.floor(tier)
    if tier < 0 then tier = 0 end
    if tier > 4 then tier = 4 end

    local family = tostring(def.family or id)
    local entry = {
        id = id,
        modifier_tier = tier,
        family = family,
        display = tostring(def.display or id),
        analyze_label = tostring(def.analyze_label or def.display or id),
        kind = tostring(def.kind or "binary"),
        potency = tonumber(def.potency) or 1,
        weight = tonumber(def.weight) or 1,
        effects = type(def.effects) == "table" and def.effects or {},
        -- special
        independent_roll = def.independent_roll and true or false,
        roll_first = def.roll_first and true or false,
        chance = tonumber(def.chance),
        loadout = def.loadout ~= false, -- false = not picked by normal loadout
        elite_only = def.elite_only and true or false,
        non_elite_ok = def.non_elite_ok ~= false,
        meta = def.meta,
    }

    -- Replace previous registration in tier/family lists
    if byId[id] then
        local old = byId[id]
        local list = byTier[old.modifier_tier]
        if list then
            for i = #list, 1, -1 do
                if list[i] == id then table.remove(list, i) end
            end
        end
        local fl = byFamily[old.family]
        if fl then
            for i = #fl, 1, -1 do
                if fl[i] == id then table.remove(fl, i) end
            end
        end
    end

    byId[id] = entry
    byTier[tier] = byTier[tier] or {}
    byTier[tier][#byTier[tier] + 1] = id
    byFamily[family] = byFamily[family] or {}
    byFamily[family][#byFamily[family] + 1] = id
    return true
end

function KnoxSystem.Modifiers.registerAntiCombo(a, b)
    if not a or not b or a == b then return end
    a, b = tostring(a), tostring(b)
    local x, y = a, b
    if x > y then x, y = y, x end
    local key = x .. "|" .. y
    if antiSet[key] then return end
    antiSet[key] = true
    antiHard[#antiHard + 1] = { x, y }
end

function KnoxSystem.Modifiers.get(id)
    return byId[tostring(id or "")]
end

function KnoxSystem.Modifiers.getLabel(id)
    local d = byId[tostring(id or "")]
    if d then return d.analyze_label or d.display end
    return nil
end

function KnoxSystem.Modifiers.idsInTier(tier)
    tier = tonumber(tier) or 0
    local src = byTier[tier] or {}
    local out = {}
    for i = 1, #src do out[i] = src[i] end
    return out
end

function KnoxSystem.Modifiers.allIds()
    local out = {}
    for id, _ in pairs(byId) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function KnoxSystem.Modifiers.toTagsString(idList)
    if type(idList) ~= "table" then return "" end
    local parts = {}
    for _, id in ipairs(idList) do
        if id and tostring(id) ~= "" then parts[#parts + 1] = tostring(id) end
    end
    return table.concat(parts, ",")
end

function KnoxSystem.Modifiers.parseTags(tags)
    local out = {}
    if tags == nil then return out end
    if type(tags) == "table" then
        for _, id in ipairs(tags) do out[#out + 1] = tostring(id) end
        return out
    end
    for piece in string.gmatch(tostring(tags), "[^,]+") do
        piece = piece:match("^%s*(.-)%s*$") or piece
        if piece ~= "" then out[#out + 1] = piece end
    end
    return out
end

local function conflictsWith(id, chosenSet, chosenList)
    local def = byId[id]
    if not def then return true end
    if chosenSet[def.family] then return true end -- one per family
    for _, other in ipairs(chosenList) do
        local a, b = id, other
        if a > b then a, b = b, a end
        if antiSet[a .. "|" .. b] then return true end
        -- also anti by family names if registered that way
        local od = byId[other]
        if od then
            local fa, fb = def.family, od.family
            if fa > fb then fa, fb = fb, fa end
            if antiSet[fa .. "|" .. fb] then return true end
        end
    end
    return false
end

local function poolForTier(tier, elite, usedFamily, chosenList)
    local ids = byTier[tier] or {}
    local pool = {}
    for _, id in ipairs(ids) do
        local d = byId[id]
        if d and d.loadout and not d.independent_roll then
            if d.elite_only and not elite then
                -- skip
            elseif (not d.non_elite_ok) and not elite then
                -- skip
            elseif not conflictsWith(id, usedFamily, chosenList) then
                pool[#pool + 1] = id
            end
        end
    end
    return pool
end

local function pickWeightedId(pool)
    if not pool or #pool == 0 then return nil end
    local sum = 0
    for _, id in ipairs(pool) do
        local d = byId[id]
        sum = sum + (d and d.weight or 1)
    end
    if sum <= 0 then return pool[1] end
    local roll = randFloat(0, sum)
    local acc = 0
    for _, id in ipairs(pool) do
        local d = byId[id]
        acc = acc + (d and d.weight or 1)
        if roll <= acc then return id end
    end
    return pool[#pool]
end

local function pickCountFromWeights(wmap)
    local sum = 0
    for _, w in pairs(wmap) do sum = sum + (tonumber(w) or 0) end
    if sum <= 0 then return 0 end
    local roll = randFloat(0, sum)
    local acc = 0
    local keys = {}
    for k, _ in pairs(wmap) do keys[#keys + 1] = tonumber(k) or 0 end
    table.sort(keys)
    for _, k in ipairs(keys) do
        acc = acc + (tonumber(wmap[k]) or 0)
        if roll <= acc then return k end
    end
    return keys[#keys] or 0
end

-- Count curves vs World Rank (0..40) — draft, tunable without touching spawn body
local NON_ELITE_COUNT = {
    [0]  = { [0] = 1.0 },
    [10] = { [0] = 0.6, [1] = 0.35, [2] = 0.05 },
    [20] = { [0] = 0.25, [1] = 0.45, [2] = 0.25, [3] = 0.05 },
    [30] = { [1] = 0.35, [2] = 0.45, [3] = 0.20 },
    [40] = { [1] = 0.25, [2] = 0.40, [3] = 0.35 },
}

local function interpolateCountWeights(tableByWr, wr)
    wr = clamp(wr, 0, 40)
    local keys = {}
    for k, _ in pairs(tableByWr) do keys[#keys + 1] = tonumber(k) end
    table.sort(keys)
    if #keys == 0 then return { [0] = 1 } end
    if wr <= keys[1] then
        local c = {}
        for k, v in pairs(tableByWr[keys[1]]) do c[k] = v end
        return c
    end
    if wr >= keys[#keys] then
        local c = {}
        for k, v in pairs(tableByWr[keys[#keys]]) do c[k] = v end
        return c
    end
    local lo, hi = keys[1], keys[#keys]
    for i = 1, #keys - 1 do
        if wr >= keys[i] and wr <= keys[i + 1] then
            lo, hi = keys[i], keys[i + 1]
            break
        end
    end
    local t = 0
    if hi > lo then t = (wr - lo) / (hi - lo) end
    local a, b = tableByWr[lo], tableByWr[hi]
    local out = {}
    local seen = {}
    for k, _ in pairs(a) do seen[k] = true end
    for k, _ in pairs(b) do seen[k] = true end
    for k, _ in pairs(seen) do
        out[k] = lerp(tonumber(a[k]) or 0, tonumber(b[k]) or 0, t)
    end
    return out
end

local function addPick(list, usedFamily, id)
    local d = byId[id]
    if not d then return false end
    if conflictsWith(id, usedFamily, list) then return false end
    list[#list + 1] = id
    usedFamily[d.family] = true
    return true
end

local function pickOneFromTiers(tiers, elite, usedFamily, chosen)
    -- try highest tier first for bias
    for i = #tiers, 1, -1 do
        local pool = poolForTier(tiers[i], elite, usedFamily, chosen)
        local id = pickWeightedId(pool)
        if id and addPick(chosen, usedFamily, id) then return true end
    end
    -- fallback any loadout tier 1-3 (or 4 if elite)
    local order = elite and { 4, 3, 2, 1 } or { 3, 2, 1 }
    for _, tier in ipairs(order) do
        local pool = poolForTier(tier, elite, usedFamily, chosen)
        local id = pickWeightedId(pool)
        if id and addPick(chosen, usedFamily, id) then return true end
    end
    return false
end

--- Goblin independent first roll. Returns true if Goblin stamped (caller must stop: no elite, no loadout).
--- Chance is SOLELY Sandbox.goblinChance() (per-thousand option → 0.001..0.01, default 0.002).
--- Catalog chance field is documentation only — not used for the roll (no double-dip).
function KnoxSystem.Modifiers.rollGoblin()
    local g = byId["goblin"]
    if not g or not g.independent_roll then return false, nil end

    local ch = 0.002
    pcall(function()
        if KnoxSystem.Sandbox and KnoxSystem.Sandbox.goblinChance then
            ch = tonumber(KnoxSystem.Sandbox.goblinChance()) or 0.002
        end
    end)
    if ch < 0.001 then ch = 0.001 end
    if ch > 0.01 then ch = 0.01 end

    local roll = randFloat(0, 1)
    local hit = roll < ch

    KnoxSystem.Modifiers._goblinRollN = (KnoxSystem.Modifiers._goblinRollN or 0) + 1
    local n = KnoxSystem.Modifiers._goblinRollN
    if hit or n <= 5 or (n % 100) == 0 then
        pcall(function()
            if KnoxSystem.Track and KnoxSystem.Track.log then
                KnoxSystem.Track.log("zombie", "goblin_roll", {
                    n = n,
                    roll = roll,
                    chance = ch,
                    hit = hit and 1 or 0,
                    perThousand = math.floor(ch * 1000 + 0.5),
                    note = hit and "GOBLIN exclusive (no elite/loadout)" or "miss",
                })
            end
        end)
        if hit then
            print(string.format(
                "[KnoxSystem] Goblin HIT n=%d roll=%.4f ch=%.4f (sandbox %d/1000) — exclusive, no elite",
                n, roll, ch, math.floor(ch * 1000 + 0.5)
            ))
        end
    end

    if hit then
        return true, "goblin"
    end
    return false, nil
end

--- Roll a modifier id list.
--- worldRank: number
--- isElite: boolean
--- profile: optional KnoxSystem.WorldSpawn.profile(wr) — preferred (A2/E2 recipes)
function KnoxSystem.Modifiers.rollLoadout(worldRank, isElite, profile)
    worldRank = clamp(worldRank, 0, 40)
    isElite = isElite and true or false
    local chosen, usedFamily = {}, {}

    if not profile and KnoxSystem.WorldSpawn and KnoxSystem.WorldSpawn.profile then
        profile = KnoxSystem.WorldSpawn.profile(worldRank)
    end

    if isElite then
        local el = profile and profile.eliteLoadout or nil
        if el and el.spine then
            -- Full spine: 1–2 T4, 1–2 T3, 1–2 T2, T1 fill to 6
            local n4 = 1
            if el.t4 then
                local a, b = el.t4.min or 1, el.t4.max or 2
                n4 = a
                if b > a and randFloat(0, 1) < 0.5 then n4 = b end
            end
            for _ = 1, n4 do pickOneFromTiers({ 4 }, true, usedFamily, chosen) end
            local n3 = 1
            if el.t3 then
                local a, b = el.t3.min or 1, el.t3.max or 2
                n3 = a
                if b > a and randFloat(0, 1) < 0.5 then n3 = b end
            end
            for _ = 1, n3 do pickOneFromTiers({ 3 }, true, usedFamily, chosen) end
            local n2 = 1
            if el.t2 then
                local a, b = el.t2.min or 1, el.t2.max or 2
                n2 = a
                if b > a and randFloat(0, 1) < 0.5 then n2 = b end
            end
            for _ = 1, n2 do pickOneFromTiers({ 2 }, true, usedFamily, chosen) end
            while #chosen < 6 do
                if not pickOneFromTiers({ 1, 2, 3 }, true, usedFamily, chosen) then break end
            end
            return chosen
        end

        -- Early / growing elite (E2): no T4 spine yet
        local cmin = (el and el.count_min) or 1
        local cmax = (el and el.count_max) or 2
        if cmax < cmin then cmax = cmin end
        local target = cmin
        if cmax > cmin then
            target = cmin + math.floor(randFloat(0, cmax - cmin + 0.999))
        end
        local maxTier = (el and el.max_tier) or 1
        if maxTier < 1 then maxTier = 1 end
        local tiers = {}
        for ti = 1, maxTier do tiers[#tiers + 1] = ti end
        for _ = 1, target do
            if not pickOneFromTiers(tiers, true, usedFamily, chosen) then break end
        end
        return chosen
    end

    -- Non-elite
    local nl = profile and profile.normalLoadout or nil
    if nl and nl.force_empty then
        return chosen
    end
    local cmin = (nl and nl.count_min) or 0
    local cmax = (nl and nl.count_max) or 0
    if cmax < 1 and cmin < 1 then return chosen end
    if cmax < cmin then cmax = cmin end
    local target = cmin
    if cmax > cmin then
        target = cmin + math.floor(randFloat(0, cmax - cmin + 0.999))
    end
    if target < 1 then return chosen end

    local maxTier = (nl and nl.max_tier) or 1
    local maxT2 = (nl and nl.max_t2) or 99
    local maxT3 = (nl and nl.max_t3) or 99
    local nT2, nT3 = 0, 0
    local tiers = {}
    for ti = 1, math.max(1, maxTier) do tiers[#tiers + 1] = ti end

    for _ = 1, target do
        -- Build restricted tier list by remaining caps
        local allow = {}
        for _, ti in ipairs(tiers) do
            if ti == 3 and nT3 >= maxT3 then
                -- skip
            elseif ti == 2 and nT2 >= maxT2 then
                -- skip
            else
                allow[#allow + 1] = ti
            end
        end
        if #allow == 0 then break end
        local before = #chosen
        if not pickOneFromTiers(allow, false, usedFamily, chosen) then break end
        if #chosen > before then
            local id = chosen[#chosen]
            local d = byId[id]
            if d then
                if d.modifier_tier == 2 then nT2 = nT2 + 1 end
                if d.modifier_tier == 3 then nT3 = nT3 + 1 end
            end
        end
    end
    return chosen
end

--- Default catalog (design/zombie_mutations.yaml). Safe to re-run; register replaces.
function KnoxSystem.Modifiers.registerDefaults()
    -- Tier 0 special
    KnoxSystem.Modifiers.register({
        id = "goblin", display = "Goblin", analyze_label = "Goblin",
        modifier_tier = 0, family = "goblin", kind = "special",
        independent_roll = true, roll_first = true, chance = 0.002, -- production 1/500; test via GOBLIN_CHANCE_OVERRIDE
        loadout = false, non_elite_ok = true,
        effects = { flee = true },
    })

    -- Tier 1
    KnoxSystem.Modifiers.register({
        id = "thick_skin", display = "Thick Skin", modifier_tier = 1, family = "thick_skin",
        kind = "percent", potency = 1, effects = { damage_taken_mult_blunt = 0.85 },
    })
    KnoxSystem.Modifiers.register({
        id = "hardened_skin", display = "Hardened Skin", modifier_tier = 1, family = "hardened_skin",
        kind = "percent", potency = 1, effects = { damage_taken_mult_blade = 0.85 },
    })
    KnoxSystem.Modifiers.register({
        id = "heavy_hit", display = "Heavy Hit", modifier_tier = 1, family = "heavy_hit",
        kind = "percent", potency = 1,
        effects = { damage_dealt_mult_player = 1.15, thump_damage_mult_doors_windows = 1.25 },
    })
    KnoxSystem.Modifiers.register({
        id = "relentless", display = "Relentless", modifier_tier = 1, family = "relentless",
        kind = "binary", effects = { knockdown_immune = true },
    })

    -- Tier 2 (+ potency II rows)
    KnoxSystem.Modifiers.register({
        id = "thick_skin_2", display = "Thick Skin II", modifier_tier = 2, family = "thick_skin",
        kind = "percent", potency = 2, effects = { damage_taken_mult_blunt = 0.70 },
    })
    KnoxSystem.Modifiers.register({
        id = "hardened_skin_2", display = "Hardened Skin II", modifier_tier = 2, family = "hardened_skin",
        kind = "percent", potency = 2, effects = { damage_taken_mult_blade = 0.70 },
    })
    KnoxSystem.Modifiers.register({
        id = "heavy_hit_2", display = "Heavy Hit II", modifier_tier = 2, family = "heavy_hit",
        kind = "percent", potency = 2,
        effects = { damage_dealt_mult_player = 1.30, thump_damage_mult_doors_windows = 1.50 },
    })
    KnoxSystem.Modifiers.register({
        id = "anchored", display = "Anchored", modifier_tier = 2, family = "anchored",
        kind = "binary", effects = { knockback_immune = true, stagger_immune = true, knockdown_immune = true },
    })
    KnoxSystem.Modifiers.register({
        id = "sharp_bones", display = "Sharp Bones", modifier_tier = 2, family = "sharp_bones",
        kind = "binary", effects = { bleed_on_damage = true },
    })
    KnoxSystem.Modifiers.register({
        id = "sharp_nose", display = "Sharp Nose", modifier_tier = 2, family = "sharp_nose",
        kind = "binary", effects = { detect_radius = 10, detect_no_los = true },
    })
    KnoxSystem.Modifiers.register({
        id = "system_hardened", display = "Sys.Hardened", analyze_label = "Sys.Hardened",
        modifier_tier = 2, family = "system_hardened", kind = "percent", potency = 1,
        effects = { damage_taken_mult_system = 0.75 },
    })

    -- Tier 3
    KnoxSystem.Modifiers.register({
        id = "system_hardened_2", display = "Sys.Hardened II", analyze_label = "Sys.Hardened II",
        modifier_tier = 3, family = "system_hardened", kind = "percent", potency = 2,
        effects = { damage_taken_mult_system = 0.50 },
    })
    KnoxSystem.Modifiers.register({
        id = "smart", display = "Smart", modifier_tier = 3, family = "smart",
        kind = "binary", effects = { open_unlocked_doors = true, vehicle_nest = true },
    })
    KnoxSystem.Modifiers.register({
        id = "silent", display = "Silent", modifier_tier = 3, family = "silent",
        kind = "binary", effects = { no_vocals = true, deaf_like_detect = true },
    })

    -- Tier 4 elite-only
    KnoxSystem.Modifiers.register({
        id = "evolved", display = "Evolved", modifier_tier = 4, family = "evolved",
        kind = "percent", elite_only = true,
        effects = { hp_mult = 3.0, damage_dealt_mult = 0.5 },
    })
    KnoxSystem.Modifiers.register({
        id = "screecher", display = "Screecher", modifier_tier = 4, family = "screecher",
        kind = "binary", elite_only = true,
        effects = { alarm_while_sees_player = true },
    })

    -- Hard anti-combos (ids or families)
    KnoxSystem.Modifiers.registerAntiCombo("screecher", "silent")
    KnoxSystem.Modifiers.registerAntiCombo("anchored", "relentless")
    KnoxSystem.Modifiers.registerAntiCombo("anchored", "evolved")
end

-- Boot defaults once
KnoxSystem.Modifiers.registerDefaults()

-- =============================================================================
-- Easy combat effects (percent + immune). No Sharp Nose / Silent / Smart / etc.
-- Vanilla damage is already applied when OnWeaponHitCharacter fires → DR via heal-back.
-- =============================================================================

local function isZombie(obj)
    local z = false
    pcall(function()
        if obj and instanceof and instanceof(obj, "IsoZombie") then z = true end
        if not z and obj and obj.isZombie and obj:isZombie() then z = true end
    end)
    return z
end

local function isPlayer(obj)
    local p = false
    pcall(function()
        if obj and instanceof and instanceof(obj, "IsoPlayer") then p = true end
    end)
    return p
end

function KnoxSystem.Modifiers.listOnZombie(zombie)
    local ids = {}
    local seen = {}
    local function add(id)
        if id == nil then return end
        id = tostring(id):gsub("^%s+", ""):gsub("%s+$", "")
        if id == "" or id == "elite_core" then return end
        local key = id:lower()
        if seen[key] then return end
        seen[key] = true
        ids[#ids + 1] = id
    end
    if not zombie then return ids end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if not md then return ids end
    -- Match Analyze: always merge knoxTags CSV + knoxEliteMods (table or string).
    -- Old path used elite-only when table non-empty and skipped tags → HH could show on plate
    -- from tags while combat bundle only saw a partial elite list (or vice versa).
    if md.knoxTags then
        for piece in string.gmatch(tostring(md.knoxTags), "[^,]+") do
            add(piece)
        end
    end
    if type(md.knoxEliteMods) == "table" then
        -- ipairs for array; also pairs for odd deserialized shapes
        local n = #md.knoxEliteMods
        if n > 0 then
            for i = 1, n do add(md.knoxEliteMods[i]) end
        else
            for _, id in pairs(md.knoxEliteMods) do
                if type(id) == "string" or type(id) == "number" then add(id) end
            end
        end
    elseif type(md.knoxEliteMods) == "string" then
        for piece in string.gmatch(md.knoxEliteMods, "[^,]+") do
            add(piece)
        end
    end
    return ids
end

--- Aggregate easy combat stats from catalog rows on this zombie.
function KnoxSystem.Modifiers.getCombatBundle(zombie)
    local b = {
        taken_blunt = 1,
        taken_blade = 1,
        taken_system = 1,
        dealt_player = 1,
        thump = 1,
        hp_mult_mod = 1,
        knockdown_immune = false,
        stagger_immune = false,
        knockback_immune = false,
        ids = {},
    }
    local ids = KnoxSystem.Modifiers.listOnZombie(zombie)
    b.ids = ids
    for _, id in ipairs(ids) do
        local def = byId[id] or byId[tostring(id):lower()]
        local fx = def and def.effects
        if type(fx) == "table" then
            if fx.damage_taken_mult_blunt then
                b.taken_blunt = b.taken_blunt * (tonumber(fx.damage_taken_mult_blunt) or 1)
            end
            if fx.damage_taken_mult_blade then
                b.taken_blade = b.taken_blade * (tonumber(fx.damage_taken_mult_blade) or 1)
            end
            if fx.damage_taken_mult_system then
                b.taken_system = b.taken_system * (tonumber(fx.damage_taken_mult_system) or 1)
            end
            if fx.damage_dealt_mult_player then
                b.dealt_player = b.dealt_player * (tonumber(fx.damage_dealt_mult_player) or 1)
            end
            if fx.damage_dealt_mult then -- Evolved etc.
                b.dealt_player = b.dealt_player * (tonumber(fx.damage_dealt_mult) or 1)
            end
            if fx.thump_damage_mult_doors_windows then
                b.thump = b.thump * (tonumber(fx.thump_damage_mult_doors_windows) or 1)
            end
            if fx.hp_mult then
                b.hp_mult_mod = b.hp_mult_mod * (tonumber(fx.hp_mult) or 1)
            end
            if fx.knockdown_immune then b.knockdown_immune = true end
            if fx.stagger_immune then b.stagger_immune = true end
            if fx.knockback_immune then b.knockback_immune = true end
        end
    end
    -- Prefer stamp cache if higher (guards against transient list glitches)
    pcall(function()
        local md = zombie:getModData()
        if md and md.knoxFxDealtPlayer then
            local cached = tonumber(md.knoxFxDealtPlayer) or 1
            if cached > b.dealt_player then b.dealt_player = cached end
        end
        if md and md.knoxFxTakenBlunt then
            local c = tonumber(md.knoxFxTakenBlunt) or 1
            if c < b.taken_blunt then b.taken_blunt = c end
        end
        if md and md.knoxFxTakenBlade then
            local c = tonumber(md.knoxFxTakenBlade) or 1
            if c < b.taken_blade then b.taken_blade = c end
        end
        if md and md.knoxFxKnockdownImmune then b.knockdown_immune = true end
        if md and md.knoxFxStaggerImmune then
            b.stagger_immune = true
            b.knockback_immune = true
        end
    end)
    -- Elite rank package immunities / KD mult (data on modData)
    pcall(function()
        local md = zombie:getModData()
        if not md then return end
        local rank = tonumber(md.knoxEliteRank) or 0
        if rank > 0 and KnoxSystem.WorldSpawn and KnoxSystem.WorldSpawn.getEliteRankDef then
            local rd = KnoxSystem.WorldSpawn.getEliteRankDef(rank)
            if rd then
                if rd.knockdown_immune then b.knockdown_immune = true end
                b.elite_kd_chance_mult = tonumber(rd.knockdown_chance_mult)
                b.elite_damage_taken_mult = tonumber(rd.damage_taken_mult) or 1
            end
        end
    end)
    return b
end

--- blunt | blade | other  (bare hands / shove → blunt)
function KnoxSystem.Modifiers.weaponDamageClass(weapon)
    if not weapon then return "blunt" end
    local cls = "other"
    pcall(function()
        if weapon.isBareHands and weapon:isBareHands() then
            cls = "blunt"
            return
        end
        local cats = nil
        if weapon.getCategories then cats = weapon:getCategories() end
        local blob = ""
        if cats then
            local n = 0
            pcall(function() n = cats:size() end)
            for i = 0, math.max(0, n) - 1 do
                local c = nil
                pcall(function() c = tostring(cats:get(i) or "") end)
                if c then blob = blob .. " " .. c:lower() end
            end
        end
        pcall(function()
            if weapon.getFullType then blob = blob .. " " .. string.lower(tostring(weapon:getFullType() or "")) end
            if weapon.getDisplayName then blob = blob .. " " .. string.lower(tostring(weapon:getDisplayName() or "")) end
        end)
        if blob:find("blade", 1, true) or blob:find("axe", 1, true) or blob:find("spear", 1, true)
            or blob:find("knife", 1, true) or blob:find("machete", 1, true) or blob:find("katana", 1, true)
            or blob:find("sword", 1, true) then
            cls = "blade"
        elseif blob:find("blunt", 1, true) or blob:find("baseball", 1, true) or blob:find("hammer", 1, true)
            or blob:find("club", 1, true) or blob:find("bat", 1, true) or blob:find("crowbar", 1, true) then
            cls = "blunt"
        else
            -- default melee unknown → blunt (most improvised)
            local ranged = false
            if weapon.isRanged and weapon:isRanged() then ranged = true end
            cls = ranged and "other" or "blunt"
        end
    end)
    return cls
end

--- Incoming taken mult for a player→zombie hit (skins + elite rank DR).
function KnoxSystem.Modifiers.takenMultForHit(zombie, weapon, opts)
    opts = opts or {}
    local b = KnoxSystem.Modifiers.getCombatBundle(zombie)
    local wclass = KnoxSystem.Modifiers.weaponDamageClass(weapon)
    local m = 1
    if wclass == "blade" then
        m = b.taken_blade
    elseif wclass == "blunt" then
        m = b.taken_blunt
    end
    -- Sys.Hardened: reduces System-layer damage (Power snips etc.) when opts.systemLayer
    if opts.systemLayer then
        m = m * b.taken_system
    end
    if b.elite_damage_taken_mult then
        m = m * b.elite_damage_taken_mult
    end
    if m < 0.05 then m = 0.05 end
    if m > 3 then m = 3 end
    return m, b, wclass
end

local function adjustHealth(zombie, delta)
    if not zombie or not delta or delta == 0 then return end
    pcall(function()
        if not zombie.getHealth or not zombie.setHealth then return end
        local h = tonumber(zombie:getHealth()) or 0
        local nh = h + delta
        if nh < 0 then nh = 0 end
        zombie:setHealth(nh)
    end)
end

local function trackDamage(kind, fields)
    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn then return end
    if not KnoxSystem.Track.isChannelOn("damage") then return end
    pcall(function()
        KnoxSystem.Track.log("damage", kind, fields)
    end)
end

local function tagsCsv(ids)
    if type(ids) ~= "table" or #ids == 0 then return "" end
    return table.concat(ids, ",")
end

--- =============================================================================
--- Control immunities (Relentless / Anchored)
--- Lessons (0.6.12–0.6.15):
---   1) Idle packs: NEVER call KD/stagger setters every tick while standing → flop bug.
---   2) Engine applies KD AFTER OnWeaponHitCharacter → late veto on OnWeaponHitXp.
---   3) Relentless = KD only; keep shove/stagger/hit reaction (don't clear hit reaction).
---   4) Anchored   = full lock: no KD, no stagger, no push (clear hit reaction OK).
---   5) Never call IsoZombie:knockDown(bool) — unclear semantics.
--- =============================================================================

local function tagsLower(md)
    return string.lower(tostring((md and md.knoxTags) or ""))
end

local function eliteHas(md, idWant)
    if not md or type(md.knoxEliteMods) ~= "table" then return false end
    local want = string.lower(idWant)
    for i = 1, #md.knoxEliteMods do
        if string.lower(tostring(md.knoxEliteMods[i] or "")) == want then return true end
    end
    return false
end

--- Relentless or Anchored (or any knockdown_immune catalog effect).
function KnoxSystem.Modifiers.isKnockdownImmune(zombie)
    if not zombie then return false end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if md then
        if md.knoxFxKnockdownImmune then return true end
        local t = tagsLower(md)
        if t:find("relentless", 1, true) or t:find("anchored", 1, true) then return true end
        if eliteHas(md, "relentless") or eliteHas(md, "anchored") then return true end
    end
    local ok, b = pcall(function() return KnoxSystem.Modifiers.getCombatBundle(zombie) end)
    return ok and b and b.knockdown_immune and true or false
end

--- Anchored only: full control lock (stagger + knockback + KD).
function KnoxSystem.Modifiers.isControlLocked(zombie)
    if not zombie then return false end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if md then
        if md.knoxFxStaggerImmune then return true end
        local t = tagsLower(md)
        if t:find("anchored", 1, true) then return true end
        if eliteHas(md, "anchored") then return true end
    end
    local ok, b = pcall(function() return KnoxSystem.Modifiers.getCombatBundle(zombie) end)
    if ok and b and (b.stagger_immune or b.knockback_immune) then return true end
    return false
end

--- Knockdown clear. idleOnly: only if isKnockedDown(). combat: force clear.
function KnoxSystem.Modifiers.forceNoKnockdown(zombie, idleOnly)
    if not zombie then return false end
    if idleOnly == nil then idleOnly = false end

    local wasDown = false
    pcall(function()
        if zombie.isKnockedDown and zombie:isKnockedDown() then wasDown = true end
    end)

    if idleOnly then
        if not wasDown then return false end
        pcall(function()
            if zombie.setAlwaysKnockedDown then zombie:setAlwaysKnockedDown(false) end
            if zombie.setKnockedDown then zombie:setKnockedDown(false) end
            if zombie.setOnFloor then zombie:setOnFloor(false) end
            if zombie.setFallOnFront then zombie:setFallOnFront(false) end
        end)
        return true
    end

    pcall(function()
        if zombie.setAlwaysKnockedDown then zombie:setAlwaysKnockedDown(false) end
        if zombie.setKnockedDown then zombie:setKnockedDown(false) end
        if zombie.setOnFloor then zombie:setOnFloor(false) end
        if zombie.setFallOnFront then zombie:setFallOnFront(false) end
    end)
    return true
end

--- Anchored stagger/push clear. idleOnly: only if currently staggering.
--- Combat: clear stagger + hit reaction + try setIgnoreStaggerBack.
function KnoxSystem.Modifiers.forceNoStagger(zombie, idleOnly)
    if not zombie then return false end
    if idleOnly == nil then idleOnly = false end

    local staggering = false
    pcall(function()
        if zombie.isStaggerBack and zombie:isStaggerBack() then staggering = true end
    end)

    if idleOnly then
        if not staggering then return false end
        pcall(function()
            if zombie.setStaggerBack then zombie:setStaggerBack(false) end
            if zombie.setHitReaction then zombie:setHitReaction("") end
        end)
        return true
    end

    -- Combat path (Anchored): cancel push/stagger immediately
    pcall(function()
        if zombie.setStaggerBack then zombie:setStaggerBack(false) end
        if zombie.setHitReaction then zombie:setHitReaction("") end
        if zombie.setIgnoreStaggerBack then zombie:setIgnoreStaggerBack(true) end
    end)
    return true
end

--- Hit-time control clear (early path). Prefer late OnWeaponHitXp for final KD.
--- Relentless: KD only, never wipe hit reaction / stagger.
--- Anchored: KD + stagger + hit reaction.
function KnoxSystem.Modifiers.clearControlState(zombie, bundle)
    if not zombie then return false end
    local kdImm = false
    local locked = false
    if bundle then
        kdImm = bundle.knockdown_immune and true or false
        locked = (bundle.stagger_immune or bundle.knockback_immune) and true or false
    else
        kdImm = KnoxSystem.Modifiers.isKnockdownImmune(zombie)
        locked = KnoxSystem.Modifiers.isControlLocked(zombie)
    end
    local did = false
    if kdImm then
        if KnoxSystem.Modifiers.forceNoKnockdown(zombie, false) then did = true end
    end
    if locked then
        if KnoxSystem.Modifiers.forceNoStagger(zombie, false) then did = true end
    end
    return did
end

--- Late hit hook (OnWeaponHitXp): engine has usually applied KD/stagger by now.
function KnoxSystem.Modifiers.onWeaponHitXpControlVeto(attacker, zombie, weapon, damage)
    if not isZombie(zombie) then return end
    local kdImm = KnoxSystem.Modifiers.isKnockdownImmune(zombie)
    local locked = KnoxSystem.Modifiers.isControlLocked(zombie)
    if not kdImm and not locked then return end

    local kdBefore, stBefore = -1, -1
    pcall(function()
        if zombie.isKnockedDown then kdBefore = zombie:isKnockedDown() and 1 or 0 end
        if zombie.isStaggerBack then stBefore = zombie:isStaggerBack() and 1 or 0 end
    end)

    if kdImm then
        KnoxSystem.Modifiers.forceNoKnockdown(zombie, false)
    end
    if locked then
        KnoxSystem.Modifiers.forceNoStagger(zombie, false)
    end

    local kdAfter, stAfter = -1, -1
    pcall(function()
        if zombie.isKnockedDown then kdAfter = zombie:isKnockedDown() and 1 or 0 end
        if zombie.isStaggerBack then stAfter = zombie:isStaggerBack() and 1 or 0 end
    end)

    local tags = ""
    pcall(function()
        local md = zombie:getModData()
        tags = md and tostring(md.knoxTags or "") or ""
    end)

    if locked then
        trackDamage("anchored_control_veto", {
            reason = "OnWeaponHitXp",
            kdBefore = kdBefore,
            kdAfter = kdAfter,
            stBefore = stBefore,
            stAfter = stAfter,
            tags = tags,
            note = "Anchored full lock: no KD, no stagger/push (late veto)",
        })
    else
        trackDamage("relentless_kd_veto", {
            reason = "OnWeaponHitXp",
            kdBefore = kdBefore,
            kdAfter = kdAfter,
            stBefore = stBefore,
            stAfter = stAfter,
            tags = tags,
            note = "Relentless KD-only late veto; shove/stagger kept",
        })
    end
end

-- Back-compat alias
KnoxSystem.Modifiers.onWeaponHitXpRelentless = KnoxSystem.Modifiers.onWeaponHitXpControlVeto

--- Idle maintain: state-gated only (standing/no-stagger = no-op → no pack flop).
function KnoxSystem.Modifiers.maintainImmunities(zombie)
    if not zombie then return end
    local md = nil
    pcall(function()
        if type(zombie.getModData) == "function" then md = zombie:getModData() end
    end)
    if not md or not md.knoxWorldScaled then return end

    local t = tagsLower(md)
    local maybeKd = md.knoxFxKnockdownImmune
        or t:find("relentless", 1, true)
        or t:find("anchored", 1, true)
    local maybeLock = md.knoxFxStaggerImmune or t:find("anchored", 1, true)
    if not maybeKd and not maybeLock then return end

    if maybeKd and KnoxSystem.Modifiers.isKnockdownImmune(zombie) then
        md.knoxFxKnockdownImmune = true
        KnoxSystem.Modifiers.forceNoKnockdown(zombie, true)
    end
    if maybeLock and KnoxSystem.Modifiers.isControlLocked(zombie) then
        md.knoxFxStaggerImmune = true
        KnoxSystem.Modifiers.forceNoStagger(zombie, true)
        -- Prefer engine ignore-stagger flag when available (set once, not every flop)
        pcall(function()
            if zombie.setIgnoreStaggerBack and zombie.isIgnoreStaggerBack then
                if not zombie:isIgnoreStaggerBack() then
                    zombie:setIgnoreStaggerBack(true)
                end
            elseif zombie.setIgnoreStaggerBack then
                -- no getter: set sparingly via cache
                if not md.knoxFxIgnoreStaggerSet then
                    zombie:setIgnoreStaggerBack(true)
                    md.knoxFxIgnoreStaggerSet = true
                end
            end
        end)
    end
end

--- Player hit zombie: heal-back for DR on vanilla event damage. Returns takenMult for Power layer.
function KnoxSystem.Modifiers.onPlayerHitZombie(attacker, zombie, weapon, damage)
    if not isPlayer(attacker) or not isZombie(zombie) then
        return 1, nil
    end
    pcall(function()
        if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.ensureStamped then
            KnoxSystem.WorldZombies.ensureStamped(zombie, "hit_fx")
        elseif KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.stamp then
            KnoxSystem.WorldZombies.stamp(zombie, "hit_fx")
        end
    end)

    local dmg = tonumber(damage) or 0
    local hpBefore = nil
    pcall(function()
        if zombie.getHealth then hpBefore = tonumber(zombie:getHealth()) end
    end)
    local taken, bundle, wclass = KnoxSystem.Modifiers.takenMultForHit(zombie, weapon, { systemLayer = false })
    local refund = 0
    -- Heal back unapplied portion of vanilla hit
    if dmg > 0 and taken < 0.999 then
        refund = dmg * (1 - taken)
        if refund > 0.0001 then
            adjustHealth(zombie, refund)
        end
    end
    local hpAfter = hpBefore
    pcall(function()
        if zombie.getHealth then hpAfter = tonumber(zombie:getHealth()) end
    end)
    KnoxSystem.Modifiers._lastHitTakenMult = taken
    KnoxSystem.Modifiers._lastHitBundle = bundle
    KnoxSystem.Modifiers._lastHitWclass = wclass

    trackDamage("mod_hit_out", {
        reason = "player_hit_zombie",
        tags = tagsCsv(bundle and bundle.ids),
        wclass = wclass or "?",
        eventDamage = dmg,
        takenMult = taken,
        takenBlunt = bundle and bundle.taken_blunt or 1,
        takenBlade = bundle and bundle.taken_blade or 1,
        takenSystem = bundle and bundle.taken_system or 1,
        eliteTaken = bundle and bundle.elite_damage_taken_mult or 1,
        refund = refund,
        hpBeforeFx = hpBefore or -1,
        hpAfterFx = hpAfter or -1,
        kdImmune = (bundle and bundle.knockdown_immune) and 1 or 0,
        staggerImmune = (bundle and (bundle.stagger_immune or bundle.knockback_immune)) and 1 or 0,
        note = "DR heal-back before Power; plate still shows raw eventDamage",
    })
    return taken, bundle
end

--- After Power/knock: clear KD/stagger if immune; scale Power bonus was applied raw — snip extra if needed.
function KnoxSystem.Modifiers.afterPlayerHitZombie(attacker, zombie, weapon, damage, powerBonusApplied)
    if not isZombie(zombie) then return end
    local bundle = KnoxSystem.Modifiers._lastHitBundle or KnoxSystem.Modifiers.getCombatBundle(zombie)
    -- Power / System layer: if Power removed extra HP, refund (1 - taken_system*skins) of that snip
    local bonus = tonumber(powerBonusApplied) or 0
    local powerRefund = 0
    if bonus > 0 then
        local takenSys = select(1, KnoxSystem.Modifiers.takenMultForHit(zombie, weapon, { systemLayer = true }))
        local takenAll = takenSys
        if takenAll < 0.999 then
            powerRefund = bonus * (1 - takenAll)
            adjustHealth(zombie, powerRefund)
        end
    end

    local kdBefore, stBefore = -1, -1
    pcall(function()
        if zombie.isKnockedDown then kdBefore = zombie:isKnockedDown() and 1 or 0 end
        if zombie.isStaggerBack then stBefore = zombie:isStaggerBack() and 1 or 0 end
    end)

    -- Immunities: early clear (late OnWeaponHitXp is authoritative for KD)
    KnoxSystem.Modifiers.clearControlState(zombie, bundle)
    if KnoxSystem.Modifiers.isKnockdownImmune(zombie) then
        KnoxSystem.Modifiers.forceNoKnockdown(zombie, false)
    end
    if KnoxSystem.Modifiers.isControlLocked(zombie) then
        KnoxSystem.Modifiers.forceNoStagger(zombie, false)
    end

    -- Elite rank KD chance mult: if not full immune and vanilla/power KD'd, maybe clear
    local kdMult = tonumber(bundle.elite_kd_chance_mult)
    if (not bundle.knockdown_immune) and kdMult and kdMult < 1 and kdMult >= 0 then
        pcall(function()
            if zombie.isKnockedDown and zombie:isKnockedDown() then
                local roll = 1
                if ZombRandFloat then roll = ZombRandFloat(0, 1)
                else roll = math.random() end
                if roll > kdMult then
                    if zombie.setKnockedDown then zombie:setKnockedDown(false) end
                    if zombie.setOnFloor then zombie:setOnFloor(false) end
                end
            end
        end)
    end

    local kdAfter, stAfter = -1, -1
    pcall(function()
        if zombie.isKnockedDown then kdAfter = zombie:isKnockedDown() and 1 or 0 end
        if zombie.isStaggerBack then stAfter = zombie:isStaggerBack() and 1 or 0 end
    end)

    if (bundle.knockdown_immune or bundle.stagger_immune or powerRefund > 0) then
        trackDamage("mod_hit_out_after", {
            reason = "after_power_control",
            tags = tagsCsv(bundle.ids),
            powerBonus = bonus,
            powerRefund = powerRefund,
            kdBefore = kdBefore,
            kdAfter = kdAfter,
            stBefore = stBefore,
            stAfter = stAfter,
            kdImmune = bundle.knockdown_immune and 1 or 0,
            staggerImmune = (bundle.stagger_immune or bundle.knockback_immune) and 1 or 0,
            eliteKdMult = kdMult or 1,
            note = "Relentless=KD only (keep shove); Anchored=full control lock; maintain on update",
        })
    end
end

--- Apply Heavy Hit / Evolved when player body health drops near an attacking modded zombie.
--- B42 often never fires WeaponHit or SCRATCH/BITE GetDamage with a usable amount — only BLEEDING DoT.
function KnoxSystem.Modifiers.onPlayerUpdateIncoming(player)
    if not isPlayer(player) then return end
    local id = 0
    pcall(function()
        if player.getPlayerNum then id = player:getPlayerNum() or 0 end
    end)
    KnoxSystem.Modifiers._prevBodyHp = KnoxSystem.Modifiers._prevBodyHp or {}
    local cur = nil
    pcall(function()
        local bd = player:getBodyDamage()
        if bd and bd.getOverallBodyHealth then
            cur = tonumber(bd:getOverallBodyHealth())
        end
    end)
    if cur == nil then
        pcall(function()
            if player.getHealth then cur = tonumber(player:getHealth()) end
        end)
    end
    if cur == nil then return end
    local prev = KnoxSystem.Modifiers._prevBodyHp[id]
    KnoxSystem.Modifiers._prevBodyHp[id] = cur
    if prev == nil then return end
    local drop = prev - cur
    -- Ignore tiny bleed ticks and heals
    if drop < 0.35 then return end
    -- GodMode / heal spikes
    if drop > 80 then return end

    local zed, b = KnoxSystem.Modifiers.findNearestCombatZombie(player, 2.6)
    if not zed or not b then return end
    local dealt = b.dealt_player or 1
    if math.abs(dealt - 1) < 0.001 then
        -- Throttle "no HH" noise (packs of silent zeds)
        local t = 0
        pcall(function()
            if getTimestampMs then t = getTimestampMs() or 0 end
        end)
        KnoxSystem.Modifiers._lastNearMissLog = KnoxSystem.Modifiers._lastNearMissLog or 0
        if t - KnoxSystem.Modifiers._lastNearMissLog < 2500 then return end
        KnoxSystem.Modifiers._lastNearMissLog = t
        trackDamage("mod_hit_in_near", {
            reason = "body_hp_drop",
            drop = drop,
            tags = tagsCsv(b.ids),
            dealtMult = 1,
            note = "Body HP drop; nearest-scored zed has no Heavy Hit/Evolved (dealt=1)",
        })
        return
    end
    local attacking = false
    local dist = -1
    pcall(function()
        if zed.isAttacking then attacking = zed:isAttacking() end
        if zed.getTarget and zed:getTarget() == player then attacking = true end
        local zx, zy = zed:getX(), zed:getY()
        local px, py = player:getX(), player:getY()
        local dx, dy = zx - px, zy - py
        dist = math.sqrt(dx * dx + dy * dy)
    end)
    local delta = drop * (dealt - 1)
    if delta > 0 then
        pcall(function()
            local bd = player:getBodyDamage()
            if bd and bd.ReduceGeneralHealth then
                bd:ReduceGeneralHealth(delta)
            end
        end)
    elseif delta < 0 then
        pcall(function()
            local bd = player:getBodyDamage()
            if bd and bd.AddGeneralHealth then
                bd:AddGeneralHealth(-delta)
            end
        end)
    end
    -- Re-baseline AFTER our extra so the next frame doesn't treat ReduceGeneralHealth as a new claw
    pcall(function()
        local bd = player:getBodyDamage()
        if bd and bd.getOverallBodyHealth then
            local after = tonumber(bd:getOverallBodyHealth())
            if after ~= nil then
                KnoxSystem.Modifiers._prevBodyHp[id] = after
            end
        end
    end)
    trackDamage("mod_hit_in", {
        reason = "body_hp_drop",
        source = "OnPlayerUpdate",
        drop = drop,
        bodyHpBefore = prev,
        bodyHpAfter = cur,
        tags = tagsCsv(b.ids),
        dealtMult = dealt,
        extraDelta = delta,
        attacking = attacking and 1 or 0,
        zedDist = dist,
        note = "Heavy Hit/Evolved via body HP drop; zed picked by max dealtMult in range",
    })
end

--- Find best combat zombie near the player for inbound FX.
--- Prefer: highest dealt_player (Heavy Hit) → attacking → nearest.
function KnoxSystem.Modifiers.findNearestCombatZombie(player, maxDist)
    if not player then return nil, nil end
    maxDist = tonumber(maxDist) or 2.5
    local best, bestB = nil, nil
    local bestScore = -1e9
    local px, py, pz = 0, 0, 0
    pcall(function()
        px = player:getX(); py = player:getY(); pz = player:getZ()
    end)
    pcall(function()
        local cell = player:getCell()
        if not cell or not cell.getZombieList then return end
        local list = cell:getZombieList()
        if not list then return end
        local n = list:size() or 0
        for i = 0, n - 1 do
            local z = list:get(i)
            if z then
                local zx, zy, zz = 0, 0, 99
                pcall(function() zx = z:getX(); zy = z:getY(); zz = z:getZ() end)
                if zz == pz then
                    local dx, dy = zx - px, zy - py
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d <= maxDist then
                        pcall(function()
                            if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.stamp then
                                local md = z:getModData()
                                if not md or not md.knoxWorldScaled then
                                    KnoxSystem.WorldZombies.stamp(z, "hit_player_near")
                                end
                            end
                        end)
                        local b = KnoxSystem.Modifiers.getCombatBundle(z)
                        local dealt = (b and b.dealt_player) or 1
                        local attacking = false
                        pcall(function()
                            if z.isAttacking then attacking = z:isAttacking() end
                            if z.getTarget and z:getTarget() == player then attacking = true end
                        end)
                        -- Score: dealt mult is king (Heavy Hit 1.15 / II 1.30), then attacking, then closer
                        local score = (dealt - 1) * 1000
                        if attacking then score = score + 50 end
                        score = score - d
                        if score > bestScore then
                            bestScore = score
                            best = z
                            bestB = b
                        end
                    end
                end
            end
        end
    end)
    return best, bestB
end

--- B42 often routes zombie claws through OnPlayerGetDamage (SCRATCH/BITE), not WeaponHitCharacter.
--- Apply Heavy Hit / Evolved extra (or reduced) damage here.
function KnoxSystem.Modifiers.onPlayerCombatDamage(player, damageType, damage)
    if not isPlayer(player) then return end
    local dtype = string.upper(tostring(damageType or ""))
    -- Skip DoTs / disease ticks
    if dtype == "" or dtype == "BLEEDING" or dtype == "INFECTION" or dtype == "POISON"
        or dtype == "FOOD_SICKNESS" or dtype == "FOODSICKNESS" or dtype == "COLD"
        or dtype == "HUNGER" or dtype == "THIRST" or dtype == "FATIGUE" then
        return
    end
    -- Combat-ish types (scratch/bite/fall from shove — prefer scratch/bite)
    local combat = dtype:find("SCRATCH", 1, true) or dtype:find("BITE", 1, true)
        or dtype:find("CUT", 1, true) or dtype:find("BLUNT", 1, true)
        or dtype:find("WEAPON", 1, true) or dtype:find("HIT", 1, true)
        or dtype == "FALLING" -- skip? no — skip fall
    if dtype == "FALLING" or dtype == "FALL" then return end
    if not combat then
        -- Unknown type with meaningful damage near a zed: still try (log type)
        local dmgProbe = tonumber(damage) or 0
        if dmgProbe < 0.01 then return end
    end

    local dmg = tonumber(damage) or 0
    if dmg <= 0 then return end

    local zed, b = KnoxSystem.Modifiers.findNearestCombatZombie(player, 1.85)
    if not zed then
        trackDamage("mod_hit_in_miss", {
            reason = "no_near_zed",
            damageType = dtype,
            damage = dmg,
            note = "Player combat damage but no zombie within 1.85 tiles",
        })
        return
    end
    if not b then b = KnoxSystem.Modifiers.getCombatBundle(zed) end
    local dealt = (b and b.dealt_player) or 1
    local rankDmg = 1
    pcall(function()
        local md = zed:getModData()
        if md and md.knoxDmgMult then rankDmg = tonumber(md.knoxDmgMult) or 1 end
    end)
    -- Stack rank baseline lightly into dealt for logging only; Heavy Hit is the catalog mult
    local delta = 0
    if math.abs(dealt - 1) >= 0.001 then
        delta = dmg * (dealt - 1)
        pcall(function()
            local bd = player:getBodyDamage()
            if not bd then return end
            if delta > 0 and bd.ReduceGeneralHealth then
                bd:ReduceGeneralHealth(delta)
            elseif delta < 0 and bd.AddGeneralHealth then
                bd:AddGeneralHealth(-delta)
            end
        end)
    end
    trackDamage("mod_hit_in", {
        reason = "player_combat_damage",
        source = "OnPlayerGetDamage",
        damageType = dtype,
        tags = tagsCsv(b and b.ids),
        eventDamage = dmg,
        dealtMult = dealt,
        rankDmgMult = rankDmg,
        extraDelta = delta,
        note = "Heavy Hit/Evolved via GetDamage path (WeaponHit often misses zombie→player)",
    })
end

--- Zombie hit player: Heavy Hit / Evolved dealt mult (extra damage beyond vanilla).
function KnoxSystem.Modifiers.onZombieHitPlayer(zombie, player, weapon, damage)
    if not isPlayer(player) then return end
    -- Always log attempts when target is player (diagnose missing WeaponHit)
    if not isZombie(zombie) then
        trackDamage("mod_hit_in_skip", {
            reason = "attacker_not_zombie",
            damage = tonumber(damage) or 0,
            note = "WeaponHit target=player but attacker failed isZombie check",
        })
        return
    end
    pcall(function()
        if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.stamp then
            local md = zombie:getModData()
            if not md or not md.knoxWorldScaled then
                KnoxSystem.WorldZombies.stamp(zombie, "hit_player")
            end
        end
    end)
    local b = KnoxSystem.Modifiers.getCombatBundle(zombie)
    local dealt = b.dealt_player or 1
    local rankDmg = 1
    pcall(function()
        local md = zombie:getModData()
        if md and md.knoxDmgMult then rankDmg = tonumber(md.knoxDmgMult) or 1 end
    end)
    local dmg = tonumber(damage) or 0
    local delta = 0
    if dmg > 0 and math.abs(dealt - 1) >= 0.001 then
        delta = dmg * (dealt - 1)
        pcall(function()
            local bd = player:getBodyDamage()
            if not bd then return end
            if delta > 0 and bd.ReduceGeneralHealth then
                bd:ReduceGeneralHealth(delta)
            elseif delta < 0 and bd.AddGeneralHealth then
                bd:AddGeneralHealth(-delta)
            elseif delta > 0 and bd.setOverallBodyHealth and bd.getOverallBodyHealth then
                local oh = tonumber(bd:getOverallBodyHealth()) or 100
                bd:setOverallBodyHealth(math.max(0, oh - delta * 10))
            end
        end)
    end

    trackDamage("mod_hit_in", {
        reason = "zombie_weapon_hit",
        source = "OnWeaponHitCharacter",
        tags = tagsCsv(b.ids),
        eventDamage = dmg,
        dealtMult = dealt,
        rankDmgMult = rankDmg,
        extraDelta = delta,
        thumpMult = b.thump or 1,
        note = "Heavy Hit / Evolved dealt; delta applied on top of vanilla",
    })
end

--- Thump doors/windows: Heavy Hit thump mult via extra damage if API allows.
function KnoxSystem.Modifiers.onZombieOrPlayerThump(attacker, weapon, thumpable, damage)
    -- Only when zombie thumps: attacker is zombie
    if not isZombie(attacker) then return end
    local b = KnoxSystem.Modifiers.getCombatBundle(attacker)
    if math.abs(b.thump - 1) < 0.001 then return end
    local dmg = tonumber(damage) or 0
    -- Prefer weapon door damage path
    pcall(function()
        if not thumpable then return end
        local extra = 0
        if dmg > 0 then
            extra = dmg * (b.thump - 1)
        else
            local base = 5
            pcall(function()
                if weapon and weapon.getDoorDamage then base = tonumber(weapon:getDoorDamage()) or 5 end
            end)
            extra = base * (b.thump - 1)
        end
        if extra <= 0 then return end
        if thumpable.WeaponHit then
            -- may double-call; try damage health
        end
        if thumpable.getHealth and thumpable.setHealth then
            local h = tonumber(thumpable:getHealth()) or 0
            thumpable:setHealth(math.max(0, h - extra))
        end
    end)
end

--- Stamp helper: apply Evolved hp_mult (and cache combat flags on modData).
function KnoxSystem.Modifiers.applyStampPassives(zombie, md)
    if not zombie or not md then return 1 end
    local b = KnoxSystem.Modifiers.getCombatBundle(zombie)
    md.knoxFxKnockdownImmune = b.knockdown_immune and true or false
    md.knoxFxStaggerImmune = (b.stagger_immune or b.knockback_immune) and true or false
    md.knoxFxDealtPlayer = b.dealt_player
    md.knoxFxThump = b.thump
    md.knoxFxTakenBlunt = b.taken_blunt
    md.knoxFxTakenBlade = b.taken_blade
    md.knoxFxTakenSystem = b.taken_system
    -- Anchored: ask engine to ignore stagger when API exists (set once at stamp)
    if md.knoxFxStaggerImmune then
        pcall(function()
            if zombie.setIgnoreStaggerBack then
                zombie:setIgnoreStaggerBack(true)
                md.knoxFxIgnoreStaggerSet = true
            end
        end)
    end
    -- Evolved HP already may stack; return mult to fold into health apply
    return b.hp_mult_mod or 1
end

print(string.format(
    "[KnoxSystem] KS_Modifiers loaded (framework + easy combat FX; %d mods)",
    #(KnoxSystem.Modifiers.allIds())
))
