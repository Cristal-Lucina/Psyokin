extends Control
class_name Battle

## Battle Scene - Main battle screen controller
## Handles UI, combatant display, and player input for combat

@onready var battle_mgr = get_node("/root/aBattleManager")
@onready var gs = get_node("/root/aGameState")
@onready var combat_resolver: CombatResolver = CombatResolver.new()
@onready var csv_loader = get_node("/root/aCSVLoader")

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
var skill_definitions: Dictionary = {}  # skill_id -> skill data
var awaiting_skill_selection: bool = false
var skill_to_use: Dictionary = {}  # Selected skill data

func _ready() -> void:
	print("[Battle] Battle scene loaded")

	# Add combat resolver to scene tree
	add_child(combat_resolver)

	# Wait for next frame to ensure all autoloads are ready
	await get_tree().process_frame

	# Load skill definitions
	_load_skills()

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

func _load_skills() -> void:
	"""Load skill definitions from skills.csv"""
	skill_definitions = csv_loader.load_csv("res://data/skills/skills.csv", "skill_id")
	if skill_definitions and not skill_definitions.is_empty():
		print("[Battle] Loaded %d skill definitions" % skill_definitions.size())
	else:
		push_error("[Battle] Failed to load skills.csv")

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
	panel.set_meta("is_ally", is_ally)

	# Make enemy panels clickable for targeting
	if not is_ally:
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.gui_input.connect(_on_enemy_panel_input.bind(combatant))

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
	"""Handle Attack action - prompt user to select target"""
	log_message("Select a target...")

	# Get alive enemies
	var enemies = battle_mgr.get_enemy_combatants()
	target_candidates = enemies.filter(func(e): return not e.is_ko)

	if target_candidates.is_empty():
		log_message("No valid targets!")
		return

	# Enable target selection mode
	awaiting_target_selection = true
	_highlight_target_candidates()

func _execute_attack(target: Dictionary) -> void:
	"""Execute attack on selected target"""
	awaiting_target_selection = false
	_clear_target_highlights()

	# Clear defending status when attacking
	current_combatant.is_defending = false

	log_message("%s attacks %s!" % [current_combatant.display_name, target.display_name])

	if target:
		# First, check if the attack hits
		var hit_check = combat_resolver.check_physical_hit(current_combatant, target)

		if not hit_check.hit:
			# Miss!
			log_message("  → Missed! (%d%% chance, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
			print("[Battle] Miss! Hit chance: %.1f%%, Roll: %d" % [hit_check.hit_chance, hit_check.roll])
		else:
			# Hit! Now roll for critical
			var crit_check = combat_resolver.check_critical_hit(current_combatant)
			var is_crit = crit_check.crit

			# Calculate mind type effectiveness
			var type_bonus = combat_resolver.get_mind_type_bonus(current_combatant, target)

			# Check weapon type weakness (check now, record later after damage)
			var weapon_weakness_hit = combat_resolver.check_weapon_weakness(current_combatant, target)

			# Critical hits also count as weakness hits for stumbling
			var crit_weakness_hit = is_crit

			# Calculate damage
			var damage_result = combat_resolver.calculate_physical_damage(
				current_combatant,
				target,
				{
					"potency": 100,
					"is_crit": is_crit,
					"type_bonus": type_bonus
				}
			)

			var damage = damage_result.damage
			var is_stumble = damage_result.is_stumble

			# Apply damage
			target.hp -= damage
			if target.hp < 0:
				target.hp = 0
				target.is_ko = true

			# Record weakness hits AFTER damage (only if target still alive)
			if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
				var became_fallen = battle_mgr.record_weapon_weakness_hit(target)
				if weapon_weakness_hit:
					var weapon_desc = combat_resolver.get_weapon_type_description(current_combatant, target)
					log_message("  → WEAPON WEAKNESS! %s" % weapon_desc)
				elif crit_weakness_hit:
					log_message("  → CRITICAL STUMBLE!")
				if became_fallen:
					log_message("  → %s is FALLEN! (will skip next turn)" % target.display_name)

			# Log the hit with details
			var hit_msg = "  → Hit %s for %d damage! (%d%% chance)" % [target.display_name, damage, int(hit_check.hit_chance)]
			if is_crit:
				hit_msg += " (CRITICAL! %d%% chance)" % int(crit_check.crit_chance)
			if type_bonus > 0.0:
				hit_msg += " (Super Effective!)"
			elif type_bonus < 0.0:
				hit_msg += " (Not Very Effective...)"
			if target.get("is_defending", false):
				# Calculate damage reduction from defensive stance (0.7 multiplier = 30% reduction)
				var damage_without_defense = int(round(damage / 0.7))
				var damage_reduced = damage_without_defense - damage
				hit_msg += " (Defensive: -%d)" % damage_reduced
			log_message(hit_msg)

			# Debug: show hit, crit, and damage breakdown
			var hit_breakdown = hit_check.breakdown
			var crit_breakdown = crit_check.breakdown
			var dmg_breakdown = damage_result.breakdown
			print("[Battle] Hit! Chance: %.1f%% (ACC %.1f - EVA %.1f), Roll: %d" % [
				hit_check.hit_chance, hit_breakdown.hit_percent, hit_breakdown.eva_percent, hit_check.roll
			])
			print("[Battle] Crit: %s | Chance: %.1f%% (Base %.1f + TPO %.1f + Weapon %d), Roll: %d" % [
				"YES" if is_crit else "NO", crit_check.crit_chance, crit_breakdown.base,
				crit_breakdown.tpo_bonus, crit_breakdown.weapon_bonus, crit_check.roll
			])
			print("[Battle] Type: %s vs %s = %.2fx (%s)" % [
				current_combatant.get("mind_type", "none"),
				target.get("mind_type", "none"),
				1.0 + type_bonus,
				"SUPER EFFECTIVE" if type_bonus > 0 else ("NOT VERY EFFECTIVE" if type_bonus < 0 else "neutral")
			])
			print("[Battle] Damage: PreMit=%.1f, AtkPower=%.1f, Raw=%.1f, Final=%d (Min=%d)" % [
				dmg_breakdown.pre_mit, dmg_breakdown.atk_power, dmg_breakdown.raw, damage, dmg_breakdown.min_damage
			])

			# Add burst gauge
			battle_mgr.add_burst(10)  # +10 for basic attack hit
			if is_crit:
				battle_mgr.add_burst(4)  # +4 for crit
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
	"""Handle Skill action - show skill menu"""
	var skills = current_combatant.get("skills", [])

	if skills.is_empty():
		log_message("No skills available!")
		return

	# Build skill menu
	var skill_list = []
	for skill_id in skills:
		if skill_definitions.has(skill_id):
			var skill_data = skill_definitions[skill_id]
			var mp_cost = int(skill_data.get("cost_mp", 0))
			var can_afford = current_combatant.mp >= mp_cost
			skill_list.append({
				"id": skill_id,
				"data": skill_data,
				"can_afford": can_afford
			})

	if skill_list.is_empty():
		log_message("No skills available!")
		return

	# Show skill selection
	_show_skill_menu(skill_list)

func _on_item_pressed() -> void:
	"""Handle Item/Type Switch action"""
	# Check if this is the hero
	if current_combatant.id == "hero":
		_show_mind_type_menu()
	else:
		log_message("Items not yet implemented")
		# TODO: Show item menu

func _on_defend_pressed() -> void:
	"""Handle Defend action"""
	log_message("%s moved into a defensive stance." % current_combatant.display_name)
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
## TARGET SELECTION
## ═══════════════════════════════════════════════════════════════

func _on_enemy_panel_input(event: InputEvent, target: Dictionary) -> void:
	"""Handle clicks on enemy panels"""
	if event is InputEventMouseButton:
		var mb_event = event as InputEventMouseButton
		if mb_event.pressed and mb_event.button_index == MOUSE_BUTTON_LEFT:
			if awaiting_target_selection:
				# Check if this target is valid
				if target in target_candidates:
					if awaiting_skill_selection:
						# Using a skill
						_clear_target_highlights()
						awaiting_target_selection = false
						awaiting_skill_selection = false
						_execute_skill_single(target)
						battle_mgr.end_turn()
					else:
						# Regular attack
						_execute_attack(target)

func _highlight_target_candidates() -> void:
	"""Highlight valid targets with a visual indicator"""
	for child in enemy_slots.get_children():
		var combatant_id = child.get_meta("combatant_id", "")
		var is_candidate = target_candidates.any(func(c): return c.id == combatant_id)

		if is_candidate:
			# Add yellow border to indicate targetable
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.3, 0.2, 0.2, 0.9)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.border_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow highlight
			child.add_theme_stylebox_override("panel", style)

func _clear_target_highlights() -> void:
	"""Remove targeting highlights from all panels"""
	for child in enemy_slots.get_children():
		# Reset to default panel style
		child.remove_theme_stylebox_override("panel")

## ═══════════════════════════════════════════════════════════════
## ENEMY AI
## ═══════════════════════════════════════════════════════════════

func _execute_enemy_ai() -> void:
	"""Execute AI for enemy turn"""
	await get_tree().create_timer(0.5).timeout  # Brief delay

	# Clear defending status when attacking
	current_combatant.is_defending = false

	log_message("%s attacks!" % current_combatant.display_name)

	# Simple AI: attack random ally
	var allies = battle_mgr.get_ally_combatants()
	var alive_allies = allies.filter(func(a): return not a.is_ko)

	if alive_allies.size() > 0:
		var target = alive_allies[randi() % alive_allies.size()]

		# First, check if the attack hits
		var hit_check = combat_resolver.check_physical_hit(current_combatant, target)

		if not hit_check.hit:
			# Miss!
			log_message("  → Missed! (%d%% chance, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
			print("[Battle] Enemy Miss! Hit chance: %.1f%%, Roll: %d" % [hit_check.hit_chance, hit_check.roll])
		else:
			# Hit! Now roll for critical
			var crit_check = combat_resolver.check_critical_hit(current_combatant)
			var is_crit = crit_check.crit

			# Calculate mind type effectiveness
			var type_bonus = combat_resolver.get_mind_type_bonus(current_combatant, target)

			# Check weapon type weakness (check now, record later after damage)
			var weapon_weakness_hit = combat_resolver.check_weapon_weakness(current_combatant, target)

			# Critical hits also count as weakness hits for stumbling
			var crit_weakness_hit = is_crit

			# Calculate damage
			var damage_result = combat_resolver.calculate_physical_damage(
				current_combatant,
				target,
				{
					"potency": 100,
					"is_crit": is_crit,
					"type_bonus": type_bonus
				}
			)

			var damage = damage_result.damage
			var is_stumble = damage_result.is_stumble

			# Apply damage
			target.hp -= damage
			if target.hp < 0:
				target.hp = 0
				target.is_ko = true

			# Record weakness hits AFTER damage (only if target still alive)
			if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
				var became_fallen = battle_mgr.record_weapon_weakness_hit(target)
				if weapon_weakness_hit:
					var weapon_desc = combat_resolver.get_weapon_type_description(current_combatant, target)
					log_message("  → WEAPON WEAKNESS! %s" % weapon_desc)
				elif crit_weakness_hit:
					log_message("  → CRITICAL STUMBLE!")
				if became_fallen:
					log_message("  → %s is FALLEN! (will skip next turn)" % target.display_name)

			# Log the hit with details
			var hit_msg = "  → Hit %s for %d damage! (%d%% chance)" % [target.display_name, damage, int(hit_check.hit_chance)]
			if is_crit:
				hit_msg += " (CRITICAL! %d%% chance)" % int(crit_check.crit_chance)
			if type_bonus > 0.0:
				hit_msg += " (Super Effective!)"
			elif type_bonus < 0.0:
				hit_msg += " (Not Very Effective...)"
			if target.get("is_defending", false):
				# Calculate damage reduction from defensive stance (0.7 multiplier = 30% reduction)
				var damage_without_defense = int(round(damage / 0.7))
				var damage_reduced = damage_without_defense - damage
				hit_msg += " (Defensive: -%d)" % damage_reduced
			log_message(hit_msg)

			# Debug: show hit, crit, and damage breakdown
			var hit_breakdown = hit_check.breakdown
			var crit_breakdown = crit_check.breakdown
			var dmg_breakdown = damage_result.breakdown
			print("[Battle] Enemy Hit! Chance: %.1f%% (ACC %.1f - EVA %.1f), Roll: %d" % [
				hit_check.hit_chance, hit_breakdown.hit_percent, hit_breakdown.eva_percent, hit_check.roll
			])
			print("[Battle] Enemy Crit: %s | Chance: %.1f%% (Base %.1f + TPO %.1f + Weapon %d), Roll: %d" % [
				"YES" if is_crit else "NO", crit_check.crit_chance, crit_breakdown.base,
				crit_breakdown.tpo_bonus, crit_breakdown.weapon_bonus, crit_check.roll
			])
			print("[Battle] Enemy Damage: PreMit=%.1f, AtkPower=%.1f, Raw=%.1f, Final=%d (Min=%d)" % [
				dmg_breakdown.pre_mit, dmg_breakdown.atk_power, dmg_breakdown.raw, damage, dmg_breakdown.min_damage
			])

			# Add burst gauge (player gains burst when taking damage)
			battle_mgr.add_burst(6)  # +6 for taking damage
			if is_crit:
				battle_mgr.add_burst(4)  # +4 for enemy crit (player gains burst)
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

## ═══════════════════════════════════════════════════════════════
## SKILL MENU & EXECUTION
## ═══════════════════════════════════════════════════════════════

func _show_skill_menu(skill_list: Array) -> void:
	"""Show simple skill selection menu in battle log"""
	log_message("--- Select a Skill ---")

	for i in range(skill_list.size()):
		var skill_entry = skill_list[i]
		var skill_data = skill_entry.data
		var skill_name = String(skill_data.get("name", "Unknown"))
		var mp_cost = int(skill_data.get("cost_mp", 0))
		var can_afford = skill_entry.can_afford

		var menu_text = "%d. %s (MP: %d)" % [i + 1, skill_name, mp_cost]
		if not can_afford:
			menu_text += " [Not enough MP]"
		log_message(menu_text)

	# For now, auto-select first affordable skill
	for skill_entry in skill_list:
		if skill_entry.can_afford:
			_on_skill_selected(skill_entry)
			return

	log_message("Not enough MP for any skills!")
	return

func _on_skill_selected(skill_entry: Dictionary) -> void:
	"""Handle skill selection"""
	skill_to_use = skill_entry.data
	var skill_name = String(skill_to_use.get("name", "Unknown"))
	var target_type = String(skill_to_use.get("target", "Enemy")).to_lower()

	log_message("Selected: %s" % skill_name)

	# Determine targeting
	if target_type == "enemy" or target_type == "enemies":
		# Get alive enemies
		var enemies = battle_mgr.get_enemy_combatants()
		target_candidates = enemies.filter(func(e): return not e.is_ko)

		if target_candidates.is_empty():
			log_message("No valid targets!")
			skill_to_use = {}
			return

		# Check if AoE
		var is_aoe = int(skill_to_use.get("aoe", 0)) > 0

		if is_aoe:
			# AoE skill - hit all enemies
			_execute_skill_aoe()
		else:
			# Single target - need to select
			log_message("Select a target...")
			awaiting_target_selection = true
			awaiting_skill_selection = true
			_highlight_target_candidates()
	elif target_type == "ally" or target_type == "allies":
		# TODO: Implement ally targeting
		log_message("Ally targeting not yet implemented")
		skill_to_use = {}
	else:
		# Self-target or other
		log_message("Self-targeting not yet implemented")
		skill_to_use = {}

func _execute_skill_single(target: Dictionary) -> void:
	"""Execute a single-target skill"""
	var skill_name = String(skill_to_use.get("name", "Unknown"))
	var mp_cost = int(skill_to_use.get("cost_mp", 0))
	var element = String(skill_to_use.get("element", "none")).to_lower()
	var power = int(skill_to_use.get("power", 30))
	var acc = int(skill_to_use.get("acc", 90))
	var crit_bonus = int(skill_to_use.get("crit_bonus_pct", 0))
	var mnd_scaling = int(skill_to_use.get("scaling_mnd", 1))

	# Clear defending status when using skill
	current_combatant.is_defending = false

	# Deduct MP
	current_combatant.mp -= mp_cost
	if current_combatant.mp < 0:
		current_combatant.mp = 0

	log_message("%s uses %s!" % [current_combatant.display_name, skill_name])

	# Check if hit
	var hit_check = combat_resolver.check_sigil_hit(current_combatant, target, {"skill_acc": acc})

	if not hit_check.hit:
		log_message("  → Missed! (%d%% chance, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
		return

	# Roll for crit
	var crit_check = combat_resolver.check_critical_hit(current_combatant, {"skill_crit_bonus": crit_bonus})
	var is_crit = crit_check.crit

	# Calculate type effectiveness (use skill's element vs defender's mind type)
	var type_bonus = 0.0
	if element != "none" and element != "":
		type_bonus = combat_resolver.get_mind_type_bonus(
			{"mind_type": element},
			target,
			element
		)

	# Check weapon weakness and crit stumble
	var weapon_weakness_hit = combat_resolver.check_weapon_weakness(current_combatant, target)
	var crit_weakness_hit = is_crit

	# Calculate skill damage
	var damage_result = combat_resolver.calculate_sigil_damage(
		current_combatant,
		target,
		{
			"potency": 100,
			"is_crit": is_crit,
			"type_bonus": type_bonus,
			"base_sig": power,
			"mnd_scale": mnd_scaling
		}
	)

	var damage = damage_result.damage
	var is_stumble = damage_result.is_stumble

	# Apply damage
	target.hp -= damage
	if target.hp < 0:
		target.hp = 0
		target.is_ko = true

	# Record weakness hits AFTER damage (only if target still alive)
	if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
		var became_fallen = battle_mgr.record_weapon_weakness_hit(target)
		if weapon_weakness_hit:
			var weapon_desc = combat_resolver.get_weapon_type_description(current_combatant, target)
			log_message("  → WEAPON WEAKNESS! %s" % weapon_desc)
		elif crit_weakness_hit:
			log_message("  → CRITICAL STUMBLE!")
		if became_fallen:
			log_message("  → %s is FALLEN! (will skip next turn)" % target.display_name)

	# Log the hit
	var hit_msg = "  → Hit %s for %d damage! (%d%% chance)" % [target.display_name, damage, int(hit_check.hit_chance)]
	if is_crit:
		hit_msg += " (CRITICAL! %d%% chance)" % int(crit_check.crit_chance)
	if type_bonus > 0.0:
		hit_msg += " (Super Effective!)"
	elif type_bonus < 0.0:
		hit_msg += " (Not Very Effective...)"
	if target.get("is_defending", false):
		var damage_without_defense = int(round(damage / 0.7))
		var damage_reduced = damage_without_defense - damage
		hit_msg += " (Defensive: -%d)" % damage_reduced
	log_message(hit_msg)

	# Update displays
	_update_combatant_displays()
	if turn_order_display:
		turn_order_display.update_combatant_hp(target.id)

func _execute_skill_aoe() -> void:
	"""Execute an AoE skill on all valid targets"""
	var skill_name = String(skill_to_use.get("name", "Unknown"))
	var mp_cost = int(skill_to_use.get("cost_mp", 0))

	# Clear defending status
	current_combatant.is_defending = false

	# Deduct MP
	current_combatant.mp -= mp_cost
	if current_combatant.mp < 0:
		current_combatant.mp = 0

	log_message("%s uses %s on all enemies!" % [current_combatant.display_name, skill_name])

	# Hit each target
	for target in target_candidates:
		if not target.is_ko:
			await get_tree().create_timer(0.3).timeout
			_execute_skill_single(target)

	# End turn after AoE
	battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## MIND TYPE SWITCHING (HERO ONLY)
## ═══════════════════════════════════════════════════════════════

func _show_mind_type_menu() -> void:
	"""Show mind type switching menu for hero"""
	var available_types = ["Fire", "Water", "Earth", "Air", "Void", "Data", "Omega"]
	var current_type = String(gs.get_meta("hero_active_type", "Omega"))

	log_message("--- Switch Mind Type ---")
	log_message("Current: %s" % current_type)

	for i in range(available_types.size()):
		var type_name = available_types[i]
		var marker = " [Current]" if type_name == current_type else ""
		log_message("%d. %s%s" % [i + 1, type_name, marker])

	# For now, auto-select first type that's different from current
	for type_name in available_types:
		if type_name != current_type:
			_switch_mind_type(type_name)
			return

func _switch_mind_type(new_type: String) -> void:
	"""Switch hero's mind type and reload skills"""
	var old_type = String(gs.get_meta("hero_active_type", "Omega"))

	# Update mind type in GameState
	gs.set_meta("hero_active_type", new_type)

	# Update combatant's mind_type
	current_combatant.mind_type = new_type.to_lower()

	# Reload sigils and skills for new type
	if has_node("/root/aSigilSystem"):
		var sigil_sys = get_node("/root/aSigilSystem")
		var loadout = sigil_sys.get_loadout("hero")

		var new_skills = []
		for sigil_inst in loadout:
			if sigil_inst != "":
				var skill_id = sigil_sys.get_active_skill_id_for_instance(sigil_inst)
				if skill_id != "":
					new_skills.append(skill_id)

		current_combatant.skills = new_skills
		log_message("%s switched from %s to %s!" % [current_combatant.display_name, old_type, new_type])
		log_message("  Skills updated: %s" % str(new_skills))

	# End turn after switching
	battle_mgr.end_turn()
