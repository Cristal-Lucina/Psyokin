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

# Controller navigation state - Clean state machine
enum NavMode { SOCKET_NAV, SKILLS_NAV }
var _nav_mode: NavMode = NavMode.SOCKET_NAV

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

	# CRITICAL: Process even when tree is paused!
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Ensure root stops input
	mouse_filter = Control.MOUSE_FILTER_STOP

	print("[SigilSkillMenu] _ready() called, member=%s" % _member)
	print("[SigilSkillMenu] Tree paused: %s, process_mode: %d" % [get_tree().paused, process_mode])

	# Debug: Add gui_input handler to track ANY mouse input
	if not gui_input.is_connected(Callable(self, "_on_gui_input")):
		gui_input.connect(Callable(self, "_on_gui_input"))

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

	set_process_input(true)
	set_process_unhandled_input(true)

	print("[SigilSkillMenu] Input processing enabled:")
	print("  - is_processing_input: %s" % is_processing_input())
	print("  - is_processing_unhandled_input: %s" % is_processing_unhandled_input())
	print("  - is_inside_tree: %s" % is_inside_tree())
	print("  - is_visible_in_tree: %s" % is_visible_in_tree())

	# Only refresh if member is already set (via set_member before adding to tree)
	if _member != "":
		print("[SigilSkillMenu] Member already set, refreshing...")
		_refresh_all()
	else:
		print("[SigilSkillMenu] Member not set yet, waiting for set_member() call")

	# Force test after next frame to ensure everything is set up
	await get_tree().process_frame
	print("[SigilSkillMenu] After process_frame:")
	print("  - is_processing_input: %s" % is_processing_input())
	print("  - is_processing_unhandled_input: %s" % is_processing_unhandled_input())
	print("  - is_visible_in_tree: %s" % is_visible_in_tree())
	print("  - mouse_filter: %d" % mouse_filter)
	print("  - Clicking anywhere should now show input logs...")

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			print("[SigilSkillMenu] GUI INPUT: Mouse button %d at (%d, %d)" % [mb.button_index, mb.position.x, mb.position.y])

func _input(e: InputEvent) -> void:
	"""Handle controller navigation for SigilSkillMenu

	Uses _input() instead of _unhandled_input() for same priority as GameMenu.

	Two-mode navigation:
	1. Socket mode: UP/DOWN to select socket, RIGHT/ACCEPT to enter skills
	2. Skills mode: UP/DOWN to select skill, ACCEPT to set active, LEFT/BACK to return to sockets
	"""
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			print("[SigilSkillMenu] _input: Mouse button %d at (%d, %d)" % [mb.button_index, mb.position.x, mb.position.y])

	# ESC or B button to close
	if e.is_action_pressed("menu_back") or (e is InputEventKey and e.is_pressed() and e.keycode == KEY_ESCAPE):
		if _nav_mode == NavMode.SOCKET_NAV:
			# Close the menu
			_on_close()
			get_viewport().set_input_as_handled()
		else:
			# Return to socket mode
			_enter_socket_mode()
			get_viewport().set_input_as_handled()
		return

	if _nav_mode == NavMode.SOCKET_NAV:
		# Socket navigation
		if e.is_action_pressed("move_up"):
			_navigate_sockets(-1)
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("move_down"):
			_navigate_sockets(1)
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("menu_accept") or e.is_action_pressed("move_right"):
			# Enter skills mode
			_enter_skills_mode()
			get_viewport().set_input_as_handled()
	else:  # NavMode.SKILLS_NAV
		# Skills navigation
		if e.is_action_pressed("move_up"):
			_navigate_skills(-1)
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("move_down"):
			_navigate_skills(1)
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("menu_accept"):
			# Set active skill
			_on_set_active()
			get_viewport().set_input_as_handled()
		elif e.is_action_pressed("move_left"):
			# Return to socket mode
			_enter_socket_mode()
			get_viewport().set_input_as_handled()


# Public
func set_member(member: String) -> void:
	print("[SigilSkillMenu] set_member(%s) called" % member)
	_member = member
	if is_inside_tree():
		_refresh_all()
	else:
		print("[SigilSkillMenu] Not in tree yet, deferring refresh")

# ───────────────── data refresh ─────────────────
func _refresh_all() -> void:
	print("[SigilSkillMenu] _refresh_all() started for member=%s" % _member)
	_refresh_capacity_and_loadout()
	print("[SigilSkillMenu] Capacity=%d, Loadout size=%d" % [_capacity, _loadout.size()])
	_refresh_sockets()

	if _selected_socket < 0:
		for i in range(min(_capacity, _loadout.size())):
			if String(_loadout[i]) != "":
				_selected_socket = i
				break
	if _selected_socket < 0 and _capacity > 0:
		_selected_socket = 0

	print("[SigilSkillMenu] Selected socket: %d" % _selected_socket)

	if _sockets and _selected_socket >= 0 and _selected_socket < _sockets.item_count:
		_sockets.select(_selected_socket)
		_on_socket_pick(_selected_socket)
	else:
		_refresh_detail("")

	print("[SigilSkillMenu] _refresh_all() completed")

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

	# Pop from panel manager if active
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr and panel_mgr.is_panel_active(self):
		print("[SigilSkillMenu] Popping from panel stack")
		panel_mgr.pop_panel()

	queue_free()

# ───────────────── helpers ─────────────────
func _get_display_name(id: String) -> String:
	if _sig and _sig.has_method("get_display_name_for"):
		var v: Variant = _sig.call("get_display_name_for", id)
		if typeof(v) == TYPE_STRING:
			return String(v)
	return id

# ───────────────── controller navigation ─────────────────
func _navigate_sockets(delta: int) -> void:
	"""Navigate UP/DOWN in sockets list"""
	if not _sockets:
		return

	var count = _sockets.item_count
	if count == 0:
		return

	var current = _sockets.get_selected_items()
	var idx = current[0] if current.size() > 0 else 0

	idx += delta
	idx = clamp(idx, 0, count - 1)

	_sockets.select(idx)
	_sockets.ensure_current_is_visible()
	_on_socket_pick(idx)
	print("[SigilSkillMenu] Socket navigation: selected index %d" % idx)

func _navigate_skills(delta: int) -> void:
	"""Navigate UP/DOWN in skills list"""
	if not _skills:
		return

	var count = _skills.item_count
	if count == 0:
		return

	var current = _skills.get_selected_items()
	var idx = current[0] if current.size() > 0 else 0

	idx += delta
	idx = clamp(idx, 0, count - 1)

	_skills.select(idx)
	_skills.ensure_current_is_visible()
	print("[SigilSkillMenu] Skills navigation: selected index %d" % idx)

func _enter_socket_mode() -> void:
	"""Switch to socket navigation mode"""
	print("[SigilSkillMenu] Entering socket mode")
	_nav_mode = NavMode.SOCKET_NAV
	if _sockets and _sockets.item_count > 0:
		var current = _sockets.get_selected_items()
		if current.size() == 0:
			_sockets.select(0)
			_on_socket_pick(0)
		_sockets.grab_focus()

func _enter_skills_mode() -> void:
	"""Switch to skills navigation mode"""
	print("[SigilSkillMenu] Entering skills mode")
	_nav_mode = NavMode.SKILLS_NAV
	if _skills and _skills.item_count > 0:
		var current = _skills.get_selected_items()
		if current.size() == 0:
			_skills.select(0)
		_skills.grab_focus()
