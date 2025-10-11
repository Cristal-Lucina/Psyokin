extends Control
class_name SystemPanel

## Centers the menu and opens sub-menus above GameMenu (overlay or router).

const LOAD_MENU_SCENE : String = "res://scenes/ui/save/LoadMenu.tscn"
const SAVE_MENU_SCENE : String = "res://scenes/ui/save/SaveMenu.tscn"
const OPTIONS_SCENE   : String = "res://scenes/main_menu/Options.tscn"
const TITLE_SCENE     : String = "res://scenes/main_menu/Title.tscn"

@onready var _btn_load     : Button = %LoadBtn
@onready var _btn_save     : Button = %SaveBtn
@onready var _btn_settings : Button = %SettingsBtn
@onready var _btn_title    : Button = %TitleBtn

func _ready() -> void:
	# Make sure we expand to the PanelHolder’s size.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_btn_load.pressed.connect(_open_load)
	_btn_save.pressed.connect(_open_save)
	_btn_settings.pressed.connect(_open_settings)
	_btn_title.pressed.connect(_to_title)

func _open_load() -> void:
	_open_overlay(LOAD_MENU_SCENE)

func _open_save() -> void:
	_open_overlay(SAVE_MENU_SCENE)

func _open_settings() -> void:
	_open_overlay(OPTIONS_SCENE)

func _to_title() -> void:
	if has_node("/root/aSceneRouter") and aSceneRouter.has_method("goto_title"):
		aSceneRouter.goto_title()
	else:
		get_tree().change_scene_to_file(TITLE_SCENE)

# --- overlay helper ------------------------------------------------------------

func _open_overlay(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_warning("[SystemPanel] Missing scene: %s" % scene_path)
		return
	# Prefer your router if present.
	if has_node("/root/aSceneRouter") and aSceneRouter.has_method("open_popup"):
		aSceneRouter.open_popup(scene_path, get_tree().current_scene)
		return

	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var inst := ps.instantiate()

	# Add to current scene so it renders above GameMenu.
	var parent := get_tree().current_scene
	parent.add_child(inst)

	if inst is Control:
		var c := inst as Control
		c.top_level = true
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 2000
