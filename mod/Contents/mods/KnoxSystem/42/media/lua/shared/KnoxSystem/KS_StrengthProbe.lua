-- Strength-application probe (logging only — does NOT touch character UI).
-- Channel: strength_apply
-- Events: melee attack, shove, fence/climb timed actions, door/thump, muscle strain sample.
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Power"

KnoxSystem.StrengthProbe = KnoxSystem.StrengthProbe or {}

local lastLog = {}
local THROTTLE_MS = {
    melee_hit = 200,
    shove = 250,
    fence_climb = 400,
    vault = 400,
    door_hit = 200,
    thump = 300,
    window_hit = 300,
    tree_hit = 400,
    muscle_strain = 2000,
    perk_read = 12000,
    default = 500,
}

local function nowMs()
    if getTimestampMs then
        local ok, t = pcall(getTimestampMs)
        if ok and type(t) == "number" then return t end
    end
    return (os and os.time and (os.time() * 1000)) or 0
end

local function throttleOk(reason)
    local key = tostring(reason or "default")
    local wait = THROTTLE_MS[key] or THROTTLE_MS.default
    local ms = nowMs()
    local prev = lastLog[key] or 0
    if (ms - prev) < wait then return false end
    lastLog[key] = ms
    return true
end

local function isLocalPlayer(obj)
    if not obj then return false end
    local ok = false
    pcall(function()
        if instanceof and instanceof(obj, "IsoPlayer") then ok = true end
    end)
    if not ok then return false end
    pcall(function()
        if obj.isLocalPlayer and not obj:isLocalPlayer() then ok = false end
    end)
    return ok
end

local function strSnap(player)
    local real, eff, pow, hooked = -1, -1, 0, -1
    pcall(function()
        if KnoxSystem.Power then
            if KnoxSystem.Power.level then pow = tonumber(KnoxSystem.Power.level(player)) or 0 end
            if KnoxSystem.Power.getStrengthReal then real = tonumber(KnoxSystem.Power.getStrengthReal(player)) or -1 end
            if KnoxSystem.Power.getStrengthEffective then
                eff = tonumber(KnoxSystem.Power.getStrengthEffective(player)) or -1
            elseif real >= 0 then
                eff = real + pow
            end
        end
        local p = Perks and (Perks.Strength or Perks.STRENGTH)
        if p and player and player.getPerkLevel then
            hooked = tonumber(player:getPerkLevel(p)) or -1
        end
    end)
    return {
        strengthReal = real,
        strengthEffective = eff,
        strengthGetPerkLevel = hooked,
        powerLv = pow,
        over10 = (type(eff) == "number" and eff > 10) and 1 or 0,
        boostGap = (type(eff) == "number" and type(real) == "number") and (eff - real) or -1,
    }
end

local function logApply(player, reason, extra)
    if not player then return end
    if not KnoxSystem.Track or not KnoxSystem.Track.isChannelOn then return end
    if not KnoxSystem.Track.isChannelOn("strength_apply") then return end
    if not throttleOk(reason) then return end
    local fields = strSnap(player)
    fields.reason = tostring(reason or "?")
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            if fields[k] == nil then fields[k] = v end
        end
    end
    pcall(function()
        KnoxSystem.Track.log("strength_apply", tostring(reason or "apply"), fields)
    end)
end

function KnoxSystem.StrengthProbe.log(player, reason, extra)
    logApply(player, reason, extra)
end

-- -------- Muscle strain --------
local lastStrainTotal = 0
local function sampleMuscleStrain(player)
    local total, n = 0, 0
    local bits = {}
    pcall(function()
        local bd = player.getBodyDamage and player:getBodyDamage()
        if not bd or not bd.getBodyParts then return end
        local list = bd:getBodyParts()
        if not list or not list.size then return end
        local size = list:size() or 0
        for i = 0, size - 1 do
            local bp = list:get(i)
            if bp then
                local strain = nil
                pcall(function() if bp.getMuscleStrain then strain = bp:getMuscleStrain() end end)
                if strain == nil then
                    pcall(function() if bp.getStiffness then strain = bp:getStiffness() end end)
                end
                strain = tonumber(strain)
                if strain and strain > 0.001 then
                    local name = "?"
                    pcall(function() if bp.getType then name = tostring(bp:getType()) end end)
                    bits[#bits + 1] = string.format("%s=%.3f", name, strain)
                    total = total + strain
                    n = n + 1
                end
            end
        end
    end)
    return total, n, table.concat(bits, ",")
end

-- -------- Timed actions (fence / climb / vault) --------
local function lowerName(o, className)
    local n = string.lower(tostring(className or ""))
    pcall(function()
        if o and o.Type then n = n .. " " .. string.lower(tostring(o.Type)) end
    end)
    return n
end

local function classifyAction(name)
    name = string.lower(tostring(name or ""))
    if name:find("climb", 1, true) then return "fence_climb" end
    if name:find("vault", 1, true) or name:find("hop", 1, true) then return "vault" end
    if name:find("shove", 1, true) then return "shove" end
    if name:find("force", 1, true) and name:find("door", 1, true) then return "door_force" end
    if name:find("barricade", 1, true) then return "barricade" end
    if name:find("destroy", 1, true) or name:find("thump", 1, true) then return "thump_action" end
    return nil
end

local function hookTimedAction(globalName)
    pcall(function()
        pcall(function() require("TimedActions/" .. globalName) end)
        local cls = _G[globalName]
        if type(cls) ~= "table" or cls._knoxStrProbe133 then return end
        cls._knoxStrProbe133 = true

        if type(cls.new) == "function" then
            local oldNew = cls.new
            cls.new = function(self, character, a, b, c, d, e, f)
                local o = oldNew(self, character, a, b, c, d, e, f)
                pcall(function()
                    local ch = character
                    if o and o.character then ch = o.character end
                    if not isLocalPlayer(ch) then return end
                    local nm = lowerName(o, globalName)
                    local kind = classifyAction(nm) or classifyAction(globalName)
                    if kind then
                        logApply(ch, kind, {
                            actionClass = globalName,
                            actionName = nm,
                            maxTime = (o and o.maxTime) or -1,
                            phase = "start",
                        })
                    end
                end)
                return o
            end
        end

        if type(cls.perform) == "function" then
            local oldPerform = cls.perform
            cls.perform = function(self, a, b, c, d, e, f)
                pcall(function()
                    local ch = self and self.character
                    if not isLocalPlayer(ch) then return end
                    local nm = lowerName(self, globalName)
                    local kind = classifyAction(nm) or classifyAction(globalName)
                    if kind then
                        logApply(ch, kind .. "_done", {
                            actionClass = globalName,
                            actionName = nm,
                            phase = "done",
                        })
                    end
                end)
                return oldPerform(self, a, b, c, d, e, f)
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
    }
    for i = 1, #names do
        hookTimedAction(names[i])
    end
end

-- -------- Combat / world hits --------
function KnoxSystem.StrengthProbe.onWeaponHitCharacter(attacker, target, weapon, damage)
    if not isLocalPlayer(attacker) then return end
    local wname = ""
    pcall(function()
        if weapon then
            if weapon.getFullType then wname = tostring(weapon:getFullType() or "") end
            if (wname == "" or wname == "nil") and weapon.getName then wname = tostring(weapon:getName() or "") end
        end
    end)
    local wl = string.lower(wname)
    local isZed = false
    pcall(function()
        if target and instanceof and instanceof(target, "IsoZombie") then isZed = true end
    end)
    if not isZed then return end

    local bare = (wl == "" or wl:find("barehands", 1, true) or wl:find("hand", 1, true))
    local kd = -1
    pcall(function()
        if target and target.isKnockedDown then kd = target:isKnockedDown() and 1 or 0 end
    end)

    if bare then
        logApply(attacker, "shove", {
            weapon = wname,
            damage = tonumber(damage) or -1,
            targetKnockedDown = kd,
        })
    else
        logApply(attacker, "melee_hit", {
            weapon = wname,
            damage = tonumber(damage) or -1,
            targetKnockedDown = kd,
        })
    end
end

function KnoxSystem.StrengthProbe.onWeaponHitThumpable(attacker, weapon, thumpable)
    if not isLocalPlayer(attacker) then return end
    local name, hp, maxHp, doorDmg = "?", -1, -1, -1
    pcall(function()
        if thumpable then
            if thumpable.getName then name = tostring(thumpable:getName() or name) end
            if thumpable.getThumpCondition then hp = tonumber(thumpable:getThumpCondition()) or hp end
            if thumpable.getHealth then hp = tonumber(thumpable:getHealth()) or hp end
            if thumpable.getMaxHealth then maxHp = tonumber(thumpable:getMaxHealth()) or maxHp end
        end
        if weapon and weapon.getDoorDamage then
            doorDmg = tonumber(weapon:getDoorDamage()) or -1
        end
    end)
    local nl = string.lower(tostring(name))
    local kind = "thump"
    if nl:find("door", 1, true) or nl:find("gate", 1, true) then kind = "door_hit"
    elseif nl:find("window", 1, true) then kind = "window_hit"
    elseif nl:find("fence", 1, true) then kind = "fence_hit"
    end
    local wname = "?"
    pcall(function()
        if weapon and weapon.getName then wname = tostring(weapon:getName()) end
    end)
    logApply(attacker, kind, {
        object = name,
        objectHp = hp,
        objectMaxHp = maxHp,
        weaponDoorDamage = doorDmg,
        weapon = wname,
    })
end

function KnoxSystem.StrengthProbe.onWeaponHitTree(attacker, weapon)
    if not isLocalPlayer(attacker) then return end
    local wname = "?"
    pcall(function()
        if weapon and weapon.getName then wname = tostring(weapon:getName()) end
    end)
    logApply(attacker, "tree_hit", { weapon = wname })
end

local tick = 0
function KnoxSystem.StrengthProbe.onPlayerUpdate(player)
    if not isLocalPlayer(player) then return end
    tick = tick + 1
    if tick % 45 == 0 then
        local total, n, detail = sampleMuscleStrain(player)
        if total > lastStrainTotal + 0.02 and total > 0.001 then
            logApply(player, "muscle_strain", {
                strainTotal = total,
                strainParts = n,
                strainDetail = detail,
                strainDelta = total - lastStrainTotal,
            })
        end
        lastStrainTotal = total
    end
    if tick % 360 == 0 then
        logApply(player, "perk_read", { note = "periodic Strength snapshot" })
    end
end

function KnoxSystem.StrengthProbe.boot()
    pcall(function()
        if KnoxSystem.Track and KnoxSystem.Track.register then
            KnoxSystem.Track.register("strength_apply", {
                enabled = true,
                desc = "Strength on actions: melee/shove/fence/door/strain; real vs effective",
            })
        end
        if KnoxSystem.Config and KnoxSystem.Config.TrackLog and type(KnoxSystem.Config.TrackLog.channels) == "table" then
            if KnoxSystem.Config.TrackLog.channels.strength_apply == nil then
                KnoxSystem.Config.TrackLog.channels.strength_apply = true
            end
            -- keep zombie spam off
            KnoxSystem.Config.TrackLog.channels.zombie = false
        end
        KnoxSystem.StrengthProbe.hookTimedActions()
    end)
    print("[KnoxSystem] KS_StrengthProbe loaded (strength_apply only; no UI hooks)")
end

print("[KnoxSystem] KS_StrengthProbe file loaded")
