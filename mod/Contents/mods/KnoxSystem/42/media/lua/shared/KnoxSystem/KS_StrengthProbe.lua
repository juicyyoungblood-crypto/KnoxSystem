-- Strength application probes — log when Strength is consulted for real gameplay.
-- Complements Power hook: each event dumps strengthReal / strengthEffective / powerLv.
-- Channel: "strength_apply" (and power for continuity).
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Power"

KnoxSystem.StrengthProbe = KnoxSystem.StrengthProbe or {}

local lastLog = {} -- reason -> ms
local THROTTLE = {
    fence_climb = 400,
    vault = 400,
    shove = 250,
    door_hit = 200,
    thump = 300,
    muscle_strain = 1500,
    perk_read = 8000,
    timed_action = 500,
    default = 600,
}

local function nowMs()
    if getTimestampMs then
        local ok, t = pcall(getTimestampMs)
        if ok and t then return t end
    end
    return (os and os.time and os.time() * 1000) or 0
end

local function throttleOk(reason)
    local ms = nowMs()
    local key = tostring(reason or "default")
    local wait = THROTTLE[key] or THROTTLE.default
    local prev = lastLog[key] or 0
    if ms - prev < wait then return false end
    lastLog[key] = ms
    return true
end

local function strSnap(player)
    local real, eff, pow = -1, -1, 0
    if KnoxSystem.Power then
        if KnoxSystem.Power.level then pow = KnoxSystem.Power.level(player) or 0 end
        if KnoxSystem.Power.getStrengthReal then real = KnoxSystem.Power.getStrengthReal(player) or -1 end
        if KnoxSystem.Power.getStrengthEffective then
            eff = KnoxSystem.Power.getStrengthEffective(player) or -1
        else
            eff = (real >= 0 and pow) and (real + pow) or -1
        end
    end
    -- Direct getPerkLevel (boosted if hook works)
    local hooked = -1
    pcall(function()
        local p = Perks and (Perks.Strength or Perks.STRENGTH)
        if p and player and player.getPerkLevel then
            hooked = tonumber(player:getPerkLevel(p)) or -1
        end
    end)
    return {
        strengthReal = real,
        strengthEffective = eff,
        strengthGetPerkLevel = hooked, -- should match effective when hook live
        powerLv = pow,
        over10 = (eff > 10) and 1 or 0,
    }
end

local function logApply(player, reason, extra)
    if not player then return end
    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn("strength_apply") then return end
    if not throttleOk(reason) then return end
    local fields = strSnap(player)
    if type(extra) == "table" then
        for k, v in pairs(extra) do fields[k] = v end
    end
    fields.reason = tostring(reason or "?")
    KnoxSystem.Track.log("strength_apply", tostring(reason or "apply"), fields)
end

function KnoxSystem.StrengthProbe.log(player, reason, extra)
    logApply(player, reason, extra)
end

-- -------- Muscle strain sampling --------
local lastStrain = {}
local function sampleMuscleStrain(player)
    local parts = {}
    local total = 0
    local n = 0
    pcall(function()
        local bd = player.getBodyDamage and player:getBodyDamage()
        if not bd then return end
        local list = bd.getBodyParts and bd:getBodyParts()
        if list then
            local size = list.size and list:size() or 0
            for i = 0, size - 1 do
                local bp = list.get and list:get(i)
                if bp then
                    local strain = nil
                    pcall(function()
                        if bp.getMuscleStrain then strain = bp:getMuscleStrain() end
                    end)
                    if strain == nil then
                        pcall(function()
                            if bp.getStiffness then strain = bp:getStiffness() end
                        end)
                    end
                    strain = tonumber(strain)
                    if strain and strain > 0.001 then
                        local name = "?"
                        pcall(function()
                            if bp.getType then name = tostring(bp:getType()) end
                        end)
                        parts[#parts + 1] = string.format("%s=%.3f", name, strain)
                        total = total + strain
                        n = n + 1
                    end
                end
            end
        end
    end)
    return total, n, table.concat(parts, ",")
end

-- -------- Timed action hooks (fence / climb / vault) --------
local function actionName(o)
    if not o then return "" end
    local n = ""
    pcall(function()
        if o.Type then n = tostring(o.Type) end
        if n == "" and o.type then n = tostring(o.type) end
    end)
    if n == "" then
        pcall(function() n = tostring(o) end)
    end
    return string.lower(n or "")
end

local function classifyAction(name)
    if name:find("climb", 1, true) and (name:find("fence", 1, true) or name:find("sheet", 1, true) or name:find("rope", 1, true) or name:find("down", 1, true) or name:find("wall", 1, true)) then
        return "fence_climb"
    end
    if name:find("climb", 1, true) then return "fence_climb" end
    if name:find("vault", 1, true) or name:find("hop", 1, true) then return "vault" end
    if name:find("shove", 1, true) or name:find("push", 1, true) then return "shove" end
    if name:find("open.*door", 1) or name:find("forcedoor", 1, true) or name:find("force_door", 1, true) then return "door_force" end
    if name:find("barricade", 1, true) then return "barricade" end
    if name:find("destroy", 1, true) or name:find("thump", 1, true) then return "thump_action" end
    return nil
end

local function hookTimedAction(globalName)
    pcall(function()
        pcall(function() require("TimedActions/" .. globalName) end)
        local cls = _G[globalName]
        if type(cls) ~= "table" or cls._knoxStrProbe then return end
        cls._knoxStrProbe = true
        local oldNew = cls.new
        if type(oldNew) == "function" then
            cls.new = function(self, character, ...)
                local o = oldNew(self, character, ...)
                pcall(function()
                    local ch = character
                    if o and o.character then ch = o.character end
                    local nm = actionName(o) .. " " .. string.lower(globalName)
                    local kind = classifyAction(nm) or classifyAction(string.lower(globalName))
                    if kind and ch then
                        logApply(ch, kind, {
                            actionClass = globalName,
                            actionName = nm,
                            maxTime = o and o.maxTime or -1,
                        })
                    end
                end)
                return o
            end
        end
        local oldPerform = cls.perform
        if type(oldPerform) == "function" then
            cls.perform = function(self, ...)
                pcall(function()
                    local ch = self and self.character
                    local nm = actionName(self) .. " " .. string.lower(globalName)
                    local kind = classifyAction(nm) or classifyAction(string.lower(globalName))
                    if kind and ch then
                        logApply(ch, kind .. "_done", {
                            actionClass = globalName,
                            actionName = nm,
                        })
                    end
                end)
                return oldPerform(self, ...)
            end
        end
    end)
end

function KnoxSystem.StrengthProbe.hookTimedActions()
    local names = {
        "ISClimbOverFence",
        "ISClimbSheetRopeAction",
        "ISClimbDownSheetRopeAction",
        "ISClimbThroughWindow",
        "ISVaultFence",
        "ISHopFenceAction",
        "ISClimbOverWall",
        "ISOpenCloseDoor",
        "ISForceDoor",
        "ISDestroyStuffAction",
        "ISSmashWindow",
        "ISRemoveBarricade",
        "ISBarricadeAction",
        "ISShoveAction",
        "ISPushAction",
    }
    for _, n in ipairs(names) do
        hookTimedAction(n)
    end
end

-- -------- Shove / weapon hit world (doors) --------
function KnoxSystem.StrengthProbe.onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker then return end
    local isPlayer = false
    pcall(function()
        if instanceof and instanceof(attacker, "IsoPlayer") then isPlayer = true end
    end)
    if not isPlayer then return end

    -- Shove / unarmed push often uses BareHands or isRanged false with shove
    local wname = ""
    pcall(function()
        if weapon then
            if weapon.getName then wname = tostring(weapon:getName() or "") end
            if wname == "" and weapon.getFullType then wname = tostring(weapon:getFullType() or "") end
        end
    end)
    local wl = string.lower(wname)
    local isZed = false
    pcall(function()
        if target and instanceof and instanceof(target, "IsoZombie") then isZed = true end
    end)
    if isZed and (wl:find("barehands", 1, true) or wl == "" or wl:find("hand", 1, true)) then
        local kd = -1
        pcall(function()
            if target.isKnockedDown then kd = target:isKnockedDown() and 1 or 0 end
        end)
        logApply(attacker, "shove", {
            weapon = wname,
            damage = tonumber(damage) or -1,
            targetKnockedDown = kd,
            target = "zombie",
        })
    end
end

function KnoxSystem.StrengthProbe.onWeaponHitThumpable(attacker, weapon, thumpable, ...)
    if not attacker then return end
    local isPlayer = false
    pcall(function()
        if instanceof and instanceof(attacker, "IsoPlayer") then isPlayer = true end
    end)
    if not isPlayer then return end

    local name, hp, maxHp, doorDmg = "?", -1, -1, -1
    pcall(function()
        if thumpable then
            if thumpable.getName then name = tostring(thumpable:getName() or name) end
            if thumpable.getThumpCondition then hp = tonumber(thumpable:getThumpCondition()) or hp end
            if thumpable.getHealth then hp = tonumber(thumpable:getHealth()) or hp end
            if thumpable.getMaxHealth then maxHp = tonumber(thumpable:getMaxHealth()) or maxHp end
            if thumpable.getModData then
                local md = thumpable:getModData()
            end
        end
        if weapon and weapon.getDoorDamage then
            doorDmg = tonumber(weapon:getDoorDamage()) or -1
        end
    end)
    local nl = string.lower(tostring(name))
    local kind = "thump"
    if nl:find("door", 1, true) then kind = "door_hit"
    elseif nl:find("gate", 1, true) then kind = "door_hit"
    elseif nl:find("window", 1, true) then kind = "window_hit"
    elseif nl:find("fence", 1, true) then kind = "fence_hit"
    end
    logApply(attacker, kind, {
        object = name,
        objectHp = hp,
        objectMaxHp = maxHp,
        weaponDoorDamage = doorDmg,
        weapon = (function()
            local w = "?"
            pcall(function()
                if weapon and weapon.getName then w = tostring(weapon:getName()) end
            end)
            return w
        end)(),
    })
end

function KnoxSystem.StrengthProbe.onWeaponHitTree(attacker, weapon, ...)
    if not attacker then return end
    pcall(function()
        if instanceof and instanceof(attacker, "IsoPlayer") then
            logApply(attacker, "tree_hit", {
                weapon = weapon and (weapon.getName and weapon:getName()) or "?",
            })
        end
    end)
end

-- -------- Player update: muscle strain deltas + rare perk snapshot --------
local strainAcc = 0
function KnoxSystem.StrengthProbe.onPlayerUpdate(player)
    if not player then return end
    strainAcc = strainAcc + 1
    if strainAcc % 40 == 0 then -- ~ periodically
        local total, n, detail = sampleMuscleStrain(player)
        local prev = lastStrain.total or 0
        if total > prev + 0.02 or (n > 0 and throttleOk("muscle_strain")) then
            if total > 0.001 then
                logApply(player, "muscle_strain", {
                    strainTotal = total,
                    strainParts = n,
                    strainDetail = detail,
                    strainDelta = total - prev,
                })
            end
        end
        lastStrain.total = total
    end
    if strainAcc % 300 == 0 then
        logApply(player, "perk_read", { note = "periodic Strength read while playing" })
    end
end

function KnoxSystem.StrengthProbe.boot()
    if KnoxSystem.Track and KnoxSystem.Track.register then
        KnoxSystem.Track.register("strength_apply", {
            enabled = true,
            desc = "Strength applications: fence/vault, muscle strain, shove, door/thump; real vs effective",
        })
        -- Hard-off zombie noise for this verification pass
        KnoxSystem.Track.register("zombie", {
            enabled = false,
            desc = "OFF: zombie stamp/observe (suppressed for Strength probe pass)",
        })
    end
    KnoxSystem.StrengthProbe.hookTimedActions()
    print("[KnoxSystem] KS_StrengthProbe loaded (channel strength_apply; zombie Track OFF)")
end

print("[KnoxSystem] KS_StrengthProbe file loaded")
