# Phase 4 — Class + Warrior (v0.5.0)

## UI lock
Sheet look remains **v0.4.19** — see `UI_LOCK.md`. Do not change chrome without ask.

## Features
- **PL10 class modal** — Warrior selectable; others “Coming later”
- Permanent class lock via `KnoxSystem.Class.select`
- System tab class skills: `Melee Proficiency`, `Armored`, `Charge` as `Name: Level`
- **Melee Proficiency** XP from melee hits on zombies
- **Armored** XP from worn protection passive + mitigate hook (partial)
- **Charge (G)**: dash, hit zombies, endurance cost, `*huff*` floater

## Test
1. Reach PL 10 (or debug level) → modal appears → pick Warrior  
2. Or System tab → click Warrior at PL10+  
3. Melee zombies → Melee Proficiency level rises  
4. Wear armor → Armored XP ticks  
5. Press **G** with stamina → Charge + huff  

## Debug
```lua
-- force PL 10
local d = KnoxSystem.getPlayerData(getPlayer()); d.personal_level = 10
KnoxSystem.UI.tryClassModal(getPlayer())
```
