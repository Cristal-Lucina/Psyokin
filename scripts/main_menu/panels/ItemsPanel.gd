extends Control
class_name ItemsPanel

## ItemsPanel — CSV is source-of-truth; show only owned (>0) CSV-defined items.

const INV_PATH      : String = "/root/aInventorySystem"
const CSV_PATH      : String = "/root/aCSVLoader"
const INSPECT_SCENE : String = "res://scenes/main_menu/panels/ItemInspect.tscn"

const ITEMS_CSV : String = "res://data/items/items.csv"
const KEY_ID    : String = "item_id"

const CATEGORIES : PackedStringArray = [
	"All","Consumables","Weapons","Armor","Headwear","Footwear",
	"Bracelets","Sigils","Battle","Materials","Gifts","Key","Other"
]

@onready var _filter    : OptionButton  = %Filter
@onready var _refresh   : Button        = %RefreshBtn
@onready var _counts_tv : Label         = %CountsValue
@onready var _list_box  : VBoxContainer = %List

var _inv : Node = null
var _csv : Node = null

var _defs       : Dictionary = {}   # {id -> row dict}
var _counts_map : Dictionary = {}   # {id -> int}

# Normalize arbitrary category strings to our canonical set
const _CAT_MAP := {
	"consumable":"Consumables","consumables":"Consumables",
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
	_inv = get_node_or_null(INV_PATH)
	_csv = get_node_or_null(CSV_PATH)

	if _inv != null and _inv.has_signal("inventory_changed"):
		if not _inv.is_connected("inventory_changed", Callable(self, "_rebuild")):
			_inv.connect("inventory_changed", Callable(self, "_rebuild"))

	if _filter != null and _filter.item_count == 0:
		for i in range(CATEGORIES.size()):
			_filter.add_item(CATEGORIES[i], i)
	if _filter != null and not _filter.item_selected.is_connected(_on_filter_changed):
		_filter.item_selected.connect(_on_filter_changed)

	if _refresh != null and not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	_rebuild()

# ------------------------------------------------------------------------------

func _rebuild() -> void:
	for c in _list_box.get_children():
		c.queue_free()

	_defs       = _read_defs()
	_counts_map = _read_counts()

	var want: String = _current_category()

	# Total count label: sum all owned counts
	var total_qty: int = 0
	for k_v in _counts_map.keys():
		total_qty += int(_counts_map.get(String(k_v), 0))
	if _counts_tv:
		_counts_tv.text = str(total_qty)

	# IDs to render: ONLY those that exist in CSV defs (source of truth)
	var ids: Array = _defs.keys()

	# Sort by display name
	ids.sort_custom(func(a, b):
		var da: Dictionary = _defs.get(a, {}) as Dictionary
		var db: Dictionary = _defs.get(b, {}) as Dictionary
		var na := _display_name(String(a), da)
		var nb := _display_name(String(b), db)
		return na < nb
	)

	for id_v in ids:
		var id: String = String(id_v)
		var def: Dictionary = _defs.get(id, {}) as Dictionary
		var nm: String = _display_name(id, def)
		var cat: String = _category_of(def)
		var qty: int = int(_counts_map.get(id, 0))

		# filter: always hide zero-owned
		if qty <= 0:
			continue
		if want != "All" and cat != want:
			continue

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)

		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text = nm
		row.add_child(name_lbl)

		var cat_lbl := Label.new()
		cat_lbl.text = cat
		row.add_child(cat_lbl)

		var qty_lbl := Label.new()
		qty_lbl.text = "x%d" % qty
		row.add_child(qty_lbl)

		var ins_btn := Button.new()
		ins_btn.text = "Inspect"
		ins_btn.disabled = (qty <= 0)
		ins_btn.set_meta("id", id)
		if not ins_btn.pressed.is_connected(_on_inspect_row):
			ins_btn.pressed.connect(_on_inspect_row.bind(ins_btn))
		row.add_child(ins_btn)

		_list_box.add_child(row)

	await get_tree().process_frame
	_list_box.queue_sort()

# --- name/category helpers ----------------------------------------------------

func _display_name(id: String, def: Dictionary) -> String:
	if not def.is_empty():
		for k in ["name","display_name","label","title"]:
			if def.has(k) and typeof(def[k]) == TYPE_STRING:
				var s := String(def[k]).strip_edges()
				if s != "":
					return s
	# prettify id as fallback
	return id.replace("_"," ").capitalize()

func _category_of(def: Dictionary) -> String:
	# Prefer explicit category (trim + normalize)
	if not def.is_empty():
		for k in ["category","cat","type"]:
			if def.has(k) and typeof(def[k]) == TYPE_STRING:
				var raw := String(def[k]).strip_edges()
				if raw != "":
					var norm := _normalize_category(raw)
					if norm != "":
						return norm
		# Fallback: infer from slot if present
		for sk in ["slot","equip_slot","equip","equip_to"]:
			if def.has(sk) and typeof(def[sk]) == TYPE_STRING:
				var slot_raw := String(def[sk]).strip_edges()
				var from_slot := _normalize_category(slot_raw)
				if from_slot != "":
					return from_slot
	return "Other"

func _normalize_category(s: String) -> String:
	var key := s.strip_edges().to_lower()
	if _CAT_MAP.has(key):
		return String(_CAT_MAP[key])
	# singular/plural quick fixes
	if key.ends_with("s") and _CAT_MAP.has(key.trim_suffix("s")):
		return String(_CAT_MAP[key.trim_suffix("s")])
	if _CAT_MAP.has(key + "s"):
		return String(_CAT_MAP[key + "s"])
	return ""

# --- reads --------------------------------------------------------------------

func _read_defs() -> Dictionary:
	# CSV first (source of truth)
	if _csv != null and _csv.has_method("load_csv"):
		var loaded: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
		if typeof(loaded) == TYPE_DICTIONARY:
			return loaded as Dictionary
	# Inventory fallback only if CSV failed
	if _inv != null:
		for m in ["get_item_defs","get_defs","get_items_dict"]:
			if _inv.has_method(m):
				var v: Variant = _inv.call(m)
				if typeof(v) == TYPE_DICTIONARY:
					return v as Dictionary
	return {}

func _read_counts() -> Dictionary:
	# Ask Inventory for counts; its frc returns only known IDs.
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

# --- UI glue ------------------------------------------------------------------

func _current_category() -> String:
	if _filter == null: return "All"
	var idx: int = _filter.get_selected()
	return _filter.get_item_text(idx)

func _on_filter_changed(_i: int) -> void:
	_rebuild()

func _on_inspect_row(btn: Button) -> void:
	var id_v: Variant = btn.get_meta("id")
	var id: String = String(id_v)
	if not ResourceLoader.exists(INSPECT_SCENE):
		push_warning("[ItemsPanel] Missing inspect scene: %s" % INSPECT_SCENE)
		return
	var ps: PackedScene = load(INSPECT_SCENE) as PackedScene
	if ps == null: return
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
	if host == null: host = get_tree().root
	host.add_child(inst)

func _on_item_used(_item_id: String, _new_count: int) -> void:
	_counts_map = _read_counts()
	_rebuild()
