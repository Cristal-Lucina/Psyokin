extends Control
class_name ItemInspect

## ItemInspect — reads name/category/descriptions from CSV-style fields.
## Adds Use / Discard / Give +1 (for quick testing).
## For Sigil instances (injected by ItemsPanel), shows read-only Level/XP/Active.

signal item_used(item_id: String, new_count: int)

@onready var _title : Label         = %Title
@onready var _cat   : Label         = %CategoryValue
@onready var _count : Label         = %CountValue
@onready var _desc  : RichTextLabel = %Desc
@onready var _use   : Button        = %UseBtn
@onready var _close : Button        = %CloseBtn

var _discard_btn: Button = null
var _add_btn: Button = null

var _id    : String = ""
var _def   : Dictionary = {}
var _qty   : int = 0
var _inv   : Node = null

func _ready() -> void:
	if _close and not _close.pressed.is_connected(_on_close):
		_close.pressed.connect(_on_close)
	if _use and not _use.pressed.is_connected(_on_use):
		_use.pressed.connect(_on_use)
	_ensure_extra_buttons()
	_update_ui()

func set_item(id: String, def: Dictionary, count: int, inv: Node) -> void:
	_id  = id
	_def = def
	_qty = max(0, count)
	_inv = inv
	_update_ui()

func _ensure_extra_buttons() -> void:
	var parent: Node = (_use if _use != null else _close)
	if parent != null:
		parent = parent.get_parent()
	if parent == null:
		return

	_discard_btn = parent.get_node_or_null("DiscardBtn") as Button
	if _discard_btn == null:
		_discard_btn = Button.new()
		_discard_btn.name = "DiscardBtn"
		_discard_btn.text = "Discard"
		parent.add_child(_discard_btn)
	if not _discard_btn.pressed.is_connected(_on_discard):
		_discard_btn.pressed.connect(_on_discard)

	_add_btn = parent.get_node_or_null("AddBtn") as Button
	if _add_btn == null:
		_add_btn = Button.new()
		_add_btn.name = "AddBtn"
		_add_btn.text = "Give +1"
		parent.add_child(_add_btn)
	if not _add_btn.pressed.is_connected(_on_add):
		_add_btn.pressed.connect(_on_add)

func _is_sigil_instance() -> bool:
	return _def.has("sigil_instance") and bool(_def["sigil_instance"])

func _desc_text() -> String:
	# Sigil instance path: show school/level/active/progress
	if _is_sigil_instance():
		var ss: Node = get_node_or_null("/root/aSigilSystem")
		var lvl: int = 1
		var pct: int = 0
		var active: String = ""
		var school: String = String(_def.get("school",""))

		if ss != null:
			if ss.has_method("get_instance_info"):
				var info_v: Variant = ss.call("get_instance_info", _id)
				if typeof(info_v) == TYPE_DICTIONARY:
					var info: Dictionary = info_v
					lvl = int(info.get("level", 1))
			if ss.has_method("get_instance_progress"):
				var pr_v: Variant = ss.call("get_instance_progress", _id)
				if typeof(pr_v) == TYPE_DICTIONARY:
					var pr: Dictionary = pr_v
					pct = int(pr.get("pct", 0))
			if ss.has_method("get_active_skill_name_for_instance"):
				active = String(ss.call("get_active_skill_name_for_instance", _id))

		var active_str := (active if active != "" else "—")
		var school_str := (school if school != "" else "—")
		return "[b]Sigil Instance[/b]\nSchool: %s\nLevel: %d\nActive: %s\nProgress: %d%% to next" % [school_str, lvl, active_str, pct]

	# CSV-backed items:
	if _def.has("short_description") and typeof(_def["short_description"]) == TYPE_STRING:
		var s := String(_def["short_description"]).strip_edges()
		if s != "": return s
	if _def.has("full_description") and typeof(_def["full_description"]) == TYPE_STRING:
		var f := String(_def["full_description"]).strip_edges()
		if f != "": return f
	if _def.has("desc") and typeof(_def["desc"]) == TYPE_STRING:
		var d := String(_def["desc"]).strip_edges()
		if d != "": return d
	return "[i]No description.[/i]"

func _update_ui() -> void:
	var nm: String = String(_def.get("name", _id))
	var cat: String = String(_def.get("category", "Other"))
	if _title: _title.text = nm
	if _cat:   _cat.text   = cat

	# For sigil instances, show a dash instead of a stack count
	if _count:
		_count.text = ("—" if _is_sigil_instance() else str(_qty))

	if _desc:  _desc.text  = _desc_text()

	var can_consume: bool = (_qty > 0) and _inventory_can_consume()
	if _is_sigil_instance():
		can_consume = false
	if _use:         _use.disabled = not can_consume
	if _discard_btn: _discard_btn.disabled = (_qty <= 0 or _inv == null or _is_sigil_instance())
	if _add_btn:     _add_btn.disabled = (_inv == null or _is_sigil_instance())

func _inventory_can_consume() -> bool:
	if _is_sigil_instance():
		return false
	if _inv == null: return false
	if _inv.has_method("use_item"): return true
	if _inv.has_method("remove_item"): return true
	if _inv.has_method("set_count") and _inv.has_method("get_count"): return true
	return false

func _on_use() -> void:
	if _is_sigil_instance():
		return
	if _qty <= 0 or not _inventory_can_consume():
		return
	var ok: bool = false
	if _inv != null:
		if _inv.has_method("use_item"):
			ok = bool(_inv.call("use_item", _id, 1))
		elif _inv.has_method("remove_item"):
			var after: int = int(_inv.call("remove_item", _id, 1))
			ok = (after < _qty)
		elif _inv.has_method("get_count") and _inv.has_method("set_count"):
			var cur: int = int(_inv.call("get_count", _id))
			_inv.call("set_count", _id, max(0, cur - 1))
			ok = true
	if ok:
		_qty = max(0, _qty - 1)
		_emit_changed()

func _on_discard() -> void:
	if _is_sigil_instance():
		return
	if _qty <= 0 or _inv == null: return
	var ok: bool = false
	if _inv.has_method("discard_item"):
		ok = bool(_inv.call("discard_item", _id, 1))
	elif _inv.has_method("use_item"):
		ok = bool(_inv.call("use_item", _id, 1))
	if ok:
		_qty = max(0, _qty - 1)
		_emit_changed()

func _on_add() -> void:
	if _is_sigil_instance():
		return
	if _inv == null: return
	if _inv.has_method("add_item"):
		_inv.call("add_item", _id, 1)
	elif _inv.has_method("get_count") and _inv.has_method("set_count"):
		var cur: int = int(_inv.call("get_count", _id))
		_inv.call("set_count", _id, cur + 1)
	_qty += 1
	_emit_changed()

func _emit_changed() -> void:
	_update_ui()
	item_used.emit(_id, _qty)

func _on_close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and (event.keycode == KEY_ESCAPE):
		_on_close()
