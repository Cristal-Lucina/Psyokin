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
var awaiting_capture_target: bool = false  # True when selecting target for capture
var awaiting_item_target: bool = false  # True when selecting target for item usage
var skill_to_use: Dictionary = {}  # Selected skill data
var skill_menu_panel: PanelContainer = null  # Skill selection menu
var item_menu_panel: PanelContainer = null  # Item selection menu
var capture_menu_panel: PanelContainer = null  # Capture selection menu
var current_skill_menu: Array = []  # Current skills in menu
var selected_item: Dictionary = {}  # Selected item data

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

func _on_turn_ended(_combatant_id: String) -> void:
	"""Called when a combatant's turn ends"""
	# Hide action menu
	action_menu.visible = false

func _on_battle_ended(victory: bool) -> void:
	"""Called when battle ends"""
	if victory:
		log_message("*** VICTORY ***")
		log_message("All enemies have been defeated!")
		# TODO: Show victory screen, award rewards
		await get_tree().create_timer(2.0).timeout
		# Return to overworld
		battle_mgr.return_to_overworld()
	else:
		log_message("*** DEFEAT ***")
		log_message("Your party has been wiped out!")
		log_message("GAME OVER")
		# TODO: Show game over screen with retry/load options
		await get_tree().create_timer(3.0).timeout
		# For now, return to main menu or reload
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

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

	# Hide KO'd enemies - move off screen and make invisible
	if not is_ally and combatant.get("is_ko", false):
		panel.visible = false
		panel.position = Vector2(-1000, -1000)  # Move off screen

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

	# Make panels clickable for targeting
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	if not is_ally:
		panel.gui_input.connect(_on_enemy_panel_input.bind(combatant))
	else:
		panel.gui_input.connect(_on_ally_panel_input.bind(combatant))

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

	# Disable Run button if already attempted this round
	var run_button = action_menu.get_node_or_null("RunButton")
	if run_button and run_button is Button:
		run_button.disabled = battle_mgr.run_attempted_this_round
		if battle_mgr.run_attempted_this_round:
			run_button.text = "Run (Used)"
		else:
			run_button.text = "Run"

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

				# Record kill for morality system (if enemy)
				if not target.get("is_ally", false):
					battle_mgr.record_enemy_defeat(target, false)  # false = kill

			# Record weakness hits AFTER damage (only if target still alive)
			if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
				var became_fallen = await battle_mgr.record_weapon_weakness_hit(target)
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

			# Refresh turn order if combatant was KO'd
			if target.is_ko:
				# Animate falling and then re-sort turn order
				if turn_order_display:
					await turn_order_display.animate_ko_fall(target.id)
				await battle_mgr.refresh_turn_order()
			elif turn_order_display:
				turn_order_display.update_combatant_hp(target.id)

	# End turn
	battle_mgr.end_turn()

func _on_skill_pressed() -> void:
	"""Handle Skill action - show sigil/skill menu"""
	var sigils = current_combatant.get("sigils", [])
	var skills = current_combatant.get("skills", [])

	if skills.is_empty():
		log_message("No skills available!")
		return

	# Get SigilSystem for display names
	var sigil_sys = get_node_or_null("/root/aSigilSystem")
	if not sigil_sys:
		log_message("Sigil system not available!")
		return

	# Build skill menu with sigil info
	var skill_menu = []
	for i in range(min(sigils.size(), skills.size())):
		var sigil_inst = sigils[i]
		var skill_id = skills[i]

		if skill_definitions.has(skill_id):
			var skill_data = skill_definitions[skill_id]
			var mp_cost = int(skill_data.get("cost_mp", 0))
			var can_afford = current_combatant.mp >= mp_cost

			# Get sigil display name
			var sigil_name = sigil_sys.get_display_name_for(sigil_inst) if sigil_sys.has_method("get_display_name_for") else "Sigil"

			skill_menu.append({
				"sigil_name": sigil_name,
				"skill_id": skill_id,
				"skill_data": skill_data,
				"can_afford": can_afford
			})

	if skill_menu.is_empty():
		log_message("No skills available!")
		return

	# Show skill selection menu
	_show_skill_menu(skill_menu)

func _on_item_pressed() -> void:
	"""Handle Item action - show usable items menu"""
	var inventory = get_node_or_null("/root/aInventorySystem")
	if not inventory:
		log_message("Inventory system not available!")
		return

	# Get all consumable items player has
	var item_counts = inventory.get_counts_dict()
	var item_defs = inventory.get_item_defs()
	var usable_items: Array = []

	for item_id in item_counts:
		var count = item_counts[item_id]
		if count <= 0:
			continue

		# Skip if item_id is invalid
		if item_id == null:
			continue

		var item_id_str = str(item_id)  # Use str() which is safer than String()
		if item_id_str == "":
			continue

		var item_def = item_defs.get(item_id, {})
		var use_type = item_def.get("use_type", "")
		if use_type == null:
			use_type = ""
		use_type = str(use_type)

		var category = item_def.get("category", "")
		if category == null:
			category = ""
		category = str(category)

		# Include items that can be used in battle (use_type = "battle" or "both")
		# Exclude bind items (those are for Capture button)
		if use_type in ["battle", "both"] and category != "Battle Items":
			var desc = item_def.get("short_description", "")
			if desc == null:
				desc = ""
			desc = str(desc)

			var item_name = item_def.get("name", "")
			if item_name == null or item_name == "":
				item_name = item_id_str
			item_name = str(item_name)

			var targeting = item_def.get("targeting", "Ally")
			if targeting == null:
				targeting = "Ally"
			targeting = str(targeting)

			usable_items.append({
				"id": item_id_str,
				"name": item_name,
				"display_name": item_name,
				"description": desc,
				"count": count,
				"targeting": targeting,
				"item_def": item_def
			})

	if usable_items.is_empty():
		log_message("No usable items!")
		return

	# Show item selection menu
	_show_item_menu(usable_items)

func _on_capture_pressed() -> void:
	"""Handle Capture action - show bind item selection menu"""
	var inventory = get_node_or_null("/root/aInventorySystem")
	if not inventory:
		log_message("Inventory system not available!")
		return

	# Find available bind items
	var bind_items: Array = []
	var bind_ids = ["BIND_001", "BIND_002", "BIND_003", "BIND_004", "BIND_005"]

	for bind_id in bind_ids:
		var count = inventory.get_count(bind_id)
		if count > 0:
			var item_def = inventory.get_item_def(bind_id)

			# Debug: Check what fields are available in item_def
			print("[Battle] Bind item %s fields: %s" % [bind_id, item_def.keys()])
			print("[Battle] Bind item %s capture_mod raw value: %s" % [bind_id, item_def.get("capture_mod", "NOT_FOUND")])

			var desc = item_def.get("short_description", "")
			if desc == null:
				desc = ""
			desc = str(desc)

			var bind_name = item_def.get("name", "")
			if bind_name == null or bind_name == "":
				bind_name = bind_id
			bind_name = str(bind_name)

			var capture_mod_raw = item_def.get("capture_mod", 0)
			var capture_mod_val = int(capture_mod_raw) if capture_mod_raw != null else 0
			print("[Battle] Bind item %s final capture_mod: %d" % [bind_id, capture_mod_val])

			bind_items.append({
				"id": str(bind_id),
				"name": bind_name,
				"display_name": bind_name,
				"description": desc,
				"capture_mod": capture_mod_val,
				"count": count,
				"item_def": item_def
			})

	if bind_items.is_empty():
		log_message("No bind items available!")
		return

	# Show bind selection menu
	_show_capture_menu(bind_items)

func _execute_capture(target: Dictionary) -> void:
	"""Execute capture attempt on selected target"""
	awaiting_target_selection = false
	awaiting_capture_target = false
	_clear_target_highlights()

	# Get the bind item that was selected
	var bind_data = get_meta("pending_capture_bind", {})
	if bind_data.is_empty():
		log_message("Capture failed - no bind selected!")
		return

	var bind_id: String = bind_data.id
	var bind_name: String = bind_data.name
	var capture_mod: int = bind_data.capture_mod

	# Calculate capture chance
	var capture_result = combat_resolver.calculate_capture_chance(target, {"item_mod": capture_mod})
	var capture_chance: float = capture_result.chance

	log_message("%s uses %s on %s!" % [current_combatant.display_name, bind_name, target.display_name])
	log_message("  Capture chance: %.1f%%" % capture_chance)

	# Attempt capture
	var success = combat_resolver.attempt_capture(target, capture_chance)

	# Consume the bind item
	var inventory = get_node("/root/aInventorySystem")
	inventory.remove_item(bind_id, 1)

	if success:
		# Capture successful!
		target.is_captured = true
		target.is_ko = true  # Remove from battle like KO
		log_message("  → SUCCESS! %s was captured!" % target.display_name)

		# Record capture for morality system
		battle_mgr.record_enemy_defeat(target, true)  # true = capture

		# Add captured enemy to collection
		_add_captured_enemy(target)

		# Animate turn cell - turn it green
		if turn_order_display and turn_order_display.has_method("animate_capture"):
			turn_order_display.animate_capture(target.id)

		# Update display
		_update_combatant_displays()

		# Check if battle is over
		if battle_mgr.check_battle_end():
			return  # Battle ended
	else:
		# Capture failed
		log_message("  → FAILED! %s broke free!" % target.display_name)

	# End turn
	battle_mgr.end_turn()

func _execute_item_usage(target: Dictionary) -> void:
	"""Execute item usage on selected target"""
	awaiting_target_selection = false
	awaiting_item_target = false
	_clear_target_highlights()

	# Get the item that was selected
	if selected_item.is_empty():
		log_message("Item usage failed - no item selected!")
		return

	var item_id: String = selected_item.id
	var item_name: String = selected_item.name
	var item_def: Dictionary = selected_item.item_def

	log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

	# Apply item effects based on battle_status_effect
	var effect: String = String(item_def.get("battle_status_effect", ""))

	if "Heal" in effect:
		# Parse heal amount from effect string (e.g., "Heal 50 HP")
		var hp_heal = 0
		var mp_heal = 0

		if "HP" in effect:
			# Extract number before "HP"
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*HP")
			var result = regex.search(effect)
			if result:
				hp_heal = int(result.get_string(1))

		if "MP" in effect:
			# Extract number before "MP"
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*MP")
			var result = regex.search(effect)
			if result:
				mp_heal = int(result.get_string(1))

		# Apply healing
		if hp_heal > 0:
			var old_hp = target.hp
			target.hp = min(target.hp + hp_heal, target.hp_max)
			var actual_heal = target.hp - old_hp
			log_message("  → Restored %d HP!" % actual_heal)

		if mp_heal > 0:
			var old_mp = target.mp
			target.mp = min(target.mp + mp_heal, target.mp_max)
			var actual_heal = target.mp - old_mp
			log_message("  → Restored %d MP!" % actual_heal)

		# Update displays
		_update_combatant_displays()

	# Consume the item
	var inventory = get_node("/root/aInventorySystem")
	inventory.remove_item(item_id, 1)

	# End turn
	battle_mgr.end_turn()

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
	# Check if run was already attempted this round
	if battle_mgr.run_attempted_this_round:
		log_message("Already tried to run this round!")
		return

	# Mark that run was attempted
	battle_mgr.run_attempted_this_round = true

	# Calculate run chance based on enemy HP and level difference
	var run_chance = _calculate_run_chance()

	log_message("Attempting to escape... (%d%% chance)" % int(run_chance))

	if randf() * 100 < run_chance:
		log_message("Escaped successfully!")
		await get_tree().create_timer(1.0).timeout
		battle_mgr.current_state = battle_mgr.BattleState.ESCAPED
		battle_mgr.return_to_overworld()
	else:
		log_message("Couldn't escape!")
		battle_mgr.end_turn()

func _calculate_run_chance() -> float:
	"""Calculate run chance based on enemy HP percentage and level difference"""
	const BASE_RUN_CHANCE: float = 50.0
	const MAX_HP_BONUS: float = 40.0
	const _MAX_LEVEL_BONUS: float = 20.0  # Reserved for future level-based calculations
	const LEVEL_BONUS_PER_LEVEL: float = 2.0

	# Calculate enemy HP percentage bonus (0-40%)
	var enemies = battle_mgr.get_enemy_combatants()
	var total_enemy_hp_current: float = 0.0
	var total_enemy_hp_max: float = 0.0

	for enemy in enemies:
		total_enemy_hp_current += enemy.hp
		total_enemy_hp_max += enemy.hp_max

	var hp_loss_percent: float = 0.0
	if total_enemy_hp_max > 0:
		hp_loss_percent = 1.0 - (total_enemy_hp_current / total_enemy_hp_max)

	var hp_bonus: float = hp_loss_percent * MAX_HP_BONUS

	# Calculate level difference bonus (0-20%, 2% per level up to 10 levels)
	var allies = battle_mgr.get_ally_combatants()
	var total_ally_level: int = 0
	var total_enemy_level: int = 0

	for ally in allies:
		total_ally_level += ally.level

	for enemy in enemies:
		total_enemy_level += enemy.level

	var level_difference: int = total_ally_level - total_enemy_level
	var level_bonus: float = 0.0
	if level_difference > 0:
		level_bonus = min(level_difference, 10) * LEVEL_BONUS_PER_LEVEL

	# Calculate final run chance
	var final_chance: float = BASE_RUN_CHANCE + hp_bonus + level_bonus

	# Log breakdown for debugging
	log_message("  Base: %d%% | HP Bonus: +%d%% | Level Bonus: +%d%%" % [
		int(BASE_RUN_CHANCE),
		int(hp_bonus),
		int(level_bonus)
	])

	return final_chance

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
					if awaiting_capture_target:
						# Attempting capture
						_execute_capture(target)
					elif awaiting_item_target:
						# Using an item
						_execute_item_usage(target)
					elif awaiting_skill_selection:
						# Using a skill
						_clear_target_highlights()
						awaiting_target_selection = false
						awaiting_skill_selection = false
						_execute_skill_single(target)
						battle_mgr.end_turn()
					else:
						# Regular attack
						_execute_attack(target)

func _on_ally_panel_input(event: InputEvent, target: Dictionary) -> void:
	"""Handle clicks on ally panels (for item targeting)"""
	if event is InputEventMouseButton:
		var mb_event = event as InputEventMouseButton
		if mb_event.pressed and mb_event.button_index == MOUSE_BUTTON_LEFT:
			if awaiting_target_selection and awaiting_item_target:
				# Check if this target is valid
				if target in target_candidates:
					_execute_item_usage(target)

func _highlight_target_candidates() -> void:
	"""Highlight valid targets with a visual indicator"""
	# Highlight enemies
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

	# Highlight allies (for items)
	for child in ally_slots.get_children():
		var combatant_id = child.get_meta("combatant_id", "")
		var is_candidate = target_candidates.any(func(c): return c.id == combatant_id)

		if is_candidate:
			# Add green border to indicate targetable ally
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.3, 0.2, 0.9)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.border_color = Color(0.0, 1.0, 0.0, 1.0)  # Green highlight
			child.add_theme_stylebox_override("panel", style)

func _clear_target_highlights() -> void:
	"""Remove targeting highlights from all panels"""
	for child in enemy_slots.get_children():
		# Reset to default panel style
		child.remove_theme_stylebox_override("panel")
	for child in ally_slots.get_children():
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

				# Record kill for morality system (if enemy)
				if not target.get("is_ally", false):
					battle_mgr.record_enemy_defeat(target, false)  # false = kill

			# Record weakness hits AFTER damage (only if target still alive)
			if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
				var became_fallen = await battle_mgr.record_weapon_weakness_hit(target)
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

			# Refresh turn order if combatant was KO'd
			if target.is_ko:
				# Animate falling and then re-sort turn order
				if turn_order_display:
					await turn_order_display.animate_ko_fall(target.id)
				await battle_mgr.refresh_turn_order()
			elif turn_order_display:
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

func _show_skill_menu(skill_menu: Array) -> void:
	"""Show skill selection menu with sigils"""
	# Hide action menu
	action_menu.visible = false

	# Store current menu
	current_skill_menu = skill_menu

	# Create skill menu panel
	skill_menu_panel = PanelContainer.new()
	skill_menu_panel.custom_minimum_size = Vector2(400, 0)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	skill_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	skill_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select a Skill"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Show current mind type
	var current_type = String(current_combatant.get("mind_type", "omega")).capitalize()
	var type_label = Label.new()
	type_label.text = "Current Type: %s" % current_type
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(type_label)

	# Add "Change Type" button (only for player)
	if current_combatant.get("is_ally", false) and current_combatant.get("id") == "hero":
		var changed_this_round = current_combatant.get("changed_type_this_round", false)
		var change_type_btn = Button.new()
		change_type_btn.text = "Change Mind Type" if not changed_this_round else "Change Mind Type (Used)"
		change_type_btn.custom_minimum_size = Vector2(380, 40)
		change_type_btn.disabled = changed_this_round
		change_type_btn.pressed.connect(_on_change_type_button_pressed)
		vbox.add_child(change_type_btn)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add skill buttons
	for i in range(skill_menu.size()):
		var menu_entry = skill_menu[i]
		var sigil_name = menu_entry.sigil_name
		var skill_data = menu_entry.skill_data
		var skill_name = String(skill_data.get("name", "Unknown"))
		var skill_element = String(skill_data.get("element", "none"))
		var skill_element_cap = skill_element.capitalize()
		var mp_cost = int(skill_data.get("cost_mp", 0))
		var can_afford = menu_entry.can_afford

		# Check if skill element matches current mind type
		var current_mind_type = String(current_combatant.get("mind_type", "omega")).to_lower()
		var type_matches = (skill_element.to_lower() == current_mind_type)

		var button = Button.new()
		button.text = "[%s] %s\n(%s, MP: %d)" % [sigil_name, skill_name, skill_element_cap, mp_cost]
		button.custom_minimum_size = Vector2(380, 50)

		# Disable if can't afford OR type doesn't match
		if not can_afford:
			button.disabled = true
			button.text += "\n[Not enough MP]"
		elif not type_matches:
			button.disabled = true
			button.text += "\n[Wrong Type - Need %s]" % skill_element_cap
		else:
			button.pressed.connect(_on_skill_button_pressed.bind(i))

		vbox.add_child(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(380, 40)
	cancel_btn.pressed.connect(_close_skill_menu)
	vbox.add_child(cancel_btn)

	# Add to scene
	add_child(skill_menu_panel)

	# Center it
	skill_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - skill_menu_panel.custom_minimum_size.x) / 2,
		100
	)

func _on_skill_button_pressed(index: int) -> void:
	"""Handle skill button press"""
	if index >= 0 and index < current_skill_menu.size():
		var menu_entry = current_skill_menu[index]
		_close_skill_menu()
		_on_skill_selected(menu_entry)

func _on_change_type_button_pressed() -> void:
	"""Handle change type button press - show type selection menu"""
	# Close current skill menu
	_close_skill_menu()

	# Create type selection panel
	var type_panel = PanelContainer.new()
	type_panel.custom_minimum_size = Vector2(300, 0)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	type_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	type_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Change Mind Type"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var current_type = String(current_combatant.get("mind_type", "omega")).capitalize()
	var current_label = Label.new()
	current_label.text = "Current: %s" % current_type
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(current_label)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add type buttons
	var available_types = ["Fire", "Water", "Earth", "Air", "Void", "Data", "Omega"]
	for type_name in available_types:
		if type_name.to_lower() != current_type.to_lower():
			var btn = Button.new()
			btn.text = type_name
			btn.custom_minimum_size = Vector2(280, 40)
			btn.pressed.connect(_on_type_selected.bind(type_name, type_panel))
			vbox.add_child(btn)

	# Cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(280, 40)
	cancel_btn.pressed.connect(_on_type_menu_cancel.bind(type_panel))
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(type_panel)
	type_panel.position = Vector2(
		(get_viewport_rect().size.x - type_panel.custom_minimum_size.x) / 2,
		150
	)

func _on_type_selected(new_type: String, type_panel: PanelContainer) -> void:
	"""Handle type selection"""
	# Close type menu
	if type_panel:
		type_panel.queue_free()

	# Switch type (don't end turn)
	_switch_mind_type(new_type, false)

	# Reopen skill menu with new type
	_on_skill_pressed()

func _on_type_menu_cancel(type_panel: PanelContainer) -> void:
	"""Cancel type selection and return to skill menu"""
	if type_panel:
		type_panel.queue_free()

	# Reopen skill menu
	_on_skill_pressed()

func _close_skill_menu() -> void:
	"""Close the skill menu"""
	if skill_menu_panel:
		skill_menu_panel.queue_free()
		skill_menu_panel = null
	current_skill_menu = []

	# Show action menu again
	action_menu.visible = true

## ═══════════════════════════════════════════════════════════════
## ITEM MENU
## ═══════════════════════════════════════════════════════════════

func _show_item_menu(items: Array) -> void:
	"""Show item selection menu"""
	# Hide action menu
	action_menu.visible = false

	# Create item menu panel
	item_menu_panel = PanelContainer.new()
	item_menu_panel.custom_minimum_size = Vector2(400, 0)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	item_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	item_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select an Item"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add item buttons
	for i in range(items.size()):
		var item_data = items[i]
		var item_name = str(item_data.get("name", "Unknown"))
		var item_desc = str(item_data.get("description", ""))
		var item_count = int(item_data.get("count", 0))

		var button = Button.new()
		button.text = "%s (x%d)\n%s" % [item_name, item_count, item_desc]
		button.custom_minimum_size = Vector2(380, 50)
		button.pressed.connect(_on_item_selected.bind(item_data))
		vbox.add_child(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(380, 40)
	cancel_btn.pressed.connect(_close_item_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(item_menu_panel)
	item_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 400) / 2,
		(get_viewport_rect().size.y - vbox.size.y) / 2
	)

func _close_item_menu() -> void:
	"""Close the item menu"""
	if item_menu_panel:
		item_menu_panel.queue_free()
		item_menu_panel = null

	# Show action menu again
	action_menu.visible = true

func _on_item_selected(item_data: Dictionary) -> void:
	"""Handle item selection from menu"""
	_close_item_menu()

	# Store selected item
	selected_item = item_data

	var targeting = str(item_data.get("targeting", "Ally"))
	log_message("Using %s - select target..." % str(item_data.get("name", "item")))

	# Determine target candidates
	if targeting == "Ally":
		var allies = battle_mgr.get_ally_combatants()
		target_candidates = allies.filter(func(a): return not a.is_ko)
	else:  # Enemy
		var enemies = battle_mgr.get_enemy_combatants()
		target_candidates = enemies.filter(func(e): return not e.is_ko)

	if target_candidates.is_empty():
		log_message("No valid targets!")
		return

	# Enable target selection mode
	awaiting_target_selection = true
	awaiting_item_target = true
	_highlight_target_candidates()

## ═══════════════════════════════════════════════════════════════
## CAPTURE/BIND MENU
## ═══════════════════════════════════════════════════════════════

func _show_capture_menu(bind_items: Array) -> void:
	"""Show bind item selection menu for capture"""
	# Hide action menu
	action_menu.visible = false

	# Create capture menu panel
	capture_menu_panel = PanelContainer.new()
	capture_menu_panel.custom_minimum_size = Vector2(400, 0)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	capture_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	capture_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select a Bind Device"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add bind item buttons
	for i in range(bind_items.size()):
		var bind_data = bind_items[i]
		var bind_name = str(bind_data.get("name", "Unknown"))
		var bind_desc = str(bind_data.get("description", ""))
		var bind_count = int(bind_data.get("count", 0))
		var capture_mod = int(bind_data.get("capture_mod", 0))

		var button = Button.new()
		button.text = "%s (x%d) [+%d%%]\n%s" % [bind_name, bind_count, capture_mod, bind_desc]
		button.custom_minimum_size = Vector2(380, 50)
		button.pressed.connect(_on_bind_selected.bind(bind_data))
		vbox.add_child(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(380, 40)
	cancel_btn.pressed.connect(_close_capture_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(capture_menu_panel)
	capture_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 400) / 2,
		(get_viewport_rect().size.y - vbox.size.y) / 2
	)

func _close_capture_menu() -> void:
	"""Close the capture menu"""
	if capture_menu_panel:
		capture_menu_panel.queue_free()
		capture_menu_panel = null

	# Show action menu again
	action_menu.visible = true

func _on_bind_selected(bind_data: Dictionary) -> void:
	"""Handle bind item selection from capture menu"""
	_close_capture_menu()

	log_message("Using %s (x%d) - select target..." % [bind_data.name, bind_data.count])

	# Get alive enemies
	var enemies = battle_mgr.get_enemy_combatants()
	target_candidates = enemies.filter(func(e): return not e.is_ko and not e.get("is_captured", false))

	if target_candidates.is_empty():
		log_message("No valid targets to capture!")
		return

	# Store selected bind for use after target selection
	set_meta("pending_capture_bind", bind_data)

	# Enable capture target selection mode
	awaiting_target_selection = true
	awaiting_capture_target = true
	_highlight_target_candidates()

func _on_skill_selected(skill_entry: Dictionary) -> void:
	"""Handle skill selection"""
	skill_to_use = skill_entry.skill_data
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
	# Skills ONLY use elemental weakness, NOT weapon triangle
	var type_bonus = 0.0
	if element != "none" and element != "":
		type_bonus = combat_resolver.get_mind_type_bonus(
			{"mind_type": element},
			target,
			element
		)

		# Show type matchup explanation
		if type_bonus > 0.0:
			log_message("  → TYPE ADVANTAGE! %s vs %s" % [element.capitalize(), target.mind_type.capitalize()])
		elif type_bonus < 0.0:
			log_message("  → TYPE DISADVANTAGE! %s vs %s" % [element.capitalize(), target.mind_type.capitalize()])

	# Both crits and type advantages count as stumbles for skills
	var crit_weakness_hit = is_crit
	var type_advantage_hit = type_bonus > 0.0

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
	var _is_stumble = damage_result.is_stumble  # Reserved for future stumble mechanics

	# Apply damage
	target.hp -= damage
	if target.hp < 0:
		target.hp = 0
		target.is_ko = true

	# Record weakness hits AFTER damage (only if target still alive)
	# Skills count crits and type advantages as weakness hits
	if not target.is_ko and (crit_weakness_hit or type_advantage_hit):
		var became_fallen = await battle_mgr.record_weapon_weakness_hit(target)
		if crit_weakness_hit:
			log_message("  → CRITICAL STUMBLE!")
		elif type_advantage_hit:
			log_message("  → ELEMENTAL STUMBLE!")
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
	if target.is_ko:
		# Animate falling and then re-sort turn order
		if turn_order_display:
			await turn_order_display.animate_ko_fall(target.id)
		battle_mgr.refresh_turn_order()
	elif turn_order_display:
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

func _switch_mind_type(new_type: String, end_turn: bool = true) -> void:
	"""Switch hero's mind type and reload skills"""
	var old_type = String(gs.get_meta("hero_active_type", "Omega"))

	# Update mind type in GameState
	gs.set_meta("hero_active_type", new_type)

	# Update combatant's mind_type
	current_combatant.mind_type = new_type.to_lower()

	# Mark that type was changed this round
	current_combatant.changed_type_this_round = true

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

	# End turn if requested (for Item button usage)
	if end_turn:
		battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## CAPTURE COLLECTION
## ═══════════════════════════════════════════════════════════════

func _add_captured_enemy(enemy: Dictionary) -> void:
	"""Add a captured enemy to the player's collection"""
	if not gs:
		return

	# Get enemy actor_id (the base enemy type, not the battle instance id)
	var actor_id = String(enemy.get("actor_id", ""))
	if actor_id == "":
		print("[Battle] Warning: Captured enemy has no actor_id!")
		return

	# Get current captured enemies list from GameState
	var captured: Array = []
	if gs.has_meta("captured_enemies"):
		var meta = gs.get_meta("captured_enemies")
		if typeof(meta) == TYPE_ARRAY:
			captured = meta.duplicate()

	# Add this enemy to the list (allows duplicates for counting)
	captured.append({
		"actor_id": actor_id,
		"display_name": enemy.get("display_name", actor_id),
		"captured_at": Time.get_datetime_string_from_system(),
		"mind_type": enemy.get("mind_type", "none"),
		"env_tag": enemy.get("env_tag", "Regular")
	})

	# Save back to GameState
	gs.set_meta("captured_enemies", captured)

	print("[Battle] Captured enemy added to collection: %s (Total captures: %d)" % [actor_id, captured.size()])
