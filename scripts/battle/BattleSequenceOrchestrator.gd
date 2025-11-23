extends RefCounted
class_name BattleSequenceOrchestrator

## ═══════════════════════════════════════════════════════════════
## BATTLE SEQUENCE ORCHESTRATOR
## ═══════════════════════════════════════════════════════════════
## Orchestrates tight, polished battle sequences with precise timing
## Handles battle start, turn flow, attacks, and round transitions

const SEQUENCES_PATH = "res://data/combat/battle_sequences.csv"
const MARKER_POSITIONS_PATH = "res://data/combat/battle_marker_positions.csv"
const TIMING_PATH = "res://data/combat/battle_sequence_timing.csv"

## Loaded configuration
var sequences: Dictionary = {}  # {sequence_name: [steps]}
var marker_positions: Dictionary = {}  # {side_index: marker_config}
var timings: Dictionary = {}  # {event_name: timing_config}

## References (set by Battle.gd)
var battle_scene: Node = null
var sprite_animator = null
var battle_mgr = null

## Current sequence state
var current_sequence: String = ""
var current_step: int = 0
var is_running: bool = false

func load_config() -> bool:
	"""Load all battle sequence configurations"""
	if not _load_sequences():
		push_error("[BattleSequenceOrchestrator] Failed to load sequences")
		return false

	if not _load_marker_positions():
		push_error("[BattleSequenceOrchestrator] Failed to load marker positions")
		return false

	if not _load_timings():
		push_error("[BattleSequenceOrchestrator] Failed to load timings")
		return false

	print("[BattleSequenceOrchestrator] Configuration loaded successfully")
	print("  - %d sequence groups configured" % sequences.size())
	print("  - %d marker positions configured" % marker_positions.size())
	print("  - %d timing configs configured" % timings.size())

	return true

func _load_sequences() -> bool:
	"""Load battle sequences from CSV"""
	var file = FileAccess.open(SEQUENCES_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleSequenceOrchestrator] Cannot open file: %s" % SEQUENCES_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read each line
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() < 14 or line[0].strip_edges() == "":
			continue

		var sequence_name = line[1].strip_edges()
		var phase = line[2].strip_edges()
		var step = int(line[3].strip_edges())

		var step_config = {
			"sequence_id": int(line[0].strip_edges()),
			"sequence_name": sequence_name,
			"phase": phase,
			"step": step,
			"action": line[4].strip_edges(),
			"duration": float(line[5].strip_edges()),
			"fade_duration": float(line[6].strip_edges()),
			"camera_distance": float(line[7].strip_edges()),
			"lock_input": line[8].strip_edges().to_upper() == "TRUE",
			"unlock_input": line[9].strip_edges().to_upper() == "TRUE",
			"text": line[10].strip_edges(),
			"wait_for_input": line[11].strip_edges().to_upper() == "TRUE",
			"enabled": line[12].strip_edges().to_upper() == "TRUE",
			"notes": line[13].strip_edges(),
		}

		# Only add enabled sequences
		if step_config.enabled:
			if not sequences.has(sequence_name):
				sequences[sequence_name] = []
			sequences[sequence_name].append(step_config)

	file.close()

	# Sort each sequence by step number
	for seq_name in sequences.keys():
		sequences[seq_name].sort_custom(func(a, b): return a.step < b.step)

	return true

func _load_marker_positions() -> bool:
	"""Load battle marker positions from CSV"""
	var file = FileAccess.open(MARKER_POSITIONS_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleSequenceOrchestrator] Cannot open file: %s" % MARKER_POSITIONS_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read each line
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() < 9 or line[0].strip_edges() == "":
			continue

		var side = line[1].strip_edges()
		var position_index = int(line[2].strip_edges())

		var marker_config = {
			"marker_id": int(line[0].strip_edges()),
			"side": side,
			"position_index": position_index,
			"marker_name": line[3].strip_edges(),
			"marker_x": float(line[4].strip_edges()),
			"marker_y": float(line[5].strip_edges()),
			"run_duration": float(line[6].strip_edges()),
			"face_direction": line[7].strip_edges(),
			"notes": line[8].strip_edges(),
		}

		# Store by key: "side_index"
		var key = "%s_%d" % [side, position_index]
		marker_positions[key] = marker_config

	file.close()
	return true

func _load_timings() -> bool:
	"""Load sequence timing configs from CSV"""
	var file = FileAccess.open(TIMING_PATH, FileAccess.READ)
	if not file:
		push_error("[BattleSequenceOrchestrator] Cannot open file: %s" % TIMING_PATH)
		return false

	# Skip header
	var header = file.get_csv_line()

	# Read each line
	while not file.eof_reached():
		var line = file.get_csv_line()

		# Skip empty lines
		if line.size() < 7 or line[0].strip_edges() == "":
			continue

		var event_name = line[1].strip_edges()

		timings[event_name] = {
			"timing_id": int(line[0].strip_edges()),
			"event_name": event_name,
			"duration": float(line[2].strip_edges()),
			"fade_duration": float(line[3].strip_edges()),
			"wait_after": float(line[4].strip_edges()),
			"enabled": line[5].strip_edges().to_upper() == "TRUE",
			"notes": line[6].strip_edges(),
		}

	file.close()
	return true

func get_marker_position(side: String, index: int) -> Dictionary:
	"""Get battle marker position for a combatant"""
	var key = "%s_%d" % [side, index]
	return marker_positions.get(key, {})

func get_timing(event_name: String) -> Dictionary:
	"""Get timing config for an event"""
	return timings.get(event_name, {})

## ═══════════════════════════════════════════════════════════════
## SEQUENCE EXECUTION
## ═══════════════════════════════════════════════════════════════

func run_sequence(sequence_name: String, context: Dictionary = {}) -> void:
	"""Run a battle sequence by name"""
	if not sequences.has(sequence_name):
		push_error("[BattleSequenceOrchestrator] Sequence not found: %s" % sequence_name)
		return

	current_sequence = sequence_name
	current_step = 0
	is_running = true

	print("[BattleSequence] Starting sequence: %s" % sequence_name)

	var steps = sequences[sequence_name]
	for step_config in steps:
		if not is_running:
			break

		await _execute_step(step_config, context)

	is_running = false
	print("[BattleSequence] Completed sequence: %s" % sequence_name)

func stop_sequence():
	"""Stop the currently running sequence"""
	is_running = false
	print("[BattleSequence] Sequence stopped: %s" % current_sequence)

func _execute_step(step_config: Dictionary, context: Dictionary):
	"""Execute a single sequence step"""
	var action = step_config.action
	print("[BattleSequence] Step %d: %s" % [step_config.step, action])

	# Handle input locking
	if step_config.lock_input and battle_scene:
		battle_scene._lock_input("Sequence: %s" % current_sequence)

	if step_config.unlock_input and battle_scene:
		battle_scene._unlock_input()

	# Execute the action
	match action:
		"LOCK_INPUT":
			if battle_scene:
				battle_scene._lock_input("Sequence: %s" % current_sequence)

		"UNLOCK_INPUT":
			if battle_scene:
				battle_scene._unlock_input()

		"UNLOCK_ACTION_MENU":
			if battle_scene:
				battle_scene._unlock_input()
				battle_scene._activate_element(battle_scene.BattleElement.ACTION_MENU)

		"FADE_IN_BACKGROUND":
			await _fade_in_background(step_config.fade_duration)

		"FADE_IN_CHARACTERS":
			await _fade_in_characters(step_config.fade_duration)

		"CAMERA_FOCUS_ENEMIES":
			await _camera_focus_enemies(step_config.duration, step_config.camera_distance)

		"SHOW_EXCLAMATION":
			await _show_exclamation(step_config.duration)

		"CAMERA_SLIDE_BACK":
			await _camera_slide_back(step_config.duration)

		"FADE_IN_UI":
			await _fade_in_ui(step_config.fade_duration)

		"SHOW_TEXT":
			if battle_scene:
				var text = _replace_placeholders(step_config.text, context)
				battle_scene.log_message(text)
				if step_config.wait_for_input:
					await battle_scene._wait_for_message_queue()

		"PLACE_TURN_ORDER":
			# Turn order is already placed by battle manager
			await battle_scene.get_tree().process_frame

		"RUN_TO_MARKER":
			await _run_to_marker(context.get("combatant", {}), step_config.duration)

		"FADE_IN_ACTION_MENU":
			await _fade_in_action_menu(step_config.fade_duration)

		"RUN_BACK":
			await _run_back(context.get("combatant", {}), step_config.duration)

		"FACE_FORWARD":
			_face_forward(context.get("combatant", {}))

		"WAIT":
			await battle_scene.get_tree().create_timer(step_config.duration).timeout

		_:
			print("[BattleSequence] Unknown action: %s" % action)

func _replace_placeholders(text: String, context: Dictionary) -> String:
	"""Replace placeholders in text with context values"""
	var result = text

	if context.has("combatant"):
		var combatant = context.combatant
		result = result.replace("[COMBATANT]", combatant.get("display_name", "Unknown"))
		result = result.replace("[ATTACKER]", combatant.get("display_name", "Unknown"))

	if context.has("target"):
		var target = context.target
		result = result.replace("[TARGET]", target.get("display_name", "Unknown"))

	if context.has("round"):
		result = result.replace("[ROUND]", str(context.round))

	if context.has("damage"):
		result = result.replace("[DAMAGE]", str(context.damage))

	return result

## ═══════════════════════════════════════════════════════════════
## SEQUENCE ACTIONS
## ═══════════════════════════════════════════════════════════════

func _fade_in_background(duration: float):
	"""Fade in the battle background"""
	# TODO: Implement background fade
	print("[BattleSequence] Fading in background (%.1fs)" % duration)
	await battle_scene.get_tree().create_timer(duration).timeout

func _fade_in_characters(duration: float):
	"""Fade in all character sprites"""
	# TODO: Implement character fade in
	print("[BattleSequence] Fading in characters (%.1fs)" % duration)
	await battle_scene.get_tree().create_timer(duration).timeout

func _camera_focus_enemies(duration: float, zoom: float):
	"""Pull camera focus to enemies"""
	# TODO: Implement camera zoom/focus
	print("[BattleSequence] Camera focusing on enemies (%.1fs, zoom: %.1f)" % [duration, zoom])
	await battle_scene.get_tree().create_timer(duration).timeout

func _show_exclamation(duration: float):
	"""Show exclamation points over enemies"""
	# TODO: Implement exclamation effects
	print("[BattleSequence] Showing exclamations (%.1fs)" % duration)
	await battle_scene.get_tree().create_timer(duration).timeout

func _camera_slide_back(duration: float):
	"""Slide camera back to normal position"""
	# TODO: Implement camera slide
	print("[BattleSequence] Camera sliding back (%.1fs)" % duration)
	await battle_scene.get_tree().create_timer(duration).timeout

func _fade_in_ui(duration: float):
	"""Fade in UI elements"""
	# TODO: Implement UI fade in
	print("[BattleSequence] Fading in UI (%.1fs)" % duration)
	await battle_scene.get_tree().create_timer(duration).timeout

func _run_to_marker(combatant: Dictionary, duration_override: float = 0.0):
	"""Have character run to their battle marker position"""
	if not sprite_animator or not combatant.has("id"):
		return

	if not sprite_animator.sprite_instances.has(combatant.id):
		return

	# Get combatant's position index
	var combatant_index = battle_scene._get_combatant_position_index(combatant.id)
	var side = "ally" if combatant.is_ally else "enemy"

	# Get marker position
	var marker_config = get_marker_position(side, combatant_index)
	if marker_config.is_empty():
		print("[BattleSequence] No marker position for %s_%d" % [side, combatant_index])
		return

	var attacker_instance = sprite_animator.sprite_instances[combatant.id]
	var attacker_sprite = attacker_instance["sprite"]

	# Get animation direction
	var run_direction = marker_config.get("face_direction", "RIGHT")
	var duration = duration_override if duration_override > 0 else marker_config.get("run_duration", 0.4)

	# Play run animation
	sprite_animator.play_animation(combatant.id, "Run", run_direction, false, false)

	# Move to marker position
	var marker_x = marker_config.get("marker_x", 0.0)
	var current_x = attacker_sprite.position.x
	var target_x = current_x + marker_x

	var tween = battle_scene.create_tween()
	tween.tween_property(attacker_sprite, "position:x", target_x, duration)
	await tween.finished

	# Return to idle
	sprite_animator.play_animation(combatant.id, "Idle", run_direction, false, false)
	print("[BattleSequence] %s ran to battle marker" % combatant.display_name)

func _fade_in_action_menu(duration: float):
	"""Fade in the action menu"""
	if not battle_scene or not battle_scene.action_menu:
		return

	# Start invisible
	battle_scene.action_menu.modulate.a = 0.0
	battle_scene._enable_action_menu()

	# Fade in
	var tween = battle_scene.create_tween()
	tween.tween_property(battle_scene.action_menu, "modulate:a", 1.0, duration)
	await tween.finished

	print("[BattleSequence] Action menu faded in")

func _run_back(combatant: Dictionary, duration_override: float = 0.0):
	"""Have character run back to starting position"""
	if not sprite_animator or not combatant.has("id"):
		return

	await battle_scene._slide_character_back(combatant)
	print("[BattleSequence] %s ran back to starting position" % combatant.display_name)

func _face_forward(combatant: Dictionary):
	"""Turn character to face forward"""
	if not sprite_animator or not combatant.has("id"):
		return

	var idle_direction = "RIGHT" if combatant.is_ally else "LEFT"
	sprite_animator.play_animation(combatant.id, "Idle", idle_direction, false, false)
	print("[BattleSequence] %s facing forward" % combatant.display_name)
