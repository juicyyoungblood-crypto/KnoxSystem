-- Personal Power — hidden effective-Strength ranks (not a Skills-tab icon)
-- Design ≥0.5.127:
--   max 10, 2 SP/level (System tab only)
--   real Strength perk level + XP curve unchanged for display when read via raw API
--   Lua getPerkLevel(Strength) returns real + Power so checks that use perk level see the boost
-- Removed: melee bonus dmg, knockdown, carry MaxWeight, window smash mults
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"

KnoxSystem.Power = KnoxSystem.Power or {}

local POWER_MAX = 10
local _hooked = false
local _rawDepth = 0
local _hookDepth = 0

function KnoxSystem.Power.maxLevel()
    return POWER_MAX
end

function KnoxSystem.Power.level(player)
    local data = KnoxSystem.getPlayerData(player)
    if not data then return 0 end
    local lv = tonumber(data.stat_power) or tonumber(data.stat_strength) or 0
    if lv < 0 then lv = 0 end
    if lv > POWER_MAX then lv = POWER_MAX end
    return lv
end

function KnoxSystem.Power.clampData(data)
    if not data then return end
    -- Prefer full migrate path if still over cap (refund before clamp)
    if (tonumber(data.stat_power) or 0) > 10 and not data._powerOver10Refund_v0128 then
        -- getPlayerData-style refund inline (ModData table already in hand)
        local before = tonumber(data.stat_power) or 0
        local refund = before
        data.skill_points_unspent = (tonumber(data.skill_points_unspent) or 0) + refund
        data.stat_power = 0
        data.stat_strength = 0
        if type(data.sp_cart_stats) == "table" then
            data.sp_cart_stats.Power = nil
            data.sp_cart_stats.Strength = nil
        end
        data._powerOver10Refund_v0128 = true
        print(string.format(
            "[KnoxSystem] Power over-cap refund (clampData): Power %d -> 0, +%d SP",
            before, refund
        ))
    end
    local p = tonumber(data.stat_power) or tonumber(data.stat_strength) or 0
    if p < 0 then p = 0 end
    if p > POWER_MAX then p = POWER_MAX end
    data.stat_power = p
    data.stat_strength = p
end

local function isStrengthPerk(perk)
    if perk == nil then return false end
    if Perks then
        if perk == Perks.Strength or perk == Perks.STRENGTH then return true end
    end
    local ok, name = pcall(function()
        if type(perk.getName) == "function" then return tostring(perk:getName() or "") end
        if type(perk.name) == "string" then return perk.name end
        return tostring(perk)
    end)
    if ok and name then
        local n = string.lower(name)
        if n == "strength" or n:find("strength", 1, true) then return true end
    end
    return false
end

--- Run fn with Strength getPerkLevel returning the REAL perk level (no Power).
--- Never rethrow — UI must stay alive.
function KnoxSystem.Power.withRawPerkLevel(fn)
    if type(fn) ~= "function" then return nil end
    _rawDepth = _rawDepth + 1
    local ok, a, b, c, d = pcall(fn)
    _rawDepth = _rawDepth - 1
    if not ok then
        print("[KnoxSystem] withRawPerkLevel error: " .. tostring(a))
        return nil
    end
    return a, b, c, d
end

function KnoxSystem.Power.getStrengthReal(player)
    if not player then return 0 end
    local lvl = 0
    KnoxSystem.Power.withRawPerkLevel(function()
        pcall(function()
            local p = nil
            if Perks then p = Perks.Strength or Perks.STRENGTH end
            if p == nil and PerkFactory and PerkFactory.Perks then
                p = PerkFactory.Perks.Strength
            end
            if p ~= nil and type(player.getPerkLevel) == "function" then
                lvl = tonumber(player:getPerkLevel(p)) or 0
            end
        end)
    end)
    return lvl
end

function KnoxSystem.Power.getStrengthEffective(player)
    return KnoxSystem.Power.getStrengthReal(player) + KnoxSystem.Power.level(player)
end

--- Deprecated mult API — always 1 (no more outcome multiplier).
function KnoxSystem.Power.mult(_player)
    return 1
end

local function installGetPerkLevelHook(classTT)
    if not classTT or not classTT.__index then return false end
    local idx = classTT.__index
    if type(idx) ~= "table" then return false end
    if idx._knoxPowerGetPerkLevelHooked then return true end
    local old = idx.getPerkLevel
    if type(old) ~= "function" then return false end

    idx.getPerkLevel = function(self, perk, ...)
        if _hookDepth > 0 then
            return old(self, perk, ...)
        end
        _hookDepth = _hookDepth + 1
        local ok, real = pcall(old, self, perk, ...)
        _hookDepth = _hookDepth - 1
        if not ok then error(real) end

        if _rawDepth > 0 then
            return real
        end

        -- Only boost for IsoPlayer characters
        local isP = false
        pcall(function()
            if self and instanceof and instanceof(self, "IsoPlayer") then isP = true end
        end)
        if not isP then return real end

        if isStrengthPerk(perk) then
            local add = KnoxSystem.Power.level(self)
            if add > 0 then
                local r = tonumber(real) or 0
                return r + add
            end
        end
        return real
    end
    idx._knoxPowerGetPerkLevelHooked = true
    return true
end

function KnoxSystem.Power.hookPerkLevel()
    if _hooked then return true end
    local okAny = false
    pcall(function()
        if IsoPlayer and IsoPlayer.class and __classmetatables then
            local mt = __classmetatables[IsoPlayer.class]
            if installGetPerkLevelHook(mt) then okAny = true end
        end
    end)
    pcall(function()
        if IsoGameCharacter and IsoGameCharacter.class and __classmetatables then
            local mt = __classmetatables[IsoGameCharacter.class]
            if installGetPerkLevelHook(mt) then okAny = true end
        end
    end)
    -- Fallback: instance metatable on local player later
    _hooked = okAny
    return okAny
end

function KnoxSystem.Power.ensureInstanceHook(player)
    if not player then return end
    pcall(function()
        local mt = getmetatable(player)
        if mt and mt.__index and type(mt.__index) == "table" then
            installGetPerkLevelHook(mt)
        end
    end)
    -- Also try class tables again (boot order)
    KnoxSystem.Power.hookPerkLevel()
end

function KnoxSystem.Power.onPlayerUpdate(player)
    -- Keep instance hook alive; no carry/melee work
    KnoxSystem.Power.ensureInstanceHook(player)
    local data = KnoxSystem.getPlayerData(player)
    if data then KnoxSystem.Power.clampData(data) end
end

function KnoxSystem.Power.onGameStart(player)
    KnoxSystem.Power.hookPerkLevel()
    KnoxSystem.Power.ensureInstanceHook(player)
    pcall(function() KnoxSystem.Power.hookUiRawDisplay() end)
    -- Clear leftover carry bonus from pre-0.5.127 Power mult implementation
    pcall(function()
        if not player then return end
        local data = KnoxSystem.getPlayerData(player)
        local our = data and tonumber(data._knoxPowerWeightBonus) or 0
        if our and our > 0 and type(player.getMaxWeightBonus) == "function" and type(player.setMaxWeightBonus) == "function" then
            local b = tonumber(player:getMaxWeightBonus()) or 0
            local nb = b - our
            if nb < 0 then nb = 0 end
            player:setMaxWeightBonus(nb)
            data._knoxPowerWeightBonus = 0
        end
    end)
    if player and KnoxSystem.Track and KnoxSystem.Track.isChannelOn("power") then
        local real = KnoxSystem.Power.getStrengthReal(player)
        local pow = KnoxSystem.Power.level(player)
        KnoxSystem.Track.log("power", "perk_hook", {
            reason = "game_start",
            powerLv = pow,
            strengthReal = real,
            strengthEffective = real + pow,
            hooked = _hooked and 1 or 0,
            note = "getPerkLevel(Strength)=real+Power; raw API for UI/SP; no Skills-tab icon",
            liveApplied = (pow > 0) and 1 or 0,
        })
    end
end

-- No-op stubs so old bootstrap calls do not error if a stale require path remains
function KnoxSystem.Power.onMeleeHit(...) end
function KnoxSystem.Power.hookSmashWindow() end
function KnoxSystem.Power.syncCarry(...) end
function KnoxSystem.Power.bonusDamage(...) return 0 end

--- Skills pips: show REAL Strength. Do NOT wrap ISCharacterInfoWindow shell
--- (that killed System tab + blue chrome when combined with other UI patches).
local function wrapUiFn(tbl, methodName)
    if type(tbl) ~= "table" then return false end
    local key = "_knoxPowerRaw_" .. tostring(methodName)
    if tbl[key] then return true end
    local old = tbl[methodName]
    if type(old) ~= "function" then return false end
    tbl[methodName] = function(self, a1, a2, a3, a4, a5, a6, a7, a8)
        if KnoxSystem.Power and KnoxSystem.Power.withRawPerkLevel then
            return KnoxSystem.Power.withRawPerkLevel(function()
                return old(self, a1, a2, a3, a4, a5, a6, a7, a8)
            end)
        end
        return old(self, a1, a2, a3, a4, a5, a6, a7, a8)
    end
    tbl[key] = true
    return true
end

local function wrapUiType(globalName, methods)
    pcall(function()
        pcall(function() require("ISUI/" .. globalName) end)
        pcall(function() require("ISUI/PlayerData/" .. globalName) end)
        local tbl = _G[globalName]
        if type(tbl) ~= "table" then return end
        for _, m in ipairs(methods) do
            wrapUiFn(tbl, m)
        end
    end)
end

function KnoxSystem.Power.hookUiRawDisplay()
    local methods = { "prerender", "render", "update", "renderLevel", "drawLevel" }
    -- Skill widgets only — never the character window shell
    for _, name in ipairs({
        "ISSkillProgressBar",
        "ISCharacterScreen",
        "ISCharacterInfo",
    }) do
        wrapUiType(name, methods)
    end
    return true
end

print("[KnoxSystem] KS_Power loaded (hidden Strength+Power; skill pips raw; no window-shell wrap)")
