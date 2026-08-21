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
require "KnoxSystem/KS_StrengthProbe"
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
    if KnoxSystem.UI._patchExisting then
        pcall(function() KnoxSystem.UI._patchExisting() end)
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
    pcall(function()
        if KnoxSystem.UI._patchCharacterInfo then KnoxSystem.UI._patchCharacterInfo() end
        if KnoxSystem.UI._patchExisting then KnoxSystem.UI._patchExisting() end
    end)
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
        if KnoxSystem.StrengthProbe and KnoxSystem.StrengthProbe.onPlayerUpdate then
            pcall(function() KnoxSystem.StrengthProbe.onPlayerUpdate(player) end)
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

-- Melee damage → Melee Proficiency XP + Analyze plate (total damage)
local function onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker or not target then return end

    -- Snapshot HP before our hooks (engine may already have applied vanilla hit)
    local hpBefore = nil
    pcall(function()
        if target.getHealth then hpBefore = tonumber(target:getHealth()) end
    end)
    if KnoxSystem.Power then
        KnoxSystem.Power._lastHitBonusDamage = 0
        KnoxSystem.Power._lastHitEventDamage = tonumber(damage) or 0
    end

    pcall(function()
        if KnoxSystem.Warrior and KnoxSystem.Warrior.Charge and KnoxSystem.Warrior.Charge.onWeaponHit then
            KnoxSystem.Warrior.Charge.onWeaponHit(attacker, target)
        end
    end)
    pcall(function()
        if KnoxSystem.StrengthProbe and KnoxSystem.StrengthProbe.onWeaponHitCharacter then
            KnoxSystem.StrengthProbe.onWeaponHitCharacter(attacker, target, weapon, damage)
        end
    end)
    pcall(function()
        if KnoxSystem.Power and KnoxSystem.Power.onWeaponHitCharacter then
            KnoxSystem.Power.onWeaponHitCharacter(attacker, target, weapon, damage)
        end
    end)

    local hpAfter = hpBefore
    pcall(function()
        if target.getHealth then hpAfter = tonumber(target:getHealth()) end
    end)

    -- Display total for Analyze plate
    -- eventDamage = engine hit (already includes ground/crit mults)
    -- powerBonus  = theoretical Power snip (10% * PowerLv * event)
    -- hpDelta     = HP removed during our hooks (usually the Power snip; engine hit already applied)
    local eventDmg = tonumber(damage) or 0
    local powerBonus = 0
    local powerLv = 0
    if KnoxSystem.Power then
        powerBonus = tonumber(KnoxSystem.Power._lastHitBonusDamage) or 0
        if KnoxSystem.Power.level then
            pcall(function() powerLv = KnoxSystem.Power.level(attacker) or 0 end)
        end
    end
    local hpDelta = 0
    if hpBefore ~= nil and hpAfter ~= nil then
        hpDelta = hpBefore - hpAfter
        if hpDelta < 0 then hpDelta = 0 end
    end

    -- Power can only remove HP that still exists when our hook runs
    local powerActual = powerBonus
    if hpBefore ~= nil and hpBefore >= 0 then
        if powerActual > hpBefore then powerActual = hpBefore end
    elseif hpDelta > 0 and powerBonus > 0 then
        -- Fallback: observed hook delta is what Power actually took
        if hpDelta < powerActual then powerActual = hpDelta end
    end

    -- Full hit ≈ engine event (pre-hook) + Power HP actually removed
    local sumParts = eventDmg + powerActual
    local shown = sumParts
    local pick = "event+powerActual"

    -- If hooks removed more than event+power (other systems), prefer that
    if hpDelta > shown + 0.001 then
        shown = eventDmg + hpDelta
        pick = "event+hpDelta"
    end

    -- Knocked-down / prone context (for log; engine already baked mult into eventDmg)
    local targetDown, targetCrawling = 0, 0
    pcall(function()
        if target.isKnockedDown and target:isKnockedDown() then targetDown = 1 end
    end)
    pcall(function()
        if target.isCrawling and target:isCrawling() then targetCrawling = 1 end
    end)
    pcall(function()
        if target.isOnFloor and target:isOnFloor() then targetDown = 1 end
    end)

    -- Weapon / HP max context
    local wpnName, wpnDmg, bare, ranged = "?", -1, 0, 0
    pcall(function()
        if weapon then
            if weapon.getDisplayName then wpnName = tostring(weapon:getDisplayName() or "?") end
            if weapon.getName and wpnName == "?" then wpnName = tostring(weapon:getName() or "?") end
            if weapon.getMaxDamage then wpnDmg = tonumber(weapon:getMaxDamage()) or -1 end
            if weapon.isBareHands and weapon:isBareHands() then bare = 1 end
            if weapon.isRanged and weapon:isRanged() then ranged = 1 end
        end
    end)
    local hpMax = -1
    pcall(function()
        if target.getMaxHealth then hpMax = tonumber(target:getMaxHealth()) or -1 end
    end)

    local function logHitBreakdown()
        if not KnoxSystem.Track then return end
        local fields = {
            reason = "hit_damage_breakdown",
            eventDamage = eventDmg,
            powerLv = powerLv,
            powerBonusTheoretical = powerBonus,
            powerBonusActual = powerActual,
            powerBonusFormula = string.format("%.3f * 0.10 * %d (= +%d%%)", eventDmg, powerLv, powerLv * 10),
            sumEventPlusPower = sumParts,
            hpBeforeHooks = hpBefore,
            hpAfterHooks = hpAfter,
            hpDeltaDuringHooks = hpDelta,
            hpMax = hpMax,
            targetKnockedDown = targetDown,
            targetCrawling = targetCrawling,
            plateShown = shown,
            plateDisplay = math.floor((tonumber(shown) or 0) * 100 + 0.5),
            platePick = pick,
            weapon = wpnName,
            weaponMaxDamage = wpnDmg,
            bareHands = bare,
            ranged = ranged,
            note = "Plate=round((eventDmg+powerActual)*100). Power10=+100% of event. Ground mult is VANILLA inside eventDmg (often ~2–2.5x).",
            noteKillCap = "powerActual capped to HP left when hooks run (no fake overkill on plate).",
        }
        if KnoxSystem.Track.isChannelOn("damage") then
            KnoxSystem.Track.log("damage", "hit_breakdown", fields)
        end
        if KnoxSystem.Track.isChannelOn("analyze") then
            KnoxSystem.Track.log("analyze", "plate_number", fields)
        end
    end
    pcall(logHitBreakdown)

    pcall(function()
        if not instanceof(attacker, "IsoPlayer") then return end
        if not instanceof(target, "IsoZombie") then return end
        if weapon and weapon.isRanged and weapon:isRanged() then return end
        KnoxSystem.Warrior.Melee.onDealtDamage(attacker, target, damage or 1, weapon)
        if KnoxSystem.Analyze and KnoxSystem.Analyze.onDamageDealt then
            KnoxSystem.Analyze.onDamageDealt(attacker, target, shown, {
                eventDamage = eventDmg,
                powerBonus = powerActual,
                powerBonusTheoretical = powerBonus,
                hpDelta = hpDelta,
                hpBefore = hpBefore,
                hpAfter = hpAfter,
                platePick = pick,
            })
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
    -- Logging only — never patches character window shell / no Strength hook
    if KnoxSystem.StrengthProbe and KnoxSystem.StrengthProbe.boot then
        pcall(function() KnoxSystem.StrengthProbe.boot() end)
    end
end)
-- Re-patch after UI classes exist / player created (boot require often fails early)
-- (OnGameStart + OnCreatePlayer already call _patchCharacterInfo / _patchExisting)
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
-- NOTE: Kahlua forbids using `...` inside nested functions — capture args explicitly.
local function onWeaponHitTree(attacker, weapon, a1, a2, a3, a4)
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
        if KnoxSystem.StrengthProbe and KnoxSystem.StrengthProbe.onWeaponHitTree then
            KnoxSystem.StrengthProbe.onWeaponHitTree(attacker, weapon)
        end
        if KnoxSystem.Power and KnoxSystem.Power.onWeaponHitTree then
            KnoxSystem.Power.onWeaponHitTree(attacker, weapon, a1, a2, a3, a4)
        end
    end)
end

local function onWeaponHitXp(owner, weapon, hitObject, damage)
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
    Events.OnWeaponHitThumpable.Add(function(attacker, weapon, thumpable, dmg, a2, a3, a4)
        pcall(function()
            if KnoxSystem.Warrior and KnoxSystem.Warrior.Melee and KnoxSystem.Warrior.Melee.onWorldWeaponUse then
                KnoxSystem.Warrior.Melee.onWorldWeaponUse(attacker, weapon, "hit_thumpable")
            end
            if KnoxSystem.StrengthProbe and KnoxSystem.StrengthProbe.onWeaponHitThumpable then
                KnoxSystem.StrengthProbe.onWeaponHitThumpable(attacker, weapon, thumpable)
            end
            if KnoxSystem.Power and KnoxSystem.Power.onWeaponHitThumpable then
                KnoxSystem.Power.onWeaponHitThumpable(attacker, weapon, thumpable, dmg)
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
