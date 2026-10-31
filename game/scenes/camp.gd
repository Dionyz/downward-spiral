extends Control
## Between fights: see your state, edit rules, then fight. (Rest rooms and rewards come in milestone 5.)

var editor: RuleEditor


func _ready() -> void:
	var v := UI.screen(self)
	var p := Game.make_player()
	var L: Dictionary = Game.data.classes.get(Game.line, {})
	v.add_child(UI.label("Floor 1 · Fight %d of %d" % [Game.fight_index + 1, Game.fights_per_floor], 30, UI.ACCENT))
	v.add_child(UI.label("%s · level %d" % [str(L.get("display", Game.line)), Game.level], 24))
	v.add_child(UI.label("HP %d/%d   Mana %d/%d   Potions: %d HP, %d MP" % [p.hp, p.max_hp, p.mana, p.max_mana,
		Game.potions["hp"], Game.potions["mp"]], 20, UI.DIM))
	v.add_child(UI.label("Abilities: " + ", ".join(PackedStringArray(p.actives)), 20, UI.DIM))
	v.add_child(UI.label("Your character fights on its own. Rules let you tell it what to do first.", 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor = RuleEditor.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(editor)
	v.add_child(scroll)
	editor.setup(p.actives, Game.rules, Game.rule_slots())
	v.add_child(UI.button("Fight", _fight, 80))


func _fight() -> void:
	Game.rules = editor.get_rules()
	Game.goto("combat")
