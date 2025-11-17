extends Node
## ControllerIconLayout - Dynamic Controller Button Icon Management
## Provides controller-specific button icons based on detected controller type

## Signals
signal controller_type_changed(new_type: String)

## Current controller type ("xbox", "playstation", "nintendo", "keyboard")
var current_controller_type: String = "xbox"

## Icon theme ("light" or "dark")
var current_theme: String = "light"

## Icon base paths
const ICON_PATH_LIGHT = "res://assets/graphics/icons/UI/PNG and PSD - Light/Controller/1x/"
const ICON_PATH_DARK = "res://assets/graphics/icons/UI/PNG and PSD - Dark/Controller/1x/"

## Button ID mappings for each controller type
## Maps common actions to controller-specific icon assets
const BUTTON_ICONS = {
	"xbox": {
		"accept": "Asset 82.png",        # A button
		"back": "Asset 81.png",          # B button
		"special_1": "Asset 79.png",     # X button
		"special_2": "Asset 80.png",     # Y button
		"l_bumper": "Asset 98.png",      # LB
		"r_bumper": "Asset 97.png",      # RB
		"l_trigger": "Asset 96.png",     # LT
		"r_trigger": "Asset 95.png",     # RT
		"dpad_up": "Asset 71.png",
		"dpad_down": "Asset 69.png",
		"dpad_left": "Asset 68.png",
		"dpad_right": "Asset 70.png",
	},
	"playstation": {
		"accept": "Asset 86.png",        # Cross button
		"back": "Asset 83.png",          # Circle button
		"special_1": "Asset 85.png",     # Square button
		"special_2": "Asset 84.png",     # Triangle button
		"l_bumper": "Asset 94.png",      # L1
		"r_bumper": "Asset 93.png",      # R1
		"l_trigger": "Asset 92.png",     # L2
		"r_trigger": "Asset 91.png",     # R2
		"dpad_up": "Asset 75.png",
		"dpad_down": "Asset 74.png",
		"dpad_left": "Asset 72.png",
		"dpad_right": "Asset 73.png",
	},
	"nintendo": {
		"accept": "Asset 82.png",        # A button (right)
		"back": "Asset 81.png",          # B button (bottom)
		"special_1": "Asset 80.png",     # Y button (left)
		"special_2": "Asset 79.png",     # X button (top)
		"l_bumper": "Asset 98.png",      # LB
		"r_bumper": "Asset 97.png",      # RB
		"l_trigger": "Asset 96.png",     # LT
		"r_trigger": "Asset 95.png",     # RT
		"dpad_up": "Asset 67.png",
		"dpad_down": "Asset 66.png",
		"dpad_left": "Asset 64.png",
		"dpad_right": "Asset 65.png",
	},
}

func _ready() -> void:
	name = "aControllerIconLayout"
	print("[ControllerIconLayout] Initialized")

	# Detect controller type from settings or connected controller
	_detect_controller_type()

func _detect_controller_type() -> void:
	"""Detect which controller type is being used"""
	# First, check if Settings has a preference
	var settings = get_node_or_null("/root/aSettings")
	if settings and settings.has_method("get_value"):
		var control_type = settings.get_value("control_type", "xbox")
		if control_type in ["xbox", "playstation", "nintendo"]:
			set_controller_type(control_type)
			print("[ControllerIconLayout] Loaded control type from settings: %s" % control_type)
			return

	# Otherwise, try to detect from connected joypad
	var joy_count = Input.get_connected_joypads().size()
	if joy_count > 0:
		var joy_index = Input.get_connected_joypads()[0]
		var joy_name = Input.get_joy_name(joy_index).to_lower()

		if "playstation" in joy_name or "ps" in joy_name or "dualshock" in joy_name or "dualsense" in joy_name:
			set_controller_type("playstation")
			print("[ControllerIconLayout] Detected PlayStation controller")
		elif "nintendo" in joy_name or "switch" in joy_name or "joycon" in joy_name:
			set_controller_type("nintendo")
			print("[ControllerIconLayout] Detected Nintendo controller")
		else:
			# Default to Xbox layout for unknown controllers
			set_controller_type("xbox")
			print("[ControllerIconLayout] Defaulting to Xbox layout for unknown controller")
	else:
		# No controller detected, default to Xbox
		set_controller_type("xbox")
		print("[ControllerIconLayout] No controller detected, defaulting to Xbox layout")

func set_controller_type(type: String) -> void:
	"""Set the controller type and emit signal if changed"""
	if type not in ["xbox", "playstation", "nintendo"]:
		push_error("[ControllerIconLayout] Invalid controller type: %s" % type)
		return

	if current_controller_type != type:
		var old_type = current_controller_type
		current_controller_type = type
		print("[ControllerIconLayout] Controller type changed: %s -> %s" % [old_type, current_controller_type])
		controller_type_changed.emit(current_controller_type)

func set_theme(theme: String) -> void:
	"""Set the icon theme (light or dark)"""
	if theme not in ["light", "dark"]:
		push_error("[ControllerIconLayout] Invalid theme: %s" % theme)
		return

	current_theme = theme

func get_button_icon(button_action: String) -> Texture2D:
	"""Get the icon texture for a specific button action"""
	if current_controller_type not in BUTTON_ICONS:
		push_error("[ControllerIconLayout] Invalid controller type: %s" % current_controller_type)
		return null

	var controller_buttons = BUTTON_ICONS[current_controller_type]
	if button_action not in controller_buttons:
		push_error("[ControllerIconLayout] Unknown button action: %s" % button_action)
		return null

	var asset_name = controller_buttons[button_action]
	var icon_path = _get_icon_path()

	# Handle dark theme asset number remapping
	if current_theme == "dark":
		asset_name = _remap_for_dark_theme(asset_name)

	var full_path = icon_path + asset_name

	if ResourceLoader.exists(full_path):
		return load(full_path)
	else:
		push_error("[ControllerIconLayout] Icon not found: %s" % full_path)
		return null

func _get_icon_path() -> String:
	"""Get the base path for icons based on current theme"""
	if current_theme == "dark":
		return ICON_PATH_DARK
	else:
		return ICON_PATH_LIGHT

func _remap_for_dark_theme(asset_name: String) -> String:
	"""Remap asset numbers for dark theme"""
	# Dark theme: Assets 1-49 = Light theme Assets 50-98
	# Special handling: Assets 99-100 (Nintendo +/-) exist in both themes
	if asset_name.begins_with("Asset 99") or asset_name.begins_with("Asset 100"):
		return asset_name

	var asset_num = int(asset_name.replace("Asset ", "").replace(".png", ""))
	if asset_num >= 50 and asset_num <= 98:
		return "Asset " + str(asset_num - 49) + ".png"

	return asset_name

func get_controller_type() -> String:
	"""Get the current controller type"""
	return current_controller_type
