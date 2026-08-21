-- KnoxSystem Personal XP minting from base skill XP
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"
require "KnoxSystem/KS_Level"
require "KnoxSystem/KS_Sandbox"

KnoxSystem.PersonalXP = KnoxSystem.PersonalXP or {}

--- Resolve a stable string key for a Perk object
function KnoxSystem.PersonalXP.perkKey(perk)
    if perk == nil then
        return "Unknown"
    end
    -- Prefer type/id style names used in Perks.*
    local ok, result = pcall(function()
        if perk.getType then
            local t = perk:getType()
            if t ~= nil then
                return tostring(t)
            end
        end
        if perk.getId then
            local id = perk:getId()
            if id ~= nil then
                return tostring(id)
            end
        end
        if perk.getName then
            return tostring(perk:getName())
        end
        return tostring(perk)
    end)
    if ok and result and result ~= "" then
        return result
    end
    return "Unknown"
end

function KnoxSystem.PersonalXP.addPersonalXp(player, amount, reason)
    if not player or not amount or amount == 0 then
        return
    end
    local data = KnoxSystem.ensurePlayerInitialized(player, "mid_save_best_effort")
    if not data then return end
    data.personal_xp = (data.personal_xp or 0) + amount
    if KnoxSystem.Config.DebugXP then
        print(string.format(
            "[KnoxSystem] +%.2f Personal XP (%s) total=%.2f PL=%d SP=%d",
            amount, tostring(reason or "?"), data.personal_xp,
            data.personal_level or 0, data.skill_points_unspent or 0
        ))
    end
    KnoxSystem.Level.syncLevelFromXp(player, data)
end

--- Called when the game grants skill XP
function KnoxSystem.PersonalXP.onAddXP(character, perk, amount)
    if not character or not amount or amount <= 0 then
        return
    end
    -- Only track the local player for MVP (SP)
    local player = getPlayer and getPlayer() or nil
    if player ~= nil and character ~= player then
        -- Still allow if character is IsoPlayer and is local
        if instanceof and not instanceof(character, "IsoPlayer") then
            return
        end
        if character.isLocalPlayer and not character:isLocalPlayer() then
            return
        end
    end

    local key = KnoxSystem.PersonalXP.perkKey(perk)
    local weight = KnoxSystem.Config.getWeightForPerkKey(key)
    local scale = 1.0
    if KnoxSystem.Sandbox and KnoxSystem.Sandbox.personalXpScale then
        scale = KnoxSystem.Sandbox.personalXpScale()
    end
    local personal = amount * weight * scale
    if personal == 0 then
        return
    end

    local pl = character
    if not instanceof or instanceof(character, "IsoPlayer") then
        KnoxSystem.PersonalXP.addPersonalXp(pl, personal, string.format("skill:%s x%.2f xpScale=%.2f", key, weight, scale))
    end
end

local function tryHookAddXP()
    if Events and Events.AddXP then
        Events.AddXP.Add(KnoxSystem.PersonalXP.onAddXP)
        print("[KnoxSystem] Hooked Events.AddXP")
        return true
    end
    print("[KnoxSystem] WARNING: Events.AddXP missing — Personal XP will not mint from skills")
    return false
end

-- Register on load (shared or client — AddXP fires where XP is granted)
tryHookAddXP()

print("[KnoxSystem] KS_PersonalXP loaded")
