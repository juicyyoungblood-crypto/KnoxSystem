# Phase 2.1 — System as character sheet tab

Version **0.3.1**

## Change
- Removed floating `ISCollapsableWindow` System panel as primary UI
- Added `KS_SystemTabView` as a real tab via `ISCharacterInfoWindow:addView` (or `panel:addView`)
- Key **O** focuses character sheet → System tab (does not open a separate window)

## How to test
1. Fully quit PZ, relaunch, enable Knox System, load game
2. Open **character sheet** (default often **C**)
3. You should see a **System** tab with Info / Skills / Health / …
4. Click **System** — blue panel with Level, World Rank, SP, classes
5. Optional: press **O** to jump to that tab

## Log
- `Character info System-tab patch installed`
- `System tab added via ISCharacterInfoWindow:addView`  
  OR `via window.panel:addView`
- If WARNING cannot find addView — paste that line and we’ll adapt to B42’s actual UI class

## Next
Phase 3 — SP cart on this tab + skills tab plus buttons
