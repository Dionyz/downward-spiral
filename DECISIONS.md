# Decisions

Choices made where the spec was silent or contradicted itself. Each one is the simplest option that kept work moving; anything marked **(Q#)** is also on the open-questions list in `QUESTIONS.md`.

| ID | Decision | Why |
| --- | --- | --- |
| D-001 | No MUD code is compiled or copied. Formulas are re-typed from reading the C; every ported ability carries `source` (`file.c:function`). All log text is original (`game/core/combat_text.gd`). | Spec license note. |
| D-002 | Class indices come from `Data/class_db.json` order (mage=0, cleric=1, thief=2, warrior=3 … knifer=16). Tier 2 = +18, tier 3 = +36 gives warrior→gladiator→knight, thief→mercenary→blade, mage→wizard→sorcerer, knifer→tumbler→wardancer. | Matches the spec's examples. `Documents/DS_SCHEMA_DELTAS.md`'s "canonical" table disagrees (it lists thief=4, mage=5) and is wrong for this file. |
| D-003 | Player-facing class names use the MUD's tier names (Warrior/Gladiator/Knight etc.) because they're generic fantasy terms. | Spec "keep generic fantasy names". |
| D-004 | Item stats are our own, hand-authored in `game/data/items.json` (weapon damage curves by item level, armor AC, trinkets, 5 rarities, affixes, legendary special passives). The MUD's item data is not imported. | Owner call. The MUD's `weapon_db.json`/`equip_db.json` had no usable stats anyway. |
| D-005 | Weapons have a min/max, read directly by the ported `get_char_min/max`. Item level 1–10 = the floor/level it dropped at; deeper drops roll rarer. | Simple progression. |
| D-006 | Cooldown in rounds = `ceil(beats / 12)`, min 1: bash 1, kick 1, backstab 2, circle 2, charge 2. A 1-round cooldown means usable again next round. | Owner: in the MUD bash was ~1–1.5 rounds and circle 2. One combat round is 12 pulses (`PULSE_VIOLENCE`). |
| D-007 | Cooldown classes (Warrior, Thief, Knifer) pay no mana. In the MUD berserk costs 75 mana, warcry 70, storm of blades 150. **(Q12)** | Spec table: their resource is "Cooldowns". |
| D-008 | Weapon skill (sword, dagger…) is 75% at level 1, +2/level, cap 95. Ability/passive proficiency follows the spec (40% +10/level, cap 95). | Owner OK'd. |
| D-009 | MUD "level" inside ported formulas = in-run level × 10 (`balance.level_scale`). | Keeps the C formulas (bash `level/2..level`, `dice(level,16)`) intact. |
| D-010 | The spec's "starting actives" unlock at in-run level 1 even when the MUD gates them later (kick: warrior 12 → L2; whirlwind: knifer 37 → L4). Everything else unlocks at `ceil(MUD level / 10)` at tier 1. | Owner OK'd. |
| D-011 | "stun" is a passive that powers bash's stun rider (warrior line skill/2, others skill/4), 1d2 rounds. | Owner: keep it passive. |
| D-012 | MUD buff durations are in ticks (~30s+). Overrides set round durations: berserk 6, warcry 10, armor/shield 12, sanctuary 6, haste 8, slow 4, sleep 2. Armor/shield spells use AC −400 (the MUD's −20 is meaningless at our scale). | Ticks don't map to a short fight. |
| D-013 | No one-shots: any single enemy hit is capped at 35% of the player's max HP inside `damage()` (`balance.enemy_hit_cap_pct`). | Spec's "no unanswerable one-shots", kept as a plain cap now that telegraphs are gone. |
| D-014 | Telegraphs are removed entirely: no wind-ups, no answer tags, no coverage test. Elites use plain heavy strikes and status attacks instead. | Owner. |
| D-015 | Warrior kit adds dirt kicking and trip (both MUD warrior skills). | Owner OK'd. |
| D-016 | Damage wakes a sleeping target. | Standard design; ROM behaviour here is position-based and doesn't map cleanly. |
| D-017 | Defenses (parry/dodge/block) only apply to normal swings, not to backstab/circle/kick etc. Everyone gets the 10% floor on parry (if armed) and dodge, even at 0 skill. | Faithful to `one_hit()` (defenses only when `dt >= TYPE_HIT`) and the `URANGE(10, …)` clamps. |
| D-018 | Vulnerable = +25% damage, not +50%. | Spec said "+50% (verify)"; `damage()` does `dam += dam/4`. |
| D-019 | Spell damage × `balance.spell_damage_scale` = 0.5, after the MUD's own −25% spell penalty. | Owner: halve it. |
| D-020 | Player acts first in a round (rules, then automatic choice), then enemies (their rules), then auto-attacks: player, then each enemy. Using an ability doesn't cost the auto-attack round. | Spec round order; MUD skills run alongside `multi_hit`. |
| D-021 | Player always targets the first living enemy; "enemy has status / HP below" rules retarget to the matching enemy. | Simplest. |
| D-022 | 2nd/3rd dual (off-hand extra attacks), offhand skill, ironskin, two-handed fumble and the gang-up modifiers are left out of v1. Fifth attack isn't in any v1 kit. | Not in the spec's kits; keeps the sim small. |
| D-023 | RNG is our own Park–Miller generator (`game/core/rng.gd`), not Godot's. | Bit-identical on every platform and Godot version; trivially serializable for save/resume. |
| D-024 | Dance is one ability with an argument: rules say `dance:mist`, `dance:storm`, `dance:cobra`, `dance:predator`. Active stance shows as a status `stance_<name>` so "I don't have buff" works on it. Dance-of-the-devil is left out. | One rule slot per stance switch; no new condition type. |
| D-025 | Chain lightning sweeps all enemies round-robin, −8 levels per hit. The MUD's backlash into the caster is dropped: with one target left the bolt fizzles. | Owner: drop backlash. |
| D-026 | Hand-authored data lives beside the import: `monsters.json`, `balance.json` (and later `boons.json`, `rooms.json`). The importer only writes `classes.json`, `abilities.json`, `items.json`. Tuning goes in `overrides/<file>.json`, deep-merged at load. | Spec rule 4. |
| D-027 | Knifer line is shown to players as **Jackal** (MUD knifer stays the internal id). Tier names don't matter while promotions are out. Stance names (mist, storm, cobra, predator) are generic words and stay. | Owner. |
| D-028 | Thief line gets **sidestep** (MUD knifer skill, `check_sidestep`): extra avoidance roll after shield block, skill/2 clamped 10–50, no floor without the skill. Unlocks thief L3 (in-run). | Owner: give thief another dodge-type skill. |
| D-029 | Classes play themselves. Each round: rules top to bottom; if none fires, the first usable equipped active in equip order (stance only if none is set). No tap-to-queue. Player inputs during a fight: potions and extract. | Owner. |
| D-030 | Promotions are out of scope: every character stays tier 1 all run. Tier data stays in `classes.json` for later. | Owner. |
| D-031 | Fights are 1–4 normal monsters (`balance.fight_size`) or one elite. | Owner. |
| D-032 | Dual wielders wield a matched pair from the single weapon slot (the off-hand copies the main weapon). | Spec has three item slots. |
| D-033 | No HP/mana regen between fights for now. | Owner: get it running first, look at survival later. |
| D-034 | Milestone 4 prototype levels the character up once per won fight (1 → 4 over the floor) so unlocks show up; XP comes with milestone 5. | Makes the one-floor prototype show progression. |
| D-035 | Rule slots: 2 at run start, a 3rd at level 5 (`balance.rule_slots`, `rule_slot_bonus_level`). | Owner. |
