extends Control
class_name SigilSkillMenu

# ------------------------------ robust node lookup ----------------------------
func _find_node_of_type(root: Node, type_name: String, wanted_name: String) -> Node:
	var by_unique: Node = root.get_node_or_null("%" + wanted_name)
	if by_unique != null:
		return by_unique
	var exact: Node = root.find_child(wanted_name, true, false)
	if exact != null:
		return exact
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var cur: Node = stack.pop_back() as Node
		var cls: String = cur.get_class()
		if cls == type_name \
		or (type_name == "ItemList" and cur is ItemList) \
		or (type_name == "Label" and cur is Label) \
		or (type_name == "TextureProgressBar" and cur is TextureProgressBar) \
		or (type_name == "Button" and cur is Button):
			if wanted_name == "" or String(cur.name).to_lower().find(wanted_name.to_lower()) >= 0:
				return cur
		var children: Array = cur.get_children()
		for c in children:
			if c is Node:
				stack.append(c)
	return null

# ------------------------------ scene refs ------------------------------------
var _title_lbl      : Label               = null
var _sub_lbl        : Label               = null
var _lv_label       : Label               = null
var _xp_bar         : TextureProgressBar  = null
var _xp_value       : Label               = null
var _sockets_il     : ItemList            = null
var _skills_il      : ItemList            = null
var _btn_set_active : Button              = null
var _btn_close      : Button              = null

# systems
var _sig : Node = null

# state
var _member          : String            = ""
var _capacity        : int               = 0
var _sockets         : PackedStringArray = PackedStringArray()
var _selected_socket : int               = -1
var _selected_inst   : String            = ""
var _skill_ids       : Array[String]     = []

# ------------------------------ lifecycle -------------------------------------
func _ready() -> void:
	_sig = get_node_or_null("/root/aSigilSystem")

	_title_lbl      = _find_node_of_type(self, "Label",              "Title")        as Label
	_sub_lbl        = _find_node_of_type(self, "Label",              "Sub")          as Label
	_lv_label       = _find_node_of_type(self, "Label",              "LvLabel")      as Label
	_xp_bar         = _find_node_of_type(self, "TextureProgressBar", "XPBar")        as TextureProgressBar
	_xp_value       = _find_node_of_type(self, "Label",              "XPValue")      as Label
	_sockets_il     = _find_node_of_type(self, "ItemList",           "SocketsList")  as ItemList
	_skills_il      = _find_node_of_type(self, "ItemList",           "SkillsList")   as ItemList
	_btn_set_active = _find_node_of_type(self, "Button",             "BtnSetActive") as Button
	_btn_close      = _find_node_of_type(self, "Button",             "BtnClose")     as Button

	if _btn_close and not _btn_close.pressed.is_connected(_on_close):
		_btn_close.pressed.connect(_on_close)
	if _sockets_il and not _sockets_il.item_selected.is_connected(_on_socket_pick):
		_sockets_il.item_selected.connect(_on_socket_pick)
	if _btn_set_active and not _btn_set_active.pressed.is_connected(_on_set_active):
		_btn_set_active.pressed.connect(_on_set_active)

	set_process_unhandled_input(true)
	_refresh_all()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and event.keycode == KEY_ESCAPE:
		_on_close()

# ------------------------------ public API ------------------------------------
func set_member(member: String) -> void:
	_member = member
	_refresh_all()

# ------------------------------ refresh pipeline ------------------------------
func _refresh_all() -> void:
	_refresh_capacity_and_loadout()
	_refresh_sockets()

	if _selected_socket < 0:
		for i in range(min(_capacity, _sockets.size())):
			if String(_sockets[i]) != "":
				_selected_socket = i
				break
	if _selected_socket < 0 and _capacity > 0:
		_selected_socket = 0

	if _sockets_il and _selected_socket >= 0 and _selected_socket < _sockets_il.item_count:
		_sockets_il.select(_selected_socket)
		_on_socket_pick(_selected_socket)
	else:
		_refresh_detail("")

func _refresh_capacity_and_loadout() -> void:
	_capacity = 0
	_sockets.clear()

	if _sig:
		if _sig.has_method("get_capacity"):
			var cap_v: Variant = _sig.call("get_capacity", _member)
			_capacity = int(cap_v)
		if _sig.has_method("get_loadout"):
			var ld_v: Variant = _sig.call("get_loadout", _member)
			if typeof(ld_v) == TYPE_PACKED_STRING_ARRAY:
				_sockets = (ld_v as PackedStringArray)
			elif typeof(ld_v) == TYPE_ARRAY:
				var tmp: PackedStringArray = PackedStringArray()
				for e in (ld_v as Array):
					tmp.append(String(e))
				_sockets = tmp

	while _sockets.size() < _capacity:
		_sockets.append("")

func _refresh_sockets() -> void:
	if _sockets_il == null:
		return

	_sockets_il.clear()

	var used: int = 0
	for i in range(_capacity):
		var inst_id: String = (String(_sockets[i]) if i < _sockets.size() else "")
		var disp: String = "(empty)"
		if inst_id != "":
			used += 1
			disp = _get_display_name(inst_id)
		_sockets_il.add_item("%d) %s" % [i + 1, disp])

	if _title_lbl:
		_title_lbl.text = "Sigil Skills"
	if _sub_lbl:
		_sub_lbl.text = "(%d/%d)" % [used, _capacity]

func _on_socket_pick(index: int) -> void:
	_selected_socket = index
	_selected_inst = ""
	if index >= 0 and index < _sockets.size():
		_selected_inst = String(_sockets[index])
	_refresh_detail(_selected_inst)

func _refresh_detail(inst_id: String) -> void:
	if _skills_il:
		_skills_il.clear()
	_skill_ids.clear()

	if inst_id == "":
		if _lv_label:  _lv_label.text = "Lv —"
		if _xp_bar:    _xp_bar.value = 0
		if _xp_value:  _xp_value.text = "0%"
		if _btn_set_active: _btn_set_active.disabled = true
		return

	var lvl: int = 1
	var pct: int = 0

	if _sig:
		if _sig.has_method("get_instance_level"):
			var lvl_v: Variant = _sig.call("get_instance_level", inst_id)
			lvl = int(lvl_v)

		if _sig.has_method("get_instance_progress"):
			var pr: Variant = _sig.call("get_instance_progress", inst_id)
			if typeof(pr) == TYPE_DICTIONARY:
				var d: Dictionary = pr
				if d.has("pct"):
					pct = int(clamp(float(d["pct"]), 0.0, 100.0))

	if _lv_label:
		_lv_label.text = "Lv %d" % lvl
	if _xp_bar:
		_xp_bar.value = pct
	if _xp_value:
		_xp_value.text = "%d%%" % pct

	var active_id: String = ""
	if _sig and _sig.has_method("get_active_skill_id_for_instance"):
		var act_v: Variant = _sig.call("get_active_skill_id_for_instance", inst_id)
		if typeof(act_v) == TYPE_STRING:
			active_id = String(act_v)

	# unlocked list comes pre-gated from SigilSystem
	var unlocked: PackedStringArray = PackedStringArray()
	if _sig and _sig.has_method("list_unlocked_skills"):
		var un_v: Variant = _sig.call("list_unlocked_skills", inst_id)
		if typeof(un_v) == TYPE_PACKED_STRING_ARRAY:
			unlocked = un_v as PackedStringArray
		elif typeof(un_v) == TYPE_ARRAY:
			for e in (un_v as Array):
				unlocked.append(String(e))

	for sid in unlocked:
		var disp: String = sid
		if _sig and _sig.has_method("get_skill_display_name"):
			var n_v: Variant = _sig.call("get_skill_display_name", sid)
			if typeof(n_v) == TYPE_STRING:
				disp = String(n_v)
		if sid == active_id:
			disp = "★ " + disp
		_skill_ids.append(sid)
		if _skills_il:
			_skills_il.add_item(disp)

	if _skills_il and active_id != "":
		for i in range(_skill_ids.size()):
			if _skill_ids[i] == active_id:
				_skills_il.select(i)
				break

	if _btn_set_active:
		_btn_set_active.disabled = (_skills_il == null or _skills_il.item_count == 0)

# ------------------------------ actions ---------------------------------------
func _on_set_active() -> void:
	if _skills_il == null or _selected_inst == "" or _sig == null:
		return
	var picks: PackedInt32Array = _skills_il.get_selected_items()
	if picks.size() == 0:
		return
	var idx: int = picks[0]
	if idx < 0 or idx >= _skill_ids.size():
		return
	var chosen: String = _skill_ids[idx]

	var ok: bool = false
	if _sig.has_method("set_active_skill_for_instance"):
		ok = bool(_sig.call("set_active_skill_for_instance", _selected_inst, chosen))
	elif _sig.has_method("set_active_skill"):
		ok = bool(_sig.call("set_active_skill", _selected_inst, chosen))
	if not ok and _sig.has_method("set_active_skill_member") and _member != "" and _selected_socket >= 0:
		ok = bool(_sig.call("set_active_skill_member", _member, _selected_socket, chosen))

	_refresh_detail(_selected_inst)

	if _member != "" and _sig and _sig.has_signal("loadout_changed"):
		_sig.emit_signal("loadout_changed", _member)

func _on_close() -> void:
	queue_free()

# ------------------------------ helpers ---------------------------------------
func _get_display_name(id: String) -> String:
	if _sig and _sig.has_method("get_display_name_for"):
		var v: Variant = _sig.call("get_display_name_for", id)
		if typeof(v) == TYPE_STRING:
			return String(v)
	return id
