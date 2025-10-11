extends Node
class_name SigilSystem

signal loadout_changed(member: String)

const INV_PATH    : String = "/root/aInventorySystem"
const CSV_PATH    : String = "/root/aCSVLoader"
const EQUIP_PATH  : String = "/root/aEquipmentSystem"

const SKILLS_CSV  : String = "res://data/skills/skills.csv"
const HOLDER_CSV  : String = "res://data/skills/sigil_holder.csv"

const SIGIL_ID_PREFIX : String = "SIG_"
const INSTANCE_SEP    : String = "#"

var _skills_by_school : Dictionary = {}
var _holder_map       : Dictionary = {}
var _instances        : Dictionary = {}
var _owned            : PackedStringArray = PackedStringArray()
var _loadouts         : Dictionary = {}
var _capacity_by_member : Dictionary = {}
var _next_instance_idx : int = 1

func _ready() -> void:
	_load_skills_csv()
	_load_holder_csv()

# --------------------------------------------------------------------
# Skills CSV
# --------------------------------------------------------------------
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
				var arr: Array = _skills_by_school[school]
				arr.append(srec)
				_skills_by_school[school] = arr

	# Fallback seed if CSV missing/empty
	if _skills_by_school.is_empty():
		var schools: Array = ["Fire","Water","Earth","Air","Data","Void","Omega"]
		for s in schools:
			_skills_by_school[s] = [
				{"skill_id":"%s_I"   % s, "name":"%s I"   % s, "school":s, "level_req":1, "desc":""},
				{"skill_id":"%s_II"  % s, "name":"%s II"  % s, "school":s, "level_req":2, "desc":""},
				{"skill_id":"%s_III" % s, "name":"%s III" % s, "school":s, "level_req":3, "desc":""},
				{"skill_id":"%s_IV"  % s, "name":"%s IV"  % s, "school":s, "level_req":4, "desc":""}
			]

	# ensure sorted by level_req
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

# --------------------------------------------------------------------
# Sigil Holder CSV (gating per base_id)
# --------------------------------------------------------------------
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

# --------------------------------------------------------------------
# Public helpers
# --------------------------------------------------------------------
func is_instance_id(id: String) -> bool:
	return id.find(INSTANCE_SEP) >= 0

func list_owned_sigils() -> PackedStringArray:
	return _owned.duplicate()

func get_capacity(member: String) -> int:
	return int(_capacity_by_member.get(member, 0))

func get_loadout(member: String) -> PackedStringArray:
	if not _loadouts.has(member):
		return PackedStringArray()
	var arr_any: Array = _loadouts[member] as Array
	var out := PackedStringArray()
	for v in arr_any:
		out.append(String(v))
	return out

# --- compatibility (some UIs expect plain Array) ---
func get_loadout_array(member: String) -> Array[String]:
	var out: Array[String] = []
	var ps: PackedStringArray = get_loadout(member)
	for s in ps: out.append(String(s))
	return out

func get_display_name_for(id: String) -> String:
	if is_instance_id(id) and _instances.has(id):
		var inst: Dictionary = _instances[id]
		var base_id: String = String(inst.get("base_id",""))
		var nm: String = _item_name(base_id)
		var lvl: int = int(inst.get("level", 1))
		return "%s [Lv%d]" % [nm, lvl]
	return _item_name(id)

# alias some cheat UIs call
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

	# Map allowed IDs to display records
	var names: Dictionary = {}  # sid -> name
	if _skills_by_school.has(sch):
		for s in (_skills_by_school[sch] as Array):
			var rec: Dictionary = s
			names[String(rec["skill_id"])] = String(rec["name"])

	for sid in allowed:
		var nm: String = String(names.get(sid, sid))
		out.append({
			"skill_id": sid,
			"name": nm,
			"level_req": 0, # already gated
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

# Preferred API: instance-based
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

# Back-compat alias used by older UI
func set_active_skill(instance_id: String, skill_id: String) -> bool:
	return set_active_skill_for_instance(instance_id, skill_id)

# Member+socket API (some UIs call this)
func set_active_skill_member(member: String, socket_index: int, skill_id: String) -> bool:
	var sockets := get_loadout(member)
	if socket_index < 0 or socket_index >= sockets.size():
		return false
	var inst_id := String(sockets[socket_index])
	var ok := set_active_skill_for_instance(inst_id, skill_id)
	if ok:
		loadout_changed.emit(member)
	return ok

# --------------------------------------------------------------------
# Equip / Remove
# --------------------------------------------------------------------
func equip_into_socket(member: String, socket_index: int, id_or_base: String) -> bool:
	var inst_id: String = ""
	if not is_instance_id(id_or_base):
		if id_or_base.begins_with(SIGIL_ID_PREFIX):
			inst_id = _mint_instance_from_inventory(id_or_base)
			if inst_id == "":
				return false
		else:
			return false
	else:
		inst_id = id_or_base

	_ensure_capacity_from_bracelet(member)
	_ensure_loadout(member)
	_trim_or_expand_sockets(member)

	var sockets: Array = _loadouts[member] as Array
	if socket_index < 0 or socket_index >= sockets.size():
		return false

	sockets[socket_index] = inst_id
	_loadouts[member] = sockets

	if _owned.find(inst_id) < 0:
		_owned.append(inst_id)

	loadout_changed.emit(member)
	return true

func remove_sigil_at(member: String, socket_index: int) -> void:
	if not _loadouts.has(member):
		return
	var sockets: Array = _loadouts[member] as Array
	if socket_index < 0 or socket_index >= sockets.size():
		return
	sockets[socket_index] = ""
	_loadouts[member] = sockets
	loadout_changed.emit(member)

# --------------------------------------------------------------------
# Capacity: call this when bracelet changes
# --------------------------------------------------------------------
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
		sockets = _loadouts[member] as Array
	else:
		sockets = []

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

# --------------------------------------------------------------------
# Instance minting
# --------------------------------------------------------------------
func _mint_instance_from_inventory(base_id: String) -> String:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv == null:
		return ""

	if inv.has_method("get_count"):
		var c: int = int(inv.call("get_count", base_id))
		if c <= 0:
			return ""
	if inv.has_method("remove_item"):
		inv.call("remove_item", base_id, 1)

	var school: String = ""
	if inv.has_method("get_item_defs"):
		var defs_v: Variant = inv.call("get_item_defs")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			if defs.has(base_id):
				var rec: Dictionary = defs[base_id]
				if rec.has("sigil_school"):
					school = String(rec["sigil_school"]).capitalize()
				elif rec.has("mind_type_tag"):
					school = String(rec["mind_type_tag"]).capitalize()
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

# --------------------------------------------------------------------
# Progress / XP
# --------------------------------------------------------------------
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
	var xp: int = int(inst.get("xp", 0))
	var need: int = max(1, _xp_needed_for_level(lvl))
	var pct: int = int(clamp((float(xp) / float(need)) * 100.0, 0.0, 100.0))
	return {"pct": pct}

# ---- Cheat/XP APIs used by dev tools --------------------------------
func cheat_add_xp_to_instance(instance_id: String, amount: int, require_equipped: bool = false) -> void:
	if not _instances.has(instance_id):
		return
	if require_equipped and not _is_equipped(instance_id):
		return
	var inst: Dictionary = _instances[instance_id]
	var lvl: int = int(inst.get("level", 1))
	var xp: int  = int(inst.get("xp", 0))
	xp = max(0, xp + max(0, amount))

	var leveled: bool = false
	while lvl < 4:
		var need: int = max(1, _xp_needed_for_level(lvl))
		if xp >= need:
			xp -= need
			lvl += 1
			leveled = true
		else:
			break

	inst["level"] = lvl
	inst["xp"] = (0 if lvl >= 4 else xp)

	# keep active legal / prefer highest unlocked
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	var active: String = String(inst.get("active_skill",""))
	if allowed.size() > 0 and (active == "" or allowed.find(active) < 0):
		inst["active_skill"] = allowed[allowed.size() - 1]

	_instances[instance_id] = inst

	var who: String = _find_member_by_instance(instance_id)
	if leveled and who != "":
		loadout_changed.emit(who)

# Compatibility names a few tools might try
func add_xp_to_instance(instance_id: String, amount: int) -> void:
	cheat_add_xp_to_instance(instance_id, amount, false)

func grant_xp_to_instance(instance_id: String, amount: int) -> void:
	cheat_add_xp_to_instance(instance_id, amount, false)

# --------------------------------------------------------------------
# Cheat helpers
# --------------------------------------------------------------------
func list_free_instances() -> PackedStringArray:
	var in_sockets: Dictionary = {}
	for m in _loadouts.keys():
		var arr: Array = _loadouts[m] as Array
		for s in arr:
			var sid: String = String(s)
			if sid != "":
				in_sockets[sid] = true
	var out := PackedStringArray()
	for id in _owned:
		if not in_sockets.has(id):
			out.append(id)
	return out

# plain Array variants for older cheat bars
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
		var arr: Array = _loadouts[m] as Array
		for v in arr:
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
	# ensure active skill is legal for new level
	var allowed: PackedStringArray = _allowed_for_instance(instance_id)
	var active: String = String(inst.get("active_skill",""))
	if allowed.size() > 0 and allowed.find(active) < 0:
		inst["active_skill"] = allowed[allowed.size() - 1]  # prefer highest
	_instances[instance_id] = inst
	var who: String = _find_member_by_instance(instance_id)
	if who != "":
		loadout_changed.emit(who)

func debug_spawn_instance(base_id: String, level: int = 1, tier: int = 1, xp: int = 0) -> String:
	if base_id == "":
		return ""
	var school: String = ""
	var inv: Node = get_node_or_null(INV_PATH)
	if inv and inv.has_method("get_item_defs"):
		var dv: Variant = inv.call("get_item_defs")
		if typeof(dv) == TYPE_DICTIONARY:
			var defs: Dictionary = dv
			if defs.has(base_id):
				var rec: Dictionary = defs[base_id]
				if rec.has("sigil_school"):
					school = String(rec["sigil_school"]).capitalize()
				elif rec.has("mind_type_tag"):
					school = String(rec["mind_type_tag"]).capitalize()
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
# Local helpers
# --------------------------------------------------------------------
func _allowed_for_instance(instance_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not _instances.has(instance_id):
		return out
	var inst: Dictionary = _instances[instance_id]
	var base_id: String = String(inst.get("base_id",""))
	var level: int = int(inst.get("level", 1))
	var school: String = String(inst.get("school",""))

	# Holder-gated path (preferred)
	if _holder_map.has(base_id):
		var rec: Dictionary = _holder_map[base_id]
		var seen: Dictionary = {}
		for i in range(1, clamp(level,1,4) + 1):
			var key := "lv%d" % i
			if rec.has(key):
				var sid: String = String(rec[key])
				if sid != "" and not seen.has(sid):
					seen[sid] = true
					out.append(sid)
		return out

	# Fallback: use school list + level_req <= level
	if _skills_by_school.has(school):
		for s in (_skills_by_school[school] as Array):
			var d: Dictionary = s
			if int(d.get("level_req", 1)) <= level:
				out.append(String(d["skill_id"]))
	return out

func _is_equipped(instance_id: String) -> bool:
	for m in _loadouts.keys():
		var arr_v: Variant = _loadouts[m]
		if typeof(arr_v) == TYPE_ARRAY:
			var arr: Array = arr_v
			for s in arr:
				if String(s) == instance_id:
					return true
	return false

func _find_member_by_instance(instance_id: String) -> String:
	for m_k in _loadouts.keys():
		var member: String = String(m_k)
		var arr: Array = _loadouts[member] as Array
		for v in arr:
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

func _to_int(v: Variant) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT: return int(v)
	if t == TYPE_FLOAT: return int(roundf(float(v)))
	return String(v).to_int()
