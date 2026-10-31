# Downward Spiral

Single-player Android roguelike: auto-exploration and rule-driven auto combat through short procedural dungeons, with class rules ported from the Devil's Silence MUD. Brief: the v1 spec. Choices the spec left open: `DECISIONS.md`. Open questions: `QUESTIONS.md`.

## Status

| Milestone | State |
| --- | --- |
| 1. Data import | Done. Classes and abilities import from the MUD; items are our own (`items.json`). |
| 2. Headless combat sim | Done, all four classes. |
| 3. Rules | Done (telegraphs dropped by owner). |
| 4. Playable text prototype | One floor of 3 fights playable on desktop. Android export pending (QUESTIONS.md). |
| 5–8 | Not started. |

## Layout

```
game/core/     pure logic, no Nodes: rng, stats, game_data, combatant, ability, factory,
               combat_sim, rules, combat_text, loot, encounters
game/scenes/   title, class_select, camp (rule editor), combat, run_end + Game autoload
game/ui/       theme/widgets, combat log, rule editor
game/data/     classes/abilities.json (imported), items/monsters/balance.json (hand-authored),
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

Prototype-floor win rates per class:

```bash
godot --headless --path . -s tools/balance_floor.gd -- --runs 300
```
