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
# Build grid + common list
# ─────────────────────────────────────────────────────────────
func _rebuild() -> void:
	_build_grid()
	_build_common_list()
	_update_detail(_selected_room)

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

	for aid in list_psa:
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
	for nid in neigh:
		var nocc_v: Variant = ds.call("occupants_of", nid)
		var nocc_psa: PackedStringArray = (nocc_v if typeof(nocc_v) == TYPE_PACKED_STRING_ARRAY else PackedStringArray())
		var nwho: String = (nocc_psa[0] if nocc_psa.size() > 0 else "")
		if nwho == "":
			lines.append("• %s — empty" % nid)
		else:
			var st: String = "Neutral"
			if ds.has_method("get_pair_status") and who != "" and nwho != "":
				st = String(ds.call("get_pair_status", who, nwho))
			lines.append("• %s — %s with [b]%s[/b]" % [nid, st, String(ds.call("display_name", nwho))])

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

	var staged_now_v: Variant = ds.call("is_staged", curr)
	var staged_now: bool = bool(staged_now_v)

	if staged_now:
		ds.call("unstage_vacate_room", _selected_room)
	else:
		var res: Dictionary = ds.call("stage_vacate_room", _selected_room)
		if not bool(res.get("ok", false)):
			_show_toast(String(res.get("reason","Cannot stage.")))
	_update_tile_colors()
	_build_common_list()

	var chk: Dictionary = ds.call("can_accept_reassignment")
	_accept_btn.disabled = not bool(chk.get("ok", false))

func _on_reset_pressed() -> void:
	var ds: Node = _ds()
	if ds == null:
		return
	ds.call("reset_only_assignments")
	_selected_person = ""
	_build_common_list()
	_update_tile_colors()

func _on_accept_pressed() -> void:
	var ds: Node = _ds()
	if ds == null:
		return

	var staged_sz: int = int(ds.call("staged_size"))
	var staged_assign_sz: int = int(ds.call("staged_assign_size"))

	if staged_sz > 0 and staged_assign_sz == 0:
		var res: Dictionary = ds.call("accept_reassignment_selection")
		if not bool(res.get("ok", false)):
			_show_toast(String(res.get("reason","Cannot accept.")))
			return
		_show_toast("Selected members moved to Common Room (staged). Place them.")

	var can2: Dictionary = ds.call("can_lock_plan")
	if bool(can2.get("ok", false)):
		var res2: Dictionary = ds.call("lock_plan_for_saturday")
		if bool(res2.get("ok", false)):
			_show_toast("Plan locked. Changes will apply on Saturday.")
	else:
		_show_toast(String(can2.get("reason","Place everyone before accepting.")))

	_update_tile_colors()
	_build_common_list()

# Place selected person into a room (handles staged & immediate)
func _try_place_selected(room_id: String) -> void:
	var ds: Node = _ds()
	if ds == null or _selected_person == "":
		return

	var staged_v: Variant = ds.call("is_staged", _selected_person)
	var staged: bool = bool(staged_v)

	if staged:
		var who_name: String = String(ds.call("display_name", _selected_person))
		var ok: bool = await _ask_confirm("Assign %s to room %s?" % [who_name, room_id])
		if not ok:
			return
		var res: Dictionary = ds.call("stage_place", _selected_person, room_id)
		if not bool(res.get("ok", false)):
			_show_toast(String(res.get("reason","Cannot place.")))
			return
		_selected_person = ""
		_show_toast("Placement staged.")
	else:
		var who_name2: String = String(ds.call("display_name", _selected_person))
		var ok2: bool = await _ask_confirm("Assign %s to room %s?" % [who_name2, room_id])
		if not ok2:
			return
		var res2: Dictionary = ds.call("assign_now_from_common", _selected_person, room_id)
		if not bool(res2.get("ok", false)):
			_show_toast(String(res2.get("reason","Cannot assign.")))
			return
		_selected_person = ""
		_show_toast("Assigned.")

	_update_tile_colors()
	_build_common_list()
	_update_detail(room_id)

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
		col = Color(0.38, 0.10, 0.10) # red (kept for completeness)

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
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()
	await get_tree().process_frame
	await get_tree().process_frame
	dlg.queue_free()

func _join_psa(arr: PackedStringArray, sep: String) -> String:
	var out := ""
	for i in range(arr.size()):
		if i > 0:
			out += sep
		out += arr[i]
	return out
