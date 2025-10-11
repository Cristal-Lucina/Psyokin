extends Control

# --- Autoload paths ------------------------------------------------------------
const CALENDAR_PATH     : String = "/root/aCalendarSystem"
const STATS_PATH        : String = "/root/aStatsSystem"
const CSV_PATH          : String = "/root/aCSVLoader"
const WORLD_SPOTS_PATH  : String = "/root/aWorldSpotsSystem"

# --- Scene paths ---------------------------------------------------------------
const TRAINING_MENU_SCENE : String = "res://scenes/ui/training/TrainingMenu.tscn"
const SAVE_MENU_SCENE     : String = "res://scenes/ui/save/SaveMenu.tscn"
const GAME_MENU_SCENE     : String = "res://scenes/main_menu/GameMenu.tscn"
const PHONE_MENU_SCENE    : String = "res://scenes/ui/phone/PhoneMenu.tscn"
# Try both common locations for the cheat bar scene (only used if not already in the tree)
const CHEATBAR_SCENES     : Array[String] = [
	"res://ItemCheatBar.tscn",
	"res://scenes/dev/ItemCheatBar.tscn"
]

# --- Input actions -------------------------------------------------------------
const INPUT_MENU_ACTION  : String = "ui_menu"
const INPUT_PHONE_ACTION : String = "ui_phone"

# --- UI references -------------------------------------------------------------
@onready var date_label        : Label  = $MarginContainer/Root/DateLabel
@onready var phase_label       : Label  = $MarginContainer/Root/PhaseLabel
@onready var advance_btn       : Button = $MarginContainer/Root/HBoxContainer/AdvanceBtn
@onready var reset_btn         : Button = $MarginContainer/Root/HBoxContainer/ResetWeekBtn
@onready var load_btn          : Button = $MarginContainer/Root/HBoxContainer2/LoadItemsBtn
@onready var items_status      : Label  = $MarginContainer/Root/HBoxContainer2/ItemsStatus
@onready var open_training_btn : Button = $MarginContainer/Root/HBoxContainer3/OpenTrainingBtn
@onready var spots_status      : Label  = $MarginContainer/Root/HBoxContainer3/SpotsStatus

var open_save_btn : Button = null

# --- Cached autoload references ------------------------------------------------
var calendar : Node = null
var stats    : Node = null
var csv      : Node = null

# --- Overlay instance caches ---------------------------------------------------
var _game_menu       : Control = null
var _phone_menu      : Control = null
var _items_cheat_bar : Control = null


func _ready() -> void:
	calendar = get_node_or_null(CALENDAR_PATH)
	stats    = get_node_or_null(STATS_PATH)
	csv      = get_node_or_null(CSV_PATH)

	var wss: Node = get_node_or_null(WORLD_SPOTS_PATH)
	if wss and wss.has_method("load_spots"):
		wss.call("load_spots")

	advance_btn.pressed.connect(_on_advance_pressed)
	reset_btn.pressed.connect(_on_reset_week_pressed)
	load_btn.pressed.connect(_on_load_items_pressed)
	open_training_btn.pressed.connect(_on_open_training)

	open_save_btn = get_node_or_null("MarginContainer/Root/HBoxContainer4/OpenSaveBtn") as Button
	if open_save_btn == null:
		open_save_btn = find_child("OpenSaveBtn", true, false) as Button
	if open_save_btn and not open_save_btn.pressed.is_connected(_on_open_save):
		open_save_btn.pressed.connect(_on_open_save)

	if calendar:
		if calendar.has_signal("phase_advanced"):
			calendar.connect("phase_advanced", Callable(self, "_on_calendar_updated"))
		if calendar.has_signal("day_advanced"):
			calendar.connect("day_advanced", Callable(self, "_on_calendar_updated"))
		if calendar.has_signal("week_reset"):
			calendar.connect("week_reset", Callable(self, "_on_week_reset"))

	_refresh_ui()
	_refresh_spots_status()

	_attach_items_cheat_bar() # <- mount/resolve cheat bar

	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return

	# Quick toggle with "C"
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_toggle_cheat_bar()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(INPUT_PHONE_ACTION):
		if not _is_on_title_screen():
			_toggle_phone_menu()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(INPUT_MENU_ACTION):
		_toggle_game_menu()
		get_viewport().set_input_as_handled()
		return


# --- UI refresh helpers --------------------------------------------------------
func _refresh_ui() -> void:
	var date_text  : String = "?? / ??"
	var wday_text  : String = "?"
	var phase_text : String = "??"

	if calendar:
		if calendar.has_method("get_date_string"):
			date_text = String(calendar.call("get_date_string"))
		if calendar.has_method("get_weekday_name"):
			wday_text = String(calendar.call("get_weekday_name"))
		if calendar.has_method("get_phase_name"):
			phase_text = String(calendar.call("get_phase_name"))

	date_label.text  = "%s — %s" % [date_text, wday_text]
	phase_label.text = phase_text


func _refresh_spots_status() -> void:
	var count : int = 0
	var wss: Node = get_node_or_null(WORLD_SPOTS_PATH)
	if wss and wss.has_method("get_available_spots"):
		var spots: Array = wss.call("get_available_spots") as Array
		count = spots.size()
	spots_status.text = "Spots: %d" % count


# --- Calendar callbacks --------------------------------------------------------
func _on_calendar_updated(_arg: Variant = null) -> void:
	_refresh_ui()
	_refresh_spots_status()

func _on_week_reset() -> void:
	_refresh_ui()


# --- Buttons ------------------------------------------------------------------
func _on_advance_pressed() -> void:
	if calendar and calendar.has_method("advance_phase"):
		calendar.call("advance_phase")
	else:
		push_warning("Calendar autoload not found or advance_phase() missing.")
	_refresh_ui()

func _on_reset_week_pressed() -> void:
	if stats and stats.has_method("reset_week"):
		stats.call("reset_week")
		items_status.text = "Week reset."
	else:
		push_warning("Stats autoload not found or reset_week() missing.")

func _on_load_items_pressed() -> void:
	if csv and csv.has_method("load_csv"):
		var file_path : String = "res://data/items/items.csv"
		var index_key : String = "item_id"
		var table : Dictionary = csv.call("load_csv", file_path, index_key) as Dictionary
		if table.is_empty():
			items_status.text = "Items: (failed)"
			push_warning("CSV load failed or returned empty/invalid.")
		else:
			items_status.text = "Items: %d" % table.size()
			print("Loaded items:", table.keys())
	else:
		push_warning("CSV autoload not found or load_csv() missing.")

func _on_open_training() -> void:
	if ResourceLoader.exists(TRAINING_MENU_SCENE):
		var s_ps : PackedScene = load(TRAINING_MENU_SCENE) as PackedScene
		if s_ps:
			var s: Node = s_ps.instantiate()
			add_child(s)
	else:
		push_warning("TrainingMenu scene missing at: " + TRAINING_MENU_SCENE)

func _on_open_save() -> void:
	if ResourceLoader.exists(SAVE_MENU_SCENE):
		var ps : PackedScene = load(SAVE_MENU_SCENE) as PackedScene
		if ps:
			var menu: Node = ps.instantiate()
			add_child(menu)
	else:
		push_warning("SaveMenu scene missing at: " + SAVE_MENU_SCENE)


# --- Game Menu overlay ---------------------------------------------------------
func _toggle_game_menu() -> void:
	if _game_menu == null or not is_instance_valid(_game_menu):
		_open_game_menu()
	elif _game_menu.visible:
		_close_game_menu()
	else:
		_open_game_menu()

func _open_game_menu() -> void:
	if _game_menu == null or not is_instance_valid(_game_menu):
		if not ResourceLoader.exists(GAME_MENU_SCENE):
			push_warning("GameMenu scene missing at: " + GAME_MENU_SCENE)
			return
		var ps : PackedScene = load(GAME_MENU_SCENE) as PackedScene
		if ps == null:
			push_warning("Failed to load GameMenu: " + GAME_MENU_SCENE)
			return
		_game_menu = ps.instantiate() as Control
		_game_menu.name = "GameMenu"
		_game_menu.mouse_filter = Control.MOUSE_FILTER_STOP
		_game_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		var parent: Node = get_node_or_null("Overlays")
		if parent == null:
			parent = self
		parent.add_child(_game_menu)

	_game_menu.visible = true
	_game_menu.move_to_front()

func _close_game_menu() -> void:
	if _game_menu and is_instance_valid(_game_menu):
		_game_menu.visible = false


# --- Phone Menu overlay --------------------------------------------------------
func _toggle_phone_menu() -> void:
	if _phone_menu == null or not is_instance_valid(_phone_menu):
		_open_phone_menu()
	elif _phone_menu.visible:
		_close_phone_menu()
	else:
		_open_phone_menu()

func _open_phone_menu() -> void:
	if _phone_menu == null or not is_instance_valid(_phone_menu):
		if not ResourceLoader.exists(PHONE_MENU_SCENE):
			push_warning("PhoneMenu scene missing at: " + PHONE_MENU_SCENE)
			return
		var ps : PackedScene = load(PHONE_MENU_SCENE) as PackedScene
		if ps == null:
			push_warning("Failed to load PhoneMenu: " + PHONE_MENU_SCENE)
			return
		_phone_menu = ps.instantiate() as Control
		_phone_menu.name = "PhoneMenu"
		_phone_menu.mouse_filter = Control.MOUSE_FILTER_STOP
		_phone_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		_phone_menu.top_level = true
		_phone_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		_phone_menu.add_to_group("phone_menu")

		var parent: Node = get_node_or_null("Overlays")
		if parent == null:
			parent = self
		parent.add_child(_phone_menu)

	_phone_menu.visible = true
	_phone_menu.move_to_front()

func _close_phone_menu() -> void:
	if _phone_menu and is_instance_valid(_phone_menu):
		_phone_menu.visible = false


# --- Helpers -------------------------------------------------------------------
func _is_on_title_screen() -> bool:
	var root: Node = get_tree().current_scene
	if root == null:
		return false
	return root.name.to_lower().find("title") >= 0


# --- Cheat bar mount / cleanup -------------------------------------------------
func _attach_items_cheat_bar() -> void:
	# 1) Prefer an existing node already placed in the scene tree
	var existing: Control = find_child("ItemsCheatBar", true, false) as Control
	if existing and is_instance_valid(existing):
		_items_cheat_bar = existing
		_items_cheat_bar.visible = true
		_items_cheat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return

	# 2) Otherwise, try to instantiate a PackedScene (either path)
	var host : Node = get_node_or_null("MarginContainer/Root")
	if host == null:
		host = self

	for p in CHEATBAR_SCENES:
		if ResourceLoader.exists(p):
			var ps : PackedScene = load(p) as PackedScene
			if ps:
				_items_cheat_bar = ps.instantiate() as Control
				_items_cheat_bar.name = "ItemsCheatBar"
				_items_cheat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				host.add_child(_items_cheat_bar)
				_items_cheat_bar.move_to_front()
				return

	push_warning("ItemsCheatBar not found in scene and no ItemCheatBar.tscn located.")

func _toggle_cheat_bar() -> void:
	if _items_cheat_bar == null or not is_instance_valid(_items_cheat_bar):
		_attach_items_cheat_bar()
		return
	_items_cheat_bar.visible = not _items_cheat_bar.visible
