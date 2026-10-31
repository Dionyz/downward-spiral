class_name DSRng
extends RefCounted
## Deterministic RNG for one run. Park-Miller "minimal standard" generator.
## Every product stays below 2^47, so the sequence is identical on every
## platform and Godot version. Never use the global RNG in core/.

const MODULUS := 2147483647  # 2^31 - 1
const MULTIPLIER := 48271

var state: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	var s := absi(seed_value) % MODULUS
	if s == 0:
		s = 1
	state = s


func next_int() -> int:
	state = (state * MULTIPLIER) % MODULUS
	return state


## Inclusive range, like the MUD's number_range(). If hi < lo, returns lo.
func number_range(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + (next_int() % (hi - lo + 1))


## 1..100 inclusive, like the MUD's number_percent().
func number_percent() -> int:
	return number_range(1, 100)


## n dice of `size` sides.
func dice(n: int, size: int) -> int:
	if n <= 0 or size <= 0:
		return 0
	var total := 0
	for _i in n:
		total += number_range(1, size)
	return total


## True with `pct` percent probability (pct in 0..100).
func chance(pct: float) -> bool:
	return number_percent() <= int(pct)


## MUD number_fuzzy(): value -1, +0 or +1, never below 1.
func number_fuzzy(value: int) -> int:
	match number_range(0, 3):
		0:
			value -= 1
		3:
			value += 1
	return maxi(1, value)


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[number_range(0, arr.size() - 1)]


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := number_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Weighted pick from {key: weight}. Keys are visited in sorted order so the
## result does not depend on dictionary insertion order.
func weighted_pick(weights: Dictionary):
	var keys := weights.keys()
	keys.sort()
	var total := 0
	for k in keys:
		total += int(weights[k])
	if total <= 0:
		return null
	var roll := number_range(1, total)
	for k in keys:
		roll -= int(weights[k])
		if roll <= 0:
			return k
	return keys[keys.size() - 1]


## Derive an independent child RNG (for example one per floor) without
## consuming more than one value from this one.
func fork() -> DSRng:
	return DSRng.new(next_int())


func save_state() -> int:
	return state


func load_state(s: int) -> void:
	state = s if s > 0 else 1
