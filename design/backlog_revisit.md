# Knox System — design backlog (revisit)

Status: parked ideas (not scheduled). Captured from playtest discussion after Analyze / D. Storage.

## Quest Board (NOT a skill — world object)
- Implement as a **placeable / findable world object**, not a personal System skill.
- Intent: System contracts UI at the object (daily/weekly jobs: kill N, clear house, craft X → SP/XP).
- Open questions: spawn locations (safehouse craftable vs world POI), multiplayer claim rules, refresh cadence, reward table.

## Threat Sense → **Sense Danger** (personal skill candidate)
- Display name: **Sense Danger** (not "Threat Sense").
- Effect draft:
  - Audible **beep** when a zombie is within **X feet** (tune X later).
  - **Normal zombies:** single beep (rate-limited).
  - **Sprinters and elites:** **continuous** beep/tone while in range.
- Open questions: range, volume, deafness/trait interactions, distinct elite vs sprinter tone, Analyze synergy.

## Save Point → **Recall** (personal skill / System ability candidate)
- Display name: **Recall** (not "Save Point").
- Intent: place or bind a recall point; activate to return (long cooldown).
- Open questions: multiplayer exploit/safe rules, corpse/bag interaction, combat lockdown, cost (SP levels vs charge item).

---
When picking these up: one-by-one options → lock → then implement. Do not bulk-ship.
