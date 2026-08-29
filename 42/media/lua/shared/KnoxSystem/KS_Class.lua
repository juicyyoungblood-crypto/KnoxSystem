-- KnoxSystem class unlock / permanent pick (Phase 4)
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"
require "KnoxSystem/KS_Sandbox"

KnoxSystem.Class = KnoxSystem.Class or {}

KnoxSystem.Class.MVP_SELECTABLE = { warrior = true }

KnoxSystem.Class.DISPLAY = {
    warrior = "Warrior",
    thief = "Thief",
    ranger = "Ranger",
    mage = "Mage",
    crafter = "Crafter",
}

KnoxSystem.Class.WARRIOR_SKILLS = {
    { id = "MeleeProficiency", display = "Melee Proficiency" },
    { id = "Armored", display = "Armored" },
    { id = "Charge", display = "Charge" },
}

local function ensureSkillBlob(data, skillId)
    data.class_skills = data.class_skills or {}
    if type(data.class_skills[skillId]) ~= "table" then
        data.class_skills[skillId] = { level = 0, xp = 0 }
    end
    local s = data.class_skills[skillId]
    s.level = tonumber(s.level) or 0
    s.xp = tonumber(s.xp) or 0
    return s
end

function KnoxSystem.Class.hasClass(data)
    return data and data.class_locked and data.class_id ~= nil and data.class_id ~= ""
end

function KnoxSystem.Class.isWarrior(data)
    return data and data.class_id == "warrior"
end

function KnoxSystem.Class.canSelect(classId, data)
    if not data or KnoxSystem.Class.hasClass(data) then return false end
    if (data.personal_level or 0) < 10 then return false end
    return KnoxSystem.Class.MVP_SELECTABLE[classId] == true
end

function KnoxSystem.Class.initWarriorSkills(data)
    for _, sk in ipairs(KnoxSystem.Class.WARRIOR_SKILLS) do
        ensureSkillBlob(data, sk.id)
    end
end

--- Permanent class pick. Returns ok, err
function KnoxSystem.Class.select(player, classId)
    if not player or not classId then return false, "bad args" end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not data then return false, "no data" end
    classId = string.lower(classId)
    if KnoxSystem.Class.hasClass(data) then return false, "already locked" end
    if (data.personal_level or 0) < 10 then return false, "level" end
    if not KnoxSystem.Class.MVP_SELECTABLE[classId] then return false, "not selectable" end

    data.class_id = classId
    data.class_locked = true
    if classId == "warrior" then
        KnoxSystem.Class.initWarriorSkills(data)
    end
    print(string.format("[KnoxSystem] Class locked: %s (PL %d)", classId, data.personal_level or 0))
    return true
end

function KnoxSystem.Class.getSkill(data, skillId)
    if not data then return nil end
    return ensureSkillBlob(data, skillId)
end

function KnoxSystem.Class.getSkillLevel(data, skillId)
    local s = KnoxSystem.Class.getSkill(data, skillId)
    return s and (s.level or 0) or 0
end

--- XP needed to go from `level` → level+1.
--- Exact 3× regular base-skill table (locked table, not a runtime formula).
--- Keys are current level; values are xp to reach next (L0→1 … L9→10).
local CLASS_XP_TO_NEXT = {
    [0] = 225,
    [1] = 450,
    [2] = 900,
    [3] = 3000,
    [4] = 4500,
    [5] = 9000,
    [6] = 13500,
    [7] = 18000,
    [8] = 22500,
    [9] = 27000,
}

function KnoxSystem.Class.xpToNext(level)
    level = tonumber(level) or 0
    if level < 0 then level = 0 end
    if level > 9 then level = 9 end
    return CLASS_XP_TO_NEXT[level] or 27000
end

function KnoxSystem.Class.addSkillXp(player, skillId, amount, reason)
    if not player or not skillId or not amount or amount <= 0 then return false end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not data or not KnoxSystem.Class.isWarrior(data) then return false end
    local s = ensureSkillBlob(data, skillId)
    local maxL = 10
    if (s.level or 0) >= maxL then return false end

    s.xp = (s.xp or 0) + amount
    local leveled = false
    while (s.level or 0) < maxL do
        local need = KnoxSystem.Class.xpToNext(s.level or 0)
        if (s.xp or 0) < need then break end
        s.xp = (s.xp or 0) - need
        s.level = (s.level or 0) + 1
        leveled = true
        print(string.format("[KnoxSystem] Class skill level-up: %s → %d (%s)", skillId, s.level, tostring(reason)))
    end

    -- Personal XP from class skill XP (sandbox ClassSkillPersonalXpPercent; def 50 = old half-bucket)
    if KnoxSystem.PersonalXP and KnoxSystem.PersonalXP.addPersonalXp then
        local scale = 0.5
        if KnoxSystem.Sandbox and KnoxSystem.Sandbox.classSkillPersonalXpScale then
            scale = KnoxSystem.Sandbox.classSkillPersonalXpScale()
        elseif KnoxSystem.Config and KnoxSystem.Config.ClassSkillWeightFactor then
            scale = KnoxSystem.Config.ClassSkillWeightFactor
        end
        pcall(function()
            KnoxSystem.PersonalXP.addPersonalXp(
                player,
                amount * scale,
                string.format("class:%s xpScale=%.2f", skillId, scale)
            )
        end)
    end
    return true, leveled
end

function KnoxSystem.Class.shouldOfferModal(player)
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not data then return false end
    if KnoxSystem.Class.hasClass(data) then return false end
    return (data.personal_level or 0) >= 10
end
