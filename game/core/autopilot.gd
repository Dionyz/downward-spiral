class_name DSAutopilot
extends RefCounted
## Plays a run with simple, fixed choices. Used by tests, the balance script and UI autoplay.
## Potions: HP below 30%, MP below 15%. Gear: strongest per slot after every room. Boons: the first offered.
## Rest: heal. Floors: always descend.


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


## Equip the strongest item (by DSLoot.power) in each slot from the bag.
static func equip_best(run: DSRunState) -> void:
	for slot in DSRunState.SLOTS:
		var cands := run.inventory_for(slot)
		if cands.is_empty():
			continue
		var cur = run.items.get(slot)
		if cur == null or DSLoot.power(cands[0]["item"]) > DSLoot.power(cur):
			run.equip_from_inventory(int(cands[0]["i"]))


## Advance one step of the run (one room, one reward, or one floor transition).
static func advance(run: DSRunState) -> void:
	match run.phase:
		"path":
			run.enter(0)
		"room":
			match run.room.get("type", ""):
				"fight", "elite", "boss":
					fight(run)
				"shrine":
					if run.room.get("offers", []).is_empty():
						run.skip()
					else:
						run.take_offer(0)
				"rest":
					run.rest_heal()
				"event":
					run.event_choose(0)
					if run.phase == "room":
						run.complete_room()
				_:
					run.skip()
		"reward":
			if run.room.get("reward", {}).get("offers", []).is_empty():
				run.skip()
			else:
				run.take_offer(0)
		"floor_end":
			run.descend()
	equip_best(run)


## Play until the run ends (or `max_steps`). Returns the run.
static func play(run: DSRunState, max_steps: int = 500) -> DSRunState:
	var n := 0
	while run.phase != "over" and n < max_steps:
		advance(run)
		n += 1
	return run
