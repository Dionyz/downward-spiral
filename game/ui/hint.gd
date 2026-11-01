class_name Hint
extends RefCounted
## One-time tutorial prompts. Each hint shows once per install (settings.hints_seen) as a dim
## overlay with a short card and a "Got it" button. `on_close` runs when it's dismissed (or
## immediately if the hint was already seen), so callers can pause timers meanwhile.

const TEXT := {
	"welcome": ["Welcome to the Spiral", "Ten floors down, a boss at the bottom. Beat it to open the next dungeon, and that dungeon's 20-floor Abyss. Your character explores and fights on its own; you pick its boons and drink its potions.

Make a character: every class and race is open. You can have up to 10."],
	"dungeon": ["The floor", "Each floor is a fresh maze. Your character explores it on its own, picks up loot, opens chests and fights whatever wakes up, turn by turn, using its whole kit.\n\nYour job: drink potions (Potion), pick boons, and decide when to leave (Extract). Character shows your stats, gear, boons and skills. Speed makes turns faster. Tap the log under the map for the blow-by-blow."],
	"boon": ["Boons", "Level-ups and elite kills each grant a boon: pick one of three. Boons last the rest of the run, and taking the same one again stacks it.\n\nThe colored border is the rarity: rarer copies have bigger numbers. Each boon belongs to a family; owning 2, 4 or 6 different boons of one family adds a bonus on top.\n\nSkip, Reroll and Banish are limited per run. Buy more in town at the Trainer."],
	"event": ["Something strange", "Events are gambles. Read carefully: some choices cost HP or gold, some pay off."],
	"floor_end": ["Descend or extract", "Press Extract any time to head back out with your gold and everything you carry. Dying loses all of it, including the gear you brought."],
	# In-run tutorial: each shows the first time its moment comes up, and pauses the game.
	"low_hp": ["You're in danger!", "Your health is under 30%. The game is paused and slowed to 1x.\n\nDrink a potion now (Potion button), or consider getting out: tap Extract and your character heads back to this floor's entrance to leave with everything it carries.\n\nIf you die, you lose all the gold and gear you have on you."],
	"combat": ["A fight", "Something woke up. Fights play out on their own: your character attacks every turn and uses its skills in the order set under Character, then Skills.\n\nNumbers float over whoever got hit; yellow ones are critical hits. Keep an eye on your health bar and drink a potion before it gets low."],
	"loot": ["Loot", "Gear you find goes into your bag; it isn't worn until you equip it. Open Character, then Gear, to compare and equip.\n\nWhen the Character button glows green, a straight upgrade is waiting in your bag.\n\nEverything you carry is lost if you die. Extract to bring it home."],
	"elite": ["An elite", "Monsters with an orange ring are elites: tougher versions of normal monsters: more health, harder hits, better loot and more XP. Killing one grants a boon pick."],
	"boss": ["The guardian", "This floor has a boss (red ring). The stairs stay sealed until it dies. It hits harder and has phases. Go in with full health and potions to spare, or extract with what you have."],
	"sleeper": ["Sleeping monsters", "Monsters drawn darker are asleep. Your character hunts them for XP and loot, and gets the first hit. While extracting, it leaves them alone.\n\nWalk too close to a sleeper and it may wake up."],
	"shield": ["Shield", "The pale blue part of your health bar is a shield. It soaks up damage before your health does. It comes from boons and resets when a fight ends."],
	"no_potions": ["Out of potions", "That was your last health potion. More drop from monsters and chests, and campfires heal you between fights.\n\nWithout potions, a bad fight can end the run. Think about extracting while you're ahead."],
	"low_mana": ["Low mana", "Spells cost mana, and yours is running low. Mana comes back a little every turn in a fight; tap Mana to drink a mana potion.\n\nWith no mana, your character falls back on melee."],
	"stunned": ["Status effects", "You can't act while stunned, knocked down or asleep. These effects get less reliable each time they hit the same target within a few turns, so neither you nor the monsters can be locked down forever."],
	"campfire": ["Campfire", "Your character rests at campfires when hurt, healing before it moves on. Each campfire works once."],
	"shrine": ["Shrine", "Your character prays at shrines on its own. Each one grants a small bonus for the rest of the run."],
	"extract": ["Extracting", "Your character is walking back to this floor's entrance. Tap Cancel Extract to keep exploring instead.\n\nAt the entrance you can leave, but the way out may be watched: there's a chance you'll have to fight through an ambush first."],
	"character": ["Your character", "Everything that decides how you fight: health, damage, armor, dodge and parry chances, boon bonuses, and recovery. Values come straight from the combat rules.\n\nGear, Boons and Skills open from here."],
	"run_end": ["Back to town", "Gold and loot you bring home stay with you. Every run, win or lose, also adds to your class mastery, which unlocks that class's skills.

In town, equip characters from the shared stash, buy and sell gear, and spend gold on power-ups at the Trainer."],
	"town": ["The town", "Between runs you're here. The Stash holds loot every character shares. The Quartermaster sells gear, the Trainer sells power-ups, and the Innkeeper keeps your characters. The Spiral Gate starts a run.

Gear your character wears goes down with it: die, and it's gone."],
}


static var _open := {}


static func seen(id: String) -> bool:
	return Game.settings.get("hints_seen", []).has(id)


## Show hint `id` over `parent` unless already seen. Returns true if shown.
static func show(parent: Control, id: String, on_close: Callable = Callable()) -> bool:
	if _open.has(id):
		return false
	if seen(id) or not TEXT.has(id):
		if on_close.is_valid():
			on_close.call()
		return false
	_open[id] = true
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Above everything the screen draws with a raised z (map tokens, the boon overlay):
	# input goes to the last child, so drawing must agree or the tip blocks clicks invisibly.
	layer.z_index = 100
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 20)
	m.add_theme_constant_override("margin_bottom", 40)
	layer.add_child(m)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	m.add_child(col)
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#221f2b")
	st.border_color = UI.ACCENT
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", st)
	col.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(UI.label(TEXT[id][0], 28, UI.ACCENT))
	v.add_child(UI.label(TEXT[id][1], 20))
	var close := func():
		var hs: Array = Game.settings.get("hints_seen", [])
		if not hs.has(id):
			hs.append(id)
		Game.settings["hints_seen"] = hs
		Game.save_settings()
		_open.erase(id)
		if is_instance_valid(layer):
			layer.queue_free()
		if on_close.is_valid():
			on_close.call()
	v.add_child(UI.button("Got it", close, 60))
	if Game.autoplay != "":
		Game.auto_next("hint_" + id, close, 0.1)
	return true
