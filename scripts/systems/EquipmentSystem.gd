extends Node
class_name EquipmentSystem

## Minimal equipment core used by LoadoutPanel.
## - Uses aInventorySystem for defs/counts.
## - Tracks per-member slots (does not consume inventory).
## - Emits equipment_changed(member) on changes.

signal equipment_changed(member: String)

const SLOT_KEYS: PackedStringArray = ["weapon","armor","head","foot","bracelet"]

# member -> { "weapon": String, "armor": String, "head": String, "foot": String, "bracelet": String }
var _equip: Dictionary = {}

# ----- public API --------------------------------------------------------------

func get_member_equip(member: String) -> Dictionary:
	_ensure_member(member)
	return (_equip[member] as Dictionary).duplicate(true)

func equip_item(member: String, item_id: String) -> String:
	var slot := _slot_of(item_id)
	if slot == "": return ""
	_ensure_member(member)
	var m: Dictionary = _equip[member]
	m[slot] = item_id
	_equip[member] = m
	equipment_changed.emit(member)
	return slot

func unequip_slot(member: String, slot: String) -> void:
	_ensure_member(member)
	if not SLOT_KEYS.has(slot): return
	var m: Dictionary = _equip[member]
	m[slot] = ""
	_equip[member] = m
	equipment_changed.emit(member)

func list_equippable(_member: String, slot: String) -> PackedStringArray:
	# Items in inventory that match the requested slot
	var out_ids: Array = []
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv == null:
		return PackedStringArray()

	var defs: Dictionary = {}
	var counts: Dictionary = {}

	if inv.has_method("get_item_defs"):
		var d_v: Variant = inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY:
			defs = d_v
	if inv.has_method("get_counts_dict"):
		var c_v: Variant = inv.call("get_counts_dict")
		if typeof(c_v) == TYPE_DICTIONARY:
			counts = c_v

	for id in counts.keys():
		if int(counts[id]) <= 0:
			continue
		var def: Dictionary = defs.get(id, {}) as Dictionary
		var s := _slot_from_def(def)
		if s == "":
			s = _slot_from_free_text(String(id))
		if s == slot:
			out_ids.append(String(id))

	out_ids.sort_custom(Callable(self, "_cmp_ids_by_name"))

	var packed := PackedStringArray()
	for e in out_ids:
		packed.append(String(e))
	return packed

func _cmp_ids_by_name(a: Variant, b: Variant) -> bool:
	return get_item_display_name(String(a)) < get_item_display_name(String(b))

func get_item_display_name(item_id: String) -> String:
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv and inv.has_method("get_item_defs"):
		var d_v: Variant = inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY:
			var def: Dictionary = (d_v as Dictionary).get(item_id, {}) as Dictionary
			for k in ["name","display_name","label","title"]:
				if def.has(k) and typeof(def[k]) == TYPE_STRING:
					var s := String(def[k]).strip_edges()
					if s != "":
						return s
	return String(item_id).replace("_"," ").capitalize()

# ----- slot inference ----------------------------------------------------------

func _slot_of(item_id: String) -> String:
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv and inv.has_method("get_item_defs"):
		var d_v: Variant = inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY:
			var def: Dictionary = (d_v as Dictionary).get(item_id, {}) as Dictionary
			var s := _slot_from_def(def)
			if s != "":
				return s
	return _slot_from_free_text(item_id)

func _slot_from_def(def: Dictionary) -> String:
	if def.is_empty(): return ""
	# prefer explicit slot field
	for k in ["slot","equip_slot","equip","equip_to"]:
		if def.has(k) and typeof(def[k]) == TYPE_STRING:
			var s := _normalize_slot(String(def[k]))
			if s != "": return s
	# fallback to category
	for kc in ["category","cat","type"]:
		if def.has(kc) and typeof(def[kc]) == TYPE_STRING:
			var s2 := _normalize_slot(String(def[kc]))
			if s2 != "": return s2
	return ""

func _slot_from_free_text(txt: String) -> String:
	return _normalize_slot(txt)

func _normalize_slot(s: String) -> String:
	var t := s.strip_edges().to_lower()
	match t:
		"weapon","weapons": return "weapon"
		"armor": return "armor"
		"head","headwear","helm","helmet": return "head"
		"foot","feet","footwear","boots","shoes": return "foot"
		"bracelet","bracelets","bangle": return "bracelet"
		_: return ""

# ----- lifecycle / save hooks --------------------------------------------------

func clear_all() -> void:
	_equip.clear()

func _ensure_member(member: String) -> void:
	if not _equip.has(member):
		_equip[member] = {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

func get_save_blob() -> Dictionary:
	# Normalize to strings for safety
	var out: Dictionary = {}
	for m in _equip.keys():
		var md: Dictionary = _equip[m]
		var rec := {
			"weapon":   String(md.get("weapon","")),
			"armor":    String(md.get("armor","")),
			"head":     String(md.get("head","")),
			"foot":     String(md.get("foot","")),
			"bracelet": String(md.get("bracelet","")),
		}
		out[String(m)] = rec
	return {"equip": out, "v": 1}

func apply_save_blob(blob: Dictionary) -> void:
	# Rebuild _equip in a normalized shape
	_equip.clear()

	var root_v: Variant = blob.get("equip", {})
	if typeof(root_v) == TYPE_DICTIONARY:
		var root: Dictionary = root_v
		for m in root.keys():
			var mkey := String(m)
			var src_v: Variant = root[m]
			var rec := {"weapon":"","armor":"","head":"","foot":"","bracelet":""}
			if typeof(src_v) == TYPE_DICTIONARY:
				var d: Dictionary = src_v
				for k in SLOT_KEYS:
					rec[k] = String(d.get(k, ""))
			_equip[mkey] = rec

	# Let listeners (UI, Sigils) rebuild after load; defer to avoid init-order issues
	for m2 in _equip.keys():
		call_deferred("_emit_equipment_changed_safe", String(m2))

func _emit_equipment_changed_safe(member: String) -> void:
	# Guard: avoid spamming during teardown
	if is_inside_tree():
		equipment_changed.emit(member)
