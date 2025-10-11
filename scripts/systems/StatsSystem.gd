extends Node
class_name StatsSystem

signal stat_leveled_up(stat_name: String, new_level: int)

var stat_sxp: Dictionary   = {"FCS": 0, "MND": 0, "TPO": 0, "BRW": 0, "VTL": 0}
var stat_level: Dictionary = {"FCS": 1, "MND": 1, "TPO": 1, "BRW": 1, "VTL": 1}
var weekly_actions: Dictionary = {"FCS": 0, "MND": 0, "TPO": 0, "BRW": 0, "VTL": 0}

var sxp_thresholds: Array[int] = [100, 250, 450, 700, 1000, 1400, 1850, 2350, 2950, 3485]

func get_stats_dict() -> Dictionary:
	return {
		"BRW": int(stat_level.get("BRW", 1)),
		"VTL": int(stat_level.get("VTL", 1)),
		"TPO": int(stat_level.get("TPO", 1)),
		"FCS": int(stat_level.get("FCS", 1)),
		"MND": int(stat_level.get("MND", 1)),
	}

func get_stat(stat: String) -> int:
	return int(stat_level.get(stat, 1))

func get_stat_sxp(stat: String) -> int:
	return int(stat_sxp.get(stat, 0))

func get_weekly_actions_dict() -> Dictionary:
	return weekly_actions.duplicate()

func add_sxp(stat: String, base_amount: int) -> int:
	if not stat_sxp.has(stat):
		push_error("StatsSystem: unknown stat '%s'" % stat)
		return 0

	var action_count: int = int(weekly_actions.get(stat, 0))
	var gain: int = base_amount
	if action_count >= 7:
		gain = int(floor(float(base_amount) * 0.5))
	if gain < 1:
		gain = 1

	weekly_actions[stat] = action_count + 1
	stat_sxp[stat] = int(stat_sxp.get(stat, 0)) + gain

	var level: int = int(stat_level.get(stat, 1))
	while level <= sxp_thresholds.size() and int(stat_sxp[stat]) >= sxp_thresholds[level - 1]:
		level += 1
		stat_level[stat] = level
		emit_signal("stat_leveled_up", stat, level)

	return gain

func reset_week() -> void:
	for key in weekly_actions.keys():
		weekly_actions[key] = 0

func add_sxp_bulk(gains: Dictionary) -> void:
	for k in gains.keys():
		add_sxp(String(k), int(gains[k]))

func set_thresholds(new_thresholds: Array) -> void:
	var cleaned: Array[int] = []
	for v in new_thresholds:
		cleaned.append(int(v))
	sxp_thresholds = cleaned

# ---- Character creation hook (called once from CharacterCreation) -------------

func apply_creation_boosts(picks: Array) -> void:
	# +1 level for each selected starting stat
	for p in picks:
		var k := String(p)
		if k == "": continue
		var cur := int(stat_level.get(k, 1))
		stat_level[k] = max(1, cur + 1)

# ---- Save module API ----------------------------------------------------------

func get_save_blob() -> Dictionary:
	return {
		"levels": stat_level.duplicate(true),
		"xp":      stat_sxp.duplicate(true),
		"weekly":  weekly_actions.duplicate(true),  # optional; if absent, defaults are used
	}

func apply_save_blob(blob: Dictionary) -> void:
	# levels
	var lv_v: Variant = blob.get("levels", {})
	if typeof(lv_v) == TYPE_DICTIONARY:
		for k in (lv_v as Dictionary).keys():
			stat_level[String(k)] = int((lv_v as Dictionary)[k])

	# xp
	var xp_v: Variant = blob.get("xp", {})
	if typeof(xp_v) == TYPE_DICTIONARY:
		for k in (xp_v as Dictionary).keys():
			stat_sxp[String(k)] = int((xp_v as Dictionary)[k])

	# optional weekly actions
	var w_v: Variant = blob.get("weekly", {})
	if typeof(w_v) == TYPE_DICTIONARY:
		for k in (w_v as Dictionary).keys():
			weekly_actions[String(k)] = int((w_v as Dictionary)[k])

func clear_all() -> void:
	reset_week()
	# reset to level 1 and 0 xp
	for k in ["FCS","MND","TPO","BRW","VTL"]:
		stat_level[k] = 1
		stat_sxp[k] = 0
