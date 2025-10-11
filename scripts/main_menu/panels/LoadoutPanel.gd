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

@onready var _brace_info   : Label         = get_node_or_null("Row/Right/Grid/BraceletInfo") as Label
@onready var _sigils_title : Label         = get_node_or_null("Row/Right/Sigils/Title") as Label
@onready var _sigils_list  : VBoxContainer = get_node_or_null("Row/Right/Sigils/List") as VBoxContainer
@onready var _btn_manage   : Button        = get_node_or_null("Row/Right/Buttons/BtnManageSigils") as Button

var _names: PackedStringArray = []
var _gs  : Node = null
var _inv : Node = null
var _sig : Node = null
var _eq  : Node = null

const _SLOTS: PackedStringArray = ["weapon","armor","head","foot","bracelet"]
var _slot_vals: Dictionary = {}

func _ready() -> void:
	_gs  = get_node_or_null("/root/aGameState")
	_inv = get_node_or_null("/root/aInventorySystem")
	_sig = get_node_or_null("/root/aSigilSystem")
	_eq  = get_node_or_null("/root/aEquipmentSystem")

	_slot_vals = {
		"weapon": _w_val, "armor": _a_val, "head": _h_val,
		"foot": _f_val, "bracelet": _b_val
	}

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

# --- party list ---------------------------------------------------------------
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
	_update_bracelet_meta(String(equip.get("bracelet","")))
	_rebuild_sigils(sel)

func _pretty_item(id: String) -> String:
	if id == "" or id == "—":
		return "—"
	if _sig and _sig.has_method("is_instance_id") and bool(_sig.call("is_instance_id", id)):
		if _sig.has_method("get_display_name_for"):
			return String(_sig.call("get_display_name_for", id))
		return id
	if _eq and _eq.has_method("get_item_display_name"):
		var v: Variant = _eq.call("get_item_display_name", id)
		if typeof(v) == TYPE_STRING:
			return String(v)
	return id

func _fetch_equip_for(member: String) -> Dictionary:
	if _gs and _gs.has_method("get_member_equip"):
		var d_v: Variant = _gs.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			return d_v as Dictionary
	if _eq and _eq.has_method("get_member_equip"):
		var d2_v: Variant = _eq.call("get_member_equip", member)
		if typeof(d2_v) == TYPE_DICTIONARY:
			return d2_v as Dictionary
	return {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

# --- per-slot equip -----------------------------------------------------------
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

	# "Unequip" row (null metadata)
	if cur_id != "" and cur_id != "—":
		pm.add_item("Unequip")
		var idx_u := pm.get_item_count() - 1
		pm.set_item_metadata(idx_u, null)
		pm.add_separator()

	# Items
	if items.is_empty():
		pm.add_item("(No items)")
		pm.set_item_disabled(pm.get_item_count() - 1, true)
	else:
		for id in items:
			var label := _pretty_item(id)
			pm.add_item(label)
			pm.set_item_metadata(pm.get_item_count() - 1, id)

	# Always prefer EquipmentSystem (does NOT touch inventory).
	# Only fall back to GameState if EquipmentSystem is missing.
	var _handle := func(index: int) -> void:
		var meta: Variant = pm.get_item_metadata(index)
		var member_local := member
		var slot_local := slot
		pm.queue_free()

		var eq_ok := _eq and _eq.has_method("equip_item")
		var eq_un_ok := _eq and _eq.has_method("unequip_slot")
		var gs_ok := _gs and _gs.has_method("equip_item")
		var gs_un_ok := _gs and _gs.has_method("unequip_slot")

		if typeof(meta) == TYPE_NIL:
			if eq_un_ok:
				_eq.call("unequip_slot", member_local, slot_local)
			elif gs_un_ok:
				_gs.call("unequip_slot", member_local, slot_local)
			if slot_local == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member_local)
		else:
			var picked_id := String(meta)
			if eq_ok:
				_eq.call("equip_item", member_local, picked_id)
			elif gs_ok:
				_gs.call("equip_item", member_local, picked_id)
			if slot_local == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member_local)

		var sel: PackedInt32Array = _party_list.get_selected_items()
		_on_party_selected(sel[0] if sel.size() > 0 else -1)

	pm.index_pressed.connect(_handle)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_handle.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(280, 0)))


# --- bracelet meta + sigils ---------------------------------------------------
func _update_bracelet_meta(bracelet_id: String) -> void:
	if _brace_info == null:
		return
	if bracelet_id == "" or bracelet_id == "—":
		_brace_info.text = ""
		return

	var slots: int = -1
	var tier: String = ""
	if _inv and _inv.has_method("get_item_defs"):
		var defs_v: Variant = _inv.call("get_item_defs")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			if defs.has(bracelet_id):
				var rec: Dictionary = defs[bracelet_id]
				for k in ["slots","sigil_slots","slot_count","capacity"]:
					if rec.has(k):
						slots = int(rec[k]); break
				if rec.has("tier_cap"): tier = String(rec["tier_cap"])
				elif rec.has("tier"):   tier = String(rec["tier"])
	_brace_info.text = "" if (slots < 0 and tier == "") else "%s slots, Tier %s" % [
		(str(slots) if slots >= 0 else "?"), (tier if tier != "" else "I")
	]

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
			if typeof(v2) == TYPE_PACKED_STRING_ARRAY: sockets = v2 as PackedStringArray
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
		var cur_id := ( String(sockets[idx]) if has else "" )
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

# --- data helpers & sigil equip ----------------------------------------------
func _collect_base_sigils() -> PackedStringArray:
	var out := PackedStringArray()
	if _sig and _sig.has_method("list_owned_sigils"):
		var v: Variant = _sig.call("list_owned_sigils")
		if typeof(v) == TYPE_PACKED_STRING_ARRAY: out = v as PackedStringArray
		elif typeof(v) == TYPE_ARRAY: for s in (v as Array): out.append(String(s))
	if out.is_empty() and _inv != null:
		var defs: Dictionary = {}
		var counts: Dictionary = {}
		if _inv.has_method("get_item_defs"):
			var d_v: Variant = _inv.call("get_item_defs"); if typeof(d_v) == TYPE_DICTIONARY: defs = d_v
		if _inv.has_method("get_counts_dict"):
			var c_v: Variant = _inv.call("get_counts_dict"); if typeof(c_v) == TYPE_DICTIONARY: counts = c_v
		for id in counts.keys():
			if int(counts[id]) <= 0: continue
			var rec: Dictionary = defs.get(id, {}) as Dictionary
			var tag := ""
			for k in ["equip_slot","slot","equip","equip_to","category","cat","type"]:
				if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
					tag = String(rec[k]).strip_edges().to_lower()
					if tag == "sigil" or tag == "sigils": out.append(String(id)); break
	return out

func _on_equip_sigil(member: String, socket_index: int) -> void:
	if _sig == null: return

	var free_instances := PackedStringArray()
	if _sig.has_method("list_free_instances"):
		var v0: Variant = _sig.call("list_free_instances")
		if typeof(v0) == TYPE_PACKED_STRING_ARRAY: free_instances = v0 as PackedStringArray
		elif typeof(v0) == TYPE_ARRAY: for s in (v0 as Array): free_instances.append(String(s))

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
			# tolerate plain string meta (id only)
			id = String(meta)

		var final_inst := ""
		if kind == "inst" or (_sig and _sig.has_method("is_instance_id") and bool(_sig.call("is_instance_id", id))):
			final_inst = id
		else:
			# base → instance, try multiple APIs
			if _sig.has_method("draft_from_inventory"):
				var v: Variant = _sig.call("draft_from_inventory", id)
				if typeof(v) == TYPE_STRING: final_inst = String(v)
			elif _sig.has_method("equip_from_inventory"):
				# some implementations equip directly from item
				var ok_direct := bool(_sig.call("equip_from_inventory", member, socket_index, id))
				if ok_direct:
					_on_sigils_changed(member); return
			# last resort: attempt to pass base id to equip_into_socket (if supported)
			if final_inst == "" and _sig.has_method("equip_into_socket"):
				var ok_base := bool(_sig.call("equip_into_socket", member, socket_index, id))
				if ok_base:
					_on_sigils_changed(member); return

		if final_inst != "" and _sig.has_method("equip_into_socket"):
			var ok := bool(_sig.call("equip_into_socket", member, socket_index, final_inst))
			if ok and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member)
			_on_sigils_changed(member)

	pm.index_pressed.connect(_handle_pick)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_handle_pick.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(260, 0)))

func _on_remove_sigil(member: String, socket_index: int) -> void:
	if _sig and _sig.has_method("remove_sigil_at"):
		_sig.call("remove_sigil_at", member, socket_index)
	_on_sigils_changed(member)

# --- auto-refresh hooks -------------------------------------------------------
func _on_equipment_changed(member: String) -> void:
	var cur := _current_member()
	if cur != "" and cur == member:
		var sel: PackedInt32Array = _party_list.get_selected_items()
		_on_party_selected(sel[0] if sel.size() > 0 else -1)

func _on_sigils_changed(member: String) -> void:
	var cur := _current_member()
	if cur != "" and cur == member:
		_rebuild_sigils(member)

# --- utils --------------------------------------------------------------------
func _list_equippable(member: String, slot: String) -> PackedStringArray:
	if _gs and _gs.has_method("list_equippable"):
		var v: Variant = _gs.call("list_equippable", member, slot)
		if typeof(v) == TYPE_PACKED_STRING_ARRAY: return v as PackedStringArray
		if typeof(v) == TYPE_ARRAY:
			var out := PackedStringArray(); for e in (v as Array): out.append(String(e)); return out
	if _eq and _eq.has_method("list_equippable"):
		var v2: Variant = _eq.call("list_equippable", member, slot)
		if typeof(v2) == TYPE_PACKED_STRING_ARRAY: return v2 as PackedStringArray
		if typeof(v2) == TYPE_ARRAY:
			var out2 := PackedStringArray(); for e2 in (v2 as Array): out2.append(String(e2)); return out2
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
