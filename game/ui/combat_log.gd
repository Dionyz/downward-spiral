class_name CombatLog
extends RichTextLabel
## Scrolling MUD-style combat log. Feed it simulator events.

const COLORS := {
	"round": "#6f6a7a", "damage": "#e6e1d6", "parry": "#8fb3d9", "dodge": "#8fb3d9", "block": "#8fb3d9",
	"miss": "#8d8798", "ability": "#d6a64f", "cast": "#9d7cf2", "ability_miss": "#8d8798", "resist": "#8d8798",
	"status_applied": "#7fc8a9", "status_expired": "#6f6a7a", "heal": "#5fd35f",
	"mana": "#5f9fd3", "stunned": "#e0b050", "phase": "#ff7a3d", "death": "#ff4040", "fight_start": "#d6a64f", "fight_end": "#d6a64f",
}

var player_name := "You"
var max_lines := 400


func _ready() -> void:
	bbcode_enabled = true
	scroll_following = true
	selection_enabled = false
	fit_content = false
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_font_size_override("normal_font_size", 20)
	add_theme_font_size_override("bold_font_size", 20)


func add_events(events: Array) -> void:
	for ev in events:
		var text := CombatText.line(ev)
		if text == "":
			continue
		var col: String = COLORS.get(ev.get("t", ""), "#e6e1d6")
		# Damage to the player reads red, damage by the player reads bright.
		if ev.get("t") == "damage" and ev.get("dst") == player_name:
			col = "#ff8c7a"
		var t := text.replace("[", "[lb]")
		if ev.get("t") in ["death", "fight_end", "phase"]:
			append_text("[b][color=%s]%s[/color][/b]\n" % [col, t])
		else:
			append_text("[color=%s]%s[/color]\n" % [col, t])
	if get_line_count() > max_lines:
		# Trim from the top by rebuilding; cheap at these sizes.
		var keep := get_parsed_text().split("\n")
		clear()
		for l in keep.slice(keep.size() - max_lines):
			append_text(str(l).replace("[", "[lb]") + "\n")
