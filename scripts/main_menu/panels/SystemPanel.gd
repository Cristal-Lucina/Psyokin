extends PanelBase
class_name SystemPanel

## Centers the menu and opens sub-menus above GameMenu (overlay or router).
##
## ARCHITECTURE:
## - Extends PanelBase for lifecycle management
## - Simple button panel (no NavState needed)
## - Opens overlays for Load/Save/Settings/Title menus
## - No popups needed (uses overlay system)

const LOAD_MENU_SCENE : String = "res://scenes/ui/save/LoadMenu.tscn"
const SAVE_MENU_SCENE : String = "res://scenes/ui/save/SaveMenu.tscn"
const OPTIONS_SCENE   : String = "res://scenes/main_menu/Options.tscn"
const TITLE_SCENE     : String = "res://scenes/main_menu/Title.tscn"

@onready var _btn_load     : Button = %LoadBtn
@onready var _btn_save     : Button = %SaveBtn
@onready var _btn_settings : Button = %SettingsBtn
@onready var _btn_title    : Button = %TitleBtn
@onready var _frame_panel  : Panel = %Frame
@onready var _title_label  : Label = get_node("Root/Header/Title")

var _buttons: Array[Button] = []
var _current_button_index: int = 0

func _ready() -> void:
	super()  # Call PanelBase._ready() for lifecycle management

	# Make sure we expand to the PanelHolder's size.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_btn_load.pressed.connect(_open_load)
	_btn_save.pressed.connect(_open_save)
	_btn_settings.pressed.connect(_open_settings)
	_btn_title.pressed.connect(_on_title_pressed)

	# Setup button array for controller navigation
	_buttons = [_btn_load, _btn_save, _btn_settings, _btn_title]

	# Enable focus for all buttons
	for btn in _buttons:
		if btn:
			btn.focus_mode = Control.FOCUS_ALL

	# Apply Core Vibe styling
	_apply_core_vibe_styling()

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to SystemPanel buttons and panel"""

	# Style the main frame panel with WHITE border and BLACK background
	if _frame_panel:
		var panel_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_MILK_WHITE,          # White border
			aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Black background
			1.0,                                       # Full opacity
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px rounded corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		panel_style.content_margin_left = 10
		panel_style.content_margin_top = 10
		panel_style.content_margin_right = 10
		panel_style.content_margin_bottom = 10
		_frame_panel.add_theme_stylebox_override("panel", panel_style)

	# Style the title label: uppercase, centered, larger font
	if _title_label:
		_title_label.text = "SYSTEM"
		_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_label.add_theme_font_size_override("font_size", 22)  # 16 + 6 = 22
		_title_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)

	# Style buttons with colorful accents - when selected, button color fills background with Night Navy text
	if _btn_load:
		aCoreVibeTheme.style_button_with_focus_invert(_btn_load, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_btn_load.custom_minimum_size = Vector2(200, 50)

	if _btn_save:
		aCoreVibeTheme.style_button_with_focus_invert(_btn_save, aCoreVibeTheme.COLOR_ELECTRIC_LIME, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_btn_save.custom_minimum_size = Vector2(200, 50)

	if _btn_settings:
		aCoreVibeTheme.style_button_with_focus_invert(_btn_settings, aCoreVibeTheme.COLOR_CITRUS_YELLOW, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_btn_settings.custom_minimum_size = Vector2(200, 50)

	if _btn_title:
		aCoreVibeTheme.style_button_with_focus_invert(_btn_title, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_btn_title.custom_minimum_size = Vector2(200, 50)

# --- Input Handling -----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_active():
		return

	# Navigate buttons with D-pad/analog stick
	if event.is_action_pressed("move_up"):
		_navigate_buttons(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_buttons(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_activate_current_button()
		get_viewport().set_input_as_handled()

func _navigate_buttons(direction: int) -> void:
	"""Navigate through buttons with controller"""
	_current_button_index += direction

	# Wrap around
	if _current_button_index < 0:
		_current_button_index = _buttons.size() - 1
	elif _current_button_index >= _buttons.size():
		_current_button_index = 0

	# Focus the button
	if _buttons[_current_button_index]:
		_buttons[_current_button_index].grab_focus()
		print("[SystemPanel] Focused button %d: %s" % [_current_button_index, _buttons[_current_button_index].name])

func _activate_current_button() -> void:
	"""Activate the currently focused button"""
	if _current_button_index >= 0 and _current_button_index < _buttons.size():
		var btn := _buttons[_current_button_index]
		if btn:
			print("[SystemPanel] Activating button: %s" % btn.name)
			btn.emit_signal("pressed")

# --- PanelBase Lifecycle Overrides ---------------------------------------------

func _on_panel_gained_focus() -> void:
	super()
	print("[SystemPanel] Gained focus - focusing first button")
	# Focus the first button when panel becomes active
	_current_button_index = 0
	if _btn_load:
		_btn_load.grab_focus()

func _open_load() -> void:
	_open_overlay(LOAD_MENU_SCENE)

func _open_save() -> void:
	print("[SystemPanel] Save button pressed")
	_open_overlay(SAVE_MENU_SCENE)

func _open_settings() -> void:
	_open_overlay(OPTIONS_SCENE)

func _on_title_pressed() -> void:
	"""Show confirmation dialog before returning to title"""
	print("[SystemPanel] Return to Title button pressed - showing confirmation")
	_confirm_return_to_title()

func _confirm_return_to_title() -> void:
	"""Ask user to confirm before returning to title screen"""
	# Create CanvasLayer overlay for popup (outside GameMenu hierarchy)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
	get_tree().root.add_child(overlay)

	var popup := ToastPopup.create("Return to title screen?\n\nAll unsaved progress will be lost.", "Confirm")
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(popup)

	var confirmed: bool = await popup.confirmed

	popup.queue_free()
	overlay.queue_free()

	if confirmed:
		print("[SystemPanel] User confirmed - returning to title")
		_to_title()
	else:
		print("[SystemPanel] User cancelled - staying in game")
		# Re-focus the title button after cancellation
		if _btn_title:
			_btn_title.grab_focus()

func _to_title() -> void:
	"""Return to title screen - clear UI managers only"""
	print("[SystemPanel] Returning to title screen...")

	# CRITICAL: Clear UI manager states but DON'T reset game data
	# Game state is preserved so user can Load if they want
	# Title scene will reset if user clicks New Game

	# 1. Force reset PanelManager (clears stack without lifecycle callbacks)
	if has_node("/root/aPanelManager"):
		print("[SystemPanel] Force resetting PanelManager")
		aPanelManager.force_reset()

	# 2. Reset ControllerManager to OVERWORLD (same as fresh title load)
	# Title.gd handles input in OVERWORLD context just like the initial load
	if has_node("/root/aControllerManager"):
		print("[SystemPanel] Resetting ControllerManager to OVERWORLD")
		aControllerManager.clear_stack()
		aControllerManager.set_context(aControllerManager.InputContext.OVERWORLD)

	# 3. CRITICAL: Unpause the game tree before changing scenes
	# GameMenu pauses the game, but when we change scenes it gets destroyed
	# before its visibility_changed callback can unpause, leaving the game stuck
	print("[SystemPanel] Unpausing game tree")
	get_tree().paused = false

	# Use SceneRouter if available, otherwise change scene directly
	if has_node("/root/aSceneRouter") and aSceneRouter.has_method("goto_title"):
		print("[SystemPanel] Using SceneRouter.goto_title()")
		aSceneRouter.goto_title()
	else:
		print("[SystemPanel] Changing scene directly to title")
		var err := get_tree().change_scene_to_file(TITLE_SCENE)
		if err != OK:
			push_error("[SystemPanel] Failed to change to title scene, error code: %d" % err)

# --- overlay helper ------------------------------------------------------------

func _open_overlay(scene_path: String) -> void:
	print("[SystemPanel] Opening overlay: %s" % scene_path)

	if not ResourceLoader.exists(scene_path):
		push_error("[SystemPanel] Missing scene: %s" % scene_path)
		return

	print("[SystemPanel] Loading scene directly (bypassing router for proper layering)")
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("[SystemPanel] Failed to load PackedScene: %s" % scene_path)
		return

	print("[SystemPanel] Instantiating scene")
	var inst := ps.instantiate()
	if inst == null:
		push_error("[SystemPanel] Failed to instantiate scene")
		return

	print("[SystemPanel] Instantiated node type: ", inst.get_class())
	print("[SystemPanel] Node name: ", inst.name)
	print("[SystemPanel] Has script: ", inst.get_script() != null)
	if inst.get_script():
		print("[SystemPanel] Script path: ", inst.get_script().resource_path)

	# Find the GameMenu to add the overlay on top of it
	var game_menu := get_tree().current_scene.find_child("GameMenu", true, false)
	var parent: Node = null

	if game_menu:
		# Add as sibling to GameMenu so they're at the same level
		parent = game_menu.get_parent()
		print("[SystemPanel] Found GameMenu, adding overlay as sibling to it")
	else:
		# Fallback: add to current scene
		parent = get_tree().current_scene
		print("[SystemPanel] GameMenu not found, adding to current scene")

	if parent == null:
		push_error("[SystemPanel] No valid parent found!")
		return

	print("[SystemPanel] Adding overlay to parent: %s" % parent.name)
	parent.add_child(inst)

	print("[SystemPanel] Added to tree, is_inside_tree: ", inst.is_inside_tree())
	print("[SystemPanel] Node ready status: ", inst.is_node_ready())

	if inst is Control:
		var c := inst as Control
		# Don't use top_level - it breaks the coordinate system
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 3000  # Higher than GameMenu
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.show()  # Ensure it's visible
		print("[SystemPanel] Configured overlay: z_index=3000, visible=true, mouse_filter=STOP")
		print("[SystemPanel] Overlay visible: ", c.visible)
		print("[SystemPanel] Overlay position: ", c.position)
		print("[SystemPanel] Overlay size: ", c.size)
		print("[SystemPanel] Overlay global_position: ", c.global_position)

		# Print tree structure
		print("[SystemPanel] Overlay children count: ", c.get_child_count())
		_print_node_tree(c, 0)

		# Give focus to the overlay for controller support
		call_deferred("_transfer_focus_to_overlay", c)

	print("[SystemPanel] Overlay opened successfully!")

func _transfer_focus_to_overlay(overlay: Control) -> void:
	"""Transfer focus to the overlay for controller support"""
	print("[SystemPanel] Transferring focus to overlay...")

	# Wait one frame to ensure overlay is fully initialized
	await get_tree().process_frame

	# Try to find the first focusable control in the overlay
	var first_focusable := _find_first_focusable(overlay)

	if first_focusable:
		print("[SystemPanel] Found focusable control: %s" % first_focusable.name)
		first_focusable.grab_focus()
		print("[SystemPanel] Focus transferred successfully, has_focus=%s" % first_focusable.has_focus())
	else:
		print("[SystemPanel] Warning: No focusable control found in overlay")

func _find_first_focusable(node: Node) -> Control:
	"""Recursively find the first focusable control in the node tree"""
	if node is Control:
		var control := node as Control
		# Check if this control can receive focus
		if control.focus_mode != Control.FOCUS_NONE and control.visible:
			# Prefer buttons and other interactive controls
			if control is Button or control is LineEdit or control is TextEdit or control is OptionButton:
				return control

	# Search children recursively
	for child in node.get_children():
		var result := _find_first_focusable(child)
		if result:
			return result

	return null

func _print_node_tree(node: Node, indent: int) -> void:
	var prefix = ""
	for i in range(indent):
		prefix += "  "
	print("%s- %s (%s) visible=%s" % [prefix, node.name, node.get_class(), node.visible if node is Control else "N/A"])
	for child in node.get_children():
		_print_node_tree(child, indent + 1)
