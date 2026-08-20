-- Phase 4 client: class modal + Warrior hooks + Charge key
require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"
require "KnoxSystem/KS_Level"
require "KnoxSystem/KS_PersonalXP"
require "KnoxSystem/KS_WorldRank"
require "KnoxSystem/KS_SP"
require "KnoxSystem/KS_SystemSkills"
require "KnoxSystem/KS_BaseSkills"
require "KnoxSystem/KS_Stats"
require "KnoxSystem/KS_Power"
require "KnoxSystem/KS_Resilience"
require "KnoxSystem/KS_DStorage"
require "KnoxSystem/KS_Class"
require "KnoxSystem/KS_Warrior_Melee"
require "KnoxSystem/KS_Warrior_Armored"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_ZombieObserve"
require "KnoxSystem/KS_WorldZombies"
require "KnoxSystem/KS_Analyze"
require "KnoxSystem/KS_AnalyzeOverlay"
require "KnoxSystem/KS_EliteTell"
require "KnoxSystem/KS_UI_SystemTab"
require "KnoxSystem/KS_UI_InventoryTheme"
require "KnoxSystem/KS_UI_ClassModal"
require "KnoxSystem/KS_Warrior_Charge"
require "KnoxSystem/KS_ItemListFix"

local KEY_SYSTEM = Keyboard.KEY_O
local KEY_CHARGE = Keyboard.KEY_G

local lastPL = {}

local function onKeyPressed(key)
    if not key or getPlayer() == nil then return end
    if key == KEY_SYSTEM then
        KnoxSystem.UI.focusSystemTab()
    elseif key == KEY_CHARGE then
        local p = getPlayer()
        if p and KnoxSystem.Warrior and KnoxSystem.Warrior.Charge then
            KnoxSystem.Warrior.Charge.activate(p)
        end
    end
end

local function onGameStart()
    print(string.format("[KnoxSystem] client game start v%s (Phase 4.1 System class Confirm)", KnoxSystem.VERSION))
    if KnoxSystem.Track and KnoxSystem.Track.clear then
        KnoxSystem.Track.clear()
    end
    if KnoxSystem.Resilience and KnoxSystem.Resilience.resetSession then
        KnoxSystem.Resilience.resetSession()
    end
    if KnoxSystem.ZombieObserve and KnoxSystem.ZombieObserve.resetSession then
        KnoxSystem.ZombieObserve.resetSession()
    end
    if KnoxSystem.EliteTell and KnoxSystem.EliteTell.resetSession then
        KnoxSystem.EliteTell.resetSession()
    end
    if KnoxSystem.Analyze and KnoxSystem.Analyze.onGameStart then
        KnoxSystem.Analyze.onGameStart()
    end
    if KnoxSystem.Analyze and KnoxSystem.Analyze.ensureOverlay then
        KnoxSystem.Analyze.ensureOverlay()
    end
    do
        local ok, err = pcall(function()
            if KnoxSystem.DStorage and KnoxSystem.DStorage.probeScripts then
                KnoxSystem.DStorage.probeScripts()
            end
            local p = getPlayer()
            if p and KnoxSystem.DStorage and KnoxSystem.DStorage.sync then
                KnoxSystem.DStorage.sync(p, KnoxSystem.getPlayerData(p))
            end
            if KnoxSystem.DStorage and KnoxSystem.DStorage.patchWearActions then
                KnoxSystem.DStorage.patchWearActions()
            end
        end)
        if not ok then
            print("[KnoxSystem] DStorage boot ERROR: " .. tostring(err))
        end
    end
    if KnoxSystem.UI._patchCharacterInfo then
        KnoxSystem.UI._patchCharacterInfo()
    end
    if KnoxSystem.UI._patchInventoryTheme then
        KnoxSystem.UI._patchInventoryTheme()
    end
    local player = getPlayer()
    if player then
        KnoxSystem.ensurePlayerInitialized(player, "new_game")
        KnoxSystem.Stats.applyAll(player, KnoxSystem.getPlayerData(player))
        KnoxSystem.Level.debugDump(player)
        if KnoxSystem.Track and KnoxSystem.Track.status then
            KnoxSystem.Track.status()
        end
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Armored and KnoxSystem.Warrior.Armored.syncProtection then
            KnoxSystem.Warrior.Armored.syncProtection(player, "game_start")
        end
        if KnoxSystem.Stats then
            if KnoxSystem.Stats.logPower then
                KnoxSystem.Stats.logPower(player, "game_start")
            elseif KnoxSystem.Stats.logStrength then
                KnoxSystem.Stats.logStrength(player, "game_start")
            end
            if KnoxSystem.Stats.logStamina then KnoxSystem.Stats.logStamina(player, "game_start") end
        end
        if KnoxSystem.Power and KnoxSystem.Power.onGameStart then
            pcall(function() KnoxSystem.Power.onGameStart(player) end)
        end
        local d = KnoxSystem.getPlayerData(player)
        lastPL[0] = d and d.personal_level or 0
        -- Class pick is on System tab (Confirm) — no modal popup
        if KnoxSystem.Class.shouldOfferModal(player) then
            print("[KnoxSystem] PL10+ without class — open System tab and Confirm a class")
        end
    end
end

local function onCreatePlayer(_, player)
    if not player then return end
    KnoxSystem.ensurePlayerInitialized(player, "new_game")
end

local function onPlayerDeath(player)
    if player then
        KnoxSystem.SP.clearCartsOnDeath(player)
        if KnoxSystem.DStorage and KnoxSystem.DStorage.onDeath then
            KnoxSystem.DStorage.onDeath(player)
        end
    end
end

-- Detect PL crossing 10 for modal
local function onPlayerUpdate(player)
    if not player then return end
    pcall(function()
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Armored then
            KnoxSystem.Warrior.Armored.onPlayerUpdate(player)
        end
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Charge and KnoxSystem.Warrior.Charge.onPlayerUpdate then
            KnoxSystem.Warrior.Charge.onPlayerUpdate(player)
        end
        if KnoxSystem.Stats and KnoxSystem.Stats.onPlayerUpdate then
            KnoxSystem.Stats.onPlayerUpdate(player)
        end
        if KnoxSystem.Resilience and KnoxSystem.Resilience.onPlayerUpdate then
            KnoxSystem.Resilience.onPlayerUpdate(player)
        end
        if KnoxSystem.Power and KnoxSystem.Power.onPlayerUpdate then
            KnoxSystem.Power.onPlayerUpdate(player)
        end
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Melee and KnoxSystem.Warrior.Melee.onPlayerUpdate then
            KnoxSystem.Warrior.Melee.onPlayerUpdate(player)
        end
        if KnoxSystem.ZombieObserve and KnoxSystem.ZombieObserve.onPlayerUpdate then
            KnoxSystem.ZombieObserve.onPlayerUpdate(player)
        end
        if KnoxSystem.EliteTell and KnoxSystem.EliteTell.onPlayerUpdate then
            KnoxSystem.EliteTell.onPlayerUpdate(player)
        end
        if KnoxSystem.Analyze and KnoxSystem.Analyze.onPlayerUpdate then
            KnoxSystem.Analyze.onPlayerUpdate(player)
        end
        if KnoxSystem.DStorage and KnoxSystem.DStorage.onPlayerUpdate then
            KnoxSystem.DStorage.onPlayerUpdate(player)
        end
        local data = KnoxSystem.getPlayerData(player)
        if not data then return end
        local id = player:getPlayerNum() or 0
        local pl = data.personal_level or 0
        local prev = lastPL[id]
        if prev and pl >= 10 and prev < 10 then
            print("[KnoxSystem] Reached PL10 — open System tab, pick a class, Confirm")
        end
        lastPL[id] = pl
    end)
end

-- Melee damage → Melee Proficiency XP (best-effort hook)
local function onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker or not target then return end
    pcall(function()
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Charge and KnoxSystem.Warrior.Charge.onWeaponHit then
            KnoxSystem.Warrior.Charge.onWeaponHit(attacker, target)
        end
    end)
    pcall(function()
        if not instanceof(attacker, "IsoPlayer") then return end
        if not instanceof(target, "IsoZombie") then return end
        if weapon and weapon.isRanged and weapon:isRanged() then return end
        KnoxSystem.Warrior.Melee.onDealtDamage(attacker, target, damage or 1, weapon)
        if KnoxSystem.Analyze and KnoxSystem.Analyze.onDamageDealt then
            KnoxSystem.Analyze.onDamageDealt(attacker, target, damage or 1)
        end
        if KnoxSystem.ZombieObserve and KnoxSystem.ZombieObserve.onMeleeHit then
            KnoxSystem.ZombieObserve.onMeleeHit(attacker, target, damage or 1)
        end
    end)
    -- Player is the one getting hit (zombie/weapon → player)
    pcall(function()
        if not instanceof(target, "IsoPlayer") then return end
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Armored and KnoxSystem.Warrior.Armored.onIncomingHit then
            local kind = "hit"
            pcall(function()
                if weapon and weapon.isRanged and weapon:isRanged() then kind = "ranged"
                elseif weapon then kind = "melee_weapon"
                end
            end)
            KnoxSystem.Warrior.Armored.onIncomingHit(target, {
                damage = damage or 0,
                damageType = kind,
            })
        end
    end)
end

local function onPlayerGetDamage(player, damageType, damage)
    if not player then return end
    -- B42: this event also fires when YOU hit a zombie (arg is IsoZombie). IsoPlayer only.
    local isPlayer = false
    pcall(function()
        if instanceof and instanceof(player, "IsoPlayer") then isPlayer = true end
    end)
    if not isPlayer then return end
    pcall(function()
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Armored and KnoxSystem.Warrior.Armored.onIncomingHit then
            KnoxSystem.Warrior.Armored.onIncomingHit(player, {
                damage = damage or 0,
                damageType = damageType or "GetDamage",
            })
        end
    end)
    pcall(function()
        if KnoxSystem.Resilience and KnoxSystem.Resilience.onPlayerGetDamage then
            KnoxSystem.Resilience.onPlayerGetDamage(player, damageType, damage)
        end
    end)
end

local function onClothingUpdated(player)
    pcall(function()
        if player and KnoxSystem.Warrior and KnoxSystem.Warrior.Armored and KnoxSystem.Warrior.Armored.onClothingUpdated then
            KnoxSystem.Warrior.Armored.onClothingUpdated(player)
        end
    end)
end

Events.OnKeyPressed.Add(onKeyPressed)
Events.OnGameStart.Add(onGameStart)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnGameBoot.Add(function()
    if KnoxSystem.UI._patchCharacterInfo then KnoxSystem.UI._patchCharacterInfo() end
    if KnoxSystem.UI._patchInventoryTheme then KnoxSystem.UI._patchInventoryTheme() end
    if KnoxSystem.Power and KnoxSystem.Power.hookPerkLevel then
        pcall(function() KnoxSystem.Power.hookPerkLevel() end)
    end
    if KnoxSystem.Power and KnoxSystem.Power.hookUiRawDisplay then
        pcall(function() KnoxSystem.Power.hookUiRawDisplay() end)
    end
end)
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(onPlayerDeath)
end
if Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(onPlayerUpdate)
end
if Events.OnWeaponHitCharacter then
    Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
elseif Events.OnHitZombie then
    -- fallback signature varies; ignore if wrong
end

-- Tree / world dull paths for Melee Proficiency sharpness refund (A2)
local function onWeaponHitTree(attacker, weapon, ...)
    pcall(function()
        if not attacker then return end
        local isP = false
        pcall(function()
            if instanceof and instanceof(attacker, "IsoPlayer") then isP = true end
        end)
        if not isP then return end
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Melee and KnoxSystem.Warrior.Melee.onWorldWeaponUse then
            KnoxSystem.Warrior.Melee.onWorldWeaponUse(attacker, weapon, "hit_tree")
        end
    end)
end

local function onWeaponHitXp(owner, weapon, hitObject, damage, ...)
    -- Fires for various hit types; filter non-zombie world-ish when possible
    pcall(function()
        if not owner then return end
        local isP = false
        pcall(function()
            if instanceof and instanceof(owner, "IsoPlayer") then isP = true end
        end)
        if not isP then return end
        if hitObject ~= nil then
            local isZ = false
            pcall(function()
                if instanceof and instanceof(hitObject, "IsoZombie") then isZ = true end
            end)
            if isZ then return end -- combat path already handled
        end
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Melee and KnoxSystem.Warrior.Melee.onWorldWeaponUse then
            KnoxSystem.Warrior.Melee.onWorldWeaponUse(owner, weapon, "weapon_hit_xp")
        end
    end)
end

if Events.OnWeaponHitTree then
    Events.OnWeaponHitTree.Add(onWeaponHitTree)
end
if Events.OnWeaponHitXp then
    Events.OnWeaponHitXp.Add(onWeaponHitXp)
end
-- Some builds use OnDestroyIsoThumpable / hit thumpable for barricades/doors
if Events.OnWeaponHitThumpable then
    Events.OnWeaponHitThumpable.Add(function(attacker, weapon, thumpable, ...)
        pcall(function()
            if KnoxSystem.Warrior and KnoxSystem.Warrior.Melee and KnoxSystem.Warrior.Melee.onWorldWeaponUse then
                KnoxSystem.Warrior.Melee.onWorldWeaponUse(attacker, weapon, "hit_thumpable")
            end
        end)
    end)
end

if Events.OnPlayerGetDamage then
    Events.OnPlayerGetDamage.Add(onPlayerGetDamage)
end
if Events.OnClothingUpdated then
    Events.OnClothingUpdated.Add(onClothingUpdated)
end
if Events.OnZombieUpdate then
    Events.OnZombieUpdate.Add(function(zombie)
        if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.onZombieUpdate then
            KnoxSystem.WorldZombies.onZombieUpdate(zombie)
        end
    end)
end
if Events.OnZombieDead then
    Events.OnZombieDead.Add(function(zombie)
        if KnoxSystem.WorldZombies and KnoxSystem.WorldZombies.onZombieDead then
            KnoxSystem.WorldZombies.onZombieDead(zombie)
        end
    end)
end

print("[KnoxSystem] client hooks registered (Phase 4-5 + Resilience infection resist)")
