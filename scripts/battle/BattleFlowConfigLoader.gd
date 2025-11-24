extends RefCounted
class_name BattleFlowConfigLoader

## ═══════════════════════════════════════════════════════════════
## BATTLE FLOW CONFIG LOADER
## ═══════════════════════════════════════════════════════════════
## Loads and applies battle flow configuration from CSV files
## - battle_flow_config.csv: Element priorities and concurrent allowances
## - battle_events.csv: Special battle events and sequences
## - character_marker_positions.csv: Character sprite positioning
## - turn_indicator_animation.csv: Turn panel slide animation

const CONFIG_PATH = "res://data/combat/battle_flow_config.csv"
const EVENTS_PATH = "res://data/combat/battle_events.csv"
const MARKER_POSITIONS_PATH = "res://data/combat/character_marker_positions.csv"
const TURN_ANIM_PATH = "res://data/combat/turn_indicator_animation.csv"

## Priority mapping
const PRIORITY_MAP = {
	"0": 0,  # CRITICAL
	"1": 1,  # URGENT
	"2": 2,  # HIGH
	"3": 3,  # MEDIUM
	"4": 4,  # LOW
	"5": 5,  # AMBIENT
	"CRITICAL": 0,
	"URGENT": 1,
	"HIGH": 2,
	"MEDIUM": 3,
	"LOW": 4,
	"AMBIENT": 5,
}

## Loaded configuration
var element_priorities: Dictionary = {}
var concurrent_elements: Dictionary = {}
var active_on_start: Array[int] = []
var battle_events: Array[Dictionary] = []
var marker_positions: Dictionary = {}  # {side_index: position_config}
var turn_animation: Dictionary = {}  # Turn indicator animation settings

func load_config() -> bool:
	"""Load battle flow configuration from CSV"""
	if not _load_element_config():
		push_error("[BattleFlowConfigLoader] Failed to load element config")
		return false

	if not _load_events_config():
		push_error("[BattleFlowConfigLoader] Failed to load events config")
		return false

	if not _load_marker_positions():
		push_error("[BattleFlowConfigLoader] Failed to load marker positions")
		return false

	if not _load_turn_animation():
		push_error("[BattleFlowConfigLoader] Failed to load turn animation")
		return false

	print("[BattleFlowConfigLoader] Configuration loaded successfully")
	print("  - %d element priorities configured" % element_priorities.size())
	print("  - %d concurrent element sets configured" % concurrent_elements.size())
	print("  - %d elements active on battle start" % active_on_start.size())
	print("  - %d battle events configured" % battle_events.size())
	print("  - %d marker positions configured" % marker_positions.size())
	print("  - Turn animation: %s" % ("enabled" if turn_animation.get("enabled", false) else "disabled"))

	return true

func _load_element_config() -> bool:
	"""Load element configuration from battle_flow_config.csv"""
	var file = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleFlowConfigLoader] Cannot open file: %s" % CONFIG_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read each line
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() < 7 or line[0].strip_edges() == "":
			continue

		var element_id = int(line[0].strip_edges())
		var element_name = line[1].strip_edges()
		var priority = _parse_priority(line[2].strip_edges())
		var can_interrupt = line[3].strip_edges().to_upper() == "TRUE"
		var concurrent_with = _parse_concurrent_list(line[4].strip_edges())
		var active_on_battle_start = line[5].strip_edges().to_upper() == "TRUE"
		var notes = line[6].strip_edges()

		# Store priority
		element_priorities[element_id] = priority

		# Store concurrent allowances
		if concurrent_with.size() > 0:
			concurrent_elements[element_id] = concurrent_with

		# Track elements that should be active on battle start
		if active_on_battle_start:
			active_on_start.append(element_id)

	file.close()
	return true

func _load_events_config() -> bool:
	"""Load battle events configuration from battle_events.csv"""
	var file = FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleFlowConfigLoader] Cannot open file: %s" % EVENTS_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read each line
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() < 9 or line[0].strip_edges() == "":
			continue

		var event = {
			"event_id": int(line[0].strip_edges()),
			"event_name": line[1].strip_edges(),
			"trigger_type": line[2].strip_edges(),
			"trigger_condition": line[3].strip_edges(),
			"priority": _parse_priority(line[4].strip_edges()),
			"actions": _parse_action_list(line[5].strip_edges()),
			"repeatable": line[6].strip_edges().to_upper() == "TRUE",
			"enabled": line[7].strip_edges().to_upper() == "TRUE",
			"notes": line[8].strip_edges(),
			"has_triggered": false,  # Runtime tracking
		}

		# Only add enabled events
		if event.enabled:
			battle_events.append(event)

	file.close()
	return true

func _parse_priority(priority_str: String) -> int:
	"""Parse priority string to integer"""
	var cleaned = priority_str.strip_edges().to_upper()
	return PRIORITY_MAP.get(cleaned, 3)  # Default to MEDIUM

func _parse_concurrent_list(concurrent_str: String) -> Array[int]:
	"""Parse comma-separated list of concurrent element IDs"""
	var result: Array[int] = []

	# Handle "ALL" keyword
	if concurrent_str.to_upper() == "ALL":
		# Return all possible element IDs (1-38)
		for i in range(1, 39):
			result.append(i)
		return result

	# Handle empty string
	if concurrent_str.strip_edges() == "":
		return result

	# Parse comma-separated IDs
	var parts = concurrent_str.split(",")
	for part in parts:
		var cleaned = part.strip_edges()
		if cleaned != "":
			result.append(int(cleaned))

	return result

func _parse_action_list(actions_str: String) -> Array[String]:
	"""Parse semicolon-separated list of actions"""
	var result: Array[String] = []

	if actions_str.strip_edges() == "":
		return result

	var parts = actions_str.split(";")
	for part in parts:
		var cleaned = part.strip_edges()
		if cleaned != "":
			result.append(cleaned)

	return result

func get_element_priority(element_id: int) -> int:
	"""Get priority for an element (defaults to MEDIUM if not configured)"""
	return element_priorities.get(element_id, 3)

func get_concurrent_elements(element_id: int) -> Array[int]:
	"""Get list of elements that can run concurrently with this element"""
	return concurrent_elements.get(element_id, [])

func is_concurrent_allowed(element_a: int, element_b: int) -> bool:
	"""Check if two elements can run concurrently"""
	var a_concurrent = concurrent_elements.get(element_a, [])
	var b_concurrent = concurrent_elements.get(element_b, [])

	return element_b in a_concurrent or element_a in b_concurrent

func get_active_on_start_elements() -> Array[int]:
	"""Get list of elements that should be active when battle starts"""
	return active_on_start

func get_enabled_events() -> Array[Dictionary]:
	"""Get list of enabled battle events"""
	return battle_events

func check_event_triggers(trigger_type: String, context: Dictionary) -> Array[Dictionary]:
	"""Check if any events should trigger based on type and context"""
	var triggered: Array[Dictionary] = []

	for event in battle_events:
		# Skip if already triggered and not repeatable
		if event.has_triggered and not event.repeatable:
			continue

		# Check trigger type match
		if event.trigger_type != trigger_type:
			continue

		# Check trigger condition
		if _check_trigger_condition(event.trigger_condition, context):
			triggered.append(event)
			event.has_triggered = true

	return triggered

func _check_trigger_condition(condition: String, context: Dictionary) -> bool:
	"""Evaluate a trigger condition against context data"""
	# Parse condition format: "variable_operator_value"
	# Examples: "enemy_hp_below_50", "turn_number_equals_1"

	var parts = condition.split("_")
	if parts.size() < 3:
		return false

	# Find operator position
	var operator_index = -1
	var valid_operators = ["below", "above", "equals", "mod"]

	for i in range(parts.size()):
		if parts[i] in valid_operators:
			operator_index = i
			break

	if operator_index == -1:
		return false

	# Extract variable name, operator, and value
	var variable_parts = parts.slice(0, operator_index)
	var variable_name = "_".join(variable_parts)
	var operator = parts[operator_index]
	var value_parts = parts.slice(operator_index + 1)
	var value_str = "_".join(value_parts)

	# Get variable value from context
	if not context.has(variable_name):
		return false

	var variable_value = context[variable_name]

	# Handle modulo operator specially
	if operator == "mod":
		# Format: "turn_number_mod_5_equals_0"
		if value_parts.size() < 3:
			return false
		var mod_value = int(value_parts[0])
		var mod_operator = value_parts[1]
		var mod_result = int(value_parts[2])

		if mod_operator == "equals":
			return (int(variable_value) % mod_value) == mod_result
		return false

	# Parse value
	var comparison_value = int(value_str) if value_str.is_valid_int() else value_str

	# Evaluate condition
	match operator:
		"below":
			return variable_value < comparison_value
		"above":
			return variable_value > comparison_value
		"equals":
			return variable_value == comparison_value

	return false

func _load_marker_positions() -> bool:
	"""Load character marker positions from character_marker_positions.csv"""
	var file = FileAccess.open(MARKER_POSITIONS_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleFlowConfigLoader] Cannot open file: %s" % MARKER_POSITIONS_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read each line
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() < 22 or line[0].strip_edges() == "":
			continue

		var position_id = int(line[0].strip_edges())
		var side = line[1].strip_edges()
		var position_index = int(line[2].strip_edges())

		var position_config = {
			"position_id": position_id,
			"side": side,
			"position_index": position_index,
			"position_name": line[3].strip_edges(),
			"sprite_x": float(line[4].strip_edges()),
			"sprite_y": float(line[5].strip_edges()),
			"sprite_scale": float(line[6].strip_edges()),
			"x_offset": float(line[7].strip_edges()),
			"shadow_x": float(line[8].strip_edges()),
			"shadow_y": float(line[9].strip_edges()),
			"shadow_scale_x": float(line[10].strip_edges()),
			"shadow_scale_y": float(line[11].strip_edges()),
			"z_index": int(line[12].strip_edges()),
			"turn_start_anim": line[13].strip_edges(),
			"turn_start_direction": line[14].strip_edges(),
			"turn_end_anim": line[15].strip_edges(),
			"turn_end_direction": line[16].strip_edges(),
			"slide_forward_distance": float(line[17].strip_edges()),
			"slide_forward_duration": float(line[18].strip_edges()),
			"slide_back_distance": float(line[19].strip_edges()),
			"slide_back_duration": float(line[20].strip_edges()),
			"notes": line[21].strip_edges(),
		}

		# Store by key: "side_index" (e.g., "ally_0", "enemy_1")
		var key = "%s_%d" % [side, position_index]
		marker_positions[key] = position_config

	file.close()
	return true

func _load_turn_animation() -> bool:
	"""Load turn indicator animation from turn_indicator_animation.csv"""
	var file = FileAccess.open(TURN_ANIM_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleFlowConfigLoader] Cannot open file: %s" % TURN_ANIM_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read first data line (should only be one config)
	var line = file.get_csv_line()

	if line.size() < 11 or line[0].strip_edges() == "":
		push_error("[BattleFlowConfigLoader] Invalid turn animation config")
		return false

	turn_animation = {
		"animation_id": int(line[0].strip_edges()),
		"animation_name": line[1].strip_edges(),
		"enabled": line[2].strip_edges().to_upper() == "TRUE",
		"slide_distance": float(line[3].strip_edges()),
		"slide_forward_duration": float(line[4].strip_edges()),
		"slide_forward_trans": line[5].strip_edges(),
		"slide_forward_ease": line[6].strip_edges(),
		"slide_back_duration": float(line[7].strip_edges()),
		"slide_back_trans": line[8].strip_edges(),
		"slide_back_ease": line[9].strip_edges(),
		"notes": line[10].strip_edges(),
	}

	file.close()
	return true

func get_marker_position(side: String, index: int) -> Dictionary:
	"""Get position config for a character marker"""
	var key = "%s_%d" % [side, index]
	return marker_positions.get(key, {})

func get_turn_animation() -> Dictionary:
	"""Get turn indicator animation settings"""
	return turn_animation

func reset_event_triggers():
	"""Reset all event trigger tracking"""
	for event in battle_events:
		event.has_triggered = false
