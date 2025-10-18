extends Node
class_name PerkSystem

## PerkSystem — 5×5 grid of stat-tied perks with save hooks and helpers.

signal perk_unlocked(stat_id: String, tier: int, perk_id: String)
signal perks_changed()

const STAT_IDS: PackedStringArray = ["BRW","VTL","MND","TPO","FCS"]
const TIER_THRESHOLDS: PackedInt32Array = [1, 3, 5, 7, 10]

# 25 placeholder perks (stable ids for saves)
const PERK_DB: Dictionary = {
	"BRW": [
		{"id":"brw_t1","name":"Iron Grip","desc":"+2% Physical Hit."},
		{"id":"brw_t2","name":"Counter Stance","desc":"Defend adds +10% reflect."},
		{"id":"brw_t3","name":"Breaker","desc":"+10% vs Shielded."},
		{"id":"brw_t4","name":"Unstaggerable","desc":"Stumble pushback -1."},
		{"id":"brw_t5","name":"Titan Form","desc":"+10% DMG floor (Player->Enemy)."}
	],
	"VTL": [
		{"id":"vtl_t1","name":"Second Wind","desc":"+5% heal at turn start under 30% HP."},
		{"id":"vtl_t2","name":"Bulwark","desc":"+5 ArmorFlat (placeholder)."},
		{"id":"vtl_t3","name":"Steadfast","desc":"-10% DoT damage."},
		{"id":"vtl_t4","name":"Stonewall","desc":"Defend x0.65 instead of x0.7."},
		{"id":"vtl_t5","name":"Nine Lives","desc":"Once per fight, survive lethal at 1 HP."}
	],
	"MND": [
		{"id":"mnd_t1","name":"Sharp Mind","desc":"+5 Skill Hit."},
		{"id":"mnd_t2","name":"Overchannel","desc":"Overcast HP cost -10%."},
		{"id":"mnd_t3","name":"Runic Echo","desc":"+10% Sigil damage."},
		{"id":"mnd_t4","name":"Mindguard","desc":"-10% MDEF damage taken."},
		{"id":"mnd_t5","name":"Arc Savant","desc":"Crit skills deal x2.2 (placeholder)."}
	],
	"TPO": [
		{"id":"tpo_t1","name":"Quickstep","desc":"+1 Speed."},
		{"id":"tpo_t2","name":"Opportunist","desc":"+4 Burst on crit (cap obeyed)."},
		{"id":"tpo_t3","name":"Ambusher","desc":"+5% opening round Hit."},
		{"id":"tpo_t4","name":"Slipstream","desc":"Initiative pushback +1 on crit."},
		{"id":"tpo_t5","name":"Time Dancer","desc":"Small chance to act twice (TBD)."}
	],
	"FCS": [
		{"id":"fcs_t1","name":"Eagle Eye","desc":"+2% Physical & Skill Hit."},
		{"id":"fcs_t2","name":"Study Pace","desc":"+5% SXP from study items."},
		{"id":"fcs_t3","name":"True Sight","desc":"+5% vs evasive foes."},
		{"id":"fcs_t4","name":"Spot Weakness","desc":"First Stumble each round +2 Burst."},
		{"id":"fcs_t5","name":"Perfect Focus","desc":"Clamp Hit min +2 (to a 7% floor)."}
	]
}

# unlocked map: stat_id -> PackedInt32Array[5] of 0/1
var _unlocked: Dictionary = {}  # {String -> PackedInt32Array(5)}

func _ready() -> void:
	for s in STAT_IDS:
		_ensure_stat(s)

# ---- Public API ---------------------------------------------------------------

func get_thresholds(_stat_id: String) -> PackedInt32Array:
	return TIER_THRESHOLDS

func get_threshold(_stat_id: String, tier_index: int) -> int:
	return TIER_THRESHOLDS[min(max(tier_index, 0), TIER_THRESHOLDS.size() - 1)]

func get_perk_id(stat_id: String, tier_index: int) -> String:
	var row: Array = PERK_DB.get(stat_id, [])
	if tier_index >= 0 and tier_index < row.size():
		return String((row[tier_index] as Dictionary).get("id", ""))
	return ""

func get_perk_name(stat_id: String, tier_index: int) -> String:
	var row: Array = PERK_DB.get(stat_id, [])
	if tier_index >= 0 and tier_index < row.size():
		return String((row[tier_index] as Dictionary).get("name", "Perk"))
	return "Perk"

func get_perk_desc(stat_id: String, tier_index: int) -> String:
	var row: Array = PERK_DB.get(stat_id, [])
	if tier_index >= 0 and tier_index < row.size():
		return String((row[tier_index] as Dictionary).get("desc", ""))
	return ""

func get_thresholds_for(_stat_id: String) -> PackedInt32Array:
	return TIER_THRESHOLDS

func is_unlocked(stat_id: String, tier_index: int) -> bool:
	_ensure_stat(stat_id)
	var row: PackedInt32Array = _unlocked[stat_id]
	return tier_index >= 0 and tier_index < row.size() and row[tier_index] == 1

func has_perk(perk_id: String) -> bool:
	var st_and_tier: Array = _find_by_id(perk_id)
	return st_and_tier.size() == 2 and is_unlocked(String(st_and_tier[0]), int(st_and_tier[1]))

func unlock_perk(stat_id: String, tier_index: int) -> bool:
	_ensure_stat(stat_id)
	if is_unlocked(stat_id, tier_index):
		return false
	var row: PackedInt32Array = _unlocked[stat_id]
	if tier_index < 0 or tier_index >= row.size():
		return false
	row[tier_index] = 1
	_unlocked[stat_id] = row
	var id := get_perk_id(stat_id, tier_index)
	perk_unlocked.emit(stat_id, tier_index, id)
	perks_changed.emit()
	return true

func unlock_by_id(perk_id: String) -> bool:
	var st_and_tier: Array = _find_by_id(perk_id)
	if st_and_tier.size() != 2:
		return false
	return unlock_perk(String(st_and_tier[0]), int(st_and_tier[1]))

func get_starting_options(stat_ids: Array) -> Array:
	# Return Tier-1 perk options for provided stats (stat, tier, id, name, desc).
	var out: Array = []
	for v in stat_ids:
		var s: String = String(v)
		if not STAT_IDS.has(s):
			continue
		out.append({
			"stat": s,
			"tier": 0,
			"id": get_perk_id(s, 0),
			"name": get_perk_name(s, 0),
			"desc": get_perk_desc(s, 0)
		})
	return out

# ---- Save hooks ---------------------------------------------------------------

func get_save_blob() -> Dictionary:
	# Save both the grid and a flat list of ids for resilience.
	return {
		"unlocked": _unlocked.duplicate(true),
		"ids": _export_unlocked_ids()
	}

func apply_save_blob(blob: Dictionary) -> void:
	_unlocked.clear()
	var used_grid: bool = false

	# Prefer the structured grid if present.
	var d_v: Variant = blob.get("unlocked", null)
	if typeof(d_v) == TYPE_DICTIONARY:
		var d: Dictionary = d_v
		for k_v in d.keys():
			var key: String = String(k_v)
			var arr_v: Variant = d[key]
			if typeof(arr_v) == TYPE_PACKED_INT32_ARRAY:
				_unlocked[key] = (arr_v as PackedInt32Array)
				used_grid = true
			elif typeof(arr_v) == TYPE_ARRAY:
				# Accept raw Array and coerce into PackedInt32Array
				var src: Array = arr_v
				var tmp := PackedInt32Array()
				for v in src:
					tmp.push_back(int(v))
				_unlocked[key] = tmp
				used_grid = true

	# Fallback: flat id list ("ids" or legacy "unlocked_ids")
	if not used_grid:
		var ids_v: Variant = blob.get("ids", blob.get("unlocked_ids", []))
		if typeof(ids_v) == TYPE_ARRAY:
			for id_v in (ids_v as Array):
				unlock_by_id(String(id_v))

	# Make sure all rows exist.
	for s in STAT_IDS:
		_ensure_stat(s)

	perks_changed.emit()

# ---- Internals ----------------------------------------------------------------

func _ensure_stat(stat_id: String) -> void:
	if not _unlocked.has(stat_id):
		_unlocked[stat_id] = PackedInt32Array([0, 0, 0, 0, 0])

func _find_by_id(perk_id: String) -> Array:
	for s in STAT_IDS:
		var row: Array = PERK_DB.get(s, [])
		for i in range(row.size()):
			var rec: Dictionary = row[i]
			if String(rec.get("id", "")) == perk_id:
				return [s, i]
	return []

func _export_unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for s in STAT_IDS:
		_ensure_stat(s)
		var row: PackedInt32Array = _unlocked[s]
		for i in range(row.size()):
			if row[i] == 1:
				out.append(get_perk_id(s, i))
	return out
