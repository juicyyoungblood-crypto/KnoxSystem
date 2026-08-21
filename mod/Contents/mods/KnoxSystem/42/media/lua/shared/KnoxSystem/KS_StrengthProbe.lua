-- Strength-application probe (logging only for actions — does NOT wrap timed-action constructors).
-- Channel: strength_apply
-- Climb: detect via isClimbing / bClimbing (B42 wall climb is Java ClimbWall, not ISClimbOverFence).
-- Never patch IS* :new — that broke Space-to-climb (0.5.134).
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_Power"

KnoxSystem.StrengthProbe = KnoxSystem.StrengthProbe or {}

local lastLog = {}
local THROTTLE_MS = {
    melee_hit = 200,
    shove = 250,
    fence_climb = 500,
    climb_wall = 500,
    vault = 400,
    door_hit = 200,
    thump = 300,
    window_hit = 300,
    tree_hit = 400,
    muscle_strain = 2000,
    perk_read = 12000,
    carry = 4000,
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
    local real, pow = -1, 0
    pcall(function()
        if KnoxSystem.Power then
            if KnoxSystem.Power.level then pow = tonumber(KnoxSystem.Power.level(player)) or 0 end
            if KnoxSystem.Power.getStrengthReal then real = tonumber(KnoxSystem.Power.getStrengthReal(player)) or -1 end
        end
        if real < 0 then
            local p = Perks and (Perks.Strength or Perks.STRENGTH)
            if p and player and player.getPerkLevel then
                real = tonumber(player:getPerkLevel(p)) or -1
            end
        end
    end)
    return {
        strengthReal = real,
        powerLv = pow,
        carryBonus = pow * 1.0,
        meleeBonusOn = (pow >= 1) and 1 or 0,
        noteDesign = "Power=carry+1/lv; dmg 10%*Power; knock reroll +13 stagger",
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

-- -------- Climb detection (no TimedAction patches) --------
local wasClimbing = false
local climbStartMs = 0

local function readClimbing(player)
    local climbing = false
    pcall(function()
        if player.isClimbing and player:isClimbing() then climbing = true end
    end)
    if not climbing then
        pcall(function()
            if player.getVariableBoolean and player:getVariableBoolean("bClimbing") then climbing = true end
        end)
    end
    if not climbing then
        pcall(function()
            if player.getVariable and tostring(player:getVariable("bClimbing") or "") == "true" then climbing = true end
        end)
    end
    -- hop / vault animation flags
    local hop = false
    pcall(function()
        if player.isSneaking then end
        if player.getVariableBoolean and player:getVariableBoolean("bClimbFence") then hop = true end
        if player.getVariableBoolean and player:getVariableBoolean("ClimbFence") then hop = true end
    end)
    return climbing, hop
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
            if name == "?" or name == "" or name == "nil" then
                if thumpable.getSprite and thumpable:getSprite() and thumpable:getSprite().getName then
                    name = tostring(thumpable:getSprite():getName() or name)
                end
            end
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

    -- Climb / hop without TimedAction hooks
    local climbing, hop = readClimbing(player)
    if (climbing or hop) and not wasClimbing then
        wasClimbing = true
        climbStartMs = nowMs()
        logApply(player, hop and "vault" or "climb_wall", {
            phase = "start",
            note = hop and "hop/vault flag" or "isClimbing/bClimbing (B42 ClimbWall path)",
        })
    elseif (climbing or hop) and wasClimbing then
        -- mid-climb heartbeat (throttled via reason key)
        if throttleOk("climb_wall") then
            logApply(player, hop and "vault" or "climb_wall", {
                phase = "active",
                climbMs = nowMs() - (climbStartMs or nowMs()),
            })
        end
    elseif wasClimbing and not climbing and not hop then
        wasClimbing = false
        logApply(player, "climb_wall_done", {
            phase = "done",
            climbMs = nowMs() - (climbStartMs or nowMs()),
        })
    end

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
                desc = "Strength on actions: melee/shove/climb/door/strain; real vs effective",
            })
        end
        if KnoxSystem.Config and KnoxSystem.Config.TrackLog and type(KnoxSystem.Config.TrackLog.channels) == "table" then
            if KnoxSystem.Config.TrackLog.channels.strength_apply == nil then
                KnoxSystem.Config.TrackLog.channels.strength_apply = true
            end
            KnoxSystem.Config.TrackLog.channels.zombie = false
        end
    end)
    -- Explicitly do NOT hook TimedActions — Space climb must stay vanilla
    print("[KnoxSystem] KS_StrengthProbe loaded (no TimedAction wraps; climb via isClimbing; carry via Power)")
end

print("[KnoxSystem] KS_StrengthProbe file loaded")
