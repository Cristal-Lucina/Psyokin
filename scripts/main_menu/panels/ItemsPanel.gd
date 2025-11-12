extends Control
class_name ItemsPanel

## Items Panel - Redesigned with Category Icons and 2-Column Grid

# Autoload paths
const INV_PATH   : String = "/root/aInventorySystem"
const CSV_PATH   : String = "/root/aCSVLoader"
const EQUIP_PATH : String = "/root/aEquipmentSystem"
const GS_PATH    : String = "/root/aGameState"

# CSV data
const ITEMS_CSV : String = "res://data/items/items.csv"
const KEY_ID    : String = "item_id"

# Categories with icons
const CATEGORIES : Array[Dictionary] = [
	{"id": "Acquired", "icon": "A"},
	{"id": "Recovery", "icon": "♥"},
	{"id": "Battle", "icon": "💣"},
	{"id": "Equipment", "icon": "⚔"},
	{"id": "Sigils", "icon": "◆"},
	{"id": "Capture", "icon": "⛓"},
	{"id": "Material", "icon": "▪"},
	{"id": "Gifts", "icon": "🎁"},
	{"id": "Key", "icon": "🗝"},
	{"id": "Other", "icon": "O"}
]

# Scene references
@onready var _item_panel: PanelContainer = %ItemPanel
@onready var _details_panel: PanelContainer = %DetailsPanel
@onready var _category_icons_container: HBoxContainer = %CategoryIconsContainer
@onready var _category_name: Label = %CategoryName
@onready var _l1_label: Label = %L1Label
@onready var _r1_label: Label = %R1Label
@onready var _items_grid: GridContainer = %ItemsGrid
@onready var _items_scroll: ScrollContainer = %ItemsScroll
@onready var _item_name: Label = %ItemName
@onready var _details_text: RichTextLabel = %DetailsText
@onready var _use_button: Button = %UseButton
@onready var _inspect_button: Button = %InspectButton

# System references
var _inv: Node = null
var _csv: Node = null
var _eq: Node = null
var _gs: Node = null

# Data
var _defs: Dictionary = {}
var _counts: Dictionary = {}
var _equipped_by: Dictionary = {}

# State
var _current_category_index: int = 0
var _category_buttons: Array[Button] = []
var _item_buttons: Array[Button] = []
var _item_ids: Array[String] = []
var _selected_item_id: String = ""
var _selected_grid_index: int = 0

# Selection arrow
var _selection_arrow: Label = null
var _debug_box: PanelContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_inv = get_node_or_null(INV_PATH)
	_csv = get_node_or_null(CSV_PATH)
	_eq = get_node_or_null(EQUIP_PATH)
	_gs = get_node_or_null(GS_PATH)

	if _use_button:
		_use_button.pressed.connect(_on_use_button_pressed)
	if _inspect_button:
		_inspect_button.pressed.connect(_on_inspect_button_pressed)

	if _inv and _inv.has_signal("inventory_changed"):
		if not _inv.is_connected("inventory_changed", Callable(self, "_rebuild")):
			_inv.connect("inventory_changed", Callable(self, "_rebuild"))

	if _eq and _eq.has_signal("equipment_changed"):
		if not _eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
			_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	visibility_changed.connect(_on_visibility_changed)
	_create_category_icons()
	_create_selection_arrow()
	call_deferred("_apply_styling")
	call_deferred("_rebuild")

func _create_category_icons() -> void:
	if not _category_icons_container:
		return

	for i in range(CATEGORIES.size()):
		var cat_data: Dictionary = CATEGORIES[i]
		var button = Button.new()
		button.text = cat_data["icon"]
		button.custom_minimum_size = Vector2(48, 48)
		button.add_theme_font_size_override("font_size", 24)
		button.set_meta("category_index", i)
		button.pressed.connect(_on_category_icon_pressed.bind(i))
		_category_icons_container.add_child(button)
		_category_buttons.append(button)

	_update_category_selection()

func _on_category_icon_pressed(index: int) -> void:
	_current_category_index = index
	_update_category_selection()
	_populate_items()

func _update_category_selection() -> void:
	for i in range(_category_buttons.size()):
		var button: Button = _category_buttons[i]
		var is_selected: bool = (i == _current_category_index)
		var style = StyleBoxFlat.new()
		style.bg_color = aCoreVibeTheme.COLOR_NIGHT_NAVY if not is_selected else aCoreVibeTheme.COLOR_MILK_WHITE
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		var text_color: Color = aCoreVibeTheme.COLOR_MILK_WHITE if not is_selected else aCoreVibeTheme.COLOR_NIGHT_NAVY
		button.add_theme_color_override("font_color", text_color)
		button.add_theme_color_override("font_hover_color", text_color)
		button.add_theme_color_override("font_pressed_color", text_color)
		var scale_factor: float = 1.1 if is_selected else 1.0
		button.scale = Vector2(scale_factor, scale_factor)

	if _category_name and _current_category_index < CATEGORIES.size():
		_category_name.text = CATEGORIES[_current_category_index]["id"].to_upper()

func _create_selection_arrow() -> void:
	_selection_arrow = Label.new()
	_selection_arrow.text = "◄"
	_selection_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selection_arrow.add_theme_font_size_override("font_size", 43)
	_selection_arrow.modulate = Color(1, 1, 1, 1)
	_selection_arrow.custom_minimum_size = Vector2(54, 72)
	_selection_arrow.size = Vector2(54, 72)
	_selection_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_arrow.z_index = 100
	add_child(_selection_arrow)
	await get_tree().process_frame
	_selection_arrow.size = Vector2(54, 72)

	_debug_box = PanelContainer.new()
	_debug_box.custom_minimum_size = Vector2(400, 20)
	_debug_box.size = Vector2(400, 20)
	_debug_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_box.z_index = 100
	var debug_style = StyleBoxFlat.new()
	debug_style.bg_color = Color(aCoreVibeTheme.COLOR_INK_CHARCOAL.r, aCoreVibeTheme.COLOR_INK_CHARCOAL.g, aCoreVibeTheme.COLOR_INK_CHARCOAL.b, 0.0)
	debug_style.corner_radius_top_left = 8
	debug_style.corner_radius_top_right = 8
	debug_style.corner_radius_bottom_left = 8
	debug_style.corner_radius_bottom_right = 8
	_debug_box.add_theme_stylebox_override("panel", debug_style)
	add_child(_debug_box)
	await get_tree().process_frame
	_debug_box.size = Vector2(400, 20)
	_start_arrow_pulse()

func _update_arrow_position() -> void:
	if not _selection_arrow or _selected_grid_index < 0 or _selected_grid_index >= _item_buttons.size():
		if _selection_arrow:
			_selection_arrow.visible = false
		if _debug_box:
			_debug_box.visible = false
		return

	_selection_arrow.visible = true
	await get_tree().process_frame

	var selected_button: Button = _item_buttons[_selected_grid_index]
	var button_global_pos = selected_button.global_position
	var panel_global_pos = global_position
	var button_offset = button_global_pos - panel_global_pos

	var arrow_x = button_offset.x + selected_button.size.x - 8.0 - 80.0 + 40.0
	var arrow_y = button_offset.y + (selected_button.size.y / 2.0) - (_selection_arrow.size.y / 2.0)
	_selection_arrow.position = Vector2(arrow_x, arrow_y)

	if _debug_box:
		_debug_box.visible = true
		var debug_x = arrow_x - _debug_box.size.x - 4.0
		var debug_y = arrow_y + (_selection_arrow.size.y / 2.0) - (_debug_box.size.y / 2.0)
		_debug_box.position = Vector2(debug_x, debug_y)

func _start_arrow_pulse() -> void:
	if not _selection_arrow:
		return
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	var base_x = _selection_arrow.position.x
	tween.tween_property(_selection_arrow, "position:x", base_x - 6, 0.6)
	tween.tween_property(_selection_arrow, "position:x", base_x, 0.6)

func _apply_styling() -> void:
	if _item_panel:
		var style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.COLOR_INK_CHARCOAL,
			aCoreVibeTheme.PANEL_OPACITY_SEMI, aCoreVibeTheme.CORNER_RADIUS_MEDIUM,
			aCoreVibeTheme.BORDER_WIDTH_THIN, aCoreVibeTheme.SHADOW_SIZE_MEDIUM)
		style.content_margin_left = 10
		style.content_margin_top = 10
		style.content_margin_right = 10
		style.content_margin_bottom = 10
		_item_panel.add_theme_stylebox_override("panel", style)

	if _details_panel:
		var style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_GRAPE_VIOLET, aCoreVibeTheme.COLOR_INK_CHARCOAL,
			aCoreVibeTheme.PANEL_OPACITY_SEMI, aCoreVibeTheme.CORNER_RADIUS_MEDIUM,
			aCoreVibeTheme.BORDER_WIDTH_THIN, aCoreVibeTheme.SHADOW_SIZE_MEDIUM)
		style.content_margin_left = 10
		style.content_margin_top = 10
		style.content_margin_right = 10
		style.content_margin_bottom = 10
		_details_panel.add_theme_stylebox_override("panel", style)

	if _category_name:
		aCoreVibeTheme.style_label(_category_name, aCoreVibeTheme.COLOR_SKY_CYAN, 18)
	if _item_name:
		aCoreVibeTheme.style_label(_item_name, aCoreVibeTheme.COLOR_MILK_WHITE, 16)
	if _l1_label:
		aCoreVibeTheme.style_label(_l1_label, aCoreVibeTheme.COLOR_MILK_WHITE, 14)
	if _r1_label:
		aCoreVibeTheme.style_label(_r1_label, aCoreVibeTheme.COLOR_MILK_WHITE, 14)
	if _use_button:
		aCoreVibeTheme.style_button(_use_button, aCoreVibeTheme.COLOR_ELECTRIC_LIME, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	if _inspect_button:
		aCoreVibeTheme.style_button(_inspect_button, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)

func _rebuild() -> void:
	_load_item_defs()
	_load_inventory()
	_load_equipped()
	_populate_items()
	_update_details()

func _load_item_defs() -> void:
	_defs.clear()
	if not _csv or not _csv.has_method("load_csv"):
		return
	var rows: Array = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			var id: String = String(row.get(KEY_ID, ""))
			if id != "":
				_defs[id] = row

func _load_inventory() -> void:
	_counts.clear()
	if not _inv or not _inv.has_method("get_all_items"):
		return
	var items: Dictionary = _inv.call("get_all_items")
	for item_id in items.keys():
		_counts[String(item_id)] = int(items[item_id])

func _load_equipped() -> void:
	_equipped_by.clear()
	if not _eq or not _eq.has_method("get_all_equipped"):
		return
	var equipped: Dictionary = _eq.call("get_all_equipped")
	for member in equipped.keys():
		var member_gear: Dictionary = equipped[member]
		for slot in member_gear.keys():
			var item_id: String = String(member_gear[slot])
			if item_id != "":
				if not _equipped_by.has(item_id):
					_equipped_by[item_id] = []
				_equipped_by[item_id].append(_member_display_name(member))

func _populate_items() -> void:
	if not _items_grid:
		return
	for button in _item_buttons:
		button.queue_free()
	_item_buttons.clear()
	_item_ids.clear()
	_selected_grid_index = 0

	if _current_category_index < 0 or _current_category_index >= CATEGORIES.size():
		return

	var category: String = CATEGORIES[_current_category_index]["id"]
	var items: Array[String] = []
	for item_id in _counts.keys():
		var qty: int = _counts[item_id]
		if qty <= 0:
			continue
		if category == "Acquired":
			items.append(item_id)
			continue
		var def: Dictionary = _defs.get(item_id, {})
		var item_cat: String = _category_of(def)
		if item_cat == category:
			items.append(item_id)

	items.sort_custom(func(a: String, b: String) -> bool:
		var def_a: Dictionary = _defs.get(a, {})
		var def_b: Dictionary = _defs.get(b, {})
		var name_a: String = _display_name(a, def_a)
		var name_b: String = _display_name(b, def_b)
		return name_a < name_b
	)

	for item_id in items:
		var def: Dictionary = _defs.get(item_id, {})
		var qty: int = _counts.get(item_id, 0)
		var name: String = _display_name(item_id, def)
		var button = Button.new()
		button.text = "%s x%d" % [name, qty]
		button.custom_minimum_size = Vector2(200, 40)
		button.set_meta("item_id", item_id)
		button.set_meta("grid_index", _item_buttons.size())
		button.pressed.connect(_on_grid_item_pressed.bind(_item_buttons.size()))
		_items_grid.add_child(button)
		_item_buttons.append(button)
		_item_ids.append(item_id)

	if _item_buttons.size() > 0:
		_selected_grid_index = 0
		_selected_item_id = _item_ids[0]
		_update_details()
		call_deferred("_update_arrow_position")

func _on_grid_item_pressed(index: int) -> void:
	if index < 0 or index >= _item_ids.size():
		return
	_selected_grid_index = index
	_selected_item_id = _item_ids[index]
	_update_details()
	_update_arrow_position()

func _update_details() -> void:
	if _selected_item_id == "" or not _defs.has(_selected_item_id):
		_clear_details()
		return

	var def: Dictionary = _defs[_selected_item_id]
	var qty: int = _counts.get(_selected_item_id, 0)
	var name: String = _display_name(_selected_item_id, def)

	if _item_name:
		_item_name.text = name

	var details: String = ""
	details += "Quantity: [color=#C8FF3D]x%d[/color]\n\n" % qty
	var desc: String = _get_description(def)
	if desc != "":
		details += "[color=#F4F7FB]%s[/color]\n\n" % desc

	if _details_text:
		_details_text.text = details

	var category: String = CATEGORIES[_current_category_index]["id"]
	if _use_button:
		_use_button.visible = (category == "Recovery")
	if _inspect_button:
		_inspect_button.visible = true

func _clear_details() -> void:
	if _item_name:
		_item_name.text = "(Select an item)"
	if _details_text:
		_details_text.text = ""
	if _use_button:
		_use_button.visible = false
	if _inspect_button:
		_inspect_button.visible = false

func _category_of(def: Dictionary) -> String:
	var type: String = String(def.get("type", "")).to_lower()
	match type:
		"recovery": return "Recovery"
		"battle": return "Battle"
		"equipment": return "Equipment"
		"sigil": return "Sigils"
		"capture": return "Capture"
		"material": return "Material"
		"gift": return "Gifts"
		"key": return "Key"
	return "Other"

func _display_name(item_id: String, def: Dictionary) -> String:
	var name: String = String(def.get("name", item_id))
	return name if name != "" else item_id

func _get_description(def: Dictionary) -> String:
	return String(def.get("description", ""))

func _member_display_name(token: String) -> String:
	if _gs and _gs.has_method("_first_name_for_id"):
		return _gs.call("_first_name_for_id", token)
	return token

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_shoulder_left"):
		_current_category_index -= 1
		if _current_category_index < 0:
			_current_category_index = CATEGORIES.size() - 1
		_update_category_selection()
		_populate_items()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_shoulder_right"):
		_current_category_index += 1
		if _current_category_index >= CATEGORIES.size():
			_current_category_index = 0
		_update_category_selection()
		_populate_items()
		get_viewport().set_input_as_handled()

func _on_visibility_changed() -> void:
	if visible:
		_rebuild()

func _on_equipment_changed(_member: String) -> void:
	_rebuild()

func _on_use_button_pressed() -> void:
	print("[ItemsPanel] Use button pressed for: %s" % _selected_item_id)

func _on_inspect_button_pressed() -> void:
	print("[ItemsPanel] Inspect button pressed for: %s" % _selected_item_id)
