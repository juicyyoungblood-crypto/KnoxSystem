-- Base skill catalog matching vanilla Skills tab labels (B42)
-- display = name shown on Skills tab / System tab
-- perk   = Perks.* key used by the game (cart + LevelPerk)

KnoxSystem = KnoxSystem or {}
KnoxSystem.BaseSkills = KnoxSystem.BaseSkills or {}

-- Ordered categories + skills (Skills tab order)
KnoxSystem.BaseSkills.CATEGORIES = {
    {
        header = "Combat - Firearms",
        skills = {
            { display = "Aiming", perk = "Aiming" },
            { display = "Reloading", perk = "Reloading" },
        },
    },
    {
        header = "Combat - Melee",
        skills = {
            { display = "Axe", perk = "Axe" },
            { display = "Long Blade", perk = "LongBlade" },
            { display = "Long Blunt", perk = "Blunt" },
            { display = "Maintenance", perk = "Maintenance" },
            { display = "Short Blade", perk = "SmallBlade" },
            { display = "Short Blunt", perk = "SmallBlunt" },
            { display = "Spear", perk = "Spear" },
        },
    },
    {
        header = "Crafting",
        skills = {
            { display = "Blacksmithing", perk = "Blacksmith" },
            { display = "Carpentry", perk = "Woodwork" },
            { display = "Carving", perk = "Carving" },
            { display = "Cooking", perk = "Cooking" },
            { display = "Electrical", perk = "Electricity" },
            { display = "Glassmaking", perk = "Glassmaking" },
            { display = "Knapping", perk = "FlintKnapping" },
            { display = "Masonry", perk = "Masonry" },
            { display = "Mechanics", perk = "Mechanics" },
            { display = "Pottery", perk = "Pottery" },
            { display = "Tailoring", perk = "Tailoring" },
            { display = "Welding", perk = "MetalWelding" },
        },
    },
    {
        header = "Farming",
        skills = {
            { display = "Agriculture", perk = "Farming" },
            { display = "Animal Care", perk = "Husbandry" },
            { display = "Butchering", perk = "Butchering" },
        },
    },
    {
        header = "Physical",
        skills = {
            { display = "Fitness", perk = "Fitness" },
            { display = "Lightfooted", perk = "Lightfoot" },
            { display = "Nimble", perk = "Nimble" },
            { display = "Running", perk = "Sprinting" },
            { display = "Sneaking", perk = "Sneak" },
            { display = "Strength", perk = "Strength" },
        },
    },
    {
        header = "Survival",
        skills = {
            { display = "First Aid", perk = "Doctor" },
            { display = "Fishing", perk = "Fishing" },
            { display = "Foraging", perk = "PlantScavenging" },
            { display = "Tracking", perk = "Tracking" },
            { display = "Trapping", perk = "Trapping" },
        },
    },
}

--- Flat list of perk keys (for iteration)
function KnoxSystem.BaseSkills.allPerkKeys()
    local out = {}
    for _, cat in ipairs(KnoxSystem.BaseSkills.CATEGORIES) do
        for _, sk in ipairs(cat.skills) do
            out[#out + 1] = sk.perk
        end
    end
    return out
end

--- display name for a perk key
function KnoxSystem.BaseSkills.displayName(perkKey)
    if not perkKey then return "?" end
    for _, cat in ipairs(KnoxSystem.BaseSkills.CATEGORIES) do
        for _, sk in ipairs(cat.skills) do
            if sk.perk == perkKey or sk.display == perkKey then
                return sk.display
            end
        end
    end
    return perkKey
end
