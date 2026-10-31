# Downward Spiral

Single-player Android roguelike: auto-exploration and rule-driven auto combat through short procedural dungeons, with class rules ported from the Devil's Silence MUD. Brief: the v1 spec. Choices the spec left open: `DECISIONS.md`. Open questions: `QUESTIONS.md`.

## Status

| Milestone | State |
| --- | --- |
| 1. Data import | Done. Classes and abilities import from the MUD; items are our own (`items.json`). |
| 2. Headless combat sim | Done, all four classes. |
| 3. Rules | Done (telegraphs dropped by owner). |
| 4. Playable text prototype | Done on desktop (Android export deferred by owner). |
| 5. Run loop | Done: 6 floors, all room types, rewards, items, boons, events, boss, extraction, death, save/resume. |
| 6. All four classes | Done: 40 boons, boss, 1,000-run balance within 6.7 points. |
| 7–8 | In progress. |

## Layout

```
game/core/     pure logic, no Nodes: rng, stats, game_data, combatant, ability, factory,
               combat_sim, rules, combat_text, loot, encounters, dungeon_gen, run_state, autopilot
game/scenes/   title, class_select, dungeon (map + rooms), combat, run_end + Game autoload
game/ui/       theme/widgets, combat log, rule editor
game/data/     classes/abilities.json (imported); items, monsters, boons, events, rooms, balance (hand-authored);
               overrides/*.json (hand-tuned, merged at load, never touched by the importer)
tools/         import_mud_data.py, combat_log.gd (CLI combat log)
tests/unit/    GUT tests
addons/gut/    GUT 9.7.1 (MIT), dev-only
```

## Commands

Re-import MUD data (never touches `game/data/overrides/`):

```bash
python3 tools/import_mud_data.py --mud ../devils-silence-resurrected
```

Run all tests headless (needs Godot 4.7 on PATH, or `GODOT=/path/to/godot`):

```bash
./run_tests.sh
```

Print a full text combat log (milestone 2 deliverable):

```bash
godot --headless --path . -s tools/combat_log.gd -- --class warrior --level 1 --enemy goblin_cutter --count 3 --seed 42
```

## Rules for the code

1. `game/core/` is pure logic and runs headless.
2. One seeded `DSRng` per run, passed in. Same seed + inputs = same fight.
3. The sim returns structured events; `CombatText` renders the log.
4. Game data comes from the one-way importer; tuning lives in `overrides/`.

Play the prototype on desktop:

```bash
godot --path .
```

Smoke-test the whole UI headless (clicks through a run; add `--shots <dir>` under a display to save screenshots):

```bash
godot --headless --path . -- --autoplay warrior
```

Full-run win rates per class (autopilot, default rules):

```bash
godot --headless --path . -s tools/balance_run.gd -- --runs 200
```
