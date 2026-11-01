class_name DSAccount
extends RefCounted
## The save between runs: up to 10 characters (name, class, race, equipped loadout), one shared
## stash and gold purse, bought power-ups, and the town shop's stock. Pure logic on a Dictionary
## so it saves as JSON and tests without the UI.
##
## account = {gold, upgrades: {id: n}, stash: [item], characters: [char], current: int,
##            shop: [item], runs, deaths, extracts, victories, best_floor}
## char    = {name, line, race, loadout: {weapon, armor, trinket}, runs, kills, best_floor, victories}
##
## Gear you take into a run is carried, so it's at risk: dying loses everything you carry
## (DECISIONS.md D-076). Extracting or winning brings the equipped items back to the character's
## loadout and the bag into the stash.

const SLOTS := ["weapon", "armor", "trinket"]


static func fresh() -> Dictionary:
	return {"gold": 0, "upgrades": {}, "stash": [], "characters": [], "current": -1, "shop": [],
		"runs": 0, "deaths": 0, "extracts": 0, "victories": 0, "best_floor": 0, "rescue_used": false}


## The one-time rescue: the account's first death (any character) is turned into an emergency
## extraction. Call before bank_run; marks the run "rescued" if it applies.
static func apply_rescue(a: Dictionary, run: DSRunState) -> bool:
	if run.result != "death" or bool(a.get("rescue_used", false)):
		return false
	run.result = "rescued"
	return true


## Fill in anything an older save lacks (old saves had XP and levels; those are dropped).
static func migrate(a: Dictionary) -> Dictionary:
	var out := fresh()
	for k in a.keys():
		if out.has(k):
			out[k] = a[k]
	out["current"] = int(out["current"])
	if out["current"] >= out["characters"].size():
		out["current"] = out["characters"].size() - 1
	return out


static func max_characters(data: DSData) -> int:
	return int(data.meta.get("max_characters", 10))


static func stash_max(data: DSData) -> int:
	return int(data.meta.get("stash_max", 500))


# --- characters -----------------------------------------------------------------

## Create a character and make it current. Returns false if the roster is full or input is bad.
static func create_character(data: DSData, a: Dictionary, name: String, line: String, race: String) -> bool:
	if a["characters"].size() >= max_characters(data) or not data.classes.has(line) or not data.races.has(race):
		return false
	name = name.strip_edges().left(16)
	if name == "":
		return false
	var L: Dictionary = data.classes[line]
	var loadout := {"weapon": DSFactory.starting_weapon(data, str(L.get("starting_weapon", "dagger")), 1), "armor": null, "trinket": null}
	a["characters"].append({"name": name, "line": line, "race": race, "loadout": loadout,
		"runs": 0, "kills": 0, "best_floor": 0, "victories": 0})
	a["current"] = a["characters"].size() - 1
	return true


## Delete character `i`; its loadout goes to the stash.
static func delete_character(data: DSData, a: Dictionary, i: int) -> void:
	if i < 0 or i >= a["characters"].size():
		return
	var ch: Dictionary = a["characters"][i]
	for s in SLOTS:
		if ch["loadout"].get(s) != null:
			stash_add(data, a, [ch["loadout"][s]])
	a["characters"].remove_at(i)
	if int(a["current"]) >= a["characters"].size():
		a["current"] = a["characters"].size() - 1


static func current(a: Dictionary) -> Dictionary:
	var i := int(a.get("current", -1))
	if i < 0 or i >= a["characters"].size():
		return {}
	return a["characters"][i]


# --- stash -----------------------------------------------------------------------

## Add items to the stash. If it's full, the weakest items are sold. Returns gold from overflow.
static func stash_add(data: DSData, a: Dictionary, found: Array) -> int:
	var gold := 0
	for it in found:
		if it == null:
			continue
		a["stash"].append(it)
		if a["stash"].size() > stash_max(data):
			var worst := 0
			for j in a["stash"].size():
				if DSLoot.power(a["stash"][j]) < DSLoot.power(a["stash"][worst]):
					worst = j
			gold += sell_value(data, a["stash"][worst])
			a["stash"].remove_at(worst)
	a["gold"] = int(a["gold"]) + gold
	return gold


## Equip stash item `idx` on the current character; what was in that slot goes to the stash.
static func equip_from_stash(a: Dictionary, idx: int) -> bool:
	var ch := current(a)
	if ch.is_empty() or idx < 0 or idx >= a["stash"].size():
		return false
	var it: Dictionary = a["stash"][idx]
	var slot: String = it.get("slot", "weapon")
	a["stash"].remove_at(idx)
	var old = ch["loadout"].get(slot)
	ch["loadout"][slot] = it
	if old != null:
		a["stash"].append(old)
	return true


## Move the current character's item in `slot` to the stash (weapons can't be left empty).
static func unequip(a: Dictionary, slot: String) -> bool:
	var ch := current(a)
	if ch.is_empty() or slot == "weapon" or ch["loadout"].get(slot) == null:
		return false
	a["stash"].append(ch["loadout"][slot])
	ch["loadout"][slot] = null
	return true


# --- selling and the shop ---------------------------------------------------------

static func sell_value(data: DSData, it: Dictionary) -> int:
	return maxi(1, DSStats.idiv(DSLoot.power(it), int(data.meta.get("shop", {}).get("sell_div", 20))))


static func buy_price(data: DSData, it: Dictionary) -> int:
	return sell_value(data, it) * int(data.meta.get("shop", {}).get("buy_mult", 5))


static func sell(data: DSData, a: Dictionary, idx: int) -> int:
	if idx < 0 or idx >= a["stash"].size():
		return 0
	var g := sell_value(data, a["stash"][idx])
	a["stash"].remove_at(idx)
	a["gold"] = int(a["gold"]) + g
	return g


## Stash indexes a bulk sale would sell: the given rarities (and, if `only_worse`, only items
## weaker than what the current character wears in that slot). Never legendaries, and never an
## item that would be a pure upgrade for any of your characters.
static func bulk_preview(data: DSData, a: Dictionary, rarities: Array, only_worse: bool = false) -> Array:
	var ch := current(a)
	var out: Array = []
	for i in a["stash"].size():
		var it: Dictionary = a["stash"][i]
		var rar := str(it.get("rarity", "common"))
		if rar == "legendary" or not rarities.has(rar):
			continue
		if only_worse:
			var eq = ch["loadout"].get(it.get("slot", "")) if not ch.is_empty() else null
			if eq == null or DSLoot.power(it) >= DSLoot.power(eq):
				continue
		var wanted := false
		for c in a["characters"]:
			var worn = c["loadout"].get(it.get("slot", ""))
			if worn != null and DSRunState.is_pure_upgrade(it, worn):
				wanted = true
				break
		if not wanted:
			out.append(i)
	return out


## Sell what bulk_preview picks. Returns {count, gold}.
static func bulk_sell(data: DSData, a: Dictionary, rarities: Array, only_worse: bool = false) -> Dictionary:
	var pick := bulk_preview(data, a, rarities, only_worse)
	var keep: Array = []
	var g := 0
	for i in a["stash"].size():
		if pick.has(i):
			g += sell_value(data, a["stash"][i])
		else:
			keep.append(a["stash"][i])
	a["stash"] = keep
	a["gold"] = int(a["gold"]) + g
	return {"count": pick.size(), "gold": g}


static func preview_gold(data: DSData, a: Dictionary, idx: Array) -> int:
	var g := 0
	for i in idx:
		g += sell_value(data, a["stash"][i])
	return g


## Restock the shop: items sized to how deep this account has been, for the current class.
static func roll_shop(data: DSData, a: Dictionary, rng: DSRng) -> void:
	var ch := current(a)
	var line: String = ch.get("line", "")
	var deep := maxi(1, int(a.get("best_floor", 0)))
	var ilvl := clampi(deep * 2, 1, 10)
	a["shop"] = []
	for i in int(data.meta.get("shop", {}).get("stock", 6)):
		var slot: String = SLOTS[i % SLOTS.size()]
		var rar := "uncommon" if i < 3 else ""
		a["shop"].append(DSLoot.roll_item(data, rng, ilvl, slot, rar, line))


static func buy(data: DSData, a: Dictionary, i: int) -> bool:
	if i < 0 or i >= a["shop"].size():
		return false
	var it: Dictionary = a["shop"][i]
	var price := buy_price(data, it)
	if int(a["gold"]) < price:
		return false
	a["gold"] = int(a["gold"]) - price
	a["shop"].remove_at(i)
	stash_add(data, a, [it])
	return true


# --- runs -------------------------------------------------------------------------

## Start a run for the current character: its loadout goes with it (and is at risk).
static func start_run(data: DSData, a: Dictionary, seed_value: int) -> DSRunState:
	var ch := current(a)
	if ch.is_empty():
		return null
	var r := DSRunState.new_run(data, str(ch["line"]), seed_value, DSMeta.perks(data, a, str(ch["race"])),
		str(ch["race"]), ch["loadout"])
	ch["loadout"] = {"weapon": null, "armor": null, "trinket": null}
	ch["in_run"] = true
	return r


## Bank a finished run. Death: nothing comes home but the character keeps its record (and gets a
## plain starting weapon back so it can go again). Extract/victory: gold, equipped gear, and the bag.
static func bank_run(data: DSData, a: Dictionary, run: DSRunState) -> Dictionary:
	var ch := current(a)
	var out := {"gold": 0, "items": 0, "lost": 0}
	a["runs"] = int(a["runs"]) + 1
	a["best_floor"] = maxi(int(a["best_floor"]), run.floor_num)
	var key: String = {"death": "deaths", "rescued": "deaths", "extract": "extracts", "victory": "victories"}.get(run.result, "")
	if key != "":
		a[key] = int(a.get(key, 0)) + 1
	if not ch.is_empty():
		ch["runs"] = int(ch["runs"]) + 1
		ch["kills"] = int(ch["kills"]) + int(run.stats.get("kills", 0))
		ch["best_floor"] = maxi(int(ch["best_floor"]), run.floor_num)
		ch.erase("in_run")
		if run.result == "victory":
			ch["victories"] = int(ch["victories"]) + 1
	var carried: Array = run.inventory.duplicate()
	for s in SLOTS:
		if run.items.get(s) != null:
			carried.append(run.items[s])
	if run.result == "rescued":
		# Keep the gear brought in and half the gold; everything found this run is lost.
		a["rescue_used"] = true
		var g := DSStats.idiv(run.gold, 2)
		a["gold"] = int(a["gold"]) + g
		out["gold"] = g
		out["rescued"] = true
		var kept := 0
		if not ch.is_empty():
			for s in SLOTS:
				ch["loadout"][s] = run.start_loadout.get(s)
				if ch["loadout"][s] != null:
					kept += 1
		out["lost"] = maxi(0, carried.size() - kept)
		return out
	if run.result == "death":
		out["lost"] = carried.size()
		if not ch.is_empty() and ch["loadout"].get("weapon") == null:
			var L: Dictionary = data.classes.get(str(ch["line"]), {})
			ch["loadout"]["weapon"] = DSFactory.starting_weapon(data, str(L.get("starting_weapon", "dagger")), 1)
		return out
	a["gold"] = int(a["gold"]) + run.gold
	out["gold"] = run.gold
	if not ch.is_empty():
		for s in SLOTS:
			ch["loadout"][s] = run.items.get(s)
	stash_add(data, a, run.inventory)
	out["items"] = carried.size()
	return out
