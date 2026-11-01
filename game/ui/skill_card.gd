class_name SkillCard
extends PanelContainer
## One skill on the Skills screen. Drag it onto another card to move it there.

signal moved(from: int, to: int)

var index := 0


func _get_drag_data(_pos: Vector2):
	var preview := Label.new()
	preview.text = "  ↕ " + str(get_meta("skill_name", ""))
	preview.add_theme_font_size_override("font_size", 22)
	preview.add_theme_color_override("font_color", UI.ACCENT)
	set_drag_preview(preview)
	modulate = Color(1, 1, 1, 0.5)
	return {"skill_index": index}


func _can_drop_data(_pos: Vector2, d) -> bool:
	return typeof(d) == TYPE_DICTIONARY and d.has("skill_index")


func _drop_data(_pos: Vector2, d) -> void:
	moved.emit(int(d["skill_index"]), index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		modulate = Color.WHITE
