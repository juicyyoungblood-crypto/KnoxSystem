-- KnoxSystem config: level curve + Personal XP weights (from design YAML)
require "KnoxSystem/KS_ModData"

KnoxSystem.Config = KnoxSystem.Config or {}

-- progression.yaml cubic C(L) = a*L + b*L^2 + c*L^3
KnoxSystem.Config.LevelCurve = {
    a = 314.6952861952857,
    b = 58.83518518518534,
    c = 1.469528619528618,
    maxLevel = 100,
    spPerLevel = 1,
}

-- weights.yaml bucket defaults
KnoxSystem.Config.BucketWeight = {
    combat = 1.0,
    firearm = 1.0,
    agility = 1.0,
    survivalist = 0.5,
    crafting = 0.3,
    passive = 0.25,
    unknown = 0.5,
}

-- Design name / common perk id -> weight
-- Live perk keys also registered below for B42 Perks.* where possible
KnoxSystem.Config.SkillWeight = {
    -- Passive
    Strength = 0.25,
    Fitness = 0.25,
    -- Agility
    Sprinting = 1.0,
    Sprint = 1.0,
    Lightfooted = 1.0,
    Lightfoot = 1.0,
    Nimble = 1.0,
    Sneaking = 1.0,
    Sneak = 1.0,
    -- Combat
    Axe = 1.0,
    LongBlunt = 1.0,
    Blunt = 1.0,
    ShortBlunt = 1.0,
    SmallBlunt = 1.0,
    LongBlade = 1.0,
    SmallBlade = 1.0,
    ShortBlade = 1.0,
    Spear = 1.0,
    Maintenance = 1.0,
    -- Firearm
    Aiming = 1.0,
    Reloading = 1.0,
    Reload = 1.0,
    -- Survival
    Fishing = 0.5,
    Trapping = 0.5,
    Foraging = 0.5,
    PlantScavenging = 0.5,
    Farming = 0.5,
    Agriculture = 0.5,
    Husbandry = 0.5,
    HusbandryAnimal = 0.5,
    FirstAid = 0.5,
    Doctor = 0.5,
    Tracking = 0.5,
    -- Crafting
    Carpentry = 0.3,
    Woodwork = 0.3,
    Carving = 0.3,
    Cooking = 0.3,
    Electrical = 0.3,
    Electricity = 0.3,
    MetalWelding = 0.3,
    MetalWork = 0.3,
    Welding = 0.3,
    Mechanics = 0.3,
    Mechanic = 0.3,
    Tailoring = 0.3,
    Blacksmith = 0.3,
    Blacksmithing = 0.3,
    Pottery = 0.3,
    Glassmaking = 0.3,
    GlassmakingSkill = 0.3,
    Masonry = 0.3,
    Knapping = 0.3,
    FlintKnapping = 0.3,
}

KnoxSystem.Config.ClassSkillWeightFactor = 0.5
KnoxSystem.Config.DebugXP = false -- off: was spamming +Personal XP / PL lines every skill tick

-- Extensible verification log (KS_TrackLog). Toggle master or per-channel.
-- Console: [KnoxTrack/<channel>] …  File: Zomboid/Lua/KnoxSystem_track.log (typical)
-- Add later: KnoxSystem.Track.register("charge", { enabled = true, desc = "…" })
--            KnoxSystem.Config.TrackLog.channels.charge = true
-- Dump: KnoxSystem.Track.dump(50)  Status: KnoxSystem.Track.status()
KnoxSystem.Config.TrackLog = {
    enabled = true,
    toConsole = true,
    toFile = true,
    fileName = "KnoxSystem_track.log",
    maxRing = 200,
    channels = {
        damage = true,
        stress = true,
        protection = true,
        strength = false, -- deprecated
        power = true,
        stamina = true,
        zombie = false, -- hard OFF (was true and overrode TrackLog default)
        loot = true,
        resilience = true,
    },
}

-- Phase 5 world scaling (spawn-stamp tiers + elites). intensity 0=off tiers, 1=design tables, 2+=more high tier/elites
KnoxSystem.Config.WorldScaling = {
    enabled = true,
    intensity = 1.0,
}

function KnoxSystem.Config.getWeightForPerkKey(key)
    if not key then
        return KnoxSystem.Config.BucketWeight.unknown
    end
    local w = KnoxSystem.Config.SkillWeight[key]
    if w ~= nil then
        return w
    end
    -- case-insensitive fallback
    local lower = string.lower(tostring(key))
    for k, v in pairs(KnoxSystem.Config.SkillWeight) do
        if string.lower(k) == lower then
            return v
        end
    end
    return KnoxSystem.Config.BucketWeight.unknown
end

print("[KnoxSystem] KS_Config loaded")
