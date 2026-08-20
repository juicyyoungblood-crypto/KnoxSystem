# Knox System — architecture

Status: ready for Phase 0 implementation. Product rules live in `design/*.yaml` and ADRs; this file is the engineering spine.

## Goals

- Ship MVP: progression + System Tab + Warrior + world tiers + death/Rising + themed character/inventory/crafting UI (theme late).
- Single-player success criteria; multiplayer-safe field placement (backbone).
- Data-driven tunables matching design YAML keys.

## Non-goals (MVP)

- Specializations (PL 25/50)
- Quest Personal XP hooks
- Full Thief/Ranger/Mage/Crafter gameplay (YAML exists; not selectable)
- Main HUD moodle/hotbar restyle
- Perfect balance numbers (Phase 8)

## Repository layout

```text
pz-system-apocalypse/
  CONTEXT.md
  README.md
  design/                 # product SoT
  docs/
    adr/
    architecture.md       # this file
    deploy-and-access.md
  mod/                    # B42 code SoT (Phase 0+)
    Contents/mods/KnoxSystem/
      42/
        mod.info
        poster.png          # optional
        media/
          lua/
            shared/         # pure data, formulas, ModData keys
            server/         # authority-friendly hooks (use even in SP)
            client/         # UI, keybinds, local FX
          sandbox-options.txt   # if used
          lua/shared/Translate/EN/
```

Canonical code path: `mod/Contents/mods/KnoxSystem/`.  
Deploy copy/symlink into the player’s Zomboid mods directory (see `deploy-and-access.md`).

## Runtime split

| Layer | Responsibility |
|-------|----------------|
| **shared** | Constants, cubic PL curve, SP cost `ceil(L/2)`, weight lookup, tier weight blend, ModData get/set helpers, schema version |
| **server** (or shared when SP-only APIs demand it) | Personal XP mint, level-up, SP grant, apply confirmed SP cart, class assign, class skill XP, zombie tier stamp, Rising/Resilience gates |
| **client** | System Tab, SP cart UI, theme, keybind Charge, floaters, eye glow / corpse name presentation, class modal |

Rule: **never trust the client to finalize SP spends, level-ups, or tier rolls** without the same functions callable from a single authority path (easier MP later).

## Module map

| Module ID | Phase | Role |
|-----------|-------|------|
| `KS_Bootstrap` | 0 | Mod load, sandbox options register |
| `KS_ModData` | 0 | Player/zombie ModData schema access + version migrate |
| `KS_Config` | 0 | Tunables from sandbox / defaults mirroring design YAML |
| `KS_PersonalXP` | 1 | On base/class skill XP → Personal XP |
| `KS_Level` | 1 | Cumulative cubic thresholds, level-up, SP schedule |
| `KS_SP` | 1–3 | Balance, cart commit, base skill instant level, stat buy |
| `KS_Stats` | 3–6 | Strength/Endurance/Mind/Resilience effects |
| `KS_WorldRank` | 2 | Display number from PL + day |
| `KS_WorldTier` | 5 | Spawn stamp, mults, elite roll |
| `KS_Class` | 4 | Unlock, permanent pick, skill registry |
| `KS_Warrior_Melee` | 4 | Melee Proficiency |
| `KS_Warrior_Armored` | 4 | Armored |
| `KS_Warrior_Charge` | 4 | Charge ability |
| `KS_Death` | 6 | Death message, Rising gate |
| `KS_UI_SystemTab` | 2–3 | System Tab |
| `KS_UI_SPCart` | 3 | Plus/minus/confirm |
| `KS_UI_Theme` | 2 then 7 | Character chrome early; inventory/crafting Phase 7 |
| `KS_UI_ClassModal` | 4 | PL10 modal |
| `KS_Tells` | 5 | Elite eye glow, corpse names |

## Event → system (implementation targets)

Exact B42 event names are spiked in Phase 0–1; intent is fixed:

| Game moment | System |
|-------------|--------|
| Base skill XP awarded | `KS_PersonalXP` |
| Class skill XP awarded | `KS_PersonalXP` (half bucket) + class skill progress |
| Level-up Personal | `KS_Level` → SP grant; if PL==10 and no class → class modal |
| SP Confirm | `KS_SP` commit cart |
| Zombie created/spawned | `KS_WorldTier` stamp |
| Player damaged / armor mitigates | `KS_Warrior_Armored` XP |
| Melee/stomp damage to zombie | `KS_Warrior_Melee` XP |
| Keybind Charge | `KS_Warrior_Charge` |
| Player death | `KS_Death` |
| Character UI open | `KS_UI_*` |

## Build phases

### Phase 0 — Skeleton
- [x] `mod/` B42 tree + `mod.info` appears in game mod list
- [x] Sandbox options stub (placeholder file)
- [x] `KS_ModData` init empty player blob on create/load
- [x] Deploy path documented and tested once by human

**Exit:** New game with mod on does not error; ModData key present.

### Phase 1 — Personal XP / Level / SP grant
- [x] Hook skill XP; apply weights (`design/weights.yaml` → `KS_Config`)
- [x] Cubic cumulative thresholds (`design/progression.yaml` → `KS_Level`)
- [x] Level-up grants SP (default 1)
- [x] Debug print or simple log for PL/XP/SP
- [x] Start `design/skill_id_map.yaml` from spike

**Exit:** Killing/crafting raises Personal XP; crossing threshold increases PL and SP. *(awaiting player playtest)*

### Phase 2 — System Tab read-only + World Rank + light theme
- [x] System panel: name, stats, Level, Exp to Next, World Rank, Unspent SP
- [x] World Rank simple band display
- [x] System blue chrome on panel (full sheet theme still Phase 7)
- [x] Open via key **O** + optional character-info button

**Exit:** Player can open System UI and see live PL/XP/SP/World Rank. *(awaiting playtest)*

### Phase 3 — SP cart + stats + Skills tab +
- [x] System tab stat + / minus / Confirm
- [x] System tab base skill + / minus / Confirm (Skills-tab native + deferred polish)
- [x] Instant base skill level on confirm; stats Mult stored on ModData
- [x] Cart persists per design until confirm/death
- [x] **UI look locked** at v0.4.19 (`mod/Contents/mods/KnoxSystem/UI_LOCK.md`)

**Exit:** Spend SP on Axe and Strength with confirm; effects visible. **PASS**

### Phase 4 — Class + Warrior
- [x] PL10 modal; Warrior only
- [x] Class skills UI on System Tab (`Name: Level`)
- [x] Melee Proficiency XP from melee hits; Armored passive/mitigate XP
- [x] Charge **G** + heavy breathing floater (*huff*)
- [ ] Playtest polish (door bash L3+, exact moodle gate, damage mult apply)

**Exit:** Warrior loop playable in SP. *(implementing / await playtest)*

### Phase 5 — World tiers + tells
- [ ] Spawn stamp + mults/tags
- [ ] Elite roll + eye glow
- [ ] Corpse tier name

**Exit:** Higher PL/day yields tougher stamped zombies; elites glow.

### Phase 6 — Death / Rising / infection hooks
- [ ] “The System Has Claimed You”
- [ ] Rising blocked only at Resilience 20
- [ ] Resilience infection modifiers (best-effort on vanilla hooks)

**Exit:** Death/Rising rules match `design/lore.yaml`.

### Phase 7 — Inventory + crafting theme
- [ ] Same blue chrome; icons unchanged

**Exit:** No vanilla parchment islands next to System UI.

### Phase 8 — Playtest balance
- [ ] Tune draft_numbers only; no silent fantasy nerfs
- [ ] Update YAML keys after playtest

## Multiplayer backbone

- Store all progression on player ModData with stable keys (`design/moddata_schema.yaml`).
- Tier/elite on zombie ModData.
- Pending SP carts: client-staged OK; commit must be authoritative.
- Do not require MP testing for MVP exit; do not put progression only in local UI state.

## Compatibility

- **New game preferred** (`design/ui.yaml` mid_save).
- Mid-save enable: best-effort init PL0 / 0 SP / no class.
- B42 only.

## Agent rules

1. Load skill `knox-system` + this file + relevant design YAML.
2. Implement **one phase at a time**; tick exit criteria.
3. Change product rules in design/ADR/CONTEXT first.
4. Never invent SP→class skill purchases or Charge on player-built doors.
5. Prefer named config keys over magic numbers.
