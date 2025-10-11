extends Node
class_name EnemyDB

## EnemyDB
## Loads enemy definitions from CSV into memory and exposes simple lookup helpers.
## Intended to run as an autoload (e.g., `/root/aEnemyDB`) so other systems
## (combat, loot, UI) can query enemy rows by `enemy_id`.
##
## CSV expectations:
## - Path: `res://data/progression/enemy_defs.csv`
## - Header row present
## - Primary key column named `enemy_id`
##
## Typical usage:
## ```
## if aEnemyDB.has_enemy("slime"):
##     var row := aEnemyDB.get_enemy("slime")
##     var hp  := int(row.get("hp", 10))
## ```

## Absolute path to the CSVLoader singleton (autoload).
const CSV_LOADER_PATH := "/root/aCSVLoader"
## Path to the enemy definitions CSV.
const ENEMY_CSV      := "res://data/progression/enemy_defs.csv"

## In-memory table: enemy_id -> row (Dictionary of CSV columns).
var enemies: Dictionary = {}  # enemy_id -> row (Dictionary)

## Called when the node enters the scene tree.
## Loads/refreshes the enemy table once at startup.
func _ready() -> void:
	reload()

## Reloads the enemy CSV into `enemies`.
## - Clears any previous contents
## - Uses CSVLoader to load and index by `enemy_id`
## - Emits warnings if Loader is missing, file absent, or type unexpected
func reload() -> void:
	enemies.clear()

	var loader: Node = get_node_or_null(CSV_LOADER_PATH)
	if loader == null:
		push_warning("EnemyDB: CSVLoader singleton not found at " + CSV_LOADER_PATH)
		return

	if not FileAccess.file_exists(ENEMY_CSV):
		push_warning("EnemyDB: CSV file not found: " + ENEMY_CSV)
		return

	var table: Dictionary = loader.load_csv(ENEMY_CSV, "enemy_id")
	if typeof(table) == TYPE_DICTIONARY:
		enemies = table
	else:
		push_warning("EnemyDB: CSVLoader returned unexpected type.")

# --- Public API (avoid overriding Object.get) ---

## Returns the row for a given enemy_id, or `{}` if not found.
## @param enemy_id: String
## @return Dictionary — row dictionary keyed by CSV headers.
func get_enemy(enemy_id: String) -> Dictionary:
	return Dictionary(enemies.get(enemy_id, {}))

## Checks whether an enemy_id exists in the DB.
## @param enemy_id: String
## @return bool — true if present.
func has_enemy(enemy_id: String) -> bool:
	return enemies.has(enemy_id)

## Lists all enemy IDs currently loaded.
## @return Array[String] — list of `enemy_id` keys.
func all_enemy_ids() -> Array[String]:
	var out: Array[String] = []
	for k in enemies.keys():
		out.append(String(k))
	return out

## Returns all enemy rows as an Array (order not guaranteed).
## @return Array — each element is a row Dictionary.
func all_enemies() -> Array:
	var out: Array = []
	for k in enemies.keys():
		out.append(enemies[k])
	return out
