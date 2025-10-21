extends Control
class_name DormsPanel

# Scene hooks
@onready var _grid_holder  : VBoxContainer  = $Root/Left/Scroll/List
@onready var _detail       : RichTextLabel  = $Root/Right/Detail
@onready var _refresh_btn  : Button         = $Root/Left/Header/RefreshBtn
@onready var _filter       : OptionButton   = $Root/Left/Filter

# Right-side controls created in code
var _common_box  : VBoxContainer = null
var _reassign_btn: Button        = null
var _reset_btn   : Button        = null
var _accept_btn  : Button        = null

# State
var _selected_room: String = ""
var _selected_person: String = ""  # actor_id (from Common Room)
var _group: ButtonGroup = null

# Track rooms consumed during this reassignment session (turn them red)
var _used_rooms: Dictionary = {}  # room_id -> true

# Local mirror of DormsSystem.RoomVisual values (keep in sync)
const VIS_EMPTY     := 0
const VIS_OCCUPIED  := 1
const VIS_STAGED    := 2
const VIS_LOCKED    := 3

func _ds() -> Node:
	return get_node_or_null("/root/aDormSystem")

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _detail != null:
		_detail.bbcode_enabled = true

	if _filter != null and _filter.item_count == 0:
		_filter.add_item("Placements", 0)
		_filter.add_item("Reassignment", 1)
		_filter.select(0)
		if not _filter.item_selected.is_connected(_on_filter_changed):
			_filter.item_selected.connect(_on_filter_changed)

	if _refresh_btn != null and not _refresh_btn.pressed.is_connected(_rebuild):
		_refresh_btn.pressed.connect(_rebuild)

	var ds: Node = _ds()
	if ds != null:
		if ds.has_signal("dorms_changed"):
			ds.connect("dorms_changed", Callable(self, "_on_model_bumped"))
		if ds.has_signal("plan_changed"):
			ds.connect("plan_changed", Callable(self, "_on_model_bumped"))
		if ds.has_signal("saturday_applied"):
			ds.connect("saturday_applied", func(_snap: Dictionary) -> void: _on_model_bumped())

	_ensure_right_controls()
	_rebuild()

func _on_model_bumped() -> void:
	_rebuild()

func _on_filter_changed(_ix: int) -> void:
	# Leaving Reassignment view? clear our local "used" paint
	if _filter and _filter.get_selected_id() != 1:
		_used_rooms.clear()
	_rebuild()

# ─────────────────────────────────────────────────────────────
# Right controls
# ─────────────────────────────────────────────────────────────
func _ensure_right_controls() -> void:
	if _common_box != null:
		return
	if _detail == null:
		return
	var holder: Node = _detail.get_parent()
	if holder == null:
		return

	var sep := HSeparator.new()
	holder.add_child(sep)

	var title := Label.new()
	title.text = "Common Room"
	holder.add_child(title)

	_common_box = VBoxContainer.new()
	_common_box.add_theme_constant_override("separation", 4)
	holder.add_child(_common_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_reassign_btn = Button.new(); _reassign_btn.text = "Room Reassignment"
	_reset_btn    = Button.new(); _reset_btn.text    = "Reset Placement"
	_accept_btn   = Button.new(); _accept_btn.text   = "Accept Plan (Saturday)"
	row.add_child(_reassign_btn); row.add_child(_reset_btn); row.add_child(_accept_btn)
	holder.add_child(row)

	if not _reassign_btn.pressed.is_connected(_on_reassign_pressed):
		_reassign_btn.pressed.connect(_on_reassign_pressed)
	if not _reset_btn.pressed.is_connected(_on_reset_pressed):
		_reset_btn.pressed.connect(_on_reset_pressed)
	if not _accept_btn.pressed.is_connected(_on_accept_pressed):
		_accept_btn.pressed.connect(_on_accept_pressed)

# ─────────────────────────────────────────────────────────────
# Build grid + common list + summary
# ─────────────────────────────────────────────────────────────
func _rebuild() -> void:
	_build_grid()
	_build_common_list()
	_update_detail(_selected_room)
	_refresh_accept_state()

func _build_grid() -> void:
	for c in _grid_holder.get_children():
		c.queue_free()

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_grid_holder.add_child(grid)

	_group = ButtonGroup.new()
	_group.allow_unpress = false

	var ds: Node = _ds()
	if ds == null:
		return

	var ids_v: Variant = ds.call("list_rooms")
	var ids: PackedStringArray = (ids_v if typeof(ids_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
	for rid in ids:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_ALL
		b.text = rid
		_apply_room_visual(b, rid)
		b.pressed.connect(func(room_id := rid) -> void:
			_selected_room = room_id
			_update_detail(room_id)
			if _selected_person != "":
				_try_place_selected(room_id)
		)
		if _selected_room == rid:
			b.button_pressed = true
		grid.add_child(b)

	# Summary under the grid
	var summary := RichTextLabel.new()
	summary.bbcode_enabled = false
	summary.fit_content = true
	summary.scroll_active = false
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("normal_font_size", 12)
	summary.text = _build_summary_text()
	_grid_holder.add_child(summary)

func _build_summary_text() -> String:
	var ds: Node = _ds()
	if ds == null:
		return ""
	var mode: int = 0
	if _filter:
		mode = _filter.get_selected_id()

	if mode == 0:
		# Placements: show current occupant of each room
		var out := PackedStringArray()
		var ids: PackedStringArray = ds.call("list_rooms")
		for i in range(ids.size()):
			var rid2: String = ids[i]
			var r: Dictionary = ds.call("get_room", rid2)
			var who: String = String(r.get("occupant", ""))
			var disp_name: String = (String(ds.call("display_name", who)) if who != "" else "— empty —")
			out.append("%s : %s" % [rid2, disp_name])
		return _join_psa(out, "\n")
	else:
		# Reassignment preview (prefer explicit API)
		if ds.has_method("list_upcoming_reassignments"):
			var rows_v: Variant = ds.call("list_upcoming_reassignments")
			if typeof(rows_v) == TYPE_ARRAY:
				var lines := PackedStringArray()
				var arr: Array = rows_v
				for i in range(arr.size()):
					var row_v: Variant = arr[i]
					if typeof(row_v) == TYPE_DICTIONARY:
						var d: Dictionary = row_v
						var nm: String = String(d.get("name",""))
						var fr: String = String(d.get("from",""))
						var to: String = String(d.get("to",""))
						if nm != "" and fr != "" and to != "":
							lines.append("%s moving from %s into %s" % [nm, fr, to])
						elif nm != "" and fr != "":
							lines.append("%s moving from %s (target TBD)" % [nm, fr])
						elif nm != "" and to != "":
							lines.append("%s moving into %s" % [nm, to])
				return _join_psa(lines, "\n")
		# Fallback discovery
		var lines2 := PackedStringArray()
		var staged: Array[String] = _collect_staged_members(ds)
		if staged.size() == 0:
			return "— none —"
		for i2 in range(staged.size()):
			var aid: String = staged[i2]
			var from_room: String = _find_current_room_of(ds, aid)
			var to_room: String = _staged_target_for(ds, aid)
			var nm2: String = String(ds.call("display_name", aid))
			if from_room != "" and to_room != "":
				lines2.append("%s moving from %s into %s" % [nm2, from_room, to_room])
			elif from_room != "":
				lines2.append("%s moving from %s (target TBD)" % [nm2, from_room])
			elif to_room != "":
				lines2.append("%s moving into %s" % [nm2, to_room])
			else:
				lines2.append("%s — staged (details TBD)" % nm2)
		return _join_psa(lines2, "\n")

# Robust staged-members discovery
func _collect_staged_members(ds: Node) -> Array[String]:
	var out: Array[String] = []
	for m in ["get_all_staged_members","list_staged_members","get_staged_members"]:
		if ds.has_method(m):
			var v: Variant = ds.call(m)
			if typeof(v) == TYPE_ARRAY:
				var arr: Array = v
				for i in range(arr.size()): out.append(String(arr[i]))
			elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
				var psa: PackedStringArray = v
				for j in range(psa.size()): out.append(String(psa[j]))
			if out.size() > 0:
				return out
	# Fallback: any occupant currently marked staged
	var ids: PackedStringArray = ds.call("list_rooms")
	for i2 in range(ids.size()):
		var rid: String = ids[i2]
		var r: Dictionary = ds.call("get_room", rid)
		var who: String = String(r.get("occupant",""))
		if who != "" and ds.has_method("is_staged") and bool(ds.call("is_staged", who)) and not out.has(who):
			out.append(who)
	return out

# Where is a member right now?
func _find_current_room_of(ds: Node, aid: String) -> String:
	var ids: PackedStringArray = ds.call("list_rooms")
	for i in range(ids.size()):
		var rid: String = ids[i]
		var r: Dictionary = ds.call("get_room", rid)
		if String(r.get("occupant","")) == aid:
			return rid
	return ""

# Try very hard to find the staged target for a member
func _staged_target_for(ds: Node, aid: String) -> String:
	for fn in ["get_staged_target_for","staged_target_for","get_plan_target_for"]:
		if ds.has_method(fn):
			var v: Variant = ds.call(fn, aid)
			if typeof(v) == TYPE_STRING and String(v) != "":
				return String(v)
	for fn2 in ["get_staged_assignments","staged_assignments","get_staged_places","list_staged_assignments"]:
		if ds.has_method(fn2):
			var v2: Variant = ds.call(fn2)
			if typeof(v2) == TYPE_DICTIONARY and (v2 as Dictionary).has(aid):
				return String((v2 as Dictionary)[aid])
	var ids: PackedStringArray = ds.call("list_rooms")
	for i2 in range(ids.size()):
		var rid2: String = ids[i2]
		var r2: Dictionary = ds.call("get_room", rid2)
		for k in r2.keys():
			var key: String = String(k).to_lower()
			if key.find("stage") != -1 or key.find("plan") != -1 or key.find("incoming") != -1:
				var val: Variant = r2[k]
				if typeof(val) == TYPE_STRING and String(val) == aid:
					return rid2
				elif typeof(val) == TYPE_DICTIONARY:
					var d3: Dictionary = val
					for inner in ["member","id","who","occupant"]:
						if d3.has(inner) and typeof(d3[inner]) == TYPE_STRING and String(d3[inner]) == aid:
							return rid2
	return ""

func _build_common_list() -> void:
	if _common_box == null:
		return
	for c in _common_box.get_children():
		c.queue_free()

	var ds: Node = _ds()
	if ds == null:
		return

	var list_v: Variant = ds.call("get_common")
	var list_psa: PackedStringArray = (list_v if typeof(list_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
	if list_psa.size() == 0:
		var empty := Label.new()
		empty.text = "— none —"
		_common_box.add_child(empty)
		return

	for i in range(list_psa.size()):
		var aid: String = list_psa[i]
		var btn := Button.new()
		btn.text = String(ds.call("display_name", aid))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.button_pressed = (_selected_person == aid)
		btn.pressed.connect(func(id := aid) -> void:
			_selected_person = ("" if _selected_person == id else id)
			_build_common_list()
		)
		_common_box.add_child(btn)

# ─────────────────────────────────────────────────────────────
# Detail (right)
# ─────────────────────────────────────────────────────────────
func _update_detail(room_id: String) -> void:
	if _detail == null:
		return
	var ds: Node = _ds()
	if ds == null:
		_detail.text = "[i]Dorm system missing.[/i]"
		return

	var r_v: Variant = ds.call("get_room", room_id)
	if typeof(r_v) != TYPE_DICTIONARY:
		_detail.text = "[i]Select a room.[/i]"
		return
	var r: Dictionary = r_v
	if r.is_empty():
		_detail.text = "[i]Select a room.[/i]"
		return

	var room_name: String = String(r.get("name", room_id))
	var who: String = ""
	var occ_v: Variant = r.get("occupant","")
	if typeof(occ_v) == TYPE_STRING:
		who = String(occ_v)

	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % room_name)
	lines.append("")

	var occ_line := "Occupant: [b]%s[/b]" % (String(ds.call("display_name", who)) if who != "" else "— empty —")
	lines.append(occ_line)

	# If a plan is locked and this room is involved, show red banner
	if ds.has_method("room_in_locked_plan") and bool(ds.call("room_in_locked_plan", room_id)):
		lines.append("[color=#d33](Room Reassignments happening on Saturday)[/color]")

	lines.append("\n[b]Neighbors[/b]:")
	var neigh_v: Variant = ds.call("room_neighbors", room_id)
	var neigh: PackedStringArray = (neigh_v if typeof(neigh_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
	for i in range(neigh.size()):
		var nid: String = neigh[i]
		var nocc_v: Variant = ds.call("occupants_of", nid)
		var nocc_psa: PackedStringArray = (nocc_v if typeof(nocc_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
		var nwho: String = (nocc_psa[0] if nocc_psa.size() > 0 else "")
		if nwho == "":
			lines.append("• %s — empty" % nid)
		else:
			var label_status: String = "Neutral"
			if ds.has_method("is_pair_hidden") and who != "" and nwho != "" and bool(ds.call("is_pair_hidden", who, nwho)):
				label_status = "Unknown (reveals Saturday)"
			elif ds.has_method("get_pair_status") and who != "" and nwho != "":
				label_status = String(ds.call("get_pair_status", who, nwho))
			lines.append("• %s — %s with [b]%s[/b]" % [nid, label_status, String(ds.call("display_name", nwho))])

	_detail.text = _join_psa(lines, "\n")

# ─────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────
func _on_reassign_pressed() -> void:
	var ds: Node = _ds()
	if ds == null:
		return

	if _selected_room == "":
		return
	var r: Dictionary = ds.call("get_room", _selected_room)
	var curr: String = String(r.get("occupant",""))
	if curr == "":
		return

	var staged_now: bool = false
	if ds.has_method("is_staged"):
		var staged_now_v: Variant = ds.call("is_staged", curr)
		staged_now = bool(staged_now_v)

	if staged_now:
		if ds.has_method("unstage_vacate_room"):
			ds.call("unstage_vacate_room", _selected_room)
	else:
		var who_name: String = String(ds.call("display_name", curr))
		var ok: bool = await _ask_confirm("Are you sure you want to reassign %s's room?" % who_name)
		if not ok:
			return
		if ds.has_method("stage_vacate_room"):
			var res: Dictionary = ds.call("stage_vacate_room", _selected_room)
			if not bool(res.get("ok", false)):
				_show_toast(String(res.get("reason","Cannot stage.")))

	# Refresh everything (summary/common/accept state)
	_rebuild()

func _on_reset_pressed() -> void:
	var ds: Node = _ds()
	if ds == null:
		return
	if ds.has_method("stage_reset_plan"):
		ds.call("stage_reset_plan")
	elif ds.has_method("reset_placement"):
		ds.call("reset_placement")
	_selected_person = ""
	_used_rooms.clear()  # clear our session paint
	_rebuild()

func _on_accept_pressed() -> void:
	var ds: Node = _ds()
	if ds == null:
		return

	if not _compute_can_accept():
		_show_toast("Pick a target room for each staged member before accepting.")
		return

	# Lock the plan for Saturday (system executes on calendar tick)
	var res: Dictionary = {}
	if ds.has_method("accept_plan_for_saturday"):
		res = ds.call("accept_plan_for_saturday")
	elif ds.has_method("stage_accept_plan"):
		res = ds.call("stage_accept_plan")
	elif ds.has_method("lock_plan_for_saturday"):
		res = ds.call("lock_plan_for_saturday")

	if typeof(res) == TYPE_DICTIONARY and not bool(res.get("ok", false)):
		_show_toast(String(res.get("reason","Cannot accept plan.")))
	else:
		_show_toast("Plan locked. Changes will apply on Saturday.")

	_used_rooms.clear()  # new section starts after lock
	_rebuild()

# Place selected person into a room (handles staged & immediate)
func _try_place_selected(room_id: String) -> void:
	var ds: Node = _ds()
	if ds == null or _selected_person == "":
		return

	var staged: bool = false
	if ds.has_method("is_staged"):
		var staged_v: Variant = ds.call("is_staged", _selected_person)
		staged = bool(staged_v)

	if staged:
		var who_name: String = String(ds.call("display_name", _selected_person))
		var ok: bool = await _ask_confirm("Assign %s to room %s?" % [who_name, room_id])
		if not ok:
			return
		var res: Dictionary = {}
		for fn in ["stage_assign","stage_set_target","pick_room_for"]:
			if ds.has_method(fn):
				res = ds.call(fn, _selected_person, room_id)
				break
		if typeof(res) == TYPE_DICTIONARY and not bool(res.get("ok", false)):
			_show_toast(String(res.get("reason","Cannot place.")))
			return
		_selected_person = ""
		_show_toast("Placement staged.")

		# mark room red only in reassignment mode
		if _filter and _filter.get_selected_id() == 1:
			_used_rooms[room_id] = true
	else:
		var who_name2: String = String(ds.call("display_name", _selected_person))
		var ok2: bool = await _ask_confirm("Assign %s to room %s?" % [who_name2, room_id])
		if not ok2:
			return
		if ds.has_method("assign_now_from_common"):
			var res2: Dictionary = ds.call("assign_now_from_common", _selected_person, room_id)
			if not bool(res2.get("ok", false)):
				_show_toast(String(res2.get("reason","Cannot assign.")))
				return
			_selected_person = ""
			_show_toast("Assigned.")

	# One rebuild to refresh grid, summary, common list, and details
	_rebuild()

# ─────────────────────────────────────────────────────────────
# Visual helpers
# ─────────────────────────────────────────────────────────────
func _apply_room_visual(btn: Button, room_id: String) -> void:
	var ds: Node = _ds()
	if ds == null:
		return
	var state: int = int(ds.call("get_room_visual", room_id))

	var col := Color(0.15, 0.17, 0.20) # default
	if state == VIS_EMPTY:
		col = Color(0.12, 0.30, 0.12) # green (empty)
	elif state == VIS_OCCUPIED:
		col = Color(0.12, 0.18, 0.32) # blue (occupied)
	elif state == VIS_STAGED:
		col = Color(0.40, 0.34, 0.08) # yellow (selected/staged)
	elif state == VIS_LOCKED:
		col = Color(0.38, 0.10, 0.10) # red (locked/kept)

	# Only in Reassignment mode do we force red for rooms already used this session
	if _filter and _filter.get_selected_id() == 1:
		if ds.has_method("has_pending_plan") and bool(ds.call("has_pending_plan")) and _used_rooms.has(room_id):
			col = Color(0.75, 0.15, 0.15)

	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.set_border_width_all(1)
	sb.border_color = col.darkened(0.35)

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)

func _update_tile_colors() -> void:
	var ds: Node = _ds()
	if ds == null:
		return
	var ids: PackedStringArray = ds.call("list_rooms")
	var grid: Node = _grid_holder.get_child(0)
	if grid == null:
		return
	var i: int = 0
	for child in grid.get_children():
		if child is Button and i < ids.size():
			_apply_room_visual(child, ids[i])
			i += 1

# ─────────────────────────────────────────────────────────────
# Accept button state
# ─────────────────────────────────────────────────────────────
func _refresh_accept_state() -> void:
	if _accept_btn == null:
		return
	_accept_btn.disabled = not _compute_can_accept()

func _compute_can_accept() -> bool:
	var ds: Node = _ds()
	if ds == null:
		return false
	# If the system exposes an explicit "locked" flag, don't allow
	if ds.has_method("is_plan_locked") and bool(ds.call("is_plan_locked")):
		return false
	# Can accept if there's at least one staged target
	if ds.has_method("staged_assign_size"):
		return int(ds.call("staged_assign_size")) > 0
	if ds.has_method("get_staged_assignments"):
		var d_v: Variant = ds.call("get_staged_assignments")
		if typeof(d_v) == TYPE_DICTIONARY:
			return (d_v as Dictionary).size() > 0
	return false

# ─────────────────────────────────────────────────────────────
# Tiny UX helpers
# ─────────────────────────────────────────────────────────────
func _ask_confirm(msg: String) -> bool:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Confirm"
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()
	return true

func _show_toast(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Notice"
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()

func _join_psa(arr: PackedStringArray, sep: String) -> String:
	var out: String = ""
	for i in range(arr.size()):
		if i > 0:
			out += sep
		out += arr[i]
	return out
