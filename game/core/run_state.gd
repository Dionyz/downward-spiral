class_name DSRunState
extends RefCounted
## One run, start to finish: six Rogue-style floors, XP, gold, loot, boons, extraction, death.
## Pure logic and plain data: to_dict()/from_dict() is the save file. The UI calls tick() on a
## timer while exploring and the choice methods when play is paused.
##
## Phases:
##   "explore"   the floor is in play: call tick() each turn
##   "boon"      choose 1 of the offered boons (offer, offer_source), or skip
##   "event"     an event object was touched: event_choose(i), then event_done()
##   "floor_end" standing on the stairs: descend() or extract() (extract from floor 2 on)
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
var potions := {"hp": 3, "mp": 2}
var items := {"weapon": null, "armor": null, "trinket": null}   # equipped, one per slot
var inventory: Array = []     # everything else you carry (max INVENTORY_MAX)
var boons: Array = []
var floor_num: int = 1
var world: DSWorld
var phase: String = "explore"
var offer: Array = []         # boon ids on offer
var offer_source: String = ""
var pending_boons: int = 0    # boon picks earned (level-ups, elites) not yet shown
var event_id: String = ""
var event_outcome: Array = []
var result: String = ""
var stats := {"kills": 0, "fights": 0, "rooms": 0, "gold_earned": 0}
var perks: Dictionary = {}    # account perks this run started with (DSMeta.perks)
var messages: Array = []      # short lines for the UI (level ups, loot); cleared by the UI
var room: Dictionary = {}     # legacy scratch (banking flag)


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
	var ps: Dictionary = r._cfg().get("potions_start", {"hp": 3, "mp": 2})
	r.potions = {"hp": int(ps.get("hp", 3)) + int(r.perks.get("potions", 0)), "mp": int(ps.get("mp", 2)) if r._has_mana() else 0}
	var L: Dictionary = p_data.classes.get(p_line, {})
	r.items["weapon"] = DSFactory.starting_weapon(p_data, str(L.get("starting_weapon", "dagger")), 1)
	r._new_floor()
	return r


func to_dict() -> Dictionary:
	_sync_from_world()
	return {
		"version": 2, "seed": seed_value, "rng": rng.save_state(), "line": line, "level": level, "xp": xp,
		"xp_total": xp_total, "gold": gold, "hp": hp, "mana": mana, "potions": potions.duplicate(),
		"items": items.duplicate(true), "inventory": inventory.duplicate(true), "boons": boons.duplicate(),
		"floor_num": floor_num, "world": world.to_dict() if world != null else {}, "phase": phase,
		"offer": offer.duplicate(), "offer_source": offer_source, "pending_boons": pending_boons,
		"event_id": event_id, "event_outcome": event_outcome.duplicate(), "result": result,
		"stats": stats.duplicate(), "perks": perks.duplicate(true), "room": room.duplicate(true),
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
	r.inventory = _normalize(d.get("inventory", []))
	r.boons = _normalize(d.get("boons", []))
	r.floor_num = int(d.get("floor_num", 1))
	r.phase = str(d.get("phase", "explore"))
	r.offer = _normalize(d.get("offer", []))
	r.offer_source = str(d.get("offer_source", ""))
	r.pending_boons = int(d.get("pending_boons", 0))
	r.event_id = str(d.get("event_id", ""))
	r.event_outcome = _normalize(d.get("event_outcome", []))
	r.result = str(d.get("result", ""))
	r.stats = _normalize(d.get("stats", r.stats))
	r.perks = _normalize(d.get("perks", {}))
	r.room = _normalize(d.get("room", {}))
	if r.perks.is_empty():
		r.perks = DSMeta.all_unlocked(p_data)
	var wd: Dictionary = _normalize(d.get("world", {}))
	if not wd.is_empty():
		r.world = DSWorld.from_dict(r, wd)
	return r


# ---------------------------------------------------------------------------
# Floors and turns
# ---------------------------------------------------------------------------

func _new_floor() -> void:
	var lvl := DSLevelGen.generate(data, rng, floor_num)
	world = DSWorld.create(self, lvl, rng.fork())
	phase = "explore"


## Advance one turn of the floor. Returns the turn's events (for the UI to animate).
func tick() -> Array:
	if phase != "explore" or world == null:
		return []
	var evs := world.step()
	world.wake_damaged()
	_sync_from_world()
	if phase == "over":
		return evs
	var p: Dictionary = world.pending
	if p.get("kind", "") == "death":
		end_run("death")
	elif p.get("kind", "") == "stairs":
		world.pending = {}
		if floor_num >= FLOORS:
			end_run("victory")
		else:
			phase = "floor_end"
	elif p.get("kind", "") == "event":
		world.pending = {}
		var ids := data.events.keys()
		ids.sort()
		event_id = str(rng.pick(ids))
		event_outcome = []
		phase = "event"
	elif p.get("kind", "") == "boon":
		world.pending = {}
		_open_offer("shrine")
	elif pending_boons > 0:
		pending_boons -= 1
		_open_offer("level")
	return evs


func _open_offer(source: String) -> void:
	offer = _boon_offers(3).map(func(o): return o["id"])
	offer_source = source
	if offer.is_empty():
		phase = "explore"
	else:
		phase = "boon"


## Live HP/mana live on the world's player while a floor is in play.
func _sync_from_world() -> void:
	if world != null and world.player != null:
		hp = world.player.hp
		mana = world.player.mana


func _sync_to_world() -> void:
	if world != null:
		world.refresh_player()


func take_boon(i: int) -> void:
	if phase != "boon" or i < 0 or i >= offer.size():
		return
	add_boon(str(offer[i]))
	_close_offer()


func skip_boon() -> void:
	if phase == "boon":
		_close_offer()


func _close_offer() -> void:
	offer = []
	offer_source = ""
	phase = "explore"
	_sync_to_world()


## Kill reward: XP, gold, maybe item and potion drops (returned as items to place on the floor).
func on_kill(c: Combatant, elite: bool, boss: bool) -> Array:
	var kind := "boss" if boss else ("elite" if elite else "normal")
	var cfg := _cfg()
	stats["kills"] = int(stats["kills"]) + 1
	var gx := c.level * int(cfg.get("xp_per_monster_level", 10)) * int(cfg.get("xp_mult", {}).get(kind, 1))
	var gg := (c.level * int(cfg.get("gold_per_monster_level", 3)) + rng.number_range(0, 3)) * int(cfg.get("gold_mult", {}).get(kind, 1))
	if boons.has("quick_study"):
		gx += DSStats.idiv(gx, 4)
	if boons.has("scavenger"):
		gg += DSStats.idiv(gg, 2)
	gold += gg
	stats["gold_earned"] = int(stats["gold_earned"]) + gg
	_sync_from_world()
	var lv := add_xp(gx)
	pending_boons += lv
	if elite:
		pending_boons += 1
	if lv > 0:
		_sync_to_world()
	if boons.has("catch_breath") and world != null:
		world.player.hp = mini(world.player.max_hp, world.player.hp + world.player.max_hp / 10)
	var drops: Array = []
	if elite or rng.number_percent() <= int(cfg.get("loot_drop_pct", 25)):
		drops.append_array(_fight_loot(elite))
	var pchance := int(cfg.get("potion_drop_pct_elite", 50)) if elite else int(cfg.get("potion_drop_pct", 8))
	if rng.number_percent() <= pchance:
		var kp := "mp" if _has_mana() and rng.number_percent() <= 35 else "hp"
		if _add_potion(kp):
			messages.append("Found a %s potion." % ("healing" if kp == "hp" else "mana"))
	if boss:
		world.pending = {"kind": "stairs"}
		world.heading_down = true
	return drops


## A chest: `balance.run.treasure_items` items, the first at least uncommon.
func open_chest() -> Array:
	var found: Array = []
	for i in int(_cfg().get("treasure_items", 3)):
		found.append(_roll_item("uncommon" if i == 0 else ""))
	var got := gain_items(found)
	_sync_to_world()
	return got


# --- events ---

## Pick option `i` of the current event. Returns the outcome lines.
func event_choose(i: int) -> Array:
	if phase != "event" or not event_outcome.is_empty():
		return event_outcome
	var opts: Array = event_def().get("options", [])
	if i < 0 or i >= opts.size():
		return []
	_sync_from_world()
	var lines: Array = []
	var found_item = null
	for op in opts[i].get("ops", []):
		found_item = _apply_op(op, lines, found_item)
	if found_item != null:
		var got := gain_items([found_item])
		lines.append("Found %s%s." % [found_item.get("name", "?"), " (equipped)" if got[0]["equipped"] else " (in your bag)"])
	event_outcome = lines
	_sync_to_world()
	return lines


func event_done() -> void:
	if phase == "event":
		event_id = ""
		event_outcome = []
		phase = "explore"


func descend() -> void:
	if phase != "floor_end":
		return
	_sync_from_world()
	floor_num += 1
	_new_floor()


func extract() -> void:
	if can_extract():
		end_run("extract")



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


## Put `item` in its slot. Whatever was there goes back into the inventory.
func equip(item: Dictionary) -> void:
	_sync_from_world()
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
	_sync_to_world()


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


func event_def() -> Dictionary:
	return data.events.get(event_id, {})


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


func can_extract() -> bool:
	return phase == "floor_end" and floor_num >= int(_cfg().get("extract_from_floor", 2))


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
