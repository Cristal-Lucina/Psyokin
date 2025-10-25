extends Node

## Global Character Data
## Stores character customization data between scenes

var selected_variants = {}  # Variant codes (e.g., {"base": "humn_v06", "hair": "bob1_v05"})
var selected_parts = {}  # Full part data from character creator

func set_character(variants: Dictionary, parts: Dictionary):
	"""Store character data"""
	selected_variants = variants.duplicate()
	selected_parts = parts.duplicate()
	print("CharacterData: Stored character variants: ", selected_variants)

func get_variants() -> Dictionary:
	"""Get selected variants"""
	return selected_variants

func has_character() -> bool:
	"""Check if character data exists"""
	return selected_variants.size() > 0
