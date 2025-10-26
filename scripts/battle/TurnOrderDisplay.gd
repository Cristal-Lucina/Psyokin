extends VBoxContainer
class_name TurnOrderDisplay

## TurnOrderDisplay - Shows the upcoming turn order in battle
## Displays combatant names and initiative in a simplified list

## References
@onready var battle_mgr = get_node("/root/aBattleManager")

## UI config
const SHOW_UPCOMING_TURNS: int = 8  # How many turns to show
const ANIMATION_DURATION: float = 0.3  # Duration of slide animations
const REVEAL_DELAY: float = 0.15  # Delay between each combatant reveal
const KO_FALL_DURATION: float = 0.5  # Duration of KO falling animation

## Container for turn slots
var turn_slots: Array[PanelContainer] = []
var previous_order: Dictionary = {}  # combatant_id -> previous_index
var round_label: Label = null
var current_round: int = 0

func _ready() -> void:
	print("[TurnOrderDisplay] Initializing turn order display")

	# Create round label
	round_label = Label.new()
	round_label.text = "Round 1"
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.add_theme_font_size_override("font_size", 14)
	round_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.5, 1.0))
	add_child(round_label)
	move_child(round_label, 0)  # Put it at the top

	# Connect to battle manager signals
	if battle_mgr:
		battle_mgr.battle_started.connect(_on_battle_started)
		battle_mgr.round_started.connect(_on_round_started)
		battle_mgr.turn_started.connect(_on_turn_started)
		battle_mgr.turn_ended.connect(_on_turn_ended)
		battle_mgr.turn_order_changed.connect(_on_turn_order_changed)

func _on_battle_started() -> void:
	"""Called when battle starts - initial display"""
	print("[TurnOrderDisplay] Battle started, displaying initial turn order")
	current_round = 1
	if round_label:
		round_label.text = "Round 1"
	_rebuild_display_with_reveal()

func _on_round_started(round_number: int) -> void:
	"""Called when a new round starts - refresh the display with animation"""
	print("[TurnOrderDisplay] Round %d started, animating turn order reveal" % round_number)
	current_round = round_number
	if round_label:
		round_label.text = "Round %d" % round_number
	_rebuild_display_with_reveal()

func _on_turn_started(_combatant_id: String) -> void:
	"""Called when a turn starts - highlight current combatant"""
	_update_highlight()

func _on_turn_ended(_combatant_id: String) -> void:
	"""Called when a turn ends"""
	pass

func _on_turn_order_changed() -> void:
	"""Called when turn order is re-sorted mid-round (e.g., from weapon weakness)"""
	print("[TurnOrderDisplay] Turn order changed, animating positions")
	_rebuild_display_animated()

## ═══════════════════════════════════════════════════════════════
## DISPLAY BUILDING
## ═══════════════════════════════════════════════════════════════

func _rebuild_display_with_reveal() -> void:
	"""Rebuild display with sequential reveal animation for new rounds"""
	# Clear existing slots
	for slot in turn_slots:
		slot.queue_free()
	turn_slots.clear()

	# Clear children except round label
	for child in get_children():
		if child != round_label:
			child.queue_free()

	# Get turn order from battle manager
	if not battle_mgr:
		return

	var turn_order = battle_mgr.turn_order
	if turn_order.is_empty():
		return

	# Create slots for upcoming turns with sequential reveal
	var turns_to_show = min(SHOW_UPCOMING_TURNS, turn_order.size())

	for i in range(turns_to_show):
		var combatant = turn_order[i]
		var slot = _create_turn_slot(combatant, i)
		turn_slots.append(slot)
		add_child(slot)

		# Start invisible and off-screen
		slot.modulate.a = 0.0
		slot.position.x = -50

		# Animate into position with delay
		var delay = i * REVEAL_DELAY
		await get_tree().create_timer(delay).timeout

		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Fade in
		tween.tween_property(slot, "modulate:a", 1.0, 0.3)
		# Slide in from left
		tween.tween_property(slot, "position:x", 0, 0.3)

	# Store current order for future animations
	_store_current_order()

func _rebuild_display() -> void:
	"""Rebuild the entire turn order display"""
	# Clear existing slots
	for slot in turn_slots:
		slot.queue_free()
	turn_slots.clear()

	# Clear children except round label
	for child in get_children():
		if child != round_label:
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

	# Store current order for future animations
	_store_current_order()

func _rebuild_display_animated() -> void:
	"""Rebuild display with animations for position changes"""
	if not battle_mgr:
		return

	var turn_order = battle_mgr.turn_order
	if turn_order.is_empty():
		return

	# If no previous order, just rebuild normally
	if previous_order.is_empty():
		_rebuild_display()
		return

	# Build new order mapping
	var new_order: Dictionary = {}
	var turns_to_show = min(SHOW_UPCOMING_TURNS, turn_order.size())
	for i in range(turns_to_show):
		var combatant = turn_order[i]
		new_order[combatant.id] = i

	# Animate existing slots to new positions
	var slots_to_animate: Array[Dictionary] = []

	for slot in turn_slots:
		var combatant_id = slot.get_meta("combatant_id", "")
		if combatant_id != "" and new_order.has(combatant_id):
			var old_index = slot.get_meta("turn_index", -1)
			var new_index = new_order[combatant_id]

			if old_index != new_index:
				# This slot needs to move
				slots_to_animate.append({
					"slot": slot,
					"old_index": old_index,
					"new_index": new_index,
					"combatant_id": combatant_id
				})

	# Perform animations
	if not slots_to_animate.is_empty():
		await _animate_position_changes(slots_to_animate)

	# Explicitly clear all slots before rebuild to prevent duplicates
	for slot in turn_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	turn_slots.clear()

	# Wait one frame to ensure nodes are cleared
	await get_tree().process_frame

	# Full rebuild to update all content (KO status, initiative, etc.)
	_rebuild_display()

func _store_current_order() -> void:
	"""Store current turn order for animation reference"""
	previous_order.clear()
	if not battle_mgr:
		return

	var turn_order = battle_mgr.turn_order
	for i in range(turn_order.size()):
		previous_order[turn_order[i].id] = i

func _animate_position_changes(animations: Array[Dictionary]) -> void:
	"""Animate slots moving to new positions"""
	var tweens: Array = []

	for anim_data in animations:
		var slot: PanelContainer = anim_data.slot
		var old_index: int = anim_data.old_index
		var new_index: int = anim_data.new_index

		# Calculate vertical offset (each slot is ~40px + spacing)
		var slot_height = 45.0  # Approximate height including spacing
		var offset = (new_index - old_index) * slot_height

		# Create tween for this slot
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Animate position offset
		var original_pos = slot.position
		tween.tween_property(slot, "position:y", original_pos.y + offset, ANIMATION_DURATION)

		# Add a slight scale bounce for stumble effect
		if new_index > old_index:
			# Falling down (stumbled)
			tween.parallel().tween_property(slot, "scale", Vector2(1.05, 1.05), ANIMATION_DURATION * 0.5)
			tween.tween_property(slot, "scale", Vector2(1.0, 1.0), ANIMATION_DURATION * 0.5)

		tweens.append(tween)

	# Wait for all tweens to finish
	if not tweens.is_empty():
		await tweens[0].finished

func _create_turn_slot(combatant: Dictionary, index: int) -> PanelContainer:
	"""Create a UI slot for a combatant in the turn order"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 40)
	panel.set_meta("combatant_id", combatant.id)
	panel.set_meta("turn_index", index)

	# Style the panel
	var style = StyleBoxFlat.new()
	var is_ko = combatant.get("is_ko", false)

	if is_ko:
		# Grey out KO'd combatants
		style.bg_color = Color(0.3, 0.3, 0.3, 0.5)  # Grey for KO'd
	elif combatant.is_ally:
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
	if is_ko:
		turn_label.modulate = Color(0.5, 0.5, 0.5, 1.0)
	hbox.add_child(turn_label)

	# Combatant name
	var name_label = Label.new()
	name_label.text = combatant.display_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Color name based on KO or weapon weakness hits
	if is_ko:
		# KO'd = Grey
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	else:
		var weakness_hits = combatant.get("weapon_weakness_hits", 0)
		if weakness_hits >= 2:
			# 2+ hits = Fallen = Red
			name_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
		elif weakness_hits == 1:
			# 1 hit = Yellow warning
			name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.0, 1.0))
		# else: default white color

	hbox.add_child(name_label)

	# Initiative value
	var init_label = Label.new()
	# Show 0 for KO'd combatants
	init_label.text = "0" if is_ko else str(combatant.initiative)
	init_label.add_theme_font_size_override("font_size", 12)
	init_label.modulate = Color(0.5, 0.5, 0.5, 1.0) if is_ko else Color(0.8, 0.8, 0.8, 1.0)
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

func animate_ko_fall(combatant_id: String) -> void:
	"""Animate a combatant falling when KO'd"""
	# Find the slot for this combatant
	var target_slot: PanelContainer = null
	for slot in turn_slots:
		if slot.get_meta("combatant_id", "") == combatant_id:
			target_slot = slot
			break

	if not target_slot:
		return

	print("[TurnOrderDisplay] Animating KO fall for %s" % combatant_id)

	# Create falling animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Rotate slightly while falling
	tween.tween_property(target_slot, "rotation", deg_to_rad(15), KO_FALL_DURATION)
	# Fade out
	tween.parallel().tween_property(target_slot, "modulate:a", 0.3, KO_FALL_DURATION)
	# Scale down
	tween.parallel().tween_property(target_slot, "scale", Vector2(0.8, 0.8), KO_FALL_DURATION)

	# Wait for animation to finish
	await tween.finished

	# Reset rotation and scale (will be rebuilt with greyed style)
	target_slot.rotation = 0
	target_slot.scale = Vector2(1.0, 1.0)
