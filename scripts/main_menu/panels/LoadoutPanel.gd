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

@onready var _stats_grid : GridContainer = get_node("Row/Right/StatsGrid") as GridContainer
@onready var _mind_value : Label         = get_node_or_null("Row/Right/MindRow/Value") as Label

# Parallel arrays: display vs token we pass into systems
var _labels: PackedStringArray = []
var _tokens: PackedStringArray = []

var _gs        : Node = null
var _inv       : Node = null
var _sig       : Node = null
var _eq        : Node = null
var _stats     : Node = null
var _party_sys : Node = null
var _hero_sys  : Node = null

const _SLOTS = ["weapon","armor","head","foot","bracelet"]
const _DEF_BASELINE := 5.0
const STATS_FONT_SIZE := 9

func _ready() -> void:
	_gs        = get_node_or_null("/root/aGameState")
	_inv       = get_node_or_null("/root/aInventorySystem")
	_sig       = get_node_or_null("/root/aSigilSystem")
	_eq        = get_node_or_null("/root/aEquipmentSystem")
	_stats     = get_node_or_null("/root/aStatsSystem")
	_party_sys = get_node_or_null("/root/aPartySystem")
	_hero_sys  = get_node_or_null("/root/aHeroSystem")

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

	_hook_party_signals()

	# defer first build so we don’t miss early system init / signals
	call_deferred("_first_fill")

func _first_fill() -> void:
	_refresh_party()
	if _party_list.get_item_count() > 0:
		_party_list.select(0)
		_on_party_selected(0)

# ───────────── helpers ─────────────

func _norm(s: String) -> String:
	return String(s).strip_edges().to_lower()

func _hero_name() -> String:
	if _hero_sys and _hero_sys.has_method("get"):
		var v: Variant = _hero_sys.get("hero_name")
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	return "Player"

func _roster() -> Dictionary:
	var roster: Dictionary = {}
	if _party_sys:
		if _party_sys.has_method("get"):
			var r_v: Variant = _party_sys.get("roster")
			if typeof(r_v) == TYPE_DICTIONARY: roster = r_v as Dictionary
		if roster.is_empty() and _party_sys.has_method("get_roster"):
			var r2_v: Variant = _party_sys.call("get_roster")
			if typeof(r2_v) == TYPE_DICTIONARY: roster = r2_v as Dictionary
	return roster

func _label_for_token(token: String, roster: Dictionary) -> String:
	if token == "hero": return _hero_name()
	if roster.has(token):
		var rec: Dictionary = roster[token]
		if rec.has("name") and typeof(rec["name"]) == TYPE_STRING:
			return String(rec["name"])
	return token

# ───────────── party discovery ─────────────

func _gather_party_entries() -> Array:
	var ros: Dictionary = _roster()
	var entries: Array = []

	# 1) From GameState (ids)
	if _gs and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		if typeof(v) == TYPE_ARRAY:
			for t in (v as Array):
				var tok := String(t)
				entries.append({"key": tok, "label": _label_for_token(tok, ros)})
			return entries

	# 2) From GameState (names)
	if _gs and _gs.has_method("get_party_names"):
		var n_v: Variant = _gs.call("get_party_names")
		if typeof(n_v) == TYPE_PACKED_STRING_ARRAY and (n_v as PackedStringArray).size() > 0:
			for s in (n_v as PackedStringArray):
				var nm := String(s)
				if nm.strip_edges() != "":
					entries.append({"key": nm, "label": nm})
			if entries.size() > 0:
				return entries
		elif typeof(n_v) == TYPE_ARRAY and (n_v as Array).size() > 0:
			for s2 in (n_v as Array):
				var nm2 := String(s2)
				if nm2.strip_edges() != "":
					entries.append({"key": nm2, "label": nm2})
			if entries.size() > 0:
				return entries

	# 3) From PartySystem (ids)
	if _party_sys:
		if _party_sys.has_method("get_active"):
			var r: Variant = _party_sys.call("get_active")
			if typeof(r) == TYPE_ARRAY and (r as Array).size() > 0:
				for t3 in (r as Array):
					var tok3 := String(t3)
					entries.append({"key": tok3, "label": _label_for_token(tok3, ros)})
				return entries
		if _party_sys.has_method("get"):
			var a_v: Variant = _party_sys.get("active")
			if typeof(a_v) == TYPE_ARRAY and (a_v as Array).size() > 0:
				for t4 in (a_v as Array):
					var tok4 := String(t4)
					entries.append({"key": tok4, "label": _label_for_token(tok4, ros)})
				return entries

	# 4) Last resort: hero only
	entries.append({"key": "hero", "label": _hero_name()})
	return entries

# ───────────── signals ─────────────

func _hook_party_signals() -> void:
	var cb := Callable(self, "_on_party_dirty")
	if _gs:
		for s in ["party_changed", "member_added", "member_removed"]:
			if _gs.has_signal(s) and not _gs.is_connected(s, cb):
				_gs.connect(s, cb)
	if _party_sys:
		for s2 in ["active_changed", "roster_changed", "party_changed"]:
			if _party_sys.has_signal(s2) and not _party_sys.is_connected(s2, cb):
				_party_sys.connect(s2, cb)

func _on_party_dirty(_a: Variant = null, _b: Variant = null) -> void:
	var prev_token: String = _current_token()
	_refresh_party()
	var idx: int = _tokens.find(prev_token)
	if idx >= 0:
		_party_list.select(idx)
		_on_party_selected(idx)
	elif _party_list.get_item_count() > 0:
		_party_list.select(0)
		_on_party_selected(0)

# ───────────── populate UI ─────────────

func _refresh_party() -> void:
	_party_list.clear()
	_labels.clear()
	_tokens.clear()

	var entries: Array = _gather_party_entries()

	# Dedup while preserving order
	var seen := {}
	for e_v in entries:
		if typeof(e_v) != TYPE_DICTIONARY: continue
		var e: Dictionary = e_v
		var key: String = String(e.get("key",""))
		var label: String = String(e.get("label",""))
		if key == "" and label == "": continue
		var uniq: String = key + "@" + label
		if not seen.has(uniq):
			seen[uniq] = true
			_tokens.append(key if key != "" else label)
			_labels.append(label if label != "" else key)

	if _labels.is_empty():
		_tokens.append("hero"); _labels.append(_hero_name())

	# ✅ correct loop
	for i in range(_labels.size()):
		_party_list.add_item(_labels[i])

	_party_list.queue_redraw()

# ───────────── selection + equip ─────────────

func _on_party_selected(index: int) -> void:
	var label: String = "(Unknown)"
	if index >= 0 and index < _labels.size():
		label = _labels[index]
	_member_name.text = label

	var token: String = _current_token()
	var equip: Dictionary = _fetch_equip_for(token)

	_w_val.text = _pretty_item(String(equip.get("weapon","")))
	_a_val.text = _pretty_item(String(equip.get("armor","")))
	_h_val.text = _pretty_item(String(equip.get("head","")))
	_f_val.text = _pretty_item(String(equip.get("foot","")))
	_b_val.text = _pretty_item(String(equip.get("bracelet","")))

	_rebuild_stats_grid(token, equip)
	_rebuild_sigils(token)
	_refresh_mind_row(token)

func _current_label() -> String:
	var sel: PackedInt32Array = _party_list.get_selected_items()
	if sel.size() == 0: return ""
	var i: int = sel[0]
	if i >= 0 and i < _labels.size(): return _labels[i]
	return ""

func _current_token() -> String:
	var sel: PackedInt32Array = _party_list.get_selected_items()
	if sel.size() == 0:
		return (_tokens[0] if _tokens.size() > 0 else "")
	var i: int = sel[0]
	if i >= 0 and i < _tokens.size():
		return _tokens[i]
	return ""

func _on_slot_button(slot: String) -> void:
	var token: String = _current_token()
	if token == "": return
	_show_item_menu_for_slot(token, slot)

func _show_item_menu_for_slot(member_token: String, slot: String) -> void:
	var items: PackedStringArray = _list_equippable(member_token, slot)
	var cur: Dictionary = _fetch_equip_for(member_token)
	var cur_id: String = String(cur.get(slot, ""))

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
			var label: String = _pretty_item(id)
			pm.add_item(label)
			pm.set_item_metadata(pm.get_item_count() - 1, id)

	var _handle := func(index: int) -> void:
		var meta: Variant = pm.get_item_metadata(index)
		pm.queue_free()
		if typeof(meta) == TYPE_NIL:
			if _eq and _eq.has_method("unequip_slot"):
				_eq.call("unequip_slot", member_token, slot)
			if slot == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member_token)
		else:
			var picked_id: String = String(meta)
			if _eq and _eq.has_method("equip_item"):
				_eq.call("equip_item", member_token, picked_id)
			if slot == "bracelet" and _sig and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member_token)

		var sel2: PackedInt32Array = _party_list.get_selected_items()
		_on_party_selected(sel2[0] if sel2.size() > 0 else -1)

	pm.index_pressed.connect(_handle)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_handle.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(280, 0)))

# ───────────── Sigils + Mind Type ─────────────

func _rebuild_sigils(member_token: String) -> void:
	if _sigils_list == null: return
	for c in _sigils_list.get_children(): c.queue_free()

	var cap: int = 0
	var sockets := PackedStringArray()
	if _sig:
		if _sig.has_method("get_capacity"): cap = int(_sig.call("get_capacity", member_token))
		if _sig.has_method("get_loadout"):
			var v2: Variant = _sig.call("get_loadout", member_token)
			if typeof(v2) == TYPE_PACKED_STRING_ARRAY: sockets = v2 as PackedStringArray
			elif typeof(v2) == TYPE_ARRAY:
				for s in (v2 as Array): sockets.append(String(s))

	if _sigils_title:
		_sigils_title.text = "Sigils  (%d/%d)" % [sockets.size(), cap]

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

		var has: bool = (idx < sockets.size() and String(sockets[idx]) != "")
		var cur_id: String = ""
		if has: cur_id = String(sockets[idx])

		if has and _sig and _sig.has_method("get_display_name_for"):
			nm.text = String(_sig.call("get_display_name_for", cur_id))
			if _sig.has_method("get_active_skill_name_for_instance"):
				var act: String = String(_sig.call("get_active_skill_name_for_instance", cur_id))
				if act != "": nm.text += "  —  " + act
		else:
			nm.text = "(empty)"
		row.add_child(nm)

		if not has:
			var btn_e := Button.new()
			btn_e.text = "Equip…"
			btn_e.pressed.connect(_on_equip_sigil.bind(member_token, idx))
			row.add_child(btn_e)
		else:
			var btn_u := Button.new()
			btn_u.text = "Remove"
			btn_u.pressed.connect(_on_remove_sigil.bind(member_token, idx))
			row.add_child(btn_u)

		_sigils_list.add_child(row)

func _on_equip_sigil(member_token: String, socket_index: int) -> void:
	if _sig == null: return

	var member_mind: String = _get_member_mind_type(member_token)

	var free_instances := PackedStringArray()
	if _sig.has_method("list_free_instances"):
		var v0: Variant = _sig.call("list_free_instances")
		if typeof(v0) == TYPE_PACKED_STRING_ARRAY: free_instances = v0 as PackedStringArray
		elif typeof(v0) == TYPE_ARRAY:
			for s in (v0 as Array): free_instances.append(String(s))

	var base_ids: PackedStringArray = _collect_base_sigils()

	var pm := PopupMenu.new()
	add_child(pm)
	var any: bool = false

	if free_instances.size() > 0:
		pm.add_item("— Unslotted Instances —")
		pm.set_item_disabled(pm.get_item_count() - 1, true)
		for inst in free_instances:
			var label: String = (String(_sig.call("get_display_name_for", inst)) if (_sig and _sig.has_method("get_display_name_for")) else inst)
			var ok_inst: bool = _is_sigil_compatible(member_mind, inst)
			if not ok_inst: label += "  (incompatible)"
			var row_i: int = pm.get_item_count()
			pm.add_item(label)
			pm.set_item_metadata(row_i, {"kind":"inst","id":inst,"ok":ok_inst})
			if not ok_inst: pm.set_item_disabled(row_i, true)
		any = true

	if base_ids.size() > 0:
		pm.add_separator()
		pm.add_item("— From Inventory —")
		pm.set_item_disabled(pm.get_item_count() - 1, true)
		for base in base_ids:
			var label2: String = (String(_sig.call("get_display_name_for", base)) if (_sig and _sig.has_method("get_display_name_for")) else _pretty_item(base))
			var ok2: bool = _is_sigil_compatible(member_mind, base)
			if not ok2: label2 += "  (incompatible)"
			var row_b: int = pm.get_item_count()
			pm.add_item(label2)
			pm.set_item_metadata(row_b, {"kind":"base","id":base,"ok":ok2})
			if not ok2: pm.set_item_disabled(row_b, true)
		any = true

	if not any:
		pm.add_item("(No sigils available)")
		pm.set_item_disabled(pm.get_item_count() - 1, true)

	var _handle_pick := func(index: int) -> void:
		var meta: Variant = pm.get_item_metadata(index)
		pm.queue_free()
		if typeof(meta) != TYPE_DICTIONARY and typeof(meta) != TYPE_STRING: return

		var kind: String = ""
		var id: String = ""
		var ok_meta: bool = true
		if typeof(meta) == TYPE_DICTIONARY:
			var d: Dictionary = meta
			kind    = String(d.get("kind",""))
			id      = String(d.get("id",""))
			ok_meta = bool(d.get("ok", true))
		else:
			id = String(meta)

		if not ok_meta: return

		var final_inst: String = ""
		if kind == "inst" or (_sig and _sig.has_method("is_instance_id") and bool(_sig.call("is_instance_id", id))):
			final_inst = id

		if final_inst == "" and (kind == "base" or kind == ""):
			if _sig.has_method("equip_from_inventory"):
				var ok_direct: bool = bool(_sig.call("equip_from_inventory", member_token, socket_index, id))
				if ok_direct:
					_on_sigils_changed(member_token)
					return
			if _sig.has_method("draft_from_inventory"):
				var drafted: Variant = _sig.call("draft_from_inventory", id)
				if typeof(drafted) == TYPE_STRING:
					final_inst = String(drafted)

		if final_inst == "":
			if _sig.has_method("create_instance"):
				var inst_v: Variant = _sig.call("create_instance", id)
				if typeof(inst_v) == TYPE_STRING:
					final_inst = String(inst_v)
					if _inv:
						if _inv.has_method("dec"): _inv.call("dec", id, 1)
						elif _inv.has_method("consume"): _inv.call("consume", id, 1)
						elif _inv.has_method("decrement"): _inv.call("decrement", id, 1)
						elif _inv.has_method("add"): _inv.call("add", id, -1)

		if final_inst != "" and _sig.has_method("equip_into_socket"):
			var ok_e: bool = bool(_sig.call("equip_into_socket", member_token, socket_index, final_inst))
			if ok_e and _sig.has_method("on_bracelet_changed"):
				_sig.call("on_bracelet_changed", member_token)
			_on_sigils_changed(member_token)
		elif final_inst == "" and _sig.has_method("equip_into_socket"):
			var ok_base: bool = bool(_sig.call("equip_into_socket", member_token, socket_index, id))
			if ok_base:
				_on_sigils_changed(member_token)

	pm.index_pressed.connect(_handle_pick)
	pm.id_pressed.connect(func(idnum: int) -> void:
		_handle_pick.call(pm.get_item_index(idnum))
	)
	pm.popup(Rect2(get_global_mouse_position(), Vector2(260, 0)))

func _on_remove_sigil(member_token: String, socket_index: int) -> void:
	if _sig and _sig.has_method("remove_sigil_at"):
		_sig.call("remove_sigil_at", member_token, socket_index)
	_on_sigils_changed(member_token)

func _collect_base_sigils() -> PackedStringArray:
	var out := PackedStringArray()
	var inv: Node = get_node_or_null("/root/aInventorySystem")
	if inv == null: return out

	var defs: Dictionary = {}
	var counts: Dictionary = {}
	if inv.has_method("get_item_defs"):
		var d_v: Variant = inv.call("get_item_defs")
		if typeof(d_v) == TYPE_DICTIONARY: defs = d_v as Dictionary
	if inv.has_method("get_counts_dict"):
		var c_v: Variant = inv.call("get_counts_dict")
		if typeof(c_v) == TYPE_DICTIONARY: counts = c_v as Dictionary

	for id_v in counts.keys():
		var id: String = String(id_v)
		if int(counts.get(id, 0)) <= 0: continue
		var rec: Dictionary = defs.get(id, {}) as Dictionary
		var tag: String = ""
		for k in ["equip_slot","slot","equip","equip_to","category","cat","type"]:
			if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
				tag = String(rec[k]).strip_edges().to_lower()
				if tag == "sigil" or tag == "sigils":
					out.append(id)
					break
	return out

# ───────────── Mind Type helpers ─────────────

func _get_member_mind_type(member_token: String) -> String:
	if _party_sys and _party_sys.has_method("get_mind_type"):
		var v: Variant = _party_sys.call("get_mind_type", member_token)
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)

	var ros: Dictionary = _roster()
	if ros.has(member_token):
		var rec_key: Dictionary = ros[member_token]
		for k in ["mind_type","mind","element"]:
			if rec_key.has(k) and typeof(rec_key[k]) == TYPE_STRING and String(rec_key[k]).strip_edges() != "":
				return String(rec_key[k])
	else:
		var n := _norm(member_token)
		for key in ros.keys():
			var rec: Dictionary = ros[key]
			if rec.has("name") and _norm(String(rec["name"])) == n:
				for k in ["mind_type","mind","element"]:
					if rec.has(k) and typeof(rec[k]) == TYPE_STRING and String(rec[k]).strip_edges() != "":
						return String(rec[k])
				break

	if member_token == "hero" or _norm(member_token) == _norm(_hero_name()):
		return "Omega"

	if _gs and _gs.has_method("get_member_field"):
		var v2: Variant = _gs.call("get_member_field", member_token, "mind_type")
		if typeof(v2) == TYPE_STRING and String(v2).strip_edges() != "":
			return String(v2)

	return ""

func _sigil_element(id_or_inst: String) -> String:
	if _sig:
		for m in ["get_element_for_instance","get_mind_for_instance","get_element_for","get_mind_for"]:
			if _sig.has_method(m):
				var v: Variant = _sig.call(m, id_or_inst)
				if typeof(v) == TYPE_STRING and String(v) != "":
					return String(v)
		for m2 in ["get_base_id","get_base_for","get_source_base","get_base_from_instance"]:
			if _sig.has_method(m2):
				var base_v: Variant = _sig.call(m2, id_or_inst)
				if typeof(base_v) == TYPE_STRING and String(base_v) != "":
					return _sigil_element(String(base_v))
	var rec: Dictionary = _item_def(id_or_inst)
	for k in ["mind_type","mind","element","elem"]:
		if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
			return String(rec[k])
	return ""

func _is_sigil_compatible(member_mind: String, sigil_id_or_inst: String) -> bool:
	var mm: String = _norm(member_mind)
	if mm == "" or mm == "omega": return true
	var se: String = _norm(_sigil_element(sigil_id_or_inst))
	return se == "" or se == mm

# ───────────── Stats grid + item defs ─────────────

func _clear_stats_grid() -> void:
	if _stats_grid == null: return
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
	var as_int: int = int(round(n))
	return str(as_int) if abs(n - float(as_int)) < 0.0001 else str(snapped(n, 0.1))

func _stat(s: String) -> int:
	if _stats and _stats.has_method("get_stat"):
		var v: Variant = _stats.call("get_stat", s)
		if typeof(v) == TYPE_INT: return int(v)
	return 0

func _item_def(id: String) -> Dictionary:
	var empty: Dictionary = {}
	if id == "" or id == "—": return empty
	if _eq and _eq.has_method("get_item_def"):
		var v: Variant = _eq.call("get_item_def", id)
		if typeof(v) == TYPE_DICTIONARY: return v as Dictionary
	if _inv and _inv.has_method("get_item_defs"):
		var d: Variant = _inv.call("get_item_defs")
		if typeof(d) == TYPE_DICTIONARY:
			var defs: Dictionary = d
			return defs.get(id, empty) as Dictionary
	return empty

func _eva_mods_from_other(equip: Dictionary, exclude_id: String) -> int:
	var sum: int = 0
	for k in ["weapon","armor","head","bracelet"]:
		var id: String = String(equip.get(k,""))
		if id == "" or id == exclude_id: continue
		var d: Dictionary = _item_def(id)
		if d.has("base_eva"):
			sum += int(d.get("base_eva",0))
	return sum

func _rebuild_stats_grid(member_token: String, equip: Dictionary) -> void:
	if _stats_grid == null: return
	_clear_stats_grid()

	var d_wea: Dictionary  = _item_def(String(equip.get("weapon","")))
	var d_arm: Dictionary  = _item_def(String(equip.get("armor","")))
	var d_head: Dictionary = _item_def(String(equip.get("head","")))
	var d_foot: Dictionary = _item_def(String(equip.get("foot","")))
	var d_brac: Dictionary = _item_def(String(equip.get("bracelet","")))

	var brw: int = _stat("BRW")
	var base_watk: int  = int(d_wea.get("base_watk", 0))
	var scale_brw: float = float(d_wea.get("scale_brw", 0.0))
	var weapon_attack: int = base_watk + int(round(scale_brw * float(brw)))
	var weapon_scale: String = _fmt_num(scale_brw)
	var weapon_acc: int = int(d_wea.get("base_acc", 0))
	var skill_acc_boost: int = int(d_wea.get("skill_acc_boost", 0))
	var crit_bonus: int = int(d_wea.get("crit_bonus_pct", 0))
	var type_raw: String = String(d_wea.get("watk_type_tag","")).strip_edges().to_lower()
	var weapon_type: String = ("Neutral" if (type_raw == "" or type_raw == "wand") else type_raw.capitalize())
	var special: String = ("NL" if bool(d_wea.get("non_lethal", false)) else "")

	var vtl: int = _stat("VTL")
	var armor_flat: int = int(d_arm.get("armor_flat", 0))
	var pdef: int = int(round(float(armor_flat) * (_DEF_BASELINE + 0.25 * float(vtl))))
	var ail_res: int = int(d_arm.get("ail_resist_pct", 0))

	var fcs: int = _stat("FCS")
	var hp_bonus: int = int(d_head.get("max_hp_boost", 0))
	var mp_bonus: int = int(d_head.get("max_mp_boost", 0))
	var ward_flat: int = int(d_head.get("ward_flat", 0))
	var mdef: int = int(round(float(ward_flat) * (_DEF_BASELINE + 0.25 * float(fcs))))

	var base_eva: int = int(d_foot.get("base_eva", 0))
	var mods: int = _eva_mods_from_other(equip, String(equip.get("foot","")))
	var peva: int = base_eva + int(round(0.25 * float(vtl))) + mods
	var meva: int = base_eva + int(round(0.25 * float(fcs))) + mods
	var speed: int = int(d_foot.get("speed", 0))

	var slots: int = int(d_brac.get("sigil_slots", 0))
	var active: String = ""
	if _sig and _sig.has_method("get_loadout"):
		var v: Variant = _sig.call("get_loadout", member_token)
		var arr: Array = []
		if typeof(v) == TYPE_PACKED_STRING_ARRAY: arr = Array(v)
		elif typeof(v) == TYPE_ARRAY: arr = v
		if arr.size() > 0 and String(arr[0]) != "":
			var sid: String = String(arr[0])
			if _sig.has_method("get_display_name_for"):
				var dn: Variant = _sig.call("get_display_name_for", sid)
				active = String(dn) if typeof(dn) == TYPE_STRING else sid
			else:
				active = sid

	var set_bonus: String = ""

	var _pair := func(lbl: String, val: String) -> void:
		_stats_grid.add_child(_label_cell(lbl))
		_stats_grid.add_child(_value_cell(val))

	_pair.call("Weapon Attack", ("" if d_wea.is_empty() else str(weapon_attack)))
	_pair.call("Weapon Scale",  ("" if d_wea.is_empty() else weapon_scale))
	_pair.call("Weapon Accuracy", ("" if d_wea.is_empty() else str(weapon_acc)))

	_pair.call("Skill Accuracy Boost", ("" if d_wea.is_empty() else str(skill_acc_boost)))
	_pair.call("Crit Bonus", ("" if d_wea.is_empty() else str(crit_bonus)))
	_pair.call("Weapon Type", ("" if d_wea.is_empty() else weapon_type))

	_pair.call("Special", ("" if d_wea.is_empty() else special))
	_pair.call("Physical Defence", ("" if d_arm.is_empty() else str(pdef)))
	_pair.call("Ailment Resistance", ("" if d_arm.is_empty() else str(ail_res)))

	_pair.call("HP Bonus", ("" if d_head.is_empty() else str(hp_bonus)))
	_pair.call("MP Bonus", ("" if d_head.is_empty() else str(mp_bonus)))
	_pair.call("Mind Defense", ("" if d_head.is_empty() else str(mdef)))

	_pair.call("Physical Evasion", ("" if d_foot.is_empty() else str(peva)))
	_pair.call("Mind Evasion", ("" if d_foot.is_empty() else str(meva)))
	_pair.call("Speed", ("" if d_foot.is_empty() else str(speed)))

	_pair.call("Set Bonus", set_bonus)
	_pair.call("Sigil Slots", ("" if d_brac.is_empty() else str(slots)))
	_stats_grid.add_child(_label_cell("Active Sigil"))
	var active_cell := _value_cell("" if d_brac.is_empty() else active)
	active_cell.custom_minimum_size.x = 60
	_stats_grid.add_child(active_cell)

# ───────────── refresh hooks ─────────────

func _on_equipment_changed(member: String) -> void:
	var cur: String = _current_token()
	if cur == "": return
	if _norm(member) == _norm(cur) or _norm(member) == _norm(_current_label()):
		var equip: Dictionary = _fetch_equip_for(cur)
		_w_val.text = _pretty_item(String(equip.get("weapon","")))
		_a_val.text = _pretty_item(String(equip.get("armor","")))
		_h_val.text = _pretty_item(String(equip.get("head","")))
		_f_val.text = _pretty_item(String(equip.get("foot","")))
		_b_val.text = _pretty_item(String(equip.get("bracelet","")))
		_rebuild_stats_grid(cur, equip)
		_rebuild_sigils(cur)
		_refresh_mind_row(cur)

func _on_sigils_changed(member: String) -> void:
	var cur: String = _current_token()
	if cur == "": return
	if _norm(member) == _norm(cur) or _norm(member) == _norm(_current_label()):
		_rebuild_sigils(cur)
		var equip: Dictionary = _fetch_equip_for(cur)
		_rebuild_stats_grid(cur, equip)
		_refresh_mind_row(cur)

# ───────────── Mind Type row ─────────────

func _refresh_mind_row(member_token: String) -> void:
	if _mind_value == null: return
	var mt: String = _get_member_mind_type(member_token)
	_mind_value.text = (mt if mt != "" else "—")

# ───────────── utils ─────────────

func _pretty_item(id: String) -> String:
	if id == "" or id == "—": return "—"
	if _eq and _eq.has_method("get_item_display_name"):
		var v: Variant = _eq.call("get_item_display_name", id)
		if typeof(v) == TYPE_STRING: return String(v)
	return id

func _fetch_equip_for(member_token: String) -> Dictionary:
	if _gs and _gs.has_method("get_member_equip"):
		var d_v: Variant = _gs.call("get_member_equip", member_token)
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			if d.has("feet") and not d.has("foot"): d["foot"] = String(d["feet"])
			for k in _SLOTS:
				if not d.has(k): d[k] = ""
			return d
	if _eq and _eq.has_method("get_member_equip"):
		var d2_v: Variant = _eq.call("get_member_equip", member_token)
		if typeof(d2_v) == TYPE_DICTIONARY:
			return d2_v as Dictionary
	return {"weapon":"","armor":"","head":"","foot":"","bracelet":""}

func _list_equippable(member_token: String, slot: String) -> PackedStringArray:
	if _eq and _eq.has_method("list_equippable"):
		var v2: Variant = _eq.call("list_equippable", member_token, slot)
		if typeof(v2) == TYPE_PACKED_STRING_ARRAY: return v2 as PackedStringArray
		if typeof(v2) == TYPE_ARRAY:
			var out2 := PackedStringArray()
			for e2 in (v2 as Array): out2.append(String(e2))
			return out2
	return PackedStringArray()

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
	var who: String = _current_token()
	if who != "" and inst.has_method("set_member"):
		inst.call("set_member", who)
	var host := get_tree().current_scene
	if host == null: host = get_tree().root
	host.add_child(inst)
