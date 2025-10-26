extends VBoxContainer
class_name TurnOrderDisplay

## TurnOrderDisplay - Shows the upcoming turn order in battle
## Displays combatant names and initiative in a simplified list

## References
@onready var battle_mgr = get_node("/root/aBattleManager")

## UI config
const SHOW_UPCOMING_TURNS: int = 8  # How many turns to show

## Container for turn slots
var turn_slots: Array[PanelContainer] = []

func _ready() -> void:
	print("[TurnOrderDisplay] Initializing turn order display")

	# Connect to battle manager signals
	if battle_mgr:
		battle_mgr.battle_started.connect(_on_battle_started)
		battle_mgr.round_started.connect(_on_round_started)
		battle_mgr.turn_started.connect(_on_turn_started)
		battle_mgr.turn_ended.connect(_on_turn_ended)

func _on_battle_started() -> void:
	"""Called when battle starts - initial display"""
	print("[TurnOrderDisplay] Battle started, displaying initial turn order")
	_rebuild_display()

func _on_round_started(_round_number: int) -> void:
	"""Called when a new round starts - refresh the display"""
	print("[TurnOrderDisplay] Round started, refreshing turn order")
	_rebuild_display()

func _on_turn_started(_combatant_id: String) -> void:
	"""Called when a turn starts - highlight current combatant"""
	_update_highlight()

func _on_turn_ended(_combatant_id: String) -> void:
	"""Called when a turn ends"""
	pass

## ═══════════════════════════════════════════════════════════════
## DISPLAY BUILDING
## ═══════════════════════════════════════════════════════════════

func _rebuild_display() -> void:
	"""Rebuild the entire turn order display"""
	# Clear existing slots
	for slot in turn_slots:
		slot.queue_free()
	turn_slots.clear()

	# Clear children
	for child in get_children():
		child.queue_free()

	# Get turn order from battle manager
	if not battle_mgr:
		return

	var turn_order = battle_mgr.turn_order
	if turn_order.is_empty():
		return

	# Create slots for upcoming turns
	var turns_to_show = min(SHOW_UPCOMING_TURNS, turn_order.size())

	for i in range(turns_to_show):
		var combatant = turn_order[i]
		var slot = _create_turn_slot(combatant, i)
		turn_slots.append(slot)
		add_child(slot)

func _create_turn_slot(combatant: Dictionary, index: int) -> PanelContainer:
	"""Create a UI slot for a combatant in the turn order"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 40)
	panel.set_meta("combatant_id", combatant.id)
	panel.set_meta("turn_index", index)

	# Style the panel
	var style = StyleBoxFlat.new()
	if combatant.is_ally:
		style.bg_color = Color(0.2, 0.3, 0.5, 0.8)  # Blue-ish for allies
	else:
		style.bg_color = Color(0.5, 0.2, 0.2, 0.8)  # Red-ish for enemies
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	# HBox for layout
	var hbox = HBoxContainer.new()
	panel.add_child(hbox)

	# Turn number indicator
	var turn_label = Label.new()
	turn_label.text = str(index + 1)
	turn_label.custom_minimum_size = Vector2(28, 0)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(turn_label)

	# Combatant name
	var name_label = Label.new()
	name_label.text = combatant.display_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_label)

	# Initiative value
	var init_label = Label.new()
	init_label.text = str(combatant.initiative)
	init_label.add_theme_font_size_override("font_size", 12)
	init_label.modulate = Color(0.8, 0.8, 0.8, 1.0)
	init_label.custom_minimum_size = Vector2(28, 0)
	init_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	init_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(init_label)

	return panel

func _update_highlight() -> void:
	"""Update highlighting to show current turn"""
	if not battle_mgr:
		return

	var current_turn_index = battle_mgr.current_turn_index

	# Update all slots
	for i in range(turn_slots.size()):
		var slot = turn_slots[i]
		var style = slot.get_theme_stylebox("panel") as StyleBoxFlat

		if style:
			# Highlight the current turn
			if i == current_turn_index:
				style.border_width_left = 4
				style.border_width_right = 4
				style.border_width_top = 4
				style.border_width_bottom = 4
				style.border_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow highlight
			else:
				style.border_width_left = 2
				style.border_width_right = 2
				style.border_width_top = 2
				style.border_width_bottom = 2
				style.border_color = Color(0.4, 0.4, 0.4, 1.0)

func update_combatant_hp(_combatant_id: String) -> void:
	"""Update HP display for a specific combatant (simplified - no HP bars in turn order)"""
	# HP updates are shown in the main combatant displays, not here
	pass
