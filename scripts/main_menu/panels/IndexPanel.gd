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

@onready var _category_list : ItemList      = $Root/CategoryPanel/CategoryColumn/CategoryList
@onready var _entry_list    : ItemList      = $Root/ContentPanel/ContentColumn/EntryList
@onready var _detail        : RichTextLabel = $Root/DetailsPanel/DetailsColumn/Detail

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

	_rebuild()

# --- PanelBase Lifecycle Overrides ---------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		print("[IndexPanel] Back button pressed")
		get_viewport().set_input_as_handled()
		# PanelBase will handle returning to previous panel

func _on_panel_gained_focus() -> void:
	super()
	print("[IndexPanel] Gained focus - focusing category list")
	# Focus the category list when panel becomes active
	if _category_list:
		_category_list.grab_focus()

func _on_index_changed(_cat: String) -> void:
	_rebuild()

func _on_category_selected(_idx: int) -> void:
	# Just rebuild entries, don't move focus
	_rebuild()

func _on_category_activated(_idx: int) -> void:
	# Move focus to entry list ONLY when category is activated (Enter or double-click)
	if _entry_list and _entry_list.item_count > 0:
		call_deferred("_move_to_entry_list")

func _move_to_entry_list() -> void:
	"""Helper to move focus to entry list and select first item"""
	if _entry_list and _entry_list.item_count > 0:
		_entry_list.grab_focus()
		_entry_list.select(0)
		_on_entry_selected(0)

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
