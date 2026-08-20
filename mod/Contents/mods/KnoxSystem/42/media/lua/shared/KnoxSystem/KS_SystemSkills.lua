-- System skills: Analyze + D. Storage (SP cart extensions)
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"

KnoxSystem.SystemSkills = KnoxSystem.SystemSkills or {}

-- Display order on System tab (under personal stats)
KnoxSystem.SystemSkills.ORDER = { "Analyze", "D. Storage" }

KnoxSystem.SystemSkills.DEFS = {
    Analyze = {
        field = "skill_analyze",
        max = 2,
        costPerLevel = 5,
        display = "Analyze",
    },
    ["D. Storage"] = {
        field = "skill_d_storage",
        max = 8, -- B42 custom bag Capacity hard ceiling ~49; L8=50 scripts reserved, live clamp 49
        costPerLevel = 5,
        display = "D. Storage",
    },
}

function KnoxSystem.SystemSkills.getLevel(data, name)
    if not data then return 0 end
    local def = KnoxSystem.SystemSkills.DEFS[name]
    if not def then return 0 end
    local v = tonumber(data[def.field]) or 0
    if v < 0 then v = 0 end
    local mx = tonumber(def.max) or 99
    if v > mx then v = mx end
    return v
end

function KnoxSystem.SystemSkills.analyzeLevel(data)
    return KnoxSystem.SystemSkills.getLevel(data, "Analyze")
end

function KnoxSystem.SystemSkills.dStorageLevel(data)
    return KnoxSystem.SystemSkills.getLevel(data, "D. Storage")
end

function KnoxSystem.SystemSkills.ensureFields(data)
    if not data then return end
    data.skill_analyze = tonumber(data.skill_analyze) or 0
    data.skill_d_storage = tonumber(data.skill_d_storage) or 0
    if data.skill_analyze > 2 then data.skill_analyze = 2 end
    if data.skill_d_storage > 8 then data.skill_d_storage = 8 end -- B42 bag cap; L9+ scripts retained only
    if data.skill_analyze < 0 then data.skill_analyze = 0 end
    if data.skill_d_storage < 0 then data.skill_d_storage = 0 end
    if type(data.sp_cart_stats) ~= "table" then data.sp_cart_stats = {} end
end

--- Cost for pending levels of a system skill (flat costPerLevel each)
function KnoxSystem.SystemSkills.costPending(name, current, pending)
    local def = KnoxSystem.SystemSkills.DEFS[name]
    if not def then return 0 end
    pending = pending or 0
    return pending * (def.costPerLevel or 5)
end

print("[KnoxSystem] KS_SystemSkills loaded (Analyze max2; D. Storage max8 @ 5 SP)")
