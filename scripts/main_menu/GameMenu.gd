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

# --- Panel state ---
var _is_fullscreen: bool = false  # true when a non-Status panel is open full screen

# --- Dorm hooks ---
var _ds: Node = null

func _ready() -> void:
	_btn_group = ButtonGroup.new()

	# Hide the LeftTabs since tab buttons are now in StatusPanel
	if _left_tabs:
		_left_tabs.visible = false

	# Always start with Status panel
	_select_tab("status")

	# Connect to StatusPanel's tab_selected signal
	call_deferred("_connect_status_panel_signal")

	# Hook: auto-open Dorms tab when someone is added to Common (menu already open)
	_ds = get_node_or_null("/root/aDormSystem")
	if _ds and _ds.has_signal("common_added") and not _ds.is_connected("common_added", Callable(self, "_on_common_added")):
		_ds.connect("common_added", Callable(self, "_on_common_added"))

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# If in fullscreen mode, B returns to Status tab
	if _is_fullscreen:
		if event.is_action_pressed(aInputManager.ACTION_BACK):
			# Check if we can leave current panel (for Dorms validation)
			if _current_tab == "dorms" and not _can_leave_dorms():
				_toast("Finish placing everyone from the Common Room before leaving Dorms.")
				get_viewport().set_input_as_handled()
				return

			_exit_fullscreen()
			get_viewport().set_input_as_handled()
		# Let panel handle all other input
		return

	# When viewing Status panel, B closes the menu
	if event.is_action_pressed(aInputManager.ACTION_BACK):
		_close_menu()
		get_viewport().set_input_as_handled()

func _connect_status_panel_signal() -> void:
	"""Connect to StatusPanel's tab_selected signal"""
	var status_panel = _panels.get("status")
	if status_panel and status_panel.has_signal("tab_selected"):
		if not status_panel.is_connected("tab_selected", Callable(self, "_on_status_panel_tab_selected")):
			status_panel.connect("tab_selected", Callable(self, "_on_status_panel_tab_selected"))

func _on_status_panel_tab_selected(tab_id: String) -> void:
	"""Handle tab selection from StatusPanel"""
	print("[GameMenu] Tab selected from StatusPanel: ", tab_id)
	_enter_fullscreen(tab_id)

func _select_tab(tab_id: String) -> void:
	# Guard: don't leave Dorms if Common has people to place
	if _current_tab == "dorms" and tab_id != "dorms":
		if not _can_leave_dorms():
			_toast("Finish placing everyone from the Common Room before leaving Dorms.")
			return

	if _current_tab == tab_id:
		return
	_current_tab = tab_id
	_show_panel(tab_id)

	var settings: Node = get_node_or_null("/root/aSettings")
	if settings and settings.has_method("set_value"):
		settings.call("set_value", "main_menu_last_tab", tab_id)

func _show_panel(tab_id: String) -> void:
	# If switching to a non-Status panel, enter fullscreen mode
	if tab_id != "status":
		_enter_fullscreen(tab_id)
		return

	# Showing Status panel - normal view with integrated tab buttons
	_is_fullscreen = false

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

func _enter_fullscreen(tab_id: String) -> void:
	"""Enter fullscreen mode for a panel"""
	_is_fullscreen = true
	_current_tab = tab_id

	# Show the panel full screen
	for child in _panel_holder.get_children():
		child.visible = false

	var panel := _get_or_create_panel(tab_id)
	if panel:
		panel.visible = true
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Give panel focus if it has the method
		if panel.has_method("panel_gained_focus"):
			panel.call("panel_gained_focus")

func _exit_fullscreen() -> void:
	"""Exit fullscreen mode - return to Status tab with sidebar"""
	_is_fullscreen = false

	# Call panel_lost_focus on the current panel
	var panel = _panels.get(_current_tab)
	if panel and panel.has_method("panel_lost_focus"):
		panel.call("panel_lost_focus")

	# Return to Status tab
	_select_tab("status")
