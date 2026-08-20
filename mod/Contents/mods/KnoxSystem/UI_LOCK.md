# UI lock — character sheet (v0.4.19 LOCKED)

Do not regress without explicit user ask.

## Vanilla tabs (Info / Skills / Health / Protection / Temperature)
- Minimal inject only
- Soft blue on **outer window** only
- **Never** set `backgroundColor` on vanilla tab views
- **Never** resize tab panel every frame for vanity
- Content must remain fully visible

## System tab
- Fixed width **460px** (no width growth / fullscreen bloom)
- Height fits content (screen-clamped); mouse-wheel scroll if needed
- Centered: character name, Confirm Stat Spend, Confirm Skill Spend
- Soft System blue body
- SP carts: stats + base skills with categories matching Skills tab
- Skill labels: `Name: Level` (e.g. `Aiming: 0`)
- Class buttons; Warrior selectable at PL10; others “Coming later”
- Catalog: `KS_BaseSkills.lua` (Skills-tab display names)

## Patch id
`KS_UI_SystemTab` **3.18** / mod **0.4.19**
