extends Node
class_name SaveLoad

## SaveLoad
## JSON save files under `user://saves/` with one file per slot.
## Wrapper structure written to disk:
## {
##   "version": 1,
##   "ts": <unix time>,
##   "scene": "Main",
##   "label": "MM/DD — Weekday — Phase",
##   "payload": { ... }  # GameState._to_payload()
## }

const SAVE_DIR : String = "user://saves"

func _path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func _label_from_payload(payload: Dictionary) -> String:
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
	# Wrap + save. Also inject a top-level "sigils" blob if missing.
	_ensure_dir()

	var payload2 := payload.duplicate(true)

	if not payload2.has("sigils"):
		var sig := get_node_or_null("/root/aSigilSystem")
		if sig != null and sig.has_method("get_save_blob"):
			var sb_v: Variant = sig.call("get_save_blob")
			if typeof(sb_v) == TYPE_DICTIONARY:
				payload2["sigils"] = (sb_v as Dictionary)

	var f := FileAccess.open(_path(slot), FileAccess.WRITE)
	if f == null: return false

	var data := {
		"version": 1,
		"ts": int(Time.get_unix_time_from_system()),
		"scene": String(payload2.get("scene", "Main")),
		"label": String(payload2.get("label", "")),
		"payload": payload2,
	}
	if String(data["label"]) == "":
		data["label"] = _label_from_payload(payload2)

	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func load_game(slot: int) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)): return {}
	var f := FileAccess.open(_path(slot), FileAccess.READ)
	if f == null: return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY: return {}
	var root: Dictionary = parsed

	if root.has("payload") and typeof(root["payload"]) == TYPE_DICTIONARY:
		var p: Dictionary = root["payload"]
		if not p.has("label") and root.has("label"):
			p["label"] = String(root["label"])
		if not p.has("ts") and root.has("ts"):
			p["ts"] = int(root["ts"])
		return p

	return root

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

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_path(slot))

func delete_slot(slot: int) -> bool:
	if FileAccess.file_exists(_path(slot)):
		return DirAccess.remove_absolute(_path(slot)) == OK
	return false

func list_slots() -> Array[int]:
	var out: Array[int] = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null: return out
	for fn in d.get_files():
		if fn.begins_with("slot_") and fn.ends_with(".json"):
			out.append(int(fn.substr(5, fn.length() - 10)))
	out.sort()
	return out
