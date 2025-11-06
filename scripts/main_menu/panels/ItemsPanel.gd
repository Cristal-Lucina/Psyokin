extends Control
class_name ItemsPanel

## Items Panel - Clean 3-Column Controller-First Design
## LEFT: Category selection | MIDDLE: Item list | RIGHT: Item details + actions

# Autoload paths
const INV_PATH   : String = "/root/aInventorySystem"
const CSV_PATH   : String = "/root/aCSVLoader"
const SIGIL_PATH : String = "/root/aSigilSystem"
const EQUIP_PATH : String = "/root/aEquipmentSystem"
const GS_PATH    : String = "/root/aGameState"
const CPS_PATH   : String = "/root/aCombatProfileSystem"

# CSV data
const ITEMS_CSV : String = "res://data/items/items.csv"
const KEY_ID    : String = "item_id"

# Categories
const CATEGORIES : Array[String] = [
	"All", "Recovery", "Consumables", "Weapons", "Armor", "Headwear", "Footwear",
	"Bracelets", "Sigils", "Materials", "Key", "Other"
]

# Scene references
@onready var _category_list: ItemList = %CategoryList
@onready var _item_list: ItemList = %ItemList
@onready var _item_label: Label = %ItemLabel  # Now in ItemColumn (moved from ItemHeader)
@onready var _count_label: Label = %CountLabel  # Now in ItemHeader
@onready var _item_name: Label = %ItemName
@onready var _details_text: Label = %DetailsText
@onready var _scroll_container: ScrollContainer = %ScrollContainer
@onready var _action_buttons: VBoxContainer = %ActionButtons
@onready var _use_button: Button = %UseButton
@onready var _inspect_button: Button = %InspectButton

# System references
var _inv: Node = null
var _csv: Node = null
var _sig: Node = null
var _eq: Node = null
var _gs: Node = null
var _cps: Node = null

# Data
var _defs: Dictionary = {}          # item_id -> item definition dict
var _counts: Dictionary = {}        # item_id -> count
var _equipped_by: Dictionary = {}   # item_id -> Array[member names]

# State
var _current_category: String = "All"
var _category_ids: Array[String] = []
var _item_ids: Array[String] = []
var _selected_item_id: String = ""
var _focus_mode: String = "category"  # "category", "items", or "party_picker"

# Party picker state
var _party_picker_list: ItemList = null
var _party_member_tokens: Array[String] = []
var _item_to_use_id: String = ""
var _item_to_use_def: Dictionary = {}

func _ready() -> void:
	# Set process mode to work while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Get system references
	_inv = get_node_or_null(INV_PATH)
	_csv = get_node_or_null(CSV_PATH)
	_sig = get_node_or_null(SIGIL_PATH)
	_eq = get_node_or_null(EQUIP_PATH)
	_gs = get_node_or_null(GS_PATH)
	_cps = get_node_or_null(CPS_PATH)

	# Connect signals
	if _category_list:
		_category_list.item_selected.connect(_on_category_selected)
	if _item_list:
		_item_list.item_selected.connect(_on_item_selected)
	if _use_button:
		_use_button.pressed.connect(_on_use_button_pressed)
	if _inspect_button:
		_inspect_button.pressed.connect(_on_inspect_button_pressed)

	# Connect inventory changes
	if _inv and _inv.has_signal("inventory_changed"):
		if not _inv.is_connected("inventory_changed", Callable(self, "_rebuild")):
			_inv.connect("inventory_changed", Callable(self, "_rebuild"))

	# Connect equipment changes
	if _eq and _eq.has_signal("equipment_changed"):
		if not _eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
			_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	# Connect visibility
	visibility_changed.connect(_on_visibility_changed)

	# Initial build
	call_deferred("_first_fill")

func _first_fill() -> void:
	"""Initial population of UI"""
	_rebuild()
	if _category_list and _category_list.item_count > 0:
		_category_list.select(0)
		call_deferred("_grab_category_focus")

func _on_visibility_changed() -> void:
	"""Grab focus when panel becomes visible"""
	if visible:
		call_deferred("_grab_category_focus")

func _grab_category_focus() -> void:
	"""Helper to grab focus on category list"""
	if _category_list and _category_list.item_count > 0:
		_focus_mode = "category"
		_category_list.grab_focus()

func _rebuild() -> void:
	"""Rebuild entire panel - refresh data and UI"""
	print("[ItemsPanel] === REBUILD CALLED ===")
	print("[ItemsPanel] Current focus_mode: %s" % _focus_mode)

	# Don't rebuild while party picker is active - it will rebuild when closed
	if _focus_mode == "party_picker":
		print("[ItemsPanel] Skipping rebuild - party picker is active")
		return

	_load_data()
	_populate_categories()
	_populate_items()
	_update_details()
	print("[ItemsPanel] === REBUILD COMPLETE ===")

func _load_data() -> void:
	"""Load item definitions and counts"""
	# Load definitions from CSV
	_defs.clear()

	print("[ItemsPanel] _csv is null: %s" % (_csv == null))
	if _csv:
		print("[ItemsPanel] _csv has load_csv: %s" % _csv.has_method("load_csv"))

	if _csv and _csv.has_method("load_csv"):
		print("[ItemsPanel] Calling load_csv with path: %s, key: %s" % [ITEMS_CSV, KEY_ID])
		var loaded: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
		print("[ItemsPanel] load_csv returned type: %d" % typeof(loaded))

		if typeof(loaded) == TYPE_DICTIONARY:
			# IMPORTANT: Duplicate to avoid modifying CSV loader's internal cache!
			_defs = (loaded as Dictionary).duplicate(true)
			print("[ItemsPanel] Loaded %d item definitions from CSV" % _defs.size())
			# Check a sample item definition
			if _defs.has("HP_002"):
				var sample: Dictionary = _defs["HP_002"]
				print("[ItemsPanel] Sample HP_002 def keys: %s" % str(sample.keys()))
				print("[ItemsPanel] Sample HP_002 category: %s" % sample.get("category", "MISSING"))
		else:
			print("[ItemsPanel] ERROR: CSV load returned wrong type! Expected Dictionary (27), got type %d" % typeof(loaded))

	# Load counts from inventory
	_counts.clear()
	if _inv:
		if _inv.has_method("get_counts"):
			var counts_data: Variant = _inv.call("get_counts")
			print("[ItemsPanel] get_counts returned type: ", typeof(counts_data))
			if typeof(counts_data) == TYPE_DICTIONARY:
				# Deep duplicate to avoid any reference issues
				var raw_counts: Dictionary = counts_data
				for item_id in raw_counts.keys():
					# Skip comment entries (start with #)
					var id_str: String = String(item_id)
					if id_str.begins_with("#"):
						continue
					var qty: Variant = raw_counts[item_id]
					if typeof(qty) == TYPE_FLOAT or typeof(qty) == TYPE_INT:
						var qty_int: int = int(qty)
						if qty_int > 0:
							_counts[id_str] = qty_int
				print("[ItemsPanel] Loaded %d items from get_counts (filtered %d comments)" % [_counts.size(), raw_counts.size() - _counts.size()])
		elif _inv.has_method("get_inventory"):
			var inv_data: Variant = _inv.call("get_inventory")
			print("[ItemsPanel] get_inventory returned type: ", typeof(inv_data))
			if typeof(inv_data) == TYPE_DICTIONARY:
				_counts = inv_data.duplicate()
				print("[ItemsPanel] Loaded %d items from get_inventory" % _counts.size())

	print("[ItemsPanel] After loading, _counts has %d items" % _counts.size())

	# Load equipped items
	_equipped_by.clear()
	_load_equipped_items()

	# Add sigil instances
	_add_sigil_instances()

func _load_equipped_items() -> void:
	"""Build map of which items are equipped by which members"""
	if not _eq or not _gs:
		return

	var members: Array[String] = _gather_members()
	for member in members:
		var equip: Dictionary = _get_equipment(member)
		for slot in ["weapon", "armor", "head", "foot", "bracelet"]:
			var item_id: String = String(equip.get(slot, ""))
			if item_id != "" and item_id != "—":
				if not _equipped_by.has(item_id):
					_equipped_by[item_id] = []
				var member_name: String = _member_display_name(member)
				if not _equipped_by[item_id].has(member_name):
					_equipped_by[item_id].append(member_name)

func _add_sigil_instances() -> void:
	"""Add sigil instances as virtual items"""
	if not _sig:
		return

	# Get all sigil instances
	var instances: Array = []
	if _sig.has_method("get_all_instances"):
		var inst_data: Variant = _sig.call("get_all_instances")
		if typeof(inst_data) == TYPE_ARRAY:
			instances = inst_data

	for inst in instances:
		if typeof(inst) != TYPE_DICTIONARY:
			continue
		var inst_dict: Dictionary = inst
		var inst_id: String = String(inst_dict.get("instance_id", ""))
		if inst_id == "":
			continue

		# Create virtual item def
		var base_id: String = String(inst_dict.get("sigil_id", ""))
		var base_def: Dictionary = _defs.get(base_id, {})

		var virtual_def: Dictionary = base_def.duplicate()
		virtual_def["sigil_instance"] = true
		virtual_def["instance_id"] = inst_id
		virtual_def["name"] = _format_sigil_name(inst_dict, base_def)
		virtual_def["category"] = "Sigils"

		_defs[inst_id] = virtual_def
		_counts[inst_id] = 1

func _format_sigil_name(inst: Dictionary, base_def: Dictionary) -> String:
	"""Format sigil instance name with level"""
	var base_name: String = String(base_def.get("name", "Sigil"))
	var level: int = int(inst.get("level", 1))
	return "%s Lv.%d" % [base_name, level]

func _populate_categories() -> void:
	"""Populate category list"""
	if not _category_list:
		return

	var prev_selection: int = _category_list.get_selected_items()[0] if _category_list.get_selected_items().size() > 0 else 0

	_category_list.clear()
	_category_ids.clear()

	for cat in CATEGORIES:
		var count: int = _count_items_in_category(cat)
		_category_list.add_item("%s (%d)" % [cat, count])
		_category_ids.append(cat)

	# Restore selection
	if prev_selection >= 0 and prev_selection < _category_list.item_count:
		_category_list.select(prev_selection)
		_current_category = _category_ids[prev_selection]

func _count_items_in_category(category: String) -> int:
	"""Count items in a category"""
	var count: int = 0
	for item_id in _counts.keys():
		var qty: int = _counts[item_id]
		if qty <= 0:
			continue
		if category == "All":
			count += 1
			continue
		var def: Dictionary = _defs.get(item_id, {})
		var item_cat: String = _category_of(def)
		if item_cat == category:
			count += 1
	return count

func _populate_items() -> void:
	"""Populate item list based on current category"""
	print("[ItemsPanel] _populate_items() called, category: %s" % _current_category)
	if not _item_list:
		print("[ItemsPanel] ERROR: _item_list is null!")
		return

	_item_list.clear()
	_item_ids.clear()

	# Update header
	if _item_label:
		_item_label.text = "Items (%s)" % _current_category

	# Gather items in category
	var items: Array[String] = []
	print("[ItemsPanel] Starting to gather items from %d entries in _counts" % _counts.size())
	for item_id in _counts.keys():
		var qty: int = _counts[item_id]
		if qty <= 0:
			continue
		if _current_category == "All":
			items.append(item_id)
			continue
		var def: Dictionary = _defs.get(item_id, {})
		var item_cat: String = _category_of(def)
		# Debug first few items
		if items.size() < 3:
			print("[ItemsPanel] DEBUG: item_id=%s, has_def=%s, def_size=%d, category=%s" % [item_id, _defs.has(item_id), def.size(), item_cat])
		if item_cat == _current_category:
			items.append(item_id)
			print("[ItemsPanel] Added %s (cat: %s, qty: %d)" % [item_id, item_cat, qty])

	print("[ItemsPanel] Gathered %d items for category '%s'" % [items.size(), _current_category])

	# Sort by name
	items.sort_custom(func(a: String, b: String) -> bool:
		var def_a: Dictionary = _defs.get(a, {})
		var def_b: Dictionary = _defs.get(b, {})
		var name_a: String = _display_name(a, def_a)
		var name_b: String = _display_name(b, def_b)
		return name_a < name_b
	)

	# Populate list
	for item_id in items:
		var def: Dictionary = _defs.get(item_id, {})
		var qty: int = _counts.get(item_id, 0)
		var name: String = _display_name(item_id, def)
		_item_list.add_item("%s  x%d" % [name, qty])
		_item_ids.append(item_id)

	print("[ItemsPanel] Added %d items to ItemList UI" % _item_list.item_count)

	# Update count
	if _count_label:
		_count_label.text = "Count: %d" % items.size()

	# Select first item if available
	if _item_list.item_count > 0 and _selected_item_id == "":
		_item_list.select(0)
		_selected_item_id = _item_ids[0]
		print("[ItemsPanel] Selected first item: %s" % _selected_item_id)
	else:
		print("[ItemsPanel] No items to select or item already selected: %s" % _selected_item_id)

func _update_details() -> void:
	"""Update item details panel"""
	if _selected_item_id == "" or not _defs.has(_selected_item_id):
		_clear_details()
		return

	var def: Dictionary = _defs[_selected_item_id]
	var qty: int = _counts.get(_selected_item_id, 0)
	var name: String = _display_name(_selected_item_id, def)

	# Update name
	if _item_name:
		_item_name.text = name

	# Build details text
	var details: String = ""

	# Quantity
	details += "Quantity: x%d\n\n" % qty

	# Description
	var desc: String = _get_description(def)
	if desc != "":
		details += "%s\n\n" % desc

	# Category
	var cat: String = _category_of(def)
	details += "Category: %s\n\n" % cat

	# Equipped by
	if _equipped_by.has(_selected_item_id):
		var members: Array = _equipped_by[_selected_item_id]
		if members.size() > 0:
			details += "Equipped by: %s\n\n" % ", ".join(members)

	# Effects
	var effects: String = _get_effects(def)
	if effects != "":
		details += "Effects:\n%s\n" % effects

	if _details_text:
		_details_text.text = details

	# Show/hide action buttons
	_update_action_buttons(def)

func _clear_details() -> void:
	"""Clear details panel"""
	if _item_name:
		_item_name.text = "(Select an item)"
	if _details_text:
		_details_text.text = ""
	if _use_button:
		_use_button.visible = false
	if _inspect_button:
		_inspect_button.visible = false

func _update_action_buttons(def: Dictionary) -> void:
	"""Show/hide action buttons based on item type"""
	var is_recovery: bool = _is_recovery_item(def)

	if _use_button:
		_use_button.visible = is_recovery
	if _inspect_button:
		_inspect_button.visible = true

func _on_category_selected(index: int) -> void:
	"""Handle category selection"""
	if index < 0 or index >= _category_ids.size():
		return

	_current_category = _category_ids[index]
	_selected_item_id = ""  # Reset item selection
	_populate_items()
	_update_details()

func _on_item_selected(index: int) -> void:
	"""Handle item selection"""
	if index < 0 or index >= _item_ids.size():
		return

	_selected_item_id = _item_ids[index]
	_update_details()

func _on_use_button_pressed() -> void:
	"""Handle Use button press"""
	if _selected_item_id == "":
		return

	var def: Dictionary = _defs.get(_selected_item_id, {})
	if not _is_recovery_item(def):
		return

	_show_member_selection_popup()

func _on_inspect_button_pressed() -> void:
	"""Handle Inspect button press"""
	if _selected_item_id == "":
		return

	# TODO: Show detailed inspect dialog
	print("[ItemsPanel] Inspect: ", _selected_item_id)

func _on_equipment_changed(_member: String) -> void:
	"""Handle equipment change"""
	_rebuild()

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

	# Create popup panel
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	popup_panel.modulate = Color(1, 1, 1, 0)  # Start transparent for fade in
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

	print("[ItemsPanel] Member selection popup shown with %d members" % _party_member_tokens.size())

func _style_popup_panel(popup: Panel) -> void:
	"""Apply consistent popup styling"""
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.border_color = Color(1.0, 0.7, 0.75, 1.0)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
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

func _grab_party_picker_focus() -> void:
	"""Helper to grab focus on party picker"""
	if _party_picker_list and is_instance_valid(_party_picker_list) and _party_picker_list.is_inside_tree():
		_party_picker_list.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input"""
	if not visible:
		return

	# Handle party picker popup input
	if _focus_mode == "party_picker":
		if event.is_action_pressed("menu_accept"):
			_on_party_picker_accept()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("menu_back"):
			# Find the popup panel to close
			if _party_picker_list and is_instance_valid(_party_picker_list):
				var popup = _party_picker_list.get_parent().get_parent()  # vbox -> popup_panel
				if popup is Panel:
					_close_member_selection_popup(popup, false)
			get_viewport().set_input_as_handled()
			return
		return

	# Handle focus switching
	if _focus_mode == "category":
		if event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_right"):
			# Move to item list if available
			if _item_list and _item_list.item_count > 0:
				_focus_mode = "items"
				_item_list.grab_focus()
				get_viewport().set_input_as_handled()
	elif _focus_mode == "items":
		if event.is_action_pressed("menu_accept"):
			# If Use button is visible (recovery item), trigger it
			if _use_button and _use_button.visible:
				_on_use_button_pressed()
				get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_back") or event.is_action_pressed("ui_left"):
			# Return to category list
			_focus_mode = "category"
			_category_list.grab_focus()
			get_viewport().set_input_as_handled()

func _on_party_picker_accept() -> void:
	"""Handle A button in party picker popup"""
	if not _party_picker_list or not is_instance_valid(_party_picker_list):
		return

	var selected_indices: Array = _party_picker_list.get_selected_items()
	if selected_indices.size() == 0:
		return

	var index: int = selected_indices[0]
	if index < 0 or index >= _party_member_tokens.size():
		return

	var member_token: String = _party_member_tokens[index]

	# Find the popup panel to close
	var popup = _party_picker_list.get_parent().get_parent()  # vbox -> popup_panel
	if popup is Panel:
		# Use item on member
		_use_item_on_member(_item_to_use_id, _item_to_use_def, member_token)
		# Close popup
		_close_member_selection_popup(popup, true)

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

	# Return focus mode
	_focus_mode = "items"

	# If item was used, rebuild to refresh counts
	if used_item:
		_rebuild()

	# Grab focus back
	if _item_list and _item_list.item_count > 0:
		_item_list.grab_focus()
	else:
		# No items in this category, return to category list
		_focus_mode = "category"
		if _category_list:
			_category_list.grab_focus()

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

	# Apply healing to GameState.member_data for persistence
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

	# Show confirmation
	var member_name: String = _member_display_name(member_token)
	var item_name: String = _display_name(item_id, item_def)
	print("[ItemsPanel] Used %s on %s" % [item_name, member_name])

	# Show heal confirmation toast if item had healing effect
	if healed:
		# Calculate actual heal amounts
		var hp_healed: int = new_hp - hp
		var mp_healed: int = new_mp - mp

		# Build heal message
		var heal_parts: Array[String] = []
		if hp_healed > 0:
			heal_parts.append("HP: +%d" % hp_healed)
		if mp_healed > 0:
			heal_parts.append("MP: +%d" % mp_healed)

		var heal_message: String = "%s Healed %s" % [member_name, ", ".join(heal_parts)]

		var overlay := CanvasLayer.new()
		overlay.layer = 100
		overlay.process_mode = Node.PROCESS_MODE_ALWAYS
		overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
		get_tree().root.add_child(overlay)
		get_tree().root.move_child(overlay, 0)

		var popup := ToastPopup.create(heal_message, "Recovery")
		popup.process_mode = Node.PROCESS_MODE_ALWAYS
		overlay.add_child(popup)
		await popup.confirmed
		popup.queue_free()
		overlay.queue_free()

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

# ==============================================================================
# Helper Functions
# ==============================================================================

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

func _category_of(def: Dictionary) -> String:
	"""Get category of an item"""
	# Check if it's a recovery item first (HP/MP healing)
	if _is_recovery_item(def):
		return "Recovery"

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
		"consumable": "Consumables", "consumables": "Consumables",
		"weapon": "Weapons", "weapons": "Weapons",
		"armor": "Armor",
		"head": "Headwear", "headwear": "Headwear", "helm": "Headwear",
		"foot": "Footwear", "footwear": "Footwear", "boots": "Footwear",
		"bracelet": "Bracelets", "bracelets": "Bracelets", "bangle": "Bracelets",
		"sigil": "Sigils", "sigils": "Sigils",
		"material": "Materials", "materials": "Materials",
		"key": "Key", "key item": "Key", "key items": "Key",
		"other": "Other"
	}

	if MAP.has(key):
		return MAP[key]
	if CATEGORIES.has(cat):
		return cat
	return ""

func _get_description(def: Dictionary) -> String:
	"""Get item description"""
	for key in ["description", "desc", "text", "info"]:
		if def.has(key):
			var val: String = String(def[key]).strip_edges()
			if val != "":
				return val
	return ""

func _get_effects(def: Dictionary) -> String:
	"""Get item effects text"""
	var effects: String = ""

	if def.has("field_status_effect"):
		effects += "Field: %s\n" % String(def["field_status_effect"])
	if def.has("battle_status_effect"):
		effects += "Battle: %s\n" % String(def["battle_status_effect"])

	return effects.strip_edges()

func _is_recovery_item(def: Dictionary) -> bool:
	"""Check if item is a recovery item (HP/MP healing)"""
	for key in ["field_status_effect", "battle_status_effect"]:
		if def.has(key):
			var effect: String = String(def[key]).to_lower()
			if (effect.contains("heal") or effect.contains("restore")) and (effect.contains("hp") or effect.contains("mp")):
				return true
	return false

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

func _member_display_name(token: String) -> String:
	"""Get display name for a party member"""
	if token == "hero":
		if _gs and _gs.has_method("get"):
			var name: String = String(_gs.get("player_name"))
			if name.strip_edges() != "":
				return name
		return "Player"

	if _gs and _gs.has_method("_display_name_for_id"):
		var name: Variant = _gs.call("_display_name_for_id", token)
		if typeof(name) == TYPE_STRING and String(name) != "":
			return String(name)

	return token.capitalize()

func _get_equipment(member: String) -> Dictionary:
	"""Get equipped items for a member"""
	if _gs and _gs.has_method("get_member_equip"):
		var equip: Variant = _gs.call("get_member_equip", member)
		if typeof(equip) == TYPE_DICTIONARY:
			return equip
	return {}

func _get_member_hp_mp(member_token: String) -> Dictionary:
	"""Get member HP/MP stats"""
	var stats: Dictionary = {"hp": 0, "hp_max": 0, "mp": 0, "mp_max": 0}

	# Get max HP/MP from pools
	if _gs and _gs.has_method("compute_member_pools"):
		var pools: Variant = _gs.call("compute_member_pools", member_token)
		if typeof(pools) == TYPE_DICTIONARY:
			stats["hp_max"] = int(pools.get("hp_max", 0))
			stats["mp_max"] = int(pools.get("mp_max", 0))

	# Get current HP/MP from combat profiles
	if _cps and _cps.has_method("get_profile"):
		var profile: Variant = _cps.call("get_profile", member_token)
		if typeof(profile) == TYPE_DICTIONARY:
			stats["hp"] = int(profile.get("hp", stats["hp_max"]))
			stats["mp"] = int(profile.get("mp", stats["mp_max"]))
	else:
		stats["hp"] = stats["hp_max"]
		stats["mp"] = stats["mp_max"]

	return stats
