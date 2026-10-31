class_name RuleEditor
extends VBoxContainer
## Two-column rule editor: IF <condition> [value] THEN <ability>. One row per rule slot.

signal changed

const PCT_CONDS := ["hp_below", "mana_below", "enemy_hp_below"]
const PCT_VALUES := [10, 20, 30, 40, 50, 60, 70, 80, 90]
const STANCES := ["mist", "storm", "cobra", "predator"]

var _rows: Array = []   # [{cond: OptionButton, value: OptionButton, then: OptionButton}]
var _abilities: Array = []
var _cond_keys: Array = []


## `actives`: equipped ability names. `rules`: current rules. `slots`: rows to show.
func setup(actives: Array, rules: Array, slots: int) -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_abilities = ["(none)"]
	for a in actives:
		if a == "dance":
			for s in STANCES:
				_abilities.append("dance:" + s)
		else:
			_abilities.append(a)
	_cond_keys = DSRules.CONDITIONS.keys()
	add_theme_constant_override("separation", 10)
	for i in slots:
		var r: Dictionary = rules[i] if i < rules.size() else {}
		_add_row(i, r)


func _add_row(i: int, r: Dictionary) -> void:
	var box := VBoxContainer.new()
	var head := UI.label("Rule %d" % (i + 1), 18, UI.DIM)
	box.add_child(head)
	var top := HBoxContainer.new()
	var lif := UI.label("IF", 22, UI.ACCENT, false)
	lif.custom_minimum_size = Vector2(64, 0)
	top.add_child(lif)
	var cond := OptionButton.new()
	cond.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cond.custom_minimum_size = Vector2(0, 56)
	for k in _cond_keys:
		cond.add_item(DSRules.CONDITIONS[k])
	var ci := _cond_keys.find(r.get("if", "always"))
	cond.select(maxi(0, ci))
	top.add_child(cond)
	var val := OptionButton.new()
	val.custom_minimum_size = Vector2(150, 56)
	top.add_child(val)
	box.add_child(top)
	var bottom := HBoxContainer.new()
	var lthen := UI.label("THEN", 22, UI.ACCENT, false)
	lthen.custom_minimum_size = Vector2(64, 0)
	bottom.add_child(lthen)
	var then := OptionButton.new()
	then.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	then.custom_minimum_size = Vector2(0, 56)
	for a in _abilities:
		then.add_item(a)
	var ti := _abilities.find(r.get("then", "(none)"))
	then.select(maxi(0, ti))
	bottom.add_child(then)
	box.add_child(bottom)
	add_child(box)
	var row := {"cond": cond, "value": val, "then": then}
	_rows.append(row)
	_fill_values(row, r.get("value", null))
	cond.item_selected.connect(func(_idx):
		_fill_values(row, null)
		changed.emit()
	)
	val.item_selected.connect(func(_idx): changed.emit())
	then.item_selected.connect(func(_idx): changed.emit())


func _fill_values(row: Dictionary, current) -> void:
	var val: OptionButton = row["value"]
	val.clear()
	var key: String = _cond_keys[row["cond"].selected]
	var opts: Array = []
	if key in PCT_CONDS:
		for p in PCT_VALUES:
			opts.append("%d%%" % p)
	elif key == "enemies_at_least":
		opts = ["2", "3", "4"]
	elif key in ["enemy_has_status", "enemy_lacks_status"]:
		opts = DSRules.ENEMY_STATUSES.duplicate()
	elif key == "missing_buff":
		opts = DSRules.SELF_BUFFS.duplicate()
	val.visible = not opts.is_empty()
	for o in opts:
		val.add_item(str(o))
	if opts.is_empty():
		return
	var idx := 0
	if current != null:
		var want := ("%d%%" % int(current)) if key in PCT_CONDS else str(int(current) if key == "enemies_at_least" else current)
		idx = maxi(0, opts.find(want))
	elif key in PCT_CONDS:
		idx = 3
	val.select(idx)


func get_rules() -> Array:
	var out: Array = []
	for row in _rows:
		var then: String = _abilities[row["then"].selected]
		if then == "(none)":
			continue
		var key: String = _cond_keys[row["cond"].selected]
		var r := {"if": key, "then": then}
		var val: OptionButton = row["value"]
		if val.visible and val.selected >= 0:
			var txt := val.get_item_text(val.selected)
			r["value"] = int(txt.trim_suffix("%")) if key in PCT_CONDS or key == "enemies_at_least" else txt
		out.append(r)
	return out
