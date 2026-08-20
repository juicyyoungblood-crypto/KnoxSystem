# Knox System design package

Mod design source of truth for **Knox System** (Project Zomboid B42 System-apocalypse / LitRPG layer).

## Layout

| Path | Role |
|------|------|
| `CONTEXT.md` | Ubiquitous language only |
| `docs/adr/` | Decision records |
| `docs/architecture.md` | Modules, events, build phases, client/server |
| `design/` | Mechanics YAML (numbers + rules) |
| `design/ui.yaml` | System Tab layout, SP cart, theme, keybind feedback |
| `design/world_scaling.yaml` | World threat: PL+time hybrid, spawn-stamped tiers + elites |
| `design/moddata_schema.yaml` | Player/zombie persisted fields |
| `docs/deploy-and-access.md` | How files reach the game + host access for testing |
| `mod/` | B42 mod code (created at Phase 0) |

## MVP

- Rising + System Infection reskin
- Personal Level / XP / SP / stats / **System Tab**
- Class at PL10 (permanent)
- **Warrior** fully realized
- Other classes: designed YAML, not selectable
- Specializations (25/50): deferred
- World scaling structure locked (draft numbers)
- LitRPG UI theme (character sheet + inventory/crafting)

## Git

Repo root: `/opt/data/workspace/pz-system-apocalypse` (branch `main`).

```bash
cd /opt/data/workspace/pz-system-apocalypse
git log --oneline
git tag
git show v0.5.125:mod/Contents/mods/KnoxSystem/42/mod.info
git diff v0.5.125 -- mod/
git checkout v0.5.125 -- path/to/file.lua   # restore one file from a tag
```

Tags: `v0.5.125` = initial snapshot (current). After meaningful ship points, tag `vX.Y.Z` to match `mod.info` / `KS_ModData.VERSION`.

Ignored: `console.txt`, `*.log`, `Issue*.jpg` dumps in the mod folder.

## Status legend

- `locked` / `locked_structure` — do not re-litigate without a new ADR
- `draft_numbers` — structure locked; magnitudes tunable
- `deferred` — out of MVP (specializations, quest Personal XP hooks)
- ~~`balance_pass_open`~~ — not current; world scaling structure is locked (ADR 0019)

## Balance note

World scaling is **structure-locked** (ADR 0019): spawn-stamped System Tiers + elites on top of vanilla sandbox. Magnitudes/weight tables are `draft_numbers` — tune in playtest (Phase 8). Do not ship player kits with world scaling disabled by default.

## Implementation note

Read `docs/architecture.md` before writing Lua. Build by phase; do not start with inventory theme or all five classes.
