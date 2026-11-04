#!/usr/bin/env python3
"""Fill game/assets/art/ with free placeholder pixel art from the Dungeon Crawl Stone Soup
CC0 tile release (https://github.com/crawl/tiles). Every file is written under the name the
game looks for (see game/assets/art/ART_SPEC.md), so an artist's file can later replace it
one-for-one. Writes game/assets/art/manifest.json recording where each placeholder came from.

Usage:  git clone --depth 1 https://github.com/crawl/tiles /tmp/crawl-tiles
        git clone --depth 1 --filter=blob:none --sparse https://github.com/google/fonts /tmp/gfonts
        (cd /tmp/gfonts && git sparse-checkout set ofl/jersey10 ofl/pixelifysans)
        python3 tools/art/import_placeholders.py /tmp/crawl-tiles /tmp/gfonts
Only the curated CC0 releases are used: releases/Nov-2015 and releases/Ancient/Oct-5-2010, minus
every file crawl/tiles lists in TILES_UNDER_UNKNOWN_LICENSE.md. Where that set has nothing that
fits, pixel_art.py draws an original (also CC0). Fonts come from Google Fonts (SIL OFL 1.1).
"""
import glob, json, os, re, shutil, sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixel_art

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/crawl-tiles"
FONTS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/gfonts"
N = os.path.join(SRC, "releases/Nov-2015")
A = os.path.join(SRC, "releases/Ancient/Oct-5-2010")
ROOT = os.path.join(os.path.dirname(__file__), "../../game/assets/art")
manifest = {}
DRAWN = "original, drawn by tools/art/pixel_art.py"
# crawl/tiles names files whose license is unclear; never use one, whatever folder it is in.
UNKNOWN = set()
with open(os.path.join(SRC, "TILES_UNDER_UNKNOWN_LICENSE.md")) as fh:
    for ln in fh:
        if ln.startswith("- ") and ln.strip().endswith(".png"):
            UNKNOWN.add(os.path.basename(ln[2:].strip()))


def _src(path):
    assert os.path.basename(path) not in UNKNOWN, ("unclear license", path)
    return Image.open(path).convert("RGBA")


def save(asset_id, img, source, license="CC0-1.0", size=None):
    if size is not None:
        assert img.size == size, (asset_id, img.size)
    dst = os.path.join(ROOT, asset_id + ".png")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save(dst)
    manifest[asset_id] = {"source": source, "license": license}


def put(asset_id, src_path, note=""):
    save(asset_id, _src(src_path), "crawl/tiles " + os.path.relpath(src_path, SRC), size=(32, 32))


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
# A fire in a stone dish (old spell art, unframed) reads as a camp brazier better than a fire cloud.
put("objects/campfire", os.path.join(A, "spells/fire/sticky_flame.png"))
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
    "hollow_matron": N + "/mon/undead/vampire_mage.png",
    "spiral_warden": N + "/mon/vault_warden.png",
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
            img.alpha_composite(_src(os.path.join(P, l)))
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

# --- frame for icons: the bevelled box every Nov-2015 spell icon sits in -------------------
def _spell_frame():
    """The pixels nearly all Nov-2015 spell icons share (border and bevel), with a black inside."""
    from collections import Counter
    ims = [_src(f) for f in sorted(glob.glob(os.path.join(N, "gui/spells/*/*.png")))]
    fr = Image.new("RGBA", (32, 32))
    for y in range(32):
        for x in range(32):
            fr.putpixel((x, y), Counter(im.getpixel((x, y)) for im in ims).most_common(1)[0][0])
    for y in range(3, 29):
        for x in range(3, 29):
            fr.putpixel((x, y), (0, 0, 0, 255))
    return fr


FRAME = _spell_frame()


def framed(asset_id, src_path):
    """An unframed sprite (old spell art, a white skill silhouette, an item) on the spell-icon frame,
    so every icon in a list has the same backing. The sprite is cropped, never scaled."""
    sp = _src(src_path)
    box = sp.getbbox()
    part = sp.crop(box)
    if part.width > 26 or part.height > 26:
        cx, cy = part.width // 2, part.height // 2
        part = part.crop((max(0, cx - 13), max(0, cy - 13), max(0, cx - 13) + min(26, part.width), max(0, cy - 13) + min(26, part.height)))
    img = FRAME.copy()
    img.alpha_composite(part, (3 + (26 - part.width) // 2, 3 + (26 - part.height) // 2))
    save(asset_id, img, "crawl/tiles %s on the gui/spells frame" % os.path.relpath(src_path, SRC))


def icon(asset_id, ref):
    """ref: 'gui/spells/air/tornado' (Nov-2015, used as is) or a tuple ('framed', path under SRC/releases)."""
    if isinstance(ref, tuple):
        framed(asset_id, os.path.join(SRC, "releases", ref[1] + ".png"))
    else:
        put(asset_id, os.path.join(N, ref + ".png"))


DATA = os.path.join(os.path.dirname(__file__), "../../game/data")
SP = "gui/spells/"
ANC = "Ancient/Oct-5-2010/spells/"
SKL = "Nov-2015/gui/skills/"

# --- skills: one icon per player skill/spell (art/skills/<name with underscores>.png) ----------
SKILLS = {
    "armor": SP + "ice/ozocubus_armour", "backstab": SP + "enchantment/sure_blade",
    "bash": ("framed", "Nov-2015/item/armour/shields/large_shield1"), "berserk": SP + "enchantment/berserker_rage",
    "blinding strike": SP + "conjuration/dazzling_spray", "chain lightning": SP + "air/chain_lightning",
    "charge": "gui/abilities/jump", "circle": SP + "necromancy/excruciating_wounds",
    "cross slash": SP + "transmutation/blade_hands", "dirt kicking": SP + "earth/sandblast",
    "envenom": ("framed", ANC + "poison/poison_brand"), "gouge": SP + "necromancy/pain",
    "haste": SP + "enchantment/haste", "implosion": SP + "translocation/gravitas",
    "kick": ("framed", SKL + "unarmed_combat"), "magic fist": SP + "conjuration/iskenderuns_mystic_blast",
    "sanctuary": "gui/invocations/elyvilon_heal_other", "shield": SP + "ice/condensation_shield",
    "sleep": SP + "ice/ensorcelled_hibernation", "slow": SP + "enchantment/slow",
    "storm of blades": SP + "enchantment/tukimas_dance", "toss daggers": ("framed", SKL + "throwing"),
    "transfix": SP + "earth/petrify", "trip": SP + "earth/ledas_liquefaction",
    "warcry": SP + "enchantment/cause_fear", "whirlwind": SP + "air/tornado",
}
classes = json.load(open(os.path.join(DATA, "overrides/classes.json")))["lines"]
wanted = {str(r["then"]).split(":")[0] for L in classes.values() for r in L.get("ai", [])}
assert wanted <= set(SKILLS), ("skills without an icon", sorted(wanted - set(SKILLS)))
for k, ref in SKILLS.items():
    icon("skills/" + k.replace(" ", "_"), ref)

# --- boons: one icon per boon (art/boons/<id>.png); rarity is a frame the game draws ----------
BOONS = {
    "vampiric_edge": SP + "necromancy/vampiric_draining", "bloodlust": SP + "necromancy/sublimation_of_blood",
    "hemorrhage": ("framed", ANC + "necromancy/lethal_infusion"), "adrenaline": SP + "fire/inner_flame",
    "thick_blood": SP + "necromancy/borgnjors_revivification", "troll_blood": SP + "necromancy/regeneration",
    "static_charge": SP + "air/static_discharge", "keen_eye": SP + "translocation/portal_projectile",
    "flurry": SP + "air/swiftness", "overkill": SP + "earth/lees_rapid_deconstruction",
    "whetstone": "gui/invocations/tso_bless_weapon", "frostbite": SP + "ice/freeze",
    "cold_snap": SP + "ice/ozocubus_refrigeration", "hoarfrost": SP + "ice/freezing_cloud",
    "glacial_edge": SP + "ice/throw_frost", "rot_touch": SP + "necromancy/corpse_rot",
    "virulence": SP + "poison/olgrebs_toxic_radiance", "contagion": SP + "poison/poisonous_cloud",
    "volatile": SP + "fire/fireball", "iron_skin": SP + "earth/stoneskin",
    "bulwark": SP + "translocation/shroud_of_golubria", "spiked_hide": SP + "earth/lehudibs_crystal_spear",
    "last_bastion": SP + "necromancy/deaths_door", "back_to_the_wall": SP + "earth/passwall",
    "counterstrike": SP + "air/deflect_missiles", "last_stand": SP + "necromancy/death_channel",
    "retaliation": SP + "air/repel_missiles", "rampage": SP + "enchantment/song_of_slaying",
    "executioner": SP + "necromancy/symbol_of_torment", "first_blood": SP + "necromancy/agony",
    "shatter": SP + "earth/shatter", "rime_armor": SP + "ice/ice_form",
    "toxic_blood": SP + "poison/venom_bolt", "wither": SP + "poison/poison_arrow",
    "concussive_bash": ("framed", ANC + "earth/maxwells_silver_hammer"), "riposte": ("framed", ANC + "enchantment/tukimas_vorpal_blade"),
    "virulent": SP + "fire/ignite_poison", "forked_bolt": SP + "air/lightning_bolt",
    "deep_well": SP + "conjuration/battlesphere", "war_mender": SP + "necromancy/twisted_resurrection",
    "bone_breaker": SP + "necromancy/animate_skeleton", "evasive_counter": ("framed", SKL + "dodging"),
    "twin_throw": SP + "conjuration/force_lance", "crushing_fist": SP + "earth/iron_shot",
    "soul_siphon": SP + "necromancy/bolt_of_draining", "whirling_blades": SP + "enchantment/spectral_weapon",
    "bleeding_cross": ("framed", ANC + "necromancy/excruciating_wounds"), "heavy_hands": SP + "earth/statue_form",
    "assassins_mark": ("framed", SKL + "stabbing"), "spinning_steel": SP + "translocation/warp_weapon",
    "hamstring": ("framed", ANC + "enchantment/slow"), "mesmerist": SP + "enchantment/confuse",
}
boons = json.load(open(os.path.join(DATA, "boons.json")))
assert set(boons["boons"]) <= set(BOONS), ("boons without an icon", sorted(set(boons["boons"]) - set(BOONS)))
for k, ref in BOONS.items():
    icon("boons/" + k, ref)


# --- UI glyphs: white, tinted by the game (art/ui/<name>.png) ---------------------------------
def white_silhouette(asset_id, src_path):
    """A DCSS skill silhouette (white on transparent with a dark edge), kept as is: tintable."""
    save(asset_id, _src(src_path), "crawl/tiles " + os.path.relpath(src_path, SRC), size=(32, 32))


for name, fn in pixel_art.GLYPHS.items():
    save("ui/" + name, fn(), DRAWN, size=(32, 32))
FAMILY = {"blood": "necromancy", "storm": "air_magic", "frost": "ice_magic", "venom": "poison_magic",
          "iron": "shields", "fury": "fighting"}
assert set(boons["families"]) <= set(FAMILY)
for fam, skill in FAMILY.items():
    white_silhouette("ui/family_" + fam, os.path.join(N, "gui/skills/%s.png" % skill))

# --- status effects: 16 x 16, drawn over map tokens and beside the health bar -------------------
STATUS = {"asleep": "sleeping", "blind": "blind", "poisoned": "poison", "haste": "hasted", "berserk": "might"}
for st, f in STATUS.items():
    p = os.path.join(N, "misc/icons/%s.png" % f)
    save("status/" + st, pixel_art.crop_status(_src(p)), "crawl/tiles %s (cropped to 16 x 16)" % os.path.relpath(p, SRC), size=(16, 16))
for st, fn in pixel_art.STATUS_DRAWN.items():
    save("status/" + st, fn(), DRAWN, size=(16, 16))

# --- hit effects: 2-4 frames each, art/fx/<name>_<frame>.png ------------------------------------
FX = {
    "hit": ["effect/searing_ray0", "effect/searing_ray2", "effect/searing_ray4"],
    "crit": ["effect/searing_ray3", "effect/searing_ray4", "effect/searing_ray5"],
    "bolt": ["effect/magic_dart0", "effect/magic_dart2", "effect/magic_dart4", "effect/magic_dart5"],
    "zap": ["effect/zap0", "effect/zap1", "effect/zap2", "effect/zap3"],
    "frost": ["effect/cloud_cold0", "effect/cloud_cold1", "effect/cloud_cold2"],
    "poison": ["effect/cloud_poison0", "effect/cloud_poison1", "effect/cloud_poison2"],
    "burst": ["effect/cloud_fire0", "effect/cloud_fire1", "effect/cloud_fire2"],
    "dark": ["effect/cloud_neg0", "effect/cloud_neg1", "effect/cloud_neg2"],
}
for name, frames in FX.items():
    for i, f in enumerate(frames):
        put("fx/%s_%d" % (name, i), os.path.join(N, f + ".png"))
for name, (fn, count) in pixel_art.FX_DRAWN.items():
    for i in range(count):
        save("fx/%s_%d" % (name, i), fn(i), DRAWN, size=(32, 32))

# --- UI skin: 9-patch panels, buttons, bars, chips ----------------------------------------------
for name, fn, _margin in pixel_art.UI_SKIN:
    save("ui/" + name, fn(), DRAWN)

# --- fonts (SIL OFL 1.1, from Google Fonts) ------------------------------------------------------
FONT_FILES = {"fonts/jersey10": ("ofl/jersey10/Jersey10-Regular.ttf", "Jersey 10 by Sarah Cadigan-Fried (The Soft Type Project)"),
              "fonts/pixelify_sans": ("ofl/pixelifysans/PixelifySans[wght].ttf", "Pixelify Sans by Stefie Justprince")}
for fid, (rel, who) in FONT_FILES.items():
    src = os.path.join(FONTS, rel)
    dst = os.path.join(ROOT, fid + ".ttf")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    shutil.copyfile(os.path.join(os.path.dirname(src), "OFL.txt"), os.path.join(ROOT, fid + "_OFL.txt"))
    manifest[fid] = {"source": "%s, github.com/google/fonts %s" % (who, rel), "license": "OFL-1.1", "file": fid + ".ttf"}

# --- title logo and the Gate's dungeon banners ---------------------------------------------------
save("ui/title", pixel_art.title_logo(os.path.join(FONTS, FONT_FILES["fonts/jersey10"][0])),
     DRAWN + " (lettering set in Jersey 10, OFL)", size=(192, 56))

BANNERS = {  # theme tiles from the map sets above, two monsters of the dungeon's depth
    "spiral": ("spiral", ["mon/goblin", "mon/undead/skeletal_warrior"]),
    "deep_spiral": ("deep_spiral", ["mon/undead/ghoul", "mon/undead/silent_spectre"]),
    "black_spiral": ("black_spiral", ["mon/death_knight", "mon/vault_warden"]),
    "abyss": ("abyss", ["mon/undead/vampire_mage", "mon/undead/lich"]),
}


def banner(theme, mons):
    """96 x 48: a wall row (half a tile tall) over a floor row, stairs down in the middle and a
    monster either side. Built only from CC0 tiles."""
    img = Image.new("RGBA", (96, 48), (0, 0, 0, 255))
    base = THEMES[theme]
    wall = sorted(glob.glob(os.path.join(N, base["wall"] + "[0-9]*.png")), key=lambda f: int(re.findall(r"(\d+)\.png$", f)[0]))
    floor = sorted(glob.glob(os.path.join(N, base["floor"] + "[0-9]*.png")), key=lambda f: int(re.findall(r"(\d+)\.png$", f)[0]))
    for i in range(3):
        img.alpha_composite(_src(wall[i % len(wall)]).crop((0, 16, 32, 32)), (i * 32, 0))
        img.alpha_composite(_src(floor[(i * 2) % len(floor)]), (i * 32, 16))
    img.alpha_composite(_src(os.path.join(A, "dc-dngn/gateways/stone_stairs_down.png")), (32, 16))
    img.alpha_composite(_src(os.path.join(N, mons[0] + ".png")), (0, 16))
    img.alpha_composite(_src(os.path.join(N, mons[1] + ".png")).transpose(Image.FLIP_LEFT_RIGHT), (64, 16))
    return img


for did, (theme, mons) in BANNERS.items():
    save("ui/banner_" + did, banner(theme, mons), "crawl/tiles composition: %s tiles, Ancient stone_stairs_down, %s" % (theme, ", ".join(mons)), size=(96, 48))


with open(os.path.join(ROOT, "manifest.json"), "w") as fh:
    json.dump(dict(sorted(manifest.items())), fh, indent=1)
print("wrote %d assets" % len(manifest))
