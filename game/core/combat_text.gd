class_name CombatText
extends RefCounted
## Turns simulator events into MUD-flavored log lines. All wording is original to
## Downward Spiral (license note: never copy the MUD's message text).

## Damage verbs by damage dealt as a share of the victim's max HP.
const TIERS := [
	[0.0, "nicks"], [0.02, "scrapes"], [0.04, "cuts"], [0.07, "bites into"], [0.10, "carves"],
	[0.14, "hacks"], [0.19, "rends"], [0.25, "*sunders*"], [0.33, "**BREAKS**"], [0.45, "*** RUINS ***"],
	[0.60, "<<< ANNIHILATES >>>"],
]

const STATUS_WORDS := {
	"blind": "is blinded", "slowed": "is slowed", "poisoned": "is poisoned", "asleep": "falls asleep",
	"stunned": "is stunned", "knocked_down": "is knocked to the ground", "dazed": "is dazed",
	"haste": "speeds up", "sanctuary": "is wrapped in a pale ward", "armor": "is warded",
	"shield": "raises a shimmering barrier", "berserk": "flies into a berserk rage", "warcry": "roars a war cry",
	"envenomed": "coats a blade in venom", "bleeding": "begins to bleed",
}

const TAG_HINT := {
	"interrupt": "INTERRUPT it", "brace": "BRACE for it", "evade": "EVADE it", "outlast": "OUTLAST it",
}


static func verb_for(amount: int, max_hp: int) -> String:
	var share := float(amount) / float(maxi(1, max_hp))
	var v: String = TIERS[0][1]
	for t in TIERS:
		if share >= float(t[0]):
			v = t[1]
	return v


static func attack_word(ev: Dictionary) -> String:
	var dt: String = ev.get("dt", "hit")
	if dt == "hit":
		return "strike"
	return dt


## One line of log text for an event, or "" for events the log skips.
static func line(ev: Dictionary) -> String:
	var src: String = ev.get("src", "")
	var dst: String = ev.get("dst", "")
	match ev.get("t", ""):
		"fight_start":
			return "-- %s faces %s --" % [src, ", ".join(PackedStringArray(ev.get("enemies", [])))]
		"round":
			return "[Round %d]" % int(ev.get("n", 0))
		"damage":
			var amt := int(ev.get("amount", 0))
			var who := src if src != "" else "Something"
			var crit := " (critical!)" if ev.get("crit", false) else ""
			if ev.get("dt", "") in ["poison", "bleed"]:
				return "%s suffers %d from %s." % [dst, amt, ev.get("dt", "")]
			return "%s's %s %s %s. [%d]%s" % [who, attack_word(ev), verb_for(amt, int(ev.get("max_hp", 1))), dst, amt, crit]
		"miss":
			if ev.has("evaded"):
				return "%s slips clear of %s's attack (%s)." % [dst, src, ev.get("evaded", "")]
			return "%s's %s misses %s." % [src, ev.get("dt", "attack"), dst]
		"parry":
			return "%s turns aside %s's blow." % [src, dst]
		"dodge":
			return "%s sidesteps %s's swing." % [src, dst]
		"block":
			return "%s catches %s's blow on a shield." % [src, dst]
		"ability", "cast":
			var arg: String = ev.get("arg", "")
			var nm: String = ev.get("ability", "")
			if arg != "":
				nm = "%s (%s)" % [nm, arg]
			var verb := "casts" if ev.get("t") == "cast" else "uses"
			if dst != "" and dst != src:
				return "%s %s %s on %s." % [src, verb, nm, dst]
			return "%s %s %s." % [src, verb, nm]
		"ability_miss":
			return "%s's %s fails." % [src, ev.get("ability", "")]
		"resist":
			return "%s shrugs off the %s." % [src, ev.get("ability", "")]
		"status_applied":
			var w: String = STATUS_WORDS.get(ev.get("status", ""), "is affected by %s" % ev.get("status", ""))
			return "%s %s." % [dst, w]
		"status_expired":
			return "%s is no longer %s." % [src, ev.get("status", "")]
		"stance":
			return "%s shifts into the %s dance." % [src, ev.get("stance", "")]
		"heal":
			return "%s recovers %d HP." % [dst, int(ev.get("amount", 0))]
		"mana":
			return "%s recovers %d mana." % [src, int(ev.get("amount", 0))]
		"stunned":
			return "%s reels, unable to act." % src
		"telegraph":
			return "!! %s readies %s -- %s! !!" % [src, ev.get("name", ""), TAG_HINT.get(ev.get("tag", ""), "")]
		"telegraph_interrupted":
			return "%s's %s is cut short!" % [src, ev.get("attack", "attack")]
		"telegraph_strike":
			var how: String = ev.get("answered", "")
			if how != "":
				return "%s unleashes %s -- answered by %s." % [src, ev.get("name", ""), how]
			return "%s unleashes %s!" % [src, ev.get("name", "")]
		"backlash":
			return "The %s arcs back into %s!" % [ev.get("ability", "spell"), src]
		"death":
			return "%s is DEAD!" % src
		"fight_end":
			match ev.get("result", ""):
				"win":
					return "-- Victory --"
				"loss":
					return "-- You have fallen --"
				_:
					return "-- The fight drags on too long --"
	return ""


static func render(events: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for ev in events:
		var l := line(ev)
		if l != "":
			out.append(l)
	return out
