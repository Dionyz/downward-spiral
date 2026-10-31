#!/usr/bin/env python3
"""One-way import of Devil's Silence MUD data into Downward Spiral's game/data/.

Usage:
    python3 tools/import_mud_data.py --mud /path/to/devils-silence-resurrected

Reads (never writes) the MUD repo:
    Data/class_db.json   class names and indices
    Data/skill_db.json   beats, min_mana, target, per-class level requirements

Writes:
    game/data/classes.json
    game/data/abilities.json

Item stats are our own (game/data/items.json, hand-authored); the MUD's item data is not imported.

Never touches game/data/overrides/. Hand-tuned values live there and are merged at load time.

Ability *effects* are ported by reading the C functions named in each entry's `source` field.
The numbers below are transcribed from those functions; no C code or message text is copied.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "data"

# ---------------------------------------------------------------------------
# Class lines. Tier 2 = base index + 18, tier 3 = base index + 36 (class_db order).
# Player-facing names are the MUD's generic fantasy names; see DECISIONS.md D-003.
# ---------------------------------------------------------------------------
CLASS_LINES = {
    "warrior": {"display": "Warrior", "line_name": "Knight", "role": "Tank, steady damage", "resource": "cooldowns"},
    "thief": {"display": "Thief", "line_name": "Blade", "role": "Burst from an opener, debuffs", "resource": "cooldowns"},
    "mage": {"display": "Mage", "line_name": "Sorcerer", "role": "Spell damage, control, self-buffs", "resource": "mana"},
    "knifer": {"display": "Jackal", "line_name": "Tarantella", "role": "Fast multi-hit, stances", "resource": "cooldowns"},
}

# Player-facing tier names that replace distinctive Devil's Silence names (DECISIONS.md D-027).
TIER_NAMES = {"knifer": ["Jackal", "Harlequin", "Tarantella"]}

# Abilities a line gets that the MUD doesn't give it: {ability: {mud_class: MUD level}}.
EXTRA_UNLOCKS = {"sidestep": {"thief": 21, "mercenary": 11, "blade": 1}}

# Spec "Classes for v1" table. Passives the line starts with; actives it starts with; signature unlocks.
CLASS_KITS = {
    "warrior": {
        "passives": ["enhanced damage", "parry", "shield block", "second attack", "third attack", "stun"],
        "starting_actives": ["bash", "kick"],
        "signature": ["berserk", "warcry", "charge", "dirt kicking", "trip"],
        "starting_weapon": "sword", "offhand": "shield",
    },
    "thief": {
        "passives": ["dodge", "sidestep", "second attack", "dual wield", "third attack", "parry", "critical hit"],
        "starting_actives": ["backstab", "dirt kicking"],
        "signature": ["trip", "envenom", "circle", "gouge", "toss daggers", "kick"],
        "starting_weapon": "dagger", "offhand": "dagger",
    },
    "mage": {
        "passives": [],
        "starting_actives": ["magic fist", "shield"],
        "signature": ["armor", "sleep", "slow", "implosion", "chain lightning", "sanctuary", "haste"],
        "starting_weapon": "dagger", "offhand": None,
    },
    "knifer": {
        "passives": ["dodge", "parry", "second attack", "dual wield", "third attack"],
        "starting_actives": ["whirlwind", "dance"],
        "signature": ["blinding strike", "storm of blades", "cross slash", "transfix", "trip", "kick"],
        "starting_weapon": "sabre", "offhand": "dagger",
    },
}


# ---------------------------------------------------------------------------
# Ported ability effects. Keyed by MUD skill name. `source` names the C function.
#   handler: which CombatSim handler runs it (see game/core/combat_sim.gd)
# Numbers use MUD "level" = in-run level * balance.level_scale (default 10).
# ---------------------------------------------------------------------------
PORTED = {
    # ----- passives -----
    "enhanced damage": {"kind": "passive", "source": "fight.c:one_hit", "effect": {"damage_mult_on_roll": 0.5}},
    "parry": {"kind": "passive", "source": "fight.c:check_parry", "effect": {"divisor": 3, "min": 10, "max": 50}},
    "dodge": {"kind": "passive", "source": "fight.c:check_dodge", "effect": {"divisor": 2, "min": 10, "max_by_size": {"tiny": 90, "small": 80, "medium": 70, "large": 60, "huge": 50, "giant": 40}}},
    "shield block": {"kind": "passive", "source": "fight.c:check_shield_block", "effect": {"min": 10, "max": 66}},
    "sidestep": {"kind": "passive", "source": "fight.c:check_sidestep", "effect": {"divisor": 2, "min": 10, "max": 50}},
    "second attack": {"kind": "passive", "source": "fight.c:multi_hit", "effect": {"num": 2, "den": 3, "slow_num": 2, "slow_den": 3}},
    "third attack": {"kind": "passive", "source": "fight.c:multi_hit", "effect": {"num": 1, "den": 2, "slow_num": 1, "slow_den": 2, "minus_fail": True}},
    "fourth attack": {"kind": "passive", "source": "fight.c:multi_hit", "effect": {"num": 4, "den": 5, "slow_num": 1, "slow_den": 2, "minus_fail": True}},
    "dual wield": {"kind": "passive", "source": "fight.c:multi_hit", "effect": {"num": 2, "den": 3, "add": 33}},
    "critical hit": {"kind": "passive", "source": "fight.c:one_hit", "effect": {"gate_pct": 15, "damage_mult": 0.5}},
    "stun": {"kind": "passive", "source": "act_combat.c:do_bash",
             "effect": {"chance_div": 4, "warrior_line_div": 2, "duration_dice": [1, 2]},
             "note": "In the MUD stun is a rider on bash/shield smash, not a command. See DECISIONS.md D-011."},

    # ----- warrior line -----
    "bash": {"kind": "active", "source": "act_combat.c:do_bash", "handler": "bash", "target": "enemy",
             "params": {"dam_min_level_div": 2, "dam_max_level_mult": 1, "knockdown_rounds": 1,
                        "chance_mods": {"str": 1, "victim_dex": -1, "level_diff": 1, "standing_victim": -5}}},
    "kick": {"kind": "active", "source": "act_combat.c:do_kick", "handler": "direct_damage", "target": "enemy",
             "params": {"dam_min_level_mult": 1, "dam_max_level_mult": 2, "dam_type": "bash"}},
    "berserk": {"kind": "active", "source": "act_combat.c:do_berserk", "handler": "berserk", "target": "self",
                "params": {"heal_level_mult": 2, "duration_level_div": 8, "mod_level_div": 4, "fighting_bonus": 10, "flat_bonus": 25, "min_chance": 10},
                "status": "berserk"},
    "warcry": {"kind": "active", "source": "act_combat.c:do_warcry", "handler": "buff", "target": "self",
               "params": {"status": "warcry", "hitroll_level_div": 2, "damroll_level_div": 2, "duration_rounds": 8},
               "status": "warcry"},
    "charge": {"kind": "active", "source": "act_combat.c:do_charge", "handler": "opener_round", "target": "enemy",
               "params": {"min_victim_hp_frac": 0.3334, "sword_damroll_level_div": 4,
                          "weapon_scale": {"preferred": "sword", "min_pct": [1.9, 2.4], "max_pct": [3.0, 5.0]}}},

    # ----- thief line -----
    "backstab": {"kind": "active", "source": "act_combat.c:do_backstab", "handler": "opener_round", "target": "enemy",
                 "params": {"min_victim_hp_frac": 0.3334, "needs_weapon": True,
                            "weapon_scale": {"preferred": "dagger", "min_pct": [2.0, 2.4], "max_pct": [5.0, 5.5]}},
                 "tags": ["opener"]},
    "circle": {"kind": "active", "source": "act_combat.c:do_circle", "handler": "opener_round", "target": "enemy",
               "params": {"min_victim_hp_frac": 0.2, "needs_weapon": True,
                          "weapon_scale": {"preferred": "dagger", "min_pct": [2.9, 3.3], "max_pct": [4.0, 4.4]}}},
    "dirt kicking": {"kind": "active", "source": "act_combat.c:do_dirt", "handler": "debuff", "target": "enemy",
                     "params": {"status": "blind", "duration_rounds": 2, "dam": [2, 5], "chance_mods": {"dex_x5": True, "level_diff": 1},
                                "hitroll_level_div": 4}},
    "trip": {"kind": "active", "source": "act_combat.c:do_trip", "handler": "trip", "target": "enemy",
             "params": {"knockdown_rounds": 1, "dam_size_mult": 2, "chance_mods": {"dex": 1, "victim_dex_x1_5": True, "level_diff_x2": True}}},
    "gouge": {"kind": "active", "source": "act_combat.c:do_gouge", "handler": "debuff", "target": "enemy",
              "params": {"status": "blind", "duration_rounds": 3, "dam": [2, 5], "chance_mods": {"dex_x5": True, "level_diff": 1}}},
    "envenom": {"kind": "active", "source": "act_obj.c:do_envenom", "handler": "envenom", "target": "self",
                "params": {"status": "envenomed", "duration_rounds": 6, "poison_rounds": 3, "poison_dmg_level_div": 10, "damroll_level_div": 10}},
    "toss daggers": {"kind": "active", "source": "act_combat.c:do_toss", "handler": "strike", "target": "enemy",
                     "params": {"swings": 1, "chance_num": 4, "chance_den": 5, "max_bonus_frac": 1.25}},

    # ----- mage line -----
    "magic fist": {"kind": "active", "source": "magic.c:spell_magic_fist", "handler": "spell_damage", "target": "enemy",
                   "params": {"dam_flat_min": 50, "dam_flat_max": 125, "dam_max_level_mult": 2, "dam_type": "bash"}},
    "implosion": {"kind": "active", "source": "magic.c:spell_implosion", "handler": "spell_damage", "target": "enemy",
                  "params": {"dice_level": 16, "save_mult": 0.75, "dam_type": "other"}},
    "chain lightning": {"kind": "active", "source": "magic.c:spell_chain_lightning", "handler": "chain_lightning", "target": "enemy",
                        "params": {"dice_level": 12, "save_mult": 0.5, "level_decrement": 8, "dam_type": "lightning"}},
    "shield": {"kind": "active", "source": "magic.c:spell_shield", "handler": "buff", "target": "self",
               "params": {"status": "shield", "ac": -20, "duration_rounds": 12}},
    "armor": {"kind": "active", "source": "magic.c:spell_armor", "handler": "buff", "target": "self",
              "params": {"status": "armor", "ac": -20, "duration_rounds": 12}},
    "sanctuary": {"kind": "active", "source": "magic.c:spell_sanctuary", "handler": "buff", "target": "self",
                  "params": {"status": "sanctuary", "duration_base": 2, "duration_level_div": 6}},
    "haste": {"kind": "active", "source": "magic.c:spell_haste", "handler": "buff", "target": "self",
              "params": {"status": "haste", "duration_level_div": 2, "dispels": ["slowed"]}},
    "sleep": {"kind": "active", "source": "magic.c:spell_sleep", "handler": "spell_status", "target": "enemy",
              "params": {"status": "asleep", "duration_rounds": 2, "save": True}},
    "slow": {"kind": "active", "source": "magic.c:spell_slow", "handler": "spell_status", "target": "enemy",
             "params": {"status": "slowed", "duration_level_div": 10, "save": True, "dispels": ["haste"]}},

    # ----- knifer line -----
    "whirlwind": {"kind": "active", "source": "act_combat.c:do_whirlwind", "handler": "aoe_strike", "target": "all_enemies",
                  "params": {"bonus_two_over": 90, "bonus_one_over": 50,
                             "weapon_scale": {"preferred": None, "min_pct": [1.5, 1.5], "max_pct": [1.5, 1.5]}}},
    "storm of blades": {"kind": "active", "source": "act_combat.c:do_storm", "handler": "aoe_strike", "target": "all_enemies",
                        "params": {"requires_stance": "storm", "bonus_three_over": 90, "bonus_two_over": 50,
                                   "weapon_scale": {"preferred": None, "min_pct": [1.7, 1.7], "max_pct": [1.4, 1.4]}}},
    "cross slash": {"kind": "active", "source": "act_combat.c:do_cross_slash", "handler": "opener_round", "target": "enemy",
                    "params": {"min_victim_hp_frac": 0.1, "needs_dual": True, "stops_before_haste": True,
                               "weapon_scale": {"preferred": "sabre", "min_pct": [1.25, 2.25], "max_pct": [1.25, 2.25]}}},
    "blinding strike": {"kind": "active", "source": "act_combat.c:do_blinding_strike", "handler": "debuff", "target": "enemy",
                        "params": {"status": "blind", "duration_rounds": 2, "dam": [2, 5], "chance_mods": {"dex": 1, "victim_dex_x2": True, "level_diff_x5": True}, "hitroll": -4}},
    "transfix": {"kind": "active", "source": "act_combat.c:do_transfix", "handler": "transfix", "target": "enemy",
                 "params": {"stun_rounds_range": [1, 3], "then_attack": True}},
}

# Dance (stance) is a DS original. Command is `do_dance`; modifiers from get_char_min/max,
# check_parry and check_dodge. No skill_db entry exists for it.
DANCE = {
    "name": "dance", "kind": "active", "source": "act_combat.c:do_dance", "handler": "stance", "target": "self",
    "beats": 12, "min_mana": 0, "mud_target": "self",
    "stances": {
        "mist": {"damage_mult": 0.3334, "dodge": 15, "parry": 0, "source": "fight.c:get_char_min,check_dodge"},
        "storm": {"damage_mult": 1.3334, "dodge": -15, "parry": -15, "source": "fight.c:get_char_min,check_parry,check_dodge"},
        "cobra": {"damage_mult": 0.9, "dodge": -10, "parry": 15, "source": "fight.c:get_char_min,check_parry,check_dodge"},
        "predator": {"damage_mult": 1.1, "dodge": 10, "parry": 0, "source": "fight.c:get_char_min,check_dodge"},
    },
    "unlock": {"knifer": 1, "tumbler": 1, "wardancer": 1},
}


def run_level(mud_level: int | None) -> int | None:
    if mud_level is None:
        return None
    if mud_level > 101:
        return None  # immortal-only
    return max(1, math.ceil(mud_level / 10))


def load_json(p: Path):
    with p.open(encoding="utf-8") as f:
        return json.load(f)


def import_classes(mud: Path) -> dict:
    cdb = load_json(mud / "Data" / "class_db.json")
    order = cdb["meta"]["class_order"]
    out = {"_generated_by": "tools/import_mud_data.py", "lines": {}}
    for base, info in CLASS_LINES.items():
        bi = order.index(base)
        tiers = [order[bi], order[bi + 18], order[bi + 36]]
        kit = CLASS_KITS[base]
        out["lines"][base] = {
            **info,
            "tiers": [{"tier": i + 1, "mud_class": t, "mud_index": cdb["classes"][t]["index"],
                       "name": TIER_NAMES.get(base, [None] * 3)[i] or t.replace("_", " ").title(), "prime_stat": cdb["classes"][t]["prime_stat"],
                       "gains_mana": cdb["classes"][t]["gains_mana"]} for i, t in enumerate(tiers)],
            **kit,
        }
    return out


def import_abilities(mud: Path, classes: dict) -> dict:
    sdb = load_json(mud / "Data" / "skill_db.json")["spells"]
    out = {"_generated_by": "tools/import_mud_data.py", "abilities": {}}
    tier_classes = {line: [t["mud_class"] for t in v["tiers"]] for line, v in classes["lines"].items()}
    missing = []
    for name, port in PORTED.items():
        entry = sdb.get(name)
        if entry is None:
            missing.append(name)
            continue
        unlock = {}
        for line, tcs in tier_classes.items():
            for tc in tcs:
                lvl = run_level(entry["level_reqs"].get(tc))
                if lvl is not None:
                    unlock[tc] = lvl
        for tc, mud_lvl in EXTRA_UNLOCKS.get(name, {}).items():
            unlock[tc] = run_level(mud_lvl)
        out["abilities"][name] = {
            "id": name.replace(" ", "_"),
            "name": name,
            "kind": port["kind"],
            "source": port["source"],
            "handler": port.get("handler"),
            "target": port.get("target"),
            "beats": entry["beats"],
            "min_mana": entry["min_mana"],
            "mud_target": entry["target"],
            "unlock": unlock,  # mud class name -> in-run level
            "params": port.get("params", {}),
            "effect": port.get("effect", {}),
            "tags": port.get("tags", []),
            **({"note": port["note"]} if "note" in port else {}),
        }
    d = dict(DANCE)
    d["id"] = "dance"
    out["abilities"]["dance"] = {
        "id": "dance", "name": "dance", "kind": "active", "source": d["source"], "handler": d["handler"],
        "target": d["target"], "beats": d["beats"], "min_mana": 0, "mud_target": "self", "unlock": d["unlock"],
        "params": {"stances": d["stances"], "default_stance": "predator"},
        "effect": {}, "tags": ["stance"],
    }
    if missing:
        print(f"WARNING: skills not in skill_db.json: {missing}", file=sys.stderr)
    return out


def write(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, sort_keys=False)
        f.write("\n")
    print(f"wrote {path.relative_to(ROOT)}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mud", required=True, type=Path, help="path to devils-silence-resurrected checkout")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args(argv)
    mud = args.mud.resolve()
    if not (mud / "Data" / "skill_db.json").exists():
        ap.error(f"{mud} does not look like the MUD repo (no Data/skill_db.json)")
    classes = import_classes(mud)
    abilities = import_abilities(mud, classes)
    write(args.out / "classes.json", classes)
    write(args.out / "abilities.json", abilities)
    bad = [k for k, v in abilities["abilities"].items() if not v.get("source")]
    if bad:
        print(f"ERROR: abilities without source: {bad}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
