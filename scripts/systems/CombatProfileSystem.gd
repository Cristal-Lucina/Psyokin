extends Node
class_name CombatProfileSystem

# ───────────────────────── Signals ─────────────────────────
signal profiles_changed                    # fired when any profile changed
signal profile_changed                     # fired when a specific member changed (no args)

# ───────────────────────── Autoload paths ─────────────────────────
const GS_PATH: String    = "/root/aGameState"
const STATS_PATH: String = "/root/aStatsSystem"
const EQUIP_PATH: String = "/root/aEquipmentSystem"
const INV_PATH: String   = "/root/aInventorySystem"
const SIG_PATH: String   = "/root/aSigilSystem"
const CSV_PATH: String   = "/root/aCSVLoader"

# Baseline used by your earlier UI math
const DEF_BASELINE: float = 5.0

# Cached outputs
var _profiles: Dictionary = {}         # member_id -> computed profile Dictionary
var _party_meta: Dictionary = {}       # optional current hp/mp/buffs/etc. (from apply_save_blob)

func _ready() -> void:
	var gs: Node = get_node_or_null(GS_PATH)
	var st: Node = get_node_or_null(STATS_PATH)
	var eq: Node = get_node_or_null(EQUIP_PATH)
	var sig: Node = get_node_or_null(SIG_PATH)
	var cal: Node = get_node_or_null("/root/aCalendarSystem")

	# Hook GameState for party changes and loads
	if gs != null:
		for s in ["party_changed", "roster_changed", "perk_points_changed"]:
			if gs.has_signal(s) and not gs.is_connected(s, Callable(self, "_on_gs_changed")):
				gs.connect(s, Callable(self, "_on_gs_changed"))

	# Hook StatsSystem for any stat changes
	if st != null and st.has_signal("stats_changed") and not st.is_connected("stats_changed", Callable(self, "_on_stats_changed")):
		st.connect("stats_changed", Callable(self, "_on_stats_changed"))

	# Hook EquipmentSystem to recompute when gear changes
	if eq != null and eq.has_signal("equipment_changed") and not eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
		eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	# Hook SigilSystem to recompute when loadout changes
	if sig != null and sig.has_signal("loadout_changed") and not sig.is_connected("loadout_changed", Callable(self, "_on_sigils_changed")):
		sig.connect("loadout_changed", Callable(self, "_on_sigils_changed"))

	# Hook CalendarSystem to auto-heal on day advance
	if cal != null and cal.has_signal("day_advanced") and not cal.is_connected("day_advanced", Callable(self, "_on_day_advanced")):
		cal.connect("day_advanced", Callable(self, "_on_day_advanced"))

	# Initial fill
	refresh_all()

# ───────────────────────── Public API ─────────────────────────

func refresh_all() -> void:
	_profiles.clear()
	var ids: Array = _active_party_ids()
	if ids.is_empty():
		ids = ["hero"]
	for id_any in ids:
		var pid: String = String(id_any)
		_profiles[pid] = _compute_for_member(pid)
	emit_signal("profiles_changed")

func refresh_member(member: String) -> void:
	var pid: String = _resolve_id(member)
	_profiles[pid] = _compute_for_member(pid)
	emit_signal("profile_changed")     # ← no args now
	emit_signal("profiles_changed")

func get_profile(member: String) -> Dictionary:
	var pid: String = _resolve_id(member)
	if not _profiles.has(pid):
		_profiles[pid] = _compute_for_member(pid)
	return (_profiles.get(pid, {}) as Dictionary)

## Heals all party members (active and benched) to full HP/MP
## Clears ailments, buffs, and debuffs
func heal_all_to_full() -> void:
	var gs: Node = get_node_or_null(GS_PATH)
	if gs == null:
		return

	# Get all party members (active + benched)
	var all_members: Array[String] = []

	# Get active party
	if gs.has_method("get_active_party_ids"):
		var active_v: Variant = gs.call("get_active_party_ids")
		if typeof(active_v) == TYPE_ARRAY:
			for m in (active_v as Array):
				all_members.append(String(m))
		elif typeof(active_v) == TYPE_PACKED_STRING_ARRAY:
			for m in (active_v as PackedStringArray):
				all_members.append(String(m))

	# Get benched members
	if gs.has_method("get"):
		var bench_v: Variant = gs.get("bench")
		if typeof(bench_v) == TYPE_ARRAY:
			for m in (bench_v as Array):
				var mid := String(m)
				if not all_members.has(mid):
					all_members.append(mid)
		elif typeof(bench_v) == TYPE_PACKED_STRING_ARRAY:
			for m in (bench_v as PackedStringArray):
				var mid := String(m)
				if not all_members.has(mid):
					all_members.append(mid)

	# Heal each member to full
	for member_id in all_members:
		var pid: String = _resolve_id(member_id)
		var pools: Dictionary = _member_pools(pid)
		var hp_max: int = int(pools.get("hp_max", 0))
		var mp_max: int = int(pools.get("mp_max", 0))

		# Also account for equipment bonuses
		var equip: Dictionary = _equip_for(pid)
		var d_head: Dictionary = _item_def(String(equip.get("head","")))
		var hp_bonus: int = int(d_head.get("max_hp_boost", 0))
		var mp_bonus: int = int(d_head.get("max_mp_boost", 0))

		var true_hp_max: int = hp_max + hp_bonus
		var true_mp_max: int = mp_max + mp_bonus

		# Update _party_meta
		if not _party_meta.has(pid):
			_party_meta[pid] = {}
		var meta: Dictionary = _party_meta[pid]
		meta["hp"] = true_hp_max
		meta["mp"] = true_mp_max
		meta["ailment"] = ""
		meta["buffs"] = []
		meta["debuffs"] = []
		_party_meta[pid] = meta

		# Update GameState.member_data for persistence
		if gs.has_method("get"):
			var member_data_v: Variant = gs.get("member_data")
			if typeof(member_data_v) == TYPE_DICTIONARY:
				var member_data: Dictionary = member_data_v
				if not member_data.has(pid):
					member_data[pid] = {}
				var gs_rec: Dictionary = member_data[pid]
				gs_rec["hp"] = true_hp_max
				gs_rec["mp"] = true_mp_max
				gs_rec["buffs"] = []
				gs_rec["debuffs"] = []
				member_data[pid] = gs_rec
				# Set it back to GameState
				if gs.has_method("set"):
					gs.set("member_data", member_data)

	# Refresh all profiles to show updated HP/MP
	refresh_all()
	print("[CombatProfileSystem] Healed all party members to full HP/MP")

# Optional: accept runtime HP/MP/buffs from save blobs
func apply_save_blob(blob: Dictionary) -> void:
	# expected format (used by your GameState loader):
	# { "party": { "<id>": {"hp":int,"mp":int,"ailment":String,"flags":{}, "buffs":[], "debuffs":[]} }, "enemies":{} }
	if blob.has("party"):
		var p: Variant = blob["party"]
		if typeof(p) == TYPE_DICTIONARY:
			_party_meta = (p as Dictionary).duplicate(true)
	refresh_all()

# ───────────────────────── Signals → Refresh ─────────────────────────

func _on_gs_changed(_a: Variant = null) -> void:
	refresh_all()

func _on_stats_changed() -> void:
	refresh_all()

func _on_equipment_changed(member: String) -> void:
	refresh_member(member)

func _on_sigils_changed(member: String) -> void:
	refresh_member(member)

func _on_day_advanced(_new_date: Dictionary) -> void:
	# Auto-heal all party members at the start of each new day
	heal_all_to_full()

# ───────────────────────── Core compute ─────────────────────────

func _compute_for_member(member: String) -> Dictionary:
	var pid: String = _resolve_id(member)

	# Name/label
	var label: String = _display_name(pid)

	# Pools/level from GameState (falls back to StatsSystem if needed)
	var pools: Dictionary = _member_pools(pid)
	var lvl: int   = int(pools.get("level", 1))
	var hp_max: int = int(pools.get("hp_max", 0))
	var mp_max: int = int(pools.get("mp_max", 0))

	# Current runtime state - check multiple sources for HP/MP persistence
	var cur_hp: int = hp_max
	var cur_mp: int = mp_max
	var ailment: String = ""
	var buffs: Array = []
	var debuffs: Array = []
	var flags: Dictionary = {}

	# Priority 1: GameState.member_data (for HP/MP persistence during gameplay)
	# This takes priority because it's updated after every battle
	var gs: Node = get_node_or_null(GS_PATH)
	var found_in_member_data = false
	if gs and gs.has_method("get"):
		if "member_data" in gs:
			var member_data_v: Variant = gs.get("member_data")
			if typeof(member_data_v) == TYPE_DICTIONARY:
				var member_data: Dictionary = member_data_v
				if member_data.has(pid):
					var gs_rec: Dictionary = member_data[pid]
					cur_hp = int(gs_rec.get("hp", hp_max))
					cur_mp = int(gs_rec.get("mp", mp_max))
					buffs = (gs_rec.get("buffs", []) as Array).duplicate()
					debuffs = (gs_rec.get("debuffs", []) as Array).duplicate()
					found_in_member_data = true
					print("[CombatProfileSystem] %s: Using GameState.member_data HP=%d/%d, MP=%d/%d" % [pid, cur_hp, hp_max, cur_mp, mp_max])

	# Priority 2: _party_meta (populated from apply_save_blob during load)
	# Only use this if member_data didn't have the data (e.g., fresh load from save)
	if not found_in_member_data and _party_meta.has(pid):
		var rec: Dictionary = _party_meta[pid]
		cur_hp = int(rec.get("hp", hp_max))
		cur_mp = int(rec.get("mp", mp_max))
		ailment = String(rec.get("ailment", ""))
		buffs = (rec.get("buffs", []) as Array).duplicate()
		debuffs = (rec.get("debuffs", []) as Array).duplicate()
		flags = (rec.get("flags", {}) as Dictionary).duplicate(true)
		print("[CombatProfileSystem] %s: Using _party_meta HP=%d/%d, MP=%d/%d" % [pid, cur_hp, hp_max, cur_mp, mp_max])
	elif not found_in_member_data:
		print("[CombatProfileSystem] %s: No saved data found, using defaults HP=%d/%d, MP=%d/%d" % [pid, cur_hp, hp_max, cur_mp, mp_max])

	# Base stats
	var brw: int = _stat_for(pid, "BRW")
	var vtl: int = _stat_for(pid, "VTL")
	var fcs: int = _stat_for(pid, "FCS")

	# Gear/equip
	var equip: Dictionary = _equip_for(pid)
	var d_wea: Dictionary  = _item_def(String(equip.get("weapon","")))
	var d_arm: Dictionary  = _item_def(String(equip.get("armor","")))
	var d_head: Dictionary = _item_def(String(equip.get("head","")))
	var d_foot: Dictionary = _item_def(String(equip.get("foot","")))
	var d_brac: Dictionary = _item_def(String(equip.get("bracelet","")))

	# Derived: weapon
	var base_watk: int   = int(d_wea.get("base_watk", 0))
	var scale_brw: float = float(d_wea.get("scale_brw", 0.0))
	var weapon_attack: int = base_watk + int(round(scale_brw * float(brw)))
	var weapon_acc: int  = int(d_wea.get("base_acc", 0))
	var skill_acc_boost: int = int(d_wea.get("skill_acc_boost", 0))
	var crit_bonus: int  = int(d_wea.get("crit_bonus_pct", 0))
	var type_raw: String = String(d_wea.get("watk_type_tag","")).strip_edges().to_lower()
	var weapon_type: String = "Neutral"
	if type_raw != "" and type_raw != "wand":
		weapon_type = type_raw.capitalize()
	var special: String = ""
	if _as_bool(d_wea.get("non_lethal", false)):
		special = "NL"

	# Derived: defenses
	var armor_flat: int = int(d_arm.get("armor_flat", 0))
	var pdef: int = int(round(float(armor_flat) * (DEF_BASELINE + 0.25 * float(vtl))))
	var ail_res: int = int(d_arm.get("ail_resist_pct", 0))

	var ward_flat: int = int(d_head.get("ward_flat", 0))
	var mdef: int = int(round(float(ward_flat) * (DEF_BASELINE + 0.25 * float(fcs))))
	var hp_bonus: int = int(d_head.get("max_hp_boost", 0))
	var mp_bonus: int = int(d_head.get("max_mp_boost", 0))

	# EVA from foot + mods from other gear base_eva
	var base_eva: int = int(d_foot.get("base_eva", 0))
	var eva_mods: int = _eva_mods_from_other(equip, String(equip.get("foot","")))
	var peva: int = base_eva + int(round(0.25 * float(vtl))) + eva_mods
	var meva: int = base_eva + int(round(0.25 * float(fcs))) + eva_mods
	var speed: int = int(d_foot.get("speed", 0))

	# Sigils / bracelet
	var slots: int = int(d_brac.get("sigil_slots", 0))
	var active_sigil_name: String = _active_sigil_display(pid)
	var loadout: Array = _sigil_loadout(pid)

	# Mind info
	var mind_base: String = _member_mind_base(pid)
	var mind_active: String = _hero_active_type_if_hero(pid, mind_base)

	# Optional set bonus hook (leave empty for now)
	var set_bonus: String = ""

	# Pretty item names
	var weapon_name: String   = _pretty_item(String(equip.get("weapon","")))
	var armor_name: String    = _pretty_item(String(equip.get("armor","")))
	var head_name: String     = _pretty_item(String(equip.get("head","")))
	var foot_name: String     = _pretty_item(String(equip.get("foot","")))
	var bracelet_name: String = _pretty_item(String(equip.get("bracelet","")))

	# Build profile dictionary
	var prof: Dictionary = {
		"member": pid,
		"label": label,
		"level": lvl,
		"hp_max": hp_max + hp_bonus,
		"mp_max": mp_max + mp_bonus,
		"hp": cur_hp,
		"mp": cur_mp,
		"ailment": ailment,
		"buffs": buffs,
		"debuffs": debuffs,
		"flags": flags,
		"stats": {"BRW": brw, "VTL": vtl, "FCS": fcs},
		"weapon": {
			"id": String(equip.get("weapon","")),
			"name": weapon_name,
			"attack": weapon_attack,
			"scale_brw": scale_brw,
			"accuracy": weapon_acc,
			"skill_acc_boost": skill_acc_boost,
			"crit_bonus_pct": crit_bonus,
			"type": weapon_type,
			"special": special
		},
		"defense": {
			"pdef": pdef,
			"mdef": mdef,
			"ail_resist_pct": ail_res,
			"peva": peva,
			"meva": meva,
			"speed": speed
		},
		"bracelet": {
			"id": String(equip.get("bracelet","")),
			"name": bracelet_name,
			"sigil_slots": slots,
			"active_sigil": active_sigil_name
		},
		"equipment_names": {
			"weapon": weapon_name,
			"armor": armor_name,
			"head": head_name,
			"foot": foot_name,
			"bracelet": bracelet_name
		},
		"mind": {"base": mind_base, "active": mind_active},
		"set_bonus": set_bonus,
		"sigils": {
			"loadout": loadout
		}
	}

	return prof

# ───────────────────────── Helpers ─────────────────────────
func _as_bool(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL:   return v
		TYPE_INT:    return int(v) != 0
		TYPE_FLOAT:  return float(v) != 0.0
		TYPE_STRING:
			var s := String(v).strip_edges().to_lower()
			return s in ["true","1","yes","y","on","t"]
		_:           return false

func _resolve_id(name_in: String) -> String:
	var gs: Node = get_node_or_null(GS_PATH)
	var want: String = String(name_in).strip_edges().to_lower()
	if gs != null:
		var pn_v: Variant = gs.get("player_name")
		if typeof(pn_v) == TYPE_STRING and String(pn_v).strip_edges().to_lower() == want:
			return "hero"
	return name_in

func _active_party_ids() -> Array:
	var gs: Node = get_node_or_null(GS_PATH)
	if gs != null and gs.has_method("get_active_party_ids"):
		var v: Variant = gs.call("get_active_party_ids")
		if typeof(v) == TYPE_ARRAY:
			return v as Array
	return ["hero"]

func _display_name(id: String) -> String:
	var gs: Node = get_node_or_null(GS_PATH)
	if gs != null and gs.has_method("get_party_names"):
		var ids: Array = _active_party_ids()
		for i in range(ids.size()):
			if String(ids[i]) == id:
				var names: PackedStringArray = gs.call("get_party_names")
				if i >= 0 and i < names.size():
					return String(names[i])
	# Fallback
	if id == "hero":
		if gs != null:
			var nm_v: Variant = gs.get("player_name")
			if typeof(nm_v) == TYPE_STRING and String(nm_v).strip_edges() != "":
				return String(nm_v)
		return "Player"
	return id.capitalize()

func _member_pools(member: String) -> Dictionary:
	var gs: Node = get_node_or_null(GS_PATH)
	if gs != null and gs.has_method("compute_member_pools"):
		var v: Variant = gs.call("compute_member_pools", member)
		if typeof(v) == TYPE_DICTIONARY:
			return v as Dictionary
	# Fallback: rough calc if GS missing
	var st: Node = get_node_or_null(STATS_PATH)
	var lvl: int = _member_level(member)
	var vtl: int = _stat_for(member, "VTL")
	var fcs: int = _stat_for(member, "FCS")
	var hp_max: int = 60 + (max(1, vtl) * max(1, lvl) * 6)
	var mp_max: int = 20 + int(round(float(max(1, fcs)) * float(max(1, lvl)) * 1.5))
	if st != null and st.has_method("compute_max_hp"):
		hp_max = int(st.call("compute_max_hp", lvl, vtl))
	if st != null and st.has_method("compute_max_mp"):
		mp_max = int(st.call("compute_max_mp", lvl, fcs))
	return {"level": lvl, "hp_max": hp_max, "mp_max": mp_max}

func _member_level(member: String) -> int:
	var st: Node = get_node_or_null(STATS_PATH)
	if st != null and st.has_method("get_member_level"):
		var v: Variant = st.call("get_member_level", member)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
	return 1

func _stat_for(member: String, stat: String) -> int:
	var st: Node = get_node_or_null(STATS_PATH)
	if st != null and st.has_method("get_member_stat_level"):
		var v: Variant = st.call("get_member_stat_level", member, stat)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
	return 1

func _equip_for(member: String) -> Dictionary:
	var eq: Node = get_node_or_null(EQUIP_PATH)
	if eq != null and eq.has_method("get_member_equip"):
		var d_v: Variant = eq.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			# normalize key "feet" -> "foot"
			if d.has("feet") and not d.has("foot"):
				d["foot"] = String(d["feet"])
			for k in ["weapon","armor","head","foot","bracelet"]:
				if not d.has(k):
					d[k] = ""
			return d
	return {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

func _item_def(id: String) -> Dictionary:
	if id == "" or id == "—":
		return {}
	var eq: Node = get_node_or_null(EQUIP_PATH)
	if eq != null and eq.has_method("get_item_def"):
		var v: Variant = eq.call("get_item_def", id)
		if typeof(v) == TYPE_DICTIONARY:
			return v as Dictionary
	var inv: Node = get_node_or_null(INV_PATH)
	if inv != null and inv.has_method("get_item_defs"):
		var d: Variant = inv.call("get_item_defs")
		if typeof(d) == TYPE_DICTIONARY:
			var defs: Dictionary = d
			return defs.get(id, {}) as Dictionary
	return {}

func _pretty_item(id: String) -> String:
	if id == "" or id == "—":
		return "—"
	var eq: Node = get_node_or_null(EQUIP_PATH)
	if eq != null and eq.has_method("get_item_display_name"):
		var v: Variant = eq.call("get_item_display_name", id)
		if typeof(v) == TYPE_STRING:
			return String(v)
	return id

func _eva_mods_from_other(equip: Dictionary, exclude_id: String) -> int:
	var sum: int = 0
	for k in ["weapon","armor","head","bracelet"]:
		var id: String = String(equip.get(k,""))
		if id == "" or id == exclude_id:
			continue
		var d: Dictionary = _item_def(id)
		if d.has("base_eva"):
			sum += int(d.get("base_eva",0))
	return sum

func _sigil_loadout(member: String) -> Array:
	var sig: Node = get_node_or_null(SIG_PATH)
	if sig != null and sig.has_method("get_loadout"):
		var v: Variant = sig.call("get_loadout", member)
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			return Array(v)
		if typeof(v) == TYPE_ARRAY:
			return v as Array
	return []

func _active_sigil_display(member: String) -> String:
	var sig: Node = get_node_or_null(SIG_PATH)
	var arr: Array = _sigil_loadout(member)
	if arr.size() == 0:
		return ""
	var first: String = String(arr[0])
	if first == "":
		return ""
	if sig != null and sig.has_method("get_display_name_for"):
		var dn: Variant = sig.call("get_display_name_for", first)
		if typeof(dn) == TYPE_STRING:
			return String(dn)
	return first

func _member_mind_base(member: String) -> String:
	# Prefer SigilSystem’s resolver if present
	var sig: Node = get_node_or_null(SIG_PATH)
	if sig != null and sig.has_method("resolve_member_mind_base"):
		var v: Variant = sig.call("resolve_member_mind_base", member)
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v).capitalize()

	# Fallback to GameState
	var gs: Node = get_node_or_null(GS_PATH)
	if gs != null and gs.has_method("get_member_field"):
		var mv: Variant = gs.call("get_member_field", member, "mind_type")
		if typeof(mv) == TYPE_STRING and String(mv).strip_edges() != "":
			return String(mv).capitalize()

	return "Omega"

func _hero_active_type_if_hero(member: String, mind_base: String) -> String:
	if member != "hero":
		return mind_base
	var gs: Node = get_node_or_null(GS_PATH)
	if gs != null:
		if gs.has_meta("hero_active_type"):
			var mv: Variant = gs.get_meta("hero_active_type")
			if typeof(mv) == TYPE_STRING and String(mv).strip_edges() != "":
				return String(mv)
		var v: Variant = gs.get("hero_active_type")
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	return mind_base
