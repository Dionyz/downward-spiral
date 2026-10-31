class_name DSAbility
extends RefCounted
## Read-only helpers over ability definitions (abilities.json + overrides).

const TAGS := ["interrupt", "brace", "evade", "outlast"]


## Telegraph tags an ability answers. Includes passives (shield block) and stance variants.
static func answers(a: Dictionary) -> Array:
	var out: Array = []
	for t in a.get("answers", []):
		if not out.has(t):
			out.append(t)
	var abs_: Dictionary = a.get("answers_by_stance", {})
	for k in abs_.keys():
		for t in abs_[k]:
			if not out.has(t):
				out.append(t)
	return out


## Which telegraph tags a class line can answer at `tier`/`level`, from data alone.
## Passives count only if the line's kit gives the needed gear (shield block needs a shield).
static func coverage(data: DSData, line: String, tier: int, level: int) -> Dictionary:
	var cov := {}
	for t in TAGS:
		cov[t] = []
	var L: Dictionary = data.classes.get(line, {})
	for n in data.kit_abilities(line, tier, level):
		var a := data.ability(n)
		if n == "shield block" and L.get("offhand", null) != "shield":
			continue
		for t in answers(a):
			if cov.has(t):
				cov[t].append(n)
	# Outlast is also answered by "burst to kill first" and by healing potions; v1 counts only abilities.
	return cov


static func is_active(a: Dictionary) -> bool:
	return a.get("kind", "") == "active"


static func display_name(aname: String) -> String:
	return aname.capitalize()
