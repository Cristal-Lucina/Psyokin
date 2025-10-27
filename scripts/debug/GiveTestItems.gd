extends Node

## Debug utility to give test ailment items to the player
## Call give_test_ailment_items() to add all test items to inventory

const TEST_ITEMS_PATH = "res://data/combat/test_ailment_items.csv"

func give_test_ailment_items() -> void:
	"""Add all test ailment items to player inventory"""
	var inventory = get_node_or_null("/root/aInventorySystem")
	if not inventory:
		push_error("[GiveTestItems] Inventory system not found!")
		return
	
	# Load test items CSV
	var csv_loader = get_node_or_null("/root/aCSVLoader")
	if not csv_loader:
		push_error("[GiveTestItems] CSV loader not found!")
		return
	
	var test_items = csv_loader.load_csv(TEST_ITEMS_PATH, "item_id")
	if test_items.is_empty():
		push_error("[GiveTestItems] Failed to load test items from: %s" % TEST_ITEMS_PATH)
		return
	
	print("[GiveTestItems] Adding %d test items to inventory..." % test_items.size())
	
	# Add each test item to inventory (give 10 of each)
	for item_id in test_items.keys():
		var item_data = test_items[item_id]
		
		# Register item definition in inventory system
		inventory.item_defs[item_id] = item_data
		
		# Add 10 of each test item
		inventory.add_item(item_id, 10)
		
		print("[GiveTestItems]   + %s x10" % item_data.get("name", item_id))
	
	print("[GiveTestItems] ✓ Test items added successfully!")
	inventory.items_changed.emit()

func _ready() -> void:
	print("[GiveTestItems] Debug utility loaded")
	print("[GiveTestItems] Call give_test_ailment_items() to add test items")
