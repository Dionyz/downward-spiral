class_name DSLoot
extends RefCounted
## Item generation from items.json. Pure logic, seeded.
## Item dict: {slot, name, rarity, ilvl, type?, min?, max?, dam_type?, level?, ac?, flags[], affixes[],
##             passive?, skill_bonus{}, damroll, hp, mana, power}


static func roll_rarity(data: DSData, rng: DSRng, floor_bonus: float = 0.0) -> String:
	var rar: Dictionary = data.items.get("rarities", {})
	var weights := {}
	var order: Array = data.items.get("rarity_order", rar.keys())
	for i in order.size():
		var k: String = order[i]
		# Deeper floors shift weight toward rarer items. Weights x100 to keep integer picks.
		var w := float(rar[k].get("weight", 1)) * (1.0 + floor_bonus * float(i))
		weights["%d_%s" % [i, k]] = int(round(w * 100.0))
	var picked: String = rng.weighted_pick(weights)
	return picked.substr(picked.find("_") + 1)


## Roll one item. `slot` "" = random; `line` biases weapon type toward the class.
static func roll_item(data: DSData, rng: DSRng, ilvl: int, slot: String = "", rarity: String = "", line: String = "") -> Dictionary:
	var it: Dictionary = data.items
	if slot == "":
		slot = rng.pick(it.get("slots", ["weapon", "armor", "trinket"]))
	if rarity == "":
		rarity = roll_rarity(data, rng, 0.08 * float(ilvl - 1))
	var rdef: Dictionary = it.get("rarities", {}).get(rarity, {})
	var mult := float(rdef.get("mult", 1.0))
	var item := {"slot": slot, "rarity": rarity, "ilvl": ilvl, "flags": [], "affixes": [], "skill_bonus": {},
		"damroll": 0, "hp": 0, "mana": 0}
	var base_name := ""
	match slot:
		"weapon":
			var types: Array = it.get("class_weapons", {}).get(line, it.get("weapon_types", {}).keys())
			var wt: String = rng.pick(types)
			var wdef: Dictionary = it["weapon_types"][wt]
			var mn: Array = wdef.get("min", [5, 2])
			var mx: Array = wdef.get("max", [10, 4])
			item["type"] = wt
			item["dam_type"] = wdef.get("dam_type", "slash")
			item["min"] = int(round((float(mn[0]) + float(mn[1]) * (ilvl - 1)) * mult))
			item["max"] = int(round((float(mx[0]) + float(mx[1]) * (ilvl - 1)) * mult))
			item["level"] = ilvl * int(data.balance.get("level_scale", 10))
			var names: Array = it.get("weapon_names", {}).get(wt, [wdef.get("name", wt)])
			base_name = names[mini(names.size() - 1, DSStats.idiv((ilvl - 1) * names.size(), 10))]
		"armor":
			item["ac"] = int(float(it.get("armor", {}).get("ac_per_level", -90)) * ilvl * mult)
			var an: Array = it.get("armor", {}).get("names", ["Armor"])
			base_name = an[mini(an.size() - 1, DSStats.idiv((ilvl - 1) * an.size(), 10))]
		"trinket":
			var tn: Array = it.get("trinket", {}).get("names", ["Charm"])
			base_name = rng.pick(tn)
			item["damroll"] = int(ilvl * 2 * mult)
	# Affixes.
	var pool: Array = []
	var affs: Dictionary = it.get("affixes", {})
	var akeys := affs.keys()
	akeys.sort()
	for k in akeys:
		if slot in affs[k].get("slots", []):
			pool.append(k)
	rng.shuffle(pool)
	var prefix := ""
	var suffix := ""
	for i in mini(int(rdef.get("affixes", 0)), pool.size()):
		var k: String = pool[i]
		var a: Dictionary = affs[k]
		item["affixes"].append(k)
		for f in a.get("flags", []):
			if not item["flags"].has(f):
				item["flags"].append(f)
		item["damroll"] += int(a.get("damroll_per_level", 0)) * ilvl
		item["hp"] += int(a.get("hp_per_level", 0)) * ilvl
		item["mana"] += int(a.get("mana_per_level", 0)) * ilvl
		if a.has("ac_per_level"):
			item["ac"] = int(item.get("ac", 0)) + int(a["ac_per_level"]) * ilvl
		var sb: Dictionary = a.get("skill_bonus", {})
		for s in sb.keys():
			item["skill_bonus"][s] = int(item["skill_bonus"].get(s, 0)) + int(sb[s])
		var nm: String = a.get("name", k)
		if nm.begins_with("of "):
			if suffix == "":
				suffix = nm
		elif prefix == "":
			prefix = nm
	if slot == "trinket":
		# Trinkets always nudge one of the class's passives.
		var tb := int(it.get("trinket", {}).get("skill_bonus", 5))
		var sk: String = rng.pick(["parry", "dodge", "second attack", "enhanced damage", "third attack"])
		item["skill_bonus"][sk] = int(item["skill_bonus"].get(sk, 0)) + tb
	# Legendary special passive.
	if rdef.get("passive", false):
		var lp: Dictionary = it.get("legendary_passives", {})
		var lkeys: Array = []
		for k in lp.keys():
			if slot in lp[k].get("slots", []):
				lkeys.append(k)
		lkeys.sort()
		if not lkeys.is_empty():
			item["passive"] = rng.pick(lkeys)
		var ln: Array = it.get("legendary_names", [])
		item["name"] = "%s, %s" % [base_name, rng.pick(ln)] if not ln.is_empty() else base_name
	else:
		var parts: Array = []
		if prefix != "":
			parts.append(prefix)
		parts.append(base_name)
		if suffix != "":
			parts.append(suffix)
		item["name"] = " ".join(PackedStringArray(parts))
	item["power"] = power(item)
	return item


## Rough single-number score so the UI can say "better" / "worse".
static func power(item: Dictionary) -> int:
	var p := 0
	match item.get("slot", ""):
		"weapon":
			p += (int(item.get("min", 0)) + int(item.get("max", 0))) * 5
		"armor":
			p += -int(item.get("ac", 0))
	p += int(item.get("damroll", 0)) * 4
	p += int(item.get("hp", 0)) * 2
	p += int(item.get("mana", 0))
	for v in item.get("skill_bonus", {}).values():
		p += int(v) * 6
	p += item.get("flags", []).size() * 25
	if item.has("passive"):
		p += 150
	return p
