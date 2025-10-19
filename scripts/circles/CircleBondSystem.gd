extends Node
class_name CircleBondSystem

signal data_reloaded
signal bxp_changed(bond_id: String, total_bxp: int)
signal level_changed(bond_id: String, layer: int)
signal known_changed(bond_id: String, is_known: bool)

# ───────── CSV locations (first path that exists wins) ─────────
const BONDS_PATHS  := [
	"res://data/circles/circle_bonds.csv",
	"res://data/circles/circle-bonds.csv",
	"res://data/circle_bonds.csv",
	"res://data/circles_bonds.csv"
]
const EVENTS_PATHS := [
	"res://data/circles/circles_events.csv",
	"res://data/circles/circle_events.csv",
	"res://data/circles/events.csv"
]

# ───────── Runtime state ─────────
# Authoring defs from CSV
var _defs: Dictionary = {}                 # id -> { bond_name, love_interest, likes[], dislikes[], poly_connects[], rewards, … }
var _events_by_actor: Dictionary = {}      # actor_id -> Array[Dictionary] (events rows)

# Player state
var _bxp: Dictionary = {}                  # id -> int (0..8)
var _known: Dictionary = {}                # id -> bool (met, discovered, etc.)
var _discovered_likes: Dictionary = {}     # id -> PackedStringArray
var _discovered_dislikes: Dictionary = {}  # id -> PackedStringArray

# Tunables
const MAX_LAYER := 8      # 0..8 (0/1 Acquaintance, 2/3 Outer, 4/5 Middle, 6/7 Inner, 8 Core)
const MAX_BXP   := 8

func _ready() -> void:
	reload()

# ────────────────────────────────────────────────────────────────────────────────
# Loading / parsing
# ────────────────────────────────────────────────────────────────────────────────
func reload() -> void:
	_defs.clear()
	_events_by_actor.clear()

	var bonds_path: String = _first_existing(BONDS_PATHS)
	var events_path: String = _first_existing(EVENTS_PATHS)

	if bonds_path != "":
		var rows: Array = _load_csv_rows(bonds_path)
		for r_v in rows:
			if typeof(r_v) != TYPE_DICTIONARY:
				continue
			var r: Dictionary = r_v
			var id: String = _s(r.get("actor_id", ""))
			if id == "":
				continue
			var bond_name: String = _s(r.get("bond_name", id.capitalize()))
			var love: bool = _b(r.get("love_interest", "0"))
			var poly: PackedStringArray = _list(r.get("poly_connects", ""))
			var likes: PackedStringArray = _list(r.get("gift_likes", ""))
			var dislikes: PackedStringArray = _list(r.get("gift_dislikes", ""))
			var desc: String = _s(r.get("bond_description", ""))
			var story: String = _s(r.get("story_points", ""))

			var rewards: Dictionary = {
				"outer":  _s(r.get("reward_outer", "")),
				"middle": _s(r.get("reward_middle", "")),
				"inner":  _s(r.get("reward_inner", "")),
				"core":   _s(r.get("reward_core", ""))
			}

			_defs[id] = {
				"id": id,
				"bond_name": bond_name,
				"love_interest": love,
				"poly_connects": poly,
				"gift_likes": likes,
				"gift_dislikes": dislikes,
				"bond_description": desc,
				"story_points": story,
				"rewards": rewards,
				"burst_unlocked": _b(r.get("burst_unlocked", "0")),
			}
			# Initialize discovery lists if missing
			if not _discovered_likes.has(id): _discovered_likes[id] = PackedStringArray()
			if not _discovered_dislikes.has(id): _discovered_dislikes[id] = PackedStringArray()

	# events (indexed by actor_id)
	if events_path != "":
		var erows: Array = _load_csv_rows(events_path)
		for e_v in erows:
			if typeof(e_v) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = e_v
			var aid: String = _s(e.get("character_id", ""))
			if aid == "":
				continue
			if not _events_by_actor.has(aid):
				_events_by_actor[aid] = []
			var arr: Array = _events_by_actor[aid]
			arr.append(e)
			_events_by_actor[aid] = arr

	emit_signal("data_reloaded")

# ────────────────────────────────────────────────────────────────────────────────
# Public API — defs
# ────────────────────────────────────────────────────────────────────────────────
func get_defs() -> Dictionary:
	return _defs.duplicate(true)

func get_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k in _defs.keys():
		out.append(String(k))
	out.sort()
	return out

func get_display_name(id: String) -> String:
	return _s((_defs.get(id, {}) as Dictionary).get("bond_name", id))

func is_love_interest(id: String) -> bool:
	return _b((_defs.get(id, {}) as Dictionary).get("love_interest", false))

func get_rewards_for(id: String) -> Dictionary:
	return (_defs.get(id, {}) as Dictionary).get("rewards", {}) as Dictionary

func get_events_for(id: String) -> Array:
	return (_events_by_actor.get(id, []) as Array).duplicate(true)

# Likes/Dislikes (full author list)
func get_likes(id: String) -> PackedStringArray:
	return _to_psa((_defs.get(id, {}) as Dictionary).get("gift_likes", []))

func get_dislikes(id: String) -> PackedStringArray:
	return _to_psa((_defs.get(id, {}) as Dictionary).get("gift_dislikes", []))

# Known subset the player has discovered so far
func get_discovered_likes(id: String) -> PackedStringArray:
	return _to_psa(_discovered_likes.get(id, PackedStringArray()))

func get_discovered_dislikes(id: String) -> PackedStringArray:
	return _to_psa(_discovered_dislikes.get(id, PackedStringArray()))

func mark_gift_discovered(id: String, gift_id: String, reaction: String) -> void:
	var r: String = _s(reaction).to_lower()
	if r == "liked" or r == "like":
		var arr: PackedStringArray = get_discovered_likes(id)
		if not arr.has(gift_id): arr.append(gift_id)
		_discovered_likes[id] = arr
	elif r == "disliked" or r == "dislike":
		var arr2: PackedStringArray = get_discovered_dislikes(id)
		if not arr2.has(gift_id): arr2.append(gift_id)
		_discovered_dislikes[id] = arr2

# ────────────────────────────────────────────────────────────────────────────────
# Public API — progress (BXP & Layer)
# ────────────────────────────────────────────────────────────────────────────────
func get_bxp(id: String) -> int:
	return int(_bxp.get(id, 0))

func get_layer(id: String) -> int:
	return _bxp_to_layer(get_bxp(id))

func add_bxp(id: String, amount: int) -> int:
	if not _defs.has(id):
		# Allow ad-hoc ids but mark as known for UI if you feed progress
		_defs[id] = {"id": id, "bond_name": id.capitalize()}
	var old_val: int = get_bxp(id)
	var clamped: int = clamp(old_val + max(amount, 0), 0, MAX_BXP)
	_bxp[id] = clamped
	if clamped != old_val:
		emit_signal("bxp_changed", id, clamped)
		var old_layer: int = _bxp_to_layer(old_val)
		var new_layer: int = _bxp_to_layer(clamped)
		if new_layer != old_layer:
			emit_signal("level_changed", id, new_layer)
		_set_known(id, true)
	return clamped

func set_bxp(id: String, value: int) -> void:
	add_bxp(id, value - get_bxp(id))

func get_max_layer() -> int: return MAX_LAYER
func get_max_bxp()   -> int: return MAX_BXP

# Known / met
func is_known(id: String) -> bool:
	return bool(_known.get(id, false) or get_bxp(id) > 0 or get_layer(id) > 0)

func set_known(id: String, val: bool) -> void:
	_set_known(id, val)
	
# Convenient aliases so UIs can use consistent names.
func get_bond_def(id: String) -> Dictionary:
	return (_defs.get(id, {}) as Dictionary).duplicate(true)

func get_bond_name(id: String) -> String:
	return get_display_name(id)

func get_max_level() -> int:
	return get_max_layer()

# (Optional) if a UI wants a single dict of defs:
func get_dict() -> Dictionary:
	return get_defs()


# ───────────────── Save / Load ─────────────────
func save() -> Dictionary:
	return {
		"bxp": _bxp.duplicate(true),
		"known": _known.duplicate(true),
		"disc_likes": _discovered_likes.duplicate(true),
		"disc_dislikes": _discovered_dislikes.duplicate(true),
	}

func load(data: Dictionary) -> void:
	var bxp_v: Variant = data.get("bxp")
	if typeof(bxp_v) == TYPE_DICTIONARY: _bxp = (bxp_v as Dictionary).duplicate(true)
	var known_v: Variant = data.get("known")
	if typeof(known_v) == TYPE_DICTIONARY: _known = (known_v as Dictionary).duplicate(true)
	var dl_v: Variant = data.get("disc_likes")
	if typeof(dl_v) == TYPE_DICTIONARY: _discovered_likes = (dl_v as Dictionary).duplicate(true)
	var ddl_v: Variant = data.get("disc_dislikes")
	if typeof(ddl_v) == TYPE_DICTIONARY: _discovered_dislikes = (ddl_v as Dictionary).duplicate(true)
	emit_signal("data_reloaded")

# ───────────────── Helpers ─────────────────
func _set_known(id: String, v: bool) -> void:
	var prev: bool = is_known(id)
	_known[id] = v
	if is_known(id) != prev:
		emit_signal("known_changed", id, is_known(id))

func _bxp_to_layer(x: int) -> int:
	# 0–1 = Acquaintance, 2–3 = Outer, 4–5 = Middle, 6–7 = Inner, 8 = Core
	return clamp(x, 0, MAX_LAYER)

# CSV helpers
func _first_existing(paths: Array) -> String:
	for p_v in paths:
		var p: String = String(p_v)
		if FileAccess.file_exists(p):
			return p
	return ""

func _load_csv_rows(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header: PackedStringArray = PackedStringArray()
	if not f.eof_reached():
		header = _split_csv_line(f.get_line())
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges() == "":
			continue
		var cols: PackedStringArray = _split_csv_line(line)
		var row: Dictionary = {}
		var n: int = min(header.size(), cols.size())
		for i in range(n):
			row[header[i]] = cols[i]
		out.append(row)
	return out

func _split_csv_line(s: String) -> PackedStringArray:
	var a := PackedStringArray()
	var cur := ""
	var in_q := false
	for i in s.length():
		var ch := s[i]
		if ch == '"' and (i == 0 or s[i-1] != "\\"):
			in_q = not in_q
			continue
		if ch == "," and not in_q:
			a.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
	a.append(cur.strip_edges())
	return a

# Coercion
func _s(v: Variant) -> String:
	return String(v).strip_edges()

func _b(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL: return v
		TYPE_INT: return int(v) != 0
		TYPE_FLOAT: return float(v) != 0.0
		_:
			var t: String = String(v).strip_edges().to_lower()
			return t in ["1","true","y","yes","on"]

func _list(v: Variant) -> PackedStringArray:
	var p := PackedStringArray()
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		return v
	for seg in String(v).split(";", false):
		var s := String(seg).strip_edges()
		if s != "":
			p.append(s)
	return p

func _to_psa(v: Variant) -> PackedStringArray:
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		return v
	var out := PackedStringArray()
	if typeof(v) == TYPE_ARRAY:
		for e in (v as Array):
			out.append(String(e))
	return out
# … keep everything you have from the last version …

func get_story_points(id: String) -> PackedStringArray:
	var rec: Dictionary = (_defs.get(id, {}) as Dictionary)
	var raw: String = _s(rec.get("story_points",""))
	var out := PackedStringArray()
	if raw == "":
		return out
	for seg in raw.split(";", false):
		var s := String(seg).strip_edges()
		if s != "":
			out.append(s)
	return out
