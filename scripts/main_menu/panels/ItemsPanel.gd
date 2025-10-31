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
@onready var _item_label: Label = %ItemLabel
@onready var _count_label: Label = %CountLabel
@onready var _item_name: Label = %ItemName
@onready var _details_text: Label = %DetailsText
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
var _focus_mode: String = "category"  # "category" or "items"

# Active popup reference
var _active_popup: Panel = null

func _ready() -> void:
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
	_load_data()
	_populate_categories()
	_populate_items()
	_update_details()

func _load_data() -> void:
	"""Load item definitions and counts"""
	# Load definitions from CSV
	_defs.clear()
	if _csv and _csv.has_method("load_csv"):
		var loaded: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
		if typeof(loaded) == TYPE_DICTIONARY:
			_defs = loaded

	# Load counts from inventory
	_counts.clear()
	if _inv:
		if _inv.has_method("get_inventory"):
			var inv_data: Variant = _inv.call("get_inventory")
			if typeof(inv_data) == TYPE_DICTIONARY:
				_counts = inv_data.duplicate()
		elif _inv.has_method("get_counts"):
			var counts_data: Variant = _inv.call("get_counts")
			if typeof(counts_data) == TYPE_DICTIONARY:
				_counts = counts_data.duplicate()

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
	if not _item_list:
		return

	_item_list.clear()
	_item_ids.clear()

	# Update header
	if _item_label:
		_item_label.text = "Items (%s)" % _current_category

	# Gather items in category
	var items: Array[String] = []
	for item_id in _counts.keys():
		var qty: int = _counts[item_id]
		if qty <= 0:
			continue
		if _current_category == "All":
			items.append(item_id)
			continue
		var def: Dictionary = _defs.get(item_id, {})
		var item_cat: String = _category_of(def)
		if item_cat == _current_category:
			items.append(item_id)

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

	# Update count
	if _count_label:
		_count_label.text = "Count: %d" % items.size()

	# Select first item if available
	if _item_list.item_count > 0 and _selected_item_id == "":
		_item_list.select(0)
		_selected_item_id = _item_ids[0]

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

	_show_party_picker()

func _on_inspect_button_pressed() -> void:
	"""Handle Inspect button press"""
	if _selected_item_id == "":
		return

	# TODO: Show detailed inspect dialog
	print("[ItemsPanel] Inspect: ", _selected_item_id)

func _on_equipment_changed(_member: String) -> void:
	"""Handle equipment change"""
	_rebuild()

func _show_party_picker() -> void:
	"""Show party member picker popup for item usage"""
	if _selected_item_id == "":
		return

	var def: Dictionary = _defs.get(_selected_item_id, {})
	var name: String = _display_name(_selected_item_id, def)

	# Create popup panel
	var popup_panel: Panel = Panel.new()
	popup_panel.custom_minimum_size = Vector2(300, 250)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	popup_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = "Use %s on:" % name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Party member list
	var member_list: ItemList = ItemList.new()
	member_list.custom_minimum_size = Vector2(280, 180)
	member_list.focus_mode = Control.FOCUS_ALL
	vbox.add_child(member_list)

	# Populate members
	var members: Array[String] = _gather_members()
	var member_tokens: Array[String] = []

	for member_token in members:
		var member_name: String = _member_display_name(member_token)
		var stats: Dictionary = _get_member_hp_mp(member_token)
		member_list.add_item("%s  HP:%d/%d  MP:%d/%d" % [
			member_name,
			stats["hp"], stats["hp_max"],
			stats["mp"], stats["mp_max"]
		])
		member_tokens.append(member_token)

	if member_list.item_count > 0:
		member_list.select(0)
		member_list.grab_focus()

	# Store metadata
	popup_panel.set_meta("_member_list", member_list)
	popup_panel.set_meta("_member_tokens", member_tokens)
	popup_panel.set_meta("_item_id", _selected_item_id)
	popup_panel.set_meta("_item_def", def)

	# Add to scene
	add_child(popup_panel)
	_active_popup = popup_panel

	# Position popup
	var popup_pos: Vector2 = get_viewport_rect().size / 2.0 - popup_panel.custom_minimum_size / 2.0
	popup_panel.position = popup_pos

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input"""
	if not visible:
		return

	# Handle popup input
	if _active_popup and is_instance_valid(_active_popup):
		if event.is_action_pressed("menu_accept"):
			_on_popup_accept()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("menu_back"):
			_close_popup()
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
		if event.is_action_pressed("menu_back") or event.is_action_pressed("ui_left"):
			# Return to category list
			_focus_mode = "category"
			_category_list.grab_focus()
			get_viewport().set_input_as_handled()

func _on_popup_accept() -> void:
	"""Handle A button in popup"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var member_list: ItemList = _active_popup.get_meta("_member_list")
	var member_tokens: Array = _active_popup.get_meta("_member_tokens")
	var item_id: String = _active_popup.get_meta("_item_id")
	var item_def: Dictionary = _active_popup.get_meta("_item_def")

	var selected_indices: Array = member_list.get_selected_items()
	if selected_indices.size() == 0:
		return

	var index: int = selected_indices[0]
	if index < 0 or index >= member_tokens.size():
		return

	var member_token: String = member_tokens[index]
	_use_item_on_member(item_id, item_def, member_token)
	_close_popup()

func _close_popup() -> void:
	"""Close active popup"""
	if _active_popup and is_instance_valid(_active_popup):
		_active_popup.queue_free()
		_active_popup = null

	# Return focus to appropriate list
	if _focus_mode == "items" and _item_list:
		_item_list.grab_focus()
	elif _category_list:
		_category_list.grab_focus()

func _use_item_on_member(item_id: String, item_def: Dictionary, member_token: String) -> void:
	"""Apply item effect to a party member"""
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
	if _inv and _inv.has_method("remove_item"):
		_inv.call("remove_item", item_id, 1)

	# Show confirmation
	var member_name: String = _member_display_name(member_token)
	var item_name: String = _display_name(item_id, item_def)
	print("[ItemsPanel] Used %s on %s" % [item_name, member_name])

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
