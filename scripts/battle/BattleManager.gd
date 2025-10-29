extends Node
class_name BattleManager

## BattleManager - Turn-Based Combat Controller
## Implements the combat system from Chapter 4 design doc

signal battle_started
signal turn_started(combatant_id: String)
signal turn_ended(combatant_id: String)
signal round_started(round_number: int)
signal round_ended(round_number: int)
signal battle_ended(victory: bool)
signal action_executed(action_data: Dictionary)
signal turn_order_changed  # Emitted when turn order is re-sorted mid-round

## Battle state
enum BattleState {
	NONE,           # No battle active
	INITIALIZING,   # Setting up battle
	ROUND_START,    # Start of round (DoT ticks, buffs expire, etc)
	TURN_ACTIVE,    # A combatant is taking their turn
	ROUND_END,      # End of round processing
	VICTORY,        # Player won
	DEFEAT,         # Player lost
	ESCAPED         # Player ran away
}

var current_state: BattleState = BattleState.NONE
var current_round: int = 0
var current_turn_index: int = 0
var run_attempted_this_round: bool = false  # Track if party tried to run this round

## Battle outcome tracking (for morality system)
var battle_kills: Dictionary = {}  # env_tag -> count (e.g., {"Regular": 2, "Elite": 1})
var battle_captures: Dictionary = {}  # env_tag -> count
var sigils_used_in_battle: Dictionary = {}  # sigil_instance_id -> true (tracks which sigils had skills used)

## Combatants (both allies and enemies)
var combatants: Array[Dictionary] = []  # List of all combatants in battle
var turn_order: Array[Dictionary] = []  # Sorted by initiative

## Burst Gauge (shared across party)
var burst_gauge: int = 0
const BURST_GAUGE_MAX: int = 100
const BURST_GAUGE_PER_ROUND_CAP: int = 25

## Encounter data
var encounter_data: Dictionary = {}
var return_scene: String = ""  # Scene to return to after battle
var battle_rewards: Dictionary = {}  # Rewards calculated at end of battle

## References
@onready var gs = get_node("/root/aGameState")
@onready var combat_profiles = get_node("/root/aCombatProfileSystem")
@onready var stats_system = get_node("/root/aStatsSystem")
@onready var transition_mgr = get_node("/root/aTransitionManager")
@onready var csv_loader = get_node("/root/aCSVLoader")

## Enemy data cache
const ENEMIES_CSV: String = "res://data/actors/enemies.csv"
var _enemy_defs: Dictionary = {}

func _ready() -> void:
	print("[BattleManager] Initialized")
	_load_enemy_definitions()

func _load_enemy_definitions() -> void:
	"""Load enemy definitions from CSV"""
	if not csv_loader or not csv_loader.has_method("load_csv"):
		push_error("[BattleManager] CSV loader not available!")
		return

	if not ResourceLoader.exists(ENEMIES_CSV):
		push_error("[BattleManager] Enemies CSV not found: %s" % ENEMIES_CSV)
		return

	var result = csv_loader.call("load_csv", ENEMIES_CSV, "actor_id")
	if typeof(result) == TYPE_DICTIONARY:
		_enemy_defs = result
		print("[BattleManager] Loaded %d enemy definitions" % _enemy_defs.size())
	else:
		push_error("[BattleManager] Failed to load enemies CSV")

## ═══════════════════════════════════════════════════════════════
## ENCOUNTER TRIGGERING
## ═══════════════════════════════════════════════════════════════

func start_random_encounter(enemy_ids: Array, return_to_scene: String) -> void:
	"""Trigger a random encounter with the given enemies"""
	print("[BattleManager] Starting random encounter: ", enemy_ids)

	return_scene = return_to_scene

	# Build encounter data
	encounter_data = {
		"enemy_ids": enemy_ids,
		"is_boss": false,
		"no_escape": false,
		"capture_base": 35
	}

	# Transition to battle scene
	if transition_mgr:
		await transition_mgr.transition_to_scene("res://scenes/battle/Battle.tscn", 0.5, 0.2, 0.5)
	else:
		get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")

func initialize_battle(ally_party: Array, enemy_list: Array) -> void:
	"""Initialize battle with ally party and enemy list"""
	print("[BattleManager] Initializing battle...")

	current_state = BattleState.INITIALIZING
	current_round = 0
	burst_gauge = 0
	combatants.clear()
	turn_order.clear()
	battle_kills.clear()
	battle_captures.clear()

	# Add allies to combatants
	for i in range(ally_party.size()):
		var ally_id = ally_party[i]
		var ally_data = _create_ally_combatant(ally_id, i)
		combatants.append(ally_data)

	# Add enemies to combatants
	for i in range(enemy_list.size()):
		var enemy_id = enemy_list[i]
		var enemy_data = _create_enemy_combatant(enemy_id, i)
		combatants.append(enemy_data)
		print("[BattleManager] Added enemy: %s [ID: %s]" % [enemy_data.display_name, enemy_data.id])

	# ULTRA FIX: Validate immediately after adding all combatants
	_validate_and_fix_combatants()

	battle_started.emit()
	print("[BattleManager] Battle initialized with %d combatants" % combatants.size())

	# Start first round
	start_round()

## ═══════════════════════════════════════════════════════════════
## ROUND & TURN MANAGEMENT
## ═══════════════════════════════════════════════════════════════

func start_round() -> void:
	"""Start a new round"""
	current_round += 1
	current_state = BattleState.ROUND_START
	print("[BattleManager] === ROUND %d START ===" % current_round)

	# ULTRA FIX: Validate combatants array has no duplicates BEFORE creating turn order
	_validate_and_fix_combatants()

	# Roll initiative for all combatants
	_roll_initiative()

	# Sort turn order by initiative (highest first)
	turn_order = combatants.duplicate()
	turn_order.sort_custom(_sort_by_initiative)
	_remove_turn_order_duplicates()  # Ensure no duplicates in turn order

	# ULTRA FIX: Final validation
	if turn_order.size() != combatants.size():
		push_error("[BattleManager] CRITICAL: turn_order size (%d) != combatants size (%d) after duplicate removal!" % [turn_order.size(), combatants.size()])

	print("[BattleManager] Turn order:")
	for i in range(turn_order.size()):
		var c = turn_order[i]
		print("  %d. %s [ID: %s] (Initiative: %d)" % [i + 1, c.display_name, c.id, c.initiative])

	# Process start-of-round effects (DoT, HoT, buff/debuff duration)
	_process_round_start_effects()

	# Emit signal AFTER turn order is calculated so UI can display it
	round_started.emit(current_round)

	# Wait for turn order animation to complete
	await _wait_for_turn_order_animation()

	# Start first turn
	current_turn_index = 0
	_next_turn()

func _roll_initiative() -> void:
	"""Roll initiative for all combatants based on TPO"""
	print("[BattleManager] Rolling initiative for %d combatants" % combatants.size())
	for combatant in combatants:
		if combatant.is_ko or combatant.is_fled:
			combatant.initiative = -1
			continue

		# Fallen combatants get 0 initiative (they'll skip their turn)
		if combatant.is_fallen:
			combatant.initiative = 0
			print("[BattleManager] %s [ID: %s] is FALLEN - initiative set to 0" % [combatant.display_name, combatant.id])
			continue

		var tpo = combatant.stats.TPO
		var base_speed = combatant.stats.get("Speed", 0)

		# Add speed buffs/debuffs to speed
		var speed_modifier = get_buff_modifier(combatant, "spd_up")
		speed_modifier += get_buff_modifier(combatant, "spd_down")
		speed_modifier += get_buff_modifier(combatant, "spd")
		speed_modifier += get_buff_modifier(combatant, "speed")

		var total_speed = base_speed + int(speed_modifier)

		# Roll dice based on TPO tier (keep highest)
		var dice_count = 1
		if tpo >= 10:
			dice_count = 4
		elif tpo >= 7:
			dice_count = 3
		elif tpo >= 4:
			dice_count = 2
		else:
			dice_count = 1

		var best_roll = 0
		for i in range(dice_count):
			var roll = randi() % 20 + 1  # 1d20
			if roll > best_roll:
				best_roll = roll

		combatant.initiative = best_roll + total_speed
		if speed_modifier != 0:
			print("[BattleManager] %s [ID: %s] initiative: %dd20(H) = %d + Speed %d (base %d + buff %+d) = %d" % [
				combatant.display_name, combatant.id, dice_count, best_roll, total_speed, base_speed, int(speed_modifier), combatant.initiative
			])
		else:
			print("[BattleManager] %s [ID: %s] initiative: %dd20(H) = %d + Speed %d = %d" % [
				combatant.display_name, combatant.id, dice_count, best_roll, total_speed, combatant.initiative
			])

func _sort_by_initiative(a: Dictionary, b: Dictionary) -> bool:
	"""Sort comparator for initiative (higher first, Fallen above KO'd, KO'd to bottom)"""
	var a_ko = a.get("is_ko", false)
	var b_ko = b.get("is_ko", false)
	var a_fallen = a.get("is_fallen", false)
	var b_fallen = b.get("is_fallen", false)

	# Priority order (highest to lowest):
	# 1. Normal combatants (not KO'd, not Fallen)
	# 2. Fallen combatants (will skip next turn)
	# 3. KO'd combatants (out of battle)

	# If one is KO'd and the other is not, non-KO'd goes first
	if a_ko and not b_ko:
		return false  # a is KO'd, b is not - b goes first
	if not a_ko and b_ko:
		return true  # a is not KO'd, b is - a goes first

	# Both KO'd - sort by initiative (both should be -1 but just in case)
	if a_ko and b_ko:
		return a.initiative > b.initiative

	# Neither KO'd - check fallen status
	# If one is fallen and the other is not, non-fallen goes first
	if a_fallen and not b_fallen:
		return false  # a is Fallen, b is not - b goes first
	if not a_fallen and b_fallen:
		return true  # a is not Fallen, b is - a goes first

	# Both alive or both fallen - sort normally by initiative
	if a.initiative != b.initiative:
		return a.initiative > b.initiative

	# Tiebreaker: TPO
	if a.stats.TPO != b.stats.TPO:
		return a.stats.TPO > b.stats.TPO

	# Tiebreaker: Speed
	var a_speed = a.stats.get("Speed", 0)
	var b_speed = b.stats.get("Speed", 0)
	if a_speed != b_speed:
		return a_speed > b_speed

	# Final tiebreaker: coinflip
	return randf() > 0.5

func _validate_and_fix_combatants() -> void:
	"""ULTRA FIX: Validate combatants array has no duplicates and fix if found"""
	print("[BattleManager] Validating %d combatants..." % combatants.size())
	var seen_ids: Dictionary = {}
	var cleaned: Array[Dictionary] = []
	var duplicates_found: int = 0

	for combatant in combatants:
		var id = combatant.id
		var name = combatant.display_name
		if not seen_ids.has(id):
			seen_ids[id] = true
			cleaned.append(combatant)
			print("[BattleManager]   ✓ %s [ID: %s]" % [name, id])
		else:
			duplicates_found += 1
			push_error("[BattleManager] CRITICAL: Duplicate combatant in combatants array: %s (id: %s)" % [name, id])
			print("[BattleManager]   ✗ DUPLICATE FOUND: %s [ID: %s] - REMOVING!" % [name, id])

	if duplicates_found > 0:
		print("[BattleManager] ULTRA FIX: Removed %d duplicate(s) from combatants array!" % duplicates_found)
		combatants = cleaned
	else:
		print("[BattleManager] Validation complete - no duplicates found")

func _remove_turn_order_duplicates() -> void:
	"""Remove duplicate combatants from turn_order (keep first occurrence)"""
	var seen_ids: Dictionary = {}
	var deduplicated: Array[Dictionary] = []
	var duplicates_found: int = 0

	for combatant in turn_order:
		var id = combatant.id
		if not seen_ids.has(id):
			seen_ids[id] = true
			deduplicated.append(combatant)
		else:
			duplicates_found += 1
			print("[BattleManager] WARNING: Duplicate combatant removed from turn order: %s" % combatant.display_name)

	if duplicates_found > 0:
		print("[BattleManager] Removed %d duplicate(s) from turn order" % duplicates_found)
		turn_order = deduplicated

func _wait_for_turn_order_animation() -> void:
	"""Wait for turn order display animation to complete"""
	# Find TurnOrderDisplay in the scene tree
	var turn_order_display = get_tree().get_first_node_in_group("turn_order_display")
	if not turn_order_display or not is_instance_valid(turn_order_display):
		# No display found, just wait a frame
		await get_tree().process_frame
		return

	# Only wait for animation if one is actually playing
	# Use 'in' operator which works with typed properties in GDScript
	var is_animating = false
	if "is_animating" in turn_order_display:
		is_animating = turn_order_display.is_animating

	if is_animating:
		print("[BattleManager] Animation in progress, waiting for completion...")
		if turn_order_display.has_signal("animation_completed"):
			await turn_order_display.animation_completed
		else:
			await get_tree().process_frame
	else:
		# No animation playing, just proceed
		print("[BattleManager] No animation in progress, proceeding immediately")
		await get_tree().process_frame

func _next_turn() -> void:
	"""Advance to the next combatant's turn"""
	# Find next valid combatant
	while current_turn_index < turn_order.size():
		var combatant = turn_order[current_turn_index]

		# Skip KO'd, fled, or fallen combatants
		if combatant.is_ko or combatant.is_fled:
			current_turn_index += 1
			continue

		# Check if fallen (skip turn, clear flag only after fallen_round completes)
		if combatant.is_fallen:
			var fallen_round = combatant.get("fallen_round", current_round)
			if current_round > fallen_round:
				# We're in the round AFTER they became fallen - clear the flag
				print("[BattleManager] %s is Fallen - skipping turn and clearing status" % combatant.display_name)
				combatant.is_fallen = false
			else:
				# Same round they became fallen - just skip, don't clear yet
				print("[BattleManager] %s is Fallen - skipping remaining turn this round" % combatant.display_name)
			current_turn_index += 1
			continue

		# Skip if they've already acted this round (stumbled but already took their turn)
		if combatant.get("has_acted_this_round", false):
			print("[BattleManager] %s has already acted this round - skipping" % combatant.display_name)
			current_turn_index += 1
			continue

		# Valid combatant found
		_start_turn(combatant)
		return

	# No more valid combatants - end round
	_end_round()

func _start_turn(combatant: Dictionary) -> void:
	"""Start a combatant's turn"""
	# Check for duplicates before starting turn
	_remove_turn_order_duplicates()

	# Check if battle has ended before starting this turn
	if await _check_battle_end():
		return

	# Mark this combatant as having acted this round
	combatant.has_acted_this_round = true

	# Check if combatant has "Revived" status BEFORE processing ailments (can't act this turn)
	var current_ailment = str(combatant.get("ailment", "")).to_lower()
	if current_ailment == "revived":
		print("[BattleManager] %s is still recovering from revival - skipping turn" % combatant.display_name)
		# Clear the revived status so they can act next round
		combatant.ailment = ""
		combatant.ailment_turn_count = 0
		print("[BattleManager] %s has recovered from revival! (can act next turn)" % combatant.display_name)
		refresh_turn_order()
		# Skip to end turn
		end_turn()
		return

	# Process turn-start ailment effects (poison/burn damage, auto-cure rolls, etc.)
	await _process_turn_start_ailments(combatant)

	# Check if combatant was KO'd by ailment damage
	if combatant.is_ko:
		print("[BattleManager] %s was KO'd by ailment - skipping turn" % combatant.display_name)
		# Refresh turn order to show KO
		refresh_turn_order()
		# Skip to end turn
		end_turn()
		return

	# Process buff/debuff durations
	process_buff_durations(combatant)

	# Process regeneration
	await process_regen(combatant)

	current_state = BattleState.TURN_ACTIVE
	print("[BattleManager] --- Turn: %s ---" % combatant.display_name)

	turn_started.emit(combatant.id)

	# AI or player decision happens here (will be handled by Battle scene)

func end_turn() -> void:
	"""End the current turn and move to next"""
	if current_turn_index < turn_order.size():
		var combatant = turn_order[current_turn_index]
		turn_ended.emit(combatant.id)

	# Check if battle has ended (all enemies or allies defeated)
	if await _check_battle_end():
		return

	current_turn_index += 1
	_next_turn()

func _end_round() -> void:
	"""End the current round"""
	current_state = BattleState.ROUND_END
	print("[BattleManager] === ROUND %d END ===" % current_round)

	round_ended.emit(current_round)

	# Check victory/defeat conditions
	if await _check_battle_end():
		return

	# Brief pause between rounds (UI will show round transition animation)
	print("[BattleManager] Pausing 0.5 seconds before next round...")
	await get_tree().create_timer(0.5).timeout

	# Start next round
	start_round()

func _process_round_start_effects() -> void:
	"""Process DoT, HoT, buff durations at start of round"""
	# Reset run attempt flag at start of each round
	run_attempted_this_round = false

	for combatant in combatants:
		if combatant.is_ko or combatant.is_fled:
			continue

		# Reset has_acted flag at start of each round
		combatant.has_acted_this_round = false

		# Reset weapon weakness hit counter at start of each round
		combatant.weapon_weakness_hits = 0

		# Reset mind type change flag (player can change type once per round)
		combatant.changed_type_this_round = false

		# NOTE: is_defending persists across rounds until combatant takes offensive action
		# This provides multi-round defensive stances

		# ═══════ Apply DoT (Damage over Time) - REMOVED ═══════
		# NOTE: Burn/Poison damage moved to _process_turn_start_ailments()
		# DoT now applies at START OF EACH TURN, not at round start
		if combatant.has("ailments"):
			var ailments_to_remove = []
			for ailment_key in combatant.ailments:
				var ailment = combatant.ailments[ailment_key]
				if typeof(ailment) == TYPE_STRING:
					# Legacy string format - convert to dict
					ailment = {"type": ailment, "duration": 0}

				var ailment_type = ailment.get("type", "")

				# Decrement duration (0 = infinite)
				var duration = ailment.get("duration", 0)
				if duration > 0:
					duration -= 1
					if duration <= 0:
						ailments_to_remove.append(ailment_key)
					else:
						ailment["duration"] = duration

			# Remove expired ailments
			for key in ailments_to_remove:
				combatant.ailments.erase(key)

		# ═══════ Apply HoT (Heal over Time) and process buffs ═══════
		if combatant.has("buffs"):
			var buffs_to_remove = []
			for i in range(combatant.buffs.size()):
				var buff = combatant.buffs[i]
				var buff_type = buff.get("type", "")

				# Apply Regen healing
				if buff_type == "regen":
					var heal = int(ceil(combatant.hp_max * 0.05))  # 5% max HP
					var old_hp = combatant.hp
					combatant.hp = min(combatant.hp + heal, combatant.hp_max)
					var actual_heal = combatant.hp - old_hp
					print("[BattleManager] %s regenerates %d HP" % [combatant.display_name, actual_heal])

				# Decrement duration
				var duration = buff.get("duration", 0)
				if duration > 0:
					duration -= 1
					if duration <= 0:
						buffs_to_remove.append(i)
						print("[BattleManager] %s's %s buff expired" % [combatant.display_name, buff_type])
					else:
						buff["duration"] = duration

			# Remove expired buffs (in reverse order to avoid index issues)
			buffs_to_remove.reverse()
			for idx in buffs_to_remove:
				combatant.buffs.remove_at(idx)

		# ═══════ Process debuffs ═══════
		if combatant.has("debuffs"):
			var debuffs_to_remove = []
			for i in range(combatant.debuffs.size()):
				var debuff = combatant.debuffs[i]

				# Decrement duration
				var duration = debuff.get("duration", 0)
				if duration > 0:
					duration -= 1
					if duration <= 0:
						debuffs_to_remove.append(i)
						print("[BattleManager] %s's %s debuff expired" % [combatant.display_name, debuff.get("type", "unknown")])
					else:
						debuff["duration"] = duration

			# Remove expired debuffs (in reverse order)
			debuffs_to_remove.reverse()
			for idx in debuffs_to_remove:
				combatant.debuffs.remove_at(idx)

		# TODO: Resolve channeling (CH1/CH2)

func _process_turn_start_ailments(combatant: Dictionary) -> void:
	"""Process ailment effects at the start of a combatant's turn"""
	var ailment = str(combatant.get("ailment", "")).to_lower()  # Convert to lowercase for consistency

	print("[BattleManager] Processing ailment for %s: '%s'" % [combatant.display_name, ailment])

	if ailment == "" or ailment == "null":
		return

	# Initialize turn counter if not present
	if not combatant.has("ailment_turn_count"):
		combatant.ailment_turn_count = 0

	# Increment turn counter
	combatant.ailment_turn_count += 1
	var turn_count = combatant.ailment_turn_count

	# ═══════ POISON & BURN - Tick damage ═══════
	if ailment in ["poison", "burn"]:
		var damage = int(ceil(combatant.hp_max * 0.08))  # 8% max HP
		combatant.hp = max(0, combatant.hp - damage)
		print("[BattleManager] %s takes %d %s damage (Turn %d)" % [
			combatant.display_name, damage, ailment.capitalize(), turn_count
		])

		# Check for KO from ailment damage
		if combatant.hp <= 0:
			combatant.is_ko = true
			combatant.ailment = "fainted"
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s was KO'd by %s!" % [combatant.display_name, ailment.capitalize()])
			return  # Don't process auto-cure if they died

		# Auto-cure chance: 30% base + 10% per turn (max 90%)
		var cure_chance = min(30 + (turn_count - 1) * 10, 90)
		var roll = randi() % 100

		if roll < cure_chance:
			combatant.ailment = ""
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s recovered from %s! (%d%% chance, rolled %d)" % [
				combatant.display_name, ailment.capitalize(), cure_chance, roll
			])
			refresh_turn_order()
		else:
			print("[BattleManager] %s is still %s (%d%% cure chance, rolled %d)" % [
				combatant.display_name, ailment.capitalize(), cure_chance, roll
			])

	# ═══════ SLEEP - 20% auto-cure (also wakes when hit or item used) ═══════
	elif ailment == "sleep":
		# 20% chance to wake up naturally at start of turn
		var wake_chance = 20
		var roll = randi() % 100

		if roll < wake_chance:
			combatant.ailment = ""
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s woke up naturally! (%d%% chance, rolled %d)" % [
				combatant.display_name, wake_chance, roll
			])
			refresh_turn_order()
		else:
			print("[BattleManager] %s is asleep (%d%% wake chance, rolled %d - skipping turn)" % [
				combatant.display_name, wake_chance, roll
			])
			# Sleep causes the turn to be skipped - handled by Battle.gd

	# ═══════ FREEZE - 20% auto-cure (also cures with Heated Blanket item) ═══════
	elif ailment == "freeze":
		# 20% chance to break free from freeze
		var cure_chance = 20
		var roll = randi() % 100

		if roll < cure_chance:
			combatant.ailment = ""
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s broke free from freeze! (%d%% chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			refresh_turn_order()
		else:
			print("[BattleManager] %s is frozen (30%% action chance, %d%% cure chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			# Freeze allows acting with 30% success - handled by Battle.gd

	# ═══════ MALAISE - 30% action chance, auto-cure escalates ═══════
	elif ailment == "malaise":
		# Auto-cure chance: 30% base + 10% per turn (max 90%)
		var cure_chance = min(30 + (turn_count - 1) * 10, 90)
		var roll = randi() % 100

		if roll < cure_chance:
			combatant.ailment = ""
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s recovered from malaise! (%d%% chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			refresh_turn_order()
		else:
			print("[BattleManager] %s is suffering from malaise (30%% action chance, %d%% cure chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			# Malaise allows acting with 30% success - handled by Battle.gd

	# ═══════ BERSERK - Attacks random target, auto-cure escalates ═══════
	elif ailment == "berserk":
		# Auto-cure chance: 30% base + 10% per turn (max 90%)
		var cure_chance = min(30 + (turn_count - 1) * 10, 90)
		var roll = randi() % 100

		if roll < cure_chance:
			combatant.ailment = ""
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s calmed down from berserk! (%d%% chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			refresh_turn_order()
		else:
			print("[BattleManager] %s is berserk! (will attack random target, %d%% cure chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			# Berserk behavior (attack random target) handled by Battle.gd

	# ═══════ CHARM - Uses healing/buff items on enemy, auto-cure escalates ═══════
	elif ailment == "charm":
		# Auto-cure chance: 30% base + 10% per turn (max 90%)
		var cure_chance = min(30 + (turn_count - 1) * 10, 90)
		var roll = randi() % 100

		if roll < cure_chance:
			combatant.ailment = ""
			combatant.ailment_turn_count = 0
			print("[BattleManager] %s broke free from charm! (%d%% chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			refresh_turn_order()
		else:
			print("[BattleManager] %s is charmed! (will aid enemy, %d%% cure chance, rolled %d)" % [
				combatant.display_name, cure_chance, roll
			])
			# Charm behavior (use heal/buff items on enemy) handled by Battle.gd

	# ═══════ REVIVED - Handled before ailment processing (see _start_turn) ═══════
	# Note: Revived status is checked and cleared in _start_turn() BEFORE this function is called,
	# so we should never reach this point with a "revived" ailment.

	# Small delay for readability
	await get_tree().create_timer(0.3).timeout

## ═══════════════════════════════════════════════════════════════
## BUFF/DEBUFF SYSTEM
## ═══════════════════════════════════════════════════════════════

func apply_buff(combatant: Dictionary, buff_type: String, value: float, duration: int) -> void:
	"""Apply a buff or debuff to a combatant

	Args:
		combatant: Target combatant dictionary
		buff_type: Type of buff (atk_up, atk_down, def_up, def_down, skl_up, skl_down, spd_up, regen, phys_acc, mind_acc, evasion)
		value: Modifier value (e.g., 0.15 for 15% increase, 10 for +10 speed)
		duration: Number of turns the buff lasts
	"""
	# Initialize buffs array if not present
	if not combatant.has("buffs"):
		combatant.buffs = []

	# Check if this buff type already exists - replace it
	for i in range(combatant.buffs.size()):
		if combatant.buffs[i].type == buff_type:
			combatant.buffs[i].duration = duration
			combatant.buffs[i].value = value
			print("[BattleManager] Refreshed %s on %s (%d turns)" % [buff_type, combatant.display_name, duration])
			return

	# Add new buff
	combatant.buffs.append({
		"type": buff_type,
		"value": value,
		"duration": duration
	})
	print("[BattleManager] Applied %s to %s (value: %.2f, duration: %d turns)" % [
		buff_type, combatant.display_name, value, duration
	])

func process_buff_durations(combatant: Dictionary) -> void:
	"""Check for expired buffs (duration is decremented at round start, not turn start)"""
	if not combatant.has("buffs"):
		return

	var expired_buffs = []

	# Check each buff for expiration (but don't decrement - that happens at round start)
	for i in range(combatant.buffs.size()):
		var buff = combatant.buffs[i]

		if buff.duration <= 0:
			expired_buffs.append(i)
			print("[BattleManager] %s on %s expired!" % [buff.type, combatant.display_name])

	# Remove expired buffs (in reverse order to preserve indices)
	for i in range(expired_buffs.size() - 1, -1, -1):
		combatant.buffs.remove_at(expired_buffs[i])

	# Clean up empty array
	if combatant.buffs.is_empty():
		combatant.erase("buffs")

func get_buff_modifier(combatant: Dictionary, buff_type: String) -> float:
	"""Get the total modifier for a specific buff type

	Returns the sum of all matching buffs (e.g., multiple atk_up buffs stack)
	"""
	if not combatant.has("buffs"):
		return 0.0

	var total_mod = 0.0
	for buff in combatant.buffs:
		if buff.type == buff_type:
			total_mod += buff.value

	return total_mod

func process_regen(combatant: Dictionary) -> void:
	"""Process health regeneration buffs at turn start"""
	if not combatant.has("buffs"):
		return

	for buff in combatant.buffs:
		if buff.type == "regen":
			var heal_amount = int(ceil(combatant.hp_max * buff.value))  # buff.value is 0.10 for 10%
			combatant.hp = min(combatant.hp_max, combatant.hp + heal_amount)
			print("[BattleManager] %s regenerates %d HP! (%d turns left)" % [
				combatant.display_name, heal_amount, buff.duration
			])
			await get_tree().create_timer(0.2).timeout

## ═══════════════════════════════════════════════════════════════
## BATTLE END CONDITIONS
## ═══════════════════════════════════════════════════════════════

func _check_battle_end() -> bool:
	"""Check if battle has ended (victory, defeat, or escape)"""
	var allies_alive = _count_alive_allies()
	var enemies_alive = _count_alive_enemies()

	if allies_alive == 0:
		await _end_battle(false)  # Defeat
		return true

	if enemies_alive == 0:
		await _end_battle(true)  # Victory
		return true

	return false

func _count_alive_allies() -> int:
	var count = 0
	for c in combatants:
		if c.is_ally and not c.is_ko and not c.is_fled:
			count += 1
	return count

func _count_alive_enemies() -> int:
	var count = 0
	for c in combatants:
		# Count enemy as defeated if KO'd, fled, or captured
		if not c.is_ally:
			var is_ko = c.is_ko
			var is_fled = c.is_fled
			var is_captured = c.get("is_captured", false)
			print("[BattleManager] Enemy %s: is_ko=%s, is_fled=%s, is_captured=%s" % [c.display_name, is_ko, is_fled, is_captured])
			if not is_ko and not is_fled and not is_captured:
				count += 1
	print("[BattleManager] _count_alive_enemies() = %d" % count)
	return count

func _calculate_battle_rewards() -> Dictionary:
	"""
	Calculate all battle rewards: LXP, GXP, AXP, Creds, Items
	Returns Dictionary with reward breakdown for display
	"""
	var rewards = {
		"lxp_awarded": {},  # member_id -> xp_amount
		"gxp_awarded": {},  # sigil_instance_id -> gxp_amount
		"axp_awarded": {},  # "memberA|memberB" -> axp_amount
		"creds": 0,
		"items": [],  # Array of item_ids dropped
		"captured_count": 0,
		"killed_count": 0
	}

	# Count captures vs kills
	for count in battle_captures.values():
		rewards.captured_count += count
	for count in battle_kills.values():
		rewards.killed_count += count

	# Calculate base XP from all defeated enemies
	var base_xp: int = 0
	var total_creds: int = 0
	var dropped_items: Array = []

	for enemy in combatants:
		if enemy.is_ally:
			continue
		if not enemy.get("is_ko", false) and not enemy.get("is_captured", false):
			continue  # Enemy wasn't defeated

		# XP based on enemy level
		var enemy_level: int = enemy.get("level", 1)
		var enemy_xp: int = enemy_level * 10  # Base formula: 10 XP per level
		base_xp += enemy_xp

		# Creds calculation
		var cred_range: String = enemy.get("cred_range", "10-20")
		var was_captured: bool = enemy.get("is_captured", false)
		var cred_multiplier: float = 1.5 if was_captured else 1.0
		var creds_from_enemy: int = _roll_creds_from_range(cred_range, cred_multiplier)
		total_creds += creds_from_enemy

		# Item drops
		var drop_table: String = enemy.get("drop_table", "")
		if drop_table != "":
			var drop_multiplier: float = 1.5 if was_captured else 1.0
			var dropped_item: String = _roll_item_drop(drop_table, drop_multiplier)
			if dropped_item != "":
				dropped_items.append(dropped_item)

	rewards.creds = total_creds
	rewards.items = dropped_items

	# Award Creds to GameState
	if total_creds > 0 and gs and gs.has_method("add_creds"):
		gs.add_creds(total_creds)
		print("[BattleManager] Awarded %d creds" % total_creds)

	# Award Items to Inventory
	var inv_sys = get_node_or_null("/root/aInventorySystem")
	if inv_sys:
		for item_id in dropped_items:
			inv_sys.add_item(item_id, 1)
			print("[BattleManager] Dropped item: %s" % item_id)

	# Distribute LXP to party members
	print("[BattleManager] Starting LXP distribution, base_xp: %d" % base_xp)

	if base_xp > 0:
		# Award LXP to all ally combatants (they're already in the battle)
		for combatant in combatants:
			if not combatant.is_ally:
				continue

			var member_id = combatant.get("id", "")
			if member_id == "":
				continue

			print("[BattleManager] Processing member: %s" % member_id)
			var xp_amount: int = 0

			# Check if KO'd for 50% XP penalty
			if combatant.get("is_ko", false):
				# Fainted - 50% XP
				xp_amount = int(base_xp * 0.5)
				print("[BattleManager] Member is KO'd, awarding 50%% XP")
			else:
				# Active and not KO'd - 100% XP
				xp_amount = base_xp
				print("[BattleManager] Member is active, awarding 100%% XP")

			print("[BattleManager] Calculated xp_amount: %d for %s" % [xp_amount, member_id])
			print("[BattleManager] stats_system exists: %s, has add_xp: %s" % [stats_system != null, stats_system.has_method("add_xp") if stats_system else false])

			if xp_amount > 0 and stats_system and stats_system.has_method("add_xp"):
				stats_system.add_xp(member_id, xp_amount)
				rewards.lxp_awarded[member_id] = xp_amount
				print("[BattleManager] Awarded %d LXP to %s" % [xp_amount, member_id])
			else:
				print("[BattleManager] SKIPPED awarding LXP (xp_amount=%d, stats_system=%s)" % [xp_amount, "exists" if stats_system else "null"])
	else:
		print("[BattleManager] SKIPPED entire LXP section (base_xp=%d)" % base_xp)

	# Award GXP to all equipped sigils
	var sigil_sys = get_node_or_null("/root/aSigilSystem")
	if sigil_sys and base_xp > 0:
		var gxp_per_sigil: int = int(base_xp * 0.5)  # Sigils get 50% of base XP

		# Find all equipped sigils for active party members
		for combatant in combatants:
			if not combatant.is_ally:
				continue

			var member_id: String = combatant.get("id", "")
			var sigils: Array = combatant.get("sigils", [])

			for sigil_inst_id in sigils:
				if sigil_inst_id == "":
					continue

				# Base GXP for equipped sigils
				var gxp_to_award = gxp_per_sigil

				# Bonus +5 GXP if sigil's skill was actually used in battle
				if sigils_used_in_battle.has(sigil_inst_id):
					gxp_to_award += 5
					print("[BattleManager] +5 GXP bonus for sigil usage: %s" % sigil_inst_id)

				# Award GXP to this sigil instance
				sigil_sys.add_xp_to_instance(sigil_inst_id, gxp_to_award, false, "battle_reward")
				rewards.gxp_awarded[sigil_inst_id] = gxp_to_award
				print("[BattleManager] Awarded %d GXP to sigil %s" % [gxp_to_award, sigil_inst_id])

	# Award AXP (Affinity XP) for co-presence
	var affinity_sys = get_node_or_null("/root/aAffinitySystem")
	if affinity_sys:
		print("[BattleManager] Calculating AXP for co-presence...")

		# Get all ally combatants who participated
		var ally_combatants: Array = []
		for combatant in combatants:
			if combatant.is_ally:
				ally_combatants.append(combatant)

		# Calculate AXP for each pair
		for i in range(ally_combatants.size()):
			for j in range(i + 1, ally_combatants.size()):
				var member_a = ally_combatants[i].get("id", "")
				var member_b = ally_combatants[j].get("id", "")

				if member_a == "" or member_b == "":
					continue

				# Check KO status
				var a_ko = ally_combatants[i].get("is_ko", false)
				var b_ko = ally_combatants[j].get("is_ko", false)

				var axp_amount = 0
				var status_desc = ""

				if not a_ko and not b_ko:
					# Both active at battle end: +2 AXP
					axp_amount = 2
					status_desc = "both active"
				elif a_ko != b_ko:
					# One KO'd, one standing: +1 AXP
					axp_amount = 1
					status_desc = "one KO'd"
				else:
					# Both KO'd: +0 AXP (no co-presence)
					axp_amount = 0
					status_desc = "both KO'd"

				if axp_amount > 0:
					var actual = affinity_sys.add_copresence_axp(member_a, member_b, axp_amount)
					if actual > 0:
						# Create pair key for display (alphabetically sorted)
						var pair_key = affinity_sys._make_pair_key(member_a, member_b)
						rewards.axp_awarded[pair_key] = actual
						print("[BattleManager] Awarded %d AXP to %s (%s)" % [actual, pair_key, status_desc])
					else:
						print("[BattleManager] Daily cap reached for %s|%s, no AXP awarded" % [member_a, member_b])
				else:
					print("[BattleManager] No AXP for %s|%s (%s)" % [member_a, member_b, status_desc])

	return rewards

func _find_combatant_by_id(member_id: String) -> Dictionary:
	"""Find a combatant by their member ID"""
	for c in combatants:
		if c.get("id", "") == member_id:
			return c
	return {}

func _roll_creds_from_range(cred_range: String, multiplier: float = 1.0) -> int:
	"""Roll credits from a range string like '10-20'"""
	var parts = cred_range.split("-")
	if parts.size() != 2:
		return 0

	var min_cred: int = parts[0].to_int()
	var max_cred: int = parts[1].to_int()
	var rolled: int = randi_range(min_cred, max_cred)
	return int(rolled * multiplier)

func _roll_item_drop(drop_table: String, multiplier: float = 1.0) -> String:
	"""Roll for an item drop from a drop table"""
	if drop_table == "" or drop_table == "None":
		return ""

	# Load drop table data from CSV
	var drop_table_path = "res://data/items/drop_tables.csv"

	# Check if drop tables file exists
	if not ResourceLoader.exists(drop_table_path):
		print("[BattleManager] Drop tables CSV not found at %s" % drop_table_path)
		return ""

	# Load the drop table CSV
	var drop_data = csv_loader.load_csv(drop_table_path, "drop_table_id")
	if drop_data.is_empty():
		print("[BattleManager] Failed to load drop tables")
		return ""

	# Collect all entries for this drop table
	var table_entries: Array = []
	for row_key in drop_data.keys():
		var row = drop_data[row_key]
		var table_id = str(row.get("drop_table_id", ""))
		if table_id == drop_table:
			table_entries.append(row)

	if table_entries.is_empty():
		print("[BattleManager] No entries found for drop table: %s" % drop_table)
		return ""

	# Roll for each possible drop in the table
	for entry in table_entries:
		var item_id = str(entry.get("item_id", ""))
		var drop_rate = float(entry.get("drop_rate", 0.0))
		var min_qty = int(entry.get("min_qty", 1))
		var max_qty = int(entry.get("max_qty", 1))

		# Apply multiplier to drop rate (captures get better drops)
		var final_rate = drop_rate * multiplier

		# Roll for this item
		if randf() < final_rate:
			# Success! This item dropped
			var qty = randi_range(min_qty, max_qty)
			print("[BattleManager] Item drop: %s x%d (rate: %.1f%%)" % [item_id, qty, final_rate * 100])

			# For now, return just the item_id (quantity handling can be added later)
			return item_id

	# No items dropped
	return ""

func _end_battle(victory: bool) -> void:
	"""End the battle"""
	# Wait for any ongoing animations to complete before ending
	print("[BattleManager] Waiting for animations to complete before ending battle...")
	await _wait_for_turn_order_animation()

	if victory:
		print("[BattleManager] *** VICTORY ***")
		current_state = BattleState.VICTORY

		# Calculate and award battle rewards
		print("[BattleManager] Calculating battle rewards...")
		battle_rewards = _calculate_battle_rewards()
		print("[BattleManager] Rewards calculated successfully")

		# Apply morality deltas for battle outcomes
		print("[BattleManager] Applying morality...")
		_apply_morality_for_battle()
		print("[BattleManager] Morality applied")
	else:
		print("[BattleManager] *** DEFEAT ***")
		current_state = BattleState.DEFEAT

	# Save HP/MP for all party members and clear status effects
	_save_party_hp_mp_and_clear_status(victory)

	print("[BattleManager] Emitting battle_ended signal...")
	battle_ended.emit(victory)
	print("[BattleManager] Battle ended signal emitted")

func _save_party_hp_mp_and_clear_status(victory: bool) -> void:
	"""
	Save HP/MP for all party members after battle and clear status effects

	HP/MP Persistence Rules:
	- HP and MP values persist from battle to field
	- If a party member was KO'd in battle but won, they revive with 1 HP
	- Status effects (burn, poison, buffs, debuffs) do NOT persist to field
	"""
	print("[BattleManager] Saving party HP/MP and clearing status effects...")

	# Get all ally combatants
	var ally_combatants = get_ally_combatants()

	# Check if GameState is available
	if not gs:
		push_error("[BattleManager] GameState not available - cannot save HP/MP!")
		return

	# Get or create member_data - ensure it exists in GameState FIRST
	var member_data: Dictionary = {}
	if "member_data" in gs:
		var existing_data = gs.get("member_data")
		if typeof(existing_data) == TYPE_DICTIONARY:
			member_data = existing_data
		else:
			# member_data exists but is wrong type, reset it
			print("[BattleManager] WARNING: member_data exists but is not a Dictionary, resetting")
			gs.set("member_data", {})
			member_data = {}
	else:
		# member_data doesn't exist, create it
		print("[BattleManager] Creating new member_data in GameState")
		gs.set("member_data", {})
		member_data = {}

	# Save HP/MP for each party member
	for combatant in ally_combatants:
		var member_id: String = combatant.get("id", "")
		if member_id == "":
			continue

		# Ensure member record exists
		if not member_data.has(member_id):
			member_data[member_id] = {}

		var member_rec: Dictionary = member_data[member_id]

		# Handle HP persistence
		if victory:
			# Victory: Save current HP, but revive KO'd members with 1 HP
			if combatant.get("is_ko", false):
				member_rec["hp"] = 1
				print("[BattleManager] %s was KO'd but won - reviving with 1 HP" % combatant.display_name)
			else:
				member_rec["hp"] = max(1, combatant.get("hp", combatant.get("hp_max", 100)))
				print("[BattleManager] %s HP saved: %d/%d" % [combatant.display_name, member_rec["hp"], combatant.get("hp_max", 100)])
		else:
			# Defeat: Save current HP (including 0 if KO'd)
			member_rec["hp"] = max(0, combatant.get("hp", combatant.get("hp_max", 100)))
			print("[BattleManager] %s HP saved after defeat: %d/%d" % [combatant.display_name, member_rec["hp"], combatant.get("hp_max", 100)])

		# Save MP persistence (always save current MP)
		member_rec["mp"] = max(0, combatant.get("mp", combatant.get("mp_max", 20)))
		print("[BattleManager] %s MP saved: %d/%d" % [combatant.display_name, member_rec["mp"], combatant.get("mp_max", 20)])

		# Clear all status effects (they do NOT persist to field)
		member_rec["buffs"] = []
		member_rec["debuffs"] = []
		member_rec["ailment"] = ""

		# Save back to member_data
		member_data[member_id] = member_rec

	# Update GameState with the modified member_data
	gs.set("member_data", member_data)
	print("[BattleManager] Updated GameState.member_data with HP/MP values")

	# Verify the data was saved correctly
	var verify_data = gs.get("member_data")
	if typeof(verify_data) == TYPE_DICTIONARY:
		print("[BattleManager] Verification - member_data in GameState: %s" % verify_data)
	else:
		push_error("[BattleManager] ERROR: member_data was not saved correctly!")

	# Update CombatProfileSystem so it reflects the new HP/MP values
	if combat_profiles and combat_profiles.has_method("refresh_all"):
		combat_profiles.refresh_all()
		print("[BattleManager] Refreshed CombatProfileSystem")

	print("[BattleManager] HP/MP persistence and status clearing completed")

func _is_all_captures() -> bool:
	"""Check if all enemies were captured (none were killed)"""
	# Count total defeats
	var total_kills = 0
	for count in battle_kills.values():
		total_kills += count

	var total_captures = 0
	for count in battle_captures.values():
		total_captures += count

	# All captures means: at least 1 capture AND zero kills
	return total_captures > 0 and total_kills == 0

func record_enemy_defeat(enemy: Dictionary, was_captured: bool) -> void:
	"""
	Record enemy defeat for morality tracking

	Args:
	  - enemy: Enemy combatant dictionary with env_tag
	  - was_captured: true if captured, false if killed
	"""
	var env_tag: String = enemy.get("env_tag", "Regular")

	if was_captured:
		battle_captures[env_tag] = battle_captures.get(env_tag, 0) + 1
		print("[BattleManager] Recorded capture: %s (%s)" % [enemy.display_name, env_tag])
	else:
		battle_kills[env_tag] = battle_kills.get(env_tag, 0) + 1
		print("[BattleManager] Recorded kill: %s (%s)" % [enemy.display_name, env_tag])

func _apply_morality_for_battle() -> void:
	"""Apply morality deltas based on battle outcomes (kills vs captures)"""
	var morality_sys = get_node_or_null("/root/aMoralitySystem")
	if not morality_sys:
		print("[BattleManager] MoralitySystem not available, skipping morality application")
		return

	# NOTE: VR battle check will be added here later
	# For now, apply morality for all battles

	# Apply kill penalties
	for env_tag in battle_kills:
		var count: int = battle_kills[env_tag]
		var delta_per_kill: int = 0

		match env_tag:
			"Regular":
				delta_per_kill = morality_sys.DELTA_REGULAR_LETHAL  # -1
			"Elite":
				delta_per_kill = morality_sys.DELTA_ELITE_LETHAL    # -3
			"Boss":
				delta_per_kill = morality_sys.DELTA_BOSS_LETHAL      # -15

		if delta_per_kill != 0:
			for i in range(count):
				morality_sys.apply_delta(delta_per_kill, "Killed %s enemy" % env_tag)

	# Apply capture bonuses
	for env_tag in battle_captures:
		var count: int = battle_captures[env_tag]
		var delta_per_capture: int = 0

		match env_tag:
			"Regular":
				delta_per_capture = morality_sys.DELTA_REGULAR_NONLETHAL  # +1
			"Elite":
				delta_per_capture = morality_sys.DELTA_ELITE_NONLETHAL    # +3
			"Boss":
				delta_per_capture = morality_sys.DELTA_BOSS_NONLETHAL      # +15

		if delta_per_capture != 0:
			for i in range(count):
				morality_sys.apply_delta(delta_per_capture, "Captured %s enemy" % env_tag)

	print("[BattleManager] Applied morality: Kills=%s, Captures=%s" % [battle_kills, battle_captures])

func return_to_overworld() -> void:
	"""Return to the overworld scene"""
	# Re-enable encounters for the player
	var scene_path = return_scene if return_scene != "" else "res://scenes/main/Main.tscn"

	if transition_mgr:
		await transition_mgr.transition_to_scene(scene_path, 0.5, 0.2, 0.5)
	else:
		get_tree().change_scene_to_file(scene_path)

	# Re-enable encounters after returning
	await get_tree().process_frame
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("enable_encounters"):
		player.enable_encounters()

## ═══════════════════════════════════════════════════════════════
## COMBATANT CREATION
## ═══════════════════════════════════════════════════════════════

func _create_ally_combatant(member_id: String, slot: int) -> Dictionary:
	"""Create a combatant dictionary for an ally"""
	# DEBUG: Check what's in GameState.member_data before creating combatant
	if gs and "member_data" in gs:
		var md = gs.get("member_data")
		if typeof(md) == TYPE_DICTIONARY and md.has(member_id):
			print("[BattleManager] GameState.member_data[%s] BEFORE profile: %s" % [member_id, md[member_id]])
		else:
			print("[BattleManager] GameState.member_data does NOT have %s" % member_id)

	# Build stats dictionary manually
	var stats = {
		"BRW": stats_system.get_member_stat_level(member_id, "BRW"),
		"VTL": stats_system.get_member_stat_level(member_id, "VTL"),
		"TPO": stats_system.get_member_stat_level(member_id, "TPO"),
		"FCS": stats_system.get_member_stat_level(member_id, "FCS"),
		"MND": stats_system.get_member_stat_level(member_id, "MND"),
		"Speed": 0
	}

	# Get combat profile
	var profile = combat_profiles.get_profile(member_id)
	var hp_current = int(profile.get("hp", profile.get("hp_max", 100)))
	var hp_max = int(profile.get("hp_max", 100))
	var mp_current = int(profile.get("mp", profile.get("mp_max", 20)))
	var mp_max = int(profile.get("mp_max", 20))

	print("[BattleManager] Creating ally combatant %s: HP=%d/%d, MP=%d/%d (from profile)" % [member_id, hp_current, hp_max, mp_current, mp_max])

	# Get display name
	var display_name = stats_system.get_member_display_name(member_id)

	# Get mind type from GameState or default to "none"
	var mind_type = "none"
	if member_id == "hero" and gs and gs.has_meta("hero_active_type"):
		mind_type = String(gs.get_meta("hero_active_type")).to_lower()
	elif stats_system and stats_system.has_method("get_member_mind_type"):
		mind_type = String(stats_system.get_member_mind_type(member_id)).to_lower()

	# Get equipment from EquipmentSystem
	var equipment_dict = {
		"weapon": "",
		"armor": "",
		"head": "",
		"foot": "",
		"bracelet": ""
	}
	if has_node("/root/aEquipmentSystem"):
		var equip_sys = get_node("/root/aEquipmentSystem")
		if equip_sys.has_method("get_member_equip"):
			var member_equip = equip_sys.get_member_equip(member_id)
			if member_equip and not member_equip.is_empty():
				equipment_dict = member_equip
				print("[BattleManager] Loaded equipment for %s: %s" % [member_id, equipment_dict])

	# Get sigils from SigilSystem
	var sigils: Array = []
	var skills: Array = []
	if has_node("/root/aSigilSystem"):
		var sigil_sys = get_node("/root/aSigilSystem")
		var loadout = sigil_sys.get_loadout(member_id)
		for sigil_inst in loadout:
			if sigil_inst != "":
				sigils.append(sigil_inst)
				# Get the active skill for this sigil instance
				var skill_id = sigil_sys.get_active_skill_id_for_instance(sigil_inst)
				if skill_id != "":
					skills.append(skill_id)
		print("[BattleManager] Loaded sigils for %s: %s" % [member_id, sigils])
		print("[BattleManager] Loaded skills for %s: %s" % [member_id, skills])

	return {
		"id": member_id,
		"display_name": display_name,
		"is_ally": true,
		"slot": slot,  # 0, 1, 2 for left/center/right
		"level": stats_system.get_member_level(member_id),
		"stats": stats,
		"hp": hp_current,
		"hp_max": hp_max,
		"mp": mp_current,
		"mp_max": mp_max,
		"initiative": 0,
		"is_ko": false,
		"is_fled": false,
		"is_fallen": false,
		"fallen_round": 0,  # Track which round they became fallen
		"is_defending": false,
		"is_channeling": false,
		"channel_data": {},
		"buffs": [],
		"debuffs": [],
		"ailments": [],
		"mind_type": mind_type,
		"equipment": equipment_dict,
		"weapon_weakness_hits": 0,  # Track weapon triangle weakness hits per round
		"changed_type_this_round": false,  # Track if player changed type this round
		"has_acted_this_round": false,  # Track if combatant has already acted this round
		"sigils": sigils,  # Sigil instances equipped
		"skills": skills   # Active skill IDs for each sigil
	}

func _create_enemy_combatant(enemy_id: String, slot: int) -> Dictionary:
	"""Create a combatant dictionary for an enemy using CSV data"""
	# Load enemy definition from CSV
	var enemy_def: Dictionary = {}
	if _enemy_defs.has(enemy_id):
		enemy_def = _enemy_defs[enemy_id]
	else:
		push_error("[BattleManager] Enemy '%s' not found in enemies.csv" % enemy_id)
		# Return basic fallback
		enemy_def = {
			"name": enemy_id.capitalize(),
			"level_start": 1,
			"start_brw": 1, "start_mnd": 1, "start_tpo": 1, "start_vtl": 1, "start_fcs": 1,
			"mind_type": "none"
		}

	# Parse stats from CSV
	var level = int(enemy_def.get("level_start", 1))
	var enemy_stats = {
		"BRW": int(enemy_def.get("start_brw", 1)),
		"VTL": int(enemy_def.get("start_vtl", 1)),
		"TPO": int(enemy_def.get("start_tpo", 1)),
		"FCS": int(enemy_def.get("start_fcs", 1)),
		"MND": int(enemy_def.get("start_mnd", 1)),
		"Speed": 0
	}

	# Calculate HP/MP using same formula as allies
	var hp_max = 30 + (enemy_stats.VTL * level * 6)
	var mp_max = 20 + int(round(float(enemy_stats.FCS) * float(level) * 1.5))

	# Parse equipment
	var weapon_id = String(enemy_def.get("start_weapon", ""))
	var armor_id = String(enemy_def.get("start_armor", ""))
	var head_id = String(enemy_def.get("start_head", ""))
	var foot_id = String(enemy_def.get("start_foot", ""))
	var bracelet_id = String(enemy_def.get("start_bracelet", ""))

	# Parse sigils and skills (semicolon-separated lists)
	var sigils_str = String(enemy_def.get("start_sigils", ""))
	var skills_str = String(enemy_def.get("start_skills", ""))
	var sigils = sigils_str.split(";", false) if sigils_str != "" else []
	var skills = skills_str.split(";", false) if skills_str != "" else []

	# Get mind type
	var mind_type = String(enemy_def.get("mind_type", "none")).to_lower()

	# Create unique instance ID by appending slot number
	var instance_id = "%s_%d" % [enemy_id, slot]

	return {
		"id": instance_id,
		"display_name": String(enemy_def.get("name", enemy_id.capitalize())),
		"is_ally": false,
		"slot": slot,  # 0, 1, 2 for left/center/right
		"level": level,
		"stats": enemy_stats,
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max,
		"initiative": 0,
		"is_ko": false,
		"is_fled": false,
		"is_captured": false,  # Captured via Bind
		"is_fallen": false,
		"fallen_round": 0,  # Track which round they became fallen
		"is_defending": false,
		"is_channeling": false,
		"channel_data": {},
		"buffs": [],
		"debuffs": [],
		"ailments": [],
		# Enemy-specific data
		"mind_type": mind_type,
		"equipment": {
			"weapon": weapon_id,
			"armor": armor_id,
			"head": head_id,
			"foot": foot_id,
			"bracelet": bracelet_id
		},
		"sigils": sigils,
		"skills": skills,
		"is_boss": String(enemy_def.get("boss_tag", "FALSE")).to_upper() == "TRUE",
		"capture_difficulty": String(enemy_def.get("capture_tag", "None")),
		"capture_resist": int(enemy_def.get("capture_resist", 25)),  # 0-60 resistance
		"env_tag": String(enemy_def.get("env_tag", "Regular")),  # Regular/Elite/Boss for morality
		"cred_range": String(enemy_def.get("cred_range", "0-0")),
		"drop_table": String(enemy_def.get("item_drops", "")),
		"weapon_weakness_hits": 0,  # Track weapon triangle weakness hits per round
		"has_acted_this_round": false  # Track if combatant has already acted this round
	}

## ═══════════════════════════════════════════════════════════════
## WEAPON WEAKNESS TRACKING
## ═══════════════════════════════════════════════════════════════

func record_weapon_weakness_hit(target: Dictionary) -> bool:
	"""
	Record a weapon weakness hit on a target

	Applies initiative penalty and re-sorts turn order

	Returns:
		true if target becomes Fallen (2+ hits this round)
	"""
	# If already fallen, they can't become fallen again this round
	if target.get("is_fallen", false):
		print("[BattleManager] %s is already Fallen - no additional effect" % target.display_name)
		return false

	if not target.has("weapon_weakness_hits"):
		target.weapon_weakness_hits = 0

	target.weapon_weakness_hits += 1
	print("[BattleManager] %s weapon weakness hits: %d/2" % [target.display_name, target.weapon_weakness_hits])

	# Apply initiative penalty (push back in turn order)
	const INITIATIVE_PENALTY: int = 5  # Lose 5 initiative per weakness hit
	target.initiative -= INITIATIVE_PENALTY
	print("[BattleManager] %s initiative reduced by %d (now %d)" % [target.display_name, INITIATIVE_PENALTY, target.initiative])

	# Store current combatant ID before re-sorting
	var current_combatant_id: String = ""
	if current_turn_index < turn_order.size():
		current_combatant_id = turn_order[current_turn_index].id

	# Re-sort turn order to reflect initiative changes
	turn_order.sort_custom(_sort_by_initiative)
	_remove_turn_order_duplicates()  # Ensure no duplicates in turn order
	print("[BattleManager] Turn order re-sorted after weakness hit")

	# Update current_turn_index to point to the same combatant after re-sort
	if current_combatant_id != "":
		for i in range(turn_order.size()):
			if turn_order[i].id == current_combatant_id:
				current_turn_index = i
				break

	# Emit signal so UI can update
	turn_order_changed.emit()

	# Wait for animation to complete
	await _wait_for_turn_order_animation()

	# Check if target should become Fallen (lose rest of this turn + next turn)
	if target.weapon_weakness_hits >= 2:
		target.is_fallen = true
		target.fallen_round = current_round  # Track which round they became fallen
		print("[BattleManager] %s is FALLEN! (will skip rest of this turn and next turn)" % target.display_name)
		return true

	return false

func refresh_turn_order() -> void:
	"""Re-sort turn order and emit signal (used when combatant state changes like KO)"""
	# ULTRA FIX: Validate combatants array first
	_validate_and_fix_combatants()

	# Store current combatant ID before re-sorting
	var current_combatant_id: String = ""
	if current_turn_index < turn_order.size():
		current_combatant_id = turn_order[current_turn_index].id

	# Re-sort the turn order
	turn_order.sort_custom(_sort_by_initiative)
	_remove_turn_order_duplicates()  # Ensure no duplicates in turn order
	print("[BattleManager] Turn order re-sorted")

	# Update current_turn_index to point to the same combatant after re-sort
	if current_combatant_id != "":
		for i in range(turn_order.size()):
			if turn_order[i].id == current_combatant_id:
				current_turn_index = i
				print("[BattleManager] Updated current_turn_index to %d to track %s" % [i, current_combatant_id])
				break

	turn_order_changed.emit()

	# Wait for animation to complete
	await _wait_for_turn_order_animation()

## ═══════════════════════════════════════════════════════════════
## BURST GAUGE
## ═══════════════════════════════════════════════════════════════

func add_burst(amount: int) -> void:
	"""Add to the burst gauge"""
	burst_gauge = mini(burst_gauge + amount, BURST_GAUGE_MAX)
	print("[BattleManager] Burst Gauge: %d / %d (+%d)" % [burst_gauge, BURST_GAUGE_MAX, amount])

func can_use_burst(tier: int) -> bool:
	"""Check if burst tier can be used"""
	match tier:
		1: return burst_gauge >= 25  # Single
		2: return burst_gauge >= 55  # Duel
		3: return burst_gauge >= 90  # Omega
	return false

func spend_burst(tier: int) -> bool:
	"""Spend burst gauge for a tier"""
	var cost = 0
	match tier:
		1: cost = 25
		2: cost = 55
		3: cost = 90

	if burst_gauge >= cost:
		burst_gauge -= cost
		print("[BattleManager] Spent %d Burst (remaining: %d)" % [cost, burst_gauge])
		return true
	return false

## ═══════════════════════════════════════════════════════════════
## HELPER FUNCTIONS
## ═══════════════════════════════════════════════════════════════

func get_current_combatant() -> Dictionary:
	"""Get the combatant whose turn it currently is"""
	if current_turn_index < turn_order.size():
		return turn_order[current_turn_index]
	return {}

func get_ally_combatants() -> Array[Dictionary]:
	"""Get all ally combatants"""
	var allies: Array[Dictionary] = []
	for c in combatants:
		if c.is_ally:
			allies.append(c)
	return allies

func get_enemy_combatants() -> Array[Dictionary]:
	"""Get all enemy combatants"""
	var enemies: Array[Dictionary] = []
	for c in combatants:
		if not c.is_ally:
			enemies.append(c)
	return enemies

func get_combatant_by_id(id: String) -> Dictionary:
	"""Get a combatant by ID"""
	for c in combatants:
		if c.id == id:
			return c
	return {}
