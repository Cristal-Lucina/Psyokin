## ═══════════════════════════════════════════════════════════════════════════
## OutreachPanel - Three-Panel Mission/Node/Mutual Aid Browser
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Browse and manage missions, nodes, and mutual aid tasks with controller
##   navigation. Three-panel layout: Categories | Mission List | Details
##
## RESPONSIBILITIES:
##   • Category selection (Missions/Nodes/Mutual Aid)
##   • Mission list display with current marker
##   • Detail panel with title, description, rewards, status
##   • Action buttons (Set Current, Advance)
##   • Signal-based reactivity to aMainEventSystem
##
## NAVIGATION FLOW:
##   CATEGORY_SELECT → (Right/Accept) → MISSION_LIST → (Accept) → Action
##   MISSION_LIST → (Left/Back) → CATEGORY_SELECT
##
## CONNECTED SYSTEMS:
##   • aMainEventSystem - Mission data and current mission tracking
##
## ═══════════════════════════════════════════════════════════════════════════

extends PanelBase
class_name OutreachPanel

## ═══════════════════════════════════════════════════════════════════════════
## CONSTANTS
## ═══════════════════════════════════════════════════════════════════════════

const MAIN_EVENT_PATH := "/root/aMainEventSystem"

const CATEGORIES: Array[Dictionary] = [
	{"id": "missions", "label": "Missions"},
	{"id": "nodes", "label": "Nodes"},
	{"id": "mutual_aid", "label": "Mutual Aid"}
]

## ═══════════════════════════════════════════════════════════════════════════
## NODE REFERENCES
## ═══════════════════════════════════════════════════════════════════════════

@onready var _category_list: ItemList = %CategoryList
@onready var _mission_list: ItemList = %MissionList
@onready var _mission_label: Label = %MissionLabel

@onready var _title_label: Label = %TitleLabel
@onready var _desc_label: Label = %DescriptionLabel
@onready var _reward_label: Label = %RewardLabel
@onready var _status_label: Label = %StatusLabel

@onready var _primary_btn: Button = %PrimaryBtn
@onready var _back_btn: Button = %BackBtn
@onready var _advance_btn: Button = %AdvanceBtn

## ═══════════════════════════════════════════════════════════════════════════
## STATE MACHINE
## ═══════════════════════════════════════════════════════════════════════════

enum NavState { CATEGORY_SELECT, MISSION_LIST, POPUP_ACTIVE }
var _nav_state: NavState = NavState.CATEGORY_SELECT
var _active_popup: Control = null

## ═══════════════════════════════════════════════════════════════════════════
## DATA TRACKING
## ═══════════════════════════════════════════════════════════════════════════

var _mission_data: Array[Dictionary] = []  # Current category's missions
var _selected_mission: Dictionary = {}     # Currently selected mission

## System references
var _main_event: Node = null

## ═══════════════════════════════════════════════════════════════════════════
## INITIALIZATION
## ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super()  # Call PanelBase._ready()

	# Get system references
	_main_event = get_node_or_null(MAIN_EVENT_PATH)

	# Wire signals
	_wire_signals()

	# Initialize UI
	_refresh_category_list()

	# Load initial data
	call_deferred("_first_fill")

func _wire_signals() -> void:
	"""Connect to all relevant signals"""
	# Category list
	if _category_list and not _category_list.item_selected.is_connected(_on_category_selected):
		_category_list.item_selected.connect(_on_category_selected)

	# Mission list
	if _mission_list and not _mission_list.item_selected.is_connected(_on_mission_selected):
		_mission_list.item_selected.connect(_on_mission_selected)

	# Action buttons
	if _primary_btn and not _primary_btn.pressed.is_connected(_on_primary_action):
		_primary_btn.pressed.connect(_on_primary_action)

	if _back_btn and not _back_btn.pressed.is_connected(_on_back_from_details):
		_back_btn.pressed.connect(_on_back_from_details)

	if _advance_btn and not _advance_btn.pressed.is_connected(_on_advance_event):
		_advance_btn.pressed.connect(_on_advance_event)

	# aMainEventSystem signals
	if _main_event:
		if _main_event.has_signal("event_changed"):
			if not _main_event.is_connected("event_changed", _on_event_changed):
				_main_event.connect("event_changed", _on_event_changed)

		if _main_event.has_signal("current_changed"):
			if not _main_event.is_connected("current_changed", _on_current_changed):
				_main_event.connect("current_changed", _on_current_changed)

func _first_fill() -> void:
	"""Initial data load"""
	if _category_list.get_item_count() > 0:
		_category_list.select(0)
		_on_category_selected(0)

	_enter_category_select_state()

## ═══════════════════════════════════════════════════════════════════════════
## PANELBASE CALLBACKS
## ═══════════════════════════════════════════════════════════════════════════

func _on_panel_gained_focus() -> void:
	super()  # Call parent
	print("[OutreachPanel] Panel gained focus - state: %s" % NavState.keys()[_nav_state])

	# Restore focus based on current navigation state
	match _nav_state:
		NavState.CATEGORY_SELECT:
			call_deferred("_enter_category_select_state")
		NavState.MISSION_LIST:
			call_deferred("_enter_mission_list_state")
		NavState.POPUP_ACTIVE:
			# Popup handles its own focus
			pass

func _on_panel_lost_focus() -> void:
	super()  # Call parent
	print("[OutreachPanel] Panel lost focus - state: %s" % NavState.keys()[_nav_state])

## ═══════════════════════════════════════════════════════════════════════════
## CATEGORY MANAGEMENT
## ═══════════════════════════════════════════════════════════════════════════

func _refresh_category_list() -> void:
	"""Populate category list"""
	_category_list.clear()

	for cat in CATEGORIES:
		_category_list.add_item(cat["label"])

func _get_current_category() -> String:
	"""Get currently selected category ID"""
	var selected = _category_list.get_selected_items()
	if selected.is_empty():
		return "missions"

	var idx = selected[0]
	if idx >= 0 and idx < CATEGORIES.size():
		return CATEGORIES[idx]["id"]

	return "missions"

func _on_category_selected(index: int) -> void:
	"""Category changed - refresh mission list"""
	print("[OutreachPanel] Category selected: %d" % index)

	if index < 0 or index >= CATEGORIES.size():
		return

	var category = CATEGORIES[index]["id"]
	var label = CATEGORIES[index]["label"]

	# Update mission panel label
	_mission_label.text = label.to_upper()

	# Refresh mission list for this category
	_refresh_mission_list(category)

## ═══════════════════════════════════════════════════════════════════════════
## MISSION MANAGEMENT
## ═══════════════════════════════════════════════════════════════════════════

func _refresh_mission_list(category: String) -> void:
	"""Load missions for the given category"""
	print("[OutreachPanel] Refreshing mission list for category: %s" % category)

	_mission_list.clear()
	_mission_data.clear()

	match category:
		"missions":
			_mission_data = _read_missions_from_system()
		"nodes":
			_mission_data = _generate_placeholder_data("VR Node", 5)
		"mutual_aid":
			_mission_data = _generate_placeholder_data("Mutual Aid Task", 6)

	# Populate mission list
	for mission in _mission_data:
		var title = mission.get("title", "")
		var is_current = mission.get("current", false)
		var display = title + ("  •" if is_current else "")

		_mission_list.add_item(display)

		# Color current mission light blue
		if is_current:
			var idx = _mission_list.item_count - 1
			_mission_list.set_item_custom_fg_color(idx, Color(0.4, 0.7, 1.0))

	# Select first mission if available
	if _mission_data.size() > 0:
		_mission_list.select(0)
		_on_mission_selected(0)
	else:
		_show_empty_details()

func _read_missions_from_system() -> Array[Dictionary]:
	"""Read missions from aMainEventSystem"""
	var out: Array[Dictionary] = []

	if _main_event == null:
		return out

	# Get mission IDs
	var ids: PackedStringArray = PackedStringArray()
	if _main_event.has_method("list_ids"):
		var v_ids: Variant = _main_event.call("list_ids")
		if typeof(v_ids) == TYPE_PACKED_STRING_ARRAY:
			ids = v_ids
		elif typeof(v_ids) == TYPE_ARRAY:
			for it in (v_ids as Array):
				ids.append(String(it))
	ids.sort()

	# Get current mission ID
	var current_id: String = ""
	if _main_event.has_method("get_current_id"):
		current_id = String(_main_event.call("get_current_id"))

	# Build mission data
	for id in ids:
		var title := id
		var hint := ""
		var reward := ""
		var status := "Available"

		if _main_event.has_method("get_event"):
			var rec_v: Variant = _main_event.call("get_event", id)
			if typeof(rec_v) == TYPE_DICTIONARY:
				var d: Dictionary = rec_v
				title = String(d.get("title", title))
				hint = String(d.get("hint", hint))
				reward = String(d.get("reward", reward))

				# Check if completed
				if d.has("completed") and bool(d.get("completed")):
					status = "Completed"
				elif id == current_id:
					status = "Current"

		out.append({
			"id": id,
			"title": title,
			"hint": hint,
			"reward": reward,
			"status": status,
			"current": (id == current_id)
		})

	return out

func _generate_placeholder_data(base_name: String, count: int) -> Array[Dictionary]:
	"""Generate placeholder missions for Nodes/Mutual Aid"""
	var out: Array[Dictionary] = []

	for i in range(count):
		out.append({
			"id": "%s_%d" % [base_name.to_lower().replace(" ", "_"), i + 1],
			"title": "%s %d" % [base_name, i + 1],
			"hint": "Details TBD.",
			"reward": "",
			"status": "Available",
			"current": false
		})

	return out

func _on_mission_selected(index: int) -> void:
	"""Mission selection changed - update details"""
	print("[OutreachPanel] Mission selected: %d" % index)

	if index < 0 or index >= _mission_data.size():
		_show_empty_details()
		return

	_selected_mission = _mission_data[index]
	_show_mission_details(_selected_mission)

## ═══════════════════════════════════════════════════════════════════════════
## DETAIL PANEL
## ═══════════════════════════════════════════════════════════════════════════

func _show_mission_details(mission: Dictionary) -> void:
	"""Update detail panel with mission info"""
	var title = mission.get("title", "")
	var hint = mission.get("hint", "")
	var reward = mission.get("reward", "")
	var status = mission.get("status", "Available")

	# Title
	_title_label.text = title

	# Description
	if hint != "":
		_desc_label.text = hint
		_desc_label.visible = true
	else:
		_desc_label.text = "[No description available]"
		_desc_label.visible = true

	# Reward
	if reward != "":
		_reward_label.text = "Reward: " + reward
		_reward_label.visible = true
	else:
		_reward_label.visible = false

	# Status
	_status_label.text = "Status: " + status

	# Update action buttons
	_update_action_buttons(mission)

func _show_empty_details() -> void:
	"""Show empty state in detail panel"""
	_title_label.text = "No missions available"
	_desc_label.text = ""
	_desc_label.visible = false
	_reward_label.visible = false
	_status_label.text = ""
	_primary_btn.visible = false
	_back_btn.visible = true
	_selected_mission = {}

func _update_action_buttons(mission: Dictionary) -> void:
	"""Update action button labels and visibility"""
	var is_current = mission.get("current", false)

	if is_current:
		# Current mission - show Advance button
		_primary_btn.text = "Advance"
		_primary_btn.tooltip_text = "Advance this mission"
	else:
		# Available mission - show Set Current button
		_primary_btn.text = "Set Current"
		_primary_btn.tooltip_text = "Set as current mission"

	_primary_btn.visible = true
	_back_btn.visible = true

## ═══════════════════════════════════════════════════════════════════════════
## ACTIONS
## ═══════════════════════════════════════════════════════════════════════════

func _on_primary_action() -> void:
	"""Primary button pressed - Set Current or Advance"""
	print("[OutreachPanel] _on_primary_action called")

	if _selected_mission.is_empty():
		print("[OutreachPanel] ERROR: No mission selected!")
		return

	var is_current = _selected_mission.get("current", false)
	var mission_title = _selected_mission.get("title", "")

	print("[OutreachPanel] Mission: %s, is_current: %s" % [mission_title, is_current])

	if is_current:
		# Advance current mission
		print("[OutreachPanel] Advancing current mission...")
		_advance_current_mission()
	else:
		# Set as current - show confirmation
		print("[OutreachPanel] Showing set current confirmation...")
		_show_set_current_confirmation()

func _show_set_current_confirmation() -> void:
	"""Show confirmation popup for setting current mission using ConfirmationPopup"""
	var title = _selected_mission.get("title", "")
	print("[OutreachPanel] Showing set current confirmation for: %s" % title)

	# Create and show ConfirmationPopup
	var popup := ConfirmationPopup.create("Set '%s' as your current mission?" % title)
	add_child(popup)

	# Wait for user response
	var result: bool = await popup.confirmed

	# Clean up
	popup.queue_free()

	# Handle response
	if result:
		print("[OutreachPanel] User confirmed setting current mission")
		_confirm_set_current()
	else:
		print("[OutreachPanel] User canceled setting current mission")

func _confirm_set_current() -> void:
	"""User confirmed setting mission as current"""
	var mission_id = _selected_mission.get("id", "")
	print("[OutreachPanel] _confirm_set_current called - mission_id: %s" % mission_id)

	if mission_id == "":
		print("[OutreachPanel] ERROR: Empty mission ID!")
		return

	if not _main_event:
		print("[OutreachPanel] ERROR: aMainEventSystem not found!")
		return

	if not _main_event.has_method("set_current"):
		print("[OutreachPanel] ERROR: aMainEventSystem has no set_current method!")
		print("[OutreachPanel] Available methods: %s" % _main_event.get_method_list())
		return

	print("[OutreachPanel] Calling set_current(%s)..." % mission_id)
	_main_event.call("set_current", mission_id)
	print("[OutreachPanel] ✓ Set current mission: %s" % mission_id)

func _advance_current_mission() -> void:
	"""Advance the current mission"""
	if _main_event and _main_event.has_method("advance"):
		_main_event.call("advance")
		print("[OutreachPanel] Advanced current mission")

func _on_advance_event() -> void:
	"""Debug button - advance current mission"""
	_advance_current_mission()

func _on_back_from_details() -> void:
	"""Back button in details - return focus to mission list"""
	_enter_mission_list_state()

## ═══════════════════════════════════════════════════════════════════════════
## SIGNAL HANDLERS
## ═══════════════════════════════════════════════════════════════════════════

func _on_event_changed(_event_id: String = "") -> void:
	"""aMainEventSystem event changed - refresh current category"""
	print("[OutreachPanel] Event changed, refreshing...")
	var category = _get_current_category()
	_refresh_mission_list(category)

func _on_current_changed(_event_id: String = "") -> void:
	"""Current mission changed - refresh display"""
	print("[OutreachPanel] Current mission changed, refreshing...")
	var category = _get_current_category()
	_refresh_mission_list(category)

## ═══════════════════════════════════════════════════════════════════════════
## POPUP MANAGEMENT
## ═══════════════════════════════════════════════════════════════════════════

func _popup_cancel() -> void:
	"""Cancel popup without action"""
	_popup_close_and_return_to_list()

func _popup_close_and_return_to_list() -> void:
	"""Close popup and return to MISSION_LIST state"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	print("[OutreachPanel] Closing popup, returning to mission list")

	var popup_to_close = _active_popup
	_active_popup = null

	# CRITICAL: Set state BEFORE popping
	_nav_state = NavState.MISSION_LIST

	# Pop from panel manager
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr and panel_mgr.is_panel_active(popup_to_close):
		panel_mgr.pop_panel()

	popup_to_close.queue_free()

## ═══════════════════════════════════════════════════════════════════════════
## STATE TRANSITIONS
## ═══════════════════════════════════════════════════════════════════════════

func _enter_category_select_state() -> void:
	"""Enter CATEGORY_SELECT state and grab focus"""
	_nav_state = NavState.CATEGORY_SELECT
	if _category_list and _category_list.get_item_count() > 0:
		_category_list.grab_focus()
		if _category_list.get_selected_items().is_empty():
			_category_list.select(0)
	print("[OutreachPanel] Entered CATEGORY_SELECT state")

func _enter_mission_list_state() -> void:
	"""Enter MISSION_LIST state and grab focus"""
	_nav_state = NavState.MISSION_LIST
	if _mission_list and _mission_list.get_item_count() > 0:
		_mission_list.grab_focus()
		if _mission_list.get_selected_items().is_empty():
			_mission_list.select(0)
	print("[OutreachPanel] Entered MISSION_LIST state")

## ═══════════════════════════════════════════════════════════════════════════
## INPUT HANDLING - STATE MACHINE
## ═══════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	"""Main input handler - routes to state-specific handlers"""

	# STATE 1: POPUP_ACTIVE
	if _nav_state == NavState.POPUP_ACTIVE:
		_handle_popup_input(event)
		return

	# Only handle other states if we're the active panel
	if not is_active():
		return

	# STATE 2: CATEGORY_SELECT
	if _nav_state == NavState.CATEGORY_SELECT:
		_handle_category_select_input(event)
		return

	# STATE 3: MISSION_LIST
	if _nav_state == NavState.MISSION_LIST:
		_handle_mission_list_input(event)
		return

func _handle_category_select_input(event: InputEvent) -> void:
	"""Handle input when in category select mode"""
	if event.is_action_pressed("move_up"):
		_navigate_category(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_category(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("menu_accept"):
		_enter_mission_list_state()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_exit_outreach_panel()
		get_viewport().set_input_as_handled()

func _handle_mission_list_input(event: InputEvent) -> void:
	"""Handle input when in mission list mode"""
	if event.is_action_pressed("move_up"):
		_navigate_mission(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_mission(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("menu_back"):
		_enter_category_select_state()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		# Pressing accept on mission triggers the primary action directly
		print("[OutreachPanel] ACCEPT pressed on mission - triggering primary action")
		_on_primary_action()
		get_viewport().set_input_as_handled()

func _handle_popup_input(event: InputEvent) -> void:
	"""Handle input when popup is active"""
	if event.is_action_pressed("menu_accept"):
		print("[OutreachPanel] ACCEPT pressed in popup")
		# Find focused button and press it
		var focused = get_viewport().gui_get_focus_owner()
		print("[OutreachPanel] Focused control: %s" % (focused.name if focused else "null"))
		if focused and focused is Button:
			print("[OutreachPanel] Emitting pressed signal on button: %s" % focused.text)
			focused.emit_signal("pressed")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		print("[OutreachPanel] BACK pressed in popup")
		_popup_cancel()
		get_viewport().set_input_as_handled()
	# NOTE: Do NOT consume move_left/move_right/move_up/move_down
	# Let Godot's focus system handle button navigation via focus neighbors

## ═══════════════════════════════════════════════════════════════════════════
## NAVIGATION HELPERS
## ═══════════════════════════════════════════════════════════════════════════

func _navigate_category(delta: int) -> void:
	"""Navigate up/down in category list"""
	if not _category_list or _category_list.get_item_count() == 0:
		return

	var current = _category_list.get_selected_items()
	var idx = current[0] if current.size() > 0 else 0
	idx = clamp(idx + delta, 0, _category_list.get_item_count() - 1)

	_category_list.select(idx)
	_category_list.ensure_current_is_visible()
	_on_category_selected(idx)

func _navigate_mission(delta: int) -> void:
	"""Navigate up/down in mission list"""
	if not _mission_list or _mission_list.get_item_count() == 0:
		return

	var current = _mission_list.get_selected_items()
	var idx = current[0] if current.size() > 0 else 0
	idx = clamp(idx + delta, 0, _mission_list.get_item_count() - 1)

	_mission_list.select(idx)
	_mission_list.ensure_current_is_visible()
	_on_mission_selected(idx)

func _exit_outreach_panel() -> void:
	"""Exit OutreachPanel back to previous panel"""
	print("[OutreachPanel] Exiting to previous panel")
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.pop_panel()
