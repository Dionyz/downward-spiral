# Open questions

Running list. Each has the default I picked so work could continue (see `DECISIONS.md`). Answer any you disagree with.

## Blockers

1. **Godot in this sandbox.** No Godot binary is installed, and GitHub release downloads are blocked by the network proxy. I tried to build Godot 4.7.2 from its official source and the permission system denied it. So none of the GDScript has run yet: it's syntax-checked with `gdparse`, and the tests are written against hand-worked numbers, but nothing has executed. Options: (a) allow the source build (~30–40 min on this container), (b) add a Godot binary to the environment's setup script, or (c) you run `./run_tests.sh` locally and paste failures back.
2. **Where should this repo live?** It's a local git repo at `/home/user/downward-spiral` with no remote. I can't create GitHub repos from here. Create an empty repo (e.g. `downward-spiral`) and attach it to the session, and I'll push.

## Spec contradictions

3. **Promotions in v1 or not?** "Misc" says "No promotions yet (v2+)", but the class table, run structure (promote after floors 2 and 4), rule slots (+1 per promotion) and the coverage test all assume tiers 2 and 3. *Default: promotions are in.*
4. **Can the player tap abilities mid-fight?** The "Combat" section says the player can only extract and use potions; the "Combat system" section says the player can tap an ability to queue it. *Default: tap-to-queue is supported by the sim; the UI can hide it.*
5. **Cooldowns from beats.** Literally "beats = rounds" makes bash a 10-round cooldown and circle 24 — once per fight. I used `ceil(beats / 4)` (bash 3, backstab 5, circle 6). *OK, or do you want the literal version?*

## Class kits

6. **Starting actives the MUD gates later.** Whirlwind is MUD level 37 for knifers (in-run L4) and kick is warrior L12 (L2), but the spec lists both as starting actives. *Default: the spec wins; they're available at L1.*
7. **"Stun" isn't a command in the MUD**: it's a passive that adds a stun chance to bash/shield smash. *Default: passive; bash can stun 1–2 rounds. Want a separate active instead?*
8. **Thief has no Brace answer.** Nothing in the spec's thief kit is a shield, parry stance or damage-reduction buff, so the coverage test can't pass for Thief. The MUD's thief line has `disarm` (thief L18 → in-run L2), which would make a natural Brace (disarmed = reduced hit). *Add disarm, or something else?* (Test is marked pending for now.)
9. **Warrior and Mage gaps.** The spec kit gives Warrior no Evade and Mage no Interrupt. I added dirt kicking (MUD warrior L4) and trip to the warrior kit, and counted sleep as an Interrupt for mages since it cancels the wind-up. *OK?*
10. **Cooldown classes paying mana.** In the MUD berserk costs 75 mana, warcry 70, storm of blades 150 (and storm needs 250). *Default: dropped — those classes run on cooldowns only.*

## Combat numbers

11. **Item data source.** `Data/weapon_db.json` has 5 placeholder weapons (all `0d0`) and `equip_db.json` has no stats, so the importer reads the raw `.are` area files instead. *OK to read outside `Data/`?*
12. **Fight size.** "3–10 enemies" with every enemy swinging every round is a swarm, especially for a level-1 mage with 90 HP. *Keep 3–10 (with weaker swarm monsters), or something like 1–4?*
13. **HP/mana between fights.** The spec only restores HP at rest rooms (40%). With 3–5 fights a floor and no regen, runs will mostly die on floor 1–2. *Default: 25% HP and mana back after every fight (`balance.post_fight_regen_pct`).*
14. **Weapon skill proficiency.** The spec's 40% + 10%/level rule, applied to weapon skills, makes every early swing do 40% damage (the MUD multiplies weapon damage by weapon skill). *Default: weapon skills start at 75%, +2/level. Abilities and passives follow the spec.*
15. **Spell damage scale.** Ported straight, magic fist does 50–145 at level 1 vs ~7–15 for a sword swing. *Default: a global `spell_damage_scale` of 0.2 on top of the MUD's −25% spell penalty.* Tuning comes once the balance script exists.
16. **Telegraph damage model.** Telegraphed attacks deal a % of *your* max HP (40–45%), not the monster's damage dice, so they stay meaningful at every level. Outlast-tagged attacks land as a 3-round bleed. *OK?*

## Names and content

17. **Class display names.** Using the MUD's tier names: Warrior → Gladiator → Knight, Thief → Mercenary → Blade, Mage → Wizard → Sorcerer, Knifer → Tumbler → Wardancer. Are "Knifer", "Tumbler" and "Wardancer" distinctive Devil's Silence names you want renamed (spec: "rename anything distinctive"), or are they yours to keep?
18. **Chain lightning backlash.** The MUD's chain lightning arcs back into the caster when only one enemy is left. I ported that faithfully. *Keep it (it's flavorful but punishes mages in 1v1 elite/boss fights) or drop it?*
