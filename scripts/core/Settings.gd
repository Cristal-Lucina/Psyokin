extends Node
class_name Settings

## Settings
## Tiny key/value store for runtime options (theme, text speed, volume, etc.).
## Designed to be autoloaded (e.g., `/root/aSettings`) so any script can:
##   - `aSettings.get_value("master_volume", 1.0)`
##   - `aSettings.set_value("ui_theme", "dark")`
##
## Notes
## - Values are kept in-memory only; persistence (save/load to disk) is not included.
## - All values are stored as `Variant`—cast when reading if you need strict types.
## - Extend/replace the `data` Dictionary with whatever settings your game needs.

## Default settings map.
var data: Dictionary = {
	"ui_theme": "default",  # String: theme identifier
	"text_speed": 1.0,      # float: 1.0 = normal speed
	"master_volume": 0.8,   # float: 0.0–1.0 linear volume
}

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
