extends Node
class_name PhoneHotkeys

const PHONE_MENU_SCENE := "res://scenes/ui/phone/PhoneMenu.tscn"

var _enabled : bool   = false
var _menu    : Control = null

func set_enabled(flag: bool) -> void:
	_enabled = flag
	if not _enabled:
		_close()

func _ready() -> void:
	set_process_unhandled_input(true)
	_enabled = false  # OFF by default

func _unhandled_input(e: InputEvent) -> void:
	if not _enabled: return
	if e.is_action_pressed("ui_phone"):
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if _menu and is_instance_valid(_menu) and _menu.visible:
		_close()
	else:
		_open()

func _open() -> void:
	if not ResourceLoader.exists(PHONE_MENU_SCENE): return
	if _menu == null or not is_instance_valid(_menu):
		_menu = (load(PHONE_MENU_SCENE) as PackedScene).instantiate() as Control
	get_tree().current_scene.add_child(_menu)
	_menu.visible = true
	_menu.move_to_front()

func _close() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
