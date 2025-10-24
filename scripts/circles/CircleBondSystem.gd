## ═══════════════════════════════════════════════════════════════════════════
## CircleBondSystem - Social Bond & Relationship Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages social bonds between the hero and party members using a layered
##   BXP (Bond Experience Points) system, tracking relationship progression,
##   likes/dislikes discovery, love interests, and bond-specific events.
##
## RESPONSIBILITIES:
##   • Bond level tracking (0-8: Acquaintance → Outer → Middle → Inner → Core)
##   • BXP (Bond Experience Points) accumulation per character
##   • Likes/dislikes discovery system (player learns character preferences)
##   • Love interest identification and tracking
##   • Poly connection tracking (polyamorous relationship compatibility)
##   • Bond event scheduling (scenes unlock at specific bond levels)
##   • CSV-based bond definitions and events
##   • Save/load bond state
##
## BOND LAYER SYSTEM:
##   Event-based progression with 9 main events (E1-E9) across 5 layers:
##   - E1: Introduction (sets layer to Acquaintance, 0 points)
##   - E2-E3: Acquaintance layer (threshold 10 to unlock Outer)
##   - E4-E5: Outer layer (threshold 12 to unlock Middle)
##   - E6-E7: Middle layer (threshold 14 to unlock Inner)
##   - E8-E9: Inner layer (threshold 16 to unlock Core)
##   - Final: Love interests only (Friend/Romance choice)
##
## PROGRESSION MECHANICS:
##   Points come from:
##   - Base event: +6 for completing any main event (E2-E9, E1 gives 0)
##   - Dialogue (3 questions): Best +2, Okay +1, Neutral 0, Negative -1
##   - Gift (once per layer): Disliked -2, Neutral +1, Liked +4
##   - Side Meetups: +6 points (optional filler scenes)
##
##   Thresholds (cost to unlock next event, paid after each event):
##   - After E2: 10 pts (Acquaintance layer)
##   - After E3: 10 pts (Acquaintance → Outer transition)
##   - After E4: 12 pts (Outer layer)
##   - After E5: 12 pts (Outer → Middle transition)
##   - After E6: 14 pts (Middle layer)
##   - After E7: 14 pts (Middle → Inner transition)
##   - After E8: 16 pts (Inner layer)
##   - After E9: 16 pts (Inner → Core transition)
##   Total: 10+10+12+12+14+14+16+16 = 104 pts across E2-E9
##
##   Points overflow/bank forward to next threshold
##
## LIKES/DISLIKES SYSTEM:
##   Each character has likes and dislikes (topics, gifts, activities)
##   Player discovers these through interactions and observation
##   Tracked separately as _discovered_likes and _discovered_dislikes
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Save/load coordination
##   • DormSystem - Bestie/Rival relationships may influence bonds
##   • RomanceSystem - Love interest integration
##   • EventRunner - Bond event scene playback
##
## CSV DATA SOURCES:
##   • res://data/circles/circle_bonds.csv - Bond definitions
##     (bond_id, bond_name, love_interest, likes, dislikes, poly_connects, rewards)
##   • res://data/circles/circles_events.csv - Bond event scenes
##     (actor_id, event_id, required_layer, scene_path, etc.)
##
## KEY METHODS:
##   • get_event_index(bond_id) -> int - Current event completed (0-9)
##   • get_layer(bond_id) -> int - Current layer as int (0=None, 1=Acq, 2=Outer, 3=Mid, 4=Inner, 5=Core)
##   • get_layer_name(bond_id) -> String - Layer name (Acquaintance, Outer, etc.)
##   • get_points_bank(bond_id) -> int - Points accumulated toward next threshold
##   • get_next_threshold(bond_id) -> int - Points needed for next event unlock
##   • complete_event(bond_id, dialogue_score) - Finish main event, add base+dialogue points
##   • give_gift(bond_id, gift_reaction) - Give gift (once per layer), add points
##   • do_side_meetup(bond_id) - Optional +6 points filler scene
##   • can_unlock_next_event(bond_id) -> bool - Check if threshold reached
##   • is_love_interest(bond_id) -> bool - Check if romance option
##   • discover_like/dislike(bond_id, topic) - Learn character preference
##
## ═══════════════════════════════════════════════════════════════════════════

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

# Player state - NEW EVENT-BASED SYSTEM
var _event_index: Dictionary = {}          # id -> int (0 = not started, 1 = E1 complete, ..., 9 = E9 complete)
var _points_bank: Dictionary = {}          # id -> int (points accumulated toward next threshold)
var _layer: Dictionary = {}                # id -> String ("None", "Acquaintance", "Outer", "Middle", "Inner", "Core")
var _gift_used_in_layer: Dictionary = {}   # id -> bool (one gift per layer)
var _known: Dictionary = {}                # id -> bool (met, discovered, etc.)
var _discovered_likes: Dictionary = {}     # id -> PackedStringArray
var _discovered_dislikes: Dictionary = {}  # id -> PackedStringArray

# Tunables - NEW THRESHOLD SYSTEM
const THRESHOLD_ACQUAINTANCE_TO_OUTER := 10  # Before E4
const THRESHOLD_OUTER_TO_MIDDLE := 12        # Before E6
const THRESHOLD_MIDDLE_TO_INNER := 14        # Before E8
const THRESHOLD_INNER_TO_CORE := 16          # Before Final/E10

const BASE_EVENT_POINTS := 6                 # E2-E9 base reward
const SIDE_MEETUP_POINTS := 6                # Side meetup reward

# Event-to-layer mapping
const EVENT_TO_LAYER := {
	0: "None",           # Not started
	1: "Acquaintance",   # E1 complete
	2: "Acquaintance",   # E2
	3: "Acquaintance",   # E3 (label flips to Outer at end)
	4: "Outer",          # E4
	5: "Outer",          # E5 (label flips to Middle at end)
	6: "Middle",         # E6
	7: "Middle",         # E7 (label flips to Inner at end)
	8: "Inner",          # E8
	9: "Inner",          # E9 (label flips to Core at end)
	10: "Core"           # Final (LI only)
}

# Layer name to numeric value (for UI compatibility)
const LAYER_TO_INT := {
	"None": 0,
	"Acquaintance": 1,
	"Outer": 2,
	"Middle": 3,
	"Inner": 4,
	"Core": 5
}

# Party integration
const PARTY_PATH := "/root/aPartySystem"
const GS_PATH := "/root/aGameState"

func _ready() -> void:
	reload()
	_connect_party_signals()
	_auto_discover_party_members()

## Connects to party system signals to auto-discover party members
func _connect_party_signals() -> void:
	var party := get_node_or_null(PARTY_PATH)
	if party:
		if party.has_signal("party_changed") and not party.is_connected("party_changed", Callable(self, "_on_party_changed")):
			party.connect("party_changed", Callable(self, "_on_party_changed"))

	var gs := get_node_or_null(GS_PATH)
	if gs:
		if gs.has_signal("party_changed") and not gs.is_connected("party_changed", Callable(self, "_on_party_changed")):
			gs.connect("party_changed", Callable(self, "_on_party_changed"))

## Called when party roster changes - automatically mark party members as known
func _on_party_changed(_a: Variant = null, _arg2: Variant = null) -> void:
	_auto_discover_party_members()

## Automatically marks all party members as known in the bond system
func _auto_discover_party_members() -> void:
	var party_ids: Array = _get_party_member_ids()
	for pid_v in party_ids:
		var pid: String = String(pid_v)
		if pid != "" and pid != "hero":
			set_known(pid, true)

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
# Public API — Event-based progression
# ────────────────────────────────────────────────────────────────────────────────

## Get current event index (0 = not started, 1 = E1 complete, ..., 9 = E9 complete)
func get_event_index(id: String) -> int:
	return int(_event_index.get(id, 0))

## Get current points accumulated toward next threshold
func get_points_bank(id: String) -> int:
	return int(_points_bank.get(id, 0))

## Get current layer as integer (0=None, 1=Acq, 2=Outer, 3=Mid, 4=Inner, 5=Core)
func get_layer(id: String) -> int:
	var layer_name: String = get_layer_name(id)
	return LAYER_TO_INT.get(layer_name, 0)

## Get current layer name
func get_layer_name(id: String) -> String:
	var stored: String = String(_layer.get(id, "None"))
	if stored != "None":
		return stored
	# Derive from event index if not explicitly set
	var event_idx: int = get_event_index(id)
	return EVENT_TO_LAYER.get(event_idx, "None")

## Get next threshold cost (points needed to unlock next event)
func get_next_threshold(id: String) -> int:
	var layer_name: String = get_layer_name(id)
	match layer_name:
		"Acquaintance": return THRESHOLD_ACQUAINTANCE_TO_OUTER
		"Outer": return THRESHOLD_OUTER_TO_MIDDLE
		"Middle": return THRESHOLD_MIDDLE_TO_INNER
		"Inner": return THRESHOLD_INNER_TO_CORE
		"Core": return 0  # No more thresholds
		_: return THRESHOLD_ACQUAINTANCE_TO_OUTER  # Default to first threshold

## Check if gift has been used in current layer
func is_gift_used_in_layer(id: String) -> bool:
	return bool(_gift_used_in_layer.get(id, false))

## Check if character has met threshold to unlock next event
func can_unlock_next_event(id: String) -> bool:
	var event_idx: int = get_event_index(id)
	if event_idx >= 9:
		return false  # All main events complete
	var threshold: int = get_next_threshold(id)
	var bank: int = get_points_bank(id)
	return bank >= threshold

## Complete a main bond event (E1-E9)
## dialogue_score: sum of dialogue choices (e.g., 3×Best = +6, mix might be +3, etc.)
func complete_event(id: String, dialogue_score: int = 0) -> void:
	if not _defs.has(id):
		_defs[id] = {"id": id, "bond_name": id.capitalize()}

	var old_event: int = get_event_index(id)
	var new_event: int = old_event + 1
	_event_index[id] = new_event

	# E1 gives 0 base points (just introduction)
	var base_points: int = 0 if new_event == 1 else BASE_EVENT_POINTS
	var total_points: int = base_points + dialogue_score

	# Add points to bank
	_add_points(id, total_points)

	# Update layer based on event completion (layer flips at E1/E3/E5/E7/E9)
	_update_layer_from_event(id, new_event)

	# After completing event, check if we can pay threshold to unlock next event
	# (except after E9, which unlocks Final for LIs only)
	if new_event < 9:
		var threshold: int = get_next_threshold(id)
		var bank: int = get_points_bank(id)
		if bank >= threshold:
			# Pay the threshold, keep the overflow banked
			_points_bank[id] = bank - threshold
			emit_signal("bxp_changed", id, _points_bank[id])
			print("[CircleBondSystem] %s completed E%d, paid %d pts threshold, %d banked" % [id, new_event, threshold, _points_bank[id]])

	# Mark as known
	_set_known(id, true)

	emit_signal("level_changed", id, get_layer(id))

## Give a gift (once per layer)
## reaction: "liked" (+4), "neutral" (+1), "disliked" (-2)
func give_gift(id: String, reaction: String) -> bool:
	if _gift_used_in_layer.get(id, false):
		print("[CircleBondSystem] Gift already used in current layer for %s" % id)
		return false

	var points: int = 0
	match reaction.to_lower():
		"liked": points = 4
		"neutral": points = 1
		"disliked": points = -2
		_: points = 1  # Default to neutral

	_add_points(id, points)
	_gift_used_in_layer[id] = true

	# Discover the gift preference
	if reaction.to_lower() != "neutral":
		# This would be called with the actual gift_id in real usage
		# For now just marking that gift was used
		pass

	return true

## Do a side meetup (optional +6 filler scene)
func do_side_meetup(id: String) -> void:
	_add_points(id, SIDE_MEETUP_POINTS)

## Internal: Add points to bank, handle threshold crossing
func _add_points(id: String, amount: int) -> void:
	var old_bank: int = get_points_bank(id)
	var new_bank: int = old_bank + amount
	_points_bank[id] = max(0, new_bank)  # Can't go below 0

	emit_signal("bxp_changed", id, new_bank)  # Reuse signal name for compatibility

## Internal: Update layer when event completes
func _update_layer_from_event(id: String, event_idx: int) -> void:
	# Layer label flips at end of E1/E3/E5/E7/E9
	var new_layer: String = _layer.get(id, "None")

	match event_idx:
		1: new_layer = "Acquaintance"  # E1 → Acquaintance
		3: new_layer = "Outer"         # E3 → Outer
		5: new_layer = "Middle"        # E5 → Middle
		7: new_layer = "Inner"         # E7 → Inner
		9: new_layer = "Core"          # E9 → Core

	var old_layer: String = _layer.get(id, "None")
	_layer[id] = new_layer

	# Reset gift flag when entering new layer
	if old_layer != new_layer:
		_gift_used_in_layer[id] = false

# Backward compatibility methods (for old UI code)
func get_bxp(id: String) -> int:
	# Return points bank for compatibility
	return get_points_bank(id)

func add_bxp(id: String, amount: int) -> int:
	# Backward compatibility: just add points
	_add_points(id, amount)
	return get_points_bank(id)

func set_bxp(id: String, value: int) -> void:
	_points_bank[id] = max(0, value)

func get_max_layer() -> int: return 5  # 0-5 (None, Acq, Outer, Middle, Inner, Core)
func get_max_bxp() -> int: return 999  # No hard cap on points

# Known / met
func is_known(id: String) -> bool:
	return bool(_known.get(id, false) or get_event_index(id) > 0 or get_layer(id) > 0)

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
		"event_index": _event_index.duplicate(true),
		"points_bank": _points_bank.duplicate(true),
		"layer": _layer.duplicate(true),
		"gift_used_in_layer": _gift_used_in_layer.duplicate(true),
		"known": _known.duplicate(true),
		"disc_likes": _discovered_likes.duplicate(true),
		"disc_dislikes": _discovered_dislikes.duplicate(true),
		# Backward compatibility
		"bxp": _points_bank.duplicate(true),  # Save points as bxp for old saves
	}

func load(data: Dictionary) -> void:
	# Load new format
	var event_v: Variant = data.get("event_index")
	if typeof(event_v) == TYPE_DICTIONARY: _event_index = (event_v as Dictionary).duplicate(true)

	var points_v: Variant = data.get("points_bank")
	if typeof(points_v) == TYPE_DICTIONARY:
		_points_bank = (points_v as Dictionary).duplicate(true)
	else:
		# Backward compatibility: try loading from old "bxp" field
		var bxp_v: Variant = data.get("bxp")
		if typeof(bxp_v) == TYPE_DICTIONARY: _points_bank = (bxp_v as Dictionary).duplicate(true)

	var layer_v: Variant = data.get("layer")
	if typeof(layer_v) == TYPE_DICTIONARY: _layer = (layer_v as Dictionary).duplicate(true)

	var gift_v: Variant = data.get("gift_used_in_layer")
	if typeof(gift_v) == TYPE_DICTIONARY: _gift_used_in_layer = (gift_v as Dictionary).duplicate(true)

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

## Helper to get all party member IDs from PartySystem or GameState
func _get_party_member_ids() -> Array:
	var out: Array = []

	# Try PartySystem first
	var party := get_node_or_null(PARTY_PATH)
	if party and party.has_method("get_active_party_ids"):
		var ids_v: Variant = party.call("get_active_party_ids")
		if typeof(ids_v) == TYPE_ARRAY:
			return ids_v as Array
		elif typeof(ids_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (ids_v as PackedStringArray):
				out.append(String(s))
			return out

	# Fallback to GameState
	var gs := get_node_or_null(GS_PATH)
	if gs and gs.has_method("get_active_party_ids"):
		var ids_v2: Variant = gs.call("get_active_party_ids")
		if typeof(ids_v2) == TYPE_ARRAY:
			return ids_v2 as Array
		elif typeof(ids_v2) == TYPE_PACKED_STRING_ARRAY:
			for s2 in (ids_v2 as PackedStringArray):
				out.append(String(s2))
			return out

	return out
