## ═══════════════════════════════════════════════════════════════════════════
## DormsPanel - Dormitory Room Assignment UI (Redesigned)
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Main menu panel for managing dormitory room assignments with a roster-based
##   interface. Three-panel layout: Roster | Details | Rooms+Common
##
## RESPONSIBILITIES:
##   • Dorm roster display with all members
##   • View type selection (Placements/Reassignments)
##   • Member details display (name, room, neighbors, status)
##   • 8-room visual grid display (301-308) with occupants
##   • Common room management with action buttons
##   • Room assignment flow with validation and confirmations
##   • Reassignment planning for Saturday moves
##
## LAYOUT:
##   Left Panel (Dorm Roster):
##   • View Type selector (Placements/Reassignments)
##   • List of all dorm members (up/down navigation)
##
##   Center Panel (Details):
##   • Name, Room, Neighbors, Status for selected member
##
##   Right Panel (split):
##   • Top: Rooms grid (2x4) showing room numbers and occupants
##   • Bottom: Common Room list + 4 action buttons
##
## SELECTION FLOW:
##   1. Initially can only navigate up/down in roster or change view
##   2. Selecting roster member → enables common room actions
##   3. First-time members: only "Assign Room" active
##   4. Previously assigned: "Assign Room" inactive until moved to common room
##   5. Can move multiple members to common room
##   6. When assigning from common room, select a room:
##      - Yellow = room with person moving out (available)
##      - Green = vacant room
##      - Red = their current room (can't go back)
##   7. Accept Plan becomes active when all common room members assigned
##   8. Confirmation → everyone returns to previous room
##   9. Reassignments view shows pending Saturday moves
##
## ═══════════════════════════════════════════════════════════════════════════

extends PanelBase
class_name DormsPanel

# ═══════════════════════════════════════════════════════════════════════════
# NODE REFERENCES
# ═══════════════════════════════════════════════════════════════════════════

@onready var _refresh_btn: Button = $Root/Header/RefreshBtn

# Left Panel - Roster
@onready var _view_type_filter: OptionButton = %ViewTypeFilter
@onready var _roster_list: VBoxContainer = %RosterList

# Center Panel - Details
@onready var _detail_content: RichTextLabel = %DetailContent

# Right Panel - Rooms + Common
@onready var _rooms_grid: GridContainer = %RoomsGrid
@onready var _common_list: VBoxContainer = %CommonList

# Action Buttons
@onready var _assign_room_btn: Button = %AssignRoomBtn
@onready var _move_out_btn: Button = %MoveOutBtn
@onready var _cancel_move_btn: Button = %CancelMoveBtn
@onready var _accept_plan_btn: Button = %AcceptPlanBtn

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

enum ViewType { PLACEMENTS, REASSIGNMENTS }
var _current_view: ViewType = ViewType.PLACEMENTS

var _selected_member: String = ""  # actor_id from roster
var _selected_room: String = ""    # room_id from rooms grid

var _all_members: PackedStringArray = []  # All dorm members
var _common_members: PackedStringArray = []  # Members in common room
var _pending_reassignments: Dictionary = {}  # actor_id -> room_id

# Navigation
enum NavState { VIEW_SELECT, ROSTER_SELECT, ROOM_SELECT, COMMON_SELECT, ACTION_SELECT, POPUP_ACTIVE }
var _nav_state: NavState = NavState.ROSTER_SELECT
var _nav_state_history: Array[NavState] = []  # Track navigation history for back button
var _roster_buttons: Array[Button] = []
var _room_buttons: Array[Button] = []
var _common_buttons: Array[Button] = []
var _action_buttons: Array[Button] = []
var _current_roster_index: int = 0
var _current_room_index: int = 0
var _current_common_index: int = 0
var _current_action_index: int = 0

# Room visual states
const VIS_EMPTY := 0
const VIS_OCCUPIED := 1
const VIS_STAGED := 2
const VIS_LOCKED := 3

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super()  # Call PanelBase._ready()

	print("[DormsPanel._ready] Starting initialization")

	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Verify node references
	print("[DormsPanel._ready] Node checks:")
	print("  _view_type_filter: ", _view_type_filter != null)
	print("  _roster_list: ", _roster_list != null)
	print("  _detail_content: ", _detail_content != null)
	print("  _rooms_grid: ", _rooms_grid != null)
	print("  _common_list: ", _common_list != null)
	print("  _assign_room_btn: ", _assign_room_btn != null)
	print("  _move_out_btn: ", _move_out_btn != null)
	print("  _cancel_move_btn: ", _cancel_move_btn != null)
	print("  _accept_plan_btn: ", _accept_plan_btn != null)

	# Setup view type filter
	if _view_type_filter and _view_type_filter.item_count == 0:
		_view_type_filter.add_item("Placements", 0)
		_view_type_filter.add_item("Reassignments", 1)
		_view_type_filter.select(0)
		if not _view_type_filter.item_selected.is_connected(_on_view_type_changed):
			_view_type_filter.item_selected.connect(_on_view_type_changed)
			print("[DormsPanel._ready] Connected view_type_filter.item_selected")

	# Connect refresh button
	if _refresh_btn and not _refresh_btn.pressed.is_connected(_rebuild):
		_refresh_btn.pressed.connect(_rebuild)
		print("[DormsPanel._ready] Connected refresh button")

	# Connect action buttons
	if _assign_room_btn and not _assign_room_btn.pressed.is_connected(_on_assign_room_pressed):
		_assign_room_btn.pressed.connect(_on_assign_room_pressed)
		print("[DormsPanel._ready] Connected assign_room button")
	if _move_out_btn and not _move_out_btn.pressed.is_connected(_on_move_out_pressed):
		_move_out_btn.pressed.connect(_on_move_out_pressed)
		print("[DormsPanel._ready] Connected move_out button")
	if _cancel_move_btn and not _cancel_move_btn.pressed.is_connected(_on_cancel_move_pressed):
		_cancel_move_btn.pressed.connect(_on_cancel_move_pressed)
		print("[DormsPanel._ready] Connected cancel_move button")
	if _accept_plan_btn and not _accept_plan_btn.pressed.is_connected(_on_accept_plan_pressed):
		_accept_plan_btn.pressed.connect(_on_accept_plan_pressed)
		print("[DormsPanel._ready] Connected accept_plan button")

	# Connect to DormSystem signals
	var ds: Node = _ds()
	print("[DormsPanel._ready] DormSystem found: ", ds != null)
	if ds:
		print("[DormsPanel._ready] DormSystem signals available:")
		print("  dorms_changed: ", ds.has_signal("dorms_changed"))
		print("  plan_changed: ", ds.has_signal("plan_changed"))

		if ds.has_signal("dorms_changed") and not ds.is_connected("dorms_changed", Callable(self, "_on_dorms_changed")):
			ds.connect("dorms_changed", Callable(self, "_on_dorms_changed"))
			print("[DormsPanel._ready] Connected dorms_changed signal")
		if ds.has_signal("plan_changed") and not ds.is_connected("plan_changed", Callable(self, "_on_dorms_changed")):
			ds.connect("plan_changed", Callable(self, "_on_dorms_changed"))
			print("[DormsPanel._ready] Connected plan_changed signal")

	print("[DormsPanel._ready] Calling _rebuild()")
	_rebuild()
	print("[DormsPanel._ready] Initialization complete")

func _ds() -> Node:
	return get_node_or_null("/root/aDormSystem")

# ═══════════════════════════════════════════════════════════════════════════
# PANELBASE OVERRIDES
# ═══════════════════════════════════════════════════════════════════════════

func _on_panel_gained_focus() -> void:
	super()
	print("[DormsPanel] Panel gained focus")
	_nav_state = NavState.VIEW_SELECT
	_nav_state_history.clear()
	print("[DormsPanel] Nav state set to VIEW_SELECT, history cleared")
	_focus_view_type()

func _can_panel_close() -> bool:
	# Prevent closing if common room has members without assignments
	if _current_view == ViewType.REASSIGNMENTS:
		if _has_unassigned_common_members():
			_show_toast("Please assign all members in the common room before leaving.")
			return false
	return true

# ═══════════════════════════════════════════════════════════════════════════
# INPUT HANDLING
# ═══════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not is_active():
		return

	if _nav_state == NavState.POPUP_ACTIVE:
		return

	# Handle directional navigation
	if event.is_action_pressed("move_up"):
		print("[DormsPanel._input] UP pressed, current state: ", _get_nav_state_name(_nav_state))
		_navigate_up()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		print("[DormsPanel._input] DOWN pressed, current state: ", _get_nav_state_name(_nav_state))
		_navigate_down()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		print("[DormsPanel._input] LEFT pressed, current state: ", _get_nav_state_name(_nav_state))
		_navigate_left()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		print("[DormsPanel._input] RIGHT pressed, current state: ", _get_nav_state_name(_nav_state))
		_navigate_right()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		print("[DormsPanel._input] ACCEPT pressed, current state: ", _get_nav_state_name(_nav_state))
		_on_accept_input()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		print("[DormsPanel._input] BACK pressed, current state: ", _get_nav_state_name(_nav_state), ", history size: ", _nav_state_history.size())
		_on_back_input()
		# Note: _on_back_input() only handles input if history exists
		# If no history, it lets the event bubble up to GameMenu for proper panel transition

func _get_nav_state_name(state: NavState) -> String:
	match state:
		NavState.VIEW_SELECT: return "VIEW_SELECT"
		NavState.ROSTER_SELECT: return "ROSTER_SELECT"
		NavState.ROOM_SELECT: return "ROOM_SELECT"
		NavState.COMMON_SELECT: return "COMMON_SELECT"
		NavState.ACTION_SELECT: return "ACTION_SELECT"
		NavState.POPUP_ACTIVE: return "POPUP_ACTIVE"
		_: return "UNKNOWN"

func _navigate_up() -> void:
	match _nav_state:
		NavState.VIEW_SELECT:
			# Move to roster
			_push_nav_state(NavState.ROSTER_SELECT)
			_current_roster_index = 0
			_focus_current_roster()
		NavState.ROSTER_SELECT:
			if _current_roster_index > 0:
				_current_roster_index -= 1
				_focus_current_roster()
			else:
				# Move to view type
				_push_nav_state(NavState.VIEW_SELECT)
				_focus_view_type()
		NavState.ROOM_SELECT:
			# 2x4 grid: move up one row (subtract 4)
			var new_index: int = _current_room_index - 4
			if new_index >= 0:
				_current_room_index = new_index
				_focus_current_room()
		NavState.COMMON_SELECT:
			if _current_common_index > 0:
				_current_common_index -= 1
				_focus_current_common()
		NavState.ACTION_SELECT:
			if _current_action_index > 0:
				_current_action_index -= 1
				_focus_current_action()

func _navigate_down() -> void:
	match _nav_state:
		NavState.VIEW_SELECT:
			# Move to roster
			_push_nav_state(NavState.ROSTER_SELECT)
			_current_roster_index = 0
			_focus_current_roster()
		NavState.ROSTER_SELECT:
			if _current_roster_index < _roster_buttons.size() - 1:
				_current_roster_index += 1
				_focus_current_roster()
		NavState.ROOM_SELECT:
			# 2x4 grid: move down one row (add 4)
			var new_index: int = _current_room_index + 4
			if new_index < _room_buttons.size():
				_current_room_index = new_index
				_focus_current_room()
		NavState.COMMON_SELECT:
			if _current_common_index < _common_buttons.size() - 1:
				_current_common_index += 1
				_focus_current_common()
		NavState.ACTION_SELECT:
			if _current_action_index < _action_buttons.size() - 1:
				_current_action_index += 1
				_focus_current_action()

func _navigate_left() -> void:
	match _nav_state:
		NavState.ROOM_SELECT:
			# 2x4 grid: move left
			if _current_room_index % 4 > 0:
				_current_room_index -= 1
				_focus_current_room()

func _navigate_right() -> void:
	# Disabled - navigation is locked within current state unless back pressed
	pass

func _on_accept_input() -> void:
	match _nav_state:
		NavState.VIEW_SELECT:
			# Toggle view type
			if _view_type_filter:
				var current: int = _view_type_filter.get_selected_id()
				var next: int = 1 if current == 0 else 0
				_view_type_filter.select(next)
				_on_view_type_changed(next)
		NavState.ROSTER_SELECT:
			if _current_roster_index >= 0 and _current_roster_index < _roster_buttons.size():
				_roster_buttons[_current_roster_index].emit_signal("pressed")
		NavState.ROOM_SELECT:
			if _current_room_index >= 0 and _current_room_index < _room_buttons.size():
				_room_buttons[_current_room_index].emit_signal("pressed")
		NavState.COMMON_SELECT:
			if _current_common_index >= 0 and _current_common_index < _common_buttons.size():
				_common_buttons[_current_common_index].emit_signal("pressed")
		NavState.ACTION_SELECT:
			if _current_action_index >= 0 and _current_action_index < _action_buttons.size():
				_action_buttons[_current_action_index].emit_signal("pressed")

func _on_back_input() -> void:
	# Go back to previous navigation state
	if _nav_state_history.size() > 0:
		var prev_state: NavState = _nav_state_history.pop_back()
		print("[DormsPanel._on_back_input] Going back from %s to %s" % [_get_nav_state_name(_nav_state), _get_nav_state_name(prev_state)])
		_nav_state = prev_state

		# Clear selection when going back to roster
		if _nav_state == NavState.ROSTER_SELECT:
			print("[DormsPanel._on_back_input] Clearing member selection")
			_selected_member = ""
			_update_details()
			_update_action_buttons()
			_update_room_colors()

		match _nav_state:
			NavState.VIEW_SELECT:
				_focus_view_type()
			NavState.ROSTER_SELECT:
				_focus_current_roster()
			NavState.ROOM_SELECT:
				_focus_current_room()
			NavState.COMMON_SELECT:
				_focus_current_common()
			NavState.ACTION_SELECT:
				_focus_current_action()
		get_viewport().set_input_as_handled()
	else:
		# No history - don't handle input, let GameMenu handle the back button
		# This allows proper slide animation back to StatusPanel
		print("[DormsPanel._on_back_input] No history, letting GameMenu handle back button for slide transition")
		# Do NOT call get_viewport().set_input_as_handled() - let event bubble up

func _focus_view_type() -> void:
	if _view_type_filter:
		_view_type_filter.grab_focus()

func _focus_current_roster() -> void:
	if _current_roster_index >= 0 and _current_roster_index < _roster_buttons.size():
		_roster_buttons[_current_roster_index].grab_focus()

func _focus_current_room() -> void:
	if _current_room_index >= 0 and _current_room_index < _room_buttons.size():
		_room_buttons[_current_room_index].grab_focus()

func _focus_current_common() -> void:
	if _current_common_index >= 0 and _current_common_index < _common_buttons.size():
		_common_buttons[_current_common_index].grab_focus()

func _focus_current_action() -> void:
	if _current_action_index >= 0 and _current_action_index < _action_buttons.size():
		_action_buttons[_current_action_index].grab_focus()

func _push_nav_state(new_state: NavState) -> void:
	"""Push current state to history and switch to new state"""
	print("[DormsPanel._push_nav_state] Pushing %s to history, switching to %s" % [_get_nav_state_name(_nav_state), _get_nav_state_name(new_state)])
	_nav_state_history.append(_nav_state)
	_nav_state = new_state
	print("[DormsPanel._push_nav_state] History size now: ", _nav_state_history.size())

# ═══════════════════════════════════════════════════════════════════════════
# UI BUILDING
# ═══════════════════════════════════════════════════════════════════════════

func _rebuild() -> void:
	print("[DormsPanel._rebuild] Starting rebuild, current view: ", "PLACEMENTS" if _current_view == ViewType.PLACEMENTS else "REASSIGNMENTS")
	var ds: Node = _ds()
	if not ds:
		print("[DormsPanel._rebuild] ERROR: DormSystem not found!")
		return

	_build_roster_list()
	_build_rooms_grid()
	_build_common_list()
	_build_action_button_array()
	_update_details()
	_update_action_buttons()
	print("[DormsPanel._rebuild] Rebuild complete")

func _build_roster_list() -> void:
	print("[DormsPanel._build_roster_list] Building roster list")
	# Clear existing roster
	for c in _roster_list.get_children():
		c.queue_free()
	_roster_buttons.clear()

	var ds: Node = _ds()
	if not ds:
		print("[DormsPanel._build_roster_list] ERROR: DormSystem not found!")
		return

	# Get all dorm members (everyone who has or could have a room)
	_all_members = _get_all_dorm_members(ds)
	print("[DormsPanel._build_roster_list] Found %d members" % _all_members.size())

	if _all_members.size() == 0:
		var empty := Label.new()
		empty.text = "— no members —"
		_roster_list.add_child(empty)
		return

	# Create button for each member
	for i in range(_all_members.size()):
		var aid: String = _all_members[i]
		var btn := Button.new()
		btn.text = String(ds.call("display_name", aid))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.button_pressed = (_selected_member == aid)
		btn.pressed.connect(func(id := aid) -> void:
			_on_roster_member_selected(id)
		)
		_roster_list.add_child(btn)
		_roster_buttons.append(btn)

	print("[DormsPanel._build_roster_list] Created %d roster buttons" % _roster_buttons.size())

func _build_rooms_grid() -> void:
	# Clear existing rooms
	for c in _rooms_grid.get_children():
		c.queue_free()
	_room_buttons.clear()

	var ds: Node = _ds()
	if not ds:
		return

	# Get room list
	var room_ids_v: Variant = ds.call("list_rooms")
	var room_ids: PackedStringArray = (room_ids_v if typeof(room_ids_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())

	# Create button for each room (2x4 grid)
	for i in range(room_ids.size()):
		var rid: String = room_ids[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 80)
		btn.toggle_mode = false
		btn.focus_mode = Control.FOCUS_ALL

		# Build button content (room number + occupant name)
		var room_data: Dictionary = ds.call("get_room", rid)
		var occupant: String = String(room_data.get("occupant", ""))
		var occupant_name: String = ""
		if occupant != "":
			occupant_name = String(ds.call("display_name", occupant))

		# Format: Room number on top, name below
		if occupant_name != "":
			btn.text = "%s\n%s" % [rid, occupant_name]
		else:
			btn.text = "%s\n(empty)" % rid

		# Make text smaller
		btn.add_theme_font_size_override("font_size", 11)

		# Apply visual styling based on state
		_apply_room_visual(btn, rid)

		btn.pressed.connect(func(room_id := rid) -> void:
			_on_room_selected(room_id)
		)

		_rooms_grid.add_child(btn)
		_room_buttons.append(btn)

func _build_action_button_array() -> void:
	"""Build array of action buttons for navigation"""
	_action_buttons.clear()
	if _assign_room_btn:
		_action_buttons.append(_assign_room_btn)
	if _move_out_btn:
		_action_buttons.append(_move_out_btn)
	if _cancel_move_btn:
		_action_buttons.append(_cancel_move_btn)
	if _accept_plan_btn:
		_action_buttons.append(_accept_plan_btn)

func _build_common_list() -> void:
	# Clear existing common room members
	for c in _common_list.get_children():
		c.queue_free()
	_common_buttons.clear()

	var ds: Node = _ds()
	if not ds:
		return

	# Get common room members
	var common_v: Variant = ds.call("get_common")
	_common_members = (common_v if typeof(common_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())

	if _common_members.size() == 0:
		var empty := Label.new()
		empty.text = "— empty —"
		_common_list.add_child(empty)
		return

	# Create label for each common room member
	for i in range(_common_members.size()):
		var aid: String = _common_members[i]
		var btn := Button.new()
		btn.text = String(ds.call("display_name", aid))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.button_pressed = (_selected_member == aid)
		btn.pressed.connect(func(id := aid) -> void:
			_on_common_member_selected(id)
		)
		_common_list.add_child(btn)
		_common_buttons.append(btn)

func _update_details() -> void:
	if not _detail_content:
		return

	if _selected_member == "":
		_detail_content.text = "[i]Select a member from the roster.[/i]"
		return

	var ds: Node = _ds()
	if not ds:
		_detail_content.text = "[i]Dorm system unavailable.[/i]"
		return

	var lines := PackedStringArray()

	# Name
	var name: String = String(ds.call("display_name", _selected_member))
	lines.append("[b]Name:[/b] %s" % name)
	lines.append("")

	# Room
	var room_id: String = _get_member_room(_selected_member)
	if room_id != "":
		lines.append("[b]Room:[/b] %s" % room_id)
	else:
		lines.append("[b]Room:[/b] Common Room")
	lines.append("")

	# Neighbors (if in a room)
	if room_id != "":
		lines.append("[b]Neighbors:[/b]")
		var neighbors_v: Variant = ds.call("room_neighbors", room_id)
		var neighbors: PackedStringArray = (neighbors_v if typeof(neighbors_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
		for n in neighbors:
			var n_room: Dictionary = ds.call("get_room", n)
			var n_occupant: String = String(n_room.get("occupant", ""))
			if n_occupant == "":
				lines.append("  • %s - Empty" % n)
			else:
				var n_name: String = String(ds.call("display_name", n_occupant))
				var status: String = _get_relationship_status(ds, _selected_member, n_occupant)
				lines.append("  • %s - %s with %s" % [n, status, n_name])
		lines.append("")

	# Status
	lines.append("[b]Status:[/b]")
	var status_lines: PackedStringArray = _get_member_status(_selected_member)
	for s in status_lines:
		lines.append("  • %s" % s)

	# Show pending reassignment in Reassignments view
	if _current_view == ViewType.REASSIGNMENTS:
		var pending_room: String = _get_pending_assignment(_selected_member)
		if pending_room != "":
			lines.append("")
			lines.append("[b][color=yellow]Pending Saturday Move:[/color][/b]")
			lines.append("  • Will move to room %s" % pending_room)

	_detail_content.text = _join_psa(lines, "\n")

func _update_action_buttons() -> void:
	if not _assign_room_btn or not _move_out_btn or not _cancel_move_btn or not _accept_plan_btn:
		return

	var ds: Node = _ds()
	if not ds:
		_assign_room_btn.disabled = true
		_move_out_btn.disabled = true
		_cancel_move_btn.disabled = true
		_accept_plan_btn.disabled = true
		return

	# Assign Room: active if member selected and either:
	# 1. First time (in common room)
	# 2. Already in common room (after Move Out)
	var in_common: bool = _common_members.has(_selected_member)
	_assign_room_btn.disabled = not (_selected_member != "" and in_common)

	# Move Out: active if member selected and has a room (not in common)
	# Move Out always works - it switches to Reassignments view and stages the move
	var has_room: bool = _get_member_room(_selected_member) != ""
	_move_out_btn.disabled = not (_selected_member != "" and has_room)

	# Cancel Move: active if in reassignments view and has pending changes
	_cancel_move_btn.disabled = not (_current_view == ViewType.REASSIGNMENTS and _has_pending_changes())

	# Accept Plan: active if all common room members have been assigned to rooms
	_accept_plan_btn.disabled = not (_current_view == ViewType.REASSIGNMENTS and _can_accept_plan())

# ═══════════════════════════════════════════════════════════════════════════
# SELECTION HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_roster_member_selected(aid: String) -> void:
	print("[DormsPanel._on_roster_member_selected] Selected member: ", aid)
	_selected_member = aid
	_update_details()
	_update_action_buttons()
	_update_room_colors()

	# Move cursor to action buttons
	print("[DormsPanel._on_roster_member_selected] Moving to ACTION_SELECT state")
	_push_nav_state(NavState.ACTION_SELECT)
	_current_action_index = 0
	_focus_current_action()

func _on_room_selected(room_id: String) -> void:
	_selected_room = room_id

	# If we have a member selected from common room, try to assign them
	if _selected_member != "" and _common_members.has(_selected_member):
		_try_assign_to_room(room_id)

func _on_common_member_selected(aid: String) -> void:
	_selected_member = aid
	_update_details()
	_update_action_buttons()
	_update_room_colors()

# ═══════════════════════════════════════════════════════════════════════════
# ACTION BUTTON HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_assign_room_pressed() -> void:
	if _selected_member == "":
		_show_toast("Please select a member from the roster first.")
		return

	if not _common_members.has(_selected_member):
		_show_toast("Member must be in the common room to assign a room.")
		return

	# Switch to room selection mode
	_nav_state = NavState.ROOM_SELECT
	_current_room_index = 0
	_focus_current_room()
	_show_toast("Select a room to assign %s." % _get_member_name(_selected_member))

func _on_move_out_pressed() -> void:
	print("[DormsPanel._on_move_out_pressed] Move Out button pressed")

	if _selected_member == "":
		_show_toast("Please select a member from the roster first.")
		return

	var room_id: String = _get_member_room(_selected_member)
	print("[DormsPanel._on_move_out_pressed] Selected member: %s, room: %s" % [_selected_member, room_id])

	if room_id == "":
		_show_toast("Member is already in the common room.")
		return

	var ds: Node = _ds()
	if not ds:
		print("[DormsPanel._on_move_out_pressed] ERROR: DormSystem not found")
		return

	# Check if reassignment can start today (Sunday only)
	if ds.has_method("can_start_reassignment_today") and not bool(ds.call("can_start_reassignment_today")):
		print("[DormsPanel._on_move_out_pressed] Not Sunday - cannot start reassignment")
		_show_toast("Room reassignment can only be started on Sunday.")
		return

	var member_name: String = _get_member_name(_selected_member)

	# Switch to Reassignments view if not already there
	if _current_view != ViewType.REASSIGNMENTS:
		print("[DormsPanel._on_move_out_pressed] Switching to Reassignments view")
		_current_view = ViewType.REASSIGNMENTS
		if _view_type_filter:
			_view_type_filter.select(1)  # Select Reassignments
		_rebuild()  # Rebuild to update view

	# Confirm staging the move
	print("[DormsPanel._on_move_out_pressed] Showing confirmation dialog")
	var confirmed: bool = await _ask_confirm("Move %s out of room %s?\n(Change will take effect on Saturday)" % [member_name, room_id])
	print("[DormsPanel._on_move_out_pressed] Confirmed: %s" % confirmed)

	if not confirmed:
		return

	# Stage the move for Saturday
	print("[DormsPanel._on_move_out_pressed] Calling stage_vacate_room for room: %s" % room_id)
	if ds.has_method("stage_vacate_room"):
		var res: Dictionary = ds.call("stage_vacate_room", room_id)
		print("[DormsPanel._on_move_out_pressed] Result: %s" % res)

		if not bool(res.get("ok", false)):
			var reason: String = String(res.get("reason", "Cannot stage move."))
			print("[DormsPanel._on_move_out_pressed] ERROR: %s" % reason)
			_show_toast(reason)
			return
	else:
		print("[DormsPanel._on_move_out_pressed] ERROR: stage_vacate_room method not found")
		_show_toast("DormSystem doesn't support staging moves.")
		return

	print("[DormsPanel._on_move_out_pressed] Success - rebuilding panel")
	_show_toast("%s staged for common room on Saturday." % member_name)
	_rebuild()

	# Keep cursor on roster for selecting more members to move out
	_push_nav_state(NavState.ROSTER_SELECT)
	_current_roster_index = 0
	_focus_current_roster()

func _on_cancel_move_pressed() -> void:
	var confirmed: bool = await _ask_confirm("Cancel all pending reassignments?")
	if not confirmed:
		return

	var ds: Node = _ds()
	if ds and ds.has_method("stage_reset_plan"):
		ds.call("stage_reset_plan")

	_pending_reassignments.clear()
	_show_toast("All pending moves cancelled.")
	_rebuild()

func _on_accept_plan_pressed() -> void:
	if not _can_accept_plan():
		_show_toast("Please assign all members in the common room before accepting the plan.")
		return

	var confirmed: bool = await _ask_confirm("Accept these room reassignments? Changes will take effect on Saturday.")
	if not confirmed:
		return

	var ds: Node = _ds()
	if not ds:
		return

	# Lock the plan for Saturday
	var res: Dictionary = {}
	if ds.has_method("accept_plan_for_saturday"):
		res = ds.call("accept_plan_for_saturday")
	elif ds.has_method("lock_plan_for_saturday"):
		res = ds.call("lock_plan_for_saturday")

	if typeof(res) == TYPE_DICTIONARY and not bool(res.get("ok", false)):
		_show_toast(String(res.get("reason", "Cannot accept plan.")))
		return

	_show_toast("Plan accepted! Changes will apply on Saturday morning.")
	_pending_reassignments.clear()

	# Switch to reassignments view to show pending moves
	_current_view = ViewType.REASSIGNMENTS
	if _view_type_filter:
		_view_type_filter.select(1)
	_rebuild()

# ═══════════════════════════════════════════════════════════════════════════
# ROOM ASSIGNMENT
# ═══════════════════════════════════════════════════════════════════════════

func _try_assign_to_room(room_id: String) -> void:
	var ds: Node = _ds()
	if not ds:
		return

	# Validate room selection
	var room_data: Dictionary = ds.call("get_room", room_id)
	var occupant: String = String(room_data.get("occupant", ""))

	# Check if room is available
	var vis: int = int(ds.call("get_room_visual", room_id))

	# Only allow green (empty) or yellow (staged) rooms
	if vis == VIS_OCCUPIED:
		_show_toast("This room is currently occupied.")
		return
	elif vis == VIS_LOCKED:
		_show_toast("This room is locked.")
		return

	# Check if this is their current room
	var current_room: String = _get_member_room(_selected_member)
	if current_room == room_id:
		_show_toast("That's their current room. Please select a different room.")
		return

	# Check if room is already targeted in plan
	if _is_room_targeted(room_id):
		_show_toast("This room is already targeted by another reassignment.")
		return

	# Confirm assignment
	var member_name: String = _get_member_name(_selected_member)
	var confirmed: bool = await _ask_confirm("Assign %s to room %s?" % [member_name, room_id])
	if not confirmed:
		return

	# Perform assignment
	if _current_view == ViewType.REASSIGNMENTS:
		# Stage the assignment for Saturday
		if ds.has_method("stage_assign"):
			var res: Dictionary = ds.call("stage_assign", _selected_member, room_id)
			if not bool(res.get("ok", false)):
				_show_toast(String(res.get("reason", "Cannot assign room.")))
				return
		_pending_reassignments[_selected_member] = room_id
		_show_toast("Assignment staged for Saturday.")
	else:
		# Immediate assignment
		if ds.has_method("assign_now_from_common"):
			var res: Dictionary = ds.call("assign_now_from_common", _selected_member, room_id)
			if not bool(res.get("ok", false)):
				_show_toast(String(res.get("reason", "Cannot assign room.")))
				return
		_show_toast("%s assigned to room %s." % [member_name, room_id])

	# Clear selection and return to roster
	_selected_member = ""
	_selected_room = ""
	_nav_state = NavState.ROSTER_SELECT
	_rebuild()

# ═══════════════════════════════════════════════════════════════════════════
# VISUAL HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _apply_room_visual(btn: Button, room_id: String) -> void:
	var ds: Node = _ds()
	if not ds:
		return

	var state: int = int(ds.call("get_room_visual", room_id))

	var col := Color(0.15, 0.17, 0.20)  # default
	if state == VIS_EMPTY:
		col = Color(0.12, 0.30, 0.12)  # green (empty)
	elif state == VIS_OCCUPIED:
		col = Color(0.12, 0.18, 0.32)  # blue (occupied)
	elif state == VIS_STAGED:
		col = Color(0.40, 0.34, 0.08)  # yellow (staged/available)
	elif state == VIS_LOCKED:
		col = Color(0.38, 0.10, 0.10)  # red (locked)

	# Override with red if this is the selected member's current room
	if _selected_member != "" and _get_member_room(_selected_member) == room_id:
		col = Color(0.75, 0.15, 0.15)  # red (can't go back to current room)

	# Override with red if room is already targeted in pending reassignments
	if _is_room_targeted(room_id):
		col = Color(0.75, 0.15, 0.15)  # red (already targeted)

	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.set_border_width_all(1)
	sb.border_color = col.darkened(0.35)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

func _update_room_colors() -> void:
	var ds: Node = _ds()
	if not ds:
		return

	var room_ids_v: Variant = ds.call("list_rooms")
	var room_ids: PackedStringArray = (room_ids_v if typeof(room_ids_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())

	for i in range(min(room_ids.size(), _room_buttons.size())):
		_apply_room_visual(_room_buttons[i], room_ids[i])

# ═══════════════════════════════════════════════════════════════════════════
# HELPER METHODS
# ═══════════════════════════════════════════════════════════════════════════

func _get_all_dorm_members(ds: Node) -> PackedStringArray:
	var members := PackedStringArray()

	# Get members from rooms
	var room_ids_v: Variant = ds.call("list_rooms")
	var room_ids: PackedStringArray = (room_ids_v if typeof(room_ids_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
	for rid in room_ids:
		var room_data: Dictionary = ds.call("get_room", rid)
		var occupant: String = String(room_data.get("occupant", ""))
		if occupant != "" and not members.has(occupant):
			members.append(occupant)

	# Get members from common room
	var common_v: Variant = ds.call("get_common")
	var common: PackedStringArray = (common_v if typeof(common_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
	for aid in common:
		if not members.has(aid):
			members.append(aid)

	return members

func _get_member_room(aid: String) -> String:
	var ds: Node = _ds()
	if not ds:
		return ""

	var room_ids_v: Variant = ds.call("list_rooms")
	var room_ids: PackedStringArray = (room_ids_v if typeof(room_ids_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
	for rid in room_ids:
		var room_data: Dictionary = ds.call("get_room", rid)
		if String(room_data.get("occupant", "")) == aid:
			return rid
	return ""

func _get_member_name(aid: String) -> String:
	var ds: Node = _ds()
	if not ds:
		return aid
	return String(ds.call("display_name", aid))

func _get_relationship_status(ds: Node, aid1: String, aid2: String) -> String:
	if ds.has_method("is_pair_hidden") and bool(ds.call("is_pair_hidden", aid1, aid2)):
		return "Unknown connection"
	if ds.has_method("get_pair_status"):
		return String(ds.call("get_pair_status", aid1, aid2))
	return "Neutral"

func _get_member_status(aid: String) -> PackedStringArray:
	var status := PackedStringArray()
	var ds: Node = _ds()
	if not ds:
		return status

	# Check if recently moved (tired)
	if ds.has_method("has_move_penalty") and bool(ds.call("has_move_penalty", aid)):
		status.append("Tired from recent move (-2 affinity with you)")

	# Check feelings about current setup
	var room_id: String = _get_member_room(aid)
	if room_id != "":
		status.append("Settled in room %s" % room_id)

		# Get neighbor quality hints
		var neighbors_v: Variant = ds.call("room_neighbors", room_id)
		var neighbors: PackedStringArray = (neighbors_v if typeof(neighbors_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
		var bestie_count: int = 0
		var rival_count: int = 0
		for n in neighbors:
			var n_room: Dictionary = ds.call("get_room", n)
			var n_occupant: String = String(n_room.get("occupant", ""))
			if n_occupant != "":
				var rel_status: String = _get_relationship_status(ds, aid, n_occupant)
				if rel_status == "Bestie":
					bestie_count += 1
				elif rel_status == "Rival":
					rival_count += 1

		if bestie_count > 0:
			status.append("Happy with %d bestie neighbor%s!" % [bestie_count, "s" if bestie_count > 1 else ""])
		if rival_count > 0:
			status.append("Unhappy with %d rival neighbor%s" % [rival_count, "s" if rival_count > 1 else ""])
	else:
		status.append("In common room, awaiting assignment")

	if status.size() == 0:
		status.append("Doing okay")

	return status

func _get_pending_assignment(aid: String) -> String:
	"""Get the pending room assignment for a member, if any"""
	var ds: Node = _ds()
	if not ds:
		return ""

	# Check DormSystem's locked plan (Saturday moves)
	if ds.has_method("get_saturday_plan"):
		var plan_v: Variant = ds.call("get_saturday_plan")
		if typeof(plan_v) == TYPE_DICTIONARY:
			var plan: Dictionary = plan_v
			if plan.has(aid):
				return String(plan[aid])

	# Check staged assignments (not yet accepted)
	if ds.has_method("get_staged_assignments"):
		var staged_v: Variant = ds.call("get_staged_assignments")
		if typeof(staged_v) == TYPE_DICTIONARY:
			var staged: Dictionary = staged_v
			if staged.has(aid):
				return String(staged[aid])

	return ""

func _is_room_targeted(room_id: String) -> bool:
	# Check if any member is already targeting this room in pending reassignments
	if _pending_reassignments.has(room_id):
		return true

	var ds: Node = _ds()
	if not ds:
		return false

	# Check DormSystem's staged assignments
	if ds.has_method("get_staged_assignments"):
		var assignments_v: Variant = ds.call("get_staged_assignments")
		if typeof(assignments_v) == TYPE_DICTIONARY:
			var assignments: Dictionary = assignments_v
			for aid in assignments.keys():
				if String(assignments[aid]) == room_id:
					return true

	return false

func _has_unassigned_common_members() -> bool:
	return _common_members.size() > 0

func _has_pending_changes() -> bool:
	return _pending_reassignments.size() > 0 or _common_members.size() > 0

func _can_accept_plan() -> bool:
	# Can accept if all common room members have been assigned
	if _common_members.size() > 0:
		return false

	# Must have at least one pending reassignment
	if _pending_reassignments.size() == 0:
		return false

	return true

func _on_view_type_changed(index: int) -> void:
	print("[DormsPanel._on_view_type_changed] View changed to index: ", index)
	_current_view = ViewType.PLACEMENTS if index == 0 else ViewType.REASSIGNMENTS
	print("[DormsPanel._on_view_type_changed] Current view now: ", "PLACEMENTS" if _current_view == ViewType.PLACEMENTS else "REASSIGNMENTS")
	_rebuild()

func _on_dorms_changed() -> void:
	print("[DormsPanel._on_dorms_changed] DormSystem signal received, rebuilding...")
	_rebuild()

# ═══════════════════════════════════════════════════════════════════════════
# POPUP HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _ask_confirm(msg: String) -> bool:
	var prev_state: NavState = _nav_state
	_nav_state = NavState.POPUP_ACTIVE

	var popup := Panel.new()
	popup.custom_minimum_size = Vector2(400, 200)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Confirm"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Message
	var msg_label := Label.new()
	msg_label.text = msg
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(msg_label)

	# Buttons
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.focus_mode = Control.FOCUS_ALL
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.focus_mode = Control.FOCUS_ALL
	hbox.add_child(accept_btn)
	hbox.add_child(cancel_btn)
	vbox.add_child(hbox)

	add_child(popup)
	popup.position = (get_viewport_rect().size - popup.custom_minimum_size) / 2
	popup.show()
	accept_btn.grab_focus()

	var result: bool = false
	accept_btn.pressed.connect(func() -> void:
		result = true
		popup.hide()
	)
	cancel_btn.pressed.connect(func() -> void:
		result = false
		popup.hide()
	)

	await popup.hidden
	popup.queue_free()

	# Restore previous navigation state
	_nav_state = prev_state
	match _nav_state:
		NavState.VIEW_SELECT:
			_focus_view_type()
		NavState.ROSTER_SELECT:
			_focus_current_roster()
		NavState.ROOM_SELECT:
			_focus_current_room()
		NavState.COMMON_SELECT:
			_focus_current_common()
		NavState.ACTION_SELECT:
			_focus_current_action()

	return result

func _show_toast(msg: String) -> void:
	var prev_state: NavState = _nav_state
	_nav_state = NavState.POPUP_ACTIVE

	var popup := Panel.new()
	popup.custom_minimum_size = Vector2(400, 150)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Notice"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Message
	var msg_label := Label.new()
	msg_label.text = msg
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(msg_label)

	# OK Button
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.focus_mode = Control.FOCUS_ALL
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(ok_btn)

	add_child(popup)
	popup.position = (get_viewport_rect().size - popup.custom_minimum_size) / 2
	popup.show()
	ok_btn.grab_focus()

	ok_btn.pressed.connect(func() -> void:
		popup.hide()
	)

	await popup.hidden
	popup.queue_free()

	# Restore previous navigation state
	_nav_state = prev_state
	match _nav_state:
		NavState.VIEW_SELECT:
			_focus_view_type()
		NavState.ROSTER_SELECT:
			_focus_current_roster()
		NavState.ROOM_SELECT:
			_focus_current_room()
		NavState.COMMON_SELECT:
			_focus_current_common()
		NavState.ACTION_SELECT:
			_focus_current_action()

func _join_psa(arr: PackedStringArray, sep: String) -> String:
	var out: String = ""
	for i in range(arr.size()):
		if i > 0:
			out += sep
		out += arr[i]
	return out
