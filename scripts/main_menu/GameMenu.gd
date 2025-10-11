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

func _build_tabs() -> void:
	for child in _left_tabs.get_children():
		child.queue_free()
	await get_tree().process_frame

	var ids: PackedStringArray = TAB_ORDER
	if ids.is_empty():
		ids = TAB_DEFS.keys()

	for tab_id in ids:
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

func _on_tab_pressed(btn: Button) -> void:
	var tab_id := String(btn.get_meta("tab_id"))
	_select_tab(tab_id)

func _select_first_tab() -> void:
	for c in _left_tabs.get_children():
		var b := c as Button
		b.button_pressed = true
		_select_tab(String(b.get_meta("tab_id")))
		break

func _select_tab(tab_id: String) -> void:
	if _current_tab == tab_id:
		return
	_current_tab = tab_id
	_show_panel(tab_id)

	for c in _left_tabs.get_children():
		var b := c as Button
		b.button_pressed = (String(b.get_meta("tab_id")) == tab_id)

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
