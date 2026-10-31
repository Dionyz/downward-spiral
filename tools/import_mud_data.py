#!/usr/bin/env python3
"""One-way import of Devil's Silence MUD data into Downward Spiral's game/data/.

Usage:
    python3 tools/import_mud_data.py --mud /path/to/devils-silence-resurrected

Reads (never writes) the MUD repo:
    Data/class_db.json   class names and indices
    Data/skill_db.json   beats, min_mana, target, per-class level requirements
    Game/Resurrected/data/area/*.are   weapon and armor stats (see DECISIONS.md D-004:
                         Data/weapon_db.json and Data/equip_db.json carry no usable numbers)

Writes:
    game/data/classes.json
    game/data/abilities.json
    game/data/items.json

Never touches game/data/overrides/. Hand-tuned values live there and are merged at load time.

Ability *effects* are ported by reading the C functions named in each entry's `source` field.
The numbers below are transcribed from those functions; no C code or message text is copied.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
from collections import defaultdict
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
    "knifer": {"display": "Knifer", "line_name": "Wardancer", "role": "Fast multi-hit, stances", "resource": "cooldowns"},
}

# Spec "Classes for v1" table. Passives the line starts with; actives it starts with; signature unlocks.
CLASS_KITS = {
    "warrior": {
        "passives": ["enhanced damage", "parry", "shield block", "second attack", "third attack", "stun"],
        "starting_actives": ["bash", "kick"],
        "signature": ["berserk", "warcry", "charge", "dirt kicking", "trip"],
        "starting_weapon": "sword", "offhand": "shield",
    },
    "thief": {
        "passives": ["dodge", "second attack", "dual wield", "third attack", "parry", "critical hit"],
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

# Weapon type numbering from the MUD's weapon type table (value[0]).
WEAPON_TYPES = {
    "exotic": 0, "sword": 1, "dagger": 2, "spear": 3, "mace": 4, "axe": 5, "flail": 6,
    "whip": 7, "polearm": 8, "katana": 9, "sabre": 10, "parrying_blade": 11, "staff": 3,
}

# ---------------------------------------------------------------------------
# Ported ability effects. Keyed by MUD skill name. `source` names the C function.
#   handler: which CombatSim handler runs it (see game/core/combat_sim.gd)
#   answers: telegraph tags this ability answers (Interrupt / Brace / Evade / Outlast)
# Numbers use MUD "level" = in-run level * balance.level_scale (default 10).
# ---------------------------------------------------------------------------
PORTED = {
    # ----- passives -----
    "enhanced damage": {"kind": "passive", "source": "fight.c:one_hit", "effect": {"damage_mult_on_roll": 0.5}},
    "parry": {"kind": "passive", "source": "fight.c:check_parry", "effect": {"divisor": 3, "min": 10, "max": 50},
              "answers": []},
    "dodge": {"kind": "passive", "source": "fight.c:check_dodge", "effect": {"divisor": 2, "min": 10, "max_by_size": {"tiny": 90, "small": 80, "medium": 70, "large": 60, "huge": 50, "giant": 40}}},
    "shield block": {"kind": "passive", "source": "fight.c:check_shield_block", "effect": {"min": 10, "max": 66},
                     "answers": ["brace"], "answer_note": "Requires a shield; braces the wielder against telegraphed blows."},
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
                        "chance_mods": {"str": 1, "victim_dex": -1, "level_diff": 1, "standing_victim": -5}},
             "answers": ["interrupt"]},
    "kick": {"kind": "active", "source": "act_combat.c:do_kick", "handler": "direct_damage", "target": "enemy",
             "params": {"dam_min_level_mult": 1, "dam_max_level_mult": 2, "dam_type": "bash"}},
    "berserk": {"kind": "active", "source": "act_combat.c:do_berserk", "handler": "berserk", "target": "self",
                "params": {"heal_level_mult": 2, "duration_level_div": 8, "mod_level_div": 4, "fighting_bonus": 10, "flat_bonus": 25, "min_chance": 10},
                "status": "berserk", "answers": ["outlast"]},
    "warcry": {"kind": "active", "source": "act_combat.c:do_warcry", "handler": "buff", "target": "self",
               "params": {"status": "warcry", "hitroll_level_div": 2, "damroll_level_div": 2, "duration_rounds": 8},
               "status": "warcry"},
    "charge": {"kind": "active", "source": "act_combat.c:do_charge", "handler": "opener_round", "target": "enemy",
               "params": {"min_victim_hp_frac": 0.3334, "sword_damroll_level_div": 4,
                          "weapon_scale": {"preferred": "sword", "min_pct": [1.9, 2.4], "max_pct": [3.0, 5.0]}},
               "answers": ["outlast"]},

    # ----- thief line -----
    "backstab": {"kind": "active", "source": "act_combat.c:do_backstab", "handler": "opener_round", "target": "enemy",
                 "params": {"min_victim_hp_frac": 0.3334, "needs_weapon": True,
                            "weapon_scale": {"preferred": "dagger", "min_pct": [2.0, 2.4], "max_pct": [5.0, 5.5]}},
                 "tags": ["opener"], "answers": ["outlast"]},
    "circle": {"kind": "active", "source": "act_combat.c:do_circle", "handler": "opener_round", "target": "enemy",
               "params": {"min_victim_hp_frac": 0.2, "needs_weapon": True,
                          "weapon_scale": {"preferred": "dagger", "min_pct": [2.9, 3.3], "max_pct": [4.0, 4.4]}},
               "answers": ["outlast"]},
    "dirt kicking": {"kind": "active", "source": "act_combat.c:do_dirt", "handler": "debuff", "target": "enemy",
                     "params": {"status": "blind", "duration_rounds": 2, "dam": [2, 5], "chance_mods": {"dex_x5": True, "level_diff": 1},
                                "hitroll_level_div": 4},
                     "answers": ["evade"]},
    "trip": {"kind": "active", "source": "act_combat.c:do_trip", "handler": "trip", "target": "enemy",
             "params": {"knockdown_rounds": 1, "dam_size_mult": 2, "chance_mods": {"dex": 1, "victim_dex_x1_5": True, "level_diff_x2": True}},
             "answers": ["interrupt"]},
    "gouge": {"kind": "active", "source": "act_combat.c:do_gouge", "handler": "debuff", "target": "enemy",
              "params": {"status": "blind", "duration_rounds": 3, "dam": [2, 5], "chance_mods": {"dex_x5": True, "level_diff": 1}},
              "answers": ["evade"]},
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
               "params": {"status": "shield", "ac": -20, "duration_rounds": 12, "damage_reduction": 0.15},
               "answers": ["brace"]},
    "armor": {"kind": "active", "source": "magic.c:spell_armor", "handler": "buff", "target": "self",
              "params": {"status": "armor", "ac": -20, "duration_rounds": 12, "damage_reduction": 0.15},
              "answers": ["brace"]},
    "sanctuary": {"kind": "active", "source": "magic.c:spell_sanctuary", "handler": "buff", "target": "self",
                  "params": {"status": "sanctuary", "duration_base": 2, "duration_level_div": 6},
                  "answers": ["outlast", "brace"]},
    "haste": {"kind": "active", "source": "magic.c:spell_haste", "handler": "buff", "target": "self",
              "params": {"status": "haste", "duration_level_div": 2, "dispels": ["slowed"]}},
    "sleep": {"kind": "active", "source": "magic.c:spell_sleep", "handler": "spell_status", "target": "enemy",
              "params": {"status": "asleep", "duration_rounds": 2, "save": True},
              "answers": ["evade", "interrupt"]},
    "slow": {"kind": "active", "source": "magic.c:spell_slow", "handler": "spell_status", "target": "enemy",
             "params": {"status": "slowed", "duration_level_div": 10, "save": True, "dispels": ["haste"]}},

    # ----- knifer line -----
    "whirlwind": {"kind": "active", "source": "act_combat.c:do_whirlwind", "handler": "aoe_strike", "target": "all_enemies",
                  "params": {"bonus_two_over": 90, "bonus_one_over": 50,
                             "weapon_scale": {"preferred": None, "min_pct": [1.5, 1.5], "max_pct": [1.5, 1.5]}}},
    "storm of blades": {"kind": "active", "source": "act_combat.c:do_storm", "handler": "aoe_strike", "target": "all_enemies",
                        "params": {"requires_stance": "storm", "bonus_three_over": 90, "bonus_two_over": 50,
                                   "weapon_scale": {"preferred": None, "min_pct": [1.7, 1.7], "max_pct": [1.4, 1.4]}},
                        "answers": ["outlast"]},
    "cross slash": {"kind": "active", "source": "act_combat.c:do_cross_slash", "handler": "opener_round", "target": "enemy",
                    "params": {"min_victim_hp_frac": 0.1, "needs_dual": True, "stops_before_haste": True,
                               "weapon_scale": {"preferred": "sabre", "min_pct": [1.25, 2.25], "max_pct": [1.25, 2.25]}},
                    "answers": ["outlast"]},
    "blinding strike": {"kind": "active", "source": "act_combat.c:do_blinding_strike", "handler": "debuff", "target": "enemy",
                        "params": {"status": "blind", "duration_rounds": 2, "dam": [2, 5], "chance_mods": {"dex": 1, "victim_dex_x2": True, "level_diff_x5": True}, "hitroll": -4},
                        "answers": ["evade"]},
    "transfix": {"kind": "active", "source": "act_combat.c:do_transfix", "handler": "transfix", "target": "enemy",
                 "params": {"stun_rounds_range": [1, 3], "then_attack": True},
                 "answers": ["interrupt"]},
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
    "answers_by_stance": {"mist": ["evade"], "cobra": ["brace"]},
    "answers": ["evade", "brace"],
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
                       "name": t.replace("_", " ").title(), "prime_stat": cdb["classes"][t]["prime_stat"],
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
            "answers": port.get("answers", []),
            "tags": port.get("tags", []),
            **({"note": port["note"]} if "note" in port else {}),
        }
    d = dict(DANCE)
    d["id"] = "dance"
    out["abilities"]["dance"] = {
        "id": "dance", "name": "dance", "kind": "active", "source": d["source"], "handler": d["handler"],
        "target": d["target"], "beats": d["beats"], "min_mana": 0, "mud_target": "self", "unlock": d["unlock"],
        "params": {"stances": d["stances"], "default_stance": "predator"},
        "effect": {}, "answers": d["answers"], "answers_by_stance": d["answers_by_stance"], "tags": ["stance"],
    }
    if missing:
        print(f"WARNING: skills not in skill_db.json: {missing}", file=sys.stderr)
    return out


# ---------------------------------------------------------------------------
# Area file parsing (ROM/ROT #OBJECTS section). We only read the stat lines.
# ---------------------------------------------------------------------------
FLAG_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"


def read_tilde(lines, i):
    """Read a ~-terminated string starting at lines[i]; return (text, next_i)."""
    buf = []
    while i < len(lines):
        ln = lines[i]
        i += 1
        if ln.rstrip().endswith("~"):
            buf.append(ln.rstrip()[:-1])
            return "\n".join(buf), i
        buf.append(ln)
    return "\n".join(buf), i


def parse_area_objects(path: Path):
    try:
        text = path.read_text(encoding="latin-1")
    except OSError:
        return []
    lines = text.splitlines()
    out = []
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "#OBJECTS")
    except StopIteration:
        return out
    i = start + 1
    while i < len(lines):
        l = lines[i].strip()
        if l == "#0" or (l.startswith("#") and not l[1:].isdigit()):
            break
        if not (l.startswith("#") and l[1:].isdigit()):
            i += 1
            continue
        vnum = int(l[1:])
        i += 1
        try:
            _name, i = read_tilde(lines, i)
            _short, i = read_tilde(lines, i)
            _long, i = read_tilde(lines, i)
            _mat, i = read_tilde(lines, i)
            type_line = lines[i].split(); i += 1
            val_line = lines[i].split(); i += 1
            stat_line = lines[i].split(); i += 1
        except (IndexError, StopIteration):
            break
        if not type_line:
            continue
        item_type = type_line[0]
        wear = type_line[2] if len(type_line) > 2 else ""
        try:
            level = int(stat_line[0])
        except (ValueError, IndexError):
            continue
        rec = {"vnum": vnum, "area": path.name, "type": item_type, "level": level, "wear": wear}
        if item_type == "weapon" and len(val_line) >= 5:
            wtype = val_line[0]
            try:
                rec.update({"weapon_type": wtype, "v1": int(val_line[1]), "v2": int(val_line[2]),
                            "noun": val_line[3], "flags": val_line[4]})
            except ValueError:
                continue
        elif item_type == "armor":
            rec["ac"] = val_line[:4]
        out.append(rec)
    return out


def import_items(mud: Path) -> dict:
    area_dir = mud / "Game" / "Resurrected" / "data" / "area"
    objs = []
    for p in sorted(area_dir.glob("*.are")):
        objs.extend(parse_area_objects(p))
    weapons = [o for o in objs if o.get("weapon_type") in WEAPON_TYPES and 1 <= o["level"] <= 101
               and o["v1"] > 0 and o["v2"] >= o["v1"]]
    # Weapon flag letters (ROM): sharp is the 'F' bit in weapon flags? DS stores flags as letters;
    # we only use the frequency of the sharp/vorpal letters as a hint (D-005).
    by_type_band = defaultdict(list)
    for w in weapons:
        band = min(10, run_level(w["level"]))
        by_type_band[(w["weapon_type"], band)].append((w["v1"], w["v2"]))
    bases = []
    for (wt, band), vals in sorted(by_type_band.items()):
        bases.append({
            "weapon_type": wt, "type_id": WEAPON_TYPES[wt], "band": band, "samples": len(vals),
            "min": int(statistics.median(v[0] for v in vals)),
            "max": int(statistics.median(v[1] for v in vals)),
        })
    armor = [o for o in objs if o["type"] == "armor" and 1 <= o["level"] <= 101]
    return {
        "_generated_by": "tools/import_mud_data.py",
        "_note": "Weapon numbers are medians of real MUD weapons by type and run-level band. "
                 "Names are generated in game; MUD item names are not imported (license note).",
        "weapon_types": WEAPON_TYPES,
        "weapon_bases": bases,
        "weapon_sample_count": len(weapons),
        "armor_sample_count": len(armor),
        "slots": ["weapon", "armor", "trinket"],
    }


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
    items = import_items(mud)
    write(args.out / "classes.json", classes)
    write(args.out / "abilities.json", abilities)
    write(args.out / "items.json", items)
    bad = [k for k, v in abilities["abilities"].items() if not v.get("source")]
    if bad:
        print(f"ERROR: abilities without source: {bad}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
