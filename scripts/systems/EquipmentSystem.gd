extends Node
class_name EquipmentSystem

signal equipment_changed(member: String)

const SLOT_KEYS = ["weapon","armor","head","foot","bracelet"]
const DEF_BASELINE := 1.0  # used in PDEF/MDEF: BASELINE + 0.25×stat

var _equip: Dictionary = {}  # member -> {weapon,armor,head,foot,bracelet}

# ───────────────────────────── Public API ─────────────────────────────

func get_member_equip(member: String) -> Dictionary:
	_ensure_member(member)
	return (_equip[member] as Dictionary).duplicate(true)

func equip_item(member: String, item_id: String) -> String:
	var slot: String = _slot_of(item_id)
	if slot == "":
		return ""
	_ensure_member(member)
	var m: Dictionary = _equip[member]
	m[slot] = item_id
	_equip[member] = m
	equipment_changed.emit(member)
	return slot

func unequip_slot(member: String, slot: String) -> void:
	_ensure_member(member)
	if not SLOT_KEYS.has(slot):
		return
	var m: Dictionary = _equip[member]
	m[slot] = ""
	_equip[member] = m
	equipment_changed.emit(member)

func list_equippable(_member: String, slot: String) -> PackedStringArray:
	var out_ids: Array[String] = []
	var counts: Dictionary = _get_inventory_counts()
	var defs: Dictionary = _get_inventory_defs()
	for id_v in counts.keys():
		var id: String = String(id_v)
		if int(counts[id_v]) <= 0:
			continue
		var def: Dictionary = defs.get(id, {}) as Dictionary
		var s: String = _slot_from_def(def)
		if s == "":
			s = _slot_from_free_text(id)
		if s == slot:
			out_ids.append(id)
	out_ids.sort_custom(Callable(self, "_cmp_ids_by_name"))
	var packed: PackedStringArray = PackedStringArray()
	for e in out_ids: packed.append(String(e))
	return packed

func get_item_display_name(item_id: String) -> String:
	var defs: Dictionary = _get_inventory_defs()
	if not defs.is_empty():
		var def: Dictionary = defs.get(item_id, {}) as Dictionary
		if not def.is_empty():
			for k in ["name","display_name","label","title"]:
				if def.has(k):
					var s: String = String(def[k]).strip_edges()
					if s != "":
						return s
	return String(item_id).replace("_"," ").capitalize()

# ─────────────────────── Save hooks ───────────────────────

func clear_all() -> void:
	_equip.clear()

func get_save_blob() -> Dictionary:
	var out: Dictionary = {}
	for m_v in _equip.keys():
		var mkey: String = String(m_v)
		var md: Dictionary = _equip[mkey]
		var rec: Dictionary = {
			"weapon":   String(md.get("weapon","")),
			"armor":    String(md.get("armor","")),
			"head":     String(md.get("head","")),
			"foot":     String(md.get("foot","")),
			"bracelet": String(md.get("bracelet","")),
		}
		out[mkey] = rec
	return {"equip": out, "v": 1}

func apply_save_blob(blob: Dictionary) -> void:
	_equip.clear()
	var root_v: Variant = blob.get("equip", {})
	if root_v is Dictionary:
		var root: Dictionary = root_v
		for m_v in root.keys():
			var mkey: String = String(m_v)
			var rec: Dictionary = {"weapon":"","armor":"","head":"","foot":"","bracelet":""}
			var src_v: Variant = root.get(m_v)
			if src_v is Dictionary:
				var d: Dictionary = src_v
				for k in SLOT_KEYS:
					rec[k] = String(d.get(k, ""))
				if String(d.get("feet","")) != "" and String(rec["foot"]) == "":
					rec["foot"] = String(d.get("feet",""))
			_equip[mkey] = rec
	for m2_v in _equip.keys():
		call_deferred("_emit_equipment_changed_safe", String(m2_v))

func _emit_equipment_changed_safe(member: String) -> void:
	if is_inside_tree():
		equipment_changed.emit(member)

# ───────────── Item defs & generic mods ──────────

func get_item_def(item_id: String) -> Dictionary:
	if item_id == "" or item_id == "—":
		return {}
	var defs: Dictionary = _get_inventory_defs()
	return defs.get(item_id, {}) as Dictionary

func get_item_mods(item_id: String) -> Dictionary:
	var def: Dictionary = get_item_def(item_id)
	if def.is_empty():
		return {}
	var out: Dictionary = {}
	if def.has("max_hp_boost"): out["max_hp"] = int(def["max_hp_boost"])
	if def.has("max_mp_boost"): out["max_mp"] = int(def["max_mp_boost"])
	if def.has("base_acc"):     out["base_acc"] = int(def["base_acc"])
	if def.has("base_eva"):     out["base_eva"] = int(def["base_eva"])
	if def.has("base_watk"):      out["watk_base"] = int(def["base_watk"])
	if def.has("scale_brw"):      out["watk_scale_brw"] = float(def["scale_brw"])
	if def.has("watk_type_tag"):  out["watk_type"] = String(def["watk_type_tag"])
	if def.has("mind_type_resists"): out["resist_mind"] = bool(def["mind_type_resists"])
	for k_v in def.keys():
		var ks: String = String(k_v)
		if ks.ends_with("_boost"):
			var v_any: Variant = def[k_v]
			if typeof(v_any) == TYPE_INT or typeof(v_any) == TYPE_FLOAT:
				if ks != "max_hp_boost" and ks != "max_mp_boost":
					out[ks] = int(v_any)
	return out

func get_member_total_mods(member: String) -> Dictionary:
	var equip: Dictionary = get_member_equip(member)
	var total: Dictionary = {}
	for k in ["weapon","armor","head","foot","bracelet"]:
		var id: String = String(equip.get(k, ""))
		if id == "" or id == "—":
			continue
		var m: Dictionary = get_item_mods(id)
		for mk_v in m.keys():
			var mk: String = String(mk_v)
			var val: Variant = m[mk_v]
			if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
				total[mk] = int(total.get(mk, 0)) + int(val)
			elif typeof(val) == TYPE_BOOL:
				total[mk] = bool(total.get(mk, false)) or bool(val)
			else:
				if not total.has(mk):
					total[mk] = val
	return total

func get_member_effective_watk(member: String) -> Dictionary:
	var mods: Dictionary = get_member_total_mods(member)
	if not (mods.has("watk_base") or mods.has("watk_scale_brw")):
		return {}
	var base: int = int(mods.get("watk_base", 0))
	var scale: float = float(mods.get("watk_scale_brw", 0.0))
	var brw: int = _get_stat("BRW")
	var watk: int = base + int(round(scale * float(brw)))
	return {"watk": watk, "explain": "WATK = %d + %.1f×BRW(%d) = %d" % [base, scale, brw, watk]}

func summarize_member_mods(member: String) -> String:
	var m: Dictionary = get_member_total_mods(member)
	if m.is_empty(): return ""
	var parts: Array[String] = []
	if m.has("max_hp"): parts.append("HP +%d" % int(m["max_hp"]))
	if m.has("max_mp"): parts.append("MP +%d" % int(m["max_mp"]))
	var w: Dictionary = get_member_effective_watk(member)
	if not w.is_empty(): parts.append(String(w["explain"]))
	if m.has("base_acc"): parts.append("ACC +%d" % int(m["base_acc"]))
	if m.has("base_eva"): parts.append("EVA +%d" % int(m["base_eva"]))
	if m.get("resist_mind", false): parts.append("Resists MIND")
	return ", ".join(parts)

# ─────────────── Slot-specific summaries ───────────────

func summarize_slot(member: String, slot: String, item_id: String) -> String:
	if item_id == "" or item_id == "—":
		return ""
	match slot:
		"weapon":   return _sum_weapon(member, item_id)
		"armor":    return _sum_armor(member, item_id)
		"head":     return _sum_head(member, item_id)
		"foot":     return _sum_foot(member, item_id)
		"bracelet": return _sum_bracelet(member, item_id)
		_:          return ""

func _sum_weapon(_member: String, item_id: String) -> String:
	var d: Dictionary = get_item_def(item_id)
	var base: int    = int(d.get("base_watk", 0))
	var scale: float = float(d.get("scale_brw", 0.0))
	var brw: int     = _get_stat("BRW")
	var eff: int     = base + int(round(scale * float(brw)))
	var wacc: int    = int(d.get("base_acc", 0))
	var sboost: int  = int(d.get("skill_acc_boost", 0))
	var crit: int    = int(d.get("crit_bonus_pct", 0))

	var typ_raw: String = String(d.get("watk_type_tag", "")).strip_edges().to_lower()
	var typ_title: String = ("Neutral" if typ_raw == "" else typ_raw.capitalize())
	var typ_note: String = ""
	match typ_raw:
		"slash":  typ_note = " (strong vs Impact, weak vs Pierce)"
		"impact": typ_note = " (strong vs Pierce, weak vs Slash)"
		"pierce": typ_note = " (strong vs Slash, weak vs Impact)"
		"wand":   typ_note = " (neutral)"
		_:        typ_note = ""

	var special: String = ("NL (non_lethal)" if bool(d.get("non_lethal", false)) else "—")

	var lines: Array[String] = []
	lines.append("Weapon Attack = %d" % eff)
	lines.append("Scale = %.1f" % scale)
	lines.append("Weapon Accuracy = %d" % wacc)
	lines.append("Skill Accuracy Boost = %d" % sboost)
	lines.append("Crit Bonus = %d" % crit)
	lines.append("Type = %s%s" % [typ_title, typ_note])
	lines.append("Special = %s" % special)
	return "\n".join(lines)

func _sum_armor(_member: String, item_id: String) -> String:
	var d: Dictionary = get_item_def(item_id)
	var flat: int = int(d.get("armor_flat", 0))
	var vtl: int  = _get_stat("VTL")
	var pdef: int = int(round(float(flat) * (DEF_BASELINE + 0.25 * float(vtl))))
	var ail: int  = int(d.get("ail_resist_pct", 0))
	var lines: Array[String] = []
	lines.append("Physical Defence = %d  (ArmorFlat %d × (%.1f + 0.25×VTL %d))" % [pdef, flat, DEF_BASELINE, vtl])
	lines.append("Ailment Resistance = %d" % ail)
	return "\n".join(lines)

func _sum_head(_member: String, item_id: String) -> String:
	var d: Dictionary = get_item_def(item_id)
	var hp: int   = int(d.get("max_hp_boost", 0))
	var mp: int   = int(d.get("max_mp_boost", 0))
	var ward: int = int(d.get("ward_flat", 0))
	var fcs: int  = _get_stat("FCS")
	var mdef: int = int(round(float(ward) * (DEF_BASELINE + 0.25 * float(fcs))))
	var lines: Array[String] = []
	lines.append("HP Bonus = %d" % hp)
	lines.append("MP Bonus = %d" % mp)
	lines.append("Mind Defence = %d  (WardFlat %d × (%.1f + 0.25×FCS %d))" % [mdef, ward, DEF_BASELINE, fcs])
	return "\n".join(lines)

func _sum_foot(member: String, item_id: String) -> String:
	var d: Dictionary = get_item_def(item_id)
	var base_eva: int = int(d.get("base_eva", 0))
	var vtl: int = _get_stat("VTL")
	var fcs: int = _get_stat("FCS")
	var mods: int = _eva_mods_from_other_gear(member, item_id)
	var peva: int = base_eva + int(round(0.25 * float(vtl))) + mods
	var meva: int = base_eva + int(round(0.25 * float(fcs))) + mods
	var spd: int  = int(d.get("speed", 0))
	var lines: Array[String] = []
	lines.append("Physical Evasion = %d%%  (base %d + 0.25·VTL %d + mods %d)" % [peva, base_eva, int(round(0.25*float(vtl))), mods])
	lines.append("Mind Evasion = %d%%  (base %d + 0.25·FCS %d + mods %d)" % [meva, base_eva, int(round(0.25*float(fcs))), mods])
	lines.append("Speed = %d" % spd)
	return "\n".join(lines)

func _sum_bracelet(member: String, item_id: String) -> String:
	var d: Dictionary = get_item_def(item_id)
	var slots: int = int(d.get("sigil_slots", 0))
	var active: String = "—"
	var sig: Node = get_node_or_null("/root/aSigilSystem")
	if sig and sig.has_method("get_loadout"):
		var v: Variant = sig.call("get_loadout", member)
		var arr: Array = []
		if typeof(v) == TYPE_PACKED_STRING_ARRAY: arr = Array(v)
		elif typeof(v) == TYPE_ARRAY: arr = v
		if arr.size() > 0 and String(arr[0]) != "":
			var sid: String = String(arr[0])
			if sig.has_method("get_display_name_for"):
				var dn: Variant = sig.call("get_display_name_for", sid)
				active = (String(dn) if typeof(dn) == TYPE_STRING else sid)
			else:
				active = sid
	var lines: Array[String] = []
	lines.append("Slots = %d" % slots)
	lines.append("Active Sigil = %s" % active)
	return "\n".join(lines)

# ───────────────────────────── Internals ─────────────────────────────

func _ensure_member(member: String) -> void:
	if not _equip.has(member):
		_equip[member] = {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

func _cmp_ids_by_name(a: Variant, b: Variant) -> bool:
	return get_item_display_name(String(a)) < get_item_display_name(String(b))

func _slot_of(item_id: String) -> String:
	var defs: Dictionary = _get_inventory_defs()
	var def: Dictionary = defs.get(item_id, {}) as Dictionary
	var s: String = _slot_from_def(def)
	if s != "":
		return s
	return _slot_from_free_text(item_id)

func _slot_from_def(def: Dictionary) -> String:
	if def.is_empty(): return ""
	for k in ["slot","equip_slot","equip","equip_to"]:
		if def.has(k):
			var s: String = _normalize_slot(String(def[k]))
			if s != "": return s
	for kc in ["category","cat","type"]:
		if def.has(kc):
			var s2: String = _normalize_slot(String(def[kc]))
			if s2 != "": return s2
	return ""

func _slot_from_free_text(txt: String) -> String:
	return _normalize_slot(txt)

func _normalize_slot(s: String) -> String:
	var t: String = s.strip_edges().to_lower()
	match t:
		"weapon","weapons": return "weapon"
		"armor": return "armor"
		"head","headwear","helm","helmet": return "head"
		"foot","feet","footwear","boots","shoes": return "foot"
		"bracelet","bracelets","bangle": return "bracelet"
		_: return ""

func _get_inventory_defs() -> Dictionary:
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv and inv.has_method("get_item_defs"):
		var v_defs: Variant = inv.call("get_item_defs")
		if v_defs is Dictionary:
			return (v_defs as Dictionary).duplicate(true)
	return {}

func _get_inventory_counts() -> Dictionary:
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv and inv.has_method("get_counts_dict"):
		var v_counts: Variant = inv.call("get_counts_dict")
		if v_counts is Dictionary:
			return (v_counts as Dictionary).duplicate(true)
	return {}

func _get_stat(stat: String) -> int:
	var stats: Node = get_node_or_null("/root/aStatsSystem")
	if stats and stats.has_method("get_stat"):
		var v: Variant = stats.call("get_stat", stat)
		if typeof(v) == TYPE_INT:
			return int(v)
	return 0

func _eva_mods_from_other_gear(member: String, foot_item_id: String) -> int:
	var equip: Dictionary = get_member_equip(member)
	var sum: int = 0
	for k in ["weapon","armor","head","bracelet"]:
		var id: String = String(equip.get(k,""))
		if id == "" or id == foot_item_id: continue
		var d: Dictionary = get_item_def(id)
		if d.has("base_eva"):
			sum += int(d.get("base_eva",0))
	return sum
