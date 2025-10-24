extends Node
class_name StatusEffects

signal status_changed(member: String)

# Storage
var _ailment: Dictionary = {}       # member -> String (e.g., "Poison", "" if none)
var _flags:   Dictionary = {}       # member -> { flag_name: bool }
var _buffs:   Dictionary = {}       # member -> Array[Dictionary]  (id, stacks, turns)
var _debuffs: Dictionary = {}       # member -> Array[Dictionary]

# ───────────── Public API ─────────────

func get_ailment_for(member: String) -> String:
	return String((_ailment.get(member, "")))

func set_ailment(member: String, ailment_id: String) -> void:
	_ailment[member] = String(ailment_id)
	status_changed.emit(member)

func get_flags_for(member: String) -> Dictionary:
	var d: Dictionary = _flags.get(member, {}) as Dictionary
	return d.duplicate(true)

func set_flag(member: String, key: String, value: bool) -> void:
	var d: Dictionary = _flags.get(member, {}) as Dictionary
	d[key] = bool(value)
	_flags[member] = d
	status_changed.emit(member)

func clear_flags(member: String) -> void:
	_flags.erase(member)
	status_changed.emit(member)

func get_buffs_for(member: String) -> Array:
	var arr: Array = _buffs.get(member, []) as Array
	return arr.duplicate(true)

func get_debuffs_for(member: String) -> Array:
	var arr: Array = _debuffs.get(member, []) as Array
	return arr.duplicate(true)

func add_buff(member: String, buff: Dictionary) -> void:
	var arr: Array = _buffs.get(member, []) as Array
	arr.append(_normalize_effect(buff))
	_buffs[member] = arr
	status_changed.emit(member)

func remove_buff(member: String, buff_id: String) -> void:
	var arr: Array = _buffs.get(member, []) as Array
	var out: Array = []
	for it_v in arr:
		if typeof(it_v) != TYPE_DICTIONARY: continue
		var it: Dictionary = it_v
		if String(it.get("id","")) != buff_id:
			out.append(it)
	_buffs[member] = out
	status_changed.emit(member)

func add_debuff(member: String, debuff: Dictionary) -> void:
	var arr: Array = _debuffs.get(member, []) as Array
	arr.append(_normalize_effect(debuff))
	_debuffs[member] = arr
	status_changed.emit(member)

func remove_debuff(member: String, debuff_id: String) -> void:
	var arr: Array = _debuffs.get(member, []) as Array
	var out: Array = []
	for it_v in arr:
		if typeof(it_v) != TYPE_DICTIONARY: continue
		var it: Dictionary = it_v
		if String(it.get("id","")) != debuff_id:
			out.append(it)
	_debuffs[member] = out
	status_changed.emit(member)

func clear_member(member: String) -> void:
	_ailment.erase(member)
	_flags.erase(member)
	_buffs.erase(member)
	_debuffs.erase(member)
	status_changed.emit(member)

# ───────────── Save/Load ─────────────

func get_save_blob() -> Dictionary:
	return {
		"v": 1,
		"ailment": _ailment.duplicate(true),
		"flags":   _flags.duplicate(true),
		"buffs":   _buffs.duplicate(true),
		"debuffs": _debuffs.duplicate(true),
	}

func apply_save_blob(blob: Dictionary) -> void:
	_ailment = {}
	_flags   = {}
	_buffs   = {}
	_debuffs = {}
	var a_v: Variant = blob.get("ailment", {})
	if typeof(a_v) == TYPE_DICTIONARY: _ailment = (a_v as Dictionary).duplicate(true)
	var f_v: Variant = blob.get("flags", {})
	if typeof(f_v) == TYPE_DICTIONARY: _flags   = (f_v as Dictionary).duplicate(true)
	var b_v: Variant = blob.get("buffs", {})
	if typeof(b_v) == TYPE_DICTIONARY: _buffs   = (b_v as Dictionary).duplicate(true)
	var d_v: Variant = blob.get("debuffs", {})
	if typeof(d_v) == TYPE_DICTIONARY: _debuffs = (d_v as Dictionary).duplicate(true)
	# ping listeners for all known members
	var notified: Dictionary = {}
	for m in _ailment.keys(): notified[String(m)] = true
	for m in _flags.keys():   notified[String(m)] = true
	for m in _buffs.keys():   notified[String(m)] = true
	for m in _debuffs.keys(): notified[String(m)] = true
	for m2 in notified.keys():
		var member: String = String(m2)
		call_deferred("_emit_status_changed_safe", member)

func clear_all() -> void:
	_ailment.clear()
	_flags.clear()
	_buffs.clear()
	_debuffs.clear()

func _emit_status_changed_safe(member: String) -> void:
	if is_inside_tree():
		status_changed.emit(member)

# ───────────── Internals ─────────────

func _normalize_effect(d: Dictionary) -> Dictionary:
	# normalize to {id:String, stacks:int, turns:int}
	var id: String = String(d.get("id",""))
	var stacks: int = int(d.get("stacks", 1))
	var turns: int  = int(d.get("turns", 0))
	return {"id": id, "stacks": max(1, stacks), "turns": max(0, turns)}
