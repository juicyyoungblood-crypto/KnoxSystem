-- KnoxSystem sandbox (world creation) options
-- Read SandboxVars.KnoxSystem.* with safe defaults.
-- When adding a NEW tuneable constant in product code: ask the user if it needs a sandbox option.
require "KnoxSystem/KS_ModData"

KnoxSystem.Sandbox = KnoxSystem.Sandbox or {}

local DEFAULTS = {
    PowerDamagePercentPerLevel = 10,              -- 1-100; combat snip = pct/100 per Power lv
    PowerKnockPointsPerLevel = 2,                 -- 0-10; knockChance += this * Power
    EnduranceStaminaPercentPerLevel = 6,          -- 1-20; drain/regen efficiency
    EnduranceEncumbranceDamagePercentPerLevel = 6, -- 0-20; over-enc dmg refund
    SpCostPower = 2,                              -- 1-5
    SpCostEndurance = 2,                          -- 1-5
    PersonalXpPercent = 50,                       -- 10-200; 100 = weight tables as-is
    AllowSprintersIfVanillaOff = true,            -- checkbox
    GoblinChancePerThousand = 2,                  -- 1-10 → chance = n/1000 (default 0.002 = 1/500)
}

local _cache = nil
local _logged = false

local function clamp(n, lo, hi, fallback)
    n = tonumber(n)
    if n == nil then return fallback end
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function readRaw()
    local t = {}
    pcall(function()
        if SandboxVars and SandboxVars.KnoxSystem then
            local s = SandboxVars.KnoxSystem
            for k, def in pairs(DEFAULTS) do
                local v = s[k]
                if v == nil then
                    t[k] = def
                else
                    t[k] = v
                end
            end
            return
        end
    end)
    for k, def in pairs(DEFAULTS) do
        if t[k] == nil then t[k] = def end
    end
    -- Normalize types / ranges
    t.PowerDamagePercentPerLevel = clamp(t.PowerDamagePercentPerLevel, 1, 100, 10)
    t.PowerKnockPointsPerLevel = clamp(t.PowerKnockPointsPerLevel, 0, 10, 2)
    t.EnduranceStaminaPercentPerLevel = clamp(t.EnduranceStaminaPercentPerLevel, 1, 20, 6)
    t.EnduranceEncumbranceDamagePercentPerLevel = clamp(t.EnduranceEncumbranceDamagePercentPerLevel, 0, 20, 6)
    t.SpCostPower = clamp(t.SpCostPower, 1, 5, 2)
    t.SpCostEndurance = clamp(t.SpCostEndurance, 1, 5, 2)
    t.PersonalXpPercent = clamp(t.PersonalXpPercent, 10, 200, 50)
    t.GoblinChancePerThousand = clamp(t.GoblinChancePerThousand, 1, 10, 2)
    if t.AllowSprintersIfVanillaOff == nil then
        t.AllowSprintersIfVanillaOff = true
    else
        t.AllowSprintersIfVanillaOff = t.AllowSprintersIfVanillaOff and true or false
    end
    return t
end

function KnoxSystem.Sandbox.defaults()
    local t = {}
    for k, v in pairs(DEFAULTS) do t[k] = v end
    return t
end

function KnoxSystem.Sandbox.refresh()
    _cache = readRaw()
    if not _logged then
        _logged = true
        print(string.format(
            "[KnoxSystem] Sandbox: PowerDmg%%=%d KnockPts=%d EndStam%%=%d EndEncDmg%%=%d SpPower=%d SpEnd=%d PersXP%%=%d SprintersIfOff=%s GoblinPerK=%d (%.4f)",
            _cache.PowerDamagePercentPerLevel,
            _cache.PowerKnockPointsPerLevel,
            _cache.EnduranceStaminaPercentPerLevel,
            _cache.EnduranceEncumbranceDamagePercentPerLevel,
            _cache.SpCostPower,
            _cache.SpCostEndurance,
            _cache.PersonalXpPercent,
            tostring(_cache.AllowSprintersIfVanillaOff),
            _cache.GoblinChancePerThousand,
            (_cache.GoblinChancePerThousand or 2) / 1000.0
        ))
    end
    return _cache
end

function KnoxSystem.Sandbox.get()
    if not _cache then return KnoxSystem.Sandbox.refresh() end
    return _cache
end

function KnoxSystem.Sandbox.getValue(key)
    local c = KnoxSystem.Sandbox.get()
    if c[key] ~= nil then return c[key] end
    return DEFAULTS[key]
end

-- Typed helpers used by gameplay modules
function KnoxSystem.Sandbox.powerMeleeBonusPerLevel()
    return KnoxSystem.Sandbox.getValue("PowerDamagePercentPerLevel") / 100.0
end

function KnoxSystem.Sandbox.powerKnockPointsPerLevel()
    return KnoxSystem.Sandbox.getValue("PowerKnockPointsPerLevel")
end

function KnoxSystem.Sandbox.enduranceStaminaPctPerLevel()
    return KnoxSystem.Sandbox.getValue("EnduranceStaminaPercentPerLevel") / 100.0
end

function KnoxSystem.Sandbox.enduranceEncumbranceDmgPctPerLevel()
    return KnoxSystem.Sandbox.getValue("EnduranceEncumbranceDamagePercentPerLevel") / 100.0
end

function KnoxSystem.Sandbox.spCostPower()
    return KnoxSystem.Sandbox.getValue("SpCostPower")
end

function KnoxSystem.Sandbox.spCostEndurance()
    return KnoxSystem.Sandbox.getValue("SpCostEndurance")
end

function KnoxSystem.Sandbox.personalXpScale()
    return KnoxSystem.Sandbox.getValue("PersonalXpPercent") / 100.0
end

function KnoxSystem.Sandbox.allowSprintersIfVanillaOff()
    return KnoxSystem.Sandbox.getValue("AllowSprintersIfVanillaOff") and true or false
end

--- Goblin spawn chance as 0..1 (sandbox per-thousand / 1000). Sole source of rate.
function KnoxSystem.Sandbox.goblinChance()
    local n = KnoxSystem.Sandbox.getValue("GoblinChancePerThousand") or 2
    n = tonumber(n) or 2
    if n < 1 then n = 1 end
    if n > 10 then n = 10 end
    return n / 1000.0
end

function KnoxSystem.Sandbox.goblinChancePerThousand()
    local n = KnoxSystem.Sandbox.getValue("GoblinChancePerThousand") or 2
    n = tonumber(n) or 2
    if n < 1 then n = 1 end
    if n > 10 then n = 10 end
    return n
end

--- Vanilla lore speed allows sprinters? (Speed enum varies; soft detect)
function KnoxSystem.Sandbox.vanillaSprintersEnabled()
    local ok = true
    pcall(function()
        if not SandboxVars then return end
        local zl = SandboxVars.ZombieLore
        if type(zl) ~= "table" then return end
        -- Common: Speed 1 = Sprinters, or string contains Sprint
        local sp = zl.Speed
        if type(sp) == "number" then
            -- 1 often sprinters; 2 fast; 3 shambler — allow if 1 or random that includes sprint
            -- Also some builds: 1=random including sprinters
            ok = (sp <= 2) -- conservative: shamblers-only (3+) => no vanilla sprinters
            if sp == 1 then ok = true end
        elseif type(sp) == "string" then
            local low = string.lower(sp)
            ok = low:find("sprint", 1, true) ~= nil or low:find("random", 1, true) ~= nil
        end
    end)
    return ok
end

--- Whether Knox stamp may apply sprinter walk types this save
function KnoxSystem.Sandbox.knoxMayStampSprinters()
    if KnoxSystem.Sandbox.vanillaSprintersEnabled() then return true end
    return KnoxSystem.Sandbox.allowSprintersIfVanillaOff()
end

-- Refresh when sandbox is applied / game starts
if Events then
    if Events.OnGameBoot then
        Events.OnGameBoot.Add(function()
            pcall(function() KnoxSystem.Sandbox.refresh() end)
        end)
    end
    if Events.OnGameStart then
        Events.OnGameStart.Add(function()
            pcall(function() KnoxSystem.Sandbox.refresh() end)
        end)
    end
    if Events.OnInitGlobalModData then
        Events.OnInitGlobalModData.Add(function()
            pcall(function() KnoxSystem.Sandbox.refresh() end)
        end)
    end
end

print("[KnoxSystem] KS_Sandbox loaded (world options + defaults)")
