extends Node
class_name DropTables

var tables: Dictionary = {}   # enemy_id -> row/definition

func _ready() -> void:
	var loader := get_node_or_null("/root/aCSVLoader")
	if loader == null: return
	if FileAccess.file_exists("res://data/progression/drop_tables.csv"):
		tables = loader.load_csv("res://data/progression/drop_tables.csv", "enemy_id")

func roll(_enemy_id: String, _rng: RandomNumberGenerator = null) -> Array:
	return []
	# Minimal placeholder: returns an empty list (no errors during development).
