extends Control
class_name OutreachPanel

## OutreachPanel (MVP wired to MainEventSystem)
## Filters: Missions (live from aMainEventSystem), Nodes & Mutual Aid (placeholders).
## Click a mission to see details; use the inline link to set it as current.
## Adds a header button to advance the main event (useful for testing).

enum Filter { MISSIONS, NODES, AID }

const MAIN_EVENT_PATH := "/root/aMainEventSystem"

@onready var _filter  : OptionButton  = %Filter
@onready var _refresh : Button        = %RefreshBtn
@onready var _list    : VBoxContainer = %List
@onready var _detail  : RichTextLabel = %Detail

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	# Populate filter once
	if _filter.item_count == 0:
		_filter.add_item("Missions",   Filter.MISSIONS)
		_filter.add_item("Nodes",      Filter.NODES)
		_filter.add_item("Mutual Aid", Filter.AID)

	if not _filter.item_selected.is_connected(_on_filter):
		_filter.item_selected.connect(_on_filter)
	if not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	# Add "Advance Main Event" header button (idempotent)
	_add_advance_button()

	# RichText actions inside the detail view (set current / advance)
	if not _detail.meta_clicked.is_connected(_on_meta):
		_detail.meta_clicked.connect(_on_meta)

	# Auto-refresh when the current mission changes
	var ms: Node = get_node_or_null(MAIN_EVENT_PATH)
	if ms and ms.has_signal("event_changed"):
		ms.connect("event_changed", Callable(self, "_rebuild"))

	_rebuild()

func _add_advance_button() -> void:
	var header := _refresh.get_parent()
	if header == null:
		return
	if header.has_node("AdvanceMainEventBtn"):
		return
	var btn := Button.new()
	btn.name = "AdvanceMainEventBtn"
	btn.text = "Advance"
	btn.tooltip_text = "Advance Main Event (debug)"
	btn.pressed.connect(_on_advance_main_event)
	header.add_child(btn)

func _on_advance_main_event() -> void:
	var ms: Node = get_node_or_null(MAIN_EVENT_PATH)
	if ms and ms.has_method("advance"):
		ms.call("advance")

func _on_filter(_i: int) -> void:
	_rebuild()

func _rebuild(_unused: Variant = null) -> void:
	# Clear
	for c in _list.get_children():
		c.queue_free()

	var cat_id: int = _filter.get_selected_id()
	if cat_id < 0:
		cat_id = Filter.MISSIONS

	match cat_id:
		Filter.MISSIONS:
			_build_missions()
		Filter.NODES:
			_build_placeholder("VR Node", 5)
		Filter.AID:
			_build_placeholder("Mutual Aid Task", 6)

# --- Missions ------------------------------------------------------------------

func _build_missions() -> void:
	var rows: Array[Dictionary] = _read_missions()
	for rec in rows:
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = ("%s %s" % [rec.get("title",""), "•" if bool(rec.get("current", false)) else ""]).strip_edges()
		b.pressed.connect(_on_pick_mission.bind(rec))
		_list.add_child(b)

	if rows.size() > 0:
		_show_mission_detail(rows[0])
	else:
		_detail.bbcode_enabled = true
		_detail.text = "[i]No missions yet.[/i]"

func _read_missions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	var ms: Node = get_node_or_null(MAIN_EVENT_PATH)
	if ms == null:
		return out

	# ids
	var ids: PackedStringArray = PackedStringArray()
	if ms.has_method("list_ids"):
		var v_ids: Variant = ms.call("list_ids")
		if typeof(v_ids) == TYPE_PACKED_STRING_ARRAY:
			ids = v_ids
		elif typeof(v_ids) == TYPE_ARRAY:
			for it in (v_ids as Array):
				ids.append(String(it))
	ids.sort()

	# current
	var cur_id: String = ""
	if ms.has_method("get_current_id"):
		cur_id = String(ms.call("get_current_id"))

	# compose rows
	for id in ids:
		var title := id
		var hint  := ""
		if ms.has_method("get_event"):
			var rec_v: Variant = ms.call("get_event", id)
			if typeof(rec_v) == TYPE_DICTIONARY:
				var d: Dictionary = rec_v
				title = String(d.get("title", title))
				hint  = String(d.get("hint",  hint))
		out.append({"id": id, "title": title, "hint": hint, "current": (id == cur_id)})

	return out

func _on_pick_mission(rec: Dictionary) -> void:
	_show_mission_detail(rec)

func _show_mission_detail(rec: Dictionary) -> void:
	var title: String = String(rec.get("title",""))
	var hint : String = String(rec.get("hint",""))
	var id   : String = String(rec.get("id",""))
	var is_cur: bool  = bool(rec.get("current", false))

	var body := "[b]%s[/b]\n\n%s\n\n" % [title, (hint if hint != "" else "[i]No details yet.[/i]")]
	if is_cur:
		body += "[i]This is your current mission.[/i]\n[url=advance]Advance (debug)[/url]"
	else:
		body += "[url=set:%s]Set as current[/url]" % id

	_detail.bbcode_enabled = true
	_detail.text = body

func _on_meta(meta: Variant) -> void:
	var s := String(meta)
	var ms: Node = get_node_or_null(MAIN_EVENT_PATH)
	if ms == null:
		return
	if s.begins_with("set:"):
		var id := s.substr(4)
		if ms.has_method("set_current"):
			ms.call("set_current", id)
		_rebuild()
	elif s == "advance":
		if ms.has_method("advance"):
			ms.call("advance")
		_rebuild()

# --- Placeholders --------------------------------------------------------------

func _build_placeholder(base: String, count: int) -> void:
	for i in range(count):
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "%s %d" % [base, i + 1]
		b.pressed.connect(func() -> void:
			_detail.bbcode_enabled = true
			_detail.text = "[b]%s[/b]\n\n[i]Details TBD.[/i]" % b.text
		)
		_list.add_child(b)
