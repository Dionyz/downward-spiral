#!/usr/bin/env python3
"""Fill game/assets/art/ with free placeholder pixel art from the Dungeon Crawl Stone Soup
CC0 tile release (https://github.com/crawl/tiles). Every file is written under the name the
game looks for (see game/assets/art/ART_SPEC.md), so an artist's file can later replace it
one-for-one. Writes game/assets/art/manifest.json recording where each placeholder came from.

Usage:  git clone --depth 1 https://github.com/crawl/tiles /tmp/crawl-tiles
        python3 tools/art/import_placeholders.py /tmp/crawl-tiles
Only the curated CC0 releases are used: releases/Nov-2015 and releases/Ancient/Oct-5-2010.
"""
import glob, json, os, re, shutil, sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/crawl-tiles"
N = os.path.join(SRC, "releases/Nov-2015")
A = os.path.join(SRC, "releases/Ancient/Oct-5-2010")
ROOT = os.path.join(os.path.dirname(__file__), "../../game/assets/art")
manifest = {}


def put(asset_id, src_path, note=""):
    dst = os.path.join(ROOT, asset_id + ".png")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img = Image.open(src_path).convert("RGBA")
    assert img.size == (32, 32), (src_path, img.size)
    img.save(dst)
    manifest[asset_id] = {"source": "crawl/tiles " + os.path.relpath(src_path, SRC), "license": "CC0-1.0"}


def variants(asset_prefix, pattern):
    files = sorted(glob.glob(pattern), key=lambda f: int(re.findall(r"(\d+)\.png$", f)[0]))
    for i, f in enumerate(files[:8]):
        put("%s_%d" % (asset_prefix, i), f)


# --- map tiles: one set per dungeon theme --------------------------------------
THEMES = {
    "spiral":       {"floor": "dngn/floor/cobble_blood", "corridor": "dngn/floor/grey_dirt", "wall": "dngn/wall/brick_gray"},
    "deep_spiral":  {"floor": "dngn/floor/limestone", "corridor": "dngn/floor/mud", "wall": "dngn/wall/catacombs"},
    "black_spiral": {"floor": "dngn/floor/black_cobalt", "corridor": "dngn/floor/pebble_brown", "wall": "dngn/wall/stone_dark"},
    "abyss":        {"floor": "dngn/floor/demonic_red", "corridor": "dngn/floor/floor_nerves", "wall": "dngn/wall/hell"},
}
for theme, kinds in THEMES.items():
    for kind, base in kinds.items():
        variants("tiles/%s/%s" % (theme, kind), os.path.join(N, base + "[0-9]*.png"))
put("tiles/stairs_down", os.path.join(A, "dc-dngn/gateways/stone_stairs_down.png"))
put("tiles/stairs_up", os.path.join(A, "dc-dngn/gateways/stone_stairs_up.png"))

# --- map objects ---------------------------------------------------------------
put("objects/chest", os.path.join(A, "UNUSED/other/chest2_closed.png"))
put("objects/shrine", os.path.join(N, "dngn/altars/zin.png"))
put("objects/campfire", os.path.join(N, "effect/cloud_fire1.png"))
put("objects/event", os.path.join(N, "dngn/gateways/portal_unknown.png"))

# --- monsters --------------------------------------------------------------------
MON = {
    "sewer_rat": A + "/dc-mon/animals/rat.png",
    "cave_spider": N + "/mon/animals/spider.png",
    "goblin_cutter": N + "/mon/goblin.png",
    "orc_brute": N + "/mon/orc_warrior.png",
    "restless_skeleton": N + "/mon/undead/skeletal_warrior.png",
    "hooded_cultist": N + "/mon/necromancer.png",
    "ghoul": N + "/mon/undead/ghoul.png",
    "wailing_shade": N + "/mon/undead/silent_spectre.png",
    "carrion_knight": N + "/mon/death_knight.png",
    "gravewarden": N + "/mon/undead/lich.png",
    "hollow_matron": N + "/mon/undead/flayed_ghost.png",
    "spiral_warden": N + "/mon/undead/ancient_lich.png",
}
for k, f in MON.items():
    put("monsters/" + k, f)

# --- player: paper-doll layers per race and class -----------------------------------
P = os.path.join(N, "player")
RACES = {"human": "base/human_m.png", "dwarf": "base/dwarf_m.png", "high_elf": "base/elf_m.png",
         "halfling": "base/halfling_m.png", "minotaur": "base/minotaur_brown1_m.png",
         "lizardman": "base/draconian_green_m.png", "daemon": "base/demonspawn_red_m.png", "golem": "base/gargoyle_m.png"}
NO_HELM = {"minotaur", "daemon", "lizardman", "golem"}   # horns / crests
CLASSES = {
    "warrior": (["legs/metal_gray.png", "boots/middle_gray.png", "body/half_plate.png"], "head/helm_plume.png",
                ["hand1/long_sword_slant.png", "hand2/shield_knight_gray.png"], []),
    "thief":   (["legs/pants_black.png", "boots/short_brown2.png", "body/leather_jacket.png"], "head/hood_black2.png",
                ["hand1/short_sword_slant.png"], ["cloak/black.png"]),
    "mage":    (["boots/short_purple.png", "body/robe_blue.png"], "", ["hand1/staff_mage.png"], []),
    "knifer":  (["legs/pants_short_darkbrown.png", "boots/middle_brown.png", "body/leather_stud.png"], "head/bandana_ybrown.png",
                ["hand1/dagger_slant.png", "hand2/misc/dagger.png"], ["cloak/brown.png"]),
}
for race, base in RACES.items():
    for line, (body, head, hands, behind) in CLASSES.items():
        layers = behind + [base] + body + ([head] if head and race not in NO_HELM else []) + hands
        img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        for l in layers:
            img.alpha_composite(Image.open(os.path.join(P, l)).convert("RGBA"))
        aid = "player/%s_%s" % (line, race)
        os.makedirs(os.path.join(ROOT, "player"), exist_ok=True)
        img.save(os.path.join(ROOT, aid + ".png"))
        manifest[aid] = {"source": "crawl/tiles player doll: " + ", ".join(layers), "license": "CC0-1.0"}
    # (no race-less fallback file: the game falls back to <class>_human)

# --- items -----------------------------------------------------------------------
ITEMS = {
    "items/weapon_dagger": N + "/item/weapon/dagger.png", "items/weapon_sword": N + "/item/weapon/long_sword1.png",
    "items/weapon_sabre": N + "/item/weapon/scimitar1.png", "items/weapon_mace": N + "/item/weapon/mace1.png",
    "items/weapon_axe": N + "/item/weapon/hand_axe1.png", "items/weapon_staff": N + "/item/weapon/quarterstaff.png",
    "items/armor_jerkin": N + "/item/armour/leather_armour1.png", "items/armor_brigandine": N + "/item/armour/ring_mail1.png",
    "items/armor_hauberk": N + "/item/armour/scale_mail1.png", "items/armor_cuirass": N + "/item/armour/scale_mail2.png",
    "items/armor_coat_of_plates": N + "/item/armour/plate1.png",
    "items/trinket_charm": N + "/item/amulet/stone1_green.png", "items/trinket_talisman": N + "/item/amulet/face1_gold.png",
    "items/trinket_ring": N + "/item/ring/ruby.png", "items/trinket_amulet": N + "/item/amulet/celtic_blue.png",
    "items/trinket_fetish": N + "/item/amulet/bone_gray.png",
    "items/potion_hp": N + "/item/potion/ruby.png", "items/potion_mp": N + "/item/potion/brilliant_blue.png",
    "items/gold": N + "/item/gold/06.png",
}
for k, f in ITEMS.items():
    put(k, f)

# --- town --------------------------------------------------------------------------
TOWN = {
    "town/stash": A + "/UNUSED/other/chest2_closed.png", "town/shop": N + "/mon/dwarf.png",
    "town/trainer": N + "/mon/deep_elf_blademaster.png", "town/inn": N + "/mon/human.png",
    "town/gate": A + "/dc-dngn/gateways/stone_stairs_down.png",
}
for k, f in TOWN.items():
    put(k, f)

with open(os.path.join(ROOT, "manifest.json"), "w") as fh:
    json.dump(dict(sorted(manifest.items())), fh, indent=1)
print("wrote %d assets" % len(manifest))
