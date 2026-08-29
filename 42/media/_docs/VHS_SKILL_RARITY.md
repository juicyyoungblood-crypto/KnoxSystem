# VHS rarity (LOCKED policy ≥0.5.124 / theme 11.6)

**Code:** `KS_UI_InventoryTheme.lua`  
**Rule:** almost all VHS share `Base.VHS_Retail` / `Base.VHS_Home` — rarity is from **title/media**, not fullType alone.

## Policy

| Case | Rarity |
|------|--------|
| Default VHS (movies, fluff, unlisted skill tapes) | **common** |
| Whitelisted titles / series below | **rare** |

No epic auto-tier for “any skill tape” anymore.

## Rare series (all episodes)

- Woodcraft  
- The Cook Show  
- Carzone  
- Exposure Survival  

## Rare named titles

- Mother's Boy  
- Dead Wrong  
- Z-Squad S2.03  
- No. 9 / Nof Vid  
- Granny Nani  
- Tailoring 101  
- OSCC '92  
- Stock Cars  
- Mathematical Quadratics and Algebraic Configurations  
- Grady v King  
- Combat Wound Management  
- RMFA  
- Muldraugh AV Club  
- TV Repair  
- Basic Gun Handling (Officer Use Only)  
- Tree Planting Guide  
- Knox Gun Owners Club's Guide to Guns  
- Controlling Nasty Crop Pests and Diseases  
- Growing Herbs at Home  
- Growing Fruit and Veg at Home 1 / 2  
- The Petting Zoo  
- A Day on the Farm  
- From Ore to Store  
- Making Sushi at Home  
- How Electricity Works  
- Emergency First Aid  
- Rosewood Medical First Aid  
- Better Fishing With Jason Master  
- Knapping: The Ancient Art  
- Working Clay at Home  
- Pottery for Anyone  
- A Stitch in Time  
- Adefipe/Adefope Fencing Special  
- Home Welding Guide  

## Verify

Analyze ≥ 1:

1. Random movie VHS → **white** (common)  
2. Woodcraft / Cook Show / listed guides → **blue** (rare)  
3. Unlisted skill-ish titles (if any) → **common** unless on whitelist  

```lua
-- title probe
local it = ... -- VHS item
print(it:getDisplayName(), it:getMediaData() and it:getMediaData():getTitle())
```
