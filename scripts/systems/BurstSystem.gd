## ═══════════════════════════════════════════════════════════════════════════
## BurstSystem - Burst Abilities Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages burst abilities that unlock based on party affinity progression.
##   Tracks available burst abilities and their unlock requirements.
##
## RESPONSIBILITIES:
##   • Load burst ability definitions from CSV
##   • Check which burst abilities are unlocked based on affinity tiers
##   • Provide burst ability data for battle system
##
## CONNECTED SYSTEMS:
##   • AffinitySystem - Checks affinity tiers for unlock conditions
##   • BattleManager - Burst gauge tracking
##   • Battle - Burst menu and execution
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name BurstSystem

const BURST_CSV_PATH: String = "res://data/combat/burst_abilities.csv"

var burst_abilities: Dictionary = {}  # burst_id -> ability data
var _csv_loader: Node = null
var _affinity_system: Node = null

func _ready() -> void:
	_csv_loader = get_node_or_null("/root/aCSVLoader")
	_affinity_system = get_node_or_null("/root/aAffinitySystem")
	_load_burst_abilities()

func _load_burst_abilities() -> void:
	"""Load burst ability definitions from CSV"""
	if not _csv_loader or not _csv_loader.has_method("load_csv"):
		push_error("[BurstSystem] CSV loader not available!")
		return

	if not ResourceLoader.exists(BURST_CSV_PATH):
		push_error("[BurstSystem] Burst abilities CSV not found: %s" % BURST_CSV_PATH)
		return

	var result = _csv_loader.call("load_csv", BURST_CSV_PATH, "burst_id")
	if typeof(result) == TYPE_DICTIONARY:
		burst_abilities = result
		print("[BurstSystem] Loaded %d burst abilities" % burst_abilities.size())
	else:
		push_error("[BurstSystem] Failed to load burst abilities CSV")

func get_available_bursts(party_ids: Array) -> Array:
	"""
	Get list of available burst abilities for the current party.
	Checks unlock conditions against affinity tiers.

	Returns: Array of burst ability dictionaries that are unlocked
	"""
	var available: Array = []

	print("[BurstSystem] Checking available bursts for party: ", party_ids)
	print("[BurstSystem] Total burst abilities loaded: %d" % burst_abilities.size())

	for burst_id in burst_abilities.keys():
		var burst_data = burst_abilities[burst_id]

		print("[BurstSystem] Checking burst: %s (data type: %s)" % [burst_id, typeof(burst_data)])

		# Validate burst_data
		if typeof(burst_data) != TYPE_DICTIONARY:
			print("[BurstSystem] ERROR: Burst data for %s is not a dictionary!" % burst_id)
			continue

		# Check if this burst is unlocked
		if _is_burst_unlocked(burst_data, party_ids):
			print("[BurstSystem] Burst %s is UNLOCKED" % burst_id)
			available.append(burst_data)
		else:
			print("[BurstSystem] Burst %s is LOCKED" % burst_id)

	print("[BurstSystem] Total available bursts: %d" % available.size())
	return available

func _is_burst_unlocked(burst_data: Dictionary, party_ids: Array) -> bool:
	"""Check if a burst ability is unlocked based on requirements"""
	var unlock_condition = String(burst_data.get("unlock_condition", "always"))

	# Always available (solo hero burst)
	if unlock_condition == "always":
		return true

	# Parse affinity tier requirement (e.g., "affinity_tier:2")
	if unlock_condition.begins_with("affinity_tier:"):
		var required_tier = int(unlock_condition.split(":")[1])

		# Get participants for this burst
		var participants_str = String(burst_data.get("participants", ""))
		var participants = participants_str.split(";", false)

		# Check if all participants are in the party
		for participant in participants:
			if not party_ids.has(participant):
				return false  # Missing a required participant

		# Check affinity tier for all pairs
		if participants.size() >= 2 and _affinity_system:
			# For duo bursts, check the single pair
			if participants.size() == 2:
				var tier = _affinity_system.get_affinity_tier(participants[0], participants[1])
				return tier >= required_tier

			# For trio+ bursts, check all pairs meet the requirement
			for i in range(participants.size()):
				for j in range(i + 1, participants.size()):
					var tier = _affinity_system.get_affinity_tier(participants[i], participants[j])
					if tier < required_tier:
						return false  # At least one pair doesn't meet tier requirement
			return true

	return false

func get_burst_by_id(burst_id: String) -> Dictionary:
	"""Get a specific burst ability by ID"""
	return burst_abilities.get(burst_id, {})

func get_save_blob() -> Dictionary:
	return {}  # Burst abilities don't need save data (they're based on affinity)

func apply_save_blob(_blob: Dictionary) -> void:
	pass  # No save data to restore

func clear_all() -> void:
	pass  # No state to clear
