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
	var p := DSMeta.perks(data, 1)
	p["charges"] = DSMeta.charges(data, acct)
	var r := DSRunState.new_run(data, "warrior", 5, p)
	assert_eq(r.charges, {"skip": 3, "reroll": 0, "banish": 1})


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
	assert_false(r.can_extract(), "no extract after floor 1")
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
	assert_eq(r.banked(), {"xp": 300, "gold": 120})
	var d := DSRunState.new_run(data, "warrior", 3)
	d.gold = 80
	d.xp_total = 200
	d.end_run("death")
	assert_eq(d.banked(), {"xp": 100, "gold": 0})


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


func test_forty_boons_six_per_class_sixteen_shared():
	assert_eq(data.boons.size(), 40)
	var per := {}
	for id in data.boons.keys():
		var lines: Array = data.boons[id].get("lines", [])
		var key := "shared" if lines.is_empty() else str(lines[0])
		per[key] = int(per.get(key, 0)) + 1
	assert_eq(per, {"shared": 16, "warrior": 6, "thief": 6, "mage": 6, "knifer": 6})


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
