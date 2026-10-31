class_name DSEncounters
extends RefCounted
## Picks the monsters for a fight. Pure logic, seeded.


## Monster ids that can appear on `floor_num` for `kind` ("normal" | "elite" | "boss").
static func pool(data: DSData, floor_num: int, kind: String = "normal") -> Array:
	var out: Array = []
	var ids := data.monsters.keys()
	ids.sort()
	for id in ids:
		var m: Dictionary = data.monsters[id]
		var floors: Array = m.get("floors", []).map(func(x): return int(x))
		if not floors.has(floor_num):
			continue
		var role: String = m.get("role", "")
		var want := kind
		if role == "elite" or role == "boss":
			if role == want:
				out.append(id)
		elif want == "normal":
			out.append(id)
	return out


## Monster ids for a fight: 1-4 normal monsters (balance.fight_size), or one elite/boss.
static func roll_ids(data: DSData, rng: DSRng, floor_num: int, kind: String = "normal") -> Array:
	var ids := pool(data, floor_num, kind)
	if ids.is_empty() and kind != "normal":
		# Fall back to the nearest floor that has one.
		for f in range(floor_num, 0, -1):
			ids = pool(data, f, kind)
			if not ids.is_empty():
				break
	if ids.is_empty():
		ids = pool(data, 1, "normal")
	var size: Array = data.balance.get("fight_size", [1, 4])
	var n := 1 if kind != "normal" else rng.number_range(int(size[0]), int(size[1]))
	var picked: Array = []
	for i in n:
		picked.append(rng.pick(ids))
	return picked


## Build Combatants for ids at `level`, numbering duplicates ("a sewer rat #2").
static func build(data: DSData, ids: Array, level: int) -> Array:
	var counts := {}
	for id in ids:
		counts[id] = int(counts.get(id, 0)) + 1
	var seen := {}
	var out: Array = []
	for i in ids.size():
		var id: String = ids[i]
		var m := DSFactory.make_monster(data, id, level, i)
		_group_scale(data, m, ids.size())
		if int(counts[id]) > 1:
			seen[id] = int(seen.get(id, 0)) + 1
			m.name = "%s #%d" % [m.name, seen[id]]
		out.append(m)
	return out


## Bigger packs are made of weaker members (balance.group_scale: size -> [hp mult, damage mult]).
static func _group_scale(data: DSData, m: Combatant, n: int) -> void:
	var gs: Dictionary = data.balance.get("group_scale", {})
	if not gs.has(str(n)):
		return
	var f: Array = gs[str(n)]
	m.max_hp = maxi(1, int(m.max_hp * float(f[0])))
	m.hp = m.max_hp
	m.dmg_min = maxi(1, int(m.dmg_min * float(f[1])))
	m.dmg_max = maxi(m.dmg_min, int(m.dmg_max * float(f[1])))
	for k in m.monster_abilities.keys():
		var a: Dictionary = m.monster_abilities[k]
		if a.has("min"):
			a["min"] = maxi(1, int(a["min"] * float(f[1])))
			a["max"] = maxi(a["min"], int(a["max"] * float(f[1])))


static func roll_fight(data: DSData, rng: DSRng, floor_num: int, level: int, kind: String = "normal") -> Array:
	return build(data, roll_ids(data, rng, floor_num, kind), level)
