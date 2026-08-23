# World Level is days/3 + avgPL/2 (time leg capped; total max 40)

World Level is the primary world progression integer for threat. Design formula:

- **Time leg:** +1 per 3 full in-game days; **time contribution capped at +10**.
- **Power leg:** `floor(avgPL / 2)` over the roster in the **14-day** activity window (offline living still count while in-window).
- **Total:** time leg + power leg, then **clamp to max World Level 40**.
- **Example:** day 20 → +6 time; avg PL 15 → +7 power; **World Level 13**.

World Level drives System Tier spawn weights and Modifier Loadout intensity on a smooth curve from the low end (non-elites 0 Modifiers; elites 1–2× Tier 1) to the **high end at World Level 40** (non-elites 1–3× T1–T3; elites exactly 6 with T4 spine). Sprinters gate at **World Level ≥ 5**.

**World Rank** on the System Tab is the player-facing readout of this progression (not a second formula). Average PL is an input leg, not a parallel Rank curve.
