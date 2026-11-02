#!/usr/bin/env python3
"""Write game/assets/art/ART_SPEC.md: the brief an artist works from, with one row per file
the game loads. Run after adding or renaming assets:  python3 tools/art/make_spec.py"""
import json, os

ROOT = os.path.join(os.path.dirname(__file__), "../../game/assets/art")
manifest = json.load(open(os.path.join(ROOT, "manifest.json")))
DATA = os.path.join(os.path.dirname(__file__), "../../game/data")
mons = json.load(open(os.path.join(DATA, "monsters.json")))["monsters"]
races = json.load(open(os.path.join(DATA, "races.json")))
races = races.get("races", races)

WHAT = {
    "tiles": "Map tiles. Drawn edge to edge on a grid, so they must tile seamlessly with their own variants.",
    "objects": "Things standing on a floor tile (transparent background).",
    "monsters": "Monster sprites (transparent background, feet near the bottom, facing right or toward the viewer).",
    "player": "Player sprites, one per class and race (transparent background).",
    "items": "Item pictures for the floor, the bag, the shop and the stash (transparent background).",
    "town": "Town hub portraits: the building or the NPC who runs it (transparent background).",
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
    return DESC.get(name, name)


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

## Not in this folder (UI glyphs)

`game/assets/icons/*.svg` holds small white vector glyphs the game tints: interface arrows, check
mark, drag grip, the "upgrade" arrow, boon and boon-family badges, the trophy badge, and the title
logo. They are UI chrome rather than world art. An artist can redraw them as PNGs too: send a list
and the game can be pointed at them.

## Every file
""" % ", ".join("`%s`" % r for r in races.keys()))

by_folder = {}
for aid in manifest:
    by_folder.setdefault(aid.split("/")[0], []).append(aid)
for folder in ["tiles", "objects", "monsters", "player", "items", "town"]:
    ids = by_folder.get(folder, [])
    out.append("\n### %s (%d files)\n\n%s\n\n| File | What it is |\n|---|---|" % (folder, len(ids), WHAT[folder]))
    for aid in ids:
        out.append("| `%s.png` | %s |" % (aid, describe(aid)))
open(os.path.join(ROOT, "ART_SPEC.md"), "w").write("\n".join(out) + "\n")
print("ART_SPEC.md: %d files" % len(manifest))
