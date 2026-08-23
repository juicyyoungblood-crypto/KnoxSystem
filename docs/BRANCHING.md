# Branch workflow: Stable / Unstable

## Branches

| Branch | Role |
|--------|------|
| **`Stable`** | Last known-good playable build. Do not land experimental work here. |
| **`Unstable`** | Active development. All new features and fixes go here first. |
| `main` | Historical line. Prefer Stable/Unstable going forward. |

## Current baseline

- **Stable tip:** (this promote) — Knox **0.6.21**
- **Live mod version at baseline:** **0.6.21**
- **Tag:** `stable-0.6.21` (and `v0.6.21`)
- **Previous Stable:** `d8ddcdf` / `stable-0.5.163` (pre–WR/modifiers hang era)

### What’s in 0.6.21 Stable (summary)

- World Rank + WorldSpawn curves (A2/H1/S1/E2/D2)
- Modifier catalog + loadouts + easy combat (skins, Heavy Hit, Sys.Hardened)
- Relentless (KD-only) + Anchored (full control lock) — idle-safe
- Goblin Tier 0: exclusive, flee, LOS despawn after flee, loot ×2, sandbox chance 1–10‰
- Analyze PLATE_REV≥23 distance prefilter
- Sandbox: Power/Endurance/SP/PersXP + GoblinChancePerThousand

## Day-to-day

1. Work and commit on **`Unstable`**.
2. Playtest Unstable builds only until you say they are good.
3. When you say **“set current as Stable”** (or equivalent):
   - Fast-forward / reset **`Stable`** to the current Unstable tip (or the commit you name).
   - Move/create a new `stable-<version>` tag if useful.
   - Continue **`Unstable`** from the new Stable tip so the next cycle starts clean.

## Emergency rollback (playable mod)

```bash
git checkout Stable
# live mod is under mod/Contents/mods/KnoxSystem/ at this commit
```

Or keep working on Unstable but restore only the mod tree:

```bash
git checkout Stable -- mod/Contents/mods/KnoxSystem/
```

## Notes

- Design docs (ADRs, `design/zombie_mutations.yaml`) may live on Unstable before code ships.
- Promoting Stable is **only** on your explicit request after you’re satisfied with the build.
