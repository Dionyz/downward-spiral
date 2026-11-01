class_name DSData
extends RefCounted
## Loads game/data/*.json and deep-merges game/data/overrides/<same name>.json on top.
## Pure logic: FileAccess only, no Nodes. Tests can also build one from dictionaries.

const FILES := ["classes", "abilities", "items", "monsters", "boons", "events", "rooms", "meta", "balance", "races", "skills", "glossary", "dungeons"]

var classes: Dictionary = {}     # line id -> line dict
var abilities: Dictionary = {}   # ability name -> ability dict
var items: Dictionary = {}
var monsters: Dictionary = {}    # monster id -> monster dict
var boons: Dictionary = {}       # boon id -> boon dict
var races: Dictionary = {}       # race id -> race dict
var glossary: Array = []          # [{cat, term, short, long, keys}]
var families: Dictionary = {}
var boons_meta: Dictionary = {}
var dungeons: Dictionary = {}      # dungeons.json (list, floors, elite/boss floors, abyss rules)    # boons.json top level (rarities, no_scale, luck_shift)    # boon family id -> {name, color, desc, tiers}
var skills: Dictionary = {}      # skill name -> player-facing description
var events: Dictionary = {}    # event id -> event dict
var rooms: Dictionary = {}     # room text templates
var meta: Dictionary = {}      # account progression
var balance: Dictionary = {}


static func load_dir(dir: String = "res://game/data") -> DSData:
	var d := DSData.new()
	var raw := {}
	for f in FILES:
		var base = _read_json("%s/%s.json" % [dir, f])
		var over = _read_json("%s/overrides/%s.json" % [dir, f])
		if base == null:
			base = {}
		if over != null:
			base = deep_merge(base, over)
		raw[f] = base
	d.apply(raw)
	return d


static func from_dicts(raw: Dictionary) -> DSData:
	var d := DSData.new()
	d.apply(raw)
	return d


func apply(raw: Dictionary) -> void:
	classes = raw.get("classes", {}).get("lines", {})
	abilities = raw.get("abilities", {}).get("abilities", {})
	items = raw.get("items", {})
	monsters = raw.get("monsters", {}).get("monsters", {})
	boons = raw.get("boons", {}).get("boons", {})
	families = raw.get("boons", {}).get("families", {})
	boons_meta = raw.get("boons", {})
	dungeons = raw.get("dungeons", {})
	races = raw.get("races", {}).get("races", {})
	skills = raw.get("skills", {}).get("skills", {})
	glossary = raw.get("glossary", {}).get("entries", [])
	events = raw.get("events", {}).get("events", {})
	rooms = raw.get("rooms", {})
	meta = raw.get("meta", {})
	balance = raw.get("balance", {})


func ability(name: String) -> Dictionary:
	return abilities.get(name, {})


## Name of the MUD class for a line at a tier (1..3).
func tier_class(line: String, tier: int) -> String:
	var l: Dictionary = classes.get(line, {})
	var tiers: Array = l.get("tiers", [])
	if tier < 1 or tier > tiers.size():
		return ""
	return tiers[tier - 1].get("mud_class", "")


## In-run unlock level for `ability_name` on `line` at `tier`, or -1 if never.
## Spec kit "starting actives" are forced to level 1 (DECISIONS.md D-010).
func unlock_level(ability_name: String, line: String, tier: int) -> int:
	var l: Dictionary = classes.get(line, {})
	if ability_name in l.get("starting_actives", []) or ability_name in l.get("starting_passives", []):
		return 1
	var a := ability(ability_name)
	if a.is_empty():
		return -1
	var unlock: Dictionary = a.get("unlock", {})
	var tc := tier_class(line, tier)
	if unlock.has(tc):
		return int(unlock[tc])
	return -1


## Every ability name the line could have at `tier` and `level`, filtered to the class kit.
func kit_abilities(line: String, tier: int, level: int, kind: String = "") -> Array:
	var l: Dictionary = classes.get(line, {})
	var kit: Array = []
	for key in ["passives", "starting_actives", "signature"]:
		for n in l.get(key, []):
			if not kit.has(n):
				kit.append(n)
	var out: Array = []
	for n in kit:
		var a := ability(n)
		if a.is_empty():
			continue
		if kind != "" and a.get("kind", "") != kind:
			continue
		var ul := unlock_level(n, line, tier)
		if ul >= 1 and ul <= level:
			out.append(n)
	return out


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed


## Recursively merge `over` into a copy of `base`. Dictionaries merge; anything else replaces.
static func deep_merge(base, over):
	if typeof(base) == TYPE_DICTIONARY and typeof(over) == TYPE_DICTIONARY:
		var out: Dictionary = base.duplicate(true)
		for k in over.keys():
			if out.has(k):
				out[k] = deep_merge(out[k], over[k])
			else:
				out[k] = over[k]
		return out
	return over


func boon_rarities() -> Dictionary:
	return boons_meta.get("rarities", {"common": {"mult": 1.0, "weight": 1}})


# --- dungeons -----------------------------------------------------------------------

func dungeon_list() -> Array:
	return dungeons.get("dungeons", [{"id": "spiral", "name": "The Spiral", "level_offset": 0}])


func dungeon(id: String) -> Dictionary:
	for d in dungeon_list():
		if d["id"] == id:
			return d
	return dungeon_list()[0]


func dungeon_index(id: String) -> int:
	var l := dungeon_list()
	for i in l.size():
		if l[i]["id"] == id:
			return i
	return 0


## "boss", "elite" or "fight" for a floor number.
func floor_kind(floor_num: int) -> String:
	if dungeons.get("boss_floors", [10, 20]).map(func(x): return int(x)).has(floor_num):
		return "boss"
	if dungeons.get("elite_floors", [3, 6, 9]).map(func(x): return int(x)).has(floor_num):
		return "elite"
	return "fight"


## Which monster roster (monsters.json "floors" 1-6) a floor draws from.
func pool_floor(floor_num: int) -> int:
	return clampi(ceili(floor_num * 0.6), 1, 6)


## Monster level on `floor_num` of dungeon `id` (bosses get boss_level_bonus on top).
func monster_level_at(id: String, floor_num: int) -> int:
	var d := dungeon(id)
	return int(d.get("level_offset", 0)) + 1 + int(round((floor_num - 1) * float(dungeons.get("level_per_floor", 0.9))))
