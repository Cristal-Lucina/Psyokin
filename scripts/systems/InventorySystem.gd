## ═══════════════════════════════════════════════════════════════════════════
## InventorySystem - Item Definition & Quantity Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages item definitions (metadata from CSV) and item counts (how many
##   of each item the player owns). Provides add/remove/use/consume operations
##   and integrates with equipment and sigil systems.
##
## RESPONSIBILITIES:
##   • Item definition storage (id -> properties dictionary)
##   • Item quantity tracking (id -> count)
##   • CSV-based item database loading
##   • Add/remove/consume item operations
##   • Item existence and availability checks
##   • Save/load inventory state
##
## TWO-PART SYSTEM:
##   1. Definitions (_defs) - Metadata for all items (name, stats, category, etc.)
##   2. Counts (_counts) - How many of each item the player owns
##
## ITEM DEFINITION FIELDS (from CSV):
##   Common fields: item_id, name, display_name, category, equip_slot,
##   base_watk, armor_flat, sigil_slots, sigil_school, etc.
##
## CONNECTED SYSTEMS (Autoloads):
##   • CSVLoader - Auto-loads item definitions from CSV on startup
##   • EquipmentSystem - Queries item definitions for equipment stats
##   • SigilSystem - Queries item definitions for base sigil properties
##   • GameState - Save/load coordination
##
## CSV DATA SOURCES:
##   Tries multiple paths in order:
##   • res://data/items/items.csv
##   • res://data/items.csv
##   • res://data/inventory.csv
##
## KEY METHODS:
##   • get_item_defs() -> Dictionary - All item definitions
##   • get_item_def(id) -> Dictionary - Single item definition
##   • get_count(id) -> int - How many of this item owned
##   • add_item(id, amount) - Increase count
##   • remove_item(id, amount) - Decrease count (returns success)
##   • has_item(id) -> bool - Check if owned (count > 0)
##   • get_save_blob() -> Dictionary - Export counts for save
##   • apply_save_blob(data) - Restore counts from save
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name InventorySystem

# Fired when item DEFINITIONS are (re)loaded or set.
signal items_loaded
# Fired whenever item COUNTS change (add/remove/set/use/discard/apply_save_blob).
signal inventory_changed
# Alias of inventory_changed for older listeners.
signal items_changed

const FORCE_RELOAD := true
# Optional CSV loader (if present) to auto-populate item defs on ready.
const CSV_LOADER_PATH: String = "/root/aCSVLoader"
const CSV_PATHS: Array[String] = [
	"res://data/items/items.csv",
	"res://data/items.csv",
	"res://data/inventory.csv"
]
# Common id keys to try in CSV
const CSV_ID_KEYS: Array[String] = ["item_id", "id", "ItemID", "ItemId"]

# Item defs: id -> Dictionary of properties (e.g., name, category, equip_slot…)
var _defs: Dictionary = {}
# Counts: id -> quantity
var _counts: Dictionary = {}

## Initializes the inventory system, loading item definitions from CSV and emitting items_loaded signal
func _ready() -> void:
	_try_load_defs_from_csv()
	print("[InventorySystem] ready. defs=%d, counts_keys=%d" % [_defs.size(), _counts.size()])
	emit_signal("items_loaded")

# ───────────── API: item defs ─────────────

## Returns the complete dictionary of all item definitions (id -> properties)
func get_item_defs() -> Dictionary:
	return _defs

## Sets the entire item definitions dictionary and emits items_loaded signal
func set_item_defs(defs: Dictionary) -> void:
	_defs = (defs if (typeof(defs) == TYPE_DICTIONARY) else {})
	print("[InventorySystem] set_item_defs() -> defs=%d" % _defs.size())
	emit_signal("items_loaded")

## Returns the definition Dictionary for a specific item by ID. Returns empty Dict if not found.
func get_item_def(id: String) -> Dictionary:
	return (_defs.get(id, {}) as Dictionary)

## Forces a reload of item definitions from CSV files
func load_definitions() -> void:
	_try_load_defs_from_csv(FORCE_RELOAD)


# ───────────── API: counts (canonical) ─────────────

## Returns the complete dictionary of item counts (id -> quantity)
func get_counts_dict() -> Dictionary:
	return _counts

## Alias for get_counts_dict()
func get_item_counts() -> Dictionary: # alias
	return get_counts_dict()

## Alias for get_counts_dict()
func get_counts() -> Dictionary: # alias
	return get_counts_dict()

## Returns the quantity of a specific item. Returns 0 if not owned.
func get_count(id: String) -> int:
	return int(_counts.get(id, 0))

## Sets the count for an item to a specific value. Removes entry if count is 0. Emits inventory_changed.
func set_count(id: String, count: int) -> void:
	var c: int = max(0, int(count))
	if c == 0:
		_counts.erase(id)
	else:
		_counts[id] = c
	print("[InventorySystem] set_count %s -> %d" % [id, c])
	emit_signal("inventory_changed")
	emit_signal("items_changed") # alias

## Adds a quantity of an item. Amount can be negative to subtract. Emits inventory_changed.
func add_item(id: String, amount: int = 1) -> void:
	if amount == 0 or id.strip_edges() == "":
		return
	var cur: int = int(_counts.get(id, 0))
	var next_val: int = max(0, cur + amount)
	if next_val == 0:
		_counts.erase(id)
	else:
		_counts[id] = next_val
	print("[InventorySystem] add_item %s %+d => %d" % [id, amount, next_val])
	emit_signal("inventory_changed")
	emit_signal("items_changed") # alias

## Removes a quantity of an item. Does not go below 0. Emits inventory_changed.
func remove_item(id: String, qty: int = 1) -> void:
	if qty <= 0 or id.strip_edges() == "":
		return
	var cur: int = int(_counts.get(id, 0))
	var next_val: int = max(0, cur - qty)
	if next_val == 0:
		_counts.erase(id)
	else:
		_counts[id] = next_val
	print("[InventorySystem] remove_item %s -%d => %d" % [id, qty, next_val])
	emit_signal("inventory_changed")
	emit_signal("items_changed") # alias

## Alias for remove_item() - consumes an item
func consume(id: String, qty: int = 1) -> void:
	remove_item(id, qty)

# Extra aliases some UIs may probe for:
## Removes item quantity and returns true if count decreased, false otherwise
func use_item(id: String, qty: int = 1) -> bool:
	var before := get_count(id)
	remove_item(id, qty)
	return get_count(id) < before

## Alias for use_item() - discards an item and returns success
func discard_item(id: String, qty: int = 1) -> bool:
	return use_item(id, qty)

## Legacy alias for add_item()
func add(id: String, delta: int) -> void: # legacy
	add_item(id, delta)

## Legacy alias for remove_item()
func dec(id: String, n: int = 1) -> void: # legacy
	remove_item(id, n)

# ───────────── Save/Load ─────────────

## Returns inventory data for saving. Format: {"items": {id -> count}}
func get_save_blob() -> Dictionary:
	# Standard key "items" for compatibility with GameState.save()
	return {"items": _counts.duplicate(true)}

## Restores inventory counts from save data. Accepts {"items": {...}} or raw count dictionary.
## Emits inventory_changed signal.
func apply_save_blob(blob: Dictionary) -> void:
	if typeof(blob) != TYPE_DICTIONARY:
		return
	if blob.has("items") and typeof(blob["items"]) == TYPE_DICTIONARY:
		_counts = (blob["items"] as Dictionary).duplicate(true)
	else:
		# Back-compat: allow raw map
		_counts = blob.duplicate(true)
	print("[InventorySystem] apply_save_blob -> keys=%d" % _counts.size())
	emit_signal("inventory_changed")
	emit_signal("items_changed")

# ───────────── Internals ─────────────

## Internal: Attempts to load item definitions from CSV files using CSVLoader
func _try_load_defs_from_csv(force: bool=false) -> void:
	print("[InventorySystem] _try_load_defs_from_csv(force=%s), current defs size: %d" % [force, _defs.size()])
	if not force and not _defs.is_empty():
		print("[InventorySystem] Skipping load - definitions already exist and force=false")
		return
	var loader: Node = get_node_or_null(CSV_LOADER_PATH)
	if loader == null or not loader.has_method("load_csv"):
		if force: print("[InventorySystem] CSV loader missing at %s" % CSV_LOADER_PATH)
		return

	print("[InventorySystem] Attempting to load CSV from paths: %s" % CSV_PATHS)
	for path in CSV_PATHS:
		print("[InventorySystem] Checking path: %s" % path)
		if not ResourceLoader.exists(path):
			print("[InventorySystem]   Path does not exist, skipping")
			continue
		print("[InventorySystem]   Path exists! Trying keys: %s" % CSV_ID_KEYS)
		for key in CSV_ID_KEYS:
			print("[InventorySystem]     Trying key: %s" % key)
			var defs_v: Variant = loader.call("load_csv", path, key)
			print("[InventorySystem]     Result type: %s, size: %d" % [typeof(defs_v), (defs_v as Dictionary).size() if typeof(defs_v) == TYPE_DICTIONARY else 0])
			if typeof(defs_v) == TYPE_DICTIONARY and not (defs_v as Dictionary).is_empty():
				_defs = defs_v as Dictionary
				print("[InventorySystem] ✓ Loaded defs from %s (key=%s) -> %d rows" % [path, key, _defs.size()])
				# Debug: Print first few item IDs
				var sample_ids = _defs.keys().slice(0, 5)
				print("[InventorySystem]   Sample IDs: %s" % sample_ids)
				emit_signal("items_loaded")
				return
	if force:
		print("[InventorySystem] ✗ Failed to load defs from CSV (tried %s)" % [", ".join(CSV_PATHS)])
