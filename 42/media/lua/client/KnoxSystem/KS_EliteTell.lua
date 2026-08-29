-- Temporary elite nameplate / tell
-- Uses screen-space Analyze plates when available; chat fallback is SINGLE line only
-- (zombies ChatElement maxLines=1; setMaxChatLines is NOT exposed to Lua).
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.EliteTell = KnoxSystem.EliteTell or {}

local lastPulse = {}
local lastScan = 0
local REFRESH_MS = 2000
local SEE_RANGE = 14

local function nowMs()
    local t = 0
    pcall(function()
        if getTimestampMs then t = getTimestampMs() else t = os.time() * 1000 end
    end)
    return t or 0
end

local function zKey(z)
    local id = nil
    pcall(function()
        if type(z.getOnlineID) == "function" then id = z:getOnlineID() end
    end)
    if id and id ~= -1 then return "id:" .. tostring(id) end
    local ok, s = pcall(function()
        return string.format("%.1f:%.1f:%.0f", z:getX() or 0, z:getY() or 0, z:getZ() or 0)
    end)
    return ok and s or tostring(z)
end

local function labelFor(tier, tierName)
    return string.format("* ELITE T%s %s *", tostring(tier), tostring(tierName or "Elite"))
end

local function applyDescriptorName(zombie, tier, tierName)
    pcall(function()
        local md = zombie:getModData()
        if md then
            md.knoxElite = true
            md.knoxTier = tier
            md.knoxTierName = tierName
        end
    end)
    pcall(function()
        if type(zombie.setCustomName) == "function" then
            -- avoid if not available
        end
    end)
end

--- Single-line chat only — do NOT call setMaxChatLines (not exposed → critical error).
local function pulsePlate(zombie, text)
    if not zombie or not text then return end
    -- Prefer Analyze screen plates (handles elite line in stack)
    if KnoxSystem.Analyze and KnoxSystem.Analyze.hasL1 and KnoxSystem.Analyze.hasL1(getPlayer()) then
        return true
    end
    local r, g, b = 1.0, 0.82, 0.15
    local range = 10.0
    pcall(function()
        if KnoxSystem.Analyze and KnoxSystem.Analyze.eliteChatRange then
            range = KnoxSystem.Analyze.eliteChatRange() or range
        end
    end)
    local ok = false
    pcall(function()
        if type(zombie.addLineChatElement) == "function" then
            local font = UIFont and (UIFont.Medium or UIFont.Small) or nil
            if font then
                zombie:addLineChatElement(text, r, g, b, font, range, "knox_elite")
            else
                zombie:addLineChatElement(text, r, g, b)
            end
            ok = true
        end
    end)
    return ok
end

local function dist2(player, z)
    local d = nil
    pcall(function()
        local dx = (player:getX() or 0) - (z:getX() or 0)
        local dy = (player:getY() or 0) - (z:getY() or 0)
        d = math.sqrt(dx * dx + dy * dy)
    end)
    return d
end

local function foreachNearbyZombie(player, range, fn)
    if not player or not fn then return end
    local cell = nil
    pcall(function() cell = getCell() end)
    if not cell or not cell.getZombieList then return end
    local list = nil
    pcall(function() list = cell:getZombieList() end)
    if not list then return end
    local n = 0
    pcall(function() n = list:size() end)
    for i = 0, math.min(n, 50) - 1 do
        local z = nil
        pcall(function() z = list:get(i) end)
        if z then
            local d = dist2(player, z)
            if d and d <= range then
                pcall(function() fn(z, d) end)
            end
        end
    end
end

local function isElite(z)
    local md = nil
    pcall(function() md = z:getModData() end)
    if not md then return false end
    if md.knoxElite then
        return true, tonumber(md.knoxTier) or 0, md.knoxTierName
    end
    return false
end

function KnoxSystem.EliteTell.onEliteStamped(zombie, tier, tierName)
    if not zombie then return end
    applyDescriptorName(zombie, tier, tierName)
    -- Screen plates pick elite up via Analyze; optional single chat if no Analyze
    if not (KnoxSystem.Analyze and KnoxSystem.Analyze.hasL1 and KnoxSystem.Analyze.hasL1(getPlayer())) then
        pulsePlate(zombie, labelFor(tier, tierName))
    end
    pcall(function()
        if KnoxSystem.TrackLog and KnoxSystem.TrackLog.log then
            KnoxSystem.TrackLog.log("zombie", "elite_tell", {
                action = "stamp_plate",
                tier = tier,
                tierName = tierName,
                analyzeGated = 1,
                label = labelFor(tier, tierName),
            })
        end
    end)
end

function KnoxSystem.EliteTell.onPlayerUpdate(player)
    if not player then return end
    if KnoxSystem.Analyze and type(KnoxSystem.Analyze.hasL1) == "function" then
        local ok, has = pcall(function() return KnoxSystem.Analyze.hasL1(player) end)
        if not ok or not has then return end
        -- Analyze screen stack owns elite text when L1+
        return
    end
    local t = nowMs()
    if lastScan > 0 and (t - lastScan) < 500 then return end
    lastScan = t

    local range = SEE_RANGE
    pcall(function()
        if KnoxSystem.Analyze and KnoxSystem.Analyze.maxSeeDist then
            range = KnoxSystem.Analyze.maxSeeDist() or range
        end
    end)

    foreachNearbyZombie(player, range, function(z, d)
        local elite, tier, tierName = isElite(z)
        if not elite then return end
        if KnoxSystem.Analyze and KnoxSystem.Analyze.canSeeTarget then
            if not KnoxSystem.Analyze.canSeeTarget(player, z) then return end
        end
        applyDescriptorName(z, tier, tierName)
        local key = zKey(z)
        local last = lastPulse[key] or 0
        if last > 0 and (t - last) < REFRESH_MS then return end
        lastPulse[key] = t
        pulsePlate(z, labelFor(tier, tierName))
    end)
end

function KnoxSystem.EliteTell.resetSession()
    lastPulse = {}
    lastScan = 0
end

print("[KnoxSystem] KS_EliteTell loaded (no setMaxChatLines; Analyze owns multi-line)")
