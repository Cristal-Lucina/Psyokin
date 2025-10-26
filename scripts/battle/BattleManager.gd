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

	# Roll initiative for all combatants
	_roll_initiative()

	# Sort turn order by initiative (highest first)
	turn_order = combatants.duplicate()
	turn_order.sort_custom(_sort_by_initiative)
	_remove_turn_order_duplicates()  # Ensure no duplicates in turn order

	print("[BattleManager] Turn order:")
	for i in range(turn_order.size()):
		var c = turn_order[i]
		print("  %d. %s (Initiative: %d)" % [i + 1, c.display_name, c.initiative])

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
	for combatant in combatants:
		if combatant.is_ko or combatant.is_fled:
			combatant.initiative = -1
			continue

		# Fallen combatants get 0 initiative (they'll skip their turn)
		if combatant.is_fallen:
			combatant.initiative = 0
			print("[BattleManager] %s is FALLEN - initiative set to 0" % combatant.display_name)
			continue

		var tpo = combatant.stats.TPO
		var speed = combatant.stats.get("Speed", 0)

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

		combatant.initiative = best_roll + speed
		print("[BattleManager] %s initiative: %dd20(H) = %d + Speed %d = %d" % [
			combatant.display_name, dice_count, best_roll, speed, combatant.initiative
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
	if not turn_order_display:
		# No display found, just wait a frame
		await get_tree().process_frame
		return

	# Wait for animation_completed signal
	if turn_order_display.has_signal("animation_completed"):
		await turn_order_display.animation_completed
	else:
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

		# Check if fallen (skip turn and clear flag)
		if combatant.is_fallen:
			print("[BattleManager] %s is Fallen - skipping turn" % combatant.display_name)
			combatant.is_fallen = false
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
	if _check_battle_end():
		return

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
	if _check_battle_end():
		return

	current_turn_index += 1
	_next_turn()

func _end_round() -> void:
	"""End the current round"""
	current_state = BattleState.ROUND_END
	print("[BattleManager] === ROUND %d END ===" % current_round)

	round_ended.emit(current_round)

	# Check victory/defeat conditions
	if _check_battle_end():
		return

	# Start next round
	start_round()

func _process_round_start_effects() -> void:
	"""Process DoT, HoT, buff durations at start of round"""
	# Reset run attempt flag at start of each round
	run_attempted_this_round = false

	for combatant in combatants:
		if combatant.is_ko or combatant.is_fled:
			continue

		# Reset weapon weakness hit counter at start of each round
		combatant.weapon_weakness_hits = 0

		# Reset mind type change flag (player can change type once per round)
		combatant.changed_type_this_round = false

		# NOTE: is_defending persists across rounds until combatant takes offensive action
		# This provides multi-round defensive stances

		# TODO: Apply DoT (poison = 5% max HP, burn = 5% max HP)
		# TODO: Apply HoT (regen)
		# TODO: Decrement buff/debuff durations
		# TODO: Resolve channeling (CH1/CH2)
		pass

## ═══════════════════════════════════════════════════════════════
## BATTLE END CONDITIONS
## ═══════════════════════════════════════════════════════════════

func _check_battle_end() -> bool:
	"""Check if battle has ended (victory, defeat, or escape)"""
	var allies_alive = _count_alive_allies()
	var enemies_alive = _count_alive_enemies()

	if allies_alive == 0:
		_end_battle(false)  # Defeat
		return true

	if enemies_alive == 0:
		_end_battle(true)  # Victory
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
		if not c.is_ally and not c.is_ko and not c.is_fled:
			count += 1
	return count

func _end_battle(victory: bool) -> void:
	"""End the battle"""
	if victory:
		print("[BattleManager] *** VICTORY ***")
		current_state = BattleState.VICTORY
	else:
		print("[BattleManager] *** DEFEAT ***")
		current_state = BattleState.DEFEAT

	battle_ended.emit(victory)

	# TODO: Award rewards (LXP, money, items)
	# TODO: Show victory/defeat screen

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
		"is_fallen": false,
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
		"cred_range": String(enemy_def.get("cred_range", "0-0")),
		"drop_table": String(enemy_def.get("item_drops", "")),
		"weapon_weakness_hits": 0  # Track weapon triangle weakness hits per round
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

	# Check if target should become Fallen (lose next turn)
	if target.weapon_weakness_hits >= 2:
		target.is_fallen = true
		print("[BattleManager] %s is FALLEN! (will skip next turn)" % target.display_name)
		return true

	return false

func refresh_turn_order() -> void:
	"""Re-sort turn order and emit signal (used when combatant state changes like KO)"""
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
