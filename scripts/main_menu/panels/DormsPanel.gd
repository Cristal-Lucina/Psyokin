extends Control
class_name DormsPanel

## DormsPanel (fits your scene)
## Left: Filter + Scroll/List of rooms
## Right: Detail (RichTextLabel)
## Request/moves UI is not required yet; this panel just lists rooms and shows occupants.

# Scene refs (match your .tscn)
@onready var _rooms_list : VBoxContainer = $Root/Left/Scroll/List
@onready var _detail     : RichTextLabel = $Root/Right/Detail
@onready var _refresh    : Button        = $Root/Left/Header/RefreshBtn
@onready var _filter     : OptionButton  = $Root/Left/Filter

var _selected_room: String = ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	# Populate filter (future-proof: Move Requests later)
	if _filter.item_count == 0:
		_filter.add_item("Placements", 0)
		_filter.add_item("Move Requests", 1)
		_filter.select(0)

	if not _filter.item_selected.is_connected(_on_filter_changed):
		_filter.item_selected.connect(_on_filter_changed)
	if not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	# Auto-rebuild on dorm changes if the system exposes a signal
	var ds := get_node_or_null("/root/aDormSystem")
	if ds and ds.has_signal("dorms_changed"):
		ds.connect("dorms_changed", Callable(self, "_rebuild"))

	_rebuild()

func _on_filter_changed(_i: int) -> void:
	# For now both filters rebuild the same list. Move Requests UI can hook here later.
	_rebuild()

func _rebuild() -> void:
	# Clear list
	for c in _rooms_list.get_children():
		c.queue_free()

	# Collect room IDs from aDormSystem (fallback to placeholders if missing)
	var ids := PackedStringArray()
	var ds := get_node_or_null("/root/aDormSystem")
	if ds and ds.has_method("list_rooms"):
		var v: Variant = ds.call("list_rooms")
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			ids = v
		elif typeof(v) == TYPE_ARRAY:
			for e in (v as Array):
				ids.append(String(e))
	if ids.is_empty():
		ids = PackedStringArray(["A101", "A102", "B201"])  # harmless placeholder

	ids.sort()

	# Build buttons
	for id in ids:
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = _room_label(id)
		b.pressed.connect(func(room := id) -> void:
			_selected_room = room
			_detail.text = _room_detail(room)
		)
		_rooms_list.add_child(b)

	# Select first by default
	if _selected_room == "" and ids.size() > 0:
		_selected_room = ids[0]
	_detail.text = _room_detail(_selected_room) if _selected_room != "" else "[i]No room selected.[/i]"

func _room_label(room_id: String) -> String:
	var ds := get_node_or_null("/root/aDormSystem")
	if ds and ds.has_method("get_room"):
		var r_v: Variant = ds.call("get_room", room_id)
		if typeof(r_v) == TYPE_DICTIONARY:
			var r: Dictionary = r_v
			var room_name := String(r.get("name", room_id))   # avoid shadowing Node.name
			var cap       := int(r.get("capacity", 0))
			var occ_count := 0
			var occ_v: Variant = r.get("occupants", [])
			if typeof(occ_v) == TYPE_ARRAY:
				occ_count = (occ_v as Array).size()
			return "%s  —  %d/%d" % [room_name, occ_count, cap]
	return room_id

func _room_detail(room_id: String) -> String:
	var ds := get_node_or_null("/root/aDormSystem")
	if ds and ds.has_method("get_room"):
		var r_v: Variant = ds.call("get_room", room_id)
		if typeof(r_v) == TYPE_DICTIONARY:
			var r: Dictionary = r_v
			var room_name := String(r.get("name", room_id))
			var cap       := int(r.get("capacity", 0))

			var lines := PackedStringArray()
			lines.append("[b]%s[/b]  (capacity %d)" % [room_name, cap])
			lines.append("")
			lines.append("Occupants:")

			var occ_v: Variant = r.get("occupants", [])
			if typeof(occ_v) == TYPE_ARRAY:
				var occ: Array = occ_v as Array
				if occ.is_empty():
					lines.append("  — none —")
				else:
					for who_v in occ:
						lines.append("  • %s" % String(who_v))
			else:
				lines.append("  — none —")

			return "\n".join(lines)

	# If system/room not found
	return "[i]Room not found.[/i]"
