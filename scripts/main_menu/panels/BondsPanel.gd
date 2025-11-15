## ═══════════════════════════════════════════════════════════════════════════
## BondsPanel - Circle Bond Management UI
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Main menu panel for viewing and managing social bonds with party members.
##   Displays bond levels, discovered likes/dislikes, rewards, and provides
##   access to bond story events.
##
## RESPONSIBILITIES:
##   • Bond list display (all characters or filtered)
##   • Bond level/layer visualization (Acquaintance → Core)
##   • Discovered likes/dislikes display
##   • Rewards preview (locked until bond level reached)
##   • Story event access button
##   • Filter system (All/Known/Locked/Maxed)
##   • Real-time updates when bonds change
##
## FILTER MODES:
##   • ALL - Show all characters
##   • KNOWN - Show only met/discovered characters
##   • LOCKED - Show only characters not yet at max bond
##   • MAXED - Show only characters at Core level (8)
##
## BOND DISPLAY:
##   Left Panel:
##   • List of characters (filtered)
##   • Current bond layer indicator
##   • Selection highlighting
##
##   Right Panel:
##   • Character name
##   • Current bond stage (Not Met, Acquaintance, Outer, Middle, Inner, Core)
##   • Discovered likes (topics/gifts they enjoy)
##   • Discovered dislikes (topics/gifts they dislike)
##   • Rewards preview (unlocks at specific bond levels)
##   • Story Events button (opens event overlay)
##
## CONNECTED SYSTEMS (Autoloads):
##   • CircleBondSystem - Bond data, BXP, likes/dislikes, events
##
## CSV DATA SOURCES:
##   • res://data/circles/circle_bonds.csv - Bond definitions (fallback)
##
## KEY METHODS:
##   • _rebuild() - Refresh entire bond list
##   • _on_bond_selected(bond_id) - Display bond details
##   • _on_filter_changed(index) - Apply filter to list
##   • _on_story_btn_pressed() - Open bond story event overlay
##
## ═══════════════════════════════════════════════════════════════════════════

extends PanelBase
class_name BondsPanel

const SYS_PATH : String = "/root/aCircleBondSystem"
const CSV_FALLBACK: String = "res://data/circles/circle_bonds.csv"

enum Filter { ALL, KNOWN, LOCKED, MAXED }

# Panel animation settings
const BASE_LEFT_RATIO := 2.0
const BASE_CENTER_RATIO := 3.5
const BASE_RIGHT_RATIO := 4.5
const ACTIVE_SCALE := 1.10  # Active panel grows by 10%
const INACTIVE_SCALE := 0.95  # Inactive panels shrink by 5%
const ANIM_DURATION := 0.2  # Animation duration in seconds

# Panel references (for animation)
@onready var _left_panel: PanelContainer = get_node("%Left") if has_node("%Left") else null
@onready var _right_panel: PanelContainer = get_node("%Right") if has_node("%Right") else null
@onready var _profile_panel: PanelContainer = get_node("%ProfilePanel") if has_node("%ProfilePanel") else null

# Controller navigation state machine
enum NavState { BOND_LIST, BOND_DETAIL }
var _nav_state: NavState = NavState.BOND_LIST
var _nav_index: int = 0  # Current selection index
var _nav_detail_elements: Array[Control] = []  # Detail buttons (Story Points, Layer transitions)
var _nav_detail_index: int = 0  # Current selection in detail view

# @onready var _filter    : OptionButton   = %Filter  # Removed
# @onready var _refresh   : Button         = %RefreshBtn  # Removed
@onready var _list      : ItemList       = %List
@onready var _bonds_label : Label = get_node_or_null("Row/Left/Margin/VBox/BondsLabel") as Label

# Selection arrow and dark box (matching LoadoutPanel/StatsPanel)
var _selection_arrow: Label = null
var _dark_box: PanelContainer = null

@onready var _name_tv   : Label          = %Name
@onready var _profile_desc : RichTextLabel = %Description

# Detail widgets (from TSCN)
@onready var _event_tv       : Label  = %EventValue
@onready var _layer_tv       : Label  = %LayerValue
@onready var _points_tv      : Label  = %PointsValue
@onready var _likes_tv       : Label  = %LikesValue
@onready var _dislikes_tv    : Label  = %DislikesValue
@onready var _unlock_hdr     : Label  = %UnlockHeader
@onready var _unlock_acq     : Button = %UnlockAcquaintance
@onready var _unlock_outer   : Button = %UnlockOuter
@onready var _unlock_middle  : Button = %UnlockMiddle
@onready var _unlock_inner   : Button = %UnlockInner
@onready var _story_btn      : Button = %StoryBtn

# Likes/Dislikes rows (containers with labels)
var _likes_row      : HBoxContainer = null
var _dislikes_row   : HBoxContainer = null

# Event/Layer/Points rows and labels
var _event_row      : HBoxContainer = null
var _event_label    : Label = null
var _layer_row      : HBoxContainer = null
var _layer_label    : Label = null
var _points_row     : HBoxContainer = null
var _points_label   : Label = null

# Old scene labels (may not exist - optional)
var _lvl_tv    : Label          = null
var _xp_tv     : Label          = null

var _story_overlay  : CanvasLayer    = null

# Data / state
var _sys  : Node = null
var _rows : Array[Dictionary] = []
var _selected : String = ""

func _ready() -> void:
	super()  # Call PanelBase._ready()

	_sys = get_node_or_null(SYS_PATH)

	# Optional old scene labels (may not exist)
	_lvl_tv = get_node_or_null("%LevelValue")
	_xp_tv = get_node_or_null("%CBXPValue")

	# Get likes/dislikes row containers
	if _likes_tv:
		_likes_row = _likes_tv.get_parent()
	if _dislikes_tv:
		_dislikes_row = _dislikes_tv.get_parent()

	# Get event/layer/points row containers and labels
	if _event_tv:
		_event_row = _event_tv.get_parent()
		_event_label = _event_row.get_node_or_null("EventLabel") if _event_row else null
	if _layer_tv:
		_layer_row = _layer_tv.get_parent()
		_layer_label = _layer_row.get_node_or_null("LayerLabel") if _layer_row else null
	if _points_tv:
		_points_row = _points_tv.get_parent()
		_points_label = _points_row.get_node_or_null("PointsLabel") if _points_row else null

	_hide_level_cbxp_labels()
	_wire_system_signals()
	_apply_core_vibe_styling()
	_create_selection_arrow()

	# Filter and refresh button removed - always show all bonds
	# if _filter != null and _filter.item_count == 0:
	#	_filter.add_item("All",    Filter.ALL)
	#	_filter.add_item("Known",  Filter.KNOWN)
	#	_filter.add_item("Locked", Filter.LOCKED)
	#	_filter.add_item("Maxed",  Filter.MAXED)
	# if _filter != null and not _filter.item_selected.is_connected(_on_filter_changed):
	#	_filter.item_selected.connect(_on_filter_changed)

	# if _refresh != null and not _refresh.pressed.is_connected(_rebuild):
	#	_refresh.pressed.connect(_rebuild)

	# Connect ItemList selection signal
	if _list and not _list.item_selected.is_connected(_on_list_item_selected):
		_list.item_selected.connect(_on_list_item_selected)

	# Connect to scroll changes to update arrow position when scrolling
	call_deferred("_connect_scroll_signals")

	if _story_btn != null and not _story_btn.pressed.is_connected(_on_story_points_pressed):
		_story_btn.pressed.connect(_on_story_points_pressed)

	# Connect unlock layer buttons to show rewards
	if _unlock_acq and not _unlock_acq.pressed.is_connected(_on_unlock_button_pressed):
		_unlock_acq.pressed.connect(_on_unlock_button_pressed.bind("acquaintance_to_outer"))
	if _unlock_outer and not _unlock_outer.pressed.is_connected(_on_unlock_button_pressed):
		_unlock_outer.pressed.connect(_on_unlock_button_pressed.bind("outer_to_middle"))
	if _unlock_middle and not _unlock_middle.pressed.is_connected(_on_unlock_button_pressed):
		_unlock_middle.pressed.connect(_on_unlock_button_pressed.bind("middle_to_inner"))
	if _unlock_inner and not _unlock_inner.pressed.is_connected(_on_unlock_button_pressed):
		_unlock_inner.pressed.connect(_on_unlock_button_pressed.bind("inner_to_core"))

	_rebuild()

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to BondsPanel elements"""

	# Style the three main panel containers with rounded neon borders
	if _left_panel:
		var left_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (bonds list)
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

	if _right_panel:
		var right_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_GRAPE_VIOLET,        # Grape Violet border (details)
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

	if _profile_panel:
		var profile_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (profile)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		profile_style.content_margin_left = 10
		profile_style.content_margin_top = 10
		profile_style.content_margin_right = 10
		profile_style.content_margin_bottom = 10
		_profile_panel.add_theme_stylebox_override("panel", profile_style)

	# Style bonds label (section header - Bubble Magenta like LoadoutPanel)
	if _bonds_label:
		aCoreVibeTheme.style_label(_bonds_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)

	# Style bonds list like LoadoutPanel's party list
	if _list:
		# Set colors - Sky Cyan for selection (matching LoadoutPanel)
		_list.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_list.add_theme_color_override("font_selected_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_list.add_theme_color_override("font_hovered_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		# Increase font size to 18 (matching LoadoutPanel)
		_list.add_theme_font_size_override("font_size", 18)
		# Set list text to layer 200 (above arrow and box at 100)
		_list.z_index = 200
		# Remove all borders and backgrounds by making them transparent
		var empty_stylebox = StyleBoxEmpty.new()
		_list.add_theme_stylebox_override("panel", empty_stylebox)
		_list.add_theme_stylebox_override("focus", empty_stylebox)
		_list.add_theme_stylebox_override("selected", empty_stylebox)
		_list.add_theme_stylebox_override("selected_focus", empty_stylebox)
		_list.add_theme_stylebox_override("cursor", empty_stylebox)
		_list.add_theme_stylebox_override("cursor_unfocused", empty_stylebox)

	# Style detail labels
	if _name_tv:
		aCoreVibeTheme.style_label(_name_tv, aCoreVibeTheme.COLOR_SKY_CYAN, 20)

	# Style Event label (Milk White) and value (Sky Cyan)
	if _event_label:
		_event_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_event_label.add_theme_font_size_override("font_size", 14)
	if _event_tv:
		_event_tv.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_event_tv.add_theme_font_size_override("font_size", 14)

	# Style Layer label (Milk White) and value (Sky Cyan)
	if _layer_label:
		_layer_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_layer_label.add_theme_font_size_override("font_size", 14)
	if _layer_tv:
		_layer_tv.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_layer_tv.add_theme_font_size_override("font_size", 14)

	# Style Points label (Milk White) and value (Sky Cyan)
	if _points_label:
		_points_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_points_label.add_theme_font_size_override("font_size", 14)
	if _points_tv:
		_points_tv.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_points_tv.add_theme_font_size_override("font_size", 14)

	# Style likes/dislikes values
	if _likes_tv:
		_likes_tv.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_PLASMA_TEAL)
		_likes_tv.add_theme_font_size_override("font_size", 14)

	if _dislikes_tv:
		_dislikes_tv.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
		_dislikes_tv.add_theme_font_size_override("font_size", 14)

	# Style unlock header
	if _unlock_hdr:
		aCoreVibeTheme.style_label(_unlock_hdr, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)

	# Style profile description
	if _profile_desc:
		_profile_desc.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_profile_desc.add_theme_font_size_override("normal_font_size", 14)

	# Style Story Points button with Bubble Magenta background and Night Navy text
	if _story_btn:
		var story_style_normal = StyleBoxFlat.new()
		story_style_normal.bg_color = aCoreVibeTheme.COLOR_BUBBLE_MAGENTA
		story_style_normal.corner_radius_top_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		story_style_normal.corner_radius_top_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		story_style_normal.corner_radius_bottom_left = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		story_style_normal.corner_radius_bottom_right = aCoreVibeTheme.CORNER_RADIUS_MEDIUM
		story_style_normal.content_margin_left = 12
		story_style_normal.content_margin_right = 12
		story_style_normal.content_margin_top = 8
		story_style_normal.content_margin_bottom = 8

		var story_style_hover = story_style_normal.duplicate()
		story_style_hover.bg_color = Color(aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.r * 1.2, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.g * 1.2, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.b * 1.2)

		var story_style_pressed = story_style_normal.duplicate()
		story_style_pressed.bg_color = Color(aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.r * 0.8, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.g * 0.8, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA.b * 0.8)

		_story_btn.add_theme_stylebox_override("normal", story_style_normal)
		_story_btn.add_theme_stylebox_override("hover", story_style_hover)
		_story_btn.add_theme_stylebox_override("pressed", story_style_pressed)
		_story_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # Remove grey focus box
		_story_btn.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_NIGHT_NAVY)
		_story_btn.add_theme_color_override("font_hover_color", aCoreVibeTheme.COLOR_NIGHT_NAVY)
		_story_btn.add_theme_color_override("font_pressed_color", aCoreVibeTheme.COLOR_NIGHT_NAVY)
		_story_btn.add_theme_font_size_override("font_size", 14)
		_story_btn.custom_minimum_size = Vector2(120, 40)

	# Note: Unlock buttons styling is dynamic based on unlock status, handled in _update_detail()

## PanelBase callback - Called when BondsPanel gains focus
func _on_panel_gained_focus() -> void:
	super()  # Call parent
	print("[BondsPanel] Panel gained focus - state: %s" % NavState.keys()[_nav_state])
	print("[BondsPanel] About to call _animate_panel_focus from gained_focus")

	# Restore focus based on current navigation state
	match _nav_state:
		NavState.BOND_LIST:
			call_deferred("_enter_bond_list_state")
		NavState.BOND_DETAIL:
			call_deferred("_enter_bond_detail_state")

## PanelBase callback - Called when BondsPanel loses focus
func _on_panel_lost_focus() -> void:
	super()  # Call parent
	print("[BondsPanel] Panel lost focus - state: %s" % NavState.keys()[_nav_state])

# ─────────────────────────────────────────────────────────────
# Input Handling - State Machine
# ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Only handle input if we're the active panel
	if not is_active():
		return

	# Block input if story overlay is open - but handle back button to close it
	if _story_overlay != null and is_instance_valid(_story_overlay):
		if event.is_action_pressed("menu_back"):
			_close_story_overlay()
			call_deferred("_enter_bond_detail_state")
			get_viewport().set_input_as_handled()
		else:
			# Block all other input when overlay is open
			get_viewport().set_input_as_handled()
		return

	# Route to appropriate handler based on state
	match _nav_state:
		NavState.BOND_LIST:
			_handle_bond_list_input(event)
		NavState.BOND_DETAIL:
			_handle_bond_detail_input(event)

## ─────────────────────── STATE 1: BOND_LIST ───────────────────────

func _handle_bond_list_input(event: InputEvent) -> void:
	"""Handle input when navigating bond list (vertical-only navigation)"""
	# Block left/right input completely (both pressed and released)
	if event.is_action("move_left") or event.is_action("move_right"):
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_up"):
		_navigate_bond_list(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_bond_list(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_select_current_bond()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		# Only mark as handled if we actually exited via PanelManager
		# Otherwise let it bubble to GameMenu
		if _exit_bonds_panel():
			get_viewport().set_input_as_handled()

func _navigate_bond_list(delta: int) -> void:
	"""Navigate up/down through bond list (wraps around cyclically)"""
	if not _list or _list.item_count == 0:
		return

	# Wrap around: pressing down at bottom goes to top, pressing up at top goes to bottom
	var size = _list.item_count
	var old_index = _nav_index
	_nav_index = (_nav_index + delta + size) % size

	# Debug wrapping behavior
	if (old_index == 0 and delta < 0) or (old_index == size - 1 and delta > 0):
		print("[BondsPanel] Wrapping: %d -> %d (size: %d)" % [old_index, _nav_index, size])

	_focus_bond_element(_nav_index)

	# Immediately show details for the newly focused bond
	if _nav_index >= 0 and _nav_index < _list.item_count:
		var id: String = String(_list.get_item_metadata(_nav_index))
		_selected = id
		_update_detail(id)

func _focus_bond_element(index: int) -> void:
	"""Focus the bond item at given index and ensure it's visible in the scroll area"""
	if not _list or index < 0 or index >= _list.item_count:
		print("[BondsPanel] _focus_bond_element: Invalid index %d (count: %d)" % [index, _list.item_count if _list else 0])
		return

	print("[BondsPanel] Focusing bond at index %d" % index)

	# Select the item
	_list.select(index)

	# Get scroll info before
	var scroll_before = 0.0
	if _list.get_v_scroll_bar():
		scroll_before = _list.get_v_scroll_bar().value

	# Ensure the selected item is scrolled into view
	# Using both methods for maximum compatibility
	_list.ensure_current_is_visible()

	# Get scroll info after
	var scroll_after = 0.0
	if _list.get_v_scroll_bar():
		scroll_after = _list.get_v_scroll_bar().value

	print("[BondsPanel] Scroll change: %.1f -> %.1f (delta: %.1f)" % [scroll_before, scroll_after, scroll_after - scroll_before])

	# Grab focus to enable keyboard/controller input
	_list.grab_focus()

	# Update arrow position to match new selection
	call_deferred("_update_arrow_position")

func _select_current_bond() -> void:
	"""Select the currently focused bond and transition to detail view"""
	if not _list or _nav_index < 0 or _nav_index >= _list.item_count:
		return

	var id: String = String(_list.get_item_metadata(_nav_index))
	# Prevent selecting unknown bonds
	if not _read_known(id):
		print("[BondsPanel] Cannot select unknown bond: %s" % id)
		return
	_selected = id
	_update_detail(id)
	_transition_to_bond_detail()

func _enter_bond_list_state() -> void:
	"""Enter BOND_LIST state and grab focus on bond list"""
	_nav_state = NavState.BOND_LIST
	if _list and _list.item_count > 0:
		# Clamp index to valid range to prevent out-of-bounds
		_nav_index = clamp(_nav_index, 0, _list.item_count - 1)
		# Focus and scroll to the current selection
		_focus_bond_element(_nav_index)
		print("[BondsPanel] Focused bond at index %d" % _nav_index)
	print("[BondsPanel] Entered BOND_LIST state")
	print("[BondsPanel] Calling _animate_panel_focus from enter_bond_list_state")
	call_deferred("_animate_panel_focus")


func _exit_bonds_panel() -> bool:
	"""Exit BondsPanel back to previous panel (StatusPanel)

	Returns: true if we popped from PanelManager, false if we let it bubble to GameMenu
	"""
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if not panel_mgr:
		print("[BondsPanel] No PanelManager - ignoring exit")
		return false

	# Check stack depth - if we're at depth 2 (StatusPanel + BondsPanel),
	# we're being managed by GameMenu and should NOT pop ourselves
	var stack_depth: int = panel_mgr.get_stack_depth()
	print("[BondsPanel] Back pressed - stack depth: %d, is_active: %s" % [stack_depth, is_active()])

	if stack_depth <= 2:
		print("[BondsPanel] Being managed by GameMenu - letting back button bubble up")
		# Don't handle the input - let it bubble up to GameMenu
		return false

	# We're deeper in the stack - pop ourselves
	print("[BondsPanel] Exiting to previous panel via PanelManager")
	panel_mgr.pop_panel()
	return true

## ─────────────────────── STATE 2: BOND_DETAIL ───────────────────────

func _handle_bond_detail_input(event: InputEvent) -> void:
	"""Handle input when viewing bond details (vertical-only navigation)"""
	# Block left/right input completely (both pressed and released)
	if event.is_action("move_left") or event.is_action("move_right"):
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("move_up"):
		_navigate_detail_buttons(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_navigate_detail_buttons(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_accept"):
		_activate_detail_button()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		_transition_to_bond_list()
		get_viewport().set_input_as_handled()

func _navigate_detail_buttons(delta: int) -> void:
	"""Navigate up/down through detail buttons (wraps around cyclically)"""
	if _nav_detail_elements.is_empty():
		return

	# Wrap around: pressing down at bottom goes to top, pressing up at top goes to bottom
	var size = _nav_detail_elements.size()
	_nav_detail_index = (_nav_detail_index + delta + size) % size
	_focus_detail_button(_nav_detail_index)

func _focus_detail_button(index: int) -> void:
	"""Focus the detail button at given index"""
	if index < 0 or index >= _nav_detail_elements.size():
		return

	var element = _nav_detail_elements[index]
	if is_instance_valid(element) and element is Control:
		element.grab_focus()
		print("[BondsPanel] Focused detail button: %s" % element.name)

func _activate_detail_button() -> void:
	"""Activate the currently focused detail button"""
	if _nav_detail_index < 0 or _nav_detail_index >= _nav_detail_elements.size():
		print("[BondsPanel] _activate_detail_button: index out of range")
		return

	var btn = _nav_detail_elements[_nav_detail_index]
	if is_instance_valid(btn) and btn is Button:
		print("[BondsPanel] Activating button: %s" % btn.name)
		print("[BondsPanel] Button has %d connections on 'pressed' signal" % (btn as Button).pressed.get_connections().size())
		btn.emit_signal("pressed")
	else:
		print("[BondsPanel] _activate_detail_button: button invalid or not a Button")

func _rebuild_detail_navigation() -> void:
	"""Build list of focusable detail buttons"""
	_nav_detail_elements.clear()

	# Add Story Points button if visible
	if _story_btn and _story_btn.visible and not _story_btn.disabled:
		_nav_detail_elements.append(_story_btn)

	# Add unlock layer buttons if visible and enabled
	if _unlock_acq and _unlock_acq.visible and not _unlock_acq.disabled:
		_nav_detail_elements.append(_unlock_acq)
	if _unlock_outer and _unlock_outer.visible and not _unlock_outer.disabled:
		_nav_detail_elements.append(_unlock_outer)
	if _unlock_middle and _unlock_middle.visible and not _unlock_middle.disabled:
		_nav_detail_elements.append(_unlock_middle)
	if _unlock_inner and _unlock_inner.visible and not _unlock_inner.disabled:
		_nav_detail_elements.append(_unlock_inner)

	print("[BondsPanel] Built detail navigation: %d buttons" % _nav_detail_elements.size())

	# Clamp index to valid range
	if _nav_detail_elements.size() > 0:
		_nav_detail_index = clamp(_nav_detail_index, 0, _nav_detail_elements.size() - 1)
	else:
		_nav_detail_index = 0

func _transition_to_bond_detail() -> void:
	"""Transition from BOND_LIST to BOND_DETAIL"""
	print("[BondsPanel] Transition: BOND_LIST → BOND_DETAIL")
	_nav_state = NavState.BOND_DETAIL
	_nav_detail_index = 0  # Start at first button
	print("[BondsPanel] Calling _animate_panel_focus from transition_to_bond_detail")
	call_deferred("_animate_panel_focus")
	call_deferred("_enter_bond_detail_state")

func _enter_bond_detail_state() -> void:
	"""Enter BOND_DETAIL state and focus first button"""
	_rebuild_detail_navigation()
	if _nav_detail_elements.size() > 0:
		_focus_detail_button(_nav_detail_index)
	print("[BondsPanel] Entered BOND_DETAIL state with %d buttons" % _nav_detail_elements.size())

func _transition_to_bond_list() -> void:
	"""Transition from BOND_DETAIL to BOND_LIST"""
	print("[BondsPanel] Transition: BOND_DETAIL → BOND_LIST")
	_nav_state = NavState.BOND_LIST
	call_deferred("_enter_bond_list_state")

func _animate_panel_focus() -> void:
	"""Animate panels to highlight which one is currently active"""
	print("[BondsPanel] _animate_panel_focus called, _nav_state: %s" % NavState.keys()[_nav_state])
	print("[BondsPanel] Panel refs - left: %s, right: %s, profile: %s" % [_left_panel != null, _right_panel != null, _profile_panel != null])

	if not _left_panel or not _right_panel or not _profile_panel:
		print("[BondsPanel] ERROR: Missing panel references!")
		return

	var left_ratio := BASE_LEFT_RATIO
	var center_ratio := BASE_CENTER_RATIO
	var right_ratio := BASE_RIGHT_RATIO  # Profile panel always stays at base size

	# Determine which panel gets the active scale (only left and center panels animate)
	match _nav_state:
		NavState.BOND_LIST:
			left_ratio = BASE_LEFT_RATIO * ACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * INACTIVE_SCALE
			# right_ratio stays at BASE_RIGHT_RATIO
		NavState.BOND_DETAIL:
			left_ratio = BASE_LEFT_RATIO * INACTIVE_SCALE
			center_ratio = BASE_CENTER_RATIO * ACTIVE_SCALE
			# right_ratio stays at BASE_RIGHT_RATIO

	print("[BondsPanel] Animation ratios - left: %.2f, center: %.2f, right: %.2f" % [left_ratio, center_ratio, right_ratio])

	# Create tweens for smooth animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(_left_panel, "size_flags_stretch_ratio", left_ratio, ANIM_DURATION)
	tween.tween_property(_right_panel, "size_flags_stretch_ratio", center_ratio, ANIM_DURATION)
	tween.tween_property(_profile_panel, "size_flags_stretch_ratio", right_ratio, ANIM_DURATION)

	print("[BondsPanel] Tween created and started")

# ─────────────────────────────────────────────────────────────
# Scene fixes
# ─────────────────────────────────────────────────────────────

func _hide_level_cbxp_labels() -> void:
	if _lvl_tv:
		_lvl_tv.visible = false
	if _xp_tv:
		_xp_tv.visible  = false
	# Hide any stray "Level/CBXP/BXP" labels nearby.
	for n in get_children():
		if n is Label:
			var t: String = (n as Label).text.strip_edges().to_lower()
			if t.begins_with("level") or t.begins_with("cbxp") or t.begins_with("bxp"):
				(n as Label).visible = false

# ─────────────────────────────────────────────────────────────
# System wiring
# ─────────────────────────────────────────────────────────────

func _wire_system_signals() -> void:
	if _sys == null:
		return
	if _sys.has_signal("data_reloaded") and not _sys.is_connected("data_reloaded", Callable(self, "_rebuild")):
		_sys.connect("data_reloaded", Callable(self, "_rebuild"))
	if _sys.has_signal("bxp_changed") and not _sys.is_connected("bxp_changed", Callable(self, "_on_progress_changed")):
		_sys.connect("bxp_changed", Callable(self, "_on_progress_changed"))
	if _sys.has_signal("level_changed") and not _sys.is_connected("level_changed", Callable(self, "_on_progress_changed")):
		_sys.connect("level_changed", Callable(self, "_on_progress_changed"))
	if _sys.has_signal("known_changed") and not _sys.is_connected("known_changed", Callable(self, "_on_progress_changed")):
		_sys.connect("known_changed", Callable(self, "_on_progress_changed"))

func _on_progress_changed(_id: String, _val: Variant = null) -> void:
	var keep: String = _selected
	_rebuild()
	if keep != "":
		_update_detail(keep)

# ─────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────

func _rebuild() -> void:
	_rows = _read_defs()
	_build_list()
	_update_detail(_selected)  # keep detail synced if selection still exists
	call_deferred("_update_arrow_position")  # Update arrow after list rebuild

func _build_list() -> void:
	_list.clear()

	var f: int = _get_filter_id()

	# Build list of bonds with their data for sorting
	var bond_list: Array[Dictionary] = []

	for rec: Dictionary in _rows:
		var id: String = String(rec.get("id", ""))
		var disp_name: String = String(rec.get("name", id))

		var lv: int = _read_layer(id)
		var _xp: int = _read_bxp(id)  # kept for future tooltip tuning
		var known: bool = _read_known(id)
		var maxed: bool = _is_maxed(id, lv)

		if f == Filter.KNOWN and not known:    continue
		if f == Filter.LOCKED and known:       continue
		if f == Filter.MAXED and not maxed:    continue

		bond_list.append({
			"id": id,
			"disp_name": disp_name,
			"known": known,
			"maxed": maxed
		})

	# Sort: known bonds first, then unknown bonds
	bond_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_known: bool = bool(a.get("known", false))
		var b_known: bool = bool(b.get("known", false))

		# Known bonds come before unknown
		if a_known != b_known:
			return a_known

		# Within same group, sort alphabetically by display name
		var a_name: String = String(a.get("disp_name", ""))
		var b_name: String = String(b.get("disp_name", ""))
		return a_name < b_name
	)

	# Create ItemList entries from sorted list
	var selected_index: int = -1
	for i in range(bond_list.size()):
		var bond_data: Dictionary = bond_list[i]
		var id: String = String(bond_data.get("id", ""))
		var disp_name: String = String(bond_data.get("disp_name", ""))
		var known: bool = bool(bond_data.get("known", false))
		var maxed: bool = bool(bond_data.get("maxed", false))

		# Show "(Unknown)" for locked bonds instead of actual name
		var display_text: String = "(Unknown)" if not known else disp_name
		_list.add_item(display_text)
		_list.set_item_metadata(i, id)

		if not known:
			# Core Vibe: Dimmed grey for unknown bonds (stays grey when highlighted)
			_list.set_item_custom_fg_color(i, Color(0.5, 0.5, 0.5, 0.6))
			_list.set_item_tooltip(i, "Unknown")
		elif maxed:
			# Core Vibe: Electric Lime for maxed bonds
			_list.set_item_custom_fg_color(i, aCoreVibeTheme.COLOR_ELECTRIC_LIME)
			_list.set_item_tooltip(i, "Maxed")
		else:
			# Core Vibe: Milk White for known, non-maxed bonds
			_list.set_item_custom_fg_color(i, aCoreVibeTheme.COLOR_MILK_WHITE)
			_list.set_item_tooltip(i, disp_name)

		# Track selected index
		if _selected != "" and _selected == id:
			selected_index = i

	# Restore selection if we found the selected bond
	if selected_index >= 0:
		_nav_index = selected_index
		# Use _focus_bond_element to ensure item is visible in scroll area
		# But don't grab focus if we're not currently active
		_list.select(selected_index)
		_list.ensure_current_is_visible()
		call_deferred("_update_arrow_position")
	elif _list.item_count > 0:
		# No previous selection or it's gone - select first item
		_nav_index = 0
		_list.select(0)
		_list.ensure_current_is_visible()
		call_deferred("_update_arrow_position")

# ─────────────────────────────────────────────────────────────
# Reads / fallbacks
# ─────────────────────────────────────────────────────────────

func _read_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if _sys != null:
		if _sys.has_method("get_defs"):
			var d_v: Variant = _sys.call("get_defs")
			if typeof(d_v) == TYPE_DICTIONARY:
				var defs: Dictionary = d_v
				for k in defs.keys():
					var id: String = String(k)
					var rec: Dictionary = defs[k]
					var nm: String = String(rec.get("bond_name", id))
					out.append({"id": id, "name": nm})
				if out.size() > 0:
					return out
		if _sys.has_method("get_ids"):
			var ids_v: Variant = _sys.call("get_ids")
			if typeof(ids_v) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
				var ids: Array = (ids_v as Array)
				for i in ids:
					var id2: String = String(i)
					var nm2: String = (String(_sys.call("get_bond_name", id2)) if _sys.has_method("get_bond_name") else String(_sys.call("get_display_name", id2)))
					out.append({"id": id2, "name": nm2})
				if out.size() > 0:
					return out

	var csv_rows: Array[Dictionary] = _read_csv_rows(CSV_FALLBACK)
	for r in csv_rows:
		var rec: Dictionary = r
		var id3: String = String(rec.get("actor_id","")).strip_edges()
		if id3 == "":
			continue
		var nm3: String = String(rec.get("bond_name", id3))
		out.append({"id": id3, "name": nm3})

	if out.is_empty():
		for i in range(6):
			out.append({"id": "bond_%d" % i, "name": "Unknown %d" % (i + 1)})

	return out

func _read_csv_rows(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header: PackedStringArray = []
	if not f.eof_reached():
		header = f.get_csv_line()
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() == 0:
			continue
		var d: Dictionary = {}
		for i in range(min(header.size(), row.size())):
			d[header[i].strip_edges()] = row[i]
		out.append(d)
	f.close()
	return out

## Read event index (0-9)
func _read_event_index(id: String) -> int:
	if _sys == null:
		return 0
	if _sys.has_method("get_event_index"):
		return int(_sys.call("get_event_index", id))
	return 0

## Read points bank
func _read_points_bank(id: String) -> int:
	if _sys == null:
		return 0
	if _sys.has_method("get_points_bank"):
		return int(_sys.call("get_points_bank", id))
	# Backward compatibility
	if _sys.has_method("get_bxp"):
		return int(_sys.call("get_bxp", id))
	return 0

## Read next threshold
func _read_next_threshold(id: String) -> int:
	if _sys == null:
		return 0
	if _sys.has_method("get_next_threshold"):
		return int(_sys.call("get_next_threshold", id))
	return 0

## Read layer name
func _read_layer_name(id: String) -> String:
	if _sys == null:
		return "None"
	if _sys.has_method("get_layer_name"):
		return String(_sys.call("get_layer_name", id))
	return "None"

## Read gift used status
func _read_gift_used(id: String) -> bool:
	if _sys == null:
		return false
	if _sys.has_method("is_gift_used_in_layer"):
		return bool(_sys.call("is_gift_used_in_layer", id))
	return false

func _read_layer(id: String) -> int:
	if _sys == null:
		return 0
	if _sys.has_method("get_layer"):
		return int(_sys.call("get_layer", id))
	if _sys.has_method("get_level"): # alias
		return int(_sys.call("get_level", id))
	return 0

func _read_bxp(id: String) -> int:
	# Backward compatibility - now reads points bank
	return _read_points_bank(id)

func _read_known(id: String) -> bool:
	if _sys == null:
		return false
	if _sys.has_method("is_known"):
		return bool(_sys.call("is_known", id))
	return _read_layer(id) > 0 or _read_bxp(id) > 0

func _is_maxed(_id: String, layer_val: int) -> bool:
	var max_lv: int = 10
	if _sys and _sys.has_method("get_max_level"):
		max_lv = int(_sys.call("get_max_level"))
	elif _sys and _sys.has_method("get_max_layer"):
		max_lv = int(_sys.call("get_max_layer"))
	return layer_val >= max_lv

# ─────────────────────────────────────────────────────────────
# Detail
# ─────────────────────────────────────────────────────────────

func _on_filter_changed(_idx: int) -> void:
	_build_list()
	# Reset to BOND_LIST state when filter changes
	_nav_state = NavState.BOND_LIST
	_nav_index = 0

func _on_list_item_selected(index: int) -> void:
	"""Handle ItemList item selection"""
	if not _list or index < 0 or index >= _list.item_count:
		return

	var id: String = String(_list.get_item_metadata(index))
	# Prevent selecting unknown bonds
	if not _read_known(id):
		print("[BondsPanel] Cannot select unknown bond: %s" % id)
		# Deselect the item since we're rejecting the selection
		_list.deselect(index)
		return

	_nav_index = index
	_selected = id
	_update_detail(_selected)
	# Transition to detail state (works for both mouse and controller)
	_transition_to_bond_detail()

func _update_detail(id: String) -> void:
	# Handle empty selection
	if id == "":
		_name_tv.text = "—"
		if _event_tv: _event_tv.text = "—"
		if _layer_tv: _layer_tv.text = "—"
		if _points_tv: _points_tv.text = "—"
		if _profile_desc: _profile_desc.text = "[i]Have not met them.[/i]"
		if _likes_tv: _likes_tv.text = "—"
		if _dislikes_tv: _dislikes_tv.text = "—"
		if _unlock_acq: _unlock_acq.disabled = true
		if _unlock_outer: _unlock_outer.disabled = true
		if _unlock_middle: _unlock_middle.disabled = true
		if _unlock_inner: _unlock_inner.disabled = true
		if _story_btn: _story_btn.set_meta("bond_id", "")
		# Show all widgets
		_show_all_detail_widgets()
		return

	# Check if bond is known
	var known: bool = _read_known(id)

	# If unknown, hide all detail widgets
	if not known:
		# Hide all detail widgets
		_hide_all_detail_widgets()

		# Update profile description for unknown character
		if _profile_desc:
			_profile_desc.text = "[i]Have not met them.[/i]"
		return

	# Known bond - show all widgets and populate with data
	_show_all_detail_widgets()

	_name_tv.text = _display_name(id)

	# Get event-based progression data
	var event_idx: int = _read_event_index(id)
	var points: int = _read_points_bank(id)
	var threshold: int = _read_next_threshold(id)
	var layer_name: String = _read_layer_name(id)
	var gift_used: bool = _read_gift_used(id)

	# Event progress (value only, label is separate)
	if _event_tv:
		if event_idx == 0:
			_event_tv.text = "Not Started"
		else:
			_event_tv.text = "E%d Complete" % event_idx

	# Layer stage (value only, label is separate)
	if _layer_tv:
		_layer_tv.text = "%s" % layer_name

	# Points bank / threshold (value only, label is separate)
	if _points_tv:
		if event_idx == 0:
			_points_tv.text = "—"
		elif threshold > 0:
			_points_tv.text = "%d / %d" % [points, threshold]
		else:
			_points_tv.text = "%d (Max)" % points

	# Profile description (same as bond description for known characters)
	var rec: Dictionary = _bond_def(id)
	if _profile_desc:
		var profile_desc: String = String(rec.get("bond_description", "")).strip_edges()
		if profile_desc != "":
			_profile_desc.text = profile_desc
		else:
			_profile_desc.text = "[i]No description available.[/i]"

	# Likes/Dislikes (only discovered, never show full list)
	var likes: PackedStringArray = _read_discovered_or_full(id, true)
	var dislikes: PackedStringArray = _read_discovered_or_full(id, false)
	if _likes_tv: _likes_tv.text = _pretty_list(likes)
	if _dislikes_tv: _dislikes_tv.text = _pretty_list(dislikes)

	# Unlock buttons - show layer transitions (based on event completions)
	# With new per-event threshold system (10+10+12+12+14+14+16+16 = 104 total):
	# - E3 complete → Outer layer unlocked (paid 10+10 thresholds)
	# - E5 complete → Middle layer unlocked (paid 10+10+12+12 thresholds)
	# - E7 complete → Inner layer unlocked (paid 10+10+12+12+14+14 thresholds)
	# - E9 complete → Core layer unlocked (paid all 104 pts thresholds)

	var outer_unlocked: bool = event_idx >= 3   # E3 complete → transitioned to Outer
	var middle_unlocked: bool = event_idx >= 5  # E5 complete → transitioned to Middle
	var inner_unlocked: bool = event_idx >= 7   # E7 complete → transitioned to Inner
	var core_unlocked: bool = event_idx >= 9    # E9 complete → transitioned to Core

	# Core Vibe: Style unlock buttons based on status
	if _unlock_acq:
		_unlock_acq.disabled = not outer_unlocked
		_unlock_acq.text = "Acquaintance → Outer" + (" [UNLOCKED]" if outer_unlocked else " [LOCKED]")
		var color = aCoreVibeTheme.COLOR_ELECTRIC_LIME if outer_unlocked else aCoreVibeTheme.COLOR_CITRUS_YELLOW
		aCoreVibeTheme.style_button(_unlock_acq, color, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_unlock_acq.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # Remove grey focus box
		_unlock_acq.custom_minimum_size = Vector2(180, 36)

	if _unlock_outer:
		_unlock_outer.disabled = not middle_unlocked
		_unlock_outer.text = "Outer → Middle" + (" [UNLOCKED]" if middle_unlocked else " [LOCKED]")
		var color = aCoreVibeTheme.COLOR_ELECTRIC_LIME if middle_unlocked else aCoreVibeTheme.COLOR_CITRUS_YELLOW
		aCoreVibeTheme.style_button(_unlock_outer, color, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_unlock_outer.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # Remove grey focus box
		_unlock_outer.custom_minimum_size = Vector2(180, 36)

	if _unlock_middle:
		_unlock_middle.disabled = not inner_unlocked
		_unlock_middle.text = "Middle → Inner" + (" [UNLOCKED]" if inner_unlocked else " [LOCKED]")
		var color = aCoreVibeTheme.COLOR_ELECTRIC_LIME if inner_unlocked else aCoreVibeTheme.COLOR_CITRUS_YELLOW
		aCoreVibeTheme.style_button(_unlock_middle, color, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_unlock_middle.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # Remove grey focus box
		_unlock_middle.custom_minimum_size = Vector2(180, 36)

	if _unlock_inner:
		_unlock_inner.disabled = not core_unlocked
		_unlock_inner.text = "Inner → Core" + (" [UNLOCKED]" if core_unlocked else " [LOCKED]")
		var color = aCoreVibeTheme.COLOR_ELECTRIC_LIME if core_unlocked else aCoreVibeTheme.COLOR_CITRUS_YELLOW
		aCoreVibeTheme.style_button(_unlock_inner, color, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_unlock_inner.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # Remove grey focus box
		_unlock_inner.custom_minimum_size = Vector2(180, 36)

	# Story points
	if _story_btn:
		_story_btn.set_meta("bond_id", id)

func _hide_all_detail_widgets() -> void:
	if _name_tv: _name_tv.visible = false
	# Hide the entire event/layer/points rows (includes labels and values)
	if _event_row: _event_row.visible = false
	if _layer_row: _layer_row.visible = false
	if _points_row: _points_row.visible = false
	# Hide the entire likes/dislikes rows (includes labels and values)
	if _likes_row: _likes_row.visible = false
	if _dislikes_row: _dislikes_row.visible = false
	if _unlock_hdr: _unlock_hdr.visible = false
	if _unlock_acq: _unlock_acq.visible = false
	if _unlock_outer: _unlock_outer.visible = false
	if _unlock_middle: _unlock_middle.visible = false
	if _unlock_inner: _unlock_inner.visible = false
	if _story_btn: _story_btn.visible = false
	# Notes/description removed from Details panel

func _show_all_detail_widgets() -> void:
	if _name_tv: _name_tv.visible = true
	# Show the entire event/layer/points rows (includes labels and values)
	if _event_row: _event_row.visible = true
	if _layer_row: _layer_row.visible = true
	if _points_row: _points_row.visible = true
	# Show the entire likes/dislikes rows (includes labels and values)
	if _likes_row: _likes_row.visible = true
	if _dislikes_row: _dislikes_row.visible = true
	if _unlock_hdr: _unlock_hdr.visible = true
	if _unlock_acq: _unlock_acq.visible = true
	if _unlock_outer: _unlock_outer.visible = true
	if _unlock_middle: _unlock_middle.visible = true
	if _unlock_inner: _unlock_inner.visible = true
	if _story_btn: _story_btn.visible = true
	# Notes/description removed from Details panel

func _display_name(id: String) -> String:
	if _sys and _sys.has_method("get_bond_name"):
		return String(_sys.call("get_bond_name", id))
	if _sys and _sys.has_method("get_display_name"):
		return String(_sys.call("get_display_name", id))
	var rec: Dictionary = _bond_def(id)
	var nm: String = String(rec.get("bond_name", ""))
	return (nm if nm != "" else id.capitalize())

func _bond_def(id: String) -> Dictionary:
	var result: Dictionary = {}

	# Try system first
	if _sys and _sys.has_method("get_bond_def"):
		var v: Variant = _sys.call("get_bond_def", id)
		if typeof(v) == TYPE_DICTIONARY:
			result = (v as Dictionary).duplicate()

	# Always check CSV to get bond_hint (and other new fields)
	var rows: Array[Dictionary] = _read_csv_rows(CSV_FALLBACK)
	for r in rows:
		var rec: Dictionary = r
		if String(rec.get("actor_id","")) == id:
			# Merge CSV data into result, CSV takes priority for new fields
			for key in rec.keys():
				if not result.has(key) or key == "bond_hint":
					result[key] = rec[key]
			return result

	return result if not result.is_empty() else {}

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

func _to_psa_local(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	match typeof(v):
		TYPE_PACKED_STRING_ARRAY:
			return v
		TYPE_ARRAY:
			for e in (v as Array):
				out.append(String(e))
		_:
			var s := String(v).strip_edges()
			if s != "":
				for seg in s.split(";", false):
					var t := String(seg).strip_edges()
					if t != "":
						out.append(t)
	return out

func _read_discovered_or_full(id: String, likes: bool) -> PackedStringArray:
	# Only return discovered preferences - do NOT fall back to full list
	# Likes/dislikes remain hidden until discovered through item interaction
	if _sys == null:
		return PackedStringArray()
	var discovered: PackedStringArray = PackedStringArray()
	if likes:
		if _sys.has_method("get_discovered_likes"):
			discovered = _to_psa_local(_sys.call("get_discovered_likes", id))
	else:
		if _sys.has_method("get_discovered_dislikes"):
			discovered = _to_psa_local(_sys.call("get_discovered_dislikes", id))
	return discovered

func _pretty_list(arr: PackedStringArray) -> String:
	if arr.size() == 0:
		return "—"
	var txt := ""
	for i in range(arr.size()):
		if i > 0:
			txt += ", "
		txt += arr[i]
	return txt

func _get_filter_id() -> int:
	# Always show all bonds (filter removed)
	return Filter.ALL
	# if _filter == null:
	#	return Filter.ALL
	# return int(_filter.get_selected_id())

# ─────────────────────────────────────────────────────────────
# Layer Unlock Rewards
# ─────────────────────────────────────────────────────────────

func _on_unlock_button_pressed(transition_id: String) -> void:
	"""Show reward information for a layer transition"""
	if _selected == "":
		return

	var reward_text: String = _get_layer_reward_text(transition_id)
	var title_text: String = _get_layer_transition_title(transition_id)

	_show_info_popup(title_text, reward_text)

func _get_layer_transition_title(transition_id: String) -> String:
	"""Get display title for layer transition"""
	match transition_id:
		"acquaintance_to_outer":
			return "Acquaintance → Outer Reward"
		"outer_to_middle":
			return "Outer → Middle Reward"
		"middle_to_inner":
			return "Middle → Inner Reward"
		"inner_to_core":
			return "Inner → Core Reward"
		_:
			return "Layer Reward"

func _get_layer_reward_text(transition_id: String) -> String:
	"""Get reward information for a layer transition from the bond system"""
	if _sys == null or _selected == "":
		return "No reward information available."

	# Try to get reward from system
	if _sys.has_method("get_layer_reward"):
		var reward = _sys.call("get_layer_reward", _selected, transition_id)
		if reward != null and String(reward).strip_edges() != "":
			return String(reward)

	# Try to get from bond definition
	var rec: Dictionary = _bond_def(_selected)
	var reward_key: String = "reward_" + transition_id
	if rec.has(reward_key):
		return String(rec[reward_key])

	# Fallback placeholder text
	match transition_id:
		"acquaintance_to_outer":
			return "Unlocks deeper conversation topics and gift preferences."
		"outer_to_middle":
			return "Unlocks personal quests and special dialogue options."
		"middle_to_inner":
			return "Unlocks character-specific abilities and team bonuses."
		"inner_to_core":
			return "Unlocks ultimate bond ability and secret ending content."
		_:
			return "Layer transition reward."

func _show_info_popup(title: String, message: String) -> void:
	"""Show a simple info popup using ToastPopup"""
	print("[BondsPanel] Showing info popup: %s" % title)

	# Create and show ToastPopup (auto-centers, auto-styles, auto-blocks input)
	var popup := ToastPopup.create(message, title)
	add_child(popup)

	# Wait for user to dismiss
	await popup.confirmed

	# Clean up
	popup.queue_free()
	print("[BondsPanel] Info popup closed")

# ─────────────────────────────────────────────────────────────
# Story Points overlay (full-screen, more opaque, Back)
# ─────────────────────────────────────────────────────────────

func _on_story_points_pressed() -> void:
	if _selected == "":
		return

	# Pull points safely
	var points: PackedStringArray = PackedStringArray()
	if _sys != null and _sys.has_method("get_story_points"):
		points = _to_psa_local(_sys.call("get_story_points", _selected))

	# Find display name for title
	var disp: String = _display_name(_selected)

	# Clear any prior overlay
	_close_story_overlay()

	# Use CanvasLayer to ensure overlay renders on top of everything
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "StoryOverlayLayer"
	canvas_layer.layer = 100  # Very high layer to be on top
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	# Full-screen overlay to center the panel
	var overlay := Control.new()
	overlay.name = "StoryOverlay"
	overlay.visible = true
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS

	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	# Toast-style panel (centered)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(600, 500)
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -300  # Half of width
	panel.offset_top = -250   # Half of height
	panel.offset_right = 300
	panel.offset_bottom = 250
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.process_mode = Node.PROCESS_MODE_ALWAYS

	# Core Vibe: Story overlay panel styling
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (story content)
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	panel.add_theme_stylebox_override("panel", style)

	overlay.add_child(panel)

	# Margin container for padding
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Core Vibe: Story overlay title
	var title := Label.new()
	title.text = "%s — Story Points" % disp
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aCoreVibeTheme.style_label(title, aCoreVibeTheme.COLOR_SKY_CYAN, 20)
	vbox.add_child(title)

	# Scrollable body
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(560, 0)
	scroll.add_child(body)

	# Core Vibe: Fill with bullets (or placeholder)
	if points.is_empty():
		var none := Label.new()
		none.text = "No story points logged yet."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		none.add_theme_font_size_override("font_size", 14)
		body.add_child(none)
	else:
		for p_str in points:
			var row := Label.new()
			row.text = "• " + p_str
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
			row.add_theme_font_size_override("font_size", 14)
			body.add_child(row)

	# Buttons
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)

	# Core Vibe: Close button with Bubble Magenta styling
	var back_btn := Button.new()
	back_btn.text = "Close"
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.custom_minimum_size = Vector2(120, 44)
	back_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	aCoreVibeTheme.style_button(back_btn, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_LARGE)
	back_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())  # Remove grey focus box
	back_btn.pressed.connect(func() -> void:
		_close_story_overlay()
		# Restore focus to detail view after closing overlay
		call_deferred("_enter_bond_detail_state")
	)
	hbox.add_child(back_btn)

	# Add overlay to canvas layer
	canvas_layer.add_child(overlay)

	# Add canvas layer to the scene tree
	get_tree().root.add_child(canvas_layer)
	_story_overlay = canvas_layer  # Store canvas_layer reference so we can clean it up
	back_btn.grab_focus()

func _close_story_overlay() -> void:
	if _story_overlay != null and is_instance_valid(_story_overlay):
		_story_overlay.queue_free()
	_story_overlay = null

# ─────────────────────────────────────────────────────────────
# Selection Arrow & Dark Box (matching LoadoutPanel)
# ─────────────────────────────────────────────────────────────

func _connect_scroll_signals() -> void:
	"""Connect to the ItemList's scrollbar to update arrow on scroll"""
	if not _list:
		return

	# Wait for the scroll bar to be ready
	await get_tree().process_frame

	var vscroll = _list.get_v_scroll_bar()
	if vscroll and not vscroll.value_changed.is_connected(_on_list_scrolled):
		vscroll.value_changed.connect(_on_list_scrolled)
		print("[BondsPanel] Connected to scroll bar value_changed signal")

func _on_list_scrolled(_value: float) -> void:
	"""Called when the list is scrolled - update arrow position"""
	print("[BondsPanel] List scrolled to: %.1f" % _value)
	call_deferred("_update_arrow_position")

func _create_selection_arrow() -> void:
	"""Create the selection arrow indicator and dark box for bonds list (matching LoadoutPanel)"""
	if not _list:
		return

	# Create arrow label
	_selection_arrow = Label.new()
	_selection_arrow.text = "◄"  # Left-pointing arrow
	_selection_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selection_arrow.add_theme_font_size_override("font_size", 43)
	_selection_arrow.modulate = Color(1, 1, 1, 1)  # White
	_selection_arrow.custom_minimum_size = Vector2(54, 72)
	_selection_arrow.size = Vector2(54, 72)
	_selection_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_arrow.z_index = 100  # Well above other elements

	# Add to main BondsPanel (not the ItemList or PanelContainer)
	add_child(_selection_arrow)

	# Ensure size is locked after adding to tree
	await get_tree().process_frame
	_selection_arrow.size = Vector2(54, 72)

	# Create dark box (160px wide, 20px height - matching LoadoutPanel)
	_dark_box = PanelContainer.new()
	_dark_box.custom_minimum_size = Vector2(160, 20)
	_dark_box.size = Vector2(160, 20)
	_dark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark_box.z_index = 99  # Behind arrow (arrow is at 100)

	# Create Ink Charcoal rounded style
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL  # Ink Charcoal
	box_style.corner_radius_top_left = 8
	box_style.corner_radius_top_right = 8
	box_style.corner_radius_bottom_left = 8
	box_style.corner_radius_bottom_right = 8
	_dark_box.add_theme_stylebox_override("panel", box_style)

	add_child(_dark_box)
	await get_tree().process_frame
	_dark_box.size = Vector2(160, 20)

	# Start pulsing animation
	_start_arrow_pulse()

func _update_arrow_position() -> void:
	"""Update arrow and dark box position to align with selected item"""
	if not _selection_arrow or not _list:
		print("[BondsPanel] _update_arrow_position: Missing arrow or list")
		return

	var selected = _list.get_selected_items()
	if selected.size() == 0:
		print("[BondsPanel] _update_arrow_position: No selection, hiding arrow")
		_selection_arrow.visible = false
		if _dark_box:
			_dark_box.visible = false
		return

	_selection_arrow.visible = true

	# Wait for layout to complete
	await get_tree().process_frame

	# Get the rect of the selected item in ItemList's local coordinates
	var item_index = selected[0]
	var item_rect = _list.get_item_rect(item_index)

	# Convert to BondsPanel coordinates
	var list_global_pos = _list.global_position
	var panel_global_pos = global_position
	var list_offset_in_panel = list_global_pos - panel_global_pos

	# Get scroll offset - item_rect is in content space, we need to adjust for scroll
	var scroll_offset = 0.0
	if _list.get_v_scroll_bar():
		var vscroll = _list.get_v_scroll_bar()
		scroll_offset = vscroll.value
		print("[BondsPanel] Arrow Update - Index: %d, Scroll: %.1f, ItemRect: %s" % [item_index, scroll_offset, item_rect])

	# Position arrow to the right of the bonds list
	var arrow_x = list_offset_in_panel.x + _list.size.x - 8.0 - 80.0 + 40.0
	# Subtract scroll offset to position arrow correctly in viewport space
	var arrow_y = list_offset_in_panel.y + item_rect.position.y - scroll_offset + (item_rect.size.y / 2.0) - (_selection_arrow.size.y / 2.0)

	print("[BondsPanel] Arrow Position - X: %.1f, Y: %.1f (item_y: %.1f, scroll: %.1f, adjusted_y: %.1f)" % [arrow_x, arrow_y, item_rect.position.y, scroll_offset, item_rect.position.y - scroll_offset])

	_selection_arrow.position = Vector2(arrow_x, arrow_y)

	# Position dark box to the left of arrow
	if _dark_box:
		_dark_box.visible = true
		var box_x = arrow_x - _dark_box.size.x - 4.0  # 4px gap to the left of arrow
		var box_y = arrow_y + (_selection_arrow.size.y / 2.0) - (_dark_box.size.y / 2.0)  # Center vertically with arrow
		_dark_box.position = Vector2(box_x, box_y)
		print("[BondsPanel] Dark Box Position - X: %.1f, Y: %.1f" % [box_x, box_y])

func _start_arrow_pulse() -> void:
	"""Start pulsing animation for the arrow"""
	if not _selection_arrow:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse left 6 pixels then back
	var base_x = _selection_arrow.position.x
	tween.tween_property(_selection_arrow, "position:x", base_x - 6, 0.6)
	tween.tween_property(_selection_arrow, "position:x", base_x, 0.6)
