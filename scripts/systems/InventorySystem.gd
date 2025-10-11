extends Node
class_name InventorySystem

signal inventory_changed()
signal item_used(item_id: String, new_count: int)

const ITEMS_PATH_A: String = "res://data/items/items.csv"
const ITEMS_PATH_B: String = "res://data/items.csv"

# Raw item definitions (already normalized)
var item_defs: Dictionary = {}   # { id -> Dictionary }
var inventory: Dictionary = {}   # { id -> count:int }

# ---- Field masks per slot (plain Array literals so they are const expressions) ----
const SLOT_FIELDS: Dictionary = {
	"Weapon": [
		"mind_type_tag","watk_type_tag",
		"base_watk","base_acc","crit_bonus_pct","scale_brw","skill_acc_boost","non_lethal",
		"equip_req_perk","equip_req_stats","set_id","flags",
		"upgrade_of","upgrade_step","upgrade_input","craft_input","craft_output","gift_type"
	],
	"Armor": [
		"armor_flat","ail_resist_pct",
		"equip_req_perk","equip_req_stats","set_id","flags",
		"upgrade_of","upgrade_step","upgrade_input","craft_input","craft_output"
	],
	"Headwear": [
		"ward_flat","max_hp_boost","max_mp_boost","mind_type_resists",
		"equip_req_perk","equip_req_stats","set_id","flags",
		"upgrade_of","upgrade_step","upgrade_input","craft_input","craft_output"
	],
	"Footwear": [
		"base_eva","speed",
		"equip_req_perk","equip_req_stats","set_id","flags",
		"upgrade_of","upgrade_step","upgrade_input","craft_input","craft_output"
	],
	"Bracelet": [
		"sigil_slots",
		"equip_req_perk","equip_req_stats","set_id","flags",
		"upgrade_of","upgrade_step","upgrade_input","craft_input","craft_output"
	],
	"Sigil": [
		"sigil_school","mind_type_tag",
		"use_type","targeting","cooldown","uses_per_battle",
		"battle_status_effect","field_status_effect","round_duration","flags",
		"upgrade_of","upgrade_step","upgrade_input","craft_input","craft_output"
	],
	"none": [
		"use_type","targeting","cooldown","uses_per_battle",
		"battle_status_effect","field_status_effect","round_duration","capture_type",
		"stat_boost","lvl_boost","flags","gift_type","craft_output"
	]
}

func _ready() -> void:
	load_definitions()

# -----------------------------------------------------------------------------
# Load & normalize
# -----------------------------------------------------------------------------
func load_definitions() -> void:
	var loader: Node = get_node_or_null("/root/aCSVLoader")
	if loader == null:
		push_warning("InventorySystem: CSVLoader not found; definitions cannot be loaded.")
		return

	var table: Dictionary = {}
	if FileAccess.file_exists(ITEMS_PATH_A):
		var v: Variant = loader.call("load_csv", ITEMS_PATH_A, "item_id")
		if typeof(v) == TYPE_DICTIONARY: table = v
	elif FileAccess.file_exists(ITEMS_PATH_B):
		var v2: Variant = loader.call("load_csv", ITEMS_PATH_B, "item_id")
		if typeof(v2) == TYPE_DICTIONARY: table = v2

	item_defs.clear()
	for id_v in table.keys():
		var id: String = String(id_v)
		var row_v: Variant = table[id]
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = row_v
		var norm: Dictionary = _normalize_row(src)
		# keep identity/display fields even if "null" in CSV
		norm["item_id"]    = id
		norm["name"]       = String(src.get("name",""))
		norm["category"]   = String(src.get("category",""))
		norm["equip_slot"] = String(src.get("equip_slot","none"))
		item_defs[id] = norm

	# Remove any unknown IDs from inventory so UI won't show "Other" ghosts
	_prune_unknown_inventory()
	inventory_changed.emit()

# Convert "null"/blank -> absent; TRUE/FALSE -> bool; numeric strings -> numbers
func _normalize_row(in_row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k_v in in_row.keys():
		var key: String = String(k_v)
		var v: Variant = in_row[k_v]
		var s: String = String(v)

		if s == "" or s.strip_edges().to_lower() == "null":
			continue

		var su: String = s.to_upper()
		if su == "TRUE":
			out[key] = true
			continue
		if su == "FALSE":
			out[key] = false
			continue

		if s.is_valid_float():
			var f: float = s.to_float()
			if absf(f - roundf(f)) < 0.000001:
				out[key] = int(roundf(f))
			else:
				out[key] = f
		else:
			out[key] = s
	return out

func _is_known(id: String) -> bool:
	return item_defs.has(id)

func _prune_unknown_inventory() -> void:
	var new_inv: Dictionary = {}
	for k_v in inventory.keys():
		var id: String = String(k_v)
		if _is_known(id):
			new_inv[id] = int(inventory.get(id, 0))
	inventory = new_inv

# -----------------------------------------------------------------------------
# Public: defs / counts / CRUD
# -----------------------------------------------------------------------------
func get_item_defs() -> Dictionary:
	return item_defs

func get_counts_dict() -> Dictionary:
	# Return counts only for known IDs (prevents ghost rows)
	var out: Dictionary = {}
	for k_v in inventory.keys():
		var id: String = String(k_v)
		if _is_known(id):
			out[id] = int(inventory.get(id, 0))
	return out

func add_item(item_id: String, quantity: int = 1) -> int:
	if not _is_known(item_id):
		push_warning("InventorySystem.add_item: unknown item_id '%s' (ignored)" % item_id)
		return get_count(item_id)
	var q: int = max(0, quantity)
	if q == 0:
		return get_count(item_id)
	var newc: int = int(inventory.get(item_id, 0)) + q
	inventory[item_id] = newc
	inventory_changed.emit()
	return newc

func set_count(item_id: String, count: int) -> int:
	if not _is_known(item_id):
		if count > 0:
			push_warning("InventorySystem.set_count: unknown item_id '%s' (ignored)" % item_id)
		return 0
	var c: int = max(0, count)
	if c <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = c
	inventory_changed.emit()
	return c

func remove_item(item_id: String, quantity: int = 1) -> int:
	if not _is_known(item_id):
		return 0
	var q: int = max(0, quantity)
	if q == 0:
		return get_count(item_id)
	if not inventory.has(item_id):
		return 0
	var newc: int = max(0, int(inventory[item_id]) - q)
	if newc == 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = newc
	inventory_changed.emit()
	return newc

func use_item(item_id: String, amount: int = 1) -> bool:
	if not _is_known(item_id):
		return false
	var before: int = get_count(item_id)
	var after: int = remove_item(item_id, amount)
	if after < before:
		item_used.emit(item_id, after)
		return true
	return false

func get_count(item_id: String) -> int:
	if not _is_known(item_id):
		return 0
	return int(inventory.get(item_id, 0))

func has_item(item_id: String) -> bool:
	return get_count(item_id) > 0

func clear_inventory() -> void:
	inventory.clear()
	inventory_changed.emit()

# -----------------------------------------------------------------------------
# Helpers for equipment/loadout UIs
# -----------------------------------------------------------------------------
# Returns only fields that matter for the item's equip slot.
func get_slot_stats(item_id: String) -> Dictionary:
	var row: Dictionary = item_defs.get(item_id, {}) as Dictionary
	if row.is_empty():
		return {}
	var slot: String = String(row.get("equip_slot", "none"))
	var allowed_v: Variant = SLOT_FIELDS.get(slot, null)
	var allowed: Array = []
	if typeof(allowed_v) == TYPE_ARRAY:
		allowed = allowed_v
	else:
		allowed = SLOT_FIELDS["none"] as Array

	var filtered: Dictionary = {}
	for key_v in allowed:
		var key: String = String(key_v)
		if row.has(key):
			filtered[key] = row[key]
	return filtered

func get_display_name(item_id: String) -> String:
	var row: Dictionary = item_defs.get(item_id, {}) as Dictionary
	return String(row.get("name", item_id))

func get_category(item_id: String) -> String:
	var row: Dictionary = item_defs.get(item_id, {}) as Dictionary
	return String(row.get("category", ""))
	
func mint_sigil_instance(item_id: String) -> String:
	if get_count(item_id) <= 0:
		return ""
	var def: Dictionary = item_defs.get(item_id, {}) as Dictionary
	if def.is_empty():
		return ""
	# remove_item(item_id, 1)  # ← REMOVE THIS LINE if you never want consumption here.
	var ss: Node = get_node_or_null("/root/aSigilSystem")
	if ss and ss.has_method("create_instance_from_item"):
		return String(ss.call("create_instance_from_item", def))
	return ""


# -----------------------------------------------------------------------------
# Save blob
# -----------------------------------------------------------------------------
func get_save_blob() -> Dictionary:
	return {"items": inventory.duplicate(true)}

func apply_save_blob(blob: Dictionary) -> void:
	var d_v: Variant = blob.get("items", {})
	var new_inv: Dictionary = {}
	if typeof(d_v) == TYPE_DICTIONARY:
		var d: Dictionary = d_v
		for k_v in d.keys():
			var id: String = String(k_v)
			if _is_known(id):
				new_inv[id] = int(d.get(id, 0))
	elif typeof(d_v) == TYPE_ARRAY:
		var arr: Array = d_v
		for v in arr:
			var id2: String = String(v)
			if _is_known(id2):
				new_inv[id2] = int(new_inv.get(id2, 0)) + 1
	inventory = new_inv
	inventory_changed.emit()

func clear_all() -> void:
	clear_inventory()
