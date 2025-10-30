extends Node
class_name Settings

## Settings
## Key/value store for runtime options (theme, text speed, volume, controller mappings, etc.).
## Designed to be autoloaded (e.g., `/root/aSettings`) so any script can:
##   - `aSettings.get_value("master_volume", 1.0)`
##   - `aSettings.set_value("ui_theme", "dark")`
##
## Notes
## - Values are persisted to disk automatically when changed
## - All values are stored as `Variant`—cast when reading if you need strict types.
## - Extend/replace the `data` Dictionary with whatever settings your game needs.

const SETTINGS_FILE_PATH = "user://settings.json"

## Default settings map.
var data: Dictionary = {
	"ui_theme": "default",  # String: theme identifier
	"text_speed": 1.0,      # float: 1.0 = normal speed
	"master_volume": 0.8,   # float: 0.0–1.0 linear volume
	"input_mapping": {},    # Dictionary: controller input mapping
}

func _ready() -> void:
	load_settings()
	# Load input mapping if available
	if data.has("input_mapping") and data["input_mapping"] is Dictionary and not data["input_mapping"].is_empty():
		aInputManager.load_input_mapping(data["input_mapping"])

## Reads a setting.
## @param key: String — setting name
## @param default: Variant — value to return if key is missing (optional)
## @return Variant — stored value or `default`
func get_value(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)

## Writes/overrides a setting.
## @param key: String — setting name
## @param value: Variant — new value
func set_value(key: String, value: Variant) -> void:
	data[key] = value
	save_settings()

## Save input mapping
func save_input_mapping() -> void:
	data["input_mapping"] = aInputManager.save_input_mapping()
	save_settings()

## Save settings to disk
func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data, "\t")
		file.store_string(json_string)
		file.close()
		print("[Settings] Settings saved to: ", SETTINGS_FILE_PATH)
	else:
		push_error("[Settings] Failed to save settings to: " + SETTINGS_FILE_PATH)

## Load settings from disk
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		print("[Settings] No settings file found, using defaults")
		return

	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()

		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			var loaded_data = json.get_data()
			if loaded_data is Dictionary:
				# Merge loaded data with defaults (to handle new settings)
				for key in loaded_data:
					data[key] = loaded_data[key]
				print("[Settings] Settings loaded from: ", SETTINGS_FILE_PATH)
			else:
				push_error("[Settings] Invalid settings data format")
		else:
			push_error("[Settings] Failed to parse settings JSON: " + json.get_error_message())
	else:
		push_error("[Settings] Failed to open settings file: " + SETTINGS_FILE_PATH)
