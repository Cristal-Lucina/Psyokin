extends Control
class_name Battle

## Battle Scene - Main battle screen controller
## Handles UI, combatant display, and player input for combat

@onready var battle_mgr = get_node("/root/aBattleManager")
@onready var gs = get_node("/root/aGameState")
@onready var combat_resolver: CombatResolver = CombatResolver.new()
@onready var csv_loader = get_node("/root/aCSVLoader")
@onready var burst_system = get_node("/root/aBurstSystem")

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
var item_description_label: Label = null  # Item description display
var capture_menu_panel: PanelContainer = null  # Capture selection menu
var burst_menu_panel: PanelContainer = null  # Burst selection menu
var current_skill_menu: Array = []  # Current skills in menu
var selected_item: Dictionary = {}  # Selected item data
var selected_burst: Dictionary = {}  # Selected burst ability data
var victory_panel: PanelContainer = null  # Victory screen panel
var is_in_round_transition: bool = false  # True during round transition animations
var combatant_panels: Dictionary = {}  # combatant_id -> PanelContainer for shake animations

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

	# Connect to turn order display signals
	if turn_order_display and turn_order_display.has_signal("animation_completed"):
		turn_order_display.animation_completed.connect(_on_turn_order_animation_completed)

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

	# Disable all input during round transition
	_disable_all_input()

func _on_turn_started(combatant_id: String) -> void:
	"""Called when a combatant's turn starts"""
	current_combatant = battle_mgr.get_combatant_by_id(combatant_id)

	if current_combatant.is_empty():
		return

	log_message("%s's turn!" % current_combatant.display_name)

	# Check if combatant is asleep - skip turn entirely
	var ailment = str(current_combatant.get("ailment", ""))
	if ailment == "sleep":
		log_message("  → %s is fast asleep... (turn skipped)" % current_combatant.display_name)
		# Wait a moment for readability
		await get_tree().create_timer(1.0).timeout
		# End turn immediately
		battle_mgr.end_turn()
		return

	# Check for Berserk - attack random target (including allies)
	if ailment == "berserk":
		if current_combatant.is_ally:
			log_message("  → %s is berserk and attacks wildly!" % current_combatant.display_name)
			await _execute_berserk_action()
			return
		else:
			# Enemies with berserk just attack normally (already random)
			_execute_enemy_ai()
			return

	# Check for Charm - use heal/buff items on enemy
	if ailment == "charm":
		if current_combatant.is_ally:
			log_message("  → %s is charmed and aids the enemy!" % current_combatant.display_name)
			await _execute_charm_action()
			return
		else:
			# Enemies with charm do nothing (have no heal items to use on player)
			log_message("  → %s is charmed but has no way to help!" % current_combatant.display_name)
			await get_tree().create_timer(1.0).timeout
			battle_mgr.end_turn()
			return

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

func _on_turn_order_animation_completed() -> void:
	"""Called when turn order display animation completes (e.g., round transitions)"""
	# Re-enable input after round transition animation completes
	if is_in_round_transition:
		_enable_all_input()

func _on_battle_ended(victory: bool) -> void:
	"""Called when battle ends"""
	if victory:
		log_message("*** VICTORY ***")
		log_message("All enemies have been defeated!")
		_show_victory_screen()
	else:
		log_message("*** DEFEAT ***")
		log_message("Your party has been wiped out!")
		log_message("GAME OVER")
		# TODO: Show game over screen with retry/load options
		await get_tree().create_timer(3.0).timeout
		# For now, return to main menu or reload
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _show_victory_screen() -> void:
	"""Display victory screen with Accept button"""
	# Create victory panel
	victory_panel = PanelContainer.new()
	victory_panel.name = "VictoryPanel"

	# Set up styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.8, 0.7, 0.3, 1.0)  # Gold border
	victory_panel.add_theme_stylebox_override("panel", style)

	# Position it in center of screen
	victory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	victory_panel.custom_minimum_size = Vector2(500, 450)
	victory_panel.size = Vector2(500, 450)
	victory_panel.position = Vector2(-250, -225)  # Center the 500x450 panel

	# Create vertical box for content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	victory_panel.add_child(vbox)

	# Add some padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	vbox.add_child(margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(content_vbox)

	# Title label
	var title_label = Label.new()
	title_label.text = "VICTORY!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3, 1.0))
	content_vbox.add_child(title_label)

	# Get rewards data from battle manager
	var rewards = battle_mgr.battle_rewards

	# Rewards display
	var rewards_scroll = ScrollContainer.new()
	rewards_scroll.custom_minimum_size = Vector2(400, 200)
	content_vbox.add_child(rewards_scroll)

	var rewards_vbox = VBoxContainer.new()
	rewards_vbox.add_theme_constant_override("separation", 5)
	rewards_scroll.add_child(rewards_vbox)

	# CREDS (changed from Credits)
	if rewards.get("creds", 0) > 0:
		var creds_label = Label.new()
		creds_label.text = "CREDS: +%d" % rewards.creds
		creds_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5, 1.0))
		rewards_vbox.add_child(creds_label)

	# Level Growth - Show LXP for all members who received it
	var lxp_awarded = rewards.get("lxp_awarded", {})
	print("[Battle] lxp_awarded: %s" % lxp_awarded)

	if not lxp_awarded.is_empty():
		var lxp_header = Label.new()
		lxp_header.text = "\nLevel Growth:"
		lxp_header.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1.0))
		rewards_vbox.add_child(lxp_header)

		# Show all members who got XP (they were in the battle)
		for member_id in lxp_awarded.keys():
			var xp_amount = lxp_awarded[member_id]
			var display_name = _get_member_display_name(member_id)
			var member_label = Label.new()
			member_label.text = "  %s: +%d LXP" % [display_name, xp_amount]
			rewards_vbox.add_child(member_label)

	# Sigil Growth - Show each sigil individually with names
	var gxp_awarded = rewards.get("gxp_awarded", {})
	if not gxp_awarded.is_empty():
		var gxp_header = Label.new()
		gxp_header.text = "\nSigil Growth:"
		gxp_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9, 1.0))
		rewards_vbox.add_child(gxp_header)

		var sigil_sys = get_node_or_null("/root/aSigilSystem")
		for sigil_inst_id in gxp_awarded.keys():
			var gxp_amount = gxp_awarded[sigil_inst_id]
			var sigil_name = "Unknown Sigil"
			if sigil_sys and sigil_sys.has_method("get_display_name_for"):
				sigil_name = sigil_sys.get_display_name_for(sigil_inst_id)

			var sigil_label = Label.new()
			sigil_label.text = "  %s: +%d GXP" % [sigil_name, gxp_amount]
			rewards_vbox.add_child(sigil_label)

	# Affinity Growth - Show AXP for each pair
	var axp_awarded = rewards.get("axp_awarded", {})
	if not axp_awarded.is_empty():
		var axp_header = Label.new()
		axp_header.text = "\nAffinity Growth:"
		axp_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.7, 1.0))
		rewards_vbox.add_child(axp_header)

		for pair_key in axp_awarded.keys():
			var axp_amount = axp_awarded[pair_key]

			# Split pair key back into member IDs
			var members = pair_key.split("|")
			if members.size() != 2:
				continue

			var name_a = _get_member_display_name(members[0])
			var name_b = _get_member_display_name(members[1])

			var axp_label = Label.new()
			axp_label.text = "  %s ↔ %s: +%d AXP" % [name_a, name_b, axp_amount]
			rewards_vbox.add_child(axp_label)

	# Items
	var items = rewards.get("items", [])
	if not items.is_empty():
		var items_header = Label.new()
		items_header.text = "\nItems Dropped:"
		items_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.9, 1.0))
		rewards_vbox.add_child(items_header)

		for item_id in items:
			var item_label = Label.new()
			item_label.text = "  %s" % item_id
			rewards_vbox.add_child(item_label)

	# Battle stats
	var stats_label = Label.new()
	var captured = rewards.get("captured_count", 0)
	var killed = rewards.get("killed_count", 0)
	stats_label.text = "\nEnemies: %d captured, %d defeated" % [captured, killed]
	stats_label.add_theme_font_size_override("font_size", 14)
	stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	rewards_vbox.add_child(stats_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	content_vbox.add_child(spacer)

	# Accept button
	var accept_button = Button.new()
	accept_button.text = "Accept"
	accept_button.custom_minimum_size = Vector2(200, 50)
	accept_button.pressed.connect(_on_victory_accept_pressed)

	# Center the button
	var button_center = CenterContainer.new()
	button_center.add_child(accept_button)
	content_vbox.add_child(button_center)

	# Add to scene
	add_child(victory_panel)

func _on_victory_accept_pressed() -> void:
	"""Handle Accept button press on victory screen"""
	print("[Battle] Victory accepted - returning to overworld")
	if victory_panel:
		victory_panel.queue_free()
		victory_panel = null
	battle_mgr.return_to_overworld()

func _get_member_display_name(member_id: String) -> String:
	"""Get display name for a party member"""
	# Special case for hero - get player name
	if member_id == "hero":
		return _get_hero_display_name()

	# Check combatants first for display names from battle
	for combatant in battle_mgr.combatants:
		if combatant.get("id", "") == member_id:
			return combatant.get("display_name", member_id)

	# Fallback to member_id
	return member_id

func _get_hero_display_name() -> String:
	"""Get the hero/player character's display name"""
	# Try to get from GameState
	if gs and gs.has_method("get"):
		var player_name_var = gs.get("player_name")
		if player_name_var and typeof(player_name_var) == TYPE_STRING:
			var player_name = String(player_name_var).strip_edges()
			if player_name != "":
				return player_name

	# Try current combatant
	if current_combatant.get("id", "") == "hero":
		var display = current_combatant.get("display_name", "")
		if display != "":
			return display

	# Fallback
	return "Hero"

func _check_freeze_action_allowed() -> bool:
	"""Check if a frozen/malaise combatant's action can proceed (30% chance)"""
	var ailment = str(current_combatant.get("ailment", ""))

	if ailment not in ["freeze", "malaise"]:
		return true  # Not frozen or malaise, action always allowed

	# Frozen/Malaise: 30% chance to act
	var success_chance = 30
	var roll = randi() % 100

	var ailment_name = "freeze" if ailment == "freeze" else "malaise"

	if roll < success_chance:
		log_message("  → %s struggles through the %s! (%d%% chance, rolled %d)" % [
			current_combatant.display_name, ailment_name, success_chance, roll
		])
		return true
	else:
		log_message("  → %s is unable to act due to %s! (%d%% chance, rolled %d)" % [
			current_combatant.display_name, ailment_name, success_chance, roll
		])
		# End turn without acting
		battle_mgr.end_turn()
		return false

func _wake_if_asleep(target: Dictionary) -> void:
	"""Wake up a target if they're asleep (called when taking damage)"""
	var ailment = str(target.get("ailment", ""))

	if ailment == "sleep":
		target.ailment = ""
		target.ailment_turn_count = 0
		log_message("  → %s woke up from the hit!" % target.display_name)
		# Refresh turn order to remove sleep indicator
		if battle_mgr:
			battle_mgr.refresh_turn_order()

func _set_fainted(target: Dictionary) -> void:
	"""Mark a combatant as fainted (KO'd) and set Fainted status ailment"""
	target.is_ko = true
	target.ailment = "fainted"
	target.ailment_turn_count = 0
	# Refresh turn order to show fainted status
	if battle_mgr:
		battle_mgr.refresh_turn_order()

func _set_captured(target: Dictionary) -> void:
	"""Mark a combatant as captured and set Captured status ailment"""
	target.is_ko = true
	target.is_captured = true
	target.ailment = "captured"
	target.ailment_turn_count = 0
	# Refresh turn order to show captured status
	if battle_mgr:
		battle_mgr.refresh_turn_order()

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

	# Clear panel references
	combatant_panels.clear()

	# Display allies
	var allies = battle_mgr.get_ally_combatants()
	for ally in allies:
		var slot = _create_combatant_slot(ally, true)
		ally_slots.add_child(slot)
		combatant_panels[ally.id] = slot

	# Display enemies
	var enemies = battle_mgr.get_enemy_combatants()
	for enemy in enemies:
		var slot = _create_combatant_slot(enemy, false)
		enemy_slots.add_child(slot)
		combatant_panels[enemy.id] = slot

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

	# Status button to show detailed status effects
	var status_button = Button.new()
	status_button.text = "Status"
	status_button.custom_minimum_size = Vector2(120, 25)
	status_button.pressed.connect(_show_status_details.bind(combatant))
	vbox.add_child(status_button)

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

func _shake_combatant_panel(combatant_id: String) -> void:
	"""Shake a combatant's panel when they take damage"""
	if not combatant_panels.has(combatant_id):
		return

	var panel = combatant_panels[combatant_id]
	var original_position = panel.position

	# Create shake animation using Tween
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Shake sequence: left, right, left, right, center
	var shake_intensity = 8.0
	var shake_duration = 0.05

	tween.tween_property(panel, "position", original_position + Vector2(-shake_intensity, 0), shake_duration)
	tween.tween_property(panel, "position", original_position + Vector2(shake_intensity, 0), shake_duration)
	tween.tween_property(panel, "position", original_position + Vector2(-shake_intensity * 0.5, 0), shake_duration)
	tween.tween_property(panel, "position", original_position + Vector2(shake_intensity * 0.5, 0), shake_duration)
	tween.tween_property(panel, "position", original_position, shake_duration)

func _show_status_details(combatant: Dictionary) -> void:
	"""Show detailed status information popup for a combatant"""
	# Create modal background (blocks clicks)
	var modal_bg = ColorRect.new()
	modal_bg.color = Color(0, 0, 0, 0.5)  # Semi-transparent black overlay
	modal_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_bg.z_index = 99
	modal_bg.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all clicks
	add_child(modal_bg)

	# Create popup panel - fully opaque, no transparency
	var popup = PanelContainer.new()
	popup.custom_minimum_size = Vector2(400, 300)
	popup.modulate.a = 1.0  # 100% solid, no transparency

	# Add solid dark background style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)  # Solid dark blue-gray
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.4, 0.6, 0.8, 1.0)  # Light blue border
	popup.add_theme_stylebox_override("panel", panel_style)

	# Center it on screen
	popup.position = get_viewport_rect().size / 2 - popup.custom_minimum_size / 2
	popup.z_index = 100
	popup.mouse_filter = Control.MOUSE_FILTER_STOP  # Prevent clicking through

	var vbox = VBoxContainer.new()
	popup.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "=== %s Status ===" % combatant.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 220)
	vbox.add_child(scroll)

	var content = VBoxContainer.new()
	scroll.add_child(content)

	# Ailment
	var ailment = str(combatant.get("ailment", ""))
	if ailment != "" and ailment != "null":
		var ailment_label = Label.new()
		ailment_label.text = "❌ Ailment: %s" % ailment.capitalize()
		ailment_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		content.add_child(ailment_label)

	# Buffs/Debuffs
	if combatant.has("buffs"):
		var buffs = combatant.get("buffs", [])
		if buffs.size() > 0:
			var buff_title = Label.new()
			buff_title.text = "\n--- Active Effects (%d) ---" % buffs.size()
			buff_title.add_theme_font_size_override("font_size", 14)
			content.add_child(buff_title)

			for buff in buffs:
				if typeof(buff) == TYPE_DICTIONARY:
					var buff_type = str(buff.get("type", ""))
					var value = float(buff.get("value", 0.0))
					var duration = int(buff.get("duration", 0))

					var buff_text = _format_buff_description(buff_type, value, duration)
					var buff_label = Label.new()
					buff_label.text = buff_text

					# Color based on positive/negative
					if value > 0:
						buff_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 1.0))
					else:
						buff_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3, 1.0))

					content.add_child(buff_label)

	# If no effects
	if ailment == "" or ailment == "null":
		if not combatant.has("buffs") or combatant.buffs.size() == 0:
			var none_label = Label.new()
			none_label.text = "\n✓ No status effects"
			none_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
			content.add_child(none_label)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func():
		popup.queue_free()
		modal_bg.queue_free()  # Remove modal background too
	)
	vbox.add_child(close_btn)

	add_child(popup)

func _format_buff_description(buff_type: String, value: float, duration: int) -> String:
	"""Format buff/debuff into readable description"""
	var type_name = ""
	var symbol = "↑" if value > 0 else "↓"

	match buff_type.to_lower():
		"atk_up", "atk_down", "atk":
			type_name = "Attack"
		"skl_up", "skl_down", "skl", "mnd_up", "mnd_down", "mnd":
			type_name = "Skill/Mind"
		"def_up", "def_down", "def":
			type_name = "Defense"
		"spd_up", "spd_down", "spd", "speed":
			type_name = "Speed"
		"phys_acc", "acc_up", "acc_down", "acc":
			type_name = "Physical Accuracy"
		"mind_acc", "skill_acc":
			type_name = "Skill Accuracy"
		"evasion", "evade", "eva_up", "eva_down":
			type_name = "Evasion"
		"regen":
			return "● Regen (%d%% per round, %d rounds left)" % [int(value * 100), duration]
		"reflect":
			var element = ""
			return "◆ Reflect (%d rounds left)" % duration
		_:
			type_name = buff_type.replace("_", " ").capitalize()

	var percent = int(abs(value) * 100)
	return "%s %s %s%d%% (%d rounds left)" % [symbol, type_name, "+" if value > 0 else "-", percent, duration]

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

func _disable_all_input() -> void:
	"""Disable all input during round transitions to prevent glitches"""
	is_in_round_transition = true

	# Disable action menu (blocks all button clicks)
	if action_menu:
		action_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Disable ally slots (prevent clicking on characters)
	if ally_slots:
		ally_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Disable enemy slots (prevent clicking on enemies)
	if enemy_slots:
		enemy_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE

	print("[Battle] Input disabled during round transition")

func _enable_all_input() -> void:
	"""Re-enable all input after round transition completes"""
	is_in_round_transition = false

	# Re-enable action menu
	if action_menu:
		action_menu.mouse_filter = Control.MOUSE_FILTER_STOP

	# Re-enable ally slots
	if ally_slots:
		ally_slots.mouse_filter = Control.MOUSE_FILTER_STOP

	# Re-enable enemy slots
	if enemy_slots:
		enemy_slots.mouse_filter = Control.MOUSE_FILTER_STOP

	print("[Battle] Input re-enabled after round transition")

func _on_attack_pressed() -> void:
	"""Handle Attack action - prompt user to select target"""
	# Block input during round transitions
	if is_in_round_transition:
		return

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

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

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

			# Wake up if asleep
			_wake_if_asleep(target)

			if target.hp <= 0:
				target.hp = 0
				_set_fainted(target)

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
	# Block input during round transitions
	if is_in_round_transition:
		return

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
				"sigil_inst_id": sigil_inst,  # Track which sigil this skill comes from
				"skill_id": skill_id,
				"skill_data": skill_data,
				"can_afford": can_afford
			})

	if skill_menu.is_empty():
		log_message("No skills available!")
		return

	# Show skill selection menu
	_show_skill_menu(skill_menu)

func _categorize_battle_item(item_id: String, item_name: String, item_def: Dictionary) -> String:
	"""Categorize an item into Restore, Cure, Tactical, or Combat"""
	var effect = str(item_def.get("battle_status_effect", ""))

	# Check for Cure items (status ailment cures)
	if item_id.begins_with("CURE_") or "Cure" in effect:
		return "Cure"

	# Check for Restore items (HP/MP healing, revival, elixirs)
	if item_id.begins_with("HP_") or item_id.begins_with("MP_") or item_id.begins_with("REV_") or \
	   item_id.begins_with("HEAL_") or item_id.begins_with("ELX_") or \
	   "Heal" in effect or "Revive" in effect:
		return "Restore"

	# Check for Combat items (bombs, AOE damage)
	if "Bomb" in item_name or "AOE dmg" in effect:
		return "Combat"

	# Check for Tactical items (buffs, mirrors, speed/defense boosts, escape items)
	if item_id.begins_with("BUFF_") or item_id.begins_with("TOOL_") or "Reflect" in effect or \
	   "Up" in effect or "Shield" in effect or "Regen" in effect or \
	   "Speed" in effect or "Hit%" in effect or "Evasion%" in effect or "SkillHit%" in effect or \
	   "escape" in effect or "Run%" in effect:
		return "Tactical"

	# Default to Tactical if we can't determine
	return "Tactical"

func _on_item_pressed() -> void:
	"""Handle Item action - show usable items menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

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

		# Debug: Print use_type for all items to see what we're getting
		print("[Battle] Item %s: use_type='%s', category='%s', count=%d" % [item_id_str, use_type, category, count])

		# Include items that can be used in battle (use_type = "battle" or "both")
		# Exclude bind items (those are for Capture button)
		# Exclude Sigils (those are equipment, not consumables)
		if use_type in ["battle", "both"] and category != "Battle Items" and category != "Sigils":
			var desc = item_def.get("short_description", "")
			if desc == null:
				desc = ""
			else:
				desc = str(desc)
				if desc == "null":
					desc = ""

			# Debug: Check what description we're getting
			if item_id_str.begins_with("BUFF_") or item_id_str.begins_with("BAT_"):
				print("[Battle] Item %s description: '%s'" % [item_id_str, desc])

			var item_name = item_def.get("name", "")
			if item_name == null or item_name == "":
				item_name = item_id_str
			item_name = str(item_name)

			var targeting = item_def.get("targeting", "Ally")
			if targeting == null:
				targeting = "Ally"
			targeting = str(targeting)

			# Categorize the item
			var item_category = _categorize_battle_item(item_id_str, item_name, item_def)

			usable_items.append({
				"id": item_id_str,
				"name": item_name,
				"display_name": item_name,
				"description": desc,
				"count": count,
				"targeting": targeting,
				"item_def": item_def,
				"battle_category": item_category
			})

	print("[Battle] Found %d usable items for battle" % usable_items.size())
	if usable_items.is_empty():
		log_message("No usable items!")
		return

	# Show item selection menu
	_show_item_menu(usable_items)

func _on_capture_pressed() -> void:
	"""Handle Capture action - show bind item selection menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

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

			var desc = item_def.get("short_description", "")
			if desc == null:
				desc = ""
			desc = str(desc)

			var bind_name = item_def.get("name", "")
			if bind_name == null or bind_name == "":
				bind_name = bind_id
			bind_name = str(bind_name)

			# Read capture modifier from stat_boost field (since capture_mod doesn't exist in CSV)
			var capture_mod_raw = item_def.get("stat_boost", 0)
			var capture_mod_val = int(capture_mod_raw) if capture_mod_raw != null else 0
			print("[Battle] Bind item %s (%s) capture modifier: %d%%" % [bind_id, bind_name, capture_mod_val])

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

	print("[Battle] bind_data contents: %s" % bind_data)
	var bind_id: String = bind_data.id
	var bind_name: String = bind_data.name
	var capture_mod: int = bind_data.capture_mod
	print("[Battle] Extracted capture_mod value: %d" % capture_mod)

	# Calculate capture chance
	var capture_result = combat_resolver.calculate_capture_chance(target, {"item_mod": capture_mod})
	var capture_chance: float = capture_result.chance
	print("[Battle] Capture calculation result: %s" % capture_result)

	log_message("%s uses %s on %s!" % [current_combatant.display_name, bind_name, target.display_name])
	log_message("  Capture chance: %.1f%%" % capture_chance)

	# Attempt capture
	var success = combat_resolver.attempt_capture(target, capture_chance)

	# Consume the bind item
	var inventory = get_node("/root/aInventorySystem")
	inventory.remove_item(bind_id, 1)

	if success:
		# Capture successful!
		_set_captured(target)  # Remove from battle and mark as captured
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

		# Check if battle is over (after capture)
		print("[Battle] Checking if battle ended after capture...")
		var battle_ended = await battle_mgr._check_battle_end()
		print("[Battle] Battle end check result: %s" % battle_ended)
		if battle_ended:
			print("[Battle] Battle ended - skipping end turn")
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

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Get the item that was selected
	if selected_item.is_empty():
		log_message("Item usage failed - no item selected!")
		return

	var item_id: String = selected_item.id
	var item_name: String = selected_item.name
	var item_def: Dictionary = selected_item.item_def

	# Get item properties
	var effect: String = String(item_def.get("battle_status_effect", ""))
	var duration: int = int(item_def.get("round_duration", 1))
	var mind_type_tag: String = String(item_def.get("mind_type_tag", "none")).to_lower()
	var targeting: String = String(item_def.get("targeting", "Ally"))

	# ═══════ MIRROR ITEMS (Reflect) ═══════
	if "Reflect" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Extract element type from effect (e.g., "Reflect: Fire (1 hit)")
		var reflect_type = mind_type_tag  # Use mind_type_tag from item
		if reflect_type == "none" or reflect_type == "":
			# Try to extract from effect string
			var lower_effect = effect.to_lower()
			if "fire" in lower_effect:
				reflect_type = "fire"
			elif "water" in lower_effect:
				reflect_type = "water"
			elif "earth" in lower_effect:
				reflect_type = "earth"
			elif "air" in lower_effect:
				reflect_type = "air"
			elif "data" in lower_effect:
				reflect_type = "data"
			elif "void" in lower_effect:
				reflect_type = "void"
			elif "any" in lower_effect or "mind" in lower_effect:
				reflect_type = "any"

		# Add reflect buff
		if not target.has("buffs"):
			target.buffs = []

		target.buffs.append({
			"type": "reflect",
			"element": reflect_type,
			"duration": duration,
			"source": item_name
		})

		log_message("  → %s is protected by a %s Mirror! (Duration: %d rounds)" % [target.display_name, reflect_type.capitalize(), duration])

	# ═══════ BOMB ITEMS (AOE Damage) ═══════
	elif "AOE" in effect or "Bomb" in item_name:
		# Get bomb element from mind_type_tag
		var bomb_element = mind_type_tag

		# Calculate bomb damage (fixed potency for now, can be adjusted)
		var base_damage = 50  # Base bomb damage (50 direct AOE damage)
		var bomb_targets = battle_mgr.get_enemy_combatants()

		log_message("  → %s explodes, hitting all enemies!" % item_name)

		var ko_list = []  # Track defeated enemies for animation

		for enemy in bomb_targets:
			if enemy.is_ko:
				continue

			# Apply type effectiveness
			var type_bonus = 0.0
			if bomb_element != "none" and combat_resolver:
				# Create a temp attacker dict with the bomb's element
				var temp_attacker = {"mind_type": bomb_element}
				type_bonus = combat_resolver.get_mind_type_bonus(temp_attacker, enemy)

			var damage = int(base_damage * (1.0 + type_bonus))
			enemy.hp = max(0, enemy.hp - damage)

			var type_msg = ""
			if type_bonus > 0:
				type_msg = " (Weakness!)"
			elif type_bonus < 0:
				type_msg = " (Resisted)"

			log_message("    %s takes %d damage%s!" % [enemy.display_name, damage, type_msg])

			# Check for KO
			if enemy.hp <= 0:
				_set_fainted(enemy)
				log_message("    %s was defeated!" % enemy.display_name)
				battle_mgr.record_enemy_defeat(enemy, false)
				ko_list.append(enemy)

		_update_combatant_displays()

		# Animate KO fall for each defeated enemy (refresh after each one)
		if ko_list.size() > 0:
			for ko_enemy in ko_list:
				if turn_order_display:
					await turn_order_display.animate_ko_fall(ko_enemy.id)
				battle_mgr.refresh_turn_order()

	# ═══════ FLASH POP (Evasion + Run Boost) ═══════
	elif "Run%" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		if not target.has("buffs"):
			target.buffs = []

		# Extract run% bonus from effect (e.g., "Run% +20%")
		var run_bonus = 20.0  # Default bonus
		var regex = RegEx.new()
		regex.compile("Run%\\s*\\+?(\\d+)%?")
		var result = regex.search(effect)
		if result:
			run_bonus = float(result.get_string(1))

		# Add run boost buff
		target.buffs.append({
			"type": "run_boost",
			"value": run_bonus,
			"duration": duration,
			"source": item_name
		})

		log_message("  → %s's escape chance increased by %d%%!" % [target.display_name, int(run_bonus)])

		# Also apply evasion buff if present
		if "Evasion Up" in effect:
			var evasion_value = 10  # Default +10% evasion
			var evasion_regex = RegEx.new()
			evasion_regex.compile("Evasion Up \\+?(\\d+)%")
			var evasion_result = evasion_regex.search(effect)
			if evasion_result:
				evasion_value = int(evasion_result.get_string(1))

			target.buffs.append({
				"type": "evasion",
				"value": evasion_value,
				"duration": duration,
				"source": item_name
			})
			log_message("  → %s's evasion increased by %d%% for %d round(s)!" % [target.display_name, evasion_value, duration])

	# ═══════ BUFF ITEMS (ATK Up, MND Up, Shield, etc.) ═══════
	elif "Up" in effect or "Shield" in effect or "Regen" in effect or "Speed" in effect or "Hit%" in effect or "Evasion%" in effect or "SkillHit%" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Determine buff type and magnitude
		var buff_type = ""
		var buff_value = 0.0

		if "ATK Up" in effect or "Attack Up" in effect:
			buff_type = "atk_up"
			buff_value = 0.15  # +15% ATK
		elif "SKL Up" in effect or "Skill Up" in effect or "MND Up" in effect:
			buff_type = "skl_up"
			buff_value = 0.15  # +15% SKL
		elif "DEF Up" in effect or "Defense Up" in effect or "Shield" in effect or "-20% dmg" in effect:
			buff_type = "def_up"
			buff_value = 0.20  # -20% damage taken
		elif "Regen" in effect or "Health Up" in effect:
			buff_type = "regen"
			buff_value = 0.10  # 10% HP per round
		elif "+10 Speed" in effect or "Speed Up" in effect:
			buff_type = "spd_up"
			buff_value = 10.0  # +10 Speed (flat bonus)
		elif "+10 Hit%" in effect or "Hit% Up" in effect:
			buff_type = "phys_acc"
			buff_value = 0.10  # +10% physical Hit%
		elif "+10 Evasion%" in effect or "Evasion% Up" in effect:
			buff_type = "evasion"
			buff_value = 0.10  # +10% Eva%
		elif "+10 SkillHit%" in effect or "SkillHit% Up" in effect:
			buff_type = "mind_acc"
			buff_value = 0.10  # +10% Skill Hit%

		if buff_type != "":
			battle_mgr.apply_buff(target, buff_type, buff_value, duration)
			log_message("  → %s gained %s for %d turns!" % [target.display_name, buff_type.replace("_", " ").capitalize(), duration])
			# Refresh turn order to show buff immediately
			if battle_mgr:
				battle_mgr.refresh_turn_order()

	# ═══════ CURE ITEMS (Remove ailments) ═══════
	elif "Cure" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		var cured_ailment = ""
		if "Poison" in effect:
			cured_ailment = "poison"
		elif "Burn" in effect:
			cured_ailment = "burn"
		elif "Sleep" in effect:
			cured_ailment = "sleep"
		elif "Freeze" in effect:
			cured_ailment = "freeze"
		elif "Confuse" in effect:
			cured_ailment = "confused"
		elif "Charm" in effect:
			cured_ailment = "charm"
		elif "Berserk" in effect:
			cured_ailment = "berserk"
		elif "Malaise" in effect:
			cured_ailment = "malaise"
		elif "Attack Down" in effect:
			# Remove attack down debuff
			if target.has("debuffs"):
				target.debuffs = target.debuffs.filter(func(d): return d.get("type", "") != "attack_down")
			log_message("  → Cured Attack Down!")
		elif "Defense Down" in effect:
			if target.has("debuffs"):
				target.debuffs = target.debuffs.filter(func(d): return d.get("type", "") != "defense_down")
			log_message("  → Cured Defense Down!")
		elif "Mind Down" in effect:
			if target.has("debuffs"):
				target.debuffs = target.debuffs.filter(func(d): return d.get("type", "") != "mind_down")
			log_message("  → Cured Mind Down!")

		if cured_ailment != "":
			var current_ailment = str(target.get("ailment", ""))
			if current_ailment == cured_ailment:
				target.ailment = ""
				target.ailment_turn_count = 0
				log_message("  → Cured %s!" % cured_ailment.capitalize())
				# Refresh turn order to remove status indicator
				if battle_mgr:
					battle_mgr.refresh_turn_order()
			else:
				log_message("  → %s doesn't have %s!" % [target.display_name, cured_ailment.capitalize()])

	# ═══════ HEAL ITEMS ═══════
	elif "Heal" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Parse heal amount from effect string (e.g., "Heal 50 HP")
		var hp_heal = 0
		var mp_heal = 0

		if "HP" in effect:
			# Extract number or percentage before "HP"
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*%?\\s*[HM]")  # Match "50 HP" or "25% HP" or "50% MaxHP"
			var result = regex.search(effect)
			if result:
				var value_str = result.get_string(1)
				var heal_value = int(value_str)

				# Check if it's a percentage heal
				if "%" in effect:
					hp_heal = int(target.hp_max * heal_value / 100.0)
				else:
					hp_heal = heal_value

		if "MP" in effect:
			# Extract number or percentage before "MP"
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*%?\\s*[HM]")
			var result = regex.search(effect)
			if result:
				var value_str = result.get_string(1)
				var heal_value = int(value_str)

				# Check if it's a percentage heal
				if "%" in effect:
					mp_heal = int(target.mp_max * heal_value / 100.0)
				else:
					mp_heal = heal_value

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

	# ═══════ REVIVE ITEMS ═══════
	elif "Revive" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		if target.is_ko:
			# Extract revive percentage
			var revive_percent = 25  # Default 25%
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*%")
			var result = regex.search(effect)
			if result:
				revive_percent = int(result.get_string(1))

			target.is_ko = false
			target.ailment = ""  # Clear Fainted status
			target.ailment_turn_count = 0
			target.hp = max(1, int(target.hp_max * revive_percent / 100.0))
			log_message("  → %s was revived with %d HP!" % [target.display_name, target.hp])
			# Refresh turn order to show revive
			if battle_mgr:
				battle_mgr.refresh_turn_order()
			_update_combatant_displays()
		else:
			log_message("  → %s is not KO'd!" % target.display_name)

	# ═══════ AILMENT/DEBUFF ITEMS (Inflict Status) ═══════
	# Check if this item inflicts an ailment or debuff
	var ailment_to_apply = ""
	var debuff_to_apply = ""

	# Match ailments
	if "Poison" in effect and "Cure" not in effect:
		ailment_to_apply = "poison"
	elif "Burn" in effect and "Cure" not in effect:
		ailment_to_apply = "burn"
	elif "Sleep" in effect and "Cure" not in effect:
		ailment_to_apply = "sleep"
	elif "Freeze" in effect and "Cure" not in effect:
		ailment_to_apply = "freeze"
	elif "Confuse" in effect and "Cure" not in effect:
		ailment_to_apply = "confuse"
	elif "Charm" in effect and "Cure" not in effect:
		ailment_to_apply = "charm"
	elif "Berserk" in effect and "Cure" not in effect:
		ailment_to_apply = "berserk"
	elif "Malaise" in effect and "Cure" not in effect:
		ailment_to_apply = "malaise"
	elif "Mind Block" in effect and "Cure" not in effect:
		ailment_to_apply = "mind_block"

	# Match debuffs
	if "Attack Down" in effect and "Cure" not in effect:
		debuff_to_apply = "atk_down"
	elif "Defense Down" in effect and "Cure" not in effect:
		debuff_to_apply = "def_down"
	elif "Skill Down" in effect and "Cure" not in effect:
		debuff_to_apply = "skl_down"
	elif "Mind Down" in effect and "Cure" not in effect:
		debuff_to_apply = "skl_down"  # Mind Down same as Skill Down

	# Apply ailment if found
	if ailment_to_apply != "":
		# Check if target already has an ailment (only one independent ailment allowed)
		var current_ailment = str(target.get("ailment", ""))
		if current_ailment != "" and current_ailment != "null":
			log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])
			log_message("  → But %s already has %s! (Ailment blocked)" % [target.display_name, current_ailment.capitalize()])
		else:
			log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])
			target.ailment = ailment_to_apply
			target.ailment_turn_count = 0  # Track how many turns they've had this ailment
			log_message("  → %s is now %s!" % [target.display_name, ailment_to_apply.capitalize()])
			# Refresh turn order to show status
			if battle_mgr:
				battle_mgr.refresh_turn_order()

	# Apply debuff if found
	if debuff_to_apply != "":
		if ailment_to_apply == "":  # Only log if we didn't already log for ailment
			log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Debuffs are negative buffs (-15% for stat debuffs)
		battle_mgr.apply_buff(target, debuff_to_apply, -0.15, duration)

		var debuff_name = debuff_to_apply.replace("_", " ").capitalize()
		log_message("  → %s's %s reduced by 15%% for %d turns!" % [target.display_name, debuff_name, duration])
		# Refresh turn order to show debuff
		if battle_mgr:
			battle_mgr.refresh_turn_order()

	# Consume the item
	var inventory = get_node("/root/aInventorySystem")
	inventory.remove_item(item_id, 1)

	# End turn
	battle_mgr.end_turn()

func _on_defend_pressed() -> void:
	"""Handle Defend action"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	log_message("%s moved into a defensive stance." % current_combatant.display_name)
	current_combatant.is_defending = true

	# End turn
	battle_mgr.end_turn()

func _on_burst_pressed() -> void:
	"""Handle Burst action - show burst abilities menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Only hero can use burst abilities
	if current_combatant.get("id", "") != "hero":
		log_message("Only %s can use Burst abilities!" % _get_hero_display_name())
		return

	if not burst_system:
		log_message("Burst system not available!")
		return

	if not battle_mgr:
		log_message("Battle manager not available!")
		return

	# Get current party IDs (all allies in battle)
	var party_ids: Array = []
	var allies = battle_mgr.get_ally_combatants()
	if allies:
		for combatant in allies:
			if combatant and not combatant.get("is_ko", false):
				var id = combatant.get("id", "")
				if id != "":
					party_ids.append(id)

	if party_ids.is_empty():
		log_message("No active party members!")
		return

	# Get available burst abilities
	var available_bursts = burst_system.get_available_bursts(party_ids)

	if available_bursts.is_empty():
		log_message("No burst abilities unlocked yet!")
		return

	# Show burst selection menu
	_show_burst_menu(available_bursts)

func _on_run_pressed() -> void:
	"""Handle Run action"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

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

	# Check for run chance bonus from items (Flash Pop buff on current combatant)
	var item_bonus: float = 0.0
	if current_combatant and current_combatant.has("buffs"):
		for buff in current_combatant.buffs:
			if buff.get("type", "") == "run_boost":
				item_bonus = buff.get("value", 0.0)
				break

	# Calculate final run chance
	var final_chance: float = BASE_RUN_CHANCE + hp_bonus + level_bonus + item_bonus

	# Log breakdown for debugging
	if item_bonus > 0:
		log_message("  Base: %d%% | HP Bonus: +%d%% | Level Bonus: +%d%% | Item Bonus: +%d%%" % [
			int(BASE_RUN_CHANCE),
			int(hp_bonus),
			int(level_bonus),
			int(item_bonus)
		])
	else:
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
						await _execute_capture(target)
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
					elif not selected_burst.is_empty():
						# Using a burst ability (single target)
						_clear_target_highlights()
						awaiting_target_selection = false
						_execute_burst_on_target(target)
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

			# Wake up if asleep
			_wake_if_asleep(target)

			if target.hp <= 0:
				target.hp = 0
				_set_fainted(target)

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

func _execute_berserk_action() -> void:
	"""Execute berserk behavior - attack random target including allies"""
	await get_tree().create_timer(0.5).timeout

	# Clear defending status
	current_combatant.is_defending = false

	# Get all alive combatants (allies and enemies)
	var all_targets = []
	for c in battle_mgr.combatants:
		if not c.is_ko and c.id != current_combatant.id:  # Don't target self
			all_targets.append(c)

	if all_targets.size() > 0:
		var target = all_targets[randi() % all_targets.size()]
		log_message("  → %s attacks %s in a berserk rage!" % [current_combatant.display_name, target.display_name])

		# Execute attack (same as normal attack)
		await _execute_attack(target)
	else:
		log_message("  → No one to attack!")
		await get_tree().create_timer(1.0).timeout

	battle_mgr.end_turn()

func _execute_charm_action() -> void:
	"""Execute charm behavior - use heal/buff items on enemies"""
	await get_tree().create_timer(0.5).timeout

	# Get inventory system
	var inventory = get_node("/root/aInventorySystem")
	var item_counts = inventory.get_counts_dict()
	var item_defs = inventory.get_item_defs()

	# Get heal/buff items from inventory
	var heal_buff_items = []
	for item_id in item_counts.keys():
		var quantity = item_counts[item_id]
		if quantity > 0:
			var item_def = item_defs.get(item_id, {})
			var category = _categorize_battle_item(item_id, item_def.get("name", ""), item_def)
			if category in ["Healing", "Buffs"]:
				heal_buff_items.append({"id": item_id, "def": item_def})

	if heal_buff_items.size() > 0:
		# Pick random item
		var item_data = heal_buff_items[randi() % heal_buff_items.size()]
		var item_id = item_data.id
		var item_def = item_data.def

		# Pick random alive enemy as target
		var enemies = battle_mgr.get_enemy_combatants()
		var alive_enemies = enemies.filter(func(e): return not e.is_ko)

		if alive_enemies.size() > 0:
			var target = alive_enemies[randi() % alive_enemies.size()]
			log_message("  → %s uses %s on %s!" % [
				current_combatant.display_name,
				item_def.get("name", item_id),
				target.display_name
			])

			# Use the item
			inventory.remove_item(item_id, 1)
			await _execute_item_usage(target)
		else:
			log_message("  → No enemies to help!")
	else:
		log_message("  → No healing or buff items to use!")

	await get_tree().create_timer(1.0).timeout
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
	"""Show item selection menu with categorized tabs"""
	# Hide action menu
	action_menu.visible = false

	# Categorize items
	var restore_items = []
	var cure_items = []
	var tactical_items = []
	var combat_items = []

	for item in items:
		var category = item.get("battle_category", "Tactical")
		if category == "Restore":
			restore_items.append(item)
		elif category == "Cure":
			cure_items.append(item)
		elif category == "Tactical":
			tactical_items.append(item)
		elif category == "Combat":
			combat_items.append(item)

	# Create item menu panel
	item_menu_panel = PanelContainer.new()
	item_menu_panel.custom_minimum_size = Vector2(550, 0)

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

	# Create tab container
	var tab_container = TabContainer.new()
	tab_container.custom_minimum_size = Vector2(530, 300)
	vbox.add_child(tab_container)

	# Add category tabs (Restore, Cure, Tactical, Combat)
	_add_category_tab(tab_container, "Restore", restore_items)
	_add_category_tab(tab_container, "Cure", cure_items)
	_add_category_tab(tab_container, "Tactical", tactical_items)
	_add_category_tab(tab_container, "Combat", combat_items)

	# Add separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Add description label
	item_description_label = Label.new()
	item_description_label.text = "Hover over an item to see its description"
	item_description_label.add_theme_font_size_override("font_size", 14)
	item_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_description_label.custom_minimum_size = Vector2(530, 60)
	item_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(item_description_label)

	# Add separator
	var sep3 = HSeparator.new()
	vbox.add_child(sep3)

	# Add cancel button
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(530, 40)
	cancel_btn.pressed.connect(_close_item_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(item_menu_panel)
	item_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 550) / 2,
		(get_viewport_rect().size.y - 400) / 2
	)

func _add_category_tab(tab_container: TabContainer, category_name: String, category_items: Array) -> void:
	"""Add a tab for a specific item category with two-column layout"""
	# Create scroll container for items
	var scroll = ScrollContainer.new()
	scroll.name = category_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab_container.add_child(scroll)

	# Create GridContainer for two-column layout
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)

	# Show message if no items in this category
	if category_items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No items in this category"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 14)
		grid.add_child(empty_label)
		return

	# Add item buttons in two columns
	for item_data in category_items:
		var item_name = str(item_data.get("name", "Unknown"))
		var item_count = int(item_data.get("count", 0))
		var item_desc = str(item_data.get("description", ""))

		# Debug: Check what description we have in item_data
		var item_id = str(item_data.get("id", ""))
		if item_id.begins_with("BUFF_") or item_id.begins_with("BAT_") or item_id.begins_with("HP_"):
			print("[Battle] Creating button for %s: description in item_data = '%s'" % [item_id, item_desc])

		var button = Button.new()
		button.text = "%s (x%d)" % [item_name, item_count]
		button.custom_minimum_size = Vector2(250, 40)
		button.pressed.connect(_on_item_selected.bind(item_data))
		button.mouse_entered.connect(_on_item_hover.bind(item_name, item_desc))
		button.mouse_exited.connect(_on_item_unhover)
		grid.add_child(button)

func _close_item_menu() -> void:
	"""Close the item menu"""
	if item_menu_panel:
		item_menu_panel.queue_free()
		item_menu_panel = null

	item_description_label = null

	# Show action menu again
	action_menu.visible = true

func _on_item_hover(item_name: String, item_desc: String) -> void:
	"""Show item description when hovering over button"""
	if item_description_label:
		if item_desc != "":
			item_description_label.text = "%s: %s" % [item_name, item_desc]
		else:
			item_description_label.text = "%s" % item_name

func _on_item_unhover() -> void:
	"""Reset item description when mouse leaves button"""
	if item_description_label:
		item_description_label.text = "Hover over an item to see its description"

func _execute_auto_escape_item(item_data: Dictionary) -> void:
	"""Execute auto-escape item (Smoke Grenade only)"""
	var item_id: String = item_data.get("id", "")
	var item_name: String = item_data.get("name", "Unknown")

	log_message("%s uses %s!" % [current_combatant.display_name, item_name])

	# Consume the item
	var inventory = get_node_or_null("/root/aInventorySystem")
	if inventory:
		inventory.remove_item(item_id, 1)
	else:
		push_error("Inventory system not available!")

	# Auto-escape effect
	log_message("  → Smoke fills the battlefield!")
	await get_tree().create_timer(1.0).timeout
	log_message("The party escapes successfully!")
	await get_tree().create_timer(1.0).timeout
	battle_mgr.current_state = battle_mgr.BattleState.ESCAPED
	battle_mgr.return_to_overworld()

func _on_item_selected(item_data: Dictionary) -> void:
	"""Handle item selection from menu"""
	_close_item_menu()

	# Store selected item
	selected_item = item_data

	var targeting = str(item_data.get("targeting", "Ally"))
	var item_def = item_data.get("item_def", {})
	var effect = str(item_def.get("battle_status_effect", ""))

	# Special handling for auto-escape items (Smoke Grenade only)
	if "Auto-escape" in effect:
		# Execute auto-escape immediately without target selection
		_execute_auto_escape_item(item_data)
		return

	# Special handling for AllEnemies targeting (Bombs)
	if targeting == "AllEnemies":
		# Bombs hit all enemies, no target selection needed
		log_message("%s uses %s!" % [current_combatant.display_name, str(item_data.get("name", "item"))])
		_execute_item_usage({})  # Pass empty dict since bombs hit all enemies
		return

	log_message("Using %s - select target..." % str(item_data.get("name", "item")))

	# Determine target candidates
	if targeting == "Ally":
		var allies = battle_mgr.get_ally_combatants()
		# Check if this is a revive item - if so, allow targeting KO'd allies
		var item_id = str(item_data.get("item_id", ""))
		var is_revive_item = "Revive" in effect or item_id.begins_with("REV_")

		if is_revive_item:
			# Revive items can only target KO'd (fainted) allies
			target_candidates = allies.filter(func(a): return a.is_ko)
		else:
			# Other items can only target alive allies
			target_candidates = allies.filter(func(a): return not a.is_ko)
	else:  # Enemy (single target)
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

	# Create scroll container for bind items (show max 5 items at a time)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, min(bind_items.size(), 5) * 55)  # 55px per item (50px button + 5px spacing)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	# Create VBox for scrollable bind item buttons
	var items_vbox = VBoxContainer.new()
	scroll.add_child(items_vbox)

	# Add bind item buttons
	for i in range(bind_items.size()):
		var bind_data = bind_items[i]
		var bind_name = str(bind_data.get("name", "Unknown"))
		var bind_desc = str(bind_data.get("description", ""))
		var bind_count = int(bind_data.get("count", 0))
		var capture_mod = int(bind_data.get("capture_mod", 0))

		var button = Button.new()
		button.text = "%s (x%d) [+%d%%]\n%s" % [bind_name, bind_count, capture_mod, bind_desc]
		button.custom_minimum_size = Vector2(360, 50)  # Slightly smaller to account for scrollbar
		button.pressed.connect(_on_bind_selected.bind(bind_data))
		items_vbox.add_child(button)

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

## ═══════════════════════════════════════════════════════════════
## BURST MENU & EXECUTION
## ═══════════════════════════════════════════════════════════════

func _show_burst_menu(burst_abilities: Array) -> void:
	"""Show burst ability selection menu"""
	# Hide action menu
	action_menu.visible = false

	# Debug: print burst abilities
	print("[Battle] Showing burst menu with %d abilities" % burst_abilities.size())
	for i in range(burst_abilities.size()):
		print("[Battle] Burst %d: %s" % [i, burst_abilities[i]])

	# Create burst menu panel
	burst_menu_panel = PanelContainer.new()
	burst_menu_panel.custom_minimum_size = Vector2(450, 0)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.3, 0.3, 1.0)  # Red border for bursts
	burst_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	burst_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select Burst Ability"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Show current burst gauge
	var gauge_label = Label.new()
	gauge_label.text = "Burst Gauge: %d / %d" % [battle_mgr.burst_gauge, battle_mgr.BURST_GAUGE_MAX]
	gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gauge_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(gauge_label)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add burst ability buttons
	for i in range(burst_abilities.size()):
		var burst_data = burst_abilities[i]

		# Validate burst_data
		if typeof(burst_data) != TYPE_DICTIONARY:
			print("[Battle] ERROR: Burst data %d is not a dictionary: %s" % [i, burst_data])
			continue

		var burst_name_raw = burst_data.get("name", "Unknown")
		var burst_name = String(burst_name_raw) if burst_name_raw != null else "Unknown"

		var burst_cost_raw = burst_data.get("burst_cost", 50)
		var burst_cost = int(burst_cost_raw) if burst_cost_raw != null else 50

		var description_raw = burst_data.get("description", "")
		var description = ""
		if description_raw != null:
			if typeof(description_raw) == TYPE_FLOAT or typeof(description_raw) == TYPE_INT:
				description = str(description_raw)  # Use str() for numbers
			else:
				description = String(description_raw)
		print("[Battle] Description for burst: '%s' (type: %d)" % [description, typeof(description_raw)])

		var participants_raw = burst_data.get("participants", "")
		var participants_str = String(participants_raw) if participants_raw != null else ""
		var participants = participants_str.split(";", false) if participants_str != "" else []

		# Build participants text safely with display names
		var participants_text = "Solo"
		if participants.size() > 0:
			var participant_names: PackedStringArray = PackedStringArray()
			for p in participants:
				var participant_id = String(p).strip_edges()
				var display_name = _get_member_display_name(participant_id)
				participant_names.append(display_name)
			participants_text = ", ".join(participant_names)

		var can_afford = battle_mgr.burst_gauge >= burst_cost

		# Build button text safely
		var button_text = ""
		button_text += str(burst_name) + " [Cost: " + str(burst_cost) + "]\n"
		button_text += str(description) + "\n"
		button_text += "With: " + str(participants_text)

		print("[Battle] Creating button with text: %s" % button_text)

		var button = Button.new()
		button.text = button_text
		button.custom_minimum_size = Vector2(430, 70)

		# Disable if can't afford
		if not can_afford:
			button.disabled = true
			button.text += "\n[Not enough Burst Gauge]"
		else:
			button.pressed.connect(_on_burst_selected.bind(burst_data))

		vbox.add_child(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(430, 40)
	cancel_btn.pressed.connect(_close_burst_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(burst_menu_panel)
	burst_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 450) / 2,
		100
	)

func _close_burst_menu() -> void:
	"""Close the burst menu"""
	if burst_menu_panel:
		burst_menu_panel.queue_free()
		burst_menu_panel = null

	# Show action menu again
	action_menu.visible = true

func _on_burst_selected(burst_data: Dictionary) -> void:
	"""Handle burst ability selection"""
	_close_burst_menu()

	selected_burst = burst_data
	var burst_name = String(burst_data.get("name", "Unknown"))
	var target_type = String(burst_data.get("target", "Enemies")).to_lower()

	log_message("Selected: %s" % burst_name)

	# Determine targeting
	if "enemies" in target_type or "all enemies" in target_type:
		# AoE burst - hit all enemies
		_execute_burst_aoe()
	elif "enemy" in target_type:
		# Single target - need to select
		var enemies = battle_mgr.get_enemy_combatants()
		target_candidates = enemies.filter(func(e): return not e.is_ko)

		if target_candidates.is_empty():
			log_message("No valid targets!")
			selected_burst = {}
			return

		log_message("Select a target...")
		awaiting_target_selection = true
		_highlight_target_candidates()
	else:
		# Self/Ally targeting not implemented yet
		log_message("This burst targeting not yet implemented")
		selected_burst = {}

func _execute_burst_aoe() -> void:
	"""Execute an AoE burst ability on all enemies"""
	var burst_name = String(selected_burst.get("name", "Unknown"))
	var burst_cost = int(selected_burst.get("burst_cost", 50))
	var power = int(selected_burst.get("power", 120))
	var element = String(selected_burst.get("element", "none")).to_lower()

	# Check and spend burst gauge
	if not battle_mgr.burst_gauge >= burst_cost:
		log_message("Not enough Burst Gauge!")
		selected_burst = {}
		return

	battle_mgr.burst_gauge -= burst_cost
	_update_burst_gauge()

	var hero_name = _get_hero_display_name()
	log_message("%s unleashes %s!" % [hero_name, burst_name])
	log_message("  (Spent %d Burst Gauge)" % burst_cost)

	# Hit all enemies
	var enemies = battle_mgr.get_enemy_combatants()
	var alive_enemies = enemies.filter(func(e): return not e.is_ko)

	for target in alive_enemies:
		await get_tree().create_timer(0.3).timeout
		_execute_burst_on_target(target)

	# End turn after burst
	battle_mgr.end_turn()

func _execute_burst_on_target(target: Dictionary) -> void:
	"""Execute burst ability on a single target"""
	var power = int(selected_burst.get("power", 120))
	var acc = int(selected_burst.get("acc", 95))
	var element = String(selected_burst.get("element", "none")).to_lower()
	var crit_bonus = int(selected_burst.get("crit_bonus_pct", 20))
	var scaling_brw = float(selected_burst.get("scaling_brw", 0.5))
	var scaling_mnd = float(selected_burst.get("scaling_mnd", 1.0))
	var scaling_fcs = float(selected_burst.get("scaling_fcs", 0.5))

	# Check if hit (bursts have high accuracy)
	var hit_check = combat_resolver.check_sigil_hit(current_combatant, target, {"skill_acc": acc})

	if not hit_check.hit:
		log_message("  → Missed %s! (%d%% chance)" % [target.display_name, int(hit_check.hit_chance)])
		return

	# Roll for crit
	var crit_check = combat_resolver.check_critical_hit(current_combatant, {"skill_crit_bonus": crit_bonus})
	var is_crit = crit_check.crit

	# Calculate type effectiveness
	var type_bonus = 0.0
	if element != "none" and element != "":
		type_bonus = combat_resolver.get_mind_type_bonus(
			{"mind_type": element},
			target,
			element
		)

	# Calculate burst damage (higher than regular skills)
	var damage_result = combat_resolver.calculate_sigil_damage(
		current_combatant,
		target,
		{
			"potency": 150,  # Bursts are more powerful
			"is_crit": is_crit,
			"type_bonus": type_bonus,
			"base_sig": power,
			"mnd_scale": scaling_mnd,
			"brw_scale": scaling_brw,
			"fcs_scale": scaling_fcs
		}
	)

	var damage = damage_result.damage

	# Apply damage
	target.hp -= damage

	# Shake the target's panel for visual feedback
	_shake_combatant_panel(target.id)

	# Wake up if asleep
	_wake_if_asleep(target)

	if target.hp <= 0:
		target.hp = 0
		_set_fainted(target)

		# Record kill
		if not target.get("is_ally", false):
			battle_mgr.record_enemy_defeat(target, false)

	# Log the hit
	var hit_msg = "  → BURST HIT %s for %d damage!" % [target.display_name, damage]
	if is_crit:
		hit_msg += " (CRITICAL!)"
	if type_bonus > 0.0:
		hit_msg += " (Super Effective!)"
	elif type_bonus < 0.0:
		hit_msg += " (Not Very Effective...)"
	log_message(hit_msg)

	# Update displays
	_update_combatant_displays()
	if target.is_ko:
		if turn_order_display:
			await turn_order_display.animate_ko_fall(target.id)
		battle_mgr.refresh_turn_order()
	elif turn_order_display:
		turn_order_display.update_combatant_hp(target.id)

func _on_skill_selected(skill_entry: Dictionary) -> void:
	"""Handle skill selection"""
	skill_to_use = skill_entry.skill_data.duplicate()
	skill_to_use["_sigil_inst_id"] = skill_entry.get("sigil_inst_id", "")  # Store sigil ID for tracking
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
	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

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

	# Track sigil usage for bonus GXP
	var sigil_inst_id = skill_to_use.get("_sigil_inst_id", "")
	if sigil_inst_id != "":
		battle_mgr.sigils_used_in_battle[sigil_inst_id] = true

	log_message("%s uses %s!" % [current_combatant.display_name, skill_name])

	# Check if hit
	var hit_check = combat_resolver.check_sigil_hit(current_combatant, target, {"skill_acc": acc})

	if not hit_check.hit:
		log_message("  → Missed! (%d%% chance, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
		return

	# ═══════ CHECK FOR REFLECT (MIRROR) ═══════
	if target.has("buffs") and element != "none" and element != "":
		for i in range(target.buffs.size()):
			var buff = target.buffs[i]
			if buff.get("type", "") == "reflect":
				var reflect_element = buff.get("element", "")

				# Check if this mirror reflects this element
				var should_reflect = false
				if reflect_element == "any":
					should_reflect = true  # Mind Mirror reflects any element
				elif reflect_element == element:
					should_reflect = true  # Element-specific mirror

				if should_reflect:
					# REFLECT! The skill bounces back to the attacker
					log_message("  → %s's Mirror reflects the attack!" % target.display_name)

					# Remove the reflect buff (it's consumed)
					target.buffs.remove_at(i)

					# Redirect the skill to the attacker
					var original_attacker = current_combatant
					var new_target = current_combatant  # The attacker becomes the target

					# Calculate damage for reflected skill
					var reflect_type_bonus = 0.0
					if element != "none" and element != "":
						reflect_type_bonus = combat_resolver.get_mind_type_bonus(
							{"mind_type": element},
							new_target,
							element
						)

					# Calculate reflected damage (no crit on reflect)
					var reflect_damage_result = combat_resolver.calculate_sigil_damage(
						original_attacker,  # Still uses attacker's stats
						new_target,
						{
							"potency": 100,
							"is_crit": false,  # Reflected attacks don't crit
							"type_bonus": reflect_type_bonus,
							"base_sig": power,
							"mnd_scale": mnd_scaling
						}
					)

					var reflect_damage = reflect_damage_result.damage

					# Apply reflected damage
					new_target.hp -= reflect_damage
					if new_target.hp <= 0:
						new_target.hp = 0
						_set_fainted(new_target)
						log_message("  → %s was defeated by the reflection!" % new_target.display_name)
					else:
						log_message("  → %s takes %d reflected damage!" % [new_target.display_name, reflect_damage])

					# Update displays and end skill
					_update_combatant_displays()
					return  # Skill ends here, original target takes no damage

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

	# Shake the target's panel for visual feedback
	_shake_combatant_panel(target.id)

	# Wake up if asleep
	_wake_if_asleep(target)

	if target.hp <= 0:
		target.hp = 0
		target.is_ko = true

		# Record kill for morality system (if enemy)
		if not target.get("is_ally", false):
			battle_mgr.record_enemy_defeat(target, false)  # false = kill

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

	# Apply status effect if skill has one (only if target still alive)
	if not target.is_ko:
		var status_to_apply = str(skill_to_use.get("status_apply", "")).to_lower()
		var status_chance_pct = int(skill_to_use.get("status_chance", 0))

		if status_to_apply != "" and status_to_apply != "null" and status_chance_pct > 0:
			var roll = randi() % 100
			if roll < status_chance_pct:
				# List of independent ailments (only one can exist at a time)
				var independent_ailments = ["burn", "burned", "freeze", "frozen", "sleep", "asleep", "poison", "poisoned", "malaise", "berserk", "charm", "charmed", "confuse", "confused"]

				if status_to_apply in independent_ailments:
					# Check if target already has an ailment
					var current_ailment = str(target.get("ailment", ""))
					if current_ailment != "" and current_ailment != "null":
						log_message("  → Failed to inflict %s! (%s already has %s)" % [status_to_apply.capitalize(), target.display_name, current_ailment.capitalize()])
					else:
						# Apply the ailment
						target.ailment = status_to_apply
						target.ailment_turn_count = 0
						log_message("  → %s is now %s! (%d%% chance, rolled %d)" % [target.display_name, status_to_apply.capitalize(), status_chance_pct, roll])
						battle_mgr.refresh_turn_order()
				else:
					# It's a debuff (not an independent ailment)
					var duration = int(skill_to_use.get("duration", 3))
					# Map status names to debuff types
					var debuff_type = ""
					if "attack down" in status_to_apply or "atk down" in status_to_apply:
						debuff_type = "attack_down"
					elif "defense down" in status_to_apply or "def down" in status_to_apply:
						debuff_type = "defense_down"
					elif "skill down" in status_to_apply or "mind down" in status_to_apply:
						debuff_type = "skill_down"
					elif "speed down" in status_to_apply or "slow" in status_to_apply:
						debuff_type = "speed_down"

					if debuff_type != "":
						battle_mgr.apply_buff(target, debuff_type, -0.15, duration)
						log_message("  → %s's %s reduced! (%d%% chance, rolled %d)" % [target.display_name, status_to_apply.replace("_", " ").capitalize(), status_chance_pct, roll])
						battle_mgr.refresh_turn_order()

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
	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

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
