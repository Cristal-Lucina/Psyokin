extends Node
class_name SigilSystem

signal loadout_changed(member: String)

const INV_PATH    : String = "/root/aInventorySystem"
const CSV_PATH    : String = "/root/aCSVLoader"
const EQUIP_PATH  : String = "/root/aEquipmentSystem"
const PARTY_PATH  : String = "/root/aPartySystem"
const MIND_PATH   : String = "/root/aMindTypeSystem"

const SKILLS_CSV  : String = "res://data/skills/skills.csv"
const HOLDER_CSV  : String = "res://data/skills/sigil_holder.csv"

const SIGIL_ID_PREFIX : String = "SIG_"
const INSTANCE_SEP    : String = "#"

var _skills_by_school     : Dictionary = {}
var _holder_map           : Dictionary = {}
var _instances            : Dictionary = {}         # inst_id -> {base_id, school, tier, level, xp, active_skill}
var _owned                : PackedStringArray = PackedStringArray()
var _loadouts             : Dictionary = {}         # member -> Array[String] of inst_ids (size = capacity)
var _capacity_by_member   : Dictionary = {}         # member -> int
var _next_instance_idx    : int = 1

func _ready() -> void:
	_load_skills_csv()
	_load_holder_csv()

# ───────────────────── Skills CSV ─────────────────────
func _load_skills_csv() -> void:
	_skills_by_school.clear()
	var csv_loader: Node = get_node_or_null(CSV_PATH)
	if csv_loader != null and FileAccess.file_exists(SKILLS_CSV):
		var table_v: Variant = csv_loader.call("load_csv", SKILLS_CSV, "skill_id")
		if typeof(table_v) == TYPE_DICTIONARY:
			var table: Dictionary = table_v
			for sid in table.keys():
				var row_v: Variant = table[sid]
				if typeof(row_v) != TYPE_DICTIONARY:
					continue
				var row: Dictionary = row_v
				var school: String = String(row.get("school","")).capitalize()
				if school == "":
					continue
				var srec: Dictionary = {
					"skill_id": String(sid),
					"name": String(row.get("name", String(sid))),
					"school": school,
					"level_req": int(_to_int(row.get("level_req", 1))),
					"desc": String(row.get("desc",""))
				}
				if not _skills_by_school.has(school):
					_skills_by_school[school] = []
				var arr_any: Variant = _skills_by_school[school]
				var arr: Array = (arr_any as Array) if typeof(arr_any) == TYPE_ARRAY else []
				arr.append(srec)
				_skills_by_school[school] = arr

	if _skills_by_school.is_empty():
		var schools: Array[String] = ["Fire","Water","Earth","Air","Data","Void","Omega"]
		for s in schools:
			_skills_by_school[s] = [
				{"skill_id":"%s_I"   % s, "name":"%s I"   % s, "school":s, "level_req":1, "desc":""},
				{"skill_id":"%s_II"  % s, "name":"%s II"  % s, "school":s, "level_req":2, "desc":""},
				{"skill_id":"%s_III" % s, "name":"%s III" % s, "school":s, "level_req":3, "desc":""},
				{"skill_id":"%s_IV"  % s, "name":"%s IV"  % s, "school":s, "level_req":4, "desc":""}
			]

	for k in _skills_by_school.keys():
		var a_v: Variant = _skills_by_school[k]
		if typeof(a_v) == TYPE_ARRAY:
			var a: Array = a_v
			a.sort_custom(Callable(self, "_cmp_skill_by_level"))
			_skills_by_school[k] = a

func _cmp_skill_by_level(x: Variant, y: Variant) -> bool:
	var dx: Dictionary = x as Dictionary
	var dy: Dictionary = y as Dictionary
	return int(dx["level_req"]) < int(dy["level_req"])

# ───────────────── Sigil Holder CSV ─────────────────
func _load_holder_csv() -> void:
	_holder_map.clear()
	var csv_loader: Node = get_node_or_null(CSV_PATH)
	if csv_loader == null or not FileAccess.file_exists(HOLDER_CSV):
		return
	var table_v: Variant = csv_loader.call("load_csv", HOLDER_CSV, "sigil_id")
	if typeof(table_v) != TYPE_DICTIONARY:
		return
	var table: Dictionary = table_v
	for base_id_v in table.keys():
		var base_id: String = String(base_id_v)
		var row: Dictionary = table[base_id]
		_holder_map[base_id] = {
			"lv1": String(row.get("lv1","")),
			"lv2": String(row.get("lv2","")),
			"lv3": String(row.get("lv3","")),
			"lv4": String(row.get("lv4",""))
		}

# ───────────────── Public helpers ─────────────────
func is_instance_id(id: String) -> bool:
	return id.find(INSTANCE_SEP) >= 0

func list_owned_sigils() -> PackedStringArray:
	return _owned.duplicate()

func get_capacity(member: String) -> int:
	return int(_capacity_by_member.get(member, 0))

func get_loadout(member: String) -> PackedStringArray:
	if not _loadouts.has(member):
		return PackedStringArray()
	var arr_any: Variant = _loadouts[member]
	var out := PackedStringArray()
	if typeof(arr_any) == TYPE_ARRAY:
		for v in (arr_any as Array):
			out.append(String(v))
	return out

func get_loadout_array(member: String) -> Array[String]:
	var out: Array[String] = []
	var ps: PackedStringArray = get_loadout(member)
	for s in ps:
		out.append(String(s))
	return out

func get_display_name_for(id: String) -> String:
	if is_instance_id(id) and _instances.has(id):
		var inst: Dictionary = _instances[id]
		var base_id: String = String(inst.get("base_id",""))
		var nm: String = _item_name(base_id)
		var lvl: int = int(inst.get("level", 1))
		return "%s [Lv%d]" % [nm, lvl]
	return _item_name(id)

func get_instance_display_name(instance_id: String) -> String:
	return get_display_name_for(instance_id)

func get_active_skill_name_for_instance(instance_id: String) -> String:
	if not _instances.has(instance_id):
		return ""
	var inst: Dictionary = _instances[instance_id]
	var cur: String = String(inst.get("active_skill",""))
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	if cur == "" or (allowed.size() > 0 and allowed.find(cur) < 0):
		cur = (allowed[0] if allowed.size() > 0 else "")
		inst["active_skill"] = cur
		_instances[instance_id] = inst
	return _skill_name(cur)

func get_active_skill_name(member: String, socket_index: int) -> String:
	var sockets: PackedStringArray = get_loadout(member)
	if socket_index < 0 or socket_index >= sockets.size():
		return ""
	var id: String = String(sockets[socket_index])
	return get_active_skill_name_for_instance(id)

func get_active_skill_id_for_instance(instance_id: String) -> String:
	if not _instances.has(instance_id):
		return ""
	var inst: Dictionary = _instances[instance_id]
	return String(inst.get("active_skill",""))

func get_skills_for_instance(instance_id: String) -> Array:
	var out: Array = []
	if not _instances.has(instance_id):
		return out
	var inst: Dictionary = _instances[instance_id]
	var sch: String = String(inst.get("school",""))
	var active: String = String(inst.get("active_skill",""))
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	var names: Dictionary = {}
	if _skills_by_school.has(sch):
		var arr_any: Variant = _skills_by_school[sch]
		if typeof(arr_any) == TYPE_ARRAY:
			for s in (arr_any as Array):
				var rec: Dictionary = s
				names[String(rec["skill_id"])] = String(rec["name"])
	for sid in allowed:
		var nm: String = String(names.get(sid, sid))
		out.append({
			"skill_id": sid,
			"name": nm,
			"level_req": 0,
			"unlocked": true,
			"is_active": (sid == active),
			"desc": ""
		})
	return out

func list_unlocked_skills(instance_id: String) -> PackedStringArray:
	return _allowed_for_instance(instance_id)

func get_skill_display_name(skill_id: String) -> String:
	return _skill_name(skill_id)

func get_instance_info(instance_id: String) -> Dictionary:
	if not _instances.has(instance_id):
		return {}
	return (_instances[instance_id] as Dictionary).duplicate(true)

func set_active_skill_for_instance(instance_id: String, skill_id: String) -> bool:
	if not _instances.has(instance_id):
		return false
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	if allowed.find(skill_id) < 0:
		return false
	var inst: Dictionary = _instances[instance_id]
	inst["active_skill"] = skill_id
	_instances[instance_id] = inst
	return true

func set_active_skill(instance_id: String, skill_id: String) -> bool:
	return set_active_skill_for_instance(instance_id, skill_id)

func set_active_skill_member(member: String, socket_index: int, skill_id: String) -> bool:
	var sockets := get_loadout(member)
	if socket_index < 0 or socket_index >= sockets.size():
		return false
	var inst_id := String(sockets[socket_index])
	var ok := set_active_skill_for_instance(inst_id, skill_id)
	if ok:
		loadout_changed.emit(member)
	return ok

# ───────────────── Equip / Remove ─────────────────

func equip_into_socket(member: String, socket_index: int, id_or_base: String) -> bool:
	var inst_id: String = ""
	# Gate by school before equipping
	if is_instance_id(id_or_base):
		var iid := id_or_base
		if not _instances.has(iid):
			return false
		var school_i := String((_instances[iid] as Dictionary).get("school",""))
		if school_i != "" and not _member_allows_school(member, school_i):
			return false
		inst_id = iid
	else:
		# base id path: peek school and gate
		var school_b := _school_of_base(id_or_base)
		if school_b != "" and not _member_allows_school(member, school_b):
			return false
		if id_or_base.begins_with(SIGIL_ID_PREFIX):
			inst_id = _mint_instance_from_inventory(id_or_base)
			if inst_id == "":
				return false
		else:
			return false

	_ensure_capacity_from_bracelet(member)
	_ensure_loadout(member)
	_trim_or_expand_sockets(member)

	var sockets_any: Variant = _loadouts.get(member, [])
	var sockets: Array = (sockets_any as Array) if typeof(sockets_any) == TYPE_ARRAY else []
	if socket_index < 0 or socket_index >= sockets.size():
		return false

	for s in sockets:
		if String(s) == inst_id:
			return false

	sockets[socket_index] = inst_id
	_loadouts[member] = sockets

	if _owned.find(inst_id) < 0:
		_owned.append(inst_id)

	loadout_changed.emit(member)
	return true

func equip_from_inventory(member: String, socket_index: int, base_id: String) -> bool:
	var iid: String = _mint_instance_from_inventory(base_id)
	if iid == "":
		return false
	# gate instance school as well
	var school := String(_instances.get(iid, {}).get("school",""))
	if school != "" and not _member_allows_school(member, school):
		return false
	return equip_into_socket(member, socket_index, iid)

func remove_sigil_at(member: String, socket_index: int) -> void:
	if not _loadouts.has(member):
		return
	var sockets_any: Variant = _loadouts[member]
	if typeof(sockets_any) != TYPE_ARRAY:
		return
	var sockets: Array = sockets_any
	if socket_index < 0 or socket_index >= sockets.size():
		return
	sockets[socket_index] = ""
	_loadouts[member] = sockets
	loadout_changed.emit(member)

# ───────────── Capacity: call when bracelet changes ─────────────

func on_bracelet_changed(member: String) -> void:
	_ensure_capacity_from_bracelet(member)
	_trim_or_expand_sockets(member)
	loadout_changed.emit(member)

func _ensure_capacity_from_bracelet(member: String) -> void:
	var cap: int = 0
	var eq: Node = get_node_or_null(EQUIP_PATH)
	var inv: Node = get_node_or_null(INV_PATH)

	var bracelet_id: String = ""
	if eq and eq.has_method("get_member_equip"):
		var d_v: Variant = eq.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			bracelet_id = String(d.get("bracelet",""))

	if bracelet_id != "" and inv and inv.has_method("get_item_defs"):
		var defs_v: Variant = inv.call("get_item_defs")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			if defs.has(bracelet_id):
				var rec: Dictionary = defs[bracelet_id]
				for k in ["sigil_slots","slots","capacity","slot_count"]:
					if rec.has(k):
						cap = int(_to_int(rec[k]))
						break

	_capacity_by_member[member] = max(0, cap)

func _trim_or_expand_sockets(member: String) -> void:
	var cap: int = get_capacity(member)
	var sockets: Array = []
	if _loadouts.has(member):
		var arr_any: Variant = _loadouts[member]
		if typeof(arr_any) == TYPE_ARRAY:
			sockets = arr_any
	if cap < sockets.size():
		while sockets.size() > cap:
			sockets.remove_at(sockets.size() - 1)
	elif cap > sockets.size():
		while sockets.size() < cap:
			sockets.append("")
	_loadouts[member] = sockets

func _ensure_loadout(member: String) -> void:
	if not _loadouts.has(member):
		_loadouts[member] = []

# ───────────────── Instance minting ─────────────────

func _mint_instance_from_inventory(base_id: String) -> String:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv == null:
		return ""

	var count: int = 0
	if inv.has_method("get_count"):
		var c_v: Variant = inv.call("get_count", base_id)
		if typeof(c_v) == TYPE_INT:
			count = int(c_v)
	elif inv.has_method("get_counts_dict"):
		var cd_v: Variant = inv.call("get_counts_dict")
		if typeof(cd_v) == TYPE_DICTIONARY:
			var cd: Dictionary = cd_v
			count = int(cd.get(base_id, 0))
	if count <= 0:
		return ""

	if inv.has_method("remove_item"):
		inv.call("remove_item", base_id, 1)
	elif inv.has_method("dec"):
		inv.call("dec", base_id, 1)
	elif inv.has_method("consume"):
		inv.call("consume", base_id, 1)
	elif inv.has_method("decrement"):
		inv.call("decrement", base_id, 1)
	elif inv.has_method("add"):
		inv.call("add", base_id, -1)

	var school: String = _school_of_base(base_id)
	if school == "":
		school = "Fire"

	var idx: int = _next_instance_idx
	_next_instance_idx += 1
	var inst_id: String = "%s%s%04d" % [base_id, INSTANCE_SEP, idx]

	_instances[inst_id] = {
		"base_id": base_id,
		"school": school,
		"tier": 1,
		"level": 1,
		"xp": 0,
		"active_skill": ""
	}

	if _owned.find(inst_id) < 0:
		_owned.append(inst_id)
	return inst_id

# ───────────────── Progress / XP ─────────────────

func _xp_needed_for_level(_level: int) -> int:
	return 100

func get_instance_level(instance_id: String) -> int:
	if not _instances.has(instance_id):
		return 1
	var inst: Dictionary = _instances[instance_id]
	return int(inst.get("level", 1))

func get_instance_progress(instance_id: String) -> Dictionary:
	if not _instances.has(instance_id):
		return {"pct": 0}
	var inst: Dictionary = _instances[instance_id]
	var lvl: int = int(inst.get("level", 1))
	if lvl >= 4:
		return {"pct": 100}
	var xp_cur: int = int(inst.get("xp", 0))
	var need: int = max(1, _xp_needed_for_level(lvl))
	var pct: int = int(clamp((float(xp_cur) / float(need)) * 100.0, 0.0, 100.0))
	return {"pct": pct}

func cheat_add_xp_to_instance(instance_id: String, amount: int, require_equipped: bool = false) -> void:
	if not _instances.has(instance_id):
		return
	if require_equipped and not _is_equipped(instance_id):
		return
	var inst: Dictionary = _instances[instance_id]
	var lvl: int = int(inst.get("level", 1))
	var xp_cur: int = int(inst.get("xp", 0))
	xp_cur = max(0, xp_cur + max(0, amount))
	var leveled: bool = false
	while lvl < 4:
		var need: int = max(1, _xp_needed_for_level(lvl))
		if xp_cur >= need:
			xp_cur -= need
			lvl += 1
			leveled = true
		else:
			break
	inst["level"] = lvl
	inst["xp"] = (0 if lvl >= 4 else xp_cur)
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	var active: String = String(inst.get("active_skill",""))
	if allowed.size() > 0 and (active == "" or allowed.find(active) < 0):
		inst["active_skill"] = allowed[allowed.size() - 1]
	_instances[instance_id] = inst
	var who: String = _find_member_by_instance(instance_id)
	if leveled and who != "":
		loadout_changed.emit(who)

func add_xp_to_instance(instance_id: String, amount: int) -> void:
	cheat_add_xp_to_instance(instance_id, amount, false)

func grant_xp_to_instance(instance_id: String, amount: int) -> void:
	cheat_add_xp_to_instance(instance_id, amount, false)

# ───────────────── Cheat helpers ─────────────────

func list_free_instances() -> PackedStringArray:
	var in_sockets: Dictionary = {}
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) != TYPE_ARRAY:
			continue
		for s in (arr_any as Array):
			var sid: String = String(s)
			if sid != "":
				in_sockets[sid] = true
	var out := PackedStringArray()
	for id in _owned:
		if not in_sockets.has(id):
			out.append(id)
	return out

func list_free_instances_array() -> Array[String]:
	var out: Array[String] = []
	for s in list_free_instances():
		out.append(String(s))
	return out

func list_all_instances(equipped_only: bool = false) -> Array[String]:
	var ids: Dictionary = {}
	if not equipped_only:
		for s in _owned:
			ids[String(s)] = true
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) != TYPE_ARRAY:
			continue
		for v in (arr_any as Array):
			var sid: String = String(v)
			if sid != "":
				ids[sid] = true
	var out: Array[String] = []
	for k in ids.keys():
		out.append(String(k))
	return out

func draft_from_inventory(base_id: String) -> String:
	return _mint_instance_from_inventory(base_id)

func cheat_set_instance_level(instance_id: String, new_level: int) -> void:
	if not _instances.has(instance_id):
		return
	var inst: Dictionary = _instances[instance_id]
	var clamped: int = clamp(new_level, 1, 4)
	inst["level"] = clamped
	if clamped >= 4:
		inst["xp"] = 0
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	var active: String = String(inst.get("active_skill",""))
	if allowed.size() > 0 and allowed.find(active) < 0:
		inst["active_skill"] = allowed[allowed.size() - 1]
	_instances[instance_id] = inst
	var who: String = _find_member_by_instance(instance_id)
	if who != "":
		loadout_changed.emit(who)

func debug_spawn_instance(base_id: String, level: int = 1, tier: int = 1, xp: int = 0) -> String:
	if base_id == "":
		return ""
	var school: String = _school_of_base(base_id)
	if school == "":
		school = "Fire"
	var idx: int = _next_instance_idx
	_next_instance_idx += 1
	var inst_id: String = "%s%s%04d" % [base_id, INSTANCE_SEP, idx]
	_instances[inst_id] = {
		"base_id": base_id,
		"school": school,
		"tier": max(1, tier),
		"level": clamp(level, 1, 4),
		"xp": max(0, xp),
		"active_skill": ""
	}
	if _owned.find(inst_id) < 0:
		_owned.append(inst_id)
	return inst_id


# --------------------------------------------------------------------
# Save / Load
# --------------------------------------------------------------------
func get_save_blob() -> Dictionary:
	# Persist instances, owned list, loadouts, and next id counter.
	var blob := {
		"instances": _instances.duplicate(true),     # inst_id -> {base_id, school, tier, level, xp, active_skill}
		"owned": _owned.duplicate(),                # PackedStringArray of inst_ids
		"loadouts": _loadouts.duplicate(true),      # member -> Array[String] of inst_ids
		"next_idx": _next_instance_idx               # int
	}
	return blob


func apply_save_blob(blob: Dictionary) -> void:
	# -------- instances --------
	var inst_in_v: Variant = blob.get("instances", {})
	var new_inst: Dictionary = {}
	if typeof(inst_in_v) == TYPE_DICTIONARY:
		var inst_in: Dictionary = inst_in_v
		for k_v in inst_in.keys():
			var iid: String = String(k_v)
			var row_v: Variant = inst_in[k_v]
			if typeof(row_v) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_v
			var base_id: String = String(row.get("base_id",""))
			if base_id == "":
				continue
			new_inst[iid] = {
				"base_id": base_id,
				"school": String(row.get("school","")),
				"tier": int(row.get("tier",1)),
				"level": int(row.get("level",1)),
				"xp": int(row.get("xp",0)),
				"active_skill": String(row.get("active_skill",""))
			}
	_instances = new_inst

	# -------- owned --------
	var owned_in_v: Variant = blob.get("owned", [])
	var new_owned := PackedStringArray()
	if typeof(owned_in_v) == TYPE_PACKED_STRING_ARRAY:
		new_owned = owned_in_v as PackedStringArray
	elif typeof(owned_in_v) == TYPE_ARRAY:
		for v in (owned_in_v as Array):
			var s := String(v)
			if _instances.has(s): new_owned.append(s)
	# ensure anything in sockets is also marked owned
	for m_k in _loadouts.keys():
		var arr_any: Variant = _loadouts[m_k]
		if typeof(arr_any) == TYPE_ARRAY:
			for sid_v in (arr_any as Array):
				var sid := String(sid_v)
				if sid != "" and _instances.has(sid) and new_owned.find(sid) < 0:
					new_owned.append(sid)
	_owned = new_owned

	# -------- loadouts --------
	var lo_in_v: Variant = blob.get("loadouts", {})
	var new_loadouts: Dictionary = {}
	if typeof(lo_in_v) == TYPE_DICTIONARY:
		var lo_in: Dictionary = lo_in_v
		for m_k in lo_in.keys():
			var member := String(m_k)
			var arr_v: Variant = lo_in[m_k]
			var arr: Array = []
			if typeof(arr_v) == TYPE_PACKED_STRING_ARRAY:
				arr = Array(arr_v)
			elif typeof(arr_v) == TYPE_ARRAY:
				arr = arr_v
			# keep only valid instance IDs
			var clean: Array = []
			for sid_v in arr:
				var sid := String(sid_v)
				if sid == "" or not _instances.has(sid):
					clean.append("")  # keep socket count stable, leave empty
				else:
					clean.append(sid)
			new_loadouts[member] = clean
	_loadouts = new_loadouts

	# -------- next index (defensive: recompute if needed) --------
	var want_next: int = int(blob.get("next_idx", 1))
	var max_seen: int = 0
	for iid_k in _instances.keys():
		var iid := String(iid_k)
		var pos := iid.rfind(INSTANCE_SEP)
		if pos >= 0 and pos + 1 < iid.length():
			var n_txt := iid.substr(pos + INSTANCE_SEP.length())
			var n := n_txt.to_int()
			if n > max_seen: max_seen = n
	_next_instance_idx = max(want_next, max_seen + 1)

	# -------- fit sockets to current bracelets and notify --------
	for m_k in _loadouts.keys():
		var member := String(m_k)
		_ensure_capacity_from_bracelet(member)
		_trim_or_expand_sockets(member)
		loadout_changed.emit(member)


# ───────────────── Local helpers ─────────────────

func _allowed_for_instance(instance_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not _instances.has(instance_id):
		return out
	var inst: Dictionary = _instances[instance_id]
	var base_id: String = String(inst.get("base_id",""))
	var level: int = int(inst.get("level", 1))
	var school: String = String(inst.get("school",""))

	if _holder_map.has(base_id):
		var rec_any: Variant = _holder_map[base_id]
		if typeof(rec_any) == TYPE_DICTIONARY:
			var rec: Dictionary = rec_any
			var seen: Dictionary = {}
			for i in range(1, clamp(level,1,4) + 1):
				var key := "lv%d" % i
				if rec.has(key):
					var sid: String = String(rec[key])
					if sid != "" and not seen.has(sid):
						seen[sid] = true
						out.append(sid)
		return out

	if _skills_by_school.has(school):
		var arr_any: Variant = _skills_by_school[school]
		if typeof(arr_any) == TYPE_ARRAY:
			for s in (arr_any as Array):
				var d: Dictionary = s
				if int(d.get("level_req", 1)) <= level:
					out.append(String(d["skill_id"]))
	return out

func _is_equipped(instance_id: String) -> bool:
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) != TYPE_ARRAY:
			continue
		for s in (arr_any as Array):
			if String(s) == instance_id:
				return true
	return false

func _find_member_by_instance(instance_id: String) -> String:
	for m_k in _loadouts.keys():
		var member: String = String(m_k)
		var arr_any: Variant = _loadouts[member]
		if typeof(arr_any) != TYPE_ARRAY:
			continue
		for v in (arr_any as Array):
			if String(v) == instance_id:
				return member
	return ""

func _item_name(item_id: String) -> String:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv and inv.has_method("get_item_defs"):
		var d_v: Variant = inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			if d.has(item_id):
				var r: Dictionary = d[item_id]
				return String(r.get("name", item_id))
	return item_id

func _skill_name(skill_id: String) -> String:
	for k in _skills_by_school.keys():
		var arr_v: Variant = _skills_by_school[k]
		if typeof(arr_v) == TYPE_ARRAY:
			var arr: Array = arr_v
			for s in arr:
				var d: Dictionary = s as Dictionary
				if String(d["skill_id"]) == skill_id:
					return String(d["name"])
	return skill_id

func _school_of_base(base_id: String) -> String:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv and inv.has_method("get_item_defs"):
		var dv: Variant = inv.call("get_item_defs")
		if typeof(dv) == TYPE_DICTIONARY:
			var defs: Dictionary = dv
			if defs.has(base_id):
				var rec: Dictionary = defs[base_id]
				if rec.has("sigil_school"):
					return String(rec["sigil_school"]).capitalize()
				if rec.has("mind_type_tag"):
					return String(rec["mind_type_tag"]).capitalize()
	return ""

func _member_allows_school(member: String, school: String) -> bool:
	var ps := get_node_or_null(PARTY_PATH)
	var mt := get_node_or_null(MIND_PATH)
	if ps == null or mt == null:
		return true  # fail-open if systems missing
	var base := ""
	if ps.has_method("get_member_mind_base"):
		base = String(ps.call("get_member_mind_base", member))
	if base == "":
		base = "Fire"
	if base == "Omega":
		return true
	if mt.has_method("is_school_allowed"):
		return bool(mt.call("is_school_allowed", base, school))
	return true

func _to_int(v: Variant) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT: return int(v)
	if t == TYPE_FLOAT: return int(roundf(float(v)))
	return String(v).to_int()
