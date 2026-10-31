# Downward Spiral

Single-player Android roguelike: auto-exploration and rule-driven auto combat through short procedural dungeons, with class rules ported from the Devil's Silence MUD. Brief: the v1 spec. Choices the spec left open: `DECISIONS.md`. Open questions: `QUESTIONS.md`.

## Status

| Milestone | State |
| --- | --- |
| 1. Data import | Done. `tools/import_mud_data.py` runs clean against the MUD repo. |
| 2. Headless combat sim | Code and tests written for Warrior and Mage (Thief/Knifer abilities are in too). **Not yet run under Godot** — see QUESTIONS.md Q1. |
| 3. Rules and telegraphs | Code and tests written, same caveat. |
| 4–8 | Not started. |

## Layout

```
game/core/     pure logic, no Nodes: rng, stats, game_data, combatant, ability, factory,
               combat_sim, rules, combat_text
game/data/     classes/abilities/items.json (imported), monsters/balance.json (hand-authored),
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
