# Phase 0 uses B42 versioned mod folder under bind-mounted KnoxSystem

The playable mod root is the bind target `Zomboid/mods/KnoxSystem` (= container path `.../mod/Contents/mods/KnoxSystem`). B42 layout is `common/` + `42/mod.info` + `42/media/lua/{shared,client,server}`. Design remains under `design/`; code under `mod/`. Deploy bridge is bind-mount (ADR path in deploy docs), not docker cp per change.
