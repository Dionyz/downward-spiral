class_name DSWorld
extends RefCounted
## One floor in play, Rogue style: a tile grid, the player, monsters, items and objects, all
## advancing in turns. Pure logic and deterministic (one seeded RNG). The UI calls step() on a
## timer and draws the state; DSRunState owns the world and reacts to what it reports.
##
## Turn order: every actor gains energy equal to its speed each turn (100 = normal) and acts
## each time its energy reaches 100. An action is: move one tile, a melee attack (a full MUD
## attack round from CombatSim), an ability, or waiting. Fights use the same CombatSim rules
## (damage, defenses, abilities, statuses), with range and line of sight decided here.

const DIRS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var data: DSData
var run                          # DSRunState (untyped to avoid a cyclic class reference)
var rng: DSRng
var sim: CombatSim
var level: Dictionary = {}
var tiles: Array = []            # Array[String] rows
var w := 0
var h := 0
var seen: Dictionary = {}        # "x,y" -> true (explored)
var visible: Dictionary = {}     # "x,y" -> true (in view this turn)
var player: Combatant
var ppos := Vector2i.ZERO
var penergy := 0
var monsters: Array = []         # [{c: Combatant, pos, state, energy, speed, elite, boss, id}]
var items: Array = []            # [{pos, item}] lying on the floor
var objects: Array = []          # [{type, pos, used}]
var stairs := Vector2i.ZERO
var turn := 0
var in_combat := false
var heading_down := false        # explored everything: walking to the stairs
var auto_potions := false        # tests/balance/autoplay drink potions on their own
var events: Array = []           # this turn's events (sim + world)
var pending: Dictionary = {}     # something the run must handle before play continues
var regen_counter := 0


# ---------------------------------------------------------------------------
# Setup / save
# ---------------------------------------------------------------------------

static func create(p_run, p_level: Dictionary, p_rng: DSRng) -> DSWorld:
	var wd := DSWorld.new()
	wd.run = p_run
	wd.data = p_run.data
	wd.rng = p_rng
	wd.level = p_level
	wd.tiles = p_level["tiles"]
	wd.w = int(p_level["w"])
	wd.h = int(p_level["h"])
	var s: Array = p_level["start"]
	wd.ppos = Vector2i(int(s[0]), int(s[1]))
	var st: Array = p_level["stairs"]
	wd.stairs = Vector2i(int(st[0]), int(st[1]))
	for o in p_level["objects"]:
		wd.objects.append({"type": o["type"], "pos": Vector2i(int(o["x"]), int(o["y"])), "used": false})
	var lvl: int = p_run.monster_level()
	for i in p_level["spawns"].size():
		var sp: Dictionary = p_level["spawns"][i]
		var ml := lvl
		if sp.get("elite", false):
			ml += int(p_run._cfg().get("elite_level_bonus", 0))
		if sp.get("boss", false):
			ml = int(p_run._cfg().get("boss_level", 10))
		wd._add_monster(str(sp["id"]), ml, Vector2i(int(sp["x"]), int(sp["y"])), i,
			"asleep" if sp.get("boss", false) else ("wander" if p_rng.number_percent() <= 25 else "asleep"),
			sp.get("elite", false), sp.get("boss", false), -1)
	wd._attach_player()
	wd._update_fov()
	return wd


func _add_monster(id: String, ml: int, pos: Vector2i, idx: int, state: String, elite: bool, boss: bool, hp: int) -> void:
	var c := DSFactory.make_monster(data, id, ml, idx)
	if hp >= 0:
		c.hp = clampi(hp, 1, c.max_hp)
	var m: Dictionary = data.monsters.get(id, {})
	monsters.append({"c": c, "pos": pos, "state": state, "energy": 0, "speed": int(m.get("move_speed", 100)),
		"elite": elite, "boss": boss, "id": id, "level": ml, "wake": int(m.get("wake_radius", 6))})


func _attach_player() -> void:
	player = run.make_player()
	sim = CombatSim.new(rng, data)
	sim.log_all = false
	sim.player = player
	sim.enemies = monsters.map(func(m): return m["c"])
	sim.range_check = _range_ok
	sim.area_targets = _area
	# Display names stay unique on the map.
	var counts := {}
	for m in monsters:
		counts[m["c"].name] = int(counts.get(m["c"].name, 0)) + 1
	var seen_n := {}
	for m in monsters:
		var nm: String = m["c"].name
		if int(counts[nm]) > 1:
			seen_n[nm] = int(seen_n.get(nm, 0)) + 1
			m["c"].name = "%s #%d" % [nm, seen_n[nm]]


## Rebuild the player from the run (gear, boons, level, run.hp/mana) keeping in-fight state.
func refresh_player() -> void:
	var cds := player.cooldowns.duplicate()
	var sts := player.statuses.duplicate(true)
	var stance := player.stance
	var fl := player.flags.duplicate()
	player = run.make_player()
	player.cooldowns = cds
	for k in sts.keys():
		if not player.statuses.has(k):
			player.statuses[k] = sts[k]
	player.stance = stance
	for k in ["second_wind_used", "last_stand_used", "first_blood_ready", "momentum", "counter_ready", "parry_stacks"]:
		if fl.has(k):
			player.flags[k] = fl[k]
	sim.player = player


func to_dict() -> Dictionary:
	var ms: Array = []
	for m in monsters:
		ms.append({"id": m["id"], "level": m["level"], "x": m["pos"].x, "y": m["pos"].y, "state": m["state"],
			"hp": m["c"].hp, "elite": m["elite"], "boss": m["boss"]})
	var its: Array = []
	for it in items:
		its.append({"x": it["pos"].x, "y": it["pos"].y, "item": it["item"]})
	var obs: Array = []
	for o in objects:
		obs.append({"type": o["type"], "x": o["pos"].x, "y": o["pos"].y, "used": o["used"]})
	return {"level": level, "seen": seen.keys(), "px": ppos.x, "py": ppos.y, "monsters": ms, "items": its,
		"objects": obs, "turn": turn, "heading_down": heading_down, "rng": rng.save_state()}


static func from_dict(p_run, d: Dictionary) -> DSWorld:
	var wd := DSWorld.new()
	wd.run = p_run
	wd.data = p_run.data
	wd.rng = DSRng.new(1)
	wd.rng.load_state(int(d.get("rng", 1)))
	wd.level = d["level"]
	wd.tiles = wd.level["tiles"]
	wd.w = int(wd.level["w"])
	wd.h = int(wd.level["h"])
	var st: Array = wd.level["stairs"]
	wd.stairs = Vector2i(int(st[0]), int(st[1]))
	wd.ppos = Vector2i(int(d["px"]), int(d["py"]))
	for k in d.get("seen", []):
		wd.seen[str(k)] = true
	for o in d.get("objects", []):
		wd.objects.append({"type": o["type"], "pos": Vector2i(int(o["x"]), int(o["y"])), "used": bool(o["used"])})
	for it in d.get("items", []):
		wd.items.append({"pos": Vector2i(int(it["x"]), int(it["y"])), "item": it["item"]})
	var i := 0
	for m in d.get("monsters", []):
		wd._add_monster(str(m["id"]), int(m["level"]), Vector2i(int(m["x"]), int(m["y"])), i, str(m["state"]),
			bool(m["elite"]), bool(m["boss"]), int(m["hp"]))
		i += 1
	wd.turn = int(d.get("turn", 0))
	wd.heading_down = bool(d.get("heading_down", false))
	wd._attach_player()
	wd._update_fov()
	return wd


# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

static func pk(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


func tile(p: Vector2i) -> String:
	if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
		return " "
	return str(tiles[p.y]).substr(p.x, 1)


func walkable(p: Vector2i) -> bool:
	return tile(p) != " "


func monster_at(p: Vector2i):
	for m in monsters:
		if m["c"].is_alive() and m["pos"] == p:
			return m
	return null


func occupied(p: Vector2i) -> bool:
	return p == ppos or monster_at(p) != null


## Diagonal moves can't cut a wall corner.
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not walkable(b):
		return false
	var d := b - a
	if d.x != 0 and d.y != 0:
		return walkable(Vector2i(a.x + d.x, a.y)) and walkable(Vector2i(a.x, a.y + d.y))
	return true


static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Bresenham line of sight through walkable tiles.
func los(a: Vector2i, b: Vector2i) -> bool:
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	while true:
		if Vector2i(x0, y0) != a and Vector2i(x0, y0) != b and not walkable(Vector2i(x0, y0)):
			return false
		if x0 == b.x and y0 == b.y:
			return true
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return true


## Breadth-first distances over walkable tiles (8-way, no corner cutting). Monsters block
## unless `through_monsters`.
func distance_map(from: Vector2i, through_monsters: bool = true, limit: int = 999) -> Dictionary:
	var dist := {pk(from): 0}
	var q: Array = [from]
	var head := 0
	while head < q.size():
		var p: Vector2i = q[head]
		head += 1
		var dp := int(dist[pk(p)])
		if dp >= limit:
			continue
		for d in DIRS8:
			var n: Vector2i = p + d
			if dist.has(pk(n)) or not can_step(p, n):
				continue
			if not through_monsters and monster_at(n) != null:
				continue
			dist[pk(n)] = dp + 1
			q.append(n)
	return dist


## Next step from `from` that goes downhill on `dist` (a distance map toward a goal).
func step_down(from: Vector2i, dist: Dictionary, avoid_occupied: bool = true):
	var best = null
	var best_d := int(dist.get(pk(from), 1 << 30))
	for d in DIRS8:
		var n: Vector2i = from + d
		if not dist.has(pk(n)) or not can_step(from, n):
			continue
		if avoid_occupied and occupied(n):
			continue
		var dn := int(dist[pk(n)])
		if dn < best_d:
			best_d = dn
			best = n
	return best


func _update_fov() -> void:
	visible.clear()
	var r := int(data.balance.get("level", {}).get("sight", 7))
	# Pass 1: walkable tiles in line of sight. Pass 2: walls touching them (so rooms read properly).
	var lit: Array = []
	for y in range(maxi(0, ppos.y - r), mini(h, ppos.y + r + 1)):
		for x in range(maxi(0, ppos.x - r), mini(w, ppos.x + r + 1)):
			var p := Vector2i(x, y)
			if walkable(p) and los(ppos, p):
				visible[pk(p)] = true
				seen[pk(p)] = true
				lit.append(p)
	for p in lit:
		for d in DIRS8:
			var n: Vector2i = p + d
			if not walkable(n) and n.x >= 0 and n.y >= 0 and n.x < w and n.y < h:
				visible[pk(n)] = true
				seen[pk(n)] = true


func is_visible(p: Vector2i) -> bool:
	return visible.has(pk(p))


# ---------------------------------------------------------------------------
# Ranges for abilities (hooks for CombatSim)
# ---------------------------------------------------------------------------

func pos_of(c: Combatant) -> Vector2i:
	if c == player:
		return ppos
	for m in monsters:
		if m["c"] == c:
			return m["pos"]
	return Vector2i(-99, -99)


## Reach of an ability in tiles: 0 = self, 1 = adjacent, n = ranged (needs line of sight).
func reach(c: Combatant, aname: String) -> int:
	var ranges: Dictionary = data.balance.get("ability_range", {})
	if ranges.has(aname):
		return int(ranges[aname])
	var a: Dictionary = c.monster_abilities.get(aname, data.ability(aname))
	if a.has("range"):
		return int(a["range"])
	if a.get("target", "enemy") == "self":
		return 0
	return 1


func _range_ok(c: Combatant, ref: String, target) -> bool:
	var aname: String = CombatSim.split_ref(ref)[0]
	var r := reach(c, aname)
	if r == 0 or target == null or target == c:
		return true
	var a: Dictionary = c.monster_abilities.get(aname, data.ability(aname))
	var from := pos_of(c)
	if a.get("target", "") == "all_enemies":
		return not _area(c, aname).is_empty()
	var to := pos_of(target)
	var d := cheb(from, to)
	if aname == "charge":
		return d >= 2 and d <= r and los(from, to) and _charge_landing(from, to) != null
	return d <= r and (d <= 1 or los(from, to))


## Who an area ability hits: adjacent enemies, or (chain lightning) enemies in view near the caster.
func _area(c: Combatant, aname: String) -> Array:
	var from := pos_of(c)
	var foes: Array = []
	if c == player:
		for m in monsters:
			if m["c"].is_alive():
				foes.append(m["c"])
	else:
		foes = [player] if player.is_alive() else []
	if aname == "chain lightning":
		return foes.filter(func(f): return cheb(pos_of(f), from) <= reach(c, aname) and los(from, pos_of(f)))
	return foes.filter(func(f): return cheb(pos_of(f), from) <= 1)


func _charge_landing(from: Vector2i, to: Vector2i):
	# The free tile next to the target on the line from the charger.
	var dir := Vector2i(signi(from.x - to.x), signi(from.y - to.y))
	var land := to + dir
	if land == from or (walkable(land) and not occupied(land)):
		return land
	return null


# ---------------------------------------------------------------------------
# Turns
# ---------------------------------------------------------------------------

func awake_hostiles(within: int = 99) -> Array:
	return monsters.filter(func(m): return m["c"].is_alive() and m["state"] == "hunt" and cheb(m["pos"], ppos) <= within)


## Advance one turn. Returns the turn's events. Does nothing while something is pending.
func step() -> Array:
	events = []
	sim.events = []
	if not pending.is_empty() or not player.is_alive():
		return events
	turn += 1
	sim.round_num = turn
	_emit({"t": "turn", "n": turn})
	var was := in_combat
	in_combat = not awake_hostiles(int(data.balance.get("level", {}).get("combat_radius", 9))).is_empty()
	if in_combat and not was:
		sim.start_encounter()
		_emit({"t": "encounter"})
	# Player.
	penergy += _speed(player, 100)
	while penergy >= 100 and pending.is_empty() and player.is_alive():
		penergy -= 100
		sim.tick(player)
		_player_act()
		_collect()
	# Monsters.
	var dist := distance_map(ppos, true, 40)
	for m in monsters:
		if not m["c"].is_alive() or not player.is_alive() or not pending.is_empty():
			continue
		m["energy"] = int(m["energy"]) + _speed(m["c"], int(m["speed"]))
		while int(m["energy"]) >= 100 and m["c"].is_alive() and player.is_alive():
			m["energy"] = int(m["energy"]) - 100
			sim.tick(m["c"])
			if m["c"].is_alive():
				_monster_act(m, dist)
			_collect()
	# Out-of-combat regeneration.
	if not in_combat and player.is_alive():
		regen_counter += 1
		var every := int(data.balance.get("level", {}).get("regen_every", 3))
		if regen_counter >= every:
			regen_counter = 0
			player.hp = mini(player.max_hp, player.hp + maxi(1, player.max_hp / 100))
	_update_fov()
	if not player.is_alive():
		pending = {"kind": "death"}
	return events


func _speed(c: Combatant, base: int) -> int:
	var s := base
	if c.has_status("haste"):
		s += 50
	if c.has_status("slowed"):
		s -= 40
	return maxi(20, s)


## Pull CombatSim's events into ours and react to deaths.
func _collect() -> void:
	for ev in sim.events:
		events.append(ev)
		if ev.get("t") == "death":
			for m in monsters:
				if m["c"].name == ev.get("src") and not m.get("dead", false) and not m["c"].is_alive():
					m["dead"] = true
					_on_kill(m)
	sim.events = []


func _emit(ev: Dictionary) -> void:
	ev["r"] = turn
	events.append(ev)


func _on_kill(m: Dictionary) -> void:
	var drops: Array = run.on_kill(m["c"], m["elite"], m["boss"])
	for it in drops:
		var p := _free_drop_spot(m["pos"])
		items.append({"pos": p, "item": it})
		_emit({"t": "drop", "x": p.x, "y": p.y, "name": it.get("name", "?"), "rarity": it.get("rarity", "common")})


func _free_drop_spot(p: Vector2i) -> Vector2i:
	if not _item_at(p):
		return p
	for d in DIRS8:
		var n: Vector2i = p + d
		if walkable(n) and not _item_at(n):
			return n
	return p


func _item_at(p: Vector2i) -> bool:
	for it in items:
		if it["pos"] == p:
			return true
	return false


# ---------------------------------------------------------------------------
# Player: fight what's awake, else explore
# ---------------------------------------------------------------------------

func _player_act() -> void:
	var foes := awake_hostiles(int(data.balance.get("level", {}).get("combat_radius", 9)))
	foes = foes.filter(func(m): return is_visible(m["pos"]) or cheb(m["pos"], ppos) <= 1)
	if not foes.is_empty():
		_player_fight(foes)
		return
	_explore()


func _player_fight(foes: Array) -> void:
	if auto_potions and player.hp_pct() < 30.0 and int(run.potions.get("hp", 0)) > 0:
		drink("hp")
		return
	if auto_potions and player.max_mana > 0 and player.mana_pct() < 15.0 and int(run.potions.get("mp", 0)) > 0:
		drink("mp")
		return
	foes.sort_custom(func(a, b): return cheb(a["pos"], ppos) < cheb(b["pos"], ppos))
	var targets: Array = foes.map(func(m): return m["c"])
	# Abilities first (range-checked through the hooks).
	var choice := sim.rules_engine.choose(sim, player, player.rules, targets)
	if not choice.is_empty():
		var aname: String = CombatSim.split_ref(choice["ability"])[0]
		if aname == "charge":
			var land = _charge_landing(ppos, pos_of(choice["target"]))
			if land != null:
				_emit({"t": "move", "who": "player", "from": [ppos.x, ppos.y], "to": [land.x, land.y], "charge": true})
				ppos = land
		sim.use_ability(player, choice["ability"], choice["target"])
		return
	# Melee the weakest adjacent enemy.
	var adj := foes.filter(func(m): return cheb(m["pos"], ppos) <= 1)
	if not adj.is_empty():
		adj.sort_custom(func(a, b): return a["c"].hp < b["c"].hp)
		sim.melee(player, adj[0]["c"])
		return
	# Hold a corridor when a pack is coming; otherwise close in.
	if foes.size() >= 3 and tile(ppos) == "#":
		_emit({"t": "wait", "who": "player"})
		return
	var dist := distance_map(foes[0]["pos"], true, 30)
	var nxt = step_down(ppos, dist)
	if nxt != null:
		_move_player(nxt)


## Explore: items in view, unused objects, then unexplored ground, then the stairs.
func _explore() -> void:
	var dist := distance_map(ppos, false, 80)
	var goal = _explore_goal(dist)
	if goal == null:
		return
	if goal == ppos:
		_interact()
		return
	var back := distance_map(goal, false, 80)
	var nxt = step_down(ppos, back)
	if nxt == null:
		back = distance_map(goal, true, 80)
		nxt = step_down(ppos, back, false)
		if nxt == null or monster_at(nxt) != null:
			_emit({"t": "wait", "who": "player"})
			return
	_move_player(nxt)


func _explore_goal(dist: Dictionary):
	var best = null
	var best_d := 1 << 30
	var hp_low := player.hp_pct() < 75.0
	for it in items:
		var d := int(dist.get(pk(it["pos"]), -1))
		if d >= 0 and seen.has(pk(it["pos"])) and d < best_d:
			best_d = d
			best = it["pos"]
	for o in objects:
		if o["used"] or not seen.has(pk(o["pos"])):
			continue
		if o["type"] == "campfire" and not hp_low:
			continue
		var d := int(dist.get(pk(o["pos"]), -1))
		if d >= 0 and d < best_d:
			best_d = d
			best = o["pos"]
	if best != null:
		return best
	# Frontier: a reachable tile next to unexplored ground.
	for k in dist.keys():
		var parts: PackedStringArray = str(k).split(",")
		var p := Vector2i(int(parts[0]), int(parts[1]))
		if _frontier(p):
			var d := int(dist[k])
			if d < best_d:
				best_d = d
				best = p
	if best != null:
		return best
	# Everything explored: rest at an unused campfire if hurt, then go down.
	for o in objects:
		if not o["used"] and o["type"] == "campfire" and player.hp_pct() < 100.0 and dist.has(pk(o["pos"])):
			return o["pos"]
	heading_down = true
	return stairs


func _frontier(p: Vector2i) -> bool:
	for d in DIRS8:
		var n: Vector2i = p + d
		if walkable(n) and not seen.has(pk(n)):
			return true
	return false


func _move_player(to: Vector2i) -> void:
	_emit({"t": "move", "who": "player", "from": [ppos.x, ppos.y], "to": [to.x, to.y]})
	ppos = to
	_update_fov()
	_interact()


## Things that happen when the player stands on a tile.
func _interact() -> void:
	for i in range(items.size() - 1, -1, -1):
		if items[i]["pos"] == ppos:
			var it: Dictionary = items[i]["item"]
			items.remove_at(i)
			var got: Array = run.gain_items([it])
			_emit({"t": "pickup", "name": it.get("name", "?"), "rarity": it.get("rarity", "common"),
				"equipped": got[0]["equipped"]})
	for o in objects:
		if o["used"] or o["pos"] != ppos:
			continue
		match o["type"]:
			"chest":
				o["used"] = true
				var got: Array = run.open_chest()
				_emit({"t": "chest", "count": got.size()})
				for g in got:
					_emit({"t": "pickup", "name": g["item"].get("name", "?"), "rarity": g["item"].get("rarity", "common"),
						"equipped": g["equipped"]})
			"campfire":
				o["used"] = true
				var before := player.hp
				player.hp = mini(player.max_hp, player.hp + int(player.max_hp * float(run._cfg().get("rest_heal_pct", 40)) / 100.0))
				if player.max_mana > 0:
					player.mana = mini(player.max_mana, player.mana + int(player.max_mana * 0.4))
				_emit({"t": "heal", "src": player.name, "dst": player.name, "amount": player.hp - before, "source": "campfire"})
			"shrine":
				o["used"] = true
				pending = {"kind": "boon", "source": "shrine"}
			"event":
				o["used"] = true
				pending = {"kind": "event"}
	if ppos == stairs and heading_down:
		pending = {"kind": "stairs"}


## Player-input potion (or autopilot). Uses the player's next action if called mid-turn.
func drink(kind: String) -> bool:
	if int(run.potions.get(kind, 0)) <= 0 or not player.is_alive():
		return false
	run.potions[kind] = int(run.potions[kind]) - 1
	var pct := float(data.balance.get("potion_pct", 50)) / 100.0
	if player.flags.get("boon_potion", false):
		pct *= 1.5
	if kind == "hp":
		var amt := int(player.max_hp * pct)
		player.hp = mini(player.max_hp, player.hp + amt)
		_emit({"t": "heal", "src": player.name, "dst": player.name, "amount": amt, "source": "potion"})
	else:
		var amt2 := int(player.max_mana * pct)
		player.mana = mini(player.max_mana, player.mana + amt2)
		_emit({"t": "mana", "src": player.name, "amount": amt2, "source": "potion"})
	return true


# ---------------------------------------------------------------------------
# Monsters
# ---------------------------------------------------------------------------

func _monster_act(m: Dictionary, dist: Dictionary) -> void:
	var c: Combatant = m["c"]
	var d := cheb(m["pos"], ppos)
	match m["state"]:
		"asleep":
			if d <= int(m["wake"]) and los(m["pos"], ppos) and rng.number_percent() <= 60:
				_wake(m)
			return
		"wander":
			if d <= int(m["wake"]) + 2 and los(m["pos"], ppos):
				_wake(m)
				return
			var dirs: Array = DIRS8.duplicate()
			var dd: Vector2i = rng.pick(dirs)
			var n: Vector2i = m["pos"] + dd
			if rng.number_percent() <= 50 and can_step(m["pos"], n) and not occupied(n):
				_move_monster(m, n)
			return
	# Hunting.
	if not c.can_act() or not c.is_awake():
		return
	if c.has_status("blind") and rng.number_percent() <= 50:
		var n2: Vector2i = m["pos"] + DIRS8[rng.number_range(0, 7)]
		if can_step(m["pos"], n2) and not occupied(n2):
			_move_monster(m, n2)
		return
	var choice := sim.rules_engine.choose(sim, c, c.rules, [player])
	if not choice.is_empty():
		sim.use_ability(c, choice["ability"], choice["target"])
		return
	if d <= 1:
		sim.melee(c, player)
		return
	# Casters keep their distance once in range.
	var keep := int(data.monsters.get(m["id"], {}).get("keep_distance", 0))
	if keep > 0 and d <= keep and los(m["pos"], ppos):
		return
	var nxt = step_down(m["pos"], dist)
	if nxt != null:
		_move_monster(m, nxt)


func _wake(m: Dictionary) -> void:
	m["state"] = "hunt"
	_emit({"t": "wake", "src": m["c"].name, "x": m["pos"].x, "y": m["pos"].y})


func _move_monster(m: Dictionary, to: Vector2i) -> void:
	_emit({"t": "move", "who": m["c"].name, "from": [m["pos"].x, m["pos"].y], "to": [to.x, to.y]})
	m["pos"] = to


## Damage wakes a monster; called after the player's actions via events.
func wake_damaged() -> void:
	for ev in events:
		if ev.get("t") == "damage":
			for m in monsters:
				if m["c"].name == ev.get("dst") and m["state"] != "hunt" and m["c"].is_alive():
					_wake(m)
