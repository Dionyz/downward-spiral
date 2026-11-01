class_name DSRules
extends RefCounted
## Combat priorities for classes and monsters: IF <condition> THEN <ability>, checked top to bottom.
## A rule whose ability is on cooldown, short of mana or otherwise unusable is skipped.
## Players don't edit these: each class has a built-in list (overrides/classes.json "ai").
##
## Rule shape: {"if": "<condition>", "value": <number|string>, "and": [<more conditions>], "then": "<ability ref>"}
## Ability refs may carry an argument after a colon ("name:arg").

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
const SELF_BUFFS := ["armor", "shield", "sanctuary", "haste", "berserk", "warcry", "envenomed"]


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


## Plain-English "when" for a rule, for the Skills screen: "when your HP is below 40%".
static func plain(r: Dictionary) -> String:
	var parts: Array = [_plain_one(str(r.get("if", "always")), r.get("value", null), false)]
	for e in r.get("and", []):
		parts.append(_plain_one(str(e.get("if", "always")), e.get("value", null), bool(e.get("not", false))))
	parts = parts.filter(func(p): return p != "")
	var stance := str(CombatSim.split_ref(str(r.get("then", "")))[1])
	var head := ("%s: " % stance.capitalize()) if stance != "" else ""
	if parts.is_empty():
		return head + "whenever it's ready"
	return head + "when " + " and ".join(PackedStringArray(parts))


static func _plain_one(cond: String, v, neg: bool) -> String:
	if typeof(v) == TYPE_FLOAT:
		v = int(v)
	var st := str(v).replace("stance_", "").replace("_", " ")
	match cond:
		"always":
			return ""
		"round_one":
			return "a fight starts"
		"hp_below":
			return ("your HP is at least %s%%" if neg else "your HP is below %s%%") % str(v)
		"mana_below":
			return ("you have at least %s%% mana" if neg else "your mana is below %s%%") % str(v)
		"enemy_hp_below":
			return "the enemy is below %s%% HP" % str(v)
		"enemies_at_least":
			return ("fewer than %s enemies are near" if neg else "%s or more enemies are near") % str(v)
		"enemy_has_status":
			return "the enemy is %s" % st
		"enemy_lacks_status":
			return "the enemy isn't %s" % st
		"missing_buff":
			return "you don't have %s" % st
	return cond
