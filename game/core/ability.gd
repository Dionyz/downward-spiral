class_name DSAbility
extends RefCounted
## Read-only helpers over ability definitions (abilities.json + overrides).


static func is_active(a: Dictionary) -> bool:
	return a.get("kind", "") == "active"


static func display_name(aname: String) -> String:
	return aname.capitalize()
