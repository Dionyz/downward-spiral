# Downward Spiral

Single-player Android roguelike: auto-exploration and rule-driven auto combat through short procedural dungeons, with class rules ported from the Devil's Silence MUD. Brief: the v1 spec. Choices the spec left open: `DECISIONS.md`. Open questions: `QUESTIONS.md`.

## Status

| Milestone | State |
| --- | --- |
| 1. Data import | Done. Classes and abilities import from the MUD; items are our own (`items.json`). |
| 2. Headless combat sim | Done, all four classes. |
| 3. Rules | Done (telegraphs dropped by owner). |
| 4. Playable text prototype | Done on desktop (Android export deferred by owner). |
| 5. Run loop | Done: 6 Rogue-style floors (random maze levels, monsters on the map), turn combat, loot, boons, events, boss, extraction, death, save/resume. |
| 6. All four classes | Done: 40 boons, boss, 1,000-run balance within 3.7 points. |
| 7. Art and feel | Done on desktop: icons, combat stage animations, screen shake, sound, log toggle. 60 fps on Android unverified. |
| 8. Meta-progression and polish | Done: account levels and unlocks, settings, credits, tutorial tips. |

## Layout

```
game/core/     pure logic, no Nodes: rng, stats, game_data, combatant, ability, factory,
               combat_sim, rules, combat_text, loot, encounters, dungeon_gen, run_state, autopilot, meta
game/scenes/   title, class_select, dungeon (tile map, turn loop, boon/event/floor panels), gear, run_end, settings + Game autoload
game/ui/       theme/widgets, combat log, rule editor, cards, tutorial hints
game/data/     classes/abilities.json (imported); items, monsters, boons, events, rooms, balance (hand-authored);
               overrides/*.json (hand-tuned, merged at load, never touched by the importer)
tools/         import_mud_data.py, combat_log.gd (CLI combat log), balance_run.gd, gen_sfx.py
tests/unit/    GUT tests
addons/gut/    GUT 9.7.1 (MIT), dev-only
game/assets/   icons (game-icons.net, CC BY 3.0) and generated sound (tools/gen_sfx.py)
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

Play in a browser: https://dionyz.github.io/downward-spiral/ (served from the `gh-pages` branch once Pages is enabled).
Rebuild the web version (needs the Godot 4.7.2 source and Emscripten 4.0.11):

```bash
GODOT_SRC=~/tools-src/godot GODOT=~/bin/godot ./tools/build_web.sh
```

Then copy `build/web/*` plus an empty `.nojekyll` to the `gh-pages` branch and push.

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
