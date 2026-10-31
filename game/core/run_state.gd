class_name DSRunState
extends RefCounted
## One run, start to finish: floors, rooms, rewards, boons, items, XP, gold, extraction, death.
## Pure logic and plain data: to_dict()/from_dict() is the save file. The UI only calls methods here.
##
## Phases:
##   "path"      between rooms; at_fork() says whether the player must pick a room
##   "room"      inside a room (fight not finished / choice not made yet)
##   "reward"    after a won fight: loot already landed in the inventory; pick 1 of 3 boons (or skip)
##   "floor_end" floor cleared; descend() or extract() (extract from floor 2 on)
##   "over"      run ended; result is "death", "extract" or "victory"

const FLOORS := 6
const SLOTS := ["weapon", "armor", "trinket"]
const INVENTORY_MAX := 500

var data: DSData
var rng: DSRng
var seed_value: int = 1
var line: String = "warrior"
var level: int = 1
var xp: int = 0               # toward next level
var xp_total: int = 0         # earned this run (converted to account XP at the end)
var gold: int = 0
var hp: int = -1              # -1 = full
var mana: int = -1
var potions := {"hp": 2, "mp": 2}
var items := {"weapon": null, "armor": null, "trinket": null}   # equipped, one per slot
var inventory: Array = []     # everything else you carry (max INVENTORY_MAX)
var boons: Array = []
var floor_num: int = 1
var floor_data: Dictionary = {}
var step: int = 0
var room: Dictionary = {}
var phase: String = "path"
var result: String = ""
var stats := {"kills": 0, "fights": 0, "rooms": 0, "gold_earned": 0}
var perks: Dictionary = {}    # account perks this run started with (DSMeta.perks)
var messages: Array = []      # short lines for the UI (level ups, loot); cleared by the UI


# ---------------------------------------------------------------------------
# Setup and save
# ---------------------------------------------------------------------------

## `p_perks` = DSMeta.perks(...) for the player's account; omitted = everything unlocked, no bonuses.
static func new_run(p_data: DSData, p_line: String, p_seed: int, p_perks: Dictionary = {}) -> DSRunState:
	var r := DSRunState.new()
	r.data = p_data
	r.perks = p_perks.duplicate(true) if not p_perks.is_empty() else DSMeta.all_unlocked(p_data)
	r.seed_value = p_seed
	r.rng = DSRng.new(p_seed)
	r.line = p_line
	var ps: Dictionary = r._cfg().get("potions_start", {"hp": 2, "mp": 2})
	r.potions = {"hp": int(ps.get("hp", 2)) + int(r.perks.get("potions", 0)), "mp": int(ps.get("mp", 2)) if r._has_mana() else 0}
	var L: Dictionary = p_data.classes.get(p_line, {})
	r.items["weapon"] = DSFactory.starting_weapon(p_data, str(L.get("starting_weapon", "dagger")), 1)
	r._new_floor()
	return r


func to_dict() -> Dictionary:
	return {
		"version": 1, "seed": seed_value, "rng": rng.save_state(), "line": line, "level": level, "xp": xp,
		"xp_total": xp_total, "gold": gold, "hp": hp, "mana": mana, "potions": potions.duplicate(),
		"items": items.duplicate(true), "inventory": inventory.duplicate(true), "boons": boons.duplicate(),
		"floor_num": floor_num, "floor_data": floor_data.duplicate(true),
		"step": step, "room": room.duplicate(true), "phase": phase, "result": result, "stats": stats.duplicate(), "perks": perks.duplicate(true),
	}


static func from_dict(p_data: DSData, d: Dictionary) -> DSRunState:
	var r := DSRunState.new()
	r.data = p_data
	r.seed_value = int(d.get("seed", 1))
	r.rng = DSRng.new(r.seed_value)
	r.rng.load_state(int(d.get("rng", 1)))
	r.line = str(d.get("line", "warrior"))
	r.level = int(d.get("level", 1))
	r.xp = int(d.get("xp", 0))
	r.xp_total = int(d.get("xp_total", 0))
	r.gold = int(d.get("gold", 0))
	r.hp = int(d.get("hp", -1))
	r.mana = int(d.get("mana", -1))
	r.potions = _normalize(d.get("potions", {}))
	r.items = _normalize(d.get("items", r.items))
	r.boons = _normalize(d.get("boons", []))
	r.inventory = _normalize(d.get("inventory", []))
	r.floor_num = int(d.get("floor_num", 1))
	r.floor_data = _normalize(d.get("floor_data", {}))
	r.step = int(d.get("step", 0))
	r.room = _normalize(d.get("room", {}))
	r.phase = str(d.get("phase", "path"))
	r.result = str(d.get("result", ""))
	r.stats = _normalize(d.get("stats", r.stats))
	r.perks = _normalize(d.get("perks", {}))
	if r.perks.is_empty():
		r.perks = DSMeta.all_unlocked(p_data)
	return r


## JSON turns ints into floats; convert dictionaries of numbers back.
static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[k] = int(d[k]) if typeof(d[k]) == TYPE_FLOAT else d[k]
	return out


static func _normalize(v):
	if typeof(v) == TYPE_DICTIONARY:
		var out := {}
		for k in v.keys():
			out[k] = _normalize(v[k])
		return out
	if typeof(v) == TYPE_ARRAY:
		return v.map(func(x): return _normalize(x))
	if typeof(v) == TYPE_FLOAT and v == floor(v) and absf(v) < 1e15:
		return int(v)
	return v


func _cfg() -> Dictionary:
	return data.balance.get("run", {})


func _has_mana() -> bool:
	var st: Dictionary = data.classes.get(line, {}).get("stats", {})
	return int(st.get("mana_base", 0)) > 0


# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------

## A fresh Combatant reflecting the run: level, gear, boons, current HP/mana.
## The character carries every ability it knows and fights by its class's built-in priorities.
func make_player() -> Combatant:
	var opts := {"rules": DSFactory.class_ai(data, line, tier(), level), "actives": known_actives(), "weapon": items["weapon"],
		"meta_hp_pct": int(perks.get("hp_pct", 0)), "meta_damage_pct": int(perks.get("damage_pct", 0))}
	if items["armor"] != null:
		opts["armor"] = items["armor"]
	if items["trinket"] != null:
		opts["trinket"] = items["trinket"]
	var p := DSFactory.make_player(data, line, tier(), level, opts)
	DSFactory.apply_boons(data, p, boons)
	if hp >= 0:
		p.hp = clampi(hp, 1, p.max_hp)
	if mana >= 0:
		p.mana = clampi(mana, 0, p.max_mana)
	return p


## Unlock schedule tier. Promotions are out, so every character uses one tier all run
## (balance.unlock_tier, default 3: the spec's v1 classes are the top-tier lines). DECISIONS.md D-045.
func tier() -> int:
	return int(data.balance.get("unlock_tier", 3))


## Every active the character knows at its level (all are used in fights).
func known_actives() -> Array:
	return data.kit_abilities(line, tier(), level, "active")


func monster_level() -> int:
	var fl: Dictionary = _cfg().get("floor_monster_level", {})
	return int(fl.get(str(floor_num), floor_num))


func item_level() -> int:
	return clampi(monster_level(), 1, 10)


# ---------------------------------------------------------------------------
# Floors and rooms
# ---------------------------------------------------------------------------

func _new_floor() -> void:
	floor_data = DSDungeonGen.generate(rng, floor_num, data.rooms)
	step = 0
	room = {}
	phase = "path"


func steps() -> Array:
	return floor_data.get("steps", [])


func current_step() -> Array:
	var s := steps()
	return s[step] if step < s.size() else []


func at_fork() -> bool:
	return phase == "path" and current_step().size() > 1


## Enter the room at `choice` of the current step (0 unless it's a fork).
func enter(choice: int = 0) -> Dictionary:
	if phase != "path":
		return room
	var options := current_step()
	if options.is_empty():
		return {}
	room = options[clampi(choice, 0, options.size() - 1)].duplicate(true)
	room["chosen"] = choice
	# Remember which room was taken at each step (the map draws the walked path).
	var taken: Array = floor_data.get("taken", [])
	while taken.size() <= step:
		taken.append(0)
	taken[step] = choice
	floor_data["taken"] = taken
	stats["rooms"] = int(stats["rooms"]) + 1
	match room["type"]:
		"fight", "elite", "boss":
			var kind := "normal" if room["type"] == "fight" else str(room["type"])
			var lvl := monster_level()
			if kind == "elite":
				lvl += int(_cfg().get("elite_level_bonus", 1))
			elif kind == "boss":
				lvl = int(_cfg().get("boss_level", 10))
			room["monsters"] = DSEncounters.roll_ids(data, rng, floor_num, kind)
			room["monster_level"] = lvl
			room["fight_seed"] = rng.next_int()
		"treasure":
			var found: Array = []
			for i in int(_cfg().get("treasure_items", 3)):
				found.append(_roll_item("uncommon" if i == 0 else ""))
			room["loot"] = gain_items(found)
		"shrine":
			room["offers"] = _boon_offers(3)
		"event":
			var ids := data.events.keys()
			ids.sort()
			room["event"] = rng.pick(ids)
	phase = "room"
	return room


func is_fight_room() -> bool:
	return phase == "room" and room.get("type", "") in ["fight", "elite", "boss"]


## Monsters for the current fight room. Same every time (resume restarts the fight identically).
func fight_monsters() -> Array:
	return DSEncounters.build(data, room.get("monsters", []), int(room.get("monster_level", 1)))


func fight_rng() -> DSRng:
	return DSRng.new(int(room.get("fight_seed", 1)))


## Record a finished fight. `potions_left` = potions after any drunk during the fight.
func finish_fight(p: Combatant, foes: Array, fight_result: String, potions_left: Dictionary = {}) -> Dictionary:
	if not potions_left.is_empty():
		potions = potions_left.duplicate()
	hp = p.hp
	mana = p.mana
	stats["fights"] = int(stats["fights"]) + 1
	if fight_result != "win":
		end_run("death")
		return {}
	var kind := "normal" if room.get("type") == "fight" else str(room.get("type"))
	var c := _cfg()
	var gained_xp := 0
	var gained_gold := 0
	for f in foes:
		if f.is_alive():
			continue
		stats["kills"] = int(stats["kills"]) + 1
		gained_xp += f.level * int(c.get("xp_per_monster_level", 10)) * int(c.get("xp_mult", {}).get(kind, 1))
		gained_gold += (f.level * int(c.get("gold_per_monster_level", 3)) + rng.number_range(0, 3)) * int(c.get("gold_mult", {}).get(kind, 1))
	if boons.has("quick_study"):
		gained_xp += DSStats.idiv(gained_xp, 4)
	if boons.has("scavenger"):
		gained_gold += DSStats.idiv(gained_gold, 2)
	gold += gained_gold
	stats["gold_earned"] = int(stats["gold_earned"]) + gained_gold
	var reward := {"gold": gained_gold, "xp": gained_xp, "levels": add_xp(gained_xp)}
	if boons.has("catch_breath"):
		_heal_pct(10, 10)
	if rng.number_percent() <= int(c.get("potion_drop_pct", 20)):
		var kind_p := "mp" if _has_mana() and rng.number_percent() <= 40 else "hp"
		if _add_potion(kind_p):
			reward["potion"] = kind_p
	if kind != "boss":
		reward["loot"] = gain_items(_fight_loot(kind == "elite"))
		reward["offers"] = _boon_offers(3)
	else:
		reward["loot"] = []
		reward["offers"] = []
	room["reward"] = reward
	phase = "reward"
	return reward


## Take boon offer `i` (after a fight, or at a shrine).
func take_offer(i: int) -> void:
	var offers: Array = room.get("reward", {}).get("offers", []) if phase == "reward" else room.get("offers", [])
	if i < 0 or i >= offers.size():
		return
	var o: Dictionary = offers[i]
	if o.get("kind") == "boon":
		add_boon(str(o["id"]))
	complete_room()


## Skip the reward / leave the treasure or shrine.
func skip() -> void:
	if phase in ["reward", "room"]:
		complete_room()


## Put `item` in its slot. Whatever was there goes back into the inventory.
func equip(item: Dictionary) -> void:
	var slot: String = item.get("slot", "weapon")
	var old = items.get(slot)
	var before := make_player()
	items[slot] = item
	var after := make_player()
	# Keep HP/mana loss the same when max HP/mana changes with gear.
	if hp >= 0:
		hp = clampi(hp + after.max_hp - before.max_hp, 1, after.max_hp)
	if mana >= 0:
		mana = clampi(mana + after.max_mana - before.max_mana, 0, after.max_mana)
	if old != null:
		inventory.append(old)
	messages.append("Equipped %s." % item.get("name", "?"))


## Equip inventory item `i` (swapping out what that slot held). Allowed between rooms.
func equip_from_inventory(i: int) -> bool:
	if i < 0 or i >= inventory.size() or phase in ["over"]:
		return false
	var it: Dictionary = inventory[i]
	inventory.remove_at(i)
	equip(it)
	return true


## Add found items: an empty slot is filled straight away, everything else goes to the inventory.
## Past INVENTORY_MAX the weakest carried item is sold for gold. Returns [{item, equipped}].
func gain_items(found: Array) -> Array:
	var out: Array = []
	for it in found:
		var slot: String = it.get("slot", "weapon")
		if items.get(slot) == null:
			equip(it)
			out.append({"item": it, "equipped": true})
			continue
		inventory.append(it)
		out.append({"item": it, "equipped": false})
		if inventory.size() > INVENTORY_MAX:
			var worst := 0
			for j in inventory.size():
				if DSLoot.power(inventory[j]) < DSLoot.power(inventory[worst]):
					worst = j
			var sold: Dictionary = inventory[worst]
			inventory.remove_at(worst)
			var price := maxi(1, DSStats.idiv(DSLoot.power(sold), 20))
			gold += price
			messages.append("Bag full: sold %s for %d gold." % [sold.get("name", "?"), price])
	return out


## Inventory items for `slot`, strongest first, with their inventory index: [{i, item}].
func inventory_for(slot: String) -> Array:
	var out: Array = []
	for i in inventory.size():
		if inventory[i].get("slot", "") == slot:
			out.append({"i": i, "item": inventory[i]})
	out.sort_custom(func(a, b): return DSLoot.power(a["item"]) > DSLoot.power(b["item"]))
	return out


func add_boon(id: String) -> void:
	if not boons.has(id) and data.boons.has(id):
		boons.append(id)
		if id == "deep_pockets":
			_add_potion("hp")
		messages.append("Boon: %s." % data.boons[id].get("name", id))


# --- shrine ---

func shrine_remove_cost() -> int:
	return int(_cfg().get("shrine_remove_cost_per_floor", 30)) * floor_num


func shrine_reroll_cost() -> int:
	return int(_cfg().get("shrine_reroll_cost_per_floor", 20)) * floor_num


func shrine_remove(id: String) -> bool:
	if room.get("type") != "shrine" or phase != "room" or not boons.has(id) or gold < shrine_remove_cost():
		return false
	gold -= shrine_remove_cost()
	boons.erase(id)
	messages.append("Removed %s." % data.boons.get(id, {}).get("name", id))
	complete_room()
	return true


func shrine_reroll() -> bool:
	if room.get("type") != "shrine" or phase != "room" or gold < shrine_reroll_cost():
		return false
	gold -= shrine_reroll_cost()
	room["offers"] = _boon_offers(3)
	return true


# --- rest ---

func rest_heal() -> void:
	if room.get("type") != "rest" or phase != "room":
		return
	var pct := int(_cfg().get("rest_heal_pct", 40))
	_heal_pct(pct, pct)
	messages.append("You rest and recover.")
	complete_room()


# --- event ---

func event_def() -> Dictionary:
	return data.events.get(room.get("event", ""), {})


## Pick option `i` of the current event. Returns the outcome lines.
func event_choose(i: int) -> Array:
	if room.get("type") != "event" or phase != "room" or room.has("outcome"):
		return room.get("outcome", [])
	var opts: Array = event_def().get("options", [])
	if i < 0 or i >= opts.size():
		return []
	var lines: Array = []
	var found_item = null
	for op in opts[i].get("ops", []):
		found_item = _apply_op(op, lines, found_item)
	if found_item != null:
		var got := gain_items([found_item])
		lines.append("Found %s%s." % [found_item.get("name", "?"), " (equipped)" if got[0]["equipped"] else " (in your bag)"])
	room["outcome"] = lines
	return lines


func _apply_op(op: Dictionary, lines: Array, found_item):
	if op.has("chance"):
		var ch: Dictionary = op["chance"]
		var branch: Array = ch.get("win", []) if rng.number_percent() <= int(ch.get("pct", 50)) else ch.get("lose", [])
		for sub in branch:
			found_item = _apply_op(sub, lines, found_item)
		return found_item
	if op.has("text"):
		lines.append(str(op["text"]))
	if op.has("hp_pct"):
		var v := int(op["hp_pct"])
		_heal_pct(v, 0)
		lines.append(("You recover %d%% HP." if v > 0 else "You lose %d%% HP.") % absi(v))
	if op.has("mana_pct") and _has_mana():
		_heal_pct(0, int(op["mana_pct"]))
	if op.has("gold"):
		var g := int(op["gold"])
		gold = maxi(0, gold + g)
		lines.append(("+%d gold." if g >= 0 else "%d gold.") % g)
	if op.has("xp"):
		var lv := add_xp(int(op["xp"]))
		lines.append("+%d XP." % int(op["xp"]) + (" Level up!" if lv > 0 else ""))
	if op.has("potion"):
		var k := str(op["potion"])
		if k == "mp" and not _has_mana():
			k = "hp"
		if _add_potion(k):
			lines.append("+1 %s potion." % k.to_upper())
	if op.has("boon"):
		var offers := _boon_offers(1)
		if not offers.is_empty():
			add_boon(str(offers[0]["id"]))
			lines.append("Boon: %s." % data.boons[offers[0]["id"]].get("name", ""))
	if op.has("item"):
		found_item = _roll_item(str(op["item"]))
	return found_item


func _heal_pct(hp_pct: int, mana_pct: int) -> void:
	var p := make_player()
	var cur_hp := p.hp
	var cur_mana := p.mana
	hp = clampi(cur_hp + int(p.max_hp * hp_pct / 100.0), 1, p.max_hp)
	if p.max_mana > 0:
		mana = clampi(cur_mana + int(p.max_mana * mana_pct / 100.0), 0, p.max_mana)


func _add_potion(kind: String) -> bool:
	var cap := int(_cfg().get("potion_max", 5)) + (2 if boons.has("deep_pockets") else 0)
	if int(potions.get(kind, 0)) >= cap:
		return false
	potions[kind] = int(potions.get(kind, 0)) + 1
	return true


# --- progression ---

func xp_to_next() -> int:
	return int(_cfg().get("xp_to_next_per_level", 40)) * level


## Add XP; returns levels gained. Level-ups raise max HP/mana (current goes up by the same amount).
func add_xp(amount: int) -> int:
	xp += amount
	xp_total += amount
	var gained := 0
	while level < 10 and xp >= xp_to_next():
		xp -= xp_to_next()
		var before := make_player()
		var before_known := known_actives()
		level += 1
		gained += 1
		var after := make_player()
		if hp >= 0:
			hp += after.max_hp - before.max_hp
		if mana >= 0:
			mana += after.max_mana - before.max_mana
		for a in known_actives():
			if not before_known.has(a):
				messages.append("Learned %s." % a)
		messages.append("Level %d!" % level)
	if level >= 10:
		xp = 0
	return gained


func _roll_item(rarity: String) -> Dictionary:
	return DSLoot.roll_item(data, rng, item_level(), "", rarity, line, int(perks.get("legendary_tier", 99)))


func available_boons() -> Array:
	var out: Array = []
	var ids := data.boons.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = data.boons[id]
		var lines: Array = b.get("lines", [])
		if boons.has(id):
			continue
		if int(b.get("tier", 1)) > int(perks.get("boon_tier", 99)):
			continue
		if lines.is_empty() or lines.has(line):
			out.append(id)
	return out


func _boon_offers(n: int) -> Array:
	var pool := available_boons()
	rng.shuffle(pool)
	var out: Array = []
	for id in pool.slice(0, n):
		out.append({"kind": "boon", "id": id})
	return out


## Loot from a won fight: `balance.run.loot_per_fight` items (elites more, and at least rare).
func _fight_loot(elite: bool) -> Array:
	var c := _cfg()
	var n := int(c.get("loot_per_elite", 2)) if elite else int(c.get("loot_per_fight", 1))
	var min_rar := str(c.get("elite_min_rarity", "rare")) if elite else ""
	var order: Array = data.items.get("rarity_order", [])
	var out: Array = []
	for i in n:
		var rar := ""
		if min_rar != "":
			rar = DSLoot.roll_rarity(data, rng, 0.08 * float(item_level() - 1))
			if order.find(rar) < order.find(min_rar):
				rar = min_rar
		out.append(_roll_item(rar))
	return out


# --- floor end, extraction, death ---

func complete_room() -> void:
	room["done"] = true
	step += 1
	if step >= steps().size():
		if floor_num >= FLOORS:
			end_run("victory")
		else:
			phase = "floor_end"
	else:
		phase = "path"


func can_extract() -> bool:
	return phase == "floor_end" and floor_num >= int(_cfg().get("extract_from_floor", 2))


func descend() -> void:
	if phase != "floor_end":
		return
	floor_num += 1
	_new_floor()


func extract() -> void:
	if can_extract():
		end_run("extract")


func end_run(kind: String) -> void:
	result = kind
	phase = "over"


## What the run banks into the account: death keeps 50% XP and no gold; extract/victory keep all.
func banked() -> Dictionary:
	var c := _cfg()
	if result == "death":
		return {"xp": int(xp_total * int(c.get("death_xp_pct", 50)) / 100.0), "gold": 0}
	return {"xp": int(xp_total * int(c.get("extract_xp_pct", 100)) / 100.0), "gold": gold}


static func bank_into(account: Dictionary, run: DSRunState) -> Dictionary:
	var a := account.duplicate(true)
	var b := run.banked()
	a["xp"] = int(a.get("xp", 0)) + int(b["xp"])
	a["gold"] = int(a.get("gold", 0)) + int(b["gold"])
	a["runs"] = int(a.get("runs", 0)) + 1
	var key: String = {"death": "deaths", "extract": "extracts", "victory": "victories"}.get(run.result, "other")
	a[key] = int(a.get(key, 0)) + 1
	a["best_floor"] = maxi(int(a.get("best_floor", 0)), run.floor_num)
	return a
