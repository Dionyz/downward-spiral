class_name DSStats
extends RefCounted
## Shared formulas that map MUD numbers onto a short run.

const SIZES := ["tiny", "small", "medium", "large", "huge", "giant"]


## MUD-scale level used inside ported formulas (bash damage, spell dice...).
static func mud_level(run_level: int, balance: Dictionary) -> int:
	return run_level * int(balance.get("level_scale", 10))


## Spec: 40% when unlocked, +10% per level after, cap 95%. Bonus (boons, gear) on top, cap 100.
static func proficiency(unlock_level: int, current_level: int, balance: Dictionary, bonus: int = 0) -> int:
	if current_level < unlock_level:
		return 0
	var p: Dictionary = balance.get("proficiency", {})
	var base := int(p.get("start", 40)) + int(p.get("per_level", 10)) * (current_level - unlock_level)
	base = mini(base, int(p.get("cap", 95)))
	return mini(base + bonus, int(p.get("hard_cap", 100)))


## Weapon skill (sword, dagger...). See DECISIONS.md D-008.
static func weapon_proficiency(current_level: int, balance: Dictionary, bonus: int = 0) -> int:
	var p: Dictionary = balance.get("weapon_proficiency", {})
	var base := int(p.get("start", 75)) + int(p.get("per_level", 2)) * (current_level - 1)
	base = mini(base, int(p.get("cap", 95)))
	return mini(base + bonus, 100)


## MUD beats (pulses of lockout) -> cooldown in rounds. See DECISIONS.md D-006.
static func cooldown_rounds(beats: int, balance: Dictionary) -> int:
	var div := float(balance.get("cooldown_divisor", 4))
	return maxi(int(balance.get("min_cooldown", 1)), ceili(float(beats) / div))


## MUD min_mana -> run mana cost.
static func mana_cost(min_mana: int, balance: Dictionary) -> int:
	if min_mana <= 0:
		return 0
	return maxi(1, roundi(float(min_mana) * float(balance.get("mana_cost_scale", 0.25))))


static func size_index(size: String) -> int:
	var i := SIZES.find(size)
	return 2 if i < 0 else i


## Integer helpers that match C integer division (truncate toward zero).
static func idiv(a: int, b: int) -> int:
	if b == 0:
		return 0
	@warning_ignore("integer_division")
	return a / b


static func urange(lo: int, v: int, hi: int) -> int:
	return clampi(v, lo, hi)
