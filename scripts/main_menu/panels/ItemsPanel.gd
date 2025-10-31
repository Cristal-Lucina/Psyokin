extends Control
class_name ItemsPanel

## ItemsPanel — CSV is source-of-truth; show only owned (>0) CSV-defined items.
## Also injects per-instance Sigils from aSigilSystem as virtual rows.
## Non-instanced equipment is expanded into virtual 1x rows (equipped + inventory).

const INV_PATH       : String = "/root/aInventorySystem"
const CSV_PATH       : String = "/root/aCSVLoader"
const SIGIL_SYS_PATH : String = "/root/aSigilSystem"
const EQUIP_SYS_PATH : String = "/root/aEquipmentSystem"
const GS_PATH        : String = "/root/aGameState"
const STATS_PATH     : String = "/root/aStatsSystem"
const INPUT_MGR_PATH : String = "/root/aInputManager"
const INSPECT_SCENE  : String = "res://scenes/main_menu/panels/ItemInspect.tscn"

const ITEMS_CSV : String = "res://data/items/items.csv"
const KEY_ID    : String = "item_id"

const CATEGORIES : PackedStringArray = [
	"All","Consumables","Bindings","Weapons","Armor","Headwear","Footwear",
	"Bracelets","Sigils","Battle","Materials","Gifts","Key","Other"
]

@onready var _filter_container : HBoxContainer = null  # Will create dynamically
@onready var _refresh   : Button        = %RefreshBtn
@onready var _counts_tv : Label         = %CountsValue
@onready var _list_box  : GridContainer = null  # Will change to GridContainer
@onready var _header    : HBoxContainer = %Header
@onready var _vbox      : VBoxContainer = %VBox
@onready var _scroll    : ScrollContainer = %Scroll

var _inv       : Node = null
var _csv       : Node = null
var _eq        : Node = null
var _gs        : Node = null
var _sig       : Node = null
var _stats     : Node = null
var _input_mgr : Node = null
var _ctrl_mgr  : Node = null  # ControllerManager reference

var _defs        : Dictionary = {}    # {id -> row dict}
var _counts_map  : Dictionary = {}    # {id -> int}  (after expansion, per-instance = 1)
var _equipped_by : Dictionary = {}    # {base_id -> PackedStringArray of member display names}
var _active_category : String = "All"  # Track currently selected category

# Controller navigation and UI
var _category_buttons: Array[Button] = []
var _selected_category_index: int = 0
var _panel_has_focus: bool = false
var _back_label: Label = null
var _description_label: Label = null
var _selected_item_id: String = ""
var _selected_item_def: Dictionary = {}

# Item grid navigation
var _item_buttons: Array[Button] = []
var _selected_item_index: int = 0
var _in_category_mode: bool = true  # true = navigating categories, false = navigating items

# Normalize arbitrary category strings to our canonical set
const _CAT_MAP := {
	"consumable":"Consumables","consumables":"Consumables",
	"binding":"Bindings","bindings":"Bindings","capture":"Bindings","captures":"Bindings",
	"weapon":"Weapons","weapons":"Weapons",
	"armor":"Armor",
	"head":"Headwear","headwear":"Headwear","helm":"Headwear","helmet":"Headwear",
	"foot":"Footwear","footwear":"Footwear","boots":"Footwear","shoes":"Footwear",
	"bracelet":"Bracelets","bracelets":"Bracelets","bangle":"Bracelets",
	"sigil":"Sigils","sigils":"Sigils",
	"battle":"Battle",
	"material":"Materials","materials":"Materials",
	"gift":"Gifts","gifts":"Gifts",
	"key":"Key","key item":"Key","key items":"Key",
	"other":"Other"
}

func _ready() -> void:
	# Add "Back (B)" indicator in bottom right
	_add_back_indicator()

	_inv       = get_node_or_null(INV_PATH)
	_csv       = get_node_or_null(CSV_PATH)
	_eq        = get_node_or_null(EQUIP_SYS_PATH)
	_gs        = get_node_or_null(GS_PATH)
	_sig       = get_node_or_null(SIGIL_SYS_PATH)
	_stats     = get_node_or_null(STATS_PATH)
	_input_mgr = get_node_or_null(INPUT_MGR_PATH)
	_ctrl_mgr  = get_node_or_null("/root/aControllerManager")

	# Setup UI: replace Filter dropdown with category buttons
	_setup_category_buttons()

	# Setup GridContainer for 2-column item layout
	_setup_item_grid()

	# Setup description section at the bottom
	_setup_description_section()

	# Live refresh on inventory
	if _inv != null and _inv.has_signal("inventory_changed"):
		if not _inv.is_connected("inventory_changed", Callable(self, "_rebuild")):
			_inv.connect("inventory_changed", Callable(self, "_rebuild"))

	# Live refresh on equipment
	if _eq != null and _eq.has_signal("equipment_changed"):
		if not _eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
			_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	# Connect to ControllerManager signals
	if _ctrl_mgr:
		_ctrl_mgr.navigate_pressed.connect(_on_controller_navigate)
		_ctrl_mgr.bumper_pressed.connect(_on_controller_bumper)
		_ctrl_mgr.action_button_pressed.connect(_on_controller_action)

	# Live refresh on sigils (xp/level/loadout etc)
	if _sig != null:
		for s in ["loadout_changed","instance_xp_changed","instances_changed",
				  "sigils_changed","sigil_instance_changed","sigil_level_changed","sigil_xp_changed"]:
			if _sig.has_signal(s):
				var cb := Callable(self, "_on_sigil_any_changed")
				if not _sig.is_connected(s, cb):
					_sig.connect(s, cb)

	if _refresh != null and not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	_rebuild()

func _setup_category_buttons() -> void:
	# Remove old Filter dropdown if it exists
	var old_filter: Node = get_node_or_null("%Filter")
	if old_filter:
		old_filter.queue_free()

	# Create category buttons container and add it to header
	_filter_container = HBoxContainer.new()
	_filter_container.add_theme_constant_override("separation", 4)

	# Find the spacer and insert categories before it
	var spacer: Node = null
	for child in _header.get_children():
		if child.name == "Spacer":
			spacer = child
			break

	if spacer:
		_header.remove_child(spacer)
		_header.add_child(_filter_container)
		_header.add_child(spacer)
	else:
		_header.add_child(_filter_container)

	# Clear button array
	_category_buttons.clear()

	# Create button for each category
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = cat
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE  # Disable direct selection - only L/R navigation
		btn.add_theme_font_size_override("font_size", 10)
		btn.set_meta("category", cat)
		if cat == "All":
			btn.button_pressed = true  # Start with "All" selected
		btn.pressed.connect(_on_category_button_pressed.bind(btn))
		_filter_container.add_child(btn)
		_category_buttons.append(btn)

	# Highlight first category button
	_selected_category_index = 0
	_highlight_category_button(_selected_category_index)

func _setup_item_grid() -> void:
	# Find and replace the List VBoxContainer with GridContainer
	var old_list: Node = get_node_or_null("%List")
	if old_list and old_list.get_parent():
		var parent: Node = old_list.get_parent()
		var idx: int = old_list.get_index()

		# Create new GridContainer
		_list_box = GridContainer.new()
		_list_box.columns = 2
		_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_list_box.add_theme_constant_override("h_separation", 16)
		_list_box.add_theme_constant_override("v_separation", 6)

		# Replace old with new
		parent.remove_child(old_list)
		parent.add_child(_list_box)
		parent.move_child(_list_box, idx)
		old_list.queue_free()

func _on_category_button_pressed(btn: Button) -> void:
	var cat: String = String(btn.get_meta("category"))
	_active_category = cat

	# Unpress all other category buttons
	for child in _filter_container.get_children():
		if child is Button and child != btn:
			child.button_pressed = false

	_rebuild()

# ------------------------------------------------------------------------------

func _rebuild() -> void:
	for c in _list_box.get_children():
		c.queue_free()

	# Clear item buttons array
	_item_buttons.clear()

	_defs       = _read_defs()
	_counts_map = _read_counts()

	# Sigil instances first (separate path)
	_inject_sigil_instances()

	# Build “who has this equipped” map for base items
	_equipped_by = _build_equipped_by_map()

	# Expand equipment into per-unit rows = equipped_count + inventory_count
	_expand_equipment_instances()

	var want: String = _current_category()

	# Total items after expansion (each row has count 1)
	var total_qty: int = 0
	for k_v in _counts_map.keys():
		total_qty += int(_counts_map.get(String(k_v), 0))
	if _counts_tv:
		_counts_tv.text = str(total_qty)

	# Render
	var ids: Array = _defs.keys()
	ids.sort_custom(Callable(self, "_cmp_ids_by_name"))

	# Separate recovery items from other items if in "All" or "Consumables"
	var show_recovery_section := (want == "All" or want == "Consumables")
	var recovery_items: Array = []
	var other_items: Array = []

	for id_v in ids:
		var id: String = String(id_v)
		var def: Dictionary = _defs.get(id, {}) as Dictionary
		var cat: String = _category_of(def)
		var qty: int = int(_counts_map.get(id, 0))

		if qty <= 0: continue
		if want != "All" and cat != want: continue

		var item_data := {"id": id, "def": def, "qty": qty}

		if show_recovery_section and _is_recovery_item(def):
			recovery_items.append(item_data)
		else:
			other_items.append(item_data)

	# Render recovery items section first (if applicable)
	if show_recovery_section and not recovery_items.is_empty():
		# Add subsection header (spans 2 columns by adding it with a spacer)
		var header := Label.new()
		header.text = "━━━ Recovery Items ━━━"
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 12)
		header.modulate = Color(0.8, 0.9, 1.0, 1.0)  # Light blue tint
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_box.add_child(header)

		# Add empty control to complete the grid row (2 columns)
		var header_spacer := Control.new()
		header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list_box.add_child(header_spacer)

		# Render recovery items (each item takes 1 column, 2 items per row)
		for item_data in recovery_items:
			_render_item(item_data["id"], item_data["def"], item_data["qty"])

		# Add blank cell if odd number of items to complete the row
		if recovery_items.size() % 2 == 1:
			var blank_cell := Control.new()
			blank_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_list_box.add_child(blank_cell)

		# Add spacing after recovery section (2 spacers for 2 columns)
		var spacer1 := Control.new()
		spacer1.custom_minimum_size = Vector2(0, 10)
		_list_box.add_child(spacer1)

		var spacer2 := Control.new()
		spacer2.custom_minimum_size = Vector2(0, 10)
		_list_box.add_child(spacer2)

	# Render other items
	for item_data in other_items:
		_render_item(item_data["id"], item_data["def"], item_data["qty"])

	await get_tree().process_frame
	_list_box.queue_sort()

	# Auto-select first item after rebuild
	_auto_select_first_item()

func _render_item(id: String, def: Dictionary, qty: int) -> void:
	"""Render a single item in the list"""
	var nm: String = _display_name(id, def)

	# Wrap each item in a PanelContainer for nice box effect
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true

	# Add margin inside the panel
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	# Create a VBox to hold item info and equipped status
	var item_vbox := VBoxContainer.new()
	item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_vbox.add_theme_constant_override("separation", 2)

	# Create a clickable button showing item name and quantity
	var item_btn := Button.new()
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.text = "%s  x%d" % [nm, qty]
	item_btn.add_theme_font_size_override("font_size", 10)
	item_btn.set_meta("id", id)
	item_btn.set_meta("def", def)
	item_btn.set_meta("qty", qty)
	item_btn.disabled = (qty <= 0)
	if not item_btn.pressed.is_connected(_on_item_clicked):
		item_btn.pressed.connect(_on_item_clicked.bind(item_btn))
	item_vbox.add_child(item_btn)

	# Track item button for controller navigation
	_item_buttons.append(item_btn)

	# Show equipped info if applicable
	var equip_txt := _equip_string_for(id, def)
	if equip_txt != "":
		var equip_lbl := Label.new()
		equip_lbl.text = "  " + equip_txt
		equip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		equip_lbl.add_theme_font_size_override("font_size", 10)
		equip_lbl.modulate = Color(0.7, 0.7, 0.7, 1.0)  # Slightly dimmed
		item_vbox.add_child(equip_lbl)

	margin.add_child(item_vbox)

	_list_box.add_child(panel)

# --- name/category helpers ----------------------------------------------------

func _cmp_ids_by_name(a: Variant, b: Variant) -> bool:
	var da: Dictionary = _defs.get(String(a), {}) as Dictionary
	var db: Dictionary = _defs.get(String(b), {}) as Dictionary
	var na := _display_name(String(a), da)
	var nb := _display_name(String(b), db)
	return na < nb

func _display_name(id: String, def: Dictionary) -> String:
	# Pre-computed name for sigil instances
	if def.has("sigil_instance") and bool(def["sigil_instance"]) and def.has("name"):
		var s := String(def["name"]).strip_edges()
		if s != "": return s

	if not def.is_empty():
		for k in ["name","display_name","label","title"]:
			if def.has(k) and typeof(def[k]) == TYPE_STRING:
				var s2 := String(def[k]).strip_edges()
				if s2 != "": return s2
	return id.replace("_"," ").capitalize()

func _category_of(def: Dictionary) -> String:
	if not def.is_empty():
		for k in ["category","cat","type"]:
			if def.has(k) and typeof(def[k]) == TYPE_STRING:
				var raw := String(def[k]).strip_edges()
				if raw != "":
					var norm := _normalize_category(raw)
					if norm != "": return norm
		for sk in ["slot","equip_slot","equip","equip_to"]:
			if def.has(sk) and typeof(def[sk]) == TYPE_STRING:
				var slot_raw := String(def[sk]).strip_edges()
				var from_slot := _normalize_category(slot_raw)
				if from_slot != "": return from_slot
	return "Other"

func _normalize_category(s: String) -> String:
	var key := s.strip_edges().to_lower()
	if _CAT_MAP.has(key): return String(_CAT_MAP[key])
	if key.ends_with("s") and _CAT_MAP.has(key.trim_suffix("s")):
		return String(_CAT_MAP[key.trim_suffix("s")])
	if _CAT_MAP.has(key + "s"):
		return String(_CAT_MAP[key + "s"])
	return ""

func _is_recovery_item(def: Dictionary) -> bool:
	"""Check if item is an HP/MP recovery item"""
	# Check field_status_effect for healing
	if def.has("field_status_effect"):
		var effect := String(def["field_status_effect"]).to_lower()
		if effect.contains("heal") and (effect.contains("hp") or effect.contains("mp")):
			return true

	# Check battle_status_effect for healing
	if def.has("battle_status_effect"):
		var effect := String(def["battle_status_effect"]).to_lower()
		if effect.contains("heal") and (effect.contains("hp") or effect.contains("mp")):
			return true

	return false

# --- reads --------------------------------------------------------------------

func _read_defs() -> Dictionary:
	if _csv != null and _csv.has_method("load_csv"):
		var loaded: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
		if typeof(loaded) == TYPE_DICTIONARY:
			return loaded as Dictionary
	if _inv != null:
		for m in ["get_item_defs","get_defs","get_items_dict"]:
			if _inv.has_method(m):
				var v: Variant = _inv.call(m)
				if typeof(v) == TYPE_DICTIONARY:
					return v as Dictionary
	return {}

func _read_counts() -> Dictionary:
	if _inv != null:
		for m in ["get_counts_dict","get_item_counts","get_counts"]:
			if _inv.has_method(m):
				var v: Variant = _inv.call(m)
				if typeof(v) == TYPE_DICTIONARY:
					var ret: Dictionary = {}
					var vd: Dictionary = v
					for k_v in vd.keys():
						var id: String = String(k_v)
						ret[id] = int(vd.get(id, 0))
					return ret
	return {}

# --- Equipped-by map for BASE items ------------------------------------------

func _build_equipped_by_map() -> Dictionary:
	var out: Dictionary = {}
	if _eq == null or not _eq.has_method("get_member_equip"):
		return out
	var members := _gather_members()
	for token in members:
		var equip_v: Variant = _eq.call("get_member_equip", token)
		if typeof(equip_v) != TYPE_DICTIONARY:
			continue
		var equip: Dictionary = equip_v
		if equip.has("feet") and not equip.has("foot"):
			equip["foot"] = String(equip["feet"])
		for k in ["weapon","armor","head","foot","bracelet"]:
			var base_id := String(equip.get(k, ""))
			if base_id == "": continue
			if not out.has(base_id):
				out[base_id] = PackedStringArray()
			var arr_psa: PackedStringArray = PackedStringArray()
			var existing: Variant = out[base_id]
			if typeof(existing) == TYPE_PACKED_STRING_ARRAY:
				arr_psa = existing
			elif typeof(existing) == TYPE_ARRAY:
				arr_psa = PackedStringArray(existing)
			var disp := _member_display_name(String(token))
			if arr_psa.find(disp) < 0:
				arr_psa.append(disp)
			out[base_id] = arr_psa
	return out

func _equip_string_for(id: String, def: Dictionary) -> String:
	# Sigil instance: resolve holder names
	if def.has("sigil_instance") and bool(def["sigil_instance"]) and def.has("instance_id"):
		var names := _holders_of_instance(String(def["instance_id"]))
		if names.size() > 0:
			return "Equipped by " + ", ".join(names)
		return ""

	# Expanded equipment instance
	if def.has("equip_instance") and bool(def["equip_instance"]):
		if def.has("equipped_by"):
			var who := String(def["equipped_by"])
			if who.strip_edges() != "":
				return "Equipped by " + who
		return ""

	# Fallback (base)
	if _equipped_by.has(id):
		var arr_any: Variant = _equipped_by[id]
		var arr: PackedStringArray = PackedStringArray()
		if typeof(arr_any) == TYPE_PACKED_STRING_ARRAY:
			arr = arr_any
		elif typeof(arr_any) == TYPE_ARRAY:
			arr = PackedStringArray(arr_any)
		if arr.size() > 0:
			return "Equipped by " + ", ".join(arr)
	return ""

# --- Equipment expansion (equipped + inventory) -------------------------------

func _is_equipment_row(def: Dictionary) -> bool:
	var cat := _category_of(def)
	if cat == "Weapons" or cat == "Armor" or cat == "Headwear" or cat == "Footwear" or cat == "Bracelets":
		return true
	for sk in ["slot","equip_slot","equip","equip_to"]:
		if def.has(sk) and typeof(def[sk]) == TYPE_STRING:
			var s := String(def[sk]).to_lower()
			if s == "weapon" or s == "armor" or s == "head" or s == "headwear" or s == "helm" or s == "helmet" or s == "foot" or s == "footwear" or s == "boots" or s == "shoes" or s == "bracelet":
				return true
	return false

func _expand_equipment_instances() -> void:
	var new_defs: Dictionary = {}
	var new_counts: Dictionary = {}

	for k_v in _defs.keys():
		var base_id := String(k_v)
		var def: Dictionary = _defs[base_id]
		var qty_unequipped: int = int(_counts_map.get(base_id, 0))

		if _is_equipment_row(def):
			var holders: PackedStringArray = PackedStringArray()
			if _equipped_by.has(base_id):
				var arr_any: Variant = _equipped_by[base_id]
				if typeof(arr_any) == TYPE_PACKED_STRING_ARRAY:
					holders = arr_any
				elif typeof(arr_any) == TYPE_ARRAY:
					holders = PackedStringArray(arr_any)

			var total_units: int = holders.size() + max(0, qty_unequipped)
			if total_units > 0:
				for i in range(total_units):
					var inst_id := "%s#%d" % [base_id, i + 1]
					var inst_def: Dictionary = def.duplicate(true)
					inst_def["equip_instance"] = true
					inst_def["base_id"] = base_id
					var who_name := ""
					if i < holders.size():
						who_name = holders[i]
					inst_def["equipped_by"] = who_name
					inst_def["name"] = _display_name(base_id, def)
					new_defs[inst_id] = inst_def
					new_counts[inst_id] = 1
				continue

		new_defs[base_id] = def
		if _counts_map.has(base_id):
			new_counts[base_id] = int(_counts_map[base_id])

	_defs = new_defs
	_counts_map = new_counts

# --- Sigil instances injection ------------------------------------------------

func _inject_sigil_instances() -> void:
	var ss: Node = _sig
	if ss == null:
		return

	var ids_map: Dictionary = {}

	if ss.has_method("list_all_instances"):
		var all_v: Variant = ss.call("list_all_instances", false)
		if typeof(all_v) == TYPE_ARRAY:
			for v in (all_v as Array):
				ids_map[String(v)] = true

	if ss.has_method("list_free_instances"):
		var free_v: Variant = ss.call("list_free_instances")
		if typeof(free_v) == TYPE_PACKED_STRING_ARRAY:
			for iid in (free_v as PackedStringArray):
				ids_map[String(iid)] = true
		elif typeof(free_v) == TYPE_ARRAY:
			for iid2 in (free_v as Array):
				ids_map[String(iid2)] = true

	if ss.has_method("get_loadout"):
		for token in _gather_members():
			var lo_v: Variant = ss.call("get_loadout", String(token))
			if typeof(lo_v) == TYPE_PACKED_STRING_ARRAY:
				for s in (lo_v as PackedStringArray):
					if String(s) != "":
						ids_map[String(s)] = true
			elif typeof(lo_v) == TYPE_ARRAY:
				for s2 in (lo_v as Array):
					if String(s2) != "":
						ids_map[String(s2)] = true

	for iid_k in ids_map.keys():
		var instance_id: String = String(iid_k)

		var base_id := instance_id
		if ss.has_method("get_base_from_instance"):
			base_id = String(ss.call("get_base_from_instance", instance_id))

		var base_name := base_id
		if ss.has_method("get_display_name_for"):
			base_name = String(ss.call("get_display_name_for", base_id))

		var level: int = 1
		if ss.has_method("get_instance_level"):
			level = int(ss.call("get_instance_level", instance_id))
		var lv_str := ( "MAX" if level >= 4 else "Lv %d" % level )

		var active := ""
		if ss.has_method("get_active_skill_name_for_instance"):
			active = String(ss.call("get_active_skill_name_for_instance", instance_id))
		var star := ("" if active.strip_edges() == "" else "  —  ★ " + active)

		var pretty := "%s  (%s)%s" % [base_name, lv_str, star]

		var school := ""
		if ss.has_method("get_instance_info"):
			var inf_v: Variant = ss.call("get_instance_info", instance_id)
			if typeof(inf_v) == TYPE_DICTIONARY:
				var info: Dictionary = inf_v
				school = String(info.get("school",""))

		var def: Dictionary = {
			"name": pretty,
			"category": "Sigils",
			"equip_slot": "Sigil",
			"sigil_instance": true,
			"instance_id": instance_id,
			"base_id": base_id,
			"school": school,
			"level": level,
			"active_skill_name": active
		}

		_defs[instance_id] = def
		_counts_map[instance_id] = 1

# --- Helpers: who holds a sigil instance -------------------------------------

func _holders_of_instance(inst_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if _sig == null or not _sig.has_method("get_loadout"):
		return out
	for token in _gather_members():
		var v: Variant = _sig.call("get_loadout", String(token))
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			var psa: PackedStringArray = v
			for s in psa:
				if String(s) == inst_id:
					var disp := _member_display_name(String(token))
					if out.find(disp) < 0:
						out.append(disp)
		elif typeof(v) == TYPE_ARRAY:
			var arr: Array = v
			for s2 in arr:
				if String(s2) == inst_id:
					var disp2 := _member_display_name(String(token))
					if out.find(disp2) < 0:
						out.append(disp2)
	return out

# --- UI glue ------------------------------------------------------------------

func _current_category() -> String:
	return _active_category

func _on_item_clicked(btn: Button) -> void:
	var id: String = String(btn.get_meta("id"))
	var def: Dictionary = btn.get_meta("def")
	var qty: int = int(btn.get_meta("qty"))
	var nm: String = _display_name(id, def)

	# Update description
	_selected_item_id = id
	_selected_item_def = def
	_update_description(id, def)

	# Create a dialog with item info and action buttons
	var dlg := AcceptDialog.new()
	dlg.title = nm
	dlg.min_size = Vector2(400, 0)
	dlg.dialog_hide_on_ok = true

	# IMPORTANT: Enable input processing for dialog
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS

	print("[ItemsPanel] Creating popup dialog for: ", nm)
	print("[ItemsPanel] Dialog process_mode: ", dlg.process_mode)

	# Build dialog content
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Show quantity
	var qty_lbl := Label.new()
	qty_lbl.text = "Quantity: x%d" % qty
	qty_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(qty_lbl)

	# Show equipment info if equipped
	var equip_txt := _equip_string_for(id, def)
	if equip_txt != "":
		var equip_lbl := Label.new()
		equip_lbl.text = equip_txt
		equip_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(equip_lbl)

	# Add button container
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	# Inspect button
	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect"
	inspect_btn.focus_mode = Control.FOCUS_ALL
	inspect_btn.set_meta("id", id)

	# Handle both mouse clicks and controller A button
	var inspect_action = func():
		print("[ItemsPanel] Inspect button pressed!")
		dlg.hide()
		_on_inspect_row(inspect_btn)

	inspect_btn.pressed.connect(inspect_action)

	# IMPORTANT: Handle controller input directly on button
	inspect_btn.gui_input.connect(func(event: InputEvent):
		print("[ItemsPanel] Inspect button received input event: ", event)
		if event.is_action_pressed("menu_accept") and inspect_btn.has_focus():
			print("[ItemsPanel] Inspect button: ACTION_ACCEPT detected!")
			inspect_action.call()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept") and inspect_btn.has_focus():
			print("[ItemsPanel] Inspect button: ui_accept detected!")
			inspect_action.call()
			get_viewport().set_input_as_handled()
	)

	inspect_btn.focus_entered.connect(func():
		print("[ItemsPanel] Inspect button focused")
	)
	btn_row.add_child(inspect_btn)
	print("[ItemsPanel] Created Inspect button, focus_mode: ", inspect_btn.focus_mode)

	# Use button (only for recovery items)
	var use_btn: Button = null
	if _is_recovery_item(def):
		use_btn = Button.new()
		use_btn.text = "Use"
		use_btn.focus_mode = Control.FOCUS_ALL
		use_btn.set_meta("id", id)
		use_btn.set_meta("def", def)

		# Handle both mouse clicks and controller A button
		var use_action = func():
			print("[ItemsPanel] Use button pressed!")
			dlg.hide()
			_on_use_item(id, def)

		use_btn.pressed.connect(use_action)

		# IMPORTANT: Handle controller input directly on button
		use_btn.gui_input.connect(func(event: InputEvent):
			print("[ItemsPanel] Use button received input event: ", event)
			if event.is_action_pressed("menu_accept") and use_btn.has_focus():
				print("[ItemsPanel] Use button: ACTION_ACCEPT detected!")
				use_action.call()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept") and use_btn.has_focus():
				print("[ItemsPanel] Use button: ui_accept detected!")
				use_action.call()
				get_viewport().set_input_as_handled()
		)

		use_btn.focus_entered.connect(func():
			print("[ItemsPanel] Use button focused")
		)
		btn_row.add_child(use_btn)
		print("[ItemsPanel] Created Use button, focus_mode: ", use_btn.focus_mode)

	# Discard button
	var discard_btn := Button.new()
	discard_btn.text = "Discard"
	discard_btn.focus_mode = Control.FOCUS_ALL
	discard_btn.set_meta("id", id)

	# Handle both mouse clicks and controller A button
	var discard_action = func():
		print("[ItemsPanel] Discard button pressed!")
		dlg.hide()
		_on_discard_row(discard_btn)

	discard_btn.pressed.connect(discard_action)

	# IMPORTANT: Handle controller input directly on button
	discard_btn.gui_input.connect(func(event: InputEvent):
		print("[ItemsPanel] Discard button received input event: ", event)
		if event.is_action_pressed("menu_accept") and discard_btn.has_focus():
			print("[ItemsPanel] Discard button: ACTION_ACCEPT detected!")
			discard_action.call()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept") and discard_btn.has_focus():
			print("[ItemsPanel] Discard button: ui_accept detected!")
			discard_action.call()
			get_viewport().set_input_as_handled()
	)

	discard_btn.focus_entered.connect(func():
		print("[ItemsPanel] Discard button focused")
	)
	btn_row.add_child(discard_btn)
	print("[ItemsPanel] Created Discard button, focus_mode: ", discard_btn.focus_mode)

	vbox.add_child(btn_row)

	# Add custom content to dialog
	dlg.add_child(vbox)

	# Show dialog
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(dlg)
	dlg.popup_centered()

	# Setup focus neighbors for controller navigation
	await get_tree().process_frame

	print("[ItemsPanel] Dialog popup shown, setting up focus...")

	# Get the dialog's OK button and make it focusable
	var ok_button = dlg.get_ok_button()
	print("[ItemsPanel] OK button found: ", ok_button != null)
	if ok_button:
		ok_button.focus_mode = Control.FOCUS_ALL

		# IMPORTANT: Handle controller input directly on OK button
		ok_button.gui_input.connect(func(event: InputEvent):
			print("[ItemsPanel] OK button received input event: ", event)
			if event.is_action_pressed("menu_accept") and ok_button.has_focus():
				print("[ItemsPanel] OK button: ACTION_ACCEPT detected!")
				print("[ItemsPanel] OK button pressed!")
				dlg.hide()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept") and ok_button.has_focus():
				print("[ItemsPanel] OK button: ui_accept detected!")
				print("[ItemsPanel] OK button pressed!")
				dlg.hide()
				get_viewport().set_input_as_handled()
		)

		ok_button.focus_entered.connect(func():
			print("[ItemsPanel] OK button focused")
		)
		print("[ItemsPanel] OK button focus_mode: ", ok_button.focus_mode)

	# Set up focus chain based on which buttons exist
	if use_btn:
		# Focus chain: Inspect -> Use -> Discard -> OK -> Inspect
		if ok_button:
			print("[ItemsPanel] Setting up 4-button focus chain (Inspect/Use/Discard/OK)")
			inspect_btn.focus_neighbor_right = inspect_btn.get_path_to(use_btn)
			inspect_btn.focus_neighbor_bottom = inspect_btn.get_path_to(ok_button)
			inspect_btn.focus_next = inspect_btn.get_path_to(use_btn)

			use_btn.focus_neighbor_left = use_btn.get_path_to(inspect_btn)
			use_btn.focus_neighbor_right = use_btn.get_path_to(discard_btn)
			use_btn.focus_neighbor_bottom = use_btn.get_path_to(ok_button)
			use_btn.focus_next = use_btn.get_path_to(discard_btn)

			discard_btn.focus_neighbor_left = discard_btn.get_path_to(use_btn)
			discard_btn.focus_neighbor_bottom = discard_btn.get_path_to(ok_button)
			discard_btn.focus_next = discard_btn.get_path_to(ok_button)

			ok_button.focus_neighbor_top = ok_button.get_path_to(inspect_btn)
			ok_button.focus_neighbor_left = ok_button.get_path_to(discard_btn)
			ok_button.focus_neighbor_right = ok_button.get_path_to(inspect_btn)
			ok_button.focus_previous = ok_button.get_path_to(discard_btn)
			ok_button.focus_next = ok_button.get_path_to(inspect_btn)
		else:
			# Focus chain: Inspect -> Use -> Discard -> Inspect
			print("[ItemsPanel] Setting up 3-button focus chain (Inspect/Use/Discard)")
			inspect_btn.focus_neighbor_right = inspect_btn.get_path_to(use_btn)
			inspect_btn.focus_next = inspect_btn.get_path_to(use_btn)
			use_btn.focus_neighbor_left = use_btn.get_path_to(inspect_btn)
			use_btn.focus_neighbor_right = use_btn.get_path_to(discard_btn)
			use_btn.focus_next = use_btn.get_path_to(discard_btn)
			discard_btn.focus_neighbor_left = discard_btn.get_path_to(use_btn)
			discard_btn.focus_next = discard_btn.get_path_to(inspect_btn)
	else:
		# No Use button - original focus chain
		if ok_button:
			print("[ItemsPanel] Setting up 3-button focus chain (Inspect/Discard/OK)")
			inspect_btn.focus_neighbor_right = inspect_btn.get_path_to(discard_btn)
			inspect_btn.focus_neighbor_bottom = inspect_btn.get_path_to(ok_button)
			inspect_btn.focus_next = inspect_btn.get_path_to(discard_btn)

			discard_btn.focus_neighbor_left = discard_btn.get_path_to(inspect_btn)
			discard_btn.focus_neighbor_bottom = discard_btn.get_path_to(ok_button)
			discard_btn.focus_next = discard_btn.get_path_to(ok_button)

			ok_button.focus_neighbor_top = ok_button.get_path_to(inspect_btn)
			ok_button.focus_neighbor_left = ok_button.get_path_to(discard_btn)
			ok_button.focus_neighbor_right = ok_button.get_path_to(inspect_btn)
			ok_button.focus_previous = ok_button.get_path_to(discard_btn)
			ok_button.focus_next = ok_button.get_path_to(inspect_btn)
		else:
			print("[ItemsPanel] No OK button, setting up 2-button focus chain (Inspect/Discard)")
			# If no OK button, just loop between Inspect and Discard
			inspect_btn.focus_neighbor_right = inspect_btn.get_path_to(discard_btn)
			inspect_btn.focus_next = inspect_btn.get_path_to(discard_btn)
			discard_btn.focus_neighbor_left = discard_btn.get_path_to(inspect_btn)
			discard_btn.focus_next = discard_btn.get_path_to(inspect_btn)

	# Give focus to first button for controller navigation
	print("[ItemsPanel] Attempting to grab focus on Inspect button...")
	inspect_btn.grab_focus()
	print("[ItemsPanel] Focus grabbed. Current focus owner: ", inspect_btn.get_viewport().gui_get_focus_owner())
	print("[ItemsPanel] Inspect button has focus: ", inspect_btn.has_focus())

func _on_use_item(item_id: String, item_def: Dictionary) -> void:
	"""Use a recovery item on a party member"""
	var item_name := _display_name(item_id, item_def)

	# Get field effect
	var effect := ""
	if item_def.has("field_status_effect"):
		effect = String(item_def["field_status_effect"])

	if effect == "":
		push_warning("[ItemsPanel] Cannot use %s - no field effect" % item_name)
		return

	# Create target selection dialog
	var dlg := ConfirmationDialog.new()
	dlg.title = "Use " + item_name
	dlg.dialog_text = "Select a party member to use this item on:"
	dlg.min_size = Vector2(500, 0)
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS

	# Main container to add spacing and grid
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)

	# Add spacer to push grid down from dialog text
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer)

	# Grid container for 2 columns of party members
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	main_vbox.add_child(grid)

	# Get party members (limit to 8)
	var members := _gather_members()
	var member_buttons: Array[Button] = []
	var max_members := mini(members.size(), 8)

	for i in range(max_members):
		var member_token = members[i]
		var member_name := _member_display_name(member_token)
		var stats := _get_member_hp_mp(member_token)

		var member_btn := Button.new()
		# Format: "Name  HP: 100/150  MP: 50/75"
		member_btn.text = "%s  HP:%d/%d  MP:%d/%d" % [
			member_name,
			stats["hp"], stats["hp_max"],
			stats["mp"], stats["mp_max"]
		]
		member_btn.focus_mode = Control.FOCUS_ALL
		member_btn.set_meta("member_token", member_token)
		member_btn.custom_minimum_size = Vector2(220, 40)

		var apply_use = func():
			print("[ItemsPanel] Using %s on %s" % [item_name, member_name])
			dlg.hide()
			_apply_recovery_item(item_id, member_token, effect)

		member_btn.pressed.connect(apply_use)

		# Handle controller input
		member_btn.gui_input.connect(func(event: InputEvent):
			if ((event.is_action_pressed("menu_accept")) or event.is_action_pressed("ui_accept")) and member_btn.has_focus():
				apply_use.call()
				get_viewport().set_input_as_handled()
		)

		grid.add_child(member_btn)
		member_buttons.append(member_btn)

	dlg.add_child(main_vbox)

	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(dlg)
	dlg.popup_centered()

	# Setup focus chain for member buttons and dialog buttons
	await get_tree().process_frame

	# Get dialog buttons (Cancel and OK)
	var cancel_btn: Button = dlg.get_cancel_button()
	var ok_btn: Button = dlg.get_ok_button()

	# Add controller support to Cancel button
	if cancel_btn:
		var cancel_action = func():
			print("[ItemsPanel] Use dialog canceled")
			dlg.hide()

		cancel_btn.gui_input.connect(func(event: InputEvent):
			if ((event.is_action_pressed("menu_accept")) or event.is_action_pressed("ui_accept")) and cancel_btn.has_focus():
				cancel_action.call()
				get_viewport().set_input_as_handled()
		)

	# Add controller support to OK button
	if ok_btn:
		ok_btn.gui_input.connect(func(event: InputEvent):
			if ((event.is_action_pressed("menu_accept")) or event.is_action_pressed("ui_accept")) and ok_btn.has_focus():
				dlg.hide()
				get_viewport().set_input_as_handled()
		)

	# Setup 2D grid focus navigation (2 columns)
	if member_buttons.size() > 0:
		for i in range(member_buttons.size()):
			var btn = member_buttons[i]
			var col = i % 2  # Column: 0 (left) or 1 (right)
			var row = i / 2  # Row index

			# Left/right navigation
			if col == 0 and i + 1 < member_buttons.size():
				# Left column -> right column
				btn.focus_neighbor_right = btn.get_path_to(member_buttons[i + 1])
			elif col == 1:
				# Right column -> left column
				btn.focus_neighbor_left = btn.get_path_to(member_buttons[i - 1])

			# Up/down navigation
			if i >= 2:
				# Has row above
				btn.focus_neighbor_top = btn.get_path_to(member_buttons[i - 2])
			if i + 2 < member_buttons.size():
				# Has row below
				btn.focus_neighbor_bottom = btn.get_path_to(member_buttons[i + 2])

		# Connect bottom row to dialog buttons
		var last_row_start = (member_buttons.size() - 1) / 2 * 2
		for i in range(last_row_start, member_buttons.size()):
			if cancel_btn:
				member_buttons[i].focus_neighbor_bottom = member_buttons[i].get_path_to(cancel_btn)

		# Connect dialog buttons back to first row
		if cancel_btn:
			cancel_btn.focus_neighbor_top = cancel_btn.get_path_to(member_buttons[0])
		if ok_btn:
			ok_btn.focus_neighbor_top = ok_btn.get_path_to(member_buttons[0])

		# Focus first member button
		member_buttons[0].grab_focus()

func _apply_recovery_item(item_id: String, member_token: String, effect: String) -> void:
	"""Apply a recovery item's effect to a party member"""
	print("[ItemsPanel] Applying %s to %s: %s" % [item_id, member_token, effect])

	# TODO: Implement actual HP/MP recovery logic here
	# This would need to interface with your character stats system
	# For now, just consume the item

	# Consume the item from inventory
	if _inv and _inv.has_method("remove_item"):
		_inv.call("remove_item", item_id, 1)
		print("[ItemsPanel] Item %s consumed" % item_id)

	# Show confirmation message
	var member_name := _member_display_name(member_token)
	var msg_dlg := AcceptDialog.new()
	msg_dlg.dialog_text = "Used item on %s!\n%s" % [member_name, effect]
	msg_dlg.title = "Item Used"
	msg_dlg.process_mode = Node.PROCESS_MODE_ALWAYS

	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(msg_dlg)
	msg_dlg.popup_centered()

	# Add controller support to OK button
	await get_tree().process_frame
	var ok_btn: Button = msg_dlg.get_ok_button()
	if ok_btn:
		ok_btn.gui_input.connect(func(event: InputEvent):
			if ((event.is_action_pressed("menu_accept")) or event.is_action_pressed("ui_accept")) and ok_btn.has_focus():
				msg_dlg.hide()
				get_viewport().set_input_as_handled()
		)
		ok_btn.grab_focus()

	# Refresh the item list
	_rebuild()

func _on_inspect_row(btn: Button) -> void:
	var id_v: Variant = btn.get_meta("id")
	var id: String = String(id_v)
	if not ResourceLoader.exists(INSPECT_SCENE):
		push_warning("[ItemsPanel] Missing inspect scene: %s" % INSPECT_SCENE)
		return
	var ps: PackedScene = load(INSPECT_SCENE) as PackedScene
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	if inst is Control:
		var c: Control = inst
		c.top_level = true
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 3000
	if inst.has_method("set_item"):
		var def: Dictionary = _defs.get(id, {}) as Dictionary
		var qty: int = int(_counts_map.get(id, 0))
		inst.call("set_item", id, def, qty, _inv)
	if inst.has_signal("item_used"):
		inst.connect("item_used", Callable(self, "_on_item_used"))
	var host := get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(inst)

func _on_item_used(_item_id: String, _new_count: int) -> void:
	_counts_map = _read_counts()
	_rebuild()

func _on_equipment_changed(_member: String) -> void:
	_rebuild()

# Accept any signal arg signature safely
func _on_sigil_any_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null, _d: Variant = null) -> void:
	_rebuild()

# --- Discard flow -------------------------------------------------------------

func _on_discard_row(btn: Button) -> void:
	var id: String = String(btn.get_meta("id"))
	var def: Dictionary = _defs.get(id, {}) as Dictionary
	var nm: String = _display_name(id, def)

	var dlg := ConfirmationDialog.new()
	dlg.title = "Discard item"
	dlg.dialog_text = "Are you sure you want to discard \"%s\"?\nThis removes it from inventory and any equipped slots." % nm
	dlg.min_size = Vector2(420, 0)
	dlg.set_meta("id", id)
	# Store a shallow copy so future rebuilds don't race this reference
	dlg.set_meta("def", def.duplicate(true))

	# IMPORTANT: Enable input processing for dialog
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS

	print("[ItemsPanel] Creating DISCARD confirmation dialog for: ", nm)
	print("[ItemsPanel] Discard dialog process_mode: ", dlg.process_mode)

	if not dlg.confirmed.is_connected(_on_discard_confirmed):
		dlg.confirmed.connect(_on_discard_confirmed.bind(dlg))

	var host := get_tree().current_scene
	if host == null: host = get_tree().root
	host.add_child(dlg)
	dlg.popup_centered()

	# Setup focus for controller navigation
	await get_tree().process_frame

	print("[ItemsPanel] Discard dialog shown, setting up focus...")

	var ok_button = dlg.get_ok_button()
	var cancel_button = dlg.get_cancel_button()

	print("[ItemsPanel] Discard OK button found: ", ok_button != null)
	print("[ItemsPanel] Discard Cancel button found: ", cancel_button != null)

	# Make sure buttons are focusable
	if ok_button:
		ok_button.focus_mode = Control.FOCUS_ALL

		# IMPORTANT: Handle controller input directly on OK button
		ok_button.gui_input.connect(func(event: InputEvent):
			print("[ItemsPanel] Discard OK button received input event: ", event)
			if event.is_action_pressed("menu_accept") and ok_button.has_focus():
				print("[ItemsPanel] Discard OK button: ACTION_ACCEPT detected!")
				print("[ItemsPanel] Discard OK button pressed!")
				dlg.hide()
				_on_discard_confirmed(dlg)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept") and ok_button.has_focus():
				print("[ItemsPanel] Discard OK button: ui_accept detected!")
				print("[ItemsPanel] Discard OK button pressed!")
				dlg.hide()
				_on_discard_confirmed(dlg)
				get_viewport().set_input_as_handled()
		)

		ok_button.focus_entered.connect(func():
			print("[ItemsPanel] Discard OK button focused")
		)
		print("[ItemsPanel] Discard OK button focus_mode: ", ok_button.focus_mode)

	if cancel_button:
		cancel_button.focus_mode = Control.FOCUS_ALL

		# IMPORTANT: Handle controller input directly on Cancel button
		cancel_button.gui_input.connect(func(event: InputEvent):
			print("[ItemsPanel] Discard Cancel button received input event: ", event)
			if event.is_action_pressed("menu_accept") and cancel_button.has_focus():
				print("[ItemsPanel] Discard Cancel button: ACTION_ACCEPT detected!")
				print("[ItemsPanel] Discard Cancel button pressed!")
				dlg.hide()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_accept") and cancel_button.has_focus():
				print("[ItemsPanel] Discard Cancel button: ui_accept detected!")
				print("[ItemsPanel] Discard Cancel button pressed!")
				dlg.hide()
				get_viewport().set_input_as_handled()
		)

		cancel_button.focus_entered.connect(func():
			print("[ItemsPanel] Discard Cancel button focused")
		)
		print("[ItemsPanel] Discard Cancel button focus_mode: ", cancel_button.focus_mode)

	# Set up focus chain between OK and Cancel buttons
	if ok_button and cancel_button:
		print("[ItemsPanel] Setting up 2-button focus chain (OK/Cancel)")
		ok_button.focus_neighbor_right = ok_button.get_path_to(cancel_button)
		ok_button.focus_neighbor_left = ok_button.get_path_to(cancel_button)
		ok_button.focus_next = ok_button.get_path_to(cancel_button)
		cancel_button.focus_neighbor_left = cancel_button.get_path_to(ok_button)
		cancel_button.focus_neighbor_right = cancel_button.get_path_to(ok_button)
		cancel_button.focus_previous = cancel_button.get_path_to(ok_button)
		cancel_button.focus_next = cancel_button.get_path_to(ok_button)

		# Focus the cancel button by default (safer choice)
		print("[ItemsPanel] Attempting to grab focus on Cancel button...")
		cancel_button.grab_focus()
		print("[ItemsPanel] Focus grabbed. Current focus owner: ", cancel_button.get_viewport().gui_get_focus_owner())
		print("[ItemsPanel] Cancel button has focus: ", cancel_button.has_focus())

func _on_discard_confirmed(dlg: ConfirmationDialog) -> void:
	if dlg == null: return
	var id_v: Variant = dlg.get_meta("id")
	var def_v: Variant = dlg.get_meta("def")
	var id: String = String(id_v)
	var def: Dictionary = (def_v if typeof(def_v) == TYPE_DICTIONARY else {}) as Dictionary
	dlg.queue_free()
	_do_discard(id, def)

func _do_discard(id: String, def: Dictionary) -> void:
	# Sigil instance: remove from all loadouts, then delete instance
	if def.has("sigil_instance") and bool(def["sigil_instance"]) and def.has("instance_id"):
		var inst_id := String(def["instance_id"])
		_discard_sigil_instance(inst_id)
		return

	# Expanded equipment instance (destroy this specific unit, even if equipped)
	if def.has("equip_instance") and bool(def["equip_instance"]):
		var base_id := String(def.get("base_id", id))
		var who := String(def.get("equipped_by",""))
		if who.strip_edges() != "":
			var token := _find_member_token_by_display(who)
			if token != "":
				var slot_key := _slot_key_for(def)
				_discard_equipped_unit(token, slot_key, base_id)
			else:
				# If we somehow can't resolve the token, just remove one from inventory.
				_remove_one_from_inventory(base_id)
		else:
			# Unequipped copy → remove one from inventory
			_remove_one_from_inventory(base_id)
		_rebuild()
		return

	# Fallback: normal stackable items or base rows
	_remove_one_from_inventory(id)
	_rebuild()


func _remove_one_from_inventory(base_id: String) -> void:
	if _inv == null: return
	# Prefer explicit remove/discard if available
	if _inv.has_method("remove_item"):
		_inv.call("remove_item", base_id, 1)
		return
	if _inv.has_method("discard_item"):
		_inv.call("discard_item", base_id, 1)
		return
	if _inv.has_method("consume"):
		_inv.call("consume", base_id, 1)
		return
	# Last resort: set_count(current-1)
	if _inv.has_method("get_count") and _inv.has_method("set_count"):
		var cur := int(_inv.call("get_count", base_id))
		_inv.call("set_count", base_id, max(0, cur - 1))

func _discard_sigil_instance(inst_id: String) -> void:
	if _sig == null: return

	# Remove from all loadouts we can see
	for token in _gather_members():
		if _sig.has_method("unequip_instance"):
			_sig.call("unequip_instance", String(token), inst_id)
			continue
		# Manual fallback: read loadout, strip the id, write it back
		if _sig.has_method("get_loadout"):
			var v: Variant = _sig.call("get_loadout", String(token))
			var arr: Array = []
			if typeof(v) == TYPE_PACKED_STRING_ARRAY:
				for s in (v as PackedStringArray):
					if String(s) != inst_id:
						arr.append(String(s))
			elif typeof(v) == TYPE_ARRAY:
				for s2 in (v as Array):
					if String(s2) != inst_id:
						arr.append(String(s2))
			# Try common setters
			if _sig.has_method("set_loadout"):
				_sig.call("set_loadout", String(token), PackedStringArray(arr))
			elif _sig.has_method("set_member_loadout"):
				_sig.call("set_member_loadout", String(token), PackedStringArray(arr))

	# Delete the instance from the sigil pool
	for m in ["delete_instance","destroy_instance","remove_instance","discard_instance"]:
		if _sig.has_method(m):
			_sig.call(m, inst_id)
			break

	_rebuild()

# Map def/category/slot to an EquipmentSystem slot key
func _slot_key_for(def: Dictionary) -> String:
	# Prefer explicit slot fields
	for sk in ["slot","equip_slot","equip","equip_to"]:
		if def.has(sk) and typeof(def[sk]) == TYPE_STRING:
			var raw := String(def[sk]).strip_edges().to_lower()
			match raw:
				"weapon":    return "weapon"
				"armor":     return "armor"
				"head","headwear","helm","helmet":
					return "head"
				"foot","feet","footwear","boots","shoes":
					return "foot"
				"bracelet","bracelets","bangle":
					return "bracelet"
	# Fallback from category
	var cat := _category_of(def)
	match cat:
		"Weapons":    return "weapon"
		"Armor":      return "armor"
		"Headwear":   return "head"
		"Footwear":   return "foot"
		"Bracelets":  return "bracelet"
		_:
			return "weapon" # harmless default if someone deletes while equipped

func _unequip_member_slot(member: String, slot_key: String) -> void:
	if _eq == null: return
	# New: your EquipmentSystem's actual method name
	if _eq.has_method("unequip_slot"):
		_eq.call("unequip_slot", member, slot_key)
		return
	# Existing fallbacks:
	if _eq.has_method("unequip"):
		_eq.call("unequip", member, slot_key)
		return
	if _eq.has_method("set_member_equip"):
		_eq.call("set_member_equip", member, slot_key, "")
		return
	if _eq.has_method("equip"):
		_eq.call("equip", member, slot_key, "")
		return
	if _eq.has_method("clear_slot"):
		_eq.call("clear_slot", member, slot_key)
		return
	if _eq.has_method("remove"):
		_eq.call("remove", member, slot_key)


func _find_member_token_by_display(display_name: String) -> String:
	for token in _gather_members():
		if _member_display_name(String(token)) == display_name:
			return String(token)
		# loose fallback
		if String(token).to_lower() == display_name.to_lower():
			return String(token)
	return ""

# --- member/party helpers -----------------------------------------------------

func _gather_members() -> Array[String]:
	var out: Array[String] = []
	var gs := _gs
	if gs == null:
		return out

	# Get active party members
	for m in ["get_active_party_ids", "get_party_ids", "list_active_party", "get_active_party"]:
		if gs.has_method(m):
			var raw: Variant = gs.call(m)
			if typeof(raw) == TYPE_PACKED_STRING_ARRAY:
				for s in (raw as PackedStringArray): out.append(String(s))
			elif typeof(raw) == TYPE_ARRAY:
				for s2 in (raw as Array): out.append(String(s2))
			if out.size() > 0: break

	if out.is_empty():
		for p in ["active_party_ids", "active_party", "party_ids", "party"]:
			var raw2: Variant = gs.get(p) if gs.has_method("get") else null
			if typeof(raw2) == TYPE_PACKED_STRING_ARRAY:
				for s3 in (raw2 as PackedStringArray): out.append(String(s3))
			elif typeof(raw2) == TYPE_ARRAY:
				for s4 in (raw2 as Array): out.append(String(s4))
			if out.size() > 0: break

	# Get benched members
	if gs.has_method("get"):
		var bench_v: Variant = gs.get("bench")
		if typeof(bench_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (bench_v as PackedStringArray):
				if not out.has(String(s)):  # Avoid duplicates
					out.append(String(s))
		elif typeof(bench_v) == TYPE_ARRAY:
			for s in (bench_v as Array):
				if not out.has(String(s)):  # Avoid duplicates
					out.append(String(s))

	return out

func _member_display_name(token: String) -> String:
	if token == "hero" and _gs and _gs.has_method("get"):
		var nm := String(_gs.get("player_name"))
		if nm.strip_edges() != "": return nm
	if _gs and _gs.has_method("_display_name_for_id"):
		var v: Variant = _gs.call("_display_name_for_id", token)
		if typeof(v) == TYPE_STRING and String(v) != "": return String(v)
	return token.capitalize()

func _get_member_hp_mp(token: String) -> Dictionary:
	"""Get current and max HP/MP for a party member. Returns {hp, hp_max, mp, mp_max}"""
	var result := {"hp": 0, "hp_max": 0, "mp": 0, "mp_max": 0}

	if not _gs or not _stats:
		return result

	# Get current HP/MP from member_data
	if _gs and _gs.has_method("get"):
		var member_data: Variant = _gs.get("member_data")
		if typeof(member_data) == TYPE_DICTIONARY:
			var md := member_data as Dictionary
			if md.has(token):
				var data := md[token] as Dictionary
				result["hp"] = int(data.get("hp", 0))
				result["mp"] = int(data.get("mp", 0))

	# Get max HP/MP from StatsSystem
	if _stats.has_method("get_member_level") and _stats.has_method("get_member_stat_level"):
		var level: int = 0
		var level_v: Variant = _stats.call("get_member_level", token)
		if typeof(level_v) == TYPE_INT:
			level = level_v as int

		var vtl: int = 0
		var vtl_v: Variant = _stats.call("get_member_stat_level", token, "VTL")
		if typeof(vtl_v) == TYPE_INT:
			vtl = vtl_v as int

		var fcs: int = 0
		var fcs_v: Variant = _stats.call("get_member_stat_level", token, "FCS")
		if typeof(fcs_v) == TYPE_INT:
			fcs = fcs_v as int

		# Compute max HP/MP
		if _stats.has_method("compute_max_hp"):
			var hp_max_v: Variant = _stats.call("compute_max_hp", level, vtl)
			if typeof(hp_max_v) == TYPE_INT:
				result["hp_max"] = hp_max_v as int

		if _stats.has_method("compute_max_mp"):
			var mp_max_v: Variant = _stats.call("compute_max_mp", level, fcs)
			if typeof(mp_max_v) == TYPE_INT:
				result["mp_max"] = mp_max_v as int

	return result

# ------------------------------------------------------------------------------
# Controller Navigation & UI Enhancements
# ------------------------------------------------------------------------------

func _setup_description_section() -> void:
	"""Add description section at the bottom of the panel"""
	if not _vbox:
		return

	# Create a separator
	var separator := HSeparator.new()
	_vbox.add_child(separator)

	# Create description container
	var desc_container := MarginContainer.new()
	desc_container.add_theme_constant_override("margin_left", 16)
	desc_container.add_theme_constant_override("margin_right", 16)
	desc_container.add_theme_constant_override("margin_top", 8)
	desc_container.add_theme_constant_override("margin_bottom", 8)
	desc_container.custom_minimum_size.y = 60

	_description_label = Label.new()
	_description_label.text = "Select an item to view its description"
	_description_label.add_theme_font_size_override("font_size", 12)
	_description_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_container.add_child(_description_label)

	_vbox.add_child(desc_container)

## ═══════════════════════════════════════════════════════════════
## CONTROLLER INPUT (via ControllerManager signals)
## ═══════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input directly - bypassing ControllerManager signal routing"""
	# Only process when panel has focus
	if not _panel_has_focus or not visible:
		return

	# L/R bumpers (9-10) - navigate categories
	if event.is_action_pressed("battle_burst"):  # L bumper
		print("[ItemsPanel] L bumper - navigate categories LEFT")
		_navigate_categories(-1)
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("battle_run"):  # R bumper
		print("[ItemsPanel] R bumper - navigate categories RIGHT")
		_navigate_categories(1)
		get_viewport().set_input_as_handled()
		return

	# D-pad navigation
	if event.is_action_pressed("move_up"):
		print("[ItemsPanel] D-pad UP")
		if not _in_category_mode and _selected_item_index > 0:
			_navigate_items(-2)  # -2 for up (grid is 2 columns)
		else:
			_enter_category_mode()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("move_down"):
		print("[ItemsPanel] D-pad DOWN")
		if _in_category_mode:
			_enter_item_mode()
		elif _selected_item_index + 2 < _item_buttons.size():
			_navigate_items(2)  # +2 for down (grid is 2 columns)
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("move_left"):
		print("[ItemsPanel] D-pad LEFT")
		if not _in_category_mode:
			_navigate_items(-1)
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("move_right"):
		print("[ItemsPanel] D-pad RIGHT")
		if not _in_category_mode:
			_navigate_items(1)
		get_viewport().set_input_as_handled()
		return

	# Action buttons
	if event.is_action_pressed("menu_accept"):  # A button
		print("[ItemsPanel] A button - accept/use item")
		if _in_category_mode:
			_enter_item_mode()
		elif not _item_buttons.is_empty():
			_use_selected_item()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("battle_defend"):  # X button
		print("[ItemsPanel] X button - inspect item")
		if not _in_category_mode and not _item_buttons.is_empty():
			_inspect_selected_item()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("battle_skill"):  # Y button
		print("[ItemsPanel] Y button - discard item")
		if not _in_category_mode and not _item_buttons.is_empty():
			_discard_selected_item()
		get_viewport().set_input_as_handled()
		return

func _on_controller_navigate(direction: Vector2, context: int) -> void:
	"""Handle navigation input from ControllerManager"""
	# Only process if this is our context
	if not _ctrl_mgr or context != _ctrl_mgr.InputContext.MENU_ITEMS:
		return

	if direction == Vector2.UP:
		if not _in_category_mode and _selected_item_index > 0:
			# Navigate items up
			_navigate_items(-2)  # -2 for up (grid is 2 columns)
		else:
			# Switch to category mode
			_enter_category_mode()
	elif direction == Vector2.DOWN:
		if _in_category_mode:
			# Switch to item mode
			_enter_item_mode()
		elif _selected_item_index + 2 < _item_buttons.size():
			# Navigate items down
			_navigate_items(2)  # +2 for down (grid is 2 columns)
	elif direction == Vector2.LEFT:
		if not _in_category_mode:
			_navigate_items(-1)
	elif direction == Vector2.RIGHT:
		if not _in_category_mode:
			_navigate_items(1)

func _on_controller_bumper(direction: int, context: int) -> void:
	"""Handle L/R bumper input from ControllerManager"""
	print("[ItemsPanel] Received bumper signal: direction=%d, context=%d, expected=%d" % [
		direction, context, _ctrl_mgr.InputContext.MENU_ITEMS if _ctrl_mgr else -1
	])

	# Only process if this is our context
	if not _ctrl_mgr or context != _ctrl_mgr.InputContext.MENU_ITEMS:
		print("[ItemsPanel] Bumper REJECTED - wrong context or no ctrl_mgr")
		return

	print("[ItemsPanel] Bumper ACCEPTED - navigating categories")
	# L/R bumpers always navigate categories
	_navigate_categories(direction)

func _on_controller_action(button: String, context: int) -> void:
	"""Handle action button input from ControllerManager"""
	# Only process if this is our context
	if not _ctrl_mgr or context != _ctrl_mgr.InputContext.MENU_ITEMS:
		return

	match button:
		"accept":  # A button
			if _in_category_mode:
				# If in category mode, switch to item mode first
				_enter_item_mode()
			elif not _item_buttons.is_empty():
				# Use selected item
				_use_selected_item()
		"back":  # B button
			# Close panel (handled by parent GameMenu)
			pass
		"inspect":  # X button
			if not _in_category_mode and not _item_buttons.is_empty():
				_inspect_selected_item()
		"discard":  # Y button
			if not _in_category_mode and not _item_buttons.is_empty():
				_discard_selected_item()

func _navigate_categories(direction: int) -> void:
	"""Navigate through categories with L/R bumpers only"""
	if _category_buttons.is_empty():
		return

	# Unhighlight current
	_unhighlight_category_button(_selected_category_index)

	# Update index with wrap-around
	_selected_category_index += direction
	if _selected_category_index < 0:
		_selected_category_index = _category_buttons.size() - 1
	elif _selected_category_index >= _category_buttons.size():
		_selected_category_index = 0

	# Highlight and activate new category
	_highlight_category_button(_selected_category_index)
	var button = _category_buttons[_selected_category_index]
	button.button_pressed = true
	_on_category_button_pressed(button)

	# Auto-select first item in new category and update description
	await get_tree().process_frame
	_auto_select_first_item()

func _highlight_category_button(index: int) -> void:
	"""Highlight a category button"""
	if index >= 0 and index < _category_buttons.size():
		var button = _category_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellow tint
		button.grab_focus()

func _unhighlight_category_button(index: int) -> void:
	"""Remove highlight from a category button"""
	if index >= 0 and index < _category_buttons.size():
		var button = _category_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func panel_gained_focus() -> void:
	"""Called by GameMenu when this panel gains focus"""
	print("[ItemsPanel] panel_gained_focus() called")
	_panel_has_focus = true
	# Start in category mode
	_in_category_mode = true
	_highlight_category_button(_selected_category_index)

	# Push context to ControllerManager
	if _ctrl_mgr:
		print("[ItemsPanel] Pushing MENU_ITEMS context to ControllerManager")
		_ctrl_mgr.push_context(_ctrl_mgr.InputContext.MENU_ITEMS, {
			"panel": self,
			"in_category_mode": _in_category_mode,
			"selected_item_index": _selected_item_index
		})
	else:
		print("[ItemsPanel] WARNING: No ControllerManager reference!")

func panel_lost_focus() -> void:
	"""Called by GameMenu when this panel loses focus"""
	print("[ItemsPanel] panel_lost_focus() called")
	_panel_has_focus = false
	# Remove highlights
	for btn in _category_buttons:
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	for btn in _item_buttons:
		btn.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Pop context from ControllerManager
	if _ctrl_mgr:
		print("[ItemsPanel] Popping context from ControllerManager")
		_ctrl_mgr.pop_context()
	else:
		print("[ItemsPanel] WARNING: No ControllerManager reference!")

func _enter_category_mode() -> void:
	"""Switch to category navigation mode"""
	_in_category_mode = true
	# Unhighlight items
	_unhighlight_item(_selected_item_index)
	# Highlight category
	_highlight_category_button(_selected_category_index)

func _enter_item_mode() -> void:
	"""Switch to item navigation mode"""
	if _item_buttons.is_empty():
		return
	_in_category_mode = false
	# Unhighlight category
	_unhighlight_category_button(_selected_category_index)
	# Highlight first item
	_selected_item_index = 0
	_highlight_item(_selected_item_index)

func _navigate_items(delta: int) -> void:
	"""Navigate through items in the grid"""
	if _item_buttons.is_empty():
		return

	# Unhighlight current
	_unhighlight_item(_selected_item_index)

	# Calculate new index
	var new_index = _selected_item_index + delta
	new_index = clamp(new_index, 0, _item_buttons.size() - 1)
	_selected_item_index = new_index

	# Highlight new selection
	_highlight_item(_selected_item_index)

func _highlight_item(index: int) -> void:
	"""Highlight an item button"""
	if index >= 0 and index < _item_buttons.size():
		var button = _item_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellow tint
		button.grab_focus()

		# Update description
		var id: String = String(button.get_meta("id"))
		var def: Dictionary = button.get_meta("def")
		_update_description(id, def)

		# Scroll to follow selected item
		_scroll_to_item(button)

func _unhighlight_item(index: int) -> void:
	"""Remove highlight from an item button"""
	if index >= 0 and index < _item_buttons.size():
		var button = _item_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func _use_selected_item() -> void:
	"""Use/activate the selected item (A button)"""
	if _selected_item_index < 0 or _selected_item_index >= _item_buttons.size():
		return
	var button = _item_buttons[_selected_item_index]
	_on_item_clicked(button)

func _inspect_selected_item() -> void:
	"""Inspect the selected item (X button)"""
	if _selected_item_index < 0 or _selected_item_index >= _item_buttons.size():
		return
	var button = _item_buttons[_selected_item_index]
	_on_inspect_row(button)

func _discard_selected_item() -> void:
	"""Discard the selected item (Y button)"""
	if _selected_item_index < 0 or _selected_item_index >= _item_buttons.size():
		return
	var button = _item_buttons[_selected_item_index]
	_on_discard_row(button)

func _add_back_indicator() -> void:
	"""Add 'Back (B)' text in bottom right corner"""
	_back_label = Label.new()
	_back_label.text = "Back (B)"
	_back_label.add_theme_font_size_override("font_size", 14)
	_back_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))

	# Position in bottom right
	_back_label.anchor_right = 1.0
	_back_label.anchor_bottom = 1.0
	_back_label.anchor_left = 1.0
	_back_label.anchor_top = 1.0
	_back_label.offset_right = -20
	_back_label.offset_bottom = -10
	_back_label.offset_left = -100
	_back_label.offset_top = -30
	_back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	add_child(_back_label)

func _auto_select_first_item() -> void:
	"""Auto-select first item in current category and update description"""
	if _item_buttons.is_empty():
		# No items in this category - show dash
		if _description_label:
			_description_label.text = "-"
		return

	# Select first item
	_selected_item_index = 0
	_highlight_item(_selected_item_index)

func _scroll_to_item(item_button: Button) -> void:
	"""Scroll the container to ensure the item is visible"""
	if not _scroll or not item_button:
		return

	# Find button's index in the item array
	var button_index = _item_buttons.find(item_button)
	if button_index < 0:
		return

	# Calculate item position based on index in 2-column grid
	# Grid layout: 2 columns, panels are ~50px tall (button + margins), 6px v_separation
	var panel_height = 58.0  # Approximate height of panel + margin + separation
	var row_index = button_index / 2  # Integer division (0,1 = row 0; 2,3 = row 1)

	# Calculate Y position of this row
	var item_y = row_index * panel_height
	var item_bottom = item_y + panel_height

	# Get scroll dimensions
	var scroll_height = _scroll.size.y
	var current_scroll = _scroll.scroll_vertical

	# Only scroll if item is actually outside the visible area (no padding)
	# Check if item top is above visible area (need to scroll up)
	if item_y < current_scroll:
		_scroll.scroll_vertical = item_y
	# Check if item bottom is below visible area (need to scroll down)
	elif item_bottom > current_scroll + scroll_height:
		_scroll.scroll_vertical = item_bottom - scroll_height

func _update_description(id: String, def: Dictionary) -> void:
	"""Update the description label with item info"""
	if not _description_label:
		return

	var nm: String = _display_name(id, def)
	var desc_text: String = ""

	# Try to get description from various fields
	for key in ["description", "desc", "info", "details", "text"]:
		if def.has(key) and typeof(def[key]) == TYPE_STRING:
			var s: String = String(def[key]).strip_edges()
			if s != "":
				desc_text = s
				break

	# If no description found, show basic info
	if desc_text == "":
		var cat: String = _category_of(def)
		desc_text = "%s - %s category item" % [nm, cat]

	# Add equipped info if applicable
	var equip_txt := _equip_string_for(id, def)
	if equip_txt != "":
		desc_text += "\n" + equip_txt

	_description_label.text = desc_text

# Try to read current inventory count, or -1 if unavailable.
func _get_inv_count(id: String) -> int:
	if _inv != null and _inv.has_method("get_count"):
		return int(_inv.call("get_count", id))
	return -1

# Destroy an equipped unit in-place.
# If your EquipmentSystem exposes a "destroy" style API, we prefer that.
# Otherwise, we unequip and then remove from inventory only if unequip returned it.
func _discard_equipped_unit(member: String, slot_key: String, base_id: String) -> void:
	# Prefer direct engine support if you have it
	if _eq != null:
		for m in ["destroy_from_slot", "discard_from_slot", "trash_from_slot", "delete_from_slot"]:
			if _eq.has_method(m):
				_eq.call(m, member, slot_key)
				return

	# Fallback: detect whether unequip adds back to inventory, and compensate.
	var before := _get_inv_count(base_id)
	_unequip_member_slot(member, slot_key)
	var after := _get_inv_count(base_id)

	if before >= 0 and after >= 0:
		# If unequipping put it back (+1), remove one to truly destroy the unit.
		if after > before:
			_remove_one_from_inventory(base_id)
	else:
		# If we can't read counts, safest is to try removing one; Inventory clamps at 0.
		_remove_one_from_inventory(base_id)
