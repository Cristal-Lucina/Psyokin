extends PanelBase
class_name IndexPanel

## IndexPanel (MVP, backed by aIndexSystem when present)
## Categories: Tutorial / Enemies / Past Missions / Locations / World History
##
## ARCHITECTURE:
## - Extends PanelBase for lifecycle management
## - Filter-based navigation (no NavState needed - buttons handle focus)
## - No popups needed (display only)
## - Reactive to IndexSystem signals

enum Filter { TUTORIALS, ENEMIES, MISSIONS, LOCATIONS, LORE }

# Panel animation settings
const BASE_LEFT_RATIO := 2.0
const BASE_CENTER_RATIO := 3.5
const BASE_RIGHT_RATIO := 4.5
const ACTIVE_SCALE := 1.10  # Active panel grows by 10%
const INACTIVE_SCALE := 0.95  # Inactive panels shrink by 5%
const ANIM_DURATION := 0.2  # Animation duration in seconds

# Panel references (for animation)
@onready var _category_panel: PanelContainer = get_node("%CategoryPanel") if has_node("%CategoryPanel") else null
@onready var _content_panel: PanelContainer = get_node("%ContentPanel") if has_node("%ContentPanel") else null
@onready var _details_panel: PanelContainer = get_node("%DetailsPanel") if has_node("%DetailsPanel") else null

@onready var _category_list : ItemList      = $Root/CategoryPanel/CategoryColumn/CategoryList
@onready var _entry_list    : ItemList      = $Root/ContentPanel/ContentColumn/EntryList
@onready var _detail        : RichTextLabel = $Root/DetailsPanel/DetailsColumn/Detail

# Header labels
@onready var _category_label: Label = $Root/CategoryPanel/CategoryColumn/CategoryLabel
@onready var _content_label: Label = $Root/ContentPanel/ContentColumn/ContentLabel
@onready var _details_label: Label = $Root/DetailsPanel/DetailsColumn/DetailsLabel

# Selection arrow for category list only
var _category_arrow: Label = null

# Focus tracking
var _focus_mode: String = "category"  # "category" or "entries"

func _ready() -> void:
	super()  # Call PanelBase._ready() for lifecycle management

	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	# Populate category list once
	if _category_list.item_count == 0:
		_category_list.add_item("Tutorial")
		_category_list.set_item_metadata(0, Filter.TUTORIALS)
		_category_list.add_item("Enemies")
		_category_list.set_item_metadata(1, Filter.ENEMIES)
		_category_list.add_item("Past Missions")
		_category_list.set_item_metadata(2, Filter.MISSIONS)
		_category_list.add_item("Locations")
		_category_list.set_item_metadata(3, Filter.LOCATIONS)
		_category_list.add_item("World History")
		_category_list.set_item_metadata(4, Filter.LORE)
		_category_list.select(0)

	if not _category_list.item_selected.is_connected(_on_category_selected):
		_category_list.item_selected.connect(_on_category_selected)
	if not _category_list.item_activated.is_connected(_on_category_activated):
		_category_list.item_activated.connect(_on_category_activated)

	# Connect entry list signals
	if not _entry_list.item_selected.is_connected(_on_entry_selected):
		_entry_list.item_selected.connect(_on_entry_selected)

	# Enable hover detection by connecting to gui_input
	_entry_list.mouse_filter = Control.MOUSE_FILTER_PASS
	if not _entry_list.gui_input.is_connected(_on_entry_list_gui_input):
		_entry_list.gui_input.connect(_on_entry_list_gui_input)

	# Live updates if the system emits changes (use safe lookup, no direct symbol)
	var idx: Node = get_node_or_null("/root/aIndexSystem")
	if idx and idx.has_signal("index_changed"):
		idx.connect("index_changed", Callable(self, "_on_index_changed"))

	_apply_core_vibe_styling()
	_create_category_arrow()

	_rebuild()

	# Position arrow after rebuild
	await get_tree().process_frame
	_update_category_arrow()

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to IndexPanel (matching LoadoutPanel)"""

	# Style the three main panel containers with rounded neon borders
	# Note: No content_margin here - scene already has VBoxContainers with separation
	if _category_panel:
		var cat_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (categories)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		cat_style.content_margin_left = 10
		cat_style.content_margin_top = 10
		cat_style.content_margin_right = 10
		cat_style.content_margin_bottom = 10
		_category_panel.add_theme_stylebox_override("panel", cat_style)

	if _content_panel:
		var content_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_GRAPE_VIOLET,        # Grape Violet border (entries)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		content_style.content_margin_left = 10
		content_style.content_margin_top = 10
		content_style.content_margin_right = 10
		content_style.content_margin_bottom = 10
		_content_panel.add_theme_stylebox_override("panel", content_style)

	if _details_panel:
		var details_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (details)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		details_style.content_margin_left = 10
		details_style.content_margin_top = 10
		details_style.content_margin_right = 10
		details_style.content_margin_bottom = 10
		_details_panel.add_theme_stylebox_override("panel", details_style)

	# Style header labels (Bubble Magenta, 16px - matching LoadoutPanel)
	if _category_label:
		aCoreVibeTheme.style_label(_category_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)
	if _content_label:
		aCoreVibeTheme.style_label(_content_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)
	if _details_label:
		aCoreVibeTheme.style_label(_details_label, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, 16)

	# Style category list (matching LoadoutPanel party list)
	if _category_list:
		_category_list.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_category_list.add_theme_color_override("font_selected_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_category_list.add_theme_color_override("font_hovered_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_category_list.add_theme_font_size_override("font_size", 18)
		_category_list.z_index = 200  # Above arrow and box at 100
		# Remove all borders and backgrounds
		var empty_stylebox = StyleBoxEmpty.new()
		_category_list.add_theme_stylebox_override("panel", empty_stylebox)
		_category_list.add_theme_stylebox_override("focus", empty_stylebox)
		_category_list.add_theme_stylebox_override("selected", empty_stylebox)
		_category_list.add_theme_stylebox_override("selected_focus", empty_stylebox)
		_category_list.add_theme_stylebox_override("cursor", empty_stylebox)
		_category_list.add_theme_stylebox_override("cursor_unfocused", empty_stylebox)

	# Style entry list (matching LoadoutPanel party list)
	if _entry_list:
		_entry_list.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_entry_list.add_theme_color_override("font_selected_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_entry_list.add_theme_color_override("font_hovered_color", aCoreVibeTheme.COLOR_SKY_CYAN)
		_entry_list.add_theme_font_size_override("font_size", 18)
		_entry_list.z_index = 200  # Above arrow and box at 100
		# Remove all borders and backgrounds
		var empty_stylebox = StyleBoxEmpty.new()
		_entry_list.add_theme_stylebox_override("panel", empty_stylebox)
		_entry_list.add_theme_stylebox_override("focus", empty_stylebox)
		_entry_list.add_theme_stylebox_override("selected", empty_stylebox)
		_entry_list.add_theme_stylebox_override("selected_focus", empty_stylebox)
		_entry_list.add_theme_stylebox_override("cursor", empty_stylebox)
		_entry_list.add_theme_stylebox_override("cursor_unfocused", empty_stylebox)

	# Style details text
	if _detail:
		_detail.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)

# --- PanelBase Lifecycle Overrides ---------------------------------------------

func _input(event: InputEvent) -> void:
	"""Handle input with wrap-around navigation"""
	if not visible:
		return

	# Disable left/right presses
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		return

	# Handle wrap-around navigation for up/down
	if _focus_mode == "category":
		if event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
			_navigate_category_up()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
			_navigate_category_down()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("menu_accept"):
			print("[IndexPanel] menu_accept pressed in category mode")
			# Move to entry list if available
			if _entry_list and _entry_list.item_count > 0:
				_focus_mode = "entries"
				_entry_list.grab_focus()
				if _entry_list.item_count > 0:
					_entry_list.select(0)
					_on_entry_selected(0)
				print("[IndexPanel] Calling _animate_panel_focus - mode: entries")
				call_deferred("_animate_panel_focus")
				get_viewport().set_input_as_handled()
				return
	elif _focus_mode == "entries":
		if event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
			_navigate_entry_up()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
			_navigate_entry_down()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("menu_back"):
			print("[IndexPanel] menu_back pressed in entries mode")
			# Move back to category list
			_focus_mode = "category"
			_category_list.grab_focus()
			print("[IndexPanel] Calling _animate_panel_focus - mode: category")
			call_deferred("_animate_panel_focus")
			get_viewport().set_input_as_handled()
			return

func _on_panel_gained_focus() -> void:
	super()
	print("[IndexPanel] Gained focus - focusing category list")
	# Focus the category list when panel becomes active
	_focus_mode = "category"
	if _category_list:
		_category_list.grab_focus()
	print("[IndexPanel] About to call _animate_panel_focus from gained_focus")
	call_deferred("_animate_panel_focus")

func _on_index_changed(_cat: String) -> void:
	_rebuild()

func _on_category_selected(_idx: int) -> void:
	# Just rebuild entries, don't move focus
	_rebuild()
	# Update arrow position
	call_deferred("_update_category_arrow")

func _on_category_activated(_idx: int) -> void:
	# This is called on double-click - move to entry list
	if _entry_list and _entry_list.item_count > 0:
		_focus_mode = "entries"
		_entry_list.grab_focus()
		if _entry_list.item_count > 0:
			_entry_list.select(0)
			_on_entry_selected(0)
		print("[IndexPanel] Calling _animate_panel_focus from category_activated - mode: entries")
		call_deferred("_animate_panel_focus")

func _on_entry_selected(_idx: int) -> void:
	# Update details when entry is selected
	if _idx < 0 or _idx >= _entry_list.item_count:
		return
	var entry_data: Dictionary = _entry_list.get_item_metadata(_idx)
	_update_detail(entry_data)

func _on_entry_list_gui_input(event: InputEvent) -> void:
	# Update details on hover
	if event is InputEventMouseMotion:
		var hovered_idx := _entry_list.get_item_at_position(event.position, true)
		if hovered_idx >= 0:
			var entry_data: Dictionary = _entry_list.get_item_metadata(hovered_idx)
			_update_detail(entry_data)

func _update_detail(entry: Dictionary) -> void:
	var title: String = String(entry.get("title", "Untitled"))
	var body: String  = String(entry.get("body", ""))
	_detail.text = "[b]%s[/b]\n\n%s" % [title, (body if body != "" else "[i]No details yet.[/i]")]

func _rebuild() -> void:
	# Clear entry list
	_entry_list.clear()

	var cat_id: int = Filter.TUTORIALS
	var selected_items := _category_list.get_selected_items()
	if selected_items.size() > 0:
		var idx: int = selected_items[0]
		cat_id = _category_list.get_item_metadata(idx)

	var items: Array[Dictionary] = _gather_items(cat_id)

	for entry in items:
		var title: String = String(entry.get("title", "Untitled"))
		_entry_list.add_item(title)
		var item_idx := _entry_list.item_count - 1
		_entry_list.set_item_metadata(item_idx, entry)

	if items.size() > 0:
		_entry_list.select(0)
		_update_detail(items[0])
	else:
		_detail.text = "[i]No entries yet.[/i]"

func _animate_panel_focus() -> void:
	"""Animate panels to highlight which one is currently active"""
	print("[IndexPanel] _animate_panel_focus called, _focus_mode: %s" % _focus_mode)
	print("[IndexPanel] Panel refs - category: %s, content: %s, details: %s" % [_category_panel != null, _content_panel != null, _details_panel != null])

	if not _category_panel or not _content_panel or not _details_panel:
		print("[IndexPanel] ERROR: Missing panel references!")
		return

	var left_ratio := BASE_LEFT_RATIO
	var center_ratio := BASE_CENTER_RATIO
	var right_ratio := BASE_RIGHT_RATIO  # Details panel always stays at base size

	# Determine which panel gets the active scale (only left and center panels animate)
	if _focus_mode == "category":
		left_ratio = BASE_LEFT_RATIO * ACTIVE_SCALE
		center_ratio = BASE_CENTER_RATIO * INACTIVE_SCALE
		# right_ratio stays at BASE_RIGHT_RATIO
	elif _focus_mode == "entries":
		left_ratio = BASE_LEFT_RATIO * INACTIVE_SCALE
		center_ratio = BASE_CENTER_RATIO * ACTIVE_SCALE
		# right_ratio stays at BASE_RIGHT_RATIO

	print("[IndexPanel] Animation ratios - left: %.2f, center: %.2f, right: %.2f" % [left_ratio, center_ratio, right_ratio])

	# Create tweens for smooth animation
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(_category_panel, "size_flags_stretch_ratio", left_ratio, ANIM_DURATION)
	tween.tween_property(_content_panel, "size_flags_stretch_ratio", center_ratio, ANIM_DURATION)
	tween.tween_property(_details_panel, "size_flags_stretch_ratio", right_ratio, ANIM_DURATION)

	print("[IndexPanel] Tween created and started")

# --- Data source ---------------------------------------------------------------

func _gather_items(cat_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	# Try live system first (safe calls; no direct aIndexSystem symbol)
	var idx: Node = get_node_or_null("/root/aIndexSystem")
	if idx:
		var cat_key: String = _cat_key(cat_id)
		if cat_key != "":
			var ids_psa := PackedStringArray()
			if idx.has_method("list_ids"):
				var ids_v: Variant = idx.call("list_ids", cat_key)
				if typeof(ids_v) == TYPE_PACKED_STRING_ARRAY:
					ids_psa = ids_v
				elif typeof(ids_v) == TYPE_ARRAY:
					for e in (ids_v as Array):
						ids_psa.append(String(e))
			ids_psa.sort()
			for id in ids_psa:
				var rec_v: Variant = idx.call("get_entry", cat_key, id)
				if typeof(rec_v) == TYPE_DICTIONARY:
					out.append(rec_v as Dictionary)

		if out.size() > 0:
			return out

	# Fallback placeholders (same as before)
	return _placeholder_items(cat_id)

func _cat_key(cat_id: int) -> String:
	match cat_id:
		Filter.TUTORIALS: return "tutorials"
		Filter.ENEMIES:   return "enemies"
		Filter.MISSIONS:  return "missions"
		Filter.LOCATIONS: return "locations"
		Filter.LORE:      return "lore"
		_: return ""

# --- placeholders (kept for empty state) --------------------------------------

func _placeholder_items(cat_id: int) -> Array[Dictionary]:
	var titles: Array[String] = []
	match cat_id:
		Filter.TUTORIALS:
			titles = ["Combat Basics","Sigils & Bracelets","Perks & Tiers","Circle Bonds","Saving & Loading"]
		Filter.ENEMIES:
			titles = ["Sludge Wisp","Street Drone","Gutter Beast","Mirrorling","Static Shell"]
		Filter.MISSIONS:
			titles = ["Orientation Day","Picking School Tracks","Abandoned Garage","VR Node: Echo","Midterm Mischief"]
		Filter.LOCATIONS:
			titles = ["Dormitory","Campus Quad","Old Garage","Downtown","VR Hub"]
		Filter.LORE:
			titles = ["School History","City Districts","Sigil Origins","Circle Traditions","World Myths"]
		_:
			titles = []

	var out: Array[Dictionary] = []
	for t in titles:
		out.append({"title": t, "body": "[i]Placeholder entry.[/i] Replace via aIndexSystem."})
	return out

# --- Selection Arrow for Category List ----------------------------------------

func _create_category_arrow() -> void:
	"""Create simple selection arrow for category list"""
	_category_arrow = Label.new()
	_category_arrow.text = "◄"
	_category_arrow.add_theme_font_size_override("font_size", 40)
	_category_arrow.modulate = Color(1, 1, 1, 1)  # White
	_category_arrow.z_index = 1000
	_category_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_category_arrow)

	# Start pulsing animation
	_start_arrow_pulse()

func _update_category_arrow() -> void:
	"""Update arrow position to align with selected category"""
	if not _category_arrow or not _category_list:
		return

	var selected = _category_list.get_selected_items()
	if selected.size() == 0:
		_category_arrow.visible = false
		return

	_category_arrow.visible = true

	# Get selected item position
	var item_index = selected[0]
	var item_rect = _category_list.get_item_rect(item_index)

	# Convert to panel coordinates
	var list_global = _category_list.global_position
	var panel_global = global_position
	var list_offset = list_global - panel_global

	# Position arrow to the right of the list, offset 40px to the left
	var arrow_x = list_offset.x + _category_list.size.x + 10.0 - 40.0
	var arrow_y = list_offset.y + item_rect.position.y + (item_rect.size.y / 2.0) - 20.0

	_category_arrow.position = Vector2(arrow_x, arrow_y)

func _start_arrow_pulse() -> void:
	"""Start pulsing animation for the category arrow"""
	if not _category_arrow:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse left 6 pixels then back
	var base_pos = _category_arrow.position
	tween.tween_property(_category_arrow, "position:x", base_pos.x - 6, 0.6)
	tween.tween_property(_category_arrow, "position:x", base_pos.x, 0.6)

# --- Wrap-around Navigation ----------------------------------------------------

func _navigate_category_up() -> void:
	"""Navigate up in category list with wrap-around"""
	if not _category_list or _category_list.item_count == 0:
		return

	var selected = _category_list.get_selected_items()
	var current_index = selected[0] if selected.size() > 0 else 0

	if current_index > 0:
		_category_list.select(current_index - 1)
	else:
		# Wrap to bottom
		_category_list.select(_category_list.item_count - 1)

	_on_category_selected(_category_list.get_selected_items()[0])

func _navigate_category_down() -> void:
	"""Navigate down in category list with wrap-around"""
	if not _category_list or _category_list.item_count == 0:
		return

	var selected = _category_list.get_selected_items()
	var current_index = selected[0] if selected.size() > 0 else 0

	if current_index < _category_list.item_count - 1:
		_category_list.select(current_index + 1)
	else:
		# Wrap to top
		_category_list.select(0)

	_on_category_selected(_category_list.get_selected_items()[0])

func _navigate_entry_up() -> void:
	"""Navigate up in entry list with wrap-around"""
	if not _entry_list or _entry_list.item_count == 0:
		return

	var selected = _entry_list.get_selected_items()
	var current_index = selected[0] if selected.size() > 0 else 0

	if current_index > 0:
		_entry_list.select(current_index - 1)
	else:
		# Wrap to bottom
		_entry_list.select(_entry_list.item_count - 1)

	_on_entry_selected(_entry_list.get_selected_items()[0])

func _navigate_entry_down() -> void:
	"""Navigate down in entry list with wrap-around"""
	if not _entry_list or _entry_list.item_count == 0:
		return

	var selected = _entry_list.get_selected_items()
	var current_index = selected[0] if selected.size() > 0 else 0

	if current_index < _entry_list.item_count - 1:
		_entry_list.select(current_index + 1)
	else:
		# Wrap to top
		_entry_list.select(0)

	_on_entry_selected(_entry_list.get_selected_items()[0])
