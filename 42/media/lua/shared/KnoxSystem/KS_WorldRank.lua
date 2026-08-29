-- KnoxSystem World Rank (System Tab readout)
-- Formula (design ADR 0031 / zombie_mutations.yaml): name stays "World Rank"
--   timeLeg  = min(10, floor(worldAgeDays / 3))   -- full +10 from day 30
--   powerLeg = floor(avgPersonalLevel / 2)       -- SP: local PL; MP: mean of online PLs
--   rank     = min(40, timeLeg + powerLeg)
-- Does NOT change zombie tier stamping — callers may still use the number later.
require "KnoxSystem/KS_ModData"

KnoxSystem.WorldRank = KnoxSystem.WorldRank or {}

local TIME_DAYS_PER_STEP = 3
local TIME_LEG_MAX = 10
local POWER_PL_PER_STEP = 2
local RANK_MAX = 40
-- Design: 14-day activity window for who counts in avg PL (SP: always local player).
local ACTIVITY_WINDOW_DAYS = 14

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

function KnoxSystem.WorldRank.timeLeg(days)
    days = tonumber(days) or 0
    if days < 0 then days = 0 end
    local leg = math.floor(days / TIME_DAYS_PER_STEP)
    if leg > TIME_LEG_MAX then leg = TIME_LEG_MAX end
    if leg < 0 then leg = 0 end
    return leg
end

function KnoxSystem.WorldRank.powerLeg(avgPl)
    avgPl = tonumber(avgPl) or 0
    if avgPl < 0 then avgPl = 0 end
    return math.floor(avgPl / POWER_PL_PER_STEP)
end

--- Average Personal Level for the power leg.
--- SP: local player's PL. MP: mean PL of online players (activity window reserved for later MP roster).
function KnoxSystem.WorldRank.getAveragePersonalLevel(preferPlayer)
    local sum, n = 0, 0
    pcall(function()
        local num = 0
        if getNumActivePlayers then num = getNumActivePlayers() or 0 end
        if num < 1 then num = 1 end
        for i = 0, num - 1 do
            local p = nil
            if getSpecificPlayer then p = getSpecificPlayer(i) end
            if p then
                local data = KnoxSystem.getPlayerData(p)
                local pl = data and tonumber(data.personal_level) or 0
                sum = sum + pl
                n = n + 1
            end
        end
    end)
    if n < 1 and preferPlayer then
        local data = KnoxSystem.getPlayerData(preferPlayer)
        if data then
            return tonumber(data.personal_level) or 0
        end
    end
    if n < 1 then return 0 end
    return sum / n
end

--- Integer World Rank for UI (and later threat). Higher = harder.
--- Returns: rank, avgPl, days, timeLeg, powerLeg
--- (5th value was dayBand; now powerLeg — ZombieObserve only logs it.)
function KnoxSystem.WorldRank.compute(player)
    if player then
        -- Keep local player ModData warm; no effect on formula beyond PL read
        pcall(function() KnoxSystem.getPlayerData(player) end)
    end
    local days = KnoxSystem.WorldRank.getWorldAgeDays()
    local avgPl = KnoxSystem.WorldRank.getAveragePersonalLevel(player)
    local tLeg = KnoxSystem.WorldRank.timeLeg(days)
    local pLeg = KnoxSystem.WorldRank.powerLeg(avgPl)
    local rank = tLeg + pLeg
    if rank < 0 then rank = 0 end
    if rank > RANK_MAX then rank = RANK_MAX end
    return rank, avgPl, days, tLeg, pLeg
end

function KnoxSystem.WorldRank.label(player)
    local rank = KnoxSystem.WorldRank.compute(player)
    return tostring(rank)
end

-- Expose constants for tests / debug
KnoxSystem.WorldRank.TIME_LEG_MAX = TIME_LEG_MAX
KnoxSystem.WorldRank.RANK_MAX = RANK_MAX
KnoxSystem.WorldRank.ACTIVITY_WINDOW_DAYS = ACTIVITY_WINDOW_DAYS

print("[KnoxSystem] KS_WorldRank loaded (time/3≤10 + floor(avgPL/2), max 40)")
