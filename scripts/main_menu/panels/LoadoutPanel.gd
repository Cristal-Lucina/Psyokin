extends Control
class_name LoadoutPanel

@onready var _party_list  : ItemList      = get_node("Row/Party/PartyList") as ItemList
@onready var _member_name : Label         = get_node("Row/Right/MemberName") as Label

@onready var _w_val : Label = get_node("Row/Right/Grid/WValue") as Label
@onready var _a_val : Label = get_node("Row/Right/Grid/AValue") as Label
@onready var _h_val : Label = get_node("Row/Right/Grid/HValue") as Label
@onready var _f_val : Label = get_node("Row/Right/Grid/FValue") as Label
@onready var _b_val : Label = get_node("Row/Right/Grid/BValue") as Label

@onready var _w_btn : Button = get_node_or_null("Row/Right/Grid/WBtn") as Button
@onready var _a_btn : Button = get_node_or_null("Row/Right/Grid/ABtn") as Button
@onready var _h_btn : Button = get_node_or_null("Row/Right/Grid/HBtn") as Button
@onready var _f_btn : Button = get_node_or_null("Row/Right/Grid/FBtn") as Button
@onready var _b_btn : Button = get_node_or_null("Row/Right/Grid/BBtn") as Button

@onready var _sigils_title : Label         = get_node_or_null("Row/Right/Sigils/Title") as Label
@onready var _sigils_list  : VBoxContainer = get_node_or_null("Row/Right/Sigils/List") as VBoxContainer
@onready var _btn_manage   : Button        = get_node_or_null("Row/Right/Buttons/BtnManageSigils") as Button

# NEW: grid lives in the scene
@onready var _stats_grid : GridContainer = get_node("Row/Right/StatsGrid") as GridContainer

var _names: PackedStringArray = []
var _gs  : Node = null
var _inv : Node = null
var _sig : Node = null
var _eq  : Node = null
var _stats : Node = null

const _SLOTS = ["weapon","armor","head","foot","bracelet"]
const _DEF_BASELINE := 5.0
const STATS_FONT_SIZE := 9  # drop this to 12, 11, etc. to make it smaller


func _ready() -> void:
	_gs   = get_node_or_null("/root/aGameState")
	_inv  = get_node_or_null("/root/aInventorySystem")
	_sig  = get_node_or_null("/root/aSigilSystem")
	_eq   = get_node_or_null("/root/aEquipmentSystem")
	_stats = get_node_or_null("/root/aStatsSystem")

	if _w_btn: _w_btn.pressed.connect(_on_slot_button.bind("weapon"))
	if _a_btn: _a_btn.pressed.connect(_on_slot_button.bind("armor"))
	if _h_btn: _h_btn.pressed.connect(_on_slot_button.bind("head"))
	if _f_btn: _f_btn.pressed.connect(_on_slot_button.bind("foot"))
	if _b_btn: _b_btn.pressed.connect(_on_slot_button.bind("bracelet"))

	if not _party_list.item_selected.is_connected(_on_party_selected):
		_party_list.item_selected.connect(_on_party_selected)

	if _btn_manage and not _btn_manage.pressed.is_connected(_on_manage_sigils):
		_btn_manage.pressed.connect(_on_manage_sigils)

	if _eq and _eq.has_signal("equipment_changed"):
		if not _eq.is_connected("equipment_changed", Callable(self, "_on_equipment_changed")):
			_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))
	if _sig and _sig.has_signal("loadout_changed"):
		if not _sig.is_connected("loadout_changed", Callable(self, "_on_sigils_changed")):
			_sig.connect("loadout_changed", Callable(self, "_on_sigils_changed"))

	_refresh_party()
	if _names.size() > 0:
		_party_list.select(0)
		_on_party_selected(0)

# ───────────────────────── Party list ─────────────────────────

func _refresh_party() -> void:
	_party_list.clear()
	_names.clear()
	if _gs and _gs.has_method("get_party_names"):
		var arr_v: Variant = _gs.call("get_party_names")
		if typeof(arr_v) == TYPE_ARRAY:
			for n in (arr_v as Array):
				_names.append(String(n))
	if _names.is_empty():
		var hs := get_node_or_null("/root/aHeroSystem")
		if hs and hs.has_method("get"):
			var hn: Variant = hs.get("hero_name")
			if typeof(hn) == TYPE_STRING and String(hn) != "":
				_names.append(String(hn))
	if _names.is_empty():
		_names = PackedStringArray(["(No party data)"])
	for nm in _names:
		_party_list.add_item(nm)

func _on_party_selected(index: int) -> void:
	var sel := "(Unknown)"
	if index >= 0 and index < _names.size():
		sel = _names[index]
	_member_name.text = sel
	var equip := _fetch_equip_for(sel)

	_w_val.text = _pretty_item(String(equip.get("weapon","")))
	_a_val.text = _pretty_item(String(equip.get("armor","")))
	_h_val.text = _pretty_item(String(equip.get("head","")))
	_f_val.text = _pretty_item(String(equip.get("foot","")))
	_b_val.text = _pretty_item(String(equip.get("bracelet","")))

	_rebuild_stats_grid(sel, equip)
	_rebuild_sigils(sel)

# ──────────────────────── Equip flow ─────────────────────────

func _on_slot_button(slot: String) -> void:
	var member := _current_member()
	if member == "":
		return
	_show_item_menu_for_slot(member, slot)

func _show_item_menu_for_slot(member: String, slot: String) -> void:
	var items := _list_equippable(member, slot)
	var cur := _fetch_equip_for(member)
	var cur_id := String(cur.get(slot, ""))

	var pm := PopupMenu.new()
	add_child(pm)
	if cur_id != "" and cur_id != "—":
		pm.add_item("Unequip")
		pm.set_item_metadata(pm.get_item_count() - 1, null)
		pm.add_separator()
	if items.is_empty():
		pm.add_item("(No items)")
		pm.set_item_disabled(pm.get_item_count() - 1, true)
	else:
		for id in items:
			var label := _pretty_item(id)
			pm.add_item(label)
			pm.set_item_metadata(pm.get_item_count() - 1, id)

	var _handle := func(index: int) -> void:
		var meta: Variant = pm.get_item_metadata(index)
		pm.queue_free()
		if typeof(meta) == TYPE_NIL:
			if _eq and _eq.has_method("unequip_slot"):
				_eq.call("unequip_slot", member, slot)
			if slot == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member)
		else:
			var picked_id := String(meta)
			if _eq and _eq.has_method("equip_item"):
				_eq.call("equip_item", member, picked_id)
			if slot == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member)
		var sel: PackedInt32Array = _party_list.get_selected_items()
		_on_party_selected(sel[0] if sel.size() > 0 else -1)

	pm.index_pressed.connect(_handle)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_handle.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(280, 0)))

# ─────────────────────── Sigils section ───────────────────────

func _rebuild_sigils(member: String) -> void:
	if _sigils_list == null:
		return
	for c in _sigils_list.get_children(): c.queue_free()

	var cap := 0
	var sockets := PackedStringArray()
	if _sig:
		if _sig.has_method("get_capacity"): cap = int(_sig.call("get_capacity", member))
		if _sig.has_method("get_loadout"):
			var v2: Variant = _sig.call("get_loadout", member)
			if typeof(v2) == TYPE_PACKED_STRING_ARRAY:
				sockets = v2 as PackedStringArray
			elif typeof(v2) == TYPE_ARRAY:
				for s in (v2 as Array): sockets.append(String(s))

	if _sigils_title: _sigils_title.text = "Sigils  (%d/%d)" % [sockets.size(), cap]

	if cap <= 0:
		var none := Label.new()
		none.text = "No bracelet slots"
		none.autowrap_mode = TextServer.AUTOWRAP_WORD
		_sigils_list.add_child(none)
		return

	for idx in range(cap):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var has := (idx < sockets.size() and String(sockets[idx]) != "")
		var cur_id := ""
		if has: cur_id = String(sockets[idx])

		if has and _sig and _sig.has_method("get_display_name_for"):
			nm.text = String(_sig.call("get_display_name_for", cur_id))
			if _sig.has_method("get_active_skill_name_for_instance"):
				var act := String(_sig.call("get_active_skill_name_for_instance", cur_id))
				if act != "": nm.text += "  —  " + act
		else:
			nm.text = "(empty)"
		row.add_child(nm)

		if not has:
			var btn_e := Button.new()
			btn_e.text = "Equip…"
			btn_e.pressed.connect(_on_equip_sigil.bind(member, idx))
			row.add_child(btn_e)
		else:
			var btn_u := Button.new()
			btn_u.text = "Remove"
			btn_u.pressed.connect(_on_remove_sigil.bind(member, idx))
			row.add_child(btn_u)

		_sigils_list.add_child(row)

func _on_equip_sigil(member: String, socket_index: int) -> void:
	if _sig == null: return

	# free (already-instanced)
	var free_instances := PackedStringArray()
	if _sig.has_method("list_free_instances"):
		var v0: Variant = _sig.call("list_free_instances")
		if typeof(v0) == TYPE_PACKED_STRING_ARRAY: free_instances = v0 as PackedStringArray
		elif typeof(v0) == TYPE_ARRAY:
			for s in (v0 as Array): free_instances.append(String(s))

	# base ids from inventory
	var base_ids := _collect_base_sigils()

	var pm := PopupMenu.new()
	add_child(pm)
	var any := false

	if free_instances.size() > 0:
		pm.add_item("— Unslotted Instances —")
		pm.set_item_disabled(pm.get_item_count() - 1, true)
		for inst in free_instances:
			var label := (String(_sig.call("get_display_name_for", inst)) if (_sig and _sig.has_method("get_display_name_for")) else inst)
			pm.add_item(label)
			pm.set_item_metadata(pm.get_item_count() - 1, {"kind":"inst","id":inst})
		any = true

	if base_ids.size() > 0:
		pm.add_separator()
		pm.add_item("— From Inventory —")
		pm.set_item_disabled(pm.get_item_count() - 1, true)
		for base in base_ids:
			var label2 := (String(_sig.call("get_display_name_for", base)) if (_sig and _sig.has_method("get_display_name_for")) else _pretty_item(base))
			pm.add_item(label2)
			pm.set_item_metadata(pm.get_item_count() - 1, {"kind":"base","id":base})
		any = true

	if not any:
		pm.add_item("(No sigils available)")
		pm.set_item_disabled(pm.get_item_count() - 1, true)

	var _handle_pick := func(index: int) -> void:
		var meta: Variant = pm.get_item_metadata(index)
		pm.queue_free()
		if typeof(meta) != TYPE_DICTIONARY and typeof(meta) != TYPE_STRING:
			return

		var kind := ""
		var id := ""
		if typeof(meta) == TYPE_DICTIONARY:
			var d: Dictionary = meta
			kind = String(d.get("kind",""))
			id   = String(d.get("id",""))
		else:
			id = String(meta)

		var final_inst := ""

		# 1) If they picked an existing instance, done.
		if kind == "inst" or (_sig and _sig.has_method("is_instance_id") and bool(_sig.call("is_instance_id", id))):
			final_inst = id

		# 2) Inventory base → try known APIs on SigilSystem
		if final_inst == "" and (kind == "base" or kind == ""):
			if _sig.has_method("equip_from_inventory"):
				# some implementations do everything internally
				var ok_direct := bool(_sig.call("equip_from_inventory", member, socket_index, id))
				if ok_direct: _on_sigils_changed(member); return
			if _sig.has_method("draft_from_inventory"):
				var drafted: Variant = _sig.call("draft_from_inventory", id)
				if typeof(drafted) == TYPE_STRING:
					final_inst = String(drafted)

		# 3) Last-resort: create instance and consume inventory via common names
		if final_inst == "":
			if _sig.has_method("create_instance"):
				var inst_v: Variant = _sig.call("create_instance", id)
				if typeof(inst_v) == TYPE_STRING:
					final_inst = String(inst_v)
					# best-effort inventory decrement
					if _inv:
						if _inv.has_method("dec"): _inv.call("dec", id, 1)
						elif _inv.has_method("consume"): _inv.call("consume", id, 1)
						elif _inv.has_method("decrement"): _inv.call("decrement", id, 1)
						elif _inv.has_method("add"): _inv.call("add", id, -1)

		# 4) Equip the instance (if we have one). If none, try passing base to equip_into_socket.
		if final_inst != "" and _sig.has_method("equip_into_socket"):
			var ok := bool(_sig.call("equip_into_socket", member, socket_index, final_inst))
			if ok and _sig.has_method("on_bracelet_changed"): _sig.call("on_bracelet_changed", member)
			_on_sigils_changed(member)
		elif final_inst == "" and _sig.has_method("equip_into_socket"):
			var ok_base := bool(_sig.call("equip_into_socket", member, socket_index, id))
			if ok_base: _on_sigils_changed(member)

	pm.index_pressed.connect(_handle_pick)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_handle_pick.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(260, 0)))

func _on_remove_sigil(member: String, socket_index: int) -> void:
	if _sig and _sig.has_method("remove_sigil_at"):
		_sig.call("remove_sigil_at", member, socket_index)
	_on_sigils_changed(member)

func _collect_base_sigils() -> PackedStringArray:
	var out := PackedStringArray()
	# SigilSystem might already expose base IDs it knows about
	if _sig and _sig.has_method("list_owned_sigils"):
		var v: Variant = _sig.call("list_owned_sigils")
		if typeof(v) == TYPE_PACKED_STRING_ARRAY: out = v as PackedStringArray
		elif typeof(v) == TYPE_ARRAY: for s in (v as Array): out.append(String(s))
	# Fallback: scan inventory for items tagged as sigils
	if out.is_empty() and _inv:
		var defs: Dictionary = {}
		var counts: Dictionary = {}
		if _inv.has_method("get_item_defs"):
			var d_v: Variant = _inv.call("get_item_defs")
			if typeof(d_v) == TYPE_DICTIONARY: defs = d_v
		if _inv.has_method("get_counts_dict"):
			var c_v: Variant = _inv.call("get_counts_dict")
			if typeof(c_v) == TYPE_DICTIONARY: counts = c_v
		for id in counts.keys():
			if int(counts[id]) <= 0: continue
			var rec: Dictionary = defs.get(id, {}) as Dictionary
			for k in ["equip_slot","slot","equip","equip_to","category","cat","type","tags"]:
				if rec.has(k):
					var v = rec[k]
					if typeof(v) == TYPE_STRING:
						var tag := String(v).strip_edges().to_lower()
						if tag == "sigil" or tag == "sigils":
							out.append(String(id)); break
					elif typeof(v) == TYPE_ARRAY:
						for t in (v as Array):
							if String(t).strip_edges().to_lower() in ["sigil","sigils"]:
								out.append(String(id)); break
	return out

# ───────────── Stats grid (6×6 in scene) ─────────────

func _clear_stats_grid() -> void:
	if not _stats_grid: return
	for c in _stats_grid.get_children():
		c.queue_free()

func _label_cell(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	return l

func _value_cell(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", STATS_FONT_SIZE)
	return l

func _fmt_num(n: float) -> String:
	var as_int := int(round(n))
	return str(as_int) if abs(n - float(as_int)) < 0.0001 else str(snapped(n, 0.1))

func _stat(s: String) -> int:
	if _stats and _stats.has_method("get_stat"):
		var v: Variant = _stats.call("get_stat", s)
		if typeof(v) == TYPE_INT: return int(v)
	return 0

func _item_def(id: String) -> Dictionary:
	if id == "" or id == "—": return {}
	if _eq and _eq.has_method("get_item_def"):
		var v: Variant = _eq.call("get_item_def", id)
		if typeof(v) == TYPE_DICTIONARY: return v as Dictionary
	if _inv and _inv.has_method("get_item_defs"):
		var d: Variant = _inv.call("get_item_defs")
		if typeof(d) == TYPE_DICTIONARY:
			var defs: Dictionary = d
			return defs.get(id, {}) as Dictionary
	return {}

func _eva_mods_from_other(equip: Dictionary, exclude_id: String) -> int:
	var sum := 0
	for k in ["weapon","armor","head","bracelet"]:
		var id := String(equip.get(k,""))
		if id == "" or id == exclude_id: continue
		var d := _item_def(id)
		if d.has("base_eva"):
			sum += int(d.get("base_eva",0))
	return sum

func _rebuild_stats_grid(member: String, equip: Dictionary) -> void:
	_clear_stats_grid()

	# Read defs once
	var d_wea := _item_def(String(equip.get("weapon","")))
	var d_arm := _item_def(String(equip.get("armor","")))
	var d_head := _item_def(String(equip.get("head","")))
	var d_foot := _item_def(String(equip.get("foot","")))
	var d_brac := _item_def(String(equip.get("bracelet","")))

	# Weapon values
	var brw := _stat("BRW")
	var base_watk := int(d_wea.get("base_watk", 0))
	var scale_brw := float(d_wea.get("scale_brw", 0.0)) # avoid Control.scale shadowing
	var weapon_attack := base_watk + int(round(scale_brw * float(brw)))
	var weapon_scale := _fmt_num(scale_brw)
	var weapon_acc := int(d_wea.get("base_acc", 0))
	var skill_acc_boost := int(d_wea.get("skill_acc_boost", 0))
	var crit_bonus := int(d_wea.get("crit_bonus_pct", 0))
	var type_raw := String(d_wea.get("watk_type_tag","")).strip_edges().to_lower()
	var weapon_type := ("Neutral" if (type_raw == "" or type_raw == "wand") else type_raw.capitalize())
	var special := ("NL" if bool(d_wea.get("non_lethal", false)) else "")

	# Armor
	var vtl := _stat("VTL")
	var armor_flat := int(d_arm.get("armor_flat", 0))
	var pdef := int(round(float(armor_flat) * (_DEF_BASELINE + 0.25 * float(vtl))))
	var ail_res := int(d_arm.get("ail_resist_pct", 0))

	# Headwear
	var fcs := _stat("FCS")
	var hp_bonus := int(d_head.get("max_hp_boost", 0))
	var mp_bonus := int(d_head.get("max_mp_boost", 0))
	var ward_flat := int(d_head.get("ward_flat", 0))
	var mdef := int(round(float(ward_flat) * (_DEF_BASELINE + 0.25 * float(fcs))))

	# Footwear
	var base_eva := int(d_foot.get("base_eva", 0))
	var mods := _eva_mods_from_other(equip, String(equip.get("foot","")))
	var peva := base_eva + int(round(0.25 * float(vtl))) + mods
	var meva := base_eva + int(round(0.25 * float(fcs))) + mods
	var speed := int(d_foot.get("speed", 0))

	# Bracelet
	var slots := int(d_brac.get("sigil_slots", 0))
	var active := ""
	if _sig and _sig.has_method("get_loadout"):
		var v: Variant = _sig.call("get_loadout", member)
		var arr: Array = []
		if typeof(v) == TYPE_PACKED_STRING_ARRAY: arr = Array(v)
		elif typeof(v) == TYPE_ARRAY: arr = v
		if arr.size() > 0 and String(arr[0]) != "":
			var sid := String(arr[0])
			if _sig.has_method("get_display_name_for"):
				var dn: Variant = _sig.call("get_display_name_for", sid)
				active = String(dn) if typeof(dn) == TYPE_STRING else sid
			else:
				active = sid

	# Set bonus (placeholder)
	var set_bonus := ""

	# Emit pairs across the 6×6
	var _pair := func(lbl: String, val: String) -> void:
		_stats_grid.add_child(_label_cell(lbl))
		_stats_grid.add_child(_value_cell(val))

	# Row 1
	_pair.call("Weapon Attack", ("" if d_wea.is_empty() else str(weapon_attack)))
	_pair.call("Weapon Scale",  ("" if d_wea.is_empty() else weapon_scale))
	_pair.call("Weapon Accuracy", ("" if d_wea.is_empty() else str(weapon_acc)))
	# Row 2
	_pair.call("Skill Accuracy Boost", ("" if d_wea.is_empty() else str(skill_acc_boost)))
	_pair.call("Crit Bonus", ("" if d_wea.is_empty() else str(crit_bonus)))
	_pair.call("Weapon Type", ("" if d_wea.is_empty() else weapon_type))
	# Row 3
	_pair.call("Special", ("" if d_wea.is_empty() else special))
	_pair.call("Physical Defence", ("" if d_arm.is_empty() else str(pdef)))
	_pair.call("Ailment Resistance", ("" if d_arm.is_empty() else str(ail_res)))
	# Row 4
	_pair.call("HP Bonus", ("" if d_head.is_empty() else str(hp_bonus)))
	_pair.call("MP Bonus", ("" if d_head.is_empty() else str(mp_bonus)))
	_pair.call("Mind Defense", ("" if d_head.is_empty() else str(mdef)))
	# Row 5
	_pair.call("Physical Evasion", ("" if d_foot.is_empty() else str(peva)))
	_pair.call("Mind Evasion", ("" if d_foot.is_empty() else str(meva)))
	_pair.call("Speed", ("" if d_foot.is_empty() else str(speed)))
	# Row 6
	_pair.call("Set Bonus", set_bonus)
	_pair.call("Sigil Slots", ("" if d_brac.is_empty() else str(slots)))
	_stats_grid.add_child(_label_cell("Active Sigil"))
	var active_cell := _value_cell("" if d_brac.is_empty() else active)
	active_cell.custom_minimum_size.x = 60  # ← bump this if you need more
	_stats_grid.add_child(active_cell)
	

# ───────────────────── Refresh hooks ─────────────────────

func _on_equipment_changed(member: String) -> void:
	var cur := _current_member()
	if cur != "" and cur == member:
		var equip := _fetch_equip_for(member)
		_w_val.text = _pretty_item(String(equip.get("weapon","")))
		_a_val.text = _pretty_item(String(equip.get("armor","")))
		_h_val.text = _pretty_item(String(equip.get("head","")))
		_f_val.text = _pretty_item(String(equip.get("foot","")))
		_b_val.text = _pretty_item(String(equip.get("bracelet","")))
		_rebuild_stats_grid(member, equip)
		_rebuild_sigils(member)

func _on_sigils_changed(member: String) -> void:
	var cur := _current_member()
	if cur != "" and cur == member:
		_rebuild_sigils(member)
		var equip := _fetch_equip_for(member)
		_rebuild_stats_grid(member, equip)

# ─────────────────────────── Utils ───────────────────────────

func _pretty_item(id: String) -> String:
	if id == "" or id == "—":
		return "—"
	if _eq and _eq.has_method("get_item_display_name"):
		var v: Variant = _eq.call("get_item_display_name", id)
		if typeof(v) == TYPE_STRING: return String(v)
	return id

func _fetch_equip_for(member: String) -> Dictionary:
	if _gs and _gs.has_method("get_member_equip"):
		var d_v: Variant = _gs.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			if d.has("feet") and not d.has("foot"):
				d["foot"] = String(d["feet"])
			for k in _SLOTS:
				if not d.has(k): d[k] = ""
			return d
	if _eq and _eq.has_method("get_member_equip"):
		var d2_v: Variant = _eq.call("get_member_equip", member)
		if typeof(d2_v) == TYPE_DICTIONARY:
			return d2_v as Dictionary
	return {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

func _list_equippable(_member: String, slot: String) -> PackedStringArray:
	if _eq and _eq.has_method("list_equippable"):
		var v2: Variant = _eq.call("list_equippable", _member, slot)
		if typeof(v2) == TYPE_PACKED_STRING_ARRAY: return v2 as PackedStringArray
		if typeof(v2) == TYPE_ARRAY:
			var out2 := PackedStringArray()
			for e2 in (v2 as Array): out2.append(String(e2))
			return out2
	return PackedStringArray()

func _current_member() -> String:
	var sel: PackedInt32Array = _party_list.get_selected_items()
	if sel.size() == 0: return ""
	var i := sel[0]
	if i >= 0 and i < _names.size(): return _names[i]
	return ""

func _on_manage_sigils() -> void:
	var path := "res://scenes/main_menu/panels/SigilSkillMenu.tscn"
	if not ResourceLoader.exists(path):
		push_warning("[LoadoutPanel] SigilSkillMenu scene missing: %s" % path)
		return
	var ps := load(path) as PackedScene
	if ps == null: return
	var inst := ps.instantiate()
	if inst is Control:
		var c := inst as Control
		c.top_level = true
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 3000
	var who := _current_member()
	if who != "" and inst.has_method("set_member"):
		inst.call("set_member", who)
	get_tree().current_scene.add_child(inst)
