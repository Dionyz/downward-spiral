class_name DSRunState
extends RefCounted
## One run, start to finish: floors, rooms, rewards, boons, items, XP, gold, extraction, death.
## Pure logic and plain data: to_dict()/from_dict() is the save file. The UI only calls methods here.
##
## Phases:
##   "path"      between rooms; at_fork() says whether the player must pick a room
##   "room"      inside a room (fight not finished / choice not made yet)
##   "reward"    after a won fight (or an event that found an item): pick 1 of the offers or skip
##   "floor_end" floor cleared; descend() or extract() (extract from floor 2 on)
##   "over"      run ended; result is "death", "extract" or "victory"

const FLOORS := 6
const SLOTS := ["weapon", "armor", "trinket"]

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
var items := {"weapon": null, "armor": null, "trinket": null}
var boons: Array = []
var rules: Array = []
var actives: Array = []
var floor_num: int = 1
var floor_data: Dictionary = {}
var step: int = 0
var room: Dictionary = {}
var phase: String = "path"
var result: String = ""
var stats := {"kills": 0, "fights": 0, "rooms": 0, "gold_earned": 0}
var messages: Array = []      # short lines for the UI (level ups, loot); cleared by the UI


# ---------------------------------------------------------------------------
# Setup and save
# ---------------------------------------------------------------------------

static func new_run(p_data: DSData, p_line: String, p_seed: int) -> DSRunState:
	var r := DSRunState.new()
	r.data = p_data
	r.seed_value = p_seed
	r.rng = DSRng.new(p_seed)
	r.line = p_line
	var ps: Dictionary = r._cfg().get("potions_start", {"hp": 2, "mp": 2})
	r.potions = {"hp": int(ps.get("hp", 2)), "mp": int(ps.get("mp", 2)) if r._has_mana() else 0}
	var L: Dictionary = p_data.classes.get(p_line, {})
	r.items["weapon"] = DSFactory.starting_weapon(p_data, str(L.get("starting_weapon", "dagger")), 1)
	r.actives = DSFactory.default_actives(p_data, p_line, 1, 1)
	r.rules = DSFactory.default_rules(p_data, p_line, 1, 1, DSFactory.rule_slots(p_data, 1))
	r._new_floor()
	return r


func to_dict() -> Dictionary:
	return {
		"version": 1, "seed": seed_value, "rng": rng.save_state(), "line": line, "level": level, "xp": xp,
		"xp_total": xp_total, "gold": gold, "hp": hp, "mana": mana, "potions": potions.duplicate(),
		"items": items.duplicate(true), "boons": boons.duplicate(), "rules": rules.duplicate(true),
		"actives": actives.duplicate(), "floor_num": floor_num, "floor_data": floor_data.duplicate(true),
		"step": step, "room": room.duplicate(true), "phase": phase, "result": result, "stats": stats.duplicate(),
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
	r.rules = _normalize(d.get("rules", []))
	r.actives = _normalize(d.get("actives", []))
	r.floor_num = int(d.get("floor_num", 1))
	r.floor_data = _normalize(d.get("floor_data", {}))
	r.step = int(d.get("step", 0))
	r.room = _normalize(d.get("room", {}))
	r.phase = str(d.get("phase", "path"))
	r.result = str(d.get("result", ""))
	r.stats = _normalize(d.get("stats", r.stats))
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

## A fresh Combatant reflecting the run: level, gear, boons, rules, current HP/mana.
func make_player() -> Combatant:
	var opts := {"rules": rules, "actives": actives, "weapon": items["weapon"]}
	if items["armor"] != null:
		opts["armor"] = items["armor"]
	if items["trinket"] != null:
		opts["trinket"] = items["trinket"]
	var p := DSFactory.make_player(data, line, 1, level, opts)
	DSFactory.apply_boons(data, p, boons)
	if hp >= 0:
		p.hp = clampi(hp, 1, p.max_hp)
	if mana >= 0:
		p.mana = clampi(mana, 0, p.max_mana)
	return p


func rule_slots() -> int:
	return DSFactory.rule_slots(data, level)


## Every active the character knows at its level (for swapping at rest rooms).
func known_actives() -> Array:
	return data.kit_abilities(line, 1, level, "active")


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
			room["offers"] = []
			for i in 3:
				room["offers"].append({"kind": "item", "item": _roll_item("")})
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
	if kind == "boss":
		reward["offers"] = []
	else:
		reward["offers"] = _reward_offers(kind == "elite")
	room["reward"] = reward
	phase = "reward"
	return reward


## Take reward/treasure/shrine offer `i`.
func take_offer(i: int) -> void:
	var offers: Array = room.get("reward", {}).get("offers", []) if phase == "reward" else room.get("offers", [])
	if i < 0 or i >= offers.size():
		return
	var o: Dictionary = offers[i]
	if o.get("kind") == "item":
		equip(o["item"])
	elif o.get("kind") == "boon":
		add_boon(str(o["id"]))
	complete_room()


## Skip the reward / leave the treasure or shrine.
func skip() -> void:
	if phase in ["reward", "room"]:
		complete_room()


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
	messages.append("Equipped %s%s." % [item.get("name", "?"), "" if old == null else " (replacing %s)" % old.get("name", "?")])


func add_boon(id: String) -> void:
	if not boons.has(id) and data.boons.has(id):
		boons.append(id)
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


## Swap equipped abilities (max 4, from known_actives) and set rules, at no HP cost.
func rest_train(new_actives: Array, new_rules: Array) -> void:
	if room.get("type") != "rest" or phase != "room":
		return
	var known := known_actives()
	var cap := int(data.balance.get("max_actives", 4))
	var picked: Array = []
	for a in new_actives:
		if known.has(a) and not picked.has(a) and picked.size() < cap:
			picked.append(a)
	if not picked.is_empty():
		actives = picked
	set_rules(new_rules)
	messages.append("You drill your technique.")
	complete_room()


## Rules can be edited between any rooms (DECISIONS.md D-037).
func set_rules(new_rules: Array) -> void:
	rules = new_rules.slice(0, rule_slots()).duplicate(true)


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
	room["outcome"] = lines
	if found_item != null:
		room["reward"] = {"gold": 0, "xp": 0, "levels": 0, "offers": [{"kind": "item", "item": found_item}]}
		phase = "reward"
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
	var cap := int(_cfg().get("potion_max", 5))
	if int(potions.get(kind, 0)) >= cap:
		return false
	potions[kind] = int(potions.get(kind, 0)) + 1
	return true


# --- progression ---

func xp_to_next() -> int:
	return int(_cfg().get("xp_to_next_per_level", 40)) * level


## Add XP; returns levels gained. Level-ups raise max HP/mana (current goes up by the same amount)
## and auto-equip newly learned actives into free slots.
func add_xp(amount: int) -> int:
	xp += amount
	xp_total += amount
	var gained := 0
	while level < 10 and xp >= xp_to_next():
		xp -= xp_to_next()
		var before := make_player()
		level += 1
		gained += 1
		var after := make_player()
		if hp >= 0:
			hp += after.max_hp - before.max_hp
		if mana >= 0:
			mana += after.max_mana - before.max_mana
		var cap := int(data.balance.get("max_actives", 4))
		for a in DSFactory.default_actives(data, line, 1, level):
			if not actives.has(a) and actives.size() < cap:
				actives.append(a)
				messages.append("Learned %s." % a)
		messages.append("Level %d!" % level)
	if level >= 10:
		xp = 0
	return gained


func _roll_item(rarity: String) -> Dictionary:
	return DSLoot.roll_item(data, rng, item_level(), "", rarity, line)


func available_boons() -> Array:
	var out: Array = []
	var ids := data.boons.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = data.boons[id]
		var lines: Array = b.get("lines", [])
		if boons.has(id):
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


func _reward_offers(elite: bool) -> Array:
	var out: Array = []
	var boon_pool := available_boons()
	rng.shuffle(boon_pool)
	var min_rar := str(_cfg().get("elite_min_rarity", "rare")) if elite else ""
	var order: Array = data.items.get("rarity_order", [])
	for i in 3:
		if not boon_pool.is_empty() and rng.number_percent() <= int(_cfg().get("reward_boon_chance", 40)):
			out.append({"kind": "boon", "id": boon_pool.pop_back()})
		else:
			var rar := ""
			if min_rar != "":
				rar = DSLoot.roll_rarity(data, rng, 0.08 * float(item_level() - 1))
				if order.find(rar) < order.find(min_rar):
					rar = min_rar
			out.append({"kind": "item", "item": _roll_item(rar)})
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
