-- Personal Endurance (System tab, max 10 @ 2 SP)
-- Stamina (vanilla Endurance 0–1 CharacterStat):
--   On update: if bar fell, refund 6% of the loss per level (L1 keeps more stamina).
--              if bar rose, grant 6% extra of the gain per level.
--   L10 floor: never below 0.12 (last endurance moodle ~0.10).
-- Over-encumbrance damage:
--   When over weight (or HeavyLoad moodle ≥1), refund 6% of incoming damage per level
--   (heal back after the hit / continuous tick).
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Endurance = KnoxSystem.Endurance or {}

local ENDURANCE_MAX = 10
local PCT_PER_LEVEL = 0.06       -- 6% per level
local FLOOR_L10 = 0.12          -- above final Winded band (~0.10)
local EPS = 0.00005             -- ignore float noise
local LOG_MS = 4000

local lastEndu = {}             -- playerNum → last observed endurance 0–1
local lastLogMs = {}
local lastEncLogMs = {}

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return t or 0
end

local function playerId(player)
    local id = 0
    pcall(function()
        if player.getPlayerNum then id = player:getPlayerNum() or 0 end
    end)
    return id
end

function KnoxSystem.Endurance.maxLevel()
    return ENDURANCE_MAX
end

function KnoxSystem.Endurance.level(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 0 end
    local lv = tonumber(data.stat_endurance) or 0
    if lv < 0 then lv = 0 end
    if lv > ENDURANCE_MAX then lv = ENDURANCE_MAX end
    return lv
end

function KnoxSystem.Endurance.pct(player)
    return KnoxSystem.Endurance.level(player) * PCT_PER_LEVEL
end

function KnoxSystem.Endurance.clampData(data)
    if not data then return end
    local e = tonumber(data.stat_endurance) or 0
    if e < 0 then e = 0 end
    if e > ENDURANCE_MAX then e = ENDURANCE_MAX end
    data.stat_endurance = e
end

--- Read vanilla endurance 0–1 (method-only; no field R/W).
local function getEndurance(player)
    local v = nil
    pcall(function()
        local st = player:getStats()
        if not st then return end
        if type(st.getEndurance) == "function" then v = tonumber(st:getEndurance()) end
        if v == nil and type(st.getPcEndurance) == "function" then
            v = tonumber(st:getPcEndurance())
        end
        if v == nil and CharacterStat and type(st.get) == "function" then
            local cs = CharacterStat.ENDURANCE or CharacterStat.Endurance
            if cs then v = tonumber(st:get(cs)) end
        end
    end)
    pcall(function()
        if v == nil and type(player.getEndurance) == "function" then
            v = tonumber(player:getEndurance())
        end
    end)
    return v
end

--- Write endurance via methods only (Charge-proven path).
local function setEndurance(player, value)
    if value == nil then return false end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    local ok = false
    pcall(function()
        local st = player:getStats()
        if not st then return end
        if type(st.setEndurance) == "function" then
            st:setEndurance(value)
            ok = true
            return
        end
        if type(st.setPcEndurance) == "function" then
            st:setPcEndurance(value)
            ok = true
            return
        end
        if CharacterStat and type(st.set) == "function" then
            local cs = CharacterStat.ENDURANCE or CharacterStat.Endurance
            if cs then st:set(cs, value); ok = true; return end
        end
    end)
    pcall(function()
        if not ok and type(player.setEndurance) == "function" then
            player:setEndurance(value)
            ok = true
        end
    end)
    return ok
end

local function tryMethodCall(obj, name, ...)
    if not obj then return false end
    local fn = obj[name]
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, obj, ...)
    return ok
end

--- Over-encumbered: weight > max OR HeavyLoad moodle ≥ 1
function KnoxSystem.Endurance.isOverencumbered(player)
    local over = false
    pcall(function()
        local w, maxW = -1, -1
        if type(player.getInventoryWeight) == "function" then
            w = tonumber(player:getInventoryWeight()) or -1
        end
        local inv = player.getInventory and player:getInventory()
        if (w < 0) and inv and type(inv.getCapacityWeight) == "function" then
            w = tonumber(inv:getCapacityWeight()) or -1
        end
        if type(player.getMaxWeight) == "function" then
            maxW = tonumber(player:getMaxWeight()) or -1
        end
        if w >= 0 and maxW > 0 and w > maxW + 0.01 then over = true end
    end)
    if over then return true end
    pcall(function()
        local moodles = player:getMoodles()
        if not moodles or type(moodles.getMoodleLevel) ~= "function" then return end
        local mt = MoodleType and (
            MoodleType.HeavyLoad or MoodleType.HEAVY_LOAD
            or MoodleType.Endurance -- never use this for encumbrance
        )
        -- Prefer explicit HeavyLoad / overweight moodles
        local names = { "HeavyLoad", "HEAVY_LOAD", "Overweight", "OVERWEIGHT" }
        if MoodleType then
            for i = 1, #names do
                local m = MoodleType[names[i]]
                if m ~= nil then
                    local lv = tonumber(moodles:getMoodleLevel(m)) or 0
                    if lv >= 1 then over = true; return end
                end
            end
        end
    end)
    return over
end

--- Heal back general health (encumbrance damage refund). Method-only, pcall-safe.
local function refundDamage(player, amount)
    if not player or not amount or amount <= 0 then return false end
    local ok = false
    pcall(function()
        local bd = player:getBodyDamage()
        if not bd then return end
        if type(bd.AddGeneralHealth) == "function" then
            bd:AddGeneralHealth(amount)
            ok = true
            return
        end
        if type(bd.setOverallBodyHealth) == "function" and type(bd.getOverallBodyHealth) == "function" then
            local h = tonumber(bd:getOverallBodyHealth()) or 0
            bd:setOverallBodyHealth(math.min(100, h + amount))
            ok = true
            return
        end
        if type(bd.RestoreToFullHealth) == "function" then
            -- never full restore
        end
    end)
    -- Some builds: reduce damage via BodyPart health
    if not ok then
        pcall(function()
            local bd = player:getBodyDamage()
            if not bd or type(bd.getBodyParts) ~= "function" then return end
            local parts = bd:getBodyParts()
            if not parts then return end
            local n = 0
            pcall(function() n = parts:size() end)
            if n < 1 then return end
            local each = amount / n
            for i = 0, n - 1 do
                local bp = nil
                pcall(function() bp = parts:get(i) end)
                if bp and type(bp.AddHealth) == "function" then
                    pcall(function() bp:AddHealth(each) end)
                    ok = true
                elseif bp and type(bp.setHealth) == "function" and type(bp.getHealth) == "function" then
                    pcall(function()
                        local h = tonumber(bp:getHealth()) or 0
                        bp:setHealth(math.min(100, h + each))
                    end)
                    ok = true
                end
            end
        end)
    end
    return ok
end

function KnoxSystem.Endurance.onPlayerUpdate(player)
    if not player then return end
    local isP = false
    pcall(function()
        if instanceof and instanceof(player, "IsoPlayer") then isP = true end
    end)
    if not isP then return end
    pcall(function()
        if player.isLocalPlayer and not player:isLocalPlayer() then isP = false end
    end)
    if not isP then return end

    local data = KnoxSystem.getPlayerData(player)
    if not data or not data.initialized then return end
    KnoxSystem.Endurance.clampData(data)

    local lv = KnoxSystem.Endurance.level(player)
    local pct = lv * PCT_PER_LEVEL
    local cur = getEndurance(player)
    if cur == nil then return end

    local id = playerId(player)
    local prev = lastEndu[id]
    local adjusted = cur
    local delta = 0
    local kind = "none"

    if prev ~= nil and lv > 0 then
        delta = cur - prev
        if delta < -EPS then
            -- Lost stamina: refund 6% of loss per level
            local loss = -delta
            local refund = loss * pct
            adjusted = cur + refund
            kind = "drain_refund"
        elseif delta > EPS then
            -- Gained stamina: extra 6% of gain per level
            local gain = delta
            local extra = gain * pct
            adjusted = cur + extra
            kind = "regen_boost"
        end
    end

    -- L10 floor (never last moodle band)
    local floored = false
    if lv >= ENDURANCE_MAX and adjusted < FLOOR_L10 then
        adjusted = FLOOR_L10
        floored = true
        if kind == "none" then kind = "floor" else kind = kind .. "+floor" end
    end

    if adjusted > 1 then adjusted = 1 end
    if adjusted < 0 then adjusted = 0 end

    local wrote = false
    if math.abs(adjusted - cur) > EPS then
        wrote = setEndurance(player, adjusted)
        if wrote then
            -- Re-read after write
            local after = getEndurance(player)
            if after ~= nil then adjusted = after end
        end
    end

    lastEndu[id] = adjusted

    if data then
        data._endLiveApplied = (lv > 0) and wrote or (lv > 0)
        data._endMult = 1 + pct -- legacy snapshot field
        data._endPct = pct
        data._endFloor = (lv >= ENDURANCE_MAX) and FLOOR_L10 or 0
    end

    local t = nowMs()
    if lv > 0 and (kind ~= "none" or floored) and KnoxSystem.Track and KnoxSystem.Track.isChannelOn("stamina") then
        local last = lastLogMs[id] or 0
        if t - last >= LOG_MS then
            lastLogMs[id] = t
            KnoxSystem.Track.log("stamina", "endurance_live", {
                reason = kind,
                enduranceLv = lv,
                pctPerLevel = PCT_PER_LEVEL,
                totalPct = pct,
                prev = prev,
                raw = cur,
                delta = delta,
                adjusted = adjusted,
                wrote = wrote and 1 or 0,
                floorL10 = floored and 1 or 0,
                floorValue = FLOOR_L10,
                note = "Endurance live: ±6%/lv on stamina delta; L10 floor 0.12",
            })
        end
    end
end

--- Incoming damage while over-encumbered: refund 6% × level of the damage amount.
function KnoxSystem.Endurance.onPlayerGetDamage(player, damageType, damage)
    if not player then return end
    local isP = false
    pcall(function()
        if instanceof and instanceof(player, "IsoPlayer") then isP = true end
    end)
    if not isP then return end

    local lv = KnoxSystem.Endurance.level(player)
    if lv < 1 then return end
    if not KnoxSystem.Endurance.isOverencumbered(player) then return end

    local dmg = tonumber(damage) or 0
    if dmg <= 0 then
        -- Some events pass 0; still try a tiny general soften is wrong — skip
        return
    end

    local pct = lv * PCT_PER_LEVEL
    local refund = dmg * pct
    if refund <= 0 then return end

    local ok = refundDamage(player, refund)

    local id = playerId(player)
    local t = nowMs()
    local last = lastEncLogMs[id] or 0
    if t - last >= LOG_MS and KnoxSystem.Track and KnoxSystem.Track.isChannelOn("stamina") then
        lastEncLogMs[id] = t
        KnoxSystem.Track.log("stamina", "encumbrance_dmg_refund", {
            reason = "overencumbered_damage",
            enduranceLv = lv,
            damageType = tostring(damageType or ""),
            damage = dmg,
            refund = refund,
            pct = pct,
            ok = ok and 1 or 0,
            note = "Endurance: refund 6%×lv of over-encumbrance damage",
        })
    end
end

function KnoxSystem.Endurance.onGameStart(player)
    if not player then return end
    local id = playerId(player)
    lastEndu[id] = getEndurance(player)
    local data = KnoxSystem.getPlayerData(player)
    if data then
        KnoxSystem.Endurance.clampData(data)
        data._endLiveApplied = KnoxSystem.Endurance.level(player) > 0
    end
end

print("[KnoxSystem] KS_Endurance loaded (stamina ±6%/lv, L10 floor 0.12, over-enc dmg 6%/lv)")
