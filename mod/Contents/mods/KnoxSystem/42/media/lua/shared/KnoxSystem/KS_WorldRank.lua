-- KnoxSystem World Rank (coarse PL + day band)
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Level"

KnoxSystem.WorldRank = KnoxSystem.WorldRank or {}

-- design/world_scaling.yaml — band display draft
local function plBand(pl)
    pl = pl or 0
    if pl >= 100 then return 5 end
    if pl >= 50 then return 4 end
    if pl >= 25 then return 3 end
    if pl >= 10 then return 2 end
    if pl >= 1 then return 1 end
    return 0
end

local function dayBand(days)
    days = days or 0
    if days >= 121 then return 5 end
    if days >= 61 then return 4 end
    if days >= 31 then return 3 end
    if days >= 15 then return 2 end
    if days >= 1 then return 1 end
    return 0
end

function KnoxSystem.WorldRank.getWorldAgeDays()
    local ok, days = pcall(function()
        if getGameTime then
            local gt = getGameTime()
            if gt and gt.getWorldAgeDays then
                return gt:getWorldAgeDays()
            end
            if gt and gt.getNightsSurvived then
                return gt:getNightsSurvived()
            end
        end
        return 0
    end)
    if ok and days then return tonumber(days) or 0 end
    return 0
end

--- Integer World Rank: higher = harder world (0+)
function KnoxSystem.WorldRank.compute(player)
    local data = player and KnoxSystem.getPlayerData(player) or nil
    local pl = data and (data.personal_level or 0) or 0
    local days = KnoxSystem.WorldRank.getWorldAgeDays()
    -- Blend-ish single number: 10*max(bands) + weighted sum (readable, coarse)
    local pb = plBand(pl)
    local db = dayBand(days)
    local rank = math.floor(pb * 0.55 * 10 + db * 0.45 * 10 + 0.5)
    if rank < 0 then rank = 0 end
    return rank, pl, days, pb, db
end

function KnoxSystem.WorldRank.label(player)
    local rank = KnoxSystem.WorldRank.compute(player)
    return tostring(rank)
end

print("[KnoxSystem] KS_WorldRank loaded")
