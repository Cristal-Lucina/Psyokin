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
const INSPECT_SCENE  : String = "res://scenes/main_menu/panels/ItemInspect.tscn"

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

var _inv  : Node = null
var _csv  : Node = null
var _eq   : Node = null
var _gs  : Node = null
var _sig : Node = null

var _defs        : Dictionary = {}    # {id -> row dict}
var _counts_map  : Dictionary = {}    # {id -> int}  (after expansion, per-instance = 1)
var _equipped_by : Dictionary = {}    # {base_id -> PackedStringArray of member display names}

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
	_eq  = get_node_or_null(EQUIP_SYS_PATH)
	_gs  = get_node_or_null(GS_PATH)
	_sig = get_node_or_null(SIGIL_SYS_PATH)

	# Live refresh on inventory
	if _inv != null and _inv.has_signal("inventory_changed"):
		if not _inv.is_connected("inventory_changed", Callable(self, "_rebuild")):
			_inv.connect("inventory_changed", Callable(self, "_rebuild"))

	# Live refresh on equipment
	if _eq != null and _eq.has_signal("equipment_changed"):
		if not _eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
			_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	# Live refresh on sigils (xp/level/loadout etc)
	if _sig != null:
		for s in ["loadout_changed","instance_xp_changed","instances_changed",
				  "sigils_changed","sigil_instance_changed","sigil_level_changed","sigil_xp_changed"]:
			if _sig.has_signal(s):
				var cb := Callable(self, "_on_sigil_any_changed")
				if not _sig.is_connected(s, cb):
					_sig.connect(s, cb)

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

	for id_v in ids:
		var id: String = String(id_v)
		var def: Dictionary = _defs.get(id, {}) as Dictionary
		var nm: String = _display_name(id, def)
		var cat: String = _category_of(def)
		var qty: int = int(_counts_map.get(id, 0))

		if qty <= 0: continue
		if want != "All" and cat != want: continue

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)

		var name_lbl := Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text = nm
		row.add_child(name_lbl)

		var equip_lbl := Label.new()
		equip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		equip_lbl.size_flags_horizontal = Control.SIZE_FILL
		var equip_txt := _equip_string_for(id, def)
		if equip_txt != "":
			equip_lbl.text = equip_txt
		row.add_child(equip_lbl)

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

		# --- Discard button (new) ---
		var del_btn := Button.new()
		del_btn.text = "Discard"
		del_btn.set_meta("id", id)
		if not del_btn.pressed.is_connected(_on_discard_row):
			del_btn.pressed.connect(_on_discard_row.bind(del_btn))
		row.add_child(del_btn)

		_list_box.add_child(row)

	await get_tree().process_frame
	_list_box.queue_sort()

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
	if _filter == null:
		return "All"
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

	if not dlg.confirmed.is_connected(_on_discard_confirmed):
		dlg.confirmed.connect(_on_discard_confirmed.bind(dlg))

	var host := get_tree().current_scene
	if host == null: host = get_tree().root
	host.add_child(dlg)
	dlg.popup_centered()

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
