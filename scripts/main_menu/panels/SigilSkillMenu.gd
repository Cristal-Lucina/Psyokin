extends Control
class_name SigilSkillMenu

# Systems
var _sig: Node = null

# State
var _member: String = ""
var _capacity: int = 0
var _loadout: PackedStringArray = PackedStringArray()
var _selected_socket: int = -1
var _selected_inst: String = ""
var _skill_ids: Array[String] = []

# Scene nodes (from your .tscn)
@onready var _backdrop: ColorRect = $"Backdrop" as ColorRect
@onready var _title: Label = $"Center/Card/CardPad/MainRow/LeftColumn/HeaderRow/Title" as Label
@onready var _sub: Label = $"Center/Card/CardPad/MainRow/LeftColumn/Sub" as Label
@onready var _lv: Label = $"Center/Card/CardPad/MainRow/LeftColumn/LevelRow/LvLabel" as Label
@onready var _xpbar: ProgressBar = $"Center/Card/CardPad/MainRow/LeftColumn/LevelRow/XPBar" as ProgressBar
@onready var _xpval: Label = $"Center/Card/CardPad/MainRow/LeftColumn/LevelRow/XPValue" as Label
@onready var _sockets: ItemList = $"Center/Card/CardPad/MainRow/LeftColumn/SocketsList" as ItemList
@onready var _skills: ItemList = $"Center/Card/CardPad/MainRow/RightColumn/SkillsList" as ItemList
@onready var _btn_set: Button = $"Center/Card/CardPad/MainRow/RightColumn/ButtonsRow/BtnSetActive" as Button
@onready var _btn_close: Button = $"Center/Card/CardPad/MainRow/RightColumn/ButtonsRow/BtnClose" as Button

func _ready() -> void:
	_sig = get_node_or_null("/root/aSigilSystem")
	# Softer dimmer so the game behind isn't shouting
	if _backdrop:
		_backdrop.color = Color(0, 0, 0, 0.35)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Ensure root stops input
	mouse_filter = Control.MOUSE_FILTER_STOP

	print("[SigilSkillMenu] _ready() called, member=%s" % _member)

	# Wire signals
	if _sockets and not _sockets.item_selected.is_connected(Callable(self, "_on_socket_pick")):
		_sockets.item_selected.connect(Callable(self, "_on_socket_pick"))
		print("[SigilSkillMenu] Connected sockets.item_selected")

	# IMPORTANT: Connect skills list item selection!
	if _skills and not _skills.item_selected.is_connected(Callable(self, "_on_skill_pick")):
		_skills.item_selected.connect(Callable(self, "_on_skill_pick"))
		print("[SigilSkillMenu] Connected skills.item_selected")

	if _btn_set and not _btn_set.pressed.is_connected(Callable(self, "_on_set_active")):
		_btn_set.pressed.connect(Callable(self, "_on_set_active"))
		print("[SigilSkillMenu] Connected btn_set.pressed")

	if _btn_close and not _btn_close.pressed.is_connected(Callable(self, "_on_close")):
		_btn_close.pressed.connect(Callable(self, "_on_close"))
		print("[SigilSkillMenu] Connected btn_close.pressed")

	set_process_unhandled_input(true)
	_refresh_all()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.is_pressed() and e.keycode == KEY_ESCAPE:
		_on_close()

# Public
func set_member(member: String) -> void:
	_member = member
	_refresh_all()

# ───────────────── data refresh ─────────────────
func _refresh_all() -> void:
	_refresh_capacity_and_loadout()
	_refresh_sockets()

	if _selected_socket < 0:
		for i in range(min(_capacity, _loadout.size())):
			if String(_loadout[i]) != "":
				_selected_socket = i
				break
	if _selected_socket < 0 and _capacity > 0:
		_selected_socket = 0

	if _sockets and _selected_socket >= 0 and _selected_socket < _sockets.item_count:
		_sockets.select(_selected_socket)
		_on_socket_pick(_selected_socket)
	else:
		_refresh_detail("")

func _refresh_capacity_and_loadout() -> void:
	_capacity = 0
	_loadout.clear()

	if _sig:
		if _sig.has_method("get_capacity"):
			var cap_v: Variant = _sig.call("get_capacity", _member)
			_capacity = int(cap_v)

		if _sig.has_method("get_loadout"):
			var ld_v: Variant = _sig.call("get_loadout", _member)
			if typeof(ld_v) == TYPE_PACKED_STRING_ARRAY:
				_loadout = ld_v as PackedStringArray
			elif typeof(ld_v) == TYPE_ARRAY:
				var tmp: PackedStringArray = PackedStringArray()
				for e in (ld_v as Array):
					tmp.append(String(e))
				_loadout = tmp

	while _loadout.size() < _capacity:
		_loadout.append("")

func _refresh_sockets() -> void:
	if _sockets == null:
		return

	_sockets.clear()
	var used: int = 0
	for i in range(_capacity):
		var inst_id: String = (String(_loadout[i]) if i < _loadout.size() else "")
		var disp: String = "(empty)"
		if inst_id != "":
			used += 1
			disp = _sigil_label(inst_id)
		_sockets.add_item("%d) %s" % [i + 1, disp])

	if _title:
		_title.text = "Sigil Skills"
	if _sub:
		_sub.text = "(%d/%d)" % [used, _capacity]

func _sigil_label(inst_id: String) -> String:
	var base_id := inst_id
	if _sig and _sig.has_method("get_base_from_instance"):
		base_id = String(_sig.call("get_base_from_instance", inst_id))

	var name_txt := base_id
	if _sig and _sig.has_method("get_display_name_for"):
		var n_v: Variant = _sig.call("get_display_name_for", base_id)
		if typeof(n_v) == TYPE_STRING:
			name_txt = String(n_v)

	var lvl := 1
	if _sig and _sig.has_method("get_instance_level"):
		lvl = int(_sig.call("get_instance_level", inst_id))

	var star := ""
	if _sig and _sig.has_method("get_active_skill_name_for_instance"):
		var act_v: Variant = _sig.call("get_active_skill_name_for_instance", inst_id)
		if typeof(act_v) == TYPE_STRING and String(act_v).strip_edges() != "":
			star = "  —  ★ " + String(act_v)

	return "%s  (Lv %d)%s" % [name_txt, lvl, star]


func _on_socket_pick(index: int) -> void:
	print("[SigilSkillMenu] _on_socket_pick(%d)" % index)
	_selected_socket = index
	_selected_inst = ""
	if index >= 0 and index < _loadout.size():
		_selected_inst = String(_loadout[index])
	print("[SigilSkillMenu] Selected sigil instance: %s" % _selected_inst)
	_refresh_detail(_selected_inst)

func _on_skill_pick(index: int) -> void:
	print("[SigilSkillMenu] _on_skill_pick(%d)" % index)
	if index >= 0 and index < _skill_ids.size():
		print("[SigilSkillMenu] Selected skill: %s" % _skill_ids[index])

func _refresh_detail(inst_id: String) -> void:
	if _skills:
		_skills.clear()
	_skill_ids.clear()

	if inst_id == "":
		if _lv:     _lv.text = "Lv —"
		if _xpbar:  _xpbar.value = 0
		if _xpval:  _xpval.text = "0%"
		if _btn_set: _btn_set.disabled = true
		return

	# Level + XP (show current XP and to-next)
	var lvl: int = 1
	var pct: int = 0
	var xp: int = 0
	var to_next: int = 0

	if _sig:
		if _sig.has_method("get_instance_level"):
			var lvl_v: Variant = _sig.call("get_instance_level", inst_id)
			lvl = int(lvl_v)

		if _sig.has_method("get_instance_progress"):
			var pr_v: Variant = _sig.call("get_instance_progress", inst_id)
			if typeof(pr_v) == TYPE_DICTIONARY:
				var d: Dictionary = pr_v as Dictionary
				if d.has("pct"):     pct = int(clamp(float(d["pct"]), 0.0, 100.0))
				if d.has("xp"):      xp = int(d["xp"])
				if d.has("to_next"): to_next = int(d["to_next"])

	if _lv:
		_lv.text = "Lv %d" % lvl
	if _xpbar:
		_xpbar.value = pct
	if _xpval:
		_xpval.text = ("MAX" if to_next <= 0 else "%d / %d (%d%%)" % [xp, to_next, pct])

	# Skills
	var active_id: String = ""
	if _sig and _sig.has_method("get_active_skill_id_for_instance"):
		var act_id_v: Variant = _sig.call("get_active_skill_id_for_instance", inst_id)
		if typeof(act_id_v) == TYPE_STRING:
			active_id = String(act_id_v)
	elif _sig and _sig.has_method("get_active_skill_name_for_instance"):
		active_id = String(_sig.call("get_active_skill_name_for_instance", inst_id))

	var unlocked: PackedStringArray = PackedStringArray()
	if _sig and _sig.has_method("list_unlocked_skills"):
		var un_v: Variant = _sig.call("list_unlocked_skills", inst_id)
		if typeof(un_v) == TYPE_PACKED_STRING_ARRAY:
			unlocked = un_v as PackedStringArray
		elif typeof(un_v) == TYPE_ARRAY:
			for e in (un_v as Array):
				unlocked.append(String(e))
	else:
		unlocked = _fallback_unlocked_for_level(lvl)

	for sid in unlocked:
		var disp: String = sid
		if _sig and _sig.has_method("get_skill_display_name"):
			var n_v: Variant = _sig.call("get_skill_display_name", sid)
			if typeof(n_v) == TYPE_STRING:
				disp = String(n_v)
		if active_id != "" and sid == active_id:
			disp = "★ " + disp
		_skill_ids.append(sid)
		if _skills:
			_skills.add_item(disp)

	if _skills and active_id != "":
		for i in range(_skill_ids.size()):
			if _skill_ids[i] == active_id:
				_skills.select(i)
				break

	if _btn_set:
		_btn_set.disabled = (_skills == null or _skills.item_count == 0)

func _fallback_unlocked_for_level(level: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("Skill I")
	if level >= 3: out.append("Skill II")
	if level >= 5: out.append("Skill III")
	return out

# ───────────────── actions ─────────────────
func _on_set_active() -> void:
	print("[SigilSkillMenu] _on_set_active() called")
	if _skills == null or _selected_inst == "" or _sig == null:
		print("[SigilSkillMenu] Validation failed: skills=%s, inst=%s, sig=%s" % [_skills != null, _selected_inst, _sig != null])
		return
	var picks: PackedInt32Array = _skills.get_selected_items()
	if picks.size() == 0:
		print("[SigilSkillMenu] No skill selected")
		return
	var idx: int = picks[0]
	if idx < 0 or idx >= _skill_ids.size():
		print("[SigilSkillMenu] Invalid skill index: %d" % idx)
		return
	var chosen: String = _skill_ids[idx]
	print("[SigilSkillMenu] Setting active skill: %s for instance: %s" % [chosen, _selected_inst])

	var ok: bool = false
	if _sig.has_method("set_active_skill_for_instance"):
		ok = bool(_sig.call("set_active_skill_for_instance", _selected_inst, chosen))
		print("[SigilSkillMenu] set_active_skill_for_instance result: %s" % ok)
	elif _sig.has_method("set_active_skill"):
		ok = bool(_sig.call("set_active_skill", _selected_inst, chosen))
		print("[SigilSkillMenu] set_active_skill result: %s" % ok)
	if not ok and _sig.has_method("set_active_skill_member") and _member != "" and _selected_socket >= 0:
		ok = bool(_sig.call("set_active_skill_member", _member, _selected_socket, chosen))
		print("[SigilSkillMenu] set_active_skill_member result: %s" % ok)

	_refresh_detail(_selected_inst)

	if _member != "" and _sig and _sig.has_signal("loadout_changed"):
		_sig.emit_signal("loadout_changed", _member)

func _on_close() -> void:
	print("[SigilSkillMenu] _on_close() called - closing menu")
	queue_free()

# ───────────────── helpers ─────────────────
func _get_display_name(id: String) -> String:
	if _sig and _sig.has_method("get_display_name_for"):
		var v: Variant = _sig.call("get_display_name_for", id)
		if typeof(v) == TYPE_STRING:
			return String(v)
	return id
