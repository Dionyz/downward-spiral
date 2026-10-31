class_name Combatant
extends RefCounted
## One fighter in a combat. Pure data plus small helpers; all rules live in CombatSim.

var id: String = ""
var name: String = ""
var is_player: bool = false
var line: String = ""          # class line for players (warrior, thief, mage, knifer)
var tier: int = 1
var level: int = 1             # in-run level (players) or monster level
var mud_level: int = 10        # level used inside ported MUD formulas

var hp: int = 1
var max_hp: int = 1
var mana: int = 0
var max_mana: int = 0
var mana_regen: int = 0        # per round

var stats := {"str": 15, "dex": 15, "con": 15, "int": 15, "wis": 15}
var size: String = "medium"
var damroll: int = 0
var hitroll: int = 0
var toughness: int = 0         # flat damage reduction (MUD victim->toughness)
var ac: int = 0
var resist: Array = []         # damage types
var vuln: Array = []
var immune: Array = []
var no_stun: bool = false      # MUD DEF_NOSTUN

var skills: Dictionary = {}    # skill name -> proficiency 0..100
var actives: Array = []        # equipped active ability refs (max 4 for players)
var rules: Array = []          # [{if, value, then}]

## Weapons: {type, type_id, min, max, level, flags:[]}. NPCs without a weapon use dmg_min/max.
var weapon = null
var offhand = null             # second weapon (dual wield)
var shield = null              # {block: int}
var dmg_min: int = 1
var dmg_max: int = 4
var dam_type: String = "slash"
var attack_noun: String = "hit"
var melee_fail: int = 0        # MUD pcdata->melee_fail (0) / NPC 40

var statuses: Dictionary = {}  # name -> {rounds:int, ...data}
var cooldowns: Dictionary = {} # ability ref -> rounds left
var stance: String = ""        # knifer dance: mist, storm, cobra, predator
var telegraph: Dictionary = {} # enemy pending telegraph {ability, tag, name, rounds}
var monster_abilities: Dictionary = {}
var flags: Dictionary = {}     # boon-driven flags and counters
var tags: Array = []           # "elite", "boss"...


func is_alive() -> bool:
	return hp > 0


func hp_pct() -> float:
	return 100.0 * float(hp) / float(maxi(1, max_hp))


func mana_pct() -> float:
	if max_mana <= 0:
		return 100.0
	return 100.0 * float(mana) / float(max_mana)


func skill(n: String) -> int:
	return int(skills.get(n, 0))


func has_status(s: String) -> bool:
	return statuses.has(s)


func status_data(s: String) -> Dictionary:
	return statuses.get(s, {})


func add_status(s: String, rounds: int, data: Dictionary = {}) -> void:
	var d := data.duplicate()
	d["rounds"] = rounds
	if statuses.has(s):
		d["rounds"] = maxi(rounds, int(statuses[s].get("rounds", 0)))
	statuses[s] = d


func remove_status(s: String) -> void:
	statuses.erase(s)


func is_awake() -> bool:
	return not has_status("asleep")


## Can this combatant see? (MUD can_see: blindness is the only v1 source.)
func can_see() -> bool:
	return not has_status("blind")


func is_stunned() -> bool:
	return has_status("stunned")


## Dazed/knocked-down/asleep/stunned fighters cannot use abilities or start telegraphs.
func can_act() -> bool:
	return is_alive() and not (has_status("stunned") or has_status("asleep") or has_status("dazed"))


func cooldown(ref: String) -> int:
	return int(cooldowns.get(ref, 0))


func total_damroll() -> int:
	var d := damroll
	for s in statuses.values():
		d += int(s.get("damroll", 0))
	return d


func total_hitroll() -> int:
	var h := hitroll
	for s in statuses.values():
		h += int(s.get("hitroll", 0))
	return h


## Sum of fractional damage reduction from buffs (armor/shield spells), capped.
func buff_reduction() -> float:
	var r := 0.0
	for s in statuses.values():
		r += float(s.get("damage_reduction", 0.0))
	return minf(r, 0.6)


func line_is(lines: Array) -> bool:
	return lines.has(line)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "is_player": is_player, "line": line, "tier": tier, "level": level,
		"hp": hp, "max_hp": max_hp, "mana": mana, "max_mana": max_mana, "statuses": statuses.duplicate(true),
		"stance": stance, "cooldowns": cooldowns.duplicate(),
	}
