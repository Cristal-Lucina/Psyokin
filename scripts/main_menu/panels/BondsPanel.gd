## ═══════════════════════════════════════════════════════════════════════════
## BondsPanel - Circle Bond Management UI
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Main menu panel for viewing and managing social bonds with party members.
##   Displays bond levels, discovered likes/dislikes, rewards, and provides
##   access to bond story events.
##
## RESPONSIBILITIES:
##   • Bond list display (all characters or filtered)
##   • Bond level/layer visualization (Acquaintance → Core)
##   • Discovered likes/dislikes display
##   • Rewards preview (locked until bond level reached)
##   • Story event access button
##   • Filter system (All/Known/Locked/Maxed)
##   • Real-time updates when bonds change
##
## FILTER MODES:
##   • ALL - Show all characters
##   • KNOWN - Show only met/discovered characters
##   • LOCKED - Show only characters not yet at max bond
##   • MAXED - Show only characters at Core level (8)
##
## BOND DISPLAY:
##   Left Panel:
##   • List of characters (filtered)
##   • Current bond layer indicator
##   • Selection highlighting
##
##   Right Panel:
##   • Character name
##   • Current bond stage (Not Met, Acquaintance, Outer, Middle, Inner, Core)
##   • Discovered likes (topics/gifts they enjoy)
##   • Discovered dislikes (topics/gifts they dislike)
##   • Rewards preview (unlocks at specific bond levels)
##   • Story Events button (opens event overlay)
##
## CONNECTED SYSTEMS (Autoloads):
##   • CircleBondSystem - Bond data, BXP, likes/dislikes, events
##
## CSV DATA SOURCES:
##   • res://data/circles/circle_bonds.csv - Bond definitions (fallback)
##
## KEY METHODS:
##   • _rebuild() - Refresh entire bond list
##   • _on_bond_selected(bond_id) - Display bond details
##   • _on_filter_changed(index) - Apply filter to list
##   • _on_story_btn_pressed() - Open bond story event overlay
##
## ═══════════════════════════════════════════════════════════════════════════

extends Control
class_name BondsPanel

const SYS_PATH : String = "/root/aCircleBondSystem"
const CSV_FALLBACK: String = "res://data/circles/circle_bonds.csv"

enum Filter { ALL, KNOWN, LOCKED, MAXED }

@onready var _filter    : OptionButton   = %Filter
@onready var _refresh   : Button         = %RefreshBtn
@onready var _list_box  : VBoxContainer  = %List

@onready var _name_tv   : Label          = %Name
@onready var _lvl_tv    : Label          = %LevelValue          # old scene label (we hide)
@onready var _xp_tv     : Label          = %CBXPValue           # old scene label (we hide)
@onready var _desc      : RichTextLabel  = %Notes               # description block

# New/managed widgets
var _layer_tv     : Label          = null   # shows stage text (Not Met, Outer…)
var _likes_tv     : Label          = null
var _dislikes_tv  : Label          = null
var _rewards_hdr  : Label          = null   # “Rewards:”
var _rewards_val  : Label          = null   # “Locked”
var _story_btn    : Button         = null
var _story_overlay: Control        = null

# Data / state
var _sys  : Node = null
var _rows : Array[Dictionary] = []
var _selected : String = ""
var _list_group: ButtonGroup = null  # exclusive selection group

func _ready() -> void:
	_sys = get_node_or_null(SYS_PATH)
	_hide_level_cbxp_labels()
	_ensure_detail_widgets()
	_wire_system_signals()

	if _filter != null and _filter.item_count == 0:
		_filter.add_item("All",    Filter.ALL)
		_filter.add_item("Known",  Filter.KNOWN)
		_filter.add_item("Locked", Filter.LOCKED)
		_filter.add_item("Maxed",  Filter.MAXED)
	if _filter != null and not _filter.item_selected.is_connected(_on_filter_changed):
		_filter.item_selected.connect(_on_filter_changed)

	if _refresh != null and not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	_rebuild()

# ─────────────────────────────────────────────────────────────
# Scene fixes / dynamic widgets
# ─────────────────────────────────────────────────────────────

func _hide_level_cbxp_labels() -> void:
	if _lvl_tv:
		_lvl_tv.visible = false
	if _xp_tv:
		_xp_tv.visible  = false
	# Hide any stray “Level/CBXP/BXP” labels nearby.
	for n in get_children():
		if n is Label:
			var t: String = (n as Label).text.strip_edges().to_lower()
			if t.begins_with("level") or t.begins_with("cbxp") or t.begins_with("bxp"):
				(n as Label).visible = false

func _ensure_detail_widgets() -> void:
	# 1) Layer label directly under the name
	if _layer_tv == null:
		_layer_tv = Label.new()
		_layer_tv.name = "LayerStage"
		_layer_tv.text = "—"
		var np: Node = (_name_tv.get_parent() if _name_tv else null)
		if np:
			np.add_child(_layer_tv)
			# place right after the name label
			var idx: int = 0
			var kids: Array = np.get_children()
			for i in range(kids.size()):
				if kids[i] == _name_tv:
					idx = i
					break
			np.move_child(_layer_tv, idx + 1)

	# 2) Everything else gets added under the same parent as the description
	if _desc == null:
		return
	var holder: Node = _desc.get_parent()
	if holder == null:
		return

	if _story_btn == null:
		_story_btn = Button.new()
		_story_btn.name = "StoryBtnAuto"
		_story_btn.text = "Story Points"
		_story_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not _story_btn.pressed.is_connected(_on_story_points_pressed):
			_story_btn.pressed.connect(_on_story_points_pressed)
		holder.add_child(_story_btn)

	if _likes_tv == null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var title := Label.new(); title.text = "Likes:"
		_likes_tv = Label.new(); _likes_tv.text = "—"
		row.add_child(title); row.add_child(_likes_tv)
		holder.add_child(row)

	if _dislikes_tv == null:
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		var title2 := Label.new(); title2.text = "Dislikes:"
		_dislikes_tv = Label.new(); _dislikes_tv.text = "—"
		row2.add_child(title2); row2.add_child(_dislikes_tv)
		holder.add_child(row2)

	# Rewards: Header + “Locked” placeholder
	if _rewards_hdr == null:
		_rewards_hdr = Label.new()
		_rewards_hdr.text = "Rewards:"
		holder.add_child(_rewards_hdr)

	if _rewards_val == null:
		_rewards_val = Label.new()
		_rewards_val.text = "Locked"
		holder.add_child(_rewards_val)

# ─────────────────────────────────────────────────────────────
# System wiring
# ─────────────────────────────────────────────────────────────

func _wire_system_signals() -> void:
	if _sys == null:
		return
	if _sys.has_signal("data_reloaded") and not _sys.is_connected("data_reloaded", Callable(self, "_rebuild")):
		_sys.connect("data_reloaded", Callable(self, "_rebuild"))
	if _sys.has_signal("bxp_changed") and not _sys.is_connected("bxp_changed", Callable(self, "_on_progress_changed")):
		_sys.connect("bxp_changed", Callable(self, "_on_progress_changed"))
	if _sys.has_signal("level_changed") and not _sys.is_connected("level_changed", Callable(self, "_on_progress_changed")):
		_sys.connect("level_changed", Callable(self, "_on_progress_changed"))
	if _sys.has_signal("known_changed") and not _sys.is_connected("known_changed", Callable(self, "_on_progress_changed")):
		_sys.connect("known_changed", Callable(self, "_on_progress_changed"))

func _on_progress_changed(_id: String, _val: Variant = null) -> void:
	var keep: String = _selected
	_rebuild()
	if keep != "":
		_update_detail(keep)

# ─────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────

func _rebuild() -> void:
	_rows = _read_defs()
	_build_list()
	_update_detail(_selected)  # keep detail synced if selection still exists

func _build_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()

	# fresh exclusive group every build
	_list_group = ButtonGroup.new()
	_list_group.allow_unpress = false

	var f: int = _get_filter_id()
	for rec: Dictionary in _rows:
		var id: String = String(rec.get("id", ""))
		var disp_name: String = String(rec.get("name", id))

		var lv: int = _read_layer(id)
		var _xp: int = _read_bxp(id)  # kept for future tooltip tuning
		var known: bool = _read_known(id)
		var maxed: bool = _is_maxed(id, lv)

		if f == Filter.KNOWN and not known:    continue
		if f == Filter.LOCKED and known:       continue
		if f == Filter.MAXED and not maxed:    continue

		var row := Button.new()
		row.text = disp_name
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.toggle_mode = true
		row.button_group = _list_group     # ← exclusive selection
		row.focus_mode = Control.FOCUS_ALL
		row.set_meta("id", id)

		if not known:
			row.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			row.tooltip_text = "Unknown"
		elif maxed:
			row.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			row.tooltip_text = "Maxed"
		else:
			row.tooltip_text = disp_name

		if not row.pressed.is_connected(_on_row_pressed):
			row.pressed.connect(_on_row_pressed.bind(row))

		# Restore pressed state if this is the selected id
		if _selected != "" and _selected == id:
			row.button_pressed = true

		_list_box.add_child(row)

	await get_tree().process_frame
	_list_box.queue_sort()

# ─────────────────────────────────────────────────────────────
# Reads / fallbacks
# ─────────────────────────────────────────────────────────────

func _read_defs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	if _sys != null:
		if _sys.has_method("get_defs"):
			var d_v: Variant = _sys.call("get_defs")
			if typeof(d_v) == TYPE_DICTIONARY:
				var defs: Dictionary = d_v
				for k in defs.keys():
					var id: String = String(k)
					var rec: Dictionary = defs[k]
					var nm: String = String(rec.get("bond_name", id))
					out.append({"id": id, "name": nm})
				if out.size() > 0:
					return out
		if _sys.has_method("get_ids"):
			var ids_v: Variant = _sys.call("get_ids")
			if typeof(ids_v) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
				var ids: Array = (ids_v as Array)
				for i in ids:
					var id2: String = String(i)
					var nm2: String = (String(_sys.call("get_bond_name", id2)) if _sys.has_method("get_bond_name") else String(_sys.call("get_display_name", id2)))
					out.append({"id": id2, "name": nm2})
				if out.size() > 0:
					return out

	var csv_rows: Array[Dictionary] = _read_csv_rows(CSV_FALLBACK)
	for r in csv_rows:
		var rec: Dictionary = r
		var id3: String = String(rec.get("actor_id","")).strip_edges()
		if id3 == "":
			continue
		var nm3: String = String(rec.get("bond_name", id3))
		out.append({"id": id3, "name": nm3})

	if out.is_empty():
		for i in range(6):
			out.append({"id": "bond_%d" % i, "name": "Unknown %d" % (i + 1)})

	return out

func _read_csv_rows(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header: PackedStringArray = []
	if not f.eof_reached():
		header = f.get_csv_line()
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() == 0:
			continue
		var d: Dictionary = {}
		for i in range(min(header.size(), row.size())):
			d[header[i].strip_edges()] = row[i]
		out.append(d)
	f.close()
	return out

func _read_layer(id: String) -> int:
	if _sys == null:
		return 0
	if _sys.has_method("get_layer"):
		return int(_sys.call("get_layer", id))
	if _sys.has_method("get_level"): # alias
		return int(_sys.call("get_level", id))
	return 0

func _read_bxp(id: String) -> int:
	if _sys == null:
		return 0
	if _sys.has_method("get_bxp"):
		return int(_sys.call("get_bxp", id))
	if _sys.has_method("get_cbxp"): # legacy
		return int(_sys.call("get_cbxp", id))
	return 0

func _read_known(id: String) -> bool:
	if _sys == null:
		return false
	if _sys.has_method("is_known"):
		return bool(_sys.call("is_known", id))
	return _read_layer(id) > 0 or _read_bxp(id) > 0

func _is_maxed(_id: String, layer_val: int) -> bool:
	var max_lv: int = 10
	if _sys and _sys.has_method("get_max_level"):
		max_lv = int(_sys.call("get_max_level"))
	elif _sys and _sys.has_method("get_max_layer"):
		max_lv = int(_sys.call("get_max_layer"))
	return layer_val >= max_lv

# ─────────────────────────────────────────────────────────────
# Detail
# ─────────────────────────────────────────────────────────────

func _on_filter_changed(_idx: int) -> void:
	_build_list()

func _on_row_pressed(btn: Button) -> void:
	var id_v: Variant = btn.get_meta("id")
	_selected = String(id_v)
	_update_detail(_selected)

func _update_detail(id: String) -> void:
	_name_tv.text = ("—" if id == "" else _display_name(id))

	if id == "":
		if _layer_tv: _layer_tv.text = "—"
		if _desc: _desc.text = "[i]Select a bond to see details.[/i]"
		if _likes_tv: _likes_tv.text = "—"
		if _dislikes_tv: _dislikes_tv.text = "—"
		if _rewards_val: _rewards_val.text = "Locked"
		if _story_btn: _story_btn.set_meta("bond_id", "")
		return

	# Layer stage (always shown)
	var layer_val: int = _read_layer(id)
	if _layer_tv:
		_layer_tv.text = _layer_stage(layer_val)

	# Description
	var rec: Dictionary = _bond_def(id)
	var desc: String = String(rec.get("bond_description", "")).strip_edges()
	if _desc:
		_desc.text = desc

	# Likes/Dislikes (discovered first, else full author list)
	var likes: PackedStringArray = _read_discovered_or_full(id, true)
	var dislikes: PackedStringArray = _read_discovered_or_full(id, false)
	if _likes_tv: _likes_tv.text = _pretty_list(likes)
	if _dislikes_tv: _dislikes_tv.text = _pretty_list(dislikes)

	# Rewards placeholder (per request)
	if _rewards_val:
		_rewards_val.text = "Locked"

	# Story points
	if _story_btn:
		_story_btn.set_meta("bond_id", id)

func _layer_stage(layer_val: int) -> String:
	# Your mapping: Not Met → Outer → Middle → Inner → Core
	if layer_val <= 1: return "Not Met"
	if layer_val <= 3: return "Outer"
	if layer_val <= 5: return "Middle"
	if layer_val <= 7: return "Inner"
	return "Core"

func _display_name(id: String) -> String:
	if _sys and _sys.has_method("get_bond_name"):
		return String(_sys.call("get_bond_name", id))
	if _sys and _sys.has_method("get_display_name"):
		return String(_sys.call("get_display_name", id))
	var rec: Dictionary = _bond_def(id)
	var nm: String = String(rec.get("bond_name", ""))
	return (nm if nm != "" else id.capitalize())

func _bond_def(id: String) -> Dictionary:
	if _sys and _sys.has_method("get_bond_def"):
		var v: Variant = _sys.call("get_bond_def", id)
		if typeof(v) == TYPE_DICTIONARY:
			return (v as Dictionary)
	var rows: Array[Dictionary] = _read_csv_rows(CSV_FALLBACK)
	for r in rows:
		var rec: Dictionary = r
		if String(rec.get("actor_id","")) == id:
			return rec
	return {}

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

func _to_psa_local(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	match typeof(v):
		TYPE_PACKED_STRING_ARRAY:
			return v
		TYPE_ARRAY:
			for e in (v as Array):
				out.append(String(e))
		_:
			var s := String(v).strip_edges()
			if s != "":
				for seg in s.split(";", false):
					var t := String(seg).strip_edges()
					if t != "":
						out.append(t)
	return out

func _read_discovered_or_full(id: String, likes: bool) -> PackedStringArray:
	if _sys == null:
		return PackedStringArray()
	var first: PackedStringArray = PackedStringArray()
	var second: PackedStringArray = PackedStringArray()
	if likes:
		if _sys.has_method("get_discovered_likes"): first = _to_psa_local(_sys.call("get_discovered_likes", id))
		if _sys.has_method("get_likes"): second = _to_psa_local(_sys.call("get_likes", id))
	else:
		if _sys.has_method("get_discovered_dislikes"): first = _to_psa_local(_sys.call("get_discovered_dislikes", id))
		if _sys.has_method("get_dislikes"): second = _to_psa_local(_sys.call("get_dislikes", id))
	return (first if first.size() > 0 else second)

func _pretty_list(arr: PackedStringArray) -> String:
	if arr.size() == 0:
		return "—"
	var txt := ""
	for i in range(arr.size()):
		if i > 0:
			txt += ", "
		txt += arr[i]
	return txt

func _get_filter_id() -> int:
	if _filter == null:
		return Filter.ALL
	return int(_filter.get_selected_id())

# ─────────────────────────────────────────────────────────────
# Story Points overlay (full-screen, more opaque, Back)
# ─────────────────────────────────────────────────────────────

func _on_story_points_pressed() -> void:
	if _selected == "":
		return

	# Pull points safely
	var points: PackedStringArray = PackedStringArray()
	if _sys != null and _sys.has_method("get_story_points"):
		points = _to_psa_local(_sys.call("get_story_points", _selected))

	# Find display name for title
	var disp: String = _display_name(_selected)

	# Clear any prior overlay
	_close_story_overlay()

	# Full-screen overlay (blocks input behind it)
	var overlay := Control.new()
	overlay.name = "StoryOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100

	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65) # darker → more opaque
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	# Margin frame to keep text off edges
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 32)
	margins.add_theme_constant_override("margin_right", 32)
	margins.add_theme_constant_override("margin_top", 32)
	margins.add_theme_constant_override("margin_bottom", 32)
	overlay.add_child(margins)

	# Panel + content
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margins.add_child(panel)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	# Header row: Back button + title
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.pressed.connect(func() -> void:
		_close_story_overlay()
	)
	header.add_child(back_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var title := Label.new()
	title.text = "%s — Story Points" % disp
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(title)

	# Scrollable body
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	root.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# Fill with bullets (or placeholder)
	if points.is_empty():
		var none := Label.new()
		none.text = "No story points logged yet."
		body.add_child(none)
	else:
		for p_str in points:
			var row := Label.new()
			row.text = "• " + p_str
			body.add_child(row)

	# Add to the top-level so it truly fills the window
	get_tree().root.add_child(overlay)
	_story_overlay = overlay

func _close_story_overlay() -> void:
	if _story_overlay != null and is_instance_valid(_story_overlay):
		_story_overlay.queue_free()
	_story_overlay = null
