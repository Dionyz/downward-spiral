extends GutTest
## Runs on Rogue-style floors: turns, exploring, kills, loot, boons, events, stairs, save/resume.

const H = preload("res://tests/helpers.gd")
var data: DSData


func before_each():
	data = H.data()


func _turns(r: DSRunState, n: int) -> void:
	for i in n:
		if r.phase != "explore":
			break
		r.world.auto_potions = true
		r.tick()


func test_new_run_starts_exploring_floor_one():
	var r := DSRunState.new_run(data, "warrior", 11)
	assert_eq(r.floor_num, 1)
	assert_eq(r.phase, "explore")
	assert_not_null(r.world)
	assert_eq(r.potions["hp"], 3, "three healing potions to start")
	assert_eq(r.potions["mp"], 0)
	assert_eq(DSRunState.new_run(data, "mage", 11).potions["mp"], 2)


func test_player_explores_and_sees_more():
	var r := DSRunState.new_run(data, "warrior", 12)
	var before := r.world.seen.size()
	var start := r.world.ppos
	_turns(r, 30)
	assert_gt(r.world.seen.size(), before)
	assert_ne(r.world.ppos, start, "the character walks")


func test_monsters_move_and_fight():
	var r := DSRunState.new_run(data, "warrior", 13)
	var moved := false
	var hits := false
	for i in 400:
		if r.phase != "explore":
			DSAutopilot.advance(r)
			continue
		for ev in DSAutopilot.advance(r):
			if ev.get("t") == "move" and ev.get("who") != "player":
				moved = true
			if ev.get("t") == "damage":
				hits = true
		if moved and hits:
			break
	assert_true(moved, "monsters move on the map")
	assert_true(hits, "fights happen on the map")


func test_same_seed_same_floor_play():
	var a := DSRunState.new_run(data, "knifer", 99)
	var b := DSRunState.new_run(data, "knifer", 99)
	_turns(a, 150)
	_turns(b, 150)
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()))


func test_save_and_resume_mid_floor():
	var a := DSRunState.new_run(data, "thief", 42)
	_turns(a, 60)
	var b := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(a.to_dict())))
	assert_eq(b.world.ppos, a.world.ppos)
	assert_eq(b.world.seen.size(), a.world.seen.size())
	assert_eq(b.world.monsters.size(), a.world.monsters.size())
	assert_eq(b.hp, a.hp)
	_turns(b, 30)
	assert_true(b.phase in ["explore", "boon", "event", "floor_end", "over"])


func test_full_runs_finish_for_every_class():
	for line in ["warrior", "thief", "mage", "knifer"]:
		var r := DSAutopilot.play(DSRunState.new_run(data, line, 7))
		assert_eq(r.phase, "over", "%s finished" % line)
		assert_true(r.result in ["death", "victory"])
		assert_gt(int(r.stats["kills"]), 0)


func test_kills_give_xp_and_level_ups_offer_boons():
	var r := DSRunState.new_run(data, "mage", 5)
	var saw_boon := false
	for i in 3000:
		if r.phase == "boon":
			saw_boon = true
			assert_eq(r.offer.size(), 3, "1 of 3")
			for id in r.offer:
				assert_true(data.boons.has(id))
			break
		if r.phase == "over":
			break
		DSAutopilot.advance(r)
	assert_true(saw_boon, "a level-up offered boons")
	assert_gt(r.xp_total, 0)


func test_take_and_skip_boon():
	var r := DSRunState.new_run(data, "warrior", 3)
	r._open_offer("level")
	assert_eq(r.phase, "boon")
	var id: String = r.offer[1]
	r.take_boon(1)
	assert_true(r.boons.has(id))
	assert_eq(r.phase, "explore")
	r._open_offer("level")
	assert_eq(r.charges["skip"], 1, "one skip per run to start")
	assert_true(r.skip_boon())
	assert_eq(r.phase, "explore")
	assert_eq(r.boons.size(), 1)
	r._open_offer("level")
	assert_false(r.skip_boon(), "no skips left")
	assert_eq(r.phase, "boon")


func test_reroll_and_banish_charges():
	var r := DSRunState.new_run(data, "warrior", 5)
	assert_eq(r.charges["reroll"], 0)
	assert_eq(r.charges["banish"], 0)
	r._open_offer("level")
	assert_false(r.reroll_boons(), "no rerolls without the upgrade")
	assert_false(r.banish_boon(0), "no banishes without the upgrade")
	r.charges = {"skip": 1, "reroll": 1, "banish": 1}
	var before: Array = r.offer.duplicate()
	assert_true(r.reroll_boons())
	assert_eq(r.offer.size(), 3)
	for id in r.offer:
		assert_false(before.has(id), "reroll shows new boons")
	assert_eq(r.charges["reroll"], 0)
	var gone: String = r.offer[0]
	assert_true(r.banish_boon(0))
	assert_true(r.banished.has(gone))
	assert_ne(r.offer[0], gone, "a new boon takes the banished one's slot")
	assert_eq(r.offer.size(), 3)
	assert_eq(r.phase, "boon", "banishing doesn't end the pick")
	assert_false(r.available_boons().has(gone), "banished boons stay out of the pool")
	var r2 := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_true(r2.banished.has(gone), "banishes survive save")
	assert_eq(int(r2.charges["banish"]), 0)


func test_charges_come_from_the_account():
	var acct := {"upgrades": {"skip": 2, "banish": 1}}
	var r := DSRunState.new_run(data, "warrior", 5, DSMeta.perks(data, acct, "dwarf"), "dwarf")
	assert_eq(r.charges, {"skip": 3, "reroll": 0, "banish": 1})
	var h := DSRunState.new_run(data, "warrior", 5, DSMeta.perks(data, acct, "human"), "human")
	assert_eq(int(h.charges["skip"]), 4, "humans get +1 skip")


func test_drink_potion():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.world.player.hp = 10
	assert_true(r.world.drink("hp"))
	assert_eq(r.potions["hp"], 2)
	assert_eq(r.world.player.hp, 10 + int(r.world.player.max_hp * 0.5), "a potion heals 50%")


func test_stairs_end_the_floor_and_descend():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.world.heading_down = true
	r.world.ppos = r.world.stairs
	r.world._interact()
	r.tick()
	assert_eq(r.phase, "floor_end")
	r.descend()
	assert_eq(r.floor_num, 2)
	assert_eq(r.phase, "explore")


func test_extract_and_death_banking():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.phase = "floor_end"
	r.floor_num = 2
	r.gold = 120
	r.xp_total = 300
	r.extract()
	assert_eq(r.banked(), {"gold": 120})
	var d := DSRunState.new_run(data, "warrior", 3)
	d.gold = 80
	d.xp_total = 200
	d.end_run("death")
	assert_eq(d.banked(), {"gold": 0})


func test_events_pause_and_resolve():
	for id in data.events.keys():
		var opts: Array = data.events[id]["options"]
		for i in opts.size():
			var r := DSRunState.new_run(data, "mage", 17)
			r.phase = "event"
			r.event_id = id
			var lines := r.event_choose(i)
			assert_gt(lines.size(), 0, "%s option %d says something" % [id, i])
			r.event_done()
			assert_eq(r.phase, "explore")


func test_chest_awards_loot_without_choosing():
	var r := DSRunState.new_run(data, "warrior", 3)
	var got := r.open_chest()
	assert_eq(got.size(), 3)


func test_loot_fills_empty_slots_then_the_bag():
	var r := DSRunState.new_run(data, "warrior", 3)
	assert_null(r.items["armor"])
	var a1 := DSLoot.roll_item(data, DSRng.new(1), 2, "armor", "common")
	var a2 := DSLoot.roll_item(data, DSRng.new(2), 2, "armor", "rare")
	var got := r.gain_items([a1, a2])
	assert_true(got[0]["equipped"])
	assert_false(got[1]["equipped"])
	assert_eq(r.inventory.size(), 1)


func test_equip_from_inventory_swaps_and_keeps_hp():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.world.player.hp = 50
	var w := DSLoot.roll_item(data, DSRng.new(5), 3, "weapon", "epic", "warrior")
	r.gain_items([w])
	assert_true(r.equip_from_inventory(0))
	assert_eq(r.items["weapon"]["name"], w["name"])
	assert_eq(r.world.player.hp, 50, "equipping doesn't reset HP")


func test_inventory_holds_500():
	var r := DSRunState.new_run(data, "warrior", 3)
	var rng := DSRng.new(9)
	var batch: Array = []
	for i in 510:
		batch.append(DSLoot.roll_item(data, rng, 2, "trinket", "common"))
	var g0 := r.gold
	r.gain_items(batch)
	assert_eq(r.inventory.size(), DSRunState.INVENTORY_MAX)
	assert_gt(r.gold, g0)


func test_boon_pool_shape():
	var per := {}
	for id in data.boons.keys():
		var lines: Array = data.boons[id].get("lines", [])
		var key := "shared" if lines.is_empty() else str(lines[0])
		per[key] = int(per.get(key, 0)) + 1
	assert_gte(int(per["shared"]), 20)
	for l in ["warrior", "thief", "mage", "knifer"]:
		assert_gte(int(per.get(l, 0)), 2, l)


func test_boon_stats_are_implemented():
	var src := FileAccess.get_file_as_string("res://game/core/combat_sim.gd") + FileAccess.get_file_as_string("res://game/core/factory.gd")
	for id in data.boons.keys():
		for k in data.boons[id].get("effect", {}).get("stats", {}).keys():
			assert_true(src.contains('"%s"' % k), "%s: stat %s is read somewhere" % [id, k])


func test_stackable_boons_have_no_limit():
	var r := DSRunState.new_run(data, "warrior", 5)
	for i in 12:
		r.add_boon("whetstone")
	assert_eq(r.boon_rank("whetstone"), 12, "stackable boons have no limit")
	assert_true(r.available_boons().has("whetstone"))
	assert_eq(int(r.make_player().flags["b_flat"]), 24, "+2 per stack")
	r.add_boon("twin_throw")
	r.add_boon("twin_throw")
	assert_eq(r.boon_rank("twin_throw"), 1, "on/off class boons are taken once")


func test_shrines_bless_automatically():
	var r := DSRunState.new_run(data, "warrior", 5)
	var o := {"type": "shrine", "pos": r.world.ppos + Vector2i(1, 0), "used": false}
	r.world.objects.append(o)
	r.world.ppos = o["pos"]
	r.world._interact()
	assert_true(o["used"])
	assert_true(r.world.pending.is_empty(), "no dialogue, no pick")
	assert_true(r.world.events.any(func(e): return e.get("t") == "shrine" and str(e.get("text", "")) != ""))


func test_levels_have_no_events():
	for s in range(1, 40):
		var lvl := DSLevelGen.generate(data, DSRng.new(s), 1 + s % 6)
		for ob in lvl["objects"]:
			assert_ne(ob["type"], "event")


func test_every_boon_flag_is_implemented():
	var src := ""
	for f in DirAccess.get_files_at("res://game/core"):
		if f.ends_with(".gd"):
			src += FileAccess.get_file_as_string("res://game/core/" + f)
	for id in data.boons.keys():
		var e: Dictionary = data.boons[id].get("effect", {})
		if e.has("flag"):
			assert_true(src.find('"%s"' % e["flag"]) >= 0, "boon %s flag %s is never read" % [id, e["flag"]])


func test_boons_reference_real_abilities():
	var stat_words := ["hp", "damage", "gold", "xp", "potion"]
	for id in data.boons.keys():
		for ref in data.boons[id].get("refs", []):
			assert_true(stat_words.has(ref) or not data.ability(ref).is_empty(), "boon %s refs missing %s" % [id, ref])


func test_boss_has_phases():
	var m := DSFactory.make_monster(data, "spiral_warden", 10)
	var sim := CombatSim.new(DSRng.new(1), data)
	var p := H.dummy("You", true)
	sim.begin(p, [m])
	sim.apply_damage(p, m, int(m.max_hp * 0.5), "hit", "slash", false)
	assert_eq(int(m.flags.get("phase", 0)), 1)
	sim.apply_damage(p, m, int(m.max_hp * 0.3), "hit", "slash", false)
	assert_eq(int(m.flags.get("phase", 0)), 2)


func test_every_class_uses_its_whole_kit():
	for line in ["warrior", "thief", "mage", "knifer"]:
		var used := {}
		for s in 40:
			var p := DSFactory.make_player(data, line, 3, 10)
			var foes := DSEncounters.build(data, ["goblin_cutter", "orc_brute", "ghoul", "cave_spider"].slice(0, 1 + s % 4), 8)
			for f in foes:
				f.max_hp *= 6
				f.hp = f.max_hp
			p.max_hp *= 2
			p.hp = p.max_hp
			var sim := CombatSim.new(DSRng.new(100 + s), data)
			for ev in sim.run(p, foes):
				if ev.get("t") in ["ability", "cast"] and ev.get("src") == p.name:
					used[str(ev.get("id", ev.get("ability")))] = true
		for a in data.kit_abilities(line, 3, 10, "active"):
			assert_true(used.has(a), "%s never used %s" % [line, a])


func test_pure_upgrade_detection():
	var eq := {"slot": "weapon", "min": 10, "max": 20, "damroll": 2, "flags": []}
	assert_true(DSRunState.is_pure_upgrade({"slot": "weapon", "min": 12, "max": 20, "damroll": 2, "flags": []}, eq))
	assert_false(DSRunState.is_pure_upgrade({"slot": "weapon", "min": 10, "max": 20, "damroll": 2, "flags": []}, eq), "identical is not an upgrade")
	assert_false(DSRunState.is_pure_upgrade({"slot": "weapon", "min": 14, "max": 24, "damroll": 1, "flags": []}, eq), "sidegrade: more damage, less damroll")
	assert_false(DSRunState.is_pure_upgrade({"slot": "weapon", "min": 14, "max": 24, "damroll": 2, "flags": []},
		{"slot": "weapon", "min": 10, "max": 20, "damroll": 2, "flags": ["sharp"]}), "loses a flag")
	assert_true(DSRunState.is_pure_upgrade({"slot": "armor", "ac": -5}, null), "empty slot")
	var r := DSRunState.new_run(data, "warrior", 3)
	r.inventory = [{"slot": "armor", "ac": -5, "flags": []}]
	assert_true(r.upgrade_slots().has("armor"))


func test_boss_seals_the_stairs():
	var r := DSRunState.new_run(data, "warrior", 3)
	r.floor_num = 10
	r._new_floor()
	assert_true(r.world.stairs_sealed())
	r.world.heading_down = true
	r.world.ppos = r.world.stairs
	r.world._interact()
	assert_true(r.world.pending.is_empty(), "can't leave while the boss lives")
	r.world.living_boss()["c"].hp = 0
	assert_false(r.world.stairs_sealed())
	r.world._interact()
	assert_eq(r.world.pending.get("kind", ""), "stairs")


func test_extract_walks_back_then_asks():
	var r := DSRunState.new_run(data, "thief", 8)
	for i in 30:
		r.world.auto_potions = true
		r.tick()
	assert_true(r.can_extract())
	r.request_extract()
	var n := 0
	while r.phase == "explore" and n < 400:
		r.world.auto_potions = true
		r.tick()
		n += 1
	if r.phase == "over":
		return   # died on the way back: fine for this seed
	if r.phase == "boon":
		r.take_boon(0)
		while r.phase == "explore" and n < 800:
			r.tick()
			n += 1
	assert_eq(r.phase, "extract_choice")
	assert_eq(r.world.ppos, r.world.entrance)
	r.extract_choice(false)
	assert_eq(r.phase, "explore")
	assert_false(r.world.extracting)


func test_extraction_ambush_or_clean():
	var ambushes := 0
	for sd in 20:
		var r := DSRunState.new_run(data, "warrior", 100 + sd)
		r.phase = "extract_choice"
		r.extract_choice(true)
		if r.phase == "over":
			assert_eq(r.result, "extract")
			continue
		ambushes += 1
		assert_true(r.world.ambush)
		assert_eq(r.world.w, 20)
		assert_gte(r.world.monsters.size(), 1)
		assert_true(r.world.monsters.all(func(m): return m["state"] == "hunt"), "ambushers are awake")
		assert_false(r.can_extract(), "no extracting out of an ambush")
		for m in r.world.monsters:
			m["c"].hp = 0
		r.tick()
		assert_eq(r.phase, "over")
		assert_eq(r.result, "extract", "clearing the ambush finishes the extraction")
	assert_between(ambushes, 10, 20, "about 80% ambushed")


func test_one_time_rescue():
	var a := DSAccount.fresh()
	DSAccount.create_character(data, a, "Ash", "warrior", "human")
	var r := DSAccount.start_run(data, a, 4)
	var brought: Dictionary = r.items["weapon"]
	r.items["armor"] = DSLoot.roll_item(data, DSRng.new(1), 3, "armor", "rare", "warrior")
	r.inventory = [DSLoot.roll_item(data, DSRng.new(2), 3, "trinket", "", "warrior")]
	r.gold = 101
	r.end_run("death")
	assert_true(DSAccount.apply_rescue(a, r))
	var out := DSAccount.bank_run(data, a, r)
	assert_true(out.get("rescued", false))
	assert_eq(int(a["gold"]), 50, "half the gold")
	assert_eq(DSAccount.current(a)["loadout"]["weapon"], brought, "keeps the gear brought in")
	assert_null(DSAccount.current(a)["loadout"]["armor"], "found gear is lost")
	assert_eq(a["stash"].size(), 0)
	var r2 := DSAccount.start_run(data, a, 5)
	r2.end_run("death")
	assert_false(DSAccount.apply_rescue(a, r2), "only once, ever")


func test_boon_families_count_distinct_boons():
	var r := DSRunState.new_run(data, "warrior", 5)
	for i in 5:
		r.add_boon("vampiric_edge")
	assert_eq(int(DSFactory.family_counts(data, r.boons).get("blood", 0)), 1, "stacks of one boon count once")
	r.add_boon("bloodlust")
	var fb := DSFactory.family_bonuses(data, r.boons)
	assert_true(fb.any(func(b): return b["family"] == "blood" and b["tier"] == 2))
	var p := r.make_player()
	assert_eq(int(p.flags["b_leech"]), 6 * 5 + 5, "5 stacks + the Blood 2 bonus")
	for id in ["hemorrhage", "adrenaline"]:
		r.add_boon(id)
	var hp4 := r.make_player().max_hp
	assert_true(DSFactory.family_bonuses(data, r.boons).any(func(b): return b["family"] == "blood" and b["tier"] == 4))
	assert_gt(hp4, p.max_hp, "Blood 4: +15% max HP")


func test_every_family_reaches_six():
	var per := {}
	for id in data.boons.keys():
		for t in data.boons[id].get("tags", []):
			per[t] = int(per.get(t, 0)) + 1
	for f in data.families.keys():
		assert_gte(int(per.get(f, 0)), 6, "%s has at least 6 boons" % f)


func test_boon_rarities_scale_stats():
	var r := DSRunState.new_run(data, "warrior", 5)
	r.add_boon("vampiric_edge", "common")
	r.add_boon("vampiric_edge", "legendary")
	assert_eq(r.boon_rarity, ["common", "legendary"])
	assert_eq(int(r.make_player().flags["b_leech"]), 6 + 15, "6 + 6*2.5")
	assert_true(r.boon_desc("vampiric_edge", "legendary").contains("15%"))
	r.add_boon("last_stand", "common")
	assert_eq(r.boon_rarity.back(), "legendary", "last stand is always legendary")
	assert_eq(r.roll_boon_rarity("twin_throw"), "common", "on/off boons have no rarity")
	var r2 := DSRunState.from_dict(data, JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(r2.boon_rarity, r.boon_rarity)


func test_fortune_shifts_rarity_odds():
	var plain := DSRunState.new_run(data, "warrior", 5)
	var lucky := DSRunState.new_run(data, "warrior", 5, DSMeta.perks(data, {"upgrades": {"fortune": 5}}))
	var hi := {"plain": 0, "lucky": 0}
	for i in 600:
		if plain.roll_boon_rarity("whetstone") in ["rare", "epic", "legendary"]:
			hi["plain"] += 1
		if lucky.roll_boon_rarity("whetstone") in ["rare", "epic", "legendary"]:
			hi["lucky"] += 1
	assert_gt(hi["lucky"], hi["plain"] + 60, "Fortune makes rare+ boons much more common")


func test_last_stand_once_per_copy_per_run():
	var r := DSRunState.new_run(data, "warrior", 5)
	r.add_boon("last_stand")
	r._sync_to_world()
	var p := r.world.player
	r.world.sim.start_encounter()
	r.world.sim.apply_damage(null, p, 99999, "hit", "none", false)
	assert_eq(p.hp, 1, "saved once")
	r.world.sim.start_encounter()
	p.hp = 5
	r.world.sim.apply_damage(null, p, 99999, "hit", "none", false)
	assert_false(p.is_alive(), "a new fight doesn't reset it")


func test_ten_floors_and_level_scaling():
	var r := DSRunState.new_run(data, "warrior", 4)
	assert_eq(r.floors(), 10)
	var a := DSRunState.new_run(data, "warrior", 4, {}, "human", {}, "spiral", true)
	assert_eq(a.floors(), 20)
	assert_eq(data.floor_kind(10), "boss")
	assert_eq(data.floor_kind(20), "boss")
	assert_eq(data.floor_kind(6), "elite")
	assert_gt(data.monster_level_at("deep_spiral", 1), data.monster_level_at("spiral", 1))
	assert_gt(data.monster_level_at("spiral", 20), data.monster_level_at("spiral", 10))


func test_abyss_floor_ten_boss_continues_down():
	var r := DSRunState.new_run(data, "warrior", 4, {}, "human", {}, "spiral", true)
	r.floor_num = 10
	r.world.pending = {"kind": "stairs"}
	r.tick()
	assert_eq(r.phase, "floor_end", "the Abyss goes on past floor 10")
	var n := DSRunState.new_run(data, "warrior", 4)
	n.floor_num = 10
	n.world.pending = {"kind": "stairs"}
	n.tick()
	assert_eq(n.result, "victory")


func test_mythic_items_only_in_the_abyss_depths():
	var r := DSRunState.new_run(data, "warrior", 4, {}, "human", {}, "spiral", true)
	r.floor_num = 5
	assert_eq(r._maybe_mythic("boss"), [])
	r.floor_num = 12
	var got: Array = r._maybe_mythic("boss")
	assert_eq(got.size(), 1)
	assert_eq(got[0]["rarity"], "mythic")
	assert_true(got[0].has("passive") and got[0].has("passive2"), "two powers")
	var rng := DSRng.new(5)
	for i in 300:
		assert_ne(DSLoot.roll_rarity(data, rng, 0.5), "mythic", "never from normal drops")


func test_explore_reaches_stairs_more_than_80_steps_away():
	# Regression: the path back from the goal was capped at 80 steps, so a cleared floor whose
	# stairs were farther away left the character waiting forever.
	var r := DSRunState.new_run(data, "warrior", 14)
	var w := 120
	var rows: Array = [" ".repeat(w), " " + ".".repeat(w - 2) + " ", " ".repeat(w)]
	var lvl := {"w": w, "h": 3, "tiles": rows, "rooms": [], "start": [w - 2, 1], "stairs": [1, 1],
		"objects": [], "spawns": [], "floor": 1}
	r.world = DSWorld.create(r, lvl, r.rng.fork())
	for y in 3:
		for x in w:
			r.world.seen[DSWorld.pk(Vector2i(x, y))] = true
	var start := r.world.ppos
	_turns(r, 5)
	assert_lt(r.world.ppos.x, start.x, "the character walks toward the far stairs")


func test_corridor_hold_is_capped_when_the_pack_never_comes():
	# Regression: with 3+ foes hunting and the character in a corridor it waited for them every
	# turn. A pack that never closes in (a caster in front blocking the rest) stalled the run.
	var perks := DSMeta.perks(data, {})
	perks["mastery"] = 1
	var r := DSRunState.new_run(data, "warrior", 15, perks)
	var w := 16
	var rows: Array = [" ".repeat(w), " " + "#".repeat(w - 2) + " ", " ".repeat(w)]
	var spawns: Array = []
	for x in [8, 9, 10]:
		spawns.append({"id": "sewer_rat", "x": x, "y": 1})
	var lvl := {"w": w, "h": 3, "tiles": rows, "rooms": [], "start": [1, 1], "stairs": [14, 1],
		"objects": [], "spawns": spawns, "floor": 1}
	r.world = DSWorld.create(r, lvl, r.rng.fork())
	for m in r.world.monsters:
		m["state"] = "hunt"
		m["energy"] = -1000000  # never acts: the pack never comes
	var waits := 0
	var most := 0
	for i in 20:
		if r.phase != "explore":
			break
		var waited := r.tick().any(func(e): return e["t"] == "wait" and e.get("who") == "player")
		waits = waits + 1 if waited else 0
		most = maxi(most, waits)
	assert_lte(most, DSWorld.CORRIDOR_HOLD_MAX, "holds the corridor a few turns at most")
	assert_gt(r.world.ppos.x, 3, "then closes in")
