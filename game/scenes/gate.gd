extends Control
## The Spiral Gate: pick where to descend. Dungeons open one after another (beat a dungeon's
## floor-10 boss to open the next). A cleared dungeon can be replayed as The Abyss: 20 floors,
## better boons and mythic items below floor 10, and a trophy for reaching the bottom.

func _ready() -> void:
	var v := UI.screen(self)
	v.add_child(UI.label("The Spiral Gate", 34, UI.ACCENT))
	var ch := Game.character()
	v.add_child(UI.label("Descending as %s." % str(ch.get("name", "?")), 18, UI.DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	v.add_child(scroll)
	var floors := int(Game.data.dungeons.get("floors", 10))
	var abyss_floors := int(Game.data.dungeons.get("abyss_floors", 20))
	var dl := Game.data.dungeon_list()
	for i in dl.size():
		var d: Dictionary = dl[i]
		var id: String = d["id"]
		var open := DSAccount.dungeon_unlocked(Game.data, Game.account, id)
		var cleared: bool = Game.account.get("cleared", []).has(id)
		var trophy: bool = Game.account.get("abyss_cleared", []).has(id)
		var card := PanelContainer.new()
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var t := UI.label(str(d["name"]), 26, UI.ACCENT if open else UI.DIM, false)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var badge: Control = null
		if trophy:
			badge = UI.tag("town_trophy", "Abyss cleared", 16, Color("#ffd24a"))
		elif cleared:
			badge = UI.tag("ui_check", "Cleared", 16, Color("#7fc8a9"))
		if Art.has("ui/banner_" + id):
			# Banner (96 x 48 at x2) beside the name and badge.
			var ban := Art.rect("ui/banner_" + id, 0)
			ban.custom_minimum_size = Vector2(192, 96)
			head.add_child(ban)
			var hv := VBoxContainer.new()
			hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hv.alignment = BoxContainer.ALIGNMENT_CENTER
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hv.add_child(t)
			if badge != null:
				hv.add_child(badge)
			head.add_child(hv)
		else:
			head.add_child(t)
			if badge != null:
				head.add_child(badge)
		cv.add_child(head)
		var lo := Game.data.monster_level_at(id, 1)
		var hi := Game.data.monster_level_at(id, floors)
		cv.add_child(UI.label("%d floors · monster level %d to %d · boss on floor %d" % [floors, lo, hi, floors], 16, UI.DIM))
		if not open:
			cv.add_child(UI.label("Clear %s to open." % str(dl[i - 1]["name"]), 17, UI.WARN))
		else:
			var dd: String = id
			cv.add_child(UI.button("Descend (%d floors)" % floors, func(): _go(dd, false), 60))
			if cleared:
				var ab := UI.button("Enter the Abyss (%d floors)" % abyss_floors, func(): _go(dd, true), 60)
				ab.add_theme_color_override("font_color", Color("#ff3d6e"))
				if Art.has("ui/banner_abyss"):
					var arow := HBoxContainer.new()
					arow.add_theme_constant_override("separation", 8)
					var aban := Art.rect("ui/banner_abyss", 0)
					aban.custom_minimum_size = Vector2(96, 48)
					aban.size_flags_vertical = Control.SIZE_SHRINK_CENTER
					arow.add_child(aban)
					ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					arow.add_child(ab)
					cv.add_child(arow)
				else:
					cv.add_child(ab)
				cv.add_child(Tip.attach(UI.label("Floors 11-%d: better boons, mythic items, and a trophy at the bottom." % abyss_floors, 15, Color("#ff3d6e")), "abyss"))
			else:
				cv.add_child(UI.label("Clear it to unlock its Abyss (floors 11-%d)." % abyss_floors, 15, UI.DIM))
		list.add_child(card)
	v.add_child(UI.button("Back to town", func(): Game.goto("town"), 56))


func _go(id: String, abyss: bool) -> void:
	var args := OS.get_cmdline_user_args()
	var si := args.find("--seed")
	Game.new_run(int(args[si + 1]) if si >= 0 and si + 1 < args.size() else 0, id, abyss)
	if Game.run == null:
		return
	Game.goto("dungeon")
