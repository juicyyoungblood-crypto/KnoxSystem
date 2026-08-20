# Phase 1 — Personal XP / Level / SP

## Files added

| File | Role |
|------|------|
| `shared/KnoxSystem/KS_Config.lua` | Curve coeffs + skill weights |
| `shared/KnoxSystem/KS_Level.lua` | Cubic level-from-XP, SP on level-up |
| `shared/KnoxSystem/KS_PersonalXP.lua` | `Events.AddXP` hook → Personal XP |
| `design/skill_id_map.yaml` | Design ↔ live perk keys |

Version bump: **0.2.0**

## Behavior

1. When vanilla grants skill XP → Personal XP `+= amount * weight(skill)`.
2. Weights from design (combat 1.0, craft 0.3, passive 0.25, …).
3. Personal Level from cubic cumulative thresholds (L1=375, L10=10500, L100=2.089e6).
4. Each new PL grants **+1 SP** (logged).
5. Debug prints every Personal XP gain + dump on game start.

## How to test

1. Quit PZ fully; relaunch; enable **Knox System**; **new game**.
2. Open `Zomboid\Logs\console.txt` (or in-game console if enabled).
3. Do something that grants skill XP (saw logs, kill zombie with weapon, etc.).
4. Look for:
   - `[KnoxSystem] shared loaded v0.2.0`
   - `[KnoxSystem] Hooked Events.AddXP`
   - `[KnoxSystem] +X.XX Personal XP (skill:SomePerk xW)`
5. Optional: debug cheat lots of XP — or wait until total Personal XP ≥ 375 for:
   - `[KnoxSystem] LEVEL UP -> Personal Level 1 (+1 SP...`

### Fast level-1 check (optional)

If you use debug/dev mode and can run Lua, after loading:

```lua
local p=getPlayer(); KnoxSystem.PersonalXP.addPersonalXp(p, 400, "debug"); KnoxSystem.Level.debugDump(p)
```

## Exit criteria

- [ ] AddXP hook present (no WARNING in log)
- [ ] Skill actions mint Personal XP lines
- [ ] Crossing 375 XP grants PL1 + 1 SP
- [ ] Note any `skill:Unknown` or weird keys → add to `skill_id_map.yaml` / `KS_Config.SkillWeight`

## Next

Phase 2 — System Tab read-only showing PL / XP / SP / World Rank.
