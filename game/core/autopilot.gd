class_name DSAutopilot
extends RefCounted
## Plays a run with simple, fixed choices. Used by tests, the balance script and UI autoplay.
## Potions: drunk automatically (HP below 30%, MP below 15%). Gear: strongest per slot.
## Boons: the first offered. Events: the first option. Stairs: always descend.


## Equip the strongest item (by DSLoot.power) in each slot from the bag.
static func equip_best(run: DSRunState) -> void:
	for slot in DSRunState.SLOTS:
		var cands := run.inventory_for(slot)
		if cands.is_empty():
			continue
		var cur = run.items.get(slot)
		if cur == null or DSLoot.power(cands[0]["item"]) > DSLoot.power(cur):
			run.equip_from_inventory(int(cands[0]["i"]))


## Handle whatever the run is waiting on, or play one turn. Returns that turn's events.
static func advance(run: DSRunState) -> Array:
	if run.world != null:
		run.world.auto_potions = true
	match run.phase:
		"explore":
			var bag := run.inventory.size()
			var evs := run.tick()
			if run.inventory.size() != bag:
				equip_best(run)
			return evs
		"boon":
			run.take_boon(0)
		"event":
			run.event_choose(0)
			run.event_done()
		"floor_end":
			run.descend()
		"extract_choice":
			run.extract_choice(true)
	return []


## Play until the run ends (or `max_turns`). Returns the run.
static func play(run: DSRunState, max_turns: int = 20000) -> DSRunState:
	var n := 0
	while run.phase != "over" and n < max_turns:
		advance(run)
		n += 1
	return run
