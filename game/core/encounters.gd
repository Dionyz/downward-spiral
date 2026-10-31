class_name DSEncounters
extends RefCounted
## Picks the monsters for a fight. Pure logic, seeded.


## Monster ids that can appear on `floor_num` for `kind` ("normal" | "elite").
static func pool(data: DSData, floor_num: int, kind: String = "normal") -> Array:
	var out: Array = []
	var ids := data.monsters.keys()
	ids.sort()
	for id in ids:
		var m: Dictionary = data.monsters[id]
		var floors: Array = m.get("floors", []).map(func(x): return int(x))
		if not floors.has(floor_num):
			continue
		var is_elite: bool = m.get("role", "") == "elite"
		if (kind == "elite") == is_elite:
			out.append(id)
	return out


## Roll a fight: 1-4 normal monsters (balance.fight_size), or one elite.
static func roll_fight(data: DSData, rng: DSRng, floor_num: int, level: int, kind: String = "normal") -> Array:
	var ids := pool(data, floor_num, kind)
	if ids.is_empty():
		ids = pool(data, 1, "normal")
	var size: Array = data.balance.get("fight_size", [1, 4])
	var n := 1 if kind == "elite" else rng.number_range(int(size[0]), int(size[1]))
	var picked: Array = []
	for i in n:
		picked.append(rng.pick(ids))
	var counts := {}
	for id in picked:
		counts[id] = int(counts.get(id, 0)) + 1
	var seen := {}
	var out: Array = []
	for i in picked.size():
		var id: String = picked[i]
		var m := DSFactory.make_monster(data, id, level, i)
		if int(counts[id]) > 1:
			seen[id] = int(seen.get(id, 0)) + 1
			m.name = "%s #%d" % [m.name, seen[id]]
		out.append(m)
	return out
