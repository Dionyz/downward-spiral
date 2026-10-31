class_name DSRules
extends RefCounted
## Combat priorities for classes and monsters: IF <condition> THEN <ability>, checked top to bottom.
## A rule whose ability is on cooldown, short of mana or otherwise unusable is skipped.
## Players don't edit these: each class has a built-in list (overrides/classes.json "ai").
##
## Rule shape: {"if": "<condition>", "value": <number|string>, "and": [<more conditions>], "then": "<ability ref>"}
## Ability refs may carry an argument: "dance:mist".

const CONDITIONS := {
	"always": "Always",
	"round_one": "Round 1 of the fight",
	"hp_below": "My HP below X%",
	"mana_below": "My mana below X%",
	"enemy_hp_below": "Enemy HP below X%",
	"enemies_at_least": "At least N enemies standing",
	"enemy_has_status": "Enemy has status",
	"enemy_lacks_status": "Enemy doesn't have status",
	"missing_buff": "I don't have buff",
}

## Statuses offered in the editor for "enemy has status" and "I don't have buff".
const ENEMY_STATUSES := ["blind", "slowed", "poisoned", "asleep", "stunned", "knocked_down"]
const SELF_BUFFS := ["armor", "shield", "sanctuary", "haste", "berserk", "warcry", "envenomed",
	"stance_mist", "stance_storm", "stance_cobra", "stance_predator"]


## Returns {"ability": ref, "target": Combatant, "rule": index} or {} if no rule fires.
func choose(sim, me, rules: Array, foes: Array) -> Dictionary:
	var living := foes.filter(func(f): return f.is_alive())
	if living.is_empty():
		return {}
	for i in rules.size():
		var r: Dictionary = rules[i]
		var target = _condition_target(sim, me, r, living)
		if target == null:
			continue
		# Extra conditions that must also hold: [{"if", "value", "not"?}]. "not": true inverts one.
		var ok := true
		for extra in r.get("and", []):
			var hit = _condition_target(sim, me, extra, living)
			if (hit != null) == bool(extra.get("not", false)):
				ok = false
				break
		if not ok:
			continue
		var ref: String = r.get("then", "")
		if ref == "":
			continue
		var a: Dictionary = sim._ability_def(me, CombatSim.split_ref(ref)[0])
		var tkind: String = a.get("target", "enemy")
		var use_target = me if tkind == "self" else target
		if sim.can_use(me, ref, use_target):
			return {"ability": ref, "target": use_target, "rule": i}
	return {}


## If the rule's condition holds, return the enemy it refers to; else null.
func _condition_target(sim, me, r: Dictionary, living: Array):
	var cond: String = r.get("if", "always")
	var v = r.get("value", 0)
	var first = living[0]
	match cond:
		"always":
			return first
		"round_one":
			return first if sim.round_num == 1 else null
		"hp_below":
			return first if me.hp_pct() < float(v) else null
		"mana_below":
			return first if me.max_mana > 0 and me.mana_pct() < float(v) else null
		"enemy_hp_below":
			for f in living:
				if f.hp_pct() < float(v):
					return f
			return null
		"enemies_at_least":
			return first if living.size() >= int(v) else null
		"enemy_has_status":
			for f in living:
				if f.has_status(str(v)):
					return f
			return null
		"enemy_lacks_status":
			for f in living:
				if not f.has_status(str(v)):
					return f
			return null
		"missing_buff":
			return first if not me.has_status(str(v)) else null
		"chance":
			# Monster-only: fire on a percent roll (keeps enemy behaviour varied but seeded).
			return first if sim.rng.number_percent() <= int(v) else null
		"every_n":
			# Monster-only: fire on rounds divisible by N.
			return first if int(v) > 0 and sim.round_num % int(v) == 0 else null
	return null


static func describe(r: Dictionary) -> String:
	var cond: String = r.get("if", "always")
	var label: String = CONDITIONS.get(cond, cond)
	var v = r.get("value", null)
	var lhs := label
	if label.find("X") >= 0 and v != null:
		lhs = label.replace("X", str(v))
	elif label.find(" N ") >= 0 and v != null:
		lhs = label.replace(" N ", " %s " % str(v))
	elif v != null and cond in ["enemy_has_status", "enemy_lacks_status", "missing_buff"]:
		lhs = "%s: %s" % [label, str(v)]
	return "IF %s THEN %s" % [lhs, str(r.get("then", "?"))]
