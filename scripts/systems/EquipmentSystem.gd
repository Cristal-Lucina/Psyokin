extends Node
class_name EquipmentSystem

signal equipment_changed(member: String)

const INV_PATH: String  = "/root/aInventorySystem"
const GS_PATH: String   = "/root/aGameState"

# Equip slots we care about
const SLOTS: Array[String] = ["weapon","armor","head","foot","bracelet"]

# member_id -> { "weapon": id, "armor": id, "head": id, "foot": id, "bracelet": id }
var _equip_by_member: Dictionary = {}

func _ready() -> void:
	# Nothing special needed on start.
	pass

# ───────────── Public API ─────────────

func get_item_def(id: String) -> Dictionary:
	if id == "" or id == "—":
		return {}
	var inv: Node = get_node_or_null(INV_PATH)
	if inv != null and inv.has_method("get_item_defs"):
		var defs_v: Variant = inv.call("get_item_defs")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			return defs.get(id, {}) as Dictionary
	return {}

func get_item_display_name(id: String) -> String:
	if id == "" or id == "—":
		return "—"
	var d: Dictionary = get_item_def(id)
	if d.has("display_name") and typeof(d["display_name"]) == TYPE_STRING:
		var dn: String = String(d["display_name"]).strip_edges()
		if dn != "":
			return dn
	if d.has("name") and typeof(d["name"]) == TYPE_STRING:
		var nm: String = String(d["name"]).strip_edges()
		if nm != "":
			return nm
	return id

func get_member_equip(member: String) -> Dictionary:
	var mid: String = String(member)
	if not _equip_by_member.has(mid):
		_equip_by_member[mid] = {"weapon":"","armor":"","head":"","foot":"","bracelet":""}
	return (_equip_by_member[mid] as Dictionary).duplicate()

func list_equippable(_member: String, slot: String) -> PackedStringArray:
	var out := PackedStringArray()
	var inv: Node = get_node_or_null(INV_PATH)
	if inv == null:
		return out
	var counts: Dictionary = {}
	if inv.has_method("get_counts_dict"):
		var c_v: Variant = inv.call("get_counts_dict")
		if typeof(c_v) == TYPE_DICTIONARY:
			counts = c_v as Dictionary
	if counts.is_empty():
		return out

	var defs: Dictionary = {}
	if inv.has_method("get_item_defs"):
		var d_v: Variant = inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY:
			defs = d_v as Dictionary

	var want: String = _norm_slot(slot)
	for id_v in counts.keys():
		if int(counts.get(id_v, 0)) <= 0:
			continue
		var iid: String = String(id_v)
		var rec: Dictionary = defs.get(iid, {}) as Dictionary
		var tag: String = _detect_slot(rec)
		if _norm_slot(tag) == want:
			out.append(iid)
	return out


func equip_item(member: String, item_id: String) -> bool:
	var mid: String = String(member).strip_edges()
	var iid: String = String(item_id).strip_edges()
	if mid == "" or iid == "":
		return false

	var rec: Dictionary = get_item_def(iid)
	var slot: String = _detect_slot(rec)
	slot = _norm_slot(slot)
	if slot == "":
		return false
	if not SLOTS.has(slot):
		return false

	var cur: Dictionary = get_member_equip(mid)
	var currently_equipped: String = String(cur.get(slot, ""))

	# Inventory interactions
	var inv: Node = get_node_or_null(INV_PATH)
	if inv != null:
		# Need the item in inventory to equip
		var have: int = 0
		if inv.has_method("get_count"):
			var c_v: Variant = inv.call("get_count", iid)
			if typeof(c_v) == TYPE_INT or typeof(c_v) == TYPE_FLOAT:
				have = int(c_v)
		elif inv.has_method("get_counts_dict"):
			var counts_v: Variant = inv.call("get_counts_dict")
			if typeof(counts_v) == TYPE_DICTIONARY:
				var cd: Dictionary = counts_v
				have = int(cd.get(iid, 0))
		if have <= 0:
			return false

		# Remove newly equipped item from inventory
		if inv.has_method("remove_item"):
			inv.call("remove_item", iid, 1)
		elif inv.has_method("consume"):
			inv.call("consume", iid, 1)
		elif inv.has_method("add"):
			inv.call("add", iid, -1)

		# Return previously equipped item (if any) to inventory
		if currently_equipped != "":
			if inv.has_method("add"):
				inv.call("add", currently_equipped, 1)

	# Apply equip
	cur[slot] = iid
	_equip_by_member[mid] = cur
	emit_signal("equipment_changed", mid)

	# If bracelet changed, nudge the SigilSystem so slots/capacity re-evaluate (if present).
	var sig: Node = get_node_or_null("/root/aSigilSystem")
	if sig != null and sig.has_method("on_bracelet_changed"):
		sig.call("on_bracelet_changed", mid)

	return true

func unequip_slot(member: String, slot: String) -> void:
	var mid: String = String(member).strip_edges()
	if mid == "":
		return
	slot = _norm_slot(slot)
	if not SLOTS.has(slot):
		return
	var cur: Dictionary = get_member_equip(mid)
	var was: String = String(cur.get(slot, ""))
	if was != "":
		# Return to inventory
		var inv: Node = get_node_or_null(INV_PATH)
		if inv != null and inv.has_method("add"):
			inv.call("add", was, 1)
	cur[slot] = ""
	_equip_by_member[mid] = cur
	emit_signal("equipment_changed", mid)

	# Bracelet unequipped → tell Sigils
	if slot == "bracelet":
		var sig: Node = get_node_or_null("/root/aSigilSystem")
		if sig != null and sig.has_method("on_bracelet_changed"):
			sig.call("on_bracelet_changed", mid)
# Destroy the equipped item in-place (do NOT return it to inventory).
func destroy_from_slot(member: String, slot: String) -> void:
	var mid := String(member).strip_edges()
	if mid == "": return
	slot = _norm_slot(slot)
	if not SLOTS.has(slot): return

	var cur := get_member_equip(mid)
	var was := String(cur.get(slot, ""))
	if was == "": return

	# Just clear the slot; equipped items are not in inventory.
	cur[slot] = ""
	_equip_by_member[mid] = cur
	emit_signal("equipment_changed", mid)

# Friendly alias, since your UI checks a few names.
func discard_from_slot(member: String, slot: String) -> void:
	destroy_from_slot(member, slot)

# Alias for compatibility with UIs that call 'unequip' instead of 'unequip_slot'.
func unequip(member: String, slot: String) -> void:
	unequip_slot(member, slot)

# ───────────── Save/Load (optional, forward-compatible) ─────────────

func save() -> Dictionary:
	return {"equip": _equip_by_member.duplicate(true)}

func load(data: Dictionary) -> void:
	var e_v: Variant = data.get("equip", {})
	if typeof(e_v) == TYPE_DICTIONARY:
		_equip_by_member = (e_v as Dictionary).duplicate(true)
	# Emit change for visible members
	if _equip_by_member.size() > 0:
		for m in _equip_by_member.keys():
			emit_signal("equipment_changed", String(m))

# ───────────── Helpers ─────────────

func _detect_slot(rec: Dictionary) -> String:
	# Common keys your data might be using
	for k in ["equip_slot","slot","equip","equip_to","category","cat","type"]:
		if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
			return _norm_slot(rec[k])    # normalize here
	return ""

func _norm_slot(s: String) -> String:
	var t: String = String(s).strip_edges().to_lower()
	match t:
		"feet", "footwear", "boots", "shoes":
			return "foot"
		"headwear", "helm", "helmet", "hat", "cap":
			return "head"
		"bracelets", "bangle":
			return "bracelet"
		"sigils":
			return "sigil"
		_:
			return t
