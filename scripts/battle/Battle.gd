extends Control
class_name Battle

## Battle Scene - Main battle screen controller
## Handles UI, combatant display, and player input for combat

@onready var battle_mgr = get_node("/root/aBattleManager")
@onready var gs = get_node("/root/aGameState")
@onready var combat_resolver: CombatResolver = CombatResolver.new()

## UI References
@onready var action_menu: VBoxContainer = %ActionMenu
@onready var battle_log: RichTextLabel = %BattleLog
@onready var burst_gauge_bar: ProgressBar = %BurstGauge
@onready var turn_order_display: VBoxContainer = %TurnOrderDisplay

## Combatant display containers
@onready var ally_slots: HBoxContainer = %AllySlots
@onready var enemy_slots: HBoxContainer = %EnemySlots

## State
var current_combatant: Dictionary = {}
var awaiting_target_selection: bool = false
var target_candidates: Array = []

func _ready() -> void:
	print("[Battle] Battle scene loaded")

	# Add combat resolver to scene tree
	add_child(combat_resolver)

	# Wait for next frame to ensure all autoloads are ready
	await get_tree().process_frame

	# Connect to battle manager signals
	battle_mgr.battle_started.connect(_on_battle_started)
	battle_mgr.turn_started.connect(_on_turn_started)
	battle_mgr.turn_ended.connect(_on_turn_ended)
	battle_mgr.round_started.connect(_on_round_started)
	battle_mgr.battle_ended.connect(_on_battle_ended)

	# Hide action menu initially
	action_menu.visible = false

	# Initialize battle with party and enemies
	_initialize_battle()

func _initialize_battle() -> void:
	"""Initialize the battle from encounter data"""
	log_message("Battle Start!")

	# Get party from GameState
	var party = gs.party.duplicate()
	if party.is_empty():
		# Fallback: use hero
		party = ["hero"]

	# Get enemies from encounter data
	var enemies = battle_mgr.encounter_data.get("enemy_ids", ["slime"])

	# Initialize battle
	battle_mgr.initialize_battle(party, enemies)

## ═══════════════════════════════════════════════════════════════
## BATTLE MANAGER SIGNAL HANDLERS
## ═══════════════════════════════════════════════════════════════

func _on_battle_started() -> void:
	"""Called when battle initializes"""
	print("[Battle] Battle started")
	_display_combatants()
	_update_burst_gauge()

func _on_round_started(round_number: int) -> void:
	"""Called at start of each round"""
	log_message("=== Round %d ===" % round_number)

func _on_turn_started(combatant_id: String) -> void:
	"""Called when a combatant's turn starts"""
	current_combatant = battle_mgr.get_combatant_by_id(combatant_id)

	if current_combatant.is_empty():
		return

	log_message("%s's turn!" % current_combatant.display_name)

	if current_combatant.is_ally:
		# Player's turn - show action menu
		_show_action_menu()
	else:
		# Enemy turn - execute AI
		_execute_enemy_ai()

func _on_turn_ended(combatant_id: String) -> void:
	"""Called when a combatant's turn ends"""
	# Hide action menu
	action_menu.visible = false

func _on_battle_ended(victory: bool) -> void:
	"""Called when battle ends"""
	if victory:
		log_message("*** VICTORY ***")
		# TODO: Show victory screen, award rewards
		await get_tree().create_timer(2.0).timeout
	else:
		log_message("*** DEFEAT ***")
		# TODO: Show defeat screen
		await get_tree().create_timer(2.0).timeout

	# Return to overworld
	battle_mgr.return_to_overworld()

## ═══════════════════════════════════════════════════════════════
## COMBATANT DISPLAY
## ═══════════════════════════════════════════════════════════════

func _display_combatants() -> void:
	"""Display all combatants in their slots"""
	# Clear existing displays
	for child in ally_slots.get_children():
		child.queue_free()
	for child in enemy_slots.get_children():
		child.queue_free()

	# Display allies
	var allies = battle_mgr.get_ally_combatants()
	for ally in allies:
		var slot = _create_combatant_slot(ally, true)
		ally_slots.add_child(slot)

	# Display enemies
	var enemies = battle_mgr.get_enemy_combatants()
	for enemy in enemies:
		var slot = _create_combatant_slot(enemy, false)
		enemy_slots.add_child(slot)

func _create_combatant_slot(combatant: Dictionary, is_ally: bool) -> PanelContainer:
	"""Create a UI slot for a combatant"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 100)

	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	# Name label
	var name_label = Label.new()
	name_label.text = combatant.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# HP bar
	var hp_bar = ProgressBar.new()
	hp_bar.max_value = combatant.hp_max
	hp_bar.value = combatant.hp
	hp_bar.show_percentage = false
	vbox.add_child(hp_bar)

	# HP label
	var hp_label = Label.new()
	hp_label.text = "HP: %d/%d" % [combatant.hp, combatant.hp_max]
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(hp_label)

	# MP bar (if applicable)
	if combatant.mp_max > 0:
		var mp_bar = ProgressBar.new()
		mp_bar.max_value = combatant.mp_max
		mp_bar.value = combatant.mp
		mp_bar.show_percentage = false
		vbox.add_child(mp_bar)

		var mp_label = Label.new()
		mp_label.text = "MP: %d/%d" % [combatant.mp, combatant.mp_max]
		mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mp_label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(mp_label)

	# Store combatant ID in metadata
	panel.set_meta("combatant_id", combatant.id)

	return panel

func _update_combatant_displays() -> void:
	"""Update all combatant HP/MP displays"""
	# TODO: Update HP/MP bars without recreating everything
	_display_combatants()

## ═══════════════════════════════════════════════════════════════
## ACTION MENU
## ═══════════════════════════════════════════════════════════════

func _show_action_menu() -> void:
	"""Show the action menu for player's turn"""
	action_menu.visible = true

	# TODO: Enable/disable actions based on state
	# e.g., disable skills if no MP, disable burst if gauge too low

func _on_attack_pressed() -> void:
	"""Handle Attack action"""
	log_message("%s attacks!" % current_combatant.display_name)

	# Select target (first alive enemy for now)
	var enemies = battle_mgr.get_enemy_combatants()
	var target = null
	for enemy in enemies:
		if not enemy.is_ko:
			target = enemy
			break

	if target:
		# Calculate damage using combat resolver
		var damage_result = combat_resolver.calculate_physical_damage(
			current_combatant,
			target,
			{
				"potency": 100,
				"is_crit": false,  # TODO: Roll for crit
				"type_bonus": 0.0   # TODO: Check type matchup
			}
		)

		var damage = damage_result.damage
		var is_crit = damage_result.is_crit
		var is_stumble = damage_result.is_stumble

		# Apply damage
		target.hp -= damage
		if target.hp < 0:
			target.hp = 0
			target.is_ko = true

		# Log the hit with details
		var hit_msg = "  → Hit %s for %d damage!" % [target.display_name, damage]
		if is_crit:
			hit_msg += " (CRITICAL!)"
		if is_stumble:
			hit_msg += " (Weakness!)"
		log_message(hit_msg)

		# Debug: show damage breakdown
		var breakdown = damage_result.breakdown
		print("[Battle] Damage breakdown: PreMit=%.1f, AtkPower=%.1f, Raw=%.1f, Final=%d (Min=%d)" % [
			breakdown.pre_mit, breakdown.atk_power, breakdown.raw, damage, breakdown.min_damage
		])

		# Add burst gauge
		battle_mgr.add_burst(10)  # +10 for basic attack hit
		if is_stumble:
			battle_mgr.add_burst(8)  # +8 for weakness

		_update_combatant_displays()
		_update_burst_gauge()

		# Update turn order display
		if turn_order_display:
			turn_order_display.update_combatant_hp(target.id)

	# End turn
	battle_mgr.end_turn()

func _on_skill_pressed() -> void:
	"""Handle Skill action"""
	log_message("Skills not yet implemented")
	# TODO: Show skill menu

func _on_item_pressed() -> void:
	"""Handle Item action"""
	log_message("Items not yet implemented")
	# TODO: Show item menu

func _on_defend_pressed() -> void:
	"""Handle Defend action"""
	log_message("%s defends!" % current_combatant.display_name)
	current_combatant.is_defending = true

	# End turn
	battle_mgr.end_turn()

func _on_burst_pressed() -> void:
	"""Handle Burst action"""
	if battle_mgr.can_use_burst(1):
		log_message("Burst attack!")
		# TODO: Show burst menu
		battle_mgr.spend_burst(1)
		_update_burst_gauge()
	else:
		log_message("Not enough Burst Gauge!")

func _on_run_pressed() -> void:
	"""Handle Run action"""
	# TODO: Implement escape formula from design doc
	var run_chance = 50  # Simplified for now

	if randf() * 100 < run_chance:
		log_message("Escaped successfully!")
		await get_tree().create_timer(1.0).timeout
		battle_mgr.current_state = battle_mgr.BattleState.ESCAPED
		battle_mgr.return_to_overworld()
	else:
		log_message("Couldn't escape!")
		battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## ENEMY AI
## ═══════════════════════════════════════════════════════════════

func _execute_enemy_ai() -> void:
	"""Execute AI for enemy turn"""
	await get_tree().create_timer(0.5).timeout  # Brief delay

	log_message("%s attacks!" % current_combatant.display_name)

	# Simple AI: attack random ally
	var allies = battle_mgr.get_ally_combatants()
	var alive_allies = allies.filter(func(a): return not a.is_ko)

	if alive_allies.size() > 0:
		var target = alive_allies[randi() % alive_allies.size()]

		# Calculate damage using combat resolver
		var damage_result = combat_resolver.calculate_physical_damage(
			current_combatant,
			target,
			{
				"potency": 100,
				"is_crit": false,
				"type_bonus": 0.0
			}
		)

		var damage = damage_result.damage
		var is_crit = damage_result.is_crit
		var is_stumble = damage_result.is_stumble

		# Apply damage
		target.hp -= damage
		if target.hp < 0:
			target.hp = 0
			target.is_ko = true

		# Log the hit
		var hit_msg = "  → Hit %s for %d damage!" % [target.display_name, damage]
		if is_crit:
			hit_msg += " (CRITICAL!)"
		if is_stumble:
			hit_msg += " (Weakness!)"
		log_message(hit_msg)

		# Add burst gauge (player gains burst when taking damage)
		battle_mgr.add_burst(6)  # +6 for taking damage
		if is_stumble:
			battle_mgr.add_burst(8)  # +8 for weakness

		_update_combatant_displays()
		_update_burst_gauge()

		# Update turn order display
		if turn_order_display:
			turn_order_display.update_combatant_hp(target.id)

	await get_tree().create_timer(1.0).timeout

	# End turn
	battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## UI UPDATES
## ═══════════════════════════════════════════════════════════════

func _update_burst_gauge() -> void:
	"""Update burst gauge display"""
	if burst_gauge_bar:
		burst_gauge_bar.max_value = battle_mgr.BURST_GAUGE_MAX
		burst_gauge_bar.value = battle_mgr.burst_gauge

func log_message(message: String) -> void:
	"""Add a message to the battle log"""
	if battle_log:
		battle_log.append_text(message + "\n")
		# Auto-scroll to bottom
		battle_log.scroll_to_line(battle_log.get_line_count() - 1)
	print("[Battle] " + message)
