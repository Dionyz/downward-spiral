class_name DSMeta
extends RefCounted
## Account progression from banked XP (meta.json). Unlocks options, not raw power.
## perks(): what a new run gets from the account.


static func level_for(data: DSData, xp: int) -> int:
	var th: Array = data.meta.get("xp_thresholds", [0])
	var lvl := 1
	for i in th.size():
		if xp >= int(th[i]):
			lvl = i + 1
	return lvl


## XP needed for the next account level, or -1 at max.
static func next_threshold(data: DSData, level: int) -> int:
	var th: Array = data.meta.get("xp_thresholds", [0])
	return int(th[level]) if level < th.size() else -1


## Everything unlocked at or below `level`.
static func perks(data: DSData, level: int) -> Dictionary:
	var out := {"level": level, "classes": [str(data.meta.get("starting_class", "warrior"))], "rule_slots": 0,
		"hp_pct": 0, "damage_pct": 0, "boon_tier": 1, "legendary_tier": 1, "potions": 0}
	var lv: Dictionary = data.meta.get("levels", {})
	for i in range(2, level + 1):
		var u: Dictionary = lv.get(str(i), {})
		for c in u.get("classes", []):
			if not out["classes"].has(c):
				out["classes"].append(c)
		for k in ["rule_slots", "hp_pct", "damage_pct", "potions"]:
			out[k] = int(out[k]) + int(u.get(k, 0))
		for k in ["boon_tier", "legendary_tier"]:
			out[k] = maxi(int(out[k]), int(u.get(k, 0)))
	var cap := int(data.meta.get("bonus_cap_pct", 10))
	out["hp_pct"] = mini(int(out["hp_pct"]), cap)
	out["damage_pct"] = mini(int(out["damage_pct"]), cap)
	return out


## For testing and the balance script: everything unlocked, no stat bonuses.
static func all_unlocked(data: DSData) -> Dictionary:
	var p := perks(data, 1)
	p["classes"] = data.classes.keys()
	p["boon_tier"] = 99
	p["legendary_tier"] = 99
	return p


## Unlock text for each level (for the account screen).
static func unlock_text(data: DSData, level: int) -> String:
	return str(data.meta.get("levels", {}).get(str(level), {}).get("text", ""))


## Which account level unlocks class `line` (1 = from the start, -1 = never).
static func class_unlock_level(data: DSData, line: String) -> int:
	if line == str(data.meta.get("starting_class", "warrior")):
		return 1
	var lv: Dictionary = data.meta.get("levels", {})
	for k in lv.keys():
		if line in lv[k].get("classes", []):
			return int(k)
	return -1
