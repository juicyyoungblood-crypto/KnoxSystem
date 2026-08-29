require "KnoxSystem/KS_ModData"
require "KnoxSystem/KS_Config"
require "KnoxSystem/KS_Level"
require "KnoxSystem/KS_PersonalXP"
require "KnoxSystem/KS_WorldRank"
require "KnoxSystem/KS_SP"
require "KnoxSystem/KS_BaseSkills"
require "KnoxSystem/KS_Stats"
require "KnoxSystem/KS_Sandbox"
require "KnoxSystem/KS_Power"
require "KnoxSystem/KS_Endurance"
require "KnoxSystem/KS_SystemSkills"
require "KnoxSystem/KS_DStorage"
require "KnoxSystem/KS_Class"
require "KnoxSystem/KS_Warrior_Melee"
require "KnoxSystem/KS_Warrior_Armored"
require "KnoxSystem/KS_TrackLog"
require "KnoxSystem/KS_ZombieObserve"
require "KnoxSystem/KS_WorldZombies"
require "KnoxSystem/KS_Goblin"

print(string.format("[KnoxSystem] server/shared boot v%s Phase 5", KnoxSystem.VERSION))

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
