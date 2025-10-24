## ═══════════════════════════════════════════════════════════════════════════
## DormsPanel - Dormitory Room Assignment UI
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Main menu panel for managing dormitory room assignments, displaying the
##   8-room layout, handling weekly Saturday reassignments, and showing
##   neighbor relationships (Bestie/Rival pairs).
##
## RESPONSIBILITIES:
##   • 8-room visual grid display (301-308)
##   • Room occupancy display (name/empty/staged)
##   • Common area management (unassigned members)
##   • Two modes:
##     - Placements: Immediate Common area assignments
##     - Reassignment: Saturday weekly planning mode
##   • Planning/staging system (preview moves before applying)
##   • Accept/Cancel controls for staged reassignments
##   • Neighbor relationship display (Bestie/Rival indicators)
##   • Real-time updates when dorm state changes
##
## DISPLAY MODES:
##   Placements Mode:
##   • Show current room assignments
##   • Common area member list
##   • Click member + room to assign immediately
##   • Shows neighbor relationships
##
##   Reassignment Mode (Saturday):
##   • Plan room swaps/reassignments
##   • Staged moves turn rooms red (consumed)
##   • Accept Plan button (applies all changes)
##   • Cancel button (discard staging)
##   • Blocks time advancement until accepted/cancelled
##
## ROOM VISUAL STATES:
##   • EMPTY (0) - No occupant, available
##   • OCCUPIED (1) - Has occupant, normal state
##   • STAGED (2) - Part of pending reassignment plan (red)
##   • LOCKED (3) - Cannot be modified
##
## CONNECTED SYSTEMS (Autoloads):
##   • DormSystem - Room assignments, neighbor tracking, reassignment logic
##
## UI ELEMENTS:
##   Left Panel:
##   • 8-room grid (2x4 layout)
##   • Common area member list
##   • Filter dropdown (Placements/Reassignment)
##   • Refresh button
##
##   Right Panel:
##   • Detail text (selected room/member info)
##   • Reassignment controls (when in Reassignment mode)
##   • Accept/Cancel buttons
##
## KEY METHODS:
##   • _rebuild() - Refresh entire room grid and Common list
##   • _on_room_clicked(room_id) - Handle room selection
##   • _on_common_person_clicked(actor_id) - Handle Common member selection
##   • _on_accept_plan() - Apply staged reassignments
##   • _on_cancel_plan() - Discard staging, return to normal
##   • _on_filter_changed(index) - Switch between Placements/Reassignment
##
## ═══════════════════════════════════════════════════════════════════════════

extends Control
class_name DormsPanel

# Scene hooks
@onready var _grid_holder  : VBoxContainer  = $Root/Left/Scroll/List
@onready var _detail       : RichTextLabel  = $Root/Right/Detail
@onready var _refresh_btn  : Button         = $Root/Left/Header/RefreshBtn
@onready var _filter       : OptionButton   = $Root/Left/Filter

# Right-side controls (from TSCN)
@onready var _common_box  : VBoxContainer = %CommonBox
@onready var _reassign_btn: Button        = %ReassignBtn
@onready var _reset_btn   : Button        = %ResetBtn
@onready var _accept_btn  : Button        = %AcceptBtn

# State
var _selected_room: String = ""
var _selected_person: String = ""  # actor_id (from Common Room)
var _pending_room: String = ""     # room-first flow: user clicked a room first
var _group: ButtonGroup = null

# Track rooms consumed during this reassignment session (turned red in UI)
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

	# Wire up right control buttons
	if _reassign_btn != null and not _reassign_btn.pressed.is_connected(_on_reassign_pressed):
		_reassign_btn.pressed.connect(_on_reassign_pressed)
	if _reset_btn != null and not _reset_btn.pressed.is_connected(_on_reset_pressed):
		_reset_btn.pressed.connect(_on_reset_pressed)
	if _accept_btn != null and not _accept_btn.pressed.is_connected(_on_accept_pressed):
		_accept_btn.pressed.connect(_on_accept_pressed)

	var ds: Node = _ds()
	if ds != null:
		if ds.has_signal("dorms_changed"):
			ds.connect("dorms_changed", Callable(self, "_on_model_bumped"))
		if ds.has_signal("plan_changed"):
			ds.connect("plan_changed", Callable(self, "_on_model_bumped"))
		if ds.has_signal("saturday_applied"):
			ds.connect("saturday_applied", func(_snap: Dictionary) -> void: _on_model_bumped())
		# Optional: react if the system is blocking time advance (could show a banner)
		if ds.has_signal("blocking_state_changed"):
			ds.connect("blocking_state_changed", func(_locked: bool) -> void: _refresh_accept_state())

	# Guard: if someone tries to hide/swap the panel while Accept is active, cancel it.
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	_rebuild()

func _on_model_bumped() -> void:
	_rebuild()

func _on_filter_changed(_ix: int) -> void:
	# Leaving Reassignment view? clear local red paint
	if _filter and _filter.get_selected_id() != 1:
		_used_rooms.clear()
		_pending_room = ""
	_rebuild()

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

			# Room-first flow: if empty (green) or staged (yellow), remember it
			var vis: int = int(ds.call("get_room_visual", room_id))
			if vis == VIS_EMPTY or vis == VIS_STAGED:
				_pending_room = room_id
			else:
				_pending_room = ""

			# Person-first flow (standard)
			if _selected_person != "":
				_try_place_selected(room_id)
			else:
				# If no one selected and room is placeable, nudge user to pick from Common
				if vis == VIS_EMPTY or vis == VIS_STAGED:
					pass
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

	# A small hint row if user “armed” a room first
	if _pending_room != "":
		var hint := Label.new()
		hint.text = "Place into room %s:" % _pending_room
		hint.add_theme_font_size_override("font_size", 11)
		_common_box.add_child(hint)

	for i in range(list_psa.size()):
		var aid: String = list_psa[i]
		var btn := Button.new()
		btn.text = String(ds.call("display_name", aid))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_ALL
		btn.button_pressed = (_selected_person == aid)
		btn.pressed.connect(func(id := aid) -> void:
			_selected_person = ("" if _selected_person == id else id)
			# If the user armed a room and now picked a person, try the place immediately
			if _selected_person != "" and _pending_room != "":
				_try_place_selected(_pending_room)
			_build_common_list()
			_update_tile_colors()
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

	# If plan is locked and this room is involved, show banner (tiles stay normal colors)
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
				label_status = "Unknown (reveals Friday)"
			elif ds.has_method("get_pair_status") and who != "" and nwho != "":
				label_status = String(ds.call("get_pair_status", who, nwho))
			lines.append("• %s — %s with [b]%s[/b]" % [nid, label_status, String(ds.call("display_name", nwho))])

	_detail.text = _join_psa(lines, "\n")

# ─────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────
func _on_reassign_pressed() -> void:
	var ds: Node = _ds()
	if ds == null or _selected_room == "":
		# Even if no room is selected, ensure we flip to Reassignment mode on click.
		if _filter and _filter.get_selected_id() != 1:
			_filter.select(1)
			_on_filter_changed(1)
		return

	# Flip the forms panel from Placements -> Reassignment (and leave it if already there)
	if _filter and _filter.get_selected_id() != 1:
		_filter.select(1)
		_on_filter_changed(1)

	# Block Friday/Saturday for starting reassignment
	if ds.has_method("can_start_reassignment_today") and not bool(ds.call("can_start_reassignment_today")):
		_show_toast("Room reassignment can only be started on Sunday.")
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

	# Fresh session markers
	_pending_room = ""
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
	_pending_room = ""
	_used_rooms.clear()  # clear our session paint
	_rebuild()

func _on_accept_pressed() -> void:
	var ds: Node = _ds()
	if ds == null:
		return

	# Only when everyone staged has a target (no one left in "Common" for reassignment)
	var ok_meta: bool = false
	if ds.has_method("can_lock_plan"):
		var meta: Dictionary = ds.call("can_lock_plan")
		ok_meta = bool(meta.get("ok", false))
	else:
		ok_meta = _compute_can_accept()
	if not ok_meta:
		_show_toast("Place every staged member into a target room before accepting.")
		return

	# Lock the plan for Saturday; live layout reverts now (visuals back to blue/green)
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

	_selected_person = ""
	_pending_room = ""
	_used_rooms.clear()  # new session starts after lock
	_rebuild()

# Place selected person into a room (handles staged & immediate)
func _try_place_selected(room_id: String) -> void:
	var ds: Node = _ds()
	if ds == null or _selected_person == "":
		return

	var staged: bool = false
	if ds.has_method("is_staged"):
		staged = bool(ds.call("is_staged", _selected_person))

	if staged:
		# Disallow blue rooms explicitly: only green/yellow
		var vis: int = int(ds.call("get_room_visual", room_id))
		if not (vis == VIS_EMPTY or vis == VIS_STAGED):
			_show_toast("Pick a green or yellow room for reassignment.")
			return

		# If trying to place back to original room, block
		var origin: String = ""
		if ds.has_method("get_staged_prev_room_for"):
			origin = String(ds.call("get_staged_prev_room_for", _selected_person))
		if origin != "" and origin == room_id:
			_show_toast("That's their current room; placing them there doesn't require reassignment.")
			return

		# If another staged person already targets this room, block
		if _room_targeted_in_plan(room_id, _selected_person):
			_show_toast("That room is already targeted by another reassignment.")
			return

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
		_pending_room = ""
		_show_toast("Placement staged.")

		# Mark room used locally (UI red). Also DS will reflect this; we still keep a local flag for instant feedback.
		if _filter and _filter.get_selected_id() == 1:
			_used_rooms[room_id] = true
	else:
		# Immediate (new Common member). Only allow empty (green).
		var vis2: int = int(ds.call("get_room_visual", room_id))
		if vis2 != VIS_EMPTY:
			_show_toast("That room is not empty.")
			return
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
			_pending_room = ""
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
		col = Color(0.40, 0.34, 0.08) # yellow (staged tile)
	elif state == VIS_LOCKED:
		col = Color(0.38, 0.10, 0.10) # red (locked/kept)

	# Only in Reassignment mode do we add our session red paints/overrides
	if _filter and _filter.get_selected_id() == 1:
		# 1) Red for the origin room when a staged person is selected (can't place them back)
		if _selected_person != "" and ds.has_method("is_staged") and bool(ds.call("is_staged", _selected_person)):
			if ds.has_method("get_staged_prev_room_for"):
				var origin: String = String(ds.call("get_staged_prev_room_for", _selected_person))
				if origin == room_id:
					col = Color(0.75, 0.15, 0.15)

		# 2) Red for rooms already targeted by any staged assignment (no double-placing)
		if _room_targeted_in_plan(room_id):
			col = Color(0.75, 0.15, 0.15)

		# 3) Also honor local 'used this session' paint
		if _used_rooms.has(room_id):
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

func _room_targeted_in_plan(room_id: String, ignore_aid: String = "") -> bool:
	var ds := _ds()
	if ds == null:
		return false
	# Prefer explicit staged assignments
	for fn in ["get_staged_assignments","staged_assignments","get_staged_places","list_staged_assignments"]:
		if ds.has_method(fn):
			var d_v: Variant = ds.call(fn)
			if typeof(d_v) == TYPE_DICTIONARY:
				var d: Dictionary = d_v
				for k in d.keys():
					var aid: String = String(k)
					if ignore_aid != "" and aid == ignore_aid:
						continue
					if String(d[k]) == room_id:
						return true
	return false

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
	# If plan exposes an explicit "locked" flag, don't allow (already accepted)
	if ds.has_method("is_plan_locked") and bool(ds.call("is_plan_locked")):
		return false
	# Prefer explicit "can_lock_plan" when available
	if ds.has_method("can_lock_plan"):
		var meta: Dictionary = ds.call("can_lock_plan")
		return bool(meta.get("ok", false))
	# Otherwise: at least one staged target
	if ds.has_method("staged_assign_size"):
		return int(ds.call("staged_assign_size")) > 0
	if ds.has_method("get_staged_assignments"):
		var d_v: Variant = ds.call("get_staged_assignments")
		if typeof(d_v) == TYPE_DICTIONARY:
			return (d_v as Dictionary).size() > 0
	return false

# Helper: is Accept Plan currently active (enabled)?
func _is_accept_active() -> bool:
	return _accept_btn != null and not _accept_btn.disabled

# ─────────────────────────────────────────────────────────────
# Exit guard — block leaving the menu while Accept is active
# ─────────────────────────────────────────────────────────────
func _on_visibility_changed() -> void:
	# If something tries to hide this panel while Accept is active, bring it back and warn.
	if not is_visible_in_tree() and _is_accept_active():
		# Re-show ourselves on the next frame to avoid flicker/race.
		call_deferred("show")
		call_deferred("_show_toast", "Room Reassignments not complete.")

func _unhandled_input(event: InputEvent) -> void:
	# Catch Esc / gamepad back while Accept is active.
	if _is_accept_active():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_end"):
			_show_toast("Room Reassignments not complete.")
			accept_event()

# Public opt-in for parent menus that want to ask first.
func can_close_panel() -> bool:
	# Return false while Accept is active; parent can honor this to block tab changes.
	return not _is_accept_active()

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
