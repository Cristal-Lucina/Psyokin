extends Node
class_name StarterLoadout

## StarterLoadout — grants a default kit at New Game, equips the hero,
## and also adds those items (incl. sigils) into the Inventory.

# You can rename these to match your CSV ids any time.
const START_WEAPON   : String = "wpn_training_blade"
const START_ARMOR    : String = "arm_school_uniform"
const START_HEAD     : String = "hd_baseball_cap"
const START_FOOT     : String = "ft_sneakers"
const START_BRACELET : String = "br_basic_band"

# Early sigils so the Sigils area isn’t empty.
const START_SIGILS : PackedStringArray = ["sigil_spark_i", "sigil_flow_i"]

func apply_for_new_game() -> void:
	var hero_name: String = _hero_name()
	_grant_items_to_inventory()
	_equip_hero(hero_name)
	_seed_sigils(hero_name)

# ------------------------------------------------------------------------------

func _hero_name() -> String:
	var hs: Node = get_node_or_null("/root/aHeroSystem")
	if hs != null and hs.has_method("get"):
		var v: Variant = hs.get("hero_name")
		if typeof(v) == TYPE_STRING and String(v) != "":
			return String(v)
	return "Player"

func _grant_items_to_inventory() -> void:
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv == null:
		push_warning("[StarterLoadout] InventorySystem not found; skipping item grants.")
		return

	# Core equipment → inventory (qty 1 each)
	var equip_ids: PackedStringArray = [
		START_WEAPON, START_ARMOR, START_HEAD, START_FOOT, START_BRACELET
	]
	for id in equip_ids:
		if inv.has_method("add_item"):
			inv.call("add_item", id, 1)

	# Sigils → inventory as well (so they show up in Items under Sigils)
	for sid in START_SIGILS:
		if inv.has_method("add_item"):
			inv.call("add_item", sid, 1)

func _equip_hero(hero_name: String) -> void:
	# Prefer dedicated EquipmentSystem
	var es: Node = get_node_or_null("/root/aEquipmentSystem")
	if es != null and es.has_method("set_member_equip"):
		var d: Dictionary = {
			"weapon": START_WEAPON,
			"armor": START_ARMOR,
			"head": START_HEAD,
			"foot": START_FOOT,
			"bracelet": START_BRACELET
		}
		es.call("set_member_equip", hero_name, d)
		return

	# Fallback: GameState owns equipment
	var gs: Node = get_node_or_null("/root/aGameState")
	if gs != null and gs.has_method("set_member_equip"):
		var d2: Dictionary = {
			"weapon": START_WEAPON,
			"armor": START_ARMOR,
			"head": START_HEAD,
			"foot": START_FOOT,
			"bracelet": START_BRACELET
		}
		gs.call("set_member_equip", hero_name, d2)

func _seed_sigils(hero_name: String) -> void:
	# Prefer GameState if it tracks per-member sigils
	var gs: Node = get_node_or_null("/root/aGameState")
	if gs != null and gs.has_method("set_member_sigils"):
		gs.call("set_member_sigils", hero_name, START_SIGILS)
		return

	# Fallback: SigilSystem
	var sig: Node = get_node_or_null("/root/aSigilSystem")
	if sig != null and sig.has_method("set_loadout"):
		sig.call("set_loadout", hero_name, START_SIGILS)
