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
##   • Dorm Roster list (all members in rooms)
##   • Common Room list (members awaiting assignment)
##
##   Center Panel (Action Menu):
##   • Assign Room, Move Out, Cancel Move, Accept Plan buttons
##
##   Right Panel (split):
##   • Top: Rooms grid (2x4) showing room numbers and occupants
##   • Bottom: Details section (Name, Room, Neighbors, Status for selected/hovered member)
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

# Background panel (opaque)
var _background_panel: PanelContainer = null

# Panel containers (for animation)
@onready var _left_panel: PanelContainer = %LeftPanel
@onready var _center_panel: PanelContainer = %CenterPanel
@onready var _right_panel: PanelContainer = %RightPanel

# Left Panel - Roster
@onready var _roster_list: ItemList = %RosterList

# Selection arrow and dark box for roster
var _roster_selection_arrow: Label = null
var _roster_dark_box: PanelContainer = null

# Selection arrow for action menu
var _action_selection_arrow: Label = null
var _action_arrow_pulse_tween: Tween = null

# Selection arrow for room grid
var _room_selection_arrow: Label = null
var _room_arrow_pulse_tween: Tween = null

# Right Panel - Details (bottom section)
@onready var _detail_content: RichTextLabel = %DetailContent

# Right Panel - Rooms + Common
@onready var _rooms_grid: GridContainer = %RoomsGrid
@onready var _common_list: VBoxContainer = %CommonList

# Action Buttons
@onready var _assign_room_btn: Button = %AssignRoomBtn
@onready var _move_out_btn: Button = %MoveOutBtn
@onready var _cancel_move_btn: Button = %CancelMoveBtn

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

enum ViewType { PLACEMENTS, REASSIGNMENTS }
var _current_view: ViewType = ViewType.REASSIGNMENTS  # Always use reassignments mode

var _selected_member: String = ""  # actor_id from roster
var _selected_room: String = ""    # room_id from rooms grid

var _all_members: PackedStringArray = []  # All dorm members
var _common_members: PackedStringArray = []  # Members in common room
var _pending_reassignments: Dictionary = {}  # actor_id -> room_id

# Navigation
enum NavState { ROSTER_SELECT, COMMON_SELECT, ROOM_SELECT, ACTION_SELECT }
var _nav_state: NavState = NavState.ACTION_SELECT
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

# Panel animation settings
const BASE_LEFT_RATIO := 2.5
const BASE_CENTER_RATIO := 2.5
const BASE_RIGHT_RATIO := 5.0
const ACTIVE_SCALE := 1.10  # Active panel grows by 10%
const INACTIVE_SCALE := 0.95  # Inactive panels shrink by 5%
const ANIM_DURATION := 0.2  # Animation duration in seconds

# Button pulse animation
var _button_pulse_tween: Tween = null
var _button_pulse_target: Button = null

# Panel animation tracking
var _panel_animating: bool = false

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	super()  # Call PanelBase._ready()

	# Set process mode to work while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Disable process by default (enabled during panel animations)
	set_process(false)

	print("[DormsPanel._ready] Starting initialization")

	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Create opaque background panel behind all content
	_create_background_panel()

	# Verify node references
	print("[DormsPanel._ready] Node checks:")
	print("  _roster_list: ", _roster_list != null)
	print("  _detail_content: ", _detail_content != null)
	print("  _rooms_grid: ", _rooms_grid != null)
	print("  _common_list: ", _common_list != null)
	print("  _assign_room_btn: ", _assign_room_btn != null)
	print("  _move_out_btn: ", _move_out_btn != null)
	print("  _cancel_move_btn: ", _cancel_move_btn != null)

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

	# Connect resize signals to update arrow positions
	if not resized.is_connected(_on_panel_resized):
		resized.connect(_on_panel_resized)
		print("[DormsPanel._ready] Connected panel resized signal")
	if _roster_list and not _roster_list.resized.is_connected(_on_roster_list_resized):
		_roster_list.resized.connect(_on_roster_list_resized)
		print("[DormsPanel._ready] Connected roster list resized signal")

	_apply_core_vibe_styling()
	print("[DormsPanel._ready] Calling _rebuild()")
	_rebuild()
	print("[DormsPanel._ready] Initialization complete")

func _create_background_panel() -> void:
	"""Create an opaque background panel behind all content"""
	_background_panel = PanelContainer.new()
	_background_panel.name = "BackgroundPanel"
	_background_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input

	# Insert as first child so it's behind everything
	add_child(_background_panel)
	move_child(_background_panel, 0)

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to DormsPanel elements"""

	# Style opaque background panel (blocks transparency)
	if _background_panel:
		var bg_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Night Navy border (subtle)
			aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Night Navy background
			1.0,                                       # FULLY OPAQUE (not semi-transparent)
			0,                                         # No rounded corners (full screen)
			0,                                         # No border
			0                                          # No glow
		)
		_background_panel.add_theme_stylebox_override("panel", bg_style)

	# Style the three main panel containers with rounded neon borders
	if _left_panel:
		var left_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (roster)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		left_style.content_margin_left = 10
		left_style.content_margin_top = 10
		left_style.content_margin_right = 10
		left_style.content_margin_bottom = 10
		_left_panel.add_theme_stylebox_override("panel", left_style)

	if _center_panel:
		var center_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_GRAPE_VIOLET,        # Grape Violet border (rooms)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		center_style.content_margin_left = 10
		center_style.content_margin_top = 10
		center_style.content_margin_right = 10
		center_style.content_margin_bottom = 10
		_center_panel.add_theme_stylebox_override("panel", center_style)

	if _right_panel:
		var right_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (details)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		right_style.content_margin_left = 10
		right_style.content_margin_top = 10
		right_style.content_margin_right = 10
		right_style.content_margin_bottom = 10
		_right_panel.add_theme_stylebox_override("panel", right_style)

	# Style detail content
	if _detail_content:
		_detail_content.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_detail_content.add_theme_font_size_override("normal_font_size", 14)

	# Style roster list like BondsPanel/OutreachPanel
	if _roster_list:
		_roster_list.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_roster_list.add_theme_color_override("font_selected_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_roster_list.add_theme_color_override("font_hovered_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_roster_list.add_theme_font_size_override("font_size", 18)
		_roster_list.z_index = 200  # Above arrow and box
		# Remove all borders and backgrounds
		var empty_stylebox = StyleBoxEmpty.new()
		_roster_list.add_theme_stylebox_override("panel", empty_stylebox)
		_roster_list.add_theme_stylebox_override("focus", empty_stylebox)
		_roster_list.add_theme_stylebox_override("selected", empty_stylebox)
		_roster_list.add_theme_stylebox_override("selected_focus", empty_stylebox)
		_roster_list.add_theme_stylebox_override("cursor", empty_stylebox)
		_roster_list.add_theme_stylebox_override("cursor_unfocused", empty_stylebox)

	# Style action buttons with focus states and pulse
	if _assign_room_btn:
		# Normal state: Outlined Electric Lime
		var assign_style_normal = StyleBoxFlat.new()
		assign_style_normal.bg_color = Color(0, 0, 0, 0)
		assign_style_normal.border_color = aCoreVibeTheme.COLOR_ELECTRIC_LIME
		assign_style_normal.border_width_left = 2
		assign_style_normal.border_width_right = 2
		assign_style_normal.border_width_top = 2
		assign_style_normal.border_width_bottom = 2
		assign_style_normal.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_normal.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_normal.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_normal.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_normal.content_margin_left = 12
		assign_style_normal.content_margin_right = 12
		assign_style_normal.content_margin_top = 8
		assign_style_normal.content_margin_bottom = 8

		# Focus state: Filled Electric Lime
		var assign_style_focus = StyleBoxFlat.new()
		assign_style_focus.bg_color = aCoreVibeTheme.COLOR_ELECTRIC_LIME
		assign_style_focus.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_focus.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_focus.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_focus.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_focus.content_margin_left = 12
		assign_style_focus.content_margin_right = 12
		assign_style_focus.content_margin_top = 8
		assign_style_focus.content_margin_bottom = 8

		# Disabled state: Grey with dark background (same for focused and unfocused)
		var assign_style_disabled = StyleBoxFlat.new()
		assign_style_disabled.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
		assign_style_disabled.border_color = Color(0.5, 0.5, 0.5, 1.0)
		assign_style_disabled.border_width_left = 2
		assign_style_disabled.border_width_right = 2
		assign_style_disabled.border_width_top = 2
		assign_style_disabled.border_width_bottom = 2
		assign_style_disabled.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_disabled.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_disabled.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_disabled.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		assign_style_disabled.content_margin_left = 12
		assign_style_disabled.content_margin_right = 12
		assign_style_disabled.content_margin_top = 8
		assign_style_disabled.content_margin_bottom = 8

		_assign_room_btn.add_theme_stylebox_override("normal", assign_style_normal)
		_assign_room_btn.add_theme_stylebox_override("hover", assign_style_normal.duplicate())
		_assign_room_btn.add_theme_stylebox_override("pressed", assign_style_normal.duplicate())
		_assign_room_btn.add_theme_stylebox_override("focus", assign_style_focus)
		_assign_room_btn.add_theme_stylebox_override("disabled", assign_style_disabled)
		_assign_room_btn.add_theme_stylebox_override("disabled_focused", assign_style_disabled.duplicate())

		_assign_room_btn.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
		_assign_room_btn.add_theme_color_override("font_hover_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
		_assign_room_btn.add_theme_color_override("font_pressed_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
		_assign_room_btn.add_theme_color_override("font_focus_color", aCoreVibeTheme.COLOR_NIGHT_NAVY)
		_assign_room_btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 1.0))
		_assign_room_btn.custom_minimum_size = Vector2(140, 40)

	if _move_out_btn:
		# Normal state: Outlined Citrus Yellow
		var move_style_normal = StyleBoxFlat.new()
		move_style_normal.bg_color = Color(0, 0, 0, 0)
		move_style_normal.border_color = aCoreVibeTheme.COLOR_CITRUS_YELLOW
		move_style_normal.border_width_left = 2
		move_style_normal.border_width_right = 2
		move_style_normal.border_width_top = 2
		move_style_normal.border_width_bottom = 2
		move_style_normal.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_normal.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_normal.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_normal.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_normal.content_margin_left = 12
		move_style_normal.content_margin_right = 12
		move_style_normal.content_margin_top = 8
		move_style_normal.content_margin_bottom = 8

		# Focus state: Filled Citrus Yellow
		var move_style_focus = StyleBoxFlat.new()
		move_style_focus.bg_color = aCoreVibeTheme.COLOR_CITRUS_YELLOW
		move_style_focus.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_focus.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_focus.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_focus.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_focus.content_margin_left = 12
		move_style_focus.content_margin_right = 12
		move_style_focus.content_margin_top = 8
		move_style_focus.content_margin_bottom = 8

		# Disabled state: Grey with dark background (same for focused and unfocused)
		var move_style_disabled = StyleBoxFlat.new()
		move_style_disabled.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
		move_style_disabled.border_color = Color(0.5, 0.5, 0.5, 1.0)
		move_style_disabled.border_width_left = 2
		move_style_disabled.border_width_right = 2
		move_style_disabled.border_width_top = 2
		move_style_disabled.border_width_bottom = 2
		move_style_disabled.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_disabled.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_disabled.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_disabled.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		move_style_disabled.content_margin_left = 12
		move_style_disabled.content_margin_right = 12
		move_style_disabled.content_margin_top = 8
		move_style_disabled.content_margin_bottom = 8

		_move_out_btn.add_theme_stylebox_override("normal", move_style_normal)
		_move_out_btn.add_theme_stylebox_override("hover", move_style_normal.duplicate())
		_move_out_btn.add_theme_stylebox_override("pressed", move_style_normal.duplicate())
		_move_out_btn.add_theme_stylebox_override("focus", move_style_focus)
		_move_out_btn.add_theme_stylebox_override("disabled", move_style_disabled)
		_move_out_btn.add_theme_stylebox_override("disabled_focused", move_style_disabled.duplicate())

		_move_out_btn.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_CITRUS_YELLOW)
		_move_out_btn.add_theme_color_override("font_hover_color", aCoreVibeTheme.COLOR_CITRUS_YELLOW)
		_move_out_btn.add_theme_color_override("font_pressed_color", aCoreVibeTheme.COLOR_CITRUS_YELLOW)
		_move_out_btn.add_theme_color_override("font_focus_color", aCoreVibeTheme.COLOR_NIGHT_NAVY)
		_move_out_btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 1.0))
		_move_out_btn.custom_minimum_size = Vector2(140, 40)

	if _cancel_move_btn:
		# Normal state: Outlined Bubble Magenta
		var cancel_style_normal = StyleBoxFlat.new()
		cancel_style_normal.bg_color = Color(0, 0, 0, 0)
		cancel_style_normal.border_color = aCoreVibeTheme.COLOR_BUBBLE_MAGENTA
		cancel_style_normal.border_width_left = 2
		cancel_style_normal.border_width_right = 2
		cancel_style_normal.border_width_top = 2
		cancel_style_normal.border_width_bottom = 2
		cancel_style_normal.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_normal.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_normal.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_normal.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_normal.content_margin_left = 12
		cancel_style_normal.content_margin_right = 12
		cancel_style_normal.content_margin_top = 8
		cancel_style_normal.content_margin_bottom = 8

		# Focus state: Filled Bubble Magenta
		var cancel_style_focus = StyleBoxFlat.new()
		cancel_style_focus.bg_color = aCoreVibeTheme.COLOR_BUBBLE_MAGENTA
		cancel_style_focus.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_focus.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_focus.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_focus.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_focus.content_margin_left = 12
		cancel_style_focus.content_margin_right = 12
		cancel_style_focus.content_margin_top = 8
		cancel_style_focus.content_margin_bottom = 8

		# Disabled state: Grey with dark background (same for focused and unfocused)
		var cancel_style_disabled = StyleBoxFlat.new()
		cancel_style_disabled.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
		cancel_style_disabled.border_color = Color(0.5, 0.5, 0.5, 1.0)
		cancel_style_disabled.border_width_left = 2
		cancel_style_disabled.border_width_right = 2
		cancel_style_disabled.border_width_top = 2
		cancel_style_disabled.border_width_bottom = 2
		cancel_style_disabled.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_disabled.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_disabled.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_disabled.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		cancel_style_disabled.content_margin_left = 12
		cancel_style_disabled.content_margin_right = 12
		cancel_style_disabled.content_margin_top = 8
		cancel_style_disabled.content_margin_bottom = 8

		_cancel_move_btn.add_theme_stylebox_override("normal", cancel_style_normal)
		_cancel_move_btn.add_theme_stylebox_override("hover", cancel_style_normal.duplicate())
		_cancel_move_btn.add_theme_stylebox_override("pressed", cancel_style_normal.duplicate())
		_cancel_move_btn.add_theme_stylebox_override("focus", cancel_style_focus)
		_cancel_move_btn.add_theme_stylebox_override("disabled", cancel_style_disabled)
		_cancel_move_btn.add_theme_stylebox_override("disabled_focused", cancel_style_disabled.duplicate())

		_cancel_move_btn.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
		_cancel_move_btn.add_theme_color_override("font_hover_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
		_cancel_move_btn.add_theme_color_override("font_pressed_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
		_cancel_move_btn.add_theme_color_override("font_focus_color", aCoreVibeTheme.COLOR_NIGHT_NAVY)
		_cancel_move_btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 1.0))
		_cancel_move_btn.custom_minimum_size = Vector2(140, 40)

	# Create selection arrows and dark box for roster
	call_deferred("_create_selection_arrows")

func _ds() -> Node:
	return get_node_or_null("/root/aDormSystem")

# ═══════════════════════════════════════════════════════════════════════════
# PANELBASE OVERRIDES
# ═══════════════════════════════════════════════════════════════════════════

func _on_panel_gained_focus() -> void:
	super()
	print("[DormsPanel] Panel gained focus")
	_nav_state = NavState.ROSTER_SELECT
	_nav_state_history.clear()
	print("[DormsPanel] Nav state set to ROSTER_SELECT, history cleared")
	_current_roster_index = 0
	_focus_current_roster()

func _can_panel_close() -> bool:
	# Prevent closing if there are incomplete changes
	# If common room is empty, we're done - allow closing (auto-accept pending moves if any)

	# Block only if there are unassigned common room members
	if _common_members.size() > 0:
		_show_toast("You must assign all common room members before continuing.")
		return false

	# If common room is empty but there are pending reassignments, auto-accept them
	if _pending_reassignments.size() > 0:
		print("[DormsPanel._can_panel_close] Auto-accepting pending reassignments before closing")
		_auto_accept_plan()
		# Return true to allow closing (auto-accept happens synchronously)

	# Common room is empty and all moves are either accepted or there were no moves - allow closing
	return true

# ═══════════════════════════════════════════════════════════════════════════
# INPUT HANDLING
# ═══════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not is_active():
		return

	# Note: Popup input is now handled by ToastPopup class
	# It calls set_input_as_handled() to block panel input while visible

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
		NavState.ROSTER_SELECT: return "ROSTER_SELECT"
		NavState.COMMON_SELECT: return "COMMON_SELECT"
		NavState.ROOM_SELECT: return "ROOM_SELECT"
		NavState.ACTION_SELECT: return "ACTION_SELECT"
		_: return "UNKNOWN"

func _navigate_up() -> void:
	match _nav_state:
		NavState.ROSTER_SELECT:
			if _roster_list and _current_roster_index > 0:
				_current_roster_index -= 1
				print("[DEBUG Arrow] Navigate UP - roster index now: %d" % _current_roster_index)
				_focus_current_roster()
				# Update arrow position after selection change
				call_deferred("_update_roster_arrow_position")
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
			# At top of action menu - can't go up further

func _navigate_down() -> void:
	match _nav_state:
		NavState.ROSTER_SELECT:
			if _roster_list and _current_roster_index < _roster_list.item_count - 1:
				_current_roster_index += 1
				print("[DEBUG Arrow] Navigate DOWN - roster index now: %d" % _current_roster_index)
				_focus_current_roster()
				# Update arrow position after selection change
				call_deferred("_update_roster_arrow_position")
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
			# 2x4 grid: move left within grid
			if _current_room_index % 4 > 0:
				_current_room_index -= 1
				_focus_current_room()
			else:
				# At leftmost edge of grid - navigate to Action Menu
				_push_nav_state(NavState.ACTION_SELECT)
				_current_action_index = 0
				_focus_current_action(true)  # Panel transition - wait for layout
		NavState.ACTION_SELECT:
			# Navigate to Roster
			_push_nav_state(NavState.ROSTER_SELECT)
			_current_roster_index = 0
			_focus_current_roster()
		NavState.COMMON_SELECT:
			# Navigate to Roster
			_push_nav_state(NavState.ROSTER_SELECT)
			_current_roster_index = 0
			_focus_current_roster()
		_:
			# ROSTER_SELECT at left edge - no further left navigation
			pass

func _navigate_right() -> void:
	match _nav_state:
		NavState.ROSTER_SELECT:
			# Navigate to Action Menu
			_push_nav_state(NavState.ACTION_SELECT)
			_current_action_index = 0
			_focus_current_action(true)  # Panel transition - wait for layout
		NavState.COMMON_SELECT:
			# Navigate to Action Menu
			_push_nav_state(NavState.ACTION_SELECT)
			_current_action_index = 0
			_focus_current_action(true)  # Panel transition - wait for layout
		NavState.ACTION_SELECT:
			# Navigate to Rooms
			_push_nav_state(NavState.ROOM_SELECT)
			_current_room_index = 0
			_focus_current_room(true)  # Panel transition - wait for animation
		NavState.ROOM_SELECT:
			# 2x4 grid: move right within grid
			if _current_room_index % 4 < 3 and _current_room_index < _room_buttons.size() - 1:
				_current_room_index += 1
				_focus_current_room()
			# At rightmost edge - no further right navigation
		_:
			pass

func _on_accept_input() -> void:
	match _nav_state:
		NavState.ROSTER_SELECT:
			if _roster_list and _current_roster_index >= 0 and _current_roster_index < _roster_list.item_count:
				# Trigger selection handler
				_on_roster_item_selected(_current_roster_index)
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
	# Special case: if in ROSTER_SELECT, clear all state and exit to StatusPanel
	if _nav_state == NavState.ROSTER_SELECT:
		print("[DormsPanel._on_back_input] In ROSTER_SELECT - clearing all state and attempting to exit")

		# Clear all navigation state
		_nav_state_history.clear()
		_selected_member = ""
		_selected_room = ""

		# Check if panel can close
		if not _can_panel_close():
			# Panel has pending changes - prevent closing
			print("[DormsPanel._on_back_input] Cannot close panel - pending changes exist")
			get_viewport().set_input_as_handled()
		else:
			# Panel can close - let GameMenu handle the back button
			# This allows proper slide animation back to StatusPanel
			print("[DormsPanel._on_back_input] Cleared state, returning to StatusPanel")
			# Do NOT call get_viewport().set_input_as_handled() - let event bubble up
		return

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
			NavState.ROSTER_SELECT:
				_focus_current_roster()
			NavState.COMMON_SELECT:
				_focus_current_common()
			NavState.ROOM_SELECT:
				_focus_current_room()
			NavState.ACTION_SELECT:
				_focus_current_action()
		get_viewport().set_input_as_handled()
	else:
		# No history - check if panel can close
		if not _can_panel_close():
			# Panel has pending changes - prevent closing
			print("[DormsPanel._on_back_input] Cannot close panel - pending changes exist")
			get_viewport().set_input_as_handled()
		else:
			# Panel can close - let GameMenu handle the back button
			# This allows proper slide animation back to StatusPanel
			print("[DormsPanel._on_back_input] No history, letting GameMenu handle back button for slide transition")
			# Do NOT call get_viewport().set_input_as_handled() - let event bubble up

func _focus_current_roster() -> void:
	print("[DEBUG Arrow] _focus_current_roster called - index: %d" % _current_roster_index)

	if _roster_list and _current_roster_index >= 0 and _current_roster_index < _roster_list.item_count:
		_roster_list.select(_current_roster_index)
		_roster_list.ensure_current_is_visible()
		_roster_list.grab_focus()
		# Update details panel to show the focused member
		if _current_roster_index < _all_members.size():
			var focused_member: String = _all_members[_current_roster_index]
			print("[DormsPanel._focus_current_roster] Focused member: ", focused_member)
			_update_details_for_member(focused_member)

	# Hide action and room arrows when focusing roster
	if _action_selection_arrow:
		_action_selection_arrow.visible = false
	if _room_selection_arrow:
		_room_selection_arrow.visible = false

	# Update roster arrow position (will show it when position is calculated)
	call_deferred("_update_roster_arrow_position")

	_animate_panel_focus(NavState.ROSTER_SELECT)

func _focus_current_room(is_panel_transition: bool = false) -> void:
	if _current_room_index >= 0 and _current_room_index < _room_buttons.size():
		_room_buttons[_current_room_index].grab_focus()

	# Hide roster and action arrows immediately when focusing on rooms
	if _roster_selection_arrow:
		_roster_selection_arrow.visible = false
		print("[DEBUG Arrow] Roster arrow hidden when moving to rooms")
	if _roster_dark_box:
		_roster_dark_box.visible = false
		print("[DEBUG Arrow] Roster dark box hidden when moving to rooms")
	if _action_selection_arrow:
		_action_selection_arrow.visible = false
		print("[DEBUG Arrow] Action arrow hidden when moving to rooms")

	# Start panel animation
	_animate_panel_focus(NavState.ROOM_SELECT)

	if is_panel_transition:
		# First time entering room panel - wait for animation to complete
		print("[DEBUG Arrow] First room navigation - waiting for panel animation (%f seconds)" % ANIM_DURATION)
		await get_tree().create_timer(ANIM_DURATION).timeout
		print("[DEBUG Arrow] Panel animation complete, updating room arrow position")
	else:
		# Already in room panel, just moving between rooms - be fast
		print("[DEBUG Arrow] Moving between rooms - waiting one frame")
		await get_tree().process_frame
		print("[DEBUG Arrow] Layout stabilized, updating room arrow position")

	# Update room arrow position (will show it after position is calculated)
	call_deferred("_update_room_arrow_position")

func _focus_current_common() -> void:
	if _current_common_index >= 0 and _current_common_index < _common_buttons.size():
		_common_buttons[_current_common_index].grab_focus()
		# Update details panel to show the focused member
		if _current_common_index < _common_members.size():
			var focused_member: String = _common_members[_current_common_index]
			print("[DormsPanel._focus_current_common] Focused member: ", focused_member)
			_update_details_for_member(focused_member)

	# Hide all arrows when focusing on common room
	if _roster_selection_arrow:
		_roster_selection_arrow.visible = false
	if _roster_dark_box:
		_roster_dark_box.visible = false
	if _action_selection_arrow:
		_action_selection_arrow.visible = false
	if _room_selection_arrow:
		_room_selection_arrow.visible = false

	_animate_panel_focus(NavState.COMMON_SELECT)

func _focus_current_action(is_panel_transition: bool = false) -> void:
	if _current_action_index >= 0 and _current_action_index < _action_buttons.size():
		_action_buttons[_current_action_index].grab_focus()

	# Hide roster and room arrows when moving to action menu
	if _roster_selection_arrow:
		_roster_selection_arrow.visible = false
		print("[DEBUG Arrow] Roster arrow hidden when moving to action menu")
	if _roster_dark_box:
		_roster_dark_box.visible = false
		print("[DEBUG Arrow] Roster dark box hidden when moving to action menu")
	if _room_selection_arrow:
		_room_selection_arrow.visible = false

	# Start panel animation
	_animate_panel_focus(NavState.ACTION_SELECT)

	if is_panel_transition:
		# First time entering action menu - wait a bit for layout to settle
		var delay = ANIM_DURATION * 0.5  # Half animation duration
		print("[DEBUG Arrow] First action navigation - waiting for layout (%f seconds)" % delay)
		await get_tree().create_timer(delay).timeout
		print("[DEBUG Arrow] Layout settled, updating action arrow position")
	else:
		# Already in action menu, just moving between buttons - be fast
		print("[DEBUG Arrow] Moving between action buttons - waiting one frame")
		await get_tree().process_frame
		print("[DEBUG Arrow] Layout stabilized, updating action arrow position")

	# Update action arrow position
	call_deferred("_update_action_arrow_position")

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
	_roster_list.clear()
	_roster_buttons.clear()

	var ds: Node = _ds()
	if not ds:
		print("[DormsPanel._build_roster_list] ERROR: DormSystem not found!")
		return

	# Get all dorm members (everyone who has or could have a room)
	_all_members = _get_all_dorm_members(ds)
	print("[DormsPanel._build_roster_list] Found %d members" % _all_members.size())

	if _all_members.size() == 0:
		return

	# Create ItemList entry for each member
	var selected_index: int = -1
	for i in range(_all_members.size()):
		var aid: String = _all_members[i]
		var member_name: String = String(ds.call("display_name", aid))
		_roster_list.add_item(member_name)
		_roster_list.set_item_metadata(i, aid)

		# Track selected index
		if _selected_member == aid:
			selected_index = i

	# Restore selection if we found the selected member
	if selected_index >= 0:
		_roster_list.select(selected_index)
		_current_roster_index = selected_index

	# Connect ItemList selection signal if not already connected
	if not _roster_list.item_selected.is_connected(_on_roster_item_selected):
		_roster_list.item_selected.connect(_on_roster_item_selected)

	print("[DormsPanel._build_roster_list] Created %d roster items" % _roster_list.item_count)

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
		btn.custom_minimum_size = Vector2(92, 61)  # 15% smaller
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
	"""Build array of action elements for navigation (View Type + buttons)"""
	_action_buttons.clear()
	# View Type filter is first action element (OptionButton, not Button)
	# We'll handle it specially in focus code
	if _assign_room_btn:
		_action_buttons.append(_assign_room_btn)
	if _move_out_btn:
		_action_buttons.append(_move_out_btn)
	if _cancel_move_btn:
		_action_buttons.append(_cancel_move_btn)

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
		# Make empty label grey (not clickable)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		empty.add_theme_font_size_override("font_size", 14)
		_common_list.add_child(empty)
		return

	# Core Vibe: Create labels for each common room member (awaiting assignment)
	for i in range(_common_members.size()):
		var aid: String = _common_members[i]
		var lbl := Label.new()
		lbl.text = String(ds.call("display_name", aid))
		# Make common room members grey (not clickable in this list)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
		lbl.add_theme_font_size_override("font_size", 14)
		_common_list.add_child(lbl)

func _update_details() -> void:
	"""Update details panel for the currently selected member"""
	print("[DormsPanel._update_details] Updating details for selected member: ", _selected_member)
	if _selected_member == "":
		if _detail_content:
			_detail_content.text = "[i]Select a member from the roster.[/i]"
			print("[DormsPanel._update_details] Showing default prompt (no selection)")
	else:
		_update_details_for_member(_selected_member)
		print("[DormsPanel._update_details] Details updated for: ", _selected_member)

func _update_details_for_member(member_id: String) -> void:
	"""Update details panel for a specific member (used for hover and selection)"""
	print("[DormsPanel._update_details_for_member] Updating details panel in RIGHT PANEL for member: ", member_id)

	if not _detail_content:
		print("[DormsPanel._update_details_for_member] ERROR: _detail_content is null!")
		return

	if member_id == "":
		_detail_content.text = "[i]Select a member from the roster.[/i]"
		return

	var ds: Node = _ds()
	if not ds:
		_detail_content.text = "[i]Dorm system unavailable.[/i]"
		return

	var lines := PackedStringArray()

	# Name
	var member_name: String = String(ds.call("display_name", member_id))
	lines.append("[b]Name:[/b] [color=#4DE9FF]%s[/color]" % member_name)
	lines.append("")

	# Room
	var room_id: String = _get_member_room(member_id)
	if room_id != "":
		lines.append("[b]Room:[/b] [color=#4DE9FF]%s[/color]" % room_id)
	else:
		lines.append("[b]Room:[/b] [color=#4DE9FF]Common Room[/color]")
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
				lines.append("  • %s - [color=#808080]Empty[/color]" % n)
			else:
				var n_name: String = String(ds.call("display_name", n_occupant))
				var status: String = _get_relationship_status(ds, member_id, n_occupant)
				var status_color: String = _get_relationship_color(status)
				lines.append("  • %s - [color=%s]%s[/color] with %s" % [n, status_color, status, n_name])
		lines.append("")

	# Show pending reassignment in Reassignments view
	if _current_view == ViewType.REASSIGNMENTS:
		var pending_room: String = _get_pending_assignment(member_id)
		if pending_room != "":
			lines.append("")
			# Core Vibe: Citrus Yellow for pending Saturday moves
			lines.append("[b][color=#FFE84D]Pending Saturday Move:[/color][/b]")
			lines.append("  • Will move to room %s" % pending_room)

	_detail_content.text = _join_psa(lines, "\n")
	print("[DormsPanel._update_details_for_member] Details panel updated with %d lines for %s" % [lines.size(), member_name])

func _update_action_buttons() -> void:
	if not _assign_room_btn or not _move_out_btn or not _cancel_move_btn:
		return

	var ds: Node = _ds()
	if not ds:
		_assign_room_btn.disabled = true
		_move_out_btn.disabled = true
		_cancel_move_btn.disabled = true
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

# ═══════════════════════════════════════════════════════════════════════════
# SELECTION HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_roster_item_selected(index: int) -> void:
	"""Handle ItemList item selection"""
	if not _roster_list or index < 0 or index >= _roster_list.item_count:
		return

	var aid: String = String(_roster_list.get_item_metadata(index))
	print("[DormsPanel._on_roster_item_selected] Selected member: ", aid)
	_selected_member = aid
	_current_roster_index = index
	_update_details()
	_update_action_buttons()
	_update_room_colors()

	# Auto-navigate to Action Menu (locked navigation flow)
	_push_nav_state(NavState.ACTION_SELECT)
	_current_action_index = 0
	_focus_current_action(true)  # Panel transition - wait for layout
	print("[DormsPanel._on_roster_item_selected] Auto-navigated to ACTION_SELECT")

func _on_roster_member_selected(aid: String) -> void:
	print("[DormsPanel._on_roster_member_selected] Selected member: ", aid)
	_selected_member = aid
	_update_details()
	_update_action_buttons()
	_update_room_colors()

	# Auto-navigate to Action Menu (locked navigation flow)
	_push_nav_state(NavState.ACTION_SELECT)
	_current_action_index = 0
	_focus_current_action(true)  # Panel transition - wait for layout
	print("[DormsPanel._on_roster_member_selected] Auto-navigated to ACTION_SELECT")

func _on_roster_member_hovered(aid: String) -> void:
	"""Update details panel when hovering over a roster member"""
	print("[DormsPanel._on_roster_member_hovered] Hovering over: ", aid)
	_update_details_for_member(aid)

func _on_roster_member_unhovered() -> void:
	"""Restore details panel to selected member when hover leaves"""
	print("[DormsPanel._on_roster_member_unhovered] Mouse left roster member")
	# Restore details to the currently selected member (or empty if none selected)
	_update_details()

func _on_room_selected(room_id: String) -> void:
	_selected_room = room_id

	# If we have a member selected from common room, try to assign them
	if _selected_member != "" and _common_members.has(_selected_member):
		_try_assign_to_room(room_id)

func _on_common_member_selected(aid: String) -> void:
	print("[DormsPanel._on_common_member_selected] Selected member: ", aid)
	_selected_member = aid
	_update_details()
	_update_action_buttons()
	_update_room_colors()

	# Auto-navigate to Action Menu (locked navigation flow)
	_push_nav_state(NavState.ACTION_SELECT)
	_current_action_index = 0
	_focus_current_action(true)  # Panel transition - wait for layout
	print("[DormsPanel._on_common_member_selected] Auto-navigated to ACTION_SELECT")

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

	# Auto-navigate to room selection (locked navigation flow)
	_push_nav_state(NavState.ROOM_SELECT)
	_current_room_index = 0
	_focus_current_room(true)  # Panel transition - wait for animation

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
		_show_toast("Error: DormSystem not found.")
		return

	# Check if reassignment can start today (Sunday only)
	var can_start: bool = false
	if ds.has_method("can_start_reassignment_today"):
		can_start = bool(ds.call("can_start_reassignment_today"))

	print("[DormsPanel._on_move_out_pressed] can_start_reassignment_today: %s" % can_start)

	if not can_start:
		print("[DormsPanel._on_move_out_pressed] Not Sunday - cannot start reassignment")
		_show_toast("Room reassignment can only be started on Sunday.\nAdvance the calendar to Sunday first.")
		# Don't switch to reassignments view if we can't start
		return

	var member_name: String = _get_member_name(_selected_member)

	# Confirm staging the move
	print("[DormsPanel._on_move_out_pressed] Showing confirmation dialog")
	var confirmed: bool = await _ask_confirm("Would you like to move out %s and stage in the Common Room?" % member_name)
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

	# Clear selection and return to roster (locked navigation flow)
	_selected_member = ""
	_nav_state = NavState.ROSTER_SELECT
	_nav_state_history.clear()  # Clear history to reset navigation flow
	_rebuild()

	# Focus back on roster for next selection
	_current_roster_index = 0
	_focus_current_roster()

func _on_cancel_move_pressed() -> void:
	"""Cancel all pending room reassignments and reset to original state

	Works at any time during the week:
	- Before plan is locked: cancels pending moves
	- After plan is locked: unlocks and reverts to original room assignments
	"""
	var confirmed: bool = await _ask_confirm("Cancel all pending reassignments?\nThis will reset rooms to their original state.")
	if not confirmed:
		return

	var ds: Node = _ds()
	if ds and ds.has_method("stage_reset_plan"):
		ds.call("stage_reset_plan")

	_pending_reassignments.clear()
	_show_toast("All pending moves cancelled. Rooms reset to original state.")

	# Clear selection and return to default state
	_selected_member = ""
	_nav_state = NavState.ROSTER_SELECT
	_nav_state_history.clear()
	_rebuild()

func _auto_accept_plan() -> void:
	"""Automatically accept the plan when all common room members are assigned"""
	print("[DormsPanel._auto_accept_plan] Auto-accepting plan - common room is empty")

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

	_pending_reassignments.clear()
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
		var member_name: String = _get_member_name(_selected_member)
		_show_toast("%s is already in this room." % member_name)
		return

	# Check if this is their previous room (before moving to common)
	var previous_room: String = _get_member_previous_room(_selected_member)
	if previous_room == room_id:
		var member_name: String = _get_member_name(_selected_member)
		_show_toast("%s is already in this room." % member_name)
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

	# Clear selection and return to roster (locked navigation flow)
	_selected_member = ""
	_selected_room = ""
	_nav_state = NavState.ROSTER_SELECT
	_nav_state_history.clear()  # Clear history to reset navigation flow
	_rebuild()

	# Auto-accept plan if common room is now empty
	if _can_accept_plan():
		_auto_accept_plan()
		return  # Skip focus since plan is locked

	# Focus back on roster for next selection
	_current_roster_index = 0
	_focus_current_roster()

# ═══════════════════════════════════════════════════════════════════════════
# SELECTION ARROWS & DARK BOX
# ═══════════════════════════════════════════════════════════════════════════

func _create_selection_arrows() -> void:
	"""Create selection arrow and dark box for roster list"""
	if _roster_list:
		_roster_selection_arrow = Label.new()
		_roster_selection_arrow.text = "◄"
		_roster_selection_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_roster_selection_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_roster_selection_arrow.add_theme_font_size_override("font_size", 43)
		_roster_selection_arrow.modulate = Color(1, 1, 1, 1)
		_roster_selection_arrow.custom_minimum_size = Vector2(54, 72)
		_roster_selection_arrow.size = Vector2(54, 72)
		_roster_selection_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_roster_selection_arrow.z_index = 100
		add_child(_roster_selection_arrow)
		await get_tree().process_frame
		_roster_selection_arrow.size = Vector2(54, 72)

		_roster_dark_box = PanelContainer.new()
		_roster_dark_box.custom_minimum_size = Vector2(240, 20)
		_roster_dark_box.size = Vector2(240, 20)
		_roster_dark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_roster_dark_box.z_index = 99
		var box_style = StyleBoxFlat.new()
		box_style.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
		box_style.corner_radius_top_left = 8
		box_style.corner_radius_top_right = 8
		box_style.corner_radius_bottom_left = 8
		box_style.corner_radius_bottom_right = 8
		_roster_dark_box.add_theme_stylebox_override("panel", box_style)
		add_child(_roster_dark_box)
		await get_tree().process_frame
		_roster_dark_box.size = Vector2(240, 20)

		_start_arrow_pulse(_roster_selection_arrow)

	# Create action menu arrow (to the right of the action panel, facing left)
	_action_selection_arrow = Label.new()
	_action_selection_arrow.text = "◄"
	_action_selection_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_selection_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_selection_arrow.add_theme_font_size_override("font_size", 43)
	_action_selection_arrow.modulate = Color(1, 1, 1, 1)

	# Add shadow to the arrow
	var arrow_label_settings = LabelSettings.new()
	arrow_label_settings.font_size = 43
	arrow_label_settings.shadow_color = Color(0, 0, 0, 0.8)
	arrow_label_settings.shadow_size = 4
	arrow_label_settings.shadow_offset = Vector2(2, 2)
	_action_selection_arrow.label_settings = arrow_label_settings

	_action_selection_arrow.custom_minimum_size = Vector2(54, 40)
	_action_selection_arrow.size = Vector2(54, 40)
	_action_selection_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_selection_arrow.z_index = 100
	_action_selection_arrow.visible = false  # Initially hidden
	add_child(_action_selection_arrow)
	await get_tree().process_frame
	_action_selection_arrow.size = Vector2(54, 40)

	# Create room selection arrow (to the right of the selected room, facing left)
	_room_selection_arrow = Label.new()
	_room_selection_arrow.text = "◄"
	_room_selection_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_selection_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_selection_arrow.add_theme_font_size_override("font_size", 43)
	_room_selection_arrow.modulate = Color(1, 1, 1, 1)

	# Add shadow to the arrow
	var room_arrow_label_settings = LabelSettings.new()
	room_arrow_label_settings.font_size = 43
	room_arrow_label_settings.shadow_color = Color(0, 0, 0, 0.8)
	room_arrow_label_settings.shadow_size = 4
	room_arrow_label_settings.shadow_offset = Vector2(2, 2)
	_room_selection_arrow.label_settings = room_arrow_label_settings

	_room_selection_arrow.custom_minimum_size = Vector2(54, 40)
	_room_selection_arrow.size = Vector2(54, 40)
	_room_selection_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_selection_arrow.z_index = 100
	_room_selection_arrow.visible = false  # Initially hidden
	add_child(_room_selection_arrow)
	await get_tree().process_frame
	_room_selection_arrow.size = Vector2(54, 40)

	# Initial arrow position
	call_deferred("_update_roster_arrow_position")

func _update_roster_arrow_position() -> void:
	"""Update roster arrow and dark box position"""
	print("[DEBUG Arrow] _update_roster_arrow_position called")

	if not _roster_selection_arrow or not _roster_list:
		print("[DEBUG Arrow] Early return - arrow or list null: arrow=%s, list=%s" % [_roster_selection_arrow != null, _roster_list != null])
		return

	var selected = _roster_list.get_selected_items()
	if selected.size() == 0:
		print("[DEBUG Arrow] Early return - no items selected")
		return

	print("[DEBUG Arrow] Arrow currently visible: %s" % _roster_selection_arrow.visible)

	await get_tree().process_frame

	var item_index = selected[0]
	var item_rect = _roster_list.get_item_rect(item_index)
	var list_global_pos = _roster_list.global_position
	var panel_global_pos = global_position
	var list_offset_in_panel = list_global_pos - panel_global_pos

	print("[DEBUG Arrow] Item index: %d" % item_index)
	print("[DEBUG Arrow] Item rect: pos=%s, size=%s" % [item_rect.position, item_rect.size])
	print("[DEBUG Arrow] List global pos: %s" % list_global_pos)
	print("[DEBUG Arrow] Panel global pos: %s" % panel_global_pos)
	print("[DEBUG Arrow] List offset in panel: %s" % list_offset_in_panel)
	print("[DEBUG Arrow] Roster list size: %s" % _roster_list.size)
	print("[DEBUG Arrow] Arrow size: %s" % _roster_selection_arrow.size)

	var scroll_offset = 0.0
	if _roster_list.get_v_scroll_bar():
		scroll_offset = _roster_list.get_v_scroll_bar().value
		print("[DEBUG Arrow] Scroll offset: %f" % scroll_offset)

	var arrow_x = list_offset_in_panel.x + _roster_list.size.x - 8.0 - 80.0 + 40.0
	var arrow_y = list_offset_in_panel.y + item_rect.position.y - scroll_offset + (item_rect.size.y / 2.0) - (_roster_selection_arrow.size.y / 2.0)

	print("[DEBUG Arrow] Calculated arrow position: x=%f, y=%f" % [arrow_x, arrow_y])
	print("[DEBUG Arrow] Calculation breakdown:")
	print("[DEBUG Arrow]   arrow_x = %f + %f - 8.0 - 80.0 + 40.0 = %f" % [list_offset_in_panel.x, _roster_list.size.x, arrow_x])
	print("[DEBUG Arrow]   arrow_y = %f + %f - %f + %f - %f = %f" % [list_offset_in_panel.y, item_rect.position.y, scroll_offset, item_rect.size.y / 2.0, _roster_selection_arrow.size.y / 2.0, arrow_y])

	_roster_selection_arrow.position = Vector2(arrow_x, arrow_y)
	print("[DEBUG Arrow] Arrow position set to: %s" % _roster_selection_arrow.position)

	# Only show arrow if we're in ROSTER_SELECT state
	var should_be_visible = (_nav_state == NavState.ROSTER_SELECT)
	_roster_selection_arrow.visible = should_be_visible
	print("[DEBUG Arrow] Arrow visibility set to: %s (nav_state: %s)" % [should_be_visible, _get_nav_state_name(_nav_state)])

	if _roster_dark_box:
		var box_x = arrow_x - _roster_dark_box.size.x - 4.0
		var box_y = arrow_y + (_roster_selection_arrow.size.y / 2.0) - (_roster_dark_box.size.y / 2.0)
		_roster_dark_box.position = Vector2(box_x, box_y)
		_roster_dark_box.visible = should_be_visible
		print("[DEBUG Arrow] Dark box position set to: %s, visible: %s" % [_roster_dark_box.position, should_be_visible])

func _update_action_arrow_position() -> void:
	"""Update action menu arrow position - to the right of the center panel, facing left"""
	if not _action_selection_arrow or not _center_panel:
		return

	# Only show arrow if we're in ACTION_SELECT state
	if _nav_state != NavState.ACTION_SELECT:
		_action_selection_arrow.visible = false
		# Stop pulse animation when hiding arrow
		if _action_arrow_pulse_tween and is_instance_valid(_action_arrow_pulse_tween):
			_action_arrow_pulse_tween.kill()
			_action_arrow_pulse_tween = null
		return

	# Only show if current button index is valid
	if _current_action_index < 0 or _current_action_index >= _action_buttons.size():
		_action_selection_arrow.visible = false
		# Stop pulse animation when hiding arrow
		if _action_arrow_pulse_tween and is_instance_valid(_action_arrow_pulse_tween):
			_action_arrow_pulse_tween.kill()
			_action_arrow_pulse_tween = null
		return

	var current_btn: Button = _action_buttons[_current_action_index]
	if not current_btn:
		_action_selection_arrow.visible = false
		# Stop pulse animation when hiding arrow
		if _action_arrow_pulse_tween and is_instance_valid(_action_arrow_pulse_tween):
			_action_arrow_pulse_tween.kill()
			_action_arrow_pulse_tween = null
		return

	# Show arrow regardless of whether button is enabled or disabled
	_action_selection_arrow.visible = true

	var center_panel_global_pos = _center_panel.global_position
	var panel_global_pos = global_position
	var center_panel_offset = center_panel_global_pos - panel_global_pos

	var btn_global_pos = current_btn.global_position
	var btn_offset_in_panel = btn_global_pos - panel_global_pos

	# Position to the right of the center panel, offset 45px to the left
	var arrow_x = center_panel_offset.x + _center_panel.size.x + 8.0 - 45.0
	# Vertically align with the current button
	var arrow_y = btn_offset_in_panel.y + (current_btn.size.y / 2.0) - (_action_selection_arrow.size.y / 2.0)

	_action_selection_arrow.position = Vector2(arrow_x, arrow_y)

	# Restart pulse animation with new base position
	if _action_arrow_pulse_tween and is_instance_valid(_action_arrow_pulse_tween):
		_action_arrow_pulse_tween.kill()

	_action_arrow_pulse_tween = create_tween()
	_action_arrow_pulse_tween.set_loops()
	_action_arrow_pulse_tween.set_trans(Tween.TRANS_SINE)
	_action_arrow_pulse_tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse left (toward the panel it's pointing at)
	_action_arrow_pulse_tween.tween_property(_action_selection_arrow, "position:x", arrow_x - 6, 0.6)
	_action_arrow_pulse_tween.tween_property(_action_selection_arrow, "position:x", arrow_x, 0.6)

func _update_room_arrow_position() -> void:
	"""Update room selection arrow position - to the right of the selected room"""
	if not _room_selection_arrow or not _rooms_grid:
		return

	# Only show arrow if we're in ROOM_SELECT state
	if _nav_state != NavState.ROOM_SELECT:
		_room_selection_arrow.visible = false
		# Stop pulse animation when hiding arrow
		if _room_arrow_pulse_tween and is_instance_valid(_room_arrow_pulse_tween):
			_room_arrow_pulse_tween.kill()
			_room_arrow_pulse_tween = null
		return

	# Only show if current room index is valid
	if _current_room_index < 0 or _current_room_index >= _room_buttons.size():
		_room_selection_arrow.visible = false
		# Stop pulse animation when hiding arrow
		if _room_arrow_pulse_tween and is_instance_valid(_room_arrow_pulse_tween):
			_room_arrow_pulse_tween.kill()
			_room_arrow_pulse_tween = null
		return

	var current_btn: Button = _room_buttons[_current_room_index]
	if not current_btn:
		_room_selection_arrow.visible = false
		# Stop pulse animation when hiding arrow
		if _room_arrow_pulse_tween and is_instance_valid(_room_arrow_pulse_tween):
			_room_arrow_pulse_tween.kill()
			_room_arrow_pulse_tween = null
		return

	# Show arrow
	_room_selection_arrow.visible = true

	var btn_global_pos = current_btn.global_position
	var panel_global_pos = global_position
	var btn_offset_in_panel = btn_global_pos - panel_global_pos

	# Position to the right of the selected room button, offset 20px to the left
	var arrow_x = btn_offset_in_panel.x + current_btn.size.x + 8.0 - 20.0
	# Vertically align with the current button
	var arrow_y = btn_offset_in_panel.y + (current_btn.size.y / 2.0) - (_room_selection_arrow.size.y / 2.0)

	_room_selection_arrow.position = Vector2(arrow_x, arrow_y)

	# Restart pulse animation with new base position
	if _room_arrow_pulse_tween and is_instance_valid(_room_arrow_pulse_tween):
		_room_arrow_pulse_tween.kill()

	_room_arrow_pulse_tween = create_tween()
	_room_arrow_pulse_tween.set_loops()
	_room_arrow_pulse_tween.set_trans(Tween.TRANS_SINE)
	_room_arrow_pulse_tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse left (in the direction it's pointing)
	_room_arrow_pulse_tween.tween_property(_room_selection_arrow, "position:x", arrow_x - 6, 0.6)
	_room_arrow_pulse_tween.tween_property(_room_selection_arrow, "position:x", arrow_x, 0.6)

func _start_arrow_pulse(arrow: Label) -> void:
	"""Start pulsing animation for arrow"""
	if not arrow:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	var base_x = arrow.position.x
	tween.tween_property(arrow, "position:x", base_x - 6, 0.6)
	tween.tween_property(arrow, "position:x", base_x, 0.6)

# ═══════════════════════════════════════════════════════════════════════════
# BUTTON PULSE ANIMATION
# ═══════════════════════════════════════════════════════════════════════════

func _on_button_focus_entered(button: Button) -> void:
	"""Start pulsing animation when button gains focus"""
	_start_button_pulse(button)

func _on_button_focus_exited() -> void:
	"""Stop pulsing animation when button loses focus"""
	_stop_button_pulse()

func _start_button_pulse(button: Button) -> void:
	"""Start pulsing animation for a button"""
	if not button:
		return

	_stop_button_pulse()
	_button_pulse_target = button

	_button_pulse_tween = create_tween()
	_button_pulse_tween.set_loops()
	_button_pulse_tween.set_trans(Tween.TRANS_SINE)
	_button_pulse_tween.set_ease(Tween.EASE_IN_OUT)

	_button_pulse_tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.6)
	_button_pulse_tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.6)

func _stop_button_pulse() -> void:
	"""Stop button pulsing animation"""
	if _button_pulse_tween and is_instance_valid(_button_pulse_tween):
		_button_pulse_tween.kill()
		_button_pulse_tween = null

	if _button_pulse_target and is_instance_valid(_button_pulse_target):
		_button_pulse_target.scale = Vector2(1.0, 1.0)
		_button_pulse_target = null

# ═══════════════════════════════════════════════════════════════════════════
# CONTINUOUS ARROW UPDATE DURING PANEL ANIMATION
# ═══════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	"""Update arrow position during panel animations"""
	if _panel_animating:
		call_deferred("_update_roster_arrow_position_immediate")

func _update_roster_arrow_position_immediate() -> void:
	"""Immediate roster arrow position update without await"""
	if not _roster_selection_arrow or not _roster_list:
		return

	var selected = _roster_list.get_selected_items()
	if selected.size() == 0:
		return

	var item_index = selected[0]
	var item_rect = _roster_list.get_item_rect(item_index)
	var list_global_pos = _roster_list.global_position
	var panel_global_pos = global_position
	var list_offset_in_panel = list_global_pos - panel_global_pos

	var scroll_offset = 0.0
	if _roster_list.get_v_scroll_bar():
		scroll_offset = _roster_list.get_v_scroll_bar().value

	var arrow_x = list_offset_in_panel.x + _roster_list.size.x - 8.0 - 80.0 + 40.0
	var arrow_y = list_offset_in_panel.y + item_rect.position.y - scroll_offset + (item_rect.size.y / 2.0) - (_roster_selection_arrow.size.y / 2.0)

	_roster_selection_arrow.position = Vector2(arrow_x, arrow_y)

	if _roster_dark_box:
		var box_x = arrow_x - _roster_dark_box.size.x - 4.0
		var box_y = arrow_y + (_roster_selection_arrow.size.y / 2.0) - (_roster_dark_box.size.y / 2.0)
		_roster_dark_box.position = Vector2(box_x, box_y)

func _on_panel_animation_finished() -> void:
	"""Called when panel animation completes"""
	_panel_animating = false
	set_process(false)
	call_deferred("_update_roster_arrow_position")

# ═══════════════════════════════════════════════════════════════════════════
# VISUAL HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _animate_panel_focus(active_panel: NavState) -> void:
	"""Animate panels to highlight which one is currently active"""
	if not _left_panel or not _center_panel or not _right_panel:
		return

	# Set animation flag to enable continuous arrow position updates
	_panel_animating = true
	set_process(true)

	var left_ratio := BASE_LEFT_RATIO
	var center_ratio := BASE_CENTER_RATIO
	var right_ratio := BASE_RIGHT_RATIO

	# Determine which panel gets the active scale
	match active_panel:
		NavState.ROSTER_SELECT, NavState.COMMON_SELECT:
			left_ratio = BASE_LEFT_RATIO * ACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * INACTIVE_SCALE
			right_ratio = BASE_RIGHT_RATIO * INACTIVE_SCALE
		NavState.ACTION_SELECT:
			left_ratio = BASE_LEFT_RATIO * INACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * ACTIVE_SCALE
			right_ratio = BASE_RIGHT_RATIO * INACTIVE_SCALE
		NavState.ROOM_SELECT:
			left_ratio = BASE_LEFT_RATIO * INACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * INACTIVE_SCALE
			right_ratio = BASE_RIGHT_RATIO * ACTIVE_SCALE

	# Create tweens for smooth animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(_left_panel, "size_flags_stretch_ratio", left_ratio, ANIM_DURATION)
	tween.tween_property(_center_panel, "size_flags_stretch_ratio", center_ratio, ANIM_DURATION)
	tween.tween_property(_right_panel, "size_flags_stretch_ratio", right_ratio, ANIM_DURATION)

	# Connect to finished signal to stop arrow updates
	tween.finished.connect(_on_panel_animation_finished)

func _apply_room_visual(btn: Button, room_id: String) -> void:
	var ds: Node = _ds()
	if not ds:
		return

	var state: int = int(ds.call("get_room_visual", room_id))

	# Core Vibe: Neon-kawaii room state colors
	var col := aCoreVibeTheme.COLOR_INK_CHARCOAL  # default
	if state == VIS_EMPTY:
		col = Color(aCoreVibeTheme.COLOR_SKY_CYAN.r, aCoreVibeTheme.COLOR_SKY_CYAN.g, aCoreVibeTheme.COLOR_SKY_CYAN.b, 0.3)  # Sky Cyan (empty/available)
	elif state == VIS_OCCUPIED:
		col = Color(aCoreVibeTheme.COLOR_GRAPE_VIOLET.r, aCoreVibeTheme.COLOR_GRAPE_VIOLET.g, aCoreVibeTheme.COLOR_GRAPE_VIOLET.b, 0.3)  # Grape Violet (occupied)
	elif state == VIS_STAGED:
		col = Color(aCoreVibeTheme.COLOR_CITRUS_YELLOW.r, aCoreVibeTheme.COLOR_CITRUS_YELLOW.g, aCoreVibeTheme.COLOR_CITRUS_YELLOW.b, 0.3)  # Citrus Yellow (moving out)
	elif state == VIS_LOCKED:
		col = Color(aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.r, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.g, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.b, 0.3)  # Bubble Magenta (locked)

	# Override with Bubble Magenta if this is the selected member's current room (can't select)
	if _selected_member != "" and _get_member_room(_selected_member) == room_id:
		col = Color(aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.r, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.g, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.b, 0.4)  # Bubble Magenta (can't go back)

	# Override with Bubble Magenta if room is already targeted in pending reassignments
	if _is_room_targeted(room_id):
		col = Color(aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.r, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.g, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.b, 0.4)  # Bubble Magenta (already targeted)

	# Override with Bubble Magenta if this is the selected member's previous room (before moving to common)
	if _selected_member != "" and _get_member_previous_room(_selected_member) == room_id:
		col = Color(aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.r, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.g, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.b, 0.4)  # Bubble Magenta (can't go back)

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
	btn.add_theme_stylebox_override("focus", sb)

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

func _get_member_previous_room(aid: String) -> String:
	"""Get the room this member vacated when moved to common room"""
	var ds: Node = _ds()
	if not ds:
		return ""

	# Check if DormSystem has the staged_prev_room data
	if ds.has_method("get_staged_prev_room_for"):
		return String(ds.call("get_staged_prev_room_for", aid))

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

func _get_relationship_color(status: String) -> String:
	"""Return color code based on relationship status"""
	match status:
		"Rival":
			return "#FF4AD9"  # Bubble Magenta
		"Bestie":
			return "#C8FF3D"  # Electric Lime
		"Neutral":
			return "#FFE84D"  # Citrus Yellow
		_:
			return "#FFE84D"  # Default to Citrus Yellow for unknown statuses

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
	# Check for unstaged pending reassignments or common members
	if _pending_reassignments.size() > 0 or _common_members.size() > 0:
		return true

	# Also check if there's a locked plan in DormSystem (staged for Saturday)
	var ds: Node = _ds()
	if ds and ds.has_method("is_plan_locked"):
		if bool(ds.call("is_plan_locked")):
			return true

	return false

func _can_accept_plan() -> bool:
	# Can accept if all common room members have been assigned
	if _common_members.size() > 0:
		return false

	# Must have at least one pending reassignment
	if _pending_reassignments.size() == 0:
		return false

	return true

func _on_dorms_changed() -> void:
	print("[DormsPanel._on_dorms_changed] DormSystem signal received, rebuilding...")
	_rebuild()

func _on_panel_resized() -> void:
	"""Handle panel resize - update arrow positions"""
	print("[DEBUG Arrow] Panel resized - updating all arrow positions")
	print("[DEBUG Arrow] Panel size: %s" % size)
	call_deferred("_update_roster_arrow_position")
	call_deferred("_update_action_arrow_position")
	call_deferred("_update_room_arrow_position")

func _on_roster_list_resized() -> void:
	"""Handle roster list resize - update arrow position"""
	print("[DEBUG Arrow] Roster list resized - updating arrow position")
	print("[DEBUG Arrow] Roster list size: %s" % _roster_list.size)
	call_deferred("_update_roster_arrow_position")

# ═══════════════════════════════════════════════════════════════════════════
# POPUP HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _ask_confirm(msg: String) -> bool:
	print("[DormsPanel._ask_confirm] Showing confirmation: %s" % msg)

	# Create CanvasLayer overlay for popup (outside GameMenu hierarchy)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
	get_tree().root.add_child(overlay)

	var popup := ToastPopup.create(msg, "Confirm")
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(popup)

	# Wait for user response (true = Accept, false = Cancel/Back)
	var result: bool = await popup.confirmed

	print("[DormsPanel._ask_confirm] Result: %s" % result)
	popup.queue_free()
	overlay.queue_free()

	return result

func _show_toast(msg: String, title: String = "") -> void:
	print("[DormsPanel._show_toast] Showing toast: %s" % msg)

	# Create CanvasLayer overlay for popup (outside GameMenu hierarchy)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
	get_tree().root.add_child(overlay)

	var popup := ToastPopup.create(msg, title)
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(popup)

	# Wait for user to respond (accept or cancel)
	await popup.confirmed

	popup.queue_free()
	overlay.queue_free()
	print("[DormsPanel._show_toast] Toast closed")

func _join_psa(arr: PackedStringArray, sep: String) -> String:
	var out: String = ""
	for i in range(arr.size()):
		if i > 0:
			out += sep
		out += arr[i]
	return out
