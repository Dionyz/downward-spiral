extends RefCounted
## Shared test fixtures.

const DATA_DIR := "res://game/data"


static func data() -> DSData:
	return DSData.load_dir(DATA_DIR)


## A bare combatant with no gear or skills unless given.
static func dummy(nm: String = "dummy", is_player: bool = false) -> Combatant:
	var c := Combatant.new()
	c.name = nm
	c.is_player = is_player
	c.max_hp = 1000
	c.hp = 1000
	c.mud_level = 10
	c.level = 1
	return c


static func sword(mn: int = 10, mx: int = 20, lvl: int = 10, flags: Array = []) -> Dictionary:
	return {"type": "sword", "min": mn, "max": mx, "level": lvl, "flags": flags, "dam_type": "slash"}


static func dagger(mn: int = 10, mx: int = 20, lvl: int = 10) -> Dictionary:
	return {"type": "dagger", "min": mn, "max": mx, "level": lvl, "flags": [], "dam_type": "pierce"}
