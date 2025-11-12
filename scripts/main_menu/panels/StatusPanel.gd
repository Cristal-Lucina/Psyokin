## ============================================================================
## StatusPanel - Party Status & Appearance Display
## ============================================================================
##
## PURPOSE:
##   Main menu panel displaying party member HP/MP status, general game info
##   (CREDS, perk points, date/time), and character appearance customization.
##   Includes party management with Leader/Active/Bench sections and member swapping.
##
## RESPONSIBILITIES:
##   • Party member HP/MP display (with max values)
##   • Party member level and appearance preview
##   • Party management (Leader + 2 Active + 5 Bench = 8 total slots)
##   • Active member swapping with bench via switch buttons
##   • Money and perk points display
##   • Current date/time display
##   • Hint/flavor text display
##   • Character appearance editor (skin, brow, eye, hair colors)
##   • Real-time status updates from combat/progression
##
## DISPLAY SECTIONS:
##   Left Panel (Party Management):
##   • LEADER section: Hero (fixed, cannot be swapped)
##   • ACTIVE section: 2 active party slots with "Switch" buttons
##   • BENCH section: 5 bench slots for reserve members
##   • Empty slots shown when positions available
##   • Refresh button to update display
##
##   Right Panel:
##   • CREDS counter
##   • Perk points available
##   • Current date (calendar)
##   • Current time phase (Morning/Afternoon/Evening)
##   • Hint text area
##   • Character appearance customization (colors)
##
## APPEARANCE SYSTEM:
##   Four customizable color components:
##   • Skin tone
##   • Brow color
##   • Eye color
##   • Hair color
##   Stored in GameState metadata and CombatProfileSystem
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Money, perk points, party roster, appearance metadata
##   • CombatProfileSystem - Current HP/MP values
##   • StatsSystem - Member levels, stat-based HP/MP pools
##   • CalendarSystem - Date/time display
##   • SigilSystem - (future) Sigil status display
##   • MainEventSystem - Hint text from story events
##
## CSV DATA SOURCES:
##   • res://data/actors/party.csv - Member base data and appearance
##
## KEY METHODS:
##   • _rebuild_party() - Update party member list with Leader/Active/Bench sections
##   • _create_member_card() - Create a member card with HP/MP and optional Switch button
##   • _create_empty_slot() - Create placeholder for empty party/bench slots
##   • _show_member_picker() - Show popup to select bench member for swapping
##   • _perform_swap() - Execute member swap between active and bench
##   • _update_summary() - Update CREDS/perks/date/time
##   • _rebuild_appearance() - Update appearance color swatches
##
## ============================================================================

extends PanelBase
class_name StatusPanel

## Shows party HP/MP, summary info, and appearance.
## Prefers GameState meta + CombatProfileSystem; falls back to Stats/CSV.
##
## ARCHITECTURE:
## - Extends PanelBase for lifecycle management
## - ROOT/HUB PANEL: First panel shown when GameMenu opens
## - Dual role: Tab list (hub to other panels) + Party management (content)
## - NavState: MENU (tab list), CONTENT (party management), POPUP_ACTIVE
## - Uses ToastPopup for all confirmations and notices
## - Member picker uses custom ItemList popup (special case)

# Signal emitted when a menu tab button is clicked
signal tab_selected(tab_id: String)

const GS_PATH        := "/root/aGameState"
const STATS_PATH     := "/root/aStatsSystem"
const CAL_PATH       := "/root/aCalendarSystem"
const PARTY_PATH     := "/root/aPartySystem"
const CSV_PATH       := "/root/aCSVLoader"
const RESOLVER_PATH  := "/root/PartyStatsResolver"
const SIGIL_PATH     := "/root/aSigilSystem"
const CPS_PATH       := "/root/aCombatProfileSystem"

const PARTY_CSV := "res://data/actors/party.csv"
const MES_PATH  := "/root/aMainEventSystem"
const ALT_MES_PATHS := [
	"/root/aMainEvents", "/root/aMainEvent",
	"/root/MainEventSystem", "/root/MainEvents", "/root/MainEvent"
]

# Tab button definitions
const TAB_DEFS: Dictionary = {
	"stats":   {"title": "STATS"},
	"perks":   {"title": "PERKS"},
	"items":   {"title": "ITEMS"},
	"loadout": {"title": "LOADOUT"},
	"bonds":   {"title": "BONDS"},
	"outreach":{"title": "OUTREACH"},
	"dorms":   {"title": "DORMS"},
	"calendar":{"title": "CALENDAR"},
	"index":   {"title": "INDEX"},
	"system":  {"title": "SYSTEM"},
}

const TAB_ORDER: PackedStringArray = [
	"stats","perks","items","loadout","bonds","outreach","dorms","calendar","index","system"
]

# Character preview constants
const CHAR_BASE_PATH = "res://assets/graphics/characters/"
const CHAR_VARIANTS = ["char_a_p1"]
const LAYERS = {
	"base": {"code": "0bas", "node_name": "BaseSprite", "path": ""},
	"outfit": {"code": "1out", "node_name": "OutfitSprite", "path": "1out"},
	"cloak": {"code": "2clo", "node_name": "CloakSprite", "path": "2clo"},
	"face": {"code": "3fac", "node_name": "FaceSprite", "path": "3fac"},
	"hair": {"code": "4har", "node_name": "HairSprite", "path": "4har"},
	"hat": {"code": "5hat", "node_name": "HatSprite", "path": "5hat"},
	"tool_a": {"code": "6tla", "node_name": "ToolASprite", "path": "6tla"},
	"tool_b": {"code": "7tlb", "node_name": "ToolBSprite", "path": "7tlb"}
}

# Debug logging (set to false to reduce console spam)
const DEBUG_LOGGING: bool = false

# Helper function for conditional logging
func _debug_log(message: String) -> void:
	if DEBUG_LOGGING:
		print("[StatusPanel] " + message)

@onready var _vertical_menu_box : PanelContainer = %VerticalMenuBox
@onready var _root_container : HBoxContainer = $Root
@onready var _tab_column : VBoxContainer = $Root/TabColumn
@onready var _tab_list  : ItemList      = %TabList
# Container references for Core Vibe styling
@onready var _left_container : VBoxContainer = $Root/Left if has_node("Root/Left") else null
@onready var _right_container : VBoxContainer = $Root/Right if has_node("Root/Right") else null
@onready var _party     : VBoxContainer = $Root/Left/PartyScroll/PartyList

# Tab button tracking for new button-based menu
var _tab_buttons: Array[Button] = []
var _tab_button_container: VBoxContainer = null
var _selected_button_index: int = 0
@onready var _creds     : Label         = $Root/Right/InfoGrid/MoneyValue
@onready var _perk      : Label         = $Root/Right/InfoGrid/PerkValue
@onready var _morality  : Label         = $Root/Right/InfoGrid/MoralityValue
@onready var _date      : Label         = $Root/Right/InfoGrid/DateValue
@onready var _phase     : Label         = $Root/Right/InfoGrid/PhaseValue
@onready var _hint      : RichTextLabel = $Root/Right/HintSection/HintValue

# New bottom-right CREDS/PERKS display
var _creds_value_label: Label = null
var _perks_value_label: Label = null

# New top-right NEXT MISSION display
var _mission_value_label: Label = null

# Character Preview UI
@onready var character_layers = $Root/Right/CharacterPreviewBox/ViewportWrapper/CharacterLayers

var _gs        : Node = null
var _st        : Node = null
var _cal       : Node = null
var _mes       : Node = null
var _party_sys : Node = null
var _csv       : Node = null
var _resolver  : Node = null
var _sig       : Node = null
var _cps       : Node = null
var _ctrl_mgr  : Node = null  # ControllerManager reference

# Menu slide state
var _menu_visible : bool = true
var _menu_tween   : Tween = null

# party.csv cache
var _csv_by_id   : Dictionary = {}      # "actor_id" -> row dict
var _name_to_id  : Dictionary = {}      # lowercase "name" -> "actor_id"

# Tab metadata (maps item index to tab_id)
var _tab_ids: Array[String] = []
var _last_selected_tab_index: int = 0  # Remember last selected tab
var _last_focused_content_button_index: int = 0  # Remember last focused content button

# HP/MP value cache for bar animations
var _prev_hp_mp: Dictionary = {}  # "member_id" -> {"hp": int, "mp": int}

# Controller navigation state - Simple state machine (like LoadoutPanel)
enum NavState { MENU, CONTENT, POPUP_ACTIVE }
var _nav_state: NavState = NavState.MENU
var _active_popup: Control = null  # Currently open popup panel
var _focus_member_id: String = ""  # Member ID to focus after rebuild (for Recovery button)

func _ready() -> void:
	super()  # Call PanelBase._ready() for lifecycle management

	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_gs        = get_node_or_null(GS_PATH)
	_st        = get_node_or_null(STATS_PATH)
	_cal       = get_node_or_null(CAL_PATH)
	_party_sys = get_node_or_null(PARTY_PATH)
	_csv       = get_node_or_null(CSV_PATH)
	_resolver  = get_node_or_null(RESOLVER_PATH)
	_sig       = get_node_or_null(SIGIL_PATH)
	_cps       = get_node_or_null(CPS_PATH)
	_ctrl_mgr  = get_node_or_null("/root/aControllerManager")

	_resolve_event_system()
	_normalize_scroll_children()
	_connect_signals()
	_load_party_csv_cache()
	_build_tab_buttons()
	_create_creds_perks_display()
	_create_next_mission_display()
	_hide_old_ui_elements()
	_apply_core_vibe_styling()

	# Note: PanelBase handles visibility_changed, no need to connect again
	call_deferred("_first_fill")

func _first_fill() -> void:
	# refresh soft refs (autoload init order resilience)
	if _gs == null:        _gs        = get_node_or_null(GS_PATH)
	if _st == null:        _st        = get_node_or_null(STATS_PATH)
	if _cal == null:       _cal       = get_node_or_null(CAL_PATH)
	if _party_sys == null: _party_sys = get_node_or_null(PARTY_PATH)
	if _csv == null:       _csv       = get_node_or_null(CSV_PATH)
	if _resolver == null:  _resolver  = get_node_or_null(RESOLVER_PATH)
	if _sig == null:       _sig       = get_node_or_null(SIGIL_PATH)
	if _cps == null:       _cps       = get_node_or_null(CPS_PATH)
	_load_party_csv_cache()
	_rebuild_all()

func _build_tab_buttons() -> void:
	"""Build individual menu tab buttons with pop-out styling"""
	# Hide old ItemList
	if _tab_list:
		_tab_list.visible = false

	# Create or get button container
	if not _tab_button_container:
		_tab_button_container = VBoxContainer.new()
		_tab_button_container.name = "TabButtons"
		_tab_button_container.add_theme_constant_override("separation", 8)
		# No container shift - buttons handle their own positioning

		# Find TabList and replace it with our button container
		if _tab_list and _tab_list.get_parent():
			var parent = _tab_list.get_parent()
			var index = _tab_list.get_index()
			parent.add_child(_tab_button_container)
			parent.move_child(_tab_button_container, index)
		else:
			_tab_column.add_child(_tab_button_container)

	# Clear existing buttons
	for btn in _tab_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_tab_buttons.clear()
	_tab_ids.clear()

	# Create buttons for each tab
	var ids: Array = Array(TAB_ORDER)
	for tab_id_any in ids:
		var tab_id: String = String(tab_id_any)
		if not TAB_DEFS.has(tab_id):
			continue
		var meta: Dictionary = TAB_DEFS[tab_id]

		var btn := Button.new()
		btn.text = String(meta["title"])
		btn.custom_minimum_size = Vector2(160, 36)  # Rounded square proportions
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER  # Center text

		# Style with rounded square and tab-specific border color
		_style_menu_button(btn, tab_id, false)

		# Connect pressed signal
		var button_index = _tab_buttons.size()
		btn.pressed.connect(func(): _on_tab_button_pressed(button_index))
		btn.focus_entered.connect(func(): _on_tab_button_focused(button_index))

		_tab_button_container.add_child(btn)
		_tab_buttons.append(btn)
		_tab_ids.append(tab_id)

	# Select and focus last selected button (or first if none)
	if _tab_buttons.size() > 0:
		# Preserve last selection instead of always resetting to 0
		_selected_button_index = _last_selected_tab_index
		if _selected_button_index >= _tab_buttons.size():
			_selected_button_index = 0  # Fallback if index is out of bounds
		_update_button_selection()
		if visible:
			call_deferred("_grab_first_tab_button_focus")

func _get_tab_border_color(tab_id: String) -> Color:
	"""Get the neon border color for a specific tab"""
	match tab_id:
		"stats":     return Color(0.5, 1.0, 0.5)    # Light green
		"perks":     return Color(1.0, 1.0, 0.0)    # Yellow
		"items":     return Color(1.0, 0.6, 0.0)    # Orange
		"loadout":   return Color(1.0, 0.0, 0.0)    # Red
		"bonds":     return Color(1.0, 0.0, 1.0)    # Magenta
		"outreach":  return Color(0.6, 0.0, 1.0)    # Purple
		"dorms":     return Color(0.0, 0.5, 1.0)    # Cobalt
		"calendar":  return Color(0.5, 0.8, 1.0)    # Light blue
		"index":     return Color(0.0, 0.8, 0.8)    # Teal
		"system":    return Color(1.0, 1.0, 1.0)    # White
		_:           return aCoreVibeTheme.COLOR_SKY_CYAN

func _style_menu_button(btn: Button, tab_id: String, is_selected: bool) -> void:
	"""Style a rounded square menu button with tab-specific neon border"""
	var style = StyleBoxFlat.new()

	# Get tab-specific border color
	var border_color = _get_tab_border_color(tab_id)

	# Colors based on selection
	if is_selected:
		# Selected: Pale white background with deep dark grey text
		style.bg_color = Color(0.95, 0.95, 0.95)  # Pale white
		style.border_color = border_color
	else:
		# Unselected: Dark greyish-blue background with white text, NO border
		style.bg_color = Color(0.15, 0.2, 0.3)  # Dark greyish-blue
		style.border_color = Color(0.15, 0.2, 0.3)  # Same as background (invisible border)

	# Rounded square: all corners equally rounded
	style.corner_radius_top_left = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8

	# Border: all sides equal
	if is_selected:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
	else:
		# No border when unselected
		style.border_width_left = 0
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0

	# Neon glow - only when selected
	if is_selected:
		style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.6)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 0)
	else:
		style.shadow_color = Color(0, 0, 0, 0)  # No glow
		style.shadow_size = 0

	# Centered padding
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)

	# Font size - increased by 3pts (was 13, now 16)
	btn.add_theme_font_size_override("font_size", 16)

	# Text color
	if is_selected:
		# Selected: Deep dark grey
		var dark_grey = Color(0.15, 0.15, 0.15)
		btn.add_theme_color_override("font_color", dark_grey)
		btn.add_theme_color_override("font_hover_color", dark_grey)
		btn.add_theme_color_override("font_pressed_color", dark_grey)
		btn.add_theme_color_override("font_focus_color", dark_grey)
	else:
		# Unselected: White
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		btn.add_theme_color_override("font_focus_color", Color.WHITE)

func _on_tab_button_pressed(index: int) -> void:
	"""Handle tab button press"""
	if index < 0 or index >= _tab_ids.size():
		return

	_selected_button_index = index
	_last_selected_tab_index = index  # Remember for when panel reopens
	_update_button_selection()

	var tab_id: String = _tab_ids[index]
	print("[StatusPanel] Tab button pressed: %s" % tab_id)
	tab_selected.emit(tab_id)

func _on_tab_button_focused(index: int) -> void:
	"""Handle tab button receiving focus"""
	_selected_button_index = index
	_last_selected_tab_index = index  # Remember for when panel reopens
	_update_button_selection()

func _update_button_selection() -> void:
	"""Update visual state for selected button"""
	for i in range(_tab_buttons.size()):
		var btn = _tab_buttons[i]
		var tab_id = _tab_ids[i] if i < _tab_ids.size() else ""
		var is_selected = (i == _selected_button_index)

		# Restyle button with tab-specific color
		_style_menu_button(btn, tab_id, is_selected)

		# Add pulse animation to selected button
		if is_selected:
			_start_button_pulse(btn)
		else:
			_stop_button_pulse(btn)

func _start_button_pulse(btn: Button) -> void:
	"""Start pulsing animation for button"""
	# Kill any existing tween
	if btn.has_meta("pulse_tween"):
		var old_tween = btn.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()

	# Create pulsing scale tween
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse between 1.0 and 1.05 scale
	tween.tween_property(btn, "scale", Vector2(1.05, 1.05), 0.8)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.8)

	btn.set_meta("pulse_tween", tween)

func _stop_button_pulse(btn: Button) -> void:
	"""Stop pulsing animation for button"""
	if btn.has_meta("pulse_tween"):
		var tween = btn.get_meta("pulse_tween")
		if tween and is_instance_valid(tween):
			tween.kill()
		btn.remove_meta("pulse_tween")

	# Reset scale to normal
	btn.scale = Vector2(1.0, 1.0)

func _grab_first_tab_button_focus() -> void:
	"""Grab focus on currently selected tab button"""
	if _tab_buttons.size() > 0 and is_instance_valid(_tab_buttons[_selected_button_index]):
		_tab_buttons[_selected_button_index].grab_focus()

func _create_creds_perks_display() -> void:
	"""Create the new CREDS/PERKS display in bottom right corner"""
	# Hide old CREDS and PERKS labels in InfoGrid
	if _creds:
		_creds.visible = false
		var parent = _creds.get_parent()
		if parent:
			var money_label = parent.get_node_or_null("MoneyLabel")
			if money_label:
				money_label.visible = false
	if _perk:
		_perk.visible = false
		var parent = _perk.get_parent()
		if parent:
			var perk_label = parent.get_node_or_null("PerkLabel")
			if perk_label:
				perk_label.visible = false

	# Create container for the new display
	var container := VBoxContainer.new()
	container.name = "CredsPerksDisplay"
	container.add_theme_constant_override("separation", 5)  # 5px gap between cells

	# Position: 40px from bottom, 10px from right edge
	# Using anchor to bottom-right corner
	container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	container.position = Vector2(-10, -40)  # 10px from right, 40px up from bottom
	container.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Grow left
	container.grow_vertical = Control.GROW_DIRECTION_BEGIN    # Grow up

	# Create CREDS cell
	var creds_cell := _create_info_cell("CREDS", "0")
	container.add_child(creds_cell)
	_creds_value_label = creds_cell.get_meta("value_label")

	# Create PERKS cell
	var perks_cell := _create_info_cell("PERKS", "0")
	container.add_child(perks_cell)
	_perks_value_label = perks_cell.get_meta("value_label")

	# Add to root (not to the Right VBoxContainer, but to the root Control)
	add_child(container)

func _create_next_mission_display() -> void:
	"""Create the NEXT MISSION display at top right corner"""
	# Create container for the display
	var container := VBoxContainer.new()
	container.name = "NextMissionDisplay"
	container.add_theme_constant_override("separation", 4)

	# Position: 20px from top, 10px from right edge
	# Using anchor to top-right corner
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.position = Vector2(-10, 20)  # 10px from right, 20px from top
	container.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Grow left
	container.grow_vertical = Control.GROW_DIRECTION_END      # Grow down

	# Create "NEXT MISSION" label - light blue
	var title_label := Label.new()
	title_label.text = "NEXT MISSION"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))  # Light blue
	container.add_child(title_label)

	# Create mission box - dark greyish-blue background, no glow
	var mission_box := PanelContainer.new()
	mission_box.custom_minimum_size = Vector2(300, 80)

	# Dark greyish-blue background matching unselected menu buttons
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.2, 0.3)  # Dark greyish-blue
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.shadow_size = 0  # No glow
	mission_box.add_theme_stylebox_override("panel", style)

	# Add margin for padding inside box
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	mission_box.add_child(margin)

	# Create label for mission text with Core Vibe styling
	_mission_value_label = Label.new()
	_mission_value_label.text = "TBD"
	_mission_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_mission_value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Core Vibe: Milk White text
	aCoreVibeTheme.style_label(_mission_value_label, aCoreVibeTheme.COLOR_MILK_WHITE, 14)
	margin.add_child(_mission_value_label)

	container.add_child(mission_box)

	# Add to root
	add_child(container)

func _hide_old_ui_elements() -> void:
	"""Hide the old player info panel, character preview, dates, morality, etc."""
	# Hide the entire Right VBoxContainer
	var right_panel = get_node_or_null("Root/Right")
	if right_panel:
		right_panel.visible = false

	# Add 150px right padding to the Left panel by wrapping it in a MarginContainer
	var left_panel = get_node_or_null("Root/Left")
	if left_panel and left_panel is VBoxContainer:
		# Create MarginContainer wrapper
		var margin_wrapper := MarginContainer.new()
		margin_wrapper.name = "LeftMarginWrapper"
		margin_wrapper.add_theme_constant_override("margin_right", 300)
		margin_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# Get parent and insert wrapper
		var parent = left_panel.get_parent()
		if parent:
			var index = left_panel.get_index()
			parent.remove_child(left_panel)
			parent.add_child(margin_wrapper)
			parent.move_child(margin_wrapper, index)
			margin_wrapper.add_child(left_panel)

func _create_info_cell(label_text: String, initial_value: String) -> PanelContainer:
	"""Create a single info cell with label and value
	Returns PanelContainer with 'value_label' meta for updating"""
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 40)  # Slightly increased for pill capsule

	# Core Vibe: Sky Cyan pill capsule panel
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
		aCoreVibeTheme.CORNER_RADIUS_SMALL,       # 12px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
	)
	panel.add_theme_stylebox_override("panel", style)

	# Add margin for padding inside cell (10px buffer on each side)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	# HBoxContainer to hold label and value
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)

	# Label - left justified, Core Vibe: Sky Cyan
	var label := Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size = Vector2(60, 0)  # ~6 chars + colon
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	aCoreVibeTheme.style_label(label, aCoreVibeTheme.COLOR_SKY_CYAN, 16)
	hbox.add_child(label)

	# Spacer to push value to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Value - right justified, Core Vibe: Milk White
	var value_label := Label.new()
	value_label.text = initial_value
	value_label.custom_minimum_size = Vector2(80, 0)  # ~16 chars max
	value_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	aCoreVibeTheme.style_label(value_label, aCoreVibeTheme.COLOR_MILK_WHITE, 16)
	hbox.add_child(value_label)

	# Store reference to value label for updating
	panel.set_meta("value_label", value_label)

	return panel

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to StatusPanel columns"""
	# Only style left column - right column stays hidden

	# Left column (party stats): Sky Cyan border (party/lists)
	if _left_container:
		_wrap_in_styled_panel(_left_container, aCoreVibeTheme.COLOR_SKY_CYAN)

func _wrap_in_styled_panel(container: Control, border_color: Color) -> PanelContainer:
	"""Wrap a container in a styled PanelContainer with rounded neon borders"""
	if not container or not container.get_parent():
		return null

	var parent = container.get_parent()
	var index = container.get_index()

	# Create styled panel
	var panel = PanelContainer.new()
	var panel_style = aCoreVibeTheme.create_panel_style(
		border_color,
		aCoreVibeTheme.COLOR_INK_CHARCOAL,
		aCoreVibeTheme.PANEL_OPACITY_SEMI,
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,
		aCoreVibeTheme.BORDER_WIDTH_THIN,
		aCoreVibeTheme.SHADOW_SIZE_MEDIUM
	)
	# Add 10px internal padding
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", panel_style)

	# Preserve size flags and reparent
	panel.size_flags_horizontal = container.size_flags_horizontal
	panel.size_flags_vertical = container.size_flags_vertical
	panel.custom_minimum_size = container.custom_minimum_size

	parent.remove_child(container)
	panel.add_child(container)
	parent.add_child(panel)
	parent.move_child(panel, index)

	return panel

func select_tab(tab_id: String) -> void:
	"""Programmatically select a tab by tab_id and give it focus"""
	# Find the index of the tab_id
	var index: int = _tab_ids.find(tab_id)
	if index >= 0 and index < _tab_buttons.size():
		_selected_button_index = index
		_update_button_selection()
		if visible and is_instance_valid(_tab_buttons[index]):
			call_deferred("_tab_buttons[%d].grab_focus" % index)
		print("[StatusPanel] Selected tab: %s (index %d)" % [tab_id, index])
	else:
		print("[StatusPanel] WARNING: Tab not found: %s" % tab_id)

func _on_tab_item_selected(index: int) -> void:
	"""Handle tab item selection (when navigating with UP/DOWN)"""
	# Just visual feedback - don't switch tabs yet
	print("[StatusPanel] Tab selected: index %d" % index)

func _on_tab_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	"""Handle tab item clicked (single left-click support)"""
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		_on_tab_item_activated(index)

func _on_tab_item_activated(index: int) -> void:
	"""Handle tab item activation (A button or double-click)"""
	if index < 0 or index >= _tab_ids.size():
		return

	# Remember this tab selection
	_last_selected_tab_index = index

	var tab_id: String = _tab_ids[index]
	print("[StatusPanel] Tab activated: %s" % tab_id)
	tab_selected.emit(tab_id)

func _connect_signals() -> void:
	# Calendar
	if _cal:
		if _cal.has_signal("day_advanced") and not _cal.is_connected("day_advanced", Callable(self, "_on_cal_day_adv")):
			_cal.connect("day_advanced", Callable(self, "_on_cal_day_adv"))
		if _cal.has_signal("phase_advanced") and not _cal.is_connected("phase_advanced", Callable(self, "_on_cal_phase_adv")):
			_cal.connect("phase_advanced", Callable(self, "_on_cal_phase_adv"))
		if _cal.has_signal("week_reset") and not _cal.is_connected("week_reset", Callable(self, "_rebuild_all")):
			_cal.connect("week_reset", Callable(self, "_rebuild_all"))

	# Stats
	if _st and _st.has_signal("stats_changed"):
		_st.connect("stats_changed", Callable(self, "_rebuild_all"))
	if _st and _st.has_signal("stat_leveled_up"):
		_st.connect("stat_leveled_up", Callable(self, "_rebuild_all"))

	# GameState / Party changes
	for src in [_gs, _party_sys]:
		if src == null: continue
		for sig in ["party_changed","active_changed","roster_changed","changed"]:
			if src.has_signal(sig) and not src.is_connected(sig, Callable(self, "_on_party_changed")):
				src.connect(sig, Callable(self, "_on_party_changed"))

	# Combat Profile updates (reflect current HP/MP/level)
	if _cps:
		for sig2 in ["profile_changed","profiles_changed"]:
			if _cps.has_signal(sig2) and not _cps.is_connected(sig2, Callable(self, "_rebuild_all")):
				_cps.connect(sig2, Callable(self, "_rebuild_all"))

	# Creation screen may fire this; listen globally
	for n in get_tree().root.get_children():
		if n.has_signal("creation_applied") and not n.is_connected("creation_applied", Callable(self, "_rebuild_all")):
			n.connect("creation_applied", Callable(self, "_rebuild_all"))

func _on_cal_day_adv(_date_dict: Dictionary) -> void:
	_rebuild_all()

func _on_cal_phase_adv(_phase_i: int) -> void:
	_rebuild_all()

func _on_party_changed(_a: Variant = null) -> void:
	_load_party_csv_cache()
	_rebuild_party()

func _resolve_event_system() -> void:
	_mes = get_node_or_null(MES_PATH)
	if _mes == null:
		for p in ALT_MES_PATHS:
			_mes = get_node_or_null(p)
			if _mes: break
	if _mes == null:
		for n in get_tree().root.get_children():
			if n.has_method("get_current_hint"):
				_mes = n; break
	if _mes and _mes.has_signal("event_changed"):
		if not _mes.is_connected("event_changed", Callable(self, "_on_event_changed")):
			_mes.connect("event_changed", Callable(self, "_on_event_changed"))

func _normalize_scroll_children() -> void:
	if not _party: return
	var parent := _party.get_parent()
	if parent is ScrollContainer:
		for c in (parent as ScrollContainer).get_children():
			if c != _party:
				(c as Node).queue_free()

func _rebuild_all() -> void:
	_rebuild_party()
	_update_summary()
	_rebuild_appearance()

# --------------------- Party (left panel) ---------------------

func _rebuild_party() -> void:
	if not _party: return

	# Remove and free all children immediately (don't use queue_free to avoid duplicates during rebuild)
	for c in _party.get_children():
		_party.remove_child(c)
		c.free()

	# Enforce party limits first
	if _gs and _gs.has_method("_enforce_party_limits"):
		_gs.call("_enforce_party_limits")

	# Get party structure from GameState
	var party_ids: Array = []
	var bench_ids: Array = []
	if _gs:
		if _gs.has_method("get"):
			var p_v: Variant = _gs.get("party")
			if typeof(p_v) == TYPE_ARRAY:
				for id in (p_v as Array):
					party_ids.append(String(id))
			var b_v: Variant = _gs.get("bench")
			if typeof(b_v) == TYPE_ARRAY:
				for id in (b_v as Array):
					bench_ids.append(String(id))

	# Debug output
	_debug_log("Party IDs: " + str(party_ids))
	_debug_log("Bench IDs: " + str(bench_ids))

	# Ensure hero is always at index 0
	if party_ids.is_empty() or party_ids[0] != "hero":
		party_ids.insert(0, "hero")

	# Handle edge case: if party has more than 3 members, move extras to bench
	if party_ids.size() > 3:
		for i in range(3, party_ids.size()):
			if not bench_ids.has(party_ids[i]):
				bench_ids.append(party_ids[i])
		party_ids = party_ids.slice(0, 3)

	# === LEADER SECTION ===
	var leader_header := Label.new()
	leader_header.text = "LEADER"
	leader_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leader_header.add_theme_font_size_override("font_size", 16)
	leader_header.add_theme_color_override("font_color", Color(1, 0.7, 0.75, 1))
	_party.add_child(leader_header)

	# Add separator after LEADER
	var leader_sep := HSeparator.new()
	_party.add_child(leader_sep)

	if party_ids.size() > 0:
		var leader_data := _get_member_snapshot(party_ids[0])
		_party.add_child(_create_member_card(leader_data, false, -1))

	_party.add_child(_create_spacer())

	# === ACTIVE SECTION ===
	var active_header := Label.new()
	active_header.text = "ACTIVE"
	active_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_header.add_theme_font_size_override("font_size", 16)
	active_header.add_theme_color_override("font_color", Color(1, 0.7, 0.75, 1))
	_party.add_child(active_header)

	# Add separator after ACTIVE
	var active_sep := HSeparator.new()
	_party.add_child(active_sep)

	for slot_idx in range(1, 3):  # Slots 1 and 2
		if party_ids.size() > slot_idx and party_ids[slot_idx] != "":
			var active_data := _get_member_snapshot(party_ids[slot_idx])
			_party.add_child(_create_member_card(active_data, true, slot_idx))
		else:
			_party.add_child(_create_empty_slot("Active", slot_idx))

	_party.add_child(_create_spacer())

	# === BENCH SECTION ===
	var bench_header := Label.new()
	bench_header.text = "BENCH"
	bench_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bench_header.add_theme_font_size_override("font_size", 16)
	bench_header.add_theme_color_override("font_color", Color(1, 0.7, 0.75, 1))
	_party.add_child(bench_header)

	# Add separator after BENCH
	var bench_sep := HSeparator.new()
	_party.add_child(bench_sep)

	# Only show bench slots that have members (hide empty slots)
	for bench_idx in range(bench_ids.size()):
		var bench_data := _get_member_snapshot(bench_ids[bench_idx])
		bench_data["_bench_idx"] = bench_idx
		bench_data["_member_id"] = bench_ids[bench_idx]
		_party.add_child(_create_member_card(bench_data, false, -1))

	await get_tree().process_frame
	_party.queue_sort()

func _create_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	return spacer

func _create_empty_slot(slot_type: String, _slot_idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Fill the panel width
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var label := Label.new()
	label.text = "[ Empty %s Slot ]" % slot_type
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(label)

	panel.add_child(vbox)
	return panel

func _create_member_card(member_data: Dictionary, show_switch: bool, active_slot: int) -> Button:
	# Create a button instead of PanelContainer for clickability
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(0, 40)  # Compact: name/level left, bars right
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Fill the panel width

	# Store metadata for popup menu
	var member_id: String = String(member_data.get("_member_id", ""))
	btn.set_meta("member_id", member_id)
	btn.set_meta("member_name", String(member_data.get("name", "Member")))
	btn.set_meta("show_switch", show_switch)
	btn.set_meta("active_slot", active_slot)
	btn.set_meta("hp", int(member_data.get("hp", 0)))
	btn.set_meta("hp_max", int(member_data.get("hp_max", 0)))
	btn.set_meta("mp", int(member_data.get("mp", 0)))
	btn.set_meta("mp_max", int(member_data.get("mp_max", 0)))

	# Connect to member card pressed
	btn.pressed.connect(_on_member_card_pressed.bind(btn))
	btn.focus_entered.connect(_on_member_card_focused.bind(btn))
	btn.focus_exited.connect(_on_member_card_unfocused.bind(btn))

	# Main horizontal container: name/level on left, stats on right
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 8)
	main_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Left side: Name and Level (20 character width)
	var name_level_vbox := VBoxContainer.new()
	name_level_vbox.add_theme_constant_override("separation", 0)
	name_level_vbox.custom_minimum_size.x = 160  # ~20 characters at default font
	name_level_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_lbl := Label.new()
	name_lbl.text = String(member_data.get("name", "Member"))
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_level_vbox.add_child(name_lbl)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lv %d" % int(member_data.get("level", 1))
	lvl_lbl.add_theme_font_size_override("font_size", 9)
	lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_level_vbox.add_child(lvl_lbl)

	main_hbox.add_child(name_level_vbox)

	# Right side: HP/MP bars stacked vertically
	var bars_vbox := VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 4)
	bars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hp_i: int = int(member_data.get("hp", -1))
	var hp_max_i: int = int(member_data.get("hp_max", -1))
	var mp_i: int = int(member_data.get("mp", -1))
	var mp_max_i: int = int(member_data.get("mp_max", -1))

	# HP bar with label
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 4)
	hp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.custom_minimum_size.x = 20
	hp_lbl.add_theme_font_size_override("font_size", 9)
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_lbl)

	if hp_i >= 0 and hp_max_i > 0:
		var hp_bar := ProgressBar.new()
		hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp_bar.custom_minimum_size = Vector2(150, 8)  # Compact bar
		hp_bar.show_percentage = false

		# Core Vibe: Bubble Magenta progress bar with neon glow
		aCoreVibeTheme.style_progress_bar(hp_bar, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)

		hp_bar.min_value = 0.0
		hp_bar.max_value = float(hp_max_i)

		# Check if we have previous HP value and it's different (animate if changed)
		var new_hp: float = clamp(float(hp_i), 0.0, float(hp_max_i))
		if member_id != "" and _prev_hp_mp.has(member_id):
			var old_hp: float = float(_prev_hp_mp[member_id].get("hp", new_hp))
			if old_hp != new_hp:
				# Start at old value and animate to new
				hp_bar.value = old_hp
				var tween := create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(hp_bar, "value", new_hp, 2.0)
			else:
				hp_bar.value = new_hp
		else:
			hp_bar.value = new_hp

		hp_row.add_child(hp_bar)

	var hp_val := Label.new()
	hp_val.text = _fmt_pair(hp_i, hp_max_i)
	hp_val.add_theme_font_size_override("font_size", 9)
	hp_val.custom_minimum_size.x = 60
	hp_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(hp_val)

	bars_vbox.add_child(hp_row)

	# MP bar with label
	var mp_row := HBoxContainer.new()
	mp_row.add_theme_constant_override("separation", 4)
	mp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mp_lbl := Label.new()
	mp_lbl.text = "MP"
	mp_lbl.custom_minimum_size.x = 20
	mp_lbl.add_theme_font_size_override("font_size", 9)
	mp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_row.add_child(mp_lbl)

	if mp_i >= 0 and mp_max_i > 0:
		var mp_bar := ProgressBar.new()
		mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mp_bar.custom_minimum_size = Vector2(150, 8)  # Compact bar
		mp_bar.show_percentage = false

		# Core Vibe: Sky Cyan progress bar with neon glow
		aCoreVibeTheme.style_progress_bar(mp_bar, aCoreVibeTheme.COLOR_SKY_CYAN)

		mp_bar.min_value = 0.0
		mp_bar.max_value = float(mp_max_i)

		# Check if we have previous MP value and it's different (animate if changed)
		var new_mp: float = clamp(float(mp_i), 0.0, float(mp_max_i))
		if member_id != "" and _prev_hp_mp.has(member_id):
			var old_mp: float = float(_prev_hp_mp[member_id].get("mp", new_mp))
			if old_mp != new_mp:
				# Start at old value and animate to new
				mp_bar.value = old_mp
				var tween := create_tween()
				tween.set_ease(Tween.EASE_OUT)
				tween.set_trans(Tween.TRANS_CUBIC)
				tween.tween_property(mp_bar, "value", new_mp, 2.0)
			else:
				mp_bar.value = new_mp
		else:
			mp_bar.value = new_mp

		mp_row.add_child(mp_bar)

	var mp_val := Label.new()
	mp_val.text = _fmt_pair(mp_i, mp_max_i)
	mp_val.add_theme_font_size_override("font_size", 9)
	mp_val.custom_minimum_size.x = 60
	mp_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_row.add_child(mp_val)

	bars_vbox.add_child(mp_row)

	main_hbox.add_child(bars_vbox)
	btn.add_child(main_hbox)

	# Style button (default unfocused state)
	_style_member_card(btn, false)

	# Store current HP/MP values for next rebuild animation
	if member_id != "":
		_prev_hp_mp[member_id] = {
			"hp": hp_i,
			"mp": mp_i
		}

	return btn

func _style_member_card(btn: Button, is_focused: bool) -> void:
	"""Style a member card button based on focus state"""
	var style = StyleBoxFlat.new()

	# No background - completely transparent
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.shadow_size = 0
	# Minimal padding
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)

	# Keep all text white regardless of focus
	if btn.get_child_count() > 0:
		var main_hbox = btn.get_child(0)
		if main_hbox.get_child_count() > 0:
			var info_vbox = main_hbox.get_child(0)
			_update_label_colors_recursive(info_vbox, false)  # Always use white

	# Handle arrow indicator
	if is_focused:
		_show_member_arrow(btn)
	else:
		_hide_member_arrow(btn)

func _update_label_colors_recursive(node: Node, is_focused: bool) -> void:
	"""Recursively update label colors in a node tree"""
	if node is Label:
		if is_focused:
			node.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_INK_CHARCOAL)
		else:
			node.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)

	for child in node.get_children():
		_update_label_colors_recursive(child, is_focused)

func _show_member_arrow(btn: Button) -> void:
	"""Show arrow indicator above selected party member"""
	# Check if arrow already exists
	var arrow = btn.get_node_or_null("SelectionArrow")
	if arrow:
		return  # Already exists

	# Create arrow indicator using Label (no external asset needed)
	var arrow_label := Label.new()
	arrow_label.name = "SelectionArrow"
	arrow_label.text = "▼"  # Down arrow Unicode character
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_label.add_theme_font_size_override("font_size", 20)
	arrow_label.modulate = Color(1, 1, 1, 1)  # White
	arrow_label.custom_minimum_size = Vector2(30, 20)

	# Position at top center of button
	arrow_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	arrow_label.position = Vector2(0, -25)  # Above the button
	arrow_label.size = Vector2(30, 20)
	arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	btn.add_child(arrow_label)

	# Start pulsing animation
	_start_arrow_pulse(arrow_label)

func _hide_member_arrow(btn: Button) -> void:
	"""Hide arrow indicator from party member"""
	var arrow = btn.get_node_or_null("SelectionArrow")
	if arrow:
		# Stop any running tween
		if arrow.has_meta("pulse_tween"):
			var tween = arrow.get_meta("pulse_tween")
			if tween and is_instance_valid(tween):
				tween.kill()
			arrow.remove_meta("pulse_tween")
		arrow.queue_free()

func _start_arrow_pulse(arrow: Control) -> void:
	"""Start pulsing animation for arrow - moves up and down"""
	if arrow.has_meta("pulse_tween"):
		var old_tween = arrow.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse down 4 pixels then back up
	var base_y = arrow.position.y
	tween.tween_property(arrow, "position:y", base_y + 4, 0.6)
	tween.tween_property(arrow, "position:y", base_y, 0.6)

	arrow.set_meta("pulse_tween", tween)

func _on_member_card_focused(btn: Button) -> void:
	"""Handle member card gaining focus"""
	_style_member_card(btn, true)

func _on_member_card_unfocused(btn: Button) -> void:
	"""Handle member card losing focus"""
	_style_member_card(btn, false)

func _on_member_card_pressed(btn: Button) -> void:
	"""Handle member card being pressed - show action menu"""
	var member_name = btn.get_meta("member_name", "Member")
	var show_switch = btn.get_meta("show_switch", false)
	var active_slot = btn.get_meta("active_slot", -1)
	var member_id = btn.get_meta("member_id", "")
	var hp = btn.get_meta("hp", 0)
	var hp_max = btn.get_meta("hp_max", 0)
	var mp = btn.get_meta("mp", 0)
	var mp_max = btn.get_meta("mp_max", 0)

	print("[StatusPanel] Member card pressed: %s (show_switch: %s)" % [member_name, show_switch])

	# Create action menu popup
	_show_member_action_menu(member_name, member_id, show_switch, active_slot, hp, hp_max, mp, mp_max)

func _show_member_action_menu(member_name: String, member_id: String, show_switch: bool, active_slot: int, hp: int, hp_max: int, mp: int, mp_max: int) -> void:
	"""Show popup menu with RECOVERY and optionally SWITCH - matches Recovery popup pattern"""
	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[StatusPanel] Popup already open, ignoring request")
		return

	# Create CanvasLayer to ensure popup is centered on viewport
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	# Create popup panel using same pattern as Recovery popup
	var popup_panel: Panel = Panel.new()
	popup_panel.name = "MemberActionMenu"
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.set_anchors_preset(Control.PRESET_CENTER)
	popup_panel.modulate.a = 0.0  # Start fully transparent
	popup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Block input until fade completes
	canvas_layer.add_child(popup_panel)

	# Apply consistent styling (matches Recovery popup)
	_style_popup_panel(popup_panel)

	# Set active popup immediately
	_active_popup = popup_panel

	# Store metadata
	popup_panel.set_meta("member_name", member_name)
	popup_panel.set_meta("member_id", member_id)
	popup_panel.set_meta("show_switch", show_switch)
	popup_panel.set_meta("active_slot", active_slot)
	popup_panel.set_meta("hp", hp)
	popup_panel.set_meta("hp_max", hp_max)
	popup_panel.set_meta("mp", mp)
	popup_panel.set_meta("mp_max", mp_max)

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = member_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Member status display
	var status_label: Label = Label.new()
	status_label.text = "HP: %d/%d  |  MP: %d/%d" % [hp, hp_max, mp, mp_max]
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	# Recovery button
	var recovery_btn := Button.new()
	recovery_btn.text = "RECOVERY"
	recovery_btn.custom_minimum_size = Vector2(200, 0)
	recovery_btn.focus_mode = Control.FOCUS_ALL
	recovery_btn.pressed.connect(_on_action_menu_recovery_pressed.bind(popup_panel))
	vbox.add_child(recovery_btn)

	# Switch button (only for active slots)
	if show_switch:
		var switch_btn := Button.new()
		switch_btn.text = "SWITCH"
		switch_btn.custom_minimum_size = Vector2(200, 0)
		switch_btn.focus_mode = Control.FOCUS_ALL
		switch_btn.pressed.connect(_on_action_menu_switch_pressed.bind(popup_panel))

		# Check if bench is empty and disable button if so
		var bench_ids: Array = []
		if _gs and _gs.has_method("get"):
			var b_v: Variant = _gs.get("bench")
			if typeof(b_v) == TYPE_ARRAY:
				for id in (b_v as Array):
					bench_ids.append(String(id))

		if bench_ids.is_empty():
			switch_btn.disabled = true
			switch_btn.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grey out
			print("[StatusPanel] Switch button disabled - bench is empty")

		vbox.add_child(switch_btn)

	# Back button
	var back_btn: Button = Button.new()
	back_btn.text = "BACK"
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.pressed.connect(_close_member_action_menu.bind(popup_panel))
	vbox.add_child(back_btn)

	# Auto-size panel - wait two frames
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0

	# Fade in popup
	_fade_in_popup(popup_panel)

	# Change nav state and grab focus
	_nav_state = NavState.POPUP_ACTIVE
	recovery_btn.call_deferred("grab_focus")

	print("[StatusPanel] Member action menu shown for: %s" % member_name)

func _on_action_menu_recovery_pressed(popup: Control) -> void:
	"""Handle RECOVERY pressed from action menu"""
	var member_id = popup.get_meta("member_id", "")
	var member_name = popup.get_meta("member_name", "Member")
	var hp = popup.get_meta("hp", 0)
	var hp_max = popup.get_meta("hp_max", 0)
	var mp = popup.get_meta("mp", 0)
	var mp_max = popup.get_meta("mp_max", 0)

	print("[StatusPanel] Action menu - Recovery selected for: %s" % member_name)

	# Clear active popup immediately to allow new popup to open
	_active_popup = null

	# Close action menu (fade out and cleanup)
	_close_member_action_menu(popup)

	# Show recovery popup
	_show_recovery_popup(member_id, member_name, hp, hp_max, mp, mp_max)

func _on_action_menu_switch_pressed(popup: Control) -> void:
	"""Handle SWITCH pressed from action menu"""
	var active_slot = popup.get_meta("active_slot", -1)

	print("[StatusPanel] Action menu - Switch selected for slot: %d" % active_slot)

	# Clear active popup immediately to allow new popup to open
	_active_popup = null

	# Close action menu (fade out and cleanup)
	_close_member_action_menu(popup)

	# Show switch popup
	_on_switch_pressed(active_slot)

func _close_member_action_menu(popup: Control) -> void:
	"""Close the member action menu - matches Recovery popup pattern"""
	if not popup or not is_instance_valid(popup):
		return

	print("[StatusPanel] Closing member action menu with fade-out, returning to content mode")

	# Store popup reference but DON'T clear _active_popup yet (prevents double-close during fade)
	var popup_to_close = popup

	# Fade out popup, then clean up
	_fade_out_popup(popup_to_close, func():
		# Only clear active popup if it's still this popup (not a new one opened since)
		if _active_popup == popup_to_close:
			_active_popup = null
			_nav_state = NavState.CONTENT

		# Free the popup and its CanvasLayer parent
		if is_instance_valid(popup_to_close):
			var canvas_layer = popup_to_close.get_parent()
			if canvas_layer and is_instance_valid(canvas_layer):
				canvas_layer.queue_free()  # This also frees the popup
			else:
				popup_to_close.queue_free()

		# Only restore focus if we're actually going back to content (not opening another popup)
		if _nav_state == NavState.CONTENT:
			call_deferred("_navigate_to_content")
	)

	print("[StatusPanel] Member action menu closed")

func _get_member_snapshot(member_id: String) -> Dictionary:
	# Get roster to pass to _label_for_id for accurate name lookup
	var roster: Dictionary = _read_roster()
	# Always get display name from _label_for_id as primary source
	var display_name: String = _label_for_id(member_id, roster)

	# Declare variables at function scope to avoid confusable declarations
	var lvl: int = 1
	var hp_max: int = 150
	var mp_max: int = 20

	# Try to get combat profile for HP/MP/level
	if _cps and _cps.has_method("get_profile"):
		var p_v: Variant = _cps.call("get_profile", member_id)
		if typeof(p_v) == TYPE_DICTIONARY:
			var p: Dictionary = p_v
			lvl = int(p.get("level", 1))
			var hp_cur: int = int(p.get("hp", -1))
			hp_max = int(p.get("hp_max", -1))
			var mp_cur: int = int(p.get("mp", -1))
			mp_max = int(p.get("mp_max", -1))

			# Always use display_name from _label_for_id which has proper CSV/roster fallbacks
			return {
				"name": "%s  (Lv %d)" % [display_name, lvl],
				"hp": hp_cur,
				"hp_max": hp_max,
				"mp": mp_cur,
				"mp_max": mp_max,
				"_member_id": member_id
			}

	# Fallback: no profile data, use display name and compute stats
	# (Variables already declared at function scope)
	if _gs:
		lvl = _gs.call("get_member_level", member_id) if _gs.has_method("get_member_level") else 1
		if _gs.has_method("compute_member_pools"):
			var pools_v: Variant = _gs.call("compute_member_pools", member_id)
			if typeof(pools_v) == TYPE_DICTIONARY:
				var pools: Dictionary = pools_v
				hp_max = int(pools.get("hp_max", hp_max))
				mp_max = int(pools.get("mp_max", mp_max))

	return {
		"name": "%s  (Lv %d)" % [display_name, lvl],
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max,
		"_member_id": member_id
	}

func _on_switch_pressed(active_slot: int) -> void:
	# Show bench member picker popup
	_show_member_picker(active_slot)

func _on_recovery_pressed(button: Button) -> void:
	"""Show recovery item selection popup"""
	var member_id: String = String(button.get_meta("member_id", ""))
	var member_name: String = String(button.get_meta("member_name", "Member"))
	var hp: int = int(button.get_meta("hp", 0))
	var hp_max: int = int(button.get_meta("hp_max", 0))
	var mp: int = int(button.get_meta("mp", 0))
	var mp_max: int = int(button.get_meta("mp_max", 0))

	print("[StatusPanel] Recovery button pressed for %s (ID: %s)" % [member_name, member_id])
	_show_recovery_popup(member_id, member_name, hp, hp_max, mp, mp_max)

func _show_no_bench_notice() -> void:
	"""Show 'no bench members' notice using ToastPopup"""
	print("[StatusPanel] Showing no bench notice")

	# Create and show ToastPopup (auto-centers, auto-styles, auto-blocks input)
	var popup := ToastPopup.create("No benched party members available.", "No Bench Members")
	add_child(popup)

	# Wait for user to dismiss
	await popup.confirmed

	# Clean up
	popup.queue_free()
	print("[StatusPanel] No bench notice closed")

func _show_already_at_max_notice(member_name: String, stat_type: String) -> void:
	"""Show 'already at max HP/MP' notice using ToastPopup"""
	print("[StatusPanel] Showing already at max notice for %s (%s)" % [member_name, stat_type])

	# Create and show ToastPopup
	var popup := ToastPopup.create("%s is already at max %s." % [member_name, stat_type], "Already at Max")
	add_child(popup)

	# Wait for user to dismiss
	await popup.confirmed

	# Clean up
	popup.queue_free()
	print("[StatusPanel] Already at max notice closed")

func _show_heal_confirmation(member_name: String, heal_amount: int, healed_type: String) -> void:
	"""Show healing confirmation message using ToastPopup"""
	print("[StatusPanel] Showing heal confirmation for %s" % member_name)

	# Create and show ToastPopup
	var popup := ToastPopup.create("%s has healed %d %s" % [member_name, heal_amount, healed_type], "Recovery")
	add_child(popup)

	# Wait for user to dismiss
	await popup.confirmed

	# Clean up
	popup.queue_free()
	print("[StatusPanel] Heal confirmation closed")

func _show_swap_confirmation(member_name: String, _member_id: String) -> void:
	"""Show swap confirmation message using ToastPopup"""
	print("[StatusPanel] Showing swap confirmation for %s" % member_name)

	# Create and show ToastPopup
	var popup := ToastPopup.create("%s is now in your active party" % member_name, "Party Swap")
	add_child(popup)

	# Wait for user to dismiss
	await popup.confirmed

	# Clean up
	popup.queue_free()
	print("[StatusPanel] Swap confirmation closed")

func _style_popup_panel(popup_panel: Panel) -> void:
	"""Apply Core Vibe styling to popup panels (matches ToastPopup)"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	popup_panel.add_theme_stylebox_override("panel", style)

func _fade_in_popup(popup_panel: Panel) -> void:
	"""Fade in popup over 0.3 seconds and enable input when complete"""
	# Create tween for fade-in animation
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fade from transparent to fully visible
	tween.tween_property(popup_panel, "modulate:a", 1.0, 0.3)

	# Enable input after fade completes
	tween.tween_callback(func():
		popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		print("[StatusPanel] Popup fade-in complete, input enabled")
	)

func _fade_out_popup(popup_panel: Panel, on_complete: Callable) -> void:
	"""Fade out popup over 0.3 seconds and call callback when complete"""
	# Disable input immediately
	popup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create tween for fade-out animation
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fade to transparent
	tween.tween_property(popup_panel, "modulate:a", 0.0, 0.3)

	# Call callback after fade completes
	tween.tween_callback(on_complete)

func _show_member_picker(active_slot: int) -> void:
	"""Show bench member picker popup - LoadoutPanel pattern"""
	if not _gs: return

	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[StatusPanel] Popup already open, ignoring request")
		return

	# Enforce limits before checking bench
	if _gs.has_method("_enforce_party_limits"):
		_gs.call("_enforce_party_limits")

	# Get bench members
	var bench_ids: Array = []
	if _gs.has_method("get"):
		var b_v: Variant = _gs.get("bench")
		if typeof(b_v) == TYPE_ARRAY:
			for id in (b_v as Array):
				bench_ids.append(String(id))

	# Debug output
	print("[StatusPanel] Switch button - Active slot: %d, Bench IDs: %s" % [active_slot, bench_ids])

	if bench_ids.is_empty():
		# Show message: no bench members available (using Panel pattern)
		_show_no_bench_notice()
		return

	# Create CanvasLayer to ensure popup is centered on viewport
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	# Create popup panel using LoadoutPanel pattern
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.set_anchors_preset(Control.PRESET_CENTER)
	popup_panel.modulate.a = 0.0  # Start fully transparent
	popup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Block input until fade completes
	canvas_layer.add_child(popup_panel)

	# Apply consistent styling (matches ToastPopup)
	_style_popup_panel(popup_panel)

	# Set active popup immediately
	_active_popup = popup_panel

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "Select Bench Member"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Instruction text
	var instruction: Label = Label.new()
	instruction.text = "Choose a member to swap into the active slot:"
	instruction.add_theme_font_size_override("font_size", 10)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(instruction)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 150)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(item_list)

	# Populate list with bench members
	var roster: Dictionary = _read_roster()
	for bench_id in bench_ids:
		var display_name: String = _label_for_id(bench_id, roster)
		var level: int = 1
		if _cps and _cps.has_method("get_profile"):
			var prof_v: Variant = _cps.call("get_profile", bench_id)
			if typeof(prof_v) == TYPE_DICTIONARY:
				level = int((prof_v as Dictionary).get("level", 1))
		item_list.add_item("%s (Lv %d)" % [display_name, level])
		item_list.set_item_metadata(item_list.item_count - 1, bench_id)

	# Add Back button
	var back_btn: Button = Button.new()
	back_btn.text = "BACK"
	back_btn.pressed.connect(_popup_cancel_switch)
	vbox.add_child(back_btn)

	# Auto-size panel - wait two frames for proper layout
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[StatusPanel] Switch popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])
	# Fade in popup
	_fade_in_popup(popup_panel)


	# Store metadata
	popup_panel.set_meta("_is_switch_popup", true)
	popup_panel.set_meta("_active_slot", active_slot)
	popup_panel.set_meta("_item_list", item_list)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[StatusPanel] Pushed switch popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	# Select first item and grab focus
	if item_list.item_count > 0:
		item_list.select(0)
		await get_tree().process_frame
		item_list.grab_focus()

func _perform_swap(active_slot: int, bench_member_id: String, member_name: String) -> void:
	if not _gs or not _gs.has_method("swap_active_bench"): return

	var success: bool = _gs.call("swap_active_bench", active_slot, bench_member_id)
	if success:
		# Save member_id to restore focus after rebuild
		_focus_member_id = bench_member_id

		_rebuild_party()  # Refresh display

		# Show confirmation message
		_show_swap_confirmation(member_name, bench_member_id)
	else:
		var error_popup := AcceptDialog.new()
		error_popup.dialog_text = "Failed to swap party members. Please try again."
		error_popup.title = "Swap Failed"
		add_child(error_popup)
		error_popup.popup_centered()
		error_popup.confirmed.connect(func(): error_popup.queue_free())

func _popup_accept_switch() -> void:
	"""User pressed A/Accept on switch popup - perform member swap"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var item_list = _active_popup.get_meta("_item_list", null)
	var active_slot = _active_popup.get_meta("_active_slot", -1)

	if not item_list or active_slot < 0:
		print("[StatusPanel] Switch popup missing metadata")
		_popup_cancel_switch()
		return

	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		print("[StatusPanel] No member selected")
		return

	var selected_idx = selected_items[0]
	var bench_member_id: String = String(item_list.get_item_metadata(selected_idx))

	# Get the display name of the bench member being swapped in
	var roster: Dictionary = _read_roster()
	var member_name: String = _label_for_id(bench_member_id, roster)

	print("[StatusPanel] Swapping slot %d with bench member: %s (%s)" % [active_slot, bench_member_id, member_name])

	# Close popup first
	_popup_close_and_return_to_content()

	# Perform swap
	_perform_swap(active_slot, bench_member_id, member_name)

func _popup_cancel_switch() -> void:
	"""User pressed Back on switch popup - close without swapping"""
	print("[StatusPanel] Switch popup cancelled")
	_popup_close_and_return_to_content()

func _popup_close_and_return_to_content() -> void:
	"""Close popup and return to CONTENT state"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	print("[StatusPanel] Closing popup with fade-out, returning to content mode")

	# Store popup reference but DON'T clear _active_popup yet (prevents double-close during fade)
	var popup_to_close = _active_popup

	# Fade out popup, then clean up
	_fade_out_popup(popup_to_close, func():
		# Pop from panel manager FIRST (before freeing)
		var panel_mgr = get_node_or_null("/root/aPanelManager")
		if panel_mgr and panel_mgr.has_method("pop_panel"):
			panel_mgr.call("pop_panel")
			print("[StatusPanel] Popped popup from aPanelManager")

		# NOW clear active popup and change state (after pop completes)
		_active_popup = null
		_nav_state = NavState.CONTENT

		# Free the popup
		if is_instance_valid(popup_to_close):
			popup_to_close.queue_free()

		# Restore focus to first button in content
		call_deferred("_navigate_to_content")
	)

func _show_recovery_popup(member_id: String, member_name: String, hp: int, hp_max: int, mp: int, mp_max: int) -> void:
	"""Show recovery item selection popup - LoadoutPanel pattern"""
	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[StatusPanel] Popup already open, ignoring request")
		return

	# Get inventory system
	var inv_sys = get_node_or_null("/root/aInventorySystem")
	if not inv_sys:
		print("[StatusPanel] No inventory system found")
		return

	# Get recovery items from inventory by filtering item definitions
	var recovery_items: Array = []

	print("[StatusPanel] Using InventorySystem methods: get_item_defs, get_counts_dict, get_count")

	# Get all item definitions
	if inv_sys.has_method("get_item_defs"):
		var all_defs: Dictionary = inv_sys.call("get_item_defs")
		print("[StatusPanel] Total item definitions: %d" % all_defs.size())

		# Get item counts to check what we actually own
		var counts_dict: Dictionary = {}
		if inv_sys.has_method("get_counts_dict"):
			counts_dict = inv_sys.call("get_counts_dict")
			print("[StatusPanel] Total items in inventory: %d" % counts_dict.size())
			print("[StatusPanel] Inventory items: " + str(counts_dict.keys()))

		# Track all unique categories to help debug
		var categories_found: Array = []

		# Filter by category "recovery" and check if we own the item
		for item_id in all_defs.keys():
			var def_data = all_defs[item_id]
			if typeof(def_data) == TYPE_DICTIONARY:
				var category = String(def_data.get("category", "")).to_lower()

				# Track unique categories
				if category != "" and not categories_found.has(category):
					categories_found.append(category)

				# Check if we own this item
				var count = int(counts_dict.get(item_id, 0))
				if count > 0:
					# Log all owned items with their categories
					print("[StatusPanel] Owned item: %s (category: '%s', count: %d)" % [item_id, category, count])

					# Check if this is a recovery item by looking at multiple possible indicators
					var field_effect = String(def_data.get("field_status_effect", "")).to_lower()
					var item_name = String(def_data.get("name", "")).to_lower()
					var description = String(def_data.get("description", "")).to_lower()

					# Print all fields for debugging
					print("[StatusPanel]   field_effect: '%s'" % field_effect)
					print("[StatusPanel]   name: '%s'" % item_name)
					print("[StatusPanel]   description: '%s'" % description)

					# Check multiple conditions for recovery items
					var is_recovery = false

					# Method 1: Check field_status_effect for healing keywords
					if field_effect.contains("heal") or field_effect.contains("restore") or field_effect.contains("recover"):
						if field_effect.contains("hp") or field_effect.contains("mp") or field_effect.contains("health") or field_effect.contains("mana"):
							is_recovery = true
							print("[StatusPanel] ✓ Matched via field_effect")

					# Method 2: Check if category is recovery-related
					if category == "recovery" or category == "healing" or category == "restorative":
						is_recovery = true
						print("[StatusPanel] ✓ Matched via category")

					# Method 3: Check consumables with healing in name/description
					if (category == "consumables" or category == "consumable"):
						if (item_name.contains("potion") or item_name.contains("elixir") or item_name.contains("tonic") or
							description.contains("restore") or description.contains("heal") or description.contains("recover")):
							is_recovery = true
							print("[StatusPanel] ✓ Matched via consumable name/description")

					if is_recovery:
						recovery_items.append(item_id)
						print("[StatusPanel] ✓✓ ADDED as recovery item!")
					else:
						print("[StatusPanel] - Skipped: not a recovery item")

		print("[StatusPanel] All unique categories found: " + str(categories_found))
		print("[StatusPanel] Total recovery items found: %d" % recovery_items.size())

	# Create CanvasLayer to ensure popup is centered on viewport
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)

	# Create popup panel using LoadoutPanel pattern
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.set_anchors_preset(Control.PRESET_CENTER)
	popup_panel.modulate.a = 0.0  # Start fully transparent
	popup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Block input until fade completes
	canvas_layer.add_child(popup_panel)

	# Apply consistent styling (matches ToastPopup)
	_style_popup_panel(popup_panel)

	# Set active popup immediately
	_active_popup = popup_panel

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "Recovery - %s" % member_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Member status display
	var status_label: Label = Label.new()
	status_label.text = "HP: %d/%d  |  MP: %d/%d" % [hp, hp_max, mp, mp_max]
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 200)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(item_list)

	# Populate list with recovery items
	if recovery_items.is_empty():
		item_list.add_item("No recovery items available")
		item_list.set_item_disabled(0, true)
	else:
		for item_id in recovery_items:
			if inv_sys.has_method("get_count") and inv_sys.has_method("get_item_def"):
				var count = inv_sys.call("get_count", item_id)
				var def_data = inv_sys.call("get_item_def", item_id)
				if typeof(def_data) == TYPE_DICTIONARY and count > 0:
					var item_name = String(def_data.get("name", item_id))

					# Determine if HP or MP recovery based on field_status_effect
					var field_effect = String(def_data.get("field_status_effect", "")).to_lower()
					var item_type = "hp" if field_effect.contains("hp") else "mp"

					item_list.add_item("%s (x%d)" % [item_name, count])
					item_list.set_item_metadata(item_list.item_count - 1, {"id": item_id, "type": item_type})
					print("[StatusPanel] Added to popup list: %s (x%d, type: %s)" % [item_name, count, item_type])

	# Add Back button
	var back_btn: Button = Button.new()
	back_btn.text = "BACK"
	back_btn.pressed.connect(_popup_cancel_recovery)
	vbox.add_child(back_btn)

	# Auto-size panel - wait two frames
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[StatusPanel] Recovery popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])
	# Fade in popup
	_fade_in_popup(popup_panel)


	# Store metadata
	popup_panel.set_meta("_is_recovery_popup", true)
	popup_panel.set_meta("_member_id", member_id)
	popup_panel.set_meta("_member_name", member_name)
	popup_panel.set_meta("_hp", hp)
	popup_panel.set_meta("_hp_max", hp_max)
	popup_panel.set_meta("_mp", mp)
	popup_panel.set_meta("_mp_max", mp_max)
	popup_panel.set_meta("_item_list", item_list)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[StatusPanel] Pushed recovery popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	# Select first non-disabled item and grab focus
	if item_list.item_count > 0:
		var first_enabled = 0
		for i in range(item_list.item_count):
			if not item_list.is_item_disabled(i):
				first_enabled = i
				break
		item_list.select(first_enabled)
		await get_tree().process_frame
		item_list.grab_focus()

func _popup_accept_recovery() -> void:
	"""User pressed A/Accept on recovery popup - use selected item"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var item_list = _active_popup.get_meta("_item_list", null)
	var member_id = _active_popup.get_meta("_member_id", "")
	var member_name = _active_popup.get_meta("_member_name", "")
	var hp = _active_popup.get_meta("_hp", 0)
	var hp_max = _active_popup.get_meta("_hp_max", 0)
	var mp = _active_popup.get_meta("_mp", 0)
	var mp_max = _active_popup.get_meta("_mp_max", 0)

	if not item_list:
		print("[StatusPanel] Recovery popup missing item_list")
		_popup_cancel_recovery()
		return

	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		print("[StatusPanel] No item selected")
		return

	var selected_idx = selected_items[0]

	# Check if it's a disabled item (shouldn't happen but be safe)
	if item_list.is_item_disabled(selected_idx):
		print("[StatusPanel] Selected item is disabled")
		return

	var meta = item_list.get_item_metadata(selected_idx)
	if typeof(meta) != TYPE_DICTIONARY:
		print("[StatusPanel] Invalid metadata for selected item")
		return

	var item_id: String = String(meta.get("id", ""))
	var item_type: String = String(meta.get("type", "hp"))

	print("[StatusPanel] Using recovery item: %s (type: %s) on %s" % [item_id, item_type, member_name])

	# Close popup first
	_popup_close_and_return_to_content()

	# Use the item
	_use_recovery_item(member_id, member_name, item_id, item_type, hp, hp_max, mp, mp_max)

func _popup_cancel_recovery() -> void:
	"""User pressed Back on recovery popup - close without using item"""
	print("[StatusPanel] Recovery popup cancelled")
	_popup_close_and_return_to_content()

func _use_recovery_item(member_id: String, member_name: String, item_id: String, item_type: String, hp: int, hp_max: int, mp: int, mp_max: int) -> void:
	"""Use a recovery item on a party member"""
	# Check if already at max
	if item_type == "hp" and hp >= hp_max:
		_show_already_at_max_notice(member_name, "HP")
		return
	elif item_type == "mp" and mp >= mp_max:
		_show_already_at_max_notice(member_name, "MP")
		return

	# Use the item
	var inv_sys = get_node_or_null("/root/aInventorySystem")
	if not inv_sys:
		print("[StatusPanel] ERROR: Inventory system not found")
		return

	# Remove item from inventory (use_item takes id and qty, not target)
	if inv_sys.has_method("use_item"):
		var success = inv_sys.call("use_item", item_id, 1)  # Remove 1 of the item
		if success:
			print("[StatusPanel] Consumed %s from inventory" % item_id)

			# Apply recovery effect to the party member and get the heal result
			var heal_result: Dictionary = _apply_recovery_effect(member_id, member_name, item_id, item_type)

			# Save member_id to restore focus after rebuild
			_focus_member_id = member_id

			# Refresh party display
			_rebuild_party()

			# Show confirmation message
			if heal_result.get("success", false):
				var heal_amount: int = int(heal_result.get("heal_amount", 0))
				var healed_type: String = String(heal_result.get("type", "HP")).to_upper()
				_show_heal_confirmation(member_name, heal_amount, healed_type)
		else:
			var error_popup := AcceptDialog.new()
			error_popup.dialog_text = "Failed to use item - you don't have any."
			error_popup.title = "Use Item Failed"
			add_child(error_popup)
			error_popup.popup_centered()
			error_popup.confirmed.connect(func(): error_popup.queue_free())
	else:
		print("[StatusPanel] ERROR: use_item method not found on InventorySystem")

func _apply_recovery_effect(member_id: String, member_name: String, item_id: String, item_type: String) -> Dictionary:
	"""Apply recovery effect to a party member by restoring HP/MP
	Returns: Dictionary with 'success' (bool), 'heal_amount' (int), and 'type' (String)"""
	print("[StatusPanel] Applying recovery effect: %s to %s (type: %s)" % [item_id, member_name, item_type])

	# Get the item definition to find recovery amount
	var inv_sys = get_node_or_null("/root/aInventorySystem")
	if not inv_sys:
		return {"success": false, "heal_amount": 0, "type": item_type}

	var item_def: Dictionary = {}
	if inv_sys.has_method("get_item_def"):
		item_def = inv_sys.call("get_item_def", item_id)

	# Parse recovery amount from field_status_effect (e.g., "Heal 50 HP" or "Heal 25% MaxHP")
	var field_effect = String(item_def.get("field_status_effect", ""))
	var recovery_amount: int = 50  # Default fallback
	var is_percentage: bool = false

	# Try to extract number from effect string
	var regex = RegEx.new()
	regex.compile("(\\d+)\\s*%")  # Match percentage like "25%"
	var match_pct = regex.search(field_effect)
	if match_pct:
		recovery_amount = int(match_pct.get_string(1))
		is_percentage = true
		print("[StatusPanel] Parsed percentage heal: %d%%" % recovery_amount)
	else:
		regex.compile("(\\d+)\\s*(HP|MP)")  # Match flat amount like "50 HP"
		var match_flat = regex.search(field_effect)
		if match_flat:
			recovery_amount = int(match_flat.get_string(1))
			print("[StatusPanel] Parsed flat heal: %d" % recovery_amount)

	print("[StatusPanel] Recovery: %d%s %s" % [recovery_amount, "%" if is_percentage else "", item_type.to_upper()])

	# Apply effect to GameState.member_data directly
	var actual_heal_amount: int = 0
	if _gs and _gs.has_method("get"):
		var member_data_v = _gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if member_data.has(member_id):
				var member_dict = member_data[member_id]
				if typeof(member_dict) == TYPE_DICTIONARY:
					if item_type == "hp":
						var current_hp = int(member_dict.get("hp", 0))
						var base_max_hp = int(member_dict.get("hp_max", 100))

						# Get TRUE max HP including equipment bonuses (from CombatProfileSystem)
						var max_hp = base_max_hp
						if _cps and _cps.has_method("get_profile"):
							var prof_v: Variant = _cps.call("get_profile", member_id)
							if typeof(prof_v) == TYPE_DICTIONARY:
								var prof: Dictionary = prof_v
								max_hp = int(prof.get("hp_max", base_max_hp))

						print("[StatusPanel] HP Heal Debug - Before:")
						print("  current_hp: %d" % current_hp)
						print("  base_max_hp: %d" % base_max_hp)
						print("  true_max_hp (with equipment): %d" % max_hp)
						print("  recovery_amount: %d" % recovery_amount)

						# Calculate actual heal amount
						var heal_amount = recovery_amount
						if is_percentage:
							heal_amount = int(float(max_hp) * float(recovery_amount) / 100.0)
							print("  percentage heal calculated: %d" % heal_amount)

						var unclamped_hp = current_hp + heal_amount
						print("  unclamped would be: %d" % unclamped_hp)

						# Clamp to TRUE max HP (including equipment bonuses) - never heal over maximum
						var new_hp = min(current_hp + heal_amount, max_hp)
						print("  clamped to: %d (max: %d)" % [new_hp, max_hp])

						actual_heal_amount = new_hp - current_hp
						member_dict["hp"] = new_hp
						print("[StatusPanel] ✓ Restored %d HP to %s (now: %d/%d)" % [actual_heal_amount, member_name, member_dict["hp"], max_hp])

					elif item_type == "mp":
						var current_mp = int(member_dict.get("mp", 0))
						var base_max_mp = int(member_dict.get("mp_max", 100))

						# Get TRUE max MP including equipment bonuses (from CombatProfileSystem)
						var max_mp = base_max_mp
						if _cps and _cps.has_method("get_profile"):
							var prof_v: Variant = _cps.call("get_profile", member_id)
							if typeof(prof_v) == TYPE_DICTIONARY:
								var prof: Dictionary = prof_v
								max_mp = int(prof.get("mp_max", base_max_mp))

						print("[StatusPanel] MP Heal Debug - Before:")
						print("  current_mp: %d" % current_mp)
						print("  base_max_mp: %d" % base_max_mp)
						print("  true_max_mp (with equipment): %d" % max_mp)
						print("  recovery_amount: %d" % recovery_amount)

						# Calculate actual heal amount
						var heal_amount = recovery_amount
						if is_percentage:
							heal_amount = int(float(max_mp) * float(recovery_amount) / 100.0)
							print("  percentage heal calculated: %d" % heal_amount)

						var unclamped_mp = current_mp + heal_amount
						print("  unclamped would be: %d" % unclamped_mp)

						# Clamp to TRUE max MP (including equipment bonuses) - never heal over maximum
						var new_mp = min(current_mp + heal_amount, max_mp)
						print("  clamped to: %d (max: %d)" % [new_mp, max_mp])

						actual_heal_amount = new_mp - current_mp
						member_dict["mp"] = new_mp
						print("[StatusPanel] ✓ Restored %d MP to %s (now: %d/%d)" % [actual_heal_amount, member_name, member_dict["mp"], max_mp])

					# Update the member_data entry
					member_data[member_id] = member_dict

					# CRITICAL: Set the modified dictionary back to GameState for persistence
					if _gs.has_method("set"):
						_gs.set("member_data", member_data)
						print("[StatusPanel] ✓ Persisted changes to GameState.member_data")

					# CRITICAL: Refresh CombatProfileSystem cache so it picks up the new HP/MP values
					if _cps and _cps.has_method("refresh_member"):
						_cps.call("refresh_member", member_id)
						print("[StatusPanel] ✓ Refreshed CombatProfileSystem cache for %s" % member_id)

					return {"success": true, "heal_amount": actual_heal_amount, "type": item_type}

	print("[StatusPanel] WARNING: Could not apply recovery effect - no suitable system found")
	return {"success": false, "heal_amount": 0, "type": item_type}

# Prefer CPS for real-time party pools
func _get_party_snapshot() -> Array:
	if _cps != null and _gs != null and _gs.has_method("get_active_party_ids"):
		var out: Array = []
		var ids_v: Variant = _gs.call("get_active_party_ids")
		var ids: Array = []
		if typeof(ids_v) == TYPE_ARRAY:
			ids = ids_v
		elif typeof(ids_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (ids_v as PackedStringArray): ids.append(String(s))
		if ids.is_empty(): ids = ["hero"]

		for id_any in ids:
			var id: String = String(id_any)
			if not _cps.has_method("get_profile"):
				continue
			var p_v: Variant = _cps.call("get_profile", id)
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var lvl: int = int(p.get("level", 1))
			var hp_cur: int = int(p.get("hp", -1))
			var hp_max: int = int(p.get("hp_max", -1))
			var mp_cur: int = int(p.get("mp", -1))
			var mp_max: int = int(p.get("mp_max", -1))
			var label: String = String(p.get("label", _label_for_id(id)))
			out.append({
				"name": "%s  (Lv %d)" % [label, lvl],
				"hp": hp_cur, "hp_max": hp_max,
				"mp": mp_cur, "mp_max": mp_max
			})
		if out.size() > 0:
			return out

	# Fallbacks
	if _resolver and _resolver.has_method("get_party_snapshots"):
		var r_v: Variant = _resolver.call("get_party_snapshots")
		if typeof(r_v) == TYPE_ARRAY:
			var out_rs: Array = []
			for d_v in (r_v as Array):
				if typeof(d_v) != TYPE_DICTIONARY: continue
				var d: Dictionary = d_v
				var label: String = String(d.get("label", String(d.get("name","Member"))))
				var lvl: int = int(d.get("level", 1))
				var hp_max_i: int = int(d.get("hp_max", -1))
				var mp_max_i: int = int(d.get("mp_max", -1))
				var hp_cur_i: int = (hp_max_i if hp_max_i >= 0 else -1)
				var mp_cur_i: int = (mp_max_i if mp_max_i >= 0 else -1)
				out_rs.append({
					"name": "%s  (Lv %d)" % [label, lvl],
					"hp": hp_cur_i, "hp_max": hp_max_i,
					"mp": mp_cur_i, "mp_max": mp_max_i
				})
			if out_rs.size() > 0:
				return out_rs
	return _build_snapshot_flexible()

# --------------------- Right column summary -------------------

func _update_summary() -> void:
	# Update new bottom-right display
	if _creds_value_label: _creds_value_label.text = _read_creds()
	if _perks_value_label: _perks_value_label.text = _read_perk_points()

	# Update new top-right mission display
	if _mission_value_label:
		var h: String = _read_mission_hint()
		_mission_value_label.text = h if h != "" else "TBD"

	# Keep old labels updated too (they're hidden but may be referenced elsewhere)
	if _creds: _creds.text = _read_creds()
	if _perk:  _perk.text  = _read_perk_points()

	if _morality:
		_morality.text = _read_morality()
		# Color the morality text based on tier
		var morality_sys = get_node_or_null("/root/aMoralitySystem")
		if morality_sys and morality_sys.has_method("get_tier_color"):
			var color: Color = morality_sys.call("get_tier_color")
			_morality.add_theme_color_override("font_color", color)

	var dp: Dictionary = _read_date_phase()
	if _date:  _date.text  = String(dp.get("date_text", "—"))
	if _phase: _phase.text = String(dp.get("phase_text", "—"))

	if _hint:
		var h: String = _read_mission_hint()
		_hint.text = h if h != "" else "[i]TBD[/i]"

# --------------------- Character Preview ----------------------

func _rebuild_appearance() -> void:
	_update_character_preview()

func _update_character_preview() -> void:
	"""Update the character preview with saved variant data"""
	print("[StatusPanel] Updating character preview...")

	if not character_layers:
		print("[StatusPanel] ERROR: character_layers is null!")
		return

	# Get character variants from GameState
	var variants: Dictionary = {}
	if _gs and _gs.has_meta("hero_identity"):
		var id_v: Variant = _gs.get_meta("hero_identity")
		if typeof(id_v) == TYPE_DICTIONARY:
			var id: Dictionary = id_v
			print("[StatusPanel] hero_identity found: ", id.keys())
			if id.has("character_variants"):
				var cv: Variant = id.get("character_variants")
				if typeof(cv) == TYPE_DICTIONARY:
					variants = cv
					print("[StatusPanel] Loaded variants from GameState: ", variants)
			else:
				print("[StatusPanel] No character_variants in hero_identity")
		else:
			print("[StatusPanel] hero_identity is not a dictionary")
	else:
		print("[StatusPanel] No hero_identity meta found in GameState")

	# If no variants saved, try to load from CharacterData autoload
	if variants.is_empty():
		print("[StatusPanel] Trying CharacterData autoload...")
		var char_data = get_node_or_null("/root/aCharacterData")
		if char_data:
			print("[StatusPanel] CharacterData found")
			if char_data.has_method("get"):
				var sv: Variant = char_data.get("selected_variants")
				print("[StatusPanel] selected_variants type: ", typeof(sv))
				if typeof(sv) == TYPE_DICTIONARY:
					variants = sv
					print("[StatusPanel] Loaded variants from CharacterData: ", variants)
			elif char_data.get("selected_variants"):
				var sv2 = char_data.get("selected_variants")
				if typeof(sv2) == TYPE_DICTIONARY:
					variants = sv2
					print("[StatusPanel] Loaded variants from CharacterData (property): ", variants)
		else:
			print("[StatusPanel] CharacterData autoload not found")

	if variants.is_empty():
		print("[StatusPanel] WARNING: No character variants found!")
		return

	# Update each layer sprite
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)

		if layer_key in variants and variants[layer_key] != "":
			var variant_code = variants[layer_key]
			_debug_log("Loading " + str(layer_key) + " with variant: " + str(variant_code))
			var texture_path = _find_character_file(layer_key, variant_code)
			_debug_log("  -> Path: " + str(texture_path))
			if texture_path != "" and FileAccess.file_exists(texture_path):
				var texture = load(texture_path)
				sprite.texture = texture
				sprite.visible = true
				# Set to idle pose (south idle = sprite 1 = frame 0)
				sprite.frame = 0
				_debug_log("  -> Loaded successfully, frame set to " + str(sprite.frame))
			else:
				_debug_log("  -> ERROR: File not found!")
				sprite.texture = null
				sprite.visible = false
		else:
			sprite.texture = null
			sprite.visible = false

func _find_character_file(layer_key: String, variant_code: String) -> String:
	"""Find the character file for a given layer and variant code"""
	if not LAYERS.has(layer_key):
		print("[StatusPanel]     Layer key not found: ", layer_key)
		return ""

	var layer = LAYERS[layer_key]
	for variant in CHAR_VARIANTS:
		var base_path = CHAR_BASE_PATH + variant + "/"
		var layer_path = base_path + (layer.path + "/" if layer.path != "" else "")
		var filename = "%s_%s_%s.png" % [variant, layer.code, variant_code]
		var full_path = layer_path + filename

		print("[StatusPanel]     Trying: ", full_path)
		if FileAccess.file_exists(full_path):
			print("[StatusPanel]     FOUND!")
			return full_path

	print("[StatusPanel]     Not found in any variant")
	return ""

# --------------------- Small helpers -------------------------

func _read_creds() -> String:
	if _gs:
		if _gs.has_method("get_creds"): return str(int(_gs.call("get_creds")))
		if _gs.has_method("get"):
			var v: Variant = _gs.get("creds")
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return str(int(v))
	return "0"

func _read_perk_points() -> String:
	if _st:
		if _st.has_method("get_perk_points"): return str(int(_st.call("get_perk_points")))
		if _st.has_method("get"):
			var v: Variant = _st.get("perk_points")
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return str(int(v))
	if _gs and _gs.has_method("get"):
		var gv: Variant = _gs.get("perk_points")
		if typeof(gv) in [TYPE_INT, TYPE_FLOAT]: return str(int(gv))
	return "0"

func _read_morality() -> String:
	var morality_sys = get_node_or_null("/root/aMoralitySystem")
	if morality_sys:
		var meter: int = 0
		var tier_name: String = "Neutral"

		# Get morality meter value
		if morality_sys.has_method("get"):
			var m_v: Variant = morality_sys.get("morality_meter")
			if typeof(m_v) in [TYPE_INT, TYPE_FLOAT]:
				meter = int(m_v)

		# Get tier name
		if morality_sys.has_method("get_tier_name"):
			tier_name = String(morality_sys.call("get_tier_name"))

		return "%s (%+d)" % [tier_name, meter]
	return "Neutral (0)"

func _read_date_phase() -> Dictionary:
	var out: Dictionary = {}
	if _cal:
		if _cal.has_method("get_date_string"): out["date_text"] = String(_cal.call("get_date_string"))
		if _cal.has_method("get_phase_name"):   out["phase_text"] = String(_cal.call("get_phase_name"))
	if not out.has("date_text"): out["date_text"] = "—"
	if not out.has("phase_text"): out["phase_text"] = "—"
	return out

func _read_mission_hint() -> String:
	if _mes:
		if _mes.has_method("get_current_hint"):
			var h2: String = String(_mes.call("get_current_hint"))
			if h2 != "": return h2
		if _mes.has_method("get_current_title"):
			var t: String = String(_mes.call("get_current_title"))
			if t != "": return t
	if _gs:
		if _gs.has_method("get_mission_hint"): return String(_gs.call("get_mission_hint"))
		if _gs.has_method("get"):
			var v: Variant = _gs.get("mission_hint")
			if typeof(v) == TYPE_STRING: return String(v)
	return ""

func _on_event_changed(_id: String) -> void:
	var h: String = _read_mission_hint()

	# Update new top-right mission display
	if _mission_value_label:
		_mission_value_label.text = h if h != "" else "TBD"

	# Update old hint label
	if _hint:
		_hint.text = h if h != "" else "[i]TBD[/i]"

func _fmt_pair(a: int, b: int) -> String:
	return "%d / %d" % [a, b] if a >= 0 and b > 0 else "—"

# --------------------- Party snapshot fallbacks -------------------

func _build_snapshot_flexible() -> Array:
	var out: Array = []
	var roster: Dictionary = _read_roster()
	var entries: Array = _gather_active_entries(roster)

	for e_v in entries:
		if typeof(e_v) != TYPE_DICTIONARY: continue
		var e: Dictionary = e_v
		var pid: String = String(e.get("key",""))
		var label: String = String(e.get("label",""))

		var resolved: Dictionary = _resolve_member_stats(pid, label)
		var disp_name: String = String(resolved.get("name", (label if label != "" else pid)))
		var lvl: int = int(resolved.get("level", 1))
		var vtl: int = int(resolved.get("VTL", 1))
		var fcs: int = int(resolved.get("FCS", 1))

		var hp_max_i: int = _calc_max_hp(lvl, vtl)
		var mp_max_i: int = _calc_max_mp(lvl, fcs)
		var hp_cur_i: int = clamp(int(resolved.get("hp_cur", hp_max_i)), 0, hp_max_i)
		var mp_cur_i: int = clamp(int(resolved.get("mp_cur", mp_max_i)), 0, mp_max_i)

		out.append({
			"name": "%s  (Lv %d)" % [disp_name, lvl],
			"hp": hp_cur_i, "hp_max": hp_max_i,
			"mp": mp_cur_i, "mp_max": mp_max_i
		})

	if out.is_empty():
		var nm2: String = _safe_hero_name()
		var lvl2: int = _safe_hero_level()
		var mh: int = _calc_max_hp(lvl2, 1)
		var mm: int = _calc_max_mp(lvl2, 1)
		out.append({"name":"%s  (Lv %d)" % [nm2, lvl2], "hp": mh, "hp_max": mh, "mp": mm, "mp_max": mm})
	return out

# ---------- CSV cache + per-member resolution ----------------

func _load_party_csv_cache() -> void:
	_csv_by_id.clear()
	_name_to_id.clear()

	# Preferred: CSV autoload
	_csv = (_csv if _csv != null else get_node_or_null(CSV_PATH))
	if _csv and _csv.has_method("load_csv"):
		var defs_v: Variant = _csv.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			for id_any in defs.keys():
				var rid: String = String(id_any)
				var row: Dictionary = defs[rid]
				_csv_by_id[rid] = row
				var n_v: Variant = row.get("name", "")
				if typeof(n_v) == TYPE_STRING:
					var key: String = String(n_v).strip_edges().to_lower()
					if key != "": _name_to_id[key] = rid
			return

	# Manual fallback
	if not FileAccess.file_exists(PARTY_CSV):
		return
	var f := FileAccess.open(PARTY_CSV, FileAccess.READ)
	if f == null: return
	if f.eof_reached():
		f.close()
		return

	var header: PackedStringArray = f.get_csv_line()
	var idx_id: int = header.find("actor_id")
	var idx_name: int = header.find("name")
	while not f.eof_reached():
		var row_psa: PackedStringArray = f.get_csv_line()
		if row_psa.is_empty(): continue
		var rid2: String = (String(row_psa[idx_id]) if idx_id >= 0 and idx_id < row_psa.size() else "")
		var nm2: String  = (String(row_psa[idx_name]) if idx_name >= 0 and idx_name < row_psa.size() else "")
		var row_dict: Dictionary = {}
		for i in range(header.size()):
			row_dict[String(header[i])] = (row_psa[i] if i < row_psa.size() else "")
		if rid2 != "":
			_csv_by_id[rid2] = row_dict
		if nm2.strip_edges() != "":
			_name_to_id[nm2.strip_edges().to_lower()] = rid2
	f.close()

func _read_roster() -> Dictionary:
	var roster: Dictionary = {}
	if _party_sys:
		if _party_sys.has_method("get"):
			var r_v: Variant = _party_sys.get("roster")
			if typeof(r_v) == TYPE_DICTIONARY: roster = r_v as Dictionary
		if roster.is_empty() and _party_sys.has_method("get_roster"):
			var r2_v: Variant = _party_sys.call("get_roster")
			if typeof(r2_v) == TYPE_DICTIONARY: roster = r2_v as Dictionary
	return roster

func _label_for_id(pid: String, roster: Dictionary = {}) -> String:
	if pid == "hero": return _safe_hero_name()
	if roster.has(pid):
		var rec: Dictionary = roster[pid]
		if rec.has("name") and typeof(rec["name"]) == TYPE_STRING and String(rec["name"]).strip_edges() != "":
			return String(rec["name"])
	# CSV fallback
	if _csv_by_id.has(pid):
		var row: Dictionary = _csv_by_id[pid]
		var nm: String = String(row.get("name",""))
		if nm != "": return nm
	return (pid.capitalize() if pid != "" else "")

func _gather_active_entries(roster: Dictionary) -> Array:
	var entries: Array = []

	if _gs and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		for s in _array_from_any(v):
			var pid := String(s)
			entries.append({"key": pid, "label": _label_for_id(pid, roster)})
		if entries.size() > 0: return entries

	if _gs and _gs.has_method("get"):
		var p_v: Variant = _gs.get("party")
		for s3 in _array_from_any(p_v):
			var pid3 := String(s3)
			entries.append({"key": pid3, "label": _label_for_id(pid3, roster)})
		if entries.size() > 0: return entries

	if _party_sys:
		for m in ["get_active_party","get_party","list_active_members","list_party","get_active"]:
			if _party_sys.has_method(m):
				var r: Variant = _party_sys.call(m)
				for s4 in _array_from_any(r):
					var pid4 := String(s4)
					entries.append({"key": pid4, "label": _label_for_id(pid4, roster)})
				if entries.size() > 0: return entries
		for prop in ["active","party"]:
			if _party_sys.has_method("get"):
				var a_v: Variant = _party_sys.get(prop)
				for s5 in _array_from_any(a_v):
					var pid5 := String(s5)
					entries.append({"key": pid5, "label": _label_for_id(pid5, roster)})
				if entries.size() > 0: return entries

	entries.append({"key":"hero","label":_safe_hero_name()})
	return entries

func _array_from_any(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY: return v as Array
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		var out: Array = []
		for s in (v as PackedStringArray): out.append(String(s))
		return out
	return []

# ---- per-member resolution & misc ------------------------------------

func _resolve_member_stats(pid_in: String, label_in: String) -> Dictionary:
	if pid_in == "hero":
		var lvl: int = _safe_hero_level()
		var vtl: int = 1
		var fcs: int = 1
		if _st and _st.has_method("get_stat"):
			var v_v: Variant = _st.call("get_stat", "VTL")
			if typeof(v_v) in [TYPE_INT, TYPE_FLOAT]: vtl = int(v_v)
			var f_v: Variant = _st.call("get_stat", "FCS")
			if typeof(f_v) in [TYPE_INT, TYPE_FLOAT]: fcs = int(f_v)
		return {"name": _safe_hero_name(), "level": max(1,lvl), "VTL": max(1,vtl), "FCS": max(1,fcs)}

	var pid: String = pid_in
	if pid == "" and label_in.strip_edges() != "":
		var key: String = label_in.strip_edges().to_lower()
		if _name_to_id.has(key): pid = String(_name_to_id[key])

	var row: Dictionary = _csv_by_id.get(pid, {}) as Dictionary
	if row.is_empty() and label_in.strip_edges() != "":
		var key2: String = label_in.strip_edges().to_lower()
		if _name_to_id.has(key2):
			var pid2: String = String(_name_to_id[key2])
			row = _csv_by_id.get(pid2, {}) as Dictionary

	var lvl_csv: int = _to_int(row.get("level_start", 1))
	var vtl_csv: int = _to_int(row.get("start_vtl", 1))
	var fcs_csv: int = _to_int(row.get("start_fcs", 1))
	var nm: String = (String(row.get("name","")) if row.has("name") else (label_in if label_in != "" else pid_in))

	return {"name": (nm if nm != "" else (label_in if label_in != "" else pid_in)), "level": max(1,lvl_csv), "VTL": max(1,vtl_csv), "FCS": max(1,fcs_csv)}

func _to_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT: return int(v)
		TYPE_FLOAT: return int(round(float(v)))
		TYPE_STRING:
			var s := String(v).strip_edges()
			if s == "": return 0
			return int(s.to_int())
		_: return 0

func _calc_max_hp(level: int, vtl: int) -> int:
	return 150 + (max(1, vtl) * max(1, level) * 6)

func _calc_max_mp(level: int, fcs: int) -> int:
	return 20 + int(round(1.5 * float(max(1, fcs)) * float(max(1, level))))

func _safe_hero_name() -> String:
	if _gs and _gs.has_method("get"):
		var v: Variant = _gs.get("player_name")
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	return "Player"

func _safe_hero_level() -> int:
	if _st:
		if _st.has_method("get_stat"):
			var v: Variant = _st.call("get_stat","LVL")
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return int(v)
		if _st.has_method("get_member_level"):
			var v2: Variant = _st.call("get_member_level","hero")
			if typeof(v2) in [TYPE_INT, TYPE_FLOAT]: return int(v2)
	return 1

# --------------------- Dev dump/hotkey ------------------------

func _on_visibility_changed() -> void:
	# Select tab when panel becomes visible
	if visible and _tab_buttons.size() > 0:
		# Wait for slide animation to complete (0.5s) before applying selection
		await get_tree().create_timer(0.5).timeout

		# Now apply the correct selection after slide completes - stay on menu, don't navigate away
		if visible and _tab_buttons.size() > 0:  # Check still visible
			var index_to_select = _last_selected_tab_index
			if index_to_select >= _tab_buttons.size():
				index_to_select = 0  # Fallback if index is out of bounds
			_selected_button_index = index_to_select
			_update_button_selection()
			if is_instance_valid(_tab_buttons[index_to_select]):
				_tab_buttons[index_to_select].grab_focus()

	if not OS.is_debug_build(): return
	_dev_dump_profiles()

func _grab_tab_list_focus() -> void:
	"""Helper to grab focus on first tab button"""
	if _tab_buttons.size() > 0:
		# Restore last selected tab instead of always selecting first tab
		var index_to_select = _last_selected_tab_index
		if index_to_select >= _tab_buttons.size():
			index_to_select = 0  # Fallback if index is out of bounds
		_selected_button_index = index_to_select
		_update_button_selection()
		if is_instance_valid(_tab_buttons[index_to_select]):
			_tab_buttons[index_to_select].grab_focus()

func _navigate_to_content() -> void:
	"""Navigate from tab list to first focusable button in content area"""
	print("[StatusPanel] _navigate_to_content called, current state: %s" % NavState.keys()[_nav_state])

	if not _party:
		print("[StatusPanel] ERROR: _party is null!")
		return

	# Find all buttons in the content area (recursively search children)
	var buttons: Array[Button] = []
	_find_buttons_recursive(_party, buttons)

	print("[StatusPanel] Found %d buttons in content area" % buttons.size())
	for i in range(buttons.size()):
		print("[StatusPanel]   Button %d: %s" % [i, buttons[i].text])

	# If we have a specific member to focus (after using recovery item), find that button
	if _focus_member_id != "":
		print("[StatusPanel] Looking for Recovery button for member: %s" % _focus_member_id)
		for i in range(buttons.size()):
			var btn = buttons[i]
			if btn.text == "Recovery" and btn.has_meta("member_id"):
				var btn_member_id = String(btn.get_meta("member_id", ""))
				if btn_member_id == _focus_member_id:
					btn.grab_focus()
					_last_focused_content_button_index = i  # Remember this position
					print("[StatusPanel] ✓ Restored focus to Recovery button for %s (index %d)" % [_focus_member_id, i])
					_focus_member_id = ""  # Clear the focus target
					return
		print("[StatusPanel] WARNING: Could not find Recovery button for %s, using last position" % _focus_member_id)
		_focus_member_id = ""  # Clear the focus target

	# Focus the last focused button (or first if index is invalid)
	if buttons.size() > 0:
		var index_to_focus = mini(_last_focused_content_button_index, buttons.size() - 1)
		buttons[index_to_focus].grab_focus()
		print("[StatusPanel] ✓ Navigated to content - focused button %d: %s" % [index_to_focus, buttons[index_to_focus].text])
	else:
		print("[StatusPanel] WARNING: No buttons found in content area")

func _find_buttons_recursive(node: Node, buttons: Array[Button]) -> void:
	"""Recursively find all Button nodes in a tree"""
	if node is Button:
		buttons.append(node as Button)

	for child in node.get_children():
		_find_buttons_recursive(child, buttons)

func _input(event: InputEvent) -> void:
	"""Handle controller input - LoadoutPanel pattern with state machine

	State Flow:
	  MENU → (Right) → CONTENT → (Recovery/Switch btn) → POPUP_ACTIVE
	  POPUP_ACTIVE → (Accept/Back) → CONTENT
	  CONTENT → (Left) → MENU
	  MENU → (Back) → Pop panel (exit StatusPanel)
	"""

	# STATE 1: POPUP_ACTIVE - Handle even when not visible (popup is on top in panel stack)
	if _nav_state == NavState.POPUP_ACTIVE:
		_handle_popup_input(event)
		# NOTE: _handle_popup_input decides which inputs to mark as handled
		return

	# Only handle other states when visible
	if not visible or not _tab_list:
		return

	# Check if we're in MENU_MAIN context
	if _ctrl_mgr and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.MENU_MAIN:
		return

	# STATE 2: MENU - Tab list navigation
	if _nav_state == NavState.MENU:
		_handle_menu_input(event)
		return

	# STATE 3: CONTENT - Content buttons navigation
	if _nav_state == NavState.CONTENT:
		_handle_content_input(event)
		return

## ─────────────────────── STATE 1: POPUP_ACTIVE ───────────────────────

func _handle_popup_input(event: InputEvent) -> void:
	"""Handle input when popup is active (switch, recovery, notice, heal confirmation, or swap confirmation popup)"""
	if event.is_action_pressed("menu_accept"):
		# Route to appropriate handler based on popup type
		# Note: ToastPopup handles its own input, so we only handle custom popups here
		if _active_popup and _active_popup.get_meta("_is_recovery_popup", false):
			_popup_accept_recovery()
			get_viewport().set_input_as_handled()
		elif _active_popup and _active_popup.get_meta("_is_switch_popup", false):
			_popup_accept_switch()
			get_viewport().set_input_as_handled()
		elif _active_popup and _active_popup.name == "MemberActionMenu":
			# Handle accept for action menu - activate focused button
			var focused_control = get_viewport().gui_get_focus_owner()
			if focused_control is Button:
				print("[StatusPanel] Activating action menu button: %s" % (focused_control as Button).text)
				(focused_control as Button).emit_signal("pressed")
				get_viewport().set_input_as_handled()
		# Notice, heal confirmation, and swap confirmation now use ToastPopup (self-handling)
	elif event.is_action_pressed("menu_back"):
		# Cancel popup - all popups can be cancelled with back
		# Note: ToastPopup handles its own input, so we only handle custom popups here
		if _active_popup and _active_popup.get_meta("_is_recovery_popup", false):
			_popup_cancel_recovery()
			get_viewport().set_input_as_handled()
		elif _active_popup and _active_popup.get_meta("_is_switch_popup", false):
			_popup_cancel_switch()
			get_viewport().set_input_as_handled()
		elif _active_popup and _active_popup.name == "MemberActionMenu":
			# Handle back for action menu - close it
			_close_member_action_menu(_active_popup)
			get_viewport().set_input_as_handled()
		# Notice, heal confirmation, and swap confirmation now use ToastPopup (self-handling)
	# UP/DOWN navigation is NOT handled - let ItemList/Button handle it

## ─────────────────────── STATE 2: MENU ───────────────────────

func _handle_menu_input(event: InputEvent) -> void:
	"""Handle input in MENU state - tab button navigation"""
	# Handle UP/DOWN with wrap-around
	if event.is_action_pressed("move_up"):
		if _tab_buttons.size() > 0:
			# Check if any tab button has focus
			var has_focus = false
			for btn in _tab_buttons:
				if btn.has_focus():
					has_focus = true
					break

			if has_focus:
				# Move to previous button with wrap-around
				_selected_button_index -= 1
				if _selected_button_index < 0:
					_selected_button_index = _tab_buttons.size() - 1
				_update_button_selection()
				if is_instance_valid(_tab_buttons[_selected_button_index]):
					_tab_buttons[_selected_button_index].grab_focus()
				get_viewport().set_input_as_handled()
				return

	elif event.is_action_pressed("move_down"):
		if _tab_buttons.size() > 0:
			# Check if any tab button has focus
			var has_focus = false
			for btn in _tab_buttons:
				if btn.has_focus():
					has_focus = true
					break

			if has_focus:
				# Move to next button with wrap-around
				_selected_button_index += 1
				if _selected_button_index >= _tab_buttons.size():
					_selected_button_index = 0
				_update_button_selection()
				if is_instance_valid(_tab_buttons[_selected_button_index]):
					_tab_buttons[_selected_button_index].grab_focus()
				get_viewport().set_input_as_handled()
				return

	# Handle RIGHT: navigate to content (no longer hiding menu)
	if event.is_action_pressed("move_right"):
		# Check if any tab button has focus
		var has_tab_button_focus = false
		for btn in _tab_buttons:
			if btn.has_focus():
				has_tab_button_focus = true
				break

		# If tab button has focus, navigate to first button in content area
		if has_tab_button_focus:
			print("[StatusPanel] MENU → CONTENT transition (keeping menu visible)")
			_nav_state = NavState.CONTENT
			# Don't hide menu anymore - keep it visible
			_navigate_to_content()
			get_viewport().set_input_as_handled()
			return

	# Handle LEFT: show menu if hidden
	elif event.is_action_pressed("move_left"):
		if not _menu_visible:
			print("[StatusPanel] Showing menu (MENU state, LEFT pressed)")
			_show_menu()
			get_viewport().set_input_as_handled()
			return

	# Handle BACK: only close panel if menu is visible
	elif event.is_action_pressed("menu_back"):
		if _menu_visible:
			print("[StatusPanel] Back pressed in MENU state with menu visible - allowing panel close")
			# Don't mark as handled - let GameMenu close the panel
		else:
			print("[StatusPanel] Back pressed in MENU state but menu hidden - showing menu first")
			_show_menu()
			get_viewport().set_input_as_handled()
			return

## ─────────────────────── STATE 3: CONTENT ───────────────────────

func _handle_content_input(event: InputEvent) -> void:
	"""Handle input in CONTENT state - button navigation"""
	# Handle LEFT/RIGHT: Check if focused button has focus neighbors first
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		var focused_control = get_viewport().gui_get_focus_owner()
		if focused_control is Button:
			# Check if button has a focus neighbor in the pressed direction
			if event.is_action_pressed("move_left"):
				var left_neighbor_path = focused_control.focus_neighbor_left
				if left_neighbor_path != NodePath(""):
					# Has a left neighbor - let Godot's focus system handle it
					print("[StatusPanel] Button has left neighbor, using focus navigation")
					return
				else:
					# No left neighbor - navigate back to menu
					print("[StatusPanel] CONTENT → MENU transition (showing menu)")
					_nav_state = NavState.MENU
					# Focus on selected tab button
					if _tab_buttons.size() > 0 and is_instance_valid(_tab_buttons[_selected_button_index]):
						_tab_buttons[_selected_button_index].grab_focus()
					get_viewport().set_input_as_handled()
					return
			elif event.is_action_pressed("move_right"):
				var right_neighbor_path = focused_control.focus_neighbor_right
				if right_neighbor_path != NodePath(""):
					# Has a right neighbor - let Godot's focus system handle it
					print("[StatusPanel] Button has right neighbor, using focus navigation")
					return

	# Handle BACK: go to menu (don't close panel)
	if event.is_action_pressed("menu_back"):
		print("[StatusPanel] Back pressed in CONTENT state - going to MENU")
		_nav_state = NavState.MENU
		# Focus on selected tab button
		if _tab_buttons.size() > 0 and is_instance_valid(_tab_buttons[_selected_button_index]):
			_tab_buttons[_selected_button_index].grab_focus()
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	"""Handle A button activation for tabs and buttons"""
	# Don't handle if in popup state
	if _nav_state == NavState.POPUP_ACTIVE:
		return

	# Only handle when visible
	if not visible:
		return

	# Check if we're in MENU_MAIN context
	if _ctrl_mgr and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.MENU_MAIN:
		return

	# Handle A button
	if event.is_action_pressed("menu_accept"):
		print("[StatusPanel] A button pressed, state: %s" % NavState.keys()[_nav_state])

		# STATE: CONTENT - Activate focused button (Recovery/Switch)
		if _nav_state == NavState.CONTENT:
			var focused_control = get_viewport().gui_get_focus_owner()
			print("[StatusPanel] Focused control: %s (is Button: %s)" % [
				focused_control.name if focused_control else "null",
				focused_control is Button
			])
			if focused_control is Button:
				# Find and store the index of the activated button
				var buttons: Array[Button] = []
				_find_buttons_recursive(_party, buttons)
				for i in range(buttons.size()):
					if buttons[i] == focused_control:
						_last_focused_content_button_index = i
						print("[StatusPanel] ✓ Activating focused button %d: %s" % [i, (focused_control as Button).text])
						break
				(focused_control as Button).emit_signal("pressed")
				get_viewport().set_input_as_handled()
				return
			else:
				print("[StatusPanel] WARNING: A pressed but no button has focus")

		# STATE: MENU - Activate selected tab button
		elif _nav_state == NavState.MENU:
			# Check if any tab button has focus
			for i in range(_tab_buttons.size()):
				if _tab_buttons[i].has_focus():
					print("[StatusPanel] A button - confirming tab button: %d" % i)
					_on_tab_button_pressed(i)
					get_viewport().set_input_as_handled()
					return

	# Debug key handling (F9 to dump profiles)
	if not OS.is_debug_build(): return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var ek := event as InputEventKey
		if ek.keycode == KEY_F9:
			_dev_dump_profiles()

func _hide_menu() -> void:
	"""Slide menu to the left (hide it) and show vertical MENU label"""
	if not _tab_column or not _menu_visible:
		return

	_menu_visible = false

	# Cancel any ongoing tween
	if _menu_tween and _menu_tween.is_running():
		_menu_tween.kill()

	# Create new tween for smooth slide-out animation
	_menu_tween = create_tween()
	_menu_tween.set_ease(Tween.EASE_OUT)
	_menu_tween.set_trans(Tween.TRANS_CUBIC)

	# Slide menu column to the left (hide it)
	# custom_minimum_size.x is 160, so we move it -176 (160 + 16 separation)
	_menu_tween.tween_property(_tab_column, "position:x", -176.0, 0.3)
	_menu_tween.parallel().tween_property(_tab_column, "modulate:a", 0.0, 0.3)

	# Show vertical MENU box (fade in)
	if _vertical_menu_box:
		_menu_tween.parallel().tween_property(_vertical_menu_box, "modulate:a", 1.0, 0.3)

	# Center the status panels by shifting root container left
	# Move left by 88 pixels (half of 176) to center: offset_left from 16 to -72
	if _root_container:
		_menu_tween.parallel().tween_property(_root_container, "position:x", -88.0, 0.3)

	# After animation completes, make menu non-interactive
	_menu_tween.tween_callback(func():
		_tab_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

	print("[StatusPanel] Menu hidden, vertical label shown, panels centered")

func _show_menu() -> void:
	"""Slide menu back from the left (show it) and hide vertical MENU label"""
	if not _tab_column or _menu_visible:
		return

	_menu_visible = true

	# Make interactive immediately
	_tab_column.mouse_filter = Control.MOUSE_FILTER_STOP

	# Cancel any ongoing tween
	if _menu_tween and _menu_tween.is_running():
		_menu_tween.kill()

	# Create new tween for smooth slide-in animation
	_menu_tween = create_tween()
	_menu_tween.set_ease(Tween.EASE_OUT)
	_menu_tween.set_trans(Tween.TRANS_CUBIC)

	# Slide menu column back to original position (x = 0)
	_menu_tween.tween_property(_tab_column, "position:x", 0.0, 0.3)
	_menu_tween.parallel().tween_property(_tab_column, "modulate:a", 1.0, 0.3)

	# Hide vertical MENU box (fade out)
	if _vertical_menu_box:
		_menu_tween.parallel().tween_property(_vertical_menu_box, "modulate:a", 0.0, 0.3)

	# Restore status panels to original position
	# Move root container back to position x = 0
	if _root_container:
		_menu_tween.parallel().tween_property(_root_container, "position:x", 0.0, 0.3)

	# After animation completes, restore focus to tab list
	_menu_tween.tween_callback(func():
		call_deferred("_grab_tab_list_focus")
	)

	print("[StatusPanel] Menu shown, vertical label hidden, panels restored")

func _dev_dump_profiles() -> void:
	print_rich("[b]=== Combat Profiles (StatusPanel) ===[/b]")
	var entries: Array = _gather_active_entries(_read_roster())
	var labels: Array = []
	for e_v in entries:
		if typeof(e_v) == TYPE_DICTIONARY:
			labels.append(String((e_v as Dictionary).get("label","")))
	print("[StatusPanel] active entries: %s" % [String(", ").join(labels)])

	if _cps and _cps.has_method("get_profile"):
		for e_v in entries:
			if typeof(e_v) != TYPE_DICTIONARY: continue
			var pid: String = String((e_v as Dictionary).get("key",""))
			var p_v: Variant = _cps.call("get_profile", pid)
			if typeof(p_v) != TYPE_DICTIONARY: continue
			var p: Dictionary = p_v
			var mind: Dictionary = p.get("mind", {}) as Dictionary
			var mind_str: String = String(mind.get("active", mind.get("base","—")))
			print("%s | Lv %d | HP %d/%d MP %d/%d | mind %s"
				% [ _label_for_id(pid), int(p.get("level",1)),
					int(p.get("hp",0)), int(p.get("hp_max",0)),
					int(p.get("mp",0)), int(p.get("mp_max",0)),
					mind_str ])
