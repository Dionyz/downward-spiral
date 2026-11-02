# Downward Spiral: art spec

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
`_0` is used for about 40% of tiles and the rest are spread across the others, so make `_0` the plain
one and the others subtle variations (cracks, stains, a missing brick). Variants are picked by map
position, so the same tile always looks the same. Unseen tiles are not drawn; remembered but
out-of-sight tiles are drawn darker by the game. The Abyss theme is used on floors 11-20 of every
dungeon. A theme with no files falls back to `spiral`.

## Player sprites

One per class × race: `player/<class>_<race>.png`. Classes: `warrior` (sword and shield, heavy
armor), `thief` (short blade, hood, dark leather), `mage` (staff and robe), `knifer` (shown as
"Jackal": twin knives, light leather). Races: `human`, `dwarf`, `high_elf`, `halfling`, `minotaur`, `lizardman`, `daemon`, `golem`. If a race file is missing the game uses
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


### tiles (85 files)

Map tiles. Drawn edge to edge on a grid, so they must tile seamlessly with their own variants.

| File | What it is |
|---|---|
| `tiles/abyss/corridor_0.png` | abyss, corridor floor (narrow tunnels between rooms), variant 0 |
| `tiles/abyss/corridor_1.png` | abyss, corridor floor (narrow tunnels between rooms), variant 1 |
| `tiles/abyss/corridor_2.png` | abyss, corridor floor (narrow tunnels between rooms), variant 2 |
| `tiles/abyss/corridor_3.png` | abyss, corridor floor (narrow tunnels between rooms), variant 3 |
| `tiles/abyss/corridor_4.png` | abyss, corridor floor (narrow tunnels between rooms), variant 4 |
| `tiles/abyss/corridor_5.png` | abyss, corridor floor (narrow tunnels between rooms), variant 5 |
| `tiles/abyss/corridor_6.png` | abyss, corridor floor (narrow tunnels between rooms), variant 6 |
| `tiles/abyss/floor_0.png` | abyss, room floor, variant 0 |
| `tiles/abyss/floor_1.png` | abyss, room floor, variant 1 |
| `tiles/abyss/floor_2.png` | abyss, room floor, variant 2 |
| `tiles/abyss/floor_3.png` | abyss, room floor, variant 3 |
| `tiles/abyss/floor_4.png` | abyss, room floor, variant 4 |
| `tiles/abyss/floor_5.png` | abyss, room floor, variant 5 |
| `tiles/abyss/floor_6.png` | abyss, room floor, variant 6 |
| `tiles/abyss/floor_7.png` | abyss, room floor, variant 7 |
| `tiles/abyss/wall_0.png` | abyss, wall (solid rock next to a seen floor), variant 0 |
| `tiles/abyss/wall_1.png` | abyss, wall (solid rock next to a seen floor), variant 1 |
| `tiles/abyss/wall_2.png` | abyss, wall (solid rock next to a seen floor), variant 2 |
| `tiles/abyss/wall_3.png` | abyss, wall (solid rock next to a seen floor), variant 3 |
| `tiles/abyss/wall_4.png` | abyss, wall (solid rock next to a seen floor), variant 4 |
| `tiles/abyss/wall_5.png` | abyss, wall (solid rock next to a seen floor), variant 5 |
| `tiles/abyss/wall_6.png` | abyss, wall (solid rock next to a seen floor), variant 6 |
| `tiles/abyss/wall_7.png` | abyss, wall (solid rock next to a seen floor), variant 7 |
| `tiles/black_spiral/corridor_0.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 0 |
| `tiles/black_spiral/corridor_1.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 1 |
| `tiles/black_spiral/corridor_2.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 2 |
| `tiles/black_spiral/corridor_3.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 3 |
| `tiles/black_spiral/corridor_4.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 4 |
| `tiles/black_spiral/corridor_5.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 5 |
| `tiles/black_spiral/corridor_6.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 6 |
| `tiles/black_spiral/corridor_7.png` | black spiral, corridor floor (narrow tunnels between rooms), variant 7 |
| `tiles/black_spiral/floor_0.png` | black spiral, room floor, variant 0 |
| `tiles/black_spiral/floor_1.png` | black spiral, room floor, variant 1 |
| `tiles/black_spiral/floor_2.png` | black spiral, room floor, variant 2 |
| `tiles/black_spiral/floor_3.png` | black spiral, room floor, variant 3 |
| `tiles/black_spiral/floor_4.png` | black spiral, room floor, variant 4 |
| `tiles/black_spiral/floor_5.png` | black spiral, room floor, variant 5 |
| `tiles/black_spiral/floor_6.png` | black spiral, room floor, variant 6 |
| `tiles/black_spiral/floor_7.png` | black spiral, room floor, variant 7 |
| `tiles/black_spiral/wall_0.png` | black spiral, wall (solid rock next to a seen floor), variant 0 |
| `tiles/black_spiral/wall_1.png` | black spiral, wall (solid rock next to a seen floor), variant 1 |
| `tiles/black_spiral/wall_2.png` | black spiral, wall (solid rock next to a seen floor), variant 2 |
| `tiles/black_spiral/wall_3.png` | black spiral, wall (solid rock next to a seen floor), variant 3 |
| `tiles/deep_spiral/corridor_0.png` | deep spiral, corridor floor (narrow tunnels between rooms), variant 0 |
| `tiles/deep_spiral/corridor_1.png` | deep spiral, corridor floor (narrow tunnels between rooms), variant 1 |
| `tiles/deep_spiral/corridor_2.png` | deep spiral, corridor floor (narrow tunnels between rooms), variant 2 |
| `tiles/deep_spiral/corridor_3.png` | deep spiral, corridor floor (narrow tunnels between rooms), variant 3 |
| `tiles/deep_spiral/floor_0.png` | deep spiral, room floor, variant 0 |
| `tiles/deep_spiral/floor_1.png` | deep spiral, room floor, variant 1 |
| `tiles/deep_spiral/floor_2.png` | deep spiral, room floor, variant 2 |
| `tiles/deep_spiral/floor_3.png` | deep spiral, room floor, variant 3 |
| `tiles/deep_spiral/floor_4.png` | deep spiral, room floor, variant 4 |
| `tiles/deep_spiral/floor_5.png` | deep spiral, room floor, variant 5 |
| `tiles/deep_spiral/floor_6.png` | deep spiral, room floor, variant 6 |
| `tiles/deep_spiral/floor_7.png` | deep spiral, room floor, variant 7 |
| `tiles/deep_spiral/wall_0.png` | deep spiral, wall (solid rock next to a seen floor), variant 0 |
| `tiles/deep_spiral/wall_1.png` | deep spiral, wall (solid rock next to a seen floor), variant 1 |
| `tiles/deep_spiral/wall_2.png` | deep spiral, wall (solid rock next to a seen floor), variant 2 |
| `tiles/deep_spiral/wall_3.png` | deep spiral, wall (solid rock next to a seen floor), variant 3 |
| `tiles/deep_spiral/wall_4.png` | deep spiral, wall (solid rock next to a seen floor), variant 4 |
| `tiles/deep_spiral/wall_5.png` | deep spiral, wall (solid rock next to a seen floor), variant 5 |
| `tiles/deep_spiral/wall_6.png` | deep spiral, wall (solid rock next to a seen floor), variant 6 |
| `tiles/deep_spiral/wall_7.png` | deep spiral, wall (solid rock next to a seen floor), variant 7 |
| `tiles/spiral/corridor_0.png` | spiral, corridor floor (narrow tunnels between rooms), variant 0 |
| `tiles/spiral/corridor_1.png` | spiral, corridor floor (narrow tunnels between rooms), variant 1 |
| `tiles/spiral/corridor_2.png` | spiral, corridor floor (narrow tunnels between rooms), variant 2 |
| `tiles/spiral/corridor_3.png` | spiral, corridor floor (narrow tunnels between rooms), variant 3 |
| `tiles/spiral/corridor_4.png` | spiral, corridor floor (narrow tunnels between rooms), variant 4 |
| `tiles/spiral/corridor_5.png` | spiral, corridor floor (narrow tunnels between rooms), variant 5 |
| `tiles/spiral/corridor_6.png` | spiral, corridor floor (narrow tunnels between rooms), variant 6 |
| `tiles/spiral/corridor_7.png` | spiral, corridor floor (narrow tunnels between rooms), variant 7 |
| `tiles/spiral/floor_0.png` | spiral, room floor, variant 0 |
| `tiles/spiral/floor_1.png` | spiral, room floor, variant 1 |
| `tiles/spiral/floor_2.png` | spiral, room floor, variant 2 |
| `tiles/spiral/floor_3.png` | spiral, room floor, variant 3 |
| `tiles/spiral/floor_4.png` | spiral, room floor, variant 4 |
| `tiles/spiral/floor_5.png` | spiral, room floor, variant 5 |
| `tiles/spiral/floor_6.png` | spiral, room floor, variant 6 |
| `tiles/spiral/floor_7.png` | spiral, room floor, variant 7 |
| `tiles/spiral/wall_0.png` | spiral, wall (solid rock next to a seen floor), variant 0 |
| `tiles/spiral/wall_1.png` | spiral, wall (solid rock next to a seen floor), variant 1 |
| `tiles/spiral/wall_2.png` | spiral, wall (solid rock next to a seen floor), variant 2 |
| `tiles/spiral/wall_3.png` | spiral, wall (solid rock next to a seen floor), variant 3 |
| `tiles/stairs_down.png` | stairs down to the next floor (a red X is drawn over it while the boss lives) |
| `tiles/stairs_up.png` | the floor's entrance, where extraction ends |

### objects (4 files)

Things standing on a floor tile (transparent background).

| File | What it is |
|---|---|
| `objects/campfire.png` | campfire (rest to heal) |
| `objects/chest.png` | treasure chest |
| `objects/event.png` | strange event (a gamble with choices) |
| `objects/shrine.png` | shrine (prayed at automatically for a blessing) |

### monsters (12 files)

Monster sprites (transparent background, feet near the bottom, facing right or toward the viewer).

| File | What it is |
|---|---|
| `monsters/carrion_knight.png` | a carrion knight |
| `monsters/cave_spider.png` | a cave spider |
| `monsters/ghoul.png` | a ghoul |
| `monsters/goblin_cutter.png` | a goblin cutter |
| `monsters/gravewarden.png` | the Gravewarden (elite) |
| `monsters/hollow_matron.png` | the Hollow Matron (elite) |
| `monsters/hooded_cultist.png` | a hooded cultist |
| `monsters/orc_brute.png` | an orc brute |
| `monsters/restless_skeleton.png` | a restless skeleton |
| `monsters/sewer_rat.png` | a sewer rat |
| `monsters/spiral_warden.png` | the Spiral Warden (boss) |
| `monsters/wailing_shade.png` | a wailing shade |

### player (32 files)

Player sprites, one per class and race (transparent background).

| File | What it is |
|---|---|
| `player/knifer_daemon.png` | Daemon Jackal |
| `player/knifer_dwarf.png` | Dwarf Jackal |
| `player/knifer_golem.png` | Golem Jackal |
| `player/knifer_halfling.png` | Halfling Jackal |
| `player/knifer_high_elf.png` | High Elf Jackal |
| `player/knifer_human.png` | Human Jackal |
| `player/knifer_lizardman.png` | Lizardman Jackal |
| `player/knifer_minotaur.png` | Minotaur Jackal |
| `player/mage_daemon.png` | Daemon Mage |
| `player/mage_dwarf.png` | Dwarf Mage |
| `player/mage_golem.png` | Golem Mage |
| `player/mage_halfling.png` | Halfling Mage |
| `player/mage_high_elf.png` | High Elf Mage |
| `player/mage_human.png` | Human Mage |
| `player/mage_lizardman.png` | Lizardman Mage |
| `player/mage_minotaur.png` | Minotaur Mage |
| `player/thief_daemon.png` | Daemon Thief |
| `player/thief_dwarf.png` | Dwarf Thief |
| `player/thief_golem.png` | Golem Thief |
| `player/thief_halfling.png` | Halfling Thief |
| `player/thief_high_elf.png` | High Elf Thief |
| `player/thief_human.png` | Human Thief |
| `player/thief_lizardman.png` | Lizardman Thief |
| `player/thief_minotaur.png` | Minotaur Thief |
| `player/warrior_daemon.png` | Daemon Warrior |
| `player/warrior_dwarf.png` | Dwarf Warrior |
| `player/warrior_golem.png` | Golem Warrior |
| `player/warrior_halfling.png` | Halfling Warrior |
| `player/warrior_high_elf.png` | High Elf Warrior |
| `player/warrior_human.png` | Human Warrior |
| `player/warrior_lizardman.png` | Lizardman Warrior |
| `player/warrior_minotaur.png` | Minotaur Warrior |

### items (19 files)

Item pictures for the floor, the bag, the shop and the stash (transparent background).

| File | What it is |
|---|---|
| `items/armor_brigandine.png` | armor: brigandine |
| `items/armor_coat_of_plates.png` | armor: coat of plates |
| `items/armor_cuirass.png` | armor: cuirass |
| `items/armor_hauberk.png` | armor: hauberk |
| `items/armor_jerkin.png` | armor: jerkin |
| `items/gold.png` | gold / coins |
| `items/potion_hp.png` | health potion (also the potion button) |
| `items/potion_mp.png` | mana potion (also the mana button) |
| `items/trinket_amulet.png` | trinket: amulet |
| `items/trinket_charm.png` | trinket: charm |
| `items/trinket_fetish.png` | trinket: fetish |
| `items/trinket_ring.png` | trinket: ring |
| `items/trinket_talisman.png` | trinket: talisman |
| `items/weapon_axe.png` | weapon: axe |
| `items/weapon_dagger.png` | weapon: dagger |
| `items/weapon_mace.png` | weapon: mace |
| `items/weapon_sabre.png` | weapon: sabre |
| `items/weapon_staff.png` | weapon: staff |
| `items/weapon_sword.png` | weapon: sword |

### town (5 files)

Town hub portraits: the building or the NPC who runs it (transparent background).

| File | What it is |
|---|---|
| `town/gate.png` | the Spiral Gate (start a run) |
| `town/inn.png` | the Innkeeper (your characters) |
| `town/shop.png` | the Quartermaster (sells gear) |
| `town/stash.png` | the Stash (shared storage) |
| `town/trainer.png` | the Trainer (sells power-ups) |
