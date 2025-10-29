extends BaseMinigame
class_name BurstMinigame

## BurstMinigame - Button mashing to increase Sync Level for burst attacks
## Faster mashing = higher damage modifier

## Configuration
var affinity: int = 1  # Affinity of burst participants (affects fill speed)

## Internal state
var sync_level: float = 0.0
var max_sync_level: float = 100.0
var button_presses: int = 0
var last_press_time: float = 0.0

## Visual elements
var sync_bar: ProgressBar
var sync_label: Label
var instruction_label: Label
var press_count_label: Label

func _setup_minigame() -> void:
	base_duration = 3.0  # Quick minigame!
	current_duration = base_duration

	# Title
	var title_label = Label.new()
	title_label.text = "BURST SYNC!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	content_container.add_child(title_label)

	# Sync bar
	sync_bar = ProgressBar.new()
	sync_bar.max_value = max_sync_level
	sync_bar.value = 0.0
	sync_bar.show_percentage = false
	sync_bar.custom_minimum_size = Vector2(400, 50)
	var bar_container = CenterContainer.new()
	bar_container.add_child(sync_bar)
	content_container.add_child(bar_container)

	# Sync level label
	sync_label = Label.new()
	sync_label.text = "Sync Level: 0%"
	sync_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sync_label.add_theme_font_size_override("font_size", 24)
	content_container.add_child(sync_label)

	# Press count
	press_count_label = Label.new()
	press_count_label.text = "Presses: 0"
	press_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	press_count_label.add_theme_font_size_override("font_size", 18)
	content_container.add_child(press_count_label)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "MASH SPACE AS FAST AS YOU CAN!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

func _start_minigame() -> void:
	print("[BurstMinigame] Starting - Affinity: %d" % affinity)
	sync_level = 0.0
	button_presses = 0

	# Start timer
	await get_tree().create_timer(current_duration).timeout
	_finish_minigame()

func _process(delta: float) -> void:
	# Check for Space press
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE):
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_press_time > 0.1:  # Debounce
			_on_button_press()
			last_press_time = current_time

	# Decay sync level slightly over time (encourages fast mashing)
	sync_level = max(0, sync_level - (5.0 * delta))

	# Update visuals
	sync_bar.value = sync_level
	sync_label.text = "Sync Level: %d%%" % int(sync_level)

func _on_button_press() -> void:
	"""Handle a button press"""
	button_presses += 1

	# Increase sync level (faster with higher affinity)
	var increase = 5.0 + (affinity * 0.5)
	sync_level = min(max_sync_level, sync_level + increase)

	press_count_label.text = "Presses: %d" % button_presses

	# Visual feedback
	sync_bar.modulate = Color(1.5, 1.5, 1.5, 1.0)
	await get_tree().create_timer(0.05).timeout
	sync_bar.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _finish_minigame() -> void:
	print("[BurstMinigame] Finished - Sync: %.1f%%, Presses: %d" % [sync_level, button_presses])

	instruction_label.text = "Sync Complete!"

	# Calculate damage modifier based on sync level
	var damage_modifier = 1.0 + (sync_level / 100.0)  # 100% sync = 2.0x damage

	var grade = "low"
	if sync_level >= 80:
		grade = "perfect"
	elif sync_level >= 50:
		grade = "good"

	var result = {
		"success": true,
		"grade": grade,
		"damage_modifier": damage_modifier,
		"is_crit": sync_level >= 90,  # Crit if 90%+ sync
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0,
		"sync_level": int(sync_level)
	}

	_complete_minigame(result)
