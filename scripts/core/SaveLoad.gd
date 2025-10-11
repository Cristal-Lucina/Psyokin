extends Node
class_name SaveLoad

## SaveLoad
## JSON save files under `user://saves/` with one file per slot.
## Wrapper structure written to disk:
## {
##   "version": 1,
##   "ts": <unix time>,
##   "scene": "Main",
##   "label": "MM/DD — Weekday — Phase",   # auto-derived if blank
##   "payload": { ... }                     # GameState._to_payload()
## }
##
## Notes:
## - load_game() returns the payload; if missing, falls back to returning the root.
## - get_slot_meta() does a light read for UI lists.
## - _label_from_payload() builds a human-friendly label from the calendar block.

const SAVE_DIR : String = "user://saves"

func _path(slot: int) -> String:
	## File path for a given slot (e.g., slot_1.json).
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func _ensure_dir() -> void:
	## Make sure the save directory exists.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _label_from_payload(payload: Dictionary) -> String:
	## Build a label like "05/10 — Saturday — Morning" from the payload.
	if payload.has("calendar") and typeof(payload["calendar"]) == TYPE_DICTIONARY:
		var c: Dictionary = payload["calendar"]
		var date: Dictionary = c.get("date", {})
		var month := int(date.get("month", 0))
		var day   := int(date.get("day", 0))

		var weekday_name := ""
		var wi := int(c.get("weekday", -1))
		if wi >= 0:
			var names := ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
			if wi >= 0 and wi < names.size(): weekday_name = names[wi]

		var phase_name := ""
		match int(c.get("phase", -1)):
			0: phase_name = "Morning"
			1: phase_name = "Afternoon"
			2: phase_name = "Evening"
			_: pass

		if month > 0 and day > 0:
			var md := "%02d/%02d" % [month, day]
			var parts: Array[String] = [md]
			if weekday_name != "": parts.append(weekday_name)
			if phase_name  != "": parts.append(phase_name)
			return " — ".join(parts)

	# Legacy label fields
	var ds := String(payload.get("date_string",""))
	var wd := String(payload.get("weekday",""))
	var ph := String(payload.get("phase",""))
	if ds != "" or wd != "" or ph != "":
		var p2: Array[String] = []
		if ds != "": p2.append(ds)
		if wd != "": p2.append(wd)
		if ph != "": p2.append(ph)
		return " — ".join(p2)

	return ""

func save_game(slot: int, payload: Dictionary) -> bool:
	## Write a slot file wrapping your payload with metadata.
	_ensure_dir()
	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null: return false

	var data := {
		"version": 1,
		"ts": int(Time.get_unix_time_from_system()),
		"scene": String(payload.get("scene", "Main")),
		"label": String(payload.get("label", "")),
		"payload": payload,
	}
	if String(data["label"]) == "":
		data["label"] = _label_from_payload(payload)

	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func load_game(slot: int) -> Dictionary:
	## Read a slot file and return the payload (enriched with top-level label/ts).
	if not FileAccess.file_exists(_path(slot)): return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null: return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: return {}
	var root: Dictionary = parsed

	# Return the payload enriched with top-level metadata (label/ts) so
	# GameState can fallback for older/broken saves.
	if root.has("payload") and typeof(root["payload"]) == TYPE_DICTIONARY:
		var p: Dictionary = root["payload"]
		if not p.has("label") and root.has("label"):
			p["label"] = String(root["label"])
		if not p.has("ts") and root.has("ts"):
			p["ts"] = int(root["ts"])
		return p

	return root

func get_slot_meta(slot: int) -> Dictionary:
	## Lightweight read for UI list rows (exists/ts/scene/label/summary).
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

func slot_exists(slot: int) -> bool:
	## Returns true if the slot file exists.
	return FileAccess.file_exists(_path(slot))

func delete_slot(slot: int) -> bool:
	## Deletes a slot file; returns true on success.
	if FileAccess.file_exists(_path(slot)):
		return DirAccess.remove_absolute(_path(slot)) == OK
	return false

func list_slots() -> Array[int]:
	## Enumerate existing slots by scanning SAVE_DIR.
	var out: Array[int] = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null: return out
	for fn in d.get_files():
		if fn.begins_with("slot_") and fn.ends_with(".json"):
			out.append(int(fn.substr(5, fn.length() - 10)))
	out.sort()
	return out
