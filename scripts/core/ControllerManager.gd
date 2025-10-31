extends Node
## ControllerManager - Centralized Controller Input Management
## Manages input contexts, routing, and cooldowns to prevent conflicts

## Input Context Enum
## Defines what screen/panel is currently active
enum InputContext {
	DISABLED,           # All input blocked
	OVERWORLD,         # Walking around the world
	BATTLE_ACTION,     # Battle: main action menu (Attack/Skill/Item/etc)
	BATTLE_SKILL,      # Battle: skill selection submenu
	BATTLE_ITEM,       # Battle: item selection submenu
	BATTLE_CAPTURE,    # Battle: capture binding selection
	BATTLE_BURST,      # Battle: burst ability selection
	BATTLE_STATUS,     # Battle: status screen
	BATTLE_TARGET,     # Battle: target selection overlay
	MENU_MAIN,         # Main pause menu
	MENU_ITEMS,        # Items panel
	MENU_PARTY,        # Party panel
	MENU_SIGILS,       # Sigils panel
	DIALOG,            # Popup dialog (AcceptDialog, ConfirmationDialog)
}

## Signals emitted for controller actions
## Panels connect to these based on their context
signal action_button_pressed(button: String, context: InputContext)
signal navigate_pressed(direction: Vector2, context: InputContext)
signal bumper_pressed(direction: int, context: InputContext)  # -1 for L, +1 for R
signal context_changed(old_context: InputContext, new_context: InputContext)

## Context stack - manages nested UI states (e.g., menu -> dialog -> confirmation)
var context_stack: Array[Dictionary] = []

## Current active context
var current_context: InputContext = InputContext.OVERWORLD

## Additional data for current context (e.g., selected item index, etc.)
var context_data: Dictionary = {}

## Global input cooldown
var input_cooldown: float = 0.0
const INPUT_COOLDOWN_DURATION: float = 0.15  # 150ms between inputs

## Debug mode
var debug_mode: bool = true

func _ready() -> void:
	# Set as autoload singleton
	name = "aControllerManager"
	set_process_input(true)
	print("[ControllerManager] Initialized - Current context: %s" % InputContext.keys()[current_context])

func _process(delta: float) -> void:
	# Update cooldown timer
	if input_cooldown > 0:
		input_cooldown -= delta

## ═══════════════════════════════════════════════════════════════
## CONTEXT MANAGEMENT
## ═══════════════════════════════════════════════════════════════

func push_context(ctx: InputContext, data: Dictionary = {}) -> void:
	"""Push a new context onto the stack (for nested states)"""
	# Save current state to stack
	if current_context != InputContext.DISABLED or not context_stack.is_empty():
		context_stack.push_back({
			"context": current_context,
			"data": context_data.duplicate(true)
		})

	var old_context = current_context

	# Set new context
	current_context = ctx
	context_data = data.duplicate(true)

	if debug_mode:
		print("[ControllerManager] PUSH context: %s → %s (stack depth: %d)" % [
			InputContext.keys()[old_context],
			InputContext.keys()[ctx],
			context_stack.size()
		])

	context_changed.emit(old_context, current_context)

func pop_context() -> void:
	"""Pop the most recent context from the stack"""
	if context_stack.is_empty():
		push_error("[ControllerManager] Attempted to pop with empty stack!")
		set_context(InputContext.OVERWORLD)
		return

	var old_context = current_context
	var prev = context_stack.pop_back()
	current_context = prev["context"]
	context_data = prev["data"].duplicate(true)

	if debug_mode:
		print("[ControllerManager] POP context: %s → %s (stack depth: %d)" % [
			InputContext.keys()[old_context],
			InputContext.keys()[current_context],
			context_stack.size()
		])

	context_changed.emit(old_context, current_context)

func set_context(ctx: InputContext, data: Dictionary = {}) -> void:
	"""Replace current context without using stack (for major transitions)"""
	var old_context = current_context
	current_context = ctx
	context_data = data.duplicate(true)

	if debug_mode:
		print("[ControllerManager] SET context: %s → %s" % [
			InputContext.keys()[old_context],
			InputContext.keys()[ctx]
		])

	context_changed.emit(old_context, current_context)

func clear_stack() -> void:
	"""Clear the entire context stack (for major state changes like scene transitions)"""
	context_stack.clear()
	if debug_mode:
		print("[ControllerManager] Context stack cleared")

func get_current_context() -> InputContext:
	"""Get the current active context"""
	return current_context

func get_context_data() -> Dictionary:
	"""Get the data associated with current context"""
	return context_data.duplicate(true)

func set_context_data(key: String, value: Variant) -> void:
	"""Set a data value for the current context"""
	context_data[key] = value

## ═══════════════════════════════════════════════════════════════
## INPUT PROCESSING
## ═══════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# Debug: Log ALL input events, not just joypad buttons
	if event is InputEventJoypadButton:
		print("[ControllerManager._input] RAW Joypad event: button=%d, pressed=%s, context=%s, is_handled=%s" % [
			event.button_index,
			event.pressed,
			InputContext.keys()[current_context],
			get_viewport().is_input_handled()
		])

		if event.pressed:
			var burst_check = event.is_action("battle_burst")
			var run_check = event.is_action("battle_run")
			print("[ControllerManager._input] Button %d pressed, context=%s, is_burst=%s, is_run=%s" % [
				event.button_index,
				InputContext.keys()[current_context],
				burst_check,
				run_check
			])

			# Also check if the actions exist in InputMap
			if not InputMap.has_action("battle_burst"):
				print("[ControllerManager] WARNING: battle_burst action not found in InputMap!")
			if not InputMap.has_action("battle_run"):
				print("[ControllerManager] WARNING: battle_run action not found in InputMap!")

	# Check cooldown
	if input_cooldown > 0:
		print("[ControllerManager._input] BLOCKED by cooldown (remaining: %.2f)" % input_cooldown) if event is InputEventJoypadButton and event.pressed else null
		return

	# Block if disabled
	if current_context == InputContext.DISABLED:
		return

	# Route input based on current context
	_route_input(event)

func _route_input(event: InputEvent) -> void:
	"""Route input to appropriate handler based on current context"""
	match current_context:
		InputContext.OVERWORLD:
			_handle_overworld_input(event)
		InputContext.BATTLE_ACTION:
			_handle_battle_action_input(event)
		InputContext.BATTLE_SKILL:
			_handle_battle_submenu_input(event, "skill")
		InputContext.BATTLE_ITEM:
			_handle_battle_submenu_input(event, "item")
		InputContext.BATTLE_CAPTURE:
			_handle_battle_submenu_input(event, "capture")
		InputContext.BATTLE_BURST:
			_handle_battle_submenu_input(event, "burst")
		InputContext.BATTLE_STATUS:
			_handle_battle_status_input(event)
		InputContext.BATTLE_TARGET:
			_handle_battle_target_input(event)
		InputContext.MENU_MAIN:
			_handle_menu_main_input(event)
		InputContext.MENU_ITEMS:
			_handle_menu_items_input(event)
		InputContext.MENU_PARTY:
			_handle_menu_party_input(event)
		InputContext.MENU_SIGILS:
			_handle_menu_sigils_input(event)
		InputContext.DIALOG:
			_handle_dialog_input(event)

## ═══════════════════════════════════════════════════════════════
## CONTEXT-SPECIFIC INPUT HANDLERS
## ═══════════════════════════════════════════════════════════════

func _handle_overworld_input(event: InputEvent) -> void:
	"""Handle input in overworld (walking around)"""
	# Movement is handled by player controller directly
	# We only intercept action buttons here

	# NOTE: In OVERWORLD context, we emit signals but DON'T mark input as handled
	# This allows existing handlers (like Main.gd's _unhandled_input) to still work
	# Once all systems are migrated to ControllerManager, we can mark as handled

	if event.is_action_pressed("action"):
		action_button_pressed.emit("action", current_context)
		_start_cooldown()
		# DON'T mark as handled - let existing handlers work
	elif event.is_action_pressed("jump"):
		action_button_pressed.emit("jump", current_context)
		_start_cooldown()
		# DON'T mark as handled - let existing handlers work
	elif event.is_action_pressed("run"):
		action_button_pressed.emit("run", current_context)
		_start_cooldown()
		# DON'T mark as handled - let existing handlers work
	elif event.is_action_pressed("menu"):
		action_button_pressed.emit("menu", current_context)
		_start_cooldown()
		# DON'T mark as handled - let existing handlers work (Main.gd opens game menu)

func _handle_battle_action_input(event: InputEvent) -> void:
	"""Handle input in battle action menu"""
	# Navigation (UP/DOWN)
	if event.is_action_pressed("move_up"):
		navigate_pressed.emit(Vector2.UP, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		navigate_pressed.emit(Vector2.DOWN, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	# Actions
	elif event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_battle_submenu_input(event: InputEvent, menu_type: String) -> void:
	"""Handle input in battle submenus (skill/item/capture/burst)"""
	# Navigation (UP/DOWN/LEFT/RIGHT for grid)
	if event.is_action_pressed("move_up"):
		navigate_pressed.emit(Vector2.UP, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		navigate_pressed.emit(Vector2.DOWN, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		navigate_pressed.emit(Vector2.LEFT, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		navigate_pressed.emit(Vector2.RIGHT, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	# Actions
	elif event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_battle_status_input(event: InputEvent) -> void:
	"""Handle input in battle status screen"""
	if event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_battle_target_input(event: InputEvent) -> void:
	"""Handle input during target selection"""
	# Navigation (LEFT/RIGHT to switch targets)
	if event.is_action_pressed("move_left"):
		navigate_pressed.emit(Vector2.LEFT, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		navigate_pressed.emit(Vector2.RIGHT, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	# Actions
	elif event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_menu_main_input(event: InputEvent) -> void:
	"""Handle input in main pause menu"""
	# Navigation
	if event.is_action_pressed("move_up"):
		navigate_pressed.emit(Vector2.UP, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		navigate_pressed.emit(Vector2.DOWN, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	# Actions
	elif event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_menu_items_input(event: InputEvent) -> void:
	"""Handle input in items panel"""
	# Navigation (UP/DOWN for items, LEFT/RIGHT for columns)
	if event.is_action_pressed("move_up"):
		navigate_pressed.emit(Vector2.UP, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		navigate_pressed.emit(Vector2.DOWN, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		navigate_pressed.emit(Vector2.LEFT, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		navigate_pressed.emit(Vector2.RIGHT, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	# L/R Bumpers for categories
	elif event.is_action_pressed("battle_burst"):  # L bumper
		print("[ControllerManager] L bumper pressed in MENU_ITEMS context, emitting bumper_pressed(-1)")
		bumper_pressed.emit(-1, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("battle_run"):  # R bumper
		print("[ControllerManager] R bumper pressed in MENU_ITEMS context, emitting bumper_pressed(+1)")
		bumper_pressed.emit(1, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	# Actions
	elif event.is_action_pressed("menu_accept"):  # A - select/use
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):  # B - back
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("run"):  # X - inspect
		action_button_pressed.emit("inspect", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump"):  # Y - discard
		action_button_pressed.emit("discard", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_menu_party_input(event: InputEvent) -> void:
	"""Handle input in party panel"""
	# Similar to items but with different actions
	if event.is_action_pressed("move_up"):
		navigate_pressed.emit(Vector2.UP, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		navigate_pressed.emit(Vector2.DOWN, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_menu_sigils_input(event: InputEvent) -> void:
	"""Handle input in sigils panel"""
	if event.is_action_pressed("move_up"):
		navigate_pressed.emit(Vector2.UP, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		navigate_pressed.emit(Vector2.DOWN, current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

func _handle_dialog_input(event: InputEvent) -> void:
	"""Handle input in popup dialogs"""
	# Dialogs typically just need accept/back
	# Navigation is handled by Godot's focus system
	if event.is_action_pressed("menu_accept"):
		action_button_pressed.emit("accept", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		action_button_pressed.emit("back", current_context)
		_start_cooldown()
		get_viewport().set_input_as_handled()

## ═══════════════════════════════════════════════════════════════
## UTILITY FUNCTIONS
## ═══════════════════════════════════════════════════════════════

func _start_cooldown() -> void:
	"""Start the input cooldown timer"""
	input_cooldown = INPUT_COOLDOWN_DURATION

func is_on_cooldown() -> bool:
	"""Check if input is currently on cooldown"""
	return input_cooldown > 0

func disable_input() -> void:
	"""Disable all controller input"""
	push_context(InputContext.DISABLED)

func enable_input(fallback_context: InputContext = InputContext.OVERWORLD) -> void:
	"""Re-enable controller input"""
	if current_context == InputContext.DISABLED:
		if context_stack.is_empty():
			set_context(fallback_context)
		else:
			pop_context()

func set_debug_mode(enabled: bool) -> void:
	"""Enable/disable debug logging"""
	debug_mode = enabled
