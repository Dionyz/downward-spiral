class_name DSDungeonGen
extends RefCounted
## Seeded floor generation (spec "Run structure").
## A floor is a list of steps; each step is an Array of 1 room (chain) or 2 rooms (a fork: pick one).
## Room: {type, name, desc, id}

## Spec table: floor -> [min rooms, max rooms, ending room type]
const FLOORS := {
	1: [3, 3, "fight"],
	2: [3, 4, "elite"],
	3: [4, 4, "fight"],
	4: [4, 5, "elite"],
	5: [5, 5, "fight"],
	6: [5, 5, "boss"],
}
const TYPE_WEIGHTS := {"fight": 50, "treasure": 15, "shrine": 15, "rest": 10, "event": 10}

const NAMES := ["A collapsed crypt", "A flooded gallery", "A root-choked hall", "An ossuary", "A chapel of rust",
	"A narrow stair", "A cistern", "A fungal grotto", "A burned library", "A collapsed mine shaft",
	"A shrine to nothing", "A guardroom", "A bone-strewn pit", "A sunken courtyard"]
const DETAILS := ["Water drips from the ceiling.", "Something skitters out of sight.", "The air tastes of ash.",
	"Old blood darkens the flagstones.", "A cold draft rises from below.", "Candles burn with no one to tend them.",
	"The walls are scratched with tally marks.", "Roots hang like curtains.", "Your footsteps echo too long."]


static func room_count(rng: DSRng, floor_num: int) -> int:
	var f: Array = FLOORS.get(floor_num, [3, 3, "fight"])
	return rng.number_range(int(f[0]), int(f[1]))


## Generate a floor. Returns {"floor": n, "steps": [[room], [room, room], ...]}.
## "Rooms" counts steps along the path, so a fork adds a side-by-side alternative, not length.
## `templates` = rooms.json ({names, details}); falls back to the built-in lists.
static func generate(rng: DSRng, floor_num: int, templates: Dictionary = {}) -> Dictionary:
	var f: Array = FLOORS.get(floor_num, [3, 3, "fight"])
	var n := room_count(rng, floor_num)
	var types := _assign_types(rng, n, str(f[2]))
	var steps: Array = []
	var fork_at := -1
	if n >= 4:
		# One fork somewhere before the final room.
		fork_at = rng.number_range(0, n - 2)
	var id := 0
	for i in n:
		var step: Array = [_room(rng, types[i], id, templates)]
		id += 1
		if i == fork_at:
			var alt_type := _alt_type(rng, types, i)
			step.append(_room(rng, alt_type, id, templates))
			id += 1
		steps.append(step)
	return {"floor": floor_num, "steps": steps}


## Types along the main path. Last = floor ending. At least half fights (ending counts),
## no two rests in a row.
static func _assign_types(rng: DSRng, n: int, ending: String) -> Array:
	var types: Array = []
	for i in n - 1:
		types.append(rng.weighted_pick(TYPE_WEIGHTS))
	types.append(ending)
	_fix(rng, types)
	return types


static func _is_fight(t: String) -> bool:
	return t in ["fight", "elite", "boss"]


static func _fix(rng: DSRng, types: Array) -> void:
	var n := types.size()
	# No two rests in a row.
	for i in range(1, n - 1):
		if types[i] == "rest" and types[i - 1] == "rest":
			types[i] = "fight"
	# At least half fights.
	var need := ceili(n / 2.0)
	var fights := types.filter(func(t): return _is_fight(t)).size()
	var guard := 0
	while fights < need and guard < 20:
		guard += 1
		var i := rng.number_range(0, n - 2)
		if not _is_fight(types[i]):
			types[i] = "fight"
			fights += 1


## The fork's alternative keeps the rules true whichever branch is taken.
static func _alt_type(rng: DSRng, types: Array, i: int) -> String:
	if _is_fight(types[i]):
		return "fight"  # swapping a fight for a non-fight could break the half-fights rule
	var t: String = rng.weighted_pick(TYPE_WEIGHTS)
	var prev_rest: bool = i > 0 and types[i - 1] == "rest"
	var next_rest: bool = i + 1 < types.size() and types[i + 1] == "rest"
	if t == "rest" and (prev_rest or next_rest):
		t = "treasure"
	return t


static func _room(rng: DSRng, t: String, id: int, templates: Dictionary = {}) -> Dictionary:
	var names: Array = templates.get("names", NAMES)
	var details: Array = templates.get("details", DETAILS)
	return {"id": id, "type": t, "name": str(rng.pick(names)), "desc": str(rng.pick(details))}


## Every path through the floor (for tests): Array of Arrays of room types.
static func paths(floor_data: Dictionary) -> Array:
	var out: Array = [[]]
	for step in floor_data["steps"]:
		var nxt: Array = []
		for p in out:
			for room in step:
				var q: Array = p.duplicate()
				q.append(room["type"])
				nxt.append(q)
		out = nxt
	return out
