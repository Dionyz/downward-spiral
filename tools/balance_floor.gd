extends SceneTree
## Simulates the milestone 4 prototype floor (3 fights, level up per win, no regen, potions
## drunk automatically below 30% HP) N times per class and prints win rates.
##   godot --headless --path . -s tools/balance_floor.gd -- [--runs 200]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := 200
	for i in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = int(args[i + 1])
	var data := DSData.load_dir("res://game/data")
	for line in ["warrior", "thief", "mage", "knifer"]:
		var wins := 0
		var fights_won := 0
		var rounds := 0
		for r in runs:
			var res := _run(data, line, 1000 + r)
			wins += 1 if res[0] else 0
			fights_won += res[1]
			rounds += res[2]
		print("%-8s win %5.1f%%  avg fights won %.2f  avg rounds/fight %.1f" % [line, 100.0 * wins / runs,
			float(fights_won) / runs, float(rounds) / maxi(1, fights_won)])
	quit()


func _run(data: DSData, line: String, seed_value: int) -> Array:
	var rng := DSRng.new(seed_value)
	var level := 1
	var hp := -1
	var mana := -1
	var pots := {"hp": 2, "mp": 2}
	var won := 0
	var rounds := 0
	for f in 3:
		var p := DSFactory.make_player(data, line, 1, level)
		if hp >= 0:
			p.hp = clampi(hp, 1, p.max_hp)
			p.mana = clampi(mana, 0, p.max_mana)
		var foes := DSEncounters.roll_fight(data, rng, 1, level)
		var sim := CombatSim.new(rng, data)
		sim.log_all = false
		sim.begin(p, foes)
		while not sim.over:
			if p.hp_pct() < 30.0 and pots["hp"] > 0:
				pots["hp"] -= 1
				sim.use_potion("hp")
			if p.max_mana > 0 and p.mana_pct() < 15.0 and pots["mp"] > 0:
				pots["mp"] -= 1
				sim.use_potion("mp")
			sim.step()
		if sim.result != "win":
			return [false, won, rounds]
		won += 1
		rounds += sim.round_num
		var old_max := p.max_hp
		var old_mmax := p.max_mana
		level += 1
		var nxt := DSFactory.make_player(data, line, 1, level)
		hp = p.hp + (nxt.max_hp - old_max)
		mana = p.mana + (nxt.max_mana - old_mmax)
	return [true, won, rounds]
