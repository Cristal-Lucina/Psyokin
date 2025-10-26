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
	print("[SystemPanel] Save button pressed")
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
	print("[SystemPanel] Opening overlay: %s" % scene_path)

	if not ResourceLoader.exists(scene_path):
		push_error("[SystemPanel] Missing scene: %s" % scene_path)
		return

	# Prefer your router if present.
	if has_node("/root/aSceneRouter") and aSceneRouter.has_method("open_popup"):
		print("[SystemPanel] Using SceneRouter to open popup")
		var result := aSceneRouter.open_popup(scene_path, get_tree().current_scene)
		if result:
			print("[SystemPanel] SceneRouter opened popup successfully")
		else:
			push_error("[SystemPanel] SceneRouter failed to open popup")
		return

	print("[SystemPanel] Loading scene directly")
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_error("[SystemPanel] Failed to load PackedScene: %s" % scene_path)
		return

	print("[SystemPanel] Instantiating scene")
	var inst := ps.instantiate()
	if inst == null:
		push_error("[SystemPanel] Failed to instantiate scene")
		return

	# Add to current scene so it renders above GameMenu.
	var parent := get_tree().current_scene
	if parent == null:
		push_error("[SystemPanel] Current scene is null!")
		return

	print("[SystemPanel] Adding overlay to scene tree (parent: %s)" % parent.name)
	parent.add_child(inst)

	if inst is Control:
		var c := inst as Control
		c.top_level = true
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 2000
		print("[SystemPanel] Configured overlay as full-screen with z_index 2000")

	print("[SystemPanel] Overlay opened successfully!")
