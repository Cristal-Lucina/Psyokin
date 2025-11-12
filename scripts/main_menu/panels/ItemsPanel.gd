extends Control
class_name ItemsPanel

## Items Panel - Redesigned with Category Icons and 2-Column Grid

# Autoload paths
const INV_PATH   : String = "/root/aInventorySystem"
const CSV_PATH   : String = "/root/aCSVLoader"
const EQUIP_PATH : String = "/root/aEquipmentSystem"
const GS_PATH    : String = "/root/aGameState"
const SIGIL_PATH : String = "/root/aSigilSystem"
const CPS_PATH   : String = "/root/aCombatProfileSystem"

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
var _sig: Node = null
var _cps: Node = null

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
	_sig = get_node_or_null(SIGIL_PATH)
	_cps = get_node_or_null(CPS_PATH)

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
	"""Rebuild all data from systems"""
	if not is_inside_tree():
		return
	_load_item_defs()
	_load_inventory()
	_load_equipped()
	_add_sigil_instances()  # Add sigil instances as virtual items
	_populate_items()
	_update_details()

func _load_item_defs() -> void:
	"""Load item definitions from CSV"""
	_defs.clear()

	if not _csv:
		print("[ItemsPanel] ERROR: CSV loader is null!")
		return

	if not _csv.has_method("load_csv"):
		print("[ItemsPanel] ERROR: CSV loader missing load_csv method!")
		return

	print("[ItemsPanel] Calling load_csv with path: %s, key: %s" % [ITEMS_CSV, KEY_ID])
	var defs_variant: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
	print("[ItemsPanel] load_csv returned type: %d" % typeof(defs_variant))

	if defs_variant == null:
		print("[ItemsPanel] ERROR: CSV returned null!")
		return

	if typeof(defs_variant) != TYPE_DICTIONARY:
		print("[ItemsPanel] ERROR: CSV returned wrong type!")
		return

	# IMPORTANT: Duplicate to avoid modifying CSV loader's internal cache
	_defs = (defs_variant as Dictionary).duplicate(true)
	print("[ItemsPanel] Loaded %d item definitions" % _defs.size())

func _load_inventory() -> void:
	"""Load inventory counts"""
	_counts.clear()

	if not _inv:
		print("[ItemsPanel] ERROR: Inventory system is null!")
		return

	if not _inv.has_method("get_counts"):
		print("[ItemsPanel] ERROR: Inventory missing get_counts method!")
		return

	print("[ItemsPanel] Calling inventory.get_counts()")
	var items_variant: Variant = _inv.call("get_counts")
	print("[ItemsPanel] get_counts returned type: %d" % typeof(items_variant))

	if items_variant == null:
		print("[ItemsPanel] ERROR: Inventory returned null!")
		return

	if typeof(items_variant) != TYPE_DICTIONARY:
		print("[ItemsPanel] ERROR: Inventory returned wrong type!")
		return

	# Filter out comment entries (start with #) and convert to proper types
	var raw_counts: Dictionary = items_variant as Dictionary
	for item_id in raw_counts.keys():
		var id_str: String = String(item_id)
		if id_str.begins_with("#"):
			continue
		var qty: Variant = raw_counts[item_id]
		if typeof(qty) == TYPE_FLOAT or typeof(qty) == TYPE_INT:
			var qty_int: int = int(qty)
			if qty_int > 0:
				_counts[id_str] = qty_int

	print("[ItemsPanel] Loaded %d items from inventory (filtered %d comments)" % [_counts.size(), raw_counts.size() - _counts.size()])

func _load_equipped() -> void:
	"""Load equipped items"""
	_equipped_by.clear()
	if not _eq or not _eq.has_method("get_member_equip") or not _gs:
		return

	# Get all party members
	var members: Array = []
	if _gs.has_method("get_active_party"):
		var party_variant: Variant = _gs.call("get_active_party")
		if typeof(party_variant) == TYPE_ARRAY:
			members = party_variant as Array

	# Load equipment for each member
	for member in members:
		var member_id: String = String(member)
		var equip_variant: Variant = _eq.call("get_member_equip", member_id)
		if typeof(equip_variant) != TYPE_DICTIONARY:
			continue
		var member_gear: Dictionary = equip_variant as Dictionary
		for slot in member_gear.keys():
			var item_id: String = String(member_gear[slot])
			if item_id != "" and item_id != "—":
				if not _equipped_by.has(item_id):
					_equipped_by[item_id] = []
				_equipped_by[item_id].append(_member_display_name(member_id))

func _add_sigil_instances() -> void:
	"""Add sigil instances as virtual items"""
	if not _sig:
		return

	# Get all sigil instance IDs
	var instance_ids: PackedStringArray = PackedStringArray()
	if _sig.has_method("list_all_instances"):
		instance_ids = _sig.call("list_all_instances", false)  # false = include equipped

	print("[ItemsPanel] Found %d sigil instances" % instance_ids.size())

	for inst_id in instance_ids:
		var inst_dict: Dictionary = {}
		if _sig.has_method("get_instance_info"):
			inst_dict = _sig.call("get_instance_info", inst_id)

		if inst_dict.is_empty():
			continue

		# Create virtual item def
		var base_id: String = String(inst_dict.get("base_id", ""))
		var base_def: Dictionary = _defs.get(base_id, {})

		var virtual_def: Dictionary = base_def.duplicate()
		virtual_def["sigil_instance"] = true
		virtual_def["instance_id"] = inst_id
		virtual_def["name"] = _format_sigil_name(inst_dict, base_def)
		virtual_def["category"] = "Sigils"

		_defs[inst_id] = virtual_def
		_counts[inst_id] = 1

		# Track who has this sigil equipped
		var equipped_by: String = String(inst_dict.get("equipped_by", ""))
		if equipped_by != "":
			if not _equipped_by.has(inst_id):
				_equipped_by[inst_id] = []
			var member_name: String = _member_display_name(equipped_by)
			if not _equipped_by[inst_id].has(member_name):
				_equipped_by[inst_id].append(member_name)

func _format_sigil_name(inst: Dictionary, base_def: Dictionary) -> String:
	"""Format sigil instance name with level"""
	var base_name: String = String(base_def.get("name", "Sigil"))
	var level: int = int(inst.get("level", 1))
	return "%s Lv.%d" % [base_name, level]

func _populate_items() -> void:
	"""Populate items grid based on current category"""
	print("[ItemsPanel] _populate_items() called")

	if not _items_grid:
		print("[ItemsPanel] ERROR: _items_grid is null!")
		return

	# Clear existing buttons
	for button in _item_buttons:
		button.queue_free()
	_item_buttons.clear()
	_item_ids.clear()
	_selected_grid_index = 0

	if _current_category_index < 0 or _current_category_index >= CATEGORIES.size():
		print("[ItemsPanel] ERROR: Invalid category index: %d" % _current_category_index)
		return

	var category: String = CATEGORIES[_current_category_index]["id"]
	print("[ItemsPanel] Current category: %s" % category)
	print("[ItemsPanel] Total item counts: %d" % _counts.size())
	print("[ItemsPanel] Total definitions: %d" % _defs.size())

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

	print("[ItemsPanel] Found %d items in category '%s'" % [items.size(), category])

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
		print("[ItemsPanel] Added button: %s" % button.text)

	print("[ItemsPanel] Total buttons created: %d" % _item_buttons.size())

	if _item_buttons.size() > 0:
		_selected_grid_index = 0
		_selected_item_id = _item_ids[0]
		print("[ItemsPanel] Selected first item: %s" % _selected_item_id)
		_update_details()
		call_deferred("_update_arrow_position")
	else:
		print("[ItemsPanel] WARNING: No items to display!")
		_clear_details()

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
	"""Get category of an item - checks multiple fields with priority"""
	# Check if it's a recovery item first (HP/MP healing)
	if _is_recovery_item(def):
		return "Recovery"

	# Check if it's a capture item
	if _is_capture_item(def):
		return "Capture"

	# Check if it's a gift item
	if _is_gift_item(def):
		return "Gifts"

	# Check if it's equipment (has equip_slot field)
	if _is_equipment(def):
		return "Equipment"

	# Check if it's a battle consumable
	if _is_battle_item(def):
		return "Battle"

	# Check category field for remaining types (Sigils, Material, Key, Other)
	for key in ["category", "cat", "type"]:
		if def.has(key):
			var cat: String = String(def[key]).strip_edges()
			var norm: String = _normalize_category(cat)
			if norm != "":
				return norm
	return "Other"

func _normalize_category(cat: String) -> String:
	"""Normalize category name"""
	var key: String = cat.to_lower().strip_edges()
	const MAP: Dictionary = {
		"sigil": "Sigils", "sigils": "Sigils",
		"material": "Material", "materials": "Material",
		"key": "Key", "key item": "Key", "key items": "Key",
		"gift": "Gifts", "gifts": "Gifts",
		"other": "Other",
		"weapon": "Equipment", "weapons": "Equipment",
		"armor": "Equipment",
		"consumable": "Recovery", "consumables": "Recovery"
	}
	if MAP.has(key):
		return MAP[key]
	# Check if it matches any category ID
	for cat_dict in CATEGORIES:
		if cat_dict["id"] == cat:
			return cat
	return ""

func _is_recovery_item(def: Dictionary) -> bool:
	"""Check if item is a recovery item (HP/MP healing)"""
	for key in ["field_status_effect", "battle_status_effect"]:
		if def.has(key):
			var effect: String = String(def[key]).to_lower()
			if (effect.contains("heal") or effect.contains("restore")) and (effect.contains("hp") or effect.contains("mp")):
				return true
	return false

func _is_capture_item(def: Dictionary) -> bool:
	"""Check if item is a capture item"""
	var cat: String = String(def.get("category", "")).to_lower()
	if cat.contains("capture") or cat.contains("bind"):
		return true
	var name: String = String(def.get("name", "")).to_lower()
	if name.contains("bind"):
		return true
	return false

func _is_gift_item(def: Dictionary) -> bool:
	"""Check if item is a gift item"""
	var cat: String = String(def.get("category", "")).to_lower()
	return cat.contains("gift")

func _is_equipment(def: Dictionary) -> bool:
	"""Check if item is equipment"""
	var equip_slot: String = String(def.get("equip_slot", "")).to_lower().strip_edges()
	return equip_slot in ["weapon", "armor", "head", "foot", "bracelet"]

func _is_battle_item(def: Dictionary) -> bool:
	"""Check if item is a battle consumable"""
	var cat: String = String(def.get("category", "")).to_lower()
	if cat.contains("consumable") or cat.contains("battle"):
		if not _is_recovery_item(def) and not _is_capture_item(def) and not _is_gift_item(def):
			return true
	return false

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

	# Use direct joypad button checks to avoid GameMenu interception
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			9:  # L1
				_current_category_index -= 1
				if _current_category_index < 0:
					_current_category_index = CATEGORIES.size() - 1
				_update_category_selection()
				_populate_items()
				get_viewport().set_input_as_handled()
				return
			10:  # R1
				_current_category_index += 1
				if _current_category_index >= CATEGORIES.size():
					_current_category_index = 0
				_update_category_selection()
				_populate_items()
				get_viewport().set_input_as_handled()
				return
			12:  # D-pad Up
				print("[ItemsPanel] D-pad Up pressed")
				_navigate_items(-1)
				get_viewport().set_input_as_handled()
				return
			13:  # D-pad Down
				print("[ItemsPanel] D-pad Down pressed")
				_navigate_items(1)
				get_viewport().set_input_as_handled()
				return
			0:  # Accept button (A/Cross)
				print("[ItemsPanel] Accept button pressed")
				_on_accept_pressed()
				get_viewport().set_input_as_handled()
				return

func _navigate_items(delta: int) -> void:
	"""Navigate items with simple up/down"""
	if _item_buttons.size() == 0:
		return

	var new_index = _selected_grid_index + delta

	# Clamp to valid range
	if new_index < 0:
		new_index = 0
	elif new_index >= _item_buttons.size():
		new_index = _item_buttons.size() - 1

	if new_index != _selected_grid_index:
		_selected_grid_index = new_index
		_selected_item_id = _item_ids[_selected_grid_index]
		_update_details()
		_update_arrow_position()

func _on_accept_pressed() -> void:
	"""Handle Accept button press"""
	if _selected_item_id == "" or not _defs.has(_selected_item_id):
		return

	var def: Dictionary = _defs[_selected_item_id]

	# If it's a recovery item, trigger use button
	if _is_recovery_item(def) and _use_button and _use_button.visible:
		_on_use_button_pressed()
	# For other items, trigger inspect
	elif _inspect_button and _inspect_button.visible:
		_on_inspect_button_pressed()

func _on_visibility_changed() -> void:
	if visible:
		_rebuild()

func _on_equipment_changed(_member: String) -> void:
	_rebuild()

func _on_use_button_pressed() -> void:
	"""Use recovery item - for now, heal first party member"""
	print("[ItemsPanel] Use button pressed for: %s" % _selected_item_id)

	if _selected_item_id == "" or not _defs.has(_selected_item_id):
		return

	var def: Dictionary = _defs[_selected_item_id]

	# Get first party member
	var members: Array = []
	if _gs and _gs.has_method("get_active_party"):
		var party_variant: Variant = _gs.call("get_active_party")
		if typeof(party_variant) == TYPE_ARRAY:
			members = party_variant as Array

	if members.size() == 0:
		print("[ItemsPanel] No party members available")
		return

	var first_member: String = String(members[0])
	print("[ItemsPanel] Using item on: %s" % first_member)

	# Get effect text
	var effect: String = String(def.get("field_status_effect", ""))
	if effect == "":
		effect = String(def.get("battle_status_effect", ""))

	print("[ItemsPanel] Effect: %s" % effect)

	# Get current HP/MP
	var hp: int = 0
	var mp: int = 0
	var hp_max: int = 1
	var mp_max: int = 1

	if _cps and _cps.has_method("get_stats"):
		var stats_variant: Variant = _cps.call("get_stats", first_member)
		if typeof(stats_variant) == TYPE_DICTIONARY:
			var stats: Dictionary = stats_variant as Dictionary
			hp = int(stats.get("hp", 0))
			mp = int(stats.get("mp", 0))
			hp_max = int(stats.get("hp_max", 1))
			mp_max = int(stats.get("mp_max", 1))

	print("[ItemsPanel] Current HP: %d/%d, MP: %d/%d" % [hp, hp_max, mp, mp_max])

	# Parse healing amount from effect string
	var effect_lower: String = effect.to_lower()
	var new_hp: int = hp
	var new_mp: int = mp
	var healed: bool = false

	# Simple number extraction using regex
	var regex := RegEx.new()
	regex.compile("\\d+")

	if effect_lower.contains("heal") and effect_lower.contains("hp"):
		var match_result := regex.search(effect)
		if match_result:
			var heal_amount: int = int(match_result.get_string())
			new_hp = min(hp + heal_amount, hp_max)
			healed = true
			print("[ItemsPanel] Healing HP by %d: %d -> %d" % [heal_amount, hp, new_hp])

	if effect_lower.contains("heal") and effect_lower.contains("mp"):
		var match_result := regex.search(effect)
		if match_result:
			var heal_amount: int = int(match_result.get_string())
			new_mp = min(mp + heal_amount, mp_max)
			healed = true
			print("[ItemsPanel] Healing MP by %d: %d -> %d" % [heal_amount, mp, new_mp])

	# Apply healing
	if healed and _cps:
		if _cps.has_method("set_hp"):
			_cps.call("set_hp", first_member, new_hp)
			print("[ItemsPanel] Set HP to: %d" % new_hp)
		if _cps.has_method("set_mp"):
			_cps.call("set_mp", first_member, new_mp)
			print("[ItemsPanel] Set MP to: %d" % new_mp)

		# Consume the item
		if _inv and _inv.has_method("remove_item"):
			_inv.call("remove_item", _selected_item_id, 1)
			print("[ItemsPanel] Consumed 1x %s" % _selected_item_id)
			# Rebuild will happen automatically via inventory_changed signal

func _on_inspect_button_pressed() -> void:
	print("[ItemsPanel] Inspect button pressed for: %s" % _selected_item_id)
