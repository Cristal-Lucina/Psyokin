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
	{
		"id": "Acquired",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 1/1x/Asset 33.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 1/1x/Asset 33.png"
	},
	{
		"id": "Recovery",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 2/1x/Asset 85.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 2/1x/Asset 85.png"
	},
	{
		"id": "Battle",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 2/1x/Asset 83.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 2/1x/Asset 83.png"
	},
	{
		"id": "Equipment",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 2/1x/Asset 54.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 2/1x/Asset 54.png"
	},
	{
		"id": "Sigils",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 2/1x/Asset 71.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 2/1x/Asset 71.png"
	},
	{
		"id": "Capture",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 2/1x/Asset 61.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 2/1x/Asset 61.png"
	},
	{
		"id": "Material",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 3/1x/Asset 8.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 3/1x/Asset 8.png"
	},
	{
		"id": "Gifts",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 1/1x/Asset 8.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 1/1x/Asset 8.png"
	},
	{
		"id": "Key",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 1/1x/Asset 72.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 1/1x/Asset 72.png"
	},
	{
		"id": "Other",
		"icon_light": "res://assets/graphics/icons/UI/PNG and PSD - Light/Icon set 1/1x/Asset 86.png",
		"icon_dark": "res://assets/graphics/icons/UI/PNG and PSD - Dark/Icon set 1/1x/Asset 86.png"
	}
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
var _category_buttons: Array[TextureButton] = []
var _category_panels: Array[PanelContainer] = []  # Background panels for category icons
var _item_buttons: Array[Button] = []
var _item_ids: Array[String] = []
var _selected_item_id: String = ""
var _selected_grid_index: int = 0

# Selection arrow
var _selection_arrow: Label = null
var _debug_box: PanelContainer = null
var _arrow_tween: Tween = null

# Party picker popup
var _party_picker_list: ItemList = null
var _party_member_tokens: Array[String] = []
var _item_to_use_id: String = ""
var _item_to_use_def: Dictionary = {}
var _focus_mode: String = "items"  # "items" or "party_picker"
var _active_popup: Panel = null
var _active_overlay: CanvasLayer = null

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

	# Set spacing between icons - increased by 10px
	_category_icons_container.add_theme_constant_override("separation", 13)

	for i in range(CATEGORIES.size()):
		var cat_data: Dictionary = CATEGORIES[i]

		# Create panel container for background
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(27, 27)  # 6px padding on all sides around 15px icon
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let clicks pass through to button

		# Create button inside panel
		var button = TextureButton.new()

		# Load icon textures
		var icon_light = load(cat_data["icon_light"]) as Texture2D
		var icon_dark = load(cat_data["icon_dark"]) as Texture2D

		# Set initial texture (light when not selected)
		button.texture_normal = icon_light
		button.texture_hover = icon_light
		button.texture_pressed = icon_light

		# Store both textures as metadata
		button.set_meta("icon_light", icon_light)
		button.set_meta("icon_dark", icon_dark)

		# Size settings - shrunk by 50% (29px -> 15px)
		button.custom_minimum_size = Vector2(15, 15)
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.ignore_texture_size = true

		button.set_meta("category_index", i)
		button.pressed.connect(_on_category_icon_pressed.bind(i))

		# Add button to panel, panel to container
		panel.add_child(button)
		_category_icons_container.add_child(panel)

		_category_buttons.append(button)
		_category_panels.append(panel)

	_update_category_selection()

func _on_category_icon_pressed(index: int) -> void:
	_current_category_index = index
	_update_category_selection()
	_populate_items()

func _update_category_selection() -> void:
	for i in range(_category_buttons.size()):
		var button: TextureButton = _category_buttons[i]
		var panel: PanelContainer = _category_panels[i]
		var is_selected: bool = (i == _current_category_index)

		# Get stored textures
		var icon_light: Texture2D = button.get_meta("icon_light")
		var icon_dark: Texture2D = button.get_meta("icon_dark")

		# Use dark theme when selected, light theme when not selected
		var texture: Texture2D = icon_dark if is_selected else icon_light
		button.texture_normal = texture
		button.texture_hover = texture
		button.texture_pressed = texture

		# Set opacity to 80% (20% reduction)
		button.modulate = Color(1.0, 1.0, 1.0, 0.8)

		# Create rounded box background
		var style = StyleBoxFlat.new()
		if is_selected:
			# Selected: Milk White background with Sky Cyan glow
			style.bg_color = Color("#F4F7FB")  # Milk White
			style.shadow_color = Color("#4DE9FF")  # Sky Cyan
			style.shadow_size = 8
			style.shadow_offset = Vector2(0, 0)
		else:
			# Unselected: Night Navy background
			style.bg_color = Color("#0A0F1A")  # Night Navy

		# Rounded corners
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8

		# Apply background to panel (not button)
		panel.add_theme_stylebox_override("panel", style)

		# No scale change
		button.scale = Vector2(1.0, 1.0)

		# Start pulse animation for selected panel
		if is_selected:
			_start_category_pulse(panel)

	if _category_name and _current_category_index < CATEGORIES.size():
		_category_name.text = CATEGORIES[_current_category_index]["id"].to_upper()

func _start_category_pulse(panel: PanelContainer) -> void:
	"""Pulse animation for selected category icon"""
	# Kill any existing tween on this panel
	if panel.has_meta("pulse_tween"):
		var old_tween = panel.get_meta("pulse_tween")
		if old_tween and is_instance_valid(old_tween):
			old_tween.kill()

	# Create pulsing glow effect
	var tween = create_tween()
	tween.set_loops()
	tween.set_parallel(false)

	# Pulse the shadow/glow size
	tween.tween_method(func(value: int):
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.shadow_size = value
	, 8, 12, 0.6)

	tween.tween_method(func(value: int):
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.shadow_size = value
	, 12, 8, 0.6)

	panel.set_meta("pulse_tween", tween)

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

	# Add shadow using LabelSettings
	var label_settings = LabelSettings.new()
	label_settings.font_size = 43
	label_settings.shadow_size = 8  # Shadow blur radius
	label_settings.shadow_color = Color(0, 0, 0, 0.7)  # Black shadow with 70% opacity
	label_settings.shadow_offset = Vector2(2, 2)  # Offset the shadow slightly
	_selection_arrow.label_settings = label_settings

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

	print("[ItemsPanel] Arrow position update:")
	print("  Selected index: %d" % _selected_grid_index)
	print("  Button global pos: %s" % str(button_global_pos))
	print("  Panel global pos: %s" % str(panel_global_pos))
	print("  Button offset: %s" % str(button_offset))
	print("  Arrow position: (%f, %f)" % [arrow_x, arrow_y])

	_selection_arrow.position = Vector2(arrow_x, arrow_y)

	if _debug_box:
		_debug_box.visible = true
		var debug_x = arrow_x - _debug_box.size.x - 4.0
		var debug_y = arrow_y + (_selection_arrow.size.y / 2.0) - (_debug_box.size.y / 2.0)
		_debug_box.position = Vector2(debug_x, debug_y)

	# Restart pulse animation at new position
	_start_arrow_pulse()

func _start_arrow_pulse() -> void:
	if not _selection_arrow:
		return

	# Kill existing tween if it exists
	if _arrow_tween and is_instance_valid(_arrow_tween):
		_arrow_tween.kill()

	# Create new tween at current position
	_arrow_tween = create_tween()
	_arrow_tween.set_loops()
	_arrow_tween.set_trans(Tween.TRANS_SINE)
	_arrow_tween.set_ease(Tween.EASE_IN_OUT)
	var base_x = _selection_arrow.position.x
	_arrow_tween.tween_property(_selection_arrow, "position:x", base_x - 6, 0.6)
	_arrow_tween.tween_property(_selection_arrow, "position:x", base_x, 0.6)

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

	# Style L1 and R1 labels with grey circles
	if _l1_label:
		aCoreVibeTheme.style_label(_l1_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)
		_l1_label.modulate = Color(1, 1, 1, 0.5)  # 50% transparency for text
		var l1_style = StyleBoxFlat.new()
		l1_style.bg_color = Color(0.3, 0.3, 0.3, 0.4)  # Darker grey with 50% less opacity
		l1_style.corner_radius_top_left = 12
		l1_style.corner_radius_top_right = 12
		l1_style.corner_radius_bottom_left = 12
		l1_style.corner_radius_bottom_right = 12
		l1_style.content_margin_left = 8
		l1_style.content_margin_right = 8
		l1_style.content_margin_top = 4
		l1_style.content_margin_bottom = 4
		_l1_label.add_theme_stylebox_override("normal", l1_style)

	if _r1_label:
		aCoreVibeTheme.style_label(_r1_label, aCoreVibeTheme.COLOR_MILK_WHITE, 12)
		_r1_label.modulate = Color(1, 1, 1, 0.5)  # 50% transparency for text
		var r1_style = StyleBoxFlat.new()
		r1_style.bg_color = Color(0.3, 0.3, 0.3, 0.4)  # Darker grey with 50% less opacity
		r1_style.corner_radius_top_left = 12
		r1_style.corner_radius_top_right = 12
		r1_style.corner_radius_bottom_left = 12
		r1_style.corner_radius_bottom_right = 12
		r1_style.content_margin_left = 8
		r1_style.content_margin_right = 8
		r1_style.content_margin_top = 4
		r1_style.content_margin_bottom = 4
		_r1_label.add_theme_stylebox_override("normal", r1_style)

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
	_add_equipment_instances()  # Convert equipment to individual instances
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

	# Get all party members - try multiple method names
	var members: Array = []
	for method in ["get_active_party_ids", "get_party_ids", "list_active_party", "get_active_party"]:
		if _gs.has_method(method):
			var party_variant: Variant = _gs.call(method)
			if typeof(party_variant) == TYPE_PACKED_STRING_ARRAY:
				for s in (party_variant as PackedStringArray):
					members.append(String(s))
			elif typeof(party_variant) == TYPE_ARRAY:
				for s in (party_variant as Array):
					members.append(String(s))
			if members.size() > 0:
				break

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

func _add_equipment_instances() -> void:
	"""Convert equipment items to individual instances (no stacking)"""
	var equipment_items: Array[String] = []

	# Find all equipment items
	for item_id in _counts.keys():
		if not _defs.has(item_id):
			continue
		var def: Dictionary = _defs[item_id]
		if _is_equipment(def):
			equipment_items.append(item_id)

	# Create individual instances for each equipment item
	for base_id in equipment_items:
		var base_def: Dictionary = _defs[base_id]
		var total_count: int = _counts.get(base_id, 0)

		# Get list of who has this equipped
		var equipped_members: Array = _equipped_by.get(base_id, [])
		var equipped_count: int = equipped_members.size()

		# Total instances = inventory count + equipped count
		var total_instances: int = total_count + equipped_count

		# Remove the base item from counts
		_counts.erase(base_id)

		# Create individual instances
		var instance_index: int = 0

		# First create instances for equipped items
		for member_name in equipped_members:
			var inst_id: String = "%s_inst_%d" % [base_id, instance_index]
			instance_index += 1

			# Create virtual item def
			var virtual_def: Dictionary = base_def.duplicate()
			virtual_def["equipment_instance"] = true
			virtual_def["instance_id"] = inst_id
			virtual_def["base_id"] = base_id

			_defs[inst_id] = virtual_def
			_counts[inst_id] = 1

			# Track who has this equipped
			_equipped_by[inst_id] = [member_name]

		# Then create instances for unequipped items in inventory
		var unequipped_count: int = total_count
		for i in range(unequipped_count):
			var inst_id: String = "%s_inst_%d" % [base_id, instance_index]
			instance_index += 1

			# Create virtual item def
			var virtual_def: Dictionary = base_def.duplicate()
			virtual_def["equipment_instance"] = true
			virtual_def["instance_id"] = inst_id
			virtual_def["base_id"] = base_id

			_defs[inst_id] = virtual_def
			_counts[inst_id] = 1
			# Not equipped, so don't add to _equipped_by

		# Clear old equipment tracking for base item
		_equipped_by.erase(base_id)

		print("[ItemsPanel] Created %d instances for %s (%d equipped, %d in inventory)" % [total_instances, base_id, equipped_count, unequipped_count])

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

		# Build button text - for Sigils and Equipment, show equipped member
		var button_text: String = "%s x%d" % [name, qty]
		var current_category: String = CATEGORIES[_current_category_index]["id"]

		if current_category == "Sigils":
			var equipped_by: String = _get_sigil_equipped_by(item_id)
			if equipped_by != "":
				var member_name: String = _member_display_name(equipped_by)
				button_text = "%s x%d [%s]" % [name, qty, member_name]
		elif current_category == "Equipment":
			# Check _equipped_by dictionary for equipment
			if _equipped_by.has(item_id) and _equipped_by[item_id].size() > 0:
				var equipped_members: String = ", ".join(_equipped_by[item_id])
				button_text = "%s x%d [%s]" % [name, qty, equipped_members]

		button.text = button_text
		button.custom_minimum_size = Vector2(284, 40)  # Decreased width by 10px to 284
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT  # Left-justify text
		button.focus_mode = Control.FOCUS_NONE  # Disable built-in focus navigation
		button.set_meta("item_id", item_id)
		button.set_meta("grid_index", _item_buttons.size())
		button.pressed.connect(_on_grid_item_pressed.bind(_item_buttons.size()))

		# Style button
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.1, 0.1, 0.15, 0.8)  # Dark background
		style_normal.corner_radius_top_left = 4
		style_normal.corner_radius_top_right = 4
		style_normal.corner_radius_bottom_left = 4
		style_normal.corner_radius_bottom_right = 4
		# Add 5px internal padding
		style_normal.content_margin_left = 5
		style_normal.content_margin_right = 5
		style_normal.content_margin_top = 5
		style_normal.content_margin_bottom = 5
		button.add_theme_stylebox_override("normal", style_normal)
		button.add_theme_stylebox_override("hover", style_normal)
		button.add_theme_stylebox_override("pressed", style_normal)

		_items_grid.add_child(button)
		_item_buttons.append(button)
		_item_ids.append(item_id)
		var idx = _item_buttons.size() - 1
		var row = idx / 2
		var col = idx % 2
		var col_name = "LEFT" if col == 0 else "RIGHT"
		print("[ItemsPanel] Index %d (Row %d, %s): %s" % [idx, row, col_name, button.text])

	print("[ItemsPanel] Total buttons created: %d" % _item_buttons.size())

	if _item_buttons.size() > 0:
		_selected_grid_index = 0
		_selected_item_id = _item_ids[0]
		print("[ItemsPanel] Selected first item: %s" % _selected_item_id)
		call_deferred("_update_selection_highlight")
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
	_update_selection_highlight()
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

	# Category/Type
	var item_category: String = _category_of(def)
	details += "[color=#00D9FF]Type:[/color] [color=#F4F7FB]%s[/color]\n\n" % item_category

	# Quantity
	details += "[color=#00D9FF]Quantity:[/color] [color=#C8FF3D]x%d[/color]\n\n" % qty

	# Description
	var desc: String = _get_description(def)
	if desc != "":
		details += "[color=#00D9FF]Description:[/color]\n[color=#F4F7FB]%s[/color]\n\n" % desc

	# Healing effects (if recovery item)
	if _is_recovery_item(def):
		var field_effect: String = String(def.get("field_status_effect", ""))
		var battle_effect: String = String(def.get("battle_status_effect", ""))
		if field_effect != "":
			details += "[color=#00D9FF]Field Effect:[/color]\n[color=#C8FF3D]%s[/color]\n\n" % field_effect
		if battle_effect != "":
			details += "[color=#00D9FF]Battle Effect:[/color]\n[color=#C8FF3D]%s[/color]\n\n" % battle_effect

	# Equipment info (if equipment)
	if _is_equipment(def):
		var equip_slot: String = String(def.get("equip_slot", "")).capitalize()
		if equip_slot != "":
			details += "[color=#00D9FF]Slot:[/color] [color=#F4F7FB]%s[/color]\n\n" % equip_slot

		# Check who has it equipped
		if _equipped_by.has(_selected_item_id):
			var equipped_members: Array = _equipped_by[_selected_item_id]
			if equipped_members.size() > 0:
				details += "[color=#00D9FF]Equipped By:[/color] [color=#FF3D8A]%s[/color]\n\n" % ", ".join(equipped_members)
			else:
				details += "[color=#00D9FF]Equipped By:[/color] [color=#888888]Not equipped[/color]\n\n"
		else:
			details += "[color=#00D9FF]Equipped By:[/color] [color=#888888]Not equipped[/color]\n\n"

	# Sigil info
	if def.has("sigil_instance") and def.get("sigil_instance", false):
		details += "[color=#00D9FF]Type:[/color] [color=#F4F7FB]Sigil Instance[/color]\n\n"

		# Check who has this sigil equipped
		var equipped_by: String = _get_sigil_equipped_by(_selected_item_id)
		if equipped_by != "":
			var member_name: String = _member_display_name(equipped_by)
			details += "[color=#00D9FF]Equipped By:[/color] [color=#FF3D8A]%s[/color]\n\n" % member_name
		else:
			details += "[color=#00D9FF]Equipped By:[/color] [color=#888888]Not equipped[/color]\n\n"

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
	"""Get display name for an item"""
	if def.has("sigil_instance") and def.has("name"):
		return String(def["name"])
	for key in ["name", "display_name", "label", "title"]:
		if def.has(key):
			var val: String = String(def[key]).strip_edges()
			if val != "":
				return val
	return item_id.replace("_", " ").capitalize()

func _get_description(def: Dictionary) -> String:
	return String(def.get("description", ""))

func _member_display_name(token: String) -> String:
	if _gs and _gs.has_method("_first_name_for_id"):
		return _gs.call("_first_name_for_id", token)
	return token

func _get_sigil_equipped_by(sigil_instance_id: String) -> String:
	"""Check which party member (if any) has this sigil equipped. Returns member token or empty string."""
	if not _sig:
		return ""

	# Get all party members
	var members: Array[String] = _gather_members()

	# Check each member's loadout
	for member in members:
		if _sig.has_method("get_loadout"):
			var loadout: Variant = _sig.call("get_loadout", member)
			# Convert to array if it's a PackedStringArray
			var loadout_array: Array[String] = []
			if typeof(loadout) == TYPE_PACKED_STRING_ARRAY:
				for inst_id in (loadout as PackedStringArray):
					loadout_array.append(String(inst_id))
			elif typeof(loadout) == TYPE_ARRAY:
				for inst_id in (loadout as Array):
					loadout_array.append(String(inst_id))

			# Check if this sigil instance is in the loadout
			if loadout_array.has(sigil_instance_id):
				return member

	return ""

func _input(event: InputEvent) -> void:
	"""Use _input() instead of _unhandled_input() for higher priority than GameMenu"""
	if not visible:
		return

	# Debug logging for party picker
	if _focus_mode == "party_picker" and event is InputEventJoypadButton:
		print("[ItemsPanel._input] party_picker mode, button: %d, pressed: %s" % [event.button_index, event.pressed])

	# Handle popup input at high priority to block GameMenu from seeing it
	if _focus_mode == "recovery_confirmation":
		# Block ALL input when recovery confirmation is showing
		if event is InputEventJoypadButton:
			print("[ItemsPanel._input] recovery_confirmation blocking button: %d, pressed: %s" % [event.button_index, event.pressed])
			if event.pressed:
				match event.button_index:
					0:  # Accept button
						print("[ItemsPanel._input] Accept button pressed on recovery confirmation")
						if _active_popup and is_instance_valid(_active_popup):
							var ok_btn = _active_popup.get_meta("ok_button", null)
							if ok_btn and is_instance_valid(ok_btn):
								ok_btn.emit_signal("pressed")
						get_viewport().set_input_as_handled()
						return
					_:
						# Block all other button presses from reaching GameMenu
						get_viewport().set_input_as_handled()
						return
			else:
				# Block button releases too
				get_viewport().set_input_as_handled()
				return
		elif event is InputEventJoypadMotion:
			# Block joystick motion
			get_viewport().set_input_as_handled()
			return

	if _focus_mode == "party_picker":
		# Allow joystick motion for ItemList navigation
		if event is InputEventJoypadMotion:
			# Let joystick motion pass through to ItemList for up/down navigation
			return

		if event is InputEventJoypadButton and event.pressed:
			match event.button_index:
				0:  # Accept button
					_on_party_picker_accept()
					get_viewport().set_input_as_handled()
					return
				1:  # Back button (B/Circle)
					# Find the popup panel to close
					if _active_popup and is_instance_valid(_active_popup):
						_close_member_selection_popup(_active_popup, false)
					get_viewport().set_input_as_handled()
					return
				12, 13, 14, 15:  # D-pad (up, down, left, right) - let ItemList handle these
					# Don't handle these - let them pass through to the ItemList for navigation
					return
				_:
					# Block all other inputs from reaching GameMenu (but don't handle navigation)
					get_viewport().set_input_as_handled()
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
			11:  # D-pad Up
				print("[ItemsPanel] D-pad Up pressed")
				_navigate_items(-2)  # UP in column: -2
				get_viewport().set_input_as_handled()
				return
			12:  # D-pad Down
				print("[ItemsPanel] D-pad Down pressed")
				_navigate_items(2)  # DOWN in column: +2
				get_viewport().set_input_as_handled()
				return
			13:  # D-pad Left
				print("[ItemsPanel] D-pad Left pressed")
				_navigate_items(-1)  # LEFT cycles BACKWARDS: -1
				get_viewport().set_input_as_handled()
				return
			14:  # D-pad Right (CORRECT button number!)
				print("[ItemsPanel] D-pad Right pressed")
				_navigate_items(1)  # RIGHT cycles FORWARDS: +1
				get_viewport().set_input_as_handled()
				return
			0:  # Accept button (A/Cross)
				print("[ItemsPanel] Accept button pressed")
				_on_accept_pressed()
				get_viewport().set_input_as_handled()
				return

func _navigate_items(delta: int) -> void:
	"""Navigate items with wrapping in 2-column grid"""
	if _item_buttons.size() == 0:
		return

	var current = _selected_grid_index
	var total = _item_buttons.size()

	# Calculate row and column (2 columns) for logging
	var current_row = current / 2
	var current_col = current % 2
	var col_name = "LEFT" if current_col == 0 else "RIGHT"
	var item_name = _item_buttons[current].text if current < _item_buttons.size() else "?"

	print("[ItemsPanel] Navigation from '%s' at index %d (Row %d, %s column), delta=%d" % [item_name, current, current_row, col_name, delta])

	# Apply delta with wrapping
	var new_index = (current + delta) % total

	# Handle negative wrapping (e.g., -1 from index 0 should go to last item)
	if new_index < 0:
		new_index = total + new_index

	var new_row = new_index / 2
	var new_col = new_index % 2
	var new_col_name = "LEFT" if new_col == 0 else "RIGHT"
	var new_item_name = _item_buttons[new_index].text if new_index < _item_buttons.size() else "?"
	print("[ItemsPanel]   → Moving TO '%s' at index %d (Row %d, %s column)" % [new_item_name, new_index, new_row, new_col_name])

	_selected_grid_index = new_index
	_selected_item_id = _item_ids[_selected_grid_index]
	_update_selection_highlight()
	_update_details()
	_update_arrow_position()

func _update_selection_highlight() -> void:
	"""Update visual highlight on selected button"""
	for i in range(_item_buttons.size()):
		var button: Button = _item_buttons[i]
		var is_selected: bool = (i == _selected_grid_index)

		# Create style based on selection state
		var style = StyleBoxFlat.new()
		if is_selected:
			# Selected: Sky Cyan background
			style.bg_color = aCoreVibeTheme.COLOR_SKY_CYAN
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = aCoreVibeTheme.COLOR_ELECTRIC_LIME
			button.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_INK_CHARCOAL)
		else:
			# Normal: Dark background
			style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
			button.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)

		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4

		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)

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
	"""Use recovery item - show party picker popup"""
	print("[ItemsPanel] Use button pressed for: %s" % _selected_item_id)
	_show_member_selection_popup()

func _on_inspect_button_pressed() -> void:
	print("[ItemsPanel] Inspect button pressed for: %s" % _selected_item_id)

# ==============================================================================
# Party Picker Popup Functions
# ==============================================================================

func _show_member_selection_popup() -> void:
	"""Show popup to select which party member to use item on - matches StatusPanel pattern"""
	if _selected_item_id == "":
		return

	var def: Dictionary = _defs.get(_selected_item_id, {})
	var item_name: String = _display_name(_selected_item_id, def)

	print("[ItemsPanel] Showing member selection popup for: %s" % item_name)

	# Create CanvasLayer overlay (for paused context)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
	get_tree().root.add_child(overlay)
	get_tree().root.move_child(overlay, 0)

	# Create background blocker to prevent clicking and controller input through
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.5)  # Semi-transparent black
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all mouse input
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)  # Fill entire screen
	blocker.focus_mode = Control.FOCUS_ALL  # Allow it to receive input events
	overlay.add_child(blocker)

	# Create popup panel
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	popup_panel.modulate = Color(1, 1, 1, 0)  # Start transparent for fade in
	popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to elements behind
	overlay.add_child(popup_panel)

	# Apply consistent styling
	_style_popup_panel(popup_panel)

	# Store overlay reference
	popup_panel.set_meta("_overlay", overlay)

	# Create content container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title := Label.new()
	title.text = "Use %s on..." % item_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Member list
	_party_picker_list = ItemList.new()
	_party_picker_list.custom_minimum_size = Vector2(300, 250)
	_party_picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_party_picker_list.focus_mode = Control.FOCUS_ALL
	vbox.add_child(_party_picker_list)

	# Populate members
	var members: Array[String] = _gather_members()
	_party_member_tokens.clear()

	for member_token in members:
		var member_name: String = _member_display_name(member_token)
		var stats: Dictionary = _get_member_hp_mp(member_token)
		_party_picker_list.add_item("%s  HP:%d/%d  MP:%d/%d" % [
			member_name,
			stats["hp"], stats["hp_max"],
			stats["mp"], stats["mp_max"]
		])
		_party_member_tokens.append(member_token)

	# Add Cancel button
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): _close_member_selection_popup(popup_panel, false))
	vbox.add_child(cancel_btn)

	# Auto-size panel
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0

	# Store item info for use
	_item_to_use_id = _selected_item_id
	_item_to_use_def = def

	# Store popup reference
	popup_panel.set_meta("_item_list", _party_picker_list)

	# Fade in
	_fade_in_popup(popup_panel)

	# Select first and grab focus
	if _party_picker_list.item_count > 0:
		_party_picker_list.select(0)
		_party_picker_list.call_deferred("grab_focus")

	# Update focus mode
	_focus_mode = "party_picker"

	# Track active popup and overlay for cleanup
	_active_popup = popup_panel
	_active_overlay = overlay

	print("[ItemsPanel] Member selection popup shown with %d members" % _party_member_tokens.size())

func _style_popup_panel(popup: Panel) -> void:
	"""Apply Core Vibe neon-kawaii popup styling"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	popup.add_theme_stylebox_override("panel", style)

func _fade_in_popup(popup: Panel) -> void:
	"""Fade in popup"""
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup, "modulate", Color(1, 1, 1, 1), 0.2)
	await tween.finished
	popup.mouse_filter = Control.MOUSE_FILTER_STOP  # Enable input after fade

func _fade_out_popup(popup: Panel) -> void:
	"""Fade out popup"""
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Block input during fade
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup, "modulate", Color(1, 1, 1, 0), 0.2)
	await tween.finished

func _on_party_picker_accept() -> void:
	"""Handle A button in party picker popup"""
	print("[ItemsPanel] _on_party_picker_accept called")

	if not _party_picker_list or not is_instance_valid(_party_picker_list):
		print("[ItemsPanel] Party picker list is null or invalid")
		return

	var selected_indices: Array = _party_picker_list.get_selected_items()
	print("[ItemsPanel] Selected indices: %s" % str(selected_indices))
	if selected_indices.size() == 0:
		print("[ItemsPanel] No items selected in party picker")
		return

	var index: int = selected_indices[0]
	if index < 0 or index >= _party_member_tokens.size():
		print("[ItemsPanel] Invalid index: %d (tokens size: %d)" % [index, _party_member_tokens.size()])
		return

	var member_token: String = _party_member_tokens[index]
	print("[ItemsPanel] Using item on member: %s" % member_token)

	# Use item on member
	_use_item_on_member(_item_to_use_id, _item_to_use_def, member_token)

	# Close popup
	if _active_popup and is_instance_valid(_active_popup):
		_close_member_selection_popup(_active_popup, true)

func _close_member_selection_popup(popup_panel: Panel, used_item: bool) -> void:
	"""Close member selection popup and clean up"""
	print("[ItemsPanel] Closing member selection popup (used_item: %s)" % used_item)

	# Fade out
	await _fade_out_popup(popup_panel)

	# Get overlay reference
	var overlay = popup_panel.get_meta("_overlay", null)

	# Clean up popup
	if popup_panel and is_instance_valid(popup_panel):
		popup_panel.queue_free()

	# Clean up overlay
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()

	# Clear references
	_party_picker_list = null
	_party_member_tokens.clear()
	_item_to_use_id = ""
	_item_to_use_def = {}

	# Clear popup tracking
	_active_popup = null
	_active_overlay = null

	# Return focus mode
	_focus_mode = "items"

	# If item was used, rebuild happens automatically via inventory_changed signal
	# No need to manually rebuild here

func _use_item_on_member(item_id: String, item_def: Dictionary, member_token: String) -> void:
	"""Apply item effect to a party member"""
	print("[ItemsPanel] === USE ITEM START ===")
	print("[ItemsPanel] Item ID: %s, Member: %s" % [item_id, member_token])
	print("[ItemsPanel] Current _counts size: %d" % _counts.size())

	var effect: String = String(item_def.get("field_status_effect", ""))
	if effect == "":
		effect = String(item_def.get("battle_status_effect", ""))

	print("[ItemsPanel] Using %s on %s: %s" % [item_id, member_token, effect])

	# Get member's current stats
	var stats: Dictionary = _get_member_hp_mp(member_token)
	var hp: int = stats["hp"]
	var hp_max: int = stats["hp_max"]
	var mp: int = stats["mp"]
	var mp_max: int = stats["mp_max"]

	# Parse and apply healing effects
	var effect_lower: String = effect.to_lower()
	var new_hp: int = hp
	var new_mp: int = mp
	var healed: bool = false

	# Parse HP healing
	if effect_lower.contains("heal") and effect_lower.contains("hp"):
		if effect_lower.contains("100%") or effect_lower.contains("full"):
			# Full HP restore
			new_hp = hp_max
			healed = true
			print("[ItemsPanel] Full HP restore: %d -> %d" % [hp, new_hp])
		elif effect_lower.contains("%"):
			# Percentage HP heal
			var percent_match: RegExMatch = _extract_percentage(effect)
			if percent_match:
				var percent: float = float(percent_match.get_string()) / 100.0
				var heal_amount: int = int(hp_max * percent)
				new_hp = min(hp + heal_amount, hp_max)
				healed = true
				print("[ItemsPanel] %d%% HP heal: %d -> %d (+%d)" % [int(percent * 100), hp, new_hp, heal_amount])
		else:
			# Flat HP heal
			var amount_match: RegExMatch = _extract_number(effect)
			if amount_match:
				var heal_amount: int = int(amount_match.get_string())
				new_hp = min(hp + heal_amount, hp_max)
				healed = true
				print("[ItemsPanel] Flat HP heal: %d -> %d (+%d)" % [hp, new_hp, heal_amount])

	# Parse MP healing
	if effect_lower.contains("heal") and effect_lower.contains("mp"):
		if effect_lower.contains("100%") or effect_lower.contains("full"):
			# Full MP restore
			new_mp = mp_max
			healed = true
			print("[ItemsPanel] Full MP restore: %d -> %d" % [mp, new_mp])
		elif effect_lower.contains("%"):
			# Percentage MP heal
			var percent_match: RegExMatch = _extract_percentage(effect)
			if percent_match:
				var percent: float = float(percent_match.get_string()) / 100.0
				var heal_amount: int = int(mp_max * percent)
				new_mp = min(mp + heal_amount, mp_max)
				healed = true
				print("[ItemsPanel] %d%% MP heal: %d -> %d (+%d)" % [int(percent * 100), mp, new_mp, heal_amount])
		else:
			# Flat MP heal
			var amount_match: RegExMatch = _extract_number(effect)
			if amount_match:
				var heal_amount: int = int(amount_match.get_string())
				new_mp = min(mp + heal_amount, mp_max)
				healed = true
				print("[ItemsPanel] Flat MP heal: %d -> %d (+%d)" % [mp, new_mp, heal_amount])

	# Apply healing to member_data in GameState for persistence
	if healed and _gs:
		var member_data: Variant = _gs.get("member_data") if _gs.has_method("get") else {}
		if typeof(member_data) == TYPE_DICTIONARY:
			if not member_data.has(member_token):
				member_data[member_token] = {}
			var gs_rec: Dictionary = member_data[member_token]
			gs_rec["hp"] = new_hp
			gs_rec["mp"] = new_mp
			member_data[member_token] = gs_rec

			# Write back to GameState
			if _gs.has_method("set"):
				_gs.set("member_data", member_data)

			# Refresh combat profile to show updates
			if _cps and _cps.has_method("refresh_member"):
				_cps.call("refresh_member", member_token)

			print("[ItemsPanel] Updated GameState.member_data: HP=%d/%d, MP=%d/%d" % [new_hp, hp_max, new_mp, mp_max])

	# Consume the item
	print("[ItemsPanel] About to consume item: %s" % item_id)
	if _inv and _inv.has_method("remove_item"):
		_inv.call("remove_item", item_id, 1)
		print("[ItemsPanel] Item consumed, inventory should emit signal now")

	# Show recovery confirmation popup if item had healing effect
	if healed:
		var member_name: String = _member_display_name(member_token)
		var hp_healed: int = new_hp - hp
		var mp_healed: int = new_mp - mp

		# Build recovery message
		var recovery_parts: Array[String] = []
		if hp_healed > 0:
			recovery_parts.append("%d HP" % hp_healed)
		if mp_healed > 0:
			recovery_parts.append("%d MP" % mp_healed)

		if recovery_parts.size() > 0:
			var recovery_message: String = "%s recovered %s" % [member_name, " and ".join(recovery_parts)]
			await _show_recovery_confirmation(recovery_message)

	print("[ItemsPanel] _counts size after use: %d" % _counts.size())
	print("[ItemsPanel] === USE ITEM END ===")

func _extract_number(text: String) -> RegExMatch:
	"""Extract first number from text"""
	var regex: RegEx = RegEx.new()
	regex.compile("\\d+")
	return regex.search(text)

func _extract_percentage(text: String) -> RegExMatch:
	"""Extract percentage number from text (e.g., '25' from '25%')"""
	var regex: RegEx = RegEx.new()
	regex.compile("(\\d+)\\s*%")
	return regex.search(text)

func _gather_members() -> Array[String]:
	"""Get all party member tokens"""
	var members: Array[String] = []
	if not _gs:
		return members

	# Try active party methods
	for method in ["get_active_party_ids", "get_party_ids", "list_active_party"]:
		if _gs.has_method(method):
			var result: Variant = _gs.call(method)
			if typeof(result) == TYPE_PACKED_STRING_ARRAY:
				for s in (result as PackedStringArray):
					members.append(String(s))
			elif typeof(result) == TYPE_ARRAY:
				for s in (result as Array):
					members.append(String(s))
			if members.size() > 0:
				break

	# Add bench if needed
	if _gs.has_method("get"):
		var bench: Variant = _gs.get("bench")
		if typeof(bench) == TYPE_PACKED_STRING_ARRAY:
			for s in (bench as PackedStringArray):
				if not members.has(String(s)):
					members.append(String(s))
		elif typeof(bench) == TYPE_ARRAY:
			for s in (bench as Array):
				if not members.has(String(s)):
					members.append(String(s))

	return members

func _show_recovery_confirmation(message: String) -> void:
	"""Show recovery confirmation popup"""
	print("[ItemsPanel] Showing recovery confirmation: %s" % message)

	# PAUSE THE GAME TREE
	get_tree().paused = true
	print("[ItemsPanel] Game tree PAUSED")

	# Create CanvasLayer overlay (for paused context)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
	get_tree().root.add_child(overlay)
	get_tree().root.move_child(overlay, 0)  # Move to front of processing order

	# Create background blocker to prevent clicking through
	var blocker := ColorRect.new()
	blocker.color = Color(0, 0, 0, 0.5)  # Semi-transparent black
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all mouse input
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)  # Fill entire screen
	blocker.focus_mode = Control.FOCUS_ALL  # Allow it to receive input events
	overlay.add_child(blocker)

	# Create popup panel
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	popup_panel.modulate = Color(1, 1, 1, 0)
	popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input to elements behind
	overlay.add_child(popup_panel)

	# Apply styling
	_style_popup_panel(popup_panel)

	# Store overlay reference
	popup_panel.set_meta("_overlay", overlay)

	# Create content container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup_panel.add_child(vbox)

	# Message label
	var message_label := Label.new()
	message_label.text = message
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(message_label)

	# OK button
	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(100, 40)
	ok_btn.focus_mode = Control.FOCUS_ALL
	vbox.add_child(ok_btn)

	# Auto-size panel
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(40, 40)
	vbox.position = Vector2(20, 20)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0

	# Store reference for input handling
	popup_panel.set_meta("ok_button", ok_btn)
	popup_panel.set_meta("is_recovery_confirmation", true)
	_active_popup = popup_panel
	_focus_mode = "recovery_confirmation"

	# Fade in
	_fade_in_popup(popup_panel)

	# Give focus to OK button
	ok_btn.call_deferred("grab_focus")

	# Wait for OK button press
	await ok_btn.pressed

	# Clear focus mode
	_focus_mode = "items"
	_active_popup = null

	# Fade out
	await _fade_out_popup(popup_panel)

	# Clean up
	if popup_panel and is_instance_valid(popup_panel):
		popup_panel.queue_free()
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()

	# UNPAUSE THE GAME TREE
	get_tree().paused = false
	print("[ItemsPanel] Game tree UNPAUSED")

	print("[ItemsPanel] Recovery confirmation closed")

func _get_member_hp_mp(member_token: String) -> Dictionary:
	"""Get member HP/MP stats - matches StatusPanel implementation"""
	print("[ItemsPanel] Getting HP/MP for member: %s" % member_token)

	# Default values
	var hp_max: int = 150
	var mp_max: int = 20

	# Try to get combat profile for HP/MP (includes both current and max)
	if _cps and _cps.has_method("get_profile"):
		var p_v: Variant = _cps.call("get_profile", member_token)
		print("[ItemsPanel]   get_profile returned type: %d, value: %s" % [typeof(p_v), str(p_v)])
		if typeof(p_v) == TYPE_DICTIONARY:
			var p: Dictionary = p_v
			var hp_cur: int = int(p.get("hp", -1))
			hp_max = int(p.get("hp_max", -1))
			var mp_cur: int = int(p.get("mp", -1))
			mp_max = int(p.get("mp_max", -1))

			print("[ItemsPanel]   Extracted from profile: HP %d/%d, MP %d/%d" % [hp_cur, hp_max, mp_cur, mp_max])

			return {
				"hp": hp_cur,
				"hp_max": hp_max,
				"mp": mp_cur,
				"mp_max": mp_max
			}

	# Fallback: no profile data, compute max stats and assume full HP/MP
	print("[ItemsPanel]   No profile found, using fallback")
	if _gs and _gs.has_method("compute_member_pools"):
		var pools_v: Variant = _gs.call("compute_member_pools", member_token)
		print("[ItemsPanel]   compute_member_pools returned type: %d, value: %s" % [typeof(pools_v), str(pools_v)])
		if typeof(pools_v) == TYPE_DICTIONARY:
			var pools: Dictionary = pools_v
			hp_max = int(pools.get("hp_max", hp_max))
			mp_max = int(pools.get("mp_max", mp_max))
			print("[ItemsPanel]   Extracted from pools: hp_max=%d, mp_max=%d" % [hp_max, mp_max])

	print("[ItemsPanel]   Final fallback stats: HP %d/%d, MP %d/%d" % [hp_max, hp_max, mp_max, mp_max])
	return {
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max
	}
