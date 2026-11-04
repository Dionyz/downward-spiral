#!/usr/bin/env python3
"""Write game/assets/art/ART_SPEC.md: the brief an artist works from, with one row per file
the game loads. Run after adding or renaming assets:  python3 tools/art/make_spec.py"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixel_art import UI_SKIN, GLYPHS

ROOT = os.path.join(os.path.dirname(__file__), "../../game/assets/art")
manifest = json.load(open(os.path.join(ROOT, "manifest.json")))
DATA = os.path.join(os.path.dirname(__file__), "../../game/data")
mons = json.load(open(os.path.join(DATA, "monsters.json")))["monsters"]
races = json.load(open(os.path.join(DATA, "races.json")))
races = races.get("races", races)
boons = json.load(open(os.path.join(DATA, "boons.json")))
skills = json.load(open(os.path.join(DATA, "skills.json")))["skills"]
dungeons = {d["id"]: d["name"] for d in json.load(open(os.path.join(DATA, "dungeons.json")))["dungeons"]}
MARGIN = {name: m for name, _fn, m in UI_SKIN}

WHAT = {
    "tiles": "Map tiles. Drawn edge to edge on a grid, so they must tile seamlessly with their own variants.",
    "objects": "Things standing on a floor tile (transparent background).",
    "monsters": "Monster sprites (transparent background, feet near the bottom, facing right or toward the viewer).",
    "player": "Player sprites, one per class and race (transparent background).",
    "items": "Item pictures for the floor, the bag, the shop and the stash (transparent background).",
    "town": "Town hub portraits: the building or the NPC who runs it (transparent background).",
    "boons": "Boon icons, 32 x 32, one per boon. Shown on the boon pick cards, the Boons list and shrine cards, inside a rarity-colored frame the game draws. Opaque square icons (like the placeholders' bevelled frame) or transparent sprites both work. Not tinted.",
    "skills": "Skill and spell icons, 32 x 32, one per skill the Skills screen lists (file name: the skill name with spaces as underscores). Not tinted.",
    "status": "Status effect icons, **16 x 16**, full color, transparent background. Drawn at 16 px in a row over the top of a map token (monsters and the player) and at 32 px (x2) beside the player's health bar. Must read as a silhouette on any floor: keep a 1 px dark outline. Not tinted.",
    "fx": "Hit effects, 32 x 32, transparent, `<name>_<frame>.png` with frames numbered from 0 (2 to 4 frames; the game plays every frame it finds, in order, about 0.06 s each at 1x game speed and faster at higher speeds). Drawn centered on the target tile at tile size, additive-looking art reads best (bright core, darker edge). Not tinted.",
    "ui": "Interface art: white glyphs the game tints, family badges, the 9-patch skin for panels, buttons, bars and chips, the title logo and the Gate banners. See the UI section above for sizes, margins and tinting.",
    "fonts": "Fonts (TTF), with their license next to them.",
}
DESC = {
    "floor": "room floor", "corridor": "corridor floor (narrow tunnels between rooms)", "wall": "wall (solid rock next to a seen floor)",
    "stairs_down": "stairs down to the next floor (a red X is drawn over it while the boss lives)",
    "stairs_up": "the floor's entrance, where extraction ends",
    "chest": "treasure chest", "shrine": "shrine (prayed at automatically for a blessing)", "campfire": "campfire (rest to heal)",
    "event": "strange event (a gamble with choices)",
    "potion_hp": "health potion (also the potion button)", "potion_mp": "mana potion (also the mana button)", "gold": "gold / coins",
    "stash": "the Stash (shared storage)", "shop": "the Quartermaster (sells gear)", "trainer": "the Trainer (sells power-ups)",
    "inn": "the Innkeeper (your characters)", "gate": "the Spiral Gate (start a run)",
}


def describe(aid):
    folder, name = aid.split("/", 1)
    if folder == "tiles":
        parts = name.split("/")
        if len(parts) == 2:
            kind, var = parts[1].rsplit("_", 1)
            return "%s, %s, variant %s" % (parts[0].replace("_", " "), DESC.get(kind, kind), var)
        return DESC.get(name, name)
    if folder == "monsters":
        m = mons.get(name, {})
        tag = " (boss)" if name == "spiral_warden" else (" (elite)" if name in ("gravewarden", "hollow_matron") else "")
        return str(m.get("name", name)) + tag
    if folder == "player":
        line, race = name.split("_", 1)
        disp = {"knifer": "Jackal"}.get(line, line.capitalize())
        return "%s %s" % (races.get(race, {}).get("name", race), disp)
    if folder == "items":
        if name.startswith(("weapon_", "armor_", "trinket_")):
            slot, base = name.split("_", 1)
            return "%s: %s" % (slot, base.replace("_", " "))
    if folder == "boons":
        b = boons["boons"].get(name, {})
        fams = ", ".join(boons["families"][t]["name"] for t in b.get("tags", []))
        cls = (" (%s only)" % ", ".join({"knifer": "Jackal"}.get(l, l.capitalize()) for l in b["lines"])) if b.get("lines") else ""
        return "**%s**%s, %s: %s" % (b.get("name", name), cls, fams, b.get("desc", "").replace("|", "/"))
    if folder == "skills":
        nm = name.replace("_", " ")
        return "**%s**: %s" % (nm.capitalize(), str(skills.get(nm, "")).replace("|", "/"))
    if folder == "status":
        return STATUS_DESC.get(name, name.replace("_", " "))
    if folder == "fx":
        base, frame = name.rsplit("_", 1)
        return "%s, frame %s" % (FX_DESC.get(base, base), frame)
    if folder == "ui":
        if name in GLYPHS:
            return "white tintable glyph: %s" % GLYPH_DESC.get(name, name)
        if name.startswith("family_"):
            fam = boons["families"].get(name[7:], {})
            return "white tintable badge for the %s boon family (tinted %s)" % (fam.get("name", name), fam.get("color", ""))
        if name in MARGIN:
            w = 8 if name.startswith("bar") else (12 if name == "chip" else 16)
            return "9-patch, %d x %d, margin %d px on every side: %s" % (w, w, MARGIN[name], SKIN_DESC.get(name, name))
        if name.startswith("banner_"):
            d = name[7:]
            return "96 x 48 Gate banner for %s" % (dungeons.get(d, "the Abyss button" if d == "abyss" else d))
        if name == "title":
            return "title logo, 192 x 56 (drawn at x2 on the title screen; the text label is hidden when this file exists)"
    if folder == "fonts":
        return manifest[aid].get("source", name)
    return DESC.get(name, name)


STATUS_DESC = {
    "stunned": "stunned (can't act)", "knocked_down": "knocked down", "asleep": "asleep", "blind": "blinded",
    "poisoned": "poisoned (damage each turn)", "bleeding": "bleeding (damage each turn)", "slowed": "slowed",
    "frozen": "frozen", "transfixed": "transfixed (Jackal)", "dazed": "dazed (after a bash or kick: can't use skills)",
    "armor": "player buff: Armor spell", "shield": "player buff: Shield spell", "sanctuary": "player buff: Sanctuary",
    "haste": "player buff: Haste", "berserk": "player buff: Berserk", "warcry": "player buff: Warcry",
    "envenomed": "player buff: Envenom (poisoned blade)",
}
FX_DESC = {
    "slash": "melee hit (slashing, piercing or crushing) on the target", "hit": "impact flash on the target of a melee hit",
    "crit": "critical hit flash (bigger)", "bolt": "spell bolt arriving (generic magic)", "zap": "lightning hit",
    "frost": "cold hit / freeze", "poison": "poison or acid hit", "burst": "fire / explosion / area blast",
    "dark": "negative energy (draining, implosion)", "heal": "heal sparkle on whoever is healed",
    "levelup": "level-up glow on the player",
}
GLYPH_DESC = {
    "ui_up": "arrow up (move a skill up)", "ui_down": "arrow down (move a skill down)", "ui_check": "check mark",
    "ui_grip": "drag grip on skill cards", "ui_upgrade": "upgrade marker (tinted green)", "ui_star": "legendary / mythic power",
    "ui_family": "generic boon-family badge", "boon": "generic boon (fallback when a boon has no icon)",
    "town_trophy": "Abyss trophy (tinted gold)",
}
SKIN_DESC = {
    "panel": "cards and panels", "popup": "tips and tutorial cards (gold edge)", "chip": "the readout chips on the run screen",
    "button": "button, normal", "button_hover": "button, hover / focus", "button_pressed": "button, pressed",
    "button_disabled": "button, disabled", "bar_bg": "bar background (health, mana)",
    "bar_hp": "health bar fill", "bar_mana": "mana bar fill", "bar_xp": "experience / progress bar fill",
    "bar_enemy": "enemy health bar fill", "bar_shield": "boon shield segment on the health bar",
}


out = []
out.append("""# Downward Spiral: art spec

Every picture the game draws comes from this folder. To replace a placeholder, save a new PNG
**under the same path and name** and re-open the project (Godot re-imports it). Nothing else needs to
change. A missing file is not an error: the game falls back to its old flat vector icon, so art can
be delivered in batches.

The current files are free placeholders from the Dungeon Crawl Stone Soup tile set (CC0, public
domain dedication; `manifest.json` lists the source of each one). `tools/art/import_placeholders.py`
rebuilds them; `tools/art/make_spec.py` rebuilds this file from `manifest.json`.

## Format

- **PNG, 32 × 32 pixels**, RGBA, one image per file. No sprite sheets.
- Pixel art. The game scales by whole multiples (×1, ×1.5, ×2) with nearest-neighbor filtering, never
  smoothing, so keep hard pixel edges and avoid anti-aliasing against transparency.
- Transparent background for everything except map tiles, which are fully opaque.
- Don't bake in outlines for selection, rarity or elite status: the game draws rarity frames, elite
  (orange) and boss (red) rings, health bars and the darker "asleep" tint on top.
- Readability over detail: on a phone a tile is about 48 px wide, so a sprite should read at a glance
  as a silhouette.
- Palette: the game's UI is dark (background `#0b0a0e`, panels `#1d1a26`, gold accent `#d6a64f`).
  Darkest dungeon first, then deeper and stranger: The Spiral is worn grey stone, The Deep Spiral
  pale old limestone and catacombs, The Black Spiral black stone, The Abyss red flesh and hellstone.

## Map tiles

Each dungeon theme (`spiral`, `deep_spiral`, `black_spiral`, `abyss`) has three tile kinds:
`floor` (rooms), `corridor` (tunnels) and `wall`. Each kind has **1 to 8 variants** named `_0`, `_1`, ...;
`_0` is used for about 40%% of tiles and the rest are spread across the others, so make `_0` the plain
one and the others subtle variations (cracks, stains, a missing brick). Variants are picked by map
position, so the same tile always looks the same. Unseen tiles are not drawn; remembered but
out-of-sight tiles are drawn darker by the game. The Abyss theme is used on floors 11-20 of every
dungeon. A theme with no files falls back to `spiral`.

## Player sprites

One per class × race: `player/<class>_<race>.png`. Classes: `warrior` (sword and shield, heavy
armor), `thief` (short blade, hood, dark leather), `mage` (staff and robe), `knifer` (shown as
"Jackal": twin knives, light leather). Races: %s. If a race file is missing the game uses
`<class>_human`, so the four human files are the minimum.

## Items

Weapons have one picture per weapon type; armor and trinkets one per base name. Item rarity is shown
by a colored frame the game draws, so draw one picture per type, not per rarity.

## Boons and skills

One 32 x 32 icon per boon (`boons/<boon id>.png`) and per skill (`skills/<skill name>.png`, spaces as
underscores). Boon rarity is a colored frame the game draws around the icon, so draw one icon per
boon, not per rarity. The boon-family badges are in `ui/` (below).

## Status effects

`status/<status>.png`, **16 x 16**. Up to four are shown in a row along the top edge of a map token
(16 px each, the token's own icon is 32 to 64 px), and every status on the player is also shown at
32 px (x2) beside the health bar. Full color, never tinted.

## Hit effects

`fx/<effect>_<frame>.png`, 32 x 32, **2 to 4 frames** numbered from 0, one file per frame (no sheets).
The game plays the frames in order over the target tile, about 0.06 s per frame at 1x speed (faster at
2x and 4x) and then removes the effect. Melee hits play `slash` and then `hit` (`crit` for critical
hits); a spell or ranged hit plays the effect for its damage type (`zap` lightning, `frost` cold,
`poison` poison/acid, `burst` fire and blasts, `dark` negative energy, `bolt` anything else); a heal
plays `heal` on whoever is healed; a level-up plays `levelup` on the player. Adding a frame file (for
example `slash_3.png`) adds a frame; removing them all brings back the old flash.

## UI

**Tinting.** Files listed as *white tintable glyph* or *badge* are drawn white (light grey for
shading) with a dark outline on a transparent background: the game multiplies them by a color
(green for the upgrade arrow, gold for the trophy, the family's color for family badges, the text
color elsewhere), so keep them white, otherwise the tint will be wrong. Everything else in `ui/` is
used as drawn.

**9-patch skin.** `panel`, `chip`, `button*` and `bar*` are 9-patch images: the corners (the margin
on each side, listed per file) are drawn as they are, the edges and the middle stretch. The game
draws them at **x2** (one art pixel = two screen pixels), so a 16 x 16 button with a 4 px margin
becomes 8 px corners on screen. Keep the middle a flat color or a pattern that survives stretching.
Buttons need four states (`button`, `button_hover`, `button_pressed`, `button_disabled`); every tap
target in the game is at least 44 px tall on a 540 x 960 screen whatever the art. Bars: `bar_bg` is
the empty bar, `bar_hp` / `bar_mana` / `bar_xp` / `bar_enemy` the fill, stretched to the current value.

**Title and banners.** `ui/title.png` is the logo on the title screen (192 x 56, drawn x2). The Gate
shows one 96 x 48 banner per dungeon (`ui/banner_<dungeon id>.png`, drawn x2 or x3 to fit the card)
and `ui/banner_abyss.png` on the Abyss button row.

**Fonts.** `fonts/` holds the pixel fonts: Jersey 10 for headings (labels 26 px and up, and the
title logo's lettering) and Pixelify Sans for button text (20 px and up). Body text keeps Godot's default font: no
pixel font tried stayed readable at the 12-15 px the smallest labels reach on a phone. Both fonts are
SIL Open Font License 1.1 (license files next to them). A replacement must be OFL or CC0; keep
the file names or change them in `game/ui/ui.gd`.

The old vector glyphs in `game/assets/icons/*.svg` stay as the fallback when a file here is missing.

## Every file
""" % ", ".join("`%s`" % r for r in races.keys()))

by_folder = {}
for aid in manifest:
    by_folder.setdefault(aid.split("/")[0], []).append(aid)
for folder in ["tiles", "objects", "monsters", "player", "items", "town", "boons", "skills", "status", "fx", "ui", "fonts"]:
    ids = by_folder.get(folder, [])
    out.append("\n### %s (%d files)\n\n%s\n\n| File | What it is |\n|---|---|" % (folder, len(ids), WHAT[folder]))
    for aid in ids:
        out.append("| `%s` | %s |" % (manifest[aid].get("file", aid + ".png"), describe(aid)))
assert set(by_folder) <= set(WHAT), set(by_folder) - set(WHAT)
open(os.path.join(ROOT, "ART_SPEC.md"), "w").write("\n".join(out) + "\n")
print("ART_SPEC.md: %d files" % len(manifest))
