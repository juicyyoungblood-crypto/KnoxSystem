# D.Storage scripts (B42) — skill max 8 (live)

File: `42/media/scripts/items_knox_dstorage.txt`

## Skill (live)

- **D. Storage** max **8**, **5 SP** / level  
- Reason: B42 custom bag **Capacity ~49** hard ceiling  
- L9–L10 **item scripts retained** (unused) for a future capacity framework  
- Live capacity clamp: **≤49** (L8 formula would be 50)

| Level | Capacity (live) | Right | Left |
|------:|----------------:|-------|------|
| 1 | 20 | DimensionalStorage / R | — |
| 2 | 20 | | DimensionalStorageLeft / L |
| 3 | 25 | R3 | L3 |
| 4 | 30 | R4 | L4 |
| 5 | 35 | R5 | L5 |
| 6 | 40 | R6 | L6 |
| 7 | 45 | R7 | L7 |
| 8 | **49** (clamp) | R8 | L8 |
| 9–10 | scripts only | R9–10 | L9–10 |

## Level-up

Transfer contents old → new; delete old when empty.
