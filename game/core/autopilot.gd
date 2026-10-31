class_name DSAutopilot
extends RefCounted
## Plays a run with simple, fixed choices. Used by tests, the balance script and UI autoplay.
## Potions: HP below 30%, MP below 15%. Rewards: best item by power or the first boon.
## Rest: heal below 70% HP, else train (keep current kit). Floors: always descend.


## Fight the current room to the end. Returns the sim.
static func fight(run: DSRunState, log_all: bool = false) -> CombatSim:
	var p := run.make_player()
	var foes := run.fight_monsters()
	var sim := CombatSim.new(run.fight_rng(), run.data)
	sim.log_all = log_all
	var pots: Dictionary = run.potions.duplicate()
	sim.begin(p, foes)
	while not sim.over:
		if p.hp_pct() < 30.0 and int(pots.get("hp", 0)) > 0:
			pots["hp"] = int(pots["hp"]) - 1
			sim.use_potion("hp")
		if p.max_mana > 0 and p.mana_pct() < 15.0 and int(pots.get("mp", 0)) > 0:
			pots["mp"] = int(pots["mp"]) - 1
			sim.use_potion("mp")
		sim.step()
	run.finish_fight(p, foes, sim.result, pots)
	return sim


## Best offer index: highest-power item that beats what's equipped, else first boon, else -1.
static func pick_offer(run: DSRunState, offers: Array) -> int:
	var best := -1
	var best_gain := 0
	for i in offers.size():
		var o: Dictionary = offers[i]
		if o.get("kind") == "item":
			var it: Dictionary = o["item"]
			var cur = run.items.get(it.get("slot", ""))
			var gain := int(it.get("power", 0)) - (0 if cur == null else int(DSLoot.power(cur)))
			if gain > best_gain:
				best_gain = gain
				best = i
	if best >= 0:
		return best
	for i in offers.size():
		if offers[i].get("kind") == "boon":
			return i
	return -1


## Advance one step of the run (one room, one reward, or one floor transition).
static func advance(run: DSRunState) -> void:
	match run.phase:
		"path":
			run.enter(0)
		"room":
			match run.room.get("type", ""):
				"fight", "elite", "boss":
					fight(run)
				"treasure":
					var i := pick_offer(run, run.room.get("offers", []))
					if i >= 0:
						run.take_offer(i)
					else:
						run.skip()
				"shrine":
					if run.room.get("offers", []).is_empty():
						run.skip()
					else:
						run.take_offer(0)
				"rest":
					if run.make_player().hp_pct() < 70.0:
						run.rest_heal()
					else:
						run.rest_train(run.actives, run.rules)
				"event":
					run.event_choose(0)
					if run.phase == "room":
						run.complete_room()
				_:
					run.skip()
		"reward":
			var j := pick_offer(run, run.room.get("reward", {}).get("offers", []))
			if j >= 0:
				run.take_offer(j)
			else:
				run.skip()
		"floor_end":
			run.descend()


## Play until the run ends (or `max_steps`). Returns the run.
static func play(run: DSRunState, max_steps: int = 500) -> DSRunState:
	var n := 0
	while run.phase != "over" and n < max_steps:
		advance(run)
		n += 1
	return run
