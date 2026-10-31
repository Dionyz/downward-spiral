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
const YOU := "You"


## Subject at the start of a sentence: "You" / "A goblin cutter".
static func subj(n: String) -> String:
	return n if n == YOU else n.left(1).to_upper() + n.substr(1)


## Object mid-sentence: "you" / "a goblin cutter".
static func obj(n: String) -> String:
	return "you" if n == YOU else n


## Possessive at sentence start: "Your" / "A goblin cutter's".
static func poss(n: String) -> String:
	return "Your" if n == YOU else subj(n) + "'s"


## Possessive mid-sentence: "your" / "a goblin cutter's".
static func poss_obj(n: String) -> String:
	return "your" if n == YOU else n + "'s"


## Verb agreeing with the subject: v("You", "dodge", "dodges").
static func v(n: String, second: String, third: String) -> String:
	return second if n == YOU else third


static func line(ev: Dictionary) -> String:
	var src: String = ev.get("src", "")
	var dst: String = ev.get("dst", "")
	match ev.get("t", ""):
		"fight_start":
			return "-- %s %s %s --" % [subj(src), v(src, "face", "faces"), ", ".join(PackedStringArray(ev.get("enemies", [])))]
		"round":
			return "[Round %d]" % int(ev.get("n", 0))
		"damage":
			var amt := int(ev.get("amount", 0))
			var crit := " (critical!)" if ev.get("crit", false) else ""
			if ev.get("dt", "") in ["poison", "bleed", "thorns"]:
				return "%s %s %d from %s." % [subj(dst), v(dst, "suffer", "suffers"), amt, ev.get("dt", "")]
			var who := poss(src) if src != "" else "Something's"
			return "%s %s %s %s. [%d]%s" % [who, attack_word(ev), verb_for(amt, int(ev.get("max_hp", 1))), obj(dst), amt, crit]
		"miss":
			return "%s %s misses %s." % [poss(src), ev.get("dt", "attack"), obj(dst)]
		"parry":
			return "%s %s %s blow." % [subj(src), v(src, "turn aside", "turns aside"), poss_obj(dst)]
		"dodge":
			if ev.get("how", "") == "sidestep":
				return "%s %s past %s swing." % [subj(src), v(src, "slip", "slips"), poss_obj(dst)]
			return "%s %s %s swing." % [subj(src), v(src, "dodge", "dodges"), poss_obj(dst)]
		"block":
			return "%s %s %s blow on a shield." % [subj(src), v(src, "catch", "catches"), poss_obj(dst)]
		"ability", "cast":
			var arg: String = ev.get("arg", "")
			var nm: String = ev.get("ability", "")
			if arg != "":
				nm = "%s (%s)" % [nm, arg]
			var verb := v(src, "cast", "casts") if ev.get("t") == "cast" else v(src, "use", "uses")
			if dst != "" and dst != src:
				return "%s %s %s on %s." % [subj(src), verb, nm, obj(dst)]
			return "%s %s %s." % [subj(src), verb, nm]
		"ability_miss":
			return "%s %s fails." % [poss(src), ev.get("ability", "")]
		"resist":
			return "%s %s off the %s." % [subj(src), v(src, "shrug", "shrugs"), ev.get("ability", "")]
		"status_applied":
			var st: String = ev.get("status", "")
			var w: String = STATUS_WORDS.get(st, "is affected by %s" % st)
			if dst == YOU:
				w = w.replace("is ", "are ").replace("falls", "fall").replace("speeds", "speed").replace("raises", "raise") \
					.replace("flies", "fly").replace("roars", "roar").replace("coats", "coat").replace("begins", "begin")
			return "%s %s." % [subj(dst), w]
		"status_expired":
			return "%s %s no longer %s." % [subj(src), v(src, "are", "is"), str(ev.get("status", "")).replace("_", " ")]
		"stance":
			return "%s %s into the %s dance." % [subj(src), v(src, "shift", "shifts"), ev.get("stance", "")]
		"heal":
			return "%s %s %d HP." % [subj(dst), v(dst, "recover", "recovers"), int(ev.get("amount", 0))]
		"mana":
			return "%s %s %d mana." % [subj(src), v(src, "recover", "recovers"), int(ev.get("amount", 0))]
		"stunned":
			return "%s %s, unable to act." % [subj(src), v(src, "reel", "reels")]
		"phase":
			return "** %s **" % str(ev.get("text", ""))
		"death":
			return "%s %s DEAD!" % [subj(src), v(src, "are", "is")]
		"pickup":
			return "%s %s %s%s." % [subj(YOU), "pick up", ev.get("name", "something"), " and equip it" if ev.get("equipped", false) else ""]
		"chest":
			return "You open a chest."
		"wake":
			return "%s wakes up." % subj(src)
		"encounter":
			return "-- Enemies close in --"
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
