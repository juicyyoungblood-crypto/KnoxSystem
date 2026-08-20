# Phase 3 — SP cart

Version **0.4.0**

## Features
- **Stat cart** on System tab: Strength/Endurance/Mind/Resilience `+` / `-` + **Confirm Stat Spend**
- **Skill cart** on System tab: base skills list with `+` / `-` + **Confirm Skill Spend**
- Costs: stats 1 SP each; skills `ceil(targetLevel/2)` per level staged
- Carts independent; persist until Confirm / death
- `KS_Stats` stores draft multipliers on ModData (full combat hooks later)

## Test
1. Quit/relaunch PZ, load with Knox System  
2. Earn SP (or debug: `KnoxSystem.PersonalXP.addPersonalXp(getPlayer(), 400, "debug")` until you have SP)  
3. Character sheet → **System**  
4. Press **+** on Strength → label shows `(+1)`, cart cost updates  
5. **Confirm Stat Spend** → SP drops, Strength stays raised  
6. **+** on Axe → Confirm Skill Spend → Axe skill level increases in vanilla Skills tab  

## Log
- `Phase 3 SP cart`
- `Confirmed stats cart` / `Confirmed skills cart`
- `LevelPerk failed` if a skill key is wrong — report the skill name

## Note
Design also wants `+` on the vanilla Skills tab; System tab list is the reliable MVP path. Skills-tab chrome can come in a polish pass.
