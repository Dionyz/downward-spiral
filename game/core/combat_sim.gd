class_name CombatSim
extends RefCounted
## Deterministic, headless combat. Ports the MUD's round structure:
##   violence_update()/multi_hit()  -> step(), _multi_hit()
##   one_hit()                      -> _one_hit()
##   get_char_min()/get_char_max()  -> damage_range()
##   damage()                       -> apply_damage()
##   check_parry/dodge/shield_block -> parry_chance(), dodge_chance(), block_chance()
## Returns structured events; the UI turns them into animation and log text.

const OPENER_DTS := ["backstab", "circle", "charge"]       # multi_hit stops before second attack
const SPECIAL_DT_CRIT := ["backstab", "circle", "cross slash", "charge"]
const THIEF_WARRIOR_LINES := ["warrior", "thief"]           # IS_THIEF || IS_WARRIOR for critical hit
const HIT := "hit"                                           # dt for a normal auto-attack

var rng: DSRng
var data: DSData
var balance: Dictionary
var rules_engine: DSRules

var player: Combatant
var enemies: Array = []        # Array[Combatant]
var round_num: int = 0
var over: bool = false
var result: String = ""        # "win" | "loss" | "extract"
var events: Array = []         # events from the current step
var log_all: bool = true
var history: Array = []        # every event of the fight when log_all
var max_rounds: int = 200
## Map play hooks (DSWorld sets these): range_check(c, ref, target) -> bool decides whether an
## ability can reach its target; area_targets(c, ability) -> Array lists who an area ability hits.
var range_check: Callable = Callable()
var area_targets: Callable = Callable()


func _init(p_rng: DSRng, p_data: DSData) -> void:
	rng = p_rng
	data = p_data
	balance = data.balance
	rules_engine = DSRules.new()
	max_rounds = int(balance.get("max_rounds", 200))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func begin(p: Combatant, foes: Array) -> Array:
	player = p
	enemies = foes
	round_num = 0
	over = false
	result = ""
	events = []
	history = []
	player.flags["second_wind_used"] = false
	player.flags["last_stand_used"] = false
	player.flags["first_blood_ready"] = player.flags.get("boon_first_blood", false) or bstat(player, "b_first_blood") > 0
	player.flags["momentum"] = 0
	player.flags["rampage"] = 0
	player.flags["retaliate_ready"] = false
	player.flags["shield_hp"] = 0
	player.flags["counter_ready"] = false
	_emit({"t": "fight_start", "src": player.name, "enemies": foes.map(func(e): return e.name)})
	if _has_passive(player, "pale_ward"):
		player.add_status("sanctuary", 3)
		_emit({"t": "status_applied", "src": player.name, "dst": player.name, "status": "sanctuary", "rounds": 3})
	return events


## Simulate one round. Returns that round's events.
func step() -> Array:
	events = []
	if over:
		return events
	round_num += 1
	_emit({"t": "round", "n": round_num})

	# 1. Tick durations, cooldowns, regeneration, damage over time.
	for c in _all():
		if c.is_alive():
			_tick(c)
	if _check_end():
		return events

	# 2-3. Player: stunned loses the round; else rules, then the class's automatic choice.
	if player.is_alive() and not player.is_stunned() and player.is_awake():
		if player.can_act():
			var choice := rules_engine.choose(self, player, player.rules, enemies)
			if choice.is_empty():
				choice = auto_choice(player)
			if not choice.is_empty():
				use_ability(player, choice["ability"], choice["target"])
	elif player.is_stunned():
		_emit({"t": "stunned", "src": player.name})
	if _check_end():
		return events

	# 4. Enemies: their own short rule lists.
	for e in enemies:
		if not e.is_alive() or not player.is_alive():
			continue
		if e.can_act() and e.is_awake():
			var ech := rules_engine.choose(self, e, e.rules, [player])
			if not ech.is_empty():
				use_ability(e, ech["ability"], ech["target"])
	if _check_end():
		return events

	# 5. Auto-attacks: player then each enemy (MUD violence_update order is list order).
	if player.is_alive() and not player.is_stunned() and player.is_awake():
		var t = _default_target(player)
		if t != null:
			_multi_hit(player, t, HIT)
	for e in enemies:
		if not player.is_alive():
			break
		if e.is_alive() and not e.is_stunned() and e.is_awake():
			_multi_hit(e, player, HIT)
		elif e.is_alive() and e.is_stunned():
			_emit({"t": "stunned", "src": e.name})
	_check_end()
	if round_num >= max_rounds and not over:
		over = true
		result = "loss"
		_emit({"t": "fight_end", "result": "timeout"})
	return events


## Run to completion (tests, balance scripts, CLI).
func run(p: Combatant, foes: Array) -> Array:
	begin(p, foes)
	while not over:
		step()
	return history


## When no rule fires, the class plays itself: first usable equipped active, in equip order.
## Stances are only taken automatically when the character has none. Buffs already up and
## openers that need a healthy target are filtered out by can_use.
func auto_choice(c: Combatant) -> Dictionary:
	if c.flags.get("no_auto", false):
		return {}
	var tgt = _default_target(c)
	if tgt == null:
		return {}
	for ref in c.actives:
		var a := _ability_def(c, str(ref))
		var use_target = c if a.get("target", "enemy") == "self" else tgt
		if can_use(c, str(ref), use_target):
			return {"ability": str(ref), "target": use_target, "rule": -1}
	return {}


func _has_passive(c: Combatant, pid: String) -> bool:
	return c.flags.get("passives", []).has(pid)


## Potions: the only direct player actions during a fight besides tap-to-queue and extract.
func use_potion(kind: String) -> void:
	var pct := float(balance.get("potion_pct", 35)) / 100.0
	if player.flags.get("boon_potion", false):
		pct *= 1.5
	if kind == "hp":
		var amt := int(player.max_hp * pct)
		player.hp = mini(player.max_hp, player.hp + amt)
		_emit({"t": "heal", "src": player.name, "dst": player.name, "amount": amt, "source": "potion"})
	elif kind == "mp":
		var amt := int(player.max_mana * pct)
		player.mana = mini(player.max_mana, player.mana + amt)
		_emit({"t": "mana", "src": player.name, "amount": amt, "source": "potion"})


func living_enemies() -> Array:
	return enemies.filter(func(e): return e.is_alive())


# ---------------------------------------------------------------------------
# Rounds
# ---------------------------------------------------------------------------

func _all() -> Array:
	var a: Array = [player]
	a.append_array(enemies)
	return a


func _tick(c: Combatant) -> void:
	for k in c.cooldowns.keys():
		c.cooldowns[k] = int(c.cooldowns[k]) - 1
		if c.cooldowns[k] <= 0:
			c.cooldowns.erase(k)
	# Regeneration boon: a share of max HP back every turn.
	if c.is_player and bstat(c, "b_regen") > 0 and c.is_alive() and c.hp < c.max_hp:
		c.hp = mini(c.max_hp, c.hp + maxi(1, DSStats.idiv(c.max_hp * bstat(c, "b_regen"), 100)))
	# Damage over time before durations drop.
	if c.has_status("poisoned") and c.immune.has("poison"):
		c.remove_status("poisoned")
	if c.has_status("poisoned"):
		var pd := int(c.status_data("poisoned").get("dmg", 1))
		if not c.is_player and player != null:
			pd += DSStats.idiv(pd * bstat(player, "b_poison_amp"), 100)
			if bstat(player, "b_contagion") > 0 and rng.number_percent() <= bstat(player, "b_contagion"):
				var clean := opponents_of(player).filter(func(f): return f != c and f.is_alive() and not f.has_status("poisoned"))
				if not clean.is_empty():
					var t: Combatant = rng.pick(clean)
					t.add_status("poisoned", 3, c.status_data("poisoned").duplicate())
					_emit({"t": "status_applied", "src": player.name, "dst": t.name, "status": "poisoned", "rounds": 3})
		_raw_damage(null, c, pd, "poison")
		if not c.is_alive():
			return
	if c.has_status("bleeding"):
		var bd := int(c.status_data("bleeding").get("dmg", 1))
		_raw_damage(null, c, bd, "bleed")
		if not c.is_alive():
			return
	for s in c.statuses.keys():
		var st: Dictionary = c.statuses[s]
		if int(st.get("rounds", 0)) < 0:
			continue  # permanent for the fight
		st["rounds"] = int(st["rounds"]) - 1
		if st["rounds"] <= 0:
			c.statuses.erase(s)
			_emit({"t": "status_expired", "src": c.name, "status": s})
	if c.mana_regen > 0 and c.mana < c.max_mana:
		c.mana = mini(c.max_mana, c.mana + c.mana_regen)


func _check_end() -> bool:
	if over:
		return true
	if not player.is_alive():
		over = true
		result = "loss"
		_emit({"t": "fight_end", "result": "loss"})
		return true
	if living_enemies().is_empty():
		over = true
		result = "win"
		_emit({"t": "fight_end", "result": "win"})
		return true
	return false


func _default_target(c: Combatant):
	if c.is_player:
		for e in enemies:
			if e.is_alive():
				return e
		return null
	return player


## How many enemies are fighting the player right now (map play: awake and close).
var engaged_count: Callable


func _engaged() -> int:
	if engaged_count.is_valid():
		return int(engaged_count.call())
	return living_enemies().size()


## Boon stat (summed over ranks) on a combatant: 0 if absent.
static func bstat(c: Combatant, k: String) -> int:
	return int(c.flags.get(k, 0)) if c != null else 0


func opponents_of(c: Combatant, aname: String = "") -> Array:
	if area_targets.is_valid():
		return area_targets.call(c, aname)
	return living_enemies() if c.is_player else ([player] if player.is_alive() else [])


## Map play: tick one combatant's statuses, cooldowns and regen (one turn).
func tick(c: Combatant) -> void:
	_tick(c)


## Map play: a new encounter starts (resets once-per-fight effects).
func start_encounter() -> void:
	player.flags["second_wind_used"] = false
	player.flags["last_stand_used"] = false
	player.flags["first_blood_ready"] = player.flags.get("boon_first_blood", false) or bstat(player, "b_first_blood") > 0
	player.flags["momentum"] = 0
	player.flags["rampage"] = 0
	player.flags["retaliate_ready"] = false
	player.flags["shield_hp"] = 0
	player.flags["counter_ready"] = false
	if _has_passive(player, "pale_ward"):
		player.add_status("sanctuary", 3)
		_emit({"t": "status_applied", "src": player.name, "dst": player.name, "status": "sanctuary", "rounds": 3})


## Map play: one melee attack (a full MUD attack round) against `victim`.
func melee(ch: Combatant, victim: Combatant) -> void:
	_multi_hit(ch, victim, HIT)
	# Flurry boon: a chance for one more swing.
	if ch.is_player and victim.is_alive() and ch.is_alive() and rng.number_percent() <= bstat(ch, "b_flurry"):
		_one_hit(ch, victim, HIT, false)


# ---------------------------------------------------------------------------
# multi_hit / one_hit
# ---------------------------------------------------------------------------

## fight.c multi_hit(): one swing, then percent rolls for each extra attack.
func _multi_hit(ch: Combatant, victim: Combatant, dt: String) -> void:
	if not victim.is_alive():
		return
	var fail := ch.melee_fail
	var slowed := ch.has_status("slowed")
	_one_hit(ch, victim, dt, false)
	if not victim.is_alive():
		return

	# Dual wield.
	if ch.offhand != null:
		var c := DSStats.idiv(ch.skill("dual wield"), 3) * 2 + 33
		if rng.number_percent() < c:
			_one_hit(ch, victim, dt, true)
			if not victim.is_alive():
				return

	if dt == "cross slash":
		return

	# Haste.
	if ch.has_status("haste"):
		_one_hit(ch, victim, dt, false)
		if not victim.is_alive():
			return

	if dt in OPENER_DTS:
		return

	if dt == HIT and _has_passive(ch, "phantom_edge") and rng.number_percent() <= 25:
		_one_hit(ch, victim, dt, false)
		if not victim.is_alive():
			return

	# NPC extra swings ("speed"): monsters' flat bonus attacks.
	for _i in int(ch.flags.get("speed", 0)):
		_one_hit(ch, victim, dt, false)
		if not victim.is_alive():
			return

	var hit := false
	if ch.skill("second attack") > 0:
		var c2 := DSStats.idiv(ch.skill("second attack"), 3) * 2
		if slowed:
			c2 = DSStats.idiv(c2 * 2, 3)
		if rng.number_percent() < c2:
			_one_hit(ch, victim, dt, false)
			hit = true
			if not victim.is_alive():
				return
	if ch.skill("third attack") > 0:
		var c3 := DSStats.idiv(ch.skill("third attack"), 2)
		if not hit:
			c3 -= fail
		if slowed:
			c3 = DSStats.idiv(c3, 2)
		if rng.number_percent() < c3:
			_one_hit(ch, victim, dt, false)
			hit = true
			if not victim.is_alive():
				return
		else:
			hit = false
	if ch.skill("fourth attack") > 0:
		var c4 := DSStats.idiv(ch.skill("fourth attack") * 4, 5)
		if not hit:
			c4 -= fail
		if slowed:
			c4 = DSStats.idiv(c4, 2)
		if rng.number_percent() < c4:
			_one_hit(ch, victim, dt, false)


## fight.c one_hit(): defenses in order, then damage roll.
func _one_hit(ch: Combatant, victim: Combatant, dt: String, offhand: bool) -> void:
	if not victim.is_alive() or ch == victim:
		return
	var wield = ch.offhand if offhand else ch.weapon
	# Defenses only apply to normal swings (dt >= TYPE_HIT in the MUD).
	if dt == HIT:
		if _check_parry(ch, victim):
			return
		if _check_dodge(ch, victim):
			return
		if _check_block(ch, victim):
			return
		if _check_sidestep(ch, victim):
			return
	var st0 := rng.number_percent() < ch.skill("enhanced damage")
	var st4 := false
	if ch.is_player and ch.line_is(THIEF_WARRIOR_LINES) and not ch.is_stunned() \
			and rng.number_percent() < ch.skill("critical hit") and rng.number_percent() < 15 \
			and (dt == HIT or dt in SPECIAL_DT_CRIT):
		st4 = true
	var rngs := damage_range(ch, dt, wield, st0, st4)
	var lo: int = rngs[0]
	var hi: int = rngs[1]
	var dam := lo if lo > hi else rng.number_range(lo, hi)
	if dam <= 0:
		dam = 1
	# Parry-stack boon: bonus to next swing.
	if ch.flags.get("boon_bloodied", false) and ch.hp_pct() < 40.0:
		dam += DSStats.idiv(dam, 4)
	if ch.flags.get("boon_opportunist", false) and (not victim.can_see() or victim.is_stunned() or victim.has_status("knocked_down")):
		dam += DSStats.idiv(dam * 3, 10)
	if ch.flags.get("boon_executioners_eye", false) and victim.hp_pct() < 30.0:
		dam += DSStats.idiv(dam, 5)
	if ch.flags.get("counter_ready", false):
		dam += DSStats.idiv(dam, 2)
		ch.flags["counter_ready"] = false
	if ch.flags.get("first_blood_ready", false):
		dam += DSStats.idiv(dam * maxi(100, bstat(ch, "b_first_blood")), 100)
		ch.flags["first_blood_ready"] = false
	var mom := int(ch.flags.get("momentum", 0))
	if mom > 0:
		dam += DSStats.idiv(dam * 10 * mom, 100)
	var stacks := int(ch.flags.get("parry_stacks", 0))
	if stacks > 0:
		dam += DSStats.idiv(dam * 5 * stacks, 100)
		ch.flags["parry_stacks"] = 0
	var dtype: String = ch.dam_type
	if wield != null:
		dtype = str(wield.get("dam_type", ch.dam_type))
	if _has_passive(ch, "executioner") and victim.hp_pct() < 25.0:
		dam += DSStats.idiv(dam, 2)
	var ev_extra := {"dt": dt, "crit": st4, "enhanced": st0, "offhand": offhand}
	var dealt := apply_damage(ch, victim, dam, dt, dtype, false, ev_extra)
	if dealt > 0 and wield != null:
		_weapon_effects(ch, victim, wield)
	if dealt > 0 and _has_passive(ch, "bloodthirst") and ch.is_alive():
		var heal := DSStats.idiv(dealt, 3)
		if heal > 0:
			ch.hp = mini(ch.max_hp, ch.hp + heal)
			_emit({"t": "heal", "src": ch.name, "dst": ch.name, "amount": heal, "source": "bloodthirst"})
	if dealt > 0 and _has_passive(victim, "thornmail") and ch.is_alive():
		_raw_damage(victim, ch, maxi(1, DSStats.idiv(dealt * 15, 100)), "thorns")



## get_char_min()/get_char_max(). Returns [min, max] before damage() reductions.
func damage_range(ch: Combatant, dt: String, wield, st0: bool, st4: bool) -> Array:
	var mn: int
	var mx: int
	if wield == null:
		if ch.is_player:
			mn = DSStats.idiv(ch.mud_level, 2)
			mx = ch.mud_level
		else:
			mn = ch.dmg_min
			mx = ch.dmg_max
	else:
		mn = int(wield.get("min", 1))
		mx = int(wield.get("max", 4))
	var dr := ch.total_damroll()
	mn += DSStats.idiv(dr, 10)
	mx += DSStats.idiv(dr, 10)
	var wflags: Array = [] if wield == null else wield.get("flags", [])
	if "sharp" in wflags:
		mn += DSStats.idiv(mn * 15, 100)
		mx += DSStats.idiv(mx * 15, 100)
	if "vorpal" in wflags:
		mn += DSStats.idiv(mn, 20)
		mx += DSStats.idiv(mx, 20)
	if st0:
		mn += DSStats.idiv(mn, 2)
		mx += DSStats.idiv(mx, 2)
	if st4:
		mn += DSStats.idiv(mn, 2)
		mx += DSStats.idiv(mx, 2)
	# Ability weapon scaling (backstab, circle, cross slash, charge, whirlwind, storm, toss).
	if wield != null and dt != HIT:
		var a := data.ability(dt)
		var ws: Dictionary = a.get("params", {}).get("weapon_scale", {})
		var wl := int(wield.get("level", 1))
		if not ws.is_empty():
			var pref = ws.get("preferred", null)
			var idx := 1 if (pref != null and str(pref) == str(wield.get("type", ""))) else 0
			var min_pct: float = float(ws.get("min_pct", [0, 0])[idx])
			var max_pct: float = float(ws.get("max_pct", [0, 0])[idx])
			mn += int(float(mn) * (float(wl) * min_pct) / 100.0)
			mx += int(float(mx) * (float(wl) * max_pct) / 100.0)
		if dt == "toss daggers":
			mx += DSStats.idiv(mx * 5, 4)
	if ch.is_player and wield != null:
		var wskill := int(ch.flags.get("weapon_skill", 75))
		mn = DSStats.idiv(mn * wskill, 100)
		mx = DSStats.idiv(mx * wskill, 100)
	var mult := float(ch.flags.get("damage_mult", 1.0))
	if mult != 1.0:
		mn = int(mn * mult)
		mx = int(mx * mult)
	return [mn, mx]


# ---------------------------------------------------------------------------
# Defenses
# ---------------------------------------------------------------------------

## check_parry(). `ch` attacks, `victim` defends.
func parry_chance(ch: Combatant, victim: Combatant) -> int:
	if not victim.is_awake():
		return 0
	var c := DSStats.idiv(victim.skill("parry"), 3)
	if victim.weapon == null and victim.offhand == null:
		if victim.is_player:
			return 0
		c = DSStats.idiv(c, 2)
	if not ch.can_see():
		c = DSStats.idiv(c, 2)
	c = clampi(c, 10, 50)
	if victim.is_stunned():
		c = 10
	if victim.has_status("transfixed"):
		c = 0
	return c


## check_dodge().
func dodge_chance(ch: Combatant, victim: Combatant) -> int:
	if not victim.is_awake():
		return 0
	var c := DSStats.idiv(victim.skill("dodge"), 2)
	if not victim.can_see():
		c = DSStats.idiv(c, 2)
	if victim.is_stunned():
		c = mini(c, 10)
	else:
		var size_max := {"tiny": 90, "small": 80, "medium": 70, "large": 60, "huge": 50, "giant": 40}
		c = clampi(c, 10, int(size_max.get(victim.size, 70)))
	if victim.has_status("transfixed"):
		c = 0
	return c


## check_shield_block().
func block_chance(_ch: Combatant, victim: Combatant) -> int:
	if not victim.is_awake() or victim.shield == null:
		return 0
	var c := DSStats.idiv(int(victim.shield.get("block", 50)) * victim.skill("shield block"), 100)
	c = clampi(c, 10, 66)
	if victim.is_stunned():
		c = 10
	return c


## check_sidestep(): skill/2 clamped 10..50; no floor without the skill.
func sidestep_chance(_ch: Combatant, victim: Combatant) -> int:
	if not victim.is_awake() or victim.skill("sidestep") < 1:
		return 0
	if victim.is_stunned():
		return 10
	return clampi(DSStats.idiv(victim.skill("sidestep"), 2), 10, 50)


func _check_sidestep(ch: Combatant, victim: Combatant) -> bool:
	var c := sidestep_chance(ch, victim)
	if c <= 0 or rng.number_percent() >= c:
		return false
	_emit({"t": "dodge", "src": victim.name, "dst": ch.name, "how": "sidestep"})
	if victim.flags.get("boon_evasive_counter", false):
		victim.flags["counter_ready"] = true
	return true


func _check_parry(ch: Combatant, victim: Combatant) -> bool:
	var c := parry_chance(ch, victim)
	if c <= 0 or rng.number_percent() >= c:
		return false
	_emit({"t": "parry", "src": victim.name, "dst": ch.name})
	_counterstrike(victim, ch)
	if victim.flags.get("boon_parry_stack", false):
		victim.flags["parry_stacks"] = mini(5, int(victim.flags.get("parry_stacks", 0)) + 1)
	return true


func _check_dodge(ch: Combatant, victim: Combatant) -> bool:
	var c := dodge_chance(ch, victim)
	if c <= 0 or rng.number_percent() >= c:
		return false
	_emit({"t": "dodge", "src": victim.name, "dst": ch.name})
	_counterstrike(victim, ch)
	if victim.flags.get("boon_evasive_counter", false):
		victim.flags["counter_ready"] = true
	return true


## Counterstrike boon: after a parry, dodge or block, a chance to swing back at once.
func _counterstrike(victim: Combatant, ch: Combatant) -> void:
	if victim.is_player and ch.is_alive() and victim.is_alive() and bstat(victim, "b_riposte") > 0 \
			and rng.number_percent() <= bstat(victim, "b_riposte"):
		_one_hit(victim, ch, "counter", false)


func _check_block(ch: Combatant, victim: Combatant) -> bool:
	var c := block_chance(ch, victim)
	if c <= 0 or rng.number_percent() >= c:
		return false
	_emit({"t": "block", "src": victim.name, "dst": ch.name})
	_counterstrike(victim, ch)
	return true


# ---------------------------------------------------------------------------
# damage()
# ---------------------------------------------------------------------------

## fight.c damage(): spell penalty, sanctuary, resist/vuln, toughness, armor class.
## Returns damage dealt. `spell` marks the MUD's spell-damage path (-25%).
func apply_damage(ch, victim: Combatant, dam: int, dt: String, dam_type: String, spell: bool, extra: Dictionary = {}) -> int:
	if not victim.is_alive():
		return 0
	if dam <= 0:
		_emit({"t": "miss", "src": ch.name if ch != null else "", "dst": victim.name, "dt": dt})
		return 0
	var orig := dam
	# Player boons that raise damage dealt.
	if ch != null and ch.is_player:
		dam += bstat(ch, "b_flat")
		if bstat(ch, "b_duel") > 0 and _engaged() <= 1:
			dam += DSStats.idiv(dam * bstat(ch, "b_duel"), 100)
		if bstat(ch, "b_giant") > 0 and (victim.flags.get("elite", false) or victim.flags.get("boss", false)):
			dam += DSStats.idiv(dam * bstat(ch, "b_giant"), 100)
		if ch.flags.get("boon_heavy_hands", false) and dt in ["bash", "kick"]:
			dam += DSStats.idiv(dam, 2)
		if ch.flags.get("boon_assassins_mark", false) and dt in ["backstab", "circle"]:
			dam += DSStats.idiv(dam, 2)
		if dt not in PROC_DTS:
			var pct := bstat(ch, "b_dmg_pct")
			if ch.hp_pct() < 30.0:
				pct += bstat(ch, "b_berserk_low")
			if victim.is_stunned() or victim.has_status("slowed"):
				pct += bstat(ch, "b_cold_snap")
			if victim.has_status("poisoned"):
				pct += bstat(ch, "b_wither")
			if dt in ["whirlwind", "storm of blades"]:
				pct += bstat(ch, "b_aoe_dmg")
			if ch.flags.get("mesmerist_round", false):
				pct += 50
			if int(ch.flags.get("rampage", 0)) > 0 and round_num <= int(ch.flags.get("rampage_until", 0)):
				pct += int(ch.flags["rampage"]) * bstat(ch, "b_rampage")
			if ch.flags.get("retaliate_ready", false) and bstat(ch, "b_retaliate") > 0:
				pct += bstat(ch, "b_retaliate")
				ch.flags["retaliate_ready"] = false
			dam += DSStats.idiv(dam * pct, 100)
		if bstat(ch, "b_crit") > 0 and not extra.get("crit", false) and dt not in PROC_DTS \
				and rng.number_percent() <= bstat(ch, "b_crit"):
			dam = DSStats.idiv(dam * (175 + bstat(ch, "b_crit_dmg")), 100)
			extra = extra.duplicate()
			extra["crit"] = true
	if spell:
		dam -= DSStats.idiv(dam, 4)
	if dam > 1 and victim.has_status("sanctuary"):
		dam = DSStats.idiv(dam, 2)
	if dam_type in victim.immune:
		dam = 0
	elif dam_type in victim.resist:
		dam -= DSStats.idiv(dam, 4)
	elif dam_type in victim.vuln:
		dam += DSStats.idiv(dam, 4)
	dam -= victim.toughness
	# Armor class: dam -= (ac / -2000 * 0.3) * dam, ac clamped to +/-2000.
	var ac := clampi(_total_ac(victim), -2000, 2000)
	dam -= int((float(ac) / -2000.0) * 0.3 * float(dam))
	# Spec: minimum 1 damage once something got through.
	if dam < 1 and orig > 0 and not (dam_type in victim.immune):
		dam = 1
	# Player boons that lower damage taken.
	if victim.is_player and dam > 0:
		var pct := 0
		if victim.hp_pct() < 40.0:
			pct += bstat(victim, "b_dr_low")
		if _engaged() >= 2:
			pct += bstat(victim, "b_dr_pack")
		if dt != HIT and ch != null:
			pct += bstat(victim, "b_dr_special")
		pct += bstat(victim, "b_dr_all")
		if bstat(victim, "b_dr_chill") > 0 and opponents_of(victim).any(func(f): return f.is_alive() and (f.is_stunned() or f.has_status("slowed"))):
			pct += bstat(victim, "b_dr_chill")
		if ch != null and ch.has_status("poisoned"):
			pct += bstat(victim, "b_venom_weaken")
		# Total percent damage reduction from boons is capped (DECISIONS.md D-085).
		dam -= DSStats.idiv(dam * mini(pct, DR_CAP), 100)
		dam = maxi(1, dam - bstat(victim, "b_dr_flat"))
		# Bulwark shield soaks what's left.
		var sh := int(victim.flags.get("shield_hp", 0))
		if sh > 0 and dam > 0:
			var soak := mini(sh, dam - 1)
			victim.flags["shield_hp"] = sh - soak
			dam -= soak
	var dtm := float(victim.flags.get("damage_taken_mult", 1.0))
	if dtm != 1.0 and victim.is_player:
		dam = maxi(1, int(dam * dtm))
	# No one-shots: any single enemy hit is capped at a share of the player's max HP (DECISIONS.md D-013).
	if ch != null and not ch.is_player and victim.is_player and not extra.get("uncapped", false):
		var cap := int(victim.max_hp * float(balance.get("enemy_hit_cap_pct", 35)) / 100.0)
		dam = mini(dam, maxi(1, cap))
	var victim_hp_before := victim.hp
	var dealt := _raw_damage(ch, victim, dam, dt, extra)
	if dealt > 0 and ch != null and ch.is_player and ch.is_alive() and dt not in PROC_DTS:
		_on_hit_procs(ch, victim)
		if extra.get("crit", false) and victim.is_alive() and bstat(ch, "b_crit_bleed") > 0:
			victim.add_status("bleeding", 4, {"dmg": bleed_damage(ch)})
			_emit({"t": "status_applied", "src": ch.name, "dst": victim.name, "status": "bleeding", "rounds": 3})
		if victim.is_alive() and victim.hp_pct() < 20.0 and not victim.flags.get("boss", false) \
				and bstat(ch, "b_execute") > 0 and rng.number_percent() <= bstat(ch, "b_execute"):
			_emit({"t": "ability", "src": ch.name, "dst": victim.name, "ability": "execute"})
			_raw_damage(ch, victim, victim.hp, "execute")
		if not victim.is_alive() and bstat(ch, "b_overkill") > 0:
			var excess := dam - victim_hp_before
			var others := opponents_of(ch).filter(func(f): return f.is_alive() and f != victim)
			if excess > 0 and not others.is_empty():
				apply_damage(ch, rng.pick(others), maxi(1, DSStats.idiv(excess * bstat(ch, "b_overkill"), 100)), "explosion", "none", false, {"uncapped": true})
	if dealt > 0 and victim.is_player and ch != null and ch.is_alive() and dt not in PROC_DTS:
		_on_player_hit(victim, ch, dealt, dt)
	return dealt


## Total percent damage reduction the player can get from boons and families.
const DR_CAP := 90


static func bleed_damage(c: Combatant) -> int:
	return maxi(2, DSStats.idiv(c.mud_level, 3)) * maxi(1, bstat(c, "b_crit_bleed"))


## Boon reactions when the player takes a hit.
func _on_player_hit(p: Combatant, attacker: Combatant, dealt: int, dt: String) -> void:
	if bstat(p, "b_retaliate") > 0:
		p.flags["retaliate_ready"] = true
	if bstat(p, "b_bulwark") > 0:
		p.flags["shield_hp"] = maxi(int(p.flags.get("shield_hp", 0)), DSStats.idiv(p.max_hp * bstat(p, "b_bulwark"), 100))
	if bstat(p, "b_reflect") > 0:
		_raw_damage(p, attacker, maxi(1, DSStats.idiv(dealt * bstat(p, "b_reflect"), 100)), "thorns")
	if dt == HIT and bstat(p, "b_thorns") > 0 and attacker.is_alive():
		_raw_damage(p, attacker, maxi(1, DSStats.idiv(p.mud_level, 5)) * bstat(p, "b_thorns"), "thorns")
	if dt == HIT and attacker.is_alive() and bstat(p, "b_poison_back") > 0 and not attacker.has_status("poisoned") \
			and rng.number_percent() <= bstat(p, "b_poison_back"):
		attacker.add_status("poisoned", 3, {"dmg": maxi(2, DSStats.idiv(p.mud_level, 4))})
		_emit({"t": "status_applied", "src": p.name, "dst": attacker.name, "status": "poisoned", "rounds": 3})
	if dt == HIT and attacker.is_alive() and not attacker.no_stun and bstat(p, "b_freeze_back") > 0 \
			and rng.number_percent() <= bstat(p, "b_freeze_back"):
		_freeze(p, attacker)


func _freeze(src: Combatant, v: Combatant) -> void:
	if v.has_status("stunned"):
		return
	if not _cc(src, v, "stunned", 2 + bstat(src, "b_freeze_long"), "freeze"):
		return
	_emit({"t": "status_applied", "src": src.name, "dst": v.name, "status": "frozen", "rounds": 1 + bstat(src, "b_freeze_long")})


## Damage types made by boon procs: they never trigger more procs.
const PROC_DTS := ["static", "explosion", "poison", "bleed", "thorns"]


## Boon procs when the player lands a hit (Megabonk-style on-hit items).
func _on_hit_procs(ch: Combatant, victim: Combatant) -> void:
	if bstat(ch, "b_zap") > 0 and rng.number_percent() <= bstat(ch, "b_zap"):
		var near := opponents_of(ch, "chain lightning").filter(func(f): return f.is_alive())
		if not near.is_empty():
			var t: Combatant = rng.pick(near)
			apply_damage(ch, t, rng.number_range(3, 6 + ch.mud_level), "static", "lightning", false)
	if victim.is_alive() and bstat(ch, "b_freeze") > 0 and not victim.no_stun and not victim.has_status("stunned") \
			and rng.number_percent() <= bstat(ch, "b_freeze"):
		_freeze(ch, victim)
	if victim.is_alive() and bstat(ch, "b_slow_hit") > 0 and not victim.has_status("slowed") \
			and rng.number_percent() <= bstat(ch, "b_slow_hit"):
		victim.add_status("slowed", 4)
		_emit({"t": "status_applied", "src": ch.name, "dst": victim.name, "status": "slowed", "rounds": 3})
	if victim.is_alive() and bstat(ch, "b_poison") > 0 and rng.number_percent() <= bstat(ch, "b_poison"):
		var had := victim.has_status("poisoned")
		victim.add_status("poisoned", 3, {"dmg": maxi(2, DSStats.idiv(ch.mud_level, 4))})
		if not had:
			_emit({"t": "status_applied", "src": ch.name, "dst": victim.name, "status": "poisoned", "rounds": 3})


## Boss phases: when HP drops below a phase threshold, the monster gains new abilities and rules.
func _check_phase(c: Combatant) -> void:
	var phases: Array = c.flags.get("phases", [])
	var done := int(c.flags.get("phase", 0))
	while done < phases.size() and c.hp_pct() < float(phases[done].get("hp_below", 0)):
		var ph: Dictionary = phases[done]
		var mult := float(c.flags.get("dmg_mult", 1.0))
		var abil: Dictionary = ph.get("abilities", {})
		for k in abil.keys():
			var a: Dictionary = abil[k].duplicate(true)
			a["name"] = k
			if a.has("min"):
				a["min"] = int(float(a["min"]) * mult)
				a["max"] = int(float(a.get("max", a["min"])) * mult)
			c.monster_abilities[k] = a
		var new_rules: Array = ph.get("rules", []).duplicate(true)
		new_rules.append_array(c.rules)
		c.rules = new_rules
		c.flags["speed"] = int(c.flags.get("speed", 0)) + int(ph.get("speed", 0))
		done += 1
		c.flags["phase"] = done
		_emit({"t": "phase", "src": c.name, "n": done + 1, "text": str(ph.get("text", ""))})


func _total_ac(c: Combatant) -> int:
	var a := c.ac
	for s in c.statuses.values():
		a += int(s.get("ac", 0))
	return a


func _raw_damage(ch, victim: Combatant, dam: int, dt: String, extra: Dictionary = {}) -> int:
	dam = maxi(0, dam)
	victim.hp -= dam
	var ev := {"t": "damage", "src": ch.name if ch != null else "", "dst": victim.name, "amount": dam,
		"dt": dt, "hp": maxi(0, victim.hp), "max_hp": victim.max_hp}
	ev.merge(extra)
	_emit(ev)
	# Life leech boon: bank fractions so small hits still add up.
	var leech := (bstat(ch, "b_leech") + (bstat(ch, "b_adrenaline") if ch != null and ch.hp_pct() < 50.0 else 0)) if ch != null else 0
	if ch != null and ch.is_player and ch.is_alive() and dam > 0 and leech > 0 and victim != ch:
		var bank := float(ch.flags.get("leech_bank", 0.0)) + dam * leech / 100.0
		var heal := mini(int(bank), ch.max_hp - ch.hp)
		ch.flags["leech_bank"] = bank - int(bank)
		if heal > 0:
			ch.hp += heal
			_emit({"t": "heal", "src": ch.name, "dst": ch.name, "amount": heal, "source": "leech"})
	# Damage wakes sleepers (DECISIONS.md D-016).
	if victim.has_status("asleep") and dam > 0:
		victim.remove_status("asleep")
		_emit({"t": "status_expired", "src": victim.name, "status": "asleep"})
	if victim.hp > 0 and victim.hp_pct() < 25.0 and _has_passive(victim, "second_wind") \
			and not victim.flags.get("second_wind_used", false):
		victim.flags["second_wind_used"] = true
		var sw := int(victim.max_hp * 0.3)
		victim.hp = mini(victim.max_hp, victim.hp + sw)
		_emit({"t": "heal", "src": victim.name, "dst": victim.name, "amount": sw, "source": "second wind"})
	if victim.hp > 0 and not victim.is_player:
		_check_phase(victim)
	if victim.hp <= 0 and victim.is_player and int(victim.flags.get("last_stands_used", 0)) < bstat(victim, "b_last_stand"):
		victim.flags["last_stands_used"] = int(victim.flags.get("last_stands_used", 0)) + 1
		victim.hp = 1
		_emit({"t": "heal", "src": victim.name, "dst": victim.name, "amount": 0, "source": "last stand"})
	if victim.hp <= 0 and not victim.is_player and player != null and player.is_alive():
		if player.flags.get("boon_momentum", false):
			player.flags["momentum"] = int(player.flags.get("momentum", 0)) + 1
		if bstat(player, "b_rampage") > 0:
			player.flags["rampage"] = int(player.flags.get("rampage", 0)) + 1
			player.flags["rampage_until"] = round_num + 5
		if bstat(player, "b_contagion") > 0 and victim.has_status("poisoned"):
			for f in opponents_of(player):
				if f != victim and f.is_alive() and not f.has_status("poisoned"):
					f.add_status("poisoned", 3, victim.status_data("poisoned").duplicate())
					_emit({"t": "status_applied", "src": player.name, "dst": f.name, "status": "poisoned", "rounds": 3})
		if bstat(player, "b_shatter") > 0 and dt != "explosion" and (victim.is_stunned() or victim.has_status("slowed")):
			var shards := maxi(1, DSStats.idiv(victim.max_hp * bstat(player, "b_shatter"), 100))
			_emit({"t": "ability", "src": player.name, "dst": victim.name, "ability": "shatter"})
			for f in opponents_of(player):
				if f != victim and f.is_alive():
					apply_damage(player, f, shards, "explosion", "cold", false, {"uncapped": true})
		if bstat(player, "b_volatile") > 0 and dt != "explosion":
			var boom := maxi(1, DSStats.idiv(victim.max_hp * bstat(player, "b_volatile"), 100))
			for f in opponents_of(player):
				if f != victim and f.is_alive():
					apply_damage(player, f, boom, "explosion", "fire", false, {"uncapped": true})
		if bstat(player, "b_kill_heal") > 0 and player.hp < player.max_hp:
			var kh := mini(player.max_hp - player.hp, DSStats.idiv(player.max_hp * bstat(player, "b_kill_heal"), 100))
			player.hp += kh
			_emit({"t": "heal", "src": player.name, "dst": player.name, "amount": kh, "source": "bloodlust"})
		if player.flags.get("boon_soul_siphon", false) and player.max_mana > 0:
			player.mana = mini(player.max_mana, player.mana + DSStats.idiv(player.max_mana, 10))
	if victim.hp <= 0:
		victim.hp = 0
		_emit({"t": "death", "src": victim.name, "killer": ch.name if ch != null else ""})
	return dam


func _weapon_effects(ch: Combatant, victim: Combatant, wield) -> void:
	if not victim.is_alive():
		return
	var flags: Array = wield.get("flags", [])
	if ch.has_status("envenomed") or "poison" in flags:
		var lvl := int(wield.get("level", ch.mud_level))
		if not _saves(ch, victim, lvl):
			var pd := maxi(1, DSStats.idiv(ch.mud_level, int(data.ability("envenom").get("params", {}).get("poison_dmg_level_div", 10))))
			if ch.flags.get("boon_virulent", false):
				pd *= 2
			var had := victim.has_status("poisoned")
			victim.add_status("poisoned", 3, {"dmg": pd})
			if not had:
				_emit({"t": "status_applied", "src": ch.name, "dst": victim.name, "status": "poisoned", "rounds": 3})
	if "flaming" in flags:
		apply_damage(ch, victim, rng.number_range(1, DSStats.idiv(int(wield.get("level", 10)), 4) + 1), "flaming", "fire", false)
	if "frost" in flags:
		apply_damage(ch, victim, rng.number_range(1, DSStats.idiv(int(wield.get("level", 10)), 6) + 2), "frost", "cold", false)
	if "vampiric" in flags and victim.is_alive():
		var vd := rng.number_range(1, DSStats.idiv(int(wield.get("level", 10)), 3) + 5)
		var got := apply_damage(ch, victim, vd, "vampiric", "negative", false)
		var heal := DSStats.idiv(got, 2)
		ch.hp = mini(ch.max_hp, ch.hp + heal)


## magic.c saves_magic(), simplified for v1 (no class saves or stat tables). True = victim saved.
func _saves(ch: Combatant, victim: Combatant, level: int) -> bool:
	var save := 25
	var diff := victim.mud_level - level
	if diff > 0:
		save += mini(diff, 30)
	else:
		save -= mini(-diff, 30)
	save += rng.number_range(-10, 10)
	save = clampi(save, 15, 80)
	return rng.number_percent() < save


# ---------------------------------------------------------------------------
# Abilities
# ---------------------------------------------------------------------------

## Split "dance:mist" into ["dance", "mist"].
static func split_ref(ref: String) -> Array:
	var i := ref.find(":")
	if i < 0:
		return [ref, ""]
	return [ref.substr(0, i), ref.substr(i + 1)]


func ability_cost(c: Combatant, ref: String) -> int:
	var a := _ability_def(c, split_ref(ref)[0])
	if a.is_empty():
		return 0
	if c.is_player and c.line != "mage":
		return 0  # cooldown classes: DECISIONS.md D-007
	return DSStats.mana_cost(int(a.get("min_mana", 0)), balance)


func _ability_def(c: Combatant, aname: String) -> Dictionary:
	if c.monster_abilities.has(aname):
		return c.monster_abilities[aname]
	return data.ability(aname)


## Can `c` use ability `ref` on `target` right now? Skipped rules fall through to the next.
func can_use(c: Combatant, ref: String, target) -> bool:
	var parts := split_ref(ref)
	var aname: String = parts[0]
	var arg: String = parts[1]
	var a := _ability_def(c, aname)
	if a.is_empty() or not c.can_act():
		return false
	if c.is_player and not c.actives.has(aname):
		return false
	if c.cooldown(ref) > 0 or c.cooldown(aname) > 0:
		return false
	if c.mana < ability_cost(c, ref):
		return false
	var p: Dictionary = a.get("params", {})
	var tkind: String = a.get("target", "enemy")
	if range_check.is_valid() and not range_check.call(c, ref, target):
		return false
	if tkind == "enemy" or tkind == "all_enemies":
		if target == null or not target.is_alive():
			return false
	match a.get("handler", ""):
		"bash", "trip":
			if target.has_status("knocked_down"):
				return false
		"opener_round":
			var frac := float(p.get("min_victim_hp_frac", 0.0))
			if c.flags.get("boon_backstab_low", false) and aname == "backstab":
				frac = 0.0
			if c.flags.get("boon_cutthroat", false) and aname == "circle":
				frac = 0.0
			if c.flags.get("boon_relentless_charge", false) and aname == "charge":
				frac = 0.0
			if float(target.hp) < float(target.max_hp) * frac:
				return false
			if p.get("needs_weapon", false) and c.weapon == null:
				return false
			if p.get("needs_dual", false) and (c.weapon == null or c.offhand == null):
				return false
		"debuff":
			if target.has_status(str(p.get("status", ""))):
				return false
		"spell_status":
			if target.has_status(str(p.get("status", ""))):
				return false
		"buff", "berserk":
			var st := str(p.get("status", a.get("status", aname)))
			if c.has_status(st):
				return false
		"envenom":
			if c.has_status("envenomed") or c.weapon == null:
				return false
	return true


## Use an ability. Starts its cooldown and spends mana whether or not it lands (MUD wait/mana rules).
func use_ability(c: Combatant, ref: String, target) -> void:
	var parts := split_ref(ref)
	var aname: String = parts[0]
	var arg: String = parts[1]
	var a := _ability_def(c, aname)
	var cost := ability_cost(c, ref)
	if cost > 0 and _has_passive(c, "spellweave") and rng.number_percent() <= 20:
		cost = 0
	c.mana -= cost
	var cd: int
	if a.has("cooldown"):
		cd = int(a["cooldown"])
	else:
		cd = DSStats.cooldown_rounds(int(a.get("beats", 0)), balance)
	if cd > 0:
		if cd > 1:
			cd = maxi(1, cd - bstat(c, "b_cdr"))
		c.cooldowns[aname] = cd + 1  # ticks at the start of each round: a cooldown of N skips N rounds
	_emit({"t": "cast" if cost > 0 else "ability", "src": c.name, "dst": target.name if target != null else "",
		"ability": str(a.get("display", aname)), "id": aname, "arg": arg, "cost": cost})
	var p: Dictionary = a.get("params", {})
	match a.get("handler", ""):
		"bash":
			_h_bash(c, target, a, p)
		"trip":
			_h_trip(c, target, a, p)
		"direct_damage":
			_h_direct(c, target, a, p)
		"berserk":
			_h_berserk(c, a, p)
		"buff":
			_h_buff(c, a, p)
		"opener_round":
			_h_opener(c, target, aname)
		"debuff":
			_h_debuff(c, target, aname, p)
		"envenom":
			_h_envenom(c, p)
		"strike":
			_h_strike(c, target, aname, p)
		"spell_damage":
			_h_spell_damage(c, target, aname, p)
		"chain_lightning":
			_h_chain(c, target, aname, p)
		"spell_status":
			_h_spell_status(c, target, aname, p)
		"aoe_strike":
			_h_aoe(c, aname, p)
		"transfix":
			_h_transfix(c, target, p)
		"monster_strike":
			_h_monster_strike(c, target, aname, a)
		"monster_status":
			_h_monster_status(c, target, aname, a)
		"monster_heal":
			_h_monster_heal(c, a)
		_:
			push_warning("CombatSim: no handler for %s" % aname)


func _skill_for(c: Combatant, aname: String) -> int:
	if not c.is_player:
		return int(c.monster_abilities.get(aname, {}).get("skill", 75))
	return c.skill(aname)


## Skill roll for an active ability. The player's actives never fail (owner); monsters still roll.
## (Defenses like dodge and parry, and saves against spells, are separate and still apply.)
func _fails(c: Combatant, chance: int) -> bool:
	if c.is_player:
		return false
	return rng.number_percent() >= chance


## Player skills that inflict a status still have a small chance to fail (balance.status_fail_pct).
func _status_skill_fails(c: Combatant) -> bool:
	return c.is_player and rng.number_percent() <= int(balance.get("status_fail_pct", 10))


## Statuses that take a fighter out of the fight: these get diminishing returns.
const INCAPACITATING := ["stunned", "knocked_down", "asleep"]


## Apply an incapacitating status with diminishing returns: each one landed on the same target
## within `cc_window` turns of the last halves the chance of the next (100%, 50%, 25%), and after
## that the target is immune until the window runs out. Returns true if it took hold.
func _cc(src: Combatant, v: Combatant, status: String, rounds: int, label: String = "") -> bool:
	var cc: Dictionary = balance.get("diminishing", {})
	if round_num > int(v.flags.get("cc_until", -1)):
		v.flags["cc_count"] = 0
	var n := int(v.flags.get("cc_count", 0))
	var steps: Array = cc.get("chances", [100, 50, 25])
	var chance := int(steps[n]) if n < steps.size() else 0
	if chance < 100 and rng.number_percent() > chance:
		_emit({"t": "resist", "src": v.name, "ability": label if label != "" else status.replace("_", " "), "dr": true})
		return false
	v.flags["cc_count"] = n + 1
	v.flags["cc_until"] = round_num + rounds + int(cc.get("window", 6))
	v.add_status(status, rounds)
	return true


func _miss(c: Combatant, target, aname: String) -> void:
	_emit({"t": "ability_miss", "src": c.name, "dst": target.name if target != null else "", "ability": aname})


## act_combat.c do_bash
func _h_bash(c: Combatant, v: Combatant, _a: Dictionary, p: Dictionary) -> void:
	var chance := _skill_for(c, "bash")
	var sd := DSStats.size_index(c.size) - DSStats.size_index(v.size)
	chance += sd * (3 if sd < 0 else 5)
	chance += int(c.stats.get("str", 15)) - int(v.stats.get("dex", 15))
	chance -= 5  # victim standing
	chance += DSStats.idiv(c.mud_level - v.mud_level, 1)
	if _fails(c, chance) or _status_skill_fails(c):
		_miss(c, v, "bash")
		return
	var dmg := rng.number_range(DSStats.idiv(c.mud_level, int(p.get("dam_min_level_div", 2))), c.mud_level * int(p.get("dam_max_level_mult", 1)))
	apply_damage(c, v, dmg, "bash", "bash", false)
	if not v.is_alive():
		return
	if v.flags.has("steady") and rng.number_percent() <= int(v.flags["steady"]):
		_emit({"t": "resist", "src": v.name, "ability": "knockdown"})
		return
	if not _cc(c, v, "knocked_down", int(p.get("knockdown_rounds", 1)) + 1, "knockdown"):
		return
	v.add_status("dazed", 2 + 1)
	_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "knocked_down", "rounds": 1})
	if c.flags.get("boon_bash_slow", false):
		v.add_status("slowed", 2 + 1)
		_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "slowed", "rounds": 2})
	# Stun rider (do_bash secondary roll; warrior line doubles it as in do_shield_smash).
	var stun := c.skill("stun")
	if stun > 0 and not v.no_stun:
		var sc := DSStats.idiv(stun, 2) if c.line == "warrior" else DSStats.idiv(stun, 4)
		if rng.number_percent() < sc and rng.number_percent() < rng.dice(2, c.mud_level):
			var dur := rng.dice(1, 2)
			if _cc(c, v, "stunned", dur + 1, "stun"):
				_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "stunned", "rounds": dur})


## act_combat.c do_trip
func _h_trip(c: Combatant, v: Combatant, _a: Dictionary, p: Dictionary) -> void:
	var chance := _skill_for(c, "trip")
	chance += int(c.stats.get("dex", 15)) - DSStats.idiv(int(v.stats.get("dex", 15)) * 3, 2)
	chance += (c.mud_level - v.mud_level) * 2
	if v.size == "giant" or v.flags.get("flying", false):
		chance = 0
	if _fails(c, chance) or _status_skill_fails(c):
		_miss(c, v, "trip")
		return
	apply_damage(c, v, rng.number_range(2, 2 * (DSStats.size_index(v.size) + 1) + 2), "trip", "bash", false)
	if not v.is_alive():
		return
	if v.flags.has("steady") and rng.number_percent() <= int(v.flags["steady"]):
		_emit({"t": "resist", "src": v.name, "ability": "knockdown"})
		return
	if not _cc(c, v, "knocked_down", int(p.get("knockdown_rounds", 1)) + 1, "knockdown"):
		return
	v.add_status("dazed", 2 + 1)
	_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "knocked_down", "rounds": 1})


## act_combat.c do_kick
func _h_direct(c: Combatant, v: Combatant, _a: Dictionary, p: Dictionary) -> void:
	var aname := "kick"
	if _fails(c, _skill_for(c, aname)):
		_miss(c, v, aname)
		return
	var lo := c.mud_level * int(p.get("dam_min_level_mult", 1))
	var hi := c.mud_level * int(p.get("dam_max_level_mult", 2))
	apply_damage(c, v, rng.number_range(lo, hi), aname, str(p.get("dam_type", "bash")), false)
	if c.flags.get("boon_stunning_kick", false) and v.is_alive() and not v.no_stun and rng.number_percent() <= 25 \
			and _cc(c, v, "stunned", 2, "stun"):
		_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "stunned", "rounds": 1})


## act_combat.c do_berserk
func _h_berserk(c: Combatant, a: Dictionary, p: Dictionary) -> void:
	var chance := _skill_for(c, "berserk") + int(p.get("fighting_bonus", 10))
	chance -= DSStats.idiv(DSStats.idiv(c.hp * 100, maxi(1, c.max_hp)), 2)
	chance += int(p.get("flat_bonus", 25))
	chance = maxi(chance, int(p.get("min_chance", 10)))
	if _fails(c, chance):
		_miss(c, null, "berserk")
		return
	var heal := c.mud_level * int(p.get("heal_level_mult", 2))
	c.hp = mini(c.max_hp, c.hp + heal)
	_emit({"t": "heal", "src": c.name, "dst": c.name, "amount": heal, "source": "berserk"})
	var mod := maxi(1, DSStats.idiv(c.mud_level, int(p.get("mod_level_div", 4))))
	var rounds := int(p.get("duration_rounds", 6))
	if c.flags.get("boon_long_berserk", false):
		rounds *= 2
	c.add_status("berserk", rounds + 1, {"hitroll": mod, "damroll": mod, "ac": int(p.get("ac", 0))})
	_emit({"t": "status_applied", "src": c.name, "dst": c.name, "status": "berserk", "rounds": rounds})


## Generic self-buff: warcry, armor, shield, sanctuary, haste.
func _h_buff(c: Combatant, a: Dictionary, p: Dictionary) -> void:
	var aname: String = a.get("name", "")
	if c.is_player and c.line != "mage" and _fails(c, _skill_for(c, aname)):
		_miss(c, null, aname)
		return
	var st := str(p.get("status", aname))
	var rounds := int(p.get("duration_rounds", 6))
	if c.flags.get("boon_lingering_ward", false) and aname in ["shield", "armor"]:
		rounds *= 2
	if c.flags.get("boon_warcry_heal", false) and aname == "warcry":
		var wh := int(c.max_hp * 0.15)
		c.hp = mini(c.max_hp, c.hp + wh)
		_emit({"t": "heal", "src": c.name, "dst": c.name, "amount": wh, "source": "warcry"})
	var d := {}
	if p.has("hitroll_level_div"):
		d["hitroll"] = DSStats.idiv(c.mud_level, int(p["hitroll_level_div"]))
	if p.has("damroll_level_div"):
		d["damroll"] = DSStats.idiv(c.mud_level, int(p["damroll_level_div"]))
	if p.has("ac"):
		d["ac"] = int(p["ac"])
	if p.has("damage_reduction"):
		d["damage_reduction"] = float(p["damage_reduction"])
	for disp in p.get("dispels", []):
		if c.has_status(disp):
			c.remove_status(disp)
			_emit({"t": "status_expired", "src": c.name, "status": disp})
	c.add_status(st, rounds + 1, d)
	_emit({"t": "status_applied", "src": c.name, "dst": c.name, "status": st, "rounds": rounds})


## backstab / circle / charge / cross slash: skill roll, then a multi_hit with that dt.
func _h_opener(c: Combatant, v: Combatant, aname: String) -> void:
	var chance := _skill_for(c, aname)
	if not v.can_see():
		chance += 25 if aname == "backstab" else 0
	if not _fails(c, chance) or (chance > 1 and not v.is_awake()):
		var saved := c.damroll
		if aname == "charge" and c.weapon != null and str(c.weapon.get("type", "")) == "sword":
			c.damroll += DSStats.idiv(c.mud_level, 4)
		_multi_hit(c, v, aname)
		c.damroll = saved
		if aname == "cross slash":
			_hamstring(c, v)
		if aname == "cross slash" and c.flags.get("boon_bleeding_cross", false) and v.is_alive():
			v.add_status("bleeding", 4, {"dmg": maxi(1, DSStats.idiv(c.mud_level, 4))})
			_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "bleeding", "rounds": 3})
	else:
		_miss(c, v, aname)


## dirt kicking / gouge / blinding strike
func _h_debuff(c: Combatant, v: Combatant, aname: String, p: Dictionary) -> void:
	var chance := _skill_for(c, aname)
	var m: Dictionary = p.get("chance_mods", {})
	var cdex := int(c.stats.get("dex", 15))
	var vdex := int(v.stats.get("dex", 15))
	if m.get("dex_x5", false):
		chance += cdex * 5 - vdex * 5
	if m.has("dex"):
		chance += cdex
	if m.get("victim_dex_x2", false):
		chance -= 2 * vdex
	if c.has_status("haste"):
		chance += 15
	if v.has_status("haste"):
		chance -= 15
	if c.has_status("slowed"):
		chance -= 15
	if v.has_status("slowed"):
		chance += 15
	var lvl_mult := 5 if m.get("level_diff_x5", false) else 1
	chance += (c.mud_level - v.mud_level) * lvl_mult
	if _fails(c, chance) or _status_skill_fails(c):
		_miss(c, v, aname)
		return
	var dr: Array = p.get("dam", [2, 5])
	apply_damage(c, v, rng.number_range(int(dr[0]), int(dr[1])), aname, "none", false)
	if not v.is_alive():
		return
	var st := str(p.get("status", "blind"))
	var rounds := int(p.get("duration_rounds", 2))
	if aname == "dirt kicking" and c.flags.get("boon_long_dirt", false):
		rounds += 2
	var hr := int(p.get("hitroll", -DSStats.idiv(c.mud_level, int(p.get("hitroll_level_div", 4)))))
	v.add_status(st, rounds + 1, {"hitroll": hr})
	_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": st, "rounds": rounds})
	if aname == "blinding strike":
		_hamstring(c, v)


## Hamstring boon (Jackal): Cross Slash and Blinding Strike also slow for 3 turns.
func _hamstring(c: Combatant, v: Combatant) -> void:
	if c.flags.get("boon_hamstring", false) and v.is_alive() and not v.has_status("slowed"):
		v.add_status("slowed", 4)
		_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "slowed", "rounds": 3})


## act_obj.c do_envenom: coats the weapon; swings may poison.
func _h_envenom(c: Combatant, p: Dictionary) -> void:
	if _fails(c, _skill_for(c, "envenom")):
		_miss(c, null, "envenom")
		return
	var rounds := int(p.get("duration_rounds", 6))
	c.add_status("envenomed", rounds + 1, {"damroll": DSStats.idiv(c.mud_level, int(p.get("damroll_level_div", 10)))})
	_emit({"t": "status_applied", "src": c.name, "dst": c.name, "status": "envenomed", "rounds": rounds})


## act_combat.c do_toss
func _h_strike(c: Combatant, v: Combatant, aname: String, p: Dictionary) -> void:
	var chance := _skill_for(c, aname)
	chance = DSStats.idiv(chance * int(p.get("chance_num", 4)), int(p.get("chance_den", 5)))
	if _fails(c, chance):
		_miss(c, v, aname)
		return
	var swings := int(p.get("swings", 1))
	if aname == "toss daggers" and c.flags.get("boon_double_toss", false):
		swings += 1
	for _i in swings:
		_one_hit(c, v, aname, false)


func _spell_scale(c: Combatant = null) -> float:
	var m := 1.0
	if c != null:
		m = float(c.flags.get("spell_mult", 1.0)) * float(c.flags.get("damage_mult", 1.0))
	return float(balance.get("spell_damage_scale", 1.0)) * m


## magic fist, implosion
func _h_spell_damage(c: Combatant, v: Combatant, aname: String, p: Dictionary) -> void:
	var dam := 0
	if p.has("dice_level"):
		dam = rng.dice(c.mud_level, int(p["dice_level"]))
		if _saves(c, v, c.mud_level):
			dam = int(dam * float(p.get("save_mult", 1.0)))
	else:
		dam = rng.number_range(int(p.get("dam_flat_min", 1)), int(p.get("dam_flat_max", 1)) + int(p.get("dam_max_level_mult", 0)) * c.mud_level)
	dam = int(dam * _spell_scale(c))
	if aname == "magic fist" and c.flags.get("boon_empowered_fist", false) and v.hp_pct() > 50.0:
		dam += DSStats.idiv(dam, 2)
	apply_damage(c, v, dam, aname, str(p.get("dam_type", "other")), true)


## magic.c spell_chain_lightning. First strike, then sweeps the room in list order hitting
## everyone except the last victim, losing 8 levels per hit.
func _h_chain(c: Combatant, v: Combatant, aname: String, p: Dictionary) -> void:
	if c.hp < DSStats.idiv(c.max_hp, 20):
		_miss(c, v, aname)
		return
	var level := c.mud_level
	var dl := int(p.get("dice_level", 12))
	var dec := int(p.get("level_decrement", 8))
	if c.flags.get("boon_chain_extra", false):
		level += dec  # one extra jump
	var dam := rng.dice(level, dl)
	if _saves(c, v, level):
		dam = int(dam * float(p.get("save_mult", 0.5)))
	apply_damage(c, v, int(dam * _spell_scale(c)), aname, "lightning", true)
	var last: Combatant = v
	level -= dec
	var guard := 0
	while level > 0 and guard < 50 and c.is_alive():
		guard += 1
		var found := false
		for tv in opponents_of(c, aname):
			if tv == last:
				continue
			found = true
			last = tv
			if level > 0:
				var d2 := rng.dice(level, dl)
				if _saves(c, tv, level):
					d2 = int(d2 * float(p.get("save_mult", 0.5)))
				apply_damage(c, tv, int(d2 * _spell_scale(c)), aname, "lightning", true)
			level -= dec
		if not found:
			return  # one target left: the bolt fizzles (MUD backlash dropped, DECISIONS.md D-025)


## sleep, slow
func _h_spell_status(c: Combatant, v: Combatant, aname: String, p: Dictionary) -> void:
	if p.get("save", false) and _saves(c, v, c.mud_level):
		_emit({"t": "resist", "src": v.name, "ability": aname})
		return
	if aname == "sleep" and v.tags.has("boss"):
		_emit({"t": "resist", "src": v.name, "ability": aname})
		return
	var st := str(p.get("status", aname))
	var rounds := int(p.get("duration_rounds", 2))
	if aname == "sleep" and c.flags.get("boon_deep_sleep", false):
		rounds += 2
	for disp in p.get("dispels", []):
		v.remove_status(disp)
	if INCAPACITATING.has(st):
		if not _cc(c, v, st, rounds + 1, aname):
			return
	else:
		v.add_status(st, rounds + 1)
	_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": st, "rounds": rounds})


## whirlwind, storm of blades: every opponent takes one swing plus bonus swings on a percent roll.
func _h_aoe(c: Combatant, aname: String, p: Dictionary) -> void:
	if _fails(c, _skill_for(c, aname)):
		_miss(c, null, aname)
		return
	for v in opponents_of(c, aname):
		_one_hit(c, v, aname, false)
		var roll := rng.number_percent()
		var extra := 0
		if p.has("bonus_three_over"):
			if roll > int(p["bonus_three_over"]):
				extra = 3
			elif roll > int(p.get("bonus_two_over", 101)):
				extra = 2
		else:
			if roll > int(p.get("bonus_two_over", 101)):
				extra = 2
			elif roll > int(p.get("bonus_one_over", 101)):
				extra = 1
		if aname == "whirlwind" and c.flags.get("boon_whirling_blades", false):
			extra = maxi(extra, 1)
		for _i in extra:
			_one_hit(c, v, aname, false)


## act_combat.c do_transfix: freeze the target for 1-3 rounds, then a full round of attacks.
func _h_transfix(c: Combatant, v: Combatant, p: Dictionary) -> void:
	if _fails(c, _skill_for(c, "transfix")) or _status_skill_fails(c):
		_miss(c, v, "transfix")
		return
	var r: Array = p.get("stun_rounds_range", [1, 3])
	var dur := rng.number_range(int(r[0]), int(r[1]))
	if not v.no_stun and _cc(c, v, "stunned", dur + 1, "stun"):
		_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": "stunned", "rounds": dur})
	if p.get("then_attack", true):
		c.flags["mesmerist_round"] = c.flags.get("boon_mesmerist", false)
		_multi_hit(c, v, HIT)
		c.flags["mesmerist_round"] = false


# ---------------------------------------------------------------------------
# Monster abilities
# ---------------------------------------------------------------------------

func _h_monster_strike(c: Combatant, v: Combatant, aname: String, a: Dictionary) -> void:
	var lo := int(a.get("min", c.dmg_min))
	var hi := int(a.get("max", c.dmg_max))
	apply_damage(c, v, rng.number_range(lo, hi), str(a.get("display", aname)), str(a.get("dam_type", c.dam_type)), false)


func _h_monster_status(c: Combatant, v: Combatant, aname: String, a: Dictionary) -> void:
	if rng.number_percent() >= int(a.get("skill", 60)):
		_miss(c, v, aname)
		return
	var st := str(a.get("status", "poisoned"))
	var rounds := int(a.get("rounds", 3))
	if INCAPACITATING.has(st):
		if not _cc(c, v, st, rounds + 1):
			return
	else:
		v.add_status(st, rounds + 1, {"dmg": int(a.get("dmg", 2))})
	_emit({"t": "status_applied", "src": c.name, "dst": v.name, "status": st, "rounds": rounds})


func _h_monster_heal(c: Combatant, a: Dictionary) -> void:
	var amt := int(c.max_hp * float(a.get("heal_pct", 20)) / 100.0)
	c.hp = mini(c.max_hp, c.hp + amt)
	_emit({"t": "heal", "src": c.name, "dst": c.name, "amount": amt, "source": a.get("name", "heal")})


# ---------------------------------------------------------------------------

func _emit(ev: Dictionary) -> void:
	ev["r"] = round_num
	events.append(ev)
	if log_all:
		history.append(ev)
