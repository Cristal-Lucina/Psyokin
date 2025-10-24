## ═══════════════════════════════════════════════════════════════════════════
## SigilSystem - Sigil Instance & Loadout Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages sigil instances (unique copies of base sigils with individual XP,
##   levels, and skill selections), loadout assignments (which sigils are
##   equipped in which member's bracelet slots), and skill progression.
##
## RESPONSIBILITIES:
##   • Sigil instance creation and tracking (base_id -> unique instance_id)
##   • XP/level progression system (Level 1-4, with XP thresholds)
##   • Active skill unlocking and selection per instance
##   • Loadout management (member -> array of equipped instance IDs)
##   • School/mind-type restrictions (member can only use compatible sigils)
##   • Bracelet capacity tracking (slot count from equipped bracelet item)
##   • CSV-based skill database (skill names, sigil holder mappings)
##
## INSTANCE ID FORMAT:
##   Base sigils (e.g., "SIG_FIRE_001") become instances like "SIG_FIRE_001#0042"
##   The "#" separator distinguishes instances from base IDs.
##
## CONNECTED SYSTEMS (Autoloads):
##   • InventorySystem - Base sigil definitions, consuming sigils from inventory
##   • EquipmentSystem - Bracelet item -> sigil slot capacity
##   • MindTypeSystem - School compatibility checks (Fire, Water, Earth, etc.)
##   • GameState - Save/load coordination, member roster
##   • StatsSystem - Member mind types (indirectly via member data)
##
## CSV DATA SOURCES:
##   • res://data/skills/skills.csv - skill_id, name, description
##   • res://data/skills/sigil_holder.csv - sigil_id, lv1, lv2, lv3, lv4 skills
##
## PROGRESSION:
##   Level 1 -> 120 XP -> Level 2 -> 240 XP -> Level 3 -> 360 XP -> Level 4 (MAX)
##   Each level unlocks more skills from the sigil's holder CSV entry.
##
## SAVE/LOAD:
##   Called by GameState after EquipmentSystem loads (needs bracelet capacity).
##   Saves: instances dict, owned array, loadouts dict, next_idx counter.
##   Restores: XP, levels, active skills, slot assignments.
##
## KEY METHODS:
##   • acquire_sigil(base_id) -> instance_id - Create new instance
##   • equip_into_socket(member, slot, inst_id) - Equip to specific slot
##   • equip_from_inventory(member, slot, base_id) - Consume from inventory
##   • get_loadout(member) -> PackedStringArray - Get equipped instances
##   • list_free_instances() -> PackedStringArray - Get unequipped instances
##   • set_instance_level/xp() - Restore saved progression
##   • set_active_skill_for_instance() - Set chosen skill
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name SigilSystem

# ─────────────────────── Signals ───────────────────────
signal grant_sigil_xp(inst_id: String, amount: int, require_equipped: bool, source: String)
signal instance_xp_changed(inst_id: String, level: int, xp_pool: int, to_next: int)
signal instances_changed
signal loadout_changed(member: String)

# ─────────────────────── Paths / Data ───────────────────────
const INV_PATH: String   = "/root/aInventorySystem"
const EQUIP_PATH: String = "/root/aEquipmentSystem"
const MIND_PATH: String  = "/root/aMindTypeSystem"

const DATA_DIR: String        = "res://data/skills/"
const PATH_SKILLS: String     = DATA_DIR + "skills.csv"         # columns: skill_id,name,...
const PATH_HOLDER: String     = DATA_DIR + "sigil_holder.csv"   # columns: sigil_id,lv1,lv2,lv3,lv4
const PATH_XP_TABLE: String   = DATA_DIR + "sigil_xp_table.csv" # optional, not required for names
const MAX_LEVEL: int = 4

const SIGIL_ID_PREFIX: String = "SIG_"
const INSTANCE_SEP: String    = "#"

# ─────────────────────── Runtime state ───────────────────────
# instance_id -> {base_id, school, tier, level, xp, active_skill}
var _instances: Dictionary = {}
var _owned: PackedStringArray = PackedStringArray()
var _loadouts: Dictionary = {}           # member -> Array[String]
var _capacity_by_member: Dictionary = {} # member -> int
var _next_instance_idx: int = 1

# CSV-backed DBs
# e.g. "FIRE_L1" -> "Fire Bolt"
var _skill_name_by_id: Dictionary = {}
# e.g. "SIG_001" -> ["FIRE_L1","FIRE_L2","FIRE_L3","FIRE_L4"]
var _holder_skills_by_base: Dictionary = {}

# ─────────────────────── Lifecycle ───────────────────────
func _ready() -> void:
	_load_databases()
	if not grant_sigil_xp.is_connected(_on_grant_sigil_xp):
		grant_sigil_xp.connect(_on_grant_sigil_xp)

# Public: if you hot-reload CSVs during dev
func reload_skill_data() -> void:
	_load_databases()

# ─────────────────────── Public API (instances / sockets) ───────────────────────
func acquire_sigil(base_id: String) -> String:
	var school: String = _school_of_base(base_id)
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

func equip_into_socket(member: String, socket_index: int, inst_or_base: String) -> bool:
	_ensure_capacity_from_bracelet(member)
	_ensure_loadout(member)
	_trim_or_expand_sockets(member)

	# Normalize: if a base id sneaks in, auto-create an instance so sockets never store bases
	var inst_id := inst_or_base
	if not _instances.has(inst_id) and inst_id != "":
		inst_id = acquire_sigil(inst_id)  # create an instance from base id (no inventory ops here)

	var sockets: Array = []
	var sockets_any: Variant = _loadouts.get(member, [])
	if typeof(sockets_any) == TYPE_ARRAY:
		sockets = sockets_any as Array

	if socket_index < 0 or socket_index >= sockets.size():
		return false

	# prevent duplicates
	for s in sockets:
		if String(s) == inst_id:
			return false

	# ── NEW: ensure the instance has an active skill selected ─────────────
	if _instances.has(inst_id):
		var cur_active := String(_instances[inst_id].get("active_skill",""))
		if cur_active.strip_edges() == "":
			var unlocked: PackedStringArray = list_unlocked_skills(inst_id)
			if unlocked.size() > 0:
				# set directly (quiet) or use helper:
				_instances[inst_id]["active_skill"] = String(unlocked[0])
	# ──────────────────────────────────────────────────────────────────────

	sockets[socket_index] = inst_id
	_loadouts[member] = sockets

	if _owned.find(inst_id) < 0:
		_owned.append(inst_id)

	emit_signal("loadout_changed", member)
	return true


func remove_sigil_at(member: String, socket_index: int) -> void:
	if not _loadouts.has(member): return
	var sockets_any: Variant = _loadouts[member]
	if typeof(sockets_any) != TYPE_ARRAY: return
	var sockets: Array = sockets_any
	if socket_index < 0 or socket_index >= sockets.size(): return
	sockets[socket_index] = ""
	_loadouts[member] = sockets
	emit_signal("loadout_changed", member)

func equip_from_inventory(member: String, socket_index: int, base_id: String) -> bool:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv != null:
		if inv.has_method("get_count"):
			var c_v: Variant = inv.call("get_count", base_id)
			if typeof(c_v) == TYPE_INT and int(c_v) <= 0:
				return false
		if inv.has_method("remove_item"): inv.call("remove_item", base_id, 1)
		elif inv.has_method("consume"):    inv.call("consume", base_id, 1)
		elif inv.has_method("add"):        inv.call("add", base_id, -1)
	var iid: String = acquire_sigil(base_id)
	if iid == "": return false
	var school: String = String(_instances[iid].get("school", ""))
	if school != "" and not _member_allows_school(member, school): return false
	return equip_into_socket(member, socket_index, iid)

func get_capacity(member: String) -> int:
	return int(_capacity_by_member.get(member, 0))

func get_loadout(member: String) -> PackedStringArray:
	_ensure_capacity_from_bracelet(member)
	_ensure_loadout(member)
	_trim_or_expand_sockets(member)

	# Convert any base ids found in sockets into instances on the fly
	var changed := false
	if _loadouts.has(member) and typeof(_loadouts[member]) == TYPE_ARRAY:
		var arr: Array = _loadouts[member]
		for i in range(arr.size()):
			var s: String = String(arr[i])
			if s != "" and not _instances.has(s):
				var iid := acquire_sigil(s)
				arr[i] = iid
				if _owned.find(iid) < 0:
					_owned.append(iid)
				changed = true
		if changed:
			_loadouts[member] = arr
			if has_signal("loadout_changed"):
				emit_signal("loadout_changed", member)

	var out := PackedStringArray()
	var arr_any: Variant = _loadouts.get(member, [])
	if typeof(arr_any) == TYPE_ARRAY:
		for v in (arr_any as Array):
			out.append(String(v))
	return out

func list_free_instances() -> PackedStringArray:
	var slotted: Dictionary = {}
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) != TYPE_ARRAY: continue
		for s in (arr_any as Array):
			var sid: String = String(s)
			if sid != "": slotted[sid] = true
	var out := PackedStringArray()
	for iid in _owned:
		if not slotted.has(iid): out.append(iid)
	return out

# ── ID helpers ──────────────────────────────────────────────
func is_instance_id(s: String) -> bool:
	return _instances.has(s)

func get_base_from_instance(id_or_inst: String) -> String:
	if _instances.has(id_or_inst):
		return String(_instances[id_or_inst].get("base_id", ""))
	return id_or_inst

# Common aliases
func get_base_id(id_or_inst: String) -> String:
	return get_base_from_instance(id_or_inst)
func get_base_for(id_or_inst: String) -> String:
	return get_base_from_instance(id_or_inst)
func get_source_base(id_or_inst: String) -> String:
	return get_base_from_instance(id_or_inst)

# ── School helpers for UI filtering ─────────────────────────
func get_element_for(base_id: String) -> String:
	return _school_of_base(base_id)
func get_mind_for(base_id: String) -> String:
	return _school_of_base(base_id)
func get_element_for_instance(inst_id: String) -> String:
	if _instances.has(inst_id):
		return String(_instances[inst_id].get("school",""))
	return _school_of_base(get_base_from_instance(inst_id))
func get_mind_for_instance(inst_id: String) -> String:
	return get_element_for_instance(inst_id)

# ─────────────────────── Names / labels ───────────────────────
func get_display_name_for(id_or_inst: String) -> String:
	var base: String = get_base_from_instance(id_or_inst)
	if base == "":
		base = id_or_inst
	var rec: Dictionary = _item_def(base)
	var label: String = ""
	for k in ["display_name","name"]:
		if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
			label = String(rec[k]); break
	if label == "": label = base
	if is_instance_id(id_or_inst):
		var idx_text: String = id_or_inst.substr(id_or_inst.find(INSTANCE_SEP) + INSTANCE_SEP.length())
		if idx_text != "":
			label = "%s #%s" % [label, idx_text]
	return label

# Pretty-name for a skill id from CSVs
func get_skill_display_name(skill_id: String) -> String:
	if skill_id == "": return ""
	if _skill_name_by_id.has(skill_id):
		return String(_skill_name_by_id[skill_id])
	return skill_id

# Active skill helpers
func get_active_skill_id_for_instance(inst_id: String) -> String:
	if _instances.has(inst_id):
		return String(_instances[inst_id].get("active_skill", ""))
	return ""

func get_active_skill_name_for_instance(inst_id: String) -> String:
	var sid: String = get_active_skill_id_for_instance(inst_id)
	return (get_skill_display_name(sid) if sid != "" else "")

# ─────────────────────── Unlock logic ───────────────────────
func list_unlocked_skills(inst_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not _instances.has(inst_id): return out

	var lvl: int = int(_instances[inst_id].get("level", 1))
	var base_id: String = String(_instances[inst_id].get("base_id", ""))

	if base_id != "" and _holder_skills_by_base.has(base_id):
		var arr_any: Variant = _holder_skills_by_base[base_id]
		if typeof(arr_any) == TYPE_ARRAY:
			var arr: Array = arr_any as Array
			var count: int = clampi(lvl, 1, arr.size())
			for i in range(count):
				out.append(String(arr[i]))
			return out

	# Fallback unlocks
	out.append("Skill I")
	if lvl >= 3: out.append("Skill II")
	if lvl >= 5: out.append("Skill III")
	return out

func set_active_skill_for_instance(inst_id: String, skill_id: String) -> bool:
	if not _instances.has(inst_id): return false
	var unlocked: PackedStringArray = list_unlocked_skills(inst_id)
	if unlocked.find(skill_id) < 0: return false
	_instances[inst_id]["active_skill"] = skill_id
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) == TYPE_ARRAY:
			for s in (arr_any as Array):
				if String(s) == inst_id and has_signal("loadout_changed"):
					emit_signal("loadout_changed", String(m))
	return true

func set_active_skill_for_instance_by_name(inst_id: String, skill_name: String) -> bool:
	if not _instances.has(inst_id): return false
	var unlocked: PackedStringArray = list_unlocked_skills(inst_id)
	for skill_id in unlocked:
		var display_name: String = get_skill_display_name(skill_id)
		if display_name == skill_name:
			return set_active_skill_for_instance(inst_id, skill_id)
	return false

# ─────────────────────── Cheats / XP API ───────────────────────
func get_instance_level(inst_id: String) -> int:
	if _instances.has(inst_id): return int(_instances[inst_id].get("level", 1))
	return 1

func set_instance_level(inst_id: String, new_level: int) -> void:
	if not _instances.has(inst_id):
		return
	var lvl: int = clamp(new_level, 1, MAX_LEVEL)
	_instances[inst_id]["level"] = lvl
	_instances[inst_id]["xp"] = 0 if lvl >= MAX_LEVEL else int(_instances[inst_id].get("xp", 0))
	_emit_progress(inst_id)

func set_instance_xp(inst_id: String, xp_amount: int) -> void:
	if not _instances.has(inst_id):
		return
	var lvl: int = int(_instances[inst_id].get("level", 1))
	_instances[inst_id]["xp"] = (0 if lvl >= MAX_LEVEL else max(0, xp_amount))
	_emit_progress(inst_id)

func get_instance_xp(inst_id: String) -> int:
	if _instances.has(inst_id):
		return int(_instances[inst_id].get("xp", 0))
	return 0

func cheat_set_instance_level(inst_id: String, new_level: int) -> void:
	set_instance_level(inst_id, new_level)

func cheat_add_xp_to_instance(inst_id: String, amount: int, require_equipped: bool) -> void:
	add_xp_to_instance(inst_id, amount, require_equipped, "cheat")

func add_xp_to_instance(inst_id: String, amount: int, require_equipped: bool = false, _source: String = "") -> void:
	if amount == 0 or not _instances.has(inst_id):
		return
	if require_equipped and not _is_equipped(inst_id):
		return

	var row: Dictionary = _instances[inst_id]
	var cur_lvl: int = int(row.get("level", 1))
	var pool: int = int(row.get("xp", 0)) + amount

	while cur_lvl < MAX_LEVEL and pool >= _xp_to_next_level(cur_lvl):
		pool -= _xp_to_next_level(cur_lvl)
		cur_lvl += 1

	_instances[inst_id]["level"] = cur_lvl
	_instances[inst_id]["xp"]    = (0 if cur_lvl >= MAX_LEVEL else max(0, pool))

	_emit_progress(inst_id)

func get_instance_progress(inst_id: String) -> Dictionary:
	if not _instances.has(inst_id):
		return {"pct": 0, "xp": 0, "to_next": 0, "level": 1}
	var lvl: int = int(_instances[inst_id].get("level", 1))
	var xp: int  = int(_instances[inst_id].get("xp", 0))
	if lvl >= MAX_LEVEL:
		return {"pct": 100, "xp": 0, "to_next": 0, "level": MAX_LEVEL}
	var to_next: int = _xp_to_next_level(lvl)
	var pct: int = int(round(100.0 * float(xp) / float(max(1, to_next))))
	return {"pct": clampi(pct, 0, 100), "xp": xp, "to_next": to_next, "level": lvl}

# ─────────────────────── Save / Load ───────────────────────
func save() -> Dictionary:
	return {
		"instances": _instances.duplicate(true),
		"owned": _owned.duplicate(),
		"loadouts": _loadouts.duplicate(true),
		"next_idx": _next_instance_idx
	}

# Bridge method for SaveLoad fallback compatibility
func get_save_blob() -> Dictionary:
	return save()

func load(data: Dictionary) -> void:
	var inst_in_v: Variant = data.get("instances", {})
	var new_inst: Dictionary = {}
	if typeof(inst_in_v) == TYPE_DICTIONARY:
		var inst_in: Dictionary = inst_in_v
		for k_v in inst_in.keys():
			var iid: String = String(k_v)
			var row_v: Variant = inst_in[k_v]
			if typeof(row_v) != TYPE_DICTIONARY: continue
			var row: Dictionary = row_v
			var base_id: String = String(row.get("base_id", ""))
			if base_id == "": continue
			new_inst[iid] = {
				"base_id": base_id,
				"school": String(row.get("school", "")),
				"tier": int(row.get("tier", 1)),
				"level": int(row.get("level", 1)),
				"xp": int(row.get("xp", 0)),
				"active_skill": String(row.get("active_skill", ""))
			}
	_instances = new_inst

	var lo_in_v: Variant = data.get("loadouts", {})
	var new_loadouts: Dictionary = {}
	if typeof(lo_in_v) == TYPE_DICTIONARY:
		var lo_in: Dictionary = lo_in_v
		for m_k in lo_in.keys():
			var member: String = String(m_k)
			var arr_v: Variant = lo_in[m_k]
			var arr: Array = []
			if typeof(arr_v) == TYPE_PACKED_STRING_ARRAY: arr = Array(arr_v)
			elif typeof(arr_v) == TYPE_ARRAY: arr = arr_v as Array
			var clean: Array = []
			for sid_v in arr:
				var sid_str: String = String(sid_v)
				clean.append(sid_str if sid_str != "" and _instances.has(sid_str) else "")
			new_loadouts[member] = clean
	_loadouts = new_loadouts

	var owned_in_v: Variant = data.get("owned", [])
	var new_owned: PackedStringArray = PackedStringArray()
	if typeof(owned_in_v) == TYPE_PACKED_STRING_ARRAY:
		new_owned = owned_in_v as PackedStringArray
	elif typeof(owned_in_v) == TYPE_ARRAY:
		for v in (owned_in_v as Array):
			var s: String = String(v)
			if _instances.has(s): new_owned.append(s)
	for m_k in _loadouts.keys():
		var arr_any: Variant = _loadouts[m_k]
		if typeof(arr_any) == TYPE_ARRAY:
			for sid_v in (arr_any as Array):
				var sid: String = String(sid_v)
				if sid != "" and _instances.has(sid) and new_owned.find(sid) < 0:
					new_owned.append(sid)
	_owned = new_owned

	var want_next: int = int(data.get("next_idx", _next_instance_idx))
	var max_seen: int = 0
	for iid_k in _instances.keys():
		var iid_str: String = String(iid_k)
		var pos: int = iid_str.rfind(INSTANCE_SEP)
		if pos >= 0 and pos + 1 < iid_str.length():
			var n_txt: String = iid_str.substr(pos + INSTANCE_SEP.length())
			var n_val: int = n_txt.to_int()
			if n_val > max_seen: max_seen = n_val
	_next_instance_idx = max(want_next, max_seen + 1)

	for m_k in _loadouts.keys():
		var member_name: String = String(m_k)
		_ensure_capacity_from_bracelet(member_name)
		_trim_or_expand_sockets(member_name)
		emit_signal("loadout_changed", member_name)

# Bridge method for SaveLoad fallback compatibility
func apply_save_blob(blob: Dictionary) -> void:
	self.load(blob)

func grant_sigil_instance(_id: String, _amount: int = 1) -> void:
	emit_signal("instances_changed")

# ─────────────────────── Internals ───────────────────────
func _on_grant_sigil_xp(inst_id: String, amount: int, require_equipped: bool, _source: String) -> void:
	add_xp_to_instance(inst_id, amount, require_equipped, _source)

func _emit_progress(inst_id: String) -> void:
	var p: Dictionary = get_instance_progress(inst_id)
	emit_signal("instance_xp_changed", inst_id, int(p.get("level", 1)), int(p.get("xp", 0)), int(p.get("to_next", 0)))

func _ensure_loadout(member: String) -> void:
	if not _loadouts.has(member):
		_loadouts[member] = []

func _ensure_capacity_from_bracelet(member: String) -> void:
	var cap: int = 0
	var eq: Node = get_node_or_null(EQUIP_PATH)
	var inv: Node = get_node_or_null(INV_PATH)
	var bracelet_id: String = ""
	if eq != null and eq.has_method("get_member_equip"):
		var d_v: Variant = eq.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			bracelet_id = String(d.get("bracelet", ""))
	if bracelet_id != "" and inv != null and inv.has_method("get_item_defs"):
		var defs_v: Variant = inv.call("get_item_defs")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			if defs.has(bracelet_id):
				var rec: Dictionary = defs[bracelet_id]
				for k in ["sigil_slots","slots","capacity","slot_count"]:
					if rec.has(k): cap = int(rec[k]); break
	_capacity_by_member[member] = max(0, cap)

func _trim_or_expand_sockets(member: String) -> void:
	var cap: int = get_capacity(member)
	var sockets: Array = []
	if _loadouts.has(member):
		var arr_any: Variant = _loadouts[member]
		if typeof(arr_any) == TYPE_ARRAY:
			sockets = arr_any as Array
	if cap < sockets.size():
		while sockets.size() > cap: sockets.remove_at(sockets.size() - 1)
	elif cap > sockets.size():
		while sockets.size() < cap: sockets.append("")
	_loadouts[member] = sockets

func _member_allows_school(member: String, school: String) -> bool:
	return is_school_allowed_for_member(member, school)

func is_school_allowed_for_member(member: String, school: String) -> bool:
	if school.strip_edges() == "" or String(member).strip_edges() == "":
		return true
	var base: String = resolve_member_mind_base(member)
	if base == "Omega": return true
	var mt: Node = get_node_or_null(MIND_PATH)
	if mt != null and mt.has_method("is_school_allowed"):
		return bool(mt.call("is_school_allowed", base, school))
	return true

func resolve_member_mind_base(member: String) -> String:
	# Hero always has Omega mind type for sigil equipping (allows any sigil)
	# Their "Active type" is only for combat purposes (weaknesses/resistances)
	if member == "hero":
		return "Omega"

	var stats_sys: Node = get_node_or_null("/root/aStatsSystem")
	if stats_sys != null:
		var defs_v: Variant = stats_sys.get("_csv_by_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			var rid: String = String(member)
			if defs.has(rid):
				var row: Dictionary = defs[rid] as Dictionary
				for k in ["mind_type","mind_type_id","mind","mind_base","mind_tag"]:
					if row.has(k):
						var base := String(row[k]).strip_edges()
						if base != "": return base.capitalize()
	var gs: Node = get_node_or_null("/root/aGameState")
	if gs != null and gs.has_method("get_member_field"):
		var mv: Variant = gs.call("get_member_field", member, "mind_type")
		if typeof(mv) == TYPE_STRING and String(mv).strip_edges() != "":
			return String(mv).capitalize()
	return "Omega"

func _school_of_base(base_id: String) -> String:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv != null and inv.has_method("get_item_defs"):
		var dv: Variant = inv.call("get_item_defs")
		if typeof(dv) == TYPE_DICTIONARY:
			var defs: Dictionary = dv
			if defs.has(base_id):
				var rec: Dictionary = defs[base_id]
				for k in ["sigil_school","school","mind_type_tag","mind_type","mind_tag"]:
					if rec.has(k):
						var s: String = String(rec[k]).strip_edges()
						if s != "": return s.capitalize()
	if base_id.begins_with(SIGIL_ID_PREFIX):
		var rest: String = base_id.substr(SIGIL_ID_PREFIX.length())
		var cut: int = rest.find("_")
		var token: String = (rest if cut < 0 else rest.substr(0, cut))
		if token != "": return token.capitalize()
	return ""

func _item_def(id: String) -> Dictionary:
	var inv: Node = get_node_or_null(INV_PATH)
	if inv != null and inv.has_method("get_item_defs"):
		var dv: Variant = inv.call("get_item_defs")
		if typeof(dv) == TYPE_DICTIONARY:
			var defs: Dictionary = dv
			return defs.get(id, {}) as Dictionary
	return {}

func _is_equipped(inst_id: String) -> bool:
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) != TYPE_ARRAY: continue
		for s in (arr_any as Array):
			if String(s) == inst_id: return true
	return false

# You can swap these numbers to match your CSV later.
func _xp_to_next_level(level: int) -> int:
	match level:
		1: return 120
		2: return 240
		3: return 360    # 3 -> 4
		_: return 0      # at MAX or invalid, no progress

# ─────────────────────── CSV loading ───────────────────────
func _load_databases() -> void:
	_skill_name_by_id = {}
	_holder_skills_by_base = {}
	_load_skill_names(PATH_SKILLS)
	_load_holder_map(PATH_HOLDER)

func _load_skill_names(path: String) -> void:
	var rows: Array[PackedStringArray] = _read_csv_rows(path)
	if rows.size() == 0: return
	var header: PackedStringArray = rows[0]
	var idx_id: int = _find_col(header, ["skill_id","id"])
	var idx_name: int = _find_col(header, ["name","display_name","label"])
	if idx_id < 0 or idx_name < 0: return
	for i in range(1, rows.size()):
		var r: PackedStringArray = rows[i]
		if r.size() <= max(idx_id, idx_name): continue
		var sid: String = String(r[idx_id]).strip_edges()
		var nm: String  = String(r[idx_name]).strip_edges()
		if sid != "" and nm != "":
			_skill_name_by_id[sid] = nm

func _load_holder_map(path: String) -> void:
	var rows: Array[PackedStringArray] = _read_csv_rows(path)
	if rows.size() == 0: return
	var header: PackedStringArray = rows[0]
	var idx_sig: int = _find_col(header, ["sigil_id","base_id","sigil"])
	if idx_sig < 0: return
	# accept any columns named lv1..lv99 (we’ll just read in order)
	var lv_cols: Array[int] = []
	for i in range(header.size()):
		var h: String = String(header[i]).strip_edges().to_lower()
		if h.begins_with("lv"):
			lv_cols.append(i)
	lv_cols.sort()
	for i in range(1, rows.size()):
		var r: PackedStringArray = rows[i]
		if r.size() <= idx_sig: continue
		var base_id: String = String(r[idx_sig]).strip_edges()
		if base_id == "": continue
		var arr: Array[String] = []
		for ci in lv_cols:
			if ci < r.size():
				var sid: String = String(r[ci]).strip_edges()
				if sid != "": arr.append(sid)
		_holder_skills_by_base[base_id] = arr

func _find_col(header: PackedStringArray, names: Array[String]) -> int:
	for i in range(header.size()):
		var h: String = String(header[i]).strip_edges().to_lower()
		for n in names:
			if h == n.to_lower():
				return i
	return -1

func _read_csv_rows(path: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	if not FileAccess.file_exists(path):
		return out
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		if out.is_empty() and line.begins_with("\ufeff"):
			line = line.substr(1) # strip BOM
		# NOTE: simple split; your files are plain commas with no quoted commas
		var parts := PackedStringArray()
		for cell in line.split(","):
			parts.append(String(cell).strip_edges())
		# skip empty trailing rows
		var nonempty: bool = false
		for c in parts:
			if String(c) != "":
				nonempty = true; break
		if nonempty:
			out.append(parts)
	return out
# List all owned instance IDs.
# If free_only==true, returns only not-equipped.
func list_all_instances(free_only: bool=false) -> PackedStringArray:
	var out := PackedStringArray()
	var slotted: Dictionary = {}
	if free_only:
		for m in _loadouts.keys():
			var arr_any: Variant = _loadouts[m]
			if typeof(arr_any) == TYPE_ARRAY:
				for s in (arr_any as Array):
					var sid := String(s)
					if sid != "": slotted[sid] = true
	for iid in _owned:
		if free_only and slotted.has(iid):
			continue
		out.append(iid)
	return out

# Who (if anyone) equips this instance.
func who_equips_instance(inst_id: String) -> String:
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) == TYPE_ARRAY:
			for s in (arr_any as Array):
				if String(s) == inst_id:
					return String(m)
	return ""

func list_equipped_instances() -> PackedStringArray:
	var out := PackedStringArray()
	for m in _loadouts.keys():
		var arr_any: Variant = _loadouts[m]
		if typeof(arr_any) != TYPE_ARRAY: continue
		for s in (arr_any as Array):
			var sid := String(s)
			if sid != "" and out.find(sid) < 0:
				out.append(sid)
	return out

# Rich info bundle for UI panels.
func get_instance_info(inst_id: String) -> Dictionary:
	if not _instances.has(inst_id):
		return {}
	var row: Dictionary = _instances[inst_id]
	var base_id := String(row.get("base_id",""))
	var school  := String(row.get("school",""))
	var level   := int(row.get("level",1))
	var xp      := int(row.get("xp",0))
	var active  := String(row.get("active_skill",""))
	var active_name := (get_skill_display_name(active) if active != "" else "")
	var eq_by := who_equips_instance(inst_id)
	return {
		"instance_id": inst_id,
		"base_id": base_id,
		"school": school,
		"level": level,
		"xp": xp,
		"tier": int(row.get("tier",1)),
		"active_skill_id": active,
		"active_skill_name": active_name,
		"equipped": eq_by != "",
		"equipped_by": eq_by
	}
# ─────────────────────── Instance removal API ───────────────────────
func unequip_instance(member: String, inst_id: String) -> bool:
	if not _loadouts.has(member):
		return false
	var sockets_any: Variant = _loadouts[member]
	if typeof(sockets_any) != TYPE_ARRAY:
		return false
	var sockets: Array = sockets_any as Array
	var changed := false
	for i in range(sockets.size()):
		if String(sockets[i]) == inst_id:
			sockets[i] = ""
			changed = true
	if changed:
		_loadouts[member] = sockets
		emit_signal("loadout_changed", member)
	return changed


func delete_instance(inst_id: String) -> void:
	if inst_id.strip_edges() == "":
		return
	# Remove from every member's loadout
	for m_k in _loadouts.keys():
		unequip_instance(String(m_k), inst_id)

	# Remove from owned list
	var new_owned := PackedStringArray()
	for s in _owned:
		if String(s) != inst_id:
			new_owned.append(String(s))
	_owned = new_owned

	# Remove from instance table
	_instances.erase(inst_id)

	# Let UIs refresh
	emit_signal("instances_changed")


# Optional aliases so callers with different names still work
func remove_instance(inst_id: String) -> void: delete_instance(inst_id)
func discard_instance(inst_id: String) -> void: delete_instance(inst_id)
func destroy_instance(inst_id: String) -> void: delete_instance(inst_id)

# (Optional) setters used by some UIs; safe no-ops if you don’t call them.
func set_loadout(member: String, sockets: PackedStringArray) -> void:
	_loadouts[member] = Array(sockets)
	_trim_or_expand_sockets(member)
	emit_signal("loadout_changed", member)

func set_member_loadout(member: String, sockets: PackedStringArray) -> void:
	set_loadout(member, sockets)
