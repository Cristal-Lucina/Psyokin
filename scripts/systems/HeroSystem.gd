extends Node
class_name HeroSystem

## HeroSystem — player identity + lightweight combat snapshot.
## Stores character-creation picks and exposes a save-friendly blob.

signal creation_applied

# --- Identity / Appearance ----------------------------------------------------

var hero_name: String = "Player"
var pronoun: String = "they"   # "she" | "he" | "they" | "rnd" (Any)
var body_id: String = "1"      # "1".."9"
var face_id: String = "1"      # "1".."9"
var eyes_id: String = "1"      # "1".."9"
var hair_id: String = "1"      # "1".."9"

var body_color: Color = Color(1.0, 0.9, 0.8)
var brow_color: Color = Color(0.2, 0.2, 0.2)
var eye_color: Color  = Color(0.4, 0.5, 0.6)
var hair_color: Color = Color(1, 1, 1)

# creation choices (for UI / reference)
var starting_stats: Array[StringName] = []
var starting_perk_id: String = ""

# --- Simple combat snapshot ---------------------------------------------------

var level: int = 1
var hp: int = 30
var hp_max: int = 30
var mp: int = 10
var mp_max: int = 10
var school_track: String = ""

# --- Save / Load --------------------------------------------------------------

func get_save_blob() -> Dictionary:
	# Colors are saved as HTML strings for stability.
	return {
		"identity": {
			"name": hero_name,
			"pronoun": pronoun,
			"body": body_id,
			"face": face_id,
			"eyes": eyes_id,
			"hair": hair_id,
			"body_color": body_color.to_html(),
			"brow_color": brow_color.to_html(),
			"eye_color": eye_color.to_html(),
			"hair_color": hair_color.to_html(),
		},
		"level": level,
		"hp": {"cur": hp, "max": hp_max},
		"mp": {"cur": mp, "max": mp_max},
		"school_track": school_track,
		"starting": {
			"stats": starting_stats,
			"perk_id": starting_perk_id
		}
	}

func apply_save_blob(blob: Dictionary) -> void:
	# identity
	var id_v: Variant = blob.get("identity", {})
	if typeof(id_v) == TYPE_DICTIONARY:
		var id: Dictionary = id_v

		hero_name = String(id.get("name", hero_name))
		pronoun   = String(id.get("pronoun", pronoun))
		body_id   = String(id.get("body", body_id))
		face_id   = String(id.get("face", face_id))
		eyes_id   = String(id.get("eyes", eyes_id))
		hair_id   = String(id.get("hair", hair_id))

		var bc_v: Variant = id.get("body_color", null)
		if typeof(bc_v) == TYPE_COLOR: body_color = bc_v as Color
		elif typeof(bc_v) == TYPE_STRING: body_color = Color(String(bc_v))

		var br_v: Variant = id.get("brow_color", null)
		if typeof(br_v) == TYPE_COLOR: brow_color = br_v as Color
		elif typeof(br_v) == TYPE_STRING: brow_color = Color(String(br_v))

		var ec_v: Variant = id.get("eye_color", null)
		if typeof(ec_v) == TYPE_COLOR: eye_color = ec_v as Color
		elif typeof(ec_v) == TYPE_STRING: eye_color = Color(String(ec_v))

		var hc_v: Variant = id.get("hair_color", null)
		if typeof(hc_v) == TYPE_COLOR: hair_color = hc_v as Color
		elif typeof(hc_v) == TYPE_STRING: hair_color = Color(String(hc_v))

	# core stats
	level = int(blob.get("level", level))

	var hp_v: Variant = blob.get("hp", {})
	if typeof(hp_v) == TYPE_DICTIONARY:
		var hp_d: Dictionary = hp_v
		hp     = int(hp_d.get("cur", hp))
		hp_max = int(hp_d.get("max", hp_max))

	var mp_v: Variant = blob.get("mp", {})
	if typeof(mp_v) == TYPE_DICTIONARY:
		var mp_d: Dictionary = mp_v
		mp     = int(mp_d.get("cur", mp))
		mp_max = int(mp_d.get("max", mp_max))

	school_track = String(blob.get("school_track", school_track))

	# starting picks
	var st_v: Variant = blob.get("starting", {})
	if typeof(st_v) == TYPE_DICTIONARY:
		var st: Dictionary = st_v

		starting_stats.clear()
		var arr_v: Variant = st.get("stats", [])
		if typeof(arr_v) == TYPE_ARRAY:
			for x in (arr_v as Array):
				starting_stats.append(StringName(String(x)))

		starting_perk_id = String(st.get("perk_id", starting_perk_id))

# --- Lifecycle helpers --------------------------------------------------------

func clear_all() -> void:
	hero_name = "Player"
	pronoun   = "they"
	body_id   = "1"
	face_id   = "1"
	eyes_id   = "1"
	hair_id   = "1"

	body_color = Color(1.0, 0.9, 0.8)
	brow_color = Color(0.2, 0.2, 0.2)
	eye_color  = Color(0.4, 0.5, 0.6)
	hair_color = Color(1, 1, 1)

	level = 1
	hp_max = 30
	hp = hp_max
	mp_max = 10
	mp = mp_max
	school_track = ""

	starting_stats.clear()
	starting_perk_id = ""

# Apply payload coming from CharacterCreation
func apply_creation(cfg: Dictionary) -> void:
	hero_name = String(cfg.get("name", hero_name))
	pronoun   = String(cfg.get("pronoun", pronoun))

	body_id   = String(cfg.get("body_id", body_id))
	face_id   = String(cfg.get("face_id", face_id))
	eyes_id   = String(cfg.get("eyes_id", eyes_id))
	hair_id   = String(cfg.get("hair_id", hair_id))

	var bc_v: Variant = cfg.get("body_color", null)
	if typeof(bc_v) == TYPE_COLOR: body_color = bc_v as Color

	var br_v: Variant = cfg.get("brow_color", null)
	if typeof(br_v) == TYPE_COLOR: brow_color = br_v as Color

	var ec_v: Variant = cfg.get("eye_color", null)
	if typeof(ec_v) == TYPE_COLOR: eye_color = ec_v as Color

	var hc_v: Variant = cfg.get("hair_color", null)
	if typeof(hc_v) == TYPE_COLOR: hair_color = hc_v as Color

	starting_stats.clear()
	var picks_v: Variant = cfg.get("starting_stats", [])
	if typeof(picks_v) == TYPE_ARRAY:
		for x in (picks_v as Array):
			starting_stats.append(StringName(String(x)))

	starting_perk_id = String(cfg.get("starting_perk_id", ""))

	creation_applied.emit()

# --- Dialogue helper ----------------------------------------------------------

func get_dialog_pronoun_token() -> String:
	# Return "RND" if Any was chosen; else "she"/"he"/"they".
	var k: String = pronoun.strip_edges().to_lower()
	return "RND" if k == "rnd" else k
