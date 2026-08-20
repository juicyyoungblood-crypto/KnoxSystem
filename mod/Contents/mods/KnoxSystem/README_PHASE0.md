# Phase 0 scaffold — Knox System B42 mod

## Location (bind-mounted)

```text
Container: /opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem
Windows:   C:\Users\jesse\Zomboid\mods\KnoxSystem
```

## Layout

```text
KnoxSystem/
  KS_DEPLOY_TEST.txt          # bridge proof
  common/mod.info             # B42 common stub
  42/
    mod.info
    media/
      sandbox-options.txt     # stub
      lua/
        shared/KnoxSystem/KS_ModData.lua
        client/KnoxSystem/KS_Bootstrap_Client.lua
        server/KnoxSystem/KS_Bootstrap_Server.lua
        shared/Translate/EN/UI_EN.txt
```

## What Phase 0 does

- Appears in Mods list as **Knox System** (`id=KnoxSystem`)
- On game start / create player: initializes player ModData blob under key `KnoxSystem`
- Logs `[KnoxSystem] ...` lines to console

## Player test

1. Fully quit Project Zomboid if running
2. Launch → **Mods** → enable **Knox System**
3. **New game** (preferred)
4. Check `C:\Users\jesse\Zomboid\Logs\` latest `console.txt` for `[KnoxSystem]`
5. No hard errors = Phase 0 exit criteria met

## Next

Phase 1 — Personal XP / Level / SP grant (`docs/architecture.md`)
