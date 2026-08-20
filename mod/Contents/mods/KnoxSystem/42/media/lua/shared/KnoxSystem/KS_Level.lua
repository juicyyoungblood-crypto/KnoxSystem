-- KnoxSystem Personal Level + SP grants
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"

KnoxSystem.Level = KnoxSystem.Level or {}

function KnoxSystem.Level.cumulativeXpForLevel(level)
    if not level or level <= 0 then
        return 0
    end
    local curve = KnoxSystem.Config.LevelCurve
    local L = math.min(level, curve.maxLevel)
    return curve.a * L + curve.b * L * L + curve.c * L * L * L
end

--- Highest Personal Level whose cumulative threshold is <= xp
function KnoxSystem.Level.levelFromXp(xp)
    xp = xp or 0
    local curve = KnoxSystem.Config.LevelCurve
    local level = 0
    for L = 1, curve.maxLevel do
        if KnoxSystem.Level.cumulativeXpForLevel(L) <= xp then
            level = L
        else
            break
        end
    end
    return level
end

function KnoxSystem.Level.xpToNextLevel(data)
    if not data then return 0 end
    local cur = data.personal_level or 0
    local maxL = KnoxSystem.Config.LevelCurve.maxLevel
    if cur >= maxL then
        return 0
    end
    local need = KnoxSystem.Level.cumulativeXpForLevel(cur + 1)
    local have = data.personal_xp or 0
    return math.max(0, need - have)
end

function KnoxSystem.Level.spGrantForLevel(level)
    -- data-driven schedule later; default 1 SP per level
    return KnoxSystem.Config.LevelCurve.spPerLevel or 1
end

--- After personal_xp changes, grant levels + SP
function KnoxSystem.Level.syncLevelFromXp(player, data)
    if not data then return end
    local target = KnoxSystem.Level.levelFromXp(data.personal_xp or 0)
    local cur = data.personal_level or 0
    if target <= cur then
        return
    end
    while cur < target do
        cur = cur + 1
        data.personal_level = cur
        local sp = KnoxSystem.Level.spGrantForLevel(cur)
        data.skill_points_unspent = (data.skill_points_unspent or 0) + sp
        print(string.format(
            "[KnoxSystem] LEVEL UP -> Personal Level %d (+%d SP, unspent=%d, xp=%.1f)",
            cur, sp, data.skill_points_unspent, data.personal_xp or 0
        ))
        if cur == 10 and not data.class_id then
            print("[KnoxSystem] Class unlock available at PL10 (UI Phase 4)")
        end
    end
end

function KnoxSystem.Level.debugDump(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then
        print("[KnoxSystem] debugDump: no player data")
        return
    end
    print(string.format(
        "[KnoxSystem] PL=%d XP=%.2f toNext=%.2f SP=%d class=%s",
        data.personal_level or 0,
        data.personal_xp or 0,
        KnoxSystem.Level.xpToNextLevel(data),
        data.skill_points_unspent or 0,
        tostring(data.class_id)
    ))
end

print("[KnoxSystem] KS_Level loaded")
