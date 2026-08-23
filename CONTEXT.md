# Knox System

Domain language for the Project Zomboid mod **Knox System**: a System-apocalypse / LitRPG reinterpretation of the Knox Event, plus a Personal Level progression layer (stats, skill points, classes).

## Language

### Setting

**Knox System** (mod / product name):
The mod and its in-world framing. The System is what makes the dead rise and what grants survivors Personal progression.
_Avoid_: System Apocalypse (working title only), LitRPG Zomboid

**System**:
The in-world force that causes the dead to rise and that surfaces Personal Level, stats, classes, and related progression to survivors.
_Avoid_: virus (as primary cause), game master, admin

**Knox Event**:
The outbreak as understood in Project Zomboid’s world; in this mod it is reinterpreted as System-driven, not a separate mundane pathogen stacked on top of the System.
_Avoid_: second infection layer, vanilla virus alongside System (as equal causes)

### Death and undeath

**Rising**:
The System turning a dead human into a zombie. Default outcome of human death unless blocked by max Resilience. Distinct from while-alive infection progression.
_Avoid_: infection spawn (unless talking about vanilla under-the-hood implementation), respawn

**The System Has Claimed You**:
Death-screen message when the survivor dies with Resilience below maximum. Corpse may still Rise as a world zombie; the player does not play as a zombie.
_Avoid_: You Died (vanilla message when this rule applies), game over only

**Zombie**:
A human corpse animated by the System after Rising. Animals do not Rise.
_Avoid_: animal zombie, infected animal

**System Infection** (working label for while-alive state):
The while-alive zombification track: vanilla infection mechanics under the hood, reskinned as System. Resilience modifies catch/progress chances; at Resilience 20 the survivor does not contract it.
_Avoid_: virus (as separate lore cause), Knox infection (as a second system)

**Resilience**:
A Personal Stat (max 20). Reduces chance of contracting System Infection while alive (design target 5% per level → immune at 20); increases innate healing speed; at maximum also prevents Rising on death. Lower Resilience does not block Rising.
_Avoid_: immunity (except as casual speech for max Resilience), HP stat

### Progression — Personal layer

**Personal Level**:
The survivor’s System level, shown on the System Tab. Characters start at Personal Level 0 with 0 Personal XP. Design targets use cumulative Personal XP anchors at levels 1, 10, and 100. Distinct from base skill levels.
_Avoid_: character level (ambiguous with PZ), player level (ambiguous), rank (use World Rank for world threat)

**Personal XP**:
Experience that advances Personal Level. Minted when base skill XP is gained, scaled by per-skill weights (mod-option overrides allowed). Level thresholds are fixed Personal XP totals; weights only change earn rate. Quest/System personal-only XP hooks are out of scope for the base layer.
_Avoid_: skill XP (that is base-game skill experience), fame, score

**Skill Point (SP)**:
Currency granted on Personal Level-up (default: 1 SP per level gained). Spendable on base skill levels or Personal Stats. Not spendable on Class Skills in the base design. Grant schedule is data-driven so milestones or skipped levels can be tuned without redesign.
_Avoid_: perk point, trait point, achievement point

**SP Purchase Confirm**:
A button at the bottom of the relevant tab that commits pending Skill Point spends. Plus controls add an unconfirmed increase when SP is available; minus removes an unconfirmed increase. Nothing is spent until Confirm.
_Avoid_: instant spend (as default), spend-on-plus-click

**Personal Stat**:
One of Strength, Endurance, Mind, Resilience — System stats raised with SP (one SP per stat level, max 20 each). Distinct from the base skills named Strength and Fitness. Personal Strength/Endurance multiply effectiveness of those base skills; they do not replace them.
_Avoid_: attribute (unless UI needs it), ability score

**Mind**:
Personal Stat that scales spell damage, mana, and mana regeneration. Always visible; in the base layer it mainly matters for Mage (and later specializations that spend mana). Non-Mage investment is largely a weak choice in MVP.
_Avoid_: intelligence, wisdom

**System Tab**:
The character-screen tab for System progression. Layout: survivor name top-center; two columns under it (left: Strength, Endurance, Mind, Resilience; right: Personal Level, Exp to Next, World Rank, Unspent SP); then the class list (Warrior, Thief, Ranger, Mage, Crafter); then the selected class’s Class Skills, left-aligned.
_Avoid_: Personal Tab (legacy doc name), skill page (vanilla), info tab

**Character Sheet Theme**:
The LitRPG restyle for character-sheet tabs and, in base scope, inventory and crafting UIs: blue panel background with white primary text. Protection and similar meters use dark-grey-to-white ramps. Health may keep a desaturated red–grey severity map for wounds so injury stays readable.
_Avoid_: vanilla brown parchment as the Knox System look; full rainbow meters

**Pending SP Cart**:
Unconfirmed plus/minus adjustments on the Skills tab and System Tab that have not yet been committed by the bottom Confirm button.
_Avoid_: purchased level (until Confirm)

### Progression — base skills via System

**Base Skill**:
A vanilla (or other-mod) Project Zomboid skill on the normal skill list (Carpentry, Axe, etc.).
_Avoid_: class skill, personal skill

**SP Purchase**:
Spending Skill Points to instantly raise a Base Skill by one level, using the tiered SP cost curve (levels 1–2 cost 1 SP each, 3–4 cost 2 each, and so on). Does not spend or refund base skill XP.
_Avoid_: training, boost, effective level (shadow bonus)

**Personal XP Weight**:
Per-base-skill multiplier applied when minting Personal XP from that skill’s XP gains. Defaults by bucket: Combat, Firearm, and Agility 1.0; Survivalist 0.5; Crafting 0.3; Passive 0.25. Overridable in mod options; unknown/mod skills fall back to category default.
_Avoid_: global XP rate (unless a separate sandbox option)

### Classes

**Class**:
A System archetype chosen at Personal Level 10. Grants access to that class’s Class Skills. Choice is permanent in the base design (no respec, no multiclass). MVP fully implements Warrior; other classes may be stubs until later.
_Avoid_: profession (PZ character creation), trait, job

**Class Skill**:
A System skill unlocked by a Class, progressed by its own activity XP rules, shown on the System Tab. Cannot be bought with Skill Points in the base design. Level range matches relevant base skills (normally 0–10, respecting raised caps if present). XP-to-level uses three times the regular (non-passive) base skill XP table. Class Skill XP gains also mint Personal XP at half the Personal XP Weight of a similar base-skill bucket (e.g. a combat-like Class Skill uses 0.5 if combat base skills use 1.0).
_Avoid_: perk, spell (except for specific Mage skills), ability (too vague)

**Warrior**:
The MVP starter Class. Class Skills: Melee Proficiency, Charge, Armored.
_Avoid_: Fighter, Knight (unless later specializations)

**Melee Proficiency**:
Warrior Class Skill. Gains XP from damage dealt to zombies with melee weapons, bare hands, and foot stomps — not from shoves/pushes or firearms. Improves melee attack speed and damage (including stomps). If multiplying base melee skill effectiveness already provides both speed and damage, prefer that single lever; otherwise add the missing lever explicitly.
_Avoid_: weapon mastery (too generic)

**Charge**:
Warrior Class Skill. Key-press dash in facing direction; default keybind **G** (rebindable). Blocked when any stamina/endurance moodle is showing; no cooldown. Stamina cost is a tunable percentage of max stamina that falls with skill level, anchored so uses-from-full-before-first-moodle are: level 1 → 2, level 10 → 4, level 20 → 10 (level 20 for raised caps / future). XP from zombies damaged by the dash (prefer per-zombie damaged count). Higher levels increase dash damage and distance. May bash prebuilt (world) doors only — not player-constructed doors. Pushes zombies aside on contact.
_Avoid_: sprint (vanilla), shoulder check

**Armored**:
Warrior Class Skill. Hybrid XP: passive from worn protection score plus larger gains when worn protection absorbs a hit. Increases worn protection per level. While Uncomfortable, every 5s refunds 6%×level of stress gained that window (stress only; does not cap DISCOMFORT).
_Avoid_: heavy armor (class name), fortitude (Resilience)

**Specialization**:
A deeper Class branch planned at Personal Levels 25 and 50. Out of scope for the base layer. Future specializations may require mana for actives even on non-Mage base classes.
_Avoid_: subclass (until designed), prestige

### Resources (System)

**Mana**:
A System resource used by Mage Class Skills and potentially later specializations across classes. Scaled by Mind. Not a vanilla PZ resource.
_Avoid_: energy (ambiguous with endurance/stamina), MP only in UI shorthand if needed

### World threat

**World Rank**:
The player-facing System Tab readout for how hard the world is. It follows **World Level** (same progression story)—not a second independent formula. Higher means harder Modifier loadouts and higher System Tier pressure.
_Avoid_: Knox Threat Level (legacy), treating Rank as unrelated to World Level, difficulty (sandbox preset)

**World Level**:
The world progression integer that drives System Tier spawn weights, Modifier Loadout intensity, and sprinter unlock (sprinters only at World Level 5+). Design: **time leg** +1 per 3 in-game days (**time leg max +10**) plus **power leg** +1 per 2 average Personal Levels of the relevant roster (**floor**). Example: day 20 and avg PL 15 → 6 + 7 = **13**. **World Level caps at 40** (high-end loadouts and tier weights). Roster average uses a **14-day** activity window (including offline living while in-window).
_Avoid_: Personal Level alone, System Tier, Modifier Tier, silent second Rank formula

**System Tier**:
The base threat band stamped onto a zombie at spawn (Untouched through Apex in the current band set). Frozen for that zombie’s lifetime. Baseline stat package (health, damage, speed, senses). Spawn weights shift with **World Level**. Sprinter chance is a speed flag only when World Level allows sprinters; not a Modifier.
_Avoid_: zombie level, World Rank, World Level (as the zed’s band name), Modifier Tier

**Modifier Potency Rank**:
Percentage-only catalog variants (Thick Skin / Hardened Skin / Heavy Hit / System Hardened). Each rank is its **own catalog row and id** (e.g. `thick_skin`, `thick_skin_2`) with a **fixed Modifier Tier** (I at the family’s base tier, II one tier higher). **II doubles** the base percentage of I. Binary Modifiers and Evolved do not use potency ranks. At most one row from a family in a loadout.
_Avoid_: stacking the same id twice, Evolved II, System Tier as potency

**Elite**:
A promote on top of a System Tier: the zombie has an **Elite Rank** (not a flat yes/no package alone). Living tell: eye glow. Player-facing name for elites is **Elite Rank + “Zombie”** (e.g. Apex Zombie, System Champion Zombie)—this **replaces** System Tier names on elite corpses and elite name presentation. Non-elites still use System Tier names (e.g. Marked Zombie).
_Avoid_: boss (unless named encounter), miniboss spam, showing System Tier name on an elite instead of Elite Rank

**Elite Rank**:
The four-step elite ladder stamped when a zombie is elite-promoted: **(1) Apex**, **(2) Elite**, **(3) System Elite**, **(4) System Champion**. Display forms: **Apex Zombie**, **Elite Zombie**, **System Elite Zombie**, **System Champion Zombie**. Each rank has a fixed stat package (HP, detection, damage taken, knockdown rules; Champion also death-screech). Higher ranks are rarer as World Level rises. **Elite Rank “Apex” is not System Tier Apex** (Untouched–Apex band).
_Avoid_: System Tier Apex (different axis), Modifier Tier, World Level

**Eye Glow**:
Subtle visual on **elite** living zombies only (base design); may intensify with Elite Rank.
_Avoid_: full-body shader spam, glow on every non-elite

**Modifier**:
A named System-touched special on a zombie, shown on Analyze when unlocked. Distinct from System Tier, Elite, Elite Rank, World Level, and sprinter. Stable snake_case ids; short Analyze labels. Some percentage Modifiers have separate potency catalog rows (I/II). Goblin is the sole Tier 0 Modifier.
_Avoid_: Mutation, Elite Mod (umbrella), Trait (PZ), the Knox System product “mod”

**Modifier Tier**:
Catalog rank 1–4 used when building a Modifier Loadout. Tier 4 is elite-only. Separate from System Tier and World Level.
_Avoid_: World Rank, World Level, System Tier

**Modifier Loadout**:
Modifiers stamped at spawn from World Level + Elite rules. Not live-rescaled. High-end elites: exactly six (1× T4, 1–2× T3, 1–2× T2, T1 fill). High-end non-elites: one to three from T1–T3. Low end: non-elites none; elites one or two Tier 1. Hard anti-combos apply. At most one catalog row per potency family.
_Avoid_: player gear build

**Thick Skin**:
Tier 1 percentage Modifier: reduced damage from **blunt** weapons. II row exists at Tier 2 (double %).
_Avoid_: all-weapon DR

**Hardened Skin**:
Tier 1 percentage Modifier: reduced damage from **bladed** weapons. II row at Tier 2. Can coexist with Thick Skin (different family).
_Avoid_: Thick Skin

**Heavy Hit**:
Tier 1 percentage Modifier: increased damage to survivors and to doors/windows. II row at Tier 2.
_Avoid_: Anchored

**Relentless**:
Tier 1 binary Modifier: immune to **knockdown** only. Hard anti-combo with Anchored.
_Avoid_: Anchored

**System Hardened** (Sys.Hardened):
Tier 2 percentage Modifier: reduced damage from **System-tagged** skills/hits. II row at Tier 3 (double %).
_Avoid_: all-source DR

**Anchored**:
Tier 2 binary: immune to knockback, stagger, and knockdown. Hard anti: sprinter, Evolved, Relentless.
_Avoid_: Relentless alone

**Sharp Bones**:
Tier 2: damaging scratch/bite applies bleed.
_Avoid_: infection primary

**Sharp Nose**:
Tier 2: proximity auto-detect in a design radius; **does not require LOS**. Not long memory follow.
_Avoid_: ten-times memory

**Smart**:
Tier 3: if the zombie **thumps an unlocked door, the door opens** (no chance roll). Includes **Vehicle Nest**. After nest restore, about **half a second** before it may lunge/act at the opener.
_Avoid_: seated passenger, driver

**Evolved**:
Tier 4: much higher HP, much lower damage dealt. Hard anti with Anchored. No potency II.
_Avoid_: Elite promote

**Screecher**:
Tier 4: loud alarm while it sees the survivor and is not knocked down. Hard anti with Silent.
_Avoid_: normal groan only

**Silent**:
Tier 3: no usual vocals; notice-by-sound ≈ Deaf harshness. Hard anti with Screecher.
_Avoid_: footsteps-only stealth

**Vehicle Nest**:
Under Smart: unlocked vehicle may absorb a non-chasing zombie (chance on touch), stow identity, remove living zed; on survivor starting to open the door, restore in front with a short no-lunge beat.
_Avoid_: true seat occupancy

**System Skill (damage tag)**:
Knox System combat (class/System-tagged) vs ordinary vanilla swings—for System Hardened and similar.
_Avoid_: every action is System

**Goblin**:
The only **Modifier Tier 0** Modifier. **Rolled first** on every eligible spawn: if Goblin hits, the zombie gets **no** other Modifiers, **no** normal loadout, and **no** Elite Rank promote from the usual path. Rare coward loot-runner (~1 in 500). Flees the survivor; if line of sight stays broken for a design timeout, it despawns. Alone (few nearby zombies) it is a sprinter even before World Level would allow sprinters; in a denser pack it is a fast shambler. On death it always drops two rolls from its own loot table. Can appear from World Level 0.
_Avoid_: loadout filler after other mods, Elite Rank nameplate as the fantasy
