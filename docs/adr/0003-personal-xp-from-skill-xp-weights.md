# Personal XP is minted from base skill XP via per-skill weights

When the game grants base skill XP, Personal XP is granted at the same time as `skillXP * weight(skill)`, with weights overridable in mod options. Default category baselines: crafting 0.3, passive 0.25, combat and physical 1.0, survival 0.5 — applied per skill, not only as a blunt category dump. Quest/System personal-only XP hooks are deferred. This matches “XP when you gain skill XP,” lets combat/craft curves be tuned without rewriting actions, and keeps a single pipeline for balance.
