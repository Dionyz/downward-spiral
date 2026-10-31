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
	var out := {"level": level, "classes": [str(data.meta.get("starting_class", "warrior"))],
		"hp_pct": 0, "damage_pct": 0, "boon_tier": 1, "legendary_tier": 1, "potions": 0}
	var lv: Dictionary = data.meta.get("levels", {})
	for i in range(2, level + 1):
		var u: Dictionary = lv.get(str(i), {})
		for c in u.get("classes", []):
			if not out["classes"].has(c):
				out["classes"].append(c)
		for k in ["hp_pct", "damage_pct", "potions"]:
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
	p["charges"] = charges(data, {})
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


# --- boon-offer charges bought with banked gold -----------------------------------

const UPGRADES := ["skip", "reroll", "banish"]


## How many of upgrade `id` the account has bought.
static func owned(account: Dictionary, id: String) -> int:
	return int(account.get("upgrades", {}).get(id, 0))


## Gold for the next purchase of `id` (doubles each time), or -1 when maxed.
static func upgrade_price(data: DSData, account: Dictionary, id: String) -> int:
	var n := owned(account, id)
	if n >= int(data.meta.get("upgrade_max", 5)):
		return -1
	return int(data.meta.get("upgrades", {}).get(id, {}).get("price", 100)) * int(pow(2, n))


## Buy one level of `id`. Returns the updated account, or the same one if unaffordable/maxed.
static func buy_upgrade(data: DSData, account: Dictionary, id: String) -> Dictionary:
	var price := upgrade_price(data, account, id)
	if price < 0 or int(account.get("gold", 0)) < price:
		return account
	var a := account.duplicate(true)
	a["gold"] = int(a.get("gold", 0)) - price
	var up: Dictionary = a.get("upgrades", {})
	up[id] = owned(account, id) + 1
	a["upgrades"] = up
	return a


## Charges per run: the base amount plus what the account bought.
static func charges(data: DSData, account: Dictionary) -> Dictionary:
	var out := {}
	for id in UPGRADES:
		out[id] = int(data.meta.get("upgrades", {}).get(id, {}).get("base", 0)) + owned(account, id)
	return out
