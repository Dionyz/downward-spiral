class_name DSMeta
extends RefCounted
## Between-runs progression: power-ups bought in town with gold (meta.json "upgrades").
## No account levels: every class, race and boon is open from the start. perks() is what a new
## run gets from the account.

const UPGRADES := ["skip", "reroll", "banish", "vitality", "might", "provisions", "fortune"]
const CHARGES := ["skip", "reroll", "banish"]


## How many of upgrade `id` the account has bought.
static func owned(account: Dictionary, id: String) -> int:
	return int(account.get("upgrades", {}).get(id, 0))


static func upgrade_cap(data: DSData, id: String) -> int:
	return int(data.meta.get("upgrades", {}).get(id, {}).get("max", data.meta.get("upgrade_max", 5)))


## Gold for the next purchase of `id` (doubles each time), or -1 when maxed.
static func upgrade_price(data: DSData, account: Dictionary, id: String) -> int:
	var n := owned(account, id)
	if n >= upgrade_cap(data, id):
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


## Boon-offer charges per run: base + bought (+ race bonus).
static func charges(data: DSData, account: Dictionary, race: String = "") -> Dictionary:
	var out := {}
	var rc: Dictionary = data.races.get(race, {}).get("effect", {}).get("charges", {})
	for id in CHARGES:
		out[id] = int(data.meta.get("upgrades", {}).get(id, {}).get("base", 0)) + owned(account, id) + int(rc.get(id, 0))
	return out


## Class mastery: per class, account-wide. Level 1-10 from total class XP (meta.json mastery_xp).
static func mastery_xp(account: Dictionary, line: String) -> int:
	return int(account.get("mastery", {}).get(line, 0))


static func mastery_level(data: DSData, account: Dictionary, line: String) -> int:
	var th: Array = data.meta.get("mastery_xp", [0])
	var xp := mastery_xp(account, line)
	var lvl := 1
	for i in th.size():
		if xp >= int(th[i]):
			lvl = i + 1
	return lvl


## XP needed for the next mastery level, or -1 at max.
static func mastery_next(data: DSData, level: int) -> int:
	var th: Array = data.meta.get("mastery_xp", [0])
	return int(th[level]) if level < th.size() else -1


## What a new run starts with: power-up bonuses, charges, and the class's mastery.
## No `line` (tests, balance): full mastery.
static func perks(data: DSData, account: Dictionary = {}, race: String = "", line: String = "") -> Dictionary:
	var ups: Dictionary = data.meta.get("upgrades", {})
	return {"classes": data.classes.keys(), "boon_tier": 99, "legendary_tier": 99,
		"hp_pct": owned(account, "vitality") * int(ups.get("vitality", {}).get("per", 4)),
		"damage_pct": owned(account, "might") * int(ups.get("might", {}).get("per", 4)),
		"potions": owned(account, "provisions"),
		"boon_luck": owned(account, "fortune"),
		"mastery": mastery_level(data, account, line) if line != "" else 10,
		"charges": charges(data, account, race)}


## For tests and the balance script: no power-ups.
static func all_unlocked(data: DSData) -> Dictionary:
	return perks(data, {})
