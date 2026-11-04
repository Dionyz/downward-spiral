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

### boons (52 files)

Boon icons, 32 x 32, one per boon. Shown on the boon pick cards, the Boons list and shrine cards, inside a rarity-colored frame the game draws. Opaque square icons (like the placeholders' bevelled frame) or transparent sprites both work. Not tinted.

| File | What it is |
|---|---|
| `boons/adrenaline.png` | **Adrenaline**, Blood, Fury: Below 50% HP, heal for an extra {b_adrenaline}% of the damage you deal. |
| `boons/assassins_mark.png` | **Assassin's Mark** (Thief only), Fury: Backstab and circle deal +50% damage. |
| `boons/back_to_the_wall.png` | **Back to the Wall**, Iron: While 2 or more enemies are on you, take {b_dr_pack}% less damage. (Total damage reduction caps at 90%.) |
| `boons/bleeding_cross.png` | **Bleeding Cross** (Jackal only), Blood: Cross slash leaves the target bleeding for 3 rounds. |
| `boons/bloodlust.png` | **Bloodlust**, Blood: Every kill heals {b_kill_heal}% of your max HP ({kill_heal} HP). |
| `boons/bone_breaker.png` | **Bone Breaker** (Warrior only), Fury: Kick has a 25% chance to stun for a round. |
| `boons/bulwark.png` | **Bulwark**, Iron: After you take damage, gain a shield that absorbs {bulwark} damage for 2 turns. |
| `boons/cold_snap.png` | **Cold Snap**, Frost: +{b_cold_snap}% damage to frozen, stunned or slowed enemies. |
| `boons/concussive_bash.png` | **Concussive Bash** (Warrior only), Frost: Bash also slows the target for 2 rounds. |
| `boons/contagion.png` | **Contagion**, Venom: Each poison tick has a {b_contagion}% chance to spread to another enemy near you, and poisoned enemies spread it to their neighbours when they die. |
| `boons/counterstrike.png` | **Counterstrike**, Iron, Fury: After you parry, dodge or block, {b_riposte}% chance to strike back at once. |
| `boons/crushing_fist.png` | **Crushing Fist** (Mage only), Storm: Magic fist deals +50% damage to enemies above half HP. |
| `boons/deep_well.png` | **Deep Well** (Mage only), Storm: +2 mana regeneration each round. |
| `boons/evasive_counter.png` | **Evasive Counter** (Thief only), Fury: After you dodge or sidestep, your next swing deals +50% damage. |
| `boons/executioner.png` | **Executioner**, Fury: Hits on enemies below 20% HP have a {b_execute}% chance to kill them outright (not bosses). |
| `boons/first_blood.png` | **First Blood**, Fury: Your first hit in each fight deals +{b_first_blood}% damage. |
| `boons/flurry.png` | **Flurry**, Storm, Fury: Each melee turn has a {b_flurry}% chance to strike one extra time. |
| `boons/forked_bolt.png` | **Forked Bolt** (Mage only), Storm: Chain lightning jumps one extra time. |
| `boons/frostbite.png` | **Frostbite**, Frost: Your hits have a {b_freeze}% chance to freeze the target for a turn. |
| `boons/glacial_edge.png` | **Glacial Edge**, Frost: Your hits have a {b_slow_hit}% chance to slow the target for 3 turns. |
| `boons/hamstring.png` | **Hamstring** (Jackal only), Frost: Cross Slash and Blinding Strike also slow the target for 3 turns. |
| `boons/heavy_hands.png` | **Heavy Hands** (Warrior only), Fury: Bash and kick deal +50% damage. |
| `boons/hemorrhage.png` | **Hemorrhage**, Blood, Storm: Critical hits make the target bleed for {bleed} damage a turn for 3 turns. |
| `boons/hoarfrost.png` | **Hoarfrost**, Frost, Iron: Enemies that hit you in melee have a {b_freeze_back}% chance to freeze for a turn. |
| `boons/iron_skin.png` | **Iron Skin**, Iron: Take {b_dr_flat} less damage from every hit. |
| `boons/keen_eye.png` | **Keen Eye**, Storm: +{b_crit}% chance for any hit to crit (crits deal +75%). |
| `boons/last_bastion.png` | **Last Bastion**, Iron: Below 40% HP, take {b_dr_low}% less damage. (Total damage reduction caps at 90%.) |
| `boons/last_stand.png` | **Last Stand**, Iron: Once per run, a killing blow leaves you at 1 HP instead. Each copy works once. |
| `boons/mesmerist.png` | **Mesmerist** (Jackal only), Fury: The attack round after Transfix deals +50% damage. |
| `boons/overkill.png` | **Overkill**, Storm: When you kill, {b_overkill}% of the leftover damage hits another nearby enemy. |
| `boons/rampage.png` | **Rampage**, Fury: Each kill gives +{b_rampage}% damage for 5 turns. Kills stack it and refresh the timer. |
| `boons/retaliation.png` | **Retaliation**, Fury: After you take damage, your next hit deals +{b_retaliate}% damage. |
| `boons/rime_armor.png` | **Rime Armor**, Frost, Iron: While an enemy next to you is frozen, stunned or slowed, take {b_dr_chill}% less damage. (Total damage reduction caps at 90%.) |
| `boons/riposte.png` | **Riposte** (Warrior only), Iron: Each parry adds +5% damage to your next swing, stacking to 5. |
| `boons/rot_touch.png` | **Rot Touch**, Venom: Your hits have a {b_poison}% chance to poison the target: {poison} damage a turn for 3 turns. |
| `boons/shatter.png` | **Shatter**, Frost, Fury: Killing a frozen, stunned or slowed enemy deals {b_shatter}% of its max HP to enemies next to you. |
| `boons/soul_siphon.png` | **Soul Siphon** (Mage only), Blood: Each kill restores 10% of your mana. |
| `boons/spiked_hide.png` | **Spiked Hide**, Iron: Enemies that hit you in melee take {thorns} damage back. |
| `boons/spinning_steel.png` | **Spinning Steel** (Jackal only), Storm: Whirlwind and Storm of Blades deal +{b_aoe_dmg}% damage. |
| `boons/static_charge.png` | **Static Charge**, Storm: Your hits have a {b_zap}% chance to zap a nearby enemy for {zap} lightning damage. |
| `boons/thick_blood.png` | **Thick Blood**, Blood, Iron: +{b_hp_pct}% max HP (+{thick} HP). |
| `boons/toxic_blood.png` | **Toxic Blood**, Venom, Iron: Enemies that hit you in melee have a {b_poison_back}% chance to be poisoned. |
| `boons/troll_blood.png` | **Troll Blood**, Blood: Regenerate {b_regen}% of your max HP every turn ({regen} HP). |
| `boons/twin_throw.png` | **Twin Throw** (Thief only), Storm: Toss daggers throws two blades. |
| `boons/vampiric_edge.png` | **Vampiric Edge**, Blood: Heal for {b_leech}% of all damage you deal. |
| `boons/virulence.png` | **Virulence**, Venom: Poison you inflict deals +{b_poison_amp}% damage. |
| `boons/virulent.png` | **Virulent** (Thief only), Venom: Your poisons deal double damage. |
| `boons/volatile.png` | **Volatile**, Venom, Fury: Slain enemies explode, dealing {b_volatile}% of their max HP to enemies next to you (about {boom} against foes like these). |
| `boons/war_mender.png` | **War Mender** (Warrior only), Blood: Warcry also heals 15% of your max HP. |
| `boons/whetstone.png` | **Whetstone**, Storm: +{b_flat} damage on every hit you land. |
| `boons/whirling_blades.png` | **Whirling Blades** (Jackal only), Storm: Whirlwind always strikes each enemy at least twice. |
| `boons/wither.png` | **Wither**, Venom, Fury: +{b_wither}% damage to poisoned enemies. |

### skills (26 files)

Skill and spell icons, 32 x 32, one per skill the Skills screen lists (file name: the skill name with spaces as underscores). Not tinted.

| File | What it is |
|---|---|
| `skills/armor.png` | **Armor**: A protective spell that improves your armor for 12 turns. |
| `skills/backstab.png` | **Backstab**: A brutal opening strike from the shadows. Best with a dagger. Only on enemies above a third of their HP. |
| `skills/bash.png` | **Bash**: Shoulder-slam an enemy: damage and a chance to knock it down for a turn. |
| `skills/berserk.png` | **Berserk**: Fly into a rage: heal a little and hit harder and more accurately for a while. |
| `skills/blinding_strike.png` | **Blinding strike**: A slash across the eyes that blinds an enemy for 2 turns. |
| `skills/chain_lightning.png` | **Chain lightning**: Lightning that jumps between enemies near you, weaker with each jump. |
| `skills/charge.png` | **Charge**: Rush an enemy up to 4 tiles away and open with a heavy blow. Best with a sword. Only on enemies above a third of their HP. |
| `skills/circle.png` | **Circle**: Slip around an enemy mid-fight and stab it in the back. Best with a dagger. |
| `skills/cross_slash.png` | **Cross slash**: Two-bladed slash that opens a fight with heavy damage. Needs two weapons. |
| `skills/dirt_kicking.png` | **Dirt kicking**: Kick dirt in an enemy's eyes: blinds it for 2 turns, making it miss far more. |
| `skills/envenom.png` | **Envenom**: Coat your weapon in poison for 6 turns: your hits poison enemies. |
| `skills/gouge.png` | **Gouge**: Go for the eyes: blinds an enemy for 3 turns. |
| `skills/haste.png` | **Haste**: Speed yourself up: you act more often for a while. |
| `skills/implosion.png` | **Implosion**: Crush one enemy with a heavy blast of force (range 5). |
| `skills/kick.png` | **Kick**: A quick kick for light damage. Short cooldown, always useful. |
| `skills/magic_fist.png` | **Magic fist**: A cheap punch of raw magic at range 6. Your bread-and-butter spell. |
| `skills/sanctuary.png` | **Sanctuary**: A holy ward that halves all damage you take for a few turns. |
| `skills/shield.png` | **Shield**: A shimmering shield that improves your armor for 12 turns. |
| `skills/sleep.png` | **Sleep**: Put an enemy to sleep for 2 turns (it may resist). Damage wakes it. |
| `skills/slow.png` | **Slow**: Slow an enemy down so it acts less often (it may resist). |
| `skills/storm_of_blades.png` | **Storm of blades**: A whirling flurry of blades that hits every enemy next to you, with bonus swings. |
| `skills/toss_daggers.png` | **Toss daggers**: Throw a dagger at an enemy up to 5 tiles away. |
| `skills/transfix.png` | **Transfix**: Lock eyes with an enemy and stun it for 1 to 3 turns, then strike. |
| `skills/trip.png` | **Trip**: Sweep an enemy's legs: knocks it down for a turn and deals a little damage. |
| `skills/warcry.png` | **Warcry**: A battle shout that raises your accuracy and damage for 8 turns. |
| `skills/whirlwind.png` | **Whirlwind**: Spin and strike every enemy next to you. |

### status (17 files)

Status effect icons, **16 x 16**, full color, transparent background. Drawn at 16 px in a row over the top of a map token (monsters and the player) and at 32 px (x2) beside the player's health bar. Must read as a silhouette on any floor: keep a 1 px dark outline. Not tinted.

| File | What it is |
|---|---|
| `status/armor.png` | player buff: Armor spell |
| `status/asleep.png` | asleep |
| `status/berserk.png` | player buff: Berserk |
| `status/bleeding.png` | bleeding (damage each turn) |
| `status/blind.png` | blinded |
| `status/dazed.png` | dazed (after a bash or kick: can't use skills) |
| `status/envenomed.png` | player buff: Envenom (poisoned blade) |
| `status/frozen.png` | frozen |
| `status/haste.png` | player buff: Haste |
| `status/knocked_down.png` | knocked down |
| `status/poisoned.png` | poisoned (damage each turn) |
| `status/sanctuary.png` | player buff: Sanctuary |
| `status/shield.png` | player buff: Shield spell |
| `status/slowed.png` | slowed |
| `status/stunned.png` | stunned (can't act) |
| `status/transfixed.png` | transfixed (Jackal) |
| `status/warcry.png` | player buff: Warcry |

### fx (36 files)

Hit effects, 32 x 32, transparent, `<name>_<frame>.png` with frames numbered from 0 (2 to 4 frames; the game plays every frame it finds, in order, about 0.06 s each at 1x game speed and faster at higher speeds). Drawn centered on the target tile at tile size, additive-looking art reads best (bright core, darker edge). Not tinted.

| File | What it is |
|---|---|
| `fx/bolt_0.png` | spell bolt arriving (generic magic), frame 0 |
| `fx/bolt_1.png` | spell bolt arriving (generic magic), frame 1 |
| `fx/bolt_2.png` | spell bolt arriving (generic magic), frame 2 |
| `fx/bolt_3.png` | spell bolt arriving (generic magic), frame 3 |
| `fx/burst_0.png` | fire / explosion / area blast, frame 0 |
| `fx/burst_1.png` | fire / explosion / area blast, frame 1 |
| `fx/burst_2.png` | fire / explosion / area blast, frame 2 |
| `fx/crit_0.png` | critical hit flash (bigger), frame 0 |
| `fx/crit_1.png` | critical hit flash (bigger), frame 1 |
| `fx/crit_2.png` | critical hit flash (bigger), frame 2 |
| `fx/dark_0.png` | negative energy (draining, implosion), frame 0 |
| `fx/dark_1.png` | negative energy (draining, implosion), frame 1 |
| `fx/dark_2.png` | negative energy (draining, implosion), frame 2 |
| `fx/frost_0.png` | cold hit / freeze, frame 0 |
| `fx/frost_1.png` | cold hit / freeze, frame 1 |
| `fx/frost_2.png` | cold hit / freeze, frame 2 |
| `fx/heal_0.png` | heal sparkle on whoever is healed, frame 0 |
| `fx/heal_1.png` | heal sparkle on whoever is healed, frame 1 |
| `fx/heal_2.png` | heal sparkle on whoever is healed, frame 2 |
| `fx/hit_0.png` | impact flash on the target of a melee hit, frame 0 |
| `fx/hit_1.png` | impact flash on the target of a melee hit, frame 1 |
| `fx/hit_2.png` | impact flash on the target of a melee hit, frame 2 |
| `fx/levelup_0.png` | level-up glow on the player, frame 0 |
| `fx/levelup_1.png` | level-up glow on the player, frame 1 |
| `fx/levelup_2.png` | level-up glow on the player, frame 2 |
| `fx/levelup_3.png` | level-up glow on the player, frame 3 |
| `fx/poison_0.png` | poison or acid hit, frame 0 |
| `fx/poison_1.png` | poison or acid hit, frame 1 |
| `fx/poison_2.png` | poison or acid hit, frame 2 |
| `fx/slash_0.png` | melee hit (slashing, piercing or crushing) on the target, frame 0 |
| `fx/slash_1.png` | melee hit (slashing, piercing or crushing) on the target, frame 1 |
| `fx/slash_2.png` | melee hit (slashing, piercing or crushing) on the target, frame 2 |
| `fx/zap_0.png` | lightning hit, frame 0 |
| `fx/zap_1.png` | lightning hit, frame 1 |
| `fx/zap_2.png` | lightning hit, frame 2 |
| `fx/zap_3.png` | lightning hit, frame 3 |

### ui (33 files)

Interface art: white glyphs the game tints, family badges, the 9-patch skin for panels, buttons, bars and chips, the title logo and the Gate banners. See the UI section above for sizes, margins and tinting.

| File | What it is |
|---|---|
| `ui/banner_abyss.png` | 96 x 48 Gate banner for the Abyss button |
| `ui/banner_black_spiral.png` | 96 x 48 Gate banner for The Black Spiral |
| `ui/banner_deep_spiral.png` | 96 x 48 Gate banner for The Deep Spiral |
| `ui/banner_spiral.png` | 96 x 48 Gate banner for The Spiral |
| `ui/bar_bg.png` | 9-patch, 8 x 8, margin 2 px on every side: bar background (health, mana) |
| `ui/bar_enemy.png` | 9-patch, 8 x 8, margin 2 px on every side: enemy health bar fill |
| `ui/bar_hp.png` | 9-patch, 8 x 8, margin 2 px on every side: health bar fill |
| `ui/bar_mana.png` | 9-patch, 8 x 8, margin 2 px on every side: mana bar fill |
| `ui/bar_shield.png` | 9-patch, 8 x 8, margin 2 px on every side: boon shield segment on the health bar |
| `ui/bar_xp.png` | 9-patch, 8 x 8, margin 2 px on every side: experience / progress bar fill |
| `ui/boon.png` | white tintable glyph: generic boon (fallback when a boon has no icon) |
| `ui/button.png` | 9-patch, 16 x 16, margin 4 px on every side: button, normal |
| `ui/button_disabled.png` | 9-patch, 16 x 16, margin 4 px on every side: button, disabled |
| `ui/button_hover.png` | 9-patch, 16 x 16, margin 4 px on every side: button, hover / focus |
| `ui/button_pressed.png` | 9-patch, 16 x 16, margin 4 px on every side: button, pressed |
| `ui/chip.png` | 9-patch, 12 x 12, margin 3 px on every side: the readout chips on the run screen |
| `ui/family_blood.png` | white tintable badge for the Blood boon family (tinted #d0453a) |
| `ui/family_frost.png` | white tintable badge for the Frost boon family (tinted #8fd3ff) |
| `ui/family_fury.png` | white tintable badge for the Fury boon family (tinted #ff7a3d) |
| `ui/family_iron.png` | white tintable badge for the Iron boon family (tinted #b8b0a0) |
| `ui/family_storm.png` | white tintable badge for the Storm boon family (tinted #5f9fd3) |
| `ui/family_venom.png` | white tintable badge for the Venom boon family (tinted #7fc84a) |
| `ui/panel.png` | 9-patch, 16 x 16, margin 4 px on every side: cards and panels |
| `ui/popup.png` | 9-patch, 16 x 16, margin 4 px on every side: tips and tutorial cards (gold edge) |
| `ui/title.png` | title logo, 192 x 56 (drawn at x2 on the title screen; the text label is hidden when this file exists) |
| `ui/town_trophy.png` | white tintable glyph: Abyss trophy (tinted gold) |
| `ui/ui_check.png` | white tintable glyph: check mark |
| `ui/ui_down.png` | white tintable glyph: arrow down (move a skill down) |
| `ui/ui_family.png` | white tintable glyph: generic boon-family badge |
| `ui/ui_grip.png` | white tintable glyph: drag grip on skill cards |
| `ui/ui_star.png` | white tintable glyph: legendary / mythic power |
| `ui/ui_up.png` | white tintable glyph: arrow up (move a skill up) |
| `ui/ui_upgrade.png` | white tintable glyph: upgrade marker (tinted green) |

### fonts (2 files)

Fonts (TTF), with their license next to them.

| File | What it is |
|---|---|
| `fonts/jersey10.ttf` | Jersey 10 by Sarah Cadigan-Fried (The Soft Type Project), github.com/google/fonts ofl/jersey10/Jersey10-Regular.ttf |
| `fonts/pixelify_sans.ttf` | Pixelify Sans by Stefie Justprince, github.com/google/fonts ofl/pixelifysans/PixelifySans[wght].ttf |
