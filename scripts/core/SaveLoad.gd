extends Node
#GOOD
## ═══════════════════════════════════════════════════════════════════════════
## SaveLoad - File Persistence System
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Handles file I/O for save games, managing JSON files in the user://saves/
##   directory with numbered slots (slot_0.json, slot_1.json, etc.).
##
## RESPONSIBILITIES:
##   • Save game data to numbered slots (JSON format)
##   • Load game data from slots
##   • Delete save slots
##   • List all save slots with metadata
##   • Generate save slot labels (date, time, scene)
##
## FILE STRUCTURE:
##   JSON save files under `user://saves/` with one file per slot.
##   Wrapper structure written to disk:
##   {
##     "version": 1,
##     "ts": <unix time>,
##     "scene": "Main",
##     "label": "MM/DD — Weekday — Phase",
##     "payload": { ... }  # GameState.save()
##   }
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Receives payload from GameState.save()
##   • CalendarSystem - For save slot label generation (date/time)
##
## KEY METHODS:
##   • save_game(slot: int, payload: Dictionary) -> bool - Write to slot
##   • load_game(slot: int) -> Dictionary - Read from slot (returns payload)
##   • delete_slot(slot: int) - Remove save file
##   • list_slots() -> Array[Dictionary] - Get all slots with metadata
##   • has_save(slot: int) -> bool - Check if slot exists
##
## ═══════════════════════════════════════════════════════════════════════════

const SAVE_DIR : String = "user://saves"

## Returns the file path for a specific save slot number
func _path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

## Ensures the save directory exists, creating it recursively if needed
func _ensure_dir() -> void:
	# DirAccess.make_dir_recursive_absolute() doesn't work with user:// paths
	# We need to use the static method that handles virtual paths
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			push_error("[SaveLoad] Failed to create save directory: %s (error %d)" % [SAVE_DIR, err])

## Generates a human-readable label from save payload using player name and calendar data.
## Format: "FirstName LastName : Mon 5/5 : Time Played"
func _label_from_payload(payload: Dictionary) -> String:
	# Get player name (first + last)
	var player_name := "Player"
	if payload.has("meta") and typeof(payload["meta"]) == TYPE_DICTIONARY:
		var meta: Dictionary = payload["meta"]
		if meta.has("hero_identity") and typeof(meta["hero_identity"]) == TYPE_DICTIONARY:
			var identity: Dictionary = meta["hero_identity"]
			var first_name := String(identity.get("name", ""))
			var surname := String(identity.get("surname", ""))
			if first_name != "":
				player_name = first_name
				if surname != "":
					player_name += " " + surname

	# Get date and weekday
	var date_str := ""
	if payload.has("calendar") and typeof(payload["calendar"]) == TYPE_DICTIONARY:
		var c: Dictionary = payload["calendar"]
		var date: Dictionary = c.get("date", {})
		var month := int(date.get("month", 0))
		var day   := int(date.get("day", 0))

		var weekday_abbrev := ""
		var wi := int(c.get("weekday", -1))
		if wi >= 0:
			var abbrevs := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
			if wi >= 0 and wi < abbrevs.size(): weekday_abbrev = abbrevs[wi]

		if month > 0 and day > 0 and weekday_abbrev != "":
			date_str = "%s %d/%d" % [weekday_abbrev, month, day]

	# Get time played (placeholder for now - can be implemented when time tracking is added)
	var time_played := "Time Played"
	if payload.has("time_played"):
		var seconds := int(payload.get("time_played", 0))
		if seconds > 0:
			var hours := seconds / 3600  # Integer division
			var minutes := (seconds % 3600) / 60  # Integer division
			time_played = "%d:%02d" % [hours, minutes]

	# Format: "FirstName LastName : Mon 5/5 : Time Played"
	if date_str != "":
		return "%s : %s : %s" % [player_name, date_str, time_played]

	# Fallback to old format if calendar data missing
	var ds := String(payload.get("date_string",""))
	if ds != "":
		return "%s : %s : %s" % [player_name, ds, time_played]

	return player_name

## Safely retrieves an autoload node by name from the SceneTree root
func _get_autoload(autoload_name: String) -> Node:
	# Direct autoload lookup using absolute path
	return get_node_or_null("/root/" + autoload_name)

## Saves game data to a numbered slot as JSON. Wraps payload with version, timestamp, scene, and label.
## Automatically injects sigil data if missing. Returns true if save successful, false on file error.
func save_game(slot: int, payload: Dictionary) -> bool:
	# Wrap + save. Also inject a top-level "sigils" blob if missing.
	_ensure_dir()

	var payload2 := payload.duplicate(true)

	if not payload2.has("sigils"):
		var sig: Node = _get_autoload("aSigilSystem")
		if sig != null and sig.has_method("get_save_blob"):
			var sb_v: Variant = sig.call("get_save_blob")
			if typeof(sb_v) == TYPE_DICTIONARY:
				payload2["sigils"] = (sb_v as Dictionary)

	var save_path := _path(slot)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("[SaveLoad] Failed to open save file '%s' for writing (error %d)" % [save_path, err])
		return false

	var data := {
		"version": 1,
		"ts": int(Time.get_unix_time_from_system()),
		"scene": String(payload2.get("scene", "Main")),
		"label": String(payload2.get("label", "")),
		"payload": payload2,
	}
	if String(data["label"]) == "":
		data["label"] = _label_from_payload(payload2)

	var json_string := JSON.stringify(data, "\t")
	f.store_string(json_string)
	f.close()

	print("[SaveLoad] Successfully saved game to slot %d: %s" % [slot, save_path])
	return true

## Loads game data from a numbered slot. Returns the payload Dictionary from the save file.
## Returns empty Dictionary if slot doesn't exist or file is corrupted.
func load_game(slot: int) -> Dictionary:
	var load_path := _path(slot)
	if not FileAccess.file_exists(load_path):
		push_warning("[SaveLoad] Save file does not exist: %s" % load_path)
		return {}

	var f := FileAccess.open(load_path, FileAccess.READ)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("[SaveLoad] Failed to open save file '%s' for reading (error %d)" % [load_path, err])
		return {}

	var json_text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SaveLoad] Save file '%s' contains invalid JSON or is not a Dictionary" % load_path)
		return {}
	var root: Dictionary = parsed

	if root.has("payload") and typeof(root["payload"]) == TYPE_DICTIONARY:
		var p: Dictionary = root["payload"]
		if not p.has("label") and root.has("label"):
			p["label"] = String(root["label"])
		if not p.has("ts") and root.has("ts"):
			p["ts"] = int(root["ts"])
		return p

	return root

## Retrieves metadata for a save slot without loading the full payload.
## Returns Dictionary with: exists, ts (timestamp), scene, label, summary.
## Returns {"exists": false} if slot doesn't exist.
func get_slot_meta(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)): return {"exists": false}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null: return {"exists": false}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: return {"exists": false}

	var d: Dictionary = parsed
	var label := String(d.get("label",""))
	if label == "" and d.has("payload") and typeof(d["payload"]) == TYPE_DICTIONARY:
		label = _label_from_payload(d["payload"])
	var summary := label if label != "" else String(d.get("scene",""))

	return {
		"exists": true,
		"ts": int(d.get("ts", 0)),
		"scene": String(d.get("scene","")),
		"label": label,
		"summary": summary,
	}

## Checks if a save file exists for the given slot number
func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))

## Deletes a save slot file. Returns true if deletion successful, false if slot doesn't exist.
func delete_slot(slot: int) -> bool:
	if FileAccess.file_exists(_path(slot)):
		return DirAccess.remove_absolute(_path(slot)) == OK
	return false

## Returns a sorted array of all existing save slot numbers in the save directory
func list_slots() -> Array[int]:
	var out: Array[int] = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null: return out
	for fn in d.get_files():
		if fn.begins_with("slot_") and fn.ends_with(".json"):
			out.append(int(fn.substr(5, fn.length() - 10)))
	out.sort()
	return out
#LULU
