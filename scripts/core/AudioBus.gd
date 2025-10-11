extends Node
class_name AudioBus

## AudioBus
## Lightweight helper for interacting with the audio buses.
## 
## Exposes convenience methods for setting/getting the **Master** bus volume
## using normalized (linear) values in the range [0.0, 1.0].
##
## Notes
## - Bus index `0` is the Master bus in Godot’s AudioServer.
## - AudioServer APIs use **decibels**; we convert to/from linear for UI.
##
## Example:
## ```
## aAudioBus.set_master_volume(0.75)  # ~-2.5 dB
## var v := aAudioBus.get_master_volume()  # 0.0..1.0
## ```

## Sets the Master bus volume from a linear value [0.0, 1.0].
func set_master_volume(linear: float) -> void:
	# clampf returns float (not Variant), so no type warning.
	var clamped: float = clampf(linear, 0.0, 1.0)
	var db: float = linear_to_db(clamped)
	AudioServer.set_bus_volume_db(0, db)

## Gets the Master bus volume as a linear value [0.0, 1.0].
func get_master_volume() -> float:
	var db: float = AudioServer.get_bus_volume_db(0)
	return db_to_linear(db)
