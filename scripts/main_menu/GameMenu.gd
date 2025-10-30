extends Control

# ------------------------------------------------------------------------------
# GameMenu — centered menu shell (tabs left, content right).
# ------------------------------------------------------------------------------

const TAB_DEFS: Dictionary = {
	"status":  {"title": "Status",  "scene": "res://scenes/main_menu/panels/StatusPanel.tscn"},
	"stats":   {"title": "Stats",   "scene": "res://scenes/main_menu/panels/StatsPanel.tscn"},
	"perks":   {"title": "Perks",   "scene": "res://scenes/main_menu/panels/PerksPanel.tscn"},
	"items":   {"title": "Items",   "scene": "res://scenes/main_menu/panels/ItemsPanel.tscn"},
	"loadout": {"title": "Loadout", "scene": "res://scenes/main_menu/panels/LoadoutPanel.tscn"},
	"bonds":   {"title": "Bonds",   "scene": "res://scenes/main_menu/panels/BondsPanel.tscn"},
	"outreach":{"title": "Outreach","scene": "res://scenes/main_menu/panels/OutreachPanel.tscn"},
	"dorms":   {"title": "Dorms",   "scene": "res://scenes/main_menu/panels/DormsPanel.tscn"},
	"calendar":{"title": "Calendar","scene": "res://scenes/main_menu/panels/CalendarPanel.tscn"},
	"index":   {"title": "Index",   "scene": "res://scenes/main_menu/panels/IndexPanel.tscn"},
	"system":  {"title": "System",  "scene": "res://scenes/main_menu/panels/SystemPanel.tscn"},
}

const TAB_ORDER: PackedStringArray = [
	"status","stats","perks","items","loadout","bonds","outreach","dorms","calendar","index","system"
]

@onready var _left_tabs: VBoxContainer = %LeftTabs
@onready var _panel_holder: Control    = %PanelHolder

var _btn_group: ButtonGroup
var _panels: Dictionary = {}  # tab_id -> Control
var _current_tab: String = ""

# --- Controller navigation ---
var _tab_buttons: Array[Button] = []
var _selected_tab_index: int = 0

# --- Dorm hooks ---
var _ds: Node = null

func _ready() -> void:
	_btn_group = ButtonGroup.new()
	_build_tabs()

	var last_tab: String = ""
	var settings: Node = get_node_or_null("/root/aSettings")
	if settings and settings.has_method("get_value"):
		last_tab = String(settings.call("get_value", "main_menu_last_tab", ""))

	if last_tab == "" or not TAB_DEFS.has(last_tab):
		_select_first_tab()
	else:
		_select_tab(last_tab)

	# Hook: auto-open Dorms tab when someone is added to Common (menu already open)
	_ds = get_node_or_null("/root/aDormSystem")
	if _ds and _ds.has_signal("common_added") and not _ds.is_connected("common_added", Callable(self, "_on_common_added")):
		_ds.connect("common_added", Callable(self, "_on_common_added"))

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle controller navigation
	if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
		_navigate_tabs(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
		_navigate_tabs(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
		_confirm_tab_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(aInputManager.ACTION_BACK):
		_close_menu()
		get_viewport().set_input_as_handled()

func _build_tabs() -> void:
	for child in _left_tabs.get_children():
		child.queue_free()
	await get_tree().process_frame

	# Clear button array
	_tab_buttons.clear()

	# Use a plain Array to avoid PackedStringArray mutability/typing traps
	var ids: Array = Array(TAB_ORDER)
	if ids.size() == 0:
		ids = TAB_DEFS.keys()

	for tab_id_any in ids:
		var tab_id: String = String(tab_id_any)
		if not TAB_DEFS.has(tab_id):
			continue
		var meta: Dictionary = TAB_DEFS[tab_id]
		var b := Button.new()
		b.text = String(meta["title"])
		b.toggle_mode = true
		b.button_group = _btn_group
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_FILL
		b.set_meta("tab_id", tab_id)
		b.pressed.connect(_on_tab_pressed.bind(b))
		_left_tabs.add_child(b)
		_tab_buttons.append(b)

func _on_tab_pressed(btn: Button) -> void:
	var tab_id := String(btn.get_meta("tab_id"))
	_select_tab(tab_id)

func _select_first_tab() -> void:
	for c in _left_tabs.get_children():
		var b := c as Button
		b.button_pressed = true
		_select_tab(String(b.get_meta("tab_id")))
		_selected_tab_index = 0
		_highlight_tab(0)
		break

func _select_tab(tab_id: String) -> void:
	# Guard: don't leave Dorms if Common has people to place
	if _current_tab == "dorms" and tab_id != "dorms":
		if not _can_leave_dorms():
			_toast("Finish placing everyone from the Common Room before leaving Dorms.")
			# snap the toggle back to Dorms
			for c in _left_tabs.get_children():
				var b := c as Button
				b.button_pressed = (String(b.get_meta("tab_id")) == "dorms")
			return

	if _current_tab == tab_id:
		return
	_current_tab = tab_id
	_show_panel(tab_id)

	# Update button states and find the selected index
	var index = 0
	for c in _left_tabs.get_children():
		var b := c as Button
		b.button_pressed = (String(b.get_meta("tab_id")) == tab_id)
		if String(b.get_meta("tab_id")) == tab_id:
			_unhighlight_tab(_selected_tab_index)
			_selected_tab_index = index
			_highlight_tab(_selected_tab_index)
		index += 1

	var settings: Node = get_node_or_null("/root/aSettings")
	if settings and settings.has_method("set_value"):
		settings.call("set_value", "main_menu_last_tab", tab_id)

func _show_panel(tab_id: String) -> void:
	for child in _panel_holder.get_children():
		child.visible = false
	var panel := _get_or_create_panel(tab_id)
	if panel:
		panel.visible = true

func _get_or_create_panel(tab_id: String) -> Control:
	if _panels.has(tab_id):
		return _panels[tab_id] as Control

	if not TAB_DEFS.has(tab_id):
		push_warning("Unknown tab_id: %s" % tab_id)
		return null

	var scene_path: String = String(TAB_DEFS[tab_id]["scene"])
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_warning("Missing panel scene: %s" % scene_path)
		return null

	var inst := ps.instantiate() as Control
	_panel_holder.add_child(inst)
	_panels[tab_id] = inst
	return inst

# --- Hooks / helpers ---

func _on_common_added(_aid: String) -> void:
	_open_dorms_tab()

func _open_dorms_tab() -> void:
	_select_tab("dorms")

func _can_leave_dorms() -> bool:
	var ds := get_node_or_null("/root/aDormSystem")
	if ds == null:
		return true
	var list_v: Variant = ds.call("get_common") # merged Common + staged-to-place
	if typeof(list_v) == TYPE_PACKED_STRING_ARRAY:
		return (list_v as PackedStringArray).size() == 0
	if typeof(list_v) == TYPE_ARRAY:
		return (list_v as Array).size() == 0
	return true

func _toast(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Heads up"
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()

# --- Controller navigation functions ---

func _navigate_tabs(direction: int) -> void:
	"""Navigate through tabs with controller"""
	if _tab_buttons.is_empty():
		return

	# Unhighlight current
	_unhighlight_tab(_selected_tab_index)

	# Update index with wrap-around
	_selected_tab_index += direction
	if _selected_tab_index < 0:
		_selected_tab_index = _tab_buttons.size() - 1
	elif _selected_tab_index >= _tab_buttons.size():
		_selected_tab_index = 0

	# Highlight new selection
	_highlight_tab(_selected_tab_index)

func _confirm_tab_selection() -> void:
	"""Confirm the currently highlighted tab"""
	if _selected_tab_index >= 0 and _selected_tab_index < _tab_buttons.size():
		var button = _tab_buttons[_selected_tab_index]
		button.button_pressed = true
		_on_tab_pressed(button)

func _close_menu() -> void:
	"""Close the game menu"""
	# Check if we can leave the current tab (for Dorms)
	if _current_tab == "dorms":
		if not _can_leave_dorms():
			_toast("Finish placing everyone from the Common Room before closing the menu.")
			return

	# Hide the menu and unpause
	visible = false
	get_tree().paused = false

func _highlight_tab(index: int) -> void:
	"""Highlight a tab button"""
	if index >= 0 and index < _tab_buttons.size():
		var button = _tab_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellow tint
		button.grab_focus()

func _unhighlight_tab(index: int) -> void:
	"""Remove highlight from a tab button"""
	if index >= 0 and index < _tab_buttons.size():
		var button = _tab_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color
